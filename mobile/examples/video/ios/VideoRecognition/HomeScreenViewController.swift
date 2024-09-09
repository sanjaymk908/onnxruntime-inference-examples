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
    
    let ISAUDIOCLONEDMESSAGE = "Video has cloned audio fragments"
    let ISPICCLONEDMESSAGE = "Video has cloned pic fragments"
    let ISBOTHCLONEDMESSAGE = "Video has cloned pic & cloned audio fragments"
    let ISREALMESSAGE = "Video has no cloned fragments"
    let ISFRAGMENTAUDIOCLONEDMESSAGE = "Fragment has cloned audio"
    let ISFRAGMENTPICCLONEDMESSAGE = "Fragment has cloned pic"
    let ISFRAGMENTBOTHCLONEDMESSAGE = "Fragment has cloned pic & cloned audio"
    let ISFRAGMENTREALMESSAGE = "Fragment has no cloned media"
    let MLMODELLOADINGFAILED = "Internal error loading ML Models"
    
    override init() {
        super.init()
        // Add self as LuminaDelegate
        self.delegate = self
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
        self.recordsVideo = true
        self.streamFrames = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        createTransparentView(view)
        updateLabels()
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
    private static let RecordMessage = "Hold down record button for video capture"
    private let loadingLine = UIView()
    var audioPlayer: AVAudioPlayer?
    var currentFragments: [VideoFragment]?
    
    func updateLabels(_ message: String = RecordMessage) {
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
    
    func displayFragmentMessage(_ fragment: VideoFragment) {
        // use updateLabels() to show per-fragment message below pic
        if fragment.isAudioCloned && fragment.isPicCloned {
            updateLabels(ISFRAGMENTBOTHCLONEDMESSAGE)
        } else if fragment.isAudioCloned {
            updateLabels(ISFRAGMENTAUDIOCLONEDMESSAGE)
        } else if fragment.isPicCloned {
            updateLabels(ISFRAGMENTPICCLONEDMESSAGE)
        } else {
            updateLabels(ISFRAGMENTREALMESSAGE)
        }
    }
    
    private func displayCapturedPic(_ capturedPic: UIImage) {
        let imageView = createImageView(with: capturedPic)
        transparentView.addSubview(imageView)
        setupImageViewConstraints(imageView)
        
        let dismissButton = createDismissButton()
        transparentView.addSubview(dismissButton)
        setupDismissButtonConstraints(dismissButton)
        
        // create replay button iff this is a video recording
        if isVideoRecording() {
            let replayButton = createReplayButton()
            transparentView.addSubview(replayButton)
            setupReplayButtonConstraints(replayButton)
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

    private func createDismissButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle("X", for: .normal)
        button.setTitleColor(.red, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissCapturedPic), for: .touchUpInside)
        return button
    }

    private func setupDismissButtonConstraints(_ button: UIButton) {
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: transparentView.topAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: transparentView.trailingAnchor, constant: -10)
        ])
    }

    private func createReplayButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle("∞", for: .normal)
        button.setTitleColor(.green, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 30)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(replayTapped), for: .touchUpInside)
        return button
    }

    private func setupReplayButtonConstraints(_ button: UIButton) {
        NSLayoutConstraint.activate([
            button.bottomAnchor.constraint(equalTo: transparentView.bottomAnchor, constant: -10),
            button.trailingAnchor.constraint(equalTo: transparentView.trailingAnchor, constant: -10)
        ])
    }

    @objc private func replayTapped() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        
        if let url = audioPlayer?.url {
            playAudio(from: url)
        }
        
        replayStillframes()
    }

    private func replayStillframes() {
        for subview in transparentView.subviews {
            if subview is UIImageView {
                subview.removeFromSuperview()
            }
        }
        
        if let fragments = currentFragments {
            displayMessageAndFragments(textPrompt, fragments: fragments)
        }
    }

    @objc private func dismissCapturedPic() {
        // Remove the imageView and dismiss button from the transparentView
        for subview in transparentView.subviews {
            subview.removeFromSuperview()
        }
        resetState(true) // force text prompt above pic to be reset
    }

    func displayMessageAndPic(_ message: String, capturedPic: UIImage) {
        // Display the message using displayMessage()
        displayMessage(message)
        
        // Display the captured picture using displayCapturedPic()
        displayCapturedPic(capturedPic)
    }
    
    func displayMessageAndFragments(_ message: String, fragments: [VideoFragment]) {
        // Display the message using displayMessage()
        displayMessage(message)
        
        for (index, fragment) in fragments.enumerated() {
            let pic = fragment.stillFrame
            let displayTime = Double(videoProcessor?.AUDIOSNIPPETLENGTH ?? 5)

            // Delay the display based on the index of the fragment
            DispatchQueue.main.asyncAfter(deadline: .now() + displayTime * Double(index)) {
                self.displayCapturedPic(UIImage(ciImage: pic))
                self.displayFragmentMessage(fragment)
            }
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
