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
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    
    private var captureSession =  AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureDevice: AVCaptureDevice?
    //Face Detection
    var captureDeviceResolution: CGSize = CGSize()
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    // Layer UI for drawing Vision results
//    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    
    // Vision requests
    private var trackingRequests: [VNTrackObjectRequest]?
//    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var detectionRequests =  [VNRequest]()

    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    //Capture photo
    @Published var capturedImage: UIImage?
    private var photoOutput: AVCapturePhotoOutput?
    @Published var shouldCapture: Bool = false
//All new
    private var requests = [VNRequest]()
    private var detectionOverlay: CALayer! = nil
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        requestCameraPermission()
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    //
    let model: Traffic_Signs =  Traffic_Signs()

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
 
    
    
    
    //
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
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
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
                //                try device.lockForConfiguration()
                //                device.activeFormat = highestResolution.format
                //                device.unlockForConfiguration()
                
                self.captureDeviceResolution = highestResolution.resolution
                
                
                //
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
        //self.prepareVisionRequest()
        //run session
        DispatchQueue.global(qos: .default).async {
            //                self.prepareVisionRequest()
            self.captureSession.startRunning()
            
        }
        
        // For taking photo
        
        // Add the photo output
        self.photoOutput = AVCapturePhotoOutput()
        if let photoOutput{
            if self.captureSession.canAddOutput(photoOutput) == true {
                self.captureSession.addOutput(photoOutput)
            }
        }
    }

    
    
    //MARK: Vision
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
    
    // MARK: AVCapture Setup
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
    
    // MARK: Helper Methods for Error Presentation
    
    fileprivate func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        self.present(alertController, animated: true)
    }
    
    fileprivate func presentError(_ error: NSError) {
        self.presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
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
    
    // MARK: Performing Vision Requests
    
    /// - Tag: WriteCompletionHandler
//    fileprivate func prepareVisionRequest() {
//        print("👋🏻👋🏻")
//        //self.trackingRequests = []
//        var requests = [VNTrackObjectRequest]()
//        
//        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
//            
//            if error != nil {
//                print("FaceDetection error: \(String(describing: error)).")
//            }
//            
//            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
//                let results = faceDetectionRequest.results as? [VNFaceObservation] else {
//                    return
//            }
//            DispatchQueue.main.async {
//                // Add the observations to the tracking list
//                for observation in results {
//                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
//                    requests.append(faceTrackingRequest)
//                }
//                self.trackingRequests = requests
//            }
//        })
//        
//        // Start with detection.  Find face, then track it.
//        self.detectionRequests = [faceDetectionRequest]
//        
//        self.sequenceRequestHandler = VNSequenceRequestHandler()
//        
//        self.setupVisionDrawingLayers()
//    }
//    fileprivate func prepareVisionRequest() {
//        print("👋🏻👋🏻")
//        var requests = [VNTrackObjectRequest]()
//        guard let modelURL = Bundle.main.url(forResource: "Traffic_Signs", withExtension: "mlmodelc") else {
//            print("Model file is missing")
//            return
//        }
//        print("Model has been created ♥️")
//        do {
//            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
//            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
////                DispatchQueue.main.async(execute: {
////                    // perform all the UI updates on the main queue
////                    if let results = request.results {
////                        self.drawVisionRequestResults(results)
////                    }
////                })
//                guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
//                    let results = faceDetectionRequest.results as? [VNFaceObservation] else {
//                        return
//                }
//                DispatchQueue.main.async {
//                    // Add the observations to the tracking list
//                    for observation in results {
//                        let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
//                        requests.append(faceTrackingRequest)
//                    }
//                    self.trackingRequests = requests
//                }
//                
//                
//                
//                
//                
//            })
////            self.requests = [objectRecognition]
//            // Start with detection.  Find face, then track it.
//            self.detectionRequests = [objectRecognition]
//            
//            self.sequenceRequestHandler = VNSequenceRequestHandler()
//            
//            self.setupVisionDrawingLayers()
//        } catch let error as NSError {
//            print("Model loading went wrong: \(error)")
//        }
//    }

    // MARK: Drawing Vision Observations
    
//    fileprivate func setupVisionDrawingLayers() {
//        let captureDeviceResolution = self.captureDeviceResolution
//        let captureDeviceBounds = CGRect(x: 0,
//                                         y: 0,
//                                         width: captureDeviceResolution.width,
//                                         height: captureDeviceResolution.height)
//        
////        print("here 🩵",  captureDeviceResolution.width, captureDeviceResolution.height)
//
//        
//        let captureDeviceBoundsCenterPoint = CGPoint(x: captureDeviceBounds.midX,
//                                                     y: captureDeviceBounds.midY)
//        
//        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)
//        
//        guard let rootLayer = self.rootLayer else {
//            self.presentErrorAlert(message: "view was not property initialized")
//            
//            return
//        }
//        
//        let overlayLayer = CALayer()
//        overlayLayer.name = "DetectionOverlay"
//        overlayLayer.masksToBounds = true
//        overlayLayer.anchorPoint = normalizedCenterPoint
//        overlayLayer.bounds = captureDeviceBounds
//        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
//        
//        let faceRectangleShapeLayer = CAShapeLayer()
//        faceRectangleShapeLayer.name = "RectangleOutlineLayer"
//        faceRectangleShapeLayer.bounds = captureDeviceBounds
//        faceRectangleShapeLayer.anchorPoint = normalizedCenterPoint
//        faceRectangleShapeLayer.position = captureDeviceBoundsCenterPoint
//        faceRectangleShapeLayer.fillColor = nil
////        faceRectangleShapeLayer.strokeColor = UIColor.green.withAlphaComponent(0.7).cgColor
//        
//        faceRectangleShapeLayer.strokeColor = UIColor(named: "BrandPrimaryBlue")?.cgColor ?? UIColor.red.cgColor
//
//        faceRectangleShapeLayer.lineWidth = 5
//        faceRectangleShapeLayer.shadowOpacity = 0.7
//        faceRectangleShapeLayer.shadowRadius = 5
//        
////        let faceLandmarksShapeLayer = CAShapeLayer()
////        faceLandmarksShapeLayer.name = "FaceLandmarksLayer"
////        faceLandmarksShapeLayer.bounds = captureDeviceBounds
////        faceLandmarksShapeLayer.anchorPoint = normalizedCenterPoint
////        faceLandmarksShapeLayer.position = captureDeviceBoundsCenterPoint
////        faceLandmarksShapeLayer.fillColor = nil
////        faceLandmarksShapeLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.7).cgColor
////        faceLandmarksShapeLayer.lineWidth = 3
////        faceLandmarksShapeLayer.shadowOpacity = 0.7
////        faceLandmarksShapeLayer.shadowRadius = 5
//        
//        overlayLayer.addSublayer(faceRectangleShapeLayer)
////        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
//        rootLayer.addSublayer(overlayLayer)
//        
//        self.detectionOverlayLayer = overlayLayer
//        self.detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
////        self.detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer
//         self.updateLayerGeometry()
//       
//    }
    
//    fileprivate func updateLayerGeometry() {
//
//        guard let overlayLayer = self.detectionOverlayLayer,
//            let rootLayer = self.rootLayer,
//            let previewLayer = self.videoPreviewLayer
//            else {
//            return
//        }
//        
//        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
//        
//        let videoPreviewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
//        
//        var rotation: CGFloat
//        var scaleX: CGFloat
//        var scaleY: CGFloat
//        
//        // Rotate the layer into screen orientation.
//        switch UIDevice.current.orientation {
//        case .portraitUpsideDown:
//            rotation = 180
//            scaleX = videoPreviewRect.width / captureDeviceResolution.width
//            scaleY = videoPreviewRect.height / captureDeviceResolution.height
//            
//        case .landscapeLeft:
//            rotation = 90
//            scaleX = videoPreviewRect.height / captureDeviceResolution.width
//            scaleY = scaleX
//            
//        case .landscapeRight:
//            rotation = -90
//            scaleX = videoPreviewRect.height / captureDeviceResolution.width
//            scaleY = scaleX
//            
//        default:
//            rotation = 0
//            scaleX = videoPreviewRect.width / captureDeviceResolution.width
//            scaleY = videoPreviewRect.height / captureDeviceResolution.height
//        }
//        
//        // Scale and mirror the image to ensure upright presentation.
//        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
//            .scaledBy(x: scaleX, y: -scaleY)
//        overlayLayer.setAffineTransform(affineTransform)
//        
//        // Cover entire screen UI.
//        let rootLayerBounds = rootLayer.bounds
//        overlayLayer.position = CGPoint(x: rootLayerBounds.midX, y: rootLayerBounds.midY)
//
//    }
    
    fileprivate func addPoints(in landmarkRegion: VNFaceLandmarkRegion2D, to path: CGMutablePath, applying affineTransform: CGAffineTransform, closingWhenComplete closePath: Bool) {

        let pointCount = landmarkRegion.pointCount
        if pointCount > 1 {

            let points: [CGPoint] = landmarkRegion.normalizedPoints
            path.move(to: points[0], transform: affineTransform)
            path.addLines(between: points, transform: affineTransform)
            if closePath {
                path.addLine(to: points[0], transform: affineTransform)
                path.closeSubpath()
            }
        }
        
    }
    
    fileprivate func addIndicators(to faceRectanglePath: CGMutablePath, faceLandmarksPath: CGMutablePath, for faceObservation: VNRecognizedObjectObservation) {
        let displaySize = self.captureDeviceResolution
        
        let faceBounds = VNImageRectForNormalizedRect(faceObservation.boundingBox, Int(displaySize.width), Int(displaySize.height))
        faceRectanglePath.addRect(faceBounds)
        let shapeLayer = createRoundedRectLayerWithBounds(faceBounds)
        detectionOverlayLayer?.addSublayer(shapeLayer)
print("drawingggg")
        
        self.updateLayerGeometry()
        
        CATransaction.commit()
//        if let landmarks = faceObservation.landmarks {
//            // Landmarks are relative to -- and normalized within --- face bounds
//            let affineTransform = CGAffineTransform(translationX: faceBounds.origin.x, y: faceBounds.origin.y)
//                .scaledBy(x: faceBounds.size.width, y: faceBounds.size.height)
//            
//            // Treat eyebrows and lines as open-ended regions when drawing paths.
//            let openLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
//                landmarks.leftEyebrow,
//                landmarks.rightEyebrow,
//                landmarks.faceContour,
//                landmarks.noseCrest,
//                landmarks.medianLine
//            ]
//            for openLandmarkRegion in openLandmarkRegions where openLandmarkRegion != nil {
//                self.addPoints(in: openLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: false)
//            }
//            
//            // Draw eyes, lips, and nose as closed regions.
//            let closedLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
//                landmarks.leftEye,
//                landmarks.rightEye,
//                landmarks.outerLips,
//                landmarks.innerLips,
//                landmarks.nose
//            ]
//            for closedLandmarkRegion in closedLandmarkRegions where closedLandmarkRegion != nil {
//                self.addPoints(in: closedLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: true)
//            }
//        }
//        
        func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
            let shapeLayer = CALayer()
            shapeLayer.bounds = bounds
            shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shapeLayer.name = "Found Object"
            shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
            shapeLayer.cornerRadius = 7
            return shapeLayer
        }

    }
    
    /// - Tag: DrawPaths
    fileprivate func drawFaceObservations(_ faceObservations: [VNRecognizedObjectObservation], color: UIColor = .blue) {
        guard let faceRectangleShapeLayer = self.detectedFaceRectangleShapeLayer
                //,
//            let faceLandmarksShapeLayer = self.detectedFaceLandmarksShapeLayer
            else {
            return
        }
        
        CATransaction.begin()
        
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let faceRectanglePath = CGMutablePath()
        let faceLandmarksPath = CGMutablePath()
        
        DispatchQueue.main.async{
            self.shouldCapture =  !faceObservations.isEmpty
        }
        
        for faceObservation in faceObservations {
            self.addIndicators(to: faceRectanglePath,
                               faceLandmarksPath: faceLandmarksPath,
                               for: faceObservation)
        }
        
        faceRectangleShapeLayer.path = faceRectanglePath
//        faceLandmarksShapeLayer.path = faceLandmarksPath
        
        self.updateLayerGeometry()
        
        CATransaction.commit()
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    /// - Tag: PerformRequests
    // Handle delegate method callback on receiving a sample buffer.
    
    //MARK: All new (Breakfast project)
    func setupVision() {
        // Setup Vision parts
//        let error: NSError! = nil
        guard let modelURL = Bundle.main.url(forResource: "Traffic_Signs", withExtension: "mlmodelc") else { 
            return }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
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
    func drawVisionRequestResults(_ results: [Any]) {

        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
//        for observation in results where observation is VNRecognizedObjectObservation {
        for observation in results{
//            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
            guard let objectObservation = observation as? VNClassificationObservation else {

                print(results.count,"🌙")

                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.identifier

//            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
//            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            print("hi model \(topLabelObservation)")
            print("hi model \(bufferSize.width)")

//            let textLayer = self.createTextSubLayerInBounds(objectBounds,
//                                                            identifier: topLabelObservation.identifier,
//                                                            confidence: topLabelObservation.confidence)
//            shapeLayer.addSublayer(textLayer)
//            detectionOverlay.addSublayer(shapeLayer)

        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
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
            print("hi hi ")
            print(error)
        }
    }
    //MARK: End of new
//    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("👋🏻")
//       // detectAndClassifySign(from: CIImage(cvImageBuffer: sampleBuffer as! CVImageBuffer))
//
//        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
//        
//        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
//        if cameraIntrinsicData != nil {
//            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
//        }
//        
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            print("Failed to obtain a CVPixelBuffer for the current output frame.")
//            return
//        }
//        
//        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
//        
//        guard let requests = self.trackingRequests, !requests.isEmpty else {
//            // No tracking object detected, so perform initial detection
//            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
//                                                            orientation: exifOrientation,
//                                                            options: requestHandlerOptions)
//            
//            do {
//                guard !self.detectionRequests.isEmpty else {
//                    print("No more faces 🏃🏻‍♀️")
//                    return
//                }
//
////                guard let detectRequests = self.detectionRequests else {
////                    print("No more faces 🏃🏻‍♀️")
////                    return
////                }
//                try imageRequestHandler.perform(detectionRequests)
//                print(detectionRequests.count,"🌱")
//
////                try imageRequestHandler.perform(detectRequests)
//            } catch let error as NSError {
//                NSLog("Failed to perform FaceRectangleRequest: %@", error)
//            }
//            return
//        }
//        
//        do {
//            try self.sequenceRequestHandler.perform(requests,
//                                                     on: pixelBuffer,
//                                                     orientation: exifOrientation)
//        } catch let error as NSError {
//            NSLog("Failed to perform SequenceRequest: %@", error)
//        }
//        
//        // Setup the next round of tracking.
//        var newTrackingRequests = [VNTrackObjectRequest]()
//        for trackingRequest in requests {
//            
//            guard let results = trackingRequest.results else {
//                return
//            }
//            
//            guard let observation = results[0] as? VNDetectedObjectObservation else {
//                return
//            }
//            
//            if !trackingRequest.isLastFrame {
//                if observation.confidence > 0.9 {//I changed it from 0.3 to 0.9 bc I want the full face
//                    trackingRequest.inputObservation = observation
//                } else {
//                    trackingRequest.isLastFrame = true
//                }
//                newTrackingRequests.append(trackingRequest)
//            }
//        }
//        self.trackingRequests = newTrackingRequests
//        
//        if newTrackingRequests.isEmpty {
//            // Nothing to track, so abort.
//            self.removeDrawing()
//            return
//        }
//        
//        // Perform face landmark tracking on detected faces.
//        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
//        
//        // Perform landmark detection on tracked faces.
//        for trackingRequest in newTrackingRequests {
//            
//            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request, error) in
//                
//                if error != nil {
//                    print("FaceLandmarks error: \(String(describing: error)).")
//                }
//                
//                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
//                    let results = landmarksRequest.results as? [VNRecognizedObjectObservation] else {
//           
//                        return
//                }
//                
//                // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
//                DispatchQueue.main.async {
//                    print("👋🏻👋🏻👋🏻👋🏻👋🏻👋🏻👋🏻👋🏻👋🏻vv")
//
//                    self.drawFaceObservations(results)
//                }
//            })
//            
//            guard let trackingResults = trackingRequest.results else {
//                return
//            }
//            
//            guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
//                return
//            }
//            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
//            faceLandmarksRequest.inputFaceObservations = [faceObservation]
//            
//            // Continue to track detected facial landmarks.
//            faceLandmarkRequests.append(faceLandmarksRequest)
//            
//            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
//                                                            orientation: exifOrientation,
//                                                            options: requestHandlerOptions)
//            
//            do {
//                try imageRequestHandler.perform(faceLandmarkRequests)
//            } catch let error as NSError {
//                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
//            }
//        }
//    }
    
    
    
    func removeDrawing(){
        self.drawFaceObservations([])
    }
    
    
}

//MARK: Capture photo
extension CustomCameraController: AVCapturePhotoCaptureDelegate{
    func capturePhoto() {
        if shouldCapture{
            let photoSettings = AVCapturePhotoSettings()
            self.photoOutput?.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("No image data available")
            return
        }
        
        DispatchQueue.main.async {
            self.capturedImage = UIImage(data: imageData)
        }
    }
    
    
}
//Either resolution or the root layer



