//! Demo-only Vulkan platform: Wayland window + Vulkan instance/device/swapchain.
//! Not part of the library — the library accepts a VulkanContext from the caller.

const std = @import("std");
const vkp = @import("vulkan_pipeline.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;
const wayland = @import("wayland_window.zig");

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
});

const vk = c;

const MAX_FRAMES_IN_FLIGHT = 2;

pub const KEY_ESCAPE = wayland.KEY_ESCAPE;
pub const KEY_R = wayland.KEY_R;
pub const KEY_L = wayland.KEY_L;
pub const KEY_Z = wayland.KEY_Z;
pub const KEY_X = wayland.KEY_X;
pub const KEY_LEFT = wayland.KEY_LEFT;
pub const KEY_RIGHT = wayland.KEY_RIGHT;
pub const KEY_UP = wayland.KEY_UP;
pub const KEY_DOWN = wayland.KEY_DOWN;

var window: ?*wayland.Window = null;

var instance: vk.VkInstance = null;
var surface: vk.VkSurfaceKHR = null;
var physical_device: vk.VkPhysicalDevice = null;
var device: vk.VkDevice = null;
var graphics_queue: vk.VkQueue = null;
var present_queue: vk.VkQueue = null;
var queue_family_index: u32 = 0;
var supports_dual_source_blend: bool = false;

var swapchain: vk.VkSwapchainKHR = null;
var swapchain_images: [8]vk.VkImage = .{null} ** 8;
var swapchain_views: [8]vk.VkImageView = .{null} ** 8;
var swapchain_count: u32 = 0;
var swapchain_format: vk.VkFormat = vk.VK_FORMAT_B8G8R8A8_UNORM;
var swapchain_extent: vk.VkExtent2D = .{ .width = 0, .height = 0 };

var render_pass: vk.VkRenderPass = null;
var framebuffers: [8]vk.VkFramebuffer = .{null} ** 8;

var command_pool: vk.VkCommandPool = null;
var command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = .{null} ** MAX_FRAMES_IN_FLIGHT;
var image_available_sems: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = .{null} ** MAX_FRAMES_IN_FLIGHT;
var render_finished_sems: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = .{null} ** MAX_FRAMES_IN_FLIGHT;
var in_flight_fences: [MAX_FRAMES_IN_FLIGHT]vk.VkFence = .{null} ** MAX_FRAMES_IN_FLIGHT;
var images_in_flight: [8]vk.VkFence = .{null} ** 8;

var current_frame: u32 = 0;
var current_image_index: u32 = 0;
var framebuffer_resized: bool = false;

const DEMO_CLEAR_COLOR = [4]f32{ 0.04, 0.05, 0.07, 1.0 };

// ── Frame timing ──
fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

const FrameTimings = struct {
    wait_fence_us: f64 = 0,
    acquire_us: f64 = 0,
    rp_setup_us: f64 = 0, // vkCmdBeginRenderPass and preamble after acquire
    cpu_work_us: f64 = 0, // main loop work between beginFrame() return and endFrame() entry
    rp_close_us: f64 = 0, // vkCmdEndRenderPass + vkEndCommandBuffer
    submit_us: f64 = 0,
    present_us: f64 = 0,
    total_us: f64 = 0,
    count: u64 = 0,
    window_start_ns: u64 = 0,

    fn add(_: *FrameTimings, field: *f64, val_us: f64) void {
        field.* += val_us;
    }

    fn report(self: *FrameTimings) void {
        if (self.count == 0) return;
        const n: f64 = @floatFromInt(self.count);
        std.debug.print(
            "\r[vk] fence={d:.0} acquire={d:.0} rp_setup={d:.0} cpu={d:.0} rp_close={d:.0} submit={d:.0} present={d:.0} total={d:.0} (all us)  \n",
            .{
                self.wait_fence_us / n,
                self.acquire_us / n,
                self.rp_setup_us / n,
                self.cpu_work_us / n,
                self.rp_close_us / n,
                self.submit_us / n,
                self.present_us / n,
                self.total_us / n,
            },
        );
        self.* = .{ .window_start_ns = self.window_start_ns };
    }
};
var ft = FrameTimings{};
var frame_start_ns: u64 = 0;
var cmd_ready_ns: u64 = 0; // set just before beginFrame returns

