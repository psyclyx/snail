const std = @import("std");
const build_options = @import("build_options");
const snail = @import("snail");
const gl = @import("support").gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};

const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;

pub const Framebuffer = struct {
    fbo: gl.GLuint,
    texture: gl.GLuint,
};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

pub fn initFramebuffer(width: u32, height: u32) Framebuffer {
    const gl_width: gl.GLsizei = @intCast(width);
    const gl_height: gl.GLsizei = @intCast(height);
    var fbo: gl.GLuint = 0;
    var tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, gl_width, gl_height, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex, 0);
    gl.glViewport(0, 0, gl_width, gl_height);
    return .{ .fbo = fbo, .texture = tex };
}

pub fn destroyFramebuffer(framebuffer: Framebuffer) void {
    var fbo = framebuffer.fbo;
    var texture = framebuffer.texture;
    gl.glDeleteFramebuffers(1, &fbo);
    gl.glDeleteTextures(1, &texture);
}

pub fn clearGlFrame() void {
    gl.glClearColor(0.02, 0.025, 0.03, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
}

pub fn timeCpuDraw(
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawState,
    pixels: []u8,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        @memset(pixels, 0);
        try renderer.drawPrepared(prepared, scene, options);
    }

    const start = nowNs();
    for (0..frames) |_| {
        @memset(pixels, 0);
        try renderer.drawPrepared(prepared, scene, options);
    }
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeGlDraw(
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawState,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        clearGlFrame();
        try renderer.drawPrepared(prepared, scene, options);
    }
    gl.glFinish();

    const start = nowNs();
    for (0..frames) |_| {
        clearGlFrame();
        try renderer.drawPrepared(prepared, scene, options);
    }
    gl.glFinish();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeVulkanDraw(
    vk_renderer: *snail.VulkanRenderer,
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawState,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    if (comptime !build_options.enable_vulkan) unreachable;

    for (0..warmup_frames) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentOffscreenFrameIndex() });
        try renderer.drawPrepared(prepared, scene, options);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();

    const start = nowNs();
    for (0..frames) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentOffscreenFrameIndex() });
        try renderer.drawPrepared(prepared, scene, options);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}
