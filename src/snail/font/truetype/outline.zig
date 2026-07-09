const std = @import("std");

const bezier = @import("../../math/bezier.zig");
const vec = @import("../../math/vec.zig");

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

pub const ComponentTransform = struct {
    xx: f32 = 1,
    xy: f32 = 0,
    yx: f32 = 0,
    yy: f32 = 1,

    pub fn apply(self: ComponentTransform, point: Vec2) Vec2 {
        return .{
            .x = self.xx * point.x + self.xy * point.y,
            .y = self.yx * point.x + self.yy * point.y,
        };
    }

    pub fn concat(self: ComponentTransform, child: ComponentTransform) ComponentTransform {
        return .{
            .xx = self.xx * child.xx + self.xy * child.yx,
            .xy = self.xx * child.xy + self.xy * child.yy,
            .yx = self.yx * child.xx + self.yy * child.yx,
            .yy = self.yx * child.xy + self.yy * child.yy,
        };
    }
};

pub const CompoundComponent = struct {
    flags: u16,
    glyph_id: u16,
    arg1: i16,
    arg2: i16,
    dx: f32 = 0,
    dy: f32 = 0,
    args_are_xy: bool,
    transform: ComponentTransform = .{},

    pub fn roundXYToGrid(self: CompoundComponent) bool {
        return self.flags & component_round_xy_to_grid != 0;
    }

    pub fn useMyMetrics(self: CompoundComponent) bool {
        return self.flags & component_use_my_metrics != 0;
    }
};

