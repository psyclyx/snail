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
        return @sqrt(v.x * v.x + v.y * v.y);
    }

    pub fn normalize(v: Vec2) Vec2 {
        const len = v.length();
        if (len == 0) return .{};
        return v.scale(1.0 / len);
    }

    pub fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
        return .{
            .x = a.x + (b.x - a.x) * t,
            .y = a.y + (b.y - a.y) * t,
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
