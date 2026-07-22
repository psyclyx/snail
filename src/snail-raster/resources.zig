//! Prepared resource views consumed by the software rasterizer.

const std = @import("std");
const coverage = @import("coverage.zig");
const path_paint = @import("path_paint.zig");
const texture = @import("texture.zig");

pub const LayerInfoEntry = path_paint.LayerInfoEntry;
const PreparedAxisCurve = coverage.PreparedAxisCurve;
const PreparedAxisCurveCold = coverage.PreparedAxisCurveCold;
const ResolvedLayerInfo = path_paint.ResolvedLayerInfo;
const readBandCurveRef = texture.readBandCurveRef;

const PreparePageError = std.mem.Allocator.Error || error{InvalidBandData};

const ReferenceRange = struct { first: usize, end: usize };
const BandBlock = struct {
    header_base: usize,
    h_band_count: usize,
    v_band_count: usize,
    end: usize,
};

// Physical band-block prefix from snail/format/band_texture.zig. The software
// module cannot import a source file already owned by the separately compiled
// `snail` module; its integration tests exercise the producer and this parser
// together so the private build-wired contract cannot drift silently.
const band_block_magic = [2]u16{ 0x534e, 0x4149 };
const band_block_prefix_texels: usize = 2;
const max_band_count: u16 = 16;

fn nextBandBlock(band_data: []const u16, cursor: *usize) error{InvalidBandData}!?BandBlock {
    const texel_count = band_data.len / 2;
    while (cursor.* < texel_count) : (cursor.* += 1) {
        if (texel_count - cursor.* < band_block_prefix_texels) return null;
        const prefix_word = cursor.* * 2;
        if (band_data[prefix_word] != band_block_magic[0] or
            band_data[prefix_word + 1] != band_block_magic[1])
        {
            // Discarded reservations are immutable zero padding. Searching
            // one texel at a time also permits a prefix to start at the last
            // column of a texture row.
            continue;
        }

        const h_count = band_data[prefix_word + 2];
        const v_count = band_data[prefix_word + 3];
        if (h_count == 0 or v_count == 0 or h_count > max_band_count or v_count > max_band_count) {
            return error.InvalidBandData;
        }
        const header_count = std.math.add(usize, h_count, v_count) catch return error.InvalidBandData;
        const header_base = std.math.add(usize, cursor.*, band_block_prefix_texels) catch return error.InvalidBandData;
        const header_end = std.math.add(usize, header_base, header_count) catch return error.InvalidBandData;
        if (header_end > texel_count) return error.InvalidBandData;

        // The producer packs reference lists contiguously. Requiring exact
        // offsets both computes the block extent and prevents a coincidental
        // magic pair in padding from becoming an arbitrary indexed walk.
        var expected_offset = header_count;
        for (0..header_count) |header_index| {
            const header_word = (header_base + header_index) * 2;
            const count: usize = band_data[header_word];
            const offset: usize = band_data[header_word + 1];
            if (offset != expected_offset) return error.InvalidBandData;
            expected_offset = std.math.add(usize, expected_offset, count) catch return error.InvalidBandData;
        }
        const block_end = std.math.add(usize, header_base, expected_offset) catch return error.InvalidBandData;
        if (block_end > texel_count) return error.InvalidBandData;
        cursor.* = block_end;
        return .{
            .header_base = header_base,
            .h_band_count = h_count,
            .v_band_count = v_count,
            .end = block_end,
        };
    }
    return null;
}

fn bandReferenceRange(
    band_data: []const u16,
    block_base: usize,
    header_count: usize,
    header_index: usize,
) error{InvalidBandData}!ReferenceRange {
    const texel_count = band_data.len / 2;
    const header_texel = std.math.add(usize, block_base, header_index) catch return error.InvalidBandData;
    if (header_texel >= texel_count) return error.InvalidBandData;
    const word = header_texel * 2;
    const reference_count: usize = band_data[word];
    const reference_offset: usize = band_data[word + 1];
    if (reference_offset < header_count) return error.InvalidBandData;
    const first = std.math.add(usize, block_base, reference_offset) catch return error.InvalidBandData;
    const end = std.math.add(usize, first, reference_count) catch return error.InvalidBandData;
    if (end > texel_count) return error.InvalidBandData;
    return .{ .first = first, .end = end };
}

