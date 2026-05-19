const std = @import("std");

const band_tex = @import("band_texture.zig");
const bezier = @import("../../math/bezier.zig");

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
