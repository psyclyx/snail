//! Shared rendering harness for the screenshot demos.
//!
//! The seven `screenshot*.zig` / `banner_screenshot*.zig` entry points
//! all do the same shape: build a `Scene` (one pool + paths+text
//! atlases + paths+text pictures), upload it to a per-backend cache,
//! emit two draw batches, run the backend's draw call, capture
//! pixels, and write a TGA. The harness owns the boilerplate; entry
//! points just wire backend-specific context (CPU pixel buffer, GL FBO,
//! Vulkan frame) and call the matching helper.
//!
//! Vulkan-specific orchestration lives at the entry-point so the
//! harness module doesn't pull `demo_platform_vulkan` into CPU/GL builds.

const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");
const support = @import("support");
const gl = support.gl;

pub const Scene = struct {
    pool: *snail.PagePool,
    paths_atlas: *const snail.Atlas,
    text_atlas: *const snail.Atlas,
    paths_picture: *const support.Picture,
    text_picture: *const support.Picture,
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
pub fn drawState(width: u32, height: u32) @import("snail-raster").DrawState {
    return drawStateExp(width, height, 1.0);
}

/// `drawState` with an explicit coverage-transfer exponent (the demo's
/// hinting-comparison view uses 0.55; screenshots default to 1.0).
pub fn drawStateExp(width: u32, height: u32, exponent: f32) @import("snail-raster").DrawState {
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    return .{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = exponent } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
}

/// Sum of the shape counts for both pictures in the scene.
pub fn shapeBudget(scene: Scene) usize {
    return scene.paths_picture.shapes.len + scene.text_picture.shapes.len;
}


pub const EmitOut = struct { instances_len: usize, batches_len: usize };

/// Emit both atlases' pictures into `instances` / `batches`. The buffers
/// must each hold at least `shapeBudget(scene)` items.
pub fn emitScene(
    instances: []snail.render.records.Instance,
    batches: []snail.render.records.DrawBatch,
    scene: Scene,
    paths_binding: snail.render.records.Binding,
    text_binding: snail.render.records.Binding,
) !EmitOut {
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(instances, batches, &wlen, &slen, paths_binding, scene.paths_atlas, scene.paths_picture.shapes, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &wlen, &slen, text_binding, scene.text_atlas, scene.text_picture.shapes, .identity, .{ 1, 1, 1, 1 });
    return .{ .instances_len = wlen, .batches_len = slen };
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
    /// Coverage-transfer exponent — match the demo's compare view (0.55) when
    /// diffing hinting; leave at 1.0 for a faithful linear-coverage capture.
    coverage_exponent: f32 = 1.0,
};

/// CPU end-to-end into a caller-owned buffer of the given `format` (stride =
/// width × bytesPerPixel). Not row-flipped — callers that sample full-height
/// content are orientation-independent. Used to verify non-rgba8 formats.
pub fn renderCpuToPixelsFmt(
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    format: @import("snail-raster").PixelFormat,
    opts: CpuOptions,
) ![]u8 {
    const stride: u32 = width * format.bytesPerPixel();
    const pixels = try allocator.alloc(u8, @as(usize, height) * stride);
    errdefer allocator.free(pixels);
    @memset(pixels, 0);

    var cache = try raster.DeviceAtlas.init(allocator, scene.pool, .{
        .max_bindings = opts.max_bindings,
        .layer_info_height = opts.layer_info_height,
        .max_images = opts.max_images,
    });
    defer cache.deinit();
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const instances = try allocator.alloc(snail.render.records.Instance, shapeBudget(scene));
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, shapeBudget(scene));
    defer allocator.free(batches);
    const e = try emitScene(instances, batches, scene, bindings[0], bindings[1]);

    var renderer = raster.Renderer.init(pixels.ptr, width, height, stride);
    renderer.format = format;
    try raster.draw(
        &renderer,
        drawState(width, height),
        .{ .instances = instances[0..e.instances_len], .batches = batches[0..e.batches_len] },
        &.{&cache},
        null,
    );
    return pixels;
}

/// CPU end-to-end into a caller-owned RGBA8 top-down buffer (the returned
/// slice is owned by `allocator`). `renderCpu` wraps this to write a TGA;
/// `backend_compare` uses it to diff against GL.
pub fn renderCpuToPixels(
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    opts: CpuOptions,
) ![]u8 {
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, @as(usize, height) * stride);
    errdefer allocator.free(pixels);
    fillBgRgba8(pixels);

    var cache = try raster.DeviceAtlas.init(allocator, scene.pool, .{
        .max_bindings = opts.max_bindings,
        .layer_info_height = opts.layer_info_height,
        .max_images = opts.max_images,
    });
    defer cache.deinit();
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const instances = try allocator.alloc(snail.render.records.Instance, shapeBudget(scene));
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, shapeBudget(scene));
    defer allocator.free(batches);
    const e = try emitScene(instances, batches, scene, bindings[0], bindings[1]);

    var renderer = raster.Renderer.init(pixels.ptr, width, height, stride);
    try raster.draw(
        &renderer,
        drawStateExp(width, height, opts.coverage_exponent),
        .{ .instances = instances[0..e.instances_len], .batches = batches[0..e.batches_len] },
        &.{&cache},
        null,
    );

    try flipRowsInPlace(allocator, pixels, width, height);
    return pixels;
}

