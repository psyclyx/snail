//! Band padding pack/unpack helpers.
//!
//! A glyph's horizontal and vertical band-padding counts are packed into a
//! single 32-bit word for storage in the layer-info slab: the horizontal count
//! in the low 16 bits and the vertical count in the high 16 bits. The renderer
//! reads this word back via `unpackBandPadding`.

const std = @import("std");

pub fn packBandPadding(h: u16, v: u16) u32 {
    return @as(u32, h) | (@as(u32, v) << 16);
}

pub fn unpackBandPadding(word: u32) struct { h: u16, v: u16 } {
    return .{
        .h = @intCast(word & 0xffff),
        .v = @intCast(word >> 16),
    };
}

test "band padding round trips through pack/unpack" {
    const packed_word = packBandPadding(0x1234, 0xabcd);
    const unpacked = unpackBandPadding(packed_word);
    try std.testing.expectEqual(@as(u16, 0x1234), unpacked.h);
    try std.testing.expectEqual(@as(u16, 0xabcd), unpacked.v);
}
