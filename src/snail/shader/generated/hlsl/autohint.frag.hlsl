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

int2 snailAhLayerLoc_0(Texture2D<float4 > layer_tex_0, int2 base_0, int offset_0)
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

float snailWarpF_0(Texture2D<float4 > layer_tex_1, int2 info_base_0, int block_0, int i_0)
{
    int f_0 = block_0 + i_0;
    int2 _S3 = snailAhLayerLoc_0(layer_tex_1, info_base_0, f_0 >> int(2));
    float4 t_0 = layer_tex_1.Load(int3(_S3, int(0)));
    int c_0 = f_0 & int(3);
    float _S4;
    if(c_0 == int(0))
    {
        _S4 = t_0.x;
    }
    else
    {
        if(c_0 == int(1))
        {
            _S4 = t_0.y;
        }
        else
        {
            if(c_0 == int(2))
            {
                _S4 = t_0.z;
            }
            else
            {
                _S4 = t_0.w;
            }
        }
    }
    return _S4;
}

bool snailAhFinite_0(float v_0)
{
    return (abs(v_0)) <= 3.40282306073709653e+38f;
}

bool snailAhCount_0(int max_knots_0, float encoded_0, out int count_0)
{
    bool _S5;
    if(!snailAhFinite_0(encoded_0))
    {
        _S5 = true;
    }
    else
    {
        _S5 = encoded_0 < 0.0f;
    }
    if(_S5)
    {
        _S5 = true;
    }
    else
    {
        _S5 = encoded_0 > float(max_knots_0);
    }
    if(_S5)
    {
        _S5 = true;
    }
    else
    {
        _S5 = (floor(encoded_0)) != encoded_0;
    }
    if(_S5)
    {
        count_0 = int(0);
        return false;
    }
    count_0 = int(encoded_0);
    return true;
}

uint snailAhFastSource_0(uint4 words_0, int idx_0)
{
    return ((words_0[idx_0 >> int(2)]) >> uint((idx_0 & int(3)) * int(8))) & 255U;
}

int snailAhFastCount_0(uint4 words_1)
{
    if((snailAhFastSource_0(words_1, int(0))) == 254U)
    {
        return int(-1);
    }
    int i_1 = int(0);
    int count_1 = int(0);
    for(;;)
    {
        if(i_1 < int(16))
        {
        }
        else
        {
            break;
        }
        if((snailAhFastSource_0(words_1, i_1)) == 255U)
        {
            break;
        }
        int count_2 = count_1 + int(1);
        i_1 = i_1 + int(1);
        count_1 = count_2;
    }
    return count_1;
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

bool snailDecodeAutohintPolicy_0(uint4 p0_0, uint3 p1_0, out SnailAutohintPolicy_0 p_0)
{
    p_0.xAlign_0 = int(0);
    p_0.xStem_0 = int(0);
    p_0.xPositioning_0 = int(0);
    p_0.xRegistration_0 = int(0);
    p_0.yAlign_0 = int(0);
    p_0.yStem_0 = int(0);
    p_0.yOvershoot_0 = int(0);
    p_0.fadeEnabled_0 = int(0);
    p_0.fadeStart_0 = 0.0f;
    p_0.fadeFull_0 = 0.0f;
    p_0.xRatio_0 = 0.0f;
    p_0.xMaxPx_0 = 0.0f;
    p_0.yRatio_0 = 0.0f;
    p_0.yMaxPx_0 = 0.0f;
    p_0.overshootMinPx_0 = 0.0f;
    uint x_0 = p0_0.x;
    uint y_0 = p0_0.y;
    bool _S6;
    if((x_0 & 4286578688U) != 0U)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (y_0 & 4294967232U) != 0U;
    }
    if(_S6)
    {
        return false;
    }
    int _S7 = int(x_0 & 3U);
    p_0.xAlign_0 = _S7;
    p_0.xStem_0 = int((x_0 >> 2U) & 3U);
    p_0.xPositioning_0 = int((x_0 >> 4U) & 3U);
    p_0.xRegistration_0 = int((x_0 >> 6U) & 3U);
    p_0.fadeEnabled_0 = int((x_0 >> 8U) & 1U);
    p_0.fadeStart_0 = float((x_0 >> 9U) & 127U);
    p_0.fadeFull_0 = float((x_0 >> 16U) & 127U);
    p_0.yAlign_0 = int(y_0 & 3U);
    p_0.yStem_0 = int((y_0 >> 2U) & 3U);
    p_0.yOvershoot_0 = int((y_0 >> 4U) & 3U);
    if(_S7 > int(1))
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.xStem_0) > int(2);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.xPositioning_0) > int(1);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.xRegistration_0) > int(1);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.yAlign_0) > int(2);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.yStem_0) > int(2);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (p_0.yOvershoot_0) > int(1);
    }
    if(_S6)
    {
        return false;
    }
    p_0.xRatio_0 = asfloat(p0_0.z);
    p_0.xMaxPx_0 = asfloat(p0_0.w);
    p_0.yRatio_0 = asfloat(p1_0.x);
    p_0.yMaxPx_0 = asfloat(p1_0.y);
    p_0.overshootMinPx_0 = asfloat(p1_0.z);
    if((p_0.xStem_0) != int(0))
    {
        if(!snailAhFinite_0(p_0.xRatio_0))
        {
            _S6 = true;
        }
        else
        {
            _S6 = (p_0.xRatio_0) < 0.0f;
        }
    }
    else
    {
        _S6 = false;
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.xStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_0.xMaxPx_0))
            {
                _S6 = true;
            }
            else
            {
                _S6 = (p_0.xMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.yStem_0) != int(0))
        {
            if(!snailAhFinite_0(p_0.yRatio_0))
            {
                _S6 = true;
            }
            else
            {
                _S6 = (p_0.yRatio_0) < 0.0f;
            }
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.yStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_0.yMaxPx_0))
            {
                _S6 = true;
            }
            else
            {
                _S6 = (p_0.yMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.yOvershoot_0) == int(1))
        {
            if(!snailAhFinite_0(p_0.overshootMinPx_0))
            {
                _S6 = true;
            }
            else
            {
                _S6 = (p_0.overshootMinPx_0) < 0.0f;
            }
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.xPositioning_0) == int(1))
        {
            _S6 = (p_0.xAlign_0) == int(0);
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        if((p_0.yOvershoot_0) == int(1))
        {
            _S6 = (p_0.yAlign_0) != int(2);
        }
        else
        {
            _S6 = false;
        }
    }
    if(_S6)
    {
        return false;
    }
    return true;
}

