const std = @import("std");
const snail = @import("snail.zig");

pub const arabic_text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7 \xd8\xa8\xd8\xa7\xd9\x84\xd8\xb9\xd8\xa7\xd9\x84\xd9\x85"; // مرحبا بالعالم
pub const devanagari_text = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0"; // नमस्ते संसार
pub const mongolian_text = "\xe1\xa0\xae\xe1\xa0\xa4\xe1\xa0\xa9\xe1\xa0\xa0\xe1\xa0\xa4\xe1\xa0\xaf"; // ᠮᠤᠩᠠᠤᠯ
pub const thai_text = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a"; // สวัสดีครับ
pub const emoji_text = "\xe2\x9c\xa8 \xf0\x9f\x8c\x8d \xf0\x9f\x8e\xa8 \xf0\x9f\x9a\x80 \xf0\x9f\x90\x8c \xf0\x9f\x8c\x88 \xf0\x9f\x94\xa5"; // ✨ 🌍 🎨 🚀 🐌 🌈 🔥

pub const title_text = "snail";
pub const badge_text = "GPU text + paths";
pub const subtitle_text = "ligatures / pangrams / scripts / emoji / paths";
pub const hero_meta_text = "quartz / velvet / zinc / jazz";
pub const ligature_label_text = "Latin";
pub const ligature_text = "office affine shuffle flow";
pub const ligature_caption_text = "ffi / fi / ffl / fl";
pub const pangram_a_text = "Sphinx of black quartz, judge my vow.";
pub const pangram_b_text = "Jived fox nymph grabs quick waltz.";
pub const specimen_footer_text = "AV / To / ffi / 0123456789";
pub const scripts_heading_text = "Scripts / emoji";
pub const stage_label_text = "Paths";
pub const stage_title_text = "fill / gradient / stroke";
pub const stage_caption_text = "frozen / instanced";
pub const stage_pill_labels = [_][]const u8{
    "round rect",
    "ellipse",
    "cubic",
};

const badge_font_size: f32 = 13.0;
const scripts_heading_font_size: f32 = 13.0;
const script_label_font_size: f32 = 11.0;
const emoji_font_size: f32 = 26.0;
const script_label_inset_x: f32 = 18.0;
const script_label_gap: f32 = 24.0;
const script_row_gap: f32 = 6.0;
const script_row_vertical_pad: f32 = 14.0;
const emoji_pill_vertical_pad: f32 = 10.0;
const script_band_top_inset: f32 = 16.0;
const script_band_bottom_inset: f32 = 14.0;
const emoji_pill_gap: f32 = 10.0;
const scripts_heading_gutter_pad: f32 = 10.0;
const emoji_label_text = "Emoji";

const ScriptRowSpec = struct {
    label: []const u8,
    text: []const u8,
    color: [4]f32,
    size: f32,
};

const script_row_specs = [_]ScriptRowSpec{
    .{ .label = "Arabic", .text = arabic_text, .color = sage, .size = 27.0 },
    .{ .label = "Devanagari", .text = devanagari_text, .color = teal, .size = 24.0 },
    .{ .label = "Thai", .text = thai_text, .color = sand, .size = 26.0 },
    .{ .label = "Mongolian", .text = mongolian_text, .color = blush, .size = 27.0 },
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
    script_label_column_w: f32,
    script_label_extents: LineExtents,
    script_row_heights: [script_row_specs.len]f32,
    script_sample_extents: [script_row_specs.len]LineExtents,
    emoji_pill_h: f32,
    emoji_extents: LineExtents,
    script_band_min_h: f32,
    scripts_heading_gutter_h: f32,
};

