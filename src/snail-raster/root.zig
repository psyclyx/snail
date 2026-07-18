//! `snail-raster`: optional software renderer for snail draw records.
//!
//! This module depends on `snail`; `snail` never depends on it. Applications
//! that only use the GPU shader contracts do not compile the rasterizer.

const renderer = @import("renderer.zig");

pub const Renderer = renderer.Renderer;
pub const InstanceProfileEntry = renderer.InstanceProfileEntry;
pub const InstanceProfileBuf = renderer.InstanceProfileBuf;
pub const BackendCache = @import("backend_cache.zig").BackendCache;
const draw_mod = @import("draw.zig");
pub const DrawRecords = draw_mod.DrawRecords;
pub const DrawError = draw_mod.DrawError;
pub const draw = draw_mod.draw;

test {
    _ = renderer;
    _ = @import("backend_cache.zig");
    _ = @import("draw.zig");
}
