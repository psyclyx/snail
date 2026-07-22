//! Value-typed atlas: the store of prepared glyph records. Holds
//! refcounted page references plus a key→record lookup table.
//! Construction and update operations return new atlases, leaving the
//! input atlas untouched.
//!
//! ## Capacity model
//!
//! The `PagePool` is the caller's residency budget: `max_layers` pages of
//! fixed curve/band capacity, sized once at init. Recording is incremental
//! and idempotent — an app can add glyphs for its whole lifetime and each
//! `record*Run` costs only the genuinely new records — but nothing is ever
//! evicted implicitly. When the pool is exhausted, recording fails with
//! `error.OutOfLayers`; that error is the caller's eviction moment, not a
//! bug. The recovery primitive is `compact` with a `RecordFilter`: rebuild
//! the store keeping only the working set (an LRU over touched keys, a
//! frame-tag sweep — retention policy is the caller's). Because compacting
//! acquires new pages before the old atlas releases its own, keep headroom:
//! trigger eviction while the pool still has at least the compacted
//! result's page count free, rather than at hard exhaustion.
//!
//! Two record kinds change the budget math: autohint records are
//! resolution-independent (one per glyph, ever — the mode to prefer under
//! continuous zoom), while TT-hinted records are per (glyph, ppem) and
//! accumulate with every distinct size (`ns.tt_advance` values are
//! page-free and never pressure the pool). `src/support/working_set.zig`
//! is the worked example of a bounded-residency policy over this model.
//!
//! See the README's capacity-model section for the public eviction recipe.

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

pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const AtlasRecord = atlas_record_mod.AtlasRecord;
pub const GlyphBandEntry = atlas_record_mod.GlyphBandEntry;
pub const RecordKey = record_key_mod.RecordKey;
pub const GlyphCurves = curves_mod.GlyphCurves;
pub const Paint = paint_mod.Paint;
/// A reference from a layer-info paint record to the image it samples.
/// `texel_offset` is the flat texel index where the image-paint header
/// lives in the atlas's layer-info buffer; backends use this to patch
/// the (layer, uv_scale) view into the cache's image array per upload.
pub const PaintImageRecord = struct {
    image: *const @import("image.zig").Image,
    texel_offset: u32,
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
pub const PaintRecordInfo = struct {
    info_x: u16,
    info_y: u16,
    layer_count: u16 = 1,
};

/// Immutable, target-free analysis for an autohint entry. All values are
/// em-normalized. The slices are borrowed by `from`/`extend`; the builder
/// copies them into the layer-info slab during the build call.
pub const AutohintAnalysis = struct {
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
};

const CURVE_TEX_WIDTH = curve_tex_format.TEX_WIDTH;
const CURVE_SEGMENT_TEXELS = curve_tex_format.SEGMENT_TEXELS;
const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * 4;
const BAND_TEX_WIDTH = band_tex_format.TEX_WIDTH;
const BAND_TEX_WIDTH_USIZE: usize = BAND_TEX_WIDTH;

/// Pair handed to `from` / `extend` to insert one keyed shape. When
/// `paint` is non-null the atlas also allocates a layer_info record
/// for the entry and remembers (info_x, info_y) in `paint_lookup` so
/// emit can encode a special-layer instance instead of a regular one.
///
/// `extra_layers` extends a single-paint entry into a multi-layer
/// composite group. With `extra_layers.len > 0` the atlas emits a
/// composite-group header followed by `1 + extra_layers.len` paint
/// records; the shader walks them per fragment and composites under
/// `composite_mode`. `.fill_stroke_inside` is the inside-stroke trick
/// (first two layers' coverages are AND'd); `.source_over` does standard
/// back-to-front porter-duff.
pub const Entry = struct {
    key: RecordKey,
    curves: GlyphCurves,
    paint: ?Paint = null,
    /// Per-entry winding rule. Geometry property of the path/glyph itself
    /// (a path author either intends non-zero or even-odd; fonts are
    /// always non-zero). Carried into the paint record so the shader
    /// picks it up per-fragment — there is no per-frame fill rule.
    fill_rule: @import("paint.zig").FillRule = .non_zero,
    extra_layers: []const Layer = &.{},
    composite_mode: CompositeMode = .source_over,
    /// When set, the atlas writes one immutable autohint feature record and
    /// remembers it in `autohint_lookup`. PPEM and fitting policy are not
    /// stored in the atlas. Mutually usable with `paint`.
    autohint: ?AutohintAnalysis = null,
    /// For an autohint entry, the key of an already-inserted unhinted base
    /// glyph whose curves+bands this warp samples. When set, the entry
    /// places NO curves of its own (`curves` is ignored) — it aliases the
    /// base record's placement — so the analysis and outline share one
    /// curve copy. The base key must be inserted earlier in
    /// the same `from`/`extend` call or already present in the parent atlas.
    /// Only meaningful together with `autohint`.
    autohint_base: ?RecordKey = null,
};

pub const Layer = struct {
    curves: GlyphCurves,
    paint: Paint,
    fill_rule: @import("paint.zig").FillRule = .non_zero,
};

pub const CompositeMode = paint_mod.CompositeMode;

pub const InsertError = std.mem.Allocator.Error || PagePool.AcquireError || PagePool.IdentityError || error{
    RecordTooLargeForPage,
    InvalidCurves,
    ImageCountOverflow,
    AtlasRevisionExhausted,
    NoPool,
    MissingAutohintBase,
    InvalidAutohintAnalysis,
    LayerInfoTooLarge,
    CorruptPaintRecord,
};

pub const Atlas = struct {
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
    /// Refcounted page references. Index into this slice is what
    /// `AtlasRecord.page_index` refers to.
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
    /// never uploaded. Written by `recordTtHintRun` / `recordTtAdvanceRun`.
    tt_advance_lookup: TtAdvanceLookup,
    /// One slot per emitted paint record (in insertion order). The slot
    /// is populated only for `.image` paints — gradient/solid records map
    /// to `null`. The software renderer's `DeviceAtlas.upload`
    /// hands this to `preparePathLayerInfoRecords`; the GPU upload path
    /// patches the matching layer-info texel in place. Images themselves
    /// are caller-owned references; the atlas only borrows.
    paint_image_records: ?[]?PaintImageRecord = null,

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
        var atlas = empty(allocator);
        atlas.pool = pool;
        atlas.snapshot_id = try pool.nextAtlasSnapshotId();
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
            for (self.pages) |p| pool.release(p);
        } else {
            std.debug.assert(self.pages.len == 0);
        }
        if (self.pages.len > 0) self.allocator.free(self.pages);
        if (self.layer_info_data) |d| self.allocator.free(d);
        if (self.paint_image_records) |records| self.allocator.free(records);
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
    pub fn recordTtAdvance(self: *Atlas, key: RecordKey, advance_26_6: i32) std.mem.Allocator.Error!void {
        if (self.tt_advance_lookup.contains(key)) return;
        const next = try self.tt_advance_lookup.put(key, advance_26_6);
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

    /// Pack the entries into a fresh atlas backed by `pool`. Existing keys
    /// in `entries` (duplicates) keep the first occurrence.
    pub fn from(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        entries: []const Entry,
    ) InsertError!Atlas {
        var builder = try Builder.init(allocator, pool);
        errdefer builder.abort();

        for (entries) |entry| {
            try builder.insert(entry);
        }

        return builder.finish();
    }

    /// Return a persistent snapshot containing the existing records plus new
    /// `entries`. The original atlas remains valid and logically unchanged.
    pub fn extend(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        entries: []const Entry,
    ) InsertError!Atlas {
        const pool = self.pool orelse return error.NoPool; // empty atlas, no pool to allocate from
        var builder = try Builder.initFrom(allocator, pool, self);
        errdefer builder.abort();

        for (entries) |entry| {
            try builder.insert(entry);
        }

        return builder.finish();
    }

    /// Replace this atlas with one extension while preserving `extend`'s
    /// failure atomicity: on error `self` remains valid and unchanged.
    /// Empty entry slices are a no-op.
    ///
    /// Each non-empty call commits a persistent snapshot and therefore copies
    /// the atlas's flat page-pointer and paint-side-data arrays once. Do not
    /// call this in a one-entry loop for bulk ingestion; pass the entries in
    /// one slice, or use `extendBatchesInPlace` when producers naturally
    /// supply several slices.
    pub fn extendInPlace(
        self: *Atlas,
        allocator: std.mem.Allocator,
        entries: []const Entry,
    ) InsertError!void {
        if (entries.len == 0) return;
        return self.extendBatchesInPlace(allocator, &.{entries});
    }

    /// Commit several entry slices in one builder transaction. This avoids
    /// the repeated O(existing flat metadata) copies caused by a loop of
    /// `extendInPlace` calls, without requiring callers to allocate and flatten
    /// a temporary entry array. All slices are consumed synchronously and the
    /// operation is failure-atomic. A list containing only empty slices is a
    /// no-op and does not mint a new snapshot identity.
    pub fn extendBatchesInPlace(
        self: *Atlas,
        allocator: std.mem.Allocator,
        batches: []const []const Entry,
    ) InsertError!void {
        var has_entries = false;
        for (batches) |entries| {
            if (entries.len != 0) {
                has_entries = true;
                break;
            }
        }
        if (!has_entries) return;

        const pool = self.pool orelse return error.NoPool;
        var builder = try Builder.initFrom(allocator, pool, self);
        errdefer builder.abort();
        for (batches) |entries| {
            for (entries) |entry| try builder.insert(entry);
        }

        const grown = try builder.finish();
        self.deinit();
        self.* = grown;
    }

    /// Rebuild the store, freshly packed into the minimum number of pages.
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
    /// Needs headroom: new pages are acquired from the same pool *before*
    /// the original atlas releases its own, so compacting requires at
    /// least the compacted result's page count free. Budget the pool with
    /// a reserve (see the capacity model notes on `PagePool`), or compact
    /// before the pool is fully exhausted.
    ///
    /// The original atlas is unaffected and continues to work.
    pub fn compact(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        filter: ?RecordFilter,
    ) InsertError!Atlas {
        const pool = self.pool orelse return Atlas.empty(allocator);
        var builder = try Builder.init(allocator, pool);
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
};

/// Record-selection closure for `Atlas.compact` — the eviction hook. The
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

    // band header = 1 h-band + 1 v-band = 2 texels = 4 u16.
    // band refs = 2 refs per band * 2 bands = 4 texels = 8 u16. Plus 4
    // header words.
    const band_bytes = try allocator.alloc(u16, 12);
    band_bytes[0] = 2; // h-band 0 count
    band_bytes[1] = 2; // h-band 0 offset (from glyph_loc, in texels) = 2
    band_bytes[2] = 2; // v-band 0 count
    band_bytes[3] = 4; // v-band 0 offset = 4

    // h-band refs at curve texel 0 and 4 (i.e., curve 0 and curve 1).
    band_bytes[4] = 0; // cx=0, first_member_band=0
    band_bytes[5] = 0; // cy=0
    band_bytes[6] = 4; // cx=4
    band_bytes[7] = 0;
    // v-band refs (same).
    band_bytes[8] = 0;
    band_bytes[9] = 0;
    band_bytes[10] = 4;
    band_bytes[11] = 0;

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

test "from packs entries into pages and records lookup" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
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
    const entries = [_]Entry{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    };

    var atlas = try Atlas.from(testing.allocator, pool, &entries);
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
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    curves.curve_count = 1; // payload still contains two encoded segments

    try testing.expectError(error.InvalidCurves, Atlas.from(testing.allocator, pool, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 1),
        .curves = curves,
    }}));
    const stats = pool.stats();
    try testing.expectEqual(@as(u32, 0), stats.pages_in_use);
    try testing.expectEqual(@as(u64, 0), stats.curve_bytes_used);
    try testing.expectEqual(@as(u64, 0), stats.band_bytes_used);
}

