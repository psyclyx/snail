//! Record shaped runs into an `Atlas`.
//!
//! The atlas is the store of prepared glyph records; these functions run the
//! per-mode producers (`Faces`, `AutohintAnalyzer`, `TtHintVm`) for every
//! glyph the store doesn't already have and commit the results with
//! `Atlas.extendInPlace`. Recording is idempotent — existing keys are
//! skipped — so repeat calls over the same run are cheap. They do not shape
//! or place text.
//!
//! Recording fails with `error.OutOfLayers` when the `PagePool` budget is
//! exhausted — see the capacity model notes on `Atlas` for the eviction
//! recipe (`compact` + `RecordFilter`).

const std = @import("std");
const atlas_mod = @import("../atlas.zig");
const font_mod = @import("../font.zig");
const hint_vm_mod = @import("../font/tt_hint_vm.zig");
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

/// How `recordUnhintedRun` stores COLRv0 glyphs. Each mode pairs with a
/// placement style; recording and placement must agree.
pub const ColrHandling = enum {
    /// Pack all layers into one immutable composite record under the base
    /// glyph key. Pairs with `RunPlacement.colr = false`: one shape per
    /// glyph resolves to the composite paint record.
    composite,
    /// Record each layer glyph as its own plain unhinted record (non-COLR
    /// glyphs get their base outline). Pairs with `RunPlacement.colr = true`
    /// fanout, which emits one shape per layer keyed by layer glyph id and
    /// resolves layer colors (including the 0xffff foreground) per shape at
    /// placement time.
    layers,
    /// Ignore COLR tables; record base outlines only.
    outline_only,
};

