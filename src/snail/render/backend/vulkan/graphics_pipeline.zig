const std = @import("std");
const vertex = @import("../../format/vertex.zig");
const vulkan_types = @import("types.zig");
const device = @import("device.zig");
const constants = @import("constants.zig");

pub const vk = vulkan_types.vk;
const vk_shaders = @import("vulkan_shaders");

const vert_spv = vk_shaders.vert_spv;
const frag_text_spv = vk_shaders.frag_text_spv;
const frag_colr_spv = vk_shaders.frag_colr_spv;
const frag_path_spv = vk_shaders.frag_path_spv;
const frag_text_subpixel_dual_spv = vk_shaders.frag_text_subpixel_dual_spv;

const UPLOAD_SLOT_BYTES = constants.UPLOAD_SLOT_BYTES;
const BYTES_PER_GLYPH = constants.BYTES_PER_GLYPH;

const BlendMode = enum {
    premultiplied,
    dual_source,
};

fn createGraphicsPipeline(self: anytype, frag_code: []const u8, blend_mode: BlendMode) !vk.VkPipeline {
    const vert_module = try createShaderModule(self, vert_spv);
    defer vk.vkDestroyShaderModule(self.ctx.device, vert_module, null);
    const frag_module = try createShaderModule(self, frag_code);
    defer vk.vkDestroyShaderModule(self.ctx.device, frag_module, null);

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

    // Vertex input: mixed-format per-instance attributes, single binding
    const stride: u32 = vertex.BYTES_PER_INSTANCE;
    const binding = vk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = stride,
        .inputRate = vk.VK_VERTEX_INPUT_RATE_INSTANCE,
    };

    const attrs = [7]vk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R16G16B16A16_SFLOAT, .offset = @offsetOf(vertex.Instance, "rect") },
        .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "xform") },
        .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(vertex.Instance, "origin") },
        .{ .location = 3, .binding = 0, .format = vk.VK_FORMAT_R32G32_UINT, .offset = @offsetOf(vertex.Instance, "glyph") },
        .{ .location = 4, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "band") },
        .{ .location = 5, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(vertex.Instance, "color") },
        .{ .location = 6, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(vertex.Instance, "tint") },
    };

    const vi_info = std.mem.zeroInit(vk.VkPipelineVertexInputStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding,
        .vertexAttributeDescriptionCount = attrs.len,
        .pVertexAttributeDescriptions = &attrs,
    });

    const ia_info = std.mem.zeroInit(vk.VkPipelineInputAssemblyStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    });

    // Dynamic viewport/scissor
    const dyn_states = [2]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dyn_info = std.mem.zeroInit(vk.VkPipelineDynamicStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2,
        .pDynamicStates = &dyn_states,
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

    // Premultiplied alpha blending: shader outputs (color * coverage, alpha * coverage),
    // so src factor is ONE to avoid double-multiplying coverage.
    const blend_attach = std.mem.zeroInit(vk.VkPipelineColorBlendAttachmentState, .{
        .blendEnable = @as(vk.VkBool32, 1),
        .srcColorBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE)),
        .dstColorBlendFactor = @as(vk.VkBlendFactor, @intCast(switch (blend_mode) {
            .premultiplied => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dual_source => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR,
        })),
        .colorBlendOp = @as(vk.VkBlendOp, @intCast(vk.VK_BLEND_OP_ADD)),
        .srcAlphaBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE)),
        .dstAlphaBlendFactor = @as(vk.VkBlendFactor, @intCast(vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)),
        .alphaBlendOp = @as(vk.VkBlendOp, @intCast(vk.VK_BLEND_OP_ADD)),
        .colorWriteMask = @as(vk.VkColorComponentFlags, @intCast(vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT)),
    });

    const blend_info = std.mem.zeroInit(vk.VkPipelineColorBlendStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &blend_attach,
    });

    const ds_info = std.mem.zeroInit(vk.VkPipelineDepthStencilStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    });

    const ci = std.mem.zeroInit(vk.VkGraphicsPipelineCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &stages,
        .pVertexInputState = &vi_info,
        .pInputAssemblyState = &ia_info,
        .pViewportState = &vp_info,
        .pRasterizationState = &rast_info,
        .pMultisampleState = &ms_info,
        .pDepthStencilState = &ds_info,
        .pColorBlendState = &blend_info,
        .pDynamicState = &dyn_info,
        .layout = self.pipeline_layout,
        .renderPass = self.ctx.render_pass,
        .subpass = 0,
    });

    var pip: vk.VkPipeline = null;
    try device.check(vk.vkCreateGraphicsPipelines(self.ctx.device, self.pipeline_cache, 1, &ci, null, &pip));
    return pip;
}

