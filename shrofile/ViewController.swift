//
//  ViewController.swift
//  shrofile
//
//  Created by Jatin Garg on 13/06/17.
//  Copyright © 2017 Jatin Garg. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import AVKit

private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

let videouploadUrl = "http://jlabs.co/socket/imageupload/video.php"

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    
    //MARK: - instance variables
    private let sessionQueue = DispatchQueue(label: "session queue",
                                             attributes: [],
                                             target: nil) // for communication with capture session
    private var setupResult: SessionSetupResult = .success
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private var sessionRunning: Bool = false
    private var sessionRunnningObservationContext = 0
    private var videoUploadProgressObservationContext = 0
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    private var uploadProgressKeyPath = "progress.fractionCompleted"
    private var uploader: VideoUploader?
    private var uploadURL: String?
    
    //MARK: - IBOutlets
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var recordBtn: UIButton!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var thumbnailImage: UIImageView!
    
    //MARK: - Overriden properties and methods
    override var prefersStatusBarHidden: Bool{
        return true
    }
    
    override var shouldAutorotate: Bool{
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        progressView.isHidden = true
        insertConceilingLayers()
        previewView.session = session
        recordBtn.isEnabled = false
        playButton.isHidden = true
        
        //check the video authorization status
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo){
        case .authorized:
            //the user has authorized video access
            break
        case .notDetermined:
            //permissions have not been presented yet
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (success) in
                if !success{
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            break
        default:
            //access was previously denied
            setupResult = .notAuthorized
            break
            
        }
        //setup the capture session
        sessionQueue.async { [unowned self] in
            self.configureCaptureSession()
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async {
            switch self.setupResult{
            case .success:
                //set observers and start the session
                self.setupObservers()
                self.session.startRunning()
                self.sessionRunning = self.session.isRunning
                break
            case .notAuthorized:
                DispatchQueue.main.async {
                    [unowned self] in
                    let changePrivacySetting = "I don't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "Shrofile", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                break
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "Shrofile", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                break
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeObservers()
    }

    
    //MARK: - Utility Methods
    private func insertConceilingLayers(){
        let topMargin = previewView.frame.origin.y
        let bottomMargin = UIScreen.main.bounds.height - (previewView.frame.height + topMargin)
        let v1 = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: topMargin))
        let v2 = UIView(frame: CGRect(x: 0, y: topMargin + previewView.frame.height, width: view.frame.height, height: bottomMargin))
        v1.backgroundColor = .black
        v2.backgroundColor = .black
        
        view.insertSubview(v1, belowSubview: recordBtn)
        view.insertSubview(v2, belowSubview: recordBtn)
    }
    
    private func configureCaptureSession(){
        if setupResult != .success{
            return
        }
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSessionPresetHigh
        
        //configure movieFileOutput
        let movieFileOutput = AVCaptureMovieFileOutput()
        if self.session.canAddOutput(movieFileOutput){
            self.session.addOutput(movieFileOutput)
            if let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo){
                if connection.isVideoStabilizationSupported{
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.movieFileOutput = movieFileOutput
            
        }
        
        //add video input
        
        var defaultVideoDevice: AVCaptureDevice?
        if  let videoDevice = AVCaptureDevice.defaultDevice(withDeviceType: AVCaptureDeviceType.builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front){
            defaultVideoDevice = videoDevice
        }else{
            //let the user know that front camera is not functioning
        }
        guard let videoDeviceInput = (try? AVCaptureDeviceInput(device: defaultVideoDevice!))
            else{
                print("Couldn't create video input")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
        }
        if session.canAddInput(videoDeviceInput){
            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            DispatchQueue.main.async {
                let statusBarOrientation = UIApplication.shared.statusBarOrientation
                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                
                //checking status bar's initial orientation and setting
                //video preview's orientation accordingly, if all goes well
                if statusBarOrientation != .unknown{
                    if let videoOrientation = statusBarOrientation.videoOrientation{
                        initialVideoOrientation = videoOrientation
                    }
                }
                self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
            }
            
        }else{
            print("Couldn't add video input device")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        //add audio input
        let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
        guard let audioDeviceInput = (try? AVCaptureDeviceInput(device: audioDevice!))
            else{
                print("Couldn't create audio device")
                return
        }
        if session.canAddInput(audioDeviceInput){
            session.addInput(audioDeviceInput)
        }else{
            print("Couldn't add audio input to session")
        }
        session.commitConfiguration()
    }
    
    private func setupObservers(){
        session.addObserver(self, forKeyPath: "running", options: .new, context: &sessionRunnningObservationContext)
    }
    
    private func removeObservers() {
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunnningObservationContext)
        uploader?.removeObserver(self, forKeyPath: uploadProgressKeyPath)
    }

    
    
    //MARK: - IBActions
    @IBAction func toggleRecording(_ sender: RecordButton) {
        if !sender.isRecording{
            //start recording
            guard let movieFileOutput = self.movieFileOutput else {
                return
            }
            recordBtn.isEnabled = false
            let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection.videoOrientation
            sessionQueue.async { [unowned self] in
                if !movieFileOutput.isRecording{
                    if UIDevice.current.isMultitaskingSupported{
                        //requesting background execution
                        self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                    }
                    let movieFileOutputConnection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo)
                    movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation
                    let videoSettings = [AVVideoCodecKey : AVVideoCodecH264] as [String : Any]
                    movieFileOutput.setOutputSettings(videoSettings, for: movieFileOutputConnection)
                    
                    //start recording to a temp file
                    let outputFileName = NSUUID().uuidString
                    let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                    movieFileOutput.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                    
                }else{
                    movieFileOutput.stopRecording()
                }
            }
        }else{
            movieFileOutput?.stopRecording()
        }
        sender.isRecording = !sender.isRecording
    }
    
    
    @IBAction func playMedia(_ sender: Any) {
        if let url = self.uploadURL{
            if let convertedURL = URL(string: url){
                let player = AVPlayer(url: convertedURL)
                let playerController = AVPlayerViewController()
                playerController.player = player
                present(playerController, animated: true){
                    player.play()
                }            }
        }
    }
    

    
    
    //MARK: AVCaptureFileOutputRecording Delegate Methods
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        DispatchQueue.main.async { [unowned self] in
            self.recordBtn.isEnabled = true
        }
    }
    
    
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        
        
        //since we are starting compression and upload in this method, we are going to disable 
        //record button
        
        DispatchQueue.main.async { [unowned self] in
            //using main dispatch because this might execute in background
            self.recordBtn.isEnabled = false
        }
        
        func cleanup(){
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path){
                do{
                    try FileManager.default.removeItem(at: outputFileURL)
                }catch{
                    print("Couldnt remove file at \(path)")
                }
            }
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskInvalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        if error != nil{
            print("Movie file fininshing error : \(error.localizedDescription)")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success{
            //cropping code
            let filename = "CroppedVideo"
            let documentsDirectory = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let croppedVideoPath =  documentsDirectory.appendingPathComponent(filename).appendingPathExtension("mp4")
            //removing previous file, if any
            if FileManager.default.fileExists(atPath: croppedVideoPath.path){
                try! FileManager.default.removeItem(at: croppedVideoPath)
            }
            let asset : AVAsset = AVAsset(url: outputFileURL)
            let composition : AVMutableComposition = AVMutableComposition()
            composition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
            let clipVideoTrack : AVAssetTrack = asset.tracks(withMediaType: AVMediaTypeVideo)[0] as AVAssetTrack
            
            let videoComposition: AVMutableVideoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTimeMake(1, 60)
            videoComposition.renderSize = CGSize(width: clipVideoTrack.naturalSize.height, height: clipVideoTrack.naturalSize.height)
            let instruction: AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, 30))
            let transformer: AVMutableVideoCompositionLayerInstruction =
                AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
            let t1: CGAffineTransform = CGAffineTransform(translationX: clipVideoTrack.naturalSize.height, y: -(clipVideoTrack.naturalSize.width - clipVideoTrack.naturalSize.height)/2 )
            let t2: CGAffineTransform = t1.rotated(by: CGFloat(M_PI_2))
            
            let finalTransform: CGAffineTransform = t2
            
            transformer.setTransform(finalTransform, at: kCMTimeZero)
            
            instruction.layerInstructions = NSArray(object: transformer) as! [AVVideoCompositionLayerInstruction]
            videoComposition.instructions = NSArray(object: instruction) as! [AVVideoCompositionInstructionProtocol]
            
            
            let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            exporter?.videoComposition = videoComposition
            exporter?.outputFileType = AVFileTypeQuickTimeMovie
            exporter?.outputURL = croppedVideoPath
            
            exporter?.exportAsynchronously(completionHandler: {
                //display video after export is complete, for example...
                let outputURL:NSURL = exporter!.outputURL! as NSURL;
                print("Cropped video saved at \(outputURL.path)")
                if FileManager.default.fileExists(atPath: outputURL.path!){
                    let asset = AVAsset(url: outputURL as URL)
                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                    let cgImage = try? imageGenerator.copyCGImage(at: CMTimeMake(0, 1), actualTime: nil)
                    let image = UIImage(cgImage: cgImage!)
                    DispatchQueue.main.async {
                        self.thumbnailImage.image = image
                    }
                    let videoData = NSData(contentsOfFile: outputURL.path!)
                    //uploading asset to server
                    self.uploader = VideoUploader(uploadUrl: URL(string: videouploadUrl)!, videoData: videoData as Data!)
                    self.uploader!.addObserver(self, forKeyPath: self.uploadProgressKeyPath, options: [], context: &self.videoUploadProgressObservationContext)
                    self.uploader!.completionHandler = {(error,url) in
                        if error != nil{
                            print("Encountered error whle uploading : \(String(describing: error))")
                        }else{
                            print("uploaded at : \(url!)")
                            self.uploadURL = url
                        }
                        self.uploader = nil
                        self.progressView.isHidden = true
                        self.playButton.isHidden = false
                        cleanup()
                        //enable camerabutton
                        DispatchQueue.main.async {
                            self.recordBtn.isEnabled = true
                        }
                    }
                    self.uploader!.startUploading()
                    
                }
            })
            
        }else{
            cleanup()
            //enable camerabutton
            DispatchQueue.main.async {
                self.recordBtn.isEnabled = true
            }
        }
        
    }
    
    
    
    //MARK: KVO
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunnningObservationContext{
            let newVal = change?[.newKey] as AnyObject
            guard let isSessionRunning = newVal.boolValue else {return}
            DispatchQueue.main.async {
                //enable caputure buttons
                self.recordBtn.isEnabled = isSessionRunning && self.movieFileOutput != nil
            }
            
            
        }else if context == &videoUploadProgressObservationContext{
            if keyPath == self.uploadProgressKeyPath{
                if let uploader = self.uploader{
                    if progressView.isHidden{
                        progressView.isHidden = false
                    }
                    progressView.progress = Float(uploader.progress.fractionCompleted)
                }else{
                    progressView.isHidden = true
                }
            }
        }else{
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    

}

