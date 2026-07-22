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
@binding(2) @group(0) var u_layer_tex_0 : texture_2d<f32>;

const kCorners_0 : array<vec2<f32>, i32(4)> = array<vec2<f32>, i32(4)>( vec2<f32>(0.0f, 0.0f), vec2<f32>(1.0f, 0.0f), vec2<f32>(1.0f, 1.0f), vec2<f32>(0.0f, 1.0f) );
fn srgbDecode_0( c_0 : f32) -> f32
{
    var _S1 : f32;
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

fn srgbToLinear_0( color_0 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbDecode_0(color_0.x), srgbDecode_0(color_0.y), srgbDecode_0(color_0.z));
}

fn snailVertexDilationScale_0( subpixel_order_1 : i32) -> f32
{
    var _S2 : f32;
    if(subpixel_order_1 == i32(0))
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
     position_0 : vec4<f32>,
     color_1 : vec4<f32>,
     tint_0 : vec4<f32>,
     texcoord_0 : vec2<f32>,
     banding_0 : vec4<f32>,
     glyph_0 : vec4<i32>,
};

struct TextVertexIn_0
{
     rect_0 : vec4<f32>,
     xform_0 : vec4<f32>,
     origin_0 : vec2<f32>,
     glyph_1 : vec2<u32>,
     bnd_0 : vec4<f32>,
     col_0 : vec4<f32>,
     tint_1 : vec4<f32>,
};

fn snailTextVertex_0( input_0 : TextVertexIn_0,  vertex_index_0 : u32,  mvp_1 : mat4x4<f32>,  viewport_1 : vec2<f32>,  subpixel_order_2 : i32) -> TextVertexResult_0
{
    var em_0 : vec2<f32> = mix(input_0.rect_0.xy, input_0.rect_0.zw, kCorners_0[vertex_index_0]);
    var _S3 : vec2<f32> = vec2<f32>(2.0f);
    var nd_0 : vec2<f32> = kCorners_0[vertex_index_0] * _S3 - vec2<f32>(1.0f);
    var _S4 : f32 = input_0.xform_0.x;
    var _S5 : f32 = em_0.x;
    var _S6 : f32 = input_0.xform_0.y;
    var _S7 : f32 = em_0.y;
    var _S8 : f32 = input_0.xform_0.z;
    var _S9 : f32 = input_0.xform_0.w;
    var pos_0 : vec2<f32> = vec2<f32>(_S4 * _S5 + _S6 * _S7 + input_0.origin_0.x, _S8 * _S5 + _S9 * _S7 + input_0.origin_0.y);
    var _S10 : f32 = nd_0.x;
    var _S11 : f32 = nd_0.y;
    var wn_0 : vec2<f32> = vec2<f32>(_S4 * _S10 + _S6 * _S11, _S8 * _S10 + _S9 * _S11);
    var inv_det_0 : f32 = 1.0f / (_S4 * _S9 - _S6 * _S8);
    var _S12 : f32 = _S9 * inv_det_0;
    var _S13 : f32 = - _S6 * inv_det_0;
    var _S14 : f32 = - _S8 * inv_det_0;
    var _S15 : f32 = _S4 * inv_det_0;
    var gz_0 : u32 = input_0.glyph_1.x;
    var gw_0 : u32 = input_0.glyph_1.y;
    var r_0 : TextVertexResult_0;
    r_0.glyph_0 = vec4<i32>(i32((gz_0 & (u32(65535)))), i32((gz_0 >> (u32(16)))), i32((gw_0 & (u32(65535)))), i32((gw_0 >> (u32(16)))));
    r_0.banding_0 = input_0.bnd_0;
    r_0.color_1 = vec4<f32>(srgbToLinear_0(input_0.col_0.xyz), input_0.col_0.w);
    r_0.tint_0 = vec4<f32>(srgbToLinear_0(input_0.tint_1.xyz), input_0.tint_1.w);
    var n_0 : vec2<f32> = normalize(wn_0);
    var _S16 : vec2<f32> = mvp_1[i32(3)].xy;
    var s_0 : f32 = dot(_S16, pos_0) + mvp_1[i32(3)].w;
    var t_val_0 : f32 = dot(_S16, n_0);
    var _S17 : vec2<f32> = mvp_1[i32(0)].xy;
    var u_val_0 : f32 = (s_0 * dot(_S17, n_0) - t_val_0 * (dot(_S17, pos_0) + mvp_1[i32(0)].w)) * viewport_1.x;
    var _S18 : vec2<f32> = mvp_1[i32(1)].xy;
    var v_val_0 : f32 = (s_0 * dot(_S18, n_0) - t_val_0 * (dot(_S18, pos_0) + mvp_1[i32(1)].w)) * viewport_1.y;
    var s2_0 : f32 = s_0 * s_0;
    var st_0 : f32 = s_0 * t_val_0;
    var uv_0 : f32 = u_val_0 * u_val_0 + v_val_0 * v_val_0;
    var denom_0 : f32 = uv_0 - st_0 * st_0;
    var d_0 : vec2<f32>;
    if((abs(denom_0)) > 1.00000001335143196e-10f)
    {
        d_0 = n_0 * vec2<f32>((s2_0 * (st_0 + sqrt(uv_0)) / denom_0));
    }
    else
    {
        d_0 = n_0 * _S3 / viewport_1;
    }
    var d_1 : vec2<f32> = d_0 * vec2<f32>(snailVertexDilationScale_0(subpixel_order_2));
    var p_0 : vec2<f32> = pos_0 + d_1;
    r_0.texcoord_0 = vec2<f32>(_S5 + dot(d_1, vec2<f32>(_S12, _S13)), _S7 + dot(d_1, vec2<f32>(_S14, _S15)));
    r_0.position_0 = (((vec4<f32>(p_0, 0.0f, 1.0f)) * (mvp_1)));
    return r_0;
}

fn snailAhFinite_0( v_0 : f32) -> bool
{
    return (abs(v_0)) <= 3.40282306073709653e+38f;
}

