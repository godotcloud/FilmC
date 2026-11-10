//
//  FilmStockDatabase.swift
//  SpektraCam
//
//  Built-in Laboratory Sensitometric & Spectral Database (380nm - 780nm)
//  Covers 22 Classic Camera Negative / Motion Picture / Reversal / B&W Stocks
//  and 5 Darkroom Print Papers / Motion Picture Print Films.
//

import Foundation
import simd

public enum FilmProcessCategory: String, Codable, CaseIterable {
    case c41ColorNegative = "C-41 Color Negative"
    case ecn2MotionPicture = "ECN-2 / Cine Negative"
    case e6K14ColorReversal = "E-6 / K-14 Slide Reversal"
    case bwSilverNegative = "B&W Silver Gelatin"
    case ra4AndCinePrint = "RA-4 Paper & Print Film"
}

/// Standardized Laboratory Datasheet Profile (Spectral 380-780nm @ 5nm step = 81 bins)
public struct FilmStockProfile: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let category: FilmProcessCategory
    public let isoSpeed: Float
    public let referenceKelvin: Float
    public let hasAntiHalationRemjet: Bool
    public let isMonochrome: Bool
    public let isReversal: Bool

    // Hurter-Driffield (H-D) Sensitometric Curve Parameters per Layer (R, G, B)
    public let dMinRGB: SIMD3<Float>
    public let dMaxRGB: SIMD3<Float>
    public let gammaRGB: SIMD3<Float>
    public let shoulderSoftnessRGB: SIMD3<Float>
    public let toeSoftnessRGB: SIMD3<Float>

    // Spectral Sensitivity Peak Centres (nm) & Bandwidths (nm) for Analytical 81-Band Reconstruction
    public let peakWavelengthsNM: SIMD3<Float>
    public let spectralWidthsNM: SIMD3<Float>
    public let crossTalkBlueToRedGreen: SIMD2<Float>

    // Normalized Dye Spectral Absorption Peaks & Side-Absorption (Unmixed + Masking Couplers)
    public let dyePeakWavelengthsNM: SIMD3<Float>
    public let dyeWidthsNM: SIMD3<Float>
    public let maskingCouplerNegativeAbsorption: SIMD3<Float>

    // Micro-Structure, Grain & Optical Scatter
    public let rmsGranularity: Float
    public let mtf50CyclesPerMM: Float
    public let halationReflectanceRGB: SIMD3<Float>
    public let halationSigmaMicrometers: SIMD3<Float>
    public let dirInterlayerMatrix: [Float]
    public let defaultEnlargerYMShift: SIMD2<Float>

    /// Generates the 81-wavelength (380nm to 780nm, 5nm step) spectral sensitivity array S_R(λ), S_G(λ), S_B(λ)
    public func evaluateSpectralSensitivities81() -> [SIMD3<Float>] {
        var table = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: 81)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            let dR: Float = (lambda - peakWavelengthsNM.x) / spectralWidthsNM.x
            let dG: Float = (lambda - peakWavelengthsNM.y) / spectralWidthsNM.y
            let dB: Float = (lambda - peakWavelengthsNM.z) / spectralWidthsNM.z

            let sB: Float = expf(-0.5 * dB * dB)
            let bDiff: Float = (lambda - 425.0) / 28.0
            let blueLeak: Float = expf(-0.5 * bDiff * bDiff)
            let sG: Float = expf(-0.5 * dG * dG) + crossTalkBlueToRedGreen.y * blueLeak
            let sR: Float = expf(-0.5 * dR * dR) + crossTalkBlueToRedGreen.x * blueLeak

            if isMonochrome {
                let pan: Float = 0.38 * sB + 0.42 * sG + 0.35 * sR
                table[i] = SIMD3<Float>(pan, pan, pan)
            } else {
                table[i] = SIMD3<Float>(max(sR, 1e-6), max(sG, 1e-6), max(sB, 1e-6))
            }
        }
        var sum = SIMD3<Float>(1e-6, 1e-6, 1e-6)
        for v in table { sum += v }
        return table.map { $0 / sum }
    }

    /// Generates the 81-wavelength (380nm to 780nm, 5nm step) unit dye spectral density curves d_C(λ), d_M(λ), d_Y(λ)
    public func evaluateDyeSpectralDensities81() -> [SIMD3<Float>] {
        var table = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: 81)
        for i in 0..<81 {
            let lambda = Float(380 + i * 5)
            if isMonochrome {
                let uvDiff: Float = (lambda - 400.0) / 60.0
                let agDensity: Float = 1.0 + 0.08 * expf(-0.5 * uvDiff * uvDiff)
                table[i] = SIMD3<Float>(agDensity, agDensity, agDensity)
            } else {
                let dC: Float = (lambda - dyePeakWavelengthsNM.x) / dyeWidthsNM.x
                let dM: Float = (lambda - dyePeakWavelengthsNM.y) / dyeWidthsNM.y
                let dY: Float = (lambda - dyePeakWavelengthsNM.z) / dyeWidthsNM.z

                let cyanMain: Float = expf(-0.5 * dC * dC)
                let magentaMain: Float = expf(-0.5 * dM * dM)
                let yellowMain: Float = expf(-0.5 * dY * dY)

                let cSideDiff: Float = (lambda - 450.0) / 45.0
                let mSideDiff: Float = (lambda - 435.0) / 38.0
                let ySideDiff: Float = (lambda - 520.0) / 40.0

                let cyanSide: Float = (0.14 - maskingCouplerNegativeAbsorption.x) * expf(-0.5 * cSideDiff * cSideDiff)
                let magentaSide: Float = (0.18 - maskingCouplerNegativeAbsorption.y) * expf(-0.5 * mSideDiff * mSideDiff)
                let yellowSide: Float = (0.05 - maskingCouplerNegativeAbsorption.z) * expf(-0.5 * ySideDiff * ySideDiff)

                table[i] = SIMD3<Float>(
                    max(cyanMain + cyanSide, -0.12),
                    max(magentaMain + magentaSide, -0.12),
                    max(yellowMain + yellowSide, -0.05)
                )
            }
        }
        return table
    }
}

