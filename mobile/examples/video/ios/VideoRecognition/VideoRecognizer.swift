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
    
    init() {
        setupPicRecognizer()
        setupSpeechRecognizer()
    }

    private func setupPicRecognizer() {
        DispatchQueue.global().async {
            do {
                let picRecognizer = try PicRecognizer()
                DispatchQueue.main.async {
                    self.picRecognizer = picRecognizer
                }
            } catch {
                // Handle the initialization error here
                print("Failed to initialize PicRecognizer: \(error)")
            }
        }
    }
    
    private func setupSpeechRecognizer() {
        DispatchQueue.global().async {
            do {
                let speechRecognizer = try SpeechRecognizer()
                DispatchQueue.main.async {
                    self.speechRecognizer = speechRecognizer
                }
            } catch {
                // Handle the initialization error here
                print("Failed to initialize SpeechRecognizer: \(error)")
            }
        }
    }
    
    func drivePicRecognizer(_ videoFragments: [VideoFragment]) {
        let count = videoFragments.count
        for index in 0..<count {
            let fragment = videoFragments[index]
            let result = picRecognizer?.evaluate(bitmap: fragment.stillFrame)
            switch result {
            case .some(.success(let cloneCheckResult)):
                fragment.isPicCloned = cloneCheckResult.contains("clone")
            case .some(.failure):
                fragment.isPicCloned = false
            case .none:
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
                fragment.isPicCloned = cloneCheckResult.contains("clone")
            case .some(.failure):
                fragment.isAudioCloned = false
            case .none:
                fragment.isAudioCloned = false
            }
        }
    }
    
}
