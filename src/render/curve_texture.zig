const std = @import("std");
const bezier_mod = @import("../math/bezier.zig");
const CurveSegment = bezier_mod.CurveSegment;
const BBox = bezier_mod.BBox;
const Vec2 = @import("../math/vec.zig").Vec2;

pub const TEX_WIDTH: u32 = 4096;
pub const SEGMENT_TEXELS: u32 = 4;
pub const PACKED_ANCHOR_CHUNK_EXTENT: f32 = 256.0;
pub const PACKED_POINT_DELTA_LIMIT: f32 = 256.0;
pub const PACKED_BAND_DILATION: f32 = 1.0;
pub const DIRECT_ENCODING_KIND_BIAS: f32 = 4.0;
const PACKED_CURVE_MAX_SPLIT_DEPTH: u8 = 24;

/// Convert f32 to IEEE 754 binary16 (half-float).
pub fn f32ToF16(val: f32) u16 {
    const bits: u32 = @bitCast(val);
    const sign: u16 = @intCast((bits >> 16) & 0x8000);
    const exp_val = @as(i32, @intCast((bits >> 23) & 0xFF)) - 127;
    const mantissa = bits & 0x7FFFFF;

    if (exp_val >= 16) {
        // Overflow → infinity
        return sign | 0x7C00;
    } else if (exp_val >= -14) {
        // Normal
        const e: u16 = @intCast(exp_val + 15);
        const m: u16 = @intCast(mantissa >> 13);
        return sign | (e << 10) | m;
    } else if (exp_val >= -24) {
        // Subnormal
        const shift: u5 = @intCast(-exp_val - 14 + 10);
        const m: u16 = @intCast((mantissa | 0x800000) >> shift);
        return sign | m;
    } else {
        return sign; // zero
    }
}

const PackedAnchor = struct {
    chunk: Vec2,
    frac: Vec2,
};

fn encodePackedAnchor(point: Vec2) PackedAnchor {
    const chunk_x_i: i32 = @intFromFloat(@round(point.x / PACKED_ANCHOR_CHUNK_EXTENT));
    const chunk_y_i: i32 = @intFromFloat(@round(point.y / PACKED_ANCHOR_CHUNK_EXTENT));
    const chunk = Vec2.new(@floatFromInt(chunk_x_i), @floatFromInt(chunk_y_i));
    return .{
        .chunk = chunk,
        .frac = Vec2.new(
            point.x - chunk.x * PACKED_ANCHOR_CHUNK_EXTENT,
            point.y - chunk.y * PACKED_ANCHOR_CHUNK_EXTENT,
        ),
    };
}

pub fn decodePackedAnchor(chunk: Vec2, frac: Vec2) Vec2 {
    return Vec2.new(
        chunk.x * PACKED_ANCHOR_CHUNK_EXTENT + frac.x,
        chunk.y * PACKED_ANCHOR_CHUNK_EXTENT + frac.y,
    );
}

fn pointFitsPackedRange(anchor: Vec2, point: Vec2) bool {
    const delta = Vec2.sub(point, anchor);
    return @abs(delta.x) <= PACKED_POINT_DELTA_LIMIT and @abs(delta.y) <= PACKED_POINT_DELTA_LIMIT;
}

pub fn curveFitsPackedRange(curve: CurveSegment) bool {
    if (!pointFitsPackedRange(curve.p0, curve.p1)) return false;
    if (!pointFitsPackedRange(curve.p0, curve.p2)) return false;
    if (curve.kind == .cubic and !pointFitsPackedRange(curve.p0, curve.p3)) return false;
    return true;
}

fn appendCurveForPacking(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: CurveSegment,
    depth: u8,
) !void {
    if (curveFitsPackedRange(curve) or depth == 0) {
        try out.append(allocator, curve);
        return;
    }

    const halves = curve.split(0.5);
    try appendCurveForPacking(allocator, out, halves[0], depth - 1);
    try appendCurveForPacking(allocator, out, halves[1], depth - 1);
}