fn snailAhAffineScale_0( mvp_2 : mat4x4<f32>,  viewport_2 : vec2<f32>,  xform_1 : vec4<f32>,  scale_0 : ptr<function, vec2<f32>>) -> bool
{
    (*scale_0) = vec2<f32>(0.0f, 0.0f);
    var _S19 : bool;
    if((abs(mvp_2[i32(3)].x)) > 1.00000001168609742e-07f)
    {
        _S19 = true;
    }
    else
    {
        _S19 = (abs(mvp_2[i32(3)].y)) > 1.00000001168609742e-07f;
    }
    if(_S19)
    {
        _S19 = true;
    }
    else
    {
        _S19 = !snailAhFinite_0(mvp_2[i32(3)].w);
    }
    if(_S19)
    {
        _S19 = true;
    }
    else
    {
        _S19 = (abs(mvp_2[i32(3)].w)) < 1.00000001335143196e-10f;
    }
    if(_S19)
    {
        return false;
    }
    var localX_0 : vec2<f32> = vec2<f32>(xform_1.x, xform_1.z);
    var localY_0 : vec2<f32> = vec2<f32>(xform_1.y, xform_1.w);
    var _S20 : vec2<f32> = vec2<f32>(0.5f) * viewport_2;
    var _S21 : vec2<f32> = mvp_2[i32(0)].xy;
    var _S22 : vec2<f32> = mvp_2[i32(1)].xy;
    var _S23 : vec2<f32> = vec2<f32>(mvp_2[i32(3)].w);
    var screenX_0 : vec2<f32> = _S20 * vec2<f32>(dot(_S21, localX_0), dot(_S22, localX_0)) / _S23;
    var screenY_0 : vec2<f32> = _S20 * vec2<f32>(dot(_S21, localY_0), dot(_S22, localY_0)) / _S23;
    var _S24 : f32 = screenX_0.x;
    var _S25 : f32 = screenY_0.y;
    var _S26 : f32 = screenY_0.x;
    var _S27 : f32 = screenX_0.y;
    var det_0 : f32 = _S24 * _S25 - _S26 * _S27;
    if(!snailAhFinite_0(det_0))
    {
        _S19 = true;
    }
    else
    {
        _S19 = (abs(det_0)) < 1.00000001335143196e-10f;
    }
    if(_S19)
    {
        return false;
    }
    var _S28 : f32 = abs(det_0);
    var _S29 : vec2<f32> = vec2<f32>(1.0f) / vec2<f32>((abs(_S25) + abs(_S26)) / _S28, (abs(_S27) + abs(_S24)) / _S28);
    (*scale_0) = _S29;
    if(snailAhFinite_0(_S29.x))
    {
        _S19 = snailAhFinite_0((*scale_0).y);
    }
    else
    {
        _S19 = false;
    }
    if(_S19)
    {
        _S19 = ((*scale_0).x) > 0.0f;
    }
    else
    {
        _S19 = false;
    }
    if(_S19)
    {
        _S19 = ((*scale_0).y) > 0.0f;
    }
    else
    {
        _S19 = false;
    }
    return _S19;
}

fn snailAhMarkFallback_0( packedTargets_0 : ptr<function, array<vec4<f32>, i32(4)>>,  packedSources_0 : ptr<function, vec4<u32>>)
{
    var i_0 : i32 = i32(0);
    for(;;)
    {
        if(i_0 < i32(4))
        {
        }
        else
        {
            break;
        }
        (*packedTargets_0)[i_0] = vec4<f32>(0.0f);
        i_0 = i_0 + i32(1);
    }
    var _S30 : vec4<u32> = vec4<u32>(u32(4294967295));
    (*packedSources_0) = _S30;
    (*packedSources_0)[i32(0)] = ((((_S30.x) & (u32(4294967040)))) | (u32(254)));
    return;
}

fn snailAhLayerLoc_0( layer_tex_0 : texture_2d<f32>,  base_0 : vec2<i32>,  offset_0 : i32) -> vec2<i32>
{
    var uw_0 : u32;
    var uh_0 : u32;
    {var dim = textureDimensions((layer_tex_0));((uw_0)) = dim.x;((uh_0)) = dim.y;};
    var width_0 : i32 = i32(uw_0);
    var texel_0 : i32 = base_0.y * width_0 + base_0.x + offset_0;
    var _S31 : i32 = texel_0 % width_0;
    var _S32 : i32 = texel_0 / width_0;
    return vec2<i32>(_S31, _S32);
}

fn snailWarpF_0( layer_tex_1 : texture_2d<f32>,  info_base_0 : vec2<i32>,  block_0 : i32,  i_1 : i32) -> f32
{
    var f_0 : i32 = block_0 + i_1;
    var _S33 : vec2<i32> = snailAhLayerLoc_0(layer_tex_1, info_base_0, (f_0 >> (u32(2))));
    var _S34 : vec3<i32> = vec3<i32>(_S33, i32(0));
    var t_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S34)).xy, ((_S34)).z));
    var c_1 : i32 = (f_0 & (i32(3)));
    var _S35 : f32;
    if(c_1 == i32(0))
    {
        _S35 = t_0.x;
    }
    else
    {
        if(c_1 == i32(1))
        {
            _S35 = t_0.y;
        }
        else
        {
            if(c_1 == i32(2))
            {
                _S35 = t_0.z;
            }
            else
            {
                _S35 = t_0.w;
            }
        }
    }
    return _S35;
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

