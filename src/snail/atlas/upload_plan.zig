//! Font-atlas GPU upload planning — pure, caller-owned state, no allocator.
//!
//! Turns an `Atlas` into the set of texel `Region`s the caller must copy into
//! its own GPU textures, plus the `Binding` that `emit` consumes. This is the
//! font-specific atlas→layer mapping (a caller can't know it); everything about
//! GPU textures, uploads, and the queue is the caller's.
//!
//! No allocator: the caller owns every state buffer (sized via `sizes`) and the
//! output `Region` buffer, exactly like `emit` takes caller-provided words. The
//! layer/row assignment matches the (removed) backend cache byte-for-byte, so
//! the `Binding`s — and therefore the emit stream — are identical.

const std = @import("std");

const atlas_mod = @import("../atlas.zig");
const page_mod = @import("page.zig");
const page_pool_mod = @import("page_pool.zig");
const draw_records = @import("../draw/records.zig");
const paint_records = @import("paint_records.zig");
const upload_common = @import("../format/upload_common.zig");

pub const Atlas = atlas_mod.Atlas;
pub const Binding = draw_records.Binding;
pub const PagePool = page_pool_mod.PagePool;

pub const CURVE_TEX_WIDTH: u32 = page_mod.CURVE_TEX_WIDTH;
pub const BAND_TEX_WIDTH: u32 = page_mod.BAND_TEX_WIDTH;
pub const INFO_WIDTH: u32 = paint_records.info_width;

pub const Target = enum { curve, band, layer_info, image };

/// One texel copy the caller must apply to its own texture. `src` are the
/// source bytes (curve/band: the full page buffer; layer_info: the f32 slab as
/// bytes; image: RGBA8 pixels). `layer` is the destination array layer
/// (curve/band/image); `row_base` is the destination row (layer_info only).
pub const Region = struct {
    target: Target,
    layer: u32 = 0,
    row_base: u32 = 0,
    src: []const u8,
    width: u32,
    height: u32,
};

pub const Options = struct {
    max_bindings: u32,
    layer_info_height: u32,
    max_images: u32,
    max_image_width: u32,
    max_image_height: u32,
};

pub const Error = error{
    UnknownPool,
    PageNotInPool,
    NoFreeBinding,
    NoFreeLayerInfoRows,
    NoFreeImageLayers,
    NoLayerInfoRoomToGrow,
    NoImageRoomToGrow,
    UnknownBinding,
    RegionBufferFull,
    LayerInfoScratchTooSmall,
    FreeListFull,
};

pub const InitError = error{
    BackingTooSmall,
    InvalidOptions,
};

/// Byte counts the caller must provide for each state buffer.
pub const Sizes = struct {
    generation: usize,
    curve_words: usize,
    band_words: usize,
    bindings: usize,
    info_free: usize,
    image_free: usize,
    /// A safe upper bound on regions produced by one `plan`/`planDelta`.
    regions: usize,
    /// f32 scratch a caller must provide per `plan`/`planDelta` call for the
    /// patched layer_info copy (image paints resolve their array-layer + uv into
    /// it). One atlas' worth; provide a distinct slice per in-flight atlas.
    layer_info_scratch: usize,
};

pub fn sizes(pool: *const PagePool, opts: Options) Sizes {
    return .{
        .generation = pool.options.max_layers,
        .curve_words = pool.options.max_layers,
        .band_words = pool.options.max_layers,
        .bindings = opts.max_bindings,
        // First-fit free-list fragments to at most one span per binding, +1.
        .info_free = opts.max_bindings + 1,
        .image_free = opts.max_bindings + 1,
        .regions = @as(usize, pool.options.max_layers) * 2 + 1 + opts.max_images,
        // layer_info is RGBA32F — 4 f32 per INFO_WIDTH texel. `layer_info_data`
        // is `INFO_WIDTH * height * 4` floats, and `plan` memcpys the whole slab
        // into this scratch, so it must be 4× the texel count (not ×1).
        .layer_info_scratch = @as(usize, INFO_WIDTH) * opts.layer_info_height * 4,
    };
}

/// Free-list element; exposed so a caller can allocate the `info_free` /
/// `image_free` backing (sized via `sizes`).
pub const Range = struct { base: u32, size: u32 };

