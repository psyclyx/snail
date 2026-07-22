//! Font-atlas GPU upload planning — pure, caller-owned state, no allocator.
//!
//! Turns an `Atlas` into the set of texel `Region`s the caller must copy into
//! its own GPU textures, plus the `Binding` that `emit` consumes. This is the
//! font-specific atlas→layer mapping (a caller can't know it); everything about
//! GPU textures, uploads, and the queue is the caller's.
//!
//! No allocator: the caller owns every state buffer (sized via `sizes`) and the
//! output `Region` buffer, exactly like `emit` takes caller-provided words.
//! Every planner receives a unique binding-source identity, so bindings from
//! two device caches over the same page pool cannot alias.

const std = @import("std");

const atlas_mod = @import("../atlas.zig");
const page_mod = @import("page.zig");
const page_pool_mod = @import("page_pool.zig");
const draw_records = @import("../draw/records.zig");
const paint_records = @import("paint_records.zig");
const upload_patch = @import("upload_patch.zig");
const image_mod = @import("../image.zig");

pub const Atlas = atlas_mod.Atlas;
pub const Binding = draw_records.Binding;
pub const PagePool = page_pool_mod.PagePool;

pub const CURVE_TEX_WIDTH: u32 = page_mod.CURVE_TEX_WIDTH;
pub const BAND_TEX_WIDTH: u32 = page_mod.BAND_TEX_WIDTH;
pub const INFO_WIDTH: u32 = paint_records.info_width;

pub const Target = enum { curve, band, layer_info, image };

/// One texel copy the caller must apply to its own texture. `src` are the
/// packed source bytes for exactly `width * height` texels. `layer` is the
/// destination array layer (curve/band/image). `(col_base, row_base)` is
/// the destination texel origin: page-local for curve/band (deltas
/// re-upload only the grown texel span of an append-only page, split into
/// at most a partial head row, full middle rows, and a partial tail row),
/// absolute (the binding's slot rows) for layer_info.
///
/// Lifetime: `layer_info` regions alias the planner's scratch and are valid
/// until the next `plan`/`planDelta`. `curve`/`band` regions alias live page
/// memory, while `image` regions alias their source `Image`. The atlas, pages,
/// and images must stay alive and unmutated between planning and applying the
/// copies; don't `deinit`, `compact`, or extend them in between.
pub const Region = struct {
    target: Target,
    layer: u32 = 0,
    row_base: u32 = 0,
    col_base: u32 = 0,
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
    /// Exact byte size of one image texel in the host's array format. Every
    /// image in every binding must match. Defaults to the sRGBA8 format used
    /// by the reference backends and `snail-raster`.
    image_bytes_per_texel: u32 = 4,
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
    ImageTooLarge,
    InvalidImageFormat,
    InvalidAtlasData,
    BindingGenerationExhausted,
};

pub const InitError = PagePool.IdentityError || error{
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

/// Compute the exact caller-owned backing sizes. Returns `InvalidOptions`
/// instead of overflowing when capacities cannot be represented by the host.
pub fn sizes(pool: *const PagePool, opts: Options) InitError!Sizes {
    const bindings: usize = @intCast(opts.max_bindings);
    const images: usize = @intCast(opts.max_images);
    const layers: usize = @intCast(pool.options.max_layers);
    const info_free = std.math.add(usize, bindings, 1) catch return error.InvalidOptions;
    const image_free = info_free;
    const page_regions = std.math.mul(usize, layers, 6) catch return error.InvalidOptions;
    const regions_with_info = std.math.add(usize, page_regions, 1) catch return error.InvalidOptions;
    const regions = std.math.add(usize, regions_with_info, images) catch return error.InvalidOptions;
    const info_texels = std.math.mul(usize, INFO_WIDTH, @as(usize, opts.layer_info_height)) catch return error.InvalidOptions;
    const layer_info_scratch = std.math.mul(usize, info_texels, 4) catch return error.InvalidOptions;
    return .{
        .generation = layers,
        .curve_words = layers,
        .band_words = layers,
        .bindings = bindings,
        // First-fit free-list fragments to at most one span per binding, +1.
        .info_free = info_free,
        .image_free = image_free,
        // Up to 3 regions per plane per page (partial head row, full middle
        // rows, partial tail row).
        .regions = regions,
        // layer_info is RGBA32F — 4 f32 per INFO_WIDTH texel. `layer_info_data`
        // is `INFO_WIDTH * height * 4` floats, and `plan` memcpys the whole slab
        // into this scratch, so it must be 4× the texel count (not ×1).
        .layer_info_scratch = layer_info_scratch,
    };
}

/// Free-list element; exposed so a caller can allocate the `info_free` /
/// `image_free` backing (sized via `sizes`).
pub const Range = struct { base: u32, size: u32 };

/// Fixed-capacity first-fit free-list over caller-provided backing — the
/// allocator-free twin of `snail-raster`'s range allocator (identical
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
    generation: u64 = 0,
    info_row_base: u32 = 0,
    info_height: u32 = 0,
    image_layer_base: u32 = 0,
    image_count: u32 = 0,
    /// Layer-info rows already uploaded for this binding. The slab is
    /// append-only and row-aligned across `Atlas.extend` (each snapshot
    /// pads to whole rows), so deltas upload only rows past this mark.
    uploaded_info_rows: u32 = 0,
    /// Snapshot whose binding-relative side data currently occupies this
    /// slot. Exact snapshots need no side-data upload; direct children may
    /// append; branches, skipped descendants, and unrelated atlases trigger
    /// a conservative full side-data replacement.
    snapshot_id: u64 = 0,
    lineage: u64 = 0,
};

