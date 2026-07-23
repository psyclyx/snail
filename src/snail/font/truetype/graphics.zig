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

    /// Returns true when the rendering grid has non-square pixels (i.e.
    /// `ppem_x != ppem_y`). Under stretching, CVT reads/writes and
    /// MPPEM/MPS must scale by the projection-relative aspect ratio,
    /// matching FreeType's `Current_Ratio`.
    pub fn isStretched(self: Environment) bool {
        return self.ppem_x_26_6 != self.ppem_y_26_6;
    }

    /// Projection-relative scale to apply to canonical (y-base) CVT and
    /// MPPEM values. Returned as 16.16 fixed-point. For square pixels
    /// this is exactly 1.0; otherwise it interpolates between x_ratio
    /// and y_ratio along the projection vector, matching the FreeType
    /// formula `Hypot(MulFix14(x_ratio, proj.x), MulFix14(y_ratio, proj.y))`.
    pub fn projectionRatio(self: Environment, projection: Vector) i32 {
        if (!self.isStretched()) return 0x10000; // 1.0 in 16.16
        const base: i64 = @max(self.ppem_x_26_6, self.ppem_y_26_6);
        if (base == 0) return 0x10000;
        const xr: i64 = @divTrunc(@as(i64, self.ppem_x_26_6) << 16, base);
        const yr: i64 = @divTrunc(@as(i64, self.ppem_y_26_6) << 16, base);
        if (projection.y == 0) return @intCast(xr);
        if (projection.x == 0) return @intCast(yr);
        // 2.14 * 16.16 → 16.16 via FreeType's MulFix14 (shift back by 14).
        const x = (xr * projection.x) >> 14;
        const y = (yr * projection.y) >> 14;
        return @intCast(hypot16Dot16(x, y));
    }

    /// The base ppem in 26.6 — the maximum of x and y. CVT values are
    /// stored in 26.6 at this base scale, then rescaled per projection.
    pub fn basePpem26Dot6(self: Environment) u32 {
        return @max(self.ppem_x_26_6, self.ppem_y_26_6);
    }
};

fn hypot16Dot16(x: i64, y: i64) i64 {
    if (x == 0) return if (y < 0) -y else y;
    if (y == 0) return if (x < 0) -x else x;
    const f = @sqrt(@as(f64, @floatFromInt(x)) * @as(f64, @floatFromInt(x)) +
        @as(f64, @floatFromInt(y)) * @as(f64, @floatFromInt(y)));
    return @intFromFloat(@round(f));
}

/// 16.16 multiply: (a * b) >> 16, with rounding to nearest. Used to
/// apply the projection ratio to a 26.6 pixel value (also produces 26.6).
pub fn mulFix16Dot16(value: i32, ratio: i32) i32 {
    if (ratio == 0x10000) return value;
    const prod: i64 = @as(i64, value) * @as(i64, ratio);
    const rounded = if (prod >= 0) prod + (1 << 15) else prod - (1 << 15);
    return @intCast(rounded >> 16);
}

/// 16.16 divide: (value << 16) / ratio, with rounding to nearest.
pub fn divFix16Dot16(value: i32, ratio: i32) i32 {
    if (ratio == 0x10000) return value;
    if (ratio == 0) return value;
    const num: i64 = @as(i64, value) << 16;
    const half = @divTrunc(@as(i64, ratio), 2);
    const adjusted = if ((num >= 0) == (ratio >= 0)) num + half else num - half;
    return @intCast(@divTrunc(adjusted, ratio));
}

pub const ZonePointer = enum(u8) {
    twilight = 0,
    glyph = 1,
};

/// Round state. The "super" round modes (SROUND 0x76, S45ROUND 0x77) carry
/// period/phase/threshold parameters, so this is a tagged union rather than
/// a flat enum. Persisted across glyphs as part of the prep snapshot.
pub const RoundMode = union(enum) {
    grid,
    half_grid,
    double_grid,
    down_grid,
    up_grid,
    off,
    super: SuperRound,

    pub const SuperRound = struct {
        period: i32,
        phase: i32,
        threshold: i32,
    };

    pub fn apply(self: RoundMode, value: i32, compensation: i32) i32 {
        return switch (self) {
            .grid => roundPeriod(value, 64, 0, 32, compensation),
            .half_grid => roundPeriod(value, 64, 32, 32, compensation),
            .double_grid => roundPeriod(value, 32, 0, 16, compensation),
            .down_grid => roundFloor(value, compensation),
            .up_grid => roundCeil(value, compensation),
            .off => roundNone(value, compensation),
            .super => |s| superRound(value, s, compensation),
        };
    }
};

