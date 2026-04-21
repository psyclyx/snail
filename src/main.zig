const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const assets = @import("assets");
const screenshot = @import("render/screenshot.zig");
const subpixel_detect = @import("render/subpixel_detect.zig");

// Backend-specific platform
const use_vulkan = build_options.enable_vulkan;
const platform = if (use_vulkan) @import("render/vulkan_platform.zig") else @import("render/platform.zig");
const gl = if (use_vulkan) struct {} else @import("render/platform.zig").gl;

const ScriptFont = struct {
    font: snail.Font,
    atlas: snail.Atlas,

    fn init(allocator: std.mem.Allocator, data: []const u8, sample_text: []const u8) !ScriptFont {
        var font = try snail.Font.init(data);
        var atlas = try snail.Atlas.init(allocator, &font, &.{});

        // Use HarfBuzz to discover glyphs from sample text when available
        if (comptime build_options.enable_harfbuzz) {
            _ = snail.replaceAtlas(&atlas, try atlas.extendGlyphsForText(sample_text));
        } else {
            // Fallback: add codepoints directly from UTF-8
            var cps: [512]u32 = undefined;
            var n: usize = 0;
            const view = std.unicode.Utf8View.initUnchecked(sample_text);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (n >= cps.len) break;
                cps[n] = cp;
                n += 1;
            }
            _ = snail.replaceAtlas(&atlas, try atlas.extendCodepoints(cps[0..n]));
        }
        return .{ .font = font, .atlas = atlas };
    }

    fn deinit(self: *ScriptFont) void {
        self.atlas.deinit();
        self.font.deinit();
    }
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

fn buildPrimitiveShowcase(batch: *snail.VectorBatch, w: f32, h: f32) void {
    const left_panel_w = w * 0.47;
    const right_panel_x = w * 0.5;
    const right_panel_w = w - right_panel_x - 24;

    addRoundedRect(batch, .{ .x = 18, .y = 18, .w = left_panel_w, .h = h - 96 }, .{ 0.08, 0.09, 0.11, 0.88 }, .{ 0.22, 0.24, 0.28, 1 }, 1.5, 24);
    addRoundedRect(batch, .{ .x = right_panel_x, .y = 18, .w = right_panel_w, .h = h - 96 }, .{ 0.07, 0.08, 0.1, 0.82 }, .{ 0.18, 0.2, 0.24, 1 }, 1.5, 24);

    _ = batch.addEllipse(
        .{ .x = right_panel_x + right_panel_w - 220, .y = 54, .w = 180, .h = 180 },
        .{ 0.28, 0.72, 0.92, 0.16 },
        .{ 0.28, 0.72, 0.92, 0.7 },
        2,
    );
    _ = batch.addEllipse(
        .{ .x = right_panel_x + right_panel_w - 160, .y = 94, .w = 96, .h = 96 },
        .{ 0.95, 0.72, 0.24, 0.22 },
        .{ 0.95, 0.72, 0.24, 0.82 },
        1.5,
    );

    addRoundedRect(batch, .{ .x = 36, .y = 44, .w = 148, .h = 28 }, .{ 0.18, 0.46, 0.82, 0.22 }, .{ 0.18, 0.46, 0.82, 0.9 }, 1.5, 14);
    addRoundedRect(batch, .{ .x = 36, .y = 84, .w = 220, .h = 14 }, .{ 0.86, 0.91, 0.96, 0.08 }, .{ 0.86, 0.91, 0.96, 0.3 }, 1, 7);

    addRoundedRect(
        batch,
        .{ .x = right_panel_x + 24, .y = h - 156, .w = right_panel_w - 48, .h = 92 },
        .{ 0.1, 0.12, 0.15, 0.9 },
        .{ 0.3, 0.33, 0.4, 1 },
        1.5,
        20,
    );
    addRoundedRect(
        batch,
        .{ .x = right_panel_x + 42, .y = h - 132, .w = right_panel_w * 0.42, .h = 18 },
        .{ 0.28, 0.72, 0.92, 0.18 },
        .{ 0.28, 0.72, 0.92, 0.85 },
        1,
        9,
    );
    addRoundedRect(
        batch,
        .{ .x = right_panel_x + 42, .y = h - 98, .w = right_panel_w * 0.3, .h = 18 },
        .{ 0.96, 0.72, 0.28, 0.16 },
        .{ 0.96, 0.72, 0.28, 0.82 },
        1,
        9,
    );
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    if (use_vulkan) {
        const vk_ctx = try platform.init(1280, 720, "snail");
        defer platform.deinit();
        return mainLoop(allocator, vk_ctx);
    } else {
        try platform.init(1280, 720, "snail");
        defer platform.deinit();
        return mainLoop(allocator, {});
    }
}

