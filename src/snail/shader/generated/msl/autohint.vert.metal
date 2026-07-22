#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
constant array<float2, int(4)> kCorners_0 = { float2(0.0, 0.0), float2(1.0, 0.0), float2(1.0, 1.0), float2(0.0, 1.0) };
float srgbDecode_0(float c_0)
{
    float _S1;
    if(c_0 <= 0.04044999927282333)
    {
        _S1 = c_0 / 12.92000007629394531;
    }
    else
    {
        _S1 = pow((c_0 + 0.05499999970197678) / 1.0549999475479126, 2.40000009536743164);
    }
    return _S1;
}

float3 srgbToLinear_0(float3 color_0)
{
    return float3(srgbDecode_0(color_0.x), srgbDecode_0(color_0.y), srgbDecode_0(color_0.z));
}

float snailVertexDilationScale_0(int subpixel_order_0)
{
    float _S2;
    if(subpixel_order_0 == int(0))
    {
        _S2 = 1.0;
    }
    else
    {
        _S2 = 2.33333325386047363;
    }
    return 1.41421353816986084 * _S2;
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

TextVertexResult_0 snailTextVertex_0(const TextVertexIn_0 thread* input_0, uint vertex_index_0, matrix<float,int(4),int(4)>  mvp_0, float2 viewport_0, int subpixel_order_1)
{
    float2 em_0 = mix(input_0->rect_0.xy, input_0->rect_0.zw, kCorners_0[vertex_index_0]);
    float2 _S3 = float2(2.0) ;
    float2 nd_0 = kCorners_0[vertex_index_0] * _S3 - float2(1.0) ;
    float _S4 = input_0->xform_0.x;
    float _S5 = em_0.x;
    float _S6 = input_0->xform_0.y;
    float _S7 = em_0.y;
    float _S8 = input_0->xform_0.z;
    float _S9 = input_0->xform_0.w;
    float2 pos_0 = float2(_S4 * _S5 + _S6 * _S7 + input_0->origin_0.x, _S8 * _S5 + _S9 * _S7 + input_0->origin_0.y);
    float _S10 = nd_0.x;
    float _S11 = nd_0.y;
    float2 wn_0 = float2(_S4 * _S10 + _S6 * _S11, _S8 * _S10 + _S9 * _S11);
    float inv_det_0 = 1.0 / (_S4 * _S9 - _S6 * _S8);
    float _S12 = _S9 * inv_det_0;
    float _S13 = - _S6 * inv_det_0;
    float _S14 = - _S8 * inv_det_0;
    float _S15 = _S4 * inv_det_0;
    uint gz_0 = input_0->glyph_1.x;
    uint gw_0 = input_0->glyph_1.y;
    thread TextVertexResult_0 r_0;
    (&r_0)->glyph_0 = int4(int(gz_0 & 65535U), int(gz_0 >> 16U), int(gw_0 & 65535U), int(gw_0 >> 16U));
    (&r_0)->banding_0 = input_0->bnd_0;
    (&r_0)->color_1 = float4(srgbToLinear_0(input_0->col_0.xyz), input_0->col_0.w);
    (&r_0)->tint_0 = float4(srgbToLinear_0(input_0->tint_1.xyz), input_0->tint_1.w);
    float2 n_0 = normalize(wn_0);
    float2 _S16 = mvp_0[int(3)].xy;
    float s_0 = dot(_S16, pos_0) + mvp_0[int(3)].w;
    float t_val_0 = dot(_S16, n_0);
    float2 _S17 = mvp_0[int(0)].xy;
    float u_val_0 = (s_0 * dot(_S17, n_0) - t_val_0 * (dot(_S17, pos_0) + mvp_0[int(0)].w)) * viewport_0.x;
    float2 _S18 = mvp_0[int(1)].xy;
    float v_val_0 = (s_0 * dot(_S18, n_0) - t_val_0 * (dot(_S18, pos_0) + mvp_0[int(1)].w)) * viewport_0.y;
    float s2_0 = s_0 * s_0;
    float st_0 = s_0 * t_val_0;
    float uv_0 = u_val_0 * u_val_0 + v_val_0 * v_val_0;
    float denom_0 = uv_0 - st_0 * st_0;
    float2 d_0;
    if((abs(denom_0)) > 1.00000001335143196e-10)
    {
        d_0 = n_0 * float2((s2_0 * (st_0 + sqrt(uv_0)) / denom_0)) ;
    }
    else
    {
        d_0 = n_0 * _S3 / viewport_0;
    }
    float2 d_1 = d_0 * float2(snailVertexDilationScale_0(subpixel_order_1)) ;
    float2 p_0 = pos_0 + d_1;
    (&r_0)->texcoord_0 = float2(_S5 + dot(d_1, float2(_S12, _S13)), _S7 + dot(d_1, float2(_S14, _S15)));
    (&r_0)->position_0 = (((float4(p_0, 0.0, 1.0)) * (mvp_0)));
    return r_0;
}

bool snailAhFinite_0(float v_0)
{
    bool _S19;
    if(!isnan(v_0))
    {
        _S19 = !isinf(v_0);
    }
    else
    {
        _S19 = false;
    }
    return _S19;
}

bool snailAhAffineScale_0(matrix<float,int(4),int(4)>  mvp_1, float2 viewport_1, float4 xform_1, float2 thread* scale_0)
{
    *scale_0 = float2(0.0, 0.0);
    bool _S20;
    if((abs(mvp_1[int(3)].x)) > 1.00000001168609742e-07)
    {
        _S20 = true;
    }
    else
    {
        _S20 = (abs(mvp_1[int(3)].y)) > 1.00000001168609742e-07;
    }
    if(_S20)
    {
        _S20 = true;
    }
    else
    {
        _S20 = !snailAhFinite_0(mvp_1[int(3)].w);
    }
    if(_S20)
    {
        _S20 = true;
    }
    else
    {
        _S20 = (abs(mvp_1[int(3)].w)) < 1.00000001335143196e-10;
    }
    if(_S20)
    {
        return false;
    }
    float2 localX_0 = float2(xform_1.x, xform_1.z);
    float2 localY_0 = float2(xform_1.y, xform_1.w);
    float2 _S21 = float2(0.5)  * viewport_1;
    float2 _S22 = mvp_1[int(0)].xy;
    float2 _S23 = mvp_1[int(1)].xy;
    float2 _S24 = float2(mvp_1[int(3)].w) ;
    float2 screenX_0 = _S21 * float2(dot(_S22, localX_0), dot(_S23, localX_0)) / _S24;
    float2 screenY_0 = _S21 * float2(dot(_S22, localY_0), dot(_S23, localY_0)) / _S24;
    float _S25 = screenX_0.x;
    float _S26 = screenY_0.y;
    float _S27 = screenY_0.x;
    float _S28 = screenX_0.y;
    float det_0 = _S25 * _S26 - _S27 * _S28;
    if(!snailAhFinite_0(det_0))
    {
        _S20 = true;
    }
    else
    {
        _S20 = (abs(det_0)) < 1.00000001335143196e-10;
    }
    if(_S20)
    {
        return false;
    }
    float _S29 = abs(det_0);
    float2 _S30 = float2(1.0)  / float2((abs(_S26) + abs(_S27)) / _S29, (abs(_S28) + abs(_S25)) / _S29);
    *scale_0 = _S30;
    if(snailAhFinite_0(_S30.x))
    {
        _S20 = snailAhFinite_0((*scale_0).y);
    }
    else
    {
        _S20 = false;
    }
    if(_S20)
    {
        _S20 = ((*scale_0).x) > 0.0;
    }
    else
    {
        _S20 = false;
    }
    if(_S20)
    {
        _S20 = ((*scale_0).y) > 0.0;
    }
    else
    {
        _S20 = false;
    }
    return _S20;
}

void snailAhMarkFallback_0(array<float4, int(4)> thread* packedTargets_0, uint4 thread* packedSources_0)
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
        (*packedTargets_0)[i_0] = float4(0.0) ;
        i_0 = i_0 + int(1);
    }
    uint4 _S31 = uint4(4294967295U) ;
    *packedSources_0 = _S31;
    (*packedSources_0).x = ((_S31.x) & 4294967040U) | 254U;
    return;
}

