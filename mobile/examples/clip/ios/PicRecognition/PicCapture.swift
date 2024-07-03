//
//  PicCapture.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import UIKit
import AVFoundation

class PicCapture: NSObject {
    typealias PictureData = (Data, AVCapturePhoto)
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
        // Ensure the capture session is running
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        imageOutput.capturePhoto(with: settings, delegate: self)
    }

    private func setupCaptureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.beginConfiguration()
            captureSession.addInput(input)
            captureSession.addOutput(imageOutput)
            captureSession.commitConfiguration()
            captureSession.startRunning()
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
            var resizedImageData: Data?
            
            if let resizedImage = UIImage(data: imageData)?.resized(to: CGSize(width: 224, height: 224)) {
                resizedImageData = resizedImage.jpegData(compressionQuality: 1.0)
            }
            
            pictureDataCallback?(.success((resizedImageData ?? imageData, photo)))
        } else {
            pictureDataCallback?(.failure(PicCaptureError.failedToCapture))
        }
        
        DispatchQueue.main.async {
            self.captureSession.stopRunning()
        }
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
