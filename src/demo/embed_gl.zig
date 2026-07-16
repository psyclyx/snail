//! Reference caller-owned GL / GLES all-in-one renderer + atlas cache.
//!
//! Relocated out of the snail library as part of the embeddable-only direction
//! (snail is a font library, not a renderer): the caller owns the GL context,
//! programs, VAO, cache, and draw loop. snail provides only the pipeline
//! packed contracts + includable shader functions (`snail.gl.embeddable`) and
//! the backend-agnostic atlas upload plan (`snail.AtlasUploadPlanner`).
//!
//! This module is the worked example integrators copy. It bundles:
//!   - `Gl{33,44}Renderer` / `Gles30Renderer` — the all-in-one text renderers.
//!   - `Gl{33,44,Gles30}BackendCache` — the GL atlas cache (planner-driven).
//!   - `linear_resolve` — the fp16-intermediate + encode pass for correct
//!     linear-space AA. Exposed because GLES 3.0 integrators typically can't
//!     get an sRGB default framebuffer and won't reinvent it; it's a
//!     font-correctness concern, not generic GPU plumbing. (Candidate for a
//!     dedicated gl-helper module later — see design notes.)

const state = @import("embed_gl_state.zig");
const gles30_state = @import("embed_gles30_state.zig");
const cache = @import("embed_gl_cache.zig");

pub const Gl33Renderer = state.Gl33Renderer;
pub const Gl44Renderer = state.Gl44Renderer;
pub const Gles30Renderer = gles30_state.Gles30Renderer;

pub const Gl33BackendCache = cache.Gl33BackendCache;
pub const Gl44BackendCache = cache.Gl44BackendCache;
pub const Gles30BackendCache = cache.Gles30BackendCache;

pub const linear_resolve = @import("embed_gl_linear_resolve.zig");

// Caller-side texture/uniform binding for the coverage contract (custom-shader
// path). snail_gl ships the contract as data; this runs the glBind/glUniform
// loop. Used by the game's quad_renderer.
const bind = @import("embed_gl_bind.zig");
pub const Gl33Backend = bind.Gl33Backend;
pub const Gl44Backend = bind.Gl44Backend;
pub const Gles30Backend = bind.Gles30Backend;
pub const GlProgram = bind.GlProgram;
pub const Gles30Program = bind.Gles30Program;
