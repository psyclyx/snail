//! Minimal caller-owned thread pool used by `CpuRenderer` to fan tile work
//! across cores without allocating in the draw path. The allocator is touched
//! exactly twice: once at `init` for the worker `[]std.Thread`, and once at
//! `deinit` to free it. `dispatch` is heap-free.
//!
//! Sync primitives are built directly on Linux futex (`std.os.linux.futex_4arg`)
//! to avoid pulling libc into snail's core: Zig 0.16 ships `Mutex` /
//! `Condition` only behind `std.Io`, which would re-introduce per-task
//! allocations on the draw path. Linux-only — adding other platforms means
//! adding the equivalent futex shims here.
//!
//! Not safe for concurrent dispatchers — at most one thread may call
//! `dispatch` at a time. This matches snail's "renderer is single-threaded
//! from the caller's perspective" rule; the pool fans work out internally and
//! joins before returning.

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

comptime {
    if (builtin.os.tag != .linux) {
        @compileError("snail.ThreadPool currently only supports Linux (futex-based sync). " ++
            "Other platforms can be added by porting the Mutex/Cond primitives in this file.");
    }
}

// Drepper's three-state futex mutex (0=unlocked, 1=locked-no-waiters,
// 2=locked-with-waiters). Self-initializes to `.unlocked`.
const Mutex = struct {
    state: u32 = 0,

    fn lock(m: *Mutex) void {
        // Uncontended fast path.
        if (@cmpxchgStrong(u32, &m.state, 0, 1, .acquire, .monotonic) == null) return;

        while (true) {
            // Decide whether to sleep. We sleep if state is 2 (already has
            // waiters) or if we successfully promote 1 -> 2. If a 1->2 attempt
            // observes 0, the lock is now free and we should re-try acquiring.
            const sleep = blk: {
                const observed = @atomicLoad(u32, &m.state, .monotonic);
                if (observed == 2) break :blk true;
                const cmp = @cmpxchgStrong(u32, &m.state, 1, 2, .monotonic, .monotonic);
                if (cmp == null) break :blk true; // we set 1 -> 2; now sleep on 2
                break :blk cmp.? != 0; // observed 1 or 2 just now
            };
            if (sleep) futexWait(&m.state, 2);

            // Acquire as 2 to keep the waiters mark; an over-conservative wake
            // is always correct, a missed wake is not.
            if (@cmpxchgStrong(u32, &m.state, 0, 2, .acquire, .monotonic) == null) return;
        }
    }

    fn unlock(m: *Mutex) void {
        // If state was 2, it had waiters; clear and wake one.
        const prev = @atomicRmw(u32, &m.state, .Sub, 1, .release);
        if (prev != 1) {
            @atomicStore(u32, &m.state, 0, .release);
            futexWake(&m.state, 1);
        }
    }
};

// Sequence-based condition variable. Waiters snapshot `seq` while holding the
// associated mutex, drop the mutex, then `futex_wait` on the snapshot — any
// signal that increments `seq` between snapshot and wait causes wait to return
// immediately, so signals are never lost.
const Cond = struct {
    seq: u32 = 0,

    // Atomically (release the mutex, queue on `seq`); on return, mutex is held.
    fn wait(c: *Cond, m: *Mutex) void {
        const seq = @atomicLoad(u32, &c.seq, .monotonic);
        m.unlock();
        futexWait(&c.seq, seq);
        m.lock();
    }

    // Bump the wakeup sequence. Caller MUST hold the associated mutex.
    fn prepareWake(c: *Cond) void {
        _ = @atomicRmw(u32, &c.seq, .Add, 1, .release);
    }

    // Wake up to `count` waiters. May be called outside the mutex; pair with
    // a prior `prepareWake` under the mutex so waiters' seq snapshots see the
    // increment.
    fn wake(c: *Cond, count: u32) void {
        futexWake(&c.seq, count);
    }
};

