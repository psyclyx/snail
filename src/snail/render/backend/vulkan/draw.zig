//! Vulkan draw entry. Walks `DrawRecords.segments`, binds the
//! matching `VulkanPreparedPages` cache's shared descriptor set, and
//! dispatches each segment through either the heterogeneous draw path
//! (one instanced draw per kind run) or the replicated path (real
//! hardware GPU instancing via `VK_EXT_vertex_attribute_divisor`).
//!
//! Reaches into `VulkanPipeline` only for the persistent vertex buffer,
//! push-constant helper, and pipeline cache.

const std = @import("std");

const vulkan_types = @import("types.zig");
const subpixel_policy = @import("../subpixel_policy.zig");
const vertex = @import("../../format/vertex.zig");
const snail_mod = @import("../../../root.zig");
const vulkan_upload_new = @import("prepared_pages.zig");
const draw_records_mod = @import("../../../picture/draw_records.zig");
const pipeline_constants = @import("constants.zig");
const vulkan_graphics = @import("graphics_pipeline.zig");
const pipeline_mod = @import("pipeline.zig");

pub const vk = vulkan_types.vk;
const VulkanPipeline = pipeline_mod.VulkanPipeline;
const ReplicatedKind = pipeline_mod.ReplicatedKind;
const DrawState = snail_mod.DrawState;

pub const DrawError = VulkanPipeline.DrawError;

/// Walk `DrawRecords.segments`, bind each segment's matching
/// `VulkanPreparedPages` cache, dispatch the encoded instances through
/// the existing pipeline + push-constant chain. Mirrors the GL
/// `draw`: subpixel runs use dual-source when available, path /
/// colr / hinted_text bind their respective pipelines.
pub fn draw(
    self: *VulkanPipeline,
    scratch: std.mem.Allocator,
    draw_state: DrawState,
    records: draw_records_mod.DrawRecords,
    caches: []const *const vulkan_upload_new.VulkanPreparedPages,
) DrawError!void {
    const cmd = self.active_cmd orelse return error.MissingCommandBuffer;
    vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    setViewportAndScissor(cmd, draw_state.surface.pixel_width, draw_state.surface.pixel_height);

    for (records.segments) |seg| {
        const cache = findCache(caches, seg.binding.pool) orelse return error.MissingBinding;
        if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) return error.StaleBinding;
        const desc_set = cache.descriptorSet();
        if (desc_set == null) return error.MissingBinding;
        const seg_words = records.words[seg.words_offset..][0..seg.words_len];
        switch (seg.kind) {
            .heterogeneous => try drawHeterogeneous(self, cmd, desc_set, draw_state, seg_words),
            .replicated => try drawReplicated(self, scratch, cmd, desc_set, draw_state, seg, seg_words),
        }
    }
}

fn drawHeterogeneous(
    self: *VulkanPipeline,
    cmd: vk.VkCommandBuffer,
    desc_set: vk.VkDescriptorSet,
    draw_state: DrawState,
    vertices: []const u32,
) DrawError!void {
    const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
    if (total_glyphs == 0) return;

    vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&desc_set), 0, null);

    const allow_subpixel = true;

    var run_start: usize = 0;
    while (run_start < total_glyphs) {
        const run_kind = subpixel_policy.glyphRunKind(vertices, run_start);
        const run_end = subpixel_policy.glyphRunEnd(vertices, run_start, run_kind);
        const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
            .grayscale
        else
            subpixel_policy.chooseTextRenderModeRange(
                vertices,
                run_start,
                run_end - run_start,
                draw_state.mvp,
                allow_subpixel,
                draw_state.raster.subpixel_order,
                self.ctx.supports_dual_source_blend,
            );
        const pip = switch (run_kind) {
            .regular => switch (run_mode) {
                .grayscale => try self.ensureTextPipeline(),
                .subpixel_dual_source => try self.ensureTextSubpixelDualPipeline(),
            },
            .colr => try self.ensureColrPipeline(),
            .path => try self.ensurePathPipeline(),
            .hinted_text => try self.ensureHintedTextPipeline(),
        };
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);
        // The new path stores absolute texture-array layer in the
        // per-instance data; no bank-local offset is needed.
        self.pushTextConstants(cmd, draw_state, 0, run_mode);
        try self.drawGlyphRange(vertices, run_start, run_end - run_start);
        run_start = run_end;
    }
}

