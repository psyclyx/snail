const std = @import("std");

pub const BackendKind = enum(c_int) {
    gl33 = 0,
    gl44 = 4,
    vulkan = 1,
    cpu = 2,
    gles3 = 3,
};

test "backend kind ABI values are stable" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(BackendKind.gl33));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(BackendKind.vulkan));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(BackendKind.cpu));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(BackendKind.gles3));
    try std.testing.expectEqual(@as(c_int, 4), @intFromEnum(BackendKind.gl44));
}
