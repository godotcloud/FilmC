//
//  FilmStockParameters.swift
//  SpektraCam
//
//  Physical Sensitometry, Dye Spectral Density & Coupler Database
//  - Static O(1) pre-initialized database (`static let` + dictionary index) for zero-latency UI & 60fps Uniform generation
//  - Precomputed 81-band spectral tables per stock so lookup and interpolation take 0ms on the main/render threads
//

import Foundation
import simd

public enum FilmFormatGate: String, CaseIterable, Identifiable, Equatable {
    case fullFrame35mm = "35mm Full Frame (36×24mm)"
    case halfFrame35mm = "35mm Half Frame (18×24mm)"
    case mediumFormat645 = "Medium Format 645 (56×41.5mm)"
    case mediumFormat67 = "Medium Format 6×7 (70×56mm)"
    case super35Motion = "Super 35 3-Perf (24.9×18.7mm)"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var gateWidthMM: Float {
        switch self {
        case .fullFrame35mm:   return 36.0
        case .halfFrame35mm:   return 18.0
        case .mediumFormat645: return 56.0
        case .mediumFormat67:  return 70.0
        case .super35Motion:   return 24.89
        }
    }
}

public enum OpticalDiffusionModel: String, CaseIterable, Identifiable, Equatable {
    case none            = "No Optical Filter"
    case blackProMist1_8 = "Tiffen Black Pro-Mist 1/8"
    case blackProMist1_4 = "Tiffen Black Pro-Mist 1/4"
    case blackProMist1_2 = "Tiffen Black Pro-Mist 1/2"
    case glimmerglass1_4 = "Tiffen Glimmerglass 1/4"
    case vintageSoftLens = "Spherical Vintage Soft Lens"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public enum DarkroomPrintPipelineMode: Int, CaseIterable, Identifiable, Equatable {
    case opticalEnlargerAndPrintStock = 0
    case directLabScanner             = 1

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .opticalEnlargerAndPrintStock: return "Optical Enlarger + Print Stock"
        case .directLabScanner:             return "Direct Lab Scanner"
        }
    }
}

public enum EnlargerLightSourceType: Int, CaseIterable, Identifiable, Equatable {
    case halogenDichroicDiffuser = 0
    case condenserPointSource    = 1

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .halogenDichroicDiffuser: return "3200K Halogen Dichroic Diffuser"
        case .condenserPointSource:    return "Point-Source Condenser (Callier Q=1.15)"
        }
    }
}

public enum TargetDisplayColorSpace: Int, CaseIterable, Identifiable, Equatable {
    case sRGB          = 0
    case displayP3     = 1
    case rec2020HLG    = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .sRGB:       return "sRGB"
        case .displayP3:  return "Display P3"
        case .rec2020HLG: return "BT.2020 HLG"
        }
    }
}

public enum LogEncodingTransferFunction: Int, CaseIterable, Identifiable, Equatable {
    case appleLogCompatible = 0
    case arriLogC3          = 1
    case kodakCineon10Bit   = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .appleLogCompatible: return "Apple Log (Compatible)"
        case .arriLogC3:          return "ARRI LogC3"
        case .kodakCineon10Bit:   return "Cineon 10-Bit"
        }
    }
}

public struct FilmSimulationParameters: Equatable {
    public var negativeStockID: String = "kodak_portra_400"
    public var printStockID: String = "kodak_endura_premier"
    public var filmFormatGate: FilmFormatGate = .fullFrame35mm
    public var lensFocalLengthMM: Float = 26.0

    // Stage 1: Exposure & Optics
    public var exposureCompensationEV: Float = 0.0
    public var autoPrintExposureComp: Bool = true
    public var sceneIlluminantKelvin: Float = 5500.0
    public var opticalVignettingStrength: Float = 0.28

    // Stage 2: Optical Diffusion & Bloom
    public var diffusionModel: OpticalDiffusionModel = .blackProMist1_8
    public var bloomStrength: Float = 0.18
    public var bloomHighlightThreshold: Float = 0.65
    public var bloomRadiusMicrometers: Float = 160.0

    // Stage 2b: Emulsion Scatter & Remjet/Base Halation
    public var halationEnabled: Bool = true
    public var halationStrengthRGB: SIMD3<Float> = SIMD3<Float>(0.045, 0.012, 0.002)
    public var halationRadiusMicrometers: SIMD3<Float> = SIMD3<Float>(185.0, 95.0, 50.0)
    public var inEmulsionScatterMicrometers: Float = 5.5

    // Stage 3: Chemical Development & DIR Couplers
    public var pushPullStops: Float = 0.0
    public var devTemperatureCelsius: Float = 37.8
    public var agitationIntensity: Float = 1.0
    public var dirCouplerAmount: Float = 1.0
    public var dirDiffusionRadiusMicrometers: Float = 18.0
    public var developerExhaustion: Float = 0.12
    public var bleachBypassAmount: Float = 0.0

    // Stage 4: Enlarger & Print Paper
    public var printPipelineMode: DarkroomPrintPipelineMode = .opticalEnlargerAndPrintStock
    public var enlargerLightSource: EnlargerLightSourceType = .halogenDichroicDiffuser
    public var dichroicCyanCC: Float = 0.0
    public var dichroicMagentaCC: Float = 0.0
    public var dichroicYellowCC: Float = 0.0
    public var printExposureEV: Float = 0.0
    public var printGammaContrast: Float = 1.0
    public var preflashExposureEV: Float = -6.0
    public var bwMultigradeFilterGrade: Float = 2.5

