//! Cross-backend driver for the interactive demo. Wraps each backend's
//! `Renderer` + `BackendCache` cache + new-API `emit`/`draw` glue into a
//! single tagged union so `main.zig` can cycle between backends with the
//! 'C' key without knowing each backend's idiom.
//!
//! CPU has three flavours that differ only in the thread-pool sizing:
//! `cpu` uses the default pool (one worker per logical core minus one),
//! `cpu_less_threaded` runs with a single worker, and `cpu_unthreaded`
//! has zero workers so dispatch runs every tile on the calling thread.
//! All three share the same `snail-raster` renderer and cache plumbing.

const std = @import("std");
const builtin = @import("builtin");
const snail = @import("snail");
const raster = @import("snail-raster");
const embed_gl = @import("embed_gl");
const presentation = @import("../platform/presentation.zig");
const wayland = @import("../platform/wayland.zig");
const demo_banner = @import("../scene/banner/root.zig");
const driver_common = @import("common.zig");

const gl_platform = @import("../platform/gl.zig");
const vulkan_platform = @import("../platform/vulkan/windowed.zig");
const embed_vulkan = @import("embed_vulkan");
const cpu_platform = @import("../platform/cpu.zig");
const gl = @import("support").gl;

pub const Kind = enum {
    vulkan,
    gl44,
    gl33,
    gles30,
    cpu,
    cpu_less_threaded,
    cpu_unthreaded,
};

pub fn defaultKind() Kind {
    return .vulkan;
}

pub fn nextKind(current: Kind) Kind {
    return switch (current) {
        .vulkan => .gl44,
        .gl44 => .gl33,
        .gl33 => .gles30,
        .gles30 => .cpu,
        .cpu => .cpu_less_threaded,
        .cpu_less_threaded => .cpu_unthreaded,
        .cpu_unthreaded => .vulkan,
    };
}

pub fn label(kind: Kind) []const u8 {
    return switch (kind) {
        .vulkan => "Vulkan",
        .gl44 => "GL 4.4",
        .gl33 => "GL 3.3",
        .gles30 => "OpenGL ES 3.0",
        .cpu => "CPU",
        .cpu_less_threaded => "CPU (1 worker)",
        .cpu_unthreaded => "CPU (unthreaded)",
    };
}

pub fn isCpuKind(kind: Kind) bool {
    return switch (kind) {
        .cpu, .cpu_less_threaded, .cpu_unthreaded => true,
        else => false,
    };
}

pub fn warnIfDebugCpu(kind: Kind) void {
    if (isCpuKind(kind) and builtin.mode == .Debug) {
        std.debug.print(
            "WARNING: Debug build. CPU rasterization is ~30x slower without `--release=fast`.\n",
            .{},
        );
    }
}

fn cpuThreadCount(kind: Kind) ?usize {
    return switch (kind) {
        .cpu => null, // default: one per logical core minus one
        .cpu_less_threaded => 1,
        .cpu_unthreaded => 0,
        else => unreachable,
    };
}

/// One draw call's worth of work. `atlases[i]` is the atlas backing
/// `pictures[i]`; all of a pass's pictures share a single `draw_state`
/// (one MVP, one surface, one raster config) and get composed into one
/// `backend.draw()` call.
///
/// The driver keeps per-pass binding state by position in the array,
/// so callers pass the same passes in the same order each frame. Set
/// `dirty=true` when any atlas in the pass added entries since the
/// last upload; the driver releases and re-issues that pass's
/// bindings.
pub const Pass = driver_common.Pass;

pub const MAX_PASSES = driver_common.MAX_PASSES;
pub const MAX_BINDINGS_PER_PASS = driver_common.MAX_BINDINGS_PER_PASS;