fn superRound(value: i32, s: RoundMode.SuperRound, compensation: i32) i32 {
    if (s.period <= 0) return value;
    // Match FreeType's Round_Super: compensation is added to the magnitude
    // (positive) / subtracted from it (negative) before period flooring.
    // Sign-aware floor of (|value| - phase + threshold (± comp)) to a
    // multiple of period, then re-apply sign and add phase back.
    if (value >= 0) {
        const shifted = @as(i64, value) - @as(i64, s.phase) + @as(i64, s.threshold) + @as(i64, compensation);
        var v = @as(i64, s.phase) + @divTrunc(shifted, s.period) * s.period;
        if (v < 0) v = @as(i64, s.phase);
        return @truncate(v);
    } else {
        const shifted = -@as(i64, value) - @as(i64, s.phase) + @as(i64, s.threshold) - @as(i64, compensation);
        var v = -@as(i64, s.phase) - @divTrunc(shifted, s.period) * s.period;
        if (v > 0) v = -@as(i64, s.phase);
        return @truncate(v);
    }
}

/// Decode the SROUND/S45ROUND parameter byte into a SuperRound struct.
/// `grid_period` is 0x40 (=1 px in 26.6) for SROUND, 0x2D41 (=sqrt(2)/2 px)
/// for S45ROUND, per the MS TrueType spec.
pub fn decodeSuperRound(grid_period: i32, selector: i32) RoundMode.SuperRound {
    var period: i32 = grid_period;
    switch (@as(u8, @intCast(@as(u32, @bitCast(selector)) & 0xC0))) {
        0x00 => period = @divTrunc(grid_period, 2),
        0x40 => period = grid_period,
        0x80 => period = grid_period * 2,
        else => {}, // 0xC0 reserved
    }
    var phase: i32 = 0;
    switch (@as(u8, @intCast(@as(u32, @bitCast(selector)) & 0x30))) {
        0x00 => phase = 0,
        0x10 => phase = @divTrunc(period, 4),
        0x20 => phase = @divTrunc(period, 2),
        0x30 => phase = @divTrunc(period * 3, 4),
        else => unreachable,
    }
    const low = @as(i32, @intCast(@as(u32, @bitCast(selector)) & 0x0F));
    const threshold: i32 = if (low == 0) period - 1 else @divTrunc((low - 4) * period, 8);
    return .{ .period = period, .phase = phase, .threshold = threshold };
}

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
    // Each square fits i64 (max 2^62), but the sum overflows when both
    // inputs are near ±2^31 (reachable via SPVFS/SPVTL). Saturate: the
    // clamped magnitude leaves the direction — and the result — unchanged.
    const len2 = @as(i64, x) * x +| @as(i64, y) * y;
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

/// i32 add/sub with TrueType's wrapping (widen to i64, truncate back).
pub fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
}

pub fn subWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) - @as(i64, rhs));
}

fn roundPeriod(value: i32, period: i32, phase: i32, threshold: i32, compensation: i32) i32 {
    // FreeType-style: branch on the input's sign (not its relationship to
    // phase) so the clamp at the end keeps positive inputs >= +phase and
    // negative inputs <= -phase. Compensation biases the magnitude before
    // period flooring; with the default 0 this collapses to the previous
    // unconditional formula. Clamping to ±phase (rather than 0) matches
    // FreeType's per-mode behaviour: RTG clamps to 0 (phase=0), RTHG to ±32
    // (phase=32), RTDG to 0 (phase=0).
    if (value >= 0) {
        const shifted = @as(i64, value) - @as(i64, phase) + @as(i64, threshold) + @as(i64, compensation);
        var v = @as(i64, phase) + @divTrunc(shifted, period) * period;
        if (v < 0) v = @as(i64, phase);
        // Bytecode can synthesize inputs within a rounding period of the i32
        // edges (PUSHW 32767 + repeated DUP;ADD), where the rounded result
        // doesn't fit i32. Truncate like ADD/SUB/MUL wrap rather than trap.
        return @truncate(v);
    }
    const shifted = -@as(i64, value) - @as(i64, phase) + @as(i64, threshold) + @as(i64, compensation);
    var v = -@as(i64, phase) - @divTrunc(shifted, period) * period;
    if (v > 0) v = -@as(i64, phase);
    return @truncate(v);
}

