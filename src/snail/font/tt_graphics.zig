const std = @import("std");

pub const Vector = struct {
    x: i32,
    y: i32,

    pub const x_axis: Vector = .{ .x = one, .y = 0 };
    pub const y_axis: Vector = .{ .x = 0, .y = one };

    pub const one: i32 = 0x4000;
};

pub const Environment = struct {
    ppem_x_26_6: u32 = 0,
    ppem_y_26_6: u32 = 0,
    units_per_em: u16 = 1,
    point_size_26_6: i32 = 0,

    pub fn scaleFUnitsX(self: Environment, value: i32) i32 {
        return scaleFUnits(value, self.ppem_x_26_6, self.units_per_em);
    }

    pub fn scaleFUnitsY(self: Environment, value: i32) i32 {
        return scaleFUnits(value, self.ppem_y_26_6, self.units_per_em);
    }
};

pub const ZonePointer = enum(u8) {
    twilight = 0,
    glyph = 1,
};

pub const RoundMode = enum {
    grid,
    half_grid,
    double_grid,
    down_grid,
    up_grid,
    off,

    pub fn apply(self: RoundMode, value: i32) i32 {
        return switch (self) {
            .grid => roundPeriod(value, 64, 0, 32),
            .half_grid => roundPeriod(value, 64, 32, 32),
            .double_grid => roundPeriod(value, 32, 0, 16),
            .down_grid => floor26Dot6(value),
            .up_grid => ceil26Dot6(value),
            .off => value,
        };
    }
};

pub const GraphicsState = struct {
    projection: Vector = Vector.x_axis,
    freedom: Vector = Vector.x_axis,
    dual_projection: Vector = Vector.x_axis,
    zp0: ZonePointer = .glyph,
    zp1: ZonePointer = .glyph,
    zp2: ZonePointer = .glyph,
    rp0: u32 = 0,
    rp1: u32 = 0,
    rp2: u32 = 0,
    loop_count: u32 = 1,
    minimum_distance: i32 = 64,
    control_value_cut_in: i32 = 68,
    single_width_cut_in: i32 = 0,
    single_width_value: i32 = 0,
    delta_base: i32 = 9,
    delta_shift: i32 = 3,
    auto_flip: bool = true,
    round_mode: RoundMode = .grid,
    scan_control: i32 = 0,
    scan_type: i32 = 0,
    instruct_control: i32 = 0,

    pub fn setVectorToAxis(self: *GraphicsState, axis: Axis, target: VectorTarget) void {
        const vector = axisVector(axis);
        switch (target) {
            .both => {
                self.projection = vector;
                self.freedom = vector;
                self.dual_projection = vector;
            },
            .projection => {
                self.projection = vector;
                self.dual_projection = vector;
            },
            .freedom => self.freedom = vector,
        }
    }

    pub fn setZone(self: *GraphicsState, target: ZoneTarget, zone: ZonePointer) void {
        switch (target) {
            .zp0 => self.zp0 = zone,
            .zp1 => self.zp1 = zone,
            .zp2 => self.zp2 = zone,
            .all => {
                self.zp0 = zone;
                self.zp1 = zone;
                self.zp2 = zone;
            },
        }
    }

    pub fn setReferencePoint(self: *GraphicsState, index: u8, point: u32) void {
        switch (index) {
            0 => self.rp0 = point,
            1 => self.rp1 = point,
            2 => self.rp2 = point,
            else => unreachable,
        }
    }
};

pub const Axis = enum {
    x,
    y,
};

pub const VectorTarget = enum {
    both,
    projection,
    freedom,
};

pub const ZoneTarget = enum {
    zp0,
    zp1,
    zp2,
    all,
};

pub fn axisVector(axis: Axis) Vector {
    return switch (axis) {
        .x => Vector.x_axis,
        .y => Vector.y_axis,
    };
}

pub fn normalizeF2Dot14(x: i32, y: i32) Vector {
    const len2 = @as(i64, x) * x + @as(i64, y) * y;
    if (len2 == 0) return Vector.x_axis;

    const len = std.math.sqrt(@as(f64, @floatFromInt(len2)));
    return .{
        .x = @intFromFloat(@round(@as(f64, @floatFromInt(x)) * @as(f64, Vector.one) / len)),
        .y = @intFromFloat(@round(@as(f64, @floatFromInt(y)) * @as(f64, Vector.one) / len)),
    };
}

pub fn floor26Dot6(value: i32) i32 {
    return value & ~@as(i32, 63);
}

pub fn ceil26Dot6(value: i32) i32 {
    return floor26Dot6(@truncate(@as(i64, value) + 63));
}

fn roundPeriod(value: i32, period: i32, phase: i32, threshold: i32) i32 {
    if (value >= phase) {
        const shifted = @as(i64, value - phase) + threshold;
        return @intCast(@as(i64, phase) + @divTrunc(shifted, period) * period);
    }

    const shifted = @as(i64, phase - value) + threshold;
    return @intCast(@as(i64, phase) - @divTrunc(shifted, period) * period);
}

fn scaleFUnits(value: i32, ppem_26_6: u32, units_per_em: u16) i32 {
    if (units_per_em == 0) return 0;

    const numerator = @as(i64, value) * @as(i64, ppem_26_6);
    const denominator = @as(i64, units_per_em);
    const half = @divTrunc(denominator, 2);
    const rounded = if (numerator >= 0)
        @divTrunc(numerator + half, denominator)
    else
        @divTrunc(numerator - half, denominator);
    return @truncate(rounded);
}

test "round modes operate in 26.6 pixels" {
    try std.testing.expectEqual(@as(i32, 64), RoundMode.grid.apply(33));
    try std.testing.expectEqual(@as(i32, -64), RoundMode.grid.apply(-33));
    try std.testing.expectEqual(@as(i32, 32), RoundMode.half_grid.apply(20));
    try std.testing.expectEqual(@as(i32, 32), RoundMode.double_grid.apply(20));
    try std.testing.expectEqual(@as(i32, -64), RoundMode.down_grid.apply(-1));
    try std.testing.expectEqual(@as(i32, 0), RoundMode.up_grid.apply(-1));
    try std.testing.expectEqual(@as(i32, 19), RoundMode.off.apply(19));
}

test "graphics environment scales font units" {
    const env: Environment = .{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
        .units_per_em = 1000,
    };

    try std.testing.expectEqual(@as(i32, 32), env.scaleFUnitsX(50));
    try std.testing.expectEqual(@as(i32, 38), env.scaleFUnitsY(50));
    try std.testing.expectEqual(@as(i32, -38), env.scaleFUnitsY(-50));
}
