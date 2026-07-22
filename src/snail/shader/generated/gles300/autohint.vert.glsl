#version 300 es

struct VsInput
{
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
    uvec4 policy0;
    uvec3 policy1;
};

struct VsOutput
{
    vec4 position;
    vec4 paint;
    vec3 texcoord_layer;
    ivec2 info;
    uvec4 policy0;
    uvec3 policy1;
    vec4 x_targets0;
    vec4 x_targets1;
    vec4 x_targets2;
    vec4 x_targets3;
    vec4 y_targets0;
    vec4 y_targets1;
    vec4 y_targets2;
    vec4 y_targets3;
    uvec4 x_sources;
    uvec4 y_sources;
};

struct TextVertexIn
{
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
};

struct AutohintVertexResult
{
    vec4 position;
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

struct TextVertexResult
{
    vec4 position;
    vec4 color;
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};

const vec2 _247[4] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0));

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

uniform highp sampler2D SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler;

layout(location = 0) in vec4 input_rect;
layout(location = 1) in vec4 input_xform;
layout(location = 2) in vec2 input_origin;
layout(location = 3) in uvec2 input_glyph;
layout(location = 4) in vec4 input_bnd;
layout(location = 5) in vec4 input_col;
layout(location = 6) in vec4 input_tint;
layout(location = 7) in uvec4 input_policy0;
layout(location = 8) in uvec3 input_policy1;
out vec4 snail_io0;
out vec3 snail_io1;
flat out ivec2 snail_io2;
flat out uvec4 snail_io3;
flat out uvec3 snail_io4;
flat out vec4 snail_io5;
flat out vec4 snail_io6;
flat out vec4 snail_io7;
flat out vec4 snail_io8;
flat out vec4 snail_io9;
flat out vec4 snail_io10;
flat out vec4 snail_io11;
flat out vec4 snail_io12;
flat out uvec4 snail_io13;
flat out uvec4 snail_io14;

highp mat4 spvWorkaroundRowMajor(highp mat4 wrap) { return wrap; }
mediump mat4 spvWorkaroundRowMajorMP(mediump mat4 wrap) { return wrap; }