int2 snailAhLayerLoc_0(texture2d<float, access::sample> layer_tex_0, int2 base_0, int offset_0)
{
    thread uint uw_0;
    thread uint uh_0;
    (*((&uw_0)) = (layer_tex_0).get_width(0)),(*((&uh_0)) = (layer_tex_0).get_height(0));
    int width_0 = int(uw_0);
    int texel_0 = base_0.y * width_0 + base_0.x + offset_0;
    int _S32 = texel_0 % width_0;
    int _S33 = texel_0 / width_0;
    return int2(_S32, _S33);
}

float snailWarpF_0(texture2d<float, access::sample> layer_tex_1, int2 info_base_0, int block_0, int i_1)
{
    int f_0 = block_0 + i_1;
    int2 _S34 = snailAhLayerLoc_0(layer_tex_1, info_base_0, f_0 >> 2U);
    int3 _S35 = int3(_S34, int(0));
    float4 t_0 = ((layer_tex_1).read(vec<uint,2>(((_S35)).xy), uint(((_S35)).z)));
    int c_1 = f_0 & int(3);
    float _S36;
    if(c_1 == int(0))
    {
        _S36 = t_0.x;
    }
    else
    {
        if(c_1 == int(1))
        {
            _S36 = t_0.y;
        }
        else
        {
            if(c_1 == int(2))
            {
                _S36 = t_0.z;
            }
            else
            {
                _S36 = t_0.w;
            }
        }
    }
    return _S36;
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

bool snailDecodeAutohintPolicy_0(uint4 p0_0, uint3 p1_0, SnailAutohintPolicy_0 thread* p_1)
{
    p_1->xAlign_0 = int(0);
    p_1->xStem_0 = int(0);
    p_1->xPositioning_0 = int(0);
    p_1->xRegistration_0 = int(0);
    p_1->yAlign_0 = int(0);
    p_1->yStem_0 = int(0);
    p_1->yOvershoot_0 = int(0);
    p_1->fadeEnabled_0 = int(0);
    p_1->fadeStart_0 = 0.0;
    p_1->fadeFull_0 = 0.0;
    p_1->xRatio_0 = 0.0;
    p_1->xMaxPx_0 = 0.0;
    p_1->yRatio_0 = 0.0;
    p_1->yMaxPx_0 = 0.0;
    p_1->overshootMinPx_0 = 0.0;
    uint x_0 = p0_0.x;
    uint y_0 = p0_0.y;
    bool _S37;
    if((x_0 & 4286578688U) != 0U)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (y_0 & 4294967232U) != 0U;
    }
    if(_S37)
    {
        return false;
    }
    int _S38 = int(x_0 & 3U);
    p_1->xAlign_0 = _S38;
    p_1->xStem_0 = int((x_0 >> 2U) & 3U);
    p_1->xPositioning_0 = int((x_0 >> 4U) & 3U);
    p_1->xRegistration_0 = int((x_0 >> 6U) & 3U);
    p_1->fadeEnabled_0 = int((x_0 >> 8U) & 1U);
    p_1->fadeStart_0 = float((x_0 >> 9U) & 127U);
    p_1->fadeFull_0 = float((x_0 >> 16U) & 127U);
    p_1->yAlign_0 = int(y_0 & 3U);
    p_1->yStem_0 = int((y_0 >> 2U) & 3U);
    p_1->yOvershoot_0 = int((y_0 >> 4U) & 3U);
    if(_S38 > int(1))
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->xStem_0) > int(2);
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->xPositioning_0) > int(1);
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->xRegistration_0) > int(1);
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->yAlign_0) > int(2);
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->yStem_0) > int(2);
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        _S37 = (p_1->yOvershoot_0) > int(1);
    }
    if(_S37)
    {
        return false;
    }
    p_1->xRatio_0 = (as_type<float>((p0_0.z)));
    p_1->xMaxPx_0 = (as_type<float>((p0_0.w)));
    p_1->yRatio_0 = (as_type<float>((p1_0.x)));
    p_1->yMaxPx_0 = (as_type<float>((p1_0.y)));
    p_1->overshootMinPx_0 = (as_type<float>((p1_0.z)));
    if((p_1->xStem_0) != int(0))
    {
        if(!snailAhFinite_0(p_1->xRatio_0))
        {
            _S37 = true;
        }
        else
        {
            _S37 = (p_1->xRatio_0) < 0.0;
        }
    }
    else
    {
        _S37 = false;
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->xStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_1->xMaxPx_0))
            {
                _S37 = true;
            }
            else
            {
                _S37 = (p_1->xMaxPx_0) < 0.0;
            }
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->yStem_0) != int(0))
        {
            if(!snailAhFinite_0(p_1->yRatio_0))
            {
                _S37 = true;
            }
            else
            {
                _S37 = (p_1->yRatio_0) < 0.0;
            }
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->yStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_1->yMaxPx_0))
            {
                _S37 = true;
            }
            else
            {
                _S37 = (p_1->yMaxPx_0) < 0.0;
            }
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->yOvershoot_0) == int(1))
        {
            if(!snailAhFinite_0(p_1->overshootMinPx_0))
            {
                _S37 = true;
            }
            else
            {
                _S37 = (p_1->overshootMinPx_0) < 0.0;
            }
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->xPositioning_0) == int(1))
        {
            _S37 = (p_1->xAlign_0) == int(0);
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        _S37 = true;
    }
    else
    {
        if((p_1->yOvershoot_0) == int(1))
        {
            _S37 = (p_1->yAlign_0) != int(2);
        }
        else
        {
            _S37 = false;
        }
    }
    if(_S37)
    {
        return false;
    }
    return true;
}

