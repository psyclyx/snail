#version 330

struct PaintedVaryings
{
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};

struct PaintedParams
{
    int layer_base;
    int output_srgb;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
};

struct PathPaintSample
{
    vec4 color;
    float gradient;
};

struct PathCompositeSample
{
    vec4 color;
    float gradient;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

struct SegmentData
{
    int kind;
    vec2 p0;
    vec2 p1;
    vec2 p2;
    vec2 p3;
    vec3 weights;
};

uvec4 _511;
uvec4 _529;

layout(std140) uniform SnailPushConstants_std140
{
    layout(row_major) mat4 mvp;
    vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
} pc;

uniform sampler2D SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler;
uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_image_texu_image_sampler;

in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

vec2 _fwidth(vec2 x)
{
    return fwidth(x);
}

PathPaintSample PathPaintSample_init(vec4 color, float gradient)
{
    PathPaintSample _276;
    _276.color = color;
    _276.gradient = gradient;
    return _276;
}

ivec2 offsetLayerLoc(ivec2 _300, int _301)
{
    uvec2 vecSize = uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0));
    uint uw = vecSize.x;
    uint uh = vecSize.y;
    int width = int(uw);
    int texel = ((_300.y * width) + _300.x) + _301;
    return ivec2(texel - width * (texel / width), texel / width);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _402;
    _402.first = first;
    _402.last = last;
    return _402;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _386 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _390 = clamp(int(center - _386), 0, bandMax);
    return CoverageBandSpan_init(_390, max(_390, clamp(int(center + _386), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _485 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_485, glyphLoc.y);
    loc.y += (_485 >> 12);
    loc.x &= 4095;
    return loc;
}

int decodeBandCurveFirstMemberCommon(uvec2 ref)
{
    return int(ref.x >> 12u);
}

ivec2 decodeBandCurveLocCommon(uvec2 ref)
{
    return ivec2(int(ref.x & 4095u), int(ref.y & 16383u));
}

int decodeBandCurveKindCommon(uvec2 ref)
{
    return int(ref.y >> 14u);
}

ivec2 offsetCurveLoc(ivec2 base, int offset)
{
    int _598 = base.x + offset;
    ivec2 loc = ivec2(_598, base.y);
    loc.y += (_598 >> 12);
    loc.x &= 4095;
    return loc;
}

SegmentData fetchSegment(ivec2 _575, int _576, int _577)
{
    vec4 _590 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_575, _576, 0).xyz, 0);
    vec4 _617 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_575, 1), _576, 0).xyz, 0);
    SegmentData seg;
    seg.kind = _577;
    seg.p0 = _590.xy;
    seg.p1 = _590.zw;
    seg.p2 = _617.xy;
    seg.p3 = _617.zw;
    if (_577 == 1)
    {
        vec4 _639 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_575, 2), _576, 0).xyz, 0);
        seg.weights = vec3(_639.wxy);
    }
    else
    {
        seg.weights = vec3(1.0);
    }
    return seg;
}

float segmentMaxX(SegmentData seg)
{
    if (seg.kind == 3)
    {
        return max(seg.p0.x, seg.p2.x);
    }
    if (seg.kind == 2)
    {
        return max(max(seg.p0.x, seg.p1.x), max(seg.p2.x, seg.p3.x));
    }
    return max(max(seg.p0.x, seg.p1.x), seg.p2.x);
}

float segmentMaxY(SegmentData seg)
{
    if (seg.kind == 3)
    {
        return max(seg.p0.y, seg.p2.y);
    }
    if (seg.kind == 2)
    {
        return max(max(seg.p0.y, seg.p1.y), max(seg.p2.y, seg.p3.y));
    }
    return max(max(seg.p0.y, seg.p1.y), seg.p2.y);
}

float rootCodeCoord(float v)
{
    float _1022;
    if (abs(v) <= 1.52587890625e-05)
    {
        _1022 = 0.0;
    }
    else
    {
        _1022 = v;
    }
    return _1022;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _1135;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _1135 = 0.0;
    }
    else
    {
        _1135 = sqrt(disc);
    }
    return _1135;
}

vec2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX)
{
    float ax = (p0x - (p1x * 2.0)) + p2x;
    float ay = (p0y - (p1y * 2.0)) + p2y;
    float by = p0y - p1y;
    float t1;
    float t2;
    if (abs(ay) < 1.52587890625e-05)
    {
        if (abs(by) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p0y * 0.5) / by;
        }
        t2 = t1;
    }
    else
    {
        float _1126 = ay * p0y;
        float sq = snapNearTangentSqrt((by * by) - _1126, by, _1126);
        if (by >= 0.0)
        {
            float q = by + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p0y / q;
            }
            t2 = q / ay;
        }
        else
        {
            float q_1 = by - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p0y / q_1;
            }
            float _1177 = t1;
            t1 = q_1 / ay;
            t2 = _1177;
        }
    }
    float _1184 = (p0x - p1x) * 2.0;
    return vec2(((((ax * t1) - _1184) * t1) + p0x) * ppeX, ((((ax * t2) - _1184) * t2) + p0x) * ppeX);
}