pub fn splitCurvesForPacking(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
) ![]CurveSegment {
    var out: std.ArrayList(CurveSegment) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, curves.len);
    for (curves) |curve| try appendCurveForPacking(allocator, &out, curve, PACKED_CURVE_MAX_SPLIT_DEPTH);
    return out.toOwnedSlice(allocator);
}

/// Curve texture: RGBA16F (half-float).
/// Each segment occupies 4 texels:
///   packed texel 0: (anchor_chunk.x, anchor_chunk.y, anchor_frac.x, anchor_frac.y)
///   packed texel 1: (p1.x - p0.x, p1.y - p0.y, p2.x - p0.x, p2.y - p0.y)
///   packed texel 2: (p3.x - p0.x, p3.y - p0.y, kind, w0)
///   packed texel 3: (w1, w2, 0, 0)
///   direct texel 0: (p0.x, p0.y, p1.x, p1.y)
///   direct texel 1: (p2.x, p2.y, p3.x, p3.y)
///   direct texel 2: (0, 0, kind + DIRECT_ENCODING_KIND_BIAS, w0)
///   direct texel 3: (w1, w2, 0, 0)
pub const CurveTexture = struct {
    data: []u16,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CurveTexture) void {
        self.allocator.free(self.data);
    }
};

pub const GlyphCurveEntry = struct {
    start_x: u16,
    start_y: u16,
    count: u16,
    offset: u32,
};

pub fn buildCurveTexture(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphCurves,
) !struct { texture: CurveTexture, entries: []GlyphCurveEntry } {
    var total_texels: u32 = 0;
    for (glyphs) |g| total_texels += @as(u32, @intCast(g.curves.len)) * SEGMENT_TEXELS;

    const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
    const total = TEX_WIDTH * height;

    var data = try allocator.alloc(u16, total * 4);
    @memset(data, 0);

    var entries = try allocator.alloc(GlyphCurveEntry, glyphs.len);
    var texel_idx: u32 = 0;

    for (glyphs, 0..) |g, gi| {
        const tx = texel_idx % TEX_WIDTH;
        const ty = texel_idx / TEX_WIDTH;
        entries[gi] = .{
            .start_x = @intCast(tx),
            .start_y = @intCast(ty),
            .count = @intCast(g.curves.len),
            .offset = texel_idx,
        };
        if (g.prefer_direct_encoding) {
            const prepared_curves = try prepareGlyphCurvesForDirectEncoding(allocator, g.curves, g.origin);
            defer allocator.free(prepared_curves);

            for (prepared_curves) |quantized_curve| {
                const base = texel_idx * 4;
                data[base + 0] = f32ToF16(quantized_curve.p0.x);
                data[base + 1] = f32ToF16(quantized_curve.p0.y);
                data[base + 2] = f32ToF16(quantized_curve.p1.x);
                data[base + 3] = f32ToF16(quantized_curve.p1.y);
                data[base + 4] = f32ToF16(quantized_curve.p2.x);
                data[base + 5] = f32ToF16(quantized_curve.p2.y);
                data[base + 6] = f32ToF16(quantized_curve.p3.x);
                data[base + 7] = f32ToF16(quantized_curve.p3.y);
                data[base + 8] = 0;
                data[base + 9] = 0;
                data[base + 10] = f32ToF16(DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(@intFromEnum(quantized_curve.kind))));
                data[base + 11] = f32ToF16(quantized_curve.weights[0]);
                data[base + 12] = f32ToF16(quantized_curve.weights[1]);
                data[base + 13] = f32ToF16(quantized_curve.weights[2]);
                texel_idx += SEGMENT_TEXELS;
            }
        } else {
            const prepared_curves = try prepareGlyphCurvesForPacking(allocator, g.curves, g.origin);
            defer allocator.free(prepared_curves);

            for (prepared_curves) |curve| {
                const base = texel_idx * 4;
                const p0 = curve.p0;
                const p1 = curve.p1;
                const p2 = curve.p2;
                const p3 = curve.p3;
                const anchor = encodePackedAnchor(p0);
                const p1_rel = Vec2.sub(p1, p0);
                const p2_rel = Vec2.sub(p2, p0);
                const p3_rel = if (curve.kind == .cubic) Vec2.sub(p3, p0) else Vec2.zero;
                data[base + 0] = f32ToF16(anchor.chunk.x);
                data[base + 1] = f32ToF16(anchor.chunk.y);
                data[base + 2] = f32ToF16(anchor.frac.x);
                data[base + 3] = f32ToF16(anchor.frac.y);
                data[base + 4] = f32ToF16(p1_rel.x);
                data[base + 5] = f32ToF16(p1_rel.y);
                data[base + 6] = f32ToF16(p2_rel.x);
                data[base + 7] = f32ToF16(p2_rel.y);
                data[base + 8] = f32ToF16(p3_rel.x);
                data[base + 9] = f32ToF16(p3_rel.y);
                data[base + 10] = f32ToF16(@floatFromInt(@intFromEnum(curve.kind)));
                data[base + 11] = f32ToF16(curve.weights[0]);
                data[base + 12] = f32ToF16(curve.weights[1]);
                data[base + 13] = f32ToF16(curve.weights[2]);
                texel_idx += SEGMENT_TEXELS;
            }
        }
    }

    return .{
        .texture = .{
            .data = data,
            .width = TEX_WIDTH,
            .height = height,
            .allocator = allocator,
        },
        .entries = entries,
    };
}