/// Caller-owned planning state. Backing slices are the caller's; `Planner` never
/// allocates. Build the slices sized to `sizes(pool, opts)` and pass them to
/// `init`.
pub const Planner = struct {
    pool: *PagePool,
    source_id: u64,
    opts: Options,
    prepared_generation: []u64,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,
    bindings: []Slot,
    info_free: FreeList,
    image_free: FreeList,
    upload_generation: u64 = 0,

    pub fn init(
        pool: *PagePool,
        opts: Options,
        generation: []u64,
        curve_words: []u32,
        band_words: []u32,
        binding_slots: []Slot,
        info_free_backing: []Range,
        image_free_backing: []Range,
    ) InitError!Planner {
        const layers: usize = @intCast(pool.options.max_layers);
        const binding_count = std.math.cast(usize, opts.max_bindings) orelse return error.InvalidOptions;
        const free_count = std.math.add(usize, binding_count, 1) catch return error.InvalidOptions;
        if (generation.len < layers or
            curve_words.len < layers or
            band_words.len < layers or
            binding_slots.len < binding_count or
            info_free_backing.len < free_count or
            image_free_backing.len < free_count)
        {
            return error.BackingTooSmall;
        }
        if (pool.options.curve_words_per_page % (CURVE_TEX_WIDTH * 4) != 0 or
            pool.options.band_words_per_page % (BAND_TEX_WIDTH * 2) != 0 or
            (opts.max_images > 0 and (opts.max_image_width == 0 or opts.max_image_height == 0 or opts.image_bytes_per_texel == 0)))
        {
            return error.InvalidOptions;
        }
        const generation_used = generation[0..layers];
        const curve_words_used = curve_words[0..layers];
        const band_words_used = band_words[0..layers];
        const bindings_used = binding_slots[0..binding_count];
        @memset(generation_used, 0);
        @memset(curve_words_used, 0);
        @memset(band_words_used, 0);
        for (bindings_used) |*b| b.* = .{};
        var self = Planner{
            .pool = pool,
            .source_id = try pool.nextBindingSourceId(),
            .opts = opts,
            .prepared_generation = generation_used,
            .prepared_curve_words = curve_words_used,
            .prepared_band_words = band_words_used,
            .bindings = bindings_used,
            .info_free = .{ .ranges = info_free_backing[0..free_count] },
            .image_free = .{ .ranges = image_free_backing[0..free_count] },
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
        const image_count = try countUniqueImages(atlas);

        const slot_index = self.findFreeBinding() orelse return error.NoFreeBinding;
        const info_range = self.info_free.take(info_height) orelse return error.NoFreeLayerInfoRows;
        errdefer self.info_free.release(info_range) catch {};
        const image_range = self.image_free.take(image_count) orelse return error.NoFreeImageLayers;
        errdefer self.image_free.release(image_range) catch {};

        const next_generation = std.math.add(u64, self.upload_generation, 1) catch return error.BindingGenerationExhausted;
        const slot = &self.bindings[slot_index];
        errdefer slot.* = .{};
        slot.* = .{
            .active = true,
            .generation = next_generation,
            .info_row_base = info_range.base,
            .info_height = info_range.size,
            .image_layer_base = image_range.base,
            .image_count = image_range.size,
        };

        try self.queue(atlas, slot, out_regions, out_len, layer_info_scratch);
        const identity = atlas.snapshotIdentity();
        slot.snapshot_id = identity.snapshot_id;
        slot.lineage = identity.lineage;
        self.upload_generation = next_generation;
        return .{ .pool = self.pool, .source_id = self.source_id, .generation = slot.generation, .info_row_base = slot.info_row_base, .image_layer_base = slot.image_layer_base };
    }

    /// Plan an incremental re-upload of `atlas` into the slot `prev_binding`
    /// already owns (only changed curve/band/layer-info/image regions).
    pub fn planDelta(self: *Planner, prev_binding: Binding, atlas: *const Atlas, out_regions: []Region, out_len: *usize, layer_info_scratch: []f32) Error!Binding {
        out_len.* = 0;
        if (prev_binding.pool != self.pool) return error.UnknownPool;
        if (prev_binding.source_id != self.source_id) return error.UnknownBinding;
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        const slot_index = self.findSlotByGeneration(prev_binding.generation) orelse return error.UnknownBinding;
        const slot = &self.bindings[slot_index];
        if (!slot.active or
            slot.info_row_base != prev_binding.info_row_base or
            slot.image_layer_base != prev_binding.image_layer_base)
        {
            return error.UnknownBinding;
        }
        const info_height: u32 = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
        if (info_height > slot.info_height) return error.NoLayerInfoRoomToGrow;
        if (try countUniqueImages(atlas) > slot.image_count) return error.NoImageRoomToGrow;

        try self.queue(atlas, slot, out_regions, out_len, layer_info_scratch);
        const identity = atlas.snapshotIdentity();
        slot.snapshot_id = identity.snapshot_id;
        slot.lineage = identity.lineage;
        return .{ .pool = self.pool, .source_id = self.source_id, .generation = slot.generation, .info_row_base = slot.info_row_base, .image_layer_base = slot.image_layer_base };
    }

    /// Free the binding's slot + ranges. Returns whether a live slot was freed
    /// (false if the binding was unknown/already released).
    pub fn release(self: *Planner, binding: Binding) bool {
        if (binding.pool != self.pool) return false;
        if (binding.source_id != self.source_id) return false;
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return false;
        const slot = &self.bindings[slot_index];
        if (!slot.active or
            slot.info_row_base != binding.info_row_base or
            slot.image_layer_base != binding.image_layer_base)
        {
            return false;
        }
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
        for (self.bindings) |*slot| slot.uploaded_info_rows = 0;
    }

    fn queue(self: *Planner, atlas: *const Atlas, slot: *Slot, out: []Region, out_len: *usize, layer_info_scratch: []f32) Error!void {
        // Validate the entire request before changing any watermark. Once this
        // preflight succeeds, emitting the regions cannot fail halfway through
        // and leave planner state ahead of the returned list.
        var region_count: usize = 0;
        const identity = atlas.snapshotIdentity();
        const exact_snapshot = slot.snapshot_id != 0 and slot.snapshot_id == identity.snapshot_id;
        const direct_child = slot.snapshot_id != 0 and
            slot.lineage == identity.lineage and identity.parent_snapshot_id == slot.snapshot_id;
        const replace_side_data = !exact_snapshot and !direct_child;
        var info_from_row: u32 = 0;
        for (atlas.pages) |p| {
            const layer: u32 = p.layer_index;
            if (layer >= self.pool.options.max_layers or self.pool.pages[layer] != p) return error.PageNotInPool;
            const stale = self.prepared_generation[layer] != p.currentGeneration() or
                p.curve.usedWords() != self.prepared_curve_words[layer] or
                p.band.usedWords() != self.prepared_band_words[layer];
            if (stale) region_count += 6;
        }
        if (atlas.paint_image_records) |records| {
            var next_image_layer: u32 = 0;
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                if (rec.first_image_use) {
                    if (rec.image_layer != next_image_layer) return error.InvalidAtlasData;
                    next_image_layer = std.math.add(u32, next_image_layer, 1) catch return error.InvalidAtlasData;
                } else if (rec.image_layer >= next_image_layer) {
                    return error.InvalidAtlasData;
                }
                if (rec.image.width == 0 or rec.image.height == 0) return error.InvalidImageFormat;
                if (rec.image.width > self.opts.max_image_width or rec.image.height > self.opts.max_image_height) return error.ImageTooLarge;
                const pixel_count = std.math.mul(usize, @as(usize, rec.image.width), @as(usize, rec.image.height)) catch return error.InvalidImageFormat;
                const expected_bytes = std.math.mul(usize, pixel_count, @as(usize, self.opts.image_bytes_per_texel)) catch return error.InvalidImageFormat;
                if (rec.image.texels.len != expected_bytes) return error.InvalidImageFormat;
                if (replace_side_data and rec.first_image_use) region_count += 1;
            }
        }
        if (atlas.layer_info_data) |info| {
            const expected_len = std.math.mul(usize, @as(usize, atlas.layer_info_width), @as(usize, atlas.layer_info_height)) catch return error.InvalidAtlasData;
            const expected_floats = std.math.mul(usize, expected_len, 4) catch return error.InvalidAtlasData;
            if (atlas.layer_info_width != INFO_WIDTH or info.len != expected_floats) return error.InvalidAtlasData;
            if (atlas.paint_image_records) |records| {
                const texel_count = expected_len;
                for (records) |maybe_rec| {
                    const rec = maybe_rec orelse continue;
                    const texel_offset: usize = rec.texel_offset;
                    if (texel_offset > texel_count or texel_count - texel_offset < 6) return error.InvalidAtlasData;
                }
            }
            if (info.len > layer_info_scratch.len) return error.LayerInfoScratchTooSmall;
            info_from_row = if (replace_side_data or slot.uploaded_info_rows > atlas.layer_info_height) 0 else slot.uploaded_info_rows;
            if (atlas.layer_info_height > info_from_row) region_count += 1;
        } else if (atlas.layer_info_height != 0 or atlas.layer_info_width != 0 or atlas.paint_image_records != null) {
            return error.InvalidAtlasData;
        }
        if (region_count > out.len) return error.RegionBufferFull;

        for (atlas.pages) |p| {
            const layer: u32 = p.layer_index;
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const gen_match = self.prepared_generation[layer] == cur_gen;
            const stale = !gen_match or
                cur_curve != self.prepared_curve_words[layer] or
                cur_band != self.prepared_band_words[layer];
            if (!stale) continue;
            self.prepared_generation[layer] = cur_gen;

            // Pages are append-only, so within a generation only the words
            // past the previous watermark can have changed; a generation
            // change (fresh or reused page) re-uploads from word zero. The
            // watermark's boundary texel re-uploads whole — its prefix is
            // immutable, so rewriting it is redundant, never wrong.
            const curve_from: u32 = if (gen_match) @min(self.prepared_curve_words[layer], cur_curve) else 0;
            const band_from: u32 = if (gen_match) @min(self.prepared_band_words[layer], cur_band) else 0;
            try emitPlaneTail(out, out_len, .curve, layer, p.curve.data, 4, CURVE_TEX_WIDTH, curve_from, cur_curve);
            try emitPlaneTail(out, out_len, .band, layer, p.band.data, 2, BAND_TEX_WIDTH, band_from, cur_band);
            self.prepared_curve_words[layer] = cur_curve;
            self.prepared_band_words[layer] = cur_band;
        }

        // layer_info + image paints. Image paint records reference an image
        // whose array-layer + uv-scale are only known here (the caller's
        // texture packing); patch them into a private copy of the slab so the
        // shared atlas data is untouched.
        const info = atlas.layer_info_data orelse {
            slot.uploaded_info_rows = 0;
            return;
        };
        const info_dst = layer_info_scratch[0..info.len];
        const row_floats = @as(usize, INFO_WIDTH) * 4;
        const copy_start = @as(usize, info_from_row) * row_floats;
        if (copy_start < info.len) @memcpy(info_dst[copy_start..], info[copy_start..]);

        if (atlas.paint_image_records) |records| {
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                const abs_layer = slot.image_layer_base + rec.image_layer;
                // Initial bindings and conservative side-data replacements
                // upload each image once. Exact snapshots and direct children
                // preserve the slot's existing image layers.
                if (replace_side_data and rec.first_image_use) {
                    try emitRegion(out, out_len, .{ .target = .image, .layer = abs_layer, .src = rec.image.texels, .width = rec.image.width, .height = rec.image.height });
                }
                if (rec.texel_offset / INFO_WIDTH >= info_from_row) {
                    const uv_x: f32 = @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(self.opts.max_image_width));
                    const uv_y: f32 = @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(self.opts.max_image_height));
                    upload_patch.patchImagePaintRecord(info_dst, INFO_WIDTH, INFO_WIDTH, 0, rec.texel_offset, .{
                        .layer = abs_layer,
                        .uv_scale = .{ .x = uv_x, .y = uv_y },
                    });
                }
            }
        }

        if (atlas.layer_info_height > 0) {
            // The slab is append-only and row-aligned across `Atlas.extend`
            // (snapshots pad to whole rows), so re-upload only rows past
            // this binding's watermark. A shrunken slab means the binding
            // was replanned against a different lineage: upload everything.
            if (atlas.layer_info_height > info_from_row) {
                const src_floats = info_dst[@as(usize, info_from_row) * row_floats .. @as(usize, atlas.layer_info_height) * row_floats];
                try emitRegion(out, out_len, .{
                    .target = .layer_info,
                    .row_base = slot.info_row_base + info_from_row,
                    .src = @as([*]const u8, @ptrCast(src_floats.ptr))[0 .. src_floats.len * @sizeOf(f32)],
                    .width = INFO_WIDTH,
                    .height = atlas.layer_info_height - info_from_row,
                });
            }
            slot.uploaded_info_rows = atlas.layer_info_height;
        }
    }

    /// Emit the changed texel span of one append-only page plane — words
    /// `[from, to)` rounded out to whole texels — as at most three packed
    /// regions: a partial head row, full middle rows, and a partial tail
    /// row. No-op when the plane hasn't grown (e.g. only the sibling plane
    /// changed).
    fn emitPlaneTail(
        out: []Region,
        out_len: *usize,
        target: Target,
        layer: u32,
        data: []const page_mod.Word,
        words_per_texel: u32,
        tex_width: u32,
        from: u32,
        to: u32,
    ) Error!void {
        if (to <= from) return;
        const texel_from = from / words_per_texel;
        const texel_to = (to + words_per_texel - 1) / words_per_texel;

        const emitSpan = struct {
            fn f(o: []Region, len: *usize, t: Target, l: u32, d: []const page_mod.Word, wpt: u32, first: u32, count_texels: u32, col: u32, row: u32, w: u32, h: u32) Error!void {
                const byte_base = @as(usize, first) * wpt * @sizeOf(page_mod.Word);
                const byte_len = @as(usize, count_texels) * wpt * @sizeOf(page_mod.Word);
                try emitRegion(o, len, .{
                    .target = t,
                    .layer = l,
                    .row_base = row,
                    .col_base = col,
                    .src = @as([*]const u8, @ptrCast(d.ptr))[byte_base .. byte_base + byte_len],
                    .width = w,
                    .height = h,
                });
            }
        }.f;

        const first_row = texel_from / tex_width;
        const last_row = (texel_to - 1) / tex_width;
        const col0 = texel_from % tex_width;

        if (first_row == last_row) {
            try emitSpan(out, out_len, target, layer, data, words_per_texel, texel_from, texel_to - texel_from, col0, first_row, texel_to - texel_from, 1);
            return;
        }

        var mid_start_row = first_row;
        if (col0 != 0) {
            const head_texels = tex_width - col0;
            try emitSpan(out, out_len, target, layer, data, words_per_texel, texel_from, head_texels, col0, first_row, head_texels, 1);
            mid_start_row += 1;
        }
        const tail_texels = texel_to - last_row * tex_width;
        const mid_end_row = if (tail_texels == tex_width) last_row + 1 else last_row;
        if (mid_end_row > mid_start_row) {
            const mid_first = mid_start_row * tex_width;
            const mid_count = (mid_end_row - mid_start_row) * tex_width;
            try emitSpan(out, out_len, target, layer, data, words_per_texel, mid_first, mid_count, 0, mid_start_row, tex_width, mid_end_row - mid_start_row);
        }
        if (tail_texels != tex_width) {
            try emitSpan(out, out_len, target, layer, data, words_per_texel, last_row * tex_width, tail_texels, 0, last_row, tail_texels, 1);
        }
    }

    fn findFreeBinding(self: *Planner) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (!slot.active) return @intCast(i);
        }
        return null;
    }

    fn findSlotByGeneration(self: *const Planner, generation: u64) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return @intCast(i);
        }
        return null;
    }
};

