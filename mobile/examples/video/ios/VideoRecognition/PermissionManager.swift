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

    // Closure to be executed when camera and audio permissions are granted or denied
    var permissionsDidChange: ((Bool) -> Void)?

    // Initialize the permission manager
    func initialize(_ completion: @escaping ((Bool) -> Void)) {
        permissionsDidChange = completion
        // Add observers for camera permission changes
        NotificationCenter.default.addObserver(self, selector: #selector(cameraPermissionChanged), name: .AVCaptureDeviceWasConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cameraPermissionChanged), name: .AVCaptureDeviceWasDisconnected, object: nil)
    }

    // Request both camera and microphone permissions
    func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] videoGranted in
            if videoGranted {
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    DispatchQueue.main.async {
                        let allGranted = videoGranted && audioGranted
                        self?.permissionsDidChange?(allGranted)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.permissionsDidChange?(false)
                }
            }
        }
    }

    // Handle camera permission change notifications
    @objc func cameraPermissionChanged() {
        let cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if cameraPermissionStatus == .authorized && audioPermissionStatus == .authorized {
            permissionsDidChange?(true)
        } else {
            permissionsDidChange?(false)
        }
    }
}


