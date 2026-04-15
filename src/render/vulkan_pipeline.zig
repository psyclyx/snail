const std = @import("std");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;
const snail_mod = @import("../snail.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

pub const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
});

const build_options = @import("build_options");
const vk_shaders = @import("vulkan_shaders");

// ── SPIR-V shader bytecode ──

const vert_spv = vk_shaders.vert_spv;
const frag_spv = vk_shaders.frag_spv;
const frag_subpixel_spv = vk_shaders.frag_subpixel_spv;

// ── Push constants layout (matches GLSL) ──

const PushConstants = extern struct {
    mvp: [16]f32, // mat4, column-major
    viewport: [2]f32,
    fill_rule: i32,
    subpixel_order: i32 = 1, // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR; replaces former padding
};

comptime {
    if (@sizeOf(PushConstants) != 80) @compileError("PushConstants must be 80 bytes");
}

// ── Initialization context (provided by caller) ──

pub const VulkanContext = struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    color_format: vk.VkFormat,
};

// ── Module state ──

var ctx: VulkanContext = undefined;
var initialized: bool = false;

var pipeline_normal: vk.VkPipeline = null;
var pipeline_subpixel: vk.VkPipeline = null;
var pipeline_layout: vk.VkPipelineLayout = null;
var desc_set_layout: vk.VkDescriptorSetLayout = null;
var desc_pool: vk.VkDescriptorPool = null;
var desc_set: vk.VkDescriptorSet = null;

// Vertex ring buffer — must have enough segments so that in-flight frames
// never share a segment.  With MAX_FRAMES_IN_FLIGHT=2 and up to 2 draw
// calls per frame (scene + HUD), we need at least 4 segments.
const RING_SEGMENTS = 4;
const RING_TOTAL_BYTES = 16 * 1024 * 1024; // 16 MB
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_GLYPH = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH * @sizeOf(f32);
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

var vertex_buffer: vk.VkBuffer = null;
var vertex_memory: vk.VkDeviceMemory = null;
var persistent_map: ?[*]u8 = null;
var ring_segment: u32 = 0;

var index_buffer: vk.VkBuffer = null;
var index_memory: vk.VkDeviceMemory = null;

// Textures
var curve_image: vk.VkImage = null;
var curve_view: vk.VkImageView = null;
var curve_memory: vk.VkDeviceMemory = null;
var band_image: vk.VkImage = null;
var band_view: vk.VkImageView = null;
var band_memory: vk.VkDeviceMemory = null;
var sampler_nearest: vk.VkSampler = null;

// Transfer command pool (one-shot uploads)
var transfer_cmd_pool: vk.VkCommandPool = null;

// Per-frame state
var active_cmd: vk.VkCommandBuffer = null;
pub var subpixel_order: SubpixelOrder = .none;
pub var fill_rule: FillRule = .non_zero;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

// ── Init / Deinit ──

