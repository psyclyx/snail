const std = @import("std");
const snail = @import("snail.zig");
const platform = @import("render/platform.zig");
const gl = platform.gl;
const assets = @import("assets");
const screenshot = @import("render/screenshot.zig");

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try platform.init(1280, 720, "snail");
    defer platform.deinit();

    // Library API usage
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();

    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    renderer.uploadAtlas(&atlas);

    // Vertex buffer: enough for ~5000 glyphs
    const buf_size = 5000 * snail.FLOATS_PER_GLYPH;
    var vbuf = try allocator.alloc(f32, buf_size);
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

    std.debug.print("snail — GPU Bézier font rendering\n", .{});
    std.debug.print("{} glyphs prepared, {} UPM\n", .{ atlas.glyph_map.count(), font.unitsPerEm() });
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

        var batch = snail.Batch.init(vbuf);
        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };
        const cyan = [4]f32{ 0.4, 0.8, 0.9, 1 };
        const yellow = [4]f32{ 0.9, 0.8, 0.3, 1 };

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
            // Title sizes
            _ = batch.addString(&atlas, &font, "snail", 30, y, 72, white);
            y -= 80;
            _ = batch.addString(&atlas, &font, "GPU font rendering via direct Bezier curve evaluation", 30, y, 18, gray);
            y -= 36;

            // Multi-size samples
            for ([_]f32{ 12, 16, 24, 36, 48 }) |fs| {
                _ = batch.addString(&atlas, &font, "The quick brown fox jumps over the lazy dog", 30, y, fs, white);
                y -= fs * 1.4;
            }
            y -= 10;

            // Character set
            _ = batch.addString(&atlas, &font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 30, y, 20, cyan);
            y -= 28;
            _ = batch.addString(&atlas, &font, "abcdefghijklmnopqrstuvwxyz !@#$%^&*()", 30, y, 20, yellow);
            y -= 32;

            // Ligatures
            _ = batch.addString(&atlas, &font, "fi fl ffi ffl office difficult", 30, y, 28, white);
            y -= 40;

            // Word-wrapped paragraph
            const paragraph = "Direct Bezier curve evaluation in the fragment shader produces resolution-independent, " ++
                "crisp text at any size, rotation, or perspective transform. No texture atlases, no signed distance fields.";
            _ = batch.addStringWrapped(&atlas, &font, paragraph, 30, y, 14, w - 60, 20, gray);
        }

        if (batch.glyphCount() > 0) {
            renderer.draw(batch.slice(), mvp, w, h);
        }

        // HUD (no rotation/zoom)
        {
            var hud = snail.Batch.init(vbuf[batch.len..]);
            _ = hud.addString(&atlas, &font, "snail - GPU Bezier curve font rendering", 10, 30, 12, gray);
            _ = hud.addString(&atlas, &font, "Z/X zoom | R rotate | S stress | L subpixel", 10, 14, 12, gray);
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
            std.debug.print("\rFPS: {d:.0}  Glyphs: {}   ", .{ fps_display, batch.glyphCount() });
        }
        frame_count += 1;

        platform.swapBuffers();
    }
}

test {
    _ = @import("snail.zig");
}
