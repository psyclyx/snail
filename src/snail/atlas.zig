//! Value-typed atlas: the store of prepared glyph records. Holds
//! refcounted page references plus a key→record lookup table.
//! `from`, `extend`, and `compactInto` return new snapshots, leaving their input
//! atlas logically unchanged. `extendInPlace` and the page-free advance
//! convenience methods mutate their receiver.
//!
//! ## Capacity model
//!
//! The `PagePool` is the caller's residency budget: `max_pages` pages of
//! fixed curve/band capacity, sized once at init. Updates are incremental and
//! idempotent — an app can add glyphs for its whole lifetime and only new
//! record keys cost space — but nothing is ever
//! evicted implicitly. When the pool is exhausted, recording fails with
//! `error.OutOfLayers`; that error is the caller's eviction moment, not a
//! bug. The recovery primitive is `compactInto` with a `RecordFilter`: rebuild
//! the working set in a distinct caller-owned pool while the source remains
//! drawable (retention policy stays with the caller). Publish the replacement
//! asynchronously, then retire the old atlas and pool after final device use.
//! The same-pool `compact` convenience remains available when result-sized
//! headroom was deliberately reserved.
//!
//! Two record kinds change the budget math: autohint records are
//! resolution-independent (one per glyph, ever — the mode to prefer under
//! continuous zoom), while TT-hinted records are per (glyph, ppem) and
//! accumulate with every distinct size (`ns.tt_advance` values are
//! page-free and never pressure the pool). `dev/support/working_set.zig`
//! is the worked example of a bounded-residency policy over this model.
//!
//! See the README's "Capacity and eviction" section for the public recipe.

const std = @import("std");
const page_mod = @import("atlas/page.zig");
const page_pool_mod = @import("atlas/page_pool.zig");
const atlas_record_mod = @import("atlas/record.zig");
const record_key_mod = @import("atlas/record_key.zig");
const curves_mod = @import("atlas/curves.zig");
const curve_tex_format = @import("format/curve_texture.zig");
const band_tex_format = @import("format/band_texture.zig");
const paint_mod = @import("paint.zig");
const atlas_builder = @import("atlas/builder.zig");
const hamt_mod = @import("util/hamt.zig");
const autohint = @import("font/autohint/producer.zig");

const Builder = atlas_builder.Builder;

const RecordKeyContext = struct {
    pub fn hash(_: RecordKeyContext, k: RecordKey) u64 {
        return k.hash();
    }
    pub fn eql(_: RecordKeyContext, a: RecordKey, b: RecordKey) bool {
        return a.eql(b);
    }
};

pub const RecordLookup = hamt_mod.Hamt(RecordKey, AtlasRecord, RecordKeyContext);
pub const PaintLookup = hamt_mod.Hamt(RecordKey, PaintRecordInfo, RecordKeyContext);
pub const TtAdvanceLookup = hamt_mod.Hamt(RecordKey, i32, RecordKeyContext);
pub const TtAdvanceEntry = struct { key: RecordKey, advance_26_6: i32 };

const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const AtlasRecord = atlas_record_mod.AtlasRecord;
pub const GlyphBandEntry = atlas_record_mod.GlyphBandEntry;
pub const RecordKey = record_key_mod.RecordKey;
pub const GlyphCurves = curves_mod.GlyphCurves;
pub const GeometryView = curves_mod.GeometryView;
pub const Paint = paint_mod.Paint;
/// Ordered structural metadata for one layer-info paint record. The slab also
/// contains TT/autohint payloads whose numeric fields can equal paint tags,
/// so consumers must use these explicit boundaries instead of tag-scanning.
/// Composite headers carry `layer_count > 1`; their following layer
/// descriptors each carry `layer_count == 1`.
pub const PaintRecordDescriptor = struct {
    texel_offset: u32,
    layer_count: u16 = 1,
    image: ?*const @import("image.zig").Image = null,
    /// Binding-relative image-array layer assigned by the atlas builder.
    /// Upload caches add their binding's `image_layer_base`.
    image_layer: u32 = 0,
    /// True only on the first record that references `image` in this atlas.
    /// Upload planning can therefore count and emit unique images in O(n).
    first_image_use: bool = false,
};

/// Lookup result for a key whose entry carries a paint. Holds the
/// (info_x, info_y) texel coordinates pointing at the layer_info record
/// in the atlas's `layer_info_data` buffer.
pub const PaintShaderClass = enum {
    /// TrueType glyph geometry with solid source-over layers: eligible for
    /// the compact COLRv0 fragment.
    colr_solid,
    /// General paint over line/quadratic geometry.
    path_quadratic,
    /// General paint over line/quadratic/rational-conic geometry.
    path_conic,
    /// Legacy general-path class; uses the conic-capable evaluator now that
    /// authored cubics are lowered during preparation.
    path_cubic,
};

/// Lookup result for a key whose entry carries a paint: the `(info_x, info_y)`
/// texel coordinate of its layer-info record, its layer count, and the shader
/// class emit uses to pick the fragment family.
pub const PaintRecordInfo = struct {
    info_x: u16,
    info_y: u16,
    layer_count: u16 = 1,
    shader_class: PaintShaderClass = .path_cubic,
};

/// Immutable, target-free analysis for an autohint entry. All values are
/// em-normalized. The slices are borrowed by `from`/`extend`; the builder
/// copies them into the layer-info slab during the build call.
pub const AutohintAnalysis = struct {
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
};

const CURVE_TEX_WIDTH = curve_tex_format.TEX_WIDTH;
const CURVE_SEGMENT_TEXELS = curve_tex_format.GENERAL_SEGMENT_TEXELS;
const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * 4;
const BAND_TEX_WIDTH = band_tex_format.TEX_WIDTH;
const BAND_TEX_WIDTH_USIZE: usize = BAND_TEX_WIDTH;

/// One independently prepared geometry record. When `paint` is non-null the
/// atlas also allocates a layer-info record and remembers its coordinates so
/// emit can encode a special-layer instance instead of a regular one.
///
/// Non-empty `extra_layers` form a multi-layer composite group; empty layers
/// are omitted. When the base curves are empty, the first visible extra is
/// promoted to the base instead of dropping the entry.
pub const GeometryEntry = struct {
    key: RecordKey,
    curves: GeometryView,
    paint: ?Paint = null,
    /// Per-entry winding rule. Geometry property of the path/glyph itself
    /// (a path author either intends non-zero or even-odd; fonts are
    /// always non-zero). Carried into the paint record so the shader
    /// picks it up per-fragment — there is no per-frame fill rule.
    fill_rule: @import("paint.zig").FillRule = .non_zero,
    extra_layers: []const Layer = &.{},
    composite_mode: CompositeMode = .source_over,
};

/// One layer of a multi-layer composite geometry entry: its own curves, paint,
/// and winding rule. Ordered back to front within `GeometryEntry.extra_layers`.
pub const Layer = struct {
    curves: GeometryView,
    paint: Paint,
    fill_rule: @import("paint.zig").FillRule = .non_zero,
};

pub const CompositeMode = paint_mod.CompositeMode;

/// Immutable autohint analysis over the same font/glyph's unhinted geometry.
/// `base_key` must be the canonical `unhintedGlyph(key.a, key.b)` key and must
/// be present in the parent atlas or earlier in the same update. The entry
/// aliases the base geometry; it never owns or places curves.
pub const AutohintEntry = struct {
    key: RecordKey,
    base_key: RecordKey,
    analysis: AutohintAnalysis,
};

/// One logical atlas insertion. The tag makes geometry placement and autohint
/// aliasing distinct operations instead of encoding the distinction with
/// optional fields whose invalid combinations must be rejected at runtime.
pub const AtlasEntry = union(enum) {
    geometry: GeometryEntry,
    autohint: AutohintEntry,

    pub fn key(self: AtlasEntry) RecordKey {
        return switch (self) {
            .geometry => |entry| entry.key,
            .autohint => |entry| entry.key,
        };
    }
};

