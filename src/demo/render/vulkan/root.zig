//! Reference caller renderer for the Vulkan embeddable path.
//!
//! This is the worked example an integrator copies: snail supplies the font
//! data (atlas, planner regions, `emit` instances) and the includable shader
//! pieces; this renderer owns the complete shaders, pipelines, and draw. It
//! builds one pipeline per shape family, walks the emit stream's glyph runs,
//! and binds the family pipeline each run needs — an engine-shaped reference
//! built from the public surface alone.
//!
//! It renders into a caller-provided command buffer + render pass; the caller
//! owns the offscreen/swapchain target, `VulkanDeviceAtlas`, and frame
//! synchronization.

const std = @import("std");
const snail = @import("snail");
const render_state = @import("render-state");

pub const contract = @import("contract.zig");
pub const vk = contract.vk;
pub const VulkanContext = @import("vulkan_types").VulkanContext;

// The caller-side atlas cache + resource layout used to live in Snail's Vulkan module;
// they're generic GPU machinery, so they're demo (caller) code now. Re-export
// them so consumers reach the whole embeddable surface via `embed_vulkan`.
pub const VulkanDeviceAtlas = @import("device_atlas.zig").VulkanDeviceAtlas;
pub const DeviceAtlasOptions = @import("device_atlas.zig").DeviceAtlasOptions;
pub const VulkanResourceLayout = @import("layout.zig").VulkanResourceLayout;
const embeddable = @import("resources.zig");
pub const cachePipelineShape = embeddable.cachePipelineShape;
pub const cachePipelineShapeCallerUpload = embeddable.cachePipelineShapeCallerUpload;

const PREMUL_FAMILIES = [_]contract.Family{ .text, .colr, .path_quadratic, .path_conic, .path, .tt_hinted_text, .autohint };
const SUBPIXEL_FAMILIES = [_]contract.Family{ .subpixel, .tt_hinted_subpixel, .autohint_subpixel };
const FAMILY_COUNT = std.enums.values(contract.Family).len;

pub const RenderError = error{
    StaleBinding,
    VertexBufferFull,
} || snail.render.records.DrawRecords.ValidationError;

