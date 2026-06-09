//! Cross-backend driver for the interactive demo. Wraps each backend's
//! `Renderer` + `BackendCache` cache + new-API `emit`/`draw` glue into a
//! single tagged union so `main.zig` can cycle between backends with the
//! 'C' key without knowing each backend's idiom.
//!
//! CPU has three flavours that differ only in the thread-pool sizing:
//! `cpu` uses the default pool (one worker per logical core minus one),
//! `cpu_less_threaded` runs with a single worker, and `cpu_unthreaded`
//! has zero workers so dispatch runs every tile on the calling thread.
//! All three share the same `CpuRenderer` + `CpuBackendCache` plumbing.

const std = @import("std");
const builtin = @import("builtin");
const snail = @import("snail");
const build_options = @import("build_options");
const presentation = @import("platform/presentation.zig");
const wayland = @import("platform/wayland.zig");
const demo_banner = @import("banner.zig");

const gl_platform = if ((build_options.enable_gl33 or build_options.enable_gl44 or build_options.enable_gles30)) @import("platform/gl.zig") else struct {};
const vulkan_platform = if (build_options.enable_vulkan) @import("platform/vulkan/windowed.zig") else struct {};
const cpu_platform = if (build_options.enable_cpu) @import("platform/cpu.zig") else struct {};
const gl = if ((build_options.enable_gl33 or build_options.enable_gl44 or build_options.enable_gles30)) @import("support").gl else struct {};

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
    if (comptime build_options.enable_vulkan) return .vulkan;
    if (comptime build_options.enable_gl44) return .gl44;
    if (comptime build_options.enable_gl33) return .gl33;
    if (comptime build_options.enable_gles30) return .gles30;
    if (comptime build_options.enable_cpu) return .cpu;
    @compileError("at least one demo backend must be enabled");
}

pub fn nextKind(current: Kind) Kind {
    // Try the next backend in the cycle; fall back to current if no other is enabled.
    const order = [_]Kind{ .vulkan, .gl44, .gl33, .gles30, .cpu, .cpu_less_threaded, .cpu_unthreaded };
    var seen_current = false;
    for (0..order.len * 2) |i| {
        const k = order[i % order.len];
        if (seen_current and kindEnabled(k)) return k;
        if (k == current) seen_current = true;
    }
    return current;
}

