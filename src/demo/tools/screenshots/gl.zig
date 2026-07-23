//! GL counterpart to `screenshot.zig`. The per-backend flow lives in
//! `screenshot/harness.zig`; this file owns the EGL/FBO setup.

const std = @import("std");
const demo_content = @import("../../scene/content.zig");
const harness = @import("../../screenshot/harness.zig");
const egl_offscreen = @import("../../platform/offscreen_gl.zig");

const W: u32 = 400;
const H: u32 = 240;
const OUT_PATH = "zig-out/demo-screenshot-gl.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(W, H, .gl33);
    defer gl_ctx.deinit();

    var target = try harness.OffscreenGlTarget.init(W, H);
    defer target.deinit();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();

    try harness.renderGl(.gl33, allocator, .{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &content.text_picture,
    }, W, H, OUT_PATH, .{});
}
