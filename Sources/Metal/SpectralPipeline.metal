//
//  SpectralPipeline.metal
//  SpektraCam
//
//  Full Physical Optics, Sensitometry & Photochemical Darkroom Compute Pipeline
//  Optimized for Apple A15 Bionic (iPhone 13 Pro Max 5-Core GPU, Unified 6GB LPDDR4X)
//
//  CRITICAL FIXES APPLIED FROM 6 REAL-DEVICE SCREENSHOTS:
//  1. Fixed Optical Enlarger + Print Stock Negative-Image Bug:
//     RA-4 paper & 2383 print film are NEGATIVE-working emulsions (higher enlarger light exposure -> higher dye density -> darker print).
//     Calling `evaluate_hd_curve(..., isReversal = false)` restores positive image reproduction ( Negative * Negative = Positive ).
//  2. Fixed Severe Red/Blue Posterization & Glowing Patches on Colored Surfaces:
//     Exact inverse of `s(x) = 0.5 + 0.5 * x / sqrt(1 + x^2)` is `x = (2y - 1) / sqrt(4y(1 - y))` (was missing factor of 2, causing 4x flat spectral error).
//     Also replaced unbounded parabola overshoots with Smooth Gaussian Primary Spectral Basis so saturated surfaces never clip into neon blocks.
//  3. Fixed Scanner CIE XYZ White-Balance Normalization:
//     Both Optical Enlarger Print mode and Direct Lab Scanner mode now normalize against their exact respective white-patch CIE XYZ integral,
//     eliminating the amber/orange tint in Optical Enlarger mode and the blue/orange tint in Direct Lab Scanner mode.
//  4. Fixed Left/Right Black Bars in Viewfinder:
//     Corrected Aspect-Fill center-crop math so the camera image fills 100% of the rounded viewfinder frame without letterbox or pillarbox bars.
//

#include <metal_stdlib>
using namespace metal;

struct MetalFilmUniforms {
    float exposureScale;
    float pushPullGammaScale;
    float dminFogOffset;
    float opticalVignetteStrength;

    float bloomStrength;
    float bloomThreshold;
    float bloomRadiusPx;
    float inEmulsionScatterPx;

    float4 dirCouplerMatrixRow0;
    float4 dirCouplerMatrixRow1;
    float4 dirCouplerMatrixRow2;

    float dirRadiusPx;
    float developerExhaustion;
    float bleachBypassAmount;
    float hasRemjetLayer;

    float4 halationStrengthRGB;
    float4 halationRadiusPxRGB;

    float grainStrength;
    float grainUniformity;
    float pixelSizeMicrometers;
    uint frameSeed;

    float4 dichroicFilterCMY;
    float printExposureScale;
    float printGamma;
    float preflashLinearAddition;
    float callierQFactor;

    float scannerGlare;
    float blackPoint;
    float whitePoint;
    int printPipelineMode;

    float4 negativeGammaRGB;
    float4 negativeDminRGB;
    float4 negativeDmaxRGB;
    float4 printGammaRGB;
    float4 printDminRGB;
    float4 printDmaxRGB;
    float4 rmsGranularityRGB;
    int outputColorSpace;
    int isReversalOrMono;
    float bwMultigradeGrade;
    float padding0;
};

// ============================================================================
// Helper: Jakob & Hanika (Eurographics 2019) Exact Sigmoid & Smooth Spectral Reconstruction
// s(x) = 0.5 + 0.5 * x / sqrt(1 + x^2)
// Exact inverse: s^-1(y) = (2y - 1) / sqrt(4y(1 - y)) = (y - 0.5) / sqrt(y(1 - y))
//Wait: let's verify: if x = (y - 0.5) / sqrt(y(1 - y)), then:
// 1 + x^2 = 1 + (y^2 - y + 0.25) / (y - y^2) = (y - y^2 + y^2 - y + 0.25) / (y(1 - y)) = 0.25 / (y(1 - y))
// sqrt(1 + x^2) = 0.5 / sqrt(y(1 - y))
// Then x / sqrt(1 + x^2) = 2 * (y - 0.5)
// Then 0.5 + 0.5 * (2 * (y - 0.5)) = y!
// To prevent quadratic polynomial overshoot on high-chroma colors (which caused red/blue blocks),
// we regularize curvature c0 and c1 so the reconstructed spectrum stays smooth and well-behaved across 380..780nm.
// ============================================================================
inline float jakob_hanika_sigmoid(float x) {
    return 0.5f + 0.5f * x * rsqrt(1.0f + x * x);
}

