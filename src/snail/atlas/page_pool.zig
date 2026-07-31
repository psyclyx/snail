//! Fixed-capacity logical page pool — the caller's residency budget.
//!
//! Page storage is allocated lazily on first use and retained for the pool's
//! lifetime. Allocated pages move between two states: "in the free list" and
//! "checked out (refcount >= 1)". Acquiring a page pulls a logical index off
//! the free list; releasing one (refcount → 0) pushes it back.
//!
//! `max_pages` bounds the *resident* record set, not the total glyphs an
//! app may ever touch: `error.OutOfLayers` from an update is the signal to
//! evict via `Atlas.compactInto` with a `RecordFilter` (see the capacity model
//! notes on `Atlas`). A distinct destination pool needs no free pages in the
//! source; `free_count` matters only to the same-pool `compact` convenience. The
//! Draw batches split the logical range into 256-page banks. A backend may
//! use separate texture arrays per bank, one deeper array where supported,
//! or the flat-buffer layout exposed by `atlas_upload.FlatLayout`.
//!
//! The pool does *not* own GPU resources — that lives in the backend-side
//! `Binding` returned by `upload`. This file is pure CPU-side bookkeeping.
//!
//! **Threading.** `acquire` / `release` / `stats` are MT-safe. The spinlock
//! protects only fixed-size bookkeeping; lazy heap allocation happens outside
//! it and is serialized separately. Hold a page reference and append to it
//! directly rather than re-acquiring from the pool per record.

const std = @import("std");
const page_mod = @import("page.zig");
const render_abi = @import("../format/abi.zig");
const band_tex = @import("../format/band_texture.zig");

const AtlasPage = page_mod.AtlasPage;

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
    /// Maximum logical pages. Draw batches bank these into 256-layer resource
    /// windows, so this may exceed a backend texture-array layer limit.
    max_pages: u32,
    /// Capacity in u16 words for the curve buffer of each page. Must be
    /// nonzero, segment-aligned, and representable by packed band refs.
    curve_words_per_page: u32,
    /// Capacity in u16 words for the band buffer of each page. Must be
    /// nonzero, texel-aligned, and addressable by `GlyphBandEntry`.
    band_words_per_page: u32,
};

pub const Stats = struct {
    /// Logical page capacity configured by `max_pages`.
    pages_total: u32,
    /// Pages whose CPU storage has been allocated at least once.
    pages_allocated: u32,
    pages_in_use: u32,
    pages_free: u32,
    /// Logical capacity, including pages not allocated on the CPU yet.
    curve_bytes_total: u64,
    curve_bytes_allocated: u64,
    curve_bytes_used: u64,
    /// Logical capacity, including pages not allocated on the CPU yet.
    band_bytes_total: u64,
    band_bytes_allocated: u64,
    band_bytes_used: u64,
};

const OptionsType = Options;
const StatsType = Stats;

/// Opaque, fixed-capacity atlas residency budget.
///
/// Page allocation, reference counting, publication, and generation identity
/// are implementation details shared by `Atlas`, `atlas_upload`, and the draw
/// encoder. Callers configure the budget, query aggregate statistics, and keep
/// the handle alive; raw mutable pages are intentionally unreachable.
pub const PagePool = opaque {
    pub const Options = OptionsType;
    pub const Stats = StatsType;
    pub const InitError = std.mem.Allocator.Error || error{InvalidOptions};
    pub const IdentityError = error{IdentityExhausted};
    pub const AcquireError = std.mem.Allocator.Error || error{OutOfLayers};

    pub fn init(allocator: std.mem.Allocator, options: OptionsType) InitError!*PagePool {
        return @ptrCast(try Pool.init(allocator, options));
    }

    /// Destroy the pool and every page it owns. The pool must outlive all
    /// atlases, upload planners, device caches, and bindings created from it.
    pub fn deinit(self: *PagePool) void {
        poolImpl(self).deinit();
    }

    /// Return the immutable capacity configuration supplied to `init`.
    pub fn config(self: *const PagePool) OptionsType {
        return poolImplConst(self).options;
    }

    pub fn stats(self: *PagePool) StatsType {
        return poolImpl(self).stats();
    }
};