    // Stage 4b: Silver Halide Grain
    public var grainEnabled: Bool = true
    public var grainStrength: Float = 1.0
    public var grainUniformity: Float = 1.0

    // Stage 5: Scanner & Display
    public var scannerVeilingGlare: Float = 0.005
    public var blackPointOffset: Float = 0.0
    public var whitePointOffset: Float = 0.0
    public var outputColorSpace: TargetDisplayColorSpace = .displayP3

    public init() {}
}

public struct MetalFilmUniforms {
    public var exposureScale: Float
    public var pushPullGammaScale: Float
    public var dminFogOffset: Float
    public var opticalVignetteStrength: Float

    public var bloomStrength: Float
    public var bloomThreshold: Float
    public var bloomRadiusPx: Float
    public var inEmulsionScatterPx: Float

    public var dirCouplerMatrixRow0: SIMD4<Float>
    public var dirCouplerMatrixRow1: SIMD4<Float>
    public var dirCouplerMatrixRow2: SIMD4<Float>

    public var dirRadiusPx: Float
    public var developerExhaustion: Float
    public var bleachBypassAmount: Float
    public var hasRemjetLayer: Float

    public var halationStrengthRGB: SIMD4<Float>
    public var halationRadiusPxRGB: SIMD4<Float>

    public var grainStrength: Float
    public var grainUniformity: Float
    public var pixelSizeMicrometers: Float
    public var frameSeed: UInt32

    public var dichroicFilterCMY: SIMD4<Float>
    public var printExposureScale: Float
    public var printGamma: Float
    public var preflashLinearAddition: Float
    public var callierQFactor: Float

    public var scannerGlare: Float
    public var blackPoint: Float
    public var whitePoint: Float
    public var printPipelineMode: Int32

    public var negativeGammaRGB: SIMD4<Float>
    public var negativeDminRGB: SIMD4<Float>
    public var negativeDmaxRGB: SIMD4<Float>
    public var negativeToeShoulder: SIMD4<Float>
    public var printGammaRGB: SIMD4<Float>
    public var printDminRGB: SIMD4<Float>
    public var printDmaxRGB: SIMD4<Float>
    public var rmsGranularityRGB: SIMD4<Float>
    public var outputColorSpace: Int32
    public var isReversalOrMono: Int32
    public var bwMultigradeGrade: Float
    public var padding0: Float = 0.0
}

public struct CameraFilmStock: Identifiable {
    public let id: String
    public let name: String
    public let processType: String
    public let isoSpeed: Float
    public let referenceKelvin: Float
    public let isReversal: Bool
    public let isMonochrome: Bool
    public let hasAntiHalationRemjet: Bool

    public let gammaRGB: SIMD3<Float>
    public let dMinRGB: SIMD3<Float>
    public let dMaxRGB: SIMD3<Float>
    public let toeSoftnessRGB: SIMD3<Float>
    public let shoulderSoftnessRGB: SIMD3<Float>
    public let rmsGranularity: Float

    public let sensPeakNM: SIMD3<Float>
    public let sensWidthNM: SIMD3<Float>
    public let greenRedCrossTalk: Float

    public let dyePeakNM: SIMD3<Float>
    public let dyeWidthNM: SIMD3<Float>
    public let dirInterlayerMatrix: [Float]
    public let halationReflectanceRGB: SIMD3<Float>
    public let defaultEnlargerYMShift: SIMD2<Float>

    // Pre-evaluated 81-band curves (380nm..780nm at 5nm steps) for 0ms runtime overhead
    public let cachedSensitivities81: [SIMD3<Float>]
    public let cachedDyeDensities81: [SIMD3<Float>]