/// Fixed-capacity first-fit free-list over caller-provided backing — the
/// allocator-free twin of `render/range_allocator.zig` (identical
/// take/release semantics so bases match).
const FreeList = struct {
    ranges: []Range,
    len: usize = 0,

    fn reset(self: *FreeList, capacity: u32) void {
        self.len = 0;
        if (capacity > 0) {
            self.ranges[0] = .{ .base = 0, .size = capacity };
            self.len = 1;
        }
    }

    fn take(self: *FreeList, size: u32) ?Range {
        if (size == 0) return .{ .base = 0, .size = 0 };
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            const r = self.ranges[i];
            if (r.size < size) continue;
            if (r.size == size) {
                // orderedRemove(i)
                var j = i;
                while (j + 1 < self.len) : (j += 1) self.ranges[j] = self.ranges[j + 1];
                self.len -= 1;
            } else {
                self.ranges[i] = .{ .base = r.base + size, .size = r.size - size };
            }
            return .{ .base = r.base, .size = size };
        }
        return null;
    }

    fn release(self: *FreeList, range: Range) Error!void {
        if (range.size == 0) return;
        if (self.len >= self.ranges.len) return error.FreeListFull;
        self.ranges[self.len] = range;
        self.len += 1;
        std.mem.sort(Range, self.ranges[0..self.len], {}, struct {
            fn lessThan(_: void, a: Range, b: Range) bool {
                return a.base < b.base;
            }
        }.lessThan);
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.len) {
            var cur = self.ranges[read];
            read += 1;
            while (read < self.len) {
                const nxt = self.ranges[read];
                if (cur.base + cur.size == nxt.base) {
                    cur.size += nxt.size;
                    read += 1;
                } else break;
            }
            self.ranges[write] = cur;
            write += 1;
        }
        self.len = write;
    }
};

/// Per-binding slot; exposed so a caller can allocate the `bindings` backing
/// (sized via `sizes`). Fields are managed by `Planner`.
pub const Slot = struct {
    active: bool = false,
    generation: u32 = 0,
    info_row_base: u32 = 0,
    info_height: u32 = 0,
    image_layer_base: u32 = 0,
    image_count: u32 = 0,
};

