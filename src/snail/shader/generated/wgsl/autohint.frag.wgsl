struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct SnailPushConstants_std140_0
{
    @align(16) mvp_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) viewport_0 : vec2<f32>,
    @align(8) subpixel_order_0 : i32,
    @align(4) output_srgb_0 : i32,
    @align(16) layer_base_0 : i32,
    @align(4) coverage_exponent_0 : f32,
    @align(8) dither_scale_0 : f32,
    @align(4) mask_output_0 : i32,
};

@binding(0) @group(2) var<uniform> pc_0 : SnailPushConstants_std140_0;
@binding(0) @group(0) var u_curve_tex_0 : texture_2d_array<f32>;

@binding(1) @group(0) var u_band_tex_0 : texture_2d_array<u32>;

@binding(2) @group(0) var u_layer_tex_0 : texture_2d<f32>;

fn snailAhLayerLoc_0( layer_tex_0 : texture_2d<f32>,  base_0 : vec2<i32>,  offset_0 : i32) -> vec2<i32>
{
    var uw_0 : u32;
    var uh_0 : u32;
    {var dim = textureDimensions((layer_tex_0));((uw_0)) = dim.x;((uh_0)) = dim.y;};
    var width_0 : i32 = i32(uw_0);
    var texel_0 : i32 = base_0.y * width_0 + base_0.x + offset_0;
    var _S1 : i32 = texel_0 % width_0;
    var _S2 : i32 = texel_0 / width_0;
    return vec2<i32>(_S1, _S2);
}

fn snailWarpF_0( layer_tex_1 : texture_2d<f32>,  info_base_0 : vec2<i32>,  block_0 : i32,  i_0 : i32) -> f32
{
    var f_0 : i32 = block_0 + i_0;
    var _S3 : vec2<i32> = snailAhLayerLoc_0(layer_tex_1, info_base_0, (f_0 >> (u32(2))));
    var _S4 : vec3<i32> = vec3<i32>(_S3, i32(0));
    var t_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S4)).xy, ((_S4)).z));
    var c_0 : i32 = (f_0 & (i32(3)));
    var _S5 : f32;
    if(c_0 == i32(0))
    {
        _S5 = t_0.x;
    }
    else
    {
        if(c_0 == i32(1))
        {
            _S5 = t_0.y;
        }
        else
        {
            if(c_0 == i32(2))
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

fn snailAhFinite_0( v_0 : f32) -> bool
{
    return (abs(v_0)) <= 3.40282306073709653e+38f;
}

fn snailAhCount_0( max_knots_0 : i32,  encoded_0 : f32,  count_0 : ptr<function, i32>) -> bool
{
    var _S6 : bool;
    if(!snailAhFinite_0(encoded_0))
    {
        _S6 = true;
    }
    else
    {
        _S6 = encoded_0 < 0.0f;
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = encoded_0 > f32(max_knots_0);
    }
    if(_S6)
    {
        _S6 = true;
    }
    else
    {
        _S6 = (floor(encoded_0)) != encoded_0;
    }
    if(_S6)
    {
        (*count_0) = i32(0);
        return false;
    }
    (*count_0) = i32(encoded_0);
    return true;
}

fn snailAhFastSource_0( words_0 : vec4<u32>,  idx_0 : i32) -> u32
{
    return ((((words_0[(idx_0 >> (u32(2)))]) >> (u32(((idx_0 & (i32(3)))) * i32(8))))) & (u32(255)));
}

fn snailAhFastCount_0( words_1 : vec4<u32>) -> i32
{
    if((snailAhFastSource_0(words_1, i32(0))) == u32(254))
    {
        return i32(-1);
    }
    var i_1 : i32 = i32(0);
    var count_1 : i32 = i32(0);
    for(;;)
    {
        if(i_1 < i32(16))
        {
        }
        else
        {
            break;
        }
        if((snailAhFastSource_0(words_1, i_1)) == u32(255))
        {
            break;
        }
        var count_2 : i32 = count_1 + i32(1);
        i_1 = i_1 + i32(1);
        count_1 = count_2;
    }
    return count_1;
}

struct SnailAutohintPolicy_0
{
     xAlign_0 : i32,
     xStem_0 : i32,
     xPositioning_0 : i32,
     xRegistration_0 : i32,
     yAlign_0 : i32,
     yStem_0 : i32,
     yOvershoot_0 : i32,
     fadeEnabled_0 : i32,
     fadeStart_0 : f32,
     fadeFull_0 : f32,
     xRatio_0 : f32,
     xMaxPx_0 : f32,
     yRatio_0 : f32,
     yMaxPx_0 : f32,
     overshootMinPx_0 : f32,
};

fn snailDecodeAutohintPolicy_0( p0_0 : vec4<u32>,  p1_0 : vec3<u32>,  p_0 : ptr<function, SnailAutohintPolicy_0>) -> bool
{
    (*p_0).xAlign_0 = i32(0);
    (*p_0).xStem_0 = i32(0);
    (*p_0).xPositioning_0 = i32(0);
    (*p_0).xRegistration_0 = i32(0);
    (*p_0).yAlign_0 = i32(0);
    (*p_0).yStem_0 = i32(0);
    (*p_0).yOvershoot_0 = i32(0);
    (*p_0).fadeEnabled_0 = i32(0);
    (*p_0).fadeStart_0 = 0.0f;
    (*p_0).fadeFull_0 = 0.0f;
    (*p_0).xRatio_0 = 0.0f;
    (*p_0).xMaxPx_0 = 0.0f;
    (*p_0).yRatio_0 = 0.0f;
    (*p_0).yMaxPx_0 = 0.0f;
    (*p_0).overshootMinPx_0 = 0.0f;
    var x_0 : u32 = p0_0.x;
    var y_0 : u32 = p0_0.y;
    var _S7 : bool;
    if(((x_0 & (u32(4286578688)))) != u32(0))
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((y_0 & (u32(4294967232)))) != u32(0);
    }
    if(_S7)
    {
        return false;
    }
    var _S8 : i32 = i32((x_0 & (u32(3))));
    (*p_0).xAlign_0 = _S8;
    (*p_0).xStem_0 = i32((((x_0 >> (u32(2)))) & (u32(3))));
    (*p_0).xPositioning_0 = i32((((x_0 >> (u32(4)))) & (u32(3))));
    (*p_0).xRegistration_0 = i32((((x_0 >> (u32(6)))) & (u32(3))));
    (*p_0).fadeEnabled_0 = i32((((x_0 >> (u32(8)))) & (u32(1))));
    (*p_0).fadeStart_0 = f32((((x_0 >> (u32(9)))) & (u32(127))));
    (*p_0).fadeFull_0 = f32((((x_0 >> (u32(16)))) & (u32(127))));
    (*p_0).yAlign_0 = i32((y_0 & (u32(3))));
    (*p_0).yStem_0 = i32((((y_0 >> (u32(2)))) & (u32(3))));
    (*p_0).yOvershoot_0 = i32((((y_0 >> (u32(4)))) & (u32(3))));
    if(_S8 > i32(1))
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).xStem_0) > i32(2);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).xPositioning_0) > i32(1);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).xRegistration_0) > i32(1);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).yAlign_0) > i32(2);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).yStem_0) > i32(2);
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        _S7 = ((*p_0).yOvershoot_0) > i32(1);
    }
    if(_S7)
    {
        return false;
    }
    (*p_0).xRatio_0 = (bitcast<f32>((p0_0.z)));
    (*p_0).xMaxPx_0 = (bitcast<f32>((p0_0.w)));
    (*p_0).yRatio_0 = (bitcast<f32>((p1_0.x)));
    (*p_0).yMaxPx_0 = (bitcast<f32>((p1_0.y)));
    (*p_0).overshootMinPx_0 = (bitcast<f32>((p1_0.z)));
    if(((*p_0).xStem_0) != i32(0))
    {
        if(!snailAhFinite_0((*p_0).xRatio_0))
        {
            _S7 = true;
        }
        else
        {
            _S7 = ((*p_0).xRatio_0) < 0.0f;
        }
    }
    else
    {
        _S7 = false;
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).xStem_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_0).xMaxPx_0))
            {
                _S7 = true;
            }
            else
            {
                _S7 = ((*p_0).xMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).yStem_0) != i32(0))
        {
            if(!snailAhFinite_0((*p_0).yRatio_0))
            {
                _S7 = true;
            }
            else
            {
                _S7 = ((*p_0).yRatio_0) < 0.0f;
            }
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).yStem_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_0).yMaxPx_0))
            {
                _S7 = true;
            }
            else
            {
                _S7 = ((*p_0).yMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).yOvershoot_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_0).overshootMinPx_0))
            {
                _S7 = true;
            }
            else
            {
                _S7 = ((*p_0).overshootMinPx_0) < 0.0f;
            }
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).xPositioning_0) == i32(1))
        {
            _S7 = ((*p_0).xAlign_0) == i32(0);
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        _S7 = true;
    }
    else
    {
        if(((*p_0).yOvershoot_0) == i32(1))
        {
            _S7 = ((*p_0).yAlign_0) != i32(2);
        }
        else
        {
            _S7 = false;
        }
    }
    if(_S7)
    {
        return false;
    }
    return true;
}

