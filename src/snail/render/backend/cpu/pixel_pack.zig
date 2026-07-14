//! Comptime pixel pack/unpack for the CPU backend, specialized per
//! `PixelFormat`. Pure bit-layout only: channel order, bit depth, and
//! packing. sRGB encode and dither are the caller's job (`blend.zig` feeds an
//! already-encoded, already-dithered value in), so these stay a clean
//! round-trippable core. The renderer dispatches on the runtime format once
//! per draw (`inline else`), so `fmt` is comptime here and every arm folds to
//! a branch-free sequence.

const std = @import("std");
const snail = @import("../../../core.zig");

const PixelFormat = snail.PixelFormat;

fn quantU8(v: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(v, 0.0, 1.0) * 255.0));
}

fn quant(v: f32, comptime max: u32) u32 {
    return @intFromFloat(@round(std.math.clamp(v, 0.0, 1.0) * @as(f32, @floatFromInt(max))));
}

inline fn unormU8(b: u8) f32 {
    return @as(f32, @floatFromInt(b)) / 255.0;
}

/// Pack a storage-space RGBA (RGB already sRGB/linear-encoded by the caller,
/// A linear) into this format's bytes. Float formats store the value raw
/// (HDR values >1 survive); mask formats keep only the painted alpha.
pub fn pack(comptime fmt: PixelFormat, rgba: [4]f32) [fmt.bytesPerPixel()]u8 {
    return switch (fmt) {
        .rgba8_unorm => .{ quantU8(rgba[0]), quantU8(rgba[1]), quantU8(rgba[2]), quantU8(rgba[3]) },
        .bgra8_unorm => .{ quantU8(rgba[2]), quantU8(rgba[1]), quantU8(rgba[0]), quantU8(rgba[3]) },
        .rgb10a2_unorm => blk: {
            const word: u32 = quant(rgba[0], 1023) |
                (quant(rgba[1], 1023) << 10) |
                (quant(rgba[2], 1023) << 20) |
                (quant(rgba[3], 3) << 30);
            var out: [4]u8 = undefined;
            std.mem.writeInt(u32, &out, word, .little);
            break :blk out;
        },
        .rgba16f => blk: {
            var out: [8]u8 = undefined;
            inline for (0..4) |i| {
                const h: u16 = @bitCast(@as(f16, @floatCast(rgba[i])));
                std.mem.writeInt(u16, out[i * 2 ..][0..2], h, .little);
            }
            break :blk out;
        },
        // R8 and A8 both store painted alpha in their single channel.
        .r8_unorm, .a8_unorm => .{quantU8(rgba[3])},
    };
}

/// Inverse of `pack` for read-modify-write blending. Mask formats return
/// `{0,0,0, alpha}` — their RGB is never read (the pipeline elides it).
pub fn unpack(comptime fmt: PixelFormat, bytes: *const [fmt.bytesPerPixel()]u8) [4]f32 {
    return switch (fmt) {
        .rgba8_unorm => .{ unormU8(bytes[0]), unormU8(bytes[1]), unormU8(bytes[2]), unormU8(bytes[3]) },
        .bgra8_unorm => .{ unormU8(bytes[2]), unormU8(bytes[1]), unormU8(bytes[0]), unormU8(bytes[3]) },
        .rgb10a2_unorm => blk: {
            const word = std.mem.readInt(u32, bytes, .little);
            break :blk .{
                @as(f32, @floatFromInt(word & 0x3FF)) / 1023.0,
                @as(f32, @floatFromInt((word >> 10) & 0x3FF)) / 1023.0,
                @as(f32, @floatFromInt((word >> 20) & 0x3FF)) / 1023.0,
                @as(f32, @floatFromInt((word >> 30) & 0x3)) / 3.0,
            };
        },
        .rgba16f => blk: {
            var out: [4]f32 = undefined;
            inline for (0..4) |i| {
                const h = std.mem.readInt(u16, bytes[i * 2 ..][0..2], .little);
                out[i] = @floatCast(@as(f16, @bitCast(h)));
            }
            break :blk out;
        },
        .r8_unorm, .a8_unorm => .{ 0, 0, 0, unormU8(bytes[0]) },
    };
}

