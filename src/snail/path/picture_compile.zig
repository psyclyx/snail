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

pub fn freeze(comptime PathPicture: type, comptime PathPictureBuilder: type, self: *const PathPictureBuilder, options: PathPictureBuilder.FreezeOptions) !PathPicture {
    if (self.paths.items.len == 0) return error.EmptyPicture;
    const allocator = options.persistent_allocator;
    const scratch_allocator = options.scratch_allocator;

    var total_layer_count: usize = 0;
    var total_paint_texels: u32 = 0;
    for (self.paths.items) |path| {
        total_layer_count += path.layer_count;
        total_paint_texels += if (path.layer_count == 1)
            kPaintTexelsPerRecord
        else
            1 + @as(u32, path.layer_count) * kPaintTexelsPerRecord;
    }

    const glyph_curves = try scratch_allocator.alloc(curve_tex.GlyphCurves, total_layer_count);
    defer scratch_allocator.free(glyph_curves);
    const packed_curve_slices = try scratch_allocator.alloc([]CurveSegment, total_layer_count);
    defer scratch_allocator.free(packed_curve_slices);
    const prepared_curve_slices = try scratch_allocator.alloc([]CurveSegment, total_layer_count);
    defer scratch_allocator.free(prepared_curve_slices);
    var glyph_cursor: usize = 0;
    defer {
        for (packed_curve_slices[0..glyph_cursor], prepared_curve_slices[0..glyph_cursor]) |curves, prepared_curves| {
            scratch_allocator.free(curves);
            scratch_allocator.free(prepared_curves);
        }
    }
    for (self.paths.items) |path| {
        const origin = core.bboxCenter(path.bbox);
        for (path.layers[0..path.layer_count]) |layer| {
            const stored_curves = try scratch_allocator.dupe(CurveSegment, layer.curves);
            const prepared_curves = curve_tex.prepareGlyphCurvesForDirectEncoding(scratch_allocator, stored_curves, origin) catch |err| {
                scratch_allocator.free(stored_curves);
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

    var ct = try curve_tex.buildCurveTexture(allocator, scratch_allocator, glyph_curves);
    var ct_texture_owned = true;
    errdefer if (ct_texture_owned) ct.texture.deinit();
    defer scratch_allocator.free(ct.entries);

    var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
    defer {
        for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(scratch_allocator, bd);
        glyph_band_data.deinit(scratch_allocator);
    }
    for (glyph_curves, 0..) |gc, i| {
        var bd = try band_tex.buildGlyphBandDataForGlyph(scratch_allocator, gc, ct.entries[i]);
        try glyph_band_data.append(scratch_allocator, bd);
        _ = &bd;
    }

    var bt = try band_tex.buildBandTexture(allocator, scratch_allocator, glyph_band_data.items);
    var bt_texture_owned = true;
    errdefer if (bt_texture_owned) bt.texture.deinit();
    defer scratch_allocator.free(bt.entries);

    var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
    errdefer glyph_map.deinit();

    const paint_width = pathPaintInfoWidth(total_paint_texels);
    const paint_height = @max(1, (total_paint_texels + paint_width - 1) / paint_width);
    const layer_info_data = try allocator.alloc(f32, paint_width * paint_height * 4);
    errdefer allocator.free(layer_info_data);
    @memset(layer_info_data, 0);

    const shapes = try allocator.alloc(PathPicture.Shape, self.paths.items.len);
    errdefer allocator.free(shapes);

    const layer_roles = try allocator.alloc(PathPicture.LayerRole, total_layer_count);
    errdefer allocator.free(layer_roles);

    const paint_image_records = try allocator.alloc(?Atlas.PaintImageRecord, total_layer_count);
    errdefer allocator.free(paint_image_records);
    @memset(paint_image_records, null);

    var has_image_paints = false;

    glyph_cursor = 0;
    var texel_cursor: u32 = 0;
    for (self.paths.items, 0..) |path, path_index| {
        const info_texel_offset = texel_cursor;
        if (path.layer_count > 1) {
            paint_records.setTexel(layer_info_data, paint_width, texel_cursor, .{
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
            try glyph_map.put(glyph_id, .{
                .bbox = local_bbox,
                .advance_width = 0,
                .band_entry = bt.entries[glyph_cursor],
                .page_index = 0,
            });
            layer_roles[glyph_cursor] = layer.role;
            paint_records.write(layer_info_data, paint_width, texel_cursor, bt.entries[glyph_cursor], local_paint);
            switch (local_paint) {
                .image => |image_paint| {
                    paint_image_records[glyph_cursor] = .{
                        .image = image_paint.image,
                        .texel_offset = texel_cursor,
                    };
                    has_image_paints = true;
                },
                else => {},
            }
            texel_cursor += kPaintTexelsPerRecord;
            glyph_cursor += 1;
        }

        shapes[path_index] = .{
            .glyph_id = first_glyph_id,
            .bbox = core.translateBBox(path.bbox, delta),
            .page_index = 0,
            .info_x = @intCast(info_texel_offset % paint_width),
            .info_y = @intCast(info_texel_offset / paint_width),
            .layer_count = path.layer_count,
            .transform = Transform2D.multiply(path.transform, Transform2D.translate(origin.x, origin.y)),
        };
    }

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

    var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
    errdefer atlas.deinit();
    atlas.layer_info_data = layer_info_data;
    atlas.layer_info_width = paint_width;
    atlas.layer_info_height = paint_height;
    if (has_image_paints) {
        atlas.paint_image_records = paint_image_records;
    } else {
        allocator.free(paint_image_records);
    }

    return .{
        .allocator = allocator,
        .atlas = atlas,
        .shapes = shapes,
        .layer_roles = layer_roles,
    };
}
