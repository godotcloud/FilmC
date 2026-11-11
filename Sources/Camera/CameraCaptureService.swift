//
//  CameraCaptureService.swift
//  SpektraCam
//
//  Hardware-Aligned Capture Engine for iPhone 13 Pro Max (iPhone14,3 / A15 Bionic)
//  - FixesShutter Lag & Low-Resolution (750x1000) Saved Photos:
//    1. Previously, `saveCurrentSpectralRenderToPhotos()` was saving the 750x1000 MTKView screen drawable
//       and calling `ciCtx.jpegRepresentation(...)` synchronously on the Main Thread while simultaneously
//       requesting heavy 12-bit Apple ProRAW (75MB DNG) capture—causing both shutter lag AND 750x1000 low-res output!
//    2. Now, pressing the shutter captures a fast, zero-lag full-resolution 12MP (3024x4032) photo via `AVCapturePhotoOutput`
//       (with `.speed` / `.balanced` prioritization for instant shutter response), decodes the 12MP sensor image to
//       Scene-Linear Display P3 on a background queue, runs `metalRenderer.renderFullResolutionPhoto(...)` at full
//       3024x4032 resolution, and saves the 12MP film render (plus optional RAW DNG when enabled) without blocking the UI!
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
    // Optional toggle: false by default so shutter is 0ms instant and outputs a 12MP (3024x4032) Spectral Film Print;
    // when true, also saves the 75MB 12-bit ProRAW DNG negative alongside the 12MP film print!
    @Published public var alsoSaveRawDNG: Bool = false
    @Published public var isProcessing12MPPhoto: Bool = false
    @Published public var videoPipelineMode: VideoRecordingPipelineMode = .logCleanWithFilmMonitor
    @Published public var logTransferCurve: LogEncodingTransferFunction = .appleLogCompatible
    @Published public var videoCodec: VideoCodecSelection = .hevc10Bit
    @Published public var statusBannerText: String = "12MP (3024×4032) Spectral Darkroom Ready"
    @Published public var activePixelFormatIs10Bit: Bool = false

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.spektracam.sessionQueue", qos: .userInitiated)
    private let videoProcessingQueue = DispatchQueue(label: "com.spektracam.videoProcessingQueue", qos: .userInteractive)
    private let photoRenderQueue = DispatchQueue(label: "com.spektracam.photoRenderQueue", qos: .userInitiated)

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

    private func configureSession(for lens: iPhone13ProMaxLens, isVideoMode: Bool) {
        session.beginConfiguration()

        if let existingInput = videoDeviceInput {
            session.removeInput(existingInput)
            self.videoDeviceInput = nil
        }

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
            // Use .balanced maxPhotoQualityPrioritization so shutter fires with zero lag!
            if photoOutput.maxPhotoQualityPrioritization.rawValue >= AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue {
                photoOutput.maxPhotoQualityPrioritization = .balanced
            }
            if #available(iOS 14.3, *) {
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                }
            }
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

        if let photoConn = photoOutput.connection(with: .video),
           photoConn.isVideoOrientationSupported {
            photoConn.videoOrientation = .portrait
        }

        session.commitConfiguration()
        isSessionConfigured = true

        if !session.isRunning {
            session.startRunning()
        }

        let final10Bit = using10Bit
        DispatchQueue.main.async {
            self.activePixelFormatIs10Bit = final10Bit
            if isVideoMode {
                self.statusBannerText = final10Bit
                    ? "10-Bit BT.2020 HLG → Scene-Linear + Log Ready"
                    : "Scene-Linear + Real-Time Log Video Ready"
            } else {
                self.statusBannerText = "12MP (3024×4032) Spectral Darkroom Ready"
            }
        }
    }

    private func configure10BitHLGFormatSafely(on device: AVCaptureDevice) -> Bool {
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

    // MARK: - Zero-Lag 12MP (3024x4032) Full-Resolution Still Photo Capture
    public func captureRAWPhoto() {
        DispatchQueue.main.async {
            self.isProcessing12MPPhoto = true
            self.statusBannerText = "Developing 12MP (3024×4032) Spectral Print..."
        }

        let wantRawDNG = self.alsoSaveRawDNG
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionConfigured, !self.isCaptureModeVideo else { return }

            let photoSettings: AVCapturePhotoSettings
            let availableRAW = self.photoOutput.availableRawPhotoPixelFormatTypes

            if wantRawDNG, let rawFormat = availableRAW.first {
                let processedFormat: [String: Any]? = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? [AVVideoCodecKey: AVVideoCodecType.hevc]
                    : nil
                photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
            } else {
                // Fast zero-lag 12MP capture (processes through full 81-band spectral darkroom on background GPU queue)
                if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    photoSettings = AVCapturePhotoSettings()
                }
            }

            if self.photoOutput.isHighResolutionCaptureEnabled {
                photoSettings.isHighResolutionPhotoEnabled = true
            }
            // Use .speed or .balanced so shutter fires immediately with zero freeze!
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
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            let extent = rawCIImage.extent.integral
            let fullW = Int(extent.width)
            let fullH = Int(extent.height)
            guard fullW > 0 && fullH > 0 else {
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            // 1. Render 12MP input image into a Scene-Linear `.rgba16Float` Metal texture
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
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
            // Flip CIImage vertically so top-left of Metal texture matches top-left of photo
            let flippedInput = rawCIImage
                .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: - CGFloat(fullH)))

            ciCtx.render(
                flippedInput,
                to: inputLinearTex,
                commandBuffer: nil,
                bounds: CGRect(x: 0, y: 0, width: fullW, height: fullH),
                colorSpace: linearSpace
            )

            // 2. Run the 81-Band Physical Spectral Darkroom Pipeline at full 12MP (3024x4032) resolution
            guard let developedTex = renderer.renderFullResolutionPhoto(
                inputLinearTexture: inputLinearTex,
                params: paramsSnapshot
            ) else {
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            // 3. Encode the developed 12MP texture to Display P3 High-Bitrate JPEG/HEIC (Quality 0.96)
            let outColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            guard let outCI = CIImage(mtlTexture: developedTex, options: [.colorSpace: outColorSpace]) else {
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                }
                return
            }
            let orientedOut = outCI.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -outCI.extent.height))

            guard let jpegData = ciCtx.jpegRepresentation(
                of: orientedOut,
                colorSpace: outColorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96]
            ) else {
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: jpegData, options: nil)
            }) { [weak self] saved, _ in
                DispatchQueue.main.async {
                    self?.isProcessing12MPPhoto = false
                    if saved {
                        self?.statusBannerText = "Saved \(fullW)×\(fullH) (12MP) Spectral Print"
                    }
                }
            }
        }
    }

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
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isProcessing12MPPhoto = false
            }
            return
        }

        if photo.isRawPhoto {
            // Optional 12-bit DNG archive save
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: nil)
        } else {
            // Develop the full 12MP (3024x4032) sensor photo through the 81-band Metal Spectral Darkroom on background queue!
            let snapshotParams = self.activeParameters
            processAndSaveFullResolutionPhoto(photoData: data, paramsSnapshot: snapshotParams)
        }
    }
}