vec2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY)
{
    float ax = (p0x - (p1x * 2.0)) + p2x;
    float ay = (p0y - (p1y * 2.0)) + p2y;
    float bx = p0x - p1x;
    float t1;
    float t2;
    if (abs(ax) < 1.52587890625e-05)
    {
        if (abs(bx) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p0x * 0.5) / bx;
        }
        t2 = t1;
    }
    else
    {
        float _1252 = ax * p0x;
        float sq = snapNearTangentSqrt((bx * bx) - _1252, bx, _1252);
        if (bx >= 0.0)
        {
            float q = bx + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p0x / q;
            }
            t2 = q / ax;
        }
        else
        {
            float q_1 = bx - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p0x / q_1;
            }
            float _1279 = t1;
            t1 = q_1 / ax;
            t2 = _1279;
        }
    }
    float _1286 = (p0y - p1y) * 2.0;
    return vec2(((((ay * t1) - _1286) * t1) + p0y) * ppeY, ((((ay * t2) - _1286) * t2) + p0y) * ppeY);
}

bool rootHullCanCross4(float p0, float p1, float p2, float p3, float sampleRoot)
{
    bool _1561;
    if ((min(min(p0, p1), min(p2, p3)) - sampleRoot) <= 1.52587890625e-05)
    {
        _1561 = (max(max(p0, p1), max(p2, p3)) - sampleRoot) >= (-1.52587890625e-05);
    }
    else
    {
        _1561 = false;
    }
    return _1561;
}

bool rootHullCanCross3(float p0, float p1, float p2, float sampleRoot)
{
    bool _1629;
    if ((min(min(p0, p1), p2) - sampleRoot) <= 1.52587890625e-05)
    {
        _1629 = (max(max(p0, p1), p2) - sampleRoot) >= (-1.52587890625e-05);
    }
    else
    {
        _1629 = false;
    }
    return _1629;
}

bool segmentRootHullCanCross(SegmentData seg, vec2 sampleRc, bool horizontal)
{
    float sampleRoot;
    if (horizontal)
    {
        sampleRoot = sampleRc.y;
    }
    else
    {
        sampleRoot = sampleRc.x;
    }
    float _1462;
    float _1463;
    float _1464;
    if (seg.kind == 2)
    {
        if (horizontal)
        {
            _1462 = seg.p0.y;
        }
        else
        {
            _1462 = seg.p0.x;
        }
        if (horizontal)
        {
            _1463 = seg.p1.y;
        }
        else
        {
            _1463 = seg.p1.x;
        }
        if (horizontal)
        {
            _1464 = seg.p2.y;
        }
        else
        {
            _1464 = seg.p2.x;
        }
        float _1465;
        if (horizontal)
        {
            _1465 = seg.p3.y;
        }
        else
        {
            _1465 = seg.p3.x;
        }
        return rootHullCanCross4(_1462, _1463, _1464, _1465, sampleRoot);
    }
    if (horizontal)
    {
        _1462 = seg.p0.y;
    }
    else
    {
        _1462 = seg.p0.x;
    }
    if (horizontal)
    {
        _1463 = seg.p1.y;
    }
    else
    {
        _1463 = seg.p1.x;
    }
    if (horizontal)
    {
        _1464 = seg.p2.y;
    }
    else
    {
        _1464 = seg.p2.x;
    }
    return rootHullCanCross3(_1462, _1463, _1464, sampleRoot);
}

float distToUnitInterval(float t)
{
    return max(max(0.0, -t), t - 1.0);
}

// Composed-catalog solver text, injected by build/glsl_patch_cubic_solver.zig
// (see that file for why the naga emission cannot be used verbatim).
bool snailSpecSolveMonotonicCubicRoot(float a, float b, float cVal, float d, float endDelta, out float tOut) {
    // Path preparation splits cubics at x/y extrema, so each uploaded cubic is
    // monotonic along both sampling axes and can contribute at most one root.
    float f0 = d;
    // Use the uploaded p3 directly. Reconstructing f(1) through a+b+c+d
    // loses enough precision near shallow extrema to corrupt the bracket.
    float f1 = endDelta;
    if ((f0 < -(1.0 / 65536.0) && f1 < -(1.0 / 65536.0)) || (f0 > (1.0 / 65536.0) && f1 > (1.0 / 65536.0))) return false;

    float lo = 0.0;
    float hi = 1.0;
    float t = 0.5;
    bool increasing = f1 >= f0;
    for (int i = 0; i < 16; i++) {
        float f = ((a * t + b) * t + cVal) * t + d;
        if ((increasing && f < 0.0) || (!increasing && f > 0.0)) {
            lo = t;
        } else {
            hi = t;
        }
        float deriv = (3.0 * a * t + 2.0 * b) * t + cVal;
        float next = (lo + hi) * 0.5;
        if (abs(deriv) >= 1e-6) {
            float newton = t - f / deriv;
            if (newton > lo && newton < hi) next = newton;
        }
        t = next;
    }
    tOut = t;
    return true;
}

bool solveMonotonicCubicRoot(float a, float b, float cVal, float d, float endDelta, out float tOut)
{
    return snailSpecSolveMonotonicCubicRoot(a, b, cVal, d, endDelta, tOut);
}