pub fn init(width: u32, height: u32, title: [*:0]const u8) !vkp.VulkanContext {
    // Note: vulkan_platform.zig and vulkan_pipeline.zig have separate @cImport blocks
    // for Vulkan, creating incompatible opaque pointer types. We use @ptrCast at the
    // boundary to convert between them.
    window = try wayland.Window.init(width, height, title);
    errdefer {
        window.?.deinit();
        window = null;
    }

    try createInstance();
    try createSurface();
    try pickPhysicalDevice();
    try createLogicalDevice();
    const fb_size = window.?.getFramebufferSize();
    try createSwapchain(fb_size[0], fb_size[1]);
    try createRenderPass();
    try createFramebuffers();
    try createCommandResources();
    try createSyncObjects();

    return .{
        .physical_device = @ptrCast(physical_device),
        .device = @ptrCast(device),
        .graphics_queue = @ptrCast(graphics_queue),
        .queue_family_index = queue_family_index,
        .render_pass = @ptrCast(render_pass),
        .color_format = @intCast(swapchain_format),
        .supports_dual_source_blend = supports_dual_source_blend,
    };
}

/// Returns true once after the window has moved (which may indicate a monitor change).
pub fn consumeMonitorChanged() bool {
    if (window) |w| return w.consumeMonitorChanged();
    return false;
}

pub fn detectCurrentMonitorSubpixelOrder(base: SubpixelOrder) SubpixelOrder {
    if (window) |w| return w.currentSubpixelOrder(base);
    return base;
}

pub fn deinit() void {
    if (device != null) _ = vk.vkDeviceWaitIdle(device);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        if (render_finished_sems[i] != null) vk.vkDestroySemaphore(device, render_finished_sems[i], null);
        if (image_available_sems[i] != null) vk.vkDestroySemaphore(device, image_available_sems[i], null);
        if (in_flight_fences[i] != null) vk.vkDestroyFence(device, in_flight_fences[i], null);
    }
    if (command_pool != null) vk.vkDestroyCommandPool(device, command_pool, null);
    cleanupSwapchain();
    if (render_pass != null) vk.vkDestroyRenderPass(device, render_pass, null);
    if (device != null) vk.vkDestroyDevice(device, null);
    if (surface != null) vk.vkDestroySurfaceKHR(instance, surface, null);
    if (instance != null) vk.vkDestroyInstance(instance, null);
    if (window) |w| w.deinit();
    window = null;
}

/// Begin a new frame. Returns the command buffer to record into.
/// Returns null if the swapchain needs recreation (caller should skip the frame).
pub fn beginFrame() ?vk.VkCommandBuffer {
    frame_start_ns = nowNs();

    const t0 = nowNs();
    _ = vk.vkWaitForFences(device, 1, &in_flight_fences[current_frame], vk.VK_TRUE, std.math.maxInt(u64));
    const t1 = nowNs();

    const result = vk.vkAcquireNextImageKHR(device, swapchain, std.math.maxInt(u64), image_available_sems[current_frame], null, &current_image_index);
    const t2 = nowNs();
    ft.add(&ft.wait_fence_us, @as(f64, @floatFromInt(t1 - t0)) / 1000.0);
    ft.add(&ft.acquire_us, @as(f64, @floatFromInt(t2 - t1)) / 1000.0);
    if (result == vk.VK_ERROR_OUT_OF_DATE_KHR) {
        recreateSwapchain() catch return null;
        return null;
    }

    if (images_in_flight[current_image_index] != null and images_in_flight[current_image_index] != in_flight_fences[current_frame]) {
        _ = vk.vkWaitForFences(device, 1, &images_in_flight[current_image_index], vk.VK_TRUE, std.math.maxInt(u64));
    }
    images_in_flight[current_image_index] = in_flight_fences[current_frame];

    _ = vk.vkResetFences(device, 1, &in_flight_fences[current_frame]);

    const cmd = command_buffers[current_frame];
    _ = vk.vkResetCommandBuffer(cmd, 0);

    const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    });
    _ = vk.vkBeginCommandBuffer(cmd, &begin_info);

    const clear_value = vk.VkClearValue{ .color = .{ .float32 = DEMO_CLEAR_COLOR } };
    const rp_info = std.mem.zeroInit(vk.VkRenderPassBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = render_pass,
        .framebuffer = framebuffers[current_image_index],
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain_extent },
        .clearValueCount = 1,
        .pClearValues = &clear_value,
    });
    vk.vkCmdBeginRenderPass(cmd, &rp_info, vk.VK_SUBPASS_CONTENTS_INLINE);
    cmd_ready_ns = nowNs();
    ft.add(&ft.rp_setup_us, @as(f64, @floatFromInt(cmd_ready_ns - t2)) / 1000.0);

    return cmd;
}

