const std = @import("std");

fn requires(b: *std.Build, opengl: bool, gles30: bool, vulkan: bool, harfbuzz: bool) []const u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    const allocator = b.allocator;
    if (opengl) appendRequirement(allocator, &out, "gl");
    if (gles30) appendRequirement(allocator, &out, "glesv2");
    if (harfbuzz) appendRequirement(allocator, &out, "harfbuzz");
    if (vulkan) appendRequirement(allocator, &out, "vulkan");
    return out.toOwnedSlice(allocator) catch @panic("out of memory");
}

fn appendRequirement(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), name: []const u8) void {
    if (out.items.len > 0) out.append(allocator, ' ') catch @panic("out of memory");
    out.appendSlice(allocator, name) catch @panic("out of memory");
}

pub fn render(
    b: *std.Build,
    version: []const u8,
    opengl: bool,
    gles30: bool,
    vulkan: bool,
    harfbuzz: bool,
) []const u8 {
    return b.fmt(
        \\prefix=${{pcfiledir}}/../..
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: snail
        \\Description: GPU font rendering via direct Bezier curve evaluation (Slug algorithm)
        \\Version: {s}
        \\Libs: -L${{libdir}} -lsnail
        \\Cflags: -I${{includedir}}
        \\Requires: {s}
        \\
    , .{ version, requires(b, opengl, gles30, vulkan, harfbuzz) });
}
