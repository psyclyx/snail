//! Interactive demo entry point.
//!
//! Opens a Wayland window and renders the shared banner content
//! (rounded-rect card + wordmark + tagline + vector snail + multi-script
//! row) via the new snail API. Backed by `renderer_driver.zig`, which
//! wraps each backend's `Renderer` + `BackendCache` cache + emit/draw
//! shim. Keys cycle backend (C), AA mode (B), and hinting (H); arrows
//! pan; Z/X zoom; R toggles rotate; L dumps a brief repro frame; Esc
//! quits.

const std = @import("std");
const snail = @import("snail");
const snail_helpers = @import("snail-helpers");
const build_options = @import("build_options");
const assets_data = @import("assets");
const renderer_driver = @import("renderer_driver.zig");
const demo_banner = @import("banner.zig");
const hud_mod = @import("hud.zig");
const autohint_compare = @import("autohint_compare.zig");
const subpixel_detect = @import("platform/subpixel.zig");
const wayland = @import("platform/wayland.zig");
const presentation = @import("platform/presentation.zig");

const KEY_R = wayland.KEY_R;
const KEY_L = wayland.KEY_L;
const KEY_Z = wayland.KEY_Z;
const KEY_X = wayland.KEY_X;
const KEY_H = wayland.KEY_H;
const KEY_B = wayland.KEY_B;
const KEY_C = wayland.KEY_C;
const KEY_T = wayland.KEY_T;
const KEY_O = wayland.KEY_O;
const KEY_V = wayland.KEY_V;
const KEY_G = wayland.KEY_G;
const KEY_F = wayland.KEY_F;
const KEY_ESCAPE = wayland.KEY_ESCAPE;
const KEY_LEFT = wayland.KEY_LEFT;
const KEY_RIGHT = wayland.KEY_RIGHT;
const KEY_UP = wayland.KEY_UP;
const KEY_DOWN = wayland.KEY_DOWN;

const HintMode = enum {
    always,
    never,
    still,

    fn next(self: HintMode) HintMode {
        return switch (self) {
            .always => .never,
            .never => .still,
            .still => .always,
        };
    }

    fn name(self: HintMode) []const u8 {
        return switch (self) {
            .always => "always-tt",
            .never => "never-tt",
            .still => "tt-when-still",
        };
    }

    fn active(self: HintMode, moving: bool) bool {
        return switch (self) {
            .always => true,
            .never => false,
            .still => !moving,
        };
    }
};

fn cycleSubpixelOrder(o: snail.SubpixelOrder) snail.SubpixelOrder {
    return switch (o) {
        .none => .rgb,
        .rgb => .bgr,
        .bgr => .vrgb,
        .vrgb => .vbgr,
        .vbgr => .none,
    };
}

fn aaName(o: snail.SubpixelOrder) []const u8 {
    return switch (o) {
        .none => "grayscale",
        .rgb => "subpixel-RGB",
        .bgr => "subpixel-BGR",
        .vrgb => "subpixel-VRGB",
        .vbgr => "subpixel-VBGR",
    };
}

fn toSnailEncoding(encoding: presentation.ColorEncoding) snail.ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: presentation.Info) snail.TargetEncoding {
    return .{
        .attachment = toSnailEncoding(info.framebuffer_encoding),
        .stored_pixels = .srgb,
    };
}

fn logPresentationInfo(info: presentation.Info) void {
    const scale = info.scale();
    std.debug.print(
        "presentation: logical={}x{} framebuffer={}x{} scale={d:.2}x{d:.2} buffer_scale={} framebuffer={s} resample={}\n",
        .{
            info.logical_size[0],
            info.logical_size[1],
            info.framebuffer_size[0],
            info.framebuffer_size[1],
            scale[0],
            scale[1],
            info.buffer_scale,
            @tagName(info.framebuffer_encoding),
            info.will_resample,
        },
    );
}

fn dumpReproFrame(
    frame_count: u32,
    backend: []const u8,
    current_order: snail.SubpixelOrder,
    hint_mode: HintMode,
    hint_active: bool,
    present: presentation.Info,
    pan_x: f32,
    pan_y: f32,
    zoom: f32,
    angle: f32,
) void {
    std.debug.print("\n--- snail repro frame {} ---\n", .{frame_count});
    std.debug.print("backend={s} aa={s} hint={s}{s}\n", .{
        backend,
        aaName(current_order),
        hint_mode.name(),
        if (hint_active) "" else " (off)",
    });
    std.debug.print("logical_size={}x{} framebuffer={}x{}\n", .{
        present.logical_size[0],   present.logical_size[1],
        present.framebuffer_size[0], present.framebuffer_size[1],
    });
    std.debug.print("pan=({d:.2},{d:.2}) zoom={d:.4} angle={d:.4}\n", .{ pan_x, pan_y, zoom, angle });
    std.debug.print("--- end snail repro frame ---\n", .{});
}

