//! `DrawRecords`: the output of `emit`.
//!
//! Two slices: `words` is packed GPU vertex data (16 `u32`s per heterogeneous
//! instance, matching `render/format/vertex.zig`'s `Instance` layout); a
//! replicated segment lays out N shape blocks + M override blocks back-to-back
//! in the same buffer (the backend materializes N*M instances at dispatch).
//! `segments` describes how to bind state and dispatch each segment's draw.
//!
//! `draw()` walks `segments`, binds each segment's `Binding`, and issues the
//! appropriate draw call.

const std = @import("std");
const page_pool_mod = @import("page_pool.zig");

pub const PagePool = page_pool_mod.PagePool;

/// A small token identifying which `PagePool` an atlas was uploaded against
/// and what generation of pages was current at upload time. Built by
/// `PagePool.upload` (phase 4+); for now `generation` is just a tag carried
/// alongside the pool pointer.
pub const Binding = struct {
    pool: *PagePool,
    generation: u32 = 0,

    pub fn eql(self: Binding, other: Binding) bool {
        return self.pool == other.pool and self.generation == other.generation;
    }
};

/// The two GPU work patterns. See `docs/rewrite/03-picture-and-emit.md` for
/// the rationale behind the split.
pub const Kind = enum(u8) {
    /// One pre-composed `Instance` per shape.
    heterogeneous,
    /// N shape blocks + M override blocks, expanded to N*M instances on the GPU.
    replicated,
};

pub const DrawSegment = struct {
    kind: Kind,
    binding: Binding,
    /// Offset (in `u32` words) into `DrawRecords.words` where this segment starts.
    words_offset: u32,
    /// Length (in `u32` words) of this segment's payload in `DrawRecords.words`.
    words_len: u32,
    /// Number of shapes the segment covers. For `.heterogeneous`, equals the
    /// instance count; for `.replicated`, multiplies with `override_count`.
    shape_count: u32,
    /// Number of overrides. Always 1 for `.heterogeneous`; M for `.replicated`.
    override_count: u32,
};

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const DrawSegment,
};

/// Try to merge `next` into the last segment of `segs` if the two are
/// adjacent in `words` and share a binding and kind. Returns true if merged.
///
/// Used by `emit` to coalesce consecutive same-binding calls without the
/// caller thinking about it.
pub fn mergeIfAdjacent(segs: []DrawSegment, len: *usize, next: DrawSegment) bool {
    if (len.* == 0) return false;
    const last = &segs[len.* - 1];
    if (last.kind != next.kind) return false;
    if (!last.binding.eql(next.binding)) return false;
    if (last.words_offset + last.words_len != next.words_offset) return false;
    // Replicated segments can't be merged simply — they have an outer-product
    // shape/override count. Keep them distinct.
    if (last.kind == .replicated) return false;
    last.words_len += next.words_len;
    last.shape_count += next.shape_count;
    return true;
}

test "binding equality compares pool pointer and generation" {
    var pool_a = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool_a.deinit();

    var pool_b = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool_b.deinit();

    const b1 = Binding{ .pool = pool_a, .generation = 0 };
    const b1_dup = Binding{ .pool = pool_a, .generation = 0 };
    const b1_other_gen = Binding{ .pool = pool_a, .generation = 1 };
    const b2 = Binding{ .pool = pool_b, .generation = 0 };

    try std.testing.expect(b1.eql(b1_dup));
    try std.testing.expect(!b1.eql(b1_other_gen));
    try std.testing.expect(!b1.eql(b2));
}

test "mergeIfAdjacent merges contiguous heterogeneous segments" {
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
        .kind = .heterogeneous,
        .binding = binding,
        .words_offset = 0,
        .words_len = 16,
        .shape_count = 1,
        .override_count = 1,
    };
    len += 1;

    const next = DrawSegment{
        .kind = .heterogeneous,
        .binding = binding,
        .words_offset = 16,
        .words_len = 32,
        .shape_count = 2,
        .override_count = 1,
    };
    try std.testing.expect(mergeIfAdjacent(buf[0..], &len, next));
    try std.testing.expectEqual(@as(usize, 1), len);
    try std.testing.expectEqual(@as(u32, 48), buf[0].words_len);
    try std.testing.expectEqual(@as(u32, 3), buf[0].shape_count);
}

test "mergeIfAdjacent skips different bindings" {
    var pool_a = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool_a.deinit();
    var pool_b = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool_b.deinit();

    const ba = Binding{ .pool = pool_a };
    const bb = Binding{ .pool = pool_b };

    var buf: [4]DrawSegment = undefined;
    var len: usize = 0;
    buf[len] = .{
        .kind = .heterogeneous,
        .binding = ba,
        .words_offset = 0,
        .words_len = 16,
        .shape_count = 1,
        .override_count = 1,
    };
    len += 1;

    try std.testing.expect(!mergeIfAdjacent(buf[0..], &len, .{
        .kind = .heterogeneous,
        .binding = bb,
        .words_offset = 16,
        .words_len = 16,
        .shape_count = 1,
        .override_count = 1,
    }));
    try std.testing.expectEqual(@as(usize, 1), len);
}

test "mergeIfAdjacent leaves replicated segments distinct" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 64,
    });
    defer pool.deinit();
    const binding = Binding{ .pool = pool };

    var buf: [4]DrawSegment = undefined;
    var len: usize = 0;
    buf[len] = .{
        .kind = .replicated,
        .binding = binding,
        .words_offset = 0,
        .words_len = 32,
        .shape_count = 1,
        .override_count = 4,
    };
    len += 1;

    try std.testing.expect(!mergeIfAdjacent(buf[0..], &len, .{
        .kind = .replicated,
        .binding = binding,
        .words_offset = 32,
        .words_len = 32,
        .shape_count = 1,
        .override_count = 4,
    }));
}
