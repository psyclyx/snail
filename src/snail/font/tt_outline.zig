const std = @import("std");

const bezier = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");

const QuadBezier = bezier.QuadBezier;
const Vec2 = vec.Vec2;

pub const ParseError = error{
    UnexpectedEof,
    InvalidFont,
    OutOfMemory,
};

pub const Point = struct {
    x: i16,
    y: i16,
    on_curve: bool,

    pub fn scaled(self: Point, scale: f32) Vec2 {
        return Vec2.new(
            @as(f32, @floatFromInt(self.x)) * scale,
            @as(f32, @floatFromInt(self.y)) * scale,
        );
    }
};

pub const ContourRange = struct {
    start: u32,
    end: u32,
};

pub const SimpleGlyph = struct {
    allocator: std.mem.Allocator,
    contours: []ContourRange,
    points: []Point,
    instructions: []const u8,

    pub fn deinit(self: *SimpleGlyph) void {
        self.allocator.free(self.contours);
        self.allocator.free(self.points);
        self.* = undefined;
    }
};

fn readU16(data: []const u8, offset: usize) ParseError!u16 {
    if (offset + 2 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) ParseError!i16 {
    if (offset + 2 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readEndPoints(
    allocator: std.mem.Allocator,
    data: []const u8,
    base: usize,
    num_contours: u16,
) ParseError![]u16 {
    const end_pts = try allocator.alloc(u16, num_contours);
    errdefer allocator.free(end_pts);

    var previous: ?u16 = null;
    for (0..num_contours) |i| {
        const end_pt = try readU16(data, base + 10 + i * 2);
        if (previous) |prev| {
            if (end_pt <= prev) return error.InvalidFont;
        }
        end_pts[i] = end_pt;
        previous = end_pt;
    }
    return end_pts;
}

fn readFlags(
    allocator: std.mem.Allocator,
    data: []const u8,
    num_points: u32,
    offset: *usize,
) ParseError![]u8 {
    const flags = try allocator.alloc(u8, num_points);
    errdefer allocator.free(flags);

    var i: u32 = 0;
    while (i < num_points) {
        if (offset.* >= data.len) return error.UnexpectedEof;
        const flag = data[offset.*];
        offset.* += 1;

        flags[i] = flag;
        i += 1;

        if (flag & 8 == 0) continue;
        if (offset.* >= data.len) return error.UnexpectedEof;
        const repeat = data[offset.*];
        offset.* += 1;
        for (0..repeat) |_| {
            if (i >= num_points) break;
            flags[i] = flag;
            i += 1;
        }
    }
    return flags;
}

fn readCoords(
    allocator: std.mem.Allocator,
    data: []const u8,
    flags: []const u8,
    offset: *usize,
    short_vector_bit: u8,
    same_or_positive_bit: u8,
) ParseError![]i16 {
    const coords = try allocator.alloc(i16, flags.len);
    errdefer allocator.free(coords);

    var coord: i16 = 0;
    for (flags, 0..) |flag, i| {
        if (flag & short_vector_bit != 0) {
            if (offset.* >= data.len) return error.UnexpectedEof;
            const delta: i16 = @intCast(data[offset.*]);
            offset.* += 1;
            if (flag & same_or_positive_bit != 0) coord += delta else coord -= delta;
        } else if (flag & same_or_positive_bit == 0) {
            coord += try readI16(data, offset.*);
            offset.* += 2;
        }
        coords[i] = coord;
    }
    return coords;
}

fn buildContourRanges(
    allocator: std.mem.Allocator,
    end_pts: []const u16,
    point_count: u32,
) ParseError![]ContourRange {
    const contours = try allocator.alloc(ContourRange, end_pts.len);
    errdefer allocator.free(contours);

    var start: u32 = 0;
    for (end_pts, 0..) |end_pt, i| {
        const end = @as(u32, end_pt) + 1;
        if (end > point_count or start >= end) return error.InvalidFont;
        contours[i] = .{ .start = start, .end = end };
        start = end;
    }
    return contours;
}

fn buildPoints(
    allocator: std.mem.Allocator,
    flags: []const u8,
    x_coords: []const i16,
    y_coords: []const i16,
) ParseError![]Point {
    std.debug.assert(flags.len == x_coords.len and flags.len == y_coords.len);

    const points = try allocator.alloc(Point, flags.len);
    errdefer allocator.free(points);

    for (points, 0..) |*point, i| {
        point.* = .{
            .x = x_coords[i],
            .y = y_coords[i],
            .on_curve = (flags[i] & 1) != 0,
        };
    }
    return points;
}

pub fn parseSimpleGlyph(
    allocator: std.mem.Allocator,
    data: []const u8,
    base: usize,
    num_contours: u16,
) ParseError!SimpleGlyph {
    if (num_contours == 0) {
        return .{
            .allocator = allocator,
            .contours = try allocator.alloc(ContourRange, 0),
            .points = try allocator.alloc(Point, 0),
            .instructions = &.{},
        };
    }

    const end_pts = try readEndPoints(allocator, data, base, num_contours);
    defer allocator.free(end_pts);

    const point_count = @as(u32, end_pts[num_contours - 1]) + 1;
    const instr_len_off = base + 10 + @as(usize, num_contours) * 2;
    const instr_len = try readU16(data, instr_len_off);
    const instr_start = instr_len_off + 2;
    const instr_end = instr_start + instr_len;
    if (instr_end > data.len) return error.UnexpectedEof;

    var offset = instr_end;
    const flags = try readFlags(allocator, data, point_count, &offset);
    defer allocator.free(flags);

    const x_coords = try readCoords(allocator, data, flags, &offset, 2, 16);
    defer allocator.free(x_coords);
    const y_coords = try readCoords(allocator, data, flags, &offset, 4, 32);
    defer allocator.free(y_coords);

    const contours = try buildContourRanges(allocator, end_pts, point_count);
    errdefer allocator.free(contours);

    const points = try buildPoints(allocator, flags, x_coords, y_coords);
    errdefer allocator.free(points);

    return .{
        .allocator = allocator,
        .contours = contours,
        .points = points,
        .instructions = data[instr_start..instr_end],
    };
}

const CurvePoint = struct {
    pos: Vec2,
    on_curve: bool,
};

pub fn contourToCurves(
    allocator: std.mem.Allocator,
    points: []const Point,
    scale: f32,
) ![]QuadBezier {
    if (points.len < 2) return &.{};

    var scaled: std.ArrayList(CurvePoint) = .empty;
    defer scaled.deinit(allocator);
    for (points) |point| {
        try scaled.append(allocator, .{
            .pos = point.scaled(scale),
            .on_curve = point.on_curve,
        });
    }

    var expanded: std.ArrayList(CurvePoint) = .empty;
    defer expanded.deinit(allocator);
    for (0..scaled.items.len) |i| {
        const curr = scaled.items[i];
        try expanded.append(allocator, curr);
        if (!curr.on_curve) {
            const next = scaled.items[(i + 1) % scaled.items.len];
            if (!next.on_curve) {
                try expanded.append(allocator, .{
                    .pos = Vec2.lerp(curr.pos, next.pos, 0.5),
                    .on_curve = true,
                });
            }
        }
    }

    return expandedContourToCurves(allocator, expanded.items);
}

fn expandedContourToCurves(allocator: std.mem.Allocator, points: []const CurvePoint) ![]QuadBezier {
    if (points.len < 2) return &.{};

    var curves: std.ArrayList(QuadBezier) = .empty;
    errdefer curves.deinit(allocator);

    const start_idx = firstOnCurvePoint(points);
    var idx = start_idx;
    var iterations: usize = 0;
    while (iterations < points.len + 1) {
        const p0 = points[idx % points.len];
        if (!p0.on_curve) {
            idx += 1;
            iterations += 1;
            continue;
        }

        const next1 = points[(idx + 1) % points.len];
        if (next1.on_curve) {
            try curves.append(allocator, .{
                .p0 = p0.pos,
                .p1 = Vec2.lerp(p0.pos, next1.pos, 0.5),
                .p2 = next1.pos,
            });
            idx += 1;
        } else {
            const next2 = points[(idx + 2) % points.len];
            try curves.append(allocator, .{
                .p0 = p0.pos,
                .p1 = next1.pos,
                .p2 = next2.pos,
            });
            idx += 2;
        }

        iterations += 1;
        if (idx % points.len == start_idx) break;
    }

    return curves.toOwnedSlice(allocator);
}

fn firstOnCurvePoint(points: []const CurvePoint) usize {
    for (points, 0..) |point, i| {
        if (point.on_curve) return i;
    }
    return 0;
}

test "parse simple glyph topology preserves instructions and points" {
    const data = [_]u8{
        0, 1, 0, 0, 0, 0, 0, 50, 0, 40, // simple glyph header, bbox ignored here
        0, 2, // one contour ending at point 2
        0, 1, 0xB0, // one instruction byte
        49, 51, 53, // point flags
        50, // x coordinate stream
        40, // y coordinate stream
    };

    var glyph = try parseSimpleGlyph(std.testing.allocator, &data, 0, 1);
    defer glyph.deinit();

    try std.testing.expectEqual(@as(usize, 1), glyph.contours.len);
    try std.testing.expectEqual(@as(u32, 0), glyph.contours[0].start);
    try std.testing.expectEqual(@as(u32, 3), glyph.contours[0].end);
    try std.testing.expectEqualSlices(u8, &.{0xB0}, glyph.instructions);
    try std.testing.expectEqual(Point{ .x = 0, .y = 0, .on_curve = true }, glyph.points[0]);
    try std.testing.expectEqual(Point{ .x = 50, .y = 0, .on_curve = true }, glyph.points[1]);
    try std.testing.expectEqual(Point{ .x = 50, .y = 40, .on_curve = true }, glyph.points[2]);

    const curves = try contourToCurves(std.testing.allocator, glyph.points, 1.0);
    defer std.testing.allocator.free(curves);
    try std.testing.expectEqual(@as(usize, 3), curves.len);
}
