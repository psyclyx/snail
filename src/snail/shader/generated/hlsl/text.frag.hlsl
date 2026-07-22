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

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S1;
    _S1.first_0 = first_1;
    _S1.last_0 = last_1;
    return _S1;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S2 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S2), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S2), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S3 = glyphLoc_0.x + int(offset_0);
    int2 loc_0 = int2(_S3, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S3 >> int(12));
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

int2 offsetCurveLoc_0(int2 base_0, int offset_1)
{
    int _S4 = base_0.x + offset_1;
    int2 loc_1 = int2(_S4, base_0.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S4 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S5;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S5 = 0.0f;
    }
    else
    {
        _S5 = v_0;
    }
    return _S5;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S6;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S6 = 0.0f;
    }
    else
    {
        _S6 = sqrt(disc_0);
    }
    return _S6;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S7 = p12_0.xy;
    float2 _S8 = p12_0.zw;
    float2 a_0 = _S7 - _S8 * 2.0f + p3_0;
    float2 b_1 = _S7 - _S8;
    float _S9 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S9)) < 0.0000152587890625f)
    {
        float _S10 = b_1.y;
        if((abs(_S10)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S10;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S11 = b_1.y;
        float _S12 = p12_0.y;
        float _S13 = _S9 * _S12;
        float sq_0 = snapNearTangentSqrt_0(_S11 * _S11 - _S13, _S11, _S13);
        if(_S11 >= 0.0f)
        {
            float q_0 = _S11 + sq_0;
            float _S14 = q_0 / _S9;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S12 / q_0;
            }
            t2_0 = _S14;
        }
        else
        {
            float q_1 = _S11 - sq_0;
            float _S15 = q_1 / _S9;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S12 / q_1;
            }
            float _S16 = t1_0;
            t1_0 = _S15;
            t2_0 = _S16;
        }
    }
    float _S17 = a_0.x;
    float _S18 = b_1.x * 2.0f;
    float _S19 = p12_0.x;
    return float2((_S17 * t1_0 - _S18) * t1_0 + _S19, (_S17 * t2_0 - _S18) * t2_0 + _S19);
}

bool accumulateHorizContribution_0(inout float xcov_0, inout float xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, Texture2DArray<float4 > curve_tex_0)
{
    float4 tex0_0 = curve_tex_0.Load(int4(cLoc_0, texLayer_0, int(0)));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = curve_tex_0.Load(int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0))).xy - rc_0;
    float _S20 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S20) < -0.5f)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * _S20;
        if((code_0 & 1U) != 0U)
        {
            float _S21 = r_0.x;
            xcov_0 = xcov_0 + clamp(_S21 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S21) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > 1U)
        {
            float _S22 = r_0.y;
            xcov_0 = xcov_0 - clamp(_S22 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S22) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S23 = p12_2.xy;
    float2 _S24 = p12_2.zw;
    float2 a_1 = _S23 - _S24 * 2.0f + p3_2;
    float2 b_2 = _S23 - _S24;
    float _S25 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S25)) < 0.0000152587890625f)
    {
        float _S26 = b_2.x;
        if((abs(_S26)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S26;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S27 = b_2.x;
        float _S28 = p12_2.x;
        float _S29 = _S25 * _S28;
        float sq_1 = snapNearTangentSqrt_0(_S27 * _S27 - _S29, _S27, _S29);
        if(_S27 >= 0.0f)
        {
            float q_2 = _S27 + sq_1;
            float _S30 = q_2 / _S25;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S28 / q_2;
            }
            t2_1 = _S30;
        }
        else
        {
            float q_3 = _S27 - sq_1;
            float _S31 = q_3 / _S25;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S28 / q_3;
            }
            float _S32 = t1_1;
            t1_1 = _S31;
            t2_1 = _S32;
        }
    }
    float _S33 = a_1.y;
    float _S34 = b_2.y * 2.0f;
    float _S35 = p12_2.y;
    return float2((_S33 * t1_1 - _S34) * t1_1 + _S35, (_S33 * t2_1 - _S34) * t2_1 + _S35);
}

