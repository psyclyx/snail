const std = @import("std");
const snail = @import("snail");
const SubpixelOrder = snail.SubpixelOrder;
pub const presentation = @import("presentation.zig");
const wayland = @import("wayland.zig");
const c = wayland.c;

pub const KEY_R = wayland.KEY_R;
pub const KEY_L = wayland.KEY_L;
pub const KEY_Z = wayland.KEY_Z;
pub const KEY_X = wayland.KEY_X;
pub const KEY_H = wayland.KEY_H;
pub const KEY_B = wayland.KEY_B;
pub const KEY_ESCAPE = wayland.KEY_ESCAPE;
pub const KEY_LEFT = wayland.KEY_LEFT;
pub const KEY_RIGHT = wayland.KEY_RIGHT;
pub const KEY_UP = wayland.KEY_UP;
pub const KEY_DOWN = wayland.KEY_DOWN;

var app: ?*wayland.Window = null;
var owns_window: bool = false;
const presentation_buffer_count = 2;
const PresentationBuffer = struct {
    pool: ?*c.wl_shm_pool = null,
    fd: std.posix.fd_t = -1,
    map: ?[]align(std.heap.page_size_min) u8 = null,
    size: usize = 0,
    wl_buffer: ?*c.wl_buffer = null,
    busy: bool = false,
};

var presentation_buffers = [_]PresentationBuffer{.{}} ** presentation_buffer_count;
var next_presentation_buffer: usize = 0;
var frame_callback: ?*c.wl_callback = null;
var frame_pending: bool = false;
var presentation_failed: bool = false;
var pixel_ptr: ?[*]u8 = null;
var render_buf: ?[]u8 = null; // separate RGBA buffer for CpuRenderer
var buf_width: u32 = 0;
var buf_height: u32 = 0;

pub fn init(width: u32, height: u32, title: [*:0]const u8) !void {
    const window = try wayland.Window.init(width, height, title);
    errdefer window.deinit();

    app = window;
    owns_window = true;
    errdefer {
        app = null;
        owns_window = false;
    }

    try initForCurrentWindow();
}

pub fn initForWindow(window: *wayland.Window) !void {
    app = window;
    owns_window = false;
    errdefer {
        app = null;
        owns_window = false;
    }

    try initForCurrentWindow();
}

fn initForCurrentWindow() !void {
    presentation_failed = false;

    const fb_size = app.?.getFramebufferSize();
    try createShmBuffer(fb_size[0], fb_size[1]);
}

pub fn deinit() void {
    if (app) |window| {
        const owned = owns_window;
        // Do not attach null here: that unmaps the xdg_toplevel, and the
        // next backend would need a fresh configure before attaching pixels.
        destroyShmBuffer();
        if (owned) window.deinit();
        app = null;
        owns_window = false;
    }
}

pub fn shouldClose() bool {
    if (presentation_failed) return true;
    if (app) |window| {
        waitForFrameCallback(window);
        window.pumpEvents();
        if (window.consumeResized() or window.consumeScaleChanged()) {
            const size = window.getFramebufferSize();
            destroyShmBuffer();
            createShmBuffer(size[0], size[1]) catch |err| {
                std.debug.print("snail: CPU presentation resize failed: {s}\n", .{@errorName(err)});
                presentation_failed = true;
                return true;
            };
        }
        return window.shouldClose();
    }
    return true;
}

/// Returns a pointer to the RGBA8888 pixel buffer for CPU rendering.
pub fn getPixelBuffer() ?[*]u8 {
    return pixel_ptr;
}

pub fn getBufferSize() [2]u32 {
    return .{ buf_width, buf_height };
}

/// Commit the current pixel buffer to the Wayland surface.
pub fn swapBuffers() void {
    if (app) |window| {
        if (acquirePresentationBuffer(window)) |present| {
            // Convert RGBA (CpuRenderer) → BGRA (ARGB8888 little-endian) into shm buffer
            if (render_buf) |src| {
                if (present.map) |dst_slice| {
                    const dst = dst_slice.ptr;
                    const total = @as(usize, buf_width) * buf_height;
                    var i: usize = 0;
                    while (i < total) : (i += 1) {
                        const off = i * 4;
                        dst[off + 0] = src[off + 2]; // B
                        dst[off + 1] = src[off + 1]; // G
                        dst[off + 2] = src[off + 0]; // R
                        dst[off + 3] = src[off + 3]; // A
                    }
                }
            }
            const callback = c.wl_surface_frame(window.surface);
            if (callback) |cb| {
                if (frame_callback) |old| c.wl_callback_destroy(old);
                frame_callback = cb;
                frame_pending = true;
                _ = c.wl_callback_add_listener(cb, &frame_listener, null);
            }
            const buf = present.wl_buffer orelse return;
            present.busy = true;
            c.wl_surface_attach(window.surface, buf, 0, 0);
            c.wl_surface_damage_buffer(window.surface, 0, 0, @intCast(buf_width), @intCast(buf_height));
            c.wl_surface_commit(window.surface);
            _ = c.wl_display_flush(window.display);
        }
    }
}

pub fn clear(r: f32, g: f32, b: f32, a: f32) void {
    // CpuRenderer handles clearing internally; this is a no-op.
    _ = r;
    _ = g;
    _ = b;
    _ = a;
}

pub fn getWindowSize() [2]u32 {
    if (app) |window| return window.getWindowSize();
    return .{ 0, 0 };
}

pub fn getFramebufferSize() [2]u32 {
    return getBufferSize();
}

