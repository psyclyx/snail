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
    int subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
};

layout(location = 0) out vec4 frag_color;
#ifdef SNAIL_DUAL_SOURCE
layout(location = 0, index = 1) out vec4 frag_blend;
#endif

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
    if (seg.kind == 3) {
        return mix(seg.p0, seg.p2, t);
    }
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
    if (seg.kind == 3) {
        return seg.p2 - seg.p0;
    }
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
    if (seg.kind == 3) {
        return solveQuadraticRoots(0.0, seg.p2.y - seg.p0.y, seg.p0.y - py);
    }
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
    if (seg.kind == 3) {
        return solveQuadraticRoots(0.0, seg.p2.x - seg.p0.x, seg.p0.x - px);
    }
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
    if (seg.kind == 3) return max(seg.p0.x, seg.p2.x);
    float result = max(max(seg.p0.x, seg.p1.x), seg.p2.x);
    if (seg.kind == 2) result = max(result, seg.p3.x);
    return result;
}

float segmentMaxY(SegmentData seg) {
    if (seg.kind == 3) return max(seg.p0.y, seg.p2.y);
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

struct PathPaintSample {
    vec4 color;
    float gradient;
};

struct PathCompositeSample {
    vec4 color;
    float gradient;
};

float srgbEncode(float c) {
    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec3 linearToSrgb(vec3 color) {
    return vec3(
        srgbEncode(max(color.r, 0.0)),
        srgbEncode(max(color.g, 0.0)),
        srgbEncode(max(color.b, 0.0))
    );
}

vec3 srgbToLinear(vec3 color) {
    return vec3(
        srgbDecode(color.r),
        srgbDecode(color.g),
        srgbDecode(color.b)
    );
}

float interleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

vec4 mixGradient(vec4 c0, vec4 c1, float t) {
    vec4 s0 = vec4(linearToSrgb(c0.rgb), c0.a);
    vec4 s1 = vec4(linearToSrgb(c1.rgb), c1.a);
    vec4 m = mix(s0, s1, t);
    return vec4(srgbToLinear(m.rgb), m.a);
}

vec4 ditherPremultipliedColor(vec4 color) {
    if (color.a <= 0.0) return color;
    float dither = (interleavedGradientNoise(gl_FragCoord.xy) - 0.5) * (clamp(color.a, 0.0, 1.0) / 255.0);
    vec3 srgb = clamp(linearToSrgb(color.rgb) + vec3(dither), 0.0, 1.0);
    return vec4(srgbToLinear(srgb), color.a);
}

PathPaintSample samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    int paintKind = int(-info.w + 0.5);
    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    if (paintKind == 1) {
        return PathPaintSample(vec4(srgbDecode(data0.r), srgbDecode(data0.g), srgbDecode(data0.b), data0.a), 0.0);
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
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, extra.x)), 1.0);
    }

    if (paintKind == 3) {
        float radius = max(abs(data0.z), 1.0 / 65536.0);
        float t = length(rc - data0.xy) / radius;
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0);
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
        return PathPaintSample(sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint, 0.0);
    }

    return PathPaintSample(vec4(1.0, 0.0, 1.0, 1.0), 0.0);
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

vec4 premultiplyColorSubpixel(vec4 color, vec3 cov, float alpha_cov) {
    vec3 alpha = vec3(color.a) * cov;
    return vec4(color.rgb * alpha, color.a * alpha_cov);
}

vec2 evalHorizCoverage(vec2 rc, float xOffset, vec2 ppe,
                       ivec2 gLoc, ivec2 hLoc, int hCount, int layer) {
    return evalAxisCoverage(rc + vec2(xOffset, 0.0), ppe.x, hLoc, hCount, layer, true);
}

vec2 evalVertCoverage(vec2 rc, float yOffset, vec2 ppe,
                      ivec2 vLoc, int vCount, int layer) {
    return evalAxisCoverage(rc + vec2(0.0, yOffset), ppe.y, vLoc, vCount, layer, false);
}

