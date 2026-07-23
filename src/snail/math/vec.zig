const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub const zero = Vec2{};

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(v: Vec2, s: f32) Vec2 {
        return .{ .x = v.x * s, .y = v.y * s };
    }

    pub fn dot(a: Vec2, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn length(v: Vec2) f32 {
        return std.math.hypot(v.x, v.y);
    }

    pub fn normalize(v: Vec2) Vec2 {
        if (!std.math.isFinite(v.x) or !std.math.isFinite(v.y)) return .{};
        const magnitude = @max(@abs(v.x), @abs(v.y));
        if (magnitude == 0) return .{};
        const scaled = Vec2{ .x = v.x / magnitude, .y = v.y / magnitude };
        const scaled_len = @sqrt(scaled.x * scaled.x + scaled.y * scaled.y);
        return .{ .x = scaled.x / scaled_len, .y = scaled.y / scaled_len };
    }

    pub fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
        const wide_t: f64 = t;
        const one_minus_t = 1.0 - wide_t;
        return .{
            // Weighted form avoids overflowing `b - a` for opposite-sign,
            // individually-finite endpoints near the f32 limits.
            .x = @floatCast(@as(f64, a.x) * one_minus_t + @as(f64, b.x) * wide_t),
            .y = @floatCast(@as(f64, a.y) * one_minus_t + @as(f64, b.y) * wide_t),
        };
    }
};

pub const Vec4 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub fn new(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

pub const Transform2D = struct {
    xx: f32 = 1,
    xy: f32 = 0,
    tx: f32 = 0,
    yx: f32 = 0,
    yy: f32 = 1,
    ty: f32 = 0,

    pub const identity = Transform2D{};

    pub fn translate(x: f32, y: f32) Transform2D {
        return .{ .tx = x, .ty = y };
    }

    pub fn scale(x: f32, y: f32) Transform2D {
        return .{ .xx = x, .yy = y };
    }

    pub fn rotate(angle_rad: f32) Transform2D {
        const c = @cos(angle_rad);
        const s = @sin(angle_rad);
        return .{
            .xx = c,
            .xy = -s,
            .yx = s,
            .yy = c,
        };
    }

    pub fn multiply(a: Transform2D, b: Transform2D) Transform2D {
        return .{
            .xx = a.xx * b.xx + a.xy * b.yx,
            .xy = a.xx * b.xy + a.xy * b.yy,
            .tx = a.xx * b.tx + a.xy * b.ty + a.tx,
            .yx = a.yx * b.xx + a.yy * b.yx,
            .yy = a.yx * b.xy + a.yy * b.yy,
            .ty = a.yx * b.tx + a.yy * b.ty + a.ty,
        };
    }

    pub fn inverse(self: Transform2D) ?Transform2D {
        const values = [_]f32{ self.xx, self.xy, self.tx, self.yx, self.yy, self.ty };
        for (values) |value| if (!std.math.isFinite(value)) return null;
        // A determinant formed in f32 can underflow for small, perfectly
        // invertible transforms or overflow for large ones. Compute the
        // inverse in f64 and reject only singular matrices or results that
        // genuinely cannot be represented by Transform2D's f32 fields.
        const xx: f64 = self.xx;
        const xy: f64 = self.xy;
        const tx: f64 = self.tx;
        const yx: f64 = self.yx;
        const yy: f64 = self.yy;
        const ty: f64 = self.ty;
        const det = xx * yy - xy * yx;
        if (!std.math.isFinite(det) or det == 0) return null;
        const inv_det = 1.0 / det;
        const result_values = [_]f64{
            yy * inv_det,
            -xy * inv_det,
            -(yy * inv_det * tx - xy * inv_det * ty),
            -yx * inv_det,
            xx * inv_det,
            -(-yx * inv_det * tx + xx * inv_det * ty),
        };
        for (result_values) |value| {
            if (!std.math.isFinite(value) or @abs(value) > std.math.floatMax(f32)) return null;
        }
        return .{
            .xx = @floatCast(result_values[0]),
            .xy = @floatCast(result_values[1]),
            .tx = @floatCast(result_values[2]),
            .yx = @floatCast(result_values[3]),
            .yy = @floatCast(result_values[4]),
            .ty = @floatCast(result_values[5]),
        };
    }

    pub fn applyPoint(self: Transform2D, p: Vec2) Vec2 {
        return .{
            .x = self.xx * p.x + self.xy * p.y + self.tx,
            .y = self.yx * p.x + self.yy * p.y + self.ty,
        };
    }
};

pub const Mat4 = struct {
    data: [16]f32,

    pub const identity = Mat4{ .data = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    } };

    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var result: [16]f32 = undefined;
        inline for (0..4) |col| {
            inline for (0..4) |row| {
                var sum: f32 = 0;
                inline for (0..4) |k| {
                    sum += a.data[k * 4 + row] * b.data[col * 4 + k];
                }
                result[col * 4 + row] = sum;
            }
        }
        return .{ .data = result };
    }

    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        var m = Mat4{ .data = .{0} ** 16 };
        m.data[0] = 2.0 / (right - left);
        m.data[5] = 2.0 / (top - bottom);
        m.data[10] = -2.0 / (far - near);
        m.data[12] = -(right + left) / (right - left);
        m.data[13] = -(top + bottom) / (top - bottom);
        m.data[14] = -(far + near) / (far - near);
        m.data[15] = 1.0;
        return m;
    }

    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy_rad / 2.0);
        var m = Mat4{ .data = .{0} ** 16 };
        m.data[0] = f / aspect;
        m.data[5] = f;
        m.data[10] = (far + near) / (near - far);
        m.data[11] = -1.0;
        m.data[14] = (2.0 * far * near) / (near - far);
        return m;
    }

    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        var m = identity;
        m.data[12] = x;
        m.data[13] = y;
        m.data[14] = z;
        return m;
    }

    pub fn scaleUniform(s: f32) Mat4 {
        var m = Mat4{ .data = .{0} ** 16 };
        m.data[0] = s;
        m.data[5] = s;
        m.data[10] = s;
        m.data[15] = 1.0;
        return m;
    }

    pub fn rotateZ(angle_rad: f32) Mat4 {
        const cos = @cos(angle_rad);
        const sin = @sin(angle_rad);
        var m = identity;
        m.data[0] = cos;
        m.data[1] = sin;
        m.data[4] = -sin;
        m.data[5] = cos;
        return m;
    }
};

