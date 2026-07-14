const std = @import("std");
const testing = std.testing;

pub const PolicyError = error{
    InvalidEncoding,
    InvalidThreshold,
    PositioningRequiresAlignment,
    OvershootRequiresBlueZones,
};

pub const StemWidth = union(enum) {
    natural,
    light: struct { std_snap_ratio: f32, max_px: f32 },
    full: struct { std_snap_ratio: f32 },
};

pub const StemPositioning = enum {
    independent,
    relative,
};

pub const Overshoot = union(enum) {
    preserve,
    suppress_below_px: f32,
};

pub const OutlineRegistration = enum {
    none,
    left_round_outline,
};

pub const XAlignment = enum {
    none,
    grid,
};

pub const YAlignment = enum {
    none,
    grid,
    blue_zones,
};

pub const XPolicy = struct {
    @"align": XAlignment = .none,
    stem_width: StemWidth = .natural,
    positioning: StemPositioning = .independent,
    registration: OutlineRegistration = .none,
};

pub const YPolicy = struct {
    @"align": YAlignment = .none,
    stem_width: StemWidth = .natural,
    overshoot: Overshoot = .preserve,
};

/// How the whole-glyph warp backs off at large ppem. Autohinting is a
/// small-size tool: above a size, analytic AA already renders stems and curves
/// cleanly, and grid-fitting there only flattens round tops / blobs corners.
pub const Fade = union(enum) {
    /// Hint fully at every ppem (no large-size fallback).
    none,
    /// Blend the warp toward identity between `start_px` (full hinting) and
    /// `full_px` (no warp) — whole ppem, 0..127, `start_px <= full_px`.
    ppem_range: struct { start_px: f32, full_px: f32 },
};

pub const AutohintPolicy = struct {
    x: XPolicy = .{},
    y: YPolicy = .{},
    fade: Fade = .none,

    pub fn validate(self: AutohintPolicy) PolicyError!void {
        return policyValidate(self);
    }

    pub fn pack(self: AutohintPolicy) [7]u32 {
        return policyPack(self);
    }

    pub fn unpack(words: [7]u32) PolicyError!AutohintPolicy {
        return policyUnpack(words);
    }
};

pub fn validate(policy: AutohintPolicy) PolicyError!void {
    return policyValidate(policy);
}

pub fn pack(policy: AutohintPolicy) [7]u32 {
    return policyPack(policy);
}

pub fn unpack(words: [7]u32) PolicyError!AutohintPolicy {
    return policyUnpack(words);
}

fn validThreshold(value: f32) bool {
    return std.math.isFinite(value) and value >= 0;
}

fn validateStemWidth(stem_width: StemWidth) PolicyError!void {
    switch (stem_width) {
        .natural => {},
        .light => |light| {
            if (!validThreshold(light.std_snap_ratio) or !validThreshold(light.max_px)) {
                return error.InvalidThreshold;
            }
        },
        .full => |full| {
            if (!validThreshold(full.std_snap_ratio)) return error.InvalidThreshold;
        },
    }
}

fn policyValidate(policy: AutohintPolicy) PolicyError!void {
    try validateStemWidth(policy.x.stem_width);
    try validateStemWidth(policy.y.stem_width);

    if (policy.x.positioning == .relative and policy.x.@"align" == .none) {
        return error.PositioningRequiresAlignment;
    }

    switch (policy.y.overshoot) {
        .preserve => {},
        .suppress_below_px => |threshold| {
            if (!validThreshold(threshold)) return error.InvalidThreshold;
            if (policy.y.@"align" != .blue_zones) return error.OvershootRequiresBlueZones;
        },
    }

    switch (policy.fade) {
        .none => {},
        .ppem_range => |r| {
            if (!validThreshold(r.start_px) or !validThreshold(r.full_px) or
                r.start_px > fade_max_px or r.full_px > fade_max_px or r.start_px > r.full_px)
            {
                return error.InvalidThreshold;
            }
        },
    }
}

const x_align_shift = 0;
const x_stem_shift = 2;
const x_positioning_shift = 4;
const x_registration_shift = 6;
const y_align_shift = 0;
const y_stem_shift = 2;
const y_overshoot_shift = 4;
const two_bit_mask: u32 = 0b11;
// Whole-glyph fade bit-packs into word[0]'s spare bits (the x-config fields only
// use bits 0-7) so the on-wire policy stays 7 words: enabled flag + two 7-bit
// whole-ppem thresholds (0..127). Kept integer because a fade threshold never
// needs sub-pixel precision.
const fade_max_px: f32 = 127;
const fade_enabled_shift: u5 = 8;
const fade_start_shift: u5 = 9;
const fade_full_shift: u5 = 16;
const seven_bit_mask: u32 = 0x7F;
const fade_mask: u32 = (@as(u32, 1) << fade_enabled_shift) |
    (seven_bit_mask << fade_start_shift) |
    (seven_bit_mask << fade_full_shift);
