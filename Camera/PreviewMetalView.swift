import UIKit
import MetalKit
import CoreImage

class PreviewMetalView: MTKView {
    
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private lazy var commandQueue: MTLCommandQueue? = {
        return self.device?.makeCommandQueue()
    }()
    private lazy var ciContext: CIContext? = {
        guard let device = self.device else { return nil }
        return CIContext(mtlDevice: device, options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    }()
    
    var image: CIImage? {
        didSet {
            setNeedsDisplay()
        }
    }
    
    init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: device)
        
        self.framebufferOnly = false
        self.enableSetNeedsDisplay = true
        self.preferredFramesPerSecond = 60
        self.isOpaque = true
        self.contentMode = .scaleAspectFill
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        // Log frame draw attempt (throttled to avoid spam, e.g., print every 60th frame normally, but here we'll print selectively to debug)
        
        guard let image = self.image else {
            // print("PreviewMetalView: No image to draw")
            return
        }
        
        guard let currentDrawable = self.currentDrawable else {
            print("PreviewMetalView: Failed to get currentDrawable. This causes flickering.")
            return
        }
        
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            print("PreviewMetalView: Failed to make command buffer.")
            return
        }
        
        guard let ciContext = self.ciContext else {
            return
        }
        
        // Calculate the scale to fill the view bounds while maintaining aspect ratio
        let drawRect = CGRect(origin: .zero, size: drawableSize)
        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scale = max(scaleX, scaleY)
        
        // Translate and scale to draw centered
        let tx = (drawableSize.width - image.extent.width * scale) / 2.0
        let ty = (drawableSize.height - image.extent.height * scale) / 2.0
        let transform = CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
        let transformedImage = image.transformed(by: transform).cropped(to: drawRect)
        
        // Clear background to black before rendering to prevent garbage/flicker
        let renderDestination = CIRenderDestination(width: Int(drawableSize.width),
                                                    height: Int(drawableSize.height),
                                                    pixelFormat: self.colorPixelFormat,
                                                    commandBuffer: commandBuffer,
                                                    mtlTextureProvider: { () -> MTLTexture in
            return currentDrawable.texture
        })
        
        do {
            try ciContext.startTask(toRender: transformedImage, to: renderDestination)
        } catch {
            print("PreviewMetalView: CoreImage render task failed - \(error.localizedDescription)")
        }
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
