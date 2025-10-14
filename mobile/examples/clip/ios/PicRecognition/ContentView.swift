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

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    private let picUpload = PicUpload()

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            VStack {
                // Reduced top space above the rounded rectangle
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.025) // 50% of original

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                    .frame(width: UIScreen.main.bounds.width * 0.85,
                           height: UIScreen.main.bounds.height * 0.6)
                    .shadow(radius: 10)
                    .overlay(
                        VStack {
                            // Input image
                            if let photo = viewModel.capturedPhoto {
                                Image(uiImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: UIScreen.main.bounds.width * 0.75,
                                           height: UIScreen.main.bounds.height * 0.4)
                                    .padding(.bottom, 4) // small gap to result text
                            }

                            // Recognition result text
                            if !viewModel.recognitionResult.isEmpty {
                                Text(viewModel.recognitionResult)
                                    .font(.system(
                                        size: UIFont.preferredFont(forTextStyle: .body).pointSize * 1.5, // 50% taller
                                        weight: .bold
                                    ))
                                    .foregroundColor(
                                        viewModel.recognitionResult.lowercased().contains("real") ? .green : .red
                                    )
                                    .padding(.bottom, 8)
                            }

                            Spacer() // pushes button to bottom

                            // Select Image button (always at bottom)
                            Button("Select Image") {
                                selectImageAndRecognize()
                            }
                            .padding(.top, 4)
                            .padding(.horizontal)
                        }
                        .padding()
                    )

                // Bottom black space
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.05)
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
                self.viewModel.selectImageAndRecognize(with: bitmap)
            case .failure(let error):
                if (error as! PicUploadError) != PicUploadError.noPicSelected {
                    self.viewModel.recognitionResult = "Error: \(error)"
                }
            }
        }
    }
}
