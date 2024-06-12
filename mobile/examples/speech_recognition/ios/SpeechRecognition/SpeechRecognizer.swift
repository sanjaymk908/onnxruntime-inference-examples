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

  enum SpeechRecognizerError: Error {
    case Error(_ message: String)
  }

  init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "titanet_small", ofType: "ort") else {
      throw SpeechRecognizerError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
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

  func evaluate(inputData: Data) -> Result<String, Error> {
      return Result<String, Error> { () -> String in
          let inputDataCount = inputData.count
          let feature_dim = 1  // This should be your expected feature dimension per time step
          let time_steps = 80 // was inputDataCount / MemoryLayout<Float>.stride

          // The batch size can be set to 1 if you're running a single sequence inference
          let inputShape: [NSNumber] = [1, 
                                        NSNumber(value: time_steps),
                                        NSNumber(value: feature_dim)]

          let input = try ORTValue(
              tensorData: NSMutableData(data: inputData),
              elementType: ORTTensorElementDataType.float,
              shape: inputShape
          )
          
          let startTime = DispatchTime.now()
          
          // Update input and output names based on your model inspection
          let lengthShape: [NSNumber] = [1]  // Shape definition for length tensor
          let int64Value = inputData.count
          let lengthData = NSMutableData(bytes: withUnsafeBytes(of: int64Value) { ptr in
              ptr.baseAddress! // Force unwrapping here (be cautious)
              // Use ptr to access the byte representation of int64Value
          }, length: MemoryLayout<Int64>.size)
          let lengthValue = try ORTValue(tensorData: lengthData, elementType: ORTTensorElementDataType.int64, shape: lengthShape)
          let inputs: [String: ORTValue] = [
            "audio_signal": input,
            "length": lengthValue,
          ]
          let outputs = try ortSession.run(
            withInputs: inputs,
            outputNames: ["logits", "embs"],
            runOptions: nil
          )
          
          let endTime = DispatchTime.now()
          print("ORT session run time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")
          
          guard let logits = outputs["logits"], let embs = outputs["embs"] else {
              throw SpeechRecognizerError.Error("Failed to get model output.")
          }
          
          let logitsData = try logits.tensorData() as Data
          let result = logitsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> String in
              let floatBuffer = buffer.bindMemory(to: Float.self)
              return postprocess(modelOutput: floatBuffer)
          }
          
          print("result: '\(result)'")
          return result
      }
  }
}
