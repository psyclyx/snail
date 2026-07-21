//! The software rasterizer's device-side atlas: resident CPU copies of
//! uploaded atlas records for one `PagePool`, with caller-controlled
//! lifecycle primitives.
//!
//! Placement (binding slots, layer-info rows, image layers) is driven by
//! the shared `snail.atlas_upload` planner — the same planner the GPU
//! reference callers use — so bindings and the emit stream are identical
//! across backends by construction. This type owns only the CPU "device"
//! side: prepared per-layer page copies (curve/band reads stay zero-copy
//! against pool pages), the persistent layer-info buffer, and the image
//! pointer table.
//!
//! - `init(allocator, pool, options)` allocates fixed-capacity storage
//!   for `max_bindings`, `layer_info_height` rows of paint records, and
//!   `max_images` image references. The caller decides how much is
//!   enough; a `DeviceAtlas` never auto-grows.
//! - `upload(scratch, atlases)` plans one binding per atlas and applies
//!   the planned regions. Errors with `error.NoFreeBinding` /
//!   `error.NoFreeLayerInfoRows` / `error.NoFreeImageLayers` if capacity
//!   is exceeded — the caller handles by releasing retired bindings or
//!   calling `resize`.
//! - `release(binding)` returns the slot's storage to the free list.
//! - `resize(options)` reshapes the storage. Errors if there are active
//!   bindings.

const std = @import("std");

const atlas_mod = @import("snail");
const draw_records = @import("snail").render.records;
const page_mod = @import("snail");
const page_pool_mod = @import("snail");
const upload_plan = @import("snail").atlas_upload;
const resources_mod = @import("resources.zig");
const path_paint_mod = @import("path_paint.zig");
const image_mod = @import("snail");

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const PreparedAtlasPage = resources_mod.PreparedAtlasPage;
pub const PaintImageRecord = atlas_mod.PaintImageRecord;
pub const Image = image_mod.Image;

const CURVE_WORDS_PER_ROW: u32 = upload_plan.CURVE_TEX_WIDTH * 4;
const BAND_WORDS_PER_ROW: u32 = upload_plan.BAND_TEX_WIDTH * 2;
const INFO_WIDTH: u32 = upload_plan.INFO_WIDTH;

/// This device samples `Image`s directly (no fixed-size array layers), so
/// image-paint records carry uv scale 1.0 — unlike the GPU patch, which
/// normalizes into a `max_image_*`-sized array layer. Applied after the
/// planner's regions, overriding the planner-patched uv texels.
fn patchImagePaintRecord(data: []f32, row_base: u32, texel_offset: u32, layer: u32) void {
    const texel_x = texel_offset % INFO_WIDTH;
    const texel_y = row_base + texel_offset / INFO_WIDTH;
    const record_base = (texel_y * INFO_WIDTH + texel_x) * 4;
    data[record_base + 2 * 4 + 3] = @floatFromInt(layer);
    data[record_base + 5 * 4 + 0] = 1.0;
    data[record_base + 5 * 4 + 1] = 1.0;
}

pub const DeviceAtlasOptions = struct {
    max_bindings: u32 = 16,
    layer_info_height: u32 = 64,
    max_images: u32 = 16,
};
pub const UploadError = upload_plan.Error || std.mem.Allocator.Error;
pub const ResizeError = error{ActiveBindingsPreventResize} || std.mem.Allocator.Error;

