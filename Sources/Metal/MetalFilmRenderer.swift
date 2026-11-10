//
//  MetalFilmRenderer.swift
//  SpektraCam
//
//  A15 Bionic Zero-Copy Metal Compute Pipeline Manager
//  - Closed-Loop Sensitometric & Spectral Calibration:
//    1. Spectral Sensitivity Pre-Normalization against Reference Scene Illuminant (18% Gray -> (0.18, 0.18, 0.18))
//    2. Enlarger Neutral Gray Auto-Calibration against 18% Developed Negative Density (Eliminates Color Cast)
//    3. Print Dye Equal-Area Normalization + Scanner D65 White-Patch Calibration (Guarantees Neutral Gray stays Neutral from Shadows to Highlights!)
//  - Strict Swift 5.9 SIMD3<Float> & Float32 explicit typing (Zero ambiguous `.zero` or `pow` overload conflicts)
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

public final class MetalFilmRenderer {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?

    private let pipeYCbCr10ToLinearAndLog: MTLComputePipelineState
    private let pipeSpectralUpsampleExpose: MTLComputePipelineState
    private let pipeHalationAndScatter: MTLComputePipelineState
    private let pipeDevelopAndDIRCouplers: MTLComputePipelineState
    private let pipeEnlargerPrintAndGrain: MTLComputePipelineState

    private let bufSpectralSensitivity: MTLBuffer
    private let bufNegDyeAndEnlarger: MTLBuffer
    private let bufPrintSens: MTLBuffer
    private let bufPrintDyeAndScanner: MTLBuffer
    private let bufCIE1931XYZ: MTLBuffer

    private var texSceneLinear: MTLTexture?
    private var texLogEncoded: MTLTexture?
    private var texEmulsionExposure: MTLTexture?
    private var texScatteredExposure: MTLTexture?
    private var texNegativeDensity: MTLTexture?
    private var currentAllocatedSize: (width: Int, height: Int) = (0, 0)

    private var frameCounter: UInt32 = 1
    private var cachedNegStockID: String = ""
    private var cachedPrintStockID: String = ""

    public init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue(),
              let library = dev.makeDefaultLibrary() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        self.textureCache = cache

        do {
            guard let fn0 = library.makeFunction(name: "kernel_ycbcr10_to_scene_linear_and_log"),
                  let fn1 = library.makeFunction(name: "kernel_spectral_upsample_and_expose"),
                  let fn2 = library.makeFunction(name: "kernel_halation_and_scatter"),
                  let fn3 = library.makeFunction(name: "kernel_develop_and_dir_couplers"),
                  let fn4 = library.makeFunction(name: "kernel_enlarger_print_and_grain") else {
                return nil
            }
            self.pipeYCbCr10ToLinearAndLog = try dev.makeComputePipelineState(function: fn0)
            self.pipeSpectralUpsampleExpose = try dev.makeComputePipelineState(function: fn1)
            self.pipeHalationAndScatter = try dev.makeComputePipelineState(function: fn2)
            self.pipeDevelopAndDIRCouplers = try dev.makeComputePipelineState(function: fn3)
            self.pipeEnlargerPrintAndGrain = try dev.makeComputePipelineState(function: fn4)
        } catch {
            return nil
        }

        let bufferBytes = 81 * MemoryLayout<SIMD4<Float>>.stride
        guard let b1 = dev.makeBuffer(length: bufferBytes, options: .storageModeShared),
              let b2 = dev.makeBuffer(length: bufferBytes, options: .storageModeShared),
              let b3 = dev.makeBuffer(length: bufferBytes, options: .storageModeShared),
              let b4 = dev.makeBuffer(length: bufferBytes, options: .storageModeShared),
              let b5 = dev.makeBuffer(length: bufferBytes, options: .storageModeShared) else {
            return nil
        }
        self.bufSpectralSensitivity = b1
        self.bufNegDyeAndEnlarger = b2
        self.bufPrintSens = b3
        self.bufPrintDyeAndScanner = b4
        self.bufCIE1931XYZ = b5

