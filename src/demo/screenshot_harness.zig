//! Shared rendering harness for the screenshot demos.
//!
//! The seven `screenshot*.zig` / `banner_screenshot*.zig` entry points
//! all do the same shape: build a `Scene` (one pool + paths+text
//! atlases + paths+text pictures), upload it to a per-backend cache,
//! emit two draw segments, run the backend's draw call, capture
//! pixels, and write a TGA. The harness owns the boilerplate; entry
//! points just wire backend-specific context (CPU pixel buffer, GL FBO,
//! Vulkan frame) and call the matching helper.
//!
//! Vulkan-specific orchestration lives at the entry-point so the
//! harness module doesn't pull `demo_platform_vulkan` into CPU/GL builds.

const std = @import("std");
const snail = @import("snail");
const snail_helpers = @import("snail-helpers");
const support = @import("support");
const gl = support.gl;

pub const Scene = struct {
    pool: *snail.PagePool,
    paths_atlas: *const snail.Atlas,
    text_atlas: *const snail.Atlas,
    paths_picture: *const snail_helpers.Picture,
    text_picture: *const snail_helpers.Picture,
};

/// Shared off-white background (sRGB).
pub const bg_srgb_u8 = [4]u8{ 245, 246, 249, 255 };
pub const bg_srgb_f32 = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };

pub fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

/// Fill a top-down RGBA8 buffer with the shared background color.
pub fn fillBgRgba8(pixels: []u8) void {
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        pixels[i + 0] = bg_srgb_u8[0];
        pixels[i + 1] = bg_srgb_u8[1];
        pixels[i + 2] = bg_srgb_u8[2];
        pixels[i + 3] = bg_srgb_u8[3];
    }
}

/// In-place vertical flip of a packed RGBA8 buffer.
pub fn flipRowsInPlace(allocator: std.mem.Allocator, pixels: []u8, width: u32, height: u32) !void {
    const stride: usize = @as(usize, width) * 4;
    const row_tmp = try allocator.alloc(u8, stride);
    defer allocator.free(row_tmp);
    var y: usize = 0;
    while (y < height / 2) : (y += 1) {
        const top = y * stride;
        const bottom = (@as(usize, height) - 1 - y) * stride;
        @memcpy(row_tmp, pixels[top..][0..stride]);
        @memcpy(pixels[top..][0..stride], pixels[bottom..][0..stride]);
        @memcpy(pixels[bottom..][0..stride], row_tmp);
    }
}

/// Standard ortho draw state for the screenshot harness: grayscale AA,
/// sRGB surface, ortho MVP matching the pixel rect.
pub fn drawState(width: u32, height: u32) snail.DrawState {
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    return .{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
}

/// Sum of the word budgets for both pictures in the scene.
pub fn wordBudget(scene: Scene) usize {
    return snail.emit.wordBudget(scene.paths_picture.shapes.len, 0) + snail.emit.wordBudget(scene.text_picture.shapes.len, 0);
}

pub const EmitOut = struct { words_len: usize, segs_len: usize };

/// Emit both atlases' pictures into `words` / `segs`. The buffers must
/// be large enough — `wordBudget(scene)` for words, ≥4 entries for segs.
pub fn emitScene(
    words: []u32,
    segs: []snail.DrawSegment,
    scene: Scene,
    paths_binding: snail.Binding,
    text_binding: snail.Binding,
) !EmitOut {
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, scene.paths_atlas, scene.paths_picture.shapes, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, scene.text_atlas, scene.text_picture.shapes, .identity, .{ 1, 1, 1, 1 });
    return .{ .words_len = wlen, .segs_len = slen };
}

/// Make `zig-out` and write the buffer as TGA, logging the path.
pub fn writeOutput(out_path: [*:0]const u8, pixels: []const u8, width: u32, height: u32) !void {
    _ = std.c.mkdir("zig-out", 0o755);
    try support.screenshot.writeTga(out_path, pixels, width, height);
    std.debug.print("wrote {s}\n", .{out_path});
}

// ── CPU helper ──────────────────────────────────────────────────────

pub const CpuOptions = struct {
    max_bindings: u32 = 4,
    layer_info_height: u32 = 64,
    max_images: u32 = 8,
};

