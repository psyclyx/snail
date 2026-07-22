//! Pin `gl_BaseVertex` to zero in a naga-generated GL vertex stage.
//!
//! The autohint vertex's GL leg must compile -emit-spirv-via-glsl (its
//! fitter has loops — the naga-structurizer trap — and spirv_asm does not
//! compile through the via-glsl backend), so it cannot use the raw
//! VertexIndex spirv_asm workaround the other families' vertex uses.
//! slangc lowers SV_VertexID with D3D semantics (VertexIndex − BaseVertex)
//! and the naga output references `gl_BaseVertex`, which needs GL 4.6 and
//! does not exist in GLES 3.0. Every snail draw is base-vertex-0 (indexed
//! quads, firstIndex/vertexOffset 0), so the builtin read is replaced with
//! the constant 0 — the exact value the driver would supply.
//!
//! Usage: glsl-patch-base-vertex <naga.glsl> <out.glsl>
//! Fails loudly when the expected builtin read is missing so drift cannot
//! silently un-patch.

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("glsl-patch-base-vertex: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const usage = "usage: <naga.glsl> <out.glsl>";
    const in_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});

    const input = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });

    const needle = "uint(gl_BaseVertex)";
    const count = std.mem.count(u8, input, needle);
    if (count != 1) fail("expected exactly one '{s}' read, found {d}", .{ needle, count });
    const patched = try std.mem.replaceOwned(u8, gpa, input, needle, "0u");

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = patched }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