bool accumulateAxisCoverageSegment(inout float cov, inout float wgt, vec2 sampleRc, float ppe, SegmentData seg, bool horizontal)
{
    float maxCoord;
    if (horizontal)
    {
        maxCoord = segmentMaxX(seg) - sampleRc.x;
    }
    else
    {
        maxCoord = segmentMaxY(seg) - sampleRc.y;
    }
    if ((maxCoord * ppe) < (-0.5))
    {
        return false;
    }
    if (seg.kind == 0)
    {
        float p0x = seg.p0.x - sampleRc.x;
        float p0y = seg.p0.y - sampleRc.y;
        float p1x = seg.p1.x - sampleRc.x;
        float p1y = seg.p1.y - sampleRc.y;
        float p2x = seg.p2.x - sampleRc.x;
        float p2y = seg.p2.y - sampleRc.y;
        uint code;
        if (horizontal)
        {
            code = calcRootCode(p0y, p1y, p2y);
        }
        else
        {
            code = calcRootCode(p0x, p1x, p2x);
        }
        if (code == 0u)
        {
            return true;
        }
        vec2 roots;
        if (horizontal)
        {
            roots = solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);
        }
        else
        {
            roots = solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);
        }
        if ((code & 1u) != 0u)
        {
            if (horizontal)
            {
                maxCoord = 1.0;
            }
            else
            {
                maxCoord = -1.0;
            }
            cov += (maxCoord * clamp(roots.x + 0.5, 0.0, 1.0));
            wgt = max(wgt, clamp(1.0 - (abs(roots.x) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            if (horizontal)
            {
                maxCoord = -1.0;
            }
            else
            {
                maxCoord = 1.0;
            }
            cov += (maxCoord * clamp(roots.y + 0.5, 0.0, 1.0));
            wgt = max(wgt, clamp(1.0 - (abs(roots.y) * 2.0), 0.0, 1.0));
        }
        return true;
    }
    float sampleRoot;
    float sampleAlong;
    float p0Root;
    if (seg.kind == 3)
    {
        float _1363 = seg.p0.x - sampleRc.x;
        float _1366 = seg.p0.y - sampleRc.y;
        float _1370 = seg.p2.x - sampleRc.x;
        float _1372 = seg.p2.y - sampleRc.y;
        do
        {
            if (horizontal)
            {
                sampleRoot = _1366;
            }
            else
            {
                sampleRoot = _1363;
            }
            if (horizontal)
            {
                sampleAlong = _1372;
            }
            else
            {
                sampleAlong = _1370;
            }
            if ((rootCodeCoord(sampleRoot) < 0.0) == (rootCodeCoord(sampleAlong) < 0.0))
            {
                break;
            }
            float denom = sampleAlong - sampleRoot;
            if (abs(denom) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _1403 = clamp((-sampleRoot) / denom, 0.0, 1.0);
            if (horizontal)
            {
                p0Root = _1372 - _1366;
            }
            else
            {
                p0Root = _1363 - _1370;
            }
            if (abs(p0Root) <= 9.9999997473787516355514526367188e-06)
            {
                break;
            }
            if (horizontal)
            {
                maxCoord = _1363 + ((_1370 - _1363) * _1403);
            }
            else
            {
                maxCoord = _1366 + ((_1372 - _1366) * _1403);
            }
            float _1427 = maxCoord;
            float distance = _1427 * ppe;
            if (p0Root > 0.0)
            {
                maxCoord = 1.0;
            }
            else
            {
                maxCoord = -1.0;
            }
            cov += (maxCoord * clamp(distance + 0.5, 0.0, 1.0));
            wgt = max(wgt, clamp(1.0 - (abs(distance) * 2.0), 0.0, 1.0));
            break;
        } while(false);
        return true;
    }
    float p1Root;
    float p2Root;
    float p3Root;
    float p0Along;
    float p1Along;
    float p2Along;
    float p3Along;
    float along;
    float derivAxis;
    if (seg.kind == 1)
    {
        do
        {
            if (!segmentRootHullCanCross(seg, sampleRc, horizontal))
            {
                break;
            }
            if (horizontal)
            {
                sampleRoot = sampleRc.y;
            }
            else
            {
                sampleRoot = sampleRc.x;
            }
            if (horizontal)
            {
                sampleAlong = sampleRc.x;
            }
            else
            {
                sampleAlong = sampleRc.y;
            }
            if (horizontal)
            {
                p0Root = seg.p0.y;
            }
            else
            {
                p0Root = seg.p0.x;
            }
            if (horizontal)
            {
                p1Root = seg.p1.y;
            }
            else
            {
                p1Root = seg.p1.x;
            }
            if (horizontal)
            {
                p2Root = seg.p2.y;
            }
            else
            {
                p2Root = seg.p2.x;
            }
            if (horizontal)
            {
                p0Along = seg.p0.x;
            }
            else
            {
                p0Along = seg.p0.y;
            }
            if (horizontal)
            {
                p1Along = seg.p1.x;
            }
            else
            {
                p1Along = seg.p1.y;
            }
            if (horizontal)
            {
                p2Along = seg.p2.x;
            }
            else
            {
                p2Along = seg.p2.y;
            }
            float c0 = seg.weights.x * (p0Root - sampleRoot);
            float c1 = seg.weights.y * (p1Root - sampleRoot);
            float c2 = seg.weights.z * (p2Root - sampleRoot);
            uint code_1 = calcRootCode(c0, c1, c2);
            if (code_1 == 0u)
            {
                break;
            }
            int want;
            if (code_1 == 257u)
            {
                want = 2;
            }
            else
            {
                want = 1;
            }
            float quadA = (c0 - (2.0 * c1)) + c2;
            float quadB = 2.0 * (c1 - c0);
            int ncand;
            if (abs(quadA) < 1.52587890625e-05)
            {
                if (abs(quadB) >= 1.52587890625e-05)
                {
                    ncand = 1;
                    p3Root = (-c0) / quadB;
                }
                else
                {
                    ncand = 0;
                    p3Root = 0.0;
                }
                float _1778 = p3Root;
                p3Root = 0.0;
                p3Along = _1778;
            }
            else
            {
                float _1788 = sqrt(max((quadB * quadB) - ((4.0 * quadA) * c0), 0.0));
                float inv2a = 0.5 / quadA;
                float _1790 = -quadB;
                ncand = 2;
                p3Root = (_1790 + _1788) * inv2a;
                p3Along = (_1790 - _1788) * inv2a;
            }
            if (ncand == 0)
            {
                break;
            }
            int rootCount;
            if (want == 1)
            {
                bool _683;
                if (ncand == 2)
                {
                    _683 = distToUnitInterval(p3Root) < distToUnitInterval(p3Along);
                }
                else
                {
                    _683 = false;
                }
                if (_683)
                {
                    along = p3Root;
                }
                else
                {
                    along = p3Along;
                }
                along = clamp(along, 0.0, 1.0);
                rootCount = 1;
                derivAxis = 0.0;
            }
            else
            {
                along = clamp(p3Along, 0.0, 1.0);
                rootCount = 2;
                derivAxis = clamp(p3Root, 0.0, 1.0);
            }
            float _1849 = p0Root * seg.weights.x;
            float rootA = (_1849 - ((2.0 * p1Root) * seg.weights.y)) + (p2Root * seg.weights.z);
            float rootB = 2.0 * ((p1Root * seg.weights.y) - _1849);
            float _1862 = p0Along * seg.weights.x;
            float alongA = (_1862 - ((2.0 * p1Along) * seg.weights.y)) + (p2Along * seg.weights.z);
            float alongB = 2.0 * ((p1Along * seg.weights.y) - _1862);
            float denA = (seg.weights.x - (2.0 * seg.weights.y)) + seg.weights.z;
            float denB = 2.0 * (seg.weights.y - seg.weights.x);
            float _1899;
            float _1903;
            bool _1912;
            float derivAxis_1;
            do
            {
                float _1885 = max((((denA * along) + denB) * along) + seg.weights.x, 1.52587890625e-05);
                _1899 = 2.0 * rootA;
                _1903 = 2.0 * denA;
                float derivAxis_2 = ((((_1899 * along) + rootB) * _1885) - (((((rootA * along) + rootB) * along) + _1849) * ((_1903 * along) + denB))) / (_1885 * _1885);
                _1912 = !horizontal;
                if (_1912)
                {
                    derivAxis_1 = -derivAxis_2;
                }
                else
                {
                    derivAxis_1 = derivAxis_2;
                }
                if (abs(derivAxis_1) <= 9.9999997473787516355514526367188e-06)
                {
                    break;
                }
                float dist = ((((((alongA * along) + alongB) * along) + _1862) / _1885) - sampleAlong) * ppe;
                if (derivAxis_1 > 0.0)
                {
                    maxCoord = 1.0;
                }
                else
                {
                    maxCoord = -1.0;
                }
                cov += (maxCoord * clamp(dist + 0.5, 0.0, 1.0));
                wgt = max(wgt, clamp(1.0 - (abs(dist) * 2.0), 0.0, 1.0));
                break;
            } while(false);
            if (rootCount == 2)
            {
                do
                {
                    float _1958 = max((((denA * derivAxis) + denB) * derivAxis) + seg.weights.x, 1.52587890625e-05);
                    float derivAxis_3 = ((((_1899 * derivAxis) + rootB) * _1958) - (((((rootA * derivAxis) + rootB) * derivAxis) + _1849) * ((_1903 * derivAxis) + denB))) / (_1958 * _1958);
                    if (_1912)
                    {
                        derivAxis_1 = -derivAxis_3;
                    }
                    else
                    {
                        derivAxis_1 = derivAxis_3;
                    }
                    if (abs(derivAxis_1) <= 9.9999997473787516355514526367188e-06)
                    {
                        break;
                    }
                    float dist_1 = ((((((alongA * derivAxis) + alongB) * derivAxis) + _1862) / _1958) - sampleAlong) * ppe;
                    if (derivAxis_1 > 0.0)
                    {
                        maxCoord = 1.0;
                    }
                    else
                    {
                        maxCoord = -1.0;
                    }
                    cov += (maxCoord * clamp(dist_1 + 0.5, 0.0, 1.0));
                    wgt = max(wgt, clamp(1.0 - (abs(dist_1) * 2.0), 0.0, 1.0));
                    break;
                } while(false);
            }
            break;
        } while(false);
        return true;
    }
    do
    {
        if (!segmentRootHullCanCross(seg, sampleRc, horizontal))
        {
            break;
        }
        if (horizontal)
        {
            sampleRoot = sampleRc.y;
        }
        else
        {
            sampleRoot = sampleRc.x;
        }
        if (horizontal)
        {
            sampleAlong = sampleRc.x;
        }
        else
        {
            sampleAlong = sampleRc.y;
        }
        if (horizontal)
        {
            p0Root = seg.p0.y;
        }
        else
        {
            p0Root = seg.p0.x;
        }
        if (horizontal)
        {
            p1Root = seg.p1.y;
        }
        else
        {
            p1Root = seg.p1.x;
        }
        if (horizontal)
        {
            p2Root = seg.p2.y;
        }
        else
        {
            p2Root = seg.p2.x;
        }
        if (horizontal)
        {
            p3Root = seg.p3.y;
        }
        else
        {
            p3Root = seg.p3.x;
        }
        if (horizontal)
        {
            p0Along = seg.p0.x;
        }
        else
        {
            p0Along = seg.p0.y;
        }
        if (horizontal)
        {
            p1Along = seg.p1.x;
        }
        else
        {
            p1Along = seg.p1.y;
        }
        if (horizontal)
        {
            p2Along = seg.p2.x;
        }
        else
        {
            p2Along = seg.p2.y;
        }
        if (horizontal)
        {
            p3Along = seg.p3.x;
        }
        else
        {
            p3Along = seg.p3.y;
        }
        float _2131 = 3.0 * p1Root;
        float _2135 = 3.0 * p2Root;
        float startDelta = p0Root - sampleRoot;
        float endDelta = p3Root - sampleRoot;
        if ((rootCodeCoord(startDelta) < 0.0) == (rootCodeCoord(endDelta) < 0.0))
        {
            break;
        }
        float t = 0.0;
        if (abs(startDelta) <= 1.52587890625e-05)
        {
            t = 0.0;
        }
        else
        {
            if (abs(endDelta) <= 1.52587890625e-05)
            {
                t = 1.0;
            }
            else
            {
                bool _2174 = solveMonotonicCubicRoot((((-p0Root) + _2131) - _2135) + p3Root, ((3.0 * p0Root) - (6.0 * p1Root)) + _2135, ((-3.0) * p0Root) + _2131, startDelta, endDelta, t);
                if (!_2174)
                {
                    break;
                }
            }
        }
        float _2357 = 3.0 * p1Along;
        float _2360 = 3.0 * p2Along;
        if (t == 1.0)
        {
            along = p3Along;
        }
        else
        {
            along = (((((((((-p0Along) + _2357) - _2360) + p3Along) * t) + (((3.0 * p0Along) - (6.0 * p1Along)) + _2360)) * t) + (((-3.0) * p0Along) + _2357)) * t) + p0Along;
        }
        if (horizontal)
        {
            derivAxis = p3Root - p0Root;
        }
        else
        {
            derivAxis = p0Root - p3Root;
        }
        float dist_2 = (along - sampleAlong) * ppe;
        if (derivAxis > 0.0)
        {
            maxCoord = 1.0;
        }
        else
        {
            maxCoord = -1.0;
        }
        cov += (maxCoord * clamp(dist_2 + 0.5, 0.0, 1.0));
        wgt = max(wgt, clamp(1.0 - (abs(dist_2) * 2.0), 0.0, 1.0));
        break;
    } while(false);
    return true;
}

vec2 evalAxisCoverageBands(vec2 _422, float _423, ivec2 _424, int _425, int _426, int _427, int _428, bool _429)
{
    float cov = 0.0;
    float wgt = 0.0;
    bool _467 = _426 != _427;
    int band = _426;
    for (;;)
    {
        bool _441_ladder_break = false;
        do
        {
            if (!(band <= _427))
            {
                _441_ladder_break = true;
                break;
            }
            uvec2 bd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_424, uint(_425 + band)), _428, 0).xyz, 0).xy.xy;
            ivec2 _514 = calcBandLoc(_424, bd.y);
            int _516 = int(bd.x);
            int i = 0;
            for (;;)
            {
                bool _446_ladder_break = false;
                do
                {
                    if (!(i < _516))
                    {
                        _446_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_514, uint(i)), _428, 0).xyz, 0).xy.xy;
                    if (_467)
                    {
                        if (band != max(decodeBandCurveFirstMemberCommon(ref), _426))
                        {
                            break;
                        }
                    }
                    SegmentData _438 = fetchSegment(decodeBandCurveLocCommon(ref), _428, decodeBandCurveKindCommon(ref));
                    bool _655 = accumulateAxisCoverageSegment(cov, wgt, _422, _423, _438, _429);
                    if (!_655)
                    {
                        _446_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_446_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_441_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return vec2(cov, wgt);
}

float applyFillRule(float winding, int fill_rule_mode)
{
    if (fill_rule_mode == 1)
    {
        return 1.0 - abs((fract(winding * 0.5) * 2.0) - 1.0);
    }
    return abs(winding);
}

float applyCoverageTransfer(float cov, float coverage_exponent)
{
    float _2498 = clamp(cov, 0.0, 1.0);
    float _2499 = max(coverage_exponent, 1.52587890625e-05);
    float _2494;
    if (abs(_2499 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _2494 = _2498;
    }
    else
    {
        _2494 = pow(_2498, _2499);
    }
    return _2494;
}

float evalPathGlyphCoverage(vec2 _356, vec2 _357, vec2 _358, ivec2 _359, ivec2 _360, vec4 _361, int _362, int _363, float _364)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_356.y, _357.y, _361.y, _361.w, _360.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_356.x, _357.x, _361.x, _361.z, _360.x);
    vec2 _419 = evalAxisCoverageBands(_356, _358.x, _359, 0, hSpan.first, hSpan.last, _362, true);
    vec2 _2454 = evalAxisCoverageBands(_356, _358.y, _359, _360.y + 1, vSpan.first, vSpan.last, _362, false);
    float _2455 = _419.y;
    float _2456 = _2454.y;
    float _2458 = _419.x;
    float _2460 = _2454.x;
    return applyCoverageTransfer(max(applyFillRule(((_2458 * _2455) + (_2460 * _2456)) / max(_2455 + _2456, 1.52587890625e-05), _363), min(applyFillRule(_2458, _363), applyFillRule(_2460, _363))), _364);
}

float wrapPaintT(float t, float extendMode)
{
    int mode = int(extendMode + 0.5);
    if (mode == 1)
    {
        return fract(t);
    }
    if (mode == 2)
    {
        float reflected_1 = t - (2.0 * floor(t / 2.0));
        float reflected;
        if (reflected_1 < 0.0)
        {
            reflected = reflected_1 + 2.0;
        }
        else
        {
            reflected = reflected_1;
        }
        return 1.0 - abs(reflected - 1.0);
    }
    return clamp(t, 0.0, 1.0);
}

vec4 mixGradient(vec4 c0, vec4 c1, float t)
{
    return mix(c0, c1, vec4(t));
}

vec4 sampleImagePaintTex(vec2 _2708, int _2709, int _2710, sampler2DArray SPIRV_Cross_Combinedu_image_tex_2707)
{
    if (_2710 == 1)
    {
        uvec3 vecSize = uvec3(textureSize(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, 0));
        uint uw = vecSize.x;
        uint uh = vecSize.y;
        uint ue = vecSize.z;
        ivec2 size = ivec2(int(uw), int(uh));
        vec4 _2743 = texelFetch(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, ivec4(clamp(ivec2(_2708 * vec2(size)), ivec2(0), size - ivec2(1)), _2709, 0).xyz, 0);
        return _2743;
    }
    vec4 _2752 = texture(SPIRV_Cross_Combinedu_image_tex_2707, vec3(_2708, float(_2709)));
    return _2752;
}

PathPaintSample samplePathPaint(vec2 _2516, ivec2 _2517, vec4 _2518, sampler2DArray SPIRV_Cross_Combinedu_image_tex_2515)
{
    int paintKind = int((-_2518.w) + 0.5);
    vec4 _2543 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 2), 0).xy, 0);
    if (paintKind == 1)
    {
        return PathPaintSample_init(_2543, 0.0);
    }
    vec4 _2553 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 3), 0).xy, 0);
    vec4 _2559 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 4), 0).xy, 0);
    if (paintKind == 2)
    {
        vec2 delta = _2543.zw - _2543.xy;
        float _2565 = dot(delta, delta);
        float t;
        if (_2565 > 1.0000000133514319600180897396058e-10)
        {
            t = dot(_2516 - _2543.xy, delta) / _2565;
        }
        else
        {
            t = 0.0;
        }
        vec4 _2580 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 5), 0).xy, 0);
        return PathPaintSample_init(mixGradient(_2553, _2559, wrapPaintT(t, _2580.x)), 1.0);
    }
    if (paintKind == 3)
    {
        return PathPaintSample_init(mixGradient(_2553, _2559, wrapPaintT(length(_2516 - _2543.xy) / max(abs(_2543.z), 1.52587890625e-05), _2543.w)), 1.0);
    }
    if (paintKind == 6)
    {
        vec2 d = _2516 - _2543.xy;
        return PathPaintSample_init(mixGradient(_2553, _2559, wrapPaintT((atan(d.y, d.x) - _2543.z) * 0.15915493667125701904296875, _2543.w)), 1.0);
    }
    if (paintKind == 4)
    {
        vec4 _2671 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 3), 0).xy, 0);
        vec4 _2677 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_2517, 5), 0).xy, 0);
        vec3 _2678 = vec3(_2516, 1.0);
        return PathPaintSample_init(sampleImagePaintTex(vec2(wrapPaintT(dot(_2678, vec3(_2543.xyz)), _2677.z) * _2677.x, wrapPaintT(dot(_2678, vec3(_2671.xyz)), _2677.w) * _2677.y), int(_2543.w + 0.5), int(_2671.w + 0.5), SPIRV_Cross_Combinedu_image_tex_2515), 0.0);
    }
    return PathPaintSample_init(vec4(1.0, 0.0, 1.0, 1.0), 0.0);
}