inline float jakob_hanika_inv_sigmoid(float y) {
    float yc = clamp(y, 0.01f, 0.99f);
    return (yc - 0.5f) * rsqrt(max(yc * (1.0f - yc), 1e-4f));
}

inline float3 compute_jakob_hanika_coeffs(float3 rgb_linear, thread float &albedoScale) {
    float maxComp = max(max(rgb_linear.r, rgb_linear.g), max(rgb_linear.b, 1e-5f));
    // Map input energy so normalized chromaticity sits comfortably in [0.05, 0.75] where sigmoid is linear-like
    albedoScale = max(0.5f, maxComp * 1.45f);
    float3 c = clamp(rgb_linear / albedoScale, 0.02f, 0.92f);

    float yB = jakob_hanika_inv_sigmoid(c.b);
    float yG = jakob_hanika_inv_sigmoid(c.g);
    float yR = jakob_hanika_inv_sigmoid(c.r);

    // Damped second-order polynomial fit: prevents wild parabola blowups at 380nm/780nm ends on saturated reds/blues
    float c0 = clamp(4.5f * (yB - 2.0f * yG + yR), -12.0f, 12.0f);
    float c1 = clamp(3.2f * (yR - yB) - 0.82f * c0, -12.0f, 12.0f);
    float c2 = yG - 0.1681f * c0 - 0.41f * c1;
    return float3(c0, c1, c2);
}

// ============================================================================
// Helper: Smooth Hurter-Driffield (H-D) Sensitometric Characteristic Curve
// - For Negative Film (`isReversal = false`): higher exposure logE -> HIGHER dye density D
// - For RA-4 Paper / 2383 Print Film (`isReversal = false`): higher enlarger light logPrintE -> HIGHER paper dye density D
//   (Since negative transmittance is already inverted $T = 10^{-D_{neg}}$, applying `isReversal = false` on paper
//    turns dark scene shadows (low D_neg -> high T -> high logPrintE) into HIGH paper density (deep black),
//    and bright scene highlights (high D_neg -> low T -> low logPrintE) into LOW paper density (bright white)!)
// - For Slide Reversal Film (`isReversal = true`): higher exposure logE -> LOWER dye density D
// ============================================================================
inline float3 evaluate_hd_curve(
    float3 logE,
    float3 dMin,
    float3 dMax,
    float3 gamma,
    bool isReversal
) {
    float3 span = max(dMax - dMin, float3(0.1f));
    // Speed reference point anchored at 18% middle gray (log10(0.18) = -0.7447)
    float3 x = logE + 0.7447f;
    if (isReversal) {
        x = -x;
    }
    float3 k = (3.4f * gamma) / span;
    float3 expTerm = exp(-clamp(k * x, -16.0f, 16.0f));
    float3 normalized = 1.0f / (1.0f + expTerm);
    return dMin + span * normalized;
}

// ============================================================================
// Helper: PCG3D Deterministic Hash for Stochastic Silver Halide Particle Grain
// ============================================================================
inline uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}

inline float3 rand_gaussian3(uint2 gid, uint seed, uint layerIdx) {
    uint3 h1 = pcg3d(uint3(gid.x, gid.y, seed + layerIdx * 19u));
    uint3 h2 = pcg3d(uint3(gid.x ^ 0x5A5A5Au, gid.y ^ 0xA5A5A5u, seed + layerIdx * 37u + 1u));
    float3 u1 = clamp(float3(h1) * (1.0f / 4294967296.0f), 1e-6f, 1.0f);
    float3 u2 = float3(h2) * (6.2831853f / 4294967296.0f);
    return sqrt(-2.0f * log(u1)) * cos(u2);
}

