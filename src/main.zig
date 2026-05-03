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

fn linearToSrgbU8(v: f32) u8 {
    const s = if (v <= 0.0031308) v * 12.92 else 1.055 * std.math.pow(f32, v, 1.0 / 2.4) - 0.055;
    return @intFromFloat(std.math.clamp(s, 0, 1) * 255);
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

    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var path_view: snail.AtlasHandle = .{ .atlas = undefined };
    var uploaded_size = [2]u32{ 0, 0 };

    var buf_width: u32 = 0;
    var buf_height: u32 = 0;
    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var last_time = platform.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0.0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0.0;

    std.debug.print("snail - GPU text & vector rendering\n", .{});
    std.debug.print("Backend: {s}, HarfBuzz: {s}\n", .{
        renderer.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, L subpixel order, Esc quit\n", .{});

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

        if (platform.consumeMonitorChanged()) {
            detected_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
            if (detected_order != renderer.subpixelOrder()) {
                renderer.setSubpixelOrder(detected_order);
            }
        }

        if (platform.isKeyPressed(platform.KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(platform.KEY_ESCAPE)) break;
        if (platform.isKeyPressed(platform.KEY_L)) {
            const next: snail.SubpixelOrder = switch (renderer.subpixelOrder()) {
                .none => .rgb,
                .rgb => .bgr,
                .bgr => .vrgb,
                .vrgb => .vbgr,
                .vbgr => .none,
            };
            renderer.setSubpixelOrder(next);
        }
        if (rotate) angle += dt * 0.5;
        if (platform.isKeyDown(platform.KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (platform.isKeyDown(platform.KEY_X)) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (platform.isKeyDown(platform.KEY_LEFT)) pan_x += pan_step;
        if (platform.isKeyDown(platform.KEY_RIGHT)) pan_x -= pan_step;
        if (platform.isKeyDown(platform.KEY_UP)) pan_y += pan_step;
        if (platform.isKeyDown(platform.KEY_DOWN)) pan_y -= pan_step;

        const size = platform.getWindowSize();
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        if (w < 1.0 or h < 1.0) continue;

        const layout = demo_banner.buildLayout(w, h);
        const size_key = [2]u32{ size[0], size[1] };

        // On resize: lay out text to collect decoration rects, rebuild path picture,
        // re-upload all atlases. Text batch is then re-populated with valid handles.
        if (path_picture == null or size_key[0] != uploaded_size[0] or size_key[1] != uploaded_size[1]) {
            // Measure decorations by populating a scratch text batch
            var scratch = snail.TextBatch.init(vbuf);
            var dec_rects: [8]snail.Rect = undefined;
            var text_result = demo_banner_scene.populateTextBatch(&scratch, layout, &scene_assets, &dec_rects);

            // If any glyphs were missing, drawText extended the atlases.
            // Re-populate so the scratch pass has correct metrics.
            if (text_result.missing) {
                scratch = snail.TextBatch.init(vbuf);
                text_result = demo_banner_scene.populateTextBatch(&scratch, layout, &scene_assets, &dec_rects);
            }

            if (path_picture) |*picture| {
                picture.deinit();
                path_picture = null;
            }
            path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, &scene_assets, dec_rects[0..text_result.decoration_count]);
            uploaded_size = size_key;
            path_view = scene_assets.uploadAtlases(&renderer, &path_picture.?);
        }

        const clear = demo_banner.clearColor();

        if (use_vulkan) {
            const cmd = platform.beginFrame() orelse continue;
            renderer.setCommandBuffer(cmd);
        } else if (use_gl) {
            gl.glViewport(0, 0, @intCast(size[0]), @intCast(size[1]));
            platform.clear(clear[0], clear[1], clear[2], clear[3]);
        } else {
            const bsz = platform.getBufferSize();
            if (bsz[0] != buf_width or bsz[1] != buf_height) {
                if (platform.getPixelBuffer()) |px| {
                    buf_width = bsz[0];
                    buf_height = bsz[1];
                    cpu_state = CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);
                    renderer = snail.Renderer.initCpu(&cpu_state);
                    uploaded_size = .{ 0, 0 };
                }
            }
            cpu_state.clear(
                linearToSrgbU8(clear[0]),
                linearToSrgbU8(clear[1]),
                linearToSrgbU8(clear[2]),
                @intFromFloat(clear[3] * 255),
            );
        }

        const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_transform = snail.Mat4.multiply(
            snail.Mat4.translate(pan_x, pan_y, 0),
            snail.Mat4.multiply(
                snail.Mat4.translate(cx, cy, 0),
                snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                    snail.Mat4.rotateZ(angle),
                    snail.Mat4.translate(-cx, -cy, 0),
                )),
            ),
        );
        const mvp = snail.Mat4.multiply(projection, scene_transform);

        renderer.beginFrame();

        if (!use_cpu) {
            if (path_picture) |*picture| {
                var paths = snail.PathBatch.init(path_buf);
                _ = paths.addPicture(&path_view, picture);
                if (paths.shapeCount() > 0) {
                    renderer.drawPaths(paths.slice(), mvp, w, h);
                }
            }
        } else {
            if (path_picture) |*picture| {
                cpu_state.drawPathPicture(picture);
            }
        }

        var batch = snail.TextBatch.init(vbuf);
        if (!use_cpu) {
            var dec_ignore: [8]snail.Rect = undefined;
            _ = demo_banner_scene.populateTextBatch(&batch, layout, &scene_assets, &dec_ignore);
        }

        if (batch.glyphCount() > 0) {
            renderer.drawText(batch.slice(), mvp, w, h);
        }

        if (use_gl and frame_count == 2) {
            const iw: u32 = @intFromFloat(w);
            const ih: u32 = @intFromFloat(h);
            if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
                defer allocator.free(px);
                screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
            }
        }
        if (frame_count % 60 == 0 and fps_display > 0.0) {
            std.debug.print("\rFPS: {d:.0}  Glyphs: {}   ", .{ fps_display, batch.glyphCount() });
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
