//! Headless CPU+GL render of the hinting-validation grid, for verifying
//! hinting quality without the interactive Wayland loop. Writes
//! zig-out/autohint-screenshot{,-gl}.tga. Each ppem shows three rows:
//! unhinted (un), auto_light (au), then the font's TrueType hinting (tt).

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const compare_mod = @import("autohint_compare.zig");
const harness = @import("screenshot_harness.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 640;
const H: u32 = 720;
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

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    var text_picture = try compare.buildGrid(arena.allocator(), scratch.allocator());
    defer text_picture.deinit();

    var empty_atlas = snail.Atlas.empty(allocator);
    defer empty_atlas.deinit();
    var empty_picture = try helpers.Picture.from(allocator, &.{});
    defer empty_picture.deinit();

    const scene = harness.Scene{
        .pool = pool,
        .paths_atlas = &empty_atlas,
        .text_atlas = &compare.atlas,
        .paths_picture = &empty_picture,
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
