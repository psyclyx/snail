//! Complete pipeline contract for Snail's reference Vulkan renderer.
//!
//! This intentionally lives under `src/demo`: it includes complete SPIR-V,
//! Vulkan pipeline structs, blend state, and dispatch policy. The library
//! exports only the data ABI and includable shader pieces; applications own
//! these renderer choices.
//!
//! To build a compatible text-coverage pipeline, a caller:
//!   1. Builds a `VkPipelineLayout` from snail's descriptor-set layout
//!      (`coverage.VulkanBackend.descriptorSetLayout()`) + a push-constant
//!      range of `PUSH_CONSTANT_SIZE` bytes at offset 0, stages
//!      `PUSH_CONSTANT_STAGE_FLAGS`.
//!   2. Builds a `VkGraphicsPipeline` with `recipe(.text)`'s modules,
//!      the vertex input from `vertexInputBinding()` / `vertexInputAttributes()`,
//!      premultiplied-over blend, against their own render pass.
//!   3. Per draw: binds snail's descriptor set + pipeline, pushes a
//!      `PushConstants`, binds the `emit` words as the per-instance vertex
//!      buffer + a 6-index `QUAD_INDICES` index buffer, and issues
//!      `vkCmdDrawIndexed(INDICES_PER_GLYPH, glyph_count, ...)`.

const std = @import("std");
const snail = @import("snail");
const render_state = @import("render-state");
const vertex = snail.render.records;
const vulkan_types = @import("vulkan_types");
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

/// Build the per-draw push constants for the text-coverage recipe from a
/// `DrawState`. This is the single source of truth the reference caller and
/// an embeddable caller both use, so their pushed constants are identical.
/// `grayscale` selects the non-subpixel path (the text-coverage recipe today).
pub fn textPushConstants(draw_state: render_state.DrawState, local_layer_base: u32, grayscale: bool) PushConstants {
    return .{
        .mvp = draw_state.mvp.data,
        .viewport = .{ draw_state.surface.pixel_width, draw_state.surface.pixel_height },
        .subpixel_order = @intFromEnum(if (grayscale) render_state.SubpixelOrder.none else draw_state.raster.subpixel_order),
        .output_srgb = if (draw_state.surface.encoding.shaderEncodesSrgb()) 1 else 0,
        .layer_base = @intCast(local_layer_base),
        .coverage_exponent = draw_state.raster.coverage_transfer.shaderExponent(),
        .dither_scale = draw_state.surface.format.ditherAmplitude(),
        .mask_output = if (draw_state.surface.format.hasColor()) 0 else 1,
    };
}

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

/// Compiled SPIR-V (native Slang, from
/// `src/snail/shader/slang/families/*.slang`). The shaders declare the
/// atlas textures as sampled images (and, for the image paint, a sampler
/// aliasing the same binding), which Vulkan permits to be backed by the
/// existing COMBINED_IMAGE_SAMPLER descriptors. Autohint uses its fitting
/// vertex stage; the other families pair with `vert_text_native_spv`.
/// Callers hand these to `vkCreateShaderModule`.
pub const vert_text_native_spv = vk_shaders.vert_text_native_spv;
pub const frag_text_native_spv = vk_shaders.frag_text_native_spv;
pub const frag_colr_native_spv = vk_shaders.frag_colr_native_spv;
pub const frag_path_native_spv = vk_shaders.frag_path_native_spv;
pub const frag_tt_hinted_native_spv = vk_shaders.frag_tt_hinted_native_spv;
pub const vert_autohint_native_spv = vk_shaders.vert_autohint_native_spv;
pub const frag_autohint_native_spv = vk_shaders.frag_autohint_native_spv;
pub const frag_subpixel_native_spv = vk_shaders.frag_subpixel_native_spv;

// ── Blend ──

/// Per-family blend. Every family blends premultiplied-over except subpixel,
/// which needs dual-source (and the `dualSrcBlend` device feature).
pub const Blend = enum { premultiplied, dual_source };

