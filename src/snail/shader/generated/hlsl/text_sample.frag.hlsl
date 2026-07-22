#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
// warning X3557: loop doesn't seem to do anything, forcing loop to unroll
#pragma warning(disable : 3557)
#endif

struct SnailTextSampleParams_0
{
    int glyph_count_0;
    int words_per_glyph_0;
    int layer_base_0;
    float coverage_exponent_0;
};

cbuffer pc_0 : register(b0)
{
    SnailTextSampleParams_0 pc_0;
}
Texture2DArray<float4 > u_curve_tex_0 : register(t0);

Texture2DArray<uint2 > u_band_tex_0 : register(t1);

Buffer<uint > u_snail_text_records_0 : register(t2);

uint Records_word_0(int linear_index_0)
{
    return u_snail_text_records_0.Load(int(uint(linear_index_0)));
}

uint snailTextSampleWord_0(int words_per_glyph_1, int glyph_index_0, int word_offset_0)
{
    return Records_word_0(glyph_index_0 * words_per_glyph_1 + word_offset_0);
}

float snailDecodeFloat16_0(uint bits_0)
{
    uint exponent_0 = (bits_0 >> 10U) & 31U;
    uint fraction_0 = bits_0 & 1023U;
    float sign_0;
    if((bits_0 >> 15U) == 0U)
    {
        sign_0 = 1.0f;
    }
    else
    {
        sign_0 = -1.0f;
    }
    if(exponent_0 == 0U)
    {
        if(fraction_0 == 0U)
        {
            return sign_0 * 0.0f;
        }
        return sign_0 * (exp2((-14.0f))) * (float(fraction_0) / 1024.0f);
    }
    if(exponent_0 == 31U)
    {
        return sign_0 * 65504.0f;
    }
    return sign_0 * (exp2((float(exponent_0) - 15.0f))) * (1.0f + float(fraction_0) / 1024.0f);
}

float2 snailUnpackHalf2_0(uint word_0)
{
    return float2(snailDecodeFloat16_0(word_0 & 65535U), snailDecodeFloat16_0(word_0 >> 16U));
}

float4 snailUnpackHalf4_0(uint lo_0, uint hi_0)
{
    return float4(snailUnpackHalf2_0(lo_0), snailUnpackHalf2_0(hi_0));
}

float4 snailUnpackUnorm4x8_0(uint word_1)
{
    return float4(float(word_1 & 255U), float((word_1 >> 8U) & 255U), float((word_1 >> 16U) & 255U), float((word_1 >> 24U) & 255U)) / 255.0f;
}

struct SnailTextSampleRecord_0
{
    float4 rect_0;
    float4 xform_0;
    float2 origin_0;
    uint2 glyph_0;
    float4 banding_0;
    float4 color_0;
    float4 tint_0;
};

SnailTextSampleRecord_0 snailTextSampleRecord_0(int words_per_glyph_2, int glyph_index_1)
{
    SnailTextSampleRecord_0 record_0;
    record_0.rect_0 = snailUnpackHalf4_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(0)), snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(1)));
    record_0.xform_0 = float4(asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(2))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(3))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(4))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(5))));
    record_0.origin_0 = float2(asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(6))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(7))));
    record_0.glyph_0 = uint2(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(8)), snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(9)));
    record_0.banding_0 = float4(asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(10))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(11))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(12))), asfloat(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(13))));
    record_0.color_0 = snailUnpackUnorm4x8_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(14)));
    record_0.tint_0 = snailUnpackUnorm4x8_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(15)));
    return record_0;
}

float2 snailTextSampleLocalCoord_0(float2 scene_pos_0, float4 xform_1, float2 origin_1)
{
    float _S1 = xform_1.x;
    float _S2 = xform_1.w;
    float _S3 = xform_1.y;
    float _S4 = xform_1.z;
    float det_0 = _S1 * _S2 - _S3 * _S4;
    float2 delta_0 = scene_pos_0 - origin_1;
    float _S5 = delta_0.x;
    float _S6 = delta_0.y;
    return float2((_S2 * _S5 - _S3 * _S6) / det_0, (- _S4 * _S5 + _S1 * _S6) / det_0);
}

