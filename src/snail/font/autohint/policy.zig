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

    /// Validate and encode this policy for the draw-instance ABI. Numeric
    /// thresholds use IEEE-754 binary16; callers therefore get a typed error
    /// instead of an infinity when a finite f32 is outside that format.
    pub fn pack(self: AutohintPolicy) PolicyError![4]u32 {
        try self.validate();
        return policyPack(self);
    }

    pub fn unpack(words: [4]u32) PolicyError!AutohintPolicy {
        return policyUnpack(words);
    }
};

pub fn validate(policy: AutohintPolicy) PolicyError!void {
    return policyValidate(policy);
}

pub fn pack(policy: AutohintPolicy) PolicyError![4]u32 {
    return policy.pack();
}

pub fn unpack(words: [4]u32) PolicyError!AutohintPolicy {
    return policyUnpack(words);
}

const max_packed_threshold: f32 = std.math.floatMax(f16);

fn validThreshold(value: f32) bool {
    return std.math.isFinite(value) and value >= 0 and value <= max_packed_threshold;
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
                r.start_px > fade_max_px or r.full_px > fade_max_px or r.start_px > r.full_px or
                @trunc(r.start_px) != r.start_px or @trunc(r.full_px) != r.full_px)
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
const y_align_shift = 8;
const y_stem_shift = 10;
const y_overshoot_shift = 12;
const two_bit_mask: u32 = 0b11;
// All enum/configuration state and the integer-only fade range share word 0.
// The other three words contain five binary16 thresholds, leaving the upper
// half of word 3 reserved for future ABI-compatible policy data.
const fade_max_px: f32 = 127;
const fade_enabled_shift: u5 = 14;
const fade_start_shift: u5 = 15;
const fade_full_shift: u5 = 22;
const seven_bit_mask: u32 = 0x7F;
const fade_mask: u32 = (@as(u32, 1) << fade_enabled_shift) |
    (seven_bit_mask << fade_start_shift) |
    (seven_bit_mask << fade_full_shift);
const config_mask: u32 = (two_bit_mask << x_align_shift) |
    (two_bit_mask << x_stem_shift) |
    (two_bit_mask << x_positioning_shift) |
    (two_bit_mask << x_registration_shift) |
    (two_bit_mask << y_align_shift) |
    (two_bit_mask << y_stem_shift) |
    (two_bit_mask << y_overshoot_shift) |
    fade_mask;

fn stemWidthTag(stem_width: StemWidth) u32 {
    return switch (stem_width) {
        .natural => 0,
        .light => 1,
        .full => 2,
    };
}

fn f16Bits(value: f32) u16 {
    return @bitCast(@as(f16, @floatCast(value)));
}

fn f16Value(bits: u16) f32 {
    return @floatCast(@as(f16, @bitCast(bits)));
}

fn packHalf2(lo: f32, hi: f32) u32 {
    return @as(u32, f16Bits(lo)) | (@as(u32, f16Bits(hi)) << 16);
}

fn halfLo(word: u32) f32 {
    return f16Value(@intCast(word & 0xffff));
}

fn halfHi(word: u32) f32 {
    return f16Value(@intCast(word >> 16));
}

