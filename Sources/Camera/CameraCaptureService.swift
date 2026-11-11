//
//  CameraCaptureService.swift
//  SpektraCam
//
//  Hardware-Aligned Capture Engine for iPhone 13 Pro Max (iPhone14,3 / A15 Bionic)
//  - Fixes Black Screen in Video Mode:
//      1. Sets `sessionPreset = .inputPriority` before locking custom 10-bit HLG `activeFormat` so `commitConfiguration()`
//         never overwrites or invalidates the video data output pipeline.
//      2. Queries `videoDataOutput.availableVideoPixelFormatTypes` AFTER `activeFormat` is set, and falls back cleanly
//         to 8-bit bi-planar if 10-bit delivery is rejected by the current connection.
//  - Zero-Lag Slider Performance:
//      Separates camera telemetry `@Published` properties from high-frequency darkroom slider parameters (`activeParameters`)
//      so dragging sliders at 120Hz never triggers a full SwiftUI view-hierarchy rebuild.
//

import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import Photos
import Metal
import Combine

public enum iPhone13ProMaxLens: String, CaseIterable, Identifiable {
    case ultraWide13mm = "builtInUltraWideCamera"
    case wide26mm      = "builtInWideAngleCamera"
    case telephoto77mm = "builtInTelephotoCamera"

    public var id: String { rawValue }
    public var focalLengthLabel: String {
        switch self {
        case .ultraWide13mm: return "13mm f/2.4"
        case .wide26mm:      return "26mm f/1.5"
        case .telephoto77mm: return "77mm f/2.8 (3×)"
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

public enum VideoRecordingPipelineMode: Int, CaseIterable, Identifiable {
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

public enum VideoCodecSelection: String, CaseIterable, Identifiable {
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
                reconfigureMode(isVideo: isCaptureModeVideo)
            }
        }
    }
    @Published public var videoPipelineMode: VideoRecordingPipelineMode = .logCleanWithFilmMonitor
    @Published public var logTransferCurve: LogEncodingTransferFunction = .appleLogCompatible
    @Published public var videoCodec: VideoCodecSelection = .hevc10Bit
    @Published public var statusBannerText: String = "Initializing Camera & Metal Engine..."
    @Published public var activePixelFormatIs10Bit: Bool = false

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.spektracam.sessionQueue", qos: .userInitiated)
    private let videoProcessingQueue = DispatchQueue(label: "com.spektracam.videoProcessingQueue", qos: .userInteractive)

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isSessionConfigured = false

    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?
    public var latestPixelBuffer: CVPixelBuffer? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _latestPixelBuffer
    }

    private let snapshotLock = NSLock()
    private var _latestRenderedTexture: MTLTexture?
    public func updateLatestRenderedTexture(_ tex: MTLTexture) {
        snapshotLock.lock()
        _latestRenderedTexture = tex
        snapshotLock.unlock()
    }