/// Per-frame stage timings (µs) for the CPU backend. GPU drivers report
/// zero for every field except `swap_us` (their per-stage cost lives on
/// the GPU timeline, not the CPU clock).
///
/// Stages in execution order:
///   clear → sync → emit → pass[0..N] → swap
/// `pass_us` is indexed 1:1 with the input passes; trailing entries stay
/// zero. The sum across all fields is the wall-clock the backend spent
/// inside `renderFrame`.
pub const FrameTimings = driver_common.FrameTimings;

const ScratchBuf = driver_common.ScratchBuf;

pub const Driver = union(Kind) {
    vulkan: VulkanDriver,
    gl44: Gl44Driver,
    gl33: Gl33Driver,
    gles30: Gles30Driver,
    cpu: CpuDriver,
    cpu_less_threaded: CpuDriver,
    cpu_unthreaded: CpuDriver,

    pub fn init(allocator: std.mem.Allocator, window: *wayland.Window, selected: Kind) !Driver {
        return switch (selected) {
            .vulkan => .{ .vulkan = try VulkanDriver.init(allocator, window) },
            .gl44 => .{ .gl44 = try Gl44Driver.init(allocator, window) },
            .gl33 => .{ .gl33 = try Gl33Driver.init(allocator, window) },
            .gles30 => .{ .gles30 = try Gles30Driver.init(allocator, window) },
            .cpu => .{ .cpu = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu)) },
            .cpu_less_threaded => .{ .cpu_less_threaded = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu_less_threaded)) },
            .cpu_unthreaded => .{ .cpu_unthreaded = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu_unthreaded)) },
        };
    }

    pub fn deinit(self: *Driver) void {
        switch (self.*) {
            inline else => |*d| d.deinit(),
        }
    }

    pub fn kind(self: *const Driver) Kind {
        return std.meta.activeTag(self.*);
    }

    pub fn backendName(self: *Driver) [:0]const u8 {
        return switch (self.*) {
            .vulkan => "Vulkan",
            .gl44 => |*d| d.renderer_state.state.backendName(),
            .gl33 => |*d| d.renderer_state.state.backendName(),
            .gles30 => |*d| d.renderer_state.state.backendName(),
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| d.renderer_state.backendName(),
        };
    }

    /// Wire the per-instance timing sink on the CPU renderer (no-op for GPU
    /// backends, which don't run the serial CPU instance loop).
    pub fn setInstanceProfile(self: *Driver, profile: ?*raster.InstanceProfileBuf) void {
        switch (self.*) {
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| d.renderer_state.instance_profile = profile,
            else => {},
        }
    }

    pub fn shouldClose(self: *Driver) bool {
        return switch (self.*) {
            .vulkan => vulkan_platform.shouldClose(),
            .gl44, .gl33, .gles30 => gl_platform.shouldClose(),
            .cpu, .cpu_less_threaded, .cpu_unthreaded => cpu_platform.shouldClose(),
        };
    }

    pub fn presentationInfo(self: *Driver) presentation.Info {
        return switch (self.*) {
            .vulkan => vulkan_platform.presentationInfo(),
            .gl44, .gl33, .gles30 => gl_platform.presentationInfo(),
            .cpu, .cpu_less_threaded, .cpu_unthreaded => cpu_platform.presentationInfo(),
        };
    }

    /// Per-frame stage timings (µs) from the most recent frame.
    /// CPU side of every backend: `clear / sync / emit / pass[] / swap`
    /// are measured by wrapping each stage in CPU clock samples. The
    /// meaning of each field differs by backend:
    ///   CPU       — `pass_us` is the rasterization work itself; `clear`
    ///               is the framebuffer fill; `swap` is just shm attach
    ///               + commit (the vsync wait is at the top of the loop).
    ///   Vulkan    — `clear` includes `vkWaitForFences` +
    ///               `vkAcquireNextImageKHR` (the real vsync-wait time
    ///               on this backend); `pass_us` is just CPU-side draw
    ///               command recording; `swap` is queue submit + present.
    ///   GL / GLES — `clear` is `glClear`; `pass_us` is command recording;
    ///               `swap` is `eglSwapBuffers`, which usually blocks
    ///               until the next vsync so the wait shows up here.
    /// Anything spent on the GPU timeline itself (actual rasterization)
    /// is not measured — that would require GPU timer queries, which we
    /// haven't wired up.
    pub fn lastFrameTimings(self: *Driver) FrameTimings {
        return switch (self.*) {
            inline else => |*d| d.last_timings,
        };
    }

    /// Render one frame as a sequence of passes. All passes share the
    /// surface size + clear color; each pass has its own DrawState
    /// (MVP, raster config) and its own (atlas, picture) pairs.
    /// Returns true if rendered, false if the frame was skipped
    /// (e.g. swapchain not ready).
    pub fn renderFrame(
        self: *Driver,
        allocator: std.mem.Allocator,
        passes: []const Pass,
        clear_srgb: [4]f32,
    ) !bool {
        std.debug.assert(passes.len > 0 and passes.len <= MAX_PASSES);
        switch (self.*) {
            inline else => |*d| return d.renderFrame(allocator, passes, clear_srgb),
        }
    }
};

