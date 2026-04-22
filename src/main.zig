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
        _ = snail.replaceAtlas(&atlas, try atlas.extendText(sample_text));
        return .{ .font = font, .atlas = atlas };
    }

    fn deinit(self: *ScriptFont) void {
        self.atlas.deinit();
        self.font.deinit();
    }
};

const demo_title_text = "snail";
const demo_subtitle_text = "GPU font rendering via direct Bezier curve evaluation";
const pulse_title_text = "scale pulse";
const pulse_caption_text = "shrinks and grows";
const tumble_title_text = "on the card";
const tumble_caption_text = "free text";

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

fn snapPx(value: f32) f32 {
    return @round(value);
}

fn snapRect(rect: snail.VectorRect) snail.VectorRect {
    return .{
        .x = snapPx(rect.x),
        .y = snapPx(rect.y),
        .w = snapPx(rect.w),
        .h = snapPx(rect.h),
    };
}

fn matScale(x: f32, y: f32, z: f32) snail.Mat4 {
    var m = snail.Mat4.identity;
    m.data[0] = x;
    m.data[5] = y;
    m.data[10] = z;
    return m;
}

fn matRotateX(angle_rad: f32) snail.Mat4 {
    const cos = @cos(angle_rad);
    const sin = @sin(angle_rad);
    var m = snail.Mat4.identity;
    m.data[5] = cos;
    m.data[6] = sin;
    m.data[9] = -sin;
    m.data[10] = cos;
    return m;
}

fn matRotateY(angle_rad: f32) snail.Mat4 {
    const cos = @cos(angle_rad);
    const sin = @sin(angle_rad);
    var m = snail.Mat4.identity;
    m.data[0] = cos;
    m.data[2] = -sin;
    m.data[8] = sin;
    m.data[10] = cos;
    return m;
}

fn matPixelPerspective(depth: f32) snail.Mat4 {
    var m = snail.Mat4.identity;
    m.data[11] = -1.0 / depth;
    return m;
}

fn centeredRect(w: f32, h: f32, center_y: f32) snail.VectorRect {
    return .{
        .x = -w * 0.5,
        .y = center_y - h * 0.5,
        .w = w,
        .h = h,
    };
}

fn measureStringAdvance(view: *const snail.AtlasView, font: *const snail.Font, text: []const u8, font_size: f32) f32 {
    var probe_buf: [64 * snail.FLOATS_PER_GLYPH]f32 = undefined;
    var probe = snail.Batch.init(&probe_buf);
    return probe.addString(view, font, text, 0, 0, font_size, .{ 1, 1, 1, 1 });
}

fn textYFromTop(h: f32, top_y: f32) f32 {
    return h - top_y;
}

const DemoLayout = struct {
    left_panel: snail.VectorRect,
    right_panel: snail.VectorRect,
    accent_pill: snail.VectorRect,
    pulse_panel: snail.VectorRect,
    tumble_panel: snail.VectorRect,
    orb_outer: snail.VectorRect,
    orb_inner: snail.VectorRect,
    footer_panel: snail.VectorRect,
    footer_bar_primary: snail.VectorRect,
    footer_bar_secondary: snail.VectorRect,
    title_baseline_top: f32,
    subtitle_baseline_top: f32,
    left_text_x: f32,
    right_text_x: f32,
    left_text_max_w: f32,
};

const DemoTextMetrics = struct {
    title_advance: f32,
    pulse_title_advance: f32,
    pulse_caption_advance: f32,
    tumble_title_advance: f32,
    tumble_caption_advance: f32,
};

