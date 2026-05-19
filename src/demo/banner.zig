const std = @import("std");
const snail = @import("snail");
const banner_snail = @import("banner_snail.zig");
const Allocator = std.mem.Allocator;

pub const addVectorSnail = banner_snail.addVectorSnail;

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
    paint_image: *const snail.Image,
    decoration_rects: []const snail.Rect,
) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    const s = layout.scale;
    const r = 10 * s;
    const stroke_w = 1.0 * s;
    const card_stroke = snail.StrokeStyle{ .paint = .{ .solid = border }, .width = stroke_w, .join = .round, .placement = .inside };
    const card_fill = snail.FillStyle{ .paint = .{ .solid = surface } };

    // Background
    try builder.addFilledRect(layout.canvas, .{ .paint = .{ .solid = bg } }, .identity);

    // Card backgrounds
    try builder.addRoundedRect(layout.styles, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.decorations, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.shaping, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.scripts, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.vectors, card_fill, card_stroke, r, .identity);
    try builder.addRoundedRect(layout.snail_stage, card_fill, card_stroke, r, .identity);

    // Decoration lines (underline/strikethrough rects collected from drawText)
    for (decoration_rects) |rect| {
        try builder.addFilledRect(rect, .{ .paint = .{ .solid = text } }, .identity);
    }

    // Vector shape demos
    try addVectorShapes(&builder, layout, paint_image);

    // The snail illustration
    try addVectorSnail(&builder, layout.snail_stage);

    return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
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
    paint_image: *const snail.Image,
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
        .paint = .{ .solid = .{ 0.22, 0.50, 0.88, 1.0 } },
    }, .{
        .paint = .{ .solid = .{ 0.15, 0.38, 0.72, 1.0 } },
        .width = stroke_w,
        .join = .miter,
        .placement = .inside,
    }, .identity);

    // Rounded rect
    const rrx = x0 + sz + gap;
    try builder.addRoundedRect(.{ .x = rrx, .y = shapes_y, .w = sz, .h = sz }, .{
        .paint = .{ .solid = .{ 0.92, 0.82, 0.48, 1.0 } },
    }, .{
        .paint = .{ .solid = .{ 0.78, 0.62, 0.22, 1.0 } },
        .width = stroke_w,
        .join = .round,
        .placement = .inside,
    }, 12 * s, .identity);

    // Ellipse
    const elx = x0 + (sz + gap) * 2;
    try builder.addEllipse(.{ .x = elx, .y = shapes_y, .w = sz, .h = sz }, .{
        .paint = .{ .solid = .{ 0.85, 0.52, 0.35, 1.0 } },
    }, .{
        .paint = .{ .solid = .{ 0.72, 0.38, 0.22, 1.0 } },
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
        .paint = .{ .solid = .{ 0.58, 0.48, 0.82, 1.0 } },
    }, .{
        .paint = .{ .solid = .{ 0.42, 0.32, 0.68, 1.0 } },
        .width = stroke_w,
        .join = .round,
    }, .identity);

    // ── Row 2: Fills ──
    // Y: shapes_y + sz + label below + gap + "Fills" sub-heading + gap
    const fills_y = shapes_y + sz + 11 * s + 6 * s + sub_heading_size * s + 6 * s;

    // Solid fill
    try builder.addRoundedRect(.{ .x = x0, .y = fills_y, .w = sz, .h = sz }, .{
        .paint = .{ .solid = .{ 0.35, 0.72, 0.55, 1.0 } },
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
    const image_period = sz;
    try builder.addRoundedRect(.{ .x = imx, .y = fills_y, .w = sz, .h = sz }, .{
        .paint = .{ .image = .{
            .image = paint_image,
            .uv_transform = .{
                .xx = 1.0 / image_period,
                .yy = 1.0 / image_period,
                .tx = -imx / image_period,
                .ty = -fills_y / image_period,
            },
            .filter = .nearest,
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
        .paint = .{ .solid = .{ 0.22, 0.55, 0.80, 1.0 } },
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

pub const TextHintOptions = struct {
    enabled: bool = false,
    ppem_scale: f32 = 1.0,
    max_ppem: f32 = 32.0,
};

const TextPlacement = struct {
    x: f32,
    y: f32,
    size: f32,
};

const TextHintBuildContext = struct {
    context: *snail.TrueTypeHintContext,
    ppem_scale: f32,
    max_ppem: f32,

    fn shouldHintSize(self: *const TextHintBuildContext, font_size: f32) bool {
        const ppem = font_size * self.ppem_scale;
        return std.math.isFinite(ppem) and ppem >= 1.0 and ppem <= self.max_ppem;
    }
};

const TextPlacer = struct {
    builder: *snail.TextBlobBuilder,
    snap_step: snail.Vec2,
    hint: ?TextHintBuildContext = null,

    fn place(self: TextPlacer, x: f32, y: f32, size: f32) TextPlacement {
        const point = snail.snapPointToStep(.{ .x = x, .y = y }, self.snap_step, .nearest);
        return .{
            .x = point.x,
            .y = point.y,
            .size = snail.snapLengthToStep(size, self.snap_step.y, .nearest, 1.0),
        };
    }

    fn appendPlaced(
        self: TextPlacer,
        style: snail.FontStyle,
        string: []const u8,
        p: TextPlacement,
        color: [4]f32,
    ) !snail.TextAppendResult {
        return self.appendPlacedPaint(style, string, p, .{ .solid = color });
    }

    fn appendPlacedPaint(
        self: TextPlacer,
        style: snail.FontStyle,
        string: []const u8,
        p: TextPlacement,
        paint: snail.Paint,
    ) !snail.TextAppendResult {
        var shaped = try self.builder.atlas.shapeText(self.builder.allocator, style, string);
        defer shaped.deinit();

        if (self.hint) |hint_context| {
            switch (paint) {
                .solid => |color| {
                    if (hint_context.shouldHintSize(p.size)) {
                        return self.appendPlacedHinted(hint_context, &shaped, p, color) catch |err| {
                            if (err == error.OutOfMemory) return err;
                            return self.appendRegular(&shaped, p, paint);
                        };
                    }
                },
                else => {},
            }
        }
        return self.appendRegular(&shaped, p, paint);
    }

    fn appendRegular(
        self: TextPlacer,
        shaped: *const snail.ShapedText,
        p: TextPlacement,
        paint: snail.Paint,
    ) !snail.TextAppendResult {
        return self.builder.append(.{
            .shaped = shaped,
            .placement = .{ .baseline = .{ .x = p.x, .y = p.y }, .em = p.size },
            .fill = paint,
        });
    }

    fn appendPlacedHinted(
        self: TextPlacer,
        hint_context: TextHintBuildContext,
        shaped: *const snail.ShapedText,
        p: TextPlacement,
        color: [4]f32,
    ) !snail.TextAppendResult {
        const ppem_26_6 = try hintPpem26_6(p.size, hint_context.ppem_scale);
        const ppem = snail.TrueTypeHintPpem.uniform(ppem_26_6);
        var run_keys = try snail.gatherTrueTypeHintRunKeys(self.builder.allocator, shaped, .{}, ppem);
        defer run_keys.deinit();

        var availability = try prepareRunHints(self.builder.allocator, hint_context.context, &run_keys);
        defer availability.deinit();
        if (!availability.ready()) return error.HintUnavailable;

        var plan = try snail.planHintedRun(self.builder.allocator, .{
            .atlas = self.builder.atlas,
            .shaped = shaped,
            .placement = .{ .baseline = .{ .x = p.x, .y = p.y }, .em = p.size },
            .hinted_glyphs = availability.glyphs,
        });
        defer plan.deinit();

        try self.appendHintedPlan(&plan, color);
        return .{ .advance = plan.stats.advance, .missing = false };
    }

    fn appendHintedPlan(
        self: TextPlacer,
        plan: *const snail.TextHintRunPlan,
        color: [4]f32,
    ) !void {
        for (plan.placements, plan.hinted_glyphs) |placement, hint_or_null| {
            const hint = hint_or_null orelse return error.HintUnavailable;
            if (!hint.renderable()) continue;
            try self.builder.appendHintedGlyphRef(
                placement.face_index,
                placement.glyph_id,
                placement.transform,
                color,
                hint,
            );
        }
    }

    fn addText(
        self: TextPlacer,
        style: snail.FontStyle,
        string: []const u8,
        x: f32,
        y: f32,
        size: f32,
        color: [4]f32,
    ) !snail.TextAppendResult {
        const p = self.place(x, y, size);
        return self.appendPlaced(style, string, p, color);
    }

    fn addPaintedText(
        self: TextPlacer,
        style: snail.FontStyle,
        string: []const u8,
        x: f32,
        y: f32,
        size: f32,
        paint: snail.Paint,
    ) !snail.TextAppendResult {
        const p = self.place(x, y, size);
        return self.appendPlacedPaint(style, string, p, paint);
    }
};

fn hintPpem26_6(font_size: f32, ppem_scale: f32) !u32 {
    const ppem = font_size * ppem_scale;
    if (!std.math.isFinite(ppem) or ppem < 1.0) return error.HintUnavailable;
    return @intFromFloat(@round(@min(ppem, 4096.0) * 64.0));
}

fn prepareRunHints(
    allocator: std.mem.Allocator,
    context: *snail.TrueTypeHintContext,
    keys: *const snail.TrueTypeHintRunKeys,
) !snail.TrueTypeHintRunAvailability {
    var availability = try context.queryRun(allocator, keys);
    if (availability.unsupported.len != 0 or availability.missing_keys.len == 0) return availability;

    for (availability.missing_keys) |key| {
        _ = try context.computeGlyph(key);
    }
    availability.deinit();
    return context.queryRun(allocator, keys);
}

/// Build the demo's prepared text blob and collect decoration rects.
pub fn buildTextBlob(
    builder: *snail.TextBlobBuilder,
    layout: Layout,
    snap_step: snail.Vec2,
    fonts: *const snail.TextAtlas,
    hint_context: ?*snail.TrueTypeHintContext,
    paint_image: *const snail.Image,
    decoration_rects_out: []snail.Rect,
    hint_options: TextHintOptions,
) !TextBuildResult {
    var decoration_count: usize = 0;
    var had_missing = false;
    const hint_build_context: ?TextHintBuildContext = if (hint_options.enabled and hint_context != null)
        .{ .context = hint_context.?, .ppem_scale = hint_options.ppem_scale, .max_ppem = hint_options.max_ppem }
    else
        null;

    const placer = TextPlacer{ .builder = builder, .snap_step = snap_step, .hint = hint_build_context };
    const s = layout.scale;
    const pad = card_pad * s;
    const label_size = heading_size * s;
    const sub_label_size = sub_heading_size * s;
    const body_size = body_text_size * s;
    const line_h = body_line_h * s;

    // ── Title ──
    _ = try placer.addPaintedText(.{ .weight = .bold }, "snail", layout.title.x, layout.title.y + 58 * s, 64 * s, .{ .linear_gradient = .{
        .start = .{ .x = layout.title.x, .y = layout.title.y },
        .end = .{ .x = layout.title.x + 190 * s, .y = layout.title.y + 72 * s },
        .start_color = accent,
        .end_color = text,
    } });
    _ = try placer.addText(.{}, "GPU text & vector rendering", layout.title.x + 210 * s, layout.title.y + 50 * s, 20 * s, muted);

    // ── Styles card ──
    {
        const x = layout.styles.x + pad;
        var y = layout.styles.y + pad;
        _ = try placer.addText(.{ .weight = .bold }, "Styles", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        _ = try placer.addText(.{}, "Regular", x, y + body_size, body_size, text);
        y += line_h;
        _ = try placer.addText(.{ .weight = .bold }, "Bold", x, y + body_size, body_size, text);
        y += line_h;
        _ = try placer.addText(.{ .italic = true }, "Italic", x, y + body_size, body_size, text);
        y += line_h;
        _ = try placer.addText(.{ .weight = .bold, .italic = true }, "Bold Italic", x, y + body_size, body_size, text);
        y += line_h;
        _ = try placer.addText(.{ .weight = .semi_bold }, "Synthetic", x, y + body_size, body_size, text);
        y += line_h + 8 * s;

        _ = try placer.addText(.{}, "Mixed styles", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        var rx = x;
        const mixed_baseline = y + body_size;
        rx += (try placer.addText(.{ .weight = .bold }, "Bold ", rx, mixed_baseline, body_size, text)).advance.x;
        rx += (try placer.addPaintedText(.{ .weight = .bold }, "gradient", rx, mixed_baseline, body_size, .{ .linear_gradient = .{
            .start = .{ .x = rx, .y = mixed_baseline - body_size },
            .end = .{ .x = rx + 92 * s, .y = mixed_baseline },
            .start_color = .{ 0.18, 0.50, 0.88, 1.0 },
            .end_color = .{ 0.88, 0.30, 0.56, 1.0 },
        } })).advance.x;
        _ = try placer.addText(.{}, " / small", rx, mixed_baseline, 14 * s, muted);
        y += line_h + 4 * s;

        // Size ramp
        const sizes = [_]f32{ 10, 14, 18, 24, 32 };
        var sx = x;
        for (sizes) |sz| {
            const fs = sz * s;
            sx += (try placer.addText(.{}, "Aa", sx, y + 32 * s, fs, muted)).advance.x + 12 * s;
        }
    }

    // ── Decorations card ──
    {
        const x = layout.decorations.x + pad;
        var y = layout.decorations.y + pad;
        _ = try placer.addText(.{ .weight = .bold }, "Decorations", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Underlined
        const ul_place = placer.place(x, y + body_size, body_size);
        const ul_advance = (try placer.appendPlaced(.{}, "Underlined", ul_place, text)).advance.x;
        if (decoration_count < decoration_rects_out.len) {
            decoration_rects_out[decoration_count] = try fonts.decorationRect(.underline, ul_place.x, ul_place.y, ul_advance, ul_place.size);
            decoration_count += 1;
        }
        y += line_h;

        // Struck
        const st_place = placer.place(x, y + body_size, body_size);
        const st_advance = (try placer.appendPlaced(.{}, "Struck", st_place, text)).advance.x;
        if (decoration_count < decoration_rects_out.len) {
            decoration_rects_out[decoration_count] = try fonts.decorationRect(.strikethrough, st_place.x, st_place.y, st_advance, st_place.size);
            decoration_count += 1;
        }
        y += line_h + 16 * s;

        // CH₅⁺ + C₂H₆ → C₂H₇⁺ + CH₄
        const sub_size = body_size * 1.2;
        const sub_y = y + sub_size;
        var cx = x;

        // CH₅⁺
        cx += (try placer.addText(.{}, "CH", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try placer.addText(.{}, "5", sub.x, sub.y, sub.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "5", cx, sub_y, sub_size * 0.7, text)).advance.x;
        }
        if (fonts.superscriptTransform(cx, sub_y, sub_size)) |sup| {
            cx += (try placer.addText(.{}, "+", sup.x, sup.y, sup.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "+", cx, sub_y - sub_size * 0.4, sub_size * 0.7, text)).advance.x;
        }

        cx += (try placer.addText(.{}, " + ", cx, sub_y, sub_size, text)).advance.x;

        // C₂H₆
        cx += (try placer.addText(.{}, "C", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try placer.addText(.{}, "2", sub.x, sub.y, sub.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "2", cx, sub_y, sub_size * 0.7, text)).advance.x;
        }
        cx += (try placer.addText(.{}, "H", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try placer.addText(.{}, "6", sub.x, sub.y, sub.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "6", cx, sub_y, sub_size * 0.7, text)).advance.x;
        }

        {
            const r = try placer.addText(.{}, " \u{2192} ", cx, sub_y, sub_size, text);
            cx += r.advance.x;
            if (r.missing) had_missing = true;
        }

        // C₂H₇⁺
        cx += (try placer.addText(.{}, "C", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try placer.addText(.{}, "2", sub.x, sub.y, sub.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "2", cx, sub_y, sub_size * 0.7, text)).advance.x;
        }
        cx += (try placer.addText(.{}, "H", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            cx += (try placer.addText(.{}, "7", sub.x, sub.y, sub.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "7", cx, sub_y, sub_size * 0.7, text)).advance.x;
        }
        if (fonts.superscriptTransform(cx, sub_y, sub_size)) |sup| {
            cx += (try placer.addText(.{}, "+", sup.x, sup.y, sup.font_size, text)).advance.x;
        } else |_| {
            cx += (try placer.addText(.{}, "+", cx, sub_y - sub_size * 0.4, sub_size * 0.7, text)).advance.x;
        }

        cx += (try placer.addText(.{}, " + ", cx, sub_y, sub_size, text)).advance.x;

        // CH₄
        cx += (try placer.addText(.{}, "CH", cx, sub_y, sub_size, text)).advance.x;
        if (fonts.subscriptTransform(cx, sub_y, sub_size)) |sub| {
            _ = try placer.addText(.{}, "4", sub.x, sub.y, sub.font_size, text);
        } else |_| {
            _ = try placer.addText(.{}, "4", cx, sub_y, sub_size * 0.7, text);
        }
    }

    // ── Shaping card ──
    {
        const x = layout.shaping.x + pad;
        var y = layout.shaping.y + pad;
        _ = try placer.addText(.{ .weight = .bold }, "Shaping", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Ligatures
        _ = try placer.addText(.{}, "Ligatures", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try placer.addText(.{}, "office ffi fl ffl", x, y + body_size, body_size, text);
        y += line_h + 16 * s;

        // Kerning
        _ = try placer.addText(.{}, "Kerning", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try placer.addText(.{}, "AV To VA Ty", x, y + body_size, body_size, text);
        y += line_h + 16 * s;

        // Mixed sample
        _ = try placer.addText(.{}, "Sphinx of black", x, y + 18 * s, 16 * s, muted);
        y += 22 * s;
        _ = try placer.addText(.{}, "quartz, judge", x, y + 18 * s, 16 * s, muted);
        y += 22 * s;
        _ = try placer.addText(.{}, "my vow.", x, y + 18 * s, 16 * s, muted);
    }

    // ── Scripts card ──
    {
        const x = layout.scripts.x + pad;
        var y = layout.scripts.y + pad;
        _ = try placer.addText(.{ .weight = .bold }, "Scripts", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        const script_size = 18 * s;
        const script_line = 24 * s;

        // Each script on its own line (FontCollection handles fallback)
        _ = try placer.addText(.{}, "Latin", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        _ = try placer.addText(.{}, "Hello, world!", x, y + script_size, script_size, text);
        y += script_line + 4 * s;

        _ = try placer.addText(.{}, "Arabic", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try placer.addText(.{}, "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7", x, y + script_size, script_size, text)).missing) had_missing = true; // مرحبا
        y += script_line + 4 * s;

        _ = try placer.addText(.{}, "Devanagari", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try placer.addText(.{}, "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87", x, y + script_size, script_size, text)).missing) had_missing = true; // नमस्ते
        y += script_line + 4 * s;

        _ = try placer.addText(.{}, "Thai", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try placer.addText(.{}, "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5", x, y + script_size, script_size, text)).missing) had_missing = true; // สวัสดี
        y += script_line + 4 * s;

        _ = try placer.addText(.{}, "Emoji", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;
        if ((try placer.addText(.{}, "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88", x, y + script_size, script_size, text)).missing) had_missing = true; // ✨🌍🎨🚀🐌🌈
    }

    // ── Vectors card labels ──
    {
        const x = layout.vectors.x + pad;
        var y = layout.vectors.y + pad;
        const sz = shape_sz * s;
        const gap = shape_gap * s;
        const item_label = 11 * s;

        _ = try placer.addText(.{ .weight = .bold }, "Primitives", x, y + label_size, label_size, accent);
        y += label_size + 14 * s;

        // Row 1: "Shapes" sub-heading
        _ = try placer.addText(.{}, "Shapes", x, y + sub_label_size, sub_label_size, muted);
        y += sub_label_size + 6 * s;

        // Shape labels below row 1
        const shape_label_y = y + sz + 2 * s;
        var lx = x;
        const shape_labels = [_][]const u8{ "rect", "round", "ellipse", "path", "stroke" };
        for (shape_labels) |lbl| {
            _ = try placer.addText(.{}, lbl, lx, shape_label_y + item_label, item_label, muted);
            lx += sz + gap;
        }

        // Row 2: "Fills" sub-heading
        const fills_label_y = shape_label_y + item_label + 6 * s;
        _ = try placer.addText(.{}, "Fills", x, fills_label_y + sub_label_size, sub_label_size, muted);

        // Fill labels below row 2
        const fill_shapes_y = fills_label_y + sub_label_size + 6 * s;
        const fill_label_y = fill_shapes_y + sz + 2 * s;
        lx = x;
        const fill_labels = [_][]const u8{ "solid", "linear", "radial", "image" };
        for (fill_labels) |lbl| {
            _ = try placer.addText(.{}, lbl, lx, fill_label_y + item_label, item_label, muted);
            lx += sz + gap;
        }

        // Row 3: text using the same Paint primitives.
        const text_paint_label_y = fill_label_y + item_label + 14 * s;
        _ = try placer.addText(.{}, "Text paint", x, text_paint_label_y + sub_label_size, sub_label_size, muted);
        const paint_text_size = 26 * s;
        const paint_text_y = text_paint_label_y + sub_label_size + 8 * s;
        const gradient_baseline = paint_text_y + paint_text_size;
        const gradient_advance = (try placer.addPaintedText(.{ .weight = .bold }, "gradient", x, gradient_baseline, paint_text_size, .{ .linear_gradient = .{
            .start = .{ .x = x, .y = gradient_baseline - paint_text_size },
            .end = .{ .x = x + 132 * s, .y = gradient_baseline },
            .start_color = .{ 0.18, 0.50, 0.88, 1.0 },
            .end_color = .{ 0.88, 0.30, 0.56, 1.0 },
        } })).advance.x;

        const image_x = x + gradient_advance + 34 * s;
        const image_period = 30 * s;
        _ = try placer.addPaintedText(.{ .weight = .bold }, "image", image_x, gradient_baseline, paint_text_size, .{ .image = .{
            .image = paint_image,
            .uv_transform = .{
                .xx = 1.0 / image_period,
                .yy = 1.0 / image_period,
                .tx = -image_x / image_period,
                .ty = -(gradient_baseline - paint_text_size) / image_period,
            },
            .extend_x = .repeat,
            .extend_y = .repeat,
            .filter = .nearest,
        } });
    }

    return .{ .decoration_count = decoration_count, .missing = had_missing };
}