/// Result of one owned-planner operation. `regions` remains valid until the
/// next `plan` or `planDelta` call on the same `OwnedPlanner`.
pub const PlannedUpload = struct {
    binding: Binding,
    regions: []const Region,
};

/// Allocator-backed convenience around `Planner`. It owns only the planner's
/// backend-neutral bookkeeping, region output, and layer-info scratch; GPU
/// resources and the application of each `Region` remain entirely caller-owned.
pub const OwnedPlanner = struct {
    allocator: std.mem.Allocator,
    planner: Planner,
    generation: []u64,
    curve_words: []u32,
    band_words: []u32,
    bindings: []Slot,
    info_free: []Range,
    image_free: []Range,
    regions: []Region,
    layer_info_scratch: []f32,

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, opts: Options) (std.mem.Allocator.Error || InitError)!OwnedPlanner {
        const required = try sizes(pool, opts);
        const generation = try allocator.alloc(u64, required.generation);
        errdefer allocator.free(generation);
        const curve_words = try allocator.alloc(u32, required.curve_words);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, required.band_words);
        errdefer allocator.free(band_words);
        const bindings = try allocator.alloc(Slot, required.bindings);
        errdefer allocator.free(bindings);
        const info_free = try allocator.alloc(Range, required.info_free);
        errdefer allocator.free(info_free);
        const image_free = try allocator.alloc(Range, required.image_free);
        errdefer allocator.free(image_free);
        const regions = try allocator.alloc(Region, required.regions);
        errdefer allocator.free(regions);
        const layer_info_scratch = try allocator.alloc(f32, required.layer_info_scratch);
        errdefer allocator.free(layer_info_scratch);

        return .{
            .allocator = allocator,
            .planner = try Planner.init(pool, opts, generation, curve_words, band_words, bindings, info_free, image_free),
            .generation = generation,
            .curve_words = curve_words,
            .band_words = band_words,
            .bindings = bindings,
            .info_free = info_free,
            .image_free = image_free,
            .regions = regions,
            .layer_info_scratch = layer_info_scratch,
        };
    }

    pub fn deinit(self: *OwnedPlanner) void {
        self.allocator.free(self.generation);
        self.allocator.free(self.curve_words);
        self.allocator.free(self.band_words);
        self.allocator.free(self.bindings);
        self.allocator.free(self.info_free);
        self.allocator.free(self.image_free);
        self.allocator.free(self.regions);
        self.allocator.free(self.layer_info_scratch);
        self.* = undefined;
    }

    pub fn plan(self: *OwnedPlanner, atlas: *const Atlas) Error!PlannedUpload {
        var region_count: usize = 0;
        const binding = try self.planner.plan(atlas, self.regions, &region_count, self.layer_info_scratch);
        return .{ .binding = binding, .regions = self.regions[0..region_count] };
    }

    pub fn planDelta(self: *OwnedPlanner, previous: Binding, atlas: *const Atlas) Error!PlannedUpload {
        var region_count: usize = 0;
        const binding = try self.planner.planDelta(previous, atlas, self.regions, &region_count, self.layer_info_scratch);
        return .{ .binding = binding, .regions = self.regions[0..region_count] };
    }

    pub fn release(self: *OwnedPlanner, binding: Binding) bool {
        return self.planner.release(binding);
    }

    pub fn invalidateUploads(self: *OwnedPlanner) void {
        self.planner.invalidateUploads();
    }
};

