// Native-Slang port of snail_tt_hinted_text_frag_body.glsl. The GLSL
// fragment is the behavioral spec: every epsilon, literal, and operation
// order is preserved.
//
// Baked TT hints use the ordinary curve and band atlas (the text-family
// glyph coverage evaluator). The small layer-info record exists only
// because the special-instance ABI needs an address for the band metadata
// while retaining a distinct program family.
module tt_hinted;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;

public int2 offsetTtHintedInfoLoc(Texture2D<float4> layer_tex, int2 base, int offset) {
    uint uw, uh;
    layer_tex.GetDimensions(uw, uh);
    int width = int(uw);
    int texel = base.y * width + base.x + offset;
    return int2(texel % width, texel / width);
}

public struct TtHintedVaryings {
    public float4 color;
    public float4 tint;
    public float2 texcoord;
    public float4 banding;
    public int4 glyph;
};

public float4 snailTtHintedTextFragment(
    TtHintedVaryings v,
    Texture2DArray<float4> curve_tex,
    Texture2DArray<uint2> band_tex,
    Texture2D<float4> layer_tex,
    int layer_base,
    int output_srgb,
    float coverage_exponent,
    int mask_output)
{
    if ((uint(v.glyph.w) & 0x8000u) == 0u) discard;
    int special_kind = v.glyph.w & 0x3;
    if (special_kind != SNAIL_SPECIAL_KIND_TT_HINTED_TEXT) discard;

    float2 rc = v.texcoord;
    float2 epp = fwidth(rc);
    float2 ppe = float2(1.0 / max(epp.x, 1.0 / 65536.0),
                        1.0 / max(epp.y, 1.0 / 65536.0));

    int2 info_base = v.glyph.xy;
    float4 header = layer_tex.Load(int3(info_base, 0));
    float4 band = layer_tex.Load(int3(offsetTtHintedInfoLoc(layer_tex, info_base, 1), 0));
    int packed_counts = asint(header.z);
    int band_max_h = packed_counts & 0xFFFF;
    int band_max_v = (packed_counts >> 16) & 0xFFFF;
    int atlas_layer = layer_base + ((v.glyph.w >> 2) & 0xff);

    float cov = evalGlyphCoverage(rc, epp, ppe, int2(int(header.x), int(header.y)),
                                  int2(band_max_v, band_max_h), band,
                                  atlas_layer, curve_tex, band_tex, coverage_exponent);
    if (cov < 1.0 / 255.0) discard;

    float4 premul = premultiplyColor(v.color * v.tint, cov);
    return (mask_output != 0) ? float4(premul.a) :
        ((output_srgb != 0) ? srgbEncodePremultiplied(premul) : premul);
}