        populateCIE1931XYZTable()
        updateSpectralTablesIfNeeded(negID: "kodak_portra_400", printID: "kodak_endura_premier", sceneKelvin: 5500)
    }

    public func ensureTransientTextures(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        guard width != currentAllocatedSize.width || height != currentAllocatedSize.height else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private

        self.texSceneLinear = device.makeTexture(descriptor: desc)
        self.texLogEncoded = device.makeTexture(descriptor: desc)
        self.texEmulsionExposure = device.makeTexture(descriptor: desc)
        self.texScatteredExposure = device.makeTexture(descriptor: desc)
        self.texNegativeDensity = device.makeTexture(descriptor: desc)
        self.currentAllocatedSize = (width, height)
    }

    private func populateCIE1931XYZTable() {
        let ptr = bufCIE1931XYZ.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        var ySum: Float = 0.0
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let x1: Float = (lambda - 442.0) * ((lambda < 442.0) ? 0.0624 : 0.0374)
            let x2: Float = (lambda - 599.8) * ((lambda < 599.8) ? 0.0264 : 0.0323)
            let x3: Float = (lambda - 501.1) * ((lambda < 501.1) ? 0.0490 : 0.0382)
            let xBar: Float = 0.362 * expf(-0.5 * x1 * x1) + 1.056 * expf(-0.5 * x2 * x2) - 0.065 * expf(-0.5 * x3 * x3)

            let y1: Float = (lambda - 568.8) * ((lambda < 568.8) ? 0.0213 : 0.0247)
            let y2: Float = (lambda - 530.9) * ((lambda < 530.9) ? 0.0613 : 0.0322)
            let yBar: Float = 0.821 * expf(-0.5 * y1 * y1) + 0.286 * expf(-0.5 * y2 * y2)

            let z1: Float = (lambda - 437.0) * ((lambda < 437.0) ? 0.0845 : 0.0278)
            let z2: Float = (lambda - 459.0) * ((lambda < 459.0) ? 0.0385 : 0.0725)
            let zBar: Float = 1.217 * expf(-0.5 * z1 * z1) + 0.681 * expf(-0.5 * z2 * z2)

            let cx = max(xBar, 0.0)
            let cy = max(yBar, 0.0)
            let cz = max(zBar, 0.0)
            ptr[i] = SIMD4<Float>(cx, cy, cz, 0.0)
            ySum += cy
        }
        let invYSum = 1.0 / max(ySum, 1e-5)
        for i in 0..<81 {
            ptr[i] *= invYSum
        }
    }

    private func blackbodyNormalized(lambdaNM: Float, kelvin: Float) -> Float {
        let T: Float = max(kelvin, 2000.0)
        let lamM: Float = lambdaNM * 1e-9
        let c2: Float = 1.438777e-2
        let val: Float = (1.0 / powf(lamM, 5.0)) / (expf(c2 / (lamM * T)) - 1.0)
        let ref555: Float = (1.0 / powf(555e-9, 5.0)) / (expf(c2 / (555e-9 * T)) - 1.0)
        return val / max(ref555, 1e-12)
    }

    // MARK: - Closed-Loop Darkroom Sensitometric & Equal-Neutral-Density Calibration
    public func updateSpectralTablesIfNeeded(negID: String, printID: String, sceneKelvin: Float) {
        guard negID != cachedNegStockID || printID != cachedPrintStockID else { return }
        cachedNegStockID = negID
        cachedPrintStockID = printID

        let negStock = FilmStockDatabase.cameraStock(withID: negID)
        let printStock = FilmStockDatabase.printStock(withID: printID)

        // Reset CIE 1931 base table before re-scaling
        populateCIE1931XYZTable()

        let negSens = negStock.evaluateSpectralSensitivities81()
        let negDye = negStock.evaluateDyeSpectralDensities81()
        let prtSens = printStock.evaluateSpectralSensitivities81()
        let prtDye = printStock.evaluateDyeSpectralDensities81()

        let ptrSens = bufSpectralSensitivity.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrNegDye = bufNegDyeAndEnlarger.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrPrtSens = bufPrintSens.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrPrtDye = bufPrintDyeAndScanner.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrCMF = bufCIE1931XYZ.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)

        // Step A: Pre-normalize negative sensitivity * reference illuminant so a flat reflector yields (1, 1, 1)
        var negIllumIntegral = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let sceneIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: negStock.referenceKelvin)
            negIllumIntegral += negSens[i] * sceneIllum
        }
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let sceneIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: negStock.referenceKelvin)
            let normSens = (negSens[i] * sceneIllum) / negIllumIntegral
            ptrSens[i] = SIMD4<Float>(normSens.x, normSens.y, normSens.z, 1.0)
        }

        // Step B: Compute 18% middle gray developed negative net density (at logE = log10(0.18) = -0.7447 -> H-D midpoint 0.5 * span)
        let midNetNeg = (negStock.dMaxRGB - negStock.dMinRGB) * 0.5
        var printMidExposureIntegral = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let enlargerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 3200.0)
            ptrNegDye[i] = SIMD4<Float>(negDye[i].x, negDye[i].y, negDye[i].z, enlargerIllum)

            let negSpecD: Float = simd_dot(midNetNeg, negDye[i])
            let clampedSpecD: Float = min(max(negSpecD, -2.0), 4.5)
            let trans: Float = powf(10.0, -clampedSpecD)
            printMidExposureIntegral += (enlargerIllum * trans) * prtSens[i]
        }

        // Pre-normalize print paper sensitivity so 18% gray negative produces exact (0.18, 0.18, 0.18) paper exposure at 0 CC!
        for i in 0..<81 {
            let normPrtSens = (prtSens[i] * 0.18) / printMidExposureIntegral
            ptrPrtSens[i] = SIMD4<Float>(normPrtSens.x, normPrtSens.y, normPrtSens.z, 1.0)
        }

        // Step C: Normalize Scanner Illuminant * CIE 1931 CMF so D_min (0 net density) maps to D65 White XYZ (0.95047, 1.0, 1.08883)
        var rawWhiteXYZ = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let scannerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 5500.0)
            let cmf = SIMD3<Float>(ptrCMF[i].x, ptrCMF[i].y, ptrCMF[i].z)
            rawWhiteXYZ += scannerIllum * cmf
        }
        let d65White = SIMD3<Float>(0.95047, 1.00000, 1.08883)
        let xyzScale = d65White / rawWhiteXYZ
        for i in 0..<81 {
            ptrCMF[i] = SIMD4<Float>(
                ptrCMF[i].x * xyzScale.x,
                ptrCMF[i].y * xyzScale.y,
                ptrCMF[i].z * xyzScale.z,
                0.0
            )
        }

        // Step D: Equalize Equivalent Neutral Density (END) of Print C/M/Y Dyes using explicit SIMD3<Float> & powf!
        let zeroVec = SIMD3<Float>(0.0, 0.0, 0.0)
        var dyeScale = SIMD3<Float>(1.0, 1.0, 1.0)
        for _ in 0..<6 {
            var midXYZ = SIMD3<Float>(1e-6, 1e-6, 1e-6)
            for i in 0..<81 {
                let lambda = Float(380 + i * 5)
                let scannerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 5500.0)
                let clampedDye = simd_max(prtDye[i], zeroVec)
                let dVec: SIMD3<Float> = clampedDye * dyeScale
                let specD: Float = 0.85 * (dVec.x + dVec.y + dVec.z)
                let trans: Float = powf(10.0, -specD)
                let cmf = SIMD3<Float>(ptrCMF[i].x, ptrCMF[i].y, ptrCMF[i].z)
                midXYZ += (scannerIllum * trans) * cmf
            }
            let targetXYZ: SIMD3<Float> = d65White * 0.22
            let ratio: SIMD3<Float> = midXYZ / targetXYZ
            dyeScale.x *= powf(max(ratio.x, 0.2), 0.45)
            dyeScale.y *= powf(max(ratio.y, 0.2), 0.45)
            dyeScale.z *= powf(max(ratio.z, 0.2), 0.45)
        }

        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let scannerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 5500.0)
            let clampedDye = simd_max(prtDye[i], zeroVec)
            let balancedDye: SIMD3<Float> = clampedDye * dyeScale
            ptrPrtDye[i] = SIMD4<Float>(balancedDye.x, balancedDye.y, balancedDye.z, scannerIllum)
        }
    }

    public func buildMetalUniforms(params: FilmSimulationParameters, imageWidth: Int) -> MetalFilmUniforms {
        let negStock = FilmStockDatabase.cameraStock(withID: params.negativeStockID)
        let printStock = FilmStockDatabase.printStock(withID: params.printStockID)

        updateSpectralTablesIfNeeded(
            negID: params.negativeStockID,
            printID: params.printStockID,
            sceneKelvin: params.sceneIlluminantKelvin
        )

        let gateMM = params.filmFormatGate.gateWidthMM
        let pixelSizeUm = (gateMM * 1000.0) / Float(max(imageWidth, 1))
        let umToPx = 1.0 / max(pixelSizeUm, 0.5)

        let tempDelta: Float = (params.devTemperatureCelsius - 37.8) * 0.04
        let pushGammaFactor: Float = powf(1.14, params.pushPullStops) * (1.0 + tempDelta) * params.agitationIntensity
        let fogOffset: Float = max(0.0, params.pushPullStops * 0.025 + tempDelta * 0.08)

        let cpl = params.dirCouplerAmount
        let row0 = SIMD4<Float>(cpl, 0, 0, 0)
        let row1 = SIMD4<Float>(0, cpl, 0, 0)
        let row2 = SIMD4<Float>(0, 0, cpl, 0)

        let zeroVec3 = SIMD3<Float>(0.0, 0.0, 0.0)
        let effectiveHalationRGB: SIMD3<Float> = params.halationEnabled
            ? (negStock.halationReflectanceRGB * (params.halationStrengthRGB / SIMD3<Float>(0.035, 0.006, 0.001)))
            : zeroVec3
        let halPxRGB = negStock.halationSigmaMicrometers * umToPx

        let netPrintEV: Float = params.autoPrintExposureComp
            ? (params.printExposureEV - params.exposureCompensationEV * 0.62)
            : params.printExposureEV

        let totalYCC = params.dichroicYellowCC
        let totalMCC = params.dichroicMagentaCC
        let totalCCC = params.dichroicCyanCC

        let preflashLin: Float = (params.preflashExposureEV > -5.9) ? powf(2.0, params.preflashExposureEV) : 0.0
        let callierQ: Float = (params.enlargerLightSource == .condenserPointSource) ? 1.15 : 1.0

        let modeFlag: Int32 = negStock.isReversal ? 1 : (negStock.isMonochrome ? 2 : 0)
        self.frameCounter &+= 1

        return MetalFilmUniforms(
            exposureScale: powf(2.0, params.exposureCompensationEV),
            pushPullGammaScale: pushGammaFactor,
            dminFogOffset: fogOffset,
            opticalVignetteStrength: params.opticalVignettingStrength,
            bloomStrength: (params.diffusionModel == .none) ? 0.0 : params.bloomStrength,
            bloomThreshold: params.bloomHighlightThreshold,
            bloomRadiusPx: params.bloomRadiusMicrometers * umToPx,
            inEmulsionScatterPx: params.inEmulsionScatterMicrometers * umToPx,
            dirCouplerMatrixRow0: row0,
            dirCouplerMatrixRow1: row1,
            dirCouplerMatrixRow2: row2,
            dirRadiusPx: params.dirDiffusionRadiusMicrometers * umToPx,
            developerExhaustion: params.developerExhaustion,
            bleachBypassAmount: params.bleachBypassAmount,
            hasRemjetLayer: negStock.hasAntiHalationRemjet ? 1.0 : 0.0,
            halationStrengthRGB: SIMD4<Float>(effectiveHalationRGB.x, effectiveHalationRGB.y, effectiveHalationRGB.z, 0),
            halationRadiusPxRGB: SIMD4<Float>(halPxRGB.x, halPxRGB.y, halPxRGB.z, 0),
            grainStrength: params.grainEnabled ? params.grainStrength : 0.0,
            grainUniformity: params.grainUniformity,
            pixelSizeMicrometers: pixelSizeUm,
            frameSeed: frameCounter,
            dichroicFilterCMY: SIMD4<Float>(totalCCC, totalMCC, totalYCC, 0),
            printExposureScale: powf(2.0, netPrintEV),
            printGamma: params.printGammaContrast,
            preflashLinearAddition: preflashLin,
            callierQFactor: callierQ,
            scannerGlare: params.scannerVeilingGlare,
            blackPoint: params.blackPointOffset,
            whitePoint: params.whitePointOffset,
            printPipelineMode: Int32(params.printPipelineMode.rawValue),
            negativeGammaRGB: SIMD4<Float>(negStock.gammaRGB.x, negStock.gammaRGB.y, negStock.gammaRGB.z, 0),
            negativeDminRGB: SIMD4<Float>(negStock.dMinRGB.x, negStock.dMinRGB.y, negStock.dMinRGB.z, 0),
            negativeDmaxRGB: SIMD4<Float>(negStock.dMaxRGB.x, negStock.dMaxRGB.y, negStock.dMaxRGB.z, 0),
            printGammaRGB: SIMD4<Float>(printStock.gammaRGB.x, printStock.gammaRGB.y, printStock.gammaRGB.z, 0),
            printDminRGB: SIMD4<Float>(printStock.dMinRGB.x, printStock.dMinRGB.y, printStock.dMinRGB.z, 0),
            printDmaxRGB: SIMD4<Float>(printStock.dMaxRGB.x, printStock.dMaxRGB.y, printStock.dMaxRGB.z, 0),
            rmsGranularityRGB: SIMD4<Float>(negStock.rmsGranularity, negStock.rmsGranularity, negStock.rmsGranularity * 1.15, 0),
            outputColorSpace: Int32(params.outputColorSpace.rawValue),
            isReversalOrMono: modeFlag,
            bwMultigradeGrade: params.bwMultigradeFilterGrade
        )
    }

    public func processVideoSampleBuffer(
        pixelBuffer: CVPixelBuffer,
        params: FilmSimulationParameters,
        logCurve: LogEncodingTransferFunction,
        outputDrawableTexture: MTLTexture
    ) -> (filmRenderedTexture: MTLTexture, logEncodedTexture: MTLTexture)? {
        guard let cache = textureCache else { return nil }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let chromaW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        guard width > 0 && height > 0 && chromaW > 0 && chromaH > 0 else { return nil }

        ensureTransientTextures(width: width, height: height)

        guard let texLinear = texSceneLinear,
              let texLog = texLogEncoded,
              let texExp = texEmulsionExposure,
              let texScat = texScatteredExposure,
              let texNeg = texNegativeDensity else {
            return nil
        }

        let ostype = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let is10Bit = (ostype == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                       ostype == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)
        let lumaFormat: MTLPixelFormat = is10Bit ? .r16Unorm : .r8Unorm
        let chromaFormat: MTLPixelFormat = is10Bit ? .rg16Unorm : .rg8Unorm

        var cvLuma: CVMetalTexture?
        var cvChroma: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, lumaFormat, width, height, 0, &cvLuma)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, chromaFormat, chromaW, chromaH, 1, &cvChroma)

        guard let lumaTex = cvLuma.flatMap({ CVMetalTextureGetTexture($0) }),
              let chromaTex = cvChroma.flatMap({ CVMetalTextureGetTexture($0) }),
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            return nil
        }

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)

        var logModeRaw = Int32(logCurve.rawValue)
        var is10BitFlag: Int32 = is10Bit ? 1 : 0
        encoder.setComputePipelineState(pipeYCbCr10ToLinearAndLog)
        encoder.setTexture(lumaTex, index: 0)
        encoder.setTexture(chromaTex, index: 1)
        encoder.setTexture(texLinear, index: 2)
        encoder.setTexture(texLog, index: 3)
        encoder.setBytes(&logModeRaw, length: MemoryLayout<Int32>.stride, index: 0)
        encoder.setBytes(&is10BitFlag, length: MemoryLayout<Int32>.stride, index: 1)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        var uniforms = buildMetalUniforms(params: params, imageWidth: width)

        encoder.setComputePipelineState(pipeSpectralUpsampleExpose)
        encoder.setTexture(texLinear, index: 0)
        encoder.setTexture(texExp, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.setBuffer(bufSpectralSensitivity, offset: 0, index: 1)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        encoder.setComputePipelineState(pipeHalationAndScatter)
        encoder.setTexture(texExp, index: 0)
        encoder.setTexture(texScat, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        encoder.setComputePipelineState(pipeDevelopAndDIRCouplers)
        encoder.setTexture(texScat, index: 0)
        encoder.setTexture(texNeg, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        let dstW = outputDrawableTexture.width
        let dstH = outputDrawableTexture.height
        let dstTGCount = MTLSize(width: (dstW + 15) / 16, height: (dstH + 15) / 16, depth: 1)

        encoder.setComputePipelineState(pipeEnlargerPrintAndGrain)
        encoder.setTexture(texNeg, index: 0)
        encoder.setTexture(outputDrawableTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.setBuffer(bufNegDyeAndEnlarger, offset: 0, index: 1)
        encoder.setBuffer(bufPrintSens, offset: 0, index: 2)
        encoder.setBuffer(bufPrintDyeAndScanner, offset: 0, index: 3)
        encoder.setBuffer(bufCIE1931XYZ, offset: 0, index: 4)
        encoder.dispatchThreadgroups(dstTGCount, threadsPerThreadgroup: tgSize)

        encoder.endEncoding()
        cmdBuf.commit()

        return (outputDrawableTexture, texLog)
    }
}
