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
    public var bloomHighlightThreshold: Float = 0.72
    public var bloomRadiusMicrometers: Float = 150.0

    // Stage 2b: Emulsion Scatter & Remjet/Base Halation
    public var halationEnabled: Bool = true
    public var halationStrengthRGB: SIMD3<Float> = SIMD3<Float>(0.028, 0.005, 0.001)
    public var halationRadiusMicrometers: SIMD3<Float> = SIMD3<Float>(210.0, 95.0, 45.0)
    public var inEmulsionScatterMicrometers: Float = 5.5

    // Stage 3: Chemical Development, Push/Pull & DIR Couplers
    public var pushPullStops: Float = 0.0
    public var devTemperatureCelsius: Float = 37.8
    public var agitationIntensity: Float = 1.0
    public var dirCouplerAmount: Float = 1.0
    public var dirDiffusionRadiusMicrometers: Float = 18.0
    public var developerExhaustion: Float = 0.12
    public var bleachBypassAmount: Float = 0.0

    // Stage 4: Multi-Layer Silver Halide Grain
    public var grainEnabled: Bool = true
    public var grainStrength: Float = 1.0
    public var grainUniformity: Float = 1.0

    // Stage 5: Virtual Enlarger & Print Stock
    public var printPipelineMode: DarkroomPrintPipelineMode = .opticalEnlargerAndPrintStock
    public var enlargerLightSource: EnlargerLightSourceType = .halogenDichroicDiffuser
    public var dichroicCyanCC: Float = 0.0
    public var dichroicMagentaCC: Float = 0.0
    public var dichroicYellowCC: Float = 0.0
    public var printExposureEV: Float = 0.0
    public var printGammaContrast: Float = 1.0
    public var preflashExposureEV: Float = -6.0
    public var bwMultigradeFilterGrade: Float = 2.5

    // Stage 6: Lab Scanner & Display Output
    public var outputColorSpace: TargetDisplayColorSpace = .displayP3
    public var scannerVeilingGlare: Float = 0.004
    public var blackPointOffset: Float = 0.0
    public var whitePointOffset: Float = 0.0

    // Stage 7: Master Cinematography Physics (Wong Kar-wai / Christopher Doyle & Johnnie To / Cheng Siu-keung)
    /// Ambient shadow fluorescent/mercury-vapor green (+) vs velvet crimson/magenta (-) split lighting (`-1.0 ... +1.0`)
    public var shadowSplitGreenMagenta: Float = 0.0
    /// Ambient night sky / HMI electric steel-blue (+) vs warm mahogany (-) shadow split (`-1.0 ... +1.0`)
    public var shadowSplitTealRed: Float = 0.0
    /// Practical 2700K tungsten lamp & sodium-vapor amber-gold highlight glow (`-1.0 ... +1.0`)
    public var highlightWarmthGold: Float = 0.0
    /// E-6 / ECN-2 Cross-Processing S-curve channel warp (`0.0 ... 1.0`)
    public var crossProcessAmount: Float = 0.0
    /// Cheng Siu-keung / Milkyway Image hard-light chiaroscuro shadow toe & micro-contrast (`0.0 ... 1.0`)
    public var chiaroscuroContrast: Float = 0.0
    /// Christopher Doyle Kinoptik Tegea 9.8mm + Century 6.8mm wide-angle barrel distortion & edge chromatic dispersion (`0.0 ... 1.0`)
    public var wideAngleDistortion: Float = 0.0
    /// Christopher Doyle 6fps–12fps Step-Printing optical printer temporal shutter trail (`0.0 ... 1.0`)
    public var stepPrintTrail: Float = 0.0

    public init() {}
}

public struct HKCinemaRecipe: Identifiable {
    public let id: String
    public let title: String
    public let directorAndYear: String
    public let stockSummary: String
    public let buildParameters: (Float) -> FilmSimulationParameters