fn snailAhSnap_0( v_1 : f32,  scale_0 : f32) -> f32
{
    return round(v_1 * scale_0) / scale_0;
}

fn snailAhStandardWidth_0( raw_0 : f32,  standard_0 : f32,  ratio_0 : f32) -> f32
{
    var _S9 : bool;
    if(standard_0 > 0.0f)
    {
        _S9 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S9 = false;
    }
    var _S10 : f32;
    if(_S9)
    {
        _S10 = standard_0;
    }
    else
    {
        _S10 = raw_0;
    }
    return _S10;
}

fn snailFitAutohintAxis_0( layer_tex_2 : texture_2d<f32>,  info_base_1 : vec2<i32>,  axis_0 : i32,  run_0 : i32,  blueCount_0 : i32,  standardWidth_0 : f32,  left_0 : f32,  scale_1 : f32,  policy_0 : SnailAutohintPolicy_0,  knotCount_0 : ptr<function, i32>,  knotBase_0 : ptr<function, array<f32, i32(32)>>,  knotTarget_0 : ptr<function, array<f32, i32(32)>>,  knotSource_0 : ptr<function, array<i32, i32(32)>>) -> bool
{
    (*knotCount_0) = i32(0);
    var i_2 : i32 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
        {
        }
        else
        {
            break;
        }
        (*knotBase_0)[i_2] = 0.0f;
        (*knotTarget_0)[i_2] = 0.0f;
        (*knotSource_0)[i_2] = i32(0);
        i_2 = i_2 + i32(1);
    }
    var _S11 : bool;
    if(!snailAhFinite_0(scale_1))
    {
        _S11 = true;
    }
    else
    {
        _S11 = scale_1 <= 0.0f;
    }
    if(_S11)
    {
        _S11 = true;
    }
    else
    {
        _S11 = blueCount_0 < i32(0);
    }
    if(_S11)
    {
        _S11 = true;
    }
    else
    {
        _S11 = blueCount_0 > i32(32);
    }
    if(_S11)
    {
        _S11 = true;
    }
    else
    {
        _S11 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S11)
    {
        _S11 = true;
    }
    else
    {
        _S11 = standardWidth_0 < 0.0f;
    }
    if(_S11)
    {
        return false;
    }
    var _S12 : bool = axis_0 == i32(0);
    if(_S12)
    {
        _S11 = (policy_0.xAlign_0) == i32(0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = (policy_0.xStem_0) == i32(0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = (policy_0.xPositioning_0) == i32(0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = (policy_0.xRegistration_0) == i32(0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = true;
    }
    else
    {
        if(axis_0 == i32(1))
        {
            _S11 = (policy_0.yAlign_0) == i32(0);
        }
        else
        {
            _S11 = false;
        }
        if(_S11)
        {
            _S11 = (policy_0.yStem_0) == i32(0);
        }
        else
        {
            _S11 = false;
        }
        if(_S11)
        {
            _S11 = (policy_0.yOvershoot_0) == i32(0);
        }
        else
        {
            _S11 = false;
        }
    }
    if(_S11)
    {
        return true;
    }
    var _S13 : f32 = snailWarpF_0(layer_tex_2, info_base_1, run_0, i32(0));
    var n_0 : i32 = i32(_S13);
    if(n_0 <= i32(0))
    {
        _S11 = true;
    }
    else
    {
        _S11 = n_0 > i32(32);
    }
    if(_S11)
    {
        return n_0 == i32(0);
    }
    var _S14 : bool = axis_0 == i32(1);
    if(_S14)
    {
        _S11 = (policy_0.yAlign_0) == i32(2);
    }
    else
    {
        _S11 = false;
    }
    var relative_0 : bool;
    if(_S12)
    {
        relative_0 = (policy_0.xRegistration_0) == i32(1);
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
    var lowerBlue_0 : bool;
    var axisAligned_0 : bool;
    var _S15 : bool;
    var bottomBlue_0 : bool;
    var anchorSet_0 : bool;
    var pos_0 : array<f32, i32(32)>;
    var width_1 : array<f32, i32(32)>;
    var stem_0 : array<i32, i32(32)>;
    var blue_0 : array<i32, i32(32)>;
    var rounded_0 : array<bool, i32(32)>;
    var syntheticApex_0 : array<bool, i32(32)>;
    var companion_0 : array<i32, i32(32)>;
    var semanticsResolved_0 : array<bool, i32(32)>;
    var blueDirNegative_0 : array<bool, i32(32)>;
    var gridCompanion_0 : array<i32, i32(32)>;
    var blueCompanion_0 : array<i32, i32(32)>;
    var dir_0 : array<i32, i32(32)>;
    var targets_0 : array<f32, i32(32)>;
    var hinted_0 : array<bool, i32(32)>;
    var knotBlueFixed_0 : array<bool, i32(32)>;
    var knotNaturalSpacing_0 : array<bool, i32(32)>;
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        var f_1 : i32 = run_0 + i32(1) + i32(4) * i_2;
        var _S16 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(0));
        pos_0[i_2] = _S16;
        var _S17 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(1));
        width_1[i_2] = _S17;
        var _S18 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(2));
        var refs_0 : u32 = (bitcast<u32>((_S18)));
        stem_0[i_2] = (i32((refs_0 << (u32(16)))) >> (u32(16)));
        blue_0[i_2] = (i32(refs_0) >> (u32(16)));
        var _S19 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(3));
        var flags_0 : u32 = (bitcast<u32>((_S19)));
        rounded_0[i_2] = ((flags_0 & (u32(1)))) != u32(0);
        syntheticApex_0[i_2] = ((flags_0 & (u32(2)))) != u32(0);
        semanticsResolved_0[i_2] = ((flags_0 & (u32(4)))) != u32(0);
        blueDirNegative_0[i_2] = ((flags_0 & (u32(8)))) != u32(0);
        gridCompanion_0[i_2] = i32((((flags_0 >> (u32(4)))) & (u32(63))));
        blueCompanion_0[i_2] = i32((((flags_0 >> (u32(10)))) & (u32(63))));
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
            bottomBlue_0 = (stem_0[i_2]) < i32(-1);
        }
        if(bottomBlue_0)
        {
            _S15 = true;
        }
        else
        {
            _S15 = (stem_0[i_2]) >= n_0;
        }
        if(_S15)
        {
            axisAligned_0 = true;
        }
        else
        {
            axisAligned_0 = (blue_0[i_2]) < i32(-1);
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
        i_2 = i_2 + i32(1);
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        var _S20 : i32 = i32(2) * i_2;
        var ref_0 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), _S20);
        var shoot_0 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), _S20 + i32(1));
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
        i_2 = i_2 + i32(1);
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        if((stem_0[i_2]) >= i32(0))
        {
            var j_0 : i32 = stem_0[i_2];
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
                _S15 = true;
            }
            else
            {
                _S15 = (pos_0[j_0]) == (pos_0[i_2]);
            }
            if(_S15)
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
        i_2 = i_2 + i32(1);
    }
    if(_S14)
    {
        relative_0 = (policy_0.yOvershoot_0) == i32(1);
    }
    else
    {
        relative_0 = false;
    }
    var spacing_0 : f32;
    if(relative_0)
    {
        spacing_0 = policy_0.overshootMinPx_0;
    }
    else
    {
        spacing_0 = 0.0f;
    }
    var maxPx_0 : f32;
    var _S21 : bool;
    var _S22 : bool;
    var upperBlue_0 : bool;
    var b_0 : i32;
    var clusterStems_0 : i32;
    var clusterRight_0 : i32;
    var stemMode_0 : i32;
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        if((stem_0[i_2]) >= i32(0))
        {
            relative_0 = (pos_0[stem_0[i_2]]) > (pos_0[i_2]);
        }
        else
        {
            relative_0 = false;
        }
        if(_S11)
        {
            anchorSet_0 = (blue_0[i_2]) >= i32(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(anchorSet_0)
        {
            var _S23 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2] + i32(1));
            var _S24 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2]);
            bottomBlue_0 = _S23 < _S24;
        }
        else
        {
            bottomBlue_0 = false;
        }
        if(!semanticsResolved_0[i_2])
        {
            _S15 = (stem_0[i_2]) < i32(0);
        }
        else
        {
            _S15 = false;
        }
        if(_S15)
        {
            axisAligned_0 = !anchorSet_0;
        }
        else
        {
            axisAligned_0 = false;
        }
        if(axisAligned_0)
        {
            lowerBlue_0 = _S11;
        }
        else
        {
            lowerBlue_0 = false;
        }
        if(lowerBlue_0)
        {
            maxPx_0 = 3.4028234663852886e+38f;
            stemMode_0 = i32(1);
            clusterRight_0 = i32(0);
            for(;;)
            {
                if(clusterRight_0 < i32(32))
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
                if((blue_0[clusterRight_0]) < i32(0))
                {
                    clusterRight_0 = clusterRight_0 + i32(1);
                    continue;
                }
                var gap_0 : f32 = abs(pos_0[clusterRight_0] - pos_0[i_2]);
                if(gap_0 >= maxPx_0)
                {
                    clusterRight_0 = clusterRight_0 + i32(1);
                    continue;
                }
                var _S25 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[clusterRight_0] + i32(1));
                var _S26 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[clusterRight_0]);
                if(_S25 < _S26)
                {
                    clusterStems_0 = i32(1);
                }
                else
                {
                    clusterStems_0 = i32(-1);
                }
                maxPx_0 = gap_0;
                stemMode_0 = clusterStems_0;
                clusterRight_0 = clusterRight_0 + i32(1);
            }
        }
        else
        {
            stemMode_0 = i32(1);
        }
        if(semanticsResolved_0[i_2])
        {
            if(_S11)
            {
                upperBlue_0 = blueDirNegative_0[i_2];
            }
            else
            {
                upperBlue_0 = false;
            }
            if(upperBlue_0)
            {
                _S22 = true;
            }
            else
            {
                if(!_S11)
                {
                    _S22 = relative_0;
                }
                else
                {
                    _S22 = false;
                }
            }
            if(_S22)
            {
                clusterRight_0 = i32(-1);
            }
            else
            {
                clusterRight_0 = i32(1);
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
                clusterRight_0 = i32(-1);
            }
            else
            {
                clusterRight_0 = stemMode_0;
            }
        }
        dir_0[i_2] = clusterRight_0;
        if(_S11)
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
            upperBlue_0 = clusterStems_0 == i32(63);
        }
        if(upperBlue_0)
        {
            b_0 = i32(-2);
        }
        else
        {
            if(clusterStems_0 == i32(62))
            {
                b_0 = i32(-1);
            }
            else
            {
                b_0 = clusterStems_0;
            }
        }
        companion_0[i_2] = b_0;
        if(anchorSet_0)
        {
            var ref_1 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2]);
            var shoot_1 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2] + i32(1));
            if(rounded_0[i_2])
            {
                _S22 = _S14;
            }
            else
            {
                _S22 = false;
            }
            if(_S22)
            {
                _S21 = (policy_0.yOvershoot_0) == i32(0);
            }
            else
            {
                _S21 = false;
            }
            if(_S21)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            else
            {
                targets_0[i_2] = snailAhSnap_0(ref_1, scale_1);
                var _S27 : bool;
                if(rounded_0[i_2])
                {
                    _S27 = (abs((shoot_1 - ref_1) * scale_1)) >= spacing_0;
                }
                else
                {
                    _S27 = false;
                }
                if(_S27)
                {
                    targets_0[i_2] = targets_0[i_2] + (shoot_1 - ref_1);
                }
            }
        }
        else
        {
            targets_0[i_2] = snailAhSnap_0(pos_0[i_2], scale_1);
        }
        i_2 = i_2 + i32(1);
    }
    var grid_0 : f32 = 1.0f / scale_1;
    if(_S12)
    {
        stemMode_0 = policy_0.xStem_0;
    }
    else
    {
        stemMode_0 = policy_0.yStem_0;
    }
    if(_S12)
    {
        spacing_0 = policy_0.xRatio_0;
    }
    else
    {
        spacing_0 = policy_0.yRatio_0;
    }
    if(_S12)
    {
        maxPx_0 = policy_0.xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0.yMaxPx_0;
    }
    if(_S12)
    {
        _S11 = (policy_0.xAlign_0) == i32(1);
    }
    else
    {
        _S11 = (policy_0.yAlign_0) != i32(0);
    }
    if(_S12)
    {
        relative_0 = (policy_0.xPositioning_0) == i32(1);
    }
    else
    {
        relative_0 = false;
    }
    var widthUnits_0 : f32;
    var bestGap_0 : f32;
    var j_1 : i32;
    anchorSet_0 = false;
    var anchorTarget_0 : f32 = 0.0f;
    var anchorBase_0 : f32 = 0.0f;
    var clusterTarget_0 : f32 = 0.0f;
    var clusterBase_0 : f32 = 0.0f;
    var clusterDesiredRight_0 : f32 = 0.0f;
    clusterRight_0 = i32(0);
    i_2 = i32(0);
    clusterStems_0 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        var j_2 : i32 = stem_0[i_2];
        if((stem_0[i_2]) < i32(0))
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
            var i_3 : i32 = i_2 + i32(1);
            anchorSet_0 = axisAligned_0;
            i_2 = i_3;
            continue;
        }
        var nominal_0 : f32 = snailAhStandardWidth_0(width_1[i_2], standardWidth_0, spacing_0);
        var _S28 : f32 = width_1[i_2];
        if(stemMode_0 == i32(2))
        {
            _S15 = true;
        }
        else
        {
            if(stemMode_0 == i32(1))
            {
                _S15 = (nominal_0 * scale_1) < maxPx_0;
            }
            else
            {
                _S15 = false;
            }
        }
        if(_S15)
        {
            bestGap_0 = max(round(nominal_0 * scale_1), 1.0f) * grid_0;
        }
        else
        {
            bestGap_0 = _S28;
        }
        var anchorBase_1 : f32;
        var clusterTarget_1 : f32;
        var clusterBase_1 : f32;
        var clusterDesiredRight_1 : f32;
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
                var _S29 : f32 = snailAhSnap_0(pos_0[i_2], scale_1);
                targets_0[i_2] = _S29;
                widthUnits_0 = _S29;
                anchorBase_1 = pos_0[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_2] = targets_0[i_2] + bestGap_0;
            var _S30 : f32 = widthUnits_0 + round((pos_0[i_2] - anchorBase_1) * scale_1) * grid_0 + bestGap_0;
            var clusterStems_1 : i32 = clusterStems_0 + i32(1);
            var _S31 : f32 = widthUnits_0;
            var _S32 : f32 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_0[i_2];
            clusterTarget_1 = _S31;
            clusterBase_1 = _S32;
            clusterDesiredRight_1 = _S30;
            b_0 = j_2;
            j_1 = clusterStems_1;
        }
        else
        {
            if(_S12)
            {
                axisAligned_0 = (policy_0.xAlign_0) != i32(0);
            }
            else
            {
                axisAligned_0 = (policy_0.yAlign_0) != i32(0);
            }
            if(axisAligned_0)
            {
                lowerBlue_0 = (blue_0[i_2]) >= i32(0);
            }
            else
            {
                lowerBlue_0 = false;
            }
            if(axisAligned_0)
            {
                upperBlue_0 = (blue_0[j_2]) >= i32(0);
            }
            else
            {
                upperBlue_0 = false;
            }
            if(!_S11)
            {
                targets_0[i_2] = pos_0[i_2];
            }
            if(upperBlue_0)
            {
                _S22 = !lowerBlue_0;
            }
            else
            {
                _S22 = false;
            }
            if(_S22)
            {
                _S21 = _S11;
            }
            else
            {
                _S21 = false;
            }
            if(_S21)
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
        var i_3 : i32 = i_2 + i32(1);
        anchorSet_0 = axisAligned_0;
        i_2 = i_3;
    }
    if(relative_0)
    {
        _S11 = clusterStems_0 > i32(1);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        var _S33 : f32 = clusterDesiredRight_0 - targets_0[clusterRight_0];
        i_2 = i32(0);
        for(;;)
        {
            if(i_2 < i32(32))
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
                targets_0[i_2] = targets_0[i_2] + _S33;
            }
            i_2 = i_2 + i32(1);
        }
    }
    if(stemMode_0 == i32(1))
    {
        spacing_0 = maxPx_0;
    }
    else
    {
        spacing_0 = 1.60000002384185791f;
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        if(_S12)
        {
            axisAligned_0 = (policy_0.xAlign_0) != i32(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != i32(0);
        }
        if(!axisAligned_0)
        {
            _S11 = true;
        }
        else
        {
            _S11 = (blue_0[i_2]) < i32(0);
        }
        if(_S11)
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
            i_2 = i_2 + i32(1);
            continue;
        }
        var top_0 : bool = (dir_0[i_2]) > i32(0);
        var best_0 : i32 = companion_0[i_2];
        if((companion_0[i_2]) >= i32(0))
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
            if(best_0 == i32(-2))
            {
                bestGap_0 = 3.4028234663852886e+38f;
                b_0 = best_0;
                j_1 = i32(0);
                for(;;)
                {
                    if(j_1 < i32(32))
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
                        j_1 = j_1 + i32(1);
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
                        _S15 = true;
                    }
                    else
                    {
                        _S15 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S15)
                    {
                        j_1 = j_1 + i32(1);
                        continue;
                    }
                    bestGap_0 = widthUnits_0;
                    b_0 = j_1;
                    j_1 = j_1 + i32(1);
                }
            }
            else
            {
                b_0 = best_0;
                bestGap_0 = 3.4028234663852886e+38f;
            }
        }
        if(b_0 < i32(0))
        {
            bottomBlue_0 = true;
        }
        else
        {
            bottomBlue_0 = hinted_0[b_0];
        }
        if(bottomBlue_0)
        {
            _S15 = true;
        }
        else
        {
            _S15 = (blue_0[b_0]) >= i32(0);
        }
        if(_S15)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (bestGap_0 * scale_1) >= spacing_0;
        }
        if(lowerBlue_0)
        {
            i_2 = i_2 + i32(1);
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
        i_2 = i_2 + i32(1);
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
        if(_S12)
        {
            axisAligned_0 = (policy_0.xAlign_0) != i32(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != i32(0);
        }
        if(!hinted_0[i_2])
        {
            if(axisAligned_0)
            {
                _S11 = (blue_0[i_2]) >= i32(0);
            }
            else
            {
                _S11 = false;
            }
            _S11 = !_S11;
        }
        else
        {
            _S11 = false;
        }
        if(_S11)
        {
            i_2 = i_2 + i32(1);
            continue;
        }
        (*knotBase_0)[(*knotCount_0)] = pos_0[i_2];
        (*knotTarget_0)[(*knotCount_0)] = targets_0[i_2];
        if(axisAligned_0)
        {
            relative_0 = (blue_0[i_2]) >= i32(0);
        }
        else
        {
            relative_0 = false;
        }
        knotBlueFixed_0[(*knotCount_0)] = relative_0;
        knotNaturalSpacing_0[(*knotCount_0)] = syntheticApex_0[i_2];
        (*knotSource_0)[(*knotCount_0)] = i_2;
        (*knotCount_0) = (*knotCount_0) + i32(1);
        i_2 = i_2 + i32(1);
    }
    if(_S12)
    {
        _S11 = (policy_0.xRegistration_0) == i32(1);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = (*knotCount_0) > i32(0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = (*knotCount_0) < i32(32);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        _S11 = left_0 < ((*knotBase_0)[i32(0)] - 0.25f * grid_0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        i_2 = i32(31);
        for(;;)
        {
            if(i_2 > i32(0))
            {
            }
            else
            {
                break;
            }
            if(i_2 <= (*knotCount_0))
            {
                var _S34 : i32 = i_2 - i32(1);
                (*knotBase_0)[i_2] = (*knotBase_0)[_S34];
                (*knotTarget_0)[i_2] = (*knotTarget_0)[_S34];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S34];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S34];
                (*knotSource_0)[i_2] = (*knotSource_0)[_S34];
            }
            i_2 = i_2 - i32(1);
        }
        (*knotBase_0)[i32(0)] = left_0;
        (*knotTarget_0)[i32(0)] = snailAhSnap_0(left_0, scale_1);
        knotBlueFixed_0[i32(0)] = false;
        knotNaturalSpacing_0[i32(0)] = false;
        (*knotSource_0)[i32(0)] = i32(32);
        (*knotCount_0) = (*knotCount_0) + i32(1);
    }
    b_0 = i32(31);
    for(;;)
    {
        if(b_0 > i32(0))
        {
        }
        else
        {
            break;
        }
        if(b_0 >= (*knotCount_0))
        {
            _S11 = true;
        }
        else
        {
            _S11 = !knotBlueFixed_0[b_0];
        }
        if(_S11)
        {
            b_0 = b_0 - i32(1);
            continue;
        }
        j_1 = i32(31);
        for(;;)
        {
            if(j_1 > i32(0))
            {
            }
            else
            {
                break;
            }
            if(j_1 > b_0)
            {
                j_1 = j_1 - i32(1);
                continue;
            }
            var _S35 : i32 = j_1 - i32(1);
            if(knotBlueFixed_0[_S35])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S35])
            {
                spacing_0 = 9.99999997475242708e-07f;
            }
            else
            {
                spacing_0 = grid_0;
            }
            (*knotTarget_0)[_S35] = min((*knotTarget_0)[_S35], (*knotTarget_0)[j_1] - spacing_0);
            j_1 = j_1 - i32(1);
        }
        b_0 = b_0 - i32(1);
    }
    i_2 = i32(1);
    for(;;)
    {
        if(i_2 < i32(32))
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
        if(((*knotTarget_0)[i_2]) <= ((*knotTarget_0)[i_2 - i32(1)]))
        {
            (*knotTarget_0)[i_2] = (*knotTarget_0)[i_2 - i32(1)] + grid_0;
        }
        i_2 = i_2 + i32(1);
    }
    if((policy_0.fadeEnabled_0) != i32(0))
    {
        _S11 = scale_1 > (policy_0.fadeStart_0);
    }
    else
    {
        _S11 = false;
    }
    if(_S11)
    {
        var span_0 : f32 = policy_0.fadeFull_0 - policy_0.fadeStart_0;
        if(span_0 <= 0.0f)
        {
            _S11 = true;
        }
        else
        {
            _S11 = scale_1 >= (policy_0.fadeFull_0);
        }
        if(_S11)
        {
            spacing_0 = 1.0f;
        }
        else
        {
            spacing_0 = (scale_1 - policy_0.fadeStart_0) / span_0;
        }
        i_2 = i32(0);
        for(;;)
        {
            if(i_2 < i32(32))
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
            i_2 = i_2 + i32(1);
        }
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(32))
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
            _S11 = true;
        }
        else
        {
            _S11 = !snailAhFinite_0((*knotTarget_0)[i_2]);
        }
        if(_S11)
        {
            (*knotCount_0) = i32(0);
            return false;
        }
        i_2 = i_2 + i32(1);
    }
    return true;
}