fn buildDemoLayout(w: f32, h: f32, metrics: DemoTextMetrics) DemoLayout {
    const panel_margin = 18.0;
    const panel_gap = 16.0;
    const panel_top = 18.0;
    const panel_height = @max(h - 64.0, 240.0);
    const split_x = snapPx(w * 0.5);
    const left_panel = snapRect(.{
        .x = panel_margin,
        .y = panel_top,
        .w = split_x - panel_margin - panel_gap,
        .h = panel_height,
    });
    const right_panel = snapRect(.{
        .x = split_x,
        .y = panel_top,
        .w = w - split_x - panel_margin,
        .h = panel_height,
    });

    const orb_outer = snapRect(.{
        .x = right_panel.x + right_panel.w - 220,
        .y = right_panel.y + 36,
        .w = 180,
        .h = 180,
    });
    const orb_inner = snapRect(.{
        .x = orb_outer.x + (orb_outer.w - 96) * 0.5,
        .y = orb_outer.y + (orb_outer.h - 96) * 0.5,
        .w = 96,
        .h = 96,
    });

    const footer_panel = snapRect(.{
        .x = right_panel.x + 24,
        .y = right_panel.y + right_panel.h - 110,
        .w = right_panel.w - 48,
        .h = 92,
    });
    const left_text_x = left_panel.x + 12;
    const title_baseline_top = 70.0;
    const subtitle_baseline_top = 110.0;
    const pill_y = 18.0;
    const pill_x = left_text_x - 18.0;
    const accent_width = std.math.clamp(metrics.title_advance + 38.0, 160.0, left_panel.w - 34.0);
    const pulse_panel_h = std.math.clamp(left_panel.h * 0.22, 128.0, 156.0);
    const tumble_panel_h = std.math.clamp(right_panel.h * 0.26, 148.0, 176.0);
    const pulse_panel = snapRect(.{
        .x = left_panel.x + 24,
        .y = left_panel.y + left_panel.h - pulse_panel_h - 30,
        .w = left_panel.w - 48,
        .h = pulse_panel_h,
    });
    const tumble_panel = snapRect(.{
        .x = right_panel.x + 24,
        .y = footer_panel.y - tumble_panel_h - 14,
        .w = right_panel.w - 48,
        .h = tumble_panel_h,
    });

    return .{
        .left_panel = left_panel,
        .right_panel = right_panel,
        .accent_pill = snapRect(.{
            .x = pill_x,
            .y = pill_y,
            .w = accent_width,
            .h = 60,
        }),
        .pulse_panel = pulse_panel,
        .tumble_panel = tumble_panel,
        .orb_outer = orb_outer,
        .orb_inner = orb_inner,
        .footer_panel = footer_panel,
        .footer_bar_primary = snapRect(.{
            .x = footer_panel.x + 18,
            .y = footer_panel.y + 24,
            .w = footer_panel.w * 0.46,
            .h = 18,
        }),
        .footer_bar_secondary = snapRect(.{
            .x = footer_panel.x + 18,
            .y = footer_panel.y + 58,
            .w = footer_panel.w * 0.32,
            .h = 18,
        }),
        .title_baseline_top = title_baseline_top,
        .subtitle_baseline_top = subtitle_baseline_top,
        .left_text_x = left_text_x,
        .right_text_x = right_panel.x + 26,
        .left_text_max_w = left_panel.w - 24,
    };
}

fn buildPrimitiveShowcase(batch: *snail.VectorBatch, layout: DemoLayout) void {
    addRoundedRect(batch, layout.left_panel, .{ 0.08, 0.09, 0.11, 0.88 }, .{ 0.22, 0.24, 0.28, 1 }, 1.5, 24);
    addRoundedRect(batch, layout.right_panel, .{ 0.07, 0.08, 0.1, 0.82 }, .{ 0.18, 0.2, 0.24, 1 }, 1.5, 24);
    addRoundedRect(batch, layout.pulse_panel, .{ 0.07, 0.09, 0.12, 0.9 }, .{ 0.2, 0.24, 0.31, 0.9 }, 1.25, 18);
    addRoundedRect(batch, layout.tumble_panel, .{ 0.07, 0.09, 0.12, 0.9 }, .{ 0.2, 0.24, 0.31, 0.9 }, 1.25, 18);

    _ = batch.addEllipse(
        layout.orb_outer,
        .{ 0.28, 0.72, 0.92, 0.16 },
        .{ 0.28, 0.72, 0.92, 0.7 },
        2,
    );
    _ = batch.addEllipse(
        layout.orb_inner,
        .{ 0.95, 0.72, 0.24, 0.22 },
        .{ 0.95, 0.72, 0.24, 0.82 },
        1.5,
    );

    addRoundedRect(batch, layout.accent_pill, .{ 0.18, 0.46, 0.82, 0.22 }, .{ 0.18, 0.46, 0.82, 0.9 }, 1.5, 18);

    addRoundedRect(batch, layout.footer_panel, .{ 0.1, 0.12, 0.15, 0.9 }, .{ 0.3, 0.33, 0.4, 1 }, 1.5, 20);
    addRoundedRect(batch, layout.footer_bar_primary, .{ 0.28, 0.72, 0.92, 0.18 }, .{ 0.28, 0.72, 0.92, 0.85 }, 1, 9);
    addRoundedRect(batch, layout.footer_bar_secondary, .{ 0.96, 0.72, 0.28, 0.16 }, .{ 0.96, 0.72, 0.28, 0.82 }, 1, 9);
}

