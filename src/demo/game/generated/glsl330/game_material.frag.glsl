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

uvec4 _676;
uvec4 _694;
uvec4 _1071;
uvec4 _1089;

layout(std140) uniform GameMaterialParams_std140
{
    layout(row_major) mat4 view_proj;
    layout(row_major) mat4 model;
    vec4 base_color;
    vec4 light_dir;
    vec2 scene_size;
    int glyph_count;
    int output_srgb;
    float relief;
    float roughness;
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
    float _386 = delta.x;
    float _388 = delta.y;
    return vec2(((xform.w * _386) - (xform.y * _388)) / det, (((-xform.z) * _386) + (xform.x * _388)) / det);
}

vec2 snailTextSampleLocalVector(vec2 scene_vector, vec4 xform)
{
    float det = (xform.x * xform.w) - (xform.y * xform.z);
    return vec2(((xform.w * scene_vector.x) - (xform.y * scene_vector.y)) / det, (((-xform.z) * scene_vector.x) + (xform.x * scene_vector.y)) / det);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _615;
    _615.first = first;
    _615.last = last;
    return _615;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _599 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _603 = clamp(int(center - _599), 0, bandMax);
    return CoverageBandSpan_init(_603, max(_603, clamp(int(center + _599), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _650 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_650, glyphLoc.y);
    loc.y += (_650 >> 12);
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
    int _781 = base.x + offset;
    ivec2 loc = ivec2(_781, base.y);
    loc.y += (_781 >> 12);
    loc.x &= 4095;
    return loc;
}

float rootCodeCoord(float v)
{
    float _834;
    if (abs(v) <= 1.52587890625e-05)
    {
        _834 = 0.0;
    }
    else
    {
        _834 = v;
    }
    return _834;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _933;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _933 = 0.0;
    }
    else
    {
        _933 = sqrt(disc);
    }
    return _933;
}

vec2 solveHorizPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _903 = a.y;
    float t1;
    float t2;
    if (abs(_903) < 1.52587890625e-05)
    {
        float _907 = b.y;
        if (abs(_907) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _907;
        }
        t2 = t1;
    }
    else
    {
        float _921 = b.y;
        float _924 = _903 * p12.y;
        float sq = snapNearTangentSqrt((_921 * _921) - _924, _921, _924);
        if (_921 >= 0.0)
        {
            float q = _921 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _903;
        }
        else
        {
            float q_1 = _921 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            float _975 = t1;
            t1 = q_1 / _903;
            t2 = _975;
        }
    }
    float _980 = a.x;
    float _984 = b.x * 2.0;
    return vec2((((_980 * t1) - _984) * t1) + p12.x, (((_980 * t2) - _984) * t2) + p12.x);
}

