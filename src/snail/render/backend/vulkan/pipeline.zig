const std = @import("std");
const subpixel_policy = @import("../subpixel_policy.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const texture_layers = @import("../../format/texture_layers.zig");
const upload_common = @import("../../format/upload_common.zig");
const vertex = @import("../../format/vertex.zig");
const snail_mod = @import("../../../root.zig");
const SubpixelOrder = @import("../../format/subpixel_order.zig").SubpixelOrder;
const DrawState = snail_mod.DrawState;
const vulkan_types = @import("types.zig");
const vulkan_resources = @import("resources.zig");
const vulkan_upload_new = @import("../../../vulkan_upload.zig");
const draw_records_mod = @import("../../../draw_records.zig");

pub const vk = vulkan_types.vk;

const build_options = @import("build_options");
const pipeline_constants = @import("constants.zig");
const vulkan_device = @import("device.zig");
const vulkan_graphics = @import("graphics_pipeline.zig");
const vulkan_upload = @import("upload.zig");
const check = vulkan_device.check;
// ── Push constants layout (matches GLSL) ──

const PushConstants = extern struct {
    mvp: [16]f32, // mat4, column-major
    viewport: [2]f32,
    subpixel_order: i32 = 1, // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    output_srgb: i32 = 0, // 0 = emit linear, 1 = sRGB-encode before write
    layer_base: i32 = 0,
    coverage_exponent: f32 = 1.0,
};

comptime {
    if (@sizeOf(PushConstants) != 88) @compileError("PushConstants must be 88 bytes");
}

pub const VulkanContext = vulkan_types.VulkanContext;
pub const TextCoverageProgram = vulkan_types.TextCoverageProgram;

// ── Constants ──

// Partition the persistently mapped upload buffer by frame slot so a frame can
// suballocate monotonically without overwriting earlier draws before submit.
pub const UPLOAD_SLOTS = pipeline_constants.UPLOAD_SLOTS;
pub const UPLOAD_SLOT_BYTES = pipeline_constants.UPLOAD_SLOT_BYTES;
pub const RING_TOTAL_BYTES = pipeline_constants.RING_TOTAL_BYTES;
pub const BYTES_PER_GLYPH = pipeline_constants.BYTES_PER_GLYPH;
pub const MAX_GLYPHS_PER_FRAME = pipeline_constants.MAX_GLYPHS_PER_FRAME;

const CurveAtlas = atlas_curve_mod.CurveAtlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const AtlasSlot = vulkan_resources.AtlasSlot;
const ImageSlot = vulkan_resources.ImageSlot;
const AtlasPageUpload = vulkan_resources.AtlasPageUpload;
const ResourceBank = vulkan_resources.ResourceBank;
const atlasPagesInBank = vulkan_resources.atlasPagesInBank;
const retainPage = vulkan_resources.retainPage;
pub const PreparedResources = vulkan_resources.PreparedResources;

pub const ReplicatedKind = enum(u8) {
    text,
    text_subpixel_dual,
    colr,
    path,
    hinted_text,
};

const ReplicatedSlot = struct {
    kind: ReplicatedKind = .text,
    m: u32 = 0,
    pipeline: vk.VkPipeline = null,
};

// ── Internal helpers ──

pub const VulkanPipeline = struct {
    ctx: VulkanContext = undefined,
    initialized: bool = false,

    pipeline_text: vk.VkPipeline = null,
    pipeline_colr: vk.VkPipeline = null,
    pipeline_path: vk.VkPipeline = null,
    pipeline_hinted_text: vk.VkPipeline = null,
    pipeline_text_subpixel_dual: vk.VkPipeline = null,
    pipeline_cache: vk.VkPipelineCache = null,
    pipeline_layout: vk.VkPipelineLayout = null,
    desc_set_layout: vk.VkDescriptorSetLayout = null,

    /// Replicated draw-path pipeline cache. Each entry pairs a (kind, M)
    /// with a fully built `VkPipeline` that has shape stream binding 0
    /// with hardware divisor M and override stream binding 1 with
    /// divisor 1. Lazily populated on first replicated draw for each
    /// unique M. 32 slots covers any sane workload.
    replicated_pipelines: [32]ReplicatedSlot = .{ReplicatedSlot{}} ** 32,
    replicated_pipeline_count: u8 = 0,

    vertex_buffer: vk.VkBuffer = null,
    vertex_memory: vk.VkDeviceMemory = null,
    persistent_map: ?[*]u8 = null,
    active_upload_slot: u32 = 0,
    upload_cursor: usize = 0,

    index_buffer: vk.VkBuffer = null,
    index_memory: vk.VkDeviceMemory = null,

    sampler_nearest: vk.VkSampler = null,
    sampler_linear: vk.VkSampler = null,

    // Transfer command pool (one-shot uploads)
    transfer_cmd_pool: vk.VkCommandPool = null,
    scheduled_resource_upload_cmd: vk.VkCommandBuffer = null,

    // Per-frame state
    active_cmd: vk.VkCommandBuffer = null,
    resource_cache: ?PreparedResources = null,

    // ── Init / Deinit ──

    pub fn init(self: *VulkanPipeline, vk_ctx: VulkanContext) !void {
        self.ctx = vk_ctx;
        errdefer self.deinitResources();

        try self.initSamplers();
        try self.initDescriptorSetLayout();
        try self.initPipelineLayout();
        try self.createPipelineCache();

        // Create draw pipelines during renderer init so draw never creates pipelines.
        try self.warmGraphicsPipelines();

        try self.initVertexUploadRing();
        try self.initTransferCommandPool();
        try self.initIndexBuffer();

        self.initialized = true;
    }

    fn initSamplers(self: *VulkanPipeline) !void {
        const sampler_info = std.mem.zeroInit(vk.VkSamplerCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = vk.VK_FILTER_NEAREST,
            .minFilter = vk.VK_FILTER_NEAREST,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        });
        try check(vk.vkCreateSampler(self.ctx.device, &sampler_info, null, &self.sampler_nearest));

        const linear_sampler_info = std.mem.zeroInit(vk.VkSamplerCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = vk.VK_FILTER_LINEAR,
            .minFilter = vk.VK_FILTER_LINEAR,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        });
        try check(vk.vkCreateSampler(self.ctx.device, &linear_sampler_info, null, &self.sampler_linear));
    }

    fn initDescriptorSetLayout(self: *VulkanPipeline) !void {
        var bindings: [4]vk.VkDescriptorSetLayoutBinding = undefined;
        bindings[0] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 0,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[0].pImmutableSamplers = &self.sampler_nearest;
        bindings[1] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[1].pImmutableSamplers = &self.sampler_nearest;
        bindings[2] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 2,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[2].pImmutableSamplers = &self.sampler_nearest;
        bindings[3] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = 3,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[3].pImmutableSamplers = &self.sampler_linear;

        const dsl_info = std.mem.zeroInit(vk.VkDescriptorSetLayoutCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 4,
            .pBindings = &bindings,
        });
        try check(vk.vkCreateDescriptorSetLayout(self.ctx.device, &dsl_info, null, &self.desc_set_layout));
    }

    fn initPipelineLayout(self: *VulkanPipeline) !void {
        const push_range = std.mem.zeroInit(vk.VkPushConstantRange, .{
            .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .offset = 0,
            .size = @sizeOf(PushConstants),
        });

        var pl_info: vk.VkPipelineLayoutCreateInfo = std.mem.zeroes(vk.VkPipelineLayoutCreateInfo);
        pl_info.sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        pl_info.setLayoutCount = 1;
        pl_info.pSetLayouts = @ptrCast(&self.desc_set_layout);
        pl_info.pushConstantRangeCount = 1;
        pl_info.pPushConstantRanges = &push_range;
        try check(vk.vkCreatePipelineLayout(self.ctx.device, &pl_info, null, &self.pipeline_layout));
    }

    fn initVertexUploadRing(self: *VulkanPipeline) !void {
        try self.createBuffer(
            RING_TOTAL_BYTES,
            vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.vertex_buffer,
            &self.vertex_memory,
        );
        var map_ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.ctx.device, self.vertex_memory, 0, RING_TOTAL_BYTES, 0, &map_ptr));
        self.persistent_map = @ptrCast(map_ptr);
    }

    fn initTransferCommandPool(self: *VulkanPipeline) !void {
        const cp_info = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
            .queueFamilyIndex = self.ctx.queue_family_index,
        });
        try check(vk.vkCreateCommandPool(self.ctx.device, &cp_info, null, &self.transfer_cmd_pool));
    }

    pub fn deinit(self: *VulkanPipeline) void {
        if (!self.initialized) return;
        self.deinitResources();
    }

    fn deinitResources(self: *VulkanPipeline) void {
        // Caller-owned frame synchronization must make renderer teardown safe.
        // Keep deinit free of implicit device-wide waits.
        if (self.resource_cache) |*cache| {
            cache.deinit();
            self.resource_cache = null;
        }
        if (self.transfer_cmd_pool != null) vk.vkDestroyCommandPool(self.ctx.device, self.transfer_cmd_pool, null);
        self.transfer_cmd_pool = null;
        if (self.index_buffer != null) {
            vk.vkDestroyBuffer(self.ctx.device, self.index_buffer, null);
            vk.vkFreeMemory(self.ctx.device, self.index_memory, null);
        }
        self.index_buffer = null;
        self.index_memory = null;
        if (self.vertex_buffer != null) {
            if (self.persistent_map != null) vk.vkUnmapMemory(self.ctx.device, self.vertex_memory);
            vk.vkDestroyBuffer(self.ctx.device, self.vertex_buffer, null);
            vk.vkFreeMemory(self.ctx.device, self.vertex_memory, null);
        }
        self.vertex_buffer = null;
        self.vertex_memory = null;
        self.persistent_map = null;
        if (self.pipeline_text_subpixel_dual != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_text_subpixel_dual, null);
        if (self.pipeline_hinted_text != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_hinted_text, null);
        if (self.pipeline_path != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_path, null);
        if (self.pipeline_colr != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_colr, null);
        if (self.pipeline_text != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_text, null);
        for (self.replicated_pipelines[0..self.replicated_pipeline_count]) |slot| {
            if (slot.pipeline != null) vk.vkDestroyPipeline(self.ctx.device, slot.pipeline, null);
        }
        self.replicated_pipeline_count = 0;
        if (self.pipeline_cache != null) vk.vkDestroyPipelineCache(self.ctx.device, self.pipeline_cache, null);
        if (self.pipeline_layout != null) vk.vkDestroyPipelineLayout(self.ctx.device, self.pipeline_layout, null);
        if (self.desc_set_layout != null) vk.vkDestroyDescriptorSetLayout(self.ctx.device, self.desc_set_layout, null);
        if (self.sampler_linear != null) vk.vkDestroySampler(self.ctx.device, self.sampler_linear, null);
        if (self.sampler_nearest != null) vk.vkDestroySampler(self.ctx.device, self.sampler_nearest, null);

        self.pipeline_text_subpixel_dual = null;
        self.pipeline_hinted_text = null;
        self.pipeline_path = null;
        self.pipeline_colr = null;
        self.pipeline_text = null;
        self.pipeline_cache = null;
        self.pipeline_layout = null;
        self.desc_set_layout = null;
        self.sampler_linear = null;
        self.sampler_nearest = null;
        self.initialized = false;
    }

    pub fn resourceCache(self: *VulkanPipeline, allocator: std.mem.Allocator) !*PreparedResources {
        if (self.resource_cache == null) {
            self.resource_cache = try PreparedResources.init(self.ctx, self.desc_set_layout, allocator);
        }
        if (self.resource_cache) |*cache| return cache;
        unreachable;
    }

    pub fn resetResourceCache(self: *VulkanPipeline) void {
        if (self.resource_cache) |*cache| {
            const allocator = cache.allocator;
            const generation = cache.generation +% 1;
            cache.deinit();
            cache.* = PreparedResources.init(self.ctx, self.desc_set_layout, allocator) catch {
                self.resource_cache = null;
                return;
            };
            cache.generation = generation;
        }
    }

    pub fn resourceCacheStats(self: *const VulkanPipeline) snail_mod.ResourceCacheStats {
        if (self.resource_cache) |*cache| {
            const active_atlas_pages = atlasPagesInBank(cache.atlas_slots[0..cache.atlas_slot_count], cache.active_atlas_bank_id);
            const active_image_layers: u32 = @intCast(cache.image_slot_count);
            var atlas_pages = active_atlas_pages;
            var atlas_layers = cache.allocated_layer_count;
            var image_layers_resident = active_image_layers;
            var image_layers = cache.allocated_image_count;
            for (cache.atlas_banks[0..cache.atlas_bank_count]) |bank| {
                atlas_pages += bank.resident_atlas_pages;
                atlas_layers += bank.allocated_layer_count;
                image_layers_resident += bank.resident_image_layers;
                image_layers += bank.allocated_image_count;
            }
            return .{
                .generation = cache.generation,
                .active_atlas_pages_resident = active_atlas_pages,
                .active_atlas_layers_allocated = cache.allocated_layer_count,
                .atlas_pages_resident = atlas_pages,
                .atlas_layers_allocated = atlas_layers,
                .active_image_layers_resident = active_image_layers,
                .active_image_layers_allocated = cache.allocated_image_count,
                .image_layers_resident = image_layers_resident,
                .image_layers_allocated = image_layers,
            };
        }
        return .{};
    }

    pub fn backendName(self: *const VulkanPipeline) [:0]const u8 {
        _ = self;
        return "Vulkan";
    }

    // ── Command buffer (set by caller per-frame) ──

    pub fn setCommandBuffer(self: *VulkanPipeline, cmd: anytype) void {
        self.active_cmd = @ptrCast(cmd);
    }

    pub fn clearCommandBuffer(self: *VulkanPipeline) void {
        self.active_cmd = null;
    }

    pub fn setFrameSlot(self: *VulkanPipeline, slot: u32) void {
        std.debug.assert(slot < UPLOAD_SLOTS);
        self.active_upload_slot = slot;
        self.upload_cursor = 0;
    }

    pub fn textCoverageDescriptorSetLayout(self: *const VulkanPipeline) vk.VkDescriptorSetLayout {
        return self.desc_set_layout;
    }

    pub fn textCoveragePipelineLayout(self: *const VulkanPipeline) vk.VkPipelineLayout {
        return self.pipeline_layout;
    }

    /// Use a caller-owned, already-recording command buffer for resource
    /// uploads. The caller must submit it; PreparedResources retains staging
    /// buffers until the prepared object is retired.
    pub fn beginResourceUploadRecording(self: *VulkanPipeline, cmd: anytype) void {
        vulkan_upload.beginResourceUploadRecording(self, cmd);
    }

    pub fn endResourceUploadRecording(self: *VulkanPipeline) void {
        vulkan_upload.endResourceUploadRecording(self);
    }

    // ── Texture array management ──

    pub fn uploadPreparedAtlases(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) !void {
        try vulkan_upload.uploadPreparedAtlases(self, prepared, atlases, out_views);
    }

    pub fn uploadPreparedAtlasesWithCapacityModes(
        self: *VulkanPipeline,
        prepared: *PreparedResources,
        atlases: []const *const CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
    ) !void {
        try vulkan_upload.uploadPreparedAtlasesWithCapacityModes(self, prepared, atlases, capacity_modes, out_views);
    }

    pub fn uploadPreparedAtlasesAndLayerInfoWithCapacityModes(
        self: *VulkanPipeline,
        prepared: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        try vulkan_upload.uploadPreparedAtlasesAndLayerInfoWithCapacityModes(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
    }

    pub fn uploadPreparedImages(self: *VulkanPipeline, prepared: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image, out_views: anytype) !void {
        try vulkan_upload.uploadPreparedImages(self, prepared, scratch, images, out_views);
    }

    fn drawTextInternal(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, state: DrawState, texture_layer_base: u32, allow_subpixel: bool) !void {
        const cmd = self.active_cmd orelse return error.MissingCommandBuffer;
        if (vertices.len == 0) return;

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;
        const bank_id = texture_layers.bank(texture_layer_base);
        const bank = prepared.bankForId(bank_id) orelse return error.MissingPreparedResource;
        const local_layer_base = texture_layers.bankLocal(texture_layer_base);

        vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&bank.desc_set), 0, null);
        setViewportAndScissor(cmd, state.surface.pixel_width, state.surface.pixel_height);

        const draw_context = TextDrawContext{
            .cmd = cmd,
            .vertices = vertices,
            .state = state,
            .local_layer_base = local_layer_base,
            .allow_subpixel = allow_subpixel,
            .total_glyphs = total_glyphs,
        };
        if (!prepared.atlas_has_special_text_runs) {
            try self.drawRegularTextRun(draw_context);
            return;
        }
        try self.drawSpecialTextRuns(draw_context);
    }

    const TextDrawContext = struct {
        cmd: vk.VkCommandBuffer,
        vertices: []const u32,
        state: DrawState,
        local_layer_base: u32,
        allow_subpixel: bool,
        total_glyphs: usize,
    };

    fn drawRegularTextRun(self: *VulkanPipeline, context: TextDrawContext) !void {
        const render_mode = subpixel_policy.chooseTextRenderMode(
            context.vertices,
            context.state.mvp,
            context.allow_subpixel,
            context.state.raster.subpixel_order,
            self.ctx.supports_dual_source_blend,
        );
        const pip = switch (render_mode) {
            .grayscale => try self.ensureTextPipeline(),
            .subpixel_dual_source => try self.ensureTextSubpixelDualPipeline(),
        };
        vk.vkCmdBindPipeline(context.cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);
        self.pushTextConstants(context.cmd, context.state, context.local_layer_base, render_mode);
        try self.drawGlyphRange(context.vertices, 0, context.total_glyphs);
    }

    fn drawSpecialTextRuns(self: *VulkanPipeline, context: TextDrawContext) !void {
        var run_start: usize = 0;
        while (run_start < context.total_glyphs) {
            const run_kind = subpixel_policy.glyphRunKind(context.vertices, run_start);
            const run_end = subpixel_policy.glyphRunEnd(context.vertices, run_start, run_kind);

            const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
                .grayscale
            else
                subpixel_policy.chooseTextRenderModeRange(
                    context.vertices,
                    run_start,
                    run_end - run_start,
                    context.state.mvp,
                    context.allow_subpixel,
                    context.state.raster.subpixel_order,
                    self.ctx.supports_dual_source_blend,
                );
            const pip = switch (run_kind) {
                .regular => switch (run_mode) {
                    .grayscale => try self.ensureTextPipeline(),
                    .subpixel_dual_source => try self.ensureTextSubpixelDualPipeline(),
                },
                .colr => try self.ensureColrPipeline(),
                .path => try self.ensurePathPipeline(),
                .hinted_text => try self.ensureHintedTextPipeline(),
            };
            vk.vkCmdBindPipeline(context.cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);
            self.pushTextConstants(context.cmd, context.state, context.local_layer_base, run_mode);
            try self.drawGlyphRange(context.vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    pub fn pushTextConstants(self: *VulkanPipeline, cmd: vk.VkCommandBuffer, state: DrawState, local_layer_base: u32, render_mode: subpixel_policy.TextRenderMode) void {
        const pc = PushConstants{
            .mvp = state.mvp.data,
            .viewport = .{ state.surface.pixel_width, state.surface.pixel_height },
            .subpixel_order = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else state.raster.subpixel_order),
            .output_srgb = if (state.surface.encoding.shaderEncodesSrgb()) 1 else 0,
            .layer_base = @intCast(local_layer_base),
            .coverage_exponent = state.raster.coverage_transfer.shaderExponent(),
        };
        vk.vkCmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);
    }

    pub fn drawTextPrepared(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        try self.drawTextInternal(prepared, vertices, state, texture_layer_base, true);
    }

    pub fn bindTextCoverageProgram(self: *VulkanPipeline, prepared: *const PreparedResources, program: TextCoverageProgram) !void {
        const cmd = self.active_cmd orelse return error.MissingCommandBuffer;
        const layout = if (program.pipeline_layout != null) program.pipeline_layout else self.pipeline_layout;
        vk.vkCmdBindDescriptorSets(
            cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            layout,
            program.descriptor_set_index,
            1,
            @ptrCast(&prepared.desc_set),
            0,
            null,
        );
    }

    pub fn drawPreparedTextCoverage(self: *VulkanPipeline, vertices: []const u32) !void {
        const cmd = self.active_cmd orelse return error.MissingCommandBuffer;
        if (vertices.len == 0) return;
        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;
        vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        try self.drawGlyphRange(vertices, 0, total_glyphs);
    }

    pub fn drawPathsPrepared(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        const cmd = self.active_cmd orelse return error.MissingCommandBuffer;
        if (vertices.len == 0) return;

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;
        const bank_id = texture_layers.bank(texture_layer_base);
        const bank = prepared.bankForId(bank_id) orelse return error.MissingPreparedResource;
        const local_layer_base = texture_layers.bankLocal(texture_layer_base);

        vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&bank.desc_set), 0, null);
        setViewportAndScissor(cmd, state.surface.pixel_width, state.surface.pixel_height);

        const render_mode: subpixel_policy.TextRenderMode = .grayscale;
        const pip = try self.ensurePathPipeline();
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);

        const pc = PushConstants{
            .mvp = state.mvp.data,
            .viewport = .{ state.surface.pixel_width, state.surface.pixel_height },
            .subpixel_order = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else state.raster.subpixel_order),
            .output_srgb = if (state.surface.encoding.shaderEncodesSrgb()) 1 else 0,
            .layer_base = @intCast(local_layer_base),
            .coverage_exponent = state.raster.coverage_transfer.shaderExponent(),
        };
        vk.vkCmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);
        try self.drawGlyphRange(vertices, 0, total_glyphs);
    }

    pub fn beginDraw(self: *VulkanPipeline) void {
        // No-op for Vulkan (ring buffer handles frame separation)
        _ = self;
    }

    // ── New-API draw entry (Phase 5c) ──

    pub const NewDrawError = error{
        MissingBinding,
        StaleBinding,
        MalformedSegment,
        MissingCommandBuffer,
    } || std.mem.Allocator.Error || anyerror;

    /// Walk `DrawRecords.segments` and dispatch via the new-API draw
    /// module. The implementation lives in `draw_new_api.zig`; this
    /// shim exists to keep the public surface on `VulkanPipeline`
    /// stable for callers that go through the snail adapter layer.
    pub fn drawNewApi(
        self: *VulkanPipeline,
        scratch: std.mem.Allocator,
        draw_state: DrawState,
        records: draw_records_mod.DrawRecords,
        caches: []const *const vulkan_upload_new.VulkanPreparedPages,
    ) NewDrawError!void {
        return @import("draw_new_api.zig").drawNewApi(self, scratch, draw_state, records, caches);
    }

    pub fn newApiPipelineShape(self: *const VulkanPipeline) vulkan_upload_new.PipelineShape {
        return .{
            .ctx = self.ctx,
            .transfer_cmd_pool = self.transfer_cmd_pool,
            .scheduled_resource_upload_cmd = self.scheduled_resource_upload_cmd,
            .sampler_nearest = self.sampler_nearest,
            .sampler_linear = self.sampler_linear,
            .desc_set_layout = self.desc_set_layout,
        };
    }

    // ── Internal helpers ──

    fn createPipelineCache(self: *VulkanPipeline) !void {
        try vulkan_graphics.createPipelineCache(self);
    }

    fn warmGraphicsPipelines(self: *VulkanPipeline) !void {
        try vulkan_graphics.warmGraphicsPipelines(self);
    }

    pub fn ensureTextPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return vulkan_graphics.ensureTextPipeline(self);
    }

    pub fn ensureColrPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return vulkan_graphics.ensureColrPipeline(self);
    }

    pub fn ensurePathPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return vulkan_graphics.ensurePathPipeline(self);
    }

    pub fn ensureHintedTextPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return vulkan_graphics.ensureHintedTextPipeline(self);
    }

    pub fn ensureTextSubpixelDualPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return vulkan_graphics.ensureTextSubpixelDualPipeline(self);
    }

    pub fn drawGlyphRange(self: *VulkanPipeline, vertices: []const u32, glyph_offset: usize, glyph_count: usize) !void {
        try vulkan_graphics.drawGlyphRange(self, vertices, glyph_offset, glyph_count);
    }

    fn createBuffer(self: *const VulkanPipeline, size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, memory: *vk.VkDeviceMemory) !void {
        try vulkan_device.createBuffer(self, size, usage, properties, buffer, memory);
    }

    fn initIndexBuffer(self: *VulkanPipeline) !void {
        try vulkan_graphics.initIndexBuffer(self);
    }
};

fn setViewportAndScissor(cmd: vk.VkCommandBuffer, viewport_w: f32, viewport_h: f32) void {
    const vp = vk.VkViewport{
        .x = 0,
        .y = viewport_h,
        .width = viewport_w,
        .height = -viewport_h,
        .minDepth = 0,
        .maxDepth = 1,
    };
    vk.vkCmdSetViewport(cmd, 0, 1, &vp);

    const scissor = vk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = @intFromFloat(viewport_w), .height = @intFromFloat(viewport_h) },
    };
    vk.vkCmdSetScissor(cmd, 0, 1, &scissor);
}