pub const GlyphCurves = struct {
    curves: []const CurveSegment,
    bbox: BBox,
    origin: Vec2 = .zero,
    logical_curve_count: usize = 0,
    prefer_direct_encoding: bool = false,
};

fn f16BitsToF32(val: u16) f32 {
    return @as(f32, @floatCast(@as(f16, @bitCast(val))));
}

fn quantizeF16(val: f32) f32 {
    return f16BitsToF32(f32ToF16(val));
}

fn quantizeVec2F16(v: Vec2) Vec2 {
    return .{
        .x = quantizeF16(v.x),
        .y = quantizeF16(v.y),
    };
}

fn pointsApproxEqual(a: Vec2, b: Vec2) bool {
    return @abs(a.x - b.x) <= 1e-4 and @abs(a.y - b.y) <= 1e-4;
}

fn quantizedAnchorPoint(point: Vec2) Vec2 {
    const anchor = encodePackedAnchor(point);
    return decodePackedAnchor(
        quantizeVec2F16(anchor.chunk),
        quantizeVec2F16(anchor.frac),
    );
}

fn quantizedPreparedLocalCurve(curve: CurveSegment, start_override: ?Vec2) CurveSegment {
    const p0 = start_override orelse quantizedAnchorPoint(curve.p0);
    const p1_rel = quantizeVec2F16(Vec2.sub(curve.p1, p0));
    const p2_rel = quantizeVec2F16(Vec2.sub(curve.p2, p0));
    const p3_rel = if (curve.kind == .cubic) quantizeVec2F16(Vec2.sub(curve.p3, p0)) else Vec2.zero;

    return .{
        .kind = curve.kind,
        .p0 = p0,
        .p1 = Vec2.add(p0, p1_rel),
        .p2 = Vec2.add(p0, p2_rel),
        .p3 = Vec2.add(p0, p3_rel),
        .weights = .{
            quantizeF16(curve.weights[0]),
            quantizeF16(curve.weights[1]),
            quantizeF16(curve.weights[2]),
        },
    };
}

pub fn quantizedLocalCurve(curve: CurveSegment, origin: Vec2) CurveSegment {
    const delta = Vec2.new(-origin.x, -origin.y);
    const local_curve = CurveSegment{
        .kind = curve.kind,
        .p0 = Vec2.add(curve.p0, delta),
        .p1 = Vec2.add(curve.p1, delta),
        .p2 = Vec2.add(curve.p2, delta),
        .p3 = if (curve.kind == .cubic) Vec2.add(curve.p3, delta) else curve.p3,
        .weights = curve.weights,
    };
    return quantizedPreparedLocalCurve(local_curve, null);
}

