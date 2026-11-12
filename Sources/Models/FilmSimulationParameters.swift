//
//  FilmSimulationParameters.swift
//  SpektraCam
//
//  Core Darkroom Parameter Models & Metal Uniform Layout
//  (FilmStockDatabase & Stock Profiles reside in `Sources/Models/FilmStockDatabase.swift`)
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
    public var negativeShoulderRGB: SIMD4<Float>
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
