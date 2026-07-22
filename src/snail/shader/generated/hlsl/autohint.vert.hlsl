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
Texture2D<float4 > u_layer_tex_0 : register(t2);

static const float2  kCorners_0[int(4)] = { float2(0.0f, 0.0f), float2(1.0f, 0.0f), float2(1.0f, 1.0f), float2(0.0f, 1.0f) };
float srgbDecode_0(float c_0)
{
    float _S1;
    if(c_0 <= 0.04044999927282333f)
    {
        _S1 = c_0 / 12.92000007629394531f;
    }
    else
    {
        _S1 = pow((c_0 + 0.05499999970197678f) / 1.0549999475479126f, 2.40000009536743164f);
    }
    return _S1;
}

float3 srgbToLinear_0(float3 color_0)
{
    return float3(srgbDecode_0(color_0.x), srgbDecode_0(color_0.y), srgbDecode_0(color_0.z));
}

float snailVertexDilationScale_0(int subpixel_order_1)
{
    float _S2;
    if(subpixel_order_1 == int(0))
    {
        _S2 = 1.0f;
    }
    else
    {
        _S2 = 2.33333325386047363f;
    }
    return 1.41421353816986084f * _S2;
}

struct TextVertexResult_0
{
    float4 position_0;
    float4 color_1;
    float4 tint_0;
    float2 texcoord_0;
    float4 banding_0;
    int4 glyph_0;
};

struct TextVertexIn_0
{
    float4 rect_0;
    float4 xform_0;
    float2 origin_0;
    uint2 glyph_1;
    float4 bnd_0;
    float4 col_0;
    float4 tint_1;
};

TextVertexResult_0 snailTextVertex_0(TextVertexIn_0 input_0, uint vertex_index_0, float4x4 mvp_1, float2 viewport_1, int subpixel_order_2)
{
    float2 em_0 = lerp(input_0.rect_0.xy, input_0.rect_0.zw, kCorners_0[vertex_index_0]);
    float2 nd_0 = kCorners_0[vertex_index_0] * 2.0f - 1.0f;
    float _S3 = input_0.xform_0.x;
    float _S4 = em_0.x;
    float _S5 = input_0.xform_0.y;
    float _S6 = em_0.y;
    float _S7 = input_0.xform_0.z;
    float _S8 = input_0.xform_0.w;
    float2 pos_0 = float2(_S3 * _S4 + _S5 * _S6 + input_0.origin_0.x, _S7 * _S4 + _S8 * _S6 + input_0.origin_0.y);
    float _S9 = nd_0.x;
    float _S10 = nd_0.y;
    float2 wn_0 = float2(_S3 * _S9 + _S5 * _S10, _S7 * _S9 + _S8 * _S10);
    float inv_det_0 = 1.0f / (_S3 * _S8 - _S5 * _S7);
    float _S11 = _S8 * inv_det_0;
    float _S12 = - _S5 * inv_det_0;
    float _S13 = - _S7 * inv_det_0;
    float _S14 = _S3 * inv_det_0;
    uint gz_0 = input_0.glyph_1.x;
    uint gw_0 = input_0.glyph_1.y;
    TextVertexResult_0 r_0;
    r_0.glyph_0 = int4(int(gz_0 & 65535U), int(gz_0 >> 16U), int(gw_0 & 65535U), int(gw_0 >> 16U));
    r_0.banding_0 = input_0.bnd_0;
    r_0.color_1 = float4(srgbToLinear_0(input_0.col_0.xyz), input_0.col_0.w);
    r_0.tint_0 = float4(srgbToLinear_0(input_0.tint_1.xyz), input_0.tint_1.w);
    float2 n_0 = normalize(wn_0);
    float2 _S15 = mvp_1[int(3)].xy;
    float s_0 = dot(_S15, pos_0) + mvp_1[int(3)].w;
    float t_val_0 = dot(_S15, n_0);
    float2 _S16 = mvp_1[int(0)].xy;
    float u_val_0 = (s_0 * dot(_S16, n_0) - t_val_0 * (dot(_S16, pos_0) + mvp_1[int(0)].w)) * viewport_1.x;
    float2 _S17 = mvp_1[int(1)].xy;
    float v_val_0 = (s_0 * dot(_S17, n_0) - t_val_0 * (dot(_S17, pos_0) + mvp_1[int(1)].w)) * viewport_1.y;
    float s2_0 = s_0 * s_0;
    float st_0 = s_0 * t_val_0;
    float uv_0 = u_val_0 * u_val_0 + v_val_0 * v_val_0;
    float denom_0 = uv_0 - st_0 * st_0;
    float2 d_0;
    if((abs(denom_0)) > 1.00000001335143196e-10f)
    {
        d_0 = n_0 * (s2_0 * (st_0 + sqrt(uv_0)) / denom_0);
    }
    else
    {
        d_0 = n_0 * 2.0f / viewport_1;
    }
    float2 d_1 = d_0 * snailVertexDilationScale_0(subpixel_order_2);
    float2 p_0 = pos_0 + d_1;
    r_0.texcoord_0 = float2(_S4 + dot(d_1, float2(_S11, _S12)), _S6 + dot(d_1, float2(_S13, _S14)));
    r_0.position_0 = mul(mvp_1, float4(p_0, 0.0f, 1.0f));
    return r_0;
}

bool snailAhFinite_0(float v_0)
{
    return (abs(v_0)) <= 3.40282306073709653e+38f;
}

