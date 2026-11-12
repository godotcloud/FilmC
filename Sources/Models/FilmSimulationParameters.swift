//
//  FilmStockParameters.swift
//  SpektraCam
//
//  Official Datasheet-Calibrated Sensitometry, Asymmetric J-Aggregate Spectral Sensitivity,
//  Fujifilm 4th Cyan Layer, Hanson Colored Masking Couplers & Distinct Dye Spectral Database
//
//  Grounded in published manufacturer technical datasheets:
//  - Kodak Portra 160 / 400 (E-4050) / 800 (E-4040)
//  - Kodak Ektar 100 (E-4046), Gold 200, UltraMax 400
//  - Fujifilm Pro 400H (AF3-176E) & Superia X-TRA 400 (AF3-144E) with 4th Cyan-Sensitive Layer (505nm)
//  - Kodak Vision3 50D (5203), 200T (5213), 250D (5207), 500T (5219 / TI-2647) & CineStill 800T / 50D
//  - Fujifilm Velvia 50 (AF3-960E), Provia 100F, Astia 100F & Kodak Ektachrome E100 (E-6 Reversal)
//  - Kodak Tri-X 400 (F-4017), T-Max 100, Ilford HP5 Plus 400, Fujifilm Acros 100 II
//  - Print Stocks: Kodak Endura Premier (E-4070), Fujifilm Crystal Archive Maxima, Kodak Vision 2383 / 2393, Ilford Multigrade FB
//

import Foundation
import simd

