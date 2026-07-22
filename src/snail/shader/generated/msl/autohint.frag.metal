#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
int2 snailAhLayerLoc_0(texture2d<float, access::sample> layer_tex_0, int2 base_0, int offset_0)
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

float2 fwidth_0(float2 x_0)
{
    ;
}

float snailWarpF_0(texture2d<float, access::sample> layer_tex_1, int2 info_base_0, int block_0, int i_0)
{
    int f_0 = block_0 + i_0;
    int2 _S3 = snailAhLayerLoc_0(layer_tex_1, info_base_0, f_0 >> 2U);
    int3 _S4 = int3(_S3, int(0));
    float4 t_0 = ((layer_tex_1).read(vec<uint,2>(((_S4)).xy), uint(((_S4)).z)));
    int c_0 = f_0 & int(3);
    float _S5;
    if(c_0 == int(0))
    {
        _S5 = t_0.x;
    }
    else
    {
        if(c_0 == int(1))
        {
            _S5 = t_0.y;
        }
        else
        {
            if(c_0 == int(2))
            {
                _S5 = t_0.z;
            }
            else
            {
                _S5 = t_0.w;
            }
        }
    }
    return _S5;
}

bool snailAhFinite_0(float v_0)
{
    bool _S6;
    if(!isnan(v_0))
    {
        _S6 = !isinf(v_0);
    }
    else
    {
        _S6 = false;
    }
    return _S6;
}

bool snailAhCount_0(int max_knots_0, float encoded_0, int thread* count_0)
{
    bool _S7;
    if(!snailAhFinite_0(encoded_0))
    {
        _S7 = true;
    }
    else
    {
        _S7 = encoded_0 < 0.0;
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = encoded_0 > float(max_knots_0);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = (floor(encoded_0)) != encoded_0;
    }
    if(_S7)
    {
        *count_0 = int(0);
        return false;
    }
    *count_0 = int(encoded_0);
    return true;
}

uint snailAhFastSource_0(uint4 words_0, int idx_0)
{
    return ((words_0[idx_0 >> 2U]) >> uint((idx_0 & int(3)) * int(8))) & 255U;
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

bool snailDecodeAutohintPolicy_0(uint4 p0_0, uint3 p1_0, SnailAutohintPolicy_0 thread* p_0)
{
    p_0->xAlign_0 = int(0);
    p_0->xStem_0 = int(0);
    p_0->xPositioning_0 = int(0);
    p_0->xRegistration_0 = int(0);
    p_0->yAlign_0 = int(0);
    p_0->yStem_0 = int(0);
    p_0->yOvershoot_0 = int(0);
    p_0->fadeEnabled_0 = int(0);
    p_0->fadeStart_0 = 0.0;
    p_0->fadeFull_0 = 0.0;
    p_0->xRatio_0 = 0.0;
    p_0->xMaxPx_0 = 0.0;
    p_0->yRatio_0 = 0.0;
    p_0->yMaxPx_0 = 0.0;
    p_0->overshootMinPx_0 = 0.0;
    uint x_1 = p0_0.x;
    uint y_0 = p0_0.y;
    bool _S8;
    if((x_1 & 4286578688U) != 0U)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (y_0 & 4294967232U) != 0U;
    }
    if(_S8)
    {
        return false;
    }
    int _S9 = int(x_1 & 3U);
    p_0->xAlign_0 = _S9;
    p_0->xStem_0 = int((x_1 >> 2U) & 3U);
    p_0->xPositioning_0 = int((x_1 >> 4U) & 3U);
    p_0->xRegistration_0 = int((x_1 >> 6U) & 3U);
    p_0->fadeEnabled_0 = int((x_1 >> 8U) & 1U);
    p_0->fadeStart_0 = float((x_1 >> 9U) & 127U);
    p_0->fadeFull_0 = float((x_1 >> 16U) & 127U);
    p_0->yAlign_0 = int(y_0 & 3U);
    p_0->yStem_0 = int((y_0 >> 2U) & 3U);
    p_0->yOvershoot_0 = int((y_0 >> 4U) & 3U);
    if(_S9 > int(1))
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->xStem_0) > int(2);
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->xPositioning_0) > int(1);
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->xRegistration_0) > int(1);
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->yAlign_0) > int(2);
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->yStem_0) > int(2);
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        _S8 = (p_0->yOvershoot_0) > int(1);
    }
    if(_S8)
    {
        return false;
    }
    p_0->xRatio_0 = (as_type<float>((p0_0.z)));
    p_0->xMaxPx_0 = (as_type<float>((p0_0.w)));
    p_0->yRatio_0 = (as_type<float>((p1_0.x)));
    p_0->yMaxPx_0 = (as_type<float>((p1_0.y)));
    p_0->overshootMinPx_0 = (as_type<float>((p1_0.z)));
    if((p_0->xStem_0) != int(0))
    {
        if(!snailAhFinite_0(p_0->xRatio_0))
        {
            _S8 = true;
        }
        else
        {
            _S8 = (p_0->xRatio_0) < 0.0;
        }
    }
    else
    {
        _S8 = false;
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->xStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_0->xMaxPx_0))
            {
                _S8 = true;
            }
            else
            {
                _S8 = (p_0->xMaxPx_0) < 0.0;
            }
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->yStem_0) != int(0))
        {
            if(!snailAhFinite_0(p_0->yRatio_0))
            {
                _S8 = true;
            }
            else
            {
                _S8 = (p_0->yRatio_0) < 0.0;
            }
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->yStem_0) == int(1))
        {
            if(!snailAhFinite_0(p_0->yMaxPx_0))
            {
                _S8 = true;
            }
            else
            {
                _S8 = (p_0->yMaxPx_0) < 0.0;
            }
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->yOvershoot_0) == int(1))
        {
            if(!snailAhFinite_0(p_0->overshootMinPx_0))
            {
                _S8 = true;
            }
            else
            {
                _S8 = (p_0->overshootMinPx_0) < 0.0;
            }
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->xPositioning_0) == int(1))
        {
            _S8 = (p_0->xAlign_0) == int(0);
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
    {
        _S8 = true;
    }
    else
    {
        if((p_0->yOvershoot_0) == int(1))
        {
            _S8 = (p_0->yAlign_0) != int(2);
        }
        else
        {
            _S8 = false;
        }
    }
    if(_S8)
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
    bool _S10;
    if(standard_0 > 0.0)
    {
        _S10 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S10 = false;
    }
    float _S11;
    if(_S10)
    {
        _S11 = standard_0;
    }
    else
    {
        _S11 = raw_0;
    }
    return _S11;
}

