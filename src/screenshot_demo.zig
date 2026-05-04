const std = @import("std");
const snail = @import("snail.zig");
const banner_scene = @import("banner_scene.zig");
const screenshot = @import("render/screenshot.zig");
const egl_offscreen = @import("render/egl_offscreen.zig");
const gl = @import("render/gl.zig").gl;

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

const SCREENSHOT_WIDTH: u32 = banner_scene.WIDTH;
const SCREENSHOT_HEIGHT: u32 = banner_scene.HEIGHT;
const SCREENSHOT_PATH = "zig-out/demo-screenshot.tga";
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
    defer gl_ctx.deinit();

    var fbo: gl.GLuint = 0;
    var fbo_tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &fbo_tex);
    defer gl.glDeleteFramebuffers(1, &fbo);
    defer gl.glDeleteTextures(1, &fbo_tex);

    gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    gl.glViewport(0, 0, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);

    var scene_assets = try banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var gl_renderer = try snail.GlRenderer.init(allocator);
    defer gl_renderer.deinit();
    var renderer = gl_renderer.asRenderer();

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);

    var builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
    defer builder.deinit();
    try banner_scene.buildTextBlob(&builder);
    var text_blob = try builder.finish();
    defer text_blob.deinit();

    var path_picture = try banner_scene.buildPathPicture(allocator);
    defer path_picture.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &path_picture });
    try scene.addText(.{ .blob = &text_blob, .resolve = .{ .hinting = .metrics } });

    var resource_entries: [8]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(allocator, &resources);
    defer prepared.deinit();

    const clear = banner_scene.clearColor();
    gl.glClearColor(srgbToLinear(clear[0]), srgbToLinear(clear[1]), srgbToLinear(clear[2]), clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    const draw_options = snail.DrawOptions{
        .mvp = projection,
        .target = .{
            .pixel_width = w,
            .pixel_height = h,
            .subpixel_order = .none,
        },
    };
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene, draw_options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, draw_options);

    if (screenshot.captureFramebuffer(allocator, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT) catch null) |px| {
        defer allocator.free(px);
        screenshot.writeTga(SCREENSHOT_PATH, px, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
        std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}