    public init(
        id: String,
        name: String,
        processType: String,
        isoSpeed: Float,
        referenceKelvin: Float,
        isReversal: Bool = false,
        isMonochrome: Bool = false,
        hasAntiHalationRemjet: Bool = false,
        gammaRGB: SIMD3<Float>,
        dMinRGB: SIMD3<Float>,
        dMaxRGB: SIMD3<Float>,
        toeSoftnessRGB: SIMD3<Float>,
        shoulderSoftnessRGB: SIMD3<Float>,
        rmsGranularity: Float,
        sensPeakNM: SIMD3<Float>,
        sensWidthNM: SIMD3<Float>,
        greenRedCrossTalk: Float = 0.06,
        dyePeakNM: SIMD3<Float> = SIMD3<Float>(655.0, 546.0, 446.0),
        dyeWidthNM: SIMD3<Float> = SIMD3<Float>(52.0, 42.0, 38.0),
        dirInterlayerMatrix: [Float],
        halationReflectanceRGB: SIMD3<Float>,
        defaultEnlargerYMShift: SIMD2<Float> = .zero
    ) {
        self.id = id
        self.name = name
        self.processType = processType
        self.isoSpeed = isoSpeed
        self.referenceKelvin = referenceKelvin
        self.isReversal = isReversal
        self.isMonochrome = isMonochrome
        self.hasAntiHalationRemjet = hasAntiHalationRemjet
        self.gammaRGB = gammaRGB
        self.dMinRGB = dMinRGB
        self.dMaxRGB = dMaxRGB
        self.toeSoftnessRGB = toeSoftnessRGB
        self.shoulderSoftnessRGB = shoulderSoftnessRGB
        self.rmsGranularity = rmsGranularity
        self.sensPeakNM = sensPeakNM
        self.sensWidthNM = sensWidthNM
        self.greenRedCrossTalk = greenRedCrossTalk
        self.dyePeakNM = dyePeakNM
        self.dyeWidthNM = dyeWidthNM
        self.dirInterlayerMatrix = dirInterlayerMatrix
        self.halationReflectanceRGB = halationReflectanceRGB
        self.defaultEnlargerYMShift = defaultEnlargerYMShift

        var sensArr = [SIMD3<Float>]()
        sensArr.reserveCapacity(81)
        var dyeArr = [SIMD3<Float>]()
        dyeArr.reserveCapacity(81)

        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            if isMonochrome {
                let p = expf(-0.5 * powf((lambda - 515.0) / 88.0, 2.0))
                let b = 0.35 * expf(-0.5 * powf((lambda - 430.0) / 42.0, 2.0))
                let redCutoff: Float = (lambda > 655.0) ? expf(-0.5 * powf((lambda - 655.0) / 18.0, 2.0)) : 1.0
                let v = max((p + b) * redCutoff, 1e-5)
                sensArr.append(SIMD3<Float>(v, v, v))
                dyeArr.append(SIMD3<Float>(1.0, 1.0, 1.0))
            } else {
                let rMain = expf(-0.5 * powf((lambda - sensPeakNM.x) / sensWidthNM.x, 2.0))
                let gMain = expf(-0.5 * powf((lambda - sensPeakNM.y) / sensWidthNM.y, 2.0))
                let bMain = expf(-0.5 * powf((lambda - sensPeakNM.z) / sensWidthNM.z, 2.0))
                let rSec  = greenRedCrossTalk * expf(-0.5 * powf((lambda - 535.0) / 28.0, 2.0))
                let gSec  = 0.08 * expf(-0.5 * powf((lambda - 445.0) / 26.0, 2.0))
                sensArr.append(SIMD3<Float>(max(rMain + rSec, 1e-5), max(gMain + gSec, 1e-5), max(bMain, 1e-5)))

                let cMain = expf(-0.5 * powf((lambda - dyePeakNM.x) / dyeWidthNM.x, 2.0))
                let mMain = expf(-0.5 * powf((lambda - dyePeakNM.y) / dyeWidthNM.y, 2.0))
                let yMain = expf(-0.5 * powf((lambda - dyePeakNM.z) / dyeWidthNM.z, 2.0))
                let cSide = 0.09 * expf(-0.5 * powf((lambda - 455.0) / 38.0, 2.0))
                let mSide = 0.12 * expf(-0.5 * powf((lambda - 438.0) / 32.0, 2.0))
                dyeArr.append(SIMD3<Float>(cMain + cSide, mMain + mSide, yMain))
            }
        }
        self.cachedSensitivities81 = sensArr
        self.cachedDyeDensities81 = dyeArr
    }

    public func evaluateSpectralSensitivities81() -> [SIMD3<Float>] {
        return cachedSensitivities81
    }

    public func evaluateDyeSpectralDensities81() -> [SIMD3<Float>] {
        return cachedDyeDensities81
    }
}

public struct PrintFilmStock: Identifiable {
    public let id: String
    public let name: String
    public let isMonochrome: Bool
    public let gammaRGB: SIMD3<Float>
    public let dMinRGB: SIMD3<Float>
    public let dMaxRGB: SIMD3<Float>
    public let sensPeakNM: SIMD3<Float>
    public let sensWidthNM: SIMD3<Float>
    public let dyePeakNM: SIMD3<Float>
    public let dyeWidthNM: SIMD3<Float>
    public let defaultEnlargerYMShift: SIMD2<Float>

    public let cachedSensitivities81: [SIMD3<Float>]
    public let cachedDyeDensities81: [SIMD3<Float>]

