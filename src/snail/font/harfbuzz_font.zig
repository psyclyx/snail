//! HarfBuzz-backed outlines and variation-aware metrics.
//!
//! Snail keeps its native parser as the fast path for static TrueType
//! outlines. This module supplies the formats whose interpreters are already
//! maintained by HarfBuzz: CFF/CFF2 and variable instances.

const std = @import("std");
const bezier = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");
const types = @import("types.zig");

const hb = @cImport({
    @cInclude("hb.h");
    @cInclude("hb-ot.h");
});

const CurveSegment = bezier.CurveSegment;
const Vec2 = vec.Vec2;

pub const GlyphMetrics = struct {
    advance_width: i32,
    lsb: i32,
    bbox: bezier.BBox,
};

pub const LineMetrics = struct {
    ascent: i32,
    descent: i32,
    line_gap: i32,
};

pub const Instance = struct {
    face: *hb.hb_face_t,
    font: *hb.hb_font_t,
    draw_funcs: *hb.hb_draw_funcs_t,

    pub fn init(data: []const u8, face_index: u32, units_per_em: u16, variations: []const types.Variation) !Instance {
        const data_len = std.math.cast(c_uint, data.len) orelse return error.FontTooLarge;
        const blob = hb.hb_blob_create(
            data.ptr,
            data_len,
            hb.HB_MEMORY_MODE_READONLY,
            null,
            null,
        ) orelse return error.HarfBuzzInitFailed;
        defer hb.hb_blob_destroy(blob);

        const face = hb.hb_face_create(blob, face_index) orelse return error.HarfBuzzInitFailed;
        errdefer hb.hb_face_destroy(face);
        if (hb.hb_face_get_glyph_count(face) == 0) return error.InvalidFont;

        const font = hb.hb_font_create(face) orelse return error.HarfBuzzInitFailed;
        errdefer hb.hb_font_destroy(font);
        hb.hb_ot_font_set_funcs(font);
        const upem: c_int = @intCast(units_per_em);
        hb.hb_font_set_scale(font, upem, upem);
        for (variations) |variation| {
            hb.hb_font_set_variation(font, makeTag(variation.tag), variation.value);
        }

        const draw_funcs = hb.hb_draw_funcs_create() orelse return error.HarfBuzzInitFailed;
        errdefer hb.hb_draw_funcs_destroy(draw_funcs);
        hb.hb_draw_funcs_set_move_to_func(draw_funcs, drawMoveTo, null, null);
        hb.hb_draw_funcs_set_line_to_func(draw_funcs, drawLineTo, null, null);
        hb.hb_draw_funcs_set_quadratic_to_func(draw_funcs, drawQuadraticTo, null, null);
        hb.hb_draw_funcs_set_cubic_to_func(draw_funcs, drawCubicTo, null, null);
        hb.hb_draw_funcs_set_close_path_func(draw_funcs, drawClosePath, null, null);
        hb.hb_draw_funcs_make_immutable(draw_funcs);
        return .{ .face = face, .font = font, .draw_funcs = draw_funcs };
    }

    pub fn deinit(self: *Instance) void {
        hb.hb_draw_funcs_destroy(self.draw_funcs);
        hb.hb_font_destroy(self.font);
        hb.hb_face_destroy(self.face);
        self.* = undefined;
    }

    pub fn glyphOutline(
        self: *Instance,
        allocator: std.mem.Allocator,
        glyph_id: u16,
        coordinate_scale: f32,
    ) !Outline {
        return drawOutline(allocator, self.font, self.draw_funcs, glyph_id, coordinate_scale);
    }

    pub fn glyphMetrics(self: *Instance, units_per_em: u16, glyph_id: u16) GlyphMetrics {
        return readGlyphMetrics(self.font, units_per_em, glyph_id);
    }
};

pub const Outline = struct {
    allocator: std.mem.Allocator,
    segments: []CurveSegment,
    contours: []types.CurveRange,

    pub fn deinit(self: *Outline) void {
        self.allocator.free(self.segments);
        self.allocator.free(self.contours);
        self.* = undefined;
    }
};

