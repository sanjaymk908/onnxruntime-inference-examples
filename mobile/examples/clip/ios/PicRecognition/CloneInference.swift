//
//  CloneInference.swift
//  SpeechRecognition
//
//  Created by Sanjay Krishnamurthy on 6/27/24.
//


import Foundation

class CloneInference {
  typealias InputType = [Double]
    
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession

  enum CloneInferenceError: Error {
    case Error(_ message: String)
  }

    required init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "140kPlusCelebA-model_no_zipmap", ofType: "onnx") else {
      throw CloneInferenceError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
  }
    
  private func createORTValueFromEmbeddings(_ embeddings: [Double]) throws -> ORTValue {
    let expectedLength = 512
    guard embeddings.count == expectedLength else {
        throw NSError(domain: "PicProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Embedding length mismatch. Expected \(expectedLength), but got \(embeddings.count)."])
    }

    // Create the input shape
    let inputShape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: expectedLength)]

    // Convert the Double array to NSMutableData
    let dataSize = embeddings.count * MemoryLayout<Double>.stride
    let mutableData = NSMutableData(bytes: embeddings, length: dataSize)

    // Create the ORTValue tensor
    let inputTensor = try ORTValue(
        tensorData: mutableData,
        elementType: ORTTensorElementDataType.float,
        shape: inputShape
    )

    return inputTensor
  }

  func evaluate(inputData: [Double]) -> Result<String, Error> {
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

            guard let _ = outputs["output_probability"], let labels = outputs["output_label"] else {
                throw CloneInferenceError.Error("Failed to get model output.")
            }
            
            let labelsData = try labels.tensorData() as Data
            let labelValue = labelsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int64 in
                let int64Buffer = buffer.bindMemory(to: Int64.self)
                return int64Buffer[0]
            }

            if labelValue == 0 {
                return "Pic is Real"
            } else {
                return "Pic is Fake"
            }
        }
  }

}

