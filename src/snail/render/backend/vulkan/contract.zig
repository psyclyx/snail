//! Public embeddable-pipeline contract for the Vulkan text-coverage path.
//!
//! An embeddable caller owns their own `VkPipeline` — snail owns the font data
//! and hands over the resources to sample plus the *contract* the caller's
//! pipeline must match. This module is the stable, all-in-one-renderer-
//! independent home for that contract: the push-constant layout, the
//! descriptor binding order, the vertex-input descriptors, the quad index
//! pattern, and the compiled shader modules. It has no dependency on the
//! `VulkanPipeline` all-in-one renderer, so it survives that renderer's
//! removal (embeddable-only end state).
//!
//! To build a compatible text-coverage pipeline, a caller:
//!   1. Builds a `VkPipelineLayout` from snail's descriptor-set layout
//!      (`coverage.VulkanBackend.descriptorSetLayout()`) + a push-constant
//!      range of `PUSH_CONSTANT_SIZE` bytes at offset 0, stages
//!      `PUSH_CONSTANT_STAGE_FLAGS`.
//!   2. Builds a `VkGraphicsPipeline` with `vert_spv` + `frag_text_spv`,
//!      the vertex input from `vertexInputBinding()` / `vertexInputAttributes()`,
//!      premultiplied-over blend, against their own render pass.
//!   3. Per draw: binds snail's descriptor set + pipeline, pushes a
//!      `PushConstants`, binds the `emit` words as the per-instance vertex
//!      buffer + a 6-index `QUAD_INDICES` index buffer, and issues
//!      `vkCmdDrawIndexed(INDICES_PER_GLYPH, glyph_count, ...)`.

const vertex = @import("snail_core").files.format_vertex;
const vulkan_types = @import("types.zig");
const vk_shaders = @import("vulkan_shaders");

pub const vk = vulkan_types.vk;

// ── Push constants ──

/// Per-draw push-constant block. `extern` + fixed 96-byte size to match the
/// GLSL declaration in the compiled shader modules.
pub const PushConstants = extern struct {
    mvp: [16]f32, // mat4, column-major
    viewport: [2]f32,
    subpixel_order: i32 = 1, // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    output_srgb: i32 = 0, // 0 = emit linear, 1 = sRGB-encode before write
    layer_base: i32 = 0,
    coverage_exponent: f32 = 1.0,
    dither_scale: f32 = 1.0 / 255.0, // gradient dither amplitude; 0 for float targets
    mask_output: i32 = 0, // 1 = single-channel mask target: emit painted alpha
};

comptime {
    if (@sizeOf(PushConstants) != 96) @compileError("PushConstants must be 96 bytes");
}

/// Size of the push-constant range the caller's pipeline layout must declare.
pub const PUSH_CONSTANT_SIZE: u32 = @sizeOf(PushConstants);

/// Shader stages that read the push constants.
pub const PUSH_CONSTANT_STAGE_FLAGS: vk.VkShaderStageFlags =
    vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT;

// ── Descriptor binding order ──

/// Descriptor-set binding indices (all `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`,
/// stage `FRAGMENT`). See `resource_layout.zig` for the concrete layout snail
/// builds; a caller building their own must match these exactly.
pub const CURVE_BINDING: u32 = 0;
pub const BAND_BINDING: u32 = 1;
pub const LAYER_INFO_BINDING: u32 = 2;
pub const IMAGE_BINDING: u32 = 3;

// ── Vertex input ──

/// The single instance-rate vertex binding: the `emit` byte stream, one
/// `vertex.Instance` per glyph.
pub fn vertexInputBinding() vk.VkVertexInputBindingDescription {
    return .{
        .binding = 0,
        .stride = vertex.BYTES_PER_INSTANCE,
        .inputRate = vk.VK_VERTEX_INPUT_RATE_INSTANCE,
    };
}

/// The 9 vertex attributes (locations 0–8) mapping the instance stream into
/// the vertex shader inputs.
pub fn vertexInputAttributes() [9]vk.VkVertexInputAttributeDescription {
    return .{
        .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R16G16B16A16_SFLOAT, .offset = @offsetOf(vertex.Instance, "rect") },
        .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "xform") },
        .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(vertex.Instance, "origin") },
        .{ .location = 3, .binding = 0, .format = vk.VK_FORMAT_R32G32_UINT, .offset = @offsetOf(vertex.Instance, "glyph") },
        .{ .location = 4, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "band") },
        .{ .location = 5, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(vertex.Instance, "color") },
        .{ .location = 6, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(vertex.Instance, "tint") },
        .{ .location = 7, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_UINT, .offset = @offsetOf(vertex.Instance, "policy") },
        .{ .location = 8, .binding = 0, .format = vk.VK_FORMAT_R32G32B32_UINT, .offset = @offsetOf(vertex.Instance, "policy") + 16 },
    };
}

// ── Index buffer ──

/// One quad drawn per glyph instance. The caller uploads this into an index
/// buffer and draws `INDICES_PER_GLYPH` indices with `glyph_count` instances.
pub const QUAD_INDICES: [6]u32 = .{ 0, 1, 2, 0, 2, 3 };
pub const INDICES_PER_GLYPH: u32 = QUAD_INDICES.len;

// ── Shader modules ──

/// Compiled SPIR-V for the text-coverage recipe. Callers hand these to
/// `vkCreateShaderModule`.
pub const vert_spv = vk_shaders.vert_spv;
pub const frag_text_spv = vk_shaders.frag_text_spv;