fn quantizedPreparedDirectLocalCurve(curve: CurveSegment, start_override: ?Vec2) CurveSegment {
    const p0 = start_override orelse quantizeVec2F16(curve.p0);
    return .{
        .kind = curve.kind,
        .p0 = p0,
        .p1 = quantizeVec2F16(curve.p1),
        .p2 = quantizeVec2F16(curve.p2),
        .p3 = if (curve.kind == .cubic) quantizeVec2F16(curve.p3) else Vec2.zero,
        .weights = .{
            quantizeF16(curve.weights[0]),
            quantizeF16(curve.weights[1]),
            quantizeF16(curve.weights[2]),
        },
    };
}

fn localizedCurve(curve: CurveSegment, delta: Vec2) CurveSegment {
    return .{
        .kind = curve.kind,
        .p0 = Vec2.add(curve.p0, delta),
        .p1 = Vec2.add(curve.p1, delta),
        .p2 = Vec2.add(curve.p2, delta),
        .p3 = if (curve.kind == .cubic) Vec2.add(curve.p3, delta) else curve.p3,
        .weights = curve.weights,
    };
}

fn snapCurveEndpoint(curve: CurveSegment, point: Vec2) CurveSegment {
    var snapped = curve;
    switch (curve.kind) {
        .cubic => snapped.p3 = point,
        .quadratic, .conic, .line => snapped.p2 = point,
    }
    return snapped;
}

const PreparedCurveMode = enum {
    packing,
    direct,
};

fn quantizePreparedCurve(curve: CurveSegment, start_override: ?Vec2, comptime mode: PreparedCurveMode) CurveSegment {
    return switch (mode) {
        .packing => quantizedPreparedLocalCurve(curve, start_override),
        .direct => quantizedPreparedDirectLocalCurve(curve, start_override),
    };
}

fn prepareGlyphCurves(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
    comptime mode: PreparedCurveMode,
) ![]CurveSegment {
    const out = try allocator.alloc(CurveSegment, curves.len);
    errdefer allocator.free(out);

    const delta = Vec2.new(-origin.x, -origin.y);
    var contour_start: usize = 0;
    while (contour_start < curves.len) {
        var contour_end = contour_start + 1;
        while (contour_end < curves.len and pointsApproxEqual(curves[contour_end - 1].endPoint(), curves[contour_end].p0)) {
            contour_end += 1;
        }

        var prev_original_end: ?Vec2 = null;
        var prev_quantized_end: ?Vec2 = null;
        for (curves[contour_start..contour_end], out[contour_start..contour_end]) |curve, *dst| {
            const local_curve = localizedCurve(curve, delta);
            const start_override = if (prev_original_end) |prev_end|
                if (pointsApproxEqual(local_curve.p0, prev_end)) prev_quantized_end else null
            else
                null;
            dst.* = quantizePreparedCurve(local_curve, start_override, mode);
            prev_original_end = local_curve.endPoint();
            prev_quantized_end = dst.endPoint();
        }

        const first_local = localizedCurve(curves[contour_start], delta);
        const last_local = localizedCurve(curves[contour_end - 1], delta);
        if (pointsApproxEqual(first_local.p0, last_local.endPoint())) {
            out[contour_end - 1] = snapCurveEndpoint(out[contour_end - 1], out[contour_start].p0);
        }

        contour_start = contour_end;
    }

    return out;
}

pub fn prepareGlyphCurvesForPacking(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
) ![]CurveSegment {
    return prepareGlyphCurves(allocator, curves, origin, .packing);
}

pub fn prepareGlyphCurvesForDirectEncoding(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
) ![]CurveSegment {
    return prepareGlyphCurves(allocator, curves, origin, .direct);
}

