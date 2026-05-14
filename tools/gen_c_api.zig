const std = @import("std");
const manifest = @import("manifest");

pub fn main(init: std.process.Init) !void {
    try writeHeader(init.io, "include/snail_generated.h");
    try writeZig(init.io, "src/snail/c_api/generated.zig");
}

fn writeHeader(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io,
        \\/* Generated from src/snail/c_api/manifest.zig by tools/gen_c_api.zig. */
        \\#ifndef SNAIL_GENERATED_H
        \\#define SNAIL_GENERATED_H
        \\
        \\/* Error codes */
        \\
    );
    for (manifest.errors) |err| {
        var buf: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "#define {s} {d}\n", .{ err.c_name, err.value });
        try file.writeStreamingAll(io, line);
    }
    try file.writeStreamingAll(io,
        \\
        \\/* Opaque handles */
        \\
    );
    for (manifest.handles) |handle| {
        var buf: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "typedef struct {s} {s};\n", .{ handle.name, handle.name });
        try file.writeStreamingAll(io, line);
    }
    try file.writeStreamingAll(io,
        \\
        \\#endif /* SNAIL_GENERATED_H */
        \\
    );
}

fn writeZig(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, "// Generated from src/snail/c_api/manifest.zig by tools/gen_c_api.zig.\n\n");
    for (manifest.errors) |err| {
        var buf: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "pub const {s}: c_int = {d};\n", .{ err.c_name, err.value });
        try file.writeStreamingAll(io, line);
    }
}
