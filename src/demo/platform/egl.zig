pub fn chooseConfig(egl_mod: anytype, display: anytype, surface_bit: anytype, api: GlApi, out: anytype) !void {
    const Int = @TypeOf(surface_bit);
    const attrs = [_]Int{
        egl_mod.EGL_SURFACE_TYPE,    surface_bit,
        egl_mod.EGL_RENDERABLE_TYPE, renderableType(egl_mod, api),
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
    gles30,
};

pub fn createOpenGlContext(egl_mod: anytype, api: GlApi, display: anytype, config: anytype) !@TypeOf(egl_mod.EGL_NO_CONTEXT) {
    const Int = @TypeOf(egl_mod.EGL_NONE);
    if (api == .gles30) {
        const attrs = [_]Int{
            egl_mod.EGL_CONTEXT_CLIENT_VERSION, 3,
            egl_mod.EGL_NONE,
        };
        const ctx = egl_mod.eglCreateContext(display, config, egl_mod.EGL_NO_CONTEXT, &attrs);
        if (ctx == egl_mod.EGL_NO_CONTEXT) return error.EglContextCreateFailed;
        return ctx;
    }

    const Version = struct { major: Int, minor: Int };
    const version = switch (api) {
        .gl33 => Version{ .major = 3, .minor = 3 },
        .gl44 => Version{ .major = 4, .minor = 4 },
        .gles30 => unreachable,
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

pub fn bindApi(egl_mod: anytype, api: GlApi) !void {
    const egl_api = switch (api) {
        .gl33, .gl44 => egl_mod.EGL_OPENGL_API,
        .gles30 => egl_mod.EGL_OPENGL_ES_API,
    };
    if (egl_mod.eglBindAPI(@intCast(egl_api)) == egl_mod.EGL_FALSE) return error.EglBindApiFailed;
}

fn renderableType(egl_mod: anytype, api: GlApi) @TypeOf(egl_mod.EGL_OPENGL_BIT) {
    return switch (api) {
        .gl33, .gl44 => egl_mod.EGL_OPENGL_BIT,
        .gles30 => egl_mod.EGL_OPENGL_ES3_BIT,
    };
}
