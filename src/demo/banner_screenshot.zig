//! Render the full banner.zig content (the 1280×720 interactive scene)
//! to a static TGA via the CPU backend. Useful for debugging the scene
//! offscreen without driving a Wayland window.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const demo_banner = @import("banner.zig");

const W: u32 = 1280;
const H: u32 = 720;
const STRIDE: u32 = W * 4;
const OUT_PATH = "zig-out/banner-screenshot.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const pixels = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels);
    const bg = [4]u8{ 245, 246, 249, 255 };
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        pixels[i + 0] = bg[0];
        pixels[i + 1] = bg[1];
        pixels[i + 2] = bg[2];
        pixels[i + 3] = bg[3];
    }

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

    var cache = try snail.CpuPreparedPages.init(allocator, content.pool, .{
        .max_bindings = 4,
        .layer_info_height = 256,
        .max_images = 8,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
    const paths_binding = bindings[0];
    const text_binding = bindings[1];

    const words = try allocator.alloc(u32, snail.emit.wordBudget(&content.paths_picture, 0) + snail.emit.wordBudget(&content.text_picture, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &content.paths_atlas, &content.paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &content.text_atlas, &content.text_picture, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(pixels.ptr, W, H, STRIDE);
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    try snail.drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    flipRowsInPlace(pixels);

    _ = std.c.mkdir("zig-out", 0o755);
    try screenshot.writeTga(OUT_PATH, pixels, W, H);
    std.debug.print("wrote {s}\n", .{OUT_PATH});
}

fn flipRowsInPlace(pixels: []u8) void {
    var tmp: [W * 4]u8 = undefined;
    var y: usize = 0;
    while (y < H / 2) : (y += 1) {
        const top = y * W * 4;
        const bottom = (@as(usize, H) - 1 - y) * W * 4;
        @memcpy(&tmp, pixels[top..][0 .. W * 4]);
        @memcpy(pixels[top..][0 .. W * 4], pixels[bottom..][0 .. W * 4]);
        @memcpy(pixels[bottom..][0 .. W * 4], &tmp);
    }
}
