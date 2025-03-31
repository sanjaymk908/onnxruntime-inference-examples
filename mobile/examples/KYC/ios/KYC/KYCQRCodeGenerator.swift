//
//  KYCQRCodeGenerator.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 3/28/25.
//

import UIKit
import CoreImage

class KYCQRCodeGenerator {
    static func generateQRCode(from clientAPI: ClientAPI, size: CGSize) -> UIImage? {
        let payload = createPayload(from: clientAPI)
        return generateQRCode(from: payload, size: size)
    }
    
    private static func createPayload(from clientAPI: ClientAPI) -> String {
        var params: [String: String] = [:]
        
        // Include all public fields - QRCode generation has a size limit
        // So, leave out embeddings for now
        //if let selfieEmbedding = clientAPI.selfieEmbedding {
        //    params["selfie_embedding"] = selfieEmbedding.map { String($0) }.joined(separator: ",")
        //}
        //if let idProfileEmbedding = clientAPI.idProfileEmbedding {
        //    params["id_profile_embedding"] = idProfileEmbedding.map { String($0) }.joined(separator: ",")
        //}
        
        params["real_prob"] = String(clientAPI.realProb ?? 0)
        params["fake_prob"] = String(clientAPI.fakeProb ?? 0)
        params["real_prob_apple"] = String(clientAPI.realProbAppleAPI ?? 0)
        params["fake_prob_apple"] = String(clientAPI.fakeProbAppleAPI ?? 0)
        params["selfie_id_match"] = String(clientAPI.selfieIDprofileMatchProb ?? 0)
        params["age_verified"] = String(clientAPI.isUserAbove21)
        params["selfie_real"] = String(clientAPI.isSelfieReal)
        if let failureReason = clientAPI.failureReason {
            params["failure_reason"] = String(describing: failureReason)
        }
        
        // Convert params to URL-encoded string
        let queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var urlComponents = URLComponents(string: "https://www.yella.co.in/kyc/verify.php")!
        urlComponents.queryItems = queryItems
        
        return urlComponents.url?.absoluteString ?? ""
    }
    
    private static func generateQRCode(from string: String, size: CGSize) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter?.setValue(data, forKey: "inputMessage")
        qrFilter?.setValue("H", forKey: "inputCorrectionLevel") // Highest error correction
        
        guard let qrImage = qrFilter?.outputImage else { return nil }
        
        // Scale the QR code
        let scaleX = size.width / qrImage.extent.width
        let scaleY = size.height / qrImage.extent.height
        let transformedImage = qrImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Render the CIImage into a CGImage using CIContext
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }
        
        // Convert CGImage to UIImage
        return UIImage(cgImage: cgImage)
    }

}

