#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
float2 fwidth_0(float2 x_0)
{
    ;
}

int2 offsetTtHintedInfoLoc_0(texture2d<float, access::sample> layer_tex_0, int2 base_0, int offset_0)
{
    thread uint uw_0;
    thread uint uh_0;
    (*((&uw_0)) = (layer_tex_0).get_width(0)),(*((&uh_0)) = (layer_tex_0).get_height(0));
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
    thread CoverageBandSpan_0 _S3;
    (&_S3)->first_0 = first_1;
    (&_S3)->last_0 = last_1;
    return _S3;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S4 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S4), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S4), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S5 = glyphLoc_0.x + int(offset_1);
    thread int2 loc_0 = int2(_S5, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S5 >> 12U);
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

int2 offsetCurveLoc_0(int2 base_1, int offset_2)
{
    int _S6 = base_1.x + offset_2;
    thread int2 loc_1 = int2(_S6, base_1.y);
    loc_1.y = loc_1.y + (_S6 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S7;
    if((abs(v_0)) <= 0.0000152587890625)
    {
        _S7 = 0.0;
    }
    else
    {
        _S7 = v_0;
    }
    return _S7;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S8;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S8 = 0.0;
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
    float2 a_0 = _S9 - _S10 * float2(2.0)  + p3_0;
    float2 b_1 = _S9 - _S10;
    float _S11 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S11)) < 0.0000152587890625)
    {
        float _S12 = b_1.y;
        if((abs(_S12)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p12_0.y * 0.5 / _S12;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S13 = b_1.y;
        float _S14 = p12_0.y;
        float _S15 = _S11 * _S14;
        float sq_0 = snapNearTangentSqrt_0(_S13 * _S13 - _S15, _S13, _S15);
        if(_S13 >= 0.0)
        {
            float q_0 = _S13 + sq_0;
            float _S16 = q_0 / _S11;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
    float _S20 = b_1.x * 2.0;
    float _S21 = p12_0.x;
    return float2((_S19 * t1_0 - _S20) * t1_0 + _S21, (_S19 * t2_0 - _S20) * t2_0 + _S21);
}

bool accumulateHorizContribution_0(float thread* xcov_0, float thread* xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, texture2d_array<float, access::sample> curve_tex_0)
{
    int4 _S22 = int4(cLoc_0, texLayer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S22)).xy), uint(((_S22)).z), uint(((_S22)).w)));
    int4 _S23 = int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = ((curve_tex_0).read(vec<uint,2>(((_S23)).xy), uint(((_S23)).z), uint(((_S23)).w))).xy - rc_0;
    float _S24 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S24) < -0.5)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * float2(_S24) ;
        if((code_0 & 1U) != 0U)
        {
            float _S25 = r_0.x;
            *xcov_0 = *xcov_0 + clamp(_S25 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S25) * 2.0, 0.0, 1.0));
        }
        if(code_0 > 1U)
        {
            float _S26 = r_0.y;
            *xcov_0 = *xcov_0 - clamp(_S26 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S26) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S27 = p12_2.xy;
    float2 _S28 = p12_2.zw;
    float2 a_1 = _S27 - _S28 * float2(2.0)  + p3_2;
    float2 b_2 = _S27 - _S28;
    float _S29 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S29)) < 0.0000152587890625)
    {
        float _S30 = b_2.x;
        if((abs(_S30)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p12_2.x * 0.5 / _S30;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S31 = b_2.x;
        float _S32 = p12_2.x;
        float _S33 = _S29 * _S32;
        float sq_1 = snapNearTangentSqrt_0(_S31 * _S31 - _S33, _S31, _S33);
        if(_S31 >= 0.0)
        {
            float q_2 = _S31 + sq_1;
            float _S34 = q_2 / _S29;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S32 / q_2;
            }
            t2_1 = _S34;
        }
        else
        {
            float q_3 = _S31 - sq_1;
            float _S35 = q_3 / _S29;
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S32 / q_3;
            }
            float _S36 = t1_1;
            t1_1 = _S35;
            t2_1 = _S36;
        }
    }
    float _S37 = a_1.y;
    float _S38 = b_2.y * 2.0;
    float _S39 = p12_2.y;
    return float2((_S37 * t1_1 - _S38) * t1_1 + _S39, (_S37 * t2_1 - _S38) * t2_1 + _S39);
}

