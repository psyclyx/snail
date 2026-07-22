#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
float2 subpixelCoverageEdgePixels_0(float2 display_dx_0, float2 display_dy_0, int subpixel_order_0)
{
    float2 dx_0 = abs(display_dx_0);
    float2 dy_0 = abs(display_dy_0);
    float2 _S1;
    if(subpixel_order_0 <= int(2))
    {
        _S1 = dx_0 * float2(0.3333333432674408)  + dy_0;
    }
    else
    {
        _S1 = dx_0 + dy_0 * float2(0.3333333432674408) ;
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
    thread CoverageBandSpan_0 _S2;
    (&_S2)->first_0 = first_1;
    (&_S2)->last_0 = last_1;
    return _S2;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S3 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S3), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S3), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S4 = glyphLoc_0.x + int(offset_0);
    thread int2 loc_0 = int2(_S4, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S4 >> 12U);
    loc_0.x = (loc_0.x) & int(4095);
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
    thread int2 loc_1 = int2(_S5, base_0.y);
    loc_1.y = loc_1.y + (_S5 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S6;
    if((abs(v_0)) <= 0.0000152587890625)
    {
        _S6 = 0.0;
    }
    else
    {
        _S6 = v_0;
    }
    return _S6;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S7;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S7 = 0.0;
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
    float2 a_0 = _S8 - _S9 * float2(2.0)  + p3_0;
    float2 b_1 = _S8 - _S9;
    float _S10 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S10)) < 0.0000152587890625)
    {
        float _S11 = b_1.y;
        if((abs(_S11)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p12_0.y * 0.5 / _S11;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S12 = b_1.y;
        float _S13 = p12_0.y;
        float _S14 = _S10 * _S13;
        float sq_0 = snapNearTangentSqrt_0(_S12 * _S12 - _S14, _S12, _S14);
        if(_S12 >= 0.0)
        {
            float q_0 = _S12 + sq_0;
            float _S15 = q_0 / _S10;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
    float _S19 = b_1.x * 2.0;
    float _S20 = p12_0.x;
    return float2((_S18 * t1_0 - _S19) * t1_0 + _S20, (_S18 * t2_0 - _S19) * t2_0 + _S20);
}

bool accumulateHorizContribution_0(float thread* xcov_0, float thread* xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, texture2d_array<float, access::sample> curve_tex_0)
{
    int4 _S21 = int4(cLoc_0, texLayer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S21)).xy), uint(((_S21)).z), uint(((_S21)).w)));
    int4 _S22 = int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = ((curve_tex_0).read(vec<uint,2>(((_S22)).xy), uint(((_S22)).z), uint(((_S22)).w))).xy - rc_0;
    float _S23 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S23) < -0.5)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * float2(_S23) ;
        if((code_0 & 1U) != 0U)
        {
            float _S24 = r_0.x;
            *xcov_0 = *xcov_0 + clamp(_S24 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S24) * 2.0, 0.0, 1.0));
        }
        if(code_0 > 1U)
        {
            float _S25 = r_0.y;
            *xcov_0 = *xcov_0 - clamp(_S25 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S25) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S26 = p12_2.xy;
    float2 _S27 = p12_2.zw;
    float2 a_1 = _S26 - _S27 * float2(2.0)  + p3_2;
    float2 b_2 = _S26 - _S27;
    float _S28 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S28)) < 0.0000152587890625)
    {
        float _S29 = b_2.x;
        if((abs(_S29)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p12_2.x * 0.5 / _S29;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S30 = b_2.x;
        float _S31 = p12_2.x;
        float _S32 = _S28 * _S31;
        float sq_1 = snapNearTangentSqrt_0(_S30 * _S30 - _S32, _S30, _S32);
        if(_S30 >= 0.0)
        {
            float q_2 = _S30 + sq_1;
            float _S33 = q_2 / _S28;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S31 / q_2;
            }
            t2_1 = _S33;
        }
        else
        {
            float q_3 = _S30 - sq_1;
            float _S34 = q_3 / _S28;
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S31 / q_3;
            }
            float _S35 = t1_1;
            t1_1 = _S34;
            t2_1 = _S35;
        }
    }
    float _S36 = a_1.y;
    float _S37 = b_2.y * 2.0;
    float _S38 = p12_2.y;
    return float2((_S36 * t1_1 - _S37) * t1_1 + _S38, (_S36 * t2_1 - _S37) * t2_1 + _S38);
}

