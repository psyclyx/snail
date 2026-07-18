//! snail GLSL shader contract root — the OpenGL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! Font-necessary only: snail provides the embeddable pipeline `contract` +
//! data contract (`embeddable`) and includable GLSL algorithm fragments
//! (`shader_library`), over Snail's backend-agnostic `AtlasUploadPlanner`.
//! GLES 3.0 shares this namespace with its own interface variants.
//!
//! The all-in-one GL renderer, atlas cache, program compilation, ring buffer,
//! and linear-resolve pass are the caller's — see the reference caller under
//! `src/demo/render/gl/`.

// Renderer-independent GL/GLES variants, resource contracts, and source
// fragments. Callers reach every shader-facing symbol through this namespace.
pub const embeddable = @import("embeddable.zig");

// No complete stages or entry points: callers own their shaders.
pub const shader_library = @import("shaders.zig");

test {
    _ = embeddable;
}
