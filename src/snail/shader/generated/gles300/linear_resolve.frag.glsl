#version 300 es
precision highp float;
precision highp int;

layout(std140) uniform SnailLinearResolveParams_std140
{
    int mode;
} pc;

uniform highp sampler2D SPIRV_Cross_Combinedu_dst_texu_dst_sampler;
uniform highp sampler2D SPIRV_Cross_Combinedu_linear_texu_linear_sampler;

in highp vec2 snail_io0;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

highp float srgbDecode(highp float c)
{
    highp float _71;
    if (c <= 0.040449999272823333740234375)
    {
        _71 = c / 12.9200000762939453125;
    }
    else
    {
        _71 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _71;
}

highp vec3 srgbToLinear(highp vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

highp vec4 snailLinearResolveSeed(highp vec4 dst_premul)
{
    if (dst_premul.w <= 0.0)
    {
        return vec4(0.0);
    }
    return vec4(srgbToLinear(clamp(dst_premul.xyz * (1.0 / dst_premul.w), vec3(0.0), vec3(1.0))) * dst_premul.w, dst_premul.w);
}

highp float srgbEncode(highp float c)
{
    highp float _142;
    if (c <= 0.003130800090730190277099609375)
    {
        _142 = c * 12.9200000762939453125;
    }
    else
    {
        _142 = (1.05499994754791259765625 * pow(c, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
    }
    return _142;
}

highp vec3 linearToSrgb(highp vec3 color)
{
    return vec3(srgbEncode(max(color.x, 0.0)), srgbEncode(max(color.y, 0.0)), srgbEncode(max(color.z, 0.0)));
}

highp vec4 srgbEncodePremultiplied(highp vec4 premul)
{
    if (premul.w <= 0.0)
    {
        return vec4(0.0);
    }
    return vec4(linearToSrgb(premul.xyz * (1.0 / premul.w)) * premul.w, premul.w);
}

highp vec4 snailLinearResolveEncode(highp vec4 linear_premul)
{
    return srgbEncodePremultiplied(linear_premul);
}

void main()
{
    if (pc.mode == 0)
    {
        highp vec4 _36 = texture(SPIRV_Cross_Combinedu_dst_texu_dst_sampler, snail_io0);
        entryPointParam_fragmentMain = snailLinearResolveSeed(_36);
        return;
    }
    highp vec4 _113 = texture(SPIRV_Cross_Combinedu_linear_texu_linear_sampler, snail_io0);
    entryPointParam_fragmentMain = snailLinearResolveEncode(_113);
}

