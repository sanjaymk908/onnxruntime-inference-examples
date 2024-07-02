//
//  PicCapture.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import UIKit
import AVFoundation

class PicCapture: NSObject {
    typealias PictureData = Data
    typealias PictureDataCallback = (Result<PictureData, Error>) -> Void

    private let captureSession = AVCaptureSession()
    private let imageOutput = AVCapturePhotoOutput()

    private var pictureDataCallback: PictureDataCallback?

    override init() {
        super.init()
        setupCaptureSession()
    }

    func captureImage(completion: @escaping PictureDataCallback) {
        pictureDataCallback = completion
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        imageOutput.capturePhoto(with: settings, delegate: self)
        
        captureSession.startRunning()
    }

    private func setupCaptureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.addInput(input)

            captureSession.addOutput(imageOutput)
        } catch {
            print("Error setting up capture session: \(error)")
        }
    }
}

extension PicCapture: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            pictureDataCallback?(.failure(error))
        } else if let imageData = photo.fileDataRepresentation() {
            let resizedImage = UIImage(data: imageData)?.resized(to: CGSize(width: 224, height: 224))
            
            if let resizedImageData = resizedImage?.jpegData(compressionQuality: 1.0) {
                pictureDataCallback?(.success(resizedImageData))
            } else {
                pictureDataCallback?(.failure(PicCaptureError.failedToEncodeImage))
            }
        } else {
            pictureDataCallback?(.failure(PicCaptureError.failedToCapture))
        }
        
        captureSession.stopRunning()
    }
}

enum PicCaptureError: Error {
    case failedToCapture
    case failedToEncodeImage
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
