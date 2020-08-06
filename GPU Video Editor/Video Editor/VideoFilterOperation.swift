//
//  VideoFilterOperation
//
//  Created by NhatHM on 9/5/19.
//  Copyright © 2019 NextMove. All rights reserved.
//

import Foundation
import GPUImage

struct VideoFilterSlideSettingValue {
    var minValue: Float
    var maxValue: Float
    var initValue: Float
}

enum RGBSlideType: String, CaseIterable {
    case none   = "none"
    case red    = "red"
    case green  = "green"
    case blue   = "blue"
}

enum VideoFilterSlideSetting {
    case disabled
    case enabled(minValue: Float, maxValue: Float, initValue: Float, currentValue: Float)
}

protocol VideoFilterOperationInterface {
    var filterName:         String { get }
    var videoFilter:        ImageProcessingOperation { get }
    var filterSlideConfig:  VideoFilterSlideSetting { get }
    
    func slideValue() -> Float
    func updateFilterType(_ type: RGBSlideType)
    func updateFilterWhenSlideValueChanged(_ slideValue: Float)
}

class VideoFilterOperation <FilterClass: ImageProcessingOperation>: VideoFilterOperationInterface {
    let filterName: String
    let internalFilter: FilterClass
    let filterSlideConfig: VideoFilterSlideSetting
    
    var currentSlideValue: Float
    var currentSlideValueDictionary: [String: Float]
    var currentRGBSlideType: RGBSlideType
    
    let slideUpdateCallback: ((FilterClass, Float) -> Void)?
    let slideUpdateWithTypeCallback: ((FilterClass, Float, RGBSlideType) -> Void)?
    
    init(filterName:    String,
         videoFilter:   FilterClass,
         slideConfig:   VideoFilterSlideSetting,
         currentSlideType: RGBSlideType,
         currentSlideValue: Float,
         slideUpdateCallback: ((FilterClass, Float) -> Void)? = nil,
         slideUpdateWithTypeCallback: ((FilterClass, Float, RGBSlideType) -> Void)? = nil) {
        self.filterName = filterName
        self.internalFilter = videoFilter
        self.filterSlideConfig = slideConfig
        self.currentRGBSlideType = currentSlideType
        self.currentSlideValue = currentSlideValue
        self.slideUpdateCallback = slideUpdateCallback
        self.slideUpdateWithTypeCallback = slideUpdateWithTypeCallback
        currentSlideValueDictionary = [:]
        currentSlideValueDictionary[RGBSlideType.none.rawValue] = currentSlideValue
        switch internalFilter.self {
        case let rgb as RGBAdjustment:
            currentSlideValueDictionary[RGBSlideType.red.rawValue] = currentSlideValue
            currentSlideValueDictionary[RGBSlideType.green.rawValue] = currentSlideValue
            currentSlideValueDictionary[RGBSlideType.blue.rawValue] = currentSlideValue
            switch currentRGBSlideType.self {
            case .red:
                rgb.red = currentSlideValue
            case .green:
                rgb.green = currentSlideValue
            case .blue:
                rgb.blue = currentSlideValue
            default:
                break
            }
        case let contrast as ContrastAdjustment:
            contrast.contrast = currentSlideValue
        case let brightness as BrightnessAdjustment:
            brightness.brightness = currentSlideValue
        case let saturation as SaturationAdjustment:
            saturation.saturation = currentSlideValue
        default:
            break
        }
    }
    
    var videoFilter: ImageProcessingOperation {
        return internalFilter
    }
    
    var outFilter: FilterClass {
        return internalFilter
    }
    
    func slideValue() -> Float {
        if let currentValue = currentSlideValueDictionary[currentRGBSlideType.rawValue] {
            return currentValue
        }
        
        return currentSlideValue
    }
    
    func updateFilterType(_ type: RGBSlideType) {
        if currentRGBSlideType != .none {
            currentRGBSlideType = type
            
        }
    }
    
    func updateFilterWhenSlideValueChanged(_ slideValue: Float) {
        currentSlideValue = slideValue
        currentSlideValueDictionary[currentRGBSlideType.rawValue] = slideValue
        slideUpdateCallback?(internalFilter, slideValue)
        slideUpdateWithTypeCallback?(internalFilter, slideValue, currentRGBSlideType)
    }
}
