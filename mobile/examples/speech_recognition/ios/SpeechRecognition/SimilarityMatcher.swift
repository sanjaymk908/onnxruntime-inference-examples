//
//  SimilarityMatcher.swift
//  SpeechRecognition
//
//  Created by Sanjay Krishnamurthy on 6/14/24.
//

import Foundation

class SimilarityMatcher {
    
    private let THRESHOLD:Double = 0.85
    private var baselineVec:[Float]?
    private var testVec:[Float]?
    
    init() {
    }
    
    public func storeBaselineVec(_ floatArray: [Float]) {
        baselineVec = floatArray
    }
    
    public func storeTestVec(_ floatArray: [Float]) {
        testVec = floatArray
    }
    
    public func clearAllInputs() {
        baselineVec = nil
        testVec = nil
    }
    
    public func doesBaselineVecExist() -> Bool {
        return baselineVec != nil
    }
    
    public func doBothVecsExist() -> Bool {
        return (baselineVec != nil && testVec != nil)
    }
    
    public func cosineMatch() -> Bool {
        guard let baselineVec = baselineVec, let testVec = testVec else {return false}
        
        // Iterate over both vecs & create dot product
        var dotProduct: Double = 0.0
        for vecs in zip(baselineVec, testVec) {
            let baselineElement = vecs.0
            let testElement = vecs.1
            dotProduct += Double((Double(baselineElement) * Double(testElement)))
        }
        
        // Calculate magnitudes of both vectors
        var baselineMagnitude: Double = 0.0
        var testMagnitude: Double = 0.0
        baselineMagnitude = baselineVec.reduce(baselineMagnitude, {(result, number) in
                                                return Double(result) + Double(number) * Double(number)}).squareRoot()
        testMagnitude = testVec.reduce(testMagnitude, {(result, number) in
                                                return Double(result) + Double(number) * Double(number)}).squareRoot()
        let magnitude: Double = baselineMagnitude * testMagnitude
        let result: Double = dotProduct / magnitude
        print("Cosine Matcher magnitude: \(result)")
        return result >= THRESHOLD
    }
    
}
