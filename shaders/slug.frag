#version 450

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_texcoord;
layout(location = 2) flat in vec4 v_banding;
layout(location = 3) flat in ivec4 v_glyph;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;
layout(set = 0, binding = 2) uniform sampler2D u_layer_tex;
layout(set = 0, binding = 3) uniform sampler2DArray u_image_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
};

layout(location = 0) out vec4 frag_color;

#define kLogBandTextureWidth 12
#define kDirectEncodingKindBias 4.0
uint calcRootCode(float y1, float y2, float y3) {
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

float applyFillRule(float winding) {
    if (fill_rule == 1) {
        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    }
    return abs(winding);
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

ivec2 offsetLayerLoc(ivec2 base, int offset) {
    ivec2 loc = ivec2(base.x + offset, base.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

struct SegmentRoots {
    int count;
    vec3 t;
};

struct SegmentData {
    int kind;
    vec2 p0;
    vec2 p1;
    vec2 p2;
    vec2 p3;
    vec3 weights;
};

float cbrtSigned(float v) {
    return (v == 0.0) ? 0.0 : sign(v) * pow(abs(v), 1.0 / 3.0);
}

void appendRoot(inout SegmentRoots roots, float t) {
    if (roots.count >= 3) return;
    if (t < -1e-5 || t > 1.0 + 1e-5) return;
    float clamped = clamp(t, 0.0, 1.0);
    for (int i = 0; i < roots.count; i++) {
        if (abs(roots.t[i] - clamped) <= 1e-5) return;
    }
    int insertAt = roots.count;
    while (insertAt > 0 && roots.t[insertAt - 1] > clamped) {
        roots.t[insertAt] = roots.t[insertAt - 1];
        insertAt--;
    }
    roots.t[insertAt] = clamped;
    roots.count++;
}

SegmentRoots solveQuadraticRoots(float a, float b, float cVal) {
    SegmentRoots roots;
    roots.count = 0;
    roots.t = vec3(0.0);
    if (abs(a) < 1.0 / 65536.0) {
        if (abs(b) < 1.0 / 65536.0) return roots;
        appendRoot(roots, -cVal / b);
        return roots;
    }
    float disc = b * b - 4.0 * a * cVal;
    if (disc < 0.0) {
        if (disc > -1e-6) {
            disc = 0.0;
        } else {
            return roots;
        }
    }
    float sqrtDisc = sqrt(disc);
    float inv2a = 0.5 / a;
    appendRoot(roots, (-b - sqrtDisc) * inv2a);
    appendRoot(roots, (-b + sqrtDisc) * inv2a);
    return roots;
}

SegmentRoots solveCubicRoots(float a, float b, float cVal, float d) {
    if (abs(a) < 1.0 / 65536.0) {
        return solveQuadraticRoots(b, cVal, d);
    }
    SegmentRoots roots;
    roots.count = 0;
    roots.t = vec3(0.0);
    float invA = 1.0 / a;
    float aa = b * invA;
    float bb = cVal * invA;
    float cc = d * invA;
    float p = bb - aa * aa / 3.0;
    float q = (2.0 * aa * aa * aa) / 27.0 - (aa * bb) / 3.0 + cc;
    float halfQ = q * 0.5;
    float thirdP = p / 3.0;
    float disc = halfQ * halfQ + thirdP * thirdP * thirdP;
    float offset = aa / 3.0;
    if (disc > 1e-8) {
        float sqrtDisc = sqrt(disc);
        float u = cbrtSigned(-halfQ + sqrtDisc);
        float v = cbrtSigned(-halfQ - sqrtDisc);
        appendRoot(roots, u + v - offset);
        return roots;
    }
    if (disc >= -1e-8) {
        float u = cbrtSigned(-halfQ);
        appendRoot(roots, 2.0 * u - offset);
        appendRoot(roots, -u - offset);
        return roots;
    }
    float r = sqrt(-thirdP);
    float phi = acos(clamp(-halfQ / (r * r * r), -1.0, 1.0));
    float twoR = 2.0 * r;
    appendRoot(roots, twoR * cos(phi / 3.0) - offset);
    appendRoot(roots, twoR * cos((phi + 2.0 * 3.14159265358979323846) / 3.0) - offset);
    appendRoot(roots, twoR * cos((phi + 4.0 * 3.14159265358979323846) / 3.0) - offset);
    return roots;
}

vec2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX) {
    float ax = p0x - p1x * 2.0 + p2x;
    float ay = p0y - p1y * 2.0 + p2y;
    float bx = p0x - p1x;
    float by = p0y - p1y;

    float t1;
    float t2;
    if (abs(ay) < 1.0 / 65536.0) {
        float rb = 0.5 / by;
        t1 = p0y * rb;
        t2 = t1;
    } else {
        float ra = 1.0 / ay;
        float d = sqrt(max(by * by - ay * p0y, 0.0));
        t1 = (by - d) * ra;
        t2 = (by + d) * ra;
    }

    float x1 = (ax * t1 - bx * 2.0) * t1 + p0x;
    float x2 = (ax * t2 - bx * 2.0) * t2 + p0x;
    return vec2(x1 * ppeX, x2 * ppeX);
}

vec2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY) {
    float ax = p0x - p1x * 2.0 + p2x;
    float ay = p0y - p1y * 2.0 + p2y;
    float bx = p0x - p1x;
    float by = p0y - p1y;

    float t1;
    float t2;
    if (abs(ax) < 1.0 / 65536.0) {
        float rb = 0.5 / bx;
        t1 = p0x * rb;
        t2 = t1;
    } else {
        float ra = 1.0 / ax;
        float d = sqrt(max(bx * bx - ax * p0x, 0.0));
        t1 = (bx - d) * ra;
        t2 = (bx + d) * ra;
    }

    float y1 = (ay * t1 - by * 2.0) * t1 + p0y;
    float y2 = (ay * t2 - by * 2.0) * t2 + p0y;
    return vec2(y1 * ppeY, y2 * ppeY);
}

SegmentData fetchSegment(ivec2 loc, int layer) {
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(loc + ivec2(1, 0), layer), 0);
    vec4 tex2 = texelFetch(u_curve_tex, ivec3(loc + ivec2(2, 0), layer), 0);
    vec4 meta = texelFetch(u_curve_tex, ivec3(loc + ivec2(3, 0), layer), 0);
    SegmentData seg;
    bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    if (direct) {
        seg.kind = int(tex2.z - kDirectEncodingKindBias + 0.5);
        seg.p0 = tex0.xy;
        seg.p1 = tex0.zw;
        seg.p2 = tex1.xy;
        seg.p3 = tex1.zw;
    } else {
        vec2 anchor = tex0.xy * 256.0 + tex0.zw;
        seg.kind = int(tex2.z + 0.5);
        seg.p0 = anchor;
        seg.p1 = anchor + tex1.xy;
        seg.p2 = anchor + tex1.zw;
        seg.p3 = anchor + tex2.xy;
    }
    seg.weights = vec3(tex2.w, meta.x, meta.y);
    return seg;
}

vec2 evalSegmentPoint(SegmentData seg, float t) {
    float mt = 1.0 - t;
    if (seg.kind == 2) {
        return mt * mt * mt * seg.p0 +
            3.0 * mt * mt * t * seg.p1 +
            3.0 * mt * t * t * seg.p2 +
            t * t * t * seg.p3;
    }
    if (seg.kind == 1) {
        float b0 = mt * mt;
        float b1 = 2.0 * mt * t;
        float b2 = t * t;
        float bw0 = b0 * seg.weights.x;
        float bw1 = b1 * seg.weights.y;
        float bw2 = b2 * seg.weights.z;
        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
        return (seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2) / denom;
    }
    return mt * mt * seg.p0 + 2.0 * mt * t * seg.p1 + t * t * seg.p2;
}

vec2 evalSegmentDerivative(SegmentData seg, float t) {
    float mt = 1.0 - t;
    if (seg.kind == 2) {
        return 3.0 * mt * mt * (seg.p1 - seg.p0) +
            6.0 * mt * t * (seg.p2 - seg.p1) +
            3.0 * t * t * (seg.p3 - seg.p2);
    }
    if (seg.kind == 1) {
        float b0 = mt * mt;
        float b1 = 2.0 * mt * t;
        float b2 = t * t;
        float db0 = -2.0 * mt;
        float db1 = 2.0 - 4.0 * t;
        float db2 = 2.0 * t;
        float bw0 = b0 * seg.weights.x;
        float bw1 = b1 * seg.weights.y;
        float bw2 = b2 * seg.weights.z;
        float dbw0 = db0 * seg.weights.x;
        float dbw1 = db1 * seg.weights.y;
        float dbw2 = db2 * seg.weights.z;
        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
        float denomPrime = dbw0 + dbw1 + dbw2;
        vec2 numer = seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2;
        vec2 numerPrime = seg.p0 * dbw0 + seg.p1 * dbw1 + seg.p2 * dbw2;
        return (numerPrime * denom - numer * denomPrime) / (denom * denom);
    }
    return 2.0 * mt * (seg.p1 - seg.p0) + 2.0 * t * (seg.p2 - seg.p1);
}

SegmentRoots solveSegmentHorizontalRoots(SegmentData seg, float py) {
    if (seg.kind == 2) {
        float a = -seg.p0.y + 3.0 * seg.p1.y - 3.0 * seg.p2.y + seg.p3.y;
        float b = 3.0 * seg.p0.y - 6.0 * seg.p1.y + 3.0 * seg.p2.y;
        float cVal = -3.0 * seg.p0.y + 3.0 * seg.p1.y;
        float d = seg.p0.y - py;
        return solveCubicRoots(a, b, cVal, d);
    }
    if (seg.kind == 1) {
        float c0 = seg.weights.x * (seg.p0.y - py);
        float c1 = seg.weights.y * (seg.p1.y - py);
        float c2 = seg.weights.z * (seg.p2.y - py);
        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    }
    float a = seg.p0.y - 2.0 * seg.p1.y + seg.p2.y;
    float b = 2.0 * (seg.p1.y - seg.p0.y);
    return solveQuadraticRoots(a, b, seg.p0.y - py);
}

SegmentRoots solveSegmentVerticalRoots(SegmentData seg, float px) {
    if (seg.kind == 2) {
        float a = -seg.p0.x + 3.0 * seg.p1.x - 3.0 * seg.p2.x + seg.p3.x;
        float b = 3.0 * seg.p0.x - 6.0 * seg.p1.x + 3.0 * seg.p2.x;
        float cVal = -3.0 * seg.p0.x + 3.0 * seg.p1.x;
        float d = seg.p0.x - px;
        return solveCubicRoots(a, b, cVal, d);
    }
    if (seg.kind == 1) {
        float c0 = seg.weights.x * (seg.p0.x - px);
        float c1 = seg.weights.y * (seg.p1.x - px);
        float c2 = seg.weights.z * (seg.p2.x - px);
        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    }
    float a = seg.p0.x - 2.0 * seg.p1.x + seg.p2.x;
    float b = 2.0 * (seg.p1.x - seg.p0.x);
    return solveQuadraticRoots(a, b, seg.p0.x - px);
}

float segmentMaxX(SegmentData seg) {
    float result = max(max(seg.p0.x, seg.p1.x), seg.p2.x);
    if (seg.kind == 2) result = max(result, seg.p3.x);
    return result;
}

float segmentMaxY(SegmentData seg) {
    float result = max(max(seg.p0.y, seg.p1.y), seg.p2.y);
    if (seg.kind == 2) result = max(result, seg.p3.y);
    return result;
}

vec2 evalAxisCoverage(vec2 sampleRc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    float cov = 0.0;
    float wgt = 0.0;
    for (int i = 0; i < count; i++) {
        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
        SegmentData seg = fetchSegment(cLoc, layer);
        float maxCoord = (horizontal ? segmentMaxX(seg) - sampleRc.x : segmentMaxY(seg) - sampleRc.y);
        if (maxCoord * ppe < -0.5) break;
        if (seg.kind == 0) {
            float p0x = seg.p0.x - sampleRc.x;
            float p0y = seg.p0.y - sampleRc.y;
            float p1x = seg.p1.x - sampleRc.x;
            float p1y = seg.p1.y - sampleRc.y;
            float p2x = seg.p2.x - sampleRc.x;
            float p2y = seg.p2.y - sampleRc.y;
            uint code = horizontal ? calcRootCode(p0y, p1y, p2y) : calcRootCode(p0x, p1x, p2x);
            if (code == 0u) continue;

            vec2 roots = horizontal
                ? solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
                : solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

            if ((code & 1u) != 0u) {
                cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
                wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u) {
                cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
                wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
            }
            continue;
        }
        SegmentRoots roots = horizontal ? solveSegmentHorizontalRoots(seg, sampleRc.y) : solveSegmentVerticalRoots(seg, sampleRc.x);
        for (int ri = 0; ri < roots.count; ri++) {
            float t = roots.t[ri];
            // Treat segment intersections as half-open [0, 1) so shared joins
            // between adjacent segments are counted once instead of twice.
            if (t >= 1.0 - 1e-5) continue;
            vec2 point = evalSegmentPoint(seg, t);
            vec2 deriv = evalSegmentDerivative(seg, t);
            float derivAxis = horizontal ? deriv.y : -deriv.x;
            if (abs(derivAxis) <= 1e-5) continue;
            float dist = (horizontal ? point.x - sampleRc.x : point.y - sampleRc.y) * ppe;
            cov += (derivAxis > 0.0 ? 1.0 : -1.0) * clamp(dist + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(dist) * 2.0, 0.0, 1.0));
        }
    }
    return vec2(cov, wgt);
}