pub const CompoundGlyph = struct {
    allocator: std.mem.Allocator,
    components: []CompoundComponent,
    instructions: []const u8,

    pub fn deinit(self: *CompoundGlyph) void {
        self.allocator.free(self.components);
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

pub fn parseCompoundGlyph(
    allocator: std.mem.Allocator,
    data: []const u8,
    base: usize,
    unit_scale: f32,
) ParseError!CompoundGlyph {
    var components: std.ArrayList(CompoundComponent) = .empty;
    errdefer components.deinit(allocator);

    var offset: usize = base + 10;
    var more = true;
    var has_instructions = false;
    while (more) {
        const flags = try readU16(data, offset);
        const glyph_id = try readU16(data, offset + 2);
        offset += 4;

        const args = try readComponentArgs(data, &offset, flags);
        const transform = try readComponentTransform(data, &offset, flags);
        const args_are_xy = flags & component_args_are_xy_values != 0;
        try components.append(allocator, .{
            .flags = flags,
            .glyph_id = glyph_id,
            .arg1 = args[0],
            .arg2 = args[1],
            .dx = if (args_are_xy) @as(f32, @floatFromInt(args[0])) * unit_scale else 0,
            .dy = if (args_are_xy) @as(f32, @floatFromInt(args[1])) * unit_scale else 0,
            .args_are_xy = args_are_xy,
            .transform = transform,
        });

        has_instructions = has_instructions or (flags & component_has_instructions != 0);
        more = flags & component_more_components != 0;
    }

    const instructions = if (has_instructions) blk: {
        const length = try readU16(data, offset);
        const start = offset + 2;
        const end = start + length;
        if (end > data.len) return error.UnexpectedEof;
        break :blk data[start..end];
    } else &.{};

    return .{
        .allocator = allocator,
        .components = try components.toOwnedSlice(allocator),
        .instructions = instructions,
    };
}

const component_arg_1_and_2_are_words = 0x0001;
const component_args_are_xy_values = 0x0002;
const component_round_xy_to_grid = 0x0004;
const component_has_scale = 0x0008;
const component_more_components = 0x0020;
const component_has_xy_scale = 0x0040;
const component_has_two_by_two = 0x0080;
const component_has_instructions = 0x0100;
const component_use_my_metrics = 0x0200;

fn readComponentArgs(data: []const u8, offset: *usize, flags: u16) ParseError![2]i16 {
    if (flags & component_arg_1_and_2_are_words != 0) {
        const arg1 = try readI16(data, offset.*);
        const arg2 = try readI16(data, offset.* + 2);
        offset.* += 4;
        return .{ arg1, arg2 };
    }

    if (offset.* + 2 > data.len) return error.UnexpectedEof;
    const arg1: i8 = @bitCast(data[offset.*]);
    const arg2: i8 = @bitCast(data[offset.* + 1]);
    offset.* += 2;
    return .{ arg1, arg2 };
}

fn readComponentTransform(data: []const u8, offset: *usize, flags: u16) ParseError!ComponentTransform {
    if (flags & component_has_scale != 0) {
        const scale = try readF2Dot14(data, offset.*);
        offset.* += 2;
        return .{ .xx = scale, .yy = scale };
    }
    if (flags & component_has_xy_scale != 0) {
        const xx = try readF2Dot14(data, offset.*);
        const yy = try readF2Dot14(data, offset.* + 2);
        offset.* += 4;
        return .{ .xx = xx, .yy = yy };
    }
    if (flags & component_has_two_by_two != 0) {
        const xx = try readF2Dot14(data, offset.*);
        const xy = try readF2Dot14(data, offset.* + 2);
        const yx = try readF2Dot14(data, offset.* + 4);
        const yy = try readF2Dot14(data, offset.* + 6);
        offset.* += 8;
        return .{ .xx = xx, .xy = xy, .yx = yx, .yy = yy };
    }
    return .{};
}

fn readF2Dot14(data: []const u8, offset: usize) ParseError!f32 {
    return @as(f32, @floatFromInt(try readI16(data, offset))) / 16384.0;
}

/// One outline point tagged on/off-curve, in curve space. Shared with
/// `points.zig`'s zone-space contour expansion.
pub const CurvePoint = struct {
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

/// Convert a contour of on/off-curve points (off-curve midpoints already
/// implied) into quadratic Béziers. Shared by `contourToCurves` and
/// `points.zig`'s zone-space equivalent.
pub fn expandedContourToCurves(allocator: std.mem.Allocator, points: []const CurvePoint) ![]QuadBezier {
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

pub fn firstOnCurvePoint(points: []const CurvePoint) usize {
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

test "parse compound glyph preserves component flags transform and instructions" {
    const data = [_]u8{
        0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, // compound glyph header, bbox ignored here
        0x01, 0x0B, // words, xy args, scale, instructions
        0x00, 0x07, // component glyph id
        0x00, 0x14, 0xFF, 0xF6, // dx = 20, dy = -10
        0x20, 0x00, // F2DOT14 scale = 0.5
        0x00, 0x01, 0x2A, // instruction bytes
    };

    var glyph = try parseCompoundGlyph(std.testing.allocator, &data, 0, 0.01);
    defer glyph.deinit();

    try std.testing.expectEqual(@as(usize, 1), glyph.components.len);
    try std.testing.expectEqual(@as(u16, 7), glyph.components[0].glyph_id);
    try std.testing.expect(glyph.components[0].args_are_xy);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), glyph.components[0].dx, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), glyph.components[0].dy, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), glyph.components[0].transform.xx, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), glyph.components[0].transform.yy, 1e-6);
    try std.testing.expectEqualSlices(u8, &.{0x2A}, glyph.instructions);
}

test "component transform applies and composes two by two matrices" {
    const parent = ComponentTransform{ .xx = 2, .xy = 0.5, .yx = -1, .yy = 3 };
    const child = ComponentTransform{ .xx = 0.25, .xy = 4, .yx = 2, .yy = -0.5 };
    const point = Vec2{ .x = 4, .y = 6 };

    const applied = parent.apply(point);
    try std.testing.expectApproxEqAbs(@as(f32, 11), applied.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 14), applied.y, 1e-6);

    const composed = parent.concat(child).apply(point);
    const sequential = parent.apply(child.apply(point));
    try std.testing.expectApproxEqAbs(sequential.x, composed.x, 1e-6);
    try std.testing.expectApproxEqAbs(sequential.y, composed.y, 1e-6);
}
