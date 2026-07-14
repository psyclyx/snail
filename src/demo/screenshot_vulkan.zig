//! Vulkan counterpart to `screenshot.zig`. Renders the demo scene through the
//! *embeddable* path — a caller-owned pipeline (`embed_vulkan.Renderer`)
//! over a standalone `VulkanBackendCache`, with no all-in-one `VulkanRenderer`.
//! Vulkan-specific orchestration (offscreen frame begin/end) stays here so the
//! harness module doesn't pull the Vulkan platform import into non-Vulkan builds.

const std = @import("std");
const snail = @import("snail");
const demo_content = @import("content.zig");
const harness = @import("screenshot_harness.zig");
const embed_vulkan = @import("embed_vulkan");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const vulkan_platform = vulkan_demo_platform.offscreen;

const vk = embed_vulkan.vk;

const W: u32 = 400;
const H: u32 = 240;
const OUT_PATH = "zig-out/demo-screenshot-vulkan.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const vk_ctx = try vulkan_platform.initOffscreen(W, H);
    defer vulkan_platform.deinitOffscreen();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();
    const scene = harness.Scene{
        .pool = content.pool,
        .paths_atlas = &content.paths_atlas,
        .text_atlas = &content.text_atlas,
        .paths_picture = &content.paths_picture,
        .text_picture = &content.text_picture,
    };

    // Standalone embeddable setup. This tool demonstrates the §6 queue-
    // decoupled upload: the cache records its atlas upload into a caller-owned
    // command buffer that the caller submits + synchronizes (see
    // `cacheWithDecoupledUpload`); snail never touches the queue.
    var layout: embed_vulkan.VulkanResourceLayout = undefined;
    try layout.init(vk_ctx);
    defer layout.deinit();
    var bindings: [2]snail.Binding = undefined;
    var cache = try embed_vulkan.cacheWithDecoupledUpload(allocator, vk_ctx, scene.pool, &layout, &.{ scene.paths_atlas, scene.text_atlas }, &bindings, .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();

    const words = try allocator.alloc(u32, harness.wordBudget(scene));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);
    const e = try harness.emitScene(words, segs, scene, bindings[0], bindings[1]);

    var caller = try embed_vulkan.Renderer.init(vk_ctx, cache.descriptorSetLayout(), harness.wordBudget(scene) * @sizeOf(u32), 1);
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
    // captureOffscreenRgba8 returns top-down rows; flip for GL bottom-up.
    try harness.flipRowsInPlace(allocator, pixels, W, H);
    try harness.writeOutput(OUT_PATH, pixels, W, H);
}
