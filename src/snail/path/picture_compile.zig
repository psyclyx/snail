const std = @import("std");

const band_tex = @import("../render/format/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const core = @import("core.zig");
const curve_tex = @import("../render/format/curve_texture.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const atlas_page_mod = @import("../render/format/atlas/page.zig");
const paint_records = @import("../paint_records.zig");
const vec = @import("../math/vec.zig");

const Atlas = atlas_curve_mod.Atlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const CurveSegment = bezier.CurveSegment;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

const kPaintTexelsPerRecord: u32 = paint_records.texels_per_record;
const kPaintTagCompositeGroup: f32 = paint_records.tag_composite_group;

fn pathPaintInfoWidth(texel_count: u32) u32 {
    return paint_records.infoWidth(texel_count);
}

const PathPictureMetrics = struct {
    layer_count: usize = 0,
    paint_texels: u32 = 0,
};

const PreparedPathCurves = struct {
    glyph_curves: []curve_tex.GlyphCurves,
    packed_curve_slices: [][]CurveSegment,
    prepared_curve_slices: [][]CurveSegment,
    glyph_count: usize = 0,

    fn deinit(self: *PreparedPathCurves, allocator: std.mem.Allocator) void {
        for (self.packed_curve_slices[0..self.glyph_count], self.prepared_curve_slices[0..self.glyph_count]) |curves, prepared_curves| {
            allocator.free(curves);
            allocator.free(prepared_curves);
        }
        allocator.free(self.glyph_curves);
        allocator.free(self.packed_curve_slices);
        allocator.free(self.prepared_curve_slices);
        self.* = undefined;
    }
};

const PathGlyphBandData = struct {
    list: std.ArrayList(band_tex.GlyphBandData) = .empty,

    fn slice(self: *const PathGlyphBandData) []const band_tex.GlyphBandData {
        return self.list.items;
    }

    fn deinit(self: *PathGlyphBandData, allocator: std.mem.Allocator) void {
        for (self.list.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
        self.list.deinit(allocator);
        self.* = undefined;
    }
};

fn PathPictureParts(comptime PathPicture: type) type {
    return struct {
        glyph_map: std.AutoHashMap(u16, Atlas.GlyphInfo),
        layer_info_data: []f32,
        layer_info_width: u32,
        layer_info_height: u32,
        shapes: []PathPicture.Shape,
        layer_roles: []PathPicture.LayerRole,
        paint_image_records: []?Atlas.PaintImageRecord,
        has_image_paints: bool = false,

        owns_glyph_map: bool = true,
        owns_layer_info_data: bool = true,
        owns_shapes: bool = true,
        owns_layer_roles: bool = true,
        owns_paint_image_records: bool = true,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_glyph_map) self.glyph_map.deinit();
            if (self.owns_layer_info_data) allocator.free(self.layer_info_data);
            if (self.owns_shapes) allocator.free(self.shapes);
            if (self.owns_layer_roles) allocator.free(self.layer_roles);
            if (self.owns_paint_image_records) allocator.free(self.paint_image_records);
            self.* = undefined;
        }
    };
}

fn measurePathPicture(comptime PathPictureBuilder: type, self: *const PathPictureBuilder) PathPictureMetrics {
    var metrics: PathPictureMetrics = .{};
    for (self.paths.items) |path| {
        metrics.layer_count += path.layer_count;
        metrics.paint_texels += if (path.layer_count == 1)
            kPaintTexelsPerRecord
        else
            1 + @as(u32, path.layer_count) * kPaintTexelsPerRecord;
    }
    return metrics;
}

fn buildPathGlyphCurves(comptime PathPictureBuilder: type, allocator: std.mem.Allocator, self: *const PathPictureBuilder, metrics: PathPictureMetrics) !PreparedPathCurves {
    const glyph_curves = try allocator.alloc(curve_tex.GlyphCurves, metrics.layer_count);
    errdefer allocator.free(glyph_curves);
    const packed_curve_slices = try allocator.alloc([]CurveSegment, metrics.layer_count);
    errdefer allocator.free(packed_curve_slices);
    const prepared_curve_slices = try allocator.alloc([]CurveSegment, metrics.layer_count);
    errdefer allocator.free(prepared_curve_slices);

    var glyph_cursor: usize = 0;
    errdefer {
        for (packed_curve_slices[0..glyph_cursor], prepared_curve_slices[0..glyph_cursor]) |curves, prepared_curves| {
            allocator.free(curves);
            allocator.free(prepared_curves);
        }
    }

    for (self.paths.items) |path| {
        const origin = core.bboxCenter(path.bbox);
        for (path.layers[0..path.layer_count]) |layer| {
            const stored_curves = try allocator.dupe(CurveSegment, layer.curves);
            const prepared_curves = curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, stored_curves, origin) catch |err| {
                allocator.free(stored_curves);
                return err;
            };
            packed_curve_slices[glyph_cursor] = stored_curves;
            prepared_curve_slices[glyph_cursor] = prepared_curves;
            glyph_curves[glyph_cursor] = .{
                .curves = stored_curves,
                .bbox = layer.bbox,
                .origin = origin,
                .logical_curve_count = layer.logical_curve_count,
                .prefer_direct_encoding = true,
                .prepared_curves = prepared_curves,
            };
            glyph_cursor += 1;
        }
    }

    return .{
        .glyph_curves = glyph_curves,
        .packed_curve_slices = packed_curve_slices,
        .prepared_curve_slices = prepared_curve_slices,
        .glyph_count = glyph_cursor,
    };
}