bool accumulateVertContribution_0(float thread* ycov_0, float thread* ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, texture2d_array<float, access::sample> curve_tex_1)
{
    int4 _S40 = int4(cLoc_1, texLayer_1, int(0));
    float4 tex0_1 = ((curve_tex_1).read(vec<uint,2>(((_S40)).xy), uint(((_S40)).z), uint(((_S40)).w)));
    int4 _S41 = int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = ((curve_tex_1).read(vec<uint,2>(((_S41)).xy), uint(((_S41)).z), uint(((_S41)).w))).xy - rc_1;
    float _S42 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S42) < -0.5)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * float2(_S42) ;
        if((code_1 & 1U) != 0U)
        {
            float _S43 = r_1.x;
            *ycov_0 = *ycov_0 - clamp(_S43 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S43) * 2.0, 0.0, 1.0));
        }
        if(code_1 > 1U)
        {
            float _S44 = r_1.y;
            *ycov_0 = *ycov_0 + clamp(_S44 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S44) * 2.0, 0.0, 1.0));
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

float applyCoverageTransfer_0(float cov_0, float coverage_exponent_0)
{
    float clamped_0 = clamp(cov_0, 0.0, 1.0);
    float _S45 = max(coverage_exponent_0, 0.0000152587890625);
    float _S46;
    if((abs(_S45 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S46 = clamped_0;
    }
    else
    {
        _S46 = pow(clamped_0, _S45);
    }
    return _S46;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_0, float coverage_exponent_1)
{
    bool _S47;
    int i_0;
    int _S48 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S48);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    thread float xcov_1 = 0.0;
    thread float xwgt_1 = 0.0;
    bool _S49 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int4 _S50 = int4(calcBandLoc_0(gLoc_0, uint(band_1)), texLayer_2, int(0));
        uint2 hbd_0 = ((band_tex_0).read(vec<uint,2>(((_S50)).xy), uint(((_S50)).z), uint(((_S50)).w)).xy).xy;
        int2 _S51 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S52 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S52)
            {
            }
            else
            {
                break;
            }
            int4 _S53 = int4(calcBandLoc_0(_S51, uint(i_0)), texLayer_2, int(0));
            uint2 ref_4 = ((band_tex_0).read(vec<uint,2>(((_S53)).xy), uint(((_S53)).z), uint(((_S53)).w)).xy).xy;
            if(_S49)
            {
                _S47 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S54 = accumulateHorizContribution_0(&xcov_1, &xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S54)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    thread float ycov_1 = 0.0;
    thread float ywgt_1 = 0.0;
    bool _S55 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        int4 _S56 = int4(calcBandLoc_0(gLoc_0, uint(_S48 + int(1) + band_1)), texLayer_2, int(0));
        uint2 vbd_0 = ((band_tex_0).read(vec<uint,2>(((_S56)).xy), uint(((_S56)).z), uint(((_S56)).w)).xy).xy;
        int2 _S57 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S58 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S58)
            {
            }
            else
            {
                break;
            }
            int4 _S59 = int4(calcBandLoc_0(_S57, uint(i_0)), texLayer_2, int(0));
            uint2 ref_5 = ((band_tex_0).read(vec<uint,2>(((_S59)).xy), uint(((_S59)).z), uint(((_S59)).w)).xy).xy;
            if(_S55)
            {
                _S47 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S60 = accumulateVertContribution_0(&ycov_1, &ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S60)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625), int(0)), min(applyFillRule_0(xcov_1, int(0)), applyFillRule_0(ycov_1, int(0)))), coverage_exponent_1);
}

float4 premultiplyColor_0(float4 color_0, float cov_1)
{
    float alpha_0 = color_0.w * cov_1;
    return float4(color_0.xyz * float3(alpha_0) , alpha_0);
}

float srgbEncode_0(float c_0)
{
    float _S61;
    if(c_0 <= 0.00313080009073019)
    {
        _S61 = c_0 * 12.92000007629394531;
    }
    else
    {
        _S61 = 1.0549999475479126 * pow(c_0, 0.4166666567325592) - 0.05499999970197678;
    }
    return _S61;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0)), srgbEncode_0(max(color_1.y, 0.0)), srgbEncode_0(max(color_1.z, 0.0)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S62 = premul_0.w;
    if(_S62 <= 0.0)
    {
        return float4(0.0) ;
    }
    return float4(linearToSrgb_0(premul_0.xyz * float3((1.0 / _S62)) ) * float3(_S62) , _S62);
}