bool snailAhAffineScale_0(float4x4 mvp_2, float2 viewport_2, float4 xform_1, out float2 scale_0)
{
    scale_0 = float2(0.0f, 0.0f);
    bool _S18;
    if((abs(mvp_2[int(3)].x)) > 1.00000001168609742e-07f)
    {
        _S18 = true;
    }
    else
    {
        _S18 = (abs(mvp_2[int(3)].y)) > 1.00000001168609742e-07f;
    }
    if(_S18)
    {
        _S18 = true;
    }
    else
    {
        _S18 = !snailAhFinite_0(mvp_2[int(3)].w);
    }
    if(_S18)
    {
        _S18 = true;
    }
    else
    {
        _S18 = (abs(mvp_2[int(3)].w)) < 1.00000001335143196e-10f;
    }
    if(_S18)
    {
        return false;
    }
    float2 localX_0 = float2(xform_1.x, xform_1.z);
    float2 localY_0 = float2(xform_1.y, xform_1.w);
    float2 _S19 = 0.5f * viewport_2;
    float2 _S20 = mvp_2[int(0)].xy;
    float2 _S21 = mvp_2[int(1)].xy;
    float _S22 = mvp_2[int(3)].w;
    float2 screenX_0 = _S19 * float2(dot(_S20, localX_0), dot(_S21, localX_0)) / _S22;
    float2 screenY_0 = _S19 * float2(dot(_S20, localY_0), dot(_S21, localY_0)) / _S22;
    float _S23 = screenX_0.x;
    float _S24 = screenY_0.y;
    float _S25 = screenY_0.x;
    float _S26 = screenX_0.y;
    float det_0 = _S23 * _S24 - _S25 * _S26;
    if(!snailAhFinite_0(det_0))
    {
        _S18 = true;
    }
    else
    {
        _S18 = (abs(det_0)) < 1.00000001335143196e-10f;
    }
    if(_S18)
    {
        return false;
    }
    float _S27 = abs(det_0);
    float2 _S28 = 1.0f / float2((abs(_S24) + abs(_S25)) / _S27, (abs(_S26) + abs(_S23)) / _S27);
    scale_0 = _S28;
    if(snailAhFinite_0(_S28.x))
    {
        _S18 = snailAhFinite_0(scale_0.y);
    }
    else
    {
        _S18 = false;
    }
    if(_S18)
    {
        _S18 = (scale_0.x) > 0.0f;
    }
    else
    {
        _S18 = false;
    }
    if(_S18)
    {
        _S18 = (scale_0.y) > 0.0f;
    }
    else
    {
        _S18 = false;
    }
    return _S18;
}

void snailAhMarkFallback_0(out float4  packedTargets_0[int(4)], out uint4 packedSources_0)
{
    int i_0 = int(0);
    for(;;)
    {
        if(i_0 < int(4))
        {
        }
        else
        {
            break;
        }
        packedTargets_0[i_0] = (float4)0.0f;
        i_0 = i_0 + int(1);
    }
    uint4 _S29 = (uint4)4294967295U;
    packedSources_0 = _S29;
    packedSources_0[int(0)] = ((_S29.x) & 4294967040U) | 254U;
    return;
}

int2 snailAhLayerLoc_0(Texture2D<float4 > layer_tex_0, int2 base_0, int offset_0)
{
    uint uw_0;
    uint uh_0;
    layer_tex_0.GetDimensions(uw_0, uh_0);
    int width_0 = int(uw_0);
    int texel_0 = base_0.y * width_0 + base_0.x + offset_0;
    int _S30 = texel_0 % width_0;
    int _S31 = texel_0 / width_0;
    return int2(_S30, _S31);
}

float snailWarpF_0(Texture2D<float4 > layer_tex_1, int2 info_base_0, int block_0, int i_1)
{
    int f_0 = block_0 + i_1;
    int2 _S32 = snailAhLayerLoc_0(layer_tex_1, info_base_0, f_0 >> int(2));
    float4 t_0 = layer_tex_1.Load(int3(_S32, int(0)));
    int c_1 = f_0 & int(3);
    float _S33;
    if(c_1 == int(0))
    {
        _S33 = t_0.x;
    }
    else
    {
        if(c_1 == int(1))
        {
            _S33 = t_0.y;
        }
        else
        {
            if(c_1 == int(2))
            {
                _S33 = t_0.z;
            }
            else
            {
                _S33 = t_0.w;
            }
        }
    }
    return _S33;
}

struct SnailAutohintPolicy_0
{
    int xAlign_0;
    int xStem_0;
    int xPositioning_0;
    int xRegistration_0;
    int yAlign_0;
    int yStem_0;
    int yOvershoot_0;
    int fadeEnabled_0;
    float fadeStart_0;
    float fadeFull_0;
    float xRatio_0;
    float xMaxPx_0;
    float yRatio_0;
    float yMaxPx_0;
    float overshootMinPx_0;
};

bool snailDecodeAutohintPolicy_0(uint4 p0_0, uint3 p1_0, out SnailAutohintPolicy_0 p_1)
{
    p_1.xAlign_0 = int(0);
    p_1.xStem_0 = int(0);
    p_1.xPositioning_0 = int(0);
    p_1.xRegistration_0 = int(0);
    p_1.yAlign_0 = int(0);
    p_1.yStem_0 = int(0);
    p_1.yOvershoot_0 = int(0);
    p_1.fadeEnabled_0 = int(0);
    p_1.fadeStart_0 = 0.0f;
    p_1.fadeFull_0 = 0.0f;
    p_1.xRatio_0 = 0.0f;
    p_1.xMaxPx_0 = 0.0f;
    p_1.yRatio_0 = 0.0f;
    p_1.yMaxPx_0 = 0.0f;
    p_1.overshootMinPx_0 = 0.0f;
    uint x_0 = p0_0.x;
    uint y_0 = p0_0.y;
    bool _S34;
    if((x_0 & 4286578688U) != 0U)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (y_0 & 4294967232U) != 0U;
    }
    if(_S34)
    {
        return false;
    }
    int _S35 = int(x_0 & 3U);
    p_1.xAlign_0 = _S35;
    p_1.xStem_0 = int((x_0 >> 2U) & 3U);
    p_1.xPositioning_0 = int((x_0 >> 4U) & 3U);
    p_1.xRegistration_0 = int((x_0 >> 6U) & 3U);
    p_1.fadeEnabled_0 = int((x_0 >> 8U) & 1U);
    p_1.fadeStart_0 = float((x_0 >> 9U) & 127U);
    p_1.fadeFull_0 = float((x_0 >> 16U) & 127U);
    p_1.yAlign_0 = int(y_0 & 3U);
    p_1.yStem_0 = int((y_0 >> 2U) & 3U);
    p_1.yOvershoot_0 = int((y_0 >> 4U) & 3U);
    if(_S35 > int(1))
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.xStem_0) > int(2);
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.xPositioning_0) > int(1);
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.xRegistration_0) > int(1);
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.yAlign_0) > int(2);
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.yStem_0) > int(2);
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        _S34 = (p_1.yOvershoot_0) > int(1);
    }
    if(_S34)
    {
        return false;
    }
    p_1.xRatio_0 = asfloat(p0_0.z);
    p_1.xMaxPx_0 = asfloat(p0_0.w);
    p_1.yRatio_0 = asfloat(p1_0.x);
    p_1.yMaxPx_0 = asfloat(p1_0.y);
    p_1.overshootMinPx_0 = asfloat(p1_0.z);
    if((p_1.xStem_0) != int(0))
    {
        if(!snailAhFinite_0(p_1.xRatio_0))
        {
            _S34 = true;
        }
        else
        {
            _S34 = (p_1.xRatio_0) < 0.0f;
        }
    }
    else
    {
        _S34 = false;
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.xStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_1.xMaxPx_0))
            {
                _S34 = true;
            }
            else
            {
                _S34 = (p_1.xMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.yStem_0) != int(0))
        {
            if(!snailAhFinite_0(p_1.yRatio_0))
            {
                _S34 = true;
            }
            else
            {
                _S34 = (p_1.yRatio_0) < 0.0f;
            }
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.yStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_1.yMaxPx_0))
            {
                _S34 = true;
            }
            else
            {
                _S34 = (p_1.yMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.yOvershoot_0) == int(1))
        {
            if(!snailAhFinite_0(p_1.overshootMinPx_0))
            {
                _S34 = true;
            }
            else
            {
                _S34 = (p_1.overshootMinPx_0) < 0.0f;
            }
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.xPositioning_0) == int(1))
        {
            _S34 = (p_1.xAlign_0) == int(0);
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        _S34 = true;
    }
    else
    {
        if((p_1.yOvershoot_0) == int(1))
        {
            _S34 = (p_1.yAlign_0) != int(2);
        }
        else
        {
            _S34 = false;
        }
    }
    if(_S34)
    {
        return false;
    }
    return true;
}

