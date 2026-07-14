pub const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
});

// Initialization context provided by the caller. The caller owns the color
// format via `render_pass`; snail builds pipelines against it. The embeddable
// caller owns the pipeline, so no format field is needed here.
pub const VulkanContext = struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    supports_dual_source_blend: bool = false,
};
