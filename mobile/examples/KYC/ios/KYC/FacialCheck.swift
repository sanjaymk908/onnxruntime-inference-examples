//
//  FacialCheck.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 4/1/25.
//

import Security
import UIKit

@objc public class FacialCheck: NSObject {
    private let serviceName = "com.yella.kyc"
    private let picIDRecognizer = PicIDRecognizer()
    private let similarityMatcher = SimilarityMatcher()
    private let THRESHOLD: Double = 0.80  // NOTE :- distinct from SimilarityMatch.THRESHOLD
    
    // MARK: - Secure Storage Methods
    
    /// Securely stores a biometric embedding without authentication checks
    public func storeBiometrics(_ embedding: [Double], key: String) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: embedding) else {
            throw KeychainError.encodingError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Retrieves a stored biometric embedding without authentication checks
    public func retrieveBiometrics(key: String) throws -> [Double]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = item as? Data,
              let embedding = try? JSONSerialization.jsonObject(with: data) as? [Double] else {
            throw KeychainError.decodingError
        }
        
        return embedding
    }
    
    /// Clears all stored biometric data without authentication checks
    @objc public func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Removes specific biometric data without authentication checks
    func clearBiometrics(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - Status Check Method
    
    /// Check if both embeddings exist in storage without authentication checks
    public func areBothEmbeddingsStored() -> Bool {
        do {
            let selfieEmbeddingExists = try retrieveBiometrics(key: "selfieEmbedding") != nil
            let idProfileEmbeddingExists = try retrieveBiometrics(key: "idProfileEmbedding") != nil
            
            return selfieEmbeddingExists && idProfileEmbeddingExists
        } catch {
            print("Error checking embeddings storage status: \(error)")
            return false
        }
    }

    // MARK: - Authentication Logic
    
    /// Performs biometric authentication with live selfie (no security checks)
    public func performAuth(inputEmbedding: [Double], completion: @escaping (Bool, Double?) -> Void) {
        validateAgainstStoredEmbeddings(inputEmbedding, completion: completion)
    }

    // MARK: - Private Helpers
    
    private func processEmbedding(for image: CIImage, clientAPI: ClientAPI, picRecognizer: PicRecognizer, completion: @escaping ([Double]) -> Void) {
        let result = picRecognizer.getEmbeddings(bitmap: image)
        switch result {
        case .success(let embedding):
            completion(embedding)
        case .failure(let error):
            print("Embedding extraction failed: \(error.localizedDescription)")
            completion([])
        }
    }
    
    private func validateAgainstStoredEmbeddings(_ inputEmbedding: [Double], completion: @escaping (Bool, Double?) -> Void) {
        var maxSimilarity = 0.0
        
        let checkGroup = DispatchGroup()
        
        ["selfieEmbedding", "idProfileEmbedding"].forEach { key in
            checkGroup.enter()
            
            do {
                if let storedEmbedding = try retrieveBiometrics(key: key) {
                    similarityMatcher.storeBaselineVec(storedEmbedding)
                    similarityMatcher.storeTestVec(inputEmbedding)
                    let (_, score) = similarityMatcher.cosineMatch()
                    maxSimilarity = max(maxSimilarity, score)
                }
            } catch {
                print("Error retrieving \(key): \(error)")
            }
            
            checkGroup.leave()
        }
        
        checkGroup.notify(queue: .main) {
            let success = maxSimilarity >= self.THRESHOLD
            completion(success, maxSimilarity)
        }
    }
}

// MARK: - Keychain Error Handling

enum KeychainError: Error {
    case encodingError
    case decodingError
    case unhandledError(status: OSStatus)

    var localizedDescription: String {
        switch self {
        case .encodingError:
            return "Failed to encode biometric data"
        case .decodingError:
            return "Failed to decode stored data"
        case .unhandledError(let status):
            return "Keychain error with code \(status)"
        }
    }
}