float wrapPaintT(float t, float extendMode) {
    int mode = int(extendMode + 0.5);
    if (mode == 1) {
        return fract(t);
    }
    if (mode == 2) {
        float reflected = mod(t, 2.0);
        if (reflected < 0.0) reflected += 2.0;
        return 1.0 - abs(reflected - 1.0);
    }
    return clamp(t, 0.0, 1.0);
}

vec4 sampleImagePaintTex(vec2 uv, int layer, int filterMode) {
    if (filterMode == 1) {
        ivec3 size = textureSize(u_image_tex, 0);
        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    }
    return texture(u_image_tex, vec3(uv, float(layer)));
}

float gradientDitherNoise(vec2 fragCoord) {
    vec2 cell = floor(fragCoord);
    float a = fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
    float b = fract(52.9829189 * fract(dot(cell + vec2(17.0, 43.0), vec2(0.06711056, 0.00583715))));
    return (a + b - 1.0) * (0.75 / 255.0);
}

vec4 ditherGradientPaint(vec4 color) {
    float dither = gradientDitherNoise(gl_FragCoord.xy);
    return vec4(clamp(color.rgb + vec3(dither), vec3(0.0), vec3(1.0)), color.a);
}

vec4 samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    int paintKind = int(-info.w + 0.5);
    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    if (paintKind == 1) {
        return data0;
    }

    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);

    if (paintKind == 2) {
        vec2 delta = data0.zw - data0.xy;
        float lenSq = dot(delta, delta);
        float t = 0.0;
        if (lenSq > 1e-10) {
            t = dot(rc - data0.xy, delta) / lenSq;
        }
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        return ditherGradientPaint(mix(color0, color1, wrapPaintT(t, extra.x)));
    }

    if (paintKind == 3) {
        float radius = max(abs(data0.z), 1.0 / 65536.0);
        float t = length(rc - data0.xy) / radius;
        return ditherGradientPaint(mix(color0, color1, wrapPaintT(t, data0.w)));
    }

    if (paintKind == 4) {
        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
        vec4 tint = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        vec2 rawUv = vec2(
            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
        );
        vec2 wrappedUv = vec2(
            wrapPaintT(rawUv.x, extra.z) * extra.x,
            wrapPaintT(rawUv.y, extra.w) * extra.y
        );
        return sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint;
    }

    return vec4(1.0, 0.0, 1.0, 1.0);
}

