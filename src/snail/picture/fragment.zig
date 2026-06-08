//! `PictureFragment` + `PictureMosaic`: pre-emitted, shareable chunks
//! of GPU draw bytes.
//!
//! `emit(picture)` resolves every shape against the atlas every frame.
//! For a 1000-shape banner where one row of text changes, that's 999
//! redundant lookups + 999 redundant transform composes + 999 redundant
//! vertex encodes per frame. A `PictureFragment` is the output of one
//! `emit` call frozen as an immutable value: words + segments, owned
//! and refcounted so multiple mosaics can hold the same fragment
//! without copying its bytes.
//!
//! A `PictureMosaic` is an ordered list of fragments. The mosaic itself
//! is value-typed (caller owns the slice of fragment pointers);
//! producing a new mosaic that replaces one fragment is O(fragment
//! count), not O(total shape count). `emitMosaic` walks the fragments
//! and splices them into a final `DrawRecords` buffer, patching
//! per-fragment word offsets to absolute positions.
//!
//! Constraints carried by a fragment:
//!   - The (binding, atlas, world_xform, world_tint) the fragment was
//!     built against are baked into its bytes. If any of those four
//!     change for some part of the scene, that fragment must be
//!     re-emitted; the rest of the mosaic stays put.
//!   - Fragments are heterogeneous-emit only. Replicated emit's N+M
//!     structure has its own one-segment-only constraint already; a
//!     replicated fragment would just be that one segment and offer no
//!     additional sharing benefit beyond what callers already get from
//!     calling `emitInstanced` directly.

const std = @import("std");
const Allocator = std.mem.Allocator;

const emit_mod = @import("emit.zig");
const draw_records = @import("draw_records.zig");
const picture_mod = @import("../picture.zig");
const atlas_mod = @import("../atlas.zig");
const math = @import("../math/vec.zig");

const Atlas = atlas_mod.Atlas;
const Binding = draw_records.Binding;
const DrawSegment = draw_records.DrawSegment;
const EmitError = emit_mod.EmitError;
const EmitResult = emit_mod.EmitResult;
const Picture = picture_mod.Picture;
const Transform2D = math.Transform2D;

pub const PictureFragment = struct {
    refcount: u32,
    allocator: Allocator,
    /// Cached `emit` output. Segment `words_offset` values are
    /// fragment-relative (0-indexed within `words`); `emitMosaic`
    /// patches them to absolute positions when splicing.
    words: []const u32,
    segments: []const DrawSegment,
    shape_count: u32,

    /// Build a fragment by emitting `picture` against `atlas`. Bytes
    /// are owned by the fragment; the picture and atlas can be
    /// modified or freed afterward without affecting the fragment.
    pub fn build(
        allocator: Allocator,
        binding: Binding,
        atlas: *const Atlas,
        picture: *const Picture,
        world_xform: Transform2D,
        world_tint: [4]f32,
    ) (EmitError || Allocator.Error)!*PictureFragment {
        const word_cap = emit_mod.wordBudget(picture, 0);
        const words = try allocator.alloc(u32, word_cap);
        errdefer allocator.free(words);

        const segs = try allocator.alloc(DrawSegment, emit_mod.segmentBudget(picture, 0));
        errdefer allocator.free(segs);

        var word_len: usize = 0;
        var seg_len: usize = 0;
        const result = try emit_mod.emit(
            words,
            segs,
            &word_len,
            &seg_len,
            binding,
            atlas,
            picture,
            world_xform,
            world_tint,
        );

        // Shrink to the actually-used portions.
        const final_words = try allocator.realloc(words, word_len);
        const final_segs = try allocator.realloc(segs, seg_len);

        const node = try allocator.create(PictureFragment);
        node.* = .{
            .refcount = 1,
            .allocator = allocator,
            .words = final_words,
            .segments = final_segs,
            .shape_count = result.shape_count,
        };
        return node;
    }

    /// Build an empty fragment. Useful as a placeholder for mosaic
    /// slots that the caller hasn't filled in yet.
    pub fn empty(allocator: Allocator) Allocator.Error!*PictureFragment {
        const node = try allocator.create(PictureFragment);
        node.* = .{
            .refcount = 1,
            .allocator = allocator,
            .words = &.{},
            .segments = &.{},
            .shape_count = 0,
        };
        return node;
    }

    /// Bump refcount; return self for fluent use.
    pub fn retain(self: *PictureFragment) *PictureFragment {
        self.refcount += 1;
        return self;
    }

    /// Drop one reference. When the last reference goes, the words
    /// and segments are freed.
    pub fn release(self: *PictureFragment) void {
        self.refcount -= 1;
        if (self.refcount == 0) {
            if (self.words.len > 0) self.allocator.free(@constCast(self.words));
            if (self.segments.len > 0) self.allocator.free(@constCast(self.segments));
            self.allocator.destroy(self);
        }
    }

    /// Total instance count baked into this fragment.
    pub fn instanceCount(self: *const PictureFragment) u32 {
        var n: u32 = 0;
        for (self.segments) |s| n += s.shape_count * s.override_count;
        return n;
    }
};