fn emitRegion(out: []Region, out_len: *usize, r: Region) Error!void {
    if (out_len.* >= out.len) return error.RegionBufferFull;
    out[out_len.*] = r;
    out_len.* += 1;
}

fn countUniqueImages(atlas: *const Atlas) Error!u32 {
    const records = atlas.paint_image_records orelse return 0;
    var seen: u32 = 0;
    for (records) |maybe_rec| {
        const rec = maybe_rec orelse continue;
        if (rec.first_image_use) seen = std.math.add(u32, seen, 1) catch return error.InvalidAtlasData;
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

test "OwnedPlanner owns only backend-neutral planner storage" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4,
        .band_words_per_page = BAND_TEX_WIDTH * 2,
    });
    defer pool.deinit();

    var planner = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = 0,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    });
    defer planner.deinit();

    var atlas = Atlas.empty(allocator);
    defer atlas.deinit();
    const upload = try planner.plan(&atlas);
    try std.testing.expectEqual(@as(usize, 0), upload.regions.len);
    try std.testing.expect(planner.release(upload.binding));
}

test "bindings are scoped to the exact planner even within one pool" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4,
        .band_words_per_page = BAND_TEX_WIDTH * 2,
    });
    defer pool.deinit();
    const opts = Options{
        .max_bindings = 1,
        .layer_info_height = 0,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    };
    var first_planner = try OwnedPlanner.init(allocator, pool, opts);
    defer first_planner.deinit();
    var second_planner = try OwnedPlanner.init(allocator, pool, opts);
    defer second_planner.deinit();
    var atlas = try Atlas.init(allocator, pool);
    defer atlas.deinit();

    const first = try first_planner.plan(&atlas);
    const second = try second_planner.plan(&atlas);
    try std.testing.expect(first.binding.source_id != second.binding.source_id);
    try std.testing.expectEqual(first.binding.generation, second.binding.generation);
    try std.testing.expect(!first_planner.release(second.binding));
    try std.testing.expectError(error.UnknownBinding, first_planner.planDelta(second.binding, &atlas));
    try std.testing.expect(first_planner.release(first.binding));
    try std.testing.expect(second_planner.release(second.binding));
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
    const sz = try sizes(pool, opts);
    const generation = try allocator.alloc(u64, sz.generation);
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
    try std.testing.expectEqual(@as(u64, 0), generation[atlas.pages[0].layer_index]);

    const binding = try planner.plan(&atlas, regions, &region_len, &.{});
    try std.testing.expectEqual(@as(usize, 2), region_len);
    var foreign_binding = binding;
    foreign_binding.pool = other_pool;
    try std.testing.expectError(error.UnknownPool, planner.planDelta(foreign_binding, &atlas, regions, &region_len, &.{}));
    try std.testing.expect(!planner.release(foreign_binding));
    var forged_binding = binding;
    forged_binding.info_row_base += 1;
    try std.testing.expectError(error.UnknownBinding, planner.planDelta(forged_binding, &atlas, regions, &region_len, &.{}));
    try std.testing.expect(!planner.release(forged_binding));
    try std.testing.expect(planner.release(binding));
}

