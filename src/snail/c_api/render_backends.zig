const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const build_options = common.build_options;
const vk = common.vk;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_RENDERER_FAILED = common.SNAIL_ERR_RENDERER_FAILED;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SnailDrawState = common.SnailDrawState;
const SnailVulkanContext = common.SnailVulkanContext;
const toDrawState = common.toDrawState;
const PreparedResourcesImpl = common.PreparedResourcesImpl;
const PreparedSceneImpl = common.PreparedSceneImpl;
const PreparedResourceRetirementQueueImpl = common.PreparedResourceRetirementQueueImpl;
const PendingResourceUploadImpl = common.PendingResourceUploadImpl;
const VulkanFrameImpl = common.VulkanFrameImpl;
const DrawListImpl = common.DrawListImpl;
const CoverageBackendImpl = common.CoverageBackendImpl;
const ThreadPoolImpl = common.ThreadPoolImpl;
const RendererImpl = common.RendererImpl;
const destroyHandle = common.destroyHandle;

// Renderer

fn cpuPixels(pixels: ?[*]u8, width: u32, height: u32, stride: u32) ?[*]u8 {
    const ptr = pixels orelse return null;
    if (width == 0 or height == 0) return null;
    const min_stride = std.math.mul(u32, width, 4) catch return null;
    if (stride < min_stride) return null;
    return ptr;
}

pub export fn snail_gl_renderer_init(out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_opengl) {
        const gl = snail.GlRenderer.init(handleAllocator()) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = gl;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .gl, .gl = gl };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

pub export fn snail_cpu_available() bool {
    return build_options.enable_cpu;
}

fn mapThreadPoolInitError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => SNAIL_ERR_OUT_OF_MEMORY,
        else => SNAIL_ERR_RENDERER_FAILED,
    };
}

fn initThreadPool(
    alloc_ptr: ?*const SnailAllocator,
    worker_count: ?usize,
    out: *?*ThreadPoolImpl,
) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(ThreadPoolImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.inner.init(allocator, .{ .threads = worker_count }) catch |err| {
        handleAllocator().destroy(impl);
        return mapThreadPoolInitError(err);
    };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_thread_pool_init(
    alloc_ptr: ?*const SnailAllocator,
    out: *?*ThreadPoolImpl,
) c_int {
    return initThreadPool(alloc_ptr, null, out);
}

pub export fn snail_thread_pool_init_with_threads(
    alloc_ptr: ?*const SnailAllocator,
    worker_count: usize,
    out: *?*ThreadPoolImpl,
) c_int {
    return initThreadPool(alloc_ptr, worker_count, out);
}

pub export fn snail_thread_pool_deinit(pool: ?*ThreadPoolImpl) void {
    if (pool) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

pub export fn snail_thread_pool_thread_count(pool: *const ThreadPoolImpl) usize {
    return pool.inner.threadCount();
}

pub export fn snail_cpu_renderer_init(pixels: ?[*]u8, width: u32, height: u32, stride: u32, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_cpu) {
        const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
        const cpu = snail.CpuRenderer.init(pixel_ptr, width, height, stride);
        const impl = handleAllocator().create(RendererImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
        impl.* = .{ .backend = .cpu, .cpu = cpu };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

pub export fn snail_cpu_renderer_reinit_buffer(renderer: *RendererImpl, pixels: ?[*]u8, width: u32, height: u32, stride: u32) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .cpu) return SNAIL_ERR_INVALID_ARGUMENT;
    const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.cpu) |*cpu| {
        cpu.reinitBuffer(pixel_ptr, width, height, stride);
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

pub export fn snail_cpu_renderer_set_thread_pool(renderer: *RendererImpl, pool: ?*ThreadPoolImpl) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .cpu) return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.cpu) |*cpu| {
        cpu.setThreadPool(if (pool) |p| &p.inner else null);
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

pub export fn snail_vulkan_available() bool {
    return build_options.enable_vulkan;
}

pub export fn snail_vulkan_renderer_init(ctx: *const SnailVulkanContext, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = snail.VulkanContext{
            .physical_device = ctx.physical_device,
            .device = ctx.device,
            .graphics_queue = ctx.graphics_queue,
            .queue_family_index = ctx.queue_family_index,
            .render_pass = ctx.render_pass,
            .color_format = ctx.color_format,
            .supports_dual_source_blend = ctx.supports_dual_source_blend,
        };
        const vk_renderer = snail.VulkanRenderer.init(handleAllocator(), vk_ctx) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = vk_renderer;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .vulkan, .vulkan = vk_renderer };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

pub export fn snail_vulkan_renderer_frame(
    renderer: *RendererImpl,
    command_buffer: vk.VkCommandBuffer,
    frame_slot: u32,
    out: *?*VulkanFrameImpl,
) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .vulkan) return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.vulkan) |*vk_renderer| {
        const frame = vk_renderer.frame(.{ .cmd = command_buffer, .slot = frame_slot });
        const impl = handleAllocator().create(VulkanFrameImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
        impl.* = .{ .inner = frame };
        out.* = impl;
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

pub export fn snail_vulkan_frame_deinit(frame: ?*VulkanFrameImpl) void {
    if (frame) |f| destroyHandle(f);
}

pub export fn snail_vulkan_frame_draw(
    frame: *VulkanFrameImpl,
    prepared: *const PreparedResourcesImpl,
    list: *const DrawListImpl,
    state: SnailDrawState,
) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    frame.inner.draw(&prepared.inner, list.inner.slice(), toDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_vulkan_frame_draw_prepared(
    frame: *VulkanFrameImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    state: SnailDrawState,
) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    frame.inner.drawPrepared(&prepared.inner, &scene.inner, toDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_vulkan_frame_coverage_backend(
    frame: *VulkanFrameImpl,
    prepared: *const PreparedResourcesImpl,
    out: *?*CoverageBackendImpl,
) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    const backend = frame.inner.coverageBackend(&prepared.inner) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    const impl = handleAllocator().create(CoverageBackendImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = backend };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_vulkan_pending_resource_upload_record(pending: *PendingResourceUploadImpl, command_buffer: vk.VkCommandBuffer, budget_bytes: usize) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    pending.inner.record(.{ .vulkan = command_buffer }, .{ .budget_bytes = budget_bytes }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_vulkan_pending_resource_upload_record_checked(pending: *PendingResourceUploadImpl, command_buffer: vk.VkCommandBuffer, budget_bytes: usize, allow_cache_rebuilds: bool) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    pending.inner.record(.{ .vulkan = command_buffer }, .{
        .budget_bytes = budget_bytes,
        .allow_cache_rebuilds = allow_cache_rebuilds,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_vulkan_pending_resource_upload_ready_fence(pending: *PendingResourceUploadImpl, fence: vk.VkFence) bool {
    if (comptime !build_options.enable_vulkan) return false;
    return pending.inner.ready(.{ .vulkan_fence = fence });
}

pub export fn snail_vulkan_prepared_resource_retirement_queue_retire_after(queue: *PreparedResourceRetirementQueueImpl, prepared: *PreparedResourcesImpl, fence: vk.VkFence) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    queue.inner.retireAfter(&prepared.inner, fence) catch |err| return mapError(err);
    destroyHandle(prepared);
    return SNAIL_OK;
}
