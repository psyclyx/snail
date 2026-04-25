const std = @import("std");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;
const wayland = @import("wayland_window.zig");
const c = wayland.c;

pub const KEY_R = wayland.KEY_R;
pub const KEY_S = wayland.KEY_S;
pub const KEY_D = wayland.KEY_D;
pub const KEY_L = wayland.KEY_L;
pub const KEY_M = wayland.KEY_M;
pub const KEY_Z = wayland.KEY_Z;
pub const KEY_X = wayland.KEY_X;
pub const KEY_ESCAPE = wayland.KEY_ESCAPE;
pub const KEY_LEFT = wayland.KEY_LEFT;
pub const KEY_RIGHT = wayland.KEY_RIGHT;
pub const KEY_UP = wayland.KEY_UP;
pub const KEY_DOWN = wayland.KEY_DOWN;

var app: ?*wayland.Window = null;
var shm_pool: ?*c.wl_shm_pool = null;
var shm_fd: std.posix.fd_t = -1;
var shm_map: ?[*]align(std.heap.page_size_min) u8 = null;
var shm_size: usize = 0;
var wl_buffer: ?*c.wl_buffer = null;
var pixel_ptr: ?[*]u8 = null;
var buf_width: u32 = 0;
var buf_height: u32 = 0;

pub fn init(width: u32, height: u32, title: [*:0]const u8) !void {
    app = try wayland.Window.init(width, height, title);
    errdefer {
        var doomed = app.?;
        doomed.deinit();
        app = null;
    }

    try createShmBuffer(width, height);
}

pub fn deinit() void {
    if (app) |window| {
        destroyShmBuffer();
        window.deinit();
        app = null;
    }
}

pub fn shouldClose() bool {
    if (app) |window| {
        window.pumpEvents();
        if (window.consumeResized()) {
            const size = window.getWindowSize();
            destroyShmBuffer();
            createShmBuffer(size[0], size[1]) catch {};
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
        if (wl_buffer) |buf| {
            // Convert RGBA → ARGB (Wayland expects ARGB8888 in native byte order)
            const total = @as(usize, buf_width) * buf_height;
            if (pixel_ptr) |px| {
                var i: usize = 0;
                while (i < total) : (i += 1) {
                    const off = i * 4;
                    const r = px[off + 0];
                    const g = px[off + 1];
                    const b = px[off + 2];
                    const a = px[off + 3];
                    px[off + 0] = b;
                    px[off + 1] = g;
                    px[off + 2] = r;
                    px[off + 3] = a;
                }
            }
            c.wl_surface_attach(window.surface, buf, 0, 0);
            c.wl_surface_damage_buffer(window.surface, 0, 0, @intCast(buf_width), @intCast(buf_height));
            c.wl_surface_commit(window.surface);
            _ = c.wl_display_flush(window.display);
        }
    }
}

pub fn clear(r: f32, g: f32, b: f32, a: f32) void {
    _ = r;
    _ = g;
    _ = b;
    _ = a;
    // CpuRenderer handles clearing
}

pub fn getWindowSize() [2]u32 {
    if (app) |window| return window.getWindowSize();
    return .{ 0, 0 };
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

fn createShmBuffer(width: u32, height: u32) !void {
    const window = app orelse return error.NoWindow;
    const wl_shm = window.shm orelse return error.NoShm;

    const stride = width * 4;
    const size = @as(usize, stride) * height;

    // Create anonymous shared memory
    shm_fd = try std.posix.memfd_create("snail-cpu", .{});
    errdefer {
        std.posix.close(shm_fd);
        shm_fd = -1;
    }
    try std.posix.ftruncate(shm_fd, @intCast(size));

    shm_map = try std.posix.mmap(null, size, .{ .read = true, .write = true }, .{ .TYPE = .SHARED }, shm_fd, 0);
    shm_size = size;

    shm_pool = c.wl_shm_create_pool(wl_shm, shm_fd, @intCast(size)) orelse return error.ShmPoolFailed;

    // ARGB8888 format (Wayland standard)
    const WL_SHM_FORMAT_ARGB8888 = 0;
    wl_buffer = c.wl_shm_pool_create_buffer(
        shm_pool.?,
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        WL_SHM_FORMAT_ARGB8888,
    ) orelse return error.BufferCreateFailed;

    pixel_ptr = @ptrCast(shm_map.?);
    buf_width = width;
    buf_height = height;
}

fn destroyShmBuffer() void {
    if (wl_buffer) |buf| {
        c.wl_buffer_destroy(buf);
        wl_buffer = null;
    }
    if (shm_pool) |pool| {
        c.wl_shm_pool_destroy(pool);
        shm_pool = null;
    }
    if (shm_map) |map| {
        std.posix.munmap(map[0..shm_size]);
        shm_map = null;
    }
    if (shm_fd >= 0) {
        std.posix.close(shm_fd);
        shm_fd = -1;
    }
    pixel_ptr = null;
    buf_width = 0;
    buf_height = 0;
    shm_size = 0;
}