fn kindEnabled(k: Kind) bool {
    return switch (k) {
        .vulkan => build_options.enable_vulkan,
        .gl44 => build_options.enable_gl44,
        .gl33 => build_options.enable_gl33,
        .gles30 => build_options.enable_gles30,
        .cpu, .cpu_less_threaded, .cpu_unthreaded => build_options.enable_cpu,
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
pub const Pass = struct {
    atlases: []const *const snail.Atlas,
    pictures: []const *const snail.Picture,
    draw_state: snail.DrawState,
    dirty: bool,
    /// CPU-backend hint: when true, fan tile work across the driver's
    /// thread pool; when false, rasterize on the calling thread. Small
    /// overlays (HUD-style) should set this to false — the per-strip
    /// dispatch + barrier cost outweighs the rasterization work for
    /// tiny batches. GPU backends ignore this field.
    cpu_parallel: bool = true,
};

/// Cap on the number of passes a single frame can run. Picked so the
/// per-driver pass state lives in inline arrays (no heap), bumpable.
pub const MAX_PASSES: usize = 4;
/// Per-pass max binding count, mirroring max_bindings on the cache.
pub const MAX_BINDINGS_PER_PASS: usize = 4;

// Buffer for new-API draw words + segments. Owned by the driver, grown on
// demand each frame. Two segments are enough (paths + text picture).
const ScratchBuf = struct {
    allocator: std.mem.Allocator,
    words: []u32 = &.{},
    segs: []snail.DrawSegment = &.{},

    fn init(allocator: std.mem.Allocator) ScratchBuf {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ScratchBuf) void {
        if (self.words.len > 0) self.allocator.free(self.words);
        if (self.segs.len > 0) self.allocator.free(self.segs);
    }

    fn ensure(self: *ScratchBuf, word_count: usize, seg_count: usize) !void {
        if (self.words.len < word_count) {
            if (self.words.len > 0) self.allocator.free(self.words);
            self.words = try self.allocator.alloc(u32, word_count);
        }
        if (self.segs.len < seg_count) {
            if (self.segs.len > 0) self.allocator.free(self.segs);
            self.segs = try self.allocator.alloc(snail.DrawSegment, seg_count);
        }
    }
};

pub const Driver = union(Kind) {
    vulkan: if (build_options.enable_vulkan) VulkanDriver else void,
    gl44: if (build_options.enable_gl44) Gl44Driver else void,
    gl33: if (build_options.enable_gl33) Gl33Driver else void,
    gles30: if (build_options.enable_gles30) Gles30Driver else void,
    cpu: if (build_options.enable_cpu) CpuDriver else void,
    cpu_less_threaded: if (build_options.enable_cpu) CpuDriver else void,
    cpu_unthreaded: if (build_options.enable_cpu) CpuDriver else void,

    pub fn init(allocator: std.mem.Allocator, window: *wayland.Window, selected: Kind) !Driver {
        return switch (selected) {
            .vulkan => if (comptime build_options.enable_vulkan)
                .{ .vulkan = try VulkanDriver.init(allocator, window) }
            else
                unreachable,
            .gl44 => if (comptime build_options.enable_gl44)
                .{ .gl44 = try Gl44Driver.init(allocator, window) }
            else
                unreachable,
            .gl33 => if (comptime build_options.enable_gl33)
                .{ .gl33 = try Gl33Driver.init(allocator, window) }
            else
                unreachable,
            .gles30 => if (comptime build_options.enable_gles30)
                .{ .gles30 = try Gles30Driver.init(allocator, window) }
            else
                unreachable,
            .cpu => if (comptime build_options.enable_cpu)
                .{ .cpu = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu)) }
            else
                unreachable,
            .cpu_less_threaded => if (comptime build_options.enable_cpu)
                .{ .cpu_less_threaded = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu_less_threaded)) }
            else
                unreachable,
            .cpu_unthreaded => if (comptime build_options.enable_cpu)
                .{ .cpu_unthreaded = try CpuDriver.init(allocator, window, cpuThreadCount(.cpu_unthreaded)) }
            else
                unreachable,
        };
    }

    pub fn deinit(self: *Driver) void {
        switch (self.*) {
            .vulkan => |*d| if (comptime build_options.enable_vulkan) d.deinit() else unreachable,
            .gl44 => |*d| if (comptime build_options.enable_gl44) d.deinit() else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) d.deinit() else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) d.deinit() else unreachable,
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| if (comptime build_options.enable_cpu) d.deinit() else unreachable,
        }
    }

    pub fn kind(self: *const Driver) Kind {
        return std.meta.activeTag(self.*);
    }

    pub fn backendName(self: *Driver) [:0]const u8 {
        return switch (self.*) {
            .vulkan => |*d| if (comptime build_options.enable_vulkan) d.renderer_state.state.backendName() else unreachable,
            .gl44 => |*d| if (comptime build_options.enable_gl44) d.renderer_state.state.backendName() else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) d.renderer_state.state.backendName() else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) d.renderer_state.state.backendName() else unreachable,
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| if (comptime build_options.enable_cpu) d.renderer_state.backendName() else unreachable,
        };
    }

    pub fn shouldClose(self: *Driver) bool {
        return switch (self.*) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.shouldClose() else true,
            .gl44 => if (comptime build_options.enable_gl44) gl_platform.shouldClose() else true,
            .gl33 => if (comptime build_options.enable_gl33) gl_platform.shouldClose() else true,
            .gles30 => if (comptime build_options.enable_gles30) gl_platform.shouldClose() else true,
            .cpu, .cpu_less_threaded, .cpu_unthreaded => if (comptime build_options.enable_cpu) cpu_platform.shouldClose() else true,
        };
    }

    pub fn presentationInfo(self: *Driver) presentation.Info {
        return switch (self.*) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.presentationInfo() else .{},
            .gl44 => if (comptime build_options.enable_gl44) gl_platform.presentationInfo() else .{},
            .gl33 => if (comptime build_options.enable_gl33) gl_platform.presentationInfo() else .{},
            .gles30 => if (comptime build_options.enable_gles30) gl_platform.presentationInfo() else .{},
            .cpu, .cpu_less_threaded, .cpu_unthreaded => if (comptime build_options.enable_cpu) cpu_platform.presentationInfo() else .{},
        };
    }

    /// Per-pass draw-call timings (µs) from the most recent frame.
    /// Only the CPU backend populates these; GPU drivers report zeros
    /// because their per-draw cost lives on the GPU timeline, not the
    /// CPU clock.
    pub fn lastPassUs(self: *Driver) [MAX_PASSES]f64 {
        return switch (self.*) {
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| if (comptime build_options.enable_cpu)
                d.last_pass_us
            else
                [_]f64{0} ** MAX_PASSES,
            else => [_]f64{0} ** MAX_PASSES,
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
            .vulkan => |*d| if (comptime build_options.enable_vulkan) {
                return d.renderFrame(allocator, passes, clear_srgb);
            } else unreachable,
            .gl44 => |*d| if (comptime build_options.enable_gl44) {
                return d.renderFrame(allocator, passes, clear_srgb);
            } else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) {
                return d.renderFrame(allocator, passes, clear_srgb);
            } else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) {
                return d.renderFrame(allocator, passes, clear_srgb);
            } else unreachable,
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| if (comptime build_options.enable_cpu) {
                return d.renderFrame(allocator, passes, clear_srgb);
            } else unreachable,
        }
    }
};

