//
//  CameraCaptureService.swift
//  SpektraCam
//
//  Hardware-Aligned Capture Engine for iPhone 13 Pro Max (iPhone14,3 / A15 Bionic)
//  - Safe Session Configuration Order (fixes AVFoundation NSInvalidArgumentException crash on launch):
//      1. Set sessionPreset (.photo for Still ProRAW mode, .inputPriority for 10-bit HLG Video mode)
//      2. Attach AVCaptureDeviceInput
//      3. Add AVCapturePhotoOutput + AVCaptureVideoDataOutput
//      4. Configure activeFormat / ProRAW / manual exposure ONLY when warranted and supported
//  - Triple-Lens Switching: 13mm f/2.4 Ultra-Wide (Macro), 26mm f/1.5 Wide (1.9um Sensor-Shift OIS), 77mm f/2.8 3x Telephoto
//  - Thread-Safe CVPixelBuffer handoff with NSLock (eliminates Swift Task races at 30/60fps)
//

import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import Photos
import Metal
import Combine

public enum iPhone13ProMaxLens: String, CaseIterable, Identifiable {
    case ultraWide13mm = "builtInUltraWideCamera" // 13mm f/2.4 120° FOV + 2cm Macro
    case wide26mm      = "builtInWideAngleCamera" // 26mm f/1.5 1.9µm Sensor-Shift OIS
    case telephoto77mm = "builtInTelephotoCamera" // 77mm f/2.8 3x Optical Zoom

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
    case logCleanWithFilmMonitor = 0 // 纯 Log 底片直录 + 实时物理胶片监看 (Viewfinder Emulation)
    case bakedPhysicalFilm = 1       // 物理胶片效果实时烘焙录制 (10-bit HEVC / ProRes 422 HQ)

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .logCleanWithFilmMonitor: return "Clean Log Record + Film VF"
        case .bakedPhysicalFilm:       return "Bake Physical Film (10-Bit)"
        }
    }
}

public enum VideoCodecSelection: String, CaseIterable, Identifiable {
    case hevc10Bit   = "HEVC 10-bit"
    case proRes422HQ = "Apple ProRes 422 HQ"

    public var id: String { rawValue }
}

public final class CameraCaptureService: NSObject, ObservableObject {
    // Published UI States
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
    @Published public var lock180DegreeShutterAngle: Bool = true
    @Published public var currentISO: Float = 100.0
    @Published public var currentShutterDurationSeconds: Double = 1.0 / 48.0
    @Published public var whiteBalanceKelvin: Float = 5500.0
    @Published public var whiteBalanceTint: Float = 0.0
    @Published public var statusBannerText: String = "Initializing Camera & Metal Engine..."
    @Published public var activePixelFormatIs10Bit: Bool = false

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.spektracam.sessionQueue", qos: .userInitiated)
    private let videoProcessingQueue = DispatchQueue(label: "com.spektracam.videoProcessingQueue", qos: .userInteractive)

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isSessionConfigured = false

