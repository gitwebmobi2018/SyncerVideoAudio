//
//  PlayVC.swift
//  VideoMergeTest
//
//  Created by Ivan on 12/11/18.
//  Copyright © 2018 Ivan. All rights reserved.
//

import UIKit
import AVFoundation

class PlayVC: UIViewController {

    var selectedVideoItem                   : VideoItem?
    var manageAppUrlService                 : ManageAppURLServiceProtocol!

    var avAsset                             : AVAsset!
    var avPlayerItem                        : AVPlayerItem!
    var avPlayer                            : AVPlayer!
    var avPlayerLayer                       : AVPlayerLayer!
    
}

//MARK: - Override Functions
extension PlayVC {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.manageAppUrlService = ManageAppURLService()
        
        self.createPlayer()
    }
    
}

//MARK: - custom function
extension PlayVC {
    
    func createPlayer() {
        guard let videoItem = self.selectedVideoItem else {
            let alert = UIAlertController(title: "VideoMergeTest", message: "Provided empty URL for playing!", preferredStyle: .alert )
            let ok = UIAlertAction(title: "Ok", style: .default, handler: { (okAction) in
                self.dismiss(animated: true, completion: nil)
            })
            alert.addAction(ok)
            self.present(alert, animated: true, completion: nil)
            
            return
        }
        let url = URL(fileURLWithPath: self.manageAppUrlService.getVideoFileFullPath(of: videoItem.fileName!))
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default, options: [])
        avAsset = AVAsset(url: url)
        avPlayerItem = AVPlayerItem(asset: avAsset)
        avPlayer = AVPlayer(playerItem: avPlayerItem)
        avPlayerLayer = AVPlayerLayer(player: avPlayer)
        avPlayerLayer.frame = self.view.frame
        self.view.layer.addSublayer(avPlayerLayer)
        avPlayer.seek(to: CMTime.zero)
        avPlayerLayer.backgroundColor = UIColor.red.cgColor
        avPlayer.play()
        
        let videoAsset = AVURLAsset(url: url, options:nil)
        let tracks:NSArray = videoAsset.tracks(withMediaType: AVMediaType.audio) as NSArray
        print(tracks.count)
    }
    
}