// ── Utility ───────────────────────────────────────────────────────────────

fn unitToU8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255);
}

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn clearColorForShader(color_srgb: [4]f32, encoding: snail.TargetEncoding) [4]f32 {
    return switch (encoding.shaderOutputEncoding()) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}

/// Per-pass view onto the shared scratch buffer. `words` spans the
/// full emitted range across every pass (segment `words_offset` values
/// index it directly); `segs` is the pass's own sub-slice of segments.
/// Each draw call gets the same `words` and only its own `segs`.
const PassRecords = struct {
    words: []const u32,
    segs: []const snail.DrawSegment,
};

/// Driver-side per-pass binding state. Indexed by pass position; the
/// caller passes the same pass count and order each frame so the
/// indexes stay stable.
const PassState = struct {
    bindings: [MAX_BINDINGS_PER_PASS]snail.Binding = undefined,
    count: u8 = 0,
    initialized: bool = false,
};

/// Total words needed to emit every picture across every pass.
fn passesWordBudget(passes: []const Pass) usize {
    var total: usize = 0;
    for (passes) |pass| {
        for (pass.pictures) |picture| total += snail.emit.wordBudget(picture, 0);
    }
    return total;
}

/// Conservative seg budget: one segment per (pass × picture) plus one
/// of slack. emit's `mergeIfAdjacent` may produce fewer.
fn passesSegBudget(passes: []const Pass) usize {
    var total: usize = 1;
    for (passes) |pass| total += pass.pictures.len;
    return total;
}

/// Emit every pass into a contiguous scratch run. Every PassRecords
/// shares the same `words` slice (the full emitted extent) so segment
/// `words_offset` values keep their absolute meaning; each pass owns
/// only its segment sub-slice.
fn emitPasses(
    scratch: *ScratchBuf,
    passes: []const Pass,
    pass_states: []const PassState,
    out_records: []PassRecords,
) !void {
    std.debug.assert(passes.len == out_records.len);
    try scratch.ensure(passesWordBudget(passes), passesSegBudget(passes));
    var wlen: usize = 0;
    var slen: usize = 0;
    for (passes, pass_states, 0..) |pass, state, i| {
        std.debug.assert(state.initialized);
        std.debug.assert(state.count == pass.atlases.len);
        const seg_start = slen;
        for (pass.atlases, pass.pictures, state.bindings[0..state.count]) |atlas, picture, binding| {
            _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, binding, atlas, picture, .identity, .{ 1, 1, 1, 1 });
        }
        out_records[i] = .{
            // .words patched after the loop once `wlen` is final.
            .words = scratch.words[0..0],
            .segs = scratch.segs[seg_start..slen],
        };
    }
    const full_words = scratch.words[0..wlen];
    for (out_records) |*rec| rec.words = full_words;
}

/// Ensure each pass's bindings are live in `cache`. Releases stale
/// bindings on `pass.dirty`; reuses bindings otherwise.
fn syncPassBindings(
    comptime CacheType: type,
    cache: *CacheType,
    allocator: std.mem.Allocator,
    passes: []const Pass,
    pass_states: []PassState,
    cache_was_reinitialized: bool,
) !void {
    for (passes, pass_states) |pass, *state| {
        const needs_upload = cache_was_reinitialized or pass.dirty or !state.initialized;
        if (!needs_upload) continue;
        if (state.initialized and !cache_was_reinitialized) {
            for (state.bindings[0..state.count]) |b| cache.release(b);
        }
        state.initialized = false;
        std.debug.assert(pass.atlases.len <= MAX_BINDINGS_PER_PASS);
        try cache.upload(allocator, pass.atlases, state.bindings[0..pass.atlases.len]);
        state.count = @intCast(pass.atlases.len);
        state.initialized = true;
    }
}

// ── Vulkan ────────────────────────────────────────────────────────────────

