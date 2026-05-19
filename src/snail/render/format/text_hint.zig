const std = @import("std");

const band_tex = @import("band_texture.zig");
const bezier = @import("../../math/bezier.zig");
const curve_tex = @import("curve_texture.zig");

pub const HintHandle = u16;
pub const no_hint: HintHandle = 0;

pub const DeltaEncoding = enum(u8) {
    /// Per-curve deltas matching the decoded base curve texture coordinates.
    curve_f16,
};

pub const GlyphFlags = packed struct(u16) {
    has_band_patch: bool = false,
    reserved: u15 = 0,

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

    pub fn reusable(self: BandReuseProof) bool {
        return self.membership_ok and self.ordering_ok;
    }
};

pub const BandReuseInput = struct {
    band_data: []const u16,
    band_width: u32,
    band_entry: band_tex.GlyphBandEntry,
    base_curve_texel: u32,
    hinted_curve_bboxes: []const bezier.BBox,
};

pub fn proveBandReuse(input: BandReuseInput) BandReuseProof {
    if (input.band_width == 0) return .{ .membership_ok = false, .ordering_ok = false };
    if (input.band_entry.h_band_count == 0 or input.band_entry.v_band_count == 0) {
        return .{
            .membership_ok = input.hinted_curve_bboxes.len == 0,
            .ordering_ok = input.hinted_curve_bboxes.len == 0,
        };
    }

    const membership_ok = proveBandMembership(input);
    const ordering_ok = proveBandOrdering(input);
    return .{ .membership_ok = membership_ok, .ordering_ok = ordering_ok };
}

fn proveBandMembership(input: BandReuseInput) bool {
    for (input.hinted_curve_bboxes, 0..) |bbox, curve_index| {
        const h_range = bandRange(bbox.min.y, bbox.max.y, input.band_entry.band_scale_y, input.band_entry.band_offset_y, input.band_entry.h_band_count);
        var h_band = h_range.start;
        while (h_band <= h_range.end) : (h_band += 1) {
            if (!bandContainsCurve(input, .horizontal, h_band, curve_index)) return false;
        }

        const v_range = bandRange(bbox.min.x, bbox.max.x, input.band_entry.band_scale_x, input.band_entry.band_offset_x, input.band_entry.v_band_count);
        var v_band = v_range.start;
        while (v_band <= v_range.end) : (v_band += 1) {
            if (!bandContainsCurve(input, .vertical, v_band, curve_index)) return false;
        }
    }
    return true;
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

fn clampBandIndex(value: f32, max_band: i32) i32 {
    if (!std.math.isFinite(value)) return 0;
    const index: i32 = @intFromFloat(value);
    return std.math.clamp(index, 0, max_band);
}

fn bandContainsCurve(input: BandReuseInput, axis: Axis, band_index: u16, curve_index: usize) bool {
    const row = bandRow(input, axis, band_index) orelse return false;
    for (0..row.count) |i| {
        const ref_pair = pairAt(input, row.index_offset + @as(u32, @intCast(i))) orelse return false;
        if (curveIndexFromRef(input, ref_pair) == curve_index) return true;
    }
    return false;
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
    const flags = GlyphFlags{ .has_band_patch = true };
    try std.testing.expect(GlyphFlags.fromBits(flags.bits()).has_band_patch);
}

test "upload ops report byte totals" {
    const ops = [_]UploadOp{
        .{ .glyph_records = .{ .byte_len = 64 } },
        .{ .curve_deltas = .{ .byte_len = 128 } },
        .{ .band_rows = .{ .byte_len = 32 } },
    };
    try std.testing.expectEqual(@as(usize, 224), totalUploadBytes(&ops));
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

    const proof = proveBandReuse(.{
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

    const proof = proveBandReuse(.{
        .band_data = &band_data,
        .band_width = 16,
        .band_entry = testBandEntry(),
        .base_curve_texel = 100,
        .hinted_curve_bboxes = &bboxes,
    });
    try std.testing.expect(proof.membership_ok);
    try std.testing.expect(!proof.ordering_ok);
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