/// Caller-owned planning state. Backing slices are the caller's; `Planner` never
/// allocates. Build the slices sized to `sizes(pool, opts)` and pass them to
/// `init`.
pub const Planner = struct {
    pool: *PagePool,
    opts: Options,
    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,
    bindings: []Slot,
    info_free: FreeList,
    image_free: FreeList,
    upload_generation: u32 = 0,

    pub fn init(
        pool: *PagePool,
        opts: Options,
        generation: []u16,
        curve_words: []u32,
        band_words: []u32,
        binding_slots: []Slot,
        info_free_backing: []Range,
        image_free_backing: []Range,
    ) InitError!Planner {
        const layers = pool.options.max_layers;
        if (generation.len < layers or
            curve_words.len < layers or
            band_words.len < layers or
            binding_slots.len < opts.max_bindings or
            info_free_backing.len < @as(usize, opts.max_bindings) + 1 or
            image_free_backing.len < @as(usize, opts.max_bindings) + 1)
        {
            return error.BackingTooSmall;
        }
        if (pool.options.curve_words_per_page % (CURVE_TEX_WIDTH * 4) != 0 or
            pool.options.band_words_per_page % (BAND_TEX_WIDTH * 2) != 0 or
            (opts.max_images > 0 and (opts.max_image_width == 0 or opts.max_image_height == 0)))
        {
            return error.InvalidOptions;
        }
        @memset(generation, 0);
        @memset(curve_words, 0);
        @memset(band_words, 0);
        for (binding_slots) |*b| b.* = .{};
        var self = Planner{
            .pool = pool,
            .opts = opts,
            .prepared_generation = generation,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
            .bindings = binding_slots,
            .info_free = .{ .ranges = info_free_backing },
            .image_free = .{ .ranges = image_free_backing },
        };
        self.info_free.reset(opts.layer_info_height);
        self.image_free.reset(opts.max_images);
        return self;
    }

    /// Plan the upload for a fresh binding of `atlas`. Fills
    /// `out_regions` (up to `sizes().regions`), sets `out_len`, and returns the
    /// `Binding` for `emit`.
    pub fn plan(self: *Planner, atlas: *const Atlas, out_regions: []Region, out_len: *usize, layer_info_scratch: []f32) Error!Binding {
        out_len.* = 0;
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        const info_height: u32 = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
        const image_count = countUniqueImages(atlas);

        const slot_index = self.findFreeBinding() orelse return error.NoFreeBinding;
        const info_range = self.info_free.take(info_height) orelse return error.NoFreeLayerInfoRows;
        errdefer self.info_free.release(info_range) catch {};
        const image_range = self.image_free.take(image_count) orelse return error.NoFreeImageLayers;
        errdefer self.image_free.release(image_range) catch {};

        self.upload_generation += 1;
        const slot = &self.bindings[slot_index];
        errdefer slot.* = .{};
        slot.* = .{
            .active = true,
            .generation = self.upload_generation,
            .info_row_base = info_range.base,
            .info_height = info_range.size,
            .image_layer_base = image_range.base,
            .image_count = image_range.size,
        };

        try self.queue(atlas, slot, out_regions, out_len, layer_info_scratch);
        return .{ .pool = self.pool, .generation = slot.generation, .info_row_base = slot.info_row_base, .image_layer_base = slot.image_layer_base };
    }

    /// Plan an incremental re-upload of `atlas` into the slot `prev_binding`
    /// already owns (only changed curve/band/layer-info/image regions).
    pub fn planDelta(self: *Planner, prev_binding: Binding, atlas: *const Atlas, out_regions: []Region, out_len: *usize, layer_info_scratch: []f32) Error!Binding {
        out_len.* = 0;
        if (prev_binding.pool != self.pool) return error.UnknownPool;
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        const slot_index = self.findSlotByGeneration(prev_binding.generation) orelse return error.UnknownBinding;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return error.UnknownBinding;
        const info_height: u32 = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
        if (info_height > slot.info_height) return error.NoLayerInfoRoomToGrow;
        if (countUniqueImages(atlas) > slot.image_count) return error.NoImageRoomToGrow;

        try self.queue(atlas, slot, out_regions, out_len, layer_info_scratch);
        return .{ .pool = self.pool, .generation = slot.generation, .info_row_base = slot.info_row_base, .image_layer_base = slot.image_layer_base };
    }

    /// Free the binding's slot + ranges. Returns whether a live slot was freed
    /// (false if the binding was unknown/already released).
    pub fn release(self: *Planner, binding: Binding) bool {
        if (binding.pool != self.pool) return false;
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return false;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return false;
        if (slot.info_height > 0) self.info_free.release(.{ .base = slot.info_row_base, .size = slot.info_height }) catch {};
        if (slot.image_count > 0) self.image_free.release(.{ .base = slot.image_layer_base, .size = slot.image_count }) catch {};
        slot.* = .{};
        return true;
    }

    /// Forget the page upload watermarks after the caller fails to apply a
    /// previously returned region list. Bindings and their placement remain
    /// valid, but the next plan conservatively re-emits every referenced page.
    /// Callers must invoke this when GPU upload/recording fails after `plan` or
    /// `planDelta` succeeds; otherwise a retry could skip bytes that never
    /// reached the GPU.
    pub fn invalidateUploads(self: *Planner) void {
        @memset(self.prepared_generation, 0);
        @memset(self.prepared_curve_words, 0);
        @memset(self.prepared_band_words, 0);
    }

    fn queue(self: *Planner, atlas: *const Atlas, slot: *Slot, out: []Region, out_len: *usize, layer_info_scratch: []f32) Error!void {
        // Validate the entire request before changing any watermark. Once this
        // preflight succeeds, emitting the regions cannot fail halfway through
        // and leave planner state ahead of the returned list.
        var region_count: usize = 0;
        for (atlas.pages) |p| {
            const layer: u32 = p.layer_index;
            if (layer >= self.pool.options.max_layers or self.pool.pages[layer] != p) return error.PageNotInPool;
            const stale = self.prepared_generation[layer] != p.currentGeneration() or
                p.curve.usedWords() != self.prepared_curve_words[layer] or
                p.band.usedWords() != self.prepared_band_words[layer];
            if (stale) region_count += 2;
        }
        if (atlas.paint_image_records) |records| {
            for (records, 0..) |maybe_rec, i| {
                if (maybe_rec != null and firstOccurrence(records, i)) region_count += 1;
            }
        }
        if (atlas.layer_info_data) |info| {
            if (info.len > layer_info_scratch.len) return error.LayerInfoScratchTooSmall;
            if (atlas.layer_info_height > 0) region_count += 1;
        }
        if (region_count > out.len) return error.RegionBufferFull;

        for (atlas.pages) |p| {
            const layer: u32 = p.layer_index;
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const stale = self.prepared_generation[layer] != cur_gen or
                cur_curve != self.prepared_curve_words[layer] or
                cur_band != self.prepared_band_words[layer];
            if (!stale) continue;
            self.prepared_generation[layer] = cur_gen;

            const curve_bytes = p.curve.data.len * @sizeOf(page_mod.Word);
            const band_bytes = p.band.data.len * @sizeOf(page_mod.Word);
            try emitRegion(out, out_len, .{ .target = .curve, .layer = layer, .src = @as([*]const u8, @ptrCast(p.curve.data.ptr))[0..curve_bytes], .width = CURVE_TEX_WIDTH, .height = self.pool.options.curve_words_per_page / (CURVE_TEX_WIDTH * 4) });
            try emitRegion(out, out_len, .{ .target = .band, .layer = layer, .src = @as([*]const u8, @ptrCast(p.band.data.ptr))[0..band_bytes], .width = BAND_TEX_WIDTH, .height = self.pool.options.band_words_per_page / (BAND_TEX_WIDTH * 2) });
            self.prepared_curve_words[layer] = cur_curve;
            self.prepared_band_words[layer] = cur_band;
        }

        // layer_info + image paints. Image paint records reference an image
        // whose array-layer + uv-scale are only known here (the caller's
        // texture packing); patch them into a private copy of the slab so the
        // shared atlas data is untouched.
        const info = atlas.layer_info_data orelse return;
        std.debug.assert(atlas.layer_info_width == INFO_WIDTH);
        const info_dst = layer_info_scratch[0..info.len];
        @memcpy(info_dst, info);

        if (atlas.paint_image_records) |records| {
            for (records, 0..) |maybe_rec, i| {
                const rec = maybe_rec orelse continue;
                const abs_layer = slot.image_layer_base + imageLayer(records, rec.image);
                // Emit the image upload once, at its first occurrence.
                if (firstOccurrence(records, i)) {
                    const img_bytes = @as(usize, rec.image.width) * @as(usize, rec.image.height) * 4;
                    try emitRegion(out, out_len, .{ .target = .image, .layer = abs_layer, .src = rec.image.pixels[0..img_bytes], .width = rec.image.width, .height = rec.image.height });
                }
                const uv_x: f32 = @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(self.opts.max_image_width));
                const uv_y: f32 = @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(self.opts.max_image_height));
                upload_common.patchImagePaintRecord(info_dst, INFO_WIDTH, INFO_WIDTH, 0, rec.texel_offset, .{
                    .layer = abs_layer,
                    .uv_scale = .{ .x = uv_x, .y = uv_y },
                });
            }
        }

        if (atlas.layer_info_height > 0) {
            const info_bytes = info_dst.len * @sizeOf(f32);
            try emitRegion(out, out_len, .{ .target = .layer_info, .row_base = slot.info_row_base, .src = @as([*]const u8, @ptrCast(info_dst.ptr))[0..info_bytes], .width = INFO_WIDTH, .height = atlas.layer_info_height });
        }
    }

    fn findFreeBinding(self: *Planner) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (!slot.active) return @intCast(i);
        }
        return null;
    }

    fn findSlotByGeneration(self: *const Planner, generation: u32) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return @intCast(i);
        }
        return null;
    }
};

