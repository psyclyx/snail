#version 330

struct SnailTextSampleRecord
{
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 banding;
    vec4 color;
    vec4 tint;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

uvec4 _634;
uvec4 _652;
uvec4 _1029;
uvec4 _1047;

layout(std140) uniform SnailTextSampleParams_std140
{
    int glyph_count;
    int words_per_glyph;
    int layer_base;
    float coverage_exponent;
} pc;

uniform usamplerBuffer u_snail_text_records;
uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in vec2 snail_io0;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

vec2 ddx(vec2 p)
{
    return dFdx(p);
}

vec2 ddy(vec2 p)
{
    return dFdy(p);
}

uint Records_word(int linear_index)
{
    return texelFetch(u_snail_text_records, int(uint(linear_index))).x;
}

uint snailTextSampleWord(int words_per_glyph, int glyph_index, int word_offset)
{
    return Records_word((glyph_index * words_per_glyph) + word_offset);
}

float snailDecodeFloat16(uint bits)
{
    uint exponent = (bits >> 10u) & 31u;
    uint fraction = bits & 1023u;
    float _sign;
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
        return (_sign * exp2(-14.0)) * (float(fraction) / 1024.0);
    }
    if (exponent == 31u)
    {
        return _sign * 65504.0;
    }
    return (_sign * exp2(float(exponent) - 15.0)) * (1.0 + (float(fraction) / 1024.0));
}

vec2 snailUnpackHalf2(uint word)
{
    return vec2(snailDecodeFloat16(word & 65535u), snailDecodeFloat16(word >> 16u));
}

vec4 snailUnpackHalf4(uint lo, uint hi)
{
    return vec4(snailUnpackHalf2(lo), snailUnpackHalf2(hi));
}

vec4 snailUnpackUnorm4x8(uint word)
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

vec2 snailTextSampleLocalCoord(vec2 scene_pos, vec4 xform, vec2 origin)
{
    float det = (xform.x * xform.w) - (xform.y * xform.z);
    vec2 delta = scene_pos - origin;
    float _343 = delta.x;
    float _345 = delta.y;
    return vec2(((xform.w * _343) - (xform.y * _345)) / det, (((-xform.z) * _343) + (xform.x * _345)) / det);
}

vec2 snailTextSampleLocalVector(vec2 scene_vector, vec4 xform)
{
    float det = (xform.x * xform.w) - (xform.y * xform.z);
    return vec2(((xform.w * scene_vector.x) - (xform.y * scene_vector.y)) / det, (((-xform.z) * scene_vector.x) + (xform.x * scene_vector.y)) / det);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _573;
    _573.first = first;
    _573.last = last;
    return _573;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _557 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _561 = clamp(int(center - _557), 0, bandMax);
    return CoverageBandSpan_init(_561, max(_561, clamp(int(center + _557), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _608 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_608, glyphLoc.y);
    loc.y += (_608 >> 12);
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
    int _739 = base.x + offset;
    ivec2 loc = ivec2(_739, base.y);
    loc.y += (_739 >> 12);
    loc.x &= 4095;
    return loc;
}

float rootCodeCoord(float v)
{
    float _792;
    if (abs(v) <= 1.52587890625e-05)
    {
        _792 = 0.0;
    }
    else
    {
        _792 = v;
    }
    return _792;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _891;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _891 = 0.0;
    }
    else
    {
        _891 = sqrt(disc);
    }
    return _891;
}

vec2 solveHorizPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _861 = a.y;
    float t1;
    float t2;
    if (abs(_861) < 1.52587890625e-05)
    {
        float _865 = b.y;
        if (abs(_865) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _865;
        }
        t2 = t1;
    }
    else
    {
        float _879 = b.y;
        float _882 = _861 * p12.y;
        float sq = snapNearTangentSqrt((_879 * _879) - _882, _879, _882);
        if (_879 >= 0.0)
        {
            float q = _879 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _861;
        }
        else
        {
            float q_1 = _879 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            float _933 = t1;
            t1 = q_1 / _861;
            t2 = _933;
        }
    }
    float _938 = a.x;
    float _942 = b.x * 2.0;
    return vec2((((_938 * t1) - _942) * t1) + p12.x, (((_938 * t2) - _942) * t2) + p12.x);
}

