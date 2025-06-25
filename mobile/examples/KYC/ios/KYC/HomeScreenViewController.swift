//
//  HomeViewController.swift
//
//  Created by Sanjay Krishnamurthy on 8/9/24.
//

import AVKit
import AVFoundation
import CoreImage
import Lumina
import SwiftUI
import UIKit

class HomeScreenViewController: LuminaViewController, LuminaDelegate, UITextFieldDelegate, ClientAPIDelegate {
    var videoRecognizer: VideoRecognizer?
    let MLMODELLOADINGFAILED = "Internal error loading ML Models"
    
    override init() {
        super.init()
        // Add self as LuminaDelegate
        self.delegate = self
        initKYC()
        LuminaViewController.loggingLevel = .critical
        startLoadingIndicator()
        self.setupVideoProcessor() { isSuccessful in
            self.stopLoadingIndicator()
            if !isSuccessful {
                self.displayMessage(self.MLMODELLOADINGFAILED)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setCancelButton(visible: false)
        self.captureLivePhotos = false
        self.streamDepthData = false
        self.recordsVideo = false
        self.streamFrames = true
        self.position = .front
        // startCamera() was originally put in to capture video frames in LuminaDelegate (self ie)
        // But doing it on the main thread here is not a good idea - it slows down initial load
        //startCamera()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQRCodeDismissal),
            name: .qrCodeDismissed,
            object: nil
        )
        // Make the view controller the first responder to detect motion events
        self.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Always reload overlays on reappearance
        DispatchQueue.main.async {
            self.resetOverlayViews()
        }
    }
    
    @objc private func handleQRCodeDismissal() {
        // If KYC successful, store biometrics securely
        if (clientAPI.isSelfieReal && clientAPI.isUserAbove21) {
            if let selfieEmbedding = clientAPI.selfieEmbedding,
               let idProfileEmbedding = clientAPI.idProfileEmbedding {
                do {
                    try facialCheck.storeBiometrics(selfieEmbedding, key: SELFIE_EMBEDDING_STORE_KEY)
                    try facialCheck.storeBiometrics(idProfileEmbedding, key: IDPROFILE_EMBEDDING_STORE_KEY)
                    displayMessage("Selfie,id profile stored securely!")
                } catch {
                    print("Error occurred storing embeddings securely: \(error)")
                }
            }
        }
        
        // Reset KYC state if needed
        clientAPI.resetKYCState()
        self.resetInternalState()
        
        // Force reload overlays
        DispatchQueue.main.async {
            self.resetOverlayViews()
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
        
    // Respond to shake gestures
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            handleShake()
        }
    }
    
    @objc private func handleShake() {
        do {
            try facialCheck.clearAll() // Clear all locally stored biometrics
            displayMessage("Stored biometrics cleared.")
        } catch {
            displayMessage("Failed to clear biometrics: \(error.localizedDescription)")
        }
    }
    
    private func resetOverlayViews() {
        // When QR Code view is presented (or any new view) & flow returns from that new view,
        // viewDidAppear() triggers this method. For some reason scanPromptLabel doesnt appear.
        // So, we force it to reappear by deleting it here. It will be added fresh in
        // createTransparentView()
        if scanPromptLabel != nil {
            scanPromptLabel.removeFromSuperview()
            scanPromptLabel = nil
        }
        self.createTransparentView(self.view)
        self.setupFaceOverlay()
        self.updateLabels(HomeScreenViewController.ScanSelfieMessage)
        self.view.bringSubviewToFront(self.transparentView)
    }
    
    func completedKYC(clientAPI: ClientAPI) {
        print("Completed TruKYC Processing!")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            self.presentQRVerification(clientAPI: self.clientAPI)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func createTransparentView(_ parent: UIView) {
       addDoubleTapHandler()
        if (scanPromptLabel == nil) {
            transparentView.translatesAutoresizingMaskIntoConstraints = false
            if !parent.subviews.contains(transparentView) {
                parent.addSubview(transparentView)
            }
            if let widthConstraint = self.view.constraints.first(where: { $0.firstAnchor == self.view.widthAnchor }) {
                // Get the constant value of the width constraint
                let widthValue = widthConstraint.constant
                // Center the transparent view in the screen
                NSLayoutConstraint.activate([
                    transparentView.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
                    transparentView.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
                    transparentView.widthAnchor.constraint(equalToConstant: widthValue - 50),
                    transparentView.heightAnchor.constraint(equalToConstant: widthValue - 50) // keep it square
                ])
            }
            
            // Create and add the label below the transparent view
            scanPromptLabel = UILabel()
            let labelFont = UIFont.systemFont(ofSize: 18, weight: UIFont.Weight.bold)
            scanPromptLabel.font = labelFont
            scanPromptLabel.textColor = UIColor.white
            scanPromptLabel.textAlignment = .center
            parent.addSubview(scanPromptLabel)
            scanPromptLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scanPromptLabel.topAnchor.constraint(equalTo: transparentView.bottomAnchor, constant: 10),
                scanPromptLabel.centerXAnchor.constraint(equalTo: transparentView.centerXAnchor)
            ])
            
            // Add a tap gesture recognizer to dismiss the keyboard
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            view.addGestureRecognizer(tapGestureRecognizer)
        }
    }
    
