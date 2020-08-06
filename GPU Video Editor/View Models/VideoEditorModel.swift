//
//  VideoEditorModel.swift
//
//  Created by NhatHM on 9/5/19.
//  Copyright © 2019 NextMove. All rights reserved.
//

import Foundation
import CoreAudio
import AVFoundation
import GPUImage
import Photos
import UIKit

struct VideoTimingInfo {
    let duration    : Double
    let currentTime : Double
    let percent     : Double
    let finished    : Bool
}

struct VideoEditingTrimmingInfo {
    let isTrimming  : Bool
    let startTime   : Double
    let duration    : Double
}

struct VideoEditingSetting {
    let loopVideo   : Bool
    let trimInfo    : VideoEditingTrimmingInfo?
    let numberOfThumbnail: Int
    let continueFilterWhenFinished: Bool
}

enum VideoFilterOperationType: String, CaseIterable {
    case flip           = "Flip"
    case rotate         = "Rotate"
    case rgb            = "RGB"
    case constrast      = "Constrast"
    case brightness     = "Brightness"
    case saturation     = "Saturation"
}

protocol VideoEditorModelProtocol {
    // Config
    // Not supported yet
    func setListFilters(_ listFilterKeys: [VideoFilterOperationType])
    // Set up render view
    func setupRenderView(with renderView: RenderView)
    // Set up video editting setting before render
    func settingVideoEditting(_ setting: VideoEditingSetting)
    // Init video editting settings
    func setupVideoEdittingEngine(_ success: @escaping () -> Void, _ failed: @escaping (String) -> Void)
    // Trim video with start time and duration
    func trimVideoWith(_ start: Double, _ duration: Double)
    // Get list thumbnail images
    func listThumnailImages(_ success: @escaping ([UIImage]) -> Void, _ failed: @escaping (String) -> Void)
    
    func listVideoFilterOperations() -> Array<VideoFilterOperationInterface>
    func videoFilterForType(_ type: VideoFilterOperationType) -> VideoFilterOperationInterface?
    
    // Start video
    func startVideo(_ atTime: Double)
    func startVideoWithCallBack(_ atTime: Double, _ callBack: ((VideoTimingInfo) -> Void)?)
    // Seek
    func seekToTime(_ atTime: Double)
    
    func pauseVideo()
    func continueVideo()
    func stopVideo()
    
    func exportVideoToPath(_ path: URL, _ completed: @escaping (Double, Bool) -> Void, _ failed: (String) -> Void)
}

class VideoEditorModel {
    private var kPreferredTimescale = CMTimeScale(600)
    
    private var listFilters: [VideoFilterOperationType]
    private var playRange: MovieInputTimeRange?
    private var videoEdittingSetting: VideoEditingSetting
    
    private var asset: AVAsset!
    private let videoURL: URL?
    
    private var movieInput: MovieInput?
    private var movieOutput: MovieOutput?
    private var speaker: SpeakerOutput?
    private var renderView: RenderView?
    
    private let movieOperationGroup = OperationGroup()

    private var videoSize: Size!
    private var videoOrientation: ImageOrientation!
    
    let flipFilter = VideoFilterOperation(
        filterName: VideoFilterOperationType.flip.rawValue.uppercased(),
        videoFilter: TransformOperation(),
        slideConfig: .enabled(minValue: 0, maxValue: 6.28, initValue: 0.0, currentValue: 0.0),
        currentSlideType: .none,
        currentSlideValue: 0.0, slideUpdateCallback: { (filter, slideValue) in
            var perspectiveTransform = CATransform3DIdentity
            perspectiveTransform.m34 = 0.4
            perspectiveTransform.m33 = 0.4
            perspectiveTransform = CATransform3DScale(perspectiveTransform, 0.75, 0.75, 0.75)
            perspectiveTransform = CATransform3DRotate(perspectiveTransform, CGFloat(slideValue), 0.0, 1.0, 0.0)
            filter.transform = Matrix4x4(perspectiveTransform)
        }
    )
    