pub fn currentFrameIndex() u32 {
    return current_frame;
}

/// End frame: close render pass, submit, present.
pub fn endFrame() void {
    const ef_start = nowNs();
    ft.add(&ft.cpu_work_us, @as(f64, @floatFromInt(ef_start - cmd_ready_ns)) / 1000.0);

    const cmd = command_buffers[current_frame];
    vk.vkCmdEndRenderPass(cmd);
    _ = vk.vkEndCommandBuffer(cmd);
    const after_close = nowNs();
    ft.add(&ft.rp_close_us, @as(f64, @floatFromInt(after_close - ef_start)) / 1000.0);

    const wait_stages = [1]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const submit_info = std.mem.zeroInit(vk.VkSubmitInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &image_available_sems[current_frame],
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffers[current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &render_finished_sems[current_frame],
    });
    const ts0 = after_close;
    _ = vk.vkQueueSubmit(graphics_queue, 1, &submit_info, in_flight_fences[current_frame]);
    const ts1 = nowNs();

    const present_info = std.mem.zeroInit(vk.VkPresentInfoKHR, .{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &render_finished_sems[current_frame],
        .swapchainCount = 1,
        .pSwapchains = &swapchain,
        .pImageIndices = &current_image_index,
    });
    const result = vk.vkQueuePresentKHR(present_queue, &present_info);
    const ts2 = nowNs();

    ft.add(&ft.submit_us, @as(f64, @floatFromInt(ts1 - ts0)) / 1000.0);
    ft.add(&ft.present_us, @as(f64, @floatFromInt(ts2 - ts1)) / 1000.0);
    ft.add(&ft.total_us, @as(f64, @floatFromInt(ts2 - frame_start_ns)) / 1000.0);
    ft.count += 1;

    // Print averages once per second
    if (ft.window_start_ns == 0) ft.window_start_ns = frame_start_ns;
    if (ts2 - ft.window_start_ns >= 1_000_000_000) {
        ft.report();
        ft.window_start_ns = ts2;
    }

    if (result == vk.VK_ERROR_OUT_OF_DATE_KHR or result == vk.VK_SUBOPTIMAL_KHR or framebuffer_resized) {
        framebuffer_resized = false;
        recreateSwapchain() catch {};
    }

    current_frame = (current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
}

pub fn shouldClose() bool {
    if (window) |w| {
        w.pumpEvents();
        if (w.consumeResized() or w.consumeScaleChanged()) framebuffer_resized = true;
        return w.shouldClose();
    }
    return true;
}

pub fn getWindowSize() [2]u32 {
    if (window) |w| return w.getWindowSize();
    return .{ 0, 0 };
}

pub fn getFramebufferSize() [2]u32 {
    return .{ swapchain_extent.width, swapchain_extent.height };
}

pub fn getTime() f64 {
    return wayland.getTime();
}

pub fn isKeyDown(key: u32) bool {
    if (window) |w| return w.isKeyDown(key);
    return false;
}

pub fn isKeyPressed(key: u32) bool {
    if (window) |w| return w.isKeyPressed(key);
    return false;
}

/// Block until all GPU work submitted to the graphics queue is complete.
/// Equivalent to glFinish() for benchmarking sync points.
pub fn queueWaitIdle() void {
    if (graphics_queue != null) _ = vk.vkQueueWaitIdle(graphics_queue);
}

// ── Offscreen (headless) Vulkan path ──
// No window, no surface, no swapchain, no present.
// Equivalent to GL's offscreen EGL+pbuffer+FBO path. Used by benchmarks.

const OFFSCREEN_FORMAT: vk.VkFormat = vk.VK_FORMAT_R8G8B8A8_SRGB;
const OFFSCREEN_FRAMES_IN_FLIGHT = 8;

var offscreen_image: vk.VkImage = null;
var offscreen_memory: vk.VkDeviceMemory = null;
var offscreen_view: vk.VkImageView = null;
var offscreen_render_pass: vk.VkRenderPass = null;
var offscreen_framebuffer: vk.VkFramebuffer = null;
var offscreen_cmds: [OFFSCREEN_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
var offscreen_fences: [OFFSCREEN_FRAMES_IN_FLIGHT]vk.VkFence = .{null} ** OFFSCREEN_FRAMES_IN_FLIGHT;
var offscreen_frame: u32 = 0;
var offscreen_active_frame: u32 = 0;
var offscreen_extent: vk.VkExtent2D = .{ .width = 0, .height = 0 };

/// Initialise Vulkan for offscreen rendering. No window or swapchain.
/// Call deinitOffscreen() when done.
pub fn initOffscreen(width: u32, height: u32) !vkp.VulkanContext {
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
        .color_format = @intCast(OFFSCREEN_FORMAT),
        .supports_dual_source_blend = supports_dual_source_blend,
    };
}

pub fn deinitOffscreen() void {
    if (device != null) _ = vk.vkDeviceWaitIdle(device);
    if (offscreen_framebuffer != null) vk.vkDestroyFramebuffer(device, offscreen_framebuffer, null);
    if (offscreen_render_pass != null) vk.vkDestroyRenderPass(device, offscreen_render_pass, null);
    if (offscreen_view != null) vk.vkDestroyImageView(device, offscreen_view, null);
    if (offscreen_image != null) vk.vkDestroyImage(device, offscreen_image, null);
    if (offscreen_memory != null) vk.vkFreeMemory(device, offscreen_memory, null);
    for (offscreen_fences) |fence| {
        if (fence != null) vk.vkDestroyFence(device, fence, null);
    }
    if (command_pool != null) vk.vkDestroyCommandPool(device, command_pool, null);
    if (device != null) vk.vkDestroyDevice(device, null);
    if (instance != null) vk.vkDestroyInstance(instance, null);
    offscreen_image = null;
    offscreen_memory = null;
    offscreen_view = null;
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
    images_in_flight = .{null} ** 8;
}

/// Begin an offscreen frame. Returns the command buffer to record into.
/// Waits only for the current ring slot, allowing the CPU to queue several
/// frames ahead during headless benchmarks instead of idling every frame.
pub fn beginFrameOffscreen() vk.VkCommandBuffer {
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

    const clear_value = vk.VkClearValue{ .color = .{ .float32 = .{ 0.12, 0.12, 0.14, 1.0 } } };
    const rp_info = std.mem.zeroInit(vk.VkRenderPassBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = offscreen_render_pass,
        .framebuffer = offscreen_framebuffer,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = offscreen_extent },
        .clearValueCount = 1,
        .pClearValues = &clear_value,
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

fn createInstanceOffscreen() !void {
    const app_info = std.mem.zeroInit(vk.VkApplicationInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "snail-bench",
        .apiVersion = vk.VK_API_VERSION_1_0,
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
    present_queue = graphics_queue;
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

fn createOffscreenResources(width: u32, height: u32) !void {
    // Image
    const img_ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = OFFSCREEN_FORMAT,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
        .usage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
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

    // Image view
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
    const color_ref = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    const subpass = std.mem.zeroInit(vk.VkSubpassDescription, .{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
    });
    const dependency = std.mem.zeroInit(vk.VkSubpassDependency, .{
        .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    });
    const rp_ci = std.mem.zeroInit(vk.VkRenderPassCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_att,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    });
    try checkVk(vk.vkCreateRenderPass(device, &rp_ci, null, &offscreen_render_pass));

    // Framebuffer
    const fb_ci = std.mem.zeroInit(vk.VkFramebufferCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = offscreen_render_pass,
        .attachmentCount = 1,
        .pAttachments = &offscreen_view,
        .width = width,
        .height = height,
        .layers = 1,
    });
    try checkVk(vk.vkCreateFramebuffer(device, &fb_ci, null, &offscreen_framebuffer));
}

// ── Vulkan setup internals ──

fn createInstance() !void {
    const app_info = std.mem.zeroInit(vk.VkApplicationInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "snail-demo",
        .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "snail",
        .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.VK_API_VERSION_1_0,
    });

    const extensions = [_][*c]const u8{
        vk.VK_KHR_SURFACE_EXTENSION_NAME,
        vk.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
    };

    const ci = std.mem.zeroInit(vk.VkInstanceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @as(u32, @intCast(extensions.len)),
        .ppEnabledExtensionNames = @as([*c]const [*c]const u8, @ptrCast(&extensions)),
    });
    try checkVk(vk.vkCreateInstance(&ci, null, &instance));
}

