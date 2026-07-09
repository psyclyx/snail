//! A working-set atlas over a fixed `PagePool`, with LRU eviction.
//!
//! `snail.Atlas` is an immutable snapshot: pages are append-only and shared,
//! so a record can't be removed in place. A long-running app with an
//! unbounded glyph set (many scripts, sizes, dynamically loaded fonts) would
//! otherwise fill the pool and hit `error.OutOfLayers`. This helper turns the
//! fixed pool into a bounded cache: it retains the source for every resident
//! record, and reclaims by dropping the least-recently-used records and
//! rebuilding the atlas from the hot set — the recycled pages then back the
//! new snapshot.
//!
//! Allocation is split so cost is predictable. `tryEnsure` is the steady-state
//! path: it only extends the live snapshot (HAMT path-copy + one curve dup on a
//! miss) and returns `error.OutOfLayers` rather than reclaiming — no hidden
//! O(resident) burst. `compact(fraction)` is the ONLY thing that rebuilds, and
//! it runs when the caller asks, at a frame boundary it owns. `ensure` is the
//! convenience that does `tryEnsure` + compact-on-full for callers that don't
//! care where the burst lands.
//!
//! This is compaction-as-eviction: the natural fit for the snapshot model,
//! and the answer to "is a fixed pool enough for arbitrary apps" — the pool
//! bounds *resident* set size, not total glyphs seen. It lives in helpers,
//! not core: core stays primitive-only (see the rewrite plan's cache policy).
//!
//! Scope: glyph-shaped records — curves plus an optional `auto_light` warp
//! (with its shared base). Paint/gradient/image and multi-layer composite
//! records are out of scope for this cache; build those into a separate,
//! long-lived atlas and `combine` at draw time.
//!
//! Not thread-safe; one per thread (like the other helper caches).

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const RecordKey = snail.RecordKey;
const GlyphCurves = snail.GlyphCurves;
const Knot = snail.autohint.warp.Knot;

/// Everything needed to re-insert one record into a freshly rebuilt atlas,
/// owned by the cache so a rebuild never depends on the caller's memory.
const Stored = struct {
    curves: GlyphCurves,
    x_knots: ?[]Knot,
    y_knots: ?[]Knot,
    autohint_base: ?RecordKey,
    fill_rule: snail.FillRule,
    /// LRU stamp; larger is more recently used.
    used: u64,

    fn isAutohint(self: Stored) bool {
        return self.x_knots != null or self.y_knots != null;
    }

    fn deinit(self: *Stored, allocator: Allocator) void {
        self.curves.deinit();
        if (self.x_knots) |k| allocator.free(k);
        if (self.y_knots) |k| allocator.free(k);
        self.* = undefined;
    }
};

/// Fraction of resident records the convenience `ensure` drops per compaction
/// round when the pool overflows. Explicit callers pass their own to `compact`.
const default_compact_fraction: f32 = 0.25;

