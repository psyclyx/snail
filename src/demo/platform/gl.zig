const std = @import("std");
const build_options = @import("build_options");
const egl_common = @import("egl.zig");
const snail = @import("snail");
const SubpixelOrder = snail.SubpixelOrder;
pub const presentation = @import("presentation.zig");
const wayland = @import("wayland.zig");
pub const gl = @import("support").gl;

const egl = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cInclude("wayland-egl.h");
});

pub const GlApi = egl_common.GlApi;
pub const KEY_R = wayland.KEY_R;
pub const KEY_L = wayland.KEY_L;
pub const KEY_W = wayland.KEY_W;
pub const KEY_A = wayland.KEY_A;
pub const KEY_S = wayland.KEY_S;
pub const KEY_D = wayland.KEY_D;
pub const KEY_Q = wayland.KEY_Q;
pub const KEY_E = wayland.KEY_E;
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
var egl_display: egl.EGLDisplay = egl.EGL_NO_DISPLAY;
var egl_context: egl.EGLContext = egl.EGL_NO_CONTEXT;
var egl_surface: egl.EGLSurface = egl.EGL_NO_SURFACE;
var egl_window: ?*egl.wl_egl_window = null;
var window_surface_encoding: presentation.ColorEncoding = .linear;
var active_api: GlApi = .gl33;

const CreatedSurface = struct {
    surface: egl.EGLSurface,
    encoding: presentation.ColorEncoding,
};

pub fn init(width: u32, height: u32, title: [*:0]const u8, api: GlApi) !void {
    const window = try wayland.Window.init(width, height, title);
    errdefer window.deinit();

    app = window;
    owns_window = true;
    errdefer {
        app = null;
        owns_window = false;
    }

    try initForCurrentWindow(api);
}

pub fn initForWindow(window: *wayland.Window, api: GlApi) !void {
    app = window;
    owns_window = false;
    errdefer {
        app = null;
        owns_window = false;
    }

    try initForCurrentWindow(api);
}

fn initForCurrentWindow(api: GlApi) !void {
    active_api = api;
    egl_display = try initEglDisplay(api);
    errdefer {
        _ = egl.eglTerminate(egl_display);
        egl_display = egl.EGL_NO_DISPLAY;
        active_api = .gl33;
    }

    var config: egl.EGLConfig = null;
    try egl_common.chooseConfig(egl, egl_display, egl.EGL_WINDOW_BIT, api, &config);

    egl_context = try egl_common.createOpenGlContext(egl, api, egl_display, config);
    errdefer {
        _ = egl.eglDestroyContext(egl_display, egl_context);
        egl_context = egl.EGL_NO_CONTEXT;
    }

    const fb_size = app.?.getFramebufferSize();
    egl_window = egl.wl_egl_window_create(@ptrCast(app.?.surface), @intCast(fb_size[0]), @intCast(fb_size[1])) orelse return error.EglSurfaceCreateFailed;
    errdefer {
        egl.wl_egl_window_destroy(egl_window.?);
        egl_window = null;
    }

    const created_surface = createWindowSurface(egl_display, config, @as(egl.EGLNativeWindowType, @intCast(@intFromPtr(egl_window.?)))) orelse return error.EglSurfaceCreateFailed;
    egl_surface = created_surface.surface;
    window_surface_encoding = created_surface.encoding;
    errdefer {
        _ = egl.eglDestroySurface(egl_display, egl_surface);
        egl_surface = egl.EGL_NO_SURFACE;
        window_surface_encoding = .linear;
    }

    if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) == egl.EGL_FALSE) {
        return error.EglMakeCurrentFailed;
    }

    _ = egl.eglSwapInterval(egl_display, 1);
}

// Prefer an sRGB EGL window surface on every GL API so the fragment stage can
// emit linear color and rely on fixed-function sRGB conversion on store. This
// matches the Vulkan swapchain choice; without it, the renderer falls back to
// shader-side sRGB encoding into a linear surface, which forces alpha blending
// to happen in storage (gamma) space and renders translucent edges darker.
fn createWindowSurface(display: egl.EGLDisplay, config: egl.EGLConfig, native_window: egl.EGLNativeWindowType) ?CreatedSurface {
    return createSrgbWindowSurface(display, config, native_window) orelse
        createLinearWindowSurface(display, config, native_window) orelse
        createDefaultWindowSurface(display, config, native_window);
}

fn createSrgbWindowSurface(display: egl.EGLDisplay, config: egl.EGLConfig, native_window: egl.EGLNativeWindowType) ?CreatedSurface {
    if (hasExtension(display, "EGL_KHR_gl_colorspace")) {
        const attrs = [_]egl.EGLint{
            egl.EGL_GL_COLORSPACE_KHR, egl.EGL_GL_COLORSPACE_SRGB_KHR,
            egl.EGL_NONE,
        };
        const surface = egl.eglCreateWindowSurface(display, config, native_window, &attrs);
        if (surface != egl.EGL_NO_SURFACE) return .{ .surface = surface, .encoding = .srgb };
    }
    return null;
}

