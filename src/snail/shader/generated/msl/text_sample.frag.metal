#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
struct SnailTextSampleParams_0
{
    int glyph_count_0;
    int words_per_glyph_0;
    int layer_base_0;
    float coverage_exponent_0;
};

struct KernelContext_0
{
    SnailTextSampleParams_0 constant* pc_0;
    texture2d_array<float, access::sample> u_curve_tex_0;
    texture2d_array<uint, access::sample> u_band_tex_0;
    texture_buffer<uint, access::read> u_snail_text_records_0;
};

uint Records_word_0(int linear_index_0, KernelContext_0 thread* kernelContext_0)
{
    return ((kernelContext_0->u_snail_text_records_0).read(uint((int(uint(linear_index_0))))).x);
}

uint snailTextSampleWord_0(int words_per_glyph_1, int glyph_index_0, int word_offset_0, KernelContext_0 thread* kernelContext_1)
{
    uint _S1 = Records_word_0(glyph_index_0 * words_per_glyph_1 + word_offset_0, kernelContext_1);
    return _S1;
}

float snailDecodeFloat16_0(uint bits_0)
{
    uint exponent_0 = (bits_0 >> 10U) & 31U;
    uint fraction_0 = bits_0 & 1023U;
    float sign_0;
    if((bits_0 >> 15U) == 0U)
    {
        sign_0 = 1.0;
    }
    else
    {
        sign_0 = -1.0;
    }
    if(exponent_0 == 0U)
    {
        if(fraction_0 == 0U)
        {
            return sign_0 * 0.0;
        }
        return sign_0 * exp2(-14.0) * (float(fraction_0) / 1024.0);
    }
    if(exponent_0 == 31U)
    {
        return sign_0 * 65504.0;
    }
    return sign_0 * exp2(float(exponent_0) - 15.0) * (1.0 + float(fraction_0) / 1024.0);
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
    return float4(float(word_1 & 255U), float((word_1 >> 8U) & 255U), float((word_1 >> 16U) & 255U), float((word_1 >> 24U) & 255U)) / float4(255.0) ;
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

SnailTextSampleRecord_0 snailTextSampleRecord_0(int words_per_glyph_2, int glyph_index_1, KernelContext_0 thread* kernelContext_2)
{
    thread SnailTextSampleRecord_0 record_0;
    uint _S2 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(0), kernelContext_2);
    uint _S3 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(1), kernelContext_2);
    (&record_0)->rect_0 = snailUnpackHalf4_0(_S2, _S3);
    uint _S4 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(2), kernelContext_2);
    float _S5 = (as_type<float>((_S4)));
    uint _S6 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(3), kernelContext_2);
    float _S7 = (as_type<float>((_S6)));
    uint _S8 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(4), kernelContext_2);
    float _S9 = (as_type<float>((_S8)));
    uint _S10 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(5), kernelContext_2);
    (&record_0)->xform_0 = float4(_S5, _S7, _S9, (as_type<float>((_S10))));
    uint _S11 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(6), kernelContext_2);
    float _S12 = (as_type<float>((_S11)));
    uint _S13 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(7), kernelContext_2);
    (&record_0)->origin_0 = float2(_S12, (as_type<float>((_S13))));
    uint _S14 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(8), kernelContext_2);
    uint _S15 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(9), kernelContext_2);
    (&record_0)->glyph_0 = uint2(_S14, _S15);
    uint _S16 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(10), kernelContext_2);
    float _S17 = (as_type<float>((_S16)));
    uint _S18 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(11), kernelContext_2);
    float _S19 = (as_type<float>((_S18)));
    uint _S20 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(12), kernelContext_2);
    float _S21 = (as_type<float>((_S20)));
    uint _S22 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(13), kernelContext_2);
    (&record_0)->banding_0 = float4(_S17, _S19, _S21, (as_type<float>((_S22))));
    uint _S23 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(14), kernelContext_2);
    (&record_0)->color_0 = snailUnpackUnorm4x8_0(_S23);
    uint _S24 = snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, int(15), kernelContext_2);
    (&record_0)->tint_0 = snailUnpackUnorm4x8_0(_S24);
    return record_0;
}

float2 snailTextSampleLocalCoord_0(float2 scene_pos_0, float4 xform_1, float2 origin_1)
{
    float _S25 = xform_1.x;
    float _S26 = xform_1.w;
    float _S27 = xform_1.y;
    float _S28 = xform_1.z;
    float det_0 = _S25 * _S26 - _S27 * _S28;
    float2 delta_0 = scene_pos_0 - origin_1;
    float _S29 = delta_0.x;
    float _S30 = delta_0.y;
    return float2((_S26 * _S29 - _S27 * _S30) / det_0, (- _S28 * _S29 + _S25 * _S30) / det_0);
}

