const snail = @import("../../root.zig");

const bezier = snail.lowlevel.bezier;
const curve_tex = snail.lowlevel.curve_tex;
const CurveSegment = bezier.CurveSegment;
const Vec2 = snail.Vec2;

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
    const ref = readBandTexelLinear(page, texel_idx);
    if (ref[0] >= page.curve_width or ref[1] >= page.curve_height) return null;
    return @as(usize, (ref[1] * page.curve_width + ref[0]) * 4);
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

pub fn decodeCurveSegmentFromSlice(curve_data_f32: []const f32, curve_base: u32) CurveSegment {
    const base: usize = @intCast(curve_base);
    const tex0 = readCurveTexelF32Slice(curve_data_f32, base);
    const tex1 = readCurveTexelF32Slice(curve_data_f32, base + 4);
    const tex2 = readCurveTexelF32Slice(curve_data_f32, base + 8);
    const meta = readCurveTexelF32Slice(curve_data_f32, base + 12);
    return decodeCurveSegment(tex0, tex1, tex2, meta);
}

pub fn isDirectEncodedCurveKind(stored_kind: f32) bool {
    return stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5;
}

pub fn curveKindFromStoredKind(stored_kind: f32) bezier.CurveKind {
    const kind_u16: u16 = @intCast(if (isDirectEncodedCurveKind(stored_kind))
        @as(i32, @intFromFloat(@round(stored_kind - curve_tex.DIRECT_ENCODING_KIND_BIAS)))
    else
        @as(i32, @intFromFloat(@round(stored_kind))));
    return switch (kind_u16) {
        1 => .conic,
        2 => .cubic,
        3 => .line,
        else => .quadratic,
    };
}

pub fn decodeCurveSegment(tex0: [4]f32, tex1: [4]f32, tex2: [4]f32, meta: [4]f32) CurveSegment {
    const stored_kind = tex2[2];
    const kind = curveKindFromStoredKind(stored_kind);
    if (isDirectEncodedCurveKind(stored_kind)) {
        return .{
            .kind = kind,
            .p0 = .{ .x = tex0[0], .y = tex0[1] },
            .p1 = .{ .x = tex0[2], .y = tex0[3] },
            .p2 = .{ .x = tex1[0], .y = tex1[1] },
            .p3 = .{ .x = tex1[2], .y = tex1[3] },
            .weights = .{ tex2[3], meta[0], meta[1] },
        };
    }

    const p0 = curve_tex.decodePackedAnchor(
        .{ .x = tex0[0], .y = tex0[1] },
        .{ .x = tex0[2], .y = tex0[3] },
    );
    return .{
        .kind = kind,
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