/// One logically atomic update. Geometry and page-free TT advances become
/// visible together, so producers do not coordinate two mutation operations.
/// Caller-controlled payloads are preflighted before append-only page
/// publication begins. A later allocator or concurrent-capacity failure can
/// consume unreachable page padding, but never publishes a partial Atlas.
pub const AtlasUpdate = struct {
    entries: []const AtlasEntry = &.{},
    tt_advances: []const TtAdvanceEntry = &.{},

    pub fn isEmpty(self: AtlasUpdate) bool {
        return self.entries.len == 0 and self.tt_advances.len == 0;
    }
};

/// Failure from `extend`/`extendInPlace` (and the `from*` builders). Includes
/// allocator and page-pool errors; `OutOfLayers` means the pool cannot grant a
/// page for a new record, and the host owns the resulting eviction policy. The
/// remaining tags flag malformed or oversized caller payloads, all rejected
/// during preflight so no partial atlas is published.
pub const InsertError = std.mem.Allocator.Error || PagePool.AcquireError || PagePool.IdentityError || error{
    MapTooLarge,
    ReferenceCountExhausted,
    RecordTooLargeForPage,
    InvalidCurves,
    InvalidPaint,
    ImageCountOverflow,
    AtlasRevisionExhausted,
    NoPool,
    MissingAutohintBase,
    InvalidAutohintAnalysis,
    LayerInfoTooLarge,
    CorruptPaintRecord,
    InvalidRecordKey,
    InvalidPacking,
};