float srgbDecode(float c)
{
    float _347;
    if (c <= 0.040449999272823333740234375)
    {
        _347 = c / 12.9200000762939453125;
    }
    else
    {
        _347 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _347;
}

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

float snailVertexDilationScale(int subpixel_order)
{
    float _439;
    if (subpixel_order == 0)
    {
        _439 = 1.0;
    }
    else
    {
        _439 = 2.3333332538604736328125;
    }
    return 1.41421353816986083984375 * _439;
}

TextVertexResult snailTextVertex(TextVertexIn _input, uint vertex_index, mat4 mvp, vec2 viewport, int subpixel_order)
{
    vec2 _261 = mix(_input.rect.xy, _input.rect.zw, _247[vertex_index]);
    vec2 nd = (_247[vertex_index] * 2.0) - vec2(1.0);
    float _274 = _261.x;
    float _277 = _261.y;
    vec2 pos = vec2(((_input.xform.x * _274) + (_input.xform.y * _277)) + _input.origin.x, ((_input.xform.z * _274) + (_input.xform.w * _277)) + _input.origin.y);
    float _290 = nd.x;
    float _292 = nd.y;
    float inv_det = 1.0 / ((_input.xform.x * _input.xform.w) - (_input.xform.y * _input.xform.z));
    TextVertexResult r;
    r.glyph = ivec4(int(_input.glyph.x & 65535u), int(_input.glyph.x >> 16u), int(_input.glyph.y & 65535u), int(_input.glyph.y >> 16u));
    r.banding = _input.bnd;
    r.color = vec4(srgbToLinear(_input.col.xyz), _input.col.w);
    r.tint = vec4(srgbToLinear(_input.tint.xyz), _input.tint.w);
    vec2 _386 = normalize(vec2((_input.xform.x * _290) + (_input.xform.y * _292), (_input.xform.z * _290) + (_input.xform.w * _292)));
    float s = dot(mvp[3].xy, pos) + mvp[3].w;
    float _391 = dot(mvp[3].xy, _386);
    float u_val = ((s * dot(mvp[0].xy, _386)) - (_391 * (dot(mvp[0].xy, pos) + mvp[0].w))) * viewport.x;
    float v_val = ((s * dot(mvp[1].xy, _386)) - (_391 * (dot(mvp[1].xy, pos) + mvp[1].w))) * viewport.y;
    float st = s * _391;
    float uv = (u_val * u_val) + (v_val * v_val);
    float denom = uv - (st * st);
    vec2 d;
    if (abs(denom) > 1.0000000133514319600180897396058e-10)
    {
        d = _386 * (((s * s) * (st + sqrt(uv))) / denom);
    }
    else
    {
        d = (_386 * 2.0) / viewport;
    }
    vec2 d_1 = d * snailVertexDilationScale(subpixel_order);
    r.texcoord = vec2(_274 + dot(d_1, vec2(_input.xform.w * inv_det, (-_input.xform.y) * inv_det)), _277 + dot(d_1, vec2((-_input.xform.z) * inv_det, _input.xform.x * inv_det)));
    r.position = vec4(pos + d_1, 0.0, 1.0) * mvp;
    return r;
}

bool snailAhFinite(float v)
{
    bool _600;
    if (!isnan(v))
    {
        _600 = !isinf(v);
    }
    else
    {
        _600 = false;
    }
    return _600;
}

bool snailAhAffineScale(mat4 mvp, vec2 viewport, vec4 xform, inout vec2 scale)
{
    scale = vec2(0.0);
    bool _546;
    if (abs(mvp[3].x) > 1.0000000116860974230803549289703e-07)
    {
        _546 = true;
    }
    else
    {
        _546 = abs(mvp[3].y) > 1.0000000116860974230803549289703e-07;
    }
    if (_546)
    {
        _546 = true;
    }
    else
    {
        _546 = !snailAhFinite(mvp[3].w);
    }
    if (_546)
    {
        _546 = true;
    }
    else
    {
        _546 = abs(mvp[3].w) < 1.0000000133514319600180897396058e-10;
    }
    if (_546)
    {
        return false;
    }
    vec2 localX = vec2(xform.xz);
    vec2 localY = vec2(xform.yw);
    vec2 _637 = viewport * 0.5;
    vec2 screenX = (_637 * vec2(dot(mvp[0].xy, localX), dot(mvp[1].xy, localX))) / vec2(mvp[3].w);
    vec2 screenY = (_637 * vec2(dot(mvp[0].xy, localY), dot(mvp[1].xy, localY))) / vec2(mvp[3].w);
    float _654 = screenX.x;
    float _655 = screenY.y;
    float _657 = screenY.x;
    float _658 = screenX.y;
    float det = (_654 * _655) - (_657 * _658);
    if (!snailAhFinite(det))
    {
        _546 = true;
    }
    else
    {
        _546 = abs(det) < 1.0000000133514319600180897396058e-10;
    }
    if (_546)
    {
        return false;
    }
    float _676 = abs(det);
    vec2 _684 = vec2(1.0) / vec2((abs(_655) + abs(_657)) / _676, (abs(_658) + abs(_654)) / _676);
    scale = _684;
    if (snailAhFinite(_684.x))
    {
        _546 = snailAhFinite(scale.y);
    }
    else
    {
        _546 = false;
    }
    if (_546)
    {
        _546 = scale.x > 0.0;
    }
    else
    {
        _546 = false;
    }
    if (_546)
    {
        _546 = scale.y > 0.0;
    }
    else
    {
        _546 = false;
    }
    return _546;
}

void snailAhMarkFallback(inout vec4 packedTargets[4], inout uvec4 packedSources)
{
    int i = 0;
    for (;;)
    {
        bool _733_ladder_break = false;
        do
        {
            if (!(i < 4))
            {
                _733_ladder_break = true;
                break;
            }
            packedTargets[i] = vec4(0.0);
            break;
        } while(false);
        if (_733_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    packedSources = uvec4(4294967295u);
    packedSources.x = (4294967295u & 4294967040u) | 254u;
}

ivec2 snailAhLayerLoc(ivec2 _809, int _810)
{
    uvec2 vecSize = uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0));
    uint uw = vecSize.x;
    uint uh = vecSize.y;
    int width = int(uw);
    int texel = ((_809.y * width) + _809.x) + _810;
    return ivec2(texel - width * (texel / width), texel / width);
}

float snailWarpF(ivec2 _790, int _791, int _792)
{
    int f = _791 + _792;
    vec4 _838 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(snailAhLayerLoc(_790, f >> 2), 0).xy, 0);
    int c = f & 3;
    float _794;
    if (c == 0)
    {
        _794 = _838.x;
    }
    else
    {
        if (c == 1)
        {
            _794 = _838.y;
        }
        else
        {
            if (c == 2)
            {
                _794 = _838.z;
            }
            else
            {
                _794 = _838.w;
            }
        }
    }
    return _794;
}

bool snailDecodeAutohintPolicy(uvec4 p0, uvec3 p1, inout SnailAutohintPolicy p)
{
    p = SnailAutohintPolicy(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    bool _870;
    if ((p0.x & 4286578688u) != 0u)
    {
        _870 = true;
    }
    else
    {
        _870 = (p0.y & 4294967232u) != 0u;
    }
    if (_870)
    {
        return false;
    }
    int _973 = int(p0.x & 3u);
    p.xAlign = _973;
    p.xStem = int((p0.x >> 2u) & 3u);
    p.xPositioning = int((p0.x >> 4u) & 3u);
    p.xRegistration = int((p0.x >> 6u) & 3u);
    p.fadeEnabled = int((p0.x >> 8u) & 1u);
    p.fadeStart = float((p0.x >> 9u) & 127u);
    p.fadeFull = float((p0.x >> 16u) & 127u);
    p.yAlign = int(p0.y & 3u);
    p.yStem = int((p0.y >> 2u) & 3u);
    p.yOvershoot = int((p0.y >> 4u) & 3u);
    if (_973 > 1)
    {
        _870 = true;
    }
    else
    {
        _870 = p.xStem > 2;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        _870 = p.xPositioning > 1;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        _870 = p.xRegistration > 1;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        _870 = p.yAlign > 2;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        _870 = p.yStem > 2;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        _870 = p.yOvershoot > 1;
    }
    if (_870)
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
            _870 = true;
        }
        else
        {
            _870 = p.xRatio < 0.0;
        }
    }
    else
    {
        _870 = false;
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.xStem == 1)
        {
            if (!snailAhFinite(p.xMaxPx))
            {
                _870 = true;
            }
            else
            {
                _870 = p.xMaxPx < 0.0;
            }
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.yStem != 0)
        {
            if (!snailAhFinite(p.yRatio))
            {
                _870 = true;
            }
            else
            {
                _870 = p.yRatio < 0.0;
            }
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.yStem == 1)
        {
            if (!snailAhFinite(p.yMaxPx))
            {
                _870 = true;
            }
            else
            {
                _870 = p.yMaxPx < 0.0;
            }
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.yOvershoot == 1)
        {
            if (!snailAhFinite(p.overshootMinPx))
            {
                _870 = true;
            }
            else
            {
                _870 = p.overshootMinPx < 0.0;
            }
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.xPositioning == 1)
        {
            _870 = p.xAlign == 0;
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        _870 = true;
    }
    else
    {
        if (p.yOvershoot == 1)
        {
            _870 = p.yAlign != 2;
        }
        else
        {
            _870 = false;
        }
    }
    if (_870)
    {
        return false;
    }
    return true;
}

