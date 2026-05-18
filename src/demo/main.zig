const std = @import("std");
const snail = @import("snail");
const build_options = @import("build_options");
const demo_banner = @import("banner.zig");
const demo_banner_scene = @import("scene.zig");
const renderer_driver = @import("renderer_driver.zig");
const subpixel_detect = @import("platform/subpixel.zig");
const wayland = @import("platform/wayland.zig");
const presentation = @import("platform/presentation.zig");

const KEY_R = wayland.KEY_R;
const KEY_L = wayland.KEY_L;
const KEY_Z = wayland.KEY_Z;
const KEY_X = wayland.KEY_X;
const KEY_B = wayland.KEY_B;
const KEY_C = wayland.KEY_C;
const KEY_ESCAPE = wayland.KEY_ESCAPE;
const KEY_LEFT = wayland.KEY_LEFT;
const KEY_RIGHT = wayland.KEY_RIGHT;
const KEY_UP = wayland.KEY_UP;
const KEY_DOWN = wayland.KEY_DOWN;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    return mainLoop(allocator);
}

fn toSnailEncoding(encoding: presentation.ColorEncoding) snail.ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: presentation.Info) snail.TargetEncoding {
    return .{
        .attachment = toSnailEncoding(info.framebuffer_encoding),
        .stored_pixels = .srgb,
    };
}