bool snailAhCount_0(int max_knots_0, float encoded_0, out int count_0)
{
    bool _S36;
    if(!snailAhFinite_0(encoded_0))
    {
        _S36 = true;
    }
    else
    {
        _S36 = encoded_0 < 0.0f;
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = encoded_0 > float(max_knots_0);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = (floor(encoded_0)) != encoded_0;
    }
    if(_S36)
    {
        count_0 = int(0);
        return false;
    }
    count_0 = int(encoded_0);
    return true;
}

float snailAhSnap_0(float v_1, float scale_1)
{
    return round(v_1 * scale_1) / scale_1;
}

float snailAhStandardWidth_0(float raw_0, float standard_0, float ratio_0)
{
    bool _S37;
    if(standard_0 > 0.0f)
    {
        _S37 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S37 = false;
    }
    float _S38;
    if(_S37)
    {
        _S38 = standard_0;
    }
    else
    {
        _S38 = raw_0;
    }
    return _S38;
}

bool snailFitAutohintAxis_0(Texture2D<float4 > layer_tex_2, int2 info_base_1, int axis_0, int run_0, int blueCount_0, float standardWidth_0, float left_0, float scale_2, SnailAutohintPolicy_0 policy_0, out int knotCount_0, out float  knotBase_0[int(16)], out float  knotTarget_0[int(16)], out int  knotSource_0[int(16)])
{
    knotCount_0 = int(0);
    int i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        knotBase_0[i_2] = 0.0f;
        knotTarget_0[i_2] = 0.0f;
        knotSource_0[i_2] = int(0);
        i_2 = i_2 + int(1);
    }
    bool _S39;
    if(!snailAhFinite_0(scale_2))
    {
        _S39 = true;
    }
    else
    {
        _S39 = scale_2 <= 0.0f;
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = blueCount_0 < int(0);
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = blueCount_0 > int(16);
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = standardWidth_0 < 0.0f;
    }
    if(_S39)
    {
        return false;
    }
    bool _S40 = axis_0 == int(0);
    if(_S40)
    {
        _S39 = (policy_0.xAlign_0) == int(0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = (policy_0.xStem_0) == int(0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = (policy_0.xPositioning_0) == int(0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = (policy_0.xRegistration_0) == int(0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        if(axis_0 == int(1))
        {
            _S39 = (policy_0.yAlign_0) == int(0);
        }
        else
        {
            _S39 = false;
        }
        if(_S39)
        {
            _S39 = (policy_0.yStem_0) == int(0);
        }
        else
        {
            _S39 = false;
        }
        if(_S39)
        {
            _S39 = (policy_0.yOvershoot_0) == int(0);
        }
        else
        {
            _S39 = false;
        }
    }
    if(_S39)
    {
        return true;
    }
    float _S41 = snailWarpF_0(layer_tex_2, info_base_1, run_0, int(0));
    int n_1 = int(_S41);
    if(n_1 <= int(0))
    {
        _S39 = true;
    }
    else
    {
        _S39 = n_1 > int(16);
    }
    if(_S39)
    {
        return n_1 == int(0);
    }
    bool _S42 = axis_0 == int(1);
    if(_S42)
    {
        _S39 = (policy_0.yAlign_0) == int(2);
    }
    else
    {
        _S39 = false;
    }
    bool relative_0;
    if(_S40)
    {
        relative_0 = (policy_0.xRegistration_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    if(relative_0)
    {
        relative_0 = !snailAhFinite_0(left_0);
    }
    else
    {
        relative_0 = false;
    }
    if(relative_0)
    {
        return false;
    }
    bool _S43;
    bool upperBlue_0;
    bool lowerBlue_0;
    bool axisAligned_0;
    bool _S44;
    bool _S45;
    bool anchorSet_0;
    int clusterRight_0;
    int stemMode_0;
    float  pos_1[int(16)];
    float  width_1[int(16)];
    int  stem_0[int(16)];
    int  blue_0[int(16)];
    bool  rounded_0[int(16)];
    bool  syntheticApex_0[int(16)];
    int  companion_0[int(16)];
    int  dir_0[int(16)];
    float  targets_0[int(16)];
    bool  hinted_0[int(16)];
    bool  knotBlueFixed_0[int(16)];
    bool  knotNaturalSpacing_0[int(16)];
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_1)
        {
            break;
        }
        int f_1 = run_0 + int(1) + int(4) * i_2;
        float _S46 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(0));
        pos_1[i_2] = _S46;
        float _S47 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(1));
        width_1[i_2] = _S47;
        float _S48 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(2));
        uint refs_0 = asuint(_S48);
        stem_0[i_2] = int(refs_0 << 16U) >> int(16);
        blue_0[i_2] = int(refs_0) >> int(16);
        float _S49 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(3));
        uint flags_0 = asuint(_S49);
        rounded_0[i_2] = (flags_0 & 1U) != 0U;
        syntheticApex_0[i_2] = (flags_0 & 2U) != 0U;
        if((flags_0 & 4U) == 0U)
        {
            return false;
        }
        if((flags_0 & 8U) != 0U)
        {
            stemMode_0 = int(-1);
        }
        else
        {
            stemMode_0 = int(1);
        }
        dir_0[i_2] = stemMode_0;
        uint _S50;
        if(_S39)
        {
            _S50 = 10U;
        }
        else
        {
            _S50 = 4U;
        }
        int encodedCompanion_0 = int((flags_0 >> _S50) & 63U);
        if(encodedCompanion_0 >= int(62))
        {
            clusterRight_0 = int(-1);
        }
        else
        {
            clusterRight_0 = encodedCompanion_0;
        }
        companion_0[i_2] = clusterRight_0;
        if(encodedCompanion_0 >= int(63))
        {
            relative_0 = rounded_0[i_2];
        }
        else
        {
            relative_0 = false;
        }
        if(relative_0)
        {
            anchorSet_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(anchorSet_0)
        {
            return false;
        }
        hinted_0[i_2] = false;
        if(!snailAhFinite_0(pos_1[i_2]))
        {
            _S45 = true;
        }
        else
        {
            _S45 = !snailAhFinite_0(width_1[i_2]);
        }
        if(_S45)
        {
            _S44 = true;
        }
        else
        {
            _S44 = (width_1[i_2]) < 0.0f;
        }
        if(_S44)
        {
            axisAligned_0 = true;
        }
        else
        {
            axisAligned_0 = (stem_0[i_2]) < int(-1);
        }
        if(axisAligned_0)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (stem_0[i_2]) >= n_1;
        }
        if(lowerBlue_0)
        {
            upperBlue_0 = true;
        }
        else
        {
            upperBlue_0 = (blue_0[i_2]) < int(-1);
        }
        if(upperBlue_0)
        {
            _S43 = true;
        }
        else
        {
            _S43 = (blue_0[i_2]) >= blueCount_0;
        }
        if(_S43)
        {
            return false;
        }
        i_2 = i_2 + int(1);
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= blueCount_0)
        {
            break;
        }
        int _S51 = int(2) * i_2;
        float ref_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S51);
        float shoot_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S51 + int(1));
        if(!snailAhFinite_0(ref_0))
        {
            relative_0 = true;
        }
        else
        {
            relative_0 = !snailAhFinite_0(shoot_0);
        }
        if(relative_0)
        {
            return false;
        }
        i_2 = i_2 + int(1);
    }
    if(_S42)
    {
        relative_0 = (policy_0.yOvershoot_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    float spacing_0;
    if(relative_0)
    {
        spacing_0 = policy_0.overshootMinPx_0;
    }
    else
    {
        spacing_0 = 0.0f;
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_1)
        {
            break;
        }
        if((stem_0[i_2]) >= int(0))
        {
            relative_0 = (pos_1[stem_0[i_2]]) > (pos_1[i_2]);
        }
        else
        {
            relative_0 = false;
        }
        if(_S39)
        {
            anchorSet_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(!_S39)
        {
            if(relative_0)
            {
                stemMode_0 = int(-1);
            }
            else
            {
                stemMode_0 = int(1);
            }
            dir_0[i_2] = stemMode_0;
        }
        if(anchorSet_0)
        {
            float ref_1 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2]);
            float shoot_1 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2] + int(1));
            if(rounded_0[i_2])
            {
                _S45 = _S42;
            }
            else
            {
                _S45 = false;
            }
            if(_S45)
            {
                _S44 = (policy_0.yOvershoot_0) == int(0);
            }
            else
            {
                _S44 = false;
            }
            if(_S44)
            {
                targets_0[i_2] = pos_1[i_2];
            }
            else
            {
                targets_0[i_2] = snailAhSnap_0(ref_1, scale_2);
                if(rounded_0[i_2])
                {
                    axisAligned_0 = (abs((shoot_1 - ref_1) * scale_2)) >= spacing_0;
                }
                else
                {
                    axisAligned_0 = false;
                }
                if(axisAligned_0)
                {
                    targets_0[i_2] = targets_0[i_2] + (shoot_1 - ref_1);
                }
            }
        }
        else
        {
            targets_0[i_2] = snailAhSnap_0(pos_1[i_2], scale_2);
        }
        i_2 = i_2 + int(1);
    }
    float grid_0 = 1.0f / scale_2;
    if(_S40)
    {
        stemMode_0 = policy_0.xStem_0;
    }
    else
    {
        stemMode_0 = policy_0.yStem_0;
    }
    if(_S40)
    {
        spacing_0 = policy_0.xRatio_0;
    }
    else
    {
        spacing_0 = policy_0.yRatio_0;
    }
    float maxPx_0;
    if(_S40)
    {
        maxPx_0 = policy_0.xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0.yMaxPx_0;
    }
    if(_S40)
    {
        _S39 = (policy_0.xAlign_0) == int(1);
    }
    else
    {
        _S39 = (policy_0.yAlign_0) != int(0);
    }
    if(_S40)
    {
        relative_0 = (policy_0.xPositioning_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    float widthUnits_0;
    float bestGap_0;
    int j_0;
    int b_0;
    anchorSet_0 = false;
    float anchorTarget_0 = 0.0f;
    float anchorBase_0 = 0.0f;
    float clusterTarget_0 = 0.0f;
    float clusterBase_0 = 0.0f;
    float clusterDesiredRight_0 = 0.0f;
    clusterRight_0 = int(0);
    i_2 = int(0);
    int clusterStems_0 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_1)
        {
            break;
        }
        int j_1 = stem_0[i_2];
        if((stem_0[i_2]) < int(0))
        {
            _S45 = true;
        }
        else
        {
            _S45 = j_1 <= i_2;
        }
        if(_S45)
        {
            axisAligned_0 = anchorSet_0;
            int i_3 = i_2 + int(1);
            anchorSet_0 = axisAligned_0;
            i_2 = i_3;
            continue;
        }
        float nominal_0 = snailAhStandardWidth_0(width_1[i_2], standardWidth_0, spacing_0);
        float _S52 = width_1[i_2];
        if(stemMode_0 == int(2))
        {
            _S44 = true;
        }
        else
        {
            if(stemMode_0 == int(1))
            {
                _S44 = (nominal_0 * scale_2) < maxPx_0;
            }
            else
            {
                _S44 = false;
            }
        }
        if(_S44)
        {
            bestGap_0 = max(round(nominal_0 * scale_2), 1.0f) * grid_0;
        }
        else
        {
            bestGap_0 = _S52;
        }
        float anchorBase_1;
        float clusterTarget_1;
        float clusterBase_1;
        float clusterDesiredRight_1;
        if(relative_0)
        {
            if(anchorSet_0)
            {
                targets_0[i_2] = anchorTarget_0 + round((pos_1[i_2] - anchorBase_0) * scale_2) * grid_0;
                widthUnits_0 = clusterTarget_0;
                anchorBase_1 = clusterBase_0;
                axisAligned_0 = anchorSet_0;
            }
            else
            {
                float _S53 = snailAhSnap_0(pos_1[i_2], scale_2);
                targets_0[i_2] = _S53;
                widthUnits_0 = _S53;
                anchorBase_1 = pos_1[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_1] = targets_0[i_2] + bestGap_0;
            float _S54 = widthUnits_0 + round((pos_1[i_2] - anchorBase_1) * scale_2) * grid_0 + bestGap_0;
            int clusterStems_1 = clusterStems_0 + int(1);
            float _S55 = widthUnits_0;
            float _S56 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_1[i_2];
            clusterTarget_1 = _S55;
            clusterBase_1 = _S56;
            clusterDesiredRight_1 = _S54;
            b_0 = j_1;
            j_0 = clusterStems_1;
        }
        else
        {
            if(_S40)
            {
                axisAligned_0 = (policy_0.xAlign_0) != int(0);
            }
            else
            {
                axisAligned_0 = (policy_0.yAlign_0) != int(0);
            }
            if(axisAligned_0)
            {
                lowerBlue_0 = (blue_0[i_2]) >= int(0);
            }
            else
            {
                lowerBlue_0 = false;
            }
            if(axisAligned_0)
            {
                upperBlue_0 = (blue_0[j_1]) >= int(0);
            }
            else
            {
                upperBlue_0 = false;
            }
            if(!_S39)
            {
                targets_0[i_2] = pos_1[i_2];
            }
            if(upperBlue_0)
            {
                _S43 = !lowerBlue_0;
            }
            else
            {
                _S43 = false;
            }
            bool _S57;
            if(_S43)
            {
                _S57 = _S39;
            }
            else
            {
                _S57 = false;
            }
            if(_S57)
            {
                targets_0[i_2] = targets_0[j_1] - bestGap_0;
            }
            else
            {
                targets_0[j_1] = targets_0[i_2] + bestGap_0;
            }
            axisAligned_0 = anchorSet_0;
            widthUnits_0 = anchorTarget_0;
            anchorBase_1 = anchorBase_0;
            clusterTarget_1 = clusterTarget_0;
            clusterBase_1 = clusterBase_0;
            clusterDesiredRight_1 = clusterDesiredRight_0;
            b_0 = clusterRight_0;
            j_0 = clusterStems_0;
        }
        hinted_0[i_2] = true;
        hinted_0[j_1] = true;
        anchorTarget_0 = widthUnits_0;
        anchorBase_0 = anchorBase_1;
        clusterTarget_0 = clusterTarget_1;
        clusterBase_0 = clusterBase_1;
        clusterDesiredRight_0 = clusterDesiredRight_1;
        clusterRight_0 = b_0;
        clusterStems_0 = j_0;
        int i_3 = i_2 + int(1);
        anchorSet_0 = axisAligned_0;
        i_2 = i_3;
    }
    if(relative_0)
    {
        _S39 = clusterStems_0 > int(1);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        float _S58 = clusterDesiredRight_0 - targets_0[clusterRight_0];
        i_2 = int(0);
        for(;;)
        {
            if(i_2 < int(16))
            {
            }
            else
            {
                break;
            }
            if(i_2 >= n_1)
            {
                break;
            }
            if(hinted_0[i_2])
            {
                targets_0[i_2] = targets_0[i_2] + _S58;
            }
            i_2 = i_2 + int(1);
        }
    }
    if(stemMode_0 == int(1))
    {
        spacing_0 = maxPx_0;
    }
    else
    {
        spacing_0 = 1.60000002384185791f;
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_1)
        {
            break;
        }
        if(_S40)
        {
            axisAligned_0 = (policy_0.xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != int(0);
        }
        if(!axisAligned_0)
        {
            _S39 = true;
        }
        else
        {
            _S39 = (blue_0[i_2]) < int(0);
        }
        if(_S39)
        {
            relative_0 = true;
        }
        else
        {
            relative_0 = !rounded_0[i_2];
        }
        if(relative_0)
        {
            anchorSet_0 = true;
        }
        else
        {
            anchorSet_0 = hinted_0[i_2];
        }
        if(anchorSet_0)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        bool top_0 = (dir_0[i_2]) > int(0);
        int best_0 = companion_0[i_2];
        if((companion_0[i_2]) >= int(0))
        {
            if(top_0)
            {
                maxPx_0 = pos_1[i_2] - pos_1[best_0];
            }
            else
            {
                maxPx_0 = pos_1[best_0] - pos_1[i_2];
            }
            b_0 = best_0;
            bestGap_0 = maxPx_0;
        }
        else
        {
            if(best_0 == int(-2))
            {
                bestGap_0 = 3.4028234663852886e+38f;
                b_0 = best_0;
                j_0 = int(0);
                for(;;)
                {
                    if(j_0 < int(16))
                    {
                    }
                    else
                    {
                        break;
                    }
                    if(j_0 >= n_1)
                    {
                        break;
                    }
                    if(j_0 == i_2)
                    {
                        _S45 = true;
                    }
                    else
                    {
                        _S45 = (dir_0[j_0]) == (dir_0[i_2]);
                    }
                    if(_S45)
                    {
                        j_0 = j_0 + int(1);
                        continue;
                    }
                    if(top_0)
                    {
                        widthUnits_0 = pos_1[i_2] - pos_1[j_0];
                    }
                    else
                    {
                        widthUnits_0 = pos_1[j_0] - pos_1[i_2];
                    }
                    if(widthUnits_0 <= 0.0f)
                    {
                        _S44 = true;
                    }
                    else
                    {
                        _S44 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S44)
                    {
                        j_0 = j_0 + int(1);
                        continue;
                    }
                    bestGap_0 = widthUnits_0;
                    b_0 = j_0;
                    j_0 = j_0 + int(1);
                }
            }
            else
            {
                b_0 = best_0;
                bestGap_0 = 3.4028234663852886e+38f;
            }
        }
        if(b_0 < int(0))
        {
            _S45 = true;
        }
        else
        {
            _S45 = hinted_0[b_0];
        }
        if(_S45)
        {
            _S44 = true;
        }
        else
        {
            _S44 = (blue_0[b_0]) >= int(0);
        }
        if(_S44)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (bestGap_0 * scale_2) >= spacing_0;
        }
        if(lowerBlue_0)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        if(syntheticApex_0[b_0])
        {
            widthUnits_0 = bestGap_0;
        }
        else
        {
            widthUnits_0 = max(round(bestGap_0 * scale_2), 1.0f) * grid_0;
        }
        if(top_0)
        {
            maxPx_0 = targets_0[i_2] - widthUnits_0;
        }
        else
        {
            maxPx_0 = targets_0[i_2] + widthUnits_0;
        }
        targets_0[b_0] = maxPx_0;
        hinted_0[b_0] = true;
        i_2 = i_2 + int(1);
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_1)
        {
            break;
        }
        if(_S40)
        {
            axisAligned_0 = (policy_0.xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != int(0);
        }
        if(!hinted_0[i_2])
        {
            if(axisAligned_0)
            {
                _S39 = (blue_0[i_2]) >= int(0);
            }
            else
            {
                _S39 = false;
            }
            _S39 = !_S39;
        }
        else
        {
            _S39 = false;
        }
        if(_S39)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        knotBase_0[knotCount_0] = pos_1[i_2];
        knotTarget_0[knotCount_0] = targets_0[i_2];
        if(axisAligned_0)
        {
            relative_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            relative_0 = false;
        }
        knotBlueFixed_0[knotCount_0] = relative_0;
        knotNaturalSpacing_0[knotCount_0] = syntheticApex_0[i_2];
        knotSource_0[knotCount_0] = i_2;
        knotCount_0 = knotCount_0 + int(1);
        i_2 = i_2 + int(1);
    }
    if(_S40)
    {
        _S39 = (policy_0.xRegistration_0) == int(1);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = knotCount_0 > int(0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = knotCount_0 < int(16);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        _S39 = left_0 < (knotBase_0[int(0)] - 0.25f * grid_0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        i_2 = int(15);
        for(;;)
        {
            if(i_2 > int(0))
            {
            }
            else
            {
                break;
            }
            if(i_2 <= knotCount_0)
            {
                int _S59 = i_2 - int(1);
                knotBase_0[i_2] = knotBase_0[_S59];
                knotTarget_0[i_2] = knotTarget_0[_S59];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S59];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S59];
                knotSource_0[i_2] = knotSource_0[_S59];
            }
            i_2 = i_2 - int(1);
        }
        knotBase_0[int(0)] = left_0;
        knotTarget_0[int(0)] = snailAhSnap_0(left_0, scale_2);
        knotBlueFixed_0[int(0)] = false;
        knotNaturalSpacing_0[int(0)] = false;
        knotSource_0[int(0)] = int(32);
        knotCount_0 = knotCount_0 + int(1);
    }
    b_0 = int(15);
    for(;;)
    {
        if(b_0 > int(0))
        {
        }
        else
        {
            break;
        }
        if(b_0 >= knotCount_0)
        {
            _S39 = true;
        }
        else
        {
            _S39 = !knotBlueFixed_0[b_0];
        }
        if(_S39)
        {
            b_0 = b_0 - int(1);
            continue;
        }
        j_0 = int(15);
        for(;;)
        {
            if(j_0 > int(0))
            {
            }
            else
            {
                break;
            }
            if(j_0 > b_0)
            {
                j_0 = j_0 - int(1);
                continue;
            }
            int _S60 = j_0 - int(1);
            if(knotBlueFixed_0[_S60])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S60])
            {
                spacing_0 = 9.99999997475242708e-07f;
            }
            else
            {
                spacing_0 = grid_0;
            }
            knotTarget_0[_S60] = min(knotTarget_0[_S60], knotTarget_0[j_0] - spacing_0);
            j_0 = j_0 - int(1);
        }
        b_0 = b_0 - int(1);
    }
    i_2 = int(1);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= knotCount_0)
        {
            break;
        }
        if((knotTarget_0[i_2]) <= (knotTarget_0[i_2 - int(1)]))
        {
            knotTarget_0[i_2] = knotTarget_0[i_2 - int(1)] + grid_0;
        }
        i_2 = i_2 + int(1);
    }
    if((policy_0.fadeEnabled_0) != int(0))
    {
        _S39 = scale_2 > (policy_0.fadeStart_0);
    }
    else
    {
        _S39 = false;
    }
    if(_S39)
    {
        float span_0 = policy_0.fadeFull_0 - policy_0.fadeStart_0;
        if(span_0 <= 0.0f)
        {
            _S39 = true;
        }
        else
        {
            _S39 = scale_2 >= (policy_0.fadeFull_0);
        }
        if(_S39)
        {
            spacing_0 = 1.0f;
        }
        else
        {
            spacing_0 = (scale_2 - policy_0.fadeStart_0) / span_0;
        }
        i_2 = int(0);
        for(;;)
        {
            if(i_2 < int(16))
            {
            }
            else
            {
                break;
            }
            if(i_2 >= knotCount_0)
            {
                break;
            }
            knotTarget_0[i_2] = knotTarget_0[i_2] + (knotBase_0[i_2] - knotTarget_0[i_2]) * spacing_0;
            i_2 = i_2 + int(1);
        }
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= knotCount_0)
        {
            break;
        }
        if(!snailAhFinite_0(knotBase_0[i_2]))
        {
            _S39 = true;
        }
        else
        {
            _S39 = !snailAhFinite_0(knotTarget_0[i_2]);
        }
        if(_S39)
        {
            knotCount_0 = int(0);
            return false;
        }
        i_2 = i_2 + int(1);
    }
    return true;
}