float snailAhSnap_0(float v_1, float scale_0)
{
    return round(v_1 * scale_0) / scale_0;
}

float snailAhStandardWidth_0(float raw_0, float standard_0, float ratio_0)
{
    bool _S8;
    if(standard_0 > 0.0f)
    {
        _S8 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S8 = false;
    }
    float _S9;
    if(_S8)
    {
        _S9 = standard_0;
    }
    else
    {
        _S9 = raw_0;
    }
    return _S9;
}

bool snailFitAutohintAxis_0(Texture2D<float4 > layer_tex_2, int2 info_base_1, int axis_0, int run_0, int blueCount_0, float standardWidth_0, float left_0, float scale_1, SnailAutohintPolicy_0 policy_0, out int knotCount_0, out float  knotBase_0[int(32)], out float  knotTarget_0[int(32)], out int  knotSource_0[int(32)])
{
    knotCount_0 = int(0);
    int i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
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
    bool _S10;
    if(!snailAhFinite_0(scale_1))
    {
        _S10 = true;
    }
    else
    {
        _S10 = scale_1 <= 0.0f;
    }
    if(_S10)
    {
        _S10 = true;
    }
    else
    {
        _S10 = blueCount_0 < int(0);
    }
    if(_S10)
    {
        _S10 = true;
    }
    else
    {
        _S10 = blueCount_0 > int(32);
    }
    if(_S10)
    {
        _S10 = true;
    }
    else
    {
        _S10 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S10)
    {
        _S10 = true;
    }
    else
    {
        _S10 = standardWidth_0 < 0.0f;
    }
    if(_S10)
    {
        return false;
    }
    bool _S11 = axis_0 == int(0);
    if(_S11)
    {
        _S10 = (policy_0.xAlign_0) == int(0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = (policy_0.xStem_0) == int(0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = (policy_0.xPositioning_0) == int(0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = (policy_0.xRegistration_0) == int(0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = true;
    }
    else
    {
        if(axis_0 == int(1))
        {
            _S10 = (policy_0.yAlign_0) == int(0);
        }
        else
        {
            _S10 = false;
        }
        if(_S10)
        {
            _S10 = (policy_0.yStem_0) == int(0);
        }
        else
        {
            _S10 = false;
        }
        if(_S10)
        {
            _S10 = (policy_0.yOvershoot_0) == int(0);
        }
        else
        {
            _S10 = false;
        }
    }
    if(_S10)
    {
        return true;
    }
    float _S12 = snailWarpF_0(layer_tex_2, info_base_1, run_0, int(0));
    int n_0 = int(_S12);
    if(n_0 <= int(0))
    {
        _S10 = true;
    }
    else
    {
        _S10 = n_0 > int(32);
    }
    if(_S10)
    {
        return n_0 == int(0);
    }
    bool _S13 = axis_0 == int(1);
    if(_S13)
    {
        _S10 = (policy_0.yAlign_0) == int(2);
    }
    else
    {
        _S10 = false;
    }
    bool relative_0;
    if(_S11)
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
    bool lowerBlue_0;
    bool axisAligned_0;
    bool _S14;
    bool bottomBlue_0;
    bool anchorSet_0;
    float  pos_0[int(32)];
    float  width_1[int(32)];
    int  stem_0[int(32)];
    int  blue_0[int(32)];
    bool  rounded_0[int(32)];
    bool  syntheticApex_0[int(32)];
    int  companion_0[int(32)];
    bool  semanticsResolved_0[int(32)];
    bool  blueDirNegative_0[int(32)];
    int  gridCompanion_0[int(32)];
    int  blueCompanion_0[int(32)];
    int  dir_0[int(32)];
    float  targets_0[int(32)];
    bool  hinted_0[int(32)];
    bool  knotBlueFixed_0[int(32)];
    bool  knotNaturalSpacing_0[int(32)];
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        int f_1 = run_0 + int(1) + int(4) * i_2;
        float _S15 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(0));
        pos_0[i_2] = _S15;
        float _S16 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(1));
        width_1[i_2] = _S16;
        float _S17 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(2));
        uint refs_0 = asuint(_S17);
        stem_0[i_2] = int(refs_0 << 16U) >> int(16);
        blue_0[i_2] = int(refs_0) >> int(16);
        float _S18 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(3));
        uint flags_0 = asuint(_S18);
        rounded_0[i_2] = (flags_0 & 1U) != 0U;
        syntheticApex_0[i_2] = (flags_0 & 2U) != 0U;
        semanticsResolved_0[i_2] = (flags_0 & 4U) != 0U;
        blueDirNegative_0[i_2] = (flags_0 & 8U) != 0U;
        gridCompanion_0[i_2] = int((flags_0 >> 4U) & 63U);
        blueCompanion_0[i_2] = int((flags_0 >> 10U) & 63U);
        hinted_0[i_2] = false;
        if(!snailAhFinite_0(pos_0[i_2]))
        {
            relative_0 = true;
        }
        else
        {
            relative_0 = !snailAhFinite_0(width_1[i_2]);
        }
        if(relative_0)
        {
            anchorSet_0 = true;
        }
        else
        {
            anchorSet_0 = (width_1[i_2]) < 0.0f;
        }
        if(anchorSet_0)
        {
            bottomBlue_0 = true;
        }
        else
        {
            bottomBlue_0 = (stem_0[i_2]) < int(-1);
        }
        if(bottomBlue_0)
        {
            _S14 = true;
        }
        else
        {
            _S14 = (stem_0[i_2]) >= n_0;
        }
        if(_S14)
        {
            axisAligned_0 = true;
        }
        else
        {
            axisAligned_0 = (blue_0[i_2]) < int(-1);
        }
        if(axisAligned_0)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (blue_0[i_2]) >= blueCount_0;
        }
        if(lowerBlue_0)
        {
            return false;
        }
        i_2 = i_2 + int(1);
    }
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
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
        int _S19 = int(2) * i_2;
        float ref_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S19);
        float shoot_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S19 + int(1));
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
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        if((stem_0[i_2]) >= int(0))
        {
            int j_0 = stem_0[i_2];
            if((stem_0[i_2]) >= n_0)
            {
                relative_0 = true;
            }
            else
            {
                relative_0 = j_0 == i_2;
            }
            if(relative_0)
            {
                anchorSet_0 = true;
            }
            else
            {
                anchorSet_0 = (stem_0[j_0]) != i_2;
            }
            if(anchorSet_0)
            {
                bottomBlue_0 = true;
            }
            else
            {
                bottomBlue_0 = !snailAhFinite_0(pos_0[j_0]);
            }
            if(bottomBlue_0)
            {
                _S14 = true;
            }
            else
            {
                _S14 = (pos_0[j_0]) == (pos_0[i_2]);
            }
            if(_S14)
            {
                axisAligned_0 = true;
            }
            else
            {
                axisAligned_0 = !snailAhFinite_0(width_1[j_0]);
            }
            if(axisAligned_0)
            {
                lowerBlue_0 = true;
            }
            else
            {
                lowerBlue_0 = (width_1[j_0]) != (width_1[i_2]);
            }
            if(lowerBlue_0)
            {
                return false;
            }
        }
        i_2 = i_2 + int(1);
    }
    if(_S13)
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
    float maxPx_0;
    bool _S20;
    bool _S21;
    bool upperBlue_0;
    int b_0;
    int clusterStems_0;
    int clusterRight_0;
    int stemMode_0;
    i_2 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        if((stem_0[i_2]) >= int(0))
        {
            relative_0 = (pos_0[stem_0[i_2]]) > (pos_0[i_2]);
        }
        else
        {
            relative_0 = false;
        }
        if(_S10)
        {
            anchorSet_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(anchorSet_0)
        {
            float _S22 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2] + int(1));
            float _S23 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2]);
            bottomBlue_0 = _S22 < _S23;
        }
        else
        {
            bottomBlue_0 = false;
        }
        if(!semanticsResolved_0[i_2])
        {
            _S14 = (stem_0[i_2]) < int(0);
        }
        else
        {
            _S14 = false;
        }
        if(_S14)
        {
            axisAligned_0 = !anchorSet_0;
        }
        else
        {
            axisAligned_0 = false;
        }
        if(axisAligned_0)
        {
            lowerBlue_0 = _S10;
        }
        else
        {
            lowerBlue_0 = false;
        }
        if(lowerBlue_0)
        {
            maxPx_0 = 3.4028234663852886e+38f;
            stemMode_0 = int(1);
            clusterRight_0 = int(0);
            for(;;)
            {
                if(clusterRight_0 < int(32))
                {
                }
                else
                {
                    break;
                }
                if(clusterRight_0 >= n_0)
                {
                    break;
                }
                if((blue_0[clusterRight_0]) < int(0))
                {
                    clusterRight_0 = clusterRight_0 + int(1);
                    continue;
                }
                float gap_0 = abs(pos_0[clusterRight_0] - pos_0[i_2]);
                if(gap_0 >= maxPx_0)
                {
                    clusterRight_0 = clusterRight_0 + int(1);
                    continue;
                }
                float _S24 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[clusterRight_0] + int(1));
                float _S25 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[clusterRight_0]);
                if(_S24 < _S25)
                {
                    clusterStems_0 = int(1);
                }
                else
                {
                    clusterStems_0 = int(-1);
                }
                maxPx_0 = gap_0;
                stemMode_0 = clusterStems_0;
                clusterRight_0 = clusterRight_0 + int(1);
            }
        }
        else
        {
            stemMode_0 = int(1);
        }
        if(semanticsResolved_0[i_2])
        {
            if(_S10)
            {
                upperBlue_0 = blueDirNegative_0[i_2];
            }
            else
            {
                upperBlue_0 = false;
            }
            if(upperBlue_0)
            {
                _S21 = true;
            }
            else
            {
                if(!_S10)
                {
                    _S21 = relative_0;
                }
                else
                {
                    _S21 = false;
                }
            }
            if(_S21)
            {
                clusterRight_0 = int(-1);
            }
            else
            {
                clusterRight_0 = int(1);
            }
        }
        else
        {
            if(relative_0)
            {
                upperBlue_0 = true;
            }
            else
            {
                upperBlue_0 = bottomBlue_0;
            }
            if(upperBlue_0)
            {
                clusterRight_0 = int(-1);
            }
            else
            {
                clusterRight_0 = stemMode_0;
            }
        }
        dir_0[i_2] = clusterRight_0;
        if(_S10)
        {
            clusterStems_0 = blueCompanion_0[i_2];
        }
        else
        {
            clusterStems_0 = gridCompanion_0[i_2];
        }
        if(!semanticsResolved_0[i_2])
        {
            upperBlue_0 = true;
        }
        else
        {
            upperBlue_0 = clusterStems_0 == int(63);
        }
        if(upperBlue_0)
        {
            b_0 = int(-2);
        }
        else
        {
            if(clusterStems_0 == int(62))
            {
                b_0 = int(-1);
            }
            else
            {
                b_0 = clusterStems_0;
            }
        }
        companion_0[i_2] = b_0;
        if(anchorSet_0)
        {
            float ref_1 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2]);
            float shoot_1 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2] + int(1));
            if(rounded_0[i_2])
            {
                _S21 = _S13;
            }
            else
            {
                _S21 = false;
            }
            if(_S21)
            {
                _S20 = (policy_0.yOvershoot_0) == int(0);
            }
            else
            {
                _S20 = false;
            }
            if(_S20)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            else
            {
                targets_0[i_2] = snailAhSnap_0(ref_1, scale_1);
                bool _S26;
                if(rounded_0[i_2])
                {
                    _S26 = (abs((shoot_1 - ref_1) * scale_1)) >= spacing_0;
                }
                else
                {
                    _S26 = false;
                }
                if(_S26)
                {
                    targets_0[i_2] = targets_0[i_2] + (shoot_1 - ref_1);
                }
            }
        }
        else
        {
            targets_0[i_2] = snailAhSnap_0(pos_0[i_2], scale_1);
        }
        i_2 = i_2 + int(1);
    }
    float grid_0 = 1.0f / scale_1;
    if(_S11)
    {
        stemMode_0 = policy_0.xStem_0;
    }
    else
    {
        stemMode_0 = policy_0.yStem_0;
    }
    if(_S11)
    {
        spacing_0 = policy_0.xRatio_0;
    }
    else
    {
        spacing_0 = policy_0.yRatio_0;
    }
    if(_S11)
    {
        maxPx_0 = policy_0.xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0.yMaxPx_0;
    }
    if(_S11)
    {
        _S10 = (policy_0.xAlign_0) == int(1);
    }
    else
    {
        _S10 = (policy_0.yAlign_0) != int(0);
    }
    if(_S11)
    {
        relative_0 = (policy_0.xPositioning_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    float widthUnits_0;
    float bestGap_0;
    int j_1;
    anchorSet_0 = false;
    float anchorTarget_0 = 0.0f;
    float anchorBase_0 = 0.0f;
    float clusterTarget_0 = 0.0f;
    float clusterBase_0 = 0.0f;
    float clusterDesiredRight_0 = 0.0f;
    clusterRight_0 = int(0);
    i_2 = int(0);
    clusterStems_0 = int(0);
    for(;;)
    {
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        int j_2 = stem_0[i_2];
        if((stem_0[i_2]) < int(0))
        {
            bottomBlue_0 = true;
        }
        else
        {
            bottomBlue_0 = j_2 <= i_2;
        }
        if(bottomBlue_0)
        {
            axisAligned_0 = anchorSet_0;
            int i_3 = i_2 + int(1);
            anchorSet_0 = axisAligned_0;
            i_2 = i_3;
            continue;
        }
        float nominal_0 = snailAhStandardWidth_0(width_1[i_2], standardWidth_0, spacing_0);
        float _S27 = width_1[i_2];
        if(stemMode_0 == int(2))
        {
            _S14 = true;
        }
        else
        {
            if(stemMode_0 == int(1))
            {
                _S14 = (nominal_0 * scale_1) < maxPx_0;
            }
            else
            {
                _S14 = false;
            }
        }
        if(_S14)
        {
            bestGap_0 = max(round(nominal_0 * scale_1), 1.0f) * grid_0;
        }
        else
        {
            bestGap_0 = _S27;
        }
        float anchorBase_1;
        float clusterTarget_1;
        float clusterBase_1;
        float clusterDesiredRight_1;
        if(relative_0)
        {
            if(anchorSet_0)
            {
                targets_0[i_2] = anchorTarget_0 + round((pos_0[i_2] - anchorBase_0) * scale_1) * grid_0;
                widthUnits_0 = clusterTarget_0;
                anchorBase_1 = clusterBase_0;
                axisAligned_0 = anchorSet_0;
            }
            else
            {
                float _S28 = snailAhSnap_0(pos_0[i_2], scale_1);
                targets_0[i_2] = _S28;
                widthUnits_0 = _S28;
                anchorBase_1 = pos_0[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_2] = targets_0[i_2] + bestGap_0;
            float _S29 = widthUnits_0 + round((pos_0[i_2] - anchorBase_1) * scale_1) * grid_0 + bestGap_0;
            int clusterStems_1 = clusterStems_0 + int(1);
            float _S30 = widthUnits_0;
            float _S31 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_0[i_2];
            clusterTarget_1 = _S30;
            clusterBase_1 = _S31;
            clusterDesiredRight_1 = _S29;
            b_0 = j_2;
            j_1 = clusterStems_1;
        }
        else
        {
            if(_S11)
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
                upperBlue_0 = (blue_0[j_2]) >= int(0);
            }
            else
            {
                upperBlue_0 = false;
            }
            if(!_S10)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            if(upperBlue_0)
            {
                _S21 = !lowerBlue_0;
            }
            else
            {
                _S21 = false;
            }
            if(_S21)
            {
                _S20 = _S10;
            }
            else
            {
                _S20 = false;
            }
            if(_S20)
            {
                targets_0[i_2] = targets_0[j_2] - bestGap_0;
            }
            else
            {
                targets_0[j_2] = targets_0[i_2] + bestGap_0;
            }
            axisAligned_0 = anchorSet_0;
            widthUnits_0 = anchorTarget_0;
            anchorBase_1 = anchorBase_0;
            clusterTarget_1 = clusterTarget_0;
            clusterBase_1 = clusterBase_0;
            clusterDesiredRight_1 = clusterDesiredRight_0;
            b_0 = clusterRight_0;
            j_1 = clusterStems_0;
        }
        hinted_0[i_2] = true;
        hinted_0[j_2] = true;
        anchorTarget_0 = widthUnits_0;
        anchorBase_0 = anchorBase_1;
        clusterTarget_0 = clusterTarget_1;
        clusterBase_0 = clusterBase_1;
        clusterDesiredRight_0 = clusterDesiredRight_1;
        clusterRight_0 = b_0;
        clusterStems_0 = j_1;
        int i_3 = i_2 + int(1);
        anchorSet_0 = axisAligned_0;
        i_2 = i_3;
    }
    if(relative_0)
    {
        _S10 = clusterStems_0 > int(1);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        float _S32 = clusterDesiredRight_0 - targets_0[clusterRight_0];
        i_2 = int(0);
        for(;;)
        {
            if(i_2 < int(32))
            {
            }
            else
            {
                break;
            }
            if(i_2 >= n_0)
            {
                break;
            }
            if(hinted_0[i_2])
            {
                targets_0[i_2] = targets_0[i_2] + _S32;
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
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        if(_S11)
        {
            axisAligned_0 = (policy_0.xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != int(0);
        }
        if(!axisAligned_0)
        {
            _S10 = true;
        }
        else
        {
            _S10 = (blue_0[i_2]) < int(0);
        }
        if(_S10)
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
                maxPx_0 = pos_0[i_2] - pos_0[best_0];
            }
            else
            {
                maxPx_0 = pos_0[best_0] - pos_0[i_2];
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
                j_1 = int(0);
                for(;;)
                {
                    if(j_1 < int(32))
                    {
                    }
                    else
                    {
                        break;
                    }
                    if(j_1 >= n_0)
                    {
                        break;
                    }
                    if(j_1 == i_2)
                    {
                        bottomBlue_0 = true;
                    }
                    else
                    {
                        bottomBlue_0 = (dir_0[j_1]) == (dir_0[i_2]);
                    }
                    if(bottomBlue_0)
                    {
                        j_1 = j_1 + int(1);
                        continue;
                    }
                    if(top_0)
                    {
                        widthUnits_0 = pos_0[i_2] - pos_0[j_1];
                    }
                    else
                    {
                        widthUnits_0 = pos_0[j_1] - pos_0[i_2];
                    }
                    if(widthUnits_0 <= 0.0f)
                    {
                        _S14 = true;
                    }
                    else
                    {
                        _S14 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S14)
                    {
                        j_1 = j_1 + int(1);
                        continue;
                    }
                    bestGap_0 = widthUnits_0;
                    b_0 = j_1;
                    j_1 = j_1 + int(1);
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
            bottomBlue_0 = true;
        }
        else
        {
            bottomBlue_0 = hinted_0[b_0];
        }
        if(bottomBlue_0)
        {
            _S14 = true;
        }
        else
        {
            _S14 = (blue_0[b_0]) >= int(0);
        }
        if(_S14)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (bestGap_0 * scale_1) >= spacing_0;
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
            widthUnits_0 = max(round(bestGap_0 * scale_1), 1.0f) * grid_0;
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
        if(i_2 < int(32))
        {
        }
        else
        {
            break;
        }
        if(i_2 >= n_0)
        {
            break;
        }
        if(_S11)
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
                _S10 = (blue_0[i_2]) >= int(0);
            }
            else
            {
                _S10 = false;
            }
            _S10 = !_S10;
        }
        else
        {
            _S10 = false;
        }
        if(_S10)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        knotBase_0[knotCount_0] = pos_0[i_2];
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
    if(_S11)
    {
        _S10 = (policy_0.xRegistration_0) == int(1);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = knotCount_0 > int(0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = knotCount_0 < int(32);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        _S10 = left_0 < (knotBase_0[int(0)] - 0.25f * grid_0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        i_2 = int(31);
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
                int _S33 = i_2 - int(1);
                knotBase_0[i_2] = knotBase_0[_S33];
                knotTarget_0[i_2] = knotTarget_0[_S33];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S33];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S33];
                knotSource_0[i_2] = knotSource_0[_S33];
            }
            i_2 = i_2 - int(1);
        }
        knotBase_0[int(0)] = left_0;
        knotTarget_0[int(0)] = snailAhSnap_0(left_0, scale_1);
        knotBlueFixed_0[int(0)] = false;
        knotNaturalSpacing_0[int(0)] = false;
        knotSource_0[int(0)] = int(32);
        knotCount_0 = knotCount_0 + int(1);
    }
    b_0 = int(31);
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
            _S10 = true;
        }
        else
        {
            _S10 = !knotBlueFixed_0[b_0];
        }
        if(_S10)
        {
            b_0 = b_0 - int(1);
            continue;
        }
        j_1 = int(31);
        for(;;)
        {
            if(j_1 > int(0))
            {
            }
            else
            {
                break;
            }
            if(j_1 > b_0)
            {
                j_1 = j_1 - int(1);
                continue;
            }
            int _S34 = j_1 - int(1);
            if(knotBlueFixed_0[_S34])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S34])
            {
                spacing_0 = 9.99999997475242708e-07f;
            }
            else
            {
                spacing_0 = grid_0;
            }
            knotTarget_0[_S34] = min(knotTarget_0[_S34], knotTarget_0[j_1] - spacing_0);
            j_1 = j_1 - int(1);
        }
        b_0 = b_0 - int(1);
    }
    i_2 = int(1);
    for(;;)
    {
        if(i_2 < int(32))
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
        _S10 = scale_1 > (policy_0.fadeStart_0);
    }
    else
    {
        _S10 = false;
    }
    if(_S10)
    {
        float span_0 = policy_0.fadeFull_0 - policy_0.fadeStart_0;
        if(span_0 <= 0.0f)
        {
            _S10 = true;
        }
        else
        {
            _S10 = scale_1 >= (policy_0.fadeFull_0);
        }
        if(_S10)
        {
            spacing_0 = 1.0f;
        }
        else
        {
            spacing_0 = (scale_1 - policy_0.fadeStart_0) / span_0;
        }
        i_2 = int(0);
        for(;;)
        {
            if(i_2 < int(32))
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
        if(i_2 < int(32))
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
            _S10 = true;
        }
        else
        {
            _S10 = !snailAhFinite_0(knotTarget_0[i_2]);
        }
        if(_S10)
        {
            knotCount_0 = int(0);
            return false;
        }
        i_2 = i_2 + int(1);
    }
    return true;
}

