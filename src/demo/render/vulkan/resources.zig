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

const backend_cache = @import("cache.zig");
const resource_layout = @import("layout.zig");

pub const vk = backend_cache.vk;
pub const VulkanBackendCache = backend_cache.VulkanBackendCache;
pub const VulkanContext = backend_cache.VulkanContext;
pub const PipelineShape = backend_cache.PipelineShape;
pub const VulkanResourceLayout = resource_layout.VulkanResourceLayout;

/// Build the cache's `PipelineShape` from a standalone `VulkanResourceLayout`
/// plus a caller-owned transfer command pool — no all-in-one `VulkanRenderer`
/// needed. This is how an embeddable consumer constructs a
/// `VulkanBackendCache`: create a resource layout, a transfer command pool on
/// the graphics queue family, then `VulkanBackendCache.init(alloc, pool,
/// cachePipelineShape(ctx, &layout, transfer_pool), opts)`.
///
/// `scheduled_resource_upload_cmd` is left null, so uploads allocate a one-shot
/// command buffer from `transfer_cmd_pool` and submit+wait on the context's
/// graphics queue (see §6 queue decoupling for a future caller-driven variant).
pub fn cachePipelineShape(
    ctx: VulkanContext,
    layout: *const VulkanResourceLayout,
    transfer_cmd_pool: vk.VkCommandPool,
) PipelineShape {
    return .{
        .ctx = ctx,
        .transfer_cmd_pool = transfer_cmd_pool,
        .scheduled_resource_upload_cmd = null,
        .sampler_nearest = layout.sampler_nearest,
        .sampler_linear = layout.sampler_linear,
        .desc_set_layout = layout.desc_set_layout,
    };
}

/// Queue-decoupled variant (§6): the cache RECORDS its atlas-upload copies into
/// `upload_cmd` (a command buffer the caller has already begun) and does NOT
/// submit or wait on any queue. The caller ends, submits, and synchronizes
/// `upload_cmd` on its own (transfer) queue, then calls `cache.releaseUploads()`
/// to free the staging buffers. For hosts that can't cede their queue to snail.
pub fn cachePipelineShapeCallerUpload(
    ctx: VulkanContext,
    layout: *const VulkanResourceLayout,
    upload_cmd: vk.VkCommandBuffer,
) PipelineShape {
    return .{
        .ctx = ctx,
        .transfer_cmd_pool = null,
        .scheduled_resource_upload_cmd = upload_cmd,
        .sampler_nearest = layout.sampler_nearest,
        .sampler_linear = layout.sampler_linear,
        .desc_set_layout = layout.desc_set_layout,
    };
}

pub const Backend = struct {
    const Self = @This();

    cache: *const VulkanBackendCache,

    pub fn from(cache: *const VulkanBackendCache) Self {
        return .{ .cache = cache };
    }

    /// The descriptor set holding snail's atlas textures (bindings per
    /// `contract`). Bind it at the caller's chosen set index.
    pub fn descriptorSet(self: Self) vk.VkDescriptorSet {
        return self.cache.descriptorSet();
    }

    /// The layout `descriptorSet()` was allocated against; build the caller's
    /// `VkPipelineLayout` from this so the two are compatible.
    pub fn descriptorSetLayout(self: Self) vk.VkDescriptorSetLayout {
        return self.cache.descriptorSetLayout();
    }

    pub fn curveTexHandle(self: Self) vk.VkImageView {
        return self.cache.curveTexHandle();
    }
    pub fn bandTexHandle(self: Self) vk.VkImageView {
        return self.cache.bandTexHandle();
    }
    pub fn layerInfoTexHandle(self: Self) vk.VkImageView {
        return self.cache.layerInfoTexHandle();
    }
    pub fn imageArrayHandle(self: Self) vk.VkImageView {
        return self.cache.imageArrayHandle();
    }
};
