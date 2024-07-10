//
//  ContentView.swift
//  PicRecognition
//
//  Created by Sanjay Krishnamurthy on 7/7/24.
//

import SwiftUI

class ContentViewModel: ObservableObject {
    @Published var capturedPhoto: UIImage?
    @Published var recognitionResult: String = ""
    @Published var isProcessing: Bool = false
    @Published var picRecognizer: PicRecognizer?

    init() {
        setupPicRecognizer()
    }

    private func setupPicRecognizer() {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            do {
                self.picRecognizer = try PicRecognizer()
                semaphore.signal()
            } catch {
                // Handle the initialization error here
                print("Failed to initialize PicRecognizer: \(error)")
                semaphore.signal()
            }
        }

        // Show a ProgressView while waiting for the semaphore
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        _ = semaphore.wait(timeout: .distantFuture)
        DispatchQueue.main.async {
            self.isProcessing = false
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    private let picUpload = PicUpload()

    var body: some View {
        ZStack {
            // Black area covering the entire background
            Color.black
                .edgesIgnoringSafeArea(.all)

            VStack {
                // Reduced black space at the top
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.05)

                // Centering the rounded rectangle with the image and button inside
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                    .frame(width: UIScreen.main.bounds.width * 0.85, height: UIScreen.main.bounds.height * 0.6)
                    .shadow(radius: 10)
                    .overlay(
                        VStack {
                            Spacer()

                            if let photo = viewModel.capturedPhoto {
                                Image(uiImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: UIScreen.main.bounds.width * 0.75, height: UIScreen.main.bounds.height * 0.4)
                            }

                            Spacer()

                            Button("Select Image") {
                                selectImageAndRecognize()
                            }
                            .padding()
                        }
                        .padding()
                    )

                // Reduced black space at the bottom
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.05)
                
                // Recognition result text at the bottom
                Text("\(viewModel.recognitionResult)")
                    .foregroundColor(viewModel.recognitionResult.isEmpty ? .white : .red)
                    .padding()
            }

            // Show a ProgressView while processing
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(2)
                    .padding()
            }
        }
    }

    private func selectImageAndRecognize() {
        picUpload.selectImage { result in
            switch result {
            case .success((let bitmap, let image)):
                self.viewModel.capturedPhoto = image
                self.recognizeImage(with: bitmap)
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func recognizeImage(with bitmap: CIImage) {
        guard let picRecognizer = viewModel.picRecognizer else {
            handleError(RecognitionError.custom(message: "PicRecognizer is not initialized"))
            return
        }

        let result = picRecognizer.evaluate(bitmap: bitmap)
        switch result {
        case .success(let cloneCheckResult):
            self.handleRecognitionSuccess(cloneCheckResult)
        case .failure(let error):
            self.handleError(error)
        }
    }

    private func handleRecognitionSuccess(_ cloneCheckResult: String) {
        DispatchQueue.main.async {
            self.viewModel.recognitionResult = cloneCheckResult
        }
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            if (error as! PicUploadError != PicUploadError.noPicSelected) {
                self.viewModel.recognitionResult = "Error: \(error)"
            }
        }
    }
}