test "image paint records carry stable preassigned unique layers" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 3,
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

    var atlas = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = record_key_mod.unhintedGlyph(0, 1), .curves = curves, .paint = .{ .image = .{ .image = &image_a } } },
        .{ .key = record_key_mod.unhintedGlyph(0, 2), .curves = curves, .paint = .{ .image = .{ .image = &image_a } } },
        .{ .key = record_key_mod.unhintedGlyph(0, 3), .curves = curves, .paint = .{ .image = .{ .image = &image_b } } },
    });
    defer atlas.deinit();

    const records = atlas.paint_image_records.?;
    try testing.expectEqual(@as(usize, 3), records.len);
    try testing.expectEqual(@as(u32, 0), records[0].?.image_layer);
    try testing.expect(records[0].?.first_image_use);
    try testing.expectEqual(@as(u32, 0), records[1].?.image_layer);
    try testing.expect(!records[1].?.first_image_use);
    try testing.expectEqual(@as(u32, 1), records[2].?.image_layer);
    try testing.expect(records[2].?.first_image_use);

    var compacted = try atlas.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();
    var first_uses: u32 = 0;
    for (compacted.paint_image_records.?) |maybe_record| {
        if (maybe_record) |record| {
            if (record.first_image_use) first_uses += 1;
        }
    }
    try testing.expectEqual(@as(u32, 2), first_uses);
}

