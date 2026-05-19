const std = @import("std");

const bezier = @import("../math/bezier.zig");
const tt_graphics = @import("tt_graphics.zig");
const tt_outline = @import("tt_outline.zig");
const vec = @import("../math/vec.zig");

const QuadBezier = bezier.QuadBezier;
const Vec2 = vec.Vec2;

pub const Error = error{
    BufferTooSmall,
    InvalidPoint,
    UnsupportedVector,
};

pub const Point = struct {
    x: i32,
    y: i32,
    ox: i32,
    oy: i32,
    on_curve: bool,
    touched_x: bool = false,
    touched_y: bool = false,
};

pub const Zone = struct {
    points: []Point,
    contours: []const tt_outline.ContourRange = &.{},

    pub fn initGlyph(
        buffer: []Point,
        outline: []const tt_outline.Point,
        contours: []const tt_outline.ContourRange,
        environment: tt_graphics.Environment,
    ) Error!Zone {
        if (buffer.len < outline.len) return Error.BufferTooSmall;
        for (outline, 0..) |source, i| {
            const x = environment.scaleFUnitsX(source.x);
            const y = environment.scaleFUnitsY(source.y);
            buffer[i] = .{
                .x = x,
                .y = y,
                .ox = x,
                .oy = y,
                .on_curve = source.on_curve,
            };
        }
        return .{ .points = buffer[0..outline.len], .contours = contours };
    }

    pub fn initTwilight(buffer: []Point) Zone {
        for (buffer) |*point| {
            point.* = .{
                .x = 0,
                .y = 0,
                .ox = 0,
                .oy = 0,
                .on_curve = true,
            };
        }
        return .{ .points = buffer };
    }

    pub fn coordinate(self: *const Zone, direction: Direction, point: u32, original: bool) Error!i32 {
        const p = try self.get(point);
        const value = switch (direction.axis) {
            .x => if (original) p.ox else p.x,
            .y => if (original) p.oy else p.y,
        };
        return applySign(value, direction.sign);
    }

    pub fn moveTo(self: *Zone, projection: Direction, freedom: Direction, point: u32, target: i32) Error!void {
        if (projection.axis != freedom.axis) return Error.UnsupportedVector;
        const p = try self.getMutable(point);
        switch (projection.axis) {
            .x => p.x = applySign(target, projection.sign),
            .y => p.y = applySign(target, projection.sign),
        }
        touchPoint(p, freedom.axis);
    }

    pub fn setOriginalCoordinate(self: *Zone, direction: Direction, point: u32, target: i32) Error!void {
        const p = try self.getMutable(point);
        switch (direction.axis) {
            .x => p.ox = applySign(target, direction.sign),
            .y => p.oy = applySign(target, direction.sign),
        }
    }

    pub fn shift(self: *Zone, freedom: Direction, point: u32, distance: i32) Error!void {
        const p = try self.getMutable(point);
        switch (freedom.axis) {
            .x => p.x = addWrap(p.x, applySign(distance, freedom.sign)),
            .y => p.y = addWrap(p.y, applySign(distance, freedom.sign)),
        }
        touchPoint(p, freedom.axis);
    }

    pub fn shiftContour(
        self: *Zone,
        freedom: Direction,
        contour_index: u32,
        distance: i32,
        skip_point: ?u32,
    ) Error!void {
        const contour_i: usize = contour_index;
        if (contour_i >= self.contours.len) return Error.InvalidPoint;
        const contour = self.contours[contour_i];
        if (contour.end > self.points.len or contour.start > contour.end) return Error.InvalidPoint;

        var i: u32 = contour.start;
        while (i < contour.end) : (i += 1) {
            if (skip_point == null or skip_point.? != i) {
                try self.shift(freedom, i, distance);
            }
        }
    }

    pub fn touch(self: *Zone, freedom: Direction, point: u32) Error!void {
        touchPoint(try self.getMutable(point), freedom.axis);
    }

    pub fn untouch(self: *Zone, vector: tt_graphics.Vector, point: u32) Error!void {
        const p = try self.getMutable(point);
        if (directionFromVector(vector)) |direction| {
            switch (direction.axis) {
                .x => p.touched_x = false,
                .y => p.touched_y = false,
            }
        } else {
            p.touched_x = false;
            p.touched_y = false;
        }
    }

    pub fn interpolateUntouched(self: *Zone, axis: tt_graphics.Axis) Error!void {
        for (self.contours) |contour| {
            try self.interpolateContour(axis, contour);
        }
    }

    pub fn contourToCurves(self: *const Zone, allocator: std.mem.Allocator, contour: tt_outline.ContourRange, scale: f32) ![]QuadBezier {
        if (contour.end > self.points.len or contour.start > contour.end) return Error.InvalidPoint;
        return pointsToCurves(allocator, self.points[contour.start..contour.end], scale);
    }

    fn interpolateContour(self: *Zone, axis: tt_graphics.Axis, contour: tt_outline.ContourRange) Error!void {
        if (contour.end <= contour.start) return;
        const start: usize = contour.start;
        const end: usize = contour.end;
        if (end > self.points.len) return Error.InvalidPoint;

        const first_touched = self.findTouched(axis, start, end) orelse return;
        const second_touched = self.findTouchedAfter(axis, first_touched, start, end) orelse {
            const delta = subWrap(
                currentCoord(self.points[first_touched], axis),
                originalCoord(self.points[first_touched], axis),
            );
            var i = start;
            while (i < end) : (i += 1) {
                if (!isTouched(self.points[i], axis)) {
                    setCurrentCoord(&self.points[i], axis, addWrap(originalCoord(self.points[i], axis), delta));
                }
            }
            return;
        };

        var prev = first_touched;
        var next = second_touched;
        while (true) {
            self.interpolateRun(axis, prev, next, start, end);
            prev = next;
            next = self.findTouchedAfter(axis, prev, start, end) orelse first_touched;
            if (prev == first_touched) break;
        }
    }

    fn interpolateRun(self: *Zone, axis: tt_graphics.Axis, prev: usize, next: usize, start: usize, end: usize) void {
        var i = advanceContourIndex(prev, start, end);
        while (i != next) : (i = advanceContourIndex(i, start, end)) {
            if (!isTouched(self.points[i], axis)) {
                const value = interpolateCoord(self.points[i], self.points[prev], self.points[next], axis);
                setCurrentCoord(&self.points[i], axis, value);
            }
        }
    }

    fn findTouched(self: *const Zone, axis: tt_graphics.Axis, start: usize, end: usize) ?usize {
        var i = start;
        while (i < end) : (i += 1) {
            if (isTouched(self.points[i], axis)) return i;
        }
        return null;
    }

    fn findTouchedAfter(self: *const Zone, axis: tt_graphics.Axis, point: usize, start: usize, end: usize) ?usize {
        var i = advanceContourIndex(point, start, end);
        while (i != point) : (i = advanceContourIndex(i, start, end)) {
            if (isTouched(self.points[i], axis)) return i;
        }
        return null;
    }

    fn get(self: *const Zone, point: u32) Error!*const Point {
        const index: usize = point;
        if (index >= self.points.len) return Error.InvalidPoint;
        return &self.points[index];
    }

    fn getMutable(self: *Zone, point: u32) Error!*Point {
        const index: usize = point;
        if (index >= self.points.len) return Error.InvalidPoint;
        return &self.points[index];
    }
};