fn snailDecodeAutohintPolicy_0( p0_0 : vec4<u32>,  p1_0 : vec3<u32>,  p_1 : ptr<function, SnailAutohintPolicy_0>) -> bool
{
    (*p_1).xAlign_0 = i32(0);
    (*p_1).xStem_0 = i32(0);
    (*p_1).xPositioning_0 = i32(0);
    (*p_1).xRegistration_0 = i32(0);
    (*p_1).yAlign_0 = i32(0);
    (*p_1).yStem_0 = i32(0);
    (*p_1).yOvershoot_0 = i32(0);
    (*p_1).fadeEnabled_0 = i32(0);
    (*p_1).fadeStart_0 = 0.0f;
    (*p_1).fadeFull_0 = 0.0f;
    (*p_1).xRatio_0 = 0.0f;
    (*p_1).xMaxPx_0 = 0.0f;
    (*p_1).yRatio_0 = 0.0f;
    (*p_1).yMaxPx_0 = 0.0f;
    (*p_1).overshootMinPx_0 = 0.0f;
    var x_0 : u32 = p0_0.x;
    var y_0 : u32 = p0_0.y;
    var _S36 : bool;
    if(((x_0 & (u32(4286578688)))) != u32(0))
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((y_0 & (u32(4294967232)))) != u32(0);
    }
    if(_S36)
    {
        return false;
    }
    var _S37 : i32 = i32((x_0 & (u32(3))));
    (*p_1).xAlign_0 = _S37;
    (*p_1).xStem_0 = i32((((x_0 >> (u32(2)))) & (u32(3))));
    (*p_1).xPositioning_0 = i32((((x_0 >> (u32(4)))) & (u32(3))));
    (*p_1).xRegistration_0 = i32((((x_0 >> (u32(6)))) & (u32(3))));
    (*p_1).fadeEnabled_0 = i32((((x_0 >> (u32(8)))) & (u32(1))));
    (*p_1).fadeStart_0 = f32((((x_0 >> (u32(9)))) & (u32(127))));
    (*p_1).fadeFull_0 = f32((((x_0 >> (u32(16)))) & (u32(127))));
    (*p_1).yAlign_0 = i32((y_0 & (u32(3))));
    (*p_1).yStem_0 = i32((((y_0 >> (u32(2)))) & (u32(3))));
    (*p_1).yOvershoot_0 = i32((((y_0 >> (u32(4)))) & (u32(3))));
    if(_S37 > i32(1))
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).xStem_0) > i32(2);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).xPositioning_0) > i32(1);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).xRegistration_0) > i32(1);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).yAlign_0) > i32(2);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).yStem_0) > i32(2);
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        _S36 = ((*p_1).yOvershoot_0) > i32(1);
    }
    if(_S36)
    {
        return false;
    }
    (*p_1).xRatio_0 = (bitcast<f32>((p0_0.z)));
    (*p_1).xMaxPx_0 = (bitcast<f32>((p0_0.w)));
    (*p_1).yRatio_0 = (bitcast<f32>((p1_0.x)));
    (*p_1).yMaxPx_0 = (bitcast<f32>((p1_0.y)));
    (*p_1).overshootMinPx_0 = (bitcast<f32>((p1_0.z)));
    if(((*p_1).xStem_0) != i32(0))
    {
        if(!snailAhFinite_0((*p_1).xRatio_0))
        {
            _S36 = true;
        }
        else
        {
            _S36 = ((*p_1).xRatio_0) < 0.0f;
        }
    }
    else
    {
        _S36 = false;
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).xStem_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_1).xMaxPx_0))
            {
                _S36 = true;
            }
            else
            {
                _S36 = ((*p_1).xMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).yStem_0) != i32(0))
        {
            if(!snailAhFinite_0((*p_1).yRatio_0))
            {
                _S36 = true;
            }
            else
            {
                _S36 = ((*p_1).yRatio_0) < 0.0f;
            }
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).yStem_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_1).yMaxPx_0))
            {
                _S36 = true;
            }
            else
            {
                _S36 = ((*p_1).yMaxPx_0) < 0.0f;
            }
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).yOvershoot_0) == i32(1))
        {
            if(!snailAhFinite_0((*p_1).overshootMinPx_0))
            {
                _S36 = true;
            }
            else
            {
                _S36 = ((*p_1).overshootMinPx_0) < 0.0f;
            }
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).xPositioning_0) == i32(1))
        {
            _S36 = ((*p_1).xAlign_0) == i32(0);
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        _S36 = true;
    }
    else
    {
        if(((*p_1).yOvershoot_0) == i32(1))
        {
            _S36 = ((*p_1).yAlign_0) != i32(2);
        }
        else
        {
            _S36 = false;
        }
    }
    if(_S36)
    {
        return false;
    }
    return true;
}

fn snailAhCount_0( max_knots_0 : i32,  encoded_0 : f32,  count_0 : ptr<function, i32>) -> bool
{
    var _S38 : bool;
    if(!snailAhFinite_0(encoded_0))
    {
        _S38 = true;
    }
    else
    {
        _S38 = encoded_0 < 0.0f;
    }
    if(_S38)
    {
        _S38 = true;
    }
    else
    {
        _S38 = encoded_0 > f32(max_knots_0);
    }
    if(_S38)
    {
        _S38 = true;
    }
    else
    {
        _S38 = (floor(encoded_0)) != encoded_0;
    }
    if(_S38)
    {
        (*count_0) = i32(0);
        return false;
    }
    (*count_0) = i32(encoded_0);
    return true;
}

fn snailAhSnap_0( v_1 : f32,  scale_1 : f32) -> f32
{
    return round(v_1 * scale_1) / scale_1;
}

fn snailAhStandardWidth_0( raw_0 : f32,  standard_0 : f32,  ratio_0 : f32) -> f32
{
    var _S39 : bool;
    if(standard_0 > 0.0f)
    {
        _S39 = (abs(raw_0 - standard_0)) <= (ratio_0 * standard_0);
    }
    else
    {
        _S39 = false;
    }
    var _S40 : f32;
    if(_S39)
    {
        _S40 = standard_0;
    }
    else
    {
        _S40 = raw_0;
    }
    return _S40;
}

