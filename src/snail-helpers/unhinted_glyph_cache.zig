//! Per-glyph memoization of `Font.extractCurves`.
//!
//! Stores `GlyphCurves` keyed by glyph id. The first `getOrInsert`
//! call for a glyph runs the extraction; subsequent calls return the
//! same cached pointer. The cache owns the stored curves and frees
//! them on `evict` / `clear` / `deinit`.
//!
//! The cache is single-font: a `*const Font` is captured at `init`
//! and used for every extraction. Multi-font callers hold one cache
//! per font.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const Font = snail.Font;
const GlyphCurves = snail.GlyphCurves;
const GlyphCache = snail.GlyphCache;

pub const UnhintedGlyphCache = struct {
    allocator: Allocator,
    font: *const Font,
    compound_cache: GlyphCache,
    curves: std.AutoHashMapUnmanaged(u16, GlyphCurves),

    pub const Stats = struct {
        glyph_count: u32,
        curve_bytes: usize,
        band_bytes: usize,
    };

    pub fn init(allocator: Allocator, font: *const Font) UnhintedGlyphCache {
        return .{
            .allocator = allocator,
            .font = font,
            .compound_cache = GlyphCache.init(allocator),
            .curves = .{},
        };
    }

    pub fn deinit(self: *UnhintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |curves| curves.deinit();
        self.curves.deinit(self.allocator);
        self.compound_cache.deinit();
        self.* = undefined;
    }

    /// Return the cached curves for `glyph_id`, extracting on first use.
    /// `allocator` owns the curves stored in the cache; `scratch` holds
    /// per-extraction intermediates and is freed before this returns.
    pub fn getOrInsert(
        self: *UnhintedGlyphCache,
        allocator: Allocator,
        scratch: Allocator,
        glyph_id: u16,
    ) !*const GlyphCurves {
        const gop = try self.curves.getOrPut(self.allocator, glyph_id);
        if (!gop.found_existing) {
            errdefer _ = self.curves.remove(glyph_id);
            gop.value_ptr.* = try self.font.extractCurves(
                allocator,
                scratch,
                &self.compound_cache,
                glyph_id,
            );
        }
        return gop.value_ptr;
    }

    pub fn evict(self: *UnhintedGlyphCache, glyph_id: u16) void {
        if (self.curves.fetchRemove(glyph_id)) |kv| {
            var curves = kv.value;
            curves.deinit();
        }
    }

    pub fn clear(self: *UnhintedGlyphCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |curves| curves.deinit();
        self.curves.clearRetainingCapacity();
    }

    pub fn stats(self: *const UnhintedGlyphCache) Stats {
        var curve_bytes: usize = 0;
        var band_bytes: usize = 0;
        var it = self.curves.valueIterator();
        while (it.next()) |c| {
            curve_bytes += c.curveBytes();
            band_bytes += c.bandBytes();
        }
        return .{
            .glyph_count = self.curves.count(),
            .curve_bytes = curve_bytes,
            .band_bytes = band_bytes,
        };
    }
};

const testing = std.testing;
const assets = @import("assets");

test "UnhintedGlyphCache returns the same curves across repeated lookups" {
    var font = try Font.init(assets.noto_sans_regular);

    var cache = UnhintedGlyphCache.init(testing.allocator, &font);
    defer cache.deinit();

    const gid_a = try font.glyphIndex('A');
    const first = try cache.getOrInsert(testing.allocator, testing.allocator, gid_a);
    const second = try cache.getOrInsert(testing.allocator, testing.allocator, gid_a);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().glyph_count);

    const gid_b = try font.glyphIndex('B');
    _ = try cache.getOrInsert(testing.allocator, testing.allocator, gid_b);
    try testing.expectEqual(@as(u32, 2), cache.stats().glyph_count);

    cache.evict(gid_a);
    try testing.expectEqual(@as(u32, 1), cache.stats().glyph_count);

    cache.clear();
    try testing.expectEqual(@as(u32, 0), cache.stats().glyph_count);
}
