//! CPU-vs-GL pixel parity gate (rebuilt on the new API — the pre-rewrite
//! `backend_compare` was dropped in the reorg cleanup).
//!
//! Renders the shared `content` scene — which exercises every paint kind
//! (solid, linear, radial, conic, image), the fill+inside-stroke composite,
//! the vector snail, and text — through both the CPU rasterizer and the GL
//! backend, then diffs the two RGBA8 buffers. The two agree everywhere except
//! at antialiased edges (small deltas on a few percent of pixels). A real
//! CPU/GLSL divergence — e.g. a paint evaluator that drifted between the
//! hand-synced Zig and GLSL implementations — colors a whole region and blows
//! past the tolerances below, failing the build.

const std = @import("std");
const demo_content = @import("content.zig");
const harness = @import("screenshot_harness.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 400;
const H: u32 = 240;

// Explicit, documented tolerances (not hidden heuristics). CPU and GL differ
// only at AA edges, by small amounts on a minority of pixels; a paint/eval
// divergence fills a region with a large, consistent delta.
const outlier_channel_delta: u8 = 32; // a channel off by >32/255 is an "outlier"
const max_outlier_fraction: f64 = 0.02; // AA edges are fine; fail past 2% of pixels
// AA-edge disagreement tops out ~29/255 on this scene; a real paint/eval
// divergence spikes a region far past that. 80 clears AA with ~2.7× headroom
// and caught a 0.3-rad conic rotation (max_delta 160) in testing.
const max_abs_channel_delta: u8 = 80;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    // The GL context must be current before `renderGlToPixels`.
    var gl_ctx = try egl_offscreen.Context.init(W, H, .gl33);
    defer gl_ctx.deinit();
    var target = try harness.OffscreenGlTarget.init(W, H);
    defer target.deinit();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();
    const scene = harness.Scene{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &content.text_picture,
    };

    const cpu_px = try harness.renderCpuToPixels(allocator, scene, W, H, .{});
    defer allocator.free(cpu_px);
    const gl_px = try harness.renderGlToPixels(.gl33, allocator, scene, W, H, .{});
    defer allocator.free(gl_px);

    if (cpu_px.len != gl_px.len) return error.SizeMismatch;

    const pixel_count = cpu_px.len / 4;
    var mismatched: usize = 0;
    var outliers: usize = 0;
    var max_delta: u8 = 0;
    var total_delta: u64 = 0;

    var p: usize = 0;
    while (p < pixel_count) : (p += 1) {
        const base = p * 4;
        var pixel_delta: u8 = 0;
        inline for (0..4) |c| {
            const a = cpu_px[base + c];
            const b = gl_px[base + c];
            const d = if (a > b) a - b else b - a;
            total_delta += d;
            if (d > pixel_delta) pixel_delta = d;
        }
        if (pixel_delta > 0) mismatched += 1;
        if (pixel_delta > outlier_channel_delta) outliers += 1;
        if (pixel_delta > max_delta) max_delta = pixel_delta;
    }

    const pc: f64 = @floatFromInt(pixel_count);
    const outlier_frac = @as(f64, @floatFromInt(outliers)) / pc;
    const mean_delta = @as(f64, @floatFromInt(total_delta)) / @as(f64, @floatFromInt(cpu_px.len));

    std.debug.print(
        "backend-compare CPU vs GL {d}x{d}: mismatched={d}/{d} ({d:.2}%)  outliers(>{d})={d} ({d:.3}%)  max_delta={d}  mean_delta={d:.4}\n",
        .{ W, H, mismatched, pixel_count, 100.0 * @as(f64, @floatFromInt(mismatched)) / pc, outlier_channel_delta, outliers, 100.0 * outlier_frac, max_delta, mean_delta },
    );

    var failed = false;
    if (outlier_frac > max_outlier_fraction) {
        std.debug.print("FAIL: outlier fraction {d:.3}% exceeds ceiling {d:.3}%\n", .{ 100.0 * outlier_frac, 100.0 * max_outlier_fraction });
        failed = true;
    }
    if (max_delta > max_abs_channel_delta) {
        std.debug.print("FAIL: max channel delta {d} exceeds ceiling {d}\n", .{ max_delta, max_abs_channel_delta });
        failed = true;
    }
    if (failed) return error.BackendMismatch;
    std.debug.print("backend-compare: PASS\n", .{});
}
