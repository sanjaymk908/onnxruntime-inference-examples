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
    private let completion: (URL?) -> Void
    
    init(localURL: URL, videoRecognizer: VideoRecognizer, completion: @escaping (URL?) -> Void) {
        self.localURL = localURL
        self.videoRecognizer = videoRecognizer
        self.completion = completion
        super.init()
        self.convert2Fragments()
        videoRecognizer.drivePicRecognizer(videoFragments)
        videoRecognizer.driveSpeechRecognizer(videoFragments)
    }
    
    public func isCloned() -> Bool {
        for fragment in videoFragments {
            if fragment.isPicCloned || fragment.isAudioCloned {
                return true
            }
        }
        return false
    }
    
    
    // MARK :- private methods
    
    private func convert2Fragments() {
        let picFragments = createStillFrames(from: localURL)
        var audioFragments: [Data] = []
        createAudioSnippets(from: localURL, completion: { audioData, outputURL in
            self.completion(outputURL)
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
        convertAudio(from: localURL, completion: { outputURL in
            let audioDataArray: [Data] = []
            completion(audioDataArray, outputURL)
        })
    }

    // convert input audio to 16KHz non-interleaved mono with Float32 internal representation
    private func convertAudio(from inputURL: URL, completion: @escaping (URL?) -> Void) {
        // Load the asset from the input URL (video file)
        let asset = AVAsset(url: inputURL)
        
        // Get the audio track from the asset
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("No audio track found in the asset")
            completion(nil)
            return
        }
        
        // Define the desired output format (kSampleRate, mono, Float32, non-interleaved)
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: kSampleRate, channels: 1, interleaved: false)!
        
        // Create the output file URL (use the same directory as the input, with a modified filename)
        let outputDirectory = inputURL.deletingLastPathComponent()
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + "_converted.wav"
        let outputURL = outputDirectory.appendingPathComponent(outputFileName)
        
        do {
            // Create an AVAssetReader to read from the audio track
            let assetReader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: kSampleRate,  // Use the provided sample rate
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            
            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            assetReader.add(trackOutput)
            
            // Create an AVAssetReaderOutput to read samples from the audio track
            guard assetReader.startReading() else {
                print("Failed to start reading from asset")
                completion(nil)
                return
            }
            
            // Prepare to write the converted audio to a file
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
            
            // Process audio samples
            while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                if let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    var length = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    
                    // Access the raw audio data
                    CMBlockBufferGetDataPointer(audioBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                    
                    if let dataPointer = dataPointer, length > 0 {
                        // Calculate frame length based on byte length and bytes per frame
                        let bytesPerFrame = Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
                        let frameLength = AVAudioFrameCount(length / bytesPerFrame)  // Ensure both operands are Int
                        
                        // Create an AVAudioPCMBuffer with the calculated frame length
                        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameLength)!
                        outputBuffer.frameLength = frameLength
                        
                        // Copy data to the buffer's float channel data
                        memcpy(outputBuffer.floatChannelData?.pointee, dataPointer, length)
                        
                        // Write the buffer to the output file
                        try outputFile.write(from: outputBuffer)
                    }
                }
            }
            
            // Completion with output URL
            completion(outputURL)
            
        } catch {
            print("Error during conversion: \(error)")
            completion(nil)
        }
    }

}
