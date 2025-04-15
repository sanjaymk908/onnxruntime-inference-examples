//
//  FaceOverlayView.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 11/4/24.
//

import UIKit
import Vision

class FaceOverlayView: UIView {
    private var ovalPath: UIBezierPath?
    private var timer: Timer?
    private let checkInterval: TimeInterval = 0.4 // 400 milliseconds
    private let faceCoverageThreshold: CGFloat = 0.5 // 50% lower limit
    private let maxFaceCoverageThreshold: CGFloat = 0.75 // 75% upper limit
    private let realProbForRealSelfie: Double = 0.99
    private let fakeProbForRealSelfie: Double = 0.01
    private let realProbForFakeSelfie: Double = 0.01
    private let fakeProbForFakeSelfie: Double = 0.99
    
    private var lastProcessedImage: CIImage?
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private let homeScreenViewController: HomeScreenViewController?
    private let clientAPI: ClientAPI
    
    private var currentColor: UIColor = .white {
        didSet {
            updateTransparentViewCorners()
            setNeedsDisplay()
        }
    }
    
    // Debounce variables for steady color changes
    private var lastUpdatedColor: UIColor = .white
    private var lastColorChangeTime: Date = Date()
    
    init(frame: CGRect, homeScreenViewController: HomeScreenViewController,
         clientAPI: ClientAPI) {
        self.homeScreenViewController = homeScreenViewController
        self.clientAPI = clientAPI
        super.init(frame: frame)
        setupView()
        startFaceDetectionTimer()
    }
    
    required init?(coder: NSCoder) {
        self.homeScreenViewController = nil
        self.clientAPI = ClientAPI.shared // expect to be unused
        super.init(coder: coder)
        setupView()
        startFaceDetectionTimer()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false // Allow touch events to pass through
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Save the initial state of the context
        context.saveGState()
        
        // Calculate oval dimensions
        let ovalWidth = bounds.width * 0.7 // 70% of the view width
        let ovalHeight = bounds.height * 0.8 // 80% of the view height
        let ovalX = (bounds.width - ovalWidth) / 2
        let ovalY: CGFloat = 20 // Top margin
        
        // Draw the oval with thicker dashed lines
        let ovalRect = CGRect(x: ovalX, y: ovalY, width: ovalWidth, height: ovalHeight)
        ovalPath = UIBezierPath(ovalIn: ovalRect)
        
        context.setStrokeColor(currentColor.cgColor)
        context.setLineWidth(48) // Increased thickness for dashed lines (2x original)
        context.setLineDash(phase: 0, lengths: [10, 5]) // Dashed line pattern
        ovalPath?.stroke()
        
        // Restore the initial state of the context
        context.restoreGState()
    }
    
    private func startFaceDetectionTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkFaceCoverage()
        }
    }
    
    private func checkFaceCoverage() {
        guard let currentImage = getCurrentImage() else { return }
        
        guard currentImage != lastProcessedImage else { return } // Only process if image has changed
        
        lastProcessedImage = currentImage
        
        do {
            try sequenceHandler.perform([faceDetectionRequest], on: currentImage)
            
            guard let results = faceDetectionRequest.results,
                  let faceObservation = results.first else {
                updateOvalColor(forCoveragePercentage: 0) // No face detected
                return
            }
            
            var faceBoundsNormalized = faceObservation.boundingBox
            
            faceBoundsNormalized = convertToImageCoordinates(faceBoundsNormalized,
                                                              imageSize:
                                                              homeScreenViewController?.transparentView.frame.size ??
                                                              currentImage.extent.size)
            
            let coveragePercentage = calculateCoverage(faceBoundsNormalized)
            
            overrideClientAPIProbs(forCoveragePercentage: coveragePercentage)
            updateOvalColor(forCoveragePercentage: coveragePercentage)
            
        } catch {
            print("Face detection failed with error \(error)")
            updateOvalColor(forCoveragePercentage: 0)
        }
    }

    private func convertToImageCoordinates(_ normalizedBounds: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalizedBounds.origin.x * imageSize.width
        let y = (1 - normalizedBounds.origin.y - normalizedBounds.height) * imageSize.height // Flip y-axis
        let width = normalizedBounds.width * imageSize.width
        let height = normalizedBounds.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func getCurrentImage() -> CIImage? {
        guard let latestImage = homeScreenViewController?.latestUIImage else { return nil }
        
        return CIImage(image: latestImage)
    }

    private func calculateCoverage(_ faceBoundsNormalized: CGRect) -> CGFloat {
        guard let ovalPathBounds = ovalPath?.bounds else { return 0 }
        
        let intersectionArea = ovalPathBounds.intersection(faceBoundsNormalized).area
        return intersectionArea / ovalPathBounds.area
    }

    // Updated debounce logic for holding color steady longer (800ms instead of changing too frequently)
    private func updateOvalColor(forCoveragePercentage coveragePercentage: CGFloat) {
        let now = Date()
        
        // Debounce logic: Update color only if 800ms have passed since the last change
        if now.timeIntervalSince(lastColorChangeTime) >= 0.8 {
            lastColorChangeTime = now
            
            // Determine the new color based on coverage percentage
            let newColor: UIColor = (coveragePercentage >= faceCoverageThreshold &&
                                     coveragePercentage <= maxFaceCoverageThreshold) ? .green : .red
            
            // Only update if the color has actually changed
            if newColor != lastUpdatedColor {
                lastUpdatedColor = newColor
                currentColor = newColor
                
                // Flash effect to indicate the change
                UIView.animate(withDuration: 0.2, animations: {
                    self.alpha = 0.5
                }) { _ in
                    UIView.animate(withDuration: 0.2) {
                        self.alpha = 1.0
                    }
                }
            }
        }
    }
    
    private func updateTransparentViewCorners() {
        guard let transparentView = homeScreenViewController?.transparentView as? RoundedCornersView else { return }
        
        // Update the corners' color dynamically
        transparentView.setCornerColor(currentColor)
    }
    
    private func overrideClientAPIProbs(forCoveragePercentage coveragePercentage: CGFloat) {
        let isRealImage = (coveragePercentage >= faceCoverageThreshold &&
                           coveragePercentage <= maxFaceCoverageThreshold)
        
        // Update clientAPI Apple API fields real vs fake probabilities
        if isRealImage {
            clientAPI.realProbAppleAPI = realProbForRealSelfie
            clientAPI.fakeProbAppleAPI = fakeProbForRealSelfie
        } else {
            clientAPI.realProbAppleAPI = realProbForFakeSelfie
            clientAPI.fakeProbAppleAPI = fakeProbForFakeSelfie
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

extension CGRect {
    var area: CGFloat {
        return width * height
    }
}

