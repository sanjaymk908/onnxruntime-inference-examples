// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

import AVFoundation
import SwiftUI

struct ContentView: View {
  private let audioRecorder = AudioRecorder()
  private let speechRecognizer = try! SpeechRecognizer()

  @State private var message: String = ""
  @State private var successful: Bool = true
  @State private var readyToRecord: Bool = true
  @State private var audioData: Data? = nil
  @State private var audioBuffer: AVAudioPCMBuffer? = nil
  @State private var playerNode: AVAudioPlayerNode? = nil
  @State private var engine: AVAudioEngine? = nil
  @State private var isPlaying: Bool = false

  private func recordAndRecognize() {
    audioRecorder.record { recordResult in
      let recognizeResult = recordResult.flatMap { recordingBufferAndData in
        self.audioData = recordingBufferAndData.data
        self.audioBuffer = recordingBufferAndData.buffer as? AVAudioPCMBuffer
        return speechRecognizer.evaluate(inputData: recordingBufferAndData.data)
      }
      endRecordAndRecognize(recognizeResult)
    }
  }

  private func endRecordAndRecognize(_ result: Result<String, Error>) {
    DispatchQueue.main.async {
      switch result {
      case .success(let transcription):
        message = transcription
        successful = true
      case .failure(let error):
        message = "Error: \(error)"
        successful = false
      }
      readyToRecord = true
    }
  }
    
  private func playAudio(buffer: AVAudioPCMBuffer) {
    engine = AVAudioEngine()
    playerNode = AVAudioPlayerNode()
    guard let engine = engine, let playerNode = playerNode else {
        print("Failed to initialize AVAudioEngine or AVAudioPlayerNode.")
        return
    }
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
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
    playerNode.scheduleBuffer(buffer, at: nil, options: []) {
        print("Playback finished.")
        self.cleanupAudio()
        self.isPlaying = false
    }
    playerNode.play()
    isPlaying = true
    print("Playing audio...")
    var playbackDuration = Double(buffer.frameLength) / buffer.format.sampleRate
    playbackDuration += 3  // prevent pre-emptive stops
    DispatchQueue.main.asyncAfter(deadline: .now() + playbackDuration) {
        print("Playback should be completed by now.")
    }
  }
    
  private func togglePlayPause() {
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
    // Clean up resources
    engine?.stop()
    engine = nil
    playerNode = nil
    let session = AVAudioSession.sharedInstance()
    do {
        try session.setActive(false)
        print("Audio session deactivated.")
    } catch {
        print("Error deactivating audio session: \(error)")
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

                // Centering the rounded rectangle with the content inside
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                    .frame(width: UIScreen.main.bounds.width * 0.85, height: UIScreen.main.bounds.height * 0.6)
                    .shadow(radius: 10)
                    .overlay(
                        VStack {
                            Text("Press \"Record\", which initiates a 5 sec recording from your Mic, and wait for your results!")
                                .foregroundColor(.black) // Darker text color for better visibility
                                .padding()

                            Button("Record") {
                                readyToRecord = false
                                recordAndRecognize()
                            }
                            .buttonStyle(RecordButtonStyle(isEnabled: readyToRecord))
                            .padding()

                            if let audioBuffer = audioBuffer {
                                HStack {
                                    Button(action: {
                                        togglePlayPause()
                                        if playerNode == nil {
                                            playAudio(buffer: audioBuffer)
                                        }
                                    }) {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .resizable()
                                            .frame(width: 50, height: 50)
                                            .foregroundColor(.blue)
                                    }
                                    WaveformView(audioBuffer: audioBuffer)
                                        .frame(height: 50)
                                }
                                .padding()
                            }

                            Text("\(message)")
                                .foregroundColor(successful ? .green : .red) // Use black color for success
                                .padding()
                        }
                        .padding()
                    )

                // Reduced black space at the bottom
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.05)
            }
        }
    }
}

struct RecordButtonStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(isEnabled ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
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
