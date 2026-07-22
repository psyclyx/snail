//! Reusable snail-content toolkit for the game demo.
//!
//! `Fonts` owns the shaper + faces + page pool shared across the scene.
//! `PassBuilder` accumulates vector paths + shaped runs into a `PreparedPass`
//! (a path atlas/picture + a text atlas/picture). The scene (`scene.zig`) uses
//! these to author every element — the HUD, the world panel, the occluded
//! label, and the text whose coverage the custom material shader samples.
//!
//! Nothing here is backend-specific: a `PreparedPass` is pure snail data that
//! any backend's renderer + cache consumes via the shared `driver_common`
//! pass machinery.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");
const assets = @import("assets");

// ── Fonts ──

/// Long-lived shaper + Font slots + page pool used to build every pass. One
/// `Fonts` value is shared across the entire game scene.
pub const Fonts = struct {
    allocator: std.mem.Allocator,
    faces: snail.Faces,
    /// Heap-allocated so `Faces.face(i).font` (raw `*const Font`) survives
    /// `Fonts` getting moved during `init`'s return-by-value.
    fonts: []snail.Font,
    pool: *snail.PagePool,

    pub const face_count: usize = 2;

    pub fn init(allocator: std.mem.Allocator) !Fonts {
        const fonts = try allocator.alloc(snail.Font, face_count);
        errdefer allocator.free(fonts);
        const datas = [_][]const u8{ assets.noto_sans_regular, assets.noto_sans_bold };
        for (datas, 0..) |data, i| {
            fonts[i] = try snail.Font.init(data);
        }

        var faces = try snail.Faces.build(allocator, &.{
            .{ .font = &fonts[0] },
            .{ .font = &fonts[1], .weight = .bold },
        });
        errdefer faces.deinit();

        const pool = try snail.PagePool.init(allocator, .{
            .max_layers = 32,
            .curve_words_per_page = 1 << 17,
            .band_words_per_page = 1 << 14,
        });
        errdefer pool.deinit();

        return .{
            .allocator = allocator,
            .faces = faces,
            .fonts = fonts,
            .pool = pool,
        };
    }

    pub fn deinit(self: *Fonts) void {
        self.pool.deinit();
        self.faces.deinit();
        self.allocator.free(self.fonts);
        self.* = undefined;
    }

    pub fn measureText(self: *Fonts, style: snail.FontStyle, text: []const u8, font_size: f32) !f32 {
        var shaped = try snail.shape(self.allocator, &self.faces, text, .{ .style = style });
        defer shaped.deinit();
        return shaped.advanceX() * font_size;
    }
};

pub fn initFonts(allocator: std.mem.Allocator) !Fonts {
    return Fonts.init(allocator);
}

// ── Pass builder ──

