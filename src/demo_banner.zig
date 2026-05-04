const std = @import("std");
const snail = @import("snail.zig");
const Allocator = std.mem.Allocator;

// ── Reference canvas ──

const REF_W: f32 = 1680;
const REF_H: f32 = 874;

// ── Palette (light theme) ──

const bg = [4]f32{ 0.96, 0.965, 0.975, 1.0 };
const text = [4]f32{ 0.10, 0.10, 0.14, 1.0 };
const muted = [4]f32{ 0.42, 0.46, 0.52, 1.0 };
const accent = [4]f32{ 0.15, 0.38, 0.85, 1.0 };
const surface = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
const border = [4]f32{ 0.84, 0.86, 0.89, 1.0 };

// ── Layout ──

pub const Layout = struct {
    scale: f32,
    canvas: snail.Rect,
    title: snail.Rect,
    styles: snail.Rect,
    decorations: snail.Rect,
    shaping: snail.Rect,
    scripts: snail.Rect,
    vectors: snail.Rect,
    snail_stage: snail.Rect,
};

pub fn buildLayout(w: f32, h: f32) Layout {
    const scale = @min(w / REF_W, h / REF_H);
    const margin = 48 * scale;
    const col_gap = 28 * scale;
    const row_gap = 24 * scale;

    const cx = (w - REF_W * scale) * 0.5;
    const cy = (h - REF_H * scale) * 0.5;

    // Title row
    const title_h = 100 * scale;
    const title = snail.Rect{ .x = cx + margin, .y = cy + margin, .w = REF_W * scale - margin * 2, .h = title_h };

    // Content row: 4 columns
    const content_top = title.y + title.h + row_gap;
    const content_w = REF_W * scale - margin * 2;
    const col_w = (content_w - col_gap * 3) / 4;
    const content_h = 300 * scale;

    const col_x = cx + margin;
    const styles = snail.Rect{ .x = col_x, .y = content_top, .w = col_w, .h = content_h };
    const decorations = snail.Rect{ .x = col_x + col_w + col_gap, .y = content_top, .w = col_w, .h = content_h };
    const shaping = snail.Rect{ .x = col_x + (col_w + col_gap) * 2, .y = content_top, .w = col_w, .h = content_h };
    const scripts = snail.Rect{ .x = col_x + (col_w + col_gap) * 3, .y = content_top, .w = col_w, .h = content_h };

    // Vectors row
    const vectors_top = content_top + content_h + row_gap;
    const vectors_h = REF_H * scale - (vectors_top - cy) - margin;
    const vectors_w = content_w * 0.55;
    const vectors = snail.Rect{ .x = col_x, .y = vectors_top, .w = vectors_w, .h = vectors_h };

    const snail_stage = snail.Rect{
        .x = col_x + vectors_w + col_gap,
        .y = vectors_top,
        .w = content_w - vectors_w - col_gap,
        .h = vectors_h,
    };

    return .{
        .scale = scale,
        .canvas = .{ .x = cx, .y = cy, .w = REF_W * scale, .h = REF_H * scale },
        .title = title,
        .styles = styles,
        .decorations = decorations,
        .shaping = shaping,
        .scripts = scripts,
        .vectors = vectors,
        .snail_stage = snail_stage,
    };
}

pub fn clearColor() [4]f32 {
    return bg;
}

// ── Path picture (background, cards, decorations, vector shapes, snail) ──

pub fn buildPathPicture(
    allocator: Allocator,
    layout: Layout,
    tile_image: *const snail.Image,
    decoration_rects: []const snail.Rect,
) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    const s = layout.scale;
    const r = 10 * s;
    const stroke_w = 1.0 * s;
    const card_stroke = snail.StrokeStyle{ .color = border, .width = stroke_w, .join = .round, .placement = .inside };
    const card_fill = snail.FillStyle{ .color = surface };

    // Background
    try builder.addFilledRect(layout.canvas, .{ .color = bg }, .identity);

    // Card backgrounds
    try builder.addRoundedRect(layout.styles, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.decorations, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.shaping, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.scripts, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.vectors, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.snail_stage, card_fill, card_stroke, r, .identity);

    // Decoration lines (underline/strikethrough rects collected from drawText)
    for (decoration_rects) |rect| {
        try builder.addFilledRect(rect, .{ .color = text }, .identity);
    }

    // Vector shape demos
    try addVectorShapes(&builder, layout, tile_image);

    // The snail illustration
    try addVectorSnail(&builder, layout.snail_stage);

    return builder.freeze(allocator);
}