float2 snailTextSampleLocalVector_0(float2 scene_vector_0, float4 xform_2)
{
    float _S7 = xform_2.x;
    float _S8 = xform_2.w;
    float _S9 = xform_2.y;
    float _S10 = xform_2.z;
    float det_1 = _S7 * _S8 - _S9 * _S10;
    float _S11 = scene_vector_0.x;
    float _S12 = scene_vector_0.y;
    return float2((_S8 * _S11 - _S9 * _S12) / det_1, (- _S10 * _S11 + _S7 * _S12) / det_1);
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S13;
    _S13.first_0 = first_1;
    _S13.last_0 = last_1;
    return _S13;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S14 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S14), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S14), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S15 = glyphLoc_0.x + int(offset_0);
    int2 loc_0 = int2(_S15, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S15 >> int(12));
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
    int _S16 = base_0.x + offset_1;
    int2 loc_1 = int2(_S16, base_0.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S16 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S17;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S17 = 0.0f;
    }
    else
    {
        _S17 = v_0;
    }
    return _S17;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S18;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S18 = 0.0f;
    }
    else
    {
        _S18 = sqrt(disc_0);
    }
    return _S18;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S19 = p12_0.xy;
    float2 _S20 = p12_0.zw;
    float2 a_0 = _S19 - _S20 * 2.0f + p3_0;
    float2 b_1 = _S19 - _S20;
    float _S21 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S21)) < 0.0000152587890625f)
    {
        float _S22 = b_1.y;
        if((abs(_S22)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S22;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S23 = b_1.y;
        float _S24 = p12_0.y;
        float _S25 = _S21 * _S24;
        float sq_0 = snapNearTangentSqrt_0(_S23 * _S23 - _S25, _S23, _S25);
        if(_S23 >= 0.0f)
        {
            float q_0 = _S23 + sq_0;
            float _S26 = q_0 / _S21;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S24 / q_0;
            }
            t2_0 = _S26;
        }
        else
        {
            float q_1 = _S23 - sq_0;
            float _S27 = q_1 / _S21;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S24 / q_1;
            }
            float _S28 = t1_0;
            t1_0 = _S27;
            t2_0 = _S28;
        }
    }
    float _S29 = a_0.x;
    float _S30 = b_1.x * 2.0f;
    float _S31 = p12_0.x;
    return float2((_S29 * t1_0 - _S30) * t1_0 + _S31, (_S29 * t2_0 - _S30) * t2_0 + _S31);
}

bool accumulateHorizContribution_0(inout float xcov_0, inout float xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, Texture2DArray<float4 > curve_tex_0)
{
    float4 tex0_0 = curve_tex_0.Load(int4(cLoc_0, texLayer_0, int(0)));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = curve_tex_0.Load(int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0))).xy - rc_0;
    float _S32 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S32) < -0.5f)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * _S32;
        if((code_0 & 1U) != 0U)
        {
            float _S33 = r_0.x;
            xcov_0 = xcov_0 + clamp(_S33 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S33) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > 1U)
        {
            float _S34 = r_0.y;
            xcov_0 = xcov_0 - clamp(_S34 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S34) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S35 = p12_2.xy;
    float2 _S36 = p12_2.zw;
    float2 a_1 = _S35 - _S36 * 2.0f + p3_2;
    float2 b_2 = _S35 - _S36;
    float _S37 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S37)) < 0.0000152587890625f)
    {
        float _S38 = b_2.x;
        if((abs(_S38)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S38;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S39 = b_2.x;
        float _S40 = p12_2.x;
        float _S41 = _S37 * _S40;
        float sq_1 = snapNearTangentSqrt_0(_S39 * _S39 - _S41, _S39, _S41);
        if(_S39 >= 0.0f)
        {
            float q_2 = _S39 + sq_1;
            float _S42 = q_2 / _S37;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S40 / q_2;
            }
            t2_1 = _S42;
        }
        else
        {
            float q_3 = _S39 - sq_1;
            float _S43 = q_3 / _S37;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S40 / q_3;
            }
            float _S44 = t1_1;
            t1_1 = _S43;
            t2_1 = _S44;
        }
    }
    float _S45 = a_1.y;
    float _S46 = b_2.y * 2.0f;
    float _S47 = p12_2.y;
    return float2((_S45 * t1_1 - _S46) * t1_1 + _S47, (_S45 * t2_1 - _S46) * t2_1 + _S47);
}

bool accumulateVertContribution_0(inout float ycov_0, inout float ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, Texture2DArray<float4 > curve_tex_1)
{
    float4 tex0_1 = curve_tex_1.Load(int4(cLoc_1, texLayer_1, int(0)));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = curve_tex_1.Load(int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0))).xy - rc_1;
    float _S48 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S48) < -0.5f)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * _S48;
        if((code_1 & 1U) != 0U)
        {
            float _S49 = r_1.x;
            ycov_0 = ycov_0 - clamp(_S49 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S49) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > 1U)
        {
            float _S50 = r_1.y;
            ycov_0 = ycov_0 + clamp(_S50 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S50) * 2.0f, 0.0f, 1.0f));
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
    float _S51 = max(coverage_exponent_1, 0.0000152587890625f);
    float _S52;
    if((abs(_S51 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S52 = clamped_0;
    }
    else
    {
        _S52 = pow(clamped_0, _S51);
    }
    return _S52;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_1, int texLayer_2, Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_0, float coverage_exponent_2)
{
    bool _S53;
    int i_0;
    int _S54 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_1.y, banding_1.w, _S54);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_1.x, banding_1.z, bandMax_1.x);
    float xcov_1 = 0.0f;
    float xwgt_1 = 0.0f;
    bool _S55 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int2 _S56 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S57 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S57)
            {
            }
            else
            {
                break;
            }
            uint2 ref_4 = band_tex_0.Load(int4(calcBandLoc_0(_S56, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S55)
            {
                _S53 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S53 = false;
            }
            if(_S53)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S58 = accumulateHorizContribution_0(xcov_1, xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S58)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    float ycov_1 = 0.0f;
    float ywgt_1 = 0.0f;
    bool _S59 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        uint2 vbd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(_S54 + int(1) + band_1)), texLayer_2, int(0))).xy;
        int2 _S60 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S61 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S61)
            {
            }
            else
            {
                break;
            }
            uint2 ref_5 = band_tex_0.Load(int4(calcBandLoc_0(_S60, uint(i_0)), texLayer_2, int(0))).xy;
            if(_S59)
            {
                _S53 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S53 = false;
            }
            if(_S53)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S62 = accumulateVertContribution_0(ycov_1, ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S62)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), coverage_exponent_2);
}