pub fn init(vk_ctx: VulkanContext) !void {
    ctx = vk_ctx;

    // Sampler
    const sampler_info = std.mem.zeroInit(vk.VkSamplerCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.VK_FILTER_NEAREST,
        .minFilter = vk.VK_FILTER_NEAREST,
        .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
        .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
    });
    try check(vk.vkCreateSampler(ctx.device, &sampler_info, null, &sampler_nearest));

    // Descriptor set layout: 2 combined image samplers
    const bindings = [2]vk.VkDescriptorSetLayoutBinding{
        std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 0,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = &sampler_nearest,
        }),
        std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = &sampler_nearest,
        }),
    };
    const dsl_info = std.mem.zeroInit(vk.VkDescriptorSetLayoutCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 2,
        .pBindings = &bindings,
    });
    try check(vk.vkCreateDescriptorSetLayout(ctx.device, &dsl_info, null, &desc_set_layout));

    // Push constant range
    const push_range = std.mem.zeroInit(vk.VkPushConstantRange, .{
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = @sizeOf(PushConstants),
    });

    // Pipeline layout
    var pl_info: vk.VkPipelineLayoutCreateInfo = std.mem.zeroes(vk.VkPipelineLayoutCreateInfo);
    pl_info.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pl_info.setLayoutCount = 1;
    pl_info.pSetLayouts = @ptrCast(&desc_set_layout);
    pl_info.pushConstantRangeCount = 1;
    pl_info.pPushConstantRanges = &push_range;
    try check(vk.vkCreatePipelineLayout(ctx.device, &pl_info, null, &pipeline_layout));

    // Descriptor pool + set
    const pool_size = [1]vk.VkDescriptorPoolSize{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 2 },
    };
    const dp_info = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    });
    try check(vk.vkCreateDescriptorPool(ctx.device, &dp_info, null, &desc_pool));

    var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
    ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ds_info.descriptorPool = desc_pool;
    ds_info.descriptorSetCount = 1;
    ds_info.pSetLayouts = @ptrCast(&desc_set_layout);
    try check(vk.vkAllocateDescriptorSets(ctx.device, &ds_info, &desc_set));

    // Graphics pipelines
    pipeline_normal = try createGraphicsPipeline(frag_spv);
    pipeline_subpixel = try createGraphicsPipeline(frag_subpixel_spv);

    // Vertex ring buffer (persistent mapped)
    try createBuffer(
        RING_TOTAL_BYTES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vertex_buffer,
        &vertex_memory,
    );
    var map_ptr: ?*anyopaque = null;
    try check(vk.vkMapMemory(ctx.device, vertex_memory, 0, RING_TOTAL_BYTES, 0, &map_ptr));
    persistent_map = @ptrCast(map_ptr);

    // Transfer command pool
    const cp_info = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = ctx.queue_family_index,
    });
    try check(vk.vkCreateCommandPool(ctx.device, &cp_info, null, &transfer_cmd_pool));

    // Index buffer: deterministic quad pattern, generated once for max segment capacity
    try initIndexBuffer();

    initialized = true;
}

pub fn deinit() void {
    if (!initialized) return;
    _ = vk.vkDeviceWaitIdle(ctx.device);

    if (transfer_cmd_pool != null) vk.vkDestroyCommandPool(ctx.device, transfer_cmd_pool, null);
    destroyTextureResources();
    if (sampler_nearest != null) vk.vkDestroySampler(ctx.device, sampler_nearest, null);
    if (index_buffer != null) {
        vk.vkDestroyBuffer(ctx.device, index_buffer, null);
        vk.vkFreeMemory(ctx.device, index_memory, null);
    }
    if (vertex_buffer != null) {
        vk.vkUnmapMemory(ctx.device, vertex_memory);
        vk.vkDestroyBuffer(ctx.device, vertex_buffer, null);
        vk.vkFreeMemory(ctx.device, vertex_memory, null);
    }
    if (desc_pool != null) vk.vkDestroyDescriptorPool(ctx.device, desc_pool, null);
    if (desc_set_layout != null) vk.vkDestroyDescriptorSetLayout(ctx.device, desc_set_layout, null);
    if (pipeline_subpixel != null) vk.vkDestroyPipeline(ctx.device, pipeline_subpixel, null);
    if (pipeline_normal != null) vk.vkDestroyPipeline(ctx.device, pipeline_normal, null);
    if (pipeline_layout != null) vk.vkDestroyPipelineLayout(ctx.device, pipeline_layout, null);

    persistent_map = null;
    initialized = false;
}

pub fn getBackendName() []const u8 {
    return "Vulkan";
}

// ── Command buffer (set by caller per-frame) ──

pub fn setCommandBuffer(cmd: anytype) void {
    active_cmd = @ptrCast(cmd);
}

// ── Texture array management ──

