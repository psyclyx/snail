//! Focused font-to-atlas population helpers.
//!
//! These functions own the temporary `GlyphCurves` / `AtlasEntry` storage,
//! deduplicate against both the atlas and the current batch, and commit with
//! `Atlas.extendInPlace`. They do not shape or place text.

const std = @import("std");
const atlas_mod = @import("../atlas.zig");
const font_mod = @import("../font.zig");
const hint_vm_mod = @import("../font/tt_hint_vm.zig");
const hinted_cache_mod = @import("../text/tt_hinted_glyph_cache.zig");
const autohint_mod = @import("../font/autohint/producer.zig");
const autohint_warp = @import("../font/autohint/warp.zig");
const faces_mod = @import("../text/faces.zig");
const text_mod = @import("../text.zig");
const record_key = @import("record_key.zig");

const Allocator = std.mem.Allocator;
const Atlas = atlas_mod.Atlas;
const Entry = atlas_mod.Entry;
const Font = font_mod.Font;
const GlyphCurves = atlas_mod.GlyphCurves;
const Layer = atlas_mod.Layer;
const RecordKey = record_key.RecordKey;

pub const UnhintedRunOptions = struct {
    /// Pack COLRv0 layers into one immutable composite record under the base
    /// glyph key. When false, the base outline is inserted as a regular glyph.
    pack_colr: bool = true,
    /// COLRv0 palette index 0xffff means "use the foreground." The current
    /// paint-record ABI is immutable, so this color is resolved at population
    /// time and shared by every draw of the resulting atlas record.
    colr_foreground: [4]f32 = .{ 1, 1, 1, 1 },
};

const Batch = struct {
    allocator: Allocator,
    scratch: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    curves: std.ArrayList(GlyphCurves) = .empty,
    layer_storage: std.ArrayList([]Layer) = .empty,
    seen: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,

    fn init(allocator: Allocator) Batch {
        return .{
            .allocator = allocator,
            .scratch = std.heap.ArenaAllocator.init(allocator),
        };
    }

    fn deinit(self: *Batch) void {
        self.seen.deinit(self.allocator);
        for (self.layer_storage.items) |layers| self.allocator.free(layers);
        self.layer_storage.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        for (self.curves.items) |*curves| curves.deinit();
        self.curves.deinit(self.allocator);
        self.scratch.deinit();
        self.* = undefined;
    }

    fn shouldInsert(self: *Batch, atlas: *const Atlas, key: RecordKey) !bool {
        if (atlas.contains(key)) return false;
        const result = try self.seen.getOrPut(self.allocator, key);
        return !result.found_existing;
    }

    fn extract(self: *Batch, font: *const Font, glyph_id: u16) !GlyphCurves {
        var curves = try font.extractCurves(self.allocator, self.scratch.allocator(), glyph_id);
        errdefer curves.deinit();
        _ = self.scratch.reset(.retain_capacity);
        try self.curves.append(self.allocator, curves);
        return self.curves.items[self.curves.items.len - 1];
    }

    fn apply(self: *Batch, atlas: *Atlas) !void {
        try atlas.extendInPlace(self.allocator, self.entries.items);
    }
};

fn paletteColor(color: [4]f32, foreground: [4]f32) [4]f32 {
    return if (color[0] < 0) foreground else color;
}

fn appendRegularGlyph(
    batch: *Batch,
    key: RecordKey,
    font: *const Font,
    glyph_id: u16,
) !void {
    const curves = try batch.extract(font, glyph_id);
    try batch.entries.append(batch.allocator, .{ .key = key, .curves = curves });
}

/// Append one glyph to `batch`, packing COLRv0 into a single composite when
/// requested.
fn appendUnhintedGlyph(
    batch: *Batch,
    atlas: *const Atlas,
    font: *const Font,
    font_id: u32,
    glyph_id: u16,
    options: UnhintedRunOptions,
) !void {
    const key = record_key.unhintedGlyph(font_id, glyph_id);
    if (!try batch.shouldInsert(atlas, key)) return;

    var iter = font.colrLayers(glyph_id);
    const layer_count: usize = iter.count();
    if (!options.pack_colr or layer_count == 0) {
        try appendRegularGlyph(batch, key, font, glyph_id);
        return;
    }

    const layers = try batch.allocator.alloc(Layer, layer_count);
    errdefer batch.allocator.free(layers);
    var count: usize = 0;
    while (iter.next()) |source| {
        const curves = try batch.extract(font, source.glyph_id);
        if (curves.isEmpty()) continue;
        layers[count] = .{
            .curves = curves,
            .paint = .{ .solid = paletteColor(source.color, options.colr_foreground) },
        };
        count += 1;
    }

    if (count == 0) {
        batch.allocator.free(layers);
        try appendRegularGlyph(batch, key, font, glyph_id);
        return;
    }

    try batch.entries.append(batch.allocator, .{
        .key = key,
        .curves = layers[0].curves,
        .paint = layers[0].paint,
        .extra_layers = layers[1..count],
    });
    try batch.layer_storage.append(batch.allocator, layers);
}

