//! Build-time SPIR-V patch: re-attach dual-source `Index` decorations.
//!
//! slangc's GLSL frontend (v2026.5.2) drops the `index = 1` layout qualifier
//! on fragment outputs (`layout(location = 0, index = 1) out vec4 frag_blend;`),
//! emitting both outputs at Location 0 with no Index decoration — which breaks
//! dual-source blending at pipeline creation. The Slang core supports the
//! decoration (native `[[vk::index(1)]]` emits it), so this tool restores
//! exactly what the GLSL source declares: for each `<needle> <index>` pair it
//! finds the output variable whose debug name contains the needle and inserts
//! `OpDecorate %var Index <index>` next to its Location decoration. Vulkan
//! only strictly needs the `Index 1` on the blend output, but naga's SPIR-V
//! front end (used to generate the WGSL catalog) requires both outputs to be
//! decorated, so the build patches `frag_color 0 frag_blend 1`. No other
//! bytes change.
//!
//! Usage: spv-patch-dual-source <input.spv> <output.spv> {<name-needle> <index>}+

const std = @import("std");

const spirv_magic: u32 = 0x0723_0203;
const op_name: u32 = 5;
const op_decorate: u32 = 71;
const decoration_location: u32 = 30;
const decoration_index: u32 = 32;

const usage = "usage: <input.spv> <output.spv> {{<name-needle> <index>}}+";

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("spv-patch-dual-source: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

const Patch = struct {
    needle: []const u8,
    index: u32,
    target_id: ?u32 = null,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const in_path = args.next() orelse fail(usage, .{});
    const out_path = args.next() orelse fail(usage, .{});
    var patches_buf: [8]Patch = undefined;
    var patch_count: usize = 0;
    while (args.next()) |needle| {
        const index_arg = args.next() orelse fail(usage, .{});
        if (patch_count == patches_buf.len) fail("too many patch pairs", .{});
        patches_buf[patch_count] = .{
            .needle = needle,
            .index = std.fmt.parseInt(u32, index_arg, 10) catch fail("bad index '{s}'", .{index_arg}),
        };
        patch_count += 1;
    }
    if (patch_count == 0) fail(usage, .{});
    const patches = patches_buf[0..patch_count];

    const bytes = std.Io.Dir.cwd().readFileAllocOptions(io, in_path, gpa, .unlimited, .of(u32), null) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(bytes);
    if (bytes.len % 4 != 0 or bytes.len < 5 * 4) fail("{s}: not a SPIR-V module", .{in_path});
    const words = std.mem.bytesAsSlice(u32, bytes);
    if (words[0] != spirv_magic) fail("{s}: bad SPIR-V magic", .{in_path});

    // Pass 1: find the id of each variable whose OpName contains its needle.
    var i: usize = 5;
    while (i < words.len) {
        const word_count = words[i] >> 16;
        const opcode = words[i] & 0xffff;
        if (word_count == 0 or i + word_count > words.len) fail("{s}: malformed instruction stream", .{in_path});
        if (opcode == op_name and word_count >= 3) {
            const raw = std.mem.sliceAsBytes(words[i + 2 .. i + word_count]);
            const name = raw[0 .. std.mem.indexOfScalar(u8, raw, 0) orelse raw.len];
            for (patches) |*patch| {
                if (std.mem.indexOf(u8, name, patch.needle) != null) {
                    if (patch.target_id != null) fail("{s}: multiple OpNames match '{s}'", .{ in_path, patch.needle });
                    patch.target_id = words[i + 1];
                }
            }
        }
        i += word_count;
    }
    for (patches) |patch| {
        if (patch.target_id == null) fail("{s}: no OpName contains '{s}'", .{ in_path, patch.needle });
    }

    // Pass 2: locate each target's Location decoration; its Index decoration
    // goes right after it (same annotation section, so section ordering holds).
    var out: std.ArrayList(u32) = .empty;
    defer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, words.len + 4 * patches.len);
    out.appendSliceAssumeCapacity(words[0..5]);
    var patched: usize = 0;
    i = 5;
    while (i < words.len) {
        const word_count = words[i] >> 16;
        const opcode = words[i] & 0xffff;
        out.appendSliceAssumeCapacity(words[i .. i + word_count]);
        if (opcode == op_decorate and word_count == 4) {
            for (patches) |patch| {
                if (words[i + 1] != patch.target_id.?) continue;
                if (words[i + 2] == decoration_index) fail("{s}: Index decoration already present", .{in_path});
                if (words[i + 2] == decoration_location) {
                    out.appendSliceAssumeCapacity(&.{ (4 << 16) | op_decorate, patch.target_id.?, decoration_index, patch.index });
                    patched += 1;
                }
            }
        }
        i += word_count;
    }
    if (patched != patches.len) fail("{s}: {d} of {d} targets had no Location decoration", .{ in_path, patches.len - patched, patches.len });

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = std.mem.sliceAsBytes(out.items) }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
