//! `snail-raster`: optional software renderer for snail draw records.
//!
//! This module depends on `snail`; `snail` never depends on it. Applications
//! that only use the GPU shader contracts do not compile the rasterizer.
//!
//! Device contracts (this renderer plays the role a GPU device + texture
//! formats play for a hardware backend):
//! - Image paint texels: 4 bytes/texel RGBA, sRGB-encoded RGB with straight
//!   linear alpha — the CPU analog of binding an `SRGB8_ALPHA8` texture.
//! - Output encoding is explicit via `TargetEncoding`/`PixelFormat`;
//!   blending is performed in linear light.

const renderer = @import("renderer.zig");
const device_atlas = @import("device_atlas.zig");
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
pub const BufferError = renderer.Renderer.BufferError;
pub const LinearResolveError = renderer.Renderer.LinearResolveError;
pub const EndLinearResolveError = renderer.Renderer.EndLinearResolveError;
pub const ReinitBufferError = renderer.Renderer.ReinitBufferError;
pub const DrawBatchError = renderer.Renderer.DrawBatchError;
pub const InstanceProfileEntry = renderer.InstanceProfileEntry;
pub const InstanceProfileBuffer = renderer.InstanceProfileBuffer;
pub const DeviceAtlas = device_atlas.DeviceAtlas;
pub const DeviceAtlasOptions = device_atlas.DeviceAtlasOptions;
pub const UploadError = device_atlas.UploadError;
pub const ResizeError = device_atlas.ResizeError;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
const draw_mod = @import("draw.zig");
pub const DrawRecords = draw_mod.DrawRecords;
pub const DrawError = draw_mod.DrawError;
pub const draw = draw_mod.draw;

test {
    _ = renderer;
    _ = device_atlas;
    _ = @import("thread_pool.zig");
    _ = @import("draw.zig");
}
