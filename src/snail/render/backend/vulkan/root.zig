//! snail_vulkan module root — the Vulkan backend.
//!
//! Depends on `snail_core`. The caller owns the instance/device/queue/
//! command-buffer/render-pass; see `types.VulkanContext`.

pub const pipeline = @import("pipeline.zig");
pub const types = @import("types.zig");
pub const backend_cache = @import("backend_cache.zig");

pub const VulkanRenderer = pipeline.VulkanRenderer;
pub const VulkanContext = types.VulkanContext;
pub const VulkanBackendCache = backend_cache.VulkanBackendCache;

test {
    _ = pipeline;
    _ = types;
    _ = backend_cache;
}
