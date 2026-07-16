// Specialized fragment body for hinted TrueType text. Hinted text outlines
// are always direct-encoded quadratics with per-instance deltas applied,
// so this path avoids the generic conic/cubic/SegmentData machinery the
// path shader carries.
const float kCoordEps = 1.0 / 65536.0;
const float kParamEps = 1e-5;
const uint kBandCurveLocXMask = 0x0FFFu;
const uint kBandCurveFirstMemberShift = 12u;

ivec2 decodeBandCurveLoc(uvec2 ref) {
    return ivec2(int(ref.x & kBandCurveLocXMask), int(ref.y));
}

int decodeBandCurveFirstMember(uvec2 ref) {
    return int(ref.x >> kBandCurveFirstMemberShift);
}

ivec2 offsetLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

int curveTexelFromLoc(ivec2 loc) {
    return loc.y * (1 << kLogBandTextureWidth) + loc.x;
}

struct HintedTextRecord {
    ivec2 infoBase;
    int baseCurveTexel;
    int flags;
    ivec2 bandPad;
};

bool hintedTextHasExpandedBands(HintedTextRecord record) {
    return (record.flags & SNAIL_HINT_RECORD_FLAG_EXPANDED_BANDS) != 0;
}

bool hintedTextHasUnorderedBands(HintedTextRecord record) {
    return (record.flags & SNAIL_HINT_RECORD_FLAG_UNORDERED_BANDS) != 0;
}

// Cancellation-free quadratic Bezier root substitution, returning the
// "along" coordinate at both roots. Mirrors the unhinted text fast path.
vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float t1, t2;
    if (abs(a.y) < kCoordEps) {
        t1 = (abs(b.y) < kCoordEps) ? 0.0 : p12.y * 0.5 / b.y;
        t2 = t1;
    } else {
        float sq = snapNearTangentSqrt(b.y * b.y - a.y * p12.y, b.y, a.y * p12.y);
        if (b.y >= 0.0) {
            float q = b.y + sq;
            t2 = q / a.y;
            t1 = (abs(q) < kCoordEps) ? 0.0 : p12.y / q;
        } else {
            float q = b.y - sq;
            t1 = q / a.y;
            t2 = (abs(q) < kCoordEps) ? 0.0 : p12.y / q;
        }
    }
    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

vec2 solveVertPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float t1, t2;
    if (abs(a.x) < kCoordEps) {
        t1 = (abs(b.x) < kCoordEps) ? 0.0 : p12.x * 0.5 / b.x;
        t2 = t1;
    } else {
        float sq = snapNearTangentSqrt(b.x * b.x - a.x * p12.x, b.x, a.x * p12.x);
        if (b.x >= 0.0) {
            float q = b.x + sq;
            t2 = q / a.x;
            t1 = (abs(q) < kCoordEps) ? 0.0 : p12.x / q;
        } else {
            float q = b.x - sq;
            t1 = q / a.x;
            t2 = (abs(q) < kCoordEps) ? 0.0 : p12.x / q;
        }
    }
    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

void appendContribution(inout float cov, inout float wgt, float distance, float sign) {
    cov += sign * clamp(distance + 0.5, 0.0, 1.0);
    wgt = max(wgt, clamp(1.0 - abs(distance) * 2.0, 0.0, 1.0));
}

// Fetch a hinted quadratic curve's three control points relativised to
// `sampleRc`. The hinted snapshot stores absolute positions directly in
// the layer-info slab, so this never consults u_curve_tex — only the
// band reference (cLoc) is used to derive the curve index into the
// snapshot's per-glyph point block.
void fetchHintedQuadratic(ivec2 cLoc, HintedTextRecord record, vec2 sampleRc,
                          out vec2 p0, out vec2 p1, out vec2 p2) {
    int curveIndex = (curveTexelFromLoc(cLoc) - record.baseCurveTexel) >> 2;
    int pointOffset = 3 + curveIndex * 2;
    vec4 pts0 = texelFetch(u_layer_tex, offsetLayerLoc(record.infoBase, pointOffset), 0);
    vec4 pts1 = texelFetch(u_layer_tex, offsetLayerLoc(record.infoBase, pointOffset + 1), 0);
    p0 = pts0.xy - sampleRc;
    p1 = pts0.zw - sampleRc;
    p2 = pts1.xy - sampleRc;
}

// Accumulate one quadratic's contribution. Returns false when the curve's
// max-along coordinate is far enough behind sampleRc that ordered-band
// callers can stop scanning.
bool accumulateQuadratic(inout float cov, inout float wgt, vec2 p0, vec2 p1, vec2 p2,
                         float ppe, bool horizontal) {
    float maxAlong = horizontal ? max(max(p0.x, p1.x), p2.x) : max(max(p0.y, p1.y), p2.y);
    if (maxAlong * ppe < -0.5) return false;
    uint code = horizontal ? calcRootCode(p0.y, p1.y, p2.y) : calcRootCode(p0.x, p1.x, p2.x);
    if (code == 0u) return true;
    vec2 roots = horizontal
        ? solveHorizPoly(vec4(p0, p1), p2) * ppe
        : solveVertPoly(vec4(p0, p1), p2) * ppe;
    if (horizontal) {
        if ((code & 1u) != 0u) appendContribution(cov, wgt, roots.x, 1.0);
        if (code > 1u) appendContribution(cov, wgt, roots.y, -1.0);
    } else {
        if ((code & 1u) != 0u) appendContribution(cov, wgt, roots.x, -1.0);
        if (code > 1u) appendContribution(cov, wgt, roots.y, 1.0);
    }
    return true;
}

