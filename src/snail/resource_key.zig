const std = @import("std");

pub const ResourceKey = struct {
    id: u64,

    const namespace_shift = 62;
    const namespace_mask: u64 = 0b11 << namespace_shift;
    const payload_mask: u64 = ~namespace_mask;

    const Namespace = enum(u2) {
        numeric = 1,
        named = 2,
        derived = 3,
    };

    pub fn named(comptime name: []const u8) ResourceKey {
        return .{ .id = namespaced(.named, hashBytes(name)) };
    }

    pub fn fromName(name: []const u8) ResourceKey {
        return .{ .id = namespaced(.named, hashBytes(name)) };
    }

    pub fn fromId(id: u64) ResourceKey {
        return .{ .id = namespaced(.numeric, id) };
    }

    pub fn fromOpaque(id: u64) ResourceKey {
        if ((id & namespace_mask) == 0) return fromId(id);
        return .{ .id = id };
    }

    pub fn toOpaque(self: ResourceKey) u64 {
        return self.id;
    }

    pub fn toExternalOpaque(self: ResourceKey) u64 {
        if ((self.id & namespace_mask) == namespaced(.numeric, 0)) return self.id & payload_mask;
        return self.id;
    }

    pub fn eql(a: ResourceKey, b: ResourceKey) bool {
        return a.id == b.id;
    }

    fn namespaced(namespace: Namespace, raw: u64) u64 {
        return (@as(u64, @intFromEnum(namespace)) << namespace_shift) | (raw & payload_mask);
    }
};

pub const ResourceStamp = struct {
    identity: u64 = 0,
    layout: u64 = 0,
    content: u64 = 0,

    pub fn eql(a: ResourceStamp, b: ResourceStamp) bool {
        return a.identity == b.identity and a.layout == b.layout and a.content == b.content;
    }
};

pub const TextResourceKeys = struct {
    atlas: ResourceKey,
    paint: ?ResourceKey = null,
    /// Shared hint pool: bundle-scoped, set when the blob's bundle has any
    /// hinted glyphs. Multiple blobs from the same bundle share this key
    /// (the manifest auto-dedupes), so the hint record bytes are uploaded
    /// once per bundle rather than once per blob.
    hint: ?ResourceKey = null,
};

pub fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0x534e41494c5f4b45, bytes);
}

pub fn mix64(h: u64, v: u64) u64 {
    return h ^ (v +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2));
}

pub fn derived(parent: ResourceKey, label: []const u8) ResourceKey {
    var h = hashBytes(label);
    h = mix64(h, parent.id);
    return .{ .id = ResourceKey.namespaced(.derived, h) };
}

test "resource key namespaces are distinct" {
    try std.testing.expect(!ResourceKey.fromId(hashBytes("x")).eql(ResourceKey.fromName("x")));
    try std.testing.expect(!ResourceKey.fromId(7).eql(derived(ResourceKey.fromId(7), "child")));
    try std.testing.expect(ResourceKey.fromOpaque(7).eql(ResourceKey.fromId(7)));
    try std.testing.expectEqual(@as(u64, 7), ResourceKey.fromOpaque(7).toExternalOpaque());
    try std.testing.expect(ResourceKey.fromOpaque(ResourceKey.fromName("x").toOpaque()).eql(ResourceKey.fromName("x")));
}