/// CPU end-to-end: allocate pixels, fill bg, upload, emit, draw, flip, write.
pub fn renderCpu(
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    out_path: [*:0]const u8,
    opts: CpuOptions,
) !void {
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, @as(usize, height) * stride);
    defer allocator.free(pixels);
    fillBgRgba8(pixels);

    var cache = try snail.CpuBackendCache.init(allocator, scene.pool, .{
        .max_bindings = opts.max_bindings,
        .layer_info_height = opts.layer_info_height,
        .max_images = opts.max_images,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const words = try allocator.alloc(u32, wordBudget(scene));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);
    const e = try emitScene(words, segs, scene, bindings[0], bindings[1]);

    var renderer = snail.CpuRenderer.init(pixels.ptr, width, height, stride);
    try snail.drawCpu(
        &renderer,
        drawState(width, height),
        .{ .words = words[0..e.words_len], .segments = segs[0..e.segs_len] },
        &.{&cache},
        null,
    );

    try flipRowsInPlace(allocator, pixels, width, height);
    try writeOutput(out_path, pixels, width, height);
}

// ── GL/GLES30 helpers ───────────────────────────────────────────────

pub const GlOptions = struct {
    max_bindings: u32 = 4,
    layer_info_height: u32 = 64,
    max_images: u32 = 8,
    max_image_width: u32 = 256,
    max_image_height: u32 = 256,
};

const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;

/// Offscreen FBO + sRGB-RGBA8 texture for GL / GLES30 screenshots.
pub const OffscreenGlTarget = struct {
    fbo: gl.GLuint = 0,
    fbo_tex: gl.GLuint = 0,

    pub fn init(width: u32, height: u32) !OffscreenGlTarget {
        var self = OffscreenGlTarget{};
        gl.glGenFramebuffers(1, &self.fbo);
        gl.glGenTextures(1, &self.fbo_tex);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.fbo_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, @intCast(width), @intCast(height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.fbo_tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        return self;
    }

    pub fn deinit(self: *OffscreenGlTarget) void {
        gl.glDeleteFramebuffers(1, &self.fbo);
        gl.glDeleteTextures(1, &self.fbo_tex);
    }
};

/// Clear the bound framebuffer to the shared background color. Use after
/// `OffscreenGlTarget.init` and before drawing.
pub fn clearGlBg() void {
    gl.glClearColor(
        srgbToLinear(bg_srgb_f32[0]),
        srgbToLinear(bg_srgb_f32[1]),
        srgbToLinear(bg_srgb_f32[2]),
        bg_srgb_f32[3],
    );
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
}

pub const GlBackend = enum { gl33, gles30 };

/// GL/GLES30 end-to-end: assumes an EGL/EGL-ES context is current and an
/// `OffscreenGlTarget` is bound. Sets up the backend renderer + cache,
/// emits, draws, captures, writes.
pub fn renderGl(
    comptime backend: GlBackend,
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    out_path: [*:0]const u8,
    opts: GlOptions,
) !void {
    const RendererT = switch (backend) {
        .gl33 => snail.Gl33Renderer,
        .gles30 => snail.Gles30Renderer,
    };
    const CacheT = switch (backend) {
        .gl33 => snail.Gl33BackendCache,
        .gles30 => snail.Gles30BackendCache,
    };

    var renderer = try RendererT.init(allocator);
    defer renderer.deinit();

    var cache = try CacheT.init(allocator, scene.pool, .{
        .max_bindings = opts.max_bindings,
        .layer_info_height = opts.layer_info_height,
        .max_images = opts.max_images,
        .max_image_width = opts.max_image_width,
        .max_image_height = opts.max_image_height,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const words = try allocator.alloc(u32, wordBudget(scene));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);
    const e = try emitScene(words, segs, scene, bindings[0], bindings[1]);

    clearGlBg();
    renderer.state.beginDraw();
    try renderer.state.draw(
        allocator,
        drawState(width, height),
        .{ .words = words[0..e.words_len], .segments = segs[0..e.segs_len] },
        &.{&cache},
    );

    const pixels = try support.screenshot.captureFramebuffer(allocator, width, height);
    defer allocator.free(pixels);
    try writeOutput(out_path, pixels, width, height);
}