pub const GlyphAtlasCache = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    atlas: snail.Atlas,
    stored: std.AutoHashMapUnmanaged(RecordKey, Stored),
    clock: u64,

    pub const InsertError = snail.Atlas.InsertError;

    pub const Stats = struct {
        resident: u32,
        pages_in_use: u32,
        pages_total: u32,
        curve_bytes: u64,
        band_bytes: u64,
    };

    pub fn init(allocator: Allocator, pool: *snail.PagePool) GlyphAtlasCache {
        return .{
            .allocator = allocator,
            .pool = pool,
            .atlas = snail.Atlas.empty(allocator),
            .stored = .{},
            .clock = 0,
        };
    }

    pub fn deinit(self: *GlyphAtlasCache) void {
        self.atlas.deinit();
        var it = self.stored.valueIterator();
        while (it.next()) |s| s.deinit(self.allocator);
        self.stored.deinit(self.allocator);
        self.* = undefined;
    }

    /// The current atlas snapshot to render from. Valid until the next
    /// `compact` (or an `ensure` that has to compact) rebuilds it.
    pub fn atlasPtr(self: *const GlyphAtlasCache) *const snail.Atlas {
        return &self.atlas;
    }

    pub fn contains(self: *const GlyphAtlasCache, key: RecordKey) bool {
        return self.stored.contains(key);
    }

    /// Mark `key` as used this frame so eviction keeps it. No-op if absent.
    pub fn touch(self: *GlyphAtlasCache, key: RecordKey) void {
        if (self.stored.getPtr(key)) |s| {
            self.clock += 1;
            s.used = self.clock;
        }
    }

    /// Look up `key`'s record and mark it used. Null if not resident.
    pub fn lookupRecord(self: *GlyphAtlasCache, key: RecordKey) ?snail.AtlasRecord {
        const rec = self.atlas.lookupRecord(key) orelse return null;
        self.touch(key);
        return rec;
    }

    /// Steady-state insert. Extends the live snapshot in place; NEVER rebuilds
    /// or evicts. Returns `error.OutOfLayers` when the pool is full so the
    /// caller decides when to reclaim. Cost is bounded and predictable: a HAMT
    /// path-copy plus one curve/knot dup on a miss, or an LRU touch on a hit —
    /// no O(resident) burst hides here. Touches the key.
    ///
    /// `entry.autohint_base`, when set, must already be resident (insert the
    /// unhinted base before its per-ppem warps) — mirrors the atlas builder.
    /// Paint/composite fields on `entry` are ignored (see the module scope).
    pub fn tryEnsure(self: *GlyphAtlasCache, entry: snail.AtlasEntry) InsertError!void {
        if (self.stored.getPtr(entry.key)) |s| {
            self.clock += 1;
            s.used = self.clock;
            return;
        }
        var stored = try self.cloneEntry(entry);
        errdefer stored.deinit(self.allocator);
        try self.tryExtend(entry.key, &stored);
    }

    /// Reclaim capacity: drop ~`fraction` of the coldest resident records and
    /// rebuild the atlas once from the survivors. This is the ONLY O(resident)
    /// allocation burst in the cache, and it happens only when the caller asks,
    /// at a frame boundary it chooses. Returns the number of records evicted
    /// (0 = nothing was evictable — everything is a live autohint base). Bases
    /// still referenced by a surviving warp are never dropped.
    pub fn compact(self: *GlyphAtlasCache, fraction: f32) InsertError!usize {
        const before = self.stored.count();
        _ = self.evictColdest(fraction, null);
        try self.rebuildWith(undefined, null);
        return before - self.stored.count();
    }

    /// Convenience: `tryEnsure`, and on `OutOfLayers` `compact` and retry until
    /// it fits (or nothing more can be evicted). This is the burst-bearing call
    /// — a latency-sensitive caller uses `tryEnsure` + an explicit `compact`
    /// instead so the O(resident) rebuild lands on a boundary it controls.
    pub fn ensure(self: *GlyphAtlasCache, entry: snail.AtlasEntry) InsertError!void {
        // Keep the pending warp's base warm so a compaction round won't drop it.
        if (entry.autohint_base) |b| self.touch(b);
        while (true) {
            self.tryEnsure(entry) catch |err| switch (err) {
                error.OutOfLayers => {
                    if (try self.compact(default_compact_fraction) == 0) return error.OutOfLayers;
                    continue;
                },
                else => return err,
            };
            return;
        }
    }

    pub fn stats(self: *const GlyphAtlasCache) Stats {
        const ps = self.pool.stats();
        var curve_bytes: u64 = 0;
        var band_bytes: u64 = 0;
        var it = self.stored.valueIterator();
        while (it.next()) |s| {
            curve_bytes += s.curves.curveBytes();
            band_bytes += s.curves.bandBytes();
        }
        return .{
            .resident = self.stored.count(),
            .pages_in_use = ps.pages_in_use,
            .pages_total = ps.pages_total,
            .curve_bytes = curve_bytes,
            .band_bytes = band_bytes,
        };
    }

    // ── internals ──────────────────────────────────────────────────────────

    /// Extend the atlas with one stored record, committing it on success.
    fn tryExtend(self: *GlyphAtlasCache, key: RecordKey, stored: *Stored) InsertError!void {
        const grown = try self.atlas.extend(self.allocator, &.{storedEntry(key, stored.*)});
        self.atlas.deinit();
        self.atlas = grown;
        self.commit(key, stored);
    }

    /// Move `stored` into the resident map with a fresh LRU stamp. Reached
    /// only after a successful atlas build for an absent key.
    fn commit(self: *GlyphAtlasCache, key: RecordKey, stored: *Stored) void {
        self.clock += 1;
        stored.used = self.clock;
        self.stored.put(self.allocator, key, stored.*) catch {
            // Map-growth OOM after the atlas already grew — astronomically
            // rare. Drop the copy; the atlas keeps an untracked (unevictable)
            // record rather than corrupting the map. Never hit in practice.
            stored.deinit(self.allocator);
            return;
        };
        stored.* = undefined; // ownership moved into the map
    }

    /// Drop roughly `fraction` of resident records, coldest first, protecting
    /// any autohint base still referenced by a survivor (or by a pending insert,
    /// via `protect_base`). Returns true if at least one record was removed.
    fn evictColdest(self: *GlyphAtlasCache, fraction: f32, protect_base: ?RecordKey) bool {
        const n = self.stored.count();
        if (n == 0) return false;

        // Collect (used, key) and sort ascending by recency.
        var list = std.ArrayList(struct { used: u64, key: RecordKey }).empty;
        defer list.deinit(self.allocator);
        var it = self.stored.iterator();
        while (it.next()) |kv| {
            list.append(self.allocator, .{ .used = kv.value_ptr.used, .key = kv.key_ptr.* }) catch return false;
        }
        std.mem.sort(@TypeOf(list.items[0]), list.items, {}, struct {
            fn lt(_: void, a: @TypeOf(list.items[0]), b: @TypeOf(list.items[0])) bool {
                return a.used < b.used;
            }
        }.lt);

        // Bases referenced by surviving autohint entries must not be evicted.
        var want: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(n)) * fraction));
        if (want == 0) want = 1;

        var removed: u32 = 0;
        var i: usize = 0;
        while (i < list.items.len and removed < want) : (i += 1) {
            const key = list.items[i].key;
            if (protect_base) |b| if (b.eql(key)) continue; // base of the pending warp
            if (self.isReferencedBase(key)) continue; // keep bases of live warps
            var s = self.stored.fetchRemove(key).?.value;
            s.deinit(self.allocator);
            removed += 1;
        }
        return removed > 0;
    }

    /// Is `key` the autohint base of some resident (non-evicted) warp record?
    fn isReferencedBase(self: *const GlyphAtlasCache, key: RecordKey) bool {
        var it = self.stored.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.autohint_base) |base| {
                if (base.eql(key)) return true;
            }
        }
        return false;
    }

    /// Rebuild the atlas from all resident records, plus `extra` when given,
    /// ordered so autohint bases (always non-autohint entries) precede their
    /// dependents. On success `extra` is moved into the resident map. On
    /// failure the old snapshot is already gone (its pages had to recycle into
    /// the rebuild), so callers restore via a second `rebuildWith(_, null)`.
    fn rebuildWith(self: *GlyphAtlasCache, extra_key: RecordKey, extra: ?*Stored) InsertError!void {
        var entries = std.ArrayList(snail.AtlasEntry).empty;
        defer entries.deinit(self.allocator);

        // Non-autohint records first (autohint bases live here), then warps.
        var it = self.stored.iterator();
        while (it.next()) |kv| {
            if (!kv.value_ptr.isAutohint()) try entries.append(self.allocator, storedEntry(kv.key_ptr.*, kv.value_ptr.*));
        }
        if (extra) |e| if (!e.isAutohint()) try entries.append(self.allocator, storedEntry(extra_key, e.*));
        it = self.stored.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.isAutohint()) try entries.append(self.allocator, storedEntry(kv.key_ptr.*, kv.value_ptr.*));
        }
        if (extra) |e| if (e.isAutohint()) try entries.append(self.allocator, storedEntry(extra_key, e.*));

        // Drop the old snapshot first so its pages recycle into the rebuild.
        self.atlas.deinit();
        self.atlas = snail.Atlas.empty(self.allocator);
        self.atlas = try snail.Atlas.from(self.allocator, self.pool, entries.items);
        if (extra) |e| self.commit(extra_key, e);
    }

    fn cloneEntry(self: *GlyphAtlasCache, entry: snail.AtlasEntry) InsertError!Stored {
        var curves = try cloneCurves(self.allocator, entry.curves);
        errdefer curves.deinit();
        var x_knots: ?[]Knot = null;
        var y_knots: ?[]Knot = null;
        errdefer if (x_knots) |k| self.allocator.free(k);
        if (entry.autohint) |ah| {
            x_knots = try self.allocator.dupe(Knot, ah.x);
            y_knots = try self.allocator.dupe(Knot, ah.y);
        }
        return .{
            .curves = curves,
            .x_knots = x_knots,
            .y_knots = y_knots,
            .autohint_base = entry.autohint_base,
            .fill_rule = entry.fill_rule,
            .used = 0,
        };
    }
};

