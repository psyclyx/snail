//! Vulkan embeddable-path test vehicle.
//!
//! Proves the embeddable contract end-to-end: a *caller-owned* set of Vulkan
//! pipelines, built only from the public surface snail exposes
//! (`snail.vulkan.contract` — SPIR-V per family + vertex input + blend + push
//! constants + the glyph-run iterator, and the cache's descriptor set/layout),
//! renders a scene and is byte-diffed against the all-in-one `VulkanRenderer`
//! reference into the same offscreen target.
//!
//! The caller builds one pipeline per shape family and, per emit segment, walks
//! the glyph runs (`contract.glyphRuns`) binding the family pipeline each run
//! needs — exactly what the all-in-one does internally. This exercises the
//! premultiplied family set (text + colr + path + hinted + autohint) across
//! both the text and path pictures.
//!
//! snail owns the font data (atlas, cache, descriptor set, emit words); the
//! caller owns the pipelines and the draw. Prints `PASS` when every picture
//! matches within the GPU ±1-LSB AA tolerance, `FAIL` (exit non-zero) otherwise.

const std = @import("std");
const snail = @import("snail");
const demo_content = @import("content.zig");
const harness = @import("screenshot_harness.zig");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const platform = vulkan_demo_platform.offscreen;

const contract = snail.vulkan.contract;
const vk = contract.vk;

const W: u32 = 400;
const H: u32 = 240;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const vk_ctx = try platform.initOffscreen(W, H);
    defer platform.deinitOffscreen();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();

    var vk_renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer vk_renderer.deinit();

    var cache = try snail.VulkanBackendCache.init(allocator, content.pool, vk_renderer.state.pipelineShape(), .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();

    // Snail owns the resources: upload both atlases once; the reference and the
    // caller pipelines both sample the resulting descriptor set.
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);

    var caller = try CallerPipelines.init(vk_ctx, cache.descriptorSetLayout());
    defer caller.deinit(vk_ctx.device);

    // One quad index buffer, shared across all draws.
    var ibo = try HostBuffer.init(vk_ctx, @sizeOf(@TypeOf(contract.QUAD_INDICES)), vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    defer ibo.deinit(vk_ctx.device);
    @memcpy(ibo.bytes()[0..@sizeOf(@TypeOf(contract.QUAD_INDICES))], std.mem.sliceAsBytes(contract.QUAD_INDICES[0..]));

    const draw_state = harness.drawState(W, H);
    const clear = [4]f32{
        harness.srgbToLinear(harness.bg_srgb_f32[0]),
        harness.srgbToLinear(harness.bg_srgb_f32[1]),
        harness.srgbToLinear(harness.bg_srgb_f32[2]),
        harness.bg_srgb_f32[3],
    };

    const pictures = [_]struct {
        label: []const u8,
        atlas: *const snail.Atlas,
        picture: *const @TypeOf(content.paths_picture),
        binding: snail.Binding,
    }{
        .{ .label = "paths", .atlas = &content.paths_atlas, .picture = &content.paths_picture, .binding = bindings[0] },
        .{ .label = "text ", .atlas = &content.text_atlas, .picture = &content.text_picture, .binding = bindings[1] },
    };

    var worst: u32 = 0;
    for (pictures) |p| {
        const d = try renderAndDiff(allocator, &vk_renderer, &cache, &caller, ibo.buffer, vk_ctx, clear, draw_state, p.atlas, p.picture, p.binding, p.label);
        worst = @max(worst, d.max);
    }

    if (worst <= 1) {
        std.debug.print("PASS: caller pipelines match the all-in-one within ±1 LSB\n", .{});
    } else {
        std.debug.print("FAIL: caller pipelines diverge from the all-in-one (max delta {d})\n", .{worst});
        return error.EmbeddableMismatch;
    }
}