bool accumulateVertContribution_0(float thread* ycov_0, float thread* ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, texture2d_array<float, access::sample> curve_tex_1)
{
    int4 _S39 = int4(cLoc_1, texLayer_1, int(0));
    float4 tex0_1 = ((curve_tex_1).read(vec<uint,2>(((_S39)).xy), uint(((_S39)).z), uint(((_S39)).w)));
    int4 _S40 = int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = ((curve_tex_1).read(vec<uint,2>(((_S40)).xy), uint(((_S40)).z), uint(((_S40)).w))).xy - rc_1;
    float _S41 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S41) < -0.5)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * float2(_S41) ;
        if((code_1 & 1U) != 0U)
        {
            float _S42 = r_1.x;
            *ycov_0 = *ycov_0 - clamp(_S42 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S42) * 2.0, 0.0, 1.0));
        }
        if(code_1 > 1U)
        {
            float _S43 = r_1.y;
            *ycov_0 = *ycov_0 + clamp(_S43 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S43) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float applyFillRule_0(float winding_0, int fill_rule_mode_0)
{
    if(fill_rule_mode_0 == int(1))
    {
        return 1.0 - abs(fract(winding_0 * 0.5) * 2.0 - 1.0);
    }
    return abs(winding_0);
}

float evalGlyphCoverageRaw_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 glyph_loc_0, int2 band_max_0, float4 banding_0, int layer_0, texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_0)
{
    bool _S44;
    int i_0;
    int _S45 = band_max_0.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S45);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, band_max_0.x);
    thread float xcov_1 = 0.0;
    thread float xwgt_1 = 0.0;
    bool _S46 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int4 _S47 = int4(calcBandLoc_0(glyph_loc_0, uint(band_1)), layer_0, int(0));
        uint2 hbd_0 = ((band_tex_0).read(vec<uint,2>(((_S47)).xy), uint(((_S47)).z), uint(((_S47)).w)).xy).xy;
        int2 _S48 = calcBandLoc_0(glyph_loc_0, hbd_0.y);
        int _S49 = int(hbd_0.x);
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
            int4 _S50 = int4(calcBandLoc_0(_S48, uint(i_0)), layer_0, int(0));
            uint2 ref_4 = ((band_tex_0).read(vec<uint,2>(((_S50)).xy), uint(((_S50)).z), uint(((_S50)).w)).xy).xy;
            if(_S46)
            {
                _S44 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S44 = false;
            }
            if(_S44)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S51 = accumulateHorizContribution_0(&xcov_1, &xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), layer_0, curve_tex_2);
            if(!_S51)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    thread float ycov_1 = 0.0;
    thread float ywgt_1 = 0.0;
    bool _S52 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        int4 _S53 = int4(calcBandLoc_0(glyph_loc_0, uint(_S45 + int(1) + band_1)), layer_0, int(0));
        uint2 vbd_0 = ((band_tex_0).read(vec<uint,2>(((_S53)).xy), uint(((_S53)).z), uint(((_S53)).w)).xy).xy;
        int2 _S54 = calcBandLoc_0(glyph_loc_0, vbd_0.y);
        int _S55 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S55)
            {
            }
            else
            {
                break;
            }
            int4 _S56 = int4(calcBandLoc_0(_S54, uint(i_0)), layer_0, int(0));
            uint2 ref_5 = ((band_tex_0).read(vec<uint,2>(((_S56)).xy), uint(((_S56)).z), uint(((_S56)).w)).xy).xy;
            if(_S52)
            {
                _S44 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S44 = false;
            }
            if(_S44)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S57 = accumulateVertContribution_0(&ycov_1, &ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), layer_0, curve_tex_2);
            if(!_S57)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return clamp(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), 0.0, 1.0);
}

float evalGlyphSample_0(float2 rc_3, float2 display_epp_0, int2 glyph_loc_1, int2 band_max_1, float4 banding_1, int layer_1, texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_1)
{
    return evalGlyphCoverageRaw_0(rc_3, display_epp_0, float2(1.0 / max(display_epp_0.x, 0.0000152587890625), 1.0 / max(display_epp_0.y, 0.0000152587890625)), glyph_loc_1, band_max_1, banding_1, layer_1, curve_tex_3, band_tex_1);
}

