//
//  PicUpload.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/7/24.
//

import UIKit
import CoreImage

class PicUpload: NSObject {
    typealias PictureData = (CIImage, UIImage)
    typealias PictureDataCallback = (Result<PictureData, Error>) -> Void

    private var pictureDataCallback: PictureDataCallback?
    private let imagePicker = UIImagePickerController()

    override init() {
        super.init()
        setupImagePicker()
    }

    func selectImage(completion: @escaping PictureDataCallback) {
        pictureDataCallback = completion
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false
        
        DispatchQueue.main.async {
            let rootViewController = UIApplication.shared.windows.first?.rootViewController
            rootViewController?.present(self.imagePicker, animated: true, completion: nil)
        }
    }

    private func setupImagePicker() {
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false
    }

    private func processImage(_ image: UIImage) -> CIImage? {
        guard let ciImage = CIImage(image: image) else {
            return nil
        }

        let targetSize = CGSize(width: 224, height: 224)
        let scaleX = targetSize.width / ciImage.extent.size.width
        let scaleY = targetSize.height / ciImage.extent.size.height
        let scaledCIImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return scaledCIImage
    }
}

extension PicUpload: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            if let ciImage = processImage(image) {
                pictureDataCallback?(.success((ciImage, image)))
            } else {
                pictureDataCallback?(.failure(PicUploadError.failedToEncodeImage))
            }
        } else {
            pictureDataCallback?(.failure(PicUploadError.failedToCapture))
        }

        DispatchQueue.main.async {
            picker.dismiss(animated: true, completion: nil)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        DispatchQueue.main.async {
            picker.dismiss(animated: true, completion: nil)
        }
    }
}

enum PicUploadError: Error {
    case failedToCapture
    case failedToEncodeImage
}
