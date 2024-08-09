//
//  ContentView.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/7/24.
//

import SwiftUI
import Combine

class ContentViewModel: ObservableObject {
    @Published var capturedPhoto: UIImage?
    @Published var recognitionResult: String = ""
    @Published var isProcessing: Bool = false
    @Published var picRecognizer: PicRecognizer?

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupPicRecognizer()
    }

    private func setupPicRecognizer() {
        DispatchQueue.global().async {
            do {
                let picRecognizer = try PicRecognizer()
                DispatchQueue.main.async {
                    self.picRecognizer = picRecognizer
                }
            } catch {
                // Handle the initialization error here
                print("Failed to initialize PicRecognizer: \(error)")
            }
        }
    }

    func selectImageAndRecognize(with bitmap: CIImage) {
        isProcessing = true

        let result = picRecognizer?.evaluate(bitmap: bitmap)
        switch result {
        case .some(.success(let cloneCheckResult)):
            DispatchQueue.main.async {
                self.recognitionResult = cloneCheckResult
                self.isProcessing = false
            }
        case .some(.failure(let error)):
            DispatchQueue.main.async {
                self.recognitionResult = "Error: \(error)"
                self.isProcessing = false
            }
        case .none:
            DispatchQueue.main.async {
                self.recognitionResult = "Error: PicRecognizer is not initialized"
                self.isProcessing = false
            }
        }
    }
}

// UIViewControllerRepresentable wrapper for HomeScreenViewController
struct HomeScreenViewControllerWrapper: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> HomeScreenViewController {
        // Instantiate and return your HomeScreenViewController
        let viewController = HomeScreenViewController()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: HomeScreenViewController, context: Context) {
        // Handle updates from SwiftUI to the UIViewController (if needed)
    }
}

// SwiftUI ContentView using the UIViewControllerRepresentable
struct ContentView: View {
    var body: some View {
        HomeScreenViewControllerWrapper()
            .edgesIgnoringSafeArea(.all) // Optional: to make it full-screen
    }
}


