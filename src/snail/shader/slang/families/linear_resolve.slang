// Linear-resolve family (GL hosts only): the fullscreen seed/encode pass of
// the correct-blending recipe (render into a float intermediate in
// premultiplied LINEAR light, then encode back to the sRGB target). Ports
// src/snail/shader/glsl/snail_linear_resolve_body.glsl plus the demo's
// fullscreen-triangle wrapper (src/demo/render/gl/shaders.zig). The GLSL is
// the behavioral spec: every epsilon, literal, and operation order is
// preserved.
//
// Only the naga GL dialects are generated (gl_only): Vulkan and WebGPU
// demo paths have no linear-resolve pass — hardware sRGB targets cover
// them. Both stages are loop-free, so the GL legs stay on direct SPIR-V
// (vertex keeps the spirv_asm raw-VertexIndex load; fragment needs no
// via-glsl). The mode dispatch is an if/else, not a select: only the pass's
// own texture is bound during a pass (the other unit holds texture 0) and
// the dead branch must not sample it.
module linear_resolve;

import color_common;

public struct SnailLinearResolveParams {
    public int mode; // 0 = seed intermediate from dst snapshot, 1 = encode to target
};

ConstantBuffer<SnailLinearResolveParams> pc;
Texture2D<float4> u_linear_tex;
SamplerState u_linear_sampler;
Texture2D<float4> u_dst_tex;
SamplerState u_dst_sampler;

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 uv;
};

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
        return snailLinearResolveSeed(u_dst_tex.Sample(u_dst_sampler, input.uv));
    }
    return snailLinearResolveEncode(u_linear_tex.Sample(u_linear_sampler, input.uv));
}
