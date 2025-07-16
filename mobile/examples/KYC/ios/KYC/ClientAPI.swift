//
//  ClientAPI.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 2/13/25.
//

import Foundation
import SwiftUI

@objc public protocol ClientAPIDelegate: AnyObject {
    func completedKYC(clientAPI: ClientAPI)
}

@objc public class ClientAPI: NSObject {
    @objc public static let shared = ClientAPI()
    @objc public weak var delegate: ClientAPIDelegate?
        
    override private init() {
        super.init()
        failureReason = .inDeterminate
    }
    
    @objc private func completedKYC() {
        delegate?.completedKYC(clientAPI: self)
    }
    
    ///
    /// Public method
    ///
        
    // See below for possible client usage scenarios
    @objc public func start(fullScreen: Bool = true) -> UIViewController {
        let contentView = ContentView()
        let hostingController = UIHostingController(rootView: contentView)
        if fullScreen {
            hostingController.modalPresentationStyle = .fullScreen
        }
        return hostingController
    }
    
    @objc public func resetKYCState() {
        selfieEmbedding = nil
        idProfileEmbedding = nil
        realProb = 0.0
        fakeProb = 0.0
        realProbAppleAPI = 0.0
        fakeProbAppleAPI = 0.0
        selfieIDprofileMatchProb = 0.0
        isUserAbove21 = false
        isSelfieReal = false
        failureReason = .inDeterminate
    }
    
    @objc public func clearBiometrics() {
        let facialCheck = FacialCheck()
        do {
            try facialCheck.clearAll() // Clear all locally stored biometrics
            failureReason = .inDeterminate
        } catch {
            failureReason = .internalError
        }
    }
    
    ///
    ///   These are the properties exposed by the SDK for client integration
    ///
    
    public internal(set) var selfieEmbedding: [Double]?
    public internal(set) var idProfileEmbedding: [Double]?
    
    // Probability that user selfie is real or fake per Trusource's liveness check
    @objc public internal(set) var realProb: Double = 0.0
    @objc public internal(set) var fakeProb: Double = 0.0
    
    // Probability that user selfie is real or fake per Apple's APIs
    @objc public internal(set) var realProbAppleAPI: Double = 0.0
    @objc public internal(set) var fakeProbAppleAPI: Double = 0.0
    
    // Probability of match b/w user selfie & ID profile pic
    @objc public internal(set) var selfieIDprofileMatchProb: Double = 0.0
    
    // Is user above age 21 with an unexpired ID?
    @objc public internal(set) var isUserAbove21: Bool = false
    
    // Is selfie fake or real
    // Is user above age 21 with an unexpired ID?
    @objc public internal(set) var isSelfieReal: Bool = false
    
    // What was the similarity prob?
    @objc public internal(set) var similarity: Double = 0.0
    
    // When age verification fails (user is declared to be below 21), failure reason
    @objc public internal(set) var failureReason: AgeVerificationResult = .inDeterminate
    @objc public enum AgeVerificationResult: Int {
        case inDeterminate
        case above21
        case below21
        case expiredID
        case selfieIDProfileMismatch
        case failedToReadID
        case selfieInaccurate
        case internalError
    }
}

// Extension to make completedKYC() accessible within the TruKYC framework
extension ClientAPI {
    func internalCompletedKYC() {
        completedKYC()
    }
}

///
/// Possible client usage of the start() method in invoking the recommended TruKYC UI
///

//  In a UIKit app
//let viewController = ClientAPI.shared.start()
//present(viewController, animated: true)
//

// Or for embedded use
//let embeddedViewController = ClientAPI.shared.start(fullScreen: false)
//addChild(embeddedViewController)
//view.addSubview(embeddedViewController.view)
//embeddedViewController.didMove(toParent: self)
//

// Or in a SwiftUI app
//struct ContentView: View {
//    var body: some View {
//        ClientViewControllerRepresentable()
//    }
//}
//
//struct ClientViewControllerRepresentable: UIViewControllerRepresentable {
//    func makeUIViewController(context: Context) -> UIViewController {
//        return ClientAPI.shared.start()
//    }
//    
//    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
//}

///
/// Complete sample client usage showing instantiation, start() & completedKYC() usage
///

//class ViewController: UIViewController, ClientAPIDelegate {
//   override func viewDidLoad() {
//       super.viewDidLoad()
//       ClientAPI.shared.delegate = self
//       let kycViewController = ClientAPI.shared.start()
//       present(kycViewController, animated: true)
//   }
//
//   func completedKYC(clientAPI: ClientAPI) {
//       print("KYC completed!")
//       // Handle KYC completion
//   }
//}


