const std = @import("std");
const manifest = @import("manifest");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len == 1) return usage();

    if (std.mem.eql(u8, args[1], "--emit")) {
        if (args.len != 4) return usage();
        try emit(init.io, init.gpa, args[2], args[3]);
        return;
    }

    if (std.mem.eql(u8, args[1], "--check")) {
        if (args.len != 4) return usage();
        try check(init.io, init.gpa, args[2], args[3]);
        return;
    }

    return usage();
}

fn usage() error{InvalidArgument} {
    std.debug.print(
        \\usage:
        \\  gen-c-api --emit <header-path> <zig-path>
        \\  gen-c-api --check <header-path> <zig-path>
        \\
    , .{});
    return error.InvalidArgument;
}

fn emit(io: std.Io, allocator: std.mem.Allocator, header_path: []const u8, zig_path: []const u8) !void {
    const header = try renderHeader(allocator);
    defer allocator.free(header);
    const zig = try renderZig(allocator);
    defer allocator.free(zig);

    try writeFile(io, header_path, header);
    try writeFile(io, zig_path, zig);
}

fn check(io: std.Io, allocator: std.mem.Allocator, header_path: []const u8, zig_path: []const u8) !void {
    const expected_header = try renderHeader(allocator);
    defer allocator.free(expected_header);
    const expected_zig = try renderZig(allocator);
    defer allocator.free(expected_zig);

    try checkFile(io, allocator, header_path, expected_header);
    try checkFile(io, allocator, zig_path, expected_zig);
}

fn checkFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8, expected: []const u8) !void {
    const actual = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(actual);

    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("{s} differs from generated C API output\n", .{path});
        return error.GeneratedCapiOutOfDate;
    }
}

fn writeFile(io: std.Io, path: []const u8, contents: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, contents);
}

fn renderHeader(allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;

    try writer.writeAll(
        \\/* Generated from src/snail/c_api/manifest.zig by tools/gen_c_api.zig. */
        \\#ifndef SNAIL_GENERATED_H
        \\#define SNAIL_GENERATED_H
        \\
        \\/* Error codes */
        \\
    );
    for (manifest.errors) |err| {
        try writer.print("#define {s} {d}\n", .{ err.c_name, err.value });
    }
    try writer.writeAll(
        \\
        \\/* Opaque handles */
        \\
    );
    for (manifest.handles) |handle| {
        try writer.print("typedef struct {s} {s};\n", .{ handle.name, handle.name });
    }
    try writer.writeAll(
        \\
        \\#endif /* SNAIL_GENERATED_H */
        \\
    );

    return out.toOwnedSlice();
}

fn renderZig(allocator: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("// Generated from src/snail/c_api/manifest.zig by tools/gen_c_api.zig.\n\n");
    for (manifest.errors) |err| {
        try writer.print("pub const {s}: c_int = {d};\n", .{ err.c_name, err.value });
    }

    return out.toOwnedSlice();
}
