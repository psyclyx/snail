//! Caller-owned portable thread pool used by `snail-raster.Renderer` to fan
//! tile work across cores. Allocation happens only during `init`/`deinit`;
//! `dispatch` is allocation-free.
//!
//! Synchronization uses Zig's portable futex-backed `std.Io.Mutex` and
//! `std.Io.Condition`, so the same worker implementation runs on Linux,
//! macOS, and Windows. Concurrent dispatchers are safely serialized.

const std = @import("std");

threadlocal var executing_pool: ?*ThreadPool = null;

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    io_impl: std.Io.Threaded,
    threads: []std.Thread,

    // Serializes callers before they can mutate the one active job slot.
    dispatch_mutex: std.Io.Mutex,
    mutex: std.Io.Mutex,
    work_ready: std.Io.Condition,
    work_done: std.Io.Condition,
    shutdown: bool,

    // Active job state. Mutated under `mutex`.
    job_ctx: ?*anyopaque,
    job_run: ?*const fn (*anyopaque, u32) void,
    job_total: u32,
    job_next: u32,
    job_active: u32,

    pub const InitOptions = struct {
        /// Worker count. `null` uses every logical core because the dispatching
        /// thread coordinates and waits rather than claiming work. `0` runs
        /// every task synchronously on the calling thread.
        threads: ?usize = null,
    };

    pub fn init(self: *ThreadPool, allocator: std.mem.Allocator, options: InitOptions) !void {
        const thread_count = options.threads orelse (std.Thread.getCpuCount() catch 1);
        const threads = try allocator.alloc(std.Thread, thread_count);
        errdefer allocator.free(threads);

        self.* = .{
            .allocator = allocator,
            // This static Io configuration still exposes Threaded's portable
            // uncancelable futex vtable, but creates no executor threads and
            // installs no process signal handlers.
            .io_impl = .init_single_threaded,
            .threads = threads,
            .dispatch_mutex = .init,
            .mutex = .init,
            .work_ready = .init,
            .work_done = .init,
            .shutdown = false,
            .job_ctx = null,
            .job_run = null,
            .job_total = 0,
            .job_next = 0,
            .job_active = 0,
        };

        var spawned: usize = 0;
        errdefer {
            self.lock();
            self.shutdown = true;
            self.unlock();
            self.work_ready.broadcast(self.io());
            for (threads[0..spawned]) |thread| thread.join();
        }
        while (spawned < threads.len) : (spawned += 1) {
            threads[spawned] = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
    }

    /// Stop the workers and release storage. The caller must first ensure no
    /// other thread is inside `dispatch`; destruction is not a dispatch fence.
    pub fn deinit(self: *ThreadPool) void {
        self.lock();
        self.shutdown = true;
        self.unlock();
        self.work_ready.broadcast(self.io());
        for (self.threads) |thread| thread.join();
        self.allocator.free(self.threads);
        self.* = undefined;
    }

    pub fn threadCount(self: *const ThreadPool) usize {
        return self.threads.len;
    }

    /// Run `run(ctx, i)` exactly once for every `i` in `[0, total)`. Blocks
    /// until all calls finish. With zero workers, executes synchronously.
    pub fn dispatch(
        self: *ThreadPool,
        total: u32,
        ctx: *anyopaque,
        run: *const fn (*anyopaque, u32) void,
    ) void {
        if (total == 0) return;
        // A worker callback may recursively submit to its own pool. Waiting
        // for the outer dispatch slot would deadlock, so execute that nested
        // work inline. Dispatch to a different pool keeps normal semantics.
        if (executing_pool == self) {
            var i: u32 = 0;
            while (i < total) : (i += 1) run(ctx, i);
            return;
        }
        self.dispatch_mutex.lockUncancelable(self.io());
        defer self.dispatch_mutex.unlock(self.io());
        if (self.threads.len == 0) {
            const previous = executing_pool;
            executing_pool = self;
            defer executing_pool = previous;
            var i: u32 = 0;
            while (i < total) : (i += 1) run(ctx, i);
            return;
        }

        self.lock();
        std.debug.assert(self.job_run == null);
        self.job_ctx = ctx;
        self.job_run = run;
        self.job_total = total;
        self.job_next = 0;
        self.job_active = 0;
        self.unlock();
        self.work_ready.broadcast(self.io());

        self.lock();
        while (self.job_next < total or self.job_active > 0) {
            self.work_done.waitUncancelable(self.io(), &self.mutex);
        }
        self.job_run = null;
        self.job_ctx = null;
        self.job_total = 0;
        self.unlock();
    }

    fn workerLoop(self: *ThreadPool) void {
        while (true) {
            self.lock();
            while (!self.shutdown and (self.job_run == null or self.job_next >= self.job_total)) {
                self.work_ready.waitUncancelable(self.io(), &self.mutex);
            }
            if (self.shutdown) {
                self.unlock();
                return;
            }

            const index = self.job_next;
            self.job_next += 1;
            self.job_active += 1;
            const ctx = self.job_ctx.?;
            const run = self.job_run.?;
            self.unlock();

            const previous = executing_pool;
            executing_pool = self;
            run(ctx, index);
            executing_pool = previous;

            self.lock();
            self.job_active -= 1;
            const finished = self.job_active == 0 and self.job_next >= self.job_total;
            self.unlock();
            if (finished) self.work_done.broadcast(self.io());
        }
    }

    inline fn io(self: *ThreadPool) std.Io {
        return self.io_impl.io();
    }

    inline fn lock(self: *ThreadPool) void {
        self.mutex.lockUncancelable(self.io());
    }

    inline fn unlock(self: *ThreadPool) void {
        self.mutex.unlock(self.io());
    }
};

