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
/// Pointer into the currently-acquired shm buffer's mmap region. The
/// CPU renderer rasterizes directly into this — there is no intermediate
/// staging buffer. Rotates between `presentation_buffers[0..N]` as the
/// compositor releases each one.
var pixel_ptr: ?[*]u8 = null;
/// Buffer `pixel_ptr` currently points into. Set by `beginFrame()`,
/// cleared by `swapBuffers()` after commit so the next `beginFrame()`
/// picks the next free buffer.
var current_buffer: ?*PresentationBuffer = null;
var buf_width: u32 = 0;
var buf_height: u32 = 0;

// wl_shm well-known format codes are 0/1; everything else uses the DRM
// fourcc. DRM_FORMAT_ABGR8888 = fourcc('A','B','2','4') describes a
// 32-bit word `A:B:G:R` MSB→LSB, which on little-endian memory is bytes
// R, G, B, A — exactly the byte order CpuRenderer writes. Picking this
// format lets us render straight into the shm buffer with no per-pixel
// swizzle on present (the previous WL_SHM_FORMAT_XRGB8888 = B,G,R,A in
// memory needed a ~3 ms per-frame conversion loop on the main thread).
const WL_SHM_FORMAT_ABGR8888: u32 = 0x34324241;

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
/// Valid between `beginFrame()` and `swapBuffers()`; null otherwise.
pub fn getPixelBuffer() ?[*]u8 {
    return pixel_ptr;
}

pub fn getBufferSize() [2]u32 {
    return .{ buf_width, buf_height };
}

/// Acquire the next free shm buffer for this frame. Blocks dispatching
/// Wayland events until the compositor releases one (back-pressure when
/// both buffers are still attached). Idempotent within a frame: if a
/// buffer is already acquired, returns its pointer without blocking.
///
/// The renderer writes into the returned RGBA buffer directly; `swapBuffers`
/// then attaches it without any per-pixel copy.
pub fn beginFrame() ?[*]u8 {
    if (current_buffer != null) return pixel_ptr;
    const window = app orelse return null;
    const buf = acquirePresentationBuffer(window) orelse return null;
    current_buffer = buf;
    if (buf.map) |m| {
        pixel_ptr = m.ptr;
        return m.ptr;
    }
    pixel_ptr = null;
    return null;
}

/// Commit the currently-acquired buffer to the Wayland surface. With
/// ABGR8888 the in-memory layout already matches what the CPU renderer
/// wrote, so this is just attach + damage + commit — no per-pixel copy
/// or format swizzle. After commit, `pixel_ptr` is cleared and the next
/// `beginFrame()` rotates to the other buffer in the pair.
pub fn swapBuffers() void {
    const window = app orelse return;
    const present = current_buffer orelse return;
    const buf = present.wl_buffer orelse return;
    const callback = c.wl_surface_frame(window.surface);
    if (callback) |cb| {
        if (frame_callback) |old| c.wl_callback_destroy(old);
        frame_callback = cb;
        frame_pending = true;
        _ = c.wl_callback_add_listener(cb, &frame_listener, null);
    }
    // Register a wp_presentation_feedback for the upcoming commit.
    // The compositor will fire `presented` (or `discarded`) when this
    // surface state is actually shown; that timestamp is what the HUD
    // cadence histogram is bucketed against. No-op when the compositor
    // doesn't advertise wp_presentation.
    window.requestPresentationFeedback();
    present.busy = true;
    c.wl_surface_attach(window.surface, buf, 0, 0);
    c.wl_surface_damage_buffer(window.surface, 0, 0, @intCast(buf_width), @intCast(buf_height));
    c.wl_surface_commit(window.surface);
    _ = c.wl_display_flush(window.display);
    current_buffer = null;
    pixel_ptr = null;
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
    // wl_shm XRGB8888 is implicitly sRGB-encoded — report sRGB so the CPU
    // renderer blends in linear space and sRGB-encodes on write, matching
    // GL/Vulkan rather than naively blending in storage (gamma) space.
    if (app) |window| {
        return .{
            .logical_size = window.getWindowSize(),
            .framebuffer_size = window.getFramebufferSize(),
            .buffer_scale = window.getBufferScale(),
            .framebuffer_encoding = .srgb,
            .will_resample = false,
        };
    }
    return .{ .framebuffer_encoding = .srgb };
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

    errdefer for (&presentation_buffers) |*buffer| destroyPresentationBuffer(buffer);
    for (&presentation_buffers) |*buffer| {
        try createPresentationBuffer(window, buffer, width, height, stride, size);
    }
    buf_width = width;
    buf_height = height;
    next_presentation_buffer = 0;
    // Eagerly own the first buffer so `getPixelBuffer()` returns a valid
    // pointer between window init and the first frame's `beginFrame`.
    // `presentation_buffers[0]` was just created and is not yet busy.
    current_buffer = &presentation_buffers[0];
    pixel_ptr = if (presentation_buffers[0].map) |m| m.ptr else null;
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

    out.wl_buffer = c.wl_shm_pool_create_buffer(
        out.pool.?,
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        WL_SHM_FORMAT_ABGR8888,
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
    current_buffer = null;
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