fn createSurface() !void {
    const win = window orelse return error.WindowCreateFailed;
    const ci = std.mem.zeroInit(vk.VkWaylandSurfaceCreateInfoKHR, .{
        .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .display = @as(?*vk.struct_wl_display_1, @ptrCast(win.display)),
        .surface = @as(?*vk.struct_wl_surface_2, @ptrCast(win.surface)),
    });
    try checkVk(vk.vkCreateWaylandSurfaceKHR(instance, &ci, null, &surface));
}

fn pickPhysicalDevice() !void {
    var count: u32 = 0;
    _ = vk.vkEnumeratePhysicalDevices(instance, &count, null);
    if (count == 0) return error.NoVulkanDevices;

    var devices: [16]vk.VkPhysicalDevice = .{null} ** 16;
    var actual: u32 = @min(count, 16);
    _ = vk.vkEnumeratePhysicalDevices(instance, &actual, &devices);

    // Pick first device with graphics queue and present support
    for (devices[0..actual]) |dev| {
        if (dev == null) continue;
        if (findQueueFamily(dev)) |qf| {
            physical_device = dev;
            queue_family_index = qf;
            return;
        }
    }
    return error.NoSuitableDevice;
}

fn findQueueFamily(dev: vk.VkPhysicalDevice) ?u32 {
    var count: u32 = 0;
    vk.vkGetPhysicalDeviceQueueFamilyProperties(dev, &count, null);

    var props: [32]vk.VkQueueFamilyProperties = undefined;
    var actual: u32 = @min(count, 32);
    vk.vkGetPhysicalDeviceQueueFamilyProperties(dev, &actual, &props);

    for (0..actual) |i| {
        const idx: u32 = @intCast(i);
        if (props[i].queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == 0) continue;
        var present_support: vk.VkBool32 = vk.VK_FALSE;
        _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(dev, idx, surface, &present_support);
        if (present_support == vk.VK_TRUE) return idx;
    }
    return null;
}

