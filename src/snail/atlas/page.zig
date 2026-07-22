//! Append-only atlas page.
//!
//! A page is one slot in a `PagePool` (and one layer of a backing GPU texture
//! array). It carries two parallel append-only buffers — a curve texture and
//! a band texture — that share the same lifetime and generation.
//!
//! ## Invariants
//!
//! - Reservations advance a private tail; they are not visible to readers.
//! - A reservation's curve and band bytes become visible together when it is
//!   committed. Bytes below the published watermarks are immutable.
//! - `generation` advances when the page returns to the free list and is
//!   then re-allocated. Records issued at an old generation are invalid; the
//!   atlas itself holds the refcount that keeps a generation live.
//! - `refcount` counts atlas references. Pages start at refcount 0 when free
//!   and are bumped to 1 by `PagePool.acquire`. Each `Atlas` retain bumps,
//!   each `Atlas.deinit` releases.

const std = @import("std");
const curve_tex = @import("../format/curve_texture.zig");
const band_tex = @import("../format/band_texture.zig");

/// Half-word storage element. Both textures are u16 internally
/// (RGBA16F for curves, RG16UI for bands).
pub const Word = u16;

pub const SEGMENT_WORDS_PER_TEXEL: u32 = 4;
pub const CURVE_SEGMENT_TEXELS: u32 = curve_tex.SEGMENT_TEXELS;
pub const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * SEGMENT_WORDS_PER_TEXEL;
pub const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
pub const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;

/// Per-axis (curve or band) storage. Publication is owned by `Page` so
/// the two planes always acquire one consistent pair of watermarks.
const Buffer = struct {
    data: []Word,
    capacity_words: u32,

    pub fn init(data: []Word) Buffer {
        return .{
            .data = data,
            .capacity_words = @intCast(data.len),
        };
    }
};

pub const Reservation = struct {
    curve_word_offset: u32,
    band_word_offset: u32,
    curve_word_count: u32,
    band_word_count: u32,
};

pub const PublishedWords = struct {
    curve: u32,
    band: u32,
};

/// Opaque page handle stored by `Atlas`. Storage, reservations, publication,
/// generation identity, and reference counts stay inside this module.
pub const AtlasPage = opaque {};