float2 snailTextSampleLocalVector_0(float2 scene_vector_0, float4 xform_2)
{
    float _S31 = xform_2.x;
    float _S32 = xform_2.w;
    float _S33 = xform_2.y;
    float _S34 = xform_2.z;
    float det_1 = _S31 * _S32 - _S33 * _S34;
    float _S35 = scene_vector_0.x;
    float _S36 = scene_vector_0.y;
    return float2((_S32 * _S35 - _S33 * _S36) / det_1, (- _S34 * _S35 + _S31 * _S36) / det_1);
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    thread CoverageBandSpan_0 _S37;
    (&_S37)->first_0 = first_1;
    (&_S37)->last_0 = last_1;
    return _S37;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S38 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S38), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S38), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S39 = glyphLoc_0.x + int(offset_0);
    thread int2 loc_0 = int2(_S39, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S39 >> 12U);
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
    int _S40 = base_0.x + offset_1;
    thread int2 loc_1 = int2(_S40, base_0.y);
    loc_1.y = loc_1.y + (_S40 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S41;
    if((abs(v_0)) <= 0.0000152587890625)
    {
        _S41 = 0.0;
    }
    else
    {
        _S41 = v_0;
    }
    return _S41;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S42;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S42 = 0.0;
    }
    else
    {
        _S42 = sqrt(disc_0);
    }
    return _S42;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S43 = p12_0.xy;
    float2 _S44 = p12_0.zw;
    float2 a_0 = _S43 - _S44 * float2(2.0)  + p3_0;
    float2 b_1 = _S43 - _S44;
    float _S45 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S45)) < 0.0000152587890625)
    {
        float _S46 = b_1.y;
        if((abs(_S46)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p12_0.y * 0.5 / _S46;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S47 = b_1.y;
        float _S48 = p12_0.y;
        float _S49 = _S45 * _S48;
        float sq_0 = snapNearTangentSqrt_0(_S47 * _S47 - _S49, _S47, _S49);
        if(_S47 >= 0.0)
        {
            float q_0 = _S47 + sq_0;
            float _S50 = q_0 / _S45;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = _S48 / q_0;
            }
            t2_0 = _S50;
        }
        else
        {
            float q_1 = _S47 - sq_0;
            float _S51 = q_1 / _S45;
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = _S48 / q_1;
            }
            float _S52 = t1_0;
            t1_0 = _S51;
            t2_0 = _S52;
        }
    }
    float _S53 = a_0.x;
    float _S54 = b_1.x * 2.0;
    float _S55 = p12_0.x;
    return float2((_S53 * t1_0 - _S54) * t1_0 + _S55, (_S53 * t2_0 - _S54) * t2_0 + _S55);
}

bool accumulateHorizContribution_0(float thread* xcov_0, float thread* xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, texture2d_array<float, access::sample> curve_tex_0)
{
    int4 _S56 = int4(cLoc_0, texLayer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S56)).xy), uint(((_S56)).z), uint(((_S56)).w)));
    int4 _S57 = int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = ((curve_tex_0).read(vec<uint,2>(((_S57)).xy), uint(((_S57)).z), uint(((_S57)).w))).xy - rc_0;
    float _S58 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S58) < -0.5)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * float2(_S58) ;
        if((code_0 & 1U) != 0U)
        {
            float _S59 = r_0.x;
            *xcov_0 = *xcov_0 + clamp(_S59 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S59) * 2.0, 0.0, 1.0));
        }
        if(code_0 > 1U)
        {
            float _S60 = r_0.y;
            *xcov_0 = *xcov_0 - clamp(_S60 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S60) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S61 = p12_2.xy;
    float2 _S62 = p12_2.zw;
    float2 a_1 = _S61 - _S62 * float2(2.0)  + p3_2;
    float2 b_2 = _S61 - _S62;
    float _S63 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S63)) < 0.0000152587890625)
    {
        float _S64 = b_2.x;
        if((abs(_S64)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p12_2.x * 0.5 / _S64;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S65 = b_2.x;
        float _S66 = p12_2.x;
        float _S67 = _S63 * _S66;
        float sq_1 = snapNearTangentSqrt_0(_S65 * _S65 - _S67, _S65, _S67);
        if(_S65 >= 0.0)
        {
            float q_2 = _S65 + sq_1;
            float _S68 = q_2 / _S63;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S66 / q_2;
            }
            t2_1 = _S68;
        }
        else
        {
            float q_3 = _S65 - sq_1;
            float _S69 = q_3 / _S63;
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S66 / q_3;
            }
            float _S70 = t1_1;
            t1_1 = _S69;
            t2_1 = _S70;
        }
    }
    float _S71 = a_1.y;
    float _S72 = b_2.y * 2.0;
    float _S73 = p12_2.y;
    return float2((_S71 * t1_1 - _S72) * t1_1 + _S73, (_S71 * t2_1 - _S72) * t2_1 + _S73);
}

