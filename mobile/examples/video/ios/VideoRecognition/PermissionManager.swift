//
//  PermissionManager.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/9/24.
//

import AVFoundation

class PermissionManager: NSObject {
    
    static let shared = PermissionManager()
    
    private override init() {}
    
    // Closure to be executed when camera permission changes to enabled
    var cameraPermissionDidChange: (() -> Void)?
    
    // Initialize the permission manager
    func initialize(_ completion: @escaping (() -> Void)) {
        cameraPermissionDidChange = completion
        // Add observer for camera permission changes
        NotificationCenter.default.addObserver(self, selector: #selector(cameraPermissionChanged), name: .AVCaptureDeviceWasConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cameraPermissionChanged), name: .AVCaptureDeviceWasDisconnected, object: nil)
    }
    
    // Request camera permission and execute the closure when it changes
    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.main.async {
                    self?.cameraPermissionDidChange?()
                }
            }
        }
    }
    
    // Handle camera permission change notifications
    @objc func cameraPermissionChanged() {
        let cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraPermissionStatus == .authorized {
            cameraPermissionDidChange?()
        }
    }
}

