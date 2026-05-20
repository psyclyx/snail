const std = @import("std");
const builtin = @import("builtin");
const snail = @import("snail");
const build_options = @import("build_options");
const screenshot = @import("support").screenshot;
const presentation = @import("platform/presentation.zig");
const wayland = @import("platform/wayland.zig");

const gl_platform = if ((build_options.enable_gl33 or build_options.enable_gl44 or build_options.enable_gles30)) @import("platform/gl.zig") else struct {};
const vulkan_platform = if (build_options.enable_vulkan) @import("platform/vulkan.zig") else struct {};
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

const CpuThreading = enum {
    default,
    less_threaded,
    unthreaded,

    fn label(self: CpuThreading) []const u8 {
        return switch (self) {
            .default => "CPU",
            .less_threaded => "CPU (1 worker)",
            .unthreaded => "CPU (unthreaded)",
        };
    }

    fn workerThreads(self: CpuThreading) ?usize {
        return switch (self) {
            .default => null,
            .less_threaded => 1,
            .unthreaded => null,
        };
    }

    fn usesPool(self: CpuThreading) bool {
        return self != .unthreaded;
    }
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
    return switch (current) {
        .vulkan => if (build_options.enable_gl44) .gl44 else if (build_options.enable_gl33) .gl33 else if (build_options.enable_gles30) .gles30 else if (build_options.enable_cpu) .cpu else .vulkan,
        .gl44 => if (build_options.enable_gl33) .gl33 else if (build_options.enable_gles30) .gles30 else if (build_options.enable_cpu) .cpu else if (build_options.enable_vulkan) .vulkan else .gl44,
        .gl33 => if (build_options.enable_gles30) .gles30 else if (build_options.enable_cpu) .cpu else if (build_options.enable_vulkan) .vulkan else if (build_options.enable_gl44) .gl44 else .gl33,
        .gles30 => if (build_options.enable_cpu) .cpu else if (build_options.enable_vulkan) .vulkan else if (build_options.enable_gl44) .gl44 else if (build_options.enable_gl33) .gl33 else .gles30,
        .cpu => if (build_options.enable_cpu) .cpu_less_threaded else if (build_options.enable_vulkan) .vulkan else if (build_options.enable_gl44) .gl44 else if (build_options.enable_gl33) .gl33 else if (build_options.enable_gles30) .gles30 else .cpu,
        .cpu_less_threaded => if (build_options.enable_cpu) .cpu_unthreaded else if (build_options.enable_vulkan) .vulkan else if (build_options.enable_gl44) .gl44 else if (build_options.enable_gl33) .gl33 else if (build_options.enable_gles30) .gles30 else .cpu_less_threaded,
        .cpu_unthreaded => if (build_options.enable_vulkan) .vulkan else if (build_options.enable_gl44) .gl44 else if (build_options.enable_gl33) .gl33 else if (build_options.enable_gles30) .gles30 else if (build_options.enable_cpu) .cpu else .cpu_unthreaded,
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
        .vulkan, .gl44, .gl33, .gles30 => false,
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
                .{ .cpu = try CpuDriver.init(allocator, window, .default) }
            else
                unreachable,
            .cpu_less_threaded => if (comptime build_options.enable_cpu)
                .{ .cpu_less_threaded = try CpuDriver.init(allocator, window, .less_threaded) }
            else
                unreachable,
            .cpu_unthreaded => if (comptime build_options.enable_cpu)
                .{ .cpu_unthreaded = try CpuDriver.init(allocator, window, .unthreaded) }
            else
                unreachable,
        };
    }

    pub fn kind(self: *const Driver) Kind {
        return switch (self.*) {
            .vulkan => .vulkan,
            .gl44 => .gl44,
            .gl33 => .gl33,
            .gles30 => .gles30,
            .cpu => .cpu,
            .cpu_less_threaded => .cpu_less_threaded,
            .cpu_unthreaded => .cpu_unthreaded,
        };
    }

    pub fn deinit(self: *Driver) void {
        switch (self.*) {
            .vulkan => |*driver| if (comptime build_options.enable_vulkan) driver.deinit() else unreachable,
            .gl44 => |*driver| if (comptime build_options.enable_gl44) driver.deinit() else unreachable,
            .gl33 => |*driver| if (comptime build_options.enable_gl33) driver.deinit() else unreachable,
            .gles30 => |*driver| if (comptime build_options.enable_gles30) driver.deinit() else unreachable,
            .cpu => |*driver| if (comptime build_options.enable_cpu) driver.deinit() else unreachable,
            .cpu_less_threaded => |*driver| if (comptime build_options.enable_cpu) driver.deinit() else unreachable,
            .cpu_unthreaded => |*driver| if (comptime build_options.enable_cpu) driver.deinit() else unreachable,
        }
    }

    pub fn renderer(self: *Driver) snail.Renderer {
        return switch (self.*) {
            .vulkan => |*driver| if (comptime build_options.enable_vulkan) driver.renderer() else unreachable,
            .gl44 => |*driver| if (comptime build_options.enable_gl44) driver.renderer() else unreachable,
            .gl33 => |*driver| if (comptime build_options.enable_gl33) driver.renderer() else unreachable,
            .gles30 => |*driver| if (comptime build_options.enable_gles30) driver.renderer() else unreachable,
            .cpu => |*driver| if (comptime build_options.enable_cpu) driver.renderer() else unreachable,
            .cpu_less_threaded => |*driver| if (comptime build_options.enable_cpu) driver.renderer() else unreachable,
            .cpu_unthreaded => |*driver| if (comptime build_options.enable_cpu) driver.renderer() else unreachable,
        };
    }

    pub fn backendName(self: *Driver) []const u8 {
        return switch (self.*) {
            .vulkan => if (comptime build_options.enable_vulkan) blk: {
                var r = self.renderer();
                break :blk r.backendName();
            } else unreachable,
            .gl44 => if (comptime build_options.enable_gl44) blk: {
                var r = self.renderer();
                break :blk r.backendName();
            } else unreachable,
            .gl33 => if (comptime build_options.enable_gl33) blk: {
                var r = self.renderer();
                break :blk r.backendName();
            } else unreachable,
            .gles30 => if (comptime build_options.enable_gles30) blk: {
                var r = self.renderer();
                break :blk r.backendName();
            } else unreachable,
            .cpu => |*driver| if (comptime build_options.enable_cpu) driver.backendName() else unreachable,
            .cpu_less_threaded => |*driver| if (comptime build_options.enable_cpu) driver.backendName() else unreachable,
            .cpu_unthreaded => |*driver| if (comptime build_options.enable_cpu) driver.backendName() else unreachable,
        };
    }

    pub fn shouldClose(self: *Driver) bool {
        return switch (self.*) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.shouldClose() else true,
            .gl44 => if (comptime build_options.enable_gl44) gl_platform.shouldClose() else true,
            .gl33 => if (comptime build_options.enable_gl33) gl_platform.shouldClose() else true,
            .gles30 => if (comptime build_options.enable_gles30) gl_platform.shouldClose() else true,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.shouldClose() else true,
            .cpu_less_threaded => if (comptime build_options.enable_cpu) cpu_platform.shouldClose() else true,
            .cpu_unthreaded => if (comptime build_options.enable_cpu) cpu_platform.shouldClose() else true,
        };
    }

    pub fn presentationInfo(self: *Driver) presentation.Info {
        return switch (self.*) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.presentationInfo() else .{},
            .gl44 => if (comptime build_options.enable_gl44) gl_platform.presentationInfo() else .{},
            .gl33 => if (comptime build_options.enable_gl33) gl_platform.presentationInfo() else .{},
            .gles30 => if (comptime build_options.enable_gles30) gl_platform.presentationInfo() else .{},
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.presentationInfo() else .{},
            .cpu_less_threaded => if (comptime build_options.enable_cpu) cpu_platform.presentationInfo() else .{},
            .cpu_unthreaded => if (comptime build_options.enable_cpu) cpu_platform.presentationInfo() else .{},
        };
    }

    pub fn beginFrame(self: *Driver, fb_size: [2]u32, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) bool {
        return switch (self.*) {
            .vulkan => |*driver| if (comptime build_options.enable_vulkan) driver.beginFrame() else false,
            .gl44 => if (comptime build_options.enable_gl44) beginGlFrame(fb_size, clear_srgb, target_encoding) else false,
            .gl33 => if (comptime build_options.enable_gl33) beginGlFrame(fb_size, clear_srgb, target_encoding) else false,
            .gles30 => if (comptime build_options.enable_gles30) beginGlFrame(fb_size, clear_srgb, target_encoding) else false,
            .cpu => |*driver| if (comptime build_options.enable_cpu) driver.beginFrame(clear_srgb, target_encoding) else false,
            .cpu_less_threaded => |*driver| if (comptime build_options.enable_cpu) driver.beginFrame(clear_srgb, target_encoding) else false,
            .cpu_unthreaded => |*driver| if (comptime build_options.enable_cpu) driver.beginFrame(clear_srgb, target_encoding) else false,
        };
    }

    pub fn draw(self: *Driver, prepared: *const snail.PreparedResources, list: *const snail.DrawList, state: snail.DrawState) !void {
        try self.drawPass(prepared, list, .{ .state = state });
    }

    pub fn drawPass(self: *Driver, prepared: *const snail.PreparedResources, list: *const snail.DrawList, pass: snail.DrawPass) !void {
        switch (self.*) {
            .vulkan => |*driver| if (comptime build_options.enable_vulkan) {
                try driver.drawPass(prepared, list, pass);
            } else unreachable,
            else => {
                var r = self.renderer();
                try r.drawPass(prepared, list, pass);
            },
        }
    }

    pub fn endFrame(self: *Driver) void {
        switch (self.*) {
            .vulkan => |*driver| if (comptime build_options.enable_vulkan) {
                driver.frame = null;
                vulkan_platform.endFrame();
            },
            .gl44 => if (comptime build_options.enable_gl44) gl_platform.swapBuffers(),
            .gl33 => if (comptime build_options.enable_gl33) gl_platform.swapBuffers(),
            .gles30 => if (comptime build_options.enable_gles30) gl_platform.swapBuffers(),
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.swapBuffers(),
            .cpu_less_threaded => if (comptime build_options.enable_cpu) cpu_platform.swapBuffers(),
            .cpu_unthreaded => if (comptime build_options.enable_cpu) cpu_platform.swapBuffers(),
        }
    }

    pub fn captureDebugFrame(self: *Driver, allocator: std.mem.Allocator, fb_size: [2]u32) void {
        const kind_value = self.kind();
        if ((kind_value != .gl44 and kind_value != .gl33 and kind_value != .gles30) or (!build_options.enable_gl33 and !build_options.enable_gl44 and !build_options.enable_gles30)) return;
        const iw = fb_size[0];
        const ih = fb_size[1];
        if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
            defer allocator.free(px);
            screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
        }
    }
};

