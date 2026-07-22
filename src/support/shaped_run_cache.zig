//! Demo-local memoization of `snail.shape()` output keyed by the inputs that
//! determine its bytes.
//!
//! `snail.shape(faces, text, opts)` is memoized by the `Faces` pointer and
//! every value in `text` and `ShapeOptions`, including exact OpenType feature
//! values/ranges and the advance-provider context/callback identities. A
//! long-running session (terminal, banner
//! with mostly-static text, animated counter that lingers on the same
//! string) re-shapes the same string every frame; this helper short-
//! circuits that.
//!
//! ## Lifetime
//!
//! `shape()` returns a borrowed `*const ShapedText` owned by the cache.
//! The pointer stays valid until the next mutating call on the same
//! cache (`evict`, `clear`, `deinit`). The cache owns the entry's
//! `text`, `language`, and `features` slices and its `ShapedText.glyphs`; all
//! are freed on eviction.
//!
//! ## Invalidation
//!
//! Pointer identities are keyed, but mutable state reachable through them is
//! not inspectable. If a `Faces` is deinitialized/rebuilt in place, or an
//! advance provider changes the data behind the same context and callbacks,
//! the caller must `clear()` the cache before the next lookup.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const Faces = snail.Faces;
const OpenTypeFeature = snail.OpenTypeFeature;
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
        direction: u3,
        script: [4]u8,
        has_script: bool,
        language: []const u8,
        features: []const OpenTypeFeature,
        faces_identity: usize,
        provider_context: usize,
        provider_covers: usize,
        provider_get_advance: usize,
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
            h.update(std.mem.asBytes(&key.direction));
            h.update(&key.script);
            h.update(std.mem.asBytes(&key.has_script));
            h.update(key.language);
            for (key.features) |feature| hashFeature(&h, feature);
            h.update(std.mem.asBytes(&key.faces_identity));
            h.update(std.mem.asBytes(&key.provider_context));
            h.update(std.mem.asBytes(&key.provider_covers));
            h.update(std.mem.asBytes(&key.provider_get_advance));
            return h.final();
        }

        pub fn eql(_: KeyContext, a: Key, b: Key) bool {
            return a.weight == b.weight and
                a.italic == b.italic and
                a.ppem_x_26_6 == b.ppem_x_26_6 and
                a.ppem_y_26_6 == b.ppem_y_26_6 and
                a.has_provider == b.has_provider and
                a.direction == b.direction and
                std.mem.eql(u8, &a.script, &b.script) and
                a.has_script == b.has_script and
                std.mem.eql(u8, a.language, b.language) and
                featuresEql(a.features, b.features) and
                a.faces_identity == b.faces_identity and
                a.provider_context == b.provider_context and
                a.provider_covers == b.provider_covers and
                a.provider_get_advance == b.provider_get_advance and
                std.mem.eql(u8, a.text, b.text);
        }

        fn hashFeature(h: *std.hash.Wyhash, feature: OpenTypeFeature) void {
            h.update(&feature.tag);
            h.update(std.mem.asBytes(&feature.value));
            const has_range = feature.range != null;
            h.update(std.mem.asBytes(&has_range));
            if (feature.range) |range| {
                h.update(std.mem.asBytes(&range.start));
                h.update(std.mem.asBytes(&range.end));
            }
        }

        fn featuresEql(a: []const OpenTypeFeature, b: []const OpenTypeFeature) bool {
            if (a.len != b.len) return false;
            for (a, b) |af, bf| {
                if (!std.mem.eql(u8, &af.tag, &bf.tag) or af.value != bf.value) return false;
                if (af.range == null and bf.range == null) continue;
                if (af.range == null or bf.range == null) return false;
                if (af.range.?.start != bf.range.?.start or af.range.?.end != bf.range.?.end) return false;
            }
            return true;
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

    /// Return a cached `ShapedText` for `(faces identity, text, opts)`, shaping on
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
        const lookup_key = keyFor(faces, text, opts);
        if (self.entries.getPtr(lookup_key)) |hit| return hit;

        // Miss: shape and intern. We copy `text` into cache-owned
        // memory before inserting so the key stays valid for the
        // lifetime of the entry.
        var shaped = try snail.shape(self.allocator, faces, text, opts);
        errdefer shaped.deinit();

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);
        const owned_language = try self.allocator.dupe(u8, lookup_key.language);
        errdefer self.allocator.free(owned_language);
        const owned_features = try self.allocator.dupe(OpenTypeFeature, lookup_key.features);
        errdefer self.allocator.free(owned_features);

        const owned_key = Key{
            .text = owned_text,
            .weight = lookup_key.weight,
            .italic = lookup_key.italic,
            .ppem_x_26_6 = lookup_key.ppem_x_26_6,
            .ppem_y_26_6 = lookup_key.ppem_y_26_6,
            .has_provider = lookup_key.has_provider,
            .direction = lookup_key.direction,
            .script = lookup_key.script,
            .has_script = lookup_key.has_script,
            .language = owned_language,
            .features = owned_features,
            .faces_identity = lookup_key.faces_identity,
            .provider_context = lookup_key.provider_context,
            .provider_covers = lookup_key.provider_covers,
            .provider_get_advance = lookup_key.provider_get_advance,
        };
        try self.entries.putNoClobber(self.allocator, owned_key, shaped);
        return self.entries.getPtr(owned_key).?;
    }

    /// Drop the exact entry for `(faces identity, text, opts)` if present.
    /// Invalidates any previously-returned pointer for that key.
    pub fn evict(self: *ShapedRunCache, faces: *Faces, text: []const u8, opts: ShapeOptions) void {
        const lookup_key = keyFor(faces, text, opts);
        if (self.entries.fetchRemove(lookup_key)) |kv| {
            self.allocator.free(kv.key.text);
            self.allocator.free(kv.key.language);
            self.allocator.free(kv.key.features);
            var shaped = kv.value;
            shaped.deinit();
        }
    }

    /// Drop every entry. Invalidates all previously-returned pointers.
    pub fn clear(self: *ShapedRunCache) void {
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.text);
            self.allocator.free(kv.key_ptr.language);
            self.allocator.free(kv.key_ptr.features);
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

    fn keyFor(faces: *Faces, text: []const u8, opts: ShapeOptions) Key {
        const ppem_x: u32 = if (opts.target_ppem) |p| p.x_26_6 else 0;
        const ppem_y: u32 = if (opts.target_ppem) |p| p.y_26_6 else 0;
        const provider_context: usize = if (opts.advance_provider) |provider| @intFromPtr(provider.context) else 0;
        const provider_covers: usize = if (opts.advance_provider) |provider| @intFromPtr(provider.covers) else 0;
        const provider_get_advance: usize = if (opts.advance_provider) |provider| @intFromPtr(provider.get_advance) else 0;
        return .{
            .text = text,
            .weight = @intFromEnum(opts.style.weight),
            .italic = opts.style.italic,
            .ppem_x_26_6 = ppem_x,
            .ppem_y_26_6 = ppem_y,
            .has_provider = opts.advance_provider != null,
            .direction = if (opts.direction) |direction| @as(u3, @intCast(@intFromEnum(direction) + 1)) else 0,
            .script = opts.script orelse .{ 0, 0, 0, 0 },
            .has_script = opts.script != null,
            .language = opts.language orelse &.{},
            .features = opts.features,
            .faces_identity = @intFromPtr(faces),
            .provider_context = provider_context,
            .provider_covers = provider_covers,
            .provider_get_advance = provider_get_advance,
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

test "ShapedRunCache distinguishes segment properties" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    const inferred = try cache.shape(&faces, "abc", .{});
    const rtl = try cache.shape(&faces, "abc", .{ .direction = .rtl });
    const arabic_script = try cache.shape(&faces, "abc", .{ .script = "Arab".* });
    const english = try cache.shape(&faces, "abc", .{ .language = "en" });
    const french = try cache.shape(&faces, "abc", .{ .language = "fr" });

    try testing.expect(inferred != rtl);
    try testing.expect(rtl != arabic_script);
    try testing.expect(english != french);
    try testing.expectEqual(@as(u32, 5), cache.stats().entry_count);
}

test "ShapedRunCache owns and distinguishes exact OpenType features" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    var mutable_features = [_]OpenTypeFeature{.{ .tag = "liga".*, .value = 0 }};
    const no_liga = try cache.shape(&faces, "office", .{ .features = &mutable_features });

    // Mutating the caller's source slice must not mutate the interned key.
    mutable_features[0].value = 1;
    const equivalent = [_]OpenTypeFeature{.{ .tag = "liga".*, .value = 0 }};
    const same = try cache.shape(&faces, "office", .{ .features = &equivalent });
    try testing.expectEqual(no_liga, same);

    const ranged = [_]OpenTypeFeature{.{
        .tag = "liga".*,
        .value = 0,
        .range = .{ .start = 0, .end = 1 },
    }};
    const ranged_result = try cache.shape(&faces, "office", .{ .features = &ranged });
    try testing.expect(ranged_result != same);

    const default = try cache.shape(&faces, "office", .{});
    try testing.expect(default != same);
    try testing.expectEqual(@as(u32, 3), cache.stats().entry_count);
}

