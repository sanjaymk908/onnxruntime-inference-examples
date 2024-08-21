//
//  AudioCloneInference.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/21/24.
//


import Foundation

class AudioCloneInference: Evaluator {
  typealias InputType = [Double]
    
  private let ortEnv: ORTEnv
  private let ortSession: ORTSession

  enum AudioCloneInferenceError: Error {
    case Error(_ message: String)
  }

    required init() throws {
    ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
    guard let modelPath = Bundle.main.path(forResource: "8KHz_logreg_96Percent-model", ofType: "ort") else {
      throw AudioCloneInferenceError.Error("Failed to find model file.")
    }
    ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
  }
    
  private func createORTValueFromEmbeddings(_ embeddings: [Double]) throws -> ORTValue {
    let rearrangedData = rearrangeColumns(embeddings)
    let expectedLength = 192
    guard rearrangedData.count == expectedLength else {
        throw NSError(domain: "AudioProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Embedding length mismatch. Expected \(expectedLength), but got \(rearrangedData.count)."])
    }

    // Create the input shape
    let inputShape: [NSNumber] = [NSNumber(value: 1), NSNumber(value: expectedLength)]

    // Convert the Double array to NSMutableData
    let dataSize = rearrangedData.count * MemoryLayout<Double>.stride
    let mutableData = NSMutableData(bytes: rearrangedData, length: dataSize)

    // Create the ORTValue tensor
    let inputTensor = try ORTValue(
        tensorData: mutableData,
        elementType: ORTTensorElementDataType.float,
        shape: inputShape
    )

    return inputTensor
  }
    
  func rearrangeColumns(_ embedding: [Double]) -> [Double] {
    // Use below for 8KHz_logreg_96Percent-model.ort
    let orderStr = "feature119,feature9,feature17,feature72,feature90,feature126,feature141,feature70,feature69,feature78,feature148,feature160,feature156,feature76,feature110,feature123,feature145,feature175,feature93,feature166,feature11,feature101,feature51,feature189,feature138,feature32,feature178,feature26,feature121,feature144,feature58,feature1,feature187,feature149,feature113,feature177,feature54,feature182,feature59,feature84,feature163,feature14,feature16,feature55,feature21,feature111,feature60,feature33,feature89,feature151,feature68,feature143,feature85,feature28,feature185,feature181,feature128,feature154,feature139,feature183,feature10,feature74,feature40,feature23,feature45,feature131,feature67,feature12,feature36,feature190,feature118,feature35,feature50,feature31,feature174,feature153,feature95,feature169,feature99,feature77,feature122,feature106,feature43,feature172,feature157,feature92,feature107,feature6,feature63,feature3,feature38,feature8,feature97,feature147,feature100,feature108,feature112,feature27,feature44,feature37,feature22,feature115,feature66,feature7,feature53,feature129,feature186,feature80,feature120,feature134,feature96,feature109,feature164,feature159,feature0,feature103,feature65,feature34,feature82,feature15,feature83,feature150,feature171,feature24,feature188,feature87,feature88,feature142,feature191,feature73,feature79,feature91,feature165,feature61,feature136,feature130,feature168,feature173,feature94,feature42,feature19,feature105,feature75,feature114,feature155,feature62,feature117,feature176,feature98,feature57,feature47,feature127,feature48,feature125,feature179,feature133,feature162,feature158,feature29,feature167,feature5,feature2,feature132,feature102,feature180,feature41,feature104,feature39,feature49,feature56,feature146,feature30,feature140,feature86,feature25,feature4,feature13,feature18,feature124,feature20,feature46,feature71,feature137,feature116,feature152,feature52,feature184,feature161,feature170,feature135,feature81,feature64"
        
    let features = orderStr.components(separatedBy: ",")
    let order = features.map { Int($0.replacingOccurrences(of: "feature", with: "")) ?? 0 }
    var outputRow : [Double] = []
    for col in order {
        outputRow.append(embedding[col])
    }
    return outputRow
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
                throw AudioCloneInferenceError.Error("Failed to get model output.")
            }
            
            let labelsData = try labels.tensorData() as Data
            let labelValue = labelsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int64 in
                let int64Buffer = buffer.bindMemory(to: Int64.self)
                return int64Buffer[0]
            }

            if labelValue == 0 {
                return "Audio is real"
            } else {
                return "Audio is cloned"
            }
        }
  }

}


