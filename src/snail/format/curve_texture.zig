const std = @import("std");
const render_abi = @import("abi.zig");
const bezier_mod = @import("../math/bezier.zig");
const CurveSegment = bezier_mod.CurveSegment;
const BBox = bezier_mod.BBox;
const Vec2 = @import("../math/vec.zig").Vec2;

pub const TEX_WIDTH: u32 = render_abi.atlas_tex_width;
pub const GENERAL_SEGMENT_TEXELS: u32 = 4;

/// Physical curve-record encoding, carried by the band block's prefix.
///
/// `general`: four texels per segment, carrying kind and conic weights.
///
/// `dense_quadratic`: line/quadratic records chained per contour. Kind lives
/// in every band reference and weights are unit, so a segment needs only
/// p0, p1, and p2. Segment i reads texel t = (p0, p1) and texel t + 1, whose
/// first two channels are its p2. When the next segment starts at that p2
/// (bit-exact after f16 quantization), texel t + 1 is also that segment's
/// first texel, (p2 = next p0, next p1): a closed contour of n segments
/// takes n + 1 texels. A chain ends with (p2, DENSE_CHAIN_END,
/// DENSE_CHAIN_END), which makes the layout self-describing.
pub const Encoding = enum(u8) {
    general,
    dense_quadratic,

    pub fn isDenseQuadratic(self: Encoding) bool {
        return self == .dense_quadratic;
    }
};

/// f16 quiet NaN in the unused channels of a dense chain's closing texel.
/// Encoded coordinates are always finite, so it never collides with p1.
pub const DENSE_CHAIN_END: u16 = 0x7e00;

/// Whether `next` continues `prev`'s dense chain: its start equals `prev`'s
/// end once both are quantized to f16.
pub fn denseJoins(prev: CurveSegment, next: CurveSegment) bool {
    return f32ToF16(prev.p2.x) == f32ToF16(next.p0.x) and
        f32ToF16(prev.p2.y) == f32ToF16(next.p0.y);
}

/// Texel offset of each segment of a dense record (written to `out`, one per
/// segment), returning the record's texel count.
pub fn denseSegmentTexels(prepared: []const CurveSegment, out: []u32) u32 {
    std.debug.assert(out.len >= prepared.len);
    if (prepared.len == 0) return 0;
    var texel: u32 = 0;
    for (prepared, 0..) |curve, i| {
        // A break skips past the previous chain's closing texel.
        if (i > 0 and !denseJoins(prepared[i - 1], curve)) texel += 1;
        out[i] = texel;
        texel += 1;
    }
    return texel + 1;
}

/// Texel count of a dense record for `prepared`.
pub fn denseTexelCount(prepared: []const CurveSegment) usize {
    if (prepared.len == 0) return 0;
    var chains: usize = 1;
    for (prepared[1..], prepared[0 .. prepared.len - 1]) |curve, prev| {
        if (!denseJoins(prev, curve)) chains += 1;
    }
    return prepared.len + chains;
}

pub fn isDenseChainEnd(words: []const u16, texel: usize) bool {
    return words[texel * 4 + 2] == DENSE_CHAIN_END and words[texel * 4 + 3] == DENSE_CHAIN_END;
}

/// Whether `texel` starts a segment of the dense record `words`: every texel
/// except a chain's closing one does.
pub fn isDenseSegmentStart(words: []const u16, texel: usize) bool {
    return texel < words.len / 4 and !isDenseChainEnd(words, texel);
}