const VulkanDriver = if (build_options.enable_vulkan) struct {
    renderer_state: snail.VulkanRenderer,
    frame: ?snail.VulkanRenderer.Frame = null,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !VulkanDriver {
        const ctx = try vulkan_platform.initForWindow(window);
        errdefer vulkan_platform.deinit();
        var renderer_state = try snail.VulkanRenderer.init(allocator, ctx);
        errdefer renderer_state.deinit();
        return .{ .renderer_state = renderer_state };
    }

    fn deinit(self: *VulkanDriver) void {
        self.renderer_state.deinit();
        vulkan_platform.deinit();
    }

    fn renderer(self: *VulkanDriver) snail.Renderer {
        return self.renderer_state.asRenderer();
    }

    fn beginFrame(self: *VulkanDriver) bool {
        const cmd = vulkan_platform.beginFrame() orelse return false;
        self.frame = self.renderer_state.frame(.{ .cmd = cmd, .slot = vulkan_platform.currentFrameIndex() });
        return true;
    }

    fn draw(self: *VulkanDriver, prepared: *const snail.PreparedResources, list: *const snail.DrawList, state: snail.DrawState) !void {
        try self.drawPass(prepared, list, .{ .state = state });
    }

    fn drawPass(self: *VulkanDriver, prepared: *const snail.PreparedResources, list: *const snail.DrawList, pass: snail.DrawPass) !void {
        const frame = self.frame orelse return error.MissingCommandBuffer;
        try frame.drawPass(prepared, list, pass);
    }
} else void;