fn snailInverseWarpAxis_0( count_3 : i32,  bases_0 : array<f32, i32(32)>,  targets_1 : array<f32, i32(32)>,  hinted_1 : f32,  invSlope_0 : ptr<function, f32>) -> f32
{
    (*invSlope_0) = 1.0f;
    if(count_3 == i32(0))
    {
        return hinted_1;
    }
    if(hinted_1 <= (targets_1[i32(0)]))
    {
        return bases_0[i32(0)] + hinted_1 - targets_1[i32(0)];
    }
    var _S36 : i32 = count_3 - i32(1);
    if(hinted_1 >= (targets_1[_S36]))
    {
        return bases_0[_S36] + hinted_1 - targets_1[_S36];
    }
    var lo_0 : i32;
    var i_4 : i32 = i32(0);
    for(;;)
    {
        if(i_4 < i32(31))
        {
        }
        else
        {
            lo_0 = i32(0);
            break;
        }
        var _S37 : i32 = i_4 + i32(1);
        var _S38 : bool;
        if(_S37 >= count_3)
        {
            _S38 = true;
        }
        else
        {
            _S38 = (targets_1[_S37]) >= hinted_1;
        }
        if(_S38)
        {
            lo_0 = i_4;
            break;
        }
        i_4 = _S37;
    }
    var _S39 : i32 = lo_0 + i32(1);
    var _S40 : i32 = lo_0;
    var dt_0 : f32 = targets_1[_S39] - targets_1[lo_0];
    var _S41 : i32 = lo_0;
    var db_0 : f32 = bases_0[_S39] - bases_0[lo_0];
    var _S42 : f32;
    if((abs(dt_0)) > 9.99999997475242708e-07f)
    {
        _S42 = db_0 / dt_0;
    }
    else
    {
        _S42 = 1.0f;
    }
    (*invSlope_0) = _S42;
    return bases_0[_S41] + (hinted_1 - targets_1[_S40]) * _S42;
}