pub fn glyphMetrics(
    data: []const u8,
    face_index: u32,
    units_per_em: u16,
    variations: []const types.Variation,
    glyph_id: u16,
) !GlyphMetrics {
    var instance = try Instance.init(data, face_index, units_per_em, variations);
    defer instance.deinit();

    return instance.glyphMetrics(units_per_em, glyph_id);
}

fn readGlyphMetrics(font: *hb.hb_font_t, units_per_em: u16, glyph_id: u16) GlyphMetrics {
    const advance = hb.hb_font_get_glyph_h_advance(font, glyph_id);
    var extents: hb.hb_glyph_extents_t = std.mem.zeroes(hb.hb_glyph_extents_t);
    _ = hb.hb_font_get_glyph_extents(font, glyph_id, &extents);

    const scale = 1.0 / @as(f32, @floatFromInt(units_per_em));
    const x_min: f32 = @floatFromInt(extents.x_bearing);
    const x_max = x_min + @as(f32, @floatFromInt(extents.width));
    const y_max: f32 = @floatFromInt(extents.y_bearing);
    const y_min = y_max + @as(f32, @floatFromInt(extents.height));
    return .{
        .advance_width = advance,
        .lsb = extents.x_bearing,
        .bbox = .{
            .min = Vec2.new(@min(x_min, x_max) * scale, @min(y_min, y_max) * scale),
            .max = Vec2.new(@max(x_min, x_max) * scale, @max(y_min, y_max) * scale),
        },
    };
}

pub fn lineMetrics(
    data: []const u8,
    face_index: u32,
    units_per_em: u16,
    variations: []const types.Variation,
) !LineMetrics {
    var instance = try Instance.init(data, face_index, units_per_em, variations);
    defer instance.deinit();
    return .{
        .ascent = metricPosition(instance.font, hb.HB_OT_METRICS_TAG_HORIZONTAL_ASCENDER),
        .descent = metricPosition(instance.font, hb.HB_OT_METRICS_TAG_HORIZONTAL_DESCENDER),
        .line_gap = metricPosition(instance.font, hb.HB_OT_METRICS_TAG_HORIZONTAL_LINE_GAP),
    };
}

pub fn metric(
    data: []const u8,
    face_index: u32,
    units_per_em: u16,
    variations: []const types.Variation,
    tag: hb.hb_ot_metrics_tag_t,
) !i32 {
    var instance = try Instance.init(data, face_index, units_per_em, variations);
    defer instance.deinit();
    return metricPosition(instance.font, tag);
}

fn metricPosition(font: *hb.hb_font_t, tag: hb.hb_ot_metrics_tag_t) i32 {
    var position: hb.hb_position_t = 0;
    hb.hb_ot_metrics_get_position_with_fallback(font, tag, &position);
    return position;
}

pub fn metricByTag(
    data: []const u8,
    face_index: u32,
    units_per_em: u16,
    variations: []const types.Variation,
    tag: types.MetricTag,
) !i32 {
    const hb_tag: hb.hb_ot_metrics_tag_t = switch (tag) {
        .subscript_x_size => hb.HB_OT_METRICS_TAG_SUBSCRIPT_EM_X_SIZE,
        .subscript_y_size => hb.HB_OT_METRICS_TAG_SUBSCRIPT_EM_Y_SIZE,
        .subscript_x_offset => hb.HB_OT_METRICS_TAG_SUBSCRIPT_EM_X_OFFSET,
        .subscript_y_offset => hb.HB_OT_METRICS_TAG_SUBSCRIPT_EM_Y_OFFSET,
        .superscript_x_size => hb.HB_OT_METRICS_TAG_SUPERSCRIPT_EM_X_SIZE,
        .superscript_y_size => hb.HB_OT_METRICS_TAG_SUPERSCRIPT_EM_Y_SIZE,
        .superscript_x_offset => hb.HB_OT_METRICS_TAG_SUPERSCRIPT_EM_X_OFFSET,
        .superscript_y_offset => hb.HB_OT_METRICS_TAG_SUPERSCRIPT_EM_Y_OFFSET,
        .strikeout_size => hb.HB_OT_METRICS_TAG_STRIKEOUT_SIZE,
        .strikeout_offset => hb.HB_OT_METRICS_TAG_STRIKEOUT_OFFSET,
        .underline_size => hb.HB_OT_METRICS_TAG_UNDERLINE_SIZE,
        .underline_offset => hb.HB_OT_METRICS_TAG_UNDERLINE_OFFSET,
    };
    return metric(data, face_index, units_per_em, variations, hb_tag);
}

