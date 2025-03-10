//
//  HomeScreenViewController+extensions.swift
//
//  Created by Sanjay Krishnamurthy on 8/14/24.
//

import AVKit
import AVFoundation
import Lumina
import UIKit

extension HomeScreenViewController {
  
  func setupVideoProcessor(_ completion: @escaping ((Bool) -> Void)) {
      videoRecognizer = VideoRecognizer(completion, clientAPI: clientAPI)
  }
  
  func captured(stillImage: UIImage, livePhotoAt: URL?, depthData: Any?, from controller: LuminaViewController) {
    resetState()
    let (resizedUIImage, croppedImage) = processCapturedImage(stillImage, shouldRotate: true)
    if let ciImage = CIImage(image: resizedUIImage) {
        imageRecognize(with: ciImage, withOriginalImage: croppedImage)
    }
  }
          
  func captured(videoAt: URL, from controller: LuminaViewController) {
  }
    
  // capture pixelBuffers here
  func streamed(videoFrame: UIImage, from controller: LuminaViewController) {
      let (_, croppedImage) = processCapturedImage(videoFrame, shouldRotate: false)
      self.latestUIImage = croppedImage
  }
    
  ///
  /// MARK :- priate methods, properties
  ///

  func resetState(_ force: Bool = false) {
    DispatchQueue.main.async { [weak self] in
        guard let self = self else {return}
        self.updateLabels(isStep1Complete() ? HomeScreenViewController.ScanIDMessage : HomeScreenViewController.ScanSelfieMessage)
        // This causes initial display to disapper-why??
        if  force {
            self.displayMessage("")
        }
    }
  }
    
  func resetInternalState() {
    step1Embs = []
    step2Embs = []
  }
    
  func initKYC() {
    clientAPI.delegate = self
  }

  private func processCapturedImage(_ inputImage: UIImage, shouldRotate: Bool = false) -> (UIImage, UIImage) {
    let screenSize: CGRect = self.view.frame
    // the captured pic has wrong orientation; account for this below
      var croppedRect: CGRect = CGRect()
      if shouldRotate {
          croppedRect = CGRect(x: transparentView.frame.origin.y - 40.0,
                               y: transparentView.frame.origin.x - 12.0,
                               width: transparentView.frame.height - 1.0,
                               height: transparentView.frame.width - 4.0)
      } else {
          croppedRect = CGRect(x: transparentView.frame.origin.x,
                               y: transparentView.frame.origin.y,
                               width: transparentView.frame.width,
                               height: transparentView.frame.height)
      }
    if let croppedImage = cropImage(inputImage,
                                    toRect: croppedRect,
                                    viewWidth: screenSize.width,
                                    viewHeight: screenSize.height,
                                    shouldRotate: shouldRotate) {
        // Resize it & convert to bitmap
        // Resize the UIImage to 224x224
        let resizedUIImage = croppedImage.resized(to: CGSize(width: 224, height: 224))
        return (resizedUIImage, croppedImage)
    }
    return (inputImage, inputImage) // on failure
  }
    
  private func imageRecognize(with bitmap: CIImage, withOriginalImage: UIImage) {
      if !self.isStep1Complete() {
          step1Driver(with: bitmap, withOriginalImage: withOriginalImage)
      } else {
          step2Driver(with: bitmap, withOriginalImage: withOriginalImage)
      }
  }
    
