// Text-as-material coverage sampler (evaluate glyph coverage at an
// arbitrary scene position inside a caller's material shader). Ported 1:1
// from the composed catalog's snail_text_sample_body.glsl (retired in
// stage D — this module is now the sole source): every epsilon, literal,
// and operation order was preserved.
//
// Structural differences from GLSL (plumbing only, math unchanged):
//  - The per-backend record storage (texel buffer / R32UI texture / SSBO)
//    becomes the `ISnailTextRecords` interface; the consumer supplies a
//    conforming struct wrapping its storage (see families/text_sample_family.slang
//    for the canonical SSBO/texel-buffer flavors).
//  - The record word stride (`SNAIL_TEXT_RECORD_WORDS_PER_GLYPH` macro) and
//    the glyph count / layer base / coverage exponent uniforms are explicit
//    parameters.
module text_sample;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;

public interface ISnailTextRecords {
    public uint word(int linear_index);
};

public struct SnailTextSampleRecord {
    public float4 rect;
    public float4 xform;
    public float2 origin;
    public uint2 glyph;
    public float4 banding;
    public float4 color;
    public float4 tint;
};

uint snailTextSampleWord<T : ISnailTextRecords>(T records, int words_per_glyph, int glyph_index, int word_offset) {
    return records.word(glyph_index * words_per_glyph + word_offset);
}

public float snailDecodeFloat16(uint bits) {
    uint sign_bit = bits >> 15u;
    uint exponent = (bits >> 10u) & 31u;
    uint fraction = bits & 1023u;
    float sign = (sign_bit == 0u) ? 1.0 : -1.0;
    if (exponent == 0u) {
        if (fraction == 0u) return sign * 0.0;
        return sign * exp2(-14.0) * (float(fraction) / 1024.0);
    }
    if (exponent == 31u) return sign * 65504.0;
    return sign * exp2(float(exponent) - 15.0) * (1.0 + float(fraction) / 1024.0);
}

public float2 snailUnpackHalf2(uint word) {
    return float2(snailDecodeFloat16(word & 0xFFFFu), snailDecodeFloat16(word >> 16u));
}

public float4 snailUnpackHalf4(uint lo, uint hi) {
    return float4(snailUnpackHalf2(lo), snailUnpackHalf2(hi));
}

public SnailTextSampleRecord snailTextSampleRecord<T : ISnailTextRecords>(T records, int words_per_glyph, int glyph_index) {
    SnailTextSampleRecord record;
    record.rect = snailUnpackHalf4(snailTextSampleWord(records, words_per_glyph, glyph_index, 0), snailTextSampleWord(records, words_per_glyph, glyph_index, 1));
    record.xform = float4(
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 2)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 3)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 4)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 5))
    );
    record.origin = float2(
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 6)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 7))
    );
    record.glyph = uint2(snailTextSampleWord(records, words_per_glyph, glyph_index, 8), snailTextSampleWord(records, words_per_glyph, glyph_index, 9));
    record.banding = float4(
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 10)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 11)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 12)),
        asfloat(snailTextSampleWord(records, words_per_glyph, glyph_index, 13))
    );
    record.color = snailUnpackHalf4(snailTextSampleWord(records, words_per_glyph, glyph_index, 14), snailTextSampleWord(records, words_per_glyph, glyph_index, 15));
    record.tint = snailUnpackHalf4(snailTextSampleWord(records, words_per_glyph, glyph_index, 16), snailTextSampleWord(records, words_per_glyph, glyph_index, 17));
    return record;
}

public float2 snailTextSampleLocalCoord(float2 scene_pos, float4 xform, float2 origin) {
    float det = xform.x * xform.w - xform.y * xform.z;
    float2 delta = scene_pos - origin;
    return float2(
        (xform.w * delta.x - xform.y * delta.y) / det,
        (-xform.z * delta.x + xform.x * delta.y) / det
    );
}

public float2 snailTextSampleLocalVector(float2 scene_vector, float4 xform) {
    float det = xform.x * xform.w - xform.y * xform.z;
    return float2(
        (xform.w * scene_vector.x - xform.y * scene_vector.y) / det,
        (-xform.z * scene_vector.x + xform.x * scene_vector.y) / det
    );
}

public float4 snailTextSamplePremulLinearWithFootprint<T : ISnailTextRecords>(
    T records,
    int words_per_glyph,
    int glyph_count,
    int layer_base,
    float coverage_exponent,
    Texture2DArray<float4> curve_tex,
    Texture2DArray<uint2> band_tex,
    float2 scene_pos,
    float2 scene_dx,
    float2 scene_dy)
{
    float4 paint = float4(0.0);
    for (int i = 0; i < glyph_count; i++) {
        SnailTextSampleRecord record = snailTextSampleRecord(records, words_per_glyph, i);
        float det = record.xform.x * record.xform.w - record.xform.y * record.xform.z;
        if (abs(det) < 1e-10) continue;
        float2 rc = snailTextSampleLocalCoord(scene_pos, record.xform, record.origin);
        float2 local_dx = snailTextSampleLocalVector(scene_dx, record.xform);
        float2 local_dy = snailTextSampleLocalVector(scene_dy, record.xform);
        float2 epp = abs(local_dx) + abs(local_dy);
        float2 em_aa = max(epp * 2.0, float2(0.001));
        if (rc.x < record.rect.x - em_aa.x || rc.x > record.rect.z + em_aa.x ||
            rc.y < record.rect.y - em_aa.y || rc.y > record.rect.w + em_aa.y) continue;

        uint gz = record.glyph.x;
        uint gw = record.glyph.y;
        if ((gw & 0x80000000u) != 0u) continue;
        int layer_byte = int((gw >> 8u) & 0xFFu);
        int atlas_layer = layer_base + layer_byte;
        int2 glyph_loc = int2(int(gz & 0xFFFFu), int(gz >> 16u));
        int2 band_max = int2(int((gw >> 4u) & 0xFu), int(gw & 0xFu));
        float2 ppe = float2(1.0 / max(epp.x, 1.0 / 65536.0),
                            1.0 / max(epp.y, 1.0 / 65536.0));
        float cov = evalGlyphCoverage(rc, epp, ppe, glyph_loc, band_max, record.banding, atlas_layer,
                                      curve_tex, band_tex, coverage_exponent);
        float alpha = clamp(cov * record.color.a * record.tint.a, 0.0, 1.0);
        if (alpha <= 1.0 / 255.0) continue;
        float3 linear_rgb = record.color.rgb * record.tint.rgb;
        paint.rgb = linear_rgb * alpha + paint.rgb * (1.0 - alpha);
        paint.a = alpha + paint.a * (1.0 - alpha);
    }
    return paint;
}

// Convenience for a direct, unconditional call. Custom materials that sample
// coverage multiple times should compute derivatives once at the top of their
// fragment entry point and call the explicit-footprint variant above; that
// keeps every derivative outside prior fragment-dependent glyph control flow.
public float4 snailTextSamplePremulLinear<T : ISnailTextRecords>(
    T records,
    int words_per_glyph,
    int glyph_count,
    int layer_base,
    float coverage_exponent,
    Texture2DArray<float4> curve_tex,
    Texture2DArray<uint2> band_tex,
    float2 scene_pos)
{
    return snailTextSamplePremulLinearWithFootprint(records, words_per_glyph, glyph_count,
                                                    layer_base, coverage_exponent,
                                                    curve_tex, band_tex,
                                                    scene_pos, ddx(scene_pos), ddy(scene_pos));
}