pub const Renderer = struct {
    device: vk.VkDevice,
    pipeline_layout: vk.VkPipelineLayout,
    // Indexed by @intFromEnum(contract.Family).
    pipelines: [FAMILY_COUNT]vk.VkPipeline = .{null} ** FAMILY_COUNT,
    supports_dual_src: bool,
    ibo: HostBuffer,
    // Vertex upload ring: `num_slots` regions of `slot_bytes` each, so frames
    // in flight don't overwrite vertices the GPU is still reading. The caller
    // passes its frame slot to `render`.
    vbo: HostBuffer,
    slot_bytes: usize,
    num_slots: u32,
    // Set by `beginFrame`; `render` appends within the current slot so multiple
    // passes in one frame don't clobber each other's vertices.
    cur_slot_base: usize = 0,
    cursor: usize = 0,

    /// Build the pipelines (one per family, subpixel only if the device
    /// supports dual-source blend) against `ctx.render_pass`, plus a quad index
    /// buffer and a `slot_bytes`×`num_slots` vertex ring. Use `num_slots` = the
    /// caller's frames-in-flight (1 if it waits idle each frame); `slot_bytes`
    /// must fit the largest frame's `emit` instances.
    /// `depth_test` makes the pipelines depth-test (LESS_OR_EQUAL, write off) so
    /// a caller rendering into a render pass with a depth attachment can have
    /// snail passes occluded by prior opaque geometry. Pass `false` for the
    /// color-only case (the default the 2D demo + screenshots use). The
    /// depth-stencil config is thus caller-controlled, not baked in.
    pub fn init(ctx: VulkanContext, desc_set_layout: vk.VkDescriptorSetLayout, slot_bytes: usize, num_slots: u32, depth_test: bool) !Renderer {
        const device = ctx.device;

        const push_range = std.mem.zeroInit(vk.VkPushConstantRange, .{
            .stageFlags = contract.PUSH_CONSTANT_STAGE_FLAGS,
            .offset = 0,
            .size = contract.PUSH_CONSTANT_SIZE,
        });
        var set_layout = desc_set_layout;
        var pl_info = std.mem.zeroes(vk.VkPipelineLayoutCreateInfo);
        pl_info.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pl_info.setLayoutCount = 1;
        pl_info.pSetLayouts = &set_layout;
        pl_info.pushConstantRangeCount = 1;
        pl_info.pPushConstantRanges = &push_range;
        var pipeline_layout: vk.VkPipelineLayout = null;
        try check(vk.vkCreatePipelineLayout(device, &pl_info, null, &pipeline_layout));
        errdefer vk.vkDestroyPipelineLayout(device, pipeline_layout, null);

        var self = Renderer{
            .device = device,
            .pipeline_layout = pipeline_layout,
            .supports_dual_src = ctx.supports_dual_source_blend,
            .ibo = undefined,
            .vbo = undefined,
            .slot_bytes = slot_bytes,
            .num_slots = num_slots,
        };
        errdefer for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(device, p, null);
        };
        // Pipeline compilation dominates a genuinely cold NVIDIA launch.
        // The families share no mutable pipeline cache and write distinct
        // result slots, so Vulkan permits these calls concurrently. Compile
        // them on independent host threads instead of making the driver
        // process eight large native-Slang modules serially.
        try buildPipelines(&self, ctx, depth_test);

        self.ibo = try HostBuffer.init(ctx, @sizeOf(@TypeOf(contract.QUAD_INDICES)), vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
        errdefer self.ibo.deinit(device);
        @memcpy(self.ibo.bytes()[0..@sizeOf(@TypeOf(contract.QUAD_INDICES))], std.mem.sliceAsBytes(contract.QUAD_INDICES[0..]));

        self.vbo = try HostBuffer.init(ctx, slot_bytes * num_slots, vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        return self;
    }

    /// Start a frame: select the vertex-ring slot (pass the platform's frame
    /// index) and reset the append cursor. Call once per frame before `render`.
    pub fn beginFrame(self: *Renderer, frame_slot: u32) void {
        self.cur_slot_base = @as(usize, frame_slot % self.num_slots) * self.slot_bytes;
        self.cursor = 0;
    }

    /// Record one draw (one `emit` stream) into `cmd`, inside an active render
    /// pass, appending its vertices after any earlier `render` calls this
    /// frame. Every batch must carry a live binding issued by `cache`.
    pub fn render(
        self: *Renderer,
        cmd: vk.VkCommandBuffer,
        cache: *const VulkanDeviceAtlas,
        draw_state: render_state.DrawState,
        instances: []const snail.render.records.Instance,
        batches: []const snail.render.records.DrawBatch,
    ) RenderError!void {
        try (snail.render.records.DrawRecords{ .instances = instances, .batches = batches }).validate();
        const instance_bytes = std.mem.sliceAsBytes(instances);
        const next_cursor = std.math.add(usize, self.cursor, instance_bytes.len) catch return error.VertexBufferFull;
        if (next_cursor > self.slot_bytes) return error.VertexBufferFull;
        for (batches) |batch| {
            if (!cache.isBindingLive(batch.binding)) return error.StaleBinding;
        }
        const base = self.cur_slot_base + self.cursor;
        @memcpy(self.vbo.bytes()[base..][0..instance_bytes.len], instance_bytes);
        defer self.cursor = next_cursor;

        vk.vkCmdBindIndexBuffer(cmd, self.ibo.buffer, 0, vk.VK_INDEX_TYPE_UINT32);

        // Y-flipped viewport (Vulkan clip space), matching the reference.
        const w: f32 = @floatFromInt(draw_state.surface.pixel_width);
        const h: f32 = @floatFromInt(draw_state.surface.pixel_height);
        const vp = vk.VkViewport{ .x = 0, .y = h, .width = w, .height = -h, .minDepth = 0, .maxDepth = 1 };
        vk.vkCmdSetViewport(cmd, 0, 1, &vp);
        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = draw_state.surface.pixel_width, .height = draw_state.surface.pixel_height },
        };
        vk.vkCmdSetScissor(cmd, 0, 1, &scissor);

        var set = cache.descriptorSet();
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &set, 0, null);

        for (batches) |batch| {
            const mode: contract.TextRenderMode = if (contract.kindHasSubpixelFamily(batch.kind))
                contract.textRenderMode(draw_state, self.supports_dual_src)
            else
                .grayscale;
            const family = contract.familyForKind(batch.kind, mode);
            vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[@intFromEnum(family)]);

            var pc = contract.textPushConstants(draw_state, 0, mode == .grayscale);
            vk.vkCmdPushConstants(cmd, self.pipeline_layout, contract.PUSH_CONSTANT_STAGE_FLAGS, 0, contract.PUSH_CONSTANT_SIZE, &pc);

            var buf = self.vbo.buffer;
            const offset: vk.VkDeviceSize = @intCast(base + batch.first_instance * snail.render.records.BYTES_PER_INSTANCE);
            vk.vkCmdBindVertexBuffers(cmd, 0, 1, &buf, &offset);
            vk.vkCmdDrawIndexed(cmd, contract.INDICES_PER_GLYPH, batch.instance_count, 0, 0, 0);
        }
    }

    pub fn deinit(self: *Renderer) void {
        self.vbo.deinit(self.device);
        self.ibo.deinit(self.device);
        for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(self.device, p, null);
        }
        vk.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
    }
};