float blendSubpixelSample(vec2 cw_s, vec2 cw_o) {
    float wsum = cw_s.y + cw_o.y;
    float blended = cw_s.x * cw_s.y + cw_o.x * cw_o.y;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                     min(applyFillRule(cw_s.x), applyFillRule(cw_o.x))), 0.0, 1.0);
}

vec4 filterSubpixelCoverage(float s_m3, float s_m2, float s_m1, float s_0, float s_p1, float s_p2, float s_p3, bool reverse_order) {
    const float w0 = 18.0 / 256.0;
    const float w1 = 67.0 / 256.0;
    const float w2 = 86.0 / 256.0;
    float left = w0 * s_m3 + w1 * s_m2 + w2 * s_m1 + w1 * s_0 + w0 * s_p1;
    float center = w0 * s_m2 + w1 * s_m1 + w2 * s_0 + w1 * s_p1 + w0 * s_p2;
    float right = w0 * s_m1 + w1 * s_0 + w2 * s_p1 + w1 * s_p2 + w0 * s_p3;
    vec3 cov = reverse_order ? vec3(right, center, left) : vec3(left, center, right);
    cov = clamp(cov, 0.0, 1.0);
    return vec4(cov, clamp((cov.r + cov.g + cov.b) * (1.0 / 3.0), 0.0, 1.0));
}

void emitSubpixelColor(vec4 color, vec3 cov, float alpha_cov) {
    vec4 premul = premultiplyColorSubpixel(color, cov, alpha_cov);
    frag_color = premul;
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(vec3(color.a) * cov, 0.0);
#endif
}

