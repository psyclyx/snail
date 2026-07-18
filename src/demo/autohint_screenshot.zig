//! Headless CPU+GL render of the hinting-validation grid, for verifying
//! hinting quality without the interactive Wayland loop. Writes
//! zig-out/autohint-screenshot{,-gl}.tga. Each ppem shows four rows in
//! V-overlay order: unhinted (un), y-only (y), strong xy (xy), TrueType (tt).

const std = @import("std");
const snail = @import("snail");
const compare_mod = @import("autohint_compare.zig");
const harness = @import("screenshot_harness.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 896; // two grid columns of gridWidthPx (448) each
const H: u32 = compare_mod.default_viewport_height;
const OUT_PATH = "zig-out/autohint-screenshot.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var compare = try compare_mod.Compare.init(allocator, pool);
    defer compare.deinit();
    var compare_noto = try compare_mod.Compare.initFont(allocator, pool, @import("assets").noto_sans_mono, "Noto");
    defer compare_noto.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    // Headless render is 1:1 logical→device, so device px scale is 1. Two fonts
    // side by side; the harness draws a "paths" and a "text" atlas/picture pair,
    // so DejaVu rides the text slot and Noto the paths slot.
    var text_picture = try compare.buildGridAt(arena.allocator(), scratch.allocator(), 1.0, 0);
    defer text_picture.deinit();
    var noto_picture = try compare_noto.buildGridAt(arena.allocator(), scratch.allocator(), 1.0, compare_mod.Compare.gridWidthPx(1.0));
    defer noto_picture.deinit();

    const scene = harness.Scene{
        .pool = pool,
        .paths_atlas = &compare_noto.atlas,
        .text_atlas = &compare.atlas,
        .paths_picture = &noto_picture,
        .text_picture = &text_picture,
    };
    try harness.renderCpu(allocator, scene, W, H, OUT_PATH, .{});
    std.debug.print("autohint-screenshot: wrote {s} ({d}x{d})\n", .{ OUT_PATH, W, H });

    // Also render through GL to verify the shader-side warp matches the CPU.
    var gl_ctx = egl_offscreen.Context.init(W, H, .gl33) catch |e| {
        std.debug.print("autohint-screenshot: GL render skipped ({s})\n", .{@errorName(e)});
        return;
    };
    defer gl_ctx.deinit();
    var target = try harness.OffscreenGlTarget.init(W, H);
    defer target.deinit();
    try harness.renderGl(.gl33, allocator, scene, W, H, "zig-out/autohint-screenshot-gl.tga", .{ .layer_info_height = 256 });
    std.debug.print("autohint-screenshot: wrote zig-out/autohint-screenshot-gl.tga (GL33)\n", .{});
}