fn snailFitAutohintAxis_0( layer_tex_2 : texture_2d<f32>,  info_base_1 : vec2<i32>,  axis_0 : i32,  run_0 : i32,  blueCount_0 : i32,  standardWidth_0 : f32,  left_0 : f32,  scale_2 : f32,  policy_0 : SnailAutohintPolicy_0,  knotCount_0 : ptr<function, i32>,  knotBase_0 : ptr<function, array<f32, i32(16)>>,  knotTarget_0 : ptr<function, array<f32, i32(16)>>,  knotSource_0 : ptr<function, array<i32, i32(16)>>) -> bool
{
    (*knotCount_0) = i32(0);
    var i_2 : i32 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
    var _S41 : bool;
    if(!snailAhFinite_0(scale_2))
    {
        _S41 = true;
    }
    else
    {
        _S41 = scale_2 <= 0.0f;
    }
    if(_S41)
    {
        _S41 = true;
    }
    else
    {
        _S41 = blueCount_0 < i32(0);
    }
    if(_S41)
    {
        _S41 = true;
    }
    else
    {
        _S41 = blueCount_0 > i32(16);
    }
    if(_S41)
    {
        _S41 = true;
    }
    else
    {
        _S41 = !snailAhFinite_0(standardWidth_0);
    }
    if(_S41)
    {
        _S41 = true;
    }
    else
    {
        _S41 = standardWidth_0 < 0.0f;
    }
    if(_S41)
    {
        return false;
    }
    var _S42 : bool = axis_0 == i32(0);
    if(_S42)
    {
        _S41 = (policy_0.xAlign_0) == i32(0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = (policy_0.xStem_0) == i32(0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = (policy_0.xPositioning_0) == i32(0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = (policy_0.xRegistration_0) == i32(0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = true;
    }
    else
    {
        if(axis_0 == i32(1))
        {
            _S41 = (policy_0.yAlign_0) == i32(0);
        }
        else
        {
            _S41 = false;
        }
        if(_S41)
        {
            _S41 = (policy_0.yStem_0) == i32(0);
        }
        else
        {
            _S41 = false;
        }
        if(_S41)
        {
            _S41 = (policy_0.yOvershoot_0) == i32(0);
        }
        else
        {
            _S41 = false;
        }
    }
    if(_S41)
    {
        return true;
    }
    var _S43 : f32 = snailWarpF_0(layer_tex_2, info_base_1, run_0, i32(0));
    var n_1 : i32 = i32(_S43);
    if(n_1 <= i32(0))
    {
        _S41 = true;
    }
    else
    {
        _S41 = n_1 > i32(16);
    }
    if(_S41)
    {
        return n_1 == i32(0);
    }
    var _S44 : bool = axis_0 == i32(1);
    if(_S44)
    {
        _S41 = (policy_0.yAlign_0) == i32(2);
    }
    else
    {
        _S41 = false;
    }
    var relative_0 : bool;
    if(_S42)
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
    var _S45 : bool;
    var upperBlue_0 : bool;
    var lowerBlue_0 : bool;
    var axisAligned_0 : bool;
    var _S46 : bool;
    var _S47 : bool;
    var anchorSet_0 : bool;
    var clusterRight_0 : i32;
    var stemMode_0 : i32;
    var pos_1 : array<f32, i32(16)>;
    var width_1 : array<f32, i32(16)>;
    var stem_0 : array<i32, i32(16)>;
    var blue_0 : array<i32, i32(16)>;
    var rounded_0 : array<bool, i32(16)>;
    var syntheticApex_0 : array<bool, i32(16)>;
    var companion_0 : array<i32, i32(16)>;
    var dir_0 : array<i32, i32(16)>;
    var targets_0 : array<f32, i32(16)>;
    var hinted_0 : array<bool, i32(16)>;
    var knotBlueFixed_0 : array<bool, i32(16)>;
    var knotNaturalSpacing_0 : array<bool, i32(16)>;
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
        var f_1 : i32 = run_0 + i32(1) + i32(4) * i_2;
        var _S48 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(0));
        pos_1[i_2] = _S48;
        var _S49 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(1));
        width_1[i_2] = _S49;
        var _S50 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(2));
        var refs_0 : u32 = (bitcast<u32>((_S50)));
        stem_0[i_2] = (i32((refs_0 << (u32(16)))) >> (u32(16)));
        blue_0[i_2] = (i32(refs_0) >> (u32(16)));
        var _S51 : f32 = snailWarpF_0(layer_tex_2, info_base_1, f_1, i32(3));
        var flags_0 : u32 = (bitcast<u32>((_S51)));
        rounded_0[i_2] = ((flags_0 & (u32(1)))) != u32(0);
        syntheticApex_0[i_2] = ((flags_0 & (u32(2)))) != u32(0);
        if(((flags_0 & (u32(4)))) == u32(0))
        {
            return false;
        }
        if(((flags_0 & (u32(8)))) != u32(0))
        {
            stemMode_0 = i32(-1);
        }
        else
        {
            stemMode_0 = i32(1);
        }
        dir_0[i_2] = stemMode_0;
        var _S52 : u32;
        if(_S41)
        {
            _S52 = u32(10);
        }
        else
        {
            _S52 = u32(4);
        }
        var encodedCompanion_0 : i32 = i32((((flags_0 >> (_S52))) & (u32(63))));
        if(encodedCompanion_0 >= i32(62))
        {
            clusterRight_0 = i32(-1);
        }
        else
        {
            clusterRight_0 = encodedCompanion_0;
        }
        companion_0[i_2] = clusterRight_0;
        if(encodedCompanion_0 >= i32(63))
        {
            relative_0 = rounded_0[i_2];
        }
        else
        {
            relative_0 = false;
        }
        if(relative_0)
        {
            anchorSet_0 = (blue_0[i_2]) >= i32(0);
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
            _S47 = true;
        }
        else
        {
            _S47 = !snailAhFinite_0(width_1[i_2]);
        }
        if(_S47)
        {
            _S46 = true;
        }
        else
        {
            _S46 = (width_1[i_2]) < 0.0f;
        }
        if(_S46)
        {
            axisAligned_0 = true;
        }
        else
        {
            axisAligned_0 = (stem_0[i_2]) < i32(-1);
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
            upperBlue_0 = (blue_0[i_2]) < i32(-1);
        }
        if(upperBlue_0)
        {
            _S45 = true;
        }
        else
        {
            _S45 = (blue_0[i_2]) >= blueCount_0;
        }
        if(_S45)
        {
            return false;
        }
        i_2 = i_2 + i32(1);
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
        var _S53 : i32 = i32(2) * i_2;
        var ref_0 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), _S53);
        var shoot_0 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), _S53 + i32(1));
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
    if(_S44)
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
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
        if((stem_0[i_2]) >= i32(0))
        {
            relative_0 = (pos_1[stem_0[i_2]]) > (pos_1[i_2]);
        }
        else
        {
            relative_0 = false;
        }
        if(_S41)
        {
            anchorSet_0 = (blue_0[i_2]) >= i32(0);
        }
        else
        {
            anchorSet_0 = false;
        }
        if(!_S41)
        {
            if(relative_0)
            {
                stemMode_0 = i32(-1);
            }
            else
            {
                stemMode_0 = i32(1);
            }
            dir_0[i_2] = stemMode_0;
        }
        if(anchorSet_0)
        {
            var ref_1 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2]);
            var shoot_1 : f32 = snailWarpF_0(layer_tex_2, info_base_1, i32(12), i32(2) * blue_0[i_2] + i32(1));
            if(rounded_0[i_2])
            {
                _S47 = _S44;
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
            {
                _S46 = (policy_0.yOvershoot_0) == i32(0);
            }
            else
            {
                _S46 = false;
            }
            if(_S46)
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
        i_2 = i_2 + i32(1);
    }
    var grid_0 : f32 = 1.0f / scale_2;
    if(_S42)
    {
        stemMode_0 = policy_0.xStem_0;
    }
    else
    {
        stemMode_0 = policy_0.yStem_0;
    }
    if(_S42)
    {
        spacing_0 = policy_0.xRatio_0;
    }
    else
    {
        spacing_0 = policy_0.yRatio_0;
    }
    var maxPx_0 : f32;
    if(_S42)
    {
        maxPx_0 = policy_0.xMaxPx_0;
    }
    else
    {
        maxPx_0 = policy_0.yMaxPx_0;
    }
    if(_S42)
    {
        _S41 = (policy_0.xAlign_0) == i32(1);
    }
    else
    {
        _S41 = (policy_0.yAlign_0) != i32(0);
    }
    if(_S42)
    {
        relative_0 = (policy_0.xPositioning_0) == i32(1);
    }
    else
    {
        relative_0 = false;
    }
    var widthUnits_0 : f32;
    var bestGap_0 : f32;
    var j_0 : i32;
    var b_0 : i32;
    anchorSet_0 = false;
    var anchorTarget_0 : f32 = 0.0f;
    var anchorBase_0 : f32 = 0.0f;
    var clusterTarget_0 : f32 = 0.0f;
    var clusterBase_0 : f32 = 0.0f;
    var clusterDesiredRight_0 : f32 = 0.0f;
    clusterRight_0 = i32(0);
    i_2 = i32(0);
    var clusterStems_0 : i32 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
        var j_1 : i32 = stem_0[i_2];
        if((stem_0[i_2]) < i32(0))
        {
            _S47 = true;
        }
        else
        {
            _S47 = j_1 <= i_2;
        }
        if(_S47)
        {
            axisAligned_0 = anchorSet_0;
            var i_3 : i32 = i_2 + i32(1);
            anchorSet_0 = axisAligned_0;
            i_2 = i_3;
            continue;
        }
        var nominal_0 : f32 = snailAhStandardWidth_0(width_1[i_2], standardWidth_0, spacing_0);
        var _S54 : f32 = width_1[i_2];
        if(stemMode_0 == i32(2))
        {
            _S46 = true;
        }
        else
        {
            if(stemMode_0 == i32(1))
            {
                _S46 = (nominal_0 * scale_2) < maxPx_0;
            }
            else
            {
                _S46 = false;
            }
        }
        if(_S46)
        {
            bestGap_0 = max(round(nominal_0 * scale_2), 1.0f) * grid_0;
        }
        else
        {
            bestGap_0 = _S54;
        }
        var anchorBase_1 : f32;
        var clusterTarget_1 : f32;
        var clusterBase_1 : f32;
        var clusterDesiredRight_1 : f32;
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
                var _S55 : f32 = snailAhSnap_0(pos_1[i_2], scale_2);
                targets_0[i_2] = _S55;
                widthUnits_0 = _S55;
                anchorBase_1 = pos_1[i_2];
                axisAligned_0 = true;
            }
            targets_0[j_1] = targets_0[i_2] + bestGap_0;
            var _S56 : f32 = widthUnits_0 + round((pos_1[i_2] - anchorBase_1) * scale_2) * grid_0 + bestGap_0;
            var clusterStems_1 : i32 = clusterStems_0 + i32(1);
            var _S57 : f32 = widthUnits_0;
            var _S58 : f32 = anchorBase_1;
            widthUnits_0 = targets_0[i_2];
            anchorBase_1 = pos_1[i_2];
            clusterTarget_1 = _S57;
            clusterBase_1 = _S58;
            clusterDesiredRight_1 = _S56;
            b_0 = j_1;
            j_0 = clusterStems_1;
        }
        else
        {
            if(_S42)
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
                upperBlue_0 = (blue_0[j_1]) >= i32(0);
            }
            else
            {
                upperBlue_0 = false;
            }
            if(!_S41)
            {
                targets_0[i_2] = pos_1[i_2];
            }
            if(upperBlue_0)
            {
                _S45 = !lowerBlue_0;
            }
            else
            {
                _S45 = false;
            }
            var _S59 : bool;
            if(_S45)
            {
                _S59 = _S41;
            }
            else
            {
                _S59 = false;
            }
            if(_S59)
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
        var i_3 : i32 = i_2 + i32(1);
        anchorSet_0 = axisAligned_0;
        i_2 = i_3;
    }
    if(relative_0)
    {
        _S41 = clusterStems_0 > i32(1);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        var _S60 : f32 = clusterDesiredRight_0 - targets_0[clusterRight_0];
        i_2 = i32(0);
        for(;;)
        {
            if(i_2 < i32(16))
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
                targets_0[i_2] = targets_0[i_2] + _S60;
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
        if(i_2 < i32(16))
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
        if(_S42)
        {
            axisAligned_0 = (policy_0.xAlign_0) != i32(0);
        }
        else
        {
            axisAligned_0 = (policy_0.yAlign_0) != i32(0);
        }
        if(!axisAligned_0)
        {
            _S41 = true;
        }
        else
        {
            _S41 = (blue_0[i_2]) < i32(0);
        }
        if(_S41)
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
            if(best_0 == i32(-2))
            {
                bestGap_0 = 3.4028234663852886e+38f;
                b_0 = best_0;
                j_0 = i32(0);
                for(;;)
                {
                    if(j_0 < i32(16))
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
                        _S47 = true;
                    }
                    else
                    {
                        _S47 = (dir_0[j_0]) == (dir_0[i_2]);
                    }
                    if(_S47)
                    {
                        j_0 = j_0 + i32(1);
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
                        _S46 = true;
                    }
                    else
                    {
                        _S46 = widthUnits_0 >= bestGap_0;
                    }
                    if(_S46)
                    {
                        j_0 = j_0 + i32(1);
                        continue;
                    }
                    bestGap_0 = widthUnits_0;
                    b_0 = j_0;
                    j_0 = j_0 + i32(1);
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
            _S47 = true;
        }
        else
        {
            _S47 = hinted_0[b_0];
        }
        if(_S47)
        {
            _S46 = true;
        }
        else
        {
            _S46 = (blue_0[b_0]) >= i32(0);
        }
        if(_S46)
        {
            lowerBlue_0 = true;
        }
        else
        {
            lowerBlue_0 = (bestGap_0 * scale_2) >= spacing_0;
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
        i_2 = i_2 + i32(1);
    }
    i_2 = i32(0);
    for(;;)
    {
        if(i_2 < i32(16))
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
        if(_S42)
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
                _S41 = (blue_0[i_2]) >= i32(0);
            }
            else
            {
                _S41 = false;
            }
            _S41 = !_S41;
        }
        else
        {
            _S41 = false;
        }
        if(_S41)
        {
            i_2 = i_2 + i32(1);
            continue;
        }
        (*knotBase_0)[(*knotCount_0)] = pos_1[i_2];
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
    if(_S42)
    {
        _S41 = (policy_0.xRegistration_0) == i32(1);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = (*knotCount_0) > i32(0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = (*knotCount_0) < i32(16);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        _S41 = left_0 < ((*knotBase_0)[i32(0)] - 0.25f * grid_0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        i_2 = i32(15);
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
                var _S61 : i32 = i_2 - i32(1);
                (*knotBase_0)[i_2] = (*knotBase_0)[_S61];
                (*knotTarget_0)[i_2] = (*knotTarget_0)[_S61];
                knotBlueFixed_0[i_2] = knotBlueFixed_0[_S61];
                knotNaturalSpacing_0[i_2] = knotNaturalSpacing_0[_S61];
                (*knotSource_0)[i_2] = (*knotSource_0)[_S61];
            }
            i_2 = i_2 - i32(1);
        }
        (*knotBase_0)[i32(0)] = left_0;
        (*knotTarget_0)[i32(0)] = snailAhSnap_0(left_0, scale_2);
        knotBlueFixed_0[i32(0)] = false;
        knotNaturalSpacing_0[i32(0)] = false;
        (*knotSource_0)[i32(0)] = i32(32);
        (*knotCount_0) = (*knotCount_0) + i32(1);
    }
    b_0 = i32(15);
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
            _S41 = true;
        }
        else
        {
            _S41 = !knotBlueFixed_0[b_0];
        }
        if(_S41)
        {
            b_0 = b_0 - i32(1);
            continue;
        }
        j_0 = i32(15);
        for(;;)
        {
            if(j_0 > i32(0))
            {
            }
            else
            {
                break;
            }
            if(j_0 > b_0)
            {
                j_0 = j_0 - i32(1);
                continue;
            }
            var _S62 : i32 = j_0 - i32(1);
            if(knotBlueFixed_0[_S62])
            {
                break;
            }
            if(knotNaturalSpacing_0[_S62])
            {
                spacing_0 = 9.99999997475242708e-07f;
            }
            else
            {
                spacing_0 = grid_0;
            }
            (*knotTarget_0)[_S62] = min((*knotTarget_0)[_S62], (*knotTarget_0)[j_0] - spacing_0);
            j_0 = j_0 - i32(1);
        }
        b_0 = b_0 - i32(1);
    }
    i_2 = i32(1);
    for(;;)
    {
        if(i_2 < i32(16))
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
        _S41 = scale_2 > (policy_0.fadeStart_0);
    }
    else
    {
        _S41 = false;
    }
    if(_S41)
    {
        var span_0 : f32 = policy_0.fadeFull_0 - policy_0.fadeStart_0;
        if(span_0 <= 0.0f)
        {
            _S41 = true;
        }
        else
        {
            _S41 = scale_2 >= (policy_0.fadeFull_0);
        }
        if(_S41)
        {
            spacing_0 = 1.0f;
        }
        else
        {
            spacing_0 = (scale_2 - policy_0.fadeStart_0) / span_0;
        }
        i_2 = i32(0);
        for(;;)
        {
            if(i_2 < i32(16))
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
        if(i_2 < i32(16))
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
            _S41 = true;
        }
        else
        {
            _S41 = !snailAhFinite_0((*knotTarget_0)[i_2]);
        }
        if(_S41)
        {
            (*knotCount_0) = i32(0);
            return false;
        }
        i_2 = i_2 + i32(1);
    }
    return true;
}

