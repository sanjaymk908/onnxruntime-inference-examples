//
//  PicRecognizer.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import AVFoundation
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
    }

    required init() throws {
        let startTime = DispatchTime.now()
        ortEnv = try ORTEnv(loggingLevel: ORTLoggingLevel.verbose)
        guard let modelPath = Bundle.main.path(forResource: "clip_image_encoder", ofType: "onnx") else {
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

    func evaluate(bitmap: CIImage) -> Result<String, Error> {
        do {
            let inputTensor = try createInputTensor(bitmap: bitmap)
            let outputs = try runModel(with: [inputName: inputTensor])
            guard let imageEmbeds = outputs[outputName] else {
                throw PicRecognizerError.failedToRunModel
            }

            let embsData = try imageEmbeds.tensorData() as Data
            var clonedTestResult: Result<String, any Error> = .success("Default Value")
            let result = try embsData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Result<String, any Error> in
                let floatBuffer = buffer.bindMemory(to: Float.self)
                print("embs size: \(floatBuffer.count)")
                let floatArray = Array(floatBuffer)
                let floatArrayRearranged: [Float] = try rearrangeArray(floatArray)
                let doubleArray = floatArrayRearranged.map { Double($0) }
                clonedTestResult = cloneDetector.evaluate(inputData: doubleArray)
                return clonedTestResult
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
      // 1. Convert image data to a [Float]]
        let floatArray = bitmapToFloat(bitmap: bitmap)
      
      // 5. Create OrtValue for the CLIP model
      let mutableData = NSMutableData(bytes: floatArray, length: floatArray.count * MemoryLayout<Float>.stride)
      let inputShape: [NSNumber] = [1, 3, 224, 224]
      return try ORTValue(
            tensorData: mutableData,
            elementType: .float,
            shape: inputShape
      )
    }
    
    private func rearrangeArray(_ floatArray: [Float]) throws -> [Float] {
        // use below for 140kPlusCelebA-model.ort only; can be used for 140kPlusCelebA-model_no_zipmap.onnx too
        let columnNumbers: [String] = ["325", "121", "398", "54", "200", "131", "86", "114", "177", "213", "395", "508", "137", "47", "20", "185", "284", "426", "6", "374", "283", "333", "394", "345", "35", "324", "291", "319", "402", "88", "220", "38", "63", "62", "510", "313", "448", "505", "148", "236", "466", "113", "235", "247", "349", "481", "278", "18", "295", "263", "351", "493", "117", "464", "382", "233", "29", "118", "17", "261", "431", "304", "254", "156", "353", "361", "471", "85", "198", "221", "371", "472", "189", "139", "192", "110", "133", "288", "469", "146", "340", "179", "310", "511", "125", "205", "103", "486", "298", "229", "132", "80", "111", "99", "232", "277", "355", "430", "57", "224", "329", "451", "446", "435", "360", "34", "76", "415", "412", "494", "485", "468", "82", "65", "151", "441", "275", "173", "328", "21", "474", "243", "365", "317", "49", "342", "183", "31", "67", "102", "266", "445", "343", "40", "52", "0", "19", "354", "509", "407", "376", "306", "249", "484", "294", "457", "356", "22", "106", "434", "182", "234", "237", "251", "270", "226", "253", "155", "425", "14", "368", "147", "444", "120", "409", "45", "238", "364", "262", "336", "335", "203", "397", "386", "180", "23", "66", "274", "269", "215", "314", "452", "208", "167", "123", "89", "438", "443", "507", "487", "320", "10", "410", "433", "265", "175", "12", "322", "373", "423", "95", "135", "344", "163", "280", "244", "286", "478", "399", "506", "193", "27", "188", "281", "455", "164", "326", "210", "207", "483", "352", "246", "276", "223", "136", "204", "406", "309", "55", "331", "465", "225", "480", "411", "165", "260", "201", "370", "440", "458", "81", "150", "5", "267", "109", "391", "418", "341", "300", "252", "74", "369", "187", "16", "211", "25", "195", "447", "53", "186", "461", "496", "115", "332", "91", "282", "417", "240", "491", "37", "315", "56", "292", "379", "44", "264", "153", "497", "126", "196", "119", "357", "59", "387", "385", "463", "162", "348", "308", "124", "144", "339", "79", "421", "48", "489", "93", "389", "359", "307", "77", "191", "9", "11", "393", "71", "174", "296", "375", "347", "456", "168", "293", "218", "217", "28", "242", "97", "152", "390", "166", "323", "43", "190", "289", "303", "475", "330", "170", "279", "98", "69", "405", "290", "228", "271", "255", "454", "268", "490", "149", "100", "388", "51", "259", "350", "64", "184", "61", "327", "498", "297", "403", "427", "70", "258", "492", "216", "302", "178", "488", "467", "305", "358", "154", "181", "72", "107", "172", "127", "414", "138", "502", "130", "367", "104", "470", "462", "2", "287", "161", "171", "212", "459", "24", "108", "380", "500", "416", "169", "15", "42", "105", "381", "383", "363", "312", "501", "41", "257", "1", "46", "68", "157", "128", "239", "134", "39", "384", "230", "460", "116", "299", "428", "316", "366", "241", "318", "473", "214", "404", "245", "272", "143", "8", "476", "413", "7", "311", "145", "499", "449", "419", "450", "158", "477", "122", "58", "432", "392", "13", "96", "482", "439", "30", "84", "206", "346", "401", "250", "222", "337", "227", "142", "194", "50", "436", "396", "83", "3", "90", "129", "372", "73", "112", "60", "400", "94", "420", "159", "256", "160", "442", "377", "209", "301", "479", "36", "504", "92", "503", "33", "362", "140", "176", "32", "87", "101", "424", "378", "78", "408", "422", "437", "495", "75", "4", "248", "273", "199", "219", "453", "429", "26", "338", "334", "141", "285", "202", "231", "197", "321"]
        
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
}
