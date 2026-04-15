//! Demo-only Vulkan platform: GLFW window + Vulkan instance/device/swapchain.
//! Not part of the library — the library accepts a VulkanContext from the caller.

const std = @import("std");
const vkp = @import("vulkan_pipeline.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

// Single cImport for both GLFW+Vulkan to avoid type incompatibility
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");
});

// Use GLFW's Vulkan types (same @cImport means compatible types)
const vk = c;

const MAX_FRAMES_IN_FLIGHT = 2;

var window: ?*c.GLFWwindow = null;
var monitor_changed: bool = false;

fn onWindowMoved(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    monitor_changed = true;
}

var instance: vk.VkInstance = null;
var surface: vk.VkSurfaceKHR = null;
var physical_device: vk.VkPhysicalDevice = null;
var device: vk.VkDevice = null;
var graphics_queue: vk.VkQueue = null;
var present_queue: vk.VkQueue = null;
var queue_family_index: u32 = 0;

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

var current_frame: u32 = 0;
var current_image_index: u32 = 0;
var framebuffer_resized: bool = false;

// ── Frame timing ──
fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

const FrameTimings = struct {
    wait_fence_us: f64 = 0,
    acquire_us: f64 = 0,
    rp_setup_us: f64 = 0,   // vkCmdBeginRenderPass and preamble after acquire
    cpu_work_us: f64 = 0,   // main loop work between beginFrame() return and endFrame() entry
    rp_close_us: f64 = 0,   // vkCmdEndRenderPass + vkEndCommandBuffer
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

// ── Key input state ──
var prev_keys: [512]bool = .{false} ** 512;

pub fn init(width: u32, height: u32, title: [*:0]const u8) !vkp.VulkanContext {
    // Note: vulkan_platform.zig and vulkan_pipeline.zig have separate @cImport blocks
    // for Vulkan, creating incompatible opaque pointer types. We use @ptrCast at the
    // boundary to convert between them.
    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

    window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null) orelse return error.WindowCreateFailed;
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    _ = c.glfwSetWindowPosCallback(window, onWindowMoved);

    try createInstance();
    try createSurface();
    try pickPhysicalDevice();
    try createLogicalDevice();
    try createSwapchain(width, height);
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
    };
}

/// Returns true once after the window has moved (which may indicate a monitor change).
pub fn consumeMonitorChanged() bool {
    const v = monitor_changed;
    monitor_changed = false;
    return v;
}

/// Detect the subpixel order for the monitor currently containing the window centre.
/// Applies a rotation correction if the monitor's physical and video orientations differ.
pub fn detectCurrentMonitorSubpixelOrder(base: SubpixelOrder) SubpixelOrder {
    const win = window orelse return base;
    var wx: c_int = 0;
    var wy: c_int = 0;
    c.glfwGetWindowPos(win, &wx, &wy);
    var ww: c_int = 0;
    var wh: c_int = 0;
    c.glfwGetWindowSize(win, &ww, &wh);
    const cx: c_int = wx + @divTrunc(ww, 2);
    const cy: c_int = wy + @divTrunc(wh, 2);

    var count: c_int = 0;
    const monitors = c.glfwGetMonitors(&count) orelse return base;
    for (0..@as(usize, @intCast(count))) |i| {
        const m = monitors[i];
        var mx: c_int = 0;
        var my: c_int = 0;
        c.glfwGetMonitorPos(m, &mx, &my);
        const mode = c.glfwGetVideoMode(m) orelse continue;
        if (cx >= mx and cx < mx + mode[0].width and
            cy >= my and cy < my + mode[0].height)
        {
            var pw: c_int = 0;
            var ph: c_int = 0;
            c.glfwGetMonitorPhysicalSize(m, &pw, &ph);
            const vid_landscape = mode[0].width > mode[0].height;
            const phy_landscape = pw > ph;
            if (vid_landscape != phy_landscape) {
                return switch (base) {
                    .rgb  => .vrgb,
                    .bgr  => .vbgr,
                    .vrgb => .rgb,
                    .vbgr => .bgr,
                    .none => .none,
                };
            }
            return base;
        }
    }
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
    if (window) |w| c.glfwDestroyWindow(w);
    c.glfwTerminate();
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

    _ = vk.vkResetFences(device, 1, &in_flight_fences[current_frame]);

    const cmd = command_buffers[current_frame];
    _ = vk.vkResetCommandBuffer(cmd, 0);

    const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    });
    _ = vk.vkBeginCommandBuffer(cmd, &begin_info);

    const clear_value = vk.VkClearValue{ .color = .{ .float32 = .{ 0.12, 0.12, 0.14, 1.0 } } };
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
    c.glfwPollEvents();
    return c.glfwWindowShouldClose(window) == c.GLFW_TRUE;
}