  private func step1Driver(with bitmap: CIImage, withOriginalImage: UIImage) {
    // Do normal Step 1 processing to check for real selfie vs printed fake
    guard let picRecognizer = videoRecognizer?.picRecognizer else {
        DispatchQueue.main.async {
            let message = "Error: PicRecognizer is not initialized"
            self.displayMessageAndPic(message, capturedPic: withOriginalImage)
        }
        return
    }
    let result = picRecognizer.evaluate(bitmap: bitmap)
    switch result {
    case .success(let cloneCheckResult):
        DispatchQueue.main.async {
            self.displayMessageAndPic(cloneCheckResult.0, capturedPic: withOriginalImage)
            self.step1Embs = cloneCheckResult.1
            self.updateLabels(HomeScreenViewController.ScanIDMessage)
            self.position = .back
        }
    case .failure(let error):
        DispatchQueue.main.async {
            let message = "Error: \(error.localizedDescription)"
            self.displayMessageAndPic(message, capturedPic: withOriginalImage)
        }
    }
      
    // Now get focused contour of face & embeddings for it
    let picIDRecognizer = PicIDRecognizer()
      picIDRecognizer.recognizeID(from: bitmap, clientAPI: clientAPI) { result in
        switch result {
        case .success(let idInformation):
            if let userProfilePic = idInformation.userProfilePic {
                let step1Image = userProfilePic
                let result = picRecognizer.getEmbeddings(bitmap: step1Image)
                switch result {
                case .success(let step1Embs):
                    self.step1Embs = step1Embs
                case .failure(let error):
                    self.displayMessage(error.localizedDescription)
                }
            } else {
                self.displayMessage("No profile picture found.")
                self.clientAPI.failureReason = .selfieInaccurate
            }
        case .failure(let error):
            self.displayMessage("Failed to recognize ID with error: \(error)")
        }
      }
  }
    
  private func step2Driver(with bitmap: CIImage, withOriginalImage: UIImage) {
    let picIDRecognizer = PicIDRecognizer()
      picIDRecognizer.recognizeID(from: bitmap, clientAPI: clientAPI) { [self] result in
        switch result {
        case .success(let idInformation):
            print("ID Information:")
            print("First Name: \(idInformation.firstName ?? "N/A")")
            print("Last Name: \(idInformation.lastName ?? "N/A")")
            print("Date of Birth: \(idInformation.dateOfBirth.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "N/A")")
            print("ID Number: \(idInformation.idNumber ?? "N/A")")
            print("Expiry: \(idInformation.expirationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "N/A")")
              
            if let userProfilePic = idInformation.userProfilePic {
                DispatchQueue.main.async {
                    let message = "Profile picture extracted successfully"
                    self.displayMessageAndPic(message, capturedPic: withOriginalImage) // was withOriginalImage
                }
                let step2Image = userProfilePic
                let similarityMatcher = SimilarityMatcher()
                similarityMatcher.storeBaselineVec(self.step1Embs ?? [])
                guard let picRecognizer = self.videoRecognizer?.picRecognizer else {
                    DispatchQueue.main.async {
                        let message = "Error: PicRecognizer is not initialized"
                        self.displayMessageAndPic(message, capturedPic: withOriginalImage)
                    }
                    self.resetInternalState()
                    return
                }
                let result = picRecognizer.getEmbeddings(bitmap: step2Image)
                switch result {
                case .success(let step2Embs):
                    similarityMatcher.storeTestVec(step2Embs)
                    let (match, prob) = similarityMatcher.cosineMatch()
                    clientAPI.selfieIDprofileMatchProb = prob
                    if match {
                        var message: String = ""
                        if idInformation.isNotUnderAge == nil {
                            message = "ID or Selfie inaccurate - please rescan"
                        } else {
                            message = (idInformation.isNotUnderAge ?? false) ?
                                      "User is above 21" :
                                      (idInformation.isExpired ? "ID has expired" : "User is below 21")
                        }
                        self.displayMessage(message)
                    } else {
                        self.displayMessage("Selfie & ID pictures do not match!")
                        clientAPI.failureReason = .selfieIDProfileMismatch
                    }
                    self.position = .front
                case .failure(let error):
                    self.displayMessage(error.localizedDescription)
                }
            } else {
                self.displayMessage("No profile picture found.")
            }
              
        case .failure(let error):
            self.displayMessage("Failed to recognize ID with error: \(error)")
        }
        clientAPI.internalCompletedKYC()  // execute BEFORE resetting any ClientAPI state
        self.resetInternalState()
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
  private func cropImage(_ inputImage: UIImage,
                         toRect cropRect: CGRect,
                         viewWidth: CGFloat,
                         viewHeight: CGFloat,
                         shouldRotate: Bool) -> UIImage? {
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
    if shouldRotate {
        guard let rotatedImage = rotateImageToPortrait(croppedImage) else {
            return nil
        }
        return rotatedImage
    } else {
        return croppedImage
    }
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
