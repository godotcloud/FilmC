//
//  FilmSimulationParameters.swift
//  SpektraCam
//
//  Physical Darkroom & Photochemical Simulation Parameter Matrix for iPhone 13 Pro Max
//  Strictly based on physical optics, sensitometry (Hurter-Driffield), DIR couplers,
//  Beer-Lambert spectral transmittance, and RA-4 / motion picture print sensitometry.
//

import Foundation
import simd

// MARK: - 1. Exposure & Metering Modes
public enum MeteringPattern: Int, CaseIterable, Codable, Identifiable {
    case spot = 0
    case centerWeighted = 1
    case matrixEvaluative = 2
    case highlightProtect = 3
    case shadowPriority = 4
    case skinToneWeighted = 5
    case incidentMiddleGray = 6

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .spot: return "Spot (3%)"
        case .centerWeighted: return "Center-Weighted"
        case .matrixEvaluative: return "Matrix Evaluative"
        case .highlightProtect: return "Highlight Priority"
        case .shadowPriority: return "Shadow Priority (Zone III)"
        case .skinToneWeighted: return "Skin-Tone Anchor"
        case .incidentMiddleGray: return "18% Gray Locked"
        }
    }
}

// MARK: - 2. Optical Diffusion Filter Types
public enum OpticalDiffusionModel: Int, CaseIterable, Codable, Identifiable {
    case none = 0
    case blackProMist1_8 = 1
    case blackProMist1_4 = 2
    case blackProMist1_2 = 3
    case glimmerglass1_4 = 4
    case vintageSoftLens = 5

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .none: return "Off (Clean)"
        case .blackProMist1_8: return "Black Pro-Mist 1/8"
        case .blackProMist1_4: return "Black Pro-Mist 1/4"
        case .blackProMist1_2: return "Black Pro-Mist 1/2"
        case .glimmerglass1_4: return "Glimmerglass 1/4"
        case .vintageSoftLens: return "Spherical Soft Lens"
        }
    }
}

// MARK: - 5. Film Format Gate Sizes (Physical Dimensions in Millimeters)
public enum FilmFormatGate: Int, CaseIterable, Codable, Identifiable {
    case regular8mm = 0
    case super8mm = 1
    case regular16mm = 2
    case super16mm = 3
    case full35mmStill = 4
    case academy35mmCine = 5
    case imax65mm5Perf = 6
    case mediumFormat6x7 = 7

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .regular8mm: return "8mm Standard (4.8×3.5mm)"
        case .super8mm: return "Super 8 (5.79×4.01mm)"
        case .regular16mm: return "16mm (10.26×7.49mm)"
        case .super16mm: return "Super 16 (12.52×7.41mm)"
        case .full35mmStill: return "35mm Full Frame (36×24mm)"
        case .academy35mmCine: return "Super 35 Cine (24.89×18.66mm)"
        case .imax65mm5Perf: return "65mm 5-Perf (52.5×23mm)"
        case .mediumFormat6x7: return "6×7 Medium Format (69×56mm)"
        }
    }

    public var gateWidthMM: Float {
        switch self {
        case .regular8mm: return 4.80
        case .super8mm: return 5.79
        case .regular16mm: return 10.26
        case .super16mm: return 12.52
        case .full35mmStill: return 36.00
        case .academy35mmCine: return 24.89
        case .imax65mm5Perf: return 52.48
        case .mediumFormat6x7: return 69.00
        }
    }
}

// MARK: - 6. Print & Enlarger Pipeline Modes
public enum DarkroomPrintPipelineMode: Int, CaseIterable, Codable, Identifiable {
    case opticalEnlargerPrint = 0
    case directNegativeScan = 1

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .opticalEnlargerPrint: return "Optical Enlarger + Print Stock"
        case .directNegativeScan: return "Direct Lab Scanner"
        }
    }
}

public enum EnlargerLightSourceType: Int, CaseIterable, Codable, Identifiable {
    case tungstenHalogenDiffuser = 0
    case condenserPointSource = 1
    case narrowbandRGBLEDHead = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .tungstenHalogenDiffuser: return "3200K Halogen Dichroic Diffuser"
        case .condenserPointSource: return "Point-Source Condenser (Callier Effect)"
        case .narrowbandRGBLEDHead: return "Narrowband RGB LED Printer"
        }
    }
}

// MARK: - 7. Scanner Light Source & Target Color Space
public enum ScannerIlluminantModel: Int, CaseIterable, Codable, Identifiable {
    case d50ReferenceBroadband = 0
    case noritsuNarrowbandLED = 1
    case frontierColdCathode = 2
    case arriScanLaser = 3

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .d50ReferenceBroadband: return "CIE D50 Reference"
        case .noritsuNarrowbandLED: return "Noritsu HS-1800 LED"
        case .frontierColdCathode: return "Frontier SP-3000 CCFL"
        case .arriScanLaser: return "ARRISCAN Narrowband LED"
        }
    }
}

public enum TargetDisplayColorSpace: Int, CaseIterable, Codable, Identifiable {
    case sRGB = 0
    case displayP3 = 1
    case rec2020HLG = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .sRGB: return "sRGB (Rec.709)"
        case .displayP3: return "Apple Display P3"
        case .rec2020HLG: return "Rec.2020 HLG (10-bit HDR)"
        }
    }
}

