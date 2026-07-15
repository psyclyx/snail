//! snail_gl module root — the OpenGL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! Font-necessary only: snail provides the embeddable pipeline `contract` +
//! texture-binding shims (`embeddable`) and the GLSL shader sources
//! (`shaders` / `gles30_shaders` / `glsl`), over the backend-agnostic atlas
//! upload plan in `snail_core` (`AtlasUploadPlanner`). GLES 3.0 shares this
//! module (its own bindings/shaders variants). Depends on `snail_core`.
//!
//! The all-in-one GL renderer, atlas cache, program compilation, ring buffer,
//! and linear-resolve pass are the caller's — see the reference caller under
//! `src/demo/embed_gl*.zig`.

// The GL embeddable coverage surface: gl-typed programs + texture-binding
// backends (over caller-supplied `TextureHandles`) + `Variant`. The facade
// `coverage` aggregation and callers reach programs/backends through here.
pub const embeddable = @import("embeddable.zig");

// GLSL source fragments the coverage custom-shader path re-aggregates.
pub const shaders = @import("shaders.zig");
pub const gles30_shaders = @import("gles30/shaders.zig");

// Raw GL symbol bindings, needed by the caller's renderer + cache.
pub const bindings = @import("bindings.zig");
pub const gles30_bindings = @import("gles30/bindings.zig");

test {
    _ = embeddable;
}
