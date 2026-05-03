//! End-to-end rendering benchmark. Measures actual GPU frame time
//! including layout + upload + draw + finish.
//! Headless: GL uses an offscreen EGL pbuffer + FBO; Vulkan renders to a VkImage (no swapchain).
//! Answers: "how fast will this be?"

const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const egl_offscreen = @import("render/egl_offscreen.zig");
const vulkan_platform = if (build_options.enable_vulkan) @import("render/vulkan_platform.zig") else undefined;
const gl = @import("render/gl.zig").gl;
const assets = @import("assets");

const WIDTH = 1280;
const HEIGHT = 720;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;
const BENCH_TIME_MULTIPLIER = 10;
const WARMUP = 100 * BENCH_TIME_MULTIPLIER;
const FRAMES = 2000 * BENCH_TIME_MULTIPLIER;

const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

// Arabic: "In the name of God, the Most Gracious, the Most Merciful"
const ARABIC_TEXT = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x85\xd9\x86 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x8a\xd9\x85";
// Devanagari: "Hello World"
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0";
// Thai: "Hello"
const THAI_TEXT = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a";

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn buildHud(batch: *snail.TextBatch, fonts: *snail.Fonts) void {
    _ = fonts.addText(batch, .{}, "Score: 12345  FPS: 60  Level 7", 10, 20, 18, .{ 1, 1, 1, 1 }) catch {};
    _ = fonts.addText(batch, .{}, "Health: 100%  Ammo: 42/120", 10, 44, 18, .{ 0.8, 0.2, 0.2, 1 }) catch {};
}

fn buildMultiSize(batch: *snail.TextBatch, fonts: *snail.Fonts) void {
    const white = [4]f32{ 1, 1, 1, 1 };
    var y: f32 = 30;
    for ([_]f32{ 12, 18, 24, 36, 48, 72 }) |sz| {
        _ = fonts.addText(batch, .{}, SENTENCE, 10, y, sz, white) catch {};
        y += sz * 1.4;
    }
}

fn buildParagraph(batch: *snail.TextBatch, fonts: *snail.Fonts) void {
    const gray = [4]f32{ 0.9, 0.9, 0.9, 1 };
    var y: f32 = 30;
    for (0..6) |_| {
        _ = fonts.addText(batch, .{}, PARAGRAPH, 10, y, 16, gray) catch {};
        y += 22;
    }
}

fn buildTorture(batch: *snail.TextBatch, fonts: *snail.Fonts) void {
    const white = [4]f32{ 1, 1, 1, 1 };
    var y: f32 = 10;
    var si: usize = 0;
    const sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
    while (y < HEIGHT) {
        const sz = sizes[si % sizes.len];
        _ = fonts.addText(batch, .{}, PARAGRAPH, 5, y, sz, white) catch {};
        y += sz * 1.2;
        si += 1;
    }
}

// ── GL scenario runners ──

