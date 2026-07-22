#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
float2 fwidth_0(float2 x_0)
{
    ;
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    thread CoverageBandSpan_0 _S1;
    (&_S1)->first_0 = first_1;
    (&_S1)->last_0 = last_1;
    return _S1;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S2 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S2), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S2), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_0)
{
    int _S3 = glyphLoc_0.x + int(offset_0);
    thread int2 loc_0 = int2(_S3, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S3 >> 12U);
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
    int _S4 = base_0.x + offset_1;
    thread int2 loc_1 = int2(_S4, base_0.y);
    loc_1.y = loc_1.y + (_S4 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_0)
{
    float _S5;
    if((abs(v_0)) <= 0.0000152587890625)
    {
        _S5 = 0.0;
    }
    else
    {
        _S5 = v_0;
    }
    return _S5;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S6;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S6 = 0.0;
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
    float2 a_0 = _S7 - _S8 * float2(2.0)  + p3_0;
    float2 b_1 = _S7 - _S8;
    float _S9 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S9)) < 0.0000152587890625)
    {
        float _S10 = b_1.y;
        if((abs(_S10)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p12_0.y * 0.5 / _S10;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S11 = b_1.y;
        float _S12 = p12_0.y;
        float _S13 = _S9 * _S12;
        float sq_0 = snapNearTangentSqrt_0(_S11 * _S11 - _S13, _S11, _S13);
        if(_S11 >= 0.0)
        {
            float q_0 = _S11 + sq_0;
            float _S14 = q_0 / _S9;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
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
    float _S18 = b_1.x * 2.0;
    float _S19 = p12_0.x;
    return float2((_S17 * t1_0 - _S18) * t1_0 + _S19, (_S17 * t2_0 - _S18) * t2_0 + _S19);
}

bool accumulateHorizContribution_0(float thread* xcov_0, float thread* xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, texture2d_array<float, access::sample> curve_tex_0)
{
    int4 _S20 = int4(cLoc_0, texLayer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S20)).xy), uint(((_S20)).z), uint(((_S20)).w)));
    int4 _S21 = int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = ((curve_tex_0).read(vec<uint,2>(((_S21)).xy), uint(((_S21)).z), uint(((_S21)).w))).xy - rc_0;
    float _S22 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S22) < -0.5)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * float2(_S22) ;
        if((code_0 & 1U) != 0U)
        {
            float _S23 = r_0.x;
            *xcov_0 = *xcov_0 + clamp(_S23 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S23) * 2.0, 0.0, 1.0));
        }
        if(code_0 > 1U)
        {
            float _S24 = r_0.y;
            *xcov_0 = *xcov_0 - clamp(_S24 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S24) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S25 = p12_2.xy;
    float2 _S26 = p12_2.zw;
    float2 a_1 = _S25 - _S26 * float2(2.0)  + p3_2;
    float2 b_2 = _S25 - _S26;
    float _S27 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S27)) < 0.0000152587890625)
    {
        float _S28 = b_2.x;
        if((abs(_S28)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p12_2.x * 0.5 / _S28;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S29 = b_2.x;
        float _S30 = p12_2.x;
        float _S31 = _S27 * _S30;
        float sq_1 = snapNearTangentSqrt_0(_S29 * _S29 - _S31, _S29, _S31);
        if(_S29 >= 0.0)
        {
            float q_2 = _S29 + sq_1;
            float _S32 = q_2 / _S27;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
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
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
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
    float _S36 = b_2.y * 2.0;
    float _S37 = p12_2.y;
    return float2((_S35 * t1_1 - _S36) * t1_1 + _S37, (_S35 * t2_1 - _S36) * t2_1 + _S37);
}

bool accumulateVertContribution_0(float thread* ycov_0, float thread* ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, texture2d_array<float, access::sample> curve_tex_1)
{
    int4 _S38 = int4(cLoc_1, texLayer_1, int(0));
    float4 tex0_1 = ((curve_tex_1).read(vec<uint,2>(((_S38)).xy), uint(((_S38)).z), uint(((_S38)).w)));
    int4 _S39 = int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = ((curve_tex_1).read(vec<uint,2>(((_S39)).xy), uint(((_S39)).z), uint(((_S39)).w))).xy - rc_1;
    float _S40 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S40) < -0.5)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * float2(_S40) ;
        if((code_1 & 1U) != 0U)
        {
            float _S41 = r_1.x;
            *ycov_0 = *ycov_0 - clamp(_S41 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S41) * 2.0, 0.0, 1.0));
        }
        if(code_1 > 1U)
        {
            float _S42 = r_1.y;
            *ycov_0 = *ycov_0 + clamp(_S42 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S42) * 2.0, 0.0, 1.0));
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
    float _S43 = max(coverage_exponent_0, 0.0000152587890625);
    float _S44;
    if((abs(_S43 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S44 = clamped_0;
    }
    else
    {
        _S44 = pow(clamped_0, _S43);
    }
    return _S44;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_0, float coverage_exponent_1)
{
    bool _S45;
    int i_0;
    int _S46 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S46);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    thread float xcov_1 = 0.0;
    thread float xwgt_1 = 0.0;
    bool _S47 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int4 _S48 = int4(calcBandLoc_0(gLoc_0, uint(band_1)), texLayer_2, int(0));
        uint2 hbd_0 = ((band_tex_0).read(vec<uint,2>(((_S48)).xy), uint(((_S48)).z), uint(((_S48)).w)).xy).xy;
        int2 _S49 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S50 = int(hbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S50)
            {
            }
            else
            {
                break;
            }
            int4 _S51 = int4(calcBandLoc_0(_S49, uint(i_0)), texLayer_2, int(0));
            uint2 ref_4 = ((band_tex_0).read(vec<uint,2>(((_S51)).xy), uint(((_S51)).z), uint(((_S51)).w)).xy).xy;
            if(_S47)
            {
                _S45 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S45 = false;
            }
            if(_S45)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S52 = accumulateHorizContribution_0(&xcov_1, &xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S52)
            {
                break;
            }
            i_0 = i_0 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    thread float ycov_1 = 0.0;
    thread float ywgt_1 = 0.0;
    bool _S53 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        int4 _S54 = int4(calcBandLoc_0(gLoc_0, uint(_S46 + int(1) + band_1)), texLayer_2, int(0));
        uint2 vbd_0 = ((band_tex_0).read(vec<uint,2>(((_S54)).xy), uint(((_S54)).z), uint(((_S54)).w)).xy).xy;
        int2 _S55 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S56 = int(vbd_0.x);
        i_0 = int(0);
        for(;;)
        {
            if(i_0 < _S56)
            {
            }
            else
            {
                break;
            }
            int4 _S57 = int4(calcBandLoc_0(_S55, uint(i_0)), texLayer_2, int(0));
            uint2 ref_5 = ((band_tex_0).read(vec<uint,2>(((_S57)).xy), uint(((_S57)).z), uint(((_S57)).w)).xy).xy;
            if(_S53)
            {
                _S45 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S45 = false;
            }
            if(_S45)
            {
                i_0 = i_0 + int(1);
                continue;
            }
            bool _S58 = accumulateVertContribution_0(&ycov_1, &ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S58)
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
    float _S59;
    if(c_0 <= 0.00313080009073019)
    {
        _S59 = c_0 * 12.92000007629394531;
    }
    else
    {
        _S59 = 1.0549999475479126 * pow(c_0, 0.4166666567325592) - 0.05499999970197678;
    }
    return _S59;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0)), srgbEncode_0(max(color_1.y, 0.0)), srgbEncode_0(max(color_1.z, 0.0)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S60 = premul_0.w;
    if(_S60 <= 0.0)
    {
        return float4(0.0) ;
    }
    return float4(linearToSrgb_0(premul_0.xyz * float3((1.0 / _S60)) ) * float3(_S60) , _S60);
}