bool snailAhCount_0(int max_knots_0, float encoded_0, int thread* count_0)
{
    bool _S39;
    if(!snailAhFinite_0(encoded_0))
    {
        _S39 = true;
    }
    else
    {
        _S39 = encoded_0 < 0.0;
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = encoded_0 > float(max_knots_0);
    }
    if(_S39)
    {
        _S39 = true;
    }
    else
    {
        _S39 = (floor(encoded_0)) != encoded_0;
    }
    if(_S39)
    {
        *count_0 = int(0);
        return false;
    }
    *count_0 = int(encoded_0);
    return true;
}

float snailAhSnap_0(float v_1, float scale_1)
{
    return round(v_1 * scale_1) / scale_1;
}

float snailAhStandardWidth_0(float raw_0, float standard_0, float ratio_0)
{
    bool _S40;
    if(standard_0 > 0.0)
    {
        _S40 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S40 = false;
    }
    float _S41;
    if(_S40)
    {
        _S41 = standard_0;
    }
    else
    {
        _S41 = raw_0;
    }
    return _S41;
}

bool snailFitAutohintAxis_0(texture2d<float, access::sample> layer_tex_2, int2 info_base_1, int axis_0, int run_0, int blueCount_0, float standardWidth_0, float left_0, float scale_2, const SnailAutohintPolicy_0 thread* policy_0, int thread* knotCount_0, array<float, int(16)> thread* knotBase_0, array<float, int(16)> thread* knotTarget_0, array<int, int(16)> thread* knotSource_0)
{
    *knotCount_0 = int(0);
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
        (*knotBase_0)[i_2] = 0.0;
        (*knotTarget_0)[i_2] = 0.0;
        (*knotSource_0)[i_2] = int(0);
        i_2 = i_2 + int(1);
    }
    bool _S42;
    if(!snailAhFinite_0(scale_2))
    {
        _S42 = true;
    }
    else
    {
        _S42 = scale_2 <= 0.0;
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        _S42 = blueCount_0 < int(0);
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        _S42 = blueCount_0 > int(16);
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        _S42 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        _S42 = standardWidth_0 < 0.0;
    }
    if(_S42)
    {
        return false;
    }
    bool _S43 = axis_0 == int(0);
    if(_S43)
    {
        _S42 = (policy_0->xAlign_0) == int(0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = (policy_0->xStem_0) == int(0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = (policy_0->xPositioning_0) == int(0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = (policy_0->xRegistration_0) == int(0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        if(axis_0 == int(1))
        {
            _S42 = (policy_0->yAlign_0) == int(0);
        }
        else
        {
            _S42 = false;
        }
        if(_S42)
        {
            _S42 = (policy_0->yStem_0) == int(0);
        }
        else
        {
            _S42 = false;
        }
        if(_S42)
        {
            _S42 = (policy_0->yOvershoot_0) == int(0);
        }
        else
        {
            _S42 = false;
        }
    }
    if(_S42)
    {
        return true;
    }
    float _S44 = snailWarpF_0(layer_tex_2, info_base_1, run_0, int(0));
    int n_1 = int(_S44);
    if(n_1 <= int(0))
    {
        _S42 = true;
    }
    else
    {
        _S42 = n_1 > int(16);
    }
    if(_S42)
    {
        return n_1 == int(0);
    }
    bool _S45 = axis_0 == int(1);
    if(_S45)
    {
        _S42 = (policy_0->yAlign_0) == int(2);
    }
    else
    {
        _S42 = false;
    }
    bool relative_0;
    if(_S43)
    {
        relative_0 = (policy_0->xRegistration_0) == int(1);
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
    bool _S46;
    bool upperBlue_0;
    bool lowerBlue_0;
    bool axisAligned_0;
    bool _S47;
    bool _S48;
    bool anchorSet_0;
    int clusterRight_0;
    int stemMode_0;
    thread array<float, int(16)> pos_1;
    thread array<float, int(16)> width_1;
    thread array<int, int(16)> stem_0;
    thread array<int, int(16)> blue_0;
    thread array<bool, int(16)> rounded_0;
    thread array<bool, int(16)> syntheticApex_0;
    thread array<int, int(16)> companion_0;
    thread array<int, int(16)> dir_0;
    thread array<float, int(16)> targets_0;
    thread array<bool, int(16)> hinted_0;
    thread array<bool, int(16)> knotBlueFixed_0;
    thread array<bool, int(16)> knotNaturalSpacing_0;
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
        float _S49 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(0));
        pos_1[i_2] = _S49;
        float _S50 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(1));
        width_1[i_2] = _S50;
        float _S51 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(2));
        uint refs_0 = (as_type<uint>((_S51)));
        stem_0[i_2] = int(refs_0 << 16U) >> 16U;
        blue_0[i_2] = int(refs_0) >> 16U;
        float _S52 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(3));
        uint flags_0 = (as_type<uint>((_S52)));
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
        uint _S53;
        if(_S42)
        {
            _S53 = 10U;
        }
        else
        {
            _S53 = 4U;
        }
        int encodedCompanion_0 = int((flags_0 >> _S53) & 63U);
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
            _S48 = true;
        }
        else
        {
            _S48 = !snailAhFinite_0(width_1[i_2]);
        }
        if(_S48)
        {
            _S47 = true;
        }
        else
        {
            _S47 = (width_1[i_2]) < 0.0;
        }
        if(_S47)
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
            _S46 = true;
        }
        else
        {
            _S46 = (blue_0[i_2]) >= blueCount_0;
        }
        if(_S46)
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
        int _S54 = int(2) * i_2;
        float ref_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S54);
        float shoot_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S54 + int(1));
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
    if(_S45)
    {
        relative_0 = (policy_0->yOvershoot_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    float spacing_0;
    if(relative_0)
    {
        spacing_0 = policy_0->overshootMinPx_0;
    }
    else
    {
        spacing_0 = 0.0;
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
            relative_0 = (pos_1[stem_0[i_2]]) > pos_1[i_2];
        }
        else
        {
            relative_0 = false;
        }
        if(_S42)
        {
            anchorSet_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(!_S42)
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
                _S48 = _S45;
            }
            else
            {
                _S48 = false;
            }
            if(_S48)
            {
                _S47 = (policy_0->yOvershoot_0) == int(0);
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
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
    float grid_0 = 1.0 / scale_2;
    if(_S43)
    {
        stemMode_0 = policy_0->xStem_0;
    }
    else
    {
        stemMode_0 = policy_0->yStem_0;
    }
    if(_S43)
    {
        spacing_0 = policy_0->xRatio_0;
    }
    else
    {
        spacing_0 = policy_0->yRatio_0;
    }
    float maxPx_0;
    if(_S43)
    {
        maxPx_0 = policy_0->xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0->yMaxPx_0;
    }
    if(_S43)
    {
        _S42 = (policy_0->xAlign_0) == int(1);
    }
    else
    {
        _S42 = (policy_0->yAlign_0) != int(0);
    }
    if(_S43)
    {
        relative_0 = (policy_0->xPositioning_0) == int(1);
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
    float anchorTarget_0 = 0.0;
    float anchorBase_0 = 0.0;
    float clusterTarget_0 = 0.0;
    float clusterBase_0 = 0.0;
    float clusterDesiredRight_0 = 0.0;
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
            _S48 = true;
        }
        else
        {
            _S48 = j_1 <= i_2;
        }
        if(_S48)
        {
            axisAligned_0 = anchorSet_0;
            int i_3 = i_2 + int(1);
            anchorSet_0 = axisAligned_0;
            i_2 = i_3;
            continue;
        }
        float nominal_0 = snailAhStandardWidth_0(width_1[i_2], standardWidth_0, spacing_0);
        float _S55 = width_1[i_2];
        if(stemMode_0 == int(2))
        {
            _S47 = true;
        }
        else
        {
            if(stemMode_0 == int(1))
            {
                _S47 = (nominal_0 * scale_2) < maxPx_0;
            }
            else
            {
                _S47 = false;
            }
        }
        if(_S47)
        {
            bestGap_0 = max(round(nominal_0 * scale_2), 1.0) * grid_0;
        }
        else
        {
            bestGap_0 = _S55;
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
                float _S56 = snailAhSnap_0(pos_1[i_2], scale_2);
                targets_0[i_2] = _S56;
                widthUnits_0 = _S56;
                anchorBase_1 = pos_1[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_1] = targets_0[i_2] + bestGap_0;
            float _S57 = widthUnits_0 + round((pos_1[i_2] - anchorBase_1) * scale_2) * grid_0 + bestGap_0;
            int clusterStems_1 = clusterStems_0 + int(1);
            float _S58 = widthUnits_0;
            float _S59 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_1[i_2];
            clusterTarget_1 = _S58;
            clusterBase_1 = _S59;
            clusterDesiredRight_1 = _S57;
            b_0 = j_1;
            j_0 = clusterStems_1;
        }
        else
        {
            if(_S43)
            {
                axisAligned_0 = (policy_0->xAlign_0) != int(0);
            }
            else
            {
                axisAligned_0 = (policy_0->yAlign_0) != int(0);
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
            if(!_S42)
            {
                targets_0[i_2] = pos_1[i_2];
            }
            if(upperBlue_0)
            {
                _S46 = !lowerBlue_0;
            }
            else
            {
                _S46 = false;
            }
            bool _S60;
            if(_S46)
            {
                _S60 = _S42;
            }
            else
            {
                _S60 = false;
            }
            if(_S60)
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
        _S42 = clusterStems_0 > int(1);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        float _S61 = clusterDesiredRight_0 - targets_0[clusterRight_0];
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
                targets_0[i_2] = targets_0[i_2] + _S61;
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
        spacing_0 = 1.60000002384185791;
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
        if(_S43)
        {
            axisAligned_0 = (policy_0->xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0->yAlign_0) != int(0);
        }
        if(!axisAligned_0)
        {
            _S42 = true;
        }
        else
        {
            _S42 = (blue_0[i_2]) < int(0);
        }
        if(_S42)
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
                bestGap_0 = 3.4028234663852886e+38;
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
                        _S48 = true;
                    }
                    else
                    {
                        _S48 = (dir_0[j_0]) == dir_0[i_2];
                    }
                    if(_S48)
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
                    if(widthUnits_0 <= 0.0)
                    {
                        _S47 = true;
                    }
                    else
                    {
                        _S47 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S47)
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
                bestGap_0 = 3.4028234663852886e+38;
            }
        }
        if(b_0 < int(0))
        {
            _S48 = true;
        }
        else
        {
            _S48 = hinted_0[b_0];
        }
        if(_S48)
        {
            _S47 = true;
        }
        else
        {
            _S47 = (blue_0[b_0]) >= int(0);
        }
        if(_S47)
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
            widthUnits_0 = max(round(bestGap_0 * scale_2), 1.0) * grid_0;
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
        if(_S43)
        {
            axisAligned_0 = (policy_0->xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0->yAlign_0) != int(0);
        }
        if(!hinted_0[i_2])
        {
            if(axisAligned_0)
            {
                _S42 = (blue_0[i_2]) >= int(0);
            }
            else
            {
                _S42 = false;
            }
            _S42 = !_S42;
        }
        else
        {
            _S42 = false;
        }
        if(_S42)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        (*knotBase_0)[*knotCount_0] = pos_1[i_2];
        (*knotTarget_0)[*knotCount_0] = targets_0[i_2];
        if(axisAligned_0)
        {
            relative_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            relative_0 = false;
        }
        knotBlueFixed_0[*knotCount_0] = relative_0;
        knotNaturalSpacing_0[*knotCount_0] = syntheticApex_0[i_2];
        (*knotSource_0)[*knotCount_0] = i_2;
        *knotCount_0 = *knotCount_0 + int(1);
        i_2 = i_2 + int(1);
    }
    if(_S43)
    {
        _S42 = (policy_0->xRegistration_0) == int(1);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = (*knotCount_0) > int(0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = (*knotCount_0) < int(16);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = left_0 < ((*knotBase_0)[int(0)] - 0.25 * grid_0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
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
            if(i_2 <= (*knotCount_0))
            {
                int _S62 = i_2 - int(1);
                (*knotBase_0)[i_2] = (*knotBase_0)[_S62];
                (*knotTarget_0)[i_2] = (*knotTarget_0)[_S62];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S62];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S62];
                (*knotSource_0)[i_2] = (*knotSource_0)[_S62];
            }
            i_2 = i_2 - int(1);
        }
        (*knotBase_0)[int(0)] = left_0;
        (*knotTarget_0)[int(0)] = snailAhSnap_0(left_0, scale_2);
        knotBlueFixed_0[int(0)] = false;
        knotNaturalSpacing_0[int(0)] = false;
        (*knotSource_0)[int(0)] = int(32);
        *knotCount_0 = *knotCount_0 + int(1);
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
        if(b_0 >= (*knotCount_0))
        {
            _S42 = true;
        }
        else
        {
            _S42 = !knotBlueFixed_0[b_0];
        }
        if(_S42)
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
            int _S63 = j_0 - int(1);
            if(knotBlueFixed_0[_S63])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S63])
            {
                spacing_0 = 9.99999997475242708e-07;
            }
            else
            {
                spacing_0 = grid_0;
            }
            (*knotTarget_0)[_S63] = min((*knotTarget_0)[_S63], (*knotTarget_0)[j_0] - spacing_0);
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
        if(i_2 >= (*knotCount_0))
        {
            break;
        }
        if(((*knotTarget_0)[i_2]) <= (*knotTarget_0)[i_2 - int(1)])
        {
            (*knotTarget_0)[i_2] = (*knotTarget_0)[i_2 - int(1)] + grid_0;
        }
        i_2 = i_2 + int(1);
    }
    if((policy_0->fadeEnabled_0) != int(0))
    {
        _S42 = scale_2 > (policy_0->fadeStart_0);
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        float _S64 = policy_0->fadeFull_0;
        float _S65 = policy_0->fadeStart_0;
        float span_0 = policy_0->fadeFull_0 - policy_0->fadeStart_0;
        if(span_0 <= 0.0)
        {
            _S42 = true;
        }
        else
        {
            _S42 = scale_2 >= _S64;
        }
        if(_S42)
        {
            spacing_0 = 1.0;
        }
        else
        {
            spacing_0 = (scale_2 - _S65) / span_0;
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
            if(i_2 >= (*knotCount_0))
            {
                break;
            }
            (*knotTarget_0)[i_2] = (*knotTarget_0)[i_2] + ((*knotBase_0)[i_2] - (*knotTarget_0)[i_2]) * spacing_0;
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
        if(i_2 >= (*knotCount_0))
        {
            break;
        }
        if(!snailAhFinite_0((*knotBase_0)[i_2]))
        {
            _S42 = true;
        }
        else
        {
            _S42 = !snailAhFinite_0((*knotTarget_0)[i_2]);
        }
        if(_S42)
        {
            *knotCount_0 = int(0);
            return false;
        }
        i_2 = i_2 + int(1);
    }
    return true;
}