test "from rewrites band refs to page-absolute texels" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
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

    var atlas = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    });
    defer atlas.deinit();

    const r1 = atlas.lookupRecord(k1).?;
    const page = atlas.pages[r1.page_index];
    const band_word_offset = (@as(usize, r1.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, r1.bands.glyph_x)) * 2;
    // The first h-band ref (4 header words in, so index 4) should point at r1.curve_texel.
    const ref_w0 = page.band.data[band_word_offset + 4];
    const ref_w1 = page.band.data[band_word_offset + 5];
    const CURVE_LOC_X_MASK: u16 = (1 << 12) - 1;
    const cx = ref_w0 & CURVE_LOC_X_MASK;
    const cy: u32 = ref_w1;
    const decoded = cy * CURVE_TEX_WIDTH + cx;
    try testing.expectEqual(r1.curve_texel, decoded);
}

test "atlas placement and compaction preserve band-reference curve kinds" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 3,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    const cubic_kind_bits: u16 = 2 << 14;
    const mutable_bands = @constCast(curves.band_bytes);
    mutable_bands[5] |= cubic_kind_bits;
    mutable_bands[7] |= cubic_kind_bits;
    mutable_bands[9] |= cubic_kind_bits;
    mutable_bands[11] |= cubic_kind_bits;

    const key = record_key_mod.unhintedGlyph(0, 1);
    var original = try Atlas.from(testing.allocator, pool, &.{.{ .key = key, .curves = curves }});
    defer original.deinit();
    var compacted = try original.compact(testing.allocator, testing.allocator, null);
    defer compacted.deinit();

    for ([_]*const Atlas{ &original, &compacted }) |candidate| {
        const rec = candidate.lookupRecord(key).?;
        const page = candidate.pages[rec.page_index];
        const band_word_offset = (@as(usize, rec.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, rec.bands.glyph_x)) * 2;
        try testing.expectEqual(cubic_kind_bits, page.band.data[band_word_offset + 5] & 0xc000);
    }
}

test "extend keeps original atlas valid" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
    defer a.deinit();

    const k1 = record_key_mod.unhintedGlyph(0, 2);
    var b = try a.extend(testing.allocator, &.{.{ .key = k1, .curves = c1 }});
    defer b.deinit();

    try testing.expect(a.contains(k0));
    try testing.expect(!a.contains(k1));
    try testing.expect(b.contains(k0));
    try testing.expect(b.contains(k1));
    try testing.expectEqual(@as(u32, 1), a.recordCount());
    try testing.expectEqual(@as(u32, 2), b.recordCount());

    // The original atlas's record for k0 references a page that's still
    // alive (b retained it).
    try testing.expectEqual(@as(u32, 2), a.pages[0].refcount.load(.acquire));
}

