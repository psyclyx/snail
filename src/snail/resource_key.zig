const std = @import("std");

pub const ResourceKey = struct {
    id: u64,
    name: []const u8 = "",

    pub fn named(comptime name: []const u8) ResourceKey {
        return .{ .id = hashBytes(name), .name = name };
    }

    pub fn fromName(name: []const u8) ResourceKey {
        return .{ .id = hashBytes(name), .name = name };
    }

    pub fn fromId(id: u64) ResourceKey {
        return .{ .id = id };
    }

    pub fn eql(a: ResourceKey, b: ResourceKey) bool {
        return a.id == b.id;
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
    return .{ .id = h };
}

pub fn resourceKey(key_value: anytype) ResourceKey {
    const T = @TypeOf(key_value);
    if (T == ResourceKey) return key_value;
    return switch (@typeInfo(T)) {
        .enum_literal => ResourceKey.fromName(@tagName(key_value)),
        .@"enum" => ResourceKey.fromName(@tagName(key_value)),
        .comptime_int, .int => ResourceKey.fromId(@intCast(key_value)),
        .pointer => |ptr| blk: {
            if (ptr.child == u8) break :blk ResourceKey.fromName(key_value);
            switch (@typeInfo(ptr.child)) {
                .array => |array| {
                    if (array.child == u8) {
                        const slice: []const u8 = key_value;
                        break :blk ResourceKey.fromName(std.mem.trimEnd(u8, slice, "\x00"));
                    }
                },
                else => {},
            }
            @compileError("resource key pointers must point to u8 strings; use ResourceKey.fromId for explicit numeric keys");
        },
        else => @compileError("resource keys must be enum literals, enums, strings, or integers"),
    };
}
