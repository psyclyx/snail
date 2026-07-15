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

const atlas_mod = @import("snail_core").files.atlas;
const draw_records = @import("snail_core").files.picture_draw_records;
const page_pool_mod = @import("snail_core").files.atlas_page_pool;
const page_mod = @import("snail_core").files.atlas_page;
const curve_tex = @import("snail_core").files.format_curve_texture;
const band_tex = @import("snail_core").files.format_band_texture;
const paint_records = @import("snail_core").files.atlas_paint_records;
const upload_common = @import("snail_core").files.format_upload_common;
const image_mod = @import("snail_core").files.image;
const cache_base = @import("snail_core").files.backend_cache_base;
const upload_plan = @import("snail_core").files.atlas_upload_plan;
const range_allocator = @import("snail_core").files.backend_range_allocator;

const RangeAllocator = range_allocator.RangeAllocator;
const Range = range_allocator.Range;

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
        .gles30 => @import("gles30/bindings.zig"),
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
pub const UploadError = cache_base.BaseUploadError || upload_plan.Error || error{ImageTooLarge};
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

        // Persistent image array (TEXTURE_2D_ARRAY of sRGBA8).
        image_array_tex: gl.GLuint = 0,

        // Font-atlas upload planning — caller-owned state (snail.AtlasUploadPlanner).
        // The cache keeps only the GL textures; allocation/deltas/patching are the
        // planner's. Backing slices are cache-owned.
        planner: upload_plan.Planner,
        plan_gen: []u16,
        plan_curve: []u32,
        plan_band: []u32,
        plan_slots: []upload_plan.Slot,
        plan_info_free: []upload_plan.Range,
        plan_image_free: []upload_plan.Range,
        plan_regions: []upload_plan.Region,
        plan_info_scratch: []f32,
        info_scratch_stride: usize,
        active_bindings: u32 = 0,
        // Highest atlas generation uploaded so far — a coarse residency proxy the
        // all-in-one renderer uses to reject stale bindings. Advanced by the
        // planner-driven upload paths; never affects texel output.
        upload_generation: u32 = 0,

        fn plannerOptions(pool: *PagePool, options: CacheOptions) upload_plan.Options {
            return .{
                .max_layers = pool.options.max_layers,
                .max_bindings = options.max_bindings,
                .layer_info_height = options.layer_info_height,
                .max_images = options.max_images,
                .max_image_width = options.max_image_width,
                .max_image_height = options.max_image_height,
                .curve_height = pool.options.curve_words_per_page / CURVE_WORDS_PER_ROW,
                .band_height = pool.options.band_words_per_page / BAND_WORDS_PER_ROW,
            };
        }

        pub fn init(allocator: std.mem.Allocator, pool: *PagePool, options: CacheOptions) !Self {
            const opts = plannerOptions(pool, options);
            const sz = upload_plan.sizes(opts);

            const gen = try allocator.alloc(u16, sz.generation);
            errdefer allocator.free(gen);
            const curve_words = try allocator.alloc(u32, sz.curve_words);
            errdefer allocator.free(curve_words);
            const band_words = try allocator.alloc(u32, sz.band_words);
            errdefer allocator.free(band_words);
            const slots = try allocator.alloc(upload_plan.Slot, sz.bindings);
            errdefer allocator.free(slots);
            const info_free = try allocator.alloc(upload_plan.Range, sz.info_free);
            errdefer allocator.free(info_free);
            const image_free = try allocator.alloc(upload_plan.Range, sz.image_free);
            errdefer allocator.free(image_free);
            const regions = try allocator.alloc(upload_plan.Region, sz.regions);
            errdefer allocator.free(regions);
            const info_scratch = try allocator.alloc(f32, sz.layer_info_scratch * options.max_bindings);
            errdefer allocator.free(info_scratch);

            return .{
                .allocator = allocator,
                .pool = pool,
                .options = options,
                .planner = upload_plan.Planner.init(opts, gen, curve_words, band_words, slots, info_free, image_free),
                .plan_gen = gen,
                .plan_curve = curve_words,
                .plan_band = band_words,
                .plan_slots = slots,
                .plan_info_free = info_free,
                .plan_image_free = image_free,
                .plan_regions = regions,
                .plan_info_scratch = info_scratch,
                .info_scratch_stride = sz.layer_info_scratch,
            };
        }

        pub fn deinit(self: *Self) void {
            self.destroyTextures();
            self.allocator.free(self.plan_gen);
            self.allocator.free(self.plan_curve);
            self.allocator.free(self.plan_band);
            self.allocator.free(self.plan_slots);
            self.allocator.free(self.plan_info_free);
            self.allocator.free(self.plan_image_free);
            self.allocator.free(self.plan_regions);
            self.allocator.free(self.plan_info_scratch);
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

            const opts = plannerOptions(self.pool, options);
            const sz = upload_plan.sizes(opts);
            self.plan_gen = try self.allocator.realloc(self.plan_gen, sz.generation);
            self.plan_curve = try self.allocator.realloc(self.plan_curve, sz.curve_words);
            self.plan_band = try self.allocator.realloc(self.plan_band, sz.band_words);
            self.plan_slots = try self.allocator.realloc(self.plan_slots, sz.bindings);
            self.plan_info_free = try self.allocator.realloc(self.plan_info_free, sz.info_free);
            self.plan_image_free = try self.allocator.realloc(self.plan_image_free, sz.image_free);
            self.plan_regions = try self.allocator.realloc(self.plan_regions, sz.regions);
            self.plan_info_scratch = try self.allocator.realloc(self.plan_info_scratch, sz.layer_info_scratch * options.max_bindings);
            self.info_scratch_stride = sz.layer_info_scratch;
            self.planner = upload_plan.Planner.init(opts, self.plan_gen, self.plan_curve, self.plan_band, self.plan_slots, self.plan_info_free, self.plan_image_free);
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

            _ = scratch;
            self.ensurePoolTextures();
            self.ensureLayerInfoTexture();
            try self.ensureImageArrayTexture(atlases);

            var planned: usize = 0;
            errdefer for (out_bindings[0..planned]) |b| {
                _ = self.planner.release(b);
            };

            for (atlases, 0..) |atlas, i| {
                var len: usize = 0;
                const info_scratch = self.plan_info_scratch[i * self.info_scratch_stride ..][0..self.info_scratch_stride];
                out_bindings[i] = try self.planner.plan(atlas, self.pool, self.plan_regions, &len, info_scratch);
                planned = i + 1;
                for (self.plan_regions[0..len]) |r| self.applyRegion(r);
                self.upload_generation = @max(self.upload_generation, out_bindings[i].generation);
            }

            self.active_bindings += @intCast(atlases.len);
        }

        /// Incrementally upload `atlas` into the existing slot held by
        /// `prev_binding`. The slot's `info_row_base` and
        /// `image_layer_base` reservations are reused; the atlas's
        /// per-page curve / band watermarks decide which bytes actually
        /// ship. Intended for the terminal hot path: the same `Atlas` is
        /// grown via `Atlas.extend`, and only the new bytes get
        /// uploaded.
        ///
        /// Semantics across `atlas` shapes:
        /// - **Extension of the prior atlas** (the design target). Pages
        ///   share identity with the prior upload; only pages whose
        ///   `usedWords` advanced past the cache's recorded watermark
        ///   ship new bytes. Layer-info rows are fully rewritten in the
        ///   slot's reserved row band (cheap — this is one
        ///   `TexSubImage2D` over a small region).
        /// - **Different atlas on the same pool**. Permitted. The
        ///   cache's per-layer page tracking notices the `currentGeneration()`
        ///   change and re-uploads each affected page in full. Layer-info
        ///   rows and images are overwritten in the slot's reservation
        ///   the same way. This is `upload(scratch, &.{atlas})` in
        ///   essence — same correctness, more bytes than a pure
        ///   extension would have shipped.
        /// - **Different pool**. `error.UnknownPool`.
        /// - **Slot already released** (or never minted by this
        ///   cache). `error.UnknownBinding` — caller must call `upload`
        ///   to mint a fresh binding.
        /// - **`atlas` outgrew the slot's `info_height` /
        ///   `image_count` reservation**. `error.NoLayerInfoRoomToGrow`
        ///   — caller must `release(prev_binding)` and call `upload`
        ///   to obtain a slot sized for the new atlas. (The reservation
        ///   is fixed at first upload; growing it would invalidate
        ///   in-flight `info_row_base` offsets baked into emitted
        ///   draw words.)
        ///
        /// Returns the (same-slot) binding so the caller can keep
        /// using one variable. The returned binding's `generation`
        /// matches `prev_binding.generation` — the slot identity is
        /// stable across `uploadDelta` calls.
        pub fn uploadDelta(
            self: *Self,
            scratch: std.mem.Allocator,
            prev_binding: Binding,
            atlas: *const Atlas,
        ) UploadError!Binding {
            _ = scratch;
            if (atlas.pool) |p| {
                if (p != self.pool) return error.UnknownPool;
            }
            self.ensurePoolTextures();
            self.ensureLayerInfoTexture();
            try self.ensureImageArrayTexture(&.{atlas});

            var len: usize = 0;
            const info_scratch = self.plan_info_scratch[0..self.info_scratch_stride];
            const binding = try self.planner.planDelta(prev_binding, atlas, self.pool, self.plan_regions, &len, info_scratch);
            for (self.plan_regions[0..len]) |r| self.applyRegion(r);
            self.upload_generation = @max(self.upload_generation, binding.generation);
            return binding;
        }

        pub fn release(self: *Self, binding: Binding) void {
            if (self.planner.release(binding)) {
                if (self.active_bindings > 0) self.active_bindings -= 1;
            }
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

        // ── Apply a planner Region to the caller's textures ──

        fn applyRegion(self: *Self, r: upload_plan.Region) void {
            switch (r.target) {
                .curve => self.texSubImage3D(self.curve_array, 0, r.layer, r.width, r.height, gl.GL_RGBA, gl.GL_HALF_FLOAT, r.src.ptr),
                .band => self.texSubImage3D(self.band_array, 1, r.layer, r.width, r.height, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, r.src.ptr),
                .image => self.texSubImage3D(self.image_array_tex, 3, r.layer, r.width, r.height, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, r.src.ptr),
                .layer_info => self.texSubImage2D(self.layer_info_tex, 2, r.row_base, r.width, r.height, gl.GL_RGBA, gl.GL_FLOAT, r.src.ptr),
            }
        }

        fn texSubImage3D(self: *Self, tex: gl.GLuint, unit: gl.GLenum, layer: u32, width: u32, height: u32, format: gl.GLenum, ty: gl.GLenum, ptr: ?*const anyopaque) void {
            _ = self;
            if (comptime variant.supportsDsa()) {
                gl.glTextureSubImage3D(tex, 0, 0, 0, @intCast(layer), @intCast(width), @intCast(height), 1, format, ty, ptr);
            } else {
                gl.glActiveTexture(@intCast(@as(i64, @intCast(gl.GL_TEXTURE0)) + @as(i64, @intCast(unit))));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, tex);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, @intCast(layer), @intCast(width), @intCast(height), 1, format, ty, ptr);
            }
        }

        fn texSubImage2D(self: *Self, tex: gl.GLuint, unit: gl.GLenum, row_base: u32, width: u32, height: u32, format: gl.GLenum, ty: gl.GLenum, ptr: ?*const anyopaque) void {
            _ = self;
            if (height == 0) return;
            if (comptime variant.supportsDsa()) {
                gl.glTextureSubImage2D(tex, 0, 0, @intCast(row_base), @intCast(width), @intCast(height), format, ty, ptr);
            } else {
                gl.glActiveTexture(@intCast(@as(i64, @intCast(gl.GL_TEXTURE0)) + @as(i64, @intCast(unit))));
                gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
                gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, 0, @intCast(row_base), @intCast(width), @intCast(height), format, ty, ptr);
            }
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

    // Planner backing sized from the caller's options (allocation + range logic
    // now lives in `snail.AtlasUploadPlanner`, unit-tested in upload_plan.zig).
    try testing.expectEqual(@as(usize, 3), cache.plan_slots.len);
    try testing.expectEqual(@as(usize, 4), cache.plan_gen.len);
}

comptime {
    _ = paint_records;
}