pub const PictureMosaic = struct {
    allocator: Allocator,
    fragments: []*PictureFragment,

    /// Empty mosaic. No fragments, no shapes.
    pub fn empty(allocator: Allocator) PictureMosaic {
        return .{ .allocator = allocator, .fragments = &.{} };
    }

    /// Build a mosaic that holds a reference to each fragment in
    /// `fragments` (in order). Bumps each fragment's refcount.
    pub fn from(allocator: Allocator, fragments: []const *PictureFragment) Allocator.Error!PictureMosaic {
        const buf = try allocator.alloc(*PictureFragment, fragments.len);
        for (fragments, 0..) |f, i| buf[i] = f.retain();
        return .{ .allocator = allocator, .fragments = buf };
    }

    /// Drop this mosaic's references to its fragments. Fragments whose
    /// refcount hits zero are freed; otherwise they live on through
    /// other mosaics holding them.
    pub fn deinit(self: *PictureMosaic) void {
        for (self.fragments) |f| f.release();
        if (self.fragments.len > 0) self.allocator.free(self.fragments);
        self.* = undefined;
    }

    /// Number of fragments in this mosaic.
    pub fn count(self: *const PictureMosaic) usize {
        return self.fragments.len;
    }

    /// Sum of shape counts across every fragment.
    pub fn shapeCount(self: *const PictureMosaic) u32 {
        var n: u32 = 0;
        for (self.fragments) |f| n += f.shape_count;
        return n;
    }

    /// Return a new mosaic whose fragment at `index` is replaced by
    /// `frag`. The new mosaic retains `frag` and every other fragment
    /// of `self` (refcounts bumped); the replaced fragment is *not*
    /// retained (the old mosaic still holds it). The original mosaic
    /// is unchanged.
    pub fn replace(
        self: *const PictureMosaic,
        allocator: Allocator,
        index: usize,
        frag: *PictureFragment,
    ) Allocator.Error!PictureMosaic {
        std.debug.assert(index < self.fragments.len);
        const buf = try allocator.alloc(*PictureFragment, self.fragments.len);
        for (self.fragments, 0..) |f, i| {
            buf[i] = if (i == index) frag.retain() else f.retain();
        }
        return .{ .allocator = allocator, .fragments = buf };
    }

    /// Return a new mosaic with `frag` inserted at `index` (shifts
    /// everything from `index` onward one slot right). `index` may
    /// equal `self.fragments.len` to append.
    pub fn insert(
        self: *const PictureMosaic,
        allocator: Allocator,
        index: usize,
        frag: *PictureFragment,
    ) Allocator.Error!PictureMosaic {
        std.debug.assert(index <= self.fragments.len);
        const buf = try allocator.alloc(*PictureFragment, self.fragments.len + 1);
        for (self.fragments[0..index], 0..) |f, i| buf[i] = f.retain();
        buf[index] = frag.retain();
        for (self.fragments[index..], 0..) |f, i| buf[index + 1 + i] = f.retain();
        return .{ .allocator = allocator, .fragments = buf };
    }

    /// Return a new mosaic with the fragment at `index` removed.
    pub fn remove(
        self: *const PictureMosaic,
        allocator: Allocator,
        index: usize,
    ) Allocator.Error!PictureMosaic {
        std.debug.assert(index < self.fragments.len);
        if (self.fragments.len == 1) return PictureMosaic.empty(allocator);
        const buf = try allocator.alloc(*PictureFragment, self.fragments.len - 1);
        for (self.fragments[0..index], 0..) |f, i| buf[i] = f.retain();
        for (self.fragments[index + 1 ..], 0..) |f, i| buf[index + i] = f.retain();
        return .{ .allocator = allocator, .fragments = buf };
    }

    /// Return a new mosaic equal to `self` followed by `more`'s
    /// fragments. Both inputs' fragments are retained.
    pub fn concat(
        self: *const PictureMosaic,
        allocator: Allocator,
        more: *const PictureMosaic,
    ) Allocator.Error!PictureMosaic {
        const total = self.fragments.len + more.fragments.len;
        const buf = try allocator.alloc(*PictureFragment, total);
        for (self.fragments, 0..) |f, i| buf[i] = f.retain();
        for (more.fragments, 0..) |f, i| buf[self.fragments.len + i] = f.retain();
        return .{ .allocator = allocator, .fragments = buf };
    }
};

