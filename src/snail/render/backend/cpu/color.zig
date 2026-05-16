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

const linear_to_srgb_bucket_count = 4096;
const linear_to_srgb_byte_buckets: [linear_to_srgb_bucket_count]u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var table: [linear_to_srgb_bucket_count]u8 = undefined;
    for (0..linear_to_srgb_bucket_count) |bucket| {
        const lower = @as(f32, @floatFromInt(bucket)) / @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
        var byte: u8 = 0;
        while (byte < linear_to_srgb_byte_thresholds.len and lower >= linear_to_srgb_byte_thresholds[byte]) {
            byte += 1;
        }
        table[bucket] = byte;
    }
    break :blk table;
};

pub fn srgbToLinear(byte: u8) f32 {
    return srgb_to_linear_lut[byte];
}

pub fn linearToSrgb(v: f32) f32 {
    const clamped = @max(v, 0.0);
    if (clamped >= 1.0) return 1.0;
    return if (clamped <= 0.0031308) clamped * 12.92 else 1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
}

pub fn linearToSrgbByte(v: f32) u8 {
    const clamped = @min(@max(v, 0.0), 1.0);
    const bucket_float = clamped * @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
    const bucket = @min(@as(usize, @intFromFloat(bucket_float)), linear_to_srgb_bucket_count - 1);
    var byte = linear_to_srgb_byte_buckets[bucket];
    while (byte < linear_to_srgb_byte_thresholds.len and clamped >= linear_to_srgb_byte_thresholds[byte]) {
        byte += 1;
    }
    while (byte > 0 and clamped < linear_to_srgb_byte_thresholds[byte - 1]) {
        byte -= 1;
    }
    return byte;
}

pub fn srgbFloatToLinear(v: f32) f32 {
    return srgbFloatToLinearFormula(v);
}

pub fn srgbToByte(v: f32) u8 {
    return @intFromFloat(@round(@min(@max(v * 255.0, 0.0), 255.0)));
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

pub fn clamp01(v: f32) f32 {
    return std.math.clamp(v, 0.0, 1.0);
}

pub fn max3(values: [3]f32) f32 {
    return @max(values[0], @max(values[1], values[2]));
}

pub fn interleavedGradientNoise(row: u32, col: u32) f32 {
    const pixel_x = @as(f32, @floatFromInt(col)) + 0.5;
    const pixel_y = @as(f32, @floatFromInt(row)) + 0.5;
    return fract(52.9829189 * fract(pixel_x * 0.06711056 + pixel_y * 0.00583715));
}
