//! Embeddable coverage surface for Vulkan.
//!
//! The Vulkan "bind" is caller-driven — unlike GL there is no uniform-location
//! state to set. So this backend is a thin accessor over the cache: it hands
//! the caller the descriptor set (+ the layout it was allocated against) and
//! the atlas image-view handles. The caller's own pipeline binds the set and
//! pushes a `contract.PushConstants`.
//!
//! Lives in the caller-owned Vulkan reference module so all `vk`-typed code
//! stays in the backend that owns it; the facade only re-exports this.

const device_atlas = @import("device_atlas.zig");
const resource_layout = @import("layout.zig");

pub const vk = device_atlas.vk;
pub const VulkanDeviceAtlas = device_atlas.VulkanDeviceAtlas;
pub const VulkanContext = device_atlas.VulkanContext;
pub const ResourceContext = device_atlas.ResourceContext;
pub const UploadRecorder = device_atlas.UploadRecorder;
pub const VulkanResourceLayout = resource_layout.VulkanResourceLayout;

/// Resident-resource context for `VulkanDeviceAtlas`. Upload command buffers,
/// submissions, waits, and staging retirement are intentionally not part of
/// this value; callers provide an `UploadRecorder` per recording scope.
pub fn cacheResourceContext(
    ctx: VulkanContext,
    layout: *const VulkanResourceLayout,
) ResourceContext {
    return .{
        .ctx = ctx,
        .sampler_nearest = layout.sampler_nearest,
        .sampler_linear = layout.sampler_linear,
        .desc_set_layout = layout.desc_set_layout,
    };
}
