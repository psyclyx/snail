//! Demo-only headless Vulkan platform path used by benchmarks and capture tools.

const std = @import("std");

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub const vk = c;

var instance: vk.VkInstance = null;
var physical_device: vk.VkPhysicalDevice = null;
var device: vk.VkDevice = null;
var graphics_queue: vk.VkQueue = null;
var queue_family_index: u32 = 0;
var supports_dual_source_blend: bool = false;
var command_pool: vk.VkCommandPool = null;

// ── Offscreen (headless) Vulkan path ──
// No window, no surface, no swapchain, no present.
// Equivalent to GL's offscreen EGL+pbuffer+FBO path. Used by benchmarks.

const OFFSCREEN_FORMAT: vk.VkFormat = vk.VK_FORMAT_R8G8B8A8_SRGB;
const DEPTH_FORMAT: vk.VkFormat = vk.VK_FORMAT_D32_SFLOAT;
pub const OFFSCREEN_FRAMES_IN_FLIGHT = 8;

var offscreen_image: vk.VkImage = null;
var offscreen_memory: vk.VkDeviceMemory = null;
var offscreen_view: vk.VkImageView = null;
var offscreen_depth_image: vk.VkImage = null;
var offscreen_depth_memory: vk.VkDeviceMemory = null;
var offscreen_depth_view: vk.VkImageView = null;
var offscreen_use_depth: bool = false;
var offscreen_render_pass: vk.VkRenderPass = null;
var offscreen_framebuffer: vk.VkFramebuffer = null;
var offscreen_cmds: [OFFSCREEN_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
var offscreen_fences: [OFFSCREEN_FRAMES_IN_FLIGHT]vk.VkFence = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
var offscreen_frame: u32 = 0;
var offscreen_active_frame: u32 = 0;
var offscreen_extent: vk.VkExtent2D = .{ .width = 0, .height = 0 };

/// Initialise Vulkan for offscreen rendering. No window or swapchain.
/// Call deinitOffscreen() when done.
pub fn initOffscreen(width: u32, height: u32) !@import("vulkan_types").VulkanContext {
    return initOffscreenOpts(width, height, false);
}

/// `use_depth` attaches a D32 depth buffer to the offscreen render pass (for
/// the game's depth-tested scene). Color-only tools call `initOffscreen`.
pub fn initOffscreenOpts(width: u32, height: u32, use_depth: bool) !@import("vulkan_types").VulkanContext {
    offscreen_use_depth = use_depth;
    try createInstanceOffscreen();
    try pickPhysicalDeviceOffscreen();
    try createDeviceOffscreen();
    try createCommandResourcesOffscreen();
    offscreen_extent = .{ .width = width, .height = height };
    try createOffscreenResources(width, height);

    return .{
        .physical_device = @ptrCast(physical_device),
        .device = @ptrCast(device),
        .graphics_queue = @ptrCast(graphics_queue),
        .queue_family_index = queue_family_index,
        .render_pass = @ptrCast(offscreen_render_pass),
        .supports_dual_source_blend = supports_dual_source_blend,
    };
}

pub fn physicalDeviceName(buf: []u8) ?[]const u8 {
    if (physical_device == null) return null;
    var props: vk.VkPhysicalDeviceProperties = undefined;
    vk.vkGetPhysicalDeviceProperties(physical_device, &props);
    const max = @min(buf.len, props.deviceName.len);
    var len: usize = 0;
    while (len < max and props.deviceName[len] != 0) : (len += 1) {
        buf[len] = @bitCast(props.deviceName[len]);
    }
    return buf[0..len];
}

pub fn deinitOffscreen() void {
    if (device != null) _ = vk.vkDeviceWaitIdle(device);
    if (offscreen_framebuffer != null) vk.vkDestroyFramebuffer(device, offscreen_framebuffer, null);
    if (offscreen_render_pass != null) vk.vkDestroyRenderPass(device, offscreen_render_pass, null);
    if (offscreen_view != null) vk.vkDestroyImageView(device, offscreen_view, null);
    if (offscreen_image != null) vk.vkDestroyImage(device, offscreen_image, null);
    if (offscreen_memory != null) vk.vkFreeMemory(device, offscreen_memory, null);
    if (offscreen_depth_view != null) vk.vkDestroyImageView(device, offscreen_depth_view, null);
    if (offscreen_depth_image != null) vk.vkDestroyImage(device, offscreen_depth_image, null);
    if (offscreen_depth_memory != null) vk.vkFreeMemory(device, offscreen_depth_memory, null);
    for (offscreen_fences) |fence| {
        if (fence != null) vk.vkDestroyFence(device, fence, null);
    }
    if (command_pool != null) vk.vkDestroyCommandPool(device, command_pool, null);
    if (device != null) vk.vkDestroyDevice(device, null);
    if (instance != null) vk.vkDestroyInstance(instance, null);
    offscreen_image = null;
    offscreen_memory = null;
    offscreen_view = null;
    offscreen_depth_image = null;
    offscreen_depth_memory = null;
    offscreen_depth_view = null;
    offscreen_use_depth = false;
    offscreen_render_pass = null;
    offscreen_framebuffer = null;
    offscreen_cmds = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
    offscreen_fences = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
    offscreen_frame = 0;
    offscreen_active_frame = 0;
    command_pool = null;
    device = null;
    instance = null;
    graphics_queue = null;
    physical_device = null;
    supports_dual_source_blend = false;
}

/// Begin an offscreen frame. Returns the command buffer to record into.
/// Waits only for the current ring slot, allowing the CPU to queue several
/// frames ahead during headless benchmarks instead of idling every frame.
pub fn beginFrameOffscreen() vk.VkCommandBuffer {
    return beginFrameOffscreenWithClear(.{ 0.12, 0.12, 0.14, 1.0 });
}

pub fn beginFrameOffscreenWithClear(clear_color: [4]f32) vk.VkCommandBuffer {
    const frame = offscreen_frame;
    const fence = offscreen_fences[frame];
    _ = vk.vkWaitForFences(device, 1, &fence, vk.VK_TRUE, std.math.maxInt(u64));
    _ = vk.vkResetFences(device, 1, &fence);

    const cmd = offscreen_cmds[frame];
    _ = vk.vkResetCommandBuffer(cmd, 0);

    const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    _ = vk.vkBeginCommandBuffer(cmd, &begin_info);

    const clear_values = [2]vk.VkClearValue{
        .{ .color = .{ .float32 = clear_color } },
        .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const rp_info = std.mem.zeroInit(vk.VkRenderPassBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = offscreen_render_pass,
        .framebuffer = offscreen_framebuffer,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = offscreen_extent },
        .clearValueCount = if (offscreen_use_depth) @as(u32, 2) else 1,
        .pClearValues = &clear_values,
    });
    vk.vkCmdBeginRenderPass(cmd, &rp_info, vk.VK_SUBPASS_CONTENTS_INLINE);
    offscreen_active_frame = frame;
    return cmd;
}

