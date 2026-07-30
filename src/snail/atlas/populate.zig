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
const TtAdvanceEntry = atlas_mod.TtAdvanceEntry;

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
    advances: std.ArrayList(TtAdvanceEntry) = .empty,
    seen_advances: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,

    fn init(allocator: Allocator) Batch {
        return .{
            .allocator = allocator,
            .scratch = std.heap.ArenaAllocator.init(allocator),
        };
    }

    fn deinit(self: *Batch) void {
        self.seen.deinit(self.allocator);
        self.seen_advances.deinit(self.allocator);
        self.advances.deinit(self.allocator);
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
        try atlas.extendWithAdvancesInPlace(self.allocator, self.entries.items, self.advances.items);
    }

    fn shouldRecordAdvance(self: *Batch, atlas: *const Atlas, key: RecordKey) !bool {
        if (atlas.lookupTtAdvance(key) != null) return false;
        const result = try self.seen_advances.getOrPut(self.allocator, key);
        return !result.found_existing;
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

fn appendUnhintedRun(
    batch: *Batch,
    atlas: *const Atlas,
    faces: *const faces_mod.Faces,
    shaped: *const text_mod.ShapedText,
    options: UnhintedRunOptions,
) !void {
    for (shaped.glyphs) |glyph| {
        const face_index: usize = @intCast(glyph.face_index);
        if (face_index >= faces.faceCount()) return error.UnknownFaceIndex;
        const font_id = faces.fontIdForFace(glyph.face_index) orelse return error.UnknownFaceIndex;
        if (font_id != glyph.font_id) return error.MismatchedFontId;
        try appendUnhintedGlyph(
            batch,
            atlas,
            faces.fontForFace(glyph.face_index).?,
            font_id,
            glyph.glyph_id,
            options,
        );
    }
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
    return recordUnhintedRuns(atlas, allocator, faces, &.{shaped}, options);
}

/// Record missing unhinted glyphs from several shaped runs in one atlas
/// transaction. Existing records and duplicates across runs are skipped.
///
/// This is the screen/paragraph ingestion path: callers may shape rows and
/// style spans independently, then avoid one persistent snapshot commit per
/// span. Any validation, extraction, allocation, or atlas error leaves the
/// original atlas unchanged.
pub fn recordUnhintedRuns(
    atlas: *Atlas,
    allocator: Allocator,
    faces: *const faces_mod.Faces,
    shaped_runs: []const *const text_mod.ShapedText,
    options: UnhintedRunOptions,
) !void {
    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped_runs) |shaped| {
        try appendUnhintedRun(&batch, atlas, faces, shaped, options);
    }
    try batch.apply(atlas);
}

// ── Caller-parallel unhinted extraction ──────────────────────────────
//
// `recordUnhintedRuns` above extracts every glyph inline on one thread.
// The three-phase API below lets a caller fan the expensive per-glyph
// extraction across its own worker threads (snail owns no thread pool):
//
//   1. `planUnhintedRuns`  — serial, cheap: dedup + COLR resolution,
//                            produces a flat list of extraction requests.
//   2. `plan.extractOne`   — parallel: one glyph → GlyphCurves, run across
//                            threads with a per-thread `ExtractContext`.
//   3. `plan.apply`        — serial: insert the results into the atlas.
//
// The extracted `GlyphCurves` between phases 2 and 3 is also the natural
// serialization unit for an offline glyph cache.
//
// Only regular glyphs and COLR `.layers` fan out (one request per atlas
// entry). The rarer COLR `.composite` case, whose entry assembly depends on
// post-extraction emptiness, is extracted serially during planning — text
// floods carry no COLR, so the hot path is fully parallel.

/// One deferred glyph extraction, produced by `planUnhintedRuns`.
pub const ExtractRequest = struct {
    font: *const Font,
    glyph_id: u16,
};