fn renderAndDiff(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    cache: *snail.VulkanBackendCache,
    caller: *CallerPipelines,
    ibo: vk.VkBuffer,
    vk_ctx: snail.VulkanContext,
    clear: [4]f32,
    draw_state: snail.DrawState,
    atlas: *const snail.Atlas,
    picture: anytype,
    binding: snail.Binding,
    label: []const u8,
) !Diff {
    const words = try allocator.alloc(u32, snail.emit.wordBudget(picture.shapes.len, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 8);
    defer allocator.free(segs);
    var words_len: usize = 0;
    var segs_len: usize = 0;
    _ = try snail.emit.emit(words, segs, &words_len, &segs_len, binding, atlas, picture.shapes, .identity, .{ 1, 1, 1, 1 });
    const glyph_count: u32 = @intCast(words_len / snail.WORDS_PER_INSTANCE);

    // Reference: the all-in-one VulkanRenderer (picks pipelines by run kind).
    {
        const cmd = platform.beginFrameOffscreenWithClear(clear);
        vk_renderer.state.setCommandBuffer(cmd);
        defer vk_renderer.state.clearCommandBuffer();
        vk_renderer.state.setFrameSlot(platform.currentOffscreenFrameIndex());
        try vk_renderer.state.draw(allocator, draw_state, .{ .words = words[0..words_len], .segments = segs[0..segs_len] }, &.{cache});
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_ref = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_ref);

    // Caller: our own pipelines, run-dispatched.
    var vbo = try HostBuffer.init(vk_ctx, words_len * @sizeOf(u32), vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    defer vbo.deinit(vk_ctx.device);
    @memcpy(vbo.bytes()[0 .. words_len * @sizeOf(u32)], std.mem.sliceAsBytes(words[0..words_len]));
    {
        const platform_cmd = platform.beginFrameOffscreenWithClear(clear);
        const cmd: vk.VkCommandBuffer = @ptrCast(platform_cmd);
        caller.record(cmd, cache.descriptorSet(), vbo.buffer, ibo, draw_state, words[0..words_len]);
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_emb = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_emb);

    const d = diff(pixels_ref, pixels_emb);
    std.debug.print("embeddable-vulkan [{s}]: {d} glyphs, max delta={d}, mean={d:.4}\n", .{ label, glyph_count, d.max, d.mean });
    return d;
}

// ── Caller-owned pipelines (one per premultiplied family) ──

const FAMILIES = [_]contract.Family{ .text, .colr, .path, .hinted_text, .autohint };

const CallerPipelines = struct {
    pipeline_layout: vk.VkPipelineLayout,
    // Indexed by @intFromEnum(contract.Family); `.subpixel` is left null (this
    // grayscale vehicle doesn't exercise dual-source).
    pipelines: [std.enums.values(contract.Family).len]vk.VkPipeline = .{null} ** std.enums.values(contract.Family).len,

    fn init(ctx: snail.VulkanContext, desc_set_layout: vk.VkDescriptorSetLayout) !CallerPipelines {
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

        var self = CallerPipelines{ .pipeline_layout = pipeline_layout };
        errdefer for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(device, p, null);
        };
        for (FAMILIES) |family| {
            self.pipelines[@intFromEnum(family)] = try buildPipeline(ctx, pipeline_layout, contract.recipe(family));
        }
        return self;
    }

    fn record(
        self: *CallerPipelines,
        cmd: vk.VkCommandBuffer,
        desc_set: vk.VkDescriptorSet,
        vbo: vk.VkBuffer,
        ibo: vk.VkBuffer,
        draw_state: snail.DrawState,
        words: []const u32,
    ) void {
        vk.vkCmdBindIndexBuffer(cmd, ibo, 0, vk.VK_INDEX_TYPE_UINT32);

        // Y-flipped viewport (matches the reference so clip space agrees).
        const vp = vk.VkViewport{ .x = 0, .y = @floatFromInt(H), .width = @floatFromInt(W), .height = -@as(f32, @floatFromInt(H)), .minDepth = 0, .maxDepth = 1 };
        vk.vkCmdSetViewport(cmd, 0, 1, &vp);
        const scissor = vk.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = W, .height = H } };
        vk.vkCmdSetScissor(cmd, 0, 1, &scissor);

        var set = desc_set;
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &set, 0, null);

        var pc = contract.textPushConstants(draw_state, 0, true);
        vk.vkCmdPushConstants(cmd, self.pipeline_layout, contract.PUSH_CONSTANT_STAGE_FLAGS, 0, contract.PUSH_CONSTANT_SIZE, &pc);

        const stride: vk.VkDeviceSize = contract.vertexInputBinding().stride;
        var runs = contract.glyphRuns(words);
        while (runs.next()) |run| {
            const family = contract.familyForRunKind(run.kind);
            const pipeline = self.pipelines[@intFromEnum(family)];
            vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

            var buf = vbo;
            const offset: vk.VkDeviceSize = @as(vk.VkDeviceSize, run.glyph_start) * stride;
            vk.vkCmdBindVertexBuffers(cmd, 0, 1, &buf, &offset);
            vk.vkCmdDrawIndexed(cmd, contract.INDICES_PER_GLYPH, @intCast(run.glyph_count), 0, 0, 0);
        }
    }

    fn deinit(self: *CallerPipelines, device: vk.VkDevice) void {
        for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(device, p, null);
        }
        vk.vkDestroyPipelineLayout(device, self.pipeline_layout, null);
    }
};

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

// ── Host-visible caller buffer ──

const HostBuffer = struct {
    buffer: vk.VkBuffer,
    memory: vk.VkDeviceMemory,
    mapped: [*]u8,
    size: usize,

    fn init(ctx: snail.VulkanContext, size: usize, usage: vk.VkBufferUsageFlags) !HostBuffer {
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

    fn bytes(self: *HostBuffer) []u8 {
        return self.mapped[0..self.size];
    }

    fn deinit(self: *HostBuffer, device: vk.VkDevice) void {
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

fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}

const Diff = struct { max: u32, mean: f64 };

fn diff(a: []const u8, b: []const u8) Diff {
    var max: u32 = 0;
    var total: u64 = 0;
    const n = @min(a.len, b.len);
    for (0..n) |i| {
        const d = if (a[i] > b[i]) a[i] - b[i] else b[i] - a[i];
        if (d > max) max = d;
        total += d;
    }
    return .{ .max = max, .mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(n)) };
}