pub fn warmGraphicsPipelines(self: anytype) !void {
    self.pipeline_text = try createGraphicsPipeline(self, frag_text_spv, .premultiplied);
    self.pipeline_colr = try createGraphicsPipeline(self, frag_colr_spv, .premultiplied);
    self.pipeline_path = try createGraphicsPipeline(self, frag_path_spv, .premultiplied);
    if (self.ctx.supports_dual_source_blend) {
        self.pipeline_text_subpixel_dual = try createGraphicsPipeline(self, frag_text_subpixel_dual_spv, .dual_source);
    }
}

pub fn ensureTextPipeline(self: anytype) !vk.VkPipeline {
    return self.pipeline_text orelse error.PipelineUnavailable;
}

pub fn ensureColrPipeline(self: anytype) !vk.VkPipeline {
    return self.pipeline_colr orelse error.PipelineUnavailable;
}

pub fn ensurePathPipeline(self: anytype) !vk.VkPipeline {
    return self.pipeline_path orelse error.PipelineUnavailable;
}

pub fn ensureTextSubpixelDualPipeline(self: anytype) !vk.VkPipeline {
    return self.pipeline_text_subpixel_dual orelse error.PipelineUnavailable;
}

pub fn drawGlyphRange(self: anytype, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
    var glyphs_drawn: usize = 0;
    while (glyphs_drawn < glyph_count) {
        const available_bytes = UPLOAD_SLOT_BYTES - self.upload_cursor;
        const available_glyphs = available_bytes / BYTES_PER_GLYPH;
        if (available_glyphs == 0) @panic("Vulkan upload slot exhausted while drawing glyphs");
        const chunk: usize = @min(glyph_count - glyphs_drawn, available_glyphs);
        const word_offset = (glyph_offset + glyphs_drawn) * vertex.WORDS_PER_INSTANCE;
        const byte_size = chunk * BYTES_PER_GLYPH;

        const ring_offset: vk.VkDeviceSize = @as(vk.VkDeviceSize, self.active_upload_slot) * UPLOAD_SLOT_BYTES + self.upload_cursor;
        const dst = self.persistent_map.?[ring_offset..][0..byte_size];
        const src: [*]const u8 = @ptrCast(vertices[word_offset..].ptr);
        @memcpy(dst, src[0..byte_size]);

        const offsets = [1]vk.VkDeviceSize{ring_offset};
        vk.vkCmdBindVertexBuffers(self.active_cmd.?, 0, 1, &self.vertex_buffer, &offsets);
        vk.vkCmdDrawIndexed(self.active_cmd.?, 6, @intCast(chunk), 0, 0, 0);

        self.upload_cursor += byte_size;
        glyphs_drawn += chunk;
    }
}

pub fn createPipelineCache(self: anytype) !void {
    const ci = std.mem.zeroInit(vk.VkPipelineCacheCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
    });
    var cache: vk.VkPipelineCache = null;
    try device.check(vk.vkCreatePipelineCache(self.ctx.device, &ci, null, &cache));
    self.pipeline_cache = cache;
}

fn createShaderModule(self: anytype, code: []const u8) !vk.VkShaderModule {
    var ci: vk.VkShaderModuleCreateInfo = std.mem.zeroes(vk.VkShaderModuleCreateInfo);
    ci.sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = code.len;
    ci.pCode = @ptrCast(@alignCast(code.ptr));
    var module: vk.VkShaderModule = null;
    try device.check(vk.vkCreateShaderModule(self.ctx.device, &ci, null, &module));
    return module;
}

pub fn initIndexBuffer(self: anytype) !void {
    // Single quad index pattern — instancing repeats it per glyph.
    const buf_size: vk.VkDeviceSize = 6 * @sizeOf(u32);

    try device.createBuffer(
        self,
        buf_size,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &self.index_buffer,
        &self.index_memory,
    );

    var map_ptr: ?*anyopaque = null;
    try device.check(vk.vkMapMemory(self.ctx.device, self.index_memory, 0, buf_size, 0, &map_ptr));
    const indices: [*]u32 = @ptrCast(@alignCast(map_ptr));
    indices[0] = 0;
    indices[1] = 1;
    indices[2] = 2;
    indices[3] = 0;
    indices[4] = 2;
    indices[5] = 3;
    vk.vkUnmapMemory(self.ctx.device, self.index_memory);
}
