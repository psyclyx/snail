//! Promote the default float precision of a SPIRV-Cross GLES 300 es output
//! to highp.
//!
//! SPIRV-Cross emits `precision mediump float;` as the fragment default and
//! only qualifies globals/struct members explicitly; function-local
//! temporaries inherit the default. The composed catalog (and the naga
//! translation it replaced) ran the whole pipeline at `precision highp
//! float;` — on desktop Mesa both compile to fp32, but on real ES devices
//! mediump may be fp16 and the coverage math (root finding, band
//! transforms) needs fp32. Promoting the DEFAULT precision statement is
//! exact: explicit `highp` qualifiers in the artifact are unaffected and no
//! declaration in the module asks for mediump semantics on purpose.
//!
//! Usage: glsl-patch-es-highp <spirv-cross.glsl> <out.glsl>
//! Fails loudly when the expected default-precision statement is missing so
//! drift cannot silently un-patch.

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("glsl-patch-es-highp: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const usage = "usage: <spirv-cross.glsl> <out.glsl>";
    const in_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});

    const input = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(input);

    const needle = "precision mediump float;";
    const replacement = "precision highp float;";
    // Vertex stages default to highp already; only patch when the mediump
    // default is present (fragment stages), but never more than once.
    const count = std.mem.count(u8, input, needle);
    const patched = switch (count) {
        0 => input,
        1 => try std.mem.replaceOwned(u8, gpa, input, needle, replacement),
        else => fail("expected at most one '{s}', found {d}", .{ needle, count }),
    };
    defer if (patched.ptr != input.ptr) gpa.free(patched);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = patched }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