fn createLogicalDevice() !void {
    const priority: f32 = 1.0;
    const queue_ci = std.mem.zeroInit(vk.VkDeviceQueueCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    });

    const ext_name: [*c]const u8 = vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    var supported_features: vk.VkPhysicalDeviceFeatures = undefined;
    vk.vkGetPhysicalDeviceFeatures(physical_device, &supported_features);
    supports_dual_source_blend = supported_features.dualSrcBlend == vk.VK_TRUE;
    var enabled_features = std.mem.zeroes(vk.VkPhysicalDeviceFeatures);
    if (supports_dual_source_blend) enabled_features.dualSrcBlend = vk.VK_TRUE;
    const dev_ci = std.mem.zeroInit(vk.VkDeviceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_ci,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &ext_name,
        .pEnabledFeatures = &enabled_features,
    });
    try checkVk(vk.vkCreateDevice(physical_device, &dev_ci, null, &device));

    vk.vkGetDeviceQueue(device, queue_family_index, 0, &graphics_queue);
    present_queue = graphics_queue; // same family
}

fn createSwapchain(width: u32, height: u32) !void {
    var capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
    _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);

    // Pick format
    var fmt_count: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &fmt_count, null);
    var formats: [32]vk.VkSurfaceFormatKHR = undefined;
    var fmt_actual: u32 = @min(fmt_count, 32);
    _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &fmt_actual, &formats);

    swapchain_format = formats[0].format;
    var color_space = formats[0].colorSpace;
    var best_score = surfaceFormatPreferenceScore(formats[0]);
    for (formats[1..fmt_actual]) |fmt| {
        const score = surfaceFormatPreferenceScore(fmt);
        if (score > best_score) {
            swapchain_format = fmt.format;
            color_space = fmt.colorSpace;
            best_score = score;
        }
    }

    if (!isSrgbColorFormat(swapchain_format)) {
        std.debug.print(
            "snail: Vulkan swapchain has no sRGB attachment format; text blending may show gamma artifacts on this surface\n",
            .{},
        );
    }

    // Prefer a throttled interactive present mode for the demo so it does not
    // monopolize the GPU and make the desktop difficult to recover.
    const chosen_present_mode: vk.VkPresentModeKHR = vk.VK_PRESENT_MODE_FIFO_KHR;

    // Extent
    if (capabilities.currentExtent.width != 0xFFFFFFFF) {
        swapchain_extent = capabilities.currentExtent;
    } else {
        swapchain_extent = .{
            .width = std.math.clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };
    }

    var image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 and image_count > capabilities.maxImageCount)
        image_count = capabilities.maxImageCount;
    image_count = @min(image_count, 8);

    const sc_ci = std.mem.zeroInit(vk.VkSwapchainCreateInfoKHR, .{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = swapchain_format,
        .imageColorSpace = color_space,
        .imageExtent = swapchain_extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = chosen_present_mode,
        .clipped = vk.VK_TRUE,
    });
    try checkVk(vk.vkCreateSwapchainKHR(device, &sc_ci, null, &swapchain));

    swapchain_count = image_count;
    _ = vk.vkGetSwapchainImagesKHR(device, swapchain, &swapchain_count, &swapchain_images);

    // Create image views
    for (0..swapchain_count) |i| {
        const iv_ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = swapchain_images[i],
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = swapchain_format,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });
        try checkVk(vk.vkCreateImageView(device, &iv_ci, null, &swapchain_views[i]));
    }
}

