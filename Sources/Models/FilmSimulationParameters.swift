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
    case spot = 0               // 点测光 (Central 3% spot)
    case centerWeighted = 1     // 中央重点测光 (70/30 center gaussian)
    case matrixEvaluative = 2   // 矩阵评价测光 (Multi-zone luminance/chromaticity)
    case highlightProtect = 3   // 高光保护测光 (ETTR / 99th percentile shoulder guard)
    case shadowPriority = 4     // 暗部优先测光 (Zone III toe guard)
    case skinToneWeighted = 5   // 肤色优先测光 (560-610nm spectral reflectance anchor)
    case incidentMiddleGray = 6 // 18% 中灰入射基准锁死

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
    case blackProMist1_8 = 1    // Tiffen Black Pro-Mist 1/8
    case blackProMist1_4 = 2    // Tiffen Black Pro-Mist 1/4
    case blackProMist1_2 = 3    // Tiffen Black Pro-Mist 1/2
    case glimmerglass1_4 = 4    // Glimmerglass 1/4 (High specular sparkle, low shadow lift)
    case vintageSoftLens = 5    // 经典球差柔焦镜头模拟 (Spherical aberration veil)

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
    case regular8mm = 0         // 4.8 x 3.5 mm
    case super8mm = 1           // 5.79 x 4.01 mm
    case regular16mm = 2        // 10.26 x 7.49 mm
    case super16mm = 3          // 12.52 x 7.41 mm
    case full35mmStill = 4      // 36.0 x 24.0 mm (135 Full Frame)
    case academy35mmCine = 5    // 21.95 x 16.0 mm (Super 35 / 4-Perf)
    case imax65mm5Perf = 6      // 52.48 x 23.01 mm (65mm 5-Perf)
    case mediumFormat6x7 = 7    // 69.0 x 56.0 mm (120 6x7 Medium Format)

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

    /// Physical gate width in millimeters (used to convert micrometer grain/halation into sensor pixels)
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
    case opticalEnlargerPrint = 0 // 负片 -> 暗房放大机 + CMY滤光片 -> 相纸/正片显影 -> 反射/透射扫描
    case directNegativeScan = 1   // 负片/反转片直扫 -> 扫描仪光谱积分 + 物理化学掩膜逆矩阵

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .opticalEnlargerPrint: return "Optical Enlarger + Print Stock"
        case .directNegativeScan: return "Direct Lab Scanner"
        }
    }
}

public enum EnlargerLightSourceType: Int, CaseIterable, Codable, Identifiable {
    case tungstenHalogenDiffuser = 0 // 3200K 卤素漫射色头 (Durst / Beseler Dichroic Diffuser)
    case condenserPointSource = 1    // Callier 效应高反差聚光头 (Condenser Head, Callier Q-factor ~1.32)
    case narrowbandRGBLEDHead = 2    // 现代窄带三色 LED 激光扩印头 (Fuji Frontier / Durst Theta)

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
    case d50ReferenceBroadband = 0   // CIE D50 标准宽谱观察/扫描光源
    case noritsuNarrowbandLED = 1    // Noritsu HS-1800 窄带三波长 RGB LED 光源
    case frontierColdCathode = 2     // Fujifilm SP-3000 冷阴极荧光灯谱线
    case arriScanLaser = 3           // ARRISCAN 电影窄带三基色 LED

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

// MARK: - Log Video Transfer Curve (iPhone 13 Pro Max Custom Dual-Track Log)
public enum LogEncodingTransferFunction: Int, CaseIterable, Codable, Identifiable {
    case appleLogCompatible = 0 // Apple Log 传递函数兼容曲线
    case arriLogC3 = 1          // ARRI LogC3 (EI 800) 传递函数
    case cineonPrintingDensity = 2 // Kodak Cineon 10-bit Printing Density Log

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
    // Stock Selection
    public var negativeStockID: String = "kodak_portra_400"
    public var printStockID: String = "kodak_endura_premier"

    // ① 曝光与测光模块 (Exposure & Auto-Metering)
    public var exposureCompensationEV: Float = 0.0          // [-4.0, +4.0] EV
    public var autoPrintExposureComp: Bool = true           // 负片曝光变化时自动反向补偿印相曝光以稳定中灰
    public var meteringPattern: MeteringPattern = .matrixEvaluative
    public var middleGrayReflectance: Float = 0.18          // 18% Gray 校准基准 [0.12, 0.25]
    public var opticalVignettingStrength: Float = 0.35      // cos^4(theta) 光学暗角强度 [0.0, 1.0]
    public var lensFocalLengthMM: Float = 26.0              // iPhone 13 Pro Max: 13mm / 26mm / 77mm
    public var sceneIlluminantKelvin: Float = 5500.0        // 场景色温 [2500K, 10000K]

    // ② 镜头光学柔焦与微光扩散 (Optical Diffusion & Bloom)
    public var diffusionModel: OpticalDiffusionModel = .blackProMist1_8
    public var bloomStrength: Float = 0.18                  // 微光扩散能量占比 [0.0, 1.0]
    public var bloomHighlightThreshold: Float = 0.75        // 触发微光散射的场景线性亮度阈值
    public var bloomRadiusMicrometers: Float = 140.0        // 镜头柔焦核物理半径 (um)