pub const Layout = struct {
    canvas: snail.VectorRect,
    specimen_panel: snail.VectorRect,
    frame: snail.VectorRect,
    script_band: snail.VectorRect,
    snail_stage: snail.VectorRect,
    path_label_area: snail.VectorRect,
    badge_pill: snail.VectorRect,
    emoji_pill: snail.VectorRect,
    script_rows: [4]snail.VectorRect,
    stage_pills: [3]snail.VectorRect,
    script_text_x: f32,
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

fn textYFromTop(h: f32, top_y: f32) f32 {
    return h - top_y;
}

fn perpLeft(v: snail.Vec2) snail.Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

fn addFilledQuadraticRibbon(
    builder: *snail.PathPictureBuilder,
    start: snail.Vec2,
    control: snail.Vec2,
    end: snail.Vec2,
    half_width: f32,
    color: [4]f32,
    transform: snail.VectorTransform2D,
) !void {
    const start_tangent = snail.Vec2.normalize(snail.Vec2.sub(control, start));
    const end_tangent = snail.Vec2.normalize(snail.Vec2.sub(end, control));
    const blended_tangent = snail.Vec2.add(start_tangent, end_tangent);
    const mid_tangent = if (snail.Vec2.length(blended_tangent) > 1e-5)
        snail.Vec2.normalize(blended_tangent)
    else
        snail.Vec2.normalize(snail.Vec2.sub(end, start));

    const start_normal = snail.Vec2.scale(perpLeft(start_tangent), half_width);
    const mid_normal = snail.Vec2.scale(perpLeft(mid_tangent), half_width);
    const end_normal = snail.Vec2.scale(perpLeft(end_tangent), half_width);
    const tip_cap = snail.Vec2.scale(end_tangent, half_width * 0.9);

    var ribbon = snail.VectorPath.init(builder.allocator);
    defer ribbon.deinit();
    try ribbon.moveTo(snail.Vec2.add(start, start_normal));
    try ribbon.quadTo(snail.Vec2.add(control, mid_normal), snail.Vec2.add(end, end_normal));
    try ribbon.quadTo(snail.Vec2.add(end, tip_cap), snail.Vec2.sub(end, end_normal));
    try ribbon.quadTo(snail.Vec2.sub(control, mid_normal), snail.Vec2.sub(start, start_normal));
    try ribbon.close();
    try builder.addFilledPath(&ribbon, .{ .color = color }, transform);
}

const TextBounds = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    fn height(self: @This()) f32 {
        return self.max_y - self.min_y;
    }

    fn empty() @This() {
        return .{
            .min_x = 0.0,
            .min_y = 0.0,
            .max_x = 0.0,
            .max_y = 0.0,
        };
    }

    fn include(self: *@This(), x: f32, y: f32) void {
        self.min_x = @min(self.min_x, x);
        self.min_y = @min(self.min_y, y);
        self.max_x = @max(self.max_x, x);
        self.max_y = @max(self.max_y, y);
    }
};

const MeasuredText = struct {
    advance: f32,
    bounds: TextBounds,
};

const LineExtents = struct {
    ascent: f32,
    descent: f32,

    fn height(self: @This()) f32 {
        return self.ascent + self.descent;
    }
};

fn measureText(atlas_like: anytype, font: *const snail.Font, text: []const u8, font_size: f32) MeasuredText {
    var probe_buf: [128 * snail.FLOATS_PER_GLYPH]f32 = undefined;
    var probe = snail.Batch.init(&probe_buf);
    const advance = probe.addString(atlas_like, font, text, 0, 0, font_size, ink);
    if (probe.glyphCount() == 0) return .{
        .advance = advance,
        .bounds = TextBounds.empty(),
    };

    var bounds = TextBounds{
        .min_x = std.math.inf(f32),
        .min_y = std.math.inf(f32),
        .max_x = -std.math.inf(f32),
        .max_y = -std.math.inf(f32),
    };
    const vertices = probe.slice();
    var glyph_start: usize = 0;
    while (glyph_start < vertices.len) : (glyph_start += snail.FLOATS_PER_GLYPH) {
        inline for (0..snail.VERTICES_PER_GLYPH) |vertex_index| {
            const base = glyph_start + vertex_index * snail.FLOATS_PER_VERTEX;
            bounds.include(vertices[base], vertices[base + 1]);
        }
    }

    return .{
        .advance = advance,
        .bounds = bounds,
    };
}