pub fn presentationInfo() presentation.Info {
    if (app) |window| {
        return .{
            .logical_size = window.getWindowSize(),
            .framebuffer_size = window.getFramebufferSize(),
            .buffer_scale = window.getBufferScale(),
            .framebuffer_encoding = .linear,
            .will_resample = false,
        };
    }
    return .{ .framebuffer_encoding = .linear };
}

pub fn getTime() f64 {
    return wayland.getTime();
}

pub fn isKeyDown(key: u32) bool {
    if (app) |window| return window.isKeyDown(key);
    return false;
}

pub fn isKeyPressed(key: u32) bool {
    if (app) |window| return window.isKeyPressed(key);
    return false;
}

pub fn consumeMonitorChanged() bool {
    if (app) |window| return window.consumeMonitorChanged();
    return false;
}

pub fn detectCurrentMonitorSubpixelOrder(base: SubpixelOrder) SubpixelOrder {
    if (app) |window| return window.currentSubpixelOrder(base);
    return base;
}

// ── wl_shm buffer management ──

fn waitForFrameCallback(window: *wayland.Window) void {
    while (frame_pending and !window.shouldClose()) {
        if (c.wl_display_dispatch(window.display) < 0) {
            frame_pending = false;
            break;
        }
    }
}

fn acquirePresentationBuffer(window: *wayland.Window) ?*PresentationBuffer {
    while (!window.shouldClose()) {
        for (0..presentation_buffer_count) |offset| {
            const idx = (next_presentation_buffer + offset) % presentation_buffer_count;
            if (presentation_buffers[idx].wl_buffer != null and !presentation_buffers[idx].busy) {
                next_presentation_buffer = (idx + 1) % presentation_buffer_count;
                return &presentation_buffers[idx];
            }
        }
        if (c.wl_display_dispatch(window.display) < 0) return null;
    }
    return null;
}

fn createShmBuffer(width: u32, height: u32) !void {
    const window = app orelse return error.NoWindow;

    const stride = width * 4;
    const size = @as(usize, stride) * height;

    // CpuRenderer writes RGBA; we convert to BGRA in swapBuffers
    render_buf = try std.heap.c_allocator.alloc(u8, size);
    errdefer {
        std.heap.c_allocator.free(render_buf.?);
        render_buf = null;
    }
    errdefer for (&presentation_buffers) |*buffer| destroyPresentationBuffer(buffer);
    for (&presentation_buffers) |*buffer| {
        try createPresentationBuffer(window, buffer, width, height, stride, size);
    }
    pixel_ptr = render_buf.?.ptr;
    buf_width = width;
    buf_height = height;
    next_presentation_buffer = 0;
}

fn createPresentationBuffer(window: *wayland.Window, out: *PresentationBuffer, width: u32, height: u32, stride: u32, size: usize) !void {
    const wl_shm = window.shm orelse return error.NoShm;

    out.fd = try std.posix.memfd_create("snail-cpu", 0);
    errdefer {
        _ = std.c.close(out.fd);
        out.fd = -1;
    }
    if (std.c.ftruncate(out.fd, @intCast(size)) != 0) return error.FtruncateFailed;

    out.map = try std.posix.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, out.fd, 0);
    errdefer {
        std.posix.munmap(out.map.?);
        out.map = null;
    }
    out.size = size;

    out.pool = c.wl_shm_create_pool(wl_shm, out.fd, @intCast(size)) orelse return error.ShmPoolFailed;
    errdefer {
        c.wl_shm_pool_destroy(out.pool.?);
        out.pool = null;
    }

    const WL_SHM_FORMAT_XRGB8888 = 1;
    out.wl_buffer = c.wl_shm_pool_create_buffer(
        out.pool.?,
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        WL_SHM_FORMAT_XRGB8888,
    ) orelse return error.BufferCreateFailed;
    out.busy = false;
    _ = c.wl_buffer_add_listener(out.wl_buffer.?, &buffer_listener, out);
}

fn destroyShmBuffer() void {
    if (frame_callback) |cb| {
        c.wl_callback_destroy(cb);
        frame_callback = null;
        frame_pending = false;
    }
    for (&presentation_buffers) |*buffer| destroyPresentationBuffer(buffer);
    if (render_buf) |rb| {
        std.heap.c_allocator.free(rb);
        render_buf = null;
    }
    pixel_ptr = null;
    buf_width = 0;
    buf_height = 0;
    next_presentation_buffer = 0;
    presentation_failed = false;
}

fn destroyPresentationBuffer(buffer: *PresentationBuffer) void {
    if (buffer.wl_buffer) |buf| c.wl_buffer_destroy(buf);
    if (buffer.pool) |pool| c.wl_shm_pool_destroy(pool);
    if (buffer.map) |map| std.posix.munmap(map);
    if (buffer.fd >= 0) _ = std.c.close(buffer.fd);
    buffer.* = .{};
}

fn bufferRelease(data: ?*anyopaque, _: ?*c.wl_buffer) callconv(.c) void {
    const buffer: *PresentationBuffer = @ptrCast(@alignCast(data.?));
    buffer.busy = false;
}

const buffer_listener = c.wl_buffer_listener{
    .release = bufferRelease,
};

fn frameDone(_: ?*anyopaque, callback: ?*c.wl_callback, _: u32) callconv(.c) void {
    if (callback) |cb| c.wl_callback_destroy(cb);
    if (frame_callback == callback) frame_callback = null;
    frame_pending = false;
}

const frame_listener = c.wl_callback_listener{
    .done = frameDone,
};