const Pool = struct {
    allocator: std.mem.Allocator,
    options: Options,
    pages: []?*AtlasPage,
    /// Indices into `pages` that are currently free. `free_count` is the
    /// number of valid entries (LIFO).
    free_stack: []u16,
    free_count: u32,
    mutex: Spinlock = .{},
    /// Serializes calls into allocators that do not promise thread safety,
    /// without blocking fixed-size acquire/release/stat bookkeeping.
    allocation_lock: Spinlock = .{},
    /// Monotonic identity source for Atlas snapshots backed by this pool.
    /// Zero is reserved for pool-less `Atlas.empty` values.
    next_atlas_snapshot_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1),
    /// Unique namespace for each upload planner/cache attached to this pool.
    next_binding_source_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1),

    fn init(allocator: std.mem.Allocator, options: OptionsType) PagePool.InitError!*Pool {
        // Logical page indices are u16; packed instances carry the bank-local
        // low byte and DrawBatch carries the aligned layer base.
        const max_curve_words = @as(u64, page_mod.CURVE_TEX_WIDTH) *
            (@as(u64, 1) << band_tex.curve_loc_y_bits) *
            page_mod.SEGMENT_WORDS_PER_TEXEL;
        const max_band_words = @as(u64, page_mod.BAND_TEX_WIDTH) *
            (@as(u64, std.math.maxInt(u16)) + 1) * 2;
        if (options.max_pages == 0 or
            options.max_pages > render_abi.max_atlas_pages or
            options.curve_words_per_page == 0 or
            options.curve_words_per_page % page_mod.MIN_CURVE_SEGMENT_WORDS != 0 or
            options.curve_words_per_page > max_curve_words or
            options.band_words_per_page == 0 or
            options.band_words_per_page % 2 != 0 or
            options.band_words_per_page > max_band_words)
        {
            return error.InvalidOptions;
        }

        const pool = try allocator.create(Pool);
        errdefer allocator.destroy(pool);

        const pages = try allocator.alloc(?*AtlasPage, options.max_pages);
        errdefer allocator.free(pages);
        @memset(pages, null);

        const stack = try allocator.alloc(u16, options.max_pages);
        errdefer allocator.free(stack);

        var page_index: u32 = 0;
        while (page_index < options.max_pages) : (page_index += 1) {
            // Free pages sit at the bottom of the stack in order; allocation
            // pops from the top, so the lowest page_index goes out first.
            stack[options.max_pages - 1 - page_index] = @intCast(page_index);
        }

        pool.* = .{
            .allocator = allocator,
            .options = options,
            .pages = pages,
            .free_stack = stack,
            .free_count = options.max_pages,
        };
        return pool;
    }

    fn deinit(self: *Pool) void {
        for (self.pages) |maybe_page| {
            const p = maybe_page orelse continue;
            std.debug.assert(page_mod.isFree(p));
            page_mod.deinit(p);
        }
        self.allocator.free(self.pages);
        self.allocator.free(self.free_stack);
        const a = self.allocator;
        a.destroy(self);
    }

    fn nextIdentity(counter: *std.atomic.Value(u64)) PagePool.IdentityError!u64 {
        while (true) {
            const id = counter.load(.monotonic);
            // Zero is reserved and max cannot be incremented without wrap.
            if (id == 0 or id == std.math.maxInt(u64)) return error.IdentityExhausted;
            if (counter.cmpxchgWeak(id, id + 1, .monotonic, .monotonic) == null) return id;
        }
    }

    /// Mint an identity that is unique for this pool's lifetime.
    fn nextAtlasSnapshotId(self: *Pool) PagePool.IdentityError!u64 {
        return nextIdentity(&self.next_atlas_snapshot_id);
    }

    /// Mint a nonzero identity for one upload planner/cache. Binding-local
    /// generations are meaningful only together with this source identity.
    fn nextBindingSourceId(self: *Pool) PagePool.IdentityError!u64 {
        return nextIdentity(&self.next_binding_source_id);
    }

    /// Pull a fresh page off the free list. Caller takes one ref (refcount
    /// transitions from 0 to 1). Returns `error.OutOfLayers` if the pool is
    /// exhausted; callers should preserve compaction headroom or recover by
    /// rebuilding the pool at a larger capacity.
    fn acquire(self: *Pool) PagePool.AcquireError!*AtlasPage {
        self.mutex.lock();
        if (self.free_count == 0) {
            self.mutex.unlock();
            return error.OutOfLayers;
        }
        self.free_count -= 1;
        const page_index = self.free_stack[self.free_count];
        const existing = self.pages[page_index];
        self.mutex.unlock();

        var page = existing;
        if (existing == null) {
            self.allocation_lock.lock();
            defer self.allocation_lock.unlock();
            page = page_mod.init(
                self.allocator,
                page_index,
                self.options.curve_words_per_page,
                self.options.band_words_per_page,
            ) catch |err| {
                self.mutex.lock();
                self.free_stack[self.free_count] = page_index;
                self.free_count += 1;
                self.mutex.unlock();
                return err;
            };
            self.mutex.lock();
            std.debug.assert(self.pages[page_index] == null);
            self.pages[page_index] = page;
            self.mutex.unlock();
        }
        page_mod.activate(page.?);
        return page.?;
    }

    /// Decrement a page's refcount; on transition to zero, recycle it back
    /// to the free list. Safe to call any number of times for releases that
    /// were retained earlier by an atlas snapshot or `acquire`.
    fn release(self: *Pool, page: *AtlasPage) void {
        if (!page_mod.release(page)) return;
        // refcount hit zero: recycle.
        page_mod.recycle(page);
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.assert(self.free_count < self.pages.len);
        self.free_stack[self.free_count] = page_mod.pageIndex(page);
        self.free_count += 1;
    }

    fn stats(self: *Pool) StatsType {
        self.mutex.lock();
        defer self.mutex.unlock();

        var curve_used: u64 = 0;
        var band_used: u64 = 0;
        var pages_allocated: u32 = 0;
        for (self.pages) |maybe_page| {
            const p = maybe_page orelse continue;
            pages_allocated += 1;
            const published = page_mod.publishedWords(p);
            curve_used += @as(u64, published.curve) * @sizeOf(page_mod.Word);
            band_used += @as(u64, published.band) * @sizeOf(page_mod.Word);
        }
        const pages_total: u32 = @intCast(self.pages.len);
        const pages_free = self.free_count;
        return .{
            .pages_total = pages_total,
            .pages_allocated = pages_allocated,
            .pages_in_use = pages_total - pages_free,
            .pages_free = pages_free,
            .curve_bytes_total = @as(u64, pages_total) * @as(u64, self.options.curve_words_per_page) * @sizeOf(page_mod.Word),
            .curve_bytes_allocated = @as(u64, pages_allocated) * @as(u64, self.options.curve_words_per_page) * @sizeOf(page_mod.Word),
            .curve_bytes_used = curve_used,
            .band_bytes_total = @as(u64, pages_total) * @as(u64, self.options.band_words_per_page) * @sizeOf(page_mod.Word),
            .band_bytes_allocated = @as(u64, pages_allocated) * @as(u64, self.options.band_words_per_page) * @sizeOf(page_mod.Word),
            .band_bytes_used = band_used,
        };
    }
};