/// Real hardware GPU instancing for the Vulkan replicated path. See
/// the GL state.zig counterpart for the design notes — uses
/// `VK_EXT_vertex_attribute_divisor` on binding 0 so shape attrs stay
/// constant within an M-instance draw while overrides cycle per
/// instance. One inner instanced draw is issued per shape; for N
/// shapes that's N draw calls of M instances each.
fn drawReplicated(
    self: *VulkanPipeline,
    _: std.mem.Allocator,
    cmd: vk.VkCommandBuffer,
    desc_set: vk.VkDescriptorSet,
    draw_state: DrawState,
    seg: draw_records_mod.DrawSegment,
    seg_words: []const u32,
) DrawError!void {
    const n = seg.shape_count;
    const m = seg.override_count;
    if (n == 0 or m == 0) return;
    const WORDS_PER_OVERRIDE: usize = 8;
    const expected = @as(usize, n) * vertex.WORDS_PER_INSTANCE + @as(usize, m) * WORDS_PER_OVERRIDE;
    if (seg_words.len != expected) return error.MalformedSegment;

    const shape_bytes: usize = @as(usize, n) * vertex.BYTES_PER_INSTANCE;
    const override_bytes: usize = @as(usize, m) * 32;
    const total_bytes: usize = shape_bytes + override_bytes;

    // Upload the segment's words into the persistent vertex buffer.
    const upload_slot_avail = pipeline_constants.UPLOAD_SLOT_BYTES - self.upload_cursor;
    if (total_bytes > upload_slot_avail) return error.VulkanUploadSlotExhausted;
    const ring_base: vk.VkDeviceSize = @as(vk.VkDeviceSize, self.active_upload_slot) * pipeline_constants.UPLOAD_SLOT_BYTES + self.upload_cursor;
    {
        const dst = self.persistent_map.?[ring_base..][0..total_bytes];
        const src: [*]const u8 = @ptrCast(seg_words.ptr);
        @memcpy(dst, src[0..total_bytes]);
    }
    self.upload_cursor += total_bytes;

    vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&desc_set), 0, null);

    const allow_subpixel = true;
    const shape_words_view = seg_words[0..@as(usize, n) * vertex.WORDS_PER_INSTANCE];

    var run_start: usize = 0;
    while (run_start < n) {
        const run_kind = subpixel_policy.glyphRunKind(shape_words_view, run_start);
        const run_end_in_shapes = subpixel_policy.glyphRunEnd(shape_words_view, run_start, run_kind);
        const run_shape_count = run_end_in_shapes - run_start;
        const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
            .grayscale
        else
            subpixel_policy.chooseTextRenderModeRange(
                shape_words_view,
                run_start,
                run_shape_count,
                draw_state.mvp,
                allow_subpixel,
                draw_state.raster.subpixel_order,
                self.ctx.supports_dual_source_blend,
            );

        const rep_kind: ReplicatedKind = switch (run_kind) {
            .regular => switch (run_mode) {
                .grayscale => .text,
                .subpixel_dual_source => .text_subpixel_dual,
            },
            .colr => .colr,
            .path => .path,
            .hinted_text => .hinted_text,
        };
        const pip = try ensureReplicatedPipeline(self, rep_kind, m);
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);
        self.pushTextConstants(cmd, draw_state, 0, run_mode);

        // One M-instance draw per shape in the run. Shape stream's
        // offset shifts by 64 bytes per shape; override stream's
        // offset stays fixed.
        var s: usize = run_start;
        while (s < run_end_in_shapes) : (s += 1) {
            const shape_off: vk.VkDeviceSize = ring_base + @as(vk.VkDeviceSize, @intCast(s * vertex.BYTES_PER_INSTANCE));
            const override_off: vk.VkDeviceSize = ring_base + @as(vk.VkDeviceSize, @intCast(shape_bytes));
            const buffers = [2]vk.VkBuffer{ self.vertex_buffer, self.vertex_buffer };
            const offsets = [2]vk.VkDeviceSize{ shape_off, override_off };
            vk.vkCmdBindVertexBuffers(cmd, 0, 2, &buffers, &offsets);
            vk.vkCmdDrawIndexed(cmd, 6, @intCast(m), 0, 0, 0);
        }
        run_start = run_end_in_shapes;
    }
}

fn ensureReplicatedPipeline(self: *VulkanPipeline, kind: ReplicatedKind, m: u32) !vk.VkPipeline {
    for (self.replicated_pipelines[0..self.replicated_pipeline_count]) |slot| {
        if (slot.kind == kind and slot.m == m) return slot.pipeline;
    }
    if (self.replicated_pipeline_count >= self.replicated_pipelines.len) return error.ReplicatedPipelineCacheFull;
    const vk_shaders_mod = @import("vulkan_shaders");
    const frag_code: []const u8 = switch (kind) {
        .text => vk_shaders_mod.frag_text_spv,
        .text_subpixel_dual => vk_shaders_mod.frag_text_subpixel_dual_spv,
        .colr => vk_shaders_mod.frag_colr_spv,
        .path => vk_shaders_mod.frag_path_spv,
        .hinted_text => vk_shaders_mod.frag_hinted_text_spv,
    };
    const blend_mode: vulkan_graphics.BlendMode = if (kind == .text_subpixel_dual) .dual_source else .premultiplied;
    const pip = try vulkan_graphics.createReplicatedPipeline(self, frag_code, blend_mode, m);
    self.replicated_pipelines[self.replicated_pipeline_count] = .{ .kind = kind, .m = m, .pipeline = pip };
    self.replicated_pipeline_count += 1;
    return pip;
}

fn setViewportAndScissor(cmd: vk.VkCommandBuffer, viewport_w: f32, viewport_h: f32) void {
    const vp = vk.VkViewport{
        .x = 0,
        .y = viewport_h,
        .width = viewport_w,
        .height = -viewport_h,
        .minDepth = 0,
        .maxDepth = 1,
    };
    vk.vkCmdSetViewport(cmd, 0, 1, &vp);

    const scissor = vk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = @intFromFloat(viewport_w), .height = @intFromFloat(viewport_h) },
    };
    vk.vkCmdSetScissor(cmd, 0, 1, &scissor);
}

fn findCache(
    caches: anytype,
    pool: *snail_mod.PagePool,
) ?@TypeOf(caches[0]) {
    for (caches) |c| {
        if (c.pool == pool) return c;
    }
    return null;
}