void snailAhPackAxis_0(int count_1, const array<float, int(16)> thread* targets_1, const array<int, int(16)> thread* sources_0, array<float4, int(4)> thread* packedTargets_1, uint4 thread* packedSources_1)
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
        (*packedTargets_1)[i_4] = float4(0.0) ;
        i_4 = i_4 + int(1);
    }
    *packedSources_1 = uint4(4294967295U) ;
    if(count_1 > int(16))
    {
        (*packedSources_1).x = (((*packedSources_1).x) & 4294967040U) | 254U;
        return;
    }
    i_4 = int(0);
    for(;;)
    {
        if(i_4 < int(16))
        {
        }
        else
        {
            break;
        }
        if(i_4 >= count_1)
        {
            break;
        }
        int _S66 = i_4 >> 2U;
        int _S67 = i_4 & int(3);
        (*packedTargets_1)[_S66][_S67] = (*targets_1)[i_4];
        uint _S68 = uint(_S67 * int(8));
        (*packedSources_1)[_S66] = (((*packedSources_1)[_S66]) & (~(255U << _S68))) | ((uint((*sources_0)[i_4]) & 255U) << _S68);
        i_4 = i_4 + int(1);
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
    array<float4, int(4)> x_targets_0;
    array<float4, int(4)> y_targets_0;
    uint4 x_sources_0;
    uint4 y_sources_0;
};