pub const DeviceAtlas = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: DeviceAtlasOptions,

    /// Shared placement/planning state (slots, free ranges, deltas).
    planner: upload_plan.OwnedPlanner,

    // Per-layer prepared atlas pages (one per pool layer, indexed by
    // AtlasPage.layer_index).
    prepared: []?PreparedAtlasPage,
    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,

    // Persistent layer-info buffer — the CPU analog of the layer-info
    // texture. Fixed-size at init; row ranges are the planner's.
    layer_info_buf: []f32,
    layer_info_width: u32,
    layer_info_capacity_rows: u32,

    // Persistent image storage (image pointers; caller owns lifetimes),
    // indexed by the planner's absolute image layer.
    image_storage: []?*const Image,
    image_capacity: u32,

    /// Device-side per-binding state, parallel to the planner's slots.
    extras: []BindingExtras,
    active_bindings: u32 = 0,

    pub const BindingExtras = struct {
        // Prepared records (offsets ABSOLUTE within layer_info_buf).
        path_records: []path_paint_mod.PreparedPathRecord = &.{},
        path_layers: []path_paint_mod.PreparedPathLayer = &.{},
        // Image records owned per-binding (small slice; caller-owned
        // image pointers).
        paint_image_records: ?[]?PaintImageRecord = null,
    };

    fn plannerOptions(pool: *const PagePool, options: DeviceAtlasOptions) upload_plan.Options {
        _ = pool;
        return .{
            .max_bindings = options.max_bindings,
            .layer_info_height = options.layer_info_height,
            .max_images = options.max_images,
            // The CPU device samples images directly; the planner's uv
            // normalization is overridden by `patchImagePaintRecord`, so
            // the array extent is a placeholder.
            .max_image_width = 1,
            .max_image_height = 1,
        };
    }

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, options: DeviceAtlasOptions) !DeviceAtlas {
        const max_layers = pool.options.max_layers;

        var planner = try upload_plan.OwnedPlanner.init(allocator, pool, plannerOptions(pool, options));
        errdefer planner.deinit();

        const prepared = try allocator.alloc(?PreparedAtlasPage, max_layers);
        errdefer allocator.free(prepared);
        const gen = try allocator.alloc(u16, max_layers);
        errdefer allocator.free(gen);
        const curve_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(band_words);
        @memset(prepared, null);
        @memset(gen, 0);
        @memset(curve_words, 0);
        @memset(band_words, 0);

        const info_floats = @as(usize, INFO_WIDTH) * @as(usize, options.layer_info_height) * 4;
        const layer_info_buf = try allocator.alloc(f32, info_floats);
        errdefer allocator.free(layer_info_buf);
        @memset(layer_info_buf, 0);

        const image_storage = try allocator.alloc(?*const Image, options.max_images);
        errdefer allocator.free(image_storage);
        @memset(image_storage, null);

        const extras = try allocator.alloc(BindingExtras, options.max_bindings);
        errdefer allocator.free(extras);
        for (extras) |*e| e.* = .{};

        return .{
            .allocator = allocator,
            .pool = pool,
            .options = options,
            .planner = planner,
            .prepared = prepared,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
            .layer_info_buf = layer_info_buf,
            .layer_info_width = INFO_WIDTH,
            .layer_info_capacity_rows = options.layer_info_height,
            .image_storage = image_storage,
            .image_capacity = options.max_images,
            .extras = extras,
        };
    }

    pub fn deinit(self: *DeviceAtlas) void {
        for (self.prepared) |*slot| {
            if (slot.*) |*p| p.deinit(self.allocator);
        }
        self.allocator.free(self.prepared);
        self.allocator.free(self.prepared_generation);
        self.allocator.free(self.prepared_curve_words);
        self.allocator.free(self.prepared_band_words);
        self.allocator.free(self.layer_info_buf);
        self.allocator.free(self.image_storage);
        for (self.extras) |*e| self.freeExtras(e);
        self.allocator.free(self.extras);
        self.planner.deinit();
        self.* = undefined;
    }

    fn freeExtras(self: *DeviceAtlas, extras: *BindingExtras) void {
        if (extras.path_records.len > 0) self.allocator.free(extras.path_records);
        if (extras.path_layers.len > 0) self.allocator.free(extras.path_layers);
        if (extras.paint_image_records) |r| self.allocator.free(r);
        extras.* = .{};
    }

    /// Reshape the cache. Errors if any binding is active — caller must
    /// release retired bindings first.
    pub fn resize(self: *DeviceAtlas, options: DeviceAtlasOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;

        var new_planner = try upload_plan.OwnedPlanner.init(self.allocator, self.pool, plannerOptions(self.pool, options));
        errdefer new_planner.deinit();

        // Reallocate layer_info_buf.
        const info_floats = @as(usize, INFO_WIDTH) * @as(usize, options.layer_info_height) * 4;
        const new_buf = try self.allocator.realloc(self.layer_info_buf, info_floats);
        @memset(new_buf, 0);
        self.layer_info_buf = new_buf;
        self.layer_info_capacity_rows = options.layer_info_height;

        // Reallocate image storage.
        const new_images = try self.allocator.realloc(self.image_storage, options.max_images);
        @memset(new_images, null);
        self.image_storage = new_images;
        self.image_capacity = options.max_images;

        // Reallocate per-binding extras.
        const new_extras = try self.allocator.realloc(self.extras, options.max_bindings);
        for (new_extras) |*e| e.* = .{};
        self.extras = new_extras;

        self.planner.deinit();
        self.planner = new_planner;
        self.options = options;
    }

    /// Upload one or more atlases into the cache and return one
    /// `Binding` per atlas. Errors if capacity is exceeded; partially
    /// planned bindings are released on failure.
    ///
    /// `scratch` is unused by this device — the signature is uniform
    /// across the device-cache family (GPU caches stage through it), so
    /// generic drivers can swap backends without reshaping call sites.
    pub fn upload(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
        out_bindings: []Binding,
    ) UploadError!void {
        _ = scratch;
        std.debug.assert(atlases.len == out_bindings.len);

        var planned: usize = 0;
        errdefer for (out_bindings[0..planned]) |b| {
            self.releaseDeviceState(b);
            _ = self.planner.release(b);
        };

        for (atlases, 0..) |atlas, i| {
            const plan = try self.planner.plan(atlas);
            out_bindings[i] = plan.binding;
            planned = i + 1;
            try self.applyPlan(atlas, plan);
        }
        self.active_bindings += @intCast(atlases.len);
    }

    /// Incrementally update `prev_binding`'s slot with `atlas`'s
    /// current state. See `GlDeviceAtlas.uploadDelta` for the
    /// contract; the planner's per-page watermarks keep unchanged
    /// pages free of copy traffic.
    pub fn uploadDelta(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        _ = scratch;
        const plan = try self.planner.planDelta(prev_binding, atlas);
        try self.applyPlan(atlas, plan);
        return plan.binding;
    }

    /// Release a binding's storage. Idempotent: releasing the same
    /// binding twice is a no-op after the first.
    pub fn release(self: *DeviceAtlas, binding: Binding) void {
        self.releaseDeviceState(binding);
        if (self.planner.release(binding)) self.active_bindings -= 1;
    }

    /// Slice into the cache's persistent storage describing one live
    /// binding. `layer_info_data` is the slot's window into the shared
    /// buffer (row 0 of the slice is the slot's first row); `info_row_base`
    /// is where this slot sits in the global info_y space and is the value
    /// emit added to `Instance.info_y`. Path records' `texel_offset` is
    /// already slot-relative (matches `layer_info_data`).
    pub fn snapshotFor(self: *const DeviceAtlas, generation: u32) ?Snapshot {
        const slot_index = self.findSlotByGeneration(generation) orelse return null;
        const slot = &self.planner.bindings[slot_index];
        const extras = &self.extras[slot_index];
        const dst_start: usize = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
        const dst_floats: usize = @as(usize, slot.info_height) * INFO_WIDTH * 4;
        return .{
            .layer_info_data = self.layer_info_buf[dst_start..][0..dst_floats],
            .layer_info_width = self.layer_info_width,
            .info_row_base = slot.info_row_base,
            .info_height = slot.info_height,
            .path_records = extras.path_records,
            .path_layers = extras.path_layers,
            .paint_image_records = extras.paint_image_records,
        };
    }

    pub const Snapshot = struct {
        layer_info_data: []const f32,
        layer_info_width: u32,
        info_row_base: u32,
        info_height: u32,
        path_records: []path_paint_mod.PreparedPathRecord,
        path_layers: []path_paint_mod.PreparedPathLayer,
        paint_image_records: ?[]const ?PaintImageRecord,
    };

    /// Highest binding generation this cache has issued — used by `draw`
    /// to reject bindings from a different/newer cache.
    pub fn uploadGeneration(self: *const DeviceAtlas) u32 {
        return self.planner.planner.upload_generation;
    }

    pub fn page(self: *const DeviceAtlas, layer: u32) ?*const PreparedAtlasPage {
        if (layer >= self.prepared.len) return null;
        if (self.prepared[layer]) |*p| return p;
        return null;
    }

    // ── Internal ──

    fn findSlotByGeneration(self: *const DeviceAtlas, generation: u32) ?usize {
        for (self.planner.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return i;
        }
        return null;
    }

    fn releaseDeviceState(self: *DeviceAtlas, binding: Binding) void {
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return;
        const slot = &self.planner.bindings[slot_index];
        for (slot.image_layer_base..slot.image_layer_base + slot.image_count) |layer| {
            self.image_storage[layer] = null;
        }
        self.freeExtras(&self.extras[slot_index]);
    }

    /// Apply a planned upload to the CPU device: refresh prepared pages,
    /// copy layer-info regions, resolve image pointers, re-patch image
    /// records to this device's uv convention, and rebuild the prepared
    /// path records.
    fn applyPlan(self: *DeviceAtlas, atlas: *const Atlas, plan: upload_plan.PlannedUpload) UploadError!void {
        const slot_index = self.findSlotByGeneration(plan.binding.generation) orelse return error.UnknownBinding;
        const slot = &self.planner.bindings[slot_index];
        const extras = &self.extras[slot_index];

        // Refresh the prepared per-layer page copies (curve/band regions
        // are not applied — this device reads packed page data through
        // `PreparedAtlasPage`, rebuilt on staleness).
        for (atlas.pages) |p| {
            const layer = p.layer_index;
            if (layer >= self.prepared.len) return error.PageNotInPool;
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const stale = (self.prepared[layer] == null) or
                self.prepared_generation[layer] != cur_gen or
                self.prepared_curve_words[layer] != cur_curve or
                self.prepared_band_words[layer] != cur_band;
            if (!stale) continue;
            if (self.prepared[layer]) |*existing| existing.deinit(self.allocator);
            self.prepared[layer] = null;

            const view = PageView.fromPage(p);
            self.prepared[layer] = try PreparedAtlasPage.initFromView(self.allocator, view);
            self.prepared_generation[layer] = cur_gen;
            self.prepared_curve_words[layer] = cur_curve;
            self.prepared_band_words[layer] = cur_band;
        }

        // Apply the planner's regions to the device storage.
        for (plan.regions) |region| switch (region.target) {
            .curve, .band => {},
            .layer_info => {
                const src = std.mem.bytesAsSlice(f32, @as([]align(4) const u8, @alignCast(region.src)));
                var row: u32 = 0;
                while (row < region.height) : (row += 1) {
                    const dst_base = ((@as(usize, region.row_base) + row) * INFO_WIDTH + region.col_base) * 4;
                    const src_base = @as(usize, row) * region.width * 4;
                    @memcpy(
                        self.layer_info_buf[dst_base..][0 .. @as(usize, region.width) * 4],
                        src[src_base..][0 .. @as(usize, region.width) * 4],
                    );
                }
            },
            .image => {
                // Resolve the region's source back to its `Image` (the
                // planner emits `src = image.texels`) and store the
                // pointer at the assigned layer.
                if (atlas.paint_image_records) |records| {
                    for (records) |maybe_rec| {
                        const rec = maybe_rec orelse continue;
                        if (rec.image.texels.ptr == region.src.ptr) {
                            self.image_storage[region.layer] = rec.image;
                            break;
                        }
                    }
                }
            },
        };

        if (atlas.layer_info_data != null) {
            // Re-patch image-paint records for this device (direct image
            // sampling: uv scale 1.0; layer = planner's absolute layer).
            if (atlas.paint_image_records) |records| {
                for (records) |maybe_rec| {
                    const rec = maybe_rec orelse continue;
                    const abs_layer = slot.image_layer_base + upload_plan.imageLayerFor(records, rec.image);
                    patchImagePaintRecord(self.layer_info_buf, slot.info_row_base, rec.texel_offset, abs_layer);
                }
            }

            // Rebuild the per-binding prepared records (freeing any prior
            // generation's — deltas rebuild in place).
            self.freeExtras(extras);
            if (atlas.paint_image_records) |records| {
                const owned = try self.allocator.alloc(?PaintImageRecord, records.len);
                @memcpy(owned, records);
                extras.paint_image_records = owned;
            }
            const dst_start: usize = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
            const dst_floats: usize = @as(usize, slot.info_height) * INFO_WIDTH * 4;
            const slot_data = self.layer_info_buf[dst_start..][0..dst_floats];
            const prepared_records = try path_paint_mod.preparePathLayerInfoRecords(
                self.allocator,
                slot_data,
                INFO_WIDTH,
                slot.info_height,
                extras.paint_image_records,
            );
            extras.path_records = prepared_records.records;
            extras.path_layers = prepared_records.layers;
        }
    }
};

