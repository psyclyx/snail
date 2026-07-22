#version 330

struct TtHintedVaryings
{
    vec4 color;
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

uvec4 _355;
uvec4 _373;
uvec4 _753;
uvec4 _771;

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

in vec4 snail_io0;
in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

vec2 _fwidth(vec2 x)
{
    return fwidth(x);
}

ivec2 offsetTtHintedInfoLoc(ivec2 _133, int _134)
{
    uvec2 vecSize = uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0));
    uint uw = vecSize.x;
    uint uh = vecSize.y;
    int width = int(uw);
    int texel = ((_133.y * width) + _133.x) + _134;
    return ivec2(texel - width * (texel / width), texel / width);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _293;
    _293.first = first;
    _293.last = last;
    return _293;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _277 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _281 = clamp(int(center - _277), 0, bandMax);
    return CoverageBandSpan_init(_281, max(_281, clamp(int(center + _277), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _329 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_329, glyphLoc.y);
    loc.y += (_329 >> 12);
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
    int _459 = base.x + offset;
    ivec2 loc = ivec2(_459, base.y);
    loc.y += (_459 >> 12);
    loc.x &= 4095;
    return loc;
}

float rootCodeCoord(float v)
{
    float _512;
    if (abs(v) <= 1.52587890625e-05)
    {
        _512 = 0.0;
    }
    else
    {
        _512 = v;
    }
    return _512;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _614;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _614 = 0.0;
    }
    else
    {
        _614 = sqrt(disc);
    }
    return _614;
}

vec2 solveHorizPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _584 = a.y;
    float t1;
    float t2;
    if (abs(_584) < 1.52587890625e-05)
    {
        float _588 = b.y;
        if (abs(_588) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _588;
        }
        t2 = t1;
    }
    else
    {
        float _602 = b.y;
        float _605 = _584 * p12.y;
        float sq = snapNearTangentSqrt((_602 * _602) - _605, _602, _605);
        if (_602 >= 0.0)
        {
            float q = _602 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _584;
        }
        else
        {
            float q_1 = _602 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            float _656 = t1;
            t1 = q_1 / _584;
            t2 = _656;
        }
    }
    float _661 = a.x;
    float _665 = b.x * 2.0;
    return vec2((((_661 * t1) - _665) * t1) + p12.x, (((_661 * t2) - _665) * t2) + p12.x);
}

