//! snail_cpu module root — the CPU rasterizer backend.
//!
//! Depends on `snail_core`; nothing depends on it except the `snail`
//! facade. A host wanting only CPU rendering pulls `snail_core` + this.

const renderer = @import("renderer.zig");

pub const CpuRenderer = renderer.CpuRenderer;
pub const InstanceProfileEntry = renderer.InstanceProfileEntry;
pub const InstanceProfileBuf = renderer.InstanceProfileBuf;
pub const CpuBackendCache = @import("backend_cache.zig").CpuBackendCache;
pub const drawCpu = @import("draw.zig").drawCpu;

test {
    _ = renderer;
    _ = @import("backend_cache.zig");
    _ = @import("draw.zig");
}
