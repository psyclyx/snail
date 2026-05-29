//! `Picture`: an immutable list of shapes plus a bounding box.
//!
//! Pure data — no refcounts, no page references, no atlas references. A
//! picture is meaningful when paired with an atlas that resolves its keys;
//! without an atlas it's still a valid value (comparable, shareable), but
//! emit-time resolution will fail.
//!
//! Construction functions (`from`, `concat`, `append`, `transformed`,
//! `tinted`) return new pictures that own their own shape array. The
//! original picture is not mutated.
//!
//! The bbox is the union of each shape's local-transform translation
//! treated as a point. That gives a rough spatial extent without needing
//! atlas resolution; callers who need a geometric bbox can recompute one
//! at emit time using `Atlas.lookupRecord`.

const std = @import("std");

const math = @import("math/vec.zig");
const bezier = @import("math/bezier.zig");
const shape_mod = @import("shape.zig");

pub const Transform2D = math.Transform2D;
pub const Vec2 = math.Vec2;
pub const BBox = bezier.BBox;
pub const Shape = shape_mod.Shape;

pub const Picture = struct {
    allocator: std.mem.Allocator,
    shapes: []const Shape,
    bbox: BBox,

    /// Identity picture. No shapes, zero bbox.
    pub fn empty(allocator: std.mem.Allocator) Picture {
        return .{
            .allocator = allocator,
            .shapes = &.{},
            .bbox = .{ .min = .zero, .max = .zero },
        };
    }

    /// Build a picture by copying `shapes` into a fresh allocation.
    pub fn from(allocator: std.mem.Allocator, shapes: []const Shape) std.mem.Allocator.Error!Picture {
        const buf = try allocator.alloc(Shape, shapes.len);
        @memcpy(buf, shapes);
        return .{
            .allocator = allocator,
            .shapes = buf,
            .bbox = computeBBox(buf),
        };
    }

    pub fn deinit(self: *Picture) void {
        if (self.shapes.len > 0) {
            self.allocator.free(@constCast(self.shapes));
        }
        self.* = undefined;
    }

    /// Concatenate pictures in order. Z-order is preserved across inputs.
    pub fn concat(allocator: std.mem.Allocator, pictures: []const *const Picture) std.mem.Allocator.Error!Picture {
        var total: usize = 0;
        for (pictures) |p| total += p.shapes.len;
        const buf = try allocator.alloc(Shape, total);
        var cursor: usize = 0;
        for (pictures) |p| {
            @memcpy(buf[cursor..][0..p.shapes.len], p.shapes);
            cursor += p.shapes.len;
        }
        return .{
            .allocator = allocator,
            .shapes = buf,
            .bbox = computeBBox(buf),
        };
    }

    /// Return a new picture that is `self` followed by `more`. The original
    /// picture is unaffected.
    pub fn append(self: *const Picture, allocator: std.mem.Allocator, more: []const Shape) std.mem.Allocator.Error!Picture {
        const buf = try allocator.alloc(Shape, self.shapes.len + more.len);
        @memcpy(buf[0..self.shapes.len], self.shapes);
        @memcpy(buf[self.shapes.len..], more);
        return .{
            .allocator = allocator,
            .shapes = buf,
            .bbox = computeBBox(buf),
        };
    }

    /// Return a new picture with `t` composed into each shape's
    /// local transform (left-multiplied: `t * shape.local_transform`).
    pub fn transformed(self: *const Picture, allocator: std.mem.Allocator, t: Transform2D) std.mem.Allocator.Error!Picture {
        const buf = try allocator.alloc(Shape, self.shapes.len);
        for (self.shapes, 0..) |s, i| {
            var copy = s;
            copy.local_transform = Transform2D.multiply(t, s.local_transform);
            buf[i] = copy;
        }
        return .{
            .allocator = allocator,
            .shapes = buf,
            .bbox = computeBBox(buf),
        };
    }

    /// Return a new picture with `tint` multiplied into each shape's
    /// local color (componentwise).
    pub fn tinted(self: *const Picture, allocator: std.mem.Allocator, tint: [4]f32) std.mem.Allocator.Error!Picture {
        const buf = try allocator.alloc(Shape, self.shapes.len);
        for (self.shapes, 0..) |s, i| {
            var copy = s;
            copy.local_color = .{
                s.local_color[0] * tint[0],
                s.local_color[1] * tint[1],
                s.local_color[2] * tint[2],
                s.local_color[3] * tint[3],
            };
            buf[i] = copy;
        }
        return .{
            .allocator = allocator,
            .shapes = buf,
            .bbox = self.bbox, // tint doesn't move shapes
        };
    }
};