AutohintVertexResult_0 snailAutohintVertex_0(const TextVertexIn_0 thread* input_1, uint vertex_index_1, matrix<float,int(4),int(4)>  mvp_2, float2 viewport_2, int subpixel_order_2, uint4 policy0_1, uint3 policy1_1, texture2d<float, access::sample> layer_tex_3)
{
    TextVertexResult_0 _S69 = snailTextVertex_0(input_1, vertex_index_1, mvp_2, viewport_2, subpixel_order_2);
    thread AutohintVertexResult_0 r_1;
    (&r_1)->position_1 = _S69.position_0;
    (&r_1)->paint_0 = _S69.color_1 * _S69.tint_0;
    (&r_1)->texcoord_layer_0 = float3(_S69.texcoord_0, input_1->bnd_0.w);
    uint gz_1 = input_1->glyph_1.x;
    (&r_1)->info_0 = int2(int(gz_1 & 65535U), int(gz_1 >> 16U));
    (&r_1)->policy0_0 = policy0_1;
    (&r_1)->policy1_0 = policy1_1;
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
            float4 _S70 = float4(0.0) ;
            (&r_1)->x_targets_0[i_5] = _S70;
            (&r_1)->y_targets_0[i_5] = _S70;
            i_5 = i_5 + int(1);
        }
        uint4 _S71 = uint4(4294967295U) ;
        (&r_1)->x_sources_0 = _S71;
        (&r_1)->y_sources_0 = _S71;
        return r_1;
    }
    int2 info_base_2 = (&r_1)->info_0;
    thread float2 scale_3;
    bool _S72 = snailAhAffineScale_0(mvp_2, viewport_2, input_1->xform_0, &scale_3);
    if(!_S72)
    {
        snailAhMarkFallback_0(&(&r_1)->x_targets_0, &(&r_1)->x_sources_0);
        snailAhMarkFallback_0(&(&r_1)->y_targets_0, &(&r_1)->y_sources_0);
        return r_1;
    }
    thread int blueCount_1 = int(0);
    thread int featureXCount_0 = int(0);
    thread int featureYCount_0 = int(0);
    float stdX_0 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(8));
    float stdY_0 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(9));
    thread SnailAutohintPolicy_0 policy_1;
    bool _S73 = snailDecodeAutohintPolicy_0(policy0_1, policy1_1, &policy_1);
    bool valid_0;
    if(_S73)
    {
        valid_0 = snailAhFinite_0(stdX_0);
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        valid_0 = stdX_0 >= 0.0;
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
        valid_0 = stdY_0 >= 0.0;
    }
    else
    {
        valid_0 = false;
    }
    if(valid_0)
    {
        float _S74 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(10));
        bool _S75 = snailAhCount_0(int(16), _S74, &blueCount_1);
        valid_0 = _S75;
    }
    else
    {
        valid_0 = false;
    }
    int xRun_0 = int(12) + int(2) * blueCount_1;
    if(valid_0)
    {
        float _S76 = snailWarpF_0(layer_tex_3, info_base_2, xRun_0, int(0));
        bool _S77 = snailAhCount_0(int(16), _S76, &featureXCount_0);
        valid_0 = _S77;
    }
    else
    {
        valid_0 = false;
    }
    int yRun_0 = xRun_0 + int(1) + int(4) * featureXCount_0;
    if(valid_0)
    {
        float _S78 = snailWarpF_0(layer_tex_3, info_base_2, yRun_0, int(0));
        valid_0 = snailAhCount_0(int(16), _S78, &featureYCount_0);
    }
    else
    {
        valid_0 = false;
    }
    if(!valid_0)
    {
        snailAhMarkFallback_0(&(&r_1)->x_targets_0, &(&r_1)->x_sources_0);
        snailAhMarkFallback_0(&(&r_1)->y_targets_0, &(&r_1)->y_sources_0);
        return r_1;
    }
    thread int xCount_0 = int(0);
    thread int yCount_0 = int(0);
    float _S79 = snailWarpF_0(layer_tex_3, info_base_2, int(0), int(11));
    float _S80 = scale_3.x;
    thread SnailAutohintPolicy_0 _S81 = policy_1;
    thread array<float, int(16)> xBase_0;
    thread array<float, int(16)> xTarget_0;
    thread array<int, int(16)> xSource_0;
    bool _S82 = snailFitAutohintAxis_0(layer_tex_3, info_base_2, int(0), xRun_0, blueCount_1, stdX_0, _S79, _S80, &_S81, &xCount_0, &xBase_0, &xTarget_0, &xSource_0);
    float _S83 = scale_3.y;
    thread SnailAutohintPolicy_0 _S84 = policy_1;
    thread array<float, int(16)> yBase_0;
    thread array<float, int(16)> yTarget_0;
    thread array<int, int(16)> ySource_0;
    bool _S85 = snailFitAutohintAxis_0(layer_tex_3, info_base_2, int(1), yRun_0, blueCount_1, stdY_0, 0.0, _S83, &_S84, &yCount_0, &yBase_0, &yTarget_0, &ySource_0);
    if(_S82)
    {
        thread array<float, int(16)> _S86 = xTarget_0;
        thread array<int, int(16)> _S87 = xSource_0;
        snailAhPackAxis_0(xCount_0, &_S86, &_S87, &(&r_1)->x_targets_0, &(&r_1)->x_sources_0);
    }
    else
    {
        snailAhMarkFallback_0(&(&r_1)->x_targets_0, &(&r_1)->x_sources_0);
    }
    if(_S85)
    {
        thread array<float, int(16)> _S88 = yTarget_0;
        thread array<int, int(16)> _S89 = ySource_0;
        snailAhPackAxis_0(yCount_0, &_S88, &_S89, &(&r_1)->y_targets_0, &(&r_1)->y_sources_0);
    }
    else
    {
        snailAhMarkFallback_0(&(&r_1)->y_targets_0, &(&r_1)->y_sources_0);
    }
    return r_1;
}