bool accumulateHorizContribution(inout float _750, inout float _751, vec2 _752, vec2 _753, ivec2 _754, int _755)
{
    vec4 _772 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_754, _755, 0).xyz, 0);
    vec4 _800 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_754, 1), _755, 0).xyz, 0);
    vec4 p12 = vec4(_772.xy, _772.zw) - vec4(_752, _752);
    vec2 p3 = _800.xy - _752;
    if ((max(max(p12.x, p12.z), p3.x) * _753.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        vec2 r = solveHorizPoly(p12, p3) * _753.x;
        if ((code & 1u) != 0u)
        {
            float _1003 = r.x;
            _750 += clamp(_1003 + 0.5, 0.0, 1.0);
            _751 = max(_751, clamp(1.0 - (abs(_1003) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _1019 = r.y;
            _750 -= clamp(_1019 + 0.5, 0.0, 1.0);
            _751 = max(_751, clamp(1.0 - (abs(_1019) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveVertPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _1182 = a.x;
    float t1;
    float t2;
    if (abs(_1182) < 1.52587890625e-05)
    {
        float _1186 = b.x;
        if (abs(_1186) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _1186;
        }
        t2 = t1;
    }
    else
    {
        float _1200 = b.x;
        float _1203 = _1182 * p12.x;
        float sq = snapNearTangentSqrt((_1200 * _1200) - _1203, _1200, _1203);
        if (_1200 >= 0.0)
        {
            float q = _1200 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _1182;
        }
        else
        {
            float q_1 = _1200 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            float _1230 = t1;
            t1 = q_1 / _1182;
            t2 = _1230;
        }
    }
    float _1235 = a.y;
    float _1239 = b.y * 2.0;
    return vec2((((_1235 * t1) - _1239) * t1) + p12.y, (((_1235 * t2) - _1239) * t2) + p12.y);
}

bool accumulateVertContribution(inout float _1105, inout float _1106, vec2 _1107, vec2 _1108, ivec2 _1109, int _1110)
{
    vec4 _1124 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1109, _1110, 0).xyz, 0);
    vec4 _1130 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_1109, 1), _1110, 0).xyz, 0);
    vec4 p12 = vec4(_1124.xy, _1124.zw) - vec4(_1107, _1107);
    vec2 p3 = _1130.xy - _1107;
    if ((max(max(p12.y, p12.w), p3.y) * _1108.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        vec2 r = solveVertPoly(p12, p3) * _1108.y;
        if ((code & 1u) != 0u)
        {
            float _1257 = r.x;
            _1105 -= clamp(_1257 + 0.5, 0.0, 1.0);
            _1106 = max(_1106, clamp(1.0 - (abs(_1257) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _1273 = r.y;
            _1105 += clamp(_1273 + 0.5, 0.0, 1.0);
            _1106 = max(_1106, clamp(1.0 - (abs(_1273) * 2.0), 0.0, 1.0));
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
    float _1353 = clamp(cov, 0.0, 1.0);
    float _1354 = max(coverage_exponent, 1.52587890625e-05);
    float _1349;
    if (abs(_1354 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1349 = _1353;
    }
    else
    {
        _1349 = pow(_1353, _1354);
    }
    return _1349;
}

float evalGlyphCoverage(vec2 _508, vec2 _509, vec2 _510, ivec2 _511, ivec2 _512, vec4 _513, int _514, float _515)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_508.y, _509.y, _513.y, _513.w, _512.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_508.x, _509.x, _513.x, _513.z, _512.x);
    float xcov = 0.0;
    float xwgt = 0.0;
    int _631 = hSpan.first;
    int _632 = hSpan.last;
    bool _633 = _631 != _632;
    int band = _631;
    int i;
    bool _521;
    for (;;)
    {
        bool _526_ladder_break = false;
        do
        {
            if (!(band <= _632))
            {
                _526_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_511, uint(band)), _514, 0).xyz, 0).xy.xy;
            ivec2 _679 = calcBandLoc(_511, hbd.y);
            int _681 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _531_ladder_break = false;
                do
                {
                    if (!(i < _681))
                    {
                        _531_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_679, uint(i)), _514, 0).xyz, 0).xy.xy;
                    if (_633)
                    {
                        _521 = !isCoverageBandSpanOwner(ref, band, _631);
                    }
                    else
                    {
                        _521 = false;
                    }
                    if (_521)
                    {
                        break;
                    }
                    bool _747 = accumulateHorizContribution(xcov, xwgt, _508, _510, decodeBandCurveLoc(ref), _514);
                    if (!_747)
                    {
                        _531_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_531_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_526_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    float ycov = 0.0;
    float ywgt = 0.0;
    int _1054 = vSpan.first;
    int _1055 = vSpan.last;
    bool _1056 = _1054 != _1055;
    band = _1054;
    for (;;)
    {
        bool _553_ladder_break = false;
        do
        {
            if (!(band <= _1055))
            {
                _553_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_511, uint((_512.y + 1) + band)), _514, 0).xyz, 0).xy.xy;
            ivec2 _1074 = calcBandLoc(_511, vbd.y);
            int _1076 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _558_ladder_break = false;
                do
                {
                    if (!(i < _1076))
                    {
                        _558_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_1074, uint(i)), _514, 0).xyz, 0).xy.xy;
                    if (_1056)
                    {
                        _521 = !isCoverageBandSpanOwner(ref_1, band, _1054);
                    }
                    else
                    {
                        _521 = false;
                    }
                    if (_521)
                    {
                        break;
                    }
                    bool _1103 = accumulateVertContribution(ycov, ywgt, _508, _510, decodeBandCurveLoc(ref_1), _514);
                    if (!_1103)
                    {
                        _558_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_558_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_553_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _515);
}

float srgbDecode(float c)
{
    float _1390;
    if (c <= 0.040449999272823333740234375)
    {
        _1390 = c / 12.9200000762939453125;
    }
    else
    {
        _1390 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _1390;
}

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

vec4 snailTextSamplePremulLinearWithFootprint(int _101, int _102, int _103, float _104, vec2 _105, vec2 _106, vec2 _107)
{
    vec4 paint = vec4(0.0);
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
            vec4 _357 = _157.xform;
            if (abs((_357.x * _357.w) - (_357.y * _357.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            vec2 rc = snailTextSampleLocalCoord(_105, _357, _157.origin);
            vec2 epp = abs(snailTextSampleLocalVector(_106, _357)) + abs(snailTextSampleLocalVector(_107, _357));
            vec2 _431 = max(epp * 2.0, vec2(0.001000000047497451305389404296875));
            float _434 = rc.x;
            vec4 _435 = _157.rect;
            float _437 = _431.x;
            if (_434 < (_435.x - _437))
            {
                _115 = true;
            }
            else
            {
                _115 = _434 > (_435.z + _437);
            }
            if (_115)
            {
                _116 = true;
            }
            else
            {
                _116 = rc.y < (_435.y - _431.y);
            }
            if (_116)
            {
                _117 = true;
            }
            else
            {
                _117 = rc.y > (_435.w + _431.y);
            }
            if (_117)
            {
                break;
            }
            uvec2 _474 = _157.glyph;
            uint gz = _474.x;
            uint gw = _474.y;
            int layer_byte = int((gw >> 24u) & 255u);
            if (layer_byte == 255)
            {
                break;
            }
            vec4 _1368 = _157.color;
            vec4 _1371 = _157.tint;
            float _1374 = clamp((evalGlyphCoverage(rc, epp, vec2(1.0 / max(epp.x, 1.52587890625e-05), 1.0 / max(epp.y, 1.52587890625e-05)), ivec2(int(gz & 65535u), int(gz >> 16u)), ivec2(int((gw >> 16u) & 255u), int(gw & 65535u)), _157.banding, _103 + layer_byte, _104) * _1368.w) * _1371.w, 0.0, 1.0);
            if (_1374 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            vec4 _1421 = paint;
            float _1423 = 1.0 - _1374;
            vec3 _1425 = ((srgbToLinear(_1368.xyz) * srgbToLinear(_1371.xyz)) * _1374) + (_1421.xyz * _1423);
            paint.x = _1425.x;
            paint.y = _1425.y;
            paint.z = _1425.z;
            paint.w = _1374 + (paint.w * _1423);
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

vec4 snailGameTextSample(vec2 scene_pos, vec2 scene_dx, vec2 scene_dy)
{
    return snailTextSamplePremulLinearWithFootprint(23, pc.glyph_count, 0, 1.0, scene_pos, scene_dx, scene_dy);
}

float snailGameHeight(vec2 uv)
{
    vec2 p = uv * 6.283185482025146484375;
    return (((0.5 * sin(dot(p, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(p, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(p, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(p, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375));
}

vec3 snailGameMaterial(vec2 uv, vec2 scene_pos, vec2 scene_dx, vec2 scene_dy, vec3 light_dir, vec4 base, float relief, float roughness)
{
    vec2 _84 = max((abs(scene_dx) + abs(scene_dy)) * 1.25, vec2(1.52587890625e-05));
    vec2 _1452 = vec2(_84.x, 0.0);
    vec2 _1460 = vec2(0.0, _84.y);
    float h0 = snailGameHeight(uv);
    vec3 _1531 = normalize(vec3(-((vec2(snailGameHeight(uv + vec2(0.0009765625, 0.0)) - h0, snailGameHeight(uv + vec2(0.0, 0.0009765625)) - h0) * (roughness / 0.0009765625)) + (vec2(snailGameTextSample(scene_pos + _1452, scene_dx, scene_dy).w - snailGameTextSample(scene_pos - _1452, scene_dx, scene_dy).w, snailGameTextSample(scene_pos + _1460, scene_dx, scene_dy).w - snailGameTextSample(scene_pos - _1460, scene_dx, scene_dy).w) * (0.5 * relief))), 1.0));
    vec3 _1532 = normalize(light_dir);
    float _1542 = clamp(snailGameTextSample(scene_pos, scene_dx, scene_dy).w, 0.0, 1.0);
    return ((mix(base.xyz, vec3(0.23999999463558197021484375, 0.300000011920928955078125, 0.4000000059604644775390625), vec3(_1542)) * (0.20000000298023223876953125 + ((0.7799999713897705078125 + (0.2199999988079071044921875 * _1542)) * max(dot(_1531, _1532), 0.0)))) * (0.939999997615814208984375 + (0.0599999986588954925537109375 * h0))) + ((vec3(0.800000011920928955078125, 0.87999999523162841796875, 1.0) * pow(max(dot(_1531, normalize(_1532 + vec3(0.0, 0.0, 1.0))), 0.0), 40.0)) * (0.119999997317790985107421875 + (0.2800000011920928955078125 * _1542)));
}

vec3 snailGameEncodeSrgb(vec3 c)
{
    vec3 _1581 = clamp(c, vec3(0.0), vec3(1.0));
    return mix((pow(_1581, vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), _1581 * 12.9200000762939453125, step(_1581, vec3(0.003130800090730190277099609375)));
}

void main()
{
    vec2 scene_pos = vec2(snail_io0.x * pc.scene_size.x, (1.0 - snail_io0.y) * pc.scene_size.y);
    vec3 lin = snailGameMaterial(snail_io0, scene_pos, ddx(scene_pos), ddy(scene_pos), pc.light_dir.xyz, pc.base_color, pc.relief, pc.roughness);
    vec3 outc;
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