fn mainLoop(allocator: std.mem.Allocator, vk_ctx: anytype) !void {

    // Latin font (primary)
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();

    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    // Script fonts
    const arabic_text = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x85\xd9\x86 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x8a\xd9\x85"; // بسم الله الرحمن الرحيم
    const devanagari_text = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0"; // नमस्ते संसार
    const mongolian_text = "\xe1\xa0\xae\xe1\xa0\xa4\xe1\xa0\xa9\xe1\xa0\xa0\xe1\xa0\xa4\xe1\xa0\xaf"; // ᠮᠤᠩᠠᠤᠯ
    const thai_text = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a"; // สวัสดีครับ
    const emoji_text = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x89\xf0\x9f\x8c\x88\xf0\x9f\x98\x80\xf0\x9f\x94\xa5"; // ✨🌍🎨🚀🐉🌈😀🔥

    var arabic = try ScriptFont.init(allocator, assets.noto_sans_arabic, arabic_text);
    defer arabic.deinit();
    var devanagari = try ScriptFont.init(allocator, assets.noto_sans_devanagari, devanagari_text);
    defer devanagari.deinit();
    var mongolian = try ScriptFont.init(allocator, assets.noto_sans_mongolian, mongolian_text);
    defer mongolian.deinit();
    var thai = try ScriptFont.init(allocator, assets.noto_sans_thai, thai_text);
    defer thai.deinit();
    var emoji = try ScriptFont.init(allocator, assets.twemoji_mozilla, emoji_text);
    defer emoji.deinit();

    var renderer = if (use_vulkan)
        try snail.Renderer.initVulkan(vk_ctx)
    else
        try snail.Renderer.init();
    defer renderer.deinit();

    // Detect system subpixel order and apply, accounting for monitor rotation.
    const sys_order = subpixel_detect.detect();
    const initial_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    renderer.setSubpixelOrder(initial_order);

    // Upload all atlases as texture array (enables single-draw multi-font rendering)
    var atlas_views: [6]snail.AtlasView = undefined;
    renderer.uploadAtlases(&[_]*const snail.Atlas{
        &atlas,
        &arabic.atlas,
        &devanagari.atlas,
        &mongolian.atlas,
        &thai.atlas,
        &emoji.atlas,
    }, &atlas_views);
    const atlas_view = &atlas_views[0];
    const arabic_view = &atlas_views[1];
    const devanagari_view = &atlas_views[2];
    const mongolian_view = &atlas_views[3];
    const thai_view = &atlas_views[4];
    const emoji_view = &atlas_views[5];

    // Vertex buffer: enough for ~10000 glyphs
    const buf_size = 10000 * snail.FLOATS_PER_GLYPH;
    const vbuf = try allocator.alloc(f32, buf_size);
    defer allocator.free(vbuf);
    const shape_buf = try allocator.alloc(f32, 256 * snail.VECTOR_FLOATS_PER_PRIMITIVE);
    defer allocator.free(shape_buf);

    var angle: f32 = 0;
    var zoom: f32 = 1.0;
    var rotate = false;
    var stress_test = false;
    var last_time = platform.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0;

    std.debug.print("snail \xe2\x80\x94 GPU B\xc3\xa9zier font rendering\n", .{});
    std.debug.print("{} glyphs (Latin), Backend: {s}, HarfBuzz: {s}\n", .{
        atlas.glyph_map.count(),
        renderer.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    std.debug.print("Subpixel order: {s}\n", .{renderer.subpixelOrder().name()});
    std.debug.print("Keys: Z/X zoom, R rotate, S stress, L subpixel order, Esc quit\n", .{});

    while (!platform.shouldClose()) {
        const now = platform.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        fps_timer += dt;
        fps_frames += 1;
        if (fps_timer >= 1.0) {
            fps_display = @as(f32, @floatFromInt(fps_frames)) / @as(f32, @floatCast(fps_timer));
            fps_timer = 0;
            fps_frames = 0;
        }

        const KEY_R = if (use_vulkan) platform.GLFW_KEY_R else platform.c.GLFW_KEY_R;
        const KEY_S = if (use_vulkan) platform.GLFW_KEY_S else platform.c.GLFW_KEY_S;
        const KEY_L = if (use_vulkan) platform.GLFW_KEY_L else platform.c.GLFW_KEY_L;
        const KEY_Z = if (use_vulkan) platform.GLFW_KEY_Z else platform.c.GLFW_KEY_Z;
        const KEY_X = if (use_vulkan) platform.GLFW_KEY_X else platform.c.GLFW_KEY_X;

        // Re-detect subpixel order when the window moves to a different monitor.
        if (platform.consumeMonitorChanged()) {
            const order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
            if (order != renderer.subpixelOrder()) {
                renderer.setSubpixelOrder(order);
                std.debug.print("Monitor change: subpixel order -> {s}\n", .{order.name()});
            }
        }

        if (platform.isKeyPressed(KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(KEY_S)) stress_test = !stress_test;
        if (platform.isKeyPressed(KEY_L)) {
            // Cycle through all orders so you can manually verify each one.
            const next: snail.SubpixelOrder = switch (renderer.subpixelOrder()) {
                .none  => .rgb,
                .rgb   => .bgr,
                .bgr   => .vrgb,
                .vrgb  => .vbgr,
                .vbgr  => .none,
            };
            renderer.setSubpixelOrder(next);
            std.debug.print("Subpixel: {s}\n", .{renderer.subpixelOrder().name()});
        }
        if (rotate) angle += dt * 0.5;
        if (platform.isKeyDown(KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (platform.isKeyDown(KEY_X)) zoom *= 1.0 - dt * 2.0;

        const size = platform.getWindowSize();
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        if (w < 1 or h < 1) continue;

        // Begin frame (Vulkan: acquire swapchain image + begin render pass)
        if (use_vulkan) {
            const cmd = platform.beginFrame() orelse continue;
            renderer.setCommandBuffer(cmd);
        } else {
            gl.glViewport(0, 0, @intCast(size[0]), @intCast(size[1]));
            platform.clear(0.12, 0.12, 0.14, 1.0);
        }

        // Vulkan NDC has Y pointing down; flip top/bottom to match OpenGL convention
        const projection = if (use_vulkan)
            snail.Mat4.ortho(0, w, h, 0, -1, 1)
        else
            snail.Mat4.ortho(0, w, 0, h, -1, 1);
        const vector_projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w / 2.0;
        const cy = h / 2.0;
        const scene_transform = snail.Mat4.multiply(
            snail.Mat4.translate(cx, cy, 0),
            snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                snail.Mat4.rotateZ(angle),
                snail.Mat4.translate(-cx, -cy, 0),
            )),
        );
        const mvp = snail.Mat4.multiply(projection, scene_transform);
        const vector_mvp = snail.Mat4.multiply(vector_projection, scene_transform);

        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };
        const cyan = [4]f32{ 0.4, 0.8, 0.9, 1 };
        const yellow = [4]f32{ 0.9, 0.8, 0.3, 1 };
        const green = [4]f32{ 0.4, 0.9, 0.5, 1 };
        const pink = [4]f32{ 0.9, 0.5, 0.7, 1 };

        renderer.beginFrame();
        var shapes = snail.VectorBatch.init(shape_buf);
        buildPrimitiveShowcase(&shapes, w, h);
        if (shapes.shapeCount() > 0) {
            renderer.drawVectorTransformed(shapes.slice(), vector_mvp, w, h);
        }

        // Everything goes into one batch — texture arrays enable single-draw multi-font
        var batch = snail.Batch.init(vbuf);

        if (stress_test) {
            const stress_sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
            var sy: f32 = h - 20;
            var si: usize = 0;
            while (sy > 0) {
                const fs = stress_sizes[si % stress_sizes.len];
                _ = batch.addString(atlas_view, &font, "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10, sy, fs, white);
                sy -= fs * 1.3;
                si += 1;
            }
        } else {
            // Left column: x=30..col2_x-20; right column: col2_x..w
            const col2_x: f32 = w * 0.52;
            const col1_max_w: f32 = col2_x - 50; // keep text out of the right column

            var y: f32 = h - 70;

            // Title + subtitle
            _ = batch.addString(atlas_view, &font, "snail", 30, y, 64, white);
            y -= 76;
            _ = batch.addString(atlas_view, &font, "GPU font rendering via direct Bezier curve evaluation", 30, y, 14, gray);
            y -= 26;

            // Multi-size Latin — strings chosen so each line fits within col1_max_w
            const size_rows = [_]struct { fs: f32, text: []const u8 }{
                .{ .fs = 11, .text = "The quick brown fox jumps over the lazy dog 0123456789" },
                .{ .fs = 14, .text = "The quick brown fox jumps over the lazy dog" },
                .{ .fs = 20, .text = "The quick brown fox jumps over" },
                .{ .fs = 28, .text = "Pack my box with five" },
                .{ .fs = 40, .text = "How vexingly quick" },
            };
            for (size_rows) |row| {
                _ = batch.addString(atlas_view, &font, row.text, 30, y, row.fs, white);
                y -= row.fs * 1.4;
            }
            y -= 6;

            // Character sets
            _ = batch.addString(atlas_view, &font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 30, y, 14, cyan);
            y -= 20;
            _ = batch.addString(atlas_view, &font, "abcdefghijklmnopqrstuvwxyz !@#$%^&*()", 30, y, 14, yellow);
            y -= 24;

            // Ligatures
            _ = batch.addString(atlas_view, &font, "fi fl ffi ffl office difficult affect", 30, y, 18, white);
            y -= 28;

            // Word-wrapped paragraph
            const paragraph = "Direct Bezier curve evaluation in the fragment shader produces " ++
                "resolution-independent text at any size, rotation, or perspective transform. " ++
                "No pre-rasterized glyph bitmaps, no signed distance fields.";
            _ = batch.addStringWrapped(atlas_view, &font, paragraph, 30, y, 12, col1_max_w, 17, gray);

            // Right column — script showcase in same batch (texture array = one draw call)
            var sy: f32 = h - 70;
            const scripts = [_]struct { label: []const u8, text: []const u8, sf: *ScriptFont, color: [4]f32 }{
                .{ .label = "Arabic", .text = arabic_text, .sf = &arabic, .color = green },
                .{ .label = "Devanagari", .text = devanagari_text, .sf = &devanagari, .color = cyan },
                .{ .label = "Thai", .text = thai_text, .sf = &thai, .color = yellow },
                .{ .label = "Mongolian", .text = mongolian_text, .sf = &mongolian, .color = pink },
                .{ .label = "Emoji", .text = emoji_text, .sf = &emoji, .color = white },
            };
            for (scripts) |s| {
                _ = batch.addString(atlas_view, &font, s.label, col2_x, sy, 10, gray);
                sy -= 26;
                _ = batch.addString(switch (s.label[0]) {
                    'A' => arabic_view,
                    'D' => devanagari_view,
                    'M' => mongolian_view,
                    'T' => thai_view,
                    else => emoji_view,
                }, &s.sf.font, s.text, col2_x, sy, 28, s.color);
                sy -= 40;
            }
        }

        // Main scene: one draw call for ALL fonts
        if (batch.glyphCount() > 0) {
            renderer.draw(batch.slice(), mvp, w, h);
        }
        const total_glyphs = batch.glyphCount();

        // HUD (separate draw for different MVP)
        {
            var hud = snail.Batch.init(vbuf[batch.len..]);
            _ = hud.addString(atlas_view, &font, "snail - GPU Bezier curve font rendering", 10, 30, 12, gray);
            const hb_str = if (build_options.enable_harfbuzz) " | HarfBuzz ON" else "";
            const sp_name = renderer.subpixelOrder().name();
            var hud_line2_buf: [128]u8 = undefined;
            const hud_line2 = std.fmt.bufPrint(&hud_line2_buf, "Z/X zoom | R rotate | S stress | L subpixel: {s}{s}", .{ sp_name, hb_str }) catch "Z/X zoom | R rotate | S stress | L subpixel order";
            _ = hud.addString(atlas_view, &font, hud_line2, 10, 14, 12, gray);
            if (hud.glyphCount() > 0) {
                renderer.draw(hud.slice(), projection, w, h);
            }
        }

        if (!use_vulkan and frame_count == 2) {
            const iw: u32 = @intFromFloat(w);
            const ih: u32 = @intFromFloat(h);
            if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
                defer allocator.free(px);
                screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
            }
        }
        if (frame_count % 60 == 0 and fps_display > 0) {
            std.debug.print("\rFPS: {d:.0}  Glyphs: {}   ", .{ fps_display, total_glyphs });
        }
        frame_count += 1;

        if (use_vulkan) {
            platform.endFrame();
        } else {
            platform.swapBuffers();
        }
    }
}

test {
    _ = @import("snail.zig");
}