fn snailAhFastTarget_0( values_0 : array<vec4<f32>, i32(4)>,  idx_1 : i32) -> f32
{
    return values_0[(idx_1 >> (u32(2)))][(idx_1 & (i32(3)))];
}

fn snailAhFastBase_0( layer_tex_3 : texture_2d<f32>,  info_base_2 : vec2<i32>,  run_1 : i32,  left_1 : f32,  sources_0 : vec4<u32>,  idx_2 : i32) -> f32
{
    var source_0 : u32 = snailAhFastSource_0(sources_0, idx_2);
    var _S43 : f32;
    if(source_0 == u32(32))
    {
        _S43 = left_1;
    }
    else
    {
        var _S44 : f32 = snailWarpF_0(layer_tex_3, info_base_2, run_1 + i32(1) + i32(4) * i32(source_0), i32(0));
        _S43 = _S44;
    }
    return _S43;
}

fn snailInverseFastAxis_0( layer_tex_4 : texture_2d<f32>,  info_base_3 : vec2<i32>,  count_4 : i32,  targets_2 : array<vec4<f32>, i32(4)>,  sources_1 : vec4<u32>,  run_2 : i32,  left_2 : f32,  hinted_2 : f32,  invSlope_1 : ptr<function, f32>) -> f32
{
    (*invSlope_1) = 1.0f;
    if(count_4 == i32(0))
    {
        return hinted_2;
    }
    var firstTarget_0 : f32 = snailAhFastTarget_0(targets_2, i32(0));
    var firstBase_0 : f32 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, i32(0));
    if(hinted_2 <= firstTarget_0)
    {
        return firstBase_0 + hinted_2 - firstTarget_0;
    }
    var _S45 : i32 = count_4 - i32(1);
    var lastTarget_0 : f32 = snailAhFastTarget_0(targets_2, _S45);
    var lastBase_0 : f32 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S45);
    if(hinted_2 >= lastTarget_0)
    {
        return lastBase_0 + hinted_2 - lastTarget_0;
    }
    var lo_1 : i32;
    var i_5 : i32 = i32(0);
    for(;;)
    {
        if(i_5 < i32(15))
        {
        }
        else
        {
            lo_1 = i32(0);
            break;
        }
        var _S46 : i32 = i_5 + i32(1);
        var _S47 : bool;
        if(_S46 >= count_4)
        {
            _S47 = true;
        }
        else
        {
            _S47 = (snailAhFastTarget_0(targets_2, _S46)) >= hinted_2;
        }
        if(_S47)
        {
            lo_1 = i_5;
            break;
        }
        i_5 = _S46;
    }
    var loTarget_0 : f32 = snailAhFastTarget_0(targets_2, lo_1);
    var _S48 : i32 = lo_1 + i32(1);
    var hiTarget_0 : f32 = snailAhFastTarget_0(targets_2, _S48);
    var loBase_0 : f32 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, lo_1);
    var hiBase_0 : f32 = snailAhFastBase_0(layer_tex_4, info_base_3, run_2, left_2, sources_1, _S48);
    var dt_1 : f32 = hiTarget_0 - loTarget_0;
    var db_1 : f32 = hiBase_0 - loBase_0;
    var _S49 : f32;
    if((abs(dt_1)) > 9.99999997475242708e-07f)
    {
        _S49 = db_1 / dt_1;
    }
    else
    {
        _S49 = 1.0f;
    }
    (*invSlope_1) = _S49;
    return loBase_0 + (hinted_2 - loTarget_0) * _S49;
}