/// Splice every fragment of `mosaic` into `words_buf` / `segs_buf`,
/// patching segment `words_offset` values from fragment-relative to
/// absolute. Consecutive fragments whose tail segment is compatible
/// with the next fragment's head segment merge via the same
/// `mergeIfAdjacent` rule as `emit`.
pub fn emitMosaic(
    words_buf: []u32,
    segs_buf: []DrawSegment,
    word_len: *usize,
    seg_len: *usize,
    mosaic: *const PictureMosaic,
) EmitError!EmitResult {
    var total_shapes: u32 = 0;
    var total_words: u32 = 0;
    var added_segs: u32 = 0;
    const start_word_len = word_len.*;

    for (mosaic.fragments) |frag| {
        if (frag.words.len == 0) continue;
        if (words_buf.len - word_len.* < frag.words.len) return error.BufferTooSmall;

        const frag_word_base: u32 = @intCast(word_len.*);
        @memcpy(words_buf[word_len.*..][0..frag.words.len], frag.words);
        word_len.* += frag.words.len;
        total_shapes += frag.shape_count;

        for (frag.segments) |seg| {
            var patched = seg;
            patched.words_offset += frag_word_base;
            if (draw_records.mergeIfAdjacent(segs_buf, seg_len, patched)) continue;
            if (seg_len.* >= segs_buf.len) return error.BufferTooSmall;
            segs_buf[seg_len.*] = patched;
            seg_len.* += 1;
            added_segs += 1;
        }
    }

    total_words = @intCast(word_len.* - start_word_len);
    return .{
        .shape_count = total_shapes,
        .word_count = total_words,
        .segment_count = added_segs,
    };
}

/// Conservative upper bound on words written by `emitMosaic(mosaic)`.
pub fn mosaicWordBudget(mosaic: *const PictureMosaic) usize {
    var n: usize = 0;
    for (mosaic.fragments) |f| n += f.words.len;
    return n;
}

/// Conservative upper bound on segments written by
/// `emitMosaic(mosaic)`. Merging may yield fewer.
pub fn mosaicSegmentBudget(mosaic: *const PictureMosaic) usize {
    var n: usize = 0;
    for (mosaic.fragments) |f| n += f.segments.len;
    return n;
}

// ── Tests ──

const testing = std.testing;
const record_key_mod = @import("../atlas/record_key.zig");
const curves_mod = @import("../atlas/curves.zig");
const page_pool_mod = @import("../atlas/page_pool.zig");
const curve_tex_format = @import("../render/format/curve_texture.zig");
const shape_mod = @import("shape.zig");
const vertex = @import("../render/format/vertex.zig");

const PagePool = page_pool_mod.PagePool;
const GlyphCurves = curves_mod.GlyphCurves;
const Shape = shape_mod.Shape;

fn makeTinyCurves(allocator: Allocator) !GlyphCurves {
    const curve_words = curve_tex_format.SEGMENT_TEXELS * 4;
    const curve_bytes = try allocator.alloc(u16, curve_words);
    for (curve_bytes, 0..) |*w, i| w.* = @intCast(@as(u16, @intCast(i)) +% 0x100);

    const band_bytes = try allocator.alloc(u16, 8);
    band_bytes[0] = 1;
    band_bytes[1] = 2;
    band_bytes[2] = 1;
    band_bytes[3] = 3;
    band_bytes[4] = 0;
    band_bytes[5] = 0;
    band_bytes[6] = 0;
    band_bytes[7] = 0;

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = 1,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
        .bbox = .{ .min = .zero, .max = .{ .x = 1, .y = 1 } },
    };
}

