//
//  PermissionManager.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/9/24.
//

import AVFoundation

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var permissionsGranted: Bool = false
    
    func initialize() {
        checkPermissions()
    }

    func checkPermissions() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        
        if cameraStatus == .authorized && micStatus == .granted {
            permissionsGranted = true
        } else {
            permissionsGranted = false
        }
    }

    func requestPermissions() {
        let group = DispatchGroup()
        
        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            group.leave()
        }
        
        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.checkPermissions()
        }
    }

    func arePermissionsDenied() -> Bool {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        
        return cameraStatus == .denied || micStatus == .denied
    }
}