/// A persistent, value-typed CPU store of prepared records over a `PagePool`.
/// `extend`/`extendInPlace` publish one logically atomic `AtlasUpdate` and
/// return a new snapshot that shares unchanged page storage with its parent;
/// `compact`/`compactInto` repack a filtered working set into a fresh root.
/// Lookups return records by value. See the module header for the full model.
pub const Atlas = struct {
    pub const Packing = struct {
        /// Maximum recent pages considered by the bounded best-fit packer.
        /// One selects tail-only placement. The hard cap keeps insertion
        /// independent of the total atlas size.
        recent_page_limit: u8 = 12,

        fn validate(self: Packing) error{InvalidPacking}!void {
            if (self.recent_page_limit == 0 or self.recent_page_limit > 64) {
                return error.InvalidPacking;
            }
        }
    };

    allocator: std.mem.Allocator,
    /// The pool from which `pages` were allocated. `null` only on the
    /// identity atlas (`empty(allocator)`); operations that allocate pages
    /// require a non-null pool.
    pool: ?*PagePool,
    /// Stable identity of the root snapshot family. Extensions inherit it;
    /// independently built and compacted atlases receive a fresh lineage.
    lineage: u64 = 0,
    /// Extension depth within a lineage. It is descriptive only: branched
    /// children can have the same revision and are distinguished by
    /// `snapshot_id`.
    revision: u64 = 0,
    /// Unique identity of this exact immutable snapshot within `pool`.
    snapshot_id: u64 = 0,
    /// Exact source snapshot for an extension, or zero for a fresh root.
    parent_snapshot_id: u64 = 0,
    /// Placement policy belongs to this atlas lineage, not its shared page
    /// residency pool. Extensions and compaction preserve it.
    packing: Packing = .{},
    /// Refcounted opaque page handles. Index into this slice is what
    /// `AtlasRecord.page_index` refers to; callers cannot inspect or mutate
    /// the underlying storage.
    pages: []*AtlasPage,
    /// Persistent map: `Atlas.extend` shares unchanged subtrees with the
    /// parent atlas, so a 1-entry extension is O(log32 N) and copies
    /// only the path-to-new-leaf.
    lookup: RecordLookup,
    /// Optional layer_info f32 buffer holding 6-texel paint records, one
    /// per entry whose `paint` was non-null. Encoded by the `paint_records`
    /// module so the CPU sampler and the GL/Vulkan path shaders consume
    /// the same byte layout.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,
    /// Per-key (info_x, info_y) lookups for paint records. Same
    /// persistent-map shape as `lookup`.
    paint_lookup: PaintLookup,
    /// Per-key (info_x, info_y) into `layer_info_data` for autohint records.
    /// Same persistent-map shape as `paint_lookup`.
    autohint_lookup: PaintLookup,
    /// Per-key (info_x, info_y) into `layer_info_data` for baked TT-hint
    /// glyph band records. The hinted outline itself remains in the ordinary
    /// curve/band atlas; this small record lets the hinted-text instance ABI
    /// address it while retaining a distinct shader/program family.
    tt_hinted_lookup: PaintLookup,
    /// Per-key TT-hinted horizontal advances (26.6 px), `ns.tt_advance`.
    /// CPU-only value records: read at shape time by advance providers,
    /// never uploaded. Produced by TT preparation and committed through an
    /// `AtlasUpdate` (or the page-free advance convenience methods).
    tt_advance_lookup: TtAdvanceLookup,
    /// One descriptor per emitted paint header/layer, in slab order. Image
    /// pointers are caller-owned references; the atlas only borrows.
    paint_records: ?[]PaintRecordDescriptor = null,

    /// Pool-less identity atlas. It can represent an empty result, but cannot
    /// be extended; use `init` for an initially empty growable atlas.
    pub fn empty(allocator: std.mem.Allocator) Atlas {
        return .{
            .allocator = allocator,
            .pool = null,
            .lineage = 0,
            .revision = 0,
            .snapshot_id = 0,
            .parent_snapshot_id = 0,
            .packing = .{},
            .pages = &.{},
            .lookup = RecordLookup.init(allocator, .{}),
            .paint_lookup = PaintLookup.init(allocator, .{}),
            .autohint_lookup = PaintLookup.init(allocator, .{}),
            .tt_hinted_lookup = PaintLookup.init(allocator, .{}),
            .tt_advance_lookup = TtAdvanceLookup.init(allocator, .{}),
        };
    }

    /// Empty atlas associated with `pool`. Unlike `empty`, this value can be
    /// populated with `extend` / `extendInPlace`; it is useful for callers
    /// whose atlas starts empty and grows on demand.
    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) PagePool.IdentityError!Atlas {
        return initWithPacking(allocator, pool, .{}) catch |err| switch (err) {
            error.InvalidPacking => unreachable,
            error.IdentityExhausted => error.IdentityExhausted,
        };
    }

    pub fn initWithPacking(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        packing: Packing,
    ) (PagePool.IdentityError || error{InvalidPacking})!Atlas {
        try packing.validate();
        var atlas = empty(allocator);
        atlas.pool = pool;
        atlas.packing = packing;
        atlas.snapshot_id = try page_pool_mod.nextAtlasSnapshotId(pool);
        atlas.lineage = atlas.snapshot_id;
        return atlas;
    }

    pub const SnapshotIdentity = struct {
        lineage: u64,
        revision: u64,
        snapshot_id: u64,
        parent_snapshot_id: u64,
    };

    /// Identity used by upload caches to distinguish an exact snapshot from
    /// its direct append-only child and from a branch/unrelated atlas.
    pub fn snapshotIdentity(self: *const Atlas) SnapshotIdentity {
        return .{
            .lineage = self.lineage,
            .revision = self.revision,
            .snapshot_id = self.snapshot_id,
            .parent_snapshot_id = self.parent_snapshot_id,
        };
    }

    pub fn deinit(self: *Atlas) void {
        if (self.pool) |pool| {
            for (self.pages) |p| page_pool_mod.release(pool, p);
        } else {
            std.debug.assert(self.pages.len == 0);
        }
        if (self.pages.len > 0) self.allocator.free(self.pages);
        if (self.layer_info_data) |d| self.allocator.free(d);
        if (self.paint_records) |records| self.allocator.free(records);
        self.paint_lookup.deinit();
        self.autohint_lookup.deinit();
        self.tt_hinted_lookup.deinit();
        self.tt_advance_lookup.deinit();
        self.lookup.deinit();
        self.* = undefined;
    }

    /// Look up the paint record (if any) bound to `key`. Returns null
    /// for keys whose entry had no paint or for a pool-less empty atlas.
    pub fn lookupPaintRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.paint_lookup.get(key);
    }

    /// Look up the autohint slab record (if any) bound to `key`.
    pub fn lookupAutohintRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.autohint_lookup.get(key);
    }

    /// Look up the band record for a baked per-PPEM TT-hinted glyph.
    pub fn lookupTtHintedRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.tt_hinted_lookup.get(key);
    }

    /// Look up a recorded TT-hinted horizontal advance (26.6 px) for a
    /// `ns.tt_advance` key.
    pub fn lookupTtAdvance(self: *const Atlas, key: RecordKey) ?i32 {
        return self.tt_advance_lookup.get(key);
    }

    /// Record a TT-hinted horizontal advance under a `ns.tt_advance` key.
    /// Idempotent: an existing record wins (advances are pure in the key).
    pub fn recordTtAdvance(
        self: *Atlas,
        key: RecordKey,
        advance_26_6: i32,
    ) (std.mem.Allocator.Error || error{ MapTooLarge, InvalidRecordKey })!void {
        try self.recordTtAdvances(&.{.{ .key = key, .advance_26_6 = advance_26_6 }});
    }

    /// Atomically add a batch of page-free TT advances. Allocation failure
    /// leaves the atlas's previous lookup untouched.
    pub fn recordTtAdvances(
        self: *Atlas,
        advances: []const TtAdvanceEntry,
    ) (std.mem.Allocator.Error || error{ MapTooLarge, InvalidRecordKey })!void {
        if (advances.len == 0) return;
        for (advances) |entry| {
            if (entry.key.namespace != record_key_mod.ns.tt_advance) return error.InvalidRecordKey;
        }
        var next = self.tt_advance_lookup.clone();
        errdefer next.deinit();
        for (advances) |entry| {
            if (next.contains(entry.key)) continue;
            const grown = try next.put(entry.key, entry.advance_26_6);
            next.deinit();
            next = grown;
        }
        self.tt_advance_lookup.deinit();
        self.tt_advance_lookup = next;
    }

    pub fn ttAdvanceCount(self: *const Atlas) u32 {
        return self.tt_advance_lookup.count();
    }

    pub fn contains(self: *const Atlas, key: RecordKey) bool {
        return self.lookup.contains(key);
    }

    pub fn lookupRecord(self: *const Atlas, key: RecordKey) ?AtlasRecord {
        return self.lookup.get(key);
    }

    pub fn recordCount(self: *const Atlas) u32 {
        return self.lookup.count();
    }

    pub fn paintRecordCount(self: *const Atlas) u32 {
        return self.paint_lookup.count();
    }

    pub fn pageCount(self: *const Atlas) usize {
        return self.pages.len;
    }

    /// Pack one logical update into a fresh atlas backed by `pool`. Duplicate
    /// keys keep their first occurrence.
    pub fn from(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        update: AtlasUpdate,
    ) InsertError!Atlas {
        return fromWithPacking(allocator, pool, update, .{});
    }

    pub fn fromWithPacking(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        update: AtlasUpdate,
        packing: Packing,
    ) InsertError!Atlas {
        try packing.validate();
        var builder = try Builder.init(allocator, pool, packing);
        errdefer builder.abort();

        try builder.preflightUpdate(update);
        for (update.entries) |entry| try builder.insert(entry);
        for (update.tt_advances) |advance| try builder.putTtAdvance(advance.key, advance.advance_26_6);

        return builder.finish();
    }

    /// Return a persistent snapshot containing the existing records plus
    /// `update`. The original atlas remains valid and logically unchanged.
    pub fn extend(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        update: AtlasUpdate,
    ) InsertError!Atlas {
        const pool = self.pool orelse return error.NoPool; // empty atlas, no pool to allocate from
        var builder = try Builder.initFrom(allocator, pool, self);
        errdefer builder.abort();

        try builder.preflightUpdate(update);
        for (update.entries) |entry| try builder.insert(entry);
        for (update.tt_advances) |advance| try builder.putTtAdvance(advance.key, advance.advance_26_6);

        return builder.finish();
    }

    /// Replace this atlas with one extension. Geometry and TT advances become
    /// visible atomically; on error `self` remains logically unchanged.
    /// Append-only page padding may have been consumed. Empty updates are a
    /// no-op.
    pub fn extendInPlace(
        self: *Atlas,
        allocator: std.mem.Allocator,
        update: AtlasUpdate,
    ) InsertError!void {
        if (update.isEmpty()) return;
        const grown = try self.extend(allocator, update);
        self.deinit();
        self.* = grown;
    }

    /// Rebuild the store, freshly packed into `target_pool`.
    /// Every record kind is carried with full fidelity: geometry is
    /// repacked, paint layers and autohint analyses are copied
    /// byte-for-byte (only placement locations are rewritten), TT-hinted
    /// band records are regenerated, and `ns.tt_advance` values are cloned.
    ///
    /// `filter` selects which records survive — this is the eviction
    /// primitive: `null` keeps everything (pure defragmentation); a filter
    /// rebuilds only the working set. Dependencies close automatically: a
    /// kept autohint record brings its base glyph even if the filter
    /// dropped it. Page-free records (`ns.tt_advance`) pass through the
    /// filter too but cost no pages either way.
    ///
    /// The source is unaffected and remains usable. If `target_pool` is the
    /// source pool, both snapshots coexist and the pool needs enough free pages
    /// for the result. A distinct target pool removes that headroom coupling
    /// and permits background migration before publication.
    pub fn compactInto(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        target_pool: *PagePool,
        filter: ?RecordFilter,
    ) InsertError!Atlas {
        var builder = try Builder.init(allocator, target_pool, self.packing);
        errdefer builder.abort();

        // Two passes: autohint records re-alias their base glyphs, so the
        // bases must be placed first.
        var it = self.lookup.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.namespace == record_key_mod.ns.autohint_glyph) continue;
            if (filter) |f| if (!f.keeps(kv.key_ptr.*)) continue;
            try builder.insertCopied(self, kv.key_ptr.*, scratch);
        }
        it = self.lookup.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.namespace != record_key_mod.ns.autohint_glyph) continue;
            if (filter) |f| if (!f.keeps(kv.key_ptr.*)) continue;
            try builder.insertCopied(self, kv.key_ptr.*, scratch);
        }

        var advances = self.tt_advance_lookup.iterator();
        while (advances.next()) |kv| {
            if (filter) |f| if (!f.keeps(kv.key_ptr.*)) continue;
            try builder.putTtAdvance(kv.key_ptr.*, kv.value_ptr.*);
        }

        return builder.finish();
    }

    /// Repack into the source pool. This persistent convenience wrapper retains
    /// the source snapshot and therefore requires result-sized free headroom.
    pub fn compact(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        filter: ?RecordFilter,
    ) InsertError!Atlas {
        const pool = self.pool orelse {
            var result = Atlas.empty(allocator);
            errdefer result.deinit();
            var advances = self.tt_advance_lookup.iterator();
            while (advances.next()) |kv| {
                if (filter) |f| if (!f.keeps(kv.key_ptr.*)) continue;
                try result.recordTtAdvance(kv.key_ptr.*, kv.value_ptr.*);
            }
            return result;
        };
        return self.compactInto(allocator, scratch, pool, filter);
    }
};

