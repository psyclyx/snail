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
    /// Color format of the caller's render-pass attachment. Snail must
    /// honor this so callers can target whatever format they render into.
    /// TODO: currently only implicitly respected via `render_pass`
    /// compatibility — not yet read for encoding decisions.
    color_format: vk.VkFormat,
    supports_dual_source_blend: bool = false,
};

/// Scaffolding for the caller-owned-pipeline (custom-shader) path — the
/// Vulkan equivalent of the GL backend's `coverage.GlProgram`. Not yet
/// wired up; the caller supplies a pipeline layout compatible with snail's
/// descriptor set + push-constant ranges and drives their own draw.
pub const TextCoverageProgram = struct {
    /// Pipeline layout for the caller-owned graphics pipeline. `null`
    /// means fall back to snail's built-in layout.
    pipeline_layout: vk.VkPipelineLayout = null,
    descriptor_set_index: u32 = 0,
};