const PipelineCompileTask = struct {
    ctx: VulkanContext,
    layout: vk.VkPipelineLayout,
    family: contract.Family,
    depth_test: bool,
    pipeline: vk.VkPipeline = null,
    compile_error: ?anyerror = null,

    fn run(self: *PipelineCompileTask) void {
        self.pipeline = buildPipeline(
            self.ctx,
            self.layout,
            contract.recipe(self.family),
            self.depth_test,
        ) catch |err| {
            self.compile_error = err;
            return;
        };
    }
};

fn buildPipelines(self: *Renderer, ctx: VulkanContext, depth_test: bool) !void {
    var tasks: [FAMILY_COUNT]PipelineCompileTask = undefined;
    var threads: [FAMILY_COUNT]?std.Thread = .{null} ** FAMILY_COUNT;
    var task_count: usize = 0;

    for (PREMUL_FAMILIES) |family| {
        tasks[task_count] = .{
            .ctx = ctx,
            .layout = self.pipeline_layout,
            .family = family,
            .depth_test = depth_test,
        };
        task_count += 1;
    }
    if (self.supports_dual_src) {
        for (SUBPIXEL_FAMILIES) |family| {
            tasks[task_count] = .{
                .ctx = ctx,
                .layout = self.pipeline_layout,
                .family = family,
                .depth_test = depth_test,
            };
            task_count += 1;
        }
    }

    // Thread creation failure is not a renderer failure: compile that one
    // task synchronously and keep the remaining work parallel.
    for (tasks[0..task_count], 0..) |*task, i| {
        threads[i] = std.Thread.spawn(.{}, PipelineCompileTask.run, .{task}) catch blk: {
            task.run();
            break :blk null;
        };
    }
    for (threads[0..task_count]) |maybe_thread| {
        if (maybe_thread) |thread| thread.join();
    }

    // Publish every successful handle before returning an error so init's
    // existing errdefer destroys all partial results.
    var first_error: ?anyerror = null;
    for (tasks[0..task_count]) |task| {
        self.pipelines[@intFromEnum(task.family)] = task.pipeline;
        if (first_error == null) first_error = task.compile_error;
    }
    if (first_error) |err| return err;
}