bool accumulateVertContribution_0(inout float ycov_0, inout float ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, Texture2DArray<float4 > curve_tex_1)
{
    float4 tex0_1 = curve_tex_1.Load(int4(cLoc_1, texLayer_1, int(0)));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = curve_tex_1.Load(int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0))).xy - rc_1;
    float _S36 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S36) < -0.5f)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * _S36;
        if((code_1 & 1U) != 0U)
        {
            float _S37 = r_1.x;
            ycov_0 = ycov_0 - clamp(_S37 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S37) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > 1U)
        {
            float _S38 = r_1.y;
            ycov_0 = ycov_0 + clamp(_S38 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S38) * 2.0f, 0.0f, 1.0f));
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
    float _S39 = max(coverage_exponent_1, 0.0000152587890625f);
    float _S40;
    if((abs(_S39 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S40 = clamped_0;
    }
    else
    {
        _S40 = pow(clamped_0, _S39);
    }
    return _S40;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_0, float coverage_exponent_2)
{
    bool _S41;
    int i_0;
    int _S42 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S42);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    float xcov_1 = 0.0f;
    float xwgt_1 = 0.0f;
    bool _S43 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int2 _S44 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S45 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S45)
            {
            }
            else
            {
                break;
            }
            uint2 ref_4 = band_tex_0.Load(int4(calcBandLoc_0(_S44, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S43)
            {
                _S41 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S41 = false;
            }
            if(_S41)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S46 = accumulateHorizContribution_0(xcov_1, xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S46)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    float ycov_1 = 0.0f;
    float ywgt_1 = 0.0f;
    bool _S47 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        uint2 vbd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(_S42 + int(1) + band_1)), texLayer_2, int(0))).xy;
        int2 _S48 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S49 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S49)
            {
            }
            else
            {
                break;
            }
            uint2 ref_5 = band_tex_0.Load(int4(calcBandLoc_0(_S48, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S47)
            {
                _S41 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S41 = false;
            }
            if(_S41)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S50 = accumulateVertContribution_0(ycov_1, ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S50)
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
    float _S51;
    if(c_0 <= 0.00313080009073019f)
    {
        _S51 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S51 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S51;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S52 = premul_0.w;
    if(_S52 <= 0.0f)
    {
        return (float4)0.0f;
    }
    return float4(linearToSrgb_0(premul_0.xyz * (1.0f / _S52)) * _S52, _S52);
}

struct TextVaryings_0
{
    float4 color_2;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_1;
    int4 glyph_0;
};

float4 snailTextFragment_0(TextVaryings_0 v_1, Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_1, int layer_base_1, int output_srgb_1, float coverage_exponent_3, int mask_output_1)
{
    int _S53 = v_1.glyph_0.w;
    int layer_byte_0 = (_S53 >> int(8)) & int(255);
    if(layer_byte_0 == int(255))
    {
        discard;
    }
    float2 epp_1 = (fwidth((v_1.texcoord_0)));
    float cov_2 = evalGlyphCoverage_0(v_1.texcoord_0, epp_1, float2(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f)), v_1.glyph_0.xy, int2(_S53 & int(255), v_1.glyph_0.z), v_1.banding_1, layer_base_1 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    float4 premul_1 = premultiplyColor_0(v_1.color_2 * v_1.tint_0, cov_2);
    float4 _S54;
    if(mask_output_1 != int(0))
    {
        _S54 = (float4)premul_1.w;
    }
    else
    {
        if(output_srgb_1 != int(0))
        {
            _S54 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S54 = premul_1;
        }
    }
    return _S54;
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
    TextVaryings_0 v_2;
    v_2.color_2 = input_0.color_3;
    v_2.tint_0 = input_0.tint_1;
    v_2.texcoord_0 = input_0.texcoord_1;
    v_2.banding_1 = input_0.banding_2;
    v_2.glyph_0 = input_0.glyph_1;
    float4 _S55 = snailTextFragment_0(v_2, u_curve_tex_0, u_band_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    return _S55;
}

