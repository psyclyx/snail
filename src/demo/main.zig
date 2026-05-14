const std = @import("std");
const builtin = @import("builtin");
const snail = @import("snail");
const build_options = @import("build_options");
const demo_banner = @import("banner.zig");
const demo_banner_scene = @import("scene.zig");
const screenshot = @import("platform/screenshot.zig");
const subpixel_detect = @import("platform/subpixel.zig");
const wayland = @import("platform/wayland.zig");
const presentation = @import("platform/presentation.zig");

const gl_platform = if (build_options.enable_opengl) @import("platform/gl.zig") else struct {};
const vulkan_platform = if (build_options.enable_vulkan) @import("platform/vulkan.zig") else struct {};
const cpu_platform = if (build_options.enable_cpu) @import("platform/cpu.zig") else struct {};
const gl = if (build_options.enable_opengl) snail.lowlevel.gl else struct {};
const CpuRenderer = snail.CpuRenderer;

const Backend = enum {
    vulkan,
    gl,
    cpu,
};

const KEY_R = wayland.KEY_R;
const KEY_Z = wayland.KEY_Z;
const KEY_X = wayland.KEY_X;
const KEY_B = wayland.KEY_B;
const KEY_C = wayland.KEY_C;
const KEY_ESCAPE = wayland.KEY_ESCAPE;
const KEY_LEFT = wayland.KEY_LEFT;
const KEY_RIGHT = wayland.KEY_RIGHT;
const KEY_UP = wayland.KEY_UP;
const KEY_DOWN = wayland.KEY_DOWN;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    return mainLoop(allocator);
}

fn defaultBackend() Backend {
    if (comptime build_options.enable_vulkan) return .vulkan;
    if (comptime build_options.enable_opengl) return .gl;
    if (comptime build_options.enable_cpu) return .cpu;
    @compileError("at least one demo backend must be enabled");
}

fn nextBackend(current: Backend) Backend {
    return switch (current) {
        .vulkan => if (build_options.enable_opengl) .gl else if (build_options.enable_cpu) .cpu else .vulkan,
        .gl => if (build_options.enable_cpu) .cpu else if (build_options.enable_vulkan) .vulkan else .gl,
        .cpu => if (build_options.enable_vulkan) .vulkan else if (build_options.enable_opengl) .gl else .cpu,
    };
}

fn backendLabel(backend: Backend) []const u8 {
    return switch (backend) {
        .vulkan => "Vulkan",
        .gl => "OpenGL",
        .cpu => "CPU",
    };
}

fn unitToU8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0, 1) * 255);
}

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn toSnailEncoding(encoding: presentation.ColorEncoding) snail.ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: presentation.Info) snail.TargetEncoding {
    return .{
        .framebuffer = toSnailEncoding(info.framebuffer_encoding),
        .pixels = .srgb,
    };
}

fn clearColorForTarget(color_srgb: [4]f32, encoding: snail.TargetEncoding) [4]f32 {
    return switch (encoding.shaderOutputEncoding()) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}

fn clearColorForStoredPixels(color_srgb: [4]f32, encoding: snail.TargetEncoding) [4]f32 {
    return switch (encoding.pixels) {
        .linear => .{ srgbToLinear(color_srgb[0]), srgbToLinear(color_srgb[1]), srgbToLinear(color_srgb[2]), color_srgb[3] },
        .srgb => color_srgb,
    };
}

fn cycleSubpixelOrder(o: snail.SubpixelOrder) snail.SubpixelOrder {
    return switch (o) {
        .none => .rgb,
        .rgb => .bgr,
        .bgr => .vrgb,
        .vrgb => .vbgr,
        .vbgr => .none,
    };
}

fn aaName(o: snail.SubpixelOrder) []const u8 {
    return switch (o) {
        .none => "grayscale",
        .rgb => "subpixel-RGB",
        .bgr => "subpixel-BGR",
        .vrgb => "subpixel-VRGB",
        .vbgr => "subpixel-VBGR",
    };
}

