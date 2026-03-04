import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

class ImageProcessor {
    static let shared = ImageProcessor()
    
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    
    // Filters for star enhancement
    private let colorControlsFilter = CIFilter.colorControls()
    private let exposureFilter = CIFilter.exposureAdjust()
    private let highlightShadowFilter = CIFilter.highlightShadowAdjust()
    
    /// Enhances the bright spots (stars) in the image for real-time preview
    func enhanceStars(image: CIImage) -> CIImage {
        // Boost exposure slightly
        exposureFilter.inputImage = image
        exposureFilter.ev = 0.5
        var result = exposureFilter.outputImage ?? image
        
        // Boost contrast and brightness
        colorControlsFilter.inputImage = result
        colorControlsFilter.contrast = 1.1
        colorControlsFilter.brightness = 0.05
        result = colorControlsFilter.outputImage ?? result
        
        return result
    }
    
}