bool accumulateVertContribution_0(float thread* ycov_0, float thread* ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, texture2d_array<float, access::sample> curve_tex_1)
{
    int4 _S74 = int4(cLoc_1, texLayer_1, int(0));
    float4 tex0_1 = ((curve_tex_1).read(vec<uint,2>(((_S74)).xy), uint(((_S74)).z), uint(((_S74)).w)));
    int4 _S75 = int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = ((curve_tex_1).read(vec<uint,2>(((_S75)).xy), uint(((_S75)).z), uint(((_S75)).w))).xy - rc_1;
    float _S76 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S76) < -0.5)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * float2(_S76) ;
        if((code_1 & 1U) != 0U)
        {
            float _S77 = r_1.x;
            *ycov_0 = *ycov_0 - clamp(_S77 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S77) * 2.0, 0.0, 1.0));
        }
        if(code_1 > 1U)
        {
            float _S78 = r_1.y;
            *ycov_0 = *ycov_0 + clamp(_S78 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S78) * 2.0, 0.0, 1.0));
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

float applyCoverageTransfer_0(float cov_0, float coverage_exponent_1)
{
    float clamped_0 = clamp(cov_0, 0.0, 1.0);
    float _S79 = max(coverage_exponent_1, 0.0000152587890625);
    float _S80;
    if((abs(_S79 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S80 = clamped_0;
    }
    else
    {
        _S80 = pow(clamped_0, _S79);
    }
    return _S80;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_1, int texLayer_2, texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_0, float coverage_exponent_2)
{
    bool _S81;
    int i_0;
    int _S82 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_1.y, banding_1.w, _S82);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_1.x, banding_1.z, bandMax_1.x);
    thread float xcov_1 = 0.0;
    thread float xwgt_1 = 0.0;
    bool _S83 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int4 _S84 = int4(calcBandLoc_0(gLoc_0, uint(band_1)), texLayer_2, int(0));
        uint2 hbd_0 = ((band_tex_0).read(vec<uint,2>(((_S84)).xy), uint(((_S84)).z), uint(((_S84)).w)).xy).xy;
        int2 _S85 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S86 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S86)
            {
            }
            else
            {
                break;
            }
            int4 _S87 = int4(calcBandLoc_0(_S85, uint(i_0)), texLayer_2, int(0));
            uint2 ref_4 = ((band_tex_0).read(vec<uint,2>(((_S87)).xy), uint(((_S87)).z), uint(((_S87)).w)).xy).xy;
            if(_S83)
            {
                _S81 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S81 = false;
            }
            if(_S81)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S88 = accumulateHorizContribution_0(&xcov_1, &xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S88)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    thread float ycov_1 = 0.0;
    thread float ywgt_1 = 0.0;
    bool _S89 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        int4 _S90 = int4(calcBandLoc_0(gLoc_0, uint(_S82 + int(1) + band_1)), texLayer_2, int(0));
        uint2 vbd_0 = ((band_tex_0).read(vec<uint,2>(((_S90)).xy), uint(((_S90)).z), uint(((_S90)).w)).xy).xy;
        int2 _S91 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S92 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S92)
            {
            }
            else
            {
                break;
            }
            int4 _S93 = int4(calcBandLoc_0(_S91, uint(i_0)), texLayer_2, int(0));
            uint2 ref_5 = ((band_tex_0).read(vec<uint,2>(((_S93)).xy), uint(((_S93)).z), uint(((_S93)).w)).xy).xy;
            if(_S89)
            {
                _S81 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S81 = false;
            }
            if(_S81)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S94 = accumulateVertContribution_0(&ycov_1, &ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S94)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), coverage_exponent_2);
}

float srgbDecode_0(float c_0)
{
    float _S95;
    if(c_0 <= 0.04044999927282333)
    {
        _S95 = c_0 / 12.92000007629394531;
    }
    else
    {
        _S95 = pow((c_0 + 0.05499999970197678) / 1.0549999475479126, 2.40000009536743164);
    }
    return _S95;
}

float3 srgbToLinear_0(float3 color_1)
{
    return float3(srgbDecode_0(color_1.x), srgbDecode_0(color_1.y), srgbDecode_0(color_1.z));
}

