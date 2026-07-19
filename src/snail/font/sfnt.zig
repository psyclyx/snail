const std = @import("std");

pub const Error = error{
    UnexpectedEof,
    InvalidFont,
    InvalidFaceIndex,
    UnsupportedFontContainer,
};

const ttc_tag = "ttcf";
const ttc_version_1: u32 = 0x00010000;
const ttc_version_2: u32 = 0x00020000;

/// Return the number of faces in an sfnt font or collection.
pub fn faceCount(data: []const u8) Error!u32 {
    if (data.len < 12) return error.InvalidFont;
    if (!std.mem.eql(u8, data[0..4], ttc_tag)) {
        if (std.mem.eql(u8, data[0..4], "wOFF") or std.mem.eql(u8, data[0..4], "wOF2"))
            return error.UnsupportedFontContainer;
        if (!isSfntVersion(data[0..4])) return error.InvalidFont;
        return 1;
    }

    const version = try readU32(data, 4);
    if (version != ttc_version_1 and version != ttc_version_2) return error.InvalidFont;

    const count = try readU32(data, 8);
    if (count == 0) return error.InvalidFont;
    const directory_bytes = std.math.mul(usize, count, 4) catch return error.InvalidFont;
    if (directory_bytes > data.len - 12) return error.UnexpectedEof;
    return count;
}

/// Resolve a zero-based face index to its sfnt table-directory offset.
/// Standalone fonts have one face at offset zero. Collection table offsets
/// remain absolute to the beginning of `data`, as required by OpenType.
pub fn directoryOffset(data: []const u8, face_index: u32) Error!u32 {
    const count = try faceCount(data);
    if (face_index >= count) return error.InvalidFaceIndex;
    if (count == 1 and !std.mem.eql(u8, data[0..4], ttc_tag)) return 0;

    const offset = try readU32(data, 12 + @as(usize, face_index) * 4);
    if (@as(usize, offset) > data.len - 12) return error.UnexpectedEof;
    if (!isSfntVersion(data[offset..][0..4])) return error.InvalidFont;
    return offset;
}

fn isSfntVersion(tag: []const u8) bool {
    return std.mem.eql(u8, tag, &.{ 0, 1, 0, 0 }) or
        std.mem.eql(u8, tag, "OTTO") or
        std.mem.eql(u8, tag, "true") or
        std.mem.eql(u8, tag, "typ1");
}

fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.UnexpectedEof;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "standalone sfnt has one face at offset zero" {
    const data = [_]u8{ 0, 1, 0, 0 } ++ [_]u8{0} ** 8;
    try std.testing.expectEqual(@as(u32, 1), try faceCount(&data));
    try std.testing.expectEqual(@as(u32, 0), try directoryOffset(&data, 0));
    try std.testing.expectError(error.InvalidFaceIndex, directoryOffset(&data, 1));
}

test "web transfer containers report an explicit unsupported error" {
    const woff = "wOFF" ++ ([_]u8{0} ** 8);
    const woff2 = "wOF2" ++ ([_]u8{0} ** 8);
    try std.testing.expectError(error.UnsupportedFontContainer, faceCount(woff));
    try std.testing.expectError(error.UnsupportedFontContainer, faceCount(woff2));
}

test "collection resolves face directory offsets" {
    const data = [_]u8{
        't', 't', 'c', 'f',
        0,   1,   0,   0,
        0,   0,   0,   2,
        0,   0,   0,   20,
        0,   0,   0,   32,
    } ++ [_]u8{ 0, 1, 0, 0 } ++ [_]u8{0} ** 8 ++ [_]u8{ 'O', 'T', 'T', 'O' } ++ [_]u8{0} ** 8;
    try std.testing.expectEqual(@as(u32, 2), try faceCount(&data));
    try std.testing.expectEqual(@as(u32, 20), try directoryOffset(&data, 0));
    try std.testing.expectEqual(@as(u32, 32), try directoryOffset(&data, 1));
    try std.testing.expectError(error.InvalidFaceIndex, directoryOffset(&data, 2));
}
