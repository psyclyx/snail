#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
// warning X3557: loop doesn't seem to do anything, forcing loop to unroll
#pragma warning(disable : 3557)
#endif

struct SnailPushConstants_0
{
    float4x4 mvp_0;
    float2 viewport_0;
    int subpixel_order_0;
    int output_srgb_0;
    int layer_base_0;
    float coverage_exponent_0;
    float dither_scale_0;
    int mask_output_0;
};

cbuffer pc_0 : register(b0)
{
    SnailPushConstants_0 pc_0;
}
Texture2DArray<float4 > u_curve_tex_0 : register(t0);

Texture2DArray<uint2 > u_band_tex_0 : register(t1);

Texture2D<float4 > u_layer_tex_0 : register(t2);

int2 offsetTtHintedInfoLoc_0(Texture2D<float4 > layer_tex_0, int2 base_0, int offset_0)
{
    uint uw_0;
    uint uh_0;
    layer_tex_0.GetDimensions(uw_0, uh_0);
    int width_0 = int(uw_0);
    int texel_0 = base_0.y * width_0 + base_0.x + offset_0;
    int _S1 = texel_0 % width_0;
    int _S2 = texel_0 / width_0;
    return int2(_S1, _S2);
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S3;
    _S3.first_0 = first_1;
    _S3.last_0 = last_1;
    return _S3;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S4 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S4), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S4), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S5 = glyphLoc_0.x + int(offset_1);
    int2 loc_0 = int2(_S5, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S5 >> int(12));
    loc_0[int(0)] = (loc_0[int(0)]) & int(4095);
    return loc_0;
}

int decodeBandCurveFirstMemberCommon_0(uint2 ref_0)
{
    return int((ref_0.x) >> 12U);
}

bool isCoverageBandSpanOwner_0(uint2 ref_1, int band_0, int spanFirst_0)
{
    return band_0 == (max(decodeBandCurveFirstMemberCommon_0(ref_1), spanFirst_0));
}

int2 decodeBandCurveLocCommon_0(uint2 ref_2)
{
    return int2(int((ref_2.x) & 4095U), int((ref_2.y) & 16383U));
}

int2 decodeBandCurveLoc_0(uint2 ref_3)
{
    return decodeBandCurveLocCommon_0(ref_3);
}

int2 offsetCurveLoc_0(int2 base_1, int offset_2)
{
    int _S6 = base_1.x + offset_2;
    int2 loc_1 = int2(_S6, base_1.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S6 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S7;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S7 = 0.0f;
    }
    else
    {
        _S7 = v_0;
    }
    return _S7;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S8;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S8 = 0.0f;
    }
    else
    {
        _S8 = sqrt(disc_0);
    }
    return _S8;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S9 = p12_0.xy;
    float2 _S10 = p12_0.zw;
    float2 a_0 = _S9 - _S10 * 2.0f + p3_0;
    float2 b_1 = _S9 - _S10;
    float _S11 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S11)) < 0.0000152587890625f)
    {
        float _S12 = b_1.y;
        if((abs(_S12)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S12;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S13 = b_1.y;
        float _S14 = p12_0.y;
        float _S15 = _S11 * _S14;
        float sq_0 = snapNearTangentSqrt_0(_S13 * _S13 - _S15, _S13, _S15);
        if(_S13 >= 0.0f)
        {
            float q_0 = _S13 + sq_0;
            float _S16 = q_0 / _S11;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S14 / q_0;
            }
            t2_0 = _S16;
        }
        else
        {
            float q_1 = _S13 - sq_0;
            float _S17 = q_1 / _S11;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S14 / q_1;
            }
            float _S18 = t1_0;
            t1_0 = _S17;
            t2_0 = _S18;
        }
    }
    float _S19 = a_0.x;
    float _S20 = b_1.x * 2.0f;
    float _S21 = p12_0.x;
    return float2((_S19 * t1_0 - _S20) * t1_0 + _S21, (_S19 * t2_0 - _S20) * t2_0 + _S21);
}

