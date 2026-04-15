const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const platform = @import("render/platform.zig");
const gl = platform.gl;
const assets = @import("assets");
const screenshot = @import("render/screenshot.zig");

const ScriptFont = struct {
    font: snail.Font,
    atlas: snail.Atlas,

    fn init(allocator: std.mem.Allocator, data: []const u8, sample_text: []const u8) !ScriptFont {
        var font = try snail.Font.init(data);
        var atlas = try snail.Atlas.init(allocator, &font, &.{});

        // Use HarfBuzz to discover glyphs from sample text when available
        if (comptime build_options.enable_harfbuzz) {
            _ = try atlas.addGlyphsForText(sample_text);
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
            _ = try atlas.addCodepoints(cps[0..n]);
        }
        return .{ .font = font, .atlas = atlas };
    }

    fn deinit(self: *ScriptFont) void {
        self.atlas.deinit();
        self.font.deinit();
    }
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try platform.init(1280, 720, "snail");
    defer platform.deinit();

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
    const emoji_text = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xae\xf0\x9f\x93\x90\xe2\x98\x85\xe2\x99\xa5\xe2\x9a\xa1"; // ✨🌍🎮📐☆♥⚡

    var arabic = try ScriptFont.init(allocator, assets.noto_sans_arabic, arabic_text);
    defer arabic.deinit();
    var devanagari = try ScriptFont.init(allocator, assets.noto_sans_devanagari, devanagari_text);
    defer devanagari.deinit();
    var mongolian = try ScriptFont.init(allocator, assets.noto_sans_mongolian, mongolian_text);
    defer mongolian.deinit();
    var thai = try ScriptFont.init(allocator, assets.noto_sans_thai, thai_text);
    defer thai.deinit();
    var emoji = try ScriptFont.init(allocator, assets.noto_emoji, emoji_text);
    defer emoji.deinit();

    var renderer = try snail.Renderer.init();
    defer renderer.deinit();

    // Upload all atlases as texture array (enables single-draw multi-font rendering)
    renderer.uploadAtlases(&[_]*const snail.Atlas{
        &atlas,
        &arabic.atlas,
        &devanagari.atlas,
        &mongolian.atlas,
        &thai.atlas,
        &emoji.atlas,
    });

    // Vertex buffer: enough for ~10000 glyphs
    const buf_size = 10000 * snail.FLOATS_PER_GLYPH;
    const vbuf = try allocator.alloc(f32, buf_size);
    defer allocator.free(vbuf);

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
    std.debug.print("{} glyphs (Latin), HarfBuzz: {s}\n", .{
        atlas.glyph_map.count(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    std.debug.print("Keys: Z/X zoom, R rotate, S stress, L subpixel, Esc quit\n", .{});

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

        if (platform.isKeyPressed(platform.c.GLFW_KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(platform.c.GLFW_KEY_S)) stress_test = !stress_test;
        if (platform.isKeyPressed(platform.c.GLFW_KEY_L)) {
            renderer.setSubpixel(!renderer.subpixelEnabled());
            std.debug.print("Subpixel: {s}\n", .{if (renderer.subpixelEnabled()) "ON" else "OFF"});
        }
        if (rotate) angle += dt * 0.5;
        if (platform.isKeyDown(platform.c.GLFW_KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (platform.isKeyDown(platform.c.GLFW_KEY_X)) zoom *= 1.0 - dt * 2.0;

        const size = platform.getWindowSize();
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        if (w < 1 or h < 1) continue;

        gl.glViewport(0, 0, @intCast(size[0]), @intCast(size[1]));
        platform.clear(0.12, 0.12, 0.14, 1.0);

        const projection = snail.Mat4.ortho(0, w, 0, h, -1, 1);
        const cx = w / 2.0;
        const cy = h / 2.0;
        const mvp = snail.Mat4.multiply(projection, snail.Mat4.multiply(
            snail.Mat4.translate(cx, cy, 0),
            snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                snail.Mat4.rotateZ(angle),
                snail.Mat4.translate(-cx, -cy, 0),
            )),
        ));

        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };
        const cyan = [4]f32{ 0.4, 0.8, 0.9, 1 };
        const yellow = [4]f32{ 0.9, 0.8, 0.3, 1 };
        const green = [4]f32{ 0.4, 0.9, 0.5, 1 };
        const pink = [4]f32{ 0.9, 0.5, 0.7, 1 };

        // Everything goes into one batch — texture arrays enable single-draw multi-font
        var batch = snail.Batch.init(vbuf);

        if (stress_test) {
            const stress_sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
            var sy: f32 = h - 20;
            var si: usize = 0;
            while (sy > 0) {
                const fs = stress_sizes[si % stress_sizes.len];
                _ = batch.addString(&atlas, &font, "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10, sy, fs, white);
                sy -= fs * 1.3;
                si += 1;
            }
        } else {
            var y: f32 = h - 50;

            // Title + subtitle
            _ = batch.addString(&atlas, &font, "snail", 30, y, 64, white);
            y -= 72;
            _ = batch.addString(&atlas, &font, "GPU font rendering via direct Bezier curve evaluation", 30, y, 16, gray);
            y -= 30;

            // Multi-size Latin
            for ([_]f32{ 12, 16, 24, 36, 48 }) |fs| {
                _ = batch.addString(&atlas, &font, "The quick brown fox jumps over the lazy dog", 30, y, fs, white);
                y -= fs * 1.35;
            }
            y -= 8;

            // Character sets
            _ = batch.addString(&atlas, &font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 30, y, 18, cyan);
            y -= 24;
            _ = batch.addString(&atlas, &font, "abcdefghijklmnopqrstuvwxyz !@#$%^&*()", 30, y, 18, yellow);
            y -= 28;

            // Ligatures
            _ = batch.addString(&atlas, &font, "fi fl ffi ffl office difficult", 30, y, 24, white);
            y -= 34;

            // Word-wrapped paragraph
            const paragraph = "Direct Bezier curve evaluation in the fragment shader produces resolution-independent, " ++
                "crisp text at any size, rotation, or perspective transform. No texture atlases, no signed distance fields.";
            _ = batch.addStringWrapped(&atlas, &font, paragraph, 30, y, 13, w * 0.45, 18, gray);

            // Script showcase (right column) — same batch, different fonts!
            const col2_x: f32 = w * 0.52;
            var sy: f32 = h - 50;
            const scripts = [_]struct { label: []const u8, text: []const u8, sf: *ScriptFont, color: [4]f32 }{
                .{ .label = "Arabic", .text = arabic_text, .sf = &arabic, .color = green },
                .{ .label = "Devanagari", .text = devanagari_text, .sf = &devanagari, .color = cyan },
                .{ .label = "Thai", .text = thai_text, .sf = &thai, .color = yellow },
                .{ .label = "Mongolian", .text = mongolian_text, .sf = &mongolian, .color = pink },
                .{ .label = "Emoji", .text = emoji_text, .sf = &emoji, .color = white },
            };
            for (scripts) |s| {
                _ = batch.addString(&atlas, &font, s.label, col2_x, sy, 12, gray);
                sy -= 18;
                _ = batch.addString(&s.sf.atlas, &s.sf.font, s.text, col2_x, sy, 32, s.color);
                sy -= 50;
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
            _ = hud.addString(&atlas, &font, "snail - GPU Bezier curve font rendering", 10, 30, 12, gray);
            const hb_str = if (build_options.enable_harfbuzz) " | HarfBuzz ON" else "";
            _ = hud.addString(&atlas, &font, "Z/X zoom | R rotate | S stress | L subpixel" ++ hb_str, 10, 14, 12, gray);
            if (hud.glyphCount() > 0) {
                renderer.draw(hud.slice(), projection, w, h);
            }
        }

        if (frame_count == 2) {
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

        platform.swapBuffers();
    }
}

test {
    _ = @import("snail.zig");
}