test "planDelta fully replaces side data for an unrelated same-height atlas" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4,
        .band_words_per_page = BAND_TEX_WIDTH * 2,
    });
    defer pool.deinit();

    const path_mod = @import("../path.zig");
    var path = path_mod.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves_a = try prepared_path.fillCurves(allocator, allocator);
    defer curves_a.deinit();
    var curves_b = try prepared_path.fillCurves(allocator, allocator);
    defer curves_b.deinit();

    const key_mod = @import("record_key.zig");
    var atlas_a = try Atlas.from(allocator, pool, &.{.{
        .key = .{ .namespace = key_mod.ns.path_fill, .a = 1 },
        .curves = curves_a,
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }});
    defer atlas_a.deinit();
    var atlas_b = try Atlas.from(allocator, pool, &.{.{
        .key = .{ .namespace = key_mod.ns.path_fill, .a = 2 },
        .curves = curves_b,
        .paint = .{ .solid = .{ 0, 1, 0, 1 } },
    }});
    defer atlas_b.deinit();
    try std.testing.expectEqual(atlas_a.layer_info_height, atlas_b.layer_info_height);
    try std.testing.expect(atlas_a.snapshotIdentity().lineage != atlas_b.snapshotIdentity().lineage);

    var planner = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = atlas_a.layer_info_height,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    });
    defer planner.deinit();

    const first = try planner.plan(&atlas_a);
    const replacement = try planner.planDelta(first.binding, &atlas_b);
    var saw_full_info = false;
    for (replacement.regions) |region| {
        if (region.target != .layer_info) continue;
        saw_full_info = true;
        try std.testing.expectEqual(first.binding.info_row_base, region.row_base);
        try std.testing.expectEqual(atlas_b.layer_info_height, region.height);
    }
    try std.testing.expect(saw_full_info);

    const unchanged = try planner.planDelta(first.binding, &atlas_b);
    for (unchanged.regions) |region| try std.testing.expect(region.target != .layer_info);
    try std.testing.expect(planner.release(first.binding));
}

