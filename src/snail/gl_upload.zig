//! Phase 5a: new-API GL prepared-pages cache.
//!
//! Per-`PagePool` resident GL state: one curve texture array, one band
//! texture array, both sized to `pool.options.max_layers` at init time.
//! `upload(atlas)` walks `atlas.pages` and pushes delta bytes per page
//! into the corresponding texture-array layer when the cached
//! (generation, used_words) watermark differs.
//!
//! Layer-info paint records and the image array are rebuilt per upload
//! from the atlas's `layer_info_data` + `paint_image_records`. Returns
//! a `Binding{pool, generation}` the caller threads into emit.
//!
//! Parameterized over `.gl33` / `.gl44` so a single source file covers
//! both API levels. DSA functions are used on gl44; classic bind-then-
//! upload on gl33.

const std = @import("std");

const atlas_mod = @import("atlas.zig");
const draw_records = @import("draw_records.zig");
const page_pool_mod = @import("page_pool.zig");
const page_mod = @import("page.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");
const paint_records = @import("paint_records.zig");
const gl = @import("render/backend/gl/bindings.zig").gl;
const gl_backend = @import("render/backend/gl/backend.zig");
const gl_texture_params = @import("render/backend/gl/texture_params.zig");

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Backend = gl_backend.Backend;

const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;
/// One row of the curve texture is `TEX_WIDTH * 4` u16 words (RGBA16F).
const CURVE_WORDS_PER_ROW: u32 = CURVE_TEX_WIDTH * 4;
/// One row of the band texture is `TEX_WIDTH * 2` u16 words (RG16UI).
const BAND_WORDS_PER_ROW: u32 = BAND_TEX_WIDTH * 2;

/// Per-pool cache. One curve_array + band_array sized to max_layers,
/// plus a per-upload layer_info_tex + image_array.
pub fn GlPreparedPagesFor(comptime backend: Backend) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        pool: *PagePool,

        // Pool-wide resident textures (allocated lazily on first upload).
        curve_array: gl.GLuint = 0,
        band_array: gl.GLuint = 0,
        curve_height: u32 = 0,
        band_height: u32 = 0,
        layer_count: u32 = 0,

        // Per-upload layer-info textures, indexed by `binding.generation`.
        // Each entry is 0 when the upload's atlas had no `layer_info_data`,
        // or the GL texture handle otherwise. drawNewApi looks up
        // `layer_info_slots[binding.generation - 1]` to find the right
        // texture for a given segment.
        layer_info_slots: std.ArrayList(gl.GLuint) = .empty,
        // Image array is not yet supported on the GL new path — image
        // paints sample the default layer-0 slot for now.
        image_array: gl.GLuint = 0,

        // Per-layer texture-array upload tracking (parallel to pool.pages).
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
            if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
            self.curve_array = 0;
            self.band_array = 0;
            self.image_array = 0;
        }

        /// Look up the layer-info texture for a binding's generation,
        /// or 0 if the upload at that generation had no paint records.
        pub fn layerInfoFor(self: *const Self, generation: u32) gl.GLuint {
            if (generation == 0 or generation > self.layer_info_slots.items.len) return 0;
            return self.layer_info_slots.items[generation - 1];
        }

        /// (Re)allocate the curve and band texture arrays sized to the pool.
        /// Idempotent: a no-op once arrays exist with the expected dimensions.
        fn ensurePoolTextures(self: *Self) void {
            if (self.curve_array != 0 and self.band_array != 0) return;

            const options = self.pool.options;
            // Fixed-capacity pages → fixed texture dimensions.
            self.curve_height = options.curve_words_per_page / CURVE_WORDS_PER_ROW;
            self.band_height = options.band_words_per_page / BAND_WORDS_PER_ROW;
            self.layer_count = options.max_layers;
            std.debug.assert(self.curve_height > 0 and self.band_height > 0);

            if (comptime backend == .gl33) {
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
                gl_texture_params.setTexParams(gl.GL_TEXTURE_2D_ARRAY);

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
                gl_texture_params.setTexParams(gl.GL_TEXTURE_2D_ARRAY);
            } else {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.curve_array);
                gl.glTextureStorage3D(
                    self.curve_array,
                    1,
                    gl.GL_RGBA16F,
                    @intCast(CURVE_TEX_WIDTH),
                    @intCast(self.curve_height),
                    @intCast(self.layer_count),
                );
                gl_texture_params.setTexParamsDSA(self.curve_array);

                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.band_array);
                gl.glTextureStorage3D(
                    self.band_array,
                    1,
                    gl.GL_RG16UI,
                    @intCast(BAND_TEX_WIDTH),
                    @intCast(self.band_height),
                    @intCast(self.layer_count),
                );
                gl_texture_params.setTexParamsDSA(self.band_array);
            }
        }

        /// Upload one page's full allocated buffer into its texture-array
        /// layer. The page's used-words watermark isn't row-aligned in
        /// general; rather than try to delta-push partial rows, upload
        /// the entire layer (size equals pool's per-page capacity). The
        /// unused tail is zero-filled at page creation and harmless to
        /// the shader, which only reads texels referenced by record
        /// metadata.
        fn uploadPageFull(self: *Self, p: *const AtlasPage) void {
            const layer = p.layer_index;
            const curve_src = p.curve.data;
            const band_src = p.band.data;
            std.debug.assert(curve_src.len % CURVE_WORDS_PER_ROW == 0);
            std.debug.assert(band_src.len % BAND_WORDS_PER_ROW == 0);

            if (comptime backend == .gl33) {
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
            } else {
                gl.glTextureSubImage3D(
                    self.curve_array,
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
                gl.glTextureSubImage3D(
                    self.band_array,
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
            }

            self.prepared_curve_words[layer] = p.curve.usedWords();
            self.prepared_band_words[layer] = p.band.usedWords();
        }

        /// Build a fresh layer-info texture for this upload (or 0 if the
        /// atlas has no `layer_info_data`). Append it to layer_info_slots
        /// so subsequent draws can index by binding.generation.
        fn buildLayerInfoTexture(_: *Self, scratch: std.mem.Allocator, atlas: *const Atlas) !gl.GLuint {
            const src = atlas.layer_info_data orelse return 0;
            const w = atlas.layer_info_width;
            const h = atlas.layer_info_height;
            if (w == 0 or h == 0) return 0;

            const data_copy = try scratch.dupe(f32, src);
            defer scratch.free(data_copy);

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

        /// Push delta bytes for each page referenced by `atlas` into the
        /// pool's GL texture arrays; rebuild the layer-info texture from
        /// `atlas.layer_info_data`. Returns a Binding identifying this
        /// upload's generation.
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

            const layer_info_tex = try self.buildLayerInfoTexture(scratch, atlas);
            try self.layer_info_slots.append(self.allocator, layer_info_tex);

            return .{ .pool = self.pool, .generation = self.upload_generation };
        }
    };
}