pub fn variationAxes(
    allocator: std.mem.Allocator,
    data: []const u8,
    face_index: u32,
) ![]types.VariationAxis {
    const data_len = std.math.cast(c_uint, data.len) orelse return error.FontTooLarge;
    const blob = hb.hb_blob_create(data.ptr, data_len, hb.HB_MEMORY_MODE_READONLY, null, null) orelse
        return error.HarfBuzzInitFailed;
    defer hb.hb_blob_destroy(blob);
    const face = hb.hb_face_create(blob, face_index) orelse return error.HarfBuzzInitFailed;
    defer hb.hb_face_destroy(face);
    if (hb.hb_face_get_glyph_count(face) == 0) return error.InvalidFont;

    const count: usize = hb.hb_ot_var_get_axis_count(face);
    const result = try allocator.alloc(types.VariationAxis, count);
    errdefer allocator.free(result);
    if (count == 0) return result;

    const infos = try allocator.alloc(hb.hb_ot_var_axis_info_t, count);
    defer allocator.free(infos);
    var info_count: c_uint = @intCast(count);
    const actual: usize = hb.hb_ot_var_get_axis_infos(face, 0, &info_count, infos.ptr);
    if (actual != count) return error.InvalidFont;
    for (infos, result) |info, *axis| {
        axis.* = .{
            .tag = tagBytes(info.tag),
            .min_value = info.min_value,
            .default_value = info.default_value,
            .max_value = info.max_value,
            .hidden = (info.flags & hb.HB_OT_VAR_AXIS_FLAG_HIDDEN) != 0,
        };
    }
    return result;
}

pub fn glyphOutline(
    allocator: std.mem.Allocator,
    data: []const u8,
    face_index: u32,
    units_per_em: u16,
    variations: []const types.Variation,
    glyph_id: u16,
    coordinate_scale: f32,
) !Outline {
    var instance = try Instance.init(data, face_index, units_per_em, variations);
    defer instance.deinit();
    return instance.glyphOutline(allocator, glyph_id, coordinate_scale);
}

fn drawOutline(
    allocator: std.mem.Allocator,
    font: *hb.hb_font_t,
    funcs: *hb.hb_draw_funcs_t,
    glyph_id: u16,
    coordinate_scale: f32,
) !Outline {
    var context = DrawContext{
        .allocator = allocator,
        .scale = coordinate_scale,
    };
    errdefer {
        context.segments.deinit(allocator);
        context.contours.deinit(allocator);
    }
    if (hb.hb_font_draw_glyph_or_fail(font, glyph_id, funcs, &context) == 0)
        return error.UnsupportedOutlineFormat;
    if (context.err) |err| return err;
    context.closeContour();
    if (context.err) |err| return err;
    const segments = try context.segments.toOwnedSlice(allocator);
    errdefer allocator.free(segments);
    const contours = try context.contours.toOwnedSlice(allocator);
    return .{
        .allocator = allocator,
        .segments = segments,
        .contours = contours,
    };
}

