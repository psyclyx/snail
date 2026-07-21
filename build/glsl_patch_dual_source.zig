//! Build-time GLSL text patch for the WGSL catalog's subpixel leg.
//!
//! The subpixel family reaches SPIR-V through generated GLSL text compiled by
//! glslang (see build/wgsl_shaders.zig), but slangc's GLSL backend — like its
//! GLSL front end — drops the `index = 1` dual-source qualifier, leaving two
//! `out` declarations at `layout(location = 0)`, which glslang rejects. This
//! tool restores the qualifier the original source declared: it finds the
//! `out` declaration whose name contains "frag_blend" and rewrites its
//! closest preceding `layout(location = 0)` line to
//! `layout(location = 0, index = 1)`.
//!
//! Usage: glsl-patch-dual-source <input.frag> <output.frag>

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("glsl-patch-dual-source: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const in_path = args.next() orelse fail("usage: <input.frag> <output.frag>", .{});
    const out_path = args.next() orelse fail("usage: <input.frag> <output.frag>", .{});
    if (args.next() != null) fail("usage: <input.frag> <output.frag>", .{});

    const source = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(source);

    // Locate the `out` declaration of the blend output, then the closest
    // preceding plain `layout(location = 0)` line.
    const blend_decl = std.mem.indexOf(u8, source, "out vec4 entryPointParam_main_frag_blend") orelse
        std.mem.indexOf(u8, source, "frag_blend") orelse
        fail("{s}: no frag_blend output declaration", .{in_path});
    const needle = "layout(location = 0)";
    const layout_at = std.mem.lastIndexOf(u8, source[0..blend_decl], needle) orelse
        fail("{s}: no layout(location = 0) before frag_blend", .{in_path});

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, source[0..layout_at]);
    try out.appendSlice(gpa, "layout(location = 0, index = 1)");
    try out.appendSlice(gpa, source[layout_at + needle.len ..]);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