const ContentCache = struct {
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    assets: demo_banner.Assets,
    content: ?demo_banner.Content = null,
    last_size: [2]u32 = .{ 0, 0 },
    last_hint_active: bool = false,
    last_hint_ppem_bits: u32 = 0,

    fn init(allocator: std.mem.Allocator) !ContentCache {
        const pool = try snail.PagePool.init(allocator, .{
            .max_layers = 24,
            .curve_words_per_page = 1 << 18,
            .band_words_per_page = 1 << 16,
        });
        errdefer pool.deinit();
        const assets = try demo_banner.Assets.init(allocator);
        return .{ .allocator = allocator, .pool = pool, .assets = assets };
    }

    fn deinit(self: *ContentCache) void {
        if (self.content) |*c| c.deinit();
        self.assets.deinit();
        self.pool.deinit();
    }

    /// Get or rebuild the full banner content. Cache key is just
    /// (size, hint_active, hint_ppem). `world_to_pixel` is *not* part of
    /// the key: pan/zoom/rotation never invalidates content. Hinted runs
    /// stored on `Content.hinted_runs` get re-snapped per frame against
    /// the current `world_to_pixel` via `Content.composeTextPicture`.
    ///
    /// The long-lived `Assets` (fonts, hinter, hinted-glyph cache) and
    /// `PagePool` survive across rebuilds, so the TT VM only runs once per
    /// `(glyph_id, ppem)`. Returns `dirty=true` when content was rebuilt.
    fn get(
        self: *ContentCache,
        width: u32,
        height: u32,
        hint_active: bool,
        hint_ppem_scale: f32,
    ) !struct { content: *demo_banner.Content, dirty: bool } {
        const ppem_bits: u32 = @bitCast(hint_ppem_scale);
        const same = self.content != null and
            self.last_size[0] == width and
            self.last_size[1] == height and
            self.last_hint_active == hint_active and
            (!hint_active or self.last_hint_ppem_bits == ppem_bits);
        if (same) return .{ .content = &self.content.?, .dirty = false };

        if (self.content) |*old| old.deinit();
        self.content = null;

        const hint_opts: demo_banner.HintOptions = .{
            .enabled = hint_active,
            .ppem_scale = hint_ppem_scale,
        };
        self.content = try demo_banner.build(
            self.allocator,
            self.pool,
            &self.assets,
            @floatFromInt(width),
            @floatFromInt(height),
            .{ .x = 1, .y = 1 },
            hint_opts,
        );
        self.last_size = .{ width, height };
        self.last_hint_active = hint_active;
        self.last_hint_ppem_bits = ppem_bits;
        return .{ .content = &self.content.?, .dirty = true };
    }
};

// ── Per-frame timing accumulator ──
//
// Finer-grained replacement for the original 1-second-averaged timing
// block. Each frame contributes a `FrameSample` (CPU-driver stage
// timings + main-loop stage timings + wall-clock for the renderFrame
// call). The accumulator does two things:
//   1. tracks running sums for averages over the current ~1 s window,
//   2. remembers the single worst frame in the window so its per-stage
//      breakdown can be printed at window end — that's where stutters
//      surface, not in the averages.
// On top of that, `observe` prints an inline `[stutter]` line for any
// individual frame whose total exceeds `stutter_floor_us` AND is more
// than `stutter_ratio` times the running average. This makes a hitch
// during a pan visible the moment it happens, not after the next
// summary.

const FrameSample = struct {
    /// Time spent idle in `shouldClose()` (Wayland frame-callback wait).
    frame_wait_us: f64,
    /// HUD picture build (shape glyphs into a fresh picture).
    hud_build_us: f64,
    /// Per-frame hinted-text re-snap (composeTextPicture).
    compose_us: f64,
    /// CPU driver stage breakdown (clear / sync / emit / pass[] / swap).
    driver: renderer_driver.FrameTimings,
    /// Wall clock for the whole `Driver.renderFrame` call.
    render_us: f64,
    /// Number of passes this frame so worst-frame prints know which
    /// `pass_us` slots are live.
    pass_count: u8,

    /// Sum of the slices that contribute to "main thread budget for
    /// this frame": everything we can act on, excluding the wait.
    fn workUs(self: FrameSample) f64 {
        return self.hud_build_us + self.compose_us + self.render_us;
    }

    /// Total wall-clock impression of the frame, including the time we
    /// blocked on the compositor's frame callback. Used for outlier
    /// detection — a long wait at the top of the loop reads as a
    /// stutter to the user even if our own work was fast.
    fn totalUs(self: FrameSample) f64 {
        return self.frame_wait_us + self.workUs();
    }
};

