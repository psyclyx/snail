//! GL banner screenshot for cross-backend comparison.

const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("banner.zig");
const harness = @import("screenshot_harness.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 1280;
const H: u32 = 720;
const OUT_PATH = "zig-out/banner-screenshot-gl.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(W, H, .gl33);
    defer gl_ctx.deinit();

    var target = try harness.OffscreenGlTarget.init(W, H);
    defer target.deinit();

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 24,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var assets = try demo_banner.Assets.init(allocator);
    defer assets.deinit();

    var content = try demo_banner.build(
        allocator,
        pool,
        &assets,
        @floatFromInt(W),
        @floatFromInt(H),
        .{ .x = 1, .y = 1 },
        .{},
    );
    defer content.deinit();

    var text_picture = try content.composeTextPicture(allocator, null);
    defer text_picture.deinit();

    try harness.renderGl(.gl33, allocator, .{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &text_picture,
    }, W, H, OUT_PATH, .{ .layer_info_height = 256 });
}