const x_config_mask: u32 = (two_bit_mask << x_align_shift) |
    (two_bit_mask << x_stem_shift) |
    (two_bit_mask << x_positioning_shift) |
    (two_bit_mask << x_registration_shift) |
    fade_mask;
const y_config_mask: u32 = (two_bit_mask << y_align_shift) |
    (two_bit_mask << y_stem_shift) |
    (two_bit_mask << y_overshoot_shift);

fn stemWidthTag(stem_width: StemWidth) u32 {
    return switch (stem_width) {
        .natural => 0,
        .light => 1,
        .full => 2,
    };
}

fn policyPack(policy: AutohintPolicy) [7]u32 {
    var words = [_]u32{0} ** 7;

    words[0] = (@as(u32, @intFromEnum(policy.x.@"align")) << x_align_shift) |
        (stemWidthTag(policy.x.stem_width) << x_stem_shift) |
        (@as(u32, @intFromEnum(policy.x.positioning)) << x_positioning_shift) |
        (@as(u32, @intFromEnum(policy.x.registration)) << x_registration_shift) |
        packFade(policy.fade);
    words[1] = (@as(u32, @intFromEnum(policy.y.@"align")) << y_align_shift) |
        (stemWidthTag(policy.y.stem_width) << y_stem_shift) |
        ((switch (policy.y.overshoot) {
            .preserve => @as(u32, 0),
            .suppress_below_px => @as(u32, 1),
        }) << y_overshoot_shift);

    switch (policy.x.stem_width) {
        .natural => {},
        .light => |light| {
            words[2] = @bitCast(light.std_snap_ratio);
            words[3] = @bitCast(light.max_px);
        },
        .full => |full| words[2] = @bitCast(full.std_snap_ratio),
    }
    switch (policy.y.stem_width) {
        .natural => {},
        .light => |light| {
            words[4] = @bitCast(light.std_snap_ratio);
            words[5] = @bitCast(light.max_px);
        },
        .full => |full| words[4] = @bitCast(full.std_snap_ratio),
    }
    switch (policy.y.overshoot) {
        .preserve => {},
        .suppress_below_px => |threshold| words[6] = @bitCast(threshold),
    }

    return words;
}

fn field(word: u32, shift: u5) u32 {
    return (word >> shift) & two_bit_mask;
}

fn packFade(fade: Fade) u32 {
    return switch (fade) {
        .none => 0,
        .ppem_range => |r| (@as(u32, 1) << fade_enabled_shift) |
            ((@as(u32, @intFromFloat(@round(r.start_px))) & seven_bit_mask) << fade_start_shift) |
            ((@as(u32, @intFromFloat(@round(r.full_px))) & seven_bit_mask) << fade_full_shift),
    };
}

fn unpackFade(word: u32) Fade {
    if ((word >> fade_enabled_shift) & 1 == 0) return .none;
    return .{ .ppem_range = .{
        .start_px = @floatFromInt((word >> fade_start_shift) & seven_bit_mask),
        .full_px = @floatFromInt((word >> fade_full_shift) & seven_bit_mask),
    } };
}

fn decodeStemWidth(tag: u32, ratio_word: u32, max_word: u32) PolicyError!StemWidth {
    return switch (tag) {
        0 => .natural,
        1 => .{ .light = .{
            .std_snap_ratio = @bitCast(ratio_word),
            .max_px = @bitCast(max_word),
        } },
        2 => .{ .full = .{ .std_snap_ratio = @bitCast(ratio_word) } },
        else => error.InvalidEncoding,
    };
}

