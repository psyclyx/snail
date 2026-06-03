//! Per-(ppem, glyph_id) memoization of `HintVm.hintGlyph` and
//! `HintVm.hintedAdvance`.
//!
//! `HintVm` runs the TT VM and packs curves; this cache stores the
//! results so repeat queries at the same size return without touching
//! the VM. The cache owns the `GlyphCurves` it stores and frees them
//! on `evictPpem` / `clear` / `deinit`.
//!
//! A typical caller wires `asAdvanceProvider()` into
//! `ShapeOptions.advance_provider` so HarfBuzz's `glyph_h_advance`
//! callback walks this cache instead of re-running the VM per glyph.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const HintVm = snail.HintVm;
const HintPpem = snail.HintPpem;
const HintError = snail.HintError;
const GlyphCurves = snail.GlyphCurves;

const Key = packed struct(u64) {
    ppem_x_26_6: u32,
    ppem_y_26_6: u16,
    glyph_id: u16,
};

inline fn keyFor(ppem: HintPpem, glyph_id: u16) Key {
    return .{
        .ppem_x_26_6 = ppem.x_26_6,
        .ppem_y_26_6 = @intCast(ppem.y_26_6 & 0xFFFF),
        .glyph_id = glyph_id,
    };
}

pub const HintedGlyphCache = struct {
    allocator: Allocator,
    vm: *HintVm,
    /// The font_id this cache covers. AdvanceProvider's `covers`
    /// callback uses it to gate per-face attach in shape().
    font_id: u32,
    curves: std.AutoHashMapUnmanaged(Key, GlyphCurves),
    advances: std.AutoHashMapUnmanaged(Key, i32),

    pub const Stats = struct {
        glyph_count: u32,
        advance_count: u32,
        curve_bytes: usize,
        band_bytes: usize,
    };

    pub fn init(allocator: Allocator, vm: *HintVm, font_id: u32) HintedGlyphCache {
        return .{
            .allocator = allocator,
            .vm = vm,
            .font_id = font_id,
            .curves = .{},
            .advances = .{},
        };
    }

    pub fn deinit(self: *HintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.deinit(self.allocator);
        self.advances.deinit(self.allocator);
        self.* = undefined;
    }

    /// Return the cached curves for `(glyph_id, ppem)`, calling
    /// `vm.hintGlyph(allocator, scratch, glyph_id, ppem)` on first use.
    /// `allocator` owns the stored curves; `scratch` is used only during
    /// the call and is freed before this returns.
    pub fn getOrInsertCurves(
        self: *HintedGlyphCache,
        allocator: Allocator,
        scratch: Allocator,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!*const GlyphCurves {
        const key = keyFor(ppem, glyph_id);
        const gop = try self.curves.getOrPut(self.allocator, key);
        if (!gop.found_existing) {
            errdefer _ = self.curves.remove(key);
            gop.value_ptr.* = try self.vm.hintGlyph(allocator, scratch, glyph_id, ppem);
        }
        return gop.value_ptr;
    }

    /// Hinted advance for `(glyph_id, ppem)`. Cached on first use.
    pub fn advance(
        self: *HintedGlyphCache,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!i32 {
        const key = keyFor(ppem, glyph_id);
        if (self.advances.get(key)) |a| return a;
        const adv = try self.vm.hintedAdvance(glyph_id, ppem);
        try self.advances.put(self.allocator, key, adv);
        return adv;
    }

    /// Drop every cached curve and advance for `ppem`. Optionally drops
    /// the VM machine for the same ppem via `vm.evictPpem`.
    pub fn evictPpem(self: *HintedGlyphCache, ppem: HintPpem) void {
        var dropped_curves: std.ArrayListUnmanaged(Key) = .empty;
        defer dropped_curves.deinit(self.allocator);
        var it = self.curves.iterator();
        while (it.next()) |kv| {
            if (kv.key_ptr.ppem_x_26_6 == ppem.x_26_6 and kv.key_ptr.ppem_y_26_6 == @as(u16, @intCast(ppem.y_26_6 & 0xFFFF))) {
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
            if (kv.key_ptr.ppem_x_26_6 == ppem.x_26_6 and kv.key_ptr.ppem_y_26_6 == @as(u16, @intCast(ppem.y_26_6 & 0xFFFF))) {
                dropped_advances.append(self.allocator, kv.key_ptr.*) catch continue;
            }
        }
        for (dropped_advances.items) |k| _ = self.advances.remove(k);
    }

    /// Drop every cached curve and advance, regardless of ppem. The
    /// underlying `HintVm`'s per-ppem machine cache is untouched.
    pub fn clear(self: *HintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.clearRetainingCapacity();
        self.advances.clearRetainingCapacity();
    }

    /// Closure adapter: returns an `AdvanceProvider` whose
    /// `get_advance` walks this cache, falling back to the underlying
    /// `HintVm.hintedAdvance` (and caching the result) on miss.
    /// `covers` returns true only for the `font_id` this cache was
    /// built for; shape() uses it to skip attach on other faces.
    ///
    /// The returned provider borrows `self`; both must outlive any
    /// shape call passed `opts.advance_provider = provider`.
    pub fn asAdvanceProvider(self: *HintedGlyphCache) snail.AdvanceProvider {
        return .{
            .context = @ptrCast(self),
            .covers = advanceProviderCovers,
            .get_advance = advanceProviderTrampoline,
        };
    }

    pub fn stats(self: *const HintedGlyphCache) Stats {
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
    const self: *HintedGlyphCache = @ptrCast(@alignCast(context));
    return font_id == self.font_id;
}

fn advanceProviderTrampoline(context: *anyopaque, font_id: u32, glyph_id: u16, ppem: HintPpem) i32 {
    _ = font_id;
    const self: *HintedGlyphCache = @ptrCast(@alignCast(context));
    return self.advance(glyph_id, ppem) catch 0;
}

const testing = std.testing;
const assets = @import("assets");

test "HintedGlyphCache memoizes curves across repeated lookups" {
    var font = try snail.Font.init(assets.noto_sans_regular);

    var vm = try HintVm.init(testing.allocator, &font);
    defer vm.deinit();

    var cache = HintedGlyphCache.init(testing.allocator, &vm, 0);
    defer cache.deinit();

    const ppem = HintPpem.uniform(13 * 64);
    const gid = try font.glyphIndex('A');

    const first = try cache.getOrInsertCurves(testing.allocator, testing.allocator, gid, ppem);
    const second = try cache.getOrInsertCurves(testing.allocator, testing.allocator, gid, ppem);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().glyph_count);

    cache.evictPpem(ppem);
    try testing.expectEqual(@as(u32, 0), cache.stats().glyph_count);
}

test "HintedGlyphCache.advance caches hinted advance" {
    var font = try snail.Font.init(assets.noto_sans_regular);

    var vm = try HintVm.init(testing.allocator, &font);
    defer vm.deinit();

    var cache = HintedGlyphCache.init(testing.allocator, &vm, 0);
    defer cache.deinit();

    const ppem = HintPpem.uniform(13 * 64);
    const gid = try font.glyphIndex('A');

    const first = try cache.advance(gid, ppem);
    const second = try cache.advance(gid, ppem);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().advance_count);
}
