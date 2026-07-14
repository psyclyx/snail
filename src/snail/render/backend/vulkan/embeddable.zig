//! Embeddable coverage surface for Vulkan.
//!
//! The Vulkan "bind" is caller-driven — unlike GL there is no uniform-location
//! state to set. So this backend is a thin accessor over the cache: it hands
//! the caller the descriptor set (+ the layout it was allocated against) and
//! the atlas image-view handles. The caller's own pipeline binds the set and
//! pushes a `contract.PushConstants`.
//!
//! Lives in the `snail_vulkan` module (not the facade) so all `vk`-typed code
//! stays in the backend that owns it; the facade only re-exports this.

const backend_cache = @import("backend_cache.zig");

pub const vk = backend_cache.vk;
pub const VulkanBackendCache = backend_cache.VulkanBackendCache;

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
