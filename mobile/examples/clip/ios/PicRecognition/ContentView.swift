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
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    private let picUpload = PicUpload()
    private var picRecognizer: PicRecognizer?

    @State private var readyToRecord: Bool = true

    init() {
        do {
            picRecognizer = try PicRecognizer()
        } catch {
            // Handle the initialization error here
            print("Failed to initialize PicRecognizer: \(error)")
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
        let result = picRecognizer?.evaluate(bitmap: bitmap)
        switch result {
        case .some(.success(let cloneCheckResult)):
            self.handleRecognitionSuccess(cloneCheckResult)
        case .some(.failure(let error)):
            self.handleError(error)
        case .none:
            self.handleError(RecognitionError.custom(message: "PicRecognizer is not initialized"))
        }
    }

    private func handleRecognitionSuccess(_ cloneCheckResult: String) {
        DispatchQueue.main.async {
            self.viewModel.recognitionResult = cloneCheckResult
            self.readyToRecord = true
        }
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.viewModel.recognitionResult = "Error: \(error)"
            self.readyToRecord = true
        }
    }

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
                                readyToRecord = false
                                selectImageAndRecognize()
                            }
                            .padding()
                            .disabled(!readyToRecord)
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
        }
    }


}