bool snailFitAutohintAxis_0(texture2d<float, access::sample> layer_tex_2, int2 info_base_1, int axis_0, int run_0, int blueCount_0, float standardWidth_0, float left_0, float scale_1, const SnailAutohintPolicy_0 thread* policy_0, int thread* knotCount_0, array<float, int(32)> thread* knotBase_0, array<float, int(32)> thread* knotTarget_0, array<int, int(32)> thread* knotSource_0)
{
    *knotCount_0 = int(0);
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
        (*knotBase_0)[i_2] = 0.0;
        (*knotTarget_0)[i_2] = 0.0;
        (*knotSource_0)[i_2] = int(0);
        i_2 = i_2 + int(1);
    }
    bool _S12;
    if(!snailAhFinite_0(scale_1))
    {
        _S12 = true;
    }
    else
    {
        _S12 = scale_1 <= 0.0;
    }
    if(_S12)
    {
        _S12 = true;
    }
    else
    {
        _S12 = blueCount_0 < int(0);
    }
    if(_S12)
    {
        _S12 = true;
    }
    else
    {
        _S12 = blueCount_0 > int(32);
    }
    if(_S12)
    {
        _S12 = true;
    }
    else
    {
        _S12 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S12)
    {
        _S12 = true;
    }
    else
    {
        _S12 = standardWidth_0 < 0.0;
    }
    if(_S12)
    {
        return false;
    }
    bool _S13 = axis_0 == int(0);
    if(_S13)
    {
        _S12 = (policy_0->xAlign_0) == int(0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = (policy_0->xStem_0) == int(0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = (policy_0->xPositioning_0) == int(0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = (policy_0->xRegistration_0) == int(0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = true;
    }
    else
    {
        if(axis_0 == int(1))
        {
            _S12 = (policy_0->yAlign_0) == int(0);
        }
        else
        {
            _S12 = false;
        }
        if(_S12)
        {
            _S12 = (policy_0->yStem_0) == int(0);
        }
        else
        {
            _S12 = false;
        }
        if(_S12)
        {
            _S12 = (policy_0->yOvershoot_0) == int(0);
        }
        else
        {
            _S12 = false;
        }
    }
    if(_S12)
    {
        return true;
    }
    float _S14 = snailWarpF_0(layer_tex_2, info_base_1, run_0, int(0));
    int n_0 = int(_S14);
    if(n_0 <= int(0))
    {
        _S12 = true;
    }
    else
    {
        _S12 = n_0 > int(32);
    }
    if(_S12)
    {
        return n_0 == int(0);
    }
    bool _S15 = axis_0 == int(1);
    if(_S15)
    {
        _S12 = (policy_0->yAlign_0) == int(2);
    }
    else
    {
        _S12 = false;
    }
    bool relative_0;
    if(_S13)
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
    bool lowerBlue_0;
    bool axisAligned_0;
    bool _S16;
    bool bottomBlue_0;
    bool anchorSet_0;
    thread array<float, int(32)> pos_0;
    thread array<float, int(32)> width_1;
    thread array<int, int(32)> stem_0;
    thread array<int, int(32)> blue_0;
    thread array<bool, int(32)> rounded_0;
    thread array<bool, int(32)> syntheticApex_0;
    thread array<int, int(32)> companion_0;
    thread array<bool, int(32)> semanticsResolved_0;
    thread array<bool, int(32)> blueDirNegative_0;
    thread array<int, int(32)> gridCompanion_0;
    thread array<int, int(32)> blueCompanion_0;
    thread array<int, int(32)> dir_0;
    thread array<float, int(32)> targets_0;
    thread array<bool, int(32)> hinted_0;
    thread array<bool, int(32)> knotBlueFixed_0;
    thread array<bool, int(32)> knotNaturalSpacing_0;
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
        float _S17 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(0));
        pos_0[i_2] = _S17;
        float _S18 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(1));
        width_1[i_2] = _S18;
        float _S19 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(2));
        uint refs_0 = (as_type<uint>((_S19)));
        stem_0[i_2] = int(refs_0 << 16U) >> 16U;
        blue_0[i_2] = int(refs_0) >> 16U;
        float _S20 = snailWarpF_0(layer_tex_2, info_base_1, f_1, int(3));
        uint flags_0 = (as_type<uint>((_S20)));
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
            anchorSet_0 = (width_1[i_2]) < 0.0;
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
            _S16 = true;
        }
        else
        {
            _S16 = (stem_0[i_2]) >= n_0;
        }
        if(_S16)
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
        int _S21 = int(2) * i_2;
        float ref_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S21);
        float shoot_0 = snailWarpF_0(layer_tex_2, info_base_1, int(12), _S21 + int(1));
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
                _S16 = true;
            }
            else
            {
                _S16 = (pos_0[j_0]) == pos_0[i_2];
            }
            if(_S16)
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
                lowerBlue_0 = (width_1[j_0]) != width_1[i_2];
            }
            if(lowerBlue_0)
            {
                return false;
            }
        }
        i_2 = i_2 + int(1);
    }
    if(_S15)
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
    float maxPx_0;
    bool _S22;
    bool _S23;
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
            relative_0 = (pos_0[stem_0[i_2]]) > pos_0[i_2];
        }
        else
        {
            relative_0 = false;
        }
        if(_S12)
        {
            anchorSet_0 = (blue_0[i_2]) >= int(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(anchorSet_0)
        {
            float _S24 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2] + int(1));
            float _S25 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[i_2]);
            bottomBlue_0 = _S24 < _S25;
        }
        else
        {
            bottomBlue_0 = false;
        }
        if(!semanticsResolved_0[i_2])
        {
            _S16 = (stem_0[i_2]) < int(0);
        }
        else
        {
            _S16 = false;
        }
        if(_S16)
        {
            axisAligned_0 = !anchorSet_0;
        }
        else
        {
            axisAligned_0 = false;
        }
        if(axisAligned_0)
        {
            lowerBlue_0 = _S12;
        }
        else
        {
            lowerBlue_0 = false;
        }
        if(lowerBlue_0)
        {
            maxPx_0 = 3.4028234663852886e+38;
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
                float _S26 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[clusterRight_0] + int(1));
                float _S27 = snailWarpF_0(layer_tex_2, info_base_1, int(12), int(2) * blue_0[clusterRight_0]);
                if(_S26 < _S27)
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
            if(_S12)
            {
                upperBlue_0 = blueDirNegative_0[i_2];
            }
            else
            {
                upperBlue_0 = false;
            }
            if(upperBlue_0)
            {
                _S23 = true;
            }
            else
            {
                if(!_S12)
                {
                    _S23 = relative_0;
                }
                else
                {
                    _S23 = false;
                }
            }
            if(_S23)
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
        if(_S12)
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
                _S23 = _S15;
            }
            else
            {
                _S23 = false;
            }
            if(_S23)
            {
                _S22 = (policy_0->yOvershoot_0) == int(0);
            }
            else
            {
                _S22 = false;
            }
            if(_S22)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            else
            {
                targets_0[i_2] = snailAhSnap_0(ref_1, scale_1);
                bool _S28;
                if(rounded_0[i_2])
                {
                    _S28 = (abs((shoot_1 - ref_1) * scale_1)) >= spacing_0;
                }
                else
                {
                    _S28 = false;
                }
                if(_S28)
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
    float grid_0 = 1.0 / scale_1;
    if(_S13)
    {
        stemMode_0 = policy_0->xStem_0;
    }
    else
    {
        stemMode_0 = policy_0->yStem_0;
    }
    if(_S13)
    {
        spacing_0 = policy_0->xRatio_0;
    }
    else
    {
        spacing_0 = policy_0->yRatio_0;
    }
    if(_S13)
    {
        maxPx_0 = policy_0->xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0->yMaxPx_0;
    }
    if(_S13)
    {
        _S12 = (policy_0->xAlign_0) == int(1);
    }
    else
    {
        _S12 = (policy_0->yAlign_0) != int(0);
    }
    if(_S13)
    {
        relative_0 = (policy_0->xPositioning_0) == int(1);
    }
    else
    {
        relative_0 = false;
    }
    float widthUnits_0;
    float bestGap_0;
    int j_1;
    anchorSet_0 = false;
    float anchorTarget_0 = 0.0;
    float anchorBase_0 = 0.0;
    float clusterTarget_0 = 0.0;
    float clusterBase_0 = 0.0;
    float clusterDesiredRight_0 = 0.0;
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
        float _S29 = width_1[i_2];
        if(stemMode_0 == int(2))
        {
            _S16 = true;
        }
        else
        {
            if(stemMode_0 == int(1))
            {
                _S16 = (nominal_0 * scale_1) < maxPx_0;
            }
            else
            {
                _S16 = false;
            }
        }
        if(_S16)
        {
            bestGap_0 = max(round(nominal_0 * scale_1), 1.0) * grid_0;
        }
        else
        {
            bestGap_0 = _S29;
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
                float _S30 = snailAhSnap_0(pos_0[i_2], scale_1);
                targets_0[i_2] = _S30;
                widthUnits_0 = _S30;
                anchorBase_1 = pos_0[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_2] = targets_0[i_2] + bestGap_0;
            float _S31 = widthUnits_0 + round((pos_0[i_2] - anchorBase_1) * scale_1) * grid_0 + bestGap_0;
            int clusterStems_1 = clusterStems_0 + int(1);
            float _S32 = widthUnits_0;
            float _S33 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_0[i_2];
            clusterTarget_1 = _S32;
            clusterBase_1 = _S33;
            clusterDesiredRight_1 = _S31;
            b_0 = j_2;
            j_1 = clusterStems_1;
        }
        else
        {
            if(_S13)
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
                upperBlue_0 = (blue_0[j_2]) >= int(0);
            }
            else
            {
                upperBlue_0 = false;
            }
            if(!_S12)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            if(upperBlue_0)
            {
                _S23 = !lowerBlue_0;
            }
            else
            {
                _S23 = false;
            }
            if(_S23)
            {
                _S22 = _S12;
            }
            else
            {
                _S22 = false;
            }
            if(_S22)
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
        _S12 = clusterStems_0 > int(1);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        float _S34 = clusterDesiredRight_0 - targets_0[clusterRight_0];
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
                targets_0[i_2] = targets_0[i_2] + _S34;
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
        if(_S13)
        {
            axisAligned_0 = (policy_0->xAlign_0) != int(0);
        }
        else
        {
            axisAligned_0 = (policy_0->yAlign_0) != int(0);
        }
        if(!axisAligned_0)
        {
            _S12 = true;
        }
        else
        {
            _S12 = (blue_0[i_2]) < int(0);
        }
        if(_S12)
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
                bestGap_0 = 3.4028234663852886e+38;
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
                        bottomBlue_0 = (dir_0[j_1]) == dir_0[i_2];
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
                    if(widthUnits_0 <= 0.0)
                    {
                        _S16 = true;
                    }
                    else
                    {
                        _S16 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S16)
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
                bestGap_0 = 3.4028234663852886e+38;
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
            _S16 = true;
        }
        else
        {
            _S16 = (blue_0[b_0]) >= int(0);
        }
        if(_S16)
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
            widthUnits_0 = max(round(bestGap_0 * scale_1), 1.0) * grid_0;
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
        if(_S13)
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
                _S12 = (blue_0[i_2]) >= int(0);
            }
            else
            {
                _S12 = false;
            }
            _S12 = !_S12;
        }
        else
        {
            _S12 = false;
        }
        if(_S12)
        {
            i_2 = i_2 + int(1);
            continue;
        }
        (*knotBase_0)[*knotCount_0] = pos_0[i_2];
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
    if(_S13)
    {
        _S12 = (policy_0->xRegistration_0) == int(1);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = (*knotCount_0) > int(0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = (*knotCount_0) < int(32);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        _S12 = left_0 < ((*knotBase_0)[int(0)] - 0.25 * grid_0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
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
            if(i_2 <= (*knotCount_0))
            {
                int _S35 = i_2 - int(1);
                (*knotBase_0)[i_2] = (*knotBase_0)[_S35];
                (*knotTarget_0)[i_2] = (*knotTarget_0)[_S35];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S35];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S35];
                (*knotSource_0)[i_2] = (*knotSource_0)[_S35];
            }
            i_2 = i_2 - int(1);
        }
        (*knotBase_0)[int(0)] = left_0;
        (*knotTarget_0)[int(0)] = snailAhSnap_0(left_0, scale_1);
        knotBlueFixed_0[int(0)] = false;
        knotNaturalSpacing_0[int(0)] = false;
        (*knotSource_0)[int(0)] = int(32);
        *knotCount_0 = *knotCount_0 + int(1);
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
        if(b_0 >= (*knotCount_0))
        {
            _S12 = true;
        }
        else
        {
            _S12 = !knotBlueFixed_0[b_0];
        }
        if(_S12)
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
            int _S36 = j_1 - int(1);
            if(knotBlueFixed_0[_S36])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S36])
            {
                spacing_0 = 9.99999997475242708e-07;
            }
            else
            {
                spacing_0 = grid_0;
            }
            (*knotTarget_0)[_S36] = min((*knotTarget_0)[_S36], (*knotTarget_0)[j_1] - spacing_0);
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
        _S12 = scale_1 > (policy_0->fadeStart_0);
    }
    else
    {
        _S12 = false;
    }
    if(_S12)
    {
        float _S37 = policy_0->fadeFull_0;
        float _S38 = policy_0->fadeStart_0;
        float span_0 = policy_0->fadeFull_0 - policy_0->fadeStart_0;
        if(span_0 <= 0.0)
        {
            _S12 = true;
        }
        else
        {
            _S12 = scale_1 >= _S37;
        }
        if(_S12)
        {
            spacing_0 = 1.0;
        }
        else
        {
            spacing_0 = (scale_1 - _S38) / span_0;
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
        if(i_2 < int(32))
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
            _S12 = true;
        }
        else
        {
            _S12 = !snailAhFinite_0((*knotTarget_0)[i_2]);
        }
        if(_S12)
        {
            *knotCount_0 = int(0);
            return false;
        }
        i_2 = i_2 + int(1);
    }
    return true;
}