public enum FilmFormatGate: String, CaseIterable, Identifiable, Codable, Equatable {
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

public enum OpticalDiffusionModel: String, CaseIterable, Identifiable, Codable, Equatable {
    case none            = "No Optical Filter"
    case blackProMist1_8 = "Tiffen Black Pro-Mist 1/8"
    case blackProMist1_4 = "Tiffen Black Pro-Mist 1/4"
    case blackProMist1_2 = "Tiffen Black Pro-Mist 1/2"
    case glimmerglass1_4 = "Tiffen Glimmerglass 1/4"
    case vintageSoftLens = "Spherical Vintage Soft Lens"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public enum DarkroomPrintPipelineMode: Int, CaseIterable, Identifiable, Codable, Equatable {
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

public enum EnlargerLightSourceType: Int, CaseIterable, Identifiable, Codable, Equatable {
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

public enum TargetDisplayColorSpace: Int, CaseIterable, Identifiable, Codable, Equatable {
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

public enum LogEncodingTransferFunction: Int, CaseIterable, Identifiable, Codable, Equatable {
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

public struct FilmSimulationParameters: Codable, Equatable {
    public var negativeStockID: String = "kodak_portra_400"
    public var printStockID: String = "kodak_endura_premier"
    public var filmFormatGate: FilmFormatGate = .fullFrame35mm
    public var lensFocalLengthMM: Float = 26.0

    // Stage 1: Exposure & Optics
    public var exposureCompensationEV: Float = 0.0
    public var autoPrintExposureComp: Bool = true
    public var sceneIlluminantKelvin: Float = 5500.0
    public var opticalVignettingStrength: Float = 0.25

    // Stage 2: Optical Diffusion & Bloom
    public var diffusionModel: OpticalDiffusionModel = .blackProMist1_8
    public var bloomStrength: Float = 0.14
    public var bloomHighlightThreshold: Float = 0.68
    public var bloomRadiusMicrometers: Float = 150.0

    // Stage 2b: Emulsion Scatter & Remjet/Base Halation
    public var halationEnabled: Bool = true
    public var halationStrengthRGB: SIMD3<Float> = SIMD3<Float>(0.055, 0.014, 0.002)
    public var halationRadiusMicrometers: SIMD3<Float> = SIMD3<Float>(190.0, 95.0, 50.0)
    public var inEmulsionScatterMicrometers: Float = 5.0

    // Stage 3: Chemical Development & DIR Couplers
    public var pushPullStops: Float = 0.0
    public var devTemperatureCelsius: Float = 37.8
    public var agitationIntensity: Float = 1.0
    public var dirCouplerAmount: Float = 1.0
    public var dirDiffusionRadiusMicrometers: Float = 18.0
    public var developerExhaustion: Float = 0.10
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
    public var scannerVeilingGlare: Float = 0.004
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
    // Per-channel shoulder softness in .xyz, packed toe softness or reversal contrast in .w
    public var negativeShoulderRGB: SIMD4<Float>
    // Per-channel toe softness in .xyz (critical for Portra vs Ektar vs Gold shadow crossover!)
    public var negativeToeRGB: SIMD4<Float>
    public var printGammaRGB: SIMD4<Float>
    public var printDminRGB: SIMD4<Float>
    public var printDmaxRGB: SIMD4<Float>
    public var rmsGranularityRGB: SIMD4<Float>
    public var outputColorSpace: Int32
    public var isReversalOrMono: Int32
    public var bwMultigradeGrade: Float
    public var padding0: Float = 0.0
}

// Asymmetric Gaussian helper: models real J-aggregate sensitizing dyes (gradual vibronic short-wave shoulder + steep long-wave Boltzmann cutoff)
@inline(__always)
private func asymmetricGaussian(lambda: Float, peak: Float, widthShort: Float, widthLong: Float) -> Float {
    let sigma = (lambda < peak) ? widthShort : widthLong
    let d = (lambda - peak) / max(sigma, 1.0)
    return expf(-0.5 * d * d)
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
    // Fujifilm 4th Color Layer (505nm cyan-sensitive layer inhibiting red layer for accurate emerald greens & skin tones)
    public let fourthCyanLayerStrength: Float

    public let dyePeakNM: SIMD3<Float>
    public let dyeWidthNM: SIMD3<Float>
    // Hanson (1950) colored masking coupler side-absorption cancellation efficiency (0.0 for E-6 reversal, 0.75..0.95 for C-41/ECN-2)
    public let maskingCouplerEfficiency: Float

    public let dirInterlayerMatrix: [Float]
    public let halationReflectanceRGB: SIMD3<Float>
    // Subtle lab color-timing personality offset (kept small, <= 3 CC, because 18% grey is now auto-balanced!)
    public let defaultEnlargerYMShift: SIMD2<Float>

    // Pre-evaluated 81-band curves (380nm..780nm at 5nm steps)
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
        greenRedCrossTalk: Float = 0.04,
        fourthCyanLayerStrength: Float = 0.0,
        dyePeakNM: SIMD3<Float> = SIMD3<Float>(652.0, 545.0, 446.0),
        dyeWidthNM: SIMD3<Float> = SIMD3<Float>(50.0, 40.0, 36.0),
        maskingCouplerEfficiency: Float = 0.85,
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
        self.fourthCyanLayerStrength = fourthCyanLayerStrength
        self.dyePeakNM = dyePeakNM
        self.dyeWidthNM = dyeWidthNM
        self.maskingCouplerEfficiency = isReversal ? 0.0 : maskingCouplerEfficiency
        self.dirInterlayerMatrix = dirInterlayerMatrix
        self.halationReflectanceRGB = halationReflectanceRGB
        self.defaultEnlargerYMShift = defaultEnlargerYMShift

        var sensArr = [SIMD3<Float>]()
        sensArr.reserveCapacity(81)
        var dyeArr = [SIMD3<Float>]()
        dyeArr.reserveCapacity(81)

        // Effective dynamic range span per channel (normalized to Portra 400's 1.98 span so stock Dmax differences manifest naturally)
        let rawSpan = simd_max(dMaxRGB - dMinRGB, SIMD3<Float>(1.4, 1.4, 1.4))
        let relSpanScale: SIMD3<Float> = isReversal
            ? SIMD3<Float>(1.0, 1.0, 1.0)
            : simd_clamp(rawSpan / SIMD3<Float>(1.95, 1.97, 1.98), SIMD3<Float>(0.85, 0.85, 0.85), SIMD3<Float>(1.18, 1.18, 1.18))

        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            if isMonochrome {
                // Panchromatic silver halide sensitivity (matches Kodak Tri-X F-4017 / T-Max / Ilford HP5+ spectral curves)
                let agBrIntrinsic = 0.55 * asymmetricGaussian(lambda: lambda, peak: 415.0, widthShort: 30.0, widthLong: 38.0)
                let orthoGreen    = 0.85 * asymmetricGaussian(lambda: lambda, peak: sensPeakNM.y - 25.0, widthShort: 42.0, widthLong: 45.0)
                let panRedPeak    = 0.92 * asymmetricGaussian(lambda: lambda, peak: sensPeakNM.x + 85.0, widthShort: 45.0, widthLong: 16.0)
                let v = max(agBrIntrinsic + orthoGreen + panRedPeak, 1e-5)
                sensArr.append(SIMD3<Float>(v, v, v))
                dyeArr.append(SIMD3<Float>(1.0, 1.0, 1.0))
            } else {
                // 1. Asymmetric J-aggregate sensitization with vibronic secondary monomer shoulder (-32nm) & steep long-wave cutoff
                let rMain = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.x, widthShort: sensWidthNM.x * 1.18, widthLong: sensWidthNM.x * 0.54)
                          + 0.28 * asymmetricGaussian(lambda: lambda, peak: sensPeakNM.x - 34.0, widthShort: 24.0, widthLong: 22.0)
                let gMain = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.y, widthShort: sensWidthNM.y * 1.15, widthLong: sensWidthNM.y * 0.56)
                          + 0.26 * asymmetricGaussian(lambda: lambda, peak: sensPeakNM.y - 30.0, widthShort: 22.0, widthLong: 20.0)
                let bMain = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.z, widthShort: sensWidthNM.z * 1.25, widthLong: sensWidthNM.z * 0.62)
                          + 0.35 * asymmetricGaussian(lambda: lambda, peak: 412.0, widthShort: 22.0, widthLong: 24.0)

                // Yellow Careyet-filter cutoff at 500nm protects green & red layers from raw blue light
                let yellowFilterPass: Float = 1.0 / (1.0 + expf(-(lambda - 495.0) / 6.5))

                // Fujifilm 4th Color Layer (peaks at 505nm): suppresses unwanted red-layer response in the blue-green band (480-525nm)
                let fourthCyanLobe = fourthCyanLayerStrength * asymmetricGaussian(lambda: lambda, peak: 505.0, widthShort: 18.0, widthLong: 19.0)
                let rCross = greenRedCrossTalk * asymmetricGaussian(lambda: lambda, peak: 538.0, widthShort: 24.0, widthLong: 24.0)

                let rTotal = max((rMain + rCross - fourthCyanLobe * 0.42) * yellowFilterPass, 1e-5)
                let gTotal = max((gMain + fourthCyanLobe * 0.18) * yellowFilterPass, 1e-5)
                let bTotal = max(bMain, 1e-5)
                sensArr.append(SIMD3<Float>(rTotal, gTotal, bTotal))

                // 2. Analytical Spectral Dye Density + Hanson (1950) Colored Masking Coupler Side-Absorption Cancellation
                let cMain = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.x, widthShort: dyeWidthNM.x * 1.12, widthLong: dyeWidthNM.x * 0.78)
                let mMain = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.y, widthShort: dyeWidthNM.y * 1.08, widthLong: dyeWidthNM.y * 0.76)
                let yMain = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.z, widthShort: dyeWidthNM.z * 1.05, widthLong: dyeWidthNM.z * 0.74)

