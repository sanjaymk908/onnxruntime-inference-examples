// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import SwiftUI
import AVFoundation


class ContentViewModel: ObservableObject {
    private let audioRecorder = AudioRecorder()
    @Published var message: String = ""
    @Published var successful: Bool = true
    @Published var audioBuffer: AVAudioPCMBuffer? = nil
    @Published var playerNode: AVAudioPlayerNode? = nil
    @Published var engine: AVAudioEngine? = nil
    @Published var isPlaying: Bool = false
    @Published var recordingProgress: Double = 0.0
    @Published var isInitializing: Bool = true
    @Published var speechRecognizer: SpeechRecognizer? = nil
    @Published var isRecording: Bool = false // Added isRecording state
    private var recordStartTime: Date?
    private let recordingDuration = 5.0

    init() {
        setupSpeechRecognizer()
    }

    private func setupSpeechRecognizer() {
        isInitializing = true // Update the state variable

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return } // Check for valid self

            do {
                let recognizer = try SpeechRecognizer()
                DispatchQueue.main.async {
                    self.speechRecognizer = recognizer // Assign to viewModel
                    self.isInitializing = false // Update state
                }
            } catch {
                print("Failed to initialize SpeechRecognizer: \(error)")
                DispatchQueue.main.async {
                    self.isInitializing = false // Update state on error
                }
            }
        }
    }

    func recordAndRecognize() {
        guard !isRecording else {
            print("Already recording.")
            return
        }

        isRecording = true // Update isRecording state
        recordingProgress = 0.0 // Reset progress
        recordStartTime = Date()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Update recordingProgress every 0.1 seconds until recordingDuration seconds
            DispatchQueue.main.async {
                self.updateRecordingProgress()
            }

            if let startTime = self.recordStartTime, Date().timeIntervalSince(startTime) >= self.recordingDuration {
                timer.invalidate()
                self.finishRecording()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        
        audioRecorder.record { [weak self] recordResult in
            guard let self = self else { return }

            switch recordResult {
            case .success(let recordingBufferAndData):
                self.audioBuffer = recordingBufferAndData.buffer as? AVAudioPCMBuffer

                if let speechRecognizer = self.speechRecognizer {
                    let recognizeResult = speechRecognizer.evaluate(inputData: recordingBufferAndData.data)
                    self.endRecordAndRecognize(recognizeResult)
                } else {
                    self.endRecordAndRecognize(.failure(AudioRecorderError.speechRecognizerNotInitialized))
                }

            case .failure(let error):
                self.endRecordAndRecognize(.failure(error))
            }
        }
    }

    private func updateRecordingProgress() {
        guard let startTime = recordStartTime else { return }
        let elapsedTime = Date().timeIntervalSince(startTime)
        recordingProgress = elapsedTime / recordingDuration // Calculate progress based on elapsed time
    }

    private func endRecordAndRecognize(_ result: Result<String, Error>) {
        DispatchQueue.main.async {
            switch result {
            case .success(let transcription):
                self.message = transcription
                self.successful = true
            case .failure(let error):
                self.message = "Error: \(error)"
                self.successful = false
            }
        }
    }

    private func finishRecording() {
        // Stop recording logic goes here
        isRecording = false
    }

    func playAudio() {
        // Placeholder for audio playback logic
        if let audioBuffer = audioBuffer {
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()

            guard let engine = engine, let playerNode = playerNode else {
                print("Failed to initialize AVAudioEngine or AVAudioPlayerNode.")
                return
            }

            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioBuffer.format)

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                print("Audio session configured for playback.")
            } catch {
                print("Error setting up audio session: \(error)")
                return
            }

            do {
                try engine.start()
                print("Audio engine started successfully.")
            } catch {
                print("Error starting engine: \(error.localizedDescription)")
                return
            }

            playerNode.scheduleBuffer(audioBuffer, at: nil, options: []) {
                print("Playback finished.")
                DispatchQueue.main.async {
                    self.cleanupAudio()
                    self.isPlaying = false
                }
            }
            playerNode.play()
            isPlaying = true
            print("Playing audio...")
        }
    }

    func togglePlayPause() {
        // Placeholder for play/pause logic
        if isPlaying {
            playerNode?.pause()
            isPlaying = false
            print("Audio paused.")
        } else {
            playerNode?.play()
            isPlaying = true
            print("Audio resumed.")
        }
    }

    private func cleanupAudio() {
        // Placeholder for audio cleanup logic
        engine?.stop()
        // CRASH!! engine = nil
        playerNode = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
            print("Audio session deactivated.")
        } catch {
            print("Error deactivating audio session: \(error)")
        }
    }
}