/// Record-selection closure for `Atlas.compactInto` — the eviction hook. The
/// filter sees every record key (geometry namespaces and `ns.tt_advance`);
/// return true to carry the record into the rebuilt store.
pub const RecordFilter = struct {
    context: *anyopaque,
    keep: *const fn (context: *anyopaque, key: RecordKey) bool,

    pub fn keeps(self: RecordFilter, key: RecordKey) bool {
        return self.keep(self.context, key);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn makeTestCurves(allocator: std.mem.Allocator) !GlyphCurves {
    // Two curve segments, one h-band, one v-band, two refs (one per band,
    // pointing at curve indices 0 and 1).
    const curve_words = 2 * CURVE_SEGMENT_WORDS;
    const curve_bytes = try allocator.alloc(u16, curve_words);
    for (curve_bytes, 0..) |*w, i| w.* = @intCast(@as(u16, @intCast(i)) +% 0x1000);
    for (0..2) |curve_index| {
        curve_bytes[curve_index * CURVE_SEGMENT_WORDS + 10] = 0; // packed quadratic
    }

    // band header = 1 h-band + 1 v-band = 2 texels = 4 u16.
    // band refs = 2 refs per band * 2 bands = 4 texels = 8 u16. Plus 4
    // header words.
    const band_bytes = try allocator.alloc(u16, 16);
    const prefix = band_tex_format.packBlockPrefix(1, 1);
    @memcpy(band_bytes[0..prefix.len], &prefix);
    band_bytes[4] = 2; // h-band 0 count
    band_bytes[5] = 2; // h-band 0 offset (from glyph_loc, in texels) = 2
    band_bytes[6] = 2; // v-band 0 count
    band_bytes[7] = 4; // v-band 0 offset = 4

    // h-band refs at curve texel 0 and 4 (i.e., curve 0 and curve 1).
    band_bytes[8] = 0; // cx=0, first_member_band=0
    band_bytes[9] = 0; // cy=0
    band_bytes[10] = 4; // cx=4
    band_bytes[11] = 0;
    // v-band refs (same).
    band_bytes[12] = 0;
    band_bytes[13] = 0;
    band_bytes[14] = 4;
    band_bytes[15] = 0;

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = 2,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
        .bbox = .{ .min = .zero, .max = .{ .x = 8, .y = 4 } },
    };
}

fn makeSizedTestCurves(
    allocator: std.mem.Allocator,
    segment_count: u16,
    reference_count: u16,
) !GlyphCurves {
    std.debug.assert(segment_count > 0 and reference_count >= 2);
    const curve_bytes = try allocator.alloc(u16, @as(usize, segment_count) * CURVE_SEGMENT_WORDS);
    errdefer allocator.free(curve_bytes);
    for (0..segment_count) |curve_index| {
        const base = curve_index * CURVE_SEGMENT_WORDS;
        @memset(curve_bytes[base..][0..CURVE_SEGMENT_WORDS], 0);
        curve_bytes[base + 10] = 0; // packed quadratic
    }

    const band_bytes = try allocator.alloc(u16, 8 + @as(usize, reference_count) * 2);
    errdefer allocator.free(band_bytes);
    const prefix = band_tex_format.packBlockPrefix(1, 1);
    @memcpy(band_bytes[0..prefix.len], &prefix);
    const h_refs = reference_count / 2;
    const v_refs = reference_count - h_refs;
    band_bytes[4] = h_refs;
    band_bytes[5] = 2;
    band_bytes[6] = v_refs;
    band_bytes[7] = 2 + h_refs;
    for (0..reference_count) |ref_index| {
        const curve_index = ref_index % segment_count;
        band_bytes[8 + ref_index * 2] = @intCast(curve_index * CURVE_SEGMENT_TEXELS);
        band_bytes[8 + ref_index * 2 + 1] = 0;
    }

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = segment_count,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1,
        .band_scale_y = 1,
        .band_offset_x = 0,
        .band_offset_y = 0,
        .bbox = .{ .min = .zero, .max = .{ .x = 1, .y = 1 } },
    };
}

fn testGeometry(key: RecordKey, curves: GlyphCurves) AtlasEntry {
    return .{ .geometry = .{ .key = key, .curves = curves.view() } };
}

test "bounded best-fit recovers complementary high-variance page holes" {
    const entries_keys = [_]RecordKey{
        record_key_mod.unhintedGlyph(0, 1),
        record_key_mod.unhintedGlyph(0, 2),
        record_key_mod.unhintedGlyph(0, 3),
    };
    var a = try makeSizedTestCurves(testing.allocator, 6, 6); // 96 curve, 20 band
    defer a.deinit();
    var b = try makeSizedTestCurves(testing.allocator, 5, 12); // 80 curve, 32 band
    defer b.deinit();
    var c = try makeSizedTestCurves(testing.allocator, 2, 6); // 32 curve, 20 band
    defer c.deinit();
    const entries = [_]AtlasEntry{
        testGeometry(entries_keys[0], a),
        testGeometry(entries_keys[1], b),
        testGeometry(entries_keys[2], c),
    };

    var best_fit_pool = try PagePool.init(testing.allocator, .{
        .max_pages = 3,
        .curve_words_per_page = 160,
        .band_words_per_page = 40,
    });
    defer best_fit_pool.deinit();
    var best_fit = try Atlas.fromWithPacking(
        testing.allocator,
        best_fit_pool,
        .{ .entries = &entries },
        .{ .recent_page_limit = 12 },
    );
    defer best_fit.deinit();
    try testing.expectEqual(@as(u32, 2), best_fit_pool.stats().pages_in_use);

    var tail_pool = try PagePool.init(testing.allocator, .{
        .max_pages = 3,
        .curve_words_per_page = 160,
        .band_words_per_page = 40,
    });
    defer tail_pool.deinit();
    var tail = try Atlas.fromWithPacking(
        testing.allocator,
        tail_pool,
        .{ .entries = &entries },
        .{ .recent_page_limit = 1 },
    );
    defer tail.deinit();
    try testing.expectEqual(@as(u32, 3), tail_pool.stats().pages_in_use);
}

fn exerciseAtlasBuildAllocationFailures(
    allocator: std.mem.Allocator,
    pool: *PagePool,
    curves: *const GlyphCurves,
) !void {
    const free_before = pool.stats().pages_free;
    var atlas = Atlas.from(allocator, pool, .{ .entries = &.{
        .{ .geometry = .{ .key = record_key_mod.unhintedGlyph(7, 1), .curves = curves.view(), .paint = .{ .solid = .{ 2, 1, 0.5, 1 } } } },
        testGeometry(record_key_mod.unhintedGlyph(7, 2), curves.*),
    } }) catch |err| {
        try testing.expectEqual(free_before, pool.stats().pages_free);
        return err;
    };
    defer atlas.deinit();
    try testing.expectEqual(@as(u32, 2), atlas.recordCount());
}

test "Atlas.from cleans up every allocation failure without leaking pages" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();

    try testing.checkAllAllocationFailures(
        testing.allocator,
        exerciseAtlasBuildAllocationFailures,
        .{ pool, &curves },
    );
    try testing.expectEqual(pool.stats().pages_total, pool.stats().pages_free);
}

test "Atlas extension reports page reference exhaustion atomically" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    const key = record_key_mod.unhintedGlyph(2, 3);
    var base = try Atlas.from(testing.allocator, pool, .{ .entries = &.{testGeometry(key, curves)} });
    defer base.deinit();
    const page = base.pages[0];
    try testing.expectEqual(@as(u32, 1), page_mod.refCount(page));
    page_mod.testSetReferenceCount(page, std.math.maxInt(u32));
    defer page_mod.testSetReferenceCount(page, 1);

    try testing.expectError(error.ReferenceCountExhausted, base.extend(testing.allocator, .{}));
    try testing.expectEqual(@as(u32, 1), base.recordCount());
    try testing.expect(base.contains(key));
    try testing.expectEqual(std.math.maxInt(u32), page_mod.refCount(page));
}