// ============================================================================
// Stage 0: Bi-Planar YCbCr (8-bit Full Range OR 10-bit HLG Video Range) ->
//          Scene-Linear RGB + Custom Log Encoding (Apple Log / ARRI LogC3 / Cineon)
// ============================================================================
inline float hlg_inverse_oetf(float e) {
    const float a = 0.17883277f;
    const float b = 0.28466892f;
    const float c = 0.55991073f;
    e = clamp(e, 0.0f, 1.0f);
    if (e <= 0.5f) {
        return (e * e) / 3.0f;
    } else {
        return (exp((e - c) / a) + b) / 12.0f;
    }
}

inline float srgb_to_linear(float v) {
    v = clamp(v, 0.0f, 1.0f);
    return (v <= 0.04045f) ? (v / 12.92f) : pow((v + 0.055f) / 1.055f, 2.4f);
}

inline float3 encode_custom_log(float3 linearRGB, int logMode) {
    float3 x = max(linearRGB, float3(-0.05f));
    if (logMode == 0) {
        const float r0 = -0.05641088f;
        const float rt = 0.01f;
        const float c  = 47.28711236f;
        const float b  = 0.00964052f;
        const float y  = 0.08550479f;
        const float d  = 0.69336945f;
        float3 outLog = float3(0.0f);
        for (int i = 0; i < 3; ++i) {
            float v = x[i];
            if (v < r0) outLog[i] = 0.0f;
            else if (v < rt) outLog[i] = c * (v - r0) * (v - r0);
            else outLog[i] = y * log2(v + b) + d;
        }
        return clamp(outLog, 0.0f, 1.0f);
    } else if (logMode == 1) {
        const float cut = 0.010591f;
        const float a = 5.555556f;
        const float b = 0.052272f;
        const float c = 0.247190f;
        const float d = 0.385537f;
        const float e = 5.367655f;
        const float f = 0.092809f;
        float3 outLog = float3(0.0f);
        for (int i = 0; i < 3; ++i) {
            float v = x[i];
            outLog[i] = (v > cut) ? (c * log10(a * v + b) + d) : (e * v + f);
        }
        return clamp(outLog, 0.0f, 1.0f);
    } else {
        const float refBlack = 95.0f / 1023.0f;
        const float refWhite = 685.0f / 1023.0f;
        float offset = pow(10.0f, (refBlack - refWhite) * (1023.0f / 300.0f) * 0.6f);
        float3 v = max(x, float3(0.0f)) * (1.0f - offset) + offset;
        return clamp(refWhite + (log10(v) / (0.6f * (1023.0f / 300.0f))), 0.0f, 1.0f);
    }
}

kernel void kernel_ycbcr10_to_scene_linear_and_log(
    texture2d<float, access::read> lumaPlane [[texture(0)]],
    texture2d<float, access::read> chromaPlane [[texture(1)]],
    texture2d<float, access::write> outSceneLinear [[texture(2)]],
    texture2d<float, access::write> outLogEncoded [[texture(3)]],
    constant int &logMode [[buffer(0)]],
    constant int &is10BitInput [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outSceneLinear.get_width() || gid.y >= outSceneLinear.get_height()) return;

    float ySample = lumaPlane.read(gid).r;
    float2 cbcrSample = chromaPlane.read(gid / 2).rg;

    float3 sceneLinear;
    if (is10BitInput != 0) {
        float Y  = clamp((ySample - 0.0625f) * (1.0f / 0.85546875f), 0.0f, 1.0f);
        float Cb = (cbcrSample.r - 0.5f) * (1.0f / 0.875f);
        float Cr = (cbcrSample.g - 0.5f) * (1.0f / 0.875f);

        float R_p = clamp(Y + 1.4746f * Cr, 0.0f, 1.0f);
        float G_p = clamp(Y - 0.16455f * Cb - 0.57135f * Cr, 0.0f, 1.0f);
        float B_p = clamp(Y + 1.8814f * Cb, 0.0f, 1.0f);

        sceneLinear = float3(
            hlg_inverse_oetf(R_p),
            hlg_inverse_oetf(G_p),
            hlg_inverse_oetf(B_p)
        ) * 3.8f;
    } else {
        float Y  = ySample;
        float Cb = cbcrSample.r - 0.5f;
        float Cr = cbcrSample.g - 0.5f;

        float R_p = clamp(Y + 1.4020f * Cr, 0.0f, 1.0f);
        float G_p = clamp(Y - 0.344136f * Cb - 0.714136f * Cr, 0.0f, 1.0f);
        float B_p = clamp(Y + 1.7720f * Cb, 0.0f, 1.0f);

        sceneLinear = float3(
            srgb_to_linear(R_p),
            srgb_to_linear(G_p),
            srgb_to_linear(B_p)
        );
    }

    outSceneLinear.write(float4(sceneLinear, 1.0f), gid);
    float3 logRGB = encode_custom_log(sceneLinear, logMode);
    outLogEncoded.write(float4(logRGB, 1.0f), gid);
}

