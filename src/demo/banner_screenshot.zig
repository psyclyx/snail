//! Render the full banner.zig content (the 1280×720 interactive scene)
//! to a static TGA via the CPU backend. Useful for debugging the scene
//! offscreen without driving a Wayland window.

const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("banner.zig");
const harness = @import("screenshot_harness.zig");

const W: u32 = 1280;
const H: u32 = 720;
const OUT_PATH = "zig-out/banner-screenshot.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 24,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var assets = try demo_banner.Assets.init(allocator);
    defer assets.deinit();

    const hint = std.c.getenv("SNAIL_HINT") != null;
    const ppem_scale: f32 = if (std.c.getenv("SNAIL_PPEM_SCALE")) |s| blk: {
        const span = std.mem.span(s);
        break :blk std.fmt.parseFloat(f32, span) catch 1.0;
    } else 1.0;
    var content = try demo_banner.build(
        allocator,
        pool,
        &assets,
        @floatFromInt(W),
        @floatFromInt(H),
        .{ .x = 1, .y = 1 },
        .{ .enabled = hint, .ppem_scale = ppem_scale },
    );
    defer content.deinit();
    if (hint) std.debug.print("[banner] hinting enabled, ppem_scale={d:.2}\n", .{ppem_scale});

    try harness.renderCpu(allocator, .{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &content.text_picture,
    }, W, H, OUT_PATH, .{ .layer_info_height = 256 });
}