float snailInverseWarpAxis_0(int count_3, const array<float, int(32)> thread* bases_0, const array<float, int(32)> thread* targets_1, float hinted_1, float thread* invSlope_0)
{
    *invSlope_0 = 1.0;
    if(count_3 == int(0))
    {
        return hinted_1;
    }
    float _S39 = (*targets_1)[int(0)];
    if(hinted_1 <= (*targets_1)[int(0)])
    {
        return (*bases_0)[int(0)] + hinted_1 - _S39;
    }
    int _S40 = count_3 - int(1);
    float _S41 = (*targets_1)[_S40];
    if(hinted_1 >= (*targets_1)[_S40])
    {
        return (*bases_0)[_S40] + hinted_1 - _S41;
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
        int _S42 = i_4 + int(1);
        bool _S43;
        if(_S42 >= count_3)
        {
            _S43 = true;
        }
        else
        {
            _S43 = ((*targets_1)[_S42]) >= hinted_1;
        }
        if(_S43)
        {
            lo_0 = i_4;
            break;
        }
        i_4 = _S42;
    }
    int _S44 = lo_0 + int(1);
    float _S45 = (*targets_1)[lo_0];
    float dt_0 = (*targets_1)[_S44] - (*targets_1)[lo_0];
    float _S46 = (*bases_0)[lo_0];
    float db_0 = (*bases_0)[_S44] - (*bases_0)[lo_0];
    float _S47;
    if((abs(dt_0)) > 9.99999997475242708e-07)
    {
        _S47 = db_0 / dt_0;
    }
    else
    {
        _S47 = 1.0;
    }
    *invSlope_0 = _S47;
    return _S46 + (hinted_1 - _S45) * _S47;
}

