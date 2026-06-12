//! Game-demo pass builders, ported to the new snail API.
//!
//! Each "pass" packages up two pieces of GPU content:
//!   - `path_atlas` + `path_picture`: every filled / stroked vector path the
//!     pass draws (rounded backings, dividers, etc.). May be empty.
//!   - `text_atlas` + `text_picture`: every shaped run the pass draws. Always
//!     non-empty for the passes the game cares about.
//!
//! HUD passes feed both pictures through `Gl33Renderer.state.draw`. World-
//! space surface passes (rough wall, center panel) additionally take the
//! text picture and emit its raw 64-byte-per-glyph words into a GL texture
//! buffer so the material fragment shader can sample coverage at arbitrary
//! UVs via `snail.coverage.Shader.gl33.sample_functions`.

const std = @import("std");
const snail = @import("snail");
const snail_helpers = @import("snail-helpers");
const assets = @import("assets");
const gl = @import("support").gl;
const common = @import("common.zig");
const materials = @import("materials.zig");

pub const MaterialMaps = materials.MaterialMaps;

const MATERIAL_TEXTURE_SIZE: u32 = 1024;

// ── Fonts ──

/// Long-lived shaper + Font slots + page pool used to build every pass. One
/// `Fonts` value is shared across the entire game scene.
pub const Fonts = struct {
    allocator: std.mem.Allocator,
    faces: snail.Faces,
    /// Heap-allocated so `Faces.face(i).font` (raw `*const Font`)
    /// survives `Fonts` getting moved during `init`'s return-by-value.
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

        // 6 passes × 2 atlases (path + text) = 12 atlases at minimum, each
        // claiming at least one page. Headroom for resize / hint changes.
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

/// Accumulates atlas entries + shapes for a single pass. Sealed via
/// `freeze` into a `PreparedPass`.
const PassBuilder = struct {
    allocator: std.mem.Allocator,
    fonts: *Fonts,

    // Path namespace: vector paths + per-glyph painted text glyphs.
    path_curves_owned: std.ArrayList(snail.GlyphCurves),
    path_entries: std.ArrayList(snail.AtlasEntry),
    path_shapes: std.ArrayList(snail.Shape),
    extra_layer_storage: std.ArrayList([]snail.AtlasLayer),
    next_path_id: u32,

    // Text namespace: solid-colored shaped runs.
    text_curves_owned: std.ArrayList(snail.GlyphCurves),
    text_entries: std.ArrayList(snail.AtlasEntry),
    text_shapes: std.ArrayList(snail.Shape),

    fn init(allocator: std.mem.Allocator, fonts: *Fonts) PassBuilder {
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .path_curves_owned = .empty,
            .path_entries = .empty,
            .path_shapes = .empty,
            .extra_layer_storage = .empty,
            .next_path_id = 0,
            .text_curves_owned = .empty,
            .text_entries = .empty,
            .text_shapes = .empty,
        };
    }

    fn deinit(self: *PassBuilder) void {
        for (self.path_curves_owned.items) |*c| c.deinit();
        self.path_curves_owned.deinit(self.allocator);
        self.path_entries.deinit(self.allocator);
        self.path_shapes.deinit(self.allocator);
        for (self.extra_layer_storage.items) |s| self.allocator.free(s);
        self.extra_layer_storage.deinit(self.allocator);

        for (self.text_curves_owned.items) |*c| c.deinit();
        self.text_curves_owned.deinit(self.allocator);
        self.text_entries.deinit(self.allocator);
        self.text_shapes.deinit(self.allocator);
    }

    fn addFilledPath(self: *PassBuilder, path: *const snail.paths.Path, paint: snail.Paint) !void {
        const curves = try snail.paths.pathToCurves(self.allocator, self.allocator, path);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.path_curves_owned.append(self.allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = paint,
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = .identity,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    fn addStrokedPath(self: *PassBuilder, path: *const snail.paths.Path, stroke: snail.StrokeStyle) !void {
        const curves = try snail.paths.strokeToCurves(self.allocator, self.allocator, path, stroke);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.path_curves_owned.append(self.allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
            .paint = stroke.paint,
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = .identity,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    fn addPathFillAndInsideStroke(
        self: *PassBuilder,
        path: *const snail.paths.Path,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
    ) !void {
        std.debug.assert(stroke.placement == .inside);

        const fill_curves = try snail.paths.pathToCurves(self.allocator, self.allocator, path);
        if (fill_curves.isEmpty()) {
            var owned = fill_curves;
            owned.deinit();
            try self.addStrokedPath(path, stroke);
            return;
        }
        const stroke_curves = try snail.paths.strokeToCurves(self.allocator, self.allocator, path, stroke);
        if (stroke_curves.isEmpty()) {
            try self.path_curves_owned.append(self.allocator, fill_curves);
            const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
            self.next_path_id += 1;
            try self.path_entries.append(self.allocator, .{
                .key = key,
                .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
                .paint = fill,
            });
            try self.path_shapes.append(self.allocator, .{
                .key = key,
                .local_transform = .identity,
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
            .paint = stroke.paint,
        };
        try self.extra_layer_storage.append(self.allocator, extras);

        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
        self.next_path_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 2],
            .paint = fill,
            .extra_layers = extras,
            .composite_mode = .fill_stroke_inside,
        });
        try self.path_shapes.append(self.allocator, .{
            .key = key,
            .local_transform = .identity,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    fn addRoundedRectWithInsideStroke(
        self: *PassBuilder,
        rect: snail.Rect,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
        radius: f32,
    ) !void {
        var p = snail.paths.Path.init(self.allocator);
        defer p.deinit();
        try p.addRoundedRect(rect, radius);
        try self.addPathFillAndInsideStroke(&p, fill, stroke);
    }

    fn addFilledRect(self: *PassBuilder, rect: snail.Rect, paint: snail.Paint) !void {
        var p = snail.paths.Path.init(self.allocator);
        defer p.deinit();
        try p.addRect(rect);
        try self.addFilledPath(&p, paint);
    }

    const TextResult = struct {
        advance_x: f32,
    };

    fn appendText(
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

    fn appendPaintedText(
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
        try self.ensureUnhintedGlyphCurves(shaped);
        var picture = try snail_helpers.shapedRunPicture(self.allocator, shaped, &self.fonts.faces, .{
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
        // Per-glyph painted runs (gradients, image fills) need the paint
        // baked into glyph-local coordinates. They live in the path
        // namespace so each glyph carries its own paint.
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

            const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
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

    fn ensureUnhintedGlyphCurves(self: *PassBuilder, shaped: *const snail.ShapedText) !void {
        for (shaped.glyphs) |g| {
            const face_index_int: usize = @intCast(g.face_index);
            if (face_index_int >= self.fonts.faces.faceCount()) continue;
            const fid = g.font_id;
            const font_ref = &self.fonts.fonts[fid];
            const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
            if (containsKey(self.text_entries.items, key)) continue;
            const curves = try font_ref.extractCurves(self.allocator, self.allocator, g.glyph_id);
            try self.text_curves_owned.append(self.allocator, curves);
            try self.text_entries.append(self.allocator, .{
                .key = key,
                .curves = self.text_curves_owned.items[self.text_curves_owned.items.len - 1],
            });
        }
    }

    fn freeze(self: *PassBuilder, pool: *snail.PagePool) !PreparedPass {
        var path_atlas = try snail.Atlas.from(self.allocator, pool, self.path_entries.items);
        errdefer path_atlas.deinit();
        var text_atlas = try snail.Atlas.from(self.allocator, pool, self.text_entries.items);
        errdefer text_atlas.deinit();
        var path_picture = try snail_helpers.Picture.from(self.allocator, self.path_shapes.items);
        errdefer path_picture.deinit();
        var text_picture = try snail_helpers.Picture.from(self.allocator, self.text_shapes.items);
        errdefer text_picture.deinit();

        // Ownership of the curve / extra-layer storage moves to PreparedPass.
        const path_owned = try self.path_curves_owned.toOwnedSlice(self.allocator);
        const text_owned = try self.text_curves_owned.toOwnedSlice(self.allocator);
        const extras = try self.extra_layer_storage.toOwnedSlice(self.allocator);

        return .{
            .allocator = self.allocator,
            .path_atlas = path_atlas,
            .text_atlas = text_atlas,
            .path_picture = path_picture,
            .text_picture = text_picture,
            .path_curves_owned = path_owned,
            .text_curves_owned = text_owned,
            .extra_layer_storage = extras,
        };
    }
};

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

// ── PreparedPass ──

pub const PreparedPass = struct {
    allocator: std.mem.Allocator,
    path_atlas: snail.Atlas,
    text_atlas: snail.Atlas,
    path_picture: snail_helpers.Picture,
    text_picture: snail_helpers.Picture,
    path_curves_owned: []snail.GlyphCurves,
    text_curves_owned: []snail.GlyphCurves,
    extra_layer_storage: [][]snail.AtlasLayer,

    pub fn deinit(self: *PreparedPass) void {
        self.text_picture.deinit();
        self.path_picture.deinit();
        self.text_atlas.deinit();
        self.path_atlas.deinit();
        for (self.path_curves_owned) |*c| c.deinit();
        if (self.path_curves_owned.len > 0) self.allocator.free(self.path_curves_owned);
        for (self.text_curves_owned) |*c| c.deinit();
        if (self.text_curves_owned.len > 0) self.allocator.free(self.text_curves_owned);
        for (self.extra_layer_storage) |s| self.allocator.free(s);
        if (self.extra_layer_storage.len > 0) self.allocator.free(self.extra_layer_storage);
        self.* = undefined;
    }
};

// ── World / HUD pass collections ──

pub const HudPasses = struct {
    plain: PreparedPass,
    translucent: PreparedPass,
    solid: PreparedPass,

    pub fn init(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32, window_h: u32) !HudPasses {
        var plain = try buildHudPlainPass(allocator, fonts, window_w);
        errdefer plain.deinit();
        var translucent = try buildHudTranslucentPass(allocator, fonts, window_w);
        errdefer translucent.deinit();
        var solid = try buildHudSolidPass(allocator, fonts, window_w, window_h);
        errdefer solid.deinit();
        return .{ .plain = plain, .translucent = translucent, .solid = solid };
    }

    pub fn deinit(self: *HudPasses) void {
        self.plain.deinit();
        self.translucent.deinit();
        self.solid.deinit();
    }
};

pub const PlanePass = struct {
    prepared: PreparedPass,
    scene_width: f32,
    scene_height: f32,
    opaque_backdrop: bool,

    pub fn deinit(self: *PlanePass) void {
        self.prepared.deinit();
        self.* = undefined;
    }
};

pub const WorldPasses = struct {
    rough_wall: PlanePass,
    center_panel: PlanePass,
    glass: PlanePass,
    material_maps: MaterialMaps,

    pub fn deinit(self: *WorldPasses) void {
        self.rough_wall.deinit();
        self.center_panel.deinit();
        self.glass.deinit();
        self.material_maps.deinit();
        self.* = undefined;
    }
};

pub fn buildWorldPasses(allocator: std.mem.Allocator, fonts: *Fonts) !WorldPasses {
    var material_maps = try MaterialMaps.init(allocator, MATERIAL_TEXTURE_SIZE);
    errdefer material_maps.deinit();

    var rough_wall = try buildRoughWallTextPass(allocator, fonts);
    errdefer rough_wall.deinit();

    var center_panel = try buildCenterPanelPass(allocator, fonts);
    errdefer center_panel.deinit();

    var glass = try buildGlassPass(allocator, fonts);
    errdefer glass.deinit();

    return .{
        .rough_wall = rough_wall,
        .center_panel = center_panel,
        .glass = glass,
        .material_maps = material_maps,
    };
}

fn max3(a: f32, b: f32, c: f32) f32 {
    return @max(a, @max(b, c));
}

fn max4(a: f32, b: f32, c: f32, d: f32) f32 {
    return @max(@max(a, b), @max(c, d));
}

// ── HUD passes ──

fn buildHudPlainPass(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32) !PreparedPass {
    _ = window_w;
    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    const x = 34.0;
    _ = try builder.appendText(.{ .weight = .bold }, "HUD text / no backing", x, 52.0, 22.0, .{ 1, 1, 1, 1 });
    _ = try builder.appendText(.{}, "WASD move  QE rise  Arrows look  R reset", x, 84.0, 17.0, .{ 0.86, 0.90, 0.96, 1.0 });
    _ = try builder.appendText(.{}, "Final pixels, but no opaque backdrop under the glyphs.", x, 108.0, 15.0, .{ 0.68, 0.75, 0.84, 1.0 });

    return builder.freeze(fonts.pool);
}

fn buildHudTranslucentPass(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32) !PreparedPass {
    const title = "Quest Log";
    const body = "Restore power and reach the observation deck.";
    const note = "Translucent vector backing keeps LCD text disabled.";
    const pad_x = 22.0;
    const pad_y = 18.0;
    const title_size = 24.0;
    const body_size = 17.0;
    const note_size = 14.0;
    const inner_w = max3(
        try fonts.measureText(.{ .weight = .bold }, title, title_size),
        try fonts.measureText(.{}, body, body_size),
        try fonts.measureText(.{}, note, note_size),
    );
    const rect_w = inner_w + pad_x * 2.0;
    const rect_h = 112.0;
    const rect = snail.Rect{
        .x = @as(f32, @floatFromInt(window_w)) * 0.5 - rect_w * 0.5,
        .y = 26.0,
        .w = rect_w,
        .h = rect_h,
    };

    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    try builder.addRoundedRectWithInsideStroke(
        rect,
        .{ .solid = .{ 0.18, 0.32, 0.44, 0.34 } },
        .{
            .paint = .{ .solid = .{ 0.56, 0.82, 1.0, 0.52 } },
            .width = 2.0,
            .placement = .inside,
        },
        18.0,
    );
    try builder.addFilledRect(
        .{ .x = rect.x + 22.0, .y = rect.y + 18.0, .w = 90.0, .h = 6.0 },
        .{ .solid = .{ 0.56, 0.82, 1.0, 0.78 } },
    );

    const tx = rect.x + pad_x;
    _ = try builder.appendText(.{ .weight = .bold }, title, tx, rect.y + pad_y + title_size, title_size, .{ 0.97, 0.99, 1.0, 1.0 });
    _ = try builder.appendText(.{}, body, tx, rect.y + pad_y + title_size + 30.0, body_size, .{ 0.88, 0.94, 0.98, 1.0 });
    _ = try builder.appendText(.{}, note, tx, rect.y + pad_y + title_size + 54.0, note_size, .{ 0.73, 0.82, 0.90, 1.0 });

    return builder.freeze(fonts.pool);
}

fn buildHudSolidPass(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32, _: u32) !PreparedPass {
    const title = "Status Panel";
    const line_one = "HEALTH 83   AMMO 42";
    const line_two = "LINK SYNCED / TEMP NOMINAL";
    const note = "Opaque vector backing: LCD-safe HUD text.";
    const pad_x = 20.0;
    const title_size = 24.0;
    const body_size = 18.0;
    const note_size = 13.0;
    const inner_w = max4(
        try fonts.measureText(.{ .weight = .bold }, title, title_size),
        try fonts.measureText(.{}, line_one, body_size),
        try fonts.measureText(.{}, line_two, body_size),
        try fonts.measureText(.{}, note, note_size),
    );
    const rect_w = inner_w + pad_x * 2.0;
    const rect = snail.Rect{
        .x = @as(f32, @floatFromInt(window_w)) - rect_w - 30.0,
        .y = 24.0,
        .w = rect_w,
        .h = 132.0,
    };

    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    try builder.addRoundedRectWithInsideStroke(
        rect,
        .{ .solid = .{ 0.08, 0.11, 0.14, 1.0 } },
        .{
            .paint = .{ .solid = .{ 0.24, 0.36, 0.44, 1.0 } },
            .width = 2.0,
            .placement = .inside,
        },
        16.0,
    );
    try builder.addFilledRect(
        .{ .x = rect.x, .y = rect.y + rect.h - 26.0, .w = rect.w, .h = 26.0 },
        .{ .solid = .{ 0.14, 0.20, 0.25, 1.0 } },
    );

    const tx = rect.x + pad_x;
    _ = try builder.appendText(.{ .weight = .bold }, title, tx, rect.y + 42.0, title_size, .{ 1.0, 1.0, 1.0, 1.0 });
    var cx = tx;
    const status_y = rect.y + 74.0;
    cx += (try builder.appendText(.{}, "HEALTH ", cx, status_y, body_size, .{ 0.78, 0.86, 0.92, 1.0 })).advance_x;
    cx += (try builder.appendText(.{ .weight = .bold }, "83", cx, status_y, body_size + 3.0, .{ 0.28, 0.92, 0.50, 1.0 })).advance_x;
    cx += (try builder.appendText(.{}, "   AMMO ", cx, status_y, body_size, .{ 0.78, 0.86, 0.92, 1.0 })).advance_x;
    _ = try builder.appendText(.{ .weight = .bold }, "42", cx, status_y, body_size + 3.0, .{ 0.98, 0.76, 0.28, 1.0 });

    cx = tx;
    const link_y = rect.y + 98.0;
    cx += (try builder.appendText(.{}, "LINK ", cx, link_y, body_size, .{ 0.78, 0.86, 0.92, 1.0 })).advance_x;
    cx += (try builder.appendPaintedText(.{ .weight = .bold }, "SYNCED", cx, link_y, body_size, .{ .linear_gradient = .{
        .start = .{ .x = cx, .y = link_y - body_size },
        .end = .{ .x = cx + 74.0, .y = link_y },
        .start_color = .{ 0.22, 0.70, 1.0, 1.0 },
        .end_color = .{ 0.42, 0.94, 0.60, 1.0 },
    } })).advance_x;
    _ = try builder.appendText(.{}, " / TEMP NOMINAL", cx, link_y, body_size, .{ 0.78, 0.86, 0.92, 1.0 });
    _ = try builder.appendText(.{}, note, tx, rect.y + 124.0, note_size, .{ 0.78, 0.86, 0.92, 1.0 });

    return builder.freeze(fonts.pool);
}

// ── World passes ──

fn buildRoughWallTextPass(allocator: std.mem.Allocator, fonts: *Fonts) !PlanePass {
    const scene_w = 760.0;
    const scene_h = 300.0;

    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    _ = try builder.appendText(.{ .weight = .bold }, "AUTHORIZED ONLY", 46.0, 118.0, 56.0, .{ 0.06, 0.055, 0.05, 1.0 });
    _ = try builder.appendText(.{}, "Text tinted directly onto the normal-mapped wall material.", 46.0, 168.0, 22.0, .{ 0.08, 0.07, 0.06, 0.96 });
    _ = try builder.appendText(.{}, "The wall keeps its surface detail; the glyphs are not billboarded.", 46.0, 198.0, 18.0, .{ 0.08, 0.07, 0.06, 0.92 });

    return .{
        .prepared = try builder.freeze(fonts.pool),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = true,
    };
}

fn buildCenterPanelPass(allocator: std.mem.Allocator, fonts: *Fonts) !PlanePass {
    const scene_w = 960.0;
    const scene_h = 360.0;
    const title = "SECTOR A";
    const kicker = "OBSERVATION";
    const body = "Analytic vector text sampled in the material shader.";
    const note = "Lit by the room; never flattened into a texture.";
    const pad_x = 42.0;
    const title_size = 58.0;
    const kicker_size = 22.0;
    const body_size = 23.0;
    const note_size = 17.0;
    const inner_w = max3(
        try fonts.measureText(.{ .weight = .bold }, title, title_size),
        try fonts.measureText(.{}, body, body_size),
        try fonts.measureText(.{}, note, note_size),
    );
    const panel = snail.Rect{
        .x = @max(34.0, (scene_w - (inner_w + pad_x * 2.0)) * 0.5),
        .y = 36.0,
        .w = @min(scene_w - 68.0, inner_w + pad_x * 2.0),
        .h = 278.0,
    };

    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    const tx = panel.x + pad_x;
    _ = try builder.appendText(.{ .weight = .bold }, kicker, panel.x + 42.0, panel.y + 76.0, kicker_size, .{ 0.10, 0.12, 0.14, 1.0 });
    _ = try builder.appendText(.{ .weight = .bold }, title, tx, panel.y + 154.0, title_size, .{ 0.93, 0.96, 0.96, 1.0 });
    _ = try builder.appendText(.{}, body, tx, panel.y + 204.0, body_size, .{ 0.82, 0.87, 0.88, 1.0 });
    _ = try builder.appendText(.{}, note, tx, panel.y + 236.0, note_size, .{ 0.66, 0.72, 0.75, 1.0 });

    return .{
        .prepared = try builder.freeze(fonts.pool),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = true,
    };
}

fn buildGlassPass(allocator: std.mem.Allocator, fonts: *Fonts) !PlanePass {
    const scene_w = 760.0;
    const scene_h = 260.0;
    const title = "OBSERVATION";
    const body = "Translucent glass overlay in front of the wall.";
    const note = "Still direct-rendered, but LCD remains off on translucent backing.";
    const pad_x = 24.0;
    const inner_w = max3(
        try fonts.measureText(.{ .weight = .bold }, title, 42.0),
        try fonts.measureText(.{}, body, 21.0),
        try fonts.measureText(.{}, note, 16.0),
    );
    const rect = snail.Rect{
        .x = (scene_w - (inner_w + pad_x * 2.0)) * 0.5,
        .y = 30.0,
        .w = inner_w + pad_x * 2.0,
        .h = 196.0,
    };

    var builder = PassBuilder.init(allocator, fonts);
    defer builder.deinit();

    try builder.addRoundedRectWithInsideStroke(
        rect,
        .{ .solid = .{ 0.38, 0.70, 1.0, 0.32 } },
        .{
            .paint = .{ .solid = .{ 0.72, 0.90, 1.0, 0.62 } },
            .width = 2.0,
            .placement = .inside,
        },
        22.0,
    );
    try builder.addFilledRect(
        .{ .x = rect.x + 24.0, .y = rect.y + 24.0, .w = rect.w - 48.0, .h = 1.5 },
        .{ .solid = .{ 0.85, 0.95, 1.0, 0.55 } },
    );

    const tx = rect.x + pad_x;
    _ = try builder.appendText(.{ .weight = .bold }, title, tx, rect.y + 72.0, 42.0, .{ 0.92, 0.98, 1.0, 0.78 });
    _ = try builder.appendText(.{}, body, tx, rect.y + 114.0, 21.0, .{ 0.84, 0.93, 0.98, 0.74 });
    _ = try builder.appendText(.{}, note, tx, rect.y + 144.0, 16.0, .{ 0.72, 0.84, 0.92, 0.70 });

    return .{
        .prepared = try builder.freeze(fonts.pool),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = false,
    };
}

// ── Draw target helpers ──

pub const DrawTarget = struct {
    surface: snail.TargetSurface,
    raster: snail.RasterOptions = .{},
};

fn effectiveSubpixelOrder(subpixel_order: snail.SubpixelOrder, opaque_backdrop: bool, will_resample: bool) snail.SubpixelOrder {
    if (will_resample) return .none;
    if (!opaque_backdrop) return .none;
    return subpixel_order;
}

pub fn hudTarget(
    window_size: [2]u32,
    fb_size: [2]u32,
    subpixel_order: snail.SubpixelOrder,
    opaque_backdrop: bool,
    encoding: snail.TargetEncoding,
    will_resample: bool,
) DrawTarget {
    _ = window_size;
    return .{
        .surface = .{
            .pixel_width = @floatFromInt(fb_size[0]),
            .pixel_height = @floatFromInt(fb_size[1]),
            .encoding = encoding,
        },
        .raster = .{ .subpixel_order = effectiveSubpixelOrder(subpixel_order, opaque_backdrop, will_resample) },
    };
}

pub fn worldTarget(fb_size: [2]u32, subpixel_order: snail.SubpixelOrder, opaque_backdrop: bool) DrawTarget {
    return .{
        .surface = .{
            .pixel_width = @floatFromInt(fb_size[0]),
            .pixel_height = @floatFromInt(fb_size[1]),
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = effectiveSubpixelOrder(subpixel_order, opaque_backdrop, false) },
    };
}