fn lineExtents(font: *const snail.Font, font_size: f32) LineExtents {
    const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
    const metrics = font.lineMetrics() catch return .{
        .ascent = font_size * 0.82,
        .descent = font_size * 0.22,
    };
    return .{
        .ascent = @as(f32, @floatFromInt(metrics.ascent)) * scale,
        .descent = -@as(f32, @floatFromInt(metrics.descent)) * scale,
    };
}

fn boundsExtents(bounds: TextBounds) LineExtents {
    return .{
        .ascent = @max(0.0, bounds.max_y),
        .descent = @max(0.0, -bounds.min_y),
    };
}

fn centeredBaselineTopFromExtents(extents: LineExtents, rect: snail.VectorRect) f32 {
    const content_h = extents.height();
    return rect.y + (rect.h - content_h) * 0.5 + extents.ascent;
}

fn baselineFromTop(top: f32, extents: LineExtents) f32 {
    return top + extents.ascent;
}

pub fn measureMetrics(
    atlas_like: anytype,
    font: *const snail.Font,
    script_fonts: [script_row_specs.len]*const snail.Font,
    emoji_font: *const snail.Font,
) TextMetrics {
    const badge = measureText(atlas_like, font, badge_text, badge_font_size);
    const emoji_label = measureText(atlas_like, font, emoji_label_text, script_label_font_size);
    const emoji_sample = measureText(atlas_like, emoji_font, emoji_text, emoji_font_size);
    const label_extents = lineExtents(font, script_label_font_size);
    const emoji_extents = lineExtents(emoji_font, emoji_font_size);
    const scripts_heading_extents = lineExtents(font, scripts_heading_font_size);
    var script_row_heights: [script_row_specs.len]f32 = undefined;
    var script_sample_extents: [script_row_specs.len]LineExtents = undefined;
    var max_label_advance: f32 = emoji_label.advance;
    var script_band_content_h: f32 = 0.0;
    inline for (script_row_specs, script_fonts, 0..) |spec, script_font, i| {
        const label = measureText(atlas_like, font, spec.label, script_label_font_size);
        const sample = measureText(atlas_like, script_font, spec.text, spec.size);
        const sample_extents = lineExtents(script_font, spec.size);
        const row_h = snapPx(@max(label.bounds.height(), sample.bounds.height()) + script_row_vertical_pad * 2.0);
        script_sample_extents[i] = sample_extents;
        script_row_heights[i] = row_h;
        max_label_advance = @max(max_label_advance, label.advance);
        script_band_content_h += row_h;
    }
    const emoji_pill_h = snapPx(@max(emoji_label.bounds.height(), emoji_sample.bounds.height()) + emoji_pill_vertical_pad * 2.0);
    const script_band_min_h = snapPx(
        script_band_top_inset +
            script_band_content_h +
            script_row_gap * @as(f32, @floatFromInt(script_row_specs.len - 1)) +
            emoji_pill_gap +
            emoji_pill_h +
            script_band_bottom_inset,
    );
    const scripts_heading_gutter_h = snapPx(@max(22.0, scripts_heading_extents.height() + scripts_heading_gutter_pad * 2.0));
    return .{
        .badge_advance = badge.advance,
        .script_label_column_w = snapPx(max_label_advance + script_label_gap),
        .script_label_extents = label_extents,
        .script_row_heights = script_row_heights,
        .script_sample_extents = script_sample_extents,
        .emoji_pill_h = emoji_pill_h,
        .emoji_extents = emoji_extents,
        .script_band_min_h = script_band_min_h,
        .scripts_heading_gutter_h = scripts_heading_gutter_h,
    };
}