public enum FilmStockDatabase {
    public static let cameraStocks: [FilmStockProfile] = [
        FilmStockProfile(
            id: "kodak_portra_160",
            name: "Kodak Portra 160",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 160,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.22, 0.62, 0.92),
            dMaxRGB: SIMD3<Float>(2.15, 2.55, 2.88),
            gammaRGB: SIMD3<Float>(0.58, 0.60, 0.62),
            shoulderSoftnessRGB: SIMD3<Float>(0.38, 0.36, 0.35),
            toeSoftnessRGB: SIMD3<Float>(0.28, 0.27, 0.26),
            peakWavelengthsNM: SIMD3<Float>(642, 545, 442),
            spectralWidthsNM: SIMD3<Float>(34, 30, 28),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.04),
            dyePeakWavelengthsNM: SIMD3<Float>(665, 548, 446),
            dyeWidthsNM: SIMD3<Float>(52, 42, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.11, 0.14, 0.03),
            rmsGranularity: 9.0,
            mtf50CyclesPerMM: 68.0,
            halationReflectanceRGB: SIMD3<Float>(0.025, 0.004, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(185, 85, 40),
            dirInterlayerMatrix: [
                 0.92, -0.18, -0.06,
                -0.15,  0.94, -0.12,
                -0.05, -0.16,  0.93
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-3.0, 6.0)
        ),
        FilmStockProfile(
            id: "kodak_portra_400",
            name: "Kodak Portra 400",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.24, 0.65, 0.96),
            dMaxRGB: SIMD3<Float>(2.22, 2.62, 2.95),
            gammaRGB: SIMD3<Float>(0.61, 0.63, 0.65),
            shoulderSoftnessRGB: SIMD3<Float>(0.42, 0.40, 0.38),
            toeSoftnessRGB: SIMD3<Float>(0.30, 0.29, 0.28),
            peakWavelengthsNM: SIMD3<Float>(645, 546, 444),
            spectralWidthsNM: SIMD3<Float>(35, 31, 29),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.025, 0.045),
            dyePeakWavelengthsNM: SIMD3<Float>(664, 548, 445),
            dyeWidthsNM: SIMD3<Float>(53, 43, 37),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.03),
            rmsGranularity: 11.0,
            mtf50CyclesPerMM: 62.0,
            halationReflectanceRGB: SIMD3<Float>(0.032, 0.005, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(200, 90, 42),
            dirInterlayerMatrix: [
                 0.95, -0.22, -0.08,
                -0.18,  0.96, -0.14,
                -0.06, -0.19,  0.95
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-4.0, 7.0)
        ),
        FilmStockProfile(
            id: "kodak_portra_800",
            name: "Kodak Portra 800",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 800,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.26, 0.68, 1.02),
            dMaxRGB: SIMD3<Float>(2.28, 2.68, 3.02),
            gammaRGB: SIMD3<Float>(0.64, 0.66, 0.68),
            shoulderSoftnessRGB: SIMD3<Float>(0.39, 0.37, 0.36),
            toeSoftnessRGB: SIMD3<Float>(0.32, 0.31, 0.30),
            peakWavelengthsNM: SIMD3<Float>(646, 548, 446),
            spectralWidthsNM: SIMD3<Float>(36, 32, 30),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.03, 0.05),
            dyePeakWavelengthsNM: SIMD3<Float>(662, 550, 446),
            dyeWidthsNM: SIMD3<Float>(54, 44, 38),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.04),
            rmsGranularity: 14.0,
            mtf50CyclesPerMM: 55.0,
            halationReflectanceRGB: SIMD3<Float>(0.038, 0.007, 0.002),
            halationSigmaMicrometers: SIMD3<Float>(225, 100, 48),
            dirInterlayerMatrix: [
                 0.96, -0.24, -0.09,
                -0.20,  0.98, -0.15,
                -0.07, -0.21,  0.96
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-5.0, 8.0)
        ),
        FilmStockProfile(
            id: "kodak_ektar_100",
            name: "Kodak Ektar 100",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 100,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.21, 0.60, 0.90),
            dMaxRGB: SIMD3<Float>(2.40, 2.78, 3.10),
            gammaRGB: SIMD3<Float>(0.72, 0.74, 0.76),
            shoulderSoftnessRGB: SIMD3<Float>(0.30, 0.29, 0.28),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.21, 0.20),
            peakWavelengthsNM: SIMD3<Float>(648, 544, 440),
            spectralWidthsNM: SIMD3<Float>(31, 27, 25),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.015, 0.03),
            dyePeakWavelengthsNM: SIMD3<Float>(668, 546, 444),
            dyeWidthsNM: SIMD3<Float>(48, 39, 34),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.13, 0.17, 0.04),
            rmsGranularity: 8.0,
            mtf50CyclesPerMM: 78.0,
            halationReflectanceRGB: SIMD3<Float>(0.024, 0.004, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(170, 80, 36),
            dirInterlayerMatrix: [
                 1.08, -0.34, -0.12,
                -0.28,  1.10, -0.22,
                -0.10, -0.30,  1.06
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, 5.0)
        ),
        FilmStockProfile(
            id: "kodak_gold_200",
            name: "Kodak Gold 200",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 200,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.25, 0.67, 0.98),
            dMaxRGB: SIMD3<Float>(2.25, 2.65, 2.92),
            gammaRGB: SIMD3<Float>(0.68, 0.69, 0.65),
            shoulderSoftnessRGB: SIMD3<Float>(0.35, 0.34, 0.38),
            toeSoftnessRGB: SIMD3<Float>(0.26, 0.25, 0.29),
            peakWavelengthsNM: SIMD3<Float>(644, 547, 445),
            spectralWidthsNM: SIMD3<Float>(36, 33, 30),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.03, 0.05),
            dyePeakWavelengthsNM: SIMD3<Float>(660, 550, 448),
            dyeWidthsNM: SIMD3<Float>(55, 45, 39),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.10, 0.13, 0.03),
            rmsGranularity: 12.5,
            mtf50CyclesPerMM: 56.0,
            halationReflectanceRGB: SIMD3<Float>(0.035, 0.006, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(210, 95, 44),
            dirInterlayerMatrix: [
                 1.00, -0.26, -0.09,
                -0.21,  1.02, -0.17,
                -0.08, -0.22,  0.98
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-1.0, 3.0)
        ),
        FilmStockProfile(
            id: "kodak_ultramax_400",
            name: "Kodak UltraMax 400",
            manufacturer: "Kodak",
            category: .c41ColorNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.27, 0.70, 1.04),
            dMaxRGB: SIMD3<Float>(2.30, 2.70, 3.00),
            gammaRGB: SIMD3<Float>(0.70, 0.71, 0.68),
            shoulderSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.36),
            toeSoftnessRGB: SIMD3<Float>(0.27, 0.26, 0.28),
            peakWavelengthsNM: SIMD3<Float>(646, 548, 446),
            spectralWidthsNM: SIMD3<Float>(37, 34, 31),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.035, 0.055),
            dyePeakWavelengthsNM: SIMD3<Float>(661, 551, 447),
            dyeWidthsNM: SIMD3<Float>(56, 46, 40),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.11, 0.14, 0.03),
            rmsGranularity: 14.5,
            mtf50CyclesPerMM: 52.0,
            halationReflectanceRGB: SIMD3<Float>(0.038, 0.007, 0.002),
            halationSigmaMicrometers: SIMD3<Float>(220, 98, 46),
            dirInterlayerMatrix: [
                 1.02, -0.28, -0.10,
                -0.23,  1.04, -0.18,
                -0.09, -0.24,  1.00
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, 4.0)
        ),
        FilmStockProfile(
            id: "fujifilm_pro_400h",
            name: "Fujifilm Pro 400H",
            manufacturer: "Fujifilm",
            category: .c41ColorNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.23, 0.64, 0.94),
            dMaxRGB: SIMD3<Float>(2.18, 2.58, 2.90),
            gammaRGB: SIMD3<Float>(0.59, 0.63, 0.64),
            shoulderSoftnessRGB: SIMD3<Float>(0.44, 0.41, 0.39),
            toeSoftnessRGB: SIMD3<Float>(0.29, 0.27, 0.26),
            peakWavelengthsNM: SIMD3<Float>(638, 540, 446),
            spectralWidthsNM: SIMD3<Float>(33, 28, 28),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.03),
            dyePeakWavelengthsNM: SIMD3<Float>(658, 544, 444),
            dyeWidthsNM: SIMD3<Float>(51, 41, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.04),
            rmsGranularity: 10.5,
            mtf50CyclesPerMM: 64.0,
            halationReflectanceRGB: SIMD3<Float>(0.028, 0.005, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(195, 88, 40),
            dirInterlayerMatrix: [
                 0.94, -0.21, -0.07,
                -0.22,  0.98, -0.18,
                -0.06, -0.20,  0.96
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, -5.0)
        ),
        FilmStockProfile(
            id: "fujifilm_superia_xtra_400",
            name: "Fujifilm Superia X-TRA 400",
            manufacturer: "Fujifilm",
            category: .c41ColorNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.26, 0.68, 0.99),
            dMaxRGB: SIMD3<Float>(2.28, 2.68, 2.98),
            gammaRGB: SIMD3<Float>(0.67, 0.70, 0.69),
            shoulderSoftnessRGB: SIMD3<Float>(0.36, 0.35, 0.35),
            toeSoftnessRGB: SIMD3<Float>(0.26, 0.25, 0.26),
            peakWavelengthsNM: SIMD3<Float>(640, 542, 448),
            spectralWidthsNM: SIMD3<Float>(35, 29, 29),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.025, 0.035),
            dyePeakWavelengthsNM: SIMD3<Float>(656, 545, 446),
            dyeWidthsNM: SIMD3<Float>(53, 43, 38),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.11, 0.14, 0.03),
            rmsGranularity: 13.5,
            mtf50CyclesPerMM: 56.0,
            halationReflectanceRGB: SIMD3<Float>(0.033, 0.006, 0.002),
            halationSigmaMicrometers: SIMD3<Float>(210, 92, 44),
            dirInterlayerMatrix: [
                 1.00, -0.25, -0.08,
                -0.24,  1.04, -0.19,
                -0.07, -0.22,  1.00
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-1.0, -3.0)
        ),
        FilmStockProfile(
            id: "kodak_vision3_50d_5203",
            name: "Kodak Vision3 50D (5203)",
            manufacturer: "Kodak",
            category: .ecn2MotionPicture,
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.18, 0.54, 0.84),
            dMaxRGB: SIMD3<Float>(2.05, 2.42, 2.75),
            gammaRGB: SIMD3<Float>(0.52, 0.53, 0.55),
            shoulderSoftnessRGB: SIMD3<Float>(0.48, 0.47, 0.46),
            toeSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.32),
            peakWavelengthsNM: SIMD3<Float>(645, 546, 442),
            spectralWidthsNM: SIMD3<Float>(33, 29, 27),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.035),
            dyePeakWavelengthsNM: SIMD3<Float>(665, 548, 445),
            dyeWidthsNM: SIMD3<Float>(52, 42, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.03),
            rmsGranularity: 6.5,
            mtf50CyclesPerMM: 82.0,
            halationReflectanceRGB: SIMD3<Float>(0.005, 0.002, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(110, 60, 30),
            dirInterlayerMatrix: [
                 0.90, -0.18, -0.06,
                -0.16,  0.92, -0.12,
                -0.05, -0.16,  0.91
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-1.0, 1.0)
        ),
        FilmStockProfile(
            id: "kodak_vision3_200t_5213",
            name: "Kodak Vision3 200T (5213)",
            manufacturer: "Kodak",
            category: .ecn2MotionPicture,
            isoSpeed: 200,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.19, 0.56, 0.86),
            dMaxRGB: SIMD3<Float>(2.08, 2.45, 2.78),
            gammaRGB: SIMD3<Float>(0.53, 0.54, 0.56),
            shoulderSoftnessRGB: SIMD3<Float>(0.47, 0.46, 0.45),
            toeSoftnessRGB: SIMD3<Float>(0.33, 0.32, 0.31),
            peakWavelengthsNM: SIMD3<Float>(646, 545, 440),
            spectralWidthsNM: SIMD3<Float>(34, 30, 26),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.035),
            dyePeakWavelengthsNM: SIMD3<Float>(665, 548, 445),
            dyeWidthsNM: SIMD3<Float>(52, 42, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.03),
            rmsGranularity: 8.5,
            mtf50CyclesPerMM: 74.0,
            halationReflectanceRGB: SIMD3<Float>(0.006, 0.002, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(120, 65, 32),
            dirInterlayerMatrix: [
                 0.91, -0.19, -0.06,
                -0.17,  0.93, -0.13,
                -0.06, -0.17,  0.92
            ],
            defaultEnlargerYMShift: SIMD2<Float>(6.0, 2.0)
        ),
        FilmStockProfile(
            id: "kodak_vision3_250d_5207",
            name: "Kodak Vision3 250D (5207)",
            manufacturer: "Kodak",
            category: .ecn2MotionPicture,
            isoSpeed: 250,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.20, 0.57, 0.88),
            dMaxRGB: SIMD3<Float>(2.10, 2.48, 2.80),
            gammaRGB: SIMD3<Float>(0.54, 0.55, 0.57),
            shoulderSoftnessRGB: SIMD3<Float>(0.46, 0.45, 0.44),
            toeSoftnessRGB: SIMD3<Float>(0.33, 0.32, 0.31),
            peakWavelengthsNM: SIMD3<Float>(645, 546, 443),
            spectralWidthsNM: SIMD3<Float>(34, 30, 28),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.04),
            dyePeakWavelengthsNM: SIMD3<Float>(664, 548, 445),
            dyeWidthsNM: SIMD3<Float>(53, 43, 37),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.03),
            rmsGranularity: 9.5,
            mtf50CyclesPerMM: 70.0,
            halationReflectanceRGB: SIMD3<Float>(0.006, 0.002, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(125, 68, 34),
            dirInterlayerMatrix: [
                 0.92, -0.20, -0.07,
                -0.17,  0.94, -0.13,
                -0.06, -0.18,  0.93
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, 2.0)
        ),
        FilmStockProfile(
            id: "kodak_vision3_500t_5219",
            name: "Kodak Vision3 500T (5219)",
            manufacturer: "Kodak",
            category: .ecn2MotionPicture,
            isoSpeed: 500,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.21, 0.59, 0.90),
            dMaxRGB: SIMD3<Float>(2.12, 2.50, 2.84),
            gammaRGB: SIMD3<Float>(0.55, 0.56, 0.58),
            shoulderSoftnessRGB: SIMD3<Float>(0.46, 0.45, 0.44),
            toeSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.32),
            peakWavelengthsNM: SIMD3<Float>(647, 546, 441),
            spectralWidthsNM: SIMD3<Float>(35, 31, 27),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.025, 0.04),
            dyePeakWavelengthsNM: SIMD3<Float>(664, 549, 446),
            dyeWidthsNM: SIMD3<Float>(54, 44, 38),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.12, 0.15, 0.03),
            rmsGranularity: 11.5,
            mtf50CyclesPerMM: 64.0,
            halationReflectanceRGB: SIMD3<Float>(0.007, 0.002, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(135, 72, 36),
            dirInterlayerMatrix: [
                 0.93, -0.20, -0.07,
                -0.18,  0.95, -0.14,
                -0.06, -0.18,  0.94
            ],
            defaultEnlargerYMShift: SIMD2<Float>(5.0, 3.0)
        ),
        FilmStockProfile(
            id: "cinestill_800t",
            name: "CineStill 800T (Remjet-Free C-41)",
            manufacturer: "CineStill",
            category: .ecn2MotionPicture,
            isoSpeed: 800,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.23, 0.62, 0.94),
            dMaxRGB: SIMD3<Float>(2.28, 2.66, 2.98),
            gammaRGB: SIMD3<Float>(0.63, 0.65, 0.67),
            shoulderSoftnessRGB: SIMD3<Float>(0.42, 0.41, 0.40),
            toeSoftnessRGB: SIMD3<Float>(0.31, 0.30, 0.29),
            peakWavelengthsNM: SIMD3<Float>(647, 546, 441),
            spectralWidthsNM: SIMD3<Float>(35, 31, 27),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.025, 0.04),
            dyePeakWavelengthsNM: SIMD3<Float>(664, 549, 446),
            dyeWidthsNM: SIMD3<Float>(54, 44, 38),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.11, 0.14, 0.03),
            rmsGranularity: 12.8,
            mtf50CyclesPerMM: 60.0,
            halationReflectanceRGB: SIMD3<Float>(0.095, 0.024, 0.003),
            halationSigmaMicrometers: SIMD3<Float>(285, 135, 55),
            dirInterlayerMatrix: [
                 0.96, -0.22, -0.08,
                -0.19,  0.98, -0.15,
                -0.07, -0.20,  0.96
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-4.0, 5.0)
        ),
        FilmStockProfile(
            id: "cinestill_50d",
            name: "CineStill 50D (Remjet-Free C-41)",
            manufacturer: "CineStill",
            category: .ecn2MotionPicture,
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.20, 0.58, 0.88),
            dMaxRGB: SIMD3<Float>(2.20, 2.56, 2.88),
            gammaRGB: SIMD3<Float>(0.60, 0.61, 0.63),
            shoulderSoftnessRGB: SIMD3<Float>(0.44, 0.43, 0.42),
            toeSoftnessRGB: SIMD3<Float>(0.32, 0.31, 0.30),
            peakWavelengthsNM: SIMD3<Float>(645, 546, 442),
            spectralWidthsNM: SIMD3<Float>(33, 29, 27),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.035),
            dyePeakWavelengthsNM: SIMD3<Float>(665, 548, 445),
            dyeWidthsNM: SIMD3<Float>(52, 42, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.11, 0.14, 0.03),
            rmsGranularity: 7.5,
            mtf50CyclesPerMM: 76.0,
            halationReflectanceRGB: SIMD3<Float>(0.078, 0.018, 0.002),
            halationSigmaMicrometers: SIMD3<Float>(250, 115, 48),
            dirInterlayerMatrix: [
                 0.94, -0.20, -0.07,
                -0.18,  0.96, -0.14,
                -0.06, -0.18,  0.95
            ],
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, 3.0)
        ),
        FilmStockProfile(
            id: "fujifilm_velvia_50",
            name: "Fujifilm Velvia 50 (RVP50)",
            manufacturer: "Fujifilm",
            category: .e6K14ColorReversal,
            isoSpeed: 50,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: true,
            dMinRGB: SIMD3<Float>(0.10, 0.11, 0.13),
            dMaxRGB: SIMD3<Float>(3.55, 3.65, 3.48),
            gammaRGB: SIMD3<Float>(1.88, 1.92, 1.86),
            shoulderSoftnessRGB: SIMD3<Float>(0.24, 0.23, 0.25),
            toeSoftnessRGB: SIMD3<Float>(0.20, 0.19, 0.21),
            peakWavelengthsNM: SIMD3<Float>(642, 544, 442),
            spectralWidthsNM: SIMD3<Float>(28, 25, 24),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.01, 0.02),
            dyePeakWavelengthsNM: SIMD3<Float>(660, 545, 444),
            dyeWidthsNM: SIMD3<Float>(46, 38, 33),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.0, 0.0, 0.0),
            rmsGranularity: 9.0,
            mtf50CyclesPerMM: 75.0,
            halationReflectanceRGB: SIMD3<Float>(0.018, 0.004, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(150, 70, 35),
            dirInterlayerMatrix: [
                 1.15, -0.38, -0.14,
                -0.32,  1.18, -0.26,
                -0.12, -0.34,  1.14
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "fujifilm_provia_100f",
            name: "Fujifilm Provia 100F (RDPIII)",
            manufacturer: "Fujifilm",
            category: .e6K14ColorReversal,
            isoSpeed: 100,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: true,
            dMinRGB: SIMD3<Float>(0.09, 0.10, 0.12),
            dMaxRGB: SIMD3<Float>(3.40, 3.48, 3.35),
            gammaRGB: SIMD3<Float>(1.65, 1.68, 1.64),
            shoulderSoftnessRGB: SIMD3<Float>(0.28, 0.27, 0.28),
            toeSoftnessRGB: SIMD3<Float>(0.24, 0.23, 0.24),
            peakWavelengthsNM: SIMD3<Float>(640, 545, 444),
            spectralWidthsNM: SIMD3<Float>(30, 27, 26),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.012, 0.022),
            dyePeakWavelengthsNM: SIMD3<Float>(658, 546, 445),
            dyeWidthsNM: SIMD3<Float>(48, 40, 35),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.0, 0.0, 0.0),
            rmsGranularity: 8.0,
            mtf50CyclesPerMM: 78.0,
            halationReflectanceRGB: SIMD3<Float>(0.016, 0.003, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(145, 68, 34),
            dirInterlayerMatrix: [
                 1.04, -0.28, -0.10,
                -0.24,  1.06, -0.20,
                -0.09, -0.26,  1.04
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "fujifilm_astia_100f",
            name: "Fujifilm Astia 100F (RAP100F)",
            manufacturer: "Fujifilm",
            category: .e6K14ColorReversal,
            isoSpeed: 100,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: true,
            dMinRGB: SIMD3<Float>(0.09, 0.10, 0.11),
            dMaxRGB: SIMD3<Float>(3.28, 3.35, 3.22),
            gammaRGB: SIMD3<Float>(1.52, 1.54, 1.50),
            shoulderSoftnessRGB: SIMD3<Float>(0.34, 0.33, 0.34),
            toeSoftnessRGB: SIMD3<Float>(0.28, 0.27, 0.28),
            peakWavelengthsNM: SIMD3<Float>(639, 545, 445),
            spectralWidthsNM: SIMD3<Float>(32, 28, 27),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.015, 0.025),
            dyePeakWavelengthsNM: SIMD3<Float>(656, 546, 445),
            dyeWidthsNM: SIMD3<Float>(50, 41, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.0, 0.0, 0.0),
            rmsGranularity: 7.0,
            mtf50CyclesPerMM: 80.0,
            halationReflectanceRGB: SIMD3<Float>(0.015, 0.003, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(140, 65, 32),
            dirInterlayerMatrix: [
                 0.96, -0.22, -0.08,
                -0.20,  0.98, -0.16,
                -0.07, -0.22,  0.96
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "kodak_ektachrome_e100",
            name: "Kodak Ektachrome E100",
            manufacturer: "Kodak",
            category: .e6K14ColorReversal,
            isoSpeed: 100,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: true,
            dMinRGB: SIMD3<Float>(0.09, 0.10, 0.12),
            dMaxRGB: SIMD3<Float>(3.42, 3.50, 3.38),
            gammaRGB: SIMD3<Float>(1.68, 1.70, 1.66),
            shoulderSoftnessRGB: SIMD3<Float>(0.29, 0.28, 0.29),
            toeSoftnessRGB: SIMD3<Float>(0.24, 0.23, 0.24),
            peakWavelengthsNM: SIMD3<Float>(646, 546, 442),
            spectralWidthsNM: SIMD3<Float>(30, 27, 26),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.012, 0.022),
            dyePeakWavelengthsNM: SIMD3<Float>(666, 548, 444),
            dyeWidthsNM: SIMD3<Float>(47, 39, 34),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.0, 0.0, 0.0),
            rmsGranularity: 8.0,
            mtf50CyclesPerMM: 78.0,
            halationReflectanceRGB: SIMD3<Float>(0.017, 0.003, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(148, 70, 34),
            dirInterlayerMatrix: [
                 1.06, -0.29, -0.10,
                -0.25,  1.08, -0.20,
                -0.09, -0.27,  1.05
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "kodachrome_64_k14",
            name: "Kodachrome 64 (KR64 / K-14)",
            manufacturer: "Kodak",
            category: .e6K14ColorReversal,
            isoSpeed: 64,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: true,
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.11),
            dMaxRGB: SIMD3<Float>(3.75, 3.82, 3.65),
            gammaRGB: SIMD3<Float>(1.78, 1.82, 1.75),
            shoulderSoftnessRGB: SIMD3<Float>(0.26, 0.25, 0.27),
            toeSoftnessRGB: SIMD3<Float>(0.21, 0.20, 0.22),
            peakWavelengthsNM: SIMD3<Float>(648, 544, 440),
            spectralWidthsNM: SIMD3<Float>(27, 24, 23),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.008, 0.015),
            dyePeakWavelengthsNM: SIMD3<Float>(670, 546, 442),
            dyeWidthsNM: SIMD3<Float>(42, 35, 31),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0.0, 0.0, 0.0),
            rmsGranularity: 10.0,
            mtf50CyclesPerMM: 92.0,
            halationReflectanceRGB: SIMD3<Float>(0.008, 0.002, 0.001),
            halationSigmaMicrometers: SIMD3<Float>(115, 58, 28),
            dirInterlayerMatrix: [
                 1.12, -0.35, -0.11,
                -0.29,  1.14, -0.22,
                -0.10, -0.31,  1.10
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "ilford_hp5_plus_400",
            name: "Ilford HP5 Plus 400",
            manufacturer: "Ilford",
            category: .bwSilverNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: true,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.18, 0.18, 0.18),
            dMaxRGB: SIMD3<Float>(2.35, 2.35, 2.35),
            gammaRGB: SIMD3<Float>(0.62, 0.62, 0.62),
            shoulderSoftnessRGB: SIMD3<Float>(0.42, 0.42, 0.42),
            toeSoftnessRGB: SIMD3<Float>(0.32, 0.32, 0.32),
            peakWavelengthsNM: SIMD3<Float>(635, 540, 445),
            spectralWidthsNM: SIMD3<Float>(45, 42, 38),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.05, 0.05),
            dyePeakWavelengthsNM: SIMD3<Float>(550, 550, 550),
            dyeWidthsNM: SIMD3<Float>(200, 200, 200),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 14.5,
            mtf50CyclesPerMM: 54.0,
            halationReflectanceRGB: SIMD3<Float>(0.030, 0.030, 0.030),
            halationSigmaMicrometers: SIMD3<Float>(195, 195, 195),
            dirInterlayerMatrix: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "ilford_delta_3200",
            name: "Ilford Delta 3200 Professional",
            manufacturer: "Ilford",
            category: .bwSilverNegative,
            isoSpeed: 3200,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: true,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.26, 0.26, 0.26),
            dMaxRGB: SIMD3<Float>(2.18, 2.18, 2.18),
            gammaRGB: SIMD3<Float>(0.58, 0.58, 0.58),
            shoulderSoftnessRGB: SIMD3<Float>(0.46, 0.46, 0.46),
            toeSoftnessRGB: SIMD3<Float>(0.38, 0.38, 0.38),
            peakWavelengthsNM: SIMD3<Float>(650, 545, 450),
            spectralWidthsNM: SIMD3<Float>(48, 44, 40),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.06, 0.06),
            dyePeakWavelengthsNM: SIMD3<Float>(550, 550, 550),
            dyeWidthsNM: SIMD3<Float>(200, 200, 200),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 24.0,
            mtf50CyclesPerMM: 42.0,
            halationReflectanceRGB: SIMD3<Float>(0.042, 0.042, 0.042),
            halationSigmaMicrometers: SIMD3<Float>(245, 245, 245),
            dirInterlayerMatrix: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "kodak_trix_400",
            name: "Kodak Tri-X 400 (400TX)",
            manufacturer: "Kodak",
            category: .bwSilverNegative,
            isoSpeed: 400,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: true,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.19, 0.19, 0.19),
            dMaxRGB: SIMD3<Float>(2.48, 2.48, 2.48),
            gammaRGB: SIMD3<Float>(0.68, 0.68, 0.68),
            shoulderSoftnessRGB: SIMD3<Float>(0.36, 0.36, 0.36),
            toeSoftnessRGB: SIMD3<Float>(0.26, 0.26, 0.26),
            peakWavelengthsNM: SIMD3<Float>(630, 538, 442),
            spectralWidthsNM: SIMD3<Float>(44, 40, 38),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.05, 0.05),
            dyePeakWavelengthsNM: SIMD3<Float>(550, 550, 550),
            dyeWidthsNM: SIMD3<Float>(200, 200, 200),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 16.0,
            mtf50CyclesPerMM: 56.0,
            halationReflectanceRGB: SIMD3<Float>(0.032, 0.032, 0.032),
            halationSigmaMicrometers: SIMD3<Float>(205, 205, 205),
            dirInterlayerMatrix: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        ),
        FilmStockProfile(
            id: "kodak_double_x_5222",
            name: "Kodak Eastman Double-X (5222)",
            manufacturer: "Kodak",
            category: .bwSilverNegative,
            isoSpeed: 250,
            referenceKelvin: 5500,
            hasAntiHalationRemjet: false,
            isMonochrome: true,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.21, 0.21, 0.21),
            dMaxRGB: SIMD3<Float>(2.42, 2.42, 2.42),
            gammaRGB: SIMD3<Float>(0.65, 0.65, 0.65),
            shoulderSoftnessRGB: SIMD3<Float>(0.38, 0.38, 0.38),
            toeSoftnessRGB: SIMD3<Float>(0.25, 0.25, 0.25),
            peakWavelengthsNM: SIMD3<Float>(638, 540, 440),
            spectralWidthsNM: SIMD3<Float>(45, 41, 37),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.05, 0.05),
            dyePeakWavelengthsNM: SIMD3<Float>(550, 550, 550),
            dyeWidthsNM: SIMD3<Float>(200, 200, 200),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 14.0,
            mtf50CyclesPerMM: 60.0,
            halationReflectanceRGB: SIMD3<Float>(0.036, 0.036, 0.036),
            halationSigmaMicrometers: SIMD3<Float>(215, 215, 215),
            dirInterlayerMatrix: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ],
            defaultEnlargerYMShift: SIMD2<Float>(0.0, 0.0)
        )
    ]

    public static let printStocks: [FilmStockProfile] = [
        FilmStockProfile(
            id: "kodak_endura_premier",
            name: "Kodak Endura Premier / Supra Endura (RA-4)",
            manufacturer: "Kodak",
            category: .ra4AndCinePrint,
            isoSpeed: 2,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.08, 0.09, 0.11),
            dMaxRGB: SIMD3<Float>(2.45, 2.42, 2.35),
            gammaRGB: SIMD3<Float>(2.42, 2.45, 2.40),
            shoulderSoftnessRGB: SIMD3<Float>(0.26, 0.25, 0.27),
            toeSoftnessRGB: SIMD3<Float>(0.24, 0.23, 0.25),
            peakWavelengthsNM: SIMD3<Float>(695, 552, 472),
            spectralWidthsNM: SIMD3<Float>(26, 24, 24),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.005, 0.008),
            dyePeakWavelengthsNM: SIMD3<Float>(655, 542, 444),
            dyeWidthsNM: SIMD3<Float>(52, 42, 38),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 4.0,
            mtf50CyclesPerMM: 85.0,
            halationReflectanceRGB: SIMD3<Float>(0, 0, 0),
            halationSigmaMicrometers: SIMD3<Float>(20, 20, 20),
            dirInterlayerMatrix: [1,0,0, 0,1,0, 0,0,1],
            defaultEnlargerYMShift: SIMD2<Float>(0, 0)
        ),
        FilmStockProfile(
            id: "fujifilm_crystal_archive_typeii",
            name: "Fujifilm Crystal Archive Type II / Maxima (RA-4)",
            manufacturer: "Fujifilm",
            category: .ra4AndCinePrint,
            isoSpeed: 2,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.07, 0.08, 0.10),
            dMaxRGB: SIMD3<Float>(2.55, 2.52, 2.44),
            gammaRGB: SIMD3<Float>(2.55, 2.58, 2.52),
            shoulderSoftnessRGB: SIMD3<Float>(0.24, 0.23, 0.25),
            toeSoftnessRGB: SIMD3<Float>(0.22, 0.21, 0.23),
            peakWavelengthsNM: SIMD3<Float>(692, 550, 470),
            spectralWidthsNM: SIMD3<Float>(25, 23, 23),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.004, 0.007),
            dyePeakWavelengthsNM: SIMD3<Float>(652, 544, 446),
            dyeWidthsNM: SIMD3<Float>(50, 41, 37),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 3.8,
            mtf50CyclesPerMM: 88.0,
            halationReflectanceRGB: SIMD3<Float>(0, 0, 0),
            halationSigmaMicrometers: SIMD3<Float>(18, 18, 18),
            dirInterlayerMatrix: [1,0,0, 0,1,0, 0,0,1],
            defaultEnlargerYMShift: SIMD2<Float>(0, 0)
        ),
        FilmStockProfile(
            id: "kodak_vision_2383",
            name: "Kodak Vision Color Print Film 2383",
            manufacturer: "Kodak",
            category: .ra4AndCinePrint,
            isoSpeed: 3,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.09),
            dMaxRGB: SIMD3<Float>(3.55, 3.62, 3.48),
            gammaRGB: SIMD3<Float>(2.85, 2.92, 2.80),
            shoulderSoftnessRGB: SIMD3<Float>(0.22, 0.21, 0.24),
            toeSoftnessRGB: SIMD3<Float>(0.20, 0.19, 0.22),
            peakWavelengthsNM: SIMD3<Float>(698, 554, 468),
            spectralWidthsNM: SIMD3<Float>(24, 22, 22),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.004, 0.006),
            dyePeakWavelengthsNM: SIMD3<Float>(668, 545, 442),
            dyeWidthsNM: SIMD3<Float>(48, 39, 35),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 5.0,
            mtf50CyclesPerMM: 95.0,
            halationReflectanceRGB: SIMD3<Float>(0, 0, 0),
            halationSigmaMicrometers: SIMD3<Float>(15, 15, 15),
            dirInterlayerMatrix: [1,0,0, 0,1,0, 0,0,1],
            defaultEnlargerYMShift: SIMD2<Float>(-2.0, 2.0)
        ),
        FilmStockProfile(
            id: "fujicolor_eterna_cp_3513di",
            name: "Fujicolor Positive Film Eterna-CP 3513DI",
            manufacturer: "Fujifilm",
            category: .ra4AndCinePrint,
            isoSpeed: 3,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: true,
            isMonochrome: false,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.06, 0.07, 0.08),
            dMaxRGB: SIMD3<Float>(3.42, 3.48, 3.40),
            gammaRGB: SIMD3<Float>(2.72, 2.76, 2.70),
            shoulderSoftnessRGB: SIMD3<Float>(0.25, 0.24, 0.25),
            toeSoftnessRGB: SIMD3<Float>(0.23, 0.22, 0.23),
            peakWavelengthsNM: SIMD3<Float>(694, 550, 470),
            spectralWidthsNM: SIMD3<Float>(25, 23, 23),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.004, 0.006),
            dyePeakWavelengthsNM: SIMD3<Float>(662, 544, 445),
            dyeWidthsNM: SIMD3<Float>(49, 40, 36),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 4.8,
            mtf50CyclesPerMM: 94.0,
            halationReflectanceRGB: SIMD3<Float>(0, 0, 0),
            halationSigmaMicrometers: SIMD3<Float>(15, 15, 15),
            dirInterlayerMatrix: [1,0,0, 0,1,0, 0,0,1],
            defaultEnlargerYMShift: SIMD2<Float>(-1.0, 0.0)
        ),
        FilmStockProfile(
            id: "ilford_multigrade_fb_classic",
            name: "Ilford Multigrade FB Classic (Baryta VC)",
            manufacturer: "Ilford",
            category: .ra4AndCinePrint,
            isoSpeed: 4,
            referenceKelvin: 3200,
            hasAntiHalationRemjet: false,
            isMonochrome: true,
            isReversal: false,
            dMinRGB: SIMD3<Float>(0.05, 0.05, 0.06),
            dMaxRGB: SIMD3<Float>(2.28, 2.28, 2.25),
            gammaRGB: SIMD3<Float>(2.15, 2.15, 2.15),
            shoulderSoftnessRGB: SIMD3<Float>(0.28, 0.28, 0.28),
            toeSoftnessRGB: SIMD3<Float>(0.26, 0.26, 0.26),
            peakWavelengthsNM: SIMD3<Float>(545, 535, 455),
            spectralWidthsNM: SIMD3<Float>(35, 32, 30),
            crossTalkBlueToRedGreen: SIMD2<Float>(0.02, 0.02),
            dyePeakWavelengthsNM: SIMD3<Float>(550, 550, 550),
            dyeWidthsNM: SIMD3<Float>(200, 200, 200),
            maskingCouplerNegativeAbsorption: SIMD3<Float>(0, 0, 0),
            rmsGranularity: 3.5,
            mtf50CyclesPerMM: 90.0,
            halationReflectanceRGB: SIMD3<Float>(0, 0, 0),
            halationSigmaMicrometers: SIMD3<Float>(16, 16, 16),
            dirInterlayerMatrix: [1,0,0, 0,1,0, 0,0,1],
            defaultEnlargerYMShift: SIMD2<Float>(0, 0)
        )
    ]

    public static func cameraStock(withID id: String) -> FilmStockProfile {
        cameraStocks.first(where: { $0.id == id }) ?? cameraStocks[1]
    }

    public static func printStock(withID id: String) -> FilmStockProfile {
        printStocks.first(where: { $0.id == id }) ?? printStocks[0]
    }
}
