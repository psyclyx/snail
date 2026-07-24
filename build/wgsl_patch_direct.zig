//! Normalize Slang's direct WGSL output.
//!
//! Slang v2026.5.2 correctly copies interpolation attributes onto the
//! synthesized entry-point IO struct, but can also leave the same attribute
//! on an ordinary helper struct when a fragment entry forwards its input to
//! another function. WGSL permits `@interpolate` only on an IO binding
//! (`@location` or a compatible builtin), so naga/wgpu reject the otherwise
//! valid artifact with "input/output binding is not consistent".
//!
//! Strip only interpolation attributes on fields that have no IO binding on
//! the same generated line. Entry-point fields retain both `@interpolate` and
//! `@location`.
//!
//! Usage:
//!   wgsl-patch-direct <in.wgsl> <out.wgsl>

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("wgsl-patch-direct: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn appendPatchedLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    const attr = "@interpolate(";
    const attr_at = std.mem.indexOf(u8, line, attr);
    const has_io_binding =
        std.mem.indexOf(u8, line, "@location(") != null or
        std.mem.indexOf(u8, line, "@builtin(") != null;

    if (attr_at != null and !has_io_binding) {
        const start = attr_at.?;
        const close = std.mem.indexOfScalarPos(u8, line, start + attr.len, ')') orelse
            fail("unterminated interpolation attribute: {s}", .{line});
        try out.appendSlice(allocator, line[0..start]);
        try out.appendSlice(allocator, std.mem.trimStart(u8, line[close + 1 ..], " \t"));
    } else {
        try out.appendSlice(allocator, line);
    }
    try out.append(allocator, '\n');
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const usage = "usage: <input.wgsl> <output.wgsl>";
    const in_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});
    if (args.next() != null) fail(usage, .{});

    const src = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(src);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| try appendPatchedLine(&out, gpa, line);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
