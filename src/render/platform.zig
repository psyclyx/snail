const std = @import("std");
const build_options = @import("build_options");
const egl_common = @import("egl_common.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;
const wayland = @import("wayland_window.zig");
pub const gl = @import("gl.zig").gl;

const egl = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cInclude("wayland-egl.h");
});

pub const KEY_R = wayland.KEY_R;
pub const KEY_S = wayland.KEY_S;
pub const KEY_D = wayland.KEY_D;
pub const KEY_L = wayland.KEY_L;
pub const KEY_Z = wayland.KEY_Z;
pub const KEY_X = wayland.KEY_X;
pub const KEY_ESCAPE = wayland.KEY_ESCAPE;
pub const KEY_LEFT = wayland.KEY_LEFT;
pub const KEY_RIGHT = wayland.KEY_RIGHT;
pub const KEY_UP = wayland.KEY_UP;
pub const KEY_DOWN = wayland.KEY_DOWN;

var app: ?*wayland.Window = null;
var egl_display: egl.EGLDisplay = egl.EGL_NO_DISPLAY;
var egl_context: egl.EGLContext = egl.EGL_NO_CONTEXT;
var egl_surface: egl.EGLSurface = egl.EGL_NO_SURFACE;
var egl_window: ?*egl.wl_egl_window = null;

pub fn init(width: u32, height: u32, title: [*:0]const u8) !void {
    app = try wayland.Window.init(width, height, title);
    errdefer {
        var doomed = app.?;
        doomed.deinit();
        app = null;
    }

    egl_display = try initEglDisplay();
    errdefer {
        _ = egl.eglTerminate(egl_display);
        egl_display = egl.EGL_NO_DISPLAY;
    }

    var config: egl.EGLConfig = null;
    try egl_common.chooseConfig(egl, egl_display, egl.EGL_WINDOW_BIT, &config);

    egl_context = try egl_common.createOpenGlContext(egl, build_options.force_gl33, egl_display, config);
    errdefer {
        _ = egl.eglDestroyContext(egl_display, egl_context);
        egl_context = egl.EGL_NO_CONTEXT;
    }

    const size = app.?.getWindowSize();
    egl_window = egl.wl_egl_window_create(@ptrCast(app.?.surface), @intCast(size[0]), @intCast(size[1])) orelse return error.EglSurfaceCreateFailed;
    errdefer {
        egl.wl_egl_window_destroy(egl_window.?);
        egl_window = null;
    }

    egl_surface = createWindowSurface(egl_display, config, @as(egl.EGLNativeWindowType, @intCast(@intFromPtr(egl_window.?))));
    if (egl_surface == egl.EGL_NO_SURFACE) return error.EglSurfaceCreateFailed;
    errdefer {
        _ = egl.eglDestroySurface(egl_display, egl_surface);
        egl_surface = egl.EGL_NO_SURFACE;
    }

    if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) == egl.EGL_FALSE) {
        return error.EglMakeCurrentFailed;
    }

    _ = egl.eglSwapInterval(egl_display, 1);
}

fn createWindowSurface(display: egl.EGLDisplay, config: egl.EGLConfig, native_window: egl.EGLNativeWindowType) egl.EGLSurface {
    if (hasExtension(display, "EGL_KHR_gl_colorspace")) {
        const attrs = [_]egl.EGLint{
            egl.EGL_GL_COLORSPACE_KHR, egl.EGL_GL_COLORSPACE_SRGB_KHR,
            egl.EGL_NONE,
        };
        const surface = egl.eglCreateWindowSurface(display, config, native_window, &attrs);
        if (surface != egl.EGL_NO_SURFACE) return surface;
    }
    return egl.eglCreateWindowSurface(display, config, native_window, null);
}

fn hasExtension(display: egl.EGLDisplay, name: []const u8) bool {
    const ext_ptr = egl.eglQueryString(display, egl.EGL_EXTENSIONS);
    if (ext_ptr == null) return false;
    const exts = std.mem.span(ext_ptr);

    var it = std.mem.tokenizeScalar(u8, exts, ' ');
    while (it.next()) |ext| {
        if (std.mem.eql(u8, ext, name)) return true;
    }
    return false;
}

pub fn consumeMonitorChanged() bool {
    if (app) |window| return window.consumeMonitorChanged();
    return false;
}

pub fn detectCurrentMonitorSubpixelOrder(base: SubpixelOrder) SubpixelOrder {
    _ = build_options;
    if (app) |window| return window.currentSubpixelOrder(base);
    return base;
}

pub fn deinit() void {
    if (app) |window| {
        _ = egl.eglMakeCurrent(egl_display, egl.EGL_NO_SURFACE, egl.EGL_NO_SURFACE, egl.EGL_NO_CONTEXT);
        if (egl_surface != egl.EGL_NO_SURFACE) _ = egl.eglDestroySurface(egl_display, egl_surface);
        if (egl_window) |win| egl.wl_egl_window_destroy(win);
        if (egl_context != egl.EGL_NO_CONTEXT) _ = egl.eglDestroyContext(egl_display, egl_context);
        if (egl_display != egl.EGL_NO_DISPLAY) _ = egl.eglTerminate(egl_display);
        egl_surface = egl.EGL_NO_SURFACE;
        egl_context = egl.EGL_NO_CONTEXT;
        egl_display = egl.EGL_NO_DISPLAY;
        egl_window = null;
        window.deinit();
        app = null;
    }
}

pub fn shouldClose() bool {
    if (app) |window| {
        window.pumpEvents();
        if (window.consumeResized()) {
            const size = window.getWindowSize();
            if (egl_window) |win| {
                egl.wl_egl_window_resize(win, @intCast(size[0]), @intCast(size[1]), 0, 0);
            }
        }
        return window.shouldClose();
    }
    return true;
}

pub fn clear(r: f32, g: f32, b: f32, a: f32) void {
    gl.glClearColor(r, g, b, a);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
}

pub fn swapBuffers() void {
    _ = egl.eglSwapBuffers(egl_display, egl_surface);
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

fn initEglDisplay() !egl.EGLDisplay {
    const get_platform_display = @as(
        ?*const fn (egl.EGLenum, ?*anyopaque, ?[*]const egl.EGLint) callconv(.c) egl.EGLDisplay,
        @ptrCast(egl.eglGetProcAddress("eglGetPlatformDisplayEXT")),
    );

    var display: egl.EGLDisplay = egl.EGL_NO_DISPLAY;
    if (get_platform_display) |func| {
        display = func(egl.EGL_PLATFORM_WAYLAND_KHR, @ptrCast(app.?.display), null);
    }
    if (display == egl.EGL_NO_DISPLAY) {
        display = egl.eglGetDisplay(@ptrCast(app.?.display));
    }
    if (display == egl.EGL_NO_DISPLAY) return error.EglDisplayFailed;

    var major: egl.EGLint = 0;
    var minor: egl.EGLint = 0;
    if (egl.eglInitialize(display, &major, &minor) == egl.EGL_FALSE) return error.EglInitializeFailed;
    if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) return error.EglBindApiFailed;
    return display;
}
