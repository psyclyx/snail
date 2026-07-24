// Compact COLRv0 fragment path.
//
// COLRv0 layers are TrueType glyph outlines with solid CPAL colors. They do
// not need the arbitrary-path segment solver or the general gradient/image
// paint evaluator. Reuse the smaller quadratic glyph coverage path and
// composite the immutable solid layers source-over in one fragment.
module colr_body;

import resource_types;

import render_abi;
import color_common;
import text_coverage;

public struct ColrParams {
    public int layer_base;
    public int output_srgb;
    public float coverage_exponent;
    public int mask_output;
};

public struct ColrVaryings {
    public float4 tint;
    public float2 texcoord;
    public int4 glyph;
};

int2 offsetColrInfoLoc(SnailFloatTexture2D layer_tex, int2 base, int offset) {
    uint uw, uh;
    layer_tex.GetDimensions(uw, uh);
    int width = int(uw);
    int texel = base.y * width + base.x + offset;
    return int2(texel % width, texel / width);
}

float colrLayerCoverage(
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    SnailFloatTexture2D layer_tex,
    float2 rc,
    float2 epp,
    float2 ppe,
    int2 record_loc,
    int tex_layer,
    float coverage_exponent)
{
    float4 info = layer_tex.Load(int3(record_loc, 0));
    if (int(-info.w + 0.5) != SNAIL_PAINT_KIND_SOLID) return 0.0;
    float4 band = layer_tex.Load(int3(offsetColrInfoLoc(layer_tex, record_loc, 1), 0));
    int packed_counts = asint(info.z);
    int band_max_h = packed_counts & 0xFFFF;
    int band_max_v = (packed_counts >> 16) & 0xFFFF;
    int packed_gx = int(info.x);
    int2 glyph_loc = int2(packed_gx & 0x7FFF, int(info.y));
    return evalGlyphCoverage(
        rc,
        epp,
        ppe,
        glyph_loc,
        int2(band_max_v, band_max_h),
        band,
        tex_layer,
        curve_tex,
        band_tex,
        coverage_exponent);
}

float4 colrSolidColor(SnailFloatTexture2D layer_tex, int2 record_loc) {
    return layer_tex.Load(int3(offsetColrInfoLoc(layer_tex, record_loc, 2), 0));
}

public float4 snailColrFragment(
    ColrVaryings v,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    SnailFloatTexture2D layer_tex,
    ColrParams p)
{
    if ((uint(v.glyph.w) & 0x8000u) == 0u) discard;
    if ((v.glyph.w & 0x3) != SNAIL_SPECIAL_KIND_COLR) discard;

    float2 rc = v.texcoord;
    float2 epp = fwidth(rc);
    float2 ppe = 1.0 / max(epp, float2(1.0 / 65536.0));
    int2 info_base = v.glyph.xy;
    float4 first_info = layer_tex.Load(int3(info_base, 0));
    int tex_layer = p.layer_base + ((v.glyph.w >> 2) & 0xff);
    float4 result = float4(0.0);

    if (int(-first_info.w + 0.5) == SNAIL_PAINT_KIND_COMPOSITE_GROUP) {
        int layer_count = int(first_info.x + 0.5);
        for (int layer = 0; layer < layer_count; ++layer) {
            int2 record_loc = offsetColrInfoLoc(
                layer_tex,
                info_base,
                1 + layer * SNAIL_PAINT_TEXELS_PER_RECORD);
            float cov = colrLayerCoverage(
                curve_tex,
                band_tex,
                layer_tex,
                rc,
                epp,
                ppe,
                record_loc,
                tex_layer,
                p.coverage_exponent);
            float4 premul = premultiplyColor(colrSolidColor(layer_tex, record_loc) * v.tint, cov);
            result = premul + result * (1.0 - premul.a);
        }
    } else {
        float cov = colrLayerCoverage(
            curve_tex,
            band_tex,
            layer_tex,
            rc,
            epp,
            ppe,
            info_base,
            tex_layer,
            p.coverage_exponent);
        result = premultiplyColor(colrSolidColor(layer_tex, info_base) * v.tint, cov);
    }

    if (result.a < 1.0 / 255.0) discard;
    return (p.mask_output != 0) ? float4(result.a) :
        ((p.output_srgb != 0) ? srgbEncodePremultiplied(result) : result);
}
