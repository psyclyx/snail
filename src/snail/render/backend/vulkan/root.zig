//! snail_vulkan module root — the Vulkan backend.
//!
//! Embeddable-only: snail owns the font data (atlas, cache, coverage math,
//! shader chunks) and hands the caller the resources + the pipeline contract;
//! the caller owns the pipeline and the draw. There is no all-in-one renderer.
//! Depends on `snail_core`. The caller owns the instance/device/queue/
//! command-buffer/render-pass; see `types.VulkanContext`.
//!
//! GPU surface: `contract` (push constants, descriptor binding order, vertex
//! input, per-family SPIR-V, glyph-run dispatch), `resource_layout` (samplers +
//! descriptor-set layout), `backend_cache` (atlas upload + descriptor set),
//! `embeddable` (accessors + standalone cache construction). See the reference
//! caller renderer `src/demo/embed_vulkan.zig` for a worked example.

pub const types = @import("types.zig");
pub const backend_cache = @import("backend_cache.zig");
pub const contract = @import("contract.zig");
pub const resource_layout = @import("resource_layout.zig");
pub const embeddable = @import("embeddable.zig");

pub const VulkanContext = types.VulkanContext;
pub const VulkanBackendCache = backend_cache.VulkanBackendCache;
pub const VulkanResourceLayout = resource_layout.VulkanResourceLayout;

test {
    _ = types;
    _ = backend_cache;
    _ = contract;
    _ = resource_layout;
    _ = embeddable;
}