test "planner enforces image dimensions and texel format atomically" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4,
        .band_words_per_page = BAND_TEX_WIDTH * 2,
    });
    defer pool.deinit();

    const path_mod = @import("../path.zig");
    var path = path_mod.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves = try prepared_path.fillCurves(allocator, allocator);
    defer curves.deinit();

    var image = try image_mod.Image.init(allocator, 2, 1, &[_]u8{ 255, 0, 0, 255, 0, 255, 0, 255 });
    defer image.deinit();
    var atlas = try Atlas.from(allocator, pool, &.{.{
        .key = .{ .namespace = @import("record_key.zig").ns.path_fill, .a = 1 },
        .curves = curves,
        .paint = .{ .image = .{ .image = &image, .uv_transform = .identity } },
    }});
    defer atlas.deinit();

    var too_small = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = atlas.layer_info_height,
        .max_images = 1,
        .max_image_width = 1,
        .max_image_height = 1,
    });
    defer too_small.deinit();
    try std.testing.expectError(error.ImageTooLarge, too_small.plan(&atlas));
    try std.testing.expect(!too_small.bindings[0].active);

    var wrong_format = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = atlas.layer_info_height,
        .max_images = 1,
        .max_image_width = 2,
        .max_image_height = 1,
        .image_bytes_per_texel = 3,
    });
    defer wrong_format.deinit();
    try std.testing.expectError(error.InvalidImageFormat, wrong_format.plan(&atlas));
    try std.testing.expect(!wrong_format.bindings[0].active);
}

