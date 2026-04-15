//! End-to-end rendering benchmark. Measures actual GPU frame time
//! including layout + upload + draw + glFinish.
//! Headless (invisible window + FBO). Answers: "how fast will this be?"

const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
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

    std.debug.print("  {s:<30} {d:>5} glyphs   static: {d:>8.0} FPS ({d:>6.1} us)   dynamic: {d:>8.0} FPS ({d:>6.1} us)\n", .{
        name, glyphs, static_fps, static_us, dynamic_fps, dynamic_us,
    });
}

const FontEntry = struct {
    atlas: *const snail.Atlas,
    font: *const snail.Font,
    text: []const u8,
    font_size: f32,
};

/// Multi-font scenario: tests both naive (per-line draw) and batched (group by atlas).
fn runMultiFontScenario(
    name: []const u8,
    font_sets: []const FontEntry,
    renderer: *snail.Renderer,
    vbuf: []f32,
    mvp: snail.Mat4,
) void {
    const white = [4]f32{ 1, 1, 1, 1 };

    var total_glyphs: usize = 0;
    for (font_sets) |fs| {
        var b = snail.Batch.init(vbuf);
        _ = b.addString(fs.atlas, fs.font, fs.text, 10, 400, fs.font_size, white);
        total_glyphs += b.glyphCount();
    }

    // Static: pre-built single batch
    var probe = snail.Batch.init(vbuf);
    {
        var y: f32 = HEIGHT - 30;
        for (font_sets) |fs| {
            _ = probe.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, white);
            y -= fs.font_size * 1.5;
        }
    }
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

    // Dynamic: rebuild single batch every frame
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

