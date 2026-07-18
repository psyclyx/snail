//! Render the full banner.zig content through the Vulkan offscreen path.
//! Useful for confirming Vulkan parity with the CPU banner.

const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("../../scene/banner/root.zig");
const harness = @import("../../screenshot/harness.zig");
const embed_vulkan = @import("embed_vulkan");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const vulkan_platform = vulkan_demo_platform.offscreen;

const vk = embed_vulkan.vk;

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

    // Embeddable path: standalone resource layout + transfer pool + cache +
    // caller renderer (no all-in-one VulkanRenderer).
    var layout: embed_vulkan.VulkanResourceLayout = undefined;
    try layout.init(vk_ctx);
    defer layout.deinit();
    const transfer_pool = try embed_vulkan.createTransferPool(vk_ctx);
    defer vk.vkDestroyCommandPool(vk_ctx.device, transfer_pool, null);

    var cache = try embed_vulkan.VulkanBackendCache.init(allocator, scene.pool, embed_vulkan.cachePipelineShape(vk_ctx, &layout, transfer_pool), .{
        .max_bindings = 4,
        .layer_info_height = 256,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const words = try allocator.alloc(u32, harness.wordBudget(scene));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.render.records.DrawSegment, 4);
    defer allocator.free(segs);
    const e = try harness.emitScene(words, segs, scene, bindings[0], bindings[1]);

    var caller = try embed_vulkan.Renderer.init(vk_ctx, cache.descriptorSetLayout(), harness.wordBudget(scene) * @sizeOf(u32), 1, false);
    defer caller.deinit();

    const cmd: vk.VkCommandBuffer = @ptrCast(vulkan_platform.beginFrameOffscreenWithClear(.{
        harness.srgbToLinear(harness.bg_srgb_f32[0]),
        harness.srgbToLinear(harness.bg_srgb_f32[1]),
        harness.srgbToLinear(harness.bg_srgb_f32[2]),
        harness.bg_srgb_f32[3],
    }));
    caller.beginFrame(0);
    caller.render(cmd, cache.descriptorSet(), harness.drawState(W, H), words[0..e.words_len], segs[0..e.segs_len]);

    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();

    const pixels = try vulkan_platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels);
    try harness.flipRowsInPlace(allocator, pixels, W, H);
    try harness.writeOutput(OUT_PATH, pixels, W, H);
}
