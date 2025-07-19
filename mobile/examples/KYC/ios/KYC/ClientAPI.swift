//
//  ClientAPI.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 2/13/25.
//

//
//  ClientAPI.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 2/13/25.
//

//
// MARK: - Example: Using TruKYC in your App
//

/// =======================================================================================
/// ▶️ How to Invoke the TruKYC Flow
///
/// Call `ClientAPI.shared.start()` to launch the TruKYC onboarding UI.
/// The returned `UIViewController` should be presented or embedded in your app's UI.
/// Assign a `ClientAPIDelegate` beforehand to receive completion results.
///
///
/// --- UIKit Example (Full-Screen Modal Presentation) ---
///
///     class ViewController: UIViewController, ClientAPIDelegate {
///         override func viewDidLoad() {
///             super.viewDidLoad()
///
///             // Register delegate
///             ClientAPI.shared.delegate = self
///
///             // Launch TruKYC flow
///             let kycVC = ClientAPI.shared.start()
///             present(kycVC, animated: true)
///         }
///
///         // Called when KYC is complete
///         func completedKYC(result: KYCResult) {
///             print("📬 KYC Completed")
///             print("✅ Real score: \(result.realProb)")
///             print("🔗 Match score: \(result.selfieIDprofileMatchProb)")
///             print("👤 Selfie real: \(result.isSelfieReal)")
///             print("🍷 Over 21: \(result.isUserAbove21)")
///             print("❌ Failure Reason: \(result.failureReason)")
///         }
///     }
///
///
/// --- UIKit Embedded Example (Non-Fullscreen) ---
///
///     let embeddedViewController = ClientAPI.shared.start(fullScreen: false)
///     addChild(embeddedViewController)
///     view.addSubview(embeddedViewController.view)
///     embeddedViewController.didMove(toParent: self)
///
///
/// --- SwiftUI Wrapper Example ---
///
///     struct TruKYCView: View {
///         var body: some View {
///             TruKYCRepresentable()
///         }
///     }
///
///     struct TruKYCRepresentable: UIViewControllerRepresentable {
///         func makeUIViewController(context: Context) -> UIViewController {
///             return ClientAPI.shared.start()
///         }
///
///         func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
///     }
///
/// =======================================================================================
/// 📌 Notes:
/// - The `KYCResult` passed to your delegate is an immutable snapshot of all KYC output.
/// - Avoid accessing properties from `ClientAPI.shared`—they are now internal-only.
/// - Call `ClientAPI.shared.clearBiometrics()` to delete any stored biometrics locally.
/// =======================================================================================


import Foundation
import SwiftUI

// MARK: - Delegate Protocol

@objc public protocol ClientAPIDelegate: AnyObject {
    func completedKYC(result: KYCResult)
}

// MARK: - Final KYC Result

@objc public class KYCResult: NSObject {
    public let selfieEmbedding: [Double]?
    public let idProfileEmbedding: [Double]?

    public let realProb: Double
    public let fakeProb: Double

    public let realProbAppleAPI: Double
    public let fakeProbAppleAPI: Double

    public let selfieIDprofileMatchProb: Double

    public let isUserAbove21: Bool
    public let is2StepKYC: Bool
    public let isSelfieReal: Bool

    public let failureReason: ClientAPI.AgeVerificationResult

    init(
        selfieEmbedding: [Double]?,
        idProfileEmbedding: [Double]?,
        realProb: Double,
        fakeProb: Double,
        realProbAppleAPI: Double,
        fakeProbAppleAPI: Double,
        selfieIDprofileMatchProb: Double,
        isUserAbove21: Bool,
        is2StepKYC: Bool,
        isSelfieReal: Bool,
        failureReason: ClientAPI.AgeVerificationResult
    ) {
        self.selfieEmbedding = selfieEmbedding
        self.idProfileEmbedding = idProfileEmbedding
        self.realProb = realProb
        self.fakeProb = fakeProb
        self.realProbAppleAPI = realProbAppleAPI
        self.fakeProbAppleAPI = fakeProbAppleAPI
        self.selfieIDprofileMatchProb = selfieIDprofileMatchProb
        self.isUserAbove21 = isUserAbove21
        self.is2StepKYC = is2StepKYC
        self.isSelfieReal = isSelfieReal
        self.failureReason = failureReason
    }
}

// MARK: - Public API

@objc public class ClientAPI: NSObject {
    
    // Singleton instance
    @objc public static let shared = ClientAPI()
    
    // Client delegate
    @objc public weak var delegate: ClientAPIDelegate?
    
    // Internal delegate (used by TruKYC internally)
    @objc weak var internalDelegate: ClientAPIDelegate?

    // MARK: - Lifecycle
    
    override private init() {
        super.init()
        failureReason = .inDeterminate
    }

    // MARK: - Public Methods

    /// Launch the TruKYC flow
    @objc public func start(fullScreen: Bool = true) -> UIViewController {
        resetKYCState()
        
        let contentView = ContentView()
        let hostingController = UIHostingController(rootView: contentView)
        
        if fullScreen {
            hostingController.modalPresentationStyle = .fullScreen
        }
        
        return hostingController
    }

    /// Clear all KYC state (manually callable)
    @objc public func resetKYCState() {
        selfieEmbedding = nil
        idProfileEmbedding = nil
        realProb = 0.0
        fakeProb = 0.0
        realProbAppleAPI = 0.0
        fakeProbAppleAPI = 0.0
        selfieIDprofileMatchProb = 0.0
        isUserAbove21 = false
        is2StepKYC = false
        isSelfieReal = false
        failureReason = .inDeterminate
    }

    /// Clear on-device biometrics
    @objc public func clearBiometrics() {
        let facialCheck = FacialCheck()
        do {
            try facialCheck.clearAll()
            failureReason = .inDeterminate
        } catch {
            failureReason = .internalError
        }
    }

    // MARK: - Internal Completion Flow

    /// Internal method to invoke the completion callback
    func internalCompletedKYC() {
        completedKYC()
    }

    private func completedKYC() {
        let result = generateKYCResult()
        internalDelegate?.completedKYC(result: result)
        delegate?.completedKYC(result: result)
    }

    /// Create a snapshot of the current KYC result
    private func generateKYCResult() -> KYCResult {
        return KYCResult(
            selfieEmbedding: selfieEmbedding,
            idProfileEmbedding: idProfileEmbedding,
            realProb: realProb,
            fakeProb: fakeProb,
            realProbAppleAPI: realProbAppleAPI,
            fakeProbAppleAPI: fakeProbAppleAPI,
            selfieIDprofileMatchProb: selfieIDprofileMatchProb,
            isUserAbove21: isUserAbove21,
            is2StepKYC: is2StepKYC,
            isSelfieReal: isSelfieReal,
            failureReason: failureReason
        )
    }

    // MARK: - Internal State (now private to framework)

    internal var selfieEmbedding: [Double]? // or just: var selfieEmbedding: [Double]?
    internal var idProfileEmbedding: [Double]?

    internal var realProb: Double = 0.0
    internal var fakeProb: Double = 0.0

    internal var realProbAppleAPI: Double = 0.0
    internal var fakeProbAppleAPI: Double = 0.0

    internal var selfieIDprofileMatchProb: Double = 0.0

    internal var isUserAbove21: Bool = false
    internal var is2StepKYC: Bool = false
    internal var isSelfieReal: Bool = false
    internal var failureReason: AgeVerificationResult = .inDeterminate

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

