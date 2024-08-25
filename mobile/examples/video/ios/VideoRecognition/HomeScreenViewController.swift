//
//  HomeViewController.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/9/24.
//

import AVKit
import AVFoundation
import Lumina
import UIKit

class HomeScreenViewController: LuminaViewController, LuminaDelegate, UITextFieldDelegate {

    private var permissionManager = PermissionManager.shared
    var videoProcessor: VideoProcessor?
    var videoRecognizer: VideoRecognizer?
    
    let ISCLONEDMESSAGE = "Video has cloned fragments"
    let ISREALMESSAGE = "Video has no cloned fragments"
    
    override init() {
        super.init()
        // Add self as LuminaDelegate
        self.delegate = self
        LuminaViewController.loggingLevel = .critical
        self.setupVideoProcessor()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setCancelButton(visible: false)
        self.captureLivePhotos = false
        self.recordsVideo = true
        self.streamFrames = false
        self.streamingModels = []
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
            
            updateLabels()
            
            // Add a tap gesture recognizer to dismiss the keyboard
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            view.addGestureRecognizer(tapGestureRecognizer)
        }
    }
    
    // MARK :- Private
    
    let transparentView = RoundedCornersView()
    private var scanPromptLabel: UILabel!
    private let GenericMLError = "Error identifying picture or audio"
    private let RecordMessage = "Hold down record button for video capture"
    private let loadingLine = UIView()
    var audioPlayer: AVAudioPlayer?
    
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
    
    func displayMessage(_ message: String) {
        textPrompt = message
    }
    
    private func displayCapturedPic(_ capturedPic: UIImage) {
        // Create UIImageView to display the capturedPic
        let imageView = UIImageView(image: capturedPic)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add the imageView to the transparentView
        transparentView.addSubview(imageView)
        
        // Set constraints to make the imageView fill the transparentView
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: transparentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: transparentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: transparentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: transparentView.trailingAnchor)
        ])
        
        // Create a dismiss button
        let dismissButton = UIButton(type: .custom)
        dismissButton.setTitle("X", for: .normal)
        dismissButton.setTitleColor(.red, for: .normal)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissCapturedPic), for: .touchUpInside)
        
        // Add the dismiss button to the transparentView
        transparentView.addSubview(dismissButton)
        
        // Set constraints for the dismiss button in the top right corner
        NSLayoutConstraint.activate([
            dismissButton.topAnchor.constraint(equalTo: transparentView.topAnchor, constant: 10),
            dismissButton.trailingAnchor.constraint(equalTo: transparentView.trailingAnchor, constant: -10)
        ])
    }

    @objc private func dismissCapturedPic() {
        // Remove the imageView and dismiss button from the transparentView
        for subview in transparentView.subviews {
            subview.removeFromSuperview()
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