float4 filterSubpixelCoverage_0(float s_m3_0, float s_m2_0, float s_m1_0, float s_0_0, float s_p1_0, float s_p2_0, float s_p3_0, bool reverse_order_0)
{
    float _S58 = 0.30078125 * s_0_0;
    float left_0 = 0.03125 * s_m3_0 + 0.30078125 * s_m2_0 + 0.3359375 * s_m1_0 + _S58 + 0.03125 * s_p1_0;
    float center_1 = 0.03125 * s_m2_0 + 0.30078125 * s_m1_0 + 0.3359375 * s_0_0 + 0.30078125 * s_p1_0 + 0.03125 * s_p2_0;
    float right_0 = 0.03125 * s_m1_0 + _S58 + 0.3359375 * s_p1_0 + 0.30078125 * s_p2_0 + 0.03125 * s_p3_0;
    float3 cov_0;
    if(reverse_order_0)
    {
        cov_0 = float3(right_0, center_1, left_0);
    }
    else
    {
        cov_0 = float3(left_0, center_1, right_0);
    }
    float3 cov_1 = clamp(cov_0, float3(0.0) , float3(1.0) );
    return float4(cov_1, clamp((cov_1.x + cov_1.y + cov_1.z) * 0.3333333432674408, 0.0, 1.0));
}