fn snailAhPackAxis_0( count_1 : i32,  targets_1 : array<f32, i32(16)>,  sources_0 : array<i32, i32(16)>,  packedTargets_1 : ptr<function, array<vec4<f32>, i32(4)>>,  packedSources_1 : ptr<function, vec4<u32>>)
{
    var i_4 : i32 = i32(0);
    for(;;)
    {
        if(i_4 < i32(4))
        {
        }
        else
        {
            break;
        }
        (*packedTargets_1)[i_4] = vec4<f32>(0.0f);
        i_4 = i_4 + i32(1);
    }
    (*packedSources_1) = vec4<u32>(u32(4294967295));
    if(count_1 > i32(16))
    {
        (*packedSources_1)[i32(0)] = (((((*packedSources_1).x) & (u32(4294967040)))) | (u32(254)));
        return;
    }
    i_4 = i32(0);
    for(;;)
    {
        if(i_4 < i32(16))
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
        var _S63 : i32 = (i_4 >> (u32(2)));
        var _S64 : i32 = (i_4 & (i32(3)));
        (*packedTargets_1)[_S63][_S64] = targets_1[i_4];
        var _S65 : u32 = u32(_S64 * i32(8));
        (*packedSources_1)[_S63] = (((((*packedSources_1)[_S63]) & ((~((u32(255) << (_S65))))))) | (((((u32(sources_0[i_4]) & (u32(255)))) << (_S65)))));
        i_4 = i_4 + i32(1);
    }
    return;
}