const VulkanDriver = if (build_options.enable_vulkan) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.VulkanRenderer,
    cache: ?snail.VulkanBackendCache = null,
    cache_pool: ?*const anyopaque = null, // PagePool pointer to detect content swap
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !VulkanDriver {
        const ctx = try vulkan_platform.initForWindow(window);
        errdefer vulkan_platform.deinit();
        var renderer_state = try snail.VulkanRenderer.init(allocator, ctx);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *VulkanDriver) void {
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        vulkan_platform.deinit();
    }

    fn renderFrame(
        self: *VulkanDriver,
        allocator: std.mem.Allocator,
        passes: []const Pass,
        clear_srgb: [4]f32,
    ) !bool {
        const pool = passes[0].atlases[0].pool.?;
        const pool_ptr: *const anyopaque = @ptrCast(pool);
        var cache_fresh = false;
        if (self.cache_pool != pool_ptr) {
            if (self.cache) |*c| c.deinit();
            self.cache = try snail.VulkanBackendCache.init(self.allocator, pool, self.renderer_state.state.pipelineShape(), .{
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

        try syncPassBindings(snail.VulkanBackendCache, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);

        var records_buf: [MAX_PASSES]PassRecords = undefined;
        try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);

        const surface = passes[0].draw_state.surface;
        const clear = clearColorForShader(clear_srgb, surface.encoding);
        const cmd = vulkan_platform.beginFrame(clear) orelse return false;

        self.renderer_state.state.setCommandBuffer(cmd);
        defer self.renderer_state.state.clearCommandBuffer();
        self.renderer_state.state.setFrameSlot(vulkan_platform.currentFrameIndex());

        for (passes, records_buf[0..passes.len]) |pass, rec| {
            try self.renderer_state.state.draw(allocator, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?});
        }

        vulkan_platform.endFrame();
        return true;
    }
} else void;

// ── GL 4.4 / 3.3 / GLES30 ─────────────────────────────────────────────────

const Gl44Driver = if (build_options.enable_gl44) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gl44Renderer,
    cache: ?snail.Gl44BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl44Driver {
        try gl_platform.initForWindow(window, .gl44);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gl44Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *Gl44Driver) void {
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderFrame(self: *Gl44Driver, allocator: std.mem.Allocator, passes: []const Pass, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, snail.Gl44BackendCache, allocator, passes, clear_srgb);
    }
} else void;

const Gl33Driver = if (build_options.enable_gl33) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gl33Renderer,
    cache: ?snail.Gl33BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl33Driver {
        try gl_platform.initForWindow(window, .gl33);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gl33Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .scratch = ScratchBuf.init(allocator),
        };
    }

    fn deinit(self: *Gl33Driver) void {
        if (self.cache) |*c| c.deinit();
        self.scratch.deinit();
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderFrame(self: *Gl33Driver, allocator: std.mem.Allocator, passes: []const Pass, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, snail.Gl33BackendCache, allocator, passes, clear_srgb);
    }
} else void;

const Gles30Driver = if (build_options.enable_gles30) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gles30Renderer,
    cache: ?snail.Gles30BackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gles30Driver {
        try gl_platform.initForWindow(window, .gles30);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gles30Renderer.init(allocator);
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
        return glRender(@TypeOf(self.*), self, snail.Gles30BackendCache, allocator, passes, clear_srgb);
    }
} else void;

fn glRender(
    comptime Self: type,
    self: *Self,
    comptime CacheType: type,
    allocator: std.mem.Allocator,
    passes: []const Pass,
    clear_srgb: [4]f32,
) !bool {
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

    try syncPassBindings(CacheType, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);

    var records_buf: [MAX_PASSES]PassRecords = undefined;
    try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);

    // Surface dims are uniform across passes (one window).
    const surface = passes[0].draw_state.surface;
    gl.glViewport(0, 0, @intFromFloat(surface.pixel_width), @intFromFloat(surface.pixel_height));

    if (surface.supportsLinearResolve()) {
        // Driver gave us a linear default framebuffer (e.g. NVIDIA's GLES on
        // Wayland silently downgrades EGL_GL_COLORSPACE_SRGB_KHR). Render
        // into a linear fp16 intermediate so blending is linear-correct, then
        // let endLinearResolve encode-pass it into the default framebuffer.
        const restore = try self.renderer_state.state.beginLinearResolve(surface, .{
            .backdrop = .{ .clear = clear_srgb },
            .region = .full_target,
            .intermediate_format = .rgba16f,
        });
        errdefer self.renderer_state.state.endLinearResolve(restore);
        self.renderer_state.state.beginDraw();
        for (passes, records_buf[0..passes.len]) |pass, rec| {
            try self.renderer_state.state.draw(allocator, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?});
        }
        self.renderer_state.state.endLinearResolve(restore);
    } else {
        const clear = clearColorForShader(clear_srgb, surface.encoding);
        gl_platform.clear(clear[0], clear[1], clear[2], clear[3]);
        self.renderer_state.state.beginDraw();
        for (passes, records_buf[0..passes.len]) |pass, rec| {
            try self.renderer_state.state.draw(allocator, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?});
        }
    }

    gl_platform.swapBuffers();
    return true;
}