/// Segment count of a dense record recovered from its chain ends, or null
/// if `words` is not a well-formed dense record (a trailing open chain, or
/// an empty one).
pub fn denseSegmentCount(words: []const u16) ?usize {
    if (words.len % 4 != 0) return null;
    var segments: usize = 0;
    var chain_open = false;
    for (0..words.len / 4) |texel| {
        if (isDenseChainEnd(words, texel)) {
            if (!chain_open) return null;
            chain_open = false;
        } else {
            segments += 1;
            chain_open = true;
        }
    }
    return if (chain_open) null else segments;
}
pub const PACKED_ANCHOR_CHUNK_EXTENT: f32 = 256.0;
pub const PACKED_POINT_DELTA_LIMIT: f32 = 256.0;
pub const PACKED_BAND_DILATION: f32 = 1.0;
pub const DIRECT_ENCODING_KIND_BIAS: f32 = 4.0;
const PACKED_CURVE_MAX_SPLIT_DEPTH: u8 = 24;
// Leave one integer of headroom for rounding before the f32 -> i32 anchor
// conversion. Finite values outside this range are not representable by the
// packed texture format and must be rejected before `@intFromFloat`.
const PACKED_ANCHOR_COORDINATE_LIMIT: f32 =
    @as(f32, @floatFromInt(std.math.maxInt(i32) - 1024)) * PACKED_ANCHOR_CHUNK_EXTENT;

fn pointIsFinite(point: Vec2) bool {
    return std.math.isFinite(point.x) and std.math.isFinite(point.y) and
        @abs(point.x) <= PACKED_ANCHOR_COORDINATE_LIMIT and
        @abs(point.y) <= PACKED_ANCHOR_COORDINATE_LIMIT;
}

fn curveIsFinite(curve: CurveSegment) bool {
    if (!pointIsFinite(curve.p0) or !pointIsFinite(curve.p1) or
        !pointIsFinite(curve.p2) or !pointIsFinite(curve.p3))
    {
        return false;
    }
    for (curve.weights) |weight| {
        if (!std.math.isFinite(weight)) return false;
    }
    if (curve.kind == .conic) {
        for (curve.weights) |weight| {
            if (weight <= 0) return false;
        }
    }
    return true;
}

pub fn validateCurveData(curves: []const CurveSegment, origin: Vec2) error{InvalidCurveData}!void {
    if (!pointIsFinite(origin)) return error.InvalidCurveData;
    for (curves) |curve| {
        if (!curveIsFinite(curve)) return error.InvalidCurveData;
    }
}

/// Convert f32 to IEEE 754 binary16 (half-float). Uses Zig's f16
/// type which the backend lowers to F16C `vcvtps2ph` on x86 and to
/// the equivalent FCVT on ARM — both are single-instruction.
pub fn f32ToF16(val: f32) u16 {
    return @bitCast(@as(f16, @floatCast(val)));
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
    try validateCurveData(curves, .zero);
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
///   direct texel 2: (w1, w2, kind + DIRECT_ENCODING_KIND_BIAS, w0)
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
    encoding: Encoding = .general,
};

/// Builds persistent curve texture data plus scratch glyph entries.
/// `texture.data` is owned by `data_allocator`; `entries` is owned by
/// `scratch_allocator` and is only needed while building dependent metadata.
/// Precomputed f16 values for `DIRECT_ENCODING_KIND_BIAS + kind`. The
/// kind enum has at most 4 values; precompute the f16 at comptime to
/// skip a per-write float-to-f16 conversion.
const direct_kind_f16: [4]u16 = blk: {
    var out: [4]u16 = undefined;
    for (0..4) |i| {
        out[i] = @bitCast(@as(f16, @floatCast(DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(i)))));
    }
    break :blk out;
};