pub fn buildLayout(w: f32, h: f32, metrics: TextMetrics) Layout {
    const margin_x = snapPx(@max(22.0, w * 0.018));
    const margin_y = snapPx(@max(22.0, h * 0.04));
    const frame = snapRect(.{
        .x = margin_x,
        .y = margin_y,
        .w = w - margin_x * 2.0,
        .h = h - margin_y * 2.0,
    });
    const badge_pill = snapRect(.{
        .x = frame.x + 28.0,
        .y = frame.y + 22.0,
        .w = std.math.clamp(metrics.badge_advance + 40.0, 220.0, 260.0),
        .h = 34.0,
    });
    const script_band_h = snapPx(@max(metrics.script_band_min_h, std.math.clamp(frame.h * 0.34, 236.0, 320.0)));
    const script_band = snapRect(.{
        .x = frame.x + 18.0,
        .y = frame.y + frame.h - script_band_h - 14.0,
        .w = frame.w - 36.0,
        .h = script_band_h,
    });
    const specimen_h = std.math.clamp(frame.h * 0.265, 192.0, 214.0);
    const specimen_panel = snapRect(.{
        .x = frame.x + 28.0,
        .y = script_band.y - specimen_h - metrics.scripts_heading_gutter_h,
        .w = std.math.clamp(frame.w * 0.36, 420.0, 600.0),
        .h = specimen_h,
    });
    var script_inner_h: f32 = emoji_pill_gap + metrics.emoji_pill_h;
    inline for (metrics.script_row_heights, 0..) |row_h, i| {
        script_inner_h += row_h;
        if (i + 1 < metrics.script_row_heights.len) script_inner_h += script_row_gap;
    }
    const script_top = script_band.y + script_band_top_inset + (script_band.h - metrics.script_band_min_h) * 0.5;
    var script_rows: [4]snail.VectorRect = undefined;
    var row_y = script_top;
    for (&script_rows, metrics.script_row_heights) |*row, row_h| {
        row.* = snapRect(.{
            .x = script_band.x + 18.0,
            .y = row_y,
            .w = script_band.w - 36.0,
            .h = row_h,
        });
        row_y += row_h + script_row_gap;
    }
    const emoji_pill = snapRect(.{
        .x = script_band.x + 18.0,
        .y = script_top + script_inner_h - metrics.emoji_pill_h,
        .w = script_band.w - 36.0,
        .h = metrics.emoji_pill_h,
    });

    const path_label_area = snapRect(.{
        .x = specimen_panel.x + specimen_panel.w + 34.0,
        .y = specimen_panel.y + 22.0,
        .w = std.math.clamp(frame.w * 0.16, 180.0, 250.0),
        .h = 120.0,
    });
    const pill_x = path_label_area.x;
    const pill_y = path_label_area.y + 82.0;
    const pill_w = std.math.clamp(frame.w * 0.14, 160.0, 232.0);
    var stage_pills: [3]snail.VectorRect = undefined;
    stage_pills[0] = snapRect(.{ .x = pill_x, .y = pill_y, .w = pill_w, .h = 28.0 });
    stage_pills[1] = snapRect(.{ .x = pill_x, .y = pill_y + 38.0, .w = pill_w * 0.82, .h = 28.0 });
    stage_pills[2] = snapRect(.{ .x = pill_x, .y = pill_y + 76.0, .w = pill_w * 0.68, .h = 28.0 });
    const snail_stage_top = frame.y + 106.0;
    const snail_stage_bottom = script_band.y - 26.0;
    const snail_stage = snapRect(.{
        .x = frame.x + frame.w * 0.60,
        .y = snail_stage_top,
        .w = std.math.clamp(frame.w * 0.34, 380.0, 540.0),
        .h = std.math.clamp(snail_stage_bottom - snail_stage_top, 236.0, 320.0),
    });

    return .{
        .canvas = .{ .x = 0, .y = 0, .w = w, .h = h },
        .frame = frame,
        .specimen_panel = specimen_panel,
        .script_band = script_band,
        .snail_stage = snail_stage,
        .path_label_area = path_label_area,
        .badge_pill = badge_pill,
        .emoji_pill = emoji_pill,
        .script_rows = script_rows,
        .stage_pills = stage_pills,
        .script_text_x = script_band.x + 18.0 + script_label_inset_x + metrics.script_label_column_w,
    };
}