struct AutohintVertexResult_0
{
     position_1 : vec4<f32>,
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

fn snailAutohintVertex_0( input_1 : TextVertexIn_0,  vertex_index_1 : u32,  mvp_3 : mat4x4<f32>,  viewport_3 : vec2<f32>,  subpixel_order_3 : i32,  policy0_1 : vec4<u32>,  policy1_1 : vec3<u32>,  layer_tex_3 : texture_2d<f32>) -> AutohintVertexResult_0
{
    var base_1 : TextVertexResult_0 = snailTextVertex_0(input_1, vertex_index_1, mvp_3, viewport_3, subpixel_order_3);
    var r_1 : AutohintVertexResult_0;
    r_1.position_1 = base_1.position_0;
    r_1.paint_0 = base_1.color_1 * base_1.tint_0;
    r_1.texcoord_layer_0 = vec3<f32>(base_1.texcoord_0, input_1.bnd_0.w);
    var gz_1 : u32 = input_1.glyph_1.x;
    r_1.info_0 = vec2<i32>(i32((gz_1 & (u32(65535)))), i32((gz_1 >> (u32(16)))));
    r_1.policy0_0 = policy0_1;
    r_1.policy1_0 = policy1_1;
    if(vertex_index_1 != u32(0))
    {
        var i_5 : i32 = i32(0);
        for(;;)
        {
            if(i_5 < i32(4))
            {
            }
            else
            {
                break;
            }
            var _S66 : vec4<f32> = vec4<f32>(0.0f);
            r_1.x_targets_0[i_5] = _S66;
            r_1.y_targets_0[i_5] = _S66;
            i_5 = i_5 + i32(1);
        }
        var _S67 : vec4<u32> = vec4<u32>(u32(4294967295));
        r_1.x_sources_0 = _S67;
        r_1.y_sources_0 = _S67;
        return r_1;
    }
    var info_base_2 : vec2<i32> = r_1.info_0;
    var scale_3 : vec2<f32>;
    var _S68 : bool = snailAhAffineScale_0(mvp_3, viewport_3, input_1.xform_0, &(scale_3));
    if(!_S68)
    {
        var _S69 : array<vec4<f32>, i32(4)> = r_1.x_targets_0;
        var _S70 : vec4<u32> = r_1.x_sources_0;
        snailAhMarkFallback_0(&(_S69), &(_S70));
        r_1.x_targets_0 = _S69;
        r_1.x_sources_0 = _S70;
        var _S71 : array<vec4<f32>, i32(4)> = r_1.y_targets_0;
        var _S72 : vec4<u32> = r_1.y_sources_0;
        snailAhMarkFallback_0(&(_S71), &(_S72));
        r_1.y_targets_0 = _S71;
        r_1.y_sources_0 = _S72;
        return r_1;
    }
    var blueCount_1 : i32 = i32(0);
    var featureXCount_0 : i32 = i32(0);
    var featureYCount_0 : i32 = i32(0);
    var stdX_0 : f32 = snailWarpF_0(layer_tex_3, info_base_2, i32(0), i32(8));
    var stdY_0 : f32 = snailWarpF_0(layer_tex_3, info_base_2, i32(0), i32(9));
    var policy_1 : SnailAutohintPolicy_0;
    var _S73 : bool = snailDecodeAutohintPolicy_0(policy0_1, policy1_1, &(policy_1));
    var valid_0 : bool;
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
        var _S74 : f32 = snailWarpF_0(layer_tex_3, info_base_2, i32(0), i32(10));
        var _S75 : bool = snailAhCount_0(i32(16), _S74, &(blueCount_1));
        valid_0 = _S75;
    }
    else
    {
        valid_0 = false;
    }
    var xRun_0 : i32 = i32(12) + i32(2) * blueCount_1;
    if(valid_0)
    {
        var _S76 : f32 = snailWarpF_0(layer_tex_3, info_base_2, xRun_0, i32(0));
        var _S77 : bool = snailAhCount_0(i32(16), _S76, &(featureXCount_0));
        valid_0 = _S77;
    }
    else
    {
        valid_0 = false;
    }
    var yRun_0 : i32 = xRun_0 + i32(1) + i32(4) * featureXCount_0;
    if(valid_0)
    {
        var _S78 : f32 = snailWarpF_0(layer_tex_3, info_base_2, yRun_0, i32(0));
        valid_0 = snailAhCount_0(i32(16), _S78, &(featureYCount_0));
    }
    else
    {
        valid_0 = false;
    }
    if(!valid_0)
    {
        var _S79 : array<vec4<f32>, i32(4)> = r_1.x_targets_0;
        var _S80 : vec4<u32> = r_1.x_sources_0;
        snailAhMarkFallback_0(&(_S79), &(_S80));
        r_1.x_targets_0 = _S79;
        r_1.x_sources_0 = _S80;
        var _S81 : array<vec4<f32>, i32(4)> = r_1.y_targets_0;
        var _S82 : vec4<u32> = r_1.y_sources_0;
        snailAhMarkFallback_0(&(_S81), &(_S82));
        r_1.y_targets_0 = _S81;
        r_1.y_sources_0 = _S82;
        return r_1;
    }
    var xCount_0 : i32 = i32(0);
    var yCount_0 : i32 = i32(0);
    var _S83 : f32 = snailWarpF_0(layer_tex_3, info_base_2, i32(0), i32(11));
    var xBase_0 : array<f32, i32(16)>;
    var xTarget_0 : array<f32, i32(16)>;
    var xSource_0 : array<i32, i32(16)>;
    var xValid_0 : bool = snailFitAutohintAxis_0(layer_tex_3, info_base_2, i32(0), xRun_0, blueCount_1, stdX_0, _S83, scale_3.x, policy_1, &(xCount_0), &(xBase_0), &(xTarget_0), &(xSource_0));
    var yBase_0 : array<f32, i32(16)>;
    var yTarget_0 : array<f32, i32(16)>;
    var ySource_0 : array<i32, i32(16)>;
    var yValid_0 : bool = snailFitAutohintAxis_0(layer_tex_3, info_base_2, i32(1), yRun_0, blueCount_1, stdY_0, 0.0f, scale_3.y, policy_1, &(yCount_0), &(yBase_0), &(yTarget_0), &(ySource_0));
    if(xValid_0)
    {
        var _S84 : array<vec4<f32>, i32(4)> = r_1.x_targets_0;
        var _S85 : vec4<u32> = r_1.x_sources_0;
        snailAhPackAxis_0(xCount_0, xTarget_0, xSource_0, &(_S84), &(_S85));
        r_1.x_targets_0 = _S84;
        r_1.x_sources_0 = _S85;
    }
    else
    {
        var _S86 : array<vec4<f32>, i32(4)> = r_1.x_targets_0;
        var _S87 : vec4<u32> = r_1.x_sources_0;
        snailAhMarkFallback_0(&(_S86), &(_S87));
        r_1.x_targets_0 = _S86;
        r_1.x_sources_0 = _S87;
    }
    if(yValid_0)
    {
        var _S88 : array<vec4<f32>, i32(4)> = r_1.y_targets_0;
        var _S89 : vec4<u32> = r_1.y_sources_0;
        snailAhPackAxis_0(yCount_0, yTarget_0, ySource_0, &(_S88), &(_S89));
        r_1.y_targets_0 = _S88;
        r_1.y_sources_0 = _S89;
    }
    else
    {
        var _S90 : array<vec4<f32>, i32(4)> = r_1.y_targets_0;
        var _S91 : vec4<u32> = r_1.y_sources_0;
        snailAhMarkFallback_0(&(_S90), &(_S91));
        r_1.y_targets_0 = _S90;
        r_1.y_sources_0 = _S91;
    }
    return r_1;
}