const Page = struct {
    allocator: std.mem.Allocator,
    layer_index: u16,
    generation: std.atomic.Value(u64),
    refcount: std.atomic.Value(u32),
    curve: Buffer,
    band: Buffer,
    /// Packed `(band_words << 32) | curve_words`. A single release store makes
    /// both initialized planes visible as one publication event.
    published_words: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Private reservation tails, protected by `reservation_lock`.
    reserved_curve_words: u32 = 0,
    reserved_band_words: u32 = 0,
    /// Serializes reservation-tail changes and ordered publication.
    reservation_lock: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn init(
        allocator: std.mem.Allocator,
        layer_index: u16,
        curve_capacity_words: u32,
        band_capacity_words: u32,
    ) !*Page {
        const page = try allocator.create(Page);
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
            .generation = std.atomic.Value(u64).init(1),
            .refcount = std.atomic.Value(u32).init(0),
            .curve = Buffer.init(curve_buf),
            .band = Buffer.init(band_buf),
        };
        return page;
    }

    pub fn deinit(self: *Page) void {
        self.allocator.free(self.curve.data);
        self.allocator.free(self.band.data);
        self.allocator.destroy(self);
    }

    pub fn retain(self: *Page) error{ReferenceCountExhausted}!void {
        while (true) {
            const prior = self.refcount.load(.acquire);
            if (prior == std.math.maxInt(u32)) return error.ReferenceCountExhausted;
            if (self.refcount.cmpxchgWeak(prior, prior + 1, .acq_rel, .acquire) == null) return;
        }
    }

    /// Decrement refcount; returns true if the page should be returned to
    /// the pool's free list (i.e. refcount transitioned to zero).
    pub fn release(self: *Page) bool {
        while (true) {
            const prior = self.refcount.load(.acquire);
            if (prior == 0) @panic("AtlasPage reference underflow");
            if (self.refcount.cmpxchgWeak(prior, prior - 1, .acq_rel, .acquire) == null) return prior == 1;
        }
    }

    pub fn currentGeneration(self: *const Page) u64 {
        return self.generation.load(.acquire);
    }

    /// Reset for reuse: bumps generation and clears the reservation and
    /// publication tails. Called by the pool when the page is recycled.
    pub fn recycle(self: *Page) void {
        const prior = self.generation.fetchAdd(1, .acq_rel);
        if (prior == std.math.maxInt(u64)) {
            @panic("AtlasPage generation space exhausted");
        }
        self.reserved_curve_words = 0;
        self.reserved_band_words = 0;
        self.published_words.store(0, .release);
    }

    /// Reserve curve+band space for a record. A reservation is private until
    /// `commit` or `discard`; readers continue to observe the previous paired
    /// watermark. Every successful reservation must eventually be committed
    /// or discarded, otherwise later publication waits for the missing range.
    ///
    /// Returns the starting word offsets into curve and band buffers, or
    /// `null` if either buffer lacks room.
    pub fn reserve(
        self: *Page,
        curve_words: u32,
        band_words: u32,
    ) ?Reservation {
        while (self.reservation_lock.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
        defer self.reservation_lock.store(0, .release);

        const cw = self.reserved_curve_words;
        const bw = self.reserved_band_words;
        if (cw > self.curve.capacity_words or
            self.curve.capacity_words - cw < curve_words or
            bw > self.band.capacity_words or
            self.band.capacity_words - bw < band_words)
        {
            return null;
        }
        self.reserved_curve_words = cw + curve_words;
        self.reserved_band_words = bw + band_words;
        return .{
            .curve_word_offset = cw,
            .band_word_offset = bw,
            .curve_word_count = curve_words,
            .band_word_count = band_words,
        };
    }

    fn packWords(words: PublishedWords) u64 {
        return @as(u64, words.curve) | (@as(u64, words.band) << 32);
    }

    fn unpackWords(value: u64) PublishedWords {
        return .{ .curve = @truncate(value), .band = @truncate(value >> 32) };
    }

    /// Atomically acquire the initialized curve+band watermarks.
    pub fn publishedWords(self: *const Page) PublishedWords {
        return unpackWords(self.published_words.load(.acquire));
    }

    /// Publish a fully initialized reservation. Reservations may be populated
    /// concurrently, but are published in reservation order so no reader can
    /// observe a hole or partially initialized bytes.
    pub fn commit(self: *Page, reservation: Reservation) void {
        const expected = packWords(.{
            .curve = reservation.curve_word_offset,
            .band = reservation.band_word_offset,
        });
        const next = packWords(.{
            .curve = reservation.curve_word_offset + reservation.curve_word_count,
            .band = reservation.band_word_offset + reservation.band_word_count,
        });
        while (true) {
            if (self.published_words.load(.acquire) != expected) {
                std.atomic.spinLoopHint();
                continue;
            }
            if (self.reservation_lock.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
                std.atomic.spinLoopHint();
                continue;
            }
            if (self.published_words.load(.monotonic) == expected) {
                std.debug.assert(reservation.curve_word_offset + reservation.curve_word_count <= self.reserved_curve_words);
                std.debug.assert(reservation.band_word_offset + reservation.band_word_count <= self.reserved_band_words);
                self.published_words.store(next, .release);
                self.reservation_lock.store(0, .release);
                return;
            }
            self.reservation_lock.store(0, .release);
        }
    }

    /// Abandon a reservation without blocking later reservations. The range is
    /// zeroed and published as immutable padding; committed watermarks never
    /// move backwards, so upload planners cannot retain stale reused bytes.
    pub fn discard(self: *Page, reservation: Reservation) void {
        @memset(self.curve.data[reservation.curve_word_offset..][0..reservation.curve_word_count], 0);
        @memset(self.band.data[reservation.band_word_offset..][0..reservation.band_word_count], 0);
        self.commit(reservation);
    }

    /// Slice from offset 0 up to the current used watermark. The returned
    /// slice's bytes are immutable for the page's current generation.
    pub fn curveBytesUsed(self: *const Page) []const Word {
        return self.curve.data[0..self.publishedWords().curve];
    }

    pub fn bandBytesUsed(self: *const Page) []const Word {
        return self.band.data[0..self.publishedWords().band];
    }
};

pub const ReferenceError = error{ReferenceCountExhausted};

fn pageImpl(page: *AtlasPage) *Page {
    return @ptrCast(@alignCast(page));
}

fn pageImplConst(page: *const AtlasPage) *const Page {
    return @ptrCast(@alignCast(page));
}

pub fn init(
    allocator: std.mem.Allocator,
    layer_index: u16,
    curve_capacity_words: u32,
    band_capacity_words: u32,
) !*AtlasPage {
    return @ptrCast(try Page.init(allocator, layer_index, curve_capacity_words, band_capacity_words));
}

