#version 330

struct AutohintVaryings
{
    vec4 paint;
    vec3 texcoord_layer;
    ivec2 info;
    uvec4 policy0;
    uvec3 policy1;
    vec4 x_targets[4];
    vec4 y_targets[4];
    uvec4 x_sources;
    uvec4 y_sources;
};

struct SnailAutohintPolicy
{
    int xAlign;
    int xStem;
    int xPositioning;
    int xRegistration;
    int yAlign;
    int yStem;
    int yOvershoot;
    int fadeEnabled;
    float fadeStart;
    float fadeFull;
    float xRatio;
    float xMaxPx;
    float yRatio;
    float yMaxPx;
    float overshootMinPx;
};

struct CoverageBandSpan
{
    int first;
    int last;
};

uvec4 _3864;
uvec4 _3882;
uvec4 _4255;
uvec4 _4273;

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
in vec3 snail_io1;
flat in ivec2 snail_io2;
flat in uvec4 snail_io3;
flat in uvec3 snail_io4;
flat in vec4 snail_io5;
flat in vec4 snail_io6;
flat in vec4 snail_io7;
flat in vec4 snail_io8;
flat in vec4 snail_io9;
flat in vec4 snail_io10;
flat in vec4 snail_io11;
flat in vec4 snail_io12;
flat in uvec4 snail_io13;
flat in uvec4 snail_io14;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

ivec2 snailAhLayerLoc(ivec2 _237, int _238)
{
    uvec2 vecSize = uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0));
    uint uw = vecSize.x;
    uint uh = vecSize.y;
    int width = int(uw);
    int texel = ((_237.y * width) + _237.x) + _238;
    return ivec2(texel - width * (texel / width), texel / width);
}

vec2 _fwidth(vec2 x)
{
    return fwidth(x);
}

float snailWarpF(ivec2 _305, int _306, int _307)
{
    int f = _306 + _307;
    vec4 _326 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(snailAhLayerLoc(_305, f >> 2), 0).xy, 0);
    int c = f & 3;
    float _309;
    if (c == 0)
    {
        _309 = _326.x;
    }
    else
    {
        if (c == 1)
        {
            _309 = _326.y;
        }
        else
        {
            if (c == 2)
            {
                _309 = _326.z;
            }
            else
            {
                _309 = _326.w;
            }
        }
    }
    return _309;
}

bool snailAhFinite(float v)
{
    bool _375;
    if (!isnan(v))
    {
        _375 = !isinf(v);
    }
    else
    {
        _375 = false;
    }
    return _375;
}

bool snailAhCount(int max_knots, float encoded, out int count)
{
    bool _358;
    if (!snailAhFinite(encoded))
    {
        _358 = true;
    }
    else
    {
        _358 = encoded < 0.0;
    }
    if (_358)
    {
        _358 = true;
    }
    else
    {
        _358 = encoded > float(max_knots);
    }
    if (_358)
    {
        _358 = true;
    }
    else
    {
        _358 = floor(encoded) != encoded;
    }
    if (_358)
    {
        count = 0;
        return false;
    }
    count = int(encoded);
    return true;
}

uint snailAhFastSource(uvec4 words, int idx)
{
    uvec4 _478 = words;
    return (_478[idx >> 2] >> uint((idx & 3) * 8)) & 255u;
}

int snailAhFastCount(uvec4 words)
{
    if (snailAhFastSource(words, 0) == 254u)
    {
        return -1;
    }
    int i = 0;
    int count = 0;
    for (;;)
    {
        int count_1;
        bool _462_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _462_ladder_break = true;
                break;
            }
            if (snailAhFastSource(words, i) == 255u)
            {
                _462_ladder_break = true;
                break;
            }
            count_1 = count + 1;
            break;
        } while(false);
        if (_462_ladder_break)
        {
            break;
        }
        i++;
        count = count_1;
        continue;
    }
    return count;
}

