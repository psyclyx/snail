const std = @import("std");

const File = struct {
    path: []const u8,
};

const sources = [_]File{
    .{ .path = "src/snail/c_api/constants.zig" },
    .{ .path = "src/snail/c_api/font.zig" },
    .{ .path = "src/snail/c_api/image.zig" },
    .{ .path = "src/snail/c_api/misc.zig" },
    .{ .path = "src/snail/c_api/path.zig" },
    .{ .path = "src/snail/c_api/render.zig" },
    .{ .path = "src/snail/c_api/render_backends.zig" },
    .{ .path = "src/snail/c_api/resources.zig" },
    .{ .path = "src/snail/c_api/scene.zig" },
    .{ .path = "src/snail/c_api/shaders.zig" },
    .{ .path = "src/snail/c_api/text.zig" },
};

const headers = [_]File{
    .{ .path = "include/snail.h" },
    .{ .path = "include/snail_cpu.h" },
    .{ .path = "include/snail_gl.h" },
    .{ .path = "include/snail_vulkan.h" },
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const all_headers = try loadHeaders(init.io, arena);

    var missing = false;
    for (sources) |source| {
        const contents = try readFile(init.io, arena, source.path);
        var rest = contents;
        while (std.mem.indexOf(u8, rest, "pub export fn snail_")) |offset| {
            const start = offset + "pub export fn ".len;
            const tail = rest[start..];
            const name_end = std.mem.indexOfAny(u8, tail, "(\n\r\t ") orelse tail.len;
            const name = tail[0..name_end];
            if (!headerContains(all_headers, name)) {
                std.debug.print("{s}: exported {s} is missing from public headers\n", .{ source.path, name });
                missing = true;
            }
            rest = tail[name_end..];
        }
    }
    if (missing) return error.CApiHeaderMismatch;
}

fn loadHeaders(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    for (headers) |header| {
        const contents = try readFile(io, allocator, header.path);
        try writer.writeAll(contents);
        try writer.writeAll("\n");
    }
    return out.toOwnedSlice();
}

fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20));
}

fn headerContains(headers_blob: []const u8, name: []const u8) bool {
    return std.mem.indexOf(u8, headers_blob, name) != null;
}