pub fn deinit(page: *AtlasPage) void {
    pageImpl(page).deinit();
}

pub fn activate(page: *AtlasPage) void {
    const impl = pageImpl(page);
    std.debug.assert(impl.refcount.load(.acquire) == 0);
    impl.refcount.store(1, .release);
}

pub fn isFree(page: *const AtlasPage) bool {
    return pageImplConst(page).refcount.load(.acquire) == 0;
}

pub fn refCount(page: *const AtlasPage) u32 {
    return pageImplConst(page).refcount.load(.acquire);
}

/// Test-only fault injection for callers that verify retain overflow
/// propagation across atlas transactions.
pub fn testSetReferenceCount(page: *AtlasPage, value: u32) void {
    if (!@import("builtin").is_test) @panic("test-only page fault injection");
    pageImpl(page).refcount.store(value, .release);
}

pub fn retain(page: *AtlasPage) ReferenceError!void {
    return pageImpl(page).retain();
}

pub fn release(page: *AtlasPage) bool {
    return pageImpl(page).release();
}

pub fn recycle(page: *AtlasPage) void {
    pageImpl(page).recycle();
}

pub fn layerIndex(page: *const AtlasPage) u16 {
    return pageImplConst(page).layer_index;
}

pub fn currentGeneration(page: *const AtlasPage) u64 {
    return pageImplConst(page).currentGeneration();
}

pub fn publishedWords(page: *const AtlasPage) PublishedWords {
    return pageImplConst(page).publishedWords();
}

pub fn reserve(page: *AtlasPage, curve_words: u32, band_words: u32) ?Reservation {
    return pageImpl(page).reserve(curve_words, band_words);
}

pub fn reservationCurveWords(page: *AtlasPage, reservation: Reservation) []Word {
    const impl = pageImpl(page);
    return impl.curve.data[reservation.curve_word_offset..][0..reservation.curve_word_count];
}

pub fn reservationBandWords(page: *AtlasPage, reservation: Reservation) []Word {
    const impl = pageImpl(page);
    return impl.band.data[reservation.band_word_offset..][0..reservation.band_word_count];
}

pub fn commit(page: *AtlasPage, reservation: Reservation) void {
    pageImpl(page).commit(reservation);
}

pub fn discard(page: *AtlasPage, reservation: Reservation) void {
    pageImpl(page).discard(reservation);
}

pub fn curveWordsUsed(page: *const AtlasPage) []const Word {
    return pageImplConst(page).curveBytesUsed();
}

pub fn bandWordsUsed(page: *const AtlasPage) []const Word {
    return pageImplConst(page).bandBytesUsed();
}

test "reservation remains invisible until both planes are committed" {
    var page = try Page.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    const reservation = page.reserve(4, 2).?;
    @memset(page.curve.data[0..4], 0x1234);
    @memset(page.band.data[0..2], 0x5678);
    try std.testing.expectEqual(PublishedWords{ .curve = 0, .band = 0 }, page.publishedWords());

    page.commit(reservation);
    try std.testing.expectEqual(PublishedWords{ .curve = 4, .band = 2 }, page.publishedWords());
}

test "page recycle bumps generation and resets buffers" {
    var page = try Page.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    const g0 = page.currentGeneration();
    const reservation = page.reserve(4, 2).?;
    page.discard(reservation);
    try std.testing.expectEqual(PublishedWords{ .curve = 4, .band = 2 }, page.publishedWords());

    page.recycle();
    try std.testing.expect(page.currentGeneration() != g0);
    try std.testing.expectEqual(PublishedWords{ .curve = 0, .band = 0 }, page.publishedWords());
}

test "page generation does not alias after the old 16-bit boundary" {
    var page = try Page.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    page.generation.store(std.math.maxInt(u16), .release);
    page.recycle();
    try std.testing.expectEqual(@as(u64, @as(u64, std.math.maxInt(u16)) + 1), page.currentGeneration());
}

test "paired reservation does not consume curve capacity when bands are full" {
    var page = try Page.init(std.testing.allocator, 0, 16, 2);
    defer page.deinit();

    const reservation = page.reserve(4, 2).?;
    try std.testing.expectEqual(@as(?Reservation, null), page.reserve(4, 2));
    try std.testing.expectEqual(PublishedWords{ .curve = 0, .band = 0 }, page.publishedWords());
    page.discard(reservation);
    try std.testing.expectEqual(PublishedWords{ .curve = 4, .band = 2 }, page.publishedWords());
}