vec4 evalGlyphCoverageSubpixelLayer(vec2 rc, vec2 epp, vec2 ppe, ivec2 gLoc, ivec2 bandMax, int layer) {
    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);

    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    int hCount = int(hbd.x);

    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    int vCount = int(vbd.x);

    if (subpixel_order <= 2) {
        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
        float sp = epp.x / 3.0;
        float s_m3 = blendSubpixelSample(evalHorizCoverage(rc, -3.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_m2 = blendSubpixelSample(evalHorizCoverage(rc, -2.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_m1 = blendSubpixelSample(evalHorizCoverage(rc, -1.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_0 = blendSubpixelSample(evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_p1 = blendSubpixelSample(evalHorizCoverage(rc, 1.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_p2 = blendSubpixelSample(evalHorizCoverage(rc, 2.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        float s_p3 = blendSubpixelSample(evalHorizCoverage(rc, 3.0 * sp, ppe, gLoc, hLoc, hCount, layer), cw_v);
        return filterSubpixelCoverage(s_m3, s_m2, s_m1, s_0, s_p1, s_p2, s_p3, subpixel_order == 2);
    }

    float sp = epp.y / 3.0;
    vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer);
    float s_m3 = blendSubpixelSample(evalVertCoverage(rc, -3.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    float s_m2 = blendSubpixelSample(evalVertCoverage(rc, -2.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    float s_m1 = blendSubpixelSample(evalVertCoverage(rc, -1.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    float s_0 = blendSubpixelSample(evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer), cw_h);
    float s_p1 = blendSubpixelSample(evalVertCoverage(rc, 1.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    float s_p2 = blendSubpixelSample(evalVertCoverage(rc, 2.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    float s_p3 = blendSubpixelSample(evalVertCoverage(rc, 3.0 * sp, ppe, vLoc, vCount, layer), cw_h);
    return filterSubpixelCoverage(s_m3, s_m2, s_m1, s_0, s_p1, s_p2, s_p3, subpixel_order == 4);
}

PathCompositeSample compositePathGroupSubpixel(vec2 rc, vec2 epp, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer) {
    int layer_count = int(header.x + 0.5);
    int composite_mode = int(header.y + 0.5);
    vec4 result = vec4(0.0);
    float has_gradient = 0.0;
    vec4 fill_cov = vec4(0.0);
    vec4 stroke_cov = vec4(0.0);
    PathPaintSample fill_paint = PathPaintSample(vec4(0.0), 0.0);
    PathPaintSample stroke_paint = PathPaintSample(vec4(0.0), 0.0);

    for (int l = 0; l < layer_count; l++) {
        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        ivec2 gLoc = ivec2(info.xy);
        ivec2 bandMax = ivec2(floatBitsToInt(info.z) & 0xFFFF,
                              (floatBitsToInt(info.z) >> 16) & 0xFFFF);
        vec4 cov = evalGlyphCoverageSubpixelLayer(rc, epp, ppe, gLoc, bandMax, texLayer);
        PathPaintSample paint = samplePathPaint(rc, loc, info);

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

        if (paint.gradient > 0.5 && cov.a > 1e-6) has_gradient = 1.0;
        vec4 premul = premultiplyColorSubpixel(paint.color, cov.rgb, cov.a);
        result = premul + result * (1.0 - premul.a);
    }

    if (composite_mode == 1 && layer_count >= 2) {
        vec3 border_cov = min(fill_cov.rgb, stroke_cov.rgb);
        vec3 interior_cov = max(fill_cov.rgb - border_cov, vec3(0.0));
        float border_alpha = min(fill_cov.a, stroke_cov.a);
        float interior_alpha = max(fill_cov.a - border_alpha, 0.0);
        if (fill_paint.gradient > 0.5 && interior_alpha > 1e-6) has_gradient = 1.0;
        if (stroke_paint.gradient > 0.5 && border_alpha > 1e-6) has_gradient = 1.0;
        vec4 combined = premultiplyColorSubpixel(fill_paint.color, interior_cov, interior_alpha) + premultiplyColorSubpixel(stroke_paint.color, border_cov, border_alpha);
        result = result + combined * (1.0 - result.a);
    }

    return PathCompositeSample(result, has_gradient);
}

void main() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = 1.0 / epp;

    int atlas_layer = (v_glyph.w >> 8) & 0xFF;

    if (atlas_layer == 0xFF) {
        ivec2 infoBase = v_glyph.xy;
        vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
        if (firstInfo.w < 0.0) {
            if (int(-firstInfo.w + 0.5) == 5) {
                PathCompositeSample result = compositePathGroupSubpixel(rc, epp, ppe, infoBase, firstInfo, int(v_banding.w));
                if (result.color.a < 1.0/255.0) discard;
                frag_color = (result.gradient > 0.5) ? ditherPremultipliedColor(result.color) : result.color;
                return;
            }
            vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
            ivec2 gLoc = ivec2(firstInfo.xy);
            ivec2 bandMax = ivec2(floatBitsToInt(firstInfo.z) & 0xFFFF,
                                  (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF);
            int layer = int(v_banding.w);
            vec4 cov_alpha = evalGlyphCoverageSubpixelLayer(rc, epp, ppe, gLoc, bandMax, layer);

            vec3 cov = cov_alpha.rgb;
            if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
            PathPaintSample paint = samplePathPaint(rc, infoBase, firstInfo);
            vec4 result = premultiplyColorSubpixel(paint.color, cov, cov_alpha.a);
            frag_color = (paint.gradient > 0.5) ? ditherPremultipliedColor(result) : result;
            return;
        }

        // Multi-layer COLR: use non-subpixel evaluation
        int layer_count = v_glyph.z;
        vec4 result = vec4(0.0);
        vec4 linear_v_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
        for (int l = 0; l < layer_count; l++) {
            ivec2 loc = offsetLayerLoc(infoBase, l * 3);
            vec4 info  = texelFetch(u_layer_tex, loc, 0);
            vec4 band  = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
            vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
            if (color.r < 0.0) color = linear_v_color;
            else color = vec4(srgbDecode(color.r), srgbDecode(color.g), srgbDecode(color.b), color.a);
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
        return;
    }

    // Single-layer subpixel path
    int layer = atlas_layer;
    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    ivec2 gLoc = v_glyph.xy;
    vec4 cov_alpha = evalGlyphCoverageSubpixelLayer(rc, epp, ppe, gLoc, bandMax, layer);

    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    emitSubpixelColor(linear_color, cov, cov_alpha.a);
}