/// CPU end-to-end: render and write a TGA.
pub fn renderCpu(
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    out_path: [*:0]const u8,
    opts: CpuOptions,
) !void {
    const pixels = try renderCpuToPixels(allocator, scene, width, height, opts);
    defer allocator.free(pixels);
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

    const GL_R8: gl.GLint = 0x8229;
    const GL_RED: gl.GLenum = 0x1903;

    pub fn init(width: u32, height: u32) !OffscreenGlTarget {
        return initFormat(width, height, GL_SRGB8_ALPHA8, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE);
    }

    /// Single-channel R8 target, for verifying GPU masks.
    pub fn initR8(width: u32, height: u32) !OffscreenGlTarget {
        return initFormat(width, height, GL_R8, GL_RED, gl.GL_UNSIGNED_BYTE);
    }

    pub fn initFormat(width: u32, height: u32, internal_format: gl.GLint, data_format: gl.GLenum, data_type: gl.GLenum) !OffscreenGlTarget {
        var self = OffscreenGlTarget{};
        gl.glGenFramebuffers(1, &self.fbo);
        gl.glGenTextures(1, &self.fbo_tex);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.fbo_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal_format, @intCast(width), @intCast(height), 0, data_format, data_type, null);
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
pub fn renderGlToPixels(
    comptime backend: GlBackend,
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    opts: GlOptions,
) ![]u8 {
    // Function-local so only modules that actually render GL pull in the
    // caller-owned reference renderer (embeddable-only); CPU/Vulkan tools import
    // this harness without needing `embed_gl` wired.
    const embed_gl = @import("embed_gl");
    const RendererT = switch (backend) {
        .gl33 => embed_gl.Gl33Renderer,
        .gles30 => embed_gl.Gles30Renderer,
    };
    const CacheT = switch (backend) {
        .gl33 => embed_gl.Gl33DeviceAtlas,
        .gles30 => embed_gl.Gles30DeviceAtlas,
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
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const instances = try allocator.alloc(snail.render.records.Instance, shapeBudget(scene));
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, shapeBudget(scene));
    defer allocator.free(batches);
    const e = try emitScene(instances, batches, scene, bindings[0], bindings[1]);

    clearGlBg();
    renderer.state.beginDraw();
    try renderer.state.draw(
        allocator,
        drawState(width, height),
        .{ .instances = instances[0..e.instances_len], .batches = batches[0..e.batches_len] },
        &.{&cache},
    );

    return support.screenshot.captureFramebuffer(allocator, width, height);
}

/// Render the scene into a bound R8 target with `surface.format = .r8_unorm`
/// (so the shader emits painted alpha to `.r`) and read the single channel
/// back. Verifies GPU masks. GL 3.3 only.
pub fn renderGlR8Mask(allocator: std.mem.Allocator, scene: Scene, width: u32, height: u32, opts: GlOptions) ![]u8 {
    const embed_gl = @import("embed_gl");
    var renderer = try embed_gl.Gl33Renderer.init(allocator);
    defer renderer.deinit();
    var cache = try embed_gl.Gl33DeviceAtlas.init(allocator, scene.pool, .{
        .max_bindings = opts.max_bindings,
        .layer_info_height = opts.layer_info_height,
        .max_images = opts.max_images,
        .max_image_width = opts.max_image_width,
        .max_image_height = opts.max_image_height,
    });
    defer cache.deinit();
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const instances = try allocator.alloc(snail.render.records.Instance, shapeBudget(scene));
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, shapeBudget(scene));
    defer allocator.free(batches);
    const e = try emitScene(instances, batches, scene, bindings[0], bindings[1]);

    gl.glClearColor(0, 0, 0, 0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const ds = @import("snail-raster").DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .linear, .format = .r8_unorm },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    renderer.state.beginDraw();
    try renderer.state.draw(allocator, ds, .{ .instances = instances[0..e.instances_len], .batches = batches[0..e.batches_len] }, &.{&cache});

    const px = try allocator.alloc(u8, @as(usize, width) * height);
    errdefer allocator.free(px);
    gl.glReadPixels(0, 0, @intCast(width), @intCast(height), OffscreenGlTarget.GL_RED, gl.GL_UNSIGNED_BYTE, px.ptr);
    return px;
}

pub fn renderGl(
    comptime backend: GlBackend,
    allocator: std.mem.Allocator,
    scene: Scene,
    width: u32,
    height: u32,
    out_path: [*:0]const u8,
    opts: GlOptions,
) !void {
    const pixels = try renderGlToPixels(backend, allocator, scene, width, height, opts);
    defer allocator.free(pixels);
    try writeOutput(out_path, pixels, width, height);
}