const PageView = struct {
    curve_data: []const u16,
    band_data: []const u16,
    curve_width: u32,
    curve_height: u32,
    band_width: u32,
    band_height: u32,

    fn fromPage(p: *const AtlasPage) PageView {
        const curve_words = p.curve.data.len;
        const band_words = p.band.data.len;
        std.debug.assert(curve_words % CURVE_WORDS_PER_ROW == 0);
        std.debug.assert(band_words % BAND_WORDS_PER_ROW == 0);
        return .{
            .curve_data = p.curve.data,
            .band_data = p.band.data,
            .curve_width = upload_plan.CURVE_TEX_WIDTH,
            .curve_height = @intCast(curve_words / CURVE_WORDS_PER_ROW),
            .band_width = upload_plan.BAND_TEX_WIDTH,
            .band_height = @intCast(band_words / BAND_WORDS_PER_ROW),
        };
    }
};

const testing = std.testing;

test "cache init allocates fixed-capacity buffers" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 2,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{
        .max_bindings = 4,
        .layer_info_height = 8,
        .max_images = 2,
    });
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 4), cache.extras.len);
    try testing.expectEqual(@as(u32, 8), cache.layer_info_capacity_rows);
    try testing.expectEqual(@as(u32, 2), cache.image_capacity);
}

