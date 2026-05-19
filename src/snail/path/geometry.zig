const std = @import("std");

const bezier = @import("../math/bezier.zig");
const core = @import("core.zig");
const paint_api = @import("../paint.zig");

const BBox = bezier.BBox;
const CurveSegment = bezier.CurveSegment;
const Path = core.Path;
const StrokeStyle = paint_api.StrokeStyle;

pub const Geometry = struct {
    curves: []CurveSegment,
    bbox: BBox,
    logical_curve_count: usize,

    pub fn deinit(self: *Geometry, allocator: std.mem.Allocator) void {
        allocator.free(self.curves);
        self.* = undefined;
    }
};

pub fn cloneFill(allocator: std.mem.Allocator, path: *const Path) !Geometry {
    return .{
        .bbox = path.bounds() orelse return error.EmptyPath,
        .curves = try path.cloneFilledCurves(allocator),
        .logical_curve_count = path.filledBandCurveCount(),
    };
}

pub fn strokeOutlineStyle(style: StrokeStyle) StrokeStyle {
    var geometry_style = style;
    if (style.placement == .inside) geometry_style.width *= 2.0;
    return geometry_style;
}

pub fn cloneStroke(allocator: std.mem.Allocator, path: *const Path, style: StrokeStyle) !?Geometry {
    const stroke_geom = (try path.cloneStrokedCurves(allocator, strokeOutlineStyle(style))) orelse return null;
    return .{
        .curves = stroke_geom.curves,
        .bbox = stroke_geom.bbox,
        .logical_curve_count = stroke_geom.logical_curve_count,
    };
}