struct CoverageBandSpan_0
{
     first_0 : i32,
     last_0 : i32,
};

fn CoverageBandSpan_x24init_0( first_1 : i32,  last_1 : i32) -> CoverageBandSpan_0
{
    var _S50 : CoverageBandSpan_0;
    _S50.first_0 = first_1;
    _S50.last_0 = last_1;
    return _S50;
}

fn computeCoverageBandSpan_0( coord_0 : f32,  eppAxis_0 : f32,  bandScale_0 : f32,  bandOffset_0 : f32,  bandMax_0 : i32) -> CoverageBandSpan_0
{
    var center_0 : f32 = coord_0 * bandScale_0 + bandOffset_0;
    var _S51 : f32 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    var first_2 : i32 = clamp(i32(center_0 - _S51), i32(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(i32(center_0 + _S51), i32(0), bandMax_0)));
}

fn calcBandLoc_0( glyphLoc_0 : vec2<i32>,  offset_1 : u32) -> vec2<i32>
{
    var _S52 : i32 = glyphLoc_0.x + i32(offset_1);
    var loc_0 : vec2<i32> = vec2<i32>(_S52, glyphLoc_0.y);
    loc_0[i32(1)] = loc_0[i32(1)] + ((_S52 >> (u32(12))));
    loc_0[i32(0)] = ((loc_0[i32(0)]) & (i32(4095)));
    return loc_0;
}

fn decodeBandCurveFirstMemberCommon_0( ref_2 : vec2<u32>) -> i32
{
    return i32(((ref_2.x) >> (u32(12))));
}

fn isCoverageBandSpanOwner_0( ref_3 : vec2<u32>,  band_0 : i32,  spanFirst_0 : i32) -> bool
{
    return band_0 == (max(decodeBandCurveFirstMemberCommon_0(ref_3), spanFirst_0));
}

fn decodeBandCurveLocCommon_0( ref_4 : vec2<u32>) -> vec2<i32>
{
    return vec2<i32>(i32(((ref_4.x) & (u32(4095)))), i32(((ref_4.y) & (u32(16383)))));
}

fn decodeBandCurveLoc_0( ref_5 : vec2<u32>) -> vec2<i32>
{
    return decodeBandCurveLocCommon_0(ref_5);
}