    let rotateFilter = VideoFilterOperation(
        filterName: "Rotate",
        videoFilter: TransformOperation(),
        slideConfig: .enabled(minValue: 0, maxValue: 6.28, initValue: 0.0, currentValue: 0.0),
        currentSlideType: .none,
        currentSlideValue: 0.0, slideUpdateCallback: { (filter, slideValue) in
            filter.transform = Matrix4x4(CGAffineTransform(rotationAngle:CGFloat(slideValue)))
        }
    )
    
    let rgbFilter = VideoFilterOperation(
        filterName: "RGB",
        videoFilter: RGBAdjustment(),
        slideConfig: .enabled(minValue: 0, maxValue: 2, initValue: 1, currentValue: 1),
        currentSlideType: .red,
        currentSlideValue: 1,
        slideUpdateWithTypeCallback: { (filter, slideValue, slideType) in
            print("slide type = \(slideType)")
            print("slide value = \(slideValue)")
            switch slideType {
            case .red:
                filter.red = slideValue
            case .green:
                filter.green = slideValue
            case .blue:
                filter.blue = slideValue
            default:
                break
            }
        }
    )
    
    let contrastFilter = VideoFilterOperation(
        filterName: "Constrast",
        videoFilter: ContrastAdjustment(),
        slideConfig: .enabled(minValue: 0, maxValue: 2, initValue: 1, currentValue: 1),
        currentSlideType: .none,
        currentSlideValue: 1,
        slideUpdateCallback: { (filter, slideValue) in
            print("Slide value = \(slideValue)")
            filter.contrast = slideValue
        }
    )
    
    let brightnessFilter = VideoFilterOperation(
        filterName: "Brightness",
        videoFilter: BrightnessAdjustment(),
        slideConfig: .enabled(minValue: -1.0, maxValue: 1.0, initValue: 0, currentValue: 1),
        currentSlideType: .none,
        currentSlideValue: 0,
        slideUpdateCallback: { (filter, slideValue) in
            print("Slide value = \(slideValue)")
            filter.brightness = slideValue
        }
    )
    
    let saturationFilter = VideoFilterOperation(
        filterName: "Saturation",
        videoFilter: SaturationAdjustment(),
        slideConfig: .enabled(minValue: 0, maxValue: 2.0, initValue: 1.0, currentValue: 1),
        currentSlideType: .none,
        currentSlideValue: 1,
        slideUpdateCallback: { (filter, slideValue) in
            print("Slide value = \(slideValue)")
            filter.saturation = slideValue
        }
    )
    
    init(videoUrl: URL?, renderView: RenderView?) {
        self.videoURL = videoUrl
        self.renderView = renderView
        self.listFilters = []
        self.videoEdittingSetting = VideoEditingSetting(loopVideo: false, trimInfo: nil, numberOfThumbnail: -1, continueFilterWhenFinished: true)
        self.videoOrientation = .portrait
        if let videoURL = self.videoURL {
            self.createAsset(videoURL)
        }
    }
    
    deinit {
        movieInput?.cancel()
        movieInput = nil
        asset = nil
        
        print("Video editor model deinit")
    }
}

// Commons
extension VideoEditorModel {
    @discardableResult private func createAsset(_ url: URL) -> AVAsset {
        let inputOptions = [AVURLAssetPreferPreciseDurationAndTimingKey:NSNumber(value:true)]
        asset = AVURLAsset(url:url, options:inputOptions)
        
        return asset
    }
    
    private func audioDecodingSettings() -> [String: Any] {
        return [AVFormatIDKey:kAudioFormatLinearPCM]
    }
    
    private func audioEncodingSettings() -> [String: Any] {
        var acl = AudioChannelLayout()
        memset(&acl, 0, MemoryLayout<AudioChannelLayout>.size)
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        let audioEncodingSettings: [String:Any]  = [
            AVFormatIDKey:kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey:2,
            AVSampleRateKey:AVAudioSession.sharedInstance().sampleRate,
            AVChannelLayoutKey:NSData(bytes:&acl, length:MemoryLayout<AudioChannelLayout>.size),
            AVEncoderBitRateKey:96000
        ]
        
        return audioEncodingSettings
    }
    
    private func videoTrackFromAsset() -> AVAssetTrack? {
        return asset.tracks(withMediaType:AVMediaType.video).first
    }
    
    private func audioTrackFromAsset() -> AVAssetTrack? {
        return asset.tracks(withMediaType:AVMediaType.audio).first
    }
    