float4 snailTextSamplePremulLinearWithFootprint_0(int words_per_glyph_3, int glyph_count_1, int layer_base_1, float coverage_exponent_3, texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_1, float2 scene_pos_1, float2 scene_dx_0, float2 scene_dy_0, KernelContext_0 thread* kernelContext_3)
{
    thread float4 paint_0 = float4(0.0) ;
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
        SnailTextSampleRecord_0 _S96 = snailTextSampleRecord_0(words_per_glyph_3, i_1, kernelContext_3);
        if((abs(_S96.xform_0.x * _S96.xform_0.w - _S96.xform_0.y * _S96.xform_0.z)) < 1.00000001335143196e-10)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float2 rc_3 = snailTextSampleLocalCoord_0(scene_pos_1, _S96.xform_0, _S96.origin_0);
        float2 epp_1 = abs(snailTextSampleLocalVector_0(scene_dx_0, _S96.xform_0)) + abs(snailTextSampleLocalVector_0(scene_dy_0, _S96.xform_0));
        float2 em_aa_0 = max(epp_1 * float2(2.0) , float2(0.00100000004749745) );
        float _S97 = rc_3.x;
        float _S98 = em_aa_0.x;
        bool _S99;
        if(_S97 < (_S96.rect_0.x - _S98))
        {
            _S99 = true;
        }
        else
        {
            _S99 = _S97 > (_S96.rect_0.z + _S98);
        }
        bool _S100;
        if(_S99)
        {
            _S100 = true;
        }
        else
        {
            _S100 = (rc_3.y) < (_S96.rect_0.y - em_aa_0.y);
        }
        bool _S101;
        if(_S100)
        {
            _S101 = true;
        }
        else
        {
            _S101 = (rc_3.y) > (_S96.rect_0.w + em_aa_0.y);
        }
        if(_S101)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        uint gz_0 = _S96.glyph_0.x;
        uint gw_0 = _S96.glyph_0.y;
        int layer_byte_0 = int((gw_0 >> 24U) & 255U);
        if(layer_byte_0 == int(255))
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float alpha_0 = clamp(evalGlyphCoverage_0(rc_3, epp_1, float2(1.0 / max(epp_1.x, 0.0000152587890625), 1.0 / max(epp_1.y, 0.0000152587890625)), int2(int(gz_0 & 65535U), int(gz_0 >> 16U)), int2(int((gw_0 >> 16U) & 255U), int(gw_0 & 65535U)), _S96.banding_0, layer_base_1 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_3) * _S96.color_0.w * _S96.tint_0.w, 0.0, 1.0);
        if(alpha_0 <= 0.00392156885936856)
        {
            i_1 = i_1 + int(1);
            continue;
        }
        float _S102 = 1.0 - alpha_0;
        paint_0.xyz = srgbToLinear_0(_S96.color_0.xyz) * srgbToLinear_0(_S96.tint_0.xyz) * float3(alpha_0)  + paint_0.xyz * float3(_S102) ;
        paint_0.w = alpha_0 + paint_0.w * _S102;
        i_1 = i_1 + int(1);
    }
    return paint_0;
}

float4 snailTextSamplePremulLinear_0(int words_per_glyph_4, int glyph_count_2, int layer_base_2, float coverage_exponent_4, texture2d_array<float, access::sample> curve_tex_4, texture2d_array<uint, access::sample> band_tex_2, float2 scene_pos_2, KernelContext_0 thread* kernelContext_4)
{
    float4 _S103 = snailTextSamplePremulLinearWithFootprint_0(words_per_glyph_4, glyph_count_2, layer_base_2, coverage_exponent_4, curve_tex_4, band_tex_2, scene_pos_2, dfdx(scene_pos_2), dfdy(scene_pos_2), kernelContext_4);
    return _S103;
}

struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};

struct pixelInput_0
{
    float2 scene_pos_3 [[user(TEXCOORD)]];
};

[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S104 [[stage_in]], float4 position_0 [[position]], SnailTextSampleParams_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]], texture_buffer<uint, access::read> u_snail_text_records_1 [[texture(2)]])
{
    thread KernelContext_0 kernelContext_5;
    (&kernelContext_5)->pc_0 = pc_1;
    (&kernelContext_5)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_5)->u_band_tex_0 = u_band_tex_1;
    (&kernelContext_5)->u_snail_text_records_0 = u_snail_text_records_1;
    float4 _S105 = snailTextSamplePremulLinear_0(pc_1->words_per_glyph_0, pc_1->glyph_count_0, pc_1->layer_base_0, pc_1->coverage_exponent_0, u_curve_tex_1, u_band_tex_1, _S104.scene_pos_3, &kernelContext_5);
    pixelOutput_0 _S106 = { _S105 };
    return _S106;
}