test "planDelta uploads only the grown row band of an append-only page" {
    const allocator = std.testing.allocator;
    const GlyphCurves = atlas_mod.GlyphCurves;
    const curve_row_words: u32 = CURVE_TEX_WIDTH * 4;
    const band_row_words: u32 = BAND_TEX_WIDTH * 2;
    const segment_words: u32 = 16; // CURVE_SEGMENT_TEXELS * 4

    var pool = try PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = curve_row_words * 4,
        .band_words_per_page = band_row_words * 2,
    });
    defer pool.deinit();

    const Synthetic = struct {
        fn curves(alloc: std.mem.Allocator, segment_count: u16) !GlyphCurves {
            const curve_bytes = try alloc.alloc(u16, @as(usize, segment_count) * segment_words);
            for (curve_bytes, 0..) |*w, i| w.* = @truncate(i);
            for (0..segment_count) |curve_index| {
                curve_bytes[curve_index * segment_words + 10] = 0; // packed quadratic
            }
            // 1 h-band + 1 v-band, one ref each, both pointing at curve 0.
            const band_bytes = try alloc.alloc(u16, 8);
            band_bytes[0] = 1;
            band_bytes[1] = 2;
            band_bytes[2] = 1;
            band_bytes[3] = 3;
            band_bytes[4] = 0;
            band_bytes[5] = 0;
            band_bytes[6] = 0;
            band_bytes[7] = 0;
            return .{
                .allocator = alloc,
                .curve_bytes = curve_bytes,
                .band_bytes = band_bytes,
                .curve_count = segment_count,
                .h_band_count = 1,
                .v_band_count = 1,
                .band_scale_x = 1.0,
                .band_scale_y = 1.0,
                .band_offset_x = 0.0,
                .band_offset_y = 0.0,
                .bbox = .{ .min = .zero, .max = .{ .x = 1, .y = 1 } },
            };
        }
    };

    // Big enough to spill into the second curve row (one row holds
    // curve_row_words / segment_words segments).
    const row_segments: u16 = @intCast(curve_row_words / segment_words);
    var big = try Synthetic.curves(allocator, row_segments + 128);
    defer big.deinit();
    var atlas = try Atlas.from(allocator, pool, &.{
        .{ .key = @import("record_key.zig").unhintedGlyph(0, 1), .curves = big },
    });
    defer atlas.deinit();

    var planner = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = 0,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    });
    defer planner.deinit();

    // Fresh plan: the big glyph spans a full first row plus a partial
    // second row — one full-width region and one partial tail row.
    const first = try planner.plan(&atlas);
    var full_rows: usize = 0;
    var tails: usize = 0;
    for (first.regions) |r| {
        if (r.target != .curve) continue;
        if (r.width == CURVE_TEX_WIDTH) {
            full_rows += 1;
            try std.testing.expectEqual(@as(u32, 0), r.row_base);
            try std.testing.expectEqual(@as(u32, 0), r.col_base);
            try std.testing.expectEqual(@as(u32, 1), r.height);
        } else {
            tails += 1;
            try std.testing.expectEqual(@as(u32, 1), r.row_base);
            try std.testing.expectEqual(@as(u32, 0), r.col_base);
            try std.testing.expectEqual(@as(u32, 128 * 4), r.width); // 128 segments * 4 texels
        }
    }
    try std.testing.expectEqual(@as(usize, 1), full_rows);
    try std.testing.expectEqual(@as(usize, 1), tails);

    // Unchanged replan: nothing to upload.
    const unchanged = try planner.planDelta(first.binding, &atlas);
    try std.testing.expectEqual(@as(usize, 0), unchanged.regions.len);

    // Append a small glyph: only its texel span re-uploads — a sub-row
    // rectangle, not the page and not even a full row.
    var small = try Synthetic.curves(allocator, 8);
    defer small.deinit();
    try atlas.extendInPlace(allocator, &.{
        .{ .key = @import("record_key.zig").unhintedGlyph(0, 2), .curves = small },
    });
    const delta = try planner.planDelta(first.binding, &atlas);
    var curve_regions: usize = 0;
    for (delta.regions) |r| {
        switch (r.target) {
            .curve => {
                curve_regions += 1;
                try std.testing.expectEqual(@as(u32, 1), r.row_base);
                try std.testing.expectEqual(@as(u32, 128 * 4), r.col_base);
                try std.testing.expectEqual(@as(u32, 8 * 4), r.width); // 8 segments
                try std.testing.expectEqual(@as(u32, 1), r.height);
                try std.testing.expectEqual(@as(usize, 8 * 4 * 4) * 2, r.src.len);
            },
            .band => {
                // Band watermark: 8 words already resident, 8 appended.
                try std.testing.expectEqual(@as(u32, 0), r.row_base);
                try std.testing.expectEqual(@as(u32, 4), r.col_base);
                try std.testing.expectEqual(@as(u32, 4), r.width);
                try std.testing.expectEqual(@as(u32, 1), r.height);
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), curve_regions);
    try std.testing.expect(planner.release(first.binding));
}

