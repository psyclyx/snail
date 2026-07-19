//! Backend-agnostic driver plumbing shared by the 2D `driver/renderer.zig`
//! (the interactive banner demo) and the 3D `game/driver.zig` (the game demo).
//!
//! These pieces know nothing about a specific backend: a `Pass` is a set of
//! snail (atlas, picture) pairs sharing one `DrawState`; `emitPasses` turns them
//! into `emit` words + segments; `syncPassBindings` keeps each pass's cache
//! bindings live; `FrameTimeStats` is the present/loop-interval ring the HUD
//! reads. Both drivers reuse them so the standard snail-pass machinery is
//! written exactly once.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");

// ── Pass ───────────────────────────────────────────────────────────────────

/// One draw call's worth of work. `atlases[i]` is the atlas backing
/// `pictures[i]`; all of a pass's pictures share a single `draw_state`
/// (one MVP, one surface, one raster config) and get composed into one
/// `backend.draw()` call.
///
/// The driver keeps per-pass binding state by position in the array,
/// so callers pass the same passes in the same order each frame. Set
/// `dirty=true` when any atlas in the pass added entries since the
/// last upload; the driver releases and re-issues that pass's bindings.
pub const Pass = struct {
    atlases: []const *const snail.Atlas,
    pictures: []const *const demo_support.Picture,
    draw_state: @import("snail-raster").DrawState,
    dirty: bool,
    /// CPU-backend hint: when true, fan tile work across the driver's
    /// thread pool; when false, rasterize on the calling thread. GPU
    /// backends ignore this field.
    cpu_parallel: bool = true,
};

/// Cap on the number of passes a single frame can run. Picked so the
/// per-driver pass state lives in inline arrays (no heap), bumpable.
pub const MAX_PASSES: usize = 4;
/// Per-pass max binding count, mirroring max_bindings on the cache.
pub const MAX_BINDINGS_PER_PASS: usize = 4;

/// Per-frame stage timings (µs). GPU drivers report zero for fields whose
/// cost lives on the GPU timeline (measured separately via timer queries).
/// Stages in execution order: clear → sync → emit → pass[0..N] → swap.
pub const FrameTimings = struct {
    clear_us: f64 = 0,
    sync_us: f64 = 0,
    emit_us: f64 = 0,
    pass_us: [MAX_PASSES]f64 = [_]f64{0} ** MAX_PASSES,
    swap_us: f64 = 0,
};

// ── Scratch buffer for emitted words + segments ──────────────────────────────

/// Owned by a driver, grown on demand each frame.
pub const ScratchBuf = struct {
    allocator: std.mem.Allocator,
    words: []u32 = &.{},
    segs: []snail.render.records.DrawSegment = &.{},

    pub fn init(allocator: std.mem.Allocator) ScratchBuf {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ScratchBuf) void {
        if (self.words.len > 0) self.allocator.free(self.words);
        if (self.segs.len > 0) self.allocator.free(self.segs);
    }

    pub fn ensure(self: *ScratchBuf, word_count: usize, seg_count: usize) !void {
        if (self.words.len < word_count) {
            if (self.words.len > 0) self.allocator.free(self.words);
            self.words = try self.allocator.alloc(u32, word_count);
        }
        if (self.segs.len < seg_count) {
            if (self.segs.len > 0) self.allocator.free(self.segs);
            self.segs = try self.allocator.alloc(snail.render.records.DrawSegment, seg_count);
        }
    }
};

/// Per-pass view onto the shared scratch buffer. `words` spans the full
/// emitted range across every pass (segment `words_offset` values index it
/// directly); `segs` is the pass's own sub-slice of segments.
pub const PassRecords = struct {
    words: []const u32,
    segs: []const snail.render.records.DrawSegment,
};

/// Driver-side per-pass binding state. Indexed by pass position; the caller
/// passes the same pass count and order each frame so the indexes stay stable.
pub const PassState = struct {
    bindings: [MAX_BINDINGS_PER_PASS]snail.render.records.Binding = undefined,
    count: u8 = 0,
    initialized: bool = false,
};

/// Total words needed to emit every picture across every pass.
pub fn passesWordBudget(passes: []const Pass) usize {
    var total: usize = 0;
    for (passes) |pass| {
        for (pass.pictures) |picture| total += snail.emit.wordBudget(picture.shapes.len);
    }
    return total;
}

/// Conservative segment budget. A picture can alternate semantic families
/// (for example unhinted/autohint/TrueType validation rows), so one picture
/// may emit many segments even though adjacent shapes normally coalesce.
pub fn passesSegBudget(passes: []const Pass) usize {
    var total: usize = 0;
    for (passes) |pass| {
        for (pass.pictures) |picture| total += snail.emit.segmentBudget(picture.shapes.len);
    }
    return total;
}

/// Emit every pass into a contiguous scratch run. Every PassRecords shares the
/// same `words` slice (the full emitted extent) so segment `words_offset`
/// values keep their absolute meaning; each pass owns only its segment
/// sub-slice.
pub fn emitPasses(
    scratch: *ScratchBuf,
    passes: []const Pass,
    pass_states: []const PassState,
    out_records: []PassRecords,
) !void {
    std.debug.assert(passes.len == out_records.len);
    try scratch.ensure(passesWordBudget(passes), passesSegBudget(passes));
    var wlen: usize = 0;
    var slen: usize = 0;
    for (passes, pass_states, 0..) |pass, state, i| {
        std.debug.assert(state.initialized);
        std.debug.assert(state.count == pass.atlases.len);
        const seg_start = slen;
        for (pass.atlases, pass.pictures, state.bindings[0..state.count]) |atlas, picture, binding| {
            _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, binding, atlas, picture.shapes, .identity, .{ 1, 1, 1, 1 });
        }
        out_records[i] = .{
            .words = scratch.words[0..0], // patched below once wlen is final
            .segs = scratch.segs[seg_start..slen],
        };
    }
    const full_words = scratch.words[0..wlen];
    for (out_records) |*rec| rec.words = full_words;
}