pub fn currentOffscreenFrameIndex() u32 {
    return offscreen_active_frame;
}

/// End the offscreen frame: close render pass and submit. Use queueWaitIdle() to sync.
pub fn endFrameOffscreen() void {
    const frame = offscreen_active_frame;
    const cmd = offscreen_cmds[frame];
    const fence = offscreen_fences[frame];
    vk.vkCmdEndRenderPass(cmd);
    _ = vk.vkEndCommandBuffer(cmd);

    const submit_info = std.mem.zeroInit(vk.VkSubmitInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    });
    _ = vk.vkQueueSubmit(graphics_queue, 1, &submit_info, fence);
    offscreen_frame = (frame + 1) % OFFSCREEN_FRAMES_IN_FLIGHT;
}

pub fn captureOffscreenRgba8(allocator: std.mem.Allocator) ![]u8 {
    const byte_count = @as(usize, offscreen_extent.width) * offscreen_extent.height * 4;
    const pixels = try allocator.alloc(u8, byte_count);
    errdefer allocator.free(pixels);

    var staging_buffer: vk.VkBuffer = null;
    var staging_memory: vk.VkDeviceMemory = null;
    try createReadbackBuffer(byte_count, &staging_buffer, &staging_memory);
    defer {
        if (staging_buffer != null) vk.vkDestroyBuffer(device, staging_buffer, null);
        if (staging_memory != null) vk.vkFreeMemory(device, staging_memory, null);
    }

    const cmd = try beginOneShotCommand();
    transitionOffscreenImageForCopy(cmd, vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = offscreen_extent.width, .height = offscreen_extent.height, .depth = 1 },
    });
    vk.vkCmdCopyImageToBuffer(cmd, offscreen_image, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, staging_buffer, 1, &region);
    transitionOffscreenImageForCopy(cmd, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    try endOneShotCommand(cmd);

    var mapped: ?*anyopaque = null;
    try checkVk(vk.vkMapMemory(device, staging_memory, 0, byte_count, 0, &mapped));
    defer vk.vkUnmapMemory(device, staging_memory);
    const src: [*]const u8 = @ptrCast(mapped.?);
    @memcpy(pixels, src[0..byte_count]);
    return pixels;
}

fn createInstanceOffscreen() !void {
    const app_info = std.mem.zeroInit(vk.VkApplicationInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "snail-bench",
        .apiVersion = vk.VK_API_VERSION_1_1,
    });
    const ci = std.mem.zeroInit(vk.VkInstanceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
    });
    try checkVk(vk.vkCreateInstance(&ci, null, &instance));
}

