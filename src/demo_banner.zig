const std = @import("std");
const snail = @import("snail.zig");

pub const arabic_text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7 \xd8\xa8\xd8\xa7\xd9\x84\xd8\xb9\xd8\xa7\xd9\x84\xd9\x85"; // مرحبا بالعالم
pub const devanagari_text = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0"; // नमस्ते संसार
pub const mongolian_text = "\xe1\xa0\xae\xe1\xa0\xa4\xe1\xa0\xa9\xe1\xa0\xa0\xe1\xa0\xa4\xe1\xa0\xaf"; // ᠮᠤᠩᠠᠤᠯ
pub const thai_text = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a"; // สวัสดีครับ
pub const emoji_text = "\xe2\x9c\xa8 \xf0\x9f\x8c\x8d \xf0\x9f\x8e\xa8 \xf0\x9f\x9a\x80 \xf0\x9f\x90\x8c \xf0\x9f\x8c\x88 \xf0\x9f\x94\xa5"; // ✨ 🌍 🎨 🚀 🐌 🌈 🔥

pub const title_text = "snail";
pub const badge_text = "GPU text + vector atlas";
pub const subtitle_text = "One atlas for text, scripts, emoji, and paths.";
pub const ligature_label_text = "Ligatures";
pub const ligature_text = "office affine shuffle flow";
pub const ligature_caption_text = "ffi fi ffl fl, kerning, gradients, strokes";
pub const pangram_text = "Waltz, bad nymph, for quick jigs vex.";
pub const paragraph_text = "Bezier glyphs, frozen vector art, and color emoji share one renderer. This banner mixes Latin copy, complex scripts, layered paths, and the snail in one scene.";
pub const api_text = "Batch.addString  PathPicture.freeze  PathBatch.addPicture";
pub const scripts_heading_text = "Scripts + emoji";
pub const stage_label_text = "Frozen vectors";
pub const stage_title_text = "fills, gradients, inside strokes";
pub const stage_caption_text = "frozen once, instanced per frame";
pub const stage_pill_labels = [_][]const u8{
    "rounded rect",
    "ellipse",
    "cubic path",
};

const ink = [4]f32{ 0.95, 0.97, 0.99, 1.0 };
const mist = [4]f32{ 0.66, 0.75, 0.82, 1.0 };
const slate = [4]f32{ 0.45, 0.53, 0.60, 1.0 };
const teal = [4]f32{ 0.42, 0.84, 0.87, 1.0 };
const sand = [4]f32{ 0.96, 0.82, 0.55, 1.0 };
const coral = [4]f32{ 0.95, 0.58, 0.42, 1.0 };
const sage = [4]f32{ 0.60, 0.84, 0.66, 1.0 };
const blush = [4]f32{ 0.87, 0.60, 0.76, 1.0 };

pub fn clearColor() [4]f32 {
    return .{ 0.04, 0.05, 0.07, 1.0 };
}

pub const ScriptFont = struct {
    font: snail.Font,
    atlas: snail.Atlas,

    pub fn init(allocator: std.mem.Allocator, data: []const u8, sample_text: []const u8) !ScriptFont {
        var font = try snail.Font.init(data);
        var atlas = try snail.Atlas.init(allocator, &font, &.{});
        _ = snail.replaceAtlas(&atlas, try atlas.extendText(sample_text));
        return .{ .font = font, .atlas = atlas };
    }

    pub fn deinit(self: *ScriptFont) void {
        self.atlas.deinit();
        self.font.deinit();
    }
};

pub const TextMetrics = struct {
    badge_advance: f32,
};

pub const Layout = struct {
    canvas: snail.VectorRect,
    hero_panel: snail.VectorRect,
    specimen_panel: snail.VectorRect,
    script_panel: snail.VectorRect,
    stage_panel: snail.VectorRect,
    badge_pill: snail.VectorRect,
    emoji_pill: snail.VectorRect,
    script_rows: [4]snail.VectorRect,
    stage_pills: [3]snail.VectorRect,
};

