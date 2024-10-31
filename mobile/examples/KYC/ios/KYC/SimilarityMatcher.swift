//
//  SimilarityMatcher.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 6/14/24.
//

import Foundation

class SimilarityMatcher {
    
    private let THRESHOLD: Float = 0.55
    private var baselineVec: [Double]?
    private var testVec: [Double]?
    
    init() {}
    
    public func storeBaselineVec(_ doubleArray: [Double]) {
        baselineVec = doubleArray
    }
    
    public func storeTestVec(_ doubleArray: [Double]) {
        testVec = doubleArray
    }
    
    public func clearAllInputs() {
        baselineVec = nil
        testVec = nil
    }
    
    public func doesBaselineVecExist() -> Bool {
        return baselineVec != nil
    }
    
    public func doBothVecsExist() -> Bool {
        return baselineVec != nil && testVec != nil
    }
    
    public func cosineMatch() -> Bool {
        guard let baselineVec = baselineVec, let testVec = testVec else { return false }
        
        // Convert baseline and test vectors to Float arrays
        let baselineFloatVec = baselineVec.map { Float($0) }
        let testFloatVec = testVec.map { Float($0) }
        
        // Calculate dot product in Float
        let dotProduct: Float = zip(baselineFloatVec, testFloatVec).reduce(0.0) { result, vecs in
            result + (vecs.0 * vecs.1)
        }
        
        // Calculate magnitudes of both vectors in Float
        let baselineMagnitude: Float = baselineFloatVec.reduce(0.0) { result, number in
            result + (number * number)
        }.squareRoot()
        
        let testMagnitude: Float = testFloatVec.reduce(0.0) { result, number in
            result + (number * number)
        }.squareRoot()
        
        // Calculate cosine similarity and check against threshold
        let magnitude: Float = baselineMagnitude * testMagnitude
        let result: Float = dotProduct / magnitude
        print("Cosine Matcher magnitude: \(result)")
        
        return result >= THRESHOLD
    }
}

