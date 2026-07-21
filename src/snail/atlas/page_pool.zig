//! Fixed-capacity bag of pages — the caller's residency budget.
//!
//! The pool owns its pages for its whole lifetime. Pages move between two
//! states: "in the free list" and "checked out (refcount >= 1)". Acquiring
//! a page pulls one off the free list; releasing one (refcount → 0) pushes
//! it back. The pool never deallocates a page; it just shuffles ownership.
//!
//! `max_layers` bounds the *resident* record set, not the total glyphs an
//! app may ever touch: `error.OutOfLayers` from a record call is the
//! signal to evict via `Atlas.compact` with a `RecordFilter` (see the
//! capacity model notes on `Atlas`). `free_count` is the headroom gauge —
//! evict while it is still above the expected compacted page count, since
//! compaction acquires its pages before the old atlas releases any. The
//! pool's `max_layers` also fixes the depth of the backend's curve/band
//! texture arrays, so growing the budget means recreating those textures.
//!
//! The pool does *not* own GPU resources — that lives in the backend-side
//! `Binding` returned by `upload`. This file is pure CPU-side bookkeeping.
//!
//! **Threading.** `acquire` / `release` / `stats` are MT-safe via a
//! spinlock. The spinlock is designed for the expected workload —
//! atlas/build-time acquire and frame-boundary release — where
//! contention is rare and short. It is *not* a fit for a hot per-record
//! call site: hold a page reference and append to it directly, don't
//! re-acquire from the pool per record.

const std = @import("std");
const page_mod = @import("page.zig");

pub const AtlasPage = page_mod.AtlasPage;

/// Minimal test-and-set spinlock. The pool is only touched at acquire/release
/// boundaries (not on the per-record append path), so contention is rare;
/// a spinlock is the simplest correct primitive that doesn't require the
/// `std.Io`-gated `std.Thread.Mutex`.
const Spinlock = struct {
    state: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    fn lock(self: *Spinlock) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *Spinlock) void {
        self.state.store(0, .release);
    }
};

pub const Options = struct {
    /// Maximum number of pages (equal to the GPU texture array layer count).
    max_layers: u32,
    /// Capacity in u16 words for the curve buffer of each page.
    curve_words_per_page: u32,
    /// Capacity in u16 words for the band buffer of each page.
    band_words_per_page: u32,
};

pub const Stats = struct {
    pages_total: u32,
    pages_in_use: u32,
    pages_free: u32,
    curve_bytes_total: u64,
    curve_bytes_used: u64,
    band_bytes_total: u64,
    band_bytes_used: u64,
};