pub const TextResources = struct {
    latin_font: *const snail.Font,
    latin_view: *const snail.AtlasView,
    arabic_font: *const ScriptFont,
    arabic_view: *const snail.AtlasView,
    devanagari_font: *const ScriptFont,
    devanagari_view: *const snail.AtlasView,
    mongolian_font: *const ScriptFont,
    mongolian_view: *const snail.AtlasView,
    thai_font: *const ScriptFont,
    thai_view: *const snail.AtlasView,
    emoji_font: *const ScriptFont,
    emoji_view: *const snail.AtlasView,
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

fn insetRect(rect: snail.VectorRect, dx: f32, dy: f32) snail.VectorRect {
    return snapRect(.{
        .x = rect.x + dx,
        .y = rect.y + dy,
        .w = rect.w - dx * 2.0,
        .h = rect.h - dy * 2.0,
    });
}

fn textYFromTop(h: f32, top_y: f32) f32 {
    return h - top_y;
}

fn measureStringAdvance(atlas_like: anytype, font: *const snail.Font, text: []const u8, font_size: f32) f32 {
    var probe_buf: [128 * snail.FLOATS_PER_GLYPH]f32 = undefined;
    var probe = snail.Batch.init(&probe_buf);
    return probe.addString(atlas_like, font, text, 0, 0, font_size, ink);
}

pub fn measureMetrics(atlas_like: anytype, font: *const snail.Font) TextMetrics {
    return .{
        .badge_advance = measureStringAdvance(atlas_like, font, badge_text, 13.0),
    };
}

pub fn buildLayout(w: f32, h: f32, metrics: TextMetrics) Layout {
    const margin_x = snapPx(@max(28.0, w * 0.022));
    const margin_y = snapPx(@max(28.0, h * 0.045));
    const gutter = snapPx(@max(22.0, w * 0.015));
    const hero_w = snapPx(std.math.clamp(w * 0.39, 440.0, 710.0));
    const hero_panel = snapRect(.{
        .x = margin_x,
        .y = margin_y,
        .w = hero_w,
        .h = h - margin_y * 2.0,
    });
    const right_x = hero_panel.x + hero_panel.w + gutter;
    const right_w = w - right_x - margin_x;
    const script_panel = snapRect(.{
        .x = right_x,
        .y = margin_y + 10.0,
        .w = right_w,
        .h = std.math.clamp(h * 0.37, 250.0, 320.0),
    });
    const stage_panel = snapRect(.{
        .x = right_x + 20.0,
        .y = script_panel.y + script_panel.h + 22.0,
        .w = right_w - 20.0,
        .h = h - (script_panel.y + script_panel.h + 22.0) - margin_y,
    });
    const specimen_panel = snapRect(.{
        .x = hero_panel.x + 24.0,
        .y = hero_panel.y + hero_panel.h - std.math.clamp(hero_panel.h * 0.42, 260.0, 320.0) - 24.0,
        .w = hero_panel.w - 48.0,
        .h = std.math.clamp(hero_panel.h * 0.42, 260.0, 320.0),
    });
    const badge_pill = snapRect(.{
        .x = hero_panel.x + 26.0,
        .y = hero_panel.y + 24.0,
        .w = std.math.clamp(metrics.badge_advance + 40.0, 220.0, hero_panel.w - 80.0),
        .h = 34.0,
    });
    const emoji_pill = snapRect(.{
        .x = script_panel.x + 22.0,
        .y = script_panel.y + script_panel.h - 62.0,
        .w = script_panel.w - 44.0,
        .h = 40.0,
    });

    const script_top = script_panel.y + 70.0;
    const script_bottom = emoji_pill.y - 16.0;
    const row_gap = 10.0;
    const row_h = (script_bottom - script_top - row_gap * 3.0) / 4.0;
    var script_rows: [4]snail.VectorRect = undefined;
    for (&script_rows, 0..) |*row, i| {
        row.* = snapRect(.{
            .x = script_panel.x + 22.0,
            .y = script_top + @as(f32, @floatFromInt(i)) * (row_h + row_gap),
            .w = script_panel.w - 44.0,
            .h = row_h,
        });
    }

    const pill_x = stage_panel.x + 42.0;
    const pill_y = stage_panel.y + stage_panel.h - 122.0;
    const pill_w = std.math.clamp(stage_panel.w * 0.34, 180.0, 260.0);
    var stage_pills: [3]snail.VectorRect = undefined;
    stage_pills[0] = snapRect(.{ .x = pill_x, .y = pill_y, .w = pill_w, .h = 28.0 });
    stage_pills[1] = snapRect(.{ .x = pill_x, .y = pill_y + 38.0, .w = pill_w * 0.82, .h = 28.0 });
    stage_pills[2] = snapRect(.{ .x = pill_x, .y = pill_y + 76.0, .w = pill_w * 0.68, .h = 28.0 });

    return .{
        .canvas = .{ .x = 0, .y = 0, .w = w, .h = h },
        .hero_panel = hero_panel,
        .specimen_panel = specimen_panel,
        .script_panel = script_panel,
        .stage_panel = stage_panel,
        .badge_pill = badge_pill,
        .emoji_pill = emoji_pill,
        .script_rows = script_rows,
        .stage_pills = stage_pills,
    };
}

pub fn drawText(batch: *snail.Batch, h: f32, layout: Layout, resources: TextResources) void {
    const hero_x = layout.hero_panel.x + 30.0;
    const title_size = std.math.clamp(layout.hero_panel.w * 0.16, 82.0, 118.0);
    const subtitle_size = std.math.clamp(layout.hero_panel.w * 0.033, 18.0, 24.0);
    const ligature_size = std.math.clamp(layout.specimen_panel.w * 0.072, 34.0, 48.0);
    const body_size = std.math.clamp(layout.specimen_panel.w * 0.026, 13.0, 16.0);

    _ = batch.addString(resources.latin_view, resources.latin_font, badge_text, layout.badge_pill.x + 16.0, textYFromTop(h, layout.badge_pill.y + 22.0), 13.0, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, title_text, hero_x, textYFromTop(h, layout.hero_panel.y + 126.0), title_size, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, subtitle_text, hero_x, textYFromTop(h, layout.hero_panel.y + 172.0), subtitle_size, mist);
    _ = batch.addString(resources.latin_view, resources.latin_font, "Bezier text rendering", hero_x, textYFromTop(h, layout.hero_panel.y + 214.0), 14.0, slate);

    const specimen_x = layout.specimen_panel.x + 24.0;
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_label_text, specimen_x, textYFromTop(h, layout.specimen_panel.y + 26.0), 12.0, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_text, specimen_x, textYFromTop(h, layout.specimen_panel.y + 76.0), ligature_size, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_caption_text, specimen_x, textYFromTop(h, layout.specimen_panel.y + 108.0), 14.0, sand);
    _ = batch.addString(resources.latin_view, resources.latin_font, pangram_text, specimen_x, textYFromTop(h, layout.specimen_panel.y + 148.0), 18.0, ink);
    _ = batch.addStringWrapped(
        resources.latin_view,
        resources.latin_font,
        paragraph_text,
        specimen_x,
        textYFromTop(h, layout.specimen_panel.y + 182.0),
        body_size,
        layout.specimen_panel.w - 48.0,
        body_size * 1.45,
        mist,
    );
    _ = batch.addString(resources.latin_view, resources.latin_font, api_text, specimen_x, textYFromTop(h, layout.specimen_panel.y + layout.specimen_panel.h - 22.0), 12.0, slate);

    _ = batch.addString(resources.latin_view, resources.latin_font, scripts_heading_text, layout.script_panel.x + 26.0, textYFromTop(h, layout.script_panel.y + 30.0), 13.0, teal);

    const script_items = [_]struct {
        label: []const u8,
        text: []const u8,
        font: *const ScriptFont,
        view: *const snail.AtlasView,
        color: [4]f32,
        size: f32,
    }{
        .{ .label = "Arabic", .text = arabic_text, .font = resources.arabic_font, .view = resources.arabic_view, .color = sage, .size = 29.0 },
        .{ .label = "Devanagari", .text = devanagari_text, .font = resources.devanagari_font, .view = resources.devanagari_view, .color = teal, .size = 27.0 },
        .{ .label = "Thai", .text = thai_text, .font = resources.thai_font, .view = resources.thai_view, .color = sand, .size = 28.0 },
        .{ .label = "Mongolian", .text = mongolian_text, .font = resources.mongolian_font, .view = resources.mongolian_view, .color = blush, .size = 30.0 },
    };
    for (layout.script_rows, script_items) |row, item| {
        _ = batch.addString(resources.latin_view, resources.latin_font, item.label, row.x + 18.0, textYFromTop(h, row.y + 20.0), 11.0, slate);
        _ = batch.addString(item.view, &item.font.font, item.text, row.x + 170.0, textYFromTop(h, row.y + row.h - 12.0), item.size, item.color);
    }

    _ = batch.addString(resources.latin_view, resources.latin_font, "Emoji", layout.emoji_pill.x + 16.0, textYFromTop(h, layout.emoji_pill.y + 18.0), 11.0, slate);
    _ = batch.addString(resources.emoji_view, &resources.emoji_font.font, emoji_text, layout.emoji_pill.x + 150.0, textYFromTop(h, layout.emoji_pill.y + layout.emoji_pill.h - 8.0), 30.0, ink);

    _ = batch.addString(resources.latin_view, resources.latin_font, stage_label_text, layout.stage_panel.x + 42.0, textYFromTop(h, layout.stage_panel.y + 48.0), 12.0, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, stage_title_text, layout.stage_panel.x + 42.0, textYFromTop(h, layout.stage_panel.y + 82.0), 23.0, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, stage_caption_text, layout.stage_panel.x + 42.0, textYFromTop(h, layout.stage_panel.y + 108.0), 14.0, mist);
    for (layout.stage_pills, stage_pill_labels) |pill, label| {
        _ = batch.addString(resources.latin_view, resources.latin_font, label, pill.x + 16.0, textYFromTop(h, pill.y + 19.0), 12.0, ink);
    }
}

