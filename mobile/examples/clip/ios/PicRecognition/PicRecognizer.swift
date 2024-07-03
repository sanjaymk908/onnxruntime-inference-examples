//
//  PicRecognizer.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import Foundation
import UIKit
import AVFoundation
import CoreVideo

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
        case failedToCreatePixelBuffer
    }

    required init() throws {
        let startTime = DispatchTime.now()
        ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
        guard let modelPath = Bundle.main.path(forResource: "clip_image_encoder.quant", ofType: "onnx") else {
            throw PicRecognizerError.failedToLoadModel
        }
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setGraphOptimizationLevel(.basic)
        try sessionOptions.setIntraOpNumThreads(1)
        ortSession = try ORTSession(env: ortEnv, modelPath: modelPath, sessionOptions: sessionOptions)
        cloneDetector = try CloneInference()
        let endTime = DispatchTime.now()
        print("Loading ML Models time: \(Float(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1.0e6) ms")
    }

    func evaluate(inputData: Data) -> Result<String, Error> {
        do {
            let inputTensor = try createInputTensor(imageData: inputData)
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
    
    private func convertImageDataToPixelBuffer(imageData: Data) -> CVPixelBuffer? {
        // 1. Create a CIImage from the image data
        guard let ciImage = CIImage(data: imageData) else {
          print("Error creating CIImage from image data")
          return nil
        }
        
        // 2. Define desired output pixel format (replace if needed)
        var pixelBuffer: CVPixelBuffer?
        let width: Int = 224
        let height: Int = 224

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        if status == kCVReturnSuccess, let pixelBuffer = pixelBuffer {
            // 3. Convert CIImage to the CVPixelBuffer
            let context = CIContext(options: nil)
            context.render(ciImage, to: pixelBuffer)
                    
            // 4. Reshape the pixelBuffer to match the expected input shape
            let bufferSize = 1 * 3 * 224 * 224 * MemoryLayout<Float>.size
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
                    
            if let pointer = CVPixelBufferGetBaseAddress(pixelBuffer) {
                var floatArray: [Float] = .init(repeating: 0.0, count: bufferSize / MemoryLayout<Float>.size)
                for channel in 0..<3 {
                    for row in 0..<224 {
                        for col in 0..<224 {
                            let index = channel * (224 * 224) + row * 224 + col
                            let pixelIndex = (row * 224 + col) * 4 + channel
                            floatArray[index] = (pointer + pixelIndex).assumingMemoryBound(to: Float.self).pointee
                        }
                    }
                }
                // 5. Update the CVPixelBuffer with the floatArray
                for channel in 0..<3 {
                    for row in 0..<224 {
                        for col in 0..<224 {
                            let index = channel * (224 * 224) + row * 224 + col
                            let pixelIndex = (row * 224 + col) * 4 + channel
                            (pointer + pixelIndex).assumingMemoryBound(to: Float.self).pointee = floatArray[index]
                        }
                    }
                }
            } else {
                print("Failed to get base address of pixelBuffer")
                return nil
            }
            return pixelBuffer
        } else {
            return nil
        }
    }
    
    private func createInputTensor(imageData: Data) throws -> ORTValue {
      // 1. Convert image data to a CVPixelBuffer
      guard let pixelBuffer = convertImageDataToPixelBuffer(imageData: imageData) else {
          throw PicRecognizerError.failedToCreatePixelBuffer
      }
      
      // 2. Get pixel data from the buffer
      CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
      let pointer = CVPixelBufferGetBaseAddress(pixelBuffer)
      let bufferSize = 1 * 3 * 224 * 224 * MemoryLayout<Float>.size // CVPixelBufferGetDataSize(pixelBuffer)
      
      // 3. Assuming pixelBuffer data layout matches model's channel order
      var pixelValues = [Float](repeating: 0.0, count: bufferSize / 4) // 4 bytes per float
      memcpy(&pixelValues, pointer, bufferSize)
      
      // 4. Reshape pixel data to match CLIP ViT-B/32 input shape (adjust if needed)
      let clipInputShape = [1, 3, 224, 224] // Batch size 1, 3 channels, 224x224 image
      var floatArray: [Float] = []
      for channel in 0..<clipInputShape[1] { // Iterate over expected channels
        for row in 0..<clipInputShape[2] {
          for col in 0..<clipInputShape[3] {
            let index = channel * (clipInputShape[2] * clipInputShape[3]) + row * clipInputShape[3] + col
            floatArray.append(pixelValues[index])
          }
        }
      }
      
      // 5. Create OrtValue for the CLIP model
      let mutableData = NSMutableData(bytes: floatArray, length: floatArray.count * MemoryLayout<Float>.stride)
      let inputShape: [NSNumber] = [1, 3, 224, 224]
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
