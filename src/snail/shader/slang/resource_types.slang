// Resource aliases shared by the authored shader modules.
//
// Desktop GL and GLES use combined sampler objects. This lets Slang's direct
// GLSL backend emit ordinary sampler2D/sampler2DArray declarations instead of
// Vulkan-style separate texture/sampler objects, which require GLSL 4.50 and
// produce expensive driver IR after a SPIR-V round trip. Other targets retain
// their native separate-resource model.
module resource_types;

import binary16;
import render_abi;

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

#if defined(SNAIL_FLAT_STORAGE)
#if defined(SNAIL_TARGET_WGSL)
// WGSL has no formatted texel-buffer resource. Keep the same compact bytes in
// read-only uint storage buffers and decode them explicitly.
public typealias SnailCurveStorage = StructuredBuffer<uint>;
public typealias SnailBandStorage = StructuredBuffer<uint>;
#else
// Vulkan Buffer<T> is a uniform texel buffer; GL/HLSL/Metal use their native
// read-only formatted-buffer equivalent.
public typealias SnailCurveStorage = Buffer<float4>;
public typealias SnailBandStorage = Buffer<uint2>;
#endif
#else
public typealias SnailCurveStorage = SnailFloatTexture2DArray;
public typealias SnailBandStorage = SnailUint2Texture2DArray;
#endif

public struct SnailAtlasLayout {
    public int curve_page_texels;
    public int band_page_texels;
};

public SnailAtlasLayout snailAtlasLayout(int2 page_texels)
{
    SnailAtlasLayout layout;
    layout.curve_page_texels = page_texels.x;
    layout.band_page_texels = page_texels.y;
    return layout;
}

int snailFlatAtlasAddress(int2 loc, int page, int page_texels)
{
    return page * page_texels + loc.y * SNAIL_ATLAS_TEX_WIDTH + loc.x;
}

public float4 snailLoadCurve(
    SnailCurveStorage texture_resource,
    int2 loc,
    int page,
    SnailAtlasLayout layout)
{
#if defined(SNAIL_FLAT_STORAGE)
#if defined(SNAIL_TARGET_WGSL)
    int texel = snailFlatAtlasAddress(loc, page, layout.curve_page_texels);
    uint lo = texture_resource[texel * 2];
    uint hi = texture_resource[texel * 2 + 1];
    return float4(
        snailDecodeFloat16Exact(lo),
        snailDecodeFloat16Exact(lo >> 16u),
        snailDecodeFloat16Exact(hi),
        snailDecodeFloat16Exact(hi >> 16u));
#else
    return texture_resource.Load(snailFlatAtlasAddress(loc, page, layout.curve_page_texels));
#endif
#else
    return texture_resource.Load(int4(loc, page, 0));
#endif
}

public uint2 snailLoadBand(
    SnailBandStorage texture_resource,
    int2 loc,
    int page,
    SnailAtlasLayout layout)
{
#if defined(SNAIL_FLAT_STORAGE)
#if defined(SNAIL_TARGET_WGSL)
    uint word = texture_resource[snailFlatAtlasAddress(loc, page, layout.band_page_texels)];
    return uint2(word & 0xffffu, word >> 16u);
#else
    return texture_resource.Load(snailFlatAtlasAddress(loc, page, layout.band_page_texels));
#endif
#else
    return texture_resource.Load(int4(loc, page, 0)).xy;
#endif
}

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