float snailAhFastTarget_0(const array<float4, int(4)> thread* values_0, int idx_1)
{
    return (*values_0)[idx_1 >> 2U][idx_1 & int(3)];
}

float snailAhFastBase_0(texture2d<float, access::sample> layer_tex_3, int2 info_base_2, int run_1, float left_1, uint4 sources_0, int idx_2)
{
    uint source_0 = snailAhFastSource_0(sources_0, idx_2);
    float _S48;
    if(source_0 == 32U)
    {
        _S48 = left_1;
    }
    else
    {
        float _S49 = snailWarpF_0(layer_tex_3, info_base_2, run_1 + int(1) + int(4) * int(source_0), int(0));
        _S48 = _S49;
    }
    return _S48;
}

float snailInverseFastAxis_0(texture2d<float, access::sample> layer_tex_4, int2 info_base_3, int count_4, const array<float4, int(4)> thread* targets_2, uint4 sources_1, int run_2, float left_2, float hinted_2, float thread* invSlope_1)
{
    *invSlope_1 = 1.0;
    if(count_4 == int(0))
    {
        return hinted_2;
    }
    float _S50 = snailAhFastTarget_0(targets_2, int(0));
    float firstBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, int(0));
    if(hinted_2 <= _S50)
    {
        return firstBase_0 + hinted_2 - _S50;
    }
    int _S51 = count_4 - int(1);
    float _S52 = snailAhFastTarget_0(targets_2, _S51);
    float lastBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S51);
    if(hinted_2 >= _S52)
    {
        return lastBase_0 + hinted_2 - _S52;
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
        int _S53 = i_5 + int(1);
        bool _S54;
        if(_S53 >= count_4)
        {
            _S54 = true;
        }
        else
        {
            float _S55 = snailAhFastTarget_0(targets_2, _S53);
            _S54 = _S55 >= hinted_2;
        }
        if(_S54)
        {
            lo_1 = i_5;
            break;
        }
        i_5 = _S53;
    }
    float _S56 = snailAhFastTarget_0(targets_2, lo_1);
    int _S57 = lo_1 + int(1);
    float _S58 = snailAhFastTarget_0(targets_2, _S57);
    float loBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, lo_1);
    float hiBase_0 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S57);
    float dt_1 = _S58 - _S56;
    float db_1 = hiBase_0 - loBase_0;
    float _S59;
    if((abs(dt_1)) > 9.99999997475242708e-07)
    {
        _S59 = db_1 / dt_1;
    }
    else
    {
        _S59 = 1.0;
    }
    *invSlope_1 = _S59;
    return loBase_0 + (hinted_2 - _S56) * _S59;
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    thread CoverageBandSpan_0 _S60;
    (&_S60)->first_0 = first_1;
    (&_S60)->last_0 = last_1;
    return _S60;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S61 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S61), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S61), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S62 = glyphLoc_0.x + int(offset_1);
    thread int2 loc_0 = int2(_S62, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S62 >> 12U);
    loc_0.x = (loc_0.x) & int(4095);
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
    int _S63 = base_1.x + offset_2;
    thread int2 loc_1 = int2(_S63, base_1.y);
    loc_1.y = loc_1.y + (_S63 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
    return loc_1;
}

