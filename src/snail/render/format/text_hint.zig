const std = @import("std");

const band_tex = @import("band_texture.zig");
const bezier = @import("../../math/bezier.zig");
const curve_tex = @import("curve_texture.zig");
const render_abi = @import("abi.zig");

pub const HintHandle = u16;
pub const no_hint: HintHandle = 0;

pub const DeltaEncoding = enum(u8) {
    /// Per-curve deltas matching the decoded base curve texture coordinates.
    curve_f16,
};

pub const GlyphFlags = packed struct(u16) {
    expanded_bands: bool = false,
    unordered_bands: bool = false,
    has_band_patch: bool = false,
    reserved: u13 = 0,

    pub fn bits(self: GlyphFlags) u16 {
        return @bitCast(self);
    }

    pub fn fromBits(bits_value: u16) GlyphFlags {
        return @bitCast(bits_value);
    }
};

pub const GlyphRecord = struct {
    base_curve_texel: u32 = 0,
    curve_count: u16 = 0,
    delta_offset: u32 = 0,
    band_offset: u32 = 0,
    h_band_pad: u16 = 0,
    v_band_pad: u16 = 0,
    flags: GlyphFlags = .{},
    band_entry: band_tex.GlyphBandEntry = .{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 0,
        .v_band_count = 0,
        .band_scale_x = 0,
        .band_scale_y = 0,
        .band_offset_x = 0,
        .band_offset_y = 0,
    },
    bbox: bezier.BBox = .{
        .min = .{ .x = 0, .y = 0 },
        .max = .{ .x = 0, .y = 0 },
    },
};

pub const record_header_texels: u32 = 3;
pub const curve_delta_texels: u32 = 2;
pub const delta_values_per_curve: usize = 8;

pub fn recordTexelCount(curve_count: usize) u32 {
    return record_header_texels + @as(u32, @intCast(curve_count)) * curve_delta_texels;
}

pub fn infoWidth(texel_count: u32) u32 {
    return @min(@max(texel_count, 1), render_abi.paint_info_width);
}

pub fn writeGlyphRecord(
    data: []f32,
    texel_width: u32,
    texel_offset: u32,
    record: GlyphRecord,
    curve_deltas_f16: []const u16,
) !void {
    const expected_deltas = @as(usize, record.curve_count) * delta_values_per_curve;
    if (curve_deltas_f16.len != expected_deltas) return error.InvalidHintDeltaCount;

    try writeRecordHeader(data, texel_width, texel_offset, record);
    for (0..record.curve_count) |curve_index| {
        const deltas = curve_deltas_f16[curve_index * delta_values_per_curve ..][0..delta_values_per_curve];
        const delta_texel = texel_offset + record_header_texels + @as(u32, @intCast(curve_index)) * curve_delta_texels;
        try setTexel(data, texel_width, delta_texel + 0, .{
            f16BitsToF32(deltas[0]),
            f16BitsToF32(deltas[1]),
            f16BitsToF32(deltas[2]),
            f16BitsToF32(deltas[3]),
        });
        try setTexel(data, texel_width, delta_texel + 1, .{
            f16BitsToF32(deltas[4]),
            f16BitsToF32(deltas[5]),
            f16BitsToF32(deltas[6]),
            f16BitsToF32(deltas[7]),
        });
    }
}

fn writeRecordHeader(data: []f32, texel_width: u32, texel_offset: u32, record: GlyphRecord) !void {
    const packed_bands = render_abi.packBandCounts(record.band_entry.h_band_count, record.band_entry.v_band_count);
    try setTexel(data, texel_width, texel_offset + 0, .{
        @floatFromInt(record.band_entry.glyph_x),
        @floatFromInt(record.band_entry.glyph_y),
        @bitCast(packed_bands),
        0,
    });
    try setTexel(data, texel_width, texel_offset + 1, .{
        record.band_entry.band_scale_x,
        record.band_entry.band_scale_y,
        record.band_entry.band_offset_x,
        record.band_entry.band_offset_y,
    });
    try setTexel(data, texel_width, texel_offset + 2, .{
        @floatFromInt(record.base_curve_texel),
        @floatFromInt(record.curve_count),
        @floatFromInt(record.flags.bits()),
        @floatFromInt(packBandPadding(record.h_band_pad, record.v_band_pad)),
    });
}