fn displayLinearResolve(kind: renderer_driver.Kind, encoding: snail.TargetEncoding) ?snail.LinearResolve {
    if (encoding.attachment == .linear and encoding.stored_pixels == .srgb and kind != .vulkan) {
        return .{};
    }
    return null;
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

fn envU32(comptime name: [:0]const u8, default: u32) u32 {
    const ptr = std.c.getenv(name.ptr) orelse return default;
    const value = std.mem.span(ptr);
    return std.fmt.parseInt(u32, value, 10) catch default;
}

fn f32Bits(value: f32) u32 {
    return @as(u32, @bitCast(value));
}

fn colorEncodingInt(encoding: snail.ColorEncoding) u32 {
    return switch (encoding) {
        .linear => 0,
        .srgb => 1,
    };
}

fn resolveLinearInt(resolve: ?snail.LinearResolve) u32 {
    return if (resolve == null) 0 else 1;
}

fn printMat4Bits(name: []const u8, m: snail.Mat4) void {
    std.debug.print("{s}=", .{name});
    for (m.data, 0..) |value, i| {
        if (i != 0) std.debug.print(",", .{});
        std.debug.print("0x{x}", .{f32Bits(value)});
    }
    std.debug.print("\n", .{});
}

fn printMat4Env(name: []const u8, m: snail.Mat4) void {
    std.debug.print(" {s}=", .{name});
    for (m.data, 0..) |value, i| {
        if (i != 0) std.debug.print(",", .{});
        std.debug.print("0x{x}", .{f32Bits(value)});
    }
}

fn dumpReproFrame(
    frame_count: u32,
    backend: []const u8,
    current_order: snail.SubpixelOrder,
    present: presentation.Info,
    target_encoding: snail.TargetEncoding,
    resolve: ?snail.LinearResolve,
    pan_x: f32,
    pan_y: f32,
    zoom: f32,
    angle: f32,
    projection: snail.Mat4,
    scene_transform: snail.Mat4,
    mvp: snail.Mat4,
) void {
    std.debug.print("\n--- snail repro frame {} ---\n", .{frame_count});
    std.debug.print("backend={s}\n", .{backend});
    std.debug.print("logical_size={}x{}\n", .{ present.logical_size[0], present.logical_size[1] });
    std.debug.print("framebuffer_size={}x{}\n", .{ present.framebuffer_size[0], present.framebuffer_size[1] });
    std.debug.print("buffer_scale={}\n", .{present.buffer_scale});
    std.debug.print("will_resample={}\n", .{@intFromBool(present.will_resample)});
    std.debug.print("subpixel_order={}\n", .{@intFromEnum(current_order)});
    std.debug.print("target_attachment={}\n", .{colorEncodingInt(target_encoding.attachment)});
    std.debug.print("target_stored={}\n", .{colorEncodingInt(target_encoding.stored_pixels)});
    std.debug.print("resolve_linear={}\n", .{resolveLinearInt(resolve)});
    std.debug.print("controls_bits pan_x=0x{x} pan_y=0x{x} zoom=0x{x} angle=0x{x}\n", .{
        f32Bits(pan_x),
        f32Bits(pan_y),
        f32Bits(zoom),
        f32Bits(angle),
    });
    printMat4Bits("projection_bits", projection);
    printMat4Bits("scene_transform_bits", scene_transform);
    printMat4Bits("mvp_bits", mvp);
    std.debug.print("repro_command: SNAIL_REPRO=1 SNAIL_REPRO_LOGICAL_W={} SNAIL_REPRO_LOGICAL_H={} SNAIL_REPRO_FB_W={} SNAIL_REPRO_FB_H={} SNAIL_REPRO_SUBPIXEL={} SNAIL_REPRO_WILL_RESAMPLE={} SNAIL_REPRO_ATTACHMENT={} SNAIL_REPRO_STORED={} SNAIL_REPRO_RESOLVE_LINEAR={} SNAIL_REPRO_OUTPUT=zig-out/repro-frame.tga", .{
        present.logical_size[0],
        present.logical_size[1],
        present.framebuffer_size[0],
        present.framebuffer_size[1],
        @intFromEnum(current_order),
        @intFromBool(present.will_resample),
        colorEncodingInt(target_encoding.attachment),
        colorEncodingInt(target_encoding.stored_pixels),
        resolveLinearInt(resolve),
    });
    printMat4Env("SNAIL_REPRO_MVP", mvp);
    std.debug.print(" zig build screenshot\n", .{});
    std.debug.print("--- end snail repro frame ---\n", .{});
}

fn logPresentationInfo(info: presentation.Info) void {
    const scale = info.scale();
    std.debug.print(
        "presentation: logical={}x{} framebuffer={}x{} scale={d:.2}x{d:.2} buffer_scale={} framebuffer={s} resample={}\n",
        .{
            info.logical_size[0],
            info.logical_size[1],
            info.framebuffer_size[0],
            info.framebuffer_size[1],
            scale[0],
            scale[1],
            info.buffer_scale,
            @tagName(info.framebuffer_encoding),
            info.will_resample,
        },
    );
}

fn releasePrepared(prepared: *?snail.PreparedResources) void {
    if (prepared.*) |*resources| {
        resources.retireNow();
        prepared.* = null;
    }
}

fn mainLoop(allocator: std.mem.Allocator) !void {
    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    const window = try wayland.Window.init(1280, 720, "snail");
    defer window.deinit();

    var active = try renderer_driver.Driver.init(allocator, window, renderer_driver.defaultKind());
    var active_valid = true;
    defer if (active_valid) active.deinit();

    const sys_order = subpixel_detect.detect();
    const detected_order = window.currentSubpixelOrder(sys_order);
    // Default to grayscale; press B to cycle into the detected subpixel mode.
    var current_order: snail.SubpixelOrder = .none;
    std.debug.print("snail: detected subpixel order: system={s} monitor={s} (starting in {s})\n", .{ @tagName(sys_order), @tagName(detected_order), @tagName(current_order) });

    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var text_blob: ?snail.TextBlob = null;
    defer if (text_blob) |*blob| blob.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    var prepared: ?snail.PreparedResources = null;
    defer releasePrepared(&prepared);
    var draw_buf: []u32 = &.{};
    defer if (draw_buf.len > 0) allocator.free(draw_buf);
    var draw_segments_buf: []snail.DrawSegment = &.{};
    defer if (draw_segments_buf.len > 0) allocator.free(draw_segments_buf);
    var uploaded_size = [4]u32{ 0, 0, 0, 0 };

    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var last_time = wayland.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0.0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0.0;
    var last_presentation: ?presentation.Info = null;
    const dump_every = envU32("SNAIL_DEMO_DUMP_EVERY", 0);

    std.debug.print("snail - GPU text & vector rendering\n", .{});
    std.debug.print("Backend: {s}, HarfBuzz: {s}\n", .{
        active.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    renderer_driver.warnIfDebugCpu(active.kind());
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, B AA mode, C backend/threading, L dump repro, Esc quit\n", .{});
    std.debug.print("aa={s}\n", .{aaName(current_order)});

    while (!active.shouldClose()) {
        const now = wayland.getTime();
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
        _ = window.consumeMonitorChanged();

        const dump_repro = window.isKeyPressed(KEY_L);
        if (window.isKeyPressed(KEY_R)) rotate = !rotate;
        if (window.isKeyPressed(KEY_ESCAPE)) break;
        if (window.isKeyPressed(KEY_B)) {
            current_order = cycleSubpixelOrder(current_order);
            std.debug.print("\naa={s}\n", .{aaName(current_order)});
        }
        if (window.isKeyPressed(KEY_C)) {
            const next = renderer_driver.nextKind(active.kind());
            if (next != active.kind()) {
                releasePrepared(&prepared);
                active.deinit();
                active_valid = false;
                active = try renderer_driver.Driver.init(allocator, window, next);
                active_valid = true;
                uploaded_size = .{ 0, 0, 0, 0 };
                last_presentation = null;
                last_time = wayland.getTime();
                frame_count = 0;
                std.debug.print("\nBackend: {s}\n", .{active.backendName()});
                renderer_driver.warnIfDebugCpu(active.kind());
                continue;
            }
        }
        if (rotate) angle += dt * 0.5;
        if (window.isKeyDown(KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (window.isKeyDown(KEY_X)) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (window.isKeyDown(KEY_LEFT)) pan_x += pan_step;
        if (window.isKeyDown(KEY_RIGHT)) pan_x -= pan_step;
        if (window.isKeyDown(KEY_UP)) pan_y += pan_step;
        if (window.isKeyDown(KEY_DOWN)) pan_y -= pan_step;

        const present = active.presentationInfo();
        if (last_presentation == null or !std.meta.eql(last_presentation.?, present)) {
            logPresentationInfo(present);
            last_presentation = present;
        }
        const size = present.logical_size;
        const fb_size = present.framebuffer_size;
        const target_encoding = displayTargetEncoding(present);
        const linear_resolve = displayLinearResolve(active.kind(), target_encoding);
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        const viewport_w: f32 = @floatFromInt(fb_size[0]);
        const viewport_h: f32 = @floatFromInt(fb_size[1]);
        if (w < 1.0 or h < 1.0 or viewport_w < 1.0 or viewport_h < 1.0) continue;

        const layout = demo_banner.buildLayout(w, h);
        const snap_step = snail.pixelSteps(.{ w, h }, fb_size);
        const size_key = [4]u32{ size[0], size[1], fb_size[0], fb_size[1] };

        // On resize/backend switch: lay out text to collect decoration rects,
        // rebuild path picture, and rebuild immutable scene resources.
        const needs_resource_rebuild = prepared == null or path_picture == null or text_blob == null or !std.mem.eql(u32, size_key[0..], uploaded_size[0..]);
        if (needs_resource_rebuild) {
            releasePrepared(&prepared);
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
            const text_result = demo_banner_scene.buildTextBlob(&builder, layout, snap_step, &scene_assets, &dec_rects);

            text_blob = try builder.finish();
            path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, &scene_assets, dec_rects[0..text_result.decoration_count]);
            uploaded_size = size_key;

            var resource_entries: [8]snail.ResourceManifest.Entry = undefined;
            var resources = snail.ResourceManifest.init(&resource_entries);
            if (path_picture) |*picture| try resources.putPathPicture(.banner_paths, picture);
            const text_keys = if (text_blob) |*blob| keys: {
                const keys = snail.ResourceManifest.textBlobResourceKeys(.banner_fonts, .banner_text, blob);
                try resources.putTextBlob(keys, blob);
                break :keys keys;
            } else null;

            scene.reset();
            if (path_picture) |*picture| try scene.addPath(.{ .picture = picture, .resource_key = snail.ResourceKey.named("banner_paths") });
            if (text_blob) |*blob| try scene.addText(.{ .blob = blob, .resources = text_keys.? });
            var renderer = active.renderer();
            prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
        }

        const clear_srgb = demo_banner.clearColor();
        if (!active.beginFrame(fb_size, clear_srgb, target_encoding)) continue;

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
        if (dump_repro or (dump_every != 0 and frame_count % dump_every == 0)) {
            dumpReproFrame(frame_count, active.backendName(), current_order, present, target_encoding, linear_resolve, pan_x, pan_y, zoom, angle, projection, scene_transform, mvp);
        }
        const draw_state = snail.DrawState{
            .mvp = mvp,
            .surface = .{
                .pixel_width = viewport_w,
                .pixel_height = viewport_h,
                .encoding = target_encoding,
            },
            .raster = .{ .subpixel_order = if (present.will_resample) .none else current_order },
        };
        const needed = snail.DrawList.estimate(&scene);
        const needed_segments = snail.DrawList.estimateSegments(&scene);
        if (draw_buf.len < needed) {
            if (draw_buf.len > 0) allocator.free(draw_buf);
            draw_buf = try allocator.alloc(u32, needed);
        }
        if (draw_segments_buf.len < needed_segments) {
            if (draw_segments_buf.len > 0) allocator.free(draw_segments_buf);
            draw_segments_buf = try allocator.alloc(snail.DrawSegment, needed_segments);
        }
        var draw = snail.DrawList.init(draw_buf[0..needed], draw_segments_buf[0..needed_segments]);
        try draw.addScene(&prepared.?, &scene);
        if (linear_resolve) |resolve| {
            const restore = try active.beginLinearResolve(draw_state.surface, resolve);
            defer active.endLinearResolve(restore);
            try active.draw(&prepared.?, draw.slice(), draw_state);
        } else {
            try active.draw(&prepared.?, draw.slice(), draw_state);
        }

        if (frame_count == 2) {
            active.captureDebugFrame(allocator, fb_size);
        }
        if (frame_count % 60 == 0 and fps_display > 0.0) {
            const glyphs = if (text_blob) |*blob| blob.glyphCount() else 0;
            std.debug.print("\rFPS: {d:.0}  Backend: {s}  Glyphs: {}   ", .{ fps_display, active.backendName(), glyphs });
        }
        frame_count += 1;

        active.endFrame();
    }
}

test {
    _ = @import("snail");
}
