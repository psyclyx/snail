//! Consolidated benchmark suite for snail GPU font rendering.
//! Outputs a single table covering preparation, layout (vs FreeType),
//! and rendering (all scenarios, static + dynamic).

const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const platform = @import("render/platform.zig");
const vulkan_platform = if (build_options.enable_vulkan) @import("render/vulkan_platform.zig") else undefined;
const gl = platform.gl;
const pipeline = @import("render/pipeline.zig");
const assets = @import("assets");

const c_ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

const WIDTH = 1280;
const HEIGHT = 720;
const WARMUP = 100;
const FRAMES = 2000;
const LAYOUT_ITERS = 500;

const SHORT = "Hello, world!";
const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";
const ARABIC_TEXT = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x85\xd9\x86 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x8a\xd9\x85";
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0";
const THAI_TEXT = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a";
const SIZES = [_]u32{ 12, 18, 24, 36, 48, 72, 96 };
const white = [4]f32{ 1, 1, 1, 1 };

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

fn initCodepoints(text: []const u8, buf: []u32) []u32 {
    var n: usize = 0;
    const view = std.unicode.Utf8View.initUnchecked(text);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (n >= buf.len) break;
        buf[n] = cp;
        n += 1;
    }
    return buf[0..n];
}

// ── Rendering scenarios ──

const FontEntry = struct {
    atlas: *const snail.Atlas,
    font: *const snail.Font,
    text: []const u8,
    font_size: f32,
};

fn addRoundedRect(
    batch: *snail.VectorBatch,
    rect: snail.VectorRect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
) void {
    _ = batch.addRoundedRect(rect, fill, border, border_width, corner_radius);
}

fn buildHud(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    _ = batch.addString(atlas, font, "Score: 12345  FPS: 60  Level 7", 10, HEIGHT - 20, 18, white);
    _ = batch.addString(atlas, font, "Health: 100%  Ammo: 42/120", 10, HEIGHT - 44, 18, .{ 0.8, 0.2, 0.2, 1 });
}

fn buildMultiSize(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    var y: f32 = HEIGHT - 30;
    for ([_]f32{ 12, 18, 24, 36, 48, 72 }) |sz| {
        _ = batch.addString(atlas, font, SENTENCE, 10, y, sz, white);
        y -= sz * 1.4;
    }
}

fn buildParagraph(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    var y: f32 = HEIGHT - 30;
    for (0..6) |_| {
        _ = batch.addString(atlas, font, PARAGRAPH, 10, y, 16, white);
        y -= 22;
    }
}

fn buildTorture(batch: *snail.Batch, atlas: *const snail.Atlas, font: *const snail.Font) void {
    var y: f32 = HEIGHT - 10;
    var si: usize = 0;
    const sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
    while (y > 0) {
        _ = batch.addString(atlas, font, PARAGRAPH, 5, y, sizes[si % sizes.len], white);
        y -= sizes[si % sizes.len] * 1.2;
        si += 1;
    }
}