vec4 premultiplyColor(vec4 color, float cov)
{
    float alpha = color.w * cov;
    return vec4(color.xyz * alpha, alpha);
}

PathCompositeSample PathCompositeSample_init(vec4 color, float gradient)
{
    PathCompositeSample _2922;
    _2922.color = color;
    _2922.gradient = gradient;
    return _2922;
}

PathCompositeSample compositePathGroup(vec2 _197, vec2 _198, vec2 _199, ivec2 _200, vec4 _201, int _202, vec4 _203, float _204, sampler2DArray SPIRV_Cross_Combinedu_image_tex_196)
{
    int layer_count = int(_201.x + 0.5);
    int composite_mode = int(_201.y + 0.5);
    PathPaintSample _270 = PathPaintSample_init(vec4(0.0), 0.0);
    vec4 result = vec4(0.0);
    float fill_cov = 0.0;
    float stroke_cov = 0.0;
    PathPaintSample fill_paint = _270;
    PathPaintSample stroke_paint = _270;
    float has_gradient = 0.0;
    int l = 0;
    bool _214;
    bool _216;
    float has_gradient_1;
    float stroke_cov_1;
    PathPaintSample fill_paint_1;
    PathPaintSample stroke_paint_1;
    bool _221;
    for (;;)
    {
        bool _224_ladder_break = false;
        do
        {
            if (!(l < layer_count))
            {
                _224_ladder_break = true;
                break;
            }
            ivec2 _297 = offsetLayerLoc(_200, 1 + (l * 6));
            vec4 _328 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_297, 0).xy, 0);
            vec4 _334 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_297, 1), 0).xy, 0);
            int packed_gx = int(_328.x);
            int _346 = floatBitsToInt(_328.z);
            float _353 = evalPathGlyphCoverage(_197, _198, _199, ivec2(packed_gx & 32767, int(_328.y)), ivec2((_346 >> 16) & 65535, _346 & 65535), _334, _202, (packed_gx >> 15) & 1, _204);
            PathPaintSample paint = samplePathPaint(_197, _297, _328, SPIRV_Cross_Combinedu_image_tex_196);
            paint.color *= _203;
            if (composite_mode == 1)
            {
                _214 = layer_count >= 2;
            }
            else
            {
                _214 = false;
            }
            if (_214)
            {
                _216 = l < 2;
            }
            else
            {
                _216 = false;
            }
            if (_216)
            {
                if (l == 0)
                {
                    has_gradient_1 = _353;
                    stroke_cov_1 = stroke_cov;
                    fill_paint_1 = paint;
                    stroke_paint_1 = stroke_paint;
                }
                else
                {
                    has_gradient_1 = fill_cov;
                    stroke_cov_1 = _353;
                    fill_paint_1 = fill_paint;
                    stroke_paint_1 = paint;
                }
                fill_paint = fill_paint_1;
                stroke_paint = stroke_paint_1;
                break;
            }
            if (paint.gradient > 0.5)
            {
                _221 = _353 > 9.9999999747524270787835121154785e-07;
            }
            else
            {
                _221 = false;
            }
            if (_221)
            {
                has_gradient_1 = 1.0;
            }
            else
            {
                has_gradient_1 = has_gradient;
            }
            vec4 premul = premultiplyColor(paint.color, _353);
            float _2841 = has_gradient_1;
            result = premul + (result * (1.0 - premul.w));
            has_gradient_1 = fill_cov;
            stroke_cov_1 = stroke_cov;
            has_gradient = _2841;
            break;
        } while(false);
        if (_224_ladder_break)
        {
            break;
        }
        fill_cov = has_gradient_1;
        stroke_cov = stroke_cov_1;
        l++;
        continue;
    }
    if (composite_mode == 1)
    {
        _214 = layer_count >= 2;
    }
    else
    {
        _214 = false;
    }
    if (_214)
    {
        float _2868 = min(fill_cov, stroke_cov);
        float _2871 = max(fill_cov - _2868, 0.0);
        if (fill_paint.gradient > 0.5)
        {
            _214 = _2871 > 9.9999999747524270787835121154785e-07;
        }
        else
        {
            _214 = false;
        }
        if (_214)
        {
            has_gradient = 1.0;
        }
        if (stroke_paint.gradient > 0.5)
        {
            _214 = _2868 > 9.9999999747524270787835121154785e-07;
        }
        else
        {
            _214 = false;
        }
        if (_214)
        {
            has_gradient = 1.0;
        }
        result += ((premultiplyColor(fill_paint.color, _2871) + premultiplyColor(stroke_paint.color, _2868)) * (1.0 - result.w));
    }
    return PathCompositeSample_init(result, has_gradient);
}

