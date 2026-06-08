//! GL / GLES3 persistent prepared-pages cache for snail.
//!
//! Mirrors `CpuBackendCache`: caller-sized capacity, slot
//! allocation via free-list, explicit `release(binding)`, no auto-grow.
//!
//! Per-cache resident state:
//!
//! - `curve_array`, `band_array` — `TEXTURE_2D_ARRAY` sized to
//!   `pool.options.max_layers`. Pages stream in via `glTexSubImage3D`.
//! - `layer_info_tex` — single `TEXTURE_2D` of `INFO_WIDTH × options
//!   .layer_info_height` `RGBA32F` texels. Each binding occupies a
//!   row band starting at `binding.info_row_base`.
//! - `image_array_tex` — `TEXTURE_2D_ARRAY` of
//!   `options.max_image_width × options.max_image_height ×
//!   options.max_images` sRGBA8 layers. Each binding occupies a contiguous
//!   layer range starting at `binding.image_layer_base`. Allocation is a
//!   no-op when `max_images == 0`.
//!
//! Parameterized over `.gl33` / `.gl44` / `.gles30`. `.gl44` uses DSA;
//! the other two go through the bind-then-upload pattern.

const std = @import("std");

const atlas_mod = @import("../../../atlas.zig");
const draw_records = @import("../../../picture/draw_records.zig");
const page_pool_mod = @import("../../../atlas/page_pool.zig");
const page_mod = @import("../../../atlas/page.zig");
const curve_tex = @import("../../format/curve_texture.zig");
const band_tex = @import("../../format/band_texture.zig");
const paint_records = @import("../../../atlas/paint_records.zig");
const upload_common = @import("../../format/upload_common.zig");
const image_mod = @import("../../../image.zig");
const cache_base = @import("../cache.zig");

pub const Variant = enum {
    gl33,
    gl44,
    gles30,

    pub fn supportsDsa(self: Variant) bool {
        return self == .gl44;
    }
};

inline fn bindingsFor(comptime v: Variant) type {
    return switch (v) {
        .gl33, .gl44 => @import("bindings.zig"),
        .gles30 => @import("../gles30/bindings.zig"),
    };
}

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Image = image_mod.Image;

const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;
/// One row of the curve texture is `TEX_WIDTH * 4` u16 words (RGBA16F).
const CURVE_WORDS_PER_ROW: u32 = CURVE_TEX_WIDTH * 4;
/// One row of the band texture is `TEX_WIDTH * 2` u16 words (RG16UI).
const BAND_WORDS_PER_ROW: u32 = BAND_TEX_WIDTH * 2;
const INFO_WIDTH: u32 = paint_records.info_width;

pub const CacheOptions = cache_base.GpuCacheOptions;
pub const UploadError = cache_base.BaseUploadError || error{ImageTooLarge};
pub const ResizeError = cache_base.BaseResizeError;

