const std = @import("std");
const snail = @import("snail.zig");
const build_options = @import("build_options");
const demo_banner = @import("demo_banner.zig");
const demo_banner_scene = @import("demo_banner_scene.zig");
const screenshot = @import("render/screenshot.zig");
const subpixel_detect = @import("render/subpixel_detect.zig");
const CpuRenderer = @import("cpu_renderer.zig").CpuRenderer;

const demo_renderer = build_options.demo_renderer;
const use_gl = demo_renderer == .gl44 or demo_renderer == .gl33;
const use_vulkan = demo_renderer == .vulkan;
const use_cpu = demo_renderer == .cpu;

const platform = if (use_vulkan) @import("render/vulkan_platform.zig") else if (use_gl) @import("render/platform.zig") else @import("render/cpu_platform.zig");
const gl = if (use_gl) @import("render/gl.zig").gl else struct {};

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
    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var cpu_state: CpuRenderer = undefined;
    var renderer = if (use_vulkan)
        try snail.Renderer.initVulkan(vk_ctx)
    else if (use_gl)
        try snail.Renderer.init()
    else blk: {
        const px = platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = platform.getBufferSize();
        cpu_state = CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);
        break :blk snail.Renderer.initCpu(&cpu_state);
    };
    defer renderer.deinit();

    const sys_order = subpixel_detect.detect();
    var detected_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    renderer.setSubpixelOrder(detected_order);

    const vbuf = try allocator.alloc(f32, 10000 * snail.TEXT_FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const path_buf = try allocator.alloc(f32, 512 * snail.TEXT_FLOATS_PER_GLYPH);
    defer allocator.free(path_buf);

    var atlas_views: [7]snail.AtlasHandle = undefined;
    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var overlay_picture: ?snail.PathPicture = null;
    defer if (overlay_picture) |*picture| picture.deinit();
    var overlay_view: ?snail.AtlasHandle = null;
    var uploaded_size = [2]u32{ 0, 0 };
    var view_mode = demo_banner_scene.ViewMode.normal;
    var uploaded_view_mode = view_mode;

    // ── Tile image for image-paint fill ──
    const assets = @import("assets");
    var tile_image = try snail.Image.initRgba8(allocator, 16, 16, assets.checkerboard_rgba);
    defer tile_image.deinit();

    var buf_width: u32 = 0;
    var buf_height: u32 = 0;
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
        scene_assets.latin_atlas.glyph_map.count(),
        renderer.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    std.debug.print("Subpixel order: {s}\n", .{renderer.subpixelOrder().name()});
    std.debug.print("Subpixel mode: {s}\n", .{renderer.subpixelMode().name()});
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, S stress, D debug view, L subpixel order, M subpixel mode, Esc quit\n", .{});

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

        const KEY_R = platform.KEY_R;
        const KEY_S = platform.KEY_S;
        const KEY_D = platform.KEY_D;
        const KEY_L = platform.KEY_L;
        const KEY_M = platform.KEY_M;
        const KEY_Z = platform.KEY_Z;
        const KEY_X = platform.KEY_X;
        const KEY_ESCAPE = platform.KEY_ESCAPE;
        const KEY_LEFT = platform.KEY_LEFT;
        const KEY_RIGHT = platform.KEY_RIGHT;
        const KEY_UP = platform.KEY_UP;
        const KEY_DOWN = platform.KEY_DOWN;

        if (platform.consumeMonitorChanged()) {
            detected_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
            if (detected_order != renderer.subpixelOrder()) {
                renderer.setSubpixelOrder(detected_order);
                std.debug.print("Monitor change: subpixel order -> {s}\n", .{detected_order.name()});
            }
        }

        if (platform.isKeyPressed(KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(KEY_S)) stress_test = !stress_test;
        if (platform.isKeyPressed(KEY_D)) {
            view_mode = view_mode.next();
            std.debug.print("View: {s}\n", .{view_mode.label()});
        }
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
        if (platform.isKeyPressed(KEY_M)) {
            const next: snail.SubpixelMode = switch (renderer.subpixelMode()) {
                .safe => .legacy_unsafe,
                .legacy_unsafe => .safe,
            };
            renderer.setSubpixelMode(next);
            std.debug.print("Subpixel mode: {s}\n", .{renderer.subpixelMode().name()});
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

        const layout = demo_banner.buildLayout(w, h, scene_assets.metrics);
        const size_key = [2]u32{ size[0], size[1] };
        if (path_picture == null or size_key[0] != uploaded_size[0] or size_key[1] != uploaded_size[1] or view_mode != uploaded_view_mode) {
            if (path_picture) |*picture| {
                picture.deinit();
                path_picture = null;
            }
            if (overlay_picture) |*picture| {
                picture.deinit();
                overlay_picture = null;
            }
            path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, view_mode, &tile_image);
            uploaded_size = size_key;
            uploaded_view_mode = view_mode;
            scene_assets.uploadAtlases(&renderer, &path_picture.?, &atlas_views);
            if (try demo_banner_scene.buildPathOverlayPicture(allocator, &path_picture.?, view_mode)) |picture| {
                overlay_picture = picture;
                overlay_view = renderer.uploadPathPicture(&overlay_picture.?);
            } else {
                overlay_view = null;
            }
        }

        const atlas_view = &atlas_views[0];
        const path_view = &atlas_views[6];
        const clear = demo_banner.clearColor();

        if (use_vulkan) {
            const cmd = platform.beginFrame() orelse continue;
            renderer.setCommandBuffer(cmd);
        } else if (use_gl) {
            gl.glViewport(0, 0, @intCast(size[0]), @intCast(size[1]));
            platform.clear(clear[0], clear[1], clear[2], clear[3]);
        } else {
            // CPU: update pixel buffer if window was resized
            const bsz = platform.getBufferSize();
            if (bsz[0] != buf_width or bsz[1] != buf_height) {
                if (platform.getPixelBuffer()) |px| {
                    buf_width = bsz[0];
                    buf_height = bsz[1];
                    cpu_state = CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);
                    renderer = snail.Renderer.initCpu(&cpu_state);
                    // Force path picture rebuild
                    uploaded_size = .{ 0, 0 };
                }
            }
            cpu_state.clear(
                @intFromFloat(clear[0] * 255),
                @intFromFloat(clear[1] * 255),
                @intFromFloat(clear[2] * 255),
                @intFromFloat(clear[3] * 255),
            );
        }

        const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_core = snail.Mat4.multiply(
            snail.Mat4.translate(cx, cy, 0),
            snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                snail.Mat4.rotateZ(angle),
                snail.Mat4.translate(-cx, -cy, 0),
            )),
        );
        const scene_transform = snail.Mat4.multiply(snail.Mat4.translate(pan_x, pan_y, 0), scene_core);
        const mvp = snail.Mat4.multiply(projection, scene_transform);

        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };

        renderer.beginFrame();
        if (use_cpu) {
            // CPU renderer: draw paths and text directly
            if (path_picture) |*picture| {
                cpu_state.drawPathPicture(picture);
            }
            demo_banner.drawTextCpu(&cpu_state, layout, scene_assets.metrics, .{
                .latin_font = &scene_assets.latin_font,
                .latin_atlas = &scene_assets.latin_atlas,
                .arabic = &scene_assets.arabic,
                .devanagari = &scene_assets.devanagari,
                .mongolian = &scene_assets.mongolian,
                .thai = &scene_assets.thai,
                .emoji = &scene_assets.emoji,
            });
        } else {
            if (path_picture) |*picture| {
                var paths = snail.PathBatch.init(path_buf);
                _ = paths.addPicture(path_view, picture);
                if (overlay_picture) |*overlay| {
                    _ = paths.addPicture(&overlay_view.?, overlay);
                }
                if (paths.shapeCount() > 0) {
                    renderer.drawPaths(paths.slice(), mvp, w, h);
                }
            }
        }

        var batch = snail.TextBatch.init(vbuf);
        if (use_cpu) {
            // Text already drawn above
        } else if (!view_mode.showText()) {
            // Debug vector views keep the text layer out of the way.
        } else if (stress_test) {
            const stress_sizes = [_]f32{ 10, 14, 18, 24, 32, 48 };
            var sy: f32 = 20.0;
            var si: usize = 0;
            while (sy < h) {
                const fs = stress_sizes[si % stress_sizes.len];
                _ = batch.addText(atlas_view, &scene_assets.latin_font, "The quick brown fox jumps over the lazy dog 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ", 10.0, sy, fs, white);
                sy += fs * 1.3;
                si += 1;
            }
        } else {
            demo_banner_scene.populateTextBatch(&batch, layout, &scene_assets, &atlas_views);
        }

        if (batch.glyphCount() > 0) {
            renderer.setSubpixelBackdrop(null);
            renderer.drawText(batch.slice(), mvp, w, h);
        }
        const total_glyphs = batch.glyphCount();

        {
            renderer.setSubpixelBackdrop(clear);
            var hud = snail.TextBatch.init(vbuf[batch.len..]);
            _ = hud.addText(atlas_view, &scene_assets.latin_font, "snail demo", 10.0, h - 30.0, 12.0, gray);
            const hb_str = if (build_options.enable_harfbuzz) " | HarfBuzz ON" else "";
            const sp_name = renderer.subpixelOrder().name();
            const sp_mode = renderer.subpixelMode().name();
            const sp_suffix = if (renderer.subpixelMode() == .safe)
                " | safe LCD when axis-aligned"
            else
                "";
            var hud_line2_buf: [160]u8 = undefined;
            const hud_line2 = std.fmt.bufPrint(&hud_line2_buf, "Arrows pan | Z/X zoom | R rotate | S stress | D view: {s} | L order: {s} | M mode: {s}{s}{s}", .{ view_mode.label(), sp_name, sp_mode, sp_suffix, hb_str }) catch "Arrows pan | Z/X zoom | R rotate | S stress | D debug view | L order | M mode";
            _ = hud.addText(atlas_view, &scene_assets.latin_font, hud_line2, 10.0, h - 14.0, 12.0, gray);
            if (hud.glyphCount() > 0) {
                renderer.drawText(hud.slice(), projection, w, h);
            }
        }

        if (use_gl and !use_cpu and frame_count == 2) {
            const iw: u32 = @intFromFloat(w);
            const ih: u32 = @intFromFloat(h);
            if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
                defer allocator.free(px);
                screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
            }
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
    }
}

test {
    _ = @import("snail.zig");
}