struct VsOutput_0
{
    @builtin(position) position_2 : vec4<f32>,
    @location(0) paint_1 : vec4<f32>,
    @location(1) texcoord_layer_1 : vec3<f32>,
    @interpolate(flat) @location(2) info_1 : vec2<i32>,
    @interpolate(flat) @location(3) policy0_2 : vec4<u32>,
    @interpolate(flat) @location(4) policy1_2 : vec3<u32>,
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

struct VsInput_0
{
     rect_1 : vec4<f32>,
     xform_2 : vec4<f32>,
     origin_1 : vec2<f32>,
     glyph_2 : vec2<u32>,
     bnd_1 : vec4<f32>,
     col_1 : vec4<f32>,
     tint_2 : vec4<f32>,
     policy0_3 : vec4<u32>,
     policy1_3 : vec3<u32>,
};

fn vertexBody_0( input_2 : VsInput_0,  vertex_index_2 : u32) -> VsOutput_0
{
    var v_2 : TextVertexIn_0;
    v_2.rect_0 = input_2.rect_1;
    v_2.xform_0 = input_2.xform_2;
    v_2.origin_0 = input_2.origin_1;
    v_2.glyph_1 = input_2.glyph_2;
    v_2.bnd_0 = input_2.bnd_1;
    v_2.col_0 = input_2.col_1;
    v_2.tint_1 = input_2.tint_2;
    var r_2 : AutohintVertexResult_0 = snailAutohintVertex_0(v_2, vertex_index_2, mat4x4<f32>(pc_0.mvp_0.data_0[i32(0)][i32(0)], pc_0.mvp_0.data_0[i32(1)][i32(0)], pc_0.mvp_0.data_0[i32(2)][i32(0)], pc_0.mvp_0.data_0[i32(3)][i32(0)], pc_0.mvp_0.data_0[i32(0)][i32(1)], pc_0.mvp_0.data_0[i32(1)][i32(1)], pc_0.mvp_0.data_0[i32(2)][i32(1)], pc_0.mvp_0.data_0[i32(3)][i32(1)], pc_0.mvp_0.data_0[i32(0)][i32(2)], pc_0.mvp_0.data_0[i32(1)][i32(2)], pc_0.mvp_0.data_0[i32(2)][i32(2)], pc_0.mvp_0.data_0[i32(3)][i32(2)], pc_0.mvp_0.data_0[i32(0)][i32(3)], pc_0.mvp_0.data_0[i32(1)][i32(3)], pc_0.mvp_0.data_0[i32(2)][i32(3)], pc_0.mvp_0.data_0[i32(3)][i32(3)]), pc_0.viewport_0, pc_0.subpixel_order_0, input_2.policy0_3, input_2.policy1_3, u_layer_tex_0);
    var o_0 : VsOutput_0;
    o_0.position_2 = r_2.position_1;
    o_0.paint_1 = r_2.paint_0;
    o_0.texcoord_layer_1 = r_2.texcoord_layer_0;
    o_0.info_1 = r_2.info_0;
    o_0.policy0_2 = r_2.policy0_0;
    o_0.policy1_2 = r_2.policy1_0;
    o_0.x_targets0_0 = r_2.x_targets_0[i32(0)];
    o_0.x_targets1_0 = r_2.x_targets_0[i32(1)];
    o_0.x_targets2_0 = r_2.x_targets_0[i32(2)];
    o_0.x_targets3_0 = r_2.x_targets_0[i32(3)];
    o_0.y_targets0_0 = r_2.y_targets_0[i32(0)];
    o_0.y_targets1_0 = r_2.y_targets_0[i32(1)];
    o_0.y_targets2_0 = r_2.y_targets_0[i32(2)];
    o_0.y_targets3_0 = r_2.y_targets_0[i32(3)];
    o_0.x_sources_1 = r_2.x_sources_0;
    o_0.y_sources_1 = r_2.y_sources_0;
    return o_0;
}

struct vertexInput_0
{
    @location(0) rect_2 : vec4<f32>,
    @location(1) xform_3 : vec4<f32>,
    @location(2) origin_2 : vec2<f32>,
    @location(3) glyph_3 : vec2<u32>,
    @location(4) bnd_2 : vec4<f32>,
    @location(5) col_2 : vec4<f32>,
    @location(6) tint_3 : vec4<f32>,
    @location(7) policy0_4 : vec4<u32>,
    @location(8) policy1_4 : vec3<u32>,
};

@vertex
fn vertexMain( _S92 : vertexInput_0, @builtin(vertex_index) vertex_index_3 : u32) -> VsOutput_0
{
    var _S93 : VsInput_0 = VsInput_0( _S92.rect_2, _S92.xform_3, _S92.origin_2, _S92.glyph_3, _S92.bnd_2, _S92.col_2, _S92.tint_3, _S92.policy0_4, _S92.policy1_4 );
    var _S94 : VsOutput_0 = vertexBody_0(_S93, vertex_index_3);
    var o_1 : VsOutput_0 = _S94;
    o_1.position_2[i32(1)] = - o_1.position_2.y;
    return o_1;
}