pub fn GlBackendCacheFor(comptime variant: Variant) type {
    const gl = bindingsFor(variant).gl;
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        pool: *PagePool,
        options: CacheOptions,

        // Pool-wide resident curve/band texture arrays.
        curve_array: gl.GLuint = 0,
        band_array: gl.GLuint = 0,
        curve_height: u32 = 0,
        band_height: u32 = 0,
        layer_count: u32 = 0,

        // Persistent layer-info texture (RGBA32F INFO_WIDTH × layer_info_height).
        layer_info_tex: gl.GLuint = 0,
        free_layer_info_ranges: std.ArrayList(LayerInfoRange) = .empty,

        // Persistent image array (TEXTURE_2D_ARRAY of sRGBA8).
        image_array_tex: gl.GLuint = 0,
        free_image_ranges: std.ArrayList(ImageRange) = .empty,
        // Slot-level image identity, for dedup within an upload.
        image_storage: []?*const Image = &.{},

        // Per-binding slots.
        bindings: []BindingSlot,
        active_bindings: u32 = 0,

        // Per-pool-layer streaming watermarks (page generation + used words).
        prepared_generation: []u16,
        prepared_curve_words: []u32,
        prepared_band_words: []u32,

        upload_generation: u32 = 0,

        pub const LayerInfoRange = struct { row_base: u32, height: u32 };
        pub const ImageRange = struct { layer_base: u32, count: u32 };

        pub const BindingSlot = struct {
            active: bool = false,
            generation: u32 = 0,
            info_row_base: u32 = 0,
            info_height: u32 = 0,
            image_layer_base: u32 = 0,
            image_count: u32 = 0,
        };

        pub fn init(allocator: std.mem.Allocator, pool: *PagePool, options: CacheOptions) !Self {
            const max_layers = pool.options.max_layers;

            const gen = try allocator.alloc(u16, max_layers);
            errdefer allocator.free(gen);
            const curve_words = try allocator.alloc(u32, max_layers);
            errdefer allocator.free(curve_words);
            const band_words = try allocator.alloc(u32, max_layers);
            errdefer allocator.free(band_words);
            @memset(gen, 0);
            @memset(curve_words, 0);
            @memset(band_words, 0);

            const bindings = try allocator.alloc(BindingSlot, options.max_bindings);
            errdefer allocator.free(bindings);
            for (bindings) |*b| b.* = .{};

            const image_storage = if (options.max_images > 0)
                try allocator.alloc(?*const Image, options.max_images)
            else
                @as([]?*const Image, &.{});
            errdefer if (options.max_images > 0) allocator.free(image_storage);
            if (options.max_images > 0) @memset(image_storage, null);

            var free_layer_info_ranges: std.ArrayList(LayerInfoRange) = .empty;
            errdefer free_layer_info_ranges.deinit(allocator);
            if (options.layer_info_height > 0) {
                try free_layer_info_ranges.append(allocator, .{ .row_base = 0, .height = options.layer_info_height });
            }

            var free_image_ranges: std.ArrayList(ImageRange) = .empty;
            errdefer free_image_ranges.deinit(allocator);
            if (options.max_images > 0) {
                try free_image_ranges.append(allocator, .{ .layer_base = 0, .count = options.max_images });
            }

            return .{
                .allocator = allocator,
                .pool = pool,
                .options = options,
                .prepared_generation = gen,
                .prepared_curve_words = curve_words,
                .prepared_band_words = band_words,
                .bindings = bindings,
                .image_storage = image_storage,
                .free_layer_info_ranges = free_layer_info_ranges,
                .free_image_ranges = free_image_ranges,
            };
        }

        pub fn deinit(self: *Self) void {
            self.destroyTextures();
            self.allocator.free(self.prepared_generation);
            self.allocator.free(self.prepared_curve_words);
            self.allocator.free(self.prepared_band_words);
            self.allocator.free(self.bindings);
            if (self.options.max_images > 0) self.allocator.free(self.image_storage);
            self.free_layer_info_ranges.deinit(self.allocator);
            self.free_image_ranges.deinit(self.allocator);
            self.* = undefined;
        }

        // ── Custom-shader resource handles ──
        //
        // GL backends expose the underlying texture names (GLuint) so
        // a caller running their own shader pipeline can bind them
        // alongside `decodeInstance` + `bindingTexels`. Returns 0
        // before `upload`/`uploadDelta` has populated the cache.

        pub fn curveTexHandle(self: *const Self) gl.GLuint {
            return self.curve_array;
        }

        pub fn bandTexHandle(self: *const Self) gl.GLuint {
            return self.band_array;
        }

        pub fn layerInfoTexHandle(self: *const Self) gl.GLuint {
            return self.layer_info_tex;
        }

        pub fn imageArrayHandle(self: *const Self) gl.GLuint {
            return self.image_array_tex;
        }

        fn destroyTextures(self: *Self) void {
            if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
            if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
            if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
            if (self.image_array_tex != 0) gl.glDeleteTextures(1, &self.image_array_tex);
            self.curve_array = 0;
            self.band_array = 0;
            self.layer_info_tex = 0;
            self.image_array_tex = 0;
        }

        // ── Persistent resource lifecycle ──

        pub fn resize(self: *Self, options: CacheOptions) ResizeError!void {
            if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;
            self.destroyTextures();
            self.options = options;

            const new_bindings = try self.allocator.realloc(self.bindings, options.max_bindings);
            for (new_bindings) |*b| b.* = .{};
            self.bindings = new_bindings;

            if (self.image_storage.len > 0) self.allocator.free(self.image_storage);
            self.image_storage = if (options.max_images > 0)
                try self.allocator.alloc(?*const Image, options.max_images)
            else
                &.{};
            if (options.max_images > 0) @memset(self.image_storage, null);

            self.free_layer_info_ranges.clearRetainingCapacity();
            if (options.layer_info_height > 0) {
                try self.free_layer_info_ranges.append(self.allocator, .{ .row_base = 0, .height = options.layer_info_height });
            }
            self.free_image_ranges.clearRetainingCapacity();
            if (options.max_images > 0) {
                try self.free_image_ranges.append(self.allocator, .{ .layer_base = 0, .count = options.max_images });
            }
        }

        /// Upload one or more atlases into the cache, allocating a slot
        /// per atlas. Returns one `Binding` per atlas in `out_bindings`.
        /// On any failure all partial allocations roll back so the cache
        /// is left in the pre-upload state.
        pub fn upload(
            self: *Self,
            scratch: std.mem.Allocator,
            atlases: []const *const Atlas,
            out_bindings: []Binding,
        ) UploadError!void {
            std.debug.assert(atlases.len == out_bindings.len);

            for (atlases) |atlas| {
                if (atlas.pool) |p| {
                    if (p != self.pool) return error.UnknownPool;
                }
            }

            self.ensurePoolTextures();
            self.ensureLayerInfoTexture();
            try self.ensureImageArrayTexture(atlases);

            var allocated_layer_ranges: std.ArrayList(LayerInfoRange) = .empty;
            defer allocated_layer_ranges.deinit(scratch);
            var allocated_image_ranges: std.ArrayList(ImageRange) = .empty;
            defer allocated_image_ranges.deinit(scratch);
            var allocated_slot_indices: std.ArrayList(u32) = .empty;
            defer allocated_slot_indices.deinit(scratch);

            var success = false;
            defer if (!success) {
                for (allocated_layer_ranges.items) |r| self.releaseLayerInfoRange(r) catch {};
                for (allocated_image_ranges.items) |r| self.releaseImageRange(r) catch {};
                for (allocated_slot_indices.items) |i| self.bindings[i] = .{};
            };

            for (atlases, 0..) |atlas, i| {
                const info_height = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
                const image_count = countUniqueImages(atlas);

                const slot_index = self.findFreeBinding() orelse return error.NoFreeBinding;
                try allocated_slot_indices.append(scratch, slot_index);

                const info_range: LayerInfoRange = if (info_height == 0)
                    .{ .row_base = 0, .height = 0 }
                else
                    (try self.takeLayerInfoRows(info_height)) orelse return error.NoFreeLayerInfoRows;
                try allocated_layer_ranges.append(scratch, info_range);

                const image_range: ImageRange = if (image_count == 0)
                    .{ .layer_base = 0, .count = 0 }
                else
                    (try self.takeImageLayers(image_count)) orelse return error.NoFreeImageLayers;
                try allocated_image_ranges.append(scratch, image_range);

                self.upload_generation += 1;
                const slot = &self.bindings[slot_index];
                slot.* = .{
                    .active = true,
                    .generation = self.upload_generation,
                    .info_row_base = info_range.row_base,
                    .info_height = info_range.height,
                    .image_layer_base = image_range.layer_base,
                    .image_count = image_range.count,
                };

                try self.writeBindingData(scratch, atlas, slot);

                out_bindings[i] = .{
                    .pool = self.pool,
                    .generation = slot.generation,
                    .info_row_base = slot.info_row_base,
                    .image_layer_base = slot.image_layer_base,
                };
            }

            self.active_bindings += @intCast(atlases.len);
            success = true;
        }

        /// Incrementally update `prev_binding`'s slot with `atlas`'s
        /// current state. Intended for the terminal hot path: the same
        /// `Atlas` is grown via `Atlas.extend`, then the new pages /
        /// layer-info rows / image layers are uploaded without
        /// re-binding everything.
        ///
        /// `writeBindingData` already walks each page's
        /// `usedWords` / `uploadedWords` watermarks under the hood, so
        /// pages whose contents haven't grown emit no GL traffic; only
        /// new bytes ship.
        ///
        /// Constraints (errors when violated):
        /// - `prev_binding.generation` must still be active
        ///   (`error.UnknownBinding` otherwise — usually means
        ///   `release` ran first).
        /// - The atlas's `layer_info_height` must fit inside the slot
        ///   reserved at the original upload
        ///   (`error.NoLayerInfoRoomToGrow` otherwise — caller must
        ///   `release` and re-`upload`).
        ///
        /// Returns the (same-slot) binding so the caller can keep
        /// using one variable.
        pub fn uploadDelta(
            self: *Self,
            scratch: std.mem.Allocator,
            prev_binding: Binding,
            atlas: *const Atlas,
        ) UploadError!Binding {
            if (atlas.pool) |p| {
                if (p != self.pool) return error.UnknownPool;
            }
            const slot_index = self.findSlotByGeneration(prev_binding.generation) orelse return error.UnknownBinding;
            const slot = &self.bindings[slot_index];
            if (!slot.active) return error.UnknownBinding;

            const need_info_height = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
            if (need_info_height > slot.info_height) return error.NoLayerInfoRoomToGrow;
            const need_image_count = countUniqueImages(atlas);
            if (need_image_count > slot.image_count) return error.NoLayerInfoRoomToGrow;

            self.ensurePoolTextures();
            self.ensureLayerInfoTexture();
            try self.ensureImageArrayTexture(&.{atlas});

            try self.writeBindingData(scratch, atlas, slot);

            return .{
                .pool = self.pool,
                .generation = slot.generation,
                .info_row_base = slot.info_row_base,
                .image_layer_base = slot.image_layer_base,
            };
        }

        pub fn release(self: *Self, binding: Binding) void {
            const slot_index = self.findSlotByGeneration(binding.generation) orelse return;
            const slot = &self.bindings[slot_index];
            if (!slot.active) return;

            if (slot.info_height > 0) {
                self.releaseLayerInfoRange(.{ .row_base = slot.info_row_base, .height = slot.info_height }) catch {};
            }
            if (slot.image_count > 0) {
                for (slot.image_layer_base..slot.image_layer_base + slot.image_count) |layer| {
                    self.image_storage[layer] = null;
                }
                self.releaseImageRange(.{ .layer_base = slot.image_layer_base, .count = slot.image_count }) catch {};
            }
            slot.* = .{};
            self.active_bindings -= 1;
        }

        // ── Per-pool-layer (curve/band) texture upload ──

        fn ensurePoolTextures(self: *Self) void {
            if (self.curve_array != 0 and self.band_array != 0) return;

            const options = self.pool.options;
            self.curve_height = options.curve_words_per_page / CURVE_WORDS_PER_ROW;
            self.band_height = options.band_words_per_page / BAND_WORDS_PER_ROW;
            self.layer_count = options.max_layers;
            std.debug.assert(self.curve_height > 0 and self.band_height > 0);

            if (comptime variant.supportsDsa()) {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.curve_array);
                gl.glTextureStorage3D(self.curve_array, 1, gl.GL_RGBA16F, @intCast(CURVE_TEX_WIDTH), @intCast(self.curve_height), @intCast(self.layer_count));
                setSampleParamsDsa(self.curve_array, .nearest);
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.band_array);
                gl.glTextureStorage3D(self.band_array, 1, gl.GL_RG16UI, @intCast(BAND_TEX_WIDTH), @intCast(self.band_height), @intCast(self.layer_count));
                setSampleParamsDsa(self.band_array, .nearest);
            } else {
                gl.glGenTextures(1, &self.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(CURVE_TEX_WIDTH), @intCast(self.curve_height), @intCast(self.layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
                setSampleParamsBind(gl.GL_TEXTURE_2D_ARRAY, .nearest);

                gl.glGenTextures(1, &self.band_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(BAND_TEX_WIDTH), @intCast(self.band_height), @intCast(self.layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
                setSampleParamsBind(gl.GL_TEXTURE_2D_ARRAY, .nearest);
            }
        }

        fn ensureLayerInfoTexture(self: *Self) void {
            if (self.layer_info_tex != 0 or self.options.layer_info_height == 0) return;

            if (comptime variant.supportsDsa()) {
                gl.glCreateTextures(gl.GL_TEXTURE_2D, 1, &self.layer_info_tex);
                gl.glTextureStorage2D(self.layer_info_tex, 1, gl.GL_RGBA32F, @intCast(INFO_WIDTH), @intCast(self.options.layer_info_height));
                setSampleParamsDsa(self.layer_info_tex, .nearest);
            } else {
                gl.glGenTextures(1, &self.layer_info_tex);
                gl.glActiveTexture(gl.GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
                gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(INFO_WIDTH), @intCast(self.options.layer_info_height), 0, gl.GL_RGBA, gl.GL_FLOAT, null);
                setSampleParamsBind(gl.GL_TEXTURE_2D, .nearest);
            }
        }

        fn ensureImageArrayTexture(self: *Self, atlases: []const *const Atlas) UploadError!void {
            if (self.options.max_images == 0) return;

            // Reject images that would overflow the cache's storage. The
            // caller asked for caps that don't fit this content; bail
            // before allocating texture state.
            for (atlases) |atlas| {
                const records = atlas.paint_image_records orelse continue;
                for (records) |maybe_rec| {
                    const rec = maybe_rec orelse continue;
                    if (rec.image.width > self.options.max_image_width or rec.image.height > self.options.max_image_height) {
                        return error.ImageTooLarge;
                    }
                }
            }

            if (self.image_array_tex != 0) return;

            if (comptime variant.supportsDsa()) {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.image_array_tex);
                gl.glTextureStorage3D(self.image_array_tex, 1, gl.GL_SRGB8_ALPHA8, @intCast(self.options.max_image_width), @intCast(self.options.max_image_height), @intCast(self.options.max_images));
                setSampleParamsDsa(self.image_array_tex, .linear);
            } else {
                gl.glGenTextures(1, &self.image_array_tex);
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array_tex);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_SRGB8_ALPHA8, @intCast(self.options.max_image_width), @intCast(self.options.max_image_height), @intCast(self.options.max_images), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
                setSampleParamsBind(gl.GL_TEXTURE_2D_ARRAY, .linear);
            }
        }

        fn uploadPageFull(self: *Self, p: *const AtlasPage) void {
            const layer = p.layer_index;
            const curve_src = p.curve.data;
            const band_src = p.band.data;
            std.debug.assert(curve_src.len % CURVE_WORDS_PER_ROW == 0);
            std.debug.assert(band_src.len % BAND_WORDS_PER_ROW == 0);

            if (comptime variant.supportsDsa()) {
                gl.glTextureSubImage3D(self.curve_array, 0, 0, 0, @intCast(layer), @intCast(CURVE_TEX_WIDTH), @intCast(self.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, curve_src.ptr);
                gl.glTextureSubImage3D(self.band_array, 0, 0, 0, @intCast(layer), @intCast(BAND_TEX_WIDTH), @intCast(self.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, band_src.ptr);
            } else {
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, @intCast(layer), @intCast(CURVE_TEX_WIDTH), @intCast(self.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, curve_src.ptr);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, @intCast(layer), @intCast(BAND_TEX_WIDTH), @intCast(self.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, band_src.ptr);
            }

            self.prepared_curve_words[layer] = p.curve.usedWords();
            self.prepared_band_words[layer] = p.band.usedWords();
        }

        fn writeBindingData(self: *Self, scratch: std.mem.Allocator, atlas: *const Atlas, slot: *BindingSlot) UploadError!void {
            // Push stale pages.
            for (atlas.pages) |p| {
                const layer = p.layer_index;
                if (layer >= self.layer_count) return error.PageNotInPool;
                const cur_gen = p.currentGeneration();
                const cur_curve = p.curve.usedWords();
                const cur_band = p.band.usedWords();
                const stale = self.prepared_generation[layer] != cur_gen or
                    cur_curve != self.prepared_curve_words[layer] or
                    cur_band != self.prepared_band_words[layer];
                if (!stale) continue;
                self.prepared_generation[layer] = cur_gen;
                self.uploadPageFull(p);
            }

            if (atlas.layer_info_data == null) return;

            const src = atlas.layer_info_data.?;
            std.debug.assert(atlas.layer_info_width == INFO_WIDTH);
            std.debug.assert(@as(usize, atlas.layer_info_height) * INFO_WIDTH * 4 == src.len);

            const data_copy = try scratch.dupe(f32, src);
            defer scratch.free(data_copy);

            // Upload each unique image into its assigned slot layer and
            // patch the layer_info records with (abs_layer, uv_scale).
            if (atlas.paint_image_records) |records| {
                var local_layer: u32 = 0;
                var seen = std.AutoHashMap(*const Image, u32).init(scratch);
                defer seen.deinit();
                for (records) |maybe_rec| {
                    const rec = maybe_rec orelse continue;
                    const gop = try seen.getOrPut(rec.image);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = local_layer;
                        const abs_layer = slot.image_layer_base + local_layer;
                        self.image_storage[abs_layer] = rec.image;
                        self.uploadImageLayer(rec.image, abs_layer);
                        local_layer += 1;
                    }
                    const abs_layer = slot.image_layer_base + gop.value_ptr.*;
                    const uv_scale_x: f32 = @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(self.options.max_image_width));
                    const uv_scale_y: f32 = @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(self.options.max_image_height));
                    const View = struct {
                        layer: u32,
                        uv_scale: struct { x: f32, y: f32 },
                    };
                    upload_common.patchImagePaintRecord(data_copy, INFO_WIDTH, INFO_WIDTH, 0, rec.texel_offset, View{
                        .layer = abs_layer,
                        .uv_scale = .{ .x = uv_scale_x, .y = uv_scale_y },
                    });
                }
            }

            // Write patched data into the slot's row band of layer_info_tex.
            self.uploadLayerInfoRows(data_copy, slot.info_row_base, slot.info_height);
        }

        fn uploadImageLayer(self: *Self, img: *const Image, abs_layer: u32) void {
            if (comptime variant.supportsDsa()) {
                gl.glTextureSubImage3D(self.image_array_tex, 0, 0, 0, @intCast(abs_layer), @intCast(img.width), @intCast(img.height), 1, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, img.pixels.ptr);
            } else {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array_tex);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, @intCast(abs_layer), @intCast(img.width), @intCast(img.height), 1, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, img.pixels.ptr);
            }
        }

        fn uploadLayerInfoRows(self: *Self, data: []const f32, row_base: u32, height: u32) void {
            if (height == 0) return;
            if (comptime variant.supportsDsa()) {
                gl.glTextureSubImage2D(self.layer_info_tex, 0, 0, @intCast(row_base), @intCast(INFO_WIDTH), @intCast(height), gl.GL_RGBA, gl.GL_FLOAT, data.ptr);
            } else {
                gl.glActiveTexture(gl.GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
                gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, 0, @intCast(row_base), @intCast(INFO_WIDTH), @intCast(height), gl.GL_RGBA, gl.GL_FLOAT, data.ptr);
            }
        }

        // ── Slot allocator ──

        fn findFreeBinding(self: *Self) ?u32 {
            for (self.bindings, 0..) |*slot, i| {
                if (!slot.active) return @intCast(i);
            }
            return null;
        }

        fn findSlotByGeneration(self: *const Self, generation: u32) ?u32 {
            for (self.bindings, 0..) |*slot, i| {
                if (slot.active and slot.generation == generation) return @intCast(i);
            }
            return null;
        }

        fn takeLayerInfoRows(self: *Self, height: u32) UploadError!?LayerInfoRange {
            var i: usize = 0;
            while (i < self.free_layer_info_ranges.items.len) : (i += 1) {
                const r = self.free_layer_info_ranges.items[i];
                if (r.height >= height) {
                    if (r.height == height) {
                        _ = self.free_layer_info_ranges.orderedRemove(i);
                    } else {
                        self.free_layer_info_ranges.items[i] = .{ .row_base = r.row_base + height, .height = r.height - height };
                    }
                    return LayerInfoRange{ .row_base = r.row_base, .height = height };
                }
            }
            return null;
        }

        fn releaseLayerInfoRange(self: *Self, range: LayerInfoRange) !void {
            if (range.height == 0) return;
            try self.free_layer_info_ranges.append(self.allocator, range);
            std.mem.sort(LayerInfoRange, self.free_layer_info_ranges.items, {}, struct {
                fn lessThan(_: void, a: LayerInfoRange, b: LayerInfoRange) bool {
                    return a.row_base < b.row_base;
                }
            }.lessThan);
            var write: usize = 0;
            var read: usize = 0;
            while (read < self.free_layer_info_ranges.items.len) {
                var cur = self.free_layer_info_ranges.items[read];
                read += 1;
                while (read < self.free_layer_info_ranges.items.len) {
                    const nxt = self.free_layer_info_ranges.items[read];
                    if (cur.row_base + cur.height == nxt.row_base) {
                        cur.height += nxt.height;
                        read += 1;
                    } else break;
                }
                self.free_layer_info_ranges.items[write] = cur;
                write += 1;
            }
            self.free_layer_info_ranges.shrinkRetainingCapacity(write);
        }

        fn takeImageLayers(self: *Self, count: u32) UploadError!?ImageRange {
            var i: usize = 0;
            while (i < self.free_image_ranges.items.len) : (i += 1) {
                const r = self.free_image_ranges.items[i];
                if (r.count >= count) {
                    if (r.count == count) {
                        _ = self.free_image_ranges.orderedRemove(i);
                    } else {
                        self.free_image_ranges.items[i] = .{ .layer_base = r.layer_base + count, .count = r.count - count };
                    }
                    return ImageRange{ .layer_base = r.layer_base, .count = count };
                }
            }
            return null;
        }

        fn releaseImageRange(self: *Self, range: ImageRange) !void {
            if (range.count == 0) return;
            try self.free_image_ranges.append(self.allocator, range);
            std.mem.sort(ImageRange, self.free_image_ranges.items, {}, struct {
                fn lessThan(_: void, a: ImageRange, b: ImageRange) bool {
                    return a.layer_base < b.layer_base;
                }
            }.lessThan);
            var write: usize = 0;
            var read: usize = 0;
            while (read < self.free_image_ranges.items.len) {
                var cur = self.free_image_ranges.items[read];
                read += 1;
                while (read < self.free_image_ranges.items.len) {
                    const nxt = self.free_image_ranges.items[read];
                    if (cur.layer_base + cur.count == nxt.layer_base) {
                        cur.count += nxt.count;
                        read += 1;
                    } else break;
                }
                self.free_image_ranges.items[write] = cur;
                write += 1;
            }
            self.free_image_ranges.shrinkRetainingCapacity(write);
        }

        // ── GL helpers ──

        const FilterKind = enum { nearest, linear };

        fn setSampleParamsBind(target: gl.GLenum, filter: FilterKind) void {
            const f: gl.GLint = if (filter == .nearest) gl.GL_NEAREST else gl.GL_LINEAR;
            gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, f);
            gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, f);
            gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        }

        fn setSampleParamsDsa(tex: gl.GLuint, filter: FilterKind) void {
            const f: gl.GLint = if (filter == .nearest) gl.GL_NEAREST else gl.GL_LINEAR;
            gl.glTextureParameteri(tex, gl.GL_TEXTURE_MIN_FILTER, f);
            gl.glTextureParameteri(tex, gl.GL_TEXTURE_MAG_FILTER, f);
            gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        }
    };
}