struct VsOutput_0
{
    float4 position_2;
    float4 paint_1;
    float3 texcoord_layer_1;
    [[flat]] int2 info_1;
    [[flat]] uint4 policy0_2;
    [[flat]] uint3 policy1_2;
    [[flat]] float4 x_targets0_0;
    [[flat]] float4 x_targets1_0;
    [[flat]] float4 x_targets2_0;
    [[flat]] float4 x_targets3_0;
    [[flat]] float4 y_targets0_0;
    [[flat]] float4 y_targets1_0;
    [[flat]] float4 y_targets2_0;
    [[flat]] float4 y_targets3_0;
    [[flat]] uint4 x_sources_1;
    [[flat]] uint4 y_sources_1;
};

struct VsInput_0
{
    float4 rect_1;
    float4 xform_2;
    float2 origin_1;
    uint2 glyph_2;
    float4 bnd_1;
    float4 col_1;
    float4 tint_2;
    uint4 policy0_3;
    uint3 policy1_3;
};

struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};

struct SnailPushConstants_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 mvp_3;
    float2 viewport_3;
    int subpixel_order_3;
    int output_srgb_0;
    int layer_base_0;
    float coverage_exponent_0;
    float dither_scale_0;
    int mask_output_0;
};

struct KernelContext_0
{
    SnailPushConstants_natural_0 constant* pc_0;
    texture2d<float, access::sample> u_layer_tex_0;
};

