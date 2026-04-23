const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const demo_banner = @import("demo_banner.zig");
const assets = @import("assets");
const screenshot = @import("render/screenshot.zig");
const subpixel_detect = @import("render/subpixel_detect.zig");

const use_vulkan = build_options.enable_vulkan;
const platform = if (use_vulkan) @import("render/vulkan_platform.zig") else @import("render/platform.zig");
const gl = if (use_vulkan) struct {} else @import("render/gl.zig").gl;
const demo_debug_timings = true;
const demo_debug_frame_limit: u32 = 300;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn debugFrameEnabled(frame_index: u32) bool {
    return demo_debug_timings and frame_index < demo_debug_frame_limit;
}

fn debugFrameStart(frame_index: u32, dt: f32, zoom: f32, pan_x: f32, pan_y: f32, angle: f32) u64 {
    const start = nowNs();
    if (debugFrameEnabled(frame_index)) {
        std.debug.print(
            "[demo][frame {d}] start dt={d:.3}ms zoom={d:.3} pan=({d:.1},{d:.1}) angle={d:.3}\n",
            .{ frame_index, dt * 1000.0, zoom, pan_x, pan_y, angle },
        );
    }
    return start;
}

fn debugFrameStep(frame_index: u32, frame_start_ns: u64, step_start_ns: *u64, label: []const u8) void {
    if (!debugFrameEnabled(frame_index)) return;
    const now = nowNs();
    const step_ms = nsToMs(now - step_start_ns.*);
    const total_ms = nsToMs(now - frame_start_ns);
    std.debug.print("[demo][frame {d}] {s}: +{d:.3}ms total={d:.3}ms\n", .{
        frame_index,
        label,
        step_ms,
        total_ms,
    });
    step_start_ns.* = now;
}

