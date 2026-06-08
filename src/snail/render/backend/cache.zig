//! Shared types for backend caches.
//!
//! Each backend's `BackendCache` (cpu, gl, vulkan) owns per-pool GPU
//! storage with a near-identical contract: bind a `PagePool`, upload
//! atlas pages into the cache, hand the caller a `Binding`, release on
//! teardown. The option struct and the bulk of the error variants are
//! the same shape across backends; this module is the one place they
//! live so adding a field or variant doesn't drift across three files.

const std = @import("std");

/// Cache options shared by all backends. The CPU backend uses this
/// shape directly; GPU backends extend it with `GpuCacheOptions`.
pub const BaseCacheOptions = struct {
    /// Maximum number of concurrent live bindings.
    max_bindings: u32 = 16,
    /// Total rows in the shared layer-info storage.
    layer_info_height: u32 = 64,
    /// Total layers in the shared image storage. `0` skips image-array
    /// allocation entirely (callers with no image paints save the VRAM).
    max_images: u32 = 16,
};

/// Cache options for GPU backends — adds the image-array sizing fields
/// that CPU doesn't need (CPU has no fixed image array).
pub const GpuCacheOptions = struct {
    max_bindings: u32 = 16,
    layer_info_height: u32 = 64,
    max_images: u32 = 16,
    /// Maximum source-image width any single image-paint upload will
    /// use. The image array is sized to this; smaller images are
    /// uploaded into the lower-left corner and the layer_info
    /// `uv_scale` texel compensates. Ignored when `max_images == 0`.
    max_image_width: u32 = 1024,
    /// Maximum source-image height. See `max_image_width`.
    max_image_height: u32 = 1024,
};

/// Upload errors shared across CPU/GL/Vulkan backends. Each backend
/// unions in its own extras (`ImageTooLarge` for GL+Vulkan; the Vulkan
/// device-error family for Vulkan).
pub const BaseUploadError = error{
    NoFreeBinding,
    NoFreeLayerInfoRows,
    NoFreeImageLayers,
    NoLayerInfoRoomToGrow,
    UnknownPool,
    UnknownBinding,
    PageNotInPool,
} || std.mem.Allocator.Error;

/// Resize errors shared across CPU/GL backends. Vulkan unions in
/// `VulkanError` on top.
pub const BaseResizeError = error{ActiveBindingsPreventResize} || std.mem.Allocator.Error;
