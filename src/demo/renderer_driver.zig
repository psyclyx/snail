//! Cross-backend driver for the interactive demo. Wraps each backend's
//! `Renderer` + `PreparedPages` cache + new-API `emit`/`draw` shim into a
//! single tagged union so `main.zig` can cycle between backends with the
//! 'C' key without knowing each backend's idiom.
//!
//! CPU has three flavours that differ only in the thread-pool sizing:
//! `cpu` uses the default pool (one worker per logical core minus one),
//! `cpu_less_threaded` runs with a single worker, and `cpu_unthreaded`
//! has zero workers so dispatch runs every tile on the calling thread.
//! All three share the same `CpuRenderer` + `CpuPreparedPages` plumbing.

const std = @import("std");
const builtin = @import("builtin");
const snail = @import("snail");
const build_options = @import("build_options");
const presentation = @import("platform/presentation.zig");
const wayland = @import("platform/wayland.zig");
const demo_scene = @import("scene.zig");

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

    /// Render `content` for one frame.  Caller has already done input/state work.
    /// Returns true if the frame was rendered, false if it was skipped (e.g.
    /// swapchain not ready).
    pub fn renderFrame(
        self: *Driver,
        allocator: std.mem.Allocator,
        content: *demo_scene.Content,
        draw_state: snail.DrawState,
        content_dirty: bool,
        clear_srgb: [4]f32,
    ) !bool {
        switch (self.*) {
            .vulkan => |*d| if (comptime build_options.enable_vulkan) {
                return d.renderFrame(allocator, content, draw_state, content_dirty, clear_srgb);
            } else unreachable,
            .gl44 => |*d| if (comptime build_options.enable_gl44) {
                return d.renderFrame(allocator, content, draw_state, content_dirty, clear_srgb);
            } else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) {
                return d.renderFrame(allocator, content, draw_state, content_dirty, clear_srgb);
            } else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) {
                return d.renderFrame(allocator, content, draw_state, content_dirty, clear_srgb);
            } else unreachable,
            .cpu, .cpu_less_threaded, .cpu_unthreaded => |*d| if (comptime build_options.enable_cpu) {
                return d.renderFrame(allocator, content, draw_state, content_dirty, clear_srgb);
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

fn emitBoth(
    scratch: *ScratchBuf,
    content: *demo_scene.Content,
    paths_binding: snail.Binding,
    text_binding: snail.Binding,
) !struct { words: []const u32, segs: []const snail.DrawSegment } {
    const needed_words = snail.emit.wordBudget(&content.paths_picture, 0) + snail.emit.wordBudget(&content.text_picture, 0);
    try scratch.ensure(needed_words, 4);
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, paths_binding, &content.paths_atlas, &content.paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, text_binding, &content.text_atlas, &content.text_picture, .identity, .{ 1, 1, 1, 1 });
    return .{ .words = scratch.words[0..wlen], .segs = scratch.segs[0..slen] };
}

// ── Vulkan ────────────────────────────────────────────────────────────────