fn buildVectorShowcase(batch: *snail.VectorBatch) void {
    addRoundedRect(batch, .{ .x = 24, .y = 24, .w = 420, .h = 180 }, .{ 0.08, 0.09, 0.11, 0.9 }, .{ 0.25, 0.28, 0.33, 1 }, 1.5, 24);
    addRoundedRect(batch, .{ .x = 472, .y = 24, .w = 360, .h = 180 }, .{ 0.09, 0.11, 0.14, 0.88 }, .{ 0.2, 0.24, 0.3, 1 }, 1.5, 22);
    addRoundedRect(batch, .{ .x = 40, .y = 52, .w = 132, .h = 28 }, .{ 0.2, 0.48, 0.86, 0.2 }, .{ 0.2, 0.48, 0.86, 0.9 }, 1.0, 14);
    addRoundedRect(batch, .{ .x = 40, .y = 96, .w = 216, .h = 14 }, .{ 0.92, 0.95, 0.99, 0.08 }, .{ 0.92, 0.95, 0.99, 0.28 }, 1.0, 7);
    addRoundedRect(batch, .{ .x = 40, .y = 126, .w = 168, .h = 18 }, .{ 0.95, 0.74, 0.28, 0.16 }, .{ 0.95, 0.74, 0.28, 0.84 }, 1.0, 9);
    _ = batch.addEllipse(
        .{ .x = 642, .y = 48, .w = 144, .h = 144 },
        .{ 0.28, 0.72, 0.92, 0.16 },
        .{ 0.28, 0.72, 0.92, 0.78 },
        2,
    );
    _ = batch.addEllipse(
        .{ .x = 688, .y = 88, .w = 72, .h = 72 },
        .{ 0.96, 0.74, 0.28, 0.22 },
        .{ 0.96, 0.74, 0.28, 0.9 },
        1.5,
    );
    addRoundedRect(batch, .{ .x = 880, .y = 24, .w = 376, .h = 180 }, .{ 0.08, 0.1, 0.12, 0.84 }, .{ 0.18, 0.21, 0.26, 1 }, 1.5, 20);
    addRoundedRect(batch, .{ .x = 904, .y = 54, .w = 220, .h = 20 }, .{ 0.32, 0.84, 0.56, 0.16 }, .{ 0.32, 0.84, 0.56, 0.9 }, 1.0, 10);
    addRoundedRect(batch, .{ .x = 904, .y = 92, .w = 148, .h = 20 }, .{ 0.84, 0.42, 0.78, 0.14 }, .{ 0.84, 0.42, 0.78, 0.84 }, 1.0, 10);
}

