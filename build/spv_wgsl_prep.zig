//! Build-time SPIR-V rewrite that prepares a Vulkan module for WGSL
//! generation through naga (see build/wgsl_shaders.zig for the pipeline).
//!
//! Two mechanical transforms, both required because WebGPU's binding model
//! differs from Vulkan's:
//!
//! 1. Samplers move to descriptor set 1 (same binding number). WGSL has no
//!    combined image samplers, so `spirv-opt --split-combined-image-sampler`
//!    runs first and leaves each split sampler at its image's set/binding —
//!    an invalid duplicate under WebGPU's `@group`/`@binding` model. After
//!    this pass: textures stay `@group(0) @binding(N)` (N = the Vulkan
//!    binding), samplers land at `@group(1) @binding(N)`.
//! 2. The push-constant block becomes a uniform buffer at set 2, binding 0
//!    (`@group(2) @binding(0) var<uniform>`), because WebGPU has no push
//!    constants. The block already carries std140 offsets, so only the
//!    storage class (every PushConstant `OpTypePointer`/`OpVariable`) and the
//!    added DescriptorSet/Binding decorations change.
//! 3. `OpCompositeExtract <query> 2` on a 3-component `OpImageQuerySizeLod`
//!    result is rewritten to extract component 1. naga's SPIR-V front end
//!    types arrayed size queries as the 2-component extent (dimensions
//!    without the layer count), so the layer-component extract fails type
//!    resolution. Snail's shaders never consume the layer count — GLSL
//!    `textureSize(...).xy` still materializes the full ivec3 — so the
//!    rewritten lane is dead by construction.
//!
//! Usage: spv-wgsl-prep <input.spv> <output.spv>

const std = @import("std");

const spirv_magic: u32 = 0x0723_0203;

const op_decorate: u32 = 71;
const op_member_decorate: u32 = 72;
const op_type_sampler: u32 = 26;
const op_type_pointer: u32 = 32;
const op_variable: u32 = 59;
const op_composite_extract: u32 = 81;
const op_image_query_size_lod: u32 = 103;
const op_type_vector: u32 = 23;

const decoration_binding: u32 = 33;
const decoration_descriptor_set: u32 = 34;

const storage_class_uniform: u32 = 2;
const storage_class_push_constant: u32 = 9;

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("spv-wgsl-prep: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // program name
    const in_path = args.next() orelse fail("usage: <input.spv> <output.spv>", .{});
    const out_path = args.next() orelse fail("usage: <input.spv> <output.spv>", .{});
    if (args.next() != null) fail("usage: <input.spv> <output.spv>", .{});

    const bytes = std.Io.Dir.cwd().readFileAllocOptions(io, in_path, gpa, .unlimited, .of(u32), null) catch |err|
        fail("reading {s}: {t}", .{ in_path, err });
    defer gpa.free(bytes);
    if (bytes.len % 4 != 0 or bytes.len < 5 * 4) fail("{s}: not a SPIR-V module", .{in_path});
    const words: []u32 = @alignCast(std.mem.bytesAsSlice(u32, bytes));
    if (words[0] != spirv_magic) fail("{s}: bad SPIR-V magic", .{in_path});

    // Pass 1: type/variable discovery.
    var sampler_types = std.AutoHashMapUnmanaged(u32, void){};
    defer sampler_types.deinit(gpa);
    var sampler_pointer_types = std.AutoHashMapUnmanaged(u32, void){};
    defer sampler_pointer_types.deinit(gpa);
    var sampler_vars = std.AutoHashMapUnmanaged(u32, void){};
    defer sampler_vars.deinit(gpa);
    var push_constant_vars: std.ArrayList(u32) = .empty;
    defer push_constant_vars.deinit(gpa);
    var vec3_types = std.AutoHashMapUnmanaged(u32, void){};
    defer vec3_types.deinit(gpa);
    var vec3_size_queries = std.AutoHashMapUnmanaged(u32, void){};
    defer vec3_size_queries.deinit(gpa);

    var i: usize = 5;
    while (i < words.len) {
        const word_count = words[i] >> 16;
        const opcode = words[i] & 0xffff;
        if (word_count == 0 or i + word_count > words.len) fail("{s}: malformed instruction stream", .{in_path});
        switch (opcode) {
            op_type_sampler => try sampler_types.put(gpa, words[i + 1], {}),
            op_type_vector => if (word_count == 4 and words[i + 3] == 3)
                try vec3_types.put(gpa, words[i + 1], {}),
            op_type_pointer => if (word_count == 4 and sampler_types.contains(words[i + 3]))
                try sampler_pointer_types.put(gpa, words[i + 1], {}),
            op_variable => if (word_count >= 4) {
                if (sampler_pointer_types.contains(words[i + 1])) try sampler_vars.put(gpa, words[i + 2], {});
                if (words[i + 3] == storage_class_push_constant) try push_constant_vars.append(gpa, words[i + 2]);
            },
            op_image_query_size_lod => if (vec3_types.contains(words[i + 1])) {
                try vec3_size_queries.put(gpa, words[i + 2], {});
            },
            else => {},
        }
        i += word_count;
    }
    if (push_constant_vars.items.len > 1) fail("{s}: multiple push-constant blocks", .{in_path});

    // Pass 2: rewrite in place (storage classes, sampler descriptor sets) and
    // find where the annotation section ends so the new uniform decorations can
    // be inserted there.
    var annotation_end: ?usize = null;
    i = 5;
    while (i < words.len) {
        const word_count = words[i] >> 16;
        const opcode = words[i] & 0xffff;
        switch (opcode) {
            op_decorate => {
                if (word_count == 4 and words[i + 2] == decoration_descriptor_set and sampler_vars.contains(words[i + 1]))
                    words[i + 3] = 1;
                annotation_end = i + word_count;
            },
            op_member_decorate => annotation_end = i + word_count,
            op_type_pointer => if (words[i + 2] == storage_class_push_constant) {
                words[i + 2] = storage_class_uniform;
            },
            op_variable => if (word_count >= 4 and words[i + 3] == storage_class_push_constant) {
                words[i + 3] = storage_class_uniform;
            },
            op_composite_extract => if (word_count == 5 and vec3_size_queries.contains(words[i + 3]) and words[i + 4] == 2) {
                words[i + 4] = 1;
            },
            else => {},
        }
        i += word_count;
    }

    var out: std.ArrayList(u32) = .empty;
    defer out.deinit(gpa);
    if (push_constant_vars.items.len == 1) {
        const pos = annotation_end orelse fail("{s}: no annotation section", .{in_path});
        const pc = push_constant_vars.items[0];
        try out.ensureTotalCapacity(gpa, words.len + 8);
        out.appendSliceAssumeCapacity(words[0..pos]);
        out.appendSliceAssumeCapacity(&.{ (4 << 16) | op_decorate, pc, decoration_descriptor_set, 2 });
        out.appendSliceAssumeCapacity(&.{ (4 << 16) | op_decorate, pc, decoration_binding, 0 });
        out.appendSliceAssumeCapacity(words[pos..]);
    } else {
        try out.appendSlice(gpa, words);
    }

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = std.mem.sliceAsBytes(out.items) }) catch |err|
        fail("writing {s}: {t}", .{ out_path, err });
}
