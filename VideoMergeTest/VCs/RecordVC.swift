//
//  RecordVC.swift
//  VideoMergeTest
//
//  Created by Ivan on 12/11/18.
//  Copyright © 2018 Ivan. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import AssetsLibrary

protocol RecordVCDelegate {
    func onDismiss()
}

class RecordVC: UIViewController {

    //MARK: - IBOutlets
    @IBOutlet weak var previewView          : VTCamPreviewView!
    @IBOutlet weak var timeLbl              : UILabel!
    
    @IBOutlet weak var recordBtn            : UIButton!
    @IBOutlet weak var switchCamBtn         : UIButton!
    @IBOutlet weak var switchFlashBtn       : UIButton!
    @IBOutlet weak var doneBtn              : UIButton!
    
    //MARK: - properties
    var delegate                            : RecordVCDelegate!
    
    var manageAppUrlService                 : ManageAppURLServiceProtocol!
    
    // video
    var sessionQueue                        : DispatchQueue!
    var captureSession                      : AVCaptureSession?
    
    var frontCameraInput                    : AVCaptureDeviceInput?
    var frontCamera                         : AVCaptureDevice?
    
    var rearCameraInput                     : AVCaptureDeviceInput?
    var rearCamera                          : AVCaptureDevice?
    
    var movieFileOutput                     : AVCaptureMovieFileOutput?
    var photoOutput                         : AVCapturePhotoOutput?
    
    var flashMode                           = AVCaptureDevice.FlashMode.off
    
    var isRecording                         : Bool = false
    
    var currentCameraPosition               : CameraPosition?
    
    var newVideoItem                        : VideoItem?
    
    var progressHUD                         : JGProgressHUDService! = JGProgressHUDService()
    
    var timer                               : Timer!
    
    var isConnectedWithEarPiece             : Bool = false
    
    var startAudioTime                      : CMTime = CMTime.zero
    
    var player                              : AVAudioPlayer?
    
    //MARK: - IBAction functions
    
    @IBAction func onSwitchCamBtn(_ sender: Any) {
        update(clickedBtn: self.switchCamBtn)
        try? self.switchCameras()
    }
    
    @IBAction func onSwitchFlashBtn(_ sender: Any) {
        update(clickedBtn: self.switchFlashBtn)
    }
    
    @IBAction func onDoneBtn(_ sender: Any) {
        
    }
    
    @IBAction func onRecordBtn(_ sender: Any) {
        update(clickedBtn: self.recordBtn)
        
        isRecording = !isRecording
        
        if isRecording {
            self.isConnectedWithEarPiece = self.checkIfConnectedWithEarPiece()
            self.startRecording()
        } else {
            self.stopRecording()
        }
    }
    
    //MARK: - custom function
    func update(clickedBtn btn: UIButton) {
        func updateRecordBtn() {
            if isRecording {
                recordBtn.setTitle("Start", for: .normal)
            } else {
                recordBtn.setTitle("Stop", for: .normal)
            }
        }
        
        func updateSwitchCamBtn() {
            if self.currentCameraPosition == .front {
                switchCamBtn.setTitle("To Front", for: .normal)
            } else {
                switchCamBtn.setTitle("To Rear", for: .normal)
            }
        }
        
        func updateSwitchFlashBtn() {
            if self.flashMode == .on {
                switchFlashBtn.setTitle("Flash on", for: .normal)
            } else {
                switchFlashBtn.setTitle("Flash off", for: .normal)
            }
        }
        
        switch btn {
        case recordBtn:
            updateRecordBtn()
            break
        case switchCamBtn:
            updateSwitchCamBtn()
            break
        case switchFlashBtn:
            updateSwitchFlashBtn()
            break
        default:
            break
        }
    }
    
}

