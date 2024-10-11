//
//  ContentView.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/7/24.
//

import SwiftUI
import Combine

struct ContentView: View {
    var body: some View {
        PermissionHandlerView()
    }
}

struct PermissionHandlerView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var showSettingsAlert = false
    @State private var cancellable: AnyCancellable?

    var body: some View {
        Group {
            if permissionManager.permissionsGranted {
                HomeScreenViewControllerWrapper()
                    .edgesIgnoringSafeArea(.all)
            } else {
                PermissionRequestView(showSettingsAlert: $showSettingsAlert)
            }
        }
        .onAppear {
            permissionManager.initialize()
            listenForAppForeground()
        }
        .onDisappear {
            cancellable?.cancel()
        }
        .alert(isPresented: $showSettingsAlert) {
            Alert(
                title: Text("Permissions Denied"),
                message: Text("Please go to Settings to allow Camera and Microphone access."),
                primaryButton: .default(Text("Go to Settings")) {
                    goToSettings()
                },
                secondaryButton: .cancel()
            )
        }
    }

    func listenForAppForeground() {
        cancellable = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                permissionManager.checkPermissions()
            }
    }

    func goToSettings() {
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
    }
}

struct PermissionRequestView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @Binding var showSettingsAlert: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Camera and Microphone Access")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .font(.title)
            
            Text("Please grant camera and microphone permissions to use this app.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                if permissionManager.arePermissionsDenied() {
                    showSettingsAlert = true
                } else {
                    permissionManager.requestPermissions()
                }
            }) {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(minWidth: 200, minHeight: 50)
                    .background(Color.blue.opacity(0.7))
                    .cornerRadius(25)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
    }
}

struct HomeScreenViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HomeScreenViewController {
        let viewController = HomeScreenViewController()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: HomeScreenViewController, context: Context) {
        // Handle updates if needed
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
