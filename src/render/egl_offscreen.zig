const std = @import("std");
const build_options = @import("build_options");

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

        try chooseConfig(self.display, egl.EGL_PBUFFER_BIT, &self.config);
        self.surface = createPbufferSurface(self.display, self.config, width, height) orelse return error.EglSurfaceCreateFailed;
        self.context = try createOpenGlContext(self.display, self.config);
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

fn chooseConfig(display: egl.EGLDisplay, surface_bit: egl.EGLint, out: *egl.EGLConfig) !void {
    const attrs = [_]egl.EGLint{
        egl.EGL_SURFACE_TYPE,    surface_bit,
        egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT,
        egl.EGL_RED_SIZE,        8,
        egl.EGL_GREEN_SIZE,      8,
        egl.EGL_BLUE_SIZE,       8,
        egl.EGL_ALPHA_SIZE,      8,
        egl.EGL_NONE,
    };

    var config: egl.EGLConfig = null;
    var count: egl.EGLint = 0;
    if (egl.eglChooseConfig(display, &attrs, &config, 1, &count) == egl.EGL_FALSE or count == 0) {
        return error.EglConfigFailed;
    }
    out.* = config;
}

fn createOpenGlContext(display: egl.EGLDisplay, config: egl.EGLConfig) !egl.EGLContext {
    var ctx: egl.EGLContext = egl.EGL_NO_CONTEXT;
    if (!build_options.force_gl33) {
        const attrs_44 = [_]egl.EGLint{
            egl.EGL_CONTEXT_MAJOR_VERSION_KHR,       4,
            egl.EGL_CONTEXT_MINOR_VERSION_KHR,       4,
            egl.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
            egl.EGL_NONE,
        };
        ctx = egl.eglCreateContext(display, config, egl.EGL_NO_CONTEXT, &attrs_44);
        if (ctx != egl.EGL_NO_CONTEXT) return ctx;
    }

    const attrs_33 = [_]egl.EGLint{
        egl.EGL_CONTEXT_MAJOR_VERSION_KHR,       3,
        egl.EGL_CONTEXT_MINOR_VERSION_KHR,       3,
        egl.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        egl.EGL_NONE,
    };
    ctx = egl.eglCreateContext(display, config, egl.EGL_NO_CONTEXT, &attrs_33);
    if (ctx == egl.EGL_NO_CONTEXT) return error.EglContextCreateFailed;
    return ctx;
}

fn createPbufferSurface(display: egl.EGLDisplay, config: egl.EGLConfig, width: u32, height: u32) ?egl.EGLSurface {
    const attrs = [_]egl.EGLint{
        egl.EGL_WIDTH,  @intCast(width),
        egl.EGL_HEIGHT, @intCast(height),
        egl.EGL_NONE,
    };
    return egl.eglCreatePbufferSurface(display, config, &attrs);
}
