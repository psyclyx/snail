//! End-to-end rendering benchmark. Measures actual GPU frame time
//! including layout + upload + draw + glFinish.
//! Headless (invisible window + FBO). Answers: "how fast will this be?"

const std = @import("std");
const snail = @import("snail.zig");
const platform = @import("render/platform.zig");
const gl = platform.gl;
const assets = @import("assets");

const WIDTH = 1280;
const HEIGHT = 720;
const WARMUP = 100;
const FRAMES = 2000;

const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

const Scenario = struct {
    name: []const u8,
    build_fn: *const fn (*snail.Batch, *const snail.Atlas, *const snail.Font) void,
    expected_glyphs: usize,
};

fn buildHud(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    _ = batch.addString(atlas, font, "Score: 12345  FPS: 60  Level 7", 10, HEIGHT - 20, 18, .{ 1, 1, 1, 1 });
    _ = batch.addString(atlas, font, "Health: 100%  Ammo: 42/120", 10, HEIGHT - 44, 18, .{ 0.8, 0.2, 0.2, 1 });
}

fn buildMultiSize(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    const white = [4]f32{ 1, 1, 1, 1 };
    var y: f32 = HEIGHT - 30;
    for ([_]f32{ 12, 18, 24, 36, 48, 72 }) |sz| {
        _ = batch.addString(atlas, font, SENTENCE, 10, y, sz, white);
        y -= sz * 1.4;
    }
}

fn buildParagraph(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    const gray = [4]f32{ 0.9, 0.9, 0.9, 1 };
    var y: f32 = HEIGHT - 30;
    for (0..6) |_| {
        _ = batch.addString(atlas, font, PARAGRAPH, 10, y, 16, gray);
        y -= 22;
    }
}

fn buildTorture(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    const white = [4]f32{ 1, 1, 1, 1 };
    var y: f32 = HEIGHT - 10;
    var si: usize = 0;
    const sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
    while (y > 0) {
        const sz = sizes[si % sizes.len];
        _ = batch.addString(atlas, font, PARAGRAPH, 5, y, sz, white);
        y -= sz * 1.2;
        si += 1;
    }
}

fn runScenario(
    name: []const u8,
    buildFn: *const fn (*snail.Batch, *const snail.Atlas, *const snail.Font) void,
    atlas: *const snail.Atlas,
    font: *const snail.Font,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    // Measure glyph count
    var probe = snail.Batch.init(vbuf);
    buildFn(&probe, atlas, font);
    const glyphs = probe.glyphCount();

    // Static: pre-built batch, just draw
    const static_slice = probe.slice();
    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();

    const t_static = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const static_ns = nowNs() - t_static;
    const static_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(static_ns)) / 1e9);
    const static_us = @as(f64, @floatFromInt(static_ns)) / 1000.0 / FRAMES;

    // Dynamic: rebuild batch every frame, then draw
    for (0..WARMUP) |_| {
        var b = snail.Batch.init(vbuf);
        buildFn(&b, atlas, font);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();

    const t_dynamic = nowNs();
    for (0..FRAMES) |_| {
        var b = snail.Batch.init(vbuf);
        buildFn(&b, atlas, font);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const dynamic_ns = nowNs() - t_dynamic;
    const dynamic_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(dynamic_ns)) / 1e9);
    const dynamic_us = @as(f64, @floatFromInt(dynamic_ns)) / 1000.0 / FRAMES;

    std.debug.print("  {s:<30} {d:>4} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    // Hidden window
    if (platform.c.glfwInit() != platform.c.GLFW_TRUE) return error.GlfwInitFailed;
    platform.c.glfwWindowHint(platform.c.GLFW_VISIBLE, platform.c.GLFW_FALSE);
    platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MINOR, 3);
    platform.c.glfwWindowHint(platform.c.GLFW_OPENGL_PROFILE, platform.c.GLFW_OPENGL_CORE_PROFILE);
    const win = platform.c.glfwCreateWindow(WIDTH, HEIGHT, "bench", null, null) orelse return error.WindowFailed;
    platform.c.glfwMakeContextCurrent(win);
    defer platform.c.glfwDestroyWindow(win);
    defer platform.c.glfwTerminate();

    // FBO
    var fbo: gl.GLuint = 0;
    var fbo_tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &fbo_tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_tex, 0);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    defer gl.glDeleteFramebuffers(1, &fbo);
    defer gl.glDeleteTextures(1, &fbo_tex);

    // Setup
    const t_setup = nowNs();
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();
    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();
    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    renderer.uploadAtlas(&atlas);
    const setup_us = @as(f64, @floatFromInt(nowNs() - t_setup)) / 1000.0;

    const vbuf = try allocator.alloc(f32, 30000 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const mvp = snail.Mat4.ortho(0, WIDTH, 0, HEIGHT, -1, 1);

    std.debug.print(
        \\
        \\=== snail end-to-end rendering ({d}x{d}, {d} frames/test) ===
        \\  Setup (font + atlas + GL): {d:.0} us
        \\
        \\  "static" = pre-built vertex buffer, draw only (game HUD, menus)
        \\  "dynamic" = rebuild vertices + draw every frame (chat, editor, debug)
        \\
    , .{ WIDTH, HEIGHT, FRAMES, setup_us });

    runScenario("Game HUD (2 lines)", buildHud, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Multi-size (6 sizes)", buildMultiSize, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Body text (6 paragraphs)", buildParagraph, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Torture (fill screen)", buildTorture, &atlas, &font, &renderer, vbuf, mvp);

    std.debug.print("\n=========================================================\n", .{});
}