fn offsetCurveLoc_0( base_1 : vec2<i32>,  offset_2 : i32) -> vec2<i32>
{
    var _S53 : i32 = base_1.x + offset_2;
    var loc_1 : vec2<i32> = vec2<i32>(_S53, base_1.y);
    loc_1[i32(1)] = loc_1[i32(1)] + ((_S53 >> (u32(12))));
    loc_1[i32(0)] = ((loc_1[i32(0)]) & (i32(4095)));
    return loc_1;
}

fn rootCodeCoord_0( v_2 : f32) -> f32
{
    var _S54 : f32;
    if((abs(v_2)) <= 0.0000152587890625f)
    {
        _S54 = 0.0f;
    }
    else
    {
        _S54 = v_2;
    }
    return _S54;
}

fn calcRootCode_0( y1_0 : f32,  y2_0 : f32,  y3_0 : f32) -> u32
{
    return (((u32(11892) >> ((((((((bitcast<u32>((rootCodeCoord_0(y3_0)))) >> (u32(29)))) & (u32(4)))) | ((((((((((bitcast<u32>((rootCodeCoord_0(y2_0)))) >> (u32(30)))) & (u32(2)))) | ((((((bitcast<u32>((rootCodeCoord_0(y1_0)))) >> (u32(31)))) & (u32(4294967293))))))) & (u32(4294967291)))))))))) & (u32(257)));
}

fn snapNearTangentSqrt_0( disc_0 : f32,  b_1 : f32,  ac_0 : f32) -> f32
{
    var _S55 : f32;
    if(disc_0 <= (max(b_1 * b_1, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S55 = 0.0f;
    }
    else
    {
        _S55 = sqrt(disc_0);
    }
    return _S55;
}

fn solveHorizPoly_0( p12_0 : vec4<f32>,  p3_0 : vec2<f32>) -> vec2<f32>
{
    var _S56 : vec2<f32> = p12_0.xy;
    var _S57 : vec2<f32> = p12_0.zw;
    var a_0 : vec2<f32> = _S56 - _S57 * vec2<f32>(2.0f) + p3_0;
    var b_2 : vec2<f32> = _S56 - _S57;
    var _S58 : f32 = a_0.y;
    var t1_0 : f32;
    var t2_0 : f32;
    if((abs(_S58)) < 0.0000152587890625f)
    {
        var _S59 : f32 = b_2.y;
        if((abs(_S59)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S59;
        }
        t2_0 = t1_0;
    }
    else
    {
        var _S60 : f32 = b_2.y;
        var _S61 : f32 = p12_0.y;
        var _S62 : f32 = _S58 * _S61;
        var sq_0 : f32 = snapNearTangentSqrt_0(_S60 * _S60 - _S62, _S60, _S62);
        if(_S60 >= 0.0f)
        {
            var q_0 : f32 = _S60 + sq_0;
            var _S63 : f32 = q_0 / _S58;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S61 / q_0;
            }
            t2_0 = _S63;
        }
        else
        {
            var q_1 : f32 = _S60 - sq_0;
            var _S64 : f32 = q_1 / _S58;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S61 / q_1;
            }
            var _S65 : f32 = t1_0;
            t1_0 = _S64;
            t2_0 = _S65;
        }
    }
    var _S66 : f32 = a_0.x;
    var _S67 : f32 = b_2.x * 2.0f;
    var _S68 : f32 = p12_0.x;
    return vec2<f32>((_S66 * t1_0 - _S67) * t1_0 + _S68, (_S66 * t2_0 - _S67) * t2_0 + _S68);
}

fn accumulateHorizContribution_0( xcov_0 : ptr<function, f32>,  xwgt_0 : ptr<function, f32>,  rc_0 : vec2<f32>,  ppe_0 : vec2<f32>,  cLoc_0 : vec2<i32>,  texLayer_0 : i32,  curve_tex_0 : texture_2d_array<f32>) -> bool
{
    var _S69 : vec4<i32> = vec4<i32>(cLoc_0, texLayer_0, i32(0));
    var tex0_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S69)).xy, i32(((_S69)).z), ((_S69)).w));
    var _S70 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_0, i32(1)), texLayer_0, i32(0));
    var p12_1 : vec4<f32> = vec4<f32>(tex0_0.xy, tex0_0.zw) - vec4<f32>(rc_0, rc_0);
    var p3_1 : vec2<f32> = (textureLoad((curve_tex_0), ((_S70)).xy, i32(((_S70)).z), ((_S70)).w)).xy - rc_0;
    var _S71 : f32 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S71) < -0.5f)
    {
        return false;
    }
    var code_0 : u32 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != u32(0))
    {
        var r_0 : vec2<f32> = solveHorizPoly_0(p12_1, p3_1) * vec2<f32>(_S71);
        if(((code_0 & (u32(1)))) != u32(0))
        {
            var _S72 : f32 = r_0.x;
            (*xcov_0) = (*xcov_0) + clamp(_S72 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S72) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > u32(1))
        {
            var _S73 : f32 = r_0.y;
            (*xcov_0) = (*xcov_0) - clamp(_S73 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S73) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn solveVertPoly_0( p12_2 : vec4<f32>,  p3_2 : vec2<f32>) -> vec2<f32>
{
    var _S74 : vec2<f32> = p12_2.xy;
    var _S75 : vec2<f32> = p12_2.zw;
    var a_1 : vec2<f32> = _S74 - _S75 * vec2<f32>(2.0f) + p3_2;
    var b_3 : vec2<f32> = _S74 - _S75;
    var _S76 : f32 = a_1.x;
    var t1_1 : f32;
    var t2_1 : f32;
    if((abs(_S76)) < 0.0000152587890625f)
    {
        var _S77 : f32 = b_3.x;
        if((abs(_S77)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S77;
        }
        t2_1 = t1_1;
    }
    else
    {
        var _S78 : f32 = b_3.x;
        var _S79 : f32 = p12_2.x;
        var _S80 : f32 = _S76 * _S79;
        var sq_1 : f32 = snapNearTangentSqrt_0(_S78 * _S78 - _S80, _S78, _S80);
        if(_S78 >= 0.0f)
        {
            var q_2 : f32 = _S78 + sq_1;
            var _S81 : f32 = q_2 / _S76;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S79 / q_2;
            }
            t2_1 = _S81;
        }
        else
        {
            var q_3 : f32 = _S78 - sq_1;
            var _S82 : f32 = q_3 / _S76;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S79 / q_3;
            }
            var _S83 : f32 = t1_1;
            t1_1 = _S82;
            t2_1 = _S83;
        }
    }
    var _S84 : f32 = a_1.y;
    var _S85 : f32 = b_3.y * 2.0f;
    var _S86 : f32 = p12_2.y;
    return vec2<f32>((_S84 * t1_1 - _S85) * t1_1 + _S86, (_S84 * t2_1 - _S85) * t2_1 + _S86);
}

fn accumulateVertContribution_0( ycov_0 : ptr<function, f32>,  ywgt_0 : ptr<function, f32>,  rc_1 : vec2<f32>,  ppe_1 : vec2<f32>,  cLoc_1 : vec2<i32>,  texLayer_1 : i32,  curve_tex_1 : texture_2d_array<f32>) -> bool
{
    var _S87 : vec4<i32> = vec4<i32>(cLoc_1, texLayer_1, i32(0));
    var tex0_1 : vec4<f32> = (textureLoad((curve_tex_1), ((_S87)).xy, i32(((_S87)).z), ((_S87)).w));
    var _S88 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_1, i32(1)), texLayer_1, i32(0));
    var p12_3 : vec4<f32> = vec4<f32>(tex0_1.xy, tex0_1.zw) - vec4<f32>(rc_1, rc_1);
    var p3_3 : vec2<f32> = (textureLoad((curve_tex_1), ((_S88)).xy, i32(((_S88)).z), ((_S88)).w)).xy - rc_1;
    var _S89 : f32 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S89) < -0.5f)
    {
        return false;
    }
    var code_1 : u32 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != u32(0))
    {
        var r_1 : vec2<f32> = solveVertPoly_0(p12_3, p3_3) * vec2<f32>(_S89);
        if(((code_1 & (u32(1)))) != u32(0))
        {
            var _S90 : f32 = r_1.x;
            (*ycov_0) = (*ycov_0) - clamp(_S90 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S90) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > u32(1))
        {
            var _S91 : f32 = r_1.y;
            (*ycov_0) = (*ycov_0) + clamp(_S91 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S91) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn applyFillRule_0( winding_0 : f32,  fill_rule_mode_0 : i32) -> f32
{
    if(fill_rule_mode_0 == i32(1))
    {
        return 1.0f - abs(fract(winding_0 * 0.5f) * 2.0f - 1.0f);
    }
    return abs(winding_0);
}

fn applyCoverageTransfer_0( cov_0 : f32,  coverage_exponent_1 : f32) -> f32
{
    var clamped_0 : f32 = clamp(cov_0, 0.0f, 1.0f);
    var _S92 : f32 = max(coverage_exponent_1, 0.0000152587890625f);
    var _S93 : f32;
    if((abs(_S92 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S93 = clamped_0;
    }
    else
    {
        _S93 = pow(clamped_0, _S92);
    }
    return _S93;
}

fn evalGlyphCoverage_0( rc_2 : vec2<f32>,  epp_0 : vec2<f32>,  ppe_2 : vec2<f32>,  gLoc_0 : vec2<i32>,  bandMax_1 : vec2<i32>,  banding_0 : vec4<f32>,  texLayer_2 : i32,  curve_tex_2 : texture_2d_array<f32>,  band_tex_0 : texture_2d_array<u32>,  coverage_exponent_2 : f32) -> f32
{
    var _S94 : bool;
    var i_6 : i32;
    var _S95 : i32 = bandMax_1.y;
    var hSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S95);
    var vSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    var xcov_1 : f32 = 0.0f;
    var xwgt_1 : f32 = 0.0f;
    var _S96 : bool = (hSpan_0.first_0) != (hSpan_0.last_0);
    var band_1 : i32 = hSpan_0.first_0;
    for(;;)
    {
        if(band_1 <= (hSpan_0.last_0))
        {
        }
        else
        {
            break;
        }
        var _S97 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(band_1)), texLayer_2, i32(0));
        var hbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S97)).xy, i32(((_S97)).z), ((_S97)).w).xy).xy;
        var _S98 : vec2<i32> = calcBandLoc_0(gLoc_0, hbd_0.y);
        var _S99 : i32 = i32(hbd_0.x);
        i_6 = i32(0);
        for(;;)
        {
            if(i_6 < _S99)
            {
            }
            else
            {
                break;
            }
            var _S100 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S98, u32(i_6)), texLayer_2, i32(0));
            var ref_6 : vec2<u32> = (textureLoad((band_tex_0), ((_S100)).xy, i32(((_S100)).z), ((_S100)).w).xy).xy;
            if(_S96)
            {
                _S94 = !isCoverageBandSpanOwner_0(ref_6, band_1, hSpan_0.first_0);
            }
            else
            {
                _S94 = false;
            }
            if(_S94)
            {
                i_6 = i_6 + i32(1);
                continue;
            }
            var _S101 : bool = accumulateHorizContribution_0(&(xcov_1), &(xwgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_6), texLayer_2, curve_tex_2);
            if(!_S101)
            {
                break;
            }
            i_6 = i_6 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    var ycov_1 : f32 = 0.0f;
    var ywgt_1 : f32 = 0.0f;
    var _S102 : bool = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        var _S103 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(_S95 + i32(1) + band_1)), texLayer_2, i32(0));
        var vbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S103)).xy, i32(((_S103)).z), ((_S103)).w).xy).xy;
        var _S104 : vec2<i32> = calcBandLoc_0(gLoc_0, vbd_0.y);
        var _S105 : i32 = i32(vbd_0.x);
        i_6 = i32(0);
        for(;;)
        {
            if(i_6 < _S105)
            {
            }
            else
            {
                break;
            }
            var _S106 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S104, u32(i_6)), texLayer_2, i32(0));
            var ref_7 : vec2<u32> = (textureLoad((band_tex_0), ((_S106)).xy, i32(((_S106)).z), ((_S106)).w).xy).xy;
            if(_S102)
            {
                _S94 = !isCoverageBandSpanOwner_0(ref_7, band_1, vSpan_0.first_0);
            }
            else
            {
                _S94 = false;
            }
            if(_S94)
            {
                i_6 = i_6 + i32(1);
                continue;
            }
            var _S107 : bool = accumulateVertContribution_0(&(ycov_1), &(ywgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_7), texLayer_2, curve_tex_2);
            if(!_S107)
            {
                break;
            }
            i_6 = i_6 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), i32(0)), min(applyFillRule_0(xcov_1, i32(0)), applyFillRule_0(ycov_1, i32(0)))), coverage_exponent_2);
}

