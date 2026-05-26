//! Caller-namespaced identity for atlas records.
//!
//! A `RecordKey` is 16 bytes of caller-meaningful data. The atlas dedups on the
//! whole key. Snail reserves well-known namespaces for its own producers; values
//! >= `ns_user_base` are free for callers to assign.
//!
//! Each namespace defines its own schema for the `a`, `b`, `c` fields — for the
//! built-in namespaces those schemas are documented below; for caller
//! namespaces the schema is whatever the caller decides.

const std = @import("std");

pub const RecordKey = extern struct {
    namespace: u32,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,

    pub fn eql(self: RecordKey, other: RecordKey) bool {
        return self.namespace == other.namespace and self.a == other.a and self.b == other.b and self.c == other.c;
    }

    pub fn hash(self: RecordKey) u64 {
        var h: u64 = 0x9e37_79b9_7f4a_7c15;
        h = mix(h, self.namespace);
        h = mix(h, self.a);
        h = mix(h, self.b);
        h = mix(h, self.c);
        return h;
    }

    fn mix(seed: u64, value: u32) u64 {
        var x = seed ^ @as(u64, value);
        x +%= 0x9e37_79b9_7f4a_7c15;
        x = (x ^ (x >> 30)) *% 0xbf58_476d_1ce4_e5b9;
        x = (x ^ (x >> 27)) *% 0x94d0_49bb_1331_11eb;
        return x ^ (x >> 31);
    }
};

/// Well-known namespaces. Callers should use values >= `ns.user_base` for their
/// own keys; snail will never assign new built-in namespaces below that line.
pub const ns = struct {
    /// Unhinted glyph: a=font_id, b=glyph_id, c=0.
    pub const unhinted_glyph: u32 = 1;
    /// Hinted glyph at a specific ppem: a=font_id, b=glyph_id, c=ppem_26_6.
    pub const hinted_glyph: u32 = 2;
    /// Filled path shape: caller-chosen a, b, c.
    pub const path_fill: u32 = 3;
    /// Stroked path shape: caller-chosen a, b, c.
    pub const path_stroke: u32 = 4;
    /// Paint record (gradient, image): caller-chosen a, b, c.
    pub const paint_record: u32 = 5;

    /// First namespace reserved for caller use.
    pub const user_base: u32 = 1024;
};

pub fn unhintedGlyph(font_id: u32, glyph_id: u16) RecordKey {
    return .{ .namespace = ns.unhinted_glyph, .a = font_id, .b = @intCast(glyph_id) };
}

pub fn hintedGlyph(font_id: u32, glyph_id: u16, ppem_26_6: u32) RecordKey {
    return .{ .namespace = ns.hinted_glyph, .a = font_id, .b = @intCast(glyph_id), .c = ppem_26_6 };
}

test "record key equality and hash" {
    const a = unhintedGlyph(0, 42);
    const b = unhintedGlyph(0, 42);
    const c = unhintedGlyph(0, 43);
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
    try std.testing.expect(a.hash() == b.hash());
}

test "user namespaces start at 1024" {
    try std.testing.expect(ns.user_base > ns.paint_record);
}
