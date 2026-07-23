//! Atlas texture decoding for the software rasterizer.

const std = @import("std");
const snail = @import("snail");

const bezier = @import("snail").render.geometry;
const curve_tex = @import("snail").render.geometry;
const CurveSegment = bezier.CurveSegment;
const band_curve_loc_x_bits = 12;
const band_curve_loc_x_mask: u32 = (1 << band_curve_loc_x_bits) - 1;
// ref.y bits 0..13 are curve_loc_y; bits 14..15 are the curve kind (see
// format/band_texture.zig::packBandCurveRef). The CPU coverage path
// reads kind directly off the curve segment, so we only need to mask
// the kind bits out of curve_loc_y here.
const band_curve_loc_y_bits = 14;
const band_curve_loc_y_mask: u32 = (1 << band_curve_loc_y_bits) - 1;

pub const BandCurveRef = struct {
    base: usize,
    first_member_band: u32,
};

// ---------------------------------------------------------------------------
// Texture access helpers
// ---------------------------------------------------------------------------

pub fn readBandTexelLinear(page: anytype, texel_idx: usize) [2]u32 {
    const idx = texel_idx * 2;
    if (idx + 1 >= page.band_data.len) return .{ 0, 0 };
    return .{
        @as(u32, page.band_data[idx]),
        @as(u32, page.band_data[idx + 1]),
    };
}

pub fn readBandCurveBase(page: anytype, texel_idx: usize) ?usize {
    return (readBandCurveRef(page, texel_idx) orelse return null).base;
}

pub fn readBandFirstMember(page: anytype, texel_idx: usize) u32 {
    const raw = readBandTexelLinear(page, texel_idx);
    return raw[0] >> band_curve_loc_x_bits;
}

pub fn readBandCurveRef(page: anytype, texel_idx: usize) ?BandCurveRef {
    const raw = readBandTexelLinear(page, texel_idx);
    const curve_x = raw[0] & band_curve_loc_x_mask;
    const curve_y = raw[1] & band_curve_loc_y_mask;
    if (curve_x >= page.curve_width or curve_y >= page.curve_height) return null;
    return .{
        .base = @as(usize, (curve_y * page.curve_width + curve_x) * 4),
        .first_member_band = raw[0] >> band_curve_loc_x_bits,
    };
}

pub fn readCurveTexelF32Base(page: anytype, idx: usize) [4]f32 {
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "curve_data_f32")) {
        if (idx + 3 >= page.curve_data_f32.len) return .{ 0, 0, 0, 0 };
        return .{
            page.curve_data_f32[idx + 0],
            page.curve_data_f32[idx + 1],
            page.curve_data_f32[idx + 2],
            page.curve_data_f32[idx + 3],
        };
    } else {
        if (idx + 3 >= page.curve_data.len) return .{ 0, 0, 0, 0 };
        return .{
            f16ToF32(page.curve_data[idx + 0]),
            f16ToF32(page.curve_data[idx + 1]),
            f16ToF32(page.curve_data[idx + 2]),
            f16ToF32(page.curve_data[idx + 3]),
        };
    }
}

pub fn readCurveTexelF32Slice(data: []const f32, idx: usize) [4]f32 {
    if (idx + 3 >= data.len) return .{ 0, 0, 0, 0 };
    return .{
        data[idx + 0],
        data[idx + 1],
        data[idx + 2],
        data[idx + 3],
    };
}

pub fn decodeCurveSegmentFromSlice(curve_data_f32: []const f32, curve_base: u32) ?CurveSegment {
    const base: usize = @intCast(curve_base);
    const tex0 = readCurveTexelF32Slice(curve_data_f32, base);
    const tex1 = readCurveTexelF32Slice(curve_data_f32, base + 4);
    const tex2 = readCurveTexelF32Slice(curve_data_f32, base + 8);
    const meta = readCurveTexelF32Slice(curve_data_f32, base + 12);
    return decodeCurveSegment(tex0, tex1, tex2, meta);
}

pub const CurveEncoding = struct {
    kind: bezier.CurveKind,
    direct: bool,
};

pub fn curveEncodingFromStoredKind(stored_kind: f32) ?CurveEncoding {
    return if (stored_kind == 0) .{ .kind = .quadratic, .direct = false } else if (stored_kind == 1) .{ .kind = .conic, .direct = false } else if (stored_kind == 2) .{ .kind = .cubic, .direct = false } else if (stored_kind == 3) .{ .kind = .line, .direct = false } else if (stored_kind == curve_tex.DIRECT_ENCODING_KIND_BIAS) .{ .kind = .quadratic, .direct = true } else if (stored_kind == curve_tex.DIRECT_ENCODING_KIND_BIAS + 1) .{ .kind = .conic, .direct = true } else if (stored_kind == curve_tex.DIRECT_ENCODING_KIND_BIAS + 2) .{ .kind = .cubic, .direct = true } else if (stored_kind == curve_tex.DIRECT_ENCODING_KIND_BIAS + 3) .{ .kind = .line, .direct = true } else null;
}

pub fn decodeCurveSegment(tex0: [4]f32, tex1: [4]f32, tex2: [4]f32, meta: [4]f32) ?CurveSegment {
    const encoding = curveEncodingFromStoredKind(tex2[2]) orelse return null;
    if (encoding.direct) {
        return .{
            .kind = encoding.kind,
            .p0 = .{ .x = tex0[0], .y = tex0[1] },
            .p1 = .{ .x = tex0[2], .y = tex0[3] },
            .p2 = .{ .x = tex1[0], .y = tex1[1] },
            .p3 = .{ .x = tex1[2], .y = tex1[3] },
            .weights = .{ tex2[3], tex2[0], tex2[1] },
        };
    }

    const p0 = curve_tex.decodePackedAnchor(
        .{ .x = tex0[0], .y = tex0[1] },
        .{ .x = tex0[2], .y = tex0[3] },
    );
    return .{
        .kind = encoding.kind,
        .p0 = p0,
        .p1 = .{ .x = p0.x + tex1[0], .y = p0.y + tex1[1] },
        .p2 = .{ .x = p0.x + tex1[2], .y = p0.y + tex1[3] },
        .p3 = .{ .x = p0.x + tex2[0], .y = p0.y + tex2[1] },
        .weights = .{ tex2[3], meta[0], meta[1] },
    };
}

pub fn f16ToF32(h: u16) f32 {
    return @floatCast(@as(f16, @bitCast(h)));
}

test "curve kind decoding accepts only canonical stored values" {
    const kinds = [_]bezier.CurveKind{ .quadratic, .conic, .cubic, .line };
    for (kinds, 0..) |kind, raw| {
        const packed_encoding = curveEncodingFromStoredKind(@floatFromInt(raw)).?;
        try std.testing.expectEqual(kind, packed_encoding.kind);
        try std.testing.expect(!packed_encoding.direct);
        const direct = curveEncodingFromStoredKind(curve_tex.DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(raw))).?;
        try std.testing.expectEqual(kind, direct.kind);
        try std.testing.expect(direct.direct);
    }
    for ([_]f32{ 3.5, 7.5, 8, 65504, std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32) }) |raw| {
        try std.testing.expectEqual(@as(?CurveEncoding, null), curveEncodingFromStoredKind(raw));
        try std.testing.expectEqual(@as(?CurveSegment, null), decodeCurveSegment(
            .{ 0, 0, 0, 0 },
            .{ 0, 0, 0, 0 },
            .{ 0, 0, raw, 0 },
            .{ 0, 0, 0, 0 },
        ));
    }
}
