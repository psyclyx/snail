//! The software rasterizer's device-side atlas: resident CPU copies of
//! uploaded atlas records for one `PagePool`, with caller-controlled
//! lifecycle primitives:
//!
//! - `init(allocator, pool, options)` allocates fixed-capacity storage
//!   for `max_bindings`, `layer_info_height` rows of paint records, and
//!   `max_images` image references. The caller decides how much is
//!   enough; a `DeviceAtlas` never auto-grows.
//! - `upload(scratch, atlases)` finds a free slot in the persistent
//!   storage, writes each atlas's curve/band into the pool's prepared
//!   pages, and lays each atlas's layer-info into the shared buffer.
//!   Returns one `Binding` per atlas. Errors with
//!   `error.NoFreeBinding` / `error.NoFreeLayerInfoRows` /
//!   `error.NoFreeImageLayers` if capacity is exceeded — the caller
//!   handles by releasing retired bindings or calling `resize`.
//! - `release(binding)` returns the slot's storage to the free list.
//!   The next upload can reuse the same row_base / image_layer_base
//!   range.
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
const range_allocator = @import("range_allocator.zig");

const RangeAllocator = range_allocator.RangeAllocator;
const Range = range_allocator.Range;

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
pub const UploadError = error{
    NoFreeBinding,
    NoFreeLayerInfoRows,
    NoFreeImageLayers,
    NoLayerInfoRoomToGrow,
    UnknownPool,
    UnknownBinding,
    PageNotInPool,
} || std.mem.Allocator.Error;
pub const ResizeError = error{ActiveBindingsPreventResize} || std.mem.Allocator.Error;