fn buildVectorStress(batch: *snail.VectorBatch) void {
    var row: usize = 0;
    var y: f32 = 18;
    while (y < HEIGHT - 46) : ({
        y += 34;
        row += 1;
    }) {
        var col: usize = 0;
        var x: f32 = 18;
        while (x < WIDTH - 78) : ({
            x += 56;
            col += 1;
        }) {
            const even = ((row + col) & 1) == 0;
            const fill = if (even)
                [4]f32{ 0.16, 0.46, 0.86, 0.2 }
            else
                [4]f32{ 0.95, 0.7, 0.25, 0.18 };
            const border = if (even)
                [4]f32{ 0.16, 0.46, 0.86, 0.82 }
            else
                [4]f32{ 0.95, 0.7, 0.25, 0.82 };
            addRoundedRect(batch, .{ .x = x, .y = y, .w = 42, .h = 22 }, fill, border, 1, 7);
            if ((row + col) % 3 == 0) {
                _ = batch.addEllipse(
                    .{ .x = x + 10, .y = y + 4, .w = 22, .h = 14 },
                    .{ 0.92, 0.96, 1, 0.1 },
                    .{ 0.92, 0.96, 1, 0.3 },
                    1,
                );
            }
        }
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
    var probe = snail.Batch.init(vbuf);
    buildFn(&probe, atlas, font);
    const glyphs = probe.glyphCount();
    const static_slice = probe.slice();

    // Static
    for (0..WARMUP) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(static_slice, mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const t_s = nowNs();
    for (0..FRAMES) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(static_slice, mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const s_ns = nowNs() - t_s;

    // Dynamic
    for (0..WARMUP) |_| { var b = snail.Batch.init(vbuf); buildFn(&b, atlas, font); gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(b.slice(), mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const t_d = nowNs();
    for (0..FRAMES) |_| { var b = snail.Batch.init(vbuf); buildFn(&b, atlas, font); gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(b.slice(), mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, glyphs, s_fps, s_us, d_fps, d_us });
}

fn runMultiFontScenario(
    name: []const u8,
    font_sets: []const FontEntry,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    var total_glyphs: usize = 0;
    for (font_sets) |fs| { var b = snail.Batch.init(vbuf); _ = b.addString(fs.atlas, fs.font, fs.text, 10, 400, fs.font_size, white); total_glyphs += b.glyphCount(); }

    // Static
    var probe = snail.Batch.init(vbuf);
    { var y: f32 = HEIGHT - 30; for (font_sets) |fs| { _ = probe.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; } }
    const static_slice = probe.slice();
    for (0..WARMUP) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(static_slice, mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const t_s = nowNs();
    for (0..FRAMES) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); renderer.draw(static_slice, mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const s_ns = nowNs() - t_s;

    // Dynamic
    for (0..WARMUP) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); var b = snail.Batch.init(vbuf); var y: f32 = HEIGHT - 30; for (font_sets) |fs| { _ = b.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; } renderer.draw(b.slice(), mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const t_d = nowNs();
    for (0..FRAMES) |_| { gl.glClear(gl.GL_COLOR_BUFFER_BIT); var b = snail.Batch.init(vbuf); var y: f32 = HEIGHT - 30; for (font_sets) |fs| { _ = b.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; } renderer.draw(b.slice(), mvp, WIDTH, HEIGHT); }
    gl.glFinish();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, total_glyphs, s_fps, s_us, d_fps, d_us });
}

fn runVectorScenario(
    name: []const u8,
    buildFn: *const fn (*snail.VectorBatch) void,
    renderer: *snail.Renderer,
    vbuf: []f32,
) void {
    var probe = snail.VectorBatch.init(vbuf);
    buildFn(&probe);
    const shapes = probe.shapeCount();
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.beginFrame();
        renderer.drawVector(static_slice, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const t_s = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.beginFrame();
        renderer.drawVector(static_slice, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const s_ns = nowNs() - t_s;

    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.beginFrame();
        var b = snail.VectorBatch.init(vbuf);
        buildFn(&b);
        renderer.drawVector(b.slice(), WIDTH, HEIGHT);
    }
    gl.glFinish();
    const t_d = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.beginFrame();
        var b = snail.VectorBatch.init(vbuf);
        buildFn(&b);
        renderer.drawVector(b.slice(), WIDTH, HEIGHT);
    }
    gl.glFinish();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, shapes, s_fps, s_us, d_fps, d_us });
}

// ── Vulkan scenario runners ──

const runScenarioVulkan = if (build_options.enable_vulkan) runScenarioVulkanImpl else @compileError("vulkan disabled");

fn runScenarioVulkanImpl(
    name: []const u8,
    buildFn: *const fn (*snail.Batch, *const snail.Atlas, *const snail.Font) void,
    atlas: *const snail.Atlas,
    font: *const snail.Font,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    var probe = snail.Batch.init(vbuf);
    buildFn(&probe, atlas, font);
    const glyphs = probe.glyphCount();
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_s = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const s_ns = nowNs() - t_s;

    for (0..WARMUP) |_| {
        var b = snail.Batch.init(vbuf);
        buildFn(&b, atlas, font);
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_d = nowNs();
    for (0..FRAMES) |_| {
        var b = snail.Batch.init(vbuf);
        buildFn(&b, atlas, font);
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, glyphs, s_fps, s_us, d_fps, d_us });
}

fn runMultiFontScenarioVulkan(
    name: []const u8,
    font_sets: []const FontEntry,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    var total_glyphs: usize = 0;
    for (font_sets) |fs| { var b = snail.Batch.init(vbuf); _ = b.addString(fs.atlas, fs.font, fs.text, 10, 400, fs.font_size, white); total_glyphs += b.glyphCount(); }

    var probe = snail.Batch.init(vbuf);
    { var y: f32 = HEIGHT - 30; for (font_sets) |fs| { _ = probe.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; } }
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_s = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.draw(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const s_ns = nowNs() - t_s;

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            var b = snail.Batch.init(vbuf);
            var y: f32 = HEIGHT - 30;
            for (font_sets) |fs| { _ = b.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; }
            renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_d = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            var b = snail.Batch.init(vbuf);
            var y: f32 = HEIGHT - 30;
            for (font_sets) |fs| { _ = b.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white); y -= fs.font_size * 1.5; }
            renderer.draw(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, total_glyphs, s_fps, s_us, d_fps, d_us });
}

fn runVectorScenarioVulkan(
    name: []const u8,
    buildFn: *const fn (*snail.VectorBatch) void,
    renderer: *snail.Renderer,
    vbuf: []f32,
) void {
    var probe = snail.VectorBatch.init(vbuf);
    buildFn(&probe);
    const shapes = probe.shapeCount();
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        renderer.setCommandBuffer(cmd);
        renderer.beginFrame();
        renderer.drawVector(static_slice, WIDTH, HEIGHT);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    const t_s = nowNs();
    for (0..FRAMES) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        renderer.setCommandBuffer(cmd);
        renderer.beginFrame();
        renderer.drawVector(static_slice, WIDTH, HEIGHT);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    const s_ns = nowNs() - t_s;

    for (0..WARMUP) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        renderer.setCommandBuffer(cmd);
        renderer.beginFrame();
        var b = snail.VectorBatch.init(vbuf);
        buildFn(&b);
        renderer.drawVector(b.slice(), WIDTH, HEIGHT);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    const t_d = nowNs();
    for (0..FRAMES) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        renderer.setCommandBuffer(cmd);
        renderer.beginFrame();
        var b = snail.VectorBatch.init(vbuf);
        buildFn(&b);
        renderer.drawVector(b.slice(), WIDTH, HEIGHT);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    const d_ns = nowNs() - t_d;

    const s_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(s_ns)) / 1e9);
    const s_us = @as(f64, @floatFromInt(s_ns)) / 1000.0 / FRAMES;
    const d_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(d_ns)) / 1e9);
    const d_us = @as(f64, @floatFromInt(d_ns)) / 1000.0 / FRAMES;
    std.debug.print("  {s:<32} {d:>5}  {d:>8.0} ({d:>6.1})  {d:>8.0} ({d:>6.1})\n", .{ name, shapes, s_fps, s_us, d_fps, d_us });
}

