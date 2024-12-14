//
//  PicIDRecognizer.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 10/28/24.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision
import UIKit

class IDInformation {
    var firstName: String?
    var lastName: String?
    var dateOfBirth: Date?
    var idNumber: String?
    var issueDate: Date?
    var expirationDate: Date?
    var userProfilePic: CIImage?

    var isNotUnderAge: Bool? {
        // Ensure both dates are available and correctly formatted
        guard let dob = dateOfBirth, let exp = expirationDate else { return nil }

        // Calculate age from date of birth
        let currentDate = Date()
        let ageComponents = Calendar.current.dateComponents([.year, .month, .day], from: dob, to: currentDate)

        // Check if the person is at least 21 years old
        let isAtLeast21 = ageComponents.year! >= 21 ||
                          (ageComponents.year! == 20 && ageComponents.month! > Calendar.current.component(.month, from: dob)) ||
                          (ageComponents.year! == 20 && ageComponents.month! == Calendar.current.component(.month, from: dob) && ageComponents.day! >= Calendar.current.component(.day, from: dob))

        // Check if expired
        let isExpired = exp < Date()

        return isAtLeast21 && !isExpired
    }

    // Helper function to parse date strings to Date objects
    func parseDate(_ dateString: String) -> Date? {
        // Regular expression to match common date formats at the end of the string
        let dateRegex = try! NSRegularExpression(pattern: "(?:\\d{1,2}/\\d{1,2}/\\d{4}|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}-\\d{1,2}-\\d{4}|\\d{1,2} [A-Za-z]{3} \\d{4}|\\d{1} [A-Za-z]{3} \\d{4})$", options: [])

        // Find the last occurrence of a date format in the string
        if let match = dateRegex.firstMatch(in: dateString, options: [], range: NSRange(location: 0, length: dateString.utf16.count)) {
            let dateMatch = String(dateString[Range(match.range, in: dateString)!])

            // Parse the extracted date string
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            let dateFormats = [
                "MM/dd/yyyy",
                "yyyy-MM-dd",
                "dd-MM-yyyy",
                "MM-dd-yyyy",
                "dd MMM yyyy", // Added for formats like "08 Sep 1966"
                "d MMM yyyy"  // Added for single-digit days
            ]
            for format in dateFormats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateMatch) {
                    return date
                }
            }
        }

        // If no match is found, return nil
        return nil
    }

    // Helper function to convert Date to String
    func parseDateToString(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: date)
    }

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
                let firstFewLines = results.prefix(5).compactMap { $0.topCandidates(1).first?.string.uppercased() }
                if firstFewLines.contains(where: { $0.contains("LICENSE") }) {
                    self.extractFieldsFromLic(results: results, idInfo: idInfo)
                } else if firstFewLines.contains(where: { $0.contains("PASSPORT") || $0.contains("PASAPORTE") || $0.contains("SURNAME") || $0.contains("PASSEPORT") }) {
                    self.extractFieldsFromPassport(results: results, idInfo: idInfo)
                }
                // Call the new method to fill in any empty idInfo fields
                self.extractUnknownFields(results: results, idInfo: idInfo)
            }

            if let profilePic = self.extractProfilePicture(from: ciImage) {
                idInfo.userProfilePic = profilePic
            }

            completion(.success(idInfo))
        }

        // Configure the request
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        request.customWords = [
            "FN", "LN", "DOB", "DL", "EXP", "ISS", "PASSPORT", "PASAPORTE", "PASSEPORT", "SURNAME",
            "GIVEN NAMES", "DATE OF BIRTH", "DATE OF EXPIRATION", "APELLIDOS", "NOMBRES",
            "FECHA DE NACIMIENTO", "FECHA DE CADUCIDAD", "PASSPORT NO", "PASAPORT NO", "DATE OF EXP"
        ]

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func extractFieldsFromLic(results: [VNRecognizedTextObservation], idInfo: IDInformation) {
        // Extract all text observations
        let allTexts = results.compactMap { $0.topCandidates(1).first?.string }
        let splitTexts = allTexts.flatMap { splitTextWithMultipleColons($0) }
        for text in splitTexts {
            print("Extracted field from ID: \(text)")

            // Define the keys to look for
            let keys = ["FN", "LN", "DOB", "DL", "ĐL", "EXP", "ISS", "ров"]

            for key in keys {
                if let range = text.range(of: key, options: .caseInsensitive) {
                    // Find the colon after the key
                    if let colonRange = text.range(of: ":", options: .caseInsensitive, range: range.upperBound..<text.endIndex) {
                        // Extract the value after the colon, trimming any leading or trailing whitespace
                        let value = text[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                        switch key.uppercased() {
                        case "FN":
                            idInfo.firstName = value
                        case "LN":
                            idInfo.lastName = value
                        case "DOB", "ров":
                            if let date = idInfo.parseDate(value) {
                                idInfo.dateOfBirth = date
                            }
                        case "DL", "ĐL":
                            idInfo.idNumber = value
                        case "EXP":
                            if let date = idInfo.parseDate(value) {
                                idInfo.expirationDate = date
                            }
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    private func extractFieldsFromPassport(results: [VNRecognizedTextObservation], idInfo: IDInformation) {
        var mrz = ""
        var currentField = ""
        for observation in results {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            let text = topCandidate.string.trimmingCharacters(in: .whitespaces)
            print("Extracted field from ID: \(text)")
            if text.contains("Surname") || text.contains("Apellidos") {
                currentField = "lastName"
            } else if text.contains("Given Names") || text.contains("Nombres") {
                currentField = "firstName"
            } else if text.contains("Date of birth") || text.contains("Fecha de nacimiento") {
                currentField = "dateOfBirth"
            } else if text.contains("Date of exp") {
                currentField = "expirationDate"
            } else if text.contains("Passport No") || text.contains("Pasaport No") {
                currentField = "idNumber"
            } else if text.starts(with: "P<") || (text.contains("USA") && text.contains("<")) {
                mrz = text
            } else if !currentField.isEmpty && !text.contains("/") {
                switch currentField {
                case "lastName":
                    idInfo.lastName = text
                case "firstName":
                    idInfo.firstName = text
                case "dateOfBirth":
                    if let date = idInfo.parseDate(text) {
                        idInfo.dateOfBirth = date
                    }
                case "expirationDate":
                    if let date = idInfo.parseDate(text) {
                        idInfo.expirationDate = date
                    }
                case "idNumber":
                    idInfo.idNumber = text
                default:
                    break
                }
                currentField = ""
            }
        }

        // Extract passport number from MRZ if not already extracted
        if idInfo.idNumber == nil && !mrz.isEmpty {
            if mrz.starts(with: "P<") {
                let components = mrz.components(separatedBy: "USA")
                if components.count > 1 {
                    idInfo.idNumber = String(components[0].suffix(9))
                }
            } else {
                // Handle the case where MRZ doesn't start with "P<"
                let mrzComponents = mrz.components(separatedBy: "USA")
                if mrzComponents.count > 0 {
                    idInfo.idNumber = String(mrzComponents[0].prefix(9))
                }
            }
        }
    }

    private func extractUnknownFields(results: [VNRecognizedTextObservation], idInfo: IDInformation) {
        // Extract all text observations
        let allTexts = results.compactMap { $0.topCandidates(1).first?.string }
        let splitTexts = allTexts.flatMap { splitTextWithMultipleColons($0) }
        // Clean the text to remove arbitrary characters, whitespaces, and colons before the actual value
        let cleanedTexts = splitTexts.map { text in
            text.replacingOccurrences(of: "^(?:.*?:\\s*)*", with: "", options: .regularExpression)
        }

        // Find the first non-date field of numbers (with or without dashes) as the idNumber
        if idInfo.idNumber == nil {
            do {
                let dateRegex = try NSRegularExpression(pattern: "\\b(?:\\d{1,2}/\\d{1,2}/\\d{4}|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}-\\d{1,2}-\\d{4}|\\d{1,2} [A-Za-z]{3} \\d{4}|\\d{1} [A-Za-z]{3} \\d{4})\\b", options: [])

                // Updated prefixSkipping to match specific prefixes and allow any arbitrary characters before them
                let prefixSkipping = ".*?(DL|DL#|Lic\\. No\\.|DLN|NO|[a-zA-Z0-9]+[.])?\\s*"  // Matches specific prefixes and any arbitrary characters
                let idFormats = [
                    "\\b[0-9]{13}\\b",           // Montana (13 digits) NOTE :- keep all digit checks at beginning in desc order
                    "\\b[0-9]{12}\\b",           // North Carolina (12 digits)
                    "\\b[0-9]{9}\\b",            // Montana (9 digits)
                    "\\b[0-9]{8}\\b",            // South Dakota, Vermont (8 digits)
                    "[a-zA-Z]?\\d{7}",           // Alabama
                    "[a-zA-Z]?\\d{9}",           // Arizona
                    "[a-zA-Z]?\\d{10}",          // Nevada
                    "[a-zA-Z]?\\d{2}-\\d{3}-\\d{4}", // Colorado
                    "[a-zA-Z]\\d{8}",            // Hawaii
                    "[a-zA-Z]\\d{7}",            // California
                    "[a-zA-Z]?9\\d{8}",          // Arkansas
                    "[a-zA-Z]\\d{12}",           // Florida
                    "[a-zA-Z] \\d{3} \\d{3} \\d{3} \\d{3}", // Florida formatted
                    "[a-zA-Z]\\d{3}-\\d{4}-\\d{4}", // Illinois formatted (P###-####-####)
                    "[a-zA-Z]\\d{11}",           // Illinois unformatted (if applicable)
                    "[a-zA-Z]?\\d{4}-\\d{2}-\\d{4}", // Indiana
                    "[a-zA-Z]?\\d{3}[a-zA-Z]{2}\\d{4}", // Iowa alternative
                    "[a-zA-Z]\\d{2}-\\d{2}-\\d{4}", // Kansas
                    "[a-zA-Z]\\d{2}-\\d{3}-\\d{3}", // Kentucky
                    "[a-zA-Z]\\d{3}-\\d{3}-\\d{3}-\\d{3}", // Minnesota
                    "[a-zA-Z]?\\d{3}-\\d{2}-\\d{4}", // Mississippi Social Security number format
                    "[a-zA-Z]\\d{9}",             // Missouri
                    "(0[1-9]|1[0-2])[a-zA-Z]{3}\\d{2}(0[1-9]|[12][0-9]|3[01])\\d", // New Hampshire
                    "[a-zA-Z]\\d{4} \\d{5} \\d{5}", // New Jersey formatted
                    "[a-zA-Z]\\d{14}",            // New Jersey unformatted
                    "\\b[0-9]{3} [0-9]{3} [0-9]{3}\\b", // New York formatted (### ### ###)
                    "[a-zA-Z]{3}-[0-9]{2}-[0-9]{4}", // North Dakota
                    "[a-zA-Z]?\\b[0-9]{7}[a-zA-Z]\\b",   // Vermont alternative (7 digits + letter)
                    "[a-zA-Z] \\b[0-9]{3} \\b[0-9]{3} \\b[0-9]{3} \\b[0-9]{3}", // Michigan formatted (L ### ### ### ###)
                    "[a-zA-Z]\\b[0-9]{3}-[0-9]{4}-[0-9]{4}-[0-9]{2}\\b", // Wisconsin formatted (L###-####-####-##)
                    "\\b[0-9]{6}-[0-9]{3}\\b",     // Wyoming (######-###)
                    "S\\s?\\d+(?:\\s?\\d+)*",     // S followed by digits with optional spaces
                    "W\\d{6}",                   // W followed by 6 digits
                    "NHL\\d{6}",                 // NHL followed by 6 digits
                    "S\\d{6}"                    // S followed by 6 digits
                ].joined(separator: "|")

                let idNumberRegexPattern = "\(prefixSkipping)(\(idFormats))"
                let idNumberRegex = try NSRegularExpression(pattern: idNumberRegexPattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
                var hasFoundFirstIdNumber = false // Flag to ensure only the first ID number is picked.
                let idNumberMatches = cleanedTexts.compactMap { text -> String? in
                    if hasFoundFirstIdNumber {
                        return nil // Skip processing further once the first ID number is found.
                    }
                    // Check if the text matches a date format; if yes, delete date from text & proceed
                    let processedText = processText(text, using: dateRegex)
                    // Check for ID number regex match.
                    if let match = idNumberRegex.firstMatch(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count)) {
                        if let range = Range(match.range(at: 2), in: text) { // Capture group for ID number.
                            let idNumber = String(text[range]).trimmingCharacters(in: .whitespaces)
                            hasFoundFirstIdNumber = true // Update the flag after the first valid ID number is found.
                            print("Matched ID Number: \(idNumber)") // Log for debugging.
                            return idNumber // Return the matched ID number.
                        } else {
                            print("No valid capture group found for ID number in text: \(text)")
                            return nil
                        }
                    } else {
                        print("No match found for ID number in text: \(text)")
                        return nil
                    }
                }

                if let idNumber = idNumberMatches.first {
                    idInfo.idNumber = idNumber  // Assign the first matched ID number to idInfo.idNumber.
                }
            } catch {
                print("Error creating regex: \(error)")
            }
        }

        // Extract date fields
        if idInfo.dateOfBirth == nil || idInfo.expirationDate == nil {
            var dateFields: [Date] = []
            for text in cleanedTexts {
                // Regular expression to match common date formats
                let dateRegex = try! NSRegularExpression(pattern: "(?:\\d{1,2}/\\d{1,2}/\\d{4}|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}-\\d{1,2}-\\d{4}|\\d{1,2} [A-Za-z]{3} \\d{4}|\\d{1} [A-Za-z]{3} \\d{4})", options: [])

                // Find all matches of date formats in the text
                let matches = dateRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

                // Extract and parse each match as a separate date
                for match in matches {
                    let dateMatch = String(text[Range(match.range, in: text)!])
                    if let date = idInfo.parseDate(dateMatch) {
                        dateFields.append(date)
                    }
                }
            }

            // Sort the date fields and assign them accordingly
            dateFields.sort()
            if !dateFields.isEmpty {
                if idInfo.dateOfBirth == nil {
                    idInfo.dateOfBirth = dateFields.first
                }
                if idInfo.expirationDate == nil && dateFields.count > 1 {
                    idInfo.expirationDate = dateFields.last
                }
                if idInfo.expirationDate == nil && dateFields.count > 2 {
                    idInfo.expirationDate = dateFields.last
                    if idInfo.dateOfBirth == nil {
                        idInfo.dateOfBirth = dateFields.first
                    }
                }
            }
        }
    }
    
    private func splitTextWithMultipleColons(_ text: String) -> [String] {
        var segments: [String] = []
        var currentSegment = ""

        let parts = text.components(separatedBy: " ")
        for part in parts {
            if part.contains(":") && !currentSegment.isEmpty {
                // If we encounter a new key-value pair, push the current segment to the array
                segments.append(currentSegment.trimmingCharacters(in: .whitespaces))
                currentSegment = part
            } else {
                // Otherwise, continue building the current segment
                currentSegment += " \(part)"
            }
        }
        
        // Add the last segment to the array
        if !currentSegment.isEmpty {
            segments.append(currentSegment.trimmingCharacters(in: .whitespaces))
        }
        
        return segments
    }

    
    private func processText(_ text: String, using dateRegex: NSRegularExpression) -> String {
        // Check for a match
        if let match = dateRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            // Create a mutable copy of the original text
            var updatedText = text
            // Extract the range of the matched date
            if let range = Range(match.range, in: text) {
                // Replace the matched date with an empty string
                updatedText.removeSubrange(range)
            }
            // Continue with the rest of your ID processing here
            return updatedText.trimmingCharacters(in: .whitespacesAndNewlines) // Optional: Trim whitespace
        }
        // If no match is found, return the original text
        return text
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

            // Handle edge case where dimensions are off by 1 pixel
            if finalImage.extent.width < targetSize.width || finalImage.extent.height < targetSize.height {
                // Calculate exact padding required on each side
                let widthDifference = targetSize.width - finalImage.extent.width
                let heightDifference = targetSize.height - finalImage.extent.height

                // Divide the difference and round to ensure integer padding
                let leftPadding = floor(widthDifference / 2)
                let topPadding = floor(heightDifference / 2)

                // Apply padding by transforming the image
                finalImage = finalImage.transformed(by: CGAffineTransform(translationX: leftPadding, y: topPadding))
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
                faceObservation.boundingBox.insetBy(dx: -0.03, dy: -0.03),
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

