//! Color-space conversions for the API boundary.
//!
//! Every `[4]f32` color crossing the snail API is LINEAR light with
//! straight (non-premultiplied) alpha. Snail never interprets or converts
//! host colors: they are stored, interpolated, tinted, and blended exactly
//! as given, and the final fragment output is premultiplied linear (encode
//! to sRGB via the framebuffer or the host's own resolve).
//!
//! These pure helpers are for hosts that author colors in sRGB — convert
//! once at the boundary. Font-sourced palette colors (CPAL, spec-defined
//! as sRGB) are already converted at extraction.
//!
//! Internally, per-instance colors travel as sRGB-encoded u8 — a transport
//! codec chosen because 8-bit sRGB is perceptually uniform (raw linear u8
//! bands near black). The round-trip is an implementation detail and is
//! invisible at the API.

const std = @import("std");

pub fn srgbToLinear(v: f32) f32 {
    if (v <= 0.04045) return v / 12.92;
    return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn linearToSrgb(v: f32) f32 {
    if (v <= 0.0031308) return v * 12.92;
    return 1.055 * std.math.pow(f32, v, 1.0 / 2.4) - 0.055;
}

/// sRGB-encoded color → linear. Alpha is linear in both encodings and
/// passes through.
pub fn srgbToLinearColor(color: [4]f32) [4]f32 {
    return .{ srgbToLinear(color[0]), srgbToLinear(color[1]), srgbToLinear(color[2]), color[3] };
}

/// Linear color → sRGB-encoded. Alpha passes through.
pub fn linearToSrgbColor(color: [4]f32) [4]f32 {
    return .{ linearToSrgb(color[0]), linearToSrgb(color[1]), linearToSrgb(color[2]), color[3] };
}

test "srgb transfer round-trips and fixes 0/1" {
    try std.testing.expectEqual(@as(f32, 0), srgbToLinear(0));
    try std.testing.expectApproxEqAbs(@as(f32, 1), srgbToLinear(1), 1e-6);
    try std.testing.expectEqual(@as(f32, 0), linearToSrgb(0));
    try std.testing.expectApproxEqAbs(@as(f32, 1), linearToSrgb(1), 1e-6);
    var v: f32 = 0.05;
    while (v < 1.0) : (v += 0.05) {
        try std.testing.expectApproxEqAbs(v, linearToSrgb(srgbToLinear(v)), 1e-5);
    }
    // The canonical mid-gray check: 50% sRGB is ~21.4% linear light.
    try std.testing.expectApproxEqAbs(@as(f32, 0.2140), srgbToLinear(0.5), 1e-3);
}