bool snailAhCount(int max_knots, float encoded, out int count)
{
    bool _1271;
    if (!snailAhFinite(encoded))
    {
        _1271 = true;
    }
    else
    {
        _1271 = encoded < 0.0;
    }
    if (_1271)
    {
        _1271 = true;
    }
    else
    {
        _1271 = encoded > float(max_knots);
    }
    if (_1271)
    {
        _1271 = true;
    }
    else
    {
        _1271 = floor(encoded) != encoded;
    }
    if (_1271)
    {
        count = 0;
        return false;
    }
    count = int(encoded);
    return true;
}

float snailAhSnap(float v, float scale)
{
    return round(v * scale) / scale;
}

float snailAhStandardWidth(float raw, float standard, float ratio)
{
    bool _2544;
    if (standard > 0.0)
    {
        _2544 = abs(raw - standard) <= (ratio * standard);
    }
    else
    {
        _2544 = false;
    }
    float _2545;
    if (_2544)
    {
        _2545 = standard;
    }
    else
    {
        _2545 = raw;
    }
    return _2545;
}

bool snailFitAutohintAxis(ivec2 _1379, int _1380, int _1381, int _1382, float _1383, float _1384, float _1385, SnailAutohintPolicy _1386, inout int _1387, inout float _1388[16], inout float _1389[16], inout int _1390[16])
{
    _1387 = 0;
    int i = 0;
    for (;;)
    {
        bool _1438_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1438_ladder_break = true;
                break;
            }
            _1388[i] = 0.0;
            _1389[i] = 0.0;
            _1390[i] = 0;
            break;
        } while(false);
        if (_1438_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    bool _1393;
    if (!snailAhFinite(_1385))
    {
        _1393 = true;
    }
    else
    {
        _1393 = _1385 <= 0.0;
    }
    if (_1393)
    {
        _1393 = true;
    }
    else
    {
        _1393 = _1382 < 0;
    }
    if (_1393)
    {
        _1393 = true;
    }
    else
    {
        _1393 = _1382 > 16;
    }
    if (_1393)
    {
        _1393 = true;
    }
    else
    {
        _1393 = !snailAhFinite(_1383);
    }
    if (_1393)
    {
        _1393 = true;
    }
    else
    {
        _1393 = _1383 < 0.0;
    }
    if (_1393)
    {
        return false;
    }
    bool _1989 = _1380 == 0;
    if (_1989)
    {
        _1393 = _1386.xAlign == 0;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1386.xStem == 0;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1386.xPositioning == 0;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1386.xRegistration == 0;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = true;
    }
    else
    {
        if (_1380 == 1)
        {
            _1393 = _1386.yAlign == 0;
        }
        else
        {
            _1393 = false;
        }
        if (_1393)
        {
            _1393 = _1386.yStem == 0;
        }
        else
        {
            _1393 = false;
        }
        if (_1393)
        {
            _1393 = _1386.yOvershoot == 0;
        }
        else
        {
            _1393 = false;
        }
    }
    if (_1393)
    {
        return true;
    }
    int n = int(snailWarpF(_1379, _1381, 0));
    if (n <= 0)
    {
        _1393 = true;
    }
    else
    {
        _1393 = n > 16;
    }
    if (_1393)
    {
        return n == 0;
    }
    bool _2073 = _1380 == 1;
    if (_2073)
    {
        _1393 = _1386.yAlign == 2;
    }
    else
    {
        _1393 = false;
    }
    bool partnerAbove;
    if (_1989)
    {
        partnerAbove = _1386.xRegistration == 1;
    }
    else
    {
        partnerAbove = false;
    }
    if (partnerAbove)
    {
        partnerAbove = !snailAhFinite(_1384);
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
    float pos[16];
    float width[16];
    int stem[16];
    int blue[16];
    bool rounded[16];
    bool syntheticApex[16];
    int companion[16];
    int dir[16];
    bool hinted[16];
    int stemMode;
    int clusterRight;
    bool validBlue;
    bool _1412;
    bool _1413;
    bool axisAligned;
    bool lowerBlue;
    bool upperBlue;
    bool _1417;
    uint _1418;
    for (;;)
    {
        bool _1507_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1507_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1507_ladder_break = true;
                break;
            }
            int f = (_1381 + 1) + (4 * i);
            pos[i] = snailWarpF(_1379, f, 0);
            width[i] = snailWarpF(_1379, f, 1);
            uint _2122 = floatBitsToUint(snailWarpF(_1379, f, 2));
            stem[i] = int(_2122 << 16u) >> 16;
            blue[i] = int(_2122) >> 16;
            uint _2135 = floatBitsToUint(snailWarpF(_1379, f, 3));
            rounded[i] = (_2135 & 1u) != 0u;
            syntheticApex[i] = (_2135 & 2u) != 0u;
            if ((_2135 & 4u) == 0u)
            {
                return false;
            }
            if ((_2135 & 8u) != 0u)
            {
                stemMode = -1;
            }
            else
            {
                stemMode = 1;
            }
            dir[i] = stemMode;
            if (_1393)
            {
                _1418 = 10u;
            }
            else
            {
                _1418 = 4u;
            }
            int encodedCompanion = int((_2135 >> _1418) & 63u);
            if (encodedCompanion >= 62)
            {
                clusterRight = -1;
            }
            else
            {
                clusterRight = encodedCompanion;
            }
            companion[i] = clusterRight;
            if (encodedCompanion >= 63)
            {
                partnerAbove = rounded[i];
            }
            else
            {
                partnerAbove = false;
            }
            if (partnerAbove)
            {
                validBlue = blue[i] >= 0;
            }
            else
            {
                validBlue = false;
            }
            if (validBlue)
            {
                return false;
            }
            hinted[i] = false;
            if (!snailAhFinite(pos[i]))
            {
                _1412 = true;
            }
            else
            {
                _1412 = !snailAhFinite(width[i]);
            }
            if (_1412)
            {
                _1413 = true;
            }
            else
            {
                _1413 = width[i] < 0.0;
            }
            if (_1413)
            {
                axisAligned = true;
            }
            else
            {
                axisAligned = stem[i] < (-1);
            }
            if (axisAligned)
            {
                lowerBlue = true;
            }
            else
            {
                lowerBlue = stem[i] >= n;
            }
            if (lowerBlue)
            {
                upperBlue = true;
            }
            else
            {
                upperBlue = blue[i] < (-1);
            }
            if (upperBlue)
            {
                _1417 = true;
            }
            else
            {
                _1417 = blue[i] >= _1382;
            }
            if (_1417)
            {
                return false;
            }
            break;
        } while(false);
        if (_1507_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    i = 0;
    for (;;)
    {
        bool _1560_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1560_ladder_break = true;
                break;
            }
            if (i >= _1382)
            {
                _1560_ladder_break = true;
                break;
            }
            int _2279 = 2 * i;
            if (!snailAhFinite(snailWarpF(_1379, 12, _2279)))
            {
                partnerAbove = true;
            }
            else
            {
                partnerAbove = !snailAhFinite(snailWarpF(_1379, 12, _2279 + 1));
            }
            if (partnerAbove)
            {
                return false;
            }
            break;
        } while(false);
        if (_1560_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_2073)
    {
        partnerAbove = _1386.yOvershoot == 1;
    }
    else
    {
        partnerAbove = false;
    }
    float spacing;
    if (partnerAbove)
    {
        spacing = _1386.overshootMinPx;
    }
    else
    {
        spacing = 0.0;
    }
    i = 0;
    float targets[16];
    for (;;)
    {
        bool _1584_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1584_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1584_ladder_break = true;
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
            if (_1393)
            {
                validBlue = blue[i] >= 0;
            }
            else
            {
                validBlue = false;
            }
            if (!_1393)
            {
                if (partnerAbove)
                {
                    stemMode = -1;
                }
                else
                {
                    stemMode = 1;
                }
                dir[i] = stemMode;
            }
            if (validBlue)
            {
                float _2375 = snailWarpF(_1379, 12, 2 * blue[i]);
                float _2379 = snailWarpF(_1379, 12, (2 * blue[i]) + 1);
                if (rounded[i])
                {
                    _1412 = _2073;
                }
                else
                {
                    _1412 = false;
                }
                if (_1412)
                {
                    _1413 = _1386.yOvershoot == 0;
                }
                else
                {
                    _1413 = false;
                }
                if (_1413)
                {
                    targets[i] = pos[i];
                }
                else
                {
                    targets[i] = snailAhSnap(_2375, _1385);
                    if (rounded[i])
                    {
                        axisAligned = abs((_2379 - _2375) * _1385) >= spacing;
                    }
                    else
                    {
                        axisAligned = false;
                    }
                    if (axisAligned)
                    {
                        targets[i] += (_2379 - _2375);
                    }
                }
            }
            else
            {
                targets[i] = snailAhSnap(pos[i], _1385);
            }
            break;
        } while(false);
        if (_1584_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    float grid = 1.0 / _1385;
    if (_1989)
    {
        stemMode = _1386.xStem;
    }
    else
    {
        stemMode = _1386.yStem;
    }
    if (_1989)
    {
        spacing = _1386.xRatio;
    }
    else
    {
        spacing = _1386.yRatio;
    }
    float maxPx;
    if (_1989)
    {
        maxPx = _1386.xMaxPx;
    }
    else
    {
        maxPx = _1386.yMaxPx;
    }
    if (_1989)
    {
        _1393 = _1386.xAlign == 1;
    }
    else
    {
        _1393 = _1386.yAlign != 0;
    }
    if (_1989)
    {
        partnerAbove = _1386.xPositioning == 1;
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
    clusterRight = 0;
    i = 0;
    int clusterStems = 0;
    int clusterRight_1;
    int clusterStems_1;
    float widthUnits;
    float clusterTarget_1;
    float clusterBase_1;
    float clusterTarget_2;
    float clusterBase_2;
    float clusterDesiredRight_1;
    bool _1435;
    for (;;)
    {
        bool _1641_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1641_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1641_ladder_break = true;
                break;
            }
            if (stem[i] < 0)
            {
                _1412 = true;
            }
            else
            {
                _1412 = stem[i] <= i;
            }
            if (_1412)
            {
                axisAligned = validBlue;
                break;
            }
            float nominal = snailAhStandardWidth(width[i], _1383, spacing);
            if (stemMode == 2)
            {
                _1413 = true;
            }
            else
            {
                if (stemMode == 1)
                {
                    _1413 = (nominal * _1385) < maxPx;
                }
                else
                {
                    _1413 = false;
                }
            }
            if (_1413)
            {
                widthUnits = max(round(nominal * _1385), 1.0) * grid;
            }
            else
            {
                widthUnits = width[i];
            }
            if (partnerAbove)
            {
                if (validBlue)
                {
                    targets[i] = anchorTarget + (round((pos[i] - anchorBase) * _1385) * grid);
                    clusterTarget_1 = clusterTarget;
                    clusterBase_1 = clusterBase;
                    axisAligned = validBlue;
                }
                else
                {
                    float _2626 = snailAhSnap(pos[i], _1385);
                    targets[i] = _2626;
                    clusterTarget_1 = _2626;
                    clusterBase_1 = pos[i];
                    axisAligned = true;
                }
                targets[stem[i]] = targets[i] + widthUnits;
                float _2645 = clusterBase_1;
                float _2650 = clusterTarget_1;
                float _2656 = clusterTarget_1;
                float _2657 = clusterBase_1;
                clusterTarget_1 = targets[i];
                clusterBase_1 = pos[i];
                clusterTarget_2 = _2656;
                clusterBase_2 = _2657;
                clusterDesiredRight_1 = (_2650 + (round((pos[i] - _2645) * _1385) * grid)) + widthUnits;
                clusterRight_1 = stem[i];
                clusterStems_1 = clusterStems + 1;
            }
            else
            {
                if (_1989)
                {
                    axisAligned = _1386.xAlign != 0;
                }
                else
                {
                    axisAligned = _1386.yAlign != 0;
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
                if (!_1393)
                {
                    targets[i] = pos[i];
                }
                if (upperBlue)
                {
                    _1417 = !lowerBlue;
                }
                else
                {
                    _1417 = false;
                }
                if (_1417)
                {
                    _1435 = _1393;
                }
                else
                {
                    _1435 = false;
                }
                if (_1435)
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
                clusterRight_1 = clusterRight;
                clusterStems_1 = clusterStems;
            }
            hinted[i] = true;
            hinted[stem[i]] = true;
            anchorTarget = clusterTarget_1;
            anchorBase = clusterBase_1;
            clusterTarget = clusterTarget_2;
            clusterBase = clusterBase_2;
            clusterDesiredRight = clusterDesiredRight_1;
            clusterRight = clusterRight_1;
            clusterStems = clusterStems_1;
            break;
        } while(false);
        if (_1641_ladder_break)
        {
            break;
        }
        validBlue = axisAligned;
        i++;
        continue;
    }
    if (partnerAbove)
    {
        _1393 = clusterStems > 1;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        float _2798 = clusterDesiredRight - targets[clusterRight];
        i = 0;
        for (;;)
        {
            bool _1697_ladder_break = false;
            do
            {
                if (!(i < 16))
                {
                    _1697_ladder_break = true;
                    break;
                }
                if (i >= n)
                {
                    _1697_ladder_break = true;
                    break;
                }
                if (hinted[i])
                {
                    targets[i] += _2798;
                }
                break;
            } while(false);
            if (_1697_ladder_break)
            {
                break;
            }
            i++;
            continue;
        }
    }
    if (stemMode == 1)
    {
        spacing = maxPx;
    }
    else
    {
        spacing = 1.60000002384185791015625;
    }
    i = 0;
    for (;;)
    {
        bool _1715_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1715_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1715_ladder_break = true;
                break;
            }
            if (_1989)
            {
                axisAligned = _1386.xAlign != 0;
            }
            else
            {
                axisAligned = _1386.yAlign != 0;
            }
            if (!axisAligned)
            {
                _1393 = true;
            }
            else
            {
                _1393 = blue[i] < 0;
            }
            if (_1393)
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
                    maxPx = pos[i] - pos[companion[i]];
                }
                else
                {
                    maxPx = pos[companion[i]] - pos[i];
                }
                clusterRight_1 = companion[i];
                widthUnits = maxPx;
            }
            else
            {
                if (companion[i] == (-2))
                {
                    widthUnits = 3.4028234663852885981170418348452e+38;
                    clusterRight_1 = companion[i];
                    clusterStems_1 = 0;
                    for (;;)
                    {
                        bool _1742_ladder_break = false;
                        do
                        {
                            if (!(clusterStems_1 < 16))
                            {
                                _1742_ladder_break = true;
                                break;
                            }
                            if (clusterStems_1 >= n)
                            {
                                _1742_ladder_break = true;
                                break;
                            }
                            if (clusterStems_1 == i)
                            {
                                _1412 = true;
                            }
                            else
                            {
                                _1412 = dir[clusterStems_1] == dir[i];
                            }
                            if (_1412)
                            {
                                break;
                            }
                            if (top)
                            {
                                clusterTarget_1 = pos[i] - pos[clusterStems_1];
                            }
                            else
                            {
                                clusterTarget_1 = pos[clusterStems_1] - pos[i];
                            }
                            if (clusterTarget_1 <= 0.0)
                            {
                                _1413 = true;
                            }
                            else
                            {
                                _1413 = clusterTarget_1 >= widthUnits;
                            }
                            if (_1413)
                            {
                                break;
                            }
                            widthUnits = clusterTarget_1;
                            clusterRight_1 = clusterStems_1;
                            break;
                        } while(false);
                        if (_1742_ladder_break)
                        {
                            break;
                        }
                        clusterStems_1++;
                        continue;
                    }
                }
                else
                {
                    clusterRight_1 = companion[i];
                    widthUnits = 3.4028234663852885981170418348452e+38;
                }
            }
            if (clusterRight_1 < 0)
            {
                _1412 = true;
            }
            else
            {
                _1412 = hinted[clusterRight_1];
            }
            if (_1412)
            {
                _1413 = true;
            }
            else
            {
                _1413 = blue[clusterRight_1] >= 0;
            }
            if (_1413)
            {
                lowerBlue = true;
            }
            else
            {
                lowerBlue = (widthUnits * _1385) >= spacing;
            }
            if (lowerBlue)
            {
                break;
            }
            if (syntheticApex[clusterRight_1])
            {
                clusterTarget_1 = widthUnits;
            }
            else
            {
                clusterTarget_1 = max(round(widthUnits * _1385), 1.0) * grid;
            }
            if (top)
            {
                maxPx = targets[i] - clusterTarget_1;
            }
            else
            {
                maxPx = targets[i] + clusterTarget_1;
            }
            targets[clusterRight_1] = maxPx;
            hinted[clusterRight_1] = true;
            break;
        } while(false);
        if (_1715_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    i = 0;
    bool knotBlueFixed[16];
    bool knotNaturalSpacing[16];
    for (;;)
    {
        bool _1792_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1792_ladder_break = true;
                break;
            }
            if (i >= n)
            {
                _1792_ladder_break = true;
                break;
            }
            if (_1989)
            {
                axisAligned = _1386.xAlign != 0;
            }
            else
            {
                axisAligned = _1386.yAlign != 0;
            }
            if (!hinted[i])
            {
                if (axisAligned)
                {
                    _1393 = blue[i] >= 0;
                }
                else
                {
                    _1393 = false;
                }
                _1393 = !_1393;
            }
            else
            {
                _1393 = false;
            }
            if (_1393)
            {
                break;
            }
            _1388[_1387] = pos[i];
            _1389[_1387] = targets[i];
            if (axisAligned)
            {
                partnerAbove = blue[i] >= 0;
            }
            else
            {
                partnerAbove = false;
            }
            knotBlueFixed[_1387] = partnerAbove;
            knotNaturalSpacing[_1387] = syntheticApex[i];
            _1390[_1387] = i;
            _1387++;
            break;
        } while(false);
        if (_1792_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_1989)
    {
        _1393 = _1386.xRegistration == 1;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1387 > 0;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1387 < 16;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        _1393 = _1384 < (_1388[0] - (0.25 * grid));
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        i = 15;
        for (;;)
        {
            bool _1831_ladder_break = false;
            do
            {
                if (!(i > 0))
                {
                    _1831_ladder_break = true;
                    break;
                }
                if (i <= _1387)
                {
                    int _3209 = i - 1;
                    _1388[i] = _1388[_3209];
                    _1389[i] = _1389[_3209];
                    knotBlueFixed[i] = knotBlueFixed[_3209];
                    knotNaturalSpacing[i] = knotNaturalSpacing[_3209];
                    _1390[i] = _1390[_3209];
                }
                break;
            } while(false);
            if (_1831_ladder_break)
            {
                break;
            }
            i--;
            continue;
        }
        _1388[0] = _1384;
        _1389[0] = snailAhSnap(_1384, _1385);
        knotBlueFixed[0] = false;
        knotNaturalSpacing[0] = false;
        _1390[0] = 32;
        _1387++;
    }
    clusterRight_1 = 15;
    for (;;)
    {
        bool _1844_ladder_break = false;
        do
        {
            if (!(clusterRight_1 > 0))
            {
                _1844_ladder_break = true;
                break;
            }
            if (clusterRight_1 >= _1387)
            {
                _1393 = true;
            }
            else
            {
                _1393 = !knotBlueFixed[clusterRight_1];
            }
            if (_1393)
            {
                break;
            }
            clusterStems_1 = 15;
            for (;;)
            {
                bool _1854_ladder_break = false;
                do
                {
                    if (!(clusterStems_1 > 0))
                    {
                        _1854_ladder_break = true;
                        break;
                    }
                    if (clusterStems_1 > clusterRight_1)
                    {
                        break;
                    }
                    int _3286 = clusterStems_1 - 1;
                    if (knotBlueFixed[_3286])
                    {
                        _1854_ladder_break = true;
                        break;
                    }
                    if (knotNaturalSpacing[_3286])
                    {
                        spacing = 9.9999999747524270787835121154785e-07;
                    }
                    else
                    {
                        spacing = grid;
                    }
                    _1389[_3286] = min(_1389[_3286], _1389[clusterStems_1] - spacing);
                    break;
                } while(false);
                if (_1854_ladder_break)
                {
                    break;
                }
                clusterStems_1--;
                continue;
            }
            break;
        } while(false);
        if (_1844_ladder_break)
        {
            break;
        }
        clusterRight_1--;
        continue;
    }
    i = 1;
    for (;;)
    {
        bool _1876_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1876_ladder_break = true;
                break;
            }
            if (i >= _1387)
            {
                _1876_ladder_break = true;
                break;
            }
            int _3335 = i - 1;
            if (_1389[i] <= _1389[_3335])
            {
                _1389[i] = _1389[_3335] + grid;
            }
            break;
        } while(false);
        if (_1876_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    if (_1386.fadeEnabled != 0)
    {
        _1393 = _1385 > _1386.fadeStart;
    }
    else
    {
        _1393 = false;
    }
    if (_1393)
    {
        float span = _1386.fadeFull - _1386.fadeStart;
        if (span <= 0.0)
        {
            _1393 = true;
        }
        else
        {
            _1393 = _1385 >= _1386.fadeFull;
        }
        if (_1393)
        {
            spacing = 1.0;
        }
        else
        {
            spacing = (_1385 - _1386.fadeStart) / span;
        }
        i = 0;
        for (;;)
        {
            bool _1900_ladder_break = false;
            do
            {
                if (!(i < 16))
                {
                    _1900_ladder_break = true;
                    break;
                }
                if (i >= _1387)
                {
                    _1900_ladder_break = true;
                    break;
                }
                _1389[i] += ((_1388[i] - _1389[i]) * spacing);
                break;
            } while(false);
            if (_1900_ladder_break)
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
        bool _1913_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _1913_ladder_break = true;
                break;
            }
            if (i >= _1387)
            {
                _1913_ladder_break = true;
                break;
            }
            if (!snailAhFinite(_1388[i]))
            {
                _1393 = true;
            }
            else
            {
                _1393 = !snailAhFinite(_1389[i]);
            }
            if (_1393)
            {
                _1387 = 0;
                return false;
            }
            break;
        } while(false);
        if (_1913_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    return true;
}

void snailAhPackAxis(int count, float targets[16], int sources[16], inout vec4 packedTargets[4], inout uvec4 packedSources)
{
    int i = 0;
    for (;;)
    {
        bool _3479_ladder_break = false;
        do
        {
            if (!(i < 4))
            {
                _3479_ladder_break = true;
                break;
            }
            packedTargets[i] = vec4(0.0);
            break;
        } while(false);
        if (_3479_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
    packedSources = uvec4(4294967295u);
    if (count > 16)
    {
        packedSources.x = (packedSources.x & 4294967040u) | 254u;
        return;
    }
    i = 0;
    for (;;)
    {
        bool _3491_ladder_break = false;
        do
        {
            if (!(i < 16))
            {
                _3491_ladder_break = true;
                break;
            }
            if (i >= count)
            {
                _3491_ladder_break = true;
                break;
            }
            int _3536 = i >> 2;
            int _3539 = i & 3;
            packedTargets[_3536][_3539] = targets[i];
            uint _3548 = uint(_3539 * 8);
            packedSources[_3536] = (packedSources[_3536] & (~(255u << _3548))) | ((uint(sources[i]) & 255u) << _3548);
            break;
        } while(false);
        if (_3491_ladder_break)
        {
            break;
        }
        i++;
        continue;
    }
}

AutohintVertexResult snailAutohintVertex(TextVertexIn _126, uint _127, mat4 _128, vec2 _129, int _130, uvec4 _131, uvec3 _132)
{
    TextVertexResult _229 = snailTextVertex(_126, _127, _128, _129, _130);
    AutohintVertexResult r;
    r.position = _229.position;
    r.paint = _229.color * _229.tint;
    r.texcoord_layer = vec3(_229.texcoord, _126.bnd.w);
    r.info = ivec2(int(_126.glyph.x & 65535u), int(_126.glyph.x >> 16u));
    r.policy0 = _131;
    r.policy1 = _132;
    if (_127 != 0u)
    {
        int i = 0;
        for (;;)
        {
            bool _187_ladder_break = false;
            do
            {
                if (!(i < 4))
                {
                    _187_ladder_break = true;
                    break;
                }
                r.x_targets[i] = vec4(0.0);
                r.y_targets[i] = vec4(0.0);
                break;
            } while(false);
            if (_187_ladder_break)
            {
                break;
            }
            i++;
            continue;
        }
        r.x_sources = uvec4(4294967295u);
        r.y_sources = uvec4(4294967295u);
        return r;
    }
    ivec2 info_base = r.info;
    vec2 scale;
    bool _538 = snailAhAffineScale(_128, _129, _126.xform, scale);
    if (!_538)
    {
        vec4 _140[4] = r.x_targets;
        uvec4 _141 = r.x_sources;
        snailAhMarkFallback(_140, _141);
        r.x_targets = _140;
        r.x_sources = _141;
        vec4 _142[4] = r.y_targets;
        uvec4 _143 = r.y_sources;
        snailAhMarkFallback(_142, _143);
        r.y_targets = _142;
        r.y_sources = _143;
        return r;
    }
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    float _787 = snailWarpF(info_base, 0, 8);
    float _862 = snailWarpF(info_base, 0, 9);
    SnailAutohintPolicy policy;
    bool _863 = snailDecodeAutohintPolicy(_131, _132, policy);
    bool valid;
    if (_863)
    {
        valid = snailAhFinite(_787);
    }
    else
    {
        valid = false;
    }
    if (valid)
    {
        valid = _787 >= 0.0;
    }
    else
    {
        valid = false;
    }
    if (valid)
    {
        valid = snailAhFinite(_862);
    }
    else
    {
        valid = false;
    }
    if (valid)
    {
        valid = _862 >= 0.0;
    }
    else
    {
        valid = false;
    }
    if (valid)
    {
        bool _1264 = snailAhCount(16, snailWarpF(info_base, 0, 10), blueCount);
        valid = _1264;
    }
    else
    {
        valid = false;
    }
    int xRun = 12 + (2 * blueCount);
    if (valid)
    {
        bool _1324 = snailAhCount(16, snailWarpF(info_base, xRun, 0), featureXCount);
        valid = _1324;
    }
    else
    {
        valid = false;
    }
    int yRun = (xRun + 1) + (4 * featureXCount);
    if (valid)
    {
        bool _1336 = snailAhCount(16, snailWarpF(info_base, yRun, 0), featureYCount);
        valid = _1336;
    }
    else
    {
        valid = false;
    }
    if (!valid)
    {
        vec4 _153[4] = r.x_targets;
        uvec4 _154 = r.x_sources;
        snailAhMarkFallback(_153, _154);
        r.x_targets = _153;
        r.x_sources = _154;
        vec4 _155[4] = r.y_targets;
        uvec4 _156 = r.y_sources;
        snailAhMarkFallback(_155, _156);
        r.y_targets = _155;
        r.y_sources = _156;
        return r;
    }
    int xCount = 0;
    int yCount = 0;
    SnailAutohintPolicy _170 = policy;
    float xBase[16];
    float xTarget[16];
    int xSource[16];
    bool _1376 = snailFitAutohintAxis(info_base, 0, xRun, blueCount, _787, snailWarpF(info_base, 0, 11), scale.x, _170, xCount, xBase, xTarget, xSource);
    SnailAutohintPolicy _171 = policy;
    float yBase[16];
    float yTarget[16];
    int ySource[16];
    bool _3454 = snailFitAutohintAxis(info_base, 1, yRun, blueCount, _862, 0.0, scale.y, _171, yCount, yBase, yTarget, ySource);
    if (_1376)
    {
        float _172[16] = xTarget;
        int _173[16] = xSource;
        vec4 _174[4] = r.x_targets;
        uvec4 _175 = r.x_sources;
        snailAhPackAxis(xCount, _172, _173, _174, _175);
        r.x_targets = _174;
        r.x_sources = _175;
    }
    else
    {
        vec4 _176[4] = r.x_targets;
        uvec4 _177 = r.x_sources;
        snailAhMarkFallback(_176, _177);
        r.x_targets = _176;
        r.x_sources = _177;
    }
    if (_3454)
    {
        float _178[16] = yTarget;
        int _179[16] = ySource;
        vec4 _180[4] = r.y_targets;
        uvec4 _181 = r.y_sources;
        snailAhPackAxis(yCount, _178, _179, _180, _181);
        r.y_targets = _180;
        r.y_sources = _181;
    }
    else
    {
        vec4 _182[4] = r.y_targets;
        uvec4 _183 = r.y_sources;
        snailAhMarkFallback(_182, _183);
        r.y_targets = _182;
        r.y_sources = _183;
    }
    return r;
}

VsOutput vertexBody(VsInput _input, uint vertex_index)
{
    TextVertexIn v;
    v.rect = _input.rect;
    v.xform = _input.xform;
    v.origin = _input.origin;
    v.glyph = _input.glyph;
    v.bnd = _input.bnd;
    v.col = _input.col;
    v.tint = _input.tint;
    TextVertexIn _57 = v;
    AutohintVertexResult _123 = snailAutohintVertex(_57, vertex_index, spvWorkaroundRowMajor(pc.mvp), pc.viewport, pc.subpixel_order, _input.policy0, _input.policy1);
    VsOutput o;
    o.position = _123.position;
    o.paint = _123.paint;
    o.texcoord_layer = _123.texcoord_layer;
    o.info = _123.info;
    o.policy0 = _123.policy0;
    o.policy1 = _123.policy1;
    vec4 _3637[4] = _123.x_targets;
    o.x_targets0 = _3637[0];
    o.x_targets1 = _3637[1];
    o.x_targets2 = _3637[2];
    o.x_targets3 = _3637[3];
    vec4 _3650[4] = _123.y_targets;
    o.y_targets0 = _3650[0];
    o.y_targets1 = _3650[1];
    o.y_targets2 = _3650[2];
    o.y_targets3 = _3650[3];
    o.x_sources = _123.x_sources;
    o.y_sources = _123.y_sources;
    return o;
}

void main()
{
    VsInput _14 = VsInput(input_rect, input_xform, input_origin, input_glyph, input_bnd, input_col, input_tint, input_policy0, input_policy1);
    VsOutput _48 = vertexBody(_14, uint(gl_VertexID));
    gl_Position = _48.position;
    snail_io0 = _48.paint;
    snail_io1 = _48.texcoord_layer;
    snail_io2 = _48.info;
    snail_io3 = _48.policy0;
    snail_io4 = _48.policy1;
    snail_io5 = _48.x_targets0;
    snail_io6 = _48.x_targets1;
    snail_io7 = _48.x_targets2;
    snail_io8 = _48.x_targets3;
    snail_io9 = _48.y_targets0;
    snail_io10 = _48.y_targets1;
    snail_io11 = _48.y_targets2;
    snail_io12 = _48.y_targets3;
    snail_io13 = _48.x_sources;
    snail_io14 = _48.y_sources;
}

