const std = @import("std");

const paint_mod = @import("../paint.zig");
const paint_records = @import("../paint_records.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const band_tex = @import("../render/format/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const hint_context = @import("hint_context.zig");
const hint_snapshot_mod = @import("hint_snapshot.zig");
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
const GlyphHintSnapshot = hint_snapshot_mod.GlyphHintSnapshot;
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
const TrueTypeHintContext = hint_context.TrueTypeHintContext;
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
        /// Texel offset of the glyph's hinted-curve record within the
        /// bound `GlyphHintSnapshot`'s layer-info slab. Resolved once at
        /// append time from `snapshot.lookup(key)`; the renderer reads
        /// this as an absolute texel coordinate without further indirection.
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
        // The hint key comes from the bound `GlyphHintSnapshot` itself:
        // many bundles can share one snapshot, and the snapshot's identity
        // is the natural dedup boundary. Empty snapshots (no renderable
        // entries) need no manifest binding.
        const hint_key: ?ResourceKey = if (self.bundle.hintSnapshotResolved()) |snapshot|
            (if (snapshot.hasRenderable()) snapshot.key else null)
        else
            null;
        return .{
            .atlas = atlas_key,
            .paint = if (self.hasPaintRecords()) resource_key_mod.derived(blob_key, "text_paint") else null,
            .hint = hint_key,
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

    // ── Hint binding ──
    //
    // Hinted glyphs are anchored to a `GlyphHintSnapshot` — the
    // per-(atlas, hint-context, ppem) immutable hinted-outline value.
    // The bundle supports two binding modes:
    //
    //   borrowed: a `*const GlyphHintSnapshot` pinned via
    //   `bindHintSnapshot(snapshot)`. Use when the snapshot is built
    //   ahead of time (cross-bundle sharing). Texel offsets resolve
    //   immediately at append time.
    //
    //   auto: a `*TrueTypeHintContext` pinned via `bindHintContext`.
    //   Texel offsets are still computed at append time (monotonic slab
    //   cursor over pending entries); the user MUST call
    //   `materialiseHintSnapshot()` once after the bundle's hinted
    //   glyphs are all appended and before adding the blob to a
    //   `ResourceManifest`. Materialisation is explicit so the upload
    //   point is honest: manifest paths read the already-packed
    //   snapshot without triggering hidden work.
    //
    // `Glyph.hint_record_texel` is always an absolute texel offset.
    hint_binding: HintBinding = .{ .none = {} },

    const HintBinding = union(enum) {
        none,
        borrowed: *const GlyphHintSnapshot,
        auto: AutoHintState,
    };

    const AutoHintState = struct {
        context: *TrueTypeHintContext,
        snapshot: GlyphHintSnapshot,
        pending: std.ArrayListUnmanaged(PendingEntry) = .empty,
        pending_refs: std.AutoHashMapUnmanaged(usize, u32) = .empty,
        texel_cursor: u32 = 0,
        dirty: bool = false,

        const PendingEntry = struct {
            key: hint_context.HintGlyphKey,
            advance: Vec2,
            bbox: BBox,
            record: text_hint.GlyphRecord,
            points_f16: []const u16,
            texel_offset: u32,
        };

        fn deinit(self: *AutoHintState, gpa: Allocator) void {
            self.snapshot.deinit();
            self.pending.deinit(gpa);
            self.pending_refs.deinit(gpa);
        }
    };

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
        self.clearHintBinding();
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
        self.clearHintBinding();
        _ = self.arena.reset(.retain_capacity);
        self.frozen = false;
        self.generation +%= 1;
    }

    fn clearHintBinding(self: *TextBlobBundle) void {
        switch (self.hint_binding) {
            .none, .borrowed => {},
            .auto => |*state| state.deinit(self.gpa),
        }
        self.hint_binding = .{ .none = {} };
    }

    /// Pin a `GlyphHintSnapshot` to this bundle (borrowed mode). The
    /// snapshot is value-typed and outlives the bundle. Idempotent for
    /// the same snapshot identity; errors if a different snapshot or a
    /// hint context is already bound.
    pub fn bindHintSnapshot(self: *TextBlobBundle, snapshot: *const GlyphHintSnapshot) !void {
        if (self.frozen) return error.BundleFrozen;
        try snapshot.validateAtlas(self.atlas);
        switch (self.hint_binding) {
            .none => self.hint_binding = .{ .borrowed = snapshot },
            .borrowed => |existing| {
                if (existing.snapshot_identity != snapshot.snapshot_identity) return error.WrongHintSnapshot;
            },
            .auto => return error.WrongHintSnapshot,
        }
    }

    /// Pin a `TrueTypeHintContext` to this bundle (auto mode). The
    /// bundle owns the resulting `GlyphHintSnapshot`; the user must
    /// call `materialiseHintSnapshot()` after all hinted appends and
    /// before any manifest preparation that consults the snapshot.
    /// Errors if a snapshot is already bound or a different context
    /// was already bound.
    pub fn bindHintContext(self: *TextBlobBundle, context: *TrueTypeHintContext) !void {
        if (self.frozen) return error.BundleFrozen;
        try context.validateAtlas();
        if (context.atlas != self.atlas) return error.WrongTextAtlasSnapshot;
        switch (self.hint_binding) {
            .none => {},
            .auto => |existing| {
                if (existing.context == context) return;
                return error.WrongHintSnapshot;
            },
            .borrowed => return error.WrongHintSnapshot,
        }
        var builder = try hint_snapshot_mod.Builder.init(self.gpa, self.atlas, .{});
        const snap = try builder.finish();
        self.hint_binding = .{ .auto = .{
            .context = context,
            .snapshot = snap,
        } };
    }

    /// Pack auto-mode pending entries into the bundle's owned
    /// `GlyphHintSnapshot`. Must be called explicitly before the bundle
    /// participates in a `ResourceManifest`. Idempotent: re-materialises
    /// only when new pending entries have been added since the last call.
    /// No-op (and OK) in borrowed mode or with no binding.
    pub fn materialiseHintSnapshot(self: *TextBlobBundle) !void {
        switch (self.hint_binding) {
            .none, .borrowed => {},
            .auto => |*state| if (state.dirty) try repackAutoSnapshot(self.gpa, self.atlas, state),
        }
    }

    /// Returns the bundle's hint snapshot upload payload. Does not
    /// materialise; in auto mode the user must have called
    /// `materialiseHintSnapshot` first or the returned upload reflects
    /// the snapshot's previous materialisation (possibly empty).
    pub fn hintLayerInfoUpload(self: *const TextBlobBundle) PreparedHintLayerInfoUpload {
        const snap = self.hintSnapshotResolved() orelse return .{};
        return snap.layerInfoUpload();
    }

    /// True if this bundle has a bound snapshot with at least one
    /// renderable hint. In auto mode reflects the most recently
    /// materialised state — call `materialiseHintSnapshot` first to
    /// include any unflushed pending entries.
    pub fn hasHintRecords(self: *const TextBlobBundle) bool {
        const snap = self.hintSnapshotResolved() orelse return false;
        return snap.hasRenderable();
    }

    /// Read-only snapshot accessor used by `blob.resourceKeys`, the
    /// renderer's batch emitter, and manifest preparation. Never
    /// triggers materialisation; auto-mode callers are responsible for
    /// calling `materialiseHintSnapshot` at the right time.
    pub fn hintSnapshotResolved(self: *const TextBlobBundle) ?*const GlyphHintSnapshot {
        return switch (self.hint_binding) {
            .none => null,
            .borrowed => |snap| snap,
            .auto => |*state| &state.snapshot,
        };
    }

    fn appendAutoHintEntry(
        self: *TextBlobBundle,
        value: *const HintedGlyphValue,
    ) !u32 {
        const state = switch (self.hint_binding) {
            .auto => |*s| s,
            else => return error.NoHintSnapshotBound,
        };
        const ptr_key = @intFromPtr(value);
        if (state.pending_refs.get(ptr_key)) |existing_idx| {
            return state.pending.items[existing_idx].texel_offset;
        }
        const attachment = value.attachment orelse return error.EmptyHintedGlyph;
        const texel_offset = state.texel_cursor;
        const record_size = text_hint.recordTexelCount(attachment.record.curve_count);
        // Copy the f16 points into the bundle's arena so the pending
        // entry never depends on the hint context's glyph storage —
        // the cache may evict entries between appends and materialise
        // without dangling references. Arena memory is reclaimed on
        // `bundle.reset()`.
        const owned_points = try self.arena.allocator().dupe(u16, attachment.curve_points_f16);
        try state.pending.append(self.gpa, .{
            .key = value.key,
            .advance = value.advance,
            .bbox = value.bbox,
            .record = attachment.record,
            .points_f16 = owned_points,
            .texel_offset = texel_offset,
        });
        errdefer _ = state.pending.pop();
        const pending_idx: u32 = @intCast(state.pending.items.len - 1);
        try state.pending_refs.put(self.gpa, ptr_key, pending_idx);
        state.texel_cursor += record_size;
        state.dirty = true;
        return texel_offset;
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

    pub fn appendHintedGlyphRef(
        self: BlobInProgress,
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        color: [4]f32,
        value: *const HintedGlyphValue,
    ) !void {
        const texel_offset = switch (self.bundle.hint_binding) {
            .none => return error.NoHintSnapshotBound,
            .borrowed => |snapshot| blk: {
                try snapshot.validateAtlas(self.bundle.atlas);
                const entry = snapshot.lookup(value.key) orelse return error.GlyphNotInHintSnapshot;
                break :blk (entry.record_texel_offset orelse return error.EmptyHintedGlyph);
            },
            .auto => try self.bundle.appendAutoHintEntry(value),
        };

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
            .hint_record_texel = texel_offset,
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

// `TextBlob.Glyph.hint_record_texel` is the absolute texel offset into the
// bound `GlyphHintSnapshot`'s layer-info slab — resolved at append time via
// `snapshot.lookup(value.key).record_texel_offset` (borrowed mode) or
// `appendAutoHintEntry` (auto mode). The renderer reads it without further
// indirection.

fn repackAutoSnapshot(
    gpa: Allocator,
    atlas: *const TextAtlas,
    state: *TextBlobBundle.AutoHintState,
) !void {
    // Rebuild the owned snapshot from the pending list. The texel
    // offsets stored in `Glyph.hint_record_texel` are stable across
    // repacks because the slab is laid out in the order pending entries
    // were appended and `texel_offset` is captured at append time.
    var builder = try hint_snapshot_mod.Builder.initWithCursor(gpa, atlas, .{}, state.texel_cursor);
    errdefer builder.deinit();
    for (state.pending.items) |entry| {
        try builder.addAtOffset(entry.key, entry.advance, entry.bbox, entry.record, entry.points_f16, entry.texel_offset);
    }
    var new_snap = try builder.finish();
    errdefer new_snap.deinit();
    state.snapshot.deinit();
    state.snapshot = new_snap;
    state.dirty = false;
}

fn emptyBBox() BBox {
    return .{ .min = Vec2.zero, .max = Vec2.zero };
}