/// Create a `VulkanDeviceAtlas` and upload `atlases` via a caller-owned
/// command buffer submitted on the caller's queue — the §6 queue-decoupled
/// path. snail only RECORDS the copies (`cachePipelineShapeCallerUpload`); this
/// helper (the caller) allocates a transient command buffer, ends + submits it
/// with its own fence, waits, then releases the staging buffers. The worked
/// example for hosts that can't cede their queue to snail.
pub fn cacheWithDecoupledUpload(
    allocator: std.mem.Allocator,
    ctx: VulkanContext,
    page_pool: *snail.PagePool,
    layout: *const VulkanResourceLayout,
    atlases: []const *const snail.Atlas,
    bindings: []snail.render.records.Binding,
    cache_opts: DeviceAtlasOptions,
) !VulkanDeviceAtlas {
    const pool = try createTransferPool(ctx);
    defer vk.vkDestroyCommandPool(ctx.device, pool, null);

    var upload_cmd: vk.VkCommandBuffer = null;
    const ai = std.mem.zeroInit(vk.VkCommandBufferAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    try check(vk.vkAllocateCommandBuffers(ctx.device, &ai, &upload_cmd));
    const bi = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    try check(vk.vkBeginCommandBuffer(upload_cmd, &bi));

    var cache = try VulkanDeviceAtlas.init(allocator, page_pool, cachePipelineShapeCallerUpload(ctx, layout, upload_cmd), cache_opts);
    errdefer cache.deinit();
    try cache.upload(allocator, atlases, bindings); // records copies into upload_cmd — no submit

    try check(vk.vkEndCommandBuffer(upload_cmd));

    // The caller owns submission + synchronization. (A real host might use a
    // dedicated transfer queue; the offscreen platform exposes only the one.)
    var fence: vk.VkFence = null;
    const fi = std.mem.zeroInit(vk.VkFenceCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO });
    try check(vk.vkCreateFence(ctx.device, &fi, null, &fence));
    defer vk.vkDestroyFence(ctx.device, fence, null);
    const si = std.mem.zeroInit(vk.VkSubmitInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &upload_cmd,
    });
    try check(vk.vkQueueSubmit(ctx.graphics_queue, 1, &si, fence));
    try check(vk.vkWaitForFences(ctx.device, 1, &fence, vk.VK_TRUE, std.math.maxInt(u64)));
    cache.releaseUploads();
    return cache;
}

/// Build a transfer command pool on the graphics queue family — what a
/// standalone `VulkanDeviceAtlas` needs (see `embeddable.cachePipelineShape`).
pub fn createTransferPool(ctx: VulkanContext) !vk.VkCommandPool {
    const ci = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = ctx.queue_family_index,
    });
    var pool: vk.VkCommandPool = null;
    try check(vk.vkCreateCommandPool(ctx.device, &ci, null, &pool));
    return pool;
}

fn buildPipeline(ctx: VulkanContext, layout: vk.VkPipelineLayout, r: contract.PipelineRecipe, depth_test: bool) !vk.VkPipeline {
    const device = ctx.device;
    const vert_module = try shaderModule(device, r.vert_spv);
    defer vk.vkDestroyShaderModule(device, vert_module, null);
    const frag_module = try shaderModule(device, r.frag_spv);
    defer vk.vkDestroyShaderModule(device, frag_module, null);

    const stages = [2]vk.VkPipelineShaderStageCreateInfo{
        std.mem.zeroInit(vk.VkPipelineShaderStageCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main",
        }),
        std.mem.zeroInit(vk.VkPipelineShaderStageCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main",
        }),
    };

    const vi_binding = contract.vertexInputBinding();
    const vi_attrs = contract.vertexInputAttributes();
    const vi_info = std.mem.zeroInit(vk.VkPipelineVertexInputStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vi_binding,
        .vertexAttributeDescriptionCount = @as(u32, vi_attrs.len),
        .pVertexAttributeDescriptions = &vi_attrs,
    });
    const ia_info = std.mem.zeroInit(vk.VkPipelineInputAssemblyStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    });
    const vp_info = std.mem.zeroInit(vk.VkPipelineViewportStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    });
    const rast_info = std.mem.zeroInit(vk.VkPipelineRasterizationStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_NONE,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0,
    });
    const ms_info = std.mem.zeroInit(vk.VkPipelineMultisampleStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
    });
    const blend_attach = contract.blendAttachment(r.blend);
    const blend_info = std.mem.zeroInit(vk.VkPipelineColorBlendStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &blend_attach,
    });
    const ds_info = std.mem.zeroInit(vk.VkPipelineDepthStencilStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        // Caller-controlled: depth-test (never write) so snail passes can be
        // occluded by prior opaque geometry when a depth attachment is present.
        .depthTestEnable = @intFromBool(depth_test),
        .depthWriteEnable = 0,
        .depthCompareOp = @as(vk.VkCompareOp, @intCast(if (depth_test) vk.VK_COMPARE_OP_LESS_OR_EQUAL else vk.VK_COMPARE_OP_NEVER)),
    });
    const dyn_states = [2]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dyn_info = std.mem.zeroInit(vk.VkPipelineDynamicStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dyn_states.len,
        .pDynamicStates = &dyn_states,
    });

    const ci = std.mem.zeroInit(vk.VkGraphicsPipelineCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = @as(u32, stages.len),
        .pStages = &stages,
        .pVertexInputState = &vi_info,
        .pInputAssemblyState = &ia_info,
        .pViewportState = &vp_info,
        .pRasterizationState = &rast_info,
        .pMultisampleState = &ms_info,
        .pDepthStencilState = &ds_info,
        .pColorBlendState = &blend_info,
        .pDynamicState = &dyn_info,
        .layout = layout,
        .renderPass = ctx.render_pass,
        .subpass = 0,
    });
    var pipeline: vk.VkPipeline = null;
    try check(vk.vkCreateGraphicsPipelines(device, null, 1, &ci, null, &pipeline));
    return pipeline;
}

