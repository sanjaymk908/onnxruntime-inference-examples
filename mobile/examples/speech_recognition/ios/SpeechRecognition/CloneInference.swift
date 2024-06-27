//
//  CloneInference.swift
//  SpeechRecognition
//
//  Created by Sanjay Krishnamurthy on 6/27/24.
//


import Foundation

class CloneInference: Evaluator {
  typealias InputType = [Float]
    
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession

  enum CloneInferenceError: Error {
    case Error(_ message: String)
  }

    required init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "8KHz_logreg_96Percent-model", ofType: "ort") else {
      throw CloneInferenceError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
  }
    
  private func createORTValueFromEmbeddings(_ embeddings: [Float]) throws -> ORTValue {
    let expectedLength = 192
    guard embeddings.count == expectedLength else {
        throw NSError(domain: "AudioProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Embedding length mismatch. Expected \(expectedLength), but got \(embeddings.count)."])
    }

    // Create the input shape
    let inputShape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: expectedLength)]

    // Convert the Float array to NSMutableData
    let dataSize = embeddings.count * MemoryLayout<Float>.stride
    let mutableData = NSMutableData(bytes: embeddings, length: dataSize)

    // Create the ORTValue tensor
    let inputTensor = try ORTValue(
        tensorData: mutableData,
        elementType: ORTTensorElementDataType.float,
        shape: inputShape
    )

    return inputTensor
  }

  func evaluate(inputData: [Float]) -> Result<String, Error> {
        return Result<String, Error> { () -> String in
            let startTime = DispatchTime.now()
            // Step 1: Create ORTValue for input data
            let inputTensor = try createORTValueFromEmbeddings(inputData)

            // Step 2: Prepare input and run session
            let inputs: [String: ORTValue] = [
                "float_input": inputTensor,
            ]
            let outputs = try ortSession.run(
                withInputs: inputs,
                outputNames: ["output_probability", "output_label"],
                runOptions: nil
            )

            let endTime = DispatchTime.now()
            print("ORT session run time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")

            guard let _ = outputs["output_probability"], let label = outputs["output_label"] else {
                throw CloneInferenceError.Error("Failed to get model output.")
            }

            let labelData = try label.tensorData() as Data
            let result = labelData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int64 in
                let int64Buffer = buffer.bindMemory(to: Int64.self)
                print("label size: \(int64Buffer.count)")
                let int64Array = Array(int64Buffer)
                let labelValue = int64Array[0]
                return labelValue
            }

            if result == 0 {
                return "Audio is real"
            } else {
                return "Audio is cloned"
            }
        }
  }

}