fn decodeCurveSegmentFromWords(data: []const u16, base: usize) ?@import("snail").render.geometry.CurveSegment {
    const view = .{ .curve_data = data };
    return texture.decodeCurveSegment(
        texture.readCurveTexelF32Base(view, base),
        texture.readCurveTexelF32Base(view, base + 4),
        texture.readCurveTexelF32Base(view, base + 8),
        texture.readCurveTexelF32Base(view, base + 12),
    );
}

fn prepareBandHeader(
    allocator: std.mem.Allocator,
    page: anytype,
    block_base: usize,
    header_count: usize,
    header_index: usize,
    axis_band_count: usize,
    curves: []PreparedAxisCurve,
    cold_curves: *std.ArrayList(PreparedAxisCurveCold),
    comptime horizontal: bool,
) PreparePageError!void {
    const references = try bandReferenceRange(page.band_data, block_base, header_count, header_index);
    for (references.first..references.end) |texel_index| {
        // Multiple atlas snapshots can share one physical page. A sibling's
        // bytes may already be resident even though its descriptors have not
        // been seen yet, so fill every missing slot rather than assuming all
        // missing work lies past the prior byte watermark. Already valid
        // slots retain their cold indices and are never decoded twice.
        if (curves[texel_index].valid) continue;
        const curve_ref = readBandCurveRef(page, texel_index) orelse return error.InvalidBandData;
        if (curve_ref.first_member_band >= axis_band_count) return error.InvalidBandData;
        const curve_end = std.math.add(usize, curve_ref.base, 16) catch return error.InvalidBandData;
        if (curve_end > page.curve_data.len) return error.InvalidBandData;
        var prepared = try coverage.prepareAxisCurve(
            allocator,
            cold_curves,
            decodeCurveSegmentFromWords(page.curve_data, curve_ref.base) orelse return error.InvalidBandData,
            horizontal,
        );
        prepared.first_member_band = @intCast(curve_ref.first_member_band);
        curves[texel_index] = prepared;
    }
}

fn prepareBandBlocks(
    allocator: std.mem.Allocator,
    page: anytype,
    scan_from_texel: usize,
    /// One prepared coefficient record per physical reference texel. H and V
    /// lists occupy disjoint ranges in the packed block, so a single indexed
    /// array is sufficient; the record at each range is prepared for that
    /// range's axis.
    axis_curves: []PreparedAxisCurve,
    h_cold_curves: *std.ArrayList(PreparedAxisCurveCold),
    v_cold_curves: *std.ArrayList(PreparedAxisCurveCold),
) PreparePageError!void {
    if (page.band_data.len % 2 != 0) return error.InvalidBandData;
    var cursor = scan_from_texel;
    while (try nextBandBlock(page.band_data, &cursor)) |block| {
        const header_count = block.h_band_count + block.v_band_count;
        for (0..block.h_band_count) |header_index| {
            try prepareBandHeader(
                allocator,
                page,
                block.header_base,
                header_count,
                header_index,
                block.h_band_count,
                axis_curves,
                h_cold_curves,
                true,
            );
        }
        for (block.h_band_count..header_count) |header_index| {
            try prepareBandHeader(
                allocator,
                page,
                block.header_base,
                header_count,
                header_index,
                block.v_band_count,
                axis_curves,
                v_cold_curves,
                false,
            );
        }
    }
}

