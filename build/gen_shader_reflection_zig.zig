//! Generate `reflection.zig` — the machine-derived parameter-ABI module —
//! from `slangc -reflection-json` output.
//!
//! Boundary: snail ships Slang source plus the machinery to make it work;
//! the parameter-passing ABI (block layout, binding slots) is not a
//! hand-pinned promise but a per-compile fact DERIVED from the compiler's
//! own reflection. This tool turns that fact into Zig the hosts consume
//! (the CPU-side parameter struct, the binding slot numbers), replacing
//! the hand-mirrored copies the reference renderers used to carry. The
//! DATA ABI — instance-stream semantics, atlas texel layouts, blend
//! semantics — is not reflectable and stays owned in
//! `src/snail/format/abi.zig` and the emit/record contracts.
//!
//! Inputs: every shared-parameter-block family's Vulkan-leg reflection
//! (both stages) plus one WGSL-leg reflection (for the uniform-buffer
//! group/binding). The tool asserts all families agree on the block
//! layout and on every resource's slot — a family that diverges fails
//! generation loudly.
//!
//! Usage: <out.zig> <wgsl-reflection.json> <vulkan-reflection.json>...

const std = @import("std");

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("gen-shader-reflection-zig: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn get(v: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (v) {
        .object => |o| o.get(key),
        else => null,
    };
}

fn getString(v: std.json.Value, key: []const u8) ?[]const u8 {
    return switch (get(v, key) orelse return null) {
        .string => |s| s,
        else => null,
    };
}

fn getInt(v: std.json.Value, key: []const u8) ?u64 {
    return switch (get(v, key) orelse return null) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        else => null,
    };
}

const Field = struct {
    name: []const u8,
    offset: u64,
    size: u64,
    zig_type: []const u8,
};

const Resource = struct { name: []const u8, index: u64 };

/// Map a reflected field type to the Zig type used in the extern struct.
fn zigTypeFor(arena: std.mem.Allocator, t: std.json.Value) []const u8 {
    const kind = getString(t, "kind") orelse fail("field type has no kind", .{});
    if (std.mem.eql(u8, kind, "scalar")) {
        const s = getString(t, "scalarType") orelse "";
        if (std.mem.eql(u8, s, "float32")) return "f32";
        if (std.mem.eql(u8, s, "int32")) return "i32";
        if (std.mem.eql(u8, s, "uint32")) return "u32";
        fail("unsupported scalar type '{s}'", .{s});
    }
    if (std.mem.eql(u8, kind, "vector")) {
        const n = getInt(t, "elementCount") orelse fail("vector without elementCount", .{});
        const elem = zigTypeFor(arena, get(t, "elementType") orelse fail("vector without elementType", .{}));
        return std.fmt.allocPrint(arena, "[{d}]{s}", .{ n, elem }) catch fail("oom", .{});
    }
    if (std.mem.eql(u8, kind, "matrix")) {
        const rows = getInt(t, "rowCount") orelse 0;
        const cols = getInt(t, "columnCount") orelse 0;
        const elem = zigTypeFor(arena, get(t, "elementType") orelse fail("matrix without elementType", .{}));
        return std.fmt.allocPrint(arena, "[{d}]{s}", .{ rows * cols, elem }) catch fail("oom", .{});
    }
    fail("unsupported field type kind '{s}'", .{kind});
}