const Gl44Driver = if (build_options.enable_gl44) struct {
    renderer_state: snail.Gl44Renderer,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl44Driver {
        try gl_platform.initForWindow(window, .gl44);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gl44Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{ .renderer_state = renderer_state };
    }

    fn deinit(self: *Gl44Driver) void {
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderer(self: *Gl44Driver) snail.Renderer {
        return self.renderer_state.asRenderer();
    }
} else void;

const Gl33Driver = if (build_options.enable_gl33) struct {
    renderer_state: snail.Gl33Renderer,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gl33Driver {
        try gl_platform.initForWindow(window, .gl33);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gl33Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{ .renderer_state = renderer_state };
    }

    fn deinit(self: *Gl33Driver) void {
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderer(self: *Gl33Driver) snail.Renderer {
        return self.renderer_state.asRenderer();
    }
} else void;

const Gles30Driver = if (build_options.enable_gles30) struct {
    renderer_state: snail.Gles30Renderer,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window) !Gles30Driver {
        try gl_platform.initForWindow(window, .gles30);
        errdefer gl_platform.deinit();
        var renderer_state = try snail.Gles30Renderer.init(allocator);
        errdefer renderer_state.deinit();
        return .{ .renderer_state = renderer_state };
    }

    fn deinit(self: *Gles30Driver) void {
        self.renderer_state.deinit();
        gl_platform.deinit();
    }

    fn renderer(self: *Gles30Driver) snail.Renderer {
        return self.renderer_state.asRenderer();
    }
} else void;

const CpuDriver = if (build_options.enable_cpu) struct {
    allocator: std.mem.Allocator,
    renderer_state: snail.CpuRenderer,
    pool: ?*snail.ThreadPool,
    threading: CpuThreading,
    buf_width: u32 = 0,
    buf_height: u32 = 0,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window, threading: CpuThreading) !CpuDriver {
        try cpu_platform.initForWindow(window);
        errdefer cpu_platform.deinit();

        const px = cpu_platform.getPixelBuffer() orelse return error.NoPixelBuffer;
        const bsz = cpu_platform.getBufferSize();
        var renderer_state = snail.CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);

        var pool: ?*snail.ThreadPool = null;
        if (threading.usesPool()) {
            const p = try allocator.create(snail.ThreadPool);
            errdefer allocator.destroy(p);
            try p.init(allocator, .{ .threads = threading.workerThreads() });
            errdefer p.deinit();
            renderer_state.setThreadPool(p);
            pool = p;
        }

        return .{
            .allocator = allocator,
            .renderer_state = renderer_state,
            .pool = pool,
            .threading = threading,
            .buf_width = bsz[0],
            .buf_height = bsz[1],
        };
    }

    fn deinit(self: *CpuDriver) void {
        self.renderer_state.setThreadPool(null);
        if (self.pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }
        cpu_platform.deinit();
    }

    fn renderer(self: *CpuDriver) snail.Renderer {
        return self.renderer_state.asRenderer();
    }

    fn backendName(self: *CpuDriver) []const u8 {
        return self.threading.label();
    }

    fn beginFrame(self: *CpuDriver, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) bool {
        self.prepareFrame(clear_srgb, target_encoding);
        return true;
    }

    fn prepareFrame(self: *CpuDriver, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) void {
        const bsz = cpu_platform.getBufferSize();
        if (bsz[0] != self.buf_width or bsz[1] != self.buf_height) {
            if (cpu_platform.getPixelBuffer()) |px| {
                self.buf_width = bsz[0];
                self.buf_height = bsz[1];
                self.renderer_state.reinitBuffer(px, bsz[0], bsz[1], bsz[0] * 4);
            }
        }

        if (cpu_platform.getPixelBuffer()) |px| {
            const clear_bytes = clearColorForStoredPixels(clear_srgb, target_encoding);
            const r = unitToU8(clear_bytes[0]);
            const g = unitToU8(clear_bytes[1]);
            const b = unitToU8(clear_bytes[2]);
            const a = unitToU8(clear_bytes[3]);
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
    }
} else void;

fn beginGlFrame(fb_size: [2]u32, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) bool {
    const clear = clearColorForTarget(clear_srgb, target_encoding);
    gl.glViewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));
    gl_platform.clear(clear[0], clear[1], clear[2], clear[3]);
    return true;
}

fn unitToU8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255);
}

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn clearColorForTarget(color_srgb: [4]f32, encoding: snail.TargetEncoding) [4]f32 {
    return switch (encoding.shaderOutputEncoding()) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}

fn clearColorForStoredPixels(color_srgb: [4]f32, encoding: snail.TargetEncoding) [4]f32 {
    return switch (encoding.stored_pixels) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}
