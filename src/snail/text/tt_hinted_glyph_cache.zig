//! Per-(ppem, glyph_id) memoization of `TtHintVm.hintGlyph` and
//! `TtHintVm.hintedAdvance`.
//!
//! `TtHintVm` runs the TT VM and packs curves; this cache stores the
//! results so repeat queries at the same size return without touching
//! the VM. The cache owns the `GlyphCurves` it stores and frees them
//! on `evictPpem` / `clear` / `deinit`.
//!
//! A typical caller wires `asAdvanceProvider()` into
//! `ShapeOptions.advance_provider` so HarfBuzz's `glyph_h_advance`
//! callback walks this cache instead of re-running the VM per glyph.

const std = @import("std");
const text = @import("../text.zig");
const font = @import("../font.zig");
const tt_hint_vm = @import("../font/tt_hint_vm.zig");
const curves_mod = @import("../atlas/curves.zig");

const Allocator = std.mem.Allocator;
const TtHintVm = tt_hint_vm.TtHintVm;
const TtHintPpem = tt_hint_vm.TtHintPpem;
const TtHintError = tt_hint_vm.TtHintError;
const GlyphCurves = curves_mod.GlyphCurves;

const Key = struct {
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    glyph_id: u16,
};

inline fn keyFor(ppem: TtHintPpem, glyph_id: u16) Key {
    return .{
        .ppem_x_26_6 = ppem.x_26_6,
        .ppem_y_26_6 = ppem.y_26_6,
        .glyph_id = glyph_id,
    };
}

pub const TtHintedGlyphCache = struct {
    allocator: Allocator,
    vm: *TtHintVm,
    /// The font_id this cache covers. AdvanceProvider's `covers`
    /// callback uses it to gate per-face attach in shape().
    font_id: u32,
    curves: std.AutoHashMapUnmanaged(Key, GlyphCurves),
    advances: std.AutoHashMapUnmanaged(Key, i32),
    /// Per-ppem `Prepared` (the fpgm/prep result) that the pure `TtHintVm`
    /// hints from. Cached here — the VM itself is stateless — so `fpgm`/`prep`
    /// runs once per size, amortized across every glyph and every frame.
    prepareds: std.AutoHashMapUnmanaged(TtHintPpem, TtHintVm.Prepared),

    pub const Stats = struct {
        glyph_count: u32,
        advance_count: u32,
        curve_bytes: usize,
        band_bytes: usize,
    };

    pub fn init(allocator: Allocator, vm: *TtHintVm, font_id: u32) TtHintedGlyphCache {
        return .{
            .allocator = allocator,
            .vm = vm,
            .font_id = font_id,
            .curves = .{},
            .advances = .{},
            .prepareds = .{},
        };
    }

    pub fn deinit(self: *TtHintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.deinit(self.allocator);
        self.advances.deinit(self.allocator);
        var pit = self.prepareds.valueIterator();
        while (pit.next()) |p| p.deinit();
        self.prepareds.deinit(self.allocator);
        self.* = undefined;
    }

    /// The cached `Prepared` for `ppem`, running fpgm/prep on first use.
    fn preparedFor(self: *TtHintedGlyphCache, ppem: TtHintPpem) TtHintError!*const TtHintVm.Prepared {
        const gop = try self.prepareds.getOrPut(self.allocator, ppem);
        if (!gop.found_existing) {
            errdefer _ = self.prepareds.remove(ppem);
            gop.value_ptr.* = try self.vm.prepare(ppem);
        }
        return gop.value_ptr;
    }

    /// Return the cached curves for `(glyph_id, ppem)`, calling
    /// `vm.hintGlyph(allocator, scratch, glyph_id, ppem)` on first use.
    /// `allocator` owns the stored curves; `scratch` is used only during
    /// the call and is freed before this returns.
    pub fn getOrInsertCurves(
        self: *TtHintedGlyphCache,
        allocator: Allocator,
        scratch: Allocator,
        glyph_id: u16,
        ppem: TtHintPpem,
    ) TtHintError!*const GlyphCurves {
        const key = keyFor(ppem, glyph_id);
        const gop = try self.curves.getOrPut(self.allocator, key);
        if (!gop.found_existing) {
            errdefer _ = self.curves.remove(key);
            const prepared = try self.preparedFor(ppem);
            gop.value_ptr.* = try self.vm.hintGlyph(allocator, scratch, prepared, glyph_id);
        }
        return gop.value_ptr;
    }

    /// Hinted advance for `(glyph_id, ppem)`. Cached on first use.
    pub fn advance(
        self: *TtHintedGlyphCache,
        glyph_id: u16,
        ppem: TtHintPpem,
    ) TtHintError!i32 {
        const key = keyFor(ppem, glyph_id);
        if (self.advances.get(key)) |a| return a;
        const prepared = try self.preparedFor(ppem);
        const adv = try self.vm.hintedAdvance(prepared, glyph_id);
        try self.advances.put(self.allocator, key, adv);
        return adv;
    }

    /// Drop every cached curve and advance for `ppem`. Optionally drops
    /// the VM machine for the same ppem via `vm.evictPpem`.
    pub fn evictPpem(self: *TtHintedGlyphCache, ppem: TtHintPpem) void {
        var dropped_curves: std.ArrayListUnmanaged(Key) = .empty;
        defer dropped_curves.deinit(self.allocator);
        var it = self.curves.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.ppem_x_26_6 == ppem.x_26_6 and kv.key_ptr.ppem_y_26_6 == ppem.y_26_6) {
                dropped_curves.append(self.allocator, kv.key_ptr.*) catch continue;
            }
        }
        for (dropped_curves.items) |k| {
            if (self.curves.fetchRemove(k)) |r| {
                var v = r.value;
                v.deinit();
            }
        }

        var dropped_advances: std.ArrayListUnmanaged(Key) = .empty;
        defer dropped_advances.deinit(self.allocator);
        var ait = self.advances.iterator();
        while (ait.next()) |kv| {
            if (kv.key_ptr.ppem_x_26_6 == ppem.x_26_6 and kv.key_ptr.ppem_y_26_6 == ppem.y_26_6) {
                dropped_advances.append(self.allocator, kv.key_ptr.*) catch continue;
            }
        }
        for (dropped_advances.items) |k| _ = self.advances.remove(k);

        // Drop the (expensive) Prepared for this size too — nothing at this
        // ppem remains resident.
        if (self.prepareds.fetchRemove(ppem)) |r| {
            var p = r.value;
            p.deinit();
        }
    }

    /// Drop every cached curve, advance, and Prepared, regardless of ppem.
    pub fn clear(self: *TtHintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.clearRetainingCapacity();
        self.advances.clearRetainingCapacity();
        var pit = self.prepareds.valueIterator();
        while (pit.next()) |p| p.deinit();
        self.prepareds.clearRetainingCapacity();
    }

    /// Closure adapter: returns an `AdvanceProvider` whose
    /// `get_advance` walks this cache, falling back to the underlying
    /// `TtHintVm.hintedAdvance` (and caching the result) on miss.
    /// `covers` returns true only for the `font_id` this cache was
    /// built for; shape() uses it to skip attach on other faces.
    ///
    /// The returned provider borrows `self`; both must outlive any
    /// shape call passed `opts.advance_provider = provider`.
    pub fn asAdvanceProvider(self: *TtHintedGlyphCache) text.AdvanceProvider {
        return .{
            .context = @ptrCast(self),
            .covers = advanceProviderCovers,
            .get_advance = advanceProviderTrampoline,
        };
    }

    pub fn stats(self: *const TtHintedGlyphCache) Stats {
        var curve_bytes: usize = 0;
        var band_bytes: usize = 0;
        var it = self.curves.valueIterator();
        while (it.next()) |c| {
            curve_bytes += c.curveBytes();
            band_bytes += c.bandBytes();
        }
        return .{
            .glyph_count = self.curves.count(),
            .advance_count = self.advances.count(),
            .curve_bytes = curve_bytes,
            .band_bytes = band_bytes,
        };
    }
};