float applyCoverageTransfer_0(float cov_2, float coverage_exponent_0)
{
    float clamped_0 = clamp(cov_2, 0.0, 1.0);
    float _S59 = max(coverage_exponent_0, 0.0000152587890625);
    float _S60;
    if((abs(_S59 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S60 = clamped_0;
    }
    else
    {
        _S60 = pow(clamped_0, _S59);
    }
    return _S60;
}

float3 applyCoverageTransfer3_0(float3 cov_3, float coverage_exponent_1)
{
    return float3(applyCoverageTransfer_0(cov_3.x, coverage_exponent_1), applyCoverageTransfer_0(cov_3.y, coverage_exponent_1), applyCoverageTransfer_0(cov_3.z, coverage_exponent_1));
}

float4 evalGlyphCoverageSubpixel_0(float2 rc_4, int2 glyph_loc_2, int2 band_max_2, float4 banding_2, int layer_2, int subpixel_order_1, float coverage_exponent_2, texture2d_array<float, access::sample> curve_tex_4, texture2d_array<uint, access::sample> band_tex_2)
{
    float2 display_dx_1 = dfdx(rc_4);
    float2 display_dy_1 = dfdy(rc_4);
    float2 _S61;
    if(subpixel_order_1 <= int(2))
    {
        _S61 = display_dx_1;
    }
    else
    {
        _S61 = display_dy_1;
    }
    float2 sample_step_0 = _S61 * float2(0.3333333432674408) ;
    float2 display_epp_1 = subpixelCoverageEdgePixels_0(display_dx_1, display_dy_1, subpixel_order_1);
    float2 _S62 = sample_step_0 * float2(3.0) ;
    float2 _S63 = sample_step_0 * float2(2.0) ;
    float s_m3_1 = evalGlyphSample_0(rc_4 - _S62, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_m2_1 = evalGlyphSample_0(rc_4 - _S63, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_m1_1 = evalGlyphSample_0(rc_4 - sample_step_0, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_0_1 = evalGlyphSample_0(rc_4, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p1_1 = evalGlyphSample_0(rc_4 + sample_step_0, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p2_1 = evalGlyphSample_0(rc_4 + _S63, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    float s_p3_1 = evalGlyphSample_0(rc_4 + _S62, display_epp_1, glyph_loc_2, band_max_2, banding_2, layer_2, curve_tex_4, band_tex_2);
    bool _S64;
    if(subpixel_order_1 == int(2))
    {
        _S64 = true;
    }
    else
    {
        _S64 = subpixel_order_1 == int(4);
    }
    float4 coverage_0 = filterSubpixelCoverage_0(s_m3_1, s_m2_1, s_m1_1, s_0_1, s_p1_1, s_p2_1, s_p3_1, _S64);
    return float4(applyCoverageTransfer3_0(coverage_0.xyz, coverage_exponent_2), applyCoverageTransfer_0(coverage_0.w, coverage_exponent_2));
}

float srgbEncode_0(float c_0)
{
    float _S65;
    if(c_0 <= 0.00313080009073019)
    {
        _S65 = c_0 * 12.92000007629394531;
    }
    else
    {
        _S65 = 1.0549999475479126 * pow(c_0, 0.4166666567325592) - 0.05499999970197678;
    }
    return _S65;
}

float4 premultiplyColorSubpixel_0(float4 color_0, float3 cov_4, float alpha_cov_0)
{
    float _S66 = color_0.w;
    return float4(color_0.xyz * (float3(_S66)  * cov_4), _S66 * alpha_cov_0);
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

SubpixelResult_0 snailSubpixelFragment_0(const SubpixelVaryings_0 thread* v_1, texture2d_array<float, access::sample> curve_tex_5, texture2d_array<uint, access::sample> band_tex_3, int layer_base_0, int subpixel_order_2, int output_srgb_0, float coverage_exponent_3)
{
    thread SubpixelResult_0 r_2;
    float4 _S67 = float4(0.0) ;
    (&r_2)->color_1 = _S67;
    (&r_2)->blend_0 = _S67;
    (&r_2)->discard_fragment_0 = false;
    int4 _S68 = v_1->glyph_0;
    int _S69 = v_1->glyph_0.w;
    int layer_byte_0 = (_S69 >> 8U) & int(255);
    if(layer_byte_0 == int(255))
    {
        (&r_2)->discard_fragment_0 = true;
        return r_2;
    }
    float4 cov_alpha_0 = evalGlyphCoverageSubpixel_0(v_1->texcoord_0, _S68.xy, int2(_S69 & int(255), _S68.z), v_1->banding_3, layer_base_0 + layer_byte_0, subpixel_order_2, coverage_exponent_3, curve_tex_5, band_tex_3);
    float3 cov_5 = cov_alpha_0.xyz;
    if((max(max(cov_5.x, cov_5.y), cov_5.z)) < 0.00392156885936856)
    {
        (&r_2)->discard_fragment_0 = true;
        return r_2;
    }
    float4 color_3 = v_1->color_2 * v_1->tint_0;
    float4 effective_0;
    if(output_srgb_0 != int(0))
    {
        effective_0 = float4(srgbEncode_0(max(color_3.x, 0.0)), srgbEncode_0(max(color_3.y, 0.0)), srgbEncode_0(max(color_3.z, 0.0)), color_3.w);
    }
    else
    {
        effective_0 = color_3;
    }
    (&r_2)->color_1 = premultiplyColorSubpixel_0(effective_0, cov_5, cov_alpha_0.w);
    (&r_2)->blend_0 = float4(float3(color_3.w)  * cov_5, 0.0);
    return r_2;
}

struct FsOutput_0
{
    float4 color_4 [[color(0)]];
    float4 blend_1 [[color(1)]];
};

struct pixelInput_0
{
    float4 color_5 [[user(TEXCOORD)]];
    float2 texcoord_1 [[user(TEXCOORD_1)]];
    [[flat]] float4 banding_4 [[user(TEXCOORD_2)]];
    [[flat]] int4 glyph_1 [[user(TEXCOORD_3)]];
    float4 tint_1 [[user(TEXCOORD_4)]];
};

struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};

struct SnailPushConstants_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 mvp_0;
    float2 viewport_0;
    int subpixel_order_3;
    int output_srgb_1;
    int layer_base_1;
    float coverage_exponent_4;
    float dither_scale_0;
    int mask_output_0;
};

struct KernelContext_0
{
    SnailPushConstants_natural_0 constant* pc_0;
    texture2d_array<float, access::sample> u_curve_tex_0;
    texture2d_array<uint, access::sample> u_band_tex_0;
};

[[fragment]] FsOutput_0 fragmentMain(pixelInput_0 _S70 [[stage_in]], float4 position_0 [[position]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]])
{
    thread KernelContext_0 kernelContext_0;
    (&kernelContext_0)->pc_0 = pc_1;
    (&kernelContext_0)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_0)->u_band_tex_0 = u_band_tex_1;
    thread SubpixelVaryings_0 v_2;
    (&v_2)->color_2 = _S70.color_5;
    (&v_2)->tint_0 = _S70.tint_1;
    (&v_2)->texcoord_0 = _S70.texcoord_1;
    (&v_2)->banding_3 = _S70.banding_4;
    (&v_2)->glyph_0 = _S70.glyph_1;
    thread SubpixelVaryings_0 _S71 = v_2;
    SubpixelResult_0 _S72 = snailSubpixelFragment_0(&_S71, u_curve_tex_1, u_band_tex_1, pc_1->layer_base_1, pc_1->subpixel_order_3, pc_1->output_srgb_1, pc_1->coverage_exponent_4);
    if(_S72.discard_fragment_0)
    {
        discard_fragment();
    }
    thread FsOutput_0 o_0;
    (&o_0)->color_4 = _S72.color_1;
    (&o_0)->blend_1 = _S72.blend_0;
    return o_0;
}

