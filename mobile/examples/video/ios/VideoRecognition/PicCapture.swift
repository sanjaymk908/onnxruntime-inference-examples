//
//  PicCapture.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/2/24.
//

import CoreImage
import UIKit
import AVFoundation

class PicCapture: NSObject {
    typealias PictureData = (CIImage, AVCapturePhoto)
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
    private func createImageData(from urlString: String, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = URL(string: urlString) else {
                completion(nil)
                return
            }
            do {
                let imageData = try Data(contentsOf: url)
                completion(imageData)
            } catch {
                print("Error loading image from URL: \(error)")
                completion(nil)
            }
        }
    }
    
    private func processImage(imageData: Data) -> CIImage? {
        guard let image = UIImage(data: imageData) else {
            return nil
        }
        
        // Convert UIImage to CIImage
        guard var ciImage = CIImage(image: image) else {
            return nil
        }
        
        let targetSize = CGSize(width: 224, height: 224)
        
        // Calculate scale factor to resize image to 224x224
        let scaleX = targetSize.width / ciImage.extent.size.width
        let scaleY = targetSize.height / ciImage.extent.size.height
        
        // Apply scaling using CIFilter
        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        return ciImage
    }

    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            pictureDataCallback?(.failure(error))
        // Use below for camera pics
        //} else if let imageData = photo.fileDataRepresentation() {
        //    processImageData(imageData: imageData, photo: photo)
        } else {
            createImageData(from: "https://yella.co.in/infer/cvd-samples/pics/zuck_real.png") { imageData in
                if let imageData = imageData {
                    self.processImageData(imageData: imageData, photo: photo)
                } else {
                    self.pictureDataCallback?(.failure(PicCaptureError.failedToCapture))
                }
            }
        }
        
        DispatchQueue.main.async {
            self.captureSession.stopRunning()
        }
    }
    
    private func processImageData(imageData: Data, photo: AVCapturePhoto) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let ciImage = self.processImage(imageData: imageData) {
                DispatchQueue.main.async {
                    self.pictureDataCallback?(.success((ciImage, photo)))
                }
            } else {
                DispatchQueue.main.async {
                    self.pictureDataCallback?(.failure(PicCaptureError.failedToCapture))
                }
            }
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