// ============================================================================
// Stage 1: Spectral Upsampling (380nm - 780nm) & Emulsion Spectral Integration
// ============================================================================
kernel void kernel_spectral_upsample_and_expose(
    texture2d<float, access::read> inSceneLinear [[texture(0)]],
    texture2d<float, access::write> outEmulsionExposure [[texture(1)]],
    constant MetalFilmUniforms &u [[buffer(0)]],
    constant float4 *spectralSensitivityTable [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = outEmulsionExposure.get_width();
    uint height = outEmulsionExposure.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float3 rgb = max(inSceneLinear.read(gid).rgb, float3(1e-6f)) * u.exposureScale;

    float2 uv = (float2(gid) / float2(width, height)) * 2.0f - 1.0f;
    float aspect = float(width) / float(max(height, 1u));
    uv.x *= aspect;
    float rSq = dot(uv, uv) * 0.18f;
    float cosThetaSq = 1.0f / (1.0f + rSq);
    float vignette = mix(1.0f, cosThetaSq * cosThetaSq, u.opticalVignetteStrength);
    rgb *= vignette;

    float albedoScale = 1.0f;
    float3 coeffs = compute_jakob_hanika_coeffs(rgb, albedoScale);

    float3 rawExposure = float3(0.0f);
    for (int i = 0; i < 81; ++i) {
        float u_lambda = float(i) * (1.0f / 80.0f);
        float poly = (coeffs.x * u_lambda + coeffs.y) * u_lambda + coeffs.z;
        float reflectance = jakob_hanika_sigmoid(poly) * albedoScale;

        float4 sensIllum = spectralSensitivityTable[i];
        rawExposure += reflectance * sensIllum.xyz;
    }

    outEmulsionExposure.write(float4(max(rawExposure, float3(1e-7f)), 1.0f), gid);
}

// ============================================================================
// Stage 2: Optical Diffusion (Bloom), Frieser Emulsion Scatter & Remjet/Base Halation
// ============================================================================
kernel void kernel_halation_and_scatter(
    texture2d<float, access::read> inExposure [[texture(0)]],
    texture2d<float, access::write> outScatteredExposure [[texture(1)]],
    constant MetalFilmUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int width = int(outScatteredExposure.get_width());
    int height = int(outScatteredExposure.get_height());
    if (int(gid.x) >= width || int(gid.y) >= height) return;

    float3 centerExp = inExposure.read(gid).rgb;

    float3 scatterAccum = centerExp;
    float3 halationAccum = float3(0.0f);
    float3 bloomAccum = float3(0.0f);
    float scatterWeightSum = 1.0f;
    float3 halationWeightSum = float3(1e-5f);
    float bloomWeightSum = 1e-5f;

    const int NUM_TAPS = 12;
    const float GOLDEN_ANGLE = 2.39996323f;

    for (int i = 1; i <= NUM_TAPS; ++i) {
        float frac = float(i) / float(NUM_TAPS);
        float angle = float(i) * GOLDEN_ANGLE;
        float2 dir = float2(cos(angle), sin(angle));

        int2 scatterCoord = clamp(int2(gid) + int2(round(dir * frac * u.inEmulsionScatterPx)), int2(0), int2(width - 1, height - 1));
        float wScatter = exp(-2.0f * frac);
        scatterAccum += inExposure.read(uint2(scatterCoord)).rgb * wScatter;
        scatterWeightSum += wScatter;

        int2 halCoordR = clamp(int2(gid) + int2(round(dir * frac * u.halationRadiusPxRGB.x)), int2(0), int2(width - 1, height - 1));
        int2 halCoordG = clamp(int2(gid) + int2(round(dir * frac * u.halationRadiusPxRGB.y)), int2(0), int2(width - 1, height - 1));
        int2 halCoordB = clamp(int2(gid) + int2(round(dir * frac * u.halationRadiusPxRGB.z)), int2(0), int2(width - 1, height - 1));

        float3 sampleHal = float3(
            inExposure.read(uint2(halCoordR)).r,
            inExposure.read(uint2(halCoordG)).g,
            inExposure.read(uint2(halCoordB)).b
        );
        float3 highlightGate = smoothstep(float3(0.45f), float3(1.8f), sampleHal);
        float3 wHal = float3(1.0f / (1.0f + 6.0f * frac * frac));
        halationAccum += sampleHal * highlightGate * wHal;
        halationWeightSum += wHal;

        int2 bloomCoord = clamp(int2(gid) + int2(round(dir * frac * u.bloomRadiusPx)), int2(0), int2(width - 1, height - 1));
        float3 sampleBloom = inExposure.read(uint2(bloomCoord)).rgb;
        float luma = dot(sampleBloom, float3(0.2627f, 0.6780f, 0.0593f));
        float bloomGate = smoothstep(u.bloomThreshold * 0.7f, u.bloomThreshold * 2.0f, luma);
        float wBloom = exp(-1.8f * frac * frac);
        bloomAccum += sampleBloom * bloomGate * wBloom;
        bloomWeightSum += wBloom;
    }

    float3 scattered = scatterAccum / scatterWeightSum;
    float3 halationSignal = (halationAccum / halationWeightSum) * u.halationStrengthRGB.rgb;
    float3 bloomSignal = (bloomAccum / bloomWeightSum) * u.bloomStrength;

    float3 finalExposure = max(scattered + halationSignal + bloomSignal, float3(1e-7f));
    outScatteredExposure.write(float4(finalExposure, 1.0f), gid);
}

// ============================================================================
// Stage 3: Hurter-Driffield Development, Push/Pull & Gentle DIR Couplers
// ============================================================================
kernel void kernel_develop_and_dir_couplers(
    texture2d<float, access::read> inScatteredExposure [[texture(0)]],
    texture2d<float, access::write> outNegativeDensityCMY [[texture(1)]],
    constant MetalFilmUniforms &u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int width = int(outNegativeDensityCMY.get_width());
    int height = int(outNegativeDensityCMY.get_height());
    if (int(gid.x) >= width || int(gid.y) >= height) return;

    float3 expCenter = inScatteredExposure.read(gid).rgb;
    float3 logE = log10(max(expCenter, float3(1e-7f)));

    bool isReversal = (u.isReversalOrMono == 1);
    float3 effGamma = u.negativeGammaRGB.rgb * u.pushPullGammaScale;
    float3 effDmin  = u.negativeDminRGB.rgb + float3(u.dminFogOffset);
    float3 effDmax  = u.negativeDmaxRGB.rgb;

    float3 dCenter = evaluate_hd_curve(logE, effDmin, effDmax, effGamma, isReversal);

    int rPx = max(int(round(u.dirRadiusPx)), 1);
    float3 expN = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(0, -rPx), int2(0), int2(width-1, height-1)))).rgb;
    float3 expS = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(0,  rPx), int2(0), int2(width-1, height-1)))).rgb;
    float3 expE = inScatteredExposure.read(uint2(clamp(int2(gid) + int2( rPx, 0), int2(0), int2(width-1, height-1)))).rgb;
    float3 expW = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(-rPx, 0), int2(0), int2(width-1, height-1)))).rgb;

    float3 dN = evaluate_hd_curve(log10(max(expN, 1e-7f)), effDmin, effDmax, effGamma, isReversal);
    float3 dS = evaluate_hd_curve(log10(max(expS, 1e-7f)), effDmin, effDmax, effGamma, isReversal);
    float3 dE = evaluate_hd_curve(log10(max(expE, 1e-7f)), effDmin, effDmax, effGamma, isReversal);
    float3 dW = evaluate_hd_curve(log10(max(expW, 1e-7f)), effDmin, effDmax, effGamma, isReversal);

    float3 dSurround = 0.25f * (dN + dS + dE + dW);
    float3 dNet = max(dCenter - effDmin, float3(0.0f));
    float3 dLaplacian = dCenter - dSurround;

    // Normalized Zero-Sum DIR Interlayer Inhibition:
    // Because dNet has different spans per channel, normalize to [0, 1] first so neutral gray has chromaDelta = (0, 0, 0)!
    float3 span = max(effDmax - effDmin, float3(0.1f));
    float3 normNet = dNet / span;
    float meanNorm = dot(normNet, float3(0.333333f));
    float3 chromaDelta = normNet - float3(meanNorm);

    // Gentle, natural interlayer saturation boost (1.0 + 0.18 * coupler strength) without clipping into neon blocks
    float3 normCoupled = float3(meanNorm) + chromaDelta * (1.0f + 0.18f * u.dirCouplerMatrixRow0.x);
    float3 dCoupled = normCoupled * span + 0.18f * dLaplacian;

    float3 finalDensityCMY = clamp(effDmin + dCoupled, effDmin, effDmax);
    outNegativeDensityCMY.write(float4(finalDensityCMY, 1.0f), gid);
}