float srgbDecode_0(float c_0)
{
    float _S63;
    if(c_0 <= 0.04044999927282333f)
    {
        _S63 = c_0 / 12.92000007629394531f;
    }
    else
    {
        _S63 = pow((c_0 + 0.05499999970197678f) / 1.0549999475479126f, 2.40000009536743164f);
    }
    return _S63;
}

float3 srgbToLinear_0(float3 color_1)
{
    return float3(srgbDecode_0(color_1.x), srgbDecode_0(color_1.y), srgbDecode_0(color_1.z));
}

float4 snailTextSamplePremulLinearWithFootprint_0(int words_per_glyph_3, int glyph_count_1, int layer_base_1, float coverage_exponent_3, Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_1, float2 scene_pos_1, float2 scene_dx_0, float2 scene_dy_0)
{
    float4 paint_0 = (float4)0.0f;
    int i_1 = int(0);
    for(;;)
    {
        if(i_1 < glyph_count_1)
        {
        }
        else
        {
            break;
        }
        SnailTextSampleRecord_0 _S64 = snailTextSampleRecord_0(words_per_glyph_3, i_1);
        if((abs(_S64.xform_0.x * _S64.xform_0.w - _S64.xform_0.y * _S64.xform_0.z)) < 1.00000001335143196e-10f)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float2 rc_3 = snailTextSampleLocalCoord_0(scene_pos_1, _S64.xform_0, _S64.origin_0);
        float2 epp_1 = abs(snailTextSampleLocalVector_0(scene_dx_0, _S64.xform_0)) + abs(snailTextSampleLocalVector_0(scene_dy_0, _S64.xform_0));
        float2 em_aa_0 = max(epp_1 * 2.0f, (float2)0.00100000004749745f);
        float _S65 = rc_3.x;
        float _S66 = em_aa_0.x;
        bool _S67;
        if(_S65 < (_S64.rect_0.x - _S66))
        {
            _S67 = true;
        }
        else
        {
            _S67 = _S65 > (_S64.rect_0.z + _S66);
        }
        bool _S68;
        if(_S67)
        {
            _S68 = true;
        }
        else
        {
            _S68 = (rc_3.y) < (_S64.rect_0.y - em_aa_0.y);
        }
        bool _S69;
        if(_S68)
        {
            _S69 = true;
        }
        else
        {
            _S69 = (rc_3.y) > (_S64.rect_0.w + em_aa_0.y);
        }
        if(_S69)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        uint gz_0 = _S64.glyph_0.x;
        uint gw_0 = _S64.glyph_0.y;
        int layer_byte_0 = int((gw_0 >> 24U) & 255U);
        if(layer_byte_0 == int(255))
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float alpha_0 = clamp(evalGlyphCoverage_0(rc_3, epp_1, float2(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f)), int2(int(gz_0 & 65535U), int(gz_0 >> 16U)), int2(int((gw_0 >> 16U) & 255U), int(gw_0 & 65535U)), _S64.banding_0, layer_base_1 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_3) * _S64.color_0.w * _S64.tint_0.w, 0.0f, 1.0f);
        if(alpha_0 <= 0.00392156885936856f)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float _S70 = 1.0f - alpha_0;
        paint_0.xyz = srgbToLinear_0(_S64.color_0.xyz) * srgbToLinear_0(_S64.tint_0.xyz) * alpha_0 + paint_0.xyz * _S70;
        paint_0[int(3)] = alpha_0 + paint_0.w * _S70;
        i_1 = i_1 + int(1);
    }
    return paint_0;
}

float4 snailTextSamplePremulLinear_0(int words_per_glyph_4, int glyph_count_2, int layer_base_2, float coverage_exponent_4, Texture2DArray<float4 > curve_tex_4, Texture2DArray<uint2 > band_tex_2, float2 scene_pos_2)
{
    return snailTextSamplePremulLinearWithFootprint_0(words_per_glyph_4, glyph_count_2, layer_base_2, coverage_exponent_4, curve_tex_4, band_tex_2, scene_pos_2, ddx(scene_pos_2), ddy(scene_pos_2));
}

struct FsInput_0
{
    float4 position_0 : SV_Position;
    float2 scene_pos_3 : TEXCOORD0;
};

float4 fragmentMain(FsInput_0 input_0) : SV_TARGET
{
    return snailTextSamplePremulLinear_0(pc_0.words_per_glyph_0, pc_0.glyph_count_0, pc_0.layer_base_0, pc_0.coverage_exponent_0, u_curve_tex_0, u_band_tex_0, input_0.scene_pos_3);
}