    private func presentQRVerification(clientAPI: ClientAPI) {
        // Calculate QR code size based on view dimensions
        let viewSize = view.bounds.size
        let qrCodeSize = CGSize(
            width: viewSize.width * 0.8,  // 80% of view width
            height: viewSize.height * 0.4 // 40% of view height
        )

        // Generate QR code using KYCQRCodeGenerator
        guard let qrCodeImage = KYCQRCodeGenerator.generateQRCode(from: clientAPI, size: qrCodeSize) else {
            print("Failed to generate QR code")
            return
        }

        // Assume selfieImage is available in clientAPI (replace with actual logic)
        guard let selfieImage = self.selfieImage else {
            print("Selfie image is missing")
            return
        }

        // Create the SwiftUI view
        presentQRCodeContent(
            selfieImage: selfieImage,
            qrCodeImage: qrCodeImage,
            isVerified: (clientAPI.isUserAbove21 && clientAPI.isSelfieReal)
        )
    }
    
    func presentQRCodeContent(selfieImage: UIImage, qrCodeImage: UIImage?, isVerified: Bool) {
        let qrCodeContentView = QRCodeContentView(
            selfieImage: selfieImage,
            qrCodeImage: qrCodeImage,
            isVerified: isVerified
        )

        // Present the SwiftUI view directly
        let hostingController = UIHostingController(rootView: qrCodeContentView)
        hostingController.modalPresentationStyle = .fullScreen // Ensures viewDidAppear is called on dismissal
        hostingController.modalTransitionStyle = .crossDissolve
        self.present(hostingController, animated: true, completion: nil)
    }
    
    // MARK :- Public
    
    public var clientAPI: ClientAPI = ClientAPI.shared
    
    // MARK :- Private
    
    private let DISPLAY_IMAGE_DURATION: TimeInterval = 3.0 // 3 seconds
    private let SELFIE_EMBEDDING_STORE_KEY: String = "selfieEmbedding"
    private let IDPROFILE_EMBEDDING_STORE_KEY: String = "idProfileEmbedding"
    private var permissionManager = PermissionManager.shared
    private var faceOverlayView: FaceOverlayView?
    let transparentView = RoundedCornersView()
    private var scanPromptLabel: UILabel!
    private let GenericMLError = "Error identifying picture or audio"
    static let ScanSelfieMessage = "Step 1 - take a selfie with face inside green oval"
    static let ScanIDMessage = "Step 2 - scan your DL/passport/State ID"
    private let loadingLine = UIView()
    var latestUIImage: UIImage?
    var selfieImage: UIImage?
    let facialCheck: FacialCheck = FacialCheck()
    
    @MainActor
    var step1Embs: [Double]? {
        didSet {
            removeFaceOverlay()
            clientAPI.selfieEmbedding = step1Embs
        }
    }
    var step2Embs: [Double]? {
        didSet {
            clientAPI.idProfileEmbedding = step2Embs
        }
    }
    
    @MainActor
    func setupFaceOverlay() {
        removeFaceOverlay()
        
        faceOverlayView = FaceOverlayView(frame: transparentView.bounds, homeScreenViewController: self,
                                          clientAPI: clientAPI)
        faceOverlayView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        if let faceOverlayView = faceOverlayView {
            transparentView.addSubview(faceOverlayView)
            transparentView.bringSubviewToFront(faceOverlayView)
        }
    }
    
    @MainActor
    private func removeFaceOverlay() {
        faceOverlayView?.removeFromSuperview()
        faceOverlayView = nil
    }
    
    func isStep1Complete() -> Bool {
        return (step1Embs != nil && step1Embs?.count ?? 0 > 0)
    }
    
    func updateLabels(_ message: String = ScanSelfieMessage) {
        let labelFont = UIFont.systemFont(ofSize: 18, weight: UIFont.Weight.bold)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: labelFont as Any,
        ]