/// The color-blend attachment state for a family's blend. Single source of
/// truth for caller pipelines, shared with the CPU renderer's decode path.
pub fn blendAttachment(mode: Blend) vk.VkPipelineColorBlendAttachmentState {
    // Shader outputs are premultiplied by coverage, so src factor stays ONE.
    return std.mem.zeroInit(vk.VkPipelineColorBlendAttachmentState, .{
        .blendEnable = @as(vk.VkBool32, 1),
        .srcColorBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE)),
        .dstColorBlendFactor = @as(vk.VkBlendFactor, @intCast(switch (mode) {
            .premultiplied => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dual_source => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR,
        })),
        .colorBlendOp = @as(vk.VkBlendOp, @intCast(vk.VK_BLEND_OP_ADD)),
        .srcAlphaBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE)),
        .dstAlphaBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)),
        .alphaBlendOp = @as(vk.VkBlendOp, @intCast(vk.VK_BLEND_OP_ADD)),
        .colorWriteMask = @as(vk.VkColorComponentFlags, @intCast(vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT)),
    });
}

// ── Pipeline recipes ──

/// A shape family the caller builds one pipeline for. `subpixel` is the LCD
/// variant of regular text; the rest map 1:1 to `ShapeKind`.
pub const Family = enum { text, colr, path, tt_hinted_text, autohint, subpixel };

/// The frag module + blend the caller's pipeline for `family` must use. Vertex
/// input, descriptor-set layout and push constants are the same for all.
pub const PipelineRecipe = struct {
    vert_spv: []align(4) const u8,
    frag_spv: []align(4) const u8,
    blend: Blend,
    /// Subpixel needs the `dualSrcBlend` device feature; gate on it and fall
    /// back to `.text` (grayscale) when unavailable.
    requires_dual_src_blend: bool = false,
};

pub fn recipe(family: Family) PipelineRecipe {
    return switch (family) {
        .text => .{ .vert_spv = vert_text_native_spv, .frag_spv = frag_text_native_spv, .blend = .premultiplied },
        .colr => .{ .vert_spv = vert_text_native_spv, .frag_spv = frag_colr_native_spv, .blend = .premultiplied },
        .path => .{ .vert_spv = vert_text_native_spv, .frag_spv = frag_path_native_spv, .blend = .premultiplied },
        .tt_hinted_text => .{ .vert_spv = vert_text_native_spv, .frag_spv = frag_tt_hinted_native_spv, .blend = .premultiplied },
        .autohint => .{ .vert_spv = vert_autohint_native_spv, .frag_spv = frag_autohint_native_spv, .blend = .premultiplied },
        .subpixel => .{ .vert_spv = vert_text_native_spv, .frag_spv = frag_subpixel_native_spv, .blend = .dual_source, .requires_dual_src_blend = true },
    };
}

/// The subpixel decision for regular text: `grayscale` uses the `.text`
/// pipeline, `subpixel_dual_source` uses `.subpixel` (dual-source blend).
pub const TextRenderMode = enum { grayscale, subpixel_dual_source };

/// Choose the render mode for a regular-text run, matching the reference
/// renderer. Returns `.grayscale` unless subpixel is requested (`draw_state`'s
/// subpixel order) and `supports_dual_src` is true. The caller passes the
/// result to `familyForKind` and to
/// `textPushConstants`'s `grayscale` flag (`mode == .grayscale`).
pub fn textRenderMode(
    draw_state: render_state.DrawState,
    supports_dual_src: bool,
) TextRenderMode {
    if (draw_state.raster.subpixel_order != .none and supports_dual_src) {
        return .subpixel_dual_source;
    }
    return .grayscale;
}

/// The family whose pipeline draws a segment. Non-regular kinds map 1:1; regular
/// text picks `.text` or `.subpixel` from `regular_mode` (see `textRenderMode`).
pub fn familyForKind(kind: vertex.ShapeKind, regular_mode: TextRenderMode) Family {
    return switch (kind) {
        .regular => switch (regular_mode) {
            .grayscale => .text,
            .subpixel_dual_source => .subpixel,
        },
        .colr => .colr,
        .path => .path,
        .tt_hinted_text => .tt_hinted_text,
        .autohint => .autohint,
    };
}