test "from packs entries into pages and records lookup" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);
    const entries = [_]AtlasEntry{
        testGeometry(k0, c0),
        testGeometry(k1, c1),
    };

    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &entries });
    defer atlas.deinit();

    try testing.expectEqual(@as(u32, 2), atlas.recordCount());
    try testing.expect(atlas.contains(k0));
    try testing.expect(atlas.contains(k1));

    // Two glyphs of 2 curves each (32 words/glyph) -> 64 curve words used.
    try testing.expectEqual(@as(usize, 1), atlas.pageCount());

    const r0 = atlas.lookupRecord(k0).?;
    const r1 = atlas.lookupRecord(k1).?;
    try testing.expectEqual(@as(u16, 0), r0.page_index);
    try testing.expectEqual(@as(u16, 0), r1.page_index);
    try testing.expect(r0.curve_texel < r1.curve_texel);
    try testing.expectEqual(@as(u16, 2), r0.curve_count);
}

test "from rejects malformed caller-provided curves before reserving a page" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    curves.curve_count = 1; // payload still contains two encoded segments

    try testing.expectError(error.InvalidCurves, Atlas.from(testing.allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = record_key_mod.unhintedGlyph(0, 1),
            .curves = curves.view(),
        },
    }} }));
    const stats = pool.stats();
    try testing.expectEqual(@as(u32, 0), stats.pages_in_use);
    try testing.expectEqual(@as(u64, 0), stats.curve_bytes_used);
    try testing.expectEqual(@as(u64, 0), stats.band_bytes_used);
}

test "image paint records carry stable preassigned unique layers" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 3,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    var image_a = try @import("image.zig").Image.init(testing.allocator, 1, 1, &.{ 1, 2, 3, 4 });
    defer image_a.deinit();
    var image_b = try @import("image.zig").Image.init(testing.allocator, 1, 1, &.{ 5, 6, 7, 8 });
    defer image_b.deinit();

    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        .{ .geometry = .{ .key = record_key_mod.unhintedGlyph(0, 1), .curves = curves.view(), .paint = .{ .image = .{ .image = &image_a } } } },
        .{ .geometry = .{ .key = record_key_mod.unhintedGlyph(0, 2), .curves = curves.view(), .paint = .{ .image = .{ .image = &image_a } } } },
        .{ .geometry = .{ .key = record_key_mod.unhintedGlyph(0, 3), .curves = curves.view(), .paint = .{ .image = .{ .image = &image_b } } } },
    } });
    defer atlas.deinit();

    const records = atlas.paint_records.?;
    try testing.expectEqual(@as(usize, 3), records.len);
    try testing.expectEqual(@as(u32, 0), records[0].image_layer);
    try testing.expect(records[0].first_image_use);
    try testing.expectEqual(@as(u32, 0), records[1].image_layer);
    try testing.expect(!records[1].first_image_use);
    try testing.expectEqual(@as(u32, 1), records[2].image_layer);
    try testing.expect(records[2].first_image_use);

    var compacted = try atlas.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();
    var first_uses: u32 = 0;
    for (compacted.paint_records.?) |record| {
        if (record.image != null and record.first_image_use) first_uses += 1;
    }
    try testing.expectEqual(@as(u32, 2), first_uses);
}

test "from rewrites band refs to page-absolute texels" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);

    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(k0, c0),
        testGeometry(k1, c1),
    } });
    defer atlas.deinit();

    const r1 = atlas.lookupRecord(k1).?;
    const page = atlas.pages[r1.page_index];
    const band_data = page_mod.bandWordsUsed(page);
    const band_word_offset = (@as(usize, r1.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, r1.bands.glyph_x)) * 2;
    // The first h-band ref (4 header words in, so index 4) should point at r1.curve_texel.
    const ref_w0 = band_data[band_word_offset + 4];
    const ref_w1 = band_data[band_word_offset + 5];
    const CURVE_LOC_X_MASK: u16 = (1 << 12) - 1;
    const cx = ref_w0 & CURVE_LOC_X_MASK;
    const cy: u32 = ref_w1;
    const decoded = cy * CURVE_TEX_WIDTH + cx;
    try testing.expectEqual(r1.curve_texel, decoded);
}

test "atlas placement and compaction preserve band-reference curve kinds" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 3,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    const cubic_kind_bits: u16 = 2 << 14;
    const mutable_bands = @constCast(curves.band_bytes);
    mutable_bands[9] |= cubic_kind_bits;
    mutable_bands[11] |= cubic_kind_bits;
    mutable_bands[13] |= cubic_kind_bits;
    mutable_bands[15] |= cubic_kind_bits;

    const key = record_key_mod.unhintedGlyph(0, 1);
    var original = try Atlas.from(testing.allocator, pool, .{ .entries = &.{testGeometry(key, curves)} });
    defer original.deinit();
    var compacted = try original.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();

    for ([_]*const Atlas{ &original, &compacted }) |candidate| {
        const rec = candidate.lookupRecord(key).?;
        const page = candidate.pages[rec.page_index];
        const band_data = page_mod.bandWordsUsed(page);
        const band_word_offset = (@as(usize, rec.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, rec.bands.glyph_x)) * 2;
        try testing.expectEqual(cubic_kind_bits, band_data[band_word_offset + 5] & 0xc000);
    }
}

test "extend keeps original atlas valid" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, .{ .entries = &.{testGeometry(k0, c0)} });
    defer a.deinit();

    const k1 = record_key_mod.unhintedGlyph(0, 2);
    var b = try a.extend(testing.allocator, .{ .entries = &.{testGeometry(k1, c1)} });
    defer b.deinit();

    try testing.expect(a.contains(k0));
    try testing.expect(!a.contains(k1));
    try testing.expect(b.contains(k0));
    try testing.expect(b.contains(k1));
    try testing.expectEqual(@as(u32, 1), a.recordCount());
    try testing.expectEqual(@as(u32, 2), b.recordCount());

    // The original atlas's record for k0 references a page that's still
    // alive (b retained it).
    try testing.expectEqual(@as(u32, 2), page_mod.refCount(a.pages[0]));
}

test "extendInPlace commits one update as one snapshot" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 1), curves),
    } });
    defer atlas.deinit();

    const before = atlas.snapshotIdentity();
    const entries = [_]AtlasEntry{
        testGeometry(record_key_mod.unhintedGlyph(0, 2), curves),
        testGeometry(record_key_mod.unhintedGlyph(0, 3), curves),
    };
    try atlas.extendInPlace(testing.allocator, .{ .entries = &entries });

    const after = atlas.snapshotIdentity();
    try testing.expectEqual(@as(u32, 3), atlas.recordCount());
    try testing.expectEqual(before.revision + 1, after.revision);
    try testing.expectEqual(before.snapshot_id, after.parent_snapshot_id);

    try atlas.extendInPlace(testing.allocator, .{});
    try testing.expectEqualDeep(after, atlas.snapshotIdentity());
}

