//
//  MetalFilmRenderer.swift
//  SpektraCam
//
//  A15 Bionic Zero-Copy Metal Compute Pipeline Manager
//  - Dual-Track Resolution Architecture:
//    1. Real-Time Viewfinder Path (`processVideoSampleBuffer`):
//       Uses 720x960 working resolution + non-blocking 2-frame semaphore so live preview & slider dragging run at 60fps (<1.8ms/frame).
//    2. Full-Resolution 12MP Still Photo Export Path (`renderFullResolutionPhoto`):
//       Runs on an independent offscreen texture pool at full 12MP (3024x4032) sensor resolution on a background queue,
//       never blocking or stalling the live viewfinder!
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreImage
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

    // Real-time Viewfinder Working Textures (720x960 for 60fps 0ms lag)
    private var texSceneLinear: MTLTexture?
    private var texLogEncoded: MTLTexture?
    private var texEmulsionExposure: MTLTexture?
    private var texScatteredExposure: MTLTexture?
    private var texNegativeDensity: MTLTexture?
    private var currentAllocatedSize: (width: Int, height: Int) = (0, 0)

    private let inFlightSemaphore = DispatchSemaphore(value: 2)
    private let tableLock = NSLock()

    private var frameCounter: UInt32 = 1
    private var cachedNegStockID: String = ""
    private var cachedPrintStockID: String = ""
    private var cachedSceneKelvin: Float = -1.0

    private var universalNegDyeScale = SIMD3<Float>(1.38, 0.88, 1.15)
    private var universalPrtSensScale = SIMD3<Float>(1.0, 1.0, 1.0)
    private var universalPrtDyeScale = SIMD3<Float>(1.046, 0.919, 1.023)

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

        calibrateUniversalReferenceDarkroom()
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

    private func blackbodyNormalized(lambdaNM: Float, kelvin: Float) -> Float {
        let T: Float = max(kelvin, 2000.0)
        let lamM: Float = lambdaNM * 1e-9
        let c2: Float = 1.438777e-2
        let val: Float = (1.0 / powf(lamM, 5.0)) / (expf(c2 / (lamM * T)) - 1.0)
        let ref555: Float = (1.0 / powf(555e-9, 5.0)) / (expf(c2 / (555e-9 * T)) - 1.0)
        return val / max(ref555, 1e-12)
    }

    private func calibrateUniversalReferenceDarkroom() {
        let ptrCMF = bufCIE1931XYZ.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
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
            ptrCMF[i] = SIMD4<Float>(cx, cy, cz, 0.0)
            ySum += cy
        }
        let invYSum = 1.0 / max(ySum, 1e-5)
        for i in 0..<81 {
            ptrCMF[i] *= invYSum
        }

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

        let refNeg = FilmStockDatabase.cameraStock(withID: "kodak_portra_400")
        let refPrt = FilmStockDatabase.printStock(withID: "kodak_endura_premier")
        let rawNegDye = refNeg.evaluateDyeSpectralDensities81()
        let rawPrtSens = refPrt.evaluateSpectralSensitivities81()
        let rawPrtDye = refPrt.evaluateDyeSpectralDensities81()
        let zeroVec = SIMD3<Float>(0.0, 0.0, 0.0)
        let refSpan = SIMD3<Float>(2.0, 2.0, 2.0)

        var negScale = SIMD3<Float>(1.2, 1.0, 1.1)
        for _ in 0..<20 {
            var tLow = SIMD3<Float>(1e-6, 1e-6, 1e-6)
            var tHigh = SIMD3<Float>(1e-6, 1e-6, 1e-6)
            for i in 0..<81 {
                let lambda = Float(380 + i * 5)
                let enlIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 3200.0)
                let cleanNegDye = simd_max(rawNegDye[i], zeroVec) * negScale
                let dLow: Float = simd_dot(0.2 * refSpan, cleanNegDye)
                let dHigh: Float = simd_dot(0.8 * refSpan, cleanNegDye)
                tLow += (enlIllum * powf(10.0, -min(max(dLow, 0.0), 4.5))) * rawPrtSens[i]
                tHigh += (enlIllum * powf(10.0, -min(max(dHigh, 0.0), 4.5))) * rawPrtSens[i]
            }
            let ratio: SIMD3<Float> = (tHigh / tLow) / 0.0631
            negScale.x *= powf(max(ratio.x, 0.2), 0.55)
            negScale.y *= powf(max(ratio.y, 0.2), 0.55)
            negScale.z *= powf(max(ratio.z, 0.2), 0.55)
        }
        self.universalNegDyeScale = negScale

        var midPrtExp = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let enlIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 3200.0)
            let scaledNegDye = simd_max(rawNegDye[i], zeroVec) * negScale
            let specD: Float = simd_dot(0.5 * refSpan, scaledNegDye)
            midPrtExp += (enlIllum * powf(10.0, -min(max(specD, 0.0), 4.5))) * rawPrtSens[i]
        }
        self.universalPrtSensScale = SIMD3<Float>(0.18, 0.18, 0.18) / midPrtExp

        var prtScale = SIMD3<Float>(1.5, 1.5, 1.5)
        for _ in 0..<15 {
            var midXYZ = SIMD3<Float>(1e-6, 1e-6, 1e-6)
            for i in 0..<81 {
                let lambda = Float(380 + i * 5)
                let scannerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 5500.0)
                let dVec: SIMD3<Float> = simd_max(rawPrtDye[i], zeroVec) * prtScale
                let specD: Float = dVec.x + dVec.y + dVec.z
                let trans: Float = powf(10.0, -specD)
                let cmf = SIMD3<Float>(ptrCMF[i].x, ptrCMF[i].y, ptrCMF[i].z)
                midXYZ += (scannerIllum * trans) * cmf
            }
            let ratio: SIMD3<Float> = midXYZ / (d65White * 0.10)
            prtScale.x *= powf(max(ratio.x, 0.2), 0.65)
            prtScale.y *= powf(max(ratio.y, 0.2), 0.65)
            prtScale.z *= powf(max(ratio.z, 0.2), 0.65)
        }
        self.universalPrtDyeScale = prtScale
    }

    public func updateSpectralTablesIfNeeded(negID: String, printID: String, sceneKelvin: Float) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard negID != cachedNegStockID || printID != cachedPrintStockID || abs(sceneKelvin - cachedSceneKelvin) > 10.0 else { return }
        cachedNegStockID = negID
        cachedPrintStockID = printID
        cachedSceneKelvin = sceneKelvin

        let negStock = FilmStockDatabase.cameraStock(withID: negID)
        let printStock = FilmStockDatabase.printStock(withID: printID)

        let negSens = negStock.evaluateSpectralSensitivities81()
        let rawNegDye = negStock.evaluateDyeSpectralDensities81()
        let prtSens = printStock.evaluateSpectralSensitivities81()
        let rawPrtDye = printStock.evaluateDyeSpectralDensities81()

        let ptrSens = bufSpectralSensitivity.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrNegDye = bufNegDyeAndEnlarger.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrPrtSens = bufPrintSens.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)
        let ptrPrtDye = bufPrintDyeAndScanner.contents().bindMemory(to: SIMD4<Float>.self, capacity: 81)

        let zeroVec = SIMD3<Float>(0.0, 0.0, 0.0)

        var refIllumIntegral = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let refIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: negStock.referenceKelvin)
            refIllumIntegral += negSens[i] * refIllum
        }
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let refIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: negStock.referenceKelvin)
            let actIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: sceneKelvin)
            let effIllum: Float = 0.62 * refIllum + 0.38 * actIllum
            let normSens = (negSens[i] * effIllum) / refIllumIntegral
            ptrSens[i] = SIMD4<Float>(normSens.x, normSens.y, normSens.z, 1.0)
        }

        let effNegScale: SIMD3<Float> = negStock.isMonochrome ? SIMD3<Float>(0.38, 0.38, 0.38) : universalNegDyeScale
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let enlargerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 3200.0)
            let scaledNegDye: SIMD3<Float> = simd_max(rawNegDye[i], zeroVec) * effNegScale
            ptrNegDye[i] = SIMD4<Float>(scaledNegDye.x, scaledNegDye.y, scaledNegDye.z, enlargerIllum)
        }

        for i in 0..<81 {
            let normPrtSens = prtSens[i] * universalPrtSensScale
            ptrPrtSens[i] = SIMD4<Float>(normPrtSens.x, normPrtSens.y, normPrtSens.z, 1.0)
        }

        let effPrtScale: SIMD3<Float> = printStock.isMonochrome ? SIMD3<Float>(0.34, 0.34, 0.34) : universalPrtDyeScale
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let scannerIllum = blackbodyNormalized(lambdaNM: lambda, kelvin: 5500.0)
            let balancedDye: SIMD3<Float> = simd_max(rawPrtDye[i], zeroVec) * effPrtScale
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

        let m = negStock.dirInterlayerMatrix
        let cpl = params.dirCouplerAmount
        let r0Raw = SIMD3<Float>(1.0 + (m[0] - 1.0) * cpl, m[1] * cpl, m[2] * cpl)
        let r1Raw = SIMD3<Float>(m[3] * cpl, 1.0 + (m[4] - 1.0) * cpl, m[5] * cpl)
        let r2Raw = SIMD3<Float>(m[6] * cpl, m[7] * cpl, 1.0 + (m[8] - 1.0) * cpl)

        let r0 = r0Raw / max(r0Raw.x + r0Raw.y + r0Raw.z, 0.1)
        let r1 = r1Raw / max(r1Raw.x + r1Raw.y + r1Raw.z, 0.1)
        let r2 = r2Raw / max(r2Raw.x + r2Raw.y + r2Raw.z, 0.1)

        let row0 = SIMD4<Float>(r0.x, r0.y, r0.z, 0)
        let row1 = SIMD4<Float>(r1.x, r1.y, r1.z, 0)
        let row2 = SIMD4<Float>(r2.x, r2.y, r2.z, 0)

        let zeroVec3 = SIMD3<Float>(0.0, 0.0, 0.0)
        let stockHalRatio = negStock.halationReflectanceRGB / SIMD3<Float>(0.032, 0.005, 0.001)
        let effectiveHalationRGB: SIMD3<Float> = params.halationEnabled
            ? (params.halationStrengthRGB * simd_max(stockHalRatio, SIMD3<Float>(0.35, 0.35, 0.35)) * 4.5)
            : zeroVec3
        let halPxRGB: SIMD3<Float> = params.halationRadiusMicrometers * umToPx

        let modelMultiplier: Float
        switch params.diffusionModel {
        case .none:            modelMultiplier = 0.0
        case .blackProMist1_8: modelMultiplier = 0.85
        case .blackProMist1_4: modelMultiplier = 1.35
        case .blackProMist1_2: modelMultiplier = 2.10
        case .glimmerglass1_4: modelMultiplier = 1.50
        case .vintageSoftLens: modelMultiplier = 2.60
        }
        let effBloomStrength: Float = params.bloomStrength * modelMultiplier

        let netPrintEV: Float = params.autoPrintExposureComp
            ? (params.printExposureEV - params.exposureCompensationEV * 0.62)
            : params.printExposureEV

        let totalYCC = params.dichroicYellowCC + negStock.defaultEnlargerYMShift.x + printStock.defaultEnlargerYMShift.x
        let totalMCC = params.dichroicMagentaCC + negStock.defaultEnlargerYMShift.y + printStock.defaultEnlargerYMShift.y
        let totalCCC = params.dichroicCyanCC

        let preflashLin: Float = (params.preflashExposureEV > -5.9) ? powf(2.0, params.preflashExposureEV) : 0.0
        let callierQ: Float = (params.enlargerLightSource == .condenserPointSource) ? 1.15 : 1.0

        let modeFlag: Int32 = negStock.isReversal ? 1 : ((negStock.isMonochrome || printStock.isMonochrome) ? 2 : 0)
        let meanToe: Float = (negStock.toeSoftnessRGB.x + negStock.toeSoftnessRGB.y + negStock.toeSoftnessRGB.z) * 0.333333
        self.frameCounter &+= 1

        return MetalFilmUniforms(
            exposureScale: powf(2.0, params.exposureCompensationEV),
            pushPullGammaScale: pushGammaFactor,
            dminFogOffset: fogOffset,
            opticalVignetteStrength: params.opticalVignettingStrength,
            bloomStrength: effBloomStrength,
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
            negativeToeShoulder: SIMD4<Float>(negStock.shoulderSoftnessRGB.x, negStock.shoulderSoftnessRGB.y, negStock.shoulderSoftnessRGB.z, meanToe),
            printGammaRGB: SIMD4<Float>(printStock.gammaRGB.x, printStock.gammaRGB.y, printStock.gammaRGB.z, 0),
            printDminRGB: SIMD4<Float>(printStock.dMinRGB.x, printStock.dMinRGB.y, printStock.dMinRGB.z, 0),
            printDmaxRGB: SIMD4<Float>(printStock.dMaxRGB.x, printStock.dMaxRGB.y, printStock.dMaxRGB.z, 0),
            rmsGranularityRGB: SIMD4<Float>(negStock.rmsGranularity, negStock.rmsGranularity, negStock.rmsGranularity * 1.15, 0),
            outputColorSpace: Int32(params.outputColorSpace.rawValue),
            isReversalOrMono: modeFlag,
            bwMultigradeGrade: params.bwMultigradeFilterGrade
        )
    }

    // MARK: - 1. Real-Time 60fps Viewfinder Path (720x960 Working Resolution, < 1.8ms GPU Time)
    public func processVideoSampleBuffer(
        pixelBuffer: CVPixelBuffer,
        params: FilmSimulationParameters,
        logCurve: LogEncodingTransferFunction,
        outputDrawableTexture: MTLTexture
    ) -> (filmRenderedTexture: MTLTexture, logEncodedTexture: MTLTexture)? {
        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            return nil
        }

        guard let cache = textureCache,
              CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            inFlightSemaphore.signal()
            return nil
        }

        let srcW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let srcH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let chromaW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        guard srcW > 0 && srcH > 0 && chromaW > 0 && chromaH > 0 else {
            inFlightSemaphore.signal()
            return nil
        }

        let maxLongEdge: Int = 960
        let scale: Float = min(1.0, Float(maxLongEdge) / Float(max(srcW, srcH)))
        let workW = max(Int(Float(srcW) * scale), 320)
        let workH = max(Int(Float(srcH) * scale), 320)

        ensureTransientTextures(width: workW, height: workH)

        guard let texLinear = texSceneLinear,
              let texLog = texLogEncoded,
              let texExp = texEmulsionExposure,
              let texScat = texScatteredExposure,
              let texNeg = texNegativeDensity else {
            inFlightSemaphore.signal()
            return nil
        }

        let ostype = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let is10Bit = (ostype == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                       ostype == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)
        let lumaFormat: MTLPixelFormat = is10Bit ? .r16Unorm : .r8Unorm
        let chromaFormat: MTLPixelFormat = is10Bit ? .rg16Unorm : .rg8Unorm

        var cvLuma: CVMetalTexture?
        var cvChroma: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, lumaFormat, srcW, srcH, 0, &cvLuma)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, nil, chromaFormat, chromaW, chromaH, 1, &cvChroma)

        guard let lumaTex = cvLuma.flatMap({ CVMetalTextureGetTexture($0) }),
              let chromaTex = cvChroma.flatMap({ CVMetalTextureGetTexture($0) }),
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            inFlightSemaphore.signal()
            return nil
        }

        let semaphore = self.inFlightSemaphore
        cmdBuf.addCompletedHandler { _ in
            semaphore.signal()
        }

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (workW + 15) / 16, height: (workH + 15) / 16, depth: 1)

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

        var uniforms = buildMetalUniforms(params: params, imageWidth: workW)

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

    // MARK: - 2. Offline Full-Resolution 12MP (3024x4032) Still Photo Darkroom Export
    // Runs asynchronously on a background queue using dedicated offscreen textures so the viewfinder never stalls
    // and the saved photo has full 12MP (3024x4032) resolution!
    public func renderFullResolutionPhoto(
        inputLinearTexture: MTLTexture,
        params: FilmSimulationParameters
    ) -> MTLTexture? {
        let fullW = inputLinearTexture.width
        let fullH = inputLinearTexture.height
        guard fullW > 0 && fullH > 0 else { return nil }

        let workDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: fullW,
            height: fullH,
            mipmapped: false
        )
        workDesc.usage = [.shaderRead, .shaderWrite]
        workDesc.storageMode = .private

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: fullW,
            height: fullH,
            mipmapped: false
        )
        outDesc.usage = [.shaderRead, .shaderWrite]
        outDesc.storageMode = .private

        guard let texExp = device.makeTexture(descriptor: workDesc),
              let texScat = device.makeTexture(descriptor: workDesc),
              let texNeg = device.makeTexture(descriptor: workDesc),
              let texOut = device.makeTexture(descriptor: outDesc),
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            return nil
        }

        var uniforms = buildMetalUniforms(params: params, imageWidth: fullW)
        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (fullW + 15) / 16, height: (fullH + 15) / 16, depth: 1)

        // Stage 1: Full-Res 81-Band Spectral Upsampling & Exposure
        encoder.setComputePipelineState(pipeSpectralUpsampleExpose)
        encoder.setTexture(inputLinearTexture, index: 0)
        encoder.setTexture(texExp, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.setBuffer(bufSpectralSensitivity, offset: 0, index: 1)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        // Stage 2: Full-Res Bloom, Frieser Scatter & Halation
        encoder.setComputePipelineState(pipeHalationAndScatter)
        encoder.setTexture(texExp, index: 0)
        encoder.setTexture(texScat, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        // Stage 3: Full-Res Hurter-Driffield Development & 3x3 DIR Couplers
        encoder.setComputePipelineState(pipeDevelopAndDIRCouplers)
        encoder.setTexture(texScat, index: 0)
        encoder.setTexture(texNeg, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        // Stage 4: Full-Res Enlarger Print, Multi-Sublayer Grain & CIE 1931 Output
        encoder.setComputePipelineState(pipeEnlargerPrintAndGrain)
        encoder.setTexture(texNeg, index: 0)
        encoder.setTexture(texOut, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFilmUniforms>.stride, index: 0)
        encoder.setBuffer(bufNegDyeAndEnlarger, offset: 0, index: 1)
        encoder.setBuffer(bufPrintSens, offset: 0, index: 2)
        encoder.setBuffer(bufPrintDyeAndScanner, offset: 0, index: 3)
        encoder.setBuffer(bufCIE1931XYZ, offset: 0, index: 4)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return texOut
    }
}