    // ③ 显影化学与 DIR 耦合模块 (Development & DIR Couplers)
    public var pushPullStops: Float = 0.0                   // 迫冲/减冲档位 [-2.0, +3.0] Stops
    public var dirCouplerAmount: Float = 1.0                // DIR 显影抑制剂浓度 [0.0, 2.0]
    public var dirDiffusionRadiusMicrometers: Float = 18.0  // DIR 邻接空间扩散半径 [2.0, 60.0] um (Eberhard 效应)
    public var langmuirInhibitionRGB: SIMD3<Float> = SIMD3<Float>(0.85, 0.90, 0.80) // Langmuir 等温抑制系数
    public var developerExhaustion: Float = 0.08            // 高密度区显影剂局部耗竭系数 [0.0, 0.5]
    public var devTemperatureCelsius: Float = 37.8          // C-41 标准 37.8°C (100°F) 显影温度微扰 [34.0, 42.0]
    public var agitationIntensity: Float = 1.0              // 搅动强度对边缘微反差与 γ 的影响 [0.5, 1.5]
    public var bleachBypassAmount: Float = 0.0              // 留银冲洗比例 (ENR / Silver Retention) [0.0, 1.0]

    // ④ 乳剂散射与防光晕层 (In-Emulsion Scatter & Halation)
    public var halationEnabled: Bool = true
    public var halationStrengthRGB: SIMD3<Float> = SIMD3<Float>(0.035, 0.006, 0.001) // R/G/B 防光晕层反射分数
    public var halationRadiusMicrometers: SIMD3<Float> = SIMD3<Float>(210.0, 95.0, 45.0) // 各层光晕物理半径 (um)
    public var halationHighlightThreshold: Float = 0.65     // 中间调光晕保护阈值 (hal_mids)
    public var halationBounces: Int = 2                     // 片基多次反射次数 [1, 4]
    public var halationBounceDecay: Float = 0.35            // 每次片基反射的能量衰减率
    public var inEmulsionScatterMicrometers: Float = 6.5    // Frieser 乳剂内部米氏散射半径 (um)

    // ⑤ 随机多层粒子颗粒引擎 (Stochastic Multi-Layer Grain)
    public var grainEnabled: Bool = true
    public var filmFormatGate: FilmFormatGate = .full35mmStill
    public var grainStrength: Float = 1.0                   // 全局颗粒强度缩放 [0.0, 2.5]
    public var grainUniformity: Float = 1.0                 // 高密度区颗粒抑制均匀度 [0.5, 1.5]
    public var sublayerSpeedWeights: SIMD3<Float> = SIMD3<Float>(0.25, 0.50, 0.25) // Fast / Mid / Slow 子层占比
    public var microStructureAcutance: Float = 1.0          // 染料云微结构边缘锐度 [0.0, 2.0]

    // ⑥ 暗房放大机与印相模块 (Enlarger & Print Stage)
    public var printPipelineMode: DarkroomPrintPipelineMode = .opticalEnlargerPrint
    public var enlargerLightSource: EnlargerLightSourceType = .tungstenHalogenDiffuser
    public var dichroicCyanCC: Float = 0.0                  // 青色双色滤光片 [-100, +100] CC
    public var dichroicMagentaCC: Float = 0.0               // 品红双色滤光片 [-100, +100] CC (绿/品红轴)
    public var dichroicYellowCC: Float = 0.0                // 黄色双色滤光片 [-100, +100] CC (冷/暖色温轴)
    public var printExposureEV: Float = 0.0                 // 放大机印相曝光时间偏移 [-3.0, +3.0] EV
    public var printGammaContrast: Float = 1.0              // 相纸显影反差系数 [0.7, 1.4]
    public var preflashExposureEV: Float = -6.0             // 相纸预闪光曝光量 (高光保留, -6.0 为关闭, [-6.0, -1.0])
    public var preflashColorShiftYM: SIMD2<Float> = SIMD2<Float>(0.0, 0.0) // 预闪光滤色片偏移
    public var bwMultigradeFilterGrade: Float = 2.5         // Ilford Multigrade 黑白相纸反差号数 [0.0, 5.0]

    // ⑦ 扫描仪与输出色彩管理 (Scanner & Output)
    public var scannerIlluminant: ScannerIlluminantModel = .d50ReferenceBroadband
    public var scannerVeilingGlare: Float = 0.004           // 扫描仪镜头杂散光眩光占比 [0.0, 0.03]
    public var scannerCCDLogResponse: Float = 0.5           // 扫描仪光电耦合线性/对数混合权重 [0.0, 1.0]
    public var blackPointOffset: Float = 0.0                // 扫描黑位偏移 [-0.05, +0.05]
    public var whitePointOffset: Float = 0.0                // 扫描白位增益偏移 [-0.10, +0.10]
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
    public var printGammaRGB: SIMD4<Float>
    public var printDminRGB: SIMD4<Float>
    public var printDmaxRGB: SIMD4<Float>
    public var rmsGranularityRGB: SIMD4<Float>
    public var outputColorSpace: Int32
    public var isReversalOrMono: Int32 // 0 = Color Neg, 1 = Color Reversal, 2 = B&W Neg
    public var bwMultigradeGrade: Float
    public var padding0: Float = 0.0
}
