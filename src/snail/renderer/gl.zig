const std = @import("std");
const gl = @import("gl_bindings.zig").gl;
const gl_backend = @import("gl_backend.zig");
const shaders = @import("shaders.zig");
const subpixel_policy = @import("subpixel_policy.zig");
const upload_common = @import("upload_common.zig");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;
const snail_mod = @import("../root.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;
const TargetEncoding = snail_mod.TargetEncoding;
const Resolve = snail_mod.Resolve;
const LinearResolve = snail_mod.LinearResolve;
const PixelRect = snail_mod.PixelRect;
const IntermediateFormat = snail_mod.IntermediateFormat;
const CoverageTransfer = snail_mod.CoverageTransfer;

// ── Backend selection ──

pub const Backend = gl_backend.Backend;

// ── Shared types ──

const ProgramState = struct {
    handle: gl.GLuint = 0,
    mvp_loc: gl.GLint = -1,
    viewport_loc: gl.GLint = -1,
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    output_srgb_loc: gl.GLint = -1,
    coverage_exponent_loc: gl.GLint = -1,
    layer_tex_loc: gl.GLint = -1,
    layer_base_loc: gl.GLint = -1,
};

const FillRule = snail_mod.FillRule;

pub const TextCoverageBindings = struct {
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    layer_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    output_srgb_loc: gl.GLint = -1,
    coverage_exponent_loc: gl.GLint = -1,
    curve_tex_unit: gl.GLint = 0,
    band_tex_unit: gl.GLint = 1,
    layer_tex_unit: gl.GLint = 2,
    image_tex_unit: gl.GLint = 3,
    fill_rule: FillRule = .non_zero,
    subpixel_order: SubpixelOrder = .none,
    /// Value to write to the shader's `u_output_srgb` uniform — i.e.,
    /// whether the shader itself should sRGB-encode its output.
    output_srgb: bool = false,
    coverage_transfer: CoverageTransfer = .identity,
};

pub const text_vertex_interface = shaders.text_vertex_interface;
pub const text_fragment_interface = shaders.text_fragment_interface;
pub const text_coverage_fragment_interface = shaders.text_coverage_fragment_interface;
pub const text_fragment_body = shaders.text_fragment_body;
pub const text_coverage_fragment_body = shaders.text_coverage_fragment_body;

// ── GL 4.4 persistent mapping constants ──

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const GL33_STREAM_BYTES = RING_SEGMENT_BYTES;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

const AtlasSlot = upload_common.AtlasSlot(snail_mod.lowlevel.CurveAtlas, snail_mod.lowlevel.AtlasPage);
const ImageSlot = upload_common.ImageSlot(snail_mod.Image);

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    curve_array: gl.GLuint = 0,
    band_array: gl.GLuint = 0,
    layer_info_tex: gl.GLuint = 0,
    image_array: gl.GLuint = 0,
    atlas_slots: []AtlasSlot = &.{},
    atlas_slot_count: usize = 0,
    allocated_curve_height: u32 = 0,
    allocated_band_height: u32 = 0,
    allocated_layer_count: u32 = 0,
    atlas_has_special_text_runs: bool = false,
    image_slots: []ImageSlot = &.{},
    image_slot_count: usize = 0,
    allocated_image_width: u32 = 0,
    allocated_image_height: u32 = 0,
    allocated_image_count: u32 = 0,

    pub fn deinit(self: *PreparedResources) void {
        self.destroyAtlasTextureResources();
        self.destroyImageResources();
        self.resetAtlasUploadState();
    }

    fn destroyAtlasTextureResources(self: *PreparedResources) void {
        if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
        if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.curve_array = 0;
        self.band_array = 0;
        self.layer_info_tex = 0;
    }

    fn destroyImageResources(self: *PreparedResources) void {
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;
        self.image_slot_count = 0;
        self.allocated_image_width = 0;
        self.allocated_image_height = 0;
        self.allocated_image_count = 0;
        if (self.image_slots.len > 0) self.allocator.free(self.image_slots);
        self.image_slots = &.{};
    }

    pub fn uploadAtlases(self: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, out_views: anytype) !void {
        return self.uploadAtlasesWithOptionalCapacityModes(self.allocator, atlases, null, out_views);
    }

    pub fn uploadAtlasesWithCapacityModes(
        self: *PreparedResources,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
    ) !void {
        var layer_infos: [0]EmptyLayerInfoUpload = .{};
        var layer_info_views: [0]EmptyLayerInfoView = .{};
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(self.allocator, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
    }

    pub fn uploadAtlasesAndLayerInfoWithCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
    }

    fn uploadAtlasesWithOptionalCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
    ) !void {
        var layer_infos: [0]EmptyLayerInfoUpload = .{};
        var layer_info_views: [0]EmptyLayerInfoView = .{};
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(scratch, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
    }

    const EmptyLayerInfoUpload = struct {
        data: ?[]const f32 = null,
        width: u32 = 0,
        height: u32 = 0,
        paint_image_records: ?[]const ?snail_mod.lowlevel.CurveAtlas.PaintImageRecord = null,
    };

    const EmptyLayerInfoView = struct {
        info_row_base: u32 = 0,
    };

    fn uploadAtlasesAndLayerInfoWithOptionalCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        std.debug.assert(atlases.len == out_views.len);
        if (capacity_modes) |modes| std.debug.assert(atlases.len == modes.len);
        std.debug.assert(layer_infos.len == out_layer_info_views.len);

        if (atlases.len == 0 and layer_infos.len == 0) {
            self.destroyAtlasTextureResources();
            self.resetAtlasUploadState();
            return;
        }

        const can_incremental = layer_infos.len == 0 and self.texturesReady() and self.atlasSlotsCompatible(atlases);
        if (!can_incremental) {
            try self.rebuildTextureArrays(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
        } else if (!try self.appendTexturePages(scratch, atlases)) {
            try self.rebuildTextureArrays(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
        } else {
            self.fillAtlasViews(atlases, out_views);
            self.fillLayerInfoViews(self.atlasLayerInfoRows(), layer_infos, out_layer_info_views);
            try self.ensureAtlasImagesRegistered(scratch, atlases);
            try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
            try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
            self.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
        }
    }

    pub fn uploadImages(self: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image, out_views: anytype) !void {
        std.debug.assert(images.len == out_views.len);
        try self.ensureImagesRegistered(scratch, images);
        const ImageView = upload_common.BufferElement(@TypeOf(out_views));
        for (images, 0..) |image, i| {
            out_views[i] = self.currentImageView(ImageView, image);
        }
    }

    pub fn bindTextCoverageResources(self: *const PreparedResources, bindings: TextCoverageBindings) void {
        if (self.backend == .gl44) {
            gl.glBindTextureUnit(@intCast(bindings.curve_tex_unit), self.curve_array);
            gl.glBindTextureUnit(@intCast(bindings.band_tex_unit), self.band_array);
            if (bindings.layer_tex_loc >= 0) gl.glBindTextureUnit(@intCast(bindings.layer_tex_unit), self.layer_info_tex);
            if (bindings.image_tex_loc >= 0) gl.glBindTextureUnit(@intCast(bindings.image_tex_unit), self.image_array);
        } else {
            gl.glActiveTexture(textureUnitEnum(bindings.curve_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
            gl.glActiveTexture(textureUnitEnum(bindings.band_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
            if (bindings.layer_tex_loc >= 0) {
                gl.glActiveTexture(textureUnitEnum(bindings.layer_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
            }
            if (bindings.image_tex_loc >= 0) {
                gl.glActiveTexture(textureUnitEnum(bindings.image_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
            }
        }

        if (bindings.curve_tex_loc >= 0) gl.glUniform1i(bindings.curve_tex_loc, @intCast(bindings.curve_tex_unit));
        if (bindings.band_tex_loc >= 0) gl.glUniform1i(bindings.band_tex_loc, @intCast(bindings.band_tex_unit));
        if (bindings.layer_tex_loc >= 0) gl.glUniform1i(bindings.layer_tex_loc, @intCast(bindings.layer_tex_unit));
        if (bindings.image_tex_loc >= 0) gl.glUniform1i(bindings.image_tex_loc, @intCast(bindings.image_tex_unit));
        if (bindings.fill_rule_loc >= 0) gl.glUniform1i(bindings.fill_rule_loc, @intFromEnum(bindings.fill_rule));
        if (bindings.subpixel_order_loc >= 0) gl.glUniform1i(bindings.subpixel_order_loc, @intFromEnum(bindings.subpixel_order));
        if (bindings.output_srgb_loc >= 0) gl.glUniform1i(bindings.output_srgb_loc, @intFromBool(bindings.output_srgb));
        if (bindings.coverage_exponent_loc >= 0) gl.glUniform1f(bindings.coverage_exponent_loc, bindings.coverage_transfer.shaderExponent());
    }

    fn currentImageView(self: *const PreparedResources, comptime ImageView: type, image: *const snail_mod.Image) ImageView {
        return upload_common.currentImageView(
            ImageView,
            self.image_slots[0..],
            self.image_slot_count,
            self.allocated_image_width,
            self.allocated_image_height,
            image,
        );
    }

    fn findImageSlot(self: *const PreparedResources, image: *const snail_mod.Image) ?usize {
        return upload_common.findImageSlot(self.image_slots[0..], self.image_slot_count, image);
    }

    fn ensureAtlasImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const snail_mod.lowlevel.CurveAtlas) !void {
        var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer images.deinit(scratch);
        try upload_common.collectAtlasImages(scratch, self.image_slots, self.image_slot_count, atlases, &images);
        try self.ensureImagesRegistered(scratch, images.items);
    }

    fn ensureLayerInfoImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, layer_infos: anytype) !void {
        var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer images.deinit(scratch);
        for (layer_infos) |info| {
            const records = info.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                if (self.findImageSlot(image) != null) continue;
                var already_queued = false;
                for (images.items) |queued| {
                    if (queued == image) {
                        already_queued = true;
                        break;
                    }
                }
                if (!already_queued) try images.append(scratch, image);
            }
        }
        try self.ensureImagesRegistered(scratch, images.items);
    }

    fn ensureImageSlotCapacity(self: *PreparedResources, capacity: usize) !void {
        if (capacity <= self.image_slots.len) return;
        const next = try self.allocator.alloc(ImageSlot, capacity);
        @memset(next, ImageSlot{});
        if (self.image_slot_count > 0) @memcpy(next[0..self.image_slot_count], self.image_slots[0..self.image_slot_count]);
        if (self.image_slots.len > 0) self.allocator.free(self.image_slots);
        self.image_slots = next;
    }

    fn ensureImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image) !void {
        if (images.len == 0) return;

        var new_images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer new_images.deinit(scratch);
        var required_width = self.allocated_image_width;
        var required_height = self.allocated_image_height;
        for (images) |image| {
            required_width = @max(required_width, image.width);
            required_height = @max(required_height, image.height);
            if (self.findImageSlot(image) != null) continue;
            var already_queued = false;
            for (new_images.items) |queued| {
                if (queued == image) {
                    already_queued = true;
                    break;
                }
            }
            if (!already_queued) try new_images.append(scratch, image);
        }

        if (new_images.items.len == 0 and self.image_array != 0) return;

        try self.ensureImageSlotCapacity(self.image_slot_count + new_images.items.len);

        const required_count: u32 = @intCast(self.image_slot_count + new_images.items.len);
        const new_width = upload_common.heightCapacity(@max(required_width, 1));
        const new_height = upload_common.heightCapacity(@max(required_height, 1));
        const needs_rebuild = self.image_array == 0 or
            required_count > self.allocated_image_count or
            new_width > self.allocated_image_width or
            new_height > self.allocated_image_height;

        if (needs_rebuild) {
            for (new_images.items, 0..) |image, i| {
                self.image_slots[self.image_slot_count + i] = .{ .image = image };
            }
            self.image_slot_count += new_images.items.len;
            self.rebuildImageArray();
            return;
        }

        for (new_images.items, 0..) |image, i| {
            const slot_index = self.image_slot_count + i;
            self.image_slots[slot_index] = .{ .image = image };
            self.uploadImageLayer(image, @intCast(slot_index));
        }
        self.image_slot_count += new_images.items.len;
    }

    fn rebuildImageArray(self: *PreparedResources) void {
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;

        if (self.image_slot_count == 0) {
            self.allocated_image_width = 0;
            self.allocated_image_height = 0;
            self.allocated_image_count = 0;
            return;
        }

        var max_width: u32 = 1;
        var max_height: u32 = 1;
        for (self.image_slots[0..self.image_slot_count]) |slot| {
            const image = slot.image orelse continue;
            max_width = @max(max_width, image.width);
            max_height = @max(max_height, image.height);
        }

        self.allocated_image_width = upload_common.heightCapacity(max_width);
        self.allocated_image_height = upload_common.heightCapacity(max_height);
        self.allocated_image_count = upload_common.imageCapacity(@intCast(self.image_slot_count));

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.image_array);
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                    0,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    null,
                );
                setImageTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.image_array);
                gl.glTextureStorage3D(
                    self.image_array,
                    1,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                );
                setImageTexParamsDSA(self.image_array);
                gl.glBindTextureUnit(3, self.image_array);
            },
        }

        for (self.image_slots[0..self.image_slot_count], 0..) |slot, i| {
            self.uploadImageLayer(slot.image.?, @intCast(i));
        }
    }

    fn uploadImageLayer(self: *const PreparedResources, image: *const snail_mod.Image, layer: u32) void {
        switch (self.backend) {
            .gl33 => {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexSubImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
            .gl44 => {
                gl.glTextureSubImage3D(
                    self.image_array,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
        }
    }

    fn rebuildTextureArrays(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        self.destroyAtlasTextureResources();
        self.resetAtlasUploadState();

        try self.ensureAtlasSlotCount(atlases.len);
        const slot_info = if (capacity_modes) |modes|
            try upload_common.rebuildAtlasSlotsWithCapacityModes(self.allocator, self.atlas_slots, atlases, modes)
        else
            try upload_common.rebuildAtlasSlots(self.allocator, self.atlas_slots, atlases);
        self.atlas_slot_count = slot_info.atlas_slot_count;
        self.allocated_curve_height = slot_info.allocated_curve_height;
        self.allocated_band_height = slot_info.allocated_band_height;
        self.allocated_layer_count = slot_info.allocated_layer_count;
        self.fillLayerInfoViews(slot_info.layer_info_rows, layer_infos, out_layer_info_views);

        const first_atlas = upload_common.firstNonEmptyAtlas(atlases) orelse {
            self.fillAtlasViews(atlases, out_views);
            try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
            try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
            return;
        };

        self.createTextureArrays(first_atlas, self.allocated_layer_count, self.allocated_curve_height, self.allocated_band_height);
        self.uploadAllPages(atlases);
        try self.ensureAtlasImagesRegistered(scratch, atlases);
        try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
        try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
        self.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
        self.fillAtlasViews(atlases, out_views);
    }

    fn appendTexturePages(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const snail_mod.lowlevel.CurveAtlas) !bool {
        var max_curve_h: u32 = self.allocated_curve_height;
        var max_band_h: u32 = self.allocated_band_height;
        const start_pages = try scratch.alloc(u32, atlases.len);
        defer scratch.free(start_pages);

        for (atlases, 0..) |atlas, i| {
            if (i >= self.atlas_slot_count) return false;
            const slot = &self.atlas_slots[i];
            const page_count: u32 = @intCast(atlas.pageCount());
            if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
            start_pages[i] = slot.uploaded_pages;
            if (slot.uploaded_pages > slot.page_ptrs.len) return false;
            for (0..slot.uploaded_pages) |page_index| {
                if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
            }
            for (0..page_count) |page_index| {
                const page = atlas.page(@intCast(page_index));
                if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
                if (page.band_height > max_band_h) max_band_h = page.band_height;
            }
        }

        if (atlases.len != self.atlas_slot_count) return false;
        if (max_curve_h > self.allocated_curve_height or max_band_h > self.allocated_band_height) return false;

        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, start_pages[0..atlases.len]),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, start_pages[0..atlases.len]),
        }

        try upload_common.refreshAtlasSlots(self.atlas_slots, atlases);
        return true;
    }

    fn texturesReady(self: *const PreparedResources) bool {
        return self.curve_array != 0 and self.band_array != 0 and self.atlas_slot_count > 0;
    }

    fn atlasSlotsCompatible(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) bool {
        return upload_common.atlasSlotsCompatible(self.atlas_slots[0..], self.atlas_slot_count, atlases);
    }

    fn fillAtlasViews(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, out_views: anytype) void {
        upload_common.fillAtlasViews(self.atlas_slots, atlases, out_views);
    }

    fn atlasLayerInfoRows(self: *const PreparedResources) u32 {
        var rows: u32 = 0;
        for (self.atlas_slots[0..self.atlas_slot_count]) |slot| {
            const atlas = slot.atlas orelse continue;
            rows += atlas.layer_info_height;
        }
        return rows;
    }

    fn fillLayerInfoViews(_: *const PreparedResources, row_base_start: u32, layer_infos: anytype, out_views: anytype) void {
        var row_base = row_base_start;
        for (layer_infos, 0..) |info, i| {
            out_views[i] = .{ .info_row_base = row_base };
            row_base += info.height;
        }
    }

    fn ensureAtlasSlotCount(self: *PreparedResources, count: usize) !void {
        if (self.atlas_slots.len == count) return;
        self.resetAtlasUploadState();
        if (count == 0) return;
        self.atlas_slots = try self.allocator.alloc(AtlasSlot, count);
        @memset(self.atlas_slots, AtlasSlot{});
    }

    fn resetAtlasUploadState(self: *PreparedResources) void {
        for (self.atlas_slots) |*slot| slot.deinit(self.allocator);
        if (self.atlas_slots.len > 0) self.allocator.free(self.atlas_slots);
        self.atlas_slots = &.{};
        self.atlas_slot_count = 0;
        self.allocated_curve_height = 0;
        self.allocated_band_height = 0;
        self.allocated_layer_count = 0;
        self.atlas_has_special_text_runs = false;
    }

    fn createTextureArrays(self: *PreparedResources, first_atlas: *const snail_mod.lowlevel.CurveAtlas, layer_count: u32, max_curve_h: u32, max_band_h: u32) void {
        const first_page = first_atlas.page(0);

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);

                gl.glGenTextures(1, &self.band_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.curve_array);
                gl.glTextureStorage3D(self.curve_array, 1, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count));
                setTexParamsDSA(self.curve_array);

                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.band_array);
                gl.glTextureStorage3D(self.band_array, 1, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count));
                setTexParamsDSA(self.band_array);
                gl.glBindTextureUnit(0, self.curve_array);
                gl.glBindTextureUnit(1, self.band_array);
            },
        }
    }

    fn uploadAllPages(self: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) void {
        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, null),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, null),
        }
    }

    fn uploadTexturePagesGl33WithStarts(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn uploadTexturePagesGl44WithStarts(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glTextureSubImage3D(self.curve_array, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glTextureSubImage3D(self.band_array, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn rebuildLayerInfoTexture(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const snail_mod.lowlevel.CurveAtlas, layer_infos: anytype, layer_info_views: anytype) !void {
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.layer_info_tex = 0;

        var total_rows: u32 = 0;
        for (atlases) |atlas| total_rows += atlas.layer_info_height;
        for (layer_infos) |info| total_rows += info.height;
        if (total_rows == 0) return;

        var width = upload_common.maxLayerInfoWidth(atlases);
        for (layer_infos) |info| {
            if (info.height > 0 and info.width > width) width = info.width;
        }
        const total_texels = @as(usize, width) * @as(usize, total_rows) * 4;
        const data = try scratch.alloc(f32, total_texels);
        defer scratch.free(data);
        @memset(data, 0);

        const ImagePatchView = struct {
            image: *const snail_mod.Image,
            layer: u32 = 0,
            uv_scale: snail_mod.Vec2 = .{ .x = 1.0, .y = 1.0 },
        };
        for (atlases, 0..) |atlas, i| {
            const lid = atlas.layer_info_data orelse continue;
            const row_base = self.atlas_slots[i].info_row_base;
            const row_count = atlas.layer_info_height;
            upload_common.copyLayerInfoRows(data, width, row_base, lid, atlas.layer_info_width, row_count);

            const records = atlas.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                const view = self.currentImageView(ImagePatchView, image);
                upload_common.patchImagePaintRecord(data, width, atlas.layer_info_width, row_base, record.?.texel_offset, view);
            }
        }
        for (layer_infos, 0..) |info, i| {
            const lid = info.data orelse continue;
            const row_base = layer_info_views[i].info_row_base;
            upload_common.copyLayerInfoRows(data, width, row_base, lid, info.width, info.height);

            const records = info.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                const view = self.currentImageView(ImagePatchView, image);
                upload_common.patchImagePaintRecord(data, width, info.width, row_base, record.?.texel_offset, view);
            }
        }

        gl.glGenTextures(1, &self.layer_info_tex);
        gl.glActiveTexture(gl.GL_TEXTURE2);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(width), @intCast(total_rows), 0, gl.GL_RGBA, gl.GL_FLOAT, @ptrCast(data.ptr));
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }
};