const VulkanDriver = if (build_options.enable_vulkan) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.VulkanRenderer,
    cache: ?snail.VulkanPreparedPages = null,
    cache_pool: ?*const anyopaque = null, // PagePool pointer to detect content swap
    scratch: ScratchBuf,
    paths_binding: snail.Binding = undefined,
    text_binding: snail.Binding = undefined,
    have_bindings: bool = false,

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

    fn ensureCache(self: *VulkanDriver, content: *demo_scene.Content) !bool {
        const pool_ptr: *const anyopaque = @ptrCast(content.pool);
        if (self.cache_pool == pool_ptr) return false;
        if (self.cache) |*c| c.deinit();
        self.cache = try snail.VulkanPreparedPages.init(self.allocator, content.pool, self.renderer_state.state.pipelineShape(), .{
            .max_bindings = 4,
            .layer_info_height = 64,
            .max_images = 8,
            .max_image_width = 256,
            .max_image_height = 256,
        });
        self.cache_pool = pool_ptr;
        return true;
    }

    fn renderFrame(
        self: *VulkanDriver,
        allocator: std.mem.Allocator,
        content: *demo_scene.Content,
        draw_state: snail.DrawState,
        content_dirty: bool,
        clear_srgb: [4]f32,
    ) !bool {
        const cache_fresh = try self.ensureCache(content);
        if (content_dirty or cache_fresh) {
            // Release the previous frame's bindings before allocating new
            // slots, otherwise repeated content rebuilds (e.g. cycling
            // hint modes) exhaust `max_bindings` after a handful of frames.
            // `cache_fresh` (just-allocated cache) means there's nothing to
            // release.
            if (self.have_bindings and !cache_fresh) {
                self.cache.?.release(self.paths_binding);
                self.cache.?.release(self.text_binding);
            }
            self.have_bindings = false;
            var bindings: [2]snail.Binding = undefined;
            try self.cache.?.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
            self.paths_binding = bindings[0];
            self.text_binding = bindings[1];
            self.have_bindings = true;
        }

        const cmd = vulkan_platform.beginFrame() orelse return false;
        const clear = clearColorForShader(clear_srgb, draw_state.surface.encoding);
        _ = clear; // Vulkan platform clears with its own fixed colour; for the demo
        // we accept the platform clear (the card fully covers the viewport anyway).

        self.renderer_state.state.setCommandBuffer(cmd);
        defer self.renderer_state.state.clearCommandBuffer();
        self.renderer_state.state.setFrameSlot(vulkan_platform.currentFrameIndex());

        const emitted = try emitBoth(&self.scratch, content, self.paths_binding, self.text_binding);
        try self.renderer_state.state.draw(allocator, draw_state, .{ .words = emitted.words, .segments = emitted.segs }, &.{&self.cache.?});

        vulkan_platform.endFrame();
        return true;
    }
} else void;

// ── GL 4.4 / 3.3 / GLES30 ─────────────────────────────────────────────────

const Gl44Driver = if (build_options.enable_gl44) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gl44Renderer,
    cache: ?snail.Gl44PreparedPages = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    paths_binding: snail.Binding = undefined,
    text_binding: snail.Binding = undefined,
    have_bindings: bool = false,

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

    fn renderFrame(self: *Gl44Driver, allocator: std.mem.Allocator, content: *demo_scene.Content, draw_state: snail.DrawState, content_dirty: bool, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, snail.Gl44PreparedPages, allocator, content, draw_state, content_dirty, clear_srgb);
    }
} else void;

const Gl33Driver = if (build_options.enable_gl33) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gl33Renderer,
    cache: ?snail.Gl33PreparedPages = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    paths_binding: snail.Binding = undefined,
    text_binding: snail.Binding = undefined,
    have_bindings: bool = false,

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

    fn renderFrame(self: *Gl33Driver, allocator: std.mem.Allocator, content: *demo_scene.Content, draw_state: snail.DrawState, content_dirty: bool, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, snail.Gl33PreparedPages, allocator, content, draw_state, content_dirty, clear_srgb);
    }
} else void;

const Gles30Driver = if (build_options.enable_gles30) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.Gles30Renderer,
    cache: ?snail.Gles30PreparedPages = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    paths_binding: snail.Binding = undefined,
    text_binding: snail.Binding = undefined,
    have_bindings: bool = false,

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

    fn renderFrame(self: *Gles30Driver, allocator: std.mem.Allocator, content: *demo_scene.Content, draw_state: snail.DrawState, content_dirty: bool, clear_srgb: [4]f32) !bool {
        return glRender(@TypeOf(self.*), self, snail.Gles30PreparedPages, allocator, content, draw_state, content_dirty, clear_srgb);
    }
} else void;

