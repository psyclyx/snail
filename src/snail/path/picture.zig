const std = @import("std");

const band_tex = @import("../renderer/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const core = @import("core.zig");
const curve_tex = @import("../renderer/curve_texture.zig");
const atlas_curve_mod = @import("../renderer/atlas/curve.zig");
const atlas_page_mod = @import("../renderer/atlas/page.zig");
const paint_api = @import("../paint.zig");
const paint_records = @import("../paint_records.zig");
const picture_compile = @import("picture_compile.zig");
const resource_footprint_mod = @import("../resources/footprint.zig");
const scene_mod = @import("../scene.zig");
const target_mod = @import("../target.zig");
const upload_mod = @import("../upload.zig");
const vec = @import("../math/vec.zig");

const Atlas = atlas_curve_mod.Atlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const BBox = bezier.BBox;
const CurveSegment = bezier.CurveSegment;
const FillStyle = paint_api.FillStyle;
const Paint = paint_api.Paint;
const Path = core.Path;
const Range = scene_mod.Range;
const Rect = target_mod.Rect;
const ResourceFootprint = upload_mod.ResourceFootprint;
const StrokeStyle = paint_api.StrokeStyle;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;
const bboxCenter = core.bboxCenter;
const buildCircularSectorPath = core.buildCircularSectorPath;
const curveAtlasFootprint = resource_footprint_mod.curveAtlasFootprint;
const fillStyleForStroke = core.fillStyleForStroke;
const kPathLargePrimitiveTileExtent = core.kPathLargePrimitiveTileExtent;
const translateBBox = core.translateBBox;
const translatePaint = core.translatePaint;

pub const PATH_PAINT_INFO_WIDTH: u32 = paint_records.info_width;
pub const PATH_PAINT_TEXELS_PER_RECORD: u32 = paint_records.texels_per_record;
pub const PATH_PAINT_TAG_SOLID: f32 = paint_records.tag_solid;
pub const PATH_PAINT_TAG_LINEAR_GRADIENT: f32 = paint_records.tag_linear_gradient;
pub const PATH_PAINT_TAG_RADIAL_GRADIENT: f32 = paint_records.tag_radial_gradient;
pub const PATH_PAINT_TAG_IMAGE: f32 = paint_records.tag_image;
pub const PATH_PAINT_TAG_COMPOSITE_GROUP: f32 = paint_records.tag_composite_group;

pub const PathPictureDebugView = enum(u8) {
    normal,
    fill_mask,
    stroke_mask,
    layer_tint,
};

pub const PathPictureBoundsOverlayOptions = struct {
    stroke_color: [4]f32 = .{ 1.0, 0.36, 0.24, 0.95 },
    stroke_width: f32 = 1.0,
    origin_color: [4]f32 = .{ 1.0, 0.78, 0.22, 0.95 },
    origin_size: f32 = 6.0,
};

const kPaintInfoWidth: u32 = PATH_PAINT_INFO_WIDTH;
const kPaintTexelsPerRecord: u32 = PATH_PAINT_TEXELS_PER_RECORD;
const kPaintTagSolid: f32 = PATH_PAINT_TAG_SOLID;
const kPaintTagLinearGradient: f32 = PATH_PAINT_TAG_LINEAR_GRADIENT;
const kPaintTagRadialGradient: f32 = PATH_PAINT_TAG_RADIAL_GRADIENT;
const kPaintTagImage: f32 = PATH_PAINT_TAG_IMAGE;
const kPaintTagCompositeGroup: f32 = PATH_PAINT_TAG_COMPOSITE_GROUP;

const PathCompositeMode = enum(u8) {
    source_over = 0,
    fill_stroke_inside = 1,
};

fn pathPaintInfoWidth(texel_count: u32) u32 {
    return paint_records.infoWidth(texel_count);
}

fn pathLayerInfoTexelOffset(texel_width: u32, info_x: u16, info_y: u16) u32 {
    return @as(u32, info_y) * texel_width + @as(u32, info_x);
}

fn readPathLayerInfoTexel(data: []const f32, texel_width: u32, texel_offset: u32) [4]f32 {
    return paint_records.readTexel(data, texel_width, texel_offset);
}

fn writePathLayerInfoTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
    paint_records.setTexel(data, texel_width, texel_offset, value);
}

