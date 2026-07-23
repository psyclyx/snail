//! The software rasterizer's device-side atlas: resident CPU copies of
//! uploaded atlas records for one `PagePool`, with caller-controlled
//! lifecycle primitives.
//!
//! Placement (binding slots, layer-info rows, image layers) is driven by
//! the shared `snail.atlas_upload` planner — the same planner the GPU
//! reference callers use — so bindings and the emit stream are identical
//! across backends by construction. This type owns only the CPU "device"
//! side: prepared per-layer page data, the persistent layer-info buffer, and
//! the image pointer table.
//!
//! - `init(allocator, pool, options)` allocates fixed-capacity storage
//!   for `max_bindings`, `layer_info_height` rows of paint records, and
//!   `max_images` image references. The caller decides how much is
//!   enough; a `DeviceAtlas` never auto-grows.
//! - `upload(scratch, atlases, out_bindings)` plans one binding per atlas and applies
//!   the planned regions. Errors with `error.NoFreeBinding` /
//!   `error.NoFreeLayerInfoRows` / `error.NoFreeImageLayers` if capacity
//!   is exceeded — the caller handles by releasing retired bindings or
//!   calling `resize`.
//! - `release(binding)` returns the slot's storage to the free list.
//! - `uploadDelta(scratch, binding, atlas)` updates a live slot. Append-only direct
//!   children reuse unchanged prepared data; branches and unrelated snapshots
//!   conservatively replace their side data within the slot's reserved capacity.
//! - `resize(options)` reshapes the storage. Errors if there are active
//!   bindings.
//!
//! Image paints borrow both the `Image` value and its texel slice. Keep them
//! alive and unmodified until every binding that references them is released or
//! replaced. This backend accepts exactly four bytes per texel: RGBA with
//! sRGB-encoded RGB and straight alpha.

const std = @import("std");

const atlas_mod = @import("snail");
const draw_records = @import("snail").render.records;
const page_pool_mod = @import("snail");
const upload_plan = @import("snail").atlas_upload;
const resources_mod = @import("resources.zig");
const texture_mod = @import("texture.zig");
const path_paint_mod = @import("path_paint.zig");
const image_mod = @import("snail");

pub const Atlas = atlas_mod.Atlas;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const PreparedAtlasPage = resources_mod.PreparedAtlasPage;
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

fn validateAtlasImages(atlas: *const Atlas) UploadError!void {
    const records = atlas.paint_records orelse return;
    for (records) |record| {
        const image = record.image orelse continue;
        if (image.bytesPerTexel() != 4) return error.InvalidImageFormat;
    }
}

fn layerInfoFloatCount(height: u32) upload_plan.InitError!usize {
    const row_floats = std.math.mul(usize, INFO_WIDTH, 4) catch return error.InvalidOptions;
    return std.math.mul(usize, row_floats, height) catch return error.InvalidOptions;
}

pub const DeviceAtlasOptions = struct {
    /// Maximum number of simultaneously live bindings.
    max_bindings: u32 = 16,
    /// Total rows in the shared RGBA32F layer-info store. Active bindings take
    /// disjoint row ranges from this fixed capacity.
    layer_info_height: u32 = 64,
    /// Total image-reference layers shared by active bindings. Repeated uses of
    /// the same `*const Image` within one atlas consume one layer.
    max_images: u32 = 16,
};
pub const UploadError = upload_plan.Error || std.mem.Allocator.Error || error{
    /// `atlases` and `out_bindings` must have identical lengths.
    BindingOutputLengthMismatch,
    /// The request length or resulting active-binding count cannot be
    /// represented as `u32`.
    ActiveBindingCountOverflow,
    /// An image has zero dimensions or is not exactly width*height*4 bytes.
    InvalidImageFormat,
    /// A planner region does not match the CPU device's texture contract.
    InvalidUploadRegion,
    /// The uploaded RGBA32F layer-info slab contains a truncated, non-finite,
    /// out-of-range, or otherwise malformed path-paint record.
    InvalidLayerInfo,
    /// Uploaded band references or curve records are non-canonical or point
    /// outside the published texture words.
    InvalidBandData,
};
pub const ResizeError = error{ActiveBindingsPreventResize} || upload_plan.InitError || std.mem.Allocator.Error;

