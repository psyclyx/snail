const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const demo_banner_scene = @import("demo_banner_scene.zig");
const screenshot = @import("render/screenshot.zig");
const egl_offscreen = @import("render/egl_offscreen.zig");
const gl = @import("render/gl.zig").gl;

const SCREENSHOT_WIDTH: u32 = 1680;
const SCREENSHOT_HEIGHT: u32 = 760;
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

    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    renderer.setSubpixelOrder(.none);

    const vbuf = try allocator.alloc(f32, 10000 * snail.TEXT_FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const path_buf = try allocator.alloc(f32, 256 * snail.TEXT_FLOATS_PER_GLYPH);
    defer allocator.free(path_buf);

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const layout = demo_banner.buildLayout(w, h, scene_assets.metrics);
    const projection = snail.Mat4.ortho(0, w, 0, h, -1, 1);
    const vector_projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);

    // Tile image for image-paint fill and sprites
    const assets = @import("assets");
    var tile_image = try snail.Image.initRgba8(allocator, 16, 16, assets.checkerboard_rgba);
    defer tile_image.deinit();
    const tile_handle = renderer.uploadImage(&tile_image);

    var path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, .normal, &tile_image);
    defer path_picture.deinit();

    var atlas_views: [7]snail.AtlasHandle = undefined;
    scene_assets.uploadAtlases(&renderer, &path_picture, &atlas_views);

    const clear = demo_banner.clearColor();
    gl.glClearColor(clear[0], clear[1], clear[2], clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    renderer.beginFrame();

    var paths = snail.PathBatch.init(path_buf);
    _ = paths.addPicture(&atlas_views[6], &path_picture);
    if (paths.shapeCount() > 0) {
        renderer.drawPaths(paths.slice(), vector_projection, w, h);
    }

    var batch = snail.TextBatch.init(vbuf);
    demo_banner_scene.populateTextBatch(&batch, h, layout, &scene_assets, &atlas_views);
    if (batch.glyphCount() > 0) {
        renderer.drawText(batch.slice(), projection, w, h);
    }

    // Sprite demo: draw in the "sprites" row, under the scene transform
    const sprite_buf = try allocator.alloc(f32, 16 * snail.SPRITE_FLOATS_PER_SPRITE);
    defer allocator.free(sprite_buf);
    {
        const icon = demo_banner.stageIconRect(layout.stage_rows[5]);
        const sz = icon.h;
        const gap: f32 = 2.0;
        var sprites = snail.SpriteBatch.init(sprite_buf);
        _ = sprites.addSpriteRect(tile_handle, .{ .x = icon.x, .y = icon.y, .w = sz, .h = sz }, .{ 1, 1, 1, 1 }, .{}, .nearest);
        _ = sprites.addSpriteRect(tile_handle, .{ .x = icon.x + sz + gap, .y = icon.y, .w = sz, .h = sz }, .{ 1, 0.6, 0.3, 0.9 }, .{}, .nearest);
        _ = sprites.addSpriteRect(tile_handle, .{ .x = icon.x + (sz + gap) * 2, .y = icon.y, .w = sz, .h = sz }, .{ 0.4, 0.7, 1, 0.85 }, .{}, .nearest);
        if (sprites.spriteCount() > 0) {
            renderer.drawSprites(sprites.slice(), vector_projection, w, h);
        }
    }

    if (screenshot.captureFramebuffer(allocator, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT) catch null) |px| {
        defer allocator.free(px);
        screenshot.writeTga(SCREENSHOT_PATH, px, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
        std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}
