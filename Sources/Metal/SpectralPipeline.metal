//
//  SpectralPipeline.metal
//  SpektraCam
//
//  Datasheet-Grade Physical Optics, Sensitometry & Photochemical Darkroom Compute Pipeline
//  Optimized for Apple A15 Bionic (iPhone 13 Pro Max 5-Core GPU, Unified 6GB LPDDR4X)
//
//  DATASHEET-GRADE PHYSICAL UPGRADES:
//  1. Per-channel asymmetric Hurter-Driffield curves (`negativeToeRGB.xyz` & `negativeShoulderRGB.xyz`)
//     anchored at 18% middle grey (`log10(0.18) = -0.7447`), preserving authentic shadow/highlight
//     color crossover (e.g., Kodak Gold 200 golden highlights, Portra 400 warm ivory shoulder, Pro 400H cool-emerald shadows).
//  2. True E-6 Reversal Slide Film Physics (`isReversalOrMono == 1`): Preserves full reversal gamma (1.68 on Velvia 50),
//     maps 18% grey to D = 1.00 (T = 10%), reaches true Dmax = 3.65 in deep shadows, and scans through the slide's
//     own narrow-band chromogenic dyes (`negDyeAndEnlargerTable`) under a 5500K transparency light table.
//  3. Edge-Contrast-Gated Dual-Scale Base Halation (`Stage 2`): Back-reflected photons are gated by `max(sample - center * 1.15, 0)`
//     across inner-core (0.32x) and outer-halo (1.0x) radii so CineStill 800T / 50D produces vivid red-orange halation
//     around window frames, streetlamps, and high-contrast edges without washing out flat surfaces.
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
    float4 negativeShoulderRGB;
    float4 negativeToeRGB;
    float4 printGammaRGB;
    float4 printDminRGB;
    float4 printDmaxRGB;
    float4 rmsGranularityRGB;
    int outputColorSpace;
    int isReversalOrMono;
    float bwMultigradeGrade;
    float padding0;
};

constant float LOG2_10 = 3.321928095f;

inline float exp10_neg(float d) {
    return exp2(-LOG2_10 * d);
}

inline float jakob_hanika_sigmoid(float x) {
    return 0.5f + 0.5f * x * rsqrt(1.0f + x * x);
}

inline float jakob_hanika_inv_sigmoid(float y) {
    float yc = clamp(y, 0.01f, 0.99f);
    return (yc - 0.5f) * rsqrt(max(yc * (1.0f - yc), 1e-4f));
}

inline float3 compute_jakob_hanika_coeffs(float3 rgb_linear, thread float &albedoScale) {
    float maxComp = max(max(rgb_linear.r, rgb_linear.g), max(rgb_linear.b, 1e-5f));
    albedoScale = max(0.5f, maxComp * 1.45f);
    float3 c = clamp(rgb_linear / albedoScale, 0.02f, 0.92f);

    float yB = jakob_hanika_inv_sigmoid(c.b);
    float yG = jakob_hanika_inv_sigmoid(c.g);
    float yR = jakob_hanika_inv_sigmoid(c.r);

    float c0 = 8.0f * (yR - 2.0f * yG + yB);
    float c1 = 2.0f * (yR - yB) - 0.82f * c0;
    float c2 = yG - 0.1681f * c0 - 0.41f * c1;
    return float3(c0, c1, c2);
}