fn emitRegion(out: []Region, out_len: *usize, r: Region) Error!void {
    if (out_len.* >= out.len) return error.RegionBufferFull;
    out[out_len.*] = r;
    out_len.* += 1;
}

fn firstOccurrence(records: anytype, i: usize) bool {
    const img = records[i].?.image;
    var j: usize = 0;
    while (j < i) : (j += 1) {
        const prev = records[j] orelse continue;
        if (prev.image == img) return false;
    }
    return true;
}

/// The array-layer assigned to `image` = its index among the distinct images in
/// first-seen order (matches the removed cache's hashmap ordering).
fn imageLayer(records: anytype, image: anytype) u32 {
    var layer: u32 = 0;
    var idx: usize = 0;
    while (idx < records.len) : (idx += 1) {
        const r = records[idx] orelse continue;
        if (!firstOccurrence(records, idx)) continue;
        if (r.image == image) return layer;
        layer += 1;
    }
    return layer;
}

fn countUniqueImages(atlas: *const Atlas) u32 {
    const records = atlas.paint_image_records orelse return 0;
    var seen: u32 = 0;
    for (records, 0..) |maybe_rec, i| {
        const rec = maybe_rec orelse continue;
        var dup = false;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            const prev = records[j] orelse continue;
            if (prev.image == rec.image) {
                dup = true;
                break;
            }
        }
        if (!dup) seen += 1;
    }
    return seen;
}

