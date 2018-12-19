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
    
    var frontCameraInput                    : AVCaptureDeviceInput?
    var frontCamera                         : AVCaptureDevice?
    
    var rearCameraInput                     : AVCaptureDeviceInput?
    var rearCamera                          : AVCaptureDevice?
    
    var videoDataOutput                     : AVCaptureVideoDataOutput?
    var audioDataOutput                     : AVCaptureAudioDataOutput?
    
    var isRecording                         : Bool = false
    
    var currentCameraPosition               : CameraPosition?
    
    var newVideoItem                        : VideoItem?
    
    var progressHUD                         : JGProgressHUDService! = JGProgressHUDService()
    
    var timer                               : Timer!
    
    var isConnectedWithEarPiece             : Bool = false
    
    var player                              : AVAudioPlayer?
    
    lazy var captureSession: AVCaptureSession = {
        let s = AVCaptureSession()
        s.sessionPreset = AVCaptureSession.Preset(rawValue: convertFromAVCaptureSessionPreset(AVCaptureSession.Preset.hd1920x1080))
        return s
    }()
    
    var sampleBufferGlobal                  : CMSampleBuffer?
    var presentationTime                    : CMTime?
    var outputSettings                      = [String: Any]()
    var videoWriterInput                    : AVAssetWriterInput!
    var audioWriterInput                    : AVAssetWriterInput!
    var assetWriter                         : AVAssetWriter!
    var justClickedStopBtn                  : Bool = false
    
    //MARK: - IBAction functions
    @IBAction func onRecordBtn(_ sender: Any) {
        update(clickedBtn: self.recordBtn)
        
        isRecording = !isRecording
        
        if isRecording {
            self.isConnectedWithEarPiece = self.checkIfConnectedWithEarPiece()
            self.startRecording()
        } else {
            self.justClickedStopBtn = true
            self.stopRecording()
        }
    }
    
    @IBAction func onSwitchCamBtn(_ sender: Any) {
        update(clickedBtn: self.switchCamBtn)
        try? self.switchCameras()
    }
    
    @IBAction func onSwitchFlashBtn(_ sender: Any) {
        update(clickedBtn: self.switchFlashBtn)
    }
    
    @IBAction func onDoneBtn(_ sender: Any) {
        
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
//            if self.flashMode == .on {
//                switchFlashBtn.setTitle("Flash on", for: .normal)
//            } else {
//                switchFlashBtn.setTitle("Flash off", for: .normal)
//            }
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.displayPreview()
        
        captureSession.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.clearTmpDirectory()
    }
    
}

//MARK: - Video merge
extension RecordVC {
    
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
        let aAudioOfVideoAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.audio)[0]
        
        // Default must have tranformation
        videoTrack!.preferredTransform = aVideoAssetTrack.preferredTransform
        
        do {
            
            if self.isConnectedWithEarPiece {
                let duration = aVideoAsset.duration
                
//                audioTrack?.scaleTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration), toDuration: duration)
                
                try videoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration), of: aVideoAssetTrack, at: CMTime.zero)
                
                try audioTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration), of: aAudioAssetTrack, at: CMTime.zero)
                
                try audioOfVideoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration), of: aAudioOfVideoAssetTrack, at: CMTime.zero)
                
            } else {
                
                try videoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: CMTime.zero)
                
                try audioOfVideoTrack!.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: aVideoAssetTrack.timeRange.duration), of: aAudioOfVideoAssetTrack, at: CMTime.zero)
            }
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