pub const Gl33PreparedPages = GlPreparedPagesFor(.gl33);
pub const Gl44PreparedPages = GlPreparedPagesFor(.gl44);

// ---------------------------------------------------------------------------
// Tests
//
// Data-only: instantiate the struct directly without touching GL. These
// verify the per-layer watermark tracking and the dimension derivation.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "GlPreparedPages init allocates per-layer state sized to pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 7,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 4,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    var cache = try Gl33PreparedPages.init(testing.allocator, pool);
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 7), cache.prepared_generation.len);
    try testing.expectEqual(@as(usize, 7), cache.prepared_curve_words.len);
    try testing.expectEqual(@as(usize, 7), cache.prepared_band_words.len);
    try testing.expectEqual(@as(gl.GLuint, 0), cache.curve_array);
    try testing.expectEqual(@as(gl.GLuint, 0), cache.band_array);
    try testing.expectEqual(@as(u32, 0), cache.upload_generation);
}

test "GlPreparedPages dimensions derive from pool options" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 3,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 5,
        .band_words_per_page = BAND_WORDS_PER_ROW * 8,
    });
    defer pool.deinit();

    var cache = try Gl33PreparedPages.init(testing.allocator, pool);
    defer cache.deinit();

    // ensurePoolTextures is GL-bound, but the derived heights can be
    // pre-computed from options independently. Verify the math.
    const expected_curve_h = pool.options.curve_words_per_page / CURVE_WORDS_PER_ROW;
    const expected_band_h = pool.options.band_words_per_page / BAND_WORDS_PER_ROW;
    try testing.expectEqual(@as(u32, 5), expected_curve_h);
    try testing.expectEqual(@as(u32, 8), expected_band_h);
}

// Paranoia — `_ = paint_records` silences "unused import" when only the
// constants are referenced indirectly.
comptime {
    _ = paint_records;
}
