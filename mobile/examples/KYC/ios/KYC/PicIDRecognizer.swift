//
//  PicIDRecognizer.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 10/28/24.
//

import CoreImage
import Vision
import UIKit

struct IDInformation: Codable {
    var firstName: String?
    var lastName: String?
    var dateOfBirth: String?
    var idNumber: String?
    var issueDate: String?
    var expirationDate: String?
    var address: String?
    
    // Store profile picture as Data for Codable conformance
    var userProfilePicData: Data?
    
    var userProfilePic: CIImage? {
        get {
            guard let data = userProfilePicData else { return nil }
            return CIImage(data: data)
        }
        set {
            guard let ciImage = newValue else {
                userProfilePicData = nil
                return
            }
            let uiImage = UIImage(ciImage: ciImage)
            userProfilePicData = uiImage.pngData()
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case firstName, lastName, dateOfBirth, idNumber, issueDate, expirationDate, address, userProfilePicData
    }
}

public class PicIDRecognizer {
    func recognizeID(from ciImage: CIImage, completion: @escaping (Result<IDInformation, Error>) -> Void) {
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            
            var idInfo = IDInformation()
            
            if let results = request.results as? [VNRecognizedTextObservation] {
                for observation in results {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    let text = topCandidate.string
                    if text.contains("First Name:") { idInfo.firstName = text.replacingOccurrences(of: "First Name:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("Last Name:") { idInfo.lastName = text.replacingOccurrences(of: "Last Name:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("DOB:") { idInfo.dateOfBirth = text.replacingOccurrences(of: "DOB:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("ID Number:") { idInfo.idNumber = text.replacingOccurrences(of: "ID Number:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("Issue Date:") { idInfo.issueDate = text.replacingOccurrences(of: "Issue Date:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("Expiration Date:") { idInfo.expirationDate = text.replacingOccurrences(of: "Expiration Date:", with: "").trimmingCharacters(in: .whitespaces) }
                    else if text.contains("Address:") { idInfo.address = text.replacingOccurrences(of: "Address:", with: "").trimmingCharacters(in: .whitespaces) }
                }
            }
            
            if let profilePic = self.extractProfilePicture(from: ciImage) {
                idInfo.userProfilePic = profilePic
            }
            
            completion(.success(idInfo))
        }
        
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func extractProfilePicture(from ciImage: CIImage) -> CIImage? {
        var profilePic: CIImage?
        
        // Create a face detection request
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { (request, error) in
            guard let results = request.results as? [VNFaceObservation], let faceObservation = results.first else {
                return
            }
            
            // Calculate bounding box for the detected face
            let faceBoundingBox = faceObservation.boundingBox
            
            // Convert bounding box to image coordinates
            let imageSize = ciImage.extent.size
            let boundingBoxInPixels = CGRect(
                x: faceBoundingBox.origin.x * imageSize.width,
                y: (1 - faceBoundingBox.origin.y - faceBoundingBox.height) * imageSize.height,
                width: faceBoundingBox.width * imageSize.width,
                height: faceBoundingBox.height * imageSize.height
            )
            
            // Crop the face region from the original image
            profilePic = ciImage.cropped(to: boundingBoxInPixels)
        }
        
        // Execute the face detection request
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        try? handler.perform([faceDetectionRequest])
        
        return profilePic
    }
}

