const std = @import("std");
const snail = @import("../../../root.zig");
const atlas_curve_mod = @import("../atlas/curve.zig");
const atlas_page_mod = @import("../atlas/page.zig");
const coverage = @import("coverage.zig");
const path_paint = @import("path_paint.zig");
const texture = @import("texture.zig");

const AtlasPage = atlas_page_mod.AtlasPage;
const CurveAtlas = atlas_curve_mod.CurveAtlas;
const LayerInfoEntry = path_paint.LayerInfoEntry;
const PreparedAxisCurve = coverage.PreparedAxisCurve;
const PreparedAxisCurveCold = coverage.PreparedAxisCurveCold;
const ResolvedLayerInfo = path_paint.ResolvedLayerInfo;
const decodeCurveSegmentFromSlice = texture.decodeCurveSegmentFromSlice;
const f16ToF32 = texture.f16ToF32;
const prepareAxisCurve = coverage.prepareAxisCurve;
const preparePathLayerInfoRecords = path_paint.preparePathLayerInfoRecords;
const readBandCurveBase = texture.readBandCurveBase;

pub const PreparedAtlasPage = struct {
    band_data: []const u16,
    h_curves: []PreparedAxisCurve,
    v_curves: []PreparedAxisCurve,
    h_cold_curves: []PreparedAxisCurveCold,
    v_cold_curves: []PreparedAxisCurveCold,
    band_width: u32,
    band_height: u32,

    fn init(allocator: std.mem.Allocator, page: *const AtlasPage) !PreparedAtlasPage {
        const curve_data = try allocator.alloc(f32, page.curve_data.len);
        defer allocator.free(curve_data);
        for (page.curve_data, 0..) |value, i| {
            curve_data[i] = f16ToF32(value);
        }
        const band_texel_count = page.band_data.len / 2;
        const h_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(h_curves);
        const v_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(v_curves);
        @memset(h_curves, .{});
        @memset(v_curves, .{});
        var h_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer h_cold_curves.deinit(allocator);
        var v_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer v_cold_curves.deinit(allocator);

        for (0..band_texel_count) |texel_idx| {
            const curve_base = readBandCurveBase(page, texel_idx) orelse continue;
            const segment = decodeCurveSegmentFromSlice(curve_data, @intCast(curve_base));

            h_curves[texel_idx] = try prepareAxisCurve(allocator, &h_cold_curves, segment, true);
            v_curves[texel_idx] = try prepareAxisCurve(allocator, &v_cold_curves, segment, false);
        }

        const h_cold_curves_owned = try h_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(h_cold_curves_owned);
        const v_cold_curves_owned = try v_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(v_cold_curves_owned);

        return .{
            .band_data = page.band_data,
            .h_curves = h_curves,
            .v_curves = v_curves,
            .h_cold_curves = h_cold_curves_owned,
            .v_cold_curves = v_cold_curves_owned,
            .band_width = page.band_width,
            .band_height = page.band_height,
        };
    }

    fn deinit(self: *PreparedAtlasPage, allocator: std.mem.Allocator) void {
        allocator.free(self.h_curves);
        allocator.free(self.v_curves);
        allocator.free(self.h_cold_curves);
        allocator.free(self.v_cold_curves);
        self.* = undefined;
    }
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    /// Flat array of atlas pages indexed by texture-array layer.
    atlas_pages: []?PreparedAtlasPage = &.{},
    /// Layer info entries from uploaded atlases (combined, like the GPU texture).
    layer_infos: []LayerInfoEntry = &.{},
    layer_info_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, atlases: []const *const CurveAtlas, layer_info_blocks: anytype) !PreparedResources {
        var layer_count: usize = 0;
        var layer_info_count: usize = 0;
        for (atlases) |atlas| {
            layer_count += atlas.pageCount();
            if (atlas.layer_info_data != null) layer_info_count += 1;
        }
        for (layer_info_blocks) |block| {
            if (block.data != null) layer_info_count += 1;
        }
        const atlas_pages = try allocator.alloc(?PreparedAtlasPage, layer_count);
        errdefer allocator.free(atlas_pages);
        const layer_infos = try allocator.alloc(LayerInfoEntry, layer_info_count);
        errdefer allocator.free(layer_infos);
        @memset(atlas_pages, null);
        @memset(layer_infos, LayerInfoEntry{});
        return .{
            .allocator = allocator,
            .atlas_pages = atlas_pages,
            .layer_infos = layer_infos,
        };
    }

    pub fn deinit(self: *PreparedResources) void {
        self.reset();
        if (self.atlas_pages.len > 0) self.allocator.free(self.atlas_pages);
        if (self.layer_infos.len > 0) self.allocator.free(self.layer_infos);
        self.* = undefined;
    }

    pub fn reset(self: *PreparedResources) void {
        for (self.atlas_pages) |*page| {
            if (page.*) |*prepared_page| prepared_page.deinit(self.allocator);
        }
        for (self.layer_infos[0..self.layer_info_count]) |*entry| entry.deinit(self.allocator);
        @memset(self.atlas_pages, null);
        @memset(self.layer_infos, LayerInfoEntry{});
        self.layer_info_count = 0;
    }

    pub fn uploadAtlases(self: *PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) !void {
        var layer_base: u32 = 0;
        var info_row_base: u32 = 0;
        self.reset();
        for (out_views, atlases) |*v, a| {
            v.* = .{ .atlas = a, .layer_base = layer_base, .info_row_base = info_row_base };
            try self.storeAtlasPages(a, layer_base, info_row_base);
            layer_base += @intCast(a.pageCount());
            info_row_base += a.layer_info_height;
        }
    }

    pub fn uploadLayerInfoBlocks(self: *PreparedResources, layer_info_blocks: anytype, out_views: anytype) !void {
        var row_base = self.nextLayerInfoRowBase();
        for (layer_info_blocks, 0..) |block, i| {
            out_views[i] = .{ .info_row_base = row_base };
            if (block.data) |data| {
                if (self.layer_info_count >= self.layer_infos.len) return error.PreparedResourceCapacityExceeded;
                const prepared_layers = try preparePathLayerInfoRecords(self.allocator, data, block.width, block.height, block.paint_image_records);
                self.layer_infos[self.layer_info_count] = .{
                    .data = data,
                    .width = block.width,
                    .height = block.height,
                    .row_base = row_base,
                    .path_records = prepared_layers.records,
                    .path_layers = prepared_layers.layers,
                    .paint_image_records = block.paint_image_records,
                };
                self.layer_info_count += 1;
            }
            row_base += block.height;
        }
    }

    pub fn uploadImages(_: *PreparedResources, images: []const *const snail.Image, out_views: anytype) void {
        for (out_views, images) |*v, img| {
            v.* = .{ .image = img };
        }
    }

    fn nextLayerInfoRowBase(self: *const PreparedResources) u32 {
        var row_base: u32 = 0;
        for (self.layer_infos[0..self.layer_info_count]) |entry| {
            row_base = @max(row_base, entry.row_base + entry.height);
        }
        return row_base;
    }

    fn storeAtlasPages(self: *PreparedResources, atlas: *const CurveAtlas, layer_base: u32, info_row_base: u32) !void {
        for (0..atlas.pageCount()) |i| {
            const layer = layer_base + @as(u32, @intCast(i));
            if (layer >= self.atlas_pages.len) return error.PreparedResourceCapacityExceeded;
            self.atlas_pages[layer] = try PreparedAtlasPage.init(self.allocator, atlas.page(@intCast(i)));
        }
        if (atlas.layer_info_data) |lid| {
            if (self.layer_info_count >= self.layer_infos.len) return error.PreparedResourceCapacityExceeded;
            const prepared_layers = try preparePathLayerInfoRecords(self.allocator, lid, atlas.layer_info_width, atlas.layer_info_height, atlas.paint_image_records);
            self.layer_infos[self.layer_info_count] = .{
                .data = lid,
                .width = atlas.layer_info_width,
                .height = atlas.layer_info_height,
                .row_base = info_row_base,
                .path_records = prepared_layers.records,
                .path_layers = prepared_layers.layers,
                .paint_image_records = atlas.paint_image_records,
            };
            self.layer_info_count += 1;
        }
    }

    /// Resolve a global (info_x, info_y) into data pointer, width, and
    /// the source atlas's image-paint records, adjusting info_y for the
    /// atlas's row_base.
    pub fn resolveLayerInfo(self: *const PreparedResources, info_y: u16) ?ResolvedLayerInfo {
        for (self.layer_infos[0..self.layer_info_count]) |*entry| {
            if (info_y >= entry.row_base and info_y < entry.row_base + entry.height) {
                return .{
                    .entry = entry,
                    .local_y = @intCast(info_y - entry.row_base),
                };
            }
        }
        return null;
    }
};