float snailInverseWarpAxis_0(int count_3, float  bases_0[int(32)], float  targets_1[int(32)], float hinted_1, out float invSlope_0)
{
    invSlope_0 = 1.0f;
    if(count_3 == int(0))
    {
        return hinted_1;
    }
    if(hinted_1 <= (targets_1[int(0)]))
    {
        return bases_0[int(0)] + hinted_1 - targets_1[int(0)];
    }
    int _S35 = count_3 - int(1);
    if(hinted_1 >= (targets_1[_S35]))
    {
        return bases_0[_S35] + hinted_1 - targets_1[_S35];
    }
    int lo_0;
    int i_4 = int(0);
    for(;;)
    {
        if(i_4 < int(31))
        {
        }
        else
        {
            lo_0 = int(0);
            break;
        }
        int _S36 = i_4 + int(1);
        bool _S37;
        if(_S36 >= count_3)
        {
            _S37 = true;
        }
        else
        {
            _S37 = (targets_1[_S36]) >= hinted_1;
        }
        if(_S37)
        {
            lo_0 = i_4;
            break;
        }
        i_4 = _S36;
    }
    int _S38 = lo_0 + int(1);
    int _S39 = lo_0;
    float dt_0 = targets_1[_S38] - targets_1[lo_0];
    int _S40 = lo_0;
    float db_0 = bases_0[_S38] - bases_0[lo_0];
    float _S41;
    if((abs(dt_0)) > 9.99999997475242708e-07f)
    {
        _S41 = db_0 / dt_0;
    }
    else
    {
        _S41 = 1.0f;
    }
    invSlope_0 = _S41;
    return bases_0[_S40] + (hinted_1 - targets_1[_S39]) * _S41;
}

