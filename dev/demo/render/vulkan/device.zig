const std = @import("std");
const vulkan_types = @import("vulkan_types");

pub const vk = vulkan_types.vk;

pub fn createBuffer(self: anytype, size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, memory: *vk.VkDeviceMemory) !void {
    const ci = std.mem.zeroInit(vk.VkBufferCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    });
    try check(vk.vkCreateBuffer(self.ctx.device, &ci, null, buffer));

    var req: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(self.ctx.device, buffer.*, &req);

    const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = findMemoryType(self, req.memoryTypeBits, properties) orelse return error.NoSuitableMemory,
    });
    try check(vk.vkAllocateMemory(self.ctx.device, &ai, null, memory));
    try check(vk.vkBindBufferMemory(self.ctx.device, buffer.*, memory.*, 0));
}

fn findMemoryType(self: anytype, type_filter: u32, properties: vk.VkMemoryPropertyFlags) ?u32 {
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(self.ctx.physical_device, &mem_props);

    for (0..mem_props.memoryTypeCount) |i| {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return null;
}

pub fn createImage2DArray(self: anytype, width: u32, height: u32, layers: u32, format: vk.VkFormat) !vk.VkImage {
    const ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = layers,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var image: vk.VkImage = null;
    try check(vk.vkCreateImage(self.ctx.device, &ci, null, &image));
    return image;
}

pub fn allocateImageMemory(self: anytype, image: vk.VkImage) !vk.VkDeviceMemory {
    var req: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(self.ctx.device, image, &req);

    const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = findMemoryType(self, req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.NoSuitableMemory,
    });
    var memory: vk.VkDeviceMemory = null;
    try check(vk.vkAllocateMemory(self.ctx.device, &ai, null, &memory));
    return memory;
}

pub fn createImageView(self: anytype, image: vk.VkImage, format: vk.VkFormat, layer_count: u32) !vk.VkImageView {
    const ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D_ARRAY,
        .format = format,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = layer_count,
        },
    });
    var view: vk.VkImageView = null;
    try check(vk.vkCreateImageView(self.ctx.device, &ci, null, &view));
    return view;
}

pub fn destroyStagingBuffer(self: anytype, buffer: vk.VkBuffer, memory: vk.VkDeviceMemory) void {
    vk.vkDestroyBuffer(self.ctx.device, buffer, null);
    vk.vkFreeMemory(self.ctx.device, memory, null);
}

pub fn createImage2D(self: anytype, width: u32, height: u32, format: vk.VkFormat) !vk.VkImage {
    const ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var image: vk.VkImage = null;
    try check(vk.vkCreateImage(self.ctx.device, &ci, null, &image));
    return image;
}

pub fn createImageView2D(self: anytype, image: vk.VkImage, format: vk.VkFormat) !vk.VkImageView {
    const ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    var view: vk.VkImageView = null;
    try check(vk.vkCreateImageView(self.ctx.device, &ci, null, &view));
    return view;
}

pub fn transitionImageLayout(
    cmd: vk.VkCommandBuffer,
    image: vk.VkImage,
    layer_count: u32,
    old_layout: vk.VkImageLayout,
    new_layout: vk.VkImageLayout,
    shader_stages: vk.VkPipelineStageFlags,
) void {
    var src_stage: vk.VkPipelineStageFlags = 0;
    var dst_stage: vk.VkPipelineStageFlags = 0;
    var src_access: vk.VkAccessFlags = 0;
    var dst_access: vk.VkAccessFlags = 0;

    if (old_layout == vk.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        src_access = 0;
        dst_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        src_access = vk.VK_ACCESS_SHADER_READ_BIT;
        dst_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = shader_stages;
        dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        src_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        dst_access = vk.VK_ACCESS_SHADER_READ_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = shader_stages;
    }

    const barrier = std.mem.zeroInit(vk.VkImageMemoryBarrier, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = src_access,
        .dstAccessMask = dst_access,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = layer_count,
        },
    });
    vk.vkCmdPipelineBarrier(cmd, src_stage, dst_stage, 0, 0, null, 0, null, 1, &barrier);
}

pub fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
