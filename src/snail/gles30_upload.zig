//! Phase 5b: new-API GLES3 prepared-pages cache.
//!
//! Mirrors `gl_upload.GlPreparedPagesFor(.gl33)` but uses the GLES3
//! binding module. GLES3 has no DSA so all uploads go through the
//! bind-then-upload pattern. The texture formats (RGBA16F, RG16UI,
//! SRGB8_ALPHA8) and the sampling shaders are the same — the new
//! path's drawNewApi on `Gles30TextState` consumes this cache the
//! same way the GL `drawNewApi` consumes `GlPreparedPages`.

const std = @import("std");

const atlas_mod = @import("atlas.zig");
const draw_records = @import("draw_records.zig");
const page_pool_mod = @import("page_pool.zig");
const page_mod = @import("page.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");
const upload_common = @import("render/format/upload_common.zig");
const image_mod = @import("image.zig");
const gl = @import("render/backend/gles30/bindings.zig").gl;

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Image = image_mod.Image;

const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;
const CURVE_WORDS_PER_ROW: u32 = CURVE_TEX_WIDTH * 4;
const BAND_WORDS_PER_ROW: u32 = BAND_TEX_WIDTH * 2;

fn setTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setImageTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

pub const Gles30PreparedPages = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: *PagePool,

    curve_array: gl.GLuint = 0,
    band_array: gl.GLuint = 0,
    curve_height: u32 = 0,
    band_height: u32 = 0,
    layer_count: u32 = 0,

    layer_info_slots: std.ArrayList(gl.GLuint) = .empty,
    image_array_slots: std.ArrayList(gl.GLuint) = .empty,

    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,

    upload_generation: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) !Self {
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

        return .{
            .allocator = allocator,
            .pool = pool,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
        };
    }

    pub fn deinit(self: *Self) void {
        self.destroyTextures();
        self.layer_info_slots.deinit(self.allocator);
        self.image_array_slots.deinit(self.allocator);
        self.allocator.free(self.prepared_generation);
        self.allocator.free(self.prepared_curve_words);
        self.allocator.free(self.prepared_band_words);
        self.* = undefined;
    }

    fn destroyTextures(self: *Self) void {
        if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
        if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
        for (self.layer_info_slots.items) |tex| {
            if (tex != 0) gl.glDeleteTextures(1, &tex);
        }
        self.layer_info_slots.clearRetainingCapacity();
        for (self.image_array_slots.items) |tex| {
            if (tex != 0) gl.glDeleteTextures(1, &tex);
        }
        self.image_array_slots.clearRetainingCapacity();
        self.curve_array = 0;
        self.band_array = 0;
    }

    pub fn layerInfoFor(self: *const Self, generation: u32) gl.GLuint {
        if (generation == 0 or generation > self.layer_info_slots.items.len) return 0;
        return self.layer_info_slots.items[generation - 1];
    }

    pub fn imageArrayFor(self: *const Self, generation: u32) gl.GLuint {
        if (generation == 0 or generation > self.image_array_slots.items.len) return 0;
        return self.image_array_slots.items[generation - 1];
    }

    fn ensurePoolTextures(self: *Self) void {
        if (self.curve_array != 0 and self.band_array != 0) return;

        const options = self.pool.options;
        self.curve_height = options.curve_words_per_page / CURVE_WORDS_PER_ROW;
        self.band_height = options.band_words_per_page / BAND_WORDS_PER_ROW;
        self.layer_count = options.max_layers;
        std.debug.assert(self.curve_height > 0 and self.band_height > 0);

        gl.glGenTextures(1, &self.curve_array);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
        gl.glTexImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            gl.GL_RGBA16F,
            @intCast(CURVE_TEX_WIDTH),
            @intCast(self.curve_height),
            @intCast(self.layer_count),
            0,
            gl.GL_RGBA,
            gl.GL_HALF_FLOAT,
            null,
        );
        setTexParams(gl.GL_TEXTURE_2D_ARRAY);

        gl.glGenTextures(1, &self.band_array);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
        gl.glTexImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            gl.GL_RG16UI,
            @intCast(BAND_TEX_WIDTH),
            @intCast(self.band_height),
            @intCast(self.layer_count),
            0,
            gl.GL_RG_INTEGER,
            gl.GL_UNSIGNED_SHORT,
            null,
        );
        setTexParams(gl.GL_TEXTURE_2D_ARRAY);
    }

    fn uploadPageFull(self: *Self, p: *const AtlasPage) void {
        const layer = p.layer_index;
        const curve_src = p.curve.data;
        const band_src = p.band.data;
        std.debug.assert(curve_src.len % CURVE_WORDS_PER_ROW == 0);
        std.debug.assert(band_src.len % BAND_WORDS_PER_ROW == 0);

        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
        gl.glTexSubImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            0,
            0,
            @intCast(layer),
            @intCast(CURVE_TEX_WIDTH),
            @intCast(self.curve_height),
            1,
            gl.GL_RGBA,
            gl.GL_HALF_FLOAT,
            curve_src.ptr,
        );
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
        gl.glTexSubImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            0,
            0,
            @intCast(layer),
            @intCast(BAND_TEX_WIDTH),
            @intCast(self.band_height),
            1,
            gl.GL_RG_INTEGER,
            gl.GL_UNSIGNED_SHORT,
            band_src.ptr,
        );

        self.prepared_curve_words[layer] = p.curve.usedWords();
        self.prepared_band_words[layer] = p.band.usedWords();
    }

    const UploadedImages = struct {
        image_array: gl.GLuint = 0,
        allocated_width: u32 = 0,
        allocated_height: u32 = 0,
        layer_count: u32 = 0,
        unique_images: std.ArrayList(*const Image) = .empty,

        fn deinit(self: *UploadedImages, allocator: std.mem.Allocator) void {
            self.unique_images.deinit(allocator);
        }

        fn layerForImage(self: *const UploadedImages, image: *const Image) ?u32 {
            for (self.unique_images.items, 0..) |existing, i| {
                if (existing == image) return @intCast(i);
            }
            return null;
        }
    };

    fn buildImageArray(_: *Self, scratch: std.mem.Allocator, atlas: *const Atlas) !UploadedImages {
        const records = atlas.paint_image_records orelse return .{};
        var result = UploadedImages{};
        errdefer result.deinit(scratch);

        for (records) |maybe_rec| {
            const rec = maybe_rec orelse continue;
            if (result.layerForImage(rec.image) != null) continue;
            try result.unique_images.append(scratch, rec.image);
        }
        if (result.unique_images.items.len == 0) return result;

        var max_w: u32 = 1;
        var max_h: u32 = 1;
        for (result.unique_images.items) |img| {
            max_w = @max(max_w, img.width);
            max_h = @max(max_h, img.height);
        }
        const alloc_w = upload_common.imageExtentCapacity(max_w);
        const alloc_h = upload_common.imageExtentCapacity(max_h);
        const layer_count: u32 = @intCast(result.unique_images.items.len);
        result.allocated_width = alloc_w;
        result.allocated_height = alloc_h;
        result.layer_count = layer_count;

        gl.glGenTextures(1, &result.image_array);
        gl.glActiveTexture(gl.GL_TEXTURE3);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, result.image_array);
        gl.glTexImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            gl.GL_SRGB8_ALPHA8,
            @intCast(alloc_w),
            @intCast(alloc_h),
            @intCast(layer_count),
            0,
            gl.GL_RGBA,
            gl.GL_UNSIGNED_BYTE,
            null,
        );
        setImageTexParams(gl.GL_TEXTURE_2D_ARRAY);

        for (result.unique_images.items, 0..) |img, layer| {
            gl.glTexSubImage3D(
                gl.GL_TEXTURE_2D_ARRAY,
                0,
                0,
                0,
                @intCast(layer),
                @intCast(img.width),
                @intCast(img.height),
                1,
                gl.GL_RGBA,
                gl.GL_UNSIGNED_BYTE,
                img.pixels.ptr,
            );
        }
        return result;
    }

    fn buildLayerInfoTexture(_: *Self, scratch: std.mem.Allocator, atlas: *const Atlas, images: *const UploadedImages) !gl.GLuint {
        const src = atlas.layer_info_data orelse return 0;
        const w = atlas.layer_info_width;
        const h = atlas.layer_info_height;
        if (w == 0 or h == 0) return 0;

        const data_copy = try scratch.dupe(f32, src);
        defer scratch.free(data_copy);

        if (atlas.paint_image_records) |records| {
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                const layer = images.layerForImage(rec.image) orelse continue;
                const uv_scale_x: f32 = if (images.allocated_width == 0) 1.0 else @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(images.allocated_width));
                const uv_scale_y: f32 = if (images.allocated_height == 0) 1.0 else @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(images.allocated_height));
                const View = struct {
                    layer: u32,
                    uv_scale: struct { x: f32, y: f32 },
                };
                upload_common.patchImagePaintRecord(data_copy, w, w, 0, rec.texel_offset, View{
                    .layer = layer,
                    .uv_scale = .{ .x = uv_scale_x, .y = uv_scale_y },
                });
            }
        }

        var tex: gl.GLuint = 0;
        gl.glGenTextures(1, &tex);
        gl.glActiveTexture(gl.GL_TEXTURE2);
        gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            gl.GL_RGBA32F,
            @intCast(w),
            @intCast(h),
            0,
            gl.GL_RGBA,
            gl.GL_FLOAT,
            @ptrCast(data_copy.ptr),
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        return tex;
    }

    pub fn upload(self: *Self, scratch: std.mem.Allocator, atlas: *const Atlas) !Binding {
        self.upload_generation += 1;
        self.ensurePoolTextures();

        for (atlas.pages) |p| {
            const layer = p.layer_index;
            std.debug.assert(layer < self.layer_count);
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

        var images = try self.buildImageArray(scratch, atlas);
        defer images.deinit(scratch);
        const layer_info_tex = try self.buildLayerInfoTexture(scratch, atlas, &images);
        try self.layer_info_slots.append(self.allocator, layer_info_tex);
        try self.image_array_slots.append(self.allocator, images.image_array);

        return .{ .pool = self.pool, .generation = self.upload_generation };
    }
};

const testing = std.testing;

test "Gles30PreparedPages init allocates per-layer state sized to pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 5,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 4,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    var cache = try Gles30PreparedPages.init(testing.allocator, pool);
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 5), cache.prepared_generation.len);
    try testing.expectEqual(@as(u32, 0), cache.upload_generation);
}
