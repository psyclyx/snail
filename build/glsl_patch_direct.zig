//! Normalize Slang's direct GLSL output to the shipping GL dialects.
//!
//! Slang preserves authored functions and control flow when targeting GLSL
//! directly, but v2026.5.2 emits Vulkan-flavored surface syntax even with a
//! glsl_330 profile: `#version 450`, explicit resource bindings, and explicit
//! varying locations. The shader modules specialize GL resources to combined
//! samplers, so the remaining rewrite is mechanical:
//!  - select `#version 330 core` or `#version 300 es`;
//!  - remove Vulkan-only binding/default-layout declarations;
//!  - rename linked varyings by location (`snail_io<N>`) because GLSL < 4.10
//!    links them by name;
//!  - turn Slang's samplerless typed buffer spelling into `usamplerBuffer`;
//!  - repair Slang's signed `textureSize` result assignments.
//!
//! Usage:
//!   glsl-patch-direct <glsl330|gles300> <vert|frag> <in.glsl> <out.glsl>

const std = @import("std");

const Dialect = enum { glsl330, gles300 };
const Stage = enum { vert, frag };

const Rename = struct {
    old: []const u8,
    new: []const u8,
};

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("glsl-patch-direct: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn parseDialect(text: []const u8) ?Dialect {
    if (std.mem.eql(u8, text, "glsl330")) return .glsl330;
    if (std.mem.eql(u8, text, "gles300")) return .gles300;
    return null;
}

fn parseStage(text: []const u8) ?Stage {
    if (std.mem.eql(u8, text, "vert")) return .vert;
    if (std.mem.eql(u8, text, "frag")) return .frag;
    return null;
}

const Location = struct {
    value: u8,
    flat: bool,
};

fn parseLocation(line: []const u8) ?Location {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    const marker = "layout(location = ";
    const start = std.mem.indexOf(u8, trimmed, marker) orelse return null;
    if (start != 0 and !std.mem.eql(u8, trimmed[0..start], "flat ")) return null;
    var end = start + marker.len;
    while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
    if (end == start + marker.len) return null;
    const value = std.fmt.parseInt(u8, trimmed[start + marker.len .. end], 10) catch return null;
    return .{ .value = value, .flat = start != 0 };
}

fn declarationDirection(line: []const u8) ?enum { in, out } {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (std.mem.startsWith(u8, trimmed, "in ")) return .in;
    if (std.mem.startsWith(u8, trimmed, "out ")) return .out;
    return null;
}

fn declarationName(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.endsWith(u8, trimmed, ";")) return null;
    const before_semicolon = std.mem.trim(u8, trimmed[0 .. trimmed.len - 1], " \t");
    const split = std.mem.lastIndexOfAny(u8, before_semicolon, " \t") orelse return null;
    const with_array = before_semicolon[split + 1 ..];
    const array = std.mem.indexOfScalar(u8, with_array, '[') orelse with_array.len;
    return with_array[0..array];
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    const aggregate = " = { ";
    if (std.mem.indexOf(u8, line, aggregate)) |aggregate_start| {
        if (std.mem.endsWith(u8, line, " };")) {
            const lhs = std.mem.trim(u8, line[0..aggregate_start], " \t");
            const variable_split = std.mem.lastIndexOfAny(u8, lhs, " \t") orelse
                fail("cannot parse aggregate initializer '{s}'", .{line});
            const variable = lhs[variable_split + 1 ..];
            const before_variable = std.mem.trim(u8, lhs[0..variable_split], " \t");
            const type_split = std.mem.lastIndexOfAny(u8, before_variable, " \t");
            const ty = if (type_split) |split_index|
                before_variable[split_index + 1 ..]
            else
                before_variable;
            const array_start = std.mem.indexOfScalar(u8, variable, '[');
            try out.appendSlice(allocator, line[0..aggregate_start]);
            try out.appendSlice(allocator, " = ");
            try out.appendSlice(allocator, ty);
            if (array_start) |start| try out.appendSlice(allocator, variable[start..]);
            try out.append(allocator, '(');
            try out.appendSlice(allocator, line[aggregate_start + aggregate.len .. line.len - 3]);
            try out.appendSlice(allocator, ");\n");
            return;
        }
    }
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