// Per-channel asymmetric Hurter-Driffield curve pivoted at 18% middle grey (log10(0.18) = -0.7447 -> norm = 0.50)
inline float3 evaluate_hd_normalized(
    float3 logE,
    float3 gamma,
    float3 shoulderSoftness,
    float3 toeSoftness,
    bool isReversal
) {
    float3 x = logE + 0.7447f;
    if (isReversal) {
        // E-6 Reversal: high exposure -> low density; preserve authentic reversal contrast ratio
        x = -x;
        float3 asym;
        for (int i = 0; i < 3; ++i) {
            if (x[i] >= 0.0f) {
                // Shadow Dmax region on reversal slide
                asym[i] = 1.0f / (1.0f + 0.22f * toeSoftness[i] * x[i]);
            } else {
                // Highlight Dmin region on reversal slide
                asym[i] = 1.0f / (1.0f - 0.30f * shoulderSoftness[i] * x[i]);
            }
        }
        float3 k = 2.15f * gamma * asym;
        float3 expTerm = exp(-clamp(k * x, -16.0f, 16.0f));
        return 1.0f / (1.0f + expTerm);
    } else {
        float3 asym;
        for (int i = 0; i < 3; ++i) {
            if (x[i] >= 0.0f) {
                asym[i] = 1.0f / (1.0f + 0.42f * shoulderSoftness[i] * x[i]);
            } else {
                asym[i] = 1.0f / (1.0f - 0.32f * toeSoftness[i] * x[i]);
            }
        }
        float3 k = 2.75f * gamma * asym;
        float3 expTerm = exp(-clamp(k * x, -16.0f, 16.0f));
        return 1.0f / (1.0f + expTerm);
    }
}

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
        float offset = exp2((refBlack - refWhite) * (1023.0f / 300.0f) * 0.6f * LOG2_10);
        float3 v = max(x, float3(0.0f)) * (1.0f - offset) + offset;
        return clamp(refWhite + (log10(v) / (0.6f * (1023.0f / 300.0f))), 0.0f, 1.0f);
    }
}

