#version 330

struct SubpixelVaryings
{
    vec4 color;
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};

struct FsOutput
{
    vec4 color;
    vec4 blend;
};

struct SubpixelResult
{
    vec4 color;
    vec4 blend;
    bool discard_fragment;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

uvec4 _392;
uvec4 _410;
uvec4 _788;
uvec4 _806;

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

uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in vec4 snail_io0;
in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain_color;
layout(location = 0, index = 1) out vec4 entryPointParam_fragmentMain_blend;

vec2 ddx(vec2 p)
{
    return dFdx(p);
}

vec2 ddy(vec2 p)
{
    return dFdy(p);
}

vec2 subpixelCoverageEdgePixels(vec2 display_dx, vec2 display_dy, int subpixel_order)
{
    vec2 _173 = abs(display_dx);
    vec2 _175 = abs(display_dy);
    vec2 _169;
    if (subpixel_order <= 2)
    {
        _169 = (_173 * 0.3333333432674407958984375) + _175;
    }
    else
    {
        _169 = _173 + (_175 * 0.3333333432674407958984375);
    }
    return _169;
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _328;
    _328.first = first;
    _328.last = last;
    return _328;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _312 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _316 = clamp(int(center - _312), 0, bandMax);
    return CoverageBandSpan_init(_316, max(_316, clamp(int(center + _312), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _364 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_364, glyphLoc.y);
    loc.y += (_364 >> 12);
    loc.x &= 4095;
    return loc;
}

int decodeBandCurveFirstMemberCommon(uvec2 ref)
{
    return int(ref.x >> 12u);
}

bool isCoverageBandSpanOwner(uvec2 ref, int band, int spanFirst)
{
    return band == max(decodeBandCurveFirstMemberCommon(ref), spanFirst);
}

ivec2 decodeBandCurveLocCommon(uvec2 ref)
{
    return ivec2(int(ref.x & 4095u), int(ref.y & 16383u));
}

ivec2 decodeBandCurveLoc(uvec2 ref)
{
    return decodeBandCurveLocCommon(ref);
}

ivec2 offsetCurveLoc(ivec2 base, int offset)
{
    int _496 = base.x + offset;
    ivec2 loc = ivec2(_496, base.y);
    loc.y += (_496 >> 12);
    loc.x &= 4095;
    return loc;
}

float rootCodeCoord(float v)
{
    float _549;
    if (abs(v) <= 1.52587890625e-05)
    {
        _549 = 0.0;
    }
    else
    {
        _549 = v;
    }
    return _549;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _650;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _650 = 0.0;
    }
    else
    {
        _650 = sqrt(disc);
    }
    return _650;
}

vec2 solveHorizPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _620 = a.y;
    float t1;
    float t2;
    if (abs(_620) < 1.52587890625e-05)
    {
        float _624 = b.y;
        if (abs(_624) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _624;
        }
        t2 = t1;
    }
    else
    {
        float _638 = b.y;
        float _641 = _620 * p12.y;
        float sq = snapNearTangentSqrt((_638 * _638) - _641, _638, _641);
        if (_638 >= 0.0)
        {
            float q = _638 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _620;
        }
        else
        {
            float q_1 = _638 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            float _692 = t1;
            t1 = q_1 / _620;
            t2 = _692;
        }
    }
    float _697 = a.x;
    float _701 = b.x * 2.0;
    return vec2((((_697 * t1) - _701) * t1) + p12.x, (((_697 * t2) - _701) * t2) + p12.x);
}

bool accumulateHorizContribution(inout float _465, inout float _466, vec2 _467, vec2 _468, ivec2 _469, int _470)
{
    vec4 _487 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_469, _470, 0).xyz, 0);
    vec4 _515 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_469, 1), _470, 0).xyz, 0);
    vec4 p12 = vec4(_487.xy, _487.zw) - vec4(_467, _467);
    vec2 p3 = _515.xy - _467;
    if ((max(max(p12.x, p12.z), p3.x) * _468.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        vec2 r = solveHorizPoly(p12, p3) * _468.x;
        if ((code & 1u) != 0u)
        {
            float _720 = r.x;
            _465 += clamp(_720 + 0.5, 0.0, 1.0);
            _466 = max(_466, clamp(1.0 - (abs(_720) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _736 = r.y;
            _465 -= clamp(_736 + 0.5, 0.0, 1.0);
            _466 = max(_466, clamp(1.0 - (abs(_736) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveVertPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _899 = a.x;
    float t1;
    float t2;
    if (abs(_899) < 1.52587890625e-05)
    {
        float _903 = b.x;
        if (abs(_903) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _903;
        }
        t2 = t1;
    }
    else
    {
        float _917 = b.x;
        float _920 = _899 * p12.x;
        float sq = snapNearTangentSqrt((_917 * _917) - _920, _917, _920);
        if (_917 >= 0.0)
        {
            float q = _917 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _899;
        }
        else
        {
            float q_1 = _917 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            float _947 = t1;
            t1 = q_1 / _899;
            t2 = _947;
        }
    }
    float _952 = a.y;
    float _956 = b.y * 2.0;
    return vec2((((_952 * t1) - _956) * t1) + p12.y, (((_952 * t2) - _956) * t2) + p12.y);
}

bool accumulateVertContribution(inout float _822, inout float _823, vec2 _824, vec2 _825, ivec2 _826, int _827)
{
    vec4 _841 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_826, _827, 0).xyz, 0);
    vec4 _847 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_826, 1), _827, 0).xyz, 0);
    vec4 p12 = vec4(_841.xy, _841.zw) - vec4(_824, _824);
    vec2 p3 = _847.xy - _824;
    if ((max(max(p12.y, p12.w), p3.y) * _825.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        vec2 r = solveVertPoly(p12, p3) * _825.y;
        if ((code & 1u) != 0u)
        {
            float _974 = r.x;
            _822 -= clamp(_974 + 0.5, 0.0, 1.0);
            _823 = max(_823, clamp(1.0 - (abs(_974) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _990 = r.y;
            _822 += clamp(_990 + 0.5, 0.0, 1.0);
            _823 = max(_823, clamp(1.0 - (abs(_990) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

float applyFillRule(float winding, int fill_rule_mode)
{
    if (fill_rule_mode == 1)
    {
        return 1.0 - abs((fract(winding * 0.5) * 2.0) - 1.0);
    }
    return abs(winding);
}

float evalGlyphCoverageRaw(vec2 _220, vec2 _221, vec2 _222, ivec2 _223, ivec2 _224, vec4 _225, int _226)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_220.y, _221.y, _225.y, _225.w, _224.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_220.x, _221.x, _225.x, _225.z, _224.x);
    float xcov = 0.0;
    float xwgt = 0.0;
    int _344 = hSpan.first;
    int _345 = hSpan.last;
    bool _346 = _344 != _345;
    int band = _344;
    int i;
    bool _234;
    for (;;)
    {
        bool _239_ladder_break = false;
        do
        {
            if (!(band <= _345))
            {
                _239_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_223, uint(band)), _226, 0).xyz, 0).xy.xy;
            ivec2 _395 = calcBandLoc(_223, hbd.y);
            int _397 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _244_ladder_break = false;
                do
                {
                    if (!(i < _397))
                    {
                        _244_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_395, uint(i)), _226, 0).xyz, 0).xy.xy;
                    if (_346)
                    {
                        _234 = !isCoverageBandSpanOwner(ref, band, _344);
                    }
                    else
                    {
                        _234 = false;
                    }
                    if (_234)
                    {
                        break;
                    }
                    bool _462 = accumulateHorizContribution(xcov, xwgt, _220, _222, decodeBandCurveLoc(ref), _226);
                    if (!_462)
                    {
                        _244_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_244_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_239_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    float ycov = 0.0;
    float ywgt = 0.0;
    int _771 = vSpan.first;
    int _772 = vSpan.last;
    bool _773 = _771 != _772;
    band = _771;
    for (;;)
    {
        bool _266_ladder_break = false;
        do
        {
            if (!(band <= _772))
            {
                _266_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_223, uint((_224.y + 1) + band)), _226, 0).xyz, 0).xy.xy;
            ivec2 _791 = calcBandLoc(_223, vbd.y);
            int _793 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _271_ladder_break = false;
                do
                {
                    if (!(i < _793))
                    {
                        _271_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_791, uint(i)), _226, 0).xyz, 0).xy.xy;
                    if (_773)
                    {
                        _234 = !isCoverageBandSpanOwner(ref_1, band, _771);
                    }
                    else
                    {
                        _234 = false;
                    }
                    if (_234)
                    {
                        break;
                    }
                    bool _820 = accumulateVertContribution(ycov, ywgt, _220, _222, decodeBandCurveLoc(ref_1), _226);
                    if (!_820)
                    {
                        _271_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_271_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_266_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return clamp(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), 0.0, 1.0);
}

float evalGlyphSample(vec2 _201, vec2 _202, ivec2 _203, ivec2 _204, vec4 _205, int _206)
{
    return evalGlyphCoverageRaw(_201, _202, vec2(1.0 / max(_202.x, 1.52587890625e-05), 1.0 / max(_202.y, 1.52587890625e-05)), _203, _204, _205, _206);
}

vec4 filterSubpixelCoverage(float s_m3, float s_m2, float s_m1, float s_0, float s_p1, float s_p2, float s_p3, bool reverse_order)
{
    float _1103 = 0.30078125 * s_0;
    float left = ((((0.03125 * s_m3) + (0.30078125 * s_m2)) + (0.3359375 * s_m1)) + _1103) + (0.03125 * s_p1);
    float center = ((((0.03125 * s_m2) + (0.30078125 * s_m1)) + (0.3359375 * s_0)) + (0.30078125 * s_p1)) + (0.03125 * s_p2);
    float right = ((((0.03125 * s_m1) + _1103) + (0.3359375 * s_p1)) + (0.30078125 * s_p2)) + (0.03125 * s_p3);
    vec3 cov;
    if (reverse_order)
    {
        cov = vec3(right, center, left);
    }
    else
    {
        cov = vec3(left, center, right);
    }
    vec3 _1132 = clamp(cov, vec3(0.0), vec3(1.0));
    return vec4(_1132, clamp(((_1132.x + _1132.y) + _1132.z) * 0.3333333432674407958984375, 0.0, 1.0));
}

float applyCoverageTransfer(float cov, float coverage_exponent)
{
    float _1162 = clamp(cov, 0.0, 1.0);
    float _1163 = max(coverage_exponent, 1.52587890625e-05);
    float _1158;
    if (abs(_1163 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1158 = _1162;
    }
    else
    {
        _1158 = pow(_1162, _1163);
    }
    return _1158;
}

vec3 applyCoverageTransfer3(vec3 cov, float coverage_exponent)
{
    return vec3(applyCoverageTransfer(cov.x, coverage_exponent), applyCoverageTransfer(cov.y, coverage_exponent), applyCoverageTransfer(cov.z, coverage_exponent));
}

vec4 evalGlyphCoverageSubpixel(vec2 _124, ivec2 _125, ivec2 _126, vec4 _127, int _128, int _129, float _130)
{
    vec2 display_dx = ddx(_124);
    vec2 display_dy = ddy(_124);
    vec2 _132;
    if (_129 <= 2)
    {
        _132 = display_dx;
    }
    else
    {
        _132 = display_dy;
    }
    vec2 sample_step = _132 * 0.3333333432674407958984375;
    vec2 display_epp = subpixelCoverageEdgePixels(display_dx, display_dy, _129);
    vec2 _188 = sample_step * 3.0;
    vec2 _191 = sample_step * 2.0;
    bool _133;
    if (_129 == 2)
    {
        _133 = true;
    }
    else
    {
        _133 = _129 == 4;
    }
    vec4 coverage = filterSubpixelCoverage(evalGlyphSample(_124 - _188, display_epp, _125, _126, _127, _128), evalGlyphSample(_124 - _191, display_epp, _125, _126, _127, _128), evalGlyphSample(_124 - sample_step, display_epp, _125, _126, _127, _128), evalGlyphSample(_124, display_epp, _125, _126, _127, _128), evalGlyphSample(_124 + sample_step, display_epp, _125, _126, _127, _128), evalGlyphSample(_124 + _191, display_epp, _125, _126, _127, _128), evalGlyphSample(_124 + _188, display_epp, _125, _126, _127, _128), _133);
    return vec4(applyCoverageTransfer3(coverage.xyz, _130), applyCoverageTransfer(coverage.w, _130));
}

float srgbEncode(float c)
{
    float _1211;
    if (c <= 0.003130800090730190277099609375)
    {
        _1211 = c * 12.9200000762939453125;
    }
    else
    {
        _1211 = (1.05499994754791259765625 * pow(c, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    return _1211;
}

vec4 premultiplyColorSubpixel(vec4 color, vec3 cov, float alpha_cov)
{
    return vec4(color.xyz * (vec3(color.w) * cov), color.w * alpha_cov);
}

SubpixelResult snailSubpixelFragment(SubpixelVaryings _72, int _73, int _74, int _75, float _76)
{
    SubpixelResult r;
    r.color = vec4(0.0);
    r.blend = vec4(0.0);
    r.discard_fragment = false;
    int layer_byte = (_72.glyph.w >> 8) & 255;
    if (layer_byte == 255)
    {
        r.discard_fragment = true;
        return r;
    }
    vec4 _121 = evalGlyphCoverageSubpixel(_72.texcoord, _72.glyph.xy, ivec2(_72.glyph.w & 255, _72.glyph.z), _72.banding, _73 + layer_byte, _74, _76);
    vec3 cov = _121.xyz;
    if (max(max(cov.x, cov.y), cov.z) < 0.0039215688593685626983642578125)
    {
        r.discard_fragment = true;
        return r;
    }
    vec4 color = _72.color * _72.tint;
    vec4 effective;
    if (_75 != 0)
    {
        effective = vec4(srgbEncode(max(color.x, 0.0)), srgbEncode(max(color.y, 0.0)), srgbEncode(max(color.z, 0.0)), color.w);
    }
    else
    {
        effective = color;
    }
    r.color = premultiplyColorSubpixel(effective, cov, _121.w);
    r.blend = vec4(vec3(color.w) * cov, 0.0);
    return r;
}

void main()
{
    SubpixelVaryings v;
    v.color = snail_io0;
    v.tint = snail_io4;
    v.texcoord = snail_io1;
    v.banding = snail_io2;
    v.glyph = snail_io3;
    SubpixelVaryings _13 = v;
    SubpixelResult _69 = snailSubpixelFragment(_13, pc.layer_base, pc.subpixel_order, pc.output_srgb, pc.coverage_exponent);
    if (_69.discard_fragment)
    {
        discard;
    }
    FsOutput o;
    o.color = _69.color;
    o.blend = _69.blend;
    entryPointParam_fragmentMain_color = o.color;
    entryPointParam_fragmentMain_blend = o.blend;
}