// ── CPU ───────────────────────────────────────────────────────────────────

const CpuDriver = if (build_options.enable_cpu) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.CpuRenderer,
    pool: ?*snail.ThreadPool = null,
    cache: ?snail.CpuBackendCache = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    pass_states: [MAX_PASSES]PassState = [_]PassState{.{}} ** MAX_PASSES,
    buf_width: u32 = 0,
    buf_height: u32 = 0,
    /// Microseconds spent inside each pass's drawCpu on the most
    /// recent frame. Indexed 1:1 with the input `passes` slice;
    /// trailing entries (beyond `passes.len`) stay zero.
    last_pass_us: [MAX_PASSES]f64 = [_]f64{0} ** MAX_PASSES,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window, thread_count: ?usize) !CpuDriver {
        try cpu_platform.initForWindow(window);
        errdefer cpu_platform.deinit();
        const px = cpu_platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = cpu_platform.getBufferSize();
        const renderer_state = snail.CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);

        const pool_ptr = try allocator.create(snail.ThreadPool);
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
        // Re-acquire pixel buffer if the platform resized.
        const bsz = cpu_platform.getBufferSize();
        if (bsz[0] != self.buf_width or bsz[1] != self.buf_height) {
            if (cpu_platform.getPixelBuffer()) |px| {
                self.buf_width = bsz[0];
                self.buf_height = bsz[1];
                self.renderer_state.reinitBuffer(px, bsz[0], bsz[1], bsz[0] * 4);
            }
        }
        // Clear the framebuffer in the storage encoding (shared by all passes).
        const surface = passes[0].draw_state.surface;
        if (cpu_platform.getPixelBuffer()) |px| {
            const stored = switch (surface.encoding.stored_pixels) {
                .linear => [4]f32{ srgbToLinear(clear_srgb[0]), srgbToLinear(clear_srgb[1]), srgbToLinear(clear_srgb[2]), clear_srgb[3] },
                .srgb => clear_srgb,
            };
            const r = unitToU8(stored[0]);
            const g = unitToU8(stored[1]);
            const b = unitToU8(stored[2]);
            const a = unitToU8(stored[3]);
            for (0..bsz[1]) |row| {
                const row_start = row * bsz[0] * 4;
                for (0..bsz[0]) |col| {
                    const off = row_start + col * 4;
                    px[off + 0] = r;
                    px[off + 1] = g;
                    px[off + 2] = b;
                    px[off + 3] = a;
                }
            }
        }

        const pool = passes[0].atlases[0].pool.?;
        const pool_ptr: *const anyopaque = @ptrCast(pool);
        var cache_fresh = false;
        if (self.cache_pool != pool_ptr) {
            if (self.cache) |*c| c.deinit();
            self.cache = try snail.CpuBackendCache.init(self.allocator, pool, .{
                .max_bindings = 16,
                .layer_info_height = 64,
                .max_images = 8,
            });
            self.cache_pool = pool_ptr;
            for (self.pass_states[0..]) |*ps| ps.initialized = false;
            cache_fresh = true;
        }

        try syncPassBindings(snail.CpuBackendCache, &self.cache.?, allocator, passes, self.pass_states[0..passes.len], cache_fresh);

        var records_buf: [MAX_PASSES]PassRecords = undefined;
        try emitPasses(&self.scratch, passes, self.pass_states[0..passes.len], records_buf[0..passes.len]);

        self.last_pass_us = [_]f64{0} ** MAX_PASSES;
        for (passes, records_buf[0..passes.len], 0..) |pass, rec, i| {
            const dispatch_pool: ?*snail.ThreadPool = if (pass.cpu_parallel) self.pool else null;
            const t0 = wayland.getTime();
            try snail.drawCpu(&self.renderer_state, pass.draw_state, .{ .words = rec.words, .segments = rec.segs }, &.{&self.cache.?}, dispatch_pool);
            self.last_pass_us[i] = (wayland.getTime() - t0) * 1_000_000.0;
        }

        cpu_platform.swapBuffers();
        return true;
    }
} else void;