pub const DeviceAtlas = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: DeviceAtlasOptions,

    /// Shared placement/planning state (slots, free ranges, deltas).
    planner: upload_plan.OwnedPlanner,

    // Per-layer prepared atlas pages (one per pool layer, indexed by
    // the pool's immutable layer index).
    prepared: []?PreparedAtlasPage,
    prepared_generation: []u64,
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
        /// Rows populated by the current snapshot (the planner slot may reserve
        /// more rows after a conservative replacement with a smaller atlas).
        info_height: u32 = 0,
        // Prepared records (offsets ABSOLUTE within layer_info_buf).
        path_records: []path_paint_mod.PreparedPathRecord = &.{},
        path_layers: []path_paint_mod.PreparedPathLayer = &.{},
    };

    fn plannerOptions(pool: *const PagePool, options: DeviceAtlasOptions) upload_plan.Options {
        _ = pool;
        return .{
            .max_bindings = options.max_bindings,
            .layer_info_height = options.layer_info_height,
            .max_images = options.max_images,
            // The CPU device samples each image at its native dimensions;
            // planner-side array extents therefore impose no smaller limit.
            // `validateAtlasImages` separately enforces this backend's RGBA8
            // texel contract before planning.
            .max_image_width = std.math.maxInt(u32),
            .max_image_height = std.math.maxInt(u32),
        };
    }

    /// Allocate all fixed-capacity planner and prepared-resource storage. The
    /// borrowed `pool` must outlive this cache and all bindings it issues.
    /// Invalid/unrepresentable options and allocation failure leave no live
    /// partial cache.
    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, options: DeviceAtlasOptions) !DeviceAtlas {
        const max_layers = pool.config().max_layers;

        var planner = try upload_plan.OwnedPlanner.init(allocator, pool, plannerOptions(pool, options));
        errdefer planner.deinit();

        const prepared = try allocator.alloc(?PreparedAtlasPage, max_layers);
        errdefer allocator.free(prepared);
        const gen = try allocator.alloc(u64, max_layers);
        errdefer allocator.free(gen);
        const curve_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(band_words);
        @memset(prepared, null);
        @memset(gen, 0);
        @memset(curve_words, 0);
        @memset(band_words, 0);

        const info_floats = try layerInfoFloatCount(options.layer_info_height);
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
        extras.* = .{};
    }

    /// Reshape the cache. Errors if any binding is active — caller must
    /// release retired bindings first.
    pub fn resize(self: *DeviceAtlas, options: DeviceAtlasOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;

        var new_planner = try upload_plan.OwnedPlanner.init(self.allocator, self.pool, plannerOptions(self.pool, options));
        errdefer new_planner.deinit();

        const info_floats = try layerInfoFloatCount(options.layer_info_height);
        const new_buf = try self.allocator.alloc(f32, info_floats);
        errdefer self.allocator.free(new_buf);
        @memset(new_buf, 0);

        const new_images = try self.allocator.alloc(?*const Image, options.max_images);
        errdefer self.allocator.free(new_images);
        @memset(new_images, null);

        const new_extras = try self.allocator.alloc(BindingExtras, options.max_bindings);
        errdefer self.allocator.free(new_extras);
        for (new_extras) |*e| e.* = .{};

        const old_buf = self.layer_info_buf;
        const old_images = self.image_storage;
        const old_extras = self.extras;

        self.layer_info_buf = new_buf;
        self.layer_info_capacity_rows = options.layer_info_height;
        self.image_storage = new_images;
        self.image_capacity = options.max_images;
        self.extras = new_extras;
        self.planner.deinit();
        self.planner = new_planner;
        self.options = options;

        self.allocator.free(old_buf);
        self.allocator.free(old_images);
        self.allocator.free(old_extras);
    }

    /// Upload one or more atlases into the cache and return one
    /// `Binding` per atlas. Errors if capacity is exceeded; partially
    /// planned bindings are released on failure.
    ///
    /// `scratch` holds transactional staging data for the duration of this
    /// call. No pointer into it is retained. Atlas page/record data is prepared
    /// into cache-owned storage, but image values and texels remain borrowed as
    /// described by the module lifetime contract. On failure, every binding
    /// planned by this call is released; entries already written to
    /// `out_bindings` must not be used.
    pub fn upload(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
        out_bindings: []Binding,
    ) UploadError!void {
        if (atlases.len != out_bindings.len) return error.BindingOutputLengthMismatch;
        const binding_count = std.math.cast(u32, atlases.len) orelse return error.ActiveBindingCountOverflow;
        const next_active = std.math.add(u32, self.active_bindings, binding_count) catch return error.ActiveBindingCountOverflow;
        if (next_active > self.options.max_bindings) return error.NoFreeBinding;

        var planned: usize = 0;
        errdefer self.planner.invalidateUploads();
        errdefer for (out_bindings[0..planned]) |b| {
            self.releaseDeviceState(b);
            _ = self.planner.release(b);
        };

        for (atlases, 0..) |atlas, i| {
            try validateAtlasImages(atlas);
            const plan = try self.planner.plan(atlas);
            out_bindings[i] = plan.binding;
            planned = i + 1;
            try self.applyPlan(scratch, atlas, plan);
        }
        self.active_bindings = next_active;
    }

    /// Incrementally update `prev_binding`'s live slot with `atlas`'s current
    /// state. Exact snapshots and direct append-only children reuse unchanged
    /// prepared pages and side data; branches, skipped descendants, and
    /// unrelated snapshots conservatively replace side data. Any resulting
    /// side data must fit the row/image capacity reserved by the original
    /// binding. On error, the previously prepared device state remains usable.
    pub fn uploadDelta(
        self: *DeviceAtlas,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        try validateAtlasImages(atlas);
        if (prev_binding.pool != self.pool) return error.UnknownPool;
        if (!self.isBindingLive(prev_binding)) return error.UnknownBinding;
        const plan = try self.planner.planDelta(prev_binding, atlas);
        errdefer self.planner.invalidateUploads();
        try self.applyPlan(scratch, atlas, plan);
        return plan.binding;
    }

    /// Release a binding's storage. Idempotent: releasing the same
    /// binding twice is a no-op after the first.
    pub fn release(self: *DeviceAtlas, binding: Binding) void {
        if (!self.isBindingLive(binding)) return;
        self.releaseDeviceState(binding);
        if (self.planner.release(binding) and self.active_bindings > 0) self.active_bindings -= 1;
    }

    /// Slice into the cache's persistent storage describing one live
    /// binding. `layer_info_data` is the slot's window into the shared
    /// buffer (row 0 of the slice is the slot's first row); `info_row_base`
    /// is where this slot sits in the global info_y space and is the value
    /// emit added to `Instance.info_y`. Path records' `texel_offset` is
    /// already slot-relative (matches `layer_info_data`). Returned slices are
    /// borrowed from the cache and remain valid only until that binding is
    /// released, updated, resized, or the cache is deinitialized.
    pub fn snapshotFor(self: *const DeviceAtlas, binding: Binding) ?Snapshot {
        const slot_index = self.findSlot(binding) orelse return null;
        const slot = &self.planner.bindings[slot_index];
        const extras = &self.extras[slot_index];
        const dst_start: usize = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
        const dst_floats: usize = @as(usize, extras.info_height) * INFO_WIDTH * 4;
        return .{
            .layer_info_data = self.layer_info_buf[dst_start..][0..dst_floats],
            .layer_info_width = self.layer_info_width,
            .info_row_base = slot.info_row_base,
            .info_height = extras.info_height,
            .path_records = extras.path_records,
            .path_layers = extras.path_layers,
        };
    }

    pub const Snapshot = struct {
        layer_info_data: []const f32,
        layer_info_width: u32,
        info_row_base: u32,
        info_height: u32,
        path_records: []path_paint_mod.PreparedPathRecord,
        path_layers: []path_paint_mod.PreparedPathLayer,
    };

    /// Whether the complete binding identity names an active slot in this
    /// cache. Checking offsets as well as the generation rejects forged and
    /// cross-cache bindings that happen to reuse a local generation number.
    pub fn isBindingLive(self: *const DeviceAtlas, binding: Binding) bool {
        return self.findSlot(binding) != null;
    }

    /// Borrow the prepared page for one pool layer, or null when that layer has
    /// not been uploaded. The pointer is invalidated by a later upload/delta
    /// touching the layer, resize, or deinit.
    pub fn page(self: *const DeviceAtlas, layer: u32) ?*const PreparedAtlasPage {
        if (layer >= self.prepared.len) return null;
        if (self.prepared[layer]) |*p| return p;
        return null;
    }

    // ── Internal ──

    fn findSlotByGeneration(self: *const DeviceAtlas, generation: u64) ?usize {
        for (self.planner.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return i;
        }
        return null;
    }

    fn findSlot(self: *const DeviceAtlas, binding: Binding) ?usize {
        if (binding.pool != self.pool or binding.source_id != self.planner.planner.source_id) return null;
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return null;
        const slot = &self.planner.bindings[slot_index];
        if (binding.info_row_base != slot.info_row_base or
            binding.image_layer_base != slot.image_layer_base)
        {
            return null;
        }
        return slot_index;
    }

    fn releaseDeviceState(self: *DeviceAtlas, binding: Binding) void {
        const slot_index = self.findSlot(binding) orelse return;
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
    fn applyPlan(self: *DeviceAtlas, scratch: std.mem.Allocator, atlas: *const Atlas, plan: upload_plan.PlannedUpload) UploadError!void {
        const slot_index = self.findSlot(plan.binding) orelse return error.UnknownBinding;
        const slot = &self.planner.bindings[slot_index];
        const extras = &self.extras[slot_index];

        const StagedPage = struct {
            layer: u32,
            page: PreparedAtlasPage,
            generation: u64,
            curve_words: u32,
            band_words: u32,
        };
        var staged_pages: std.ArrayList(StagedPage) = .empty;
        defer staged_pages.deinit(scratch);
        var pages_committed = false;
        defer if (!pages_committed) {
            for (staged_pages.items) |*staged| staged.page.deinit(self.allocator);
        };

        // Reconstruct stale device pages exclusively from the backend-neutral
        // upload regions. `AtlasPage` storage is opaque even to this package;
        // the software renderer follows the same copy contract as a GPU host.
        const PendingPage = struct {
            layer: u32,
            generation: u64,
            curve_words: u32,
            band_words: u32,
            curve_data: []u16,
            band_data: []u16,
            extends_previous: bool,
        };
        var pending_pages: std.ArrayList(PendingPage) = .empty;
        defer {
            for (pending_pages.items) |pending| {
                if (pending.curve_data.len > 0) self.allocator.free(pending.curve_data);
                if (pending.band_data.len > 0) self.allocator.free(pending.band_data);
            }
            pending_pages.deinit(scratch);
        }
        const pending_by_layer = try scratch.alloc(usize, self.prepared.len);
        defer scratch.free(pending_by_layer);
        @memset(pending_by_layer, std.math.maxInt(usize));

        for (plan.regions) |region| switch (region.target) {
            .curve, .band => {
                const layer: usize = region.layer;
                if (layer >= self.prepared.len) return error.PageNotInPool;
                if (pending_by_layer[layer] != std.math.maxInt(usize)) continue;

                const generation = self.planner.generation[layer];
                const curve_words = self.planner.curve_words[layer];
                const band_words = self.planner.band_words[layer];
                const curve_data = try self.allocator.alloc(u16, curve_words);
                const band_data = self.allocator.alloc(u16, band_words) catch |err| {
                    self.allocator.free(curve_data);
                    return err;
                };

                var extends_previous = false;
                if (self.prepared[layer]) |*previous| {
                    extends_previous = self.prepared_generation[layer] == generation and
                        previous.curve_data.len <= curve_data.len and
                        previous.band_data.len <= band_data.len;
                    if (extends_previous) {
                        @memcpy(curve_data[0..previous.curve_data.len], previous.curve_data);
                        @memcpy(band_data[0..previous.band_data.len], previous.band_data);
                        @memset(curve_data[previous.curve_data.len..], 0);
                        @memset(band_data[previous.band_data.len..], 0);
                    }
                }
                if (!extends_previous) {
                    @memset(curve_data, 0);
                    @memset(band_data, 0);
                }

                pending_pages.append(scratch, .{
                    .layer = region.layer,
                    .generation = generation,
                    .curve_words = curve_words,
                    .band_words = band_words,
                    .curve_data = curve_data,
                    .band_data = band_data,
                    .extends_previous = extends_previous,
                }) catch |err| {
                    self.allocator.free(curve_data);
                    self.allocator.free(band_data);
                    return err;
                };
                pending_by_layer[layer] = pending_pages.items.len - 1;
            },
            .layer_info, .image => {},
        };

        for (plan.regions) |region| switch (region.target) {
            .curve, .band => {
                if (region.layer >= pending_by_layer.len) return error.PageNotInPool;
                const pending_index = pending_by_layer[region.layer];
                if (pending_index == std.math.maxInt(usize)) return error.InvalidUploadRegion;
                const pending = &pending_pages.items[pending_index];
                switch (region.target) {
                    .curve => try applyWordRegion(pending.curve_data, region, upload_plan.CURVE_TEX_WIDTH, 4),
                    .band => try applyWordRegion(pending.band_data, region, upload_plan.BAND_TEX_WIDTH, 2),
                    else => unreachable,
                }
            },
            .layer_info, .image => {},
        };

        for (pending_pages.items) |*pending| {
            const view = PageView{
                .curve_data = pending.curve_data,
                .band_data = pending.band_data,
                .curve_width = upload_plan.CURVE_TEX_WIDTH,
                .curve_height = @intCast((pending.curve_words + CURVE_WORDS_PER_ROW - 1) / CURVE_WORDS_PER_ROW),
                .band_width = upload_plan.BAND_TEX_WIDTH,
                .band_height = @intCast((pending.band_words + BAND_WORDS_PER_ROW - 1) / BAND_WORDS_PER_ROW),
            };
            // The owned-view constructors consume both slices even on error.
            pending.curve_data = &.{};
            pending.band_data = &.{};
            var prepared_page = (if (pending.extends_previous)
                PreparedAtlasPage.initExtendedFromOwnedView(self.allocator, &self.prepared[pending.layer].?, view)
            else
                PreparedAtlasPage.initFromOwnedView(self.allocator, view)) catch |err| switch (err) {
                error.InvalidBandData => return error.InvalidUploadRegion,
                error.OutOfMemory => return error.OutOfMemory,
            };
            staged_pages.append(scratch, .{
                .layer = pending.layer,
                .page = prepared_page,
                .generation = pending.generation,
                .curve_words = pending.curve_words,
                .band_words = pending.band_words,
            }) catch |err| {
                prepared_page.deinit(self.allocator);
                return err;
            };
        }

        // Build the binding's next layer-info slab in scratch storage. Region
        // validation happens before any copy so malformed dimensions cannot
        // escape into unchecked pointer arithmetic.
        const slot_floats = std.math.mul(usize, @as(usize, slot.info_height), @as(usize, INFO_WIDTH) * 4) catch
            return error.InvalidUploadRegion;
        var staged_info: []f32 = &.{};
        if (slot_floats > 0) {
            staged_info = try scratch.alloc(f32, slot_floats);
            const current_start = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
            @memcpy(staged_info, self.layer_info_buf[current_start..][0..slot_floats]);
        }
        defer if (slot_floats > 0) scratch.free(staged_info);
        for (plan.regions) |region| switch (region.target) {
            .curve, .band => {},
            .layer_info => {
                const row_end = std.math.add(u32, region.row_base, region.height) catch return error.InvalidUploadRegion;
                const col_end = std.math.add(u32, region.col_base, region.width) catch return error.InvalidUploadRegion;
                const slot_row_end = std.math.add(u32, slot.info_row_base, slot.info_height) catch return error.InvalidUploadRegion;
                if (region.row_base < slot.info_row_base or
                    row_end > slot_row_end or
                    col_end > INFO_WIDTH or
                    @intFromPtr(region.src.ptr) % @alignOf(f32) != 0)
                {
                    return error.InvalidUploadRegion;
                }
                const src_floats = std.math.mul(usize, @as(usize, region.width) * 4, region.height) catch
                    return error.InvalidUploadRegion;
                const src_bytes = std.math.mul(usize, src_floats, @sizeOf(f32)) catch
                    return error.InvalidUploadRegion;
                if (region.src.len < src_bytes) return error.InvalidUploadRegion;
                const src = std.mem.bytesAsSlice(f32, @as([]align(4) const u8, @alignCast(region.src)));
                var row: u32 = 0;
                while (row < region.height) : (row += 1) {
                    const local_row = region.row_base - slot.info_row_base + row;
                    const dst_base = (@as(usize, local_row) * INFO_WIDTH + region.col_base) * 4;
                    const src_base = @as(usize, row) * region.width * 4;
                    @memcpy(
                        staged_info[dst_base..][0 .. @as(usize, region.width) * 4],
                        src[src_base..][0 .. @as(usize, region.width) * 4],
                    );
                }
            },
            .image => {},
        };

        const staged_images = try scratch.alloc(?*const Image, slot.image_count);
        defer scratch.free(staged_images);
        @memset(staged_images, null);
        var staged_extras = BindingExtras{};
        staged_extras.info_height = atlas.layer_info_height;
        var extras_committed = false;
        defer if (!extras_committed) self.freeExtras(&staged_extras);

        if (atlas.layer_info_data != null) {
            // Re-patch image-paint records for this device (direct image
            // sampling: uv scale 1.0; layer = planner's absolute layer).
            if (atlas.paint_records) |records| {
                for (records) |rec| {
                    const image = rec.image orelse continue;
                    const local_layer = rec.image_layer;
                    if (local_layer >= staged_images.len) return error.InvalidUploadRegion;
                    if (rec.first_image_use) {
                        if (staged_images[local_layer] != null) return error.InvalidUploadRegion;
                        staged_images[local_layer] = image;
                    } else if (staged_images[local_layer] != image) {
                        return error.InvalidUploadRegion;
                    }
                    const abs_layer = slot.image_layer_base + local_layer;
                    patchImagePaintRecord(staged_info, 0, rec.texel_offset, abs_layer);
                }
            }

            const staged_layer_info = staged_info[0 .. @as(usize, atlas.layer_info_height) * INFO_WIDTH * 4];
            const prepared_records = if (atlas.paint_records) |records|
                try path_paint_mod.preparePathLayerInfoRecords(
                    self.allocator,
                    staged_layer_info,
                    INFO_WIDTH,
                    atlas.layer_info_height,
                    records,
                )
            else
                try path_paint_mod.preparePathLayerInfoWithoutPaint(
                    self.allocator,
                    staged_layer_info,
                    INFO_WIDTH,
                    atlas.layer_info_height,
                );
            staged_extras.path_records = prepared_records.records;
            staged_extras.path_layers = prepared_records.layers;
        }

        // Commit only after every allocation and validation succeeded.
        for (staged_pages.items) |*staged| {
            if (self.prepared[staged.layer]) |*previous| previous.deinit(self.allocator);
            self.prepared[staged.layer] = staged.page;
            self.prepared_generation[staged.layer] = staged.generation;
            self.prepared_curve_words[staged.layer] = staged.curve_words;
            self.prepared_band_words[staged.layer] = staged.band_words;
        }
        pages_committed = true;

        if (slot_floats > 0) {
            const dst_start = @as(usize, slot.info_row_base) * INFO_WIDTH * 4;
            @memcpy(self.layer_info_buf[dst_start..][0..slot_floats], staged_info);
        }
        if (slot.image_count > 0) {
            @memcpy(self.image_storage[slot.image_layer_base..][0..slot.image_count], staged_images);
        }
        self.freeExtras(extras);
        extras.* = staged_extras;
        extras_committed = true;
    }
};