void snailAhPackAxis_0(int count_1, float  targets_1[int(16)], int  sources_0[int(16)], out float4  packedTargets_1[int(4)], out uint4 packedSources_1)
{
    int i_4 = int(0);
    for(;;)
    {
        if(i_4 < int(4))
        {
        }
        else
        {
            break;
        }
        packedTargets_1[i_4] = (float4)0.0f;
        i_4 = i_4 + int(1);
    }
    packedSources_1 = (uint4)4294967295U;
    if(count_1 > int(16))
    {
        packedSources_1[int(0)] = ((packedSources_1.x) & 4294967040U) | 254U;
        return;
    }
    if(int(0) < count_1)
    {
        packedTargets_1[int(0)][int(0)] = targets_1[int(0)];
        packedSources_1[int(0)] = ((packedSources_1[int(0)]) & 4294967040U) | ((uint(sources_0[int(0)]) & 255U) << 0U);
    }
    if(int(1) < count_1)
    {
        packedTargets_1[int(0)][int(1)] = targets_1[int(1)];
        packedSources_1[int(0)] = ((packedSources_1[int(0)]) & 4294902015U) | ((uint(sources_0[int(1)]) & 255U) << 8U);
    }
    if(int(2) < count_1)
    {
        packedTargets_1[int(0)][int(2)] = targets_1[int(2)];
        packedSources_1[int(0)] = ((packedSources_1[int(0)]) & 4278255615U) | ((uint(sources_0[int(2)]) & 255U) << 16U);
    }
    if(int(3) < count_1)
    {
        packedTargets_1[int(0)][int(3)] = targets_1[int(3)];
        packedSources_1[int(0)] = ((packedSources_1[int(0)]) & 16777215U) | ((uint(sources_0[int(3)]) & 255U) << 24U);
    }
    if(int(4) < count_1)
    {
        packedTargets_1[int(1)][int(0)] = targets_1[int(4)];
        packedSources_1[int(1)] = ((packedSources_1[int(1)]) & 4294967040U) | ((uint(sources_0[int(4)]) & 255U) << 0U);
    }
    if(int(5) < count_1)
    {
        packedTargets_1[int(1)][int(1)] = targets_1[int(5)];
        packedSources_1[int(1)] = ((packedSources_1[int(1)]) & 4294902015U) | ((uint(sources_0[int(5)]) & 255U) << 8U);
    }
    if(int(6) < count_1)
    {
        packedTargets_1[int(1)][int(2)] = targets_1[int(6)];
        packedSources_1[int(1)] = ((packedSources_1[int(1)]) & 4278255615U) | ((uint(sources_0[int(6)]) & 255U) << 16U);
    }
    if(int(7) < count_1)
    {
        packedTargets_1[int(1)][int(3)] = targets_1[int(7)];
        packedSources_1[int(1)] = ((packedSources_1[int(1)]) & 16777215U) | ((uint(sources_0[int(7)]) & 255U) << 24U);
    }
    if(int(8) < count_1)
    {
        packedTargets_1[int(2)][int(0)] = targets_1[int(8)];
        packedSources_1[int(2)] = ((packedSources_1[int(2)]) & 4294967040U) | ((uint(sources_0[int(8)]) & 255U) << 0U);
    }
    if(int(9) < count_1)
    {
        packedTargets_1[int(2)][int(1)] = targets_1[int(9)];
        packedSources_1[int(2)] = ((packedSources_1[int(2)]) & 4294902015U) | ((uint(sources_0[int(9)]) & 255U) << 8U);
    }
    if(int(10) < count_1)
    {
        packedTargets_1[int(2)][int(2)] = targets_1[int(10)];
        packedSources_1[int(2)] = ((packedSources_1[int(2)]) & 4278255615U) | ((uint(sources_0[int(10)]) & 255U) << 16U);
    }
    if(int(11) < count_1)
    {
        packedTargets_1[int(2)][int(3)] = targets_1[int(11)];
        packedSources_1[int(2)] = ((packedSources_1[int(2)]) & 16777215U) | ((uint(sources_0[int(11)]) & 255U) << 24U);
    }
    if(int(12) < count_1)
    {
        packedTargets_1[int(3)][int(0)] = targets_1[int(12)];
        packedSources_1[int(3)] = ((packedSources_1[int(3)]) & 4294967040U) | ((uint(sources_0[int(12)]) & 255U) << 0U);
    }
    if(int(13) < count_1)
    {
        packedTargets_1[int(3)][int(1)] = targets_1[int(13)];
        packedSources_1[int(3)] = ((packedSources_1[int(3)]) & 4294902015U) | ((uint(sources_0[int(13)]) & 255U) << 8U);
    }
    if(int(14) < count_1)
    {
        packedTargets_1[int(3)][int(2)] = targets_1[int(14)];
        packedSources_1[int(3)] = ((packedSources_1[int(3)]) & 4278255615U) | ((uint(sources_0[int(14)]) & 255U) << 16U);
    }
    if(int(15) < count_1)
    {
        packedTargets_1[int(3)][int(3)] = targets_1[int(15)];
        packedSources_1[int(3)] = ((packedSources_1[int(3)]) & 16777215U) | ((uint(sources_0[int(15)]) & 255U) << 24U);
    }
    return;
}

