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

pub const AutohintPolicy = struct {
    x: XPolicy = .{},
    y: YPolicy = .{},

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
}

const x_align_shift = 0;
const x_stem_shift = 2;
const x_positioning_shift = 4;
const x_registration_shift = 6;
const y_align_shift = 0;
const y_stem_shift = 2;
const y_overshoot_shift = 4;
const two_bit_mask: u32 = 0b11;
const x_config_mask: u32 = (two_bit_mask << x_align_shift) |
    (two_bit_mask << x_stem_shift) |
    (two_bit_mask << x_positioning_shift) |
    (two_bit_mask << x_registration_shift);
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
        (@as(u32, @intFromEnum(policy.x.registration)) << x_registration_shift);
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
    };
    try p.validate();
    try testing.expectEqual(@as(usize, 7), p.pack().len);
    try testing.expectEqualDeep(p, try AutohintPolicy.unpack(p.pack()));
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
