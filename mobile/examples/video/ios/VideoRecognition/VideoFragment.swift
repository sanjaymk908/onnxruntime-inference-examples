//
//  VideoFragment.swift
//  VideoRecognition
//
//  Created by Sanjay Krishnamurthy on 8/13/24.
//

import Foundation
import UIKit
import AVFAudio

// Is the primary container for a video snippet. A full recording is broken up
// into fixed size video fragments

class VideoFragment: NSObject {
    
    let timeDelta: Int
    let stillFrame: CIImage  // UIImage converted to a 224x224 bitmap (CIImage)
    let origPic: UIImage     // StillFrame cropped to transparentView dimensions
    let audioSnippet: Data // AVAudioPCMBuffer converted to Data
    var isAudioCloned: Bool = false
    var isPicCloned: Bool = false
    
    init(timeDelta: Int, stillFrame: CIImage, origPic: UIImage, audioSnippet: Data) {
        self.timeDelta = timeDelta
        self.stillFrame = stillFrame
        self.origPic = origPic
        self.audioSnippet = audioSnippet
    }
    
    func isCloned() -> Bool {
        return isAudioCloned || isPicCloned
    }
}