// ── GlTextState ──

pub const LinearResolveRestore = struct {
    draw_fbo: gl.GLint = 0,
    read_fbo: gl.GLint = 0,
    viewport: [4]gl.GLint = .{ 0, 0, 0, 0 },
    resolve_rect: PixelRect = .{},
    depth_test: bool = false,
    scissor_test: bool = false,
    blend: bool = false,
};

pub const GlTextState = struct {
    backend: Backend = .gl33,
    text_program: ProgramState = .{},
    text_subpixel_dual_program: ProgramState = .{},
    colr_program: ProgramState = .{},
    path_program: ProgramState = .{},
    subpixel_order: SubpixelOrder = .none,
    fill_rule: FillRule = .non_zero,
    target_encoding: TargetEncoding = .srgb,
    resolve: Resolve = .{ .direct = .{} },
    coverage_transfer: CoverageTransfer = .identity,
    linear_resolve_program: gl.GLuint = 0,
    linear_resolve_tex_loc: gl.GLint = -1,
    linear_resolve_dst_tex_loc: gl.GLint = -1,
    linear_resolve_mode_loc: gl.GLint = -1,
    linear_resolve_vao: gl.GLuint = 0,
    linear_resolve_fbo: gl.GLuint = 0,
    linear_resolve_tex: gl.GLuint = 0,
    linear_resolve_dst_tex: gl.GLuint = 0,
    linear_resolve_width: u32 = 0,
    linear_resolve_height: u32 = 0,
    linear_resolve_format: IntermediateFormat = .rgba16f,
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    active_program: gl.GLuint = 0,
    frame_begun: bool = false,
    supports_dual_source_blend: bool = false,
    persistent_map: ?[*]u8 = null,
    ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS,
    ring_segment: u32 = 0,

    // ── Init / Deinit ──

    pub fn init(self: *GlTextState) !void {
        self.backend = gl_backend.detect(gl);
        self.supports_dual_source_blend = detectDualSourceBlendSupport();

        // Link all draw programs during renderer init so draw never compiles or links.
        self.text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
        self.colr_program = try loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false);
        self.path_program = try loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader, false);
        if (self.supports_dual_source_blend) {
            self.text_subpixel_dual_program = try loadProgramState("text-subpixel-dual", shaders.vertex_shader, shaders.fragment_shader_text_subpixel_dual, true);
        }
        self.linear_resolve_program = try linkProgram("linear-resolve", linear_resolve_vertex_shader, linear_resolve_fragment_shader, false);
        self.linear_resolve_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_linear_tex");
        self.linear_resolve_dst_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_dst_tex");
        self.linear_resolve_mode_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_mode");
        gl.glGenVertexArrays(1, &self.linear_resolve_vao);

        switch (self.backend) {
            .gl33 => self.initGl33(),
            .gl44 => self.initGl44(),
        }

        gl.glEnable(gl.GL_BLEND);
        // Shader outputs premultiplied alpha (frag_color = v_color * coverage),
        // so use GL_ONE for src to avoid double-multiplying coverage.
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

        // Enable sRGB framebuffer so GL handles gamma correction during blending.
        // The fragment shaders output linear premultiplied color; GL linearizes
        // existing framebuffer values before blending and applies sRGB gamma on write.
        gl.glEnable(gl.GL_FRAMEBUFFER_SRGB);
    }

    fn initGl33(self: *GlTextState) void {
        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, GL33_STREAM_BYTES, null, gl.GL_STREAM_DRAW);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
        setupVertexAttribs();
        setupInstanceDivisors();
    }

    fn initGl44(self: *GlTextState) void {
        gl.glCreateVertexArrays(1, &self.vao);
        gl.glCreateBuffers(1, &self.vbo);
        gl.glCreateBuffers(1, &self.ebo);

        const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
        gl.glNamedBufferStorage(self.vbo, RING_TOTAL_BYTES, null, flags);
        self.persistent_map = @ptrCast(gl.glMapNamedBufferRange(self.vbo, 0, RING_TOTAL_BYTES, flags));

        if (self.persistent_map == null) {
            // Persistent mapping unavailable — fall back to the GL 3.3 baseline path.
            gl.glDeleteVertexArrays(1, &self.vao);
            gl.glDeleteBuffers(1, &self.vbo);
            gl.glDeleteBuffers(1, &self.ebo);
            self.backend = .gl33;
            self.initGl33();
            return;
        }

        // All vertex attribs are per-instance (binding divisor = 1).
        const stride: gl.GLint = vertex.BYTES_PER_INSTANCE;
        gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, 0, stride);
        gl.glVertexArrayElementBuffer(self.vao, self.ebo);
        gl.glVertexArrayBindingDivisor(self.vao, 0, 1);

        setupVertexArrayAttribs(self.vao);

        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
    }

    pub fn deinit(self: *GlTextState) void {
        if (self.backend == .gl44) {
            for (&self.ring_fences) |*f| {
                if (f.*) |fence| {
                    gl.glDeleteSync(fence);
                    f.* = null;
                }
            }
            if (self.persistent_map != null) {
                _ = gl.glUnmapNamedBuffer(self.vbo);
                self.persistent_map = null;
            }
        }

        deleteProgramState(&self.text_program);
        deleteProgramState(&self.text_subpixel_dual_program);
        deleteProgramState(&self.colr_program);
        deleteProgramState(&self.path_program);
        if (self.linear_resolve_program != 0) gl.glDeleteProgram(self.linear_resolve_program);
        if (self.linear_resolve_vao != 0) gl.glDeleteVertexArrays(1, &self.linear_resolve_vao);
        if (self.linear_resolve_fbo != 0) gl.glDeleteFramebuffers(1, &self.linear_resolve_fbo);
        if (self.linear_resolve_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_tex);
        if (self.linear_resolve_dst_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_dst_tex);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
    }

    pub fn backendName(self: *const GlTextState) []const u8 {
        return switch (self.backend) {
            .gl33 => "GL 3.3",
            .gl44 => "GL 4.4 (persistent mapped)",
        };
    }

    pub fn beginLinearResolve(self: *GlTextState, width: u32, height: u32, resolve: LinearResolve) !LinearResolveRestore {
        if (width == 0 or height == 0) return error.InvalidResolveTarget;
        try self.ensureLinearResolve(width, height, resolve.intermediate_format);

        var restore: LinearResolveRestore = .{};
        gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &restore.draw_fbo);
        gl.glGetIntegerv(gl.GL_READ_FRAMEBUFFER_BINDING, &restore.read_fbo);
        gl.glGetIntegerv(gl.GL_VIEWPORT, &restore.viewport);
        restore.resolve_rect = resolve.region.rect(width, height);
        restore.depth_test = gl.glIsEnabled(gl.GL_DEPTH_TEST) == gl.GL_TRUE;
        restore.scissor_test = gl.glIsEnabled(gl.GL_SCISSOR_TEST) == gl.GL_TRUE;
        restore.blend = gl.glIsEnabled(gl.GL_BLEND) == gl.GL_TRUE;

        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.linear_resolve_fbo);
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        gl.glDisable(gl.GL_DEPTH_TEST);
        self.setResolveScissor(restore.resolve_rect, 0, height);
        gl.glDisable(gl.GL_BLEND);
        switch (resolve.backdrop) {
            .target => {
                self.snapshotResolveDestination(restore, width, height);
                self.drawLinearResolveTriangle(.seed_intermediate);
            },
            .clear => |color| {
                const linear = linearPremultipliedBackdropColor(color);
                gl.glClearBufferfv(gl.GL_COLOR, 0, &linear);
            },
            .transparent => {
                const zero = [4]f32{ 0, 0, 0, 0 };
                gl.glClearBufferfv(gl.GL_COLOR, 0, &zero);
            },
            .dont_care => {},
        }
        return restore;
    }

    pub fn endLinearResolve(self: *GlTextState, restore: LinearResolveRestore) void {
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(restore.draw_fbo));
        gl.glViewport(restore.viewport[0], restore.viewport[1], restore.viewport[2], restore.viewport[3]);
        gl.glDisable(gl.GL_DEPTH_TEST);
        self.setResolveScissor(restore.resolve_rect, restore.viewport[1], @intCast(restore.viewport[3]));

        gl.glDisable(gl.GL_BLEND);
        self.drawLinearResolveTriangle(.encode_to_target);

        if (restore.blend) {
            gl.glEnable(gl.GL_BLEND);
        } else {
            gl.glDisable(gl.GL_BLEND);
        }
        gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        if (restore.depth_test) {
            gl.glEnable(gl.GL_DEPTH_TEST);
        } else {
            gl.glDisable(gl.GL_DEPTH_TEST);
        }
        if (restore.scissor_test) {
            gl.glEnable(gl.GL_SCISSOR_TEST);
        } else {
            gl.glDisable(gl.GL_SCISSOR_TEST);
        }
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(restore.read_fbo));
        self.frame_begun = false;
    }

    const LinearResolvePass = enum(gl.GLint) {
        seed_intermediate = 0,
        encode_to_target = 1,
    };

    fn snapshotResolveDestination(self: *GlTextState, restore: LinearResolveRestore, width: u32, height: u32) void {
        var prev_tex: gl.GLint = 0;
        gl.glGetIntegerv(gl.GL_TEXTURE_BINDING_2D, &prev_tex);
        defer gl.glBindTexture(gl.GL_TEXTURE_2D, @intCast(prev_tex));

        const rect = restore.resolve_rect;
        if (rect.w == 0 or rect.h == 0) return;
        const y = glRectY(rect, height);
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(restore.draw_fbo));
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_dst_tex);
        gl.glCopyTexSubImage2D(
            gl.GL_TEXTURE_2D,
            0,
            rect.x,
            y,
            restore.viewport[0] + rect.x,
            restore.viewport[1] + y,
            @intCast(@min(rect.w, width)),
            @intCast(@min(rect.h, height)),
        );
    }

    fn drawLinearResolveTriangle(self: *GlTextState, pass: LinearResolvePass) void {
        gl.glUseProgram(self.linear_resolve_program);
        gl.glBindVertexArray(self.linear_resolve_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, if (pass == .seed_intermediate) 0 else self.linear_resolve_tex);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_dst_tex);
        if (self.linear_resolve_tex_loc >= 0) gl.glUniform1i(self.linear_resolve_tex_loc, 0);
        if (self.linear_resolve_dst_tex_loc >= 0) gl.glUniform1i(self.linear_resolve_dst_tex_loc, 1);
        if (self.linear_resolve_mode_loc >= 0) gl.glUniform1i(self.linear_resolve_mode_loc, @intFromEnum(pass));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
    }

    fn setResolveScissor(_: *GlTextState, rect: PixelRect, viewport_y: gl.GLint, viewport_height: u32) void {
        const y = viewport_y + glRectY(rect, viewport_height);
        gl.glEnable(gl.GL_SCISSOR_TEST);
        gl.glScissor(rect.x, y, @intCast(rect.w), @intCast(rect.h));
    }

    fn glRectY(rect: PixelRect, height: u32) gl.GLint {
        return @intCast(@as(i32, @intCast(height)) - rect.y - @as(i32, @intCast(rect.h)));
    }

    fn srgbFloatToLinear(v: f32) f32 {
        const c = std.math.clamp(v, 0.0, 1.0);
        return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }

    fn linearPremultipliedBackdropColor(color_srgb: [4]f32) [4]f32 {
        const alpha = std.math.clamp(color_srgb[3], 0.0, 1.0);
        return .{
            srgbFloatToLinear(color_srgb[0]) * alpha,
            srgbFloatToLinear(color_srgb[1]) * alpha,
            srgbFloatToLinear(color_srgb[2]) * alpha,
            alpha,
        };
    }

    fn ensureLinearResolve(self: *GlTextState, width: u32, height: u32, format: IntermediateFormat) !void {
        if (self.linear_resolve_fbo != 0 and
            self.linear_resolve_tex != 0 and
            self.linear_resolve_dst_tex != 0 and
            self.linear_resolve_width == width and
            self.linear_resolve_height == height and
            self.linear_resolve_format == format)
        {
            return;
        }

        if (self.linear_resolve_fbo != 0) gl.glDeleteFramebuffers(1, &self.linear_resolve_fbo);
        if (self.linear_resolve_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_tex);
        if (self.linear_resolve_dst_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_dst_tex);
        self.linear_resolve_fbo = 0;
        self.linear_resolve_tex = 0;
        self.linear_resolve_dst_tex = 0;
        self.linear_resolve_width = 0;
        self.linear_resolve_height = 0;
        self.linear_resolve_format = format;

        var prev_draw: gl.GLint = 0;
        var prev_read: gl.GLint = 0;
        var prev_tex: gl.GLint = 0;
        gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
        gl.glGetIntegerv(gl.GL_READ_FRAMEBUFFER_BINDING, &prev_read);
        gl.glGetIntegerv(gl.GL_TEXTURE_BINDING_2D, &prev_tex);
        defer {
            gl.glBindTexture(gl.GL_TEXTURE_2D, @intCast(prev_tex));
            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(prev_draw));
            gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(prev_read));
        }

        gl.glGenFramebuffers(1, &self.linear_resolve_fbo);
        gl.glGenTextures(1, &self.linear_resolve_tex);
        gl.glGenTextures(1, &self.linear_resolve_dst_tex);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_tex);
        const internal_format: gl.GLint = switch (format) {
            .rgba16f => gl.GL_RGBA16F,
            .rgba32f => gl.GL_RGBA32F,
        };
        const pixel_type: gl.GLenum = switch (format) {
            .rgba16f => gl.GL_HALF_FLOAT,
            .rgba32f => gl.GL_FLOAT,
        };
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            internal_format,
            @intCast(width),
            @intCast(height),
            0,
            gl.GL_RGBA,
            pixel_type,
            null,
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_dst_tex);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            internal_format,
            @intCast(width),
            @intCast(height),
            0,
            gl.GL_RGBA,
            pixel_type,
            null,
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.linear_resolve_fbo);
        gl.glFramebufferTexture2D(gl.GL_DRAW_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.linear_resolve_tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_DRAW_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) {
            return error.FramebufferIncomplete;
        }

        self.linear_resolve_width = width;
        self.linear_resolve_height = height;
    }

    // ── Draw ──

    fn drawTextInternal(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32, allow_subpixel: bool) void {
        // VAO may have been unbound by other renderers in the same context.
        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl33) {
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        const render_mode = subpixel_policy.chooseTextRenderMode(
            vertices,
            mvp,
            allow_subpixel,
            self.subpixel_order,
            self.supports_dual_source_blend,
        );
        if (!prepared.atlas_has_special_text_runs) {
            setTextBlendMode(false, render_mode);
            const prog_state = switch (render_mode) {
                .grayscale => &self.text_program,
                .subpixel_dual_source => &self.text_subpixel_dual_program,
            };
            self.bindProgramState(prepared, prog_state, mvp, viewport_w, viewport_h, texture_layer_base, render_mode);
            self.drawGlyphRange(vertices, 0, total_glyphs);
            return;
        }

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
                    mvp,
                    allow_subpixel,
                    self.subpixel_order,
                    self.supports_dual_source_blend,
                );
            setTextBlendMode(run_kind != .regular, run_mode);
            const prog_state = switch (run_kind) {
                .regular => switch (run_mode) {
                    .grayscale => &self.text_program,
                    .subpixel_dual_source => &self.text_subpixel_dual_program,
                },
                .colr => self.ensureColrProgram(),
                .path => self.ensurePathProgram(),
            };
            self.bindProgramState(prepared, prog_state, mvp, viewport_w, viewport_h, texture_layer_base, run_mode);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    pub fn drawTextPrepared(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.drawTextInternal(prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base, true);
    }

    pub fn drawPreparedText(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32) void {
        _ = prepared;
        if (vertices.len == 0) return;
        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl33) {
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }
        self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
    }

    pub fn drawPathsPrepared(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        const render_mode: subpixel_policy.TextRenderMode = .grayscale;
        const prog_state = self.ensurePathProgram();
        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl33) {
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        setTextBlendMode(false, render_mode);

        self.bindProgramState(prepared, prog_state, mvp, viewport_w, viewport_h, texture_layer_base, render_mode);
        self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
    }

    pub fn beginFrame(self: *GlTextState) void {
        self.frame_begun = false;
    }

    pub fn setSubpixelOrder(self: *GlTextState, order: SubpixelOrder) void {
        self.subpixel_order = order;
    }

    pub fn getSubpixelOrder(self: *const GlTextState) SubpixelOrder {
        return self.subpixel_order;
    }

    pub fn setFillRule(self: *GlTextState, rule: FillRule) void {
        self.fill_rule = rule;
    }

    pub fn getFillRule(self: *const GlTextState) FillRule {
        return self.fill_rule;
    }

    pub fn setTargetEncoding(self: *GlTextState, encoding: TargetEncoding) void {
        self.target_encoding = encoding;
    }

    pub fn getTargetEncoding(self: *const GlTextState) TargetEncoding {
        return self.target_encoding;
    }

    pub fn setResolve(self: *GlTextState, resolve: Resolve) void {
        self.resolve = resolve;
    }

    pub fn getResolve(self: *const GlTextState) Resolve {
        return self.resolve;
    }

    pub fn setCoverageTransfer(self: *GlTextState, transfer: CoverageTransfer) void {
        self.coverage_transfer = transfer;
    }

    pub fn getCoverageTransfer(self: *const GlTextState) CoverageTransfer {
        return self.coverage_transfer;
    }

    inline fn shaderEncodesSrgb(self: *const GlTextState) bool {
        return self.target_encoding.shaderEncodesSrgb();
    }

    fn ensureColrProgram(self: *GlTextState) *const ProgramState {
        std.debug.assert(self.colr_program.handle != 0);
        return &self.colr_program;
    }

    fn ensurePathProgram(self: *GlTextState) *const ProgramState {
        std.debug.assert(self.path_program.handle != 0);
        return &self.path_program;
    }

    fn bindProgramState(self: *GlTextState, prepared: *const PreparedResources, prog_state: *const ProgramState, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32, render_mode: subpixel_policy.TextRenderMode) void {
        if (prog_state.handle != self.active_program or !self.frame_begun) {
            gl.glUseProgram(prog_state.handle);
            self.active_program = prog_state.handle;

            if (self.backend == .gl44) {
                gl.glBindTextureUnit(0, prepared.curve_array);
                gl.glBindTextureUnit(1, prepared.band_array);
                if (prog_state.layer_tex_loc >= 0 and prepared.layer_info_tex != 0) gl.glBindTextureUnit(2, prepared.layer_info_tex);
                if (prog_state.image_tex_loc >= 0 and prepared.image_array != 0) gl.glBindTextureUnit(3, prepared.image_array);
            } else {
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, prepared.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, prepared.band_array);
                if (prog_state.layer_tex_loc >= 0 and prepared.layer_info_tex != 0) {
                    gl.glActiveTexture(gl.GL_TEXTURE2);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, prepared.layer_info_tex);
                }
                if (prog_state.image_tex_loc >= 0 and prepared.image_array != 0) {
                    gl.glActiveTexture(gl.GL_TEXTURE3);
                    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, prepared.image_array);
                }
            }

            if (prog_state.curve_tex_loc >= 0) gl.glUniform1i(prog_state.curve_tex_loc, 0);
            if (prog_state.band_tex_loc >= 0) gl.glUniform1i(prog_state.band_tex_loc, 1);
            if (prog_state.layer_tex_loc >= 0) gl.glUniform1i(prog_state.layer_tex_loc, 2);
            if (prog_state.image_tex_loc >= 0) gl.glUniform1i(prog_state.image_tex_loc, 3);
            self.frame_begun = true;
        }

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, viewport_w, viewport_h);
        if (prog_state.layer_base_loc >= 0) gl.glUniform1i(prog_state.layer_base_loc, @intCast(texture_layer_base));
        gl.glUniform1i(prog_state.fill_rule_loc, @intFromEnum(self.fill_rule));
        if (prog_state.subpixel_order_loc >= 0) {
            const order = if (render_mode == .grayscale) SubpixelOrder.none else self.subpixel_order;
            gl.glUniform1i(prog_state.subpixel_order_loc, @intFromEnum(order));
        }
        if (prog_state.output_srgb_loc >= 0) {
            gl.glUniform1i(prog_state.output_srgb_loc, @intFromBool(self.shaderEncodesSrgb()));
        }
        if (prog_state.coverage_exponent_loc >= 0) {
            gl.glUniform1f(prog_state.coverage_exponent_loc, self.coverage_transfer.shaderExponent());
        }
    }

    fn drawGlyphRange(self: *GlTextState, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
        var glyphs_drawn: usize = 0;
        while (glyphs_drawn < glyph_count) {
            const chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
            const word_offset = (glyph_offset + glyphs_drawn) * vertex.WORDS_PER_INSTANCE;
            const byte_size = chunk * BYTES_PER_GLYPH;

            switch (self.backend) {
                .gl33 => {
                    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, @intCast(byte_size), @ptrCast(vertices[word_offset..].ptr));
                },
                .gl44 => {
                    const offset = @as(usize, self.ring_segment) * RING_SEGMENT_BYTES;

                    if (self.ring_fences[self.ring_segment]) |fence| {
                        const status = gl.glClientWaitSync(fence, 0, 0);
                        if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                            _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                        }
                        gl.glDeleteSync(fence);
                        self.ring_fences[self.ring_segment] = null;
                    }

                    const dst = self.persistent_map.?[offset..][0..byte_size];
                    const src: [*]const u8 = @ptrCast(vertices[word_offset..].ptr);
                    @memcpy(dst, src[0..byte_size]);

                    const stride: gl.GLint = vertex.BYTES_PER_INSTANCE;
                    gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, @intCast(offset), stride);
                },
            }

            gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(chunk));

            if (self.backend == .gl44) {
                self.ring_fences[self.ring_segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
                self.ring_segment = (self.ring_segment + 1) % RING_SEGMENTS;
            }

            glyphs_drawn += chunk;
        }
    }
};