/// Per-thread extraction state. Each worker thread owns one: a scratch arena
/// reused across glyphs and a lazily-built cache of per-font HarfBuzz
/// `Instance`s (hb_font is not thread-safe, so instances are never shared
/// across threads). `out_allocator` owns the produced `GlyphCurves` bytes and
/// MUST be thread-safe — contexts on other threads allocate from it too.
pub const ExtractContext = struct {
    out_allocator: Allocator,
    scratch: std.heap.ArenaAllocator,
    instances: std.AutoHashMapUnmanaged(*const Font, Font.Instance) = .empty,

    pub fn init(out_allocator: Allocator, scratch_parent: Allocator) ExtractContext {
        return .{
            .out_allocator = out_allocator,
            .scratch = std.heap.ArenaAllocator.init(scratch_parent),
        };
    }

    pub fn deinit(self: *ExtractContext) void {
        var it = self.instances.valueIterator();
        while (it.next()) |inst| inst.deinit();
        self.instances.deinit(self.out_allocator);
        self.scratch.deinit();
        self.* = undefined;
    }

    fn instanceFor(self: *ExtractContext, font: *const Font) !?*Font.Instance {
        if (!font.requiresInstance()) return null;
        const gop = try self.instances.getOrPut(self.out_allocator, font);
        if (!gop.found_existing) gop.value_ptr.* = try font.createInstance();
        return gop.value_ptr;
    }
};

pub const UnhintedExtractPlan = struct {
    allocator: Allocator,
    requests: []ExtractRequest,
    request_keys: []RecordKey,
    /// Filled by `extractOne`; entry `i` corresponds to `requests[i]`.
    results: []?GlyphCurves,
    /// Serially-extracted COLR composites + their storage, plus the shared
    /// dedup set and the entry list `apply` inserts through.
    composites: Batch,

    pub fn requestCount(self: *const UnhintedExtractPlan) usize {
        return self.requests.len;
    }

    /// Extract request `index` into `results[index]` using `ctx`. Distinct
    /// indices touch distinct slots and distinct per-thread state, so calls
    /// for different indices run concurrently.
    pub fn extractOne(self: *UnhintedExtractPlan, index: usize, ctx: *ExtractContext) !void {
        const req = self.requests[index];
        const instance = try ctx.instanceFor(req.font);
        const curves = try req.font.extractCurvesWith(
            instance,
            ctx.out_allocator,
            ctx.scratch.allocator(),
            req.glyph_id,
        );
        _ = ctx.scratch.reset(.retain_capacity);
        self.results[index] = curves;
    }

    /// Insert every planned glyph (parallel results + serial composites)
    /// into the atlas in one transaction. Requires all requests extracted.
    pub fn apply(self: *UnhintedExtractPlan, atlas: *Atlas) !void {
        for (self.requests, 0..) |_, i| {
            const curves = self.results[i] orelse return error.MissingExtraction;
            try self.composites.entries.append(self.composites.allocator, .{
                .key = self.request_keys[i],
                .curves = curves,
            });
        }
        try atlas.extendWithAdvancesInPlace(
            self.composites.allocator,
            self.composites.entries.items,
            self.composites.advances.items,
        );
    }

    pub fn deinit(self: *UnhintedExtractPlan) void {
        for (self.results) |*r| if (r.*) |*c| c.deinit();
        self.allocator.free(self.results);
        self.allocator.free(self.requests);
        self.allocator.free(self.request_keys);
        self.composites.deinit();
    }
};