// ── FreeType layout benchmark ──

fn benchFreetypeLayout(font_data: []const u8) !struct { short: f64, sentence: f64, paragraph: f64, torture: f64 } {
    var library: c_ft.FT_Library = null;
    if (c_ft.FT_Init_FreeType(&library) != 0) return error.FTInitFailed;
    defer _ = c_ft.FT_Done_FreeType(library);
    var face: c_ft.FT_Face = null;
    if (c_ft.FT_New_Memory_Face(library, font_data.ptr, @intCast(font_data.len), 0, &face) != 0) return error.FTFaceFailed;
    defer _ = c_ft.FT_Done_Face(face);

    const layoutString = struct {
        fn f(fc: c_ft.FT_Face, text: []const u8) void {
            var pen_x: i32 = 0;
            var prev: u32 = 0;
            for (text) |ch| {
                const gi = c_ft.FT_Get_Char_Index(fc, ch);
                if (prev != 0 and gi != 0) { var d: c_ft.FT_Vector = undefined; _ = c_ft.FT_Get_Kerning(fc, prev, gi, c_ft.FT_KERNING_DEFAULT, &d); pen_x += @intCast(d.x >> 6); }
                if (c_ft.FT_Load_Glyph(fc, gi, c_ft.FT_LOAD_DEFAULT) != 0) { prev = gi; continue; }
                pen_x += @intCast(fc.*.glyph.*.advance.x >> 6);
                prev = gi;
            }
            std.mem.doNotOptimizeAway(&pen_x);
        }
    }.f;

    _ = c_ft.FT_Set_Pixel_Sizes(face, 0, 24);
    var t = nowNs();
    for (0..LAYOUT_ITERS) |_| layoutString(face, SHORT);
    const short = usFrom(t) / LAYOUT_ITERS;

    _ = c_ft.FT_Set_Pixel_Sizes(face, 0, 48);
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| layoutString(face, SENTENCE);
    const sentence = usFrom(t) / LAYOUT_ITERS;

    _ = c_ft.FT_Set_Pixel_Sizes(face, 0, 18);
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| layoutString(face, PARAGRAPH);
    const paragraph = usFrom(t) / LAYOUT_ITERS;

    t = nowNs();
    for (0..LAYOUT_ITERS) |_| { for (SIZES) |sz| { _ = c_ft.FT_Set_Pixel_Sizes(face, 0, sz); layoutString(face, PARAGRAPH); } }
    const torture = usFrom(t) / LAYOUT_ITERS;

    return .{ .short = short, .sentence = sentence, .paragraph = paragraph, .torture = torture };
}

