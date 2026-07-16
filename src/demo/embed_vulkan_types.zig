pub const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
});

/// Plain handle bundle used by the demo Vulkan integration. It owns no
/// resources and performs no rendering; callers retain every referenced
/// object and all synchronization responsibility.
pub const VulkanContext = struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    supports_dual_source_blend: bool = false,
};
