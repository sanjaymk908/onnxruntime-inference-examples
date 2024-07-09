// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import Foundation

class SpeechRecognizer: Evaluator {
  typealias InputType = Data
    
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession
  private let cloneDetector: CloneInference

  enum SpeechRecognizerError: Error {
    case Error(_ message: String)
  }

  required init() throws {
    let startTime = DispatchTime.now()
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "titanet_large", ofType: "onnx") else {
      throw SpeechRecognizerError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
    cloneDetector = try CloneInference()
    let endTime = DispatchTime.now()
    print("Loading ML Models time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")
  }
    
  private func createORTValueFromAudio(inputData: Data, sampleRate: Int, expectedLength: Int, group: Int) throws -> ORTValue {
    // Ensure the input data is in Float32 format
    let floatArray: [Double] = inputData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [Double] in
        let floatBuffer = buffer.bindMemory(to: Double.self)
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
            let expectedLength = 1000 // 1000 * 80 == 80000 samples of input
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
            var clonedTestResult: Result<String, any Error> = .success("Default Value")
            let result = try embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> String in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                let floatArray = Array(floatBuffer)
                let doubleArray = floatArray.map { Double($0) }
                clonedTestResult = cloneDetector.evaluate(inputData: doubleArray)
                return try clonedTestResult.get()
            }
            return result
        }
  }

}