/// Plan (but don't extract) every missing unhinted glyph referenced by
/// `shaped_runs`. See the module-level notes above for the phase model.
pub fn planUnhintedRuns(
    atlas: *const Atlas,
    allocator: Allocator,
    faces: *const faces_mod.Faces,
    shaped_runs: []const *const text_mod.ShapedText,
    options: UnhintedRunOptions,
) !UnhintedExtractPlan {
    var batch = Batch.init(allocator);
    errdefer batch.deinit();
    var requests: std.ArrayList(ExtractRequest) = .empty;
    errdefer requests.deinit(allocator);
    var keys: std.ArrayList(RecordKey) = .empty;
    errdefer keys.deinit(allocator);

    for (shaped_runs) |shaped| {
        for (shaped.glyphs) |glyph| {
            const face_index: usize = @intCast(glyph.face_index);
            if (face_index >= faces.faceCount()) return error.UnknownFaceIndex;
            const font_id = faces.fontIdForFace(glyph.face_index) orelse return error.UnknownFaceIndex;
            if (font_id != glyph.font_id) return error.MismatchedFontId;
            try planUnhintedGlyph(
                &batch,
                &requests,
                &keys,
                atlas,
                faces.fontForFace(glyph.face_index).?,
                font_id,
                glyph.glyph_id,
                options,
            );
        }
    }

    const results = try allocator.alloc(?GlyphCurves, requests.items.len);
    @memset(results, null);
    return .{
        .allocator = allocator,
        .requests = try requests.toOwnedSlice(allocator),
        .request_keys = try keys.toOwnedSlice(allocator),
        .results = results,
        .composites = batch,
    };
}

/// Mirror of `appendUnhintedGlyph`, but routes regular glyphs and COLR
/// `.layers` layers to deferred `requests` (parallel extraction) and keeps
/// the COLR `.composite` assembly serial in `batch`.
fn planUnhintedGlyph(
    batch: *Batch,
    requests: *std.ArrayList(ExtractRequest),
    keys: *std.ArrayList(RecordKey),
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
                try requests.append(batch.allocator, .{ .font = font, .glyph_id = source.glyph_id });
                try keys.append(batch.allocator, layer_key);
            }
            return;
        }
    }

    const key = record_key.unhintedGlyph(font_id, glyph_id);
    if (!try batch.shouldInsert(atlas, key)) return;

    var iter = font.colrLayers(glyph_id);
    const layer_count: usize = iter.count();
    if (options.colr != .composite or layer_count == 0) {
        try requests.append(batch.allocator, .{ .font = font, .glyph_id = glyph_id });
        try keys.append(batch.allocator, key);
        return;
    }

    // COLR composite: extract serially now (matches appendUnhintedGlyph).
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
        const curves = try batch.extract(font, glyph_id);
        try batch.entries.append(batch.allocator, .{ .key = key, .curves = curves });
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
    return recordAutohintRuns(atlas, allocator, analyzer, font_id, &.{shaped});
}

/// Record immutable autohint analysis for several independently shaped runs
/// in one atlas transaction.
pub fn recordAutohintRuns(
    atlas: *Atlas,
    allocator: Allocator,
    analyzer: *autohint_mod.AutohintAnalyzer,
    font_id: u32,
    shaped_runs: []const *const text_mod.ShapedText,
) !void {
    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped_runs) |shaped| {
        try appendAutohintRun(&batch, atlas, analyzer, font_id, shaped);
    }
    try batch.apply(atlas);
}

fn appendAutohintRun(
    batch: *Batch,
    atlas: *const Atlas,
    analyzer: *autohint_mod.AutohintAnalyzer,
    font_id: u32,
    shaped: *const text_mod.ShapedText,
) !void {
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.autohintGlyph(font_id, glyph.glyph_id);
        if (!try batch.shouldInsert(atlas, key)) continue;
        const base_key = record_key.unhintedGlyph(font_id, glyph.glyph_id);
        const base = atlas.lookupRecord(base_key) orelse return error.MissingBaseGlyph;
        if (base.curve_count == 0) {
            try batch.entries.append(batch.allocator, .{
                .key = key,
                .curves = GlyphCurves.empty(batch.scratch.allocator()),
            });
            continue;
        }

        const x = try batch.scratch.allocator().alloc(autohint_mod.FeatureEdge, autohint_mod.max_features_per_axis);
        const y = try batch.scratch.allocator().alloc(autohint_mod.FeatureEdge, autohint_mod.max_features_per_axis);
        const analysis = try analyzer.analyzeGlyph(batch.scratch.allocator(), glyph.glyph_id, x, y);
        try batch.entries.append(batch.allocator, .{
            .key = key,
            .curves = GlyphCurves.empty(batch.scratch.allocator()),
            .autohint = .{ .font = analyzer.fontFeatures(), .glyph = analysis },
            .autohint_base = base_key,
        });
    }
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
    return recordTtHintRuns(atlas, allocator, vm, prepared, font_id, &.{shaped});
}