test "discard publishes immutable padding instead of rolling watermarks back" {
    var page = try Page.init(std.testing.allocator, 0, 32, 16);
    defer page.deinit();

    const first = page.reserve(4, 2).?;
    @memset(page.curve.data[0..4], 1);
    @memset(page.band.data[0..2], 1);
    page.commit(first);
    const abandoned = page.reserve(8, 4).?;
    page.discard(abandoned);

    try std.testing.expectEqual(PublishedWords{ .curve = 12, .band = 6 }, page.publishedWords());
    try std.testing.expectEqualSlices(Word, &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, page.curve.data[4..12]);
    try std.testing.expectEqualSlices(Word, &.{ 0, 0, 0, 0 }, page.band.data[2..6]);
}

test "page refcount round-trips" {
    var page = try Page.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();

    try page.retain();
    try page.retain();
    try std.testing.expectEqual(false, page.release());
    try std.testing.expectEqual(true, page.release());
}

test "page retain reports exhaustion without wrapping the refcount" {
    var page = try Page.init(std.testing.allocator, 0, 16, 8);
    defer page.deinit();
    page.refcount.store(std.math.maxInt(u32), .release);

    try std.testing.expectError(error.ReferenceCountExhausted, page.retain());
    try std.testing.expectEqual(std.math.maxInt(u32), page.refcount.load(.acquire));
}

test "concurrent reserve initializes before ordered publication" {
    var page = try Page.init(std.testing.allocator, 0, 1024, 512);
    defer page.deinit();

    const Worker = struct {
        fn run(p: *Page, results: *std.atomic.Value(u32), gathered: []u32, idx: *std.atomic.Value(u32)) void {
            while (true) {
                const reservation = p.reserve(4, 2) orelse break;
                const marker: Word = @intCast(reservation.curve_word_offset / 4 + 1);
                @memset(p.curve.data[reservation.curve_word_offset..][0..4], marker);
                @memset(p.band.data[reservation.band_word_offset..][0..2], marker);
                p.commit(reservation);
                _ = results.fetchAdd(1, .acq_rel);
                const slot = idx.fetchAdd(1, .acq_rel);
                if (slot < gathered.len) gathered[slot] = reservation.curve_word_offset;
            }
        }
    };
    const Reader = struct {
        fn run(p: *const Page, done: *std.atomic.Value(bool), failed: *std.atomic.Value(bool)) void {
            while (!done.load(.acquire)) {
                const published = p.publishedWords();
                if (published.curve != published.band * 2) {
                    failed.store(true, .release);
                    return;
                }
                var curve_offset: usize = 0;
                var band_offset: usize = 0;
                while (curve_offset < published.curve) : ({
                    curve_offset += 4;
                    band_offset += 2;
                }) {
                    const marker = p.curve.data[curve_offset];
                    if (marker == 0 or
                        !std.mem.allEqual(Word, p.curve.data[curve_offset..][0..4], marker) or
                        !std.mem.allEqual(Word, p.band.data[band_offset..][0..2], marker))
                    {
                        failed.store(true, .release);
                        return;
                    }
                }
            }
        }
    };

    var results = std.atomic.Value(u32).init(0);
    var slot = std.atomic.Value(u32).init(0);
    var done = std.atomic.Value(bool).init(false);
    var failed = std.atomic.Value(bool).init(false);
    var gathered: [256]u32 = undefined;

    const reader = try std.Thread.spawn(.{}, Reader.run, .{ page, &done, &failed });
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{ page, &results, gathered[0..], &slot });
    }
    for (threads) |t| t.join();
    done.store(true, .release);
    reader.join();

    const count = results.load(.acquire);
    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expectEqual(@as(u32, 256), count);
    try std.testing.expectEqual(PublishedWords{ .curve = 1024, .band = 512 }, page.publishedWords());

    var seen: [256]bool = undefined;
    @memset(&seen, false);
    for (gathered[0..@min(@as(usize, count), gathered.len)]) |off| {
        const idx = off / 4;
        try std.testing.expect(!seen[idx]);
        seen[idx] = true;
    }
    for (0..256) |i| {
        const marker: Word = @intCast(i + 1);
        try std.testing.expectEqualSlices(Word, &.{ marker, marker, marker, marker }, page.curve.data[i * 4 ..][0..4]);
        try std.testing.expectEqualSlices(Word, &.{ marker, marker }, page.band.data[i * 2 ..][0..2]);
    }
}