    private func videoSettingFor(_ videoTrack: AVAssetTrack) -> [String:Any]  {
        let videoSetting: [String:Any] = [
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey:videoTrack.nominalFrameRate,
                AVVideoAverageBitRateKey:videoTrack.estimatedDataRate,
                AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey:AVVideoH264EntropyModeCABAC,
                AVVideoAllowFrameReorderingKey:videoTrack.requiresFrameReordering],
            AVVideoCodecKey:AVVideoCodecType.h264
        ]
        
        return videoSetting
    }
    
    private func setupVideoEditTrimInfo(_ movieInput: MovieInput, _ trimInfo: VideoEditingTrimmingInfo) {
        movieInput.isTrimming = trimInfo.isTrimming
        movieInput.trimStartTime = CMTime(seconds: trimInfo.startTime, preferredTimescale: kPreferredTimescale)
        movieInput.trimDuration = CMTime(seconds: trimInfo.duration, preferredTimescale: kPreferredTimescale)
        
    }
    
    private func orientationForTrack(_ track: AVAssetTrack) -> ImageOrientation {
        let size = track.naturalSize
        let transform = track.preferredTransform
        
        if (size.width == transform.tx && size.height == transform.ty) {
            return .landscapeRight
        } else if (transform.tx == 0 && transform.ty == 0) {
            return .landscapeLeft
        } else if (transform.tx == 0 && transform.ty == size.width) {
            return .portraitUpsideDown
        } else {
            return .portrait
        }
    }
}

// Movie filter affect live view
extension VideoEditorModel: VideoEditorModelProtocol {
    func startVideoWithCallBack(_ atTime: Double = 0.0, _ callBack: ((VideoTimingInfo) -> Void)?) {
        if (atTime >= CMTimeGetSeconds(asset.duration)) {
            print("Time > duration")
            return
        }
        
        if let speaker = self.speaker, let movieInput = self.movieInput {
            speaker.start()            
            movieInput.start()
            movieInput.progress = { current, duration in
                let videoInfo = VideoTimingInfo(duration: duration, currentTime: current, percent: current/duration, finished: false)
                callBack?(videoInfo)
            }
            
            movieInput.completion = { duration in
                let videoInfo = VideoTimingInfo(duration: duration, currentTime: duration, percent: duration/duration, finished: true)
                callBack?(videoInfo)
            }
        } else {
            print("Video can't start")
        }
    }
    
    func trimVideoWith(_ start: Double, _ duration: Double) {
        guard let movieInput = movieInput else {
            print("trimVideoWith error")
            return
        }
        
        movieInput.cancel()
        
        let trimInfo = VideoEditingTrimmingInfo(isTrimming: true, startTime: start, duration: duration)
        let newSetting =
            VideoEditingSetting(loopVideo: videoEdittingSetting.loopVideo,
                                trimInfo: trimInfo,
                                numberOfThumbnail: videoEdittingSetting.numberOfThumbnail,
                                continueFilterWhenFinished: videoEdittingSetting.continueFilterWhenFinished)
        self.videoEdittingSetting = newSetting
        setupVideoEditTrimInfo(movieInput, trimInfo)
        
        movieInput.start()
    }
    
    func listThumnailImages(_ success: @escaping ([UIImage]) -> Void, _ failed: @escaping (String) -> Void) {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.appliesPreferredTrackTransform = true
        
        var startTime = 0.0
        var duration = Double(CMTimeGetSeconds(asset.duration))
        
        if let videoTrimSetting = videoEdittingSetting.trimInfo, videoTrimSetting.isTrimming == true {
            startTime = videoTrimSetting.startTime
            duration = videoTrimSetting.duration
        }
        
        let avgDuration = duration / Double(videoEdittingSetting.numberOfThumbnail)
        
        var listSec = [CMTime]()
        
        for _ in 0..<videoEdittingSetting.numberOfThumbnail {
            listSec.append(CMTime(seconds: startTime, preferredTimescale: kPreferredTimescale))
            startTime = startTime + avgDuration
        }
        
        let listSecInNSValue = listSec.map {
            NSValue(time: $0)
        }
        
        var listImages = [UIImage]()
        var completedCount = 0
        imageGenerator.generateCGImagesAsynchronously(forTimes: listSecInNSValue) { (requestedTime, cgImage, actualTime, result, error) in
            completedCount += 1
            if result == .succeeded, let cgImage = cgImage {
                let image = UIImage(cgImage: cgImage)
                listImages.append(image)
            }
            
            if completedCount == listSecInNSValue.count {
                success(listImages)
            }
        }
    }
    