pub fn buildPathShowcase(builder: *snail.PathPictureBuilder, layout: Layout) !void {
    try builder.addRoundedRect(
        layout.canvas,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = layout.canvas.w, .y = layout.canvas.h },
            .start_color = .{ 0.07, 0.09, 0.12, 1.0 },
            .end_color = .{ 0.03, 0.04, 0.06, 1.0 },
        } } },
        null,
        0.0,
        .identity,
    );

    try builder.addFilledEllipse(.{
        .x = layout.hero_panel.x - 60.0,
        .y = layout.hero_panel.y - 40.0,
        .w = layout.hero_panel.w * 0.95,
        .h = layout.hero_panel.h * 0.68,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = layout.hero_panel.x + layout.hero_panel.w * 0.28, .y = layout.hero_panel.y + layout.hero_panel.h * 0.18 },
        .radius = layout.hero_panel.w * 0.46,
        .inner_color = .{ 0.16, 0.34, 0.56, 0.30 },
        .outer_color = .{ 0.16, 0.34, 0.56, 0.0 },
    } } }, .identity);
    try builder.addFilledEllipse(.{
        .x = layout.stage_panel.x + layout.stage_panel.w * 0.24,
        .y = layout.stage_panel.y - 60.0,
        .w = layout.stage_panel.w * 0.84,
        .h = layout.stage_panel.h * 0.92,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = layout.stage_panel.x + layout.stage_panel.w * 0.72, .y = layout.stage_panel.y + layout.stage_panel.h * 0.34 },
        .radius = layout.stage_panel.w * 0.42,
        .inner_color = .{ 0.10, 0.24, 0.44, 0.24 },
        .outer_color = .{ 0.10, 0.24, 0.44, 0.0 },
    } } }, .identity);

    try builder.addRoundedRect(
        layout.hero_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.hero_panel.x, .y = layout.hero_panel.y },
            .end = .{ .x = layout.hero_panel.x + layout.hero_panel.w * 0.9, .y = layout.hero_panel.y + layout.hero_panel.h },
            .start_color = .{ 0.07, 0.11, 0.16, 0.96 },
            .end_color = .{ 0.04, 0.07, 0.10, 0.96 },
        } } },
        .{ .color = .{ 0.23, 0.31, 0.39, 1.0 }, .width = 1.5, .join = .round, .placement = .inside },
        34.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.specimen_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.specimen_panel.x, .y = layout.specimen_panel.y },
            .end = .{ .x = layout.specimen_panel.x, .y = layout.specimen_panel.y + layout.specimen_panel.h },
            .start_color = .{ 0.08, 0.10, 0.13, 0.96 },
            .end_color = .{ 0.04, 0.05, 0.07, 0.96 },
        } } },
        .{ .color = .{ 0.19, 0.24, 0.29, 1.0 }, .width = 1.2, .join = .round, .placement = .inside },
        24.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.script_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.script_panel.x, .y = layout.script_panel.y },
            .end = .{ .x = layout.script_panel.x + layout.script_panel.w, .y = layout.script_panel.y + layout.script_panel.h },
            .start_color = .{ 0.08, 0.09, 0.12, 0.96 },
            .end_color = .{ 0.04, 0.05, 0.07, 0.94 },
        } } },
        .{ .color = .{ 0.20, 0.24, 0.30, 1.0 }, .width = 1.4, .join = .round, .placement = .inside },
        28.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.stage_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.stage_panel.x, .y = layout.stage_panel.y },
            .end = .{ .x = layout.stage_panel.x + layout.stage_panel.w, .y = layout.stage_panel.y + layout.stage_panel.h },
            .start_color = .{ 0.08, 0.10, 0.12, 0.95 },
            .end_color = .{ 0.04, 0.06, 0.08, 0.94 },
        } } },
        .{ .color = .{ 0.19, 0.23, 0.29, 1.0 }, .width = 1.4, .join = .round, .placement = .inside },
        34.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.badge_pill,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.badge_pill.x, .y = layout.badge_pill.y },
            .end = .{ .x = layout.badge_pill.x + layout.badge_pill.w, .y = layout.badge_pill.y },
            .start_color = .{ 0.12, 0.28, 0.40, 0.94 },
            .end_color = .{ 0.08, 0.18, 0.28, 0.94 },
        } } },
        .{ .color = .{ 0.34, 0.74, 0.78, 0.92 }, .width = 1.0, .join = .round, .placement = .inside },
        17.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.emoji_pill,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.emoji_pill.x, .y = layout.emoji_pill.y },
            .end = .{ .x = layout.emoji_pill.x + layout.emoji_pill.w, .y = layout.emoji_pill.y },
            .start_color = .{ 0.12, 0.14, 0.18, 0.94 },
            .end_color = .{ 0.08, 0.09, 0.12, 0.94 },
        } } },
        .{ .color = .{ 0.22, 0.28, 0.34, 1.0 }, .width = 1.0, .join = .round, .placement = .inside },
        18.0,
        .identity,
    );

    const row_colors = [_]struct {
        start: [4]f32,
        end: [4]f32,
        stroke: [4]f32,
    }{
        .{ .start = .{ 0.08, 0.11, 0.10, 0.94 }, .end = .{ 0.05, 0.07, 0.07, 0.94 }, .stroke = .{ 0.30, 0.42, 0.34, 1.0 } },
        .{ .start = .{ 0.08, 0.11, 0.13, 0.94 }, .end = .{ 0.05, 0.07, 0.08, 0.94 }, .stroke = .{ 0.24, 0.40, 0.42, 1.0 } },
        .{ .start = .{ 0.12, 0.11, 0.08, 0.94 }, .end = .{ 0.08, 0.07, 0.05, 0.94 }, .stroke = .{ 0.42, 0.36, 0.24, 1.0 } },
        .{ .start = .{ 0.11, 0.08, 0.12, 0.94 }, .end = .{ 0.07, 0.05, 0.09, 0.94 }, .stroke = .{ 0.40, 0.28, 0.40, 1.0 } },
    };
    for (layout.script_rows, row_colors) |row, colors| {
        try builder.addRoundedRect(
            row,
            .{ .paint = .{ .linear_gradient = .{
                .start = .{ .x = row.x, .y = row.y },
                .end = .{ .x = row.x + row.w, .y = row.y },
                .start_color = colors.start,
                .end_color = colors.end,
            } } },
            .{ .color = colors.stroke, .width = 1.0, .join = .round, .placement = .inside },
            18.0,
            .identity,
        );
    }

    const pill_colors = [_]struct {
        start: [4]f32,
        end: [4]f32,
        stroke: [4]f32,
    }{
        .{ .start = .{ 0.18, 0.40, 0.42, 0.90 }, .end = .{ 0.10, 0.22, 0.24, 0.90 }, .stroke = .{ 0.46, 0.84, 0.86, 0.92 } },
        .{ .start = .{ 0.40, 0.32, 0.14, 0.90 }, .end = .{ 0.22, 0.18, 0.08, 0.90 }, .stroke = .{ 0.96, 0.82, 0.55, 0.92 } },
        .{ .start = .{ 0.38, 0.20, 0.12, 0.90 }, .end = .{ 0.22, 0.10, 0.08, 0.90 }, .stroke = .{ 0.95, 0.58, 0.42, 0.92 } },
    };
    for (layout.stage_pills, pill_colors) |pill, colors| {
        try builder.addRoundedRect(
            pill,
            .{ .paint = .{ .linear_gradient = .{
                .start = .{ .x = pill.x, .y = pill.y },
                .end = .{ .x = pill.x + pill.w, .y = pill.y },
                .start_color = colors.start,
                .end_color = colors.end,
            } } },
            .{ .color = colors.stroke, .width = 1.0, .join = .round, .placement = .inside },
            pill.h * 0.5,
            .identity,
        );
    }

    const hero_glow = snapRect(.{
        .x = layout.hero_panel.x + layout.hero_panel.w - 230.0,
        .y = layout.hero_panel.y + 36.0,
        .w = 240.0,
        .h = 240.0,
    });
    try builder.addFilledEllipse(hero_glow, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = hero_glow.x + hero_glow.w * 0.44, .y = hero_glow.y + hero_glow.h * 0.44 },
        .radius = hero_glow.w * 0.42,
        .inner_color = .{ 0.30, 0.80, 0.92, 0.22 },
        .outer_color = .{ 0.30, 0.80, 0.92, 0.0 },
    } } }, .identity);

    const orbit_outer = snapRect(.{
        .x = layout.stage_panel.x + layout.stage_panel.w - std.math.clamp(layout.stage_panel.w * 0.46, 280.0, 360.0) - 58.0,
        .y = layout.stage_panel.y + 22.0,
        .w = std.math.clamp(layout.stage_panel.w * 0.46, 280.0, 360.0),
        .h = std.math.clamp(layout.stage_panel.h * 0.78, 220.0, 300.0),
    });
    const orbit_inner = insetRect(orbit_outer, orbit_outer.w * 0.16, orbit_outer.h * 0.16);
    try builder.addEllipse(
        orbit_outer,
        .{ .paint = .{ .radial_gradient = .{
            .center = .{ .x = orbit_outer.x + orbit_outer.w * 0.5, .y = orbit_outer.y + orbit_outer.h * 0.45 },
            .radius = orbit_outer.w * 0.42,
            .inner_color = .{ 0.22, 0.56, 0.74, 0.18 },
            .outer_color = .{ 0.22, 0.56, 0.74, 0.0 },
        } } },
        .{ .color = .{ 0.34, 0.74, 0.78, 0.36 }, .width = 1.4, .join = .round },
        .identity,
    );
    try builder.addEllipse(
        orbit_inner,
        .{ .paint = .{ .radial_gradient = .{
            .center = .{ .x = orbit_inner.x + orbit_inner.w * 0.5, .y = orbit_inner.y + orbit_inner.h * 0.48 },
            .radius = orbit_inner.w * 0.36,
            .inner_color = .{ 0.96, 0.82, 0.55, 0.14 },
            .outer_color = .{ 0.96, 0.82, 0.55, 0.0 },
        } } },
        .{ .color = .{ 0.96, 0.82, 0.55, 0.30 }, .width = 1.2, .join = .round },
        .identity,
    );

    var hero_ribbon = snail.VectorPath.init(builder.allocator);
    defer hero_ribbon.deinit();
    try hero_ribbon.moveTo(.{ .x = layout.hero_panel.x + 46.0, .y = layout.hero_panel.y + 252.0 });
    try hero_ribbon.cubicTo(
        .{ .x = layout.hero_panel.x + 156.0, .y = layout.hero_panel.y + 196.0 },
        .{ .x = layout.hero_panel.x + 324.0, .y = layout.hero_panel.y + 282.0 },
        .{ .x = layout.hero_panel.x + 458.0, .y = layout.hero_panel.y + 236.0 },
    );
    try hero_ribbon.cubicTo(
        .{ .x = layout.hero_panel.x + 520.0, .y = layout.hero_panel.y + 214.0 },
        .{ .x = layout.hero_panel.x + 578.0, .y = layout.hero_panel.y + 170.0 },
        .{ .x = layout.hero_panel.x + layout.hero_panel.w - 34.0, .y = layout.hero_panel.y + 146.0 },
    );
    try builder.addStrokedPath(&hero_ribbon, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.hero_panel.x + 46.0, .y = layout.hero_panel.y + 252.0 },
            .end = .{ .x = layout.hero_panel.x + layout.hero_panel.w - 34.0, .y = layout.hero_panel.y + 146.0 },
            .start_color = .{ 0.95, 0.58, 0.42, 0.62 },
            .end_color = .{ 0.42, 0.84, 0.87, 0.42 },
        } },
        .width = 14.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    var stage_arc = snail.VectorPath.init(builder.allocator);
    defer stage_arc.deinit();
    try stage_arc.moveTo(.{ .x = layout.stage_panel.x + 42.0, .y = layout.stage_panel.y + 138.0 });
    try stage_arc.cubicTo(
        .{ .x = layout.stage_panel.x + 132.0, .y = layout.stage_panel.y + 92.0 },
        .{ .x = layout.stage_panel.x + 272.0, .y = layout.stage_panel.y + 102.0 },
        .{ .x = layout.stage_panel.x + 372.0, .y = layout.stage_panel.y + 148.0 },
    );
    try stage_arc.cubicTo(
        .{ .x = layout.stage_panel.x + 460.0, .y = layout.stage_panel.y + 188.0 },
        .{ .x = layout.stage_panel.x + 578.0, .y = layout.stage_panel.y + 190.0 },
        .{ .x = layout.stage_panel.x + 676.0, .y = layout.stage_panel.y + 132.0 },
    );
    try builder.addStrokedPath(&stage_arc, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.stage_panel.x + 42.0, .y = layout.stage_panel.y + 138.0 },
            .end = .{ .x = layout.stage_panel.x + 676.0, .y = layout.stage_panel.y + 132.0 },
            .start_color = .{ 0.42, 0.84, 0.87, 0.34 },
            .end_color = .{ 0.96, 0.82, 0.55, 0.24 },
        } },
        .width = 8.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    try addVectorSnail(builder, layout.stage_panel);
}

