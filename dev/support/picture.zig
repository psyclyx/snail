//! Minimal owned shape slice used by the demos and benchmark.
//!
//! This deliberately lives outside `snail`: scene ownership and composition
//! are caller policy. The renderer consumes the raw `shapes` slice.

const std = @import("std");
const snail = @import("snail");

pub const Picture = struct {
    allocator: std.mem.Allocator,
    shapes: []const snail.Shape,

    pub fn empty(allocator: std.mem.Allocator) Picture {
        return .{ .allocator = allocator, .shapes = &.{} };
    }

    pub fn from(allocator: std.mem.Allocator, shapes: []const snail.Shape) std.mem.Allocator.Error!Picture {
        if (shapes.len == 0) return empty(allocator);
        return fromOwnedSlice(allocator, try allocator.dupe(snail.Shape, shapes));
    }

    pub fn fromOwnedSlice(allocator: std.mem.Allocator, shapes: []snail.Shape) Picture {
        return .{ .allocator = allocator, .shapes = shapes };
    }

    pub fn deinit(self: *Picture) void {
        if (self.shapes.len > 0) self.allocator.free(@constCast(self.shapes));
        self.* = undefined;
    }

    pub fn concat(allocator: std.mem.Allocator, pictures: []const *const Picture) std.mem.Allocator.Error!Picture {
        var total: usize = 0;
        for (pictures) |picture| total += picture.shapes.len;
        if (total == 0) return empty(allocator);

        const shapes = try allocator.alloc(snail.Shape, total);
        var cursor: usize = 0;
        for (pictures) |picture| {
            @memcpy(shapes[cursor..][0..picture.shapes.len], picture.shapes);
            cursor += picture.shapes.len;
        }
        return fromOwnedSlice(allocator, shapes);
    }
};

test "concat preserves shape order" {
    const allocator = std.testing.allocator;
    var a = try Picture.from(allocator, &.{.{ .key = snail.record_key.unhintedGlyph(0, 1) }});
    defer a.deinit();
    var b = try Picture.from(allocator, &.{.{ .key = snail.record_key.unhintedGlyph(0, 2) }});
    defer b.deinit();
    var combined = try Picture.concat(allocator, &.{ &a, &b });
    defer combined.deinit();

    try std.testing.expectEqual(@as(usize, 2), combined.shapes.len);
    try std.testing.expect(combined.shapes[0].key.eql(a.shapes[0].key));
    try std.testing.expect(combined.shapes[1].key.eql(b.shapes[0].key));
}