bool snailDecodeAutohintPolicy(uvec4 p0, uvec3 p1, inout SnailAutohintPolicy p)
{
    p = SnailAutohintPolicy(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    bool _566;
    if ((p0.x & 4286578688u) != 0u)
    {
        _566 = true;
    }
    else
    {
        _566 = (p0.y & 4294967232u) != 0u;
    }
    if (_566)
    {
        return false;
    }
    int _670 = int(p0.x & 3u);
    p.xAlign = _670;
    p.xStem = int((p0.x >> 2u) & 3u);
    p.xPositioning = int((p0.x >> 4u) & 3u);
    p.xRegistration = int((p0.x >> 6u) & 3u);
    p.fadeEnabled = int((p0.x >> 8u) & 1u);
    p.fadeStart = float((p0.x >> 9u) & 127u);
    p.fadeFull = float((p0.x >> 16u) & 127u);
    p.yAlign = int(p0.y & 3u);
    p.yStem = int((p0.y >> 2u) & 3u);
    p.yOvershoot = int((p0.y >> 4u) & 3u);
    if (_670 > 1)
    {
        _566 = true;
    }
    else
    {
        _566 = p.xStem > 2;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        _566 = p.xPositioning > 1;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        _566 = p.xRegistration > 1;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        _566 = p.yAlign > 2;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        _566 = p.yStem > 2;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        _566 = p.yOvershoot > 1;
    }
    if (_566)
    {
        return false;
    }
    p.xRatio = uintBitsToFloat(p0.z);
    p.xMaxPx = uintBitsToFloat(p0.w);
    p.yRatio = uintBitsToFloat(p1.x);
    p.yMaxPx = uintBitsToFloat(p1.y);
    p.overshootMinPx = uintBitsToFloat(p1.z);
    if (p.xStem != 0)
    {
        if (!snailAhFinite(p.xRatio))
        {
            _566 = true;
        }
        else
        {
            _566 = p.xRatio < 0.0;
        }
    }
    else
    {
        _566 = false;
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.xStem == 1)
        {
            if (!snailAhFinite(p.xMaxPx))
            {
                _566 = true;
            }
            else
            {
                _566 = p.xMaxPx < 0.0;
            }
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.yStem != 0)
        {
            if (!snailAhFinite(p.yRatio))
            {
                _566 = true;
            }
            else
            {
                _566 = p.yRatio < 0.0;
            }
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.yStem == 1)
        {
            if (!snailAhFinite(p.yMaxPx))
            {
                _566 = true;
            }
            else
            {
                _566 = p.yMaxPx < 0.0;
            }
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.yOvershoot == 1)
        {
            if (!snailAhFinite(p.overshootMinPx))
            {
                _566 = true;
            }
            else
            {
                _566 = p.overshootMinPx < 0.0;
            }
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.xPositioning == 1)
        {
            _566 = p.xAlign == 0;
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        _566 = true;
    }
    else
    {
        if (p.yOvershoot == 1)
        {
            _566 = p.yAlign != 2;
        }
        else
        {
            _566 = false;
        }
    }
    if (_566)
    {
        return false;
    }
    return true;
}

float snailAhSnap(float v, float scale)
{
    return round(v * scale) / scale;
}

float snailAhStandardWidth(float raw, float standard, float ratio)
{
    bool _2447;
    if (standard > 0.0)
    {
        _2447 = abs(raw - standard) <= (ratio * standard);
    }
    else
    {
        _2447 = false;
    }
    float _2448;
    if (_2447)
    {
        _2448 = standard;
    }
    else
    {
        _2448 = raw;
    }
    return _2448;
}

bool snailFitAutohintAxis(ivec2 _972, int _973, int _974, int _975, float _976, float _977, float _978, SnailAutohintPolicy _979, inout int _980, inout float _981[32], inout float _982[32], inout int _983[32])
{
    _980 = 0;
    int i = 0;
    for (;;)
    {
        bool _1035_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1035_ladder_break = true;
                break;
            }
            _981[i] = 0.0;
            _982[i] = 0.0;
            _983[i] = 0;
            break;
        } while(false);
        if (_1035_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    bool _986;
    if (!snailAhFinite(_978))
    {
        _986 = true;
    }
    else
    {
        _986 = _978 <= 0.0;
    }
    if (_986)
    {
        _986 = true;
    }
    else
    {
        _986 = _975 < 0;
    }
    if (_986)
    {
        _986 = true;
    }
    else
    {
        _986 = _975 > 32;
    }
    if (_986)
    {
        _986 = true;
    }
    else
    {
        _986 = !snailAhFinite(_976);
    }
    if (_986)
    {
        _986 = true;
    }
    else
    {
        _986 = _976 < 0.0;
    }
    if (_986)
    {
        return false;
    }
    bool _1663 = _973 == 0;
    if (_1663)
    {
        _986 = _979.xAlign == 0;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _979.xStem == 0;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _979.xPositioning == 0;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _979.xRegistration == 0;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = true;
    }
    else
    {
        if (_973 == 1)
        {
            _986 = _979.yAlign == 0;
        }
        else
        {
            _986 = false;
        }
        if (_986)
        {
            _986 = _979.yStem == 0;
        }
        else
        {
            _986 = false;
        }
        if (_986)
        {
            _986 = _979.yOvershoot == 0;
        }
        else
        {
            _986 = false;
        }
    }
    if (_986)
    {
        return true;
    }
    int n = int(snailWarpF(_972, _974, 0));
    if (n <= 0)
    {
        _986 = true;
    }
    else
    {
        _986 = n > 32;
    }
    if (_986)
    {
        return n == 0;
    }
    bool _1747 = _973 == 1;
    if (_1747)
    {
        _986 = _979.yAlign == 2;
    }
    else
    {
        _986 = false;
    }
    bool partnerAbove;
    if (_1663)
    {
        partnerAbove = _979.xRegistration == 1;
    }
    else
    {
        partnerAbove = false;
    }
    if (partnerAbove)
    {
        partnerAbove = !snailAhFinite(_977);
    }
    else
    {
        partnerAbove = false;
    }
    if (partnerAbove)
    {
        return false;
    }
    i = 0;
    float pos[32];
    float width[32];
    int stem[32];
    int blue[32];
    bool rounded[32];
    bool syntheticApex[32];
    bool semanticsResolved[32];
    bool blueDirNegative[32];
    int gridCompanion[32];
    int blueCompanion[32];
    bool hinted[32];
    bool validBlue;
    bool bottomBlue;
    bool _1008;
    bool axisAligned;
    bool lowerBlue;
    for (;;)
    {
        bool _1104_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1104_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1104_ladder_break = true;
                break;
            }
            int f = (_974 + 1) + (4 * i);
            pos[i] = snailWarpF(_972, f, 0);
            width[i] = snailWarpF(_972, f, 1);
            uint _1796 = floatBitsToUint(snailWarpF(_972, f, 2));
            stem[i] = int(_1796 << 16u) >> 16;
            blue[i] = int(_1796) >> 16;
            uint _1809 = floatBitsToUint(snailWarpF(_972, f, 3));
            rounded[i] = (_1809 & 1u) != 0u;
            syntheticApex[i] = (_1809 & 2u) != 0u;
            semanticsResolved[i] = (_1809 & 4u) != 0u;
            blueDirNegative[i] = (_1809 & 8u) != 0u;
            gridCompanion[i] = int((_1809 >> 4u) & 63u);
            blueCompanion[i] = int((_1809 >> 10u) & 63u);
            hinted[i] = false;
            if (!snailAhFinite(pos[i]))
            {
                partnerAbove = true;
            }
            else
            {
                partnerAbove = !snailAhFinite(width[i]);
            }
            if (partnerAbove)
            {
                validBlue = true;
            }
            else
            {
                validBlue = width[i] < 0.0;
            }
            if (validBlue)
            {
                bottomBlue = true;
            }
            else
            {
                bottomBlue = stem[i] < (-1);
            }
            if (bottomBlue)
            {
                _1008 = true;
            }
            else
            {
                _1008 = stem[i] >= n;
            }
            if (_1008)
            {
                axisAligned = true;
            }
            else
            {
                axisAligned = blue[i] < (-1);
            }
            if (axisAligned)
            {
                lowerBlue = true;
            }
            else
            {
                lowerBlue = blue[i] >= _975;
            }
            if (lowerBlue)
            {
                return false;
            }
            break;
        } while(false);
        if (_1104_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    i = 0;
    for (;;)
    {
        bool _1137_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1137_ladder_break = true;
                break;
            }
            if (i >= _975)
            {
                _1137_ladder_break = true;
                break;
            }
            int _1918 = 2 * i;
            if (!snailAhFinite(snailWarpF(_972, 12, _1918)))
            {
                partnerAbove = true;
            }
            else
            {
                partnerAbove = !snailAhFinite(snailWarpF(_972, 12, _1918 + 1));
            }
            if (partnerAbove)
            {
                return false;
            }
            break;
        } while(false);
        if (_1137_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    i = 0;
    for (;;)
    {
        bool _1155_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1155_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1155_ladder_break = true;
                break;
            }
            if (stem[i] >= 0)
            {
                if (stem[i] >= n)
                {
                    partnerAbove = true;
                }
                else
                {
                    partnerAbove = stem[i] == i;
                }
                if (partnerAbove)
                {
                    validBlue = true;
                }
                else
                {
                    validBlue = stem[stem[i]] != i;
                }
                if (validBlue)
                {
                    bottomBlue = true;
                }
                else
                {
                    bottomBlue = !snailAhFinite(pos[stem[i]]);
                }
                if (bottomBlue)
                {
                    _1008 = true;
                }
                else
                {
                    _1008 = pos[stem[i]] == pos[i];
                }
                if (_1008)
                {
                    axisAligned = true;
                }
                else
                {
                    axisAligned = !snailAhFinite(width[stem[i]]);
                }
                if (axisAligned)
                {
                    lowerBlue = true;
                }
                else
                {
                    lowerBlue = width[stem[i]] != width[i];
                }
                if (lowerBlue)
                {
                    return false;
                }
            }
            break;
        } while(false);
        if (_1155_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_1747)
    {
        partnerAbove = _979.yOvershoot == 1;
    }
    else
    {
        partnerAbove = false;
    }
    float spacing;
    if (partnerAbove)
    {
        spacing = _979.overshootMinPx;
    }
    else
    {
        spacing = 0.0;
    }
    i = 0;
    int companion[32];
    int dir[32];
    float targets[32];
    int companionDir;
    int k;
    int encodedCompanion;
    int clusterRight;
    bool upperBlue;
    bool _1017;
    bool _1018;
    float nearest;
    bool _1020;
    for (;;)
    {
        bool _1196_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1196_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1196_ladder_break = true;
                break;
            }
            if (stem[i] >= 0)
            {
                partnerAbove = pos[stem[i]] > pos[i];
            }
            else
            {
                partnerAbove = false;
            }
            if (_986)
            {
                validBlue = blue[i] >= 0;
            }
            else
            {
                validBlue = false;
            }
            if (validBlue)
            {
                bottomBlue = snailWarpF(_972, 12, (2 * blue[i]) + 1) < snailWarpF(_972, 12, 2 * blue[i]);
            }
            else
            {
                bottomBlue = false;
            }
            if (!semanticsResolved[i])
            {
                _1008 = stem[i] < 0;
            }
            else
            {
                _1008 = false;
            }
            if (_1008)
            {
                axisAligned = !validBlue;
            }
            else
            {
                axisAligned = false;
            }
            if (axisAligned)
            {
                lowerBlue = _986;
            }
            else
            {
                lowerBlue = false;
            }
            if (lowerBlue)
            {
                nearest = 3.4028234663852885981170418348452e+38;
                companionDir = 1;
                k = 0;
                for (;;)
                {
                    bool _1223_ladder_break = false;
                    do
                    {
                        if (!(k < 32))
                        {
                            _1223_ladder_break = true;
                            break;
                        }
                        if (k >= n)
                        {
                            _1223_ladder_break = true;
                            break;
                        }
                        if (blue[k] < 0)
                        {
                            break;
                        }
                        float _2149 = abs(pos[k] - pos[i]);
                        if (_2149 >= nearest)
                        {
                            break;
                        }
                        if (snailWarpF(_972, 12, (2 * blue[k]) + 1) < snailWarpF(_972, 12, 2 * blue[k]))
                        {
                            encodedCompanion = 1;
                        }
                        else
                        {
                            encodedCompanion = -1;
                        }
                        nearest = _2149;
                        companionDir = encodedCompanion;
                        break;
                    } while(false);
                    if (_1223_ladder_break)
                    {
                        break;
                    }
                    k++;
                    continue;
                }
            }
            else
            {
                companionDir = 1;
            }
            if (semanticsResolved[i])
            {
                if (_986)
                {
                    upperBlue = blueDirNegative[i];
                }
                else
                {
                    upperBlue = false;
                }
                if (upperBlue)
                {
                    _1017 = true;
                }
                else
                {
                    if (!_986)
                    {
                        _1017 = partnerAbove;
                    }
                    else
                    {
                        _1017 = false;
                    }
                }
                if (_1017)
                {
                    k = -1;
                }
                else
                {
                    k = 1;
                }
            }
            else
            {
                if (partnerAbove)
                {
                    upperBlue = true;
                }
                else
                {
                    upperBlue = bottomBlue;
                }
                if (upperBlue)
                {
                    k = -1;
                }
                else
                {
                    k = companionDir;
                }
            }
            dir[i] = k;
            if (_986)
            {
                encodedCompanion = blueCompanion[i];
            }
            else
            {
                encodedCompanion = gridCompanion[i];
            }
            if (!semanticsResolved[i])
            {
                upperBlue = true;
            }
            else
            {
                upperBlue = encodedCompanion == 63;
            }
            if (upperBlue)
            {
                clusterRight = -2;
            }
            else
            {
                if (encodedCompanion == 62)
                {
                    clusterRight = -1;
                }
                else
                {
                    clusterRight = encodedCompanion;
                }
            }
            companion[i] = clusterRight;
            if (validBlue)
            {
                float _2278 = snailWarpF(_972, 12, 2 * blue[i]);
                float _2282 = snailWarpF(_972, 12, (2 * blue[i]) + 1);
                if (rounded[i])
                {
                    _1017 = _1747;
                }
                else
                {
                    _1017 = false;
                }
                if (_1017)
                {
                    _1018 = _979.yOvershoot == 0;
                }
                else
                {
                    _1018 = false;
                }
                if (_1018)
                {
                    targets[i] = pos[i];
                }
                else
                {
                    targets[i] = snailAhSnap(_2278, _978);
                    if (rounded[i])
                    {
                        _1020 = abs((_2282 - _2278) * _978) >= spacing;
                    }
                    else
                    {
                        _1020 = false;
                    }
                    if (_1020)
                    {
                        targets[i] += (_2282 - _2278);
                    }
                }
            }
            else
            {
                targets[i] = snailAhSnap(pos[i], _978);
            }
            break;
        } while(false);
        if (_1196_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    float grid = 1.0 / _978;
    if (_1663)
    {
        companionDir = _979.xStem;
    }
    else
    {
        companionDir = _979.yStem;
    }
    if (_1663)
    {
        spacing = _979.xRatio;
    }
    else
    {
        spacing = _979.yRatio;
    }
    if (_1663)
    {
        nearest = _979.xMaxPx;
    }
    else
    {
        nearest = _979.yMaxPx;
    }
    if (_1663)
    {
        _986 = _979.xAlign == 1;
    }
    else
    {
        _986 = _979.yAlign != 0;
    }
    if (_1663)
    {
        partnerAbove = _979.xPositioning == 1;
    }
    else
    {
        partnerAbove = false;
    }
    validBlue = false;
    float anchorTarget = 0.0;
    float anchorBase = 0.0;
    float clusterTarget = 0.0;
    float clusterBase = 0.0;
    float clusterDesiredRight = 0.0;
    k = 0;
    i = 0;
    encodedCompanion = 0;
    int clusterStems;
    float widthUnits;
    float clusterTarget_1;
    float clusterBase_1;
    float clusterTarget_2;
    float clusterBase_2;
    float clusterDesiredRight_1;
    for (;;)
    {
        bool _1315_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1315_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1315_ladder_break = true;
                break;
            }
            if (stem[i] < 0)
            {
                bottomBlue = true;
            }
            else
            {
                bottomBlue = stem[i] <= i;
            }
            if (bottomBlue)
            {
                axisAligned = validBlue;
                break;
            }
            float nominal = snailAhStandardWidth(width[i], _976, spacing);
            if (companionDir == 2)
            {
                _1008 = true;
            }
            else
            {
                if (companionDir == 1)
                {
                    _1008 = (nominal * _978) < nearest;
                }
                else
                {
                    _1008 = false;
                }
            }
            if (_1008)
            {
                widthUnits = max(round(nominal * _978), 1.0) * grid;
            }
            else
            {
                widthUnits = width[i];
            }
            if (partnerAbove)
            {
                if (validBlue)
                {
                    targets[i] = anchorTarget + (round((pos[i] - anchorBase) * _978) * grid);
                    clusterTarget_1 = clusterTarget;
                    clusterBase_1 = clusterBase;
                    axisAligned = validBlue;
                }
                else
                {
                    float _2529 = snailAhSnap(pos[i], _978);
                    targets[i] = _2529;
                    clusterTarget_1 = _2529;
                    clusterBase_1 = pos[i];
                    axisAligned = true;
                }
                targets[stem[i]] = targets[i] + widthUnits;
                float _2548 = clusterBase_1;
                float _2553 = clusterTarget_1;
                float _2559 = clusterTarget_1;
                float _2560 = clusterBase_1;
                clusterTarget_1 = targets[i];
                clusterBase_1 = pos[i];
                clusterTarget_2 = _2559;
                clusterBase_2 = _2560;
                clusterDesiredRight_1 = (_2553 + (round((pos[i] - _2548) * _978) * grid)) + widthUnits;
                clusterRight = stem[i];
                clusterStems = encodedCompanion + 1;
            }
            else
            {
                if (_1663)
                {
                    axisAligned = _979.xAlign != 0;
                }
                else
                {
                    axisAligned = _979.yAlign != 0;
                }
                if (axisAligned)
                {
                    lowerBlue = blue[i] >= 0;
                }
                else
                {
                    lowerBlue = false;
                }
                if (axisAligned)
                {
                    upperBlue = blue[stem[i]] >= 0;
                }
                else
                {
                    upperBlue = false;
                }
                if (!_986)
                {
                    targets[i] = pos[i];
                }
                if (upperBlue)
                {
                    _1017 = !lowerBlue;
                }
                else
                {
                    _1017 = false;
                }
                if (_1017)
                {
                    _1018 = _986;
                }
                else
                {
                    _1018 = false;
                }
                if (_1018)
                {
                    targets[i] = targets[stem[i]] - widthUnits;
                }
                else
                {
                    targets[stem[i]] = targets[i] + widthUnits;
                }
                axisAligned = validBlue;
                clusterTarget_1 = anchorTarget;
                clusterBase_1 = anchorBase;
                clusterTarget_2 = clusterTarget;
                clusterBase_2 = clusterBase;
                clusterDesiredRight_1 = clusterDesiredRight;
                clusterRight = k;
                clusterStems = encodedCompanion;
            }
            hinted[i] = true;
            hinted[stem[i]] = true;
            anchorTarget = clusterTarget_1;
            anchorBase = clusterBase_1;
            clusterTarget = clusterTarget_2;
            clusterBase = clusterBase_2;
            clusterDesiredRight = clusterDesiredRight_1;
            k = clusterRight;
            encodedCompanion = clusterStems;
            break;
        } while(false);
        if (_1315_ladder_break)
        {
            break;
        }
        validBlue = axisAligned;
        i++;
        continue;
    }
    if (partnerAbove)
    {
        _986 = encodedCompanion > 1;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        float _2701 = clusterDesiredRight - targets[k];
        i = 0;
        for (;;)
        {
            bool _1371_ladder_break = false;
            do
            {
                if (!(i < 32))
                {
                    _1371_ladder_break = true;
                    break;
                }
                if (i >= n)
                {
                    _1371_ladder_break = true;
                    break;
                }
                if (hinted[i])
                {
                    targets[i] += _2701;
                }
                break;
            } while(false);
            if (_1371_ladder_break)
            {
                break;
            }
            i++;
            continue;
        }
    }
    if (companionDir == 1)
    {
        spacing = nearest;
    }
    else
    {
        spacing = 1.60000002384185791015625;
    }
    i = 0;
    for (;;)
    {
        bool _1389_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1389_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1389_ladder_break = true;
                break;
            }
            if (_1663)
            {
                axisAligned = _979.xAlign != 0;
            }
            else
            {
                axisAligned = _979.yAlign != 0;
            }
            if (!axisAligned)
            {
                _986 = true;
            }
            else
            {
                _986 = blue[i] < 0;
            }
            if (_986)
            {
                partnerAbove = true;
            }
            else
            {
                partnerAbove = !rounded[i];
            }
            if (partnerAbove)
            {
                validBlue = true;
            }
            else
            {
                validBlue = hinted[i];
            }
            if (validBlue)
            {
                break;
            }
            bool top = dir[i] > 0;
            if (companion[i] >= 0)
            {
                if (top)
                {
                    nearest = pos[i] - pos[companion[i]];
                }
                else
                {
                    nearest = pos[companion[i]] - pos[i];
                }
                clusterRight = companion[i];
                widthUnits = nearest;
            }
            else
            {
                if (companion[i] == (-2))
                {
                    widthUnits = 3.4028234663852885981170418348452e+38;
                    clusterRight = companion[i];
                    clusterStems = 0;
                    for (;;)
                    {
                        bool _1416_ladder_break = false;
                        do
                        {
                            if (!(clusterStems < 32))
                            {
                                _1416_ladder_break = true;
                                break;
                            }
                            if (clusterStems >= n)
                            {
                                _1416_ladder_break = true;
                                break;
                            }
                            if (clusterStems == i)
                            {
                                bottomBlue = true;
                            }
                            else
                            {
                                bottomBlue = dir[clusterStems] == dir[i];
                            }
                            if (bottomBlue)
                            {
                                break;
                            }
                            if (top)
                            {
                                clusterTarget_1 = pos[i] - pos[clusterStems];
                            }
                            else
                            {
                                clusterTarget_1 = pos[clusterStems] - pos[i];
                            }
                            if (clusterTarget_1 <= 0.0)
                            {
                                _1008 = true;
                            }
                            else
                            {
                                _1008 = clusterTarget_1 >= widthUnits;
                            }
                            if (_1008)
                            {
                                break;
                            }
                            widthUnits = clusterTarget_1;
                            clusterRight = clusterStems;
                            break;
                        } while(false);
                        if (_1416_ladder_break)
                        {
                            break;
                        }
                        clusterStems++;
                        continue;
                    }
                }
                else
                {
                    clusterRight = companion[i];
                    widthUnits = 3.4028234663852885981170418348452e+38;
                }
            }
            if (clusterRight < 0)
            {
                bottomBlue = true;
            }
            else
            {
                bottomBlue = hinted[clusterRight];
            }
            if (bottomBlue)
            {
                _1008 = true;
            }
            else
            {
                _1008 = blue[clusterRight] >= 0;
            }
            if (_1008)
            {
                lowerBlue = true;
            }
            else
            {
                lowerBlue = (widthUnits * _978) >= spacing;
            }
            if (lowerBlue)
            {
                break;
            }
            if (syntheticApex[clusterRight])
            {
                clusterTarget_1 = widthUnits;
            }
            else
            {
                clusterTarget_1 = max(round(widthUnits * _978), 1.0) * grid;
            }
            if (top)
            {
                nearest = targets[i] - clusterTarget_1;
            }
            else
            {
                nearest = targets[i] + clusterTarget_1;
            }
            targets[clusterRight] = nearest;
            hinted[clusterRight] = true;
            break;
        } while(false);
        if (_1389_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    i = 0;
    bool knotBlueFixed[32];
    bool knotNaturalSpacing[32];
    for (;;)
    {
        bool _1466_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1466_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1466_ladder_break = true;
                break;
            }
            if (_1663)
            {
                axisAligned = _979.xAlign != 0;
            }
            else
            {
                axisAligned = _979.yAlign != 0;
            }
            if (!hinted[i])
            {
                if (axisAligned)
                {
                    _986 = blue[i] >= 0;
                }
                else
                {
                    _986 = false;
                }
                _986 = !_986;
            }
            else
            {
                _986 = false;
            }
            if (_986)
            {
                break;
            }
            _981[_980] = pos[i];
            _982[_980] = targets[i];
            if (axisAligned)
            {
                partnerAbove = blue[i] >= 0;
            }
            else
            {
                partnerAbove = false;
            }
            knotBlueFixed[_980] = partnerAbove;
            knotNaturalSpacing[_980] = syntheticApex[i];
            _983[_980] = i;
            _980++;
            break;
        } while(false);
        if (_1466_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_1663)
    {
        _986 = _979.xRegistration == 1;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _980 > 0;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _980 < 32;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        _986 = _977 < (_981[0] - (0.25 * grid));
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        i = 31;
        for (;;)
        {
            bool _1505_ladder_break = false;
            do
            {
                if (!(i > 0))
                {
                    _1505_ladder_break = true;
                    break;
                }
                if (i <= _980)
                {
                    int _3110 = i - 1;
                    _981[i] = _981[_3110];
                    _982[i] = _982[_3110];
                    knotBlueFixed[i] = knotBlueFixed[_3110];
                    knotNaturalSpacing[i] = knotNaturalSpacing[_3110];
                    _983[i] = _983[_3110];
                }
                break;
            } while(false);
            if (_1505_ladder_break)
            {
                break;
            }
            i--;
            continue;
        }
        _981[0] = _977;
        _982[0] = snailAhSnap(_977, _978);
        knotBlueFixed[0] = false;
        knotNaturalSpacing[0] = false;
        _983[0] = 32;
        _980++;
    }
    clusterRight = 31;
    for (;;)
    {
        bool _1518_ladder_break = false;
        do
        {
            if (!(clusterRight > 0))
            {
                _1518_ladder_break = true;
                break;
            }
            if (clusterRight >= _980)
            {
                _986 = true;
            }
            else
            {
                _986 = !knotBlueFixed[clusterRight];
            }
            if (_986)
            {
                break;
            }
            clusterStems = 31;
            for (;;)
            {
                bool _1528_ladder_break = false;
                do
                {
                    if (!(clusterStems > 0))
                    {
                        _1528_ladder_break = true;
                        break;
                    }
                    if (clusterStems > clusterRight)
                    {
                        break;
                    }
                    int _3186 = clusterStems - 1;
                    if (knotBlueFixed[_3186])
                    {
                        _1528_ladder_break = true;
                        break;
                    }
                    if (knotNaturalSpacing[_3186])
                    {
                        spacing = 9.9999999747524270787835121154785e-07;
                    }
                    else
                    {
                        spacing = grid;
                    }
                    _982[_3186] = min(_982[_3186], _982[clusterStems] - spacing);
                    break;
                } while(false);
                if (_1528_ladder_break)
                {
                    break;
                }
                clusterStems--;
                continue;
            }
            break;
        } while(false);
        if (_1518_ladder_break)
        {
            break;
        }
        clusterRight--;
        continue;
    }
    i = 1;
    for (;;)
    {
        bool _1550_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1550_ladder_break = true;
                break;
            }
            if (i >= _980)
            {
                _1550_ladder_break = true;
                break;
            }
            int _3235 = i - 1;
            if (_982[i] <= _982[_3235])
            {
                _982[i] = _982[_3235] + grid;
            }
            break;
        } while(false);
        if (_1550_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_979.fadeEnabled != 0)
    {
        _986 = _978 > _979.fadeStart;
    }
    else
    {
        _986 = false;
    }
    if (_986)
    {
        float span = _979.fadeFull - _979.fadeStart;
        if (span <= 0.0)
        {
            _986 = true;
        }
        else
        {
            _986 = _978 >= _979.fadeFull;
        }
        if (_986)
        {
            spacing = 1.0;
        }
        else
        {
            spacing = (_978 - _979.fadeStart) / span;
        }
        i = 0;
        for (;;)
        {
            bool _1574_ladder_break = false;
            do
            {
                if (!(i < 32))
                {
                    _1574_ladder_break = true;
                    break;
                }
                if (i >= _980)
                {
                    _1574_ladder_break = true;
                    break;
                }
                _982[i] += ((_981[i] - _982[i]) * spacing);
                break;
            } while(false);
            if (_1574_ladder_break)
            {
                break;
            }
            i++;
            continue;
        }
    }
    i = 0;
    for (;;)
    {
        bool _1587_ladder_break = false;
        do
        {
            if (!(i < 32))
            {
                _1587_ladder_break = true;
                break;
            }
            if (i >= _980)
            {
                _1587_ladder_break = true;
                break;
            }
            if (!snailAhFinite(_981[i]))
            {
                _986 = true;
            }
            else
            {
                _986 = !snailAhFinite(_982[i]);
            }
            if (_986)
            {
                _980 = 0;
                return false;
            }
            break;
        } while(false);
        if (_1587_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    return true;
}

float snailInverseWarpAxis(int count, float bases[32], float targets[32], float hinted, out float invSlope)
{
    invSlope = 1.0;
    if (count == 0)
    {
        return hinted;
    }
    if (hinted <= targets[0])
    {
        return (bases[0] + hinted) - targets[0];
    }
    int _3411 = count - 1;
    if (hinted >= targets[_3411])
    {
        return (bases[_3411] + hinted) - targets[_3411];
    }
    int i = 0;
    int lo;
    bool _3372;
    for (;;)
    {
        int _3426;
        bool _3382_ladder_break = false;
        do
        {
            if (!(i < 31))
            {
                lo = 0;
                _3382_ladder_break = true;
                break;
            }
            _3426 = i + 1;
            if (_3426 >= count)
            {
                _3372 = true;
            }
            else
            {
                _3372 = targets[_3426] >= hinted;
            }
            if (_3372)
            {
                lo = i;
                _3382_ladder_break = true;
                break;
            }
            break;
        } while(false);
        if (_3382_ladder_break)
        {
            break;
        }
        i = _3426;
        continue;
    }
    int _3448 = lo + 1;
    float dt = targets[_3448] - targets[lo];
    float _3373;
    if (abs(dt) > 9.9999999747524270787835121154785e-07)
    {
        _3373 = (bases[_3448] - bases[lo]) / dt;
    }
    else
    {
        _3373 = 1.0;
    }
    invSlope = _3373;
    return bases[lo] + ((hinted - targets[lo]) * _3373);
}

float snailAhFastTarget(vec4 values[4], int idx)
{
    return values[idx >> 2][idx & 3];
}

float snailAhFastBase(ivec2 _3577, int _3578, float _3579, uvec4 _3580, int _3581)
{
    uint source = snailAhFastSource(_3580, _3581);
    float _3583;
    if (source == 32u)
    {
        _3583 = _3579;
    }
    else
    {
        _3583 = snailWarpF(_3577, (_3578 + 1) + (4 * int(source)), 0);
    }
    return _3583;
}

float snailInverseFastAxis(ivec2 _3521, int _3522, vec4 _3523[4], uvec4 _3524, int _3525, float _3526, float _3527, out float _3528)
{
    _3528 = 1.0;
    if (_3522 == 0)
    {
        return _3527;
    }
    float _3562 = snailAhFastTarget(_3523, 0);
    if (_3527 <= _3562)
    {
        return (snailAhFastBase(_3521, _3525, _3526, _3524, 0) + _3527) - _3562;
    }
    int _3607 = _3522 - 1;
    float _3608 = snailAhFastTarget(_3523, _3607);
    if (_3527 >= _3608)
    {
        return (snailAhFastBase(_3521, _3525, _3526, _3524, _3607) + _3527) - _3608;
    }
    int i = 0;
    int lo;
    bool _3532;
    for (;;)
    {
        int _3621;
        bool _3542_ladder_break = false;
        do
        {
            if (!(i < 15))
            {
                lo = 0;
                _3542_ladder_break = true;
                break;
            }
            _3621 = i + 1;
            if (_3621 >= _3522)
            {
                _3532 = true;
            }
            else
            {
                _3532 = snailAhFastTarget(_3523, _3621) >= _3527;
            }
            if (_3532)
            {
                lo = i;
                _3542_ladder_break = true;
                break;
            }
            break;
        } while(false);
        if (_3542_ladder_break)
        {
            break;
        }
        i = _3621;
        continue;
    }
    float _3642 = snailAhFastTarget(_3523, lo);
    int _3644 = lo + 1;
    float _3647 = snailAhFastBase(_3521, _3525, _3526, _3524, lo);
    float dt = snailAhFastTarget(_3523, _3644) - _3642;
    float _3533;
    if (abs(dt) > 9.9999999747524270787835121154785e-07)
    {
        _3533 = (snailAhFastBase(_3521, _3525, _3526, _3524, _3644) - _3647) / dt;
    }
    else
    {
        _3533 = 1.0;
    }
    _3528 = _3533;
    return _3647 + ((_3527 - _3642) * _3533);
}

CoverageBandSpan CoverageBandSpan_init(int first, int last)
{
    CoverageBandSpan _3805;
    _3805.first = first;
    _3805.last = last;
    return _3805;
}

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax)
{
    float center = (coord * bandScale) + bandOffset;
    float _3789 = max(abs(eppAxis * bandScale) * 0.5, 9.9999997473787516355514526367188e-06);
    int _3793 = clamp(int(center - _3789), 0, bandMax);
    return CoverageBandSpan_init(_3793, max(_3793, clamp(int(center + _3789), 0, bandMax)));
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset)
{
    int _3839 = glyphLoc.x + int(offset);
    ivec2 loc = ivec2(_3839, glyphLoc.y);
    loc.y += (_3839 >> 12);
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
    int _3967 = base.x + offset;
    ivec2 loc = ivec2(_3967, base.y);
    loc.y += (_3967 >> 12);
    loc.x &= 4095;
    return loc;
}

