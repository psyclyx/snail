#ifndef SNAIL_VULKAN_H
#define SNAIL_VULKAN_H

#include "snail.h"
#include <vulkan/vulkan_core.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SnailVulkanContext {
    VkPhysicalDevice physical_device;
    VkDevice device;
    VkQueue graphics_queue;
    uint32_t queue_family_index;
    VkRenderPass render_pass;
    VkFormat color_format;
    bool supports_dual_source_blend;
} SnailVulkanContext;

typedef struct {
    VkPipelineLayout pipeline_layout;
    uint32_t descriptor_set_index;
} SnailVulkanTextCoverageBindings;

bool snail_vulkan_available(void);
int snail_vulkan_renderer_init(const SnailVulkanContext *context,
                               SnailRenderer **out);
int snail_vulkan_renderer_begin_frame(SnailRenderer *renderer,
                                      VkCommandBuffer command_buffer,
                                      uint32_t frame_slot);
int snail_vulkan_pending_resource_upload_record(SnailPendingResourceUpload *pending,
                                                VkCommandBuffer command_buffer,
                                                size_t budget_bytes);
bool snail_vulkan_pending_resource_upload_ready_fence(SnailPendingResourceUpload *pending,
                                                      VkFence fence);
int snail_vulkan_prepared_resource_retirement_queue_retire_after(SnailPreparedResourceRetirementQueue *queue,
                                                                 SnailPreparedResources *prepared,
                                                                 VkFence fence);
SnailString snail_vulkan_coverage_shader_vertex_shader(void);
SnailString snail_vulkan_coverage_shader_text_fragment_shader(void);
SnailString snail_vulkan_coverage_shader_coverage_functions(void);
uint32_t snail_vulkan_coverage_shader_descriptor_set_index(void);
uint32_t snail_vulkan_coverage_shader_curve_texture_binding(void);
uint32_t snail_vulkan_coverage_shader_band_texture_binding(void);
VkDescriptorSetLayout snail_vulkan_coverage_backend_descriptor_set_layout(SnailCoverageBackend *backend);
VkPipelineLayout snail_vulkan_coverage_backend_pipeline_layout(SnailCoverageBackend *backend);
int snail_vulkan_coverage_backend_bind_resources(SnailCoverageBackend *backend,
                                                 SnailVulkanTextCoverageBindings bindings);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_VULKAN_H */