    func setListFilters(_ listFilterKeys: [VideoFilterOperationType]) {
        
    }
    
    func settingVideoEditting(_ setting: VideoEditingSetting) {
        videoEdittingSetting = setting
    }
    
    func setupRenderView(with renderView: RenderView) {
        self.renderView = renderView
    }
    
    func setupVideoEdittingEngine(_ success: @escaping () -> Void, _ failed: @escaping (String) -> Void) {
        do {
            guard let renderView = renderView else {
                failed("Render view not set up yet")
                return
            }
            
            calculateSizeAndOrientation()
            
            movieInput = try MovieInput(asset: asset, videoComposition: nil, playAtActualSpeed: true, loop: videoEdittingSetting.loopVideo, audioSettings: audioDecodingSettings())
            guard let movieInput = movieInput else {
                failed("Init Movie input failed")
                return
            }

            if let trimInfo = videoEdittingSetting.trimInfo, trimInfo.isTrimming == true {
                setupVideoEditTrimInfo(movieInput, trimInfo)
            }
            
            movieInput.continueFilterAfterFinishedReadingAsset = videoEdittingSetting.continueFilterWhenFinished
            movieInput.movieOrientation = videoOrientation
            
            setUpFiltersForVideo(movieInput, renderView)
            speaker = SpeakerOutput()
            movieInput.audioEncodingTarget = speaker
            success()
        } catch (let error) {
            failed(error.localizedDescription)
        }
    }
    
    private func calculateSizeAndOrientation() {
        let videoTrack = asset.tracks(withMediaType: .video).first!
        let size = videoTrack.naturalSize
        let orientation = orientationForTrack(videoTrack)
        
        // AVAssetTrack always return size with width > height
        if (size.width > size.height) {
            if (orientation == .portrait) {
                videoOrientation = .landscapeRight
            } else if (orientation == .portraitUpsideDown) {
                videoOrientation = .landscapeLeft
            } else if (orientation == .landscapeLeft) {
                videoOrientation = .portrait
            } else {
                videoOrientation = .portraitUpsideDown
            }
        }
        else {
            // Test with movie from camera
        }
        
        if (orientation == .portrait || orientation == .portraitUpsideDown) {
            videoSize = Size(width: Float(size.height), height: Float(size.width))
        } else {
            videoSize = Size(width: Float(size.width), height: Float(size.height))
        }
        
        // If video size more than HD, then resize
//        if videoSize.width > 1280 {
//            videoSize = Size(width: 1280.0, height: 720.0)
//        }
    }
    
    func seekToTime(_ atTime: Double) {
        movieInput?.seekToTime(CMTime(seconds: atTime, preferredTimescale: kPreferredTimescale))
    }
    
    func startVideo(_ atTime: Double = 0.0) {
        if (atTime >= CMTimeGetSeconds(asset.duration)) {
            print("Time > duration")
            return
        }
        
        if let speaker = self.speaker, let movieInput = self.movieInput {
            speaker.start()
            movieInput.start(atTime: CMTime(seconds: atTime, preferredTimescale: kPreferredTimescale))
        } else {
            print("Video can't start")
        }
    }
    
    func pauseVideo() {
        movieInput?.pause()
    }
    
    func continueVideo() {
        movieInput?.start()
    }
    
    func stopVideo() {
        movieInput?.cancel()
    }
    
    func setUpFiltersForVideo(_ movieInput: MovieInput, _ movieOutput: RenderView) {
        movieOperationGroup.configureGroup { input, output in
            input   --> flipFilter.outFilter
                    --> rotateFilter.outFilter
                    --> rgbFilter.outFilter
                    --> contrastFilter.outFilter
                    --> brightnessFilter.outFilter
                    --> saturationFilter.outFilter
                            --> output
            
            print(brightnessFilter.outFilter.brightness)
        }
            
        movieInput --> movieOperationGroup --> movieOutput
    }
    
