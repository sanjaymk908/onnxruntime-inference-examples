//
//  SimilarityMatcher.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 6/14/24.
//

import Foundation

class SimilarityMatcher {
    
    public let THRESHOLD: Double = 0.70
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
    
    public func cosineMatch() -> (Bool, Double) {
        guard let baselineVec = baselineVec, let testVec = testVec else { return (false, 0.0) }
        
        // Calculate dot product in Double
        let dotProduct: Double = zip(baselineVec, testVec).reduce(0.0) { result, vecs in
            result + (vecs.0 * vecs.1)
        }
        
        // Calculate magnitudes of both vectors in Double
        let baselineMagnitude: Double = baselineVec.reduce(0.0) { result, number in
            result + (number * number)
        }.squareRoot()
        
        let testMagnitude: Double = testVec.reduce(0.0) { result, number in
            result + (number * number)
        }.squareRoot()
        
        // Calculate cosine similarity and check against threshold
        let magnitude: Double = baselineMagnitude * testMagnitude
        let result: Double = dotProduct / magnitude
        let roundedResult = Double(round(100 * result) / 100)
        print("Cosine Matcher magnitude: \(roundedResult)")
        
        return (roundedResult >= THRESHOLD, roundedResult)
    }
}

