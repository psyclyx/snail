//! Procedural normal+height map textures for the game demo's surface
//! materials (floor, ceiling, wall, rough wall, panel). Each map is a
//! single sRGB8 RGBA texture: RGB encodes the surface normal, A
//! encodes a packed height term used by the parallax-occlusion pass.

const std = @import("std");
const gl = @import("support").gl;
const common = @import("common.zig");

pub const MaterialKind = enum {
    floor,
    ceiling,
    wall,
    rough_wall,
    panel,
};

pub const MaterialMaps = struct {
    floor: gl.GLuint = 0,
    ceiling: gl.GLuint = 0,
    wall: gl.GLuint = 0,
    rough_wall: gl.GLuint = 0,
    panel: gl.GLuint = 0,

    pub fn init(allocator: std.mem.Allocator, size: u32) !MaterialMaps {
        var maps: MaterialMaps = .{};
        errdefer maps.deinit();

        maps.floor = try createMaterialNormalMapTexture(allocator, size, .floor);
        maps.ceiling = try createMaterialNormalMapTexture(allocator, size, .ceiling);
        maps.wall = try createMaterialNormalMapTexture(allocator, size, .wall);
        maps.rough_wall = try createMaterialNormalMapTexture(allocator, size, .rough_wall);
        maps.panel = try createMaterialNormalMapTexture(allocator, size, .panel);
        return maps;
    }

    pub fn deinit(self: *MaterialMaps) void {
        if (self.floor != 0) gl.glDeleteTextures(1, &self.floor);
        if (self.ceiling != 0) gl.glDeleteTextures(1, &self.ceiling);
        if (self.wall != 0) gl.glDeleteTextures(1, &self.wall);
        if (self.rough_wall != 0) gl.glDeleteTextures(1, &self.rough_wall);
        if (self.panel != 0) gl.glDeleteTextures(1, &self.panel);
        self.* = .{};
    }
};