const FUTEX_WAIT_PRIVATE: linux.FUTEX_OP = .{ .cmd = .WAIT, .private = true };
const FUTEX_WAKE_PRIVATE: linux.FUTEX_OP = .{ .cmd = .WAKE, .private = true };

fn futexWait(addr: *const u32, expected: u32) void {
    // Spurious returns (EAGAIN, EINTR) are fine: every caller rechecks its
    // predicate in a loop after `futexWait` returns.
    _ = linux.futex_4arg(@ptrCast(addr), FUTEX_WAIT_PRIVATE, expected, null);
}

fn futexWake(addr: *const u32, count: u32) void {
    // The kernel reads `val` as a signed int; values > INT_MAX (e.g. our
    // `wakeAll` sentinel) would be observed as negative and return EINVAL.
    const clamped = @min(count, @as(u32, std.math.maxInt(i32)));
    _ = linux.futex_4arg(@ptrCast(addr), FUTEX_WAKE_PRIVATE, clamped, null);
}

const wake_all: u32 = std.math.maxInt(i32);

pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,

    mutex: Mutex,
    work_ready: Cond,
    work_done: Cond,
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
            .mutex = .{},
            .work_ready = .{},
            .work_done = .{},
            .shutdown = false,
            .job_ctx = null,
            .job_run = null,
            .job_total = 0,
            .job_next = 0,
            .job_active = 0,
        };

        var spawned: usize = 0;
        errdefer {
            self.mutex.lock();
            self.shutdown = true;
            self.work_ready.prepareWake();
            self.mutex.unlock();
            self.work_ready.wake(wake_all);
            for (threads_slice[0..spawned]) |t| t.join();
        }

        while (spawned < threads_slice.len) : (spawned += 1) {
            threads_slice[spawned] = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
    }

    pub fn deinit(self: *ThreadPool) void {
        self.mutex.lock();
        self.shutdown = true;
        self.work_ready.prepareWake();
        self.mutex.unlock();
        self.work_ready.wake(wake_all);
        for (self.threads) |t| t.join();
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

        self.mutex.lock();
        self.job_ctx = ctx;
        self.job_run = run;
        self.job_total = total;
        self.job_next = 0;
        self.job_active = 0;
        self.work_ready.prepareWake();
        self.mutex.unlock();
        self.work_ready.wake(wake_all);

        // The dispatching thread also pulls tasks. Once the queue is empty it
        // waits for in-flight workers to drain, then clears the job slot.
        while (true) {
            self.mutex.lock();
            if (self.job_next >= total) {
                while (self.job_active > 0) self.work_done.wait(&self.mutex);
                self.job_run = null;
                self.job_ctx = null;
                self.job_total = 0;
                self.mutex.unlock();
                return;
            }
            const idx = self.job_next;
            self.job_next += 1;
            self.job_active += 1;
            self.mutex.unlock();

            run(ctx, idx);

            self.mutex.lock();
            self.job_active -= 1;
            const last = self.job_active == 0 and self.job_next >= total;
            if (last) self.work_done.prepareWake();
            self.mutex.unlock();
            if (last) self.work_done.wake(wake_all);
        }
    }

    fn workerLoop(self: *ThreadPool) void {
        while (true) {
            self.mutex.lock();
            while (!self.shutdown and (self.job_run == null or self.job_next >= self.job_total)) {
                self.work_ready.wait(&self.mutex);
            }
            if (self.shutdown) {
                self.mutex.unlock();
                return;
            }
            const idx = self.job_next;
            self.job_next += 1;
            self.job_active += 1;
            const ctx = self.job_ctx.?;
            const run = self.job_run.?;
            self.mutex.unlock();

            run(ctx, idx);

            self.mutex.lock();
            self.job_active -= 1;
            const last = self.job_active == 0 and self.job_next >= self.job_total;
            if (last) self.work_done.prepareWake();
            self.mutex.unlock();
            if (last) self.work_done.wake(wake_all);
        }
    }
};