fn createLinearWindowSurface(display: egl.EGLDisplay, config: egl.EGLConfig, native_window: egl.EGLNativeWindowType) ?CreatedSurface {
    if (hasExtension(display, "EGL_KHR_gl_colorspace")) {
        const attrs = [_]egl.EGLint{
            egl.EGL_GL_COLORSPACE_KHR, egl.EGL_GL_COLORSPACE_LINEAR_KHR,
            egl.EGL_NONE,
        };
        const surface = egl.eglCreateWindowSurface(display, config, native_window, &attrs);
        if (surface != egl.EGL_NO_SURFACE) return .{ .surface = surface, .encoding = .linear };
    }
    return null;
}

fn createDefaultWindowSurface(display: egl.EGLDisplay, config: egl.EGLConfig, native_window: egl.EGLNativeWindowType) ?CreatedSurface {
    const surface = egl.eglCreateWindowSurface(display, config, native_window, null);
    if (surface == egl.EGL_NO_SURFACE) return null;
    return .{ .surface = surface, .encoding = .linear };
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
        const owned = owns_window;
        _ = egl.eglMakeCurrent(egl_display, egl.EGL_NO_SURFACE, egl.EGL_NO_SURFACE, egl.EGL_NO_CONTEXT);
        if (egl_surface != egl.EGL_NO_SURFACE) _ = egl.eglDestroySurface(egl_display, egl_surface);
        if (egl_window) |win| egl.wl_egl_window_destroy(win);
        if (egl_context != egl.EGL_NO_CONTEXT) _ = egl.eglDestroyContext(egl_display, egl_context);
        if (egl_display != egl.EGL_NO_DISPLAY) _ = egl.eglTerminate(egl_display);
        egl_surface = egl.EGL_NO_SURFACE;
        egl_context = egl.EGL_NO_CONTEXT;
        egl_display = egl.EGL_NO_DISPLAY;
        egl_window = null;
        window_surface_encoding = .linear;
        active_api = .gl33;
        if (owned) window.deinit();
        app = null;
        owns_window = false;
    }
}

pub fn shouldClose() bool {
    if (app) |window| {
        window.pumpEvents();
        if (window.consumeResized() or window.consumeScaleChanged()) {
            const size = window.getFramebufferSize();
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

pub fn getFramebufferSize() [2]u32 {
    if (app) |window| return window.getFramebufferSize();
    return .{ 0, 0 };
}

pub fn presentationInfo() presentation.Info {
    if (app) |window| {
        return .{
            .logical_size = window.getWindowSize(),
            .framebuffer_size = window.getFramebufferSize(),
            .buffer_scale = window.getBufferScale(),
            .framebuffer_encoding = defaultFramebufferEncoding(),
            .will_resample = false,
        };
    }
    return .{ .framebuffer_encoding = defaultFramebufferEncoding() };
}

pub fn defaultFramebufferEncoding() presentation.ColorEncoding {
    return switch (active_api) {
        .gl33, .gl44 => {
            if (window_surface_encoding == .srgb) return .srgb;
            return queryDefaultFramebufferEncoding() orelse .linear;
        },
        // GLES has no GL_FRAMEBUFFER_SRGB toggle; sRGB conversion is governed
        // by the actual attachment encoding. NVIDIA's Wayland EGL accepts the
        // EGL_GL_COLORSPACE_SRGB_KHR request but delivers a linear default
        // framebuffer, and the GL query honestly reports it. Trust the query.
        // When it reports linear, the demo renderer falls back to the existing
        // beginLinearResolve / endLinearResolve path.
        .gles30 => queryDefaultFramebufferEncoding() orelse window_surface_encoding,
    };
}

fn queryDefaultFramebufferEncoding() ?presentation.ColorEncoding {
    var prev_draw_fb: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw_fb);
    gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, 0);
    defer gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(prev_draw_fb));

    // Desktop GL exposes GL_BACK_LEFT; GLES 3.0's default fb is GL_BACK.
    const attachment: gl.GLenum = switch (active_api) {
        .gl33, .gl44 => @intCast(gl.GL_BACK_LEFT),
        .gles30 => @intCast(gl.GL_BACK),
    };
    while (gl.glGetError() != gl.GL_NO_ERROR) {}
    var encoding: gl.GLint = 0;
    gl.glGetFramebufferAttachmentParameteriv(gl.GL_DRAW_FRAMEBUFFER, attachment, gl.GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING, &encoding);
    if (gl.glGetError() != gl.GL_NO_ERROR) return null;
    if (encoding == gl.GL_SRGB) return .srgb;
    if (encoding == gl.GL_LINEAR) return .linear;
    return null;
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

fn initEglDisplay(api: GlApi) !egl.EGLDisplay {
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
    try egl_common.bindApi(egl, api);
    return display;
}
