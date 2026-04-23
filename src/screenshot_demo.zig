const std = @import("std");
const snail = @import("snail.zig");
const assets = @import("assets");
const screenshot = @import("render/screenshot.zig");
const egl_offscreen = @import("render/egl_offscreen.zig");
const gl = @import("render/gl.zig").gl;

const SCREENSHOT_WIDTH: u32 = 1680;
const SCREENSHOT_HEIGHT: u32 = 760;
const SCREENSHOT_PATH = "zig-out/demo-screenshot.tga";
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;

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
const demo_subtitle_text = "Sharp forms. Quick rhythm.";
const demo_title_font_size = 58.0;
const demo_subtitle_font_size = 13.0;

const DemoLayout = struct {
    left_panel: snail.VectorRect,
    right_panel: snail.VectorRect,
    accent_pill: snail.VectorRect,
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
};

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

fn measureStringAdvance(atlas_like: anytype, font: *const snail.Font, text: []const u8, font_size: f32) f32 {
    var probe_buf: [64 * snail.FLOATS_PER_GLYPH]f32 = undefined;
    var probe = snail.Batch.init(&probe_buf);
    return probe.addString(atlas_like, font, text, 0, 0, font_size, .{ 1, 1, 1, 1 });
}

fn textYFromTop(h: f32, top_y: f32) f32 {
    return h - top_y;
}

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
    const left_text_x = left_panel.x + 24;
    const title_baseline_top = 78.0;
    const subtitle_baseline_top = 106.0;
    const pill_y = left_panel.y + 10.0;
    const pill_x = left_panel.x + 14.0;
    const accent_width = std.math.clamp(metrics.title_advance + 56.0, 180.0, left_panel.w - 26.0);
    return .{
        .left_panel = left_panel,
        .right_panel = right_panel,
        .accent_pill = snapRect(.{
            .x = pill_x,
            .y = pill_y,
            .w = accent_width,
            .h = 56,
        }),
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

fn addVectorSnail(builder: *snail.PathPictureBuilder, layout: DemoLayout) !void {
    const art_width = @min(layout.right_panel.w * 0.58, 430.0);
    const scale = art_width / 360.0;
    const art_height = 220.0 * scale;
    const vertical_gap = layout.footer_panel.y - layout.right_panel.y - art_height;
    const art_x = layout.right_panel.x + layout.right_panel.w - art_width - 36.0;
    const art_y = layout.right_panel.y + std.math.clamp(vertical_gap * 0.45, 54.0, 118.0);
    const transform = snail.VectorTransform2D.multiply(
        snail.VectorTransform2D.translate(art_x, art_y),
        snail.VectorTransform2D.scale(scale, scale),
    );

    try builder.addFilledEllipse(.{
        .x = 68,
        .y = 164,
        .w = 232,
        .h = 24,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 184, .y = 176 },
        .radius = 120,
        .inner_color = .{ 0.0, 0.0, 0.0, 0.18 },
        .outer_color = .{ 0.0, 0.0, 0.0, 0.0 },
    } } }, transform);
    try builder.addEllipse(.{
        .x = 142,
        .y = 10,
        .w = 144,
        .h = 144,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 214, .y = 82 },
        .radius = 92,
        .inner_color = .{ 0.28, 0.72, 0.92, 0.18 },
        .outer_color = .{ 0.28, 0.72, 0.92, 0.0 },
    } } }, .{ .color = .{ 0.28, 0.72, 0.92, 0.22 }, .width = 1.2, .join = .round }, transform);

    var body = snail.VectorPath.init(builder.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28, .y = 155 });
    try body.cubicTo(.{ .x = 62, .y = 132 }, .{ .x = 106, .y = 121 }, .{ .x = 142, .y = 127 });
    try body.cubicTo(.{ .x = 179, .y = 133 }, .{ .x = 210, .y = 151 }, .{ .x = 246, .y = 151 });
    try body.cubicTo(.{ .x = 288, .y = 151 }, .{ .x = 317, .y = 145 }, .{ .x = 332, .y = 131 });
    try body.cubicTo(.{ .x = 346, .y = 119 }, .{ .x = 345, .y = 104 }, .{ .x = 327, .y = 100 });
    try body.cubicTo(.{ .x = 307, .y = 96 }, .{ .x = 286, .y = 105 }, .{ .x = 278, .y = 119 });
    try body.cubicTo(.{ .x = 269, .y = 132 }, .{ .x = 252, .y = 136 }, .{ .x = 233, .y = 132 });
    try body.cubicTo(.{ .x = 210, .y = 126 }, .{ .x = 189, .y = 105 }, .{ .x = 166, .y = 92 });
    try body.cubicTo(.{ .x = 142, .y = 79 }, .{ .x = 106, .y = 84 }, .{ .x = 82, .y = 106 });
    try body.cubicTo(.{ .x = 58, .y = 127 }, .{ .x = 42, .y = 149 }, .{ .x = 28, .y = 155 });
    try body.close();
    try builder.addPath(&body, .{ .paint = .{ .linear_gradient = .{
        .start = .{ .x = 48, .y = 102 },
        .end = .{ .x = 320, .y = 158 },
        .start_color = .{ 0.88, 0.86, 0.78, 0.98 },
        .end_color = .{ 0.58, 0.63, 0.56, 0.98 },
    } } }, .{
        .color = .{ 0.9, 0.9, 0.84, 0.42 },
        .width = 2.0,
        .join = .round,
    }, transform);

    var belly = snail.VectorPath.init(builder.allocator);
    defer belly.deinit();
    try belly.moveTo(.{ .x = 92, .y = 140 });
    try belly.cubicTo(.{ .x = 138, .y = 132 }, .{ .x = 204, .y = 136 }, .{ .x = 274, .y = 142 });
    try builder.addStrokedPath(&belly, .{
        .color = .{ 1.0, 1.0, 1.0, 0.18 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    try builder.addEllipse(.{
        .x = 156,
        .y = 24,
        .w = 114,
        .h = 114,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 214, .y = 80 },
        .radius = 76,
        .inner_color = .{ 0.4, 0.76, 0.92, 0.44 },
        .outer_color = .{ 0.12, 0.22, 0.3, 0.92 },
    } } }, .{
        .color = .{ 0.52, 0.86, 0.98, 0.78 },
        .width = 2.4,
        .join = .round,
    }, transform);

    var spiral = snail.VectorPath.init(builder.allocator);
    defer spiral.deinit();
    try spiral.moveTo(.{ .x = 254, .y = 78 });
    try spiral.cubicTo(.{ .x = 248, .y = 44 }, .{ .x = 196, .y = 41 }, .{ .x = 178, .y = 72 });
    try spiral.cubicTo(.{ .x = 160, .y = 102 }, .{ .x = 178, .y = 138 }, .{ .x = 214, .y = 134 });
    try spiral.cubicTo(.{ .x = 247, .y = 130 }, .{ .x = 256, .y = 95 }, .{ .x = 235, .y = 81 });
    try spiral.cubicTo(.{ .x = 217, .y = 69 }, .{ .x = 195, .y = 83 }, .{ .x = 200, .y = 103 });
    try spiral.cubicTo(.{ .x = 204, .y = 118 }, .{ .x = 224, .y = 117 }, .{ .x = 229, .y = 104 });
    try builder.addStrokedPath(&spiral, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 252, .y = 60 },
            .end = .{ .x = 194, .y = 114 },
            .start_color = .{ 0.98, 0.86, 0.54, 0.92 },
            .end_color = .{ 0.94, 0.54, 0.28, 0.88 },
        } },
        .width = 9.0,
        .cap = .round,
        .join = .round,
    }, transform);

    var stalk_a = snail.VectorPath.init(builder.allocator);
    defer stalk_a.deinit();
    try stalk_a.moveTo(.{ .x = 308, .y = 100 });
    try stalk_a.quadTo(.{ .x = 316, .y = 76 }, .{ .x = 334, .y = 58 });
    try builder.addStrokedPath(&stalk_a, .{
        .color = .{ 0.86, 0.87, 0.8, 0.92 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    var stalk_b = snail.VectorPath.init(builder.allocator);
    defer stalk_b.deinit();
    try stalk_b.moveTo(.{ .x = 294, .y = 102 });
    try stalk_b.quadTo(.{ .x = 298, .y = 80 }, .{ .x = 306, .y = 64 });
    try builder.addStrokedPath(&stalk_b, .{
        .color = .{ 0.86, 0.87, 0.8, 0.82 },
        .width = 3.4,
        .cap = .round,
        .join = .round,
    }, transform);

    try builder.addFilledEllipse(.{ .x = 330, .y = 54, .w = 9, .h = 9 }, .{ .color = .{ 0.98, 0.96, 0.9, 0.95 } }, transform);
    try builder.addFilledEllipse(.{ .x = 303, .y = 61, .w = 7, .h = 7 }, .{ .color = .{ 0.98, 0.96, 0.9, 0.88 } }, transform);
    try builder.addFilledEllipse(.{ .x = 333, .y = 57, .w = 3, .h = 3 }, .{ .color = .{ 0.08, 0.08, 0.1, 0.95 } }, transform);
    try builder.addFilledEllipse(.{ .x = 305, .y = 63, .w = 2.5, .h = 2.5 }, .{ .color = .{ 0.08, 0.08, 0.1, 0.9 } }, transform);

    var smile = snail.VectorPath.init(builder.allocator);
    defer smile.deinit();
    try smile.moveTo(.{ .x = 314, .y = 119 });
    try smile.quadTo(.{ .x = 321, .y = 123 }, .{ .x = 329, .y = 119 });
    try builder.addStrokedPath(&smile, .{
        .color = .{ 0.18, 0.2, 0.22, 0.55 },
        .width = 2.0,
        .cap = .round,
        .join = .round,
    }, transform);
}

fn buildPathShowcase(builder: *snail.PathPictureBuilder, layout: DemoLayout) !void {
    try builder.addRoundedRect(
        layout.left_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.left_panel.x, .y = layout.left_panel.y },
            .end = .{ .x = layout.left_panel.x, .y = layout.left_panel.y + layout.left_panel.h },
            .start_color = .{ 0.1, 0.11, 0.14, 0.94 },
            .end_color = .{ 0.05, 0.06, 0.08, 0.9 },
        } } },
        .{ .color = .{ 0.22, 0.24, 0.28, 1.0 }, .width = 1.5, .join = .round, .placement = .inside },
        24,
        .identity,
    );
    try builder.addRoundedRect(
        layout.right_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.right_panel.x, .y = layout.right_panel.y },
            .end = .{ .x = layout.right_panel.x + layout.right_panel.w, .y = layout.right_panel.y + layout.right_panel.h },
            .start_color = .{ 0.08, 0.09, 0.12, 0.92 },
            .end_color = .{ 0.05, 0.06, 0.08, 0.82 },
        } } },
        .{ .color = .{ 0.18, 0.2, 0.24, 1.0 }, .width = 1.5, .join = .round, .placement = .inside },
        24,
        .identity,
    );

    try builder.addRoundedRect(
        layout.accent_pill,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.accent_pill.x, .y = layout.accent_pill.y },
            .end = .{ .x = layout.accent_pill.x + layout.accent_pill.w, .y = layout.accent_pill.y },
            .start_color = .{ 0.18, 0.46, 0.82, 0.28 },
            .end_color = .{ 0.34, 0.76, 0.95, 0.16 },
        } } },
        .{ .color = .{ 0.18, 0.46, 0.82, 0.9 }, .width = 1.5, .join = .round, .placement = .inside },
        16,
        .identity,
    );

    try builder.addRoundedRect(
        layout.footer_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.footer_panel.x, .y = layout.footer_panel.y },
            .end = .{ .x = layout.footer_panel.x, .y = layout.footer_panel.y + layout.footer_panel.h },
            .start_color = .{ 0.12, 0.14, 0.18, 0.94 },
            .end_color = .{ 0.08, 0.1, 0.13, 0.92 },
        } } },
        .{ .color = .{ 0.3, 0.33, 0.4, 1.0 }, .width = 1.5, .join = .round, .placement = .inside },
        20,
        .identity,
    );
    try builder.addRoundedRect(
        layout.footer_bar_primary,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.footer_bar_primary.x, .y = layout.footer_bar_primary.y },
            .end = .{ .x = layout.footer_bar_primary.x + layout.footer_bar_primary.w, .y = layout.footer_bar_primary.y },
            .start_color = .{ 0.28, 0.72, 0.92, 0.24 },
            .end_color = .{ 0.42, 0.84, 0.98, 0.08 },
        } } },
        .{ .color = .{ 0.28, 0.72, 0.92, 0.85 }, .width = 1.0, .join = .round, .placement = .inside },
        9,
        .identity,
    );
    try builder.addRoundedRect(
        layout.footer_bar_secondary,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.footer_bar_secondary.x, .y = layout.footer_bar_secondary.y },
            .end = .{ .x = layout.footer_bar_secondary.x + layout.footer_bar_secondary.w, .y = layout.footer_bar_secondary.y },
            .start_color = .{ 0.96, 0.72, 0.28, 0.22 },
            .end_color = .{ 0.98, 0.84, 0.42, 0.08 },
        } } },
        .{ .color = .{ 0.96, 0.72, 0.28, 0.82 }, .width = 1.0, .join = .round, .placement = .inside },
        9,
        .identity,
    );

    try addVectorSnail(builder, layout);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
    defer gl_ctx.deinit();

    var fbo: gl.GLuint = 0;
    var fbo_tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &fbo_tex);
    defer gl.glDeleteFramebuffers(1, &fbo);
    defer gl.glDeleteTextures(1, &fbo_tex);

    gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    gl.glViewport(0, 0, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);

    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();
    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    const arabic_text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7 \xd8\xa8\xd8\xa7\xd9\x84\xd8\xb9\xd8\xa7\xd9\x84\xd9\x85";
    const devanagari_text = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0";
    const mongolian_text = "\xe1\xa0\xae\xe1\xa0\xa4\xe1\xa0\xa9\xe1\xa0\xa0\xe1\xa0\xa4\xe1\xa0\xaf";
    const thai_text = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a";
    const emoji_text = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x89\xf0\x9f\x8c\x88\xf0\x9f\x98\x80\xf0\x9f\x94\xa5";

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

    var renderer = try snail.Renderer.init();
    defer renderer.deinit();
    renderer.setSubpixelOrder(.none);

    const metrics: DemoTextMetrics = .{
        .title_advance = measureStringAdvance(&atlas, &font, demo_title_text, demo_title_font_size),
    };

    const vbuf = try allocator.alloc(f32, 10000 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(vbuf);
    const path_buf = try allocator.alloc(f32, 256 * snail.FLOATS_PER_GLYPH);
    defer allocator.free(path_buf);

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const layout = buildDemoLayout(w, h, metrics);
    const projection = snail.Mat4.ortho(0, w, 0, h, -1, 1);
    const vector_projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);

    var picture_builder = snail.PathPictureBuilder.init(allocator);
    defer picture_builder.deinit();
    try buildPathShowcase(&picture_builder, layout);
    var path_picture = try picture_builder.freeze(allocator);
    defer path_picture.deinit();

    var atlas_views: [7]snail.AtlasView = undefined;
    renderer.uploadAtlases(&[_]*const snail.Atlas{
        &atlas,
        &arabic.atlas,
        &devanagari.atlas,
        &mongolian.atlas,
        &thai.atlas,
        &emoji.atlas,
        &path_picture.atlas,
    }, &atlas_views);
    const atlas_view = &atlas_views[0];
    const arabic_view = &atlas_views[1];
    const devanagari_view = &atlas_views[2];
    const mongolian_view = &atlas_views[3];
    const thai_view = &atlas_views[4];
    const emoji_view = &atlas_views[5];
    const path_view = &atlas_views[6];

    const white = [4]f32{ 1, 1, 1, 1 };
    const gray = [4]f32{ 0.6, 0.6, 0.65, 1 };
    const cyan = [4]f32{ 0.4, 0.8, 0.9, 1 };
    const yellow = [4]f32{ 0.9, 0.8, 0.3, 1 };
    const green = [4]f32{ 0.4, 0.9, 0.5, 1 };
    const pink = [4]f32{ 0.9, 0.5, 0.7, 1 };

    gl.glClearColor(0.12, 0.12, 0.14, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    renderer.beginFrame();

    var paths = snail.PathBatch.init(path_buf);
    _ = paths.addPicture(path_view, &path_picture);
    if (paths.shapeCount() > 0) {
        renderer.drawPaths(paths.slice(), vector_projection, w, h);
    }

    var batch = snail.Batch.init(vbuf);
    const col2_x = layout.right_text_x;
    const col1_max_w = layout.left_text_max_w;
    const subtitle_color = [4]f32{ 0.72, 0.83, 0.92, 1 };

    var y: f32 = textYFromTop(h, layout.title_baseline_top);
    _ = batch.addString(atlas_view, &font, demo_title_text, layout.left_text_x, y, demo_title_font_size, white);
    y = textYFromTop(h, layout.subtitle_baseline_top);
    _ = batch.addString(atlas_view, &font, demo_subtitle_text, layout.left_text_x, y, demo_subtitle_font_size, subtitle_color);
    y -= 24;

    _ = batch.addString(atlas_view, &font, "ZINC JAZZ / BRISK GLOW / 1979", layout.left_text_x, y, 14, cyan);
    y -= 20;
    _ = batch.addString(atlas_view, &font, "thin flicker, velvet hush, soft shuffle", layout.left_text_x, y, 14, yellow);
    y -= 24;
    _ = batch.addString(atlas_view, &font, "affine office shuffle cliff flora", layout.left_text_x, y, 18, white);
    y -= 30;

    const size_rows = [_]struct { fs: f32, text: []const u8 }{
        .{ .fs = 20, .text = "The wizard quickly jinxed the gnomes before they vaporized." },
        .{ .fs = 28, .text = "Sphinx of black quartz, judge my vow." },
        .{ .fs = 40, .text = "Waltz, bad nymph, for quick jigs vex." },
    };
    for (size_rows) |row| {
        _ = batch.addString(atlas_view, &font, row.text, layout.left_text_x, y, row.fs, white);
        y -= row.fs * 1.4;
    }
    y -= 10;

    const paragraph = "Quiet counters, brisk stems, bright edges. Fragments stack like poster scraps: clipped vows, quick glints, soft pauses.";
    _ = batch.addStringWrapped(atlas_view, &font, paragraph, layout.left_text_x, y, 12, col1_max_w, 17, gray);

    var sy: f32 = h - 70;
    const scripts = [_]struct { label: []const u8, text: []const u8, sf: *ScriptFont, color: [4]f32, view: *const snail.AtlasView }{
        .{ .label = "Arabic", .text = arabic_text, .sf = &arabic, .color = green, .view = arabic_view },
        .{ .label = "Devanagari", .text = devanagari_text, .sf = &devanagari, .color = cyan, .view = devanagari_view },
        .{ .label = "Thai", .text = thai_text, .sf = &thai, .color = yellow, .view = thai_view },
        .{ .label = "Mongolian", .text = mongolian_text, .sf = &mongolian, .color = pink, .view = mongolian_view },
        .{ .label = "Emoji", .text = emoji_text, .sf = &emoji, .color = white, .view = emoji_view },
    };
    for (scripts) |s| {
        _ = batch.addString(atlas_view, &font, s.label, col2_x, sy, 10, gray);
        sy -= 26;
        _ = batch.addString(s.view, &s.sf.font, s.text, col2_x, sy, 28, s.color);
        sy -= 40;
    }

    if (batch.glyphCount() > 0) {
        renderer.draw(batch.slice(), projection, w, h);
    }

    if (screenshot.captureFramebuffer(allocator, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT) catch null) |px| {
        defer allocator.free(px);
        screenshot.writeTga(SCREENSHOT_PATH, px, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
        std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}
