//! Demo-local memoization of `snail.shape()` output keyed by the inputs that
//! determine its bytes.
//!
//! `snail.shape(faces, text, opts)` is deterministic in
//! `(text, opts.style, opts.target_ppem)` for a given `Faces` and
//! `opts.advance_provider`. A long-running session (terminal, banner
//! with mostly-static text, animated counter that lingers on the same
//! string) re-shapes the same string every frame; this helper short-
//! circuits that.
//!
//! ## Lifetime
//!
//! `shape()` returns a borrowed `*const ShapedText` owned by the cache.
//! The pointer stays valid until the next mutating call on the same
//! cache (`evict`, `clear`, `deinit`). The cache owns the entry's
//! `text` slice and its `ShapedText.glyphs`; both are freed on
//! eviction.
//!
//! ## Invalidation
//!
//! The cache key does **not** include the `Faces` value or the
//! `advance_provider`. If the caller mutates the face chain or swaps
//! the provider's underlying data (e.g. a different `TtHintedGlyphCache`
//! for a different VM), they must `clear()` the cache — otherwise
//! returned `ShapedText` values reflect the old shaping and would not
//! re-shape until the entry naturally evicts.
//!
//! ## What's not covered
//!
//! `ShapeOptions.features` is not part of the key. Callers using
//! per-run features should either avoid the cache or instantiate one
//! cache per feature set.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const Faces = snail.Faces;
const ShapeOptions = snail.ShapeOptions;
const ShapedText = snail.ShapedText;

pub const ShapedRunCache = struct {
    allocator: Allocator,
    entries: std.HashMapUnmanaged(Key, ShapedText, KeyContext, std.hash_map.default_max_load_percentage),

    pub const Stats = struct {
        entry_count: u32,
        glyph_count: usize,
        text_bytes: usize,
    };

    pub const Key = struct {
        text: []const u8,
        weight: u4,
        italic: bool,
        ppem_x_26_6: u32,
        ppem_y_26_6: u32,
        has_provider: bool,
    };

    const KeyContext = struct {
        pub fn hash(_: KeyContext, key: Key) u64 {
            var h = std.hash.Wyhash.init(0x73_61_69_6c); // "snai"
            h.update(key.text);
            h.update(std.mem.asBytes(&key.weight));
            h.update(std.mem.asBytes(&key.italic));
            h.update(std.mem.asBytes(&key.ppem_x_26_6));
            h.update(std.mem.asBytes(&key.ppem_y_26_6));
            h.update(std.mem.asBytes(&key.has_provider));
            return h.final();
        }

        pub fn eql(_: KeyContext, a: Key, b: Key) bool {
            return a.weight == b.weight and
                a.italic == b.italic and
                a.ppem_x_26_6 == b.ppem_x_26_6 and
                a.ppem_y_26_6 == b.ppem_y_26_6 and
                a.has_provider == b.has_provider and
                std.mem.eql(u8, a.text, b.text);
        }
    };

    pub fn init(allocator: Allocator) ShapedRunCache {
        return .{
            .allocator = allocator,
            .entries = .{},
        };
    }

    pub fn deinit(self: *ShapedRunCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    /// Return a cached `ShapedText` for `(text, opts)`, shaping on
    /// first sight. On a cache hit the returned pointer's `glyphs`
    /// slice is byte-identical to a fresh `snail.shape()` call.
    ///
    /// Lifetime: valid until the next `evict` / `clear` / `deinit` on
    /// this cache.
    pub fn shape(
        self: *ShapedRunCache,
        faces: *Faces,
        text: []const u8,
        opts: ShapeOptions,
    ) !*const ShapedText {
        const lookup_key = keyFor(text, opts);
        if (self.entries.getPtr(lookup_key)) |hit| return hit;

        // Miss: shape and intern. We copy `text` into cache-owned
        // memory before inserting so the key stays valid for the
        // lifetime of the entry.
        var shaped = try snail.shape(self.allocator, faces, text, opts);
        errdefer shaped.deinit();

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        const owned_key = Key{
            .text = owned_text,
            .weight = lookup_key.weight,
            .italic = lookup_key.italic,
            .ppem_x_26_6 = lookup_key.ppem_x_26_6,
            .ppem_y_26_6 = lookup_key.ppem_y_26_6,
            .has_provider = lookup_key.has_provider,
        };
        try self.entries.putNoClobber(self.allocator, owned_key, shaped);
        return self.entries.getPtr(owned_key).?;
    }

    /// Drop the entry for `(text, opts)` if present. Invalidates any
    /// previously-returned pointer for that key.
    pub fn evict(self: *ShapedRunCache, text: []const u8, opts: ShapeOptions) void {
        const lookup_key = keyFor(text, opts);
        if (self.entries.fetchRemove(lookup_key)) |kv| {
            self.allocator.free(kv.key.text);
            var shaped = kv.value;
            shaped.deinit();
        }
    }

    /// Drop every entry. Invalidates all previously-returned pointers.
    pub fn clear(self: *ShapedRunCache) void {
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.text);
            kv.value_ptr.deinit();
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn stats(self: *const ShapedRunCache) Stats {
        var glyphs: usize = 0;
        var text_bytes: usize = 0;
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            glyphs += kv.value_ptr.glyphs.len;
            text_bytes += kv.key_ptr.text.len;
        }
        return .{
            .entry_count = self.entries.count(),
            .glyph_count = glyphs,
            .text_bytes = text_bytes,
        };
    }

    fn keyFor(text: []const u8, opts: ShapeOptions) Key {
        const ppem_x: u32 = if (opts.target_ppem) |p| p.x_26_6 else 0;
        const ppem_y: u32 = if (opts.target_ppem) |p| p.y_26_6 else 0;
        return .{
            .text = text,
            .weight = @intFromEnum(opts.style.weight),
            .italic = opts.style.italic,
            .ppem_x_26_6 = ppem_x,
            .ppem_y_26_6 = ppem_y,
            .has_provider = opts.advance_provider != null,
        };
    }
};