fn runScenario(
    name: []const u8,
    buildFn: *const fn (*snail.TextBatch, *snail.Fonts) void,
    fonts: *snail.Fonts,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    var probe = snail.TextBatch.init(vbuf);
    buildFn(&probe, fonts);
    const glyphs = probe.glyphCount();

    const static_slice = probe.slice();
    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();

    const t_static = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const static_ns = nowNs() - t_static;
    const static_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(static_ns)) / 1e9);
    const static_us = @as(f64, @floatFromInt(static_ns)) / 1000.0 / FRAMES;

    for (0..WARMUP) |_| {
        var b = snail.TextBatch.init(vbuf);
        buildFn(&b, fonts);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(b.slice(), mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();

    const t_dynamic = nowNs();
    for (0..FRAMES) |_| {
        var b = snail.TextBatch.init(vbuf);
        buildFn(&b, fonts);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(b.slice(), mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const dynamic_ns = nowNs() - t_dynamic;
    const dynamic_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(dynamic_ns)) / 1e9);
    const dynamic_us = @as(f64, @floatFromInt(dynamic_ns)) / 1000.0 / FRAMES;

    std.debug.print("  {s:<30} {d:>5} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

const MultiFontEntry = struct {
    fonts: *snail.Fonts,
    text: []const u8,
    font_size: f32,
};

fn runMultiFontScenario(
    name: []const u8,
    font_sets: []const MultiFontEntry,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    const white = [4]f32{ 1, 1, 1, 1 };

    var total_glyphs: usize = 0;
    for (font_sets) |fs| {
        var b = snail.TextBatch.init(vbuf);
        _ = fs.fonts.addText(&b, .{}, fs.text, 10, 400, fs.font_size, white) catch {};
        total_glyphs += b.glyphCount();
    }

    var probe = snail.TextBatch.init(vbuf);
    {
        var y: f32 = 30;
        for (font_sets) |fs| {
            _ = fs.fonts.addText(&probe, .{}, fs.text, 10, y, fs.font_size, white) catch {};
            y += fs.font_size * 1.5;
        }
    }
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const t_static = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
    }
    gl.glFinish();
    const static_ns = nowNs() - t_static;
    const static_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(static_ns)) / 1e9);
    const static_us = @as(f64, @floatFromInt(static_ns)) / 1000.0 / FRAMES;

    for (0..WARMUP) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        drawSingleBatch(font_sets, renderer, vbuf, mvp, white);
    }
    gl.glFinish();
    const t_dynamic = nowNs();
    for (0..FRAMES) |_| {
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        drawSingleBatch(font_sets, renderer, vbuf, mvp, white);
    }
    gl.glFinish();
    const dynamic_ns = nowNs() - t_dynamic;
    const dynamic_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(dynamic_ns)) / 1e9);
    const dynamic_us = @as(f64, @floatFromInt(dynamic_ns)) / 1000.0 / FRAMES;

    std.debug.print("  {s:<30} {d:>5} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, total_glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

fn drawSingleBatch(font_sets: []const MultiFontEntry, renderer: *snail.Renderer, vbuf: []f32, mvp: snail.Mat4, color: [4]f32) void {
    var batch = snail.TextBatch.init(vbuf);
    var y: f32 = 30;
    for (font_sets) |fs| {
        _ = fs.fonts.addText(&batch, .{}, fs.text, 10, y, fs.font_size, color) catch {};
        y += fs.font_size * 1.5;
    }
    if (batch.glyphCount() > 0) renderer.drawText(batch.slice(), mvp, WIDTH, HEIGHT);
}

// ── Vulkan scenario runners (conditional on -Dvulkan=true) ──

const runScenarioVulkan = if (build_options.enable_vulkan) runScenarioVulkanImpl else @compileError("vulkan disabled");
const runMultiFontScenarioVulkan = if (build_options.enable_vulkan) runMultiFontScenarioVulkanImpl else @compileError("vulkan disabled");

fn runScenarioVulkanImpl(
    name: []const u8,
    buildFn: *const fn (*snail.TextBatch, *snail.Fonts) void,
    fonts: *snail.Fonts,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    var probe = snail.TextBatch.init(vbuf);
    buildFn(&probe, fonts);
    const glyphs = probe.glyphCount();
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();

    const t_static = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const static_ns = nowNs() - t_static;
    const static_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(static_ns)) / 1e9);
    const static_us = @as(f64, @floatFromInt(static_ns)) / 1000.0 / FRAMES;

    for (0..WARMUP) |_| {
        var b = snail.TextBatch.init(vbuf);
        buildFn(&b, fonts);
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();

    const t_dynamic = nowNs();
    for (0..FRAMES) |_| {
        var b = snail.TextBatch.init(vbuf);
        buildFn(&b, fonts);
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(b.slice(), mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const dynamic_ns = nowNs() - t_dynamic;
    const dynamic_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(dynamic_ns)) / 1e9);
    const dynamic_us = @as(f64, @floatFromInt(dynamic_ns)) / 1000.0 / FRAMES;

    std.debug.print("  {s:<30} {d:>5} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

fn runMultiFontScenarioVulkanImpl(
    name: []const u8,
    font_sets: []const MultiFontEntry,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    const white = [4]f32{ 1, 1, 1, 1 };

    var total_glyphs: usize = 0;
    for (font_sets) |fs| {
        var b = snail.TextBatch.init(vbuf);
        _ = fs.fonts.addText(&b, .{}, fs.text, 10, 400, fs.font_size, white) catch {};
        total_glyphs += b.glyphCount();
    }

    var probe = snail.TextBatch.init(vbuf);
    {
        var y: f32 = 30;
        for (font_sets) |fs| {
            _ = fs.fonts.addText(&probe, .{}, fs.text, 10, y, fs.font_size, white) catch {};
            y += fs.font_size * 1.5;
        }
    }
    const static_slice = probe.slice();

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_static = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            renderer.drawText(static_slice, mvp, WIDTH, HEIGHT);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const static_ns = nowNs() - t_static;
    const static_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(static_ns)) / 1e9);
    const static_us = @as(f64, @floatFromInt(static_ns)) / 1000.0 / FRAMES;

    for (0..WARMUP) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            drawSingleBatchVulkan(font_sets, renderer, vbuf, mvp, white);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const t_dynamic = nowNs();
    for (0..FRAMES) |_| {
        {
            const cmd = vulkan_platform.beginFrameOffscreen();
            renderer.setCommandBuffer(cmd);
            drawSingleBatchVulkan(font_sets, renderer, vbuf, mvp, white);
            vulkan_platform.endFrameOffscreen();
        }
    }
    vulkan_platform.queueWaitIdle();
    const dynamic_ns = nowNs() - t_dynamic;
    const dynamic_fps = @as(f64, FRAMES) / (@as(f64, @floatFromInt(dynamic_ns)) / 1e9);
    const dynamic_us = @as(f64, @floatFromInt(dynamic_ns)) / 1000.0 / FRAMES;

    std.debug.print("  {s:<30} {d:>5} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, total_glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

fn drawSingleBatchVulkan(font_sets: []const MultiFontEntry, renderer: *snail.Renderer, vbuf: []f32, mvp: snail.Mat4, color: [4]f32) void {
    var batch = snail.TextBatch.init(vbuf);
    var y: f32 = 30;
    for (font_sets) |fs| {
        _ = fs.fonts.addText(&batch, .{}, fs.text, 10, y, fs.font_size, color) catch {};
        y += fs.font_size * 1.5;
    }
    if (batch.glyphCount() > 0) renderer.drawText(batch.slice(), mvp, WIDTH, HEIGHT);
}

fn initFonts(allocator: std.mem.Allocator, specs: []const snail.Fonts.FaceSpec) !snail.Fonts {
    return snail.Fonts.init(allocator, specs);
}

fn ensureAllText(fonts: *snail.Fonts, texts: []const []const u8) !void {
    for (texts) |text| {
        if (try fonts.ensureText(.{}, text)) |new_fonts| {
            fonts.deinit();
            fonts.* = new_fonts;
        }
    }
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const hb_str = if (build_options.enable_harfbuzz) "ON" else "OFF";

    // ── OpenGL section ──
    {
        var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
        defer gl_ctx.deinit();

        var fbo: gl.GLuint = 0;
        var fbo_tex: gl.GLuint = 0;
        gl.glGenFramebuffers(1, &fbo);
        gl.glGenTextures(1, &fbo_tex);
        gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_tex, 0);
        gl.glViewport(0, 0, WIDTH, HEIGHT);
        defer gl.glDeleteFramebuffers(1, &fbo);
        defer gl.glDeleteTextures(1, &fbo_tex);

        const t_setup = nowNs();
        var fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_regular },
        });
        defer fonts.deinit();
        try ensureAllText(&fonts, &.{ SENTENCE, PARAGRAPH });

        var renderer = try snail.Renderer.init();
        defer renderer.deinit();

        const vbuf = try allocator.alloc(f32, 30000 * snail.TEXT_FLOATS_PER_GLYPH);
        defer allocator.free(vbuf);
        const mvp = snail.Mat4.ortho(0, WIDTH, HEIGHT, 0, -1, 1);

        var arabic_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_arabic },
        });
        defer arabic_fonts.deinit();
        try ensureAllText(&arabic_fonts, &.{ARABIC_TEXT});

        var deva_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_devanagari },
        });
        defer deva_fonts.deinit();
        try ensureAllText(&deva_fonts, &.{DEVANAGARI_TEXT});

        var thai_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_thai },
        });
        defer thai_fonts.deinit();
        try ensureAllText(&thai_fonts, &.{THAI_TEXT});

        const setup_us = @as(f64, @floatFromInt(nowNs() - t_setup)) / 1000.0;

        const gl_pipeline = @import("render/pipeline.zig");
        std.debug.print(
            \\
            \\=== snail end-to-end rendering ===
            \\  Backend: {s} | HarfBuzz: {s} | {d}x{d} | {d} warmup + {d} measured frames/test
            \\  Setup (4 fonts + atlases): {d:.0} us
            \\
            \\  "static" = pre-built vertex buffer, draw only (game HUD, menus)
            \\  "dynamic" = rebuild vertices + draw every frame (chat, editor, debug)
            \\
        , .{ gl_pipeline.getBackendName(), hb_str, WIDTH, HEIGHT, WARMUP, FRAMES, setup_us });

        std.debug.print("  --- Latin (built-in shaper{s}) ---\n", .{
            if (build_options.enable_harfbuzz) " + HarfBuzz" else "",
        });
        runScenario("Game HUD (2 lines)", buildHud, &fonts, &renderer, vbuf, mvp);
        runScenario("Multi-size (6 sizes)", buildMultiSize, &fonts, &renderer, vbuf, mvp);
        runScenario("Body text (6 paragraphs)", buildParagraph, &fonts, &renderer, vbuf, mvp);
        runScenario("Torture (fill screen)", buildTorture, &fonts, &renderer, vbuf, mvp);

        std.debug.print("\n  --- Multi-script ---\n", .{});

        const buildArabic = struct {
            fn f(batch: *snail.TextBatch, fo: *snail.Fonts) void {
                var y: f32 = 30;
                for (0..12) |_| {
                    _ = fo.addText(batch, .{}, ARABIC_TEXT, 10, y, 24, .{ 1, 1, 1, 1 }) catch {};
                    y += 32;
                }
            }
        }.f;
        const buildDevanagari = struct {
            fn f(batch: *snail.TextBatch, fo: *snail.Fonts) void {
                var y: f32 = 30;
                for (0..12) |_| {
                    _ = fo.addText(batch, .{}, DEVANAGARI_TEXT, 10, y, 24, .{ 1, 1, 1, 1 }) catch {};
                    y += 32;
                }
            }
        }.f;

        runScenario("Arabic (12 lines)", buildArabic, &arabic_fonts, &renderer, vbuf, mvp);
        runScenario("Devanagari (12 lines)", buildDevanagari, &deva_fonts, &renderer, vbuf, mvp);

        std.debug.print("\n  --- Multi-font (atlas switching) ---\n", .{});

        const game_ui_fonts = [_]MultiFontEntry{
            .{ .fonts = &fonts, .text = "Score: 12345  Level 7", .font_size = 18 },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT, .font_size = 24 },
            .{ .fonts = &fonts, .text = "Health: 100%  Ammo: 42", .font_size = 16 },
        };
        runMultiFontScenario("Game UI (3 fonts)", &game_ui_fonts, &renderer, vbuf, mvp);

        const chat_fonts = [_]MultiFontEntry{
            .{ .fonts = &fonts, .text = "Alice: Hey, how's it going?", .font_size = 16 },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT, .font_size = 16 },
            .{ .fonts = &deva_fonts, .text = DEVANAGARI_TEXT, .font_size = 16 },
            .{ .fonts = &fonts, .text = "Charlie: Let's meet at the cafe", .font_size = 16 },
            .{ .fonts = &thai_fonts, .text = THAI_TEXT, .font_size = 16 },
            .{ .fonts = &fonts, .text = "Eve: Sounds good!", .font_size = 16 },
        };
        runMultiFontScenario("Chat (6 msgs, 4 fonts)", &chat_fonts, &renderer, vbuf, mvp);

        var torture_fonts: [24]MultiFontEntry = undefined;
        const mixed_texts = [_]struct { fonts: *snail.Fonts, text: []const u8 }{
            .{ .fonts = &fonts, .text = SENTENCE },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT },
            .{ .fonts = &deva_fonts, .text = DEVANAGARI_TEXT },
            .{ .fonts = &thai_fonts, .text = THAI_TEXT },
        };
        for (&torture_fonts, 0..) |*tf, i| {
            const src = mixed_texts[i % mixed_texts.len];
            tf.* = .{ .fonts = src.fonts, .text = src.text, .font_size = 16 };
        }
        runMultiFontScenario("Torture (24 lines, 4 fonts)", &torture_fonts, &renderer, vbuf, mvp);

        std.debug.print("\n=========================================================\n", .{});
    }

    // ── Vulkan section (requires -Dvulkan=true) ──
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
        defer vulkan_platform.deinitOffscreen();

        const t_setup = nowNs();
        var fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_regular },
        });
        defer fonts.deinit();
        try ensureAllText(&fonts, &.{ SENTENCE, PARAGRAPH });

        var renderer = try snail.Renderer.initVulkan(vk_ctx);
        defer renderer.deinit();

        const vbuf = try allocator.alloc(f32, 30000 * snail.TEXT_FLOATS_PER_GLYPH);
        defer allocator.free(vbuf);
        const mvp = snail.Mat4.ortho(0, WIDTH, HEIGHT, 0, -1, 1);

        var arabic_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_arabic },
        });
        defer arabic_fonts.deinit();
        try ensureAllText(&arabic_fonts, &.{ARABIC_TEXT});

        var deva_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_devanagari },
        });
        defer deva_fonts.deinit();
        try ensureAllText(&deva_fonts, &.{DEVANAGARI_TEXT});

        var thai_fonts = try initFonts(allocator, &.{
            .{ .data = assets.noto_sans_thai },
        });
        defer thai_fonts.deinit();
        try ensureAllText(&thai_fonts, &.{THAI_TEXT});

        const setup_us = @as(f64, @floatFromInt(nowNs() - t_setup)) / 1000.0;

        std.debug.print(
            \\
            \\=== snail end-to-end rendering ===
            \\  Backend: Vulkan | HarfBuzz: {s} | {d}x{d} | {d} warmup + {d} measured frames/test
            \\  Setup (4 fonts + atlases): {d:.0} us
            \\
            \\  "static" = pre-built vertex buffer, draw only (game HUD, menus)
            \\  "dynamic" = rebuild vertices + draw every frame (chat, editor, debug)
            \\
        , .{ hb_str, WIDTH, HEIGHT, WARMUP, FRAMES, setup_us });

        std.debug.print("  --- Latin (built-in shaper{s}) ---\n", .{
            if (build_options.enable_harfbuzz) " + HarfBuzz" else "",
        });
        runScenarioVulkan("Game HUD (2 lines)", buildHud, &fonts, &renderer, vbuf, mvp);
        runScenarioVulkan("Multi-size (6 sizes)", buildMultiSize, &fonts, &renderer, vbuf, mvp);
        runScenarioVulkan("Body text (6 paragraphs)", buildParagraph, &fonts, &renderer, vbuf, mvp);
        runScenarioVulkan("Torture (fill screen)", buildTorture, &fonts, &renderer, vbuf, mvp);

        std.debug.print("\n  --- Multi-script ---\n", .{});

        const buildArabic = struct {
            fn f(batch: *snail.TextBatch, fo: *snail.Fonts) void {
                var y: f32 = 30;
                for (0..12) |_| {
                    _ = fo.addText(batch, .{}, ARABIC_TEXT, 10, y, 24, .{ 1, 1, 1, 1 }) catch {};
                    y += 32;
                }
            }
        }.f;
        const buildDevanagari = struct {
            fn f(batch: *snail.TextBatch, fo: *snail.Fonts) void {
                var y: f32 = 30;
                for (0..12) |_| {
                    _ = fo.addText(batch, .{}, DEVANAGARI_TEXT, 10, y, 24, .{ 1, 1, 1, 1 }) catch {};
                    y += 32;
                }
            }
        }.f;

        runScenarioVulkan("Arabic (12 lines)", buildArabic, &arabic_fonts, &renderer, vbuf, mvp);
        runScenarioVulkan("Devanagari (12 lines)", buildDevanagari, &deva_fonts, &renderer, vbuf, mvp);

        std.debug.print("\n  --- Multi-font (atlas switching) ---\n", .{});

        const game_ui_fonts = [_]MultiFontEntry{
            .{ .fonts = &fonts, .text = "Score: 12345  Level 7", .font_size = 18 },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT, .font_size = 24 },
            .{ .fonts = &fonts, .text = "Health: 100%  Ammo: 42", .font_size = 16 },
        };
        runMultiFontScenarioVulkan("Game UI (3 fonts)", &game_ui_fonts, &renderer, vbuf, mvp);

        const chat_fonts = [_]MultiFontEntry{
            .{ .fonts = &fonts, .text = "Alice: Hey, how's it going?", .font_size = 16 },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT, .font_size = 16 },
            .{ .fonts = &deva_fonts, .text = DEVANAGARI_TEXT, .font_size = 16 },
            .{ .fonts = &fonts, .text = "Charlie: Let's meet at the cafe", .font_size = 16 },
            .{ .fonts = &thai_fonts, .text = THAI_TEXT, .font_size = 16 },
            .{ .fonts = &fonts, .text = "Eve: Sounds good!", .font_size = 16 },
        };
        runMultiFontScenarioVulkan("Chat (6 msgs, 4 fonts)", &chat_fonts, &renderer, vbuf, mvp);

        var torture_fonts: [24]MultiFontEntry = undefined;
        const mixed_texts = [_]struct { fonts: *snail.Fonts, text: []const u8 }{
            .{ .fonts = &fonts, .text = SENTENCE },
            .{ .fonts = &arabic_fonts, .text = ARABIC_TEXT },
            .{ .fonts = &deva_fonts, .text = DEVANAGARI_TEXT },
            .{ .fonts = &thai_fonts, .text = THAI_TEXT },
        };
        for (&torture_fonts, 0..) |*tf, i| {
            const src = mixed_texts[i % mixed_texts.len];
            tf.* = .{ .fonts = src.fonts, .text = src.text, .font_size = 16 };
        }
        runMultiFontScenarioVulkan("Torture (24 lines, 4 fonts)", &torture_fonts, &renderer, vbuf, mvp);

        std.debug.print("\n=========================================================\n", .{});
    }
}