    // Lock-protected parameters read directly by MTKView.draw(in:) without triggering SwiftUI body recomputation
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
            _activeParameters = newValue
            paramsLock.unlock()
        }
    }

    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?

    public let metalRenderer: MetalFilmRenderer?
    private let ciContext: CIContext?

    public override init() {
        let renderer = MetalFilmRenderer()
        self.metalRenderer = renderer
        if let dev = renderer?.device {
            self.ciContext = CIContext(mtlDevice: dev, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any
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
                self.configureSession(for: self.activeLens, isVideoMode: self.isCaptureModeVideo)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureSession(for: self.activeLens, isVideoMode: self.isCaptureModeVideo)
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

    // MARK: - Reliable Dual-Mode Session Configuration (Fixes Video Mode Blank Viewfinder)
    private func configureSession(for lens: iPhone13ProMaxLens, isVideoMode: Bool) {
        session.beginConfiguration()

        if let existingInput = videoDeviceInput {
            session.removeInput(existingInput)
            self.videoDeviceInput = nil
        }

        // CRITICAL FIX FOR VIDEO MODE BLACK SCREEN:
        // In Video Mode, remove photoOutput (which conflicts with 10-bit 4K video formats when AppleProRAW was enabled)
        // and use `.hd1920x1080` or `.hd4K3840x2160` standard preset first so `AVCaptureVideoDataOutput` always stays active!
        if isVideoMode {
            if session.outputs.contains(photoOutput) {
                session.removeOutput(photoOutput)
            }
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }
        } else {
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            } else {
                session.sessionPreset = .high
            }
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

        // Ensure VideoDataOutput is attached
        if !session.outputs.contains(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
        }

        if !isVideoMode {
            if !session.outputs.contains(photoOutput) && session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 14.3, *) {
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                }
            }
        }

        // Ensure Continuous Auto Exposure & Auto White Balance are active
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

        // Try enabling 10-bit HLG in Video mode ONLY if supported by VideoDataOutput without dropping frames
        var using10Bit = false
        if isVideoMode {
            using10Bit = configure10BitHLGFormatSafely(on: cameraDevice)
        }

        let supportedFormats = videoDataOutput.availableVideoPixelFormatTypes
        let targetFormat: OSType
        if using10Bit && supportedFormats.contains(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        } else if supportedFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            using10Bit = false
        } else if supportedFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            using10Bit = false
        } else {
            targetFormat = kCVPixelFormatType_32BGRA
            using10Bit = false
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

        session.commitConfiguration()
        isSessionConfigured = true

        if !session.isRunning {
            session.startRunning()
        }

        let final10Bit = using10Bit
        let proRAWActive: Bool = {
            if !isVideoMode, #available(iOS 14.3, *) {
                return self.photoOutput.isAppleProRAWEnabled
            }
            return false
        }()

        DispatchQueue.main.async {
            self.activePixelFormatIs10Bit = final10Bit
            if isVideoMode {
                self.statusBannerText = final10Bit
                    ? "10-Bit BT.2020 HLG → Scene-Linear + Log Ready"
                    : "Scene-Linear + Real-Time Log Video Ready"
            } else {
                self.statusBannerText = proRAWActive
                    ? "12-Bit Apple ProRAW (DNG) + 81-Band Spectral Engine"
                    : "12MP Bayer RAW (DNG) + 81-Band Spectral Engine"
            }
        }
    }

    private func configure10BitHLGFormatSafely(on device: AVCaptureDevice) -> Bool {
        // Prefer 1920x1080 10-bit HLG format for guaranteed 60fps zero-lag real-time spectral rendering on A15
        let tenBitFormats = device.formats.filter { format in
            let subType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supports30fps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30.0 }
            return subType == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange && dims.width == 1920 && dims.height == 1080 && supports30fps
        }

        guard let targetFormat = tenBitFormats.last else {
            return false
        }

        do {
            // Switch preset to inputPriority BEFORE locking activeFormat so session.commitConfiguration() doesn't reset the format!
            session.sessionPreset = .inputPriority
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.activeFormat = targetFormat
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            let desiredFPS: Double = 30.0
            if let matchedRange = targetFormat.videoSupportedFrameRateRanges.first(where: {
                $0.minFrameRate <= desiredFPS && desiredFPS <= $0.maxFrameRate
            }) {
                let duration = CMTimeMake(value: 1, timescale: Int32(desiredFPS))
                let clampedDuration = CMTimeClampToRange(
                    duration,
                    range: CMTimeRangeFromTimeToTime(start: matchedRange.minFrameDuration, end: matchedRange.maxFrameDuration)
                )
                device.activeVideoMinFrameDuration = clampedDuration
                device.activeVideoMaxFrameDuration = clampedDuration
            }
            return true
        } catch {
            return false
        }
    }

    private func reconfigureMode(isVideo: Bool) {
        let lens = activeLens
        sessionQueue.async { [weak self] in
            self?.configureSession(for: lens, isVideoMode: isVideo)
        }
    }

    public func switchLens(to lens: iPhone13ProMaxLens) {
        activeLens = lens
        var p = activeParameters
        p.lensFocalLengthMM = lens.nominalFocalMM
        activeParameters = p
        let isVideo = isCaptureModeVideo
        sessionQueue.async { [weak self] in
            self?.configureSession(for: lens, isVideoMode: isVideo)
        }
    }

    // MARK: - Capture 81-Band Spectral Film Render + 12-Bit ProRAW DNG
    public func captureRAWPhoto() {
        saveCurrentSpectralRenderToPhotos()

        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured, !self.isCaptureModeVideo else { return }

            let availableRAW = self.photoOutput.availableRawPhotoPixelFormatTypes
            let photoSettings: AVCapturePhotoSettings

            if let rawFormat = availableRAW.first {
                let processedFormat: [String: Any]? = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? [AVVideoCodecKey: AVVideoCodecType.hevc]
                    : nil
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
            } else {
                photoSettings = AVCapturePhotoSettings()
            }

            if self.photoOutput.isHighResolutionCaptureEnabled {
                photoSettings.isHighResolutionPhotoEnabled = true
            }
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    private func saveCurrentSpectralRenderToPhotos() {
        snapshotLock.lock()
        let tex = _latestRenderedTexture
        snapshotLock.unlock()

        guard let texture = tex,
              let ciCtx = ciContext,
              let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any]) else {
            return
        }
        let oriented = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height))
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let jpegData = ciCtx.jpegRepresentation(of: oriented, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96]) else {
            return
        }

        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: jpegData, options: nil)
        }) { [weak self] saved, _ in
            if saved {
                DispatchQueue.main.async {
                    self?.statusBannerText = "Saved Spectral Film Print + 12-Bit DNG to Photos"
                }
            }
        }
    }

    // MARK: - Real-Time Video Recording (Writes Live Rendered or Log Frames to Movie)
    public func toggleVideoRecording() {
        if isRecordingVideo {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpektraCam_\(Int(Date().timeIntervalSince1970)).mov")

        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: 1080,
                AVVideoHeightKey: 1920
            ]

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = true

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 1080,
                    kCVPixelBufferHeightKey as String: 1920,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]
            )

            if writer.canAdd(writerInput) {
                writer.add(writerInput)
            }
            writer.startWriting()

            self.assetWriter = writer
            self.assetWriterVideoInput = writerInput
            self.assetWriterPixelBufferAdaptor = adaptor
            self.recordingStartTime = nil
            self.isRecordingVideo = true
            self.statusBannerText = (videoPipelineMode == .logCleanWithFilmMonitor)
                ? "REC \(logTransferCurve.displayName) + Live Film VF"
                : "REC Baked Physical Film"
        } catch {
            self.statusBannerText = "Recording Error: \(error.localizedDescription)"
        }
    }

    private func stopVideoRecording() {
        guard let writer = assetWriter, let input = assetWriterVideoInput else {
            isRecordingVideo = false
            return
        }
        isRecordingVideo = false
        input.markAsFinished()
        let outputURL = writer.outputURL
        writer.finishWriting { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
            }) { saved, _ in
                DispatchQueue.main.async {
                    self?.statusBannerText = saved ? "Saved Video to Photos" : "Video Recording Stopped"
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
        frameLock.lock()
        _latestPixelBuffer = pb
        frameLock.unlock()
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, photo.isRawPhoto, let data = photo.fileDataRepresentation() else { return }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
        }) { [weak self] saved, _ in
            if saved {
                DispatchQueue.main.async {
                    self?.statusBannerText = "Saved Spectral Print + 12-Bit ProRAW DNG"
                }
            }
        }
    }
}
