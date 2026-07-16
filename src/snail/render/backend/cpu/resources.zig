const std = @import("std");
const coverage = @import("coverage.zig");
const path_paint = @import("path_paint.zig");
const texture = @import("texture.zig");

pub const LayerInfoEntry = path_paint.LayerInfoEntry;
const PreparedAxisCurve = coverage.PreparedAxisCurve;
const PreparedAxisCurveCold = coverage.PreparedAxisCurveCold;
const ResolvedLayerInfo = path_paint.ResolvedLayerInfo;
const decodeCurveSegmentFromSlice = texture.decodeCurveSegmentFromSlice;
const f16ToF32 = texture.f16ToF32;
const readBandCurveRef = texture.readBandCurveRef;

/// Per-page CPU-side rasterizer view of an atlas page.
///
/// Built from the page's raw curve/band byte data so the inner sampling
/// loop has direct, prepared arrays to walk. Lifecycle is the calling
/// `CpuBackendCache`'s problem.
pub const PreparedAtlasPage = struct {
    curve_data: []const u16,
    band_data: []const u16,
    h_curves: []PreparedAxisCurve,
    v_curves: []PreparedAxisCurve,
    h_cold_curves: []PreparedAxisCurveCold,
    v_cold_curves: []PreparedAxisCurveCold,
    curve_width: u32,
    curve_height: u32,
    band_width: u32,
    band_height: u32,

    /// Build a prepared page view from any struct exposing the page field
    /// shape (`curve_data`, `band_data`, plus per-texture width/height pairs).
    pub fn initFromView(allocator: std.mem.Allocator, page: anytype) !PreparedAtlasPage {
        const curve_data = try allocator.dupe(u16, page.curve_data);
        errdefer allocator.free(curve_data);

        const curve_data_f32 = try allocator.alloc(f32, page.curve_data.len);
        defer allocator.free(curve_data_f32);
        for (page.curve_data, 0..) |value, i| {
            curve_data_f32[i] = f16ToF32(value);
        }
        const band_texel_count = page.band_data.len / 2;
        const band_data = try allocator.dupe(u16, page.band_data);
        errdefer allocator.free(band_data);
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
            const curve_ref = readBandCurveRef(page, texel_idx) orelse continue;
            const curve_base = curve_ref.base;
            const segment = decodeCurveSegmentFromSlice(curve_data_f32, @intCast(curve_base));

            h_curves[texel_idx] = try coverage.prepareAxisCurve(allocator, &h_cold_curves, segment, true);
            h_curves[texel_idx].first_member_band = @intCast(curve_ref.first_member_band);
            v_curves[texel_idx] = try coverage.prepareAxisCurve(allocator, &v_cold_curves, segment, false);
            v_curves[texel_idx].first_member_band = @intCast(curve_ref.first_member_band);
        }

        const h_cold_curves_owned = try h_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(h_cold_curves_owned);
        const v_cold_curves_owned = try v_cold_curves.toOwnedSlice(allocator);

        return .{
            .curve_data = curve_data,
            .band_data = band_data,
            .h_curves = h_curves,
            .v_curves = v_curves,
            .h_cold_curves = h_cold_curves_owned,
            .v_cold_curves = v_cold_curves_owned,
            .curve_width = page.curve_width,
            .curve_height = page.curve_height,
            .band_width = page.band_width,
            .band_height = page.band_height,
        };
    }

    pub fn deinit(self: *PreparedAtlasPage, allocator: std.mem.Allocator) void {
        allocator.free(self.curve_data);
        allocator.free(self.band_data);
        allocator.free(self.h_curves);
        allocator.free(self.v_curves);
        allocator.free(self.h_cold_curves);
        allocator.free(self.v_cold_curves);
        self.* = undefined;
    }
};

/// Per-frame view the rasterizer reads from. `drawCpu` builds one of these
/// for each segment from the segment's `CpuBackendCache` cache.
pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    atlas_pages: []?PreparedAtlasPage = &.{},
    layer_infos: []LayerInfoEntry = &.{},
    layer_info_count: usize = 0,

    /// Resolve a global (info_x, info_y) into the layer-info entry that owns
    /// it, plus a local row offset. Returns null when the row falls outside
    /// every entry's window.
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
