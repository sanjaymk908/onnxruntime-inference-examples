//
//  FaceOverlayView.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 11/4/24.
//

import Lumina
import UIKit
import Vision

class FaceOverlayView: UIView {
    private var ovalPath: UIBezierPath?
    private var silhouettePath: UIBezierPath?
    private var timer: Timer?
    private let checkInterval: TimeInterval = 0.4 // 400 milliseconds
    private let faceCoverageThreshold: CGFloat = 0.5 // 50% lower limit
    private let maxFaceCoverageThreshold: CGFloat = 0.75 // 75%  upper limit
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
            setNeedsDisplay()
        }
    }
    
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
        isUserInteractionEnabled = false  // Allow touch events to pass through
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
        
        // Draw the oval
        let ovalRect = CGRect(x: ovalX, y: ovalY, width: ovalWidth, height: ovalHeight)
        ovalPath = UIBezierPath(ovalIn: ovalRect)
        
        context.setStrokeColor(currentColor.cgColor)
        context.setLineWidth(24)
        context.setLineDash(phase: 0, lengths: [10, 5]) // Dashed line pattern
        ovalPath?.stroke()
        
        // Draw the face silhouette (neck)
        silhouettePath = UIBezierPath()
        let neckY = ovalRect.maxY - 30
        let neckWidth: CGFloat = 30
        silhouettePath?.move(to: CGPoint(x: ovalRect.midX - neckWidth / 2, y: neckY))
        silhouettePath?.addLine(to: CGPoint(x: ovalRect.midX + neckWidth / 2, y: neckY))
        
        context.setStrokeColor(UIColor.white.cgColor) // Neck line color
        context.setLineWidth(24)
        silhouettePath?.stroke()
        
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
        
        // Only process if the image has changed
        guard currentImage != lastProcessedImage else { return }
        lastProcessedImage = currentImage

        do {
            try sequenceHandler.perform([faceDetectionRequest], on: currentImage)
            
            guard let results = faceDetectionRequest.results,
                  let face = results.first else {
                updateOvalColor(for: 0) // No face detected
                return
            }
            
            // Get the bounding box from the face observation
            var faceBounds = face.boundingBox
            
            // Convert the normalized coordinates to the image's coordinate space
            // NOTE :- the currentImage (croppedImage ie) has a messed up size. So,
            //         we use transparentView's frame size instead.
            faceBounds = convertToImageCoordinates(faceBounds: faceBounds,
                                                   imageSize: homeScreenViewController?.transparentView.frame.size ??
                                                                                      currentImage.extent.size)
            
            // Calculate the coverage
            let coverage = calculateCoverage(faceBounds: faceBounds)
            // Update ClientAPI probabilities based on coverage
            overrideClientAPIProbs(for: coverage)
            
            // Update the oval color based on the coverage
            updateOvalColor(for: coverage)
        } catch {
            print("Face detection failed: \(error)")
            updateOvalColor(for: 0)
        }
    }

    // Helper method to convert normalized face bounding box to image coordinates
    private func convertToImageCoordinates(faceBounds: CGRect, imageSize: CGSize) -> CGRect {
        // Flip the y-origin since the bounding box is in normalized coordinates (bottom-left)
        let x = faceBounds.origin.x * imageSize.width
        let y = (1 - faceBounds.origin.y - faceBounds.height) * imageSize.height // Flipping the y-coordinate
        let width = faceBounds.size.width * imageSize.width
        let height = faceBounds.size.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }

    
    private func getCurrentImage() -> CIImage? {
        guard let latestImage = homeScreenViewController?.latestUIImage else {
            print("No image frame available")
            return nil
        }
        // Convert UIImage to CIImage
        guard let ciImage = CIImage(image: latestImage) else {
            print("Failed to convert UIImage to CIImage")
            return nil
        }
        return ciImage
    }

    
    private func calculateCoverage(faceBounds: CGRect) -> CGFloat {
        guard let ovalPath = ovalPath else { return 0 }
        let ovalBounds = ovalPath.bounds
        let intersectionArea = ovalBounds.intersection(faceBounds).area
        let ovalArea = ovalBounds.area
        return intersectionArea / ovalArea
    }
    
    private func updateOvalColor(for coverage: CGFloat) {
        currentColor = (coverage >= faceCoverageThreshold &&
                        coverage <= maxFaceCoverageThreshold)  ? .green : .red
        
        // Flash effect
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0.5
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.alpha = 1.0
            }
        }
    }
    
    private func overrideClientAPIProbs(for coverage: CGFloat) {
        let isRealImage = (coverage >= faceCoverageThreshold &&
                           coverage <= maxFaceCoverageThreshold)  ? true : false
        // update clientAPI Apple API fields real vs fake probabilities
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