/// Record per-PPEM TT-hinted curves and advances for several independently
/// shaped runs in one atlas transaction.
pub fn recordTtHintRuns(
    atlas: *Atlas,
    allocator: Allocator,
    vm: *hint_vm_mod.TtHintVm,
    prepared: *const hint_vm_mod.TtHintVm.PreparedPpem,
    font_id: u32,
    shaped_runs: []const *const text_mod.ShapedText,
) !void {
    const ppem = ppemOf(prepared);
    // Curve record keys use the uniform-ppem convention shared with
    // `HintMode.tt_hint` and `record_key.ttHintedGlyph`; an anisotropic
    // `prepared` cannot be keyed.
    if (ppem.x_26_6 != ppem.y_26_6) return error.AnisotropicPpem;
    const packed_ppem = try ppem.packed26Dot6();

    var batch = Batch.init(allocator);
    defer batch.deinit();

    for (shaped_runs) |shaped| {
        try appendTtHintRun(&batch, atlas, vm, prepared, font_id, ppem.x_26_6, packed_ppem, shaped);
    }
    try batch.apply(atlas);
}

fn appendTtHintRun(
    batch: *Batch,
    atlas: *const Atlas,
    vm: *hint_vm_mod.TtHintVm,
    prepared: *const hint_vm_mod.TtHintVm.PreparedPpem,
    font_id: u32,
    ppem_26_6: u32,
    packed_ppem: u32,
    shaped: *const text_mod.ShapedText,
) !void {
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;

        const advance_key = record_key.ttAdvance(font_id, glyph.glyph_id, packed_ppem);
        if (try batch.shouldRecordAdvance(atlas, advance_key)) {
            const advance = try vm.hintedAdvance(prepared, glyph.glyph_id);
            try batch.advances.append(batch.allocator, .{ .key = advance_key, .advance_26_6 = advance });
        }

        const key = record_key.ttHintedGlyph(font_id, glyph.glyph_id, ppem_26_6);
        if (!try batch.shouldInsert(atlas, key)) continue;
        var curves = try vm.hintGlyph(batch.allocator, batch.scratch.allocator(), prepared, glyph.glyph_id);
        errdefer curves.deinit();
        _ = batch.scratch.reset(.retain_capacity);
        try batch.curves.append(batch.allocator, curves);
        try batch.entries.append(batch.allocator, .{
            .key = key,
            .curves = batch.curves.items[batch.curves.items.len - 1],
        });
    }
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
    const packed_ppem = try ppemOf(prepared).packed26Dot6();
    var advances: std.ArrayList(TtAdvanceEntry) = .empty;
    defer advances.deinit(atlas.allocator);
    var seen: std.AutoHashMapUnmanaged(RecordKey, void) = .empty;
    defer seen.deinit(atlas.allocator);
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != font_id) continue;
        const key = record_key.ttAdvance(font_id, glyph.glyph_id, packed_ppem);
        if (atlas.lookupTtAdvance(key) != null) continue;
        const result = try seen.getOrPut(atlas.allocator, key);
        if (result.found_existing) continue;
        const advance = try vm.hintedAdvance(prepared, glyph.glyph_id);
        try advances.append(atlas.allocator, .{ .key = key, .advance_26_6 = advance });
    }
    try atlas.recordTtAdvances(advances.items);
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
        const packed_ppem = ppem.packed26Dot6() catch return null;
        const key = record_key.ttAdvance(font_id, glyph_id, packed_ppem);
        if (self.atlas.lookupTtAdvance(key)) |advance| return advance;
        const prepared_ppem = ppemOf(self.prepared);
        std.debug.assert(ppem.x_26_6 == prepared_ppem.x_26_6 and ppem.y_26_6 == prepared_ppem.y_26_6);
        if (ppem.x_26_6 != prepared_ppem.x_26_6 or ppem.y_26_6 != prepared_ppem.y_26_6) return null;
        return self.vm.hintedAdvance(self.prepared, glyph_id) catch |err| {
            self.last_error = err;
            self.fallback_count +|= 1;
            return null;
        };
    }
};