const DrawContext = struct {
    allocator: std.mem.Allocator,
    segments: std.ArrayList(CurveSegment) = .empty,
    contours: std.ArrayList(types.CurveRange) = .empty,
    contour_start: usize = 0,
    scale: f32,
    start: Vec2 = .zero,
    current: Vec2 = .zero,
    path_open: bool = false,
    err: ?std.mem.Allocator.Error = null,

    fn point(self: *const DrawContext, x: f32, y: f32) Vec2 {
        return Vec2.new(x * self.scale, y * self.scale);
    }

    fn append(self: *DrawContext, segment: CurveSegment) void {
        if (self.err != null) return;
        self.segments.append(self.allocator, segment) catch |err| {
            self.err = err;
        };
    }

    fn closeContour(self: *DrawContext) void {
        if (!self.path_open) return;
        if (self.current.x != self.start.x or self.current.y != self.start.y) {
            self.append(CurveSegment.fromLine(self.current, self.start));
        }
        if (self.err == null and self.segments.items.len > self.contour_start) {
            self.contours.append(self.allocator, .{
                .start = @intCast(self.contour_start),
                .end = @intCast(self.segments.items.len),
            }) catch |err| {
                self.err = err;
            };
        }
        self.contour_start = self.segments.items.len;
        self.current = self.start;
        self.path_open = false;
    }
};

fn contextFrom(draw_data: ?*anyopaque) *DrawContext {
    return @ptrCast(@alignCast(draw_data orelse unreachable));
}

fn drawMoveTo(
    _: ?*hb.hb_draw_funcs_t,
    draw_data: ?*anyopaque,
    _: ?*hb.hb_draw_state_t,
    to_x: f32,
    to_y: f32,
    _: ?*anyopaque,
) callconv(.c) void {
    const context = contextFrom(draw_data);
    context.closeContour();
    const to = context.point(to_x, to_y);
    context.start = to;
    context.current = to;
    context.contour_start = context.segments.items.len;
    context.path_open = true;
}

fn drawLineTo(
    _: ?*hb.hb_draw_funcs_t,
    draw_data: ?*anyopaque,
    _: ?*hb.hb_draw_state_t,
    to_x: f32,
    to_y: f32,
    _: ?*anyopaque,
) callconv(.c) void {
    const context = contextFrom(draw_data);
    const to = context.point(to_x, to_y);
    context.append(CurveSegment.fromLine(context.current, to));
    context.current = to;
}

fn drawQuadraticTo(
    _: ?*hb.hb_draw_funcs_t,
    draw_data: ?*anyopaque,
    _: ?*hb.hb_draw_state_t,
    control_x: f32,
    control_y: f32,
    to_x: f32,
    to_y: f32,
    _: ?*anyopaque,
) callconv(.c) void {
    const context = contextFrom(draw_data);
    const control = context.point(control_x, control_y);
    const to = context.point(to_x, to_y);
    context.append(CurveSegment.fromQuad(.{ .p0 = context.current, .p1 = control, .p2 = to }));
    context.current = to;
}

fn drawCubicTo(
    _: ?*hb.hb_draw_funcs_t,
    draw_data: ?*anyopaque,
    _: ?*hb.hb_draw_state_t,
    control1_x: f32,
    control1_y: f32,
    control2_x: f32,
    control2_y: f32,
    to_x: f32,
    to_y: f32,
    _: ?*anyopaque,
) callconv(.c) void {
    const context = contextFrom(draw_data);
    const c1 = context.point(control1_x, control1_y);
    const c2 = context.point(control2_x, control2_y);
    const to = context.point(to_x, to_y);
    context.append(CurveSegment.fromCubic(.{ .p0 = context.current, .p1 = c1, .p2 = c2, .p3 = to }));
    context.current = to;
}

fn drawClosePath(
    _: ?*hb.hb_draw_funcs_t,
    draw_data: ?*anyopaque,
    _: ?*hb.hb_draw_state_t,
    _: ?*anyopaque,
) callconv(.c) void {
    contextFrom(draw_data).closeContour();
}

fn makeTag(tag: [4]u8) hb.hb_tag_t {
    return (@as(u32, tag[0]) << 24) | (@as(u32, tag[1]) << 16) |
        (@as(u32, tag[2]) << 8) | @as(u32, tag[3]);
}

fn tagBytes(tag: hb.hb_tag_t) [4]u8 {
    return .{
        @truncate(tag >> 24),
        @truncate(tag >> 16),
        @truncate(tag >> 8),
        @truncate(tag),
    };
}