fn policyPack(policy: AutohintPolicy) [4]u32 {
    var words = [_]u32{0} ** 4;

    words[0] = (@as(u32, @intFromEnum(policy.x.@"align")) << x_align_shift) |
        (stemWidthTag(policy.x.stem_width) << x_stem_shift) |
        (@as(u32, @intFromEnum(policy.x.positioning)) << x_positioning_shift) |
        (@as(u32, @intFromEnum(policy.x.registration)) << x_registration_shift) |
        (@as(u32, @intFromEnum(policy.y.@"align")) << y_align_shift) |
        (stemWidthTag(policy.y.stem_width) << y_stem_shift) |
        ((switch (policy.y.overshoot) {
            .preserve => @as(u32, 0),
            .suppress_below_px => @as(u32, 1),
        }) << y_overshoot_shift) |
        packFade(policy.fade);

    var x_ratio: f32 = 0;
    var x_max: f32 = 0;
    var y_ratio: f32 = 0;
    var y_max: f32 = 0;
    var overshoot: f32 = 0;

    switch (policy.x.stem_width) {
        .natural => {},
        .light => |light| {
            x_ratio = light.std_snap_ratio;
            x_max = light.max_px;
        },
        .full => |full| x_ratio = full.std_snap_ratio,
    }
    switch (policy.y.stem_width) {
        .natural => {},
        .light => |light| {
            y_ratio = light.std_snap_ratio;
            y_max = light.max_px;
        },
        .full => |full| y_ratio = full.std_snap_ratio,
    }
    switch (policy.y.overshoot) {
        .preserve => {},
        .suppress_below_px => |threshold| overshoot = threshold,
    }

    words[1] = packHalf2(x_ratio, x_max);
    words[2] = packHalf2(y_ratio, y_max);
    words[3] = @as(u32, f16Bits(overshoot));

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

fn decodeStemWidth(tag: u32, ratio: f32, max_px: f32) PolicyError!StemWidth {
    return switch (tag) {
        0 => .natural,
        1 => .{ .light = .{
            .std_snap_ratio = ratio,
            .max_px = max_px,
        } },
        2 => .{ .full = .{ .std_snap_ratio = ratio } },
        else => error.InvalidEncoding,
    };
}

fn policyUnpack(words: [4]u32) PolicyError!AutohintPolicy {
    if (words[0] & ~config_mask != 0 or words[3] >> 16 != 0) {
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
    const y_align: YAlignment = switch (field(words[0], y_align_shift)) {
        0 => .none,
        1 => .grid,
        2 => .blue_zones,
        else => return error.InvalidEncoding,
    };
    const overshoot: Overshoot = switch (field(words[0], y_overshoot_shift)) {
        0 => .preserve,
        1 => .{ .suppress_below_px = halfLo(words[3]) },
        else => return error.InvalidEncoding,
    };

    const policy: AutohintPolicy = .{
        .x = .{
            .@"align" = x_align,
            .stem_width = try decodeStemWidth(field(words[0], x_stem_shift), halfLo(words[1]), halfHi(words[1])),
            .positioning = x_positioning,
            .registration = x_registration,
        },
        .y = .{
            .@"align" = y_align,
            .stem_width = try decodeStemWidth(field(words[0], y_stem_shift), halfLo(words[2]), halfHi(words[2])),
            .overshoot = overshoot,
        },
        .fade = unpackFade(words[0]),
    };
    try policy.validate();
    if (!std.mem.eql(u32, &words, &policyPack(policy))) return error.InvalidEncoding;
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
    const words = try p.pack();
    try testing.expectEqual(@as(usize, 4), words.len);
    const decoded = try AutohintPolicy.unpack(words);
    try expectPolicyApproxEq(p, decoded);
}

test "fade bit-packs into word 0 and round-trips; default is none" {
    // Whole-ppem thresholds survive the 7-bit fields; default policy has no fade.
    const faded: AutohintPolicy = .{ .fade = .{ .ppem_range = .{ .start_px = 18, .full_px = 30 } } };
    try faded.validate();
    const words = try faded.pack();
    try testing.expectEqualDeep(faded, try AutohintPolicy.unpack(words));
    try testing.expectEqual(Fade.none, (AutohintPolicy{}).fade);
    // Fade lives in word 0; all binary16 payload words stay zero.
    try testing.expectEqualSlices(u32, &.{ 0, 0, 0 }, words[1..]);
    // Reject an out-of-range or inverted range.
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .fade = .{ .ppem_range = .{ .start_px = 30, .full_px = 18 } },
    }).validate());
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .fade = .{ .ppem_range = .{ .start_px = 18.5, .full_px = 30 } },
    }).validate());
}