test "extendBatchesInPlace commits many slices as one snapshot" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var curves = try makeTestCurves(testing.allocator);
    defer curves.deinit();
    var atlas = try Atlas.from(testing.allocator, pool, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 1),
        .curves = curves,
    }});
    defer atlas.deinit();

    const before = atlas.snapshotIdentity();
    const batch_a = [_]Entry{.{
        .key = record_key_mod.unhintedGlyph(0, 2),
        .curves = curves,
    }};
    const batch_b = [_]Entry{.{
        .key = record_key_mod.unhintedGlyph(0, 3),
        .curves = curves,
    }};
    const batches = [_][]const Entry{ &batch_a, &.{}, &batch_b };
    try atlas.extendBatchesInPlace(testing.allocator, &batches);

    const after = atlas.snapshotIdentity();
    try testing.expectEqual(@as(u32, 3), atlas.recordCount());
    try testing.expectEqual(before.revision + 1, after.revision);
    try testing.expectEqual(before.snapshot_id, after.parent_snapshot_id);

    const only_empty = [_][]const Entry{ &.{}, &.{} };
    try atlas.extendBatchesInPlace(testing.allocator, &only_empty);
    try testing.expectEqualDeep(after, atlas.snapshotIdentity());
}

test "snapshot identities distinguish roots, extensions, and branches" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    var root = try Atlas.from(testing.allocator, pool, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 1),
        .curves = c0,
    }});
    defer root.deinit();
    var child_a = try root.extend(testing.allocator, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 2),
        .curves = c1,
    }});
    defer child_a.deinit();
    var child_b = try root.extend(testing.allocator, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 3),
        .curves = c1,
    }});
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

test "aborted extension restores its parent's shared page tail" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();
    var root = try Atlas.from(testing.allocator, pool, &.{.{
        .key = record_key_mod.unhintedGlyph(0, 1),
        .curves = c0,
    }});
    defer root.deinit();

    const page = root.pages[0];
    const curve_before = page.curve.usedWords();
    const band_before = page.band.usedWords();
    var builder = try Builder.initFrom(testing.allocator, pool, &root);
    try builder.insert(.{
        .key = record_key_mod.unhintedGlyph(0, 2),
        .curves = c1,
    });
    try testing.expect(page.curve.usedWords() > curve_before);
    try testing.expect(page.band.usedWords() > band_before);
    builder.abort();

    try testing.expectEqual(curve_before, page.curve.usedWords());
    try testing.expectEqual(band_before, page.band.usedWords());
    try testing.expectEqual(@as(u32, 1), root.recordCount());
}

test "extend dedups keys against existing atlas" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
    defer a.deinit();

    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();
    var b = try a.extend(testing.allocator, &.{
        .{ .key = k0, .curves = c1 }, // conflict — existing wins
    });
    defer b.deinit();

    try testing.expectEqual(@as(u32, 1), b.recordCount());
    const old_rec = a.lookupRecord(k0).?;
    const new_rec = b.lookupRecord(k0).?;
    try testing.expectEqual(old_rec.curve_texel, new_rec.curve_texel);
}

test "one immutable autohint record serves multiple sizes and policies" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
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

    var atlas = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = base_key, .curves = base_curves },
        .{ .key = analysis_key, .curves = GlyphCurves.empty(testing.allocator), .autohint = analysis, .autohint_base = base_key },
    });
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
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    const analysis_key = record_key_mod.autohintGlyph(0, 1);
    const analysis = AutohintAnalysis{
        .font = .{ .blues = &.{}, .std_x = 0, .std_y = 0 },
        .glyph = .{ .x = &.{}, .y = &.{}, .left = 0 },
    };
    try testing.expectError(error.MissingAutohintBase, Atlas.from(testing.allocator, pool, &.{
        .{ .key = analysis_key, .curves = GlyphCurves.empty(testing.allocator), .autohint = analysis, .autohint_base = record_key_mod.unhintedGlyph(0, 99) },
    }));
}

