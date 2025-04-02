//
//  FacialCheck.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 4/1/25.
//

import LocalAuthentication
import Security
import UIKit

class FacialCheck {
    private let serviceName = "com.yella.kyc"
    private let picIDRecognizer = PicIDRecognizer()
    private let similarityMatcher = SimilarityMatcher()
    
    // MARK: - Secure Storage Methods
    
    /// Securely stores a biometric embedding using the Secure Enclave
    public func storeBiometrics(_ embedding: [Double], key: String) throws {
        guard let data = try? JSONSerialization.data(withJSONObject: embedding) else {
            throw KeychainError.encodingError
        }
        
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlocked,
            [.privateKeyUsage, .userPresence],
            nil
        )!
        
        let context = LAContext()
        context.localizedReason = "Authenticate to store biometric data securely"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: data,
            kSecUseAuthenticationContext as String: context
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Retrieves a stored biometric embedding
    public func retrieveBiometrics(key: String) throws -> [Double]? {
        let context = LAContext()
        context.localizedReason = "Authenticate to access biometric data"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
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
    
    /// Check if both embeddings exist in storage
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
    
    /// Clears all stored biometric data
    public func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Authentication Logic
    
    /// Performs biometric authentication with live selfie
    public func performAuth(inputSelfie: CIImage, clientAPI: ClientAPI, picRecognizer: PicRecognizer, completion: @escaping (Bool, Double?) -> Void) {
        picIDRecognizer.recognizeID(from: inputSelfie, clientAPI: clientAPI) { [weak self] result in
            switch result {
            case .success(let idInfo):
                guard let profilePic = idInfo.userProfilePic else {
                    completion(false, nil)
                    return
                }
                
                self?.processEmbedding(for: profilePic, clientAPI: clientAPI, picRecognizer: picRecognizer) { inputEmbedding in
                    self?.validateAgainstStoredEmbeddings(inputEmbedding, completion: completion)
                }
                
            case .failure(let error):
                print("Authentication failed: \(error.localizedDescription)")
                completion(false, nil)
            }
        }
    }
    
    // MARK: - Management Methods
    
    /// Removes specific biometric data
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
            let success = maxSimilarity >= self.similarityMatcher.THRESHOLD
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