VsOutput_0 vertexBody_0(const VsInput_0 thread* input_2, uint vertex_index_2, KernelContext_0 thread* kernelContext_0)
{
    thread TextVertexIn_0 v_2;
    (&v_2)->rect_0 = input_2->rect_1;
    (&v_2)->xform_0 = input_2->xform_2;
    (&v_2)->origin_0 = input_2->origin_1;
    (&v_2)->glyph_1 = input_2->glyph_2;
    (&v_2)->bnd_0 = input_2->bnd_1;
    (&v_2)->col_0 = input_2->col_1;
    (&v_2)->tint_1 = input_2->tint_2;
    matrix<float,int(4),int(4)>  _S90 = matrix<float,int(4),int(4)> (kernelContext_0->pc_0->mvp_3.data_0[int(0)][int(0)], kernelContext_0->pc_0->mvp_3.data_0[int(1)][int(0)], kernelContext_0->pc_0->mvp_3.data_0[int(2)][int(0)], kernelContext_0->pc_0->mvp_3.data_0[int(3)][int(0)], kernelContext_0->pc_0->mvp_3.data_0[int(0)][int(1)], kernelContext_0->pc_0->mvp_3.data_0[int(1)][int(1)], kernelContext_0->pc_0->mvp_3.data_0[int(2)][int(1)], kernelContext_0->pc_0->mvp_3.data_0[int(3)][int(1)], kernelContext_0->pc_0->mvp_3.data_0[int(0)][int(2)], kernelContext_0->pc_0->mvp_3.data_0[int(1)][int(2)], kernelContext_0->pc_0->mvp_3.data_0[int(2)][int(2)], kernelContext_0->pc_0->mvp_3.data_0[int(3)][int(2)], kernelContext_0->pc_0->mvp_3.data_0[int(0)][int(3)], kernelContext_0->pc_0->mvp_3.data_0[int(1)][int(3)], kernelContext_0->pc_0->mvp_3.data_0[int(2)][int(3)], kernelContext_0->pc_0->mvp_3.data_0[int(3)][int(3)]);
    float2 _S91 = kernelContext_0->pc_0->viewport_3;
    int _S92 = kernelContext_0->pc_0->subpixel_order_3;
    thread TextVertexIn_0 _S93 = v_2;
    AutohintVertexResult_0 _S94 = snailAutohintVertex_0(&_S93, vertex_index_2, _S90, _S91, _S92, input_2->policy0_3, input_2->policy1_3, kernelContext_0->u_layer_tex_0);
    thread VsOutput_0 o_0;
    (&o_0)->position_2 = _S94.position_1;
    (&o_0)->paint_1 = _S94.paint_0;
    (&o_0)->texcoord_layer_1 = _S94.texcoord_layer_0;
    (&o_0)->info_1 = _S94.info_0;
    (&o_0)->policy0_2 = _S94.policy0_0;
    (&o_0)->policy1_2 = _S94.policy1_0;
    (&o_0)->x_targets0_0 = _S94.x_targets_0[int(0)];
    (&o_0)->x_targets1_0 = _S94.x_targets_0[int(1)];
    (&o_0)->x_targets2_0 = _S94.x_targets_0[int(2)];
    (&o_0)->x_targets3_0 = _S94.x_targets_0[int(3)];
    (&o_0)->y_targets0_0 = _S94.y_targets_0[int(0)];
    (&o_0)->y_targets1_0 = _S94.y_targets_0[int(1)];
    (&o_0)->y_targets2_0 = _S94.y_targets_0[int(2)];
    (&o_0)->y_targets3_0 = _S94.y_targets_0[int(3)];
    (&o_0)->x_sources_1 = _S94.x_sources_0;
    (&o_0)->y_sources_1 = _S94.y_sources_0;
    return o_0;
}

