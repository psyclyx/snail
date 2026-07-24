// Shared arbitrary-path + general-paint fragment-family adapter.
//
// Thin family entry modules specialize pathFragment for classified
// quadratic, classified conic, or unrestricted cubic records while keeping
// the public fragmentMain entry-point name on every textual backend.
//
// Binding 3 is a sampled image:
//  - Vulkan aliases an image-only and sampler-only variable onto the one
//    COMBINED_IMAGE_SAMPLER descriptor.
//  - WGSL uses the catalog's split sampler at group 1, binding 3.
//  - GL lowers the resource aliases to a combined sampler object.
module path_family;

import resource_types;

import path_body;
import painted_family_common;

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
[[vk::binding(3, 0)]] SnailFloatTexture2DArray u_image_tex;
[[vk::binding(3, 0)]] SnailSamplerState u_image_sampler;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
[[vk::binding(3, 0)]] SnailFloatTexture2DArray u_image_tex;
[[vk::binding(3, 1)]] SnailSamplerState u_image_sampler;
#else // GL family, D3D11 HLSL, and Metal MSL use declaration order.
ConstantBuffer<SnailPushConstants> pc;
SnailFloatTexture2DArray u_curve_tex;
SnailUint2Texture2DArray u_band_tex;
SnailFloatTexture2D u_layer_tex;
SnailFloatTexture2DArray u_image_tex;
#if defined(SNAIL_TARGET_GL)
static const SnailSamplerState u_image_sampler = 0;
#else
SnailSamplerState u_image_sampler;
#endif
#endif

public float4 pathFragment<let HAS_CONIC : bool, let HAS_CUBIC : bool>(
    PaintedFragmentInput input)
{
    PaintedVaryings v;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    PaintedParams p;
    p.layer_base = pc.layer_base;
    p.output_srgb = pc.output_srgb;
    p.coverage_exponent = pc.coverage_exponent;
    p.dither_scale = pc.dither_scale;
    p.mask_output = pc.mask_output;
    return snailPaintedFragment<HAS_CONIC, HAS_CUBIC>(
        v, input.position.xy,
        u_curve_tex, u_band_tex, u_layer_tex,
        u_image_tex, u_image_sampler, p);
}
