// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import SwiftUI

// Define a custom error type
enum RecognitionError: Error {
    case custom(message: String)
}

struct ContentView: View {
  private let picCapture = PicCapture()
  private var picRecognizer: PicRecognizer?

  @State private var message: String = ""
  @State private var successful: Bool = true
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
        case .success(let data):
            self.recognizeImage(with: data)
        case .failure(let error):
            self.handleError(error)
        }
    }
  }

  private func recognizeImage(with data: Data) {
      let result = picRecognizer?.evaluate(inputData: data)
      switch result {
      case .success(let transcription):
          self.handleRecognitionSuccess(transcription)
      case .failure(let error):
          self.handleError(error)
      case .none:
          self.handleError(RecognitionError.custom(message: "PicRecognizer is not initialized"))
      }
  }

  private func handleRecognitionSuccess(_ transcription: String) {
    DispatchQueue.main.async {
        self.message = transcription
        self.successful = true
        self.readyToRecord = true
    }
  }

  private func handleError(_ error: Error) {
    DispatchQueue.main.async {
        self.message = "Error: \(error)"
        self.successful = false
        self.readyToRecord = true
    }
  }

  var body: some View {
    VStack {
      Text("Press \"Record\", which initiates a 5 sec recording from your Mic, and wait for your results!")
        .padding()

      Button("Record") {
        readyToRecord = false
        capturePhotoAndRecognize()
      }
      .padding()
      .disabled(!readyToRecord)

      Text("\(message)")
        .foregroundColor(successful ? .none : .red)
        .padding()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