fn parseParams(parsed: std.json.Value, path: []const u8) []std.json.Value {
    return switch (get(parsed, "parameters") orelse fail("{s}: no parameters", .{path})) {
        .array => |a| a.items,
        else => fail("{s}: parameters is not an array", .{path}),
    };
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const usage = "usage: <out.zig> <wgsl-reflection.json> <vulkan-reflection.json>...";
    const out_path = args.next() orelse fail(usage, .{});
    const wgsl_path = args.next() orelse fail(usage, .{});

    // ── WGSL leg: the parameter block's uniform-buffer group/binding. ──
    const wgsl_src = std.Io.Dir.cwd().readFileAlloc(io, wgsl_path, arena, .unlimited) catch |err|
        fail("reading {s}: {t}", .{ wgsl_path, err });
    const wgsl_parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, wgsl_src, .{}) catch |err|
        fail("parsing {s}: {t}", .{ wgsl_path, err });
    var wgsl_group: u64 = 0;
    var wgsl_binding: u64 = 0;
    var wgsl_pc_seen = false;
    for (parseParams(wgsl_parsed, wgsl_path)) |p| {
        const name = getString(p, "name") orelse continue;
        if (!std.mem.eql(u8, name, "pc")) continue;
        const binding = get(p, "binding") orelse fail("wgsl pc has no binding", .{});
        wgsl_group = getInt(binding, "space") orelse 0;
        wgsl_binding = getInt(binding, "index") orelse 0;
        wgsl_pc_seen = true;
    }
    if (!wgsl_pc_seen) fail("{s}: no pc parameter", .{wgsl_path});

    // ── Vulkan legs: block layout + resource slots, asserted uniform
    // across every input. ──
    var fields: std.ArrayList(Field) = .empty;
    var block_size: u64 = 0;
    var resources: std.ArrayList(Resource) = .empty;
    var first_pc_path: []const u8 = "";

    while (args.next()) |vk_path_raw| {
        const vk_path = try arena.dupe(u8, vk_path_raw);
        const src = std.Io.Dir.cwd().readFileAlloc(io, vk_path, arena, .unlimited) catch |err|
            fail("reading {s}: {t}", .{ vk_path, err });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, src, .{}) catch |err|
            fail("parsing {s}: {t}", .{ vk_path, err });

        for (parseParams(parsed, vk_path)) |p| {
            const name = getString(p, "name") orelse continue;
            if (std.mem.eql(u8, name, "pc")) {
                const binding = get(p, "binding") orelse fail("{s}: pc has no binding", .{vk_path});
                const kind = getString(binding, "kind") orelse "";
                if (!std.mem.eql(u8, kind, "pushConstantBuffer"))
                    fail("{s}: pc binding kind '{s}', expected pushConstantBuffer", .{ vk_path, kind });
                const element = get(get(p, "type") orelse fail("{s}: pc without type", .{vk_path}), "elementType") orelse
                    fail("{s}: pc without elementType", .{vk_path});
                const jfields = switch (get(element, "fields") orelse fail("{s}: pc without fields", .{vk_path})) {
                    .array => |a| a.items,
                    else => fail("{s}: pc fields not an array", .{vk_path}),
                };
                var this_size: u64 = 0;
                var this_fields: std.ArrayList(Field) = .empty;
                for (jfields) |jf| {
                    const fname = getString(jf, "name") orelse fail("{s}: unnamed pc field", .{vk_path});
                    const fbinding = get(jf, "binding") orelse fail("{s}: pc field {s} without binding", .{ vk_path, fname });
                    const offset = getInt(fbinding, "offset") orelse fail("{s}: pc field {s} without offset", .{ vk_path, fname });
                    const size = getInt(fbinding, "size") orelse fail("{s}: pc field {s} without size", .{ vk_path, fname });
                    try this_fields.append(arena, .{
                        .name = try arena.dupe(u8, fname),
                        .offset = offset,
                        .size = size,
                        .zig_type = zigTypeFor(arena, get(jf, "type") orelse fail("{s}: pc field {s} without type", .{ vk_path, fname })),
                    });
                    this_size = @max(this_size, offset + size);
                }
                if (fields.items.len == 0) {
                    fields = this_fields;
                    block_size = this_size;
                    first_pc_path = vk_path;
                } else {
                    if (this_fields.items.len != fields.items.len)
                        fail("parameter blocks disagree: {s} has {d} fields, {s} has {d}", .{ vk_path, this_fields.items.len, first_pc_path, fields.items.len });
                    for (this_fields.items, fields.items) |a, b| {
                        if (!std.mem.eql(u8, a.name, b.name) or a.offset != b.offset or a.size != b.size or !std.mem.eql(u8, a.zig_type, b.zig_type))
                            fail("parameter blocks disagree on field '{s}' ({s} vs {s})", .{ a.name, vk_path, first_pc_path });
                    }
                }
            } else if (std.mem.startsWith(u8, name, "u_")) {
                const binding = get(p, "binding") orelse fail("{s}: {s} has no binding", .{ vk_path, name });
                const kind = getString(binding, "kind") orelse "";
                if (!std.mem.eql(u8, kind, "descriptorTableSlot"))
                    fail("{s}: {s} binding kind '{s}', expected descriptorTableSlot", .{ vk_path, name, kind });
                const index = getInt(binding, "index") orelse fail("{s}: {s} has no index", .{ vk_path, name });
                const existing = for (resources.items) |r| {
                    if (std.mem.eql(u8, r.name, name)) break r;
                } else null;
                if (existing) |r| {
                    if (r.index != index)
                        fail("resource '{s}' at slot {d} in {s} but {d} elsewhere", .{ name, index, vk_path, r.index });
                } else {
                    try resources.append(arena, .{ .name = try arena.dupe(u8, name), .index = index });
                }
            }
        }
    }
    if (fields.items.len == 0) fail("no vulkan reflection input carried a pc block", .{});

    // ── Emit. ──
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena,
        \\//! GENERATED by build/gen_shader_reflection_zig.zig from `slangc
        \\//! -reflection-json` over the shared-parameter-block families — the
        \\//! machine-derived parameter ABI. Do not edit; do not hand-mirror
        \\//! these values (that is the point). The data ABI (instance-stream
        \\//! semantics, atlas texel layouts, blend semantics) is NOT here —
        \\//! see src/snail/format/abi.zig and the emit/record contracts.
        \\
        \\
    );
    try out.appendSlice(arena, "/// The per-draw parameter block, laid out exactly as every compiled\n");
    try out.appendSlice(arena, "/// target reads it (Vulkan push constants; a UBO elsewhere).\n");
    try out.appendSlice(arena, "pub const PushConstants = extern struct {\n");
    for (fields.items) |f| {
        try out.print(arena, "    {s}: {s},\n", .{ f.name, f.zig_type });
    }
    try out.appendSlice(arena, "};\n\ncomptime {\n");
    try out.print(arena, "    if (@sizeOf(PushConstants) != {d}) @compileError(\"PushConstants size drifted from reflection\");\n", .{block_size});
    for (fields.items) |f| {
        try out.print(arena, "    if (@offsetOf(PushConstants, \"{s}\") != {d}) @compileError(\"PushConstants.{s} offset drifted from reflection\");\n", .{ f.name, f.offset, f.name });
    }
    try out.appendSlice(arena, "}\n\n");
    try out.print(arena, "pub const params_size: u32 = {d};\n\n", .{block_size});
    try out.appendSlice(arena, "/// Descriptor slots (Vulkan set-0 bindings; the canonical numbers the\n");
    try out.appendSlice(arena, "/// other targets map in declaration order).\n");
    try out.appendSlice(arena, "pub const binding = struct {\n");
    for (resources.items) |r| {
        try out.print(arena, "    pub const {s}: u32 = {d};\n", .{ r.name[2..], r.index });
    }
    try out.print(arena, "    /// WGSL: the parameter block is a uniform buffer at this group/binding.\n    pub const wgsl_params_group: u32 = {d};\n    pub const wgsl_params_binding: u32 = {d};\n", .{ wgsl_group, wgsl_binding });
    try out.appendSlice(arena, "};\n");

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
