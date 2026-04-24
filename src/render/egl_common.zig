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

pub fn createOpenGlContext(egl_mod: anytype, force_gl33: bool, display: anytype, config: anytype) !@TypeOf(egl_mod.EGL_NO_CONTEXT) {
    const Int = @TypeOf(egl_mod.EGL_NONE);
    var ctx: @TypeOf(egl_mod.EGL_NO_CONTEXT) = egl_mod.EGL_NO_CONTEXT;
    if (!force_gl33) {
        const attrs_44 = [_]Int{
            egl_mod.EGL_CONTEXT_MAJOR_VERSION_KHR,       4,
            egl_mod.EGL_CONTEXT_MINOR_VERSION_KHR,       4,
            egl_mod.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, egl_mod.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
            egl_mod.EGL_NONE,
        };
        ctx = egl_mod.eglCreateContext(display, config, egl_mod.EGL_NO_CONTEXT, &attrs_44);
        if (ctx != egl_mod.EGL_NO_CONTEXT) return ctx;
    }

    const attrs_33 = [_]Int{
        egl_mod.EGL_CONTEXT_MAJOR_VERSION_KHR,       3,
        egl_mod.EGL_CONTEXT_MINOR_VERSION_KHR,       3,
        egl_mod.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, egl_mod.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        egl_mod.EGL_NONE,
    };
    ctx = egl_mod.eglCreateContext(display, config, egl_mod.EGL_NO_CONTEXT, &attrs_33);
    if (ctx == egl_mod.EGL_NO_CONTEXT) return error.EglContextCreateFailed;
    return ctx;
}
