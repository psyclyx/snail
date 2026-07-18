//! Headless (offscreen, no window) screenshot of the game scene through Vulkan.
//! Mirrors `game_screenshot.zig` (GL) but drives the Vulkan `VkSceneRenderer`
//! into an offscreen render target with a depth attachment. Writes
//! `zig-out/game-vulkan.tga`. Never opens a window.

const std = @import("std");
const snail = @import("snail");
const support = @import("support");
const harness = @import("screenshot/harness.zig");
const embed_vulkan = @import("embed_vulkan");
const vulkan_platform = @import("demo_platform_vulkan").offscreen;
const passes = @import("game/passes.zig");
const scene_mod = @import("game/scene.zig");
const vk_scene = @import("game/vk_scene.zig");

const vk = embed_vulkan.vk;
const W: u32 = 1280;
const H: u32 = 800;
const OUT_PATH = "zig-out/game-vulkan.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const ctx = try vulkan_platform.initOffscreenOpts(W, H, true);
    defer vulkan_platform.deinitOffscreen();

    var fonts = try passes.initFonts(allocator);
    defer fonts.deinit();
    var scene = try scene_mod.Scene.init(allocator, &fonts, W, H);
    defer scene.deinit();
    try scene.rebuildHud(W, "Vulkan", "offscreen capture");

    var sr = try vk_scene.VkSceneRenderer.init(allocator, ctx, &scene, 1);
    defer sr.deinit();

    const cmd: vk.VkCommandBuffer = @ptrCast(vulkan_platform.beginFrameOffscreenWithClear(.{
        harness.srgbToLinear(0.035), harness.srgbToLinear(0.045), harness.srgbToLinear(0.065), 1.0,
    }));
    const view_proj = snail.Mat4.multiply(scene_mod.vulkan_z_fix, scene.viewProj(@as(f32, @floatFromInt(W)) / @as(f32, @floatFromInt(H))));
    const surface = @import("snail-raster").TargetSurface{ .pixel_width = @floatFromInt(W), .pixel_height = @floatFromInt(H), .encoding = @import("snail-raster").TargetEncoding.srgb };
    try sr.record(cmd, 0, &scene, view_proj, surface);
    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();

    const pixels = try vulkan_platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels);
    try harness.flipRowsInPlace(allocator, pixels, W, H);
    try harness.writeOutput(OUT_PATH, pixels, W, H);
}
