//! Headless (offscreen, no window) screenshot of the game scene, per GL
//! backend. Uses an EGL pbuffer context + an FBO with a depth attachment so the
//! full scene — custom-material coverage quad, depth-tested occluded label,
//! translucent panel, HUD — renders exactly as in the windowed demo, then reads
//! it back to `zig-out/game-<backend>.tga`. This is the game's verification
//! harness; it never opens a window.

const std = @import("std");
const snail = @import("snail");
const support = @import("support");
const build_options = @import("build_options");
const offscreen_gl = @import("../../platform/offscreen_gl.zig");
const passes = @import("../../game/passes.zig");
const scene_mod = @import("../../game/scene.zig");
const gl_scene = @import("../../game/gl_scene.zig");
const gl_material = @import("../../game/gl_material.zig");
const desktop_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});
const gles_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES2/gl2ext.h");
});

const W: u32 = 1280;
const H: u32 = 800;

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    _ = std.c.mkdir("zig-out", 0o755);

    if (build_options.enable_gl44) try renderOne(.gl44, allocator, "OpenGL 4.4", "zig-out/game-gl44.tga");
    if (build_options.enable_gl33) try renderOne(.gl33, allocator, "OpenGL 3.3", "zig-out/game-gl33.tga");
    if (build_options.enable_gles30) try renderOne(.gles30, allocator, "OpenGL ES 3.0", "zig-out/game-gles30.tga");
}

fn renderOne(comptime variant: gl_material.Variant, allocator: std.mem.Allocator, name: []const u8, out_path: [*:0]const u8) !void {
    const api: offscreen_gl.GlApi = switch (variant) {
        .gl44 => .gl44,
        .gl33 => .gl33,
        .gles30 => .gles30,
    };
    const gl = switch (variant) {
        .gles30 => gles_gl,
        else => desktop_gl,
    };

    var ctx = try offscreen_gl.Context.init(W, H, api);
    defer ctx.deinit();

    // Offscreen target: sRGB color texture + depth renderbuffer.
    const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;
    const GL_DEPTH_COMPONENT24: gl.GLenum = 0x81A6;
    var fbo: gl.GLuint = 0;
    var color_tex: gl.GLuint = 0;
    var depth_rb: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &color_tex);
    gl.glGenRenderbuffers(1, &depth_rb);
    gl.glBindTexture(gl.GL_TEXTURE_2D, color_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, @intCast(W), @intCast(H), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, color_tex, 0);
    gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, depth_rb);
    gl.glRenderbufferStorage(gl.GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, @intCast(W), @intCast(H));
    gl.glFramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_RENDERBUFFER, depth_rb);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    defer {
        gl.glDeleteFramebuffers(1, &fbo);
        gl.glDeleteTextures(1, &color_tex);
        gl.glDeleteRenderbuffers(1, &depth_rb);
    }

    // Desktop GL needs FRAMEBUFFER_SRGB to encode linear shader output into the
    // sRGB attachment; GLES 3.0 encodes to sRGB attachments unconditionally.
    switch (variant) {
        .gl44, .gl33 => gl.glEnable(0x8DB9), // GL_FRAMEBUFFER_SRGB
        .gles30 => {},
    }

    var fonts = try passes.initFonts(allocator);
    defer fonts.deinit();
    var scene = try scene_mod.Scene.init(allocator, &fonts, W, H);
    defer scene.deinit();
    try scene.rebuildHud(W, name, "offscreen capture");

    var sr = try gl_scene.GlSceneRenderer(variant).init(allocator, &scene);
    defer sr.deinit();

    gl.glViewport(0, 0, @intCast(W), @intCast(H));
    gl.glDepthMask(gl.GL_TRUE);
    // Clear in linear (the sRGB target encodes on store) so the bg matches Vulkan.
    gl.glClearColor(srgbToLinear(0.035), srgbToLinear(0.045), srgbToLinear(0.065), 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    const view_proj = scene.viewProj(@as(f32, @floatFromInt(W)) / @as(f32, @floatFromInt(H)));
    const surface = @import("snail-raster").TargetSurface{ .pixel_width = @floatFromInt(W), .pixel_height = @floatFromInt(H), .encoding = @import("snail-raster").TargetEncoding.srgb };
    try sr.draw(&scene, W, H, view_proj, surface);

    const px = try support.screenshot.captureFramebuffer(allocator, W, H);
    defer allocator.free(px);
    try support.screenshot.writeTga(out_path, px, W, H);
    std.debug.print("wrote {s} ({s})\n", .{ out_path, name });
}