fn buildPulseAnimatedVectors(batch: *snail.VectorBatch, metrics: DemoTextMetrics) void {
    const chip_w = snapPx(@max(metrics.pulse_title_advance + 72.0, 210.0));
    const rule_w = snapPx(@max(metrics.pulse_caption_advance + 88.0, 250.0));
    const chip = centeredRect(chip_w, 54, -4);
    const rule = centeredRect(rule_w, 10, 42);
    const accent = centeredRect(18, 18, -2);
    addRoundedRect(batch, chip, .{ 0.2, 0.48, 0.86, 0.2 }, .{ 0.34, 0.7, 0.96, 0.9 }, 1.5, 16);
    addRoundedRect(batch, rule, .{ 0.86, 0.9, 0.96, 0.08 }, .{ 0.86, 0.9, 0.96, 0.3 }, 1, 5);
    _ = batch.addEllipse(
        .{
            .x = chip.x - 28,
            .y = accent.y,
            .w = accent.w,
            .h = accent.h,
        },
        .{ 0.96, 0.74, 0.28, 0.18 },
        .{ 0.96, 0.74, 0.28, 0.9 },
        1.25,
    );
}

fn buildTumbleAnimatedVectors(batch: *snail.VectorBatch, metrics: DemoTextMetrics) void {
    const halo_w = snapPx(@max(metrics.tumble_caption_advance + 96.0, 290.0));
    const plaque_w = snapPx(@max(metrics.tumble_title_advance + 84.0, 232.0));
    _ = batch.addEllipse(
        centeredRect(halo_w, 54, -46),
        .{ 0.28, 0.72, 0.92, 0.14 },
        .{ 0.28, 0.72, 0.92, 0.7 },
        1.5,
    );
    addRoundedRect(batch, centeredRect(plaque_w, 58, 18), .{ 0.16, 0.42, 0.78, 0.22 }, .{ 0.38, 0.76, 0.98, 0.92 }, 1.5, 16);
    _ = batch.addEllipse(
        .{ .x = plaque_w * 0.5 - 18, .y = 28, .w = 22, .h = 22 },
        .{ 0.96, 0.74, 0.28, 0.18 },
        .{ 0.96, 0.74, 0.28, 0.88 },
        1.25,
    );
}

fn buildPulseAnimatedText(batch: *snail.Batch, view: *const snail.AtlasView, font: *const snail.Font, metrics: DemoTextMetrics) void {
    _ = batch.addString(view, font, pulse_title_text, -metrics.pulse_title_advance * 0.5, 10, 28, .{ 1, 1, 1, 1 });
    _ = batch.addString(view, font, pulse_caption_text, -metrics.pulse_caption_advance * 0.5, -40, 17, .{ 0.72, 0.83, 0.92, 1 });
}