fn applyWordRegion(
    destination: []u16,
    region: upload_plan.Region,
    texture_width: u32,
    words_per_texel: u32,
) UploadError!void {
    if (region.width == 0 or region.height == 0) return error.InvalidUploadRegion;
    const col_end = std.math.add(u32, region.col_base, region.width) catch return error.InvalidUploadRegion;
    if (col_end > texture_width or @intFromPtr(region.src.ptr) % @alignOf(u16) != 0) return error.InvalidUploadRegion;

    const row_words = std.math.mul(usize, region.width, words_per_texel) catch return error.InvalidUploadRegion;
    const source_words = std.math.mul(usize, row_words, region.height) catch return error.InvalidUploadRegion;
    const source_bytes = std.math.mul(usize, source_words, @sizeOf(u16)) catch return error.InvalidUploadRegion;
    if (region.src.len != source_bytes) return error.InvalidUploadRegion;
    const source = std.mem.bytesAsSlice(u16, @as([]align(2) const u8, @alignCast(region.src)));

    var row: u32 = 0;
    while (row < region.height) : (row += 1) {
        const texture_row = std.math.add(u32, region.row_base, row) catch return error.InvalidUploadRegion;
        const texel_base = std.math.add(
            usize,
            std.math.mul(usize, texture_row, texture_width) catch return error.InvalidUploadRegion,
            region.col_base,
        ) catch return error.InvalidUploadRegion;
        const destination_base = std.math.mul(usize, texel_base, words_per_texel) catch return error.InvalidUploadRegion;
        const destination_end = std.math.add(usize, destination_base, row_words) catch return error.InvalidUploadRegion;
        if (destination_end > destination.len) return error.InvalidUploadRegion;
        const source_base = @as(usize, row) * row_words;
        @memcpy(destination[destination_base..destination_end], source[source_base..][0..row_words]);
    }
}