test "autohint entry rejects oversized immutable analysis" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var base_curves = try makeTestCurves(testing.allocator);
    defer base_curves.deinit();
    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const FeatureEdge = autohint.FeatureEdge;
    const max_knots = @import("font/autohint/warp.zig").max_knots;
    const too_many = [_]FeatureEdge{.{ .pos = 0, .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } }} ** (max_knots + 1);
    try testing.expectError(error.InvalidAutohintAnalysis, Atlas.from(testing.allocator, pool, &.{
        .{ .key = base_key, .curves = base_curves },
        .{
            .key = record_key_mod.autohintGlyph(0, 1),
            .curves = GlyphCurves.empty(testing.allocator),
            .autohint = .{
                .font = .{ .blues = &.{}, .std_x = 0, .std_y = 0 },
                .glyph = .{ .x = &too_many, .y = &.{}, .left = 0 },
            },
            .autohint_base = base_key,
        },
    }));
}

test "deinit releases pages back to the pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);

    {
        var atlas = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
        defer atlas.deinit();
        try testing.expectError(error.OutOfLayers, pool.acquire());
    }
    // Atlas has been deinit'd; pool should be drained again.
    const reacquired = try pool.acquire();
    pool.release(reacquired);
}

test "atlas + font extract: end-to-end smoke test" {
    const font_mod = @import("font.zig");
    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var entries: std.ArrayList(Entry) = .empty;
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
        try entries.append(testing.allocator, .{
            .key = record_key_mod.unhintedGlyph(0, gid),
            .curves = owned.items[owned.items.len - 1],
        });
    }

    var atlas = try Atlas.from(testing.allocator, pool, entries.items);
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
        .max_layers = 4,
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
    var original = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    });
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

test "compact carries paint layers, autohint analyses, and advances byte-for-byte" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
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
    var original = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = base_key, .curves = base_curves },
        .{
            .key = colr_key,
            .curves = base_curves,
            .paint = .{ .solid = .{ 1, 0, 0, 1 } },
            .extra_layers = &.{.{ .curves = layer_curves, .paint = .{ .solid = .{ 0, 1, 0, 0.5 } } }},
        },
        .{
            .key = auto_key,
            .curves = GlyphCurves.empty(testing.allocator),
            .autohint = .{
                .font = .{ .blues = &.{}, .std_x = 0.08, .std_y = 0.09 },
                .glyph = .{ .x = &x_edges, .y = &.{}, .left = 0.02 },
            },
            .autohint_base = base_key,
        },
        .{ .key = tt_key, .curves = base_curves },
    });
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
    const comp_x = @import("format/autohint_record.zig").xFeatures(comp_slab, auto_off);
    try testing.expectEqual(@as(usize, 1), comp_x.len);
    try testing.expectEqual(x_edges[0].pos, comp_x[0].pos);
    try testing.expectEqual(x_edges[0].width, comp_x[0].width);

    // TT-hinted band record and the advance value both survive.
    try testing.expect(compacted.lookupTtHintedRecord(tt_key) != null);
    try testing.expectEqual(@as(?i32, 7 * 64), compacted.lookupTtAdvance(advance_key));
}

test "filtered compact evicts records and closes dependencies" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
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

    var original = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = keep_base, .curves = c0 },
        .{ .key = drop_key, .curves = c1 },
        .{
            .key = keep_auto,
            .curves = GlyphCurves.empty(testing.allocator),
            .autohint = .{
                .font = .{ .blues = &.{}, .std_x = 0.1, .std_y = 0 },
                .glyph = .{ .x = &.{}, .y = &.{}, .left = 0 },
            },
            .autohint_base = keep_base,
        },
    });
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
