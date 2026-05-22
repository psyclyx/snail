const std = @import("std");

const paint_mod = @import("../paint.zig");
const paint_records = @import("../paint_records.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const band_tex = @import("../render/format/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const hint_context = @import("hint_context.zig");
const resource_key_mod = @import("../resource_key.zig");
const text_hint = @import("../render/format/text_hint.zig");
const atlas_mod = @import("atlas.zig");
const config_mod = @import("config.zig");
const shape_mod = @import("shape.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");
const view_mod = @import("view.zig");
const resource_view_mod = @import("../resources/view.zig");

const PreparedHintLayerInfoUpload = resource_view_mod.PreparedHintLayerInfoUpload;

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const FaceIndex = config_mod.FaceIndex;
const FaceView = view_mod.FaceView;
const HintedGlyphValue = hint_context.HintedGlyphValue;
const Paint = paint_mod.Paint;
const PaintImageRecord = atlas_curve_mod.CurveAtlas.PaintImageRecord;
const PreparedHintRun = hint_context.PreparedHintRun;
const ResourceKey = resource_key_mod.ResourceKey;
const ShapedText = types_mod.ShapedText;
const SyntheticStyle = config_mod.SyntheticStyle;
const TextAppend = types_mod.TextAppend;
const TextAppendResult = types_mod.TextAppendResult;
const TextAtlas = atlas_mod.TextAtlas;
const TextPlacement = types_mod.TextPlacement;
const TextResourceKeys = resource_key_mod.TextResourceKeys;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;
const glyphInstanceBudget = shape_mod.glyphInstanceBudget;
const glyphPlacementTransform = shape_mod.glyphPlacementTransform;
const scaleAdvance = shape_mod.scaleAdvance;
const shapedGlyphAvailable = shape_mod.shapedGlyphAvailable;

// ── TextBlob ──
//
// An immutable, drawable text fragment. Always owned by a
// `TextBlobBundle`: the blob struct itself is heap-allocated by the
// bundle's gpa for pointer stability, and its `glyphs` /
// `paint_layer_info_data` / `paint_image_records` slices live in the
// bundle's arena. Blob references stay valid until the bundle is reset
// or deinit'd; both release every blob in one shot.

pub const TextBlob = struct {
    /// Owning bundle. Carries the atlas binding for identity checks and
    /// supplies the storage arena. Stable for the lifetime of the blob.
    bundle: *const TextBlobBundle,
    /// Per-blob key passed at `finish` time. Used by `resourceKeys` to
    /// derive related slots (e.g. `text_paint`).
    resource_key: ResourceKey,
    glyphs: []Glyph,
    paint_layer_info_data: ?[]f32 = null,
    paint_layer_info_width: u32 = 0,
    paint_layer_info_height: u32 = 0,
    paint_image_records: ?[]?PaintImageRecord = null,
    /// Upper bound on GPU vertex-output instances this blob will emit
    /// (counts COLR layer fan-out and synthetic-bold duplication). Used
    /// to size scratch buffers in `DrawList.estimate`.
    gpu_instance_budget: usize,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        embolden: f32,
        color: [4]f32,
        paint_record_index: ?u32 = null,
        hint_record_texel: ?u32 = null,
        hint_bbox: BBox = emptyBBox(),
    };

    pub const LayerInfoLoc = struct { x: u16, y: u16 };

    pub fn atlas(self: *const TextBlob) *const TextAtlas {
        return self.bundle.atlas;
    }

    pub fn atlasIdentity(self: *const TextBlob) u64 {
        return self.bundle.atlas_identity;
    }

    pub fn glyphCount(self: *const TextBlob) usize {
        return self.glyphs.len;
    }

    pub fn validateExact(self: *const TextBlob) !void {
        if (self.bundle.atlas.snapshotIdentity() != self.bundle.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn validate(self: *const TextBlob) !void {
        try self.validateExact();
    }

    pub fn hasPaintRecords(self: *const TextBlob) bool {
        return self.paint_layer_info_data != null;
    }

    pub fn resourceKeys(self: *const TextBlob, atlas_key: ResourceKey, blob_key: ResourceKey) TextResourceKeys {
        // The hint key is derived from the *atlas* key, not the blob key:
        // every blob produced from the same bundle (which is bound to one
        // atlas) shares the same hint pool, and we want them to dedupe to
        // a single manifest entry. `atlas_key` is a stable shared identity
        // across all blobs in a bundle.
        return .{
            .atlas = atlas_key,
            .paint = if (self.hasPaintRecords()) resource_key_mod.derived(blob_key, "text_paint") else null,
            .hint = if (self.bundle.hasHintRecords()) resource_key_mod.derived(atlas_key, "text_hint") else null,
        };
    }

    pub fn paintRecordLoc(self: *const TextBlob, record_index: u32) LayerInfoLoc {
        const texel_offset = record_index * paint_records.texels_per_record;
        return self.layerInfoLoc(texel_offset);
    }

    pub fn hintRecordLoc(self: *const TextBlob, texel_offset: u32) LayerInfoLoc {
        return self.layerInfoLoc(texel_offset);
    }

    fn layerInfoLoc(self: *const TextBlob, texel_offset: u32) LayerInfoLoc {
        return .{
            .x = @intCast(texel_offset % self.paint_layer_info_width),
            .y = @intCast(texel_offset / self.paint_layer_info_width),
        };
    }
};

// ── TextBlobBundle ──
//
// Arena-backed container for many `TextBlob`s sharing a `TextAtlas`.
// The bundle owns:
//   - The blob structs themselves (gpa-allocated, accessed via
//     stable `*TextBlob` pointers in `blobs`).
//   - All blob content (glyph slices, paint texel buffers, image
//     records), allocated from the bundle's arena.
//   - The single in-flight `PendingBlob` during streaming construction.
//
// Lifetime: `reset()` and `deinit()` invalidate every blob the bundle
// has produced. The bundle borrows the `TextAtlas` snapshot pointer
// (must outlive the bundle).
//
// In-flight invariant: at most one `BlobInProgress` may exist at a
// time. `startBlob` returns `error.BlobInFlight` while one is open.
// Terminate with `finish(key)` (commits the blob) or `abort()`
// (discards). Use `errdefer bip.abort()` on error paths.
//
// Freeze: after `freeze()`, builder operations return
// `error.BundleFrozen`. `reset()` clears the freeze.

pub const TextBlobBundle = struct {
    gpa: Allocator,
    arena: std.heap.ArenaAllocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    blobs: std.ArrayListUnmanaged(*TextBlob) = .empty,
    pending: PendingBlob = .{},
    in_flight: bool = false,
    frozen: bool = false,
    /// Monotonic counter incremented on `reset` and `deinit`. C-side
    /// handles capture this at construction and compare on dereference
    /// to detect use-after-reset.
    generation: u32 = 0,

    // ── Shared hint pool ──
    //
    // Hint records are bundle-scoped, not blob-scoped: every blob whose
    // hinted glyphs reference the same `*const HintedGlyphValue` (same
    // glyph_id at the same PPEM, same hint context) shares one encoded
    // entry. The pool is built incrementally as blobs are finished.
    //
    // `hint_layer_info_data` is materialised lazily into the arena once
    // the bundle is frozen (or once anyone calls `hintLayerInfoUpload`)
    // and is invalidated by `reset`.
    //
    // Each `TextBlob.Glyph.hint_record_texel` is a *pool index* into
    // `hint_pool` rather than a texel offset; the texel offset comes
    // from `hint_pool_texel_offsets`, computed at materialisation time.
    hint_pool: std.ArrayListUnmanaged(PendingHintRecord) = .empty,
    hint_pool_refs: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    hint_pool_texel_offsets: ?[]u32 = null,
    hint_layer_info_data: ?[]f32 = null,
    hint_layer_info_width: u32 = 0,
    hint_layer_info_height: u32 = 0,

    pub fn init(gpa: Allocator, atlas: *const TextAtlas) TextBlobBundle {
        return .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .atlas = atlas,
            .atlas_identity = atlas.snapshotIdentity(),
        };
    }

    pub fn deinit(self: *TextBlobBundle) void {
        self.pending.deinit(self.gpa);
        for (self.blobs.items) |blob| self.gpa.destroy(blob);
        self.blobs.deinit(self.gpa);
        self.clearHintPool();
        self.hint_pool.deinit(self.gpa);
        self.hint_pool_refs.deinit(self.gpa);
        if (self.hint_pool_texel_offsets) |buf| self.gpa.free(buf);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Drop every blob and pending state. Retains arena and blob-list
    /// capacity. Invalidates every `*const TextBlob` previously
    /// returned. Debug-asserts no blob is in flight.
    pub fn reset(self: *TextBlobBundle) void {
        std.debug.assert(!self.in_flight);
        self.pending.reset(self.gpa);
        for (self.blobs.items) |blob| self.gpa.destroy(blob);
        self.blobs.clearRetainingCapacity();
        self.clearHintPool();
        self.hint_pool.clearRetainingCapacity();
        self.hint_pool_refs.clearRetainingCapacity();
        if (self.hint_pool_texel_offsets) |buf| self.gpa.free(buf);
        self.hint_pool_texel_offsets = null;
        self.hint_layer_info_data = null;
        self.hint_layer_info_width = 0;
        self.hint_layer_info_height = 0;
        _ = self.arena.reset(.retain_capacity);
        self.frozen = false;
        self.generation +%= 1;
    }

    fn clearHintPool(self: *TextBlobBundle) void {
        for (self.hint_pool.items) |entry| self.gpa.free(entry.curve_deltas_f16);
    }

    /// Intern a hinted glyph value into the bundle's pool. Returns the
    /// pool index. Subsequent calls with the same `intern_key` (typically
    /// `@intFromPtr(value)`) return the same index. Invalidates any
    /// previously-materialised hint layer info data — call `materialiseHintLayerInfo`
    /// (or `freeze`) before uploading after additions.
    fn internHintRecord(
        self: *TextBlobBundle,
        intern_key: usize,
        record: text_hint.GlyphRecord,
        curve_deltas_f16: []const u16,
    ) !u32 {
        if (self.hint_pool_refs.get(intern_key)) |index| return index;
        const index: u32 = @intCast(self.hint_pool.items.len);
        const deltas = try self.gpa.dupe(u16, curve_deltas_f16);
        errdefer self.gpa.free(deltas);
        try self.hint_pool.append(self.gpa, .{
            .record = record,
            .curve_deltas_f16 = deltas,
        });
        errdefer _ = self.hint_pool.pop();
        try self.hint_pool_refs.put(self.gpa, intern_key, index);
        self.invalidateHintMaterialisation();
        return index;
    }

    fn invalidateHintMaterialisation(self: *TextBlobBundle) void {
        if (self.hint_pool_texel_offsets) |buf| self.gpa.free(buf);
        self.hint_pool_texel_offsets = null;
        self.hint_layer_info_data = null;
        self.hint_layer_info_width = 0;
        self.hint_layer_info_height = 0;
    }

    /// Pack the bundle's hint pool into a single layer-info slab and
    /// compute per-entry texel offsets. Idempotent: returns immediately
    /// once materialised. The slab lives in the bundle's arena; both are
    /// invalidated by `reset` or any subsequent `internHintRecord`.
    pub fn materialiseHintLayerInfo(self: *TextBlobBundle) !void {
        if (self.hint_layer_info_data != null) return;
        if (self.hint_pool.items.len == 0) return;

        const offsets = try self.gpa.alloc(u32, self.hint_pool.items.len);
        errdefer self.gpa.free(offsets);

        var texel_cursor: u32 = 0;
        for (self.hint_pool.items, offsets) |record, *offset| {
            offset.* = texel_cursor;
            texel_cursor += text_hint.recordTexelCount(record.record.curve_count);
        }
        const texel_count = texel_cursor;
        const width = text_hint.infoWidth(texel_count);
        const height = @max(@as(u32, 1), (texel_count + width - 1) / width);
        const data = try self.arena.allocator().alloc(f32, @as(usize, width) * @as(usize, height) * 4);
        @memset(data, 0);

        for (self.hint_pool.items, offsets) |record, texel_offset| {
            try text_hint.writeGlyphRecord(data, width, texel_offset, record.record, record.curve_deltas_f16);
        }

        self.hint_pool_texel_offsets = offsets;
        self.hint_layer_info_data = data;
        self.hint_layer_info_width = width;
        self.hint_layer_info_height = height;
    }

    /// Returns the bundle's shared-hint upload payload. May be empty
    /// (no hinted glyphs in the bundle). Triggers materialisation if not
    /// already done.
    pub fn hintLayerInfoUpload(self: *TextBlobBundle) !PreparedHintLayerInfoUpload {
        try self.materialiseHintLayerInfo();
        return .{
            .data = self.hint_layer_info_data,
            .width = self.hint_layer_info_width,
            .height = self.hint_layer_info_height,
        };
    }

    /// True if this bundle has any hinted glyphs (and therefore needs
    /// a `text_hint` resource binding).
    pub fn hasHintRecords(self: *const TextBlobBundle) bool {
        return self.hint_pool.items.len > 0;
    }

    /// Texel offset of a pool entry, in the bundle's hint slab. Must be
    /// called after `materialiseHintLayerInfo`. Used by the renderer to
    /// resolve a `Glyph.hint_record_texel` (which is a pool index) to a
    /// position in the shared slab.
    pub fn hintPoolTexelOffset(self: *const TextBlobBundle, pool_index: u32) u32 {
        const offsets = self.hint_pool_texel_offsets orelse return 0;
        if (pool_index >= offsets.len) return 0;
        return offsets[pool_index];
    }

    /// Streaming construction. Returns a thin handle that must terminate
    /// with `finish` or `abort`. Use `errdefer bip.abort()` on error
    /// paths.
    pub fn startBlob(self: *TextBlobBundle) !BlobInProgress {
        if (self.frozen) return error.BundleFrozen;
        if (self.in_flight) return error.BlobInFlight;
        self.in_flight = true;
        return .{ .bundle = self };
    }

    /// Bulk construction. If `results` is non-null it must have length
    /// `appends.len`; each entry receives the per-append result.
    pub fn buildBlob(
        self: *TextBlobBundle,
        key: ResourceKey,
        appends: []const TextAppend,
        results: ?[]TextAppendResult,
    ) !*const TextBlob {
        if (results) |r| if (r.len != appends.len) return error.InvalidArgument;

        var bip = try self.startBlob();
        errdefer bip.abort();
        for (appends, 0..) |append, i| {
            const result = try bip.append(append);
            if (results) |r| r[i] = result;
        }
        return bip.finish(key);
    }

    /// Migrate every blob in this bundle to `new_atlas`, which must
    /// satisfy `new_atlas.canRebindFrom(self.atlas)` and contain every
    /// glyph referenced by every blob. On error the bundle is unchanged.
    pub fn rebindAtlas(self: *TextBlobBundle, new_atlas: *const TextAtlas) !void {
        if (self.frozen) return error.BundleFrozen;
        if (self.in_flight) return error.BlobInFlight;
        if (!new_atlas.canRebindFrom(self.atlas)) return error.WrongTextAtlasSnapshot;
        for (self.blobs.items) |blob| {
            for (blob.glyphs) |g| {
                if (!new_atlas.hasPreparedGlyph(g.face_index, g.glyph_id)) return error.MissingPreparedGlyph;
            }
        }
        self.atlas = new_atlas;
        self.atlas_identity = new_atlas.snapshotIdentity();
    }

    /// Produce a new bundle-owned blob copied from `src` but bound via
    /// this bundle's atlas. The bundle's `atlas` must equal `new_atlas`
    /// (call `rebindAtlas` first or initialize the bundle with
    /// `new_atlas`). `src` may belong to this or any other bundle.
    pub fn rebound(
        self: *TextBlobBundle,
        key: ResourceKey,
        src: *const TextBlob,
        new_atlas: *const TextAtlas,
    ) !*const TextBlob {
        if (self.frozen) return error.BundleFrozen;
        if (self.in_flight) return error.BlobInFlight;
        if (self.atlas != new_atlas) return error.WrongTextAtlasSnapshot;
        if (!new_atlas.canRebindFrom(src.atlas())) return error.WrongTextAtlasSnapshot;
        for (src.glyphs) |g| {
            if (!new_atlas.hasPreparedGlyph(g.face_index, g.glyph_id)) return error.MissingPreparedGlyph;
        }

        const arena_alloc = self.arena.allocator();
        const glyphs_copy = try arena_alloc.dupe(TextBlob.Glyph, src.glyphs);
        const paint_data_copy = if (src.paint_layer_info_data) |data|
            try arena_alloc.dupe(f32, data)
        else
            null;
        const image_records_copy = if (src.paint_image_records) |records|
            try arena_alloc.dupe(?PaintImageRecord, records)
        else
            null;

        const slot = try self.gpa.create(TextBlob);
        errdefer self.gpa.destroy(slot);
        slot.* = .{
            .bundle = self,
            .resource_key = key,
            .glyphs = glyphs_copy,
            .paint_layer_info_data = paint_data_copy,
            .paint_layer_info_width = src.paint_layer_info_width,
            .paint_layer_info_height = src.paint_layer_info_height,
            .paint_image_records = image_records_copy,
            .gpu_instance_budget = textBlobGpuInstanceBudgetForAtlas(new_atlas, glyphs_copy),
        };
        try self.blobs.append(self.gpa, slot);
        return slot;
    }

    /// Lock the bundle. After freeze, builder operations return
    /// `error.BundleFrozen`. `reset()` clears the freeze.
    pub fn freeze(self: *TextBlobBundle) void {
        self.frozen = true;
    }

    pub fn unfreeze(self: *TextBlobBundle) void {
        self.frozen = false;
    }

    pub fn isFrozen(self: *const TextBlobBundle) bool {
        return self.frozen;
    }

    pub fn blobCount(self: *const TextBlobBundle) usize {
        return self.blobs.items.len;
    }

    pub fn currentGeneration(self: *const TextBlobBundle) u32 {
        return self.generation;
    }
};

/// Thin handle to in-progress blob construction. Must terminate with
/// either `finish(key)` or `abort()`. Use `errdefer bip.abort()` on
/// error paths.
pub const BlobInProgress = struct {
    bundle: *TextBlobBundle,

    pub fn append(self: BlobInProgress, text_append: TextAppend) !TextAppendResult {
        return appendIntoPending(self.bundle, text_append, true);
    }

    pub fn appendHintedGlyph(
        self: BlobInProgress,
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        color: [4]f32,
        record: text_hint.GlyphRecord,
        curve_deltas_f16: []const u16,
    ) !void {
        const expected_deltas = @as(usize, record.curve_count) * text_hint.delta_values_per_curve;
        if (curve_deltas_f16.len != expected_deltas) return error.InvalidHintDeltaCount;

        // Raw record append: no `HintedGlyphValue` pointer to use as an
        // intern key, so push a fresh pool entry. Callers using the cached
        // hint context should prefer `appendHintedGlyphRef` to dedupe.
        const intern_key = @intFromPtr(curve_deltas_f16.ptr);
        const pool_index = try self.bundle.internHintRecord(intern_key, record, curve_deltas_f16);

        try self.bundle.pending.glyphs.append(self.bundle.gpa, .{
            .face_index = face_index,
            .glyph_id = glyph_id,
            .transform = transform,
            .embolden = 0,
            .color = color,
            .hint_record_texel = pool_index,
            .hint_bbox = record.bbox,
        });
        self.bundle.pending.gpu_instance_budget += 1;
    }

    pub fn appendHintedGlyphRef(
        self: BlobInProgress,
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        color: [4]f32,
        value: *const HintedGlyphValue,
    ) !void {
        const attachment = value.attachment orelse return error.EmptyHintedGlyph;
        const intern_key = @intFromPtr(value);
        const pool_index = try self.bundle.internHintRecord(intern_key, attachment.record, attachment.curve_deltas_f16);

        // Faux-bold: passthrough the face's embolden offset so the renderer
        // emits a second hinted copy at `transform.tx + embolden`. The hint
        // program ran on the un-emboldened outline; both copies share the
        // same hinted geometry.
        const face = &self.bundle.atlas.config.faces[face_index];
        const embolden = face.synthetic.embolden;
        try self.bundle.pending.glyphs.append(self.bundle.gpa, .{
            .face_index = face_index,
            .glyph_id = glyph_id,
            .transform = transform,
            .embolden = embolden,
            .color = color,
            .hint_record_texel = pool_index,
            .hint_bbox = value.bbox,
        });
        // Each hinted glyph is one GPU instance; emboldening emits a second
        // copy at draw time so the budget must reserve two.
        self.bundle.pending.gpu_instance_budget += if (embolden != 0) 2 else 1;
    }

    pub fn glyphCount(self: BlobInProgress) usize {
        return self.bundle.pending.glyphs.items.len;
    }

    /// Finalize the in-progress blob. The blob struct lives in
    /// `bundle.gpa` (pointer-stable); its glyph and paint content lives
    /// in the bundle's arena. The returned pointer is valid until the
    /// bundle is reset or deinit'd.
    pub fn finish(self: BlobInProgress, key: ResourceKey) !*const TextBlob {
        std.debug.assert(self.bundle.in_flight);
        const pending = &self.bundle.pending;
        const arena_alloc = self.bundle.arena.allocator();

        const owned_glyphs = try arena_alloc.dupe(TextBlob.Glyph, pending.glyphs.items);
        const paint_info = try finishLayerInfoRecords(pending, self.bundle.gpa, arena_alloc, owned_glyphs);
        const gpu_budget = pending.gpu_instance_budget;

        const slot = try self.bundle.gpa.create(TextBlob);
        errdefer self.bundle.gpa.destroy(slot);
        slot.* = .{
            .bundle = self.bundle,
            .resource_key = key,
            .glyphs = owned_glyphs,
            .paint_layer_info_data = paint_info.data,
            .paint_layer_info_width = paint_info.width,
            .paint_layer_info_height = paint_info.height,
            .paint_image_records = paint_info.image_records,
            .gpu_instance_budget = gpu_budget,
        };
        try self.bundle.blobs.append(self.bundle.gpa, slot);

        pending.reset(self.bundle.gpa);
        self.bundle.in_flight = false;
        return slot;
    }

    /// Discard the in-progress blob. Idempotent and safe to call after
    /// `finish` (no-op in that case).
    pub fn abort(self: BlobInProgress) void {
        if (!self.bundle.in_flight) return;
        self.bundle.pending.reset(self.bundle.gpa);
        self.bundle.in_flight = false;
    }
};

// ── PendingBlob ──
//
// One in-flight blob's accumulators. Backed by gpa-allocated
// ArrayLists so growth doesn't churn the arena. On `finish`, contents
// are duplicated into the bundle's arena and pending state is cleared
// (retaining capacity for the next blob).

const PendingBlob = struct {
    glyphs: std.ArrayListUnmanaged(TextBlob.Glyph) = .empty,
    paint_records: std.ArrayListUnmanaged(PendingPaintRecord) = .empty,
    gpu_instance_budget: usize = 0,

    fn deinit(self: *PendingBlob, gpa: Allocator) void {
        self.glyphs.deinit(gpa);
        self.paint_records.deinit(gpa);
        self.* = undefined;
    }

    fn reset(self: *PendingBlob, gpa: Allocator) void {
        _ = gpa;
        self.glyphs.clearRetainingCapacity();
        self.paint_records.clearRetainingCapacity();
        self.gpu_instance_budget = 0;
    }
};

const PendingPaintRecord = struct {
    band_entry: band_tex.GlyphBandEntry,
    paint: Paint,
};

const PendingHintRecord = struct {
    record: text_hint.GlyphRecord,
    curve_deltas_f16: []u16,
};

const FinishedLayerInfoRecords = struct {
    data: ?[]f32 = null,
    width: u32 = 0,
    height: u32 = 0,
    image_records: ?[]?PaintImageRecord = null,
};

fn finishLayerInfoRecords(
    pending: *PendingBlob,
    gpa: Allocator,
    arena: Allocator,
    glyphs: []TextBlob.Glyph,
) !FinishedLayerInfoRecords {
    _ = gpa;
    _ = glyphs;
    const paint_count = pending.paint_records.items.len;
    if (paint_count == 0) return .{};

    // Hint records live in the bundle's shared pool now; each blob's
    // layer-info slab is paint-records-only.
    const texel_count: u32 = @intCast(paint_count * paint_records.texels_per_record);
    const width = text_hint.infoWidth(texel_count);
    const height = @max(@as(u32, 1), (texel_count + width - 1) / width);
    const data = try arena.alloc(f32, @as(usize, width) * @as(usize, height) * 4);
    @memset(data, 0);

    const image_records = try arena.alloc(?PaintImageRecord, @max(paint_count, 1));
    @memset(image_records, null);
    var has_image_paints = false;

    for (pending.paint_records.items, 0..) |record, i| {
        const texel_offset: u32 = @intCast(i * paint_records.texels_per_record);
        paint_records.write(data, width, texel_offset, record.band_entry, record.paint);
        switch (record.paint) {
            .image => |image_paint| {
                image_records[i] = .{
                    .image = image_paint.image,
                    .texel_offset = texel_offset,
                };
                has_image_paints = true;
            },
            else => {},
        }
    }

    return .{
        .data = data,
        .width = width,
        .height = height,
        .image_records = if (has_image_paints) image_records else null,
    };
}

// ── Append plumbing ──

fn appendIntoPending(
    bundle: *TextBlobBundle,
    append: TextAppend,
    allow_missing: bool,
) !TextAppendResult {
    return switch (append.source) {
        .shaped => |slice| appendShapedSlice(bundle, slice, append.placement, append.fill, allow_missing),
        .hinted => |slice| appendHintedSlice(bundle, slice, append.placement, append.fill),
    };
}

fn appendShapedSlice(
    bundle: *TextBlobBundle,
    slice: []const ShapedText.Glyph,
    placement: TextPlacement,
    fill: Paint,
    allow_missing: bool,
) !TextAppendResult {
    if (slice.len == 0) return .{ .advance = .zero, .missing = false };
    const atlas = bundle.atlas;
    const origin_x = slice[0].x_offset;
    const origin_y = slice[0].y_offset;

    var missing = false;
    var advance = Vec2.zero;
    for (slice) |glyph| {
        advance.x += glyph.x_advance;
        advance.y += glyph.y_advance;
        const fc = &atlas.config.faces[glyph.face_index];
        const face_view = atlas.faceView(glyph.face_index, .{});
        if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
            missing = true;
            if (!allow_missing) return error.MissingPreparedGlyph;
            continue;
        }
        const x = placement.baseline.x + (glyph.x_offset - origin_x) * placement.em;
        const y = placement.baseline.y + (glyph.y_offset - origin_y) * placement.em;
        const transform = glyphPlacementTransform(x, y, placement.em, fc.synthetic.skew_x);
        const local_fill = paint_mod.mapToLocal(fill, transform) orelse return error.InvalidTransform;
        const paint = try appendPendingGlyphPaint(bundle, &face_view, glyph.glyph_id, local_fill);
        try appendPendingGlyph(
            bundle,
            glyph.face_index,
            &face_view,
            glyph.glyph_id,
            transform,
            paint.color,
            paint.record_index,
            fc.synthetic,
        );
    }

    return .{
        .advance = scaleAdvance(advance, placement.em),
        .missing = missing,
    };
}

fn appendHintedSlice(
    bundle: *TextBlobBundle,
    slice: []const PreparedHintRun.Glyph,
    placement: TextPlacement,
    fill: Paint,
) !TextAppendResult {
    const color = switch (fill) {
        .solid => |c| c,
        else => return error.HintedAppendRequiresSolidFill,
    };
    const atlas = bundle.atlas;
    const bip = BlobInProgress{ .bundle = bundle };

    var missing = false;
    var hinted_pen = Vec2.zero;
    var advance = Vec2.zero;
    for (slice) |glyph| {
        advance = Vec2.add(advance, glyph.advance);
        const face = &atlas.config.faces[glyph.face_index];
        const x = placement.baseline.x + (hinted_pen.x + glyph.placement_delta.x) * placement.em;
        const y = placement.baseline.y + (hinted_pen.y + glyph.placement_delta.y) * placement.em;
        const transform = glyphPlacementTransform(x, y, placement.em, face.synthetic.skew_x);
        switch (glyph.source) {
            .hint => |hint| {
                if (hint.renderable()) {
                    try bip.appendHintedGlyphRef(glyph.face_index, glyph.glyph_id, transform, color, hint);
                }
            },
            .fallback => {
                const face_view = atlas.faceView(glyph.face_index, .{});
                if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
                    missing = true;
                } else {
                    const paint = try appendPendingGlyphPaint(bundle, &face_view, glyph.glyph_id, .{ .solid = color });
                    try appendPendingGlyph(
                        bundle,
                        glyph.face_index,
                        &face_view,
                        glyph.glyph_id,
                        transform,
                        paint.color,
                        paint.record_index,
                        face.synthetic,
                    );
                }
            },
        }
        hinted_pen = Vec2.add(hinted_pen, glyph.advance);
    }

    return .{
        .advance = scaleAdvance(advance, placement.em),
        .missing = missing,
    };
}

