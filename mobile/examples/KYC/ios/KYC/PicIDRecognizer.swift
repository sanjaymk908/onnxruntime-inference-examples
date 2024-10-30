//
//  PicIDRecognizer.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 10/28/24.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UIKit

class IDInformation {
    var firstName: String?
    var lastName: String?
    var dateOfBirth: String?
    var idNumber: String?
    var issueDate: String?
    var expirationDate: String?
    var address: String?
    
    var userProfilePic: CIImage?
    
    init() {}
}

public class PicIDRecognizer {
    func recognizeID(from ciImage: CIImage, completion: @escaping (Result<IDInformation, Error>) -> Void) {
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            
            let idInfo = IDInformation()
            
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
        // Step 1: Detect faces
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            try handler.perform([faceRequest])
        } catch {
            print("Face detection failed: \(error)")
            return nil
        }
        
        // Helper function to process and resize the cropped image
        func processAndResizeImage(_ croppedImage: CIImage) -> CIImage? {
            let targetSize = CGSize(width: 224, height: 224)

            // Calculate scale with a small buffer to ensure 224x224 size
            let scaleX = targetSize.width / croppedImage.extent.width
            let scaleY = targetSize.height / croppedImage.extent.height
            let scale = max(scaleX, scaleY) * 1.001  // Adding a tiny buffer for rounding

            // Scale the image
            let scaledImage = croppedImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            // Center the image to (0,0) after scaling
            let translatedImage = scaledImage.transformed(by: CGAffineTransform(translationX: -scaledImage.extent.origin.x, y: -scaledImage.extent.origin.y))

            // Define the final crop rectangle and pad if necessary
            let cropRect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
            var finalImage = translatedImage.cropped(to: cropRect)

            // Check if padding is needed and apply padding if required
            if finalImage.extent.width < targetSize.width || finalImage.extent.height < targetSize.height {
                let paddingX = max(0, (targetSize.width - finalImage.extent.width) / 2)
                let paddingY = max(0, (targetSize.height - finalImage.extent.height) / 2)

                finalImage = finalImage.transformed(by: CGAffineTransform(translationX: paddingX, y: paddingY))
            }

            // Print extents for debugging
            print("Face detection crop extent:", croppedImage.extent)
            print("Scaled Image Extent:", scaledImage.extent)
            print("Translated Image Extent:", translatedImage.extent)
            print("Final Image Extent:", finalImage.extent)

            return finalImage
        }

        // Check if any faces were detected
        if let faceObservations = faceRequest.results, !faceObservations.isEmpty {
            guard let faceObservation = faceObservations.first else { return nil }
            
            // Expand the face bounding box slightly to include more of the head/shoulders
            var expandedBoundingBox = VNImageRectForNormalizedRect(
                faceObservation.boundingBox.insetBy(dx: -0.1, dy: -0.1),
                Int(ciImage.extent.width),
                Int(ciImage.extent.height)
            )
            
            // Ensure the expanded bounding box is within the image bounds
            expandedBoundingBox = expandedBoundingBox.intersection(ciImage.extent)
            
            guard !expandedBoundingBox.isNull && expandedBoundingBox.width > 0 && expandedBoundingBox.height > 0 else {
                print("Invalid face bounding box")
                return nil
            }
            
            let croppedImage = ciImage.cropped(to: expandedBoundingBox)
            print("Face detection crop extent: \(croppedImage.extent)")
            
            return processAndResizeImage(croppedImage)
        } else {
            print("No faces detected; returning nil.")
            return nil // Or you could return the entire image if desired.
        }
    }

}