/// Per-page CPU-side rasterizer view of an atlas page.
///
/// Built from curve/band upload-region copies so the inner sampling loop has
/// direct, prepared arrays to walk without access to snail's opaque pages.
/// Lifecycle is the calling `DeviceAtlas`'s problem.
pub const PreparedAtlasPage = struct {
    curve_data: []const u16,
    band_data: []const u16,
    /// One axis-specific coefficient record per serialized curve-reference
    /// texel. Horizontal and vertical lists occupy disjoint physical ranges.
    axis_curves: []PreparedAxisCurve,
    h_cold_curves: []PreparedAxisCurveCold,
    v_cold_curves: []PreparedAxisCurveCold,
    curve_width: u32,
    curve_height: u32,
    band_width: u32,
    band_height: u32,

    /// Build a prepared page view from any struct exposing the page field
    /// shape (`curve_data`, `band_data`, plus per-texture width/height pairs).
    pub fn initFromView(allocator: std.mem.Allocator, page: anytype) !PreparedAtlasPage {
        return initFromViewImpl(allocator, page, false);
    }

    /// Build from newly allocated curve/band slices, taking ownership whether
    /// preparation succeeds or fails. This avoids a second full-page copy when
    /// a device cache has already assembled upload regions transactionally.
    pub fn initFromOwnedView(allocator: std.mem.Allocator, page: anytype) !PreparedAtlasPage {
        return initFromViewImpl(allocator, page, true);
    }

    fn initFromViewImpl(allocator: std.mem.Allocator, page: anytype, comptime take_ownership: bool) !PreparedAtlasPage {
        const curve_data = if (take_ownership) @constCast(page.curve_data) else try allocator.dupe(u16, page.curve_data);
        errdefer allocator.free(curve_data);

        const band_texel_count = page.band_data.len / 2;
        const band_data = if (take_ownership) @constCast(page.band_data) else try allocator.dupe(u16, page.band_data);
        errdefer allocator.free(band_data);
        const axis_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(axis_curves);
        @memset(axis_curves, .{});
        var h_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer h_cold_curves.deinit(allocator);
        var v_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer v_cold_curves.deinit(allocator);

        try prepareBandBlocks(allocator, page, 0, axis_curves, &h_cold_curves, &v_cold_curves);

        const h_cold_curves_owned = try h_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(h_cold_curves_owned);
        const v_cold_curves_owned = try v_cold_curves.toOwnedSlice(allocator);

        return .{
            .curve_data = curve_data,
            .band_data = band_data,
            .axis_curves = axis_curves,
            .h_cold_curves = h_cold_curves_owned,
            .v_cold_curves = v_cold_curves_owned,
            .curve_width = page.curve_width,
            .curve_height = page.curve_height,
            .band_width = page.band_width,
            .band_height = page.band_height,
        };
    }

    /// Prepare an append-only revision of a page without re-decoding the band
    /// entries that were already prepared. The returned page owns fresh
    /// storage, so allocation failure leaves `previous` untouched.
    pub fn initExtended(allocator: std.mem.Allocator, previous: *const PreparedAtlasPage, page: anytype) !PreparedAtlasPage {
        return initExtendedImpl(allocator, previous, page, false);
    }

    /// Append-only counterpart to `initFromOwnedView`; ownership of both input
    /// slices transfers on every return path.
    pub fn initExtendedFromOwnedView(allocator: std.mem.Allocator, previous: *const PreparedAtlasPage, page: anytype) !PreparedAtlasPage {
        return initExtendedImpl(allocator, previous, page, true);
    }

    fn initExtendedImpl(allocator: std.mem.Allocator, previous: *const PreparedAtlasPage, page: anytype, comptime take_ownership: bool) !PreparedAtlasPage {
        if (page.curve_width != previous.curve_width or
            page.band_width != previous.band_width or
            page.curve_data.len < previous.curve_data.len or
            page.band_data.len < previous.band_data.len)
        {
            return initFromViewImpl(allocator, page, take_ownership);
        }

        const curve_data = if (take_ownership) @constCast(page.curve_data) else try allocator.dupe(u16, page.curve_data);
        errdefer allocator.free(curve_data);
        const band_data = if (take_ownership) @constCast(page.band_data) else try allocator.dupe(u16, page.band_data);
        errdefer allocator.free(band_data);

        const band_texel_count = page.band_data.len / 2;
        const previous_texel_count = previous.band_data.len / 2;
        const axis_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(axis_curves);
        @memcpy(axis_curves[0..previous_texel_count], previous.axis_curves);
        @memset(axis_curves[previous_texel_count..], .{});

        var h_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer h_cold_curves.deinit(allocator);
        try h_cold_curves.appendSlice(allocator, previous.h_cold_curves);
        var v_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer v_cold_curves.deinit(allocator);
        try v_cold_curves.appendSlice(allocator, previous.v_cold_curves);

        try prepareBandBlocks(
            allocator,
            page,
            previous_texel_count,
            axis_curves,
            &h_cold_curves,
            &v_cold_curves,
        );

        const h_cold_owned = try h_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(h_cold_owned);
        const v_cold_owned = try v_cold_curves.toOwnedSlice(allocator);

        return .{
            .curve_data = curve_data,
            .band_data = band_data,
            .axis_curves = axis_curves,
            .h_cold_curves = h_cold_owned,
            .v_cold_curves = v_cold_owned,
            .curve_width = page.curve_width,
            .curve_height = page.curve_height,
            .band_width = page.band_width,
            .band_height = page.band_height,
        };
    }

    pub fn deinit(self: *PreparedAtlasPage, allocator: std.mem.Allocator) void {
        allocator.free(self.curve_data);
        allocator.free(self.band_data);
        allocator.free(self.axis_curves);
        allocator.free(self.h_cold_curves);
        allocator.free(self.v_cold_curves);
        self.* = undefined;
    }
};