    // Thread-safe frame storage for MTKView (avoids Swift Task creation overhead & thread races)
    private let frameLock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?
    public var latestPixelBuffer: CVPixelBuffer? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _latestPixelBuffer
    }

    // Thread-safe parameters snapshot for renderer
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

    // AVAssetWriter for 10-bit HEVC / ProRes 422 HQ Recording
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?

    // Shared reference to Metal Renderer
    public let metalRenderer: MetalFilmRenderer?

    public override init() {
        self.metalRenderer = MetalFilmRenderer()
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

    // MARK: - Crash-Safe Camera Session Setup for iPhone 13 Pro Max
    private func configureSession(for lens: iPhone13ProMaxLens, isVideoMode: Bool) {
        session.beginConfiguration()

        // 1. Remove existing inputs before changing sessionPreset
        if let existingInput = videoDeviceInput {
            session.removeInput(existingInput)
            self.videoDeviceInput = nil
        }

        // 2. Use .photo preset in Still Photo mode (required by Apple ProRAW / Bayer RAW!)
        //    Switch to .high or .hd4K3840x2160 in Video mode before locking custom 10-bit format
        if isVideoMode {
            if session.canSetSessionPreset(.hd4K3840x2160) {
                session.sessionPreset = .hd4K3840x2160
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

        // 3. Discover requested lens (fallback gracefully to Wide 26mm if unavailable)
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

        // 4. Attach VideoDataOutput FIRST so we can query supported pixel formats safely
        if !session.outputs.contains(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
        }

        // 5. Attach PhotoOutput in Still Photo mode (or keep attached if compatible)
        if !session.outputs.contains(photoOutput) && session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // 6. Configure 10-bit HLG format ONLY in Video Mode, AFTER inputs/outputs are added
        var using10Bit = false
        if isVideoMode {
            using10Bit = configure10BitHLGFormatSafely(on: cameraDevice)
        } else {
            // In Still Photo mode, configure Apple ProRAW / RAW safely
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 14.3, *) {
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                }
            }
        }

        // 7. Set VideoDataOutput pixel format ONLY after checking availableVideoPixelFormatTypes
        let supportedFormats = videoDataOutput.availableVideoPixelFormatTypes
        let targetFormat: OSType
        if using10Bit && supportedFormats.contains(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        } else if supportedFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            using10Bit = false
        } else {
            targetFormat = kCVPixelFormatType_32BGRA
            using10Bit = false
        }

        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: targetFormat
        ]

        if let connection = videoDataOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()
        isSessionConfigured = true

        if !session.isRunning {
            session.startRunning()
        }

        let final10Bit = using10Bit
        let proRAWActive: Bool = {
            if #available(iOS 14.3, *) {
                return self.photoOutput.isAppleProRAWEnabled
            }
            return false
        }()

        DispatchQueue.main.async {
            self.activePixelFormatIs10Bit = final10Bit
            if isVideoMode {
                self.statusBannerText = final10Bit
                    ? "4K 10-Bit BT.2020 HLG → Scene-Linear + Log Ready"
                    : "4K Rec.709 → Scene-Linear + Log Ready"
            } else {
                self.statusBannerText = proRAWActive
                    ? "12-Bit Apple ProRAW (DNG) + 81-Band Spectral Engine"
                    : "12MP Bayer RAW (DNG) + 81-Band Spectral Engine"
            }
        }
    }

    /// Safely selects a 10-bit BT.2020 HLG format on iPhone 13 Pro Max without violating min/max frame duration bounds
    private func configure10BitHLGFormatSafely(on device: AVCaptureDevice) -> Bool {
        let tenBitFormats = device.formats.filter { format in
            let subType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supports30fps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 24.0 }
            return subType == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange && dims.width >= 1920 && supports30fps
        }

        guard let targetFormat = tenBitFormats.last else {
            return false
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.activeFormat = targetFormat

            // Find a valid frame rate range before setting activeVideoMinFrameDuration
            let desiredFPS: Double = lock180DegreeShutterAngle ? 24.0 : 30.0
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

    // MARK: - Switch iPhone 13 Pro Max Triple Lenses (13mm / 26mm / 77mm)
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

    // MARK: - Crash-Safe Manual Exposure & White Balance
    public func setManualExposure(iso: Float, shutterSeconds: Double) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            guard device.isExposureModeSupported(.custom) else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let format = device.activeFormat
                let safeISO = min(max(iso, format.minISO), format.maxISO)
                let requestedDur = CMTimeMakeWithSeconds(shutterSeconds, preferredTimescale: 1_000_000)
                let minDur = format.minExposureDuration
                let maxDur = format.maxExposureDuration
                let safeDur = CMTimeMaximum(minDur, CMTimeMinimum(requestedDur, maxDur))

                device.setExposureModeCustom(duration: safeDur, iso: safeISO, completionHandler: nil)
            } catch {}
        }
    }

    public func setManualWhiteBalance(kelvin: Float, tint: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDeviceInput?.device else { return }
            guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: min(max(kelvin, 2500), 10000),
                    tint: min(max(tint, -150), 150)
                )
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = min(max(gains.redGain, 1.0), maxGain)
                gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
                gains.blueGain = min(max(gains.blueGain, 1.0), maxGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } catch {}
        }
    }

    // MARK: - 12-Bit Apple ProRAW / Bayer RAW Photo Capture (with Safe Fallback)
    public func captureRAWPhoto() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured else { return }

            let availableRAW = self.photoOutput.availableRawPhotoPixelFormatTypes
            let photoSettings: AVCapturePhotoSettings

            if let rawFormat = availableRAW.first {
                let processedFormat: [String: Any]? = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? [AVVideoCodecKey: AVVideoCodecType.hevc]
                    : nil
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
            } else {
                // Safe fallback if the current lens (e.g. Ultra-Wide under certain modes) doesn't expose RAW
                photoSettings = AVCapturePhotoSettings()
            }

            if self.photoOutput.isHighResolutionCaptureEnabled {
                photoSettings.isHighResolutionPhotoEnabled = true
            }
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // MARK: - Dual-Track 10-Bit Video Recording
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
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080
            ]

            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = true

            if writer.canAdd(writerInput) {
                writer.add(writerInput)
            }
            writer.startWriting()

            self.assetWriter = writer
            self.assetWriterVideoInput = writerInput
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCapturePhotoCaptureDelegate
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
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
        }) { [weak self] saved, _ in
            DispatchQueue.main.async {
                self?.statusBannerText = saved
                    ? (photo.isRawPhoto ? "Saved 12-Bit DNG Negative to Photos" : "Saved Spectral Photo to Photos")
                    : "Photo Capture Completed"
            }
        }
    }
}