// ── Main ──

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const hb_str = if (build_options.enable_harfbuzz) "ON" else "OFF";

    // ── OpenGL section (layout comparison + rendering) ──
    {
        // Hidden window
        if (platform.c.glfwInit() != platform.c.GLFW_TRUE) return error.GlfwInitFailed;
        platform.c.glfwWindowHint(platform.c.GLFW_VISIBLE, platform.c.GLFW_FALSE);
        platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MAJOR, 4);
        platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MINOR, 4);
        platform.c.glfwWindowHint(platform.c.GLFW_OPENGL_PROFILE, platform.c.GLFW_OPENGL_CORE_PROFILE);
        var win = platform.c.glfwCreateWindow(WIDTH, HEIGHT, "bench", null, null);
        if (win == null) {
            platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MAJOR, 3);
            platform.c.glfwWindowHint(platform.c.GLFW_CONTEXT_VERSION_MINOR, 3);
            platform.c.glfwWindowHint(platform.c.GLFW_VISIBLE, platform.c.GLFW_FALSE);
            win = platform.c.glfwCreateWindow(WIDTH, HEIGHT, "bench", null, null);
        }
        if (win == null) return error.WindowFailed;
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

        // Multi-script fonts
        var arabic_font = try snail.Font.init(assets.noto_sans_arabic);
        defer arabic_font.deinit();
        var arabic_atlas = try snail.Atlas.init(allocator, &arabic_font, &.{});
        defer arabic_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(ARABIC_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try arabic_atlas.addGlyphsForText(ARABIC_TEXT); } else { _ = try arabic_atlas.addCodepoints(cp); } }

        var deva_font = try snail.Font.init(assets.noto_sans_devanagari);
        defer deva_font.deinit();
        var deva_atlas = try snail.Atlas.init(allocator, &deva_font, &.{});
        defer deva_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(DEVANAGARI_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try deva_atlas.addGlyphsForText(DEVANAGARI_TEXT); } else { _ = try deva_atlas.addCodepoints(cp); } }

        var thai_font = try snail.Font.init(assets.noto_sans_thai);
        defer thai_font.deinit();
        var thai_atlas = try snail.Atlas.init(allocator, &thai_font, &.{});
        defer thai_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(THAI_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try thai_atlas.addGlyphsForText(THAI_TEXT); } else { _ = try thai_atlas.addCodepoints(cp); } }

        var renderer = try snail.Renderer.init();
        defer renderer.deinit();
        renderer.uploadAtlases(&[_]*const snail.Atlas{ &atlas, &arabic_atlas, &deva_atlas, &thai_atlas });
        const setup_us = usFrom(t_setup);

        const vbuf = try allocator.alloc(f32, 30000 * snail.FLOATS_PER_GLYPH);
        defer allocator.free(vbuf);
        const vector_buf = try allocator.alloc(f32, 4096 * snail.VECTOR_FLOATS_PER_PRIMITIVE);
        defer allocator.free(vector_buf);
        const mvp = snail.Mat4.ortho(0, WIDTH, 0, HEIGHT, -1, 1);

        // ── Header ──
        std.debug.print(
            \\
            \\=== snail benchmark suite ===
            \\  Backend: {s} | HarfBuzz: {s} | {d}x{d} | {d} frames/test
            \\  Setup (4 fonts + atlases + texture array): {d:.0} us
            \\
        , .{ pipeline.getBackendName(), hb_str, WIDTH, HEIGHT, FRAMES, setup_us });

        // ── Layout: snail vs FreeType ──
        std.debug.print(
            \\  ── Layout ({d} iters, snail vs FreeType) ──
            \\  Scenario                          snail       FreeType    speedup
            \\
        , .{LAYOUT_ITERS});

        var layout_vbuf: [20000 * snail.FLOATS_PER_GLYPH]f32 = undefined;
        var t = nowNs();
        for (0..LAYOUT_ITERS) |_| { var b = snail.Batch.init(&layout_vbuf); _ = b.addString(&atlas, &font, SHORT, 0, 0, 24, white); std.mem.doNotOptimizeAway(&b); }
        const s_short = usFrom(t) / LAYOUT_ITERS;
        t = nowNs();
        for (0..LAYOUT_ITERS) |_| { var b = snail.Batch.init(&layout_vbuf); _ = b.addString(&atlas, &font, SENTENCE, 0, 0, 48, white); std.mem.doNotOptimizeAway(&b); }
        const s_sent = usFrom(t) / LAYOUT_ITERS;
        t = nowNs();
        for (0..LAYOUT_ITERS) |_| { var b = snail.Batch.init(&layout_vbuf); _ = b.addString(&atlas, &font, PARAGRAPH, 0, 0, 18, white); std.mem.doNotOptimizeAway(&b); }
        const s_para = usFrom(t) / LAYOUT_ITERS;
        t = nowNs();
        for (0..LAYOUT_ITERS) |_| { var b = snail.Batch.init(&layout_vbuf); var y: f32 = 700; for (SIZES) |sz| { _ = b.addString(&atlas, &font, PARAGRAPH, 0, y, @floatFromInt(sz), white); y -= @as(f32, @floatFromInt(sz)) * 1.4; } std.mem.doNotOptimizeAway(&b); }
        const s_tort = usFrom(t) / LAYOUT_ITERS;

        const ft_bench = try benchFreetypeLayout(assets.noto_sans_regular);

        const layout_rows = [_]struct { name: []const u8, snail_us: f64, ft_us: f64 }{
            .{ .name = "Short string (13 chars)", .snail_us = s_short, .ft_us = ft_bench.short },
            .{ .name = "Sentence (53 chars)", .snail_us = s_sent, .ft_us = ft_bench.sentence },
            .{ .name = "Paragraph (175 chars)", .snail_us = s_para, .ft_us = ft_bench.paragraph },
            .{ .name = "Torture (para x 7 sizes)", .snail_us = s_tort, .ft_us = ft_bench.torture },
        };
        for (layout_rows) |r| {
            std.debug.print("  {s:<32} {d:>8.1} us  {d:>8.1} us    {d:>5.1}x\n", .{
                r.name, r.snail_us, r.ft_us, r.ft_us / @max(r.snail_us, 0.001),
            });
        }

        // ── GL Rendering ──
        std.debug.print(
            \\
            \\  ── Rendering (OpenGL) ──
            \\  Scenario                          Glyphs  static FPS (us)   dynamic FPS (us)
            \\
        , .{});

        runScenario("Game HUD (2 lines)", buildHud, &atlas, &font, &renderer, vbuf, mvp);
        runScenario("Multi-size (6 sizes)", buildMultiSize, &atlas, &font, &renderer, vbuf, mvp);
        runScenario("Body text (6 paragraphs)", buildParagraph, &atlas, &font, &renderer, vbuf, mvp);
        runScenario("Torture (fill screen)", buildTorture, &atlas, &font, &renderer, vbuf, mvp);

        const buildArabic = struct { fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void { var y: f32 = HEIGHT - 30; for (0..12) |_| { _ = batch.addString(a, fo, ARABIC_TEXT, 10, y, 24, white); y -= 32; } } }.f;
        const buildDeva = struct { fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void { var y: f32 = HEIGHT - 30; for (0..12) |_| { _ = batch.addString(a, fo, DEVANAGARI_TEXT, 10, y, 24, white); y -= 32; } } }.f;
        runScenario("Arabic (12 lines)", buildArabic, &arabic_atlas, &arabic_font, &renderer, vbuf, mvp);
        runScenario("Devanagari (12 lines)", buildDeva, &deva_atlas, &deva_font, &renderer, vbuf, mvp);

        std.debug.print("\n", .{});
        const game_ui = [_]FontEntry{
            .{ .atlas = &atlas, .font = &font, .text = "Score: 12345  Level 7", .font_size = 18 },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 24 },
            .{ .atlas = &atlas, .font = &font, .text = "Health: 100%  Ammo: 42", .font_size = 16 },
        };
        runMultiFontScenario("Multi-font UI (3 fonts)", &game_ui, &renderer, vbuf, mvp);

        const chat = [_]FontEntry{
            .{ .atlas = &atlas, .font = &font, .text = "Alice: Hey, how's it going?", .font_size = 16 },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 16 },
            .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT, .font_size = 16 },
            .{ .atlas = &atlas, .font = &font, .text = "Charlie: Let's meet at the cafe", .font_size = 16 },
            .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT, .font_size = 16 },
            .{ .atlas = &atlas, .font = &font, .text = "Eve: Sounds good!", .font_size = 16 },
        };
        runMultiFontScenario("Multi-font chat (4 fonts)", &chat, &renderer, vbuf, mvp);

        var torture_entries: [24]FontEntry = undefined;
        const mixed = [_]struct { atlas: *const snail.Atlas, font: *const snail.Font, text: []const u8 }{
            .{ .atlas = &atlas, .font = &font, .text = SENTENCE },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT },
            .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT },
            .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT },
        };
        for (&torture_entries, 0..) |*te, i| {
            const src = mixed[i % mixed.len];
            te.* = .{ .atlas = src.atlas, .font = src.font, .text = src.text, .font_size = 16 };
        }
        runMultiFontScenario("Multi-font torture (4 fonts)", &torture_entries, &renderer, vbuf, mvp);

        std.debug.print(
            \\
            \\  ── Vector Rendering (OpenGL) ──
            \\  Scenario                          Shapes  static FPS (us)   dynamic FPS (us)
            \\
        , .{});
        runVectorScenario("Primitive showcase", buildVectorShowcase, &renderer, vector_buf);
        runVectorScenario("Primitive stress", buildVectorStress, &renderer, vector_buf);
    }

    // ── Vulkan rendering section (requires -Dvulkan=true) ──
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
        defer vulkan_platform.deinitOffscreen();

        const t_setup = nowNs();
        var font = try snail.Font.init(assets.noto_sans_regular);
        defer font.deinit();
        var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
        defer atlas.deinit();

        var arabic_font = try snail.Font.init(assets.noto_sans_arabic);
        defer arabic_font.deinit();
        var arabic_atlas = try snail.Atlas.init(allocator, &arabic_font, &.{});
        defer arabic_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(ARABIC_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try arabic_atlas.addGlyphsForText(ARABIC_TEXT); } else { _ = try arabic_atlas.addCodepoints(cp); } }

        var deva_font = try snail.Font.init(assets.noto_sans_devanagari);
        defer deva_font.deinit();
        var deva_atlas = try snail.Atlas.init(allocator, &deva_font, &.{});
        defer deva_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(DEVANAGARI_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try deva_atlas.addGlyphsForText(DEVANAGARI_TEXT); } else { _ = try deva_atlas.addCodepoints(cp); } }

        var thai_font = try snail.Font.init(assets.noto_sans_thai);
        defer thai_font.deinit();
        var thai_atlas = try snail.Atlas.init(allocator, &thai_font, &.{});
        defer thai_atlas.deinit();
        { var cps: [256]u32 = undefined; const cp = initCodepoints(THAI_TEXT, &cps);
          if (comptime build_options.enable_harfbuzz) { _ = try thai_atlas.addGlyphsForText(THAI_TEXT); } else { _ = try thai_atlas.addCodepoints(cp); } }

        var renderer = try snail.Renderer.initVulkan(vk_ctx);
        defer renderer.deinit();
        renderer.uploadAtlases(&[_]*const snail.Atlas{ &atlas, &arabic_atlas, &deva_atlas, &thai_atlas });
        const setup_us = usFrom(t_setup);

        const vbuf = try allocator.alloc(f32, 30000 * snail.FLOATS_PER_GLYPH);
        defer allocator.free(vbuf);
        const vector_buf = try allocator.alloc(f32, 4096 * snail.VECTOR_FLOATS_PER_PRIMITIVE);
        defer allocator.free(vector_buf);
        const mvp = snail.Mat4.ortho(0, WIDTH, 0, HEIGHT, -1, 1);

        std.debug.print(
            \\
            \\  ── Rendering (Vulkan) ──
            \\  Backend: Vulkan | HarfBuzz: {s} | {d}x{d} | {d} frames/test
            \\  Setup (4 fonts + atlases + texture array): {d:.0} us
            \\  Scenario                          Glyphs  static FPS (us)   dynamic FPS (us)
            \\
        , .{ hb_str, WIDTH, HEIGHT, FRAMES, setup_us });

        runScenarioVulkan("Game HUD (2 lines)", buildHud, &atlas, &font, &renderer, vbuf, mvp);
        runScenarioVulkan("Multi-size (6 sizes)", buildMultiSize, &atlas, &font, &renderer, vbuf, mvp);
        runScenarioVulkan("Body text (6 paragraphs)", buildParagraph, &atlas, &font, &renderer, vbuf, mvp);
        runScenarioVulkan("Torture (fill screen)", buildTorture, &atlas, &font, &renderer, vbuf, mvp);

        const buildArabic = struct { fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void { var y: f32 = HEIGHT - 30; for (0..12) |_| { _ = batch.addString(a, fo, ARABIC_TEXT, 10, y, 24, white); y -= 32; } } }.f;
        const buildDeva = struct { fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void { var y: f32 = HEIGHT - 30; for (0..12) |_| { _ = batch.addString(a, fo, DEVANAGARI_TEXT, 10, y, 24, white); y -= 32; } } }.f;
        runScenarioVulkan("Arabic (12 lines)", buildArabic, &arabic_atlas, &arabic_font, &renderer, vbuf, mvp);
        runScenarioVulkan("Devanagari (12 lines)", buildDeva, &deva_atlas, &deva_font, &renderer, vbuf, mvp);

        std.debug.print("\n", .{});
        const game_ui = [_]FontEntry{
            .{ .atlas = &atlas, .font = &font, .text = "Score: 12345  Level 7", .font_size = 18 },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 24 },
            .{ .atlas = &atlas, .font = &font, .text = "Health: 100%  Ammo: 42", .font_size = 16 },
        };
        runMultiFontScenarioVulkan("Multi-font UI (3 fonts)", &game_ui, &renderer, vbuf, mvp);

        const chat = [_]FontEntry{
            .{ .atlas = &atlas, .font = &font, .text = "Alice: Hey, how's it going?", .font_size = 16 },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 16 },
            .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT, .font_size = 16 },
            .{ .atlas = &atlas, .font = &font, .text = "Charlie: Let's meet at the cafe", .font_size = 16 },
            .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT, .font_size = 16 },
            .{ .atlas = &atlas, .font = &font, .text = "Eve: Sounds good!", .font_size = 16 },
        };
        runMultiFontScenarioVulkan("Multi-font chat (4 fonts)", &chat, &renderer, vbuf, mvp);

        var torture_entries: [24]FontEntry = undefined;
        const mixed = [_]struct { atlas: *const snail.Atlas, font: *const snail.Font, text: []const u8 }{
            .{ .atlas = &atlas, .font = &font, .text = SENTENCE },
            .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT },
            .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT },
            .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT },
        };
        for (&torture_entries, 0..) |*te, i| {
            const src = mixed[i % mixed.len];
            te.* = .{ .atlas = src.atlas, .font = src.font, .text = src.text, .font_size = 16 };
        }
        runMultiFontScenarioVulkan("Multi-font torture (4 fonts)", &torture_entries, &renderer, vbuf, mvp);

        std.debug.print(
            \\
            \\  ── Vector Rendering (Vulkan) ──
            \\  Scenario                          Shapes  static FPS (us)   dynamic FPS (us)
            \\
        , .{});
        runVectorScenarioVulkan("Primitive showcase", buildVectorShowcase, &renderer, vector_buf);
        runVectorScenarioVulkan("Primitive stress", buildVectorStress, &renderer, vector_buf);
    }

    std.debug.print(
        \\
        \\══════════════════════════════════════════════════════════════════════
        \\
    , .{});
}
