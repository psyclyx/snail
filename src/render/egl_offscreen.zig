const std = @import("std");
const build_options = @import("build_options");
const egl_common = @import("egl_common.zig");

pub const egl = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
});

pub const Context = struct {
    display: egl.EGLDisplay = egl.EGL_NO_DISPLAY,
    config: egl.EGLConfig = null,
    context: egl.EGLContext = egl.EGL_NO_CONTEXT,
    surface: egl.EGLSurface = egl.EGL_NO_SURFACE,

    pub fn init(width: u32, height: u32) !Context {
        var self = Context{};
        try self.initDisplay();
        errdefer self.deinit();

        try egl_common.chooseConfig(egl, self.display, egl.EGL_PBUFFER_BIT, &self.config);
        self.surface = createPbufferSurface(self.display, self.config, width, height) orelse return error.EglSurfaceCreateFailed;
        self.context = try egl_common.createOpenGlContext(egl, build_options.force_gl33, self.display, self.config);
        if (egl.eglMakeCurrent(self.display, self.surface, self.surface, self.context) == egl.EGL_FALSE) {
            return error.EglMakeCurrentFailed;
        }
        return self;
    }

    pub fn deinit(self: *Context) void {
        if (self.display != egl.EGL_NO_DISPLAY) {
            _ = egl.eglMakeCurrent(self.display, egl.EGL_NO_SURFACE, egl.EGL_NO_SURFACE, egl.EGL_NO_CONTEXT);
            if (self.surface != egl.EGL_NO_SURFACE) _ = egl.eglDestroySurface(self.display, self.surface);
            if (self.context != egl.EGL_NO_CONTEXT) _ = egl.eglDestroyContext(self.display, self.context);
            _ = egl.eglTerminate(self.display);
        }
        self.* = .{};
    }

    fn initDisplay(self: *Context) !void {
        const get_platform_display = @as(
            ?*const fn (egl.EGLenum, ?*anyopaque, ?[*]const egl.EGLint) callconv(.c) egl.EGLDisplay,
            @ptrCast(egl.eglGetProcAddress("eglGetPlatformDisplayEXT")),
        );

        if (get_platform_display) |func| {
            self.display = func(egl.EGL_PLATFORM_SURFACELESS_MESA, egl.EGL_DEFAULT_DISPLAY, null);
        }
        if (self.display == egl.EGL_NO_DISPLAY) {
            self.display = egl.eglGetDisplay(egl.EGL_DEFAULT_DISPLAY);
        }
        if (self.display == egl.EGL_NO_DISPLAY) return error.EglDisplayFailed;

        var major: egl.EGLint = 0;
        var minor: egl.EGLint = 0;
        if (egl.eglInitialize(self.display, &major, &minor) == egl.EGL_FALSE) return error.EglInitializeFailed;
        if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) return error.EglBindApiFailed;
    }
};

fn createPbufferSurface(display: egl.EGLDisplay, config: egl.EGLConfig, width: u32, height: u32) ?egl.EGLSurface {
    const attrs = [_]egl.EGLint{
        egl.EGL_WIDTH,  @intCast(width),
        egl.EGL_HEIGHT, @intCast(height),
        egl.EGL_NONE,
    };
    return egl.eglCreatePbufferSurface(display, config, &attrs);
}
