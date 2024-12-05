//
//  CloneInference.swift
//
//  Created by Sanjay Krishnamurthy on 6/27/24.
//


import Foundation

class CloneInference {
  typealias InputType = [Double]
    
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession
  private let THRESHOLD: Double = 0.7 // Base threshold
  private let CONFIDENCE_MARGIN:Double = 0.4 // Parameterized difference

  enum CloneInferenceError: Error {
    case Error(_ message: String)
  }

    required init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "xgboost_liveness_quant_enh", ofType: "onnx") else {
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
                "input": inputTensor,
            ]
            let outputs = try ortSession.run(
                withInputs: inputs,
                outputNames: ["probabilities", "label"],
                runOptions: nil
            )

            let endTime = DispatchTime.now()
            print("ORT session run time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")

            guard let probs = outputs["probabilities"], let labels = outputs["label"] else {
                throw CloneInferenceError.Error("Failed to get model output.")
            }
            
            let labelsData = try labels.tensorData() as Data
            let labelValue = labelsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int64 in
                let int64Buffer = buffer.bindMemory(to: Int64.self)
                return int64Buffer[0]
            }
            
            let probsData = try probs.tensorData() as Data
            let probValues: [Float32] = probsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let float32Buffer = buffer.bindMemory(to: Float32.self)
                return Array(float32Buffer)
            }
            print("Probabilities: \(probValues)")
            let realProb = ceil(Double(probValues[0]) * 100) / 100
            let fakeProb = ceil(Double(probValues[1]) * 100) / 100
            let probDifference = abs(realProb - fakeProb)

            if realProb > THRESHOLD || fakeProb > THRESHOLD {
                // There's a large difference, so we can be more confident in the decision
                if realProb > fakeProb {
                    let message = "Pic is real. \nProbs: " + String(realProb) + " " + String(fakeProb)
                    return message
                } else {
                    let message = "Pic is printout/fake. \nProbs: " + String(realProb) + " " + String(fakeProb)
                    return message
                }
            } else if probDifference >= CONFIDENCE_MARGIN {
                // Difference is large enough
                if realProb > fakeProb {
                    let message = "Pic is real. \nProbs: " + String(realProb) + " " + String(fakeProb)
                    return message
                } else {
                    let message = "Pic is printout/fake. \nProbs: " + String(realProb) + " " + String(fakeProb)
                    return message
                }
            } else {
                // difference is not large enough to justify decision
                let message = "Inconclusive. \nProbs: " + String(realProb) + " " + String(fakeProb)
                return message
            }
        }
  }

}