// Shared sizing constants (must match between drawText, addDecorationLines, addVectorShapes)
const card_pad = 20;
const heading_size = 15;
const sub_heading_size = 13;
const body_text_size = 22;
const body_line_h = 28;
const shape_sz = 56;
const shape_gap = 14;

fn addVectorShapes(
    builder: *snail.PathPictureBuilder,
    layout: Layout,
    tile_image: *const snail.Image,
) !void {
    const s = layout.scale;
    const pad = card_pad * s;
    const sz = shape_sz * s;
    const gap = shape_gap * s;
    const x0 = layout.vectors.x + pad;
    const stroke_w = 2 * s;

    // Y positions must match drawText's Vectors label layout.
    // heading + 14 + "Shapes" sub-heading + 8 → shapes_y
    const shapes_y = layout.vectors.y + pad + heading_size * s + 14 * s + sub_heading_size * s + 6 * s;

    // ── Row 1: Shapes ──

    // Rect
    try builder.addRect(.{ .x = x0, .y = shapes_y, .w = sz, .h = sz }, .{
        .color = .{ 0.22, 0.50, 0.88, 1.0 },
    }, .{
        .color = .{ 0.15, 0.38, 0.72, 1.0 },
        .width = stroke_w,
        .join = .miter,
        .placement = .inside,
    }, .identity);

    // Rounded rect
    const rrx = x0 + sz + gap;
    try builder.addRoundedRect(.{ .x = rrx, .y = shapes_y, .w = sz, .h = sz }, .{
        .color = .{ 0.92, 0.82, 0.48, 1.0 },
    }, .{
        .color = .{ 0.78, 0.62, 0.22, 1.0 },
        .width = stroke_w,
        .join = .round,
        .placement = .inside,
    }, 12 * s, .identity);

    // Ellipse
    const elx = x0 + (sz + gap) * 2;
    try builder.addEllipse(.{ .x = elx, .y = shapes_y, .w = sz, .h = sz }, .{
        .color = .{ 0.85, 0.52, 0.35, 1.0 },
    }, .{
        .color = .{ 0.72, 0.38, 0.22, 1.0 },
        .width = stroke_w,
        .join = .round,
        .placement = .inside,
    }, .identity);

    // Custom path (leaf/diamond shape)
    const plx = x0 + (sz + gap) * 3;
    var path = snail.Path.init(builder.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = plx + sz * 0.5, .y = shapes_y });
    try path.cubicTo(
        .{ .x = plx + sz * 0.95, .y = shapes_y + sz * 0.2 },
        .{ .x = plx + sz * 0.95, .y = shapes_y + sz * 0.8 },
        .{ .x = plx + sz * 0.5, .y = shapes_y + sz },
    );
    try path.cubicTo(
        .{ .x = plx + sz * 0.05, .y = shapes_y + sz * 0.8 },
        .{ .x = plx + sz * 0.05, .y = shapes_y + sz * 0.2 },
        .{ .x = plx + sz * 0.5, .y = shapes_y },
    );
    try path.close();
    try builder.addPath(&path, .{
        .color = .{ 0.58, 0.48, 0.82, 1.0 },
    }, .{
        .color = .{ 0.42, 0.32, 0.68, 1.0 },
        .width = stroke_w,
        .join = .round,
    }, .identity);

    // ── Row 2: Fills ──
    // Y: shapes_y + sz + label below + gap + "Fills" sub-heading + gap
    const fills_y = shapes_y + sz + 11 * s + 6 * s + sub_heading_size * s + 6 * s;

    // Solid fill
    try builder.addRoundedRect(.{ .x = x0, .y = fills_y, .w = sz, .h = sz }, .{
        .color = .{ 0.35, 0.72, 0.55, 1.0 },
    }, null, 6 * s, .identity);

    // Linear gradient
    const lgx = x0 + sz + gap;
    try builder.addRoundedRect(.{ .x = lgx, .y = fills_y, .w = sz, .h = sz }, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = lgx, .y = fills_y },
            .end = .{ .x = lgx + sz, .y = fills_y + sz },
            .start_color = .{ 0.25, 0.55, 0.95, 1.0 },
            .end_color = .{ 0.85, 0.30, 0.55, 1.0 },
        } },
    }, null, 6 * s, .identity);

    // Radial gradient
    const rgx = x0 + (sz + gap) * 2;
    try builder.addRoundedRect(.{ .x = rgx, .y = fills_y, .w = sz, .h = sz }, .{
        .paint = .{ .radial_gradient = .{
            .center = .{ .x = rgx + sz * 0.45, .y = fills_y + sz * 0.4 },
            .radius = sz * 0.55,
            .inner_color = .{ 0.98, 0.90, 0.55, 1.0 },
            .outer_color = .{ 0.88, 0.42, 0.18, 1.0 },
        } },
    }, null, 6 * s, .identity);

    // Image fill
    const imx = x0 + (sz + gap) * 3;
    try builder.addRoundedRect(.{ .x = imx, .y = fills_y, .w = sz, .h = sz }, .{
        .paint = .{ .image = .{
            .image = tile_image,
            .uv_transform = snail.Transform2D.multiply(
                snail.Transform2D.translate(-imx, -fills_y),
                snail.Transform2D.scale(1.0 / (4.0 * s), 1.0 / (4.0 * s)),
            ),
            .extend_x = .repeat,
            .extend_y = .repeat,
        } },
    }, null, 6 * s, .identity);

    // Stroke-only path (in shapes row)
    const stx = x0 + (sz + gap) * 4;
    var stroke_path = snail.Path.init(builder.allocator);
    defer stroke_path.deinit();
    try stroke_path.moveTo(.{ .x = stx + 4 * s, .y = shapes_y + sz * 0.7 });
    try stroke_path.cubicTo(
        .{ .x = stx + sz * 0.3, .y = shapes_y - sz * 0.1 },
        .{ .x = stx + sz * 0.7, .y = shapes_y + sz * 1.1 },
        .{ .x = stx + sz - 4 * s, .y = shapes_y + sz * 0.3 },
    );
    try builder.addStrokedPath(&stroke_path, .{
        .color = .{ 0.22, 0.55, 0.80, 1.0 },
        .width = 4 * s,
        .cap = .round,
        .join = .round,
    }, .identity);

}

