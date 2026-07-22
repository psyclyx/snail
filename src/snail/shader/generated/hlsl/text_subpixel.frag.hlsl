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

float2 subpixelCoverageEdgePixels_0(float2 display_dx_0, float2 display_dy_0, int subpixel_order_1)
{
    float2 dx_0 = abs(display_dx_0);
    float2 dy_0 = abs(display_dy_0);
    float2 _S1;
    if(subpixel_order_1 <= int(2))
    {
        _S1 = dx_0 * 0.3333333432674408f + dy_0;
    }
    else
    {
        _S1 = dx_0 + dy_0 * 0.3333333432674408f;
    }
    return _S1;
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S2;
    _S2.first_0 = first_1;
    _S2.last_0 = last_1;
    return _S2;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S3 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S3), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S3), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S4 = glyphLoc_0.x + int(offset_0);
    int2 loc_0 = int2(_S4, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S4 >> int(12));
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
    int _S5 = base_0.x + offset_1;
    int2 loc_1 = int2(_S5, base_0.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S5 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S6;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S6 = 0.0f;
    }
    else
    {
        _S6 = v_0;
    }
    return _S6;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S7;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S7 = 0.0f;
    }
    else
    {
        _S7 = sqrt(disc_0);
    }
    return _S7;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S8 = p12_0.xy;
    float2 _S9 = p12_0.zw;
    float2 a_0 = _S8 - _S9 * 2.0f + p3_0;
    float2 b_1 = _S8 - _S9;
    float _S10 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S10)) < 0.0000152587890625f)
    {
        float _S11 = b_1.y;
        if((abs(_S11)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S11;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S12 = b_1.y;
        float _S13 = p12_0.y;
        float _S14 = _S10 * _S13;
        float sq_0 = snapNearTangentSqrt_0(_S12 * _S12 - _S14, _S12, _S14);
        if(_S12 >= 0.0f)
        {
            float q_0 = _S12 + sq_0;
            float _S15 = q_0 / _S10;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S13 / q_0;
            }
            t2_0 = _S15;
        }
        else
        {
            float q_1 = _S12 - sq_0;
            float _S16 = q_1 / _S10;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S13 / q_1;
            }
            float _S17 = t1_0;
            t1_0 = _S16;
            t2_0 = _S17;
        }
    }
    float _S18 = a_0.x;
    float _S19 = b_1.x * 2.0f;
    float _S20 = p12_0.x;
    return float2((_S18 * t1_0 - _S19) * t1_0 + _S20, (_S18 * t2_0 - _S19) * t2_0 + _S20);
}

bool accumulateHorizContribution_0(inout float xcov_0, inout float xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, Texture2DArray<float4 > curve_tex_0)
{
    float4 tex0_0 = curve_tex_0.Load(int4(cLoc_0, texLayer_0, int(0)));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = curve_tex_0.Load(int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0))).xy - rc_0;
    float _S21 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S21) < -0.5f)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * _S21;
        if((code_0 & 1U) != 0U)
        {
            float _S22 = r_0.x;
            xcov_0 = xcov_0 + clamp(_S22 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S22) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > 1U)
        {
            float _S23 = r_0.y;
            xcov_0 = xcov_0 - clamp(_S23 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S23) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S24 = p12_2.xy;
    float2 _S25 = p12_2.zw;
    float2 a_1 = _S24 - _S25 * 2.0f + p3_2;
    float2 b_2 = _S24 - _S25;
    float _S26 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S26)) < 0.0000152587890625f)
    {
        float _S27 = b_2.x;
        if((abs(_S27)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S27;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S28 = b_2.x;
        float _S29 = p12_2.x;
        float _S30 = _S26 * _S29;
        float sq_1 = snapNearTangentSqrt_0(_S28 * _S28 - _S30, _S28, _S30);
        if(_S28 >= 0.0f)
        {
            float q_2 = _S28 + sq_1;
            float _S31 = q_2 / _S26;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S29 / q_2;
            }
            t2_1 = _S31;
        }
        else
        {
            float q_3 = _S28 - sq_1;
            float _S32 = q_3 / _S26;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S29 / q_3;
            }
            float _S33 = t1_1;
            t1_1 = _S32;
            t2_1 = _S33;
        }
    }
    float _S34 = a_1.y;
    float _S35 = b_2.y * 2.0f;
    float _S36 = p12_2.y;
    return float2((_S34 * t1_1 - _S35) * t1_1 + _S36, (_S34 * t2_1 - _S35) * t2_1 + _S36);
}