test "extendInPlace commits geometry and advances atomically" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var base_curves = try makeTestCurves(testing.allocator);
    defer base_curves.deinit();
    var next_curves = try makeTestCurves(testing.allocator);
    defer next_curves.deinit();
    var invalid_curves = try makeTestCurves(testing.allocator);
    defer invalid_curves.deinit();
    invalid_curves.curve_count = 1;

    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const next_key = record_key_mod.unhintedGlyph(0, 2);
    const advance_key = record_key_mod.ttAdvance(0, 2, 12 * 64);
    var atlas = try Atlas.from(testing.allocator, pool, .{
        .entries = &.{testGeometry(base_key, base_curves)},
    });
    defer atlas.deinit();

    const before = atlas.snapshotIdentity();
    try testing.expectError(error.InvalidCurves, atlas.extendInPlace(testing.allocator, .{
        .entries = &.{testGeometry(next_key, invalid_curves)},
        .tt_advances = &.{.{ .key = advance_key, .advance_26_6 = 9 * 64 }},
    }));
    try testing.expectEqualDeep(before, atlas.snapshotIdentity());
    try testing.expect(!atlas.contains(next_key));
    try testing.expect(atlas.lookupTtAdvance(advance_key) == null);

    try atlas.extendInPlace(testing.allocator, .{
        .entries = &.{testGeometry(next_key, next_curves)},
        .tt_advances = &.{.{ .key = advance_key, .advance_26_6 = 9 * 64 }},
    });
    try testing.expect(atlas.contains(next_key));
    try testing.expectEqual(@as(?i32, 9 * 64), atlas.lookupTtAdvance(advance_key));
}

test "snapshot identities distinguish roots, extensions, and branches" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    var root = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 1), c0),
    } });
    defer root.deinit();
    var child_a = try root.extend(testing.allocator, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 2), c1),
    } });
    defer child_a.deinit();
    var child_b = try root.extend(testing.allocator, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 3), c1),
    } });
    defer child_b.deinit();

    const root_id = root.snapshotIdentity();
    const a_id = child_a.snapshotIdentity();
    const b_id = child_b.snapshotIdentity();
    try testing.expect(root_id.snapshot_id != 0);
    try testing.expectEqual(root_id.lineage, a_id.lineage);
    try testing.expectEqual(root_id.lineage, b_id.lineage);
    try testing.expectEqual(root_id.snapshot_id, a_id.parent_snapshot_id);
    try testing.expectEqual(root_id.snapshot_id, b_id.parent_snapshot_id);
    try testing.expectEqual(@as(u64, 1), a_id.revision);
    try testing.expectEqual(a_id.revision, b_id.revision);
    try testing.expect(a_id.snapshot_id != b_id.snapshot_id);
}

test "aborted extension preserves its parent while keeping page publication monotonic" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();
    var root = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 1), c0),
    } });
    defer root.deinit();

    const page = root.pages[0];
    const before = page_mod.publishedWords(page);
    var builder = try Builder.initFrom(testing.allocator, pool, &root);
    try builder.insert(testGeometry(record_key_mod.unhintedGlyph(0, 2), c1));
    const after_insert = page_mod.publishedWords(page);
    try testing.expect(after_insert.curve > before.curve);
    try testing.expect(after_insert.band > before.band);
    builder.abort();

    // Published append-only bytes never move backwards: a concurrent upload
    // may already have consumed them. They remain unreachable from the parent
    // snapshot and are reclaimed with the page generation.
    try testing.expectEqual(after_insert, page_mod.publishedWords(page));
    try testing.expectEqual(@as(u32, 1), root.recordCount());
}

test "update preflight rejects late invalid input without consuming capacity" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var root_curves = try makeTestCurves(testing.allocator);
    defer root_curves.deinit();
    var next_curves = try makeTestCurves(testing.allocator);
    defer next_curves.deinit();
    var root = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 1), root_curves),
    } });
    defer root.deinit();

    const before = pool.stats();
    const update = AtlasUpdate{
        .entries = &.{
            testGeometry(record_key_mod.unhintedGlyph(0, 2), next_curves),
        },
        .tt_advances = &.{.{
            .key = record_key_mod.unhintedGlyph(0, 3),
            .advance_26_6 = 9 * 64,
        }},
    };
    for (0..8) |_| {
        try testing.expectError(
            error.InvalidRecordKey,
            root.extend(testing.allocator, update),
        );
    }
    const after = pool.stats();
    try testing.expectEqual(before.curve_bytes_used, after.curve_bytes_used);
    try testing.expectEqual(before.band_bytes_used, after.band_bytes_used);
    try testing.expectEqual(@as(u32, 1), root.recordCount());
}

test "pool-less compaction preserves page-free advances" {
    var atlas = Atlas.empty(testing.allocator);
    defer atlas.deinit();
    const keep = record_key_mod.ttAdvance(0, 1, 12 * 64);
    const drop = record_key_mod.ttAdvance(0, 2, 12 * 64);
    try atlas.recordTtAdvances(&.{
        .{ .key = keep, .advance_26_6 = 7 * 64 },
        .{ .key = drop, .advance_26_6 = 8 * 64 },
    });

    const Filter = struct {
        fn call(_: *anyopaque, key: RecordKey) bool {
            return key.b == 1;
        }
    };
    var ignored: u8 = 0;
    var compacted = try atlas.compact(
        testing.allocator,
        testing.allocator,
        .{ .context = &ignored, .keep = Filter.call },
    );
    defer compacted.deinit();
    try testing.expectEqual(@as(?i32, 7 * 64), compacted.lookupTtAdvance(keep));
    try testing.expectEqual(@as(?i32, null), compacted.lookupTtAdvance(drop));

    var target_pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 128,
    });
    defer target_pool.deinit();
    var migrated = try atlas.compactInto(
        testing.allocator,
        testing.allocator,
        target_pool,
        null,
    );
    defer migrated.deinit();
    try testing.expectEqual(@as(?i32, 7 * 64), migrated.lookupTtAdvance(keep));
    try testing.expectEqual(@as(?i32, 8 * 64), migrated.lookupTtAdvance(drop));
}

test "related atlas snapshots extend and release concurrently" {
    const allocator = std.heap.page_allocator;
    var pool = try PagePool.init(allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 16384,
        .band_words_per_page = 8192,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(allocator);
    defer curves.deinit();
    var root = try Atlas.from(allocator, pool, .{ .entries = &.{
        testGeometry(record_key_mod.unhintedGlyph(0, 1), curves),
    } });
    defer root.deinit();

    const Worker = struct {
        fn run(base: *const Atlas, source: *const GlyphCurves, worker_id: u32, failed: *std.atomic.Value(bool)) void {
            for (0..64) |i| {
                const glyph_id: u16 = @intCast(i + 2);
                var child = base.extend(std.heap.page_allocator, .{ .entries = &.{
                    testGeometry(record_key_mod.unhintedGlyph(worker_id, glyph_id), source.*),
                } }) catch {
                    failed.store(true, .release);
                    return;
                };
                if (child.recordCount() != 2 or child.lookupRecord(record_key_mod.unhintedGlyph(worker_id, glyph_id)) == null) {
                    failed.store(true, .release);
                    child.deinit();
                    return;
                }
                child.deinit();
            }
        }
    };

    var failed = std.atomic.Value(bool).init(false);
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &root, &curves, @as(u32, @intCast(i + 1)), &failed });
    }
    for (threads) |thread| thread.join();

    try testing.expect(!failed.load(.acquire));
    try testing.expectEqual(@as(u32, 1), root.recordCount());
    try testing.expectEqual(page_mod.PublishedWords{ .curve = 8224, .band = 4112 }, page_mod.publishedWords(root.pages[0]));
}

test "an empty composite base promotes its first visible extra layer" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var visible = try makeTestCurves(testing.allocator);
    defer visible.deinit();
    const key = record_key_mod.unhintedGlyph(0, 77);
    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = GeometryView.empty(),
            .extra_layers = &.{.{
                .curves = visible.view(),
                .paint = .{ .solid = .{ 0.2, 0.4, 0.6, 1 } },
            }},
        },
    }} });
    defer atlas.deinit();

    try testing.expectEqual(@as(u16, 2), atlas.lookupRecord(key).?.curve_count);
    try testing.expectEqual(@as(u16, 1), atlas.lookupPaintRecord(key).?.layer_count);
}