    public init(
        id: String,
        name: String,
        isMonochrome: Bool = false,
        gammaRGB: SIMD3<Float>,
        dMinRGB: SIMD3<Float>,
        dMaxRGB: SIMD3<Float>,
        sensPeakNM: SIMD3<Float> = SIMD3<Float>(690.0, 550.0, 460.0),
        sensWidthNM: SIMD3<Float> = SIMD3<Float>(28.0, 25.0, 24.0),
        dyePeakNM: SIMD3<Float> = SIMD3<Float>(652.0, 542.0, 445.0),
        dyeWidthNM: SIMD3<Float> = SIMD3<Float>(54.0, 44.0, 40.0),
        defaultEnlargerYMShift: SIMD2<Float> = .zero
    ) {
        self.id = id
        self.name = name
        self.isMonochrome = isMonochrome
        self.gammaRGB = gammaRGB
        self.dMinRGB = dMinRGB
        self.dMaxRGB = dMaxRGB
        self.sensPeakNM = sensPeakNM
        self.sensWidthNM = sensWidthNM
        self.dyePeakNM = dyePeakNM
        self.dyeWidthNM = dyeWidthNM
        self.defaultEnlargerYMShift = defaultEnlargerYMShift

        var sensArr = [SIMD3<Float>]()
        sensArr.reserveCapacity(81)
        var dyeArr = [SIMD3<Float>]()
        dyeArr.reserveCapacity(81)

        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let rS = expf(-0.5 * powf((lambda - sensPeakNM.x) / sensWidthNM.x, 2.0))
            let gS = expf(-0.5 * powf((lambda - sensPeakNM.y) / sensWidthNM.y, 2.0))
            let bS = expf(-0.5 * powf((lambda - sensPeakNM.z) / sensWidthNM.z, 2.0))
            sensArr.append(SIMD3<Float>(max(rS, 1e-6), max(gS, 1e-6), max(bS, 1e-6)))

            if isMonochrome {
                dyeArr.append(SIMD3<Float>(1.0, 1.0, 1.0))
            } else {
                let cD = expf(-0.5 * powf((lambda - dyePeakNM.x) / dyeWidthNM.x, 2.0))
                let mD = expf(-0.5 * powf((lambda - dyePeakNM.y) / dyeWidthNM.y, 2.0))
                let yD = expf(-0.5 * powf((lambda - dyePeakNM.z) / dyeWidthNM.z, 2.0))
                dyeArr.append(SIMD3<Float>(cD, mD, yD))
            }
        }
        self.cachedSensitivities81 = sensArr
        self.cachedDyeDensities81 = dyeArr
    }

    public func evaluateSpectralSensitivities81() -> [SIMD3<Float>] {
        return cachedSensitivities81
    }

    public func evaluateDyeSpectralDensities81() -> [SIMD3<Float>] {
        return cachedDyeDensities81
    }
}