bool accumulateHorizContribution_0(inout float xcov_0, inout float xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, Texture2DArray<float4 > curve_tex_0)
{
    float4 tex0_0 = curve_tex_0.Load(int4(cLoc_0, texLayer_0, int(0)));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = curve_tex_0.Load(int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0))).xy - rc_0;
    float _S22 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S22) < -0.5f)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * _S22;
        if((code_0 & 1U) != 0U)
        {
            float _S23 = r_0.x;
            xcov_0 = xcov_0 + clamp(_S23 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S23) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > 1U)
        {
            float _S24 = r_0.y;
            xcov_0 = xcov_0 - clamp(_S24 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S24) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S25 = p12_2.xy;
    float2 _S26 = p12_2.zw;
    float2 a_1 = _S25 - _S26 * 2.0f + p3_2;
    float2 b_2 = _S25 - _S26;
    float _S27 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S27)) < 0.0000152587890625f)
    {
        float _S28 = b_2.x;
        if((abs(_S28)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S28;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S29 = b_2.x;
        float _S30 = p12_2.x;
        float _S31 = _S27 * _S30;
        float sq_1 = snapNearTangentSqrt_0(_S29 * _S29 - _S31, _S29, _S31);
        if(_S29 >= 0.0f)
        {
            float q_2 = _S29 + sq_1;
            float _S32 = q_2 / _S27;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S30 / q_2;
            }
            t2_1 = _S32;
        }
        else
        {
            float q_3 = _S29 - sq_1;
            float _S33 = q_3 / _S27;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S30 / q_3;
            }
            float _S34 = t1_1;
            t1_1 = _S33;
            t2_1 = _S34;
        }
    }
    float _S35 = a_1.y;
    float _S36 = b_2.y * 2.0f;
    float _S37 = p12_2.y;
    return float2((_S35 * t1_1 - _S36) * t1_1 + _S37, (_S35 * t2_1 - _S36) * t2_1 + _S37);
}

bool accumulateVertContribution_0(inout float ycov_0, inout float ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, Texture2DArray<float4 > curve_tex_1)
{
    float4 tex0_1 = curve_tex_1.Load(int4(cLoc_1, texLayer_1, int(0)));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = curve_tex_1.Load(int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0))).xy - rc_1;
    float _S38 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S38) < -0.5f)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * _S38;
        if((code_1 & 1U) != 0U)
        {
            float _S39 = r_1.x;
            ycov_0 = ycov_0 - clamp(_S39 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S39) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > 1U)
        {
            float _S40 = r_1.y;
            ycov_0 = ycov_0 + clamp(_S40 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S40) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float applyFillRule_0(float winding_0, int fill_rule_mode_0)
{
    if(fill_rule_mode_0 == int(1))
    {
        return 1.0f - abs(frac(winding_0 * 0.5f) * 2.0f - 1.0f);
    }
    return abs(winding_0);
}

float applyCoverageTransfer_0(float cov_0, float coverage_exponent_1)
{
    float clamped_0 = clamp(cov_0, 0.0f, 1.0f);
    float _S41 = max(coverage_exponent_1, 0.0000152587890625f);
    float _S42;
    if((abs(_S41 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S42 = clamped_0;
    }
    else
    {
        _S42 = pow(clamped_0, _S41);
    }
    return _S42;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_0, float coverage_exponent_2)
{
    bool _S43;
    int i_0;
    int _S44 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S44);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    float xcov_1 = 0.0f;
    float xwgt_1 = 0.0f;
    bool _S45 = (hSpan_0.first_0) != (hSpan_0.last_0);
    int band_1 = hSpan_0.first_0;
    for(;;)
    {
        if(band_1 <= (hSpan_0.last_0))
        {
        }
        else
        {
            break;
        }
        uint2 hbd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(band_1)), texLayer_2, int(0))).xy;
        int2 _S46 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S47 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S47)
            {
            }
            else
            {
                break;
            }
            uint2 ref_4 = band_tex_0.Load(int4(calcBandLoc_0(_S46, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S45)
            {
                _S43 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S43 = false;
            }
            if(_S43)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S48 = accumulateHorizContribution_0(xcov_1, xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S48)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    float ycov_1 = 0.0f;
    float ywgt_1 = 0.0f;
    bool _S49 = (vSpan_0.first_0) != (vSpan_0.last_0);
    band_1 = vSpan_0.first_0;
    for(;;)
    {
        if(band_1 <= (vSpan_0.last_0))
        {
        }
        else
        {
            break;
        }
        uint2 vbd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(_S44 + int(1) + band_1)), texLayer_2, int(0))).xy;
        int2 _S50 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S51 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S51)
            {
            }
            else
            {
                break;
            }
            uint2 ref_5 = band_tex_0.Load(int4(calcBandLoc_0(_S50, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S49)
            {
                _S43 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S43 = false;
            }
            if(_S43)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S52 = accumulateVertContribution_0(ycov_1, ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S52)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), coverage_exponent_2);
}