pub const Zones = struct {
    twilight: Zone,
    glyph: Zone,

    pub fn select(self: *Zones, pointer: tt_graphics.ZonePointer) *Zone {
        return switch (pointer) {
            .twilight => &self.twilight,
            .glyph => &self.glyph,
        };
    }

    pub fn selectConst(self: *const Zones, pointer: tt_graphics.ZonePointer) *const Zone {
        return switch (pointer) {
            .twilight => &self.twilight,
            .glyph => &self.glyph,
        };
    }
};

pub const Direction = struct {
    axis: tt_graphics.Axis,
    sign: i32,
};

pub fn directionFromVector(vector: tt_graphics.Vector) ?Direction {
    if (vector.x != 0 and vector.y == 0) {
        return .{ .axis = .x, .sign = if (vector.x < 0) -1 else 1 };
    }
    if (vector.y != 0 and vector.x == 0) {
        return .{ .axis = .y, .sign = if (vector.y < 0) -1 else 1 };
    }
    return null;
}

const CurvePoint = struct {
    pos: Vec2,
    on_curve: bool,
};

fn pointsToCurves(allocator: std.mem.Allocator, points: []const Point, scale: f32) ![]QuadBezier {
    if (points.len < 2) return &.{};

    var scaled: std.ArrayList(CurvePoint) = .empty;
    defer scaled.deinit(allocator);
    for (points) |point| {
        try scaled.append(allocator, .{
            .pos = Vec2.new(
                @as(f32, @floatFromInt(point.x)) * scale,
                @as(f32, @floatFromInt(point.y)) * scale,
            ),
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

fn touchPoint(point: *Point, axis: tt_graphics.Axis) void {
    switch (axis) {
        .x => point.touched_x = true,
        .y => point.touched_y = true,
    }
}

fn isTouched(point: Point, axis: tt_graphics.Axis) bool {
    return switch (axis) {
        .x => point.touched_x,
        .y => point.touched_y,
    };
}

fn originalCoord(point: Point, axis: tt_graphics.Axis) i32 {
    return switch (axis) {
        .x => point.ox,
        .y => point.oy,
    };
}

fn currentCoord(point: Point, axis: tt_graphics.Axis) i32 {
    return switch (axis) {
        .x => point.x,
        .y => point.y,
    };
}

fn setCurrentCoord(point: *Point, axis: tt_graphics.Axis, value: i32) void {
    switch (axis) {
        .x => point.x = value,
        .y => point.y = value,
    }
}

fn advanceContourIndex(point: usize, start: usize, end: usize) usize {
    const next = point + 1;
    return if (next == end) start else next;
}

fn interpolateCoord(point: Point, prev: Point, next: Point, axis: tt_graphics.Axis) i32 {
    const org = originalCoord(point, axis);
    const org1 = originalCoord(prev, axis);
    const org2 = originalCoord(next, axis);
    const cur1 = currentCoord(prev, axis);
    const cur2 = currentCoord(next, axis);

    if (org1 == org2) return addWrap(org, subWrap(cur1, org1));

    if (org1 < org2) {
        if (org <= org1) return addWrap(org, subWrap(cur1, org1));
        if (org >= org2) return addWrap(org, subWrap(cur2, org2));
        return lerpCoord(org, org1, org2, cur1, cur2);
    }

    if (org <= org2) return addWrap(org, subWrap(cur2, org2));
    if (org >= org1) return addWrap(org, subWrap(cur1, org1));
    return lerpCoord(org, org2, org1, cur2, cur1);
}

fn lerpCoord(org: i32, org1: i32, org2: i32, cur1: i32, cur2: i32) i32 {
    const numerator = (@as(i64, org) - @as(i64, org1)) * (@as(i64, cur2) - @as(i64, cur1));
    return @truncate(@as(i64, cur1) + @divTrunc(numerator, @as(i64, org2) - @as(i64, org1)));
}

fn applySign(value: i32, sign: i32) i32 {
    return @truncate(@as(i64, value) * @as(i64, sign));
}

fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
}

fn subWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) - @as(i64, rhs));
}