const FrameTimingAccum = struct {
    window_start: f64 = 0,
    frames: u32 = 0,
    /// Frames whose work blew the 60 Hz budget. The user feels these as
    /// stutters: the compositor pushes the next frame's wait by a full
    /// vsync (~16.67 ms), which is what shows up as a wait spike on the
    /// *following* frame — so tracking the cause separately matters.
    over_budget_frames: u32 = 0,
    sum: FrameSampleSums = .{},
    /// Highest-`render_us` frame: the work spike that *causes* a
    /// stutter. This is what to optimize.
    worst_work: ?FrameSample = null,
    worst_work_moving: bool = false,
    /// Highest-`totalUs` frame: the symptom — the frame whose `wait`
    /// got pushed to a full vsync after the prior frame ran long.
    /// Useful for confirming vsync-miss recovery is what hurts.
    worst_total: ?FrameSample = null,
    worst_total_moving: bool = false,

    /// Inline `[stutter]` print floor — frames faster than this don't
    /// register as stutters even if they're well above the recent mean.
    /// 16.6 ms is the 60 Hz budget; anything past that drops a frame.
    const stutter_floor_us: f64 = 16_000;
    /// And they have to be at least this much slower than the running
    /// average to count. Keeps the log readable when the average is
    /// itself elevated.
    const stutter_ratio: f64 = 1.5;
    /// 60 Hz vsync budget. Frames whose `render_us` exceeds this are
    /// virtually guaranteed to miss a vsync and produce a visible hitch.
    const vsync_budget_us: f64 = 16_667;

    fn reset(self: *FrameTimingAccum, now: f64) void {
        self.* = .{ .window_start = now };
    }

    /// Records `frame` and returns true if this call caused a window
    /// summary flush (so the caller can print follow-up info like the
    /// per-instance profile snapshot tied to the just-printed worst
    /// frame).
    fn observe(self: *FrameTimingAccum, frame: FrameSample, now: f64, moving: bool) bool {
        // Compare against the running average BEFORE folding this frame
        // into the sums, so a single huge frame doesn't raise its own
        // detection bar.
        if (self.frames > 0) {
            const avg = self.sum.render_us / @as(f64, @floatFromInt(self.frames));
            if (frame.render_us > stutter_floor_us and frame.render_us > avg * stutter_ratio) {
                printStutterLine(frame, avg, moving);
            }
        }

        self.sum.add(frame);
        self.frames += 1;
        if (frame.render_us > vsync_budget_us) self.over_budget_frames += 1;
        if (self.worst_work == null or frame.render_us > self.worst_work.?.render_us) {
            self.worst_work = frame;
            self.worst_work_moving = moving;
        }
        if (self.worst_total == null or frame.totalUs() > self.worst_total.?.totalUs()) {
            self.worst_total = frame;
            self.worst_total_moving = moving;
        }

        if (now - self.window_start >= 1.0 and self.frames > 0) {
            self.flush(now);
            return true;
        }
        return false;
    }

    fn flush(self: *FrameTimingAccum, now: f64) void {
        const frames_f: f64 = @floatFromInt(self.frames);
        const fps_measured: f64 = frames_f / (now - self.window_start);
        std.debug.print(
            "\n[timing] {d} frames @ {d:.1} FPS, {d} over 16.67 ms | avg µs: wait={d:.0} hud_build={d:.0} compose={d:.0} clear={d:.0} sync={d:.0} emit={d:.0} pass0={d:.0} pass1={d:.0} swap={d:.0} render={d:.0}\n",
            .{
                self.frames,
                fps_measured,
                self.over_budget_frames,
                self.sum.frame_wait_us / frames_f,
                self.sum.hud_build_us / frames_f,
                self.sum.compose_us / frames_f,
                self.sum.driver.clear_us / frames_f,
                self.sum.driver.sync_us / frames_f,
                self.sum.driver.emit_us / frames_f,
                self.sum.driver.pass_us[0] / frames_f,
                self.sum.driver.pass_us[1] / frames_f,
                self.sum.driver.swap_us / frames_f,
                self.sum.render_us / frames_f,
            },
        );
        if (self.worst_work) |w| {
            std.debug.print(
                "[timing] worst work  (moving={s}): render={d:.0} hud_build={d:.0} compose={d:.0} clear={d:.0} sync={d:.0} emit={d:.0} pass0={d:.0} pass1={d:.0} swap={d:.0} µs\n",
                .{
                    if (self.worst_work_moving) "yes" else "no",
                    w.render_us,
                    w.hud_build_us,
                    w.compose_us,
                    w.driver.clear_us,
                    w.driver.sync_us,
                    w.driver.emit_us,
                    w.driver.pass_us[0],
                    w.driver.pass_us[1],
                    w.driver.swap_us,
                },
            );
        }
        if (self.worst_total) |w| {
            std.debug.print(
                "[timing] worst total (moving={s}): total={d:.0} wait={d:.0} render={d:.0} µs\n",
                .{
                    if (self.worst_total_moving) "yes" else "no",
                    w.totalUs(),
                    w.frame_wait_us,
                    w.render_us,
                },
            );
        }
        self.reset(now);
    }
};

const FrameSampleSums = struct {
    frame_wait_us: f64 = 0,
    hud_build_us: f64 = 0,
    compose_us: f64 = 0,
    driver: renderer_driver.FrameTimings = .{},
    render_us: f64 = 0,

    fn add(self: *FrameSampleSums, s: FrameSample) void {
        self.frame_wait_us += s.frame_wait_us;
        self.hud_build_us += s.hud_build_us;
        self.compose_us += s.compose_us;
        self.driver.clear_us += s.driver.clear_us;
        self.driver.sync_us += s.driver.sync_us;
        self.driver.emit_us += s.driver.emit_us;
        for (&self.driver.pass_us, s.driver.pass_us) |*acc, v| acc.* += v;
        self.driver.swap_us += s.driver.swap_us;
        self.render_us += s.render_us;
    }
};

/// Print the top-K most expensive instances from a captured profile.
/// Empty profile prints a hint about the unthreaded backend. The
/// printed pixel_w × pixel_h is the post-transform screen bbox, which
/// makes huge fills (background, cards) easy to identify by area
/// without needing to know the picture's instance order.
fn printInstanceProfileTopK(snap: *const snail.InstanceProfileBuf, k: usize) void {
    if (snap.count == 0) {
        std.debug.print(
            "[timing] no per-instance profile captured this window — switch to cpu_unthreaded backend (press C)\n",
            .{},
        );
        return;
    }
    // Partial selection sort: small K, ~hundreds of entries; not worth
    // a real sort.
    var entries = snap.entries[0..snap.count];
    const top = @min(k, entries.len);
    for (0..top) |i| {
        var max_j = i;
        var j = i + 1;
        while (j < entries.len) : (j += 1) {
            if (entries[j].us > entries[max_j].us) max_j = j;
        }
        if (max_j != i) std.mem.swap(snail.InstanceProfileEntry, &entries[i], &entries[max_j]);
    }
    var total_us: f64 = 0;
    for (snap.entries[0..snap.count]) |e| total_us += e.us;
    std.debug.print(
        "[timing] per-instance top {d} of {d} (sum {d:.0} µs):\n",
        .{ top, snap.count, total_us },
    );
    for (entries[0..top], 0..) |e, rank| {
        std.debug.print(
            "[timing]   {d:>2}. {d:>7.0} µs  {d:>5}×{d:<5} px  (batch index {d})\n",
            .{ rank + 1, e.us, e.pixel_w, e.pixel_h, e.index },
        );
    }
}

fn printStutterLine(f: FrameSample, recent_avg_us: f64, moving: bool) void {
    std.debug.print(
        "\n[stutter] moving={s} render={d:.0} µs (avg {d:.0}) | wait={d:.0} hud_build={d:.0} compose={d:.0} clear={d:.0} sync={d:.0} emit={d:.0} pass0={d:.0} pass1={d:.0} swap={d:.0}\n",
        .{
            if (moving) "yes" else "no",
            f.render_us,
            recent_avg_us,
            f.frame_wait_us,
            f.hud_build_us,
            f.compose_us,
            f.driver.clear_us,
            f.driver.sync_us,
            f.driver.emit_us,
            f.driver.pass_us[0],
            f.driver.pass_us[1],
            f.driver.swap_us,
        },
    );
}

