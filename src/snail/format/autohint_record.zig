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

pub const FeatureEdge = autohint.FeatureEdge;
pub const header_floats: usize = 8;
pub const metrics_floats: usize = 4;
pub const fixed_floats: usize = header_floats + metrics_floats;
pub const floats_per_blue: usize = 2;
pub const floats_per_feature: usize = 4;

pub const WriteError = error{
    TooManyFeatures,
    TooManyBlueZones,
    InvalidAnalysis,
    InvalidBandEntry,
    RecordTooLarge,
    BufferTooSmall,
};

pub const SizeError = error{RecordTooLarge};

pub const DecodeError = error{
    BufferTooSmall,
    InvalidBandEntry,
    InvalidCount,
    InvalidScalar,
    InvalidFeature,
    NonCanonicalRecord,
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

/// Floats occupied by one immutable analysis record. Counts are accepted as
/// `usize` for allocator planning, so every operation is checked explicitly.
pub fn recordFloatCount(blue_count: usize, x_count: usize, y_count: usize) SizeError!usize {
    var count = fixed_floats;
    const blue_floats = std.math.mul(usize, floats_per_blue, blue_count) catch return error.RecordTooLarge;
    count = std.math.add(usize, count, blue_floats) catch return error.RecordTooLarge;
    count = std.math.add(usize, count, 1) catch return error.RecordTooLarge;
    const x_floats = std.math.mul(usize, floats_per_feature, x_count) catch return error.RecordTooLarge;
    count = std.math.add(usize, count, x_floats) catch return error.RecordTooLarge;
    count = std.math.add(usize, count, 1) catch return error.RecordTooLarge;
    const y_floats = std.math.mul(usize, floats_per_feature, y_count) catch return error.RecordTooLarge;
    return std.math.add(usize, count, y_floats) catch return error.RecordTooLarge;
}

/// Write a complete record only after validating all counts and slab bounds.
pub fn writeRecord(
    data: []f32,
    off: usize,
    be: BandEntry,
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
) WriteError!void {
    if (glyph.x.len > autohint.max_features_per_axis or glyph.y.len > autohint.max_features_per_axis) return error.TooManyFeatures;
    if (font.blues.len > autohint.max_features_per_axis) return error.TooManyBlueZones;
    if (!validBandEntry(be)) return error.InvalidBandEntry;
    if (!validFontFeatures(font) or !std.math.isFinite(glyph.left) or
        !validFeatureRun(glyph.x, font.blues.len) or
        !validFeatureRun(glyph.y, font.blues.len)) return error.InvalidAnalysis;
    const count = recordFloatCount(font.blues.len, glyph.x.len, glyph.y.len) catch return error.RecordTooLarge;
    if (off > data.len or count > data.len - off) return error.BufferTooSmall;

    data[off + 0] = @floatFromInt(be.glyph_x);
    data[off + 1] = @floatFromInt(be.glyph_y);
    data[off + 2] = @bitCast(render_abi.packBandCounts(be.h_band_count, be.v_band_count).?);
    data[off + 3] = 0;
    data[off + 4] = be.band_scale_x;
    data[off + 5] = be.band_scale_y;
    data[off + 6] = be.band_offset_x;
    data[off + 7] = be.band_offset_y;
    data[off + 8] = font.std_x;
    data[off + 9] = font.std_y;
    data[off + 10] = @floatFromInt(font.blues.len);
    data[off + 11] = glyph.left;

    var cursor = off + fixed_floats;
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

/// Allocation-free, validated borrowed view of one record. Call `decode` once
/// at a trust boundary, then pass these slices through hot fitting paths.
pub const DecodedRecord = struct {
    band_entry: BandEntry,
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
    float_count: usize,
};

/// Decode a caller-owned record without allocation. Every length, count,
/// integer conversion, scalar, and feature reference is validated before a
/// borrowed slice is returned.
pub fn decode(data: []const f32, off: usize) DecodeError!DecodedRecord {
    if (off > data.len or fixed_floats > data.len - off) return error.BufferTooSmall;
    const header = data[off..][0..fixed_floats];
    const glyph_x = exactU16(header[0]) orelse return error.InvalidBandEntry;
    const glyph_y = exactU16(header[1]) orelse return error.InvalidBandEntry;
    const counts = render_abi.unpackBandCounts(@bitCast(header[2])) orelse return error.InvalidBandEntry;
    if (counts.h > 16 or counts.v > 16) return error.InvalidBandEntry;
    if (@as(u32, @bitCast(header[3])) != 0) return error.NonCanonicalRecord;
    for (header[4..10]) |value| if (!std.math.isFinite(value)) return error.InvalidScalar;
    if (header[8] < 0 or header[9] < 0 or !std.math.isFinite(header[11])) return error.InvalidScalar;

    const blue_count = exactCount(header[10]) orelse return error.InvalidCount;
    var cursor = off + fixed_floats;
    const blue_float_count = blue_count * floats_per_blue;
    const blue_floats = try take(data, &cursor, blue_float_count);
    const blues = std.mem.bytesAsSlice(blue.FeatureZone, std.mem.sliceAsBytes(blue_floats));
    for (blues) |zone| {
        if (!std.math.isFinite(zone.ref) or !std.math.isFinite(zone.shoot)) return error.InvalidScalar;
    }

    const x = try decodeFeatureRun(data, &cursor, blue_count);
    const y = try decodeFeatureRun(data, &cursor, blue_count);
    return .{
        .band_entry = .{
            .glyph_x = glyph_x,
            .glyph_y = glyph_y,
            .h_band_count = counts.h,
            .v_band_count = counts.v,
            .band_scale_x = header[4],
            .band_scale_y = header[5],
            .band_offset_x = header[6],
            .band_offset_y = header[7],
        },
        .font = .{ .blues = blues, .std_x = header[8], .std_y = header[9] },
        .glyph = .{ .x = x, .y = y, .left = header[11] },
        .float_count = cursor - off,
    };
}

fn exactU16(value: f32) ?u16 {
    if (!std.math.isFinite(value) or value < 0 or value > std.math.maxInt(u16) or @trunc(value) != value) return null;
    return @intFromFloat(value);
}

fn exactCount(value: f32) ?usize {
    if (!std.math.isFinite(value) or value < 0 or value > autohint.max_features_per_axis or @trunc(value) != value) return null;
    return @intFromFloat(value);
}

fn take(data: []const f32, cursor: *usize, count: usize) DecodeError![]const f32 {
    if (cursor.* > data.len or count > data.len - cursor.*) return error.BufferTooSmall;
    const result = data[cursor.*..][0..count];
    cursor.* += count;
    return result;
}

fn decodeFeatureRun(data: []const f32, cursor: *usize, blue_count: usize) DecodeError![]const FeatureEdge {
    const count_float = (try take(data, cursor, 1))[0];
    const count = exactCount(count_float) orelse return error.InvalidCount;
    const floats = try take(data, cursor, count * floats_per_feature);
    const features = std.mem.bytesAsSlice(FeatureEdge, std.mem.sliceAsBytes(floats));
    if (!validFeatureRun(features, blue_count)) return error.InvalidFeature;
    return features;
}

fn validBandEntry(be: BandEntry) bool {
    return be.h_band_count > 0 and be.h_band_count <= 16 and
        be.v_band_count > 0 and be.v_band_count <= 16 and
        std.math.isFinite(be.band_scale_x) and std.math.isFinite(be.band_scale_y) and
        std.math.isFinite(be.band_offset_x) and std.math.isFinite(be.band_offset_y);
}

fn validFontFeatures(font: autohint.FontFeatures) bool {
    if (!std.math.isFinite(font.std_x) or font.std_x < 0 or
        !std.math.isFinite(font.std_y) or font.std_y < 0) return false;
    for (font.blues) |zone| {
        if (!std.math.isFinite(zone.ref) or !std.math.isFinite(zone.shoot)) return false;
    }
    return true;
}

fn validFeatureRun(features: []const FeatureEdge, blue_count: usize) bool {
    for (features, 0..) |feature, i| {
        if (!std.math.isFinite(feature.pos) or !std.math.isFinite(feature.width) or feature.width < 0 or
            feature.stem < -1 or feature.blue < -1 or feature.flags._reserved != 0 or
            (feature.blue >= 0 and @as(usize, @intCast(feature.blue)) >= blue_count)) return false;
        if (feature.flags.semantics_resolved) {
            const grid_companion = feature.flags.grid_companion;
            const blue_companion = feature.flags.blue_companion;
            if ((grid_companion < 62 and (grid_companion >= features.len or grid_companion == i)) or
                (blue_companion < 62 and (blue_companion >= features.len or blue_companion == i))) return false;
        } else if (feature.flags.grid_companion != 63 or feature.flags.blue_companion != 63) {
            return false;
        }
        if (feature.stem >= 0) {
            const partner_index: usize = @intCast(feature.stem);
            if (partner_index >= features.len or partner_index == i) return false;
            const partner = features[partner_index];
            if (partner.stem != @as(i16, @intCast(i)) or
                !std.math.isFinite(partner.pos) or partner.pos == feature.pos or
                !std.math.isFinite(partner.width) or partner.width != feature.width) return false;
        }
    }
    return true;
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "autohint record round-trips immutable features" {
    const blues = [_]blue.FeatureZone{.{ .ref = 0.48, .shoot = 0.49 }};
    const x = [_]FeatureEdge{.{ .pos = 0.1, .width = 0.08, .stem = -1, .blue = -1, .flags = .{ .round = false } }};
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

    const n = try recordFloatCount(blues.len, x.len, y.len);
    const buf = try testing.allocator.alloc(f32, n + 8);
    defer testing.allocator.free(buf);
    @memset(buf, -999);
    const off: usize = 8;
    try writeRecord(buf, off, be, font, glyph);

    const decoded = try decode(buf, off);
    const back_be = decoded.band_entry;
    try testing.expectEqual(be.glyph_x, back_be.glyph_x);
    try testing.expectEqual(be.v_band_count, back_be.v_band_count);
    const back_font = decoded.font;
    try testing.expectApproxEqAbs(font.std_x, back_font.std_x, 1e-6);
    try testing.expectEqualSlices(blue.FeatureZone, &blues, back_font.blues);
    try testing.expectApproxEqAbs(glyph.left, decoded.glyph.left, 1e-6);
    try testing.expectEqualSlices(FeatureEdge, &x, decoded.glyph.x);
    try testing.expectEqualSlices(FeatureEdge, &y, decoded.glyph.y);
    try testing.expectEqual(n, decoded.float_count);
}

test "autohint record rejects invalid input before mutation" {
    var buf = [_]f32{7} ** 16;
    const too_many = [_]FeatureEdge{.{ .pos = 0, .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } }} ** (autohint.max_features_per_axis + 1);
    const too_many_blues = [_]blue.FeatureZone{.{ .ref = 0, .shoot = 0 }} ** (autohint.max_features_per_axis + 1);
    const be = BandEntry{ .glyph_x = 1, .glyph_y = 1, .h_band_count = 1, .v_band_count = 1, .band_scale_x = 1, .band_scale_y = 1, .band_offset_x = 0, .band_offset_y = 0 };
    try testing.expectError(error.TooManyFeatures, writeRecord(&buf, 0, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &too_many, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
    try testing.expectError(error.TooManyBlueZones, writeRecord(&buf, 0, be, .{ .blues = &too_many_blues, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
    try testing.expectError(error.BufferTooSmall, writeRecord(&buf, 8, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &([_]f32{7} ** 16), &buf);
}

test "record sizing rejects every overflow position" {
    const max = std.math.maxInt(usize);
    try testing.expectError(error.RecordTooLarge, recordFloatCount(max, 0, 0));
    try testing.expectError(error.RecordTooLarge, recordFloatCount(0, max, 0));
    try testing.expectError(error.RecordTooLarge, recordFloatCount(0, 0, max));
}

test "decoder is total for short and hostile caller records" {
    var buf = [_]f32{0} ** 32;
    try testing.expectError(error.BufferTooSmall, decode(&buf, std.math.maxInt(usize)));
    for (0..fixed_floats) |len| {
        try testing.expectError(error.BufferTooSmall, decode(buf[0..len], 0));
    }

    const be = BandEntry{ .glyph_x = 1, .glyph_y = 2, .h_band_count = 1, .v_band_count = 1, .band_scale_x = 1, .band_scale_y = 1, .band_offset_x = 0, .band_offset_y = 0 };
    try writeRecord(&buf, 0, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 });
    const valid_count = (try decode(&buf, 0)).float_count;

    var malformed = buf;
    malformed[0] = std.math.nan(f32);
    try testing.expectError(error.InvalidBandEntry, decode(&malformed, 0));
    malformed = buf;
    malformed[2] = @bitCast(@as(u32, 0x0000ffff));
    try testing.expectError(error.InvalidBandEntry, decode(&malformed, 0));
    malformed = buf;
    malformed[3] = -0.0;
    try testing.expectError(error.NonCanonicalRecord, decode(&malformed, 0));
    malformed = buf;
    malformed[10] = std.math.inf(f32);
    try testing.expectError(error.InvalidCount, decode(&malformed, 0));
    malformed = buf;
    malformed[10] = 0.5;
    try testing.expectError(error.InvalidCount, decode(&malformed, 0));
    malformed = buf;
    malformed[10] = @floatFromInt(autohint.max_features_per_axis + 1);
    try testing.expectError(error.InvalidCount, decode(&malformed, 0));
    try testing.expectError(error.BufferTooSmall, decode(buf[0 .. valid_count - 1], 0));

    const blues = [_]blue.FeatureZone{.{ .ref = 0.4, .shoot = 0.41 }};
    const edges = [_]FeatureEdge{.{ .pos = 0.2, .width = 0.1, .stem = -1, .blue = 0, .flags = .{ .round = false } }};
    var full = [_]f32{0} ** 32;
    try writeRecord(&full, 0, be, .{ .blues = &blues, .std_x = 0.1, .std_y = 0.1 }, .{ .x = &edges, .y = &edges, .left = 0 });
    const full_count = (try decode(&full, 0)).float_count;
    for (0..full_count) |len| {
        try testing.expectError(error.BufferTooSmall, decode(full[0..len], 0));
    }
    malformed = full;
    malformed[12] = std.math.nan(f32);
    try testing.expectError(error.InvalidScalar, decode(&malformed, 0));
    malformed = full;
    malformed[14] = std.math.nan(f32);
    try testing.expectError(error.InvalidCount, decode(&malformed, 0));
    malformed = full;
    malformed[15] = std.math.inf(f32);
    try testing.expectError(error.InvalidFeature, decode(&malformed, 0));
    malformed = full;
    malformed[18] = @bitCast(@as(u32, 1) << 16);
    try testing.expectError(error.InvalidFeature, decode(&malformed, 0));
    malformed = full;
    malformed[18] = @bitCast((@as(u32, 1) << 2) | (@as(u32, 5) << 4) | (@as(u32, 62) << 10));
    try testing.expectError(error.InvalidFeature, decode(&malformed, 0));
}

test "writer rejects invalid analysis before mutation" {
    var buf = [_]f32{7} ** 32;
    const original = buf;
    const be = BandEntry{ .glyph_x = 1, .glyph_y = 2, .h_band_count = 1, .v_band_count = 1, .band_scale_x = 1, .band_scale_y = 1, .band_offset_x = 0, .band_offset_y = 0 };
    const invalid = [_]FeatureEdge{.{ .pos = std.math.nan(f32), .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } }};
    try testing.expectError(error.InvalidAnalysis, writeRecord(&buf, 0, be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &invalid, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &original, &buf);
    var invalid_be = be;
    invalid_be.h_band_count = 0;
    try testing.expectError(error.InvalidBandEntry, writeRecord(&buf, 0, invalid_be, .{ .blues = &.{}, .std_x = 0, .std_y = 0 }, .{ .x = &.{}, .y = &.{}, .left = 0 }));
    try testing.expectEqualSlices(f32, &original, &buf);
}