float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe,
                        ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    int hCount = int(hbd.x);
    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    int vCount = int(vbd.x);
    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return clamp(cov, 0.0, 1.0);
}

vec4 premultiplyColor(vec4 color, float cov) {
    float alpha = color.a * cov;
    return vec4(color.rgb * alpha, alpha);
}

vec4 compositePathGroup(vec2 rc, vec2 epp, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer) {
    int layer_count = int(header.x + 0.5);
    int composite_mode = int(header.y + 0.5);
    vec4 result = vec4(0.0);
    float fill_cov = 0.0;
    float stroke_cov = 0.0;
    vec4 fill_paint = vec4(0.0);
    vec4 stroke_paint = vec4(0.0);

    for (int l = 0; l < layer_count; l++) {
        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(loc, 1), 0);
        ivec2 gLoc = ivec2(info.xy);
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
        vec4 paint = samplePathPaint(rc, loc, info);

        if (composite_mode == 1 && layer_count >= 2 && l < 2) {
            if (l == 0) {
                fill_cov = cov;
                fill_paint = paint;
            } else {
                stroke_cov = cov;
                stroke_paint = paint;
            }
            continue;
        }

        vec4 premul = premultiplyColor(paint, cov);
        result = premul + result * (1.0 - premul.a);
    }

    if (composite_mode == 1 && layer_count >= 2) {
        float border_cov = min(fill_cov, stroke_cov);
        float interior_cov = max(fill_cov - border_cov, 0.0);
        vec4 combined = premultiplyColor(fill_paint, interior_cov) + premultiplyColor(stroke_paint, border_cov);
        result = result + combined * (1.0 - result.a);
    }

    return result;
}

