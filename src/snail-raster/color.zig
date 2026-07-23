//! Color conversion primitives for the software rasterizer.

const std = @import("std");

// sRGB ↔ linear conversion. The 256-entry decode LUT is exact for u8 texels.
// Encode uses the IEC 61966-2-1 formula directly so per-pixel output rounds
// to the same bytes as a GL_SRGB framebuffer (no LUT-interpolation drift).

fn srgbFloatToLinearFormula(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

const srgb_to_linear_lut: [256]f32 = blk: {
    @setEvalBranchQuota(100_000);
    var table: [256]f32 = undefined;
    for (0..256) |i| {
        const v: f32 = @as(f32, @floatFromInt(i)) / 255.0;
        table[i] = srgbFloatToLinearFormula(v);
    }
    break :blk table;
};

const linear_to_srgb_byte_thresholds: [255]f32 = blk: {
    @setEvalBranchQuota(100_000);
    var table: [255]f32 = undefined;
    for (0..255) |i| {
        const threshold_srgb = (@as(f32, @floatFromInt(i)) + 0.5) / 255.0;
        table[i] = srgbFloatToLinearFormula(threshold_srgb);
    }
    break :blk table;
};

// 8192 buckets gives a bucket width of ~1.22e-4 in linear space, well below
// the minimum sRGB byte-threshold gap of 1/(255 * 12.92) ≈ 3.04e-4. With at
// most one threshold per bucket, an entry sized to the bucket's upper edge is
// either correct or one byte too high, so the lookup is bit-exact with the
// IEC 61966-2-1 formula after at most one branch-predicted step down.
const linear_to_srgb_bucket_count = 8192;
const linear_to_srgb_byte_buckets: [linear_to_srgb_bucket_count]u8 = blk: {
    @setEvalBranchQuota(10_000_000);
    var table: [linear_to_srgb_bucket_count]u8 = undefined;
    for (0..linear_to_srgb_bucket_count) |bucket| {
        const upper = @as(f32, @floatFromInt(bucket + 1)) / @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
        var byte: u8 = 0;
        while (byte < linear_to_srgb_byte_thresholds.len and upper >= linear_to_srgb_byte_thresholds[byte]) {
            byte += 1;
        }
        table[bucket] = byte;
    }
    break :blk table;
};

pub fn srgbToLinear(byte: u8) f32 {
    return srgb_to_linear_lut[byte];
}

/// Clamp a possibly non-finite channel to the normalized storage domain.
/// NaN has no meaningful ordering or color interpretation, so canonicalize it
/// to zero; infinities saturate at the corresponding endpoint. Keeping this
/// helper total matters because otherwise two individually finite HDR layers
/// can overflow during blending and trap in a later float-to-integer pack.
pub fn clamp01(v: f32) f32 {
    if (std.math.isNan(v) or v <= 0.0) return 0.0;
    if (v >= 1.0) return 1.0;
    return v;
}

pub fn linearToSrgb(v: f32) f32 {
    const clamped = clamp01(v);
    if (clamped >= 1.0) return 1.0;
    return if (clamped <= 0.0031308) clamped * 12.92 else 1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
}

// LUT-based approximation of `linearToSrgb`, sized so each bucket's
// quantization error is well under one byte after re-quantization. Hot path:
// dithered blends, where the formula's `pow` is otherwise per-pixel-per-channel.
const linear_to_srgb_float_buckets: [linear_to_srgb_bucket_count]f32 = blk: {
    @setEvalBranchQuota(1_000_000);
    var table: [linear_to_srgb_bucket_count]f32 = undefined;
    for (0..linear_to_srgb_bucket_count) |bucket| {
        const center: f32 = (@as(f32, @floatFromInt(bucket)) + 0.5) / @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
        const clamped = @max(center, 0.0);
        table[bucket] = if (clamped <= 0.0031308) clamped * 12.92 else 1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
    }
    break :blk table;
};

pub inline fn linearToSrgbApprox(v: f32) f32 {
    const clamped = clamp01(v);
    const bucket_float = clamped * @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
    const bucket = @min(@as(usize, @intFromFloat(bucket_float)), linear_to_srgb_bucket_count - 1);
    return linear_to_srgb_float_buckets[bucket];
}

pub fn linearToSrgbByte(v: f32) u8 {
    const clamped = clamp01(v);
    const bucket_float = clamped * @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
    const bucket = @min(@as(usize, @intFromFloat(bucket_float)), linear_to_srgb_bucket_count - 1);
    var byte = linear_to_srgb_byte_buckets[bucket];
    // LUT entry is the byte for the bucket's upper edge, so the answer is
    // either correct or one too high. One conditional step-down is enough.
    if (byte > 0 and clamped < linear_to_srgb_byte_thresholds[byte - 1]) {
        byte -= 1;
    }
    return byte;
}

pub fn srgbFloatToLinear(v: f32) f32 {
    return srgbFloatToLinearFormula(v);
}

pub fn srgbToByte(v: f32) u8 {
    return @intFromFloat(@round(clamp01(v) * 255.0));
}

pub fn srgbColorToLinear(color: [4]f32) [4]f32 {
    return .{
        srgbFloatToLinear(color[0]),
        srgbFloatToLinear(color[1]),
        srgbFloatToLinear(color[2]),
        color[3],
    };
}

pub fn srgbBytesToLinearColor(color: [4]u8) [4]f32 {
    return .{
        srgbToLinear(color[0]),
        srgbToLinear(color[1]),
        srgbToLinear(color[2]),
        @as(f32, @floatFromInt(color[3])) / 255.0,
    };
}

pub fn linearColorToSrgb(color: [4]f32) [4]f32 {
    return .{
        linearToSrgb(color[0]),
        linearToSrgb(color[1]),
        linearToSrgb(color[2]),
        color[3],
    };
}

pub fn multiplyLinearColor(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

pub fn fract(v: f32) f32 {
    return v - @floor(v);
}

pub fn max3(values: [3]f32) f32 {
    return @max(values[0], @max(values[1], values[2]));
}

pub fn interleavedGradientNoise(row: u32, col: u32) f32 {
    const pixel_x = @as(f32, @floatFromInt(col)) + 0.5;
    const pixel_y = @as(f32, @floatFromInt(row)) + 0.5;
    return fract(52.9829189 * fract(pixel_x * 0.06711056 + pixel_y * 0.00583715));
}

test "normalized color packing is total for non-finite channels" {
    try std.testing.expectEqual(@as(f32, 0), clamp01(std.math.nan(f32)));
    try std.testing.expectEqual(@as(f32, 0), clamp01(-std.math.inf(f32)));
    try std.testing.expectEqual(@as(f32, 1), clamp01(std.math.inf(f32)));
    try std.testing.expectEqual(@as(u8, 0), linearToSrgbByte(std.math.nan(f32)));
    try std.testing.expectEqual(@as(u8, 255), linearToSrgbByte(std.math.inf(f32)));
    try std.testing.expectEqual(@as(u8, 0), srgbToByte(-std.math.inf(f32)));
    try std.testing.expectEqual(@as(u8, 255), srgbToByte(std.math.inf(f32)));
}
