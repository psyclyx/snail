const std = @import("std");

const tt_graphics = @import("tt_graphics.zig");
const tt_outline = @import("tt_outline.zig");

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

    pub fn initGlyph(buffer: []Point, outline: []const tt_outline.Point, environment: tt_graphics.Environment) Error!Zone {
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
        return .{ .points = buffer[0..outline.len] };
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

    pub fn shift(self: *Zone, freedom: Direction, point: u32, distance: i32) Error!void {
        const p = try self.getMutable(point);
        switch (freedom.axis) {
            .x => p.x = addWrap(p.x, applySign(distance, freedom.sign)),
            .y => p.y = addWrap(p.y, applySign(distance, freedom.sign)),
        }
        touchPoint(p, freedom.axis);
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

fn touchPoint(point: *Point, axis: tt_graphics.Axis) void {
    switch (axis) {
        .x => point.touched_x = true,
        .y => point.touched_y = true,
    }
}

fn applySign(value: i32, sign: i32) i32 {
    return @truncate(@as(i64, value) * @as(i64, sign));
}

fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
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

    const zone = try Zone.initGlyph(&buffer, &raw, env);

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
