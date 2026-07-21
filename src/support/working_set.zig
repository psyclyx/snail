//! Bounded-residency policy over a snail `Atlas` — the worked example for
//! the capacity model (see the module notes on `snail.Atlas`).
//!
//! Core snail never evicts: the `PagePool` is a fixed budget, recording is
//! idempotent, and `error.OutOfLayers` is the caller's signal to shrink the
//! resident set. This type is one reasonable retention policy — touch
//! tracking plus evict-by-filtered-compact — written as demo support so
//! embedders copy the shape rather than inherit the policy:
//!
//!   var ws = WorkingSet.init(allocator, pool, .{});
//!   // each frame:
//!   ws.beginFrame();
//!   try snail.recordUnhintedRun(&ws.atlas, allocator, &faces, &shaped, .{});
//!   try ws.touchShapes(placed_shapes);
//!   if (try ws.ensureHeadroom(scratch)) rebuildDeviceBindings();
//!
//! Eviction runs `Atlas.compact` with a keep-filter over recently touched
//! keys. Compaction acquires new pages before the old atlas releases its
//! own, so the policy triggers while `pool.free_count` is still above
//! `options.reserve_layers` — waiting for hard `OutOfLayers` would leave
//! no room to rebuild into. After a rebuild every prior `Binding` is
//! stale; the caller re-uploads to its `DeviceAtlas` backends.
//!
//! `ns.tt_advance` records are always kept: they cost no pages and losing
//! them would re-run the TT VM at shape time for no space gain.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const RecordKey = snail.record_key.RecordKey;

pub const WorkingSet = struct {
    pub const Options = struct {
        /// Evict when the pool's free layers drop below this. Must cover
        /// the compacted working set's page count — compaction needs its
        /// destination pages while the source atlas still holds its own.
        reserve_layers: u32 = 2,
        /// Records untouched for more than this many `beginFrame` ticks
        /// are eviction candidates.
        max_idle_ticks: u64 = 300,
    };

    allocator: Allocator,
    pool: *snail.PagePool,
    /// The store. Callers record into and emit against this directly;
    /// the working set only manages its lifetime.
    atlas: snail.Atlas,
    options: Options,
    last_touch: std.AutoHashMapUnmanaged(RecordKey, u64) = .empty,
    tick: u64 = 0,

    pub fn init(allocator: Allocator, pool: *snail.PagePool, options: Options) WorkingSet {
        return .{
            .allocator = allocator,
            .pool = pool,
            .atlas = snail.Atlas.init(allocator, pool),
            .options = options,
        };
    }

    pub fn deinit(self: *WorkingSet) void {
        self.last_touch.deinit(self.allocator);
        self.atlas.deinit();
        self.* = undefined;
    }

    pub fn beginFrame(self: *WorkingSet) void {
        self.tick += 1;
    }

    /// Mark one record as part of the current working set.
    pub fn touch(self: *WorkingSet, key: RecordKey) !void {
        try self.last_touch.put(self.allocator, key, self.tick);
    }

    /// Mark every record a placed shape references. Call with each run's
    /// shapes after placement — emit-time keys are exactly the resident
    /// set the next eviction must keep.
    pub fn touchShapes(self: *WorkingSet, shapes: []const snail.Shape) !void {
        for (shapes) |shape| try self.touch(shape.key);
    }

    /// Rebuild the store from the recently touched set when pool headroom
    /// runs low. Returns true when the atlas was replaced — every
    /// previously issued `Binding` is then stale and the caller re-uploads.
    pub fn ensureHeadroom(self: *WorkingSet, scratch: Allocator) !bool {
        if (self.pool.free_count >= self.options.reserve_layers) return false;

        const Filter = struct {
            ws: *WorkingSet,
            fn keep(context: *anyopaque, key: RecordKey) bool {
                const filter: *@This() = @ptrCast(@alignCast(context));
                // Advances are page-free: always worth keeping.
                if (key.namespace == snail.record_key.ns.tt_advance) return true;
                const touched = filter.ws.last_touch.get(key) orelse return false;
                return filter.ws.tick - touched <= filter.ws.options.max_idle_ticks;
            }
        };
        var filter = Filter{ .ws = self };
        const compacted = try self.atlas.compact(self.allocator, scratch, .{
            .context = @ptrCast(&filter),
            .keep = Filter.keep,
        });
        self.atlas.deinit();
        self.atlas = compacted;

        // Drop touch entries for evicted records so the map tracks the
        // resident set rather than growing with history.
        var stale: std.ArrayList(RecordKey) = .empty;
        defer stale.deinit(self.allocator);
        var it = self.last_touch.keyIterator();
        while (it.next()) |key| {
            if (!self.atlas.contains(key.*) and self.atlas.lookupTtAdvance(key.*) == null) {
                try stale.append(self.allocator, key.*);
            }
        }
        for (stale.items) |key| _ = self.last_touch.remove(key);
        return true;
    }
};

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "working set evicts cold records and keeps the touched set drawable" {
    const allocator = testing.allocator;
    var font = try snail.Font.init(@import("assets").noto_sans_regular);
    var faces = try snail.Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    // A deliberately tiny pool: two content pages plus reserve headroom.
    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 4096,
        .band_words_per_page = 2048,
    });
    defer pool.deinit();

    var ws = WorkingSet.init(allocator, pool, .{ .reserve_layers = 4, .max_idle_ticks = 1 });
    defer ws.deinit();

    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    // Frame 1: record and touch a run.
    ws.beginFrame();
    var cold = try snail.shape(allocator, &faces, "ABCDEFGH", .{});
    defer cold.deinit();
    try snail.recordUnhintedRun(&ws.atlas, allocator, &faces, &cold, .{});
    const cold_shapes = try snail.placeRunAlloc(allocator, &cold, null, .{
        .baseline = .{ .x = 0, .y = 20 },
        .em = 20,
        .color = .{ 1, 1, 1, 1 },
    });
    defer allocator.free(cold_shapes);
    try ws.touchShapes(cold_shapes);

    // Later frames: new content, old run never touched again.
    ws.beginFrame();
    ws.beginFrame();
    ws.beginFrame();
    var hot = try snail.shape(allocator, &faces, "xyz", .{});
    defer hot.deinit();
    try snail.recordUnhintedRun(&ws.atlas, allocator, &faces, &hot, .{});
    const hot_shapes = try snail.placeRunAlloc(allocator, &hot, null, .{
        .baseline = .{ .x = 0, .y = 40 },
        .em = 20,
        .color = .{ 1, 1, 1, 1 },
    });
    defer allocator.free(hot_shapes);
    try ws.touchShapes(hot_shapes);

    // reserve_layers == max_layers forces the rebuild branch: any recorded
    // page drops free_count below the reserve.
    const before = ws.atlas.recordCount();
    try testing.expect(try ws.ensureHeadroom(scratch.allocator()));

    // Cold records evicted, hot records still resident and complete.
    try testing.expect(ws.atlas.recordCount() < before);
    for (hot_shapes) |shape| try testing.expect(ws.atlas.contains(shape.key));
    for (cold_shapes) |shape| try testing.expect(!ws.atlas.contains(shape.key));
}