// ── Utility ───────────────────────────────────────────────────────────────

const unitToU8 = driver_common.unitToU8;
const srgbToLinear = driver_common.srgbToLinear;
const clearColorForShader = driver_common.clearColorForShader;

const PassRecords = driver_common.PassRecords;
const PassState = driver_common.PassState;
const emitPasses = driver_common.emitPasses;
const syncPassBindings = driver_common.syncPassBindings;

// ── GL timer-query ring ───────────────────────────────────────────────────
//
// Wraps `GL_ARB_timer_query` (core in OpenGL 3.3+) so the GL driver
// path can report actual GPU rasterization time per pass instead of
// the CPU-side draw-record time. The driver queues up to 2-3 frames'
// worth of commands; reading a query's result before the GPU completes
// it would stall the CPU. To avoid the stall we keep a ring of 3 slots
// of begin/end queries and read each slot's results 3 frames later,
// after the GPU has long since retired them.
const GlTimer = struct {
    const RING: usize = 3;
    const SLOT_QUERIES: usize = MAX_PASSES * 2;
    const TOTAL_QUERIES: usize = SLOT_QUERIES * RING;

    queries: [TOTAL_QUERIES]gl.GLuint = .{0} ** TOTAL_QUERIES,
    /// Current ring slot — the one we're about to write into.
    slot: u32 = 0,
    /// `true` once a slot has been written to and its results are
    /// pending. Read & cleared before reuse.
    slot_pending: [RING]bool = .{false} ** RING,
    /// Most recent COMPLETED frame's per-pass µs.
    last_pass_us: [MAX_PASSES]f64 = .{0} ** MAX_PASSES,
    initialized: bool = false,

    fn ensureInit(self: *GlTimer) void {
        if (self.initialized) return;
        gl.glGenQueries(TOTAL_QUERIES, &self.queries);
        self.initialized = true;
    }

    fn deinit(self: *GlTimer) void {
        if (!self.initialized) return;
        gl.glDeleteQueries(TOTAL_QUERIES, &self.queries);
        self.initialized = false;
    }

    inline fn slotBase(slot: u32) usize {
        return @as(usize, slot) * SLOT_QUERIES;
    }

    /// Call at the START of each frame. If `slot` has pending results
    /// from RING frames ago, drain them into `last_pass_us`.
    fn beginFrame(self: *GlTimer) void {
        if (!self.initialized) return;
        if (!self.slot_pending[self.slot]) return;
        const base = slotBase(self.slot);
        for (0..MAX_PASSES) |i| {
            const q_begin = self.queries[base + i * 2];
            const q_end = self.queries[base + i * 2 + 1];
            var begin_ns: gl.GLuint64 = 0;
            var end_ns: gl.GLuint64 = 0;
            gl.glGetQueryObjectui64v(q_begin, gl.GL_QUERY_RESULT, &begin_ns);
            gl.glGetQueryObjectui64v(q_end, gl.GL_QUERY_RESULT, &end_ns);
            self.last_pass_us[i] = if (end_ns > begin_ns)
                @as(f64, @floatFromInt(end_ns - begin_ns)) / 1000.0
            else
                0;
        }
        self.slot_pending[self.slot] = false;
    }

    fn beginPass(self: *GlTimer, pass_index: usize) void {
        if (!self.initialized or pass_index >= MAX_PASSES) return;
        const base = slotBase(self.slot);
        gl.glQueryCounter(self.queries[base + pass_index * 2], gl.GL_TIMESTAMP);
    }

    fn endPass(self: *GlTimer, pass_index: usize) void {
        if (!self.initialized or pass_index >= MAX_PASSES) return;
        const base = slotBase(self.slot);
        gl.glQueryCounter(self.queries[base + pass_index * 2 + 1], gl.GL_TIMESTAMP);
        self.slot_pending[self.slot] = true;
    }

    fn endFrame(self: *GlTimer) void {
        self.slot = (self.slot + 1) % @as(u32, @intCast(RING));
    }
};