fn decodeStoredSegment(data: []const u16) CurveSegment {
    const stored_kind = f16BitsToF32(data[10]);
    const kind_u16: u16 = @intCast(if (stored_kind >= DIRECT_ENCODING_KIND_BIAS - 0.5)
        @as(i32, @intFromFloat(@round(stored_kind - DIRECT_ENCODING_KIND_BIAS)))
    else
        @as(i32, @intFromFloat(@round(stored_kind))));
    const kind: bezier_mod.CurveKind = switch (kind_u16) {
        1 => .conic,
        2 => .cubic,
        3 => .line,
        else => .quadratic,
    };
    if (stored_kind >= DIRECT_ENCODING_KIND_BIAS - 0.5) {
        return .{
            .kind = kind,
            .p0 = Vec2.new(f16BitsToF32(data[0]), f16BitsToF32(data[1])),
            .p1 = Vec2.new(f16BitsToF32(data[2]), f16BitsToF32(data[3])),
            .p2 = Vec2.new(f16BitsToF32(data[4]), f16BitsToF32(data[5])),
            .p3 = Vec2.new(f16BitsToF32(data[6]), f16BitsToF32(data[7])),
            .weights = .{
                f16BitsToF32(data[11]),
                f16BitsToF32(data[12]),
                f16BitsToF32(data[13]),
            },
        };
    }

    const anchor = decodePackedAnchor(
        Vec2.new(f16BitsToF32(data[0]), f16BitsToF32(data[1])),
        Vec2.new(f16BitsToF32(data[2]), f16BitsToF32(data[3])),
    );
    const p1_rel = Vec2.new(f16BitsToF32(data[4]), f16BitsToF32(data[5]));
    const p2_rel = Vec2.new(f16BitsToF32(data[6]), f16BitsToF32(data[7]));
    const p3_rel = Vec2.new(f16BitsToF32(data[8]), f16BitsToF32(data[9]));
    return .{
        .kind = kind,
        .p0 = anchor,
        .p1 = Vec2.add(anchor, p1_rel),
        .p2 = Vec2.add(anchor, p2_rel),
        .p3 = Vec2.add(anchor, p3_rel),
        .weights = .{
            f16BitsToF32(data[11]),
            f16BitsToF32(data[12]),
            f16BitsToF32(data[13]),
        },
    };
}

test "f32ToF16 basic conversions" {
    // Zero
    try std.testing.expectEqual(@as(u16, 0), f32ToF16(0.0));
    // One
    try std.testing.expectEqual(@as(u16, 0x3C00), f32ToF16(1.0));
    // Half
    try std.testing.expectEqual(@as(u16, 0x3800), f32ToF16(0.5));
    // Negative
    try std.testing.expectEqual(@as(u16, 0xBC00), f32ToF16(-1.0));
}

test "buildCurveTexture packs FP16" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0, 0),
            .p1 = Vec2.new(0.5, 1),
            .p2 = Vec2.new(1, 0),
        },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{ .min = Vec2.new(0, 0), .max = Vec2.new(1, 1) },
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    try std.testing.expectEqual(@as(u16, 1), result.entries[0].count);
    // Zero chunk and zero fractional anchor.
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[0]);
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[1]);
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[2]);
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[3]);
    // p1 = (0.5, 1.0), p2 = (1.0, 0.0) relative to p0
    try std.testing.expectEqual(@as(u16, 0x3800), result.texture.data[4]);
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[5]);
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[6]);
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[7]);
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[11]); // w0 = 1
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[12]); // w1 = 1
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[13]); // w2 = 1
}

test "buildCurveTexture rebases coordinates by glyph origin" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(640, 960),
            .p1 = Vec2.new(660, 960),
            .p2 = Vec2.new(680, 960),
        },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{ .min = Vec2.new(0, 0), .max = Vec2.new(40, 10) },
        .origin = Vec2.new(640, 960),
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    try std.testing.expectApproxEqAbs(0.0, decoded.p0.x, 0.001);
    try std.testing.expectApproxEqAbs(0.0, decoded.p0.y, 0.001);
    try std.testing.expectApproxEqAbs(20.0, decoded.p1.x, 0.001);
    try std.testing.expectApproxEqAbs(0.0, decoded.p1.y, 0.001);
    try std.testing.expectApproxEqAbs(40.0, decoded.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(0.0, decoded.p2.y, 0.001);
}