fn paletteColor(index: usize) [4]f32 {
    const palette = [_][4]f32{
        .{ 0.27, 0.86, 0.98, 0.96 },
        .{ 0.98, 0.54, 0.29, 0.96 },
        .{ 0.58, 0.94, 0.43, 0.96 },
        .{ 0.95, 0.39, 0.77, 0.96 },
        .{ 0.99, 0.86, 0.28, 0.96 },
        .{ 0.56, 0.66, 0.98, 0.96 },
    };
    return palette[index % palette.len];
}

fn blendColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    };
}

fn debugPaintColor(view: PathPictureDebugView, role: PathPicture.LayerRole, shape_index: usize) [4]f32 {
    const base = paletteColor(shape_index);
    return switch (view) {
        .normal => .{ 0, 0, 0, 0 },
        .fill_mask => switch (role) {
            .fill => base,
            .stroke => .{ 0.0, 0.0, 0.0, 0.0 },
        },
        .stroke_mask => switch (role) {
            .fill => .{ 0.0, 0.0, 0.0, 0.0 },
            .stroke => base,
        },
        .layer_tint => switch (role) {
            .fill => blendColor(base, .{ 0.15, 0.90, 0.98, 0.96 }, 0.45),
            .stroke => blendColor(base, .{ 0.98, 0.24, 0.82, 0.96 }, 0.55),
        },
    };
}

