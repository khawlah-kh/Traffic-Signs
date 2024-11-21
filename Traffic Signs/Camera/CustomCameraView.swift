//
//  CustomCameraView.swift
//  Hydro
//
//  Created by Khawlah Khalid on 16/07/2024.
//

import Foundation
import UIKit
import SwiftUI
import AVFoundation

struct CustomCameraView: UIViewControllerRepresentable {
    @ObservedObject var cameraController: CustomCameraController
    
    func makeUIViewController(context: Context) -> CustomCameraController {
        cameraController
    }
    
    func updateUIViewController(_ uiViewController: CustomCameraController, context: Context) {
        // No update necessary
    }
}
import Vision
class CustomCameraController: UIViewController, ObservableObject,
                              AVCaptureMetadataOutputObjectsDelegate,AVCaptureVideoDataOutputSampleBufferDelegate{
    
    private var captureSession =  AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    //Face Detection
    var captureDeviceResolution: CGSize = CGSize()
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    // Layer UI for drawing Vision results
    var detectionOverlayLayer: CALayer?

//All new
    private var requests = [VNRequest]()
    private var detectionOverlay: CALayer! = nil
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    @Published var className: String = ""

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        requestCameraPermission()
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // For simple asset classification
    let model: Traffic_Signs =  Traffic_Signs()

    
    //Not used
    func detectAndClassifySign(from image: CIImage) -> String? {
        guard let model = try? VNCoreMLModel(for: model.model) else {
            return nil
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let topResult = results.first else {
                return
            }
            
            DispatchQueue.main.async {
                let className = topResult.featureValue.stringValue ?? "Unknown"
                print("Detected sign: \(className)")
            }
        }
        
        if let buffer = image.pixelBuffer{
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer)
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("Error: \(error)")
                }
            }
        }
            return nil
        }
    
    
    //MARK: Setup
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    self.setupCamera()
                }
            }
        }
    }
    
    private func setupCamera() {
        //Create Session
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        captureDevice = device
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession = AVCaptureSession()
            captureSession.addInput(input)
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer?.frame = view.bounds
            //Video output data
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VisionFaceTrack")
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            if captureSession.canAddOutput(videoDataOutput) {
                captureSession.addOutput(videoDataOutput)
            }
            videoDataOutput.connection(with: .video)?.isEnabled = true
            if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
                if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                    captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
            }
            self.videoDataOutput = videoDataOutput
            self.videoDataOutputQueue = videoDataOutputQueue
            
            self.captureDevice = device
            if let highestResolution = self.highestResolution420Format(for: device) {
                self.captureDeviceResolution = highestResolution.resolution
                let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                bufferSize.width = CGFloat(dimensions.width)
                bufferSize.height = CGFloat(dimensions.height)
            }
            
            
            self.rootLayer = view.layer
            view.layer.addSublayer(videoPreviewLayer!)
            setupLayers()
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
            print("Error setting up camera: \(error.localizedDescription)")
            self.teardownAVCapture()
        }
        //Setup vision
        setupVision()
        updateLayerGeometry()
        //run session
        DispatchQueue.global(qos: .default).async {
            self.captureSession.startRunning()
            
        }
    }
    
    func setupLayers() {
        detectionOverlay = CALayer()
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    // MARK: AVCapture Setup
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "ViewController", code: 1, userInfo: nil)
    }
    
    // Removes infrastructure for AVCapture as part of cleanup.
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
        
        if let previewLayer = self.videoPreviewLayer {
            videoPreviewLayer?.removeFromSuperlayer()
            self.videoPreviewLayer = nil
        }
    }
    
    // MARK: Helper Methods for Handling Device Orientation & EXIF
    fileprivate func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    func updateLayerGeometry() {
    let bounds = rootLayer.bounds
    var scale: CGFloat
    
    let xScale: CGFloat = bounds.size.width / bufferSize.height
    let yScale: CGFloat = bounds.size.height / bufferSize.width
    
    scale = fmax(xScale, yScale)
    if scale.isInfinite {
        scale = 1.0
    }
    CATransaction.begin()
    CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
    
    // rotate the layer into screen orientation and scale and mirror
    detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
    // center the layer
    detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
    
    CATransaction.commit()
    
}

    
    // MARK: Performing Vision Requests
    func setupVision() {
//        guard let modelURL = Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc") else {  return }

        guard let modelURL = Bundle.main.url(forResource: "Traffic_Signs_v2", withExtension: "mlmodelc") else {  return }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.detectClass(results)
                    }
                })
            })
            
            self.requests = [objectRecognition]
            
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
    }

    func detectClass(_ results: [Any]) {
    guard let results = results as? [VNClassificationObservation] else {
        return
    }
    
    if let firstResult = results.first {
        self.className = firstResult.identifier
        //self.className = TrafficSignManager.idNameDic[firstResult.identifier, default: "na"]
        print("hi model \(firstResult.identifier) 🩵")
        print("hi model \(firstResult.confidence)")
    }
        
    
}

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("👋🏻")
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }

 }