fn logPresentationInfo(info: presentation.Info) void {
    const scale = info.scale();
    std.debug.print(
        "presentation: logical={}x{} framebuffer={}x{} scale={d:.2}x{d:.2} buffer_scale={} framebuffer={s} resample={}\n",
        .{
            info.logical_size[0],
            info.logical_size[1],
            info.framebuffer_size[0],
            info.framebuffer_size[1],
            scale[0],
            scale[1],
            info.buffer_scale,
            @tagName(info.framebuffer_encoding),
            info.will_resample,
        },
    );
}

const ActiveBackend = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    initialized: bool = false,
    renderer: snail.Renderer = undefined,
    gl_renderer: if (build_options.enable_opengl) snail.GlRenderer else void = undefined,
    vk_renderer: if (build_options.enable_vulkan) snail.VulkanRenderer else void = undefined,
    cpu_state: if (build_options.enable_cpu) CpuRenderer else void = undefined,
    cpu_pool: if (build_options.enable_cpu) snail.ThreadPool else void = undefined,
    cpu_pool_initialized: bool = false,
    buf_width: u32 = 0,
    buf_height: u32 = 0,

    fn init(allocator: std.mem.Allocator, backend: Backend) !ActiveBackend {
        var self = ActiveBackend{ .allocator = allocator, .backend = backend };
        try self.initBackend(backend);
        return self;
    }

    fn switchTo(self: *ActiveBackend, backend: Backend) !void {
        if (backend == self.backend) return;
        self.deinitBackend();
        try self.initBackend(backend);
    }

    fn deinit(self: *ActiveBackend) void {
        self.deinitBackend();
    }

    fn initBackend(self: *ActiveBackend, backend: Backend) !void {
        self.backend = backend;
        self.initialized = false;
        self.buf_width = 0;
        self.buf_height = 0;
        switch (backend) {
            .vulkan => if (comptime build_options.enable_vulkan) {
                const vk_ctx = try vulkan_platform.init(1280, 720, "snail");
                errdefer vulkan_platform.deinit();
                self.vk_renderer = try snail.VulkanRenderer.init(vk_ctx);
                self.renderer = self.vk_renderer.asRenderer();
            } else unreachable,
            .gl => if (comptime build_options.enable_opengl) {
                try gl_platform.init(1280, 720, "snail");
                errdefer gl_platform.deinit();
                self.gl_renderer = try snail.GlRenderer.init(self.allocator);
                self.renderer = self.gl_renderer.asRenderer();
            } else unreachable,
            .cpu => if (comptime build_options.enable_cpu) {
                try cpu_platform.init(1280, 720, "snail");
                errdefer cpu_platform.deinit();
                const px = cpu_platform.getPixelBuffer() orelse return error.NoPixelBuffer;
                const bsz = cpu_platform.getBufferSize();
                self.cpu_state = CpuRenderer.init(px, bsz[0], bsz[1], bsz[0] * 4);
                try self.cpu_pool.init(self.allocator, .{});
                self.cpu_pool_initialized = true;
                self.cpu_state.setThreadPool(&self.cpu_pool);
                self.renderer = self.cpu_state.asRenderer();
                self.buf_width = bsz[0];
                self.buf_height = bsz[1];
            } else unreachable,
        }
        self.initialized = true;
    }

    fn deinitBackend(self: *ActiveBackend) void {
        if (!self.initialized) return;
        switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) {
                self.vk_renderer.deinit();
                vulkan_platform.deinit();
            },
            .gl => if (comptime build_options.enable_opengl) {
                self.gl_renderer.deinit();
                gl_platform.deinit();
            },
            .cpu => if (comptime build_options.enable_cpu) {
                if (self.cpu_pool_initialized) {
                    self.cpu_state.setThreadPool(null);
                    self.cpu_pool.deinit();
                    self.cpu_pool_initialized = false;
                }
                cpu_platform.deinit();
            },
        }
        self.initialized = false;
    }

    fn shouldClose(self: *ActiveBackend) bool {
        if (!self.initialized) return true;
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.shouldClose() else true,
            .gl => if (comptime build_options.enable_opengl) gl_platform.shouldClose() else true,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.shouldClose() else true,
        };
    }

    fn getTime(self: *ActiveBackend) f64 {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.getTime() else 0,
            .gl => if (comptime build_options.enable_opengl) gl_platform.getTime() else 0,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.getTime() else 0,
        };
    }

    fn isKeyDown(self: *ActiveBackend, key: u32) bool {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.isKeyDown(key) else false,
            .gl => if (comptime build_options.enable_opengl) gl_platform.isKeyDown(key) else false,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.isKeyDown(key) else false,
        };
    }

    fn isKeyPressed(self: *ActiveBackend, key: u32) bool {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.isKeyPressed(key) else false,
            .gl => if (comptime build_options.enable_opengl) gl_platform.isKeyPressed(key) else false,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.isKeyPressed(key) else false,
        };
    }

    fn consumeMonitorChanged(self: *ActiveBackend) bool {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.consumeMonitorChanged() else false,
            .gl => if (comptime build_options.enable_opengl) gl_platform.consumeMonitorChanged() else false,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.consumeMonitorChanged() else false,
        };
    }

    fn detectCurrentMonitorSubpixelOrder(self: *ActiveBackend, base: snail.SubpixelOrder) snail.SubpixelOrder {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.detectCurrentMonitorSubpixelOrder(base) else base,
            .gl => if (comptime build_options.enable_opengl) gl_platform.detectCurrentMonitorSubpixelOrder(base) else base,
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.detectCurrentMonitorSubpixelOrder(base) else base,
        };
    }

    fn presentationInfo(self: *ActiveBackend) presentation.Info {
        return switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.presentationInfo() else .{},
            .gl => if (comptime build_options.enable_opengl) gl_platform.presentationInfo() else .{},
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.presentationInfo() else .{},
        };
    }

    fn beginFrame(self: *ActiveBackend, fb_size: [2]u32, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) bool {
        switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) {
                const cmd = vulkan_platform.beginFrame() orelse return false;
                self.vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentFrameIndex() });
                return true;
            } else return false,
            .gl => if (comptime build_options.enable_opengl) {
                const clear = clearColorForTarget(clear_srgb, target_encoding);
                gl.glViewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));
                gl_platform.clear(clear[0], clear[1], clear[2], clear[3]);
                return true;
            } else return false,
            .cpu => if (comptime build_options.enable_cpu) {
                self.prepareCpuFrame(clear_srgb, target_encoding);
                return true;
            } else return false,
        }
    }

    fn endFrame(self: *ActiveBackend) void {
        switch (self.backend) {
            .vulkan => if (comptime build_options.enable_vulkan) vulkan_platform.endFrame(),
            .gl => if (comptime build_options.enable_opengl) gl_platform.swapBuffers(),
            .cpu => if (comptime build_options.enable_cpu) cpu_platform.swapBuffers(),
        }
    }

    fn captureDebugFrame(self: *ActiveBackend, allocator: std.mem.Allocator, fb_size: [2]u32) void {
        if (self.backend != .gl or !build_options.enable_opengl) return;
        const iw = fb_size[0];
        const ih = fb_size[1];
        if (screenshot.captureFramebuffer(allocator, iw, ih) catch null) |px| {
            defer allocator.free(px);
            screenshot.writeTga("zig-out/frame0.tga", px, iw, ih);
        }
    }

    fn prepareCpuFrame(self: *ActiveBackend, clear_srgb: [4]f32, target_encoding: snail.TargetEncoding) void {
        if (comptime !build_options.enable_cpu) return;
        const bsz = cpu_platform.getBufferSize();
        if (bsz[0] != self.buf_width or bsz[1] != self.buf_height) {
            if (cpu_platform.getPixelBuffer()) |px| {
                self.buf_width = bsz[0];
                self.buf_height = bsz[1];
                self.cpu_state.reinitBuffer(px, bsz[0], bsz[1], bsz[0] * 4);
                self.renderer = self.cpu_state.asRenderer();
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
};

fn releasePrepared(prepared: *?snail.PreparedResources) void {
    if (prepared.*) |*resources| {
        resources.retireNow();
        prepared.* = null;
    }
}

fn warnIfDebugCpu(backend: Backend) void {
    if (backend == .cpu and builtin.mode == .Debug) {
        std.debug.print(
            "WARNING: Debug build. CPU rasterization is ~30x slower without `--release=fast`.\n",
            .{},
        );
    }
}

fn mainLoop(allocator: std.mem.Allocator) !void {
    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var active = try ActiveBackend.init(allocator, defaultBackend());
    defer active.deinit();

    const sys_order = subpixel_detect.detect();
    const detected_order = active.detectCurrentMonitorSubpixelOrder(sys_order);
    // Default to grayscale; press B to cycle into the detected subpixel mode.
    var current_order: snail.SubpixelOrder = .none;
    std.debug.print("snail: detected subpixel order: system={s} monitor={s} (starting in {s})\n", .{ @tagName(sys_order), @tagName(detected_order), @tagName(current_order) });

    var path_picture: ?snail.PathPicture = null;
    defer if (path_picture) |*picture| picture.deinit();
    var text_blob: ?snail.TextBlob = null;
    defer if (text_blob) |*blob| blob.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    var prepared: ?snail.PreparedResources = null;
    defer releasePrepared(&prepared);
    var draw_buf: []u32 = &.{};
    defer if (draw_buf.len > 0) allocator.free(draw_buf);
    var draw_segments_buf: []snail.DrawSegment = &.{};
    defer if (draw_segments_buf.len > 0) allocator.free(draw_segments_buf);
    var uploaded_size = [4]u32{ 0, 0, 0, 0 };

    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var last_time = active.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0.0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0.0;
    var last_presentation: ?presentation.Info = null;

    std.debug.print("snail - GPU text & vector rendering\n", .{});
    std.debug.print("Backend: {s}, HarfBuzz: {s}\n", .{
        active.renderer.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    warnIfDebugCpu(active.backend);
    std.debug.print("Keys: arrows pan, Z/X zoom, R rotate, B AA mode, C backend, Esc quit\n", .{});
    std.debug.print("aa={s}\n", .{aaName(current_order)});

    while (!active.shouldClose()) {
        const now = active.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;
        fps_timer += dt;
        fps_frames += 1;
        if (fps_timer >= 1.0) {
            fps_display = @as(f32, @floatFromInt(fps_frames)) / @as(f32, @floatCast(fps_timer));
            fps_timer = 0.0;
            fps_frames = 0;
        }

        // Drop monitor-change auto-reset; the user owns the AA mode and can
        // cycle with B if they want to track the current display.
        _ = active.consumeMonitorChanged();

        if (active.isKeyPressed(KEY_R)) rotate = !rotate;
        if (active.isKeyPressed(KEY_ESCAPE)) break;
        if (active.isKeyPressed(KEY_B)) {
            current_order = cycleSubpixelOrder(current_order);
            std.debug.print("\naa={s}\n", .{aaName(current_order)});
        }
        if (active.isKeyPressed(KEY_C)) {
            const next = nextBackend(active.backend);
            if (next != active.backend) {
                releasePrepared(&prepared);
                try active.switchTo(next);
                uploaded_size = .{ 0, 0, 0, 0 };
                last_presentation = null;
                last_time = active.getTime();
                frame_count = 0;
                std.debug.print("\nBackend: {s}\n", .{backendLabel(active.backend)});
                warnIfDebugCpu(active.backend);
                continue;
            }
        }
        if (rotate) angle += dt * 0.5;
        if (active.isKeyDown(KEY_Z)) zoom *= 1.0 + dt * 2.0;
        if (active.isKeyDown(KEY_X)) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (active.isKeyDown(KEY_LEFT)) pan_x += pan_step;
        if (active.isKeyDown(KEY_RIGHT)) pan_x -= pan_step;
        if (active.isKeyDown(KEY_UP)) pan_y += pan_step;
        if (active.isKeyDown(KEY_DOWN)) pan_y -= pan_step;

        const present = active.presentationInfo();
        if (last_presentation == null or !std.meta.eql(last_presentation.?, present)) {
            logPresentationInfo(present);
            last_presentation = present;
        }
        const size = present.logical_size;
        const fb_size = present.framebuffer_size;
        const target_encoding = displayTargetEncoding(present);
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        const viewport_w: f32 = @floatFromInt(fb_size[0]);
        const viewport_h: f32 = @floatFromInt(fb_size[1]);
        if (w < 1.0 or h < 1.0 or viewport_w < 1.0 or viewport_h < 1.0) continue;

        const layout = demo_banner.buildLayout(w, h);
        const grid = snail.PixelGrid.init(.{ w, h }, fb_size);
        const size_key = [4]u32{ size[0], size[1], fb_size[0], fb_size[1] };

        // On resize/backend switch: lay out text to collect decoration rects,
        // rebuild path picture, and rebuild immutable scene resources.
        const needs_resource_rebuild = prepared == null or path_picture == null or text_blob == null or !std.mem.eql(u32, size_key[0..], uploaded_size[0..]);
        if (needs_resource_rebuild) {
            releasePrepared(&prepared);
            if (path_picture) |*picture| {
                picture.deinit();
                path_picture = null;
            }
            if (text_blob) |*blob| {
                blob.deinit();
                text_blob = null;
            }

            var builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
            defer builder.deinit();
            var dec_rects: [8]snail.Rect = undefined;
            const text_result = demo_banner_scene.buildTextBlob(&builder, layout, grid, &scene_assets, &dec_rects);

            text_blob = try builder.finish();
            path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, &scene_assets, dec_rects[0..text_result.decoration_count]);
            uploaded_size = size_key;
            scene.reset();
            if (path_picture) |*picture| try scene.addPath(.{ .picture = picture });
            if (text_blob) |*blob| try scene.addText(.{ .blob = blob });

            var resource_entries: [8]snail.ResourceSet.Entry = undefined;
            var resources = snail.ResourceSet.init(&resource_entries);
            try resources.addScene(&scene);
            prepared = try active.renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
        }

        const clear_srgb = demo_banner.clearColor();
        if (!active.beginFrame(fb_size, clear_srgb, target_encoding)) continue;

        const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_transform = snail.Mat4.multiply(
            snail.Mat4.translate(pan_x, pan_y, 0),
            snail.Mat4.multiply(
                snail.Mat4.translate(cx, cy, 0),
                snail.Mat4.multiply(snail.Mat4.scaleUniform(zoom), snail.Mat4.multiply(
                    snail.Mat4.rotateZ(angle),
                    snail.Mat4.translate(-cx, -cy, 0),
                )),
            ),
        );
        const mvp = snail.Mat4.multiply(projection, scene_transform);
        const draw_options = snail.DrawOptions{
            .mvp = mvp,
            .target = .{
                .pixel_width = viewport_w,
                .pixel_height = viewport_h,
                .subpixel_order = current_order,
                .will_resample = present.will_resample,
                .encoding = target_encoding,
                .coverage_transfer = snail.CoverageTransfer.power(0.9),
            },
        };
        const needed = snail.DrawList.estimate(&scene, draw_options);
        const needed_segments = snail.DrawList.estimateSegments(&scene, draw_options);
        if (draw_buf.len < needed) {
            if (draw_buf.len > 0) allocator.free(draw_buf);
            draw_buf = try allocator.alloc(u32, needed);
        }
        if (draw_segments_buf.len < needed_segments) {
            if (draw_segments_buf.len > 0) allocator.free(draw_segments_buf);
            draw_segments_buf = try allocator.alloc(snail.DrawSegment, needed_segments);
        }
        var draw = snail.DrawList.init(draw_buf[0..needed], draw_segments_buf[0..needed_segments]);
        try draw.addScene(&prepared.?, &scene, draw_options);
        try active.renderer.draw(&prepared.?, draw.slice(), draw_options);

        if (frame_count == 2) {
            active.captureDebugFrame(allocator, fb_size);
        }
        if (frame_count % 60 == 0 and fps_display > 0.0) {
            const glyphs = if (text_blob) |*blob| blob.glyphCount() else 0;
            std.debug.print("\rFPS: {d:.0}  Backend: {s}  Glyphs: {}   ", .{ fps_display, active.renderer.backendName(), glyphs });
        }
        frame_count += 1;

        active.endFrame();
    }
}

test {
    _ = @import("snail");
}