const testing = std.testing;

test "unhinted run packs COLR and deduplicates repeated glyphs" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "AA\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
    const emoji_glyph = shaped.glyphs[shaped.glyphs.len - 1];
    const info = atlas.lookupPaintRecord(record_key.unhintedGlyph(emoji_glyph.font_id, emoji_glyph.glyph_id)).?;
    try testing.expect(info.layer_count > 1);

    try recordUnhintedRun(&atlas, testing.allocator, &faces, &shaped, .{});
}

test "parallel plan/extract/apply matches serial recordUnhintedRuns" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    // Mixed: repeated Latin (dedup) + a COLR emoji (serial-composite path).
    var shaped = try faces_mod.shape(testing.allocator, &faces, "Hello AA\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    const cfg = atlas_mod.PagePool.Options{
        .max_pages = 8,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    };

    // Reference: serial path.
    var serial_pool = try atlas_mod.PagePool.init(testing.allocator, cfg);
    defer serial_pool.deinit();
    var serial = try Atlas.init(testing.allocator, serial_pool);
    defer serial.deinit();
    try recordUnhintedRuns(&serial, testing.allocator, &faces, &.{&shaped}, .{});

    // Under test: plan → extractOne (single-threaded loop here) → apply.
    var par_pool = try atlas_mod.PagePool.init(testing.allocator, cfg);
    defer par_pool.deinit();
    var parallel = try Atlas.init(testing.allocator, par_pool);
    defer parallel.deinit();

    var plan = try planUnhintedRuns(&parallel, testing.allocator, &faces, &.{&shaped}, .{});
    defer plan.deinit();
    var ctx = ExtractContext.init(testing.allocator, testing.allocator);
    defer ctx.deinit();
    for (0..plan.requestCount()) |i| try plan.extractOne(i, &ctx);
    try plan.apply(&parallel);

    // Every referenced glyph lands in both atlases identically.
    for (shaped.glyphs) |glyph| {
        const key = record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id);
        try testing.expectEqual(serial.contains(key), parallel.contains(key));
        const s_info = serial.lookupPaintRecord(key);
        const p_info = parallel.lookupPaintRecord(key);
        try testing.expectEqual(s_info == null, p_info == null);
        if (s_info) |si| try testing.expectEqual(si.layer_count, p_info.?.layer_count);
    }
}

test "concurrent extractOne across threads is safe and matches serial" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &regular, .font_id = 0 }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(
        testing.allocator,
        &faces,
        "The quick brown fox jumps over the lazy dog 0123456789",
        .{},
    );
    defer shaped.deinit();

    const cfg = atlas_mod.PagePool.Options{
        .max_pages = 8,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    };
    var serial_pool = try atlas_mod.PagePool.init(testing.allocator, cfg);
    defer serial_pool.deinit();
    var serial = try Atlas.init(testing.allocator, serial_pool);
    defer serial.deinit();
    try recordUnhintedRuns(&serial, testing.allocator, &faces, &.{&shaped}, .{});

    var par_pool = try atlas_mod.PagePool.init(testing.allocator, cfg);
    defer par_pool.deinit();
    var parallel = try Atlas.init(testing.allocator, par_pool);
    defer parallel.deinit();

    var plan = try planUnhintedRuns(&parallel, testing.allocator, &faces, &.{&shaped}, .{});
    defer plan.deinit();

    // Four threads, each with its own context, striping the requests.
    const thread_count = 4;
    const Worker = struct {
        fn run(p: *UnhintedExtractPlan, base: usize, stride: usize) void {
            var ctx = ExtractContext.init(std.heap.smp_allocator, std.heap.smp_allocator);
            defer ctx.deinit();
            var i = base;
            while (i < p.requestCount()) : (i += stride) {
                p.extractOne(i, &ctx) catch unreachable;
            }
        }
    };
    var threads: [thread_count]std.Thread = undefined;
    for (0..thread_count) |t| threads[t] = try std.Thread.spawn(.{}, Worker.run, .{ &plan, t, thread_count });
    for (threads) |th| th.join();
    try plan.apply(&parallel);

    for (shaped.glyphs) |glyph| {
        const key = record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id);
        try testing.expect(parallel.contains(key));
        try testing.expectEqual(serial.contains(key), parallel.contains(key));
    }
}

