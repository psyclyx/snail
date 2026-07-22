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

struct VsOutput_0
{
    float4 position_1;
    float4 color_2;
    float2 texcoord_1;
    [[flat]] float4 banding_1;
    [[flat]] int4 glyph_2;
    float4 tint_2;
};

struct VsInput_0
{
    float4 rect_1;
    float4 xform_1;
    float2 origin_1;
    uint2 glyph_3;
    float4 bnd_1;
    float4 col_1;
    float4 tint_3;
};

struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};

struct SnailPushConstants_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 mvp_1;
    float2 viewport_1;
    int subpixel_order_2;
    int output_srgb_0;
    int layer_base_0;
    float coverage_exponent_0;
    float dither_scale_0;
    int mask_output_0;
};

struct KernelContext_0
{
    SnailPushConstants_natural_0 constant* pc_0;
};

VsOutput_0 vertexBody_0(const VsInput_0 thread* input_1, uint vertex_index_1, KernelContext_0 thread* kernelContext_0)
{
    thread TextVertexIn_0 v_0;
    (&v_0)->rect_0 = input_1->rect_1;
    (&v_0)->xform_0 = input_1->xform_1;
    (&v_0)->origin_0 = input_1->origin_1;
    (&v_0)->glyph_1 = input_1->glyph_3;
    (&v_0)->bnd_0 = input_1->bnd_1;
    (&v_0)->col_0 = input_1->col_1;
    (&v_0)->tint_1 = input_1->tint_3;
    matrix<float,int(4),int(4)>  _S19 = matrix<float,int(4),int(4)> (kernelContext_0->pc_0->mvp_1.data_0[int(0)][int(0)], kernelContext_0->pc_0->mvp_1.data_0[int(1)][int(0)], kernelContext_0->pc_0->mvp_1.data_0[int(2)][int(0)], kernelContext_0->pc_0->mvp_1.data_0[int(3)][int(0)], kernelContext_0->pc_0->mvp_1.data_0[int(0)][int(1)], kernelContext_0->pc_0->mvp_1.data_0[int(1)][int(1)], kernelContext_0->pc_0->mvp_1.data_0[int(2)][int(1)], kernelContext_0->pc_0->mvp_1.data_0[int(3)][int(1)], kernelContext_0->pc_0->mvp_1.data_0[int(0)][int(2)], kernelContext_0->pc_0->mvp_1.data_0[int(1)][int(2)], kernelContext_0->pc_0->mvp_1.data_0[int(2)][int(2)], kernelContext_0->pc_0->mvp_1.data_0[int(3)][int(2)], kernelContext_0->pc_0->mvp_1.data_0[int(0)][int(3)], kernelContext_0->pc_0->mvp_1.data_0[int(1)][int(3)], kernelContext_0->pc_0->mvp_1.data_0[int(2)][int(3)], kernelContext_0->pc_0->mvp_1.data_0[int(3)][int(3)]);
    float2 _S20 = kernelContext_0->pc_0->viewport_1;
    int _S21 = kernelContext_0->pc_0->subpixel_order_2;
    thread TextVertexIn_0 _S22 = v_0;
    TextVertexResult_0 _S23 = snailTextVertex_0(&_S22, vertex_index_1, _S19, _S20, _S21);
    thread VsOutput_0 o_0;
    (&o_0)->position_1 = _S23.position_0;
    (&o_0)->color_2 = _S23.color_1;
    (&o_0)->texcoord_1 = _S23.texcoord_0;
    (&o_0)->banding_1 = _S23.banding_0;
    (&o_0)->glyph_2 = _S23.glyph_0;
    (&o_0)->tint_2 = _S23.tint_0;
    return o_0;
}

struct vertexMain_Result_0
{
    float4 position_2 [[position]];
    float4 color_3 [[user(TEXCOORD)]];
    float2 texcoord_2 [[user(TEXCOORD_1)]];
    float4 banding_2 [[user(TEXCOORD_2)]];
    int4 glyph_4 [[user(TEXCOORD_3)]];
    float4 tint_4 [[user(TEXCOORD_4)]];
};

struct vertexInput_0
{
    float4 rect_2 [[attribute(0)]];
    float4 xform_2 [[attribute(1)]];
    float2 origin_2 [[attribute(2)]];
    uint2 glyph_5 [[attribute(3)]];
    float4 bnd_2 [[attribute(4)]];
    float4 col_2 [[attribute(5)]];
    float4 tint_5 [[attribute(6)]];
};

[[vertex]] vertexMain_Result_0 vertexMain(vertexInput_0 _S24 [[stage_in]], uint vertex_index_2 [[vertex_id]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]])
{
    thread KernelContext_0 kernelContext_1;
    (&kernelContext_1)->pc_0 = pc_1;
    thread VsInput_0 _S25;
    (&_S25)->rect_1 = _S24.rect_2;
    (&_S25)->xform_1 = _S24.xform_2;
    (&_S25)->origin_1 = _S24.origin_2;
    (&_S25)->glyph_3 = _S24.glyph_5;
    (&_S25)->bnd_1 = _S24.bnd_2;
    (&_S25)->col_1 = _S24.col_2;
    (&_S25)->tint_3 = _S24.tint_5;
    VsOutput_0 _S26 = vertexBody_0(&_S25, vertex_index_2, &kernelContext_1);
    thread VsOutput_0 o_1 = _S26;
    (&o_1)->position_1.y = - (&o_1)->position_1.y;
    thread vertexMain_Result_0 _S27;
    (&_S27)->position_2 = o_1.position_1;
    (&_S27)->color_3 = o_1.color_2;
    (&_S27)->texcoord_2 = o_1.texcoord_1;
    (&_S27)->banding_2 = o_1.banding_1;
    (&_S27)->glyph_4 = o_1.glyph_2;
    (&_S27)->tint_4 = o_1.tint_2;
    return _S27;
}