// ── Text drawing ──

pub const TextBuildResult = struct {
    decoration_count: usize,
    missing: bool,
};

/// Build the demo's prepared text blob and collect decoration rects.
pub fn buildTextBlob(
    builder: *snail.TextBlobBuilder,
    layout: Layout,
    fonts: *const snail.TextAtlas,
    decoration_rects_out: []snail.Rect,
) !TextBuildResult {
    var decoration_count: usize = 0;
    var had_missing = false;
    const s = layout.scale;
    const pad = card_pad * s;
    const label_size = heading_size * s;
    const sub_label_size = sub_heading_size * s;
    const body_size = body_text_size * s;
    const line_h = body_line_h * s;

    // ── Title ──
    _ = try builder.addText(.{ .weight = .bold }, "snail", layout.title.x, layout.title.y + 58 * s, 64 * s, text);
    _ = try builder.addText(.{}, "GPU text & vector rendering", layout.title.x + 210 * s, layout.title.y + 50 * s, 20 * s, muted);

    // ── Styles card ──
    {
        const x = layout.styles.x + pad;
        var y = layout.styles.y + pad;
        _ = try builder.addText(.{ .weight = .bold }, "Styles", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        _ = try builder.addText(.{}, "Regular", x, y + body_size, body_size, text);
        y += line_h;
        _ = try builder.addText(.{ .weight = .bold }, "Bold", x, y + body_size, body_size, text);
        y += line_h;
        _ = try builder.addText(.{ .italic = true }, "Italic", x, y + body_size, body_size, text);
        y += line_h;
        _ = try builder.addText(.{ .weight = .bold, .italic = true }, "Bold Italic", x, y + body_size, body_size, text);
        y += line_h;
        _ = try builder.addText(.{ .weight = .semi_bold }, "Synthetic", x, y + body_size, body_size, text);
        y += line_h + 8 * s;

        // Size ramp
        const sizes = [_]f32{ 10, 14, 18, 24, 32 };
        var sx = x;
        for (sizes) |sz| {
            const fs = sz * s;
            sx += (try builder.addText(.{}, "Aa", sx, y + 32 * s, fs, muted)).advance + 12 * s;
        }
    }

    // ── Decorations card ──
    {
        const x = layout.decorations.x + pad;
        var y = layout.decorations.y + pad;
        _ = try builder.addText(.{ .weight = .bold }, "Decorations", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Underlined
        const ul_advance = (try builder.addText(.{}, "Underlined", x, y + body_size, body_size, text)).advance;
        if (decoration_count < decoration_rects_out.len) {
            decoration_rects_out[decoration_count] = try fonts.decorationRect(.underline, x, y + body_size, ul_advance, body_size);
            decoration_count += 1;
        }
        y += line_h;

        // Struck
        const st_advance = (try builder.addText(.{}, "Struck", x, y + body_size, body_size, text)).advance;
        if (decoration_count < decoration_rects_out.len) {
            decoration_rects_out[decoration_count] = try fonts.decorationRect(.strikethrough, x, y + body_size, st_advance, body_size);
            decoration_count += 1;
        }
        y += line_h + 16 * s;

        // CH₅⁺ + C₂H₆ → C₂H₇⁺ + CH₄
        const sub_size = body_size * 1.2;
        const sub_y = y + sub_size;
        var cx = x;

        // CH₅⁺
        cx += (try builder.addText(.{}, "CH", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try builder.addText(.{}, "5", sub.x, sub.y, sub.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "5", cx, sub_y, sub_size * 0.7, text)).advance;
        }
        if (fonts.superscriptTransform(cx, sub_y, sub_size)) |sup| {
            cx += (try builder.addText(.{}, "+", sup.x, sup.y, sup.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "+", cx, sub_y - sub_size * 0.4, sub_size * 0.7, text)).advance;
        }

        cx += (try builder.addText(.{}, " + ", cx, sub_y, sub_size, text)).advance;

        // C₂H₆
        cx += (try builder.addText(.{}, "C", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try builder.addText(.{}, "2", sub.x, sub.y, sub.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "2", cx, sub_y, sub_size * 0.7, text)).advance;
        }
        cx += (try builder.addText(.{}, "H", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try builder.addText(.{}, "6", sub.x, sub.y, sub.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "6", cx, sub_y, sub_size * 0.7, text)).advance;
        }

        {
            const r = try builder.addText(.{}, " \u{2192} ", cx, sub_y, sub_size, text);
            cx += r.advance;
            if (r.missing) had_missing = true;
        }

        // C₂H₇⁺
        cx += (try builder.addText(.{}, "C", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try builder.addText(.{}, "2", sub.x, sub.y, sub.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "2", cx, sub_y, sub_size * 0.7, text)).advance;
        }
        cx += (try builder.addText(.{}, "H", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try builder.addText(.{}, "7", sub.x, sub.y, sub.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "7", cx, sub_y, sub_size * 0.7, text)).advance;
        }
        if (fonts.superscriptTransform(cx, sub_y, sub_size)) |sup| {
            cx += (try builder.addText(.{}, "+", sup.x, sup.y, sup.font_size, text)).advance;
        } else |_| {
            cx += (try builder.addText(.{}, "+", cx, sub_y - sub_size * 0.4, sub_size * 0.7, text)).advance;
        }

        cx += (try builder.addText(.{}, " + ", cx, sub_y, sub_size, text)).advance;

        // CH₄
        cx += (try builder.addText(.{}, "CH", cx, sub_y, sub_size, text)).advance;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            _ = try builder.addText(.{}, "4", sub.x, sub.y, sub.font_size, text);
        } else |_| {
            _ = try builder.addText(.{}, "4", cx, sub_y, sub_size * 0.7, text);
        }
    }

    // ── Shaping card ──
    {
        const x = layout.shaping.x + pad;
        var y = layout.shaping.y + pad;
        _ = try builder.addText(.{ .weight = .bold }, "Shaping", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Ligatures
        _ = try builder.addText(.{}, "Ligatures", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try builder.addText(.{}, "office ffi fl ffl", x, y + body_size, body_size, text);
        y += line_h + 16 * s;

        // Kerning
        _ = try builder.addText(.{}, "Kerning", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try builder.addText(.{}, "AV To VA Ty", x, y + body_size, body_size, text);
        y += line_h + 16 * s;

        // Mixed sample
        _ = try builder.addText(.{}, "Sphinx of black", x, y + 18 * s, 16 * s, muted);
        y += 22 * s;
        _ = try builder.addText(.{}, "quartz, judge", x, y + 18 * s, 16 * s, muted);
        y += 22 * s;
        _ = try builder.addText(.{}, "my vow.", x, y + 18 * s, 16 * s, muted);
    }

    // ── Scripts card ──
    {
        const x = layout.scripts.x + pad;
        var y = layout.scripts.y + pad;
        _ = try builder.addText(.{ .weight = .bold }, "Scripts", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        const script_size = 18 * s;
        const script_line = 24 * s;

        // Each script on its own line (FontCollection handles fallback)
        _ = try builder.addText(.{}, "Latin", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try builder.addText(.{}, "Hello, world!", x, y + script_size, script_size, text);
        y += script_line + 4 * s;

        _ = try builder.addText(.{}, "Arabic", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try builder.addText(.{}, "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7", x, y + script_size, script_size, text)).missing) had_missing = true; // مرحبا
        y += script_line + 4 * s;

        _ = try builder.addText(.{}, "Devanagari", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try builder.addText(.{}, "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87", x, y + script_size, script_size, text)).missing) had_missing = true; // नमस्ते
        y += script_line + 4 * s;

        _ = try builder.addText(.{}, "Thai", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try builder.addText(.{}, "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5", x, y + script_size, script_size, text)).missing) had_missing = true; // สวัสดี
        y += script_line + 4 * s;

        _ = try builder.addText(.{}, "Emoji", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try builder.addText(.{}, "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88", x, y + script_size, script_size, text)).missing) had_missing = true; // ✨🌍🎨🚀🐌🌈
    }

    // ── Vectors card labels ──
    {
        const x = layout.vectors.x + pad;
        var y = layout.vectors.y + pad;
        const sz = shape_sz * s;
        const gap = shape_gap * s;
        const item_label = 11 * s;

        _ = try builder.addText(.{ .weight = .bold }, "Vectors", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Row 1: "Shapes" sub-heading
        _ = try builder.addText(.{}, "Shapes", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;

        // Shape labels below row 1
        const shape_label_y = y + sz + 2 * s;
        var lx = x;
        const shape_labels = [_][]const u8{ "rect", "round", "ellipse", "path", "stroke" };
        for (shape_labels) |lbl| {
            _ = try builder.addText(.{}, lbl, lx, shape_label_y + item_label, item_label, muted);
            lx += sz + gap;
        }

        // Row 2: "Fills" sub-heading
        const fills_label_y = shape_label_y + item_label + 6 * s;
        _ = try builder.addText(.{}, "Fills", x, fills_label_y + sub_label_size, sub_label_size, muted);

        // Fill labels below row 2
        const fill_shapes_y = fills_label_y + sub_label_size + 6 * s;
        const fill_label_y = fill_shapes_y + sz + 2 * s;
        lx = x;
        const fill_labels = [_][]const u8{ "solid", "linear", "radial", "image" };
        for (fill_labels) |lbl| {
            _ = try builder.addText(.{}, lbl, lx, fill_label_y + item_label, item_label, muted);
            lx += sz + gap;
        }
    }

    return .{ .decoration_count = decoration_count, .missing = had_missing };
}

// ── Snail vector illustration ──

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
    transform: snail.Transform2D,
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

    var ribbon = snail.Path.init(builder.allocator);
    defer ribbon.deinit();
    try ribbon.moveTo(snail.Vec2.add(start, start_normal));
    try ribbon.quadTo(snail.Vec2.add(control, mid_normal), snail.Vec2.add(end, end_normal));
    try ribbon.quadTo(snail.Vec2.add(end, tip_cap), snail.Vec2.sub(end, end_normal));
    try ribbon.quadTo(snail.Vec2.sub(control, mid_normal), snail.Vec2.sub(start, start_normal));
    try ribbon.close();
    try builder.addFilledPath(&ribbon, .{ .color = color }, transform);
}

pub fn addVectorSnail(builder: *snail.PathPictureBuilder, snail_stage: snail.Rect) !void {
    const art_width = @min(snail_stage.w * 0.82, 440.0);
    const scale = art_width / 360.0;
    const art_height = 220.0 * scale;
    const art_x = snail_stage.x + (snail_stage.w - art_width) * 0.5;
    const art_y = snail_stage.y + (snail_stage.h - art_height) * 0.5 + 10.0;
    const transform = snail.Transform2D.multiply(
        snail.Transform2D.translate(art_x, art_y),
        snail.Transform2D.scale(scale, scale),
    );

    // Shadow
    try builder.addFilledEllipse(.{
        .x = 62.0, .y = 168.0, .w = 240.0, .h = 28.0,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 182.0, .y = 182.0 },
        .radius = 125.0,
        .inner_color = .{ 0.0, 0.0, 0.0, 0.18 },
        .outer_color = .{ 0.0, 0.0, 0.0, 0.0 },
    } } }, transform);

    // Body — soft warm gradient
    var body = snail.Path.init(builder.allocator);
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
        .start_color = .{ 0.38, 0.48, 0.38, 0.95 },
        .end_color = .{ 0.68, 0.65, 0.52, 0.95 },
    } } }, .{
        .color = .{ 0.45, 0.50, 0.38, 0.50 },
        .width = 2.0,
        .join = .round,
    }, transform);

    // Belly highlight
    var belly = snail.Path.init(builder.allocator);
    defer belly.deinit();
    try belly.moveTo(.{ .x = 92.0, .y = 140.0 });
    try belly.cubicTo(.{ .x = 138.0, .y = 132.0 }, .{ .x = 204.0, .y = 136.0 }, .{ .x = 274.0, .y = 142.0 });
    try builder.addStrokedPath(&belly, .{
        .color = .{ 1.0, 1.0, 0.95, 0.35 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    // Shell — translucent teal radial falloff
    try builder.addEllipse(.{
        .x = 156.0, .y = 24.0, .w = 114.0, .h = 114.0,
    }, .{ .paint = .{ .radial_gradient = .{
        .center = .{ .x = 208.0, .y = 68.0 },
        .radius = 72.0,
        .inner_color = .{ 0.62, 0.82, 0.92, 0.55 },
        .outer_color = .{ 0.25, 0.45, 0.62, 0.88 },
    } } }, .{
        .color = .{ 0.35, 0.60, 0.78, 0.65 },
        .width = 2.4,
        .join = .round,
    }, transform);

    // Spiral — warm amber/orange
    var spiral = snail.Path.init(builder.allocator);
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
            .start_color = .{ 0.92, 0.72, 0.28, 0.92 },
            .end_color = .{ 0.85, 0.45, 0.18, 0.88 },
        } },
        .width = 9.0,
        .cap = .round,
        .join = .round,
    }, transform);

    // Tentacles
    try addFilledQuadraticRibbon(builder, .{ .x = 308.0, .y = 100.0 }, .{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 }, 2.0, .{ 0.58, 0.58, 0.52, 0.90 }, transform);
    try addFilledQuadraticRibbon(builder, .{ .x = 294.0, .y = 102.0 }, .{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 }, 2.0, .{ 0.58, 0.58, 0.52, 0.90 }, transform);

    // Eyes — outlined sclera, dark iris, specular highlight
    const eye_stroke = snail.StrokeStyle{ .color = .{ 0.30, 0.32, 0.28, 0.80 }, .width = 1.2, .join = .round };
    // Outer eye
    try builder.addEllipse(.{ .x = 330.0, .y = 54.0, .w = 9.0, .h = 9.0 }, .{ .color = .{ 0.98, 0.97, 0.94, 1.0 } }, eye_stroke, transform);
    try builder.addFilledEllipse(.{ .x = 332.0, .y = 56.0, .w = 5.0, .h = 5.0 }, .{ .color = .{ 0.18, 0.20, 0.22, 1.0 } }, transform);
    try builder.addFilledEllipse(.{ .x = 333.0, .y = 56.5, .w = 1.5, .h = 1.5 }, .{ .color = .{ 1.0, 1.0, 1.0, 0.90 } }, transform);
    // Inner eye
    try builder.addEllipse(.{ .x = 303.0, .y = 61.0, .w = 7.0, .h = 7.0 }, .{ .color = .{ 0.98, 0.97, 0.94, 1.0 } }, eye_stroke, transform);
    try builder.addFilledEllipse(.{ .x = 304.5, .y = 62.5, .w = 4.0, .h = 4.0 }, .{ .color = .{ 0.18, 0.20, 0.22, 1.0 } }, transform);
    try builder.addFilledEllipse(.{ .x = 305.2, .y = 63.0, .w = 1.2, .h = 1.2 }, .{ .color = .{ 1.0, 1.0, 1.0, 0.90 } }, transform);

    // Smile
    var smile = snail.Path.init(builder.allocator);
    defer smile.deinit();
    try smile.moveTo(.{ .x = 314.0, .y = 119.0 });
    try smile.quadTo(.{ .x = 321.0, .y = 123.0 }, .{ .x = 329.0, .y = 119.0 });
    try builder.addStrokedPath(&smile, .{
        .color = .{ 0.25, 0.28, 0.22, 0.70 },
        .width = 2.0,
        .cap = .round,
        .join = .round,
    }, transform);
}