fn buildTestAtlas(pool: *PagePool, keys: []const u16) !Atlas {
    var owned: std.ArrayList(GlyphCurves) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(testing.allocator);
    }
    var entries: std.ArrayList(atlas_mod.Entry) = .empty;
    defer entries.deinit(testing.allocator);
    for (keys) |k| {
        const c = try makeTinyCurves(testing.allocator);
        try owned.append(testing.allocator, c);
        try entries.append(testing.allocator, .{
            .key = record_key_mod.unhintedGlyph(0, k),
            .curves = owned.items[owned.items.len - 1],
        });
    }
    return Atlas.from(testing.allocator, pool, entries.items);
}

test "PictureFragment.build caches one emit" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2 });
    defer atlas.deinit();

    const shapes = [_]Shape{
        .{ .key = record_key_mod.unhintedGlyph(0, 1), .local_transform = .translate(10, 0) },
        .{ .key = record_key_mod.unhintedGlyph(0, 2), .local_transform = .translate(20, 0) },
    };
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    const binding = Binding{ .pool = pool };
    const frag = try PictureFragment.build(testing.allocator, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });
    defer frag.release();

    try testing.expectEqual(@as(u32, 2), frag.shape_count);
    try testing.expectEqual(@as(usize, 1), frag.segments.len);
    try testing.expectEqual(@as(u32, 2), frag.segments[0].shape_count);
    try testing.expectEqual(@as(u32, 0), frag.segments[0].words_offset); // fragment-relative
}

test "Mosaic.replace shares unchanged fragments" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2, 3 });
    defer atlas.deinit();
    const binding = Binding{ .pool = pool };

    var pa = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 1) }});
    defer pa.deinit();
    var pb = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 2) }});
    defer pb.deinit();
    var pc = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 3) }});
    defer pc.deinit();

    const fa = try PictureFragment.build(testing.allocator, binding, &atlas, &pa, .identity, .{ 1, 1, 1, 1 });
    defer fa.release();
    const fb = try PictureFragment.build(testing.allocator, binding, &atlas, &pb, .identity, .{ 1, 1, 1, 1 });
    defer fb.release();
    const fc = try PictureFragment.build(testing.allocator, binding, &atlas, &pc, .identity, .{ 1, 1, 1, 1 });
    defer fc.release();

    var m1 = try PictureMosaic.from(testing.allocator, &.{ fa, fb });
    defer m1.deinit();

    // Replace fb with fc. m1 still has (fa, fb); m2 has (fa, fc).
    var m2 = try m1.replace(testing.allocator, 1, fc);
    defer m2.deinit();

    try testing.expectEqual(@as(usize, 2), m1.fragments.len);
    try testing.expectEqual(@as(usize, 2), m2.fragments.len);
    try testing.expectEqual(fa, m1.fragments[0]);
    try testing.expectEqual(fa, m2.fragments[0]); // shared
    try testing.expectEqual(fb, m1.fragments[1]);
    try testing.expectEqual(fc, m2.fragments[1]);
}

test "emitMosaic splices fragments with absolute word offsets" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2 });
    defer atlas.deinit();
    const binding = Binding{ .pool = pool };

    var pa = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 1) }});
    defer pa.deinit();
    var pb = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 2) }});
    defer pb.deinit();

    const fa = try PictureFragment.build(testing.allocator, binding, &atlas, &pa, .identity, .{ 1, 1, 1, 1 });
    defer fa.release();
    const fb = try PictureFragment.build(testing.allocator, binding, &atlas, &pb, .identity, .{ 1, 1, 1, 1 });
    defer fb.release();

    var mosaic = try PictureMosaic.from(testing.allocator, &.{ fa, fb });
    defer mosaic.deinit();

    const cap = mosaicWordBudget(&mosaic);
    const seg_cap = mosaicSegmentBudget(&mosaic);
    const words = try testing.allocator.alloc(u32, cap);
    defer testing.allocator.free(words);
    const segs = try testing.allocator.alloc(DrawSegment, seg_cap);
    defer testing.allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    const result = try emitMosaic(words, segs, &wlen, &slen, &mosaic);

    try testing.expectEqual(@as(u32, 2), result.shape_count);
    // Same binding → fragments merge into one segment.
    try testing.expectEqual(@as(usize, 1), slen);
    try testing.expectEqual(@as(u32, 2), segs[0].shape_count);
    try testing.expectEqual(@as(u32, 0), segs[0].words_offset);

    // The first WORDS_PER_INSTANCE words match fa.words; the next match fb.words.
    try testing.expectEqualSlices(u32, fa.words, words[0..fa.words.len]);
    try testing.expectEqualSlices(u32, fb.words, words[fa.words.len..][0..fb.words.len]);
}

