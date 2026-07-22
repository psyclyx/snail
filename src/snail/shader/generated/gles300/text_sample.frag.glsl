#version 300 es
precision highp float;
precision highp int;

struct SnailTextSampleRecord
{
    highp vec4 rect;
    highp vec4 xform;
    highp vec2 origin;
    uvec2 glyph;
    highp vec4 banding;
    highp vec4 color;
    highp vec4 tint;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

uvec4 _636;
uvec4 _654;
uvec4 _1031;
uvec4 _1049;

layout(std140) uniform SnailTextSampleParams_std140
{
    int glyph_count;
    int words_per_glyph;
    int layer_base;
    highp float coverage_exponent;
} pc;

uniform highp usampler2D SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler;
uniform highp usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform highp sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in highp vec2 snail_io0;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

highp vec2 ddx(highp vec2 p)
{
    return dFdx(p);
}

highp vec2 ddy(highp vec2 p)
{
    return dFdy(p);
}

uint Records_word(int linear_index)
{
    return texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(linear_index - 1024 * (linear_index / 1024), linear_index / 1024), 0).x;
}

uint snailTextSampleWord(int words_per_glyph, int glyph_index, int word_offset)
{
    return Records_word((glyph_index * words_per_glyph) + word_offset);
}

highp float snailDecodeFloat16(uint bits)
{
    uint exponent = (bits >> 10u) & 31u;
    uint fraction = bits & 1023u;
    highp float _sign;
    if ((bits >> 15u) == 0u)
    {
        _sign = 1.0;
    }
    else
    {
        _sign = -1.0;
    }
    if (exponent == 0u)
    {
        if (fraction == 0u)
        {
            return _sign * 0.0;
        }
        highp float _200 = exp2(-14.0);
        return (_sign * _200) * (float(fraction) / 1024.0);
    }
    if (exponent == 31u)
    {
        return _sign * 65504.0;
    }
    return (_sign * exp2(float(exponent) - 15.0)) * (1.0 + (float(fraction) / 1024.0));
}

highp vec2 snailUnpackHalf2(uint word)
{
    return vec2(snailDecodeFloat16(word & 65535u), snailDecodeFloat16(word >> 16u));
}

highp vec4 snailUnpackHalf4(uint lo, uint hi)
{
    return vec4(snailUnpackHalf2(lo), snailUnpackHalf2(hi));
}

highp vec4 snailUnpackUnorm4x8(uint word)
{
    return vec4(float(word & 255u), float((word >> 8u) & 255u), float((word >> 16u) & 255u), float((word >> 24u) & 255u)) / vec4(255.0);
}

SnailTextSampleRecord snailTextSampleRecord(int words_per_glyph, int glyph_index)
{
    SnailTextSampleRecord record;
    record.rect = snailUnpackHalf4(snailTextSampleWord(words_per_glyph, glyph_index, 0), snailTextSampleWord(words_per_glyph, glyph_index, 1));
    record.xform = vec4(uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 2)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 3)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 4)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 5)));
    record.origin = vec2(uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 6)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 7)));
    record.glyph = uvec2(snailTextSampleWord(words_per_glyph, glyph_index, 8), snailTextSampleWord(words_per_glyph, glyph_index, 9));
    record.banding = vec4(uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 10)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 11)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 12)), uintBitsToFloat(snailTextSampleWord(words_per_glyph, glyph_index, 13)));
    record.color = snailUnpackUnorm4x8(snailTextSampleWord(words_per_glyph, glyph_index, 14));
    record.tint = snailUnpackUnorm4x8(snailTextSampleWord(words_per_glyph, glyph_index, 15));
    return record;
}

highp vec2 snailTextSampleLocalCoord(highp vec2 scene_pos, highp vec4 xform, highp vec2 origin)
{
    highp float det = (xform.x * xform.w) - (xform.y * xform.z);
    highp vec2 delta = scene_pos - origin;
    highp float _346 = delta.x;
    highp float _348 = delta.y;
    return vec2(((xform.w * _346) - (xform.y * _348)) / det, (((-xform.z) * _346) + (xform.x * _348)) / det);
}