public enum FilmStockDatabase {
    public static let cameraStocks: [CameraFilmStock] = [
        // 1. Kodak Color Negative (C-41)
        CameraFilmStock(
            id: "kodak_portra_160",
            name: "Kodak Portra 160",
            processType: "C-41",
            isoSpeed: 160,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.58, 0.60, 0.62),
            dMinRGB: SIMD3<Float>(0.18, 0.56, 0.88),
            dMaxRGB: SIMD3<Float>(2.05, 2.45, 2.78),
            toeSoftnessRGB: SIMD3<Float>(0.42, 0.40, 0.38),
            shoulderSoftnessRGB: SIMD3<Float>(0.55, 0.52, 0.50),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(642, 544, 444),
            sensWidthNM: SIMD3<Float>(30, 27, 25),
            greenRedCrossTalk: 0.05,
            dirInterlayerMatrix: [1.05, -0.08, -0.02, -0.06, 1.04, -0.04, -0.02, -0.07, 1.06],
            halationReflectanceRGB: SIMD3<Float>(0.025, 0.004, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(6.0, -3.0)
        ),
        CameraFilmStock(
            id: "kodak_portra_400",
            name: "Kodak Portra 400",
            processType: "C-41",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.62, 0.63, 0.65),
            dMinRGB: SIMD3<Float>(0.20, 0.58, 0.90),
            dMaxRGB: SIMD3<Float>(2.15, 2.55, 2.88),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.36, 0.35),
            shoulderSoftnessRGB: SIMD3<Float>(0.48, 0.46, 0.44),
            rmsGranularity: 9.5,
            sensPeakNM: SIMD3<Float>(645, 545, 445),
            sensWidthNM: SIMD3<Float>(32, 28, 26),
            greenRedCrossTalk: 0.06,
            dirInterlayerMatrix: [1.08, -0.10, -0.03, -0.08, 1.07, -0.05, -0.03, -0.09, 1.09],
            halationReflectanceRGB: SIMD3<Float>(0.032, 0.005, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(4.0, -2.0)
        ),
        CameraFilmStock(
            id: "kodak_portra_800",
            name: "Kodak Portra 800",
            processType: "C-41",
            isoSpeed: 800,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.66, 0.67, 0.70),
            dMinRGB: SIMD3<Float>(0.22, 0.60, 0.94),
            dMaxRGB: SIMD3<Float>(2.22, 2.62, 2.95),
            toeSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.32),
            shoulderSoftnessRGB: SIMD3<Float>(0.44, 0.42, 0.40),
            rmsGranularity: 12.5,
            sensPeakNM: SIMD3<Float>(648, 546, 448),
            sensWidthNM: SIMD3<Float>(34, 30, 28),
            greenRedCrossTalk: 0.07,
            dirInterlayerMatrix: [1.11, -0.12, -0.04, -0.09, 1.10, -0.06, -0.04, -0.10, 1.12],
            halationReflectanceRGB: SIMD3<Float>(0.038, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(10.0, 2.0)
        ),
        CameraFilmStock(
            id: "kodak_ektar_100",
            name: "Kodak Ektar 100",
            processType: "C-41",
            isoSpeed: 100,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.76, 0.75, 0.78),
            dMinRGB: SIMD3<Float>(0.18, 0.55, 0.86),
            dMaxRGB: SIMD3<Float>(2.35, 2.75, 3.05),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.22, 0.20),
            shoulderSoftnessRGB: SIMD3<Float>(0.28, 0.28, 0.26),
            rmsGranularity: 6.0,
            sensPeakNM: SIMD3<Float>(652, 542, 442),
            sensWidthNM: SIMD3<Float>(25, 23, 22),
            greenRedCrossTalk: 0.02,
            dirInterlayerMatrix: [1.24, -0.18, -0.06, -0.15, 1.22, -0.08, -0.05, -0.16, 1.25],
            halationReflectanceRGB: SIMD3<Float>(0.028, 0.004, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-8.0, 6.0)
        ),
        CameraFilmStock(
            id: "kodak_gold_200",
            name: "Kodak Gold 200",
            processType: "C-41",
            isoSpeed: 200,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.70, 0.68, 0.64),
            dMinRGB: SIMD3<Float>(0.21, 0.59, 0.92),
            dMaxRGB: SIMD3<Float>(2.20, 2.55, 2.80),
            toeSoftnessRGB: SIMD3<Float>(0.30, 0.32, 0.36),
            shoulderSoftnessRGB: SIMD3<Float>(0.40, 0.42, 0.48),
            rmsGranularity: 11.0,
            sensPeakNM: SIMD3<Float>(646, 548, 448),
            sensWidthNM: SIMD3<Float>(33, 29, 27),
            greenRedCrossTalk: 0.08,
            dirInterlayerMatrix: [1.14, -0.11, -0.03, -0.09, 1.12, -0.05, -0.03, -0.08, 1.06],
            halationReflectanceRGB: SIMD3<Float>(0.036, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(18.0, 4.0)
        ),
        CameraFilmStock(
            id: "kodak_ultramax_400",
            name: "Kodak UltraMax 400",
            processType: "C-41",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.72, 0.71, 0.69),
            dMinRGB: SIMD3<Float>(0.22, 0.61, 0.95),
            dMaxRGB: SIMD3<Float>(2.25, 2.60, 2.88),
            toeSoftnessRGB: SIMD3<Float>(0.28, 0.30, 0.33),
            shoulderSoftnessRGB: SIMD3<Float>(0.36, 0.38, 0.42),
            rmsGranularity: 13.5,
            sensPeakNM: SIMD3<Float>(648, 546, 446),
            sensWidthNM: SIMD3<Float>(34, 30, 28),
            greenRedCrossTalk: 0.07,
            dirInterlayerMatrix: [1.16, -0.13, -0.04, -0.11, 1.15, -0.06, -0.04, -0.10, 1.14],
            halationReflectanceRGB: SIMD3<Float>(0.040, 0.007, 0.002),
            defaultEnlargerYMShift: SIMD2<Float>(14.0, 2.0)
        ),
        // 2. Fujifilm Color Negative (C-41)
        CameraFilmStock(
            id: "fujifilm_pro_400h",
            name: "Fujifilm Pro 400H",
            processType: "C-41 (4th Cyan Layer)",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.59, 0.62, 0.64),
            dMinRGB: SIMD3<Float>(0.19, 0.56, 0.88),
            dMaxRGB: SIMD3<Float>(2.10, 2.52, 2.86),
            toeSoftnessRGB: SIMD3<Float>(0.40, 0.36, 0.35),
            shoulderSoftnessRGB: SIMD3<Float>(0.54, 0.48, 0.45),
            rmsGranularity: 9.0,
            sensPeakNM: SIMD3<Float>(640, 538, 444),
            sensWidthNM: SIMD3<Float>(29, 25, 25),
            greenRedCrossTalk: 0.03,
            dirInterlayerMatrix: [1.06, -0.07, -0.02, -0.14, 1.15, -0.05, -0.03, -0.08, 1.10],
            halationReflectanceRGB: SIMD3<Float>(0.026, 0.005, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-10.0, -12.0)
        ),
        CameraFilmStock(
            id: "fujifilm_superia_400",
            name: "Fujifilm Superia X-TRA 400",
            processType: "C-41 (4th Layer)",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.68, 0.71, 0.72),
            dMinRGB: SIMD3<Float>(0.21, 0.58, 0.91),
            dMaxRGB: SIMD3<Float>(2.22, 2.64, 2.94),
            toeSoftnessRGB: SIMD3<Float>(0.30, 0.28, 0.28),
            shoulderSoftnessRGB: SIMD3<Float>(0.38, 0.36, 0.36),
            rmsGranularity: 12.0,
            sensPeakNM: SIMD3<Float>(642, 536, 442),
            sensWidthNM: SIMD3<Float>(30, 26, 26),
            greenRedCrossTalk: 0.04,
            dirInterlayerMatrix: [1.14, -0.10, -0.03, -0.15, 1.18, -0.06, -0.04, -0.11, 1.15],
            halationReflectanceRGB: SIMD3<Float>(0.034, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-8.0, 10.0)
        ),
        // 3. Kodak Vision3 Motion Picture (ECN-2 & Remjet-Free C-41)
        CameraFilmStock(
            id: "kodak_vision3_50d",
            name: "Kodak Vision3 50D (5203)",
            processType: "ECN-2",
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.52, 0.53, 0.54),
            dMinRGB: SIMD3<Float>(0.16, 0.52, 0.84),
            dMaxRGB: SIMD3<Float>(1.95, 2.35, 2.68),
            toeSoftnessRGB: SIMD3<Float>(0.45, 0.44, 0.42),
            shoulderSoftnessRGB: SIMD3<Float>(0.62, 0.60, 0.58),
            rmsGranularity: 5.5,
            sensPeakNM: SIMD3<Float>(646, 544, 444),
            sensWidthNM: SIMD3<Float>(28, 26, 24),
            greenRedCrossTalk: 0.04,
            dirInterlayerMatrix: [1.08, -0.09, -0.02, -0.07, 1.08, -0.04, -0.02, -0.08, 1.09],
            halationReflectanceRGB: SIMD3<Float>(0.006, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-4.0, -4.0)
        ),
        CameraFilmStock(
            id: "kodak_vision3_200t",
            name: "Kodak Vision3 200T (5213)",
            processType: "ECN-2",
            isoSpeed: 200,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.53, 0.54, 0.56),
            dMinRGB: SIMD3<Float>(0.17, 0.54, 0.86),
            dMaxRGB: SIMD3<Float>(1.98, 2.38, 2.72),
            toeSoftnessRGB: SIMD3<Float>(0.44, 0.43, 0.42),
            shoulderSoftnessRGB: SIMD3<Float>(0.60, 0.58, 0.56),
            rmsGranularity: 7.5,
            sensPeakNM: SIMD3<Float>(648, 545, 442),
            sensWidthNM: SIMD3<Float>(30, 27, 25),
            greenRedCrossTalk: 0.05,
            dirInterlayerMatrix: [1.09, -0.10, -0.02, -0.08, 1.09, -0.05, -0.03, -0.08, 1.10],
            halationReflectanceRGB: SIMD3<Float>(0.007, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-16.0, -3.0)
        ),
        CameraFilmStock(
            id: "kodak_vision3_250d",
            name: "Kodak Vision3 250D (5207)",
            processType: "ECN-2",
            isoSpeed: 250,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.54, 0.55, 0.57),
            dMinRGB: SIMD3<Float>(0.18, 0.55, 0.87),
            dMaxRGB: SIMD3<Float>(2.02, 2.42, 2.75),
            toeSoftnessRGB: SIMD3<Float>(0.42, 0.41, 0.40),
            shoulderSoftnessRGB: SIMD3<Float>(0.58, 0.56, 0.54),
            rmsGranularity: 8.5,
            sensPeakNM: SIMD3<Float>(646, 545, 445),
            sensWidthNM: SIMD3<Float>(31, 28, 26),
            greenRedCrossTalk: 0.05,
            dirInterlayerMatrix: [1.10, -0.10, -0.03, -0.08, 1.10, -0.05, -0.03, -0.09, 1.11],
            halationReflectanceRGB: SIMD3<Float>(0.008, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(2.0, -3.0)
        ),
        CameraFilmStock(
            id: "kodak_vision3_500t",
            name: "Kodak Vision3 500T (5219)",
            processType: "ECN-2",
            isoSpeed: 500,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.55, 0.56, 0.58),
            dMinRGB: SIMD3<Float>(0.19, 0.56, 0.89),
            dMaxRGB: SIMD3<Float>(2.05, 2.45, 2.80),
            toeSoftnessRGB: SIMD3<Float>(0.40, 0.39, 0.38),
            shoulderSoftnessRGB: SIMD3<Float>(0.56, 0.54, 0.52),
            rmsGranularity: 10.5,
            sensPeakNM: SIMD3<Float>(650, 546, 442),
            sensWidthNM: SIMD3<Float>(33, 29, 27),
            greenRedCrossTalk: 0.06,
            dirInterlayerMatrix: [1.11, -0.11, -0.03, -0.09, 1.11, -0.06, -0.03, -0.09, 1.12],
            halationReflectanceRGB: SIMD3<Float>(0.009, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-18.0, -2.0)
        ),
        CameraFilmStock(
            id: "cinestill_800t",
            name: "CineStill 800T (Remjet-Free C-41)",
            processType: "C-41 (Remjet Removed)",
            isoSpeed: 800,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            gammaRGB: SIMD3<Float>(0.64, 0.65, 0.68),
            dMinRGB: SIMD3<Float>(0.21, 0.58, 0.92),
            dMaxRGB: SIMD3<Float>(2.20, 2.58, 2.92),
            toeSoftnessRGB: SIMD3<Float>(0.35, 0.34, 0.33),
            shoulderSoftnessRGB: SIMD3<Float>(0.46, 0.45, 0.43),
            rmsGranularity: 12.0,
            sensPeakNM: SIMD3<Float>(650, 546, 442),
            sensWidthNM: SIMD3<Float>(33, 29, 27),
            greenRedCrossTalk: 0.06,
            dirInterlayerMatrix: [1.13, -0.11, -0.03, -0.09, 1.12, -0.06, -0.03, -0.10, 1.14],
            halationReflectanceRGB: SIMD3<Float>(0.145, 0.028, 0.004),
            defaultEnlargerYMShift: SIMD2<Float>(-22.0, 4.0)
        ),
        CameraFilmStock(
            id: "cinestill_50d",
            name: "CineStill 50D (Remjet-Free C-41)",
            processType: "C-41 (Remjet Removed)",
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            gammaRGB: SIMD3<Float>(0.61, 0.62, 0.64),
            dMinRGB: SIMD3<Float>(0.18, 0.55, 0.87),
            dMaxRGB: SIMD3<Float>(2.12, 2.50, 2.82),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.37, 0.36),
            shoulderSoftnessRGB: SIMD3<Float>(0.50, 0.48, 0.46),
            rmsGranularity: 6.5,
            sensPeakNM: SIMD3<Float>(646, 544, 444),
            sensWidthNM: SIMD3<Float>(28, 26, 24),
            greenRedCrossTalk: 0.04,
            dirInterlayerMatrix: [1.10, -0.10, -0.02, -0.08, 1.10, -0.05, -0.02, -0.09, 1.11],
            halationReflectanceRGB: SIMD3<Float>(0.115, 0.022, 0.003),
            defaultEnlargerYMShift: SIMD2<Float>(6.0, 2.0)
        ),
        // 4. Color Reversal Slide Films (E-6)
        CameraFilmStock(
            id: "fujifilm_velvia_50",
            name: "Fujifilm Velvia 50 (RVP50)",
            processType: "E-6 Reversal",
            isoSpeed: 50,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.68, 1.65, 1.72),
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.11),
            dMaxRGB: SIMD3<Float>(3.55, 3.60, 3.45),
            toeSoftnessRGB: SIMD3<Float>(0.16, 0.16, 0.15),
            shoulderSoftnessRGB: SIMD3<Float>(0.20, 0.20, 0.18),
            rmsGranularity: 8.5,
            sensPeakNM: SIMD3<Float>(654, 540, 440),
            sensWidthNM: SIMD3<Float>(24, 22, 21),
            greenRedCrossTalk: 0.015,
            dirInterlayerMatrix: [1.30, -0.22, -0.06, -0.18, 1.28, -0.10, -0.06, -0.18, 1.30],
            halationReflectanceRGB: SIMD3<Float>(0.018, 0.003, 0.001)
        ),
        CameraFilmStock(
            id: "fujifilm_provia_100f",
            name: "Fujifilm Provia 100F (RDPIII)",
            processType: "E-6 Reversal",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.42, 1.44, 1.46),
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.10),
            dMaxRGB: SIMD3<Float>(3.35, 3.40, 3.30),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.22, 0.21),
            shoulderSoftnessRGB: SIMD3<Float>(0.26, 0.26, 0.25),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(648, 542, 442),
            sensWidthNM: SIMD3<Float>(26, 24, 23),
            greenRedCrossTalk: 0.025,
            dirInterlayerMatrix: [1.18, -0.14, -0.04, -0.12, 1.18, -0.06, -0.04, -0.12, 1.18],
            halationReflectanceRGB: SIMD3<Float>(0.016, 0.003, 0.001)
        ),
        CameraFilmStock(
            id: "fujifilm_astia_100f",
            name: "Fujifilm Astia 100F (RAP100F)",
            processType: "E-6 Reversal",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.28, 1.30, 1.32),
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.10),
            dMaxRGB: SIMD3<Float>(3.20, 3.25, 3.18),
            toeSoftnessRGB: SIMD3<Float>(0.28, 0.28, 0.26),
            shoulderSoftnessRGB: SIMD3<Float>(0.34, 0.34, 0.32),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(644, 543, 444),
            sensWidthNM: SIMD3<Float>(28, 25, 24),
            greenRedCrossTalk: 0.03,
            dirInterlayerMatrix: [1.12, -0.10, -0.03, -0.09, 1.12, -0.05, -0.03, -0.10, 1.13],
            halationReflectanceRGB: SIMD3<Float>(0.015, 0.003, 0.001)
        ),
        CameraFilmStock(
            id: "kodak_ektachrome_e100",
            name: "Kodak Ektachrome E100",
            processType: "E-6 Reversal",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.45, 1.46, 1.50),
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.10),
            dMaxRGB: SIMD3<Float>(3.40, 3.45, 3.38),
            toeSoftnessRGB: SIMD3<Float>(0.20, 0.20, 0.19),
            shoulderSoftnessRGB: SIMD3<Float>(0.25, 0.25, 0.24),
            rmsGranularity: 7.5,
            sensPeakNM: SIMD3<Float>(648, 544, 446),
            sensWidthNM: SIMD3<Float>(26, 24, 23),
            greenRedCrossTalk: 0.025,
            dirInterlayerMatrix: [1.20, -0.15, -0.04, -0.12, 1.19, -0.06, -0.04, -0.14, 1.22],
            halationReflectanceRGB: SIMD3<Float>(0.018, 0.003, 0.001)
        ),
        // 5. Silver Halide Black & White Negative
        CameraFilmStock(
            id: "kodak_tri_x_400",
            name: "Kodak Tri-X 400 (400TX)",
            processType: "B&W D-76",
            isoSpeed: 400,
            referenceKelvin: 5500,
            isMonochrome: true,
            gammaRGB: SIMD3<Float>(0.68, 0.68, 0.68),
            dMinRGB: SIMD3<Float>(0.12, 0.12, 0.12),
            dMaxRGB: SIMD3<Float>(2.35, 2.35, 2.35),
            toeSoftnessRGB: SIMD3<Float>(0.32, 0.32, 0.32),
            shoulderSoftnessRGB: SIMD3<Float>(0.38, 0.38, 0.38),
            rmsGranularity: 16.0,
            sensPeakNM: SIMD3<Float>(520, 520, 520),
            sensWidthNM: SIMD3<Float>(85, 85, 85),
            dirInterlayerMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            halationReflectanceRGB: SIMD3<Float>(0.035, 0.035, 0.035)
        ),
        CameraFilmStock(
            id: "ilford_hp5_plus_400",
            name: "Ilford HP5 Plus 400",
            processType: "B&W ID-11",
            isoSpeed: 400,
            referenceKelvin: 5500,
            isMonochrome: true,
            gammaRGB: SIMD3<Float>(0.62, 0.62, 0.62),
            dMinRGB: SIMD3<Float>(0.11, 0.11, 0.11),
            dMaxRGB: SIMD3<Float>(2.25, 2.25, 2.25),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.38, 0.38),
            shoulderSoftnessRGB: SIMD3<Float>(0.48, 0.48, 0.48),
            rmsGranularity: 15.0,
            sensPeakNM: SIMD3<Float>(515, 515, 515),
            sensWidthNM: SIMD3<Float>(88, 88, 88),
            dirInterlayerMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            halationReflectanceRGB: SIMD3<Float>(0.032, 0.032, 0.032)
        ),
        CameraFilmStock(
            id: "kodak_tmax_100",
            name: "Kodak T-Max 100 (100TMX)",
            processType: "B&W T-Max Dev",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isMonochrome: true,
            gammaRGB: SIMD3<Float>(0.65, 0.65, 0.65),
            dMinRGB: SIMD3<Float>(0.09, 0.09, 0.09),
            dMaxRGB: SIMD3<Float>(2.40, 2.40, 2.40),
            toeSoftnessRGB: SIMD3<Float>(0.24, 0.24, 0.24),
            shoulderSoftnessRGB: SIMD3<Float>(0.28, 0.28, 0.28),
            rmsGranularity: 8.0,
            sensPeakNM: SIMD3<Float>(525, 525, 525),
            sensWidthNM: SIMD3<Float>(90, 90, 90),
            dirInterlayerMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            halationReflectanceRGB: SIMD3<Float>(0.022, 0.022, 0.022)
        ),
        CameraFilmStock(
            id: "fujifilm_acros_100_ii",
            name: "Fujifilm Neopan 100 Acros II",
            processType: "B&W Super Fine-Σ",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isMonochrome: true,
            gammaRGB: SIMD3<Float>(0.70, 0.70, 0.70),
            dMinRGB: SIMD3<Float>(0.08, 0.08, 0.08),
            dMaxRGB: SIMD3<Float>(2.45, 2.45, 2.45),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.22, 0.22),
            shoulderSoftnessRGB: SIMD3<Float>(0.32, 0.32, 0.32),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(510, 510, 510),
            sensWidthNM: SIMD3<Float>(82, 82, 82),
            dirInterlayerMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            halationReflectanceRGB: SIMD3<Float>(0.020, 0.020, 0.020)
        )
    ]

    public static let printStocks: [PrintFilmStock] = [
        PrintFilmStock(
            id: "kodak_endura_premier",
            name: "Kodak Endura Premier / Supra Endura (RA-4)",
            gammaRGB: SIMD3<Float>(2.40, 2.42, 2.45),
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.10),
            dMaxRGB: SIMD3<Float>(2.45, 2.42, 2.38),
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        PrintFilmStock(
            id: "fujifilm_crystal_archive_maxima",
            name: "Fujifilm Crystal Archive Type II / Maxima (RA-4)",
            gammaRGB: SIMD3<Float>(2.52, 2.55, 2.58),
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.09),
            dMaxRGB: SIMD3<Float>(2.58, 2.55, 2.50),
            defaultEnlargerYMShift: SIMD2<Float>(-6.0, 4.0)
        ),
        PrintFilmStock(
            id: "kodak_vision_2383",
            name: "Kodak Vision Color Print Film 2383 (ECP-2E)",
            gammaRGB: SIMD3<Float>(2.78, 2.82, 2.88),
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.08),
            dMaxRGB: SIMD3<Float>(3.15, 3.20, 3.10),
            defaultEnlargerYMShift: SIMD2<Float>(-10.0, -5.0)
        ),
        PrintFilmStock(
            id: "kodak_premier_2393",
            name: "Kodak Vision Premier 2393 Print Film",
            gammaRGB: SIMD3<Float>(2.92, 2.95, 3.00),
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.08),
            dMaxRGB: SIMD3<Float>(3.35, 3.40, 3.30),
            defaultEnlargerYMShift: SIMD2<Float>(-6.0, -2.0)
        ),
        PrintFilmStock(
            id: "ilford_multigrade_fb",
            name: "Ilford Multigrade FB Classic (B&W VC Paper)",
            isMonochrome: true,
            gammaRGB: SIMD3<Float>(2.45, 2.45, 2.45),
            dMinRGB: SIMD3<Float>(0.06, 0.06, 0.06),
            dMaxRGB: SIMD3<Float>(2.25, 2.25, 2.25),
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        )
    ]

    private static let cameraStockIndex: [String: CameraFilmStock] = {
        Dictionary(uniqueKeysWithValues: cameraStocks.map { ($0.id, $0) })
    }()

    private static let printStockIndex: [String: PrintFilmStock] = {
        Dictionary(uniqueKeysWithValues: printStocks.map { ($0.id, $0) })
    }()

    public static func cameraStock(withID id: String) -> CameraFilmStock {
        return cameraStockIndex[id] ?? cameraStocks[1]
    }

    public static func printStock(withID id: String) -> PrintFilmStock {
        return printStockIndex[id] ?? printStocks[0]
    }
}
