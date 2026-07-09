//! Batteries-included text atlas: the low-ceremony way to render shaped runs
//! in any hinting mode.
//!
//! Ties together the pieces a text renderer needs — glyph producers (unhinted
//! extraction, the pure `HintVm`, `auto_light`), one working-set
//! `GlyphAtlasCache` over a caller's `PagePool`, and `placeRun` — behind a
//! single call:
//!
//!   var text = try TextAtlas.init(alloc, &faces, pool);
//!   // per frame:
//!   const pic = try text.run(arena, &shaped, .{ .mode = .auto_light{...}, .snap = .origins,
//!                                               .baseline = ..., .em = ..., .world_to_pixel = w2p });
//!   // draw `pic` against `text.atlas()`
//!
//! `run` makes every glyph the run references resident (running a producer
//! only on a real cache miss — output is memoized by the atlas) and builds the
//! placed `Picture`. The producers are pure; the only mutable state is the
//! caches, held here (not in the algorithms). Allocation is controllable:
//! `run` uses the convenience `ensure` (grow, compact-on-full); a
//! latency-sensitive caller drops to `text.cache` (`tryEnsure` + explicit
//! `compact`) or bypasses the facade entirely with `placeRun` + a raw `Atlas`.
//!
//! Scope: glyph runs (unhinted / auto_light / truetype). COLR/paint records
//! are out of `GlyphAtlasCache`'s scope — build those into a separate,
//! long-lived atlas and `combine`. Not thread-safe; one per thread.

const std = @import("std");
const snail = @import("snail");
const text_picture = @import("text_picture.zig");

const Allocator = std.mem.Allocator;
const Faces = snail.Faces;
const Atlas = snail.Atlas;
const HintVm = snail.HintVm;
const AutoLight = snail.autohint.AutoLight;
const warp = snail.autohint.warp;
const GlyphAtlasCache = @import("glyph_atlas_cache.zig").GlyphAtlasCache;

pub const Picture = text_picture.Picture;
pub const RunPlacement = text_picture.RunPlacement;
pub const HintMode = text_picture.HintMode;

const PreparedKey = struct { font_id: u32, ppem_26_6: u32 };