float snailAhFastTarget_0(float4  values_0[int(4)], int idx_1)
{
    return values_0[idx_1 >> int(2)][idx_1 & int(3)];
}

float snailAhFastBase_0(Texture2D<float4 > layer_tex_3, int2 info_base_2, int run_1, float left_1, uint4 sources_0, int idx_2)
{
    uint source_0 = snailAhFastSource_0(sources_0, idx_2);
    float _S42;
    if(source_0 == 32U)
    {
        _S42 = left_1;
    }
    else
    {
        float _S43 = snailWarpF_0(layer_tex_3, info_base_2, run_1 + int(1) + int(4) * int(source_0), int(0));
        _S42 = _S43;
    }
    return _S42;
}

float snailInverseFastAxis_0(Texture2D<float4 > layer_tex_4, int2 info_base_3, int count_4, float4  targets_2[int(4)], uint4 sources_1, int run_2, float left_2, float hinted_2, out float invSlope_1)
{
    invSlope_1 = 1.0f;
    if(count_4 == int(0))
    {
        return hinted_2;
    }
    float firstTarget_0 = snailAhFastTarget_0(targets_2, int(0));
    float firstBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, int(0));
    if(hinted_2 <= firstTarget_0)
    {
        return firstBase_0 + hinted_2 - firstTarget_0;
    }
    int _S44 = count_4 - int(1);
    float lastTarget_0 = snailAhFastTarget_0(targets_2, _S44);
    float lastBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S44);
    if(hinted_2 >= lastTarget_0)
    {
        return lastBase_0 + hinted_2 - lastTarget_0;
    }
    int lo_1;
    int i_5 = int(0);
    for(;;)
    {
        if(i_5 < int(15))
        {
        }
        else
        {
            lo_1 = int(0);
            break;
        }
        int _S45 = i_5 + int(1);
        bool _S46;
        if(_S45 >= count_4)
        {
            _S46 = true;
        }
        else
        {
            _S46 = (snailAhFastTarget_0(targets_2, _S45)) >= hinted_2;
        }
        if(_S46)
        {
            lo_1 = i_5;
            break;
        }
        i_5 = _S45;
    }
    float loTarget_0 = snailAhFastTarget_0(targets_2, lo_1);
    int _S47 = lo_1 + int(1);
    float hiTarget_0 = snailAhFastTarget_0(targets_2, _S47);
    float loBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, lo_1);
    float hiBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S47);
    float dt_1 = hiTarget_0 - loTarget_0;
    float db_1 = hiBase_0 - loBase_0;
    float _S48;
    if((abs(dt_1)) > 9.99999997475242708e-07f)
    {
        _S48 = db_1 / dt_1;
    }
    else
    {
        _S48 = 1.0f;
    }
    invSlope_1 = _S48;
    return loBase_0 + (hinted_2 - loTarget_0) * _S48;
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S49;
    _S49.first_0 = first_1;
    _S49.last_0 = last_1;
    return _S49;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S50 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S50), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S50), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S51 = glyphLoc_0.x + int(offset_1);
    int2 loc_0 = int2(_S51, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S51 >> int(12));
    loc_0[int(0)] = (loc_0[int(0)]) & int(4095);
    return loc_0;
}

