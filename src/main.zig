const std = @import("std");
const builtin = @import("builtin");
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

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn cycleHinting(h: snail.TextHinting) snail.TextHinting {
    return switch (h) {
        .none => .phase,
        .phase => .metrics,
        .metrics => .none,
    };
}

fn cycleSubpixelOrder(o: snail.SubpixelOrder) snail.SubpixelOrder {
    return switch (o) {
        .none => .rgb,
        .rgb => .bgr,
        .bgr => .vrgb,
        .vrgb => .vbgr,
        .vbgr => .none,
    };
}

fn aaName(o: snail.SubpixelOrder) []const u8 {
    return switch (o) {
        .none => "grayscale",
        .rgb => "subpixel-RGB",
        .bgr => "subpixel-BGR",
        .vrgb => "subpixel-VRGB",
        .vbgr => "subpixel-VBGR",
    };
}

fn mainLoop(allocator: std.mem.Allocator, vk_ctx: anytype) !void {
    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var gl_renderer: snail.GlRenderer = undefined;
    var vk_renderer: snail.VulkanRenderer = undefined;
    var cpu_state: CpuRenderer = undefined;
    var cpu_pool: snail.ThreadPool = undefined;
    var cpu_pool_initialized = false;
    var renderer = if (use_vulkan) blk: {
        vk_renderer = try snail.VulkanRenderer.init(vk_ctx);
        break :blk vk_renderer.asRenderer();
    } else if (use_gl) blk: {
        gl_renderer = try snail.GlRenderer.init(allocator);
        break :blk gl_renderer.asRenderer();
    } else blk: {
        const px = platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = platform.getBufferSize();
        cpu_state = CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);
        try cpu_pool.init(allocator, .{});
        cpu_pool_initialized = true;
        cpu_state.setThreadPool(&cpu_pool);
        break :blk snail.Renderer.initCpu(&cpu_state);
    };
    defer if (use_vulkan) vk_renderer.deinit();
    defer if (use_gl) gl_renderer.deinit();
    defer if (cpu_pool_initialized) cpu_pool.deinit();

    const sys_order = subpixel_detect.detect();
    const detected_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    // Default to grayscale; press B to cycle into the detected subpixel mode.
    var current_order: snail.SubpixelOrder = .none;
    std.debug.print("snail: detected subpixel order: system={s} monitor={s} (starting in {s})\n", .{ @tagName(sys_order), @tagName(detected_order), @tagName(current_order) });
    var selected_hinting: snail.TextHinting = .metrics;

    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var text_blob: ?snail.TextBlob = null;
    defer if (text_blob) |*blob| blob.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    var prepared: ?snail.PreparedResources = null;
    defer if (prepared) |*resources| resources.deinit();
    var draw_buf: []u32 = &.{};
    defer if (draw_buf.len > 0) allocator.free(draw_buf);
    var uploaded_size = [2]u32{ 0, 0 };
    var current_text_hinting: snail.TextHinting = .none;

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
    if (use_cpu and builtin.mode == .Debug) {
        std.debug.print(
            "WARNING: Debug build. CPU rasterization is ~30x slower without `--release=fast`.\n",
            .{},
        );
    }
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, H hinting, B AA mode, Esc quit\n", .{});
    std.debug.print("hinting={s} aa={s}\n", .{ @tagName(selected_hinting), aaName(current_order) });

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

        // Drop monitor-change auto-reset; the user owns the AA mode and can
        // cycle with B if they want to track the current display.
        _ = platform.consumeMonitorChanged();

        if (platform.isKeyPressed(platform.KEY_R)) rotate = !rotate;
        if (platform.isKeyPressed(platform.KEY_ESCAPE)) break;
        if (platform.isKeyPressed(platform.KEY_H)) {
            selected_hinting = cycleHinting(selected_hinting);
            std.debug.print("\nhinting={s}\n", .{@tagName(selected_hinting)});
        }
        if (platform.isKeyPressed(platform.KEY_B)) {
            current_order = cycleSubpixelOrder(current_order);
            std.debug.print("\naa={s}\n", .{aaName(current_order)});
        }
        if (rotate) angle += dt * 0.5;
        if (platform.isKeyDown(platform.KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (platform.isKeyDown(platform.KEY_X)) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (platform.isKeyDown(platform.KEY_LEFT)) pan_x += pan_step;
        if (platform.isKeyDown(platform.KEY_RIGHT)) pan_x -= pan_step;
        if (platform.isKeyDown(platform.KEY_UP)) pan_y += pan_step;
        if (platform.isKeyDown(platform.KEY_DOWN)) pan_y -= pan_step;
        const active_motion = rotate or
            platform.isKeyDown(platform.KEY_Z) or
            platform.isKeyDown(platform.KEY_X) or
            platform.isKeyDown(platform.KEY_LEFT) or
            platform.isKeyDown(platform.KEY_RIGHT) or
            platform.isKeyDown(platform.KEY_UP) or
            platform.isKeyDown(platform.KEY_DOWN);
        const desired_text_hinting: snail.TextHinting = if (active_motion) .none else selected_hinting;

        const size = platform.getWindowSize();
        const fb_size = platform.getFramebufferSize();
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        const viewport_w: f32 = @floatFromInt(fb_size[0]);
        const viewport_h: f32 = @floatFromInt(fb_size[1]);
        if (w < 1.0 or h < 1.0 or viewport_w < 1.0 or viewport_h < 1.0) continue;

        const layout = demo_banner.buildLayout(w, h);
        const size_key = [2]u32{ size[0], size[1] };

        // On resize: lay out text to collect decoration rects, rebuild path picture,
        // and rebuild the immutable scene resources.
        const needs_resource_rebuild = path_picture == null or text_blob == null or size_key[0] != uploaded_size[0] or size_key[1] != uploaded_size[1];
        if (needs_resource_rebuild) {
            if (prepared) |*resources| {
                resources.retireNowOrWhenSafe(&renderer);
                prepared = null;
            }
            if (path_picture) |*picture| {
                picture.deinit();
                path_picture = null;
            }
            if (text_blob) |*blob| {
                blob.deinit();
                text_blob = null;
            }

            var builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
            defer builder.deinit();
            var dec_rects: [8]snail.Rect = undefined;
            const text_result = demo_banner_scene.buildTextBlob(&builder, layout, &scene_assets, &dec_rects);

            text_blob = try builder.finish();
            path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, &scene_assets, dec_rects[0..text_result.decoration_count]);
            uploaded_size = size_key;
            current_text_hinting = desired_text_hinting;
            scene.reset();
            if (path_picture) |*picture| try scene.addPath(.{ .picture = picture });
            if (text_blob) |*blob| try scene.addText(.{ .blob = blob, .resolve = .{ .hinting = current_text_hinting } });

            var resource_entries: [8]snail.ResourceSet.Entry = undefined;
            var resources = snail.ResourceSet.init(&resource_entries);
            try resources.addScene(&scene);
            prepared = try renderer.uploadResourcesBlocking(allocator, &resources);
        } else if (desired_text_hinting != current_text_hinting) {
            current_text_hinting = desired_text_hinting;
            scene.reset();
            if (path_picture) |*picture| try scene.addPath(.{ .picture = picture });
            if (text_blob) |*blob| try scene.addText(.{ .blob = blob, .resolve = .{ .hinting = current_text_hinting } });
        }

        const clear_srgb = demo_banner.clearColor();
        // GL_FRAMEBUFFER_SRGB encodes glClearColor's linear input on write, and
        // the CPU path passes linear into linearToSrgbU8. Convert once here so
        // both backends store the documented sRGB clear bytes.
        const clear = [4]f32{ srgbToLinear(clear_srgb[0]), srgbToLinear(clear_srgb[1]), srgbToLinear(clear_srgb[2]), clear_srgb[3] };

        if (use_vulkan) {
            const cmd = platform.beginFrame() orelse continue;
            vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = platform.currentFrameIndex() });
        } else if (use_gl) {
            gl.glViewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));
            platform.clear(clear[0], clear[1], clear[2], clear[3]);
        } else {
            const bsz = platform.getBufferSize();
            if (bsz[0] != buf_width or bsz[1] != buf_height) {
                if (platform.getPixelBuffer()) |px| {
                    buf_width = bsz[0];
                    buf_height = bsz[1];
                    cpu_state.reinitBuffer(px, bsz[0], bsz[1], bsz[0] * 4);
                }
            }
            if (platform.getPixelBuffer()) |px| {
                const r = linearToSrgbU8(clear[0]);
                const g = linearToSrgbU8(clear[1]);
                const b = linearToSrgbU8(clear[2]);
                const a: u8 = @intFromFloat(clear[3] * 255);
                for (0..bsz[1]) |row| {
                    const row_start = row * bsz[0] * 4;
                    for (0..bsz[0]) |col| {
                        const off = row_start + col * 4;
                        px[off + 0] = r;
                        px[off + 1] = g;
                        px[off + 2] = b;
                        px[off + 3] = a;
                    }
                }
            }
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
        const draw_options = snail.DrawOptions{
            .mvp = mvp,
            .target = .{
                .pixel_width = viewport_w,
                .pixel_height = viewport_h,
                .subpixel_order = current_order,
            },
        };
        const needed = snail.DrawList.estimate(&scene, draw_options);
        const needed_segments = snail.DrawList.estimateSegments(&scene, draw_options);
        if (draw_buf.len < needed) {
            if (draw_buf.len > 0) allocator.free(draw_buf);
            draw_buf = try allocator.alloc(u32, needed);
        }
        const draw_segments = try allocator.alloc(snail.DrawSegment, needed_segments);
        defer allocator.free(draw_segments);
        var draw = snail.DrawList.init(draw_buf[0..needed], draw_segments);
        try draw.addScene(&prepared.?, &scene, draw_options);
        try renderer.draw(&prepared.?, draw.slice(), draw_options);

        if (use_gl and frame_count == 2) {
            const iw = fb_size[0];
            const ih = fb_size[1];
            if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
                defer allocator.free(px);
                screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
            }
        }
        if (frame_count % 60 == 0 and fps_display > 0.0) {
            const glyphs = if (text_blob) |*blob| blob.glyphCount() else 0;
            std.debug.print("\rFPS: {d:.0}  Glyphs: {}   ", .{ fps_display, glyphs });
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
