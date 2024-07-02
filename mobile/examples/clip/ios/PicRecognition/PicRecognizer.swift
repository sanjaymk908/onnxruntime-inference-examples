//
//  PicRecognizer.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import Foundation

class PicRecognizer: Evaluator {
    typealias InputType = Data
    typealias OutputType = String

    private let ortEnv: ORTEnv
    private let ortSession: ORTSession
    private let inputName = "pixel_values"
    private let outputName = "image_embeds"
    private let cloneDetector: CloneInference

    enum PicRecognizerError: Error {
        case failedToLoadModel
        case failedToCreateInputTensor
        case failedToRunModel
    }

    required init() throws {
        let startTime = DispatchTime.now()
        ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
        guard let modelPath = Bundle.main.path(forResource: "clip_image_encoder.quant", ofType: "onnx") else {
            throw PicRecognizerError.failedToLoadModel
        }
        ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: nil)
        cloneDetector = try CloneInference()
        let endTime = DispatchTime.now()
        print("Loading ML Models time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")
    }

    func evaluate(inputData: Data) -> Result<String, Error> {
        do {
            let inputTensor = try createInputTensor(from: inputData)
            let outputs = try runModel(with: [inputName: inputTensor])
            guard let imageEmbeds = outputs[outputName] else {
                throw PicRecognizerError.failedToRunModel
            }

            let embsData = try imageEmbeds.tensorData() as Data
            var clonedTestResult: Result<String, any Error> = .success("Default Value")
            let result = embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Result<String, any Error> in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                let floatArray = Array(floatBuffer)
                let doubleArray = floatArray.map { Double($0) }
                clonedTestResult = cloneDetector.evaluate(inputData: doubleArray)
                return clonedTestResult
            }
            return result
        } catch {
            return .failure(error)
        }
    }

    private func createInputTensor(from data: Data) throws -> ORTValue {
        let inputShape: [NSNumber] = [1, 3, 224, 224]
        let floatArray = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [Float] in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }

        let mutableData = NSMutableData(bytes: floatArray, length: floatArray.count * MemoryLayout<Float>.stride)
        return try ORTValue(
            tensorData: mutableData,
            elementType: .float,
            shape: inputShape
        )
    }

    private func runModel(with inputs: [String: ORTValue]) throws -> [String: ORTValue] {
        let startTime = DispatchTime.now()
        let outputs = try ortSession.run(
            withInputs: inputs,
            outputNames: [outputName],
            runOptions: nil
        )
        let endTime = DispatchTime.now()
        print("ORT session run time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")
        return outputs
    }
}