bool accumulateVertContribution_0(inout float ycov_0, inout float ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, Texture2DArray<float4 > curve_tex_1)
{
    float4 tex0_1 = curve_tex_1.Load(int4(cLoc_1, texLayer_1, int(0)));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = curve_tex_1.Load(int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0))).xy - rc_1;
    float _S37 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S37) < -0.5f)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * _S37;
        if((code_1 & 1U) != 0U)
        {
            float _S38 = r_1.x;
            ycov_0 = ycov_0 - clamp(_S38 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S38) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > 1U)
        {
            float _S39 = r_1.y;
            ycov_0 = ycov_0 + clamp(_S39 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S39) * 2.0f, 0.0f, 1.0f));
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

float evalGlyphCoverageRaw_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 glyph_loc_0, int2 band_max_0, float4 banding_0, int layer_0, Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_0)
{
    bool _S40;
    int i_0;
    int _S41 = band_max_0.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S41);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, band_max_0.x);
    float xcov_1 = 0.0f;
    float xwgt_1 = 0.0f;
    bool _S42 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        uint2 hbd_0 = band_tex_0.Load(int4(calcBandLoc_0(glyph_loc_0, uint(band_1)), layer_0, int(0))).xy;
        int2 _S43 = calcBandLoc_0(glyph_loc_0, hbd_0.y);
        int _S44 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S44)
            {
            }
            else
            {
                break;
            }
            uint2 ref_4 = band_tex_0.Load(int4(calcBandLoc_0(_S43, uint(i_0)), layer_0, int(0))).xy;
            if(_S42)
            {
                _S40 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S40 = false;
            }
            if(_S40)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S45 = accumulateHorizContribution_0(xcov_1, xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), layer_0, curve_tex_2);
            if(!_S45)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    float ycov_1 = 0.0f;
    float ywgt_1 = 0.0f;
    bool _S46 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        uint2 vbd_0 = band_tex_0.Load(int4(calcBandLoc_0(glyph_loc_0, uint(_S41 + int(1) + band_1)), layer_0, int(0))).xy;
        int2 _S47 = calcBandLoc_0(glyph_loc_0, vbd_0.y);
        int _S48 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S48)
            {
            }
            else
            {
                break;
            }
            uint2 ref_5 = band_tex_0.Load(int4(calcBandLoc_0(_S47, uint(i_0)), layer_0, int(0))).xy;
            if(_S46)
            {
                _S40 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S40 = false;
            }
            if(_S40)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S49 = accumulateVertContribution_0(ycov_1, ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), layer_0, curve_tex_2);
            if(!_S49)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return clamp(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), 0.0f, 1.0f);
}

float evalGlyphSample_0(float2 rc_3, float2 display_epp_0, int2 glyph_loc_1, int2 band_max_1, float4 banding_1, int layer_1, Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_1)
{
    return evalGlyphCoverageRaw_0(rc_3, display_epp_0, float2(1.0f / max(display_epp_0.x, 0.0000152587890625f), 1.0f / max(display_epp_0.y, 0.0000152587890625f)), glyph_loc_1, band_max_1, banding_1, layer_1, curve_tex_3, band_tex_1);
}