fn poolImpl(pool: *PagePool) *Pool {
    return @ptrCast(@alignCast(pool));
}

fn poolImplConst(pool: *const PagePool) *const Pool {
    return @ptrCast(@alignCast(pool));
}

/// Internal atlas allocation bridge. The module is not exported by the public
/// root, so these functions remain available to sibling implementation files
/// without becoming methods on the opaque caller handle.
pub fn acquire(pool: *PagePool) PagePool.AcquireError!*AtlasPage {
    return poolImpl(pool).acquire();
}

pub fn release(pool: *PagePool, page: *AtlasPage) void {
    poolImpl(pool).release(page);
}

pub fn nextAtlasSnapshotId(pool: *PagePool) PagePool.IdentityError!u64 {
    return poolImpl(pool).nextAtlasSnapshotId();
}

pub fn nextBindingSourceId(pool: *PagePool) PagePool.IdentityError!u64 {
    return poolImpl(pool).nextBindingSourceId();
}

pub fn ownsPage(pool: *const PagePool, page_index: u32, page: *const AtlasPage) bool {
    const impl = poolImplConst(pool);
    return page_index < impl.pages.len and impl.pages[page_index] == page;
}

test "pool acquire and release round-trip" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool.deinit();

    const a = try acquire(pool);
    const b = try acquire(pool);
    try std.testing.expect(a != b);
    try std.testing.expect(page_mod.pageIndex(a) != page_mod.pageIndex(b));
    try std.testing.expectEqual(@as(u32, 1), page_mod.refCount(a));

    release(pool, a);
    try std.testing.expectEqual(@as(u32, 0), page_mod.refCount(a));

    const c = try acquire(pool);
    // `a` was the most recently freed (LIFO) so it should come back first.
    try std.testing.expectEqual(page_mod.pageIndex(a), page_mod.pageIndex(c));

    release(pool, b);
    release(pool, c);
}

test "pool exhausts at capacity" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 16,
        .band_words_per_page = 8,
    });
    defer pool.deinit();

    const p0 = try acquire(pool);
    const p1 = try acquire(pool);
    try std.testing.expectError(error.OutOfLayers, acquire(pool));

    release(pool, p0);
    release(pool, p1);
}