// ── Module-level state instance ──

pub var state: GlTextState = .{};

pub fn init() !void {
    return state.init();
}

pub fn deinit() void {
    state.deinit();
}

pub fn beginFrame() void {
    state.beginFrame();
}

pub fn backendName() []const u8 {
    return state.backendName();
}

// ── Pure utility functions (no mutable state access) ──

fn setupVertexAttribs() void {
    const stride: gl.GLsizei = vertex.BYTES_PER_INSTANCE;
    setupVertexAttrib(0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "rect"));
    setupVertexAttrib(1, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "xform"));
    setupVertexAttrib(2, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "origin"));
    gl.glVertexAttribIPointer(3, 2, gl.GL_UNSIGNED_INT, stride, @ptrFromInt(@offsetOf(vertex.Instance, "glyph")));
    gl.glEnableVertexAttribArray(3);
    setupVertexAttrib(4, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "band"));
    setupVertexAttrib(5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @offsetOf(vertex.Instance, "color"));
    setupVertexAttrib(6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @offsetOf(vertex.Instance, "tint"));
}

fn textureUnitEnum(unit: gl.GLint) gl.GLenum {
    return @intCast(@as(i64, @intCast(gl.GL_TEXTURE0)) + @as(i64, unit));
}

fn setupInstanceDivisors() void {
    inline for (0..7) |i| {
        gl.glVertexAttribDivisor(@intCast(i), 1);
    }
}