pub const UnhintedRunOptions = struct {
    colr: ColrHandling = .composite,
    /// COLRv0 palette index 0xffff means "use the foreground." The paint
    /// record ABI is immutable, so under `.composite` this color is resolved
    /// at record time and shared by every draw of the resulting record.
    /// (`.layers` resolves the foreground at placement time instead.)
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

/// Append one glyph to `batch` under the chosen COLR handling.
fn appendUnhintedGlyph(
    batch: *Batch,
    atlas: *const Atlas,
    font: *const Font,
    font_id: u32,
    glyph_id: u16,
    options: UnhintedRunOptions,
) !void {
    if (options.colr == .layers) {
        var layer_iter = font.colrLayers(glyph_id);
        if (layer_iter.count() > 0) {
            while (layer_iter.next()) |source| {
                const layer_key = record_key.unhintedGlyph(font_id, source.glyph_id);
                if (!try batch.shouldInsert(atlas, layer_key)) continue;
                try appendRegularGlyph(batch, layer_key, font, source.glyph_id);
            }
            return;
        }
    }

    const key = record_key.unhintedGlyph(font_id, glyph_id);
    if (!try batch.shouldInsert(atlas, key)) return;

    var iter = font.colrLayers(glyph_id);
    const layer_count: usize = iter.count();
    if (options.colr != .composite or layer_count == 0) {
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

/// Record every missing unhinted glyph referenced by `shaped`.
/// COLRv0 glyphs are packed into composites by default, so ordinary
/// `placeRun` (`colr = false`) emits one instance per base glyph without
/// caller-side layer assembly; see `ColrHandling` for the fanout pairing.
pub fn recordUnhintedRun(
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

/// Record immutable autohint analysis for every matching glyph.
/// Missing base glyphs are rejected; empty base glyphs get empty records so
/// callers can place a whole run without patching whitespace afterward.
pub fn recordAutohintRun(
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

fn ppemOf(prepared: *const hint_vm_mod.TtHintVm.PreparedPpem) hint_vm_mod.TtHintPpem {
    return .{ .x_26_6 = prepared.size.request.ppem_x_26_6, .y_26_6 = prepared.size.request.ppem_y_26_6 };
}

/// Record per-PPEM TT-hinted curves *and* horizontal advances for every
/// glyph in `shaped` matching `font_id`. The ppem comes from `prepared`
/// (the caller-owned result of `vm.prepare`); the advance is a byproduct
/// of the same glyph-program execution, so it is recorded for free.
pub fn recordTtHintRun(
    atlas: *Atlas,
    allocator: Allocator,
    vm: *hint_vm_mod.TtHintVm,
    prepared: *const hint_vm_mod.TtHintVm.PreparedPpem,
    font_id: u32,
    shaped: *const text_mod.ShapedText,
) !void {
    const ppem = ppemOf(prepared);
    // Curve record keys use the uniform-ppem convention shared with
    // `HintMode.tt_hint` and `record_key.ttHintedGlyph`; an anisotropic
    // `prepared` cannot be keyed.
    if (ppem.x_26_6 != ppem.y_26_6) return error.AnisotropicPpem;
    const ppem_26_6 = ppem.x_26_6;

    try recordTtAdvanceRun(atlas, vm, prepared, font_id, shaped);

    var has_missing = false;
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.ttHintedGlyph(font_id, glyph.glyph_id, ppem_26_6);
        if (!atlas.contains(key)) {
            has_missing = true;
            break;
        }
    }
    // Keep repeat recording calls cheap when the store contains the run.
    if (!has_missing) return;

    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.ttHintedGlyph(font_id, glyph.glyph_id, ppem_26_6);
        if (!try batch.shouldInsert(atlas, key)) continue;
        var curves = try vm.hintGlyph(allocator, batch.scratch.allocator(), prepared, glyph.glyph_id);
        errdefer curves.deinit();
        _ = batch.scratch.reset(.retain_capacity);
        try batch.curves.append(batch.allocator, curves);
        try batch.entries.append(allocator, .{
            .key = key,
            .curves = batch.curves.items[batch.curves.items.len - 1],
        });
    }
    try batch.apply(atlas);
}

/// Record TT-hinted horizontal advances (`ns.tt_advance`) for every glyph
/// in `shaped` matching `font_id`. Touches no curve pages — this is the
/// cheap path for measurement-only runs (line breaking, width queries)
/// whose glyphs may never be drawn.
pub fn recordTtAdvanceRun(
    atlas: *Atlas,
    vm: *hint_vm_mod.TtHintVm,
    prepared: *const hint_vm_mod.TtHintVm.PreparedPpem,
    font_id: u32,
    shaped: *const text_mod.ShapedText,
) !void {
    const packed_ppem = ppemOf(prepared).packed26Dot6();
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.ttAdvance(font_id, glyph.glyph_id, packed_ppem);
        if (atlas.lookupTtAdvance(key) != null) continue;
        const advance = try vm.hintedAdvance(prepared, glyph.glyph_id);
        try atlas.recordTtAdvance(key, advance);
    }
}

/// Read-side `AdvanceProvider` over recorded `ns.tt_advance` values,
/// falling back to the pure VM for glyphs not yet recorded. Read-only
/// over `atlas` — `shape()` never mutates the store; recording happens
/// in `recordTtHintRun` / `recordTtAdvanceRun`.
///
/// The VM fallback requires the shape call's `target_ppem` to match
/// `prepared`'s ppem — both come from the caller, so a mismatch is a
/// programmer error (asserted in debug; in release the provider declines
/// and shaping uses the font's native advance).
///
/// When the VM fails on a glyph the provider declines it (native-advance
/// fallback) and records the failure in `last_error`/`fallback_count`;
/// check those after shaping to detect degraded runs.
pub const TtAdvanceSource = struct {
    atlas: *const Atlas,
    vm: *hint_vm_mod.TtHintVm,
    prepared: *const hint_vm_mod.TtHintVm.PreparedPpem,
    font_id: u32,
    /// Most recent VM failure that forced a native-advance fallback.
    last_error: ?hint_vm_mod.TtHintError = null,
    /// Number of glyph advances that fell back since construction.
    fallback_count: u32 = 0,

    /// The returned provider borrows `self`; both must outlive any
    /// `shape` call passed `opts.advance_provider = provider`.
    pub fn advanceProvider(self: *TtAdvanceSource) text_mod.AdvanceProvider {
        return .{
            .context = @ptrCast(self),
            .covers = covers,
            .get_advance = getAdvance,
        };
    }

    fn covers(context: *anyopaque, font_id: u32) bool {
        const self: *TtAdvanceSource = @ptrCast(@alignCast(context));
        return font_id == self.font_id;
    }

    fn getAdvance(context: *anyopaque, font_id: u32, glyph_id: u16, ppem: hint_vm_mod.TtHintPpem) ?i32 {
        const self: *TtAdvanceSource = @ptrCast(@alignCast(context));
        const key = record_key.ttAdvance(font_id, glyph_id, ppem.packed26Dot6());
        if (self.atlas.lookupTtAdvance(key)) |advance| return advance;
        const prepared_ppem = ppemOf(self.prepared);
        std.debug.assert(ppem.x_26_6 == prepared_ppem.x_26_6 and ppem.y_26_6 == prepared_ppem.y_26_6);
        if (ppem.x_26_6 != prepared_ppem.x_26_6 or ppem.y_26_6 != prepared_ppem.y_26_6) return null;
        return self.vm.hintedAdvance(self.prepared, glyph_id) catch |err| {
            self.last_error = err;
            self.fallback_count += 1;
            return null;
        };
    }
};

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

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
    const emoji_glyph = shaped.glyphs[shaped.glyphs.len - 1];
    const info = atlas.lookupPaintRecord(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)).?;
    try testing.expect(info.layer_count > 1);

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
}