float rootCodeCoord_0(float v_2)
{
    float _S64;
    if((abs(v_2)) <= 0.0000152587890625)
    {
        _S64 = 0.0;
    }
    else
    {
        _S64 = v_2;
    }
    return _S64;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_1, float ac_0)
{
    float _S65;
    if(disc_0 <= (max(b_1 * b_1, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S65 = 0.0;
    }
    else
    {
        _S65 = sqrt(disc_0);
    }
    return _S65;
}

float2 solveHorizPoly_0(float4 p12_0, float2 p3_0)
{
    float2 _S66 = p12_0.xy;
    float2 _S67 = p12_0.zw;
    float2 a_0 = _S66 - _S67 * float2(2.0)  + p3_0;
    float2 b_2 = _S66 - _S67;
    float _S68 = a_0.y;
    float t1_0;
    float t2_0;
    if((abs(_S68)) < 0.0000152587890625)
    {
        float _S69 = b_2.y;
        if((abs(_S69)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p12_0.y * 0.5 / _S69;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S70 = b_2.y;
        float _S71 = p12_0.y;
        float _S72 = _S68 * _S71;
        float sq_0 = snapNearTangentSqrt_0(_S70 * _S70 - _S72, _S70, _S72);
        if(_S70 >= 0.0)
        {
            float q_0 = _S70 + sq_0;
            float _S73 = q_0 / _S68;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = _S71 / q_0;
            }
            t2_0 = _S73;
        }
        else
        {
            float q_1 = _S70 - sq_0;
            float _S74 = q_1 / _S68;
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = _S71 / q_1;
            }
            float _S75 = t1_0;
            t1_0 = _S74;
            t2_0 = _S75;
        }
    }
    float _S76 = a_0.x;
    float _S77 = b_2.x * 2.0;
    float _S78 = p12_0.x;
    return float2((_S76 * t1_0 - _S77) * t1_0 + _S78, (_S76 * t2_0 - _S77) * t2_0 + _S78);
}

bool accumulateHorizContribution_0(float thread* xcov_0, float thread* xwgt_0, float2 rc_0, float2 ppe_0, int2 cLoc_0, int texLayer_0, texture2d_array<float, access::sample> curve_tex_0)
{
    int4 _S79 = int4(cLoc_0, texLayer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S79)).xy), uint(((_S79)).z), uint(((_S79)).w)));
    int4 _S80 = int4(offsetCurveLoc_0(cLoc_0, int(1)), texLayer_0, int(0));
    float4 p12_1 = float4(tex0_0.xy, tex0_0.zw) - float4(rc_0, rc_0);
    float2 p3_1 = ((curve_tex_0).read(vec<uint,2>(((_S80)).xy), uint(((_S80)).z), uint(((_S80)).w))).xy - rc_0;
    float _S81 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S81) < -0.5)
    {
        return false;
    }
    uint code_0 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != 0U)
    {
        float2 r_0 = solveHorizPoly_0(p12_1, p3_1) * float2(_S81) ;
        if((code_0 & 1U) != 0U)
        {
            float _S82 = r_0.x;
            *xcov_0 = *xcov_0 + clamp(_S82 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S82) * 2.0, 0.0, 1.0));
        }
        if(code_0 > 1U)
        {
            float _S83 = r_0.y;
            *xcov_0 = *xcov_0 - clamp(_S83 + 0.5, 0.0, 1.0);
            *xwgt_0 = max(*xwgt_0, clamp(1.0 - abs(_S83) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float2 solveVertPoly_0(float4 p12_2, float2 p3_2)
{
    float2 _S84 = p12_2.xy;
    float2 _S85 = p12_2.zw;
    float2 a_1 = _S84 - _S85 * float2(2.0)  + p3_2;
    float2 b_3 = _S84 - _S85;
    float _S86 = a_1.x;
    float t1_1;
    float t2_1;
    if((abs(_S86)) < 0.0000152587890625)
    {
        float _S87 = b_3.x;
        if((abs(_S87)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p12_2.x * 0.5 / _S87;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S88 = b_3.x;
        float _S89 = p12_2.x;
        float _S90 = _S86 * _S89;
        float sq_1 = snapNearTangentSqrt_0(_S88 * _S88 - _S90, _S88, _S90);
        if(_S88 >= 0.0)
        {
            float q_2 = _S88 + sq_1;
            float _S91 = q_2 / _S86;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S89 / q_2;
            }
            t2_1 = _S91;
        }
        else
        {
            float q_3 = _S88 - sq_1;
            float _S92 = q_3 / _S86;
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = _S89 / q_3;
            }
            float _S93 = t1_1;
            t1_1 = _S92;
            t2_1 = _S93;
        }
    }
    float _S94 = a_1.y;
    float _S95 = b_3.y * 2.0;
    float _S96 = p12_2.y;
    return float2((_S94 * t1_1 - _S95) * t1_1 + _S96, (_S94 * t2_1 - _S95) * t2_1 + _S96);
}

bool accumulateVertContribution_0(float thread* ycov_0, float thread* ywgt_0, float2 rc_1, float2 ppe_1, int2 cLoc_1, int texLayer_1, texture2d_array<float, access::sample> curve_tex_1)
{
    int4 _S97 = int4(cLoc_1, texLayer_1, int(0));
    float4 tex0_1 = ((curve_tex_1).read(vec<uint,2>(((_S97)).xy), uint(((_S97)).z), uint(((_S97)).w)));
    int4 _S98 = int4(offsetCurveLoc_0(cLoc_1, int(1)), texLayer_1, int(0));
    float4 p12_3 = float4(tex0_1.xy, tex0_1.zw) - float4(rc_1, rc_1);
    float2 p3_3 = ((curve_tex_1).read(vec<uint,2>(((_S98)).xy), uint(((_S98)).z), uint(((_S98)).w))).xy - rc_1;
    float _S99 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S99) < -0.5)
    {
        return false;
    }
    uint code_1 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != 0U)
    {
        float2 r_1 = solveVertPoly_0(p12_3, p3_3) * float2(_S99) ;
        if((code_1 & 1U) != 0U)
        {
            float _S100 = r_1.x;
            *ycov_0 = *ycov_0 - clamp(_S100 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S100) * 2.0, 0.0, 1.0));
        }
        if(code_1 > 1U)
        {
            float _S101 = r_1.y;
            *ycov_0 = *ycov_0 + clamp(_S101 + 0.5, 0.0, 1.0);
            *ywgt_0 = max(*ywgt_0, clamp(1.0 - abs(_S101) * 2.0, 0.0, 1.0));
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
    float _S102 = max(coverage_exponent_0, 0.0000152587890625);
    float _S103;
    if((abs(_S102 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S103 = clamped_0;
    }
    else
    {
        _S103 = pow(clamped_0, _S102);
    }
    return _S103;
}

float evalGlyphCoverage_0(float2 rc_2, float2 epp_0, float2 ppe_2, int2 gLoc_0, int2 bandMax_1, float4 banding_0, int texLayer_2, texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_0, float coverage_exponent_1)
{
    bool _S104;
    int i_6;
    int _S105 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S105);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    thread float xcov_1 = 0.0;
    thread float xwgt_1 = 0.0;
    bool _S106 = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        int4 _S107 = int4(calcBandLoc_0(gLoc_0, uint(band_1)), texLayer_2, int(0));
        uint2 hbd_0 = ((band_tex_0).read(vec<uint,2>(((_S107)).xy), uint(((_S107)).z), uint(((_S107)).w)).xy).xy;
        int2 _S108 = calcBandLoc_0(gLoc_0, hbd_0.y);
        int _S109 = int(hbd_0.x);
        i_6 = int(0);
        for(;;)
        {
            if(i_6 < _S109)
            {
            }
            else
            {
                break;
            }
            int4 _S110 = int4(calcBandLoc_0(_S108, uint(i_6)), texLayer_2, int(0));
            uint2 ref_6 = ((band_tex_0).read(vec<uint,2>(((_S110)).xy), uint(((_S110)).z), uint(((_S110)).w)).xy).xy;
            if(_S106)
            {
                _S104 = !isCoverageBandSpanOwner_0(ref_6, band_1, hSpan_0.first_0);
            }
            else
            {
                _S104 = false;
            }
            if(_S104)
            {
                i_6 = i_6 + int(1);
                continue;
            }
            bool _S111 = accumulateHorizContribution_0(&xcov_1, &xwgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_6), texLayer_2, curve_tex_2);
            if(!_S111)
            {
                break;
            }
            i_6 = i_6 + int(1);
        }
        band_1 = band_1 + int(1);
    }
    thread float ycov_1 = 0.0;
    thread float ywgt_1 = 0.0;
    bool _S112 = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        int4 _S113 = int4(calcBandLoc_0(gLoc_0, uint(_S105 + int(1) + band_1)), texLayer_2, int(0));
        uint2 vbd_0 = ((band_tex_0).read(vec<uint,2>(((_S113)).xy), uint(((_S113)).z), uint(((_S113)).w)).xy).xy;
        int2 _S114 = calcBandLoc_0(gLoc_0, vbd_0.y);
        int _S115 = int(vbd_0.x);
        i_6 = int(0);
        for(;;)
        {
            if(i_6 < _S115)
            {
            }
            else
            {
                break;
            }
            int4 _S116 = int4(calcBandLoc_0(_S114, uint(i_6)), texLayer_2, int(0));
            uint2 ref_7 = ((band_tex_0).read(vec<uint,2>(((_S116)).xy), uint(((_S116)).z), uint(((_S116)).w)).xy).xy;
            if(_S112)
            {
                _S104 = !isCoverageBandSpanOwner_0(ref_7, band_1, vSpan_0.first_0);
            }
            else
            {
                _S104 = false;
            }
            if(_S104)
            {
                i_6 = i_6 + int(1);
                continue;
            }
            bool _S117 = accumulateVertContribution_0(&ycov_1, &ywgt_1, rc_2, ppe_2, decodeBandCurveLoc_0(ref_7), texLayer_2, curve_tex_2);
            if(!_S117)
            {
                break;
            }
            i_6 = i_6 + int(1);
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

float srgbEncode_0(float c_1)
{
    float _S118;
    if(c_1 <= 0.00313080009073019)
    {
        _S118 = c_1 * 12.92000007629394531;
    }
    else
    {
        _S118 = 1.0549999475479126 * pow(c_1, 0.4166666567325592) - 0.05499999970197678;
    }
    return _S118;
}

float3 linearToSrgb_0(float3 color_1)
{
    return float3(srgbEncode_0(max(color_1.x, 0.0)), srgbEncode_0(max(color_1.y, 0.0)), srgbEncode_0(max(color_1.z, 0.0)));
}

float4 srgbEncodePremultiplied_0(float4 premul_0)
{
    float _S119 = premul_0.w;
    if(_S119 <= 0.0)
    {
        return float4(0.0) ;
    }
    return float4(linearToSrgb_0(premul_0.xyz * float3((1.0 / _S119)) ) * float3(_S119) , _S119);
}

struct AutohintVaryings_0
{
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

float4 snailAutohintFragment_0(const AutohintVaryings_0 thread* v_3, texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_1, texture2d<float, access::sample> layer_tex_5, int layer_base_0, int output_srgb_0, float coverage_exponent_2, int mask_output_0)
{
    int2 _S120 = v_3->info_0;
    int3 _S121 = int3(v_3->info_0, int(0));
    float4 h0_0 = ((layer_tex_5).read(vec<uint,2>(((_S121)).xy), uint(((_S121)).z)));
    int2 _S122 = snailAhLayerLoc_0(layer_tex_5, v_3->info_0, int(1));
    int3 _S123 = int3(_S122, int(0));
    float4 h1_0 = ((layer_tex_5).read(vec<uint,2>(((_S123)).xy), uint(((_S123)).z)));
    int2 gLoc_1 = int2(int(h0_0.x + 0.5), int(h0_0.y + 0.5));
    int packedBands_0 = (as_type<int>((h0_0.z)));
    int bandMaxH_0 = packedBands_0 & int(65535);
    int bandMaxV_0 = (packedBands_0 >> 16U) & int(65535);
    int texLayer_3 = layer_base_0 + int(v_3->texcoord_layer_0.z);
    float2 _S124 = v_3->texcoord_layer_0.xy;
    thread float2 rc_3 = _S124;
    float2 epp_1 = fwidth_0(_S124);
    float _S125 = 1.0 / epp_1.x;
    float _S126 = 1.0 / epp_1.y;
    thread int blueCount_1 = int(0);
    thread int featureXCount_0 = int(0);
    thread int featureYCount_0 = int(0);
    float _S127 = snailWarpF_0(layer_tex_5, v_3->info_0, int(0), int(10));
    bool valid_0 = snailAhCount_0(int(32), _S127, &blueCount_1);
    int xRun_0 = int(12) + int(2) * blueCount_1;
    bool valid_1;
    if(valid_0)
    {
        float _S128 = snailWarpF_0(layer_tex_5, _S120, xRun_0, int(0));
        bool _S129 = snailAhCount_0(int(32), _S128, &featureXCount_0);
        valid_1 = _S129;
    }
    else
    {
        valid_1 = false;
    }
    int yRun_0 = xRun_0 + int(1) + int(4) * featureXCount_0;
    if(valid_1)
    {
        float _S130 = snailWarpF_0(layer_tex_5, _S120, yRun_0, int(0));
        valid_1 = snailAhCount_0(int(32), _S130, &featureYCount_0);
    }
    else
    {
        valid_1 = false;
    }
    thread int xCount_0;
    int _S131;
    if(valid_1)
    {
        _S131 = snailAhFastCount_0(v_3->x_sources_0);
    }
    else
    {
        _S131 = int(0);
    }
    xCount_0 = _S131;
    thread int yCount_0;
    if(valid_1)
    {
        _S131 = snailAhFastCount_0(v_3->y_sources_0);
    }
    else
    {
        _S131 = int(0);
    }
    yCount_0 = _S131;
    thread float slopeX_0 = 1.0;
    thread float slopeY_0 = 1.0;
    bool fallbackX_0 = xCount_0 < int(0);
    bool fallbackY_0 = _S131 < int(0);
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
        float stdX_0 = snailWarpF_0(layer_tex_5, _S120, int(0), int(8));
        float stdY_0 = snailWarpF_0(layer_tex_5, _S120, int(0), int(9));
        thread SnailAutohintPolicy_0 policy_1;
        bool _S132 = snailDecodeAutohintPolicy_0(v_3->policy0_0, v_3->policy1_0, &policy_1);
        if(_S132)
        {
            valid_1 = snailAhFinite_0(stdX_0);
        }
        else
        {
            valid_1 = false;
        }
        if(valid_1)
        {
            valid_1 = stdX_0 >= 0.0;
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
            valid_1 = stdY_0 >= 0.0;
        }
        else
        {
            valid_1 = false;
        }
        bool _S133;
        if(valid_1)
        {
            _S133 = fallbackX_0;
        }
        else
        {
            _S133 = false;
        }
        if(_S133)
        {
            float _S134 = snailWarpF_0(layer_tex_5, _S120, int(0), int(11));
            thread SnailAutohintPolicy_0 _S135 = policy_1;
            thread array<float, int(32)> bases_1;
            thread array<float, int(32)> targets_3;
            thread array<int, int(32)> sources_2;
            bool _S136 = snailFitAutohintAxis_0(layer_tex_5, _S120, int(0), xRun_0, blueCount_1, stdX_0, _S134, _S125, &_S135, &xCount_0, &bases_1, &targets_3, &sources_2);
            if(!_S136)
            {
                xCount_0 = int(0);
            }
            float _S137 = rc_3.x;
            thread array<float, int(32)> _S138 = bases_1;
            thread array<float, int(32)> _S139 = targets_3;
            float _S140 = snailInverseWarpAxis_0(xCount_0, &_S138, &_S139, _S137, &slopeX_0);
            rc_3.x = _S140;
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
            thread SnailAutohintPolicy_0 _S141 = policy_1;
            thread array<float, int(32)> bases_2;
            thread array<float, int(32)> targets_4;
            thread array<int, int(32)> sources_3;
            bool _S142 = snailFitAutohintAxis_0(layer_tex_5, _S120, int(1), yRun_0, blueCount_1, stdY_0, 0.0, _S126, &_S141, &yCount_0, &bases_2, &targets_4, &sources_3);
            if(!_S142)
            {
                yCount_0 = int(0);
            }
            float _S143 = rc_3.y;
            thread array<float, int(32)> _S144 = bases_2;
            thread array<float, int(32)> _S145 = targets_4;
            float _S146 = snailInverseWarpAxis_0(yCount_0, &_S144, &_S145, _S143, &slopeY_0);
            rc_3.y = _S146;
        }
    }
    if(!fallbackX_0)
    {
        float _S147 = snailWarpF_0(layer_tex_5, _S120, int(0), int(11));
        float _S148 = snailInverseFastAxis_0(layer_tex_5, _S120, xCount_0, &v_3->x_targets_0, v_3->x_sources_0, xRun_0, _S147, rc_3.x, &slopeX_0);
        rc_3.x = _S148;
    }
    if(!fallbackY_0)
    {
        float _S149 = snailInverseFastAxis_0(layer_tex_5, _S120, yCount_0, &v_3->y_targets_0, v_3->y_sources_0, yRun_0, 0.0, rc_3.y, &slopeY_0);
        rc_3.y = _S149;
    }
    float2 epp_2 = epp_1 * float2(slopeX_0, slopeY_0);
    float cov_2 = evalGlyphCoverage_0(rc_3, epp_2, float2(1.0 / max(epp_2.x, 0.0000152587890625), 1.0 / max(epp_2.y, 0.0000152587890625)), gLoc_1, int2(bandMaxV_0, bandMaxH_0), h1_0, texLayer_3, curve_tex_3, band_tex_1, coverage_exponent_2);
    if(cov_2 < 0.00392156885936856)
    {
        discard_fragment();
    }
    float4 premul_1 = premultiplyColor_0(v_3->paint_0, cov_2);
    float4 _S150;
    if(mask_output_0 != int(0))
    {
        _S150 = float4(premul_1.w) ;
    }
    else
    {
        if(output_srgb_0 != int(0))
        {
            _S150 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S150 = premul_1;
        }
    }
    return _S150;
}

struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};