const PageView = struct {
    curve_data: []const u16,
    band_data: []const u16,
    curve_width: u32,
    curve_height: u32,
    band_width: u32,
    band_height: u32,
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

    var unexpected_binding: [1]Binding = undefined;
    try testing.expectError(error.BindingOutputLengthMismatch, cache.upload(testing.allocator, &.{}, &unexpected_binding));
    try testing.expectEqual(@as(u32, 0), cache.active_bindings);
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

    // A forged binding with a valid generation must not release the slot.
    var forged = b1[0];
    forged.info_row_base += 1;
    cache.release(forged);
    try testing.expectEqual(@as(u32, 2), cache.active_bindings);
    try testing.expect(cache.isBindingLive(b1[0]));

    // A rejected resize leaves every allocation and option untouched.
    const old_options = cache.options;
    const old_info_ptr = cache.layer_info_buf.ptr;
    const old_images_ptr = cache.image_storage.ptr;
    try testing.expectError(error.ActiveBindingsPreventResize, cache.resize(.{
        .max_bindings = 8,
        .layer_info_height = 16,
        .max_images = 4,
    }));
    try testing.expectEqual(old_options, cache.options);
    try testing.expectEqual(old_info_ptr, cache.layer_info_buf.ptr);
    try testing.expectEqual(old_images_ptr, cache.image_storage.ptr);

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

    var other_cache = try DeviceAtlas.init(testing.allocator, pool, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer other_cache.deinit();
    var other_binding: [1]Binding = undefined;
    try other_cache.upload(testing.allocator, &.{&atlas}, &other_binding);
    try testing.expect(binding[0].source_id != other_binding[0].source_id);
    try testing.expect(!cache.isBindingLive(other_binding[0]));
    try testing.expect(other_cache.isBindingLive(other_binding[0]));

    cache.release(binding[0]);

    try testing.expectError(error.UnknownBinding, cache.uploadDelta(testing.allocator, binding[0], &atlas));
}

test "uploadDelta accepts a different atlas on the same pool" {
    // Per the public uploadDelta contract, a different atlas on the same pool
    // is permitted — the cache's
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

test "sibling snapshots prepare every self-described block on their shared page" {
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    var font = try font_mod.Font.init(@import("assets").noto_sans_regular);
    const gid = try font.glyphIndex('A');
    var curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves.deinit();

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const root_key = record_key_mod.unhintedGlyph(0, 1);
    const a_key = record_key_mod.unhintedGlyph(0, 2);
    const b_key = record_key_mod.unhintedGlyph(0, 3);
    var root_atlas = try Atlas.from(testing.allocator, pool, &.{.{ .key = root_key, .curves = curves }});
    defer root_atlas.deinit();
    var child_a = try root_atlas.extend(testing.allocator, &.{.{ .key = a_key, .curves = curves }});
    defer child_a.deinit();
    // Branch B publishes after A on the same physical page. Planning A below
    // therefore uploads bytes through B's tail even though A cannot look up B.
    var child_b = try root_atlas.extend(testing.allocator, &.{.{ .key = b_key, .curves = curves }});
    defer child_b.deinit();

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{
        .max_bindings = 2,
        .layer_info_height = 1,
        .max_images = 0,
    });
    defer cache.deinit();
    var a_binding: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&child_a}, &a_binding);

    const page_index = for (cache.prepared, 0..) |page, index| {
        if (page != null) break index;
    } else return error.TestUnexpectedResult;
    const prepared_before = &cache.prepared[page_index].?;
    const b_record = child_b.lookupRecord(b_key).?;
    const b_base = @as(usize, b_record.bands.glyph_y) * @as(usize, prepared_before.band_width) +
        @as(usize, b_record.bands.glyph_x);
    for (0..b_record.bands.h_band_count) |band_index| {
        const header = texture_mod.readBandTexelLinear(prepared_before, b_base + band_index);
        const first = b_base + @as(usize, header[1]);
        for (prepared_before.axis_curves[first..][0..@as(usize, header[0])]) |curve| try testing.expect(curve.valid);
    }
    for (0..b_record.bands.v_band_count) |band_index| {
        const header = texture_mod.readBandTexelLinear(prepared_before, b_base + b_record.bands.h_band_count + band_index);
        const first = b_base + @as(usize, header[1]);
        for (prepared_before.axis_curves[first..][0..@as(usize, header[0])]) |curve| try testing.expect(curve.valid);
    }

    const curve_ptr = prepared_before.curve_data.ptr;
    const h_cold_ptr = prepared_before.h_cold_curves.ptr;
    const v_cold_ptr = prepared_before.v_cold_curves.ptr;
    const resident_band_words = cache.prepared_band_words[page_index];
    var b_binding: [1]Binding = undefined;
    try cache.upload(testing.allocator, &.{&child_b}, &b_binding);

    // The planner had already reached the shared page's physical watermark,
    // so B emits no page region and preparation neither replaces the page nor
    // duplicates any cold coefficient records.
    const prepared_after = &cache.prepared[page_index].?;
    try testing.expectEqual(curve_ptr, prepared_after.curve_data.ptr);
    try testing.expectEqual(h_cold_ptr, prepared_after.h_cold_curves.ptr);
    try testing.expectEqual(v_cold_ptr, prepared_after.v_cold_curves.ptr);
    try testing.expectEqual(resident_band_words, cache.prepared_band_words[page_index]);
}

test "upload rejects malformed layer-info transactionally" {
    const record_key_mod = @import("snail").record_key;
    const font_mod = @import("snail").font;

    var font = try font_mod.Font.init(@import("assets").noto_sans_regular);
    const gid = try font.glyphIndex('A');
    var curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer curves.deinit();
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    var atlas = try Atlas.from(testing.allocator, pool, &.{.{
        .key = record_key_mod.unhintedGlyph(0, gid),
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas.deinit();
    atlas.layer_info_data.?[0] = std.math.nan(f32);

    var cache = try DeviceAtlas.init(testing.allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = 2,
        .max_images = 0,
    });
    defer cache.deinit();
    var binding: [1]Binding = undefined;
    try testing.expectError(error.InvalidLayerInfo, cache.upload(testing.allocator, &.{&atlas}, &binding));
    try testing.expectEqual(@as(u32, 0), cache.active_bindings);
    try testing.expect(!cache.isBindingLive(binding[0]));
}
