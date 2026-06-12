//! Render the full banner.zig content through the Vulkan offscreen path.
//! Useful for confirming Vulkan parity with the CPU banner.

const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("banner.zig");
const harness = @import("screenshot_harness.zig");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const vulkan_platform = vulkan_demo_platform.offscreen;

const W: u32 = 1280;
const H: u32 = 720;
const OUT_PATH = "zig-out/banner-screenshot-vulkan.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const vk_ctx = try vulkan_platform.initOffscreen(W, H);
    defer vulkan_platform.deinitOffscreen();

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

    const scene = harness.Scene{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &text_picture,
    };

    var vk_renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer vk_renderer.deinit();

    var cache = try snail.VulkanBackendCache.init(allocator, scene.pool, vk_renderer.state.pipelineShape(), .{
        .max_bindings = 4,
        .layer_info_height = 256,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const words = try allocator.alloc(u32, harness.wordBudget(scene));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);
    const e = try harness.emitScene(words, segs, scene, bindings[0], bindings[1]);

    const cmd = vulkan_platform.beginFrameOffscreenWithClear(.{
        harness.srgbToLinear(harness.bg_srgb_f32[0]),
        harness.srgbToLinear(harness.bg_srgb_f32[1]),
        harness.srgbToLinear(harness.bg_srgb_f32[2]),
        harness.bg_srgb_f32[3],
    });
    vk_renderer.state.setCommandBuffer(cmd);
    defer vk_renderer.state.clearCommandBuffer();
    vk_renderer.state.setFrameSlot(vulkan_platform.currentOffscreenFrameIndex());

    try vk_renderer.state.draw(
        allocator,
        harness.drawState(W, H),
        .{ .words = words[0..e.words_len], .segments = segs[0..e.segs_len] },
        &.{&cache},
    );

    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();

    const pixels = try vulkan_platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels);
    try harness.flipRowsInPlace(allocator, pixels, W, H);
    try harness.writeOutput(OUT_PATH, pixels, W, H);
}