/// Write one curve into the direct-encoding texel block. `data` must
/// be at least `GENERAL_SEGMENT_TEXELS * 4` u16s; only those words are touched.
pub fn writeDirectCurveTexels(data: []u16, curve: CurveSegment) void {
    // Cache the f16'd weights once — the encoding repeats weights[1] and
    // weights[2] (slots 8/9 and 12/13) so otherwise we'd do four
    // duplicate conversions.
    const w0 = f32ToF16(curve.weights[0]);
    const w1 = f32ToF16(curve.weights[1]);
    const w2 = f32ToF16(curve.weights[2]);
    data[0] = f32ToF16(curve.p0.x);
    data[1] = f32ToF16(curve.p0.y);
    data[2] = f32ToF16(curve.p1.x);
    data[3] = f32ToF16(curve.p1.y);
    data[4] = f32ToF16(curve.p2.x);
    data[5] = f32ToF16(curve.p2.y);
    data[6] = f32ToF16(curve.p3.x);
    data[7] = f32ToF16(curve.p3.y);
    data[8] = w1;
    data[9] = w2;
    data[10] = direct_kind_f16[@intFromEnum(curve.kind)];
    data[11] = w0;
    data[12] = w1;
    data[13] = w2;
    data[14] = 0;
    data[15] = 0;
}

/// Allocate and direct-encode a single glyph's prepared curves into a
/// `prepared.len * GENERAL_SEGMENT_TEXELS * 4` u16 buffer. Skips the
/// `buildCurveTexture` TEX_WIDTH-row padding — for single-glyph callers
/// (`font.extractCurves`, TT-hinted snapshots), the padding is pure waste.
pub fn encodeDirectSingleGlyphCurves(
    allocator: std.mem.Allocator,
    prepared: []const CurveSegment,
) ![]u16 {
    try validateCurveData(prepared, .zero);
    for (prepared) |curve| {
        if (!curveFitsDirectF16(curve)) return error.InvalidCurveData;
    }
    const words_per_segment: usize = GENERAL_SEGMENT_TEXELS * 4;
    const total_words = std.math.mul(usize, prepared.len, words_per_segment) catch
        return error.ShapeTooComplex;
    const buf = try allocator.alloc(u16, total_words);
    var cursor: usize = 0;
    for (prepared) |curve| {
        writeDirectCurveTexels(buf[cursor..][0..words_per_segment], curve);
        cursor += words_per_segment;
    }
    return buf;
}

/// Encode a line/quadratic-only glyph as chained dense texels (see
/// `Encoding.dense_quadratic`). Coordinates are byte-identical to the
/// general direct encoding. Kind comes from the band reference; weights are
/// unit. Band references locate segments with `denseSegmentTexels`.
pub fn encodeDenseQuadraticSingleGlyphCurves(
    allocator: std.mem.Allocator,
    prepared: []const CurveSegment,
    /// When the caller has already validated `prepared` in this pipeline,
    /// skip the redundant finiteness pre-pass. The per-curve
    /// `curveFitsDirectF16` gate below still rejects non-finite and
    /// out-of-f16-range control points, so encoding stays safe.
    trusted: bool,
) ![]u16 {
    if (!trusted) try validateCurveData(prepared, .zero);
    for (prepared) |curve| {
        if ((curve.kind != .line and curve.kind != .quadratic) or
            !curveFitsDirectF16(curve))
        {
            return error.InvalidCurveData;
        }
    }
    const total_words = std.math.mul(usize, denseTexelCount(prepared), 4) catch
        return error.ShapeTooComplex;
    const buf = try allocator.alloc(u16, total_words);
    errdefer allocator.free(buf);
    var cursor: usize = 0;
    var chain_open = false;
    for (prepared, 0..) |curve, i| {
        if (!chain_open) {
            writeDenseTexel(buf[cursor..][0..4], curve.p0, f32ToF16(curve.p1.x), f32ToF16(curve.p1.y));
            cursor += 4;
        }
        // The texel holding p2 doubles as the next segment's first texel
        // when that segment starts there; otherwise it closes the chain.
        chain_open = i + 1 < prepared.len and denseJoins(curve, prepared[i + 1]);
        if (chain_open) {
            const next_p1 = prepared[i + 1].p1;
            writeDenseTexel(buf[cursor..][0..4], curve.p2, f32ToF16(next_p1.x), f32ToF16(next_p1.y));
        } else {
            writeDenseTexel(buf[cursor..][0..4], curve.p2, DENSE_CHAIN_END, DENSE_CHAIN_END);
        }
        cursor += 4;
    }
    std.debug.assert(cursor == total_words);
    return buf;
}

