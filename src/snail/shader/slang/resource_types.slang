// Resource aliases shared by the authored shader modules.
//
// Desktop GL and GLES use combined sampler objects. This lets Slang's direct
// GLSL backend emit ordinary sampler2D/sampler2DArray declarations instead of
// Vulkan-style separate texture/sampler objects, which require GLSL 4.50 and
// produce expensive driver IR after a SPIR-V round trip. Other targets retain
// their native separate-resource model.
module resource_types;

#if defined(SNAIL_TARGET_GL)
public typealias SnailFloatTexture2DArray = Sampler2DArray<float4>;
public typealias SnailUint2Texture2DArray = Sampler2DArray<uint2>;
public typealias SnailFloatTexture2D = Sampler2D<float4>;
public typealias SnailUintTexture2D = Sampler2D<uint>;
public typealias SnailSamplerState = int;
#else
public typealias SnailFloatTexture2DArray = Texture2DArray<float4>;
public typealias SnailUint2Texture2DArray = Texture2DArray<uint2>;
public typealias SnailFloatTexture2D = Texture2D<float4>;
public typealias SnailUintTexture2D = Texture2D<uint>;
public typealias SnailSamplerState = SamplerState;
#endif

public float4 snailSample2D(
    SnailFloatTexture2D texture_resource,
    SnailSamplerState sampler_resource,
    float2 uv)
{
#if defined(SNAIL_TARGET_GL)
    return texture_resource.Sample(uv);
#else
    return texture_resource.Sample(sampler_resource, uv);
#endif
}

public float4 snailSample2DArray(
    SnailFloatTexture2DArray texture_resource,
    SnailSamplerState sampler_resource,
    float3 uv)
{
#if defined(SNAIL_TARGET_GL)
    return texture_resource.Sample(uv);
#else
    return texture_resource.Sample(sampler_resource, uv);
#endif
}