highp vec2 snailTextSampleLocalVector(highp vec2 scene_vector, highp vec4 xform)
{
    highp float det = (xform.x * xform.w) - (xform.y * xform.z);
    return vec2(((xform.w * scene_vector.x) - (xform.y * scene_vector.y)) / det, (((-xform.z) * scene_vector.x) + (xform.x * scene_vector.y)) / det);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _575;
    _575.first = first;
    _575.last = last;
    return _575;
}

CoverageBandSpan computeCoverageBandSpan(highp float coord, highp float eppAxis, highp float bandScale, highp float bandOffset, int bandMax)
{
    highp float center = (coord * bandScale) + bandOffset;
    highp float _559 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _563 = clamp(int(center - _559), 0, bandMax);
    return CoverageBandSpan_init(_563, max(_563, clamp(int(center + _559), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _610 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_610, glyphLoc.y);
    loc.y += (_610 >> 12);
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
    int _741 = base.x + offset;
    ivec2 loc = ivec2(_741, base.y);
    loc.y += (_741 >> 12);
    loc.x &= 4095;
    return loc;
}

highp float rootCodeCoord(highp float v)
{
    highp float _794;
    if (abs(v) <= 1.52587890625e-05)
    {
        _794 = 0.0;
    }
    else
    {
        _794 = v;
    }
    return _794;
}

uint calcRootCode(highp float y1, highp float y2, highp float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

highp float snapNearTangentSqrt(highp float disc, highp float b, highp float ac)
{
    highp float _893;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _893 = 0.0;
    }
    else
    {
        _893 = sqrt(disc);
    }
    return _893;
}

highp vec2 solveHorizPoly(highp vec4 p12, highp vec2 p3)
{
    highp vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    highp vec2 b = p12.xy - p12.zw;
    highp float _863 = a.y;
    highp float t1;
    highp float t2;
    if (abs(_863) < 1.52587890625e-05)
    {
        highp float _867 = b.y;
        if (abs(_867) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _867;
        }
        t2 = t1;
    }
    else
    {
        highp float _881 = b.y;
        highp float _884 = _863 * p12.y;
        highp float sq = snapNearTangentSqrt((_881 * _881) - _884, _881, _884);
        if (_881 >= 0.0)
        {
            highp float q = _881 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _863;
        }
        else
        {
            highp float q_1 = _881 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            highp float _935 = t1;
            t1 = q_1 / _863;
            t2 = _935;
        }
    }
    highp float _940 = a.x;
    highp float _944 = b.x * 2.0;
    return vec2((((_940 * t1) - _944) * t1) + p12.x, (((_940 * t2) - _944) * t2) + p12.x);
}

bool accumulateHorizContribution(inout highp float _710, inout highp float _711, highp vec2 _712, highp vec2 _713, ivec2 _714, int _715)
{
    highp vec4 _732 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_714, _715, 0).xyz, 0);
    highp vec4 _760 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_714, 1), _715, 0).xyz, 0);
    highp vec4 p12 = vec4(_732.xy, _732.zw) - vec4(_712, _712);
    highp vec2 p3 = _760.xy - _712;
    if ((max(max(p12.x, p12.z), p3.x) * _713.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        highp vec2 r = solveHorizPoly(p12, p3) * _713.x;
        if ((code & 1u) != 0u)
        {
            highp float _963 = r.x;
            _710 += clamp(_963 + 0.5, 0.0, 1.0);
            _711 = max(_711, clamp(1.0 - (abs(_963) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            highp float _979 = r.y;
            _710 -= clamp(_979 + 0.5, 0.0, 1.0);
            _711 = max(_711, clamp(1.0 - (abs(_979) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

highp vec2 solveVertPoly(highp vec4 p12, highp vec2 p3)
{
    highp vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    highp vec2 b = p12.xy - p12.zw;
    highp float _1142 = a.x;
    highp float t1;
    highp float t2;
    if (abs(_1142) < 1.52587890625e-05)
    {
        highp float _1146 = b.x;
        if (abs(_1146) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _1146;
        }
        t2 = t1;
    }
    else
    {
        highp float _1160 = b.x;
        highp float _1163 = _1142 * p12.x;
        highp float sq = snapNearTangentSqrt((_1160 * _1160) - _1163, _1160, _1163);
        if (_1160 >= 0.0)
        {
            highp float q = _1160 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _1142;
        }
        else
        {
            highp float q_1 = _1160 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            highp float _1190 = t1;
            t1 = q_1 / _1142;
            t2 = _1190;
        }
    }
    highp float _1195 = a.y;
    highp float _1199 = b.y * 2.0;
    return vec2((((_1195 * t1) - _1199) * t1) + p12.y, (((_1195 * t2) - _1199) * t2) + p12.y);
}

bool accumulateVertContribution(inout highp float _1065, inout highp float _1066, highp vec2 _1067, highp vec2 _1068, ivec2 _1069, int _1070)
{
    highp vec4 _1084 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1069, _1070, 0).xyz, 0);
    highp vec4 _1090 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_1069, 1), _1070, 0).xyz, 0);
    highp vec4 p12 = vec4(_1084.xy, _1084.zw) - vec4(_1067, _1067);
    highp vec2 p3 = _1090.xy - _1067;
    if ((max(max(p12.y, p12.w), p3.y) * _1068.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        highp vec2 r = solveVertPoly(p12, p3) * _1068.y;
        if ((code & 1u) != 0u)
        {
            highp float _1217 = r.x;
            _1065 -= clamp(_1217 + 0.5, 0.0, 1.0);
            _1066 = max(_1066, clamp(1.0 - (abs(_1217) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            highp float _1233 = r.y;
            _1065 += clamp(_1233 + 0.5, 0.0, 1.0);
            _1066 = max(_1066, clamp(1.0 - (abs(_1233) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

highp float applyFillRule(highp float winding, int fill_rule_mode)
{
    if (fill_rule_mode == 1)
    {
        return 1.0 - abs((fract(winding * 0.5) * 2.0) - 1.0);
    }
    return abs(winding);
}

highp float applyCoverageTransfer(highp float cov, highp float coverage_exponent)
{
    highp float _1313 = clamp(cov, 0.0, 1.0);
    highp float _1314 = max(coverage_exponent, 1.52587890625e-05);
    highp float _1309;
    if (abs(_1314 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1309 = _1313;
    }
    else
    {
        _1309 = pow(_1313, _1314);
    }
    return _1309;
}

highp float evalGlyphCoverage(highp vec2 _468, highp vec2 _469, highp vec2 _470, ivec2 _471, ivec2 _472, highp vec4 _473, int _474, highp float _475)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_468.y, _469.y, _473.y, _473.w, _472.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_468.x, _469.x, _473.x, _473.z, _472.x);
    highp float xcov = 0.0;
    highp float xwgt = 0.0;
    int _591 = hSpan.first;
    int _592 = hSpan.last;
    bool _593 = _591 != _592;
    int band = _591;
    int i;
    bool _481;
    for (;;)
    {
        bool _486_ladder_break = false;
        do
        {
            if (!(band <= _592))
            {
                _486_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_471, uint(band)), _474, 0).xyz, 0).xy.xy;
            ivec2 _639 = calcBandLoc(_471, hbd.y);
            int _641 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _491_ladder_break = false;
                do
                {
                    if (!(i < _641))
                    {
                        _491_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_639, uint(i)), _474, 0).xyz, 0).xy.xy;
                    if (_593)
                    {
                        _481 = !isCoverageBandSpanOwner(ref, band, _591);
                    }
                    else
                    {
                        _481 = false;
                    }
                    if (_481)
                    {
                        break;
                    }
                    bool _707 = accumulateHorizContribution(xcov, xwgt, _468, _470, decodeBandCurveLoc(ref), _474);
                    if (!_707)
                    {
                        _491_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_491_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_486_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    highp float ycov = 0.0;
    highp float ywgt = 0.0;
    int _1014 = vSpan.first;
    int _1015 = vSpan.last;
    bool _1016 = _1014 != _1015;
    band = _1014;
    for (;;)
    {
        bool _513_ladder_break = false;
        do
        {
            if (!(band <= _1015))
            {
                _513_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_471, uint((_472.y + 1) + band)), _474, 0).xyz, 0).xy.xy;
            ivec2 _1034 = calcBandLoc(_471, vbd.y);
            int _1036 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _518_ladder_break = false;
                do
                {
                    if (!(i < _1036))
                    {
                        _518_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_1034, uint(i)), _474, 0).xyz, 0).xy.xy;
                    if (_1016)
                    {
                        _481 = !isCoverageBandSpanOwner(ref_1, band, _1014);
                    }
                    else
                    {
                        _481 = false;
                    }
                    if (_481)
                    {
                        break;
                    }
                    bool _1063 = accumulateVertContribution(ycov, ywgt, _468, _470, decodeBandCurveLoc(ref_1), _474);
                    if (!_1063)
                    {
                        _518_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_518_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_513_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _475);
}

highp float srgbDecode(highp float c)
{
    highp float _1351;
    if (c <= 0.040449999272823333740234375)
    {
        _1351 = c / 12.9200000762939453125;
    }
    else
    {
        _1351 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _1351;
}

highp vec3 srgbToLinear(highp vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

highp vec4 snailTextSamplePremulLinearWithFootprint(int _54, int _55, int _56, highp float _57, highp vec2 _58, highp vec2 _59, highp vec2 _60)
{
    highp vec4 paint = vec4(0.0);
    int i = 0;
    bool _68;
    bool _69;
    bool _70;
    for (;;)
    {
        bool _73_ladder_break = false;
        do
        {
            if (!(i < _55))
            {
                _73_ladder_break = true;
                break;
            }
            SnailTextSampleRecord _109 = snailTextSampleRecord(_54, i);
            highp vec4 _317 = _109.xform;
            if (abs((_317.x * _317.w) - (_317.y * _317.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp vec2 rc = snailTextSampleLocalCoord(_58, _317, _109.origin);
            highp vec2 epp = abs(snailTextSampleLocalVector(_59, _317)) + abs(snailTextSampleLocalVector(_60, _317));
            highp vec2 _391 = max(epp * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _394 = rc.x;
            highp vec4 _395 = _109.rect;
            highp float _397 = _391.x;
            if (_394 < (_395.x - _397))
            {
                _68 = true;
            }
            else
            {
                _68 = _394 > (_395.z + _397);
            }
            if (_68)
            {
                _69 = true;
            }
            else
            {
                _69 = rc.y < (_395.y - _391.y);
            }
            if (_69)
            {
                _70 = true;
            }
            else
            {
                _70 = rc.y > (_395.w + _391.y);
            }
            if (_70)
            {
                break;
            }
            uvec2 _434 = _109.glyph;
            uint gz = _434.x;
            uint gw = _434.y;
            int layer_byte = int((gw >> 24u) & 255u);
            if (layer_byte == 255)
            {
                break;
            }
            highp vec4 _1328 = _109.color;
            highp vec4 _1331 = _109.tint;
            highp float _1334 = clamp((evalGlyphCoverage(rc, epp, vec2(1.0 / max(epp.x, 1.52587890625e-05), 1.0 / max(epp.y, 1.52587890625e-05)), ivec2(int(gz & 65535u), int(gz >> 16u)), ivec2(int((gw >> 16u) & 255u), int(gw & 65535u)), _109.banding, _56 + layer_byte, _57) * _1328.w) * _1331.w, 0.0, 1.0);
            if (_1334 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp vec4 _1382 = paint;
            highp float _1384 = 1.0 - _1334;
            highp vec3 _1386 = ((srgbToLinear(_1328.xyz) * srgbToLinear(_1331.xyz)) * _1334) + (_1382.xyz * _1384);
            paint.x = _1386.x;
            paint.y = _1386.y;
            paint.z = _1386.z;
            paint.w = _1334 + (paint.w * _1384);
            break;
        } while(false);
        if (_73_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    return paint;
}

highp vec4 snailTextSamplePremulLinear(int _32, int _33, int _34, highp float _35, highp vec2 _36)
{
    return snailTextSamplePremulLinearWithFootprint(_32, _33, _34, _35, _36, ddx(_36), ddy(_36));
}

void main()
{
    entryPointParam_fragmentMain = snailTextSamplePremulLinear(pc.words_per_glyph, pc.glyph_count, pc.layer_base, pc.coverage_exponent, snail_io0);
}

