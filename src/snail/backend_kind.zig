const std = @import("std");

pub const BackendKind = enum(c_int) {
    gl = 0,
    vulkan = 1,
    cpu = 2,
    gles = 3,
};

test "backend kind ABI values are stable" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(BackendKind.gl));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(BackendKind.vulkan));
    try std.testing.expectEqual(@as(c_int, 2), @intFromEnum(BackendKind.cpu));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(BackendKind.gles));
}
