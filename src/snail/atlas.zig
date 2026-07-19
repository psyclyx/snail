//! Value-typed atlas. Holds refcounted page references plus a key→record
//! lookup table. Construction and update operations return new atlases,
//! leaving the input atlas untouched.
//!
//! See `docs/rewrite/02-atlas-and-pages.md` for the design rationale.

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

pub const InsertError = std.mem.Allocator.Error || PagePool.AcquireError || error{
    RecordTooLargeForPage,
    NoPool,
    MissingAutohintBase,
    InvalidAutohintAnalysis,
    LayerInfoTooLarge,
};

pub const Atlas = struct {
    allocator: std.mem.Allocator,
    /// The pool from which `pages` were allocated. `null` only on the
    /// identity atlas (`empty(allocator)`); operations that allocate pages
    /// require a non-null pool.
    pool: ?*PagePool,
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
    hinted_lookup: PaintLookup,
    /// One slot per emitted paint record (in insertion order). The slot
    /// is populated only for `.image` paints — gradient/solid records map
    /// to `null`. The software renderer's `BackendCache.upload`
    /// hands this to `preparePathLayerInfoRecords`; the GPU upload path
    /// patches the matching layer-info texel in place. Images themselves
    /// are caller-owned references; the atlas only borrows.
    paint_image_records: ?[]?PaintImageRecord = null,

    /// Identity atlas. Has no pool; usable as the neutral element of
    /// `combine` but not extensible on its own.
    pub fn empty(allocator: std.mem.Allocator) Atlas {
        return .{
            .allocator = allocator,
            .pool = null,
            .pages = &.{},
            .lookup = RecordLookup.init(allocator, .{}),
            .paint_lookup = PaintLookup.init(allocator, .{}),
            .autohint_lookup = PaintLookup.init(allocator, .{}),
            .hinted_lookup = PaintLookup.init(allocator, .{}),
        };
    }

    /// Empty atlas associated with `pool`. Unlike `empty`, this value can be
    /// populated with `extend` / `extendInPlace`; it is useful for callers
    /// whose atlas starts empty and grows on demand.
    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) Atlas {
        var atlas = empty(allocator);
        atlas.pool = pool;
        return atlas;
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
        self.hinted_lookup.deinit();
        self.lookup.deinit();
        self.* = undefined;
    }

    /// Look up the paint record (if any) bound to `key`. Returns null
    /// for keys whose entry had no paint, or for entries that came from
    /// `empty()` / `combine` of atlases without paints.
    pub fn lookupPaintRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.paint_lookup.get(key);
    }

    /// Look up the autohint slab record (if any) bound to `key`.
    pub fn lookupAutohintRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.autohint_lookup.get(key);
    }

    /// Look up the band record for a baked per-PPEM TT-hinted glyph.
    pub fn lookupHintedRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.hinted_lookup.get(key);
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
        var builder = Builder.init(allocator, pool);
        errdefer builder.abort();

        for (entries) |entry| {
            try builder.insert(entry);
        }

        return builder.finish();
    }

    /// Sugar for `combine(allocator, &.{self, from(entries)})` that avoids
    /// the intermediate allocation. The original atlas is not mutated.
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

    /// Replace this atlas with an extension while preserving `extend`'s
    /// failure atomicity: on error `self` remains valid and unchanged.
    /// Empty entry slices are a no-op.
    pub fn extendInPlace(
        self: *Atlas,
        allocator: std.mem.Allocator,
        entries: []const Entry,
    ) InsertError!void {
        if (entries.len == 0) return;
        const grown = try self.extend(allocator, entries);
        self.deinit();
        self.* = grown;
    }

    /// Union of pages and lookups. The result references the union of pages
    /// (each retained for the new atlas) and the union of lookups; on a key
    /// collision the first occurrence in the input order wins.
    ///
    /// `allocator` owns the returned atlas; `scratch` holds the page-dedup
    /// hashmap used during the merge and is freed before this returns.
    ///
    /// Asserts all non-empty inputs share the same `PagePool`.
    pub fn combine(
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
    ) std.mem.Allocator.Error!Atlas {
        var pool: ?*PagePool = null;
        for (atlases) |a| {
            if (a.pool) |p| {
                if (pool == null) {
                    pool = p;
                } else {
                    std.debug.assert(pool.? == p);
                }
            }
        }

        var page_set = std.AutoHashMapUnmanaged(*AtlasPage, u16){};
        defer page_set.deinit(scratch);

        var pages: std.ArrayList(*AtlasPage) = .empty;
        errdefer pages.deinit(allocator);

        for (atlases) |a| {
            for (a.pages) |p| {
                const gop = try page_set.getOrPut(scratch, p);
                if (!gop.found_existing) {
                    gop.value_ptr.* = @intCast(pages.items.len);
                    try pages.append(allocator, p);
                }
            }
        }

        var lookup = RecordLookup.init(allocator, .{});
        errdefer lookup.deinit();

        for (atlases) |a| {
            var it = a.lookup.iterator();
            while (it.next()) |kv| {
                if (lookup.contains(kv.key_ptr.*)) continue;
                const old_page = a.pages[kv.value_ptr.page_index];
                const new_index = page_set.get(old_page).?;
                var rec = kv.value_ptr.*;
                rec.page_index = new_index;
                const next = try lookup.put(kv.key_ptr.*, rec);
                lookup.deinit();
                lookup = next;
            }
        }

        // Bump refcount once per page for the new atlas.
        for (pages.items) |p| p.retain();

        return .{
            .allocator = allocator,
            .pool = pool,
            .pages = try pages.toOwnedSlice(allocator),
            .lookup = lookup,
            .paint_lookup = PaintLookup.init(allocator, .{}),
            .autohint_lookup = PaintLookup.init(allocator, .{}),
            .hinted_lookup = PaintLookup.init(allocator, .{}),
        };
    }

    /// Rebuild the atlas with the same keys but freshly packed into the
    /// minimum number of pages. Decodes each record's curve+band bytes from
    /// its source page, re-encodes them on new pages from the same pool.
    /// The original atlas is unaffected and continues to work.
    pub fn compact(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
    ) InsertError!Atlas {
        const pool = self.pool orelse return Atlas.empty(allocator);
        var builder = Builder.init(allocator, pool);
        errdefer builder.abort();

        var it = self.lookup.iterator();
        while (it.next()) |kv| {
            const rec = kv.value_ptr.*;
            const src_page = self.pages[rec.page_index];
            // Decode the band bytes from the page back to glyph-local form.
            const band_words_total = atlas_builder.bandWordsForRecordIncludingRefs(src_page, rec);
            const local_band = try scratch.alloc(u16, band_words_total);
            defer scratch.free(local_band);
            atlas_builder.extractAndLocalizeBand(src_page, rec, local_band);

            const curve_word_offset = rec.curve_texel * 4;
            const curve_words_total: u32 = @as(u32, rec.curve_count) * CURVE_SEGMENT_WORDS;
            const local_curves = src_page.curve.data[curve_word_offset..][0..curve_words_total];

            const curves_value = GlyphCurves{
                .allocator = scratch,
                .curve_bytes = local_curves,
                .band_bytes = local_band,
                .curve_count = rec.curve_count,
                .h_band_count = rec.bands.h_band_count,
                .v_band_count = rec.bands.v_band_count,
                .band_scale_x = rec.bands.band_scale_x,
                .band_scale_y = rec.bands.band_scale_y,
                .band_offset_x = rec.bands.band_offset_x,
                .band_offset_y = rec.bands.band_offset_y,
                .bbox = rec.bbox,
            };

            try builder.insert(.{ .key = kv.key_ptr.*, .curves = curves_value });
        }

        return builder.finish();
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

test "combine merges pages and lookups, first key wins" {
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
    const k_shared = record_key_mod.unhintedGlyph(0, 2);

    var a = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k_shared, .curves = c0 },
    });
    defer a.deinit();

    var c2 = try makeTestCurves(testing.allocator);
    defer c2.deinit();
    const k1 = record_key_mod.unhintedGlyph(0, 3);
    var b = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k_shared, .curves = c2 }, // conflicting key
        .{ .key = k1, .curves = c1 },
    });
    defer b.deinit();

    var combined = try Atlas.combine(testing.allocator, testing.allocator, &.{ &a, &b });
    defer combined.deinit();

    try testing.expectEqual(@as(u32, 3), combined.recordCount());
    try testing.expect(combined.contains(k0));
    try testing.expect(combined.contains(k_shared));
    try testing.expect(combined.contains(k1));

    // First-occurrence-wins: shared key resolves to A's record (same
    // curve_texel as in A).
    const shared_in_a = a.lookupRecord(k_shared).?;
    const shared_combined = combined.lookupRecord(k_shared).?;
    try testing.expectEqual(shared_in_a.curve_texel, shared_combined.curve_texel);

    // page_index is remapped to the combined atlas's pages slice.
    try testing.expect(shared_combined.page_index < combined.pages.len);
    try testing.expect(combined.pages[shared_combined.page_index] == a.pages[shared_in_a.page_index]);
}

test "combine with empty atlas is identity" {
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

    var empty = Atlas.empty(testing.allocator);
    defer empty.deinit();

    var combined = try Atlas.combine(testing.allocator, testing.allocator, &.{ &a, &empty });
    defer combined.deinit();
    try testing.expectEqual(@as(u32, 1), combined.recordCount());
    try testing.expect(combined.contains(k0));
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

    var compacted = try original.compact(testing.allocator, testing.allocator);
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