//MARK: - Camera & Audio functions
extension RecordVC {
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        
        func configureCaptureDevices() throws {
            self.frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            self.rearCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        
        func configureDeviceInputs() throws {
            
            if let rearCamera = self.rearCamera {
                do {
                    self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                    
                    if captureSession.canAddInput(self.rearCameraInput!) { captureSession.addInput(self.rearCameraInput!) }
                    
                    self.currentCameraPosition = .rear
                } catch {
                    throw CameraServiceError.inputsAreInvalid
                }
            }
            else
            if let frontCamera = self.frontCamera {
                do {
                    self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                    
                    if captureSession.canAddInput(self.frontCameraInput!) {
                        captureSession.addInput(self.frontCameraInput!)
                    }
                    else {
                        throw CameraServiceError.inputsAreInvalid
                    }
                    
                    self.currentCameraPosition = .front
                } catch {
                    throw CameraServiceError.inputsAreInvalid
                }
            }
            else
            { throw CameraServiceError.noCamerasAvailable }
        }
        
        func configureAudioCaptureDevice() throws {
            
            guard let audioDevice = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified) else {
                throw CameraServiceError.noCamerasAvailable
            }
            
            do {
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice )
                
                if captureSession.canAddInput(audioDeviceInput) {
                    captureSession.addInput(audioDeviceInput)
                }
            } catch {
                throw CameraServiceError.inputsAreInvalid
            }
        }
        
        func configureVideoAudioDataOutput() {
            
            self.videoDataOutput = AVCaptureVideoDataOutput()
            self.videoDataOutput?.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as UInt32)] as [String : Any]
            self.videoDataOutput?.alwaysDiscardsLateVideoFrames = true
            
            self.audioDataOutput = AVCaptureAudioDataOutput()
            
            if captureSession.canAddOutput(self.videoDataOutput!) {
                captureSession.addOutput(self.videoDataOutput!)
            }
            
            if captureSession.canAddOutput(self.audioDataOutput!) {
                captureSession.addOutput(self.audioDataOutput!)
            }
            
            captureSession.commitConfiguration()
            
            self.sessionQueue = DispatchQueue(label: "com.videomergetest.videoQueue", qos: .utility, attributes: .concurrent)
            self.videoDataOutput?.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.audioDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.videomergetest.audioQueue", qos: .utility, attributes: .concurrent))
            
        }
        
        func setAudioSession() throws {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.videoRecording, options: AVAudioSession.CategoryOptions.mixWithOthers)
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
        
        func setupAssetWriter () throws {
            outputSettings = [AVVideoCodecKey   : AVVideoCodecType.h264,
                              AVVideoWidthKey   : NSNumber(value: 1920.0),
                              AVVideoHeightKey  : NSNumber(value: 1080.0),
                              AVVideoCompressionPropertiesKey : [
                                AVVideoAverageBitRateKey : 2300000,
                              ]
                             ] as [String : Any]
            
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: nil)
            
            videoWriterInput.expectsMediaDataInRealTime = true
            audioWriterInput.expectsMediaDataInRealTime = true
            
            let fileName = self.manageAppUrlService.newVideoFileName()
            let outputFileUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
            do {
                assetWriter = try AVAssetWriter(outputURL: outputFileUrl, fileType: AVFileType.mov)
                if assetWriter.canAdd(videoWriterInput) {
                    assetWriter.add(videoWriterInput)
                }
                
                if assetWriter.canAdd(audioWriterInput) {
                    assetWriter.add(audioWriterInput)
                }
            } catch {
                throw CameraServiceError.inputsAreInvalid
            }
            
        }
        
        self.sessionQueue = DispatchQueue(label: "PrepareForCamera")
        self.sessionQueue.async {
            do {
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configureAudioCaptureDevice()
                configureVideoAudioDataOutput()
                try setAudioSession()
                try setupAssetWriter()
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
    
    func displayPreview() {
        
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
        guard let currentCameraPosition = currentCameraPosition, self.captureSession.isRunning else { throw CameraServiceError.captureSessionIsMissing }
        
        self.captureSession.beginConfiguration()
        
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
                let  alert = UIAlertController(title: "VideoMergeTest", message: error.localizedDescription, preferredStyle: .alert )
                let ok = UIAlertAction(title: "Ok", style: .default, handler: nil)
                alert.addAction(ok)
                self.present(alert, animated: true, completion: nil )
            } 
        }
    }
    
    func startRecording() {
        
        self.presentationTime = nil
//        setUpWriter()
        
        assetWriter.startWriting()
        self.player?.play()
        
        if assetWriter.status == .writing {
            print("status writing")
        } else if assetWriter.status == .failed {
            print("status failed")
        } else if assetWriter.status == .cancelled {
            print("status cancelled")
        } else if assetWriter.status == .unknown {
            print("status unknown")
        } else {
            print("status completed")
        }
    }
    
    func stopRecording() {
        audioWriterInput.markAsFinished()
        videoWriterInput.markAsFinished()
        print("marked as finished")
        
        assetWriter?.finishWriting(completionHandler: {
            
            self.videoDataOutput = nil
            self.audioDataOutput = nil
            
            self.audioWriterInput = nil
            self.videoWriterInput = nil
            
            self.player?.stop()
            self.presentationTime = nil
            if (self.assetWriter?.status == AVAssetWriter.Status.failed) {
                let  alert = UIAlertController(title: "VideoMergeTest", message: "Cannot create a movie file right now!", preferredStyle: .alert )
                let ok = UIAlertAction(title: "Ok", style: .default, handler: nil)
                alert.addAction(ok)
                self.present(alert, animated: true, completion: nil )
            } else {
                
                DispatchQueue.main.async {
                    let videoItem = VideoItem()
                    print(self.assetWriter.outputURL)
                    if let previewImg = self.thumbnailFromVideoAtURL(url: self.assetWriter.outputURL, andTime: CMTime.zero) {
                        videoItem.previewImg = previewImg
                    }
                    videoItem.fileName = self.manageAppUrlService.getFileName(from: self.assetWriter.outputURL)
                    
                    self.newVideoItem = videoItem
                    
                    self.assetWriter = nil
                    
                    let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                    let saveAction = UIAlertAction(title: "Save and Exit", style: .default) { (saveAction) in
                        self.saveNewVideoToAppDir()
                    }
                    let exitAction = UIAlertAction(title: "Exit", style: .default) { (exitAction) in
                        self.dismiss(animated: true, completion: nil)
                    }
                    
                    actionSheet.addAction(saveAction)
                    actionSheet.addAction(exitAction)
                    self.present(actionSheet, animated: true, completion: nil)
                }
            }
        })
        
        captureSession.stopRunning()
    }
    
}

//MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate
extension RecordVC : AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let writable = canWrite()
        if writable, presentationTime == nil {
            presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: presentationTime!)
        }
        
        if captureOutput == videoDataOutput {
            connection.videoOrientation = .portrait
            
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        if writable, captureOutput == videoDataOutput, videoWriterInput.isReadyForMoreMediaData {
            videoWriterInput.append(sampleBuffer)
        } else
        if writable, captureOutput == audioDataOutput, audioWriterInput.isReadyForMoreMediaData {
            audioWriterInput?.append(sampleBuffer)
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Here you can count how many frames are dopped
    }
    
}

//MARK: - AVAudioPlayerDelegate
extension RecordVC : AVAudioPlayerDelegate {
    
    
    
}

//MARK: - Other functions
extension RecordVC {
    
    @objc func setTimer( timer : Timer) {
//        let duration : Double = self.movieFileOutput?.recordedDuration.seconds ?? 0.0
//        let timeNow = String( format :"%02d:%02d", Int(duration.rounded(.up)/60), Int(duration.rounded(.up))%60);
//
//        self.timeLbl.text = timeNow
    }
    
    func saveNewVideoToAppDir() {
        self.progressHUD.showHUD(self.view)
        
        let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent((self.newVideoItem?.fileName)!)
        let audioUrl = Bundle.main.url(forResource: "test", withExtension: "mp3")
        
        self.mergeFilesWithUrl(videoUrl: videoUrl, audioUrl: audioUrl!) { (isSuccess, resultDescription) in
            var content : String
            
            if isSuccess {
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
                
            } else {
                content = resultDescription
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
    
    func canWrite() -> Bool {
        return isRecording && assetWriter != nil && assetWriter?.status == .writing
    }
    
    fileprivate func convertFromAVCaptureSessionPreset(_ input: AVCaptureSession.Preset) -> String {
        return input.rawValue
    }
    
    fileprivate func convertFromAVLayerVideoGravity(_ input: AVLayerVideoGravity) -> String {
        return input.rawValue
    }
    
    fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
        return input.rawValue
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
