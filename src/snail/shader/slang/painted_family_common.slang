// Shared host ABI and fragment input for the COLR and arbitrary-path
// families. Both fragment families pair with the regular text vertex
// artifact, whose output has this exact location/type contract.
module painted_family_common;

public struct PaintedFragmentInput {
    public float4 position : SV_Position;
    [[vk::location(0)]] public float4 color : TEXCOORD0;
    [[vk::location(1)]] public float2 texcoord : TEXCOORD1;
    [[vk::location(2)]] public nointerpolation float4 banding : TEXCOORD2;
    [[vk::location(3)]] public nointerpolation int4 glyph : TEXCOORD3;
    [[vk::location(4)]] public float4 tint : TEXCOORD4;
};