/// Extend `atlas` with every missing unhinted glyph referenced by `shaped`.
/// COLRv0 glyphs are packed by default, so ordinary `placeRun` emits one COLR
/// instance for each base glyph without caller-side layer assembly.
pub fn extendUnhintedRun(
    atlas: *Atlas,
    allocator: Allocator,
    faces: *const faces_mod.Faces,
    shaped: *const text_mod.ShapedText,
    options: UnhintedRunOptions,
) !void {
    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped.glyphs) |glyph| {
        const face_index: usize = @intCast(glyph.face_index);
        if (face_index >= faces.faceCount()) return error.UnknownFaceIndex;
        const font_id = faces.fontIdForFace(glyph.face_index);
        if (font_id != glyph.font_id) return error.MismatchedFontId;
        try appendUnhintedGlyph(
            &batch,
            atlas,
            faces.face(glyph.face_index).font,
            font_id,
            glyph.glyph_id,
            options,
        );
    }
    try batch.apply(atlas);
}

/// Extend `atlas` with immutable autohint analysis for every matching glyph.
/// Missing base glyphs are rejected; empty base glyphs get empty records so
/// callers can place a whole run without patching whitespace afterward.
pub fn extendAutohintRun(
    atlas: *Atlas,
    allocator: Allocator,
    analyzer: *autohint_mod.AutohintAnalyzer,
    font_id: u32,
    shaped: *const text_mod.ShapedText,
) !void {
    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.autohintGlyph(font_id, glyph.glyph_id);
        if (!try batch.shouldInsert(atlas, key)) continue;
        const base_key = record_key.unhintedGlyph(font_id, glyph.glyph_id);
        const base = atlas.lookupRecord(base_key) orelse return error.MissingBaseGlyph;
        if (base.curve_count == 0) {
            try batch.entries.append(allocator, .{
                .key = key,
                .curves = GlyphCurves.empty(batch.scratch.allocator()),
            });
            continue;
        }

        const x = try batch.scratch.allocator().alloc(autohint_mod.FeatureEdge, autohint_warp.max_knots);
        const y = try batch.scratch.allocator().alloc(autohint_mod.FeatureEdge, autohint_warp.max_knots);
        const analysis = try analyzer.analyzeGlyph(batch.scratch.allocator(), glyph.glyph_id, x, y);
        try batch.entries.append(allocator, .{
            .key = key,
            .curves = GlyphCurves.empty(batch.scratch.allocator()),
            .autohint = .{ .font = analyzer.fontFeatures(), .glyph = analysis },
            .autohint_base = base_key,
        });
    }
    try batch.apply(atlas);
}

/// Extend `atlas` with per-PPEM TT-hinted curves for every glyph covered by
/// `cache`. The cache amortizes VM preparation across calls at the same PPEM.
pub fn extendTtHintRun(
    atlas: *Atlas,
    allocator: Allocator,
    cache: *hinted_cache_mod.TtHintedGlyphCache,
    shaped: *const text_mod.ShapedText,
    ppem_26_6: u32,
) !void {
    var has_missing = false;
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != cache.font_id) continue;
        const key = record_key.ttHintedGlyph(cache.font_id, glyph.glyph_id, ppem_26_6);
        if (!atlas.contains(key)) {
            has_missing = true;
            break;
        }
    }
    // Keep repeat population calls cheap when this atlas contains the run.
    if (!has_missing) return;

    var batch = Batch.init(allocator);
    defer batch.deinit();
    const ppem = hint_vm_mod.TtHintPpem.uniform(ppem_26_6);

    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != cache.font_id) continue;
        const key = record_key.ttHintedGlyph(cache.font_id, glyph.glyph_id, ppem_26_6);
        if (!try batch.shouldInsert(atlas, key)) continue;
        const curves = try cache.getOrInsertCurves(allocator, batch.scratch.allocator(), glyph.glyph_id, ppem);
        _ = batch.scratch.reset(.retain_capacity);
        try batch.entries.append(allocator, .{
            .key = key,
            .curves = curves.*,
        });
    }
    try batch.apply(atlas);
}

const testing = std.testing;

test "unhinted run packs COLR and deduplicates repeated glyphs" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular },
        .{ .font = &emoji, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "AA\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    try extendUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
    const emoji_glyph = shaped.glyphs[shaped.glyphs.len - 1];
    const info = atlas.lookupPaintRecord(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)).?;
    try testing.expect(info.layer_count > 1);

    try extendUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
}

test "autohint and TT-hint run helpers cover empty and visible glyphs" {
    const bytes = @import("assets").dejavu_sans_mono;
    var font = try Font.init(bytes);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, " A", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = Atlas.init(testing.allocator, pool);
    defer atlas.deinit();
    try extendUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});

    var analyzer = try autohint_mod.AutohintAnalyzer.init(testing.allocator, bytes);
    defer analyzer.deinit();
    try extendAutohintRun(&atlas, testing.allocator, &analyzer, 0, &shaped);

    var vm = try hint_vm_mod.TtHintVm.init(testing.allocator, &font);
    defer vm.deinit();
    var cache = hinted_cache_mod.TtHintedGlyphCache.init(testing.allocator, &vm, 0);
    defer cache.deinit();
    const ppem_26_6: u32 = 16 * 64;
    try extendTtHintRun(&atlas, testing.allocator, &cache, &shaped, ppem_26_6);

    for (shaped.glyphs) |glyph| {
        try testing.expect(atlas.contains(record_key.autohintGlyph(0, glyph.glyph_id)));
        try testing.expect(atlas.contains(record_key.ttHintedGlyph(0, glyph.glyph_id, ppem_26_6)));
    }
}