// ── Vulkan ────────────────────────────────────────────────────────────────

const VulkanDriver = struct {
    // Generous vertex ring slot; the interactive scenes are well under this.
    const SLOT_BYTES: usize = 8 * 1024 * 1024;

    allocator: std.mem.Allocator,
    ctx: embed_vulkan.VulkanContext,
    layout: embed_vulkan.VulkanResourceLayout,
    transfer_pool: embed_vulkan.vk.VkCommandPool,
    caller: embed_vulkan.Renderer,
    cache: ?embed_vulkan.VulkanBackendCache = null,
    cache_pool: ?*const anyopaque = null, // PagePool pointer to detect content swap
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    last_timings: FrameTimings = .{},

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !VulkanDriver {
        const ctx = try vulkan_platform.initForWindow(window, false);
        errdefer vulkan_platform.deinit();
        // Standalone embeddable setup — resource layout + transfer pool + the
        // reference caller renderer. No all-in-one VulkanRenderer.
        var layout: embed_vulkan.VulkanResourceLayout = undefined;
        try layout.init(ctx);
        errdefer layout.deinit();
        const transfer_pool = try embed_vulkan.createTransferPool(ctx);
        errdefer embed_vulkan.vk.vkDestroyCommandPool(ctx.device, transfer_pool, null);
        const caller = try embed_vulkan.Renderer.init(ctx, layout.desc_set_layout, SLOT_BYTES, vulkan_platform.MAX_FRAMES_IN_FLIGHT, false);
        return .{
            .allocator = allocator,
            .ctx = ctx,
            .layout = layout,
            .transfer_pool = transfer_pool,
            .caller = caller,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *VulkanDriver) void {
        if (self.cache) |*c| c.deinit();
        self.caller.deinit();
        embed_vulkan.vk.vkDestroyCommandPool(self.ctx.device, self.transfer_pool, null);
        self.layout.deinit();
        self.scratch.deinit();
        vulkan_platform.deinit();
    }

    fn renderFrame(
        self: *VulkanDriver,
        allocator: std.mem.Allocator,
        passes: []const Pass,
        clear_srgb: [4]f32,
    ) !bool {
        self.last_timings = .{};
        const pool = passes[0].atlases[0].pool.?;
        const pool_ptr: *const anyopaque = @ptrCast(pool);
        var cache_fresh = false;
        if (self.cache_pool != pool_ptr) {
            if (self.cache) |*c| c.deinit();
            self.cache = try embed_vulkan.VulkanBackendCache.init(self.allocator, pool, embed_vulkan.cachePipelineShape(self.ctx, &self.layout, self.transfer_pool), .{
                .max_bindings = 16,
                .layer_info_height = 64,
                .max_images = 8,
                .max_image_width = 256,
                .max_image_height = 256,
            });
            self.cache_pool = pool_ptr;
            for (self.pass_states[0..]) |*ps| ps.initialized = false;
            cache_fresh = true;
        }

        const sync_t0 = wayland.getTime();
        try syncPassBindings(embed_vulkan.VulkanBackendCache, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);
        self.last_timings.sync_us = (wayland.getTime() - sync_t0) * 1_000_000.0;

        var records_buf: [MAX_PASSES]PassRecords = undefined;
        const emit_t0 = wayland.getTime();
        try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);
        self.last_timings.emit_us = (wayland.getTime() - emit_t0) * 1_000_000.0;

        const surface = passes[0].draw_state.surface;
        const clear = clearColorForShader(clear_srgb, surface.encoding);
        // beginFrame's body is dominated by `vkWaitForFences` +
        // `vkAcquireNextImageKHR` — i.e. the actual vsync-wait time on
        // this backend. Lumping it into `clear_us` means the HUD's
        // "clear" column shows the right number for Vulkan (it'll be
        // the dominant time on a vsync-bound frame), instead of pretending
        // there's no wait happening at all.
        const clear_t0 = wayland.getTime();
        const platform_cmd = vulkan_platform.beginFrame(clear) orelse {
            self.last_timings.clear_us = (wayland.getTime() - clear_t0) * 1_000_000.0;
            return false;
        };
        self.last_timings.clear_us = (wayland.getTime() - clear_t0) * 1_000_000.0;

        const cmd: embed_vulkan.vk.VkCommandBuffer = @ptrCast(platform_cmd);
        self.caller.beginFrame(vulkan_platform.currentFrameIndex());
        const desc_set = self.cache.?.descriptorSet();

        for (passes, records_buf[0..passes.len], 0..) |pass, rec, i| {
            // CPU-side draw command recording. Issue GPU timestamps
            // around it; the actual GPU rasterization time gets
            // attributed to `last_timings.pass_us` once the platform
            // reads the timestamp results (= MAX_FRAMES_IN_FLIGHT
            // frames later, when this slot is reused).
            vulkan_platform.beginPassTimestamp(platform_cmd, @intCast(i));
            self.caller.render(cmd, desc_set, pass.draw_state, rec.words, rec.segs);
            vulkan_platform.endPassTimestamp(platform_cmd, @intCast(i));
        }

        const swap_t0 = wayland.getTime();
        vulkan_platform.endFrame();
        self.last_timings.swap_us = (wayland.getTime() - swap_t0) * 1_000_000.0;

        // Replace per-pass times with the GPU-side measurements from
        // the slot we just reused. These are MAX_FRAMES_IN_FLIGHT
        // frames behind real time but reflect actual GPU rasterization
        // cost, not CPU command-record time.
        var gpu_pass_us: [@import("../platform/vulkan/windowed.zig").MAX_TIMED_PASSES]f64 = undefined;
        vulkan_platform.lastGpuPassUs(&gpu_pass_us);
        for (0..@min(passes.len, gpu_pass_us.len)) |i| {
            self.last_timings.pass_us[i] = gpu_pass_us[i];
        }
        return true;
    }
};

