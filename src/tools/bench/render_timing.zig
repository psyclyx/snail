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
const embed_vulkan = if (build_options.enable_vulkan) @import("embed_vulkan") else struct {};

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
    thread_pool: ?*snail.ThreadPool,
) !f64 {
    for (0..warmup_frames) |_| {
        @memset(pixels, 0);
        try snail.drawCpu(renderer, state, .{ .words = records.words, .segments = records.segments }, caches, thread_pool);
    }

    const start = nowNs();
    for (0..frames) |_| {
        @memset(pixels, 0);
        try snail.drawCpu(renderer, state, .{ .words = records.words, .segments = records.segments }, caches, thread_pool);
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

pub const Gl33Breakdown = struct {
    clear_us: f64,
    begin_us: f64,
    draw_us: f64,
    finish_us: f64,
    total_us: f64,
    gpu_us: f64,
};

/// Pure GPU-side draw time using a `GL_TIME_ELAPSED` timer query — no
/// CPU clock involved, no glFinish needed. Returns the minimum of
/// `samples` repeated runs of `frames` queries each. Min is more
/// robust than mean for an isolated GPU measurement: the true cost is
/// what the hardware actually does; any larger sample is the result
/// of an external disturbance (clock thrash, other contention) and
/// should be filtered out.
pub fn timeGl33DrawGpu(
    allocator: std.mem.Allocator,
    renderer: *snail.Gl33Renderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.Gl33BackendCache,
    warmup_frames: usize,
    frames: usize,
    samples: usize,
) !f64 {
    var query: gl.GLuint = 0;
    gl.glGenQueries(1, &query);
    defer gl.glDeleteQueries(1, &query);

    for (0..warmup_frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();

    var min_per_frame_us: f64 = std.math.inf(f64);
    for (0..samples) |_| {
        var total_ns: u64 = 0;
        for (0..frames) |_| {
            clearGlFrame();
            renderer.state.beginDraw();
            gl.glBeginQuery(gl.GL_TIME_ELAPSED, query);
            try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
            gl.glEndQuery(gl.GL_TIME_ELAPSED);
            var elapsed_ns: u64 = 0;
            gl.glGetQueryObjectui64v(query, gl.GL_QUERY_RESULT, &elapsed_ns);
            total_ns += elapsed_ns;
        }
        const per_frame_us = @as(f64, @floatFromInt(total_ns)) / 1000.0 / @as(f64, @floatFromInt(frames));
        if (per_frame_us < min_per_frame_us) min_per_frame_us = per_frame_us;
    }
    return min_per_frame_us;
}

/// Per-stage GL 3.3 timing for one scene. Includes a per-frame glFinish
/// so each measurement reflects strict CPU submission cost — handy for
/// pinpointing which stage is responsible for residual per-frame
/// overhead, at the cost of losing the GPU pipelining the
/// non-breakdown harness depends on.
pub fn timeGl33DrawBreakdown(
    allocator: std.mem.Allocator,
    renderer: *snail.Gl33Renderer,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const snail.Gl33BackendCache,
    warmup_frames: usize,
    frames: usize,
) !Gl33Breakdown {
    for (0..warmup_frames) |_| {
        clearGlFrame();
        renderer.state.beginDraw();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
    }
    gl.glFinish();

    var clear_ns: u64 = 0;
    var begin_ns: u64 = 0;
    var draw_ns: u64 = 0;
    var finish_ns: u64 = 0;

    for (0..frames) |_| {
        const t0 = nowNs();
        clearGlFrame();
        const t1 = nowNs();
        renderer.state.beginDraw();
        const t2 = nowNs();
        try renderer.state.draw(allocator, state, .{ .words = records.words, .segments = records.segments }, caches);
        const t3 = nowNs();
        gl.glFinish();
        const t4 = nowNs();
        clear_ns += t1 - t0;
        begin_ns += t2 - t1;
        draw_ns += t3 - t2;
        finish_ns += t4 - t3;
    }
    const n: f64 = @floatFromInt(frames);
    const gpu_us = try timeGl33DrawGpu(allocator, renderer, state, records, caches, 0, frames, 5);
    return .{
        .clear_us = @as(f64, @floatFromInt(clear_ns)) / 1000.0 / n,
        .begin_us = @as(f64, @floatFromInt(begin_ns)) / 1000.0 / n,
        .draw_us = @as(f64, @floatFromInt(draw_ns)) / 1000.0 / n,
        .finish_us = @as(f64, @floatFromInt(finish_ns)) / 1000.0 / n,
        .total_us = @as(f64, @floatFromInt(clear_ns + begin_ns + draw_ns + finish_ns)) / 1000.0 / n,
        .gpu_us = gpu_us,
    };
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

/// Times the embeddable caller path (`embed_vulkan.Renderer`) — the same code
/// integrators use — not the all-in-one renderer.
pub fn timeVulkanDraw(
    caller: *embed_vulkan.Renderer,
    desc_set: embed_vulkan.vk.VkDescriptorSet,
    state: snail.DrawState,
    records: DrawRecords,
    warmup_frames: usize,
    frames: usize,
) !f64 {
    if (comptime !build_options.enable_vulkan) unreachable;

    for (0..warmup_frames) |_| {
        const cmd: embed_vulkan.vk.VkCommandBuffer = @ptrCast(vulkan_platform.beginFrameOffscreen());
        caller.render(cmd, desc_set, state, records.words, records.segments);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();

    const start = nowNs();
    for (0..frames) |_| {
        const cmd: embed_vulkan.vk.VkCommandBuffer = @ptrCast(vulkan_platform.beginFrameOffscreen());
        caller.render(cmd, desc_set, state, records.words, records.segments);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    return usFrom(start) / @as(f64, @floatFromInt(frames));
}