//MARK: - Override functions
extension RecordVC {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.configureAudioPlayer { (isSuccess, resultDescription) in
            if isSuccess {
                print("Succeed to configure audio player!")
            } else {
                let  alert = UIAlertController.init(title: "Video Merge Test", message: resultDescription, preferredStyle: .alert )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (okAction) in
                    self.dismiss(animated: true, completion: nil)
                }))
                self.present(alert, animated: true, completion: nil )
            }
        }
        
        self.manageAppUrlService = ManageAppURLService()
        
        self.checkDeviceAuthorizationStatus({ (isDeviceAccessGranted, resultDescription) in
            if isDeviceAccessGranted {
                self.configureCameraSession()
            } else {
                let  alert = UIAlertController.init(title: "VideoMergeTest", message: resultDescription, preferredStyle: .alert )
                let ok = UIAlertAction.init(title: "OK", style: .default, handler: nil)
                alert.addAction(ok)
                
                self.present(alert, animated: true, completion: nil )
            }
        })
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.clearTmpDirectory()
    }
    
}

//MARK: - Video merge
extension RecordVC {
    
    /// Merges video and sound while keeping sound of the video too
    ///
    /// - Parameters:
    ///   - videoUrl: URL to video file
    ///   - audioUrl: URL to audio file
    ///   - shouldFlipHorizontally: pass True if video was recorded using frontal camera otherwise pass False
    ///   - completion: completion of saving: error or url with final video
    func mergeVideoAndAudio(videoUrl: URL,
                            audioUrl: URL,
                            shouldFlipHorizontally: Bool = false,
                            completion: @escaping (_ error: Error?, _ url: URL?) -> Void) {
        
        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()
        
        //start merge
        
        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)
        