// ── GL 4.4 / 3.3 / GLES30 ─────────────────────────────────────────────────

const Gl44Driver = struct {
    allocator: std.mem.Allocator,
    renderer_state: embed_gl.Gl44Renderer,
    cache: ?embed_gl.Gl44BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    last_timings: FrameTimings = .{},
    gl_timer: GlTimer = .{},

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl44Driver {
        try gl_platform.initForWindow(window, .gl44, 0);
        errdefer gl_platform.deinit();
        var renderer_state = try embed_gl.Gl44Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *Gl44Driver) void {
        self.gl_timer.deinit();
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderFrame(self: *Gl44Driver, allocator: std.mem.Allocator, passes: []const Pass, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, embed_gl.Gl44BackendCache, allocator, passes, clear_srgb, &self.last_timings);
    }
};

const Gl33Driver = struct {
    allocator: std.mem.Allocator,
    renderer_state: embed_gl.Gl33Renderer,
    cache: ?embed_gl.Gl33BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    last_timings: FrameTimings = .{},
    gl_timer: GlTimer = .{},

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl33Driver {
        try gl_platform.initForWindow(window, .gl33, 0);
        errdefer gl_platform.deinit();
        var renderer_state = try embed_gl.Gl33Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *Gl33Driver) void {
        self.gl_timer.deinit();
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderFrame(self: *Gl33Driver, allocator: std.mem.Allocator, passes: []const Pass, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, embed_gl.Gl33BackendCache, allocator, passes, clear_srgb, &self.last_timings);
    }
};