fn policyUnpack(words: [7]u32) PolicyError!AutohintPolicy {
    if (words[0] & ~x_config_mask != 0 or words[1] & ~y_config_mask != 0) {
        return error.InvalidEncoding;
    }

    const x_align: XAlignment = switch (field(words[0], x_align_shift)) {
        0 => .none,
        1 => .grid,
        else => return error.InvalidEncoding,
    };
    const x_positioning: StemPositioning = switch (field(words[0], x_positioning_shift)) {
        0 => .independent,
        1 => .relative,
        else => return error.InvalidEncoding,
    };
    const x_registration: OutlineRegistration = switch (field(words[0], x_registration_shift)) {
        0 => .none,
        1 => .left_round_outline,
        else => return error.InvalidEncoding,
    };
    const y_align: YAlignment = switch (field(words[1], y_align_shift)) {
        0 => .none,
        1 => .grid,
        2 => .blue_zones,
        else => return error.InvalidEncoding,
    };
    const overshoot: Overshoot = switch (field(words[1], y_overshoot_shift)) {
        0 => .preserve,
        1 => .{ .suppress_below_px = @bitCast(words[6]) },
        else => return error.InvalidEncoding,
    };

    const policy: AutohintPolicy = .{
        .x = .{
            .@"align" = x_align,
            .stem_width = try decodeStemWidth(field(words[0], x_stem_shift), words[2], words[3]),
            .positioning = x_positioning,
            .registration = x_registration,
        },
        .y = .{
            .@"align" = y_align,
            .stem_width = try decodeStemWidth(field(words[1], y_stem_shift), words[4], words[5]),
            .overshoot = overshoot,
        },
        .fade = unpackFade(words[0]),
    };
    try policy.validate();
    return policy;
}

test "policy round-trips without named presets" {
    const p: AutohintPolicy = .{
        .x = .{
            .@"align" = .grid,
            .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
            .positioning = .relative,
            .registration = .left_round_outline,
        },
        .y = .{
            .@"align" = .blue_zones,
            .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = 1.6 } },
            .overshoot = .{ .suppress_below_px = 0.5 },
        },
        .fade = .{ .ppem_range = .{ .start_px = 16, .full_px = 26 } },
    };
    try p.validate();
    try testing.expectEqual(@as(usize, 7), p.pack().len);
    try testing.expectEqualDeep(p, try AutohintPolicy.unpack(p.pack()));
}

test "fade bit-packs into word 0 and round-trips; default is none" {
    // Whole-ppem thresholds survive the 7-bit fields; default policy has no fade.
    const faded: AutohintPolicy = .{ .fade = .{ .ppem_range = .{ .start_px = 18, .full_px = 30 } } };
    try faded.validate();
    try testing.expectEqualDeep(faded, try AutohintPolicy.unpack(faded.pack()));
    try testing.expectEqual(Fade.none, (AutohintPolicy{}).fade);
    // Fade lives in word 0's spare bits, so the float payload words stay zero.
    try testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0, 0 }, faded.pack()[2..]);
    // Reject an out-of-range or inverted range.
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .fade = .{ .ppem_range = .{ .start_px = 30, .full_px = 18 } },
    }).validate());
}

test "all five simultaneous float payloads round-trip exactly" {
    const p: AutohintPolicy = .{
        .x = .{
            .@"align" = .grid,
            .stem_width = .{ .light = .{
                .std_snap_ratio = @bitCast(@as(u32, 0x3eaaaaab)),
                .max_px = @bitCast(@as(u32, 0x41234567)),
            } },
        },
        .y = .{
            .@"align" = .blue_zones,
            .stem_width = .{ .light = .{
                .std_snap_ratio = @bitCast(@as(u32, 0x3f012345)),
                .max_px = @bitCast(@as(u32, 0x40abcdef)),
            } },
            .overshoot = .{ .suppress_below_px = @bitCast(@as(u32, 0x3d987654)) },
        },
    };
    const words = p.pack();
    try testing.expectEqualSlices(u32, &.{ 0x3eaaaaab, 0x41234567, 0x3f012345, 0x40abcdef, 0x3d987654 }, words[2..]);
    try testing.expectEqualDeep(p, try AutohintPolicy.unpack(words));
}

test "dependent operations reject missing alignment" {
    const p: AutohintPolicy = .{ .x = .{ .positioning = .relative } };
    try testing.expectError(error.PositioningRequiresAlignment, p.validate());
}

test "overshoot suppression requires blue zones" {
    const p: AutohintPolicy = .{ .y = .{ .@"align" = .grid, .overshoot = .{ .suppress_below_px = 0.5 } } };
    try testing.expectError(error.OvershootRequiresBlueZones, p.validate());
}

test "thresholds must be finite and non-negative" {
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .x = .{ .stem_width = .{ .full = .{ .std_snap_ratio = -0.1 } } },
    }).validate());
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .y = .{ .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = std.math.inf(f32) } } },
    }).validate());
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .y = .{ .@"align" = .blue_zones, .overshoot = .{ .suppress_below_px = std.math.nan(f32) } },
    }).validate());
}

test "unpack rejects reserved configuration encodings" {
    var words = (AutohintPolicy{}).pack();
    words[0] |= @as(u32, 3) << x_stem_shift;
    try testing.expectError(error.InvalidEncoding, AutohintPolicy.unpack(words));

    words = (AutohintPolicy{}).pack();
    words[1] |= @as(u32, 1) << 31;
    try testing.expectError(error.InvalidEncoding, unpack(words));
}