        let compositionAddVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let compositionAddAudio = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let compositionAddAudioOfVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                        preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let aVideoAssetTrack: AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video)[0]
        let aAudioOfVideoAssetTrack: AVAssetTrack? = aVideoAsset.tracks(withMediaType: AVMediaType.audio).first
        let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio)[0]
        
        // Default must have tranformation
        compositionAddVideo!.preferredTransform = aVideoAssetTrack.preferredTransform
        
        if shouldFlipHorizontally {
            // Flip video horizontally
            var frontalTransform: CGAffineTransform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            frontalTransform = frontalTransform.translatedBy(x: -aVideoAssetTrack.naturalSize.width, y: 0.0)
            frontalTransform = frontalTransform.translatedBy(x: 0.0, y: -aVideoAssetTrack.naturalSize.width)
            compositionAddVideo!.preferredTransform = frontalTransform
        }
        
        mutableCompositionVideoTrack.append(compositionAddVideo!)
        mutableCompositionAudioTrack.append(compositionAddAudio!)
        mutableCompositionAudioOfVideoTrack.append(compositionAddAudioOfVideo!)
        
        do {
            try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aVideoAssetTrack,
                                                                at: CMTime.zero)
            
            //In my case my audio file is longer then video file so i took videoAsset duration
            //instead of audioAsset duration
            if self.isConnectedWithEarPiece {
                let realDura = CMTimeSubtract(aVideoAssetTrack.timeRange.duration, self.startAudioTime)
                print("real video file duration ------> ", aVideoAsset.duration.seconds)
                print("real audio played duration  ------> ", realDura.seconds)
                
                try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                    duration: realDura),
                                                                    of: aAudioAssetTrack,
                                                                    at: self.startAudioTime)
            }
            
            // adding audio (of the video if exists) asset to the final composition
            if let aAudioOfVideoAssetTrack = aAudioOfVideoAssetTrack {
                try mutableCompositionAudioOfVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                           duration: aVideoAssetTrack.timeRange.duration),
                                                                           of: aAudioOfVideoAssetTrack,
                                                                           at: CMTime.zero)
            }
        } catch {
            print(error.localizedDescription)
        }
        
        // Exporting
        let fileName = self.manageAppUrlService.newVideoFileName()
        let savePathUrl = URL(fileURLWithPath: self.manageAppUrlService.getVideoFileFullPath(of: fileName))
        
        let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        assetExport.outputFileType = AVFileType.mp4
        assetExport.outputURL = savePathUrl
        assetExport.shouldOptimizeForNetworkUse = true
        
        assetExport.exportAsynchronously { () -> Void in
            switch assetExport.status {
            case .completed:
                print("success")
                self.newVideoItem!.fileName = fileName
                completion(nil, savePathUrl)
            case .failed:
                print("failed \(assetExport.error?.localizedDescription ?? "error nil")")
                completion(assetExport.error, nil)
            case .cancelled:
                print("cancelled \(assetExport.error?.localizedDescription ?? "error nil")")
                completion(assetExport.error, nil)
            default:
                print("complete")
                completion(assetExport.error, nil)
            }
        }
        
    }
    
    func mergeFilesWithUrl(videoUrl: URL, audioUrl: URL, completion: @escaping (Bool, String) -> Void) {
        let mixComposition = AVMutableComposition()
        
        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)
        
        let videoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioOfVideoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let aVideoAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video)[0]
        let aAudioAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio)[0]
        let aAudioOfVideoAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.audio).first
        
        // Default must have tranformation
        videoTrack!.preferredTransform = aVideoAssetTrack.preferredTransform
        
        do {
            try videoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: CMTime.zero)
            
            //            if self.isConnectedWithEarPiece {
            //                let timeScale = aAudioAsset.duration.timescale
            //                let startTime = CMTime(seconds: self.startAudioTime!, preferredTimescale: timeScale)
            ////                let startTime = CMTime(seconds: 0, preferredTimescale: 600)
            //                print("Time started audio file with headphone ----------> ", startTime, ", TimeScale is -----> ", timeScale)
            //                try audioTrack!.insertTimeRange(CMTimeRangeMake(start: startTime, duration: aVideoAssetTrack.timeRange.duration), of: aAudioAssetTrack, at: startTime)
            //                try audioOfVideoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aAudioOfVideoAssetTrack!, at: CMTime.zero)
            //            } else {
            try videoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: CMTime.zero)
            
            try audioOfVideoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aAudioOfVideoAssetTrack!, at: CMTime.zero)
            //            }
        } catch {
            print(error.localizedDescription)
        }
        //////////////////////////////////////////////////////////////////////////////////////////////////
        
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: mixComposition.duration)
        
        let videolayerInstruction = AVMutableVideoCompositionLayerInstruction.init(assetTrack: videoTrack! )
        var isVideoAssetPortrait = false
        let videoTransform : CGAffineTransform = aVideoAssetTrack.preferredTransform
        
        if (videoTransform.a == 0 && videoTransform.b == 1.0 && videoTransform.c == -1.0 && videoTransform.d == 0) {
            //    videoAssetOrientation = UIImageOrientation.right
            isVideoAssetPortrait = true
        }
        if (videoTransform.a == 0 && videoTransform.b == -1.0 && videoTransform.c == 1.0 && videoTransform.d == 0) {
            //    videoAssetOrientation =  UIImageOrientation.left
            isVideoAssetPortrait = true
        }
        if (videoTransform.a == 1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == 1.0) {
            //    videoAssetOrientation =  UIImageOrientation.up
        }
        if (videoTransform.a == -1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == -1.0) {
            //    videoAssetOrientation = UIImageOrientation.down
        }
        videolayerInstruction.setTransform(aVideoAssetTrack.preferredTransform, at: CMTime.zero)
        videolayerInstruction.setOpacity(0.0, at:mixComposition.duration)
        
        mainInstruction.layerInstructions = NSArray(object: videolayerInstruction) as! [AVVideoCompositionLayerInstruction]
        
        let mainCompositionInst = AVMutableVideoComposition()
        
        var naturalSize = CGSize()
        if isVideoAssetPortrait {
            naturalSize = CGSize(width: aVideoAssetTrack.naturalSize.height, height: aVideoAssetTrack.naturalSize.width)
        } else {
            naturalSize = aVideoAssetTrack.naturalSize
        }
        
        var renderWidth = 0.0, renderHeight = 0.0
        renderWidth = Double(naturalSize.width)
        renderHeight = Double(naturalSize.height)
        
        mainCompositionInst.renderSize = CGSize(width: renderWidth, height: renderHeight)
        mainCompositionInst.instructions = NSArray(object: mainInstruction) as! [AVVideoCompositionInstructionProtocol]
        mainCompositionInst.frameDuration = CMTimeMake(value: 1, timescale: 30)
        
        
        let fileName = self.manageAppUrlService.newVideoFileName()
        let savePathUrl = URL(fileURLWithPath: self.manageAppUrlService.getVideoFileFullPath(of: fileName))
        
        let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        assetExport.outputFileType = AVFileType.mov
        assetExport.outputURL = savePathUrl
        assetExport.shouldOptimizeForNetworkUse = true
        assetExport.videoComposition = mainCompositionInst
        
        assetExport.exportAsynchronously { () -> Void in
            switch assetExport.status {
                
            case .completed:
                self.newVideoItem!.fileName = fileName
                completion(true, "success")
                
            case  .failed:
                completion(false, "failed \(assetExport.error ?? "Error" as! Error)")
                
            case .cancelled:
                completion(false, "cancelled \(assetExport.error ?? "Error" as! Error)")
                
            case .exporting:
                completion(false, "exporting \(assetExport.error ?? "Error" as! Error)")
                
            case .waiting:
                completion(false, "waiting \(assetExport.error ?? "Error" as! Error)")
                
            case .unknown:
                completion(false, "unknown \(assetExport.error ?? "Error" as! Error)")
            }
        }
    }
}