fn advanceProviderCovers(context: *anyopaque, font_id: u32) bool {
    const self: *TtHintedGlyphCache = @ptrCast(@alignCast(context));
    return font_id == self.font_id;
}

fn advanceProviderTrampoline(context: *anyopaque, font_id: u32, glyph_id: u16, ppem: TtHintPpem) i32 {
    _ = font_id;
    const self: *TtHintedGlyphCache = @ptrCast(@alignCast(context));
    return self.advance(glyph_id, ppem) catch 0;
}

const testing = std.testing;
const assets = @import("assets");

test "TtHintedGlyphCache memoizes curves across repeated lookups" {
    var test_font = try font.Font.init(assets.noto_sans_regular);

    var vm = try TtHintVm.init(testing.allocator, &test_font);
    defer vm.deinit();

    var cache = TtHintedGlyphCache.init(testing.allocator, &vm, 0);
    defer cache.deinit();

    const ppem = TtHintPpem.uniform(13 * 64);
    const gid = try test_font.glyphIndex('A');

    const first = try cache.getOrInsertCurves(testing.allocator, testing.allocator, gid, ppem);
    const second = try cache.getOrInsertCurves(testing.allocator, testing.allocator, gid, ppem);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().glyph_count);

    cache.evictPpem(ppem);
    try testing.expectEqual(@as(u32, 0), cache.stats().glyph_count);
}

test "TtHintedGlyphCache.advance caches hinted advance" {
    var test_font = try font.Font.init(assets.noto_sans_regular);

    var vm = try TtHintVm.init(testing.allocator, &test_font);
    defer vm.deinit();

    var cache = TtHintedGlyphCache.init(testing.allocator, &vm, 0);
    defer cache.deinit();

    const ppem = TtHintPpem.uniform(13 * 64);
    const gid = try test_font.glyphIndex('A');

    const first = try cache.advance(gid, ppem);
    const second = try cache.advance(gid, ppem);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().advance_count);
}