fn roundFloor(value: i32, compensation: i32) i32 {
    if (value >= 0) {
        const adjusted = @as(i64, value) + @as(i64, compensation);
        var v = adjusted & ~@as(i64, 63);
        if (v < 0) v = 0;
        return @truncate(v);
    }
    const adjusted = -@as(i64, value) + @as(i64, compensation);
    var v = -(adjusted & ~@as(i64, 63));
    if (v > 0) v = 0;
    return @truncate(v);
}

fn roundCeil(value: i32, compensation: i32) i32 {
    if (value >= 0) {
        const adjusted = @as(i64, value) + @as(i64, compensation) + 63;
        var v = adjusted & ~@as(i64, 63);
        if (v < 0) v = 0;
        return @truncate(v);
    }
    const adjusted = -@as(i64, value) + @as(i64, compensation) + 63;
    var v = -(adjusted & ~@as(i64, 63));
    if (v > 0) v = 0;
    return @truncate(v);
}

fn roundNone(value: i32, compensation: i32) i32 {
    if (value >= 0) {
        var v = @as(i64, value) + @as(i64, compensation);
        if (v < 0) v = 0;
        return @truncate(v);
    }
    var v = @as(i64, value) - @as(i64, compensation);
    if (v > 0) v = 0;
    return @truncate(v);
}

/// FUnit → 26.6 pixel scaling with round-to-nearest, truncated to i32. The
/// single implementation shared by the graphics-state scalers, the exec
/// context (`scaleFUnitsBase`), and vm's `scaleFWordTo26Dot6`.
pub fn scaleFUnits(value: i32, ppem_26_6: u32, units_per_em: u16) i32 {
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
    try std.testing.expectEqual(@as(i32, 64), (RoundMode{ .grid = {} }).apply(33, 0));
    try std.testing.expectEqual(@as(i32, -64), (RoundMode{ .grid = {} }).apply(-33, 0));
    try std.testing.expectEqual(@as(i32, 32), (RoundMode{ .half_grid = {} }).apply(20, 0));
    try std.testing.expectEqual(@as(i32, 32), (RoundMode{ .double_grid = {} }).apply(20, 0));
    // RDTG floors magnitude toward zero; RUTG ceils magnitude away from
    // zero. Matches FreeType's Round_Down_To_Grid / Round_Up_To_Grid.
    // snail's earlier behaviour did arithmetic floor/ceil (toward -inf /
    // +inf), which is symmetric in sign but the wrong semantic — a TT
    // font asking "round this stem-length down" expects magnitude reduced
    // regardless of the distance's sign.
    try std.testing.expectEqual(@as(i32, 0), (RoundMode{ .down_grid = {} }).apply(-1, 0));
    try std.testing.expectEqual(@as(i32, -64), (RoundMode{ .down_grid = {} }).apply(-65, 0));
    try std.testing.expectEqual(@as(i32, -64), (RoundMode{ .up_grid = {} }).apply(-1, 0));
    try std.testing.expectEqual(@as(i32, 0), (RoundMode{ .up_grid = {} }).apply(0, 0));
    try std.testing.expectEqual(@as(i32, 19), (RoundMode{ .off = {} }).apply(19, 0));
}

