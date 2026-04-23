const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const assets = @import("assets");
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

    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();
    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    var arabic = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_arabic, demo_banner.arabic_text);
    defer arabic.deinit();
    var devanagari = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_devanagari, demo_banner.devanagari_text);
    defer devanagari.deinit();
    var mongolian = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_mongolian, demo_banner.mongolian_text);
    defer mongolian.deinit();
    var thai = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_thai, demo_banner.thai_text);
    defer thai.deinit();
    var emoji = try demo_banner.ScriptFont.init(allocator, assets.twemoji_mozilla, demo_banner.emoji_text);
    defer emoji.deinit();

    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    renderer.setSubpixelOrder(.none);

    const metrics = demo_banner.measureMetrics(&atlas, &font);
    const vbuf = try allocator.alloc(f32, 10000 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const path_buf = try allocator.alloc(f32, 256 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(path_buf);

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const layout = demo_banner.buildLayout(w, h, metrics);
    const projection = snail.Mat4.ortho(0, w, 0, h, -1, 1);
    const vector_projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);

    var picture_builder = snail.PathPictureBuilder.init(allocator);
    defer picture_builder.deinit();
    try demo_banner.buildPathShowcase(&picture_builder, layout);
    var path_picture = try picture_builder.freeze(allocator);
    defer path_picture.deinit();

    var atlas_views: [7]snail.AtlasView = undefined;
    renderer.uploadAtlases(&[_]*const snail.Atlas{
        &atlas,
        &arabic.atlas,
        &devanagari.atlas,
        &mongolian.atlas,
        &thai.atlas,
        &emoji.atlas,
        &path_picture.atlas,
    }, &atlas_views);

    const clear = demo_banner.clearColor();
    gl.glClearColor(clear[0], clear[1], clear[2], clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    renderer.beginFrame();

    var paths = snail.PathBatch.init(path_buf);
    _ = paths.addPicture(&atlas_views[6], &path_picture);
    if (paths.shapeCount() > 0) {
        renderer.drawPaths(paths.slice(), vector_projection, w, h);
    }

    var batch = snail.Batch.init(vbuf);
    demo_banner.drawText(&batch, h, layout, .{
        .latin_font = &font,
        .latin_view = &atlas_views[0],
        .arabic_font = &arabic,
        .arabic_view = &atlas_views[1],
        .devanagari_font = &devanagari,
        .devanagari_view = &atlas_views[2],
        .mongolian_font = &mongolian,
        .mongolian_view = &atlas_views[3],
        .thai_font = &thai,
        .thai_view = &atlas_views[4],
        .emoji_font = &emoji,
        .emoji_view = &atlas_views[5],
    });
    if (batch.glyphCount() > 0) {
        renderer.draw(batch.slice(), projection, w, h);
    }

    if (screenshot.captureFramebuffer(allocator, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT) catch null) |px| {
        defer allocator.free(px);
        screenshot.writeTga(SCREENSHOT_PATH, px, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
        std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}