struct TextVaryings_0
{
    float4 color_2;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_1;
    int4 glyph_0;
};

float4 snailTextFragment_0(const TextVaryings_0 thread* v_1, texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_1, int layer_base_0, int output_srgb_0, float coverage_exponent_2, int mask_output_0)
{
    int4 _S61 = v_1->glyph_0;
    int _S62 = v_1->glyph_0.w;
    int layer_byte_0 = (_S62 >> 8U) & int(255);
    if(layer_byte_0 == int(255))
    {
        discard_fragment();
    }
    float2 epp_1 = fwidth_0(v_1->texcoord_0);
    float cov_2 = evalGlyphCoverage_0(v_1->texcoord_0, epp_1, float2(1.0 / max(epp_1.x, 0.0000152587890625), 1.0 / max(epp_1.y, 0.0000152587890625)), _S61.xy, int2(_S62 & int(255), _S61.z), v_1->banding_1, layer_base_0 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_2);
    if(cov_2 < 0.00392156885936856)
    {
        discard_fragment();
    }
    float4 premul_1 = premultiplyColor_0(v_1->color_2 * v_1->tint_0, cov_2);
    float4 _S63;
    if(mask_output_0 != int(0))
    {
        _S63 = float4(premul_1.w) ;
    }
    else
    {
        if(output_srgb_0 != int(0))
        {
            _S63 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S63 = premul_1;
        }
    }
    return _S63;
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
};

[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S64 [[stage_in]], float4 position_0 [[position]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]])
{
    thread KernelContext_0 kernelContext_0;
    (&kernelContext_0)->pc_0 = pc_1;
    (&kernelContext_0)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_0)->u_band_tex_0 = u_band_tex_1;
    thread TextVaryings_0 v_2;
    (&v_2)->color_2 = _S64.color_3;
    (&v_2)->tint_0 = _S64.tint_1;
    (&v_2)->texcoord_0 = _S64.texcoord_1;
    (&v_2)->banding_1 = _S64.banding_2;
    (&v_2)->glyph_0 = _S64.glyph_1;
    thread TextVaryings_0 _S65 = v_2;
    float4 _S66 = snailTextFragment_0(&_S65, u_curve_tex_1, u_band_tex_1, pc_1->layer_base_1, pc_1->output_srgb_1, pc_1->coverage_exponent_3, pc_1->mask_output_1);
    pixelOutput_0 _S67 = { _S66 };
    return _S67;
}

