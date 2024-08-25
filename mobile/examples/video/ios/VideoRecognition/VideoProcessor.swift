//
//  VideoProcessor.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/13/24.
//

import Accelerate
import AVFoundation
import CoreImage
import Foundation
import UIKit

// Takes a local mov URL. Splits it into [VideoFragment]

class VideoProcessor: NSObject {
    
    private let localURL: URL
    private let TIMESLICE: Int = 10
    private let AUDIOSNIPPETLENGTH: Int = 5 // keep in sync w/ SpeechRecognizer
    private let kSampleRate: Double = 16000.0
    private var videoFragments: [VideoFragment] = []
    private let videoRecognizer: VideoRecognizer
    private let completion: (URL?, Bool) -> Void
    
    init(localURL: URL, videoRecognizer: VideoRecognizer, completion: @escaping (URL?, Bool) -> Void) {
        self.localURL = localURL
        self.videoRecognizer = videoRecognizer
        self.completion = completion
        super.init()
        self.convert2Fragments()
    }
    
    // MARK :- private methods
    
    private func isCloned() -> Bool {
        for fragment in videoFragments {
            if fragment.isPicCloned || fragment.isAudioCloned {
                return true
            }
        }
        return false
    }
    
    private func convert2Fragments() {
        let picFragments = createStillFrames(from: localURL)
        var audioFragments: [Data] = []
        createAudioSnippets(from: localURL, completion: { audioData, outputURL in
            audioFragments = audioData
            let count = min(picFragments.count, audioFragments.count)
            var timeSlice: Int = 0
            
            for index in 0..<count {
                let fragment = VideoFragment(timeDelta: timeSlice,
                                             stillFrame: picFragments[index],
                                             audioSnippet: audioFragments[index])
                self.videoFragments.append(fragment)
                timeSlice += self.TIMESLICE
            }
            self.videoRecognizer.drivePicRecognizer(self.videoFragments)
            self.videoRecognizer.driveSpeechRecognizer(self.videoFragments)
            self.completion(outputURL, self.isCloned())
        })
    }
    
