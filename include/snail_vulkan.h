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

bool snail_vulkan_available(void);
int snail_vulkan_renderer_init(const SnailVulkanContext *context,
                               SnailRenderer **out);
int snail_vulkan_renderer_begin_frame(SnailRenderer *renderer,
                                      VkCommandBuffer command_buffer,
                                      uint32_t frame_slot);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_VULKAN_H */
