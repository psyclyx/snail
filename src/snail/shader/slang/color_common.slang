// Canonical shared color-transfer implementation.
module color_common;

public float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

public float srgbEncode(float c) {
    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

public float3 linearToSrgb(float3 color) {
    return float3(
        srgbEncode(max(color.r, 0.0)),
        srgbEncode(max(color.g, 0.0)),
        srgbEncode(max(color.b, 0.0))
    );
}

public float3 srgbToLinear(float3 color) {
    return float3(
        srgbDecode(color.r),
        srgbDecode(color.g),
        srgbDecode(color.b)
    );
}

public float4 premultiplyColor(float4 color, float cov) {
    float alpha = color.a * cov;
    return float4(color.rgb * alpha, alpha);
}

// Convert a linear-premultiplied color to sRGB-encoded-premultiplied. The
// caller only uses this when shader-side storage encoding is required.
public float4 srgbEncodePremultiplied(float4 premul) {
    if (premul.a <= 0.0) return float4(0.0);
    float inv_a = 1.0 / premul.a;
    return float4(linearToSrgb(premul.rgb * inv_a) * premul.a, premul.a);
}