fn pickPhysicalDeviceOffscreen() !void {
    var count: u32 = 0;
    _ = vk.vkEnumeratePhysicalDevices(instance, &count, null);
    if (count == 0) return error.NoVulkanDevices;
    var devices: [16]vk.VkPhysicalDevice = .{null} ** 16;
    var actual: u32 = @min(count, 16);
    _ = vk.vkEnumeratePhysicalDevices(instance, &actual, &devices);
    for (devices[0..actual]) |dev| {
        if (dev == null) continue;
        if (findGraphicsQueueFamily(dev)) |qf| {
            physical_device = dev;
            queue_family_index = qf;
            return;
        }
    }
    return error.NoSuitableDevice;
}

fn findGraphicsQueueFamily(dev: vk.VkPhysicalDevice) ?u32 {
    var count: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(dev, &count, null);
    var props: [32]vk.VkQueueFamilyProperties = undefined;
    var actual: u32 = @min(count, 32);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(dev, &actual, &props);
    for (0..actual) |i| {
        if (props[i].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) return @intCast(i);
    }
    return null;
}

fn createDeviceOffscreen() !void {
    const priority: f32 = 1.0;
    const queue_ci = std.mem.zeroInit(vk.VkDeviceQueueCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    });
    var supported_features: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(physical_device, &supported_features);
    supports_dual_source_blend = supported_features.dualSrcBlend == vk.VK_TRUE;
    var enabled_features = std.mem.zeroes(vk.VkPhysicalDeviceFeatures);
    if (supports_dual_source_blend) enabled_features.dualSrcBlend = vk.VK_TRUE;

    const dev_ci = std.mem.zeroInit(vk.VkDeviceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_ci,
        .pEnabledFeatures = &enabled_features,
    });
    try checkVk(vk.vkCreateDevice(physical_device, &dev_ci, null, &device));
    vk.vkGetDeviceQueue(device, queue_family_index, 0, &graphics_queue);
}

fn createCommandResourcesOffscreen() !void {
    const cp_ci = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_index,
    });
    try checkVk(vk.vkCreateCommandPool(device, &cp_ci, null, &command_pool));

    const cb_ai = std.mem.zeroInit(vk.VkCommandBufferAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = OFFSCREEN_FRAMES_IN_FLIGHT,
    });
    try checkVk(vk.vkAllocateCommandBuffers(device, &cb_ai, &offscreen_cmds));

    const fence_ci = std.mem.zeroInit(vk.VkFenceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    });
    for (&offscreen_fences) |*fence| {
        try checkVk(vk.vkCreateFence(device, &fence_ci, null, fence));
    }
}

fn findMemoryType(type_filter: u32, properties: vk.VkMemoryPropertyFlags) !u32 {
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_props);
    for (0..mem_props.memoryTypeCount) |i| {
        const bit: u32 = @as(u32, 1) << @intCast(i);
        if ((type_filter & bit != 0) and
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return error.NoSuitableMemoryType;
}

fn createReadbackBuffer(size: usize, buffer: *vk.VkBuffer, memory: *vk.VkDeviceMemory) !void {
    const buffer_ci = std.mem.zeroInit(vk.VkBufferCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    });
    try checkVk(vk.vkCreateBuffer(device, &buffer_ci, null, buffer));
    errdefer {
        vk.vkDestroyBuffer(device, buffer.*, null);
        buffer.* = null;
    }

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(device, buffer.*, &mem_req);
    const mem_type = try findMemoryType(
        mem_req.memoryTypeBits,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    const alloc_info = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    });
    try checkVk(vk.vkAllocateMemory(device, &alloc_info, null, memory));
    errdefer {
        vk.vkFreeMemory(device, memory.*, null);
        memory.* = null;
    }
    try checkVk(vk.vkBindBufferMemory(device, buffer.*, memory.*, 0));
}

fn beginOneShotCommand() !vk.VkCommandBuffer {
    var cmd: vk.VkCommandBuffer = null;
    const alloc_info = std.mem.zeroInit(vk.VkCommandBufferAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    try checkVk(vk.vkAllocateCommandBuffers(device, &alloc_info, &cmd));
    errdefer vk.vkFreeCommandBuffers(device, command_pool, 1, &cmd);

    const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    try checkVk(vk.vkBeginCommandBuffer(cmd, &begin_info));
    return cmd;
}

fn endOneShotCommand(cmd: vk.VkCommandBuffer) !void {
    defer vk.vkFreeCommandBuffers(device, command_pool, 1, &cmd);
    try checkVk(vk.vkEndCommandBuffer(cmd));
    const submit_info = std.mem.zeroInit(vk.VkSubmitInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    });
    try checkVk(vk.vkQueueSubmit(graphics_queue, 1, &submit_info, null));
    try checkVk(vk.vkQueueWaitIdle(graphics_queue));
}

