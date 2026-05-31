//! GL counterpart to `screenshot.zig`. Renders the shared content
//! (see `content.zig`) through the GL upload + draw path
//! and writes `zig-out/demo-screenshot-gl.tga`.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const gl = @import("support").gl;
const demo_content = @import("content.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 400;
const H: u32 = 240;
const OUT_PATH = "zig-out/demo-screenshot-gl.tga";

const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;

const OffscreenTarget = struct {
    fbo: gl.GLuint = 0,
    fbo_tex: gl.GLuint = 0,

    fn init(width: u32, height: u32) !OffscreenTarget {
        var self = OffscreenTarget{};
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

    fn deinit(self: *OffscreenTarget) void {
        gl.glDeleteFramebuffers(1, &self.fbo);
        gl.glDeleteTextures(1, &self.fbo_tex);
    }
};

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(W, H, .gl33);
    defer gl_ctx.deinit();

    var target = try OffscreenTarget.init(W, H);
    defer target.deinit();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();

    var gl_renderer = try snail.Gl33Renderer.init(allocator);
    defer gl_renderer.deinit();

    var cache = try snail.Gl33PreparedPages.init(allocator, content.pool, .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
    const paths_binding = bindings[0];
    const text_binding = bindings[1];

    const words = try allocator.alloc(u32, snail.emit.wordBudget(&content.paths_picture, 0) + snail.emit.wordBudget(&content.text_picture, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &content.paths_atlas, &content.paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &content.text_atlas, &content.text_picture, .identity, .{ 1, 1, 1, 1 });

    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const draw_state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };

    const bg = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };
    gl.glClearColor(srgbToLinear(bg[0]), srgbToLinear(bg[1]), srgbToLinear(bg[2]), bg[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl_renderer.state.beginDraw();
    try gl_renderer.state.draw(
        allocator,
        draw_state,
        .{ .words = words[0..wlen], .segments = segs[0..slen] },
        &.{&cache},
    );

    const pixels = try screenshot.captureFramebuffer(allocator, W, H);
    defer allocator.free(pixels);

    _ = std.c.mkdir("zig-out", 0o755);
    try screenshot.writeTga(OUT_PATH, pixels, W, H);
    std.debug.print("wrote {s}\n", .{OUT_PATH});
}