// ── round-trip vector tests ────────────────────────────────────────────────

const testing = std.testing;

fn roundTrip(comptime fmt: PixelFormat, rgba: [4]f32) [4]f32 {
    const bytes = pack(fmt, rgba);
    return unpack(fmt, &bytes);
}

test "bytesPerPixel matches the layout" {
    try testing.expectEqual(@as(u32, 4), PixelFormat.rgba8_unorm.bytesPerPixel());
    try testing.expectEqual(@as(u32, 4), PixelFormat.bgra8_unorm.bytesPerPixel());
    try testing.expectEqual(@as(u32, 4), PixelFormat.rgb10a2_unorm.bytesPerPixel());
    try testing.expectEqual(@as(u32, 8), PixelFormat.rgba16f.bytesPerPixel());
    try testing.expectEqual(@as(u32, 1), PixelFormat.r8_unorm.bytesPerPixel());
    try testing.expectEqual(@as(u32, 1), PixelFormat.a8_unorm.bytesPerPixel());
}

test "rgba8 round-trips within 8-bit quantization" {
    const v = [4]f32{ 0.25, 0.5, 0.75, 1.0 };
    const rt = roundTrip(.rgba8_unorm, v);
    inline for (0..4) |i| try testing.expectApproxEqAbs(v[i], rt[i], 1.0 / 255.0);
}

test "bgra8 swaps R and B in storage but round-trips" {
    // Pure red: the blue byte slot holds it, red slot is zero.
    const bytes = pack(.bgra8_unorm, .{ 1, 0, 0, 1 });
    try testing.expectEqual(@as(u8, 255), bytes[2]); // R stored at byte 2
    try testing.expectEqual(@as(u8, 0), bytes[0]);
    const rt = roundTrip(.bgra8_unorm, .{ 0.25, 0.5, 0.75, 1.0 });
    try testing.expectApproxEqAbs(@as(f32, 0.25), rt[0], 1.0 / 255.0);
    try testing.expectApproxEqAbs(@as(f32, 0.75), rt[2], 1.0 / 255.0);
}

test "rgb10a2 round-trips at 10-bit RGB / 2-bit alpha" {
    const rt = roundTrip(.rgb10a2_unorm, .{ 0.25, 0.5, 0.75, 0.6667 });
    try testing.expectApproxEqAbs(@as(f32, 0.25), rt[0], 1.0 / 1023.0);
    try testing.expectApproxEqAbs(@as(f32, 0.5), rt[1], 1.0 / 1023.0);
    try testing.expectApproxEqAbs(@as(f32, 0.75), rt[2], 1.0 / 1023.0);
    try testing.expectApproxEqAbs(@as(f32, 0.6667), rt[3], 1.0 / 3.0); // 2-bit → 2/3
}

test "rgba16f round-trips, including HDR values above 1" {
    const v = [4]f32{ 0.1, 1.5, 3.25, 0.8 }; // 1.5, 3.25 exceed unorm range
    const rt = roundTrip(.rgba16f, v);
    inline for (0..4) |i| try testing.expectApproxEqAbs(v[i], rt[i], 0.01);
}

test "mask formats keep only painted alpha" {
    inline for (.{ PixelFormat.r8_unorm, PixelFormat.a8_unorm }) |fmt| {
        const bytes = pack(fmt, .{ 0.9, 0.4, 0.1, 0.5 });
        try testing.expectEqual(@as(u8, quantU8(0.5)), bytes[0]);
        const rt = unpack(fmt, &bytes);
        try testing.expectEqual(@as(f32, 0), rt[0]);
        try testing.expectEqual(@as(f32, 0), rt[1]);
        try testing.expectEqual(@as(f32, 0), rt[2]);
        try testing.expectApproxEqAbs(@as(f32, 0.5), rt[3], 1.0 / 255.0);
    }
}