/// Per-frame view the rasterizer reads from. `draw` builds one of these
/// for each segment from the segment's `DeviceAtlas` cache.
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

const TestPageView = struct {
    curve_data: []const u16,
    band_data: []const u16,
    curve_width: u32 = 4,
    curve_height: u32 = 4,
    band_width: u32 = 4,
    band_height: u32,
};

fn countValid(curves: []const PreparedAxisCurve) usize {
    var count: usize = 0;
    for (curves) |curve| count += @intFromBool(curve.valid);
    return count;
}

fn testBandBlock() [12]u16 {
    return .{
        band_block_magic[0], band_block_magic[1],
        1,                   1,
        1,                   2,
        1,                   3,
        0,                   0,
        0,                   0,
    };
}

test "prepared atlas ignores headers and prepares each reference for only its axis" {
    // Two headers followed by one H reference and one V reference. The
    // headers are deliberately also plausible curve coordinates; a flat
    // texel scan would incorrectly prepare them for both axes.
    const curve_data = [_]u16{0} ** 64;
    const band_data = testBandBlock();
    var prepared = try PreparedAtlasPage.initFromView(std.testing.allocator, TestPageView{
        .curve_data = &curve_data,
        .band_data = &band_data,
        .band_height = 2,
    });
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), countValid(prepared.axis_curves));
    for (0..4) |index| try std.testing.expect(!prepared.axis_curves[index].valid);
    try std.testing.expect(prepared.axis_curves[4].valid);
    try std.testing.expect(prepared.axis_curves[5].valid);
}

test "prepared atlas extension skips discard padding and retains cold coefficients" {
    var curve_data = [_]u16{0} ** 64;
    curve_data[10] = @bitCast(@as(f16, 1)); // packed conic: one cold record/axis
    const block = testBandBlock();
    const old_band_data = block ++ [_]u16{0} ** 4;
    const new_band_data = old_band_data ++ block;

    var previous = try PreparedAtlasPage.initFromView(std.testing.allocator, TestPageView{
        .curve_data = &curve_data,
        .band_data = &old_band_data,
        .band_height = 2,
    });
    defer previous.deinit(std.testing.allocator);
    var extended = try PreparedAtlasPage.initExtended(std.testing.allocator, &previous, TestPageView{
        .curve_data = &curve_data,
        .band_data = &new_band_data,
        .band_height = 4,
    });
    defer extended.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), countValid(extended.axis_curves));
    try std.testing.expect(extended.axis_curves[4].valid);
    try std.testing.expect(extended.axis_curves[5].valid);
    try std.testing.expect(extended.axis_curves[12].valid);
    try std.testing.expect(extended.axis_curves[13].valid);
    try std.testing.expectEqual(@as(usize, 2), extended.h_cold_curves.len);
    try std.testing.expectEqual(@as(usize, 2), extended.v_cold_curves.len);
}

test "prepared atlas rejects reference ranges that overlap headers" {
    const curve_data = [_]u16{0} ** 64;
    const band_data = [_]u16{
        band_block_magic[0], band_block_magic[1],
        1,                   1,
        1,                   0,
        1,                   1,
    };
    try std.testing.expectError(error.InvalidBandData, PreparedAtlasPage.initFromView(std.testing.allocator, TestPageView{
        .curve_data = &curve_data,
        .band_data = &band_data,
        .band_height = 1,
    }));
}

test "prepared atlas finds a prefix that straddles a texture row" {
    const curve_data = [_]u16{0} ** 64;
    const band_data = [_]u16{0} ** 6 ++ testBandBlock();
    var prepared = try PreparedAtlasPage.initFromView(std.testing.allocator, TestPageView{
        .curve_data = &curve_data,
        .band_data = &band_data,
        .band_height = 3,
    });
    defer prepared.deinit(std.testing.allocator);
    try std.testing.expect(prepared.axis_curves[7].valid);
    try std.testing.expect(prepared.axis_curves[8].valid);
}