test "ShapedRunCache distinguishes Faces identity and evicts exactly" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces_a = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces_a.deinit();
    var faces_b = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces_b.deinit();

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();

    const a = try cache.shape(&faces_a, "same", .{});
    const b = try cache.shape(&faces_b, "same", .{});
    try testing.expect(a != b);
    try testing.expectEqual(@as(u32, 2), cache.stats().entry_count);

    cache.evict(&faces_a, "same", .{});
    try testing.expectEqual(@as(u32, 1), cache.stats().entry_count);
    cache.evict(&faces_b, "same", .{});
    try testing.expectEqual(@as(u32, 0), cache.stats().entry_count);
}

test "ShapedRunCache distinguishes advance-provider identities" {
    const Providers = struct {
        fn coversA(_: *anyopaque, _: u32) bool {
            return false;
        }
        fn coversB(_: *anyopaque, _: u32) bool {
            return false;
        }
        fn advanceA(_: *anyopaque, _: u32, _: u16, _: snail.TtHintPpem) ?i32 {
            return null;
        }
        fn advanceB(_: *anyopaque, _: u32, _: u16, _: snail.TtHintPpem) ?i32 {
            return null;
        }
    };

    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    var context_a: u8 = 0;
    var context_b: u8 = 0;

    var cache = ShapedRunCache.init(testing.allocator);
    defer cache.deinit();
    const ppem = snail.TtHintPpem.uniform(16 * 64);

    const base_opts: ShapeOptions = .{
        .advance_provider = .{
            .context = &context_a,
            .covers = Providers.coversA,
            .get_advance = Providers.advanceA,
        },
        .target_ppem = ppem,
    };
    const base = try cache.shape(&faces, "same", base_opts);
    try testing.expectEqual(base, try cache.shape(&faces, "same", base_opts));

    const other_context = try cache.shape(&faces, "same", .{
        .advance_provider = .{
            .context = &context_b,
            .covers = Providers.coversA,
            .get_advance = Providers.advanceA,
        },
        .target_ppem = ppem,
    });
    const other_covers = try cache.shape(&faces, "same", .{
        .advance_provider = .{
            .context = &context_a,
            .covers = Providers.coversB,
            .get_advance = Providers.advanceA,
        },
        .target_ppem = ppem,
    });
    const other_advance = try cache.shape(&faces, "same", .{
        .advance_provider = .{
            .context = &context_a,
            .covers = Providers.coversA,
            .get_advance = Providers.advanceB,
        },
        .target_ppem = ppem,
    });

    try testing.expect(other_context != base);
    try testing.expect(other_covers != base);
    try testing.expect(other_advance != base);
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

    cache.evict(&faces, "b", .{});
    try testing.expectEqual(@as(u32, 2), cache.stats().entry_count);

    cache.clear();
    try testing.expectEqual(@as(u32, 0), cache.stats().entry_count);

    // Cache is reusable after clear.
    _ = try cache.shape(&faces, "again", .{});
    try testing.expectEqual(@as(u32, 1), cache.stats().entry_count);
}
