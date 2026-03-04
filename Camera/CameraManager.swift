import Foundation
import AVFoundation

enum CameraMode {
    case moon
    case stars
}

protocol CameraManagerDelegate: AnyObject {
    func didOutput(sampleBuffer: CMSampleBuffer)
}

class CameraManager: NSObject {
    static let shared = CameraManager()
    
    let captureSession = AVCaptureSession()
    weak var delegate: CameraManagerDelegate?
    
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    
    private let sessionQueue = DispatchQueue(label: "com.camera.sessionQueue")
    
    override init() {
        super.init()
    }
    
    func setupCamera() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            
            // 1. Select device and set a manageable session preset
            self.captureSession.sessionPreset = .hd1920x1080 // Or .hd1280x720 if 1080p is still too heavy for realtime CIImage filtering
            
            // Try to find a telephoto camera first, otherwise fallback to wide angle
            var device: AVCaptureDevice?
            if let telephoto = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
                device = telephoto
            } else if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                device = dualCamera
            } else if let wideAngle = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                device = wideAngle
            }
            
            guard let selectedDevice = device else {
                print("Error: No suitable back camera found.")
                self.captureSession.commitConfiguration()
                return
            }
            self.videoDevice = selectedDevice
            
            // 2. Add input
            do {
                let input = try AVCaptureDeviceInput(device: selectedDevice)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                }
                
                // Set initial zoom if it's a wide angle to help frame the moon
                try selectedDevice.lockForConfiguration()
                if selectedDevice.deviceType == .builtInWideAngleCamera {
                     // Zoom in a bit if we only have wide angle
                     selectedDevice.videoZoomFactor = min(3.0, selectedDevice.activeFormat.videoMaxZoomFactor)
                } else if selectedDevice.deviceType == .builtInDualCamera {
                     selectedDevice.videoZoomFactor = 2.0
                }
                
                // Allow continuous auto exposure and focus initially so the user can easily find the moon
                if selectedDevice.isFocusModeSupported(.continuousAutoFocus) {
                    selectedDevice.focusMode = .continuousAutoFocus
                }
                if selectedDevice.isExposureModeSupported(.continuousAutoExposure) {
                    selectedDevice.exposureMode = .continuousAutoExposure
                }
                selectedDevice.unlockForConfiguration()
            } catch {
                print("Error setting up input: \(error)")
                self.captureSession.commitConfiguration()
                return
            }
            
            // 3. Add video output
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            // Use a background queue for delivery to prevent blocking the session pipeline
            let videoOutputQueue = DispatchQueue(label: "com.camera.videoOutputQueue", qos: .userInteractive)
            self.videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            // Fix connection orientation (portrait)
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            // 4. Add photo output (Highest quality for the actual shot)
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
            }
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
            
            // We no longer lock parameters here; it's done when the user confirms the position
        }
    }
    
    func lockParameters(for mode: CameraMode) {
        guard let device = self.videoDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // 1. Lock focus to infinity for moon/stars
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
                device.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)
            }
            
            // 2. Lock white balance just in case
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            
            if mode == .moon {
                // 3. Set exposure for Moon (Low ISO, relatively fast shutter)
                let minISO = device.activeFormat.minISO
                let moonShutter = CMTimeMake(value: 1, timescale: 120) // 1/120 sec is a good starting point
                let duration = max(device.activeFormat.minExposureDuration, min(moonShutter, device.activeFormat.maxExposureDuration))
                
                self.setManualExposure(iso: minISO, duration: duration)
            } else {
                // 3. Set exposure for Stars (High ISO, slow shutter for preview)
                let maxISO = device.activeFormat.maxISO
                let previewSlowestShutter = CMTimeMake(value: 1, timescale: 15) // 1/15 sec for preview
                let duration = max(device.activeFormat.minExposureDuration, min(previewSlowestShutter, device.activeFormat.maxExposureDuration))
                
                self.setManualExposure(iso: maxISO, duration: duration)
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error locking device for configuration: \(error)")
        }
    }
    
    func setManualExposure(iso: Float, duration: CMTime) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let safeISO = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso))
            let safeDuration = max(device.activeFormat.minExposureDuration, min(device.activeFormat.maxExposureDuration, duration))
            
            device.setExposureModeCustom(duration: safeDuration, iso: safeISO, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set manual exposure.")
        }
    }
    
    func resetToAutoParameters() {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            print("Error resetting device to auto: \(error)")
        }
    }
    
    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.photoQualityPrioritization = .quality
        // Ensure high-resolution capture is requested if it was enabled on the output
        photoSettings.isHighResolutionPhotoEnabled = true 
        photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.didOutput(sampleBuffer: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("CameraManager: Dropped a video frame. The processing might be too slow.")
    }
}