pub fn buildTextureArrays(atlases: []const *const snail_mod.Atlas) void {
    _ = vk.vkDeviceWaitIdle(ctx.device);
    destroyTextureResources();

    const layer_count: u32 = @intCast(atlases.len);
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    for (atlases) |a| {
        if (a.curve_height > max_curve_h) max_curve_h = a.curve_height;
        if (a.band_height > max_band_h) max_band_h = a.band_height;
    }

    const curve_w = atlases[0].curve_width;
    const band_w = atlases[0].band_width;

    // Create images
    curve_image = createImage2DArray(curve_w, max_curve_h, layer_count, vk.VK_FORMAT_R16G16B16A16_SFLOAT) catch return;
    curve_memory = allocateImageMemory(curve_image) catch return;
    _ = vk.vkBindImageMemory(ctx.device, curve_image, curve_memory, 0);

    band_image = createImage2DArray(band_w, max_band_h, layer_count, vk.VK_FORMAT_R16G16_UINT) catch return;
    band_memory = allocateImageMemory(band_image) catch return;
    _ = vk.vkBindImageMemory(ctx.device, band_image, band_memory, 0);

    // Upload via staging buffer
    uploadTextureData(atlases, curve_w, max_curve_h, band_w, max_band_h, layer_count) catch return;

    // Create image views
    curve_view = createImageView(curve_image, vk.VK_FORMAT_R16G16B16A16_SFLOAT, layer_count) catch return;
    band_view = createImageView(band_image, vk.VK_FORMAT_R16G16_UINT, layer_count) catch return;

    // Set atlas layer indices
    for (atlases, 0..) |atlas, i| {
        @constCast(atlas).gl_layer = @intCast(i);
    }

    // Update descriptor set
    const image_infos = [2]vk.VkDescriptorImageInfo{
        .{
            .sampler = sampler_nearest,
            .imageView = curve_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        },
        .{
            .sampler = sampler_nearest,
            .imageView = band_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        },
    };
    const writes = [2]vk.VkWriteDescriptorSet{
        std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = desc_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_infos[0],
        }),
        std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = desc_set,
            .dstBinding = 1,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_infos[1],
        }),
    };
    vk.vkUpdateDescriptorSets(ctx.device, 2, &writes, 0, null);
}

// ── Draw ──

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    const cmd = active_cmd orelse return;
    if (vertices.len == 0) return;

    const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    const total_glyphs = vertices.len / floats_per_glyph;
    if (total_glyphs == 0) return;

    // Bind pipeline + state (shared across all chunks)
    const pip = if (subpixel_order != .none) pipeline_subpixel else pipeline_normal;
    vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);
    vk.vkCmdBindIndexBuffer(cmd, index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_layout, 0, 1, @ptrCast(&desc_set), 0, null);

    const pc = PushConstants{
        .mvp = mvp.data,
        .viewport = .{ viewport_w, viewport_h },
        .fill_rule = @intFromEnum(fill_rule),
        .subpixel_order = @intFromEnum(subpixel_order),
    };
    vk.vkCmdPushConstants(cmd, pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);

    const vp = vk.VkViewport{
        .x = 0,
        .y = 0,
        .width = viewport_w,
        .height = viewport_h,
        .minDepth = 0,
        .maxDepth = 1,
    };
    vk.vkCmdSetViewport(cmd, 0, 1, &vp);

    const scissor = vk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = @intFromFloat(viewport_w), .height = @intFromFloat(viewport_h) },
    };
    vk.vkCmdSetScissor(cmd, 0, 1, &scissor);

    // Draw in chunks that fit within a single ring segment
    var glyphs_drawn: usize = 0;
    while (glyphs_drawn < total_glyphs) {
        const chunk: usize = @min(total_glyphs - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
        const float_offset = glyphs_drawn * floats_per_glyph;
        const byte_size = chunk * BYTES_PER_GLYPH;

        const ring_offset: vk.VkDeviceSize = @as(vk.VkDeviceSize, ring_segment) * RING_SEGMENT_BYTES;
        const dst = persistent_map.?[ring_offset..][0..byte_size];
        const src: [*]const u8 = @ptrCast(vertices[float_offset..].ptr);
        @memcpy(dst, src[0..byte_size]);

        const offsets = [1]vk.VkDeviceSize{ring_offset};
        vk.vkCmdBindVertexBuffers(cmd, 0, 1, &vertex_buffer, &offsets);
        vk.vkCmdDrawIndexed(cmd, @intCast(chunk * 6), 1, 0, 0, 0);

        ring_segment = (ring_segment + 1) % RING_SEGMENTS;
        glyphs_drawn += chunk;
    }
}