fn countUniqueImages(atlas: *const Atlas) u32 {
    const records = atlas.paint_image_records orelse return 0;
    var seen_count: u32 = 0;
    for (records, 0..) |maybe_rec, i| {
        const rec = maybe_rec orelse continue;
        var duplicate = false;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            const prev = records[j] orelse continue;
            if (prev.image == rec.image) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) seen_count += 1;
    }
    return seen_count;
}

pub const Gl33BackendCache = GlBackendCacheFor(.gl33);
pub const Gl44BackendCache = GlBackendCacheFor(.gl44);
pub const Gles30BackendCache = GlBackendCacheFor(.gles30);

// ── Tests (data only — no GL calls) ──

const testing = std.testing;

test "GlBackendCache init allocates fixed-capacity slots" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 2,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    var cache = try Gl33BackendCache.init(testing.allocator, pool, .{
        .max_bindings = 3,
        .layer_info_height = 8,
        .max_images = 2,
        .max_image_width = 64,
        .max_image_height = 64,
    });
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 3), cache.bindings.len);
    try testing.expectEqual(@as(usize, 2), cache.image_storage.len);
    try testing.expectEqual(@as(usize, 1), cache.free_layer_info_ranges.items.len);
    try testing.expectEqual(@as(u32, 8), cache.free_layer_info_ranges.items[0].height);
    try testing.expectEqual(@as(usize, 1), cache.free_image_ranges.items.len);
    try testing.expectEqual(@as(u32, 2), cache.free_image_ranges.items[0].count);
}

test "GlBackendCache release returns slot ranges to free list" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = CURVE_WORDS_PER_ROW,
        .band_words_per_page = BAND_WORDS_PER_ROW,
    });
    defer pool.deinit();

    var cache = try Gl33BackendCache.init(testing.allocator, pool, .{
        .max_bindings = 2,
        .layer_info_height = 4,
        .max_images = 0,
    });
    defer cache.deinit();

    // Forge a slot rather than calling upload (which would touch GL).
    cache.bindings[0] = .{ .active = true, .generation = 1, .info_row_base = 0, .info_height = 2 };
    cache.active_bindings = 1;
    _ = try cache.takeLayerInfoRows(2);

    cache.release(.{ .pool = pool, .generation = 1 });
    try testing.expectEqual(@as(u32, 0), cache.active_bindings);
    try testing.expectEqual(@as(usize, 1), cache.free_layer_info_ranges.items.len);
    try testing.expectEqual(@as(u32, 4), cache.free_layer_info_ranges.items[0].height);
}

comptime {
    _ = paint_records;
}