//MARK: - Camera functions
extension RecordVC {
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
            self.captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        }
        
        func configureCaptureDevices() throws {
            
            let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
            let cameras = session.devices.compactMap({ $0 })
            guard cameras.count != 0, !cameras.isEmpty else {
                throw CameraServiceError.noCamerasAvailable
            }
            
            for camera in cameras {
                if camera.position == .front {
                    self.frontCamera = camera
                }
                
                if camera.position == .back {
                    self.rearCamera = camera
                }
            }
        }
        
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraServiceError.captureSessionIsMissing }
            
            if let rearCamera = self.rearCamera {
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                
                if captureSession.canAddInput(self.rearCameraInput!) { captureSession.addInput(self.rearCameraInput!) }
                
                self.currentCameraPosition = .rear
            } else
            if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!) }
                else { throw CameraServiceError.inputsAreInvalid }
                
                self.currentCameraPosition = .front
            } else
            { throw CameraServiceError.noCamerasAvailable }
        }
        
        func configureAudioCaptureDevice() throws {
            
            guard let audioDevice = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified) else {
                throw CameraServiceError.noCamerasAvailable
            }
            
            let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice )
            
            guard let captureSession = self.captureSession else { throw CameraServiceError.captureSessionIsMissing }
            
            if captureSession.canAddInput(audioDeviceInput!) {
                captureSession.addInput(audioDeviceInput!)
            }
        }
        
        func configureMovieOutput() throws {
            
            guard let captureSession = self.captureSession else { throw CameraServiceError.captureSessionIsMissing }
            
            self.movieFileOutput = AVCaptureMovieFileOutput()
            
            if captureSession.canAddOutput(self.movieFileOutput!) {
                captureSession.addOutput(self.movieFileOutput!)
                
                let connection = self.movieFileOutput?.connection(with: AVMediaType.video )
                
                if ( connection?.isVideoStabilizationSupported )! {
                    connection?.preferredVideoStabilizationMode = .auto
                }
            }
        }
        
        func configurePhotoOutput() throws {
            guard let captureSession = self.captureSession else { throw CameraServiceError.captureSessionIsMissing }
            
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput!) { captureSession.addOutput(self.photoOutput!) }
            
            captureSession.startRunning()
        }
        
        func setAudioSession() throws {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.playAndRecord,
                                             mode: AVAudioSession.Mode.videoRecording,
                                             options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            } catch {
                print("Can't Set Audio Session Category: \(error)")
                throw CameraServiceError.cannotSetAudioSession
            }
            // Start Session
            do {
                try audioSession.setActive(true)
            } catch {
                print("Can't Start Audio Session: \(error)")
                throw CameraServiceError.cannotSetAudioSession
            }
        }
        
        self.sessionQueue = DispatchQueue(label: "PrepareForCamera")
        self.sessionQueue.async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configureAudioCaptureDevice()
                try configureMovieOutput()
                try configurePhotoOutput()
                try setAudioSession()
            } catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                return
            }
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func displayPreview() throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraServiceError.captureSessionIsMissing }
        
        self.previewView.setSession(session: captureSession)
        DispatchQueue.main.async {
            let orientation: AVCaptureVideoOrientation?
            switch UIApplication.shared.statusBarOrientation
            {
            case .landscapeLeft:
                orientation = .landscapeLeft
            case .landscapeRight:
                orientation = .landscapeRight
            case .portrait:
                orientation = .portrait
            case .portraitUpsideDown:
                orientation = .portraitUpsideDown
            case .unknown:
                orientation = nil
            }

            if let orientation = orientation {
                (self.previewView.layer as! AVCaptureVideoPreviewLayer).connection?.videoOrientation = orientation
            }

        }
    }
    
    func checkDeviceAuthorizationStatus(_ completion: @escaping (Bool, String) -> Void) {
        let mediaType = AVMediaType.video
        
        AVCaptureDevice.requestAccess(for: mediaType) { (granted) in
            if (granted) {
                completion(true, "Granted!")
            } else {
                completion(false, "VideoMergeTest doesn't have permission to use Camera, please change privacy settings")
            }
        }
    }
    
    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else { throw CameraServiceError.captureSessionIsMissing }
        
        captureSession.beginConfiguration()
        
        func switchToFrontCamera() throws {
            guard captureSession.inputs.count != 0, let rearCameraInput = self.rearCameraInput, captureSession.inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else { throw CameraServiceError.invalidOperation }
            
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                
                self.currentCameraPosition = .front
            }
                
            else { throw CameraServiceError.invalidOperation }
        }
        
        func switchToRearCamera() throws {
            guard captureSession.inputs.count != 0, let frontCameraInput = self.frontCameraInput, captureSession.inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else { throw CameraServiceError.invalidOperation }
            
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                
                self.currentCameraPosition = .rear
            }
                
            else { throw CameraServiceError.invalidOperation }
        }
        
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera()
            
        case .rear:
            try switchToFrontCamera()
        }
        
        captureSession.commitConfiguration()
    }
    
    func configureCameraSession() {
        self.prepare {(error) in
            if let error = error {
                print(error)
            } else {
                try? self.displayPreview()
            }
        }
    }
    
    func startRecording() {
        
        self.movieFileOutput!.movieFragmentInterval = CMTime.invalid
        
        self.movieFileOutput!.connection(with: AVMediaType.video)?.videoOrientation = ((self.previewView.layer as! AVCaptureVideoPreviewLayer).connection?.videoOrientation)!
        
        // Start recording to a temporary file.
        let fileName = self.manageAppUrlService.newVideoFileName()
        let outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        
        self.movieFileOutput!.startRecording(to: outputFilePath, recordingDelegate:self as AVCaptureFileOutputRecordingDelegate )
    }
    
    func stopRecording() {
        print("clicked stop button just now ------> ", self.movieFileOutput?.recordedDuration.seconds ?? 0)
        self.startAudioTime = self.movieFileOutput?.recordedDuration ?? CMTime.zero
        
        self.movieFileOutput!.stopRecording()
        print(self.movieFileOutput?.recordedDuration.seconds)
    }
    
}