pub const PathPicture = struct {
    allocator: std.mem.Allocator,
    atlas: Atlas,
    shapes: []Shape,
    layer_roles: []LayerRole,

    pub const LayerRole = enum(u8) {
        fill,
        stroke,
    };

    pub const Shape = struct {
        glyph_id: u16,
        bbox: BBox,
        page_index: u16,
        info_x: u16,
        info_y: u16,
        layer_count: u16 = 1,
        transform: Transform2D,
    };

    pub fn deinit(self: *PathPicture) void {
        self.atlas.deinit();
        self.allocator.free(self.shapes);
        self.allocator.free(self.layer_roles);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPicture) usize {
        return self.shapes.len;
    }

    pub fn uploadFootprint(self: *const PathPicture) ResourceFootprint {
        return curveAtlasFootprint(&self.atlas, .exact);
    }

    fn applyDebugViewInPlace(self: *PathPicture, view: PathPictureDebugView) void {
        if (view == .normal) return;
        const data = self.atlas.layer_info_data orelse return;
        const width = self.atlas.layer_info_width;

        for (self.shapes, 0..) |shape, shape_index| {
            const info_offset = pathLayerInfoTexelOffset(width, shape.info_x, shape.info_y);
            var header = readPathLayerInfoTexel(data, width, info_offset);
            var layer_count: usize = 1;
            var record_base = info_offset;

            if (@abs(header[3] - PATH_PAINT_TAG_COMPOSITE_GROUP) <= 0.001) {
                layer_count = @intCast(@as(i32, @intFromFloat(@round(header[0]))));
                header[1] = @floatFromInt(@intFromEnum(PathCompositeMode.source_over));
                writePathLayerInfoTexel(data, width, info_offset, header);
                record_base += 1;
            }

            for (0..layer_count) |layer_index| {
                const role_index = @as(usize, shape.glyph_id - 1) + layer_index;
                if (role_index >= self.layer_roles.len) break;
                const texel_offset = record_base + @as(u32, @intCast(layer_index)) * PATH_PAINT_TEXELS_PER_RECORD;
                var info = readPathLayerInfoTexel(data, width, texel_offset);
                info[3] = PATH_PAINT_TAG_SOLID;
                writePathLayerInfoTexel(data, width, texel_offset, info);
                writePathLayerInfoTexel(data, width, texel_offset + 2, debugPaintColor(view, self.layer_roles[role_index], shape_index));
            }
        }
    }

    pub fn withDebugView(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        view: PathPictureDebugView,
    ) !PathPicture {
        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.atlas.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        const pages = try allocator.alloc(*AtlasPage, self.atlas.pages.len);
        errdefer allocator.free(pages);
        for (self.atlas.pages, 0..) |page, i| pages[i] = page.retain();

        var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
        errdefer atlas.deinit();

        if (self.atlas.layer_info_data) |data| {
            atlas.layer_info_data = try allocator.dupe(f32, data);
            atlas.layer_info_width = self.atlas.layer_info_width;
            atlas.layer_info_height = self.atlas.layer_info_height;
        }
        if (self.atlas.paint_image_records) |records| {
            atlas.paint_image_records = try allocator.dupe(?Atlas.PaintImageRecord, records);
        }

        const shapes = try allocator.dupe(Shape, self.shapes);
        errdefer allocator.free(shapes);
        const layer_roles = try allocator.dupe(LayerRole, self.layer_roles);
        errdefer allocator.free(layer_roles);

        var result = PathPicture{
            .allocator = allocator,
            .atlas = atlas,
            .shapes = shapes,
            .layer_roles = layer_roles,
        };
        result.applyDebugViewInPlace(view);
        return result;
    }

    pub fn buildBoundsOverlay(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        options: PathPictureBoundsOverlayOptions,
    ) !PathPicture {
        if (self.shapes.len == 0) return error.EmptyPicture;

        var builder = PathPictureBuilder.init(allocator);
        defer builder.deinit();

        const cross_thickness = @max(options.stroke_width, 1.0);
        for (self.shapes) |shape| {
            const rect = Rect{
                .x = shape.bbox.min.x,
                .y = shape.bbox.min.y,
                .w = shape.bbox.max.x - shape.bbox.min.x,
                .h = shape.bbox.max.y - shape.bbox.min.y,
            };
            try builder.addStrokedRect(
                rect,
                .{ .paint = .{ .solid = options.stroke_color }, .width = options.stroke_width, .join = .miter },
                shape.transform,
            );
            if (options.origin_size > 1e-4 and options.origin_color[3] > 1e-4) {
                try builder.addFilledRect(.{
                    .x = -options.origin_size,
                    .y = -cross_thickness * 0.5,
                    .w = options.origin_size * 2.0,
                    .h = cross_thickness,
                }, .{ .paint = .{ .solid = options.origin_color } }, shape.transform);
                try builder.addFilledRect(.{
                    .x = -cross_thickness * 0.5,
                    .y = -options.origin_size,
                    .w = cross_thickness,
                    .h = options.origin_size * 2.0,
                }, .{ .paint = .{ .solid = options.origin_color } }, shape.transform);
            }
        }

        return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
    }
};

