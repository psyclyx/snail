//! Reference caller-owned GL / GLES all-in-one renderer + atlas cache.
//!
//! Relocated out of the snail library as part of the embeddable-only direction
//! (snail is a font library, not a renderer): the caller owns the GL context,
//! programs, VAO, cache, and draw loop. snail provides only the pipeline
//! packed contracts + includable shader functions (`snail.shader.glsl`) and
//! the backend-agnostic atlas upload plan (`snail.atlas_upload.Planner`).
//!
//! This module is the worked example integrators copy. It bundles:
//!   - `Gl{33,44}Renderer` / `Gles30Renderer` — the all-in-one text renderers.
//!   - `Gl{33,44,Gles30}DeviceAtlas` — the GL atlas cache (planner-driven).
//!   - `linear_resolve` — the fp16-intermediate + encode pass for correct
//!     linear-space AA. Exposed because GLES 3.0 integrators typically can't
//!     get an sRGB default framebuffer and won't reinvent it; it's a
//!     font-correctness concern, not generic GPU plumbing. (Candidate for a
//!     dedicated gl-helper module later — see design notes.)

const state = @import("desktop/state.zig");
const gles30_state = @import("gles30/state.zig");
const cache = @import("device_atlas.zig");

pub const Gl33Renderer = state.Gl33Renderer;
pub const Gl44Renderer = state.Gl44Renderer;
pub const Gles30Renderer = gles30_state.Gles30Renderer;

pub const Gl33DeviceAtlas = cache.Gl33DeviceAtlas;
pub const Gl44DeviceAtlas = cache.Gl44DeviceAtlas;
pub const Gles30DeviceAtlas = cache.Gles30DeviceAtlas;

pub const linear_resolve = @import("linear_resolve.zig");

// Caller-side texture/uniform binding for the coverage contract (custom-shader
// path). snail.shader.glsl ships the contract as data; this runs the glBind/glUniform
// loop. Used by the game's quad_renderer.
const bind = @import("bind.zig");
pub const Gl33Backend = bind.Gl33Backend;
pub const Gl44Backend = bind.Gl44Backend;
pub const Gles30Backend = bind.Gles30Backend;
pub const GlProgram = bind.GlProgram;
pub const Gles30Program = bind.Gles30Program;