test "Vec2 basic operations" {
    const a = Vec2.new(1, 2);
    const b = Vec2.new(3, 4);
    const sum = Vec2.add(a, b);
    try std.testing.expectApproxEqAbs(sum.x, 4.0, 1e-6);
    try std.testing.expectApproxEqAbs(sum.y, 6.0, 1e-6);

    const d = Vec2.dot(a, b);
    try std.testing.expectApproxEqAbs(d, 11.0, 1e-6);
}

test "Vec2 lerp keeps the midpoint of extreme finite endpoints finite" {
    const limit = std.math.floatMax(f32);
    const midpoint = Vec2.lerp(.{ .x = -limit, .y = limit }, .{ .x = limit, .y = -limit }, 0.5);
    try std.testing.expectEqual(@as(f32, 0), midpoint.x);
    try std.testing.expectEqual(@as(f32, 0), midpoint.y);
}

test "Vec2 length and normalization avoid intermediate overflow" {
    const huge = Vec2{ .x = std.math.floatMax(f32), .y = 1 };
    try std.testing.expectEqual(std.math.floatMax(f32), huge.length());
    const unit = huge.normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1), unit.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), unit.y, 1e-6);

    const diagonal = (Vec2{ .x = std.math.floatMax(f32), .y = std.math.floatMax(f32) }).normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1), diagonal.length(), 1e-6);
}

test "Transform2D inverse rejects non-finite input and unrepresentable output" {
    var invalid = Transform2D.identity;
    invalid.tx = std.math.nan(f32);
    try std.testing.expectEqual(@as(?Transform2D, null), invalid.inverse());

    const overflowing = Transform2D{ .xx = std.math.floatTrueMin(f32), .yy = std.math.floatTrueMin(f32) };
    try std.testing.expectEqual(@as(?Transform2D, null), overflowing.inverse());
}

test "Transform2D inverse handles finite determinant underflow and overflow" {
    const tiny = Transform2D.scale(1e-20, 2e-20);
    const tiny_inverse = tiny.inverse().?;
    try std.testing.expectApproxEqRel(@as(f32, 1e20), tiny_inverse.xx, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 5e19), tiny_inverse.yy, 1e-6);

    const huge = Transform2D.scale(1e20, 2e20);
    const huge_inverse = huge.inverse().?;
    try std.testing.expectApproxEqRel(@as(f32, 1e-20), huge_inverse.xx, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 5e-21), huge_inverse.yy, 1e-6);
}

test "Mat4 identity multiply" {
    const m = Mat4.identity;
    const result = Mat4.multiply(m, m);
    for (0..16) |i| {
        try std.testing.expectApproxEqAbs(result.data[i], m.data[i], 1e-6);
    }
}

test "Mat4 ortho produces valid projection" {
    const m = Mat4.ortho(0, 800, 600, 0, -1, 1);
    // Top-left corner should map to (-1, 1)
    try std.testing.expectApproxEqAbs(m.data[0], 2.0 / 800.0, 1e-6);
}

test "Transform2D multiply composes affine transforms" {
    const t = Transform2D.translate(12, -4);
    const r = Transform2D.rotate(std.math.pi / 2.0);
    const combined = Transform2D.multiply(t, r);
    const p = combined.applyPoint(.{ .x = 2, .y = 0 });
    try std.testing.expectApproxEqAbs(p.x, 12.0, 1e-6);
    try std.testing.expectApproxEqAbs(p.y, -2.0, 1e-6);
}

test "Transform2D inverse reverses affine transforms" {
    const t = Transform2D.multiply(
        Transform2D.translate(12, -4),
        Transform2D.multiply(Transform2D.rotate(0.25), Transform2D.scale(3, -2)),
    );
    const inv = t.inverse() orelse return error.TestExpectedEqual;
    const p = Vec2.new(5, -7);
    const round_trip = inv.applyPoint(t.applyPoint(p));
    try std.testing.expectApproxEqAbs(p.x, round_trip.x, 1e-5);
    try std.testing.expectApproxEqAbs(p.y, round_trip.y, 1e-5);
    try std.testing.expect(Transform2D.scale(0, 1).inverse() == null);
}
