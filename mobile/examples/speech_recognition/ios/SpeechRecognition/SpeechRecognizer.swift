// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import Foundation

// these labels correspond to the model's output values
// the labels and postprocessing logic were copied and adapted from:
// https://github.com/pytorch/ios-demo-app/blob/f2b9aa196821c136d3299b99c5dd592de1fa1776/SpeechRecognition/create_wav2vec2.py#L10
private let kLabels = [
  "<s>", "<pad>", "</s>", "<unk>", "|", "E", "T", "A", "O", "N", "I", "H", "S", "R", "D", "L", "U", "M", "W", "C", "F",
  "G", "Y", "P", "B", "V", "K", "'", "X", "J", "Q", "Z",
]

class SpeechRecognizer {
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession
  private let matcher: SimilarityMatcher

  enum SpeechRecognizerError: Error {
    case Error(_ message: String)
  }

  init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "titanet_small", ofType: "ort") else {
      throw SpeechRecognizerError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
    matcher = SimilarityMatcher()
  }

  private func postprocess(modelOutput: UnsafeBufferPointer<Float>) -> String {
    func maxIndex<S>(_ values: S) -> Int? where S: Sequence, S.Element == Float {
      var max: (idx: Int, value: Float)?
      for (idx, value) in values.enumerated() {
        if max == nil || value > max!.value {
          max = (idx, value)
        }
      }
      return max?.idx
    }

    func labelIndexToOutput(_ index: Int) -> String {
      if index == 4 {
        return " "
      } else if index > 4 && index < kLabels.count {
        return kLabels[index]
      }
      return ""
    }

    precondition(modelOutput.count % kLabels.count == 0)
    let n = modelOutput.count / kLabels.count
    var resultLabelIndices: [Int] = []

    for i in 0..<n {
      let labelValues = modelOutput[i * kLabels.count..<(i + 1) * kLabels.count]
      if let labelIndex = maxIndex(labelValues) {
        // append without consecutive duplicates
        if labelIndex != resultLabelIndices.last {
          resultLabelIndices.append(labelIndex)
        }
      }
    }

    return resultLabelIndices.map(labelIndexToOutput).joined()
  }
    
    func createORTValueFromAudio(inputData: Data, sampleRate: Int, expectedLength: Int, group: Int) throws -> ORTValue {
        // Ensure the input data is in Float32 format
        let floatArray: [Float] = inputData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [Float] in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }

        // Check if the length is correct and pad/trim as necessary
        let sequenceLength = expectedLength
        // Make sure the input length is compatible with the group's requirement
        guard floatArray.count == sequenceLength * group else {
            throw NSError(domain: "AudioProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio length mismatch. Expected \(sequenceLength * group), but got \(floatArray.count)."])
        }

        // Create the input shape
        let inputShape: [NSNumber] = [1, NSNumber(value: group), NSNumber(value: sequenceLength)]

        // Convert the Float array to NSMutableData
        let dataSize = floatArray.count * MemoryLayout<Float>.stride
        let mutableData = NSMutableData(bytes: floatArray, length: dataSize)

        // Create the ORTValue tensor
        let inputTensor = try ORTValue(
            tensorData: mutableData,
            elementType: ORTTensorElementDataType.float,
            shape: inputShape
        )

        return inputTensor
    }

  func evaluate(inputData: Data) -> Result<String, Error> {
        return Result<String, Error> { () -> String in
            let startTime = DispatchTime.now()
            // Step 1: Create ORTValue for input data
            let expectedLength = 1200 // 1200 * 80 == 96000 samples of input
            let group = 80 // Number of groups for convolution
            let inputTensor = try createORTValueFromAudio(inputData: inputData, sampleRate: 16000, expectedLength: expectedLength, group: group)

            // Step 2: Create ORTValue for audio length
            let lengthShape: [NSNumber] = [1]
            let audioLength = inputData.count
            let audioLengthData = NSMutableData(bytes: withUnsafeBytes(of: audioLength) { ptr in
                return ptr.baseAddress!
            }, length: MemoryLayout<Int64>.size)
            let lengthValue = try ORTValue(tensorData: audioLengthData, elementType: ORTTensorElementDataType.int64, shape: lengthShape)

            // Step 3: Prepare inputs and run session
            let inputs: [String: ORTValue] = [
                "audio_signal": inputTensor,
                "length": lengthValue,
            ]
            let outputs = try ortSession.run(
                withInputs: inputs,
                outputNames: ["logits", "embs"],
                runOptions: nil
            )

            let endTime = DispatchTime.now()
            print("ORT session run time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")

            guard let _ = outputs["logits"], let embs = outputs["embs"] else {
                throw SpeechRecognizerError.Error("Failed to get model output.")
            }

            let embsData = try embs.tensorData() as Data
            var isBaselineVec = true
            let result = embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> String in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                let floatArray = Array(floatBuffer)
                if !matcher.doesBaselineVecExist() {
                    matcher.storeBaselineVec(floatArray)
                    return ""
                } else {
                    isBaselineVec = false
                    matcher.storeTestVec(floatArray)
                    let isMatch = matcher.cosineMatch()
                    matcher.clearAllInputs()
                    let matchResult = isMatch ? "Did match baseline" : "Did not match baseline"
                    return "Used current recording for Voice Match: " + matchResult
                }
            }

            if isBaselineVec {
                return "Stored Baseline audio for Voice Matching"
            } else {
                return result
            }
        }
  }

  // Placeholder function to convert raw audio data to float array
  func convertToFloatArray(audioData: Data) throws -> [Float] {
    // Implement the conversion logic or use a library
    // Return the processed data
    return []
  }

}
