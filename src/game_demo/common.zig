const std = @import("std");
const snail = @import("../snail.zig");
const gl = @import("../render/gl.zig").gl;

pub const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn scale(v: Vec3, s: f32) Vec3 {
        return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
    }
};

pub const Camera = struct {
    pos: Vec3 = .{ .x = 0.0, .y = 1.45, .z = 5.8 },
    yaw: f32 = 0.0,
    pitch: f32 = -0.04,

    pub fn reset(self: *Camera) void {
        self.* = .{};
    }

    pub fn forward(self: Camera) Vec3 {
        return .{
            .x = -@sin(self.yaw),
            .y = 0.0,
            .z = -@cos(self.yaw),
        };
    }

    pub fn right(self: Camera) Vec3 {
        return .{
            .x = @cos(self.yaw),
            .y = 0.0,
            .z = -@sin(self.yaw),
        };
    }
};

pub const PlaneBasis = struct {
    origin: Vec3,
    axis_x: Vec3,
    axis_y: Vec3,
};

pub fn fract(v: f32) f32 {
    return v - @floor(v);
}

pub fn composeModel(pos: Vec3, rot_x: f32, rot_y: f32, scale: Vec3) snail.Mat4 {
    return snail.Mat4.multiply(
        snail.Mat4.translate(pos.x, pos.y, pos.z),
        snail.Mat4.multiply(
            rotateY(rot_y),
            snail.Mat4.multiply(rotateX(rot_x), scale3(scale.x, scale.y, scale.z)),
        ),
    );
}

pub fn planeMvp(
    view_proj: snail.Mat4,
    scene_w: f32,
    scene_h: f32,
    pos: Vec3,
    rot_x: f32,
    rot_y: f32,
    world_w: f32,
    world_h: f32,
    depth_bias: f32,
) snail.Mat4 {
    const local = snail.Mat4.multiply(
        snail.Mat4.translate(0.0, 0.0, depth_bias),
        snail.Mat4.multiply(
            scale3(world_w / scene_w, -(world_h / scene_h), 1.0),
            snail.Mat4.translate(-scene_w * 0.5, -scene_h * 0.5, 0.0),
        ),
    );
    const world = snail.Mat4.multiply(
        snail.Mat4.translate(pos.x, pos.y, pos.z),
        snail.Mat4.multiply(rotateY(rot_y), snail.Mat4.multiply(rotateX(rot_x), local)),
    );
    return snail.Mat4.multiply(view_proj, world);
}

pub fn planeBasis(
    scene_w: f32,
    scene_h: f32,
    pos: Vec3,
    rot_x: f32,
    rot_y: f32,
    world_w: f32,
    world_h: f32,
    depth_bias: f32,
) PlaneBasis {
    const model = snail.Mat4.multiply(
        snail.Mat4.translate(pos.x, pos.y, pos.z),
        snail.Mat4.multiply(rotateY(rot_y), rotateX(rot_x)),
    );
    return .{
        .origin = transformPoint(model, .{ .x = -world_w * 0.5, .y = world_h * 0.5, .z = depth_bias }),
        .axis_x = transformVector(model, .{ .x = world_w / scene_w, .y = 0.0, .z = 0.0 }),
        .axis_y = transformVector(model, .{ .x = 0.0, .y = -(world_h / scene_h), .z = 0.0 }),
    };
}

pub fn centeredSurfaceUvRect(content_w: f32, content_h: f32, surface_w: f32, surface_h: f32) struct { min: [2]f32, max: [2]f32 } {
    const span_u = content_w / surface_w;
    const span_v = content_h / surface_h;
    return .{
        .min = .{ 0.5 - span_u * 0.5, 0.5 - span_v * 0.5 },
        .max = .{ 0.5 + span_u * 0.5, 0.5 + span_v * 0.5 },
    };
}

pub fn transformPoint(m: snail.Mat4, p: Vec3) Vec3 {
    return .{
        .x = m.data[0] * p.x + m.data[4] * p.y + m.data[8] * p.z + m.data[12],
        .y = m.data[1] * p.x + m.data[5] * p.y + m.data[9] * p.z + m.data[13],
        .z = m.data[2] * p.x + m.data[6] * p.y + m.data[10] * p.z + m.data[14],
    };
}

pub fn transformVector(m: snail.Mat4, p: Vec3) Vec3 {
    return .{
        .x = m.data[0] * p.x + m.data[4] * p.y + m.data[8] * p.z,
        .y = m.data[1] * p.x + m.data[5] * p.y + m.data[9] * p.z,
        .z = m.data[2] * p.x + m.data[6] * p.y + m.data[10] * p.z,
    };
}

pub fn buildViewProjection(camera: Camera, aspect: f32) snail.Mat4 {
    const projection = snail.Mat4.perspective(std.math.degreesToRadians(60.0), aspect, 0.1, 80.0);
    const view = snail.Mat4.multiply(
        rotateX(-camera.pitch),
        snail.Mat4.multiply(rotateY(-camera.yaw), snail.Mat4.translate(-camera.pos.x, -camera.pos.y, -camera.pos.z)),
    );
    return snail.Mat4.multiply(projection, view);
}

pub fn rotateX(angle: f32) snail.Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    var m = snail.Mat4.identity;
    m.data[5] = c;
    m.data[6] = s;
    m.data[9] = -s;
    m.data[10] = c;
    return m;
}

pub fn rotateY(angle: f32) snail.Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    var m = snail.Mat4.identity;
    m.data[0] = c;
    m.data[2] = -s;
    m.data[8] = s;
    m.data[10] = c;
    return m;
}

pub fn scale3(x: f32, y: f32, z: f32) snail.Mat4 {
    var m = snail.Mat4.identity;
    m.data[0] = x;
    m.data[5] = y;
    m.data[10] = z;
    return m;
}

pub fn linearColor(r: u8, g: u8, b: u8, a: f32) [4]f32 {
    return .{
        srgbToLinear(@as(f32, @floatFromInt(r)) / 255.0),
        srgbToLinear(@as(f32, @floatFromInt(g)) / 255.0),
        srgbToLinear(@as(f32, @floatFromInt(b)) / 255.0),
        a,
    };
}

fn srgbToLinear(v: f32) f32 {
    if (v <= 0.04045) return v / 12.92;
    return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn compileShader(shader_type: gl.GLenum, source: [:0]const u8) !gl.GLuint {
    const shader = gl.glCreateShader(shader_type);
    var ptr = source.ptr;
    gl.glShaderSource(shader, 1, &ptr, null);
    gl.glCompileShader(shader);

    var ok: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetShaderInfoLog(shader, 4096, &len, &buf);
        if (len > 0) std.debug.print("Shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteShader(shader);
        return error.ShaderCompileFailed;
    }
    return shader;
}

pub fn linkProgram(vs_src: [:0]const u8, fs_src: [:0]const u8) !gl.GLuint {
    const vs = try compileShader(gl.GL_VERTEX_SHADER, vs_src);
    defer gl.glDeleteShader(vs);
    const fs = try compileShader(gl.GL_FRAGMENT_SHADER, fs_src);
    defer gl.glDeleteShader(fs);

    const program = gl.glCreateProgram();
    gl.glAttachShader(program, vs);
    gl.glAttachShader(program, fs);
    gl.glLinkProgram(program);

    var ok: gl.GLint = 0;
    gl.glGetProgramiv(program, gl.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetProgramInfoLog(program, 4096, &len, &buf);
        if (len > 0) std.debug.print("Shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteProgram(program);
        return error.ShaderLinkFailed;
    }
    return program;
}