pub fn drawText(batch: *snail.Batch, h: f32, layout: Layout, metrics: TextMetrics, resources: TextResources) void {
    const hero_x = layout.frame.x + 30.0;
    const title_size = std.math.clamp(layout.frame.w * 0.11, 88.0, 118.0);
    const subtitle_size = std.math.clamp(layout.frame.w * 0.019, 19.0, 26.0);
    const ligature_size = std.math.clamp(layout.specimen_panel.w * 0.072, 34.0, 48.0);
    const pangram_size = std.math.clamp(layout.specimen_panel.w * 0.034, 18.0, 22.0);
    const badge_extents = lineExtents(resources.latin_font, badge_font_size);
    const title_measure = measureText(resources.latin_view, resources.latin_font, title_text, title_size);
    const subtitle_measure = measureText(resources.latin_view, resources.latin_font, subtitle_text, subtitle_size);
    const hero_meta_measure = measureText(resources.latin_view, resources.latin_font, hero_meta_text, 14.0);
    const title_extents = boundsExtents(title_measure.bounds);
    const subtitle_extents = boundsExtents(subtitle_measure.bounds);
    const hero_meta_extents = boundsExtents(hero_meta_measure.bounds);
    const specimen_label_extents = lineExtents(resources.latin_font, 12.0);
    const ligature_extents = lineExtents(resources.latin_font, ligature_size);
    const ligature_caption_extents = lineExtents(resources.latin_font, 14.0);
    const pangram_a_extents = lineExtents(resources.latin_font, pangram_size);
    const pangram_b_extents = lineExtents(resources.latin_font, 16.0);
    const specimen_footer_extents = lineExtents(resources.latin_font, 12.0);
    const scripts_heading_extents = lineExtents(resources.latin_font, scripts_heading_font_size);
    const stage_label_extents = lineExtents(resources.latin_font, 12.0);
    const stage_title_extents = lineExtents(resources.latin_font, 23.0);
    const stage_caption_extents = lineExtents(resources.latin_font, 14.0);
    const stage_pill_extents = lineExtents(resources.latin_font, 12.0);
    const badge_baseline_top = centeredBaselineTopFromExtents(badge_extents, layout.badge_pill);
    const emoji_label_baseline_top = centeredBaselineTopFromExtents(metrics.script_label_extents, layout.emoji_pill);
    const emoji_baseline_top = centeredBaselineTopFromExtents(metrics.emoji_extents, layout.emoji_pill);
    const scripts_heading_gutter = snail.VectorRect{
        .x = layout.script_band.x,
        .y = layout.specimen_panel.y + layout.specimen_panel.h,
        .w = layout.script_band.w,
        .h = layout.script_band.y - (layout.specimen_panel.y + layout.specimen_panel.h),
    };
    const hero_badge_gap = snapPx(@max(10.0, subtitle_extents.height() * 0.45));
    const hero_subtitle_gap = snapPx(@max(8.0, hero_meta_extents.height() * 0.65));
    const hero_meta_gap = snapPx(@max(8.0, hero_meta_extents.height() * 0.35));
    const hero_title_top = layout.badge_pill.y + layout.badge_pill.h + hero_badge_gap;
    const hero_subtitle_top = hero_title_top + title_extents.height() + hero_subtitle_gap;
    const hero_meta_top = hero_subtitle_top + subtitle_extents.height() + hero_meta_gap;
    const specimen_label_top = layout.specimen_panel.y + 26.0 - specimen_label_extents.ascent;
    const ligature_top = layout.specimen_panel.y + 70.0 - ligature_extents.ascent;
    const ligature_caption_top = layout.specimen_panel.y + 100.0 - ligature_caption_extents.ascent;
    const pangram_a_top = layout.specimen_panel.y + 136.0 - pangram_a_extents.ascent;
    const pangram_b_top = layout.specimen_panel.y + 162.0 - pangram_b_extents.ascent;
    const specimen_footer_top = layout.specimen_panel.y + layout.specimen_panel.h - 20.0 - specimen_footer_extents.ascent;
    const scripts_heading_baseline_top = centeredBaselineTopFromExtents(scripts_heading_extents, scripts_heading_gutter);
    const stage_label_top = layout.path_label_area.y + 12.0 - stage_label_extents.ascent;
    const stage_title_top = layout.path_label_area.y + 44.0 - stage_title_extents.ascent;
    const stage_caption_top = layout.path_label_area.y + 70.0 - stage_caption_extents.ascent;

    _ = batch.addString(resources.latin_view, resources.latin_font, badge_text, layout.badge_pill.x + 16.0, textYFromTop(h, badge_baseline_top), badge_font_size, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, title_text, hero_x, textYFromTop(h, baselineFromTop(hero_title_top, title_extents)), title_size, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, subtitle_text, hero_x, textYFromTop(h, baselineFromTop(hero_subtitle_top, subtitle_extents)), subtitle_size, mist);
    _ = batch.addString(resources.latin_view, resources.latin_font, hero_meta_text, hero_x, textYFromTop(h, baselineFromTop(hero_meta_top, hero_meta_extents)), 14.0, slate);

    const specimen_x = layout.specimen_panel.x + 24.0;
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_label_text, specimen_x, textYFromTop(h, baselineFromTop(specimen_label_top, specimen_label_extents)), 12.0, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_text, specimen_x, textYFromTop(h, baselineFromTop(ligature_top, ligature_extents)), ligature_size, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, ligature_caption_text, specimen_x, textYFromTop(h, baselineFromTop(ligature_caption_top, ligature_caption_extents)), 14.0, sand);
    _ = batch.addString(resources.latin_view, resources.latin_font, pangram_a_text, specimen_x, textYFromTop(h, baselineFromTop(pangram_a_top, pangram_a_extents)), pangram_size, mist);
    _ = batch.addString(resources.latin_view, resources.latin_font, pangram_b_text, specimen_x, textYFromTop(h, baselineFromTop(pangram_b_top, pangram_b_extents)), 16.0, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, specimen_footer_text, specimen_x, textYFromTop(h, baselineFromTop(specimen_footer_top, specimen_footer_extents)), 12.0, slate);

    _ = batch.addString(resources.latin_view, resources.latin_font, scripts_heading_text, layout.script_band.x + 12.0, textYFromTop(h, scripts_heading_baseline_top), scripts_heading_font_size, teal);

    const script_items = [_]struct {
        spec: ScriptRowSpec,
        font: *const ScriptFont,
        view: *const snail.AtlasView,
    }{
        .{ .spec = script_row_specs[0], .font = resources.arabic_font, .view = resources.arabic_view },
        .{ .spec = script_row_specs[1], .font = resources.devanagari_font, .view = resources.devanagari_view },
        .{ .spec = script_row_specs[2], .font = resources.thai_font, .view = resources.thai_view },
        .{ .spec = script_row_specs[3], .font = resources.mongolian_font, .view = resources.mongolian_view },
    };
    for (layout.script_rows, script_items, 0..) |row, item, i| {
        const label_baseline_top = centeredBaselineTopFromExtents(metrics.script_label_extents, row);
        const sample_baseline_top = centeredBaselineTopFromExtents(metrics.script_sample_extents[i], row);
        _ = batch.addString(resources.latin_view, resources.latin_font, item.spec.label, row.x + script_label_inset_x, textYFromTop(h, label_baseline_top), script_label_font_size, slate);
        _ = batch.addString(item.view, &item.font.font, item.spec.text, layout.script_text_x, textYFromTop(h, sample_baseline_top), item.spec.size, item.spec.color);
    }

    _ = batch.addString(resources.latin_view, resources.latin_font, emoji_label_text, layout.emoji_pill.x + script_label_inset_x, textYFromTop(h, emoji_label_baseline_top), script_label_font_size, slate);
    _ = batch.addString(resources.emoji_view, &resources.emoji_font.font, emoji_text, layout.script_text_x, textYFromTop(h, emoji_baseline_top), emoji_font_size, ink);

    _ = batch.addString(resources.latin_view, resources.latin_font, stage_label_text, layout.path_label_area.x, textYFromTop(h, baselineFromTop(stage_label_top, stage_label_extents)), 12.0, teal);
    _ = batch.addString(resources.latin_view, resources.latin_font, stage_title_text, layout.path_label_area.x, textYFromTop(h, baselineFromTop(stage_title_top, stage_title_extents)), 23.0, ink);
    _ = batch.addString(resources.latin_view, resources.latin_font, stage_caption_text, layout.path_label_area.x, textYFromTop(h, baselineFromTop(stage_caption_top, stage_caption_extents)), 14.0, mist);
    for (layout.stage_pills, stage_pill_labels) |pill, label| {
        _ = batch.addString(resources.latin_view, resources.latin_font, label, pill.x + 16.0, textYFromTop(h, centeredBaselineTopFromExtents(stage_pill_extents, pill)), 12.0, ink);
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

    try builder.addRoundedRect(
        layout.frame,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.frame.x, .y = layout.frame.y },
            .end = .{ .x = layout.frame.x + layout.frame.w * 0.9, .y = layout.frame.y + layout.frame.h },
            .start_color = .{ 0.07, 0.11, 0.16, 0.96 },
            .end_color = .{ 0.04, 0.07, 0.10, 0.96 },
        } } },
        .{ .color = .{ 0.23, 0.31, 0.39, 1.0 }, .width = 1.5, .join = .round, .placement = .inside },
        40.0,
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
        layout.specimen_panel,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.specimen_panel.x, .y = layout.specimen_panel.y },
            .end = .{ .x = layout.specimen_panel.x, .y = layout.specimen_panel.y + layout.specimen_panel.h },
            .start_color = .{ 0.09, 0.11, 0.15, 0.94 },
            .end_color = .{ 0.05, 0.06, 0.09, 0.96 },
        } } },
        .{ .color = .{ 0.22, 0.28, 0.34, 1.0 }, .width = 1.1, .join = .round, .placement = .inside },
        28.0,
        .identity,
    );
    try builder.addRoundedRect(
        layout.script_band,
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = layout.script_band.x, .y = layout.script_band.y },
            .end = .{ .x = layout.script_band.x + layout.script_band.w, .y = layout.script_band.y + layout.script_band.h },
            .start_color = .{ 0.08, 0.09, 0.12, 0.84 },
            .end_color = .{ 0.05, 0.06, 0.08, 0.90 },
        } } },
        .{ .color = .{ 0.19, 0.24, 0.29, 0.96 }, .width = 1.2, .join = .round, .placement = .inside },
        28.0,
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
        16.0,
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
            row.h * 0.5,
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

    try addVectorSnail(builder, layout.snail_stage);
}

fn addVectorSnail(builder: *snail.PathPictureBuilder, snail_stage: snail.VectorRect) !void {
    const art_width = @min(snail_stage.w * 0.74, 440.0);
    const scale = art_width / 360.0;
    const art_height = 220.0 * scale;
    const art_x = snail_stage.x + snail_stage.w - art_width - 8.0;
    const art_y = snail_stage.y + snail_stage.h - art_height - 6.0;
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

    try addFilledQuadraticRibbon(
        builder,
        .{ .x = 308.0, .y = 100.0 },
        .{ .x = 316.0, .y = 76.0 },
        .{ .x = 334.0, .y = 58.0 },
        2.0,
        .{ 0.86, 0.87, 0.80, 0.92 },
        transform,
    );
    try addFilledQuadraticRibbon(
        builder,
        .{ .x = 294.0, .y = 102.0 },
        .{ .x = 298.0, .y = 80.0 },
        .{ .x = 306.0, .y = 64.0 },
        2.0,
        .{ 0.86, 0.87, 0.80, 0.92 },
        transform,
    );

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
