//! `snail-raster`: optional software renderer for snail draw records.
//!
//! This module depends on `snail`; `snail` never depends on it. Applications
//! that only use the GPU shader contracts do not compile the rasterizer.

const renderer = @import("renderer.zig");
const backend_cache = @import("backend_cache.zig");
const target = @import("render-state");

pub const SubpixelOrder = target.SubpixelOrder;
pub const ColorEncoding = target.ColorEncoding;
pub const TargetEncoding = target.TargetEncoding;
pub const PixelFormat = target.PixelFormat;
pub const PixelRect = target.PixelRect;
pub const LinearResolve = target.LinearResolve;
pub const CoverageTransfer = target.CoverageTransfer;
pub const TargetSurface = target.TargetSurface;
pub const RasterOptions = target.RasterOptions;
pub const DrawState = target.DrawState;
pub const resolveRect = target.resolveRect;

pub const Renderer = renderer.Renderer;
pub const InstanceProfileEntry = renderer.InstanceProfileEntry;
pub const InstanceProfileBuf = renderer.InstanceProfileBuf;
pub const BackendCache = backend_cache.BackendCache;
pub const CacheOptions = backend_cache.CacheOptions;
pub const UploadError = backend_cache.UploadError;
pub const ResizeError = backend_cache.ResizeError;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
const draw_mod = @import("draw.zig");
pub const DrawRecords = draw_mod.DrawRecords;
pub const DrawError = draw_mod.DrawError;
pub const draw = draw_mod.draw;

test {
    _ = renderer;
    _ = backend_cache;
    _ = @import("thread_pool.zig");
    _ = @import("draw.zig");
}
