//
//  VideoRecognizer.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/14/24.
//

import Foundation

class VideoRecognizer {
    
    var picRecognizer: PicRecognizer?
    
    init(_ completion: @escaping ((Bool) -> Void), clientAPI: ClientAPI) {
        let dispatchGroup = DispatchGroup()
        var isSuccessful = true  // Track success status
        
        dispatchGroup.enter()
        setupPicRecognizer(completion: { success in
                if !success { isSuccessful = false }
                dispatchGroup.leave()
        }, clientAPI: clientAPI)
        
        // Notify when both setup tasks are done
        dispatchGroup.notify(queue: .main) {
            completion(isSuccessful) // Returns true if both succeeded, false if any failed
        }
    }

    private func setupPicRecognizer(completion: @escaping ((Bool) -> Void), clientAPI: ClientAPI) {
        DispatchQueue.global().async {
            do {
                let picRecognizer = try PicRecognizer(clientAPI)
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
    
}