int decodeBandCurveFirstMemberCommon_0(uint2 ref_2)
{
    return int((ref_2.x) >> 12U);
}

bool isCoverageBandSpanOwner_0(uint2 ref_3, int band_0, int spanFirst_0)
{
    return band_0 == (max(decodeBandCurveFirstMemberCommon_0(ref_3), spanFirst_0));
}

int2 decodeBandCurveLocCommon_0(uint2 ref_4)
{
    return int2(int((ref_4.x) & 4095U), int((ref_4.y) & 16383U));
}

int2 decodeBandCurveLoc_0(uint2 ref_5)
{
    return decodeBandCurveLocCommon_0(ref_5);
}

int2 offsetCurveLoc_0(int2 base_1, int offset_2)
{
    int _S52 = base_1.x + offset_2;
    int2 loc_1 = int2(_S52, base_1.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S52 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_2)
{
    float _S53;
    if((abs(v_2)) <= 0.0000152587890625f)
    {
        _S53 = 0.0f;
    }
    else
    {
        _S53 = v_2;
    }
    return _S53;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_1, float ac_0)
{
    float _S54;
    if(disc_0 <= (max(b_1 * b_1, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S54 = 0.0f;
    }
    else
    {
        _S54 = sqrt(disc_0);
    }
    return _S54;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S55 = p12_0.xy;
    float2 _S56 = p12_0.zw;
    float2 a_0 = _S55 - _S56 * 2.0f + p3_0;
    float2 b_2 = _S55 - _S56;
    float _S57 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S57)) < 0.0000152587890625f)
    {
        float _S58 = b_2.y;
        if((abs(_S58)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S58;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S59 = b_2.y;
        float _S60 = p12_0.y;
        float _S61 = _S57 * _S60;
        float sq_0 = snapNearTangentSqrt_0(_S59 * _S59 - _S61, _S59, _S61);
        if(_S59 >= 0.0f)
        {
            float q_0 = _S59 + sq_0;
            float _S62 = q_0 / _S57;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S60 / q_0;
            }
            t2_0 = _S62;
        }
        else
        {
            float q_1 = _S59 - sq_0;
            float _S63 = q_1 / _S57;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S60 / q_1;
            }
            float _S64 = t1_0;
            t1_0 = _S63;
            t2_0 = _S64;
        }
    }
    float _S65 = a_0.x;
    float _S66 = b_2.x * 2.0f;
    float _S67 = p12_0.x;
    return float2((_S65 * t1_0 - _S66) * t1_0 + _S67, (_S65 * t2_0 - _S66) * t2_0 + _S67);
}