// MARK: - Log Video Transfer Curve
public enum LogEncodingTransferFunction: Int, CaseIterable, Codable, Identifiable {
    case appleLogCompatible = 0
    case arriLogC3 = 1
    case cineonPrintingDensity = 2

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .appleLogCompatible: return "Apple Log (Compatible)"
        case .arriLogC3: return "ARRI LogC3 (EI 800)"
        case .cineonPrintingDensity: return "Kodak Cineon Log"
        }
    }
}

// MARK: - Full 7-Module Physical Darkroom Parameter Matrix
public struct FilmSimulationParameters: Codable, Equatable {
    public var negativeStockID: String = "kodak_portra_400"
    public var printStockID: String = "kodak_endura_premier"

    // ① 曝光与测光模块 (Exposure & Auto-Metering)
    public var exposureCompensationEV: Float = 0.0
    public var autoPrintExposureComp: Bool = true
    public var meteringPattern: MeteringPattern = .matrixEvaluative
    public var middleGrayReflectance: Float = 0.18
    public var opticalVignettingStrength: Float = 0.28
    public var lensFocalLengthMM: Float = 26.0
    public var sceneIlluminantKelvin: Float = 5500.0

    // ② 镜头光学柔焦与微光扩散 (Optical Diffusion & Bloom)
    public var diffusionModel: OpticalDiffusionModel = .blackProMist1_8
    public var bloomStrength: Float = 0.15
    public var bloomHighlightThreshold: Float = 0.75
    public var bloomRadiusMicrometers: Float = 140.0

    // ③ 显影化学与 DIR 耦合模块 (Development & DIR Couplers)
    public var pushPullStops: Float = 0.0
    public var dirCouplerAmount: Float = 1.0
    public var dirDiffusionRadiusMicrometers: Float = 18.0
    public var langmuirInhibitionRGB: SIMD3<Float> = SIMD3<Float>(0.85, 0.90, 0.80)
    public var developerExhaustion: Float = 0.06
    public var devTemperatureCelsius: Float = 37.8
    public var agitationIntensity: Float = 1.0
    public var bleachBypassAmount: Float = 0.0

    // ④ 乳剂散射与防光晕层 (In-Emulsion Scatter & Halation)
    public var halationEnabled: Bool = true
    public var halationStrengthRGB: SIMD3<Float> = SIMD3<Float>(0.035, 0.006, 0.001)
    public var halationRadiusMicrometers: SIMD3<Float> = SIMD3<Float>(210.0, 95.0, 45.0)
    public var halationHighlightThreshold: Float = 0.65
    public var halationBounces: Int = 2
    public var halationBounceDecay: Float = 0.35
    public var inEmulsionScatterMicrometers: Float = 6.0

    // ⑤ 随机多层粒子颗粒引擎 (Stochastic Multi-Layer Grain)
    public var grainEnabled: Bool = true
    public var filmFormatGate: FilmFormatGate = .full35mmStill
    public var grainStrength: Float = 1.0
    public var grainUniformity: Float = 1.0
    public var sublayerSpeedWeights: SIMD3<Float> = SIMD3<Float>(0.25, 0.50, 0.25)
    public var microStructureAcutance: Float = 1.0

    // ⑥ 暗房放大机与印相模块 (Enlarger & Print Stage)
    public var printPipelineMode: DarkroomPrintPipelineMode = .opticalEnlargerPrint
    public var enlargerLightSource: EnlargerLightSourceType = .tungstenHalogenDiffuser
    public var dichroicCyanCC: Float = 0.0
    public var dichroicMagentaCC: Float = 0.0
    public var dichroicYellowCC: Float = 0.0
    public var printExposureEV: Float = 0.0
    public var printGammaContrast: Float = 1.0
    public var preflashExposureEV: Float = -6.0
    public var preflashColorShiftYM: SIMD2<Float> = SIMD2<Float>(0.0, 0.0)
    public var bwMultigradeFilterGrade: Float = 2.5

    // ⑦ 扫描仪与输出色彩管理 (Scanner & Output)
    public var scannerIlluminant: ScannerIlluminantModel = .d50ReferenceBroadband
    public var scannerVeilingGlare: Float = 0.002
    public var scannerCCDLogResponse: Float = 0.5
    public var blackPointOffset: Float = 0.0
    public var whitePointOffset: Float = 0.0
    public var outputColorSpace: TargetDisplayColorSpace = .displayP3

    public init() {}
}

// MARK: - GPU Constant Buffer Packing (16-byte Aligned for Metal Compute Shaders)
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
    public var negativeToeShoulder: SIMD4<Float> // .xyz = shoulderSoftnessRGB, .w = mean toeSoftness
    public var printGammaRGB: SIMD4<Float>
    public var printDminRGB: SIMD4<Float>
    public var printDmaxRGB: SIMD4<Float>
    public var rmsGranularityRGB: SIMD4<Float>
    public var outputColorSpace: Int32
    public var isReversalOrMono: Int32
    public var bwMultigradeGrade: Float
    public var padding0: Float = 0.0
}