float interleavedGradientNoise(vec2 pixel)
{
    return fract(52.98291778564453125 * fract(dot(pixel, vec2(0.067110560834407806396484375, 0.005837149918079376220703125))));
}

float srgbEncode(float c)
{
    float _2995;
    if (c <= 0.003130800090730190277099609375)
    {
        _2995 = c * 12.9200000762939453125;
    }
    else
    {
        _2995 = (1.05499994754791259765625 * pow(c, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    return _2995;
}

vec3 linearToSrgb(vec3 color)
{
    return vec3(srgbEncode(max(color.x, 0.0)), srgbEncode(max(color.y, 0.0)), srgbEncode(max(color.z, 0.0)));
}

float srgbDecode(float c)
{
    float _3038;
    if (c <= 0.040449999272823333740234375)
    {
        _3038 = c / 12.9200000762939453125;
    }
    else
    {
        _3038 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _3038;
}

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

vec4 ditherPremultipliedColor(vec4 color, vec2 frag_coord, float dither_scale)
{
    bool _2948;
    if (color.w <= 0.0)
    {
        _2948 = true;
    }
    else
    {
        _2948 = dither_scale <= 0.0;
    }
    if (_2948)
    {
        return color;
    }
    return vec4(srgbToLinear(clamp(linearToSrgb(color.xyz) + vec3((interleavedGradientNoise(frag_coord) - 0.5) * (clamp(color.w, 0.0, 1.0) * dither_scale)), vec3(0.0), vec3(1.0))), color.w);
}

vec4 srgbEncodePremultiplied(vec4 premul)
{
    if (premul.w <= 0.0)
    {
        return vec4(0.0);
    }
    return vec4(linearToSrgb(premul.xyz * (1.0 / premul.w)) * premul.w, premul.w);
}

vec4 snailPaintedFragment(int _90, PaintedVaryings _91, vec2 _92, PaintedParams _94, sampler2DArray SPIRV_Cross_Combinedu_image_tex_93)
{
    vec2 epp = _fwidth(_91.texcoord);
    vec2 ppe = vec2(1.0) / max(epp, vec2(1.52587890625e-05));
    if (((_91.glyph.w >> 8) & 255) != 255)
    {
        discard;
    }
    if ((_91.glyph.w & 255) != _90)
    {
        discard;
    }
    vec4 _169 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_91.glyph.xy, 0).xy, 0);
    if (_169.w >= 0.0)
    {
        discard;
    }
    int texLayer = _94.layer_base + int(_91.banding.w);
    vec4 emit;
    if (int((-_169.w) + 0.5) == 5)
    {
        PathCompositeSample _193 = compositePathGroup(_91.texcoord, epp, ppe, _91.glyph.xy, _169, texLayer, _91.tint, _94.coverage_exponent, SPIRV_Cross_Combinedu_image_tex_93);
        vec4 _2930 = _193.color;
        if (_2930.w < 0.0039215688593685626983642578125)
        {
            discard;
        }
        if (_193.gradient > 0.5)
        {
            emit = ditherPremultipliedColor(_2930, _92, _94.dither_scale);
        }
        else
        {
            emit = _2930;
        }
        if (_94.mask_output != 0)
        {
            emit = vec4(emit.w);
        }
        else
        {
            if (_94.output_srgb != 0)
            {
                emit = srgbEncodePremultiplied(emit);
            }
        }
        return emit;
    }
    vec4 _3111 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetLayerLoc(_91.glyph.xy, 1), 0).xy, 0);
    int packed_gx = int(_169.x);
    int _3121 = floatBitsToInt(_169.z);
    float _3128 = evalPathGlyphCoverage(_91.texcoord, epp, ppe, ivec2(packed_gx & 32767, int(_169.y)), ivec2((_3121 >> 16) & 65535, _3121 & 65535), _3111, texLayer, (packed_gx >> 15) & 1, _94.coverage_exponent);
    if (_3128 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    PathPaintSample paint = samplePathPaint(_91.texcoord, _91.glyph.xy, _169, SPIRV_Cross_Combinedu_image_tex_93);
    vec4 _3137 = paint.color;
    vec4 _3138 = _3137 * _91.tint;
    paint.color = _3138;
    vec4 result = premultiplyColor(_3138, _3128);
    if (paint.gradient > 0.5)
    {
        emit = ditherPremultipliedColor(result, _92, _94.dither_scale);
    }
    else
    {
        emit = result;
    }
    if (_94.mask_output != 0)
    {
        emit = vec4(emit.w);
    }
    else
    {
        if (_94.output_srgb != 0)
        {
            emit = srgbEncodePremultiplied(emit);
        }
    }
    return emit;
}

void main()
{
    PaintedVaryings v;
    v.tint = snail_io4;
    v.texcoord = snail_io1;
    v.banding = snail_io2;
    v.glyph = snail_io3;
    PaintedParams p;
    p.layer_base = pc.layer_base;
    p.output_srgb = pc.output_srgb;
    p.coverage_exponent = pc.coverage_exponent;
    p.dither_scale = pc.dither_scale;
    p.mask_output = pc.mask_output;
    PaintedVaryings _16 = v;
    PaintedParams _17 = p;
    vec4 _87 = snailPaintedFragment(1, _16, gl_FragCoord.xy, _17, SPIRV_Cross_Combinedu_image_texu_image_sampler);
    entryPointParam_fragmentMain = _87;
}

