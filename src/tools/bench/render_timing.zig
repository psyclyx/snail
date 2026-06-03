//! Backend draw-timing wrappers used by the bench harness.
//!
//! Replaces the legacy `Renderer.drawPrepared` calls with the new
//! prepared-pages + DrawRecords API. Each function takes a typed backend
//! state and the relevant `*BackendCache` cache, then loops `frames`
//! times measuring wall-clock around a `state.draw(...)` invocation.

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

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const snail.DrawSegment,
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
    renderer: *snail.CpuRenderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.CpuBackendCache,
    pixels: []u8,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        @memset(pixels, 0);
        try snail.drawCpu(renderer, state, .{ .words = records.words, .segments = records.segments }, caches);
    }

    const start = nowNs();
    for (0..frames) |_| {
        @memset(pixels, 0);
        try snail.drawCpu(renderer, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeGl33Draw(
    allocator: std.mem.Allocator,
    renderer: *snail.Gl33Renderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.Gl33BackendCache,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();

    const start = nowNs();
    for (0..frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeGl44Draw(
    allocator: std.mem.Allocator,
    renderer: *snail.Gl44Renderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.Gl44BackendCache,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();

    const start = nowNs();
    for (0..frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeGles30Draw(
    allocator: std.mem.Allocator,
    renderer: *snail.Gles30Renderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.Gles30BackendCache,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    for (0..warmup_frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();

    const start = nowNs();
    for (0..frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}

pub fn timeVulkanDraw(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.VulkanBackendCache,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    if (comptime !build_options.enable_vulkan) unreachable;

    for (0..warmup_frames) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.state.setCommandBuffer(cmd);
        vk_renderer.state.setFrameSlot(vulkan_platform.currentOffscreenFrameIndex());
        try vk_renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
        vk_renderer.state.clearCommandBuffer();
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();

    const start = nowNs();
    for (0..frames) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.state.setCommandBuffer(cmd);
        vk_renderer.state.setFrameSlot(vulkan_platform.currentOffscreenFrameIndex());
        try vk_renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
        vk_renderer.state.clearCommandBuffer();
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}