fn premultiplyColor_0( color_0 : vec4<f32>,  cov_1 : f32) -> vec4<f32>
{
    var alpha_0 : f32 = color_0.w * cov_1;
    return vec4<f32>(color_0.xyz * vec3<f32>(alpha_0), alpha_0);
}

fn srgbEncode_0( c_1 : f32) -> f32
{
    var _S108 : f32;
    if(c_1 <= 0.00313080009073019f)
    {
        _S108 = c_1 * 12.92000007629394531f;
    }
    else
    {
        _S108 = 1.0549999475479126f * pow(c_1, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S108;
}

fn linearToSrgb_0( color_1 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

fn srgbEncodePremultiplied_0( premul_0 : vec4<f32>) -> vec4<f32>
{
    var _S109 : f32 = premul_0.w;
    if(_S109 <= 0.0f)
    {
        return vec4<f32>(0.0f);
    }
    return vec4<f32>(linearToSrgb_0(premul_0.xyz * vec3<f32>((1.0f / _S109))) * vec3<f32>(_S109), _S109);
}

struct AutohintVaryings_0
{
     paint_0 : vec4<f32>,
     texcoord_layer_0 : vec3<f32>,
     info_0 : vec2<i32>,
     policy0_0 : vec4<u32>,
     policy1_0 : vec3<u32>,
     x_targets_0 : array<vec4<f32>, i32(4)>,
     y_targets_0 : array<vec4<f32>, i32(4)>,
     x_sources_0 : vec4<u32>,
     y_sources_0 : vec4<u32>,
};

fn snailAutohintFragment_0( v_3 : AutohintVaryings_0,  curve_tex_3 : texture_2d_array<f32>,  band_tex_1 : texture_2d_array<u32>,  layer_tex_5 : texture_2d<f32>,  layer_base_1 : i32,  output_srgb_1 : i32,  coverage_exponent_3 : f32,  mask_output_1 : i32) -> vec4<f32>
{
    var _S110 : vec3<i32> = vec3<i32>(v_3.info_0, i32(0));
    var h0_0 : vec4<f32> = (textureLoad((layer_tex_5), ((_S110)).xy, ((_S110)).z));
    var _S111 : vec2<i32> = snailAhLayerLoc_0(layer_tex_5, v_3.info_0, i32(1));
    var _S112 : vec3<i32> = vec3<i32>(_S111, i32(0));
    var h1_0 : vec4<f32> = (textureLoad((layer_tex_5), ((_S112)).xy, ((_S112)).z));
    var gLoc_1 : vec2<i32> = vec2<i32>(i32(h0_0.x + 0.5f), i32(h0_0.y + 0.5f));
    var packedBands_0 : i32 = (bitcast<i32>((h0_0.z)));
    var bandMaxH_0 : i32 = (packedBands_0 & (i32(65535)));
    var bandMaxV_0 : i32 = (((packedBands_0 >> (u32(16)))) & (i32(65535)));
    var texLayer_3 : i32 = layer_base_1 + i32(v_3.texcoord_layer_0.z);
    var _S113 : vec2<f32> = v_3.texcoord_layer_0.xy;
    var rc_3 : vec2<f32> = _S113;
    var epp_1 : vec2<f32> = (fwidth((_S113)));
    var _S114 : f32 = 1.0f / epp_1.x;
    var _S115 : f32 = 1.0f / epp_1.y;
    var blueCount_1 : i32 = i32(0);
    var featureXCount_0 : i32 = i32(0);
    var featureYCount_0 : i32 = i32(0);
    var _S116 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, i32(0), i32(10));
    var valid_0 : bool = snailAhCount_0(i32(32), _S116, &(blueCount_1));
    var xRun_0 : i32 = i32(12) + i32(2) * blueCount_1;
    var valid_1 : bool;
    if(valid_0)
    {
        var _S117 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, xRun_0, i32(0));
        var _S118 : bool = snailAhCount_0(i32(32), _S117, &(featureXCount_0));
        valid_1 = _S118;
    }
    else
    {
        valid_1 = false;
    }
    var yRun_0 : i32 = xRun_0 + i32(1) + i32(4) * featureXCount_0;
    if(valid_1)
    {
        var _S119 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, yRun_0, i32(0));
        valid_1 = snailAhCount_0(i32(32), _S119, &(featureYCount_0));
    }
    else
    {
        valid_1 = false;
    }
    var xCount_0 : i32;
    var _S120 : i32;
    if(valid_1)
    {
        _S120 = snailAhFastCount_0(v_3.x_sources_0);
    }
    else
    {
        _S120 = i32(0);
    }
    xCount_0 = _S120;
    var yCount_0 : i32;
    if(valid_1)
    {
        _S120 = snailAhFastCount_0(v_3.y_sources_0);
    }
    else
    {
        _S120 = i32(0);
    }
    yCount_0 = _S120;
    var slopeX_0 : f32 = 1.0f;
    var slopeY_0 : f32 = 1.0f;
    var fallbackX_0 : bool = xCount_0 < i32(0);
    var fallbackY_0 : bool = _S120 < i32(0);
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
        var stdX_0 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, i32(0), i32(8));
        var stdY_0 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, i32(0), i32(9));
        var policy_1 : SnailAutohintPolicy_0;
        var _S121 : bool = snailDecodeAutohintPolicy_0(v_3.policy0_0, v_3.policy1_0, &(policy_1));
        if(_S121)
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
        var _S122 : bool;
        if(valid_1)
        {
            _S122 = fallbackX_0;
        }
        else
        {
            _S122 = false;
        }
        if(_S122)
        {
            var _S123 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, i32(0), i32(11));
            var bases_1 : array<f32, i32(32)>;
            var targets_3 : array<f32, i32(32)>;
            var sources_2 : array<i32, i32(32)>;
            var fitValid_0 : bool = snailFitAutohintAxis_0(layer_tex_5, v_3.info_0, i32(0), xRun_0, blueCount_1, stdX_0, _S123, _S114, policy_1, &(xCount_0), &(bases_1), &(targets_3), &(sources_2));
            if(!fitValid_0)
            {
                xCount_0 = i32(0);
            }
            var _S124 : f32 = snailInverseWarpAxis_0(xCount_0, bases_1, targets_3, rc_3.x, &(slopeX_0));
            rc_3[i32(0)] = _S124;
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
            var bases_2 : array<f32, i32(32)>;
            var targets_4 : array<f32, i32(32)>;
            var sources_3 : array<i32, i32(32)>;
            var fitValid_1 : bool = snailFitAutohintAxis_0(layer_tex_5, v_3.info_0, i32(1), yRun_0, blueCount_1, stdY_0, 0.0f, _S115, policy_1, &(yCount_0), &(bases_2), &(targets_4), &(sources_3));
            if(!fitValid_1)
            {
                yCount_0 = i32(0);
            }
            var _S125 : f32 = snailInverseWarpAxis_0(yCount_0, bases_2, targets_4, rc_3.y, &(slopeY_0));
            rc_3[i32(1)] = _S125;
        }
    }
    if(!fallbackX_0)
    {
        var _S126 : f32 = snailWarpF_0(layer_tex_5, v_3.info_0, i32(0), i32(11));
        var _S127 : f32 = snailInverseFastAxis_0(layer_tex_5, v_3.info_0, xCount_0, v_3.x_targets_0, v_3.x_sources_0, xRun_0, _S126, rc_3.x, &(slopeX_0));
        rc_3[i32(0)] = _S127;
    }
    if(!fallbackY_0)
    {
        var _S128 : f32 = snailInverseFastAxis_0(layer_tex_5, v_3.info_0, yCount_0, v_3.y_targets_0, v_3.y_sources_0, yRun_0, 0.0f, rc_3.y, &(slopeY_0));
        rc_3[i32(1)] = _S128;
    }
    var epp_2 : vec2<f32> = epp_1 * vec2<f32>(slopeX_0, slopeY_0);
    var cov_2 : f32 = evalGlyphCoverage_0(rc_3, epp_2, vec2<f32>(1.0f / max(epp_2.x, 0.0000152587890625f), 1.0f / max(epp_2.y, 0.0000152587890625f)), gLoc_1, vec2<i32>(bandMaxV_0, bandMaxH_0), h1_0, texLayer_3, curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    var premul_1 : vec4<f32> = premultiplyColor_0(v_3.paint_0, cov_2);
    var _S129 : vec4<f32>;
    if(mask_output_1 != i32(0))
    {
        _S129 = vec4<f32>(premul_1.w);
    }
    else
    {
        if(output_srgb_1 != i32(0))
        {
            _S129 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S129 = premul_1;
        }
    }
    return _S129;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) paint_1 : vec4<f32>,
    @location(1) texcoord_layer_1 : vec3<f32>,
    @interpolate(flat) @location(2) info_1 : vec2<i32>,
    @interpolate(flat) @location(3) policy0_1 : vec4<u32>,
    @interpolate(flat) @location(4) policy1_1 : vec3<u32>,
    @interpolate(flat) @location(5) x_targets0_0 : vec4<f32>,
    @interpolate(flat) @location(6) x_targets1_0 : vec4<f32>,
    @interpolate(flat) @location(7) x_targets2_0 : vec4<f32>,
    @interpolate(flat) @location(8) x_targets3_0 : vec4<f32>,
    @interpolate(flat) @location(9) y_targets0_0 : vec4<f32>,
    @interpolate(flat) @location(10) y_targets1_0 : vec4<f32>,
    @interpolate(flat) @location(11) y_targets2_0 : vec4<f32>,
    @interpolate(flat) @location(12) y_targets3_0 : vec4<f32>,
    @interpolate(flat) @location(13) x_sources_1 : vec4<u32>,
    @interpolate(flat) @location(14) y_sources_1 : vec4<u32>,
};

