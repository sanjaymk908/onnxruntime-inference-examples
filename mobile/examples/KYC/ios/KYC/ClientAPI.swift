//
//  ClientAPI.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 2/13/25.
//

import Foundation

public class ClientAPI {
    
    ///
    ///   These are the properties exposed by the SDK for client integration
    ///
    
    var selfieEmbedding: [Double]?
    var idProfileEmbedding: [Double]?
    
    // Probability that user selfie is real or fake per Trusource's liveness check
    var realProb: Double?
    var fakeProb: Double?
    
    // Probability of match b/w user selfie & ID profile pic
    var selfieIDprofileMatchProb: Double?
    
    // Is user above age 21 with an unexpired ID?
    var isUserAbove21: Bool?
    
    // When age verification fails (user is declared to be below 21), failure reason
    var failureReason: ageVerificationResult?
    enum ageVerificationResult: Error {
        case inDeterminate
        case above21
        case below21
        case expiredID
        case selfieIDProfileMismatch
        case failedToReadID
        case selfieInaccurate
    }
    
    required init() {
        failureReason = .inDeterminate
    }
}