pub const PagePool = struct {
    allocator: std.mem.Allocator,
    options: Options,
    pages: []*AtlasPage,
    /// Indices into `pages` that are currently free. `free_count` is the
    /// number of valid entries (LIFO).
    free_stack: []u16,
    free_count: u32,
    mutex: Spinlock = .{},

    pub fn init(allocator: std.mem.Allocator, options: Options) !*PagePool {
        std.debug.assert(options.max_layers > 0);

        const pool = try allocator.create(PagePool);
        errdefer allocator.destroy(pool);

        const pages = try allocator.alloc(*AtlasPage, options.max_layers);
        errdefer allocator.free(pages);

        const stack = try allocator.alloc(u16, options.max_layers);
        errdefer allocator.free(stack);

        var built: u32 = 0;
        errdefer {
            var i: u32 = 0;
            while (i < built) : (i += 1) pages[i].deinit();
        }

        while (built < options.max_layers) : (built += 1) {
            pages[built] = try AtlasPage.init(
                allocator,
                @intCast(built),
                options.curve_words_per_page,
                options.band_words_per_page,
            );
            // Free pages sit at the bottom of the stack in order; allocation
            // pops from the top, so the lowest layer_index goes out first.
            stack[options.max_layers - 1 - built] = @intCast(built);
        }

        pool.* = .{
            .allocator = allocator,
            .options = options,
            .pages = pages,
            .free_stack = stack,
            .free_count = options.max_layers,
        };
        return pool;
    }

    pub fn deinit(self: *PagePool) void {
        for (self.pages) |p| p.deinit();
        self.allocator.free(self.pages);
        self.allocator.free(self.free_stack);
        const a = self.allocator;
        a.destroy(self);
    }

    pub const AcquireError = error{OutOfLayers};

    /// Pull a fresh page off the free list. Caller takes one ref (refcount
    /// transitions from 0 to 1). Returns `error.OutOfLayers` if the pool is
    /// exhausted; callers should oversize the pool at construction or
    /// recover by rebuilding it (see `docs/rewrite/12-open-questions.md`).
    pub fn acquire(self: *PagePool) AcquireError!*AtlasPage {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.free_count == 0) return error.OutOfLayers;
        self.free_count -= 1;
        const layer = self.free_stack[self.free_count];
        const page = self.pages[layer];
        std.debug.assert(page.refcount.load(.acquire) == 0);
        page.refcount.store(1, .release);
        return page;
    }

    /// Decrement a page's refcount; on transition to zero, recycle it back
    /// to the free list. Safe to call any number of times for releases that
    /// were retained earlier via `page.retain()` or `acquire`.
    pub fn release(self: *PagePool, page: *AtlasPage) void {
        if (!page.release()) return;
        // refcount hit zero: recycle.
        page.recycle();
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.assert(self.free_count < self.pages.len);
        self.free_stack[self.free_count] = page.layer_index;
        self.free_count += 1;
    }

    pub fn stats(self: *PagePool) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var curve_used: u64 = 0;
        var band_used: u64 = 0;
        for (self.pages) |p| {
            curve_used += @as(u64, p.curve.usedWords()) * @sizeOf(page_mod.Word);
            band_used += @as(u64, p.band.usedWords()) * @sizeOf(page_mod.Word);
        }
        const pages_total: u32 = @intCast(self.pages.len);
        const pages_free = self.free_count;
        return .{
            .pages_total = pages_total,
            .pages_in_use = pages_total - pages_free,
            .pages_free = pages_free,
            .curve_bytes_total = @as(u64, pages_total) * @as(u64, self.options.curve_words_per_page) * @sizeOf(page_mod.Word),
            .curve_bytes_used = curve_used,
            .band_bytes_total = @as(u64, pages_total) * @as(u64, self.options.band_words_per_page) * @sizeOf(page_mod.Word),
            .band_bytes_used = band_used,
        };
    }
};

test "pool acquire and release round-trip" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool.deinit();

    const a = try pool.acquire();
    const b = try pool.acquire();
    try std.testing.expect(a != b);
    try std.testing.expect(a.layer_index != b.layer_index);
    try std.testing.expectEqual(@as(u32, 1), a.refcount.load(.acquire));

    pool.release(a);
    try std.testing.expectEqual(@as(u32, 0), a.refcount.load(.acquire));

    const c = try pool.acquire();
    // `a` was the most recently freed (LIFO) so it should come back first.
    try std.testing.expectEqual(a.layer_index, c.layer_index);

    pool.release(b);
    pool.release(c);
}

test "pool exhausts at capacity" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 16,
        .band_words_per_page = 8,
    });
    defer pool.deinit();

    const p0 = try pool.acquire();
    const p1 = try pool.acquire();
    try std.testing.expectError(error.OutOfLayers, pool.acquire());

    pool.release(p0);
    pool.release(p1);
}

test "release recycles on refcount transition to zero" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 16,
        .band_words_per_page = 8,
    });
    defer pool.deinit();

    const p = try pool.acquire();
    p.retain();
    _ = p.curve.reserve(4);
    const g0 = p.currentGeneration();

    pool.release(p); // still refcount 1
    try std.testing.expect(p.refcount.load(.acquire) == 1);
    try std.testing.expectError(error.OutOfLayers, pool.acquire());

    pool.release(p); // refcount 0 → recycled
    try std.testing.expect(p.refcount.load(.acquire) == 0);
    try std.testing.expect(p.currentGeneration() != g0);
    try std.testing.expect(p.curve.usedWords() == 0);

    const reused = try pool.acquire();
    try std.testing.expectEqual(p.layer_index, reused.layer_index);
    pool.release(reused);
}

test "pool stats track used watermarks" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 32,
        .band_words_per_page = 16,
    });
    defer pool.deinit();

    const p = try pool.acquire();
    _ = p.curve.reserve(8);
    _ = p.band.reserve(4);

    const s = pool.stats();
    try std.testing.expectEqual(@as(u32, 2), s.pages_total);
    try std.testing.expectEqual(@as(u32, 1), s.pages_in_use);
    try std.testing.expectEqual(@as(u64, 8 * @sizeOf(page_mod.Word)), s.curve_bytes_used);
    try std.testing.expectEqual(@as(u64, 4 * @sizeOf(page_mod.Word)), s.band_bytes_used);

    pool.release(p);
}