@fragment
fn fragmentMain( _S130 : pixelInput_0, @builtin(position) position_0 : vec4<f32>) -> pixelOutput_0
{
    var v_4 : AutohintVaryings_0;
    v_4.paint_0 = _S130.paint_1;
    v_4.texcoord_layer_0 = _S130.texcoord_layer_1;
    v_4.info_0 = _S130.info_1;
    v_4.policy0_0 = _S130.policy0_1;
    v_4.policy1_0 = _S130.policy1_1;
    v_4.x_targets_0[i32(0)] = _S130.x_targets0_0;
    v_4.x_targets_0[i32(1)] = _S130.x_targets1_0;
    v_4.x_targets_0[i32(2)] = _S130.x_targets2_0;
    v_4.x_targets_0[i32(3)] = _S130.x_targets3_0;
    v_4.y_targets_0[i32(0)] = _S130.y_targets0_0;
    v_4.y_targets_0[i32(1)] = _S130.y_targets1_0;
    v_4.y_targets_0[i32(2)] = _S130.y_targets2_0;
    v_4.y_targets_0[i32(3)] = _S130.y_targets3_0;
    v_4.x_sources_0 = _S130.x_sources_1;
    v_4.y_sources_0 = _S130.y_sources_1;
    var _S131 : vec4<f32> = snailAutohintFragment_0(v_4, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    var _S132 : pixelOutput_0 = pixelOutput_0( _S131 );
    return _S132;
}