fn buildTumbleAnimatedText(batch: *snail.Batch, view: *const snail.AtlasView, font: *const snail.Font, metrics: DemoTextMetrics) void {
    _ = batch.addString(view, font, tumble_caption_text, -metrics.tumble_caption_advance * 0.5, 54, 22, .{ 0.72, 0.86, 0.95, 1 });
    _ = batch.addString(view, font, tumble_title_text, -metrics.tumble_title_advance * 0.5, -2, 30, .{ 1, 1, 1, 1 });
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

    const metrics: DemoTextMetrics = .{
        .title_advance = measureStringAdvance(atlas_view, &font, demo_title_text, 64),
        .pulse_title_advance = measureStringAdvance(atlas_view, &font, pulse_title_text, 28),
        .pulse_caption_advance = measureStringAdvance(atlas_view, &font, pulse_caption_text, 17),
        .tumble_title_advance = measureStringAdvance(atlas_view, &font, tumble_title_text, 30),
        .tumble_caption_advance = measureStringAdvance(atlas_view, &font, tumble_caption_text, 22),
    };

    // Vertex buffer: enough for ~10000 glyphs
    const buf_size = 10000 * snail.FLOATS_PER_GLYPH;
    const vbuf = try allocator.alloc(f32, buf_size);
    defer allocator.free(vbuf);
    const shape_buf = try allocator.alloc(f32, 256 * snail.VECTOR_FLOATS_PER_PRIMITIVE);
    defer allocator.free(shape_buf);

    var angle: f32 = 0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0;
    var pan_y: f32 = 0;
    var rotate = false;
    var stress_test = false;
    var anim_time: f32 = 0;
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
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, S stress, L subpixel order, Esc quit\n", .{});

    while (!platform.shouldClose()) {
        const now = platform.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;
        anim_time += dt;

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
        const KEY_LEFT = if (use_vulkan) platform.GLFW_KEY_LEFT else platform.c.GLFW_KEY_LEFT;
        const KEY_RIGHT = if (use_vulkan) platform.GLFW_KEY_RIGHT else platform.c.GLFW_KEY_RIGHT;
        const KEY_UP = if (use_vulkan) platform.GLFW_KEY_UP else platform.c.GLFW_KEY_UP;
        const KEY_DOWN = if (use_vulkan) platform.GLFW_KEY_DOWN else platform.c.GLFW_KEY_DOWN;

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
        if (w < 1 or h < 1) continue;
        const layout = buildDemoLayout(w, h, metrics);

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
        const pulse_center_x = layout.pulse_panel.x + layout.pulse_panel.w * 0.5;
        const pulse_center_y = layout.pulse_panel.y + layout.pulse_panel.h * 0.5;
        const pulse_scale = 1.0 + 0.18 * @sin(anim_time * 1.8);
        const pulse_vector_local = snail.Mat4.multiply(
            snail.Mat4.translate(pulse_center_x, pulse_center_y, 0),
            matScale(pulse_scale, pulse_scale, 1.0),
        );
        const pulse_text_local = snail.Mat4.multiply(
            snail.Mat4.translate(pulse_center_x, textYFromTop(h, pulse_center_y), 0),
            matScale(pulse_scale, pulse_scale, 1.0),
        );
        const pulse_vector_mvp = snail.Mat4.multiply(vector_projection, snail.Mat4.multiply(vector_scene_transform, pulse_vector_local));
        const pulse_text_mvp = snail.Mat4.multiply(projection, snail.Mat4.multiply(text_scene_transform, pulse_text_local));
        const tumble_center_x = layout.tumble_panel.x + layout.tumble_panel.w * 0.5;
        const tumble_center_y = layout.tumble_panel.y + layout.tumble_panel.h * 0.5;
        const tumble_depth = @max(layout.tumble_panel.w * 3.4, 960.0);
        const tumble_rotation = snail.Mat4.multiply(
            snail.Mat4.rotateZ(anim_time * 0.08),
            snail.Mat4.multiply(
                matRotateY(anim_time * 0.17),
                matRotateX(anim_time * 0.13),
            ),
        );
        const tumble_vector_local = snail.Mat4.multiply(
            snail.Mat4.translate(tumble_center_x, tumble_center_y, 0),
            snail.Mat4.multiply(matPixelPerspective(tumble_depth), tumble_rotation),
        );
        const tumble_text_local = snail.Mat4.multiply(
            snail.Mat4.translate(tumble_center_x, textYFromTop(h, tumble_center_y), 0),
            snail.Mat4.multiply(matPixelPerspective(tumble_depth), tumble_rotation),
        );
        const tumble_vector_mvp = snail.Mat4.multiply(vector_projection, snail.Mat4.multiply(vector_scene_transform, tumble_vector_local));
        const tumble_text_mvp = snail.Mat4.multiply(projection, snail.Mat4.multiply(text_scene_transform, tumble_text_local));

        const white = [4]f32{ 1, 1, 1, 1 };
        const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };
        const cyan = [4]f32{ 0.4, 0.8, 0.9, 1 };
        const yellow = [4]f32{ 0.9, 0.8, 0.3, 1 };
        const green = [4]f32{ 0.4, 0.9, 0.5, 1 };
        const pink = [4]f32{ 0.9, 0.5, 0.7, 1 };

        renderer.beginFrame();
        var shapes = snail.VectorBatch.init(shape_buf);
        buildPrimitiveShowcase(&shapes, layout);
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
            const col2_x = layout.right_text_x;
            const col1_max_w = layout.left_text_max_w;

            const subtitle_color = [4]f32{ 0.72, 0.83, 0.92, 1 };
            var y: f32 = textYFromTop(h, layout.title_baseline_top);

            // Title + subtitle
            _ = batch.addString(atlas_view, &font, demo_title_text, layout.left_text_x, y, 64, white);
            y = textYFromTop(h, layout.subtitle_baseline_top);
            _ = batch.addString(atlas_view, &font, demo_subtitle_text, layout.left_text_x, y, 14, subtitle_color);
            y -= 32;

            // Multi-size Latin — strings chosen so each line fits within col1_max_w
            const size_rows = [_]struct { fs: f32, text: []const u8 }{
                .{ .fs = 11, .text = "The quick brown fox jumps over the lazy dog 0123456789" },
                .{ .fs = 14, .text = "The quick brown fox jumps over the lazy dog" },
                .{ .fs = 20, .text = "The quick brown fox jumps over" },
                .{ .fs = 28, .text = "Pack my box with five" },
                .{ .fs = 40, .text = "How vexingly quick" },
            };
            for (size_rows) |row| {
                _ = batch.addString(atlas_view, &font, row.text, layout.left_text_x, y, row.fs, white);
                y -= row.fs * 1.4;
            }
            y -= 6;

            // Character sets
            _ = batch.addString(atlas_view, &font, "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", layout.left_text_x, y, 14, cyan);
            y -= 20;
            _ = batch.addString(atlas_view, &font, "abcdefghijklmnopqrstuvwxyz !@#$%^&*()", layout.left_text_x, y, 14, yellow);
            y -= 24;

            // Ligatures
            _ = batch.addString(atlas_view, &font, "fi fl ffi ffl office difficult affect", layout.left_text_x, y, 18, white);
            y -= 28;

            // Word-wrapped paragraph
            const paragraph = "Direct Bezier curve evaluation in the fragment shader produces " ++
                "resolution-independent text at any size, rotation, or perspective transform. " ++
                "No pre-rasterized glyph bitmaps, no signed distance fields.";
            _ = batch.addStringWrapped(atlas_view, &font, paragraph, layout.left_text_x, y, 12, col1_max_w, 17, gray);

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
        var total_glyphs = batch.glyphCount();

        if (!stress_test) {
            var pulse_shapes = snail.VectorBatch.init(shape_buf);
            buildPulseAnimatedVectors(&pulse_shapes, metrics);
            if (pulse_shapes.shapeCount() > 0) {
                renderer.drawVectorTransformed(pulse_shapes.slice(), pulse_vector_mvp, w, h);
            }

            var pulse_batch = snail.Batch.init(vbuf);
            buildPulseAnimatedText(&pulse_batch, atlas_view, &font, metrics);
            if (pulse_batch.glyphCount() > 0) {
                renderer.draw(pulse_batch.slice(), pulse_text_mvp, w, h);
            }
            total_glyphs += pulse_batch.glyphCount();

            var tumble_shapes = snail.VectorBatch.init(shape_buf);
            buildTumbleAnimatedVectors(&tumble_shapes, metrics);
            if (tumble_shapes.shapeCount() > 0) {
                renderer.drawVectorTransformed(tumble_shapes.slice(), tumble_vector_mvp, w, h);
            }

            var tumble_batch = snail.Batch.init(vbuf);
            buildTumbleAnimatedText(&tumble_batch, atlas_view, &font, metrics);
            if (tumble_batch.glyphCount() > 0) {
                renderer.draw(tumble_batch.slice(), tumble_text_mvp, w, h);
            }
            total_glyphs += tumble_batch.glyphCount();
        }

        // HUD (separate draw for different MVP)
        {
            var hud = snail.Batch.init(vbuf[batch.len..]);
            _ = hud.addString(atlas_view, &font, "snail - GPU Bezier curve font rendering", 10, 30, 12, gray);
            const hb_str = if (build_options.enable_harfbuzz) " | HarfBuzz ON" else "";
            const sp_name = renderer.subpixelOrder().name();
            var hud_line2_buf: [128]u8 = undefined;
            const hud_line2 = std.fmt.bufPrint(&hud_line2_buf, "Arrows pan | Z/X zoom | R rotate | S stress | L subpixel: {s}{s}", .{ sp_name, hb_str }) catch "Arrows pan | Z/X zoom | R rotate | S stress | L subpixel order";
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
