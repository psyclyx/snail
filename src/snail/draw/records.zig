//! `DrawRecords`: the output of `emit`.
//!
//! Two slices:
//! - `instances` is packed GPU-ready data: one `Instance` per non-empty shape
//!   record emitted by `emit`.
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
/// exact planner/device cache that owns the slot (`source_id`), its slot
/// identity (`generation`), and the offsets into the
/// cache's persistent layer-info / image-array storage. emit applies
/// `info_row_base` to paint records so the GPU sees absolute coords.
pub const Binding = struct {
    pool: *PagePool,
    /// Unique nonzero identity of the planner/device cache that issued this
    /// binding. Zero is reserved for caller-authored, untracked bindings used
    /// by custom renderers; device caches reject it.
    source_id: u64 = 0,
    generation: u64 = 0,
    /// Row offset within the cache's persistent layer-info texture.
    info_row_base: u32 = 0,
    /// Layer offset within the cache's persistent image array.
    image_layer_base: u32 = 0,

    pub fn eql(self: Binding, other: Binding) bool {
        return self.pool == other.pool and
            self.source_id == other.source_id and
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

    pub const ValidationError = error{
        EmptyBatch,
        BatchRangeOverflow,
        BatchOutOfBounds,
        NonContiguousBatch,
        UncoveredInstances,
        InvalidInstance,
        BatchKindMismatch,
    };

    /// Validate the complete renderer-facing record stream. Batches must form
    /// one contiguous, non-overlapping partition of `instances`, and every
    /// instance must decode to the batch's declared semantic family.
    pub fn validate(self: DrawRecords) ValidationError!void {
        var cursor: usize = 0;
        for (self.batches) |batch| {
            if (batch.instance_count == 0) return error.EmptyBatch;
            if (@as(usize, batch.first_instance) != cursor) return error.NonContiguousBatch;
            const end = std.math.add(
                usize,
                @as(usize, batch.first_instance),
                @as(usize, batch.instance_count),
            ) catch return error.BatchRangeOverflow;
            if (end > self.instances.len) return error.BatchOutOfBounds;
            for (self.instances[cursor..end]) |*instance| {
                vertex_mod.validateInstance(instance) catch return error.InvalidInstance;
                const kind = shapeKind(instance) orelse return error.InvalidInstance;
                if (kind != batch.kind) return error.BatchKindMismatch;
            }
            cursor = end;
        }
        if (cursor != self.instances.len) return error.UncoveredInstances;
    }
};

/// Try to merge `next` into the last batch of `batches` if the two are
/// adjacent in `instances` and share a binding and semantic family. Returns
/// true if merged.
pub fn mergeIfAdjacent(batches: []DrawBatch, len: *usize, next: DrawBatch) bool {
    if (len.* == 0) return false;
    const last = &batches[len.* - 1];
    if (!last.binding.eql(next.binding)) return false;
    if (last.kind != next.kind) return false;
    const last_end = std.math.add(u32, last.first_instance, last.instance_count) catch return false;
    if (last_end != next.first_instance) return false;
    last.instance_count = std.math.add(u32, last.instance_count, next.instance_count) catch return false;
    return true;
}

/// Decode the semantic family encoded in one packed instance. Emit uses this
/// once while constructing homogeneous batches; it is also useful for ABI
/// validation and diagnostics without imposing renderer dispatch policy.
pub fn shapeKind(instance: *const Instance) ?ShapeKind {
    const packed_word = instance.glyph[1];
    if (!abi_mod.glyphWordIsSpecial(packed_word)) return .regular;
    return switch (abi_mod.specialGlyphWordKind(packed_word) orelse return null) {
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
    const b1_other_source = Binding{ .pool = pool_a, .source_id = 1 };
    const b1_other_row = Binding{ .pool = pool_a, .generation = 0, .info_row_base = 4 };

    try std.testing.expect(b1.eql(b1_dup));
    try std.testing.expect(!b1.eql(b1_other_gen));
    try std.testing.expect(!b1.eql(b1_other_source));
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

test "DrawRecords validation rejects malformed ranges and kind mismatches" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool.deinit();

    var instances = [_]Instance{std.mem.zeroes(Instance)};
    instances[0].xform = .{ 1, 0, 0, 1 };
    const binding = Binding{ .pool = pool };
    const regular = [_]DrawBatch{.{
        .binding = binding,
        .first_instance = 0,
        .instance_count = 1,
        .kind = .regular,
    }};
    try (DrawRecords{ .instances = &instances, .batches = &regular }).validate();

    const empty = [_]DrawBatch{.{
        .binding = binding,
        .first_instance = 0,
        .instance_count = 0,
        .kind = .regular,
    }};
    try std.testing.expectError(error.EmptyBatch, (DrawRecords{ .instances = &.{}, .batches = &empty }).validate());

    const wrong_kind = [_]DrawBatch{.{
        .binding = binding,
        .first_instance = 0,
        .instance_count = 1,
        .kind = .path,
    }};
    try std.testing.expectError(error.BatchKindMismatch, (DrawRecords{ .instances = &instances, .batches = &wrong_kind }).validate());

    // Marker plus a reserved bit: special, but not a decodable semantic kind.
    instances[0].glyph[1] = @as(u32, 1) << 31 | @as(u32, 1) << 26;
    try std.testing.expectEqual(@as(?ShapeKind, null), shapeKind(&instances[0]));
    try std.testing.expectError(error.InvalidInstance, (DrawRecords{ .instances = &instances, .batches = &regular }).validate());
}