fn buildPathGlyphBandData(allocator: std.mem.Allocator, glyph_curves: []const curve_tex.GlyphCurves, curve_entries: []const curve_tex.GlyphCurveEntry) !PathGlyphBandData {
    var out: PathGlyphBandData = .{};
    errdefer out.deinit(allocator);

    for (glyph_curves, 0..) |gc, i| {
        var bd = try band_tex.buildGlyphBandDataForGlyph(allocator, gc, curve_entries[i]);
        out.list.append(allocator, bd) catch |err| {
            band_tex.freeGlyphBandData(allocator, &bd);
            return err;
        };
    }
    return out;
}

fn initPathPicturePartsStorage(comptime PathPicture: type, allocator: std.mem.Allocator, path_count: usize, metrics: PathPictureMetrics) !PathPictureParts(PathPicture) {
    var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
    errdefer glyph_map.deinit();

    const paint_width = pathPaintInfoWidth(metrics.paint_texels);
    const paint_height = @max(1, (metrics.paint_texels + paint_width - 1) / paint_width);
    const layer_info_data = try allocator.alloc(f32, paint_width * paint_height * 4);
    errdefer allocator.free(layer_info_data);
    @memset(layer_info_data, 0);

    const shapes = try allocator.alloc(PathPicture.Shape, path_count);
    errdefer allocator.free(shapes);

    const layer_roles = try allocator.alloc(PathPicture.LayerRole, metrics.layer_count);
    errdefer allocator.free(layer_roles);

    const paint_image_records = try allocator.alloc(?Atlas.PaintImageRecord, metrics.layer_count);
    errdefer allocator.free(paint_image_records);
    @memset(paint_image_records, null);

    return .{
        .glyph_map = glyph_map,
        .layer_info_data = layer_info_data,
        .layer_info_width = paint_width,
        .layer_info_height = paint_height,
        .shapes = shapes,
        .layer_roles = layer_roles,
        .paint_image_records = paint_image_records,
    };
}

fn writePathPictureParts(
    comptime PathPicture: type,
    comptime PathPictureBuilder: type,
    parts: *PathPictureParts(PathPicture),
    self: *const PathPictureBuilder,
    band_entries: []const band_tex.GlyphBandEntry,
) !void {
    var glyph_cursor: usize = 0;
    var texel_cursor: u32 = 0;
    for (self.paths.items, 0..) |path, path_index| {
        const info_texel_offset = texel_cursor;
        if (path.layer_count > 1) {
            paint_records.setTexel(parts.layer_info_data, parts.layer_info_width, texel_cursor, .{
                @floatFromInt(path.layer_count),
                @floatFromInt(@intFromEnum(path.composite_mode)),
                0,
                kPaintTagCompositeGroup,
            });
            texel_cursor += 1;
        }

        var first_glyph_id: u16 = 0;
        const origin = core.bboxCenter(path.bbox);
        const delta = Vec2.new(-origin.x, -origin.y);
        for (path.layers[0..path.layer_count], 0..) |layer, layer_index| {
            const glyph_id: u16 = @intCast(glyph_cursor + 1);
            if (layer_index == 0) first_glyph_id = glyph_id;
            const local_bbox = core.translateBBox(layer.bbox, delta);
            const local_paint = core.translatePaint(layer.paint, delta);
            try parts.glyph_map.put(glyph_id, .{
                .bbox = local_bbox,
                .advance_width = 0,
                .band_entry = band_entries[glyph_cursor],
                .page_index = 0,
            });
            parts.layer_roles[glyph_cursor] = layer.role;
            paint_records.write(parts.layer_info_data, parts.layer_info_width, texel_cursor, band_entries[glyph_cursor], local_paint);
            switch (local_paint) {
                .image => |image_paint| {
                    parts.paint_image_records[glyph_cursor] = .{
                        .image = image_paint.image,
                        .texel_offset = texel_cursor,
                    };
                    parts.has_image_paints = true;
                },
                else => {},
            }
            texel_cursor += kPaintTexelsPerRecord;
            glyph_cursor += 1;
        }

        parts.shapes[path_index] = .{
            .glyph_id = first_glyph_id,
            .bbox = core.translateBBox(path.bbox, delta),
            .page_index = 0,
            .info_x = @intCast(info_texel_offset % parts.layer_info_width),
            .info_y = @intCast(info_texel_offset / parts.layer_info_width),
            .layer_count = path.layer_count,
            .transform = Transform2D.multiply(path.transform, Transform2D.translate(origin.x, origin.y)),
        };
    }
}