fn debugLayout(frame_index: u32, layout: demo_banner.Layout, size: [2]u32) void {
    if (!debugFrameEnabled(frame_index)) return;
    std.debug.print(
        "[demo][frame {d}] window={}x{} hero=({d:.1},{d:.1},{d:.1},{d:.1}) script=({d:.1},{d:.1},{d:.1},{d:.1}) stage=({d:.1},{d:.1},{d:.1},{d:.1})\n",
        .{
            frame_index,
            size[0],
            size[1],
            layout.hero_panel.x,
            layout.hero_panel.y,
            layout.hero_panel.w,
            layout.hero_panel.h,
            layout.script_panel.x,
            layout.script_panel.y,
            layout.script_panel.w,
            layout.script_panel.h,
            layout.stage_panel.x,
            layout.stage_panel.y,
            layout.stage_panel.w,
            layout.stage_panel.h,
        },
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
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();
    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    var arabic = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_arabic, demo_banner.arabic_text);
    defer arabic.deinit();
    var devanagari = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_devanagari, demo_banner.devanagari_text);
    defer devanagari.deinit();
    var mongolian = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_mongolian, demo_banner.mongolian_text);
    defer mongolian.deinit();
    var thai = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_thai, demo_banner.thai_text);
    defer thai.deinit();
    var emoji = try demo_banner.ScriptFont.init(allocator, assets.twemoji_mozilla, demo_banner.emoji_text);
    defer emoji.deinit();

    var renderer = if (use_vulkan)
        try snail.Renderer.initVulkan(vk_ctx)
    else
        try snail.Renderer.init();
    defer renderer.deinit();

    const sys_order = subpixel_detect.detect();
    const initial_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    renderer.setSubpixelOrder(initial_order);

    const metrics = demo_banner.measureMetrics(&atlas, &font);
    const vbuf = try allocator.alloc(f32, 10000 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const path_buf = try allocator.alloc(f32, 256 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(path_buf);

    var atlas_views: [7]snail.AtlasView = undefined;
    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var uploaded_size = [2]u32{ 0, 0 };

    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var stress_test = false;
    var last_time = platform.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0.0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0.0;

    std.debug.print("snail - GPU Bezier font rendering\n", .{});
    std.debug.print("{} glyphs (Latin), Backend: {s}, HarfBuzz: {s}\n", .{
        atlas.glyph_map.count(),
        renderer.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    std.debug.print("Subpixel order: {s}\n", .{renderer.subpixelOrder().name()});
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, S stress, L subpixel order, Esc quit\n", .{});

    while (!platform.shouldClose()) {
        const now = platform.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;
        fps_timer += dt;
        fps_frames += 1;
        if (fps_timer >= 1.0) {
            fps_display = @as(f32, @floatFromInt(fps_frames)) / @as(f32, @floatCast(fps_timer));
            fps_timer = 0.0;
            fps_frames = 0;
        }
        const frame_start_ns = debugFrameStart(frame_count, dt, zoom, pan_x, pan_y, angle);
        var frame_step_ns = frame_start_ns;

        const KEY_R = platform.KEY_R;
        const KEY_S = platform.KEY_S;
        const KEY_L = platform.KEY_L;
        const KEY_Z = platform.KEY_Z;
        const KEY_X = platform.KEY_X;
        const KEY_ESCAPE = platform.KEY_ESCAPE;
        const KEY_LEFT = platform.KEY_LEFT;
        const KEY_RIGHT = platform.KEY_RIGHT;
        const KEY_UP = platform.KEY_UP;
        const KEY_DOWN = platform.KEY_DOWN;

        if (platform.consumeMonitorChanged()) {
            const order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
            if (order != renderer.subpixelOrder()) {
                renderer.setSubpixelOrder(order);
                std.debug.print("Monitor change: subpixel order -> {s}\n", .{order.name()});
            }
        }

        if (platform.isKeyPressed(KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(KEY_S)) stress_test = !stress_test;
        if (platform.isKeyPressed(KEY_ESCAPE)) break;
        if (platform.isKeyPressed(KEY_L)) {
            const next: snail.SubpixelOrder = switch (renderer.subpixelOrder()) {
                .none => .rgb,
                .rgb => .bgr,
                .bgr => .vrgb,
                .vrgb => .vbgr,
                .vbgr => .none,
            };
            renderer.setSubpixelOrder(next);
            std.debug.print("Subpixel: {s}\n", .{renderer.subpixelOrder().name()});
        }
        if (rotate) angle += dt * 0.5;
        if (platform.isKeyDown(KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (platform.isKeyDown(KEY_X)) zoom *= 1.0 - dt * 2.0;
        const pan_speed: f32 = 900.0;
        const pan_step = pan_speed * dt;
        if (platform.isKeyDown(KEY_LEFT)) pan_x += pan_step;
        if (platform.isKeyDown(KEY_RIGHT)) pan_x -= pan_step;
        if (platform.isKeyDown(KEY_UP)) pan_y += pan_step;
        if (platform.isKeyDown(KEY_DOWN)) pan_y -= pan_step;

        const size = platform.getWindowSize();
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        if (w < 1.0 or h < 1.0) continue;
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "input + window");

        const layout = demo_banner.buildLayout(w, h, metrics);
        debugLayout(frame_count, layout, size);
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "build layout");
        const size_key = [2]u32{ size[0], size[1] };
        if (path_picture == null or size_key[0] != uploaded_size[0] or size_key[1] != uploaded_size[1]) {
            if (debugFrameEnabled(frame_count)) {
                const reason = if (path_picture == null) "path picture missing" else "window size changed";
                std.debug.print(
                    "[demo][frame {d}] rebuild picture reason={s} old={}x{} new={}x{}\n",
                    .{ frame_count, reason, uploaded_size[0], uploaded_size[1], size_key[0], size_key[1] },
                );
            }
            if (path_picture) |*picture| {
                picture.deinit();
                path_picture = null;
            }
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "drop old picture");
            var picture_builder = snail.PathPictureBuilder.init(allocator);
            defer picture_builder.deinit();
            try demo_banner.buildPathShowcase(&picture_builder, layout);
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "build path showcase");
            path_picture = try picture_builder.freeze(allocator);
            if (debugFrameEnabled(frame_count)) {
                std.debug.print(
                    "[demo][frame {d}] picture instances={} layer_info={}x{} pages={}\n",
                    .{
                        frame_count,
                        path_picture.?.instances.len,
                        path_picture.?.atlas.layer_info_width,
                        path_picture.?.atlas.layer_info_height,
                        path_picture.?.atlas.pages.len,
                    },
                );
            }
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "freeze picture");
            uploaded_size = size_key;
            renderer.uploadAtlases(&[_]*const snail.Atlas{
                &atlas,
                &arabic.atlas,
                &devanagari.atlas,
                &mongolian.atlas,
                &thai.atlas,
                &emoji.atlas,
                &path_picture.?.atlas,
            }, &atlas_views);
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "upload atlases");
        }

        const atlas_view = &atlas_views[0];
        const path_view = &atlas_views[6];

        if (use_vulkan) {
            const cmd = platform.beginFrame() orelse continue;
            renderer.setCommandBuffer(cmd);
        } else {
            const clear = demo_banner.clearColor();
            gl.glViewport(0, 0, @intCast(size[0]), @intCast(size[1]));
            platform.clear(clear[0], clear[1], clear[2], clear[3]);
        }
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "begin frame + clear");

        const projection = snail.Mat4.ortho(0, w, 0, h, -1, 1);
        const vector_projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_core = snail.Mat4.multiply(
            snail.Mat4.translate(cx, cy, 0),
            snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                snail.Mat4.rotateZ(angle),
                snail.Mat4.translate(-cx, -cy, 0),
            )),
        );
        const text_scene_transform = snail.Mat4.multiply(snail.Mat4.translate(pan_x, -pan_y, 0), scene_core);
        const vector_scene_transform = snail.Mat4.multiply(snail.Mat4.translate(pan_x, pan_y, 0), scene_core);
        const mvp = snail.Mat4.multiply(projection, text_scene_transform);
        const vector_mvp = snail.Mat4.multiply(vector_projection, vector_scene_transform);
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "build transforms");

        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };

        renderer.beginFrame();
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "renderer.beginFrame");
        if (path_picture) |*picture| {
            var paths = snail.PathBatch.init(path_buf);
            _ = paths.addPicture(path_view, picture);
            if (debugFrameEnabled(frame_count)) {
                std.debug.print("[demo][frame {d}] path batch shapes={}\n", .{ frame_count, paths.shapeCount() });
            }
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "build path batch");
            if (paths.shapeCount() > 0) {
                renderer.drawPaths(paths.slice(), vector_mvp, w, h);
                debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "draw paths");
            }
        }

        var batch = snail.Batch.init(vbuf);
        if (stress_test) {
            const stress_sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
            var sy: f32 = h - 20.0;
            var si: usize = 0;
            while (sy > 0.0) {
                const fs = stress_sizes[si % stress_sizes.len];
                _ = batch.addString(atlas_view, &font, "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10.0, sy, fs, white);
                sy -= fs * 1.3;
                si += 1;
            }
        } else {
            demo_banner.drawText(&batch, h, layout, .{
                .latin_font = &font,
                .latin_view = &atlas_views[0],
                .arabic_font = &arabic,
                .arabic_view = &atlas_views[1],
                .devanagari_font = &devanagari,
                .devanagari_view = &atlas_views[2],
                .mongolian_font = &mongolian,
                .mongolian_view = &atlas_views[3],
                .thai_font = &thai,
                .thai_view = &atlas_views[4],
                .emoji_font = &emoji,
                .emoji_view = &atlas_views[5],
            });
        }
        if (debugFrameEnabled(frame_count)) {
            std.debug.print("[demo][frame {d}] text batch glyphs={} floats={}\n", .{
                frame_count,
                batch.glyphCount(),
                batch.len,
            });
        }
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "build text batch");

        if (batch.glyphCount() > 0) {
            renderer.draw(batch.slice(), mvp, w, h);
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "draw text");
        }
        const total_glyphs = batch.glyphCount();

        {
            var hud = snail.Batch.init(vbuf[batch.len..]);
            _ = hud.addString(atlas_view, &font, "snail demo", 10.0, 30.0, 12.0, gray);
            const hb_str = if (build_options.enable_harfbuzz) " | HarfBuzz ON" else "";
            const sp_name = renderer.subpixelOrder().name();
            var hud_line2_buf: [128]u8 = undefined;
            const hud_line2 = std.fmt.bufPrint(&hud_line2_buf, "Arrows pan | Z/X zoom | R rotate | S stress | L subpixel: {s}{s}", .{ sp_name, hb_str }) catch "Arrows pan | Z/X zoom | R rotate | S stress | L subpixel order";
            _ = hud.addString(atlas_view, &font, hud_line2, 10.0, 14.0, 12.0, gray);
            if (hud.glyphCount() > 0) {
                renderer.draw(hud.slice(), projection, w, h);
            }
        }
        debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "draw hud");

        if (!use_vulkan and frame_count == 2) {
            const iw: u32 = @intFromFloat(w);
            const ih: u32 = @intFromFloat(h);
            if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
                defer allocator.free(px);
                screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
            }
            debugFrameStep(frame_count, frame_start_ns, &frame_step_ns, "capture screenshot");
        }
        if (frame_count % 60 == 0 and fps_display > 0.0) {
            std.debug.print("\rFPS: {d:.0}  Glyphs: {}   ", .{ fps_display, total_glyphs });
        }
        frame_count += 1;

        if (use_vulkan) {
            platform.endFrame();
        } else {
            platform.swapBuffers();
        }
        debugFrameStep(frame_count - 1, frame_start_ns, &frame_step_ns, "present");
        if (debugFrameEnabled(frame_count - 1)) {
            std.debug.print(
                "[demo][frame {d}] done total={d:.3}ms\n",
                .{ frame_count - 1, nsToMs(nowNs() - frame_start_ns) },
            );
        }
    }
}

test {
    _ = @import("snail.zig");
}