fn glRender(
    comptime Self: type,
    self: *Self,
    comptime CacheType: type,
    allocator: std.mem.Allocator,
    content: *demo_scene.Content,
    draw_state: snail.DrawState,
    content_dirty: bool,
    clear_srgb: [4]f32,
) !bool {
    // Ensure cache.
    const pool_ptr: *const anyopaque = @ptrCast(content.pool);
    var cache_fresh = false;
    if (self.cache_pool != pool_ptr) {
        if (self.cache) |*c| c.deinit();
        self.cache = try CacheType.init(self.allocator, content.pool, .{
            .max_bindings = 4,
            .layer_info_height = 64,
            .max_images = 8,
            .max_image_width = 256,
            .max_image_height = 256,
        });
        self.cache_pool = pool_ptr;
        self.have_bindings = false;
        cache_fresh = true;
    }
    if (content_dirty or cache_fresh) {
        // Release the previous frame's bindings before allocating new
        // slots, or repeated content rebuilds exhaust `max_bindings`.
        if (self.have_bindings and !cache_fresh) {
            self.cache.?.release(self.paths_binding);
            self.cache.?.release(self.text_binding);
        }
        self.have_bindings = false;
        var bindings: [2]snail.Binding = undefined;
        try self.cache.?.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
        self.paths_binding = bindings[0];
        self.text_binding = bindings[1];
        self.have_bindings = true;
    }

    const clear = clearColorForShader(clear_srgb, draw_state.surface.encoding);
    gl.glViewport(0, 0, @intFromFloat(draw_state.surface.pixel_width), @intFromFloat(draw_state.surface.pixel_height));
    gl_platform.clear(clear[0], clear[1], clear[2], clear[3]);
    self.renderer_state.state.beginDraw();

    const emitted = try emitBoth(&self.scratch, content, self.paths_binding, self.text_binding);
    try self.renderer_state.state.draw(allocator, draw_state, .{ .words = emitted.words, .segments = emitted.segs }, &.{&self.cache.?});

    gl_platform.swapBuffers();
    return true;
}

// ── CPU ───────────────────────────────────────────────────────────────────

const CpuDriver = if (build_options.enable_cpu) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.CpuRenderer,
    pool: ?*snail.ThreadPool = null,
    cache: ?snail.CpuPreparedPages = null,
    cache_pool: ?*const anyopaque = null,
    scratch: ScratchBuf,
    paths_binding: snail.Binding = undefined,
    text_binding: snail.Binding = undefined,
    have_bindings: bool = false,
    buf_width: u32 = 0,
    buf_height: u32 = 0,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window, thread_count: ?usize) !CpuDriver {
        try cpu_platform.initForWindow(window);
        errdefer cpu_platform.deinit();
        const px = cpu_platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = cpu_platform.getBufferSize();
        var renderer_state = snail.CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);

        const pool_ptr = try allocator.create(snail.ThreadPool);
        errdefer allocator.destroy(pool_ptr);
        try pool_ptr.init(allocator, .{ .threads = thread_count });
        errdefer pool_ptr.deinit();
        renderer_state.setThreadPool(pool_ptr);

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
        self.renderer_state.setThreadPool(null);
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
        content: *demo_scene.Content,
        draw_state: snail.DrawState,
        content_dirty: bool,
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
        // Clear the framebuffer in the storage encoding.
        if (cpu_platform.getPixelBuffer()) |px| {
            const stored = switch (draw_state.surface.encoding.stored_pixels) {
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

        // Ensure cache.
        const pool_ptr: *const anyopaque = @ptrCast(content.pool);
        var cache_fresh = false;
        if (self.cache_pool != pool_ptr) {
            if (self.cache) |*c| c.deinit();
            self.cache = try snail.CpuPreparedPages.init(self.allocator, content.pool, .{
                .max_bindings = 4,
                .layer_info_height = 64,
                .max_images = 8,
            });
            self.cache_pool = pool_ptr;
            self.have_bindings = false;
            cache_fresh = true;
        }
        if (content_dirty or cache_fresh) {
            if (self.have_bindings and !cache_fresh) {
                self.cache.?.release(self.paths_binding);
                self.cache.?.release(self.text_binding);
            }
            self.have_bindings = false;
            var bindings: [2]snail.Binding = undefined;
            try self.cache.?.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
            self.paths_binding = bindings[0];
            self.text_binding = bindings[1];
            self.have_bindings = true;
        }

        const emitted = try emitBoth(&self.scratch, content, self.paths_binding, self.text_binding);
        try snail.drawCpu(&self.renderer_state, draw_state, .{ .words = emitted.words, .segments = emitted.segs }, &.{&self.cache.?});

        cpu_platform.swapBuffers();
        return true;
    }
} else void;
