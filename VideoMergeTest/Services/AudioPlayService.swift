//
//  RecordService.swift
//  VideoMergeTest
//
//  Created by gitwebmobi2018 on 12/11/18.
//  Copyright © 2018 gitwebmobi2018. All rights reserved.
//

import Foundation
import AVFoundation

protocol AudioPlayServiceProtocol {
    
    typealias ConfigurePlayerCallBackType = (Bool, String) -> Void
    
    // sound in bg
    func startRecording(_ completion: @escaping ConfigurePlayerCallBackType)
    
    func playSound(_ completion: @escaping ConfigurePlayerCallBackType)
    func pauseSound()
    func stopSound()
}

extension AudioPlayServiceProtocol {
    
}

class AudioPlayService : AudioPlayServiceProtocol {
    
    private var player : AVAudioPlayer?
    
    func startRecording(_ completion: @escaping ConfigurePlayerCallBackType) {
        self.playSound { (isDone, resultDescription) in
            completion(isDone, resultDescription)
        }
    }
    
    func playSound(_ completion: @escaping ConfigurePlayerCallBackType) {
        self.configurePlayer { (isDone, resultDescription) in
            if isDone {
                self.player?.play()
                completion(true, "Success for Playing!")
            } else {
                self.player = nil
                completion(false, resultDescription)
            }
        }
    }
    
    func pauseSound() {
        if self.player != nil {
            self.player?.pause()
        } else {
            print("Not configured player with this sound file!")
        }
    }
    
    func stopSound() {
        if self.player != nil {
            self.player?.stop()
        } else {
            print("Not configured player with this sound file!")
        }
    }
    
    private func configurePlayer(_ completion: @escaping ConfigurePlayerCallBackType) {
        
        guard let url = Bundle.main.url(forResource: "test", withExtension: "mp3") else {
            completion(false, "There is no sound file!")
            return
        }
        
        do {
            
            self.player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            
            if self.player == nil {
                completion(false, "Couldn't configure a player with this file!")
            } else {
                completion(true, "Success!")
            }
            
        } catch let error {
            print(error.localizedDescription)
            completion(false, error.localizedDescription)
        }
        
    }
    
}