float rootCodeCoord(float v)
{
    float _4020;
    if (abs(v) <= 1.52587890625e-05)
    {
        _4020 = 0.0;
    }
    else
    {
        _4020 = v;
    }
    return _4020;
}

uint calcRootCode(float y1, float y2, float y3)
{
    return (11892u >> (((floatBitsToUint(rootCodeCoord(y3)) >> 29u) & 4u) | ((((floatBitsToUint(rootCodeCoord(y2)) >> 30u) & 2u) | ((floatBitsToUint(rootCodeCoord(y1)) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
}

float snapNearTangentSqrt(float disc, float b, float ac)
{
    float _4118;
    if (disc <= (max(b * b, abs(ac)) * 3.0000001061125658452510833740234e-06))
    {
        _4118 = 0.0;
    }
    else
    {
        _4118 = sqrt(disc);
    }
    return _4118;
}

vec2 solveHorizPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _4089 = a.y;
    float t1;
    float t2;
    if (abs(_4089) < 1.52587890625e-05)
    {
        float _4093 = b.y;
        if (abs(_4093) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.y * 0.5) / _4093;
        }
        t2 = t1;
    }
    else
    {
        float _4107 = b.y;
        float _4110 = _4089 * p12.y;
        float sq = snapNearTangentSqrt((_4107 * _4107) - _4110, _4107, _4110);
        if (_4107 >= 0.0)
        {
            float q = _4107 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q;
            }
            t2 = q / _4089;
        }
        else
        {
            float q_1 = _4107 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.y / q_1;
            }
            float _4160 = t1;
            t1 = q_1 / _4089;
            t2 = _4160;
        }
    }
    float _4165 = a.x;
    float _4169 = b.x * 2.0;
    return vec2((((_4165 * t1) - _4169) * t1) + p12.x, (((_4165 * t2) - _4169) * t2) + p12.x);
}

bool accumulateHorizContribution(inout float _3937, inout float _3938, vec2 _3939, vec2 _3940, ivec2 _3941, int _3942)
{
    vec4 _3959 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3941, _3942, 0).xyz, 0);
    vec4 _3986 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_3941, 1), _3942, 0).xyz, 0);
    vec4 p12 = vec4(_3959.xy, _3959.zw) - vec4(_3939, _3939);
    vec2 p3 = _3986.xy - _3939;
    if ((max(max(p12.x, p12.z), p3.x) * _3940.x) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u)
    {
        vec2 r = solveHorizPoly(p12, p3) * _3940.x;
        if ((code & 1u) != 0u)
        {
            float _4187 = r.x;
            _3937 += clamp(_4187 + 0.5, 0.0, 1.0);
            _3938 = max(_3938, clamp(1.0 - (abs(_4187) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _4203 = r.y;
            _3937 -= clamp(_4203 + 0.5, 0.0, 1.0);
            _3938 = max(_3938, clamp(1.0 - (abs(_4203) * 2.0), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveVertPoly(vec4 p12, vec2 p3)
{
    vec2 a = (p12.xy - (p12.zw * 2.0)) + p3;
    vec2 b = p12.xy - p12.zw;
    float _4366 = a.x;
    float t1;
    float t2;
    if (abs(_4366) < 1.52587890625e-05)
    {
        float _4370 = b.x;
        if (abs(_4370) < 1.52587890625e-05)
        {
            t1 = 0.0;
        }
        else
        {
            t1 = (p12.x * 0.5) / _4370;
        }
        t2 = t1;
    }
    else
    {
        float _4384 = b.x;
        float _4387 = _4366 * p12.x;
        float sq = snapNearTangentSqrt((_4384 * _4384) - _4387, _4384, _4387);
        if (_4384 >= 0.0)
        {
            float q = _4384 + sq;
            if (abs(q) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q;
            }
            t2 = q / _4366;
        }
        else
        {
            float q_1 = _4384 - sq;
            if (abs(q_1) < 1.52587890625e-05)
            {
                t1 = 0.0;
            }
            else
            {
                t1 = p12.x / q_1;
            }
            float _4414 = t1;
            t1 = q_1 / _4366;
            t2 = _4414;
        }
    }
    float _4419 = a.y;
    float _4423 = b.y * 2.0;
    return vec2((((_4419 * t1) - _4423) * t1) + p12.y, (((_4419 * t2) - _4423) * t2) + p12.y);
}

bool accumulateVertContribution(inout float _4289, inout float _4290, vec2 _4291, vec2 _4292, ivec2 _4293, int _4294)
{
    vec4 _4308 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4293, _4294, 0).xyz, 0);
    vec4 _4314 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(offsetCurveLoc(_4293, 1), _4294, 0).xyz, 0);
    vec4 p12 = vec4(_4308.xy, _4308.zw) - vec4(_4291, _4291);
    vec2 p3 = _4314.xy - _4291;
    if ((max(max(p12.y, p12.w), p3.y) * _4292.y) < (-0.5))
    {
        return false;
    }
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u)
    {
        vec2 r = solveVertPoly(p12, p3) * _4292.y;
        if ((code & 1u) != 0u)
        {
            float _4441 = r.x;
            _4289 -= clamp(_4441 + 0.5, 0.0, 1.0);
            _4290 = max(_4290, clamp(1.0 - (abs(_4441) * 2.0), 0.0, 1.0));
        }
        if (code > 1u)
        {
            float _4457 = r.y;
            _4289 += clamp(_4457 + 0.5, 0.0, 1.0);
            _4290 = max(_4290, clamp(1.0 - (abs(_4457) * 2.0), 0.0, 1.0));
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
    float _4536 = clamp(cov, 0.0, 1.0);
    float _4537 = max(coverage_exponent, 1.52587890625e-05);
    float _4532;
    if (abs(_4537 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _4532 = _4536;
    }
    else
    {
        _4532 = pow(_4536, _4537);
    }
    return _4532;
}

float evalGlyphCoverage(vec2 _3699, vec2 _3700, vec2 _3701, ivec2 _3702, ivec2 _3703, vec4 _3704, int _3705, float _3706)
{
    CoverageBandSpan hSpan = computeCoverageBandSpan(_3699.y, _3700.y, _3704.y, _3704.w, _3703.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(_3699.x, _3700.x, _3704.x, _3704.z, _3703.x);
    float xcov = 0.0;
    float xwgt = 0.0;
    int _3821 = hSpan.first;
    int _3822 = hSpan.last;
    bool _3823 = _3821 != _3822;
    int band = _3821;
    int i;
    bool _3712;
    for (;;)
    {
        bool _3717_ladder_break = false;
        do
        {
            if (!(band <= _3822))
            {
                _3717_ladder_break = true;
                break;
            }
            uvec2 hbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_3702, uint(band)), _3705, 0).xyz, 0).xy.xy;
            ivec2 _3867 = calcBandLoc(_3702, hbd.y);
            int _3869 = int(hbd.x);
            i = 0;
            for (;;)
            {
                bool _3722_ladder_break = false;
                do
                {
                    if (!(i < _3869))
                    {
                        _3722_ladder_break = true;
                        break;
                    }
                    uvec2 ref = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_3867, uint(i)), _3705, 0).xyz, 0).xy.xy;
                    if (_3823)
                    {
                        _3712 = !isCoverageBandSpanOwner(ref, band, _3821);
                    }
                    else
                    {
                        _3712 = false;
                    }
                    if (_3712)
                    {
                        break;
                    }
                    bool _3934 = accumulateHorizContribution(xcov, xwgt, _3699, _3701, decodeBandCurveLoc(ref), _3705);
                    if (!_3934)
                    {
                        _3722_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_3722_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_3717_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    float ycov = 0.0;
    float ywgt = 0.0;
    int _4238 = vSpan.first;
    int _4239 = vSpan.last;
    bool _4240 = _4238 != _4239;
    band = _4238;
    for (;;)
    {
        bool _3744_ladder_break = false;
        do
        {
            if (!(band <= _4239))
            {
                _3744_ladder_break = true;
                break;
            }
            uvec2 vbd = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_3702, uint((_3703.y + 1) + band)), _3705, 0).xyz, 0).xy.xy;
            ivec2 _4258 = calcBandLoc(_3702, vbd.y);
            int _4260 = int(vbd.x);
            i = 0;
            for (;;)
            {
                bool _3749_ladder_break = false;
                do
                {
                    if (!(i < _4260))
                    {
                        _3749_ladder_break = true;
                        break;
                    }
                    uvec2 ref_1 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(calcBandLoc(_4258, uint(i)), _3705, 0).xyz, 0).xy.xy;
                    if (_4240)
                    {
                        _3712 = !isCoverageBandSpanOwner(ref_1, band, _4238);
                    }
                    else
                    {
                        _3712 = false;
                    }
                    if (_3712)
                    {
                        break;
                    }
                    bool _4287 = accumulateVertContribution(ycov, ywgt, _3699, _3701, decodeBandCurveLoc(ref_1), _3705);
                    if (!_4287)
                    {
                        _3749_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_3749_ladder_break)
                {
                    break;
                }
                i++;
                continue;
            }
            break;
        } while(false);
        if (_3744_ladder_break)
        {
            break;
        }
        band++;
        continue;
    }
    return applyCoverageTransfer(max(applyFillRule(((xcov * xwgt) + (ycov * ywgt)) / max(xwgt + ywgt, 1.52587890625e-05), 0), min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), _3706);
}

vec4 premultiplyColor(vec4 color, float cov)
{
    float alpha = color.w * cov;
    return vec4(color.xyz * alpha, alpha);
}

float srgbEncode(float c)
{
    float _4602;
    if (c <= 0.003130800090730190277099609375)
    {
        _4602 = c * 12.9200000762939453125;
    }
    else
    {
        _4602 = (1.05499994754791259765625 * pow(c, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    return _4602;
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

vec4 snailAutohintFragment(AutohintVaryings _120, int _121, int _122, float _123, int _124)
{
    vec4 _233 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_120.info, 0).xy, 0);
    vec4 _264 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(snailAhLayerLoc(_120.info, 1), 0).xy, 0);
    int _274 = floatBitsToInt(_233.z);
    vec2 rc = _120.texcoord_layer.xy;
    vec2 epp = _fwidth(_120.texcoord_layer.xy);
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    bool valid_1 = snailAhCount(32, snailWarpF(_120.info, 0, 10), blueCount);
    int xRun = 12 + (2 * blueCount);
    bool valid;
    if (valid_1)
    {
        bool _430 = snailAhCount(32, snailWarpF(_120.info, xRun, 0), featureXCount);
        valid = _430;
    }
    else
    {
        valid = false;
    }
    int yRun = (xRun + 1) + (4 * featureXCount);
    if (valid)
    {
        bool _442 = snailAhCount(32, snailWarpF(_120.info, yRun, 0), featureYCount);
        valid = _442;
    }
    else
    {
        valid = false;
    }
    int _136;
    if (valid)
    {
        _136 = snailAhFastCount(_120.x_sources);
    }
    else
    {
        _136 = 0;
    }
    int xCount = _136;
    if (valid)
    {
        _136 = snailAhFastCount(_120.y_sources);
    }
    else
    {
        _136 = 0;
    }
    int yCount = _136;
    float slopeX = 1.0;
    float slopeY = 1.0;
    int _536 = xCount;
    bool fallbackX = _536 < 0;
    bool fallbackY = _136 < 0;
    if (valid)
    {
        if (fallbackX)
        {
            valid = true;
        }
        else
        {
            valid = fallbackY;
        }
    }
    else
    {
        valid = false;
    }
    if (valid)
    {
        float _552 = snailWarpF(_120.info, 0, 8);
        float _553 = snailWarpF(_120.info, 0, 9);
        SnailAutohintPolicy policy;
        bool _559 = snailDecodeAutohintPolicy(_120.policy0, _120.policy1, policy);
        if (_559)
        {
            valid = snailAhFinite(_552);
        }
        else
        {
            valid = false;
        }
        if (valid)
        {
            valid = _552 >= 0.0;
        }
        else
        {
            valid = false;
        }
        if (valid)
        {
            valid = snailAhFinite(_553);
        }
        else
        {
            valid = false;
        }
        if (valid)
        {
            valid = _553 >= 0.0;
        }
        else
        {
            valid = false;
        }
        bool _144;
        if (valid)
        {
            _144 = fallbackX;
        }
        else
        {
            _144 = false;
        }
        if (_144)
        {
            SnailAutohintPolicy _153 = policy;
            float bases[32];
            float targets[32];
            int sources[32];
            bool _969 = snailFitAutohintAxis(_120.info, 0, xRun, blueCount, _552, snailWarpF(_120.info, 0, 11), 1.0 / epp.x, _153, xCount, bases, targets, sources);
            if (!_969)
            {
                xCount = 0;
            }
            float _154[32] = bases;
            float _155[32] = targets;
            float _3361 = snailInverseWarpAxis(xCount, _154, _155, rc.x, slopeX);
            rc.x = _3361;
        }
        if (valid)
        {
            valid = fallbackY;
        }
        else
        {
            valid = false;
        }
        if (valid)
        {
            SnailAutohintPolicy _159 = policy;
            float bases_1[32];
            float targets_1[32];
            int sources_1[32];
            bool _3489 = snailFitAutohintAxis(_120.info, 1, yRun, blueCount, _553, 0.0, 1.0 / epp.y, _159, yCount, bases_1, targets_1, sources_1);
            if (!_3489)
            {
                yCount = 0;
            }
            float _160[32] = bases_1;
            float _161[32] = targets_1;
            float _3502 = snailInverseWarpAxis(yCount, _160, _161, rc.y, slopeY);
            rc.y = _3502;
        }
    }
    if (!fallbackX)
    {
        vec4 _162[4] = _120.x_targets;
        float _3518 = snailInverseFastAxis(_120.info, xCount, _162, _120.x_sources, xRun, snailWarpF(_120.info, 0, 11), rc.x, slopeX);
        rc.x = _3518;
    }
    if (!fallbackY)
    {
        vec4 _163[4] = _120.y_targets;
        float _3679 = snailInverseFastAxis(_120.info, yCount, _163, _120.y_sources, yRun, 0.0, rc.y, slopeY);
        rc.y = _3679;
    }
    vec2 epp_1 = epp * vec2(slopeX, slopeY);
    float _3696 = evalGlyphCoverage(rc, epp_1, vec2(1.0 / max(epp_1.x, 1.52587890625e-05), 1.0 / max(epp_1.y, 1.52587890625e-05)), ivec2(int(_233.x + 0.5), int(_233.y + 0.5)), ivec2((_274 >> 16) & 65535, _274 & 65535), _264, _121 + int(_120.texcoord_layer.z), _123);
    if (_3696 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    vec4 premul = premultiplyColor(_120.paint, _3696);
    vec4 _164;
    if (_124 != 0)
    {
        _164 = vec4(premul.w);
    }
    else
    {
        if (_122 != 0)
        {
            _164 = srgbEncodePremultiplied(premul);
        }
        else
        {
            _164 = premul;
        }
    }
    return _164;
}

void main()
{
    AutohintVaryings v;
    v.paint = snail_io0;
    v.texcoord_layer = snail_io1;
    v.info = snail_io2;
    v.policy0 = snail_io3;
    v.policy1 = snail_io4;
    v.x_targets[0] = snail_io5;
    v.x_targets[1] = snail_io6;
    v.x_targets[2] = snail_io7;
    v.x_targets[3] = snail_io8;
    v.y_targets[0] = snail_io9;
    v.y_targets[1] = snail_io10;
    v.y_targets[2] = snail_io11;
    v.y_targets[3] = snail_io12;
    v.x_sources = snail_io13;
    v.y_sources = snail_io14;
    AutohintVaryings _18 = v;
    vec4 _117 = snailAutohintFragment(_18, pc.layer_base, pc.output_srgb, pc.coverage_exponent, pc.mask_output);
    entryPointParam_fragmentMain = _117;
}

