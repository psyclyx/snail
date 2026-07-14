//! Reference caller renderer for the Vulkan embeddable path.
//!
//! This is the worked example an integrator copies: snail owns the font data
//! (atlas, cache, descriptor set, `emit` words) and hands over the public
//! `snail.vulkan.contract`; this owns the pipelines and the draw. It builds one
//! pipeline per shape family, walks the emit stream's glyph runs, and binds the
//! family pipeline each run needs — reproducing the all-in-one `VulkanRenderer`
//! from the public surface alone.
//!
//! It renders into a caller-provided command buffer + render pass; the caller
//! owns the offscreen/swapchain target, the descriptor set (from
//! `VulkanBackendCache`), and frame synchronization.

const std = @import("std");
const snail = @import("snail");

const contract = snail.vulkan.contract;
pub const vk = contract.vk;

const PREMUL_FAMILIES = [_]contract.Family{ .text, .colr, .path, .hinted_text, .autohint };

pub const Renderer = struct {
    device: vk.VkDevice,
    pipeline_layout: vk.VkPipelineLayout,
    // Indexed by @intFromEnum(contract.Family).
    pipelines: [std.enums.values(contract.Family).len]vk.VkPipeline = .{null} ** std.enums.values(contract.Family).len,
    supports_dual_src: bool,
    ibo: HostBuffer,
    vbo: HostBuffer,

    /// Build the pipelines (one per family, subpixel only if the device
    /// supports dual-source blend) against `ctx.render_pass`, plus a quad index
    /// buffer and a vertex upload buffer of `max_vbo_bytes`.
    pub fn init(ctx: snail.VulkanContext, desc_set_layout: vk.VkDescriptorSetLayout, max_vbo_bytes: usize) !Renderer {
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
        };
        errdefer for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(device, p, null);
        };
        for (PREMUL_FAMILIES) |family| {
            self.pipelines[@intFromEnum(family)] = try buildPipeline(ctx, pipeline_layout, contract.recipe(family));
        }
        if (self.supports_dual_src) {
            self.pipelines[@intFromEnum(contract.Family.subpixel)] = try buildPipeline(ctx, pipeline_layout, contract.recipe(.subpixel));
        }

        self.ibo = try HostBuffer.init(ctx, @sizeOf(@TypeOf(contract.QUAD_INDICES)), vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
        errdefer self.ibo.deinit(device);
        @memcpy(self.ibo.bytes()[0..@sizeOf(@TypeOf(contract.QUAD_INDICES))], std.mem.sliceAsBytes(contract.QUAD_INDICES[0..]));

        self.vbo = try HostBuffer.init(ctx, max_vbo_bytes, vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        return self;
    }

    /// Record the draw for one segment stream into `cmd` (inside an active
    /// render pass). `desc_set` is the cache's descriptor set; `words` +
    /// `segments` come from `snail.emit`.
    pub fn render(
        self: *Renderer,
        cmd: vk.VkCommandBuffer,
        desc_set: vk.VkDescriptorSet,
        draw_state: snail.DrawState,
        words: []const u32,
        segments: []const snail.DrawSegment,
    ) void {
        std.debug.assert(words.len * @sizeOf(u32) <= self.vbo.size);
        @memcpy(self.vbo.bytes()[0 .. words.len * @sizeOf(u32)], std.mem.sliceAsBytes(words));

        vk.vkCmdBindIndexBuffer(cmd, self.ibo.buffer, 0, vk.VK_INDEX_TYPE_UINT32);

        // Y-flipped viewport (Vulkan clip space), matching the reference.
        const w = draw_state.surface.pixel_width;
        const h = draw_state.surface.pixel_height;
        const vp = vk.VkViewport{ .x = 0, .y = h, .width = w, .height = -h, .minDepth = 0, .maxDepth = 1 };
        vk.vkCmdSetViewport(cmd, 0, 1, &vp);
        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{ .width = @intFromFloat(@max(w, 0)), .height = @intFromFloat(@max(h, 0)) },
        };
        vk.vkCmdSetScissor(cmd, 0, 1, &scissor);

        var set = desc_set;
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &set, 0, null);

        for (segments) |seg| {
            const seg_words = words[seg.words_offset..][0..seg.words_len];
            var runs = contract.glyphRuns(seg_words);
            while (runs.next()) |run| {
                const mode: contract.TextRenderMode = if (run.kind == .regular)
                    contract.textRenderMode(seg_words, run.glyph_start, run.glyph_count, draw_state, self.supports_dual_src)
                else
                    .grayscale;
                const family = contract.familyForRun(run.kind, mode);
                vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[@intFromEnum(family)]);

                var pc = contract.textPushConstants(draw_state, 0, mode == .grayscale);
                vk.vkCmdPushConstants(cmd, self.pipeline_layout, contract.PUSH_CONSTANT_STAGE_FLAGS, 0, contract.PUSH_CONSTANT_SIZE, &pc);

                const abs_word = seg.words_offset + run.glyph_start * snail.WORDS_PER_INSTANCE;
                var buf = self.vbo.buffer;
                const offset: vk.VkDeviceSize = @as(vk.VkDeviceSize, abs_word) * @sizeOf(u32);
                vk.vkCmdBindVertexBuffers(cmd, 0, 1, &buf, &offset);
                vk.vkCmdDrawIndexed(cmd, contract.INDICES_PER_GLYPH, @intCast(run.glyph_count), 0, 0, 0);
            }
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

/// Build a transfer command pool on the graphics queue family — what a
/// standalone `VulkanBackendCache` needs (see `embeddable.cachePipelineShape`).
pub fn createTransferPool(ctx: snail.VulkanContext) !vk.VkCommandPool {
    const ci = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = ctx.queue_family_index,
    });
    var pool: vk.VkCommandPool = null;
    try check(vk.vkCreateCommandPool(ctx.device, &ci, null, &pool));
    return pool;
}

fn buildPipeline(ctx: snail.VulkanContext, layout: vk.VkPipelineLayout, r: contract.PipelineRecipe) !vk.VkPipeline {
    const device = ctx.device;
    const vert_module = try shaderModule(device, contract.vert_spv);
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

    pub fn init(ctx: snail.VulkanContext, size: usize, usage: vk.VkBufferUsageFlags) !HostBuffer {
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