const Gles30Driver = struct {
    allocator: std.mem.Allocator,
    renderer_state: embed_gl.Gles30Renderer,
    cache: ?embed_gl.Gles30BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    last_timings: FrameTimings = .{},

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gles30Driver {
        try gl_platform.initForWindow(window, .gles30, 0);
        errdefer gl_platform.deinit();
        var renderer_state = try embed_gl.Gles30Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *Gles30Driver) void {
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderFrame(self: *Gles30Driver, allocator: std.mem.Allocator, passes: []const Pass, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, embed_gl.Gles30BackendCache, allocator, passes, clear_srgb, &self.last_timings);
    }
};

fn glRender(
    comptime Self: type,
    self: *Self,
    comptime CacheType: type,
    allocator: std.mem.Allocator,
    passes: []const Pass,
    clear_srgb: [4]f32,
    timings: *FrameTimings,
) !bool {
    timings.* = .{};
    // When the driver carries a `gl_timer` (GL 3.3 / 4.4 — GLES30
    // skipped because `GL_EXT_disjoke_timer_query` isn't universal),
    // pass times come from GPU timestamps; otherwise we fall back to
    // CPU-side draw-record time.
    const has_timer = comptime @hasField(Self, "gl_timer");
    if (has_timer) {
        self.gl_timer.ensureInit();
        self.gl_timer.beginFrame();
    }
    // All passes draw to the same surface and share the PagePool (each
    // pass's atlases come from the same pool). Pull the pool off the
    // first pass for cache pinning.
    const pool = passes[0].atlases[0].pool.?;
    const pool_ptr: *const anyopaque = @ptrCast(pool);
    var cache_fresh = false;
    if (self.cache_pool != pool_ptr) {
        if (self.cache) |*c| c.deinit();
        self.cache = try CacheType.init(self.allocator, pool, .{
            .max_bindings = 16,
            .layer_info_height = 64,
            .max_images = 8,
            .max_image_width = 256,
            .max_image_height = 256,
        });
        self.cache_pool = pool_ptr;
        for (self.pass_states[0..]) |*ps| ps.initialized = false;
        cache_fresh = true;
    }

    const sync_t0 = wayland.getTime();
    try syncPassBindings(CacheType, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);
    timings.sync_us = (wayland.getTime() - sync_t0) * 1_000_000.0;

    var records_buf: [MAX_PASSES]PassRecords = undefined;
    const emit_t0 = wayland.getTime();
    try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);
    timings.emit_us = (wayland.getTime() - emit_t0) * 1_000_000.0;

    // Surface dims are uniform across passes (one window).
    const surface = passes[0].draw_state.surface;
    gl.glViewport(0, 0, @intFromFloat(surface.pixel_width), @intFromFloat(surface.pixel_height));

    const clear_t0 = wayland.getTime();
    var resolve_restore: ?@TypeOf(try self.renderer_state.state.beginLinearResolve(surface, .{
        .backdrop = .{ .clear = clear_srgb },
        .region = .full_target,
        .intermediate_format = .rgba16f,
    })) = null;
    if (surface.supportsLinearResolve()) {
        // Driver gave us a linear default framebuffer (e.g. NVIDIA's GLES on
        // Wayland silently downgrades EGL_GL_COLORSPACE_SRGB_KHR). Render
        // into a linear fp16 intermediate so blending is linear-correct, then
        // let endLinearResolve encode-pass it into the default framebuffer.
        resolve_restore = try self.renderer_state.state.beginLinearResolve(surface, .{
            .backdrop = .{ .clear = clear_srgb },
            .region = .full_target,
            .intermediate_format = .rgba16f,
        });
    } else {
        const clear = clearColorForShader(clear_srgb, surface.encoding);
        gl_platform.clear(clear[0], clear[1], clear[2], clear[3]);
    }
    timings.clear_us = (wayland.getTime() - clear_t0) * 1_000_000.0;

    errdefer if (resolve_restore) |r| self.renderer_state.state.endLinearResolve(r);
    self.renderer_state.state.beginDraw();
    for (passes, records_buf[0..passes.len], 0..) |pass, rec, i| {
        if (has_timer) self.gl_timer.beginPass(i);
        const t0 = wayland.getTime();
        try self.renderer_state.state.draw(allocator, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?});
        timings.pass_us[i] = (wayland.getTime() - t0) * 1_000_000.0;
        if (has_timer) self.gl_timer.endPass(i);
    }
    if (resolve_restore) |r| self.renderer_state.state.endLinearResolve(r);

    // eglSwapBuffers normally blocks until the next vsync (interval=1),
    // so on GL/GLES this is where the vsync-wait time accumulates.
    const swap_t0 = wayland.getTime();
    gl_platform.swapBuffers();
    timings.swap_us = (wayland.getTime() - swap_t0) * 1_000_000.0;

    if (has_timer) {
        self.gl_timer.endFrame();
        // Overwrite the CPU-side pass times with the GPU timestamps
        // from RING frames ago. These reflect actual rasterization
        // cost on the GPU; the CPU-side fallback above (now masked)
        // would only have shown command-record time.
        for (0..@min(passes.len, MAX_PASSES)) |i| {
            timings.pass_us[i] = self.gl_timer.last_pass_us[i];
        }
    }
    return true;
}

