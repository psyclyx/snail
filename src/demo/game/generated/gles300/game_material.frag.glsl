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

uvec4 _678;
uvec4 _696;
uvec4 _1073;
uvec4 _1091;

layout(std140) uniform GameMaterialParams_std140
{
    layout(row_major) highp mat4 view_proj;
    layout(row_major) highp mat4 model;
    highp vec4 base_color;
    highp vec4 light_dir;
    highp vec2 scene_size;
    int glyph_count;
    int output_srgb;
    highp float relief;
    highp float roughness;
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
        highp float _248 = exp2(-14.0);
        return (_sign * _248) * (float(fraction) / 1024.0);
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
    highp float _389 = delta.x;
    highp float _391 = delta.y;
    return vec2(((xform.w * _389) - (xform.y * _391)) / det, (((-xform.z) * _389) + (xform.x * _391)) / det);
}

highp vec2 snailTextSampleLocalVector(highp vec2 scene_vector, highp vec4 xform)
{
    highp float det = (xform.x * xform.w) - (xform.y * xform.z);
    return vec2(((xform.w * scene_vector.x) - (xform.y * scene_vector.y)) / det, (((-xform.z) * scene_vector.x) + (xform.x * scene_vector.y)) / det);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _617;
    _617.first = first;
    _617.last = last;
    return _617;
}

