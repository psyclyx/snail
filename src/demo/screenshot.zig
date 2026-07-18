//! New-API screenshot demo — CPU backend.
//!
//! Builds the shared content (see `content.zig`) and renders it
//! through `raster.draw` into `zig-out/demo-screenshot.tga`. The
//! per-backend flow lives in `screenshot/harness.zig`.

const std = @import("std");
const demo_content = @import("scene/content.zig");
const harness = @import("screenshot/harness.zig");

const W: u32 = 400;
const H: u32 = 240;
const OUT_PATH = "zig-out/demo-screenshot.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();

    try harness.renderCpu(allocator, .{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &content.text_picture,
    }, W, H, OUT_PATH, .{});
}