test "buildCurveTexture reconstructs large anchors and local deltas" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(200057, -179941),
            .p1 = Vec2.new(200093, -179905),
            .p2 = Vec2.new(200121, -179877),
        },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = curves[0].boundingBox(),
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    try std.testing.expectApproxEqAbs(curves[0].p0.x, decoded.p0.x, 0.13);
    try std.testing.expectApproxEqAbs(curves[0].p0.y, decoded.p0.y, 0.13);
    try std.testing.expectApproxEqAbs(curves[0].p1.x, decoded.p1.x, 0.13);
    try std.testing.expectApproxEqAbs(curves[0].p1.y, decoded.p1.y, 0.13);
    try std.testing.expectApproxEqAbs(curves[0].p2.x, decoded.p2.x, 0.13);
    try std.testing.expectApproxEqAbs(curves[0].p2.y, decoded.p2.y, 0.13);
}

test "quantizedLocalCurve matches packed decode" {
    const curve = CurveSegment{
        .kind = .quadratic,
        .p0 = Vec2.new(200057, -179941),
        .p1 = Vec2.new(200093, -179905),
        .p2 = Vec2.new(200121, -179877),
    };
    const glyph = GlyphCurves{
        .curves = &.{curve},
        .bbox = curve.boundingBox(),
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    const quantized = quantizedLocalCurve(curve, .zero);

    try std.testing.expectApproxEqAbs(decoded.p0.x, quantized.p0.x, 0.001);
    try std.testing.expectApproxEqAbs(decoded.p0.y, quantized.p0.y, 0.001);
    try std.testing.expectApproxEqAbs(decoded.p1.x, quantized.p1.x, 0.001);
    try std.testing.expectApproxEqAbs(decoded.p1.y, quantized.p1.y, 0.001);
    try std.testing.expectApproxEqAbs(decoded.p2.x, quantized.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(decoded.p2.y, quantized.p2.y, 0.001);
}

test "prepareGlyphCurvesForPacking keeps adjacent joins identical" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0.0, 10.2),
            .p1 = Vec2.new(48.3, 10.2),
            .p2 = Vec2.new(96.6, 10.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(96.6, 10.2),
            .p1 = Vec2.new(144.9, 10.2),
            .p2 = Vec2.new(193.2, 10.2),
        },
    };

    const prepared = try prepareGlyphCurvesForPacking(std.testing.allocator, &curves, .zero);
    defer std.testing.allocator.free(prepared);

    try std.testing.expectApproxEqAbs(prepared[0].endPoint().x, prepared[1].p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(prepared[0].endPoint().y, prepared[1].p0.y, 0.0001);
}

test "prepareGlyphCurvesForPacking keeps closed contour wrap identical" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0.3, 10.2),
            .p1 = Vec2.new(48.6, 22.7),
            .p2 = Vec2.new(96.9, 10.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(96.9, 10.2),
            .p1 = Vec2.new(48.6, -2.1),
            .p2 = Vec2.new(0.3, 10.2),
        },
    };

    const prepared = try prepareGlyphCurvesForPacking(std.testing.allocator, &curves, .zero);
    defer std.testing.allocator.free(prepared);

    try std.testing.expectApproxEqAbs(prepared[prepared.len - 1].endPoint().x, prepared[0].p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(prepared[prepared.len - 1].endPoint().y, prepared[0].p0.y, 0.0001);
}

test "prepareGlyphCurvesForDirectEncoding keeps adjacent joins identical" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0.0, 10.2),
            .p1 = Vec2.new(48.3, 10.2),
            .p2 = Vec2.new(96.6, 10.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(96.6, 10.2),
            .p1 = Vec2.new(144.9, 10.2),
            .p2 = Vec2.new(193.2, 10.2),
        },
    };

    const prepared = try prepareGlyphCurvesForDirectEncoding(std.testing.allocator, &curves, .zero);
    defer std.testing.allocator.free(prepared);

    try std.testing.expectApproxEqAbs(prepared[0].endPoint().x, prepared[1].p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(prepared[0].endPoint().y, prepared[1].p0.y, 0.0001);
}