test "outline_only COLR handling records base outlines and ignores layers" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular },
        .{ .font = &emoji, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "A\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{ .colr = .outline_only });

    // The COLR glyph is recorded as a plain base outline: present under
    // its base key, with no composite paint record and no layer records.
    const emoji_glyph = shaped.glyphs[shaped.glyphs.len - 1];
    try testing.expect(atlas.contains(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)));
    try testing.expect(atlas.lookupPaintRecord(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)) == null);
    var iter = emoji.colrLayers(emoji_glyph.glyph_id);
    while (iter.next()) |layer| {
        if (layer.glyph_id == emoji_glyph.glyph_id) continue;
        try testing.expect(!atlas.contains(record_key.unhintedGlyph(emoji_glyph.font_id, layer.glyph_id)));
    }
}

test "layers COLR handling records per-layer glyphs for fanout placement" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular },
        .{ .font = &emoji, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "A\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{ .colr = .layers });

    // Non-COLR glyph: base outline recorded.
    const a_glyph = shaped.glyphs[0];
    try testing.expect(atlas.contains(record_key.unhintedGlyph(a_glyph.font_id, a_glyph.glyph_id)));

    // COLR glyph: every layer glyph recorded as a plain record (no
    // composite under the base key).
    const emoji_glyph = shaped.glyphs[shaped.glyphs.len - 1];
    try testing.expect(atlas.lookupPaintRecord(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)) == null);
    var iter = emoji.colrLayers(emoji_glyph.glyph_id);
    try testing.expect(iter.count() > 1);
    while (iter.next()) |layer| {
        try testing.expect(atlas.contains(record_key.unhintedGlyph(emoji_glyph.font_id, layer.glyph_id)));
    }
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
    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});

    var analyzer = try autohint_mod.AutohintAnalyzer.init(testing.allocator, bytes);
    defer analyzer.deinit();
    try recordAutohintRun(&atlas, testing.allocator, &analyzer, 0, &shaped);

    var vm = try hint_vm_mod.TtHintVm.init(testing.allocator, &font);
    defer vm.deinit();
    const ppem_26_6: u32 = 16 * 64;
    var prepared = try vm.prepare(hint_vm_mod.TtHintPpem.uniform(ppem_26_6));
    defer prepared.deinit();
    try recordTtHintRun(&atlas, testing.allocator, &vm, &prepared, 0, &shaped);

    const packed_ppem = hint_vm_mod.TtHintPpem.uniform(ppem_26_6).packed26Dot6();
    for (shaped.glyphs) |glyph| {
        try testing.expect(atlas.contains(record_key.autohintGlyph(0, glyph.glyph_id)));
        try testing.expect(atlas.contains(record_key.ttHintedGlyph(0, glyph.glyph_id, ppem_26_6)));
        try testing.expect(atlas.lookupTtAdvance(record_key.ttAdvance(0, glyph.glyph_id, packed_ppem)) != null);
    }

    // Recording is idempotent and survives snapshot extension.
    const advance_count = atlas.ttAdvanceCount();
    try recordTtHintRun(&atlas, testing.allocator, &vm, &prepared, 0, &shaped);
    try testing.expectEqual(advance_count, atlas.ttAdvanceCount());
}

test "TtAdvanceSource reads recorded advances and falls back to the VM" {
    const bytes = @import("assets").dejavu_sans_mono;
    var font = try Font.init(bytes);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "Ab", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    var vm = try hint_vm_mod.TtHintVm.init(testing.allocator, &font);
    defer vm.deinit();
    const ppem = hint_vm_mod.TtHintPpem.uniform(13 * 64);
    var prepared = try vm.prepare(ppem);
    defer prepared.deinit();

    var source = TtAdvanceSource{ .atlas = &atlas, .vm = &vm, .prepared = &prepared, .font_id = 0 };
    const provider = source.advanceProvider();
    try testing.expect(provider.covers(provider.context, 0));
    try testing.expect(!provider.covers(provider.context, 1));

    // Store miss: falls back to the pure VM.
    const gid = shaped.glyphs[0].glyph_id;
    const from_vm = provider.get_advance(provider.context, 0, gid, ppem).?;
    try testing.expect(from_vm > 0);

    // Advance-only recording stores the same value without touching pages.
    try recordTtAdvanceRun(&atlas, &vm, &prepared, 0, &shaped);
    try testing.expectEqual(@as(usize, 0), atlas.pageCount());
    const from_store = provider.get_advance(provider.context, 0, gid, ppem).?;
    try testing.expectEqual(from_vm, from_store);
    try testing.expectEqual(@as(u32, 0), source.fallback_count);
}
