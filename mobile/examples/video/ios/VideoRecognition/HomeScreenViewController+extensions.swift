//
//  HomeScreenViewController+extensions.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/14/24.
//

import AVKit
import AVFoundation
import Lumina
import UIKit

extension HomeScreenViewController {
  
  func setupVideoProcessor(_ completion: @escaping ((Bool) -> Void)) {
      videoRecognizer = VideoRecognizer(completion)
  }
  
  func captured(stillImage: UIImage, livePhotoAt: URL?, depthData: Any?, from controller: LuminaViewController) {
    let (resizedUIImage, croppedImage) = processCapturedImage(stillImage, shouldRotate: true)
    if let ciImage = CIImage(image: resizedUIImage) {
        imageRecognize(with: ciImage, withOriginalImage: croppedImage)
    }
  }
          
  func captured(videoAt: URL, from controller: LuminaViewController) {
      guard let videoRecognizer = videoRecognizer else {return}
      print("Starting video processing...")
      self.videoProcessor = VideoProcessor(localURL: videoAt,
                                           videoRecognizer: videoRecognizer,
                                           processStillFrame: { inputImage in
                                              return self.processCapturedImage(inputImage)
                                           },
                                           completion: { outputURL, isCloned, isClonedType in
          guard let outputURL = outputURL else {return}
          DispatchQueue.main.async {
              self.playAudio(from: outputURL)
              switch isClonedType {
              case .IsPicCloned(let fragments):
                  self.displayMessageAndFragments(self.ISPICCLONEDMESSAGE, fragments: fragments)
              case .IsAudioCloned(let fragments):
                  self.displayMessageAndFragments(self.ISAUDIOCLONEDMESSAGE, fragments: fragments)
              case .IsBothCloned(let fragments):
                  self.displayMessageAndFragments(self.ISBOTHCLONEDMESSAGE, fragments: fragments)
              case .NotCloned(let fragments):
                  self.displayMessageAndFragments(self.ISREALMESSAGE, fragments: fragments)
              }
          }
      })
  }
    
  ///
  /// MARK :- priate methods, properties
  ///

  private func processCapturedImage(_ inputImage: UIImage, shouldRotate: Bool = false) -> (UIImage, UIImage) {
    let screenSize: CGRect = self.view.frame
    // the captured pic has wrong orientation; account for this below
    let croppedRect = CGRect(x: transparentView.frame.origin.y - 40.0,
                                y: transparentView.frame.origin.x - 12.0,
                                width: transparentView.frame.height - 1.0,
                                height: transparentView.frame.width - 4.0)
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
    
  private func playAudio(from url: URL) {
      do {
          // Initialize the AVAudioPlayer with the output URL
          audioPlayer = try AVAudioPlayer(contentsOf: url)
          
          // Prepare to play the audio
          audioPlayer?.prepareToPlay()
          
          // Play the audio
          audioPlayer?.play()
          
          print("Playing audio from \(url)")
      } catch {
          print("Failed to play audio: \(error)")
      }
  }
    
  private func imageRecognize(with bitmap: CIImage, withOriginalImage: UIImage) {
    let result = videoRecognizer?.picRecognizer?.evaluate(bitmap: bitmap)
    switch result {
    case .some(.success(let cloneCheckResult)):
        DispatchQueue.main.async {
            self.displayMessageAndPic(cloneCheckResult, capturedPic: withOriginalImage)
        }
    case .some(.failure(let error)):
        DispatchQueue.main.async {
        let message = "Error: \(error)"
        self.displayMessageAndPic(message, capturedPic: withOriginalImage)
        }
    case .none:
        DispatchQueue.main.async {
        let message = "Error: PicRecognizer is not initialized"
        self.displayMessageAndPic(message, capturedPic: withOriginalImage)
        }
    }
  }
    
  private func playVideo(from url: URL) {
      let player = AVPlayer(url: url)
      let playerViewController = AVPlayerViewController()
      playerViewController.player = player

      // Present the video player
      self.present(playerViewController, animated: true) {
          playerViewController.player?.play()
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
