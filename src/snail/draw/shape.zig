//! `Shape`: the small value type layered on top of
//! `RecordKey` and `AtlasRecord`.
//!
//! A `Shape` is one emitted draw element: a record key plus a local
//! transform and a local color. Paint is looked up via `shape.key` from
//! the atlas.
//!
//! It is pure data — no allocations, no hidden state.

const std = @import("std");
const math = @import("../math/vec.zig");
const record_key_mod = @import("../atlas/record_key.zig");
const autohint_policy = @import("../font/autohint/policy.zig");

pub const Transform2D = math.Transform2D;
pub const RecordKey = record_key_mod.RecordKey;
pub const AutohintPolicy = autohint_policy.AutohintPolicy;

pub const Shape = struct {
    key: RecordKey,
    local_transform: Transform2D = .identity,
    local_color: [4]f32 = .{ 1, 1, 1, 1 },
    /// Draw-time fitting policy. Required exactly when `key` resolves to an
    /// immutable autohint analysis record.
    autohint_policy: ?AutohintPolicy = null,
};

test "Shape has identity defaults" {
    const k = record_key_mod.unhintedGlyph(0, 1);
    const s = Shape{ .key = k };
    try std.testing.expect(s.local_transform.xx == 1);
    try std.testing.expect(s.local_transform.yy == 1);
    try std.testing.expect(s.local_transform.tx == 0);
    try std.testing.expect(s.local_color[0] == 1);
    try std.testing.expect(s.local_color[3] == 1);
    try std.testing.expectEqual(@as(?AutohintPolicy, null), s.autohint_policy);
}
