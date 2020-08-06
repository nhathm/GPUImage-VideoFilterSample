//
//  VideoFilterViewController.swift
//  RTSP Player
//
//  Created by NhatHM on 9/3/19.
//  Copyright © 2019 NextMove. All rights reserved.
//

import UIKit
import GPUImage
import Photos

class VideoFilterViewController: UIViewController {
    @IBOutlet private weak var renderView: RenderView!
    @IBOutlet weak var listFiltersTableView: UITableView!
    @IBOutlet weak var filterSlide: UISlider!
    @IBOutlet weak var rgbTypeSegment: UISegmentedControl!    
    @IBOutlet weak var thumnailImagesHolder: UIScrollView!
        
    private var fileURL: URL!
    
    private var movieOutput:MovieOutput? = nil
    private var videoFilterModel = VideoEditorModel(videoUrl: nil, renderView: nil)
    private var currentFilter: VideoFilterOperationInterface?
    private let operationGroup = OperationGroup()
    
    private var currentIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        registCustomCells(listFiltersTableView)
        setupCommonTableViewSetting(listFiltersTableView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportVideo))

    }
    
    deinit {
        currentFilter = nil
    }
    
    private func registCustomCells(_ tableView: UITableView) {
        tableView.register(UINib(nibName: "MainTableViewCell", bundle: nil), forCellReuseIdentifier: "MainTableViewCell")
    }
    
    private func setupCommonTableViewSetting(_ tableView: UITableView) {
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 140
        
        tableView.separatorStyle = .none
        tableView.separatorColor = .clear
        tableView.tableFooterView = UIView(frame: .zero)
    }
}

// IBAction
extension VideoFilterViewController {
    @IBAction func rgbSegmentChanged(_ sender: UISegmentedControl, forEvent event: UIEvent) {
        print("Selected index = \(sender.selectedSegmentIndex)")
        switch sender.selectedSegmentIndex {
        case 0:
            currentFilter?.updateFilterType(.red)
        case 1:
            currentFilter?.updateFilterType(.green)
        case 2:
            currentFilter?.updateFilterType(.blue)
        default:
            break
        }
        
        if let slideConfig = currentFilter?.filterSlideConfig {
            switch slideConfig {
            case .disabled:
                break
            case let .enabled(minValue, maxValue, initValue, _):
                print(currentFilter?.slideValue() ?? "-1")
                filterSlide.minimumValue = minValue
                filterSlide.maximumValue = maxValue
                filterSlide.value = currentFilter?.slideValue() ?? initValue
            }
        }
    }
    
    @IBAction func changeFilterValue(_ sender: UISlider, forEvent event: UIEvent) {
        currentFilter?.updateFilterWhenSlideValueChanged(sender.value)
    }
    
    @IBAction func invokeButtonSelectVideo(_ sender: UIButton, forEvent event: UIEvent) {
        let bundleURL = Bundle.main.resourceURL!
        let movieURL = URL(string: "maldives.mp4", relativeTo:bundleURL)
        
        guard let url = movieURL else {
            print("path not valid")
            return
        }
        videoFilterModel = VideoEditorModel(videoUrl: url, renderView: renderView)
        
        let videoTrimmingInfo = VideoEditingTrimmingInfo(isTrimming: false, startTime: 0, duration: 0)
        let videoEdittingConfig = VideoEditingSetting(
                                                      loopVideo: true,
                                                      trimInfo: videoTrimmingInfo,
                                                      numberOfThumbnail: 10,
                                                      continueFilterWhenFinished: true)
        
        videoFilterModel.settingVideoEditting(videoEdittingConfig)
        videoFilterModel.setupVideoEdittingEngine({ [weak self] in
            self?.getListThumbnailImages()
        }) { (error) in
            print(error)
        }
    }
    
