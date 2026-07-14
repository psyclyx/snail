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

    const cache_opts: snail.vulkan.backend_cache.CacheOptions = .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    };

    // ── Reference path: the all-in-one renderer + its own cache ──
    var vk_renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer vk_renderer.deinit();
    var ref_cache = try snail.VulkanBackendCache.init(allocator, content.pool, vk_renderer.state.pipelineShape(), cache_opts);
    defer ref_cache.deinit();
    var ref_bindings: [2]snail.Binding = undefined;
    try ref_cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &ref_bindings);

    // ── Standalone embeddable path: our OWN resource layout + transfer command
    //    pool + cache, built via the public contract — no VulkanRenderer. ──
    var layout: snail.vulkan.VulkanResourceLayout = undefined;
    try layout.init(vk_ctx);
    defer layout.deinit();
    const transfer_pool = try createTransferPool(vk_ctx);
    defer vk.vkDestroyCommandPool(vk_ctx.device, transfer_pool, null);
    var sa_cache = try snail.VulkanBackendCache.init(allocator, content.pool, snail.vulkan.embeddable.cachePipelineShape(vk_ctx, &layout, transfer_pool), cache_opts);
    defer sa_cache.deinit();
    var sa_bindings: [2]snail.Binding = undefined;
    try sa_cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &sa_bindings);

    var caller = try CallerPipelines.init(vk_ctx, sa_cache.descriptorSetLayout());
    defer caller.deinit(vk_ctx.device);

    // One quad index buffer, shared across all draws.
    var ibo = try HostBuffer.init(vk_ctx, @sizeOf(@TypeOf(contract.QUAD_INDICES)), vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
    defer ibo.deinit(vk_ctx.device);
    @memcpy(ibo.bytes()[0..@sizeOf(@TypeOf(contract.QUAD_INDICES))], std.mem.sliceAsBytes(contract.QUAD_INDICES[0..]));

    const clear = [4]f32{
        harness.srgbToLinear(harness.bg_srgb_f32[0]),
        harness.srgbToLinear(harness.bg_srgb_f32[1]),
        harness.srgbToLinear(harness.bg_srgb_f32[2]),
        harness.bg_srgb_f32[3],
    };
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const gray_ds = harness.drawState(W, H);
    // Subpixel (LCD) draw state: regular runs take the dual-source pipeline
    // when the device supports it (else the all-in-one and caller both fall
    // back to grayscale, and the diff still holds).
    const sub_ds = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .rgb, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };

    // Two emit buffer sets: the reference emits against its cache's bindings,
    // the caller against the standalone cache's — each self-consistent.
    const budget = snail.emit.wordBudget(content.paths_picture.shapes.len, 0) + snail.emit.wordBudget(content.text_picture.shapes.len, 0);
    var buf = try EmitBuffers.init(allocator, budget);
    defer buf.deinit(allocator);

    var worst: u32 = 0;

    // Paths only (single path segment).
    {
        const r = try buf.emitPicture(.ref, ref_bindings[0], &content.paths_atlas, content.paths_picture.shapes);
        const c = try buf.emitPicture(.caller, sa_bindings[0], &content.paths_atlas, content.paths_picture.shapes);
        const d = try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, ibo.buffer, vk_ctx, clear, gray_ds, r, c, "paths        ");
        worst = @max(worst, d.max);
    }
    // Text only — grayscale and subpixel reuse one emit per side.
    {
        const r = try buf.emitPicture(.ref, ref_bindings[1], &content.text_atlas, content.text_picture.shapes);
        const c = try buf.emitPicture(.caller, sa_bindings[1], &content.text_atlas, content.text_picture.shapes);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, ibo.buffer, vk_ctx, clear, gray_ds, r, c, "text gray    ")).max);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, ibo.buffer, vk_ctx, clear, sub_ds, r, c, "text subpixel")).max);
    }
    // Full scene: paths + text in one frame (two segments, run-dispatched).
    {
        const r = try buf.emitScene(.ref, &content, ref_bindings);
        const c = try buf.emitScene(.caller, &content, sa_bindings);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, ibo.buffer, vk_ctx, clear, gray_ds, r, c, "full scene   ")).max);
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
    ref_cache: *snail.VulkanBackendCache,
    caller: *CallerPipelines,
    sa_cache: *snail.VulkanBackendCache,
    ibo: vk.VkBuffer,
    vk_ctx: snail.VulkanContext,
    clear: [4]f32,
    draw_state: snail.DrawState,
    ref: Emitted,
    call: Emitted,
    label: []const u8,
) !Diff {
    const glyph_count: u32 = @intCast(ref.words.len / snail.WORDS_PER_INSTANCE);

    // Reference: the all-in-one VulkanRenderer + its cache.
    {
        const cmd = platform.beginFrameOffscreenWithClear(clear);
        vk_renderer.state.setCommandBuffer(cmd);
        defer vk_renderer.state.clearCommandBuffer();
        vk_renderer.state.setFrameSlot(platform.currentOffscreenFrameIndex());
        try vk_renderer.state.draw(allocator, draw_state, .{ .words = ref.words, .segments = ref.segs }, &.{ref_cache});
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_ref = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_ref);

    // Caller: standalone cache + our own pipelines, run-dispatched per segment.
    var vbo = try HostBuffer.init(vk_ctx, call.words.len * @sizeOf(u32), vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
    defer vbo.deinit(vk_ctx.device);
    @memcpy(vbo.bytes()[0 .. call.words.len * @sizeOf(u32)], std.mem.sliceAsBytes(call.words));
    {
        const platform_cmd = platform.beginFrameOffscreenWithClear(clear);
        const cmd: vk.VkCommandBuffer = @ptrCast(platform_cmd);
        caller.record(cmd, sa_cache.descriptorSet(), vbo.buffer, ibo, draw_state, call.words, call.segs);
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_emb = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_emb);

    const d = diff(pixels_ref, pixels_emb);
    std.debug.print("embeddable-vulkan [{s}]: {d} glyphs, max delta={d}, mean={d:.4}\n", .{ label, glyph_count, d.max, d.mean });
    return d;
}

const Emitted = struct { words: []const u32, segs: []const snail.DrawSegment };

const Side = enum { ref, caller };

// Two emit buffer sets — the reference emits against its cache's bindings, the
// caller against the standalone cache's.
const EmitBuffers = struct {
    ref_words: []u32,
    ref_segs: []snail.DrawSegment,
    ca_words: []u32,
    ca_segs: []snail.DrawSegment,

    fn init(a: std.mem.Allocator, budget: usize) !EmitBuffers {
        return .{
            .ref_words = try a.alloc(u32, budget),
            .ref_segs = try a.alloc(snail.DrawSegment, 16),
            .ca_words = try a.alloc(u32, budget),
            .ca_segs = try a.alloc(snail.DrawSegment, 16),
        };
    }

    fn deinit(self: *EmitBuffers, a: std.mem.Allocator) void {
        a.free(self.ref_words);
        a.free(self.ref_segs);
        a.free(self.ca_words);
        a.free(self.ca_segs);
    }

    fn pick(self: *EmitBuffers, side: Side) struct { w: []u32, s: []snail.DrawSegment } {
        return switch (side) {
            .ref => .{ .w = self.ref_words, .s = self.ref_segs },
            .caller => .{ .w = self.ca_words, .s = self.ca_segs },
        };
    }

    fn emitPicture(self: *EmitBuffers, side: Side, binding: snail.Binding, atlas: *const snail.Atlas, shapes: anytype) !Emitted {
        const b = self.pick(side);
        var wl: usize = 0;
        var sl: usize = 0;
        _ = try snail.emit.emit(b.w, b.s, &wl, &sl, binding, atlas, shapes, .identity, .{ 1, 1, 1, 1 });
        return .{ .words = b.w[0..wl], .segs = b.s[0..sl] };
    }

    fn emitScene(self: *EmitBuffers, side: Side, content: anytype, bindings: [2]snail.Binding) !Emitted {
        const b = self.pick(side);
        const scene = harness.Scene{
            .pool = content.pool,
            .paths_atlas = &content.paths_atlas,
            .text_atlas = &content.text_atlas,
            .paths_picture = &content.paths_picture,
            .text_picture = &content.text_picture,
        };
        const e = try harness.emitScene(b.w, b.s, scene, bindings[0], bindings[1]);
        return .{ .words = b.w[0..e.words_len], .segs = b.s[0..e.segs_len] };
    }
};

fn createTransferPool(ctx: snail.VulkanContext) !vk.VkCommandPool {
    const ci = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = ctx.queue_family_index,
    });
    var pool: vk.VkCommandPool = null;
    try check(vk.vkCreateCommandPool(ctx.device, &ci, null, &pool));
    return pool;
}