/// Single draw: all fonts in one batch (texture arrays).
fn drawSingleBatch(font_sets: []const FontEntry, renderer: *snail.Renderer, vbuf: []f32, mvp: snail.Mat4, color: [4]f32) void {
    var batch = snail.Batch.init(vbuf);
    var y: f32 = HEIGHT - 30;
    for (font_sets) |fs| {
        _ = batch.addString(fs.atlas, fs.font, fs.text, 10, y, fs.font_size, color);
        y -= fs.font_size * 1.5;
    }
    if (batch.glyphCount() > 0) renderer.draw(batch.slice(), mvp, WIDTH, HEIGHT);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    // Hidden window — try GL 4.4 first, fall back to 3.3
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
    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    // Upload deferred until all atlases are ready (see below)

    const vbuf = try allocator.alloc(f32, 30000 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const mvp = snail.Mat4.ortho(0, WIDTH, 0, HEIGHT, -1, 1);

    // ── Multi-script font setup (before texture array build) ──

    // Arabic
    var arabic_font = try snail.Font.init(assets.noto_sans_arabic);
    defer arabic_font.deinit();
    var arabic_atlas = try snail.Atlas.init(allocator, &arabic_font, &.{});
    defer arabic_atlas.deinit();
    {
        if (comptime build_options.enable_harfbuzz) {
            _ = try arabic_atlas.addGlyphsForText(ARABIC_TEXT);
        } else {
            var cps: [256]u32 = undefined;
            var n: usize = 0;
            const view = std.unicode.Utf8View.initUnchecked(ARABIC_TEXT);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (n >= cps.len) break;
                cps[n] = cp;
                n += 1;
            }
            _ = try arabic_atlas.addCodepoints(cps[0..n]);
        }
    }

    // Devanagari
    var deva_font = try snail.Font.init(assets.noto_sans_devanagari);
    defer deva_font.deinit();
    var deva_atlas = try snail.Atlas.init(allocator, &deva_font, &.{});
    defer deva_atlas.deinit();
    {
        if (comptime build_options.enable_harfbuzz) {
            _ = try deva_atlas.addGlyphsForText(DEVANAGARI_TEXT);
        } else {
            var cps: [256]u32 = undefined;
            var n: usize = 0;
            const view = std.unicode.Utf8View.initUnchecked(DEVANAGARI_TEXT);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (n >= cps.len) break;
                cps[n] = cp;
                n += 1;
            }
            _ = try deva_atlas.addCodepoints(cps[0..n]);
        }
    }

    // Thai
    var thai_font = try snail.Font.init(assets.noto_sans_thai);
    defer thai_font.deinit();
    var thai_atlas = try snail.Atlas.init(allocator, &thai_font, &.{});
    defer thai_atlas.deinit();
    {
        if (comptime build_options.enable_harfbuzz) {
            _ = try thai_atlas.addGlyphsForText(THAI_TEXT);
        } else {
            var cps: [256]u32 = undefined;
            var n: usize = 0;
            const view = std.unicode.Utf8View.initUnchecked(THAI_TEXT);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (n >= cps.len) break;
                cps[n] = cp;
                n += 1;
            }
            _ = try thai_atlas.addCodepoints(cps[0..n]);
        }
    }

    // Upload all atlases as texture array (single-draw multi-font)
    renderer.uploadAtlases(&[_]*const snail.Atlas{
        &atlas, &arabic_atlas, &deva_atlas, &thai_atlas,
    });
    const setup_us = @as(f64, @floatFromInt(nowNs() - t_setup)) / 1000.0;

    const hb_str = if (build_options.enable_harfbuzz) "ON" else "OFF";
    const pipeline = @import("render/pipeline.zig");
    std.debug.print(
        \\
        \\=== snail end-to-end rendering ===
        \\  Backend: {s} | HarfBuzz: {s} | {d}x{d} | {d} frames/test
        \\  Setup (4 fonts + atlases + texture array): {d:.0} us
        \\
        \\  "static" = pre-built vertex buffer, draw only (game HUD, menus)
        \\  "dynamic" = rebuild vertices + draw every frame (chat, editor, debug)
        \\
    , .{ pipeline.getBackendName(), hb_str, WIDTH, HEIGHT, FRAMES, setup_us });

    // ── Latin scenarios ──
    std.debug.print("  --- Latin (built-in shaper{s}) ---\n", .{
        if (build_options.enable_harfbuzz) " + HarfBuzz" else "",
    });
    runScenario("Game HUD (2 lines)", buildHud, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Multi-size (6 sizes)", buildMultiSize, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Body text (6 paragraphs)", buildParagraph, &atlas, &font, &renderer, vbuf, mvp);
    runScenario("Torture (fill screen)", buildTorture, &atlas, &font, &renderer, vbuf, mvp);

    std.debug.print("\n  --- Multi-script ---\n", .{});

    // Single-script benchmarks (Arabic repeated to fill lines)
    const buildArabic = struct {
        fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void {
            var y: f32 = HEIGHT - 30;
            for (0..12) |_| {
                _ = batch.addString(a, fo, ARABIC_TEXT, 10, y, 24, .{ 1, 1, 1, 1 });
                y -= 32;
            }
        }
    }.f;

    const buildDevanagari = struct {
        fn f(batch: *snail.Batch, a: *const snail.Atlas, fo: *const snail.Font) void {
            var y: f32 = HEIGHT - 30;
            for (0..12) |_| {
                _ = batch.addString(a, fo, DEVANAGARI_TEXT, 10, y, 24, .{ 1, 1, 1, 1 });
                y -= 32;
            }
        }
    }.f;

    runScenario("Arabic (12 lines)", buildArabic, &arabic_atlas, &arabic_font, &renderer, vbuf, mvp);
    runScenario("Devanagari (12 lines)", buildDevanagari, &deva_atlas, &deva_font, &renderer, vbuf, mvp);

    // Multi-font: simulate game UI with mixed scripts
    std.debug.print("\n  --- Multi-font (atlas switching) ---\n", .{});

    const game_ui_fonts = [_]FontEntry{
        .{ .atlas = &atlas, .font = &font, .text = "Score: 12345  Level 7", .font_size = 18 },
        .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 24 },
        .{ .atlas = &atlas, .font = &font, .text = "Health: 100%  Ammo: 42", .font_size = 16 },
    };
    runMultiFontScenario("Game UI (3 fonts)", &game_ui_fonts, &renderer, vbuf, mvp);

    const chat_fonts = [_]FontEntry{
        .{ .atlas = &atlas, .font = &font, .text = "Alice: Hey, how's it going?", .font_size = 16 },
        .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT, .font_size = 16 },
        .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT, .font_size = 16 },
        .{ .atlas = &atlas, .font = &font, .text = "Charlie: Let's meet at the cafe", .font_size = 16 },
        .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT, .font_size = 16 },
        .{ .atlas = &atlas, .font = &font, .text = "Eve: Sounds good!", .font_size = 16 },
    };
    runMultiFontScenario("Chat (6 msgs, 4 fonts)", &chat_fonts, &renderer, vbuf, mvp);

    // Torture: fill screen with alternating scripts
    var torture_fonts: [24]FontEntry = undefined;
    const mixed_texts = [_]struct { atlas: *const snail.Atlas, font: *const snail.Font, text: []const u8 }{
        .{ .atlas = &atlas, .font = &font, .text = SENTENCE },
        .{ .atlas = &arabic_atlas, .font = &arabic_font, .text = ARABIC_TEXT },
        .{ .atlas = &deva_atlas, .font = &deva_font, .text = DEVANAGARI_TEXT },
        .{ .atlas = &thai_atlas, .font = &thai_font, .text = THAI_TEXT },
    };
    for (&torture_fonts, 0..) |*tf, i| {
        const src = mixed_texts[i % mixed_texts.len];
        tf.* = .{ .atlas = src.atlas, .font = src.font, .text = src.text, .font_size = 16 };
    }
    runMultiFontScenario("Torture (24 lines, 4 fonts)", &torture_fonts, &renderer, vbuf, mvp);

    std.debug.print("\n=========================================================\n", .{});
}