    // Slice localURL (mov stored locally) every TIMESLICE seconds to get a stillframe per TIMESLICE
    private func createStillFrames(from localURL: URL) -> [CIImage] {
        var stillFrames: [CIImage] = []
        
        // Create an AVAsset from the local URL
        let asset = AVAsset(url: localURL)
        let duration = CMTimeGetSeconds(asset.duration)
        
        // Create an AVAssetImageGenerator instance
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true  // Ensure the orientation is correct
        
        // Generate still frames every TIMESLICE seconds
        var times: [NSValue] = []
        var currentTime: Double = 0.0
        
        while currentTime < duration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: asset.duration.timescale)
            times.append(NSValue(time: cmTime))
            currentTime += Double(TIMESLICE)
        }
        
        // Generate the images
        for time in times {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time.timeValue, actualTime: nil)
                
                // Convert to UIImage
                let uiImage = UIImage(cgImage: cgImage)
                
                // Resize the UIImage to 224x224
                let resizedUIImage = uiImage.resized(to: CGSize(width: 224, height: 224))
                
                // Convert the resized UIImage to CIImage
                if let ciImage = CIImage(image: resizedUIImage) {
                    stillFrames.append(ciImage)
                }
            } catch {
                print("Error generating still frame at time \(time): \(error.localizedDescription)")
            }
        }
        
        return stillFrames
    }
    
    // Helper function to resize UIImage
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what the new size will be
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        // Create a rectangle for the new size
        let rect = CGRect(origin: .zero, size: newSize)
        
        // Resize the image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    private func createAudioSnippets(from localURL: URL, completion: @escaping ([Data], URL?) -> Void) {
        convertAudio(from: localURL, completion: { outputURL, outputFileLength in
            guard let outputURL = outputURL else {
                completion([], localURL)
                return
            }
            let audioDataArray: [Data] = self.extractAudioSnippets(from: outputURL, frameLength: outputFileLength)
            completion(audioDataArray, outputURL)
        })
    }

    // convert input audio to 16KHz non-interleaved mono with Float32 internal representation
    private func convertAudio(from inputURL: URL, completion: @escaping (URL?, Int64) -> Void) {
        // Load the asset from the input URL (video file)
        let asset = AVAsset(url: inputURL)
        
        // Get the audio track from the asset
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("No audio track found in the asset")
            completion(nil, 0)
            return
        }
        
        // Define the desired output format (kSampleRate, mono, Float32, non-interleaved)
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: kSampleRate, channels: 1, interleaved: false)!
        
        // Create the output file URL (use the same directory as the input, with a modified filename)
        let outputDirectory = inputURL.deletingLastPathComponent()
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + "_converted.wav"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)
        
        var fileLength: Int64 = 0
        
        do {
            // Create an AVAssetReader to read from the audio track
            let assetReader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: kSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            assetReader.add(trackOutput)
            
            guard assetReader.startReading() else {
                print("Failed to start reading from asset")
                completion(nil, 0)
                return
            }
            
            // Use autoreleasepool to ensure timely deallocation of resources
            autoreleasepool {
                // Prepare to write the converted audio to a file
                do {
                    let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
                    
                    // Process audio samples
                    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        if let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                            var length = 0
                            var dataPointer: UnsafeMutablePointer<Int8>?
                            
                            CMBlockBufferGetDataPointer(audioBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                            
                            if let dataPointer = dataPointer, length > 0 {
                                let bytesPerFrame = Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
                                let frameLength = AVAudioFrameCount(length / bytesPerFrame)
                                
                                let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameLength)!
                                outputBuffer.frameLength = frameLength
                                
                                memcpy(outputBuffer.floatChannelData?.pointee, dataPointer, length)
                                
                                try outputFile.write(from: outputBuffer)
                            }
                        }
                    }
                    
                    // Store the file length
                    fileLength = outputFile.length
                } catch {
                    print("Error during file writing: \(error)")
                }
            }
            // AVAudioFile will be deallocated and closed here when it goes out of scope
            
        } catch {
            print("Error during conversion: \(error)")
            completion(nil, 0)
            return
        }
        
        // Verify file existence and size
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path) {
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("File size: \(fileSize) bytes")
                if fileSize > 0 {
                    completion(outputURL, fileLength)
                    return
                }
            }
        }
        
        // If we reach here, something went wrong
        print("File creation failed or file is empty")
        completion(nil, 0)
    }
    
    private func extractAudioSnippets(from outputURL: URL, frameLength: Int64) -> [Data] {
        var audioDataArray = [Data]()
        
        do {
            // Load the audio file from the output URL
            let commonFormat: AVAudioCommonFormat = .pcmFormatFloat32  // 32-bit float
            let interleaved = false  // Set to false for non-interleaved data
            let audioFile = try AVAudioFile(forReading: outputURL, commonFormat: commonFormat, interleaved: interleaved)
            let audioFormat = audioFile.processingFormat
            let audioFrameCount = frameLength // DOESN'T WORK!! Int(audioFile.length)
            let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(audioFrameCount))!
            try audioFile.read(into: audioBuffer)
            
            // Define the sample rate as a Double
            let sampleRateDouble = Double(audioFormat.sampleRate)
            
            // Calculate frame lengths
            let timesliceInFrames = AVAudioFrameCount(Double(TIMESLICE) * sampleRateDouble)
            let samplesPerSlice = Int(sampleRateDouble * Double(AUDIOSNIPPETLENGTH))
            
            var startFrame: AVAudioFramePosition = 0
            
            while startFrame < audioBuffer.frameLength {
                // Calculate end frame
                let endFrame = min(startFrame + AVAudioFramePosition(samplesPerSlice), AVAudioFramePosition(audioBuffer.frameLength))
                
                // Create a buffer for the snippet
                let snippetFrameCount = AVAudioFrameCount(endFrame - startFrame)
                let snippetBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: snippetFrameCount)!
                snippetBuffer.frameLength = snippetBuffer.frameCapacity
                
                // Copy data manually from the main buffer to the snippet buffer
                if let sourceChannelData = audioBuffer.floatChannelData?[0],
                   let destinationChannelData = snippetBuffer.floatChannelData?[0] {
                    
                    for frame in 0..<Int(snippetFrameCount) {
                        let sourceIndex = Int(startFrame) + frame
                        if sourceIndex < Int(audioBuffer.frameLength) {
                            destinationChannelData[frame] = sourceChannelData[sourceIndex]
                        }
                    }
                }
                
                // Convert buffer to [Double]
                let doubleData = convertBufferToDouble(snippetBuffer)
                
                // Pad data to ensure consistent length
                let paddedData = padData(doubleData, toLength: Int(kSampleRate * Double(AUDIOSNIPPETLENGTH)))
                
                // Convert [Double] to Data
                let data = doubleArrayToData(paddedData)
                audioDataArray.append(data)
                
                // Move to the next time slice
                startFrame += AVAudioFramePosition(timesliceInFrames)
            }
            
        } catch {
            print("Error extracting audio snippets: \(error)")
        }
        
        return audioDataArray
    }

    
    private func padData(_ data: [Double], toLength length: Int) -> [Double] {
        var paddedData = data
        if paddedData.count < length {
            paddedData.append(contentsOf: Array(repeating: 0.0, count: length - paddedData.count))
        }
        return paddedData
    }

    private func doubleArrayToData(_ array: [Double]) -> Data {
        return Data(bytes: array, count: array.count * MemoryLayout<Double>.size)
    }


    private func clampAmplitude(of pcmBuffer: AVAudioPCMBuffer) {
        guard let channelData = pcmBuffer.floatChannelData else {
            print("No channel data available")
            return
        }

        // Iterate over each channel
        for channel in 0..<Int(pcmBuffer.format.channelCount) {
            let dataPointer = channelData[channel]
            let frameCount = Int(pcmBuffer.frameLength)
            
            // Clamp values for each sample
            for frame in 0..<frameCount {
                let sample = dataPointer[frame]
                dataPointer[frame] = min(max(sample, -1.0), 1.0)
            }
        }
    }
    
    private func convertBufferToDouble(_ buffer: AVAudioPCMBuffer) -> [Double] {
        let channelData = buffer.floatChannelData?[0]
        let frameLength = Int(buffer.frameLength)
        
        // Convert Float32 buffer data to Double
        let doubleData: [Double] = (0..<frameLength).map { index in
            return Double(channelData?[index] ?? 0)
        }
        
        return doubleData
    }


}
