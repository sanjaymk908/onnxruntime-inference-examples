//
//  VideoProcessor.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/13/24.
//

import CoreImage
import Foundation
import AVFoundation
import UIKit

// Takes a local mov URL. Splits it into [VideoFragment]

class VideoProcessor: NSObject {
    
    private let localURL: URL
    private let TIMESLICE: Int = 3
    private let AUDIOSNIPPETLENGTH: Int = 5 // Length of each audio snippet in seconds
    private let kSampleRate: Double = 16000.0 // Example sample rate
    private var videoFragments: [VideoFragment] = []
    private let videoRecognizer: VideoRecognizer
    
    init(localURL: URL, videoRecognizer: VideoRecognizer) {
        self.localURL = localURL
        self.videoRecognizer = videoRecognizer
        super.init()
        self.convert2Fragments()
        videoRecognizer.drivePicRecognizer(videoFragments)
    }
    
    private func convert2Fragments() {
        let picFragments = createStillFrames(from: localURL)
        let audioFragments = createAudioSnippets(from: localURL)
        let count = min(picFragments.count, audioFragments.count)
        var timeSlice: Int = 0
        
        for index in 0..<count {
            let fragment = VideoFragment(timeDelta: timeSlice,
                                         stillFrame: picFragments[index],
                                         audioSnippet: audioFragments[index])
            videoFragments.append(fragment)
            timeSlice += TIMESLICE
        }
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
    
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let recordingFloatChannelData = buffer.floatChannelData else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let dataSize = frameLength * MemoryLayout<Double>.size
        let recordingDoubleChannelData = UnsafeBufferPointer(start: recordingFloatChannelData[0], count: frameLength)
            .map { Double($0) }

        return Data(bytes: recordingDoubleChannelData, count: dataSize)
    }

    private func createAudioSnippets(from localURL: URL) -> [Data] {
        var audioDataArray: [Data] = []

        // Create an AVAsset from the local URL
        let asset = AVAsset(url: localURL)

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("No audio track found in the asset")
            return []
        }

        let assetReader: AVAssetReader
        do {
            assetReader = try AVAssetReader(asset: asset)
        } catch {
            print("Error initializing AVAssetReader: \(error)")
            return []
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: kSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        assetReader.add(trackOutput)

        let timescale = asset.duration.timescale
        var currentTime = CMTime(seconds: 0, preferredTimescale: timescale)

        // Define the audio format that matches your recording format
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: kSampleRate,
                                        channels: 1,
                                        interleaved: false)!

        while CMTimeGetSeconds(currentTime) < CMTimeGetSeconds(asset.duration) {
            // Define the time range for each audio snippet
            let snippetEndTime = CMTimeAdd(currentTime, CMTime(seconds: Double(AUDIOSNIPPETLENGTH), preferredTimescale: timescale))
            let timeRange = CMTimeRange(start: currentTime, end: snippetEndTime)

            // Adjust the time range if the snippet end time exceeds the duration
            if CMTimeGetSeconds(snippetEndTime) > CMTimeGetSeconds(asset.duration) {
                break
            }

            // Start the reader
            assetReader.timeRange = timeRange
            assetReader.startReading()

            // Read audio samples into AVAudioPCMBuffer
            while let sampleBuffer = trackOutput.copyNextSampleBuffer(), assetReader.status == .reading {
                if let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    var length: Int = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    CMBlockBufferGetDataPointer(audioBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                    let bufferFrameLength = AVAudioFrameCount(length) / audioFormat.streamDescription.pointee.mBytesPerFrame
                    let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: bufferFrameLength)!
                    pcmBuffer.frameLength = bufferFrameLength

                    memcpy(pcmBuffer.floatChannelData?[0], dataPointer, length)

                    // Apply clampAmplitude to the buffer
                    clampAmplitude(of: pcmBuffer)

                    // Convert clamped buffer to Data
                    if let recordingData = convertBufferToData(pcmBuffer) {
                        audioDataArray.append(recordingData)
                    }
                }
            }

            // Move to the next time slice
            currentTime = CMTimeAdd(currentTime, CMTime(seconds: Double(TIMESLICE), preferredTimescale: timescale))
            assetReader.cancelReading() // Reset the reader for the next snippet
        }

        return audioDataArray
    }
    
    private func clampAmplitude(of buffer: AVAudioPCMBuffer) {
        // Ensure buffer is non-interleaved
        guard buffer.format.isInterleaved == false else {
            print("Buffer must be non-interleaved.")
            return
        }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var wasModified = false
        
        for channel in 0..<channelCount {
            if let channelData = buffer.floatChannelData?[channel] {
                for frame in 0..<frameLength {
                    if channelData[frame] > 1.0 {
                        channelData[frame] = 1.0
                        wasModified = true
                    } else if channelData[frame] < -1.0 {
                        channelData[frame] = -1.0
                        wasModified = true
                    }
                }
            }
        }
        
        if wasModified {
            print("Buffer data was modified to clamp amplitude within the range [-1.0, +1.0].")
        } else {
            print("Buffer data was already within the range [-1.0, +1.0].")
        }
    }
    
}