                // Unwanted secondary dye absorptions (Cyan absorbs slightly in G/B; Magenta absorbs in B)
                // In C-41/ECN-2 negatives, colored masking couplers (pink-colored cyan coupler & yellow-colored magenta coupler)
                // are consumed where dye forms, cancelling `maskingCouplerEfficiency` (85%-92%) of the unwanted side-absorption!
                let residualFactor = max(1.0 - self.maskingCouplerEfficiency, 0.05)
                let cSide = (0.11 * residualFactor) * asymmetricGaussian(lambda: lambda, peak: 455.0, widthShort: 36.0, widthLong: 36.0)
                let mSide = (0.16 * residualFactor) * asymmetricGaussian(lambda: lambda, peak: 438.0, widthShort: 30.0, widthLong: 30.0)

                let effDye = SIMD3<Float>(
                    (cMain + cSide) * relSpanScale.x,
                    (mMain + mSide) * relSpanScale.y,
                    yMain * relSpanScale.z
                )
                dyeArr.append(effDye)
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
        sensPeakNM: SIMD3<Float> = SIMD3<Float>(692.0, 552.0, 462.0),
        sensWidthNM: SIMD3<Float> = SIMD3<Float>(25.0, 23.0, 22.0),
        dyePeakNM: SIMD3<Float> = SIMD3<Float>(650.0, 542.0, 445.0),
        dyeWidthNM: SIMD3<Float> = SIMD3<Float>(52.0, 42.0, 38.0),
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
            // Narrow-band RA-4 / 2383 print emulsion spectral sensitivities (minimal overlap to prevent crosstalk during printing)
            let rS = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.x, widthShort: sensWidthNM.x * 1.05, widthLong: sensWidthNM.x * 0.65)
            let gS = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.y, widthShort: sensWidthNM.y * 1.05, widthLong: sensWidthNM.y * 0.65)
            let bS = asymmetricGaussian(lambda: lambda, peak: sensPeakNM.z, widthShort: sensWidthNM.z * 1.10, widthLong: sensWidthNM.z * 0.65)
            sensArr.append(SIMD3<Float>(max(rS, 1e-6), max(gS, 1e-6), max(bS, 1e-6)))

            if isMonochrome {
                dyeArr.append(SIMD3<Float>(1.0, 1.0, 1.0))
            } else {
                let cD = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.x, widthShort: dyeWidthNM.x * 1.10, widthLong: dyeWidthNM.x * 0.82)
                let mD = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.y, widthShort: dyeWidthNM.y * 1.06, widthLong: dyeWidthNM.y * 0.80)
                let yD = asymmetricGaussian(lambda: lambda, peak: dyePeakNM.z, widthShort: dyeWidthNM.z * 1.04, widthLong: dyeWidthNM.z * 0.78)
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
        // 1. Kodak Professional Portra Family (E-4050 / E-4040: VISION3 technology lineage, ultra-long shoulder, natural skin separation)
        CameraFilmStock(
            id: "kodak_portra_160",
            name: "Kodak Portra 160",
            processType: "C-41",
            isoSpeed: 160,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.56, 0.57, 0.55),
            dMinRGB: SIMD3<Float>(0.18, 0.56, 0.88),
            dMaxRGB: SIMD3<Float>(2.04, 2.44, 2.75),
            toeSoftnessRGB: SIMD3<Float>(0.44, 0.42, 0.40),
            shoulderSoftnessRGB: SIMD3<Float>(0.58, 0.55, 0.62),
            rmsGranularity: 6.5,
            sensPeakNM: SIMD3<Float>(642, 544, 444),
            sensWidthNM: SIMD3<Float>(28, 25, 24),
            greenRedCrossTalk: 0.035,
            dyePeakNM: SIMD3<Float>(652, 545, 446),
            dyeWidthNM: SIMD3<Float>(50, 41, 37),
            maskingCouplerEfficiency: 0.90,
            dirInterlayerMatrix: [1.14, -0.10, -0.04, -0.08, 1.13, -0.05, -0.03, -0.09, 1.12],
            halationReflectanceRGB: SIMD3<Float>(0.022, 0.004, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(1.5, -0.5)
        ),
        CameraFilmStock(
            id: "kodak_portra_400",
            name: "Kodak Portra 400",
            processType: "C-41",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.61, 0.62, 0.59),
            dMinRGB: SIMD3<Float>(0.20, 0.58, 0.90),
            dMaxRGB: SIMD3<Float>(2.15, 2.55, 2.86),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.36, 0.35),
            shoulderSoftnessRGB: SIMD3<Float>(0.50, 0.48, 0.55),
            rmsGranularity: 9.0,
            sensPeakNM: SIMD3<Float>(645, 545, 445),
            sensWidthNM: SIMD3<Float>(29, 26, 25),
            greenRedCrossTalk: 0.04,
            dyePeakNM: SIMD3<Float>(654, 546, 446),
            dyeWidthNM: SIMD3<Float>(51, 41, 37),
            maskingCouplerEfficiency: 0.90,
            dirInterlayerMatrix: [1.18, -0.13, -0.05, -0.10, 1.16, -0.06, -0.04, -0.11, 1.15],
            halationReflectanceRGB: SIMD3<Float>(0.028, 0.005, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(2.0, -0.5)
        ),
        CameraFilmStock(
            id: "kodak_portra_800",
            name: "Kodak Portra 800",
            processType: "C-41",
            isoSpeed: 800,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.66, 0.67, 0.63),
            dMinRGB: SIMD3<Float>(0.22, 0.60, 0.94),
            dMaxRGB: SIMD3<Float>(2.24, 2.64, 2.94),
            toeSoftnessRGB: SIMD3<Float>(0.33, 0.32, 0.36),
            shoulderSoftnessRGB: SIMD3<Float>(0.44, 0.42, 0.50),
            rmsGranularity: 12.0,
            sensPeakNM: SIMD3<Float>(648, 546, 447),
            sensWidthNM: SIMD3<Float>(31, 28, 26),
            greenRedCrossTalk: 0.045,
            dyePeakNM: SIMD3<Float>(656, 547, 448),
            dyeWidthNM: SIMD3<Float>(52, 42, 38),
            maskingCouplerEfficiency: 0.88,
            dirInterlayerMatrix: [1.22, -0.16, -0.06, -0.12, 1.20, -0.08, -0.05, -0.13, 1.18],
            halationReflectanceRGB: SIMD3<Float>(0.035, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(3.0, 0.5)
        ),

        // 2. Kodak Ektar 100 (E-4046: Cubic DIR couplers, ultra-high chroma, deep shadow Dmax, cyan-cobalt skies & punchy reds)
        CameraFilmStock(
            id: "kodak_ektar_100",
            name: "Kodak Ektar 100",
            processType: "C-41",
            isoSpeed: 100,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.76, 0.75, 0.77),
            dMinRGB: SIMD3<Float>(0.18, 0.55, 0.86),
            dMaxRGB: SIMD3<Float>(2.38, 2.78, 3.08),
            toeSoftnessRGB: SIMD3<Float>(0.18, 0.18, 0.17),
            shoulderSoftnessRGB: SIMD3<Float>(0.26, 0.26, 0.25),
            rmsGranularity: 5.5,
            sensPeakNM: SIMD3<Float>(654, 542, 441),
            sensWidthNM: SIMD3<Float>(23, 21, 20),
            greenRedCrossTalk: 0.012,
            dyePeakNM: SIMD3<Float>(658, 543, 443),
            dyeWidthNM: SIMD3<Float>(45, 37, 34),
            maskingCouplerEfficiency: 0.94,
            dirInterlayerMatrix: [1.38, -0.28, -0.10, -0.22, 1.34, -0.12, -0.08, -0.24, 1.32],
            halationReflectanceRGB: SIMD3<Float>(0.024, 0.004, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-1.0, 1.5)
        ),

        // 3. Kodak Consumer Negative: Gold 200 & UltraMax 400
        // Authentic gamma differential (`gamma_B < gamma_G < gamma_R`) + soft blue shoulder creates golden highlights & warm-amber shadows while keeping 18% grey neutral!
        CameraFilmStock(
            id: "kodak_gold_200",
            name: "Kodak Gold 200",
            processType: "C-41",
            isoSpeed: 200,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.72, 0.69, 0.61),
            dMinRGB: SIMD3<Float>(0.21, 0.59, 0.92),
            dMaxRGB: SIMD3<Float>(2.24, 2.58, 2.74),
            toeSoftnessRGB: SIMD3<Float>(0.26, 0.28, 0.38),
            shoulderSoftnessRGB: SIMD3<Float>(0.36, 0.40, 0.56),
            rmsGranularity: 10.5,
            sensPeakNM: SIMD3<Float>(647, 548, 448),
            sensWidthNM: SIMD3<Float>(30, 27, 26),
            greenRedCrossTalk: 0.055,
            dyePeakNM: SIMD3<Float>(650, 548, 449),
            dyeWidthNM: SIMD3<Float>(53, 43, 39),
            maskingCouplerEfficiency: 0.82,
            dirInterlayerMatrix: [1.24, -0.18, -0.06, -0.14, 1.21, -0.07, -0.05, -0.12, 1.17],
            halationReflectanceRGB: SIMD3<Float>(0.034, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(3.5, 1.0)
        ),
        CameraFilmStock(
            id: "kodak_ultramax_400",
            name: "Kodak UltraMax 400",
            processType: "C-41",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.74, 0.72, 0.66),
            dMinRGB: SIMD3<Float>(0.22, 0.61, 0.95),
            dMaxRGB: SIMD3<Float>(2.28, 2.63, 2.86),
            toeSoftnessRGB: SIMD3<Float>(0.25, 0.27, 0.34),
            shoulderSoftnessRGB: SIMD3<Float>(0.34, 0.36, 0.46),
            rmsGranularity: 13.0,
            sensPeakNM: SIMD3<Float>(649, 546, 446),
            sensWidthNM: SIMD3<Float>(31, 28, 26),
            greenRedCrossTalk: 0.05,
            dyePeakNM: SIMD3<Float>(652, 547, 447),
            dyeWidthNM: SIMD3<Float>(52, 42, 38),
            maskingCouplerEfficiency: 0.84,
            dirInterlayerMatrix: [1.28, -0.20, -0.08, -0.16, 1.25, -0.09, -0.06, -0.16, 1.22],
            halationReflectanceRGB: SIMD3<Float>(0.038, 0.007, 0.002),
            defaultEnlargerYMShift: SIMD2<Float>(2.5, 0.5)
        ),

        // 4. Fujifilm Color Negative (AF3-176E / AF3-144E: Patented 4th Cyan-Sensitive Layer at 505nm)
        // Neutral 18% grey concrete + airy pastel highlights + distinct mint/emerald green separation
        CameraFilmStock(
            id: "fujifilm_pro_400h",
            name: "Fujifilm Pro 400H",
            processType: "C-41 (4th Cyan Layer)",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.58, 0.63, 0.64),
            dMinRGB: SIMD3<Float>(0.19, 0.56, 0.88),
            dMaxRGB: SIMD3<Float>(2.08, 2.54, 2.88),
            toeSoftnessRGB: SIMD3<Float>(0.42, 0.34, 0.33),
            shoulderSoftnessRGB: SIMD3<Float>(0.56, 0.46, 0.44),
            rmsGranularity: 8.5,
            sensPeakNM: SIMD3<Float>(638, 539, 444),
            sensWidthNM: SIMD3<Float>(26, 23, 24),
            greenRedCrossTalk: 0.02,
            fourthCyanLayerStrength: 0.55,
            dyePeakNM: SIMD3<Float>(647, 541, 444),
            dyeWidthNM: SIMD3<Float>(48, 39, 36),
            maskingCouplerEfficiency: 0.91,
            dirInterlayerMatrix: [1.16, -0.12, -0.04, -0.20, 1.26, -0.06, -0.04, -0.12, 1.16],
            halationReflectanceRGB: SIMD3<Float>(0.024, 0.005, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-1.5, -1.5)
        ),
        CameraFilmStock(
            id: "fujifilm_superia_400",
            name: "Fujifilm Superia X-TRA 400",
            processType: "C-41 (4th Layer)",
            isoSpeed: 400,
            referenceKelvin: 5500,
            gammaRGB: SIMD3<Float>(0.67, 0.72, 0.71),
            dMinRGB: SIMD3<Float>(0.21, 0.58, 0.91),
            dMaxRGB: SIMD3<Float>(2.20, 2.66, 2.95),
            toeSoftnessRGB: SIMD3<Float>(0.32, 0.26, 0.27),
            shoulderSoftnessRGB: SIMD3<Float>(0.40, 0.35, 0.36),
            rmsGranularity: 11.5,
            sensPeakNM: SIMD3<Float>(640, 537, 442),
            sensWidthNM: SIMD3<Float>(27, 24, 24),
            greenRedCrossTalk: 0.025,
            fourthCyanLayerStrength: 0.48,
            dyePeakNM: SIMD3<Float>(648, 540, 443),
            dyeWidthNM: SIMD3<Float>(49, 40, 36),
            maskingCouplerEfficiency: 0.88,
            dirInterlayerMatrix: [1.24, -0.16, -0.08, -0.22, 1.30, -0.08, -0.05, -0.15, 1.20],
            halationReflectanceRGB: SIMD3<Float>(0.032, 0.006, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-1.5, 1.5)
        ),

        // 5. Kodak Vision3 Motion Picture Negative (ECN-2 & Remjet-Free C-41)
        CameraFilmStock(
            id: "kodak_vision3_50d",
            name: "Kodak Vision3 50D (5203)",
            processType: "ECN-2",
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.52, 0.53, 0.54),
            dMinRGB: SIMD3<Float>(0.16, 0.52, 0.84),
            dMaxRGB: SIMD3<Float>(1.96, 2.36, 2.68),
            toeSoftnessRGB: SIMD3<Float>(0.46, 0.44, 0.42),
            shoulderSoftnessRGB: SIMD3<Float>(0.64, 0.62, 0.60),
            rmsGranularity: 5.0,
            sensPeakNM: SIMD3<Float>(646, 544, 444),
            sensWidthNM: SIMD3<Float>(26, 24, 23),
            greenRedCrossTalk: 0.03,
            dyePeakNM: SIMD3<Float>(655, 545, 445),
            dyeWidthNM: SIMD3<Float>(49, 40, 36),
            maskingCouplerEfficiency: 0.92,
            dirInterlayerMatrix: [1.20, -0.15, -0.05, -0.12, 1.18, -0.06, -0.04, -0.12, 1.16],
            halationReflectanceRGB: SIMD3<Float>(0.004, 0.001, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-0.5, -0.5)
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
            toeSoftnessRGB: SIMD3<Float>(0.44, 0.43, 0.40),
            shoulderSoftnessRGB: SIMD3<Float>(0.62, 0.60, 0.56),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(648, 545, 442),
            sensWidthNM: SIMD3<Float>(27, 25, 23),
            greenRedCrossTalk: 0.035,
            dyePeakNM: SIMD3<Float>(656, 545, 444),
            dyeWidthNM: SIMD3<Float>(49, 40, 36),
            maskingCouplerEfficiency: 0.92,
            dirInterlayerMatrix: [1.21, -0.15, -0.06, -0.12, 1.19, -0.07, -0.05, -0.12, 1.17],
            halationReflectanceRGB: SIMD3<Float>(0.005, 0.001, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-2.5, -0.5)
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
            shoulderSoftnessRGB: SIMD3<Float>(0.60, 0.58, 0.56),
            rmsGranularity: 8.0,
            sensPeakNM: SIMD3<Float>(646, 545, 445),
            sensWidthNM: SIMD3<Float>(28, 26, 24),
            greenRedCrossTalk: 0.035,
            dyePeakNM: SIMD3<Float>(655, 545, 445),
            dyeWidthNM: SIMD3<Float>(50, 40, 36),
            maskingCouplerEfficiency: 0.92,
            dirInterlayerMatrix: [1.22, -0.16, -0.06, -0.13, 1.20, -0.07, -0.05, -0.13, 1.18],
            halationReflectanceRGB: SIMD3<Float>(0.006, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(0.5, -0.5)
        ),
        CameraFilmStock(
            id: "kodak_vision3_500t",
            name: "Kodak Vision3 500T (5219)",
            processType: "ECN-2",
            isoSpeed: 500,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            gammaRGB: SIMD3<Float>(0.55, 0.56, 0.59),
            dMinRGB: SIMD3<Float>(0.19, 0.56, 0.89),
            dMaxRGB: SIMD3<Float>(2.06, 2.46, 2.82),
            toeSoftnessRGB: SIMD3<Float>(0.40, 0.39, 0.36),
            shoulderSoftnessRGB: SIMD3<Float>(0.58, 0.56, 0.52),
            rmsGranularity: 10.0,
            sensPeakNM: SIMD3<Float>(650, 546, 442),
            sensWidthNM: SIMD3<Float>(29, 26, 24),
            greenRedCrossTalk: 0.04,
            dyePeakNM: SIMD3<Float>(657, 546, 444),
            dyeWidthNM: SIMD3<Float>(50, 41, 36),
            maskingCouplerEfficiency: 0.91,
            dirInterlayerMatrix: [1.23, -0.17, -0.06, -0.13, 1.21, -0.08, -0.05, -0.14, 1.19],
            halationReflectanceRGB: SIMD3<Float>(0.007, 0.002, 0.001),
            defaultEnlargerYMShift: SIMD2<Float>(-3.0, -0.5)
        ),
        CameraFilmStock(
            id: "cinestill_800t",
            name: "CineStill 800T (Remjet-Free C-41)",
            processType: "C-41 (Remjet Removed)",
            isoSpeed: 800,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            gammaRGB: SIMD3<Float>(0.65, 0.66, 0.69),
            dMinRGB: SIMD3<Float>(0.21, 0.58, 0.92),
            dMaxRGB: SIMD3<Float>(2.22, 2.60, 2.95),
            toeSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.31),
            shoulderSoftnessRGB: SIMD3<Float>(0.46, 0.45, 0.42),
            rmsGranularity: 11.5,
            sensPeakNM: SIMD3<Float>(650, 546, 442),
            sensWidthNM: SIMD3<Float>(29, 26, 24),
            greenRedCrossTalk: 0.04,
            dyePeakNM: SIMD3<Float>(657, 546, 444),
            dyeWidthNM: SIMD3<Float>(50, 41, 36),
            maskingCouplerEfficiency: 0.90,
            dirInterlayerMatrix: [1.25, -0.18, -0.07, -0.14, 1.22, -0.08, -0.06, -0.15, 1.21],
            halationReflectanceRGB: SIMD3<Float>(0.185, 0.036, 0.004),
            defaultEnlargerYMShift: SIMD2<Float>(-3.5, 0.5)
        ),
        CameraFilmStock(
            id: "cinestill_50d",
            name: "CineStill 50D (Remjet-Free C-41)",
            processType: "C-41 (Remjet Removed)",
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            gammaRGB: SIMD3<Float>(0.62, 0.63, 0.65),
            dMinRGB: SIMD3<Float>(0.18, 0.55, 0.87),
            dMaxRGB: SIMD3<Float>(2.14, 2.52, 2.84),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.37, 0.36),
            shoulderSoftnessRGB: SIMD3<Float>(0.50, 0.48, 0.46),
            rmsGranularity: 6.0,
            sensPeakNM: SIMD3<Float>(646, 544, 444),
            sensWidthNM: SIMD3<Float>(26, 24, 23),
            greenRedCrossTalk: 0.03,
            dyePeakNM: SIMD3<Float>(655, 545, 445),
            dyeWidthNM: SIMD3<Float>(49, 40, 36),
            maskingCouplerEfficiency: 0.91,
            dirInterlayerMatrix: [1.22, -0.16, -0.06, -0.13, 1.20, -0.07, -0.05, -0.13, 1.18],
            halationReflectanceRGB: SIMD3<Float>(0.145, 0.028, 0.003),
            defaultEnlargerYMShift: SIMD2<Float>(1.5, 0.5)
        ),

        // 6. Color Reversal Slide Films (E-6 Direct Positive Transparency)
        CameraFilmStock(
            id: "fujifilm_velvia_50",
            name: "Fujifilm Velvia 50 (RVP50)",
            processType: "E-6 Reversal",
            isoSpeed: 50,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.68, 1.65, 1.72),
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.10),
            dMaxRGB: SIMD3<Float>(3.65, 3.70, 3.55),
            toeSoftnessRGB: SIMD3<Float>(0.16, 0.16, 0.15),
            shoulderSoftnessRGB: SIMD3<Float>(0.20, 0.20, 0.18),
            rmsGranularity: 8.5,
            sensPeakNM: SIMD3<Float>(654, 540, 440),
            sensWidthNM: SIMD3<Float>(22, 20, 19),
            greenRedCrossTalk: 0.01,
            dyePeakNM: SIMD3<Float>(656, 540, 442),
            dyeWidthNM: SIMD3<Float>(44, 36, 33),
            dirInterlayerMatrix: [1.38, -0.26, -0.12, -0.22, 1.36, -0.14, -0.10, -0.24, 1.34],
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
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.09),
            dMaxRGB: SIMD3<Float>(3.38, 3.42, 3.32),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.22, 0.21),
            shoulderSoftnessRGB: SIMD3<Float>(0.26, 0.26, 0.25),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(648, 542, 442),
            sensWidthNM: SIMD3<Float>(24, 22, 21),
            greenRedCrossTalk: 0.02,
            dyePeakNM: SIMD3<Float>(652, 542, 444),
            dyeWidthNM: SIMD3<Float>(46, 38, 35),
            dirInterlayerMatrix: [1.24, -0.17, -0.07, -0.14, 1.23, -0.09, -0.06, -0.16, 1.22],
            halationReflectanceRGB: SIMD3<Float>(0.016, 0.003, 0.001)
        ),
        CameraFilmStock(
            id: "fujifilm_astia_100f",
            name: "Fujifilm Astia 100F (RAP100F)",
            processType: "E-6 Reversal",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.26, 1.28, 1.30),
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.09),
            dMaxRGB: SIMD3<Float>(3.22, 3.26, 3.18),
            toeSoftnessRGB: SIMD3<Float>(0.30, 0.30, 0.28),
            shoulderSoftnessRGB: SIMD3<Float>(0.36, 0.36, 0.34),
            rmsGranularity: 7.0,
            sensPeakNM: SIMD3<Float>(644, 543, 444),
            sensWidthNM: SIMD3<Float>(26, 24, 23),
            greenRedCrossTalk: 0.025,
            dyePeakNM: SIMD3<Float>(650, 543, 445),
            dyeWidthNM: SIMD3<Float>(48, 39, 36),
            dirInterlayerMatrix: [1.18, -0.13, -0.05, -0.11, 1.18, -0.07, -0.05, -0.12, 1.17],
            halationReflectanceRGB: SIMD3<Float>(0.015, 0.003, 0.001)
        ),
        CameraFilmStock(
            id: "kodak_ektachrome_e100",
            name: "Kodak Ektachrome E100",
            processType: "E-6 Reversal",
            isoSpeed: 100,
            referenceKelvin: 5500,
            isReversal: true,
            gammaRGB: SIMD3<Float>(1.46, 1.47, 1.52),
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.09),
            dMaxRGB: SIMD3<Float>(3.42, 3.46, 3.40),
            toeSoftnessRGB: SIMD3<Float>(0.20, 0.20, 0.19),
            shoulderSoftnessRGB: SIMD3<Float>(0.25, 0.25, 0.24),
            rmsGranularity: 7.5,
            sensPeakNM: SIMD3<Float>(648, 544, 446),
            sensWidthNM: SIMD3<Float>(24, 22, 21),
            greenRedCrossTalk: 0.02,
            dyePeakNM: SIMD3<Float>(654, 544, 446),
            dyeWidthNM: SIMD3<Float>(46, 38, 35),
            dirInterlayerMatrix: [1.26, -0.18, -0.08, -0.15, 1.24, -0.09, -0.07, -0.17, 1.24],
            halationReflectanceRGB: SIMD3<Float>(0.018, 0.003, 0.001)
        ),

        // 7. Silver Halide Black & White Negative
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
            dyePeakNM: SIMD3<Float>(648.0, 540.0, 444.0),
            defaultEnlargerYMShift: SIMD2<Float>(-1.5, 1.0)
        ),
        PrintFilmStock(
            id: "kodak_vision_2383",
            name: "Kodak Vision Color Print Film 2383 (ECP-2E)",
            gammaRGB: SIMD3<Float>(2.78, 2.82, 2.88),
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.08),
            dMaxRGB: SIMD3<Float>(3.15, 3.20, 3.10),
            dyePeakNM: SIMD3<Float>(655.0, 544.0, 446.0),
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, -1.0)
        ),
        PrintFilmStock(
            id: "kodak_premier_2393",
            name: "Kodak Vision Premier 2393 Print Film",
            gammaRGB: SIMD3<Float>(2.92, 2.95, 3.00),
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.08),
            dMaxRGB: SIMD3<Float>(3.35, 3.40, 3.30),
            dyePeakNM: SIMD3<Float>(656.0, 544.0, 445.0),
            defaultEnlargerYMShift: SIMD2<Float>(-1.5, -0.5)
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