void main() {
    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = 1.0 / epp;

    int atlas_layer = (v_glyph.w >> 8) & 0xFF;

    if (atlas_layer == 0xFF) {
        ivec2 infoBase = v_glyph.xy;
        vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
        if (firstInfo.w < 0.0) {
            if (int(-firstInfo.w + 0.5) == 5) {
                vec4 result = compositePathGroup(rc, epp, ppe, infoBase, firstInfo, int(v_banding.w));
                if (result.a < 1.0/255.0) discard;
                frag_color = result;
                return;
            }
            vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
            ivec2 lGLoc = ivec2(firstInfo.xy);
            int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
            int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
            int texLayer = int(v_banding.w);
            float cov = evalGlyphCoverage(rc, epp, ppe, lGLoc,
                                          ivec2(bandMaxH, bandMaxV), band, texLayer);
            if (cov < 1.0/255.0) discard;
            frag_color = premultiplyColor(samplePathPaint(rc, infoBase, firstInfo), cov);
            return;
        }

        int layer_count = v_glyph.z;
        vec4 result = vec4(0.0);
        for (int l = 0; l < layer_count; l++) {
            ivec2 loc = offsetLayerLoc(infoBase, l * 3);
            vec4 info  = texelFetch(u_layer_tex, loc, 0);
            vec4 band  = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
            vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
            if (color.r < 0.0) color = v_color;
            ivec2 lGLoc = ivec2(info.xy);
            int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
            int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
            int texLayer = int(v_banding.w);
            float cov = evalGlyphCoverage(rc, epp, ppe, lGLoc,
                                          ivec2(bandMaxH, bandMaxV), band, texLayer);
            vec4 premul = premultiplyColor(color, cov);
            result = premul + result * (1.0 - premul.a);
        }
        if (result.a < 1.0/255.0) discard;
        frag_color = result;
    } else {
        float cov = evalGlyphCoverage(rc, epp, ppe, v_glyph.xy,
                                      ivec2(v_glyph.z, v_glyph.w & 0xFF),
                                      v_banding, atlas_layer);
        if (cov < 1.0/255.0) discard;
        frag_color = premultiplyColor(v_color, cov);
    }
}