fn setupVertexAttrib(loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, stride: gl.GLsizei, offset: usize) void {
    gl.glVertexAttribPointer(loc, components, ty, normalized, stride, @ptrFromInt(offset));
    gl.glEnableVertexAttribArray(loc);
}

fn setupVertexArrayAttribs(vao: gl.GLuint) void {
    setupVertexArrayAttrib(vao, 0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "rect"));
    setupVertexArrayAttrib(vao, 1, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "xform"));
    setupVertexArrayAttrib(vao, 2, 2, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "origin"));
    gl.glEnableVertexArrayAttrib(vao, 3);
    gl.glVertexArrayAttribIFormat(vao, 3, 2, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "glyph")));
    gl.glVertexArrayAttribBinding(vao, 3, 0);
    setupVertexArrayAttrib(vao, 4, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "band"));
    setupVertexArrayAttrib(vao, 5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "color"));
    setupVertexArrayAttrib(vao, 6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "tint"));
}

fn setupVertexArrayAttrib(vao: gl.GLuint, loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, offset: usize) void {
    gl.glEnableVertexArrayAttrib(vao, loc);
    gl.glVertexArrayAttribFormat(vao, loc, components, ty, normalized, @intCast(offset));
    gl.glVertexArrayAttribBinding(vao, loc, 0);
}