test "round compensation biases magnitude before flooring" {
    // RTG with compensation 0: 10 → 0 (10 + 32 < 64). With compensation 32:
    // 10 + 32 + 32 = 74 → 64. Comp pushed it over the half-period boundary.
    try std.testing.expectEqual(@as(i32, 0), (RoundMode{ .grid = {} }).apply(10, 0));
    try std.testing.expectEqual(@as(i32, 64), (RoundMode{ .grid = {} }).apply(10, 32));

    // Sign-preserving compensation on the negative side too: -10 + comp 32
    // → magnitude 74 → 64 → -64.
    try std.testing.expectEqual(@as(i32, 0), (RoundMode{ .grid = {} }).apply(-10, 0));
    try std.testing.expectEqual(@as(i32, -64), (RoundMode{ .grid = {} }).apply(-10, 32));

    // Down-to-grid (floor) with compensation 32: 10 + 32 = 42 → floor → 0;
    // 32 + 32 = 64 → 64.
    try std.testing.expectEqual(@as(i32, 0), (RoundMode{ .down_grid = {} }).apply(10, 32));
    try std.testing.expectEqual(@as(i32, 64), (RoundMode{ .down_grid = {} }).apply(32, 32));

    // ROFF: comp directly adds to magnitude.
    try std.testing.expectEqual(@as(i32, 19), (RoundMode{ .off = {} }).apply(19, 0));
    try std.testing.expectEqual(@as(i32, 27), (RoundMode{ .off = {} }).apply(19, 8));
    try std.testing.expectEqual(@as(i32, -27), (RoundMode{ .off = {} }).apply(-19, 8));
}

test "SROUND decodes period, phase, and threshold per spec" {
    // SROUND uses a 1-pixel grid period (0x40 in 26.6).
    // Selector 0x48 = period bits 01 (1px), phase bits 00 (0), threshold bits 1000 (=8-4=4 * 64/8 = 32)
    const r = decodeSuperRound(0x40, 0x48);
    try std.testing.expectEqual(@as(i32, 64), r.period);
    try std.testing.expectEqual(@as(i32, 0), r.phase);
    try std.testing.expectEqual(@as(i32, 32), r.threshold);

    // Same as RTG: threshold = period/2, phase = 0.
    const grid_like = RoundMode{ .super = r };
    try std.testing.expectEqual(@as(i32, 64), grid_like.apply(33, 0));
    try std.testing.expectEqual(@as(i32, 0), grid_like.apply(31, 0));
    try std.testing.expectEqual(@as(i32, -64), grid_like.apply(-33, 0));

    // SROUND with low nibble 0 → threshold = period-1.
    const r2 = decodeSuperRound(0x40, 0x40);
    try std.testing.expectEqual(@as(i32, 63), r2.threshold);
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

test "round modes tolerate values near the i32 edges" {
    // Bytecode can synthesize stack values within a rounding period of the
    // i32 limits (PUSHW 32767 + repeated DUP;ADD); the rounded result then
    // doesn't fit i32 and must wrap like ADD/SUB/MUL, not trap.
    const near_max = std.math.maxInt(i32) - 32;
    const near_min = std.math.minInt(i32) + 32;
    const modes = [_]RoundMode{ .grid, .half_grid, .double_grid, .down_grid, .up_grid, .off };
    for (modes) |mode| {
        _ = mode.apply(near_max, 64);
        _ = mode.apply(near_max, -64);
        _ = mode.apply(near_min, 64);
        _ = mode.apply(near_min, -64);
    }
    // S45ROUND's period (sqrt(2) px in 26.6, doubled) is the largest the
    // super modes can reach; phase/threshold are bounded by the period.
    const super: RoundMode = .{ .super = .{ .period = 23170, .phase = 11585, .threshold = 11585 } };
    _ = super.apply(near_max, 64);
    _ = super.apply(near_min, 64);
    // In-range behaviour is unchanged: rounding still snaps to the grid.
    try std.testing.expectEqual(@as(i32, 64), (RoundMode{ .grid = {} }).apply(33, 0));
    try std.testing.expectEqual(@as(i32, -64), (RoundMode{ .grid = {} }).apply(-33, 0));
}

test "normalizeF2Dot14 tolerates i32-min inputs" {
    // (-2^31, -2^31): x² + y² = 2^63 overflows i64; saturation keeps the
    // direction exact. Expected: (-1, -1)/sqrt(2) in 2.14 ≈ -11585.237.
    const v = normalizeF2Dot14(std.math.minInt(i32), std.math.minInt(i32));
    try std.testing.expectEqual(@as(i32, -11585), v.x);
    try std.testing.expectEqual(@as(i32, -11585), v.y);
    // Degenerate zero still falls back to the x axis.
    try std.testing.expectEqual(Vector.x_axis, normalizeF2Dot14(0, 0));
    // Ordinary F2DOT14 inputs are unaffected.
    try std.testing.expectEqual(Vector.x_axis, normalizeF2Dot14(Vector.one, 0));
}