struct vertexMain_Result_0
{
    float4 position_3 [[position]];
    float4 paint_2 [[user(TEXCOORD)]];
    float3 texcoord_layer_2 [[user(TEXCOORD_1)]];
    int2 info_2 [[user(TEXCOORD_2)]];
    uint4 policy0_4 [[user(TEXCOORD_3)]];
    uint3 policy1_4 [[user(TEXCOORD_4)]];
    float4 x_targets0_1 [[user(TEXCOORD_5)]];
    float4 x_targets1_1 [[user(TEXCOORD_6)]];
    float4 x_targets2_1 [[user(TEXCOORD_7)]];
    float4 x_targets3_1 [[user(TEXCOORD_8)]];
    float4 y_targets0_1 [[user(TEXCOORD_9)]];
    float4 y_targets1_1 [[user(TEXCOORD_10)]];
    float4 y_targets2_1 [[user(TEXCOORD_11)]];
    float4 y_targets3_1 [[user(TEXCOORD_12)]];
    uint4 x_sources_2 [[user(TEXCOORD_13)]];
    uint4 y_sources_2 [[user(TEXCOORD_14)]];
};

struct vertexInput_0
{
    float4 rect_2 [[attribute(0)]];
    float4 xform_3 [[attribute(1)]];
    float2 origin_2 [[attribute(2)]];
    uint2 glyph_3 [[attribute(3)]];
    float4 bnd_2 [[attribute(4)]];
    float4 col_2 [[attribute(5)]];
    float4 tint_3 [[attribute(6)]];
    uint4 policy0_5 [[attribute(7)]];
    uint3 policy1_5 [[attribute(8)]];
};

[[vertex]] vertexMain_Result_0 vertexMain(vertexInput_0 _S95 [[stage_in]], uint vertex_index_3 [[vertex_id]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d<float, access::sample> u_layer_tex_1 [[texture(2)]])
{
    thread KernelContext_0 kernelContext_1;
    (&kernelContext_1)->pc_0 = pc_1;
    (&kernelContext_1)->u_layer_tex_0 = u_layer_tex_1;
    thread VsInput_0 _S96;
    (&_S96)->rect_1 = _S95.rect_2;
    (&_S96)->xform_2 = _S95.xform_3;
    (&_S96)->origin_1 = _S95.origin_2;
    (&_S96)->glyph_2 = _S95.glyph_3;
    (&_S96)->bnd_1 = _S95.bnd_2;
    (&_S96)->col_1 = _S95.col_2;
    (&_S96)->tint_2 = _S95.tint_3;
    (&_S96)->policy0_3 = _S95.policy0_5;
    (&_S96)->policy1_3 = _S95.policy1_5;
    VsOutput_0 _S97 = vertexBody_0(&_S96, vertex_index_3, &kernelContext_1);
    thread VsOutput_0 o_1 = _S97;
    (&o_1)->position_2.y = - (&o_1)->position_2.y;
    thread vertexMain_Result_0 _S98;
    (&_S98)->position_3 = o_1.position_2;
    (&_S98)->paint_2 = o_1.paint_1;
    (&_S98)->texcoord_layer_2 = o_1.texcoord_layer_1;
    (&_S98)->info_2 = o_1.info_1;
    (&_S98)->policy0_4 = o_1.policy0_2;
    (&_S98)->policy1_4 = o_1.policy1_2;
    (&_S98)->x_targets0_1 = o_1.x_targets0_0;
    (&_S98)->x_targets1_1 = o_1.x_targets1_0;
    (&_S98)->x_targets2_1 = o_1.x_targets2_0;
    (&_S98)->x_targets3_1 = o_1.x_targets3_0;
    (&_S98)->y_targets0_1 = o_1.y_targets0_0;
    (&_S98)->y_targets1_1 = o_1.y_targets1_0;
    (&_S98)->y_targets2_1 = o_1.y_targets2_0;
    (&_S98)->y_targets3_1 = o_1.y_targets3_0;
    (&_S98)->x_sources_2 = o_1.x_sources_1;
    (&_S98)->y_sources_2 = o_1.y_sources_1;
    return _S98;
}