bool accumulateHorizContribution_0(inout float xcov_0, inout float xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, Texture2DArray<float4 > curve_tex_0)
{
    float4 tex0_0 = curve_tex_0.Load(int4(cLoc_0, texLayer_0, int(0)));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = curve_tex_0.Load(int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0))).xy - rc_0;
    float _S68 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S68) < -0.5f)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * _S68;
        if((code_0 & 1U) != 0U)
        {
            float _S69 = r_0.x;
            xcov_0 = xcov_0 + clamp(_S69 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S69) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > 1U)
        {
            float _S70 = r_0.y;
            xcov_0 = xcov_0 - clamp(_S70 + 0.5f, 0.0f, 1.0f);
            xwgt_0 = max(xwgt_0, clamp(1.0f - abs(_S70) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S71 = p12_2.xy;
    float2 _S72 = p12_2.zw;
    float2 a_1 = _S71 - _S72 * 2.0f + p3_2;
    float2 b_3 = _S71 - _S72;
    float _S73 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S73)) < 0.0000152587890625f)
    {
        float _S74 = b_3.x;
        if((abs(_S74)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S74;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S75 = b_3.x;
        float _S76 = p12_2.x;
        float _S77 = _S73 * _S76;
        float sq_1 = snapNearTangentSqrt_0(_S75 * _S75 - _S77, _S75, _S77);
        if(_S75 >= 0.0f)
        {
            float q_2 = _S75 + sq_1;
            float _S78 = q_2 / _S73;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S76 / q_2;
            }
            t2_1 = _S78;
        }
        else
        {
            float q_3 = _S75 - sq_1;
            float _S79 = q_3 / _S73;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S76 / q_3;
            }
            float _S80 = t1_1;
            t1_1 = _S79;
            t2_1 = _S80;
        }
    }
    float _S81 = a_1.y;
    float _S82 = b_3.y * 2.0f;
    float _S83 = p12_2.y;
    return float2((_S81 * t1_1 - _S82) * t1_1 + _S83, (_S81 * t2_1 - _S82) * t2_1 + _S83);
}