// ── HUD frame-time stats ──
//
// Rolling ring buffer of recent inter-frame intervals (in microseconds).
// The HUD renders three things derived from this:
//   * mean FPS over the window (replaces the old once-per-second
//     `fps_display`, which masked spikes by averaging),
//   * a p50/p95/max readout of frame times,
//   * a "vsync cadence" histogram bucketing frames by which 60 Hz vsync
//     interval they fell into (≤1, 2, 3, 4+). The cadence row is the
//     thing you watch for "is it actually displaying smoothly?" — at a
//     clean 60 fps every frame is bucket 1; at a clean 30 fps every
//     frame is bucket 2; juddery 30 fps shows up as a split between 1
//     and 2.
//
// Resolution is intentionally microseconds-since-prev-frame so the
// math works the same for hundred-Hz refresh as for 60 — and so a
// long compositor wait at the top of the loop shows up faithfully as
// a long frame.

const FrameTimeStats = struct {
    const WINDOW: usize = 120; // ~2 s at 60 fps
    const VSYNC_US: u32 = 16_667;

    times_us: [WINDOW]u32 = [_]u32{0} ** WINDOW,
    write_idx: usize = 0,
    count: usize = 0,

    fn record(self: *FrameTimeStats, frame_us: u32) void {
        self.times_us[self.write_idx] = frame_us;
        self.write_idx = (self.write_idx + 1) % WINDOW;
        if (self.count < WINDOW) self.count += 1;
    }

    const Snapshot = struct {
        fps: f32 = 0,
        p50_us: u32 = 0,
        p95_us: u32 = 0,
        max_us: u32 = 0,
        /// Frames bucketed by which 60 Hz vsync interval they spanned.
        /// `cadence[0]` = "made it inside one vsync" (smooth 60),
        /// `cadence[1]` = "took 2 vsyncs" (smooth 30 if every frame),
        /// `cadence[2]` = "took 3" (smooth 20), `cadence[3]` = "≥ 4".
        /// A split distribution = judder.
        cadence: [4]u32 = .{ 0, 0, 0, 0 },
        count: u32 = 0,
    };

    fn snapshot(self: *const FrameTimeStats) Snapshot {
        if (self.count == 0) return .{};
        var sorted: [WINDOW]u32 = undefined;
        @memcpy(sorted[0..self.count], self.times_us[0..self.count]);
        std.sort.pdq(u32, sorted[0..self.count], {}, std.sort.asc(u32));

        var cad = [_]u32{ 0, 0, 0, 0 };
        var sum_us: u64 = 0;
        for (self.times_us[0..self.count]) |t| {
            sum_us += t;
            // Round `t` to the nearest whole vsync count, then bucket.
            // Putting the boundary at the *midpoint* between vsyncs
            // (8.33 ms, 25 ms, 41.67 ms) instead of on each vsync
            // (16.67, 33.33, 50) gives ±half-vsync of slack to absorb
            // the few ms of CPU-scheduling / event-pump / driver-side
            // jitter present in any real loop. Without this slack, a
            // perfectly steady 60 fps stream — where consecutive `dt`
            // samples drift 14.5, 17.1, 15.8, 18.2, ... around the
            // true 16.67 ms interval — bins as "half 1×, half 2×"
            // even though the display itself never drops a frame.
            // That false split is what made the Vulkan backend (which
            // genuinely never misses vsync on this hardware) look
            // identical to a struggling CPU backend in the histogram.
            const vsync_count = (t + VSYNC_US / 2) / VSYNC_US;
            const bucket: usize = if (vsync_count <= 1) 0
                else if (vsync_count == 2) 1
                else if (vsync_count == 3) 2
                else 3;
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

/// Running per-stage sums for the HUD's stage-breakdown lines (the same
/// information the `T` stdout prints carry, but on-screen and live).
/// Always fed from the per-frame `FrameSample`, then read & reset at
/// each HUD-string update tick (`hud_stats_period`). Bucketing into
/// "mean over the last 0.5 s" keeps the numbers stable enough to read
/// while still tracking what's actually happening right now.
const StageStats = struct {
    count: u32 = 0,
    frame_wait_us: f64 = 0,
    hud_build_us: f64 = 0,
    compose_us: f64 = 0,
    clear_us: f64 = 0,
    sync_us: f64 = 0,
    emit_us: f64 = 0,
    pass0_us: f64 = 0,
    pass1_us: f64 = 0,
    swap_us: f64 = 0,
    render_us: f64 = 0,

    fn record(self: *StageStats, frame: FrameSample) void {
        self.count += 1;
        self.frame_wait_us += frame.frame_wait_us;
        self.hud_build_us += frame.hud_build_us;
        self.compose_us += frame.compose_us;
        self.clear_us += frame.driver.clear_us;
        self.sync_us += frame.driver.sync_us;
        self.emit_us += frame.driver.emit_us;
        self.pass0_us += frame.driver.pass_us[0];
        self.pass1_us += frame.driver.pass_us[1];
        self.swap_us += frame.driver.swap_us;
        self.render_us += frame.render_us;
    }

    fn reset(self: *StageStats) void {
        self.* = .{};
    }

    /// Mean of `total_us` over the window, in milliseconds. Zero on an
    /// empty window so callers can format unconditionally.
    fn meanMs(self: *const StageStats, total_us: f64) f32 {
        if (self.count == 0) return 0;
        return @floatCast(total_us / @as(f64, @floatFromInt(self.count)) / 1000.0);
    }
};

/// Wayland `wp_presentation_feedback`-driven callback. Invoked from the
/// libwayland event dispatcher (i.e. inside `pumpEvents` or
/// `waitForFrameCallback`) every time the compositor reports a
/// successful surface presentation. Records the interval since the
/// previous presentation into the supplied `FrameTimeStats` ring.
fn presentStatsCallback(ctx: *anyopaque, interval_us: u32) void {
    const stats: *FrameTimeStats = @ptrCast(@alignCast(ctx));
    stats.record(interval_us);
}

fn transform2DEql(a: ?snail.Transform2D, b: ?snail.Transform2D) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    const x = a.?;
    const y = b.?;
    return x.xx == y.xx and x.xy == y.xy and x.yx == y.yx and x.yy == y.yy and x.tx == y.tx and x.ty == y.ty;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    return mainLoop(allocator);
}

fn mainLoop(allocator: std.mem.Allocator) !void {
    const window = try wayland.Window.init(1280, 720, "snail");
    defer window.deinit();

    var active = try renderer_driver.Driver.init(allocator, window, renderer_driver.defaultKind());
    var active_valid = true;
    defer if (active_valid) active.deinit();

    const sys_order = subpixel_detect.detect();
    const detected_order = window.currentSubpixelOrder(sys_order);
    var current_order: snail.SubpixelOrder = .none;
    std.debug.print(
        "snail: detected subpixel order: system={s} monitor={s} (starting in {s})\n",
        .{ @tagName(sys_order), @tagName(detected_order), @tagName(current_order) },
    );

    var content_cache = try ContentCache.init(allocator);
    defer content_cache.deinit();

    var hud = try hud_mod.Overlay.init(allocator, &content_cache.assets.faces, content_cache.pool, 0);
    defer hud.deinit();
    var hud_arena = std.heap.ArenaAllocator.init(allocator);
    defer hud_arena.deinit();
    var hud_scratch = std.heap.ArenaAllocator.init(allocator);
    defer hud_scratch.deinit();

    // Autohint comparison overlay (V toggles; G / F change ppem).
    var compare = try autohint_compare.Compare.init(allocator, content_cache.pool);
    defer compare.deinit();
    var compare_arena = std.heap.ArenaAllocator.init(allocator);
    defer compare_arena.deinit();
    var compare_scratch = std.heap.ArenaAllocator.init(allocator);
    defer compare_scratch.deinit();
    var compare_on = false;
    // Per-frame arena for re-snapping hinted text runs into a fresh
    // text Picture. retain_capacity means we pay one allocation on the
    // first frame and bump-pointer thereafter.
    var content_arena = std.heap.ArenaAllocator.init(allocator);
    defer content_arena.deinit();

    var timing_enabled = false;
    var timing: FrameTimingAccum = .{};
    var last_frame_end: f64 = 0;
    var hud_enabled = true;

    // Per-instance profile buffer. Wired into the snail CPU renderer's
    // global hook each frame while `timing_enabled` is on. The live buf
    // is reset between frames; whenever we observe a new worst-work
    // frame, we copy its entries into `profile_snap` so the window's
    // flush print has them. Sized for ~all banner instances plus
    // headroom — silently truncates beyond this.
    const profile_cap: usize = 8192;
    const profile_entries = try allocator.alloc(snail.InstanceProfileEntry, profile_cap);
    defer allocator.free(profile_entries);
    var profile_live: snail.InstanceProfileBuf = .{ .entries = profile_entries };
    const snap_entries = try allocator.alloc(snail.InstanceProfileEntry, profile_cap);
    defer allocator.free(snap_entries);
    var profile_snap: snail.InstanceProfileBuf = .{ .entries = snap_entries };
    var profile_snap_render_us: f64 = 0;

    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var last_time = wayland.getTime();
    var frame_count: u32 = 0;
    var last_presentation: ?presentation.Info = null;
    var hint_mode: HintMode = .never;

    // Frame-time ring buffer + cached HUD strings. The ring records
    // every frame's `dt`; the displayed strings are regenerated on a
    // fixed cadence (`hud_stats_period`) so the HUD's shape cache only
    // sees a few unique strings per second instead of one per frame.
    // The previous strings are explicitly evicted from the cache before
    // we overwrite the buffers (the shape cache copies its key bytes,
    // so eviction by content works as long as we evict before we
    // mutate the buffer).
    // Two rings. `present_stats` is fed by the compositor's
    // wp_presentation feedback — it captures the true display interval
    // independent of which backend (CPU / GL / Vulkan) is rendering and
    // independent of where each backend chooses to wait. `loop_stats`
    // is the old top-of-loop dt ring, kept as a fallback (for when
    // wp_presentation isn't advertised) and for surfacing render-loop
    // jitter in the HUD's max/p95 next to the display readout.
    var present_stats: FrameTimeStats = .{};
    var loop_stats: FrameTimeStats = .{};
    var stage_stats: StageStats = .{};
    var hud_stats_timer: f64 = 0.0;
    const hud_stats_period: f64 = 0.5;
    var hud_frame_ms_buf: [64]u8 = undefined;
    var hud_cadence_buf: [96]u8 = undefined;
    var hud_stage_pre_buf: [96]u8 = undefined;
    var hud_stage_pass_buf: [96]u8 = undefined;
    var hud_stage_loop_buf: [96]u8 = undefined;
    var hud_frame_ms_text: []const u8 = "";
    var hud_cadence_text: []const u8 = "";
    var hud_stage_pre_text: []const u8 = "";
    var hud_stage_pass_text: []const u8 = "";
    var hud_stage_loop_text: []const u8 = "";
    var hud_fps: f32 = 0;

    window.setPresentationCallback(presentStatsCallback, &present_stats);
    defer window.setPresentationCallback(null, null);
    const has_presentation_feedback = window.hasPresentationFeedback();

    std.debug.print("snail - GPU text & vector rendering\n", .{});
    std.debug.print("Backend: {s}, HarfBuzz: {s}\n", .{
        active.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    renderer_driver.warnIfDebugCpu(active.kind());
    std.debug.print(
        "Keys: arrows pan, Z/X zoom, R rotate, H TT hinting, B AA mode, C backend, O HUD on/off, T timing prints, L dump repro, Esc quit\n",
        .{},
    );
    std.debug.print("aa={s}\n", .{aaName(current_order)});
    std.debug.print("hinting={s}\n", .{hint_mode.name()});

    while (true) {
        // Stage timestamps are unconditional now — a few extra
        // `clock_gettime` calls per frame are immeasurable against the
        // render budget, and capturing them always means the HUD's
        // per-stage breakdown (toggled with `T`) reflects whatever
        // happened since the last update, with no warm-up after toggle.
        const wait_t0 = wayland.getTime();
        if (active.shouldClose()) break;
        const now = wayland.getTime();
        const frame_wait_us = (now - wait_t0) * 1_000_000.0;
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;
        const dt_us: u32 = @intFromFloat(std.math.clamp(dt * 1_000_000.0, 0.0, 1.0e9));
        loop_stats.record(dt_us);
        // `present_stats` is populated by the wp_presentation feedback
        // callback running off the wayland dispatcher in `pumpEvents` /
        // `waitForFrameCallback` — no per-frame record() here.

        hud_stats_timer += dt;
        if (hud_stats_timer >= hud_stats_period) {
            hud_stats_timer = 0.0;
            // Prefer the compositor's presentation feedback. When it's
            // unavailable (no wp_presentation global), fall back to the
            // top-of-loop dt, which is correct for backends that wait
            // there (CPU + wayland frame_callback) and a render-rate
            // proxy for the others. Either way the HUD's cadence row
            // labels what it's showing so the reader isn't fooled.
            const use_present = has_presentation_feedback and present_stats.count > 0;
            const display_snap = if (use_present)
                present_stats.snapshot()
            else if (loop_stats.count > 0)
                loop_stats.snapshot()
            else
                FrameTimeStats.Snapshot{};
            const loop_snap = loop_stats.snapshot();
            // Evict the previous strings from the shape cache before we
            // overwrite the buffers backing them. The cache copies key
            // bytes on insert, so eviction-by-content works as long as
            // the slice we hand it still reflects what was inserted.
            if (hud_frame_ms_text.len > 0)
                hud.shape_cache.evict(hud_frame_ms_text, .{ .style = .{ .weight = .regular } });
            if (hud_cadence_text.len > 0)
                hud.shape_cache.evict(hud_cadence_text, .{ .style = .{ .weight = .regular } });
            hud_fps = display_snap.fps;
            // Always quote frame ms from the loop ring — it tells the
            // user how fast their render code is running, which is the
            // diagnostic that actually moves with optimization work.
            hud_frame_ms_text = std.fmt.bufPrint(
                &hud_frame_ms_buf,
                "{d:.1} p50  {d:.1} p95  {d:.1} max ms",
                .{
                    @as(f32, @floatFromInt(loop_snap.p50_us)) / 1000.0,
                    @as(f32, @floatFromInt(loop_snap.p95_us)) / 1000.0,
                    @as(f32, @floatFromInt(loop_snap.max_us)) / 1000.0,
                },
            ) catch "";
            // The cadence row, by contrast, ALWAYS reflects what the
            // display actually shows (when wp_presentation is bound).
            // The "(loop)" label flags the fallback case so a CPU
            // backend without wp_presentation still reads honestly.
            const cadence_label: []const u8 = if (use_present) "vsync" else "vsync(loop)";
            hud_cadence_text = std.fmt.bufPrint(
                &hud_cadence_buf,
                "{s} 1x:{d} 2x:{d} 3x:{d} 4+:{d}",
                .{
                    cadence_label,
                    display_snap.cadence[0],
                    display_snap.cadence[1],
                    display_snap.cadence[2],
                    display_snap.cadence[3],
                },
            ) catch "";

            // Per-stage means for the HUD breakdown lines. Three rows:
            //   pre     pre-pass driver stages   (clear / sync / emit)
            //   pass    actual rasterization     (pass0 / pass1 / swap)
            //   loop    main-loop top stages     (wait / hud / compose)
            // Empty when `T` is off so the HUD lines collapse.
            if (hud_stage_pre_text.len > 0)
                hud.shape_cache.evict(hud_stage_pre_text, .{ .style = .{ .weight = .regular } });
            if (hud_stage_pass_text.len > 0)
                hud.shape_cache.evict(hud_stage_pass_text, .{ .style = .{ .weight = .regular } });
            if (hud_stage_loop_text.len > 0)
                hud.shape_cache.evict(hud_stage_loop_text, .{ .style = .{ .weight = .regular } });
            if (timing_enabled and stage_stats.count > 0) {
                const ss = &stage_stats;
                hud_stage_pre_text = std.fmt.bufPrint(
                    &hud_stage_pre_buf,
                    "clear {d:.2}  sync {d:.2}  emit {d:.2} ms",
                    .{ ss.meanMs(ss.clear_us), ss.meanMs(ss.sync_us), ss.meanMs(ss.emit_us) },
                ) catch "";
                hud_stage_pass_text = std.fmt.bufPrint(
                    &hud_stage_pass_buf,
                    "pass0 {d:.2}  pass1 {d:.2}  swap {d:.2} ms",
                    .{ ss.meanMs(ss.pass0_us), ss.meanMs(ss.pass1_us), ss.meanMs(ss.swap_us) },
                ) catch "";
                hud_stage_loop_text = std.fmt.bufPrint(
                    &hud_stage_loop_buf,
                    "wait {d:.2}  hud {d:.2}  compose {d:.2} ms",
                    .{ ss.meanMs(ss.frame_wait_us), ss.meanMs(ss.hud_build_us), ss.meanMs(ss.compose_us) },
                ) catch "";
            } else {
                hud_stage_pre_text = "";
                hud_stage_pass_text = "";
                hud_stage_loop_text = "";
            }
            stage_stats.reset();
        }

        _ = window.consumeMonitorChanged();

        const dump_repro = window.isKeyPressed(KEY_L);
        if (window.isKeyPressed(KEY_R)) rotate = !rotate;
        if (window.isKeyPressed(KEY_H)) {
            hint_mode = hint_mode.next();
            std.debug.print("\nhinting={s}\n", .{hint_mode.name()});
        }
        if (window.isKeyPressed(KEY_ESCAPE)) break;
        if (window.isKeyPressed(KEY_O)) {
            hud_enabled = !hud_enabled;
            std.debug.print("\nhud={s}\n", .{if (hud_enabled) "on" else "off"});
        }
        if (window.isKeyPressed(KEY_V)) {
            compare_on = !compare_on;
            std.debug.print("\nautohint-validation={s} (rows per size: un=unhinted, au=auto_light, tt=truetype)\n", .{if (compare_on) "on" else "off"});
        }
        if (window.isKeyPressed(KEY_T)) {
            timing_enabled = !timing_enabled;
            timing.reset(now);
            last_frame_end = now;
            profile_snap.count = 0;
            profile_snap_render_us = 0;
            // Wire / unwire the per-instance profile hook. When off, the
            // renderer's tight inner loop pays nothing for the hook.
            active.setInstanceProfile(if (timing_enabled) &profile_live else null);
            std.debug.print("\ntiming={s}\n", .{if (timing_enabled) "on" else "off"});
            if (timing_enabled and !renderer_driver.isCpuKind(active.kind())) {
                std.debug.print("[timing] per-instance profile requires a CPU backend\n", .{});
            } else if (timing_enabled and active.kind() != .cpu_unthreaded) {
                std.debug.print("[timing] per-instance profile only fills under cpu_unthreaded (press C to cycle backends)\n", .{});
            }
        }
        if (window.isKeyPressed(KEY_B)) {
            current_order = cycleSubpixelOrder(current_order);
            std.debug.print("\naa={s}\n", .{aaName(current_order)});
        }
        if (window.isKeyPressed(KEY_C)) {
            const next_kind = renderer_driver.nextKind(active.kind());
            if (next_kind != active.kind()) {
                active.deinit();
                active_valid = false;
                active = try renderer_driver.Driver.init(allocator, window, next_kind);
                active_valid = true;
                // The profile hook is per-renderer now; re-wire it on the new driver.
                active.setInstanceProfile(if (timing_enabled) &profile_live else null);
                last_presentation = null;
                last_time = wayland.getTime();
                frame_count = 0;
                // Force a content re-upload by invalidating the cache pool match
                // on the new backend's first frame (we set dirty=true unconditionally
                // when the backend was swapped; see below).
                std.debug.print("\nBackend: {s}\n", .{active.backendName()});
                renderer_driver.warnIfDebugCpu(active.kind());
                continue;
            }
        }
        const zoom_in = window.isKeyDown(KEY_Z);
        const zoom_out = window.isKeyDown(KEY_X);
        const pan_left = window.isKeyDown(KEY_LEFT);
        const pan_right = window.isKeyDown(KEY_RIGHT);
        const pan_up = window.isKeyDown(KEY_UP);
        const pan_down = window.isKeyDown(KEY_DOWN);
        const moving = rotate or zoom_in or zoom_out or pan_left or pan_right or pan_up or pan_down;

        if (rotate) angle += dt * 0.5;
        if (zoom_in) zoom *= 1.0 + dt * 2.0;
        if (zoom_out) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (pan_left) pan_x += pan_step;
        if (pan_right) pan_x -= pan_step;
        if (pan_up) pan_y += pan_step;
        if (pan_down) pan_y -= pan_step;

        const present = active.presentationInfo();
        if (last_presentation == null or !std.meta.eql(last_presentation.?, present)) {
            logPresentationInfo(present);
            last_presentation = present;
        }
        const size = present.logical_size;
        const fb_size = present.framebuffer_size;
        const target_encoding = displayTargetEncoding(present);
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        const viewport_w: f32 = @floatFromInt(fb_size[0]);
        const viewport_h: f32 = @floatFromInt(fb_size[1]);
        if (w < 1.0 or h < 1.0 or viewport_w < 1.0 or viewport_h < 1.0) continue;

        const hint_active = hint_mode.active(moving);
        // Hint at the *framebuffer* ppem the glyph will occupy, not the
        // logical-pixel ppem. On a HiDPI display the framebuffer is wider
        // than the logical size; hinting at logical ppem would render every
        // hint pixel as a buffer_scale-sized block (i.e. half-resolution
        // glyphs on a 2× display). Factor in framebuffer/logical so the
        // hinter targets the real pixel grid the GPU writes to.
        const hint_ppem_scale: f32 = zoom * (viewport_h / h);

        // MVP first — the hinted-text picture builder needs the
        // world→pixel transform to snap each shaped run's baseline onto
        // the screen pixel grid (without quantizing per-glyph kerning).
        const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_transform = snail.Mat4.multiply(
            snail.Mat4.translate(pan_x, pan_y, 0),
            snail.Mat4.multiply(
                snail.Mat4.translate(cx, cy, 0),
                snail.Mat4.multiply(
                    snail.Mat4.scaleUniform(zoom),
                    snail.Mat4.multiply(
                        snail.Mat4.rotateZ(angle),
                        snail.Mat4.translate(-cx, -cy, 0),
                    ),
                ),
            ),
        );
        const mvp = snail.Mat4.multiply(projection, scene_transform);
        const world_to_pixel = snail.mvpToScenePixel(mvp, viewport_w, viewport_h);

        const cached = try content_cache.get(size[0], size[1], hint_active, hint_ppem_scale);

        if (dump_repro) {
            dumpReproFrame(frame_count, active.backendName(), current_order, hint_mode, hint_active, present, pan_x, pan_y, zoom, angle);
        }

        const draw_state = snail.DrawState{
            .mvp = mvp,
            .surface = .{
                .pixel_width = viewport_w,
                .pixel_height = viewport_h,
                .encoding = target_encoding,
            },
            .raster = .{
                .subpixel_order = if (present.will_resample) .none else current_order,
                .coverage_transfer = .{ .exponent = 1.0 },
            },
        };

        // Background color (light cream — the card sits on top).
        const clear_srgb = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };

        // HUD: build a fresh screen-space picture each frame. Atlas
        // grows the first time each glyph is encountered; the
        // recordCount delta tells the driver when to re-upload.
        _ = hud_arena.reset(.retain_capacity);
        _ = hud_scratch.reset(.retain_capacity);
        const hud_before = hud.atlas.recordCount();
        const hud_build_t0 = wayland.getTime();
        var hud_picture = try hud.buildPicture(
            hud_arena.allocator(),
            hud_scratch.allocator(),
            .{
                .fps = hud_fps,
                .backend = active.backendName(),
                .aa = aaName(current_order),
                .hint = if (hint_active) hint_mode.name() else "Hint: off",
                .frame_ms = hud_frame_ms_text,
                .cadence = hud_cadence_text,
                .stage_pre = hud_stage_pre_text,
                .stage_pass = hud_stage_pass_text,
                .stage_loop = hud_stage_loop_text,
            },
            w,
            h,
        );
        defer hud_picture.deinit();
        const hud_build_us = (wayland.getTime() - hud_build_t0) * 1_000_000.0;
        const hud_after = hud.atlas.recordCount();

        // HUD MVP: projection only — no scene_transform, so the
        // overlay doesn't pan/zoom/rotate with the world.
        const hud_draw_state = snail.DrawState{
            .mvp = projection,
            .surface = draw_state.surface,
            .raster = .{
                .subpixel_order = if (present.will_resample) .none else current_order,
                .coverage_transfer = .{ .exponent = 1.0 },
            },
        };
        // Compose the cached unhinted text shapes with per-frame hinted
        // shapes (baseline-snapped against the current world→pixel) into
        // a fresh Picture in `content_arena`. Pan with hinting on no
        // longer rebuilds the whole content; just this picture changes
        // each frame.
        _ = content_arena.reset(.retain_capacity);
        const compose_t0 = wayland.getTime();
        var frame_text_picture = try cached.content.composeTextPicture(
            content_arena.allocator(),
            if (hint_active) world_to_pixel else null,
        );
        const compose_us = (wayland.getTime() - compose_t0) * 1_000_000.0;
        // Autohint comparison overlay (screen-space, projection-only like the
        // HUD). Built only when toggled on; the atlas grows per new (glyph,
        // ppem) so a `dirty` on growth triggers re-upload.
        _ = compare_arena.reset(.retain_capacity);
        _ = compare_scratch.reset(.retain_capacity);
        const compare_before = compare.atlas.recordCount();
        var compare_picture = if (compare_on)
            try compare.buildGrid(compare_arena.allocator(), compare_scratch.allocator())
        else
            try snail_helpers.Picture.from(compare_arena.allocator(), &.{});
        defer compare_picture.deinit();
        const compare_dirty = compare.atlas.recordCount() != compare_before;

        const content_atlases = [_]*const snail.Atlas{ &cached.content.paths_atlas, &cached.content.text_atlas };
        const content_pictures = [_]*const snail_helpers.Picture{ &cached.content.paths_picture, &frame_text_picture };
        const hud_atlases = [_]*const snail.Atlas{&hud.atlas};
        const hud_pictures = [_]*const snail_helpers.Picture{&hud_picture};
        const compare_atlases = [_]*const snail.Atlas{&compare.atlas};
        const compare_pictures = [_]*const snail_helpers.Picture{&compare_picture};

        var passes_buf: [3]renderer_driver.Pass = undefined;
        var pass_count: usize = 0;
        passes_buf[pass_count] = .{
            .atlases = &content_atlases,
            .pictures = &content_pictures,
            .draw_state = draw_state,
            .dirty = cached.dirty,
        };
        pass_count += 1;
        if (hud_enabled) {
            passes_buf[pass_count] = .{
                .atlases = &hud_atlases,
                .pictures = &hud_pictures,
                .draw_state = hud_draw_state,
                .dirty = hud_after != hud_before,
            };
            pass_count += 1;
        }
        if (compare_on) {
            passes_buf[pass_count] = .{
                .atlases = &compare_atlases,
                .pictures = &compare_pictures,
                .draw_state = hud_draw_state,
                .dirty = compare_dirty,
            };
            pass_count += 1;
        }
        const passes: []const renderer_driver.Pass = passes_buf[0..pass_count];
        if (timing_enabled) profile_live.reset();
        const frame_t0 = wayland.getTime();
        _ = try active.renderFrame(allocator, passes, clear_srgb);
        const frame_end = wayland.getTime();
        const render_us = (frame_end - frame_t0) * 1_000_000.0;
        const frame = FrameSample{
            .frame_wait_us = frame_wait_us,
            .hud_build_us = hud_build_us,
            .compose_us = compose_us,
            .driver = active.lastFrameTimings(),
            .render_us = render_us,
            .pass_count = @intCast(passes.len),
        };
        // Always feed `stage_stats` (powers the HUD's per-stage line
        // when `T` is on). `timing.observe` is the stdout-printing
        // accumulator and stays gated on `T` so a non-timing session
        // sees no per-frame stderr noise.
        stage_stats.record(frame);
        if (timing_enabled) {
            // Snapshot the per-instance profile BEFORE observe might reset
            // the window, and only when this frame is the new worst-work
            // candidate. That keeps the snapshot tied to whichever frame
            // the window-summary print is about to call "worst work".
            if (render_us > profile_snap_render_us) {
                const n = profile_live.count;
                @memcpy(profile_snap.entries[0..n], profile_live.entries[0..n]);
                profile_snap.count = n;
                profile_snap_render_us = render_us;
            }
            const flushed = timing.observe(frame, frame_end, moving);
            if (flushed) {
                printInstanceProfileTopK(&profile_snap, 10);
                profile_snap.count = 0;
                profile_snap_render_us = 0;
            }
            last_frame_end = frame_end;
        }

        if (frame_count % 60 == 0 and hud_fps > 0.0) {
            std.debug.print("\rFPS: {d:.0}  Backend: {s}  AA: {s}  Hint: {s}{s}   ", .{
                hud_fps,
                active.backendName(),
                aaName(current_order),
                hint_mode.name(),
                if (hint_active) "" else " (off)",
            });
        }
        frame_count += 1;
    }
}

test {
    _ = @import("snail");
}
