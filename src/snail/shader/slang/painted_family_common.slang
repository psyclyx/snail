// Shared host ABI and fragment input for the COLR and arbitrary-path
// families. Both fragment families pair with the regular text vertex
// artifact, whose output has this exact location/type contract.
module painted_family_common;

public struct SnailPushConstants {
    public float4x4 mvp;
    public float2 viewport;
    public int subpixel_order;
    public int output_srgb;
    public int layer_base;
    public float coverage_exponent;
    public float dither_scale;
    public int mask_output;
};

public struct PaintedFragmentInput {
    public float4 position : SV_Position;
    [[vk::location(0)]] public float4 color : TEXCOORD0;
    [[vk::location(1)]] public float2 texcoord : TEXCOORD1;
    [[vk::location(2)]] public nointerpolation float4 banding : TEXCOORD2;
    [[vk::location(3)]] public nointerpolation int4 glyph : TEXCOORD3;
    [[vk::location(4)]] public float4 tint : TEXCOORD4;
};
