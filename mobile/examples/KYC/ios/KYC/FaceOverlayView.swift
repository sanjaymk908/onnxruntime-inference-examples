//
//  FaceOverlayView.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 11/4/24.
//
//  PURPOSE: Overlays the camera feed for face framing guidance.
//  This version includes fixes for coordinate system mapping, dynamic probability scoring,
//  and crucial state management to ensure reliability upon repeated use (3rd and subsequent runs).
//

import UIKit
import Vision

class FaceOverlayView: UIView {
    private var ovalPath: UIBezierPath?
    private var timer: Timer?
    private let checkInterval: TimeInterval = 0.4
    private let minColorChangeDelay: TimeInterval = 0.8
    private let faceCoverageThreshold: CGFloat = 0.5
    private let maxFaceCoverageThreshold: CGFloat = 0.75
    
    private let realProbForRealSelfie: Double = 0.99
    private let fakeProbForRealSelfie: Double = 0.01
    private let realProbForFakeSelfie: Double = 0.01
    private let fakeProbForFakeSelfie: Double = 0.99
    
    private var lastProcessedImage: CIImage?
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()
    
    private var sequenceHandler: VNSequenceRequestHandler?
    
    private let homeScreenViewController: HomeScreenViewController?
    private let clientAPI: ClientAPI
    
    private var currentColor: UIColor = .white {
        didSet {
            updateTransparentViewCorners()
            setNeedsDisplay()
        }
    }
    
    private var lastUpdatedColor: UIColor = .white
    private var lastColorChangeTime: Date = Date()
    
    init(frame: CGRect, homeScreenViewController: HomeScreenViewController,
         clientAPI: ClientAPI) {
        self.homeScreenViewController = homeScreenViewController
        self.clientAPI = clientAPI
        super.init(frame: frame)
        setupView()
        
        self.sequenceHandler = VNSequenceRequestHandler()
        self.lastProcessedImage = nil
        
        startFaceDetectionTimer()
    }
    
    required init?(coder: NSCoder) {
        self.homeScreenViewController = nil
        self.clientAPI = ClientAPI.shared
        super.init(coder: coder)
        setupView()
        
        self.sequenceHandler = VNSequenceRequestHandler()
        self.lastProcessedImage = nil
        
        startFaceDetectionTimer()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        
        let ovalWidth = bounds.width * 0.7
        let ovalHeight = bounds.height * 0.8
        let ovalX = (bounds.width - ovalWidth) / 2
        let ovalY: CGFloat = 20
        
        let ovalRect = CGRect(x: ovalX, y: ovalY, width: ovalWidth, height: ovalHeight)
        ovalPath = UIBezierPath(ovalIn: ovalRect)
        
        context.setStrokeColor(currentColor.cgColor)
        context.setLineWidth(48)
        context.setLineDash(phase: 0, lengths: [10, 5])
        ovalPath?.stroke()
        
        context.restoreGState()
    }
    
    private func startFaceDetectionTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkFaceCoverage()
        }
    }
    
    private func checkFaceCoverage() {
        guard let currentImage = getCurrentImage(),
              let handler = sequenceHandler else {
            
            // DONT set probs to zero - just ignore this
            return
        }
        
        guard currentImage != lastProcessedImage else { return }
        lastProcessedImage = currentImage
        
        do {
            try handler.perform([faceDetectionRequest], on: currentImage)
            
            guard let results = faceDetectionRequest.results,
                  let faceObservation = results.first else {
                
                updateOvalColor(forCoveragePercentage: 0)
                overrideClientAPIProbs(forCoveragePercentage: 0)
                return
            }
            
            let faceBoundsImageCoordinates = VNImageRectForNormalizedRect(
                faceObservation.boundingBox,
                Int(currentImage.extent.width),
                Int(currentImage.extent.height)
            )
            
            let imageSize = currentImage.extent.size
            let viewSize = self.bounds.size
            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            
            let faceBoundsInView = CGRect(
                x: faceBoundsImageCoordinates.origin.x * scaleX,
                y: viewSize.height - (faceBoundsImageCoordinates.origin.y * scaleY) - (faceBoundsImageCoordinates.height * scaleY),
                width: faceBoundsImageCoordinates.width * scaleX,
                height: faceBoundsImageCoordinates.height * scaleY
            )
            
            let coveragePercentage = calculateCoverage(faceBoundsInView)
            
            overrideClientAPIProbs(forCoveragePercentage: coveragePercentage)
            updateOvalColor(forCoveragePercentage: coveragePercentage)
            
        } catch {
            updateOvalColor(forCoveragePercentage: 0)
            overrideClientAPIProbs(forCoveragePercentage: 0)
        }
    }
    
    private func convertToImageCoordinates(_ normalizedBounds: CGRect, imageSize: CGSize) -> CGRect {
        let x = normalizedBounds.origin.x * imageSize.width
        let y = (1 - normalizedBounds.origin.y - normalizedBounds.height) * imageSize.height
        let width = normalizedBounds.width * imageSize.width
        let height = normalizedBounds.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func getCurrentImage() -> CIImage? {
        guard let latestImage = homeScreenViewController?.latestUIImage else { return nil }
        
        return CIImage(image: latestImage)
    }
    
    private func calculateCoverage(_ faceBoundsInView: CGRect) -> CGFloat {
        guard let ovalPathBounds = ovalPath?.bounds else { return 0 }
        
        let intersectionArea = ovalPathBounds.intersection(faceBoundsInView).area
        return intersectionArea / ovalPathBounds.area
    }
    
    private func updateOvalColor(forCoveragePercentage coveragePercentage: CGFloat) {
        let now = Date()
        
        if now.timeIntervalSince(lastColorChangeTime) >= minColorChangeDelay {
            lastColorChangeTime = now
            
            let newColor: UIColor = (coveragePercentage >= faceCoverageThreshold &&
                                     coveragePercentage <= maxFaceCoverageThreshold) ? .green : .red
            
            if newColor != lastUpdatedColor {
                lastUpdatedColor = newColor
                currentColor = newColor
                
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
        
        transparentView.setCornerColor(currentColor)
    }
    
    private func overrideClientAPIProbs(forCoveragePercentage coveragePercentage: CGFloat) {
        let realProb = min(1.0, max(0.0, coveragePercentage))
        let fakeProb = 1.0 - realProb
        
        clientAPI.realProbAppleAPI = Double(realProb)
        clientAPI.fakeProbAppleAPI = Double(fakeProb)
    }
    
    deinit {
        timer?.invalidate()
        
        self.sequenceHandler = nil
        lastProcessedImage = nil
    }
}

extension CGRect {
    var area: CGFloat {
        return width * height
    }
}
