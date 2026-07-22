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

struct VsOutput_0
{
    @builtin(position) position_1 : vec4<f32>,
    @location(0) color_2 : vec4<f32>,
    @location(1) texcoord_1 : vec2<f32>,
    @interpolate(flat) @location(2) banding_1 : vec4<f32>,
    @interpolate(flat) @location(3) glyph_2 : vec4<i32>,
    @location(4) tint_2 : vec4<f32>,
};

struct VsInput_0
{
     rect_1 : vec4<f32>,
     xform_1 : vec4<f32>,
     origin_1 : vec2<f32>,
     glyph_3 : vec2<u32>,
     bnd_1 : vec4<f32>,
     col_1 : vec4<f32>,
     tint_3 : vec4<f32>,
};

fn vertexBody_0( input_1 : VsInput_0,  vertex_index_1 : u32) -> VsOutput_0
{
    var v_0 : TextVertexIn_0;
    v_0.rect_0 = input_1.rect_1;
    v_0.xform_0 = input_1.xform_1;
    v_0.origin_0 = input_1.origin_1;
    v_0.glyph_1 = input_1.glyph_3;
    v_0.bnd_0 = input_1.bnd_1;
    v_0.col_0 = input_1.col_1;
    v_0.tint_1 = input_1.tint_3;
    var r_1 : TextVertexResult_0 = snailTextVertex_0(v_0, vertex_index_1, mat4x4<f32>(pc_0.mvp_0.data_0[i32(0)][i32(0)], pc_0.mvp_0.data_0[i32(1)][i32(0)], pc_0.mvp_0.data_0[i32(2)][i32(0)], pc_0.mvp_0.data_0[i32(3)][i32(0)], pc_0.mvp_0.data_0[i32(0)][i32(1)], pc_0.mvp_0.data_0[i32(1)][i32(1)], pc_0.mvp_0.data_0[i32(2)][i32(1)], pc_0.mvp_0.data_0[i32(3)][i32(1)], pc_0.mvp_0.data_0[i32(0)][i32(2)], pc_0.mvp_0.data_0[i32(1)][i32(2)], pc_0.mvp_0.data_0[i32(2)][i32(2)], pc_0.mvp_0.data_0[i32(3)][i32(2)], pc_0.mvp_0.data_0[i32(0)][i32(3)], pc_0.mvp_0.data_0[i32(1)][i32(3)], pc_0.mvp_0.data_0[i32(2)][i32(3)], pc_0.mvp_0.data_0[i32(3)][i32(3)]), pc_0.viewport_0, pc_0.subpixel_order_0);
    var o_0 : VsOutput_0;
    o_0.position_1 = r_1.position_0;
    o_0.color_2 = r_1.color_1;
    o_0.texcoord_1 = r_1.texcoord_0;
    o_0.banding_1 = r_1.banding_0;
    o_0.glyph_2 = r_1.glyph_0;
    o_0.tint_2 = r_1.tint_0;
    return o_0;
}

struct vertexInput_0
{
    @location(0) rect_2 : vec4<f32>,
    @location(1) xform_2 : vec4<f32>,
    @location(2) origin_2 : vec2<f32>,
    @location(3) glyph_4 : vec2<u32>,
    @location(4) bnd_2 : vec4<f32>,
    @location(5) col_2 : vec4<f32>,
    @location(6) tint_4 : vec4<f32>,
};

@vertex
fn vertexMain( _S19 : vertexInput_0, @builtin(vertex_index) vertex_index_2 : u32) -> VsOutput_0
{
    var _S20 : VsInput_0 = VsInput_0( _S19.rect_2, _S19.xform_2, _S19.origin_2, _S19.glyph_4, _S19.bnd_2, _S19.col_2, _S19.tint_4 );
    var o_1 : VsOutput_0 = vertexBody_0(_S20, vertex_index_2);
    o_1.position_1[i32(1)] = - o_1.position_1.y;
    return o_1;
}