        let labelAttributedPlaceholder = NSAttributedString(string: message, attributes: labelAttributes)
        scanPromptLabel.attributedText = labelAttributedPlaceholder
    }
    
    @objc func handleTap() {
        view.endEditing(true)
    }
    
    private func createLoadingIndicator() {
        // Set up the loading line
        loadingLine.backgroundColor = UIColor.blue
        loadingLine.frame = CGRect(x: 0, y: view.frame.height - 3, width: view.frame.width, height: 3)
        view.addSubview(loadingLine)
        view.bringSubviewToFront(loadingLine)
    }
    
    func startLoadingIndicator() {
        view.isUserInteractionEnabled = false
        createLoadingIndicator()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            UIView.animate(withDuration: 0.5, delay: 0, options: [.autoreverse, .repeat], animations: {
                self.loadingLine.frame.origin.x = self.view.frame.width - 100
            }, completion: nil)
        }
    }

    func stopLoadingIndicator() {
        view.isUserInteractionEnabled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            loadingLine.layer.removeAllAnimations()
        }
    }
    
    func displayMessage(_ message: String) {
        textPrompt = message
    }
    
    private func displayCapturedPic(_ capturedPic: UIImage) {
        let imageView = createImageView(with: capturedPic)
        transparentView.addSubview(imageView)
        setupImageViewConstraints(imageView)
        
        // Schedule auto-dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + DISPLAY_IMAGE_DURATION) {
            self.dismissCapturedPic()
        }
    }

    private func createImageView(with image: UIImage) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

    private func setupImageViewConstraints(_ imageView: UIImageView) {
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: transparentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: transparentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: transparentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: transparentView.trailingAnchor)
        ])
    }

    @objc func dismissCapturedPic() {
        // Remove the imageView from the transparentView
        for subview in transparentView.subviews {
            if subview is UIImageView {
                subview.removeFromSuperview()
            }
        }
        resetState(true) // force text prompt above pic to be reset
        // redraw oval silhouette for face
        if !isStep1Complete() {
            DispatchQueue.main.async {
                self.setupFaceOverlay()
            }
        }
    }

    func displayMessageAndPic(_ message: String, capturedPic: UIImage) {
        // Display the message using displayMessage()
        displayMessage(message)
        
        // Display the captured picture using displayCapturedPic()
        displayCapturedPic(capturedPic)
    }
    
    private func addDoubleTapHandler() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap))
        tapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func didDoubleTap() {
    }
}

class RoundedCornersView: UIView {
    private var cornerColor: UIColor = .white // Default corner color
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.clipsToBounds = true
        self.backgroundColor = UIColor.clear
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        // Use the dynamic corner color
        cornerColor.setStroke()
        
        // Create a UIBezierPath for each corner border
        let lineWidth: CGFloat = 12.0 // Keep thicker lines
        
        let corner1Path = UIBezierPath()
        corner1Path.move(to: CGPoint(x: 0, y: 0))
        corner1Path.addLine(to: CGPoint(x: 0, y: 20))
        corner1Path.move(to: CGPoint(x: 0, y: 0))
        corner1Path.addLine(to: CGPoint(x: 20, y: 0))
        corner1Path.lineWidth = lineWidth
        corner1Path.stroke()
        
        let corner2Path = UIBezierPath()
        corner2Path.move(to: CGPoint(x: rect.width, y: 0))
        corner2Path.addLine(to: CGPoint(x: rect.width - 20, y: 0))
        corner2Path.move(to: CGPoint(x: rect.width, y: 0))
        corner2Path.addLine(to: CGPoint(x: rect.width, y: 20))
        corner2Path.lineWidth = lineWidth
        corner2Path.stroke()
        
        let corner3Path = UIBezierPath()
        corner3Path.move(to: CGPoint(x: rect.width, y: rect.height))
        corner3Path.addLine(to: CGPoint(x: rect.width, y: rect.height - 20))
        corner3Path.move(to: CGPoint(x: rect.width, y: rect.height))
        corner3Path.addLine(to: CGPoint(x: rect.width - 20, y: rect.height))
        corner3Path.lineWidth = lineWidth
        corner3Path.stroke()
        
        let corner4Path = UIBezierPath()
        corner4Path.move(to: CGPoint(x: 0, y: rect.height))
        corner4Path.addLine(to: CGPoint(x: 0, y: rect.height - 20))
        corner4Path.move(to: CGPoint(x: 0, y: rect.height))
        corner4Path.addLine(to: CGPoint(x: 20, y: rect.height))
        corner4Path.lineWidth = lineWidth
        corner4Path.stroke()
    }
    
    func setCornerColor(_ color: UIColor) {
        self.cornerColor = color
        setNeedsDisplay() // Trigger a redraw with the new color
    }
}

extension CIImage {
    /// Converts the CIImage into a UIImage
    func toUIImage() -> UIImage? {
        let context = CIContext(options: nil) // Create a Core Image context
        if let cgImage = context.createCGImage(self, from: self.extent) {
            return UIImage(cgImage: cgImage) // Create UIImage from CGImage
        }
        return nil // Return nil if conversion fails
    }
}

