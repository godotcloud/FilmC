//
//  CameraCaptureService.swift
//  SpektraCam
//
//  Hardware-Aligned Capture Engine for iPhone 13 Pro Max (iPhone14,3 / A15 Bionic)
//  - Unified Continuous Session (Zero `AVCaptureSession` teardown when switching between 12MP Photo & Video modes!)
//  - Non-Blocking Lock-Protected Video Recording State Machine (Zero `videoWriterQueue.sync` on Main Thread!)
//  - GPU-Completion-Synchronized `AVAssetWriterInputPixelBufferAdaptor` Append
//

import Foundation
import AVFoundation
import CoreVideo
import CoreMedia
import CoreImage
import Photos
import Metal
import Combine

public enum iPhone13ProMaxLens: String, CaseIterable, Identifiable, Equatable {
    case ultraWide13mm = "builtInUltraWideCamera"
    case wide26mm      = "builtInWideAngleCamera"
    case telephoto77mm = "builtInTelephotoCamera"

    public var id: String { rawValue }
    public var focalLengthLabel: String {
        switch self {
        case .ultraWide13mm: return "13mm f/2.4"
        case .wide26mm:      return "26mm f/1.5"
        case .telephoto77mm: return "77mm f/2.8"
        }
    }
    public var nominalFocalMM: Float {
        switch self {
        case .ultraWide13mm: return 13.0
        case .wide26mm:      return 26.0
        case .telephoto77mm: return 77.0
        }
    }
    public var avDeviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide13mm: return .builtInUltraWideCamera
        case .wide26mm:      return .builtInWideAngleCamera
        case .telephoto77mm: return .builtInTelephotoCamera
        }
    }
}

public enum VideoRecordingPipelineMode: Int, CaseIterable, Identifiable, Equatable {
    case logCleanWithFilmMonitor = 0
    case bakedPhysicalFilm = 1

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .logCleanWithFilmMonitor: return "Clean Log + Film VF"
        case .bakedPhysicalFilm:       return "Bake Physical Film"
        }
    }
}

public enum VideoCodecSelection: String, CaseIterable, Identifiable, Equatable {
    case hevc10Bit   = "HEVC 10-bit"
    case proRes422HQ = "Apple ProRes 422 HQ"

    public var id: String { rawValue }
}

public final class CameraCaptureService: NSObject, ObservableObject {
    @Published public var activeLens: iPhone13ProMaxLens = .wide26mm
    @Published public var isRecordingVideo: Bool = false
    @Published public var isCaptureModeVideo: Bool = false {
        didSet {
            if oldValue != isCaptureModeVideo {
                if isRecordingVideo {
                    stopVideoRecording()
                }
                statusBannerText = isCaptureModeVideo
                    ? "Physical Film & Log Video Ready"
                    : "12MP (3024×4032) Spectral Darkroom Ready"
                bumpParameterRevision()
            }
        }
    }
    @Published public var alsoSaveRawDNG: Bool = false
    @Published public var isProcessing12MPPhoto: Bool = false
    @Published public var videoPipelineMode: VideoRecordingPipelineMode = .bakedPhysicalFilm
    @Published public var logTransferCurve: LogEncodingTransferFunction = .appleLogCompatible {
        didSet {
            bumpParameterRevision()
        }
    }
    @Published public var videoCodec: VideoCodecSelection = .hevc10Bit
    @Published public var statusBannerText: String = "12MP (3024×4032) Spectral Darkroom Ready"
    @Published public var activePixelFormatIs10Bit: Bool = false

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.spektracam.sessionQueue", qos: .userInitiated)
    private let videoProcessingQueue = DispatchQueue(label: "com.spektracam.videoProcessingQueue", qos: .userInteractive)
    private let videoWriterQueue = DispatchQueue(label: "com.spektracam.videoWriterQueue", qos: .userInitiated)
    private let photoRenderQueue = DispatchQueue(label: "com.spektracam.photoRenderQueue", qos: .userInitiated)

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isSessionConfigured = false

    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?
    private var _latestPresentationTime: CMTime = .invalid
    private var _latestFrameID: UInt64 = 0
    private var _paramRevisionID: UInt64 = 1

    public func latestFrameSnapshot() -> (pixelBuffer: CVPixelBuffer?, pts: CMTime, frameID: UInt64, combinedRevision: UInt64) {
        frameLock.lock()
        defer { frameLock.unlock() }
        let rev = (_latestFrameID &* 1099511628211) &+ _paramRevisionID
        return (_latestPixelBuffer, _latestPresentationTime, _latestFrameID, rev)
    }

