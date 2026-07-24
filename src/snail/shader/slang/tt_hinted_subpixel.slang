// LCD-subpixel fragment body for baked TT-hinted text. There is no GLSL
// spec for this path: the Slang source is authoritative, and the CPU
// raster backend (snail-raster renderTtHintedTextBatchInstance with
// allow_subpixel) is the parity reference. Semantics: the tt_hinted
// grayscale decode (band metadata from the layer-info record, ordinary
// curve/band atlas) feeding the regular-text 7-tap subpixel evaluator.
module tt_hinted_subpixel;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import tt_hinted;
import subpixel_body;

public SubpixelResult snailTtHintedSubpixelFragment(
    TtHintedVaryings v,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    SnailFloatTexture2D layer_tex,
    int layer_base,
    int subpixel_order,
    int output_srgb,
    float coverage_exponent)
{
    SubpixelResult r;
    r.color = float4(0.0);
    r.blend = float4(0.0);
    r.discard_fragment = false;

    if ((uint(v.glyph.w) & 0x8000u) == 0u) { r.discard_fragment = true; return r; }
    int special_kind = v.glyph.w & 0x3;
    if (special_kind != SNAIL_SPECIAL_KIND_TT_HINTED_TEXT) { r.discard_fragment = true; return r; }

    float2 rc = v.texcoord;
    int2 info_base = v.glyph.xy;
    float4 header = layer_tex.Load(int3(info_base, 0));
    float4 band = layer_tex.Load(int3(offsetTtHintedInfoLoc(layer_tex, info_base, 1), 0));
    int packed_counts = asint(header.z);
    int band_max_h = packed_counts & 0xFFFF;
    int band_max_v = (packed_counts >> 16) & 0xFFFF;
    int atlas_layer = layer_base + ((v.glyph.w >> 2) & 0xff);

    float4 cov_alpha = evalGlyphCoverageSubpixel(rc, int2(int(header.x), int(header.y)),
                                                int2(band_max_v, band_max_h), band, atlas_layer,
                                                subpixel_order, coverage_exponent,
                                                curve_tex, band_tex);
    // v.color / v.tint arrive as linear-light f16 vertex attributes.
    return snailPackSubpixelResult(v.color * v.tint, cov_alpha, output_srgb);
}