/// Accumulates atlas entries + shapes for a single pass. Sealed via `freeze`
/// into a `PreparedPass`.
pub const PassBuilder = struct {
    allocator: std.mem.Allocator,
    fonts: *Fonts,

    // Path namespace: vector paths + per-glyph painted text glyphs.
    path_curves_owned: std.ArrayList(snail.GlyphCurves),
    path_entries: std.ArrayList(snail.AtlasEntry),
    path_shapes: std.ArrayList(snail.Shape),
    extra_layer_storage: std.ArrayList([]snail.AtlasLayer),
    next_path_id: u32,

    // Text namespace: solid-colored shaped runs, recorded straight into
    // the store (`recordUnhintedRun`).
    text_atlas: snail.Atlas,
    text_shapes: std.ArrayList(snail.Shape),

    pub fn init(allocator: std.mem.Allocator, fonts: *Fonts) snail.PagePool.IdentityError!PassBuilder {
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .path_curves_owned = .empty,
            .path_entries = .empty,
            .path_shapes = .empty,
            .extra_layer_storage = .empty,
            .next_path_id = 0,
            .text_atlas = try snail.Atlas.init(allocator, fonts.pool),
            .text_shapes = .empty,
        };
    }

    pub fn deinit(self: *PassBuilder) void {
        for (self.path_curves_owned.items) |*c| c.deinit();
        self.path_curves_owned.deinit(self.allocator);
        self.path_entries.deinit(self.allocator);
        self.path_shapes.deinit(self.allocator);
        for (self.extra_layer_storage.items) |s| self.allocator.free(s);
        self.extra_layer_storage.deinit(self.allocator);

        self.text_atlas.deinit();
        self.text_shapes.deinit(self.allocator);
    }

    pub fn addFilledPath(self: *PassBuilder, path: *const snail.Path, paint: snail.Paint) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const curves = try prepared.fillCurves(self.allocator, self.allocator);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.path_curves_owned.append(self.allocator, curves);
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = prepared.paintForDesign(paint),
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = prepared.design_to_source,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    pub fn addStrokedPath(self: *PassBuilder, path: *const snail.Path, stroke: snail.StrokeStyle) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const curves = try prepared.strokeCurves(self.allocator, self.allocator, stroke);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.path_curves_owned.append(self.allocator, curves);
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_stroke, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = prepared.paintForDesign(stroke.paint),
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = prepared.design_to_source,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    pub fn addPathFillAndInsideStroke(
        self: *PassBuilder,
        path: *const snail.Path,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
        place: snail.Transform2D,
    ) !void {
        std.debug.assert(stroke.placement == .inside);

        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const fill_curves = try prepared.fillCurves(self.allocator, self.allocator);
        if (fill_curves.isEmpty()) {
            var owned = fill_curves;
            owned.deinit();
            try self.addStrokedPath(path, stroke);
            return;
        }
        const stroke_curves = try prepared.strokeCurves(self.allocator, self.allocator, stroke);
        if (stroke_curves.isEmpty()) {
            try self.path_curves_owned.append(self.allocator, fill_curves);
            const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_path_id };
            self.next_path_id += 1;
            try self.path_entries.append(self.allocator, .{
                .key = key,
                .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
                .paint = prepared.paintForDesign(fill),
            });
            try self.path_shapes.append(self.allocator, .{
                .key = key,
                .local_transform = prepared.placedBy(place),
                .local_color = .{ 1, 1, 1, 1 },
            });
            var owned_stroke = stroke_curves;
            owned_stroke.deinit();
            return;
        }

        try self.path_curves_owned.append(self.allocator, fill_curves);
        try self.path_curves_owned.append(self.allocator, stroke_curves);

        const extras = try self.allocator.alloc(snail.AtlasLayer, 1);
        extras[0] = .{
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = prepared.paintForDesign(stroke.paint),
        };
        try self.extra_layer_storage.append(self.allocator, extras);

        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 2],
            .paint = prepared.paintForDesign(fill),
            .extra_layers = extras,
            .composite_mode = .fill_stroke_inside,
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = prepared.placedBy(place),
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    /// HUD/world panels: author the rounded rect in a unit frame
    /// (aspect-preserving) and place it uniformly, so corners stay crisp at the
    /// panel's screen offset. Paints are remapped into unit space.
    pub fn addRoundedRectWithInsideStroke(
        self: *PassBuilder,
        rect: snail.Rect,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
        radius: f32,
    ) !void {
        var p = try demo_support.unitRoundedRectPathFor(self.allocator, rect, radius);
        defer p.deinit();
        const to_paint = demo_support.placeRectUniform(rect);
        var unit_stroke = stroke;
        unit_stroke.width = demo_support.unitStrokeWidth(rect, stroke.width);
        unit_stroke.paint = snail.mapPaintToLocal(stroke.paint, to_paint) orelse stroke.paint;
        const local_fill = snail.mapPaintToLocal(fill, to_paint) orelse fill;
        try self.addPathFillAndInsideStroke(&p, local_fill, unit_stroke, to_paint);
    }

    /// Fill-only counterpart of `addRoundedRectWithInsideStroke`: identical
    /// unit-frame authoring + uniform placement + paint remap, but no stroke
    /// and no composite. The composite probe uses this to isolate whether the
    /// fill layer's coverage alone holes at a given `rc`.
    pub fn addRoundedRectFilledUnit(
        self: *PassBuilder,
        rect: snail.Rect,
        fill: snail.Paint,
        radius: f32,
    ) !void {
        var p = try demo_support.unitRoundedRectPathFor(self.allocator, rect, radius);
        defer p.deinit();
        const to_paint = demo_support.placeRectUniform(rect);
        const local_fill = snail.mapPaintToLocal(fill, to_paint) orelse fill;
        var prepared = try p.prepare(self.allocator);
        defer prepared.deinit();
        const fill_curves = try prepared.fillCurves(self.allocator, self.allocator);
        if (fill_curves.isEmpty()) {
            var owned = fill_curves;
            owned.deinit();
            return;
        }
        try self.path_curves_owned.append(self.allocator, fill_curves);
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = prepared.paintForDesign(local_fill),
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = prepared.placedBy(to_paint),
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    pub fn addFilledRect(self: *PassBuilder, rect: snail.Rect, paint: snail.Paint) !void {
        var p = snail.Path.init(self.allocator);
        defer p.deinit();
        try p.addRect(rect);
        try self.addFilledPath(&p, paint);
    }

    /// Filled rounded rect + a separate center-stroke border, as two independent
    /// shapes. Unlike `addRoundedRectWithInsideStroke` (the `fill_stroke_inside`
    /// composite), this leaves no coverage residue under perspective — the
    /// composite clips a center-stroke to the fill interior *per fragment*, and
    /// combining two coverage fields at grazing angles produces specks/seams.
    pub fn addRoundedRectFilledStroked(
        self: *PassBuilder,
        rect: snail.Rect,
        fill: snail.Paint,
        stroke_paint: snail.Paint,
        stroke_width: f32,
        radius: f32,
    ) !void {
        var p = snail.Path.init(self.allocator);
        defer p.deinit();
        try p.addRoundedRect(rect, radius);
        try self.addFilledPath(&p, fill);
        if (stroke_width > 0)
            try self.addStrokedPath(&p, .{ .paint = stroke_paint, .width = stroke_width, .placement = .center });
    }

    pub const TextResult = struct {
        advance_x: f32,
    };

    pub fn appendText(
        self: *PassBuilder,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        em: f32,
        color: [4]f32,
    ) !TextResult {
        return self.appendPaintedText(style, text, x, y, em, .{ .solid = color });
    }

    pub fn appendPaintedText(
        self: *PassBuilder,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        em: f32,
        paint: snail.Paint,
    ) !TextResult {
        var shaped = try snail.shape(self.allocator, &self.fonts.faces, text, .{ .style = style });
        defer shaped.deinit();

        const advance_x = em * shaped.advanceX();

        switch (paint) {
            .solid => |color| try self.emitSolidShapedRun(&shaped, x, y, em, color),
            else => try self.emitPaintedShapedRun(&shaped, x, y, em, paint),
        }

        return .{ .advance_x = advance_x };
    }

    fn emitSolidShapedRun(
        self: *PassBuilder,
        shaped: *const snail.ShapedText,
        x: f32,
        y: f32,
        em: f32,
        color: [4]f32,
    ) !void {
        try snail.recordUnhintedRun(&self.text_atlas, self.allocator, &self.fonts.faces, shaped, .{});
        var picture = try demo_support.placeRun(self.allocator, shaped, &self.fonts.faces, .{
            .baseline = .{ .x = x, .y = y },
            .em = em,
            .color = color,
        });
        defer picture.deinit();
        try self.text_shapes.appendSlice(self.allocator, picture.shapes);
    }

    fn emitPaintedShapedRun(
        self: *PassBuilder,
        shaped: *const snail.ShapedText,
        x: f32,
        y: f32,
        em: f32,
        paint: snail.Paint,
    ) !void {
        // Per-glyph painted runs (gradients, image fills) need the paint baked
        // into glyph-local coordinates. They live in the path namespace so each
        // glyph carries its own paint.
        for (shaped.glyphs) |g| {
            const face_index_int: usize = @intCast(g.face_index);
            if (face_index_int >= self.fonts.faces.faceCount()) continue;
            const fid = g.font_id;
            const font_ref = &self.fonts.fonts[fid];

            const pen_x = x + em * g.x_offset;
            const pen_y = y + em * g.y_offset;
            const transform = snail.Transform2D{
                .xx = em,
                .xy = 0,
                .tx = pen_x,
                .yx = 0,
                .yy = -em,
                .ty = pen_y,
            };
            const local_paint = snail.mapPaintToLocal(paint, transform) orelse continue;

            const curves = try font_ref.extractCurves(self.allocator, self.allocator, g.glyph_id);
            try self.path_curves_owned.append(self.allocator, curves);

            const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_path_id };
            self.next_path_id += 1;
            try self.path_entries.append(self.allocator, .{
                .key = key,
                .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
                .paint = local_paint,
            });
            try self.path_shapes.append(self.allocator, .{
                .key = key,
                .local_transform = transform,
                .local_color = .{ 1, 1, 1, 1 },
            });
        }
    }

    pub fn freeze(self: *PassBuilder, pool: *snail.PagePool) !PreparedPass {
        var path_atlas = try snail.Atlas.from(self.allocator, pool, self.path_entries.items);
        errdefer path_atlas.deinit();
        // Ownership of the recorded text store moves to PreparedPass.
        var text_atlas = self.text_atlas;
        self.text_atlas = snail.Atlas.empty(self.allocator);
        errdefer text_atlas.deinit();
        var path_picture = try demo_support.Picture.from(self.allocator, self.path_shapes.items);
        errdefer path_picture.deinit();
        var text_picture = try demo_support.Picture.from(self.allocator, self.text_shapes.items);
        errdefer text_picture.deinit();

        // Ownership of the curve / extra-layer storage moves to PreparedPass.
        const path_owned = try self.path_curves_owned.toOwnedSlice(self.allocator);
        const extras = try self.extra_layer_storage.toOwnedSlice(self.allocator);

        return .{
            .allocator = self.allocator,
            .path_atlas = path_atlas,
            .text_atlas = text_atlas,
            .path_picture = path_picture,
            .text_picture = text_picture,
            .path_curves_owned = path_owned,
            .extra_layer_storage = extras,
        };
    }
};

// ── PreparedPass ──

pub const PreparedPass = struct {
    allocator: std.mem.Allocator,
    path_atlas: snail.Atlas,
    text_atlas: snail.Atlas,
    path_picture: demo_support.Picture,
    text_picture: demo_support.Picture,
    path_curves_owned: []snail.GlyphCurves,
    extra_layer_storage: [][]snail.AtlasLayer,

    pub fn deinit(self: *PreparedPass) void {
        self.text_picture.deinit();
        self.path_picture.deinit();
        self.text_atlas.deinit();
        self.path_atlas.deinit();
        for (self.path_curves_owned) |*c| c.deinit();
        if (self.path_curves_owned.len > 0) self.allocator.free(self.path_curves_owned);
        for (self.extra_layer_storage) |s| self.allocator.free(s);
        if (self.extra_layer_storage.len > 0) self.allocator.free(self.extra_layer_storage);
        self.* = undefined;
    }
};

pub fn max3(a: f32, b: f32, c: f32) f32 {
    return @max(a, @max(b, c));
}

pub fn max4(a: f32, b: f32, c: f32, d: f32) f32 {
    return @max(@max(a, b), @max(c, d));
}