    func listVideoFilterOperations() -> Array<VideoFilterOperationInterface> {
        return [flipFilter, rotateFilter, rgbFilter, contrastFilter, brightnessFilter, saturationFilter]
    }
    
    func videoFilterForType(_ type: VideoFilterOperationType) -> VideoFilterOperationInterface? {
        switch type {
        case .flip:
            return flipFilter
        case .rotate:
            return rotateFilter
        case .rgb:
            return rgbFilter
        case .brightness:
            return brightnessFilter
        case .constrast:
            return contrastFilter
        case .saturation:
            return saturationFilter
        }
    }
}

// Movie filter affect export
extension VideoEditorModel {
    private func cancelMoviePlayer() {
        movieInput?.removeAllTargets()
        
        movieInput?.completion = nil
        movieInput?.cancel()
        
        movieInput = nil
        speaker?.cancel()
        speaker = nil
    }
    
    private func createMovieInputForExport() -> MovieInput? {
        do {
            movieInput = try MovieInput(asset: asset, videoComposition: nil, playAtActualSpeed: false, loop: false, audioSettings: audioDecodingSettings())
            return movieInput
        } catch {
            return nil
        }
    }
    
    private func createMovieOutputForExport(_ path: URL) -> MovieOutput? {
        guard let videoTrack = videoTrackFromAsset() else {
            return nil
        }
        
        do {
            
            let videoTrack = asset.tracks(withMediaType: .video).first!
            
            let orientation = orientationForTrack(videoTrack)
            
            movieOutput = try MovieOutput(URL: path,
                                          size: Size(width: Float(videoTrack.naturalSize.width), height: Float(videoTrack.naturalSize.height)),
                                          fileType: .mp4,
                                          liveVideo: false,
                                          videoSettings: videoSettingFor(videoTrack),
                                          videoNaturalTimeScale: videoTrack.naturalTimeScale,
                                          audioSettings: audioEncodingSettings())
            return movieOutput
        } catch {
            return nil
        }
    }
    
    func exportVideoToPath(_ path: URL, _ completed: @escaping (Double, Bool) -> Void, _ failed: (String) -> Void) {
        try? FileManager().removeItem(at: path)
        cancelMoviePlayer()
        
        guard let movieInput = createMovieInputForExport() else {
            failed("Movie Input nil")
            return
        }
        
        let videoTrack = asset.tracks(withMediaType: .video).first!
        
        let orientation = orientationForTrack(videoTrack)
        
        if let trimInfo = videoEdittingSetting.trimInfo, trimInfo.isTrimming == true {
            setupVideoEditTrimInfo(movieInput, trimInfo)
        }
                
//        movieInput.movieOrientation = videoOrientation
        
        guard let movieOutput = createMovieOutputForExport(path) else {
            failed("Movie output failed")
            return
        }
        
//        movieOutput.videoOrientation = videoOrientation
            
        if(audioTrackFromAsset() != nil) {
            movieInput.audioEncodingTarget = movieOutput
        }
        
        movieOperationGroup.removeAllTargets()
        movieInput --> movieOperationGroup --> movieOutput
        movieInput.synchronizedEncodingDebug = true
        movieInput.synchronizedMovieOutput = movieOutput
        movieInput.completion = { [weak self] (duration) in
            guard let movieOutput_ = self?.movieOutput else {
                print("Movie output when movie input completed failed")
                return
            }
            
            movieOutput_.finishRecording { [weak self] in
                guard let movieInput_ = self?.movieInput else {
                    print("Movie input when movie input completed failed")
                    return
                }
                
                movieInput_.audioEncodingTarget = nil
                movieInput_.synchronizedMovieOutput = nil
                
                completed(duration/duration, true)
            }
        }
        
        movieInput.progress = { current, duration in
            completed(current/duration, false)
        }
        
        movieOutput.startRecording { [weak self] (started, error) in
            if(!started) {
                print("ERROR: MovieOutput unable to start writing with error: \(String(describing: error))")
                return
            }
            guard let movieInput_ = self?.movieInput else {
                print("Movie input when movie input completed failed")
                return
            }
            movieInput_.start()
            print("Encoding started")
        }
    }
}