test "FreeList matches RangeAllocator take/release semantics" {
    var backing: [8]Range = undefined;
    var fl = FreeList{ .ranges = &backing };
    fl.reset(16);
    const a = fl.take(4).?;
    const b = fl.take(4).?;
    try std.testing.expectEqual(@as(u32, 0), a.base);
    try std.testing.expectEqual(@as(u32, 4), b.base);
    try fl.release(a);
    // First-fit reuses the freed low span.
    const c = fl.take(2).?;
    try std.testing.expectEqual(@as(u32, 0), c.base);
    const d = fl.take(8).?;
    try std.testing.expectEqual(@as(u32, 8), d.base);
}

test "Planner preflights atomically and is bound to one page pool" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4 * 2,
        .band_words_per_page = BAND_TEX_WIDTH * 2 * 2,
    });
    defer pool.deinit();
    var other_pool = try PagePool.init(allocator, pool.options);
    defer other_pool.deinit();

    const path_mod = @import("../path.zig");
    var path = path_mod.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves = try prepared_path.fillCurves(allocator, allocator);
    defer curves.deinit();
    var atlas = try Atlas.from(allocator, pool, &.{.{
        .key = @import("record_key.zig").unhintedGlyph(0, 1),
        .curves = curves,
    }});
    defer atlas.deinit();

    const opts = Options{
        .max_bindings = 1,
        .layer_info_height = 0,
        .max_images = 0,
        .max_image_width = 1,
        .max_image_height = 1,
    };
    const sz = sizes(pool, opts);
    const generation = try allocator.alloc(u16, sz.generation);
    defer allocator.free(generation);
    const curve_words = try allocator.alloc(u32, sz.curve_words);
    defer allocator.free(curve_words);
    const band_words = try allocator.alloc(u32, sz.band_words);
    defer allocator.free(band_words);
    const slots = try allocator.alloc(Slot, sz.bindings);
    defer allocator.free(slots);
    const info_free = try allocator.alloc(Range, sz.info_free);
    defer allocator.free(info_free);
    const image_free = try allocator.alloc(Range, sz.image_free);
    defer allocator.free(image_free);
    const regions = try allocator.alloc(Region, sz.regions);
    defer allocator.free(regions);

    var planner = try Planner.init(pool, opts, generation, curve_words, band_words, slots, info_free, image_free);
    var region_len: usize = 0;
    try std.testing.expectError(error.RegionBufferFull, planner.plan(&atlas, regions[0..0], &region_len, &.{}));
    try std.testing.expect(!slots[0].active);
    try std.testing.expectEqual(@as(u16, 0), generation[atlas.pages[0].layer_index]);

    const binding = try planner.plan(&atlas, regions, &region_len, &.{});
    try std.testing.expectEqual(@as(usize, 2), region_len);
    var foreign_binding = binding;
    foreign_binding.pool = other_pool;
    try std.testing.expectError(error.UnknownPool, planner.planDelta(foreign_binding, &atlas, regions, &region_len, &.{}));
    try std.testing.expect(!planner.release(foreign_binding));
    try std.testing.expect(planner.release(binding));
}