pub const TextAtlas = struct {
    allocator: Allocator,
    faces: *const Faces,
    cache: GlyphAtlasCache,
    /// Reusable arena for producer internals + knot buffers; reset per glyph.
    scratch: std.heap.ArenaAllocator,
    /// Per-font-id lazy producers. `vms` holds `null` for a font with no TT
    /// hinting (falls back to unhinted).
    vms: std.AutoHashMapUnmanaged(u32, ?*HintVm),
    autos: std.AutoHashMapUnmanaged(u32, *AutoLight),
    /// Per-(font, ppem) TrueType `Prepared` (fpgm/prep amortization).
    prepareds: std.AutoHashMapUnmanaged(PreparedKey, HintVm.Prepared),

    /// Errors from residency (`GlyphAtlasCache`), placement (COLR fanout), the
    /// producers' font parse (`AutoLight.init`), and this facade's own scope.
    const AutoInitError = @typeInfo(@typeInfo(@TypeOf(AutoLight.init)).@"fn".return_type.?).error_union.error_set;
    pub const Error = GlyphAtlasCache.InsertError || text_picture.ShapedRunError ||
        AutoInitError || snail.HintError || error{ColrUnsupported};

    pub fn init(allocator: Allocator, faces: *const Faces, pool: *snail.PagePool) TextAtlas {
        return .{
            .allocator = allocator,
            .faces = faces,
            .cache = GlyphAtlasCache.init(allocator, pool),
            .scratch = std.heap.ArenaAllocator.init(allocator),
            .vms = .{},
            .autos = .{},
            .prepareds = .{},
        };
    }

    pub fn deinit(self: *TextAtlas) void {
        var pit = self.prepareds.valueIterator();
        while (pit.next()) |p| p.deinit();
        self.prepareds.deinit(self.allocator);
        var vit = self.vms.valueIterator();
        while (vit.next()) |v| if (v.*) |vm| {
            vm.deinit();
            self.allocator.destroy(vm);
        };
        self.vms.deinit(self.allocator);
        var ait = self.autos.valueIterator();
        while (ait.next()) |a| {
            a.*.deinit();
            self.allocator.destroy(a.*);
        }
        self.autos.deinit(self.allocator);
        self.scratch.deinit();
        self.cache.deinit();
        self.* = undefined;
    }

    /// The atlas snapshot to hand the renderer.
    pub fn atlas(self: *const TextAtlas) *const Atlas {
        return self.cache.atlasPtr();
    }

    /// Reclaim capacity: drop ~`fraction` of the coldest glyphs and rebuild.
    /// The only O(resident) burst — call it at a frame boundary you own.
    pub fn compact(self: *TextAtlas, fraction: f32) Error!usize {
        return self.cache.compact(fraction);
    }

    /// Make every glyph the run references resident (producing on cache miss),
    /// then build the placed `Picture` in `arena`. `p.mode` selects the path;
    /// `p.colr` is unsupported here (see the module scope).
    pub fn run(self: *TextAtlas, arena: Allocator, shaped: *const snail.ShapedText, p: RunPlacement) Error!Picture {
        if (p.colr) return error.ColrUnsupported;
        for (shaped.glyphs) |g| {
            try self.ensureGlyph(p.mode, g.face_index, g.font_id, g.glyph_id);
        }
        return text_picture.placeRun(arena, shaped, self.faces, p);
    }

    // ── residency ────────────────────────────────────────────────────────

    fn ensureGlyph(self: *TextAtlas, mode: HintMode, face_index: snail.FaceIndex, font_id: u32, gid: u16) Error!void {
        if (self.cache.contains(mode.key(font_id, gid))) return;
        switch (mode) {
            .unhinted => try self.ensureUnhinted(face_index, font_id, gid),
            .truetype => |t| try self.ensureTrueType(face_index, font_id, gid, t.ppem_26_6),
            .auto_light => |m| try self.ensureAutoLight(face_index, font_id, gid, m.ppem_26_6),
        }
    }

    fn ensureUnhinted(self: *TextAtlas, face_index: snail.FaceIndex, font_id: u32, gid: u16) Error!void {
        const key = snail.recordKey.unhintedGlyph(font_id, gid);
        if (self.cache.contains(key)) return;
        defer _ = self.scratch.reset(.retain_capacity);
        var curves = try self.faces.face(face_index).font.extractCurves(self.allocator, self.scratch.allocator(), gid);
        defer curves.deinit();
        try self.cache.ensure(.{ .key = key, .curves = curves });
    }

    fn ensureTrueType(self: *TextAtlas, face_index: snail.FaceIndex, font_id: u32, gid: u16, ppem_26_6: u32) Error!void {
        const vm = (try self.vmFor(face_index, font_id)) orelse {
            // Font has no TrueType hinting — fall back to unhinted curves under
            // the SAME hinted key so the run's Picture still resolves.
            defer _ = self.scratch.reset(.retain_capacity);
            var curves = try self.faces.face(face_index).font.extractCurves(self.allocator, self.scratch.allocator(), gid);
            defer curves.deinit();
            try self.cache.ensure(.{ .key = snail.recordKey.hintedGlyph(font_id, gid, ppem_26_6), .curves = curves });
            return;
        };
        const prepared = try self.preparedFor(vm, font_id, ppem_26_6);
        defer _ = self.scratch.reset(.retain_capacity);
        // A glyph the VM can't hint (a broken glyph program) degrades to empty
        // rather than failing the whole run.
        var curves = vm.hintGlyph(self.allocator, self.scratch.allocator(), prepared, gid) catch
            snail.GlyphCurves.empty(self.allocator);
        defer curves.deinit();
        try self.cache.ensure(.{ .key = snail.recordKey.hintedGlyph(font_id, gid, ppem_26_6), .curves = curves });
    }

    fn ensureAutoLight(self: *TextAtlas, face_index: snail.FaceIndex, font_id: u32, gid: u16, ppem_26_6: u32) Error!void {
        // The shared, ppem-independent base must be resident first — the warp
        // aliases its curves.
        try self.ensureUnhinted(face_index, font_id, gid);
        const auto = try self.autoFor(face_index, font_id);
        defer _ = self.scratch.reset(.retain_capacity);
        const sa = self.scratch.allocator();
        const xk = try sa.alloc(warp.Knot, warp.max_knots);
        const yk = try sa.alloc(warp.Knot, warp.max_knots);
        const knots = auto.glyphKnots(sa, gid, ppem_26_6, xk, yk) catch return; // no features → skip warp
        try self.cache.ensure(.{
            .key = snail.recordKey.autohintGlyph(font_id, gid, ppem_26_6),
            .curves = snail.GlyphCurves.empty(sa),
            .autohint = .{ .x = knots.x, .y = knots.y },
            .autohint_base = snail.recordKey.unhintedGlyph(font_id, gid),
        });
    }

    // ── lazy producers ───────────────────────────────────────────────────

    fn vmFor(self: *TextAtlas, face_index: snail.FaceIndex, font_id: u32) Error!?*HintVm {
        const gop = try self.vms.getOrPut(self.allocator, font_id);
        if (!gop.found_existing) {
            errdefer _ = self.vms.remove(font_id);
            const vm = self.allocator.create(HintVm) catch |e| return e;
            vm.* = HintVm.init(self.allocator, self.faces.face(face_index).font) catch {
                // No fpgm/prep/cvt — remember the absence.
                self.allocator.destroy(vm);
                gop.value_ptr.* = null;
                return null;
            };
            gop.value_ptr.* = vm;
        }
        return gop.value_ptr.*;
    }

    fn autoFor(self: *TextAtlas, face_index: snail.FaceIndex, font_id: u32) Error!*AutoLight {
        const gop = try self.autos.getOrPut(self.allocator, font_id);
        if (!gop.found_existing) {
            errdefer _ = self.autos.remove(font_id);
            const a = try self.allocator.create(AutoLight);
            errdefer self.allocator.destroy(a);
            a.* = try AutoLight.init(self.allocator, self.faces.face(face_index).font.inner.data);
            gop.value_ptr.* = a;
        }
        return gop.value_ptr.*;
    }

    fn preparedFor(self: *TextAtlas, vm: *HintVm, font_id: u32, ppem_26_6: u32) Error!*const HintVm.Prepared {
        const gop = try self.prepareds.getOrPut(self.allocator, .{ .font_id = font_id, .ppem_26_6 = ppem_26_6 });
        if (!gop.found_existing) {
            errdefer _ = self.prepareds.remove(.{ .font_id = font_id, .ppem_26_6 = ppem_26_6 });
            gop.value_ptr.* = try vm.prepare(snail.HintPpem.uniform(ppem_26_6));
        }
        return gop.value_ptr;
    }
};