pub fn packBandPadding(h: u16, v: u16) u32 {
    return @as(u32, h) | (@as(u32, v) << 16);
}

pub fn unpackBandPadding(word: u32) struct { h: u16, v: u16 } {
    return .{
        .h = @intCast(word & 0xffff),
        .v = @intCast(word >> 16),
    };
}

fn setTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) !void {
    if (texel_width == 0) return error.InvalidLayerInfoWidth;
    const base = @as(usize, texel_offset) * 4;
    if (base + 4 > data.len) return error.LayerInfoRecordOutOfBounds;
    data[base + 0] = value[0];
    data[base + 1] = value[1];
    data[base + 2] = value[2];
    data[base + 3] = value[3];
}

fn readTexel(data: []const f32, texel_offset: u32) [4]f32 {
    const base = @as(usize, texel_offset) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

fn f16BitsToF32(bits: u16) f32 {
    return @floatCast(@as(f16, @bitCast(bits)));
}

pub const UploadBytes = struct {
    byte_len: usize = 0,
};

pub const UploadOp = union(enum) {
    glyph_records: UploadBytes,
    curve_deltas: UploadBytes,
    band_rows: UploadBytes,

    pub fn byteLen(self: UploadOp) usize {
        return switch (self) {
            .glyph_records => |bytes| bytes.byte_len,
            .curve_deltas => |bytes| bytes.byte_len,
            .band_rows => |bytes| bytes.byte_len,
        };
    }
};

pub fn totalUploadBytes(ops: []const UploadOp) usize {
    var total: usize = 0;
    for (ops) |op| total += op.byteLen();
    return total;
}

pub const BandReuseProof = struct {
    membership_ok: bool,
    ordering_ok: bool,
    h_band_pad: u16 = 0,
    v_band_pad: u16 = 0,

    pub fn reusable(self: BandReuseProof) bool {
        return self.membership_ok and self.ordering_ok;
    }

    pub fn needsExpandedBands(self: BandReuseProof) bool {
        return self.h_band_pad != 0 or self.v_band_pad != 0;
    }
};

pub const BandReuseInput = struct {
    band_data: []const u16,
    band_width: u32,
    band_entry: band_tex.GlyphBandEntry,
    base_curve_texel: u32,
    hinted_curve_bboxes: []const bezier.BBox,
};

pub fn proveBandReuse(allocator: std.mem.Allocator, input: BandReuseInput) !BandReuseProof {
    if (input.band_width == 0) return .{ .membership_ok = false, .ordering_ok = false };
    if (input.band_entry.h_band_count == 0 or input.band_entry.v_band_count == 0) {
        return .{
            .membership_ok = input.hinted_curve_bboxes.len == 0,
            .ordering_ok = input.hinted_curve_bboxes.len == 0,
        };
    }

    // Single scratch buffer reused across both axes. Stack-fallback keeps the
    // common (small-glyph) case heap-free; large CJK falls through to the gpa.
    var stack_fallback = std.heap.stackFallback(256 * @sizeOf(BaseRange), allocator);
    const scratch = stack_fallback.get();
    const base_ranges = try scratch.alloc(BaseRange, input.hinted_curve_bboxes.len);
    defer scratch.free(base_ranges);

    const h_band_pad = requiredBandPadding(input, .horizontal, base_ranges) orelse input.band_entry.h_band_count;
    const v_band_pad = requiredBandPadding(input, .vertical, base_ranges) orelse input.band_entry.v_band_count;
    const membership_ok = h_band_pad == 0 and v_band_pad == 0;
    const ordering_ok = proveBandOrdering(input);
    return .{
        .membership_ok = membership_ok,
        .ordering_ok = ordering_ok,
        .h_band_pad = h_band_pad,
        .v_band_pad = v_band_pad,
    };
}

const BaseRange = struct {
    start: u16,
    end: u16,
    found: bool,
};

/// Walks every band once and records each hinted curve's min/max base band.
/// Replaces the previous O(curves × bands × refs_per_band) inner-loop search
/// with a single O(total_refs) sweep, then an O(curves) expansion pass.
fn requiredBandPadding(input: BandReuseInput, axis: Axis, base_ranges: []BaseRange) ?u16 {
    for (base_ranges) |*r| r.* = .{ .start = std.math.maxInt(u16), .end = 0, .found = false };

    const band_count: u16 = switch (axis) {
        .horizontal => input.band_entry.h_band_count,
        .vertical => input.band_entry.v_band_count,
    };

    var band: u16 = 0;
    while (band < band_count) : (band += 1) {
        const row = bandRow(input, axis, band) orelse continue;
        for (0..row.count) |i| {
            const ref_pair = pairAt(input, row.index_offset + @as(u32, @intCast(i))) orelse break;
            const curve_index = curveIndexFromRef(input, ref_pair) orelse continue;
            if (curve_index >= base_ranges.len) continue;
            const r = &base_ranges[curve_index];
            r.found = true;
            r.start = @min(r.start, band);
            r.end = @max(r.end, band);
        }
    }

    var required: u16 = 0;
    for (input.hinted_curve_bboxes, base_ranges) |bbox, r| {
        if (!r.found) return null;
        const hinted_range = hintedBandRange(input, axis, bbox);
        required = @max(required, bandRangeExpansion(hinted_range, .{ .start = r.start, .end = r.end }));
    }
    return required;
}

fn proveBandOrdering(input: BandReuseInput) bool {
    for (0..input.band_entry.h_band_count) |band| {
        if (!bandOrderIsDescending(input, .horizontal, @intCast(band))) return false;
    }
    for (0..input.band_entry.v_band_count) |band| {
        if (!bandOrderIsDescending(input, .vertical, @intCast(band))) return false;
    }
    return true;
}

const Axis = enum { horizontal, vertical };

const BandRange = struct {
    start: u16,
    end: u16,
};

fn bandRange(min_value: f32, max_value: f32, scale: f32, offset: f32, band_count: u16) BandRange {
    const max_band_i: i32 = @as(i32, @intCast(band_count)) - 1;
    const start = clampBandIndex(@floor(min_value * scale + offset), max_band_i);
    const end = clampBandIndex(@floor(max_value * scale + offset), max_band_i);
    return .{
        .start = @intCast(@min(start, end)),
        .end = @intCast(@max(start, end)),
    };
}

fn hintedBandRange(input: BandReuseInput, axis: Axis, bbox: bezier.BBox) BandRange {
    return switch (axis) {
        .horizontal => bandRange(bbox.min.y, bbox.max.y, input.band_entry.band_scale_y, input.band_entry.band_offset_y, input.band_entry.h_band_count),
        .vertical => bandRange(bbox.min.x, bbox.max.x, input.band_entry.band_scale_x, input.band_entry.band_offset_x, input.band_entry.v_band_count),
    };
}

fn bandRangeExpansion(hinted: BandRange, base: BandRange) u16 {
    var required: u16 = 0;
    if (hinted.start < base.start) required = @max(required, base.start - hinted.start);
    if (hinted.end > base.end) required = @max(required, hinted.end - base.end);
    return required;
}

fn clampBandIndex(value: f32, max_band: i32) i32 {
    if (!std.math.isFinite(value)) return 0;
    const index: i32 = @intFromFloat(value);
    return std.math.clamp(index, 0, max_band);
}

fn bandOrderIsDescending(input: BandReuseInput, axis: Axis, band_index: u16) bool {
    const row = bandRow(input, axis, band_index) orelse return false;

    var previous: f32 = std.math.inf(f32);
    for (0..row.count) |i| {
        const ref_pair = pairAt(input, row.index_offset + @as(u32, @intCast(i))) orelse return false;
        const curve_index = curveIndexFromRef(input, ref_pair) orelse return false;
        if (curve_index >= input.hinted_curve_bboxes.len) return false;
        const key = curveSortKey(input.hinted_curve_bboxes[curve_index], axis);
        if (key > previous + 1.0e-6) return false;
        previous = key;
    }
    return true;
}

const BandRow = struct {
    count: u16,
    index_offset: u32,
};

fn bandRow(input: BandReuseInput, axis: Axis, band_index: u16) ?BandRow {
    const header_offset = switch (axis) {
        .horizontal => @as(u32, band_index),
        .vertical => @as(u32, input.band_entry.h_band_count) + @as(u32, band_index),
    };
    const header = pairAt(input, header_offset) orelse return null;
    return .{ .count = header[0], .index_offset = header[1] };
}

fn pairAt(input: BandReuseInput, offset_from_glyph: u32) ?[2]u16 {
    const glyph_texel = @as(u32, input.band_entry.glyph_y) * input.band_width + @as(u32, input.band_entry.glyph_x);
    const texel = glyph_texel + offset_from_glyph;
    const index = @as(usize, texel) * 2;
    if (index + 2 > input.band_data.len) return null;
    return .{ input.band_data[index], input.band_data[index + 1] };
}

fn curveIndexFromRef(input: BandReuseInput, ref_pair: [2]u16) ?usize {
    const curve_texel = (@as(u32, ref_pair[1]) * band_tex.TEX_WIDTH) + (@as(u32, ref_pair[0]) & 0x0FFF);
    if (curve_texel < input.base_curve_texel) return null;
    const delta = curve_texel - input.base_curve_texel;
    if (delta % curve_tex.SEGMENT_TEXELS != 0) return null;
    return @intCast(delta / curve_tex.SEGMENT_TEXELS);
}

fn curveSortKey(bbox: bezier.BBox, axis: Axis) f32 {
    return switch (axis) {
        .horizontal => bbox.max.x,
        .vertical => bbox.max.y,
    };
}

test "hint flags round trip" {
    const flags = GlyphFlags{ .expanded_bands = true, .unordered_bands = true, .has_band_patch = true };
    const decoded = GlyphFlags.fromBits(flags.bits());
    try std.testing.expect(decoded.expanded_bands);
    try std.testing.expect(decoded.unordered_bands);
    try std.testing.expect(decoded.has_band_patch);
}

test "upload ops report byte totals" {
    const ops = [_]UploadOp{
        .{ .glyph_records = .{ .byte_len = 64 } },
        .{ .curve_deltas = .{ .byte_len = 128 } },
        .{ .band_rows = .{ .byte_len = 32 } },
    };
    try std.testing.expectEqual(@as(usize, 224), totalUploadBytes(&ops));
}

test "hint glyph record writes band header and curve deltas" {
    var data = [_]f32{0} ** (@as(usize, recordTexelCount(1)) * 4);
    const deltas = [_]u16{
        curve_tex.f32ToF16(0.125),
        curve_tex.f32ToF16(-0.25),
        curve_tex.f32ToF16(0.5),
        curve_tex.f32ToF16(0.75),
        curve_tex.f32ToF16(-1.0),
        curve_tex.f32ToF16(1.25),
        curve_tex.f32ToF16(0.0),
        curve_tex.f32ToF16(2.0),
    };

    try writeGlyphRecord(&data, infoWidth(recordTexelCount(1)), 0, .{
        .base_curve_texel = 128,
        .curve_count = 1,
        .band_entry = testBandEntry(),
    }, &deltas);

    const header = readTexel(&data, 0);
    const meta = readTexel(&data, 2);
    const delta0 = readTexel(&data, 3);
    const delta1 = readTexel(&data, 4);
    const packed_bands: u32 = @bitCast(header[2]);
    try std.testing.expectEqual(@as(f32, 0), header[0]);
    try std.testing.expectEqual(@as(f32, 0), header[1]);
    try std.testing.expectEqual(render_abi.packBandCounts(1, 1), packed_bands);
    try std.testing.expectEqual(@as(f32, 128), meta[0]);
    try std.testing.expectEqual(@as(f32, 1), meta[1]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), delta0[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.25), delta0[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), delta1[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), delta1[3], 0.001);
}

