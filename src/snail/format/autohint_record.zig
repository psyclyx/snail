//! Immutable autohint analysis record stored in the layer-info slab.
//!
//! The record contains no fitted targets and no PPEM. It couples the base
//! glyph's band entry with em-normalized font and glyph features, allowing a
//! later CPU or shader fitter to derive a policy-specific warp at draw time.
//!
//! Layout (flat f32; RGBA32F on the GPU):
//!   [0..8)   base glyph band entry
//!   [8]      normalized standard x stem width
//!   [9]      normalized standard y stem width
//!   [10]     blue-zone count
//!   [11]     normalized glyph left edge
//!   [12..]   blue zones: (ref, shoot) × count
//!   [..]     x features: count, then (pos, width, packed refs, flags) × count
//!   [..]     y features: count, then (pos, width, packed refs, flags) × count

const std = @import("std");

const render_abi = @import("abi.zig");
const autohint = @import("../font/autohint/producer.zig");
const blue = @import("../font/autohint/blue.zig");
const warp = @import("../font/autohint/warp.zig");

pub const FeatureEdge = autohint.FeatureEdge;
pub const header_floats: usize = 8;
pub const metrics_floats: usize = 4;
pub const fixed_floats: usize = header_floats + metrics_floats;
pub const floats_per_blue: usize = 2;
pub const floats_per_feature: usize = 4;

pub const WriteError = error{
    TooManyFeatures,
    TooManyBlueZones,
    BufferTooSmall,
};