struct AutohintVertexResult_0
{
    float4 position_1;
    float4 paint_0;
    float3 texcoord_layer_0;
    int2 info_0;
    uint4 policy0_0;
    uint3 policy1_0;
    float4  x_targets_0[int(4)];
    float4  y_targets_0[int(4)];
    uint4 x_sources_0;
    uint4 y_sources_0;
};

AutohintVertexResult_0 snailAutohintVertex_0(TextVertexIn_0 input_1, uint vertex_index_1, float4x4 mvp_3, float2 viewport_3, int subpixel_order_3, uint4 policy0_1, uint3 policy1_1, Texture2D<float4 > layer_tex_3)
{
    TextVertexResult_0 base_1 = snailTextVertex_0(input_1, vertex_index_1, mvp_3, viewport_3, subpixel_order_3);
    AutohintVertexResult_0 r_1;
    r_1.position_1 = base_1.position_0;
    r_1.paint_0 = base_1.color_1 * base_1.tint_0;
    r_1.texcoord_layer_0 = float3(base_1.texcoord_0, input_1.bnd_0.w);
    uint gz_1 = input_1.glyph_1.x;
    r_1.info_0 = int2(int(gz_1 & 65535U), int(gz_1 >> 16U));
    r_1.policy0_0 = policy0_1;
    r_1.policy1_0 = policy1_1;
    if(vertex_index_1 != 0U)
    {
        int i_5 = int(0);
        for(;;)
        {
            if(i_5 < int(4))
            {
            }
            else
            {
                break;
            }
            float4 _S61 = (float4)0.0f;
            r_1.x_targets_0[i_5] = _S61;
            r_1.y_targets_0[i_5] = _S61;
            i_5 = i_5 + int(1);
        }
        uint4 _S62 = (uint4)4294967295U;
        r_1.x_sources_0 = _S62;
        r_1.y_sources_0 = _S62;
        return r_1;
    }
    int2 info_base_2 = r_1.info_0;
    float2 scale_3;
    bool _S63 = snailAhAffineScale_0(mvp_3, viewport_3, input_1.xform_0, scale_3);
    if(!_S63)
    {
        snailAhMarkFallback_0(r_1.x_targets_0, r_1.x_sources_0);
        snailAhMarkFallback_0(r_1.y_targets_0, r_1.y_sources_0);
        return r_1;
    }
    int blueCount_1 = int(0);
    int featureXCount_0 = int(0);
    int featureYCount_0 = int(0);
    float stdX_0 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(8));
    float stdY_0 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(9));
    SnailAutohintPolicy_0 policy_1;
    bool _S64 = snailDecodeAutohintPolicy_0(policy0_1, policy1_1, policy_1);
    bool valid_0;
    if(_S64)
    {
        valid_0 = snailAhFinite_0(stdX_0);
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        valid_0 = stdX_0 >= 0.0f;
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        valid_0 = snailAhFinite_0(stdY_0);
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        valid_0 = stdY_0 >= 0.0f;
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        float _S65 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(10));
        bool _S66 = snailAhCount_0(int(16), _S65, blueCount_1);
        valid_0 = _S66;
    }
    else
    {
        valid_0 = false;
    }
    int xRun_0 = int(12) + int(2) * blueCount_1;
    if(valid_0)
    {
        float _S67 = snailWarpF_0(layer_tex_3, info_base_2, xRun_0, int(0));
        bool _S68 = snailAhCount_0(int(16), _S67, featureXCount_0);
        valid_0 = _S68;
    }
    else
    {
        valid_0 = false;
    }
    int yRun_0 = xRun_0 + int(1) + int(4) * featureXCount_0;
    if(valid_0)
    {
        float _S69 = snailWarpF_0(layer_tex_3, info_base_2, yRun_0, int(0));
        valid_0 = snailAhCount_0(int(16), _S69, featureYCount_0);
    }
    else
    {
        valid_0 = false;
    }
    if(!valid_0)
    {
        snailAhMarkFallback_0(r_1.x_targets_0, r_1.x_sources_0);
        snailAhMarkFallback_0(r_1.y_targets_0, r_1.y_sources_0);
        return r_1;
    }
    int xCount_0 = int(0);
    int yCount_0 = int(0);
    float _S70 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(11));
    float  xBase_0[int(16)];
    float  xTarget_0[int(16)];
    int  xSource_0[int(16)];
    bool xValid_0 = snailFitAutohintAxis_0(layer_tex_3, info_base_2, int(0), xRun_0, blueCount_1, stdX_0, _S70, scale_3.x, policy_1, xCount_0, xBase_0, xTarget_0, xSource_0);
    float  yBase_0[int(16)];
    float  yTarget_0[int(16)];
    int  ySource_0[int(16)];
    bool yValid_0 = snailFitAutohintAxis_0(layer_tex_3, info_base_2, int(1), yRun_0, blueCount_1, stdY_0, 0.0f, scale_3.y, policy_1, yCount_0, yBase_0, yTarget_0, ySource_0);
    if(xValid_0)
    {
        snailAhPackAxis_0(xCount_0, xTarget_0, xSource_0, r_1.x_targets_0, r_1.x_sources_0);
    }
    else
    {
        snailAhMarkFallback_0(r_1.x_targets_0, r_1.x_sources_0);
    }
    if(yValid_0)
    {
        snailAhPackAxis_0(yCount_0, yTarget_0, ySource_0, r_1.y_targets_0, r_1.y_sources_0);
    }
    else
    {
        snailAhMarkFallback_0(r_1.y_targets_0, r_1.y_sources_0);
    }
    return r_1;
}