fn shaderModule(device: vk.VkDevice, spv: []align(4) const u8) !vk.VkShaderModule {
    const ci = std.mem.zeroInit(vk.VkShaderModuleCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spv.len,
        .pCode = @as([*]const u32, @ptrCast(@alignCast(spv.ptr))),
    });
    var module: vk.VkShaderModule = null;
    try check(vk.vkCreateShaderModule(device, &ci, null, &module));
    return module;
}

pub const HostBuffer = struct {
    buffer: vk.VkBuffer,
    memory: vk.VkDeviceMemory,
    mapped: [*]u8,
    size: usize,

    pub fn init(ctx: VulkanContext, size: usize, usage: vk.VkBufferUsageFlags) !HostBuffer {
        const device = ctx.device;
        const bi = std.mem.zeroInit(vk.VkBufferCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        });
        var buffer: vk.VkBuffer = null;
        try check(vk.vkCreateBuffer(device, &bi, null, &buffer));
        errdefer vk.vkDestroyBuffer(device, buffer, null);

        var req: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(device, buffer, &req);
        const mem_type = try findMemoryType(ctx.physical_device, req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = req.size,
            .memoryTypeIndex = mem_type,
        });
        var memory: vk.VkDeviceMemory = null;
        try check(vk.vkAllocateMemory(device, &ai, null, &memory));
        errdefer vk.vkFreeMemory(device, memory, null);
        try check(vk.vkBindBufferMemory(device, buffer, memory, 0));

        var ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(device, memory, 0, size, 0, &ptr));
        return .{ .buffer = buffer, .memory = memory, .mapped = @ptrCast(ptr.?), .size = size };
    }

    pub fn bytes(self: *HostBuffer) []u8 {
        return self.mapped[0..self.size];
    }

    pub fn deinit(self: *HostBuffer, device: vk.VkDevice) void {
        vk.vkUnmapMemory(device, self.memory);
        vk.vkDestroyBuffer(device, self.buffer, null);
        vk.vkFreeMemory(device, self.memory, null);
    }
};

fn findMemoryType(phys: vk.VkPhysicalDevice, type_filter: u32, props: vk.VkMemoryPropertyFlags) !u32 {
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(phys, &mem_props);
    for (0..mem_props.memoryTypeCount) |i| {
        const bit = @as(u32, 1) << @intCast(i);
        if ((type_filter & bit != 0) and (mem_props.memoryTypes[i].propertyFlags & props) == props) return @intCast(i);
    }
    return error.NoSuitableMemoryType;
}

pub fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