test "emitMosaic matches a single big emit byte-for-byte" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2, 3, 4 });
    defer atlas.deinit();
    const binding = Binding{ .pool = pool };

    const all_shapes = [_]Shape{
        .{ .key = record_key_mod.unhintedGlyph(0, 1), .local_transform = .translate(0, 0) },
        .{ .key = record_key_mod.unhintedGlyph(0, 2), .local_transform = .translate(10, 0) },
        .{ .key = record_key_mod.unhintedGlyph(0, 3), .local_transform = .translate(20, 0) },
        .{ .key = record_key_mod.unhintedGlyph(0, 4), .local_transform = .translate(30, 0) },
    };
    var pic = try Picture.from(testing.allocator, &all_shapes);
    defer pic.deinit();

    // One-shot emit through the existing path.
    const cap = emit_mod.wordBudget(&pic, 0);
    const ref_words = try testing.allocator.alloc(u32, cap);
    defer testing.allocator.free(ref_words);
    var ref_segs: [4]DrawSegment = undefined;
    var ref_wlen: usize = 0;
    var ref_slen: usize = 0;
    _ = try emit_mod.emit(ref_words, ref_segs[0..], &ref_wlen, &ref_slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

    // Mosaic with one fragment per shape.
    var fragments: [4]*PictureFragment = undefined;
    inline for (0..4) |i| {
        const shape = [_]Shape{all_shapes[i]};
        var sp = try Picture.from(testing.allocator, &shape);
        defer sp.deinit();
        fragments[i] = try PictureFragment.build(testing.allocator, binding, &atlas, &sp, .identity, .{ 1, 1, 1, 1 });
    }
    defer for (fragments) |f| f.release();

    var mosaic = try PictureMosaic.from(testing.allocator, &fragments);
    defer mosaic.deinit();

    const m_words = try testing.allocator.alloc(u32, mosaicWordBudget(&mosaic));
    defer testing.allocator.free(m_words);
    const m_segs = try testing.allocator.alloc(DrawSegment, mosaicSegmentBudget(&mosaic));
    defer testing.allocator.free(m_segs);
    var m_wlen: usize = 0;
    var m_slen: usize = 0;
    _ = try emitMosaic(m_words, m_segs, &m_wlen, &m_slen, &mosaic);

    try testing.expectEqual(ref_wlen, m_wlen);
    try testing.expectEqual(ref_slen, m_slen);
    try testing.expectEqualSlices(u32, ref_words[0..ref_wlen], m_words[0..m_wlen]);
}

test "Mosaic.insert and remove keep other fragments shared" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2, 3 });
    defer atlas.deinit();
    const binding = Binding{ .pool = pool };

    var p1 = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 1) }});
    defer p1.deinit();
    var p2 = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 2) }});
    defer p2.deinit();
    var p3 = try Picture.from(testing.allocator, &.{.{ .key = record_key_mod.unhintedGlyph(0, 3) }});
    defer p3.deinit();

    const f1 = try PictureFragment.build(testing.allocator, binding, &atlas, &p1, .identity, .{ 1, 1, 1, 1 });
    defer f1.release();
    const f2 = try PictureFragment.build(testing.allocator, binding, &atlas, &p2, .identity, .{ 1, 1, 1, 1 });
    defer f2.release();
    const f3 = try PictureFragment.build(testing.allocator, binding, &atlas, &p3, .identity, .{ 1, 1, 1, 1 });
    defer f3.release();

    var m1 = try PictureMosaic.from(testing.allocator, &.{ f1, f3 });
    defer m1.deinit();

    var m2 = try m1.insert(testing.allocator, 1, f2);
    defer m2.deinit();
    try testing.expectEqual(@as(usize, 3), m2.fragments.len);
    try testing.expectEqual(f2, m2.fragments[1]);

    var m3 = try m2.remove(testing.allocator, 0);
    defer m3.deinit();
    try testing.expectEqual(@as(usize, 2), m3.fragments.len);
    try testing.expectEqual(f2, m3.fragments[0]);
    try testing.expectEqual(f3, m3.fragments[1]);
}