// ── CPU ───────────────────────────────────────────────────────────────────

const CpuDriver = struct {
    allocator: std.mem.Allocator,
    renderer_state: raster.Renderer,
    pool: ?*raster.ThreadPool = null,
    cache: ?raster.BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    buf_width: u32 = 0,
    buf_height: u32 = 0,
    /// Per-stage µs from the most recent frame. See `FrameTimings`.
    last_timings: FrameTimings = .{},

    fn init(allocator: std.mem.Allocator, window: *wayland.Window, thread_count: ?usize) !CpuDriver {
        try cpu_platform.initForWindow(window);
        errdefer cpu_platform.deinit();
        const px = cpu_platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = cpu_platform.getBufferSize();
        const renderer_state = raster.Renderer.init(px, bsz[0], bsz[1], bsz[0] * 4);

        const pool_ptr = try allocator.create(raster.ThreadPool);
        errdefer allocator.destroy(pool_ptr);
        try pool_ptr.init(allocator, .{ .threads = thread_count });
        errdefer pool_ptr.deinit();

        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .pool = pool_ptr,
            .scratch = ScratchBuf.init(allocator),
            .buf_width = bsz[0],
            .buf_height = bsz[1],
        };
    }

    fn deinit(self: *CpuDriver) void {
        if (self.pool) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        cpu_platform.deinit();
    }

    fn backendName(_: *const CpuDriver) [:0]const u8 {
        return "CPU";
    }

    fn renderFrame(
        self: *CpuDriver,
        allocator: std.mem.Allocator,
        passes: []const Pass,
        clear_srgb: [4]f32,
    ) !bool {
        self.last_timings = .{};

        // Acquire the next shm buffer up front. The CPU renderer
        // rasterizes directly into the compositor's buffer (ABGR8888 in
        // memory matches what raster.Renderer writes); `swapBuffers` then
        // just attaches it with no per-pixel copy. `beginFrame` blocks
        // dispatching Wayland events when both buffers are still busy.
        const fb_ptr = cpu_platform.beginFrame() orelse return false;
        const bsz = cpu_platform.getBufferSize();
        // Always point the renderer at this frame's buffer — the shm
        // buffer rotates between the two presentation slots, so the
        // pointer changes most frames even when size doesn't.
        self.buf_width = bsz[0];
        self.buf_height = bsz[1];
        self.renderer_state.reinitBuffer(fb_ptr, bsz[0], bsz[1], bsz[0] * 4);

        // Clear the framebuffer in the storage encoding (shared by all passes).
        // Splat the RGBA bytes into a single u32 word and `@memset` it across
        // the whole buffer — much faster than a byte-at-a-time row/col loop,
        // and lets the kernel page-fault cold shm-buffer pages in bulk
        // instead of taking a per-page TLB miss on each store. The shm mmap
        // is page-aligned, so the `alignCast` is safe.
        const surface = passes[0].draw_state.surface;
        const clear_t0 = wayland.getTime();
        {
            const stored = switch (surface.encoding.stored_pixels) {
                .linear => [4]f32{ srgbToLinear(clear_srgb[0]), srgbToLinear(clear_srgb[1]), srgbToLinear(clear_srgb[2]), clear_srgb[3] },
                .srgb => clear_srgb,
            };
            const r: u32 = unitToU8(stored[0]);
            const g: u32 = unitToU8(stored[1]);
            const b: u32 = unitToU8(stored[2]);
            const a: u32 = unitToU8(stored[3]);
            // Host is little-endian: byte 0 = R sits in the u32's low byte,
            // matching the ABGR8888 wl_shm format we render straight into.
            const word: u32 = r | (g << 8) | (b << 16) | (a << 24);
            const px_u32: [*]u32 = @ptrCast(@alignCast(fb_ptr));
            @memset(px_u32[0 .. @as(usize, bsz[0]) * bsz[1]], word);
        }
        self.last_timings.clear_us = (wayland.getTime() - clear_t0) * 1_000_000.0;

        const pool = passes[0].atlases[0].pool.?;
        const pool_ptr: *const anyopaque = @ptrCast(pool);
        var cache_fresh = false;
        if (self.cache_pool != pool_ptr) {
            if (self.cache) |*c| c.deinit();
            self.cache = try raster.BackendCache.init(self.allocator, pool, .{
                .max_bindings = 16,
                .layer_info_height = 64,
                .max_images = 8,
            });
            self.cache_pool = pool_ptr;
            for (self.pass_states[0..]) |*ps| ps.initialized = false;
            cache_fresh = true;
        }

        const sync_t0 = wayland.getTime();
        try syncPassBindings(raster.BackendCache, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);
        self.last_timings.sync_us = (wayland.getTime() - sync_t0) * 1_000_000.0;

        var records_buf: [MAX_PASSES]PassRecords = undefined;
        const emit_t0 = wayland.getTime();
        try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);
        self.last_timings.emit_us = (wayland.getTime() - emit_t0) * 1_000_000.0;

        for (passes, records_buf[0..passes.len], 0..) |pass, rec, i| {
            const dispatch_pool: ?*raster.ThreadPool = if (pass.cpu_parallel) self.pool else null;
            const t0 = wayland.getTime();
            try raster.draw(&self.renderer_state, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?}, dispatch_pool);
            self.last_timings.pass_us[i] = (wayland.getTime() - t0) * 1_000_000.0;
        }

        const swap_t0 = wayland.getTime();
        cpu_platform.swapBuffers();
        self.last_timings.swap_us = (wayland.getTime() - swap_t0) * 1_000_000.0;
        return true;
    }
};