// ── Caller-owned pipelines (one per premultiplied family) ──

// The premultiplied families are always built; subpixel is built only when the
// device supports dual-source blend.
const PREMUL_FAMILIES = [_]contract.Family{ .text, .colr, .path, .hinted_text, .autohint };

const CallerPipelines = struct {
    pipeline_layout: vk.VkPipelineLayout,
    // Indexed by @intFromEnum(contract.Family).
    pipelines: [std.enums.values(contract.Family).len]vk.VkPipeline = .{null} ** std.enums.values(contract.Family).len,
    supports_dual_src: bool,

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

        var self = CallerPipelines{ .pipeline_layout = pipeline_layout, .supports_dual_src = ctx.supports_dual_source_blend };
        errdefer for (self.pipelines) |p| {
            if (p != null) vk.vkDestroyPipeline(device, p, null);
        };
        for (PREMUL_FAMILIES) |family| {
            self.pipelines[@intFromEnum(family)] = try buildPipeline(ctx, pipeline_layout, contract.recipe(family));
        }
        if (self.supports_dual_src) {
            self.pipelines[@intFromEnum(contract.Family.subpixel)] = try buildPipeline(ctx, pipeline_layout, contract.recipe(.subpixel));
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
        segments: []const snail.DrawSegment,
    ) void {
        vk.vkCmdBindIndexBuffer(cmd, ibo, 0, vk.VK_INDEX_TYPE_UINT32);

        // Y-flipped viewport (matches the reference so clip space agrees).
        const vp = vk.VkViewport{ .x = 0, .y = @floatFromInt(H), .width = @floatFromInt(W), .height = -@as(f32, @floatFromInt(H)), .minDepth = 0, .maxDepth = 1 };
        vk.vkCmdSetViewport(cmd, 0, 1, &vp);
        const scissor = vk.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = W, .height = H } };
        vk.vkCmdSetScissor(cmd, 0, 1, &scissor);

        var set = desc_set;
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &set, 0, null);

        for (segments) |seg| {
            const seg_words = words[seg.words_offset..][0 .. seg.words_len];
            var runs = contract.glyphRuns(seg_words);
            while (runs.next()) |run| {
                // Regular runs pick grayscale vs subpixel per the shared policy;
                // every other kind is grayscale.
                const mode: contract.TextRenderMode = if (run.kind == .regular)
                    contract.textRenderMode(seg_words, run.glyph_start, run.glyph_count, draw_state, self.supports_dual_src)
                else
                    .grayscale;
                const family = contract.familyForRun(run.kind, mode);
                vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[@intFromEnum(family)]);

                var pc = contract.textPushConstants(draw_state, 0, mode == .grayscale);
                vk.vkCmdPushConstants(cmd, self.pipeline_layout, contract.PUSH_CONSTANT_STAGE_FLAGS, 0, contract.PUSH_CONSTANT_SIZE, &pc);

                // Absolute word index of this run in the full vertex buffer.
                const abs_word = seg.words_offset + run.glyph_start * snail.WORDS_PER_INSTANCE;
                var buf = vbo;
                const offset: vk.VkDeviceSize = @as(vk.VkDeviceSize, abs_word) * @sizeOf(u32);
                vk.vkCmdBindVertexBuffers(cmd, 0, 1, &buf, &offset);
                vk.vkCmdDrawIndexed(cmd, contract.INDICES_PER_GLYPH, @intCast(run.glyph_count), 0, 0, 0);
            }
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
