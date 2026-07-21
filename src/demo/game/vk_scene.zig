//! Vulkan scene renderer for the game demo — the Vulkan analog of
//! `gl_scene.GlSceneRenderer`. Records the whole scene into a caller-provided
//! command buffer (inside an active render pass with a depth attachment):
//!   1. the custom-material coverage quad (its own pipeline; samples snail
//!      coverage via the atlas plane in set 0 + a records SSBO in set 1;
//!      depth-tests + writes so it occludes),
//!   2. the depth-tested occluded label, the translucent panel, and the HUD,
//!      all via `embed_vulkan.Renderer` (built with depth_test=true).
//!
//! Platform-agnostic: the windowed driver and the offscreen screenshot harness
//! both build one of these and hand it a command buffer.

const std = @import("std");
const snail = @import("snail");
const embed_vulkan = @import("embed_vulkan");
const scene_mod = @import("scene.zig");
const game_shaders = @import("game_shaders.zig");
const passes = @import("passes.zig");

pub const vk = embed_vulkan.vk;
const Scene = scene_mod.Scene;
const PreparedPass = passes.PreparedPass;

/// Push constants for the material pipeline (matches glsl/game_material.*).
const MaterialPush = extern struct {
    mvp: [16]f32,
    base_color: [4]f32,
    light_dir: [4]f32, // xyz = tangent-space light
    scene_size: [2]f32,
    glyph_count: i32,
    output_srgb: i32,
    relief: f32,
    roughness: f32,
};

const SLOT_BYTES: usize = 4 * 1024 * 1024;

fn check(r: vk.VkResult) !void {
    if (r != vk.VK_SUCCESS) return error.VulkanError;
}