pub fn getWindowSize() [2]u32 {
    return .{ swapchain_extent.width, swapchain_extent.height };
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

pub fn isKeyDown(key: c_int) bool {
    if (window) |w| return c.glfwGetKey(w, key) == c.GLFW_PRESS;
    return false;
}

pub fn isKeyPressed(key: c_int) bool {
    const idx: usize = @intCast(@as(u32, @bitCast(key)));
    if (idx >= 512) return false;
    const down = isKeyDown(key);
    const was_down = prev_keys[idx];
    prev_keys[idx] = down;
    return down and !was_down;
}

/// Block until all GPU work submitted to the graphics queue is complete.
/// Equivalent to glFinish() for benchmarking sync points.
pub fn queueWaitIdle() void {
    if (graphics_queue != null) _ = vk.vkQueueWaitIdle(graphics_queue);
}

// Re-export GLFW key constants
pub const GLFW_KEY_ESCAPE = c.GLFW_KEY_ESCAPE;
pub const GLFW_KEY_R = c.GLFW_KEY_R;
pub const GLFW_KEY_S = c.GLFW_KEY_S;
pub const GLFW_KEY_L = c.GLFW_KEY_L;
pub const GLFW_KEY_Z = c.GLFW_KEY_Z;
pub const GLFW_KEY_X = c.GLFW_KEY_X;

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

    // Get required extensions from GLFW
    var glfw_ext_count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    const ci = std.mem.zeroInit(vk.VkInstanceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = glfw_ext_count,
        .ppEnabledExtensionNames = glfw_exts,
    });
    try checkVk(vk.vkCreateInstance(&ci, null, &instance));
}

fn createSurface() !void {
    if (c.glfwCreateWindowSurface(instance, window, null, &surface) != vk.VK_SUCCESS)
        return error.SurfaceCreateFailed;
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
    const dev_ci = std.mem.zeroInit(vk.VkDeviceCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_ci,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = &ext_name,
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
    for (formats[0..fmt_actual]) |fmt| {
        if (fmt.format == vk.VK_FORMAT_B8G8R8A8_SRGB and fmt.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            swapchain_format = fmt.format;
            color_space = fmt.colorSpace;
            break;
        }
    }

    // Pick present mode: prefer MAILBOX (triple-buffer, no blocking) over FIFO
    var pm_count: u32 = 0;
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &pm_count, null);
    var present_modes: [8]vk.VkPresentModeKHR = undefined;
    var pm_actual: u32 = @min(pm_count, 8);
    _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &pm_actual, &present_modes);
    var chosen_present_mode: vk.VkPresentModeKHR = vk.VK_PRESENT_MODE_FIFO_KHR;
    for (present_modes[0..pm_actual]) |pm| {
        if (pm == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
            chosen_present_mode = vk.VK_PRESENT_MODE_MAILBOX_KHR;
            break;
        }
    }

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
    }
    if (swapchain != null) vk.vkDestroySwapchainKHR(device, swapchain, null);
    swapchain = null;
}

fn recreateSwapchain() !void {
    // Wait for minimized window
    var w: c_int = 0;
    var h: c_int = 0;
    c.glfwGetFramebufferSize(window, &w, &h);
    while (w == 0 or h == 0) {
        c.glfwGetFramebufferSize(window, &w, &h);
        c.glfwWaitEvents();
    }

    _ = vk.vkDeviceWaitIdle(device);
    cleanupSwapchain();
    try createSwapchain(@intCast(w), @intCast(h));
    try createFramebuffers();
}

fn framebufferSizeCallback(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    framebuffer_resized = true;
}

fn checkVk(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