fn addVectorSnail(builder: *snail.PathPictureBuilder, stage_panel: snail.VectorRect) !void {
    const art_width = @min(stage_panel.w * 0.58, 520.0);
    const scale = art_width / 360.0;
    const art_height = 220.0 * scale;
    const art_x = stage_panel.x + stage_panel.w - art_width - 26.0;
    const art_y = stage_panel.y + stage_panel.h - art_height - 24.0;
    const transform = snail.VectorTransform2D.multiply(
        snail.VectorTransform2D.translate(art_x, art_y),
        snail.VectorTransform2D.scale(scale, scale),
    );

    try builder.addFilledEllipse(.{
        .x = 62.0,
        .y = 168.0,
        .w = 240.0,
        .h = 24.0,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 182.0, .y = 180.0 },
        .radius = 122.0,
        .inner_color = .{ 0.0, 0.0, 0.0, 0.18 },
        .outer_color = .{ 0.0, 0.0, 0.0, 0.0 },
    } } }, transform);
    try builder.addEllipse(.{
        .x = 144.0,
        .y = 10.0,
        .w = 146.0,
        .h = 146.0,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 216.0, .y = 84.0 },
        .radius = 96.0,
        .inner_color = .{ 0.28, 0.72, 0.92, 0.18 },
        .outer_color = .{ 0.28, 0.72, 0.92, 0.0 },
    } } }, .{ .color = .{ 0.28, 0.72, 0.92, 0.24 }, .width = 1.2, .join = .round }, transform);

    var body = snail.VectorPath.init(builder.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28.0, .y = 155.0 });
    try body.cubicTo(.{ .x = 62.0, .y = 132.0 }, .{ .x = 106.0, .y = 121.0 }, .{ .x = 142.0, .y = 127.0 });
    try body.cubicTo(.{ .x = 179.0, .y = 133.0 }, .{ .x = 210.0, .y = 151.0 }, .{ .x = 246.0, .y = 151.0 });
    try body.cubicTo(.{ .x = 288.0, .y = 151.0 }, .{ .x = 317.0, .y = 145.0 }, .{ .x = 332.0, .y = 131.0 });
    try body.cubicTo(.{ .x = 346.0, .y = 119.0 }, .{ .x = 345.0, .y = 104.0 }, .{ .x = 327.0, .y = 100.0 });
    try body.cubicTo(.{ .x = 307.0, .y = 96.0 }, .{ .x = 286.0, .y = 105.0 }, .{ .x = 278.0, .y = 119.0 });
    try body.cubicTo(.{ .x = 269.0, .y = 132.0 }, .{ .x = 252.0, .y = 136.0 }, .{ .x = 233.0, .y = 132.0 });
    try body.cubicTo(.{ .x = 210.0, .y = 126.0 }, .{ .x = 189.0, .y = 105.0 }, .{ .x = 166.0, .y = 92.0 });
    try body.cubicTo(.{ .x = 142.0, .y = 79.0 }, .{ .x = 106.0, .y = 84.0 }, .{ .x = 82.0, .y = 106.0 });
    try body.cubicTo(.{ .x = 58.0, .y = 127.0 }, .{ .x = 42.0, .y = 149.0 }, .{ .x = 28.0, .y = 155.0 });
    try body.close();
    try builder.addPath(&body, .{ .paint = .{ .linear_gradient = .{
        .start = .{ .x = 48.0, .y = 102.0 },
        .end = .{ .x = 320.0, .y = 158.0 },
        .start_color = .{ 0.90, 0.87, 0.78, 0.98 },
        .end_color = .{ 0.58, 0.66, 0.57, 0.98 },
    } } }, .{
        .color = .{ 0.92, 0.92, 0.86, 0.42 },
        .width = 2.0,
        .join = .round,
    }, transform);

    var belly = snail.VectorPath.init(builder.allocator);
    defer belly.deinit();
    try belly.moveTo(.{ .x = 92.0, .y = 140.0 });
    try belly.cubicTo(.{ .x = 138.0, .y = 132.0 }, .{ .x = 204.0, .y = 136.0 }, .{ .x = 274.0, .y = 142.0 });
    try builder.addStrokedPath(&belly, .{
        .color = .{ 1.0, 1.0, 1.0, 0.18 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    try builder.addEllipse(.{
        .x = 156.0,
        .y = 24.0,
        .w = 114.0,
        .h = 114.0,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 214.0, .y = 80.0 },
        .radius = 76.0,
        .inner_color = .{ 0.42, 0.78, 0.93, 0.46 },
        .outer_color = .{ 0.12, 0.22, 0.30, 0.94 },
    } } }, .{
        .color = .{ 0.52, 0.86, 0.98, 0.80 },
        .width = 2.4,
        .join = .round,
    }, transform);

    var spiral = snail.VectorPath.init(builder.allocator);
    defer spiral.deinit();
    try spiral.moveTo(.{ .x = 254.0, .y = 78.0 });
    try spiral.cubicTo(.{ .x = 248.0, .y = 44.0 }, .{ .x = 196.0, .y = 41.0 }, .{ .x = 178.0, .y = 72.0 });
    try spiral.cubicTo(.{ .x = 160.0, .y = 102.0 }, .{ .x = 178.0, .y = 138.0 }, .{ .x = 214.0, .y = 134.0 });
    try spiral.cubicTo(.{ .x = 247.0, .y = 130.0 }, .{ .x = 256.0, .y = 95.0 }, .{ .x = 235.0, .y = 81.0 });
    try spiral.cubicTo(.{ .x = 217.0, .y = 69.0 }, .{ .x = 195.0, .y = 83.0 }, .{ .x = 200.0, .y = 103.0 });
    try spiral.cubicTo(.{ .x = 204.0, .y = 118.0 }, .{ .x = 224.0, .y = 117.0 }, .{ .x = 229.0, .y = 104.0 });
    try builder.addStrokedPath(&spiral, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 252.0, .y = 60.0 },
            .end = .{ .x = 194.0, .y = 114.0 },
            .start_color = .{ 0.98, 0.86, 0.54, 0.94 },
            .end_color = .{ 0.94, 0.54, 0.28, 0.90 },
        } },
        .width = 9.0,
        .cap = .round,
        .join = .round,
    }, transform);

    var stalk_a = snail.VectorPath.init(builder.allocator);
    defer stalk_a.deinit();
    try stalk_a.moveTo(.{ .x = 308.0, .y = 100.0 });
    try stalk_a.quadTo(.{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 });
    try builder.addStrokedPath(&stalk_a, .{
        .color = .{ 0.86, 0.87, 0.80, 0.92 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    var stalk_b = snail.VectorPath.init(builder.allocator);
    defer stalk_b.deinit();
    try stalk_b.moveTo(.{ .x = 294.0, .y = 102.0 });
    try stalk_b.quadTo(.{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 });
    try builder.addStrokedPath(&stalk_b, .{
        .color = .{ 0.86, 0.87, 0.80, 0.82 },
        .width = 3.4,
        .cap = .round,
        .join = .round,
    }, transform);

    try builder.addFilledEllipse(.{ .x = 330.0, .y = 54.0, .w = 9.0, .h = 9.0 }, .{ .color = .{ 0.98, 0.96, 0.90, 0.95 } }, transform);
    try builder.addFilledEllipse(.{ .x = 303.0, .y = 61.0, .w = 7.0, .h = 7.0 }, .{ .color = .{ 0.98, 0.96, 0.90, 0.88 } }, transform);
    try builder.addFilledEllipse(.{ .x = 333.0, .y = 57.0, .w = 3.0, .h = 3.0 }, .{ .color = .{ 0.08, 0.08, 0.10, 0.95 } }, transform);
    try builder.addFilledEllipse(.{ .x = 305.0, .y = 63.0, .w = 2.5, .h = 2.5 }, .{ .color = .{ 0.08, 0.08, 0.10, 0.90 } }, transform);

    var smile = snail.VectorPath.init(builder.allocator);
    defer smile.deinit();
    try smile.moveTo(.{ .x = 314.0, .y = 119.0 });
    try smile.quadTo(.{ .x = 321.0, .y = 123.0 }, .{ .x = 329.0, .y = 119.0 });
    try builder.addStrokedPath(&smile, .{
        .color = .{ 0.18, 0.20, 0.22, 0.55 },
        .width = 2.0,
        .cap = .round,
        .join = .round,
    }, transform);
}