const PendingGlyphPaint = struct {
    color: [4]f32,
    record_index: ?u32 = null,
};

fn appendPendingGlyphPaint(
    bundle: *TextBlobBundle,
    face_view: *const FaceView,
    glyph_id: u16,
    fill: Paint,
) !PendingGlyphPaint {
    return switch (fill) {
        .solid => |color| .{ .color = color },
        else => blk: {
            const info = face_view.getGlyph(glyph_id) orelse {
                if (glyph_id == 0) break :blk .{ .color = .{ 1, 1, 1, 1 } };
                return error.UnsupportedTextPaint;
            };
            if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) {
                break :blk .{ .color = .{ 1, 1, 1, 1 } };
            }
            const pending = &bundle.pending;
            const index: u32 = @intCast(pending.paint_records.items.len);
            try pending.paint_records.append(bundle.gpa, .{
                .band_entry = info.band_entry,
                .paint = fill,
            });
            break :blk .{ .color = .{ 1, 1, 1, 1 }, .record_index = index };
        },
    };
}

fn appendPendingGlyph(
    bundle: *TextBlobBundle,
    face_index: FaceIndex,
    face_view: *const FaceView,
    glyph_id: u16,
    transform: Transform2D,
    color: [4]f32,
    paint_record_index: ?u32,
    synthetic: SyntheticStyle,
) !void {
    const pending = &bundle.pending;
    try pending.glyphs.append(bundle.gpa, .{
        .face_index = face_index,
        .glyph_id = glyph_id,
        .transform = transform,
        .embolden = synthetic.embolden,
        .color = color,
        .paint_record_index = paint_record_index,
    });
    pending.gpu_instance_budget += glyphInstanceBudget(face_view, glyph_id);
    if (synthetic.embolden != 0 and glyph_id != 0) {
        pending.gpu_instance_budget += glyphInstanceBudget(face_view, glyph_id);
    }
}

fn textBlobGpuInstanceBudgetForAtlas(atlas: *const TextAtlas, glyphs: []const TextBlob.Glyph) usize {
    var total: usize = 0;
    for (glyphs) |glyph| {
        if (glyph.hint_record_texel != null) {
            // Hinted glyphs always emit one instance; faux-bold doubles it.
            total += if (glyph.embolden != 0) 2 else 1;
            continue;
        }
        const fi = atlas.checkedFaceIndex(glyph.face_index) catch continue;
        const face_view = atlas.faceView(fi, .{});
        const base_budget = glyphInstanceBudget(&face_view, glyph.glyph_id);
        total += base_budget;
        if (glyph.embolden != 0 and glyph.glyph_id != 0) {
            total += base_budget;
        }
    }
    return total;
}

// Note: `TextBlob.Glyph.hint_record_texel` is now a bundle hint-pool index,
// not a texel offset. The renderer resolves it via
// `bundle.hintPoolTexelOffset(index)` against the bundle's shared hint slab.

fn emptyBBox() BBox {
    return .{ .min = Vec2.zero, .max = Vec2.zero };
}