test "release returns range to free list and allows reuse" {
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);
    const gid = try font.glyphIndex('A');
    var curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves.deinit();

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{
        .max_bindings = 4,
        .layer_info_height = 2,
        .max_images = 0,
    });
    defer cache.deinit();

    // Two atlases with one painted entry each — exhausts layer_info rows.
    const key1 = record_key_mod.unhintedGlyph(0, gid);
    var atlas1 = try Atlas.from(testing.allocator, pool, &.{.{
        .key = key1,
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas1.deinit();
    const key2 = record_key_mod.unhintedGlyph(1, gid);
    var atlas2 = try Atlas.from(testing.allocator, pool, &.{.{
        .key = key2,
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas2.deinit();

    var b1: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&atlas1}, &b1);
    try testing.expectEqual(@as(u32, 1), cache.active_bindings);

    var b2: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&atlas2}, &b2);
    try testing.expectEqual(@as(u32, 2), cache.active_bindings);

    // No more rows — third upload errors.
    const key3 = record_key_mod.unhintedGlyph(2, gid);
    var atlas3 = try Atlas.from(testing.allocator, pool, &.{.{
        .key = key3,
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas3.deinit();
    var b3: [1]Binding = undefined;
    try testing.expectError(error.NoFreeLayerInfoRows, cache.upload(testing.allocator, &.{&atlas3}, &b3));

    cache.release(b1[0]);
    try testing.expectEqual(@as(u32, 1), cache.active_bindings);

    // Now the third upload succeeds.
    try cache.upload(testing.allocator, &.{&atlas3}, &b3);
    try testing.expectEqual(@as(u32, 2), cache.active_bindings);
}

test "uploadDelta errors for unknown pool" {
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);
    const gid = try font.glyphIndex('A');
    var curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves.deinit();
    var curves2 = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves2.deinit();

    var pool_a = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool_a.deinit();
    var pool_b = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool_b.deinit();

    const key = record_key_mod.unhintedGlyph(0, gid);
    var atlas_a = try Atlas.from(testing.allocator, pool_a, &.{.{ .key = key, .curves = curves }});
    defer atlas_a.deinit();
    var atlas_b = try Atlas.from(testing.allocator, pool_b, &.{.{ .key = key, .curves = curves2 }});
    defer atlas_b.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool_a, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache.deinit();
    var binding: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&atlas_a}, &binding);

    try testing.expectError(error.UnknownPool, cache.uploadDelta(testing.allocator, binding[0], &atlas_b));
}

test "uploadDelta errors for released binding" {
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);
    const gid = try font.glyphIndex('A');
    var curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves.deinit();

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const key = record_key_mod.unhintedGlyph(0, gid);
    var atlas = try Atlas.from(testing.allocator, pool, &.{.{ .key = key, .curves = curves }});
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache.deinit();
    var binding: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&atlas}, &binding);
    cache.release(binding[0]);

    try testing.expectError(error.UnknownBinding, cache.uploadDelta(testing.allocator, binding[0], &atlas));
}