/// Ensure each pass's bindings are live in `cache`. Releases stale bindings on
/// `pass.dirty`; reuses bindings otherwise.
pub fn syncPassBindings(
    comptime CacheType: type,
    cache: *CacheType,
    allocator: std.mem.Allocator,
    passes: []const Pass,
    pass_states: []PassState,
    cache_was_reinitialized: bool,
) !void {
    for (passes, pass_states) |pass, *state| {
        const needs_upload = cache_was_reinitialized or pass.dirty or !state.initialized;
        if (!needs_upload) continue;
        if (state.initialized and !cache_was_reinitialized) {
            for (state.bindings[0..state.count]) |b| cache.release(b);
        }
        state.initialized = false;
        std.debug.assert(pass.atlases.len <= MAX_BINDINGS_PER_PASS);
        try cache.upload(allocator, pass.atlases, state.bindings[0..pass.atlases.len]);
        state.count = @intCast(pass.atlases.len);
        state.initialized = true;
    }
}

// ── Color utility ────────────────────────────────────────────────────────────

pub fn unitToU8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255);
}

pub fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn clearColorForShader(color_srgb: [4]f32, encoding: @import("snail-raster").TargetEncoding) [4]f32 {
    return switch (encoding.shaderOutputEncoding()) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}

test "segment budget covers every shape in mixed pictures" {
    const shapes_a = [_]snail.Shape{.{}, .{}, .{}};
    const shapes_b = [_]snail.Shape{.{}, .{}};
    const picture_a = demo_support.Picture{ .allocator = std.testing.allocator, .shapes = &shapes_a };
    const picture_b = demo_support.Picture{ .allocator = std.testing.allocator, .shapes = &shapes_b };
    const pictures = [_]*const demo_support.Picture{ &picture_a, &picture_b };
    const passes = [_]Pass{.{
        .atlases = &.{},
        .pictures = &pictures,
        .draw_state = undefined,
        .dirty = false,
    }};

    try std.testing.expectEqual(@as(usize, shapes_a.len + shapes_b.len), passesSegBudget(&passes));
}

// ── Frame-time stats (HUD) ───────────────────────────────────────────────────
//
// Rolling ring of recent inter-frame intervals (µs). Feeds a mean-FPS +
// p50/p95/max readout and a 60 Hz vsync-cadence histogram. Resolution is
// microseconds-since-prev so the math works for any refresh rate and a long
// compositor wait shows up faithfully as a long frame.

pub const FrameTimeStats = struct {
    pub const WINDOW: usize = 120; // ~2 s at 60 fps
    pub const VSYNC_US: u32 = 16_667;

    times_us: [WINDOW]u32 = [_]u32{0} ** WINDOW,
    write_idx: usize = 0,
    count: usize = 0,

    pub fn record(self: *FrameTimeStats, frame_us: u32) void {
        self.times_us[self.write_idx] = frame_us;
        self.write_idx = (self.write_idx + 1) % WINDOW;
        if (self.count < WINDOW) self.count += 1;
    }

    pub const Snapshot = struct {
        fps: f32 = 0,
        p50_us: u32 = 0,
        p95_us: u32 = 0,
        max_us: u32 = 0,
        /// Frames bucketed by which 60 Hz vsync interval they spanned:
        /// [0]=≤1 (smooth 60), [1]=2 (smooth 30), [2]=3, [3]=≥4. A split = judder.
        cadence: [4]u32 = .{ 0, 0, 0, 0 },
        count: u32 = 0,
    };

    pub fn snapshot(self: *const FrameTimeStats) Snapshot {
        if (self.count == 0) return .{};
        var sorted: [WINDOW]u32 = undefined;
        @memcpy(sorted[0..self.count], self.times_us[0..self.count]);
        std.sort.pdq(u32, sorted[0..self.count], {}, std.sort.asc(u32));

        var cad = [_]u32{ 0, 0, 0, 0 };
        var sum_us: u64 = 0;
        for (self.times_us[0..self.count]) |t| {
            sum_us += t;
            // Round to nearest whole vsync count (boundary at the midpoint,
            // 8.33/25/41.67 ms) so a steady 60 fps stream with a few ms of
            // scheduling jitter bins cleanly as 1× instead of splitting 1×/2×.
            const vsync_count = (t + VSYNC_US / 2) / VSYNC_US;
            const bucket: usize = if (vsync_count <= 1) 0 else if (vsync_count == 2) 1 else if (vsync_count == 3) 2 else 3;
            cad[bucket] += 1;
        }
        const mean_us: f32 = if (sum_us > 0)
            @as(f32, @floatFromInt(sum_us)) / @as(f32, @floatFromInt(self.count))
        else
            0;
        const fps: f32 = if (mean_us > 1.0) 1_000_000.0 / mean_us else 0;
        const n = self.count;
        return .{
            .fps = fps,
            .p50_us = sorted[n / 2],
            .p95_us = sorted[@min((n * 95) / 100, n - 1)],
            .max_us = sorted[n - 1],
            .cadence = cad,
            .count = @intCast(n),
        };
    }
};
