//! Vulkan counterpart to `screenshot_new.zig`. Renders the shared
//! content (see `new_content.zig`) through the new-API Vulkan upload +
//! draw path and writes `zig-out/demo-screenshot-new-vulkan.tga`.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const new_content = @import("new_content.zig");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const vulkan_platform = vulkan_demo_platform.offscreen;

const W: u32 = 400;
const H: u32 = 240;
const OUT_PATH = "zig-out/demo-screenshot-new-vulkan.tga";

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const vk_ctx = try vulkan_platform.initOffscreen(W, H);
    defer vulkan_platform.deinitOffscreen();

    var content = try new_content.build(allocator, W, H);
    defer content.deinit();

    var vk_renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer vk_renderer.deinit();

    var cache = try snail.VulkanPreparedPages.init(allocator, content.pool, vk_renderer.state.newApiPipelineShape(), .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas_new }, &bindings);
    const paths_binding = bindings[0];
    const text_binding = bindings[1];

    const words = try allocator.alloc(u32, snail.emit.wordBudget(&content.paths_picture, 0) + snail.emit.wordBudget(&content.text_pic, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &content.paths_atlas, &content.paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &content.text_atlas_new, &content.text_pic, .identity, .{ 1, 1, 1, 1 });

    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const draw_state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };

    const bg = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };
    const cmd = vulkan_platform.beginFrameOffscreenWithClear(.{
        srgbToLinear(bg[0]),
        srgbToLinear(bg[1]),
        srgbToLinear(bg[2]),
        bg[3],
    });
    vk_renderer.state.setCommandBuffer(cmd);
    defer vk_renderer.state.clearCommandBuffer();
    vk_renderer.state.setFrameSlot(vulkan_platform.currentOffscreenFrameIndex());

    try vk_renderer.state.drawNewApi(
        allocator,
        draw_state,
        .{ .words = words[0..wlen], .segments = segs[0..slen] },
        &.{&cache},
    );

    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();

    const pixels = try vulkan_platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels);

    // captureOffscreenRgba8 returns top-down rows; writeTga also flips
    // for GL bottom-up output. Pre-flip so the on-disk image is right
    // side up.
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