//MARK: - AVCaptureFileOutputRecordingDelegate
extension RecordVC : AVCaptureFileOutputRecordingDelegate {
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        
        self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.setTimer(timer:)), userInfo: nil, repeats: true )
        
        DispatchQueue.global().async {
            self.player?.play()
        }
        
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        print("output did finished just now ------> ",output.recordedDuration.seconds)
        self.player?.stop()
        
        self.timer.invalidate()
        self.timer = nil
        
        let videoItem = VideoItem()
        
        if let previewImg = thumbnailFromVideoAtURL(url: outputFileURL, andTime: CMTime.zero) {
            videoItem.previewImg = previewImg
        }
        videoItem.fileName = self.manageAppUrlService.getFileName(from: outputFileURL)
        
        self.newVideoItem = videoItem
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let saveAction = UIAlertAction(title: "Save and Exit", style: .default) { (saveAction) in
            self.saveNewVideoToAppDir()
        }
        let exitAction = UIAlertAction(title: "Exit", style: .default) { (exitAction) in
            self.dismiss(animated: true, completion: nil)
        }
        
        actionSheet.addAction(saveAction)
        actionSheet.addAction(exitAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
}

//MARK: - AVAudioPlayerDelegate
extension RecordVC : AVAudioPlayerDelegate {
    
    
    
}