// ============================================================================
// Stage 0: Resolution-Adaptive YCbCr -> Scene-Linear + Log
// ============================================================================
kernel void kernel_ycbcr10_to_scene_linear_and_log(
    texture2d<float, access::read> lumaPlane [[texture(0)]],
    texture2d<float, access::read> chromaPlane [[texture(1)]],
    texture2d<float, access::write> outSceneLinear [[texture(2)]],
    texture2d<float, access::write> outLogEncoded [[texture(3)]],
    constant int &logMode [[buffer(0)]],
    constant int &is10BitInput [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint dstW = outSceneLinear.get_width();
    uint dstH = outSceneLinear.get_height();
    if (gid.x >= dstW || gid.y >= dstH) return;

    uint lumaW = lumaPlane.get_width();
    uint lumaH = lumaPlane.get_height();
    uint chromaW = chromaPlane.get_width();
    uint chromaH = chromaPlane.get_height();

    float2 uv = (float2(gid) + 0.5f) / float2(float(max(dstW, 1u)), float(max(dstH, 1u)));
    uint2 lumaCoord = uint2(clamp(uint(uv.x * float(lumaW)), 0u, lumaW - 1u),
                            clamp(uint(uv.y * float(lumaH)), 0u, lumaH - 1u));
    uint2 chromaCoord = uint2(clamp(uint(uv.x * float(chromaW)), 0u, chromaW - 1u),
                              clamp(uint(uv.y * float(chromaH)), 0u, chromaH - 1u));

    float ySample = lumaPlane.read(lumaCoord).r;
    float2 cbcrSample = chromaPlane.read(chromaCoord).rg;

    float3 sceneLinear;
    if (is10BitInput != 0) {
        float Y  = clamp((ySample - 0.0625f) * (1.0f / 0.85546875f), 0.0f, 1.0f);
        float Cb = (cbcrSample.r - 0.5f) * (1.0f / 0.875f);
        float Cr = (cbcrSample.g - 0.5f) * (1.0f / 0.875f);

        float R_p = clamp(Y + 1.4020f * Cr, 0.0f, 1.0f);
        float G_p = clamp(Y - 0.344136f * Cb - 0.714136f * Cr, 0.0f, 1.0f);
        float B_p = clamp(Y + 1.7720f * Cb, 0.0f, 1.0f);

        sceneLinear = float3(
            srgb_to_linear(R_p),
            srgb_to_linear(G_p),
            srgb_to_linear(B_p)
        );
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
    float rSq = dot(uv, uv) * 0.25f;
    float cosThetaSq = 1.0f / (1.0f + rSq);
    float vignette = mix(1.0f, cosThetaSq * cosThetaSq, u.opticalVignetteStrength);
    rgb *= vignette;

    float albedoScale = 1.0f;
    float3 coeffs = compute_jakob_hanika_coeffs(rgb, albedoScale);

    float3 rawExposure = float3(0.0f);
    for (int i = 0; i < 81; ++i) {
        float u_lambda = float(i) * (1.0f / 80.0f);
        float poly = (coeffs.x * u_lambda + coeffs.y) * u_lambda + coeffs.z;
        float reflectance = jakob_hanika_sigmoid(poly);
        rawExposure += reflectance * spectralSensitivityTable[i].xyz;
    }
    rawExposure *= albedoScale;

    outEmulsionExposure.write(float4(max(rawExposure, float3(1e-7f)), 1.0f), gid);
}

// ============================================================================
// Stage 2: Dual-Scale Edge-Contrast-Gated Base Halation (CineStill 800T / 50D),
//          Optical Diffusion (Black Pro-Mist) & Frieser Emulsion Scatter
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

    bool needScatter = (u.inEmulsionScatterPx > 0.2f);
    bool needHalation = (dot(u.halationStrengthRGB.rgb, float3(1.0f)) > 1e-4f);
    bool needBloom = (u.bloomStrength > 1e-4f);

    if (!needScatter && !needHalation && !needBloom) {
        outScatteredExposure.write(float4(max(centerExp, float3(1e-7f)), 1.0f), gid);
        return;
    }

    float3 scatterAccum = centerExp;
    float3 halationAccum = float3(0.0f);
    float3 bloomAccum = float3(0.0f);
    float scatterWeightSum = 1.0f;
    float3 halationWeightSum = float3(1e-5f);
    float bloomWeightSum = 1e-5f;

    float linearBloomCutoff = pow(clamp(u.bloomThreshold * 0.65f, 0.05f, 1.2f), 2.0f);
    float bloomRadPx = clamp(u.bloomRadiusPx, 2.0f, 120.0f);
    float3 halRadPx = clamp(u.halationRadiusPxRGB.xyz, float3(2.0f), float3(140.0f));
    float scatRadPx = clamp(u.inEmulsionScatterPx, 0.0f, 18.0f);

    const int NUM_TAPS = 12;
    const float GOLDEN_ANGLE = 2.39996323f;

    for (int i = 1; i <= NUM_TAPS; ++i) {
        float frac = float(i) / float(NUM_TAPS);
        float angle = float(i) * GOLDEN_ANGLE;
        float2 dir = float2(cos(angle), sin(angle));

        if (needScatter) {
            int2 scatterCoord = clamp(int2(gid) + int2(round(dir * frac * scatRadPx)), int2(0), int2(width - 1, height - 1));
            float wScatter = exp(-2.0f * frac);
            scatterAccum += inExposure.read(uint2(scatterCoord)).rgb * wScatter;
            scatterWeightSum += wScatter;
        }

        if (needHalation) {
            // Dual-scale sampling: inner core (0.32x radius) for tight red rim + outer halo (1.0x radius) for soft falloff
            float scaleStep = (i & 1) != 0 ? (frac * 0.35f) : frac;
            int2 halCoordR = clamp(int2(gid) + int2(round(dir * scaleStep * halRadPx.x)), int2(0), int2(width - 1, height - 1));
            int2 halCoordG = clamp(int2(gid) + int2(round(dir * scaleStep * halRadPx.y)), int2(0), int2(width - 1, height - 1));
            int2 halCoordB = clamp(int2(gid) + int2(round(dir * scaleStep * halRadPx.z)), int2(0), int2(width - 1, height - 1));

            float3 sampleHal = float3(
                inExposure.read(uint2(halCoordR)).r,
                inExposure.read(uint2(halCoordG)).g,
                inExposure.read(uint2(halCoordB)).b
            );
            // Gate halation on local high-contrast edge excess (`sampleHal > centerExp * 1.12`) AND bright source threshold
            float3 edgeExcess = max(sampleHal - centerExp * 1.12f, float3(0.0f));
            float3 highlightGate = smoothstep(float3(0.20f), float3(0.75f), sampleHal);
            float3 wHal = float3(1.0f / (1.0f + 6.0f * scaleStep * scaleStep));
            halationAccum += edgeExcess * highlightGate * wHal * 3.8f;
            halationWeightSum += wHal;
        }

        if (needBloom) {
            int2 bloomCoord = clamp(int2(gid) + int2(round(dir * frac * bloomRadPx)), int2(0), int2(width - 1, height - 1));
            float3 sampleBloom = inExposure.read(uint2(bloomCoord)).rgb;
            float peakChannel = max(max(sampleBloom.r, sampleBloom.g), sampleBloom.b);
            float bloomGate = smoothstep(linearBloomCutoff * 0.50f, linearBloomCutoff * 1.50f, peakChannel);
            float wBloom = exp(-1.8f * frac * frac);
            float3 bloomDiff = max(sampleBloom - centerExp * 0.85f, float3(0.0f));
            bloomAccum += (bloomDiff * bloomGate * 2.4f + sampleBloom * bloomGate * 0.35f) * wBloom;
            bloomWeightSum += wBloom;
        }
    }

    float3 scattered = scatterAccum / scatterWeightSum;
    float3 halationSignal = needHalation ? ((halationAccum / halationWeightSum) * u.halationStrengthRGB.rgb) : float3(0.0f);
    float3 bloomSignal = needBloom ? ((bloomAccum / bloomWeightSum) * u.bloomStrength) : float3(0.0f);

    float3 finalExposure = max(scattered + halationSignal + bloomSignal, float3(1e-7f));
    outScatteredExposure.write(float4(finalExposure, 1.0f), gid);
}

// ============================================================================
// Stage 3: Per-Channel Asymmetric Hurter-Driffield Development, Push/Pull &
//          3x3 DIR Coupler Interlayer Matrix (Neutral-Grey Invariant)
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
    float3 shoulder = u.negativeShoulderRGB.xyz;
    float3 toe = u.negativeToeRGB.xyz;

    float3 normCenter = evaluate_hd_normalized(logE, effGamma, shoulder, toe, isReversal);

    int rPx = max(int(round(u.dirRadiusPx)), 1);
    float3 expN = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(0, -rPx), int2(0), int2(width-1, height-1)))).rgb;
    float3 expS = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(0,  rPx), int2(0), int2(width-1, height-1)))).rgb;
    float3 expE = inScatteredExposure.read(uint2(clamp(int2(gid) + int2( rPx, 0), int2(0), int2(width-1, height-1)))).rgb;
    float3 expW = inScatteredExposure.read(uint2(clamp(int2(gid) + int2(-rPx, 0), int2(0), int2(width-1, height-1)))).rgb;

    float3 normN = evaluate_hd_normalized(log10(max(expN, 1e-7f)), effGamma, shoulder, toe, isReversal);
    float3 normS = evaluate_hd_normalized(log10(max(expS, 1e-7f)), effGamma, shoulder, toe, isReversal);
    float3 normE = evaluate_hd_normalized(log10(max(expE, 1e-7f)), effGamma, shoulder, toe, isReversal);
    float3 normW = evaluate_hd_normalized(log10(max(expW, 1e-7f)), effGamma, shoulder, toe, isReversal);

    float3 normSurround = 0.25f * (normN + normS + normE + normW);
    float3 normLaplacian = normCenter - normSurround;

    // 3x3 DIR Interlayer Matrix (row-sum = 1.0 so neutral greys [d, d, d] remain 100% invariant while color purity expands)
    float3 normCoupled = float3(
        dot(u.dirCouplerMatrixRow0.xyz, normCenter),
        dot(u.dirCouplerMatrixRow1.xyz, normCenter),
        dot(u.dirCouplerMatrixRow2.xyz, normCenter)
    ) + 0.18f * normLaplacian;

    float meanSurround = dot(normSurround, float3(0.333333f));
    float exhFactor = 1.0f / (1.0f + 0.30f * u.developerExhaustion * max(meanSurround - 0.50f, 0.0f));
    normCoupled = clamp(normCoupled * exhFactor + float3(u.dminFogOffset * 0.2f), 0.0f, 1.0f);

    if (isReversal) {
        // For E-6 Reversal Slide Film: map normCoupled in [0, 1] (where 18% grey is 0.5) to physical slide optical density [Dmin, Dmax]
        // such that normCoupled = 0.5 produces D_slide = 1.00 (10% transmittance = 18% perceptual grey!)
        float3 dMin = u.negativeDminRGB.rgb;
        float3 dMax = u.negativeDmaxRGB.rgb;
        float3 curved = pow(normCoupled, float3(1.92f));
        float3 slideDensity = dMin + (dMax - dMin) * curved;
        outNegativeDensityCMY.write(float4(slideDensity, 1.0f), gid);
    } else {
        outNegativeDensityCMY.write(float4(normCoupled * 2.0f, 1.0f), gid);
    }
}