float4 filterSubpixelCoverage_0(float s_m3_0, float s_m2_0, float s_m1_0, float s_0_0, float s_p1_0, float s_p2_0, float s_p3_0, bool reverse_order_0)
{
    float _S50 = 0.30078125f * s_0_0;
    float left_0 = 0.03125f * s_m3_0 + 0.30078125f * s_m2_0 + 0.3359375f * s_m1_0 + _S50 + 0.03125f * s_p1_0;
    float center_1 = 0.03125f * s_m2_0 + 0.30078125f * s_m1_0 + 0.3359375f * s_0_0 + 0.30078125f * s_p1_0 + 0.03125f * s_p2_0;
    float right_0 = 0.03125f * s_m1_0 + _S50 + 0.3359375f * s_p1_0 + 0.30078125f * s_p2_0 + 0.03125f * s_p3_0;
    float3 cov_0;
    if(reverse_order_0)
    {
        cov_0 = float3(right_0, center_1, left_0);
    }
    else
    {
        cov_0 = float3(left_0, center_1, right_0);
    }
    float3 cov_1 = clamp(cov_0, (float3)0.0f, (float3)1.0f);
    return float4(cov_1, clamp((cov_1.x + cov_1.y + cov_1.z) * 0.3333333432674408f, 0.0f, 1.0f));
}