    private func bumpParameterRevision() {
        frameLock.lock()
        _paramRevisionID &+= 1
        frameLock.unlock()
    }

    private let paramsLock = NSLock()
    private var _activeParameters = FilmSimulationParameters()
    public var activeParameters: FilmSimulationParameters {
        get {
            paramsLock.lock()
            defer { paramsLock.unlock() }
            return _activeParameters
        }
        set {
            paramsLock.lock()
            let changed = (_activeParameters != newValue)
            _activeParameters = newValue
            paramsLock.unlock()
            if changed {
                bumpParameterRevision()
            }
        }
    }

    // Real-Time Video Recording State (Protected by `writerLock` & serialized on `videoWriterQueue`)
    private let writerLock = NSLock()
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isWriterActive: Bool = false
    private var hasStartedWritingSession: Bool = false
    private var lastAppendedPTS: CMTime = .invalid
    private var lastDequeuedCameraFrameID: UInt64 = 0

    public let metalRenderer: MetalFilmRenderer?
    private let ciContext: CIContext?

    public override init() {
        let renderer = MetalFilmRenderer()
        self.metalRenderer = renderer
        if let dev = renderer?.device {
            self.ciContext = CIContext(mtlDevice: dev, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any,
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = nil
        }
        super.init()
    }

    public func requestPermissionsAndSetup() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                self.configureSession(for: self.activeLens)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureSession(for: self.activeLens)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.statusBannerText = "Camera Permission Denied in Settings"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.statusBannerText = "Please Enable Camera Access in Settings"
            }
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }

    // Unified camera session that serves both 12MP Photo Capture and Real-Time Video Recording
    // without tearing down inputs/outputs or triggering `AVCaptureSession` format exceptions!
    private func configureSession(for lens: iPhone13ProMaxLens) {
        session.beginConfiguration()

        if let existingInput = videoDeviceInput {
            session.removeInput(existingInput)
            self.videoDeviceInput = nil
        }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        } else {
            session.sessionPreset = .high
        }

        let device = AVCaptureDevice.default(lens.avDeviceType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        guard let cameraDevice = device,
              let input = try? AVCaptureDeviceInput(device: cameraDevice),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.statusBannerText = "Camera Input Unavailable"
            }
            return
        }
        session.addInput(input)
        self.videoDeviceInput = input

        if !session.outputs.contains(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
        }

        if !session.outputs.contains(photoOutput) && session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        photoOutput.isHighResolutionCaptureEnabled = true
        if photoOutput.maxPhotoQualityPrioritization.rawValue >= AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue {
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        do {
            try cameraDevice.lockForConfiguration()
            if cameraDevice.isExposureModeSupported(.continuousAutoExposure) {
                cameraDevice.exposureMode = .continuousAutoExposure
            }
            if cameraDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                cameraDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            cameraDevice.unlockForConfiguration()
        } catch {}

        let supportedFormats = videoDataOutput.availableVideoPixelFormatTypes
        let targetFormat: OSType
        if supportedFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } else if supportedFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } else {
            targetFormat = kCVPixelFormatType_32BGRA
        }

        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: targetFormat
        ]

        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            connection.isEnabled = true
        }

        if let photoConn = photoOutput.connection(with: .video),
           photoConn.isVideoOrientationSupported {
            photoConn.videoOrientation = .portrait
        }

        session.commitConfiguration()
        isSessionConfigured = true

        if !session.isRunning {
            session.startRunning()
        }

        let isVideo = self.isCaptureModeVideo
        DispatchQueue.main.async {
            self.activePixelFormatIs10Bit = false
            self.statusBannerText = isVideo
                ? "Physical Film & Log Video Ready"
                : "12MP (3024×4032) Spectral Darkroom Ready"
        }
    }

    public func switchLens(to lens: iPhone13ProMaxLens) {
        guard activeLens != lens else { return }
        if isRecordingVideo {
            stopVideoRecording()
        }
        activeLens = lens
        var p = activeParameters
        p.lensFocalLengthMM = lens.nominalFocalMM
        activeParameters = p
        sessionQueue.async { [weak self] in
            self?.configureSession(for: lens)
        }
    }

    // MARK: - Zero-Lag 12MP (3024x4032) Full-Resolution Still Photo Capture
    public func captureRAWPhoto() {
        guard !isProcessing12MPPhoto else { return }
        DispatchQueue.main.async {
            self.isProcessing12MPPhoto = true
            self.statusBannerText = "Developing 12MP (3024×4032) Spectral Print..."
        }

        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured else {
                DispatchQueue.main.async { [weak self] in
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            let photoSettings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }

            if self.photoOutput.isHighResolutionCaptureEnabled {
                photoSettings.isHighResolutionPhotoEnabled = true
            }
            photoSettings.photoQualityPrioritization = .speed

            if let photoConn = self.photoOutput.connection(with: .video),
               photoConn.isVideoOrientationSupported {
                photoConn.videoOrientation = .portrait
            }

            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // MARK: - Develop Full 12MP (3024x4032) Sensor Image Through 81-Band Metal Darkroom
    private func processAndSaveFullResolutionPhoto(photoData: Data, paramsSnapshot: FilmSimulationParameters) {
        photoRenderQueue.async { [weak self] in
            guard let self = self,
                  let renderer = self.metalRenderer,
                  let ciCtx = self.ciContext,
                  let rawCIImage = CIImage(data: photoData, options: [.applyOrientationProperty: true]) else {
                DispatchQueue.main.async { [weak self] in
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            let extent = rawCIImage.extent.integral
            let fullW = Int(extent.width)
            let fullH = Int(extent.height)
            guard fullW > 0 && fullH > 0 else {
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                }
                return
            }

            let inDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: fullW,
                height: fullH,
                mipmapped: false
            )
            inDesc.usage = [.shaderRead, .shaderWrite]
            inDesc.storageMode = .private

            guard let inputLinearTex = renderer.device.makeTexture(descriptor: inDesc) else {
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                }
                return
            }

            let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
            let negFullH: CGFloat = -CGFloat(fullH)
            let flippedInput = rawCIImage
                .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: negFullH))

            ciCtx.render(
                flippedInput,
                to: inputLinearTex,
                commandBuffer: nil,
                bounds: CGRect(x: 0, y: 0, width: fullW, height: fullH),
                colorSpace: linearSpace
            )

            guard let developedTex = renderer.renderFullResolutionPhoto(
                inputLinearTexture: inputLinearTex,
                params: paramsSnapshot
            ) else {
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                }
                return
            }

            let outColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            guard let outCI = CIImage(mtlTexture: developedTex, options: [.colorSpace: outColorSpace]) else {
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                }
                return
            }
            let negOutH: CGFloat = -outCI.extent.height
            let orientedOut = outCI.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: negOutH))

            guard let jpegData = ciCtx.jpegRepresentation(
                of: orientedOut,
                colorSpace: outColorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
            ) else {
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: jpegData, options: nil)
            }) { saved, _ in
                DispatchQueue.main.async {
                    self.isProcessing12MPPhoto = false
                    if saved {
                        self.statusBannerText = "Saved \(fullW)×\(fullH) (12MP) Spectral Print"
                    }
                }
            }
        }
    }

    // MARK: - Crash-Proof Real-Time Video Recording (`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`)
    public func toggleVideoRecording() {
        if isRecordingVideo {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        let modeSnapshot = self.videoPipelineMode
        let logSnapshot = self.logTransferCurve

        videoWriterQueue.async { [weak self] in
            guard let self = self else { return }
            self.writerLock.lock()
            if self.isWriterActive {
                self.writerLock.unlock()
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpektraCam_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: tempURL)

            do {
                let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
                // 3:4 aspect ratio (960x1280) matches the sensor & viewfinder aspect ratio without cropping
                let recWidth = 720
                let recHeight = 960
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: recWidth,
                    AVVideoHeightKey: recHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 14_000_000
                    ]
                ]

                let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                writerInput.expectsMediaDataInRealTime = true

                let sourceBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: recWidth,
                    kCVPixelBufferHeightKey as String: recHeight,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: writerInput,
                    sourcePixelBufferAttributes: sourceBufferAttributes
                )

                guard writer.canAdd(writerInput) else {
                    self.writerLock.unlock()
                    return
                }
                writer.add(writerInput)

                guard writer.startWriting() else {
                    self.writerLock.unlock()
                    return
                }

                // Immediately start session at kCMTimeZero and use relative presentation timestamps
                // so `startSession(atSourceTime:)` is ALWAYS active before any frame or `stopVideoRecording()`!
                writer.startSession(atSourceTime: .zero)

                self.assetWriter = writer
                self.assetWriterVideoInput = writerInput
                self.assetWriterPixelBufferAdaptor = adaptor
                self.hasStartedWritingSession = true
                self.lastAppendedPTS = .invalid
                self.lastDequeuedCameraFrameID = 0
                self.isWriterActive = true
                self.writerLock.unlock()

                DispatchQueue.main.async {
                    self.isRecordingVideo = true
                    self.statusBannerText = (modeSnapshot == .logCleanWithFilmMonitor)
                        ? "REC \(logSnapshot.displayName) + Live Film VF"
                        : "REC Baked Physical Film"
                }
            } catch {
                self.writerLock.unlock()
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    self.statusBannerText = "Recording Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // Non-blocking lock check (never blocks main thread on `videoWriterQueue.sync`!)
    public func dequeueVideoRecordingBufferIfNeeded(cameraFrameID: UInt64) -> (pixelBuffer: CVPixelBuffer, bakeFilm: Bool)? {
        guard writerLock.try() else { return nil }
        defer { writerLock.unlock() }

        guard isWriterActive,
              cameraFrameID != lastDequeuedCameraFrameID,
              let writer = assetWriter,
              writer.status == .writing,
              let input = assetWriterVideoInput,
              input.isReadyForMoreMediaData,
              let pool = assetWriterPixelBufferAdaptor?.pixelBufferPool else {
            return nil
        }

        var pbOut: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut) == kCVReturnSuccess,
              let validPB = pbOut else {
            return nil
        }
        lastDequeuedCameraFrameID = cameraFrameID
        let bakeFilm = (self.videoPipelineMode == .bakedPhysicalFilm)
        return (validPB, bakeFilm)
    }

    private var recordingFirstPTS: CMTime = .invalid

    public func appendRecordedVideoFrame(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        videoWriterQueue.async { [weak self] in
            guard let self = self else { return }
            self.writerLock.lock()
            guard self.isWriterActive,
                  self.hasStartedWritingSession,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  let input = self.assetWriterVideoInput,
                  input.isReadyForMoreMediaData,
                  let adaptor = self.assetWriterPixelBufferAdaptor else {
                self.writerLock.unlock()
                return
            }

            let rawPTS = pts.isValid ? pts : CMTimeMakeWithSeconds(CACurrentMediaTime(), preferredTimescale: 600)
            if !self.recordingFirstPTS.isValid {
                self.recordingFirstPTS = rawPTS
            }
            var relativePTS = CMTimeSubtract(rawPTS, self.recordingFirstPTS)
            if relativePTS.seconds < 0 {
                relativePTS = .zero
            }
            if self.lastAppendedPTS.isValid && CMTimeCompare(relativePTS, self.lastAppendedPTS) <= 0 {
                relativePTS = CMTimeAdd(self.lastAppendedPTS, CMTimeMake(value: 1, timescale: 600))
            }

            adaptor.append(pixelBuffer, withPresentationTime: relativePTS)
            self.lastAppendedPTS = relativePTS
            self.writerLock.unlock()
        }
    }

    private func stopVideoRecording() {
        videoWriterQueue.async { [weak self] in
            guard let self = self else { return }
            self.writerLock.lock()
            guard self.isWriterActive,
                  let writer = self.assetWriter,
                  let input = self.assetWriterVideoInput else {
                self.writerLock.unlock()
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                }
                return
            }

            self.isWriterActive = false
            let hasFrames = self.lastAppendedPTS.isValid
            self.hasStartedWritingSession = false
            self.lastAppendedPTS = .invalid
            self.recordingFirstPTS = .invalid
            self.assetWriter = nil
            self.assetWriterVideoInput = nil
            self.assetWriterPixelBufferAdaptor = nil
            self.writerLock.unlock()

            let outputURL = writer.outputURL
            if writer.status == .writing && hasFrames {
                input.markAsFinished()
                writer.finishWriting { [weak self] in
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                    }) { saved, _ in
                        try? FileManager.default.removeItem(at: outputURL)
                        DispatchQueue.main.async {
                            self?.isRecordingVideo = false
                            self?.statusBannerText = saved
                                ? "Saved Physical Film/Log Video to Photos"
                                : "Video Saved"
                        }
                    }
                }
            } else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    self.statusBannerText = "Physical Film & Log Video Ready"
                }
            }
        }
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameLock.lock()
        _latestPixelBuffer = pb
        _latestPresentationTime = pts
        _latestFrameID &+= 1
        frameLock.unlock()
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isProcessing12MPPhoto = false
            }
            return
        }

        if photo.isRawPhoto {
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: nil)
        } else {
            let snapshotParams = self.activeParameters
            processAndSaveFullResolutionPhoto(photoData: data, paramsSnapshot: snapshotParams)
        }
    }
}