const testing = std.testing;
const assets = @import("assets");

fn testPool() !*snail.PagePool {
    return snail.PagePool.init(testing.allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
}

test "TextAtlas.run makes glyphs resident and places them, per mode" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    const pool = try testPool();
    defer pool.deinit();

    var text = TextAtlas.init(testing.allocator, &faces, pool);
    defer text.deinit();

    var shaped = try snail.shape(testing.allocator, &faces, "abc", .{});
    defer shaped.deinit();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const modes = [_]HintMode{
        .unhinted,
        .{ .auto_light = .{ .ppem_26_6 = 13 * 64 } },
        .{ .truetype = .{ .ppem_26_6 = 13 * 64 } },
    };
    for (modes) |mode| {
        _ = arena.reset(.retain_capacity);
        var pic = try text.run(arena.allocator(), &shaped, .{
            .baseline = .{ .x = 4, .y = 20 },
            .em = 13,
            .mode = mode,
            .snap = if (mode == .unhinted) .none else .columns,
            .world_to_pixel = snail.Transform2D{},
        });
        defer pic.deinit();
        try testing.expectEqual(@as(usize, 3), pic.shapes.len);
        // Every referenced record is now resident in the atlas.
        for (pic.shapes) |s| try testing.expect(text.atlas().lookupRecord(s.key) != null);
    }
    // auto_light aliases one shared base per glyph; truetype bakes per-ppem.
    try testing.expect(text.cache.stats().resident >= 3);
}

test "TextAtlas rejects COLR runs (out of scope)" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    const pool = try testPool();
    defer pool.deinit();
    var text = TextAtlas.init(testing.allocator, &faces, pool);
    defer text.deinit();
    var shaped = try snail.shape(testing.allocator, &faces, "x", .{});
    defer shaped.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.ColrUnsupported, text.run(arena.allocator(), &shaped, .{
        .baseline = .{ .x = 0, .y = 10 },
        .em = 12,
        .colr = true,
    }));
}