pub const DeviceAtlas = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: DeviceAtlasOptions,

    // Per-layer prepared atlas pages (one per pool layer, indexed by
    // AtlasPage.layer_index).
    prepared: []?PreparedAtlasPage,
    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,

    // Persistent layer-info buffer. Fixed-size at init. Slot ranges
    // come and go via layer_info_ranges.
    layer_info_buf: []f32,
    layer_info_width: u32,
    layer_info_capacity_rows: u32,
    layer_info_ranges: RangeAllocator,

    // Persistent image storage (image pointers; caller owns lifetimes).
    image_storage: []?*const Image,
    image_capacity: u32,
    image_ranges: RangeAllocator,

    // Per-binding slots.
    bindings: []BindingSlot,
    active_bindings: u32 = 0,

    upload_generation: u32 = 0,

    pub const BindingSlot = struct {
        active: bool = false,
        generation: u32 = 0,
        info_row_base: u32 = 0,
        info_height: u32 = 0,
        image_layer_base: u32 = 0,
        image_count: u32 = 0,
        // Prepared records (offsets ABSOLUTE within layer_info_buf).
        path_records: []path_paint_mod.PreparedPathRecord = &.{},
        path_layers: []path_paint_mod.PreparedPathLayer = &.{},
        // Image records owned per-binding (small slice; caller-owned
        // image pointers).
        paint_image_records: ?[]?PaintImageRecord = null,
    };

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, options: DeviceAtlasOptions) !DeviceAtlas {
        const max_layers = pool.options.max_layers;

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

        const bindings = try allocator.alloc(BindingSlot, options.max_bindings);
        errdefer allocator.free(bindings);
        for (bindings) |*b| b.* = .{};

        var layer_info_ranges = try RangeAllocator.init(allocator, options.layer_info_height);
        errdefer layer_info_ranges.deinit(allocator);

        var image_ranges = try RangeAllocator.init(allocator, options.max_images);
        errdefer image_ranges.deinit(allocator);

        return .{
            .allocator = allocator,
            .pool = pool,
            .options = options,
            .prepared = prepared,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
            .layer_info_buf = layer_info_buf,
            .layer_info_width = INFO_WIDTH,
            .layer_info_capacity_rows = options.layer_info_height,
            .layer_info_ranges = layer_info_ranges,
            .image_storage = image_storage,
            .image_capacity = options.max_images,
            .image_ranges = image_ranges,
            .bindings = bindings,
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
        for (self.bindings) |*slot| self.freeBindingState(slot);
        self.allocator.free(self.bindings);
        self.layer_info_ranges.deinit(self.allocator);
        self.image_ranges.deinit(self.allocator);
        self.* = undefined;
    }

    fn freeBindingState(self: *DeviceAtlas, slot: *BindingSlot) void {
        if (slot.path_records.len > 0) self.allocator.free(slot.path_records);
        if (slot.path_layers.len > 0) self.allocator.free(slot.path_layers);
        if (slot.paint_image_records) |r| self.allocator.free(r);
        slot.path_records = &.{};
        slot.path_layers = &.{};
        slot.paint_image_records = null;
    }

    /// Reshape the cache. Errors if any binding is active — caller must
    /// release retired bindings first.
    pub fn resize(self: *DeviceAtlas, options: DeviceAtlasOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;
        self.options = options;

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

        // Reallocate bindings.
        const new_bindings = try self.allocator.realloc(self.bindings, options.max_bindings);
        for (new_bindings) |*b| b.* = .{};
        self.bindings = new_bindings;

        // Reset free lists.
        try self.layer_info_ranges.reset(self.allocator, options.layer_info_height);
        try self.image_ranges.reset(self.allocator, options.max_images);
    }

    /// Upload one or more atlases into the cache and return one
    /// `Binding` per atlas. Errors if capacity is exceeded.
    pub fn upload(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
        out_bindings: []Binding,
    ) UploadError!void {
        std.debug.assert(atlases.len == out_bindings.len);

        // First pass: validate pool ownership and tally capacity.
        for (atlases) |atlas| {
            if (atlas.pool) |p| {
                if (p != self.pool) return error.UnknownPool;
            }
        }

        var allocated_layer_ranges = std.ArrayList(Range).empty;
        defer allocated_layer_ranges.deinit(scratch);
        var allocated_image_ranges = std.ArrayList(Range).empty;
        defer allocated_image_ranges.deinit(scratch);
        var allocated_slot_indices = std.ArrayList(u32).empty;
        defer allocated_slot_indices.deinit(scratch);

        var success = false;
        defer if (!success) {
            // Roll back any allocations we made before the failure.
            for (allocated_layer_ranges.items) |r| self.layer_info_ranges.release(self.allocator, r) catch {};
            for (allocated_image_ranges.items) |r| self.image_ranges.release(self.allocator, r) catch {};
            for (allocated_slot_indices.items) |i| self.bindings[i] = .{};
        };

        for (atlases, 0..) |atlas, i| {
            const info_height = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
            const image_count = countUniqueImages(atlas);

            // Reserve a slot.
            const slot_index = self.findFreeBinding() orelse return error.NoFreeBinding;
            try allocated_slot_indices.append(scratch, slot_index);

            // Reserve layer-info rows.
            const info_range: Range = if (info_height == 0)
                .{ .base = 0, .size = 0 }
            else
                self.layer_info_ranges.take(info_height) orelse return error.NoFreeLayerInfoRows;
            try allocated_layer_ranges.append(scratch, info_range);

            // Reserve image layers.
            const image_range: Range = if (image_count == 0)
                .{ .base = 0, .size = 0 }
            else
                self.image_ranges.take(image_count) orelse return error.NoFreeImageLayers;
            try allocated_image_ranges.append(scratch, image_range);

            // Mark slot active (rolled back on failure).
            self.upload_generation += 1;
            const slot = &self.bindings[slot_index];
            slot.* = .{
                .active = true,
                .generation = self.upload_generation,
                .info_row_base = info_range.base,
                .info_height = info_range.size,
                .image_layer_base = image_range.base,
                .image_count = image_range.size,
            };

            try self.writeBindingData(atlas, slot);

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
    /// current state. See `GlDeviceAtlas.uploadDelta` for the
    /// contract; the CPU implementation re-runs `writeBindingData`
    /// which natively walks per-page watermarks under the hood, so
    /// pages whose contents haven't grown emit no copy traffic.
    pub fn uploadDelta(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        _ = scratch;
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

        try self.writeBindingData(atlas, slot);

        return .{
            .pool = self.pool,
            .generation = slot.generation,
            .info_row_base = slot.info_row_base,
            .image_layer_base = slot.image_layer_base,
        };
    }

    /// Release a binding's storage. Idempotent: releasing the same
    /// binding twice is a no-op after the first.
    pub fn release(self: *DeviceAtlas, binding: Binding) void {
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return;

        if (slot.info_height > 0) {
            self.layer_info_ranges.release(self.allocator, .{ .base = slot.info_row_base, .size = slot.info_height }) catch {};
        }
        if (slot.image_count > 0) {
            for (slot.image_layer_base..slot.image_layer_base + slot.image_count) |layer| {
                self.image_storage[layer] = null;
            }
            self.image_ranges.release(self.allocator, .{ .base = slot.image_layer_base, .size = slot.image_count }) catch {};
        }
        self.freeBindingState(slot);
        slot.* = .{};
        self.active_bindings -= 1;
    }

    /// Slice into the cache's persistent storage describing one live
    /// binding. `layer_info_data` is the slot's window into the shared
    /// buffer (row 0 of the slice is the slot's first row); `info_row_base`
    /// is where this slot sits in the global info_y space and is the value
    /// emit added to `Instance.info_y`. Path records' `texel_offset` is
    /// already slot-relative (matches `layer_info_data`).
    pub fn snapshotFor(self: *const DeviceAtlas, generation: u32) ?Snapshot {
        const slot_index = self.findSlotByGeneration(generation) orelse return null;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return null;
        const dst_start: usize = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
        const dst_floats: usize = @as(usize, slot.info_height) * INFO_WIDTH * 4;
        return .{
            .layer_info_data = self.layer_info_buf[dst_start..][0..dst_floats],
            .layer_info_width = self.layer_info_width,
            .info_row_base = slot.info_row_base,
            .info_height = slot.info_height,
            .path_records = slot.path_records,
            .path_layers = slot.path_layers,
            .paint_image_records = slot.paint_image_records,
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

    pub fn page(self: *const DeviceAtlas, layer: u32) ?*const PreparedAtlasPage {
        if (layer >= self.prepared.len) return null;
        if (self.prepared[layer]) |*p| return p;
        return null;
    }

    // ── Internal ──

    fn findFreeBinding(self: *DeviceAtlas) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (!slot.active) return @intCast(i);
        }
        return null;
    }

    fn findSlotByGeneration(self: *const DeviceAtlas, generation: u32) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return @intCast(i);
        }
        return null;
    }

    fn writeBindingData(self: *DeviceAtlas, atlas: *const Atlas, slot: *BindingSlot) UploadError!void {
        // Push each page in the atlas into its layer (rebuild if stale).
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

        // Write atlas's layer_info_data into the persistent buffer at
        // the slot's row_base. Patch image paint records with absolute
        // image layer indices.
        if (atlas.layer_info_data) |src_data| {
            const dst_floats = src_data.len;
            const dst_start: usize = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
            std.debug.assert(dst_start + dst_floats <= self.layer_info_buf.len);
            @memcpy(self.layer_info_buf[dst_start..][0..dst_floats], src_data);

            // Patch image-paint records with the absolute image layer.
            const image_layer_base = slot.image_layer_base;
            if (atlas.paint_image_records) |records| {
                var local_layer: u32 = 0;
                var seen = std.AutoHashMap(*const Image, u32).init(self.allocator);
                defer seen.deinit();
                for (records) |maybe_rec| {
                    const rec = maybe_rec orelse continue;
                    const gop = try seen.getOrPut(rec.image);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = local_layer;
                        self.image_storage[image_layer_base + local_layer] = rec.image;
                        local_layer += 1;
                    }
                    // Absolute layer in cache's image storage.
                    const abs_layer = image_layer_base + gop.value_ptr.*;
                    patchImagePaintRecord(self.layer_info_buf, slot.info_row_base, rec.texel_offset, abs_layer);
                }
            }

            // Copy image records to a per-binding slice (non-owning of
            // the images themselves). Do this BEFORE preparing path
            // layers — the prepared layers cache image-record pointers
            // by texel match (see `findImageRecordByTexel`).
            if (atlas.paint_image_records) |records| {
                const owned = try self.allocator.alloc(?PaintImageRecord, records.len);
                @memcpy(owned, records);
                slot.paint_image_records = owned;
            }

            // Build prepared path records pointing into the persistent
            // buffer (offsets stored as if the slot's region were
            // a standalone buffer; the rasterizer pairs each
            // LayerInfoEntry with its row_base to translate absolute
            // info_y back to local coords).
            const slot_data = self.layer_info_buf[dst_start..][0..dst_floats];
            const prepared_records = try path_paint_mod.preparePathLayerInfoRecords(
                self.allocator,
                slot_data,
                INFO_WIDTH,
                slot.info_height,
                slot.paint_image_records,
            );
            slot.path_records = prepared_records.records;
            slot.path_layers = prepared_records.layers;
        }
    }

    fn countUniqueImages(atlas: *const Atlas) u32 {
        const records = atlas.paint_image_records orelse return 0;
        var seen_count: u32 = 0;
        // Simple O(n^2) dedup against earlier entries — atlases have a
        // handful of image records at most.
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

    try testing.expectEqual(@as(usize, 4), cache.bindings.len);
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
