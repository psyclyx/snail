//! `Shape` and `Override`: the small value types layered on top of
//! `RecordKey` and `AtlasRecord`.
//!
//! A `Shape` is one element of a `Picture`: a record key plus a local
//! transform and a local color. Paint is looked up via `shape.key` from
//! the atlas. An `Override` is a per-instance modifier applied to the
//! whole picture during instanced emit.
//!
//! Both types are pure data — no allocations, no hidden state.

const std = @import("std");
const math = @import("../math/vec.zig");
const record_key_mod = @import("../atlas/record_key.zig");

pub const Transform2D = math.Transform2D;
pub const RecordKey = record_key_mod.RecordKey;

pub const Shape = struct {
    key: RecordKey,
    local_transform: Transform2D = .identity,
    local_color: [4]f32 = .{ 1, 1, 1, 1 },
};

pub const Override = struct {
    transform: Transform2D = .identity,
    tint: [4]f32 = .{ 1, 1, 1, 1 },

    pub const identity = Override{};
};

test "Shape has identity defaults" {
    const k = record_key_mod.unhintedGlyph(0, 1);
    const s = Shape{ .key = k };
    try std.testing.expect(s.local_transform.xx == 1);
    try std.testing.expect(s.local_transform.yy == 1);
    try std.testing.expect(s.local_transform.tx == 0);
    try std.testing.expect(s.local_color[0] == 1);
    try std.testing.expect(s.local_color[3] == 1);
}

test "Override identity is no-op" {
    const o = Override.identity;
    try std.testing.expect(o.transform.xx == 1);
    try std.testing.expect(o.tint[0] == 1);
    try std.testing.expect(o.tint[3] == 1);
}