    private func getListThumbnailImages() {
        videoFilterModel.listThumnailImages({ [weak self] (listImages) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let imageViewHeight = self.thumnailImagesHolder.frame.height 
                var startX = 0
                for image in listImages {
                    let imageView = UIImageView(frame: CGRect(x: CGFloat(startX), y: 0, width: imageViewHeight, height: imageViewHeight))
                    imageView.image = image
                    self.thumnailImagesHolder.addSubview(imageView)
                    startX = startX + Int(imageViewHeight)
                }
                
                self.thumnailImagesHolder.isScrollEnabled = true
                self.thumnailImagesHolder.contentSize = CGSize(width: CGFloat(startX), height: imageViewHeight)
                
                self.startVideo()
            }
        }) { (error) in
            print(error)
        }
    }
    
    private func startVideo() {
        videoFilterModel.startVideoWithCallBack { (timingInfo) in
//            print("Duration = \(timingInfo.duration)")
//            print("Current = \(timingInfo.currentTime)")
//            print("Percent = \(timingInfo.percent)")
//            print("End = \(timingInfo.finished)")
        }
    }
    
    @IBAction func invokeStartRecordButton(_ sender: UIButton, forEvent event: UIEvent) {
        pauseVideo()
    }
    
    @IBAction func invokeStopRecordButton(_ sender: UIButton, forEvent event: UIEvent) {
        continueVideo()
    }
}

extension VideoFilterViewController {
    func checkPermission() {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        switch photoAuthorizationStatus {
        case .authorized: print("Access is granted by user")
        case .notDetermined: PHPhotoLibrary.requestAuthorization({
            (newStatus) in print("status is \(newStatus)")
            if newStatus == PHAuthorizationStatus.authorized { /* do stuff here */ print("success") }
            })
        case .restricted: // print("User do not have access to photo album.")
            print("restricted")
        case .denied: // print("User has denied the permission.")
            print("denied")
        @unknown default:
            fatalError()
        }
    }
}

extension VideoFilterViewController {
    @objc private func exportVideo() {
        let documentsDir = FileManager().urls(for:.documentDirectory, in:.userDomainMask).first!
        let path = URL(fileURLWithPath: "export.mp4", relativeTo: documentsDir)
        
        videoFilterModel.exportVideoToPath(path, { [unowned self]  (progress, done) in
            if done {
                DispatchQueue.main.async {
                    PHPhotoLibrary.shared().performChanges({                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: path)
                    }) { saved, error in
                        DispatchQueue.main.async {
                        if saved {
                            
                            let alertController = UIAlertController(title: "Your video was successfully saved", message: nil, preferredStyle: .alert)
                            let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                            alertController.addAction(defaultAction)
                            self.present(alertController, animated: true, completion: nil)
                        } else {
                            print(error ?? "Unknow error")
                            let alertController = UIAlertController(title: "Your video was successfully FAILED", message: error?.localizedDescription, preferredStyle: .alert)
                            let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                            alertController.addAction(defaultAction)
                            DispatchQueue.main.async {
                                self.present(alertController, animated: true, completion: nil)
                            }
                        }
                        }
                    }
                }
            }
        }) { (error) in
            print(error)
        }
    }
    
    private func pauseVideo() {
        videoFilterModel.pauseVideo()
    }
    
    private func continueVideo() {
        videoFilterModel.continueVideo()
    }
}

extension VideoFilterViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            let filter = videoFilterModel.videoFilterForType(.flip)
            currentFilter = filter
        case 1:
            let filter = videoFilterModel.videoFilterForType(.rotate)
            currentFilter = filter
        case 2:
            let filter = videoFilterModel.videoFilterForType(.rgb)
            currentFilter = filter
        case 3:
            let filter = videoFilterModel.videoFilterForType(.brightness)
            currentFilter = filter
        case 4:
            let filter = videoFilterModel.videoFilterForType(.constrast)
            currentFilter = filter
        case 5:
            let filter = videoFilterModel.videoFilterForType(.saturation)
            currentFilter = filter
        default:
            print("")
        }
        
        if let slideConfig = currentFilter?.filterSlideConfig {
            switch slideConfig {
            case .disabled:
                break
            case let .enabled(minValue, maxValue, initValue, _):
                print(currentFilter?.slideValue() ?? 0)
                filterSlide.minimumValue = minValue
                filterSlide.maximumValue = maxValue
                filterSlide.value = currentFilter?.slideValue() ?? initValue
            }
        }
    }
}

extension VideoFilterViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videoFilterModel.listVideoFilterOperations().count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MainTableViewCell", for: indexPath) as? MainTableViewCell else {
            return UITableViewCell()
        }
        
        let listVideoFilter = videoFilterModel.listVideoFilterOperations()
        let videoFilter = listVideoFilter[indexPath.row]
        
        cell.textLabel?.text = videoFilter.filterName
        
        return cell
    }
}