test "thread pool dispatches each index exactly once" {
    var pool: ThreadPool = undefined;
    try pool.init(std.testing.allocator, .{ .threads = 2 });
    defer pool.deinit();
    try std.testing.expectEqual(@as(usize, 2), pool.threadCount());

    const Context = struct {
        hits: *[37]u8,

        fn run(opaque_ctx: *anyopaque, index: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            context.hits[index] += 1;
        }
    };
    var hits = [_]u8{0} ** 37;
    var context = Context{ .hits = &hits };
    pool.dispatch(hits.len, &context, Context.run);
    for (hits) |hit| try std.testing.expectEqual(@as(u8, 1), hit);
}

test "zero-worker pool dispatches synchronously" {
    var pool: ThreadPool = undefined;
    try pool.init(std.testing.allocator, .{ .threads = 0 });
    defer pool.deinit();

    const Context = struct {
        count: u32 = 0,

        fn run(opaque_ctx: *anyopaque, _: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            context.count += 1;
        }
    };
    var context = Context{};
    pool.dispatch(11, &context, Context.run);
    try std.testing.expectEqual(@as(u32, 11), context.count);
}

test "independent pools survive either lifecycle order" {
    var first: ThreadPool = undefined;
    try first.init(std.testing.allocator, .{ .threads = 1 });
    var second: ThreadPool = undefined;
    try second.init(std.testing.allocator, .{ .threads = 1 });
    defer second.deinit();

    const Context = struct {
        count: u32 = 0,

        fn run(opaque_ctx: *anyopaque, _: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            context.count += 1;
        }
    };
    var first_context = Context{};
    var second_context = Context{};
    first.dispatch(3, &first_context, Context.run);
    second.dispatch(5, &second_context, Context.run);
    first.deinit();

    // Destroying one pool must not tear down synchronization used by another.
    second.dispatch(7, &second_context, Context.run);
    try std.testing.expectEqual(@as(u32, 3), first_context.count);
    try std.testing.expectEqual(@as(u32, 12), second_context.count);
}

test "concurrent dispatchers are serialized without losing work" {
    var pool: ThreadPool = undefined;
    try pool.init(std.testing.allocator, .{ .threads = 2 });
    defer pool.deinit();

    const Context = struct {
        pool: *ThreadPool,
        hits: *[31]u8,

        fn run(opaque_ctx: *anyopaque, index: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            context.hits[index] = 1;
        }

        fn dispatch(context: *@This()) void {
            context.pool.dispatch(context.hits.len, context, run);
        }
    };
    var first_hits = [_]u8{0} ** 31;
    var second_hits = [_]u8{0} ** 31;
    var first = Context{ .pool = &pool, .hits = &first_hits };
    var second = Context{ .pool = &pool, .hits = &second_hits };
    const first_thread = try std.Thread.spawn(.{}, Context.dispatch, .{&first});
    const second_thread = try std.Thread.spawn(.{}, Context.dispatch, .{&second});
    first_thread.join();
    second_thread.join();
    for (first_hits) |hit| try std.testing.expectEqual(@as(u8, 1), hit);
    for (second_hits) |hit| try std.testing.expectEqual(@as(u8, 1), hit);
}

test "worker callbacks can recursively dispatch to the same pool" {
    var pool: ThreadPool = undefined;
    try pool.init(std.testing.allocator, .{ .threads = 2 });
    defer pool.deinit();

    const Context = struct {
        pool: *ThreadPool,
        inner_count: std.atomic.Value(u32) = .init(0),

        fn inner(opaque_ctx: *anyopaque, _: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            _ = context.inner_count.fetchAdd(1, .monotonic);
        }

        fn outer(opaque_ctx: *anyopaque, _: u32) void {
            const context: *@This() = @ptrCast(@alignCast(opaque_ctx));
            context.pool.dispatch(3, context, inner);
        }
    };
    var context = Context{ .pool = &pool };
    pool.dispatch(4, &context, Context.outer);
    try std.testing.expectEqual(@as(u32, 12), context.inner_count.load(.monotonic));
}