test "unhinted runs commit several shaped runs as one snapshot" {
    var font = try Font.init(@import("assets").noto_sans_regular);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font, .font_id = 7 }});
    defer faces.deinit();

    var first = try faces_mod.shape(testing.allocator, &faces, "abc", .{});
    defer first.deinit();
    var second = try faces_mod.shape(testing.allocator, &faces, "xyz", .{});
    defer second.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 15,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    const before = atlas.snapshotIdentity();
    try recordUnhintedRuns(&atlas, testing.allocator, &faces, &.{ &first, &second }, .{});
    const after = atlas.snapshotIdentity();
    try testing.expectEqual(before.revision + 1, after.revision);
    try testing.expectEqual(before.snapshot_id, after.parent_snapshot_id);
    for (first.glyphs) |glyph| {
        try testing.expect(atlas.contains(record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id)));
    }
    for (second.glyphs) |glyph| {
        try testing.expect(atlas.contains(record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id)));
    }
}

test "outline_only COLR handling records base outlines and ignores layers" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "A\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
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
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "A\xf0\x9f\x8c\x8d", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
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
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font, .font_id = 0 }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, " A", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
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

    const packed_ppem = try hint_vm_mod.TtHintPpem.uniform(ppem_26_6).packed26Dot6();
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
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font, .font_id = 0 }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(testing.allocator, &faces, "Ab", .{});
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
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

test "TT run failure is atomic and leaves the VM reusable" {
    const bytes = @import("assets").dejavu_sans_mono;
    var font = try Font.init(bytes);
    var faces = try faces_mod.Faces.build(testing.allocator, &.{.{ .font = &font, .font_id = 0 }});
    defer faces.deinit();
    var valid = try faces_mod.shape(testing.allocator, &faces, "A", .{});
    defer valid.deinit();

    var glyphs = [_]text_mod.ShapedText.Glyph{
        valid.glyphs[0],
        .{
            .face_index = valid.glyphs[0].face_index,
            .glyph_id = std.math.maxInt(u16),
            .x_offset = 0,
            .y_offset = 0,
            .x_advance = 0,
            .y_advance = 0,
            .source_start = 1,
            .source_end = 2,
            .font_id = 0,
        },
    };
    const shaped = text_mod.ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    var vm = try hint_vm_mod.TtHintVm.init(testing.allocator, &font);
    defer vm.deinit();
    var prepared = try vm.prepare(hint_vm_mod.TtHintPpem.uniform(13 * 64));
    defer prepared.deinit();

    if (recordTtHintRun(&atlas, testing.allocator, &vm, &prepared, 0, &shaped)) |_| {
        return error.TestExpectedError;
    } else |_| {}
    try testing.expectEqual(@as(u32, 0), atlas.recordCount());
    try testing.expectEqual(@as(u32, 0), atlas.ttAdvanceCount());
    try testing.expectEqual(@as(usize, 0), atlas.pageCount());

    // The failed topology cache insertion was removed: a valid glyph still
    // executes, and the VM's deferred destruction must remain safe.
    try testing.expect((try vm.hintedAdvance(&prepared, valid.glyphs[0].glyph_id)) > 0);
    var curves = try vm.hintGlyph(testing.allocator, testing.allocator, &prepared, valid.glyphs[0].glyph_id);
    curves.deinit();
}
