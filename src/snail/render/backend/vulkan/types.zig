pub const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
});

// Initialization context provided by the caller.
pub const VulkanContext = struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    color_format: vk.VkFormat,
    supports_dual_source_blend: bool = false,
};

pub const TextCoverageBindings = struct {
    /// Pipeline layout for the caller-owned graphics pipeline. Defaults to
    /// Snail's built-in layout, useful when the caller's layout is compatible
    /// with Snail's descriptor set and push-constant ranges.
    pipeline_layout: vk.VkPipelineLayout = null,
    descriptor_set_index: u32 = 0,
};