fn writeDenseTexel(out: *[4]u16, point: Vec2, z: u16, w: u16) void {
    out.* = .{ f32ToF16(point.x), f32ToF16(point.y), z, w };
}

pub fn buildCurveTexture(
    data_allocator: std.mem.Allocator,
    scratch_allocator: std.mem.Allocator,
    glyphs: []const GlyphCurves,
) !struct { texture: CurveTexture, entries: []GlyphCurveEntry } {
    var total_texels: u32 = 0;
    for (glyphs) |g| {
        try validateCurveData(g.curves, g.origin);
        if (g.prepared_curves) |prepared| try validateCurveData(prepared, .zero);
        const curve_count = if (g.prepared_curves) |prepared| prepared.len else g.curves.len;
        const count_u16 = std.math.cast(u16, curve_count) orelse return error.ShapeTooComplex;
        const glyph_texels = std.math.mul(u32, count_u16, GENERAL_SEGMENT_TEXELS) catch return error.ShapeTooComplex;
        total_texels = std.math.add(u32, total_texels, glyph_texels) catch return error.ShapeTooComplex;
    }

    const rounded_texels = std.math.add(u32, total_texels, TEX_WIDTH - 1) catch return error.ShapeTooComplex;
    const height = @max(1, rounded_texels / TEX_WIDTH);
    if (height > (@as(u32, 1) << 14)) return error.ShapeTooComplex;
    const total = std.math.mul(u32, TEX_WIDTH, height) catch return error.ShapeTooComplex;
    const total_words = std.math.mul(usize, total, 4) catch return error.ShapeTooComplex;

    var data = try data_allocator.alloc(u16, total_words);
    errdefer data_allocator.free(data);
    @memset(data, 0);

    var entries = try scratch_allocator.alloc(GlyphCurveEntry, glyphs.len);
    errdefer scratch_allocator.free(entries);
    var texel_idx: u32 = 0;

    for (glyphs, 0..) |g, gi| {
        const tx = texel_idx % TEX_WIDTH;
        const ty = texel_idx / TEX_WIDTH;
        entries[gi] = .{
            .start_x = @intCast(tx),
            .start_y = @intCast(ty),
            .count = @intCast(if (g.prepared_curves) |prepared| prepared.len else g.curves.len),
            .offset = texel_idx,
        };
        if (g.prefer_direct_encoding) {
            var owned_prepared_curves: ?[]CurveSegment = null;
            const prepared_curves = if (g.prepared_curves) |prepared| prepared else blk: {
                const prepared = try prepareGlyphCurvesForDirectEncoding(scratch_allocator, g.curves, g.origin);
                owned_prepared_curves = prepared;
                break :blk prepared;
            };
            defer if (owned_prepared_curves) |prepared| scratch_allocator.free(prepared);

            for (prepared_curves) |quantized_curve| {
                if (!curveFitsDirectF16(quantized_curve)) return error.InvalidCurveData;
                const base = texel_idx * 4;
                data[base + 0] = f32ToF16(quantized_curve.p0.x);
                data[base + 1] = f32ToF16(quantized_curve.p0.y);
                data[base + 2] = f32ToF16(quantized_curve.p1.x);
                data[base + 3] = f32ToF16(quantized_curve.p1.y);
                data[base + 4] = f32ToF16(quantized_curve.p2.x);
                data[base + 5] = f32ToF16(quantized_curve.p2.y);
                data[base + 6] = f32ToF16(quantized_curve.p3.x);
                data[base + 7] = f32ToF16(quantized_curve.p3.y);
                data[base + 8] = f32ToF16(quantized_curve.weights[1]);
                data[base + 9] = f32ToF16(quantized_curve.weights[2]);
                data[base + 10] = f32ToF16(DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(@intFromEnum(quantized_curve.kind))));
                data[base + 11] = f32ToF16(quantized_curve.weights[0]);
                data[base + 12] = f32ToF16(quantized_curve.weights[1]);
                data[base + 13] = f32ToF16(quantized_curve.weights[2]);
                texel_idx += GENERAL_SEGMENT_TEXELS;
            }
        } else {
            var owned_prepared_curves: ?[]CurveSegment = null;
            const prepared_curves = if (g.prepared_curves) |prepared| prepared else blk: {
                const prepared = try prepareGlyphCurvesForPacking(scratch_allocator, g.curves, g.origin);
                owned_prepared_curves = prepared;
                break :blk prepared;
            };
            defer if (owned_prepared_curves) |prepared| scratch_allocator.free(prepared);

            for (prepared_curves) |curve| {
                if (!curveFitsPackedF16(curve)) return error.InvalidCurveData;
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
                texel_idx += GENERAL_SEGMENT_TEXELS;
            }
        }
    }

    return .{
        .texture = .{
            .data = data,
            .width = TEX_WIDTH,
            .height = height,
            .allocator = data_allocator,
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
    /// Optional caller-owned curves already localized and quantized for the
    /// selected encoding mode. Builders only read this slice.
    prepared_curves: ?[]const CurveSegment = null,
};

fn f16BitsToF32(val: u16) f32 {
    return @as(f32, @floatCast(@as(f16, @bitCast(val))));
}

fn quantizeF16(val: f32) f32 {
    return f16BitsToF32(f32ToF16(val));
}

fn fitsF16(value: f32) bool {
    return std.math.isFinite(value) and @abs(value) <= @as(f32, std.math.floatMax(f16));
}

fn curveFitsDirectF16(curve: CurveSegment) bool {
    const points = [_]Vec2{ curve.p0, curve.p1, curve.p2, curve.p3 };
    for (points) |point| {
        if (!fitsF16(point.x) or !fitsF16(point.y)) return false;
    }
    for (curve.weights) |weight| {
        if (!fitsF16(weight)) return false;
    }
    return true;
}

fn curveFitsPackedF16(curve: CurveSegment) bool {
    const anchor = encodePackedAnchor(curve.p0);
    const vectors = [_]Vec2{
        anchor.chunk,
        anchor.frac,
        Vec2.sub(curve.p1, curve.p0),
        Vec2.sub(curve.p2, curve.p0),
        if (curve.kind == .cubic) Vec2.sub(curve.p3, curve.p0) else .zero,
    };
    for (vectors) |vector| {
        if (!fitsF16(vector.x) or !fitsF16(vector.y)) return false;
    }
    for (curve.weights) |weight| {
        if (!fitsF16(weight)) return false;
    }
    return true;
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
    var p1_rel = quantizeVec2F16(Vec2.sub(curve.p1, p0));
    var p2_rel = quantizeVec2F16(Vec2.sub(curve.p2, p0));
    const p3_rel = if (curve.kind == .cubic) quantizeVec2F16(Vec2.sub(curve.p3, p0)) else Vec2.zero;

    // Preserve bit-exact zero start/end tangents through quantization.
    // Without this, start_override's quantized p0 can differ from raw p0 by
    // an ULP and turn an exact shared tangent into a tiny nonzero one.
    if (curve.p1.x == curve.p0.x) p1_rel.x = 0;
    if (curve.p1.y == curve.p0.y) p1_rel.y = 0;
    if (curve.kind == .cubic) {
        if (curve.p2.x == curve.p3.x) p2_rel.x = p3_rel.x;
        if (curve.p2.y == curve.p3.y) p2_rel.y = p3_rel.y;
    } else {
        if (curve.p1.x == curve.p2.x) p1_rel.x = p2_rel.x;
        if (curve.p1.y == curve.p2.y) p1_rel.y = p2_rel.y;
    }

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
    var p1 = quantizeVec2F16(curve.p1);
    var p2 = quantizeVec2F16(curve.p2);
    const p3 = if (curve.kind == .cubic) quantizeVec2F16(curve.p3) else Vec2.zero;

    // See quantizedPreparedLocalCurve: preserve bit-exact zero tangents.
    if (curve.p1.x == curve.p0.x) p1.x = p0.x;
    if (curve.p1.y == curve.p0.y) p1.y = p0.y;
    if (curve.kind == .cubic) {
        if (curve.p2.x == curve.p3.x) p2.x = p3.x;
        if (curve.p2.y == curve.p3.y) p2.y = p3.y;
    } else {
        if (curve.p1.x == curve.p2.x) p1.x = p2.x;
        if (curve.p1.y == curve.p2.y) p1.y = p2.y;
    }

    return .{
        .kind = curve.kind,
        .p0 = p0,
        .p1 = p1,
        .p2 = p2,
        .p3 = p3,
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
    bboxes_out: ?[]bezier_mod.BBox,
) ![]CurveSegment {
    try validateCurveData(curves, origin);
    if (bboxes_out) |bo| {
        if (bo.len != curves.len) return error.InvalidOutputBufferSize;
    }
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
            const representable = switch (mode) {
                .packing => curveFitsPackedF16(local_curve),
                .direct => curveFitsDirectF16(local_curve),
            };
            if (!representable) return error.InvalidCurveData;
            const start_override = if (prev_original_end) |prev_end|
                if (pointsApproxEqual(local_curve.p0, prev_end)) prev_quantized_end else null
            else
                null;
            dst.* = quantizePreparedCurve(local_curve, start_override, mode);
            if (!curveIsFinite(dst.*)) return error.InvalidCurveData;
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

    // Cache per-curve analytic bboxes if the caller wants them. Downstream
    // (mergeBBoxWithCurves + collectPreparedCurveMetrics) would otherwise
    // recompute these twice per curve. One pass here amortises both.
    if (bboxes_out) |bo| {
        for (out, bo) |c, *b| b.* = c.boundingBox();
    }

    return out;
}

pub fn prepareGlyphCurvesForPacking(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
) ![]CurveSegment {
    return prepareGlyphCurves(allocator, curves, origin, .packing, null);
}

pub fn prepareGlyphCurvesForDirectEncoding(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
) ![]CurveSegment {
    return prepareGlyphCurves(allocator, curves, origin, .direct, null);
}

/// Like `prepareGlyphCurvesForDirectEncoding`, but also writes each
/// prepared curve's analytic bbox into `bboxes_out` (must match
/// `curves.len`). Callers that need both can pre-allocate `bboxes_out`
/// in scratch and avoid recomputing in downstream passes.
pub fn prepareGlyphCurvesForDirectEncodingWithBBoxes(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    origin: Vec2,
    bboxes_out: []bezier_mod.BBox,
) ![]CurveSegment {
    return prepareGlyphCurves(allocator, curves, origin, .direct, bboxes_out);
}

pub fn decodeSegmentAt(data: []const u16, curve_texel: u32) ?CurveSegment {
    const index = std.math.mul(usize, curve_texel, 4) catch return null;
    const segment_words: usize = GENERAL_SEGMENT_TEXELS * 4;
    const end = std.math.add(usize, index, segment_words) catch return null;
    if (end > data.len) return null;
    const stored = data[index..end];
    for (stored) |bits| {
        if (!std.math.isFinite(f16BitsToF32(bits))) return null;
    }
    const stored_kind = f16BitsToF32(stored[10]);
    const rounded_kind = @round(stored_kind);
    if (stored_kind != rounded_kind or
        !((rounded_kind >= 0 and rounded_kind <= 3) or
            (rounded_kind >= DIRECT_ENCODING_KIND_BIAS and rounded_kind <= DIRECT_ENCODING_KIND_BIAS + 3)))
    {
        return null;
    }
    const decoded = decodeStoredSegment(stored);
    if (!curveIsFinite(decoded)) return null;
    return decoded;
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
                f16BitsToF32(data[8]),
                f16BitsToF32(data[9]),
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
    try std.testing.expectEqual(@as(u16, 0), f32ToF16(0.0));
    try std.testing.expectEqual(@as(u16, 0x3C00), f32ToF16(1.0));
    try std.testing.expectEqual(@as(u16, 0x3800), f32ToF16(0.5));
    try std.testing.expectEqual(@as(u16, 0xBC00), f32ToF16(-1.0));
}

test "decodeSegmentAt rejects malformed half-float payloads" {
    var words = [_]u16{0} ** (GENERAL_SEGMENT_TEXELS * 4);
    try std.testing.expect(decodeSegmentAt(&words, 0) != null);

    words[0] = @bitCast(std.math.nan(f16));
    try std.testing.expectEqual(@as(?CurveSegment, null), decodeSegmentAt(&words, 0));
    words[0] = 0;

    words[10] = f32ToF16(9);
    try std.testing.expectEqual(@as(?CurveSegment, null), decodeSegmentAt(&words, 0));
    try std.testing.expectEqual(@as(?CurveSegment, null), decodeSegmentAt(&words, std.math.maxInt(u32)));
}

test "curve preparation rejects non-finite producer data before packing" {
    var curve = CurveSegment.fromLine(.zero, .{ .x = 1, .y = 1 });
    curve.p1.x = std.math.nan(f32);

    try std.testing.expectError(
        error.InvalidCurveData,
        prepareGlyphCurvesForPacking(std.testing.allocator, &.{curve}, .zero),
    );
    try std.testing.expectError(
        error.InvalidCurveData,
        splitCurvesForPacking(std.testing.allocator, &.{curve}),
    );
    try std.testing.expectError(
        error.InvalidCurveData,
        encodeDirectSingleGlyphCurves(std.testing.allocator, &.{curve}),
    );

    const valid = CurveSegment.fromLine(.zero, .{ .x = 1, .y = 1 });
    var wrong_size: [0]BBox = .{};
    try std.testing.expectError(
        error.InvalidOutputBufferSize,
        prepareGlyphCurvesForDirectEncodingWithBBoxes(std.testing.allocator, &.{valid}, .zero, &wrong_size),
    );

    const outside_f16 = CurveSegment.fromLine(.{ .x = 70_000, .y = 0 }, .{ .x = 70_001, .y = 1 });
    try std.testing.expectError(
        error.InvalidCurveData,
        prepareGlyphCurvesForDirectEncoding(std.testing.allocator, &.{outside_f16}, .zero),
    );
    try std.testing.expectError(
        error.InvalidCurveData,
        encodeDirectSingleGlyphCurves(std.testing.allocator, &.{outside_f16}),
    );

    const outside_anchor = CurveSegment.fromLine(.{ .x = 1.0e12, .y = 0 }, .{ .x = 1.0e12, .y = 1 });
    try std.testing.expectError(
        error.InvalidCurveData,
        prepareGlyphCurvesForPacking(std.testing.allocator, &.{outside_anchor}, .zero),
    );
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &glyphs);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const decoded = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
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

    try std.testing.expectEqual(prepared[0].endPoint().x, prepared[1].p0.x);
    try std.testing.expectEqual(prepared[0].endPoint().y, prepared[1].p0.y);
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

    try std.testing.expectEqual(prepared[prepared.len - 1].endPoint().x, prepared[0].p0.x);
    try std.testing.expectEqual(prepared[prepared.len - 1].endPoint().y, prepared[0].p0.y);
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

    try std.testing.expectEqual(prepared[0].endPoint().x, prepared[1].p0.x);
    try std.testing.expectEqual(prepared[0].endPoint().y, prepared[1].p0.y);
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

    try std.testing.expectEqual(prepared[prepared.len - 1].endPoint().x, prepared[0].p0.x);
    try std.testing.expectEqual(prepared[prepared.len - 1].endPoint().y, prepared[0].p0.y);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    try std.testing.expectEqual(f32ToF16(DIRECT_ENCODING_KIND_BIAS), result.texture.data[10]);

    const decoded = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &.{glyph});
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const first = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
    const second = decodeStoredSegment(result.texture.data[GENERAL_SEGMENT_TEXELS * 4 .. GENERAL_SEGMENT_TEXELS * 8]);
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

    var result = try buildCurveTexture(std.testing.allocator, std.testing.allocator, &.{glyph});
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    const first = decodeStoredSegment(result.texture.data[0 .. GENERAL_SEGMENT_TEXELS * 4]);
    const second = decodeStoredSegment(result.texture.data[GENERAL_SEGMENT_TEXELS * 4 .. GENERAL_SEGMENT_TEXELS * 8]);
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

fn testQuad(p0: [2]f32, p1: [2]f32, p2: [2]f32) CurveSegment {
    return CurveSegment.fromQuad(.{
        .p0 = .{ .x = p0[0], .y = p0[1] },
        .p1 = .{ .x = p1[0], .y = p1[1] },
        .p2 = .{ .x = p2[0], .y = p2[1] },
    });
}

test "dense encoding chains each contour through shared joints" {
    // Two closed contours: a triangle of quadratics, then a two-segment loop.
    const curves = [_]CurveSegment{
        testQuad(.{ 0, 0 }, .{ 0.5, -0.25 }, .{ 1, 0 }),
        testQuad(.{ 1, 0 }, .{ 0.75, 0.5 }, .{ 0.5, 1 }),
        testQuad(.{ 0.5, 1 }, .{ 0.25, 0.5 }, .{ 0, 0 }),
        testQuad(.{ 2, 2 }, .{ 2.5, 1.5 }, .{ 3, 2 }),
        testQuad(.{ 3, 2 }, .{ 2.5, 2.5 }, .{ 2, 2 }),
    };
    const words = try encodeDenseQuadraticSingleGlyphCurves(std.testing.allocator, &curves, false);
    defer std.testing.allocator.free(words);

    // n segments + one closing texel per contour.
    try std.testing.expectEqual(@as(usize, (curves.len + 2) * 4), words.len);
    try std.testing.expectEqual(@as(?usize, curves.len), denseSegmentCount(words));

    var texels: [curves.len]u32 = undefined;
    try std.testing.expectEqual(@as(u32, curves.len + 2), denseSegmentTexels(&curves, &texels));
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 4, 5 }, &texels);

    // Each segment reads (p0, p1) at its texel and p2 from the next one.
    for (curves, texels) |curve, t| {
        try std.testing.expect(isDenseSegmentStart(words, t));
        const w = words[t * 4 ..][0..6];
        try std.testing.expectEqualSlices(u16, &.{
            f32ToF16(curve.p0.x), f32ToF16(curve.p0.y),
            f32ToF16(curve.p1.x), f32ToF16(curve.p1.y),
            f32ToF16(curve.p2.x), f32ToF16(curve.p2.y),
        }, w);
    }
    // Chain ends are not segment starts.
    try std.testing.expect(!isDenseSegmentStart(words, 3));
    try std.testing.expect(!isDenseSegmentStart(words, 6));
    try std.testing.expect(!isDenseSegmentStart(words, 7));
}

test "dense segment count rejects open and empty chains" {
    const curves = [_]CurveSegment{testQuad(.{ 0, 0 }, .{ 0.5, 1 }, .{ 1, 0 })};
    const words = try encodeDenseQuadraticSingleGlyphCurves(std.testing.allocator, &curves, false);
    defer std.testing.allocator.free(words);
    try std.testing.expectEqual(@as(?usize, 1), denseSegmentCount(words));
    // Dropping the closing texel leaves the chain open.
    try std.testing.expectEqual(@as(?usize, null), denseSegmentCount(words[0..4]));
    // A chain end with no segment before it.
    try std.testing.expectEqual(@as(?usize, null), denseSegmentCount(words[4..8]));
}
