import SwiftUI
import AVFoundation

// Define a custom error type
enum RecognitionError: Error {
    case custom(message: String)
}

class ContentViewModel: ObservableObject {
    @Published var capturedPhoto: AVCapturePhoto?
    @Published var recognitionResult: String = ""
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    private let picCapture = PicCapture()
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

    private func capturePhotoAndRecognize() {
        picCapture.captureImage { result in
            switch result {
            case .success((let data, let photo)):
                self.viewModel.capturedPhoto = photo
                self.recognizeImage(with: data)
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func recognizeImage(with data: Data) {
        let result = picRecognizer?.evaluate(inputData: data)
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
            if let photo = viewModel.capturedPhoto, let image = UIImage(data: photo.fileDataRepresentation()!) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .edgesIgnoringSafeArea(.all)
            }

            VStack {
                Text("Click the button to capture a photo from your rear-facing camera and wait for the results!")
                    .padding()

                Button("Click") {
                    readyToRecord = false
                    capturePhotoAndRecognize()
                }
                .padding()
                .disabled(!readyToRecord)

                Text("\(viewModel.recognitionResult)")
                    .foregroundColor(viewModel.recognitionResult.isEmpty ? .white : .red)
                    .padding()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
