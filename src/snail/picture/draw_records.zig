//! `DrawRecords`: the output of `emit`.
//!
//! Two slices:
//! - `words` is packed GPU vertex data. Heterogeneous segments lay
//!   out one 16-word `Instance` per instance. Replicated segments
//!   lay out N shape blocks (16 words each) followed by M override
//!   blocks (8 words each); the backend issues a single instanced
//!   draw of `N*M` quads and the vertex shader composes
//!   `override[gl_InstanceID % M]` onto `shape[gl_InstanceID / M]`.
//! - `segments` describes how to bind state and dispatch each draw.
//!
//! Replicated saves bandwidth when one picture is drawn at many
//! transforms — only N+M payload instead of N*M. The CPU rasterizer
//! expands at draw time (no hardware instancing); GPU backends use a
//! real instanced draw call.

const std = @import("std");
const page_pool_mod = @import("../atlas/page_pool.zig");

pub const PagePool = page_pool_mod.PagePool;

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

pub const Kind = enum(u8) {
    /// One pre-composed `Instance` per shape. Total instance count =
    /// `shape_count`.
    heterogeneous,
    /// N shape blocks + M override blocks, drawn as `N*M` instanced
    /// quads with the vertex shader composing per pair.
    replicated,
};

pub const DrawSegment = struct {
    kind: Kind,
    binding: Binding,
    /// Offset (in `u32` words) into `DrawRecords.words` where this segment starts.
    words_offset: u32,
    /// Length (in `u32` words) of this segment's payload in `DrawRecords.words`.
    words_len: u32,
    /// Number of distinct shapes. For `.heterogeneous`, equals the
    /// instance count. For `.replicated`, multiplies with override_count.
    shape_count: u32,
    /// Number of overrides. Always 1 for `.heterogeneous`; M for
    /// `.replicated`. Total instance count = `shape_count * override_count`.
    override_count: u32,
};

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const DrawSegment,
};

/// Try to merge `next` into the last segment of `segs` if the two are
/// adjacent in `words` and share kind + binding. Returns true if merged.
pub fn mergeIfAdjacent(segs: []DrawSegment, len: *usize, next: DrawSegment) bool {
    if (len.* == 0) return false;
    const last = &segs[len.* - 1];
    if (last.kind != next.kind) return false;
    if (!last.binding.eql(next.binding)) return false;
    if (last.words_offset + last.words_len != next.words_offset) return false;
    // Replicated segments can't merge — their (N, M) structure is
    // semantically distinct from a longer (N+N', M) segment.
    if (last.kind == .replicated) return false;
    last.words_len += next.words_len;
    last.shape_count += next.shape_count;
    return true;
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

test "mergeIfAdjacent skips replicated segments" {
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