//MARK: - Other functions
extension RecordVC {
    
    @objc func setTimer( timer : Timer) {
        let duration : Double = self.movieFileOutput?.recordedDuration.seconds ?? 0.0
        let timeNow = String( format :"%02d:%02d", Int(duration.rounded(.up)/60), Int(duration.rounded(.up))%60);

        self.timeLbl.text = timeNow
    }
    
    func saveNewVideoToAppDir() {
        self.progressHUD.showHUD(self.view)
        
        self.startAudioTime = CMTimeSubtract((self.movieFileOutput?.recordedDuration)!, self.startAudioTime)
        print(self.startAudioTime.seconds)
        
        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent((self.newVideoItem?.fileName)!)
        let audioUrl = Bundle.main.url(forResource: "test", withExtension: "mp3")
        
        self.mergeVideoAndAudio(videoUrl: videoUrl, audioUrl: audioUrl!) { (error, url) in
            var content : String
            if error == nil{
                content = "Succeed!"
                
                let defaults = UserDefaults.standard
                var videoItemArray = [VideoItem]()
                if let encodedObject = defaults.object(forKey: C_LocalVideoItemsKey) {
                    let object = NSKeyedUnarchiver.unarchiveObject(with: encodedObject as! Data )
                    videoItemArray = object as! [VideoItem]
                }
                
                videoItemArray.append(self.newVideoItem!)
                let encodedObject = NSKeyedArchiver.archivedData(withRootObject: videoItemArray )
                defaults.set(encodedObject, forKey: C_LocalVideoItemsKey )
            }
            else{
                content = (error?.localizedDescription)!
            }
            DispatchQueue.main.async {
                let  alert = UIAlertController(title: "VideoMergeTest", message: content, preferredStyle: .alert )
                let ok = UIAlertAction(title: "Ok", style: .default, handler: { (okAction) in
                    self.delegate.onDismiss()
                    self.dismiss(animated: true, completion: nil)
                })
                alert.addAction(ok)
                
                self.present(alert, animated: true, completion: nil )
                
                self.progressHUD.hideHUD()
            }
        }
//        self.mergeFilesWithUrl(videoUrl: videoUrl, audioUrl: audioUrl!) { (isSuccess, resultDescription) in
//            var content : String
//
//            if isSuccess {
//                content = "Succeed!"
//
//                let defaults = UserDefaults.standard
//                var videoItemArray = [VideoItem]()
//                if let encodedObject = defaults.object(forKey: C_LocalVideoItemsKey) {
//                    let object = NSKeyedUnarchiver.unarchiveObject(with: encodedObject as! Data )
//                    videoItemArray = object as! [VideoItem]
//                }
//
//                videoItemArray.append(self.newVideoItem!)
//                let encodedObject = NSKeyedArchiver.archivedData(withRootObject: videoItemArray )
//                defaults.set(encodedObject, forKey: C_LocalVideoItemsKey )
//
//            } else {
//                content = resultDescription
//            }
//
//            DispatchQueue.main.async {
//                let  alert = UIAlertController(title: "VideoMergeTest", message: content, preferredStyle: .alert )
//                let ok = UIAlertAction(title: "Ok", style: .default, handler: { (okAction) in
//                    self.delegate.onDismiss()
//                    self.dismiss(animated: true, completion: nil)
//                })
//                alert.addAction(ok)
//
//                self.present(alert, animated: true, completion: nil )
//
//                self.progressHUD.hideHUD()
//            }
//        }
    }
    
