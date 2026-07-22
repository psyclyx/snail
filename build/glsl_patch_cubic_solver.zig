//! Substitute the composed-catalog text of `solveMonotonicCubicRoot` into a
//! naga-generated GL fragment (stage B of the Slang cutover).
//!
//! Why: the GL gate demands bit-exact output vs the raw-GLSL composed
//! catalog. The native-Slang cubic solver is *semantically* identical (a
//! 20M-input strict-IEEE CPU sweep of both transcriptions matches bitwise),
//! but Mesa/llvmpipe compiles naga's statement-per-op emission of the
//! Newton/bisection loop differently from the composed single-expression
//! form (shape-sensitive multiply-add fusion), which shifts the root by
//! ULPs and flips scattered LSBs on cubic path edges. No source-level
//! restructuring can pin a driver's fusion heuristics, so the generated
//! artifact carries the composed function text verbatim: the mangled
//! solver's body is replaced with a forwarding call to the extracted spec
//! function.
//!
//! Usage: glsl-patch-cubic-solver <naga.glsl> <snail_path_frag_body.glsl> <out.glsl>
//! Fails loudly when either the spec function or the mangled function
//! stops matching, so artifact drift cannot silently un-patch.

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("glsl-patch-cubic-solver: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn findMatchingBrace(text: []const u8, open_idx: usize) usize {
    var depth: usize = 0;
    var i = open_idx;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    fail("unbalanced braces", .{});
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const usage = "usage: <naga.glsl> <snail_path_frag_body.glsl> <out.glsl>";
    const in_path = args.next() orelse fail(usage, .{});
    const spec_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});

    const input = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    const spec = std.Io.Dir.cwd().readFileAlloc(io, spec_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ spec_path, err });

    // ── Extract the composed solver from the spec ──
    const spec_sig = "bool solveMonotonicCubicRoot(";
    const spec_start = std.mem.indexOf(u8, spec, spec_sig) orelse fail("spec function missing", .{});
    const spec_open = std.mem.indexOfScalarPos(u8, spec, spec_start, '{') orelse fail("spec function missing brace", .{});
    const spec_close = findMatchingBrace(spec, spec_open);
    var composed = try gpa.dupe(u8, spec[spec_start .. spec_close + 1]);
    // Free-standing copy: rename + inline the file-scope epsilon constant.
    composed = try std.mem.replaceOwned(u8, gpa, composed, "solveMonotonicCubicRoot(", "snailSpecSolveMonotonicCubicRoot(");
    composed = try std.mem.replaceOwned(u8, gpa, composed, "kCoordEps", "(1.0 / 65536.0)");
    if (std.mem.indexOf(u8, composed, "kParamEps") != null) fail("spec references an unexpected constant", .{});

    // ── Locate the mangled generated solver ──
    const gen_prefix = "bool solveMonotonicCubicRoot_";
    const gen_start = std.mem.indexOf(u8, input, gen_prefix) orelse fail("generated function missing", .{});
    const paren_open = std.mem.indexOfScalarPos(u8, input, gen_start, '(') orelse fail("generated signature missing", .{});
    const paren_close = std.mem.indexOfScalarPos(u8, input, paren_open, ')') orelse fail("generated signature missing", .{});
    const gen_open = std.mem.indexOfScalarPos(u8, input, paren_close, '{') orelse fail("generated body missing", .{});
    const gen_close = findMatchingBrace(input, gen_open);

    // Parameter names: last identifier of each comma-separated declaration.
    var params: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, input[paren_open + 1 .. paren_close], ',');
    while (it.next()) |decl| {
        const trimmed = std.mem.trim(u8, decl, " \t\n");
        const space = std.mem.lastIndexOfScalar(u8, trimmed, ' ') orelse fail("bad parameter list", .{});
        try params.append(gpa, trimmed[space + 1 ..]);
    }
    if (params.items.len != 6) fail("expected 6 solver parameters, found {d}", .{params.items.len});

    var forward: std.ArrayList(u8) = .empty;
    try forward.appendSlice(gpa, "{\n    return snailSpecSolveMonotonicCubicRoot(");
    for (params.items, 0..) |p, i| {
        if (i != 0) try forward.appendSlice(gpa, ", ");
        try forward.appendSlice(gpa, p);
    }
    try forward.appendSlice(gpa, ");\n}");

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(gpa, input[0..gen_start]);
    try out.appendSlice(gpa,
        \\// Composed-catalog solver text, injected by build/glsl_patch_cubic_solver.zig
        \\// (see that file for why the naga emission cannot be used verbatim).
        \\
    );
    try out.appendSlice(gpa, composed);
    try out.appendSlice(gpa, "\n\n");
    try out.appendSlice(gpa, input[gen_start..gen_open]);
    try out.appendSlice(gpa, forward.items);
    try out.appendSlice(gpa, input[gen_close + 1 ..]);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