bool accumulateVertContribution_0(inout float ycov_0, inout float ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, Texture2DArray<float4 > curve_tex_1)
{
    float4 tex0_1 = curve_tex_1.Load(int4(cLoc_1, texLayer_1, int(0)));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = curve_tex_1.Load(int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0))).xy - rc_1;
    float _S84 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S84) < -0.5f)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * _S84;
        if((code_1 & 1U) != 0U)
        {
            float _S85 = r_1.x;
            ycov_0 = ycov_0 - clamp(_S85 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S85) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > 1U)
        {
            float _S86 = r_1.y;
            ycov_0 = ycov_0 + clamp(_S86 + 0.5f, 0.0f, 1.0f);
            ywgt_0 = max(ywgt_0, clamp(1.0f - abs(_S86) * 2.0f, 0.0f, 1.0f));
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
    float _S87 = max(coverage_exponent_1, 0.0000152587890625f);
    float _S88;
    if((abs(_S87 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S88 = clamped_0;
    }
    else
    {
        _S88 = pow(clamped_0, _S87);
    }
    return _S88;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_0, float coverage_exponent_2)
{
    bool _S89;
    int i_6;
    int _S90 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S90);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    float xcov_1 = 0.0f;
    float xwgt_1 = 0.0f;
    bool _S91 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int2 _S92 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S93 = int(hbd_0.x);
        i_6 = int(0);
        for(;;)
        {
            if(i_6 < _S93)
            {
            }
            else
            {
                break;
            }
            uint2 ref_6 = band_tex_0.Load(int4(calcBandLoc_0(_S92, uint(i_6)), texLayer_2, int(0))).xy;
            if(_S91)
            {
                _S89 = !isCoverageBandSpanOwner_0(ref_6, band_1, hSpan_0.first_0);
            }
            else
            {
                _S89 = false;
            }
            if(_S89)
            {
                i_6 = i_6 + int(1);
                continue;
            }
            bool _S94 = accumulateHorizContribution_0(xcov_1, xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_6), texLayer_2, curve_tex_2);
            if(!_S94)
            {
                break;
            }
            i_6 = i_6 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    float ycov_1 = 0.0f;
    float ywgt_1 = 0.0f;
    bool _S95 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        uint2 vbd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(_S90 + int(1) + band_1)), texLayer_2, int(0))).xy;
        int2 _S96 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S97 = int(vbd_0.x);
        i_6 = int(0);
        for(;;)
        {
            if(i_6 < _S97)
            {
            }
            else
            {
                break;
            }
            uint2 ref_7 = band_tex_0.Load(int4(calcBandLoc_0(_S96, uint(i_6)), texLayer_2, int(0))).xy;
            if(_S95)
            {
                _S89 = !isCoverageBandSpanOwner_0(ref_7, band_1, vSpan_0.first_0);
            }
            else
            {
                _S89 = false;
            }
            if(_S89)
            {
                i_6 = i_6 + int(1);
                continue;
            }
            bool _S98 = accumulateVertContribution_0(ycov_1, ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_7), texLayer_2, curve_tex_2);
            if(!_S98)
            {
                break;
            }
            i_6 = i_6 + int(1);
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

