//! Append-only atlas page.
//!
//! A page is one slot in a `PagePool` (and one layer of a backing GPU texture
//! array). It carries two parallel append-only buffers — a curve texture and
//! a band texture — that share the same lifetime and generation.
//!
//! ## Invariants
//!
//! - Bytes at offsets below `curve_used` (resp. `band_used`) are immutable.
//!   `reserve` extends these monotonically via atomic CAS.
//! - `uploaded` <= `used` for both buffers; the gap is the GPU's pending
//!   delta.
//! - `generation` advances when the page returns to the free list and is
//!   then re-allocated. Records issued at an old generation are invalid; the
//!   atlas itself holds the refcount that keeps a generation live.
//! - `refcount` counts atlas references. Pages start at refcount 0 when free
//!   and are bumped to 1 by `PagePool.acquire`. Each `Atlas` retain bumps,
//!   each `Atlas.deinit` releases.

const std = @import("std");
const curve_tex = @import("../render/format/curve_texture.zig");
const band_tex = @import("../render/format/band_texture.zig");

/// Half-word storage element. Both textures are u16 internally
/// (RGBA16F for curves, RG16UI for bands).
pub const Word = u16;

pub const SEGMENT_WORDS_PER_TEXEL: u32 = 4;
pub const CURVE_SEGMENT_TEXELS: u32 = curve_tex.SEGMENT_TEXELS;
pub const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
pub const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;

/// Per-axis (curve or band) buffer state. Kept compact and 8-byte aligned so
/// the two atomics live on independent cache lines from neighbouring page
/// fields under typical layouts.
pub const Buffer = struct {
    data: []Word,
    capacity_words: u32,
    used_words: std.atomic.Value(u32),
    uploaded_words: std.atomic.Value(u32),

    pub fn init(data: []Word) Buffer {
        return .{
            .data = data,
            .capacity_words = @intCast(data.len),
            .used_words = std.atomic.Value(u32).init(0),
            .uploaded_words = std.atomic.Value(u32).init(0),
        };
    }

    pub fn reset(self: *Buffer) void {
        self.used_words.store(0, .release);
        self.uploaded_words.store(0, .release);
    }

    /// Reserve `n` words at the current tail. Returns the starting word
    /// offset or `null` if the page is full.
    pub fn reserve(self: *Buffer, n: u32) ?u32 {
        while (true) {
            const cur = self.used_words.load(.acquire);
            if (cur > self.capacity_words or self.capacity_words - cur < n) return null;
            const next = cur + n;
            if (self.used_words.cmpxchgWeak(cur, next, .acq_rel, .acquire) == null) {
                return cur;
            }
        }
    }

    pub fn usedWords(self: *const Buffer) u32 {
        return self.used_words.load(.acquire);
    }

    pub fn uploadedWords(self: *const Buffer) u32 {
        return self.uploaded_words.load(.acquire);
    }

    /// Mark the buffer as uploaded up to `n` words. `n` must be <= current
    /// used. Idempotent: monotonic update.
    pub fn markUploaded(self: *Buffer, n: u32) void {
        std.debug.assert(n <= self.used_words.load(.acquire));
        while (true) {
            const cur = self.uploaded_words.load(.acquire);
            if (n <= cur) return;
            if (self.uploaded_words.cmpxchgWeak(cur, n, .acq_rel, .acquire) == null) return;
        }
    }
};