pub const VkSceneRenderer = struct {
    allocator: std.mem.Allocator,
    ctx: embed_vulkan.VulkanContext,
    layout: embed_vulkan.VulkanResourceLayout,
    transfer_pool: vk.VkCommandPool,
    cache: embed_vulkan.VulkanDeviceAtlas,
    caller: embed_vulkan.Renderer,

    material_pipeline: vk.VkPipeline = null,
    material_layout: vk.VkPipelineLayout = null,
    ssbo_set_layout: vk.VkDescriptorSetLayout = null,
    ssbo_pool: vk.VkDescriptorPool = null,
    ssbo_set: vk.VkDescriptorSet = null,
    records: embed_vulkan.HostBuffer,
    quad: embed_vulkan.HostBuffer,
    glyph_count: i32 = 0,

    material_b: snail.render.records.Binding,
    label_path_b: snail.render.records.Binding,
    label_text_b: snail.render.records.Binding,
    panel_path_b: snail.render.records.Binding,
    panel_text_b: snail.render.records.Binding,
    hud_path_b: snail.render.records.Binding,
    hud_text_b: snail.render.records.Binding,

    scratch: []snail.render.records.Instance,
    segs: [4]snail.render.records.DrawBatch = undefined,

    pub fn init(allocator: std.mem.Allocator, ctx: embed_vulkan.VulkanContext, scene: *Scene, num_slots: u32) !VkSceneRenderer {
        var layout: embed_vulkan.VulkanResourceLayout = undefined;
        try layout.init(ctx);
        errdefer layout.deinit();
        const transfer_pool = try embed_vulkan.createTransferPool(ctx);
        errdefer vk.vkDestroyCommandPool(ctx.device, transfer_pool, null);

        // Upload every atlas the scene needs in one decoupled upload.
        var bindings: [7]snail.render.records.Binding = undefined;
        var cache = try embed_vulkan.cacheWithDecoupledUpload(allocator, ctx, scene.fonts.pool, &layout, &.{
            &scene.material.text_atlas,
            &scene.label.path_atlas,
            &scene.label.text_atlas,
            &scene.panel.path_atlas,
            &scene.panel.text_atlas,
            &scene.hud.path_atlas,
            &scene.hud.text_atlas,
        }, &bindings, .{
            .max_bindings = 16,
            .layer_info_height = 128,
            .max_images = 8,
            .max_image_width = 128,
            .max_image_height = 128,
        });
        errdefer cache.deinit();

        var caller = try embed_vulkan.Renderer.init(ctx, cache.descriptorSetLayout(), SLOT_BYTES, num_slots, true);
        errdefer caller.deinit();

        var self = VkSceneRenderer{
            .allocator = allocator,
            .ctx = ctx,
            .layout = layout,
            .transfer_pool = transfer_pool,
            .cache = cache,
            .caller = caller,
            .records = undefined,
            .quad = undefined,
            .material_b = bindings[0],
            .label_path_b = bindings[1],
            .label_text_b = bindings[2],
            .panel_path_b = bindings[3],
            .panel_text_b = bindings[4],
            .hud_path_b = bindings[5],
            .hud_text_b = bindings[6],
            .scratch = try allocator.alloc(snail.render.records.Instance, maxShapeBudget(scene)),
        };
        errdefer allocator.free(self.scratch);

        try self.buildRecords(scene);
        errdefer self.records.deinit(ctx.device);
        try self.buildQuad();
        errdefer self.quad.deinit(ctx.device);
        try self.buildSsboSet();
        try self.buildMaterialPipeline();
        return self;
    }

    pub fn deinit(self: *VkSceneRenderer) void {
        const device = self.ctx.device;
        _ = vk.vkDeviceWaitIdle(device);
        if (self.material_pipeline != null) vk.vkDestroyPipeline(device, self.material_pipeline, null);
        if (self.material_layout != null) vk.vkDestroyPipelineLayout(device, self.material_layout, null);
        if (self.ssbo_pool != null) vk.vkDestroyDescriptorPool(device, self.ssbo_pool, null);
        if (self.ssbo_set_layout != null) vk.vkDestroyDescriptorSetLayout(device, self.ssbo_set_layout, null);
        self.quad.deinit(device);
        self.records.deinit(device);
        self.allocator.free(self.scratch);
        self.caller.deinit();
        self.cache.deinit();
        vk.vkDestroyCommandPool(device, self.transfer_pool, null);
        self.layout.deinit();
        self.* = undefined;
    }

    fn maxShapeBudget(scene: *Scene) usize {
        var m: usize = 0;
        for ([_]*const PreparedPass{ &scene.material, &scene.label, &scene.panel, &scene.hud }) |p| {
            const n = p.path_picture.shapes.len + p.text_picture.shapes.len;
            if (n > m) m = n;
        }
        return @max(m, 1);
    }

    fn buildRecords(self: *VkSceneRenderer, scene: *Scene) !void {
        const shapes = scene.material.text_picture.shapes;
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try snail.emit.emit(self.scratch, &self.segs, &wlen, &slen, self.material_b, &scene.material.text_atlas, shapes, .identity, .{ 1, 1, 1, 1 });
        self.glyph_count = @intCast(wlen);
        self.records = try embed_vulkan.HostBuffer.init(self.ctx, @max(wlen * snail.render.records.BYTES_PER_INSTANCE, 4), vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
        @memcpy(self.records.bytes()[0 .. wlen * snail.render.records.BYTES_PER_INSTANCE], std.mem.sliceAsBytes(self.scratch[0..wlen]));
    }

    fn buildQuad(self: *VkSceneRenderer) !void {
        // 2 triangles, pos(3) + uv(2), in [-0.5,0.5]² with uv [0,1].
        const verts = [_]f32{
            -0.5, -0.5, 0, 0, 0,
            0.5,  -0.5, 0, 1, 0,
            0.5,  0.5,  0, 1, 1,
            -0.5, -0.5, 0, 0, 0,
            0.5,  0.5,  0, 1, 1,
            -0.5, 0.5,  0, 0, 1,
        };
        self.quad = try embed_vulkan.HostBuffer.init(self.ctx, @sizeOf(@TypeOf(verts)), vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        @memcpy(self.quad.bytes()[0..@sizeOf(@TypeOf(verts))], std.mem.sliceAsBytes(verts[0..]));
    }

    fn buildSsboSet(self: *VkSceneRenderer) !void {
        const device = self.ctx.device;
        const binding = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 0,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        const dsl_ci = std.mem.zeroInit(vk.VkDescriptorSetLayoutCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 1,
            .pBindings = &binding,
        });
        try check(vk.vkCreateDescriptorSetLayout(device, &dsl_ci, null, &self.ssbo_set_layout));

        const pool_size = vk.VkDescriptorPoolSize{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1 };
        const pool_ci = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
        });
        try check(vk.vkCreateDescriptorPool(device, &pool_ci, null, &self.ssbo_pool));

        var set_layout = self.ssbo_set_layout;
        const alloc_info = std.mem.zeroInit(vk.VkDescriptorSetAllocateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = self.ssbo_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &set_layout,
        });
        try check(vk.vkAllocateDescriptorSets(device, &alloc_info, &self.ssbo_set));

        const buf_info = vk.VkDescriptorBufferInfo{ .buffer = self.records.buffer, .offset = 0, .range = vk.VK_WHOLE_SIZE };
        const write = std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = self.ssbo_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buf_info,
        });
        vk.vkUpdateDescriptorSets(device, 1, &write, 0, null);
    }

    fn buildMaterialPipeline(self: *VkSceneRenderer) !void {
        const device = self.ctx.device;
        const push_range = std.mem.zeroInit(vk.VkPushConstantRange, .{
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .offset = 0,
            .size = @sizeOf(MaterialPush),
        });
        var set_layouts = [2]vk.VkDescriptorSetLayout{ self.cache.descriptorSetLayout(), self.ssbo_set_layout };
        const pl_ci = std.mem.zeroInit(vk.VkPipelineLayoutCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 2,
            .pSetLayouts = &set_layouts,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &push_range,
        });
        try check(vk.vkCreatePipelineLayout(device, &pl_ci, null, &self.material_layout));

        const vert_module = try shaderModule(device, game_shaders.vert_spv);
        defer vk.vkDestroyShaderModule(device, vert_module, null);
        const frag_module = try shaderModule(device, game_shaders.frag_spv);
        defer vk.vkDestroyShaderModule(device, frag_module, null);
        const stages = [2]vk.VkPipelineShaderStageCreateInfo{
            std.mem.zeroInit(vk.VkPipelineShaderStageCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert_module, .pName = "main" }),
            std.mem.zeroInit(vk.VkPipelineShaderStageCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag_module, .pName = "main" }),
        };

        const vi_binding = vk.VkVertexInputBindingDescription{ .binding = 0, .stride = 5 * @sizeOf(f32), .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX };
        const vi_attrs = [2]vk.VkVertexInputAttributeDescription{
            .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 },
            .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 3 * @sizeOf(f32) },
        };
        const vi_info = std.mem.zeroInit(vk.VkPipelineVertexInputStateCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &vi_binding,
            .vertexAttributeDescriptionCount = 2,
            .pVertexAttributeDescriptions = &vi_attrs,
        });
        const ia_info = std.mem.zeroInit(vk.VkPipelineInputAssemblyStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST });
        const vp_info = std.mem.zeroInit(vk.VkPipelineViewportStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO, .viewportCount = 1, .scissorCount = 1 });
        const rast_info = std.mem.zeroInit(vk.VkPipelineRasterizationStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO, .polygonMode = vk.VK_POLYGON_MODE_FILL, .cullMode = vk.VK_CULL_MODE_NONE, .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE, .lineWidth = 1.0 });
        const ms_info = std.mem.zeroInit(vk.VkPipelineMultisampleStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT });
        const blend_attach = std.mem.zeroInit(vk.VkPipelineColorBlendAttachmentState, .{
            .blendEnable = vk.VK_FALSE,
            .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        });
        const blend_info = std.mem.zeroInit(vk.VkPipelineColorBlendStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, .attachmentCount = 1, .pAttachments = &blend_attach });
        const ds_info = std.mem.zeroInit(vk.VkPipelineDepthStencilStateCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = vk.VK_TRUE,
            .depthWriteEnable = vk.VK_TRUE,
            .depthCompareOp = vk.VK_COMPARE_OP_LESS_OR_EQUAL,
        });
        const dyn_states = [2]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
        const dyn_info = std.mem.zeroInit(vk.VkPipelineDynamicStateCreateInfo, .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = 2, .pDynamicStates = &dyn_states });

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
            .layout = self.material_layout,
            .renderPass = self.ctx.render_pass,
        });
        try check(vk.vkCreateGraphicsPipelines(device, null, 1, &ci, null, &self.material_pipeline));
    }

    /// Record the whole scene. `view_proj` must already include the Vulkan
    /// clip-space Z fix (see `scene.vulkan_z_fix`).
    pub fn record(self: *VkSceneRenderer, cmd: vk.VkCommandBuffer, frame_index: u32, scene: *Scene, view_proj: snail.Mat4, surface: @import("snail-raster").TargetSurface) !void {
        self.caller.beginFrame(frame_index);
        const desc0 = self.cache.descriptorSet();
        const w = surface.pixel_width;
        const h = surface.pixel_height;

        // 1. Material quad (own pipeline; depth test + write).
        const vp = vk.VkViewport{ .x = 0, .y = h, .width = w, .height = -h, .minDepth = 0, .maxDepth = 1 };
        vk.vkCmdSetViewport(cmd, 0, 1, &vp);
        const scissor = vk.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = @intFromFloat(@max(w, 0)), .height = @intFromFloat(@max(h, 0)) } };
        vk.vkCmdSetScissor(cmd, 0, 1, &scissor);
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.material_pipeline);
        var sets = [2]vk.VkDescriptorSet{ desc0, self.ssbo_set };
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.material_layout, 0, 2, &sets, 0, null);
        const ld = scene.materialLightDir();
        var push = MaterialPush{
            .mvp = snail.Mat4.multiply(view_proj, scene.material_model).data,
            .base_color = scene_mod.material_base_color,
            .light_dir = .{ ld[0], ld[1], ld[2], 0.0 },
            .scene_size = .{ scene_mod.material_scene_w, scene_mod.material_scene_h },
            .glyph_count = self.glyph_count,
            .output_srgb = 0,
            .relief = scene_mod.material_relief,
            .roughness = scene_mod.material_roughness,
        };
        vk.vkCmdPushConstants(cmd, self.material_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(MaterialPush), &push);
        var quad_buf = self.quad.buffer;
        var quad_off: vk.VkDeviceSize = 0;
        vk.vkCmdBindVertexBuffers(cmd, 0, 1, &quad_buf, &quad_off);
        vk.vkCmdDraw(cmd, 6, 1, 0, 0);

        // 2/3. Label + translucent panel, depth-tested against the material
        // quad but writing no depth, so drawn back-to-front among themselves
        // (see Scene.labelBeforePanel) — otherwise the panel paints over a
        // nearer label.
        if (scene.labelBeforePanel()) {
            try self.drawSnailPass(cmd, desc0, &scene.label, self.label_path_b, self.label_text_b, scene.label_plane.mvp(view_proj), surface);
            try self.drawSnailPass(cmd, desc0, &scene.panel, self.panel_path_b, self.panel_text_b, scene.panel_plane.mvp(view_proj), surface);
        } else {
            try self.drawSnailPass(cmd, desc0, &scene.panel, self.panel_path_b, self.panel_text_b, scene.panel_plane.mvp(view_proj), surface);
            try self.drawSnailPass(cmd, desc0, &scene.label, self.label_path_b, self.label_text_b, scene.label_plane.mvp(view_proj), surface);
        }
        // 4. HUD.
        const hud_mvp = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        try self.drawSnailPass(cmd, desc0, &scene.hud, self.hud_path_b, self.hud_text_b, hud_mvp, surface);
    }

    fn drawSnailPass(self: *VkSceneRenderer, cmd: vk.VkCommandBuffer, desc0: vk.VkDescriptorSet, pass: *const PreparedPass, path_b: snail.render.records.Binding, text_b: snail.render.records.Binding, mvp: snail.Mat4, surface: @import("snail-raster").TargetSurface) !void {
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try snail.emit.emit(self.scratch, &self.segs, &wlen, &slen, path_b, &pass.path_atlas, pass.path_picture.shapes, .identity, .{ 1, 1, 1, 1 });
        _ = try snail.emit.emit(self.scratch, &self.segs, &wlen, &slen, text_b, &pass.text_atlas, pass.text_picture.shapes, .identity, .{ 1, 1, 1, 1 });
        const ds = @import("snail-raster").DrawState{ .mvp = mvp, .surface = surface, .raster = .{} };
        self.caller.render(cmd, desc0, ds, self.scratch[0..wlen], self.segs[0..slen]);
    }
};

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