struct VsOutput_0
{
    float4 position_2 : SV_Position;
    float4 paint_1 : TEXCOORD0;
    float3 texcoord_layer_1 : TEXCOORD1;
    nointerpolation int2 info_1 : TEXCOORD2;
    nointerpolation uint4 policy0_2 : TEXCOORD3;
    nointerpolation uint3 policy1_2 : TEXCOORD4;
    nointerpolation float4 x_targets0_0 : TEXCOORD5;
    nointerpolation float4 x_targets1_0 : TEXCOORD6;
    nointerpolation float4 x_targets2_0 : TEXCOORD7;
    nointerpolation float4 x_targets3_0 : TEXCOORD8;
    nointerpolation float4 y_targets0_0 : TEXCOORD9;
    nointerpolation float4 y_targets1_0 : TEXCOORD10;
    nointerpolation float4 y_targets2_0 : TEXCOORD11;
    nointerpolation float4 y_targets3_0 : TEXCOORD12;
    nointerpolation uint4 x_sources_1 : TEXCOORD13;
    nointerpolation uint4 y_sources_1 : TEXCOORD14;
};

struct VsInput_0
{
    float4 rect_1 : ATTRIB0;
    float4 xform_2 : ATTRIB1;
    float2 origin_1 : ATTRIB2;
    uint2 glyph_2 : ATTRIB3;
    float4 bnd_1 : ATTRIB4;
    float4 col_1 : ATTRIB5;
    float4 tint_2 : ATTRIB6;
    uint4 policy0_3 : ATTRIB7;
    uint3 policy1_3 : ATTRIB8;
};