test "band reuse proof accepts stable membership and ordering" {
    const band_data = [_]u16{
        2, 2, // h0 header
        2, 4, // v0 header
        100, 0, // h0 curve 0
        104, 0, // h0 curve 1
        100, 0, // v0 curve 0
        104, 0, // v0 curve 1
    };
    const bboxes = [_]bezier.BBox{
        .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = 2, .y = 2 } },
        .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = 1, .y = 1 } },
    };

    const proof = try proveBandReuse(std.testing.allocator, .{
        .band_data = &band_data,
        .band_width = 16,
        .band_entry = testBandEntry(),
        .base_curve_texel = 100,
        .hinted_curve_bboxes = &bboxes,
    });
    try std.testing.expect(proof.reusable());
}

test "band reuse proof reports ordering failure" {
    const band_data = [_]u16{
        2,   2, 2,   4,
        100, 0, 104, 0,
        100, 0, 104, 0,
    };
    const bboxes = [_]bezier.BBox{
        .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = 1, .y = 1 } },
        .{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = 2, .y = 2 } },
    };

    const proof = try proveBandReuse(std.testing.allocator, .{
        .band_data = &band_data,
        .band_width = 16,
        .band_entry = testBandEntry(),
        .base_curve_texel = 100,
        .hinted_curve_bboxes = &bboxes,
    });
    try std.testing.expect(proof.membership_ok);
    try std.testing.expect(!proof.ordering_ok);
}

