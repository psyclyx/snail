//! `DrawRecords`: the output of `emit`.
//!
//! Two slices:
//! - `instances` is packed GPU-ready data: one `Instance` per shape.
//! - `batches` describes how to bind state and dispatch each draw.
//!
const std = @import("std");
const page_pool_mod = @import("../atlas/page_pool.zig");
const abi_mod = @import("../format/abi.zig");
const vertex_mod = @import("../format/vertex.zig");

pub const PagePool = page_pool_mod.PagePool;
pub const Instance = vertex_mod.Instance;

/// Semantic family of every instance in a `DrawBatch`. This describes the
/// prepared record; callers decide which shader or pipeline consumes it.
pub const ShapeKind = enum {
    regular,
    colr,
    path,
    tt_hinted_text,
    autohint,
};

/// Identifies which `PagePool` an atlas was uploaded against plus the
/// cache-side slot identity (`generation`) and the offsets into the
/// cache's persistent layer-info / image-array storage. emit applies
/// `info_row_base` to paint records so the GPU sees absolute coords.
pub const Binding = struct {
    pool: *PagePool,
    generation: u32 = 0,
    /// Row offset within the cache's persistent layer-info texture.
    info_row_base: u32 = 0,
    /// Layer offset within the cache's persistent image array.
    image_layer_base: u32 = 0,

    pub fn eql(self: Binding, other: Binding) bool {
        return self.pool == other.pool and
            self.generation == other.generation and
            self.info_row_base == other.info_row_base and
            self.image_layer_base == other.image_layer_base;
    }
};

/// One instanced draw call: a contiguous run of instances sharing a binding
/// and a semantic family.
pub const DrawBatch = struct {
    binding: Binding,
    /// Index into `DrawRecords.instances` of this batch's first instance.
    first_instance: u32,
    /// Number of instances in this batch.
    instance_count: u32,
    /// Exact semantic family shared by every instance in this batch.
    kind: ShapeKind,
};

pub const DrawRecords = struct {
    instances: []const Instance,
    batches: []const DrawBatch,
};

/// Try to merge `next` into the last batch of `batches` if the two are
/// adjacent in `instances` and share a binding and semantic family. Returns
/// true if merged.
pub fn mergeIfAdjacent(batches: []DrawBatch, len: *usize, next: DrawBatch) bool {
    if (len.* == 0) return false;
    const last = &batches[len.* - 1];
    if (!last.binding.eql(next.binding)) return false;
    if (last.kind != next.kind) return false;
    if (last.first_instance + last.instance_count != next.first_instance) return false;
    last.instance_count += next.instance_count;
    return true;
}

/// Decode the semantic family encoded in one packed instance. Emit uses this
/// once while constructing homogeneous batches; it is also useful for ABI
/// validation and diagnostics without imposing renderer dispatch policy.
pub fn shapeKind(instance: *const Instance) ShapeKind {
    const packed_word = instance.glyph[1];
    if (!abi_mod.glyphWordIsSpecial(packed_word)) return .regular;
    return switch (abi_mod.specialGlyphWordKind(packed_word) orelse .colr) {
        .colr => .colr,
        .path => .path,
        .tt_hinted_text => .tt_hinted_text,
        .autohint => .autohint,
    };
}

test "binding equality compares pool, generation, and offsets" {
    var pool_a = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool_a.deinit();

    const b1 = Binding{ .pool = pool_a, .generation = 0 };
    const b1_dup = Binding{ .pool = pool_a, .generation = 0 };
    const b1_other_gen = Binding{ .pool = pool_a, .generation = 1 };
    const b1_other_row = Binding{ .pool = pool_a, .generation = 0, .info_row_base = 4 };

    try std.testing.expect(b1.eql(b1_dup));
    try std.testing.expect(!b1.eql(b1_other_gen));
    try std.testing.expect(!b1.eql(b1_other_row));
}

test "mergeIfAdjacent merges only contiguous homogeneous batches" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool.deinit();

    const binding = Binding{ .pool = pool, .generation = 0 };
    var buf: [4]DrawBatch = undefined;
    var len: usize = 0;

    buf[len] = .{
        .binding = binding,
        .first_instance = 0,
        .instance_count = 1,
        .kind = .regular,
    };
    len += 1;

    const next = DrawBatch{
        .binding = binding,
        .first_instance = 1,
        .instance_count = 2,
        .kind = .regular,
    };
    try std.testing.expect(mergeIfAdjacent(buf[0..], &len, next));
    try std.testing.expectEqual(@as(usize, 1), len);
    try std.testing.expectEqual(@as(u32, 3), buf[0].instance_count);

    const different_kind = DrawBatch{
        .binding = binding,
        .first_instance = 3,
        .instance_count = 1,
        .kind = .path,
    };
    try std.testing.expect(!mergeIfAdjacent(buf[0..], &len, different_kind));
}