test "TT advance batches are allocation-failure atomic" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    var atlas = Atlas.empty(failing.allocator());
    defer atlas.deinit();

    try testing.expectError(error.OutOfMemory, atlas.recordTtAdvances(&.{
        .{ .key = record_key_mod.ttAdvance(0, 1, 12), .advance_26_6 = 100 },
        .{ .key = record_key_mod.ttAdvance(0, 2, 12), .advance_26_6 = 200 },
    }));
    try testing.expectEqual(@as(u32, 0), atlas.ttAdvanceCount());
}

test "extend dedups keys against existing atlas" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, .{ .entries = &.{testGeometry(k0, c0)} });
    defer a.deinit();

    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();
    var b = try a.extend(testing.allocator, .{
        .entries = &.{
            testGeometry(k0, c1), // conflict — existing wins
        },
    });
    defer b.deinit();

    try testing.expectEqual(@as(u32, 1), b.recordCount());
    const old_rec = a.lookupRecord(k0).?;
    const new_rec = b.lookupRecord(k0).?;
    try testing.expectEqual(old_rec.curve_texel, new_rec.curve_texel);
}

test "one immutable autohint record serves multiple sizes and policies" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var base_curves = try makeTestCurves(testing.allocator);
    defer base_curves.deinit();

    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const analysis_key = record_key_mod.autohintGlyph(0, 1);
    const blues = [_]@import("font/autohint/blue.zig").FeatureZone{.{ .ref = 0, .shoot = -0.01 }};
    const x = [_]autohint.FeatureEdge{.{ .pos = 0.1, .width = 0.08, .stem = -1, .blue = -1, .flags = .{ .round = false } }};
    const y = [_]autohint.FeatureEdge{.{ .pos = 0.5, .width = 0.07, .stem = -1, .blue = 0, .flags = .{ .round = true } }};
    const analysis = AutohintAnalysis{
        .font = .{ .blues = &blues, .std_x = 0.08, .std_y = 0.07 },
        .glyph = .{ .x = &x, .y = &y, .left = 0.02 },
    };

    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(base_key, base_curves),
        .{ .autohint = .{ .key = analysis_key, .base_key = base_key, .analysis = analysis } },
    } });
    defer atlas.deinit();

    const pages_before = atlas.pageCount();
    const slab_len_before = atlas.layer_info_data.?.len;
    const root_12_light = atlas.lookupRecord(record_key_mod.autohintGlyph(0, 1)).?;
    // PPEM and policy are synthetic draw-time inputs: neither changes the key
    // used for this second lookup.
    const ppem_26_6: u32 = 24 * 64;
    const policy = @import("font/autohint/policy.zig").AutohintPolicy{ .x = .{ .@"align" = .grid } };
    _ = ppem_26_6;
    _ = policy;
    const root_24_grid = atlas.lookupRecord(record_key_mod.autohintGlyph(0, 1)).?;

    try testing.expectEqual(@as(u32, 2), atlas.recordCount());
    try testing.expectEqual(pages_before, atlas.pageCount());
    try testing.expectEqual(slab_len_before, atlas.layer_info_data.?.len);
    try testing.expectEqual(root_12_light, root_24_grid);
    try testing.expectEqual(atlas.lookupRecord(base_key).?.curve_texel, root_24_grid.curve_texel);
    try testing.expect(atlas.lookupAutohintRecord(analysis_key) != null);
    try testing.expect(atlas.lookupAutohintRecord(base_key) == null);
}

test "autohint entry with a missing base key errors" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    const analysis_key = record_key_mod.autohintGlyph(0, 1);
    const analysis = AutohintAnalysis{
        .font = .{ .blues = &.{}, .std_x = 0, .std_y = 0 },
        .glyph = .{ .x = &.{}, .y = &.{}, .left = 0 },
    };
    try testing.expectError(error.MissingAutohintBase, Atlas.from(testing.allocator, pool, .{ .entries = &.{
        .{ .autohint = .{
            .key = analysis_key,
            .base_key = record_key_mod.unhintedGlyph(0, 1),
            .analysis = analysis,
        } },
    } }));
}

test "autohint entry rejects a noncanonical base alias" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    const canonical = record_key_mod.unhintedGlyph(0, 1);
    const alias = record_key_mod.unhintedGlyph(0, 2);
    const analysis_key = record_key_mod.autohintGlyph(0, 1);
    try testing.expectError(error.InvalidRecordKey, Atlas.from(
        testing.allocator,
        pool,
        .{ .entries = &.{
            testGeometry(canonical, curves),
            testGeometry(alias, curves),
            .{ .autohint = .{
                .key = analysis_key,
                .base_key = alias,
                .analysis = .{
                    .font = .{ .blues = &.{}, .std_x = 0, .std_y = 0 },
                    .glyph = .{ .x = &.{}, .y = &.{}, .left = 0 },
                },
            } },
        } },
    ));
}

test "autohint entry rejects oversized immutable analysis" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var base_curves = try makeTestCurves(testing.allocator);
    defer base_curves.deinit();
    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const FeatureEdge = autohint.FeatureEdge;
    const max_knots = autohint.max_features_per_axis;
    const too_many = [_]FeatureEdge{.{ .pos = 0, .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } }} ** (max_knots + 1);
    try testing.expectError(error.InvalidAutohintAnalysis, Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(base_key, base_curves),
        .{ .autohint = .{
            .key = record_key_mod.autohintGlyph(0, 1),
            .base_key = base_key,
            .analysis = .{
                .font = .{ .blues = &.{}, .std_x = 0, .std_y = 0 },
                .glyph = .{ .x = &too_many, .y = &.{}, .left = 0 },
            },
        } },
    } }));
}

test "deinit releases pages back to the pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);

    {
        var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = &.{testGeometry(k0, c0)} });
        defer atlas.deinit();
        try testing.expectError(error.OutOfLayers, page_pool_mod.acquire(pool));
    }
    // Atlas has been deinit'd; pool should be drained again.
    const reacquired = try page_pool_mod.acquire(pool);
    page_pool_mod.release(pool, reacquired);
}

test "atlas + font extract: end-to-end smoke test" {
    const font_mod = @import("font.zig");
    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);

    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var entries: std.ArrayList(AtlasEntry) = .empty;
    defer entries.deinit(testing.allocator);

    var owned: std.ArrayList(GlyphCurves) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(testing.allocator);
    }

    const codes = [_]u32{ 'A', 'B', 'C', 'M', 'a', 'g', 'o' };
    for (codes) |cp| {
        const gid = try font.glyphIndex(cp);
        const curves = try font.extractCurves(testing.allocator, testing.allocator, gid);
        try owned.append(testing.allocator, curves);
        try entries.append(testing.allocator, testGeometry(
            record_key_mod.unhintedGlyph(0, gid),
            owned.items[owned.items.len - 1],
        ));
    }

    var atlas = try Atlas.from(testing.allocator, pool, .{ .entries = entries.items });
    defer atlas.deinit();

    try testing.expectEqual(@as(u32, codes.len), atlas.recordCount());
    for (codes) |cp| {
        const gid = try font.glyphIndex(cp);
        const key = record_key_mod.unhintedGlyph(0, gid);
        const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
        try testing.expect(rec.curve_count > 0);
    }
}

