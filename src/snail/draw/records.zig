//! `DrawRecords`: the output of `emit`.
//!
//! Two slices:
//! - `words` is packed GPU-ready data: one 23-word `Instance` per shape.
//! - `segments` describes how to bind state and dispatch each draw.
//!
const std = @import("std");
const page_pool_mod = @import("../atlas/page_pool.zig");
const abi_mod = @import("../format/abi.zig");
const vertex_mod = @import("../format/vertex.zig");

pub const PagePool = page_pool_mod.PagePool;

/// Semantic family of every instance in a `DrawSegment`. This describes the
/// prepared record; callers decide which shader or pipeline consumes it.
pub const ShapeKind = enum {
    regular,
    colr,
    path,
    hinted_text,
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

pub const DrawSegment = struct {
    binding: Binding,
    /// Offset (in `u32` words) into `DrawRecords.words` where this segment starts.
    words_offset: u32,
    /// Length (in `u32` words) of this segment's payload in `DrawRecords.words`.
    words_len: u32,
    /// Number of instances in this segment.
    shape_count: u32,
    /// Exact semantic family shared by every instance in this segment.
    kind: ShapeKind,
};

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const DrawSegment,
};

/// Try to merge `next` into the last segment of `segs` if the two are
/// adjacent in `words` and share a binding and semantic family. Returns true
/// if merged.
pub fn mergeIfAdjacent(segs: []DrawSegment, len: *usize, next: DrawSegment) bool {
    if (len.* == 0) return false;
    const last = &segs[len.* - 1];
    if (!last.binding.eql(next.binding)) return false;
    if (last.kind != next.kind) return false;
    if (last.words_offset + last.words_len != next.words_offset) return false;
    last.words_len += next.words_len;
    last.shape_count += next.shape_count;
    return true;
}

/// Decode the semantic family encoded in one packed instance. Emit uses this
/// once while constructing homogeneous segments; it is also useful for ABI
/// validation and diagnostics without imposing renderer dispatch policy.
pub fn shapeKind(words: []const u32, shape_index: usize) ShapeKind {
    std.debug.assert(words.len % vertex_mod.WORDS_PER_INSTANCE == 0);
    const packed_word = vertex_mod.instanceAt(words, shape_index).glyph[1];
    if (!abi_mod.glyphWordIsSpecial(packed_word)) return .regular;
    return switch (abi_mod.specialGlyphWordKind(packed_word) orelse .colr) {
        .colr => .colr,
        .path => .path,
        .hinted_text => .hinted_text,
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

test "mergeIfAdjacent merges only contiguous homogeneous segments" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool.deinit();

    const binding = Binding{ .pool = pool, .generation = 0 };
    var buf: [4]DrawSegment = undefined;
    var len: usize = 0;

    buf[len] = .{
        .binding = binding,
        .words_offset = 0,
        .words_len = 16,
        .shape_count = 1,
        .kind = .regular,
    };
    len += 1;

    const next = DrawSegment{
        .binding = binding,
        .words_offset = 16,
        .words_len = 32,
        .shape_count = 2,
        .kind = .regular,
    };
    try std.testing.expect(mergeIfAdjacent(buf[0..], &len, next));
    try std.testing.expectEqual(@as(usize, 1), len);
    try std.testing.expectEqual(@as(u32, 48), buf[0].words_len);
    try std.testing.expectEqual(@as(u32, 3), buf[0].shape_count);

    const different_kind = DrawSegment{
        .binding = binding,
        .words_offset = 48,
        .words_len = 16,
        .shape_count = 1,
        .kind = .path,
    };
    try std.testing.expect(!mergeIfAdjacent(buf[0..], &len, different_kind));
}