fn createMaterialNormalMapTexture(allocator: std.mem.Allocator, size: u32, kind: MaterialKind) !gl.GLuint {
    const side: usize = @intCast(size);
    const texel_count = side * side;
    const pixel_count = texel_count * 4;
    const heights = try allocator.alloc(f32, texel_count);
    defer allocator.free(heights);
    const data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(data);

    var min_height: f32 = std.math.inf(f32);
    var max_height: f32 = -std.math.inf(f32);
    for (0..side) |y| {
        for (0..side) |x| {
            const index = y * side + x;
            const h = materialHeight(kind, @floatFromInt(x), @floatFromInt(y), size);
            heights[index] = h;
            min_height = @min(min_height, h);
            max_height = @max(max_height, h);
        }
    }
    const height_scale = if (max_height - min_height > 1e-5) 1.0 / (max_height - min_height) else 1.0;
    const normal_scale = materialNormalScale(kind);

    for (0..side) |y| {
        for (0..side) |x| {
            const xi: i32 = @intCast(x);
            const yi: i32 = @intCast(y);
            const h = sampleMaterialHeight(heights, side, xi, yi);
            const h_l = sampleMaterialHeight(heights, side, xi - 1, yi);
            const h_r = sampleMaterialHeight(heights, side, xi + 1, yi);
            const h_d = sampleMaterialHeight(heights, side, xi, yi - 1);
            const h_u = sampleMaterialHeight(heights, side, xi, yi + 1);
            const dx = h_r - h_l;
            const dy = h_u - h_d;

            var nx: f32 = -dx * normal_scale;
            var ny: f32 = -dy * normal_scale;
            var nz: f32 = 1.0;
            const len = @sqrt(nx * nx + ny * ny + nz * nz);
            nx /= len;
            ny /= len;
            nz /= len;

            const encoded_h = std.math.clamp((((h - min_height) * height_scale) - 0.5) * 1.42 + 0.5, 0.0, 1.0);

            const base = (y * side + x) * 4;
            data[base + 0] = encodeUnorm8(nx * 0.5 + 0.5);
            data[base + 1] = encodeUnorm8(ny * 0.5 + 0.5);
            data[base + 2] = encodeUnorm8(nz * 0.5 + 0.5);
            data[base + 3] = encodeUnorm8(encoded_h);
        }
    }

    var texture: gl.GLuint = 0;
    gl.glGenTextures(1, &texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        gl.GL_RGBA8,
        @intCast(size),
        @intCast(size),
        0,
        gl.GL_RGBA,
        gl.GL_UNSIGNED_BYTE,
        data.ptr,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
    gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    return texture;
}

fn sampleMaterialHeight(heights: []const f32, side: usize, x: i32, y: i32) f32 {
    const s: i32 = @intCast(side);
    const wrapped_x: usize = @intCast(@mod(x, s));
    const wrapped_y: usize = @intCast(@mod(y, s));
    return heights[wrapped_y * side + wrapped_x];
}

fn materialHeight(kind: MaterialKind, x: f32, y: f32, size: u32) f32 {
    const s = @as(f32, @floatFromInt(size));
    const ux = x / s;
    const uy = y / s;
    return switch (kind) {
        .floor => floorHeight(ux, uy),
        .ceiling => ceilingHeight(ux, uy),
        .wall => plasterHeight(ux, uy, 301, 0.62),
        .rough_wall => plasterHeight(ux, uy, 907, 1.0) - cellularPits(ux, uy, 58, 44, 1193) * 0.16 + crackMask(ux, uy, 1609) * 0.08,
        .panel => panelHeight(ux, uy),
    };
}

fn materialNormalScale(kind: MaterialKind) f32 {
    return switch (kind) {
        .floor => 8.8,
        .ceiling => 4.8,
        .wall => 6.6,
        .rough_wall => 9.4,
        .panel => 4.2,
    };
}

fn floorHeight(ux: f32, uy: f32) f32 {
    const seams = gridGroove(ux, uy, 6, 6, 0.018);
    const slab = tileFbm2(ux, uy, 14, 14, 5, 101, 0.53);
    const aggregate = tileFbm2(ux, uy, 72, 64, 4, 211, 0.48);
    const scuffs = scratchLines(ux, uy, 96, 307) * 0.10;
    const pits = cellularPits(ux, uy, 46, 46, 409) * 0.12;
    return slab * 0.34 + aggregate * 0.10 - seams * 0.58 - pits - scuffs;
}

fn ceilingHeight(ux: f32, uy: f32) f32 {
    const panels = gridGroove(ux, uy, 8, 4, 0.010);
    const broad = tileFbm2(ux, uy, 7, 5, 4, 503, 0.55);
    const stipple = tileFbm2(ux, uy, 96, 88, 3, 607, 0.46);
    return broad * 0.22 + stipple * 0.08 - panels * 0.20;
}

fn plasterHeight(ux: f32, uy: f32, seed: u32, roughness: f32) f32 {
    const warp_x = tileFbm2(ux, uy, 3, 4, 4, seed + 11, 0.54) * 0.035;
    const warp_y = tileFbm2(ux, uy, 4, 3, 4, seed + 29, 0.54) * 0.030;
    const u = common.fract(ux + warp_x);
    const v = common.fract(uy + warp_y);
    const broad = tileFbm2(u, v, 5, 4, 5, seed + 41, 0.55);
    const trowel = @abs(tileFbm2(u, v, 16, 11, 4, seed + 71, 0.50)) * 2.0 - 1.0;
    const grit = tileFbm2(u, v, 88, 76, 3, seed + 97, 0.45);
    const pores = cellularPits(u, v, 72, 56, seed + 131);
    return broad * 0.38 + trowel * 0.18 * roughness + grit * 0.08 * roughness - pores * 0.10 * roughness;
}

fn panelHeight(ux: f32, uy: f32) f32 {
    const brushed = tileFbm2(ux, uy, 112, 9, 4, 709, 0.50);
    const fine = tileFbm2(ux, uy, 180, 36, 3, 811, 0.42);
    const scratches = scratchLines(ux, uy, 128, 919);
    const pressed = gridGroove(ux, uy, 1, 1, 0.018) * 0.10;
    return brushed * 0.18 + fine * 0.06 - scratches * 0.14 - pressed;
}

fn tileFbm2(ux: f32, uy: f32, base_cells_x: u32, base_cells_y: u32, octaves: u32, seed: u32, gain: f32) f32 {
    var sum: f32 = 0.0;
    var amplitude: f32 = 0.55;
    var norm: f32 = 0.0;
    var cells_x = base_cells_x;
    var cells_y = base_cells_y;
    var i: u32 = 0;
    while (i < octaves) : (i += 1) {
        sum += tileValueNoise2(ux, uy, cells_x, cells_y, seed + i * 131) * amplitude;
        norm += amplitude;
        amplitude *= gain;
        cells_x *= 2;
        cells_y *= 2;
    }
    return if (norm > 1e-6) sum / norm else 0.0;
}

fn tileValueNoise2(ux: f32, uy: f32, cells_x: u32, cells_y: u32, seed: u32) f32 {
    const x = common.fract(ux) * @as(f32, @floatFromInt(cells_x));
    const y = common.fract(uy) * @as(f32, @floatFromInt(cells_y));
    const x0f = @floor(x);
    const y0f = @floor(y);
    const x0: i32 = @intFromFloat(x0f);
    const y0: i32 = @intFromFloat(y0f);
    const tx = smoother01(x - x0f);
    const ty = smoother01(y - y0f);

    const v00 = hashCell(wrapCell(x0, cells_x), wrapCell(y0, cells_y), seed);
    const v10 = hashCell(wrapCell(x0 + 1, cells_x), wrapCell(y0, cells_y), seed);
    const v01 = hashCell(wrapCell(x0, cells_x), wrapCell(y0 + 1, cells_y), seed);
    const v11 = hashCell(wrapCell(x0 + 1, cells_x), wrapCell(y0 + 1, cells_y), seed);

    const ix0 = std.math.lerp(v00, v10, tx);
    const ix1 = std.math.lerp(v01, v11, tx);
    return std.math.lerp(ix0, ix1, ty) * 2.0 - 1.0;
}

fn cellularPits(ux: f32, uy: f32, cells_x: u32, cells_y: u32, seed: u32) f32 {
    const x = common.fract(ux) * @as(f32, @floatFromInt(cells_x));
    const y = common.fract(uy) * @as(f32, @floatFromInt(cells_y));
    const xi: i32 = @intFromFloat(@floor(x));
    const yi: i32 = @intFromFloat(@floor(y));

    var min_dist2: f32 = 100.0;
    var oy: i32 = -1;
    while (oy <= 1) : (oy += 1) {
        var ox: i32 = -1;
        while (ox <= 1) : (ox += 1) {
            const cx = xi + ox;
            const cy = yi + oy;
            const wx = wrapCell(cx, cells_x);
            const wy = wrapCell(cy, cells_y);
            const jx = hashCell(wx, wy, seed + 17);
            const jy = hashCell(wx, wy, seed + 53);
            const dx = (@as(f32, @floatFromInt(cx)) + jx) - x;
            const dy = (@as(f32, @floatFromInt(cy)) + jy) - y;
            min_dist2 = @min(min_dist2, dx * dx + dy * dy);
        }
    }

    return 1.0 - smoothstep(0.06, 0.42, @sqrt(min_dist2));
}

fn gridGroove(ux: f32, uy: f32, cells_x: u32, cells_y: u32, width: f32) f32 {
    const fx = common.fract(ux * @as(f32, @floatFromInt(cells_x)));
    const fy = common.fract(uy * @as(f32, @floatFromInt(cells_y)));
    const dx = @min(fx, 1.0 - fx);
    const dy = @min(fy, 1.0 - fy);
    const gx = 1.0 - smoothstep(width, width * 2.8, dx);
    const gy = 1.0 - smoothstep(width, width * 2.8, dy);
    return @max(gx, gy);
}

fn scratchLines(ux: f32, uy: f32, rows: u32, seed: u32) f32 {
    const y = common.fract(uy) * @as(f32, @floatFromInt(rows));
    const row_i: i32 = @intFromFloat(@floor(y));
    const row = wrapCell(row_i, rows);
    const fy = y - @floor(y);
    const center = 0.18 + hashCell(row, 0, seed) * 0.64;
    const width = 0.020 + hashCell(row, 1, seed) * 0.035;
    const line = 1.0 - smoothstep(width, width * 2.5, @abs(fy - center));
    const broken = smoothstep(0.28, 0.78, tileValueNoise2(ux, uy, 48, rows, seed + 101) * 0.5 + 0.5);
    return line * broken;
}

fn crackMask(ux: f32, uy: f32, seed: u32) f32 {
    const web = @abs(tileFbm2(ux, uy, 18, 14, 4, seed, 0.50));
    return 1.0 - smoothstep(0.015, 0.085, web);
}

fn smoother01(t: f32) f32 {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

fn wrapCell(v: i32, period: u32) u32 {
    const p: i32 = @intCast(period);
    return @intCast(@mod(v, p));
}

fn hashCell(x: u32, y: u32, seed: u32) f32 {
    var h = x *% 0x8da6b343;
    h ^= y *% 0xd8163841;
    h ^= seed *% 0xcb1ab31f;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    h *%= 0x846ca68b;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0x00ffffff)) / 16777215.0;
}

fn encodeUnorm8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0.0, 1.0) * 255.0 + 0.5);
}
