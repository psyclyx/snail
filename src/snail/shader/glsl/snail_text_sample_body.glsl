struct SnailTextSampleRecord {
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 banding;
    vec4 color;
    vec4 tint;
};

// `snailTextRecordWord(int linear_index)` — fetch one u32 word of the emit
// record stream — is supplied by the records *interface* (which differs per
// backend: a texel buffer on desktop GL, a 2D R32UI texture on GLES 3.0, an
// SSBO on Vulkan). This body is identical everywhere; only the storage the
// accessor reads changes.
uint snailTextSampleWord(int glyph_index, int word_offset) {
    return snailTextRecordWord(glyph_index * SNAIL_TEXT_RECORD_WORDS_PER_GLYPH + word_offset);
}

float snailDecodeFloat16(uint bits) {
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

vec2 snailUnpackHalf2(uint word) {
    return vec2(snailDecodeFloat16(word & 0xFFFFu), snailDecodeFloat16(word >> 16u));
}

vec4 snailUnpackHalf4(uint lo, uint hi) {
    return vec4(snailUnpackHalf2(lo), snailUnpackHalf2(hi));
}

vec4 snailUnpackUnorm4x8(uint word) {
    return vec4(
        float(word & 0xFFu),
        float((word >> 8u) & 0xFFu),
        float((word >> 16u) & 0xFFu),
        float((word >> 24u) & 0xFFu)
    ) / 255.0;
}

SnailTextSampleRecord snailTextSampleRecord(int glyph_index) {
    SnailTextSampleRecord record;
    record.rect = snailUnpackHalf4(snailTextSampleWord(glyph_index, 0), snailTextSampleWord(glyph_index, 1));
    record.xform = vec4(
        uintBitsToFloat(snailTextSampleWord(glyph_index, 2)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 3)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 4)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 5))
    );
    record.origin = vec2(
        uintBitsToFloat(snailTextSampleWord(glyph_index, 6)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 7))
    );
    record.glyph = uvec2(snailTextSampleWord(glyph_index, 8), snailTextSampleWord(glyph_index, 9));
    record.banding = vec4(
        uintBitsToFloat(snailTextSampleWord(glyph_index, 10)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 11)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 12)),
        uintBitsToFloat(snailTextSampleWord(glyph_index, 13))
    );
    record.color = snailUnpackUnorm4x8(snailTextSampleWord(glyph_index, 14));
    record.tint = snailUnpackUnorm4x8(snailTextSampleWord(glyph_index, 15));
    return record;
}

vec2 snailTextSampleLocalCoord(vec2 scene_pos, vec4 xform, vec2 origin) {
    float det = xform.x * xform.w - xform.y * xform.z;
    vec2 delta = scene_pos - origin;
    return vec2(
        (xform.w * delta.x - xform.y * delta.y) / det,
        (-xform.z * delta.x + xform.x * delta.y) / det
    );
}

vec2 snailTextSampleLocalVector(vec2 scene_vector, vec4 xform) {
    float det = xform.x * xform.w - xform.y * xform.z;
    return vec2(
        (xform.w * scene_vector.x - xform.y * scene_vector.y) / det,
        (-xform.z * scene_vector.x + xform.x * scene_vector.y) / det
    );
}

vec4 snail_text_sample_premul_linear_with_footprint(vec2 scene_pos, vec2 scene_dx, vec2 scene_dy) {
    vec4 paint = vec4(0.0);
    for (int i = 0; i < u_snail_text_glyph_count; i++) {
        SnailTextSampleRecord record = snailTextSampleRecord(i);
        float det = record.xform.x * record.xform.w - record.xform.y * record.xform.z;
        if (abs(det) < 1e-10) continue;
        vec2 rc = snailTextSampleLocalCoord(scene_pos, record.xform, record.origin);
        vec2 local_dx = snailTextSampleLocalVector(scene_dx, record.xform);
        vec2 local_dy = snailTextSampleLocalVector(scene_dy, record.xform);
        vec2 epp = abs(local_dx) + abs(local_dy);
        vec2 em_aa = max(epp * 2.0, vec2(0.001));
        if (rc.x < record.rect.x - em_aa.x || rc.x > record.rect.z + em_aa.x ||
            rc.y < record.rect.y - em_aa.y || rc.y > record.rect.w + em_aa.y) continue;

        uint gz = record.glyph.x;
        uint gw = record.glyph.y;
        int layer_byte = int((gw >> 24u) & 0xFFu);
        if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) continue;
        int atlas_layer = u_layer_base + layer_byte;
        ivec2 glyph_loc = ivec2(int(gz & 0xFFFFu), int(gz >> 16u));
        ivec2 band_max = ivec2(int((gw >> 16u) & 0xFFu), int(gw & 0xFFFFu));
        vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0),
                        1.0 / max(epp.y, 1.0 / 65536.0));
        float cov = evalGlyphCoverage(rc, epp, ppe, glyph_loc, band_max, record.banding, atlas_layer);
        float alpha = clamp(cov * record.color.a * record.tint.a, 0.0, 1.0);
        if (alpha <= 1.0 / 255.0) continue;
        vec3 linear_rgb = srgbToLinear(record.color.rgb) * srgbToLinear(record.tint.rgb);
        paint.rgb = linear_rgb * alpha + paint.rgb * (1.0 - alpha);
        paint.a = alpha + paint.a * (1.0 - alpha);
    }
    return paint;
}

// Convenience for a direct, unconditional call. Custom materials that sample
// coverage multiple times should compute derivatives once at the top of their
// fragment entry point and call the explicit-footprint variant above; that
// keeps every derivative outside prior fragment-dependent glyph control flow.
vec4 snail_text_sample_premul_linear(vec2 scene_pos) {
    return snail_text_sample_premul_linear_with_footprint(scene_pos, dFdx(scene_pos), dFdy(scene_pos));
}