    func deleteFileAtPath(with fileName: String?) {
        guard let name = fileName else {
            return
        }
        let urlStr = self.manageAppUrlService.getVideoFileFullPath(of: name)
        let path = URL(fileURLWithPath: urlStr)
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: path.path) {
                try fileManager.removeItem(atPath: path.path)
            } else {
                print("There is no such file to be deleted!")
            }
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }
    
    func thumbnailFromVideoAtURL( url: URL, andTime time: CMTime) -> UIImage? {
        
        func imageWithImage( image:UIImage, scaledToSize newSize:CGSize ) -> UIImage {
            UIGraphicsBeginImageContext( newSize )
            image.draw(in: CGRect( x: 0, y: 0, width: newSize.width, height: newSize.height ))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage!
        }
        
        let asset = AVAsset(url: url)
        var thumbnailTime = asset.duration
        thumbnailTime.value = 0
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        var thumbnail : UIImage!
        do {
            let imageRef = try imageGenerator.copyCGImage(at: time, actualTime: nil )
            autoreleasepool{
                thumbnail = UIImage(cgImage: imageRef)
                let size = CGSize(width: 106, height: 72)
                thumbnail = imageWithImage(image: thumbnail, scaledToSize: size )
            }
        } catch {
            print(error.localizedDescription)
            return nil
        }
        
        thumbnail = imageWithImage(image: thumbnail, scaledToSize: CGSize(width: 1920, height: 1080) )
        
        return thumbnail
    }
    
    func clearTmpDirectory() {
        do {
            let fileManager = FileManager.default
            let tmpDirURL = fileManager.temporaryDirectory
            let tmpDirectory = try fileManager.contentsOfDirectory(at: tmpDirURL, includingPropertiesForKeys: nil)
            try tmpDirectory.forEach { file in
                try fileManager.removeItem(atPath: file.path)
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func checkIfConnectedWithEarPiece() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        for description in route.outputs {
            if description.portType == AVAudioSession.Port.bluetoothA2DP || description.portType == AVAudioSession.Port.headphones {
                return true
            }
        }
        return false
    }
    
    func configureAudioPlayer(_ completion: @escaping (Bool, String) -> Void) {
        guard let url = Bundle.main.url(forResource: "test", withExtension: "mp3") else {
            completion(false, "There is no sound file!")
            return
        }
        
        do {
            
            self.player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            
            if self.player == nil {
                completion(false, "Couldn't configure a player with this file!")
            } else {
                
                let isPreparedForPlaying = self.player?.prepareToPlay() ?? false
                if !isPreparedForPlaying {
                    completion(false, "Failed to prepare audio file to be preload!")
                }
                
                self.player?.delegate = self
                
                completion(true, "Success!")
            }
            
        } catch let error {
            print(error.localizedDescription)
            completion(false, error.localizedDescription)
        }
    }
    
}

extension RecordVC {
    enum CameraServiceError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case cannotSetAudioSession
        case unknown
    }
    
    public enum CameraPosition {
        case front
        case rear
    }
}