VsOutput_0 vertexBody_0(VsInput_0 input_2, uint vertex_index_2)
{
    TextVertexIn_0 v_2;
    v_2.rect_0 = input_2.rect_1;
    v_2.xform_0 = input_2.xform_2;
    v_2.origin_0 = input_2.origin_1;
    v_2.glyph_1 = input_2.glyph_2;
    v_2.bnd_0 = input_2.bnd_1;
    v_2.col_0 = input_2.col_1;
    v_2.tint_1 = input_2.tint_2;
    AutohintVertexResult_0 r_2 = snailAutohintVertex_0(v_2, vertex_index_2, pc_0.mvp_0, pc_0.viewport_0, pc_0.subpixel_order_0, input_2.policy0_3, input_2.policy1_3, u_layer_tex_0);
    VsOutput_0 o_0;
    o_0.position_2 = r_2.position_1;
    o_0.paint_1 = r_2.paint_0;
    o_0.texcoord_layer_1 = r_2.texcoord_layer_0;
    o_0.info_1 = r_2.info_0;
    o_0.policy0_2 = r_2.policy0_0;
    o_0.policy1_2 = r_2.policy1_0;
    o_0.x_targets0_0 = r_2.x_targets_0[int(0)];
    o_0.x_targets1_0 = r_2.x_targets_0[int(1)];
    o_0.x_targets2_0 = r_2.x_targets_0[int(2)];
    o_0.x_targets3_0 = r_2.x_targets_0[int(3)];
    o_0.y_targets0_0 = r_2.y_targets_0[int(0)];
    o_0.y_targets1_0 = r_2.y_targets_0[int(1)];
    o_0.y_targets2_0 = r_2.y_targets_0[int(2)];
    o_0.y_targets3_0 = r_2.y_targets_0[int(3)];
    o_0.x_sources_1 = r_2.x_sources_0;
    o_0.y_sources_1 = r_2.y_sources_0;
    return o_0;
}

VsOutput_0 vertexMain(VsInput_0 input_3, uint vertex_index_3 : SV_VertexID)
{
    VsOutput_0 _S71 = vertexBody_0(input_3, vertex_index_3);
    VsOutput_0 o_1 = _S71;
    o_1.position_2[int(1)] = - o_1.position_2.y;
    return o_1;
}

