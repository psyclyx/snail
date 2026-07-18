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
//!   2. Builds a `VkGraphicsPipeline` with `vert_spv` + `frag_text_spv`,
//!      the vertex input from `vertexInputBinding()` / `vertexInputAttributes()`,
//!      premultiplied-over blend, against their own render pass.
//!   3. Per draw: binds snail's descriptor set + pipeline, pushes a
//!      `PushConstants`, binds the `emit` words as the per-instance vertex
//!      buffer + a 6-index `QUAD_INDICES` index buffer, and issues
//!      `vkCmdDrawIndexed(INDICES_PER_GLYPH, glyph_count, ...)`.

const std = @import("std");
const snail = @import("snail");
const vertex = snail.render.vertex;
const subpixel_policy = snail.render.subpixel;
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
/// `DrawState`. This is the single source of truth the all-in-one renderer and
/// an embeddable caller both use, so their pushed constants are identical.
/// `grayscale` selects the non-subpixel path (the text-coverage recipe today).
pub fn textPushConstants(draw_state: snail.DrawState, local_layer_base: u32, grayscale: bool) PushConstants {
    return .{
        .mvp = draw_state.mvp.data,
        .viewport = .{ draw_state.surface.pixel_width, draw_state.surface.pixel_height },
        .subpixel_order = @intFromEnum(if (grayscale) snail.SubpixelOrder.none else draw_state.raster.subpixel_order),
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

/// Compiled SPIR-V. All shape families share `vert_spv` and the single-binding
/// vertex input above; they differ only in fragment shader (and subpixel also
/// in blend). Callers hand these to `vkCreateShaderModule`.
pub const vert_spv = vk_shaders.vert_spv;
pub const frag_text_spv = vk_shaders.frag_text_spv;
pub const frag_hinted_text_spv = vk_shaders.frag_hinted_text_spv;
pub const frag_autohint_spv = vk_shaders.frag_autohint_spv;
pub const frag_colr_spv = vk_shaders.frag_colr_spv;
pub const frag_path_spv = vk_shaders.frag_path_spv;
pub const frag_text_subpixel_dual_spv = vk_shaders.frag_text_subpixel_dual_spv;

// ── Blend ──

/// Per-family blend. Every family blends premultiplied-over except subpixel,
/// which needs dual-source (and the `dualSrcBlend` device feature).
pub const Blend = enum { premultiplied, dual_source };

/// The color-blend attachment state for a family's blend. Single source of
/// truth shared with the all-in-one renderer so caller pipelines match exactly.
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
/// variant of regular text; the rest map 1:1 to `GlyphRunKind`.
pub const Family = enum { text, colr, path, hinted_text, autohint, subpixel };

/// The frag module + blend the caller's pipeline for `family` must use. Vertex
/// input, descriptor-set layout and push constants are the same for all.
pub const PipelineRecipe = struct {
    frag_spv: []align(4) const u8,
    blend: Blend,
    /// Subpixel needs the `dualSrcBlend` device feature; gate on it and fall
    /// back to `.text` (grayscale) when unavailable.
    requires_dual_src_blend: bool = false,
};

pub fn recipe(family: Family) PipelineRecipe {
    return switch (family) {
        .text => .{ .frag_spv = frag_text_spv, .blend = .premultiplied },
        .colr => .{ .frag_spv = frag_colr_spv, .blend = .premultiplied },
        .path => .{ .frag_spv = frag_path_spv, .blend = .premultiplied },
        .hinted_text => .{ .frag_spv = frag_hinted_text_spv, .blend = .premultiplied },
        .autohint => .{ .frag_spv = frag_autohint_spv, .blend = .premultiplied },
        .subpixel => .{ .frag_spv = frag_text_subpixel_dual_spv, .blend = .dual_source, .requires_dual_src_blend = true },
    };
}

// ── Glyph-run dispatch ──

/// The `emit` byte stream is a sequence of runs, each a maximal span of glyphs
/// of one kind. A caller walks the runs and binds the matching family pipeline
/// per run — exactly what the all-in-one renderer does internally.
pub const GlyphRunKind = subpixel_policy.GlyphRunKind;

pub const GlyphRun = struct {
    kind: GlyphRunKind,
    glyph_start: usize,
    glyph_count: usize,
};

pub const GlyphRunIterator = struct {
    words: []const u32,
    total_glyphs: usize,
    pos: usize = 0,

    pub fn next(self: *GlyphRunIterator) ?GlyphRun {
        if (self.pos >= self.total_glyphs) return null;
        const kind = subpixel_policy.glyphRunKind(self.words, self.pos);
        const end = subpixel_policy.glyphRunEnd(self.words, self.pos, kind);
        defer self.pos = end;
        return .{ .kind = kind, .glyph_start = self.pos, .glyph_count = end - self.pos };
    }
};

/// Iterate the glyph runs in a segment's `emit` words.
pub fn glyphRuns(words: []const u32) GlyphRunIterator {
    return .{ .words = words, .total_glyphs = words.len / vertex.WORDS_PER_INSTANCE };
}

/// The family whose pipeline draws a run of `kind` in the grayscale
/// (non-subpixel) configuration. Regular text maps to `.text`; opt into
/// `.subpixel` separately when the device supports dual-source blend.
pub fn familyForRunKind(kind: GlyphRunKind) Family {
    return familyForRun(kind, .grayscale);
}

/// The subpixel decision for regular text: `grayscale` uses the `.text`
/// pipeline, `subpixel_dual_source` uses `.subpixel` (dual-source blend).
pub const TextRenderMode = subpixel_policy.TextRenderMode;

/// Choose the render mode for a regular-text run, matching the all-in-one
/// renderer. Returns `.grayscale` unless subpixel is requested (`draw_state`'s
/// subpixel order), the run is axis-aligned enough, and `supports_dual_src` is
/// true. The caller passes the result to `familyForRun` and to
/// `textPushConstants`'s `grayscale` flag (`mode == .grayscale`).
pub fn textRenderMode(
    words: []const u32,
    glyph_start: usize,
    glyph_count: usize,
    draw_state: snail.DrawState,
    supports_dual_src: bool,
) TextRenderMode {
    return subpixel_policy.chooseTextRenderModeRange(
        words,
        glyph_start,
        glyph_count,
        draw_state.mvp,
        true, // allow_subpixel
        draw_state.raster.subpixel_order,
        supports_dual_src,
    );
}

/// The family whose pipeline draws a run. Non-regular kinds map 1:1; regular
/// text picks `.text` or `.subpixel` from `regular_mode` (see `textRenderMode`).
pub fn familyForRun(kind: GlyphRunKind, regular_mode: TextRenderMode) Family {
    return switch (kind) {
        .regular => switch (regular_mode) {
            .grayscale => .text,
            .subpixel_dual_source => .subpixel,
        },
        .colr => .colr,
        .path => .path,
        .hinted_text => .hinted_text,
        .autohint => .autohint,
    };
}
