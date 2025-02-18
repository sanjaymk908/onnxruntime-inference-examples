//
//  ClientAPI.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 2/13/25.
//

import Foundation
import SwiftUI

public protocol ClientAPIDelegate: AnyObject {
    func completedKYC(clientAPI: ClientAPI)
}

public class ClientAPI {
    public static let shared = ClientAPI()
    public weak var delegate: ClientAPIDelegate?
        
    private init() {
        failureReason = .inDeterminate
    }
    
    ///
    /// Public method
    ///
        
    // See below for possible client usage scenarios
    public func start(fullScreen: Bool = true) -> UIViewController {
        let contentView = ContentView()
        let hostingController = UIHostingController(rootView: contentView)
        if fullScreen {
            hostingController.modalPresentationStyle = .fullScreen
        }
        return hostingController
    }
    
    private func completedKYC() {
        delegate?.completedKYC(clientAPI: self)
    }
    
    ///
    ///   These are the properties exposed by the SDK for client integration
    ///
    
    public internal(set) var selfieEmbedding: [Double]?
    public internal(set) var idProfileEmbedding: [Double]?
    
    // Probability that user selfie is real or fake per Trusource's liveness check
    public internal(set) var realProb: Double?
    public internal(set) var fakeProb: Double?
    
    // Probability of match b/w user selfie & ID profile pic
    public internal(set) var selfieIDprofileMatchProb: Double?
    
    // Is user above age 21 with an unexpired ID?
    public internal(set) var isUserAbove21: Bool?
    
    // When age verification fails (user is declared to be below 21), failure reason
    public internal(set) var failureReason: ageVerificationResult?
    public enum ageVerificationResult: Error {
        case inDeterminate
        case above21
        case below21
        case expiredID
        case selfieIDProfileMismatch
        case failedToReadID
        case selfieInaccurate
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


