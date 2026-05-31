const std = @import("std");

const bezier = @import("../../math/bezier.zig");
const tt_graphics = @import("graphics.zig");
const tt_outline = @import("outline.zig");
const vec = @import("../../math/vec.zig");

pub const QuadBezier = bezier.QuadBezier;
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
    /// Unscaled FUnit coordinates (FreeType's `orus`). IUP uses these for the
    /// interpolation ratio so that two FUnit-distinct points whose scaled
    /// pixel coords collapse to the same value still produce a meaningful
    /// lerp instead of a degenerate org1 == org2 shift.
    orus_x: i32 = 0,
    orus_y: i32 = 0,
    on_curve: bool,
    touched_x: bool = false,
    touched_y: bool = false,
};

pub const phantom_count = 4;

pub const PhantomMetrics = struct {
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    advance_width: u16,
    left_side_bearing: i16,
    advance_height: i32,
    top_side_bearing: i32 = 0,
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
                .orus_x = source.x,
                .orus_y = source.y,
                .on_curve = source.on_curve,
            };
        }
        return .{ .points = buffer[0..outline.len], .contours = contours };
    }

    pub fn initGlyphWithPhantoms(
        buffer: []Point,
        outline: []const tt_outline.Point,
        contours: []const tt_outline.ContourRange,
        environment: tt_graphics.Environment,
        phantoms: PhantomMetrics,
    ) Error!Zone {
        const point_count = outline.len + phantom_count;
        if (buffer.len < point_count) return Error.BufferTooSmall;
        const zone = try initGlyph(buffer, outline, contours, environment);
        initPhantomPoints(buffer[outline.len..][0..phantom_count], phantoms, environment);
        return .{ .points = buffer[0..point_count], .contours = zone.contours };
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

    pub fn coordinateVector(self: *const Zone, vector: tt_graphics.Vector, point: u32, original: bool) Error!i32 {
        return projectPoint(try self.get(point), vector, original);
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

    pub fn moveToVector(self: *Zone, projection: tt_graphics.Vector, freedom: tt_graphics.Vector, point: u32, target: i32) Error!void {
        const p = try self.getMutable(point);
        const current = projectPoint(p, projection, false);
        const delta = subWrap(target, current);
        const move_delta = try projectedMoveDelta(delta, projection, freedom);
        p.x = addWrap(p.x, move_delta.x);
        p.y = addWrap(p.y, move_delta.y);
        touchPointVector(p, freedom);
    }

    pub fn setOriginalCoordinate(self: *Zone, direction: Direction, point: u32, target: i32) Error!void {
        const p = try self.getMutable(point);
        switch (direction.axis) {
            .x => p.ox = applySign(target, direction.sign),
            .y => p.oy = applySign(target, direction.sign),
        }
    }

    pub fn setOriginalCoordinateVector(self: *Zone, projection: tt_graphics.Vector, point: u32, target: i32) Error!void {
        const p = try self.getMutable(point);
        const current = projectPoint(p, projection, true);
        const delta = subWrap(target, current);
        const move_delta = try projectedMoveDelta(delta, projection, projection);
        p.ox = addWrap(p.ox, move_delta.x);
        p.oy = addWrap(p.oy, move_delta.y);
    }

    pub fn shift(self: *Zone, freedom: Direction, point: u32, distance: i32) Error!void {
        const p = try self.getMutable(point);
        switch (freedom.axis) {
            .x => p.x = addWrap(p.x, applySign(distance, freedom.sign)),
            .y => p.y = addWrap(p.y, applySign(distance, freedom.sign)),
        }
        touchPoint(p, freedom.axis);
    }

    pub fn shiftVector(self: *Zone, freedom: tt_graphics.Vector, point: u32, distance: i32) Error!void {
        const p = try self.getMutable(point);
        p.x = addWrap(p.x, try vectorDistanceDelta(distance, freedom.x));
        p.y = addWrap(p.y, try vectorDistanceDelta(distance, freedom.y));
        touchPointVector(p, freedom);
    }

    pub fn shiftProjectedVector(
        self: *Zone,
        projection: tt_graphics.Vector,
        freedom: tt_graphics.Vector,
        point: u32,
        distance: i32,
    ) Error!void {
        const p = try self.getMutable(point);
        const move_delta = try projectedMoveDelta(distance, projection, freedom);
        p.x = addWrap(p.x, move_delta.x);
        p.y = addWrap(p.y, move_delta.y);
        touchPointVector(p, freedom);
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

    pub fn shiftContourProjectedVector(
        self: *Zone,
        projection: tt_graphics.Vector,
        freedom: tt_graphics.Vector,
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
                try self.shiftProjectedVector(projection, freedom, i, distance);
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
        return self.contourToCurvesXY(allocator, contour, scale, scale);
    }

    pub fn contourToCurvesXY(
        self: *const Zone,
        allocator: std.mem.Allocator,
        contour: tt_outline.ContourRange,
        scale_x: f32,
        scale_y: f32,
    ) ![]QuadBezier {
        if (contour.end > self.points.len or contour.start > contour.end) return Error.InvalidPoint;
        return pointsToCurves(allocator, self.points[contour.start..contour.end], scale_x, scale_y);
    }

    pub fn contoursToCurves(self: *const Zone, allocator: std.mem.Allocator, scale: f32) ![]QuadBezier {
        return self.contoursToCurvesXY(allocator, scale, scale);
    }

    pub fn contoursToCurvesXY(
        self: *const Zone,
        allocator: std.mem.Allocator,
        scale_x: f32,
        scale_y: f32,
    ) ![]QuadBezier {
        var out: std.ArrayList(QuadBezier) = .empty;
        errdefer out.deinit(allocator);

        for (self.contours) |contour| {
            const curves = try self.contourToCurvesXY(allocator, contour, scale_x, scale_y);
            defer if (curves.len > 0) allocator.free(curves);
            try out.appendSlice(allocator, curves);
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn horizontalAdvance(self: *const Zone, phantom_start: usize) Error!i32 {
        if (phantom_start + 1 >= self.points.len) return Error.InvalidPoint;
        return subWrap(self.points[phantom_start + 1].x, self.points[phantom_start].x);
    }

    pub fn originalHorizontalAdvance(self: *const Zone, phantom_start: usize) Error!i32 {
        if (phantom_start + 1 >= self.points.len) return Error.InvalidPoint;
        return subWrap(self.points[phantom_start + 1].ox, self.points[phantom_start].ox);
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

fn initPhantomPoints(points: []Point, metrics: PhantomMetrics, environment: tt_graphics.Environment) void {
    const left = @as(i32, metrics.x_min) - @as(i32, metrics.left_side_bearing);
    const right = left + @as(i32, metrics.advance_width);
    const top = @as(i32, metrics.y_max) + metrics.top_side_bearing;
    const bottom = top - metrics.advance_height;

    points[0] = phantomPoint(environment.scaleFUnitsX(left), 0, left, 0);
    points[1] = phantomPoint(environment.scaleFUnitsX(right), 0, right, 0);
    points[2] = phantomPoint(0, environment.scaleFUnitsY(top), 0, top);
    points[3] = phantomPoint(0, environment.scaleFUnitsY(bottom), 0, bottom);
}

fn phantomPoint(x: i32, y: i32, orus_x: i32, orus_y: i32) Point {
    return .{
        .x = x,
        .y = y,
        .ox = x,
        .oy = y,
        .orus_x = orus_x,
        .orus_y = orus_y,
        .on_curve = true,
    };
}

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

fn pointsToCurves(allocator: std.mem.Allocator, points: []const Point, scale_x: f32, scale_y: f32) ![]QuadBezier {
    if (points.len < 2) return &.{};

    var scaled: std.ArrayList(CurvePoint) = .empty;
    defer scaled.deinit(allocator);
    for (points) |point| {
        try scaled.append(allocator, .{
            .pos = Vec2.new(
                @as(f32, @floatFromInt(point.x)) * scale_x,
                @as(f32, @floatFromInt(point.y)) * scale_y,
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

fn touchPointVector(point: *Point, vector: tt_graphics.Vector) void {
    if (vector.x != 0) point.touched_x = true;
    if (vector.y != 0) point.touched_y = true;
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

fn orusCoord(point: Point, axis: tt_graphics.Axis) i32 {
    return switch (axis) {
        .x => point.orus_x,
        .y => point.orus_y,
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
    // Matches FreeType `_iup_worker_interpolate`: in-range comparison uses
    // scaled `org` coords (so the shift-by-neighbor branches stay in pixel
    // space), but the lerp ratio uses unscaled FUnit `orus` coords. The
    // FUnit denominator preserves precision when FUnit-distinct points
    // scale to identical pixel values — without it, the lerp would either
    // divide by zero (and hit the org1 == org2 shortcut) or compound the
    // scale-rounding error across the interpolated point.
    const org = originalCoord(point, axis);
    const org1 = originalCoord(prev, axis);
    const org2 = originalCoord(next, axis);
    const cur1 = currentCoord(prev, axis);
    const cur2 = currentCoord(next, axis);
    const orus = orusCoord(point, axis);
    const orus1 = orusCoord(prev, axis);
    const orus2 = orusCoord(next, axis);

    if (orus1 == orus2) return addWrap(org, subWrap(cur1, org1));

    if (orus1 < orus2) {
        if (org <= org1) return addWrap(org, subWrap(cur1, org1));
        if (org >= org2) return addWrap(org, subWrap(cur2, org2));
        return lerpCoord(orus, orus1, orus2, cur1, cur2);
    }

    if (org <= org2) return addWrap(org, subWrap(cur2, org2));
    if (org >= org1) return addWrap(org, subWrap(cur1, org1));
    return lerpCoord(orus, orus2, orus1, cur2, cur1);
}

/// Compute `cur1 + (key - key1) * (cur2 - cur1) / (key2 - key1)`. The key
/// arguments are unscaled FUnit coords; cur1/cur2 are 26.6 pixel coords.
/// The pixel/FUnit ratio cancels in the final result, so the return value
/// is in 26.6 pixels regardless of the key's units.
fn lerpCoord(key: i32, key1: i32, key2: i32, cur1: i32, cur2: i32) i32 {
    const numerator = (@as(i64, key) - @as(i64, key1)) * (@as(i64, cur2) - @as(i64, cur1));
    return @truncate(@as(i64, cur1) + @divTrunc(numerator, @as(i64, key2) - @as(i64, key1)));
}

fn applySign(value: i32, sign: i32) i32 {
    return @truncate(@as(i64, value) * @as(i64, sign));
}

fn projectPoint(point: *const Point, vector: tt_graphics.Vector, original: bool) i32 {
    const x = if (original) point.ox else point.x;
    const y = if (original) point.oy else point.y;
    return divRound(
        @as(i64, x) * @as(i64, vector.x) + @as(i64, y) * @as(i64, vector.y),
        tt_graphics.Vector.one,
    );
}

fn vectorDistanceDelta(distance: i32, component: i32) Error!i32 {
    return divRound(@as(i64, distance) * @as(i64, component), tt_graphics.Vector.one);
}

fn projectedMoveDelta(distance: i32, projection: tt_graphics.Vector, freedom: tt_graphics.Vector) Error!struct { x: i32, y: i32 } {
    const denom = @as(i64, projection.x) * @as(i64, freedom.x) + @as(i64, projection.y) * @as(i64, freedom.y);
    if (denom == 0) return Error.UnsupportedVector;
    const scaled = @as(i64, distance) * tt_graphics.Vector.one;
    return .{
        .x = divRound(scaled * @as(i64, freedom.x), denom),
        .y = divRound(scaled * @as(i64, freedom.y), denom),
    };
}

fn divRound(numerator: i64, denominator: i64) i32 {
    std.debug.assert(denominator != 0);
    const half = @divTrunc(absI64(denominator), 2);
    const adjusted = if ((numerator >= 0) == (denominator >= 0))
        numerator + half
    else
        numerator - half;
    return @truncate(@divTrunc(adjusted, denominator));
}

fn absI64(value: i64) i64 {
    return if (value < 0) -value else value;
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

test "point zone moves along non-axis freedom vectors" {
    var buffer: [1]Point = .{.{
        .x = 0,
        .y = 0,
        .ox = 0,
        .oy = 0,
        .on_curve = true,
    }};
    var zone: Zone = .{ .points = &buffer };
    const diagonal = tt_graphics.normalizeF2Dot14(tt_graphics.Vector.one, tt_graphics.Vector.one);

    try zone.moveToVector(tt_graphics.Vector.x_axis, diagonal, 0, 64);

    try std.testing.expectApproxEqAbs(@as(f32, 64), @as(f32, @floatFromInt(zone.points[0].x)), 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 64), @as(f32, @floatFromInt(zone.points[0].y)), 1.0);
    try std.testing.expect(zone.points[0].touched_x);
    try std.testing.expect(zone.points[0].touched_y);
}

test "point zone interpolates untouched contour points" {
    var buffer: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .orus_x = 0, .on_curve = true, .touched_x = true },
        .{ .x = 50, .y = 0, .ox = 50, .oy = 0, .orus_x = 50, .on_curve = true },
        .{ .x = 200, .y = 0, .ox = 100, .oy = 0, .orus_x = 100, .on_curve = true, .touched_x = true },
    };
    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = 3 }};
    var zone: Zone = .{ .points = &buffer, .contours = &contours };

    try zone.interpolateUntouched(.x);

    try std.testing.expectEqual(@as(i32, 100), zone.points[1].x);
    try std.testing.expect(!zone.points[1].touched_x);
}

test "point zone IUP lerp uses orus, decoupling rounding-distorted ox ratios" {
    // p1 is at FUnit position 50 out of [0, 100] — exactly halfway between
    // its touched neighbors. Scaling rounded p1.ox to 3 instead of 2.5,
    // distorting the org-space ratio to 3/5 = 0.6. Using ox for the lerp
    // would place p1 at 60% of (cur1..cur2), the wrong answer. Using
    // orus restores the true 0.5 ratio → cur1 + 0.5 * (cur2 - cur1) = 50.
    var buffer: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .orus_x = 0, .on_curve = true, .touched_x = true },
        .{ .x = 3, .y = 0, .ox = 3, .oy = 0, .orus_x = 50, .on_curve = true },
        .{ .x = 100, .y = 0, .ox = 5, .oy = 0, .orus_x = 100, .on_curve = true, .touched_x = true },
    };
    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = 3 }};
    var zone: Zone = .{ .points = &buffer, .contours = &contours };

    try zone.interpolateUntouched(.x);

    try std.testing.expectEqual(@as(i32, 50), zone.points[1].x);
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