test "compact preserves keys" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);
    var original = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(k0, c0),
        testGeometry(k1, c1),
    } });
    defer original.deinit();

    var compacted = try original.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();

    try testing.expectEqual(original.recordCount(), compacted.recordCount());
    try testing.expect(compacted.contains(k0));
    try testing.expect(compacted.contains(k1));

    // Compaction lays records out into fresh pages from the pool, so
    // bbox/metadata round-trip but curve_texel may differ.
    const orig_r0 = original.lookupRecord(k0).?;
    const comp_r0 = compacted.lookupRecord(k0).?;
    try testing.expectEqual(orig_r0.curve_count, comp_r0.curve_count);
    try testing.expectEqual(orig_r0.bands.h_band_count, comp_r0.bands.h_band_count);
    try testing.expectEqual(orig_r0.bands.v_band_count, comp_r0.bands.v_band_count);
}

test "compactInto migrates without source-pool headroom" {
    var source_pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer source_pool.deinit();
    var target_pool = try PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer target_pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    const key = record_key_mod.unhintedGlyph(0, 1);
    var source = try Atlas.from(testing.allocator, source_pool, .{
        .entries = &.{testGeometry(key, curves)},
    });
    defer source.deinit();
    try testing.expectEqual(@as(u32, 0), source_pool.stats().pages_free);

    var migrated = try source.compactInto(
        testing.allocator,
        testing.allocator,
        target_pool,
        null,
    );
    defer migrated.deinit();

    try testing.expect(source.contains(key));
    try testing.expect(migrated.contains(key));
    try testing.expectEqual(@as(u32, 0), source_pool.stats().pages_free);
    try testing.expectEqual(@as(u32, 0), target_pool.stats().pages_free);
    try testing.expect(source.pool.? != migrated.pool.?);
}

test "compact carries paint layers, autohint analyses, and advances byte-for-byte" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var base_curves = try makeTestCurves(testing.allocator);
    defer base_curves.deinit();
    var layer_curves = try makeTestCurves(testing.allocator);
    defer layer_curves.deinit();

    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const colr_key = record_key_mod.unhintedGlyph(0, 2);
    const auto_key = record_key_mod.autohintGlyph(0, 1);
    const tt_key = record_key_mod.ttHintedGlyph(0, 1, 13 * 64);
    const advance_key = record_key_mod.ttAdvance(0, 1, 13 * 64);

    const x_edges = [_]autohint.FeatureEdge{.{
        .pos = 0.25,
        .width = 0.1,
        .stem = -1,
        .blue = -1,
        .flags = .{ .round = true },
    }};
    var original = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(base_key, base_curves),
        .{ .geometry = .{
            .key = colr_key,
            .curves = base_curves.view(),
            .paint = .{ .solid = .{ 1, 0, 0, 1 } },
            .extra_layers = &.{.{ .curves = layer_curves.view(), .paint = .{ .solid = .{ 0, 1, 0, 0.5 } } }},
        } },
        .{ .autohint = .{
            .key = auto_key,
            .base_key = base_key,
            .analysis = .{
                .font = .{ .blues = &.{}, .std_x = 0.08, .std_y = 0.09 },
                .glyph = .{ .x = &x_edges, .y = &.{}, .left = 0.02 },
            },
        } },
        testGeometry(tt_key, base_curves),
    } });
    defer original.deinit();
    try original.recordTtAdvance(advance_key, 7 * 64);

    var compacted = try original.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();

    // Composite paint: layer count and the placement-independent payload
    // texels (paint colors, tags) survive verbatim.
    const orig_paint = original.lookupPaintRecord(colr_key).?;
    const comp_paint = compacted.lookupPaintRecord(colr_key).?;
    try testing.expectEqual(orig_paint.layer_count, comp_paint.layer_count);
    const texels_per = 6;
    const orig_slab = original.layer_info_data.?;
    const comp_slab = compacted.layer_info_data.?;
    const orig_base_texel = (@as(usize, orig_paint.info_y) * original.layer_info_width + orig_paint.info_x);
    const comp_base_texel = (@as(usize, comp_paint.info_y) * compacted.layer_info_width + comp_paint.info_x);
    var layer: usize = 0;
    while (layer < orig_paint.layer_count) : (layer += 1) {
        // Composite header + per-layer records: payload texels 2..6.
        const orig_layer = orig_base_texel + 1 + layer * texels_per;
        const comp_layer = comp_base_texel + 1 + layer * texels_per;
        try testing.expectEqualSlices(
            f32,
            orig_slab[(orig_layer + 2) * 4 .. (orig_layer + texels_per) * 4],
            comp_slab[(comp_layer + 2) * 4 .. (comp_layer + texels_per) * 4],
        );
    }

    // Autohint: record survives, aliases the base (no duplicated curves),
    // and the feature payload round-trips exactly.
    try testing.expect(compacted.lookupAutohintRecord(auto_key) != null);
    const comp_auto_rec = compacted.lookupRecord(auto_key).?;
    const comp_base_rec = compacted.lookupRecord(base_key).?;
    try testing.expectEqual(comp_base_rec.curve_texel, comp_auto_rec.curve_texel);
    const auto_info = compacted.lookupAutohintRecord(auto_key).?;
    const auto_off = (@as(usize, auto_info.info_y) * compacted.layer_info_width + auto_info.info_x) * 4;
    const comp_x = (try @import("format/autohint_record.zig").decode(comp_slab, auto_off)).glyph.x;
    try testing.expectEqual(@as(usize, 1), comp_x.len);
    try testing.expectEqual(x_edges[0].pos, comp_x[0].pos);
    try testing.expectEqual(x_edges[0].width, comp_x[0].width);

    // TT-hinted band record and the advance value both survive.
    try testing.expect(compacted.lookupTtHintedRecord(tt_key) != null);
    try testing.expectEqual(@as(?i32, 7 * 64), compacted.lookupTtAdvance(advance_key));
}

test "filtered compact evicts records and closes dependencies" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const keep_base = record_key_mod.unhintedGlyph(0, 1);
    const drop_key = record_key_mod.unhintedGlyph(0, 2);
    const keep_auto = record_key_mod.autohintGlyph(0, 1);
    const keep_advance = record_key_mod.ttAdvance(0, 1, 13 * 64);
    const drop_advance = record_key_mod.ttAdvance(0, 2, 13 * 64);

    var original = try Atlas.from(testing.allocator, pool, .{ .entries = &.{
        testGeometry(keep_base, c0),
        testGeometry(drop_key, c1),
        .{ .autohint = .{
            .key = keep_auto,
            .base_key = keep_base,
            .analysis = .{
                .font = .{ .blues = &.{}, .std_x = 0.1, .std_y = 0 },
                .glyph = .{ .x = &.{}, .y = &.{}, .left = 0 },
            },
        } },
    } });
    defer original.deinit();
    try original.recordTtAdvance(keep_advance, 6 * 64);
    try original.recordTtAdvance(drop_advance, 6 * 64);

    // Keep only the autohint record and one advance: the base glyph must
    // come along via dependency closure; everything else is evicted.
    const Keeps = struct {
        fn keep(_: *anyopaque, key: RecordKey) bool {
            return key.namespace == record_key_mod.ns.autohint_glyph or
                (key.namespace == record_key_mod.ns.tt_advance and key.b == 1);
        }
    };
    var ctx: u8 = 0;
    var compacted = try original.compact(testing.allocator, testing.allocator, .{
        .context = @ptrCast(&ctx),
        .keep = Keeps.keep,
    });
    defer compacted.deinit();

    try testing.expect(compacted.contains(keep_auto));
    try testing.expect(compacted.contains(keep_base));
    try testing.expect(!compacted.contains(drop_key));
    try testing.expectEqual(@as(?i32, 6 * 64), compacted.lookupTtAdvance(keep_advance));
    try testing.expect(compacted.lookupTtAdvance(drop_advance) == null);
    try testing.expectEqual(@as(u32, 1), compacted.ttAdvanceCount());
}