struct pixelInput_0
{
    float4 paint_1 [[user(TEXCOORD)]];
    float3 texcoord_layer_1 [[user(TEXCOORD_1)]];
    [[flat]] int2 info_1 [[user(TEXCOORD_2)]];
    [[flat]] uint4 policy0_1 [[user(TEXCOORD_3)]];
    [[flat]] uint3 policy1_1 [[user(TEXCOORD_4)]];
    [[flat]] float4 x_targets0_0 [[user(TEXCOORD_5)]];
    [[flat]] float4 x_targets1_0 [[user(TEXCOORD_6)]];
    [[flat]] float4 x_targets2_0 [[user(TEXCOORD_7)]];
    [[flat]] float4 x_targets3_0 [[user(TEXCOORD_8)]];
    [[flat]] float4 y_targets0_0 [[user(TEXCOORD_9)]];
    [[flat]] float4 y_targets1_0 [[user(TEXCOORD_10)]];
    [[flat]] float4 y_targets2_0 [[user(TEXCOORD_11)]];
    [[flat]] float4 y_targets3_0 [[user(TEXCOORD_12)]];
    [[flat]] uint4 x_sources_1 [[user(TEXCOORD_13)]];
    [[flat]] uint4 y_sources_1 [[user(TEXCOORD_14)]];
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

[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S151 [[stage_in]], float4 position_0 [[position]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]], texture2d<float, access::sample> u_layer_tex_1 [[texture(2)]])
{
    thread KernelContext_0 kernelContext_0;
    (&kernelContext_0)->pc_0 = pc_1;
    (&kernelContext_0)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_0)->u_band_tex_0 = u_band_tex_1;
    (&kernelContext_0)->u_layer_tex_0 = u_layer_tex_1;
    thread AutohintVaryings_0 v_4;
    (&v_4)->paint_0 = _S151.paint_1;
    (&v_4)->texcoord_layer_0 = _S151.texcoord_layer_1;
    (&v_4)->info_0 = _S151.info_1;
    (&v_4)->policy0_0 = _S151.policy0_1;
    (&v_4)->policy1_0 = _S151.policy1_1;
    (&v_4)->x_targets_0[int(0)] = _S151.x_targets0_0;
    (&v_4)->x_targets_0[int(1)] = _S151.x_targets1_0;
    (&v_4)->x_targets_0[int(2)] = _S151.x_targets2_0;
    (&v_4)->x_targets_0[int(3)] = _S151.x_targets3_0;
    (&v_4)->y_targets_0[int(0)] = _S151.y_targets0_0;
    (&v_4)->y_targets_0[int(1)] = _S151.y_targets1_0;
    (&v_4)->y_targets_0[int(2)] = _S151.y_targets2_0;
    (&v_4)->y_targets_0[int(3)] = _S151.y_targets3_0;
    (&v_4)->x_sources_0 = _S151.x_sources_1;
    (&v_4)->y_sources_0 = _S151.y_sources_1;
    thread AutohintVaryings_0 _S152 = v_4;
    float4 _S153 = snailAutohintFragment_0(&_S152, u_curve_tex_1, u_band_tex_1, u_layer_tex_1, pc_1->layer_base_1, pc_1->output_srgb_1, pc_1->coverage_exponent_3, pc_1->mask_output_1);
    pixelOutput_0 _S154 = { _S153 };
    return _S154;
}