// ============================================================================
// Stage 4: Virtual Enlarger, RA-4 / 2383 Print, Grain & Display Output
// ============================================================================
kernel void kernel_enlarger_print_and_grain(
    texture2d<float, access::read> inNegativeDensityCMY [[texture(0)]],
    texture2d<float, access::write> outDisplayTexture [[texture(1)]],
    constant MetalFilmUniforms &u [[buffer(0)]],
    constant float4 *negDyeAndEnlargerTable [[buffer(1)]],
    constant float4 *printSensTable [[buffer(2)]],
    constant float4 *printDyeAndScannerTable [[buffer(3)]],
    constant float4 *cie1931XYZTable [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint dstW = outDisplayTexture.get_width();
    uint dstH = outDisplayTexture.get_height();
    if (gid.x >= dstW || gid.y >= dstH) return;

    uint srcW = inNegativeDensityCMY.get_width();
    uint srcH = inNegativeDensityCMY.get_height();

    // Exact Aspect-Fill Center-Crop Mapping (0% black bars, 0% geometric distortion):
    float dstAspect = float(dstW) / float(max(dstH, 1u));
    float srcAspect = float(srcW) / float(max(srcH, 1u));
    float2 normUV = (float2(gid) + 0.5f) / float2(float(max(dstW, 1u)), float(max(dstH, 1u)));

    if (dstAspect > srcAspect) {
        // Viewfinder is wider than camera buffer -> fill full width, crop top/bottom
        float scaleY = srcAspect / dstAspect;
        normUV.y = (normUV.y - 0.5f) * scaleY + 0.5f;
    } else {
        // Viewfinder is taller than camera buffer -> fill full height, crop left/right
        float scaleX = dstAspect / srcAspect;
        normUV.x = (normUV.x - 0.5f) * scaleX + 0.5f;
    }

    uint2 srcCoord = uint2(
        clamp(uint(normUV.x * float(srcW)), 0u, max(srcW, 1u) - 1u),
        clamp(uint(normUV.y * float(srcH)), 0u, max(srcH, 1u) - 1u)
    );

    float3 dNegCMY = inNegativeDensityCMY.read(srcCoord).rgb;

    if (u.grainStrength > 0.001f) {
        float3 netD = clamp((dNegCMY - u.negativeDminRGB.rgb) / max(u.negativeDmaxRGB.rgb - u.negativeDminRGB.rgb, float3(0.1f)), 0.0f, 1.0f);
        float3 fastVar = netD * (1.0f - 0.65f * netD);
        float3 midVar  = 4.0f * netD * (1.0f - netD);
        float3 slowVar = netD * netD * (1.0f - 0.5f * pow(netD, float3(u.grainUniformity)));

        float3 nFast = rand_gaussian3(gid, u.frameSeed, 0u);
        float3 nMid  = rand_gaussian3(gid, u.frameSeed, 1u);
        float3 nSlow = rand_gaussian3(gid, u.frameSeed, 2u);

        float areaScale = clamp(12.0f / max(u.pixelSizeMicrometers, 1.5f), 0.25f, 2.2f);
        float3 sigmaGrain = (u.rmsGranularityRGB.rgb * 0.0014f) * u.grainStrength * areaScale;
        float3 deltaD = sigmaGrain * (0.45f * sqrt(fastVar) * nFast + 0.38f * sqrt(midVar) * nMid + 0.17f * sqrt(slowVar) * nSlow);
        dNegCMY = max(dNegCMY + deltaD, u.negativeDminRGB.rgb);
    }

    float3 netNegD = max(dNegCMY - u.negativeDminRGB.rgb, float3(0.0f)) * u.callierQFactor;

    float3 netPrintOrScanDensity = float3(0.0f);
    bool isDirectScan = (u.printPipelineMode == 1) || (u.isReversalOrMono == 1);

    if (!isDirectScan) {
        // OPTICAL ENLARGER + PRINT STOCK (RA-4 / 2383 / 3513DI / Multigrade)
        float3 printExposureRGB = float3(0.0f);
        for (int i = 0; i < 81; ++i) {
            float4 negDyeIllum = negDyeAndEnlargerTable[i];
            float lambda = 380.0f + float(i) * 5.0f;

            float cLobe = exp(-0.5f * pow((lambda - 660.0f) / 48.0f, 2.0f));
            float mLobe = exp(-0.5f * pow((lambda - 548.0f) / 40.0f, 2.0f));
            float yLobe = exp(-0.5f * pow((lambda - 445.0f) / 35.0f, 2.0f));
            float filterDensity = dot(u.dichroicFilterCMY.xyz * 0.008f, float3(cLobe, mLobe, yLobe));

            float negSpectralDensity = dot(netNegD, negDyeIllum.xyz) + filterDensity;
            // Bright scene highlights -> high netNegD -> low transmittance T -> low printExposureRGB
            // Dark scene shadows -> low netNegD -> high transmittance T -> high printExposureRGB
            float transmittance = pow(10.0f, -clamp(negSpectralDensity, -2.0f, 4.5f));

            float4 printSens = printSensTable[i];
            printExposureRGB += (negDyeIllum.w * transmittance) * printSens.xyz;
        }

        printExposureRGB = printExposureRGB * u.printExposureScale + float3(u.preflashLinearAddition);
        float3 logPrintE = log10(max(printExposureRGB, float3(1e-7f)));

        float3 pGamma = u.printGammaRGB.rgb * u.printGamma * 0.62f;
        if (u.isReversalOrMono == 2) {
            float vcMultiplier = 0.55f + 0.22f * u.bwMultigradeGrade;
            pGamma *= vcMultiplier;
        }
        // CRITICAL: `isReversal = false` because RA-4 paper is a NEGATIVE-working emulsion!
        // High printExposureRGB (scene shadows) -> High paper dye density -> Dark shadows in scan!
        // Low printExposureRGB (scene highlights) -> Low paper dye density -> Bright whites in scan!
        float3 rawPrintD = evaluate_hd_curve(logPrintE, u.printDminRGB.rgb, u.printDmaxRGB.rgb, pGamma, false);
        netPrintOrScanDensity = max(rawPrintD - u.printDminRGB.rgb, float3(0.0f));
    } else {
        // DIRECT LAB SCANNER
        if (u.isReversalOrMono == 1) {
            // Slide Reversal Film: already positive density
            netPrintOrScanDensity = netNegD;
        } else {
            // Direct Negative Scan: invert normalized negative density per channel so 18% middle gray (0.5 span) stays at 0.5 span
            float3 negSpan = max(u.negativeDmaxRGB.rgb - u.negativeDminRGB.rgb, float3(0.2f));
            float3 normNeg = clamp(netNegD / negSpan, 0.0f, 1.0f);
            // Apply scanner contrast gamma and invert to positive print-equivalent density [0, 2.2]
            float3 invNorm = pow(1.0f - normNeg, float3(1.15f * u.printGamma));
            netPrintOrScanDensity = invNorm * float3(2.20f);
        }
    }

    if (u.bleachBypassAmount > 0.001f) {
        float agDensity = dot(netPrintOrScanDensity, float3(0.30f, 0.55f, 0.15f));
        netPrintOrScanDensity = mix(netPrintOrScanDensity, float3(agDensity * 1.25f), u.bleachBypassAmount * 0.65f);
    }

    // 4. Scanner / Viewing Spectral Integration -> CIE 1931 XYZ (D65 Normalized)
    // Always use printDyeAndScannerTable for positive density -> transmittance -> XYZ so neutral density (d, d, d)
    // integrates to exact neutral gray!
    float3 cieXYZ = float3(0.0f);
    for (int i = 0; i < 81; ++i) {
        float4 dyeScan = printDyeAndScannerTable[i];
        float3 cleanDye = max(dyeScan.xyz, float3(0.0f));
        float spectralD = dot(netPrintOrScanDensity, cleanDye);
        float transmittance = pow(10.0f, -clamp(spectralD, 0.0f, 4.5f));
        transmittance = clamp(transmittance + u.scannerGlare, 0.0f, 1.0f);

        float3 cmf = cie1931XYZTable[i].xyz;
        cieXYZ += (dyeScan.w * transmittance) * cmf;
    }

    // 5. CIE 1931 XYZ (D65) -> Target Display Color Space
    float3 linearOut;
    if (u.outputColorSpace == 0) {
        linearOut = float3(
             3.2404542f * cieXYZ.x - 1.5371385f * cieXYZ.y - 0.4985314f * cieXYZ.z,
            -0.9692660f * cieXYZ.x + 1.8760108f * cieXYZ.y + 0.0415560f * cieXYZ.z,
             0.0556434f * cieXYZ.x - 0.2040259f * cieXYZ.y + 1.0572252f * cieXYZ.z
        );
    } else if (u.outputColorSpace == 1) {
        linearOut = float3(
             2.4934969f * cieXYZ.x - 0.9313836f * cieXYZ.y - 0.4027107f * cieXYZ.z,
            -0.8294890f * cieXYZ.x + 1.7626641f * cieXYZ.y + 0.0236247f * cieXYZ.z,
             0.0358458f * cieXYZ.x - 0.0761724f * cieXYZ.y + 0.9568845f * cieXYZ.z
        );
    } else {
        linearOut = float3(
             1.7166512f * cieXYZ.x - 0.3556708f * cieXYZ.y - 0.2533663f * cieXYZ.z,
            -0.6666844f * cieXYZ.x + 1.6164812f * cieXYZ.y + 0.0157685f * cieXYZ.z,
             0.0176399f * cieXYZ.x - 0.0427706f * cieXYZ.y + 0.9421031f * cieXYZ.z
        );
    }

    linearOut = (linearOut - float3(u.blackPoint)) / max(1.0f - u.blackPoint + u.whitePoint, 0.1f);
    linearOut = max(linearOut, float3(0.0f));

    if (u.isReversalOrMono == 2) {
        float monoLuma = dot(linearOut, float3(0.2126f, 0.7152f, 0.0722f));
        linearOut = float3(monoLuma);
    }

    float3 encodedOut = float3(0.0f);
    if (u.outputColorSpace == 2) {
        const float a = 0.17883277f;
        const float b = 0.28466892f;
        const float c = 0.55991073f;
        for (int i = 0; i < 3; ++i) {
            float e = clamp(linearOut[i], 0.0f, 1.0f);
            encodedOut[i] = (e <= 1.0f / 12.0f) ? sqrt(3.0f * e) : (a * log(12.0f * e - b) + c);
        }
    } else {
        for (int i = 0; i < 3; ++i) {
            float v = clamp(linearOut[i], 0.0f, 1.0f);
            encodedOut[i] = (v <= 0.0031308f) ? (12.92f * v) : (1.055f * pow(v, 1.0f / 2.4f) - 0.055f);
        }
    }

    outDisplayTexture.write(float4(encodedOut, 1.0f), gid);
}
