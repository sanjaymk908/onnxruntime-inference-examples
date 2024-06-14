//
//  SimilarityMatcher.swift
//  SpeechRecognition
//
//  Created by Sanjay Krishnamurthy on 6/14/24.
//

import Foundation

class SimilarityMatcher {
    
    private let THRESHOLD:Float = 0.70
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
    
    public func doesBaselineVecExist() -> Bool {
        return baselineVec != nil
    }
    
    public func doBothVecsExist() -> Bool {
        return (baselineVec != nil && testVec != nil)
    }
    
    public func cosineMatch() -> Bool {
        guard let baselineVec = baselineVec, let testVec = testVec else {return false}
        
        // Iterate over both vecs & create dot product
        var dotProduct: Float = 0.0
        for vecs in zip(baselineVec, testVec) {
            let baselineElement = vecs.0
            let testElement = vecs.1
            dotProduct += (baselineElement * testElement)
        }
        
        // Calculate magnitudes of both vectors
        var baselineMagnitude: Float = 0.0
        var testMagnitude: Float = 0.0
        baselineMagnitude = baselineVec.reduce(baselineMagnitude, {(result, number) in
                                                return result + number * number})
        testMagnitude = testVec.reduce(testMagnitude, {(result, number) in
                                                return result + number * number})
        baselineMagnitude = baselineMagnitude.squareRoot()
        testMagnitude = testMagnitude.squareRoot()
        let magnitude = baselineMagnitude * testMagnitude
        let result = dotProduct / magnitude
        print("Cosine Matcher magnitude: \(result)")
        return result >= THRESHOLD
    }
    
}
