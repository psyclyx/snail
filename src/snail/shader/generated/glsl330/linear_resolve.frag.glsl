#version 330

layout(std140) uniform SnailLinearResolveParams_std140
{
    int mode;
} pc;

uniform sampler2D SPIRV_Cross_Combinedu_dst_texu_dst_sampler;
uniform sampler2D SPIRV_Cross_Combinedu_linear_texu_linear_sampler;

in vec2 snail_io0;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

float srgbDecode(float c)
{
    float _71;
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

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

vec4 snailLinearResolveSeed(vec4 dst_premul)
{
    if (dst_premul.w <= 0.0)
    {
        return vec4(0.0);
    }
    return vec4(srgbToLinear(clamp(dst_premul.xyz * (1.0 / dst_premul.w), vec3(0.0), vec3(1.0))) * dst_premul.w, dst_premul.w);
}

float srgbEncode(float c)
{
    float _142;
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

vec4 snailLinearResolveEncode(vec4 linear_premul)
{
    return srgbEncodePremultiplied(linear_premul);
}

void main()
{
    if (pc.mode == 0)
    {
        vec4 _36 = texture(SPIRV_Cross_Combinedu_dst_texu_dst_sampler, snail_io0);
        entryPointParam_fragmentMain = snailLinearResolveSeed(_36);
        return;
    }
    vec4 _113 = texture(SPIRV_Cross_Combinedu_linear_texu_linear_sampler, snail_io0);
    entryPointParam_fragmentMain = snailLinearResolveEncode(_113);
}

