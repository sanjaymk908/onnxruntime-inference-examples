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
  
    
  func setupVideoProcessor() {
      videoRecognizer = VideoRecognizer()
  }
  
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
    
  private func playVideo(from url: URL) {
      let player = AVPlayer(url: url)
      let playerViewController = AVPlayerViewController()
      playerViewController.player = player

      // Present the video player
      self.present(playerViewController, animated: true) {
          playerViewController.player?.play()
      }
  }
    
  func captured(videoAt: URL, from controller: LuminaViewController) {
      guard let videoRecognizer = videoRecognizer else {return}
      let videoProcessor = VideoProcessor(localURL: videoAt, videoRecognizer: videoRecognizer)
      playVideo(from: videoAt)
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