    public init(
        id: String,
        title: String,
        directorAndYear: String,
        stockSummary: String,
        buildParameters: @escaping (Float) -> FilmSimulationParameters
    ) {
        self.id = id
        self.title = title
        self.directorAndYear = directorAndYear
        self.stockSummary = stockSummary
        self.buildParameters = buildParameters
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
            id: "wkw_in_the_mood_for_love_2000",
            title: "王家卫《花样年华·2000原版》",
            directorAndYear: "In the Mood for Love (2000 Theatrical · 杜可风/李屏宾)",
            stockSummary: "5279 500T · 丝绒绯红与钨丝流金 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.85
                p.dirCouplerAmount = 1.48
                p.dichroicYellowCC = 16.0
                p.dichroicMagentaCC = 10.0
                p.dichroicCyanCC = -14.0
                p.shadowSplitGreenMagenta = -0.35
                p.shadowSplitTealRed = -0.45
                p.highlightWarmthGold = 0.68
                p.chiaroscuroContrast = 0.25
                p.printGammaContrast = 1.06
                p.diffusionModel = .vintageSoftLens
                p.bloomStrength = 0.16
                p.bloomHighlightThreshold = 0.68
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.12, 0.028, 0.003)
                p.opticalVignettingStrength = 0.42
                p.grainStrength = 1.12
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_in_the_mood_for_love_2020",
            title: "王家卫《花样年华·4K修复青金》",
            directorAndYear: "In the Mood for Love (2020 Criterion 4K · 怀旧苔绿流金)",
            stockSummary: "5279 500T · 暗部苔绿+高光流金 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.85
                p.dirCouplerAmount = 1.42
                p.dichroicYellowCC = 14.0
                p.dichroicMagentaCC = -8.0
                p.dichroicCyanCC = 4.0
                p.shadowSplitGreenMagenta = 0.65
                p.shadowSplitTealRed = 0.20
                p.highlightWarmthGold = 0.72
                p.chiaroscuroContrast = 0.22
                p.printGammaContrast = 1.06
                p.diffusionModel = .vintageSoftLens
                p.bloomStrength = 0.22
                p.bloomHighlightThreshold = 0.68
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.10, 0.025, 0.003)
                p.opticalVignettingStrength = 0.40
                p.grainStrength = 1.10
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_chungking_express",
            title: "王家卫《重庆森林》",
            directorAndYear: "Chungking Express (1994 · 杜可风/刘伟强 · 汞灯快餐店+8fps抽帧)",
            stockSummary: "EXR 5298 500T · 荧光翠青暗部+暖金霓虹 → 2383",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_vision_2383"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.00
                p.dirCouplerAmount = 1.38
                p.dichroicYellowCC = 8.0
                p.dichroicMagentaCC = -14.0
                p.dichroicCyanCC = 8.0
                p.shadowSplitGreenMagenta = 0.75
                p.shadowSplitTealRed = 0.45
                p.highlightWarmthGold = 0.62
                p.crossProcessAmount = 0.25
                p.chiaroscuroContrast = 0.15
                p.stepPrintTrail = 0.0
                p.diffusionModel = .blackProMist1_4
                p.bloomStrength = 0.16
                p.bloomHighlightThreshold = 0.66
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.11, 0.030, 0.004)
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.25
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_fallen_angels",
            title: "王家卫《堕落天使》",
            directorAndYear: "Fallen Angels (1995 · 杜可风 Kinoptik 9.8mm + 反转负冲)",
            stockSummary: "EXR 5298 (+1.3 Push) · 9.8mm广角畸变+妖异翠绿霓虹 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.25
                p.dirCouplerAmount = 1.48
                p.dichroicYellowCC = 4.0
                p.dichroicMagentaCC = -18.0
                p.dichroicCyanCC = 12.0
                p.shadowSplitGreenMagenta = 0.85
                p.shadowSplitTealRed = 0.55
                p.highlightWarmthGold = 0.58
                p.crossProcessAmount = 0.55
                p.chiaroscuroContrast = 0.35
                p.wideAngleDistortion = 0.0
                p.stepPrintTrail = 0.0
                p.printGammaContrast = 1.08
                p.diffusionModel = .blackProMist1_2
                p.bloomStrength = 0.18
                p.halationEnabled = true
                p.halationStrengthRGB = SIMD3<Float>(0.15, 0.038, 0.005)
                p.opticalVignettingStrength = 0.54
                p.grainStrength = 1.38
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_happy_together_color",
            title: "王家卫《春光乍泄·流金》",
            directorAndYear: "Happy Together (1997 · 布宜诺斯艾利斯探戈浓金琥珀)",
            stockSummary: "5279 500T + E-6负冲偏移 · 浓金暖黄 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.10
                p.dirCouplerAmount = 1.42
                p.dichroicYellowCC = 24.0
                p.dichroicMagentaCC = 4.0
                p.dichroicCyanCC = -12.0
                p.shadowSplitGreenMagenta = 0.15
                p.shadowSplitTealRed = -0.20
                p.highlightWarmthGold = 0.85
                p.crossProcessAmount = 0.30
                p.chiaroscuroContrast = 0.25
                p.bleachBypassAmount = 0.15
                p.diffusionModel = .glimmerglass1_4
                p.bloomStrength = 0.16
                p.opticalVignettingStrength = 0.38
                p.grainStrength = 1.28
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_happy_together_bw",
            title: "王家卫《春光乍泄·黑白》",
            directorAndYear: "Happy Together (1997 · 粗颗粒高反差银盐黑白)",
            stockSummary: "Double-X 5222 (+1.2 Push) → Ilford G3.8",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_double_x_5222"
                p.printStockID = "ilford_multigrade_fb"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.20
                p.chiaroscuroContrast = 0.35
                p.enlargerLightSource = .condenserPointSource
                p.bwMultigradeFilterGrade = 3.8
                p.diffusionModel = .blackProMist1_8
                p.bloomStrength = 0.20
                p.opticalVignettingStrength = 0.40
                p.grainStrength = 1.42
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_days_of_being_wild",
            title: "王家卫《阿飞正传》",
            directorAndYear: "Days of Being Wild (1990 · 杜可风热带雨林青碧滤镜)",
            stockSummary: "EXR 5298 · 60年代湿热翡翠青绿 → 2383",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_vision_2383"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.75
                p.dirCouplerAmount = 1.25
                p.dichroicYellowCC = 6.0
                p.dichroicMagentaCC = -20.0
                p.dichroicCyanCC = 14.0
                p.shadowSplitGreenMagenta = 0.80
                p.shadowSplitTealRed = 0.60
                p.highlightWarmthGold = 0.22
                p.crossProcessAmount = 0.15
                p.chiaroscuroContrast = 0.20
                p.bleachBypassAmount = 0.10
                p.diffusionModel = .vintageSoftLens
                p.bloomStrength = 0.16
                p.opticalVignettingStrength = 0.38
                p.grainStrength = 1.15
                return p
            }
        ),
        HKCinemaRecipe(
            id: "wkw_2046_grandmaster",
            title: "王家卫《2046 / 一代宗师》",
            directorAndYear: "2046 & The Grandmaster (Panavision 变形宽银幕 · 黑金留银)",
            stockSummary: "Vision3 500T + 30% Bleach Bypass · 漆黑鎏金 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision3_500t"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.90
                p.bleachBypassAmount = 0.30
                p.dichroicYellowCC = 16.0
                p.dichroicMagentaCC = 2.0
                p.dichroicCyanCC = -8.0
                p.shadowSplitGreenMagenta = 0.10
                p.shadowSplitTealRed = 0.15
                p.highlightWarmthGold = 0.75
                p.chiaroscuroContrast = 0.45
                p.printGammaContrast = 1.08
                p.diffusionModel = .blackProMist1_4
                p.bloomStrength = 0.22
                p.opticalVignettingStrength = 0.38
                p.grainStrength = 1.10
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_ptu_night_patrol",
            title: "杜琪峰《PTU 机动部队》",
            directorAndYear: "PTU (2003 · 郑兆强 · 尖沙咀冷电蓝暗夜顶光 + 留银冲洗)",
            stockSummary: "5279 500T + 42% Bleach · 电光冷蓝暗夜+钠灯高反差 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "kodak_vision_500t_5279"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 1.05
                p.bleachBypassAmount = 0.42
                p.dichroicYellowCC = -14.0
                p.dichroicMagentaCC = -4.0
                p.dichroicCyanCC = 14.0
                p.shadowSplitGreenMagenta = 0.15
                p.shadowSplitTealRed = 0.80
                p.highlightWarmthGold = 0.30
                p.chiaroscuroContrast = 0.65
                p.printGammaContrast = 1.12
                p.enlargerLightSource = .condenserPointSource
                p.diffusionModel = .blackProMist1_8
                p.bloomStrength = 0.16
                p.bloomHighlightThreshold = 0.60
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.22
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_election_exiled",
            title: "杜琪峰《放·逐 / 黑社会》",
            directorAndYear: "Exiled & Election (2005–2006 · 郑兆强 · 澳门古铜金绿留银)",
            stockSummary: "Eterna Vivid 8547 + 38% Bleach · 古铜黄绿硬光 → 2393",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "fujifilm_eterna_vivid_500t_8547"
                p.printStockID = "kodak_premier_2393"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.95
                p.bleachBypassAmount = 0.38
                p.dichroicYellowCC = 16.0
                p.dichroicMagentaCC = -4.0
                p.dichroicCyanCC = -6.0
                p.shadowSplitGreenMagenta = 0.25
                p.shadowSplitTealRed = -0.15
                p.highlightWarmthGold = 0.65
                p.crossProcessAmount = 0.10
                p.chiaroscuroContrast = 0.55
                p.printGammaContrast = 1.10
                p.opticalVignettingStrength = 0.36
                p.grainStrength = 1.20
                return p
            }
        ),
        HKCinemaRecipe(
            id: "jto_the_mission",
            title: "杜琪峰《枪火 / 暗战》",
            directorAndYear: "The Mission (1999 · 郑兆强 · 荃湾商场冷蓝钢灰枪战)",
            stockSummary: "EXR 5298 + 30% Bleach · 冷钢灰蓝高反差 → 2383",
            buildParameters: { focalMM in
                var p = FilmSimulationParameters()
                p.lensFocalLengthMM = focalMM
                p.negativeStockID = "eastman_exr_500t_5298"
                p.printStockID = "kodak_vision_2383"
                p.filmFormatGate = .super35Motion
                p.pushPullStops = 0.80
                p.bleachBypassAmount = 0.30
                p.dichroicYellowCC = -15.0
                p.dichroicMagentaCC = -2.0
                p.dichroicCyanCC = 12.0
                p.shadowSplitGreenMagenta = 0.05
                p.shadowSplitTealRed = 0.65
                p.highlightWarmthGold = 0.15
                p.chiaroscuroContrast = 0.45
                p.printGammaContrast = 1.08
                p.opticalVignettingStrength = 0.32
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
    public var chiaroscuroContrast: Float

    /// `x = shadowSplitGreenMagenta`, `y = shadowSplitTealRed`, `z = highlightWarmthGold`, `w = crossProcessAmount`
    public var cinemaSplitTone: SIMD4<Float>
    /// `x = wideAngleDistortion`, `y = stepPrintTrail`, `z = reserved`, `w = reserved`
    public var cinemaOpticsAndStep: SIMD4<Float>
}