fn initEbo() void {
    // Single quad index pattern — instancing repeats it per glyph.
    const indices = [6]u32{ 0, 1, 2, 0, 2, 3 };
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);
}

// ── Shader compilation ──

const linear_resolve_vertex_shader: [:0]const u8 =
    \\#version 330 core
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,
    \\                    (gl_VertexID == 2) ? 3.0 : -1.0);
    \\    v_uv = pos * 0.5 + 0.5;
    \\    gl_Position = vec4(pos, 0.0, 1.0);
    \\}
;

const linear_resolve_fragment_shader: [:0]const u8 =
    \\#version 330 core
    \\in vec2 v_uv;
    \\uniform sampler2D u_linear_tex;
    \\uniform sampler2D u_dst_tex;
    \\uniform int u_mode;
    \\out vec4 frag_color;
    \\
    \\float srgbDecode(float c) {
    \\    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\float srgbEncode(float c) {
    \\    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    \\}
    \\
    \\vec4 srgbDecodePremultiplied(vec4 premul) {
    \\    if (premul.a <= 0.0) return vec4(0.0);
    \\    float inv_a = 1.0 / premul.a;
    \\    return vec4(
    \\        srgbDecode(clamp(premul.r * inv_a, 0.0, 1.0)) * premul.a,
    \\        srgbDecode(clamp(premul.g * inv_a, 0.0, 1.0)) * premul.a,
    \\        srgbDecode(clamp(premul.b * inv_a, 0.0, 1.0)) * premul.a,
    \\        premul.a
    \\    );
    \\}
    \\
    \\vec4 srgbEncodePremultiplied(vec4 premul) {
    \\    if (premul.a <= 0.0) return vec4(0.0);
    \\    float inv_a = 1.0 / premul.a;
    \\    return vec4(
    \\        srgbEncode(max(premul.r * inv_a, 0.0)) * premul.a,
    \\        srgbEncode(max(premul.g * inv_a, 0.0)) * premul.a,
    \\        srgbEncode(max(premul.b * inv_a, 0.0)) * premul.a,
    \\        premul.a
    \\    );
    \\}
    \\
    \\void main() {
    \\    if (u_mode == 0) {
    \\        frag_color = srgbDecodePremultiplied(texture(u_dst_tex, v_uv));
    \\    } else {
    \\        frag_color = srgbEncodePremultiplied(texture(u_linear_tex, v_uv));
    \\    }
    \\}
;

fn compileShader(shader_type: gl.GLenum, source: [*c]const u8) ?gl.GLuint {
    const shader = gl.glCreateShader(shader_type);
    gl.glShaderSource(shader, 1, &source, null);
    gl.glCompileShader(shader);

    var ok: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetShaderInfoLog(shader, 4096, &len, &buf);
        if (len > 0) std.debug.print("Shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

fn loadProgramState(cache_label: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !ProgramState {
    const handle = try linkProgram(cache_label, vs_src, fs_src, dual_source);
    return .{
        .handle = handle,
        .mvp_loc = gl.glGetUniformLocation(handle, "u_mvp"),
        .viewport_loc = gl.glGetUniformLocation(handle, "u_viewport"),
        .curve_tex_loc = gl.glGetUniformLocation(handle, "u_curve_tex"),
        .band_tex_loc = gl.glGetUniformLocation(handle, "u_band_tex"),
        .image_tex_loc = gl.glGetUniformLocation(handle, "u_image_tex"),
        .fill_rule_loc = gl.glGetUniformLocation(handle, "u_fill_rule"),
        .subpixel_order_loc = gl.glGetUniformLocation(handle, "u_subpixel_order"),
        .output_srgb_loc = gl.glGetUniformLocation(handle, "u_output_srgb"),
        .coverage_exponent_loc = gl.glGetUniformLocation(handle, "u_coverage_exponent"),
        .layer_tex_loc = gl.glGetUniformLocation(handle, "u_layer_tex"),
        .layer_base_loc = gl.glGetUniformLocation(handle, "u_layer_base"),
    };
}

fn deleteProgramState(prog_state: *ProgramState) void {
    if (prog_state.handle != 0) gl.glDeleteProgram(prog_state.handle);
    prog_state.* = .{};
}

fn linkProgram(_: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !gl.GLuint {
    const vs = compileShader(gl.GL_VERTEX_SHADER, vs_src) orelse return error.VertexShaderFailed;
    defer gl.glDeleteShader(vs);
    const fs = compileShader(gl.GL_FRAGMENT_SHADER, fs_src) orelse return error.FragmentShaderFailed;
    defer gl.glDeleteShader(fs);

    const prog = gl.glCreateProgram();
    gl.glAttachShader(prog, vs);
    gl.glAttachShader(prog, fs);
    if (dual_source) {
        gl.glBindFragDataLocationIndexed(prog, 0, 0, "frag_color");
        gl.glBindFragDataLocationIndexed(prog, 0, 1, "frag_blend");
    }
    gl.glLinkProgram(prog);

    var ok: gl.GLint = 0;
    gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetProgramInfoLog(prog, 4096, &len, &buf);
        if (len > 0) std.debug.print("Shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderLinkFailed;
    }
    return prog;
}

fn setTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setTexParamsDSA(tex: gl.GLuint) void {
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setImageTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setImageTexParamsDSA(tex: gl.GLuint) void {
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setTextBlendMode(special: bool, render_mode: subpixel_policy.TextRenderMode) void {
    if (!special and render_mode == .subpixel_dual_source) {
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC1_COLOR, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        return;
    }
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
}

fn detectDualSourceBlendSupport() bool {
    var max_draw_buffers: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_MAX_DUAL_SOURCE_DRAW_BUFFERS, &max_draw_buffers);
    return max_draw_buffers >= 1;
}
