//! snail GLSL shader contract root — the OpenGL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! Font-necessary only: snail provides the embeddable pipeline `contract` +
//! data contract (`embeddable`) and includable GLSL algorithm fragments
//! (`shader_library`), over the backend-agnostic atlas
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

// No complete stages or entry points: callers own their shaders.
pub const shader_library = @import("shaders.zig");

test {
    _ = embeddable;
}