bool accumulateHorizContribution(inout float _429, inout float _430, vec2 _431, vec2 _432, ivec2 _433, int _434)
{
    vec4 _451 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_433, _434, 0).xyz, 0);
    vec4 _478 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_433, 1), _434, 0).xyz, 0);
    vec4 p12 = vec4(_451.xy, _451.zw) - vec4(_431, _431);
    vec2 p3 = _478.xy - _431;
    if ((max(max(p12.x, p12.z), p3.x) * _432.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        vec2 r = solveHorizPoly(p12, p3) * _432.x;
        if ((code & 1u) != 0u)
        {
            float _684 = r.x;
            _429 += clamp(_684 + 0.5, 0.0, 1.0);
            _430 = max(_430, clamp(1.0 - (abs(_684) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _700 = r.y;
            _429 -= clamp(_700 + 0.5, 0.0, 1.0);
            _430 = max(_430, clamp(1.0 - (abs(_700) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveVertPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _864 = a.x;
    float t1;
    float t2;
    if (abs(_864) < 1.52587890625e-05)
    {
        float _868 = b.x;
        if (abs(_868) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _868;
        }
        t2 = t1;
    }
    else
    {
        float _882 = b.x;
        float _885 = _864 * p12.x;
        float sq = snapNearTangentSqrt((_882 * _882) - _885, _882, _885);
        if (_882 >= 0.0)
        {
            float q = _882 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _864;
        }
        else
        {
            float q_1 = _882 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            float _912 = t1;
            t1 = q_1 / _864;
            t2 = _912;
        }
    }
    float _917 = a.y;
    float _921 = b.y * 2.0;
    return vec2((((_917 * t1) - _921) * t1) + p12.y, (((_917 * t2) - _921) * t2) + p12.y);
}

bool accumulateVertContribution(inout float _787, inout float _788, vec2 _789, vec2 _790, ivec2 _791, int _792)
{
    vec4 _806 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_791, _792, 0).xyz, 0);
    vec4 _812 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_791, 1), _792, 0).xyz, 0);
    vec4 p12 = vec4(_806.xy, _806.zw) - vec4(_789, _789);
    vec2 p3 = _812.xy - _789;
    if ((max(max(p12.y, p12.w), p3.y) * _790.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        vec2 r = solveVertPoly(p12, p3) * _790.y;
        if ((code & 1u) != 0u)
        {
            float _939 = r.x;
            _787 -= clamp(_939 + 0.5, 0.0, 1.0);
            _788 = max(_788, clamp(1.0 - (abs(_939) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _955 = r.y;
            _787 += clamp(_955 + 0.5, 0.0, 1.0);
            _788 = max(_788, clamp(1.0 - (abs(_955) * 2.0), 0.0, 1.0));
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
    float _1035 = clamp(cov, 0.0, 1.0);
    float _1036 = max(coverage_exponent, 1.52587890625e-05);
    float _1031;
    if (abs(_1036 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _1031 = _1035;
    }
    else
    {
        _1031 = pow(_1035, _1036);
    }
    return _1031;
}

float evalGlyphCoverage(vec2 _183, vec2 _184, vec2 _185, ivec2 _186, ivec2 _187, vec4 _188, int _189, float _190)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_183.y, _184.y, _188.y, _188.w, _187.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_183.x, _184.x, _188.x, _188.z, _187.x);
    float xcov = 0.0;
    float xwgt = 0.0;
    int _310 = hSpan.first;
    int _311 = hSpan.last;
    bool _312 = _310 != _311;
    int band = _310;
    int i;
    bool _199;
    for (;;)
    {
        bool _204_ladder_break = false;
        do
        {
            if (!(band <= _311))
            {
                _204_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_186, uint(band)), _189, 0).xyz, 0).xy.xy;
            ivec2 _358 = calcBandLoc(_186, hbd.y);
            int _360 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _209_ladder_break = false;
                do
                {
                    if (!(i < _360))
                    {
                        _209_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_358, uint(i)), _189, 0).xyz, 0).xy.xy;
                    if (_312)
                    {
                        _199 = !isCoverageBandSpanOwner(ref, band, _310);
                    }
                    else
                    {
                        _199 = false;
                    }
                    if (_199)
                    {
                        break;
                    }
                    bool _426 = accumulateHorizContribution(xcov, xwgt, _183, _185, decodeBandCurveLoc(ref), _189);
                    if (!_426)
                    {
                        _209_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_209_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_204_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    float ycov = 0.0;
    float ywgt = 0.0;
    int _736 = vSpan.first;
    int _737 = vSpan.last;
    bool _738 = _736 != _737;
    band = _736;
    for (;;)
    {
        bool _231_ladder_break = false;
        do
        {
            if (!(band <= _737))
            {
                _231_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_186, uint((_187.y + 1) + band)), _189, 0).xyz, 0).xy.xy;
            ivec2 _756 = calcBandLoc(_186, vbd.y);
            int _758 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _236_ladder_break = false;
                do
                {
                    if (!(i < _758))
                    {
                        _236_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_756, uint(i)), _189, 0).xyz, 0).xy.xy;
                    if (_738)
                    {
                        _199 = !isCoverageBandSpanOwner(ref_1, band, _736);
                    }
                    else
                    {
                        _199 = false;
                    }
                    if (_199)
                    {
                        break;
                    }
                    bool _785 = accumulateVertContribution(ycov, ywgt, _183, _185, decodeBandCurveLoc(ref_1), _189);
                    if (!_785)
                    {
                        _236_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_236_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_231_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _190);
}

vec4 premultiplyColor(vec4 color, float cov)
{
    float alpha = color.w * cov;
    return vec4(color.xyz * alpha, alpha);
}

float srgbEncode(float c)
{
    float _1106;
    if (c <= 0.003130800090730190277099609375)
    {
        _1106 = c * 12.9200000762939453125;
    }
    else
    {
        _1106 = (1.05499994754791259765625 * pow(c, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    return _1106;
}

vec3 linearToSrgb(vec3 color)
{
    return vec3(srgbEncode(max(color.x, 0.0)), srgbEncode(max(color.y, 0.0)), srgbEncode(max(color.z, 0.0)));
}

vec4 srgbEncodePremultiplied(vec4 premul)
{
    if (premul.w <= 0.0)
    {
        return vec4(0.0);
    }
    return vec4(linearToSrgb(premul.xyz * (1.0 / premul.w)) * premul.w, premul.w);
}

vec4 snailTtHintedTextFragment(TtHintedVaryings _66, int _67, int _68, float _69, int _70)
{
    if (((_66.glyph.w >> 8) & 255) != 255)
    {
        discard;
    }
    if ((_66.glyph.w & 255) != 2)
    {
        discard;
    }
    vec2 epp = _fwidth(_66.texcoord);
    vec4 _129 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_66.glyph.xy, 0).xy, 0);
    vec4 _161 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(offsetTtHintedInfoLoc(_66.glyph.xy, 1), 0).xy, 0);
    int _163 = floatBitsToInt(_129.z);
    float _180 = evalGlyphCoverage(_66.texcoord, epp, vec2(1.0 / max(epp.x, 1.52587890625e-05), 1.0 / max(epp.y, 1.52587890625e-05)), ivec2(int(_129.x), int(_129.y)), ivec2((_163 >> 16) & 65535, _163 & 65535), _161, _67 + int(_66.banding.w), _69);
    if (_180 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    vec4 premul = premultiplyColor(_66.color * _66.tint, _180);
    vec4 _72;
    if (_70 != 0)
    {
        _72 = vec4(premul.w);
    }
    else
    {
        if (_68 != 0)
        {
            _72 = srgbEncodePremultiplied(premul);
        }
        else
        {
            _72 = premul;
        }
    }
    return _72;
}

void main()
{
    TtHintedVaryings v;
    v.color = snail_io0;
    v.tint = snail_io4;
    v.texcoord = snail_io1;
    v.banding = snail_io2;
    v.glyph = snail_io3;
    TtHintedVaryings _13 = v;
    vec4 _63 = snailTtHintedTextFragment(_13, pc.layer_base, pc.output_srgb, pc.coverage_exponent, pc.mask_output);
    entryPointParam_fragmentMain = _63;
}