pub fn resetFrameState() void {
    // No-op for Vulkan (ring buffer handles frame separation)
}

// ── Internal helpers ──

fn createGraphicsPipeline(frag_code: []const u8) !vk.VkPipeline {
    const vert_module = try createShaderModule(vert_spv);
    defer vk.vkDestroyShaderModule(ctx.device, vert_module, null);
    const frag_module = try createShaderModule(frag_code);
    defer vk.vkDestroyShaderModule(ctx.device, frag_module, null);

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

    // Vertex input: 5 vec4 attributes, single binding
    const stride: u32 = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    const binding = vk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = stride,
        .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    const attrs = [5]vk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 0 },
        .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 16 },
        .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 32 },
        .{ .location = 3, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 48 },
        .{ .location = 4, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = 64 },
    };

    const vi_info = std.mem.zeroInit(vk.VkPipelineVertexInputStateCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding,
        .vertexAttributeDescriptionCount = 5,
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
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
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
        .layout = pipeline_layout,
        .renderPass = ctx.render_pass,
        .subpass = 0,
    });

    var pip: vk.VkPipeline = null;
    try check(vk.vkCreateGraphicsPipelines(ctx.device, null, 1, &ci, null, &pip));
    return pip;
}

fn createShaderModule(code: []const u8) !vk.VkShaderModule {
    var ci: vk.VkShaderModuleCreateInfo = std.mem.zeroes(vk.VkShaderModuleCreateInfo);
    ci.sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    ci.codeSize = code.len;
    ci.pCode = @ptrCast(@alignCast(code.ptr));
    var module: vk.VkShaderModule = null;
    try check(vk.vkCreateShaderModule(ctx.device, &ci, null, &module));
    return module;
}

fn createBuffer(size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, memory: *vk.VkDeviceMemory) !void {
    const ci = std.mem.zeroInit(vk.VkBufferCreateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    });
    try check(vk.vkCreateBuffer(ctx.device, &ci, null, buffer));

    var req: vk.VkMemoryRequirements = undefined;
    vk.vkGetBufferMemoryRequirements(ctx.device, buffer.*, &req);

    const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = findMemoryType(req.memoryTypeBits, properties) orelse return error.NoSuitableMemory,
    });
    try check(vk.vkAllocateMemory(ctx.device, &ai, null, memory));
    try check(vk.vkBindBufferMemory(ctx.device, buffer.*, memory.*, 0));
}

fn findMemoryType(type_filter: u32, properties: vk.VkMemoryPropertyFlags) ?u32 {
    var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
    vk.vkGetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_props);

    for (0..mem_props.memoryTypeCount) |i| {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return @intCast(i);
        }
    }
    return null;
}

fn createImage2DArray(width: u32, height: u32, layers: u32, format: vk.VkFormat) !vk.VkImage {
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
    try check(vk.vkCreateImage(ctx.device, &ci, null, &image));
    return image;
}

fn allocateImageMemory(image: vk.VkImage) !vk.VkDeviceMemory {
    var req: vk.VkMemoryRequirements = undefined;
    vk.vkGetImageMemoryRequirements(ctx.device, image, &req);

    const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = findMemoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.NoSuitableMemory,
    });
    var memory: vk.VkDeviceMemory = null;
    try check(vk.vkAllocateMemory(ctx.device, &ai, null, &memory));
    return memory;
}

