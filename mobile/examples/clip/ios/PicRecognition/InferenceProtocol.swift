//
//  InferenceProtocol.swift
//  SpeechRecognition
//
//  Created by Sanjay Krishnamurthy on 6/27/24.
//

import Foundation

protocol Evaluator {
    associatedtype InputType
    
    init() throws
    func evaluate(inputData: InputType) -> Result<String, Error>
}