test "prepareGlyphCurvesForDirectEncoding keeps closed contour wrap identical" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1000.3, 2010.2),
            .p1 = Vec2.new(1048.6, 2022.7),
            .p2 = Vec2.new(1096.9, 2010.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1096.9, 2010.2),
            .p1 = Vec2.new(1048.6, 1997.9),
            .p2 = Vec2.new(1000.3, 2010.2),
        },
    };

    const prepared = try prepareGlyphCurvesForDirectEncoding(std.testing.allocator, &curves, .zero);
    defer std.testing.allocator.free(prepared);

    try std.testing.expectApproxEqAbs(prepared[prepared.len - 1].endPoint().x, prepared[0].p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(prepared[prepared.len - 1].endPoint().y, prepared[0].p0.y, 0.0001);
}

test "buildCurveTexture supports direct encoding for font glyphs" {
    const curve = CurveSegment{
        .kind = .quadratic,
        .p0 = Vec2.new(10.25, 20.5),
        .p1 = Vec2.new(10.75, 21.0),
        .p2 = Vec2.new(11.0, 20.25),
    };
    const glyph = GlyphCurves{
        .curves = &.{curve},
        .bbox = curve.boundingBox(),
        .origin = Vec2.new(10.0, 20.0),
        .prefer_direct_encoding = true,
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    try std.testing.expectEqual(f32ToF16(DIRECT_ENCODING_KIND_BIAS), result.texture.data[10]);

    const decoded = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(0.25)), decoded.p0.x, 0.001);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(0.5)), decoded.p0.y, 0.001);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(0.75)), decoded.p1.x, 0.001);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(1.0)), decoded.p1.y, 0.001);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(1.0)), decoded.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(f16BitsToF32(f32ToF16(0.25)), decoded.p2.y, 0.001);
}

test "buildCurveTexture direct encoding preserves adjacent joins" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1000.3, 2000.2),
            .p1 = Vec2.new(1048.6, 2000.2),
            .p2 = Vec2.new(1096.9, 2000.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1096.9, 2000.2),
            .p1 = Vec2.new(1145.2, 2000.2),
            .p2 = Vec2.new(1193.5, 2000.2),
        },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{
            .min = Vec2.new(1000.3, 2000.2),
            .max = Vec2.new(1193.5, 2000.2),
        },
        .origin = Vec2.new(1000.0, 2000.0),
        .prefer_direct_encoding = true,
    };

    var result = try buildCurveTexture(std.testing.allocator, &.{glyph});
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const first = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    const second = decodeStoredSegment(result.texture.data[SEGMENT_TEXELS * 4 .. SEGMENT_TEXELS * 8]);
    try std.testing.expectApproxEqAbs(first.endPoint().x, second.p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(first.endPoint().y, second.p0.y, 0.0001);
}

test "buildCurveTexture preserves closed contour wrap" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0.3, 10.2),
            .p1 = Vec2.new(48.6, 22.7),
            .p2 = Vec2.new(96.9, 10.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(96.9, 10.2),
            .p1 = Vec2.new(48.6, -2.1),
            .p2 = Vec2.new(0.3, 10.2),
        },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{
            .min = Vec2.new(0.3, -2.1),
            .max = Vec2.new(96.9, 22.7),
        },
        .origin = Vec2.new(48.6, 10.2),
        .prefer_direct_encoding = true,
    };

    var result = try buildCurveTexture(std.testing.allocator, &.{glyph});
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const first = decodeStoredSegment(result.texture.data[0 .. SEGMENT_TEXELS * 4]);
    const second = decodeStoredSegment(result.texture.data[SEGMENT_TEXELS * 4 .. SEGMENT_TEXELS * 8]);
    try std.testing.expectApproxEqAbs(second.endPoint().x, first.p0.x, 0.0001);
    try std.testing.expectApproxEqAbs(second.endPoint().y, first.p0.y, 0.0001);
}

test "splitCurvesForPacking bounds per-segment control deltas" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0, 0),
            .p1 = Vec2.new(2048, 256),
            .p2 = Vec2.new(4096, 0),
        },
    };

    const packable_curves = try splitCurvesForPacking(std.testing.allocator, &curves);
    defer std.testing.allocator.free(packable_curves);

    try std.testing.expect(packable_curves.len > curves.len);
    for (packable_curves) |curve| {
        try std.testing.expect(curveFitsPackedRange(curve));
    }
}