test "band reuse proof reports required expansion" {
    const band_data = [_]u16{
        1, 4, // h0 header
        0, 5, // h1 header
        0, 5, // h2 header
        1, 5, // v0 header
        100, 0, // h0 curve 0
        100, 0, // v0 curve 0
    };
    const bboxes = [_]bezier.BBox{
        .{ .min = .{ .x = 0.1, .y = 2.1 }, .max = .{ .x = 0.2, .y = 2.2 } },
    };
    const proof = try proveBandReuse(std.testing.allocator, .{
        .band_data = &band_data,
        .band_width = 16,
        .band_entry = .{
            .glyph_x = 0,
            .glyph_y = 0,
            .h_band_count = 3,
            .v_band_count = 1,
            .band_scale_x = 1,
            .band_scale_y = 1,
            .band_offset_x = 0,
            .band_offset_y = 0,
        },
        .base_curve_texel = 100,
        .hinted_curve_bboxes = &bboxes,
    });

    try std.testing.expect(!proof.membership_ok);
    try std.testing.expect(proof.ordering_ok);
    try std.testing.expectEqual(@as(u16, 2), proof.h_band_pad);
    try std.testing.expectEqual(@as(u16, 0), proof.v_band_pad);
    try std.testing.expect(proof.needsExpandedBands());
}

