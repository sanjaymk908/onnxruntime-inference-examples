//
//  VideoRecognizer.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/14/24.
//

import Foundation

class VideoRecognizer {
    
    var picRecognizer: PicRecognizer?
    var speechRecognizer: SpeechRecognizer?
    
    init(_ completion: @escaping ((Bool) -> Void)) {
        let dispatchGroup = DispatchGroup()
        var isSuccessful = true  // Track success status
        
        dispatchGroup.enter()
        setupPicRecognizer { success in
            if !success { isSuccessful = false }
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        setupSpeechRecognizer { success in
            if !success { isSuccessful = false }
            dispatchGroup.leave()
        }
        
        // Notify when both setup tasks are done
        dispatchGroup.notify(queue: .main) {
            completion(isSuccessful) // Returns true if both succeeded, false if any failed
        }
    }

    private func setupPicRecognizer(completion: @escaping ((Bool) -> Void)) {
        DispatchQueue.global().async {
            do {
                let picRecognizer = try PicRecognizer()
                DispatchQueue.main.async {
                    self.picRecognizer = picRecognizer
                    completion(true) // Success
                }
            } catch {
                // Handle the initialization error here
                print("Failed to initialize PicRecognizer: \(error)")
                DispatchQueue.main.async {
                    completion(false) // Failure
                }
            }
        }
    }

    private func setupSpeechRecognizer(completion: @escaping ((Bool) -> Void)) {
        DispatchQueue.global().async {
            do {
                let speechRecognizer = try SpeechRecognizer()
                DispatchQueue.main.async {
                    self.speechRecognizer = speechRecognizer
                    completion(true) // Success
                }
            } catch {
                // Handle the initialization error here
                print("Failed to initialize SpeechRecognizer: \(error)")
                DispatchQueue.main.async {
                    completion(false) // Failure
                }
            }
        }
    }

    func drivePicRecognizer(_ videoFragments: [VideoFragment]) {
        let count = videoFragments.count
        for index in 0..<count {
            let fragment = videoFragments[index]
            
            if let picRecognizer = picRecognizer {
                let result = picRecognizer.evaluate(bitmap: fragment.stillFrame)
                
                switch result {
                case .success(let cloneCheckResult):
                    // Check if cloneCheckResult tuple contains "clone" in the result string
                    fragment.isPicCloned = cloneCheckResult.0.contains("clone")
                case .failure:
                    fragment.isPicCloned = false
                }
            } else {
                // Handle case where picRecognizer is nil
                fragment.isPicCloned = false
            }
        }
    }
    
    func driveSpeechRecognizer(_ videoFragments: [VideoFragment]) {
        let count = videoFragments.count
        for index in 0..<count {
            let fragment = videoFragments[index]
            let result = speechRecognizer?.evaluate(inputData: fragment.audioSnippet)
            switch result {
            case .some(.success(let cloneCheckResult)):
                fragment.isAudioCloned = cloneCheckResult.contains("clone")
            case .some(.failure):
                fragment.isAudioCloned = false
            case .none:
                fragment.isAudioCloned = false
            }
        }
    }
    
}