fn createImageView(image: vk.VkImage, format: vk.VkFormat, layer_count: u32) !vk.VkImageView {
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
    try check(vk.vkCreateImageView(ctx.device, &ci, null, &view));
    return view;
}

fn uploadTextureData(atlases: []const *const snail_mod.Atlas, _: u32, _: u32, _: u32, _: u32, layer_count: u32) !void {
    // Calculate staging buffer sizes
    const curve_px_bytes: usize = 4 * 2; // RGBA16F = 4 channels * 2 bytes
    const band_px_bytes: usize = 2 * 2; // RG16UI = 2 channels * 2 bytes

    var total_staging: usize = 0;
    for (atlases) |a| {
        total_staging += @as(usize, a.curve_width) * @as(usize, a.curve_height) * curve_px_bytes;
        total_staging += @as(usize, a.band_width) * @as(usize, a.band_height) * band_px_bytes;
    }

    // Create staging buffer
    var staging_buf: vk.VkBuffer = null;
    var staging_mem: vk.VkDeviceMemory = null;
    try createBuffer(
        @intCast(total_staging),
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &staging_buf,
        &staging_mem,
    );
    defer {
        vk.vkDestroyBuffer(ctx.device, staging_buf, null);
        vk.vkFreeMemory(ctx.device, staging_mem, null);
    }

    // Map and copy data
    var map_ptr: ?*anyopaque = null;
    try check(vk.vkMapMemory(ctx.device, staging_mem, 0, @intCast(total_staging), 0, &map_ptr));
    const staging_data: [*]u8 = @ptrCast(map_ptr);

    // Record copy regions
    var curve_regions: [256]vk.VkBufferImageCopy = undefined;
    var band_regions: [256]vk.VkBufferImageCopy = undefined;
    var staging_offset: usize = 0;

    for (atlases, 0..) |atlas, i| {
        // Copy curve data
        const curve_size = @as(usize, atlas.curve_width) * @as(usize, atlas.curve_height) * curve_px_bytes;
        const curve_bytes: [*]const u8 = @ptrCast(atlas.curve_data.ptr);
        @memcpy(staging_data[staging_offset..][0..curve_size], curve_bytes[0..curve_size]);
        var cr: vk.VkBufferImageCopy = std.mem.zeroes(vk.VkBufferImageCopy);
        cr.bufferOffset = @intCast(staging_offset);
        cr.imageSubresource.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT;
        cr.imageSubresource.baseArrayLayer = @intCast(i);
        cr.imageSubresource.layerCount = 1;
        cr.imageExtent = .{ .width = atlas.curve_width, .height = atlas.curve_height, .depth = 1 };
        curve_regions[i] = cr;
        staging_offset += curve_size;

        // Copy band data
        const band_size = @as(usize, atlas.band_width) * @as(usize, atlas.band_height) * band_px_bytes;
        const band_bytes: [*]const u8 = @ptrCast(atlas.band_data.ptr);
        @memcpy(staging_data[staging_offset..][0..band_size], band_bytes[0..band_size]);
        var br: vk.VkBufferImageCopy = std.mem.zeroes(vk.VkBufferImageCopy);
        br.bufferOffset = @intCast(staging_offset);
        br.imageSubresource.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT;
        br.imageSubresource.baseArrayLayer = @intCast(i);
        br.imageSubresource.layerCount = 1;
        br.imageExtent = .{ .width = atlas.band_width, .height = atlas.band_height, .depth = 1 };
        band_regions[i] = br;
        staging_offset += band_size;
    }

    vk.vkUnmapMemory(ctx.device, staging_mem);

    // Record transfer commands
    var cmd: vk.VkCommandBuffer = null;
    const alloc_info = std.mem.zeroInit(vk.VkCommandBufferAllocateInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = transfer_cmd_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    try check(vk.vkAllocateCommandBuffers(ctx.device, &alloc_info, &cmd));

    const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    try check(vk.vkBeginCommandBuffer(cmd, &begin_info));

    // Transition images UNDEFINED -> TRANSFER_DST
    transitionImageLayout(cmd, curve_image, layer_count, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    transitionImageLayout(cmd, band_image, layer_count, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    // Copy buffer to images
    vk.vkCmdCopyBufferToImage(cmd, staging_buf, curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, layer_count, &curve_regions);
    vk.vkCmdCopyBufferToImage(cmd, staging_buf, band_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, layer_count, &band_regions);

    // Transition TRANSFER_DST -> SHADER_READ_ONLY
    transitionImageLayout(cmd, curve_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    transitionImageLayout(cmd, band_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    try check(vk.vkEndCommandBuffer(cmd));

    // Submit and wait
    const submit_info = std.mem.zeroInit(vk.VkSubmitInfo, .{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    });
    try check(vk.vkQueueSubmit(ctx.graphics_queue, 1, &submit_info, null));
    _ = vk.vkQueueWaitIdle(ctx.graphics_queue);

    vk.vkFreeCommandBuffers(ctx.device, transfer_cmd_pool, 1, &cmd);
}

fn transitionImageLayout(cmd: vk.VkCommandBuffer, image: vk.VkImage, layer_count: u32, old_layout: vk.VkImageLayout, new_layout: vk.VkImageLayout) void {
    var src_stage: vk.VkPipelineStageFlags = 0;
    var dst_stage: vk.VkPipelineStageFlags = 0;
    var src_access: vk.VkAccessFlags = 0;
    var dst_access: vk.VkAccessFlags = 0;

    if (old_layout == vk.VK_IMAGE_LAYOUT_UNDEFINED and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        src_access = 0;
        dst_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        src_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        dst_access = vk.VK_ACCESS_SHADER_READ_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
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

fn initIndexBuffer() !void {
    const index_count: u32 = MAX_GLYPHS_PER_SEGMENT * 6;
    const buf_size: vk.VkDeviceSize = @as(vk.VkDeviceSize, index_count) * @sizeOf(u32);

    try createBuffer(
        buf_size,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &index_buffer,
        &index_memory,
    );

    // Map and generate the deterministic quad index pattern directly into GPU memory
    var map_ptr: ?*anyopaque = null;
    try check(vk.vkMapMemory(ctx.device, index_memory, 0, buf_size, 0, &map_ptr));
    const indices: [*]u32 = @ptrCast(@alignCast(map_ptr));

    for (0..MAX_GLYPHS_PER_SEGMENT) |i| {
        const base: u32 = @intCast(i * 4);
        const idx = i * 6;
        indices[idx + 0] = base + 0;
        indices[idx + 1] = base + 1;
        indices[idx + 2] = base + 2;
        indices[idx + 3] = base + 0;
        indices[idx + 4] = base + 2;
        indices[idx + 5] = base + 3;
    }

    vk.vkUnmapMemory(ctx.device, index_memory);
}

fn destroyTextureResources() void {
    if (curve_view != null) { vk.vkDestroyImageView(ctx.device, curve_view, null); curve_view = null; }
    if (curve_image != null) { vk.vkDestroyImage(ctx.device, curve_image, null); curve_image = null; }
    if (curve_memory != null) { vk.vkFreeMemory(ctx.device, curve_memory, null); curve_memory = null; }
    if (band_view != null) { vk.vkDestroyImageView(ctx.device, band_view, null); band_view = null; }
    if (band_image != null) { vk.vkDestroyImage(ctx.device, band_image, null); band_image = null; }
    if (band_memory != null) { vk.vkFreeMemory(ctx.device, band_memory, null); band_memory = null; }
}

fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