vec2 evalSingleBand(vec2 sampleRc, float ppe, ivec2 gLoc, int headerOffset, int layer,
                    bool horizontal, bool ordered, HintedTextRecord record) {
    float cov = 0.0;
    float wgt = 0.0;
    ivec2 headerLoc = calcBandLoc(gLoc, uint(headerOffset));
    uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
    ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
    int count = int(bd.x);
    for (int i = 0; i < count; i++) {
        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
        ivec2 cLoc = decodeBandCurveLoc(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
        vec2 p0, p1, p2;
        fetchHintedQuadratic(cLoc, record, sampleRc, p0, p1, p2);
        if (!accumulateQuadratic(cov, wgt, p0, p1, p2, ppe, horizontal) && ordered) break;
    }
    return vec2(cov, wgt);
}

vec2 evalMultiBand(vec2 sampleRc, float ppe, ivec2 gLoc, int headerBase, int firstBand, int lastBand,
                   int layer, bool horizontal, bool ordered, HintedTextRecord record) {
    float cov = 0.0;
    float wgt = 0.0;
    bool dedup = firstBand != lastBand;
    for (int band = firstBand; band <= lastBand; band++) {
        ivec2 headerLoc = calcBandLoc(gLoc, uint(headerBase + band));
        uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
        ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
        int count = int(bd.x);
        for (int i = 0; i < count; i++) {
            ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
            uvec2 ref = texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy;
            if (dedup) {
                int ownerBand = max(decodeBandCurveFirstMember(ref), firstBand);
                if (band != ownerBand) continue;
            }
            ivec2 cLoc = decodeBandCurveLoc(ref);
            vec2 p0, p1, p2;
            fetchHintedQuadratic(cLoc, record, sampleRc, p0, p1, p2);
            if (!accumulateQuadratic(cov, wgt, p0, p1, p2, ppe, horizontal) && ordered) break;
        }
    }
    return vec2(cov, wgt);
}

struct BandSpan {
    int first;
    int last;
};

BandSpan coverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax) {
    float center = coord * bandScale + bandOffset;
    float halfWidth = max(abs(eppAxis * bandScale) * 0.5, kParamEps);
    int first = clamp(int(center - halfWidth), 0, bandMax);
    int last = clamp(int(center + halfWidth), 0, bandMax);
    return BandSpan(first, max(first, last));
}

BandSpan expandBandSpan(BandSpan span, int pad, int bandMax) {
    return BandSpan(max(span.first - pad, 0), min(span.last + pad, bandMax));
}

vec2 evalAxis(vec2 sampleRc, float ppe, ivec2 gLoc, int headerBase, BandSpan span, int layer,
              bool horizontal, bool ordered, HintedTextRecord record) {
    if (span.first == span.last) {
        return evalSingleBand(sampleRc, ppe, gLoc, headerBase + span.first, layer, horizontal, ordered, record);
    }
    return evalMultiBand(sampleRc, ppe, gLoc, headerBase, span.first, span.last, layer, horizontal, ordered, record);
}

float evalHintedTextCoverage(vec2 rc, vec2 epp, vec2 ppe, ivec2 gLoc, ivec2 bandMax,
                             vec4 banding, int layer, HintedTextRecord record) {
    BandSpan hSpan = coverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    BandSpan vSpan = coverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    if (hintedTextHasExpandedBands(record)) {
        hSpan = expandBandSpan(hSpan, record.bandPad.x, bandMax.y);
        vSpan = expandBandSpan(vSpan, record.bandPad.y, bandMax.x);
    }
    bool ordered = !hintedTextHasUnorderedBands(record);
    vec2 horiz = evalAxis(rc, ppe.x, gLoc, 0, hSpan, layer, true, ordered, record);
    vec2 vert = evalAxis(rc, ppe.y, gLoc, bandMax.y + 1, vSpan, layer, false, ordered, record);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, kCoordEps)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return applyCoverageTransfer(cov);
}

void snailHintedTextFragment() {
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte != SNAIL_SPECIAL_LAYER_SENTINEL) discard;
    int special_kind = v_glyph.w & 0xFF;
    if (special_kind != SNAIL_SPECIAL_KIND_HINTED_TEXT) discard;

    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = 1.0 / max(epp, vec2(kCoordEps));

    ivec2 infoBase = v_glyph.xy;
    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    vec4 meta = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    ivec2 gLoc = ivec2(firstInfo.xy);
    int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
    int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
    int texLayer = u_layer_base + int(v_banding.w);

    HintedTextRecord record;
    record.infoBase = infoBase;
    record.baseCurveTexel = int(meta.x + 0.5);
    record.flags = int(meta.z + 0.5);
    int bandPad = int(meta.w + 0.5);
    record.bandPad = ivec2(bandPad & 0xffff, bandPad >> 16);

    float cov = evalHintedTextCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer, record);
    if (cov < 1.0 / 255.0) discard;

    // v_color / v_tint are already sRGB-decoded in the vertex shader.
    vec4 result = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(result.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(result) : result);
}