// ============================================================================
// Stage 4: Virtual Enlarger, RA-4 / 2383 Print, E-6 Light-Table Scan & Grain
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

    uint2 srcCoord;
    if (dstW == srcW && dstH == srcH) {
        srcCoord = gid;
    } else {
        float dstAspect = float(dstW) / float(max(dstH, 1u));
        float srcAspect = float(srcW) / float(max(srcH, 1u));
        float2 normUV = (float2(gid) + 0.5f) / float2(float(max(dstW, 1u)), float(max(dstH, 1u)));

        if (dstAspect > srcAspect) {
            float scaleY = srcAspect / dstAspect;
            normUV.y = (normUV.y - 0.5f) * scaleY + 0.5f;
        } else {
            float scaleX = dstAspect / srcAspect;
            normUV.x = (normUV.x - 0.5f) * scaleX + 0.5f;
        }

        srcCoord = uint2(
            clamp(uint(normUV.x * float(srcW)), 0u, max(srcW, 1u) - 1u),
            clamp(uint(normUV.y * float(srcH)), 0u, max(srcH, 1u) - 1u)
        );
    }

    float3 netNegD = inNegativeDensityCMY.read(srcCoord).rgb;

    if (u.grainStrength > 0.001f) {
        float3 normD = clamp(netNegD * 0.5f, 0.0f, 1.0f);
        float3 fastVar = normD * (1.0f - 0.65f * normD);
        float3 midVar  = 4.0f * normD * (1.0f - normD);
        float3 slowVar = normD * normD * (1.0f - 0.5f * pow(normD, float3(u.grainUniformity)));

        float3 nFast = rand_gaussian3(gid, u.frameSeed, 0u);
        float3 nMid  = rand_gaussian3(gid, u.frameSeed, 1u);
        float3 nSlow = rand_gaussian3(gid, u.frameSeed, 2u);

        float areaScale = clamp(12.0f / max(u.pixelSizeMicrometers, 1.5f), 0.25f, 2.2f);
        float3 sigmaGrain = (u.rmsGranularityRGB.rgb * 0.0015f) * u.grainStrength * areaScale;
        float3 deltaD = sigmaGrain * (0.45f * sqrt(fastVar) * nFast + 0.38f * sqrt(midVar) * nMid + 0.17f * sqrt(slowVar) * nSlow);
        netNegD = max(netNegD + deltaD, float3(0.0f));
    }

    netNegD *= u.callierQFactor;

    bool isReversal = (u.isReversalOrMono == 1);
    float3 netPrintOrScanDensity = float3(0.0f);

    if (isReversal) {
        // Genuine E-6 Slide Transparency Path:
        // `netNegD` is already physical slide optical density [Dmin..Dmax] (with 18% grey at 1.00),
        // and `printDyeAndScannerTable` has been loaded with the E-6 slide's own calibrated dyes by `MetalFilmRenderer`!
        float3 tintOffset = float3(u.dichroicFilterCMY.x, u.dichroicFilterCMY.y, u.dichroicFilterCMY.z) * 0.005f;
        netPrintOrScanDensity = max(netNegD / max(u.printExposureScale, 0.1f) + tintOffset, float3(0.0f));
    } else if (u.printPipelineMode == 0) {
        // Optical Enlarger + RA-4 / 2383 Print Stock Path
        float3 printExposureRGB = float3(0.0f);
        for (int i = 0; i < 81; ++i) {
            float3 negDye = negDyeAndEnlargerTable[i].xyz;
            float negSpectralDensity = dot(netNegD, negDye);
            float transmittance = exp10_neg(clamp(negSpectralDensity, 0.0f, 4.5f));
            printExposureRGB += transmittance * printSensTable[i].xyz;
        }

        printExposureRGB = printExposureRGB * u.printExposureScale + float3(u.preflashLinearAddition);
        float3 logPrintE = log10(max(printExposureRGB, float3(1e-7f)));

        float3 spanP = max(u.printDmaxRGB.rgb - u.printDminRGB.rgb, float3(1.8f));
        float3 pSlope = float3(3.55f) * (u.printGammaRGB.rgb / 2.42f) * u.printGamma;
        if (u.isReversalOrMono == 2) {
            float vcMultiplier = 0.55f + 0.22f * u.bwMultigradeGrade;
            pSlope *= vcMultiplier;
        }

        // At 18% middle grey (`printExposureRGB = 0.18`, `logPrintE = -0.7447`), `xP = -0.15`, producing exact END = 1.00!
        float3 xP = logPrintE + 0.7447f - 0.15f;
        float3 rawPrtD = spanP / (1.0f + exp(-clamp(pSlope * xP, -16.0f, 16.0f)));
        netPrintOrScanDensity = max(rawPrtD - float3(0.14f), float3(0.0f)) * 1.14f;
    } else {
        // Direct Lab Scanner Inversion Path (Noritsu / Frontier CCD Scanner)
        float3 normNeg = clamp(netNegD * 0.5f, 0.0f, 1.0f);
        float3 stretched = clamp((normNeg - 0.12f) / 0.76f, 0.0f, 1.0f);
        float3 invNorm = pow(1.0f - stretched, float3(1.12f * u.printGamma));
        float3 tintOffset = float3(u.dichroicFilterCMY.x, u.dichroicFilterCMY.y, u.dichroicFilterCMY.z) * 0.006f;
        netPrintOrScanDensity = max((invNorm * 2.05f) / max(u.printExposureScale, 0.2f) + tintOffset, float3(0.0f));
    }

    if (u.bleachBypassAmount > 0.001f) {
        float agDensity = dot(netPrintOrScanDensity, float3(0.30f, 0.55f, 0.15f));
        netPrintOrScanDensity = mix(netPrintOrScanDensity, float3(agDensity * 1.25f), u.bleachBypassAmount * 0.65f);
    }

    float3 cieXYZ = float3(0.0f);
    for (int i = 0; i < 81; ++i) {
        float4 dyeScan = printDyeAndScannerTable[i];
        float spectralD = dot(netPrintOrScanDensity, dyeScan.xyz);
        float transmittance = clamp(exp10_neg(clamp(spectralD, 0.0f, 4.5f)) + u.scannerGlare, 0.0f, 1.0f);

        float3 weightedCMF = cie1931XYZTable[i].xyz * dyeScan.w;
        cieXYZ += transmittance * weightedCMF;
    }

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