float applyCoverageTransfer_0(float cov_2, float coverage_exponent_1)
{
    float clamped_0 = clamp(cov_2, 0.0f, 1.0f);
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

float3 applyCoverageTransfer3_0(float3 cov_3, float coverage_exponent_2)
{
    return float3(applyCoverageTransfer_0(cov_3.x, coverage_exponent_2), applyCoverageTransfer_0(cov_3.y, coverage_exponent_2), applyCoverageTransfer_0(cov_3.z, coverage_exponent_2));
}

float4 evalGlyphCoverageSubpixel_0(float2 rc_4, int2 glyph_loc_2, int2 band_max_2, float4 banding_2, int layer_2, int subpixel_order_2, float coverage_exponent_3, Texture2DArray<float4 > curve_tex_4, Texture2DArray<uint2 > band_tex_2)
{
    float2 display_dx_1 = ddx(rc_4);
    float2 display_dy_1 = ddy(rc_4);
    float2 _S53;
    if(subpixel_order_2 <= int(2))
    {
        _S53 = display_dx_1;
    }
    else
    {
        _S53 = display_dy_1;
    }
    float2 sample_step_0 = _S53 * 0.3333333432674408f;
    float2 display_epp_1 = subpixelCoverageEdgePixels_0(display_dx_1, display_dy_1, subpixel_order_2);
    float2 _S54 = sample_step_0 * 3.0f;
    float2 _S55 = sample_step_0 * 2.0f;
    float s_m3_1 = evalGlyphSample_0(rc_4 - _S54, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_m2_1 = evalGlyphSample_0(rc_4 - _S55, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_m1_1 = evalGlyphSample_0(rc_4 - sample_step_0, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_0_1 = evalGlyphSample_0(rc_4, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p1_1 = evalGlyphSample_0(rc_4 + sample_step_0, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p2_1 = evalGlyphSample_0(rc_4 + _S55, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p3_1 = evalGlyphSample_0(rc_4 + _S54, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    bool _S56;
    if(subpixel_order_2 == int(2))
    {
        _S56 = true;
    }
    else
    {
        _S56 = subpixel_order_2 == int(4);
    }
    float4 coverage_0 = filterSubpixelCoverage_0(s_m3_1, s_m2_1, s_m1_1, s_0_1, s_p1_1, s_p2_1, s_p3_1, _S56);
    return float4(applyCoverageTransfer3_0(coverage_0.xyz, coverage_exponent_3), applyCoverageTransfer_0(coverage_0.w, coverage_exponent_3));
}

float srgbEncode_0(float c_0)
{
    float _S57;
    if(c_0 <= 0.00313080009073019f)
    {
        _S57 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S57 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S57;
}

float4 premultiplyColorSubpixel_0(float4 color_0, float3 cov_4, float alpha_cov_0)
{
    float _S58 = color_0.w;
    return float4(color_0.xyz * ((float3)_S58 * cov_4), _S58 * alpha_cov_0);
}

struct SubpixelResult_0
{
    float4 color_1;
    float4 blend_0;
    bool discard_fragment_0;
};

struct SubpixelVaryings_0
{
    float4 color_2;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_3;
    int4 glyph_0;
};

SubpixelResult_0 snailSubpixelFragment_0(SubpixelVaryings_0 v_1, Texture2DArray<float4 > curve_tex_5, Texture2DArray<uint2 > band_tex_3, int layer_base_1, int subpixel_order_3, int output_srgb_1, float coverage_exponent_4)
{
    SubpixelResult_0 r_2;
    float4 _S59 = (float4)0.0f;
    r_2.color_1 = _S59;
    r_2.blend_0 = _S59;
    r_2.discard_fragment_0 = false;
    int _S60 = v_1.glyph_0.w;
    int layer_byte_0 = (_S60 >> int(8)) & int(255);
    if(layer_byte_0 == int(255))
    {
        r_2.discard_fragment_0 = true;
        return r_2;
    }
    float4 cov_alpha_0 = evalGlyphCoverageSubpixel_0(v_1.texcoord_0, v_1.glyph_0.xy, int2(_S60 & int(255), v_1.glyph_0.z), v_1.banding_3, layer_base_1 + layer_byte_0, subpixel_order_3, coverage_exponent_4, curve_tex_5, band_tex_3);
    float3 cov_5 = cov_alpha_0.xyz;
    if((max(max(cov_5.x, cov_5.y), cov_5.z)) < 0.00392156885936856f)
    {
        r_2.discard_fragment_0 = true;
        return r_2;
    }
    float4 color_3 = v_1.color_2 * v_1.tint_0;
    float4 effective_0;
    if(output_srgb_1 != int(0))
    {
        effective_0 = float4(srgbEncode_0(max(color_3.x, 0.0f)), srgbEncode_0(max(color_3.y, 0.0f)), srgbEncode_0(max(color_3.z, 0.0f)), color_3.w);
    }
    else
    {
        effective_0 = color_3;
    }
    r_2.color_1 = premultiplyColorSubpixel_0(effective_0, cov_5, cov_alpha_0.w);
    r_2.blend_0 = float4((float3)color_3.w * cov_5, 0.0f);
    return r_2;
}

struct FsOutput_0
{
    float4 color_4 : SV_Target0;
    float4 blend_1 : SV_Target1;
};

struct VsOutput_0
{
    float4 position_0 : SV_Position;
    float4 color_5 : TEXCOORD0;
    float2 texcoord_1 : TEXCOORD1;
    nointerpolation float4 banding_4 : TEXCOORD2;
    nointerpolation int4 glyph_1 : TEXCOORD3;
    float4 tint_1 : TEXCOORD4;
};

FsOutput_0 fragmentMain(VsOutput_0 input_0)
{
    SubpixelVaryings_0 v_2;
    v_2.color_2 = input_0.color_5;
    v_2.tint_0 = input_0.tint_1;
    v_2.texcoord_0 = input_0.texcoord_1;
    v_2.banding_3 = input_0.banding_4;
    v_2.glyph_0 = input_0.glyph_1;
    SubpixelResult_0 r_3 = snailSubpixelFragment_0(v_2, u_curve_tex_0, u_band_tex_0, pc_0.layer_base_0, pc_0.subpixel_order_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0);
    if(r_3.discard_fragment_0)
    {
        discard;
    }
    FsOutput_0 o_0;
    o_0.color_4 = r_3.color_1;
    o_0.blend_1 = r_3.blend_0;
    return o_0;
}

