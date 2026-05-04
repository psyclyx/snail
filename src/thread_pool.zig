//! Minimal caller-owned thread pool used by `CpuRenderer` to fan tile work
//! across cores without allocating in the draw path. The allocator is touched
//! exactly twice: once at `init` for the worker `[]std.Thread`, and once at
//! `deinit` to free it. `dispatch` is heap-free.
//!
//! Built on libc pthread mutex + condvar because Zig 0.16 only ships blocking
//! sync behind `std.Io`, which would re-introduce per-task allocations. snail
//! already links libc for FreeType / HarfBuzz, so the dependency is free.
//!
//! Not safe for concurrent dispatchers — at most one thread may call
//! `dispatch` at a time. This matches snail's "renderer is single-threaded
//! from the caller's perspective" rule; the pool fans work out internally and
//! joins before returning.

const std = @import("std");
const c = std.c;

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,

    mutex: c.pthread_mutex_t,
    work_ready: c.pthread_cond_t,
    work_done: c.pthread_cond_t,
    shutdown: bool,

    // Active job state. Mutated under `mutex`.
    job_ctx: ?*anyopaque,
    job_run: ?*const fn (*anyopaque, u32) void,
    job_total: u32,
    job_next: u32,
    job_active: u32,

    pub const InitOptions = struct {
        /// Worker thread count. `null` defaults to one per logical core minus
        /// one (the dispatching thread also runs tasks). `0` is allowed and
        /// makes `dispatch` run every task on the calling thread.
        threads: ?usize = null,
    };

    pub fn init(self: *ThreadPool, allocator: std.mem.Allocator, options: InitOptions) !void {
        const thread_count = options.threads orelse blk: {
            const n = std.Thread.getCpuCount() catch 1;
            break :blk if (n > 1) n - 1 else 0;
        };

        const threads_slice = try allocator.alloc(std.Thread, thread_count);
        errdefer allocator.free(threads_slice);

        self.* = .{
            .allocator = allocator,
            .threads = threads_slice,
            .mutex = c.PTHREAD_MUTEX_INITIALIZER,
            .work_ready = c.PTHREAD_COND_INITIALIZER,
            .work_done = c.PTHREAD_COND_INITIALIZER,
            .shutdown = false,
            .job_ctx = null,
            .job_run = null,
            .job_total = 0,
            .job_next = 0,
            .job_active = 0,
        };

        var spawned: usize = 0;
        errdefer {
            _ = c.pthread_mutex_lock(&self.mutex);
            self.shutdown = true;
            _ = c.pthread_cond_broadcast(&self.work_ready);
            _ = c.pthread_mutex_unlock(&self.mutex);
            for (threads_slice[0..spawned]) |t| t.join();
            _ = c.pthread_cond_destroy(&self.work_done);
            _ = c.pthread_cond_destroy(&self.work_ready);
            _ = c.pthread_mutex_destroy(&self.mutex);
        }

        while (spawned < threads_slice.len) : (spawned += 1) {
            threads_slice[spawned] = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
    }

    pub fn deinit(self: *ThreadPool) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        self.shutdown = true;
        _ = c.pthread_cond_broadcast(&self.work_ready);
        _ = c.pthread_mutex_unlock(&self.mutex);
        for (self.threads) |t| t.join();
        _ = c.pthread_cond_destroy(&self.work_done);
        _ = c.pthread_cond_destroy(&self.work_ready);
        _ = c.pthread_mutex_destroy(&self.mutex);
        self.allocator.free(self.threads);
        self.* = undefined;
    }

    pub fn threadCount(self: *const ThreadPool) usize {
        return self.threads.len;
    }

    /// Run `run(ctx, i)` for every `i` in `[0, total)`, distributing across
    /// workers and the calling thread. Blocks until all calls return.
    /// Allocation-free.
    pub fn dispatch(
        self: *ThreadPool,
        total: u32,
        ctx: *anyopaque,
        run: *const fn (*anyopaque, u32) void,
    ) void {
        if (total == 0) return;

        _ = c.pthread_mutex_lock(&self.mutex);
        self.job_ctx = ctx;
        self.job_run = run;
        self.job_total = total;
        self.job_next = 0;
        self.job_active = 0;
        _ = c.pthread_mutex_unlock(&self.mutex);
        _ = c.pthread_cond_broadcast(&self.work_ready);

        // The dispatching thread also pulls tasks. Once the queue is empty it
        // waits for in-flight workers to drain, then clears the job slot.
        while (true) {
            _ = c.pthread_mutex_lock(&self.mutex);
            if (self.job_next >= total) {
                while (self.job_active > 0) {
                    _ = c.pthread_cond_wait(&self.work_done, &self.mutex);
                }
                self.job_run = null;
                self.job_ctx = null;
                self.job_total = 0;
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            const idx = self.job_next;
            self.job_next += 1;
            self.job_active += 1;
            _ = c.pthread_mutex_unlock(&self.mutex);

            run(ctx, idx);

            _ = c.pthread_mutex_lock(&self.mutex);
            self.job_active -= 1;
            const last = self.job_active == 0 and self.job_next >= total;
            _ = c.pthread_mutex_unlock(&self.mutex);
            if (last) _ = c.pthread_cond_broadcast(&self.work_done);
        }
    }

    fn workerLoop(self: *ThreadPool) void {
        while (true) {
            _ = c.pthread_mutex_lock(&self.mutex);
            while (!self.shutdown and (self.job_run == null or self.job_next >= self.job_total)) {
                _ = c.pthread_cond_wait(&self.work_ready, &self.mutex);
            }
            if (self.shutdown) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            const idx = self.job_next;
            self.job_next += 1;
            self.job_active += 1;
            const ctx = self.job_ctx.?;
            const run = self.job_run.?;
            _ = c.pthread_mutex_unlock(&self.mutex);

            run(ctx, idx);

            _ = c.pthread_mutex_lock(&self.mutex);
            self.job_active -= 1;
            const last = self.job_active == 0 and self.job_next >= self.job_total;
            _ = c.pthread_mutex_unlock(&self.mutex);
            if (last) _ = c.pthread_cond_broadcast(&self.work_done);
        }
    }
};