CoverageBandSpan computeCoverageBandSpan(highp float coord, highp float eppAxis, highp float bandScale, highp float bandOffset, int bandMax)
{
    highp float center = (coord * bandScale) + bandOffset;
    highp float _601 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _605 = clamp(int(center - _601), 0, bandMax);
    return CoverageBandSpan_init(_605, max(_605, clamp(int(center + _601), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _652 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_652, glyphLoc.y);
    loc.y += (_652 >> 12);
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
    int _783 = base.x + offset;
    ivec2 loc = ivec2(_783, base.y);
    loc.y += (_783 >> 12);
    loc.x &= 4095;
    return loc;
}

highp float rootCodeCoord(highp float v)
{
    highp float _836;
    if (abs(v) <= 1.52587890625e-05)
    {
        _836 = 0.0;
    }
    else
    {
        _836 = v;
    }
    return _836;
}

uint calcRootCode(highp float y1, highp float y2, highp float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

highp float snapNearTangentSqrt(highp float disc, highp float b, highp float ac)
{
    highp float _935;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _935 = 0.0;
    }
    else
    {
        _935 = sqrt(disc);
    }
    return _935;
}

highp vec2 solveHorizPoly(highp vec4 p12, highp vec2 p3)
{
    highp vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    highp vec2 b = p12.xy - p12.zw;
    highp float _905 = a.y;
    highp float t1;
    highp float t2;
    if (abs(_905) < 1.52587890625e-05)
    {
        highp float _909 = b.y;
        if (abs(_909) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _909;
        }
        t2 = t1;
    }
    else
    {
        highp float _923 = b.y;
        highp float _926 = _905 * p12.y;
        highp float sq = snapNearTangentSqrt((_923 * _923) - _926, _923, _926);
        if (_923 >= 0.0)
        {
            highp float q = _923 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _905;
        }
        else
        {
            highp float q_1 = _923 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            highp float _977 = t1;
            t1 = q_1 / _905;
            t2 = _977;
        }
    }
    highp float _982 = a.x;
    highp float _986 = b.x * 2.0;
    return vec2((((_982 * t1) - _986) * t1) + p12.x, (((_982 * t2) - _986) * t2) + p12.x);
}

bool accumulateHorizContribution(inout highp float _752, inout highp float _753, highp vec2 _754, highp vec2 _755, ivec2 _756, int _757)
{
    highp vec4 _774 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_756, _757, 0).xyz, 0);
    highp vec4 _802 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_756, 1), _757, 0).xyz, 0);
    highp vec4 p12 = vec4(_774.xy, _774.zw) - vec4(_754, _754);
    highp vec2 p3 = _802.xy - _754;
    if ((max(max(p12.x, p12.z), p3.x) * _755.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        highp vec2 r = solveHorizPoly(p12, p3) * _755.x;
        if ((code & 1u) != 0u)
        {
            highp float _1005 = r.x;
            _752 += clamp(_1005 + 0.5, 0.0, 1.0);
            _753 = max(_753, clamp(1.0 - (abs(_1005) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            highp float _1021 = r.y;
            _752 -= clamp(_1021 + 0.5, 0.0, 1.0);
            _753 = max(_753, clamp(1.0 - (abs(_1021) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

highp vec2 solveVertPoly(highp vec4 p12, highp vec2 p3)
{
    highp vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    highp vec2 b = p12.xy - p12.zw;
    highp float _1184 = a.x;
    highp float t1;
    highp float t2;
    if (abs(_1184) < 1.52587890625e-05)
    {
        highp float _1188 = b.x;
        if (abs(_1188) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _1188;
        }
        t2 = t1;
    }
    else
    {
        highp float _1202 = b.x;
        highp float _1205 = _1184 * p12.x;
        highp float sq = snapNearTangentSqrt((_1202 * _1202) - _1205, _1202, _1205);
        if (_1202 >= 0.0)
        {
            highp float q = _1202 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _1184;
        }
        else
        {
            highp float q_1 = _1202 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            highp float _1232 = t1;
            t1 = q_1 / _1184;
            t2 = _1232;
        }
    }
    highp float _1237 = a.y;
    highp float _1241 = b.y * 2.0;
    return vec2((((_1237 * t1) - _1241) * t1) + p12.y, (((_1237 * t2) - _1241) * t2) + p12.y);
}

bool accumulateVertContribution(inout highp float _1107, inout highp float _1108, highp vec2 _1109, highp vec2 _1110, ivec2 _1111, int _1112)
{
    highp vec4 _1126 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1111, _1112, 0).xyz, 0);
    highp vec4 _1132 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_1111, 1), _1112, 0).xyz, 0);
    highp vec4 p12 = vec4(_1126.xy, _1126.zw) - vec4(_1109, _1109);
    highp vec2 p3 = _1132.xy - _1109;
    if ((max(max(p12.y, p12.w), p3.y) * _1110.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        highp vec2 r = solveVertPoly(p12, p3) * _1110.y;
        if ((code & 1u) != 0u)
        {
            highp float _1259 = r.x;
            _1107 -= clamp(_1259 + 0.5, 0.0, 1.0);
            _1108 = max(_1108, clamp(1.0 - (abs(_1259) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            highp float _1275 = r.y;
            _1107 += clamp(_1275 + 0.5, 0.0, 1.0);
            _1108 = max(_1108, clamp(1.0 - (abs(_1275) * 2.0), 0.0, 1.0));
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
    highp float _1355 = clamp(cov, 0.0, 1.0);
    highp float _1356 = max(coverage_exponent, 1.52587890625e-05);
    highp float _1351;
    if (abs(_1356 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1351 = _1355;
    }
    else
    {
        _1351 = pow(_1355, _1356);
    }
    return _1351;
}

highp float evalGlyphCoverage(highp vec2 _510, highp vec2 _511, highp vec2 _512, ivec2 _513, ivec2 _514, highp vec4 _515, int _516, highp float _517)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_510.y, _511.y, _515.y, _515.w, _514.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_510.x, _511.x, _515.x, _515.z, _514.x);
    highp float xcov = 0.0;
    highp float xwgt = 0.0;
    int _633 = hSpan.first;
    int _634 = hSpan.last;
    bool _635 = _633 != _634;
    int band = _633;
    int i;
    bool _523;
    for (;;)
    {
        bool _528_ladder_break = false;
        do
        {
            if (!(band <= _634))
            {
                _528_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_513, uint(band)), _516, 0).xyz, 0).xy.xy;
            ivec2 _681 = calcBandLoc(_513, hbd.y);
            int _683 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _533_ladder_break = false;
                do
                {
                    if (!(i < _683))
                    {
                        _533_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_681, uint(i)), _516, 0).xyz, 0).xy.xy;
                    if (_635)
                    {
                        _523 = !isCoverageBandSpanOwner(ref, band, _633);
                    }
                    else
                    {
                        _523 = false;
                    }
                    if (_523)
                    {
                        break;
                    }
                    bool _749 = accumulateHorizContribution(xcov, xwgt, _510, _512, decodeBandCurveLoc(ref), _516);
                    if (!_749)
                    {
                        _533_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_533_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_528_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    highp float ycov = 0.0;
    highp float ywgt = 0.0;
    int _1056 = vSpan.first;
    int _1057 = vSpan.last;
    bool _1058 = _1056 != _1057;
    band = _1056;
    for (;;)
    {
        bool _555_ladder_break = false;
        do
        {
            if (!(band <= _1057))
            {
                _555_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_513, uint((_514.y + 1) + band)), _516, 0).xyz, 0).xy.xy;
            ivec2 _1076 = calcBandLoc(_513, vbd.y);
            int _1078 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _560_ladder_break = false;
                do
                {
                    if (!(i < _1078))
                    {
                        _560_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_1076, uint(i)), _516, 0).xyz, 0).xy.xy;
                    if (_1058)
                    {
                        _523 = !isCoverageBandSpanOwner(ref_1, band, _1056);
                    }
                    else
                    {
                        _523 = false;
                    }
                    if (_523)
                    {
                        break;
                    }
                    bool _1105 = accumulateVertContribution(ycov, ywgt, _510, _512, decodeBandCurveLoc(ref_1), _516);
                    if (!_1105)
                    {
                        _560_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_560_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_555_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _517);
}

highp float srgbDecode(highp float c)
{
    highp float _1392;
    if (c <= 0.040449999272823333740234375)
    {
        _1392 = c / 12.9200000762939453125;
    }
    else
    {
        _1392 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _1392;
}

highp vec3 srgbToLinear(highp vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

highp vec4 snailTextSamplePremulLinearWithFootprint(int _101, int _102, int _103, highp float _104, highp vec2 _105, highp vec2 _106, highp vec2 _107)
{
    highp vec4 paint = vec4(0.0);
    int i = 0;
    bool _115;
    bool _116;
    bool _117;
    for (;;)
    {
        bool _120_ladder_break = false;
        do
        {
            if (!(i < _102))
            {
                _120_ladder_break = true;
                break;
            }
            SnailTextSampleRecord _157 = snailTextSampleRecord(_101, i);
            highp vec4 _360 = _157.xform;
            if (abs((_360.x * _360.w) - (_360.y * _360.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp vec2 rc = snailTextSampleLocalCoord(_105, _360, _157.origin);
            highp vec2 epp = abs(snailTextSampleLocalVector(_106, _360)) + abs(snailTextSampleLocalVector(_107, _360));
            highp vec2 _434 = max(epp * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _437 = rc.x;
            highp vec4 _438 = _157.rect;
            highp float _440 = _434.x;
            if (_437 < (_438.x - _440))
            {
                _115 = true;
            }
            else
            {
                _115 = _437 > (_438.z + _440);
            }
            if (_115)
            {
                _116 = true;
            }
            else
            {
                _116 = rc.y < (_438.y - _434.y);
            }
            if (_116)
            {
                _117 = true;
            }
            else
            {
                _117 = rc.y > (_438.w + _434.y);
            }
            if (_117)
            {
                break;
            }
            uvec2 _477 = _157.glyph;
            uint gz = _477.x;
            uint gw = _477.y;
            int layer_byte = int((gw >> 24u) & 255u);
            if (layer_byte == 255)
            {
                break;
            }
            highp vec4 _1370 = _157.color;
            highp vec4 _1373 = _157.tint;
            highp float _1376 = clamp((evalGlyphCoverage(rc, epp, vec2(1.0 / max(epp.x, 1.52587890625e-05), 1.0 / max(epp.y, 1.52587890625e-05)), ivec2(int(gz & 65535u), int(gz >> 16u)), ivec2(int((gw >> 16u) & 255u), int(gw & 65535u)), _157.banding, _103 + layer_byte, _104) * _1370.w) * _1373.w, 0.0, 1.0);
            if (_1376 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp vec4 _1423 = paint;
            highp float _1425 = 1.0 - _1376;
            highp vec3 _1427 = ((srgbToLinear(_1370.xyz) * srgbToLinear(_1373.xyz)) * _1376) + (_1423.xyz * _1425);
            paint.x = _1427.x;
            paint.y = _1427.y;
            paint.z = _1427.z;
            paint.w = _1376 + (paint.w * _1425);
            break;
        } while(false);
        if (_120_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    return paint;
}

highp vec4 snailGameTextSample(highp vec2 scene_pos, highp vec2 scene_dx, highp vec2 scene_dy)
{
    return snailTextSamplePremulLinearWithFootprint(23, pc.glyph_count, 0, 1.0, scene_pos, scene_dx, scene_dy);
}

highp float snailGameHeight(highp vec2 uv)
{
    highp vec2 p = uv * 6.283185482025146484375;
    return (((0.5 * sin(dot(p, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(p, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(p, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(p, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375));
}

highp vec3 snailGameMaterial(highp vec2 uv, highp vec2 scene_pos, highp vec2 scene_dx, highp vec2 scene_dy, highp vec3 light_dir, highp vec4 base, highp float relief, highp float roughness)
{
    highp vec2 _84 = max((abs(scene_dx) + abs(scene_dy)) * 1.25, vec2(1.52587890625e-05));
    highp vec2 _1454 = vec2(_84.x, 0.0);
    highp vec2 _1462 = vec2(0.0, _84.y);
    highp float h0 = snailGameHeight(uv);
    highp vec3 _1533 = normalize(vec3(-((vec2(snailGameHeight(uv + vec2(0.0009765625, 0.0)) - h0, snailGameHeight(uv + vec2(0.0, 0.0009765625)) - h0) * (roughness / 0.0009765625)) + (vec2(snailGameTextSample(scene_pos + _1454, scene_dx, scene_dy).w - snailGameTextSample(scene_pos - _1454, scene_dx, scene_dy).w, snailGameTextSample(scene_pos + _1462, scene_dx, scene_dy).w - snailGameTextSample(scene_pos - _1462, scene_dx, scene_dy).w) * (0.5 * relief))), 1.0));
    highp vec3 _1534 = normalize(light_dir);
    highp float _1544 = clamp(snailGameTextSample(scene_pos, scene_dx, scene_dy).w, 0.0, 1.0);
    return ((mix(base.xyz, vec3(0.23999999463558197021484375, 0.300000011920928955078125, 0.4000000059604644775390625), vec3(_1544)) * (0.20000000298023223876953125 + ((0.7799999713897705078125 + (0.2199999988079071044921875 * _1544)) * max(dot(_1533, _1534), 0.0)))) * (0.939999997615814208984375 + (0.0599999986588954925537109375 * h0))) + ((vec3(0.800000011920928955078125, 0.87999999523162841796875, 1.0) * pow(max(dot(_1533, normalize(_1534 + vec3(0.0, 0.0, 1.0))), 0.0), 40.0)) * (0.119999997317790985107421875 + (0.2800000011920928955078125 * _1544)));
}

highp vec3 snailGameEncodeSrgb(highp vec3 c)
{
    highp vec3 _1583 = clamp(c, vec3(0.0), vec3(1.0));
    return mix((pow(_1583, vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), _1583 * 12.9200000762939453125, step(_1583, vec3(0.003130800090730190277099609375)));
}

void main()
{
    highp vec2 scene_pos = vec2(snail_io0.x * pc.scene_size.x, (1.0 - snail_io0.y) * pc.scene_size.y);
    highp vec3 lin = snailGameMaterial(snail_io0, scene_pos, ddx(scene_pos), ddy(scene_pos), pc.light_dir.xyz, pc.base_color, pc.relief, pc.roughness);
    highp vec3 outc;
    if (pc.output_srgb == 1)
    {
        outc = snailGameEncodeSrgb(lin);
    }
    else
    {
        outc = lin;
    }
    entryPointParam_fragmentMain = vec4(outc, 1.0);
}

