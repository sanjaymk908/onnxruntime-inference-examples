//
//  HomeViewController.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/9/24.
//

import Lumina
import UIKit
import AVFoundation
import AVKit

class HomeScreenViewController: LuminaViewController, LuminaDelegate, UITextFieldDelegate {

    private var permissionManager = PermissionManager.shared
    
    override init() {
        super.init()
        // Add self as LuminaDelegate
        self.delegate = self
        LuminaViewController.loggingLevel = .critical
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setCancelButton(visible: false)
        showPromptsForPermissionDeniedCase(true) // do reset location string
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        createTransparentView(view)
        showPromptsForPermissionDeniedCase(false)
        permissionManager.initialize { [weak self] in
            guard let self = self else {return}
            updateLabels()
            showPromptsForPermissionEnabledCase()
        }
        permissionManager.requestCameraPermission()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func createTransparentView(_ parent: UIView) {
       addDoubleTapHandler()
        if (scanPromptLabel == nil) {
            transparentView.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(transparentView)
            if let widthConstraint = self.view.constraints.first(where: { $0.firstAnchor == self.view.widthAnchor }) {
                // Get the constant value of the width constraint
                let widthValue = widthConstraint.constant
                // Center the transparent view in the screen
                NSLayoutConstraint.activate([
                    transparentView.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
                    transparentView.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
                    transparentView.widthAnchor.constraint(equalToConstant: widthValue - 100),
                    transparentView.heightAnchor.constraint(equalToConstant: 512)
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
            
            updateLabels()
            
            // Add a tap gesture recognizer to dismiss the keyboard
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            view.addGestureRecognizer(tapGestureRecognizer)
        }
    }
    
    // MARK :- Private
    
    private let transparentView = RoundedCornersView()
    private var scanPromptLabel: UILabel!
    private let GenericMLError = "Error identifying picture or audio"
    private let RecordMessage = "Press record to start"
    private let loadingLine = UIView()
    
    private func updateLabels() {
        let labelFont = UIFont.systemFont(ofSize: 18, weight: UIFont.Weight.bold)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: labelFont as Any,
        ]

        let labelAttributedPlaceholder = NSAttributedString(string: RecordMessage, attributes: labelAttributes)
        scanPromptLabel.attributedText = labelAttributedPlaceholder
    }
    
    @objc func handleTap() {
        view.endEditing(true)
    }
    
    private func showPromptsForPermissionDeniedCase(_ resetLocation: Bool) {
        displayMessage("Cannot proceed without camera permission!")
        setShutterButton(visible: false)
    }
    
    private func showPromptsForPermissionEnabledCase() {
        displayMessage("")
        setShutterButton(visible: true)
    }
    
    private func createLoadingIndicator() {
        // Set up the loading line
        loadingLine.backgroundColor = UIColor.blue
        loadingLine.frame = CGRect(x: 0, y: view.frame.height - 3, width: view.frame.width, height: 3)
        view.addSubview(loadingLine)
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
    
    private func displayMessage(_ message: String) {
        textPrompt = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            // Clear prompt after 4 seconds
            self.scanPromptLabel.text = self.textPrompt
        }
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
    override func layoutSubviews() {
        super.layoutSubviews()
        //layer.cornerRadius = 10 // Adjust the value to change the corner radius
        self.clipsToBounds = true
        
        // Set the background color to clear
        self.backgroundColor = UIColor.clear
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        // Set the white stroke color
        UIColor.white.setStroke()
        
        // Create a UIBezierPath for each corner border
        let corner1Path = UIBezierPath()
        corner1Path.move(to: CGPoint(x: 0, y: 0))
        corner1Path.addLine(to: CGPoint(x: 0, y: 20))
        corner1Path.move(to: CGPoint(x: 0, y: 0))
        corner1Path.addLine(to: CGPoint(x: 20, y: 0))
        // Set the line width to make it bolder
        corner1Path.lineWidth = 8.0
        corner1Path.stroke()
        
        let corner2Path = UIBezierPath()
        corner2Path.move(to: CGPoint(x: rect.width, y: 0))
        corner2Path.addLine(to: CGPoint(x: rect.width - 20, y: 0))
        corner2Path.move(to: CGPoint(x: rect.width, y: 0))
        corner2Path.addLine(to: CGPoint(x: rect.width, y: 20))
        // Set the line width to make it bolder
        corner2Path.lineWidth = 8.0
        corner2Path.stroke()
        
        let corner3Path = UIBezierPath()
        corner3Path.move(to: CGPoint(x: rect.width, y: rect.height))
        corner3Path.addLine(to: CGPoint(x: rect.width, y: rect.height - 20))
        corner3Path.move(to: CGPoint(x: rect.width, y: rect.height))
        corner3Path.addLine(to: CGPoint(x: rect.width - 20, y: rect.height))
        // Set the line width to make it bolder
        corner3Path.lineWidth = 8.0
        corner3Path.stroke()
        
        let corner4Path = UIBezierPath()
        corner4Path.move(to: CGPoint(x: 0, y: rect.height))
        corner4Path.addLine(to: CGPoint(x: 0, y: rect.height - 20))
        corner4Path.move(to: CGPoint(x: 0, y: rect.height))
        corner4Path.addLine(to: CGPoint(x: 20, y: rect.height))
        // Set the line width to make it bolder
        corner4Path.lineWidth = 8.0
        corner4Path.stroke()
    }
}

extension HomeScreenViewController {
  
  func captured(stillImage: UIImage, livePhotoAt: URL?, depthData: Any?, from controller: LuminaViewController) {
      //UIImageWriteToSavedPhotosAlbum(stillImage, nil, nil, nil)
      // crop input image to constrain it to restaurant name scan area
      let screenSize: CGRect = self.view.frame
      let luminaAddedOffsetAtTop = 70.0
      // this toRect kindof works CGRect(x: 400, y: 200, width: 100, height: 400)
      let croppedRect = CGRect(x: transparentView.frame.origin.y - luminaAddedOffsetAtTop,
                               y: transparentView.frame.origin.x,
                               width: transparentView.frame.width,
                               height: transparentView.frame.height)
      if let croppedImage = cropImage(stillImage,
                                      toRect: croppedRect,
                                      viewWidth: screenSize.width,
                                      viewHeight: screenSize.height) {
          // Use croppedImage for ML flow
          print("\(croppedImage)")
      }
  }
    
  // Below is src code from apple.com for cropping(). It is VERY non-intuitive because:
  //     1. The image has MANY more pixels than the transparentView (ie scanning) frame
  //        So, you have to scale (imageViewScale) to reach the scanning view
  //     2. Input image pixels are laid out in row order. So, the first row is at
  //        (0,0) (0,1) (0,2)...(o,W-1) & so on. So, the cropRect you provide has
  //        be inverted. With its x offset and width inverted with the y offset &
  //        height.
  //     3. And to make things even more interesting, the static stuff Lumina adds
  //        to the top of its view pushes everything UP by luminaAddedOffsetAtTop.
  //        So, the y origin of the cropRect box has to be reduced by this amount.
  func cropImage(_ inputImage: UIImage, toRect cropRect: CGRect, viewWidth: CGFloat, viewHeight: CGFloat) -> UIImage? {
    let imageViewScale = max(inputImage.size.width / viewWidth,
                             inputImage.size.height / viewHeight)


    // Scale cropRect to handle images larger than shown-on-screen size
    let cropZone = CGRect(x:cropRect.origin.x * imageViewScale,
                         y:cropRect.origin.y * imageViewScale,
                         width:cropRect.size.width * imageViewScale,
                         height:cropRect.size.height * imageViewScale)


    // Perform cropping in Core Graphics
    guard let cutImageRef: CGImage = inputImage.cgImage?.cropping(to:cropZone) else {
        return nil
    }


    // Return image to UIImage
    let croppedImage: UIImage = UIImage(cgImage: cutImageRef)
    guard let rotatedImage = rotateImageToPortrait(croppedImage) else {
        return nil
    }
    return rotatedImage
  }
    
  private func rotateImageToPortrait(_ image: UIImage) -> UIImage? {
      // Calculate the new size for the rotated image
      let newSize = CGSize(width: image.size.height, height: image.size.width)
      
      // Create a new graphics context
      UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
      guard let context = UIGraphicsGetCurrentContext() else { return nil }
      
      // Move the origin to the middle of the new image so the rotation happens around the center
      context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
      
      // Rotate the context by 90 degrees (π/2 radians)
      context.rotate(by: .pi / 2)
      
      // Draw the image onto the context, offsetting it so the center is aligned
      image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
      
      // Get the new image from the context
      let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
      
      // Clean up the graphics context
      UIGraphicsEndImageContext()
      
      return rotatedImage
  }

}