// ── Tests ──

const testing = std.testing;
const assets = @import("assets");
const Font = snail.Font;

test "ShapedRunCache returns the same pointer across repeated lookups" {
    var font = try Font.init(assets.noto_sans_regular);

    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    const first = try cache.shape(&faces, "FPS: 60", .{});
    const second = try cache.shape(&faces, "FPS: 60", .{});
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.stats().entry_count);

    // A different string lands in a different slot.
    const third = try cache.shape(&faces, "FPS: 59", .{});
    try testing.expect(third != first);
    try testing.expectEqual(@as(u32, 2), cache.stats().entry_count);
}

test "ShapedRunCache distinguishes styles and ppems" {
    var font = try Font.init(assets.noto_sans_regular);
    var bold = try Font.init(assets.noto_sans_bold);

    var faces = try Faces.build(testing.allocator, &.{
        .{ .font = &font, .weight = .regular },
        .{ .font = &bold, .weight = .bold },
    });
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    const a = try cache.shape(&faces, "hello", .{ .style = .{ .weight = .regular } });
    const b = try cache.shape(&faces, "hello", .{ .style = .{ .weight = .bold } });
    try testing.expect(a != b);

    const c = try cache.shape(&faces, "hello", .{ .target_ppem = .{ .x_26_6 = 14 << 6, .y_26_6 = 14 << 6 } });
    const d = try cache.shape(&faces, "hello", .{ .target_ppem = .{ .x_26_6 = 24 << 6, .y_26_6 = 24 << 6 } });
    try testing.expect(c != d);
    try testing.expectEqual(@as(u32, 4), cache.stats().entry_count);
}

test "ShapedRunCache reproduces snail.shape output byte-for-byte" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    var direct = try snail.shape(testing.allocator, &faces, "The quick brown fox", .{});
    defer direct.deinit();

    const cached = try cache.shape(&faces, "The quick brown fox", .{});

    try testing.expectEqual(direct.glyphs.len, cached.glyphs.len);
    for (direct.glyphs, cached.glyphs) |a, b| {
        try testing.expectEqual(a.face_index, b.face_index);
        try testing.expectEqual(a.glyph_id, b.glyph_id);
        try testing.expectEqual(a.x_advance, b.x_advance);
        try testing.expectEqual(a.x_offset, b.x_offset);
        try testing.expectEqual(a.source_start, b.source_start);
        try testing.expectEqual(a.font_id, b.font_id);
    }
}

test "ShapedRunCache evict and clear free the entries" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    _ = try cache.shape(&faces, "a", .{});
    _ = try cache.shape(&faces, "b", .{});
    _ = try cache.shape(&faces, "c", .{});
    try testing.expectEqual(@as(u32, 3), cache.stats().entry_count);

    cache.evict("b", .{});
    try testing.expectEqual(@as(u32, 2), cache.stats().entry_count);

    cache.clear();
    try testing.expectEqual(@as(u32, 0), cache.stats().entry_count);

    // Cache is reusable after clear.
    _ = try cache.shape(&faces, "again", .{});
    try testing.expectEqual(@as(u32, 1), cache.stats().entry_count);
}