float4 premultiplyColor_0(float4 color_0, float cov_1)
{
    float alpha_0 = color_0.w * cov_1;
    return float4(color_0.xyz * alpha_0, alpha_0);
}

float srgbEncode_0(float c_0)
{
    float _S53;
    if(c_0 <= 0.00313080009073019f)
    {
        _S53 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S53 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S53;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S54 = premul_0.w;
    if(_S54 <= 0.0f)
    {
        return (float4)0.0f;
    }
    return float4(linearToSrgb_0(premul_0.xyz * (1.0f / _S54)) * _S54, _S54);
}

struct TtHintedVaryings_0
{
    float4 color_2;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_1;
    int4 glyph_0;
};

float4 snailTtHintedTextFragment_0(TtHintedVaryings_0 v_1, Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_1, Texture2D<float4 > layer_tex_1, int layer_base_1, int output_srgb_1, float coverage_exponent_3, int mask_output_1)
{
    int _S55 = v_1.glyph_0.w;
    if(((_S55 >> int(8)) & int(255)) != int(255))
    {
        discard;
    }
    if((_S55 & int(255)) != int(2))
    {
        discard;
    }
    float2 epp_1 = (fwidth((v_1.texcoord_0)));
    float2 ppe_3 = float2(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f));
    int2 info_base_0 = v_1.glyph_0.xy;
    float4 header_0 = layer_tex_1.Load(int3(info_base_0, int(0)));
    int2 _S56 = offsetTtHintedInfoLoc_0(layer_tex_1, info_base_0, int(1));
    int packed_counts_0 = asint(header_0.z);
    float cov_2 = evalGlyphCoverage_0(v_1.texcoord_0, epp_1, ppe_3, int2(int(header_0.x), int(header_0.y)), int2((packed_counts_0 >> int(16)) & int(65535), packed_counts_0 & int(65535)), layer_tex_1.Load(int3(_S56, int(0))), layer_base_1 + int(v_1.banding_1.w), curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    float4 premul_1 = premultiplyColor_0(v_1.color_2 * v_1.tint_0, cov_2);
    float4 _S57;
    if(mask_output_1 != int(0))
    {
        _S57 = (float4)premul_1.w;
    }
    else
    {
        if(output_srgb_1 != int(0))
        {
            _S57 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S57 = premul_1;
        }
    }
    return _S57;
}

struct VsOutput_0
{
    float4 position_0 : SV_Position;
    float4 color_3 : TEXCOORD0;
    float2 texcoord_1 : TEXCOORD1;
    nointerpolation float4 banding_2 : TEXCOORD2;
    nointerpolation int4 glyph_1 : TEXCOORD3;
    float4 tint_1 : TEXCOORD4;
};

float4 fragmentMain(VsOutput_0 input_0) : SV_TARGET
{
    TtHintedVaryings_0 v_2;
    v_2.color_2 = input_0.color_3;
    v_2.tint_0 = input_0.tint_1;
    v_2.texcoord_0 = input_0.texcoord_1;
    v_2.banding_1 = input_0.banding_2;
    v_2.glyph_0 = input_0.glyph_1;
    float4 _S58 = snailTtHintedTextFragment_0(v_2, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    return _S58;
}