fn buildPathPictureParts(
    comptime PathPicture: type,
    comptime PathPictureBuilder: type,
    allocator: std.mem.Allocator,
    self: *const PathPictureBuilder,
    metrics: PathPictureMetrics,
    band_entries: []const band_tex.GlyphBandEntry,
) !PathPictureParts(PathPicture) {
    var parts = try initPathPicturePartsStorage(PathPicture, allocator, self.paths.items.len, metrics);
    errdefer parts.deinit(allocator);
    try writePathPictureParts(PathPicture, PathPictureBuilder, &parts, self, band_entries);
    return parts;
}

pub fn freeze(comptime PathPicture: type, comptime PathPictureBuilder: type, self: *const PathPictureBuilder, options: PathPictureBuilder.FreezeOptions) !PathPicture {
    if (self.paths.items.len == 0) return error.EmptyPicture;
    const allocator = options.persistent_allocator;
    const scratch_allocator = options.scratch_allocator;

    const metrics = measurePathPicture(PathPictureBuilder, self);
    var glyph_curves = try buildPathGlyphCurves(PathPictureBuilder, scratch_allocator, self, metrics);
    defer glyph_curves.deinit(scratch_allocator);

    var ct = try curve_tex.buildCurveTexture(allocator, scratch_allocator, glyph_curves.glyph_curves);
    var ct_texture_owned = true;
    errdefer if (ct_texture_owned) ct.texture.deinit();
    defer scratch_allocator.free(ct.entries);

    var glyph_band_data = try buildPathGlyphBandData(scratch_allocator, glyph_curves.glyph_curves, ct.entries);
    defer glyph_band_data.deinit(scratch_allocator);

    var bt = try band_tex.buildBandTexture(allocator, scratch_allocator, glyph_band_data.slice());
    var bt_texture_owned = true;
    errdefer if (bt_texture_owned) bt.texture.deinit();
    defer scratch_allocator.free(bt.entries);

    var parts = try buildPathPictureParts(PathPicture, PathPictureBuilder, allocator, self, metrics, bt.entries);
    errdefer parts.deinit(allocator);

    const page = try AtlasPage.init(
        allocator,
        ct.texture.data,
        ct.texture.width,
        ct.texture.height,
        bt.texture.data,
        bt.texture.width,
        bt.texture.height,
    );
    ct_texture_owned = false;
    bt_texture_owned = false;
    errdefer page.release();

    const pages = try allocator.alloc(*AtlasPage, 1);
    errdefer allocator.free(pages);
    pages[0] = page;

    var atlas = try Atlas.initFromParts(allocator, null, pages, parts.glyph_map);
    parts.owns_glyph_map = false;
    errdefer atlas.deinit();
    atlas.layer_info_data = parts.layer_info_data;
    atlas.layer_info_width = parts.layer_info_width;
    atlas.layer_info_height = parts.layer_info_height;
    parts.owns_layer_info_data = false;
    if (parts.has_image_paints) {
        atlas.paint_image_records = parts.paint_image_records;
        parts.owns_paint_image_records = false;
    } else {
        allocator.free(parts.paint_image_records);
        parts.owns_paint_image_records = false;
    }
    parts.owns_shapes = false;
    parts.owns_layer_roles = false;

    return .{
        .allocator = allocator,
        .atlas = atlas,
        .shapes = parts.shapes,
        .layer_roles = parts.layer_roles,
    };
}
