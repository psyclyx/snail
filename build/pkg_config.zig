const std = @import("std");

fn requires(opengl: bool, vulkan: bool, harfbuzz: bool) []const u8 {
    if (opengl) {
        if (harfbuzz) {
            return if (vulkan) "gl harfbuzz vulkan" else "gl harfbuzz";
        }
        return if (vulkan) "gl vulkan" else "gl";
    }
    if (harfbuzz) {
        return if (vulkan) "harfbuzz vulkan" else "harfbuzz";
    }
    return if (vulkan) "vulkan" else "";
}

pub fn render(
    b: *std.Build,
    version: []const u8,
    opengl: bool,
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
    , .{ version, requires(opengl, vulkan, harfbuzz) });
}