/// Build a borrowed `AtlasEntry` view over a stored record (no copy — the
/// atlas builder copies the bytes it needs during `from`/`extend`).
fn storedEntry(key: RecordKey, s: Stored) snail.AtlasEntry {
    const autohint: ?snail.AutohintKnots = if (s.isAutohint())
        .{ .x = s.x_knots orelse &.{}, .y = s.y_knots orelse &.{} }
    else
        null;
    return .{
        .key = key,
        .curves = s.curves,
        .fill_rule = s.fill_rule,
        .autohint = autohint,
        .autohint_base = s.autohint_base,
    };
}

fn cloneCurves(allocator: Allocator, src: GlyphCurves) Allocator.Error!GlyphCurves {
    const cb = try allocator.dupe(u16, src.curve_bytes);
    errdefer allocator.free(cb);
    const bb = try allocator.dupe(u16, src.band_bytes);
    return .{
        .allocator = allocator,
        .curve_bytes = cb,
        .band_bytes = bb,
        .backing = null,
        .curve_count = src.curve_count,
        .h_band_count = src.h_band_count,
        .v_band_count = src.v_band_count,
        .band_scale_x = src.band_scale_x,
        .band_scale_y = src.band_scale_y,
        .band_offset_x = src.band_offset_x,
        .band_offset_y = src.band_offset_y,
        .bbox = src.bbox,
    };
}

// ── tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");
const recordKey = snail.recordKey;

fn testPool(max_layers: u32) !*snail.PagePool {
    return snail.PagePool.init(testing.allocator, .{
        .max_layers = max_layers,
        .curve_words_per_page = 1 << 12,
        .band_words_per_page = 1 << 11,
    });
}

test "GlyphAtlasCache inserts and looks up glyphs" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    const pool = try testPool(8);
    defer pool.deinit();
    var cache = GlyphAtlasCache.init(testing.allocator, pool);
    defer cache.deinit();

    for ("abcXYZ") |ch| {
        const gid = try font.glyphIndex(ch);
        var c = try font.extractCurves(testing.allocator, testing.allocator, gid);
        defer c.deinit();
        const key = recordKey.unhintedGlyph(0, gid);
        try cache.ensure(.{ .key = key, .curves = c });
    }
    try testing.expectEqual(@as(u32, 6), cache.stats().resident);
    const gid_a = try font.glyphIndex('a');
    try testing.expect(cache.lookupRecord(recordKey.unhintedGlyph(0, gid_a)) != null);
    // Re-inserting an existing key is a no-op touch, not a duplicate.
    var again = try font.extractCurves(testing.allocator, testing.allocator, gid_a);
    defer again.deinit();
    try cache.ensure(.{ .key = recordKey.unhintedGlyph(0, gid_a), .curves = again });
    try testing.expectEqual(@as(u32, 6), cache.stats().resident);
}

test "GlyphAtlasCache evicts the coldest glyphs when the pool fills" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    // Tiny pool: only a few glyphs fit before eviction kicks in.
    const pool = try testPool(2);
    defer pool.deinit();
    var cache = GlyphAtlasCache.init(testing.allocator, pool);
    defer cache.deinit();

    // Insert far more distinct glyphs than the pool can hold at once.
    const text = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    for (text) |ch| {
        const gid = try font.glyphIndex(ch);
        var c = try font.extractCurves(testing.allocator, testing.allocator, gid);
        defer c.deinit();
        try cache.ensure(.{ .key = recordKey.unhintedGlyph(0, gid), .curves = c });
        // The just-inserted glyph is always resident.
        try testing.expect(cache.contains(recordKey.unhintedGlyph(0, gid)));
    }
    // The working set is bounded well under the total glyphs seen ...
    const resident = cache.stats().resident;
    try testing.expect(resident > 0 and resident < text.len);
    // ... and the pool never overflowed (all inserts succeeded above).
    try testing.expect(cache.stats().pages_in_use <= 2);
}