fn thresholdTolerance(value: f32) f32 {
    // Binary16 round-to-nearest is within half an ULP. This slightly looser
    // bound covers subnormals and makes the quantization contract obvious.
    return @max(@abs(value) / 1024.0, 0x1p-24);
}

fn expectPolicyApproxEq(expected: AutohintPolicy, actual: AutohintPolicy) !void {
    try testing.expectEqual(expected.x.@"align", actual.x.@"align");
    try testing.expectEqual(expected.x.positioning, actual.x.positioning);
    try testing.expectEqual(expected.x.registration, actual.x.registration);
    try testing.expectEqual(expected.y.@"align", actual.y.@"align");
    try testing.expectEqual(expected.fade, actual.fade);
    switch (expected.x.stem_width) {
        .natural => try testing.expectEqual(StemWidth.natural, actual.x.stem_width),
        .light => |e| switch (actual.x.stem_width) {
            .light => |a| {
                try testing.expectApproxEqAbs(e.std_snap_ratio, a.std_snap_ratio, thresholdTolerance(e.std_snap_ratio));
                try testing.expectApproxEqAbs(e.max_px, a.max_px, thresholdTolerance(e.max_px));
            },
            else => return error.TestExpectedEqual,
        },
        .full => |e| switch (actual.x.stem_width) {
            .full => |a| try testing.expectApproxEqAbs(e.std_snap_ratio, a.std_snap_ratio, thresholdTolerance(e.std_snap_ratio)),
            else => return error.TestExpectedEqual,
        },
    }
    switch (expected.y.stem_width) {
        .natural => try testing.expectEqual(StemWidth.natural, actual.y.stem_width),
        .light => |e| switch (actual.y.stem_width) {
            .light => |a| {
                try testing.expectApproxEqAbs(e.std_snap_ratio, a.std_snap_ratio, thresholdTolerance(e.std_snap_ratio));
                try testing.expectApproxEqAbs(e.max_px, a.max_px, thresholdTolerance(e.max_px));
            },
            else => return error.TestExpectedEqual,
        },
        .full => |e| switch (actual.y.stem_width) {
            .full => |a| try testing.expectApproxEqAbs(e.std_snap_ratio, a.std_snap_ratio, thresholdTolerance(e.std_snap_ratio)),
            else => return error.TestExpectedEqual,
        },
    }
    switch (expected.y.overshoot) {
        .preserve => try testing.expectEqual(Overshoot.preserve, actual.y.overshoot),
        .suppress_below_px => |e| switch (actual.y.overshoot) {
            .suppress_below_px => |a| try testing.expectApproxEqAbs(e, a, thresholdTolerance(e)),
            else => return error.TestExpectedEqual,
        },
    }
}

test "all five simultaneous float payloads round-trip within binary16 error" {
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
    const words = try p.pack();
    try testing.expectEqual(@as(u32, 0), words[3] >> 16);
    try expectPolicyApproxEq(p, try AutohintPolicy.unpack(words));
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
    try testing.expectError(error.InvalidThreshold, (AutohintPolicy{
        .x = .{ .stem_width = .{ .full = .{ .std_snap_ratio = 65505 } } },
    }).pack());
}

test "unpack rejects reserved configuration encodings" {
    var words = try (AutohintPolicy{}).pack();
    words[0] |= @as(u32, 3) << x_stem_shift;
    try testing.expectError(error.InvalidEncoding, AutohintPolicy.unpack(words));

    words = try (AutohintPolicy{}).pack();
    words[3] |= @as(u32, 1) << 31;
    try testing.expectError(error.InvalidEncoding, unpack(words));

    words = try (AutohintPolicy{}).pack();
    words[1] = packHalf2(0.5, 0);
    try testing.expectError(error.InvalidEncoding, unpack(words));
}