test "band reuse proof expands partially overlapping ranges" {
    const band_data = [_]u16{
        0, 5, // h0 header
        1, 5, // h1 header
        1, 6, // h2 header
        0, 7, // h3 header
        1, 7, // v0 header
        100, 0, // h1 curve 0
        100, 0, // h2 curve 0
        100, 0, // v0 curve 0
    };
    const bboxes = [_]bezier.BBox{
        .{ .min = .{ .x = 0.1, .y = 2.1 }, .max = .{ .x = 0.2, .y = 3.1 } },
    };
    const proof = try proveBandReuse(std.testing.allocator, .{
        .band_data = &band_data,
        .band_width = 16,
        .band_entry = .{
            .glyph_x = 0,
            .glyph_y = 0,
            .h_band_count = 4,
            .v_band_count = 1,
            .band_scale_x = 1,
            .band_scale_y = 1,
            .band_offset_x = 0,
            .band_offset_y = 0,
        },
        .base_curve_texel = 100,
        .hinted_curve_bboxes = &bboxes,
    });

    try std.testing.expect(!proof.membership_ok);
    try std.testing.expectEqual(@as(u16, 1), proof.h_band_pad);
    try std.testing.expectEqual(@as(u16, 0), proof.v_band_pad);
}

fn testBandEntry() band_tex.GlyphBandEntry {
    return .{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1,
        .band_scale_y = 1,
        .band_offset_x = 0,
        .band_offset_y = 0,
    };
}