pub const AtlasPage = struct {
    allocator: std.mem.Allocator,
    layer_index: u16,
    generation: std.atomic.Value(u32),
    refcount: std.atomic.Value(u32),
    curve: Buffer,
    band: Buffer,

    pub fn init(
        allocator: std.mem.Allocator,
        layer_index: u16,
        curve_capacity_words: u32,
        band_capacity_words: u32,
    ) !*AtlasPage {
        const page = try allocator.create(AtlasPage);
        errdefer allocator.destroy(page);
        const curve_buf = try allocator.alloc(Word, curve_capacity_words);
        errdefer allocator.free(curve_buf);
        const band_buf = try allocator.alloc(Word, band_capacity_words);
        errdefer allocator.free(band_buf);
        // No @memset: both buffers are written before read. Curve and
        // band shaders fetch by explicit entry offsets that point only
        // at written regions; unwritten words are never accessed.
        page.* = .{
            .allocator = allocator,
            .layer_index = layer_index,
            .generation = std.atomic.Value(u32).init(1),
            .refcount = std.atomic.Value(u32).init(0),
            .curve = Buffer.init(curve_buf),
            .band = Buffer.init(band_buf),
        };
        return page;
    }

    pub fn deinit(self: *AtlasPage) void {
        self.allocator.free(self.curve.data);
        self.allocator.free(self.band.data);
        self.allocator.destroy(self);
    }

    pub fn retain(self: *AtlasPage) void {
        _ = self.refcount.fetchAdd(1, .acq_rel);
    }

    /// Decrement refcount; returns true if the page should be returned to
    /// the pool's free list (i.e. refcount transitioned to zero).
    pub fn release(self: *AtlasPage) bool {
        const prior = self.refcount.fetchSub(1, .acq_rel);
        std.debug.assert(prior > 0);
        return prior == 1;
    }

    pub fn currentGeneration(self: *const AtlasPage) u16 {
        return @intCast(self.generation.load(.acquire) & 0xFFFF);
    }

    /// Reset for reuse: bumps generation, clears both buffers' used and
    /// uploaded counters. Called by the pool when the page is recycled.
    pub fn recycle(self: *AtlasPage) void {
        _ = self.generation.fetchAdd(1, .acq_rel);
        self.curve.reset();
        self.band.reset();
    }

    /// Reserve curve+band space for a record. Both must succeed atomically:
    /// if the band reservation fails, the curve allocation is *not* rolled
    /// back (the bytes are simply unreferenced). This matches the immutable
    /// append-only contract: bytes don't move once written.
    ///
    /// Returns the starting word offsets into curve and band buffers, or
    /// `null` if either buffer lacks room.
    pub fn reserve(
        self: *AtlasPage,
        curve_words: u32,
        band_words: u32,
    ) ?Reservation {
        const cw = self.curve.reserve(curve_words) orelse return null;
        const bw = self.band.reserve(band_words) orelse return null;
        return .{ .curve_word_offset = cw, .band_word_offset = bw };
    }

    pub const Reservation = struct {
        curve_word_offset: u32,
        band_word_offset: u32,
    };

    /// Slice from offset 0 up to the current used watermark. The returned
    /// slice's bytes are immutable for the page's current generation.
    pub fn curveBytesUsed(self: *const AtlasPage) []const Word {
        return self.curve.data[0..self.curve.usedWords()];
    }

    pub fn bandBytesUsed(self: *const AtlasPage) []const Word {
        return self.band.data[0..self.band.usedWords()];
    }
};

test "buffer reserve grows monotonically and bounds correctly" {
    const data = try std.testing.allocator.alloc(Word, 8);
    defer std.testing.allocator.free(data);
    var b = Buffer.init(data);

    try std.testing.expectEqual(@as(?u32, 0), b.reserve(4));
    try std.testing.expectEqual(@as(?u32, 4), b.reserve(4));
    try std.testing.expectEqual(@as(?u32, null), b.reserve(1));
    try std.testing.expectEqual(@as(u32, 8), b.usedWords());
}

test "page recycle bumps generation and resets buffers" {
    var page = try AtlasPage.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    const g0 = page.currentGeneration();
    _ = page.curve.reserve(4);
    _ = page.band.reserve(2);
    try std.testing.expect(page.curve.usedWords() == 4);

    page.recycle();
    try std.testing.expect(page.currentGeneration() != g0);
    try std.testing.expect(page.curve.usedWords() == 0);
    try std.testing.expect(page.band.usedWords() == 0);
}

test "page refcount round-trips" {
    var page = try AtlasPage.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    page.retain();
    page.retain();
    try std.testing.expectEqual(false, page.release());
    try std.testing.expectEqual(true, page.release());
}

test "concurrent reserve hands out disjoint ranges" {
    var page = try AtlasPage.init(std.testing.allocator, 0, 1024, 256);
    defer page.deinit();

    const Worker = struct {
        fn run(p: *AtlasPage, results: *std.atomic.Value(u32), gathered: []u32, idx: *std.atomic.Value(u32)) void {
            while (true) {
                const off = p.curve.reserve(4) orelse break;
                _ = results.fetchAdd(1, .acq_rel);
                const slot = idx.fetchAdd(1, .acq_rel);
                if (slot < gathered.len) gathered[slot] = off;
            }
        }
    };

    var results = std.atomic.Value(u32).init(0);
    var slot = std.atomic.Value(u32).init(0);
    var gathered: [256]u32 = undefined;

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ page, &results, gathered[0..], &slot });
    }
    for (threads) |t| t.join();

    const count = results.load(.acquire);
    try std.testing.expectEqual(@as(u32, 256), count);

    var seen: [256]bool = undefined;
    @memset(&seen, false);
    for (gathered[0..@min(@as(usize, count), gathered.len)]) |off| {
        const idx = off / 4;
        try std.testing.expect(!seen[idx]);
        seen[idx] = true;
    }
}
