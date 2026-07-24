// Native-Slang port of snail_text_main.glsl — the regular-text fragment
// entry logic. The GLSL fragment is the behavioral spec: every epsilon,
// literal, and operation order is preserved.
module text_main;

import resource_types;

import render_abi;
import coverage_common;
import color_common;
import text_coverage;

public struct TextVaryings {
    public float4 color;
    public float4 tint;
    public float2 texcoord;
    public float4 banding;
    public int4 glyph;
};

public float4 snailTextFragment(
    TextVaryings v,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    int layer_base,
    int output_srgb,
    float coverage_exponent,
    int mask_output)
{
    if ((uint(v.glyph.w) & 0x8000u) != 0u) discard;
    int layer_byte = (v.glyph.z >> 8) & 0xFF;
    int atlas_layer = layer_base + layer_byte;
    float2 rc = v.texcoord;
    float2 epp = fwidth(rc);
    float2 ppe = float2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, epp, ppe, v.glyph.xy,
                                                   int2((v.glyph.z >> 4) & 0xF, v.glyph.z & 0xF),
                                  v.banding, atlas_layer,
                                  curve_tex, band_tex, coverage_exponent);
    if (cov < 1.0 / 255.0) discard;
    // v.color / v.tint arrive as linear-light f16 vertex attributes.
    float4 premul = premultiplyColor(v.color * v.tint, cov);
    return (mask_output != 0) ? float4(premul.a) : ((output_srgb != 0) ? srgbEncodePremultiplied(premul) : premul);
}