struct ContentView: View {
    @ObservedObject private var viewModel = ContentViewModel()

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                    .frame(height: 20)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                    .frame(width: 300, height: 400) // Adjusted height to fit all components
                    .shadow(radius: 10)
                    .overlay(
                        VStack {
                            Text("Record 5 seconds of audio to check whether it is real or cloned")
                                .foregroundColor(.black)
                                .padding()

                            Button(action: {
                                viewModel.recordAndRecognize()
                            }) {
                                RecordButton(isRecording: viewModel.isRecording, progress: viewModel.recordingProgress)
                            }
                            .buttonStyle(RecordButtonStyle(isRecording: viewModel.isRecording, progress: viewModel.recordingProgress))
                            .padding()

                            if let audioBuffer = viewModel.audioBuffer {
                                HStack {
                                    Button(action: {
                                        viewModel.togglePlayPause()
                                        if viewModel.playerNode == nil {
                                            viewModel.playAudio()
                                        }
                                    }) {
                                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                            .foregroundColor(.blue)
                                    }
                                    WaveformView(audioBuffer: audioBuffer)
                                        .frame(height: 50)
                                }
                                .padding()

                                Text("\(viewModel.message)")
                                    .foregroundColor(viewModel.successful ? .green : .red)
                                    .padding()
                            }
                        }
                        .padding()
                    )

                Spacer()
                    .frame(height: 20)
            }
        }
    }
}

struct RecordButton: View {
    var isRecording: Bool
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.9, opacity: 1.0)) // Light gray color
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0.0, to: isRecording ? CGFloat(progress) : 0.0)
                .stroke(Color.gray, lineWidth: 8) // Gray stroke for countdown
                .rotationEffect(Angle(degrees: -90))
                .frame(width: 70, height: 70)

            Text("Record")
                .font(.title2)
                .foregroundColor(isRecording ? Color.blue.opacity(0.5) :
                                    Color.blue)
        }
    }
}

struct RecordButtonStyle: ButtonStyle {
    var isRecording: Bool
    var progress: Double // Add progress parameter for countdown animation

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.9, opacity: 1.0))
                .frame(width: 80, height: 80)

            if isRecording {
                Circle()
                    .trim(from: 0.0, to: CGFloat(progress))
                    .stroke(Color.gray, lineWidth: 8) // Grey circle for countdown
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 70, height: 70)
            }

            configuration.label
                .font(.title2)
                .foregroundColor(Color.blue.opacity(isRecording ? 0.5 : 1.0)) // Adjust colors based on recording state
        }
        .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}

struct RecordingCircle: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray, lineWidth: 8)
                .frame(width: 100, height: 100)

            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(Color.red, lineWidth: 8)
                .frame(width: 100, height: 100)
                .rotationEffect(Angle(degrees: -90))
        }
        .animation(.linear(duration: 0.1)) // Ensure animation is smooth
    }
}

struct WaveformView: View {
    var audioBuffer: AVAudioPCMBuffer

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2

                let audioData = audioBuffer.floatChannelData![0]
                let frameLength = Int(audioBuffer.frameLength)
                let scalingFactor: CGFloat = 8.0 // Increase this value to make the waveform taller

                for x in 0..<Int(width) {
                    let sampleIndex = Int(CGFloat(x) / width * CGFloat(frameLength))
                    let sample = audioData[sampleIndex]
                    let y = CGFloat(sample) * midY * scalingFactor + midY

                    if x == 0 {
                        path.move(to: CGPoint(x: CGFloat(x), y: y))
                    } else {
                        path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                    }
                }
            }
            .stroke(Color.blue, lineWidth: 3) // Increase lineWidth for bolder lines
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