/// BBox of the local_transform translation points. Treats each shape's
/// origin as a zero-extent point; emit-time atlas resolution can produce
/// a tighter geometric bbox per shape, but that requires atlas access.
fn computeBBox(shapes: []const Shape) BBox {
    if (shapes.len == 0) return .{ .min = .zero, .max = .zero };
    var min_x: f32 = shapes[0].local_transform.tx;
    var min_y: f32 = shapes[0].local_transform.ty;
    var max_x: f32 = min_x;
    var max_y: f32 = min_y;
    for (shapes[1..]) |s| {
        if (s.local_transform.tx < min_x) min_x = s.local_transform.tx;
        if (s.local_transform.ty < min_y) min_y = s.local_transform.ty;
        if (s.local_transform.tx > max_x) max_x = s.local_transform.tx;
        if (s.local_transform.ty > max_y) max_y = s.local_transform.ty;
    }
    return .{
        .min = Vec2.new(min_x, min_y),
        .max = Vec2.new(max_x, max_y),
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const record_key = @import("record_key.zig");

fn keyAt(i: u16) record_key.RecordKey {
    return record_key.unhintedGlyph(0, i);
}

test "empty picture has no shapes" {
    var p = Picture.empty(testing.allocator);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 0), p.shapes.len);
}

test "from copies shapes and computes translation bbox" {
    const shapes = [_]Shape{
        .{ .key = keyAt(0), .local_transform = .translate(0, 0) },
        .{ .key = keyAt(1), .local_transform = .translate(10, 5) },
        .{ .key = keyAt(2), .local_transform = .translate(-3, 8) },
    };
    var p = try Picture.from(testing.allocator, &shapes);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 3), p.shapes.len);
    try testing.expectEqual(@as(f32, -3), p.bbox.min.x);
    try testing.expectEqual(@as(f32, 0), p.bbox.min.y);
    try testing.expectEqual(@as(f32, 10), p.bbox.max.x);
    try testing.expectEqual(@as(f32, 8), p.bbox.max.y);
}

test "concat is associative on shape order" {
    const a_shapes = [_]Shape{.{ .key = keyAt(0) }};
    const b_shapes = [_]Shape{.{ .key = keyAt(1) }};
    const c_shapes = [_]Shape{.{ .key = keyAt(2) }};

    var a = try Picture.from(testing.allocator, &a_shapes);
    defer a.deinit();
    var b = try Picture.from(testing.allocator, &b_shapes);
    defer b.deinit();
    var c = try Picture.from(testing.allocator, &c_shapes);
    defer c.deinit();

    var ab_c_inner = try Picture.concat(testing.allocator, &.{ &a, &b });
    defer ab_c_inner.deinit();
    var ab_c = try Picture.concat(testing.allocator, &.{ &ab_c_inner, &c });
    defer ab_c.deinit();

    var bc_inner = try Picture.concat(testing.allocator, &.{ &b, &c });
    defer bc_inner.deinit();
    var a_bc = try Picture.concat(testing.allocator, &.{ &a, &bc_inner });
    defer a_bc.deinit();

    try testing.expectEqual(@as(usize, 3), ab_c.shapes.len);
    try testing.expectEqual(@as(usize, 3), a_bc.shapes.len);
    for (ab_c.shapes, a_bc.shapes) |x, y| {
        try testing.expect(x.key.eql(y.key));
    }
}

test "append leaves the original intact" {
    var a = try Picture.from(testing.allocator, &.{.{ .key = keyAt(0) }});
    defer a.deinit();
    var b = try a.append(testing.allocator, &.{.{ .key = keyAt(1) }});
    defer b.deinit();
    try testing.expectEqual(@as(usize, 1), a.shapes.len);
    try testing.expectEqual(@as(usize, 2), b.shapes.len);
    try testing.expect(b.shapes[0].key.eql(keyAt(0)));
    try testing.expect(b.shapes[1].key.eql(keyAt(1)));
}

test "transformed composes left-to-right onto local_transform" {
    const shapes = [_]Shape{
        .{ .key = keyAt(0), .local_transform = .translate(5, 0) },
    };
    var a = try Picture.from(testing.allocator, &shapes);
    defer a.deinit();
    var b = try a.transformed(testing.allocator, .scale(2, 2));
    defer b.deinit();
    // scale(2,2) * translate(5,0) = translate(10,0) with x/y scale 2.
    const t = b.shapes[0].local_transform;
    try testing.expectEqual(@as(f32, 2), t.xx);
    try testing.expectEqual(@as(f32, 2), t.yy);
    try testing.expectEqual(@as(f32, 10), t.tx);
    try testing.expectEqual(@as(f32, 0), t.ty);
}

test "tinted multiplies local_color componentwise" {
    const shapes = [_]Shape{
        .{ .key = keyAt(0), .local_color = .{ 0.5, 1.0, 1.0, 1.0 } },
    };
    var a = try Picture.from(testing.allocator, &shapes);
    defer a.deinit();
    var b = try a.tinted(testing.allocator, .{ 0.5, 0.5, 0.5, 1.0 });
    defer b.deinit();
    try testing.expectApproxEqAbs(@as(f32, 0.25), b.shapes[0].local_color[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), b.shapes[0].local_color[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), b.shapes[0].local_color[3], 1e-6);
}