/// The base glyph's band entry — everything ordinary coverage needs to locate
/// and bucket its curves in the atlas.
pub const BandEntry = struct {
    glyph_x: u16,
    glyph_y: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

/// Floats occupied by one immutable analysis record.
pub fn recordFloatCount(blue_count: usize, x_count: usize, y_count: usize) usize {
    return fixed_floats + floats_per_blue * blue_count +
        1 + floats_per_feature * x_count +
        1 + floats_per_feature * y_count;
}

pub fn blueRunOffset() usize {
    return fixed_floats;
}

pub fn xRunOffset(blue_count: usize) usize {
    return blueRunOffset() + floats_per_blue * blue_count;
}

pub fn yRunOffset(blue_count: usize, x_count: usize) usize {
    return xRunOffset(blue_count) + 1 + floats_per_feature * x_count;
}

/// Write a complete record only after validating all counts and slab bounds.
pub fn writeRecord(
    data: []f32,
    off: usize,
    be: BandEntry,
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
) WriteError!void {
    if (glyph.x.len > warp.max_knots or glyph.y.len > warp.max_knots) return error.TooManyFeatures;
    if (font.blues.len > warp.max_knots) return error.TooManyBlueZones;
    const count = recordFloatCount(font.blues.len, glyph.x.len, glyph.y.len);
    if (off > data.len or count > data.len - off) return error.BufferTooSmall;

    data[off + 0] = @floatFromInt(be.glyph_x);
    data[off + 1] = @floatFromInt(be.glyph_y);
    data[off + 2] = @bitCast(render_abi.packBandCounts(be.h_band_count, be.v_band_count));
    data[off + 3] = 0;
    data[off + 4] = be.band_scale_x;
    data[off + 5] = be.band_scale_y;
    data[off + 6] = be.band_offset_x;
    data[off + 7] = be.band_offset_y;
    data[off + 8] = font.std_x;
    data[off + 9] = font.std_y;
    data[off + 10] = @floatFromInt(font.blues.len);
    data[off + 11] = glyph.left;

    var cursor = off + blueRunOffset();
    for (font.blues) |zone| {
        data[cursor] = zone.ref;
        data[cursor + 1] = zone.shoot;
        cursor += floats_per_blue;
    }
    cursor += writeFeatureRun(data[cursor..], glyph.x);
    _ = writeFeatureRun(data[cursor..], glyph.y);
}

fn writeFeatureRun(out: []f32, features: []const FeatureEdge) usize {
    out[0] = @floatFromInt(features.len);
    for (features, 0..) |edge, i| {
        const dst = 1 + i * floats_per_feature;
        const refs = packed struct(u32) { stem: i16, blue: i16 }{ .stem = edge.stem, .blue = edge.blue };
        out[dst + 0] = edge.pos;
        out[dst + 1] = edge.width;
        const refs_bits: u32 = @bitCast(refs);
        const flags_bits: u32 = @bitCast(edge.flags);
        out[dst + 2] = @bitCast(refs_bits);
        out[dst + 3] = @bitCast(flags_bits);
    }
    return 1 + floats_per_feature * features.len;
}

pub fn readBandEntry(data: []const f32, off: usize) BandEntry {
    const counts = render_abi.unpackBandCounts(@bitCast(data[off + 2]));
    return .{
        .glyph_x = @intFromFloat(data[off + 0]),
        .glyph_y = @intFromFloat(data[off + 1]),
        .h_band_count = counts.h,
        .v_band_count = counts.v,
        .band_scale_x = data[off + 4],
        .band_scale_y = data[off + 5],
        .band_offset_x = data[off + 6],
        .band_offset_y = data[off + 7],
    };
}

pub fn fontFeatures(data: []const f32, off: usize) autohint.FontFeatures {
    const count: usize = @intFromFloat(data[off + 10]);
    const floats = data[off + blueRunOffset() ..][0 .. count * floats_per_blue];
    return .{
        .blues = std.mem.bytesAsSlice(blue.FeatureZone, std.mem.sliceAsBytes(floats)),
        .std_x = data[off + 8],
        .std_y = data[off + 9],
    };
}

pub fn glyphLeft(data: []const f32, off: usize) f32 {
    return data[off + 11];
}

/// Borrow the x-axis feature records directly from the CPU slab.
pub fn xFeatures(data: []const f32, off: usize) []const FeatureEdge {
    const blue_count: usize = @intFromFloat(data[off + 10]);
    return featureRun(data, off + xRunOffset(blue_count));
}

/// Borrow the y-axis feature records directly from the CPU slab.
pub fn yFeatures(data: []const f32, off: usize) []const FeatureEdge {
    const blue_count: usize = @intFromFloat(data[off + 10]);
    const x_off = off + xRunOffset(blue_count);
    const x_count: usize = @intFromFloat(data[x_off]);
    return featureRun(data, off + yRunOffset(blue_count, x_count));
}

fn featureRun(data: []const f32, run_off: usize) []const FeatureEdge {
    const count: usize = @intFromFloat(data[run_off]);
    const floats = data[run_off + 1 ..][0 .. count * floats_per_feature];
    return std.mem.bytesAsSlice(FeatureEdge, std.mem.sliceAsBytes(floats));
}

/// Raw shader-ABI x run: count followed by one RGBA texel per feature.
pub fn xRun(data: []const f32, off: usize) []const f32 {
    const blue_count: usize = @intFromFloat(data[off + 10]);
    const run_off = off + xRunOffset(blue_count);
    const count: usize = @intFromFloat(data[run_off]);
    return data[run_off..][0 .. 1 + floats_per_feature * count];
}

/// Raw shader-ABI y run: count followed by one RGBA texel per feature.
pub fn yRun(data: []const f32, off: usize) []const f32 {
    const blue_count: usize = @intFromFloat(data[off + 10]);
    const x_off = off + xRunOffset(blue_count);
    const x_count: usize = @intFromFloat(data[x_off]);
    const run_off = off + yRunOffset(blue_count, x_count);
    const count: usize = @intFromFloat(data[run_off]);
    return data[run_off..][0 .. 1 + floats_per_feature * count];
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "autohint record round-trips immutable features" {
    const blues = [_]blue.FeatureZone{.{ .ref = 0.48, .shoot = 0.49 }};
    const x = [_]FeatureEdge{.{ .pos = 0.1, .width = 0.08, .stem = 1, .blue = -1, .flags = .{ .round = false } }};
    const y = [_]FeatureEdge{.{ .pos = 0.5, .width = 0.07, .stem = -1, .blue = 0, .flags = .{ .round = true } }};
    const font = autohint.FontFeatures{ .blues = &blues, .std_x = 0.08, .std_y = 0.07 };
    const glyph = autohint.GlyphFeatures{ .x = &x, .y = &y, .left = 0.02 };
    const be = BandEntry{
        .glyph_x = 12,
        .glyph_y = 34,
        .h_band_count = 5,
        .v_band_count = 3,
        .band_scale_x = 1.5,
        .band_scale_y = 2.5,
        .band_offset_x = -0.25,
        .band_offset_y = 0.75,
    };

    const n = recordFloatCount(blues.len, x.len, y.len);
    const buf = try testing.allocator.alloc(f32, n + 8);
    defer testing.allocator.free(buf);
    @memset(buf, -999);
    const off: usize = 8;
    try writeRecord(buf, off, be, font, glyph);

    const back_be = readBandEntry(buf, off);
    try testing.expectEqual(be.glyph_x, back_be.glyph_x);
    try testing.expectEqual(be.v_band_count, back_be.v_band_count);
    const back_font = fontFeatures(buf, off);
    try testing.expectApproxEqAbs(font.std_x, back_font.std_x, 1e-6);
    try testing.expectEqualSlices(blue.FeatureZone, &blues, back_font.blues);
    try testing.expectApproxEqAbs(glyph.left, glyphLeft(buf, off), 1e-6);
    try testing.expectEqualSlices(FeatureEdge, &x, xFeatures(buf, off));
    try testing.expectEqualSlices(FeatureEdge, &y, yFeatures(buf, off));
}

test "autohint record rejects invalid input before mutation" {
    var buf = [_]f32{7} ** 16;
    const too_many = [_]FeatureEdge{.{ .pos = 0, .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } }} ** (warp.max_knots + 1);
    const too_many_blues = [_]blue.FeatureZone{.{ .ref = 0, .shoot = 0 }} ** (warp.max_knots + 1);
    const be = BandEntry{ .glyph_x = 1, .glyph_y = 1, .h_band_count = 1, .v_band_count = 1, .band_scale_x = 1, .band_scale_y = 1, .band_offset_x = 0, .band_offset_y = 0 };
    try testing.expectError(error.TooManyFeatures, writeRecord(&buf, 0, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &too_many, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
    try testing.expectError(error.TooManyBlueZones, writeRecord(&buf, 0, be, .{ .blues = &too_many_blues, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
    try testing.expectError(error.BufferTooSmall, writeRecord(&buf, 8, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
}