fn transitionOffscreenImageForCopy(cmd: vk.VkCommandBuffer, old_layout: vk.VkImageLayout, new_layout: vk.VkImageLayout) void {
    var src_access: vk.VkAccessFlags = 0;
    var dst_access: vk.VkAccessFlags = 0;
    var src_stage: vk.VkPipelineStageFlags = 0;
    var dst_stage: vk.VkPipelineStageFlags = 0;

    if (old_layout == vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
        src_access = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        dst_access = vk.VK_ACCESS_TRANSFER_READ_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        src_access = vk.VK_ACCESS_TRANSFER_READ_BIT;
        dst_access = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else {
        src_stage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    }

    const barrier = std.mem.zeroInit(vk.VkImageMemoryBarrier, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = offscreen_image,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .srcAccessMask = src_access,
        .dstAccessMask = dst_access,
    });
    vk.vkCmdPipelineBarrier(cmd, src_stage, dst_stage, 0, 0, null, 0, null, 1, &barrier);
}

fn createOffscreenResources(width: u32, height: u32) !void {
    const img_ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = OFFSCREEN_FORMAT,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    try checkVk(vk.vkCreateImage(device, &img_ci, null, &offscreen_image));

    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(device, offscreen_image, &mem_req);
    const mem_type = try findMemoryType(mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    const alloc_info = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    });
    try checkVk(vk.vkAllocateMemory(device, &alloc_info, null, &offscreen_memory));
    try checkVk(vk.vkBindImageMemory(device, offscreen_image, offscreen_memory, 0));

    const iv_ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = offscreen_image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = OFFSCREEN_FORMAT,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    try checkVk(vk.vkCreateImageView(device, &iv_ci, null, &offscreen_view));

    if (offscreen_use_depth) try createOffscreenDepth(width, height);

    // Render pass (final layout COLOR_ATTACHMENT_OPTIMAL, not PRESENT_SRC_KHR)
    const color_att = std.mem.zeroInit(vk.VkAttachmentDescription, .{
        .format = OFFSCREEN_FORMAT,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    });
    const depth_att = std.mem.zeroInit(vk.VkAttachmentDescription, .{
        .format = DEPTH_FORMAT,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    });
    const atts = [2]vk.VkAttachmentDescription{ color_att, depth_att };
    const color_ref = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    const depth_ref = vk.VkAttachmentReference{
        .attachment = 1,
        .layout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };
    const subpass = std.mem.zeroInit(vk.VkSubpassDescription, .{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
        .pDepthStencilAttachment = if (offscreen_use_depth) &depth_ref else null,
    });
    const dependency = std.mem.zeroInit(vk.VkSubpassDependency, .{
        .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    });
    const rp_ci = std.mem.zeroInit(vk.VkRenderPassCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = if (offscreen_use_depth) @as(u32, 2) else 1,
        .pAttachments = &atts,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    });
    try checkVk(vk.vkCreateRenderPass(device, &rp_ci, null, &offscreen_render_pass));

    const fb_atts = [2]vk.VkImageView{ offscreen_view, offscreen_depth_view };
    const fb_ci = std.mem.zeroInit(vk.VkFramebufferCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = offscreen_render_pass,
        .attachmentCount = if (offscreen_use_depth) @as(u32, 2) else 1,
        .pAttachments = &fb_atts,
        .width = width,
        .height = height,
        .layers = 1,
    });
    try checkVk(vk.vkCreateFramebuffer(device, &fb_ci, null, &offscreen_framebuffer));
}

fn createOffscreenDepth(width: u32, height: u32) !void {
    const img_ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = DEPTH_FORMAT,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    try checkVk(vk.vkCreateImage(device, &img_ci, null, &offscreen_depth_image));
    var mem_req: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(device, offscreen_depth_image, &mem_req);
    const mem_type = try findMemoryType(mem_req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    const alloc_info = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    });
    try checkVk(vk.vkAllocateMemory(device, &alloc_info, null, &offscreen_depth_memory));
    try checkVk(vk.vkBindImageMemory(device, offscreen_depth_image, offscreen_depth_memory, 0));
    const iv_ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = offscreen_depth_image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = DEPTH_FORMAT,
        .subresourceRange = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    try checkVk(vk.vkCreateImageView(device, &iv_ci, null, &offscreen_depth_view));
}

/// Block until all GPU work submitted to the graphics queue is complete.
pub fn queueWaitIdle() void {
    if (graphics_queue != null) _ = vk.vkQueueWaitIdle(graphics_queue);
}

fn checkVk(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