test "GlyphAtlasCache keeps a hot glyph across many evictions" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    const pool = try testPool(2);
    defer pool.deinit();
    var cache = GlyphAtlasCache.init(testing.allocator, pool);
    defer cache.deinit();

    const hot_gid = try font.glyphIndex('a');
    const hot_key = recordKey.unhintedGlyph(0, hot_gid);
    var hot = try font.extractCurves(testing.allocator, testing.allocator, hot_gid);
    defer hot.deinit();
    try cache.ensure(.{ .key = hot_key, .curves = hot });

    for ("bcdefghijklmnopqrstuvwxyz0123456789") |ch| {
        const gid = try font.glyphIndex(ch);
        var c = try font.extractCurves(testing.allocator, testing.allocator, gid);
        defer c.deinit();
        try cache.ensure(.{ .key = recordKey.unhintedGlyph(0, gid), .curves = c });
        cache.touch(hot_key); // keep 'a' warm every round
    }
    try testing.expect(cache.contains(hot_key));
    try testing.expect(cache.lookupRecord(hot_key) != null);
}

test "GlyphAtlasCache protects an autohint base from eviction" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var auto = try snail.autohint.AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer auto.deinit();
    const pool = try testPool(3);
    defer pool.deinit();
    var cache = GlyphAtlasCache.init(testing.allocator, pool);
    defer cache.deinit();

    const gid = try font.glyphIndex('a');
    const base_key = recordKey.unhintedGlyph(0, gid);
    var base = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer base.deinit();
    try cache.ensure(.{ .key = base_key, .curves = base });

    // A run of per-ppem warps over the same base, interleaved with churn from
    // other glyphs. The base must survive so each warp can alias it.
    for ([_]u32{ 9, 10, 11, 12, 13, 14, 16, 18, 22, 28 }) |px| {
        var xb: [snail.autohint.warp.max_knots]snail.autohint.warp.Knot = undefined;
        var yb: [snail.autohint.warp.max_knots]snail.autohint.warp.Knot = undefined;
        const knots = try auto.glyphKnots(testing.allocator, gid, px * 64, &xb, &yb);
        const warp_key = recordKey.autohintGlyph(0, gid, px * 64);
        cache.touch(base_key);
        try cache.ensure(.{
            .key = warp_key,
            .curves = snail.GlyphCurves.empty(testing.allocator),
            .autohint = .{ .x = knots.x, .y = knots.y },
            .autohint_base = base_key,
        });
        // Churn a throwaway glyph to pressure the pool.
        const other = try font.glyphIndex('m');
        var oc = try font.extractCurves(testing.allocator, testing.allocator, other);
        defer oc.deinit();
        _ = cache.ensure(.{ .key = recordKey.unhintedGlyph(1, @intCast(px)), .curves = oc }) catch {};
    }
    try testing.expect(cache.contains(base_key));
}

test "tryEnsure surfaces OutOfLayers without evicting; compact reclaims" {
    var font = try snail.Font.init(assets.dejavu_sans_mono);
    const pool = try testPool(2); // tiny: fills after a handful of glyphs
    defer pool.deinit();
    var cache = GlyphAtlasCache.init(testing.allocator, pool);
    defer cache.deinit();

    var filled: u32 = 0;
    var hit_full = false;
    for ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") |ch| {
        const gid = try font.glyphIndex(ch);
        var c = try font.extractCurves(testing.allocator, testing.allocator, gid);
        defer c.deinit();
        cache.tryEnsure(.{ .key = recordKey.unhintedGlyph(0, gid), .curves = c }) catch |e| {
            try testing.expectEqual(error.OutOfLayers, e);
            hit_full = true;
            break;
        };
        filled += 1;
    }
    // The pool is small enough that we must have hit the wall ...
    try testing.expect(hit_full);
    // ... and tryEnsure NEVER evicts: everything placed so far is still resident.
    try testing.expectEqual(filled, cache.stats().resident);

    // Explicit compaction is the only thing that reclaims; it reports the drop.
    const before = cache.stats().resident;
    const evicted = try cache.compact(0.25);
    try testing.expect(evicted > 0);
    try testing.expectEqual(before - @as(u32, @intCast(evicted)), cache.stats().resident);

    // A fresh tryEnsure now fits without any implicit rebuild.
    const gid = try font.glyphIndex('!');
    var c = try font.extractCurves(testing.allocator, testing.allocator, gid);
    defer c.deinit();
    try cache.tryEnsure(.{ .key = recordKey.unhintedGlyph(0, gid), .curves = c });
    try testing.expect(cache.lookupRecord(recordKey.unhintedGlyph(0, gid)) != null);
}
