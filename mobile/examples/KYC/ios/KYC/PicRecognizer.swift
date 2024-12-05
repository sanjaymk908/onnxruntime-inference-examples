//
//  PicRecognizer.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UIKit

class PicRecognizer {
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
        case invalidArraySizes
        case invalidColumnNumbers
        case failedToNormalize
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

    func evaluate(bitmap: CIImage) -> Result<(String, [Double]), Error> {
        do {
            guard isRGBImage(bitmap) else {
                throw PicRecognizerError.failedToNormalize // Or define a new error case
            }
            guard let normalizedBitmap = normalizeCIImage(inputImage: bitmap) else {
                throw PicRecognizerError.failedToNormalize
            }
            let inputTensor = try createInputTensor(bitmap: normalizedBitmap)
            let outputs = try runModel(with: [inputName: inputTensor])
            guard let imageEmbeds = outputs[outputName] else {
                throw PicRecognizerError.failedToRunModel
            }

            let embsData = try imageEmbeds.tensorData() as Data
            let result = try embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Result<(String, [Double]), Error> in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                
                // Convert floatBuffer to an array of Floats, rearrange, and then convert to Doubles
                let floatArray = Array(floatBuffer)
                let floatArrayRearranged: [Float] = try rearrangeArray(floatArray)
                let doubleArray = floatArrayRearranged.map { Double($0) }
                
                // Evaluate using cloneDetector and handle the result
                let clonedTestResult = cloneDetector.evaluate(inputData: doubleArray)
                switch clonedTestResult {
                case .success(let cloneResult):
                    return .success((cloneResult, doubleArray))
                case .failure(let error):
                    return .failure(error)
                }
            }
            
            return result
        } catch {
            return .failure(error)
        }
    }
    
    func getEmbeddings(bitmap: CIImage) -> Result<[Double], Error> {
        do {
            let inputTensor = try createInputTensor(bitmap: bitmap)
            let outputs = try runModel(with: [inputName: inputTensor])
            guard let imageEmbeds = outputs[outputName] else {
                throw PicRecognizerError.failedToRunModel
            }

            let embsData = try imageEmbeds.tensorData() as Data
            let result = try embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Result<[Double], Error> in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                
                // Convert floatBuffer to an array of Floats, rearrange, and then convert to Doubles
                let floatArray = Array(floatBuffer)
                let floatArrayRearranged: [Float] = try rearrangeArray(floatArray)
                let doubleArray = floatArrayRearranged.map { Double($0) }
                return .success(doubleArray)
            }
            
            return result
        } catch {
            return .failure(error)
        }
    }

    private func bitmapToFloat(bitmap: CIImage) -> [Float] {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(bitmap, from: bitmap.extent) else {
            return []
        }
        guard let pixelData = cgImage.dataProvider?.data else {
            return []
        }
        
        guard let data = CFDataGetBytePtr(pixelData) else {
            return []
        }
        
        let width = Int(bitmap.extent.width)
        let height = Int(bitmap.extent.height)
        
        var floatArray = [Float](repeating: 0.0, count: width * height * 3)
        var index = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                
                let r = Float(data[pixelIndex]) / 255.0
                let g = Float(data[pixelIndex + 1]) / 255.0
                let b = Float(data[pixelIndex + 2]) / 255.0
                
                floatArray[index] = (r - 0.485) / 0.229
                floatArray[index + width * height] = (g - 0.456) / 0.224
                floatArray[index + 2 * width * height] = (b - 0.406) / 0.225
                index += 1
            }
        }
        
        return floatArray
    }

    private func createInputTensor(bitmap: CIImage) throws -> ORTValue {
        // 1. Convert image data to a [Float] array
        var floatArray = bitmapToFloat(bitmap: bitmap)
        
        // 2. Define expected input size
        let expectedSize = 1 * 3 * 224 * 224  // = 150,528
        
        // 3. Adjust the float array size if necessary
        if floatArray.count < expectedSize {
            // Pad the array with zeros if it's too short
            floatArray.append(contentsOf: Array(repeating: 0.0, count: expectedSize - floatArray.count))
        } else if floatArray.count > expectedSize {
            // Trim the array if it's too long
            floatArray = Array(floatArray.prefix(expectedSize))
        }

        // 4. Create OrtValue for the CLIP model
        let mutableData = NSMutableData(bytes: floatArray, length: floatArray.count * MemoryLayout<Float>.stride)
        let inputShape: [NSNumber] = [1, 3, 224, 224]
        return try ORTValue(
            tensorData: mutableData,
            elementType: .float,
            shape: inputShape
        )
    }

    
    private func rearrangeArray(_ floatArray: [Float]) throws -> [Float] {
        // use below for xgboost_liveness_quant_enh only; keep in sync with model used by CloneInference
        let columnNumbers: [String] = ["246", "339", "114", "142", "84", "13", "140", "381", "476", "507", "467", "404", "396", "376", "4", "499", "173", "425", "304", "481", "269", "257", "430", "331", "222", "133", "97", "391", "240", "220", "180", "356", "272", "295", "471", "468", "154", "305", "502", "403", "8", "243", "194", "110", "508", "313", "30", "219", "168", "37", "181", "314", "6", "411", "445", "60", "473", "478", "310", "412", "501", "217", "70", "167", "116", "420", "102", "418", "311", "386", "346", "472", "42", "432", "446", "268", "16", "366", "55", "388", "191", "399", "160", "172", "460", "353", "383", "208", "474", "65", "447", "125", "276", "372", "465", "85", "81", "367", "153", "28", "421", "453", "239", "2", "57", "250", "103", "363", "253", "490", "213", "196", "185", "495", "274", "284", "7", "285", "226", "354", "80", "368", "145", "41", "20", "341", "322", "371", "434", "251", "402", "292", "207", "503", "108", "330", "267", "504", "120", "439", "24", "317", "255", "351", "489", "414", "18", "449", "95", "401", "427", "484", "0", "419", "124", "131", "358", "52", "38", "496", "244", "119", "241", "123", "164", "23", "32", "35", "261", "12", "128", "135", "101", "429", "326", "395", "234", "279", "416", "22", "106", "259", "204", "506", "117", "293", "66", "212", "49", "78", "87", "130", "74", "332", "328", "201", "136", "79", "98", "104", "477", "321", "273", "99", "266", "170", "139", "137", "500", "256", "448", "289", "405", "205", "408", "333", "302", "174", "369", "362", "392", "31", "1", "323", "19", "189", "59", "5", "444", "232", "394", "452", "377", "10", "258", "127", "200", "296", "92", "298", "349", "50", "324", "325", "71", "479", "107", "360", "36", "237", "475", "115", "48", "202", "443", "53", "105", "33", "43", "398", "126", "455", "458", "423", "44", "227", "197", "327", "184", "365", "400", "152", "277", "206", "494", "407", "456", "91", "413", "9", "463", "483", "265", "149", "27", "340", "450", "188", "316", "470", "56", "301", "221", "280", "182", "389", "380", "82", "409", "319", "464", "151", "466", "451", "199", "94", "350", "278", "320", "374", "93", "17", "233", "440", "209", "157", "457", "248", "229", "45", "138", "228", "177", "254", "297", "165", "29", "68", "147", "39", "216", "54", "342", "397", "224", "155", "307", "335", "406", "264", "359", "96", "249", "247", "132", "148", "410", "438", "347", "88", "210", "337", "158", "442", "214", "235", "482", "370", "437", "497", "498", "169", "129", "343", "493", "288", "46", "113", "69", "290", "300", "203", "373", "422", "415", "461", "511", "190", "211", "329", "73", "270", "72", "303", "112", "47", "361", "67", "262", "509", "510", "345", "77", "286", "505", "193", "146", "143", "89", "163", "287", "486", "348", "192", "134", "487", "308", "198", "62", "176", "236", "109", "159", "283", "485", "100", "315", "334", "252", "242", "61", "355", "459", "26", "25", "231", "183", "162", "417", "86", "428", "393", "156", "225", "121", "171", "187", "318", "336", "424", "454", "375", "260", "111", "21", "141", "309", "433", "491", "364", "64", "299", "238", "83", "462", "384", "51", "338", "76", "291", "441", "492", "385", "150", "3", "435", "75", "294", "282", "378", "480", "357", "63", "218", "245", "469", "306", "34", "426", "144", "14", "387", "488", "223", "281", "352", "263", "275", "118", "122", "271", "175", "312", "90", "58", "178", "215", "230", "436", "382", "379", "344", "161", "186", "195", "431", "166", "390", "179", "15", "40", "11"]
        // use below for non-enh (straight quant ie)
        //let columnNumbers: [String] = ["161", "140", "235", "434", "192", "133", "299", "189", "243", "288", "469", "113", "483", "426", "87", "210", "368", "279", "230", "97", "302", "63", "42", "198", "430", "216", "286", "80", "241", "270", "211", "342", "419", "464", "6", "435", "38", "276", "202", "250", "309", "494", "260", "311", "297", "60", "300", "511", "11", "227", "225", "371", "253", "231", "474", "151", "106", "74", "169", "39", "116", "349", "333", "17", "143", "55", "395", "81", "369", "118", "78", "58", "360", "310", "236", "456", "165", "379", "320", "54", "308", "186", "37", "98", "293", "49", "462", "105", "197", "404", "94", "79", "374", "468", "247", "96", "442", "277", "237", "132", "343", "194", "459", "444", "460", "252", "251", "389", "47", "193", "204", "41", "375", "377", "53", "244", "31", "274", "93", "400", "327", "173", "437", "505", "155", "221", "335", "16", "254", "66", "69", "33", "422", "261", "233", "372", "125", "167", "91", "285", "117", "76", "413", "137", "497", "174", "407", "51", "284", "466", "34", "324", "124", "123", "145", "157", "7", "154", "290", "433", "238", "477", "307", "473", "249", "508", "142", "152", "481", "228", "344", "393", "417", "109", "141", "164", "200", "463", "506", "95", "3", "201", "331", "332", "283", "376", "432", "373", "455", "471", "136", "305", "382", "65", "401", "226", "363", "21", "390", "366", "431", "35", "135", "421", "416", "496", "99", "339", "281", "306", "14", "128", "222", "190", "467", "351", "418", "144", "352", "325", "19", "275", "28", "370", "264", "322", "480", "256", "388", "0", "348", "242", "12", "510", "448", "436", "73", "10", "478", "447", "64", "183", "362", "412", "365", "318", "146", "57", "398", "86", "2", "443", "289", "18", "166", "24", "72", "472", "316", "502", "295", "255", "319", "67", "110", "188", "71", "75", "213", "101", "127", "219", "159", "181", "415", "70", "330", "445", "153", "234", "269", "337", "104", "271", "176", "410", "147", "405", "265", "29", "187", "346", "345", "282", "359", "257", "403", "27", "336", "385", "148", "177", "120", "356", "232", "294", "367", "88", "179", "340", "191", "263", "298", "304", "50", "205", "429", "214", "397", "475", "82", "378", "272", "425", "268", "163", "258", "387", "490", "25", "223", "292", "446", "180", "175", "361", "479", "386", "121", "358", "185", "240", "353", "458", "1", "449", "262", "411", "77", "287", "301", "44", "212", "239", "209", "440", "420", "383", "323", "380", "126", "504", "36", "138", "245", "100", "229", "108", "409", "160", "450", "482", "40", "43", "84", "218", "26", "215", "493", "45", "172", "457", "507", "85", "115", "315", "150", "484", "491", "32", "278", "303", "355", "394", "328", "30", "9", "266", "338", "439", "22", "5", "267", "158", "334", "46", "312", "438", "107", "341", "52", "314", "296", "102", "129", "92", "59", "350", "399", "206", "326", "170", "112", "408", "509", "317", "423", "111", "224", "465", "454", "391", "503", "114", "452", "347", "259", "203", "122", "20", "83", "488", "130", "424", "248", "427", "149", "489", "291", "476", "313", "103", "162", "168", "184", "329", "68", "48", "492", "61", "195", "428", "498", "134", "451", "220", "487", "56", "119", "217", "196", "156", "486", "4", "178", "280", "246", "357", "441", "208", "364", "15", "89", "90", "453", "273", "392", "501", "199", "354", "8", "207", "495", "171", "499", "414", "23", "381", "182", "139", "470", "62", "131", "406", "321", "485", "384", "13", "500", "461", "402", "396"]
        
        guard columnNumbers.count == floatArray.count else {
            throw PicRecognizerError.invalidArraySizes
        }
        
        let intColumns: [Int] = columnNumbers.compactMap { Int($0) }
        guard !intColumns.contains(where: { $0 < 0 || $0 >= columnNumbers.count }) else {
            throw PicRecognizerError.invalidColumnNumbers
        }
        
        var reorderedArray = [Float](repeating: 0.0, count: columnNumbers.count)
        for (index, col) in intColumns.enumerated() {
            reorderedArray[index] = floatArray[col]
        }
        
        return reorderedArray
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
    
    private func normalizeCIImage(inputImage: CIImage) -> CIImage? {
        // Define the normalization parameters
        let meanRed: CGFloat = 0.48145466
        let meanGreen: CGFloat = 0.4578275
        let meanBlue: CGFloat = 0.40821073
        let stdRed: CGFloat = 0.26862954
        let stdGreen: CGFloat = 0.26130258
        let stdBlue: CGFloat = 0.27577711

        // Use CIColorMatrix filter to normalize the image
        let colorMatrixFilter = CIFilter.colorMatrix()
        colorMatrixFilter.inputImage = inputImage

        // (pixel - mean) / std normalization for RGB channels
        // Apply color matrix with mean subtraction and standard deviation scaling
        // Subtract mean
        colorMatrixFilter.rVector = CIVector(x: 1.0 / stdRed, y: 0, z: 0, w: -meanRed / stdRed)
        colorMatrixFilter.gVector = CIVector(x: 0, y: 1.0 / stdGreen, z: 0, w: -meanGreen / stdGreen)
        colorMatrixFilter.bVector = CIVector(x: 0, y: 0, z: 1.0 / stdBlue, w: -meanBlue / stdBlue)
        colorMatrixFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        // Get the output image
        guard let normalizedImage = colorMatrixFilter.outputImage else {
            print("Error: Failed to apply normalization filter")
            return nil
        }

        return normalizedImage
    }
    
    private func isRGBImage(_ image: CIImage) -> Bool {
        guard let colorSpace = image.colorSpace else {
            return false // Assume non-RGB if no color space is defined
        }
        return colorSpace.model == .rgb
    }
    
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