test "point zone scales glyph points without allocation" {
    const raw = [_]tt_outline.Point{
        .{ .x = 0, .y = 0, .on_curve = true },
        .{ .x = 50, .y = -50, .on_curve = false },
    };
    var buffer: [2]Point = undefined;
    const env: tt_graphics.Environment = .{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
        .units_per_em = 1000,
    };

    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = @intCast(raw.len) }};
    const zone = try Zone.initGlyph(&buffer, &raw, &contours, env);

    try std.testing.expectEqual(@as(i32, 32), zone.points[1].x);
    try std.testing.expectEqual(@as(i32, -38), zone.points[1].y);
    try std.testing.expect(!zone.points[1].on_curve);
}

test "point zone moves and shifts directed axis coordinates" {
    var buffer: [1]Point = .{.{
        .x = 10,
        .y = 20,
        .ox = 10,
        .oy = 20,
        .on_curve = true,
    }};
    var zone: Zone = .{ .points = &buffer };
    const x_pos: Direction = .{ .axis = .x, .sign = 1 };
    const x_neg: Direction = .{ .axis = .x, .sign = -1 };

    try zone.moveTo(x_neg, x_neg, 0, -64);
    try std.testing.expectEqual(@as(i32, 64), zone.points[0].x);
    try std.testing.expect(zone.points[0].touched_x);

    try zone.shift(x_pos, 0, 16);
    try std.testing.expectEqual(@as(i32, 80), zone.points[0].x);
}

test "point zone interpolates untouched contour points" {
    var buffer: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true, .touched_x = true },
        .{ .x = 50, .y = 0, .ox = 50, .oy = 0, .on_curve = true },
        .{ .x = 200, .y = 0, .ox = 100, .oy = 0, .on_curve = true, .touched_x = true },
    };
    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = 3 }};
    var zone: Zone = .{ .points = &buffer, .contours = &contours };

    try zone.interpolateUntouched(.x);

    try std.testing.expectEqual(@as(i32, 100), zone.points[1].x);
    try std.testing.expect(!zone.points[1].touched_x);
}

test "point zone shifts a contour range" {
    var buffer: [4]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 10, .y = 0, .ox = 10, .oy = 0, .on_curve = true },
        .{ .x = 20, .y = 0, .ox = 20, .oy = 0, .on_curve = true },
        .{ .x = 30, .y = 0, .ox = 30, .oy = 0, .on_curve = true },
    };
    const contours = [_]tt_outline.ContourRange{
        .{ .start = 0, .end = 2 },
        .{ .start = 2, .end = 4 },
    };
    var zone: Zone = .{ .points = &buffer, .contours = &contours };
    const x_pos: Direction = .{ .axis = .x, .sign = 1 };

    try zone.shiftContour(x_pos, 1, 5, 3);

    try std.testing.expectEqual(@as(i32, 25), zone.points[2].x);
    try std.testing.expectEqual(@as(i32, 30), zone.points[3].x);
    try std.testing.expect(zone.points[2].touched_x);
    try std.testing.expect(!zone.points[3].touched_x);
}

test "point zone converts hinted contour points to curves" {
    var buffer: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 64, .y = 64, .ox = 64, .oy = 64, .on_curve = false },
        .{ .x = 128, .y = 0, .ox = 128, .oy = 0, .on_curve = true },
    };
    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = 3 }};
    const zone: Zone = .{ .points = &buffer, .contours = &contours };

    const curves = try zone.contourToCurves(std.testing.allocator, contours[0], 1.0 / 64.0);
    defer std.testing.allocator.free(curves);

    try std.testing.expectEqual(@as(usize, 2), curves.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), curves[0].p1.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), curves[0].p1.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), curves[0].p2.x, 0.001);
}
