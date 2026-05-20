pub fn chooseConfig(egl_mod: anytype, display: anytype, surface_bit: anytype, out: anytype) !void {
    const Int = @TypeOf(surface_bit);
    const attrs = [_]Int{
        egl_mod.EGL_SURFACE_TYPE,    surface_bit,
        egl_mod.EGL_RENDERABLE_TYPE, egl_mod.EGL_OPENGL_BIT,
        egl_mod.EGL_RED_SIZE,        8,
        egl_mod.EGL_GREEN_SIZE,      8,
        egl_mod.EGL_BLUE_SIZE,       8,
        egl_mod.EGL_ALPHA_SIZE,      8,
        egl_mod.EGL_NONE,
    };

    var config: @TypeOf(out.*) = null;
    var count: Int = 0;
    if (egl_mod.eglChooseConfig(display, &attrs, &config, 1, &count) == egl_mod.EGL_FALSE or count == 0) {
        return error.EglConfigFailed;
    }
    out.* = config;
}

pub const GlApi = enum {
    gl33,
    gl44,
};

pub fn createOpenGlContext(egl_mod: anytype, api: GlApi, display: anytype, config: anytype) !@TypeOf(egl_mod.EGL_NO_CONTEXT) {
    const Int = @TypeOf(egl_mod.EGL_NONE);
    const Version = struct { major: Int, minor: Int };
    const version = switch (api) {
        .gl33 => Version{ .major = 3, .minor = 3 },
        .gl44 => Version{ .major = 4, .minor = 4 },
    };
    const attrs = [_]Int{
        egl_mod.EGL_CONTEXT_MAJOR_VERSION_KHR,       version.major,
        egl_mod.EGL_CONTEXT_MINOR_VERSION_KHR,       version.minor,
        egl_mod.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, egl_mod.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        egl_mod.EGL_NONE,
    };
    const ctx = egl_mod.eglCreateContext(display, config, egl_mod.EGL_NO_CONTEXT, &attrs);
    if (ctx == egl_mod.EGL_NO_CONTEXT) return error.EglContextCreateFailed;
    return ctx;
}
