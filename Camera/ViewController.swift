import UIKit
import CoreMedia
import Combine
import Photos
import Vision

class ViewController: UIViewController {
    
    // Core Modules
    let cameraManager = CameraManager.shared
    let imageProcessor = ImageProcessor.shared
    
    // UI Elements
    var previewView: PreviewMetalView!
    var meteringBoxView: UIView!
    var modeSegmentedControl: UISegmentedControl!
    var confirmButton: UIButton!
    var shutterButton: UIButton!
    
    // State
    private var isCapturing = false
    private lazy var context = CIContext(options: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupUI()
        
        cameraManager.delegate = self
        cameraManager.setupCamera()
    }
    
    private func setupUI() {
        // Preview View
        previewView = PreviewMetalView(frame: .zero)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // Metering Box (Center)
        meteringBoxView = UIView()
        meteringBoxView.translatesAutoresizingMaskIntoConstraints = false
        meteringBoxView.layer.borderColor = UIColor.yellow.withAlphaComponent(0.8).cgColor
        meteringBoxView.layer.borderWidth = 2
        meteringBoxView.backgroundColor = .clear
        view.addSubview(meteringBoxView)
        
        // Mode Segmented Control
        modeSegmentedControl = UISegmentedControl(items: ["拍月亮", "拍星星"])
        modeSegmentedControl.selectedSegmentIndex = 0
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        modeSegmentedControl.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        modeSegmentedControl.selectedSegmentTintColor = .white
        modeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(modeSegmentedControl)
        
        // Confirm Position Button
        confirmButton = UIButton(type: .system)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.setTitle("月亮已放入框中", for: .normal)
        confirmButton.setTitleColor(.black, for: .normal)
        confirmButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        confirmButton.backgroundColor = .white
        confirmButton.layer.cornerRadius = 25
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        view.addSubview(confirmButton)
        
        // Shutter Button
        shutterButton = UIButton(type: .custom)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.layer.cornerRadius = 35
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.backgroundColor = .white
        shutterButton.alpha = 0.5 // Initially disabled look
        shutterButton.isUserInteractionEnabled = false // Initially disabled
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutterButton)
        
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            modeSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            modeSegmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeSegmentedControl.widthAnchor.constraint(equalToConstant: 200),
            modeSegmentedControl.heightAnchor.constraint(equalToConstant: 32),
            
            meteringBoxView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            meteringBoxView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            meteringBoxView.widthAnchor.constraint(equalToConstant: 150),
            meteringBoxView.heightAnchor.constraint(equalToConstant: 150),
            
            // Buttons Layout (Side by side at the bottom)
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            confirmButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            confirmButton.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -20),
            confirmButton.heightAnchor.constraint(equalToConstant: 50),
            
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            shutterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70)
        ])
    }
    
    @objc private func modeChanged() {
        // Reset camera state allowing user to find the new subjects
        cameraManager.resetToAutoParameters()
        
        // Update UI back to finding state
        let modeText = modeSegmentedControl.selectedSegmentIndex == 0 ? "月亮已放入框中" : "星星已放入框中"
        confirmButton.setTitle(modeText, for: .normal)
        confirmButton.alpha = 1.0
        confirmButton.isUserInteractionEnabled = true
        
        shutterButton.alpha = 0.5
        shutterButton.isUserInteractionEnabled = false
        
        UIView.animate(withDuration: 0.3) {
            self.meteringBoxView.alpha = 1.0
        }
    }
    
    @objc private func confirmTapped() {
        // Lock camera parameters based on selected mode
        let mode: CameraMode = modeSegmentedControl.selectedSegmentIndex == 0 ? .moon : .stars
        cameraManager.lockParameters(for: mode)
        
        // Update UI
        confirmButton.setTitle("已锁定参数", for: .normal)
        confirmButton.alpha = 0.5
        confirmButton.isUserInteractionEnabled = false
        
        // Enable shutter button
        shutterButton.alpha = 1.0
        shutterButton.isUserInteractionEnabled = true
        
        // Optional: Hide the metering box since position is confirmed
        UIView.animate(withDuration: 0.3) {
            self.meteringBoxView.alpha = 0
        }
    }
    
    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        
        isCapturing = true
        shutterButton.backgroundColor = .red
        
        cameraManager.capturePhoto(delegate: self)
    }
}

extension ViewController: CameraManagerDelegate {
    func didOutput(sampleBuffer: CMSampleBuffer) {
        guard !isCapturing else { return } // Pause preview update during capture
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Enhance for view finder
        let enhancedImage = imageProcessor.enhanceStars(image: ciImage)
        
        DispatchQueue.main.async {
            self.previewView.image = enhancedImage
        }
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            resetCaptureState()
            return
        }
        
        guard let cgImage = photo.cgImageRepresentation() else {
            resetCaptureState()
            return
        }
        
        let rawCI = CIImage(cgImage: cgImage)
        
        DispatchQueue.main.async {
            self.previewView.image = rawCI
        }
        
        saveToPhotos(image: rawCI)
    }
    
    private func saveToPhotos(image: CIImage) {
        // Render CIImage to UIImage
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            resetCaptureState()
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                self.resetCaptureState()
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }) { _, _ in
                DispatchQueue.main.async {
                    self.resetCaptureState()
                }
            }
        }
    }
    
    private func resetCaptureState() {
        DispatchQueue.main.async {
            self.isCapturing = false
            self.shutterButton.backgroundColor = .white
            
            // Re-enable confirm button to allow re-framing if needed
            let modeText = self.modeSegmentedControl.selectedSegmentIndex == 0 ? "月亮已放入框中" : "星星已放入框中"
            self.confirmButton.setTitle(modeText, for: .normal)
            self.confirmButton.alpha = 1.0
            self.confirmButton.isUserInteractionEnabled = true
            
            // Gray out shutter button again
            self.shutterButton.alpha = 0.5
            self.shutterButton.isUserInteractionEnabled = false
            
            // Show metering box
            UIView.animate(withDuration: 0.3) {
                self.meteringBoxView.alpha = 1.0
            }
            
            // Restore camera to auto parameters for finding the next moon
            self.cameraManager.resetToAutoParameters()
        }
    }
}


