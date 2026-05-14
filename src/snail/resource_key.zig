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

pub fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0x534e41494c5f4b45, bytes);
}

pub fn mix64(h: u64, v: u64) u64 {
    return h ^ (v +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2));
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
                        break :blk ResourceKey.fromName(std.mem.trimRight(u8, slice, "\x00"));
                    }
                },
                else => {},
            }
            break :blk ResourceKey.fromId(@intCast(@intFromPtr(key_value)));
        },
        else => @compileError("resource keys must be enum literals, enums, strings, integers, or pointers"),
    };
}

pub fn pointerResourceKey(comptime prefix: []const u8, ptr: anytype) ResourceKey {
    var h = hashBytes(prefix);
    h = mix64(h, @intCast(@intFromPtr(ptr)));
    return .{ .id = h, .name = prefix };
}
