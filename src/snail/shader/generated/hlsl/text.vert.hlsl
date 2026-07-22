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

struct VsOutput_0
{
    float4 position_1 : SV_Position;
    float4 color_2 : TEXCOORD0;
    float2 texcoord_1 : TEXCOORD1;
    nointerpolation float4 banding_1 : TEXCOORD2;
    nointerpolation int4 glyph_2 : TEXCOORD3;
    float4 tint_2 : TEXCOORD4;
};

struct VsInput_0
{
    float4 rect_1 : ATTRIB0;
    float4 xform_1 : ATTRIB1;
    float2 origin_1 : ATTRIB2;
    uint2 glyph_3 : ATTRIB3;
    float4 bnd_1 : ATTRIB4;
    float4 col_1 : ATTRIB5;
    float4 tint_3 : ATTRIB6;
};

VsOutput_0 vertexBody_0(VsInput_0 input_1, uint vertex_index_1)
{
    TextVertexIn_0 v_0;
    v_0.rect_0 = input_1.rect_1;
    v_0.xform_0 = input_1.xform_1;
    v_0.origin_0 = input_1.origin_1;
    v_0.glyph_1 = input_1.glyph_3;
    v_0.bnd_0 = input_1.bnd_1;
    v_0.col_0 = input_1.col_1;
    v_0.tint_1 = input_1.tint_3;
    TextVertexResult_0 r_1 = snailTextVertex_0(v_0, vertex_index_1, pc_0.mvp_0, pc_0.viewport_0, pc_0.subpixel_order_0);
    VsOutput_0 o_0;
    o_0.position_1 = r_1.position_0;
    o_0.color_2 = r_1.color_1;
    o_0.texcoord_1 = r_1.texcoord_0;
    o_0.banding_1 = r_1.banding_0;
    o_0.glyph_2 = r_1.glyph_0;
    o_0.tint_2 = r_1.tint_0;
    return o_0;
}

VsOutput_0 vertexMain(VsInput_0 input_2, uint vertex_index_2 : SV_VertexID)
{
    VsOutput_0 o_1 = vertexBody_0(input_2, vertex_index_2);
    o_1.position_1[int(1)] = - o_1.position_1.y;
    return o_1;
}