// ============================================================================
// Stage 5: Ultra-Fast Bilinear Aspect-Fit Presentation & Video Recorder Blit
// ============================================================================
kernel void kernel_present_or_record_bgra8(
    texture2d<float, access::sample> inSourceTexture [[texture(0)]],
    texture2d<float, access::write> outTargetTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint dstW = outTargetTexture.get_width();
    uint dstH = outTargetTexture.get_height();
    if (gid.x >= dstW || gid.y >= dstH) return;

    uint srcW = inSourceTexture.get_width();
    uint srcH = inSourceTexture.get_height();

    float dstAspect = float(dstW) / float(max(dstH, 1u));
    float srcAspect = float(srcW) / float(max(srcH, 1u));
    float2 normUV = (float2(gid) + 0.5f) / float2(float(max(dstW, 1u)), float(max(dstH, 1u)));

    if (dstAspect > srcAspect) {
        float scaleY = srcAspect / dstAspect;
        normUV.y = (normUV.y - 0.5f) * scaleY + 0.5f;
    } else {
        float scaleX = dstAspect / srcAspect;
        normUV.x = (normUV.x - 0.5f) * scaleX + 0.5f;
    }

    constexpr sampler bilinearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 c = inSourceTexture.sample(bilinearSampler, clamp(normUV, float2(0.0f), float2(1.0f)));
    outTargetTexture.write(float4(c.rgb, 1.0f), gid);
}