test "planDelta uploads only appended layer-info rows" {
    const allocator = std.testing.allocator;
    var pool = try PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = CURVE_TEX_WIDTH * 4,
        .band_words_per_page = BAND_TEX_WIDTH * 2,
    });
    defer pool.deinit();

    const path_mod = @import("../path.zig");
    var path = path_mod.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves = try prepared_path.fillCurves(allocator, allocator);
    defer curves.deinit();

    const record_key = @import("record_key.zig");
    var atlas = try Atlas.from(allocator, pool, &.{.{
        .key = .{ .namespace = record_key.ns.path_fill, .a = 1 },
        .curves = curves,
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }});
    defer atlas.deinit();

    var planner = try OwnedPlanner.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = 4,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    });
    defer planner.deinit();

    const first = try planner.plan(&atlas);
    var info_rows_first: u32 = 0;
    for (first.regions) |r| {
        if (r.target == .layer_info) {
            try std.testing.expectEqual(@as(u32, 0), r.row_base);
            info_rows_first = r.height;
        }
    }
    try std.testing.expectEqual(@as(u32, 1), info_rows_first);

    // Page growth without new side records: the resident layer-info rows
    // are past the binding's watermark, so no info region is emitted at
    // all (previously every delta re-uploaded the whole slab). Info
    // *growth* exceeds the slot's exact-size reservation and still takes
    // the documented release + replan path.
    var more = try prepared_path.fillCurves(allocator, allocator);
    defer more.deinit();
    try atlas.extendInPlace(allocator, &.{.{
        .key = record_key.unhintedGlyph(0, 7),
        .curves = more,
    }});
    const delta = try planner.planDelta(first.binding, &atlas);
    var saw_pages = false;
    for (delta.regions) |r| {
        try std.testing.expect(r.target != .layer_info);
        if (r.target == .curve or r.target == .band) saw_pages = true;
    }
    try std.testing.expect(saw_pages);
    try std.testing.expect(planner.release(first.binding));
}