struct TtHintedVaryings_0
{
    float4 color_2;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_1;
    int4 glyph_0;
};

float4 snailTtHintedTextFragment_0(const TtHintedVaryings_0 thread* v_1, texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_1, texture2d<float, access::sample> layer_tex_1, int layer_base_0, int output_srgb_0, float coverage_exponent_2, int mask_output_0)
{
    int4 _S63 = v_1->glyph_0;
    int _S64 = v_1->glyph_0.w;
    if(((_S64 >> 8U) & int(255)) != int(255))
    {
        discard_fragment();
    }
    if((_S64 & int(255)) != int(2))
    {
        discard_fragment();
    }
    float2 epp_1 = fwidth_0(v_1->texcoord_0);
    float2 ppe_3 = float2(1.0 / max(epp_1.x, 0.0000152587890625), 1.0 / max(epp_1.y, 0.0000152587890625));
    int2 info_base_0 = _S63.xy;
    int3 _S65 = int3(info_base_0, int(0));
    float4 header_0 = ((layer_tex_1).read(vec<uint,2>(((_S65)).xy), uint(((_S65)).z)));
    int2 _S66 = offsetTtHintedInfoLoc_0(layer_tex_1, info_base_0, int(1));
    int3 _S67 = int3(_S66, int(0));
    int packed_counts_0 = (as_type<int>((header_0.z)));
    float cov_2 = evalGlyphCoverage_0(v_1->texcoord_0, epp_1, ppe_3, int2(int(header_0.x), int(header_0.y)), int2((packed_counts_0 >> 16U) & int(65535), packed_counts_0 & int(65535)), ((layer_tex_1).read(vec<uint,2>(((_S67)).xy), uint(((_S67)).z))), layer_base_0 + int(v_1->banding_1.w), curve_tex_3, band_tex_1, coverage_exponent_2);
    if(cov_2 < 0.00392156885936856)
    {
        discard_fragment();
    }
    float4 premul_1 = premultiplyColor_0(v_1->color_2 * v_1->tint_0, cov_2);
    float4 _S68;
    if(mask_output_0 != int(0))
    {
        _S68 = float4(premul_1.w) ;
    }
    else
    {
        if(output_srgb_0 != int(0))
        {
            _S68 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S68 = premul_1;
        }
    }
    return _S68;
}

struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};

struct pixelInput_0
{
    float4 color_3 [[user(TEXCOORD)]];
    float2 texcoord_1 [[user(TEXCOORD_1)]];
    [[flat]] float4 banding_2 [[user(TEXCOORD_2)]];
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
    int subpixel_order_0;
    int output_srgb_1;
    int layer_base_1;
    float coverage_exponent_3;
    float dither_scale_0;
    int mask_output_1;
};

struct KernelContext_0
{
    SnailPushConstants_natural_0 constant* pc_0;
    texture2d_array<float, access::sample> u_curve_tex_0;
    texture2d_array<uint, access::sample> u_band_tex_0;
    texture2d<float, access::sample> u_layer_tex_0;
};

[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S69 [[stage_in]], float4 position_0 [[position]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]], texture2d<float, access::sample> u_layer_tex_1 [[texture(2)]])
{
    thread KernelContext_0 kernelContext_0;
    (&kernelContext_0)->pc_0 = pc_1;
    (&kernelContext_0)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_0)->u_band_tex_0 = u_band_tex_1;
    (&kernelContext_0)->u_layer_tex_0 = u_layer_tex_1;
    thread TtHintedVaryings_0 v_2;
    (&v_2)->color_2 = _S69.color_3;
    (&v_2)->tint_0 = _S69.tint_1;
    (&v_2)->texcoord_0 = _S69.texcoord_1;
    (&v_2)->banding_1 = _S69.banding_2;
    (&v_2)->glyph_0 = _S69.glyph_1;
    thread TtHintedVaryings_0 _S70 = v_2;
    float4 _S71 = snailTtHintedTextFragment_0(&_S70, u_curve_tex_1, u_band_tex_1, u_layer_tex_1, pc_1->layer_base_1, pc_1->output_srgb_1, pc_1->coverage_exponent_3, pc_1->mask_output_1);
    pixelOutput_0 _S72 = { _S71 };
    return _S72;
}

