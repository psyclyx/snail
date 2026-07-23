#ifndef SNAIL_LINEAR_RESOLVE_BODY_GLSL
#define SNAIL_LINEAR_RESOLVE_BODY_GLSL

// Linear-resolve pass: render into a float intermediate (RGBA16F/RGBA32F)
// in premultiplied LINEAR light, then encode back to the sRGB target.
// This is the correct-blending recipe for hosts whose target cannot do
// hardware sRGB encode (e.g. GLES 3.0 surfaces) or that need snail output
// composited over an already-encoded destination:
//
//   1. Seed the intermediate from a snapshot of the destination region:
//      `snailLinearResolveSeed(dst_texel)` (skip when clearing instead).
//   2. Draw the snail batches into the intermediate with
//      SNAIL_OUTPUT_SRGB = 0 and premultiplied blending.
//   3. Blit back with blending disabled:
//      `snailLinearResolveEncode(intermediate_texel)`.
//
// Alpha is coverage and carries straight through: RGB un-premultiplies,
// converts, and re-premultiplies so the transfer function applies to
// color, never to coverage. The host owns the FBOs, textures, snapshot
// copy, and state save/restore (see the demo's reference implementation).
//
// Requires: snail_color_common.glsl.

// sRGB-encoded premultiplied -> linear premultiplied (destination seed).
vec4 snailLinearResolveSeed(vec4 dst_premul) {
    if (dst_premul.a <= 0.0) return vec4(0.0);
    float inv_a = 1.0 / dst_premul.a;
    return vec4(
        srgbToLinear(clamp(dst_premul.rgb * inv_a, 0.0, 1.0)) * dst_premul.a,
        dst_premul.a
    );
}

// Linear premultiplied -> sRGB-encoded premultiplied (target encode).
vec4 snailLinearResolveEncode(vec4 linear_premul) {
    return srgbEncodePremultiplied(linear_premul);
}

#endif