test "uploadDelta accepts a different atlas on the same pool" {
    // Per the contract docstring on GlDeviceAtlas.uploadDelta: a
    // different atlas on the same pool is permitted — the cache's
    // per-layer page tracking notices the change and re-uploads
    // affected pages. This is correct, just less efficient than a
    // true extension would be. Lock that in so future "tighten the
    // contract" rewrites don't accidentally make it an error.
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);
    const gid_a = try font.glyphIndex('A');
    const gid_b = try font.glyphIndex('B');
    var curves_a = try font.extractCurves(testing.allocator, testing.allocator, gid_a);
    defer curves_a.deinit();
    var curves_b = try font.extractCurves(testing.allocator, testing.allocator, gid_b);
    defer curves_b.deinit();

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const key_a = record_key_mod.unhintedGlyph(0, gid_a);
    var atlas_a = try Atlas.from(testing.allocator, pool, &.{.{ .key = key_a, .curves = curves_a }});
    defer atlas_a.deinit();
    const key_b = record_key_mod.unhintedGlyph(0, gid_b);
    var atlas_b = try Atlas.from(testing.allocator, pool, &.{.{ .key = key_b, .curves = curves_b }});
    defer atlas_b.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache.deinit();
    var binding: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&atlas_a}, &binding);

    const new_binding = try cache.uploadDelta(testing.allocator, binding[0], &atlas_b);
    try testing.expectEqual(binding[0].generation, new_binding.generation);
    try testing.expectEqual(binding[0].info_row_base, new_binding.info_row_base);
}