pub const PathPictureBuilder = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList(PathRecord) = .empty,

    pub const ShapeMark = struct {
        shape_count: usize = 0,
    };

    pub const FreezeOptions = struct {
        /// Owns the returned `PathPicture`'s arrays and atlas page data.
        persistent_allocator: std.mem.Allocator,
        /// Used only while compiling path geometry into texture data.
        scratch_allocator: std.mem.Allocator,
    };

    const PathLayerRecord = struct {
        curves: []CurveSegment,
        bbox: BBox,
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
    };

    const PathRecord = struct {
        bbox: BBox,
        transform: Transform2D,
        layer_count: u16,
        composite_mode: PathCompositeMode,
        layers: [2]PathLayerRecord,
    };

    pub fn init(allocator: std.mem.Allocator) PathPictureBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathPictureBuilder) void {
        for (self.paths.items) |path| {
            for (path.layers[0..path.layer_count]) |layer| self.allocator.free(layer.curves);
        }
        self.paths.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPictureBuilder) usize {
        return self.paths.items.len;
    }

    pub fn mark(self: *const PathPictureBuilder) ShapeMark {
        return .{ .shape_count = self.shapeCount() };
    }

    pub fn rangeFrom(self: *const PathPictureBuilder, mark_value: ShapeMark) !Range {
        return self.rangeBetween(mark_value, self.mark());
    }

    pub fn rangeBetween(self: *const PathPictureBuilder, start: ShapeMark, end: ShapeMark) !Range {
        const total = self.shapeCount();
        if (start.shape_count > total or end.shape_count > total) return error.InvalidShapeMark;
        if (start.shape_count > end.shape_count) return error.InvalidShapeRange;
        return .{
            .start = start.shape_count,
            .count = end.shape_count - start.shape_count,
        };
    }

    fn addSingleRecord(
        self: *PathPictureBuilder,
        curves: []CurveSegment,
        bbox: BBox,
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
        transform: Transform2D,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = bbox,
            .transform = transform,
            .layer_count = 1,
            .composite_mode = .source_over,
            .layers = .{
                .{
                    .curves = curves,
                    .bbox = bbox,
                    .logical_curve_count = logical_curve_count,
                    .paint = paint,
                    .role = role,
                },
                undefined,
            },
        });
    }

    fn shouldTileRoundedRect(size: Vec2) bool {
        return @max(size.x, size.y) > kPathLargePrimitiveTileExtent;
    }

    fn addFilledRectTiles(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        const width = @max(rect.w, 0.0);
        const height = @max(rect.h, 0.0);
        if (width <= 1e-4 or height <= 1e-4) return;

        var y = rect.y;
        var remaining_h = height;
        while (remaining_h > 1e-4) {
            const tile_h = @min(remaining_h, kPathLargePrimitiveTileExtent);
            var x = rect.x;
            var remaining_w = width;
            while (remaining_w > 1e-4) {
                const tile_w = @min(remaining_w, kPathLargePrimitiveTileExtent);
                try self.addFilledRect(.{
                    .x = x,
                    .y = y,
                    .w = tile_w,
                    .h = tile_h,
                }, fill, transform);
                x += tile_w;
                remaining_w -= tile_w;
            }
            y += tile_h;
            remaining_h -= tile_h;
        }
    }

    fn addFilledCircularSector(
        self: *PathPictureBuilder,
        center: Vec2,
        outer_radius: f32,
        inner_radius: f32,
        start_angle: f32,
        end_angle: f32,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        if (outer_radius <= 1e-4) return;
        var path = Path.init(self.allocator);
        defer path.deinit();
        try buildCircularSectorPath(&path, center, outer_radius, inner_radius, start_angle, end_angle);
        try self.addFilledPath(&path, fill, transform);
    }

    fn addSimpleFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, null, transform);
    }

    fn addLargeFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addFilledRect(rect, fill, transform);

        const inner_w = size.x - radius * 2.0;
        const inner_h = size.y - radius * 2.0;

        if (inner_w > 1e-4 and inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + radius,
                .w = inner_w,
                .h = inner_h,
            }, fill, transform);
        }
        if (inner_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - radius,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
        }
        if (inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - radius,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
        }

        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                0.0,
                corner.start_angle,
                corner.end_angle,
                fill,
                transform,
            );
        }
    }

    fn addLargeInsideStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const inset = std.math.clamp(stroke.width, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) {
            if (fill) |style| {
                const inner_w = @max(size.x - inset * 2.0, 0.0);
                const inner_h = @max(size.y - inset * 2.0, 0.0);
                if (inner_w > 1e-4 and inner_h > 1e-4) {
                    try self.addFilledRectTiles(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = inner_w,
                        .h = inner_h,
                    }, style, transform);
                }
            }
            const stroke_fill = fillStyleForStroke(stroke);
            if (inset > 1e-4) {
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y, .w = size.x, .h = inset }, stroke_fill, transform);
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + size.y - inset, .w = size.x, .h = inset }, stroke_fill, transform);
                const middle_h = size.y - inset * 2.0;
                if (middle_h > 1e-4) {
                    try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                    try self.addFilledRectTiles(.{ .x = rect.x + size.x - inset, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                }
            }
            return;
        }

        if (fill) |style| {
            const inner_rect = Rect{
                .x = rect.x + inset,
                .y = rect.y + inset,
                .w = size.x - inset * 2.0,
                .h = size.y - inset * 2.0,
            };
            if (inner_rect.w > 1e-4 and inner_rect.h > 1e-4) {
                const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                if (shouldTileRoundedRect(Vec2.new(inner_rect.w, inner_rect.h))) {
                    try self.addLargeFilledRoundedRect(inner_rect, style, inner_radius, transform);
                } else {
                    try self.addSimpleFilledRoundedRect(inner_rect, style, inner_radius, transform);
                }
            }
        }

        if (inset <= 1e-4) return;

        const stroke_fill = fillStyleForStroke(stroke);
        const straight_w = size.x - radius * 2.0;
        const straight_h = size.y - radius * 2.0;
        if (straight_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - inset,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
        }
        if (straight_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - inset,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
        }

        const inner_radius = @max(radius - inset, 0.0);
        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                inner_radius,
                corner.start_angle,
                corner.end_angle,
                stroke_fill,
                transform,
            );
        }
    }

    fn addLargeCenterStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const half_width = @max(stroke.width * 0.5, 0.0);

        if (fill) |style| {
            try self.addLargeFilledRoundedRect(rect, style, radius, transform);
        }

        if (stroke.width <= 1e-4) return;

        var stroke_only = stroke;
        stroke_only.placement = .inside;
        const expanded = Rect{
            .x = rect.x - half_width,
            .y = rect.y - half_width,
            .w = size.x + stroke.width,
            .h = size.y + stroke.width,
        };
        try self.addLargeInsideStrokeRoundedRect(
            expanded,
            null,
            stroke_only,
            radius + half_width,
            transform,
        );
    }

    fn addExplicitInsideStrokeRecord(
        self: *PathPictureBuilder,
        fill_path: *const Path,
        fill: ?FillStyle,
        stroke_path: *const Path,
        stroke_paint: Paint,
        transform: Transform2D,
    ) !void {
        const stroke_bbox = stroke_path.bounds() orelse return error.EmptyPath;
        const stroke_curves = try stroke_path.cloneFilledCurves(self.allocator);
        errdefer self.allocator.free(stroke_curves);
        const stroke_logical_curve_count = stroke_path.filledBandCurveCount();

        if (fill) |style| {
            const fill_bbox = fill_path.bounds() orelse return error.EmptyPath;
            const fill_curves = try fill_path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(fill_curves);
            const fill_logical_curve_count = fill_path.filledBandCurveCount();
            try self.addCompositeRecord(
                fill_curves,
                fill_bbox,
                fill_logical_curve_count,
                style.paint,
                stroke_curves,
                stroke_bbox,
                stroke_logical_curve_count,
                stroke_paint,
                transform,
                .fill_stroke_inside,
            );
            return;
        }

        try self.addSingleRecord(stroke_curves, stroke_bbox, stroke_logical_curve_count, stroke_paint, .stroke, transform);
    }

    fn addCompositeRecord(
        self: *PathPictureBuilder,
        fill_curves: []CurveSegment,
        fill_bbox: BBox,
        fill_logical_curve_count: usize,
        fill_paint: Paint,
        stroke_curves: []CurveSegment,
        stroke_bbox: BBox,
        stroke_logical_curve_count: usize,
        stroke_paint: Paint,
        transform: Transform2D,
        composite_mode: PathCompositeMode,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = switch (composite_mode) {
                .source_over => fill_bbox.merge(stroke_bbox),
                .fill_stroke_inside => fill_bbox,
            },
            .transform = transform,
            .layer_count = 2,
            .composite_mode = composite_mode,
            .layers = .{
                .{
                    .curves = fill_curves,
                    .bbox = fill_bbox,
                    .logical_curve_count = fill_logical_curve_count,
                    .paint = fill_paint,
                    .role = .fill,
                },
                .{
                    .curves = stroke_curves,
                    .bbox = stroke_bbox,
                    .logical_curve_count = stroke_logical_curve_count,
                    .paint = stroke_paint,
                    .role = .stroke,
                },
            },
        });
    }

    pub fn addPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (fill == null and stroke == null) return error.EmptyStyle;
        if (path.isEmpty()) return error.EmptyPath;

        if (fill) |style| {
            const bbox = path.bounds() orelse return error.EmptyPath;
            const curves = try path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(curves);
            const logical_curve_count = path.filledBandCurveCount();
            if (stroke) |stroke_style| {
                var stroke_geom_style = stroke_style;
                if (stroke_style.placement == .inside) stroke_geom_style.width *= 2.0;
                if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                    errdefer self.allocator.free(stroke_geom.curves);
                    const composite_mode: PathCompositeMode = if (stroke_style.placement == .inside)
                        .fill_stroke_inside
                    else
                        .source_over;
                    try self.addCompositeRecord(
                        curves,
                        bbox,
                        logical_curve_count,
                        style.paint,
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        stroke_style.paint,
                        transform,
                        composite_mode,
                    );
                    return;
                }
            }
            try self.addSingleRecord(curves, bbox, logical_curve_count, style.paint, .fill, transform);
        }
        if (stroke) |style| {
            var stroke_geom_style = style;
            if (style.placement == .inside) stroke_geom_style.width *= 2.0;
            if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                errdefer self.allocator.free(stroke_geom.curves);
                if (style.placement == .inside) {
                    const fill_bbox = path.bounds() orelse return error.EmptyPath;
                    const fill_curves = try path.cloneFilledCurves(self.allocator);
                    errdefer self.allocator.free(fill_curves);
                    try self.addCompositeRecord(
                        fill_curves,
                        fill_bbox,
                        path.filledBandCurveCount(),
                        .{ .solid = .{ 0, 0, 0, 0 } },
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        style.paint,
                        transform,
                        .fill_stroke_inside,
                    );
                    return;
                }
                try self.addSingleRecord(
                    stroke_geom.curves,
                    stroke_geom.bbox,
                    stroke_geom.logical_curve_count,
                    style.paint,
                    .stroke,
                    transform,
                );
            }
        }
    }

    pub fn addFilledPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, fill, null, transform);
    }

    pub fn addStrokedPath(
        self: *PathPictureBuilder,
        path: *const Path,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, null, stroke, transform);
    }

    pub fn addRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRect(rect);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRect(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addRectReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));

        if (stroke) |stroke_style| {
            const max_radius = @min(size.x, size.y) * 0.5;
            const radius = std.math.clamp(corner_radius, 0.0, max_radius);
            const inset = std.math.clamp(stroke_style.width, 0.0, max_radius);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRoundedRect(rect, radius);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRoundedRect(rect, radius);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    const inner_rect = Rect{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    };
                    const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                    try stroke_path.addRoundedRectReversed(inner_rect, inner_radius);
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addEllipse(rect);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addEllipse(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addEllipseReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, fill, null, transform);
    }

    pub fn addFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, fill, null, corner_radius, transform);
    }

    pub fn addFilledEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addEllipse(rect, fill, null, transform);
    }

    pub fn addStrokedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, null, stroke, transform);
    }

    pub fn addStrokedRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, null, stroke, corner_radius, transform);
    }

    pub fn addStrokedEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addEllipse(rect, null, stroke, transform);
    }

    pub fn freeze(self: *const PathPictureBuilder, options: FreezeOptions) !PathPicture {
        return picture_compile.freeze(PathPicture, PathPictureBuilder, self, options);
    }
};
