//! Post-generation WGSL dual-source entry synthesizer.
//!
//! slangc's WGSL backend drops `[[vk::index(1)]]` and renumbers the blend
//! output to `@location(1)` — plain MRT, silently wrong blend semantics —
//! and no Slang declaration syntax reaches WGSL's `@blend_src`. This tool
//! replaces the earlier in-source `__requirePrelude` interop (which had to
//! hard-code slang's internal name mangling and broke on any edit to the
//! family or its imports): it derives the dual-source entry MECHANICALLY
//! from the emitted artifact, so no mangled name is ever written by hand.
//!
//! Transform (usage: <input.wgsl> <output.wgsl>):
//!   1. Prepend `enable dual_source_blending;` (directives precede all
//!      declarations; the artifact has none of its own).
//!   2. Locate the single `@fragment fn fragmentMain` entry and its output
//!      struct (two fields at @location(0)/@location(1)).
//!   3. Clone the output struct as `SnailDualSourceOut` with the SAME
//!      field names but `@location(0) @blend_src(0)` / `@location(0)
//!      @blend_src(1)` attributes — same names means the entry body clones
//!      verbatim.
//!   4. Clone the entry as `fragmentDualMain` returning the dual struct.
//!
//! WGSL entry points cannot be called from other functions, so the body is
//! textually cloned rather than forwarded. The plain `fragmentMain` (valid
//! MRT) stays in the artifact; dual-source consumers select
//! `fragmentDualMain` (naga >= 29 validates the two-entry shape — the
//! reason wgpu-native is pinned to v29). naga validation of the PATCHED
//! artifact in gen-shaders / `zig build test` is the tripwire for this
//! transform's assumptions.

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("wgsl-gen-dual-entry: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

/// Index just past the brace that closes the block opened at `open`.
fn matchBrace(text: []const u8, open: usize) usize {
    std.debug.assert(text[open] == '{');
    var depth: usize = 0;
    var i = open;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if (depth == 0) return i + 1;
            },
            else => {},
        }
    }
    fail("unbalanced braces after offset {d}", .{open});
}

const Field = struct { name: []const u8, type_text: []const u8, location: u8 };

/// Parse one `@location(N) name : type,` struct-field line.
fn parseField(line: []const u8) ?Field {
    const loc_tag = "@location(";
    const loc_at = std.mem.indexOf(u8, line, loc_tag) orelse return null;
    const loc_digit_at = loc_at + loc_tag.len;
    if (loc_digit_at + 1 >= line.len) return null;
    const loc_digit = line[loc_digit_at];
    if (loc_digit < '0' or loc_digit > '9' or line[loc_digit_at + 1] != ')') return null;
    const rest = std.mem.trim(u8, line[loc_digit_at + 2 ..], " \t\r");
    const colon = std.mem.indexOf(u8, rest, " : ") orelse return null;
    const name = std.mem.trim(u8, rest[0..colon], " \t");
    var type_text = std.mem.trim(u8, rest[colon + 3 ..], " \t");
    if (std.mem.endsWith(u8, type_text, ",")) type_text = type_text[0 .. type_text.len - 1];
    if (name.len == 0 or type_text.len == 0) return null;
    return .{ .name = name, .type_text = type_text, .location = loc_digit - '0' };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const usage = "usage: <input.wgsl> <output.wgsl>";
    const in_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});

    const src = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(src);

    // The single-entry compile carries exactly one @fragment entry.
    const frag_attr = "@fragment";
    const frag_at = std.mem.indexOf(u8, src, frag_attr) orelse fail("no @fragment entry in {s}", .{in_path});
    if (std.mem.indexOfPos(u8, src, frag_at + frag_attr.len, frag_attr) != null)
        fail("expected exactly one @fragment entry in {s}", .{in_path});
    const fn_tag = "fn fragmentMain";
    const fn_at = std.mem.indexOfPos(u8, src, frag_at, fn_tag) orelse fail("@fragment entry is not fragmentMain in {s}", .{in_path});

    // Return type: the token between `->` and the body's opening brace.
    const arrow_at = std.mem.indexOfPos(u8, src, fn_at, "->") orelse fail("fragmentMain has no return type in {s}", .{in_path});
    const body_open = std.mem.indexOfScalarPos(u8, src, arrow_at, '{') orelse fail("fragmentMain has no body in {s}", .{in_path});
    const ret_type = std.mem.trim(u8, src[arrow_at + 2 .. body_open], " \t\r\n");
    if (ret_type.len == 0 or std.mem.indexOfAny(u8, ret_type, " \t\r\n") != null)
        fail("could not isolate fragmentMain return type in {s} (got '{s}')", .{ in_path, ret_type });
    const entry_clone = src[frag_at..matchBrace(src, body_open)];

    // The output struct: exactly two fields, at @location(0) and (1).
    var struct_tag_buf: [128]u8 = undefined;
    const struct_tag = std.fmt.bufPrint(&struct_tag_buf, "struct {s}", .{ret_type}) catch fail("return type name too long", .{});
    const struct_at = std.mem.indexOf(u8, src, struct_tag) orelse fail("output struct {s} not found in {s}", .{ ret_type, in_path });
    const struct_open = std.mem.indexOfScalarPos(u8, src, struct_at, '{') orelse fail("malformed struct {s}", .{ret_type});
    const struct_body = src[struct_open..matchBrace(src, struct_open)];

    var fields: [2]Field = undefined;
    var field_count: usize = 0;
    var lines = std.mem.splitScalar(u8, struct_body, '\n');
    while (lines.next()) |line| {
        const f = parseField(line) orelse continue;
        if (field_count >= 2) fail("output struct {s} has more than two located fields in {s}", .{ ret_type, in_path });
        fields[field_count] = f;
        field_count += 1;
    }
    if (field_count != 2 or fields[0].location != 0 or fields[1].location != 1)
        fail("output struct {s} is not the expected @location(0)/@location(1) pair in {s}", .{ ret_type, in_path });

    // Assemble: enable directive + original + dual struct + cloned entry.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, "enable dual_source_blending;\n\n");
    try out.appendSlice(gpa, src);
    var dual_buf: [512]u8 = undefined;
    const dual_struct = std.fmt.bufPrint(
        &dual_buf,
        "\nstruct SnailDualSourceOut\n{{\n" ++
            "    @location(0) @blend_src(0) {s} : {s},\n" ++
            "    @location(0) @blend_src(1) {s} : {s},\n" ++
            "}};\n\n",
        .{ fields[0].name, fields[0].type_text, fields[1].name, fields[1].type_text },
    ) catch fail("output-struct fields too long", .{});
    try out.appendSlice(gpa, dual_struct);

    // Clone with the entry name and return-struct name substituted. Same
    // output field names, so the body needs no other edits.
    const renamed_entry = try std.mem.replaceOwned(u8, gpa, entry_clone, "fragmentMain", "fragmentDualMain");
    defer gpa.free(renamed_entry);
    const retyped_entry = try std.mem.replaceOwned(u8, gpa, renamed_entry, ret_type, "SnailDualSourceOut");
    defer gpa.free(retyped_entry);
    try out.appendSlice(gpa, retyped_entry);
    try out.appendSlice(gpa, "\n");

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