float srgbEncode_0(float c_1)
{
    float _S99;
    if(c_1 <= 0.00313080009073019f)
    {
        _S99 = c_1 * 12.92000007629394531f;
    }
    else
    {
        _S99 = 1.0549999475479126f * pow(c_1, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S99;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S100 = premul_0.w;
    if(_S100 <= 0.0f)
    {
        return (float4)0.0f;
    }
    return float4(linearToSrgb_0(premul_0.xyz * (1.0f / _S100)) * _S100, _S100);
}

struct AutohintVaryings_0
{
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

float4 snailAutohintFragment_0(AutohintVaryings_0 v_3, Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_1, Texture2D<float4 > layer_tex_5, int layer_base_1, int output_srgb_1, float coverage_exponent_3, int mask_output_1)
{
    float4 h0_0 = layer_tex_5.Load(int3(v_3.info_0, int(0)));
    int2 _S101 = snailAhLayerLoc_0(layer_tex_5, v_3.info_0, int(1));
    float4 h1_0 = layer_tex_5.Load(int3(_S101, int(0)));
    int2 gLoc_1 = int2(int(h0_0.x + 0.5f), int(h0_0.y + 0.5f));
    int packedBands_0 = asint(h0_0.z);
    int bandMaxH_0 = packedBands_0 & int(65535);
    int bandMaxV_0 = (packedBands_0 >> int(16)) & int(65535);
    int texLayer_3 = layer_base_1 + int(v_3.texcoord_layer_0.z);
    float2 _S102 = v_3.texcoord_layer_0.xy;
    float2 rc_3 = _S102;
    float2 epp_1 = (fwidth((_S102)));
    float _S103 = 1.0f / epp_1.x;
    float _S104 = 1.0f / epp_1.y;
    int blueCount_1 = int(0);
    int featureXCount_0 = int(0);
    int featureYCount_0 = int(0);
    float _S105 = snailWarpF_0(layer_tex_5, v_3.info_0, int(0), int(10));
    bool valid_0 = snailAhCount_0(int(32), _S105, blueCount_1);
    int xRun_0 = int(12) + int(2) * blueCount_1;
    bool valid_1;
    if(valid_0)
    {
        float _S106 = snailWarpF_0(layer_tex_5, v_3.info_0, xRun_0, int(0));
        bool _S107 = snailAhCount_0(int(32), _S106, featureXCount_0);
        valid_1 = _S107;
    }
    else
    {
        valid_1 = false;
    }
    int yRun_0 = xRun_0 + int(1) + int(4) * featureXCount_0;
    if(valid_1)
    {
        float _S108 = snailWarpF_0(layer_tex_5, v_3.info_0, yRun_0, int(0));
        valid_1 = snailAhCount_0(int(32), _S108, featureYCount_0);
    }
    else
    {
        valid_1 = false;
    }
    int xCount_0;
    int _S109;
    if(valid_1)
    {
        _S109 = snailAhFastCount_0(v_3.x_sources_0);
    }
    else
    {
        _S109 = int(0);
    }
    xCount_0 = _S109;
    int yCount_0;
    if(valid_1)
    {
        _S109 = snailAhFastCount_0(v_3.y_sources_0);
    }
    else
    {
        _S109 = int(0);
    }
    yCount_0 = _S109;
    float slopeX_0 = 1.0f;
    float slopeY_0 = 1.0f;
    bool fallbackX_0 = xCount_0 < int(0);
    bool fallbackY_0 = _S109 < int(0);
    if(valid_1)
    {
        if(fallbackX_0)
        {
            valid_1 = true;
        }
        else
        {
            valid_1 = fallbackY_0;
        }
    }
    else
    {
        valid_1 = false;
    }
    if(valid_1)
    {
        float stdX_0 = snailWarpF_0(layer_tex_5, v_3.info_0, int(0), int(8));
        float stdY_0 = snailWarpF_0(layer_tex_5, v_3.info_0, int(0), int(9));
        SnailAutohintPolicy_0 policy_1;
        bool _S110 = snailDecodeAutohintPolicy_0(v_3.policy0_0, v_3.policy1_0, policy_1);
        if(_S110)
        {
            valid_1 = snailAhFinite_0(stdX_0);
        }
        else
        {
            valid_1 = false;
        }
        if(valid_1)
        {
            valid_1 = stdX_0 >= 0.0f;
        }
        else
        {
            valid_1 = false;
        }
        if(valid_1)
        {
            valid_1 = snailAhFinite_0(stdY_0);
        }
        else
        {
            valid_1 = false;
        }
        if(valid_1)
        {
            valid_1 = stdY_0 >= 0.0f;
        }
        else
        {
            valid_1 = false;
        }
        bool _S111;
        if(valid_1)
        {
            _S111 = fallbackX_0;
        }
        else
        {
            _S111 = false;
        }
        if(_S111)
        {
            float _S112 = snailWarpF_0(layer_tex_5, v_3.info_0, int(0), int(11));
            float  bases_1[int(32)];
            float  targets_3[int(32)];
            int  sources_2[int(32)];
            bool fitValid_0 = snailFitAutohintAxis_0(layer_tex_5, v_3.info_0, int(0), xRun_0, blueCount_1, stdX_0, _S112, _S103, policy_1, xCount_0, bases_1, targets_3, sources_2);
            if(!fitValid_0)
            {
                xCount_0 = int(0);
            }
            float _S113 = snailInverseWarpAxis_0(xCount_0, bases_1, targets_3, rc_3.x, slopeX_0);
            rc_3[int(0)] = _S113;
        }
        if(valid_1)
        {
            valid_1 = fallbackY_0;
        }
        else
        {
            valid_1 = false;
        }
        if(valid_1)
        {
            float  bases_2[int(32)];
            float  targets_4[int(32)];
            int  sources_3[int(32)];
            bool fitValid_1 = snailFitAutohintAxis_0(layer_tex_5, v_3.info_0, int(1), yRun_0, blueCount_1, stdY_0, 0.0f, _S104, policy_1, yCount_0, bases_2, targets_4, sources_3);
            if(!fitValid_1)
            {
                yCount_0 = int(0);
            }
            float _S114 = snailInverseWarpAxis_0(yCount_0, bases_2, targets_4, rc_3.y, slopeY_0);
            rc_3[int(1)] = _S114;
        }
    }
    if(!fallbackX_0)
    {
        float _S115 = snailWarpF_0(layer_tex_5, v_3.info_0, int(0), int(11));
        float _S116 = snailInverseFastAxis_0(layer_tex_5, v_3.info_0, xCount_0, v_3.x_targets_0, v_3.x_sources_0, xRun_0, _S115, rc_3.x, slopeX_0);
        rc_3[int(0)] = _S116;
    }
    if(!fallbackY_0)
    {
        float _S117 = snailInverseFastAxis_0(layer_tex_5, v_3.info_0, yCount_0, v_3.y_targets_0, v_3.y_sources_0, yRun_0, 0.0f, rc_3.y, slopeY_0);
        rc_3[int(1)] = _S117;
    }
    float2 epp_2 = epp_1 * float2(slopeX_0, slopeY_0);
    float cov_2 = evalGlyphCoverage_0(rc_3, epp_2, float2(1.0f / max(epp_2.x, 0.0000152587890625f), 1.0f / max(epp_2.y, 0.0000152587890625f)), gLoc_1, int2(bandMaxV_0, bandMaxH_0), h1_0, texLayer_3, curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    float4 premul_1 = premultiplyColor_0(v_3.paint_0, cov_2);
    float4 _S118;
    if(mask_output_1 != int(0))
    {
        _S118 = (float4)premul_1.w;
    }
    else
    {
        if(output_srgb_1 != int(0))
        {
            _S118 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S118 = premul_1;
        }
    }
    return _S118;
}

struct VsOutput_0
{
    float4 position_0 : SV_Position;
    float4 paint_1 : TEXCOORD0;
    float3 texcoord_layer_1 : TEXCOORD1;
    nointerpolation int2 info_1 : TEXCOORD2;
    nointerpolation uint4 policy0_1 : TEXCOORD3;
    nointerpolation uint3 policy1_1 : TEXCOORD4;
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

float4 fragmentMain(VsOutput_0 input_0) : SV_TARGET
{
    AutohintVaryings_0 v_4;
    v_4.paint_0 = input_0.paint_1;
    v_4.texcoord_layer_0 = input_0.texcoord_layer_1;
    v_4.info_0 = input_0.info_1;
    v_4.policy0_0 = input_0.policy0_1;
    v_4.policy1_0 = input_0.policy1_1;
    v_4.x_targets_0[int(0)] = input_0.x_targets0_0;
    v_4.x_targets_0[int(1)] = input_0.x_targets1_0;
    v_4.x_targets_0[int(2)] = input_0.x_targets2_0;
    v_4.x_targets_0[int(3)] = input_0.x_targets3_0;
    v_4.y_targets_0[int(0)] = input_0.y_targets0_0;
    v_4.y_targets_0[int(1)] = input_0.y_targets1_0;
    v_4.y_targets_0[int(2)] = input_0.y_targets2_0;
    v_4.y_targets_0[int(3)] = input_0.y_targets3_0;
    v_4.x_sources_0 = input_0.x_sources_1;
    v_4.y_sources_0 = input_0.y_sources_1;
    float4 _S119 = snailAutohintFragment_0(v_4, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    return _S119;
}

