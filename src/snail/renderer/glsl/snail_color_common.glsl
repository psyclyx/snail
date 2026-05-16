#ifndef SNAIL_COLOR_COMMON_GLSL
#define SNAIL_COLOR_COMMON_GLSL

float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float srgbEncode(float c) {
    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

vec3 linearToSrgb(vec3 color) {
    return vec3(
        srgbEncode(max(color.r, 0.0)),
        srgbEncode(max(color.g, 0.0)),
        srgbEncode(max(color.b, 0.0))
    );
}

vec3 srgbToLinear(vec3 color) {
    return vec3(
        srgbDecode(color.r),
        srgbDecode(color.g),
        srgbDecode(color.b)
    );
}

vec4 premultiplyColor(vec4 color, float cov) {
    float alpha = color.a * cov;
    return vec4(color.rgb * alpha, alpha);
}

// Convert a linear-premultiplied color to sRGB-encoded-premultiplied. The
// caller only uses this when shader-side storage encoding is required.
vec4 srgbEncodePremultiplied(vec4 premul) {
    if (premul.a <= 0.0) return vec4(0.0);
    float inv_a = 1.0 / premul.a;
    return vec4(linearToSrgb(premul.rgb * inv_a) * premul.a, premul.a);
}

#endif