fn surfaceFormatPreferenceScore(fmt: vk.VkSurfaceFormatKHR) u32 {
    if (fmt.colorSpace != vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) return 0;
    return switch (fmt.format) {
        vk.VK_FORMAT_B8G8R8A8_SRGB => 5,
        vk.VK_FORMAT_R8G8B8A8_SRGB => 4,
        vk.VK_FORMAT_A8B8G8R8_SRGB_PACK32 => 3,
        vk.VK_FORMAT_B8G8R8A8_UNORM => 2,
        vk.VK_FORMAT_R8G8B8A8_UNORM => 1,
        else => 0,
    };
}

fn isSrgbColorFormat(format: vk.VkFormat) bool {
    return switch (format) {
        vk.VK_FORMAT_B8G8R8A8_SRGB,
        vk.VK_FORMAT_R8G8B8A8_SRGB,
        vk.VK_FORMAT_A8B8G8R8_SRGB_PACK32,
        => true,
        else => false,
    };
}

fn createRenderPass() !void {
    const color_attachment = std.mem.zeroInit(vk.VkAttachmentDescription, .{
        .format = swapchain_format,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    });

    const color_ref = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = std.mem.zeroInit(vk.VkSubpassDescription, .{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
    });

    const dependency = std.mem.zeroInit(vk.VkSubpassDependency, .{
        .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    });

    const rp_ci = std.mem.zeroInit(vk.VkRenderPassCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    });
    try checkVk(vk.vkCreateRenderPass(device, &rp_ci, null, &render_pass));
}

fn createFramebuffers() !void {
    for (0..swapchain_count) |i| {
        const fb_ci = std.mem.zeroInit(vk.VkFramebufferCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &swapchain_views[i],
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,
        });
        try checkVk(vk.vkCreateFramebuffer(device, &fb_ci, null, &framebuffers[i]));
    }
}

fn createCommandResources() !void {
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
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
    });
    try checkVk(vk.vkAllocateCommandBuffers(device, &cb_ai, &command_buffers));
}

fn createSyncObjects() !void {
    const sem_ci = std.mem.zeroInit(vk.VkSemaphoreCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    });
    const fence_ci = std.mem.zeroInit(vk.VkFenceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    });

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        try checkVk(vk.vkCreateSemaphore(device, &sem_ci, null, &image_available_sems[i]));
        try checkVk(vk.vkCreateSemaphore(device, &sem_ci, null, &render_finished_sems[i]));
        try checkVk(vk.vkCreateFence(device, &fence_ci, null, &in_flight_fences[i]));
    }
}

fn cleanupSwapchain() void {
    for (0..swapchain_count) |i| {
        if (framebuffers[i] != null) vk.vkDestroyFramebuffer(device, framebuffers[i], null);
        if (swapchain_views[i] != null) vk.vkDestroyImageView(device, swapchain_views[i], null);
        framebuffers[i] = null;
        swapchain_views[i] = null;
        images_in_flight[i] = null;
    }
    if (swapchain != null) vk.vkDestroySwapchainKHR(device, swapchain, null);
    swapchain = null;
    swapchain_count = 0;
}

fn recreateSwapchain() !void {
    const win = window orelse return error.WindowCreateFailed;
    var size = win.getFramebufferSize();
    while (size[0] == 0 or size[1] == 0) {
        win.pumpEvents();
        size = win.getFramebufferSize();
    }

    _ = vk.vkDeviceWaitIdle(device);
    cleanupSwapchain();
    try createSwapchain(size[0], size[1]);
    try createFramebuffers();
}

fn checkVk(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