test "lazy page allocation failure preserves free capacity" {
    // Pool initialization performs three allocations; fail the first page
    // allocation, then ensure the logical slot remains available.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 3 });
    var pool = try PagePool.init(failing.allocator(), .{
        .max_pages = 1,
        .curve_words_per_page = 16,
        .band_words_per_page = 8,
    });
    defer pool.deinit();

    try std.testing.expectError(error.OutOfMemory, acquire(pool));
    try std.testing.expectEqual(@as(u32, 1), pool.stats().pages_free);
    try std.testing.expectEqual(@as(u32, 0), pool.stats().pages_allocated);
}

test "pool rejects options that cannot be represented by the atlas ABI" {
    const allocator = std.testing.allocator;
    const valid = Options{
        .max_pages = 1,
        .curve_words_per_page = page_mod.CURVE_SEGMENT_WORDS,
        .band_words_per_page = 2,
    };

    var opts = valid;
    opts.max_pages = 0;
    try std.testing.expectError(error.InvalidOptions, PagePool.init(allocator, opts));

    opts = valid;
    opts.max_pages = render_abi.max_atlas_pages + 1;
    try std.testing.expectError(error.InvalidOptions, PagePool.init(allocator, opts));

    opts = valid;
    opts.curve_words_per_page -= 1;
    try std.testing.expectError(error.InvalidOptions, PagePool.init(allocator, opts));

    opts = valid;
    opts.band_words_per_page += 1;
    try std.testing.expectError(error.InvalidOptions, PagePool.init(allocator, opts));
}

test "pool mints distinct nonzero binding source identities" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = page_mod.CURVE_SEGMENT_WORDS,
        .band_words_per_page = 2,
    });
    defer pool.deinit();

    const a = try nextBindingSourceId(pool);
    const b = try nextBindingSourceId(pool);
    try std.testing.expect(a != 0);
    try std.testing.expect(b != 0);
    try std.testing.expect(a != b);
}

test "identity sources fail without wrapping their reserved value" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = page_mod.CURVE_SEGMENT_WORDS,
        .band_words_per_page = 2,
    });
    defer pool.deinit();

    poolImpl(pool).next_atlas_snapshot_id.store(std.math.maxInt(u64), .monotonic);
    try std.testing.expectError(error.IdentityExhausted, nextAtlasSnapshotId(pool));
    try std.testing.expectEqual(std.math.maxInt(u64), poolImpl(pool).next_atlas_snapshot_id.load(.monotonic));

    poolImpl(pool).next_binding_source_id.store(std.math.maxInt(u64), .monotonic);
    try std.testing.expectError(error.IdentityExhausted, nextBindingSourceId(pool));
    try std.testing.expectEqual(std.math.maxInt(u64), poolImpl(pool).next_binding_source_id.load(.monotonic));
}

test "release recycles on refcount transition to zero" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 16,
        .band_words_per_page = 8,
    });
    defer pool.deinit();

    const p = try acquire(pool);
    try page_mod.retain(p);
    page_mod.discard(p, page_mod.reserve(p, 4, 2).?);
    const g0 = page_mod.currentGeneration(p);

    release(pool, p); // still refcount 1
    try std.testing.expectEqual(@as(u32, 1), page_mod.refCount(p));
    try std.testing.expectError(error.OutOfLayers, acquire(pool));

    release(pool, p); // refcount 0 → recycled
    try std.testing.expectEqual(@as(u32, 0), page_mod.refCount(p));
    try std.testing.expect(page_mod.currentGeneration(p) != g0);
    try std.testing.expectEqual(page_mod.PublishedWords{ .curve = 0, .band = 0 }, page_mod.publishedWords(p));

    const reused = try acquire(pool);
    try std.testing.expectEqual(page_mod.pageIndex(p), page_mod.pageIndex(reused));
    release(pool, reused);
}

test "pool stats track used watermarks" {
    var pool = try PagePool.init(std.testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 32,
        .band_words_per_page = 16,
    });
    defer pool.deinit();

    const p = try acquire(pool);
    page_mod.discard(p, page_mod.reserve(p, 8, 4).?);

    const s = pool.stats();
    try std.testing.expectEqual(@as(u32, 2), s.pages_total);
    try std.testing.expectEqual(@as(u32, 1), s.pages_allocated);
    try std.testing.expectEqual(@as(u32, 1), s.pages_in_use);
    try std.testing.expectEqual(@as(u64, 32 * @sizeOf(page_mod.Word)), s.curve_bytes_allocated);
    try std.testing.expectEqual(@as(u64, 8 * @sizeOf(page_mod.Word)), s.curve_bytes_used);
    try std.testing.expectEqual(@as(u64, 16 * @sizeOf(page_mod.Word)), s.band_bytes_allocated);
    try std.testing.expectEqual(@as(u64, 4 * @sizeOf(page_mod.Word)), s.band_bytes_used);

    release(pool, p);
}
