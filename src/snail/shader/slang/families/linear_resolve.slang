// Linear-resolve family (GL hosts only): the fullscreen seed/encode pass of
// the correct-blending recipe (render into a float intermediate in
// premultiplied LINEAR light, then encode back to the sRGB target). Ports
// src/snail/shader/glsl/snail_linear_resolve_body.glsl plus the demo's
// fullscreen-triangle wrapper (src/demo/render/gl/shaders.zig). The GLSL is
// the behavioral spec: every epsilon, literal, and operation order is
// preserved.
//
// Only the direct GL dialects are generated (gl_only): Vulkan and WebGPU
// demo paths have no linear-resolve pass — hardware sRGB targets cover
// them. The mode dispatch is an if/else, not a select: only the pass's
// own texture is bound during a pass (the other unit holds texture 0) and
// the dead branch must not sample it.
module linear_resolve;

import resource_types;

import color_common;

public struct SnailLinearResolveParams {
    public int mode; // 0 = seed intermediate from dst snapshot, 1 = encode to target
};

ConstantBuffer<SnailLinearResolveParams> pc;
SnailFloatTexture2D u_linear_tex;
#if defined(SNAIL_TARGET_GL)
static const SnailSamplerState u_linear_sampler = 0;
#else
SnailSamplerState u_linear_sampler;
#endif
SnailFloatTexture2D u_dst_tex;
#if defined(SNAIL_TARGET_GL)
static const SnailSamplerState u_dst_sampler = 0;
#else
SnailSamplerState u_dst_sampler;
#endif

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 uv;
};

#if defined(SNAIL_TARGET_GL)
[shader("vertex")]
VsOutput vertexMain(uint vertex_index: SV_VertexID) {
    float2 pos = float2((vertex_index == 1) ? 3.0 : -1.0,
                        (vertex_index == 2) ? 3.0 : -1.0);
    VsOutput o;
    o.uv = pos * 0.5 + 0.5;
    o.position = float4(pos, 0.0, 1.0);
    return o;
}
#else
int snailRawVertexIndex() {
    return spirv_asm {
        result:$$int = OpLoad builtin(VertexIndex:int);
    };
}

[shader("vertex")]
VsOutput vertexMain() {
    int vertex_index = snailRawVertexIndex();
    float2 pos = float2((vertex_index == 1) ? 3.0 : -1.0,
                        (vertex_index == 2) ? 3.0 : -1.0);
    VsOutput o;
    o.uv = pos * 0.5 + 0.5;
    o.position = float4(pos, 0.0, 1.0);
    return o;
}
#endif

// sRGB-encoded premultiplied -> linear premultiplied (destination seed).
float4 snailLinearResolveSeed(float4 dst_premul) {
    if (dst_premul.a <= 0.0) return float4(0.0);
    float inv_a = 1.0 / dst_premul.a;
    return float4(
        srgbToLinear(clamp(dst_premul.rgb * inv_a, 0.0, 1.0)) * dst_premul.a,
        dst_premul.a
    );
}

// Linear premultiplied -> sRGB-encoded premultiplied (target encode).
float4 snailLinearResolveEncode(float4 linear_premul) {
    return srgbEncodePremultiplied(linear_premul);
}

[shader("fragment")]
float4 fragmentMain(VsOutput input) : SV_Target {
    if (pc.mode == 0) {
        return snailLinearResolveSeed(snailSample2D(u_dst_tex, u_dst_sampler, input.uv));
    }
    return snailLinearResolveEncode(snailSample2D(u_linear_tex, u_linear_sampler, input.uv));
}
