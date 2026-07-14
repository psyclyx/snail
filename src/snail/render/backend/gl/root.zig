//! snail_gl module root — the OpenGL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! GLES 3.0 shares this module: it reuses the GL cache
//! (`GlBackendCacheFor(.gles30)`) and the GL-family shared infra
//! (`gl_common`, `linear_resolve`). Depends on `snail_core`.

pub const state = @import("state.zig");
pub const gles30_state = @import("gles30/state.zig");
pub const backend_cache = @import("backend_cache.zig");

// Internals the `coverage` custom-shader facade re-aggregates.
pub const shaders = @import("shaders.zig");
pub const gles30_shaders = @import("gles30/shaders.zig");
pub const bindings = @import("bindings.zig");
pub const gles30_bindings = @import("gles30/bindings.zig");

pub const Gl33Renderer = state.Gl33Renderer;
pub const Gl44Renderer = state.Gl44Renderer;
pub const Gles30Renderer = gles30_state.Gles30Renderer;
pub const Gl33BackendCache = backend_cache.Gl33BackendCache;
pub const Gl44BackendCache = backend_cache.Gl44BackendCache;
pub const Gles30BackendCache = backend_cache.Gles30BackendCache;

test {
    _ = state;
    _ = gles30_state;
    _ = backend_cache;
}