bool accumulateHorizContribution(inout float _708, inout float _709, vec2 _710, vec2 _711, ivec2 _712, int _713)
{
    vec4 _730 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_712, _713, 0).xyz, 0);
    vec4 _758 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_712, 1), _713, 0).xyz, 0);
    vec4 p12 = vec4(_730.xy, _730.zw) - vec4(_710, _710);
    vec2 p3 = _758.xy - _710;
    if ((max(max(p12.x, p12.z), p3.x) * _711.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        vec2 r = solveHorizPoly(p12, p3) * _711.x;
        if ((code & 1u) != 0u)
        {
            float _961 = r.x;
            _708 += clamp(_961 + 0.5, 0.0, 1.0);
            _709 = max(_709, clamp(1.0 - (abs(_961) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _977 = r.y;
            _708 -= clamp(_977 + 0.5, 0.0, 1.0);
            _709 = max(_709, clamp(1.0 - (abs(_977) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveVertPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _1140 = a.x;
    float t1;
    float t2;
    if (abs(_1140) < 1.52587890625e-05)
    {
        float _1144 = b.x;
        if (abs(_1144) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _1144;
        }
        t2 = t1;
    }
    else
    {
        float _1158 = b.x;
        float _1161 = _1140 * p12.x;
        float sq = snapNearTangentSqrt((_1158 * _1158) - _1161, _1158, _1161);
        if (_1158 >= 0.0)
        {
            float q = _1158 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _1140;
        }
        else
        {
            float q_1 = _1158 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            float _1188 = t1;
            t1 = q_1 / _1140;
            t2 = _1188;
        }
    }
    float _1193 = a.y;
    float _1197 = b.y * 2.0;
    return vec2((((_1193 * t1) - _1197) * t1) + p12.y, (((_1193 * t2) - _1197) * t2) + p12.y);
}

bool accumulateVertContribution(inout float _1063, inout float _1064, vec2 _1065, vec2 _1066, ivec2 _1067, int _1068)
{
    vec4 _1082 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1067, _1068, 0).xyz, 0);
    vec4 _1088 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_1067, 1), _1068, 0).xyz, 0);
    vec4 p12 = vec4(_1082.xy, _1082.zw) - vec4(_1065, _1065);
    vec2 p3 = _1088.xy - _1065;
    if ((max(max(p12.y, p12.w), p3.y) * _1066.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        vec2 r = solveVertPoly(p12, p3) * _1066.y;
        if ((code & 1u) != 0u)
        {
            float _1215 = r.x;
            _1063 -= clamp(_1215 + 0.5, 0.0, 1.0);
            _1064 = max(_1064, clamp(1.0 - (abs(_1215) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _1231 = r.y;
            _1063 += clamp(_1231 + 0.5, 0.0, 1.0);
            _1064 = max(_1064, clamp(1.0 - (abs(_1231) * 2.0), 0.0, 1.0));
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

float applyCoverageTransfer(float cov, float coverage_exponent)
{
    float _1311 = clamp(cov, 0.0, 1.0);
    float _1312 = max(coverage_exponent, 1.52587890625e-05);
    float _1307;
    if (abs(_1312 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1307 = _1311;
    }
    else
    {
        _1307 = pow(_1311, _1312);
    }
    return _1307;
}

float evalGlyphCoverage(vec2 _466, vec2 _467, vec2 _468, ivec2 _469, ivec2 _470, vec4 _471, int _472, float _473)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_466.y, _467.y, _471.y, _471.w, _470.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_466.x, _467.x, _471.x, _471.z, _470.x);
    float xcov = 0.0;
    float xwgt = 0.0;
    int _589 = hSpan.first;
    int _590 = hSpan.last;
    bool _591 = _589 != _590;
    int band = _589;
    int i;
    bool _479;
    for (;;)
    {
        bool _484_ladder_break = false;
        do
        {
            if (!(band <= _590))
            {
                _484_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_469, uint(band)), _472, 0).xyz, 0).xy.xy;
            ivec2 _637 = calcBandLoc(_469, hbd.y);
            int _639 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _489_ladder_break = false;
                do
                {
                    if (!(i < _639))
                    {
                        _489_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_637, uint(i)), _472, 0).xyz, 0).xy.xy;
                    if (_591)
                    {
                        _479 = !isCoverageBandSpanOwner(ref, band, _589);
                    }
                    else
                    {
                        _479 = false;
                    }
                    if (_479)
                    {
                        break;
                    }
                    bool _705 = accumulateHorizContribution(xcov, xwgt, _466, _468, decodeBandCurveLoc(ref), _472);
                    if (!_705)
                    {
                        _489_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_489_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_484_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    float ycov = 0.0;
    float ywgt = 0.0;
    int _1012 = vSpan.first;
    int _1013 = vSpan.last;
    bool _1014 = _1012 != _1013;
    band = _1012;
    for (;;)
    {
        bool _511_ladder_break = false;
        do
        {
            if (!(band <= _1013))
            {
                _511_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_469, uint((_470.y + 1) + band)), _472, 0).xyz, 0).xy.xy;
            ivec2 _1032 = calcBandLoc(_469, vbd.y);
            int _1034 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _516_ladder_break = false;
                do
                {
                    if (!(i < _1034))
                    {
                        _516_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_1032, uint(i)), _472, 0).xyz, 0).xy.xy;
                    if (_1014)
                    {
                        _479 = !isCoverageBandSpanOwner(ref_1, band, _1012);
                    }
                    else
                    {
                        _479 = false;
                    }
                    if (_479)
                    {
                        break;
                    }
                    bool _1061 = accumulateVertContribution(ycov, ywgt, _466, _468, decodeBandCurveLoc(ref_1), _472);
                    if (!_1061)
                    {
                        _516_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_516_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_511_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _473);
}

float srgbDecode(float c)
{
    float _1349;
    if (c <= 0.040449999272823333740234375)
    {
        _1349 = c / 12.9200000762939453125;
    }
    else
    {
        _1349 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _1349;
}

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

vec4 snailTextSamplePremulLinearWithFootprint(int _54, int _55, int _56, float _57, vec2 _58, vec2 _59, vec2 _60)
{
    vec4 paint = vec4(0.0);
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
            vec4 _314 = _109.xform;
            if (abs((_314.x * _314.w) - (_314.y * _314.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            vec2 rc = snailTextSampleLocalCoord(_58, _314, _109.origin);
            vec2 epp = abs(snailTextSampleLocalVector(_59, _314)) + abs(snailTextSampleLocalVector(_60, _314));
            vec2 _388 = max(epp * 2.0, vec2(0.001000000047497451305389404296875));
            float _391 = rc.x;
            vec4 _392 = _109.rect;
            float _394 = _388.x;
            if (_391 < (_392.x - _394))
            {
                _68 = true;
            }
            else
            {
                _68 = _391 > (_392.z + _394);
            }
            if (_68)
            {
                _69 = true;
            }
            else
            {
                _69 = rc.y < (_392.y - _388.y);
            }
            if (_69)
            {
                _70 = true;
            }
            else
            {
                _70 = rc.y > (_392.w + _388.y);
            }
            if (_70)
            {
                break;
            }
            uvec2 _431 = _109.glyph;
            uint gz = _431.x;
            uint gw = _431.y;
            int layer_byte = int((gw >> 24u) & 255u);
            if (layer_byte == 255)
            {
                break;
            }
            vec4 _1326 = _109.color;
            vec4 _1329 = _109.tint;
            float _1332 = clamp((evalGlyphCoverage(rc, epp, vec2(1.0 / max(epp.x, 1.52587890625e-05), 1.0 / max(epp.y, 1.52587890625e-05)), ivec2(int(gz & 65535u), int(gz >> 16u)), ivec2(int((gw >> 16u) & 255u), int(gw & 65535u)), _109.banding, _56 + layer_byte, _57) * _1326.w) * _1329.w, 0.0, 1.0);
            if (_1332 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            vec4 _1380 = paint;
            float _1382 = 1.0 - _1332;
            vec3 _1384 = ((srgbToLinear(_1326.xyz) * srgbToLinear(_1329.xyz)) * _1332) + (_1380.xyz * _1382);
            paint.x = _1384.x;
            paint.y = _1384.y;
            paint.z = _1384.z;
            paint.w = _1332 + (paint.w * _1382);
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

vec4 snailTextSamplePremulLinear(int _32, int _33, int _34, float _35, vec2 _36)
{
    return snailTextSamplePremulLinearWithFootprint(_32, _33, _34, _35, _36, ddx(_36), ddy(_36));
}

void main()
{
    entryPointParam_fragmentMain = snailTextSamplePremulLinear(pc.words_per_glyph, pc.glyph_count, pc.layer_base, pc.coverage_exponent, snail_io0);
}

