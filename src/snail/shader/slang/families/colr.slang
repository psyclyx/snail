// Compact TrueType-quadratic + solid-layer COLRv0 fragment family.
//
// This fragment pairs with the regular text vertex artifact. The entry file
// owns only its target-specific resource bindings and stage adapter; the
// evaluator lives in colr_body.
module colr;

import resource_types;
import render_params;

import colr_body;
import painted_family_common;

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailCurveStorage u_curve_tex;
[[vk::binding(1, 0)]] SnailBandStorage u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailCurveStorage u_curve_tex;
[[vk::binding(1, 0)]] SnailBandStorage u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#else // GL family, D3D11 HLSL, and Metal MSL use declaration order.
ConstantBuffer<SnailPushConstants> pc;
SnailCurveStorage u_curve_tex;
SnailBandStorage u_band_tex;
SnailFloatTexture2D u_layer_tex;
#endif

[shader("fragment")]
float4 fragmentMain(PaintedFragmentInput input) : SV_Target {
    ColrVaryings v;
    // Composite COLR records carry immutable palette colors. Do not apply
    // input.color: text placement stores its foreground there, and only
    // 0xffff foreground layers should inherit that color. Those layers are
    // resolved explicitly when the composite atlas record is built.
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.glyph = input.glyph;
    ColrParams p;
    p.page_base = pc.page_base;
    p.atlas_layout = snailAtlasLayout(pc.atlas_page_texels);
    p.output_srgb = pc.output_srgb;
    p.coverage_exponent = pc.coverage_exponent;
    p.mask_output = pc.mask_output;
    return snailColrFragment(v, u_curve_tex, u_band_tex, u_layer_tex, p);
}