fn replaceAllOwned(
    allocator: std.mem.Allocator,
    input: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    return std.mem.replaceOwned(u8, allocator, input, needle, replacement);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const usage = "usage: glsl-patch-direct <glsl330|gles300> <vert|frag> <in.glsl> <out.glsl>";
    const dialect_text = args.next() orelse fail(usage, .{});
    const stage_text = args.next() orelse fail(usage, .{});
    const input_path = args.next() orelse fail(usage, .{});
    const output_path = args.next() orelse fail(usage, .{});
    if (args.next() != null) fail(usage, .{});
    const dialect = parseDialect(dialect_text) orelse fail("unknown dialect '{s}'", .{dialect_text});
    const stage = parseStage(stage_text) orelse fail("unknown stage '{s}'", .{stage_text});

    const input = std.Io.Dir.cwd().readFileAlloc(io, input_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ input_path, err });
    defer gpa.free(input);

    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    var split = std.mem.splitScalar(u8, input, '\n');
    while (split.next()) |line| try lines.append(gpa, line);

    var renames: std.ArrayList(Rename) = .empty;
    defer {
        for (renames.items) |rename| gpa.free(rename.new);
        renames.deinit(gpa);
    }
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(gpa);

    var saw_version = false;
    var index: usize = 0;
    while (index < lines.items.len) {
        const line = lines.items[index];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "#version ")) {
            if (saw_version) fail("multiple #version directives", .{});
            saw_version = true;
            try appendLine(&normalized, gpa, switch (dialect) {
                .glsl330 => "#version 330 core",
                .gles300 => "#version 300 es",
            });
            if (dialect == .gles300) {
                try appendLine(&normalized, gpa, "precision highp float;");
                try appendLine(&normalized, gpa, "precision highp int;");
            }
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "#extension GL_EXT_samplerless_texture_functions : require") or
            std.mem.eql(u8, trimmed, "#extension GL_ARB_shader_draw_parameters : require") or
            std.mem.eql(u8, trimmed, "layout(row_major) uniform;") or
            std.mem.eql(u8, trimmed, "layout(row_major) buffer;") or
            (std.mem.startsWith(u8, trimmed, "layout(binding = ") and std.mem.endsWith(u8, trimmed, ")")))
        {
            index += 1;
            continue;
        }

        if (parseLocation(line)) |location| {
            if (index + 1 < lines.items.len) {
                const declaration = lines.items[index + 1];
                if (declarationDirection(declaration)) |direction| {
                    const linked_varying =
                        (stage == .vert and direction == .out) or
                        (stage == .frag and direction == .in);
                    if (linked_varying) {
                        const old = declarationName(declaration) orelse
                            fail("cannot parse interface declaration '{s}'", .{declaration});
                        const new = try std.fmt.allocPrint(gpa, "snail_io{d}", .{location.value});
                        try renames.append(gpa, .{ .old = old, .new = new });
                        if (location.flat) try normalized.appendSlice(gpa, "flat ");
                        try appendLine(&normalized, gpa, declaration);
                        index += 2;
                        continue;
                    }
                }
            }
        }

        try appendLine(&normalized, gpa, line);
        index += 1;
    }
    if (!saw_version) fail("missing #version directive", .{});

    var patched = try normalized.toOwnedSlice(gpa);
    defer gpa.free(patched);
    for (renames.items) |rename| {
        const replacement = try replaceAllOwned(gpa, patched, rename.old, rename.new);
        gpa.free(patched);
        patched = replacement;
    }
    const textual_rewrites = [_][2][]const u8{
        .{ "uniform utextureBuffer ", "uniform usamplerBuffer " },
        .{ "uniform textureBuffer ", "uniform samplerBuffer " },
        .{ "layout(std140) uniform ", "layout(std140, row_major) uniform " },
        .{ "gl_VertexIndex - gl_BaseVertex", "gl_VertexID" },
        .{ "uint uw_", "int uw_" },
        .{ "uint uh_", "int uh_" },
        .{ "uint ue_", "int ue_" },
    };
    for (textual_rewrites) |rewrite| {
        const replacement = try replaceAllOwned(gpa, patched, rewrite[0], rewrite[1]);
        gpa.free(patched);
        patched = replacement;
    }

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path, .data = patched }) catch |err|
        fail("writing {s}: {t}", .{ output_path, err });
}
