//
//  FilmSimulationParameters.swift
//  SpektraCam
//
//  Core Darkroom Parameter Models, Metal Uniform Layout & Classic Hong Kong Cinema Master Recipes
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

    public var shortBadge: String {
        switch self {
        case .fullFrame35mm:   return "35mm"
        case .halfFrame35mm:   return "Half"
        case .mediumFormat645: return "645"
        case .mediumFormat67:  return "6×7"
        case .super35Motion:   return "S35"
        }
    }

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

// MARK: - Classic Hong Kong Cinema Physical Darkroom Recipes (Wong Kar-wai & Johnnie To)
// Every recipe configures authentic photochemical pipeline parameters (Stock + Print Film + Push + Printer Lights + Bleach Bypass + Halation)
public struct HKCinemaRecipe: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let directorAndYear: String
    public let stockSummary: String
    public let buildParameters: (Float) -> FilmSimulationParameters

    public static func == (lhs: HKCinemaRecipe, rhs: HKCinemaRecipe) -> Bool {
        lhs.id == rhs.id
    }
}

extension FilmSimulationParameters {
    public mutating func applyHKCinemaRecipe(_ recipe: HKCinemaRecipe) {
        self = recipe.buildParameters(self.lensFocalLengthMM)
    }
}

public enum HKCinemaRecipeDatabase {
    public static let recipes: [HKCinemaRecipe] = [
        HKCinemaRecipe(
            id: "standard_lab_neutral",
            title: "Standard Lab Neutral",
            directorAndYear: "0 CC Reference · Standard Process",
            stockSummary: "Portra 400 → Endura",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_in_the_mood_for_love",
            title: "王家卫《花样年华》",
            directorAndYear: "In the Mood for Love (2000 · 杜可风)",
            stockSummary: "5279 500T (+0.85 Push) → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.85
                p.dirCouplerAmount = 1.45
                // Lush cheongsam crimson-red & warm tungsten amber-gold (+Y, +M, -C)
                p.dichroicYellowCC = 18.0
                p.dichroicMagentaCC = 9.0
                p.dichroicCyanCC = -12.0
                p.printGammaContrast = 1.06
                p.diffusionModel = .vintageSoftLens
                p.bloomStrength = 0.22
                p.bloomHighlightThreshold = 0.60
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.11, 0.025, 0.003)
                p.opticalVignettingStrength = 0.38
                p.grainStrength = 1.10
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_chungking_express",
            title: "王家卫《重庆森林》",
            directorAndYear: "Chungking Express (1994 · 杜可风/刘伟强)",
            stockSummary: "EXR 5298 500T (+1.0 Push) → 2383",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_vision_2383"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.00
                p.dirCouplerAmount = 1.35
                // Fluorescent mercury-vapor emerald-cyan shadows + warm golden highlights
                p.dichroicYellowCC = 10.0
                p.dichroicMagentaCC = -18.0
                p.dichroicCyanCC = 10.0
                p.diffusionModel = .blackProMist1_4
                p.bloomStrength = 0.25
                p.bloomHighlightThreshold = 0.56
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.10, 0.028, 0.004)
                p.opticalVignettingStrength = 0.35
                p.grainStrength = 1.25
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_fallen_angels",
            title: "王家卫《堕落天使》",
            directorAndYear: "Fallen Angels (1995 · 杜可风广角暗夜)",
            stockSummary: "EXR 5298 (+1.25 Push) → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.25
                p.dirCouplerAmount = 1.45
                p.dichroicYellowCC = 6.0
                p.dichroicMagentaCC = -22.0
                p.dichroicCyanCC = 14.0
                p.printGammaContrast = 1.08
                p.diffusionModel = .blackProMist1_2
                p.bloomStrength = 0.28
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.14, 0.035, 0.005)
                p.opticalVignettingStrength = 0.48
                p.grainStrength = 1.35
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_happy_together_color",
            title: "王家卫《春光乍泄·流金》",
            directorAndYear: "Happy Together (1997 · 浓金琥珀印相)",
            stockSummary: "5279 500T (+1.1 Push) → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.10
                p.dirCouplerAmount = 1.40
                // Intense Buenos Aires golden-amber warmth (+26 Y, +5 M, -14 C)
                p.dichroicYellowCC = 26.0
                p.dichroicMagentaCC = 5.0
                p.dichroicCyanCC = -14.0
                p.bleachBypassAmount = 0.16
                p.diffusionModel = .glimmerglass1_4
                p.bloomStrength = 0.22
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.25
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_happy_together_bw",
            title: "王家卫《春光乍泄·黑白》",
            directorAndYear: "Happy Together (1997 · 高反差银盐)",
            stockSummary: "Double-X 5222 (+1.1 Push) → Ilford G3.5",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_double_x_5222"
                p.printStockID = "ilford_multigrade_fb"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.10
                p.enlargerLightSource = .condenserPointSource
                p.bwMultigradeFilterGrade = 3.5
                p.diffusionModel = .blackProMist1_8
                p.bloomStrength = 0.18
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.35
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_2046_grandmaster",
            title: "王家卫《2046 / 一代宗师》",
            directorAndYear: "2046 & The Grandmaster (黑金留银)",
            stockSummary: "Vision3 500T + 28% Bleach → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision3_500t"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.85
                p.bleachBypassAmount = 0.28
                p.dichroicYellowCC = 18.0
                p.dichroicMagentaCC = 3.0
                p.dichroicCyanCC = -8.0
                p.printGammaContrast = 1.08
                p.diffusionModel = .blackProMist1_4
                p.bloomStrength = 0.22
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.10
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_ptu_night_patrol",
            title: "杜琪峰《PTU 机动部队》",
            directorAndYear: "PTU (2003 · 郑兆强 · 银河映像冷峻暗夜)",
            stockSummary: "5279 500T + 45% Bleach → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.00
                p.bleachBypassAmount = 0.45
                p.dichroicYellowCC = -14.0
                p.dichroicMagentaCC = -6.0
                p.dichroicCyanCC = 14.0
                p.printGammaContrast = 1.10
                p.enlargerLightSource = .condenserPointSource
                p.diffusionModel = .blackProMist1_8
                p.bloomStrength = 0.16
                p.bloomHighlightThreshold = 0.60
                p.opticalVignettingStrength = 0.34
                p.grainStrength = 1.20
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_election_exiled",
            title: "杜琪峰《黑社会 / 放·逐》",
            directorAndYear: "Election & Exiled (2005–2006 · 古铜留银)",
            stockSummary: "Eterna Vivid 8547 + 38% Bleach → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "fujifilm_eterna_vivid_500t_8547"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.90
                p.bleachBypassAmount = 0.38
                p.dichroicYellowCC = 15.0
                p.dichroicMagentaCC = -4.0
                p.dichroicCyanCC = -5.0
                p.printGammaContrast = 1.08
                p.opticalVignettingStrength = 0.34
                p.grainStrength = 1.18
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_the_mission",
            title: "杜琪峰《枪火 / 暗战》",
            directorAndYear: "The Mission (1999 · 冷蓝钢灰枪战)",
            stockSummary: "EXR 5298 + 28% Bleach → 2383",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_vision_2383"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.75
                p.bleachBypassAmount = 0.28
                p.dichroicYellowCC = -15.0
                p.dichroicMagentaCC = -3.0
                p.dichroicCyanCC = 12.0
                p.printGammaContrast = 1.08
                p.opticalVignettingStrength = 0.30
                p.grainStrength = 1.15
                return p
            }
        )
    ]
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
