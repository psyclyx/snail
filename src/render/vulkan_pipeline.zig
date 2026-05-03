const std = @import("std");
const subpixel_policy = @import("subpixel_policy.zig");
const upload_common = @import("upload_common.zig");
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

extern "c" fn fseek(stream: *std.c.FILE, offset: c_long, whence: c_int) c_int;
extern "c" fn ftell(stream: *std.c.FILE) c_long;
extern "c" fn rewind(stream: *std.c.FILE) void;

// ── SPIR-V shader bytecode ──

const vert_spv = vk_shaders.vert_spv;
const frag_text_spv = vk_shaders.frag_text_spv;
const frag_colr_spv = vk_shaders.frag_colr_spv;
const frag_path_spv = vk_shaders.frag_path_spv;
const frag_text_subpixel_dual_spv = vk_shaders.frag_text_subpixel_dual_spv;
// ── Push constants layout (matches GLSL) ──

const PushConstants = extern struct {
    mvp: [16]f32, // mat4, column-major
    viewport: [2]f32,
    fill_rule: i32,
    subpixel_order: i32 = 1, // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    layer_base: i32 = 0,
};

comptime {
    if (@sizeOf(PushConstants) != 84) @compileError("PushConstants must be 84 bytes");
}

// ── Initialization context (provided by caller) ──

pub const VulkanContext = struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    color_format: vk.VkFormat,
    supports_dual_source_blend: bool = false,
};

// ── Constants ──

// Partition the persistently mapped upload buffer by frame slot so a frame can
// suballocate monotonically without overwriting earlier draws before submit.
const UPLOAD_SLOTS = 8;
const UPLOAD_SLOT_BYTES = 8 * 1024 * 1024; // 8 MB per frame slot
const RING_TOTAL_BYTES = UPLOAD_SLOTS * UPLOAD_SLOT_BYTES;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_FRAME = UPLOAD_SLOT_BYTES / BYTES_PER_GLYPH;

const MAX_ATLASES = upload_common.MAX_ATLASES;
const MAX_PAGES_PER_ATLAS = upload_common.MAX_PAGES_PER_ATLAS;
const MAX_IMAGES = upload_common.MAX_IMAGES;

const AtlasSlot = upload_common.AtlasSlot(snail_mod.lowlevel.CurveAtlas, snail_mod.lowlevel.AtlasPage, MAX_PAGES_PER_ATLAS);
const ImageSlot = upload_common.ImageSlot(snail_mod.Image);

const FillRule = snail_mod.FillRule;
const MAX_RESOURCE_UPLOAD_STAGING = MAX_ATLASES * 3 + MAX_IMAGES + 4;

const UploadStagingBuffer = struct {
    buffer: vk.VkBuffer = null,
    memory: vk.VkDeviceMemory = null,
};

const TransferCommand = struct {
    cmd: vk.VkCommandBuffer,
    owned: bool,
};

// ── Internal helpers ──

const BlendMode = enum {
    premultiplied,
    dual_source,
};

pub const PreparedResources = struct {
    ctx: VulkanContext,
    desc_pool: vk.VkDescriptorPool = null,
    desc_set: vk.VkDescriptorSet = null,

    curve_image: vk.VkImage = null,
    curve_view: vk.VkImageView = null,
    curve_memory: vk.VkDeviceMemory = null,
    band_image: vk.VkImage = null,
    band_view: vk.VkImageView = null,
    band_memory: vk.VkDeviceMemory = null,
    layer_image: vk.VkImage = null,
    layer_view: vk.VkImageView = null,
    layer_memory: vk.VkDeviceMemory = null,
    image_image: vk.VkImage = null,
    image_view: vk.VkImageView = null,
    image_memory: vk.VkDeviceMemory = null,

    atlas_slots: [MAX_ATLASES]AtlasSlot = std.mem.zeroes([MAX_ATLASES]AtlasSlot),
    atlas_slot_count: usize = 0,
    allocated_curve_height: u32 = 0,
    allocated_band_height: u32 = 0,
    allocated_layer_count: u32 = 0,
    atlas_has_special_text_runs: bool = false,
    image_slots: [MAX_IMAGES]ImageSlot = std.mem.zeroes([MAX_IMAGES]ImageSlot),
    image_slot_count: usize = 0,
    allocated_image_width: u32 = 0,
    allocated_image_height: u32 = 0,
    allocated_image_count: u32 = 0,
    upload_staging: [MAX_RESOURCE_UPLOAD_STAGING]UploadStagingBuffer = std.mem.zeroes([MAX_RESOURCE_UPLOAD_STAGING]UploadStagingBuffer),
    upload_staging_count: usize = 0,

    pub fn init(renderer: *const VulkanPipeline) !PreparedResources {
        var self = PreparedResources{ .ctx = renderer.ctx };
        errdefer self.deinit();

        const pool_size = [1]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 4 },
        };
        const dp_info = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
        });
        try check(vk.vkCreateDescriptorPool(self.ctx.device, &dp_info, null, &self.desc_pool));

        var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
        ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        ds_info.descriptorPool = self.desc_pool;
        ds_info.descriptorSetCount = 1;
        ds_info.pSetLayouts = @ptrCast(&renderer.desc_set_layout);
        try check(vk.vkAllocateDescriptorSets(self.ctx.device, &ds_info, &self.desc_set));

        return self;
    }

    pub fn deinit(self: *PreparedResources) void {
        self.destroyRetainedUploadStaging();
        self.destroyAtlasTextureResources();
        self.destroyImageResources();
        self.resetAtlasUploadState();
        if (self.desc_pool != null) vk.vkDestroyDescriptorPool(self.ctx.device, self.desc_pool, null);
        self.desc_pool = null;
        self.desc_set = null;
    }

    fn retainUploadStaging(self: *PreparedResources, buffer: vk.VkBuffer, memory: vk.VkDeviceMemory) !void {
        if (self.upload_staging_count >= self.upload_staging.len) return error.TooManyUploadStagingBuffers;
        self.upload_staging[self.upload_staging_count] = .{ .buffer = buffer, .memory = memory };
        self.upload_staging_count += 1;
    }

    fn destroyRetainedUploadStaging(self: *PreparedResources) void {
        for (self.upload_staging[0..self.upload_staging_count]) |staging| {
            if (staging.buffer != null) vk.vkDestroyBuffer(self.ctx.device, staging.buffer, null);
            if (staging.memory != null) vk.vkFreeMemory(self.ctx.device, staging.memory, null);
        }
        self.upload_staging_count = 0;
    }

    fn texturesReady(self: *const PreparedResources) bool {
        return self.curve_image != null and self.band_image != null and self.atlas_slot_count > 0;
    }

    fn atlasSlotsCompatible(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) bool {
        return upload_common.atlasSlotsCompatible(self.atlas_slots[0..], self.atlas_slot_count, atlases);
    }

    fn fillAtlasViews(self: *const PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, out_views: anytype) void {
        upload_common.fillAtlasViews(self.atlas_slots[0..], atlases, out_views);
    }

    fn currentImageView(self: *const PreparedResources, comptime ImageView: type, image: *const snail_mod.Image) ImageView {
        return upload_common.currentImageView(
            ImageView,
            self.image_slots[0..],
            self.image_slot_count,
            self.allocated_image_width,
            self.allocated_image_height,
            image,
        );
    }

    fn findImageSlot(self: *const PreparedResources, image: *const snail_mod.Image) ?usize {
        return upload_common.findImageSlot(self.image_slots[0..], self.image_slot_count, image);
    }

    fn resetAtlasUploadState(self: *PreparedResources) void {
        self.atlas_slot_count = 0;
        self.allocated_curve_height = 0;
        self.allocated_band_height = 0;
        self.allocated_layer_count = 0;
        self.atlas_has_special_text_runs = false;
        for (&self.atlas_slots) |*slot| slot.* = .{};
    }

    fn destroyAtlasTextureResources(self: *PreparedResources) void {
        if (self.curve_view != null) {
            vk.vkDestroyImageView(self.ctx.device, self.curve_view, null);
            self.curve_view = null;
        }
        if (self.curve_image != null) {
            vk.vkDestroyImage(self.ctx.device, self.curve_image, null);
            self.curve_image = null;
        }
        if (self.curve_memory != null) {
            vk.vkFreeMemory(self.ctx.device, self.curve_memory, null);
            self.curve_memory = null;
        }
        if (self.band_view != null) {
            vk.vkDestroyImageView(self.ctx.device, self.band_view, null);
            self.band_view = null;
        }
        if (self.band_image != null) {
            vk.vkDestroyImage(self.ctx.device, self.band_image, null);
            self.band_image = null;
        }
        if (self.band_memory != null) {
            vk.vkFreeMemory(self.ctx.device, self.band_memory, null);
            self.band_memory = null;
        }
        if (self.layer_view != null) {
            vk.vkDestroyImageView(self.ctx.device, self.layer_view, null);
            self.layer_view = null;
        }
        if (self.layer_image != null) {
            vk.vkDestroyImage(self.ctx.device, self.layer_image, null);
            self.layer_image = null;
        }
        if (self.layer_memory != null) {
            vk.vkFreeMemory(self.ctx.device, self.layer_memory, null);
            self.layer_memory = null;
        }
    }

    fn destroyImageResources(self: *PreparedResources) void {
        if (self.image_view != null) {
            vk.vkDestroyImageView(self.ctx.device, self.image_view, null);
            self.image_view = null;
        }
        if (self.image_image != null) {
            vk.vkDestroyImage(self.ctx.device, self.image_image, null);
            self.image_image = null;
        }
        if (self.image_memory != null) {
            vk.vkFreeMemory(self.ctx.device, self.image_memory, null);
            self.image_memory = null;
        }
        self.image_slot_count = 0;
        self.allocated_image_width = 0;
        self.allocated_image_height = 0;
        self.allocated_image_count = 0;
        for (&self.image_slots) |*slot| slot.* = .{};
    }
};

pub const VulkanPipeline = struct {
    ctx: VulkanContext = undefined,
    initialized: bool = false,

    pipeline_text: vk.VkPipeline = null,
    pipeline_colr: vk.VkPipeline = null,
    pipeline_path: vk.VkPipeline = null,
    pipeline_text_subpixel_dual: vk.VkPipeline = null,
    pipeline_cache: vk.VkPipelineCache = null,
    pipeline_cache_dirty: bool = false,
    pipeline_layout: vk.VkPipelineLayout = null,
    desc_set_layout: vk.VkDescriptorSetLayout = null,

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
    subpixel_order: SubpixelOrder = .none,
    fill_rule: FillRule = .non_zero,

    // ── Init / Deinit ──

    pub fn init(self: *VulkanPipeline, vk_ctx: VulkanContext) !void {
        self.ctx = vk_ctx;
        self.pipeline_cache_dirty = false;

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

        // Descriptor set layout: curve, band, layer info, image array.
        // Bindings must be constructed programmatically because immutable sampler
        // pointers point into self (runtime address, not comptime).
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
        pl_info.pSetLayouts = @ptrCast(&self.desc_set_layout);
        pl_info.pushConstantRangeCount = 1;
        pl_info.pPushConstantRanges = &push_range;
        try check(vk.vkCreatePipelineLayout(self.ctx.device, &pl_info, null, &self.pipeline_layout));

        try self.createPersistentPipelineCache();

        // Create draw pipelines during renderer init so draw never creates pipelines.
        try self.warmGraphicsPipelines();
        self.writePersistentPipelineCache();

        // Vertex ring buffer (persistent mapped)
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

        // Transfer command pool
        const cp_info = std.mem.zeroInit(vk.VkCommandPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
            .queueFamilyIndex = self.ctx.queue_family_index,
        });
        try check(vk.vkCreateCommandPool(self.ctx.device, &cp_info, null, &self.transfer_cmd_pool));

        // Index buffer: deterministic quad pattern, generated once for max segment capacity
        try self.initIndexBuffer();

        self.initialized = true;
    }

    pub fn deinit(self: *VulkanPipeline) void {
        if (!self.initialized) return;
        // Caller-owned frame synchronization must make renderer teardown safe.
        // Keep deinit free of implicit device-wide waits.
        self.writePersistentPipelineCache();

        if (self.transfer_cmd_pool != null) vk.vkDestroyCommandPool(self.ctx.device, self.transfer_cmd_pool, null);
        if (self.sampler_linear != null) vk.vkDestroySampler(self.ctx.device, self.sampler_linear, null);
        if (self.sampler_nearest != null) vk.vkDestroySampler(self.ctx.device, self.sampler_nearest, null);
        if (self.index_buffer != null) {
            vk.vkDestroyBuffer(self.ctx.device, self.index_buffer, null);
            vk.vkFreeMemory(self.ctx.device, self.index_memory, null);
        }
        if (self.vertex_buffer != null) {
            vk.vkUnmapMemory(self.ctx.device, self.vertex_memory);
            vk.vkDestroyBuffer(self.ctx.device, self.vertex_buffer, null);
            vk.vkFreeMemory(self.ctx.device, self.vertex_memory, null);
        }
        if (self.desc_set_layout != null) vk.vkDestroyDescriptorSetLayout(self.ctx.device, self.desc_set_layout, null);
        if (self.pipeline_text_subpixel_dual != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_text_subpixel_dual, null);
        if (self.pipeline_path != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_path, null);
        if (self.pipeline_colr != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_colr, null);
        if (self.pipeline_text != null) vk.vkDestroyPipeline(self.ctx.device, self.pipeline_text, null);
        if (self.pipeline_cache != null) vk.vkDestroyPipelineCache(self.ctx.device, self.pipeline_cache, null);
        if (self.pipeline_layout != null) vk.vkDestroyPipelineLayout(self.ctx.device, self.pipeline_layout, null);

        self.pipeline_text_subpixel_dual = null;
        self.pipeline_path = null;
        self.pipeline_colr = null;
        self.pipeline_text = null;
        self.pipeline_cache = null;
        self.pipeline_cache_dirty = false;
        self.pipeline_layout = null;
        self.persistent_map = null;
        self.initialized = false;
    }

    pub fn backendName(self: *const VulkanPipeline) []const u8 {
        _ = self;
        return "Vulkan";
    }

    pub fn setSubpixelOrder(self: *VulkanPipeline, order: SubpixelOrder) void {
        self.subpixel_order = order;
    }

    pub fn getSubpixelOrder(self: *const VulkanPipeline) SubpixelOrder {
        return self.subpixel_order;
    }

    pub fn setFillRule(self: *VulkanPipeline, rule: FillRule) void {
        self.fill_rule = rule;
    }

    pub fn getFillRule(self: *const VulkanPipeline) FillRule {
        return self.fill_rule;
    }

    // ── Command buffer (set by caller per-frame) ──

    pub fn setCommandBuffer(self: *VulkanPipeline, cmd: anytype) void {
        self.active_cmd = @ptrCast(cmd);
    }

    pub fn setFrameSlot(self: *VulkanPipeline, slot: u32) void {
        std.debug.assert(slot < UPLOAD_SLOTS);
        self.active_upload_slot = slot;
        self.upload_cursor = 0;
    }

    /// Use a caller-owned, already-recording command buffer for resource
    /// uploads. The caller must submit it; PreparedResources retains staging
    /// buffers until the prepared object is retired.
    pub fn beginResourceUploadRecording(self: *VulkanPipeline, cmd: anytype) void {
        std.debug.assert(self.scheduled_resource_upload_cmd == null);
        self.scheduled_resource_upload_cmd = @ptrCast(cmd);
    }

    pub fn endResourceUploadRecording(self: *VulkanPipeline) void {
        self.scheduled_resource_upload_cmd = null;
    }

    // ── Texture array management ──

    pub fn uploadPreparedAtlases(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, out_views: anytype) void {
        std.debug.assert(atlases.len == out_views.len);

        if (atlases.len == 0) {
            prepared.destroyAtlasTextureResources();
            prepared.resetAtlasUploadState();
            return;
        }

        const can_incremental = prepared.texturesReady() and prepared.atlasSlotsCompatible(atlases);
        if (!can_incremental) {
            self.rebuildTextureArrays(prepared, atlases, out_views);
        } else if (!self.appendTexturePages(prepared, atlases)) {
            self.rebuildTextureArrays(prepared, atlases, out_views);
        } else {
            prepared.fillAtlasViews(atlases, out_views);
            self.ensureAtlasImagesRegistered(prepared, atlases);
            self.rebuildLayerInfoTexture(prepared, atlases);
            prepared.atlas_has_special_text_runs = subpixel_policy.atlasesHaveSpecialTextRuns(atlases);
            self.updateDescriptorSet(prepared);
        }
    }

    pub fn uploadPreparedImages(self: *VulkanPipeline, prepared: *PreparedResources, images: []const *const snail_mod.Image, out_views: anytype) void {
        std.debug.assert(images.len == out_views.len);
        self.ensureImagesRegistered(prepared, images);
        const ImageView = upload_common.BufferElement(@TypeOf(out_views));
        for (images, 0..) |image, i| {
            out_views[i] = prepared.currentImageView(ImageView, image);
        }
        self.updateDescriptorSet(prepared);
    }

    fn rebuildTextureArrays(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas, out_views: anytype) void {
        prepared.destroyAtlasTextureResources();
        prepared.resetAtlasUploadState();

        const slot_info = upload_common.rebuildAtlasSlots(prepared.atlas_slots[0..], atlases);
        prepared.atlas_slot_count = slot_info.atlas_slot_count;
        prepared.allocated_curve_height = slot_info.allocated_curve_height;
        prepared.allocated_band_height = slot_info.allocated_band_height;
        prepared.allocated_layer_count = slot_info.allocated_layer_count;

        const first_page = atlases[0].page(0);
        const curve_w = first_page.curve_width;
        const band_w = first_page.band_width;

        // Create images
        prepared.curve_image = self.createImage2DArray(curve_w, prepared.allocated_curve_height, prepared.allocated_layer_count, vk.VK_FORMAT_R16G16B16A16_SFLOAT) catch return;
        prepared.curve_memory = self.allocateImageMemory(prepared.curve_image) catch return;
        _ = vk.vkBindImageMemory(self.ctx.device, prepared.curve_image, prepared.curve_memory, 0);

        prepared.band_image = self.createImage2DArray(band_w, prepared.allocated_band_height, prepared.allocated_layer_count, vk.VK_FORMAT_R16G16_UINT) catch return;
        prepared.band_memory = self.allocateImageMemory(prepared.band_image) catch return;
        _ = vk.vkBindImageMemory(self.ctx.device, prepared.band_image, prepared.band_memory, 0);

        // Upload via staging buffer
        self.uploadTextureData(prepared, atlases, null, prepared.allocated_layer_count, vk.VK_IMAGE_LAYOUT_UNDEFINED) catch return;

        // Create image views
        prepared.curve_view = self.createImageView(prepared.curve_image, vk.VK_FORMAT_R16G16B16A16_SFLOAT, prepared.allocated_layer_count) catch return;
        prepared.band_view = self.createImageView(prepared.band_image, vk.VK_FORMAT_R16G16_UINT, prepared.allocated_layer_count) catch return;

        self.ensureAtlasImagesRegistered(prepared, atlases);
        self.rebuildLayerInfoTexture(prepared, atlases);
        prepared.atlas_has_special_text_runs = subpixel_policy.atlasesHaveSpecialTextRuns(atlases);
        prepared.fillAtlasViews(atlases, out_views);
        self.updateDescriptorSet(prepared);
    }

    fn appendTexturePages(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) bool {
        var max_curve_h: u32 = prepared.allocated_curve_height;
        var max_band_h: u32 = prepared.allocated_band_height;
        var start_pages: [MAX_ATLASES]u32 = undefined;

        for (atlases, 0..) |atlas, i| {
            if (i >= prepared.atlas_slot_count) return false;
            const slot = &prepared.atlas_slots[i];
            const page_count: u32 = @intCast(atlas.pageCount());
            if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
            start_pages[i] = slot.uploaded_pages;
            if (slot.uploaded_pages > slot.page_ptrs.len) return false;
            for (0..slot.uploaded_pages) |page_index| {
                if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
            }
            for (0..page_count) |page_index| {
                const page = atlas.page(@intCast(page_index));
                if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
                if (page.band_height > max_band_h) max_band_h = page.band_height;
            }
        }

        if (atlases.len != prepared.atlas_slot_count) return false;
        if (max_curve_h > prepared.allocated_curve_height or max_band_h > prepared.allocated_band_height) return false;
        self.uploadTextureData(prepared, atlases, start_pages[0..atlases.len], prepared.allocated_layer_count, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) catch return false;

        upload_common.refreshAtlasSlots(prepared.atlas_slots[0..], atlases);
        return true;
    }

    fn ensureAtlasImagesRegistered(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) void {
        var scratch: [MAX_IMAGES]*const snail_mod.Image = undefined;
        const count = upload_common.collectAtlasImages(prepared.image_slots[0..], prepared.image_slot_count, atlases, scratch[0..]);
        self.ensureImagesRegistered(prepared, scratch[0..count]);
    }

    fn ensureImagesRegistered(self: *VulkanPipeline, prepared: *PreparedResources, images: []const *const snail_mod.Image) void {
        if (images.len == 0) return;

        var new_images: [MAX_IMAGES]*const snail_mod.Image = undefined;
        var new_count: usize = 0;
        var required_width = prepared.allocated_image_width;
        var required_height = prepared.allocated_image_height;
        for (images) |image| {
            required_width = @max(required_width, image.width);
            required_height = @max(required_height, image.height);
            if (prepared.findImageSlot(image) != null) continue;
            if (prepared.image_slot_count + new_count >= MAX_IMAGES) break;
            new_images[new_count] = image;
            new_count += 1;
        }

        if (new_count == 0 and prepared.image_image != null) return;

        const required_count: u32 = @intCast(prepared.image_slot_count + new_count);
        const new_width = upload_common.heightCapacity(@max(required_width, 1));
        const new_height = upload_common.heightCapacity(@max(required_height, 1));
        const needs_rebuild = prepared.image_image == null or
            required_count > prepared.allocated_image_count or
            new_width > prepared.allocated_image_width or
            new_height > prepared.allocated_image_height;

        if (needs_rebuild) {
            for (new_images[0..new_count], 0..) |image, i| {
                prepared.image_slots[prepared.image_slot_count + i] = .{ .image = image };
            }
            prepared.image_slot_count += new_count;
            self.rebuildImageArray(prepared);
            return;
        }

        for (new_images[0..new_count], 0..) |image, i| {
            prepared.image_slots[prepared.image_slot_count + i] = .{ .image = image };
        }
        self.uploadImagesToArray(prepared, new_images[0..new_count], @intCast(prepared.image_slot_count), vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) catch return;
        prepared.image_slot_count += new_count;
    }

    fn rebuildLayerInfoTexture(self: *VulkanPipeline, prepared: *PreparedResources, atlases: []const *const snail_mod.lowlevel.CurveAtlas) void {
        if (prepared.layer_view != null) {
            vk.vkDestroyImageView(self.ctx.device, prepared.layer_view, null);
            prepared.layer_view = null;
        }
        if (prepared.layer_image != null) {
            vk.vkDestroyImage(self.ctx.device, prepared.layer_image, null);
            prepared.layer_image = null;
        }
        if (prepared.layer_memory != null) {
            vk.vkFreeMemory(self.ctx.device, prepared.layer_memory, null);
            prepared.layer_memory = null;
        }

        var total_rows: u32 = 0;
        for (atlases) |atlas| total_rows += atlas.layer_info_height;
        if (total_rows == 0) return;

        const width = snail_mod.lowlevel.PATH_PAINT_INFO_WIDTH;
        const total_texels = @as(usize, width) * @as(usize, total_rows) * 4;
        var data = std.heap.page_allocator.alloc(f32, total_texels) catch return;
        defer std.heap.page_allocator.free(data);
        @memset(data, 0);

        const ImagePatchView = struct {
            image: *const snail_mod.Image,
            layer: u16 = 0,
            uv_scale: snail_mod.Vec2 = .{ .x = 1.0, .y = 1.0 },
        };
        for (atlases, 0..) |atlas, i| {
            const lid = atlas.layer_info_data orelse continue;
            const row_base = prepared.atlas_slots[i].info_row_base;
            const row_count = atlas.layer_info_height;
            const copy_len = @as(usize, atlas.layer_info_width) * @as(usize, row_count) * 4;
            const dst_base = @as(usize, row_base) * @as(usize, width) * 4;
            @memcpy(data[dst_base .. dst_base + copy_len], lid[0..copy_len]);

            const records = atlas.paint_image_records orelse continue;
            for (records) |record| {
                const paint = record orelse continue;
                upload_common.patchImagePaintRecord(data, width, row_base, paint.texel_offset, prepared.currentImageView(ImagePatchView, paint.image));
            }
        }

        prepared.layer_image = self.createImage2D(width, total_rows, vk.VK_FORMAT_R32G32B32A32_SFLOAT) catch return;
        prepared.layer_memory = self.allocateImageMemory(prepared.layer_image) catch return;
        _ = vk.vkBindImageMemory(self.ctx.device, prepared.layer_image, prepared.layer_memory, 0);
        self.uploadLayerInfoData(prepared, data, width, total_rows) catch return;
        prepared.layer_view = self.createImageView2D(prepared.layer_image, vk.VK_FORMAT_R32G32B32A32_SFLOAT) catch return;
    }

    fn updateDescriptorSet(self: *VulkanPipeline, prepared: *PreparedResources) void {
        const effective_layer_view = if (prepared.layer_view != null) prepared.layer_view else prepared.curve_view;
        const effective_image_view = if (prepared.image_view != null) prepared.image_view else prepared.curve_view;
        const image_infos = [4]vk.VkDescriptorImageInfo{
            .{
                .sampler = self.sampler_nearest,
                .imageView = prepared.curve_view,
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            },
            .{
                .sampler = self.sampler_nearest,
                .imageView = prepared.band_view,
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            },
            .{
                .sampler = self.sampler_nearest,
                .imageView = effective_layer_view,
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            },
            .{
                .sampler = self.sampler_linear,
                .imageView = effective_image_view,
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            },
        };
        const writes = [4]vk.VkWriteDescriptorSet{
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = prepared.desc_set,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[0],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = prepared.desc_set,
                .dstBinding = 1,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[1],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = prepared.desc_set,
                .dstBinding = 2,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[2],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = prepared.desc_set,
                .dstBinding = 3,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[3],
            }),
        };
        vk.vkUpdateDescriptorSets(self.ctx.device, 4, &writes, 0, null);
    }

    // ── Draw ──

    fn drawTextInternal(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32, allow_subpixel: bool) void {
        const cmd = self.active_cmd orelse return;
        if (vertices.len == 0) return;

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;

        vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&prepared.desc_set), 0, null);
        setViewportAndScissor(cmd, viewport_w, viewport_h);

        const render_mode = subpixel_policy.chooseTextRenderMode(
            vertices,
            mvp,
            allow_subpixel,
            self.subpixel_order,
            self.ctx.supports_dual_source_blend,
        );

        if (!prepared.atlas_has_special_text_runs) {
            const pip = switch (render_mode) {
                .grayscale => self.ensureTextPipeline() catch {
                    std.debug.print("Vulkan: failed to create text pipeline\n", .{});
                    return;
                },
                .subpixel_dual_source => self.ensureTextSubpixelDualPipeline() catch {
                    std.debug.print("Vulkan: failed to create dual-source subpixel pipeline\n", .{});
                    return;
                },
            };
            vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);

            const pc = PushConstants{
                .mvp = mvp.data,
                .viewport = .{ viewport_w, viewport_h },
                .fill_rule = @intFromEnum(self.fill_rule),
                .subpixel_order = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else self.subpixel_order),
                .layer_base = @intCast(texture_layer_base),
            };
            vk.vkCmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);
            self.drawGlyphRange(vertices, 0, total_glyphs);
            return;
        }

        var run_start: usize = 0;
        while (run_start < total_glyphs) {
            const special = subpixel_policy.glyphRunIsSpecial(vertices, run_start);
            const run_end = subpixel_policy.specialRunEnd(vertices, run_start, special);

            const run_mode: subpixel_policy.TextRenderMode = if (special)
                .grayscale
            else
                subpixel_policy.chooseTextRenderModeRange(
                    vertices,
                    run_start,
                    run_end - run_start,
                    mvp,
                    allow_subpixel,
                    self.subpixel_order,
                    self.ctx.supports_dual_source_blend,
                );
            const pip = if (special)
                self.ensureColrPipeline() catch {
                    std.debug.print("Vulkan: failed to create COLR pipeline\n", .{});
                    return;
                }
            else switch (run_mode) {
                .grayscale => self.ensureTextPipeline() catch {
                    std.debug.print("Vulkan: failed to create text pipeline\n", .{});
                    return;
                },
                .subpixel_dual_source => self.ensureTextSubpixelDualPipeline() catch {
                    std.debug.print("Vulkan: failed to create dual-source subpixel pipeline\n", .{});
                    return;
                },
            };
            vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);

            const pc = PushConstants{
                .mvp = mvp.data,
                .viewport = .{ viewport_w, viewport_h },
                .fill_rule = @intFromEnum(self.fill_rule),
                .subpixel_order = @intFromEnum(if (run_mode == .grayscale) SubpixelOrder.none else self.subpixel_order),
                .layer_base = @intCast(texture_layer_base),
            };
            vk.vkCmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    pub fn drawTextPrepared(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.drawTextInternal(prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base, true);
    }

    pub fn drawPathsPrepared(self: *VulkanPipeline, prepared: *const PreparedResources, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        const cmd = self.active_cmd orelse return;
        if (vertices.len == 0) return;

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;

        vk.vkCmdBindIndexBuffer(cmd, self.index_buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        vk.vkCmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, @ptrCast(&prepared.desc_set), 0, null);
        setViewportAndScissor(cmd, viewport_w, viewport_h);

        const render_mode: subpixel_policy.TextRenderMode = .grayscale;
        const pip = self.ensurePathPipeline() catch {
            std.debug.print("Vulkan: missing path pipeline\n", .{});
            return;
        };
        vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pip);

        const pc = PushConstants{
            .mvp = mvp.data,
            .viewport = .{ viewport_w, viewport_h },
            .fill_rule = @intFromEnum(self.fill_rule),
            .subpixel_order = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else self.subpixel_order),
            .layer_base = @intCast(texture_layer_base),
        };
        vk.vkCmdPushConstants(cmd, self.pipeline_layout, vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &pc);
        self.drawGlyphRange(vertices, 0, total_glyphs);
    }

    pub fn beginFrame(self: *VulkanPipeline) void {
        // No-op for Vulkan (ring buffer handles frame separation)
        _ = self;
    }

    // ── Internal helpers ──

    fn createGraphicsPipeline(self: *VulkanPipeline, frag_code: []const u8, blend_mode: BlendMode) !vk.VkPipeline {
        const vert_module = try self.createShaderModule(vert_spv);
        defer vk.vkDestroyShaderModule(self.ctx.device, vert_module, null);
        const frag_module = try self.createShaderModule(frag_code);
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

        const attrs = [6]vk.VkVertexInputAttributeDescription{
            .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R16G16B16A16_SFLOAT, .offset = @offsetOf(vertex.Instance, "rect") },
            .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "xform") },
            .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(vertex.Instance, "origin") },
            .{ .location = 3, .binding = 0, .format = vk.VK_FORMAT_R32G32_UINT, .offset = @offsetOf(vertex.Instance, "glyph") },
            .{ .location = 4, .binding = 0, .format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(vertex.Instance, "band") },
            .{ .location = 5, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(vertex.Instance, "color") },
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
        try check(vk.vkCreateGraphicsPipelines(self.ctx.device, self.pipeline_cache, 1, &ci, null, &pip));
        self.pipeline_cache_dirty = true;
        return pip;
    }

    fn warmGraphicsPipelines(self: *VulkanPipeline) !void {
        self.pipeline_text = try self.createGraphicsPipeline(frag_text_spv, .premultiplied);
        self.pipeline_colr = try self.createGraphicsPipeline(frag_colr_spv, .premultiplied);
        self.pipeline_path = try self.createGraphicsPipeline(frag_path_spv, .premultiplied);
        if (self.ctx.supports_dual_source_blend) {
            self.pipeline_text_subpixel_dual = try self.createGraphicsPipeline(frag_text_subpixel_dual_spv, .dual_source);
        }
    }

    fn ensureTextPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return self.pipeline_text orelse error.PipelineUnavailable;
    }

    fn ensureColrPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return self.pipeline_colr orelse error.PipelineUnavailable;
    }

    fn ensurePathPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return self.pipeline_path orelse error.PipelineUnavailable;
    }

    fn ensureTextSubpixelDualPipeline(self: *VulkanPipeline) !vk.VkPipeline {
        return self.pipeline_text_subpixel_dual orelse error.PipelineUnavailable;
    }

    fn drawGlyphRange(self: *VulkanPipeline, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
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

    fn createPersistentPipelineCache(self: *VulkanPipeline) !void {
        const initial_data = self.loadPersistentPipelineCacheData();
        defer if (initial_data) |data| std.heap.c_allocator.free(data);

        var ci = std.mem.zeroInit(vk.VkPipelineCacheCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
            .initialDataSize = if (initial_data) |data| data.len else 0,
            .pInitialData = if (initial_data) |data| data.ptr else null,
        });

        var cache: vk.VkPipelineCache = null;
        const result = vk.vkCreatePipelineCache(self.ctx.device, &ci, null, &cache);
        if (result == vk.VK_SUCCESS) {
            self.pipeline_cache = cache;
            return;
        }

        if (initial_data != null and result == vk.VK_ERROR_INITIALIZATION_FAILED) {
            std.debug.print("Vulkan: ignoring stale pipeline cache ({})\n", .{result});
            ci.initialDataSize = 0;
            ci.pInitialData = null;
            try check(vk.vkCreatePipelineCache(self.ctx.device, &ci, null, &cache));
            self.pipeline_cache = cache;
            return;
        }

        try check(result);
    }

    fn writePersistentPipelineCache(self: *VulkanPipeline) void {
        if (self.pipeline_cache == null or !self.pipeline_cache_dirty) return;

        var size: usize = 0;
        if (vk.vkGetPipelineCacheData(self.ctx.device, self.pipeline_cache, &size, null) != vk.VK_SUCCESS) return;
        if (size == 0 or size > 64 * 1024 * 1024) return;

        const data = std.heap.c_allocator.alloc(u8, size) catch return;
        defer std.heap.c_allocator.free(data);
        if (vk.vkGetPipelineCacheData(self.ctx.device, self.pipeline_cache, &size, data.ptr) != vk.VK_SUCCESS) return;
        if (size == 0) return;

        var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const dir_path = pipelineCacheDirPath(&dir_buf) orelse return;
        _ = std.c.mkdir(dir_path.ptr, 0o755);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.pipelineCacheFilePath(&path_buf) orelse return;
        const file = std.c.fopen(path.ptr, "wb") orelse return;
        defer _ = std.c.fclose(file);
        if (std.c.fwrite(data.ptr, 1, size, file) != size) {
            std.debug.print("Vulkan: failed to write pipeline cache\n", .{});
            return;
        }
        self.pipeline_cache_dirty = false;
    }

    fn loadPersistentPipelineCacheData(self: *const VulkanPipeline) ?[]u8 {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = self.pipelineCacheFilePath(&path_buf) orelse return null;
        const file = std.c.fopen(path.ptr, "rb") orelse return null;
        defer _ = std.c.fclose(file);

        if (fseek(file, 0, 2) != 0) return null;
        const size_long = ftell(file);
        if (size_long <= 0 or size_long > 64 * 1024 * 1024) return null;
        rewind(file);

        const size: usize = @intCast(size_long);
        const data = std.heap.c_allocator.alloc(u8, size) catch return null;
        if (std.c.fread(data.ptr, 1, size, file) != size) {
            std.heap.c_allocator.free(data);
            return null;
        }
        return data;
    }

    fn pipelineCacheFilePath(self: *const VulkanPipeline, buf: []u8) ?[:0]const u8 {
        var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const dir_path = pipelineCacheDirPath(&dir_buf) orelse return null;

        var props: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(self.ctx.physical_device, &props);

        return std.fmt.bufPrintZ(
            buf,
            "{s}/vk-pipeline-cache-{d}-{d}-{d}.bin",
            .{ dir_path, props.vendorID, props.deviceID, props.driverVersion },
        ) catch null;
    }

    fn createShaderModule(self: *const VulkanPipeline, code: []const u8) !vk.VkShaderModule {
        var ci: vk.VkShaderModuleCreateInfo = std.mem.zeroes(vk.VkShaderModuleCreateInfo);
        ci.sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        ci.codeSize = code.len;
        ci.pCode = @ptrCast(@alignCast(code.ptr));
        var module: vk.VkShaderModule = null;
        try check(vk.vkCreateShaderModule(self.ctx.device, &ci, null, &module));
        return module;
    }

    fn createBuffer(self: *const VulkanPipeline, size: vk.VkDeviceSize, usage: vk.VkBufferUsageFlags, properties: vk.VkMemoryPropertyFlags, buffer: *vk.VkBuffer, memory: *vk.VkDeviceMemory) !void {
        const ci = std.mem.zeroInit(vk.VkBufferCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        });
        try check(vk.vkCreateBuffer(self.ctx.device, &ci, null, buffer));

        var req: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.ctx.device, buffer.*, &req);

        const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = req.size,
            .memoryTypeIndex = self.findMemoryType(req.memoryTypeBits, properties) orelse return error.NoSuitableMemory,
        });
        try check(vk.vkAllocateMemory(self.ctx.device, &ai, null, memory));
        try check(vk.vkBindBufferMemory(self.ctx.device, buffer.*, memory.*, 0));
    }

    fn findMemoryType(self: *const VulkanPipeline, type_filter: u32, properties: vk.VkMemoryPropertyFlags) ?u32 {
        var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(self.ctx.physical_device, &mem_props);

        for (0..mem_props.memoryTypeCount) |i| {
            if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
                (mem_props.memoryTypes[i].propertyFlags & properties) == properties)
            {
                return @intCast(i);
            }
        }
        return null;
    }

    fn createImage2DArray(self: *const VulkanPipeline, width: u32, height: u32, layers: u32, format: vk.VkFormat) !vk.VkImage {
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
        try check(vk.vkCreateImage(self.ctx.device, &ci, null, &image));
        return image;
    }

    fn allocateImageMemory(self: *const VulkanPipeline, image: vk.VkImage) !vk.VkDeviceMemory {
        var req: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(self.ctx.device, image, &req);

        const ai = std.mem.zeroInit(vk.VkMemoryAllocateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = req.size,
            .memoryTypeIndex = self.findMemoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.NoSuitableMemory,
        });
        var memory: vk.VkDeviceMemory = null;
        try check(vk.vkAllocateMemory(self.ctx.device, &ai, null, &memory));
        return memory;
    }

    fn createImageView(self: *const VulkanPipeline, image: vk.VkImage, format: vk.VkFormat, layer_count: u32) !vk.VkImageView {
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
        try check(vk.vkCreateImageView(self.ctx.device, &ci, null, &view));
        return view;
    }

    fn beginTransferCommand(self: *VulkanPipeline) !TransferCommand {
        if (self.scheduled_resource_upload_cmd != null) {
            return .{ .cmd = self.scheduled_resource_upload_cmd, .owned = false };
        }

        var cmd: vk.VkCommandBuffer = null;
        const alloc_info = std.mem.zeroInit(vk.VkCommandBufferAllocateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.transfer_cmd_pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        });
        try check(vk.vkAllocateCommandBuffers(self.ctx.device, &alloc_info, &cmd));

        const begin_info = std.mem.zeroInit(vk.VkCommandBufferBeginInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        });
        try check(vk.vkBeginCommandBuffer(cmd, &begin_info));
        return .{ .cmd = cmd, .owned = true };
    }

    fn discardTransferCommand(self: *VulkanPipeline, transfer: TransferCommand) void {
        if (transfer.owned and transfer.cmd != null) {
            var cmd = transfer.cmd;
            vk.vkFreeCommandBuffers(self.ctx.device, self.transfer_cmd_pool, 1, &cmd);
        }
    }

    fn finishTransferCommand(self: *VulkanPipeline, transfer: TransferCommand) !void {
        if (!transfer.owned) return;
        try check(vk.vkEndCommandBuffer(transfer.cmd));
        try self.submitTransferAndWait(transfer.cmd);
        var cmd = transfer.cmd;
        vk.vkFreeCommandBuffers(self.ctx.device, self.transfer_cmd_pool, 1, &cmd);
    }

    fn destroyStagingBuffer(self: *VulkanPipeline, buffer: vk.VkBuffer, memory: vk.VkDeviceMemory) void {
        vk.vkDestroyBuffer(self.ctx.device, buffer, null);
        vk.vkFreeMemory(self.ctx.device, memory, null);
    }

    fn finishUploadStaging(self: *VulkanPipeline, prepared: *PreparedResources, buffer: vk.VkBuffer, memory: vk.VkDeviceMemory) !void {
        if (self.scheduled_resource_upload_cmd != null) {
            try prepared.retainUploadStaging(buffer, memory);
        } else {
            self.destroyStagingBuffer(buffer, memory);
        }
    }

    fn uploadTextureData(
        self: *VulkanPipeline,
        prepared: *PreparedResources,
        atlases: []const *const snail_mod.lowlevel.CurveAtlas,
        start_pages: ?[]const u32,
        layer_count: u32,
        old_layout: vk.VkImageLayout,
    ) !void {
        // Calculate staging buffer sizes
        const curve_px_bytes: usize = 4 * 2; // RGBA16F = 4 channels * 2 bytes
        const band_px_bytes: usize = 2 * 2; // RG16UI = 2 channels * 2 bytes

        var total_staging: usize = 0;
        var region_count: u32 = 0;
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            for (start_page..atlas.pageCount()) |page_index| {
                region_count += 1;
                const a = atlas;
                const page = a.page(@intCast(page_index));
                total_staging += @as(usize, page.curve_width) * @as(usize, page.curve_height) * curve_px_bytes;
                total_staging += @as(usize, page.band_width) * @as(usize, page.band_height) * band_px_bytes;
            }
        }
        if (region_count == 0) return;

        // Create staging buffer
        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try self.createBuffer(
            @intCast(total_staging),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        errdefer self.destroyStagingBuffer(staging_buf, staging_mem);

        // Map and copy data
        var map_ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, @intCast(total_staging), 0, &map_ptr));
        const staging_data: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);

        // Record one VkBufferImageCopy per (atlas page, image), sized to the
        // total page count discovered above. Static arrays would silently
        // overflow when many fonts/atlases are uploaded together.
        const curve_regions = try std.heap.c_allocator.alloc(vk.VkBufferImageCopy, region_count);
        defer std.heap.c_allocator.free(curve_regions);
        const band_regions = try std.heap.c_allocator.alloc(vk.VkBufferImageCopy, region_count);
        defer std.heap.c_allocator.free(band_regions);
        var staging_offset: usize = 0;

        var region_index: usize = 0;
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = prepared.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));

                const curve_size = @as(usize, page.curve_width) * @as(usize, page.curve_height) * curve_px_bytes;
                const curve_bytes: [*]const u8 = @ptrCast(page.curve_data.ptr);
                @memcpy(staging_data[staging_offset..][0..curve_size], curve_bytes[0..curve_size]);
                var cr: vk.VkBufferImageCopy = std.mem.zeroes(vk.VkBufferImageCopy);
                cr.bufferOffset = @intCast(staging_offset);
                cr.imageSubresource.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT;
                cr.imageSubresource.baseArrayLayer = layer;
                cr.imageSubresource.layerCount = 1;
                cr.imageExtent = .{ .width = page.curve_width, .height = page.curve_height, .depth = 1 };
                curve_regions[region_index] = cr;
                staging_offset += curve_size;

                const band_size = @as(usize, page.band_width) * @as(usize, page.band_height) * band_px_bytes;
                const band_bytes: [*]const u8 = @ptrCast(page.band_data.ptr);
                @memcpy(staging_data[staging_offset..][0..band_size], band_bytes[0..band_size]);
                var br: vk.VkBufferImageCopy = std.mem.zeroes(vk.VkBufferImageCopy);
                br.bufferOffset = @intCast(staging_offset);
                br.imageSubresource.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT;
                br.imageSubresource.baseArrayLayer = layer;
                br.imageSubresource.layerCount = 1;
                br.imageExtent = .{ .width = page.band_width, .height = page.band_height, .depth = 1 };
                band_regions[region_index] = br;
                staging_offset += band_size;
                region_index += 1;
            }
        }

        vk.vkUnmapMemory(self.ctx.device, staging_mem);

        const transfer = try self.beginTransferCommand();
        var transfer_finished = false;
        errdefer if (!transfer_finished) self.discardTransferCommand(transfer);
        const cmd = transfer.cmd;

        // Transition images into transfer dst for the upload.
        transitionImageLayout(cmd, prepared.curve_image, layer_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        transitionImageLayout(cmd, prepared.band_image, layer_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

        // Copy buffer to images
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, prepared.curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, region_count, curve_regions.ptr);
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, prepared.band_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, region_count, band_regions.ptr);

        // Transition TRANSFER_DST -> SHADER_READ_ONLY
        transitionImageLayout(cmd, prepared.curve_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        transitionImageLayout(cmd, prepared.band_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        try self.finishTransferCommand(transfer);
        transfer_finished = true;
        try self.finishUploadStaging(prepared, staging_buf, staging_mem);
    }

    fn submitTransferAndWait(self: *VulkanPipeline, cmd: vk.VkCommandBuffer) !void {
        var fence: vk.VkFence = null;
        const fence_info = std.mem.zeroInit(vk.VkFenceCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        });
        try check(vk.vkCreateFence(self.ctx.device, &fence_info, null, &fence));
        defer vk.vkDestroyFence(self.ctx.device, fence, null);

        const submit_info = std.mem.zeroInit(vk.VkSubmitInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &cmd,
        });
        try check(vk.vkQueueSubmit(self.ctx.graphics_queue, 1, &submit_info, fence));
        try check(vk.vkWaitForFences(self.ctx.device, 1, &fence, vk.VK_TRUE, std.math.maxInt(u64)));
    }

    fn initIndexBuffer(self: *VulkanPipeline) !void {
        // Single quad index pattern — instancing repeats it per glyph.
        const buf_size: vk.VkDeviceSize = 6 * @sizeOf(u32);

        try self.createBuffer(
            buf_size,
            vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.index_buffer,
            &self.index_memory,
        );

        var map_ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.ctx.device, self.index_memory, 0, buf_size, 0, &map_ptr));
        const indices: [*]u32 = @ptrCast(@alignCast(map_ptr));
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 0;
        indices[4] = 2;
        indices[5] = 3;
        vk.vkUnmapMemory(self.ctx.device, self.index_memory);
    }

    fn createImage2D(self: *const VulkanPipeline, width: u32, height: u32, format: vk.VkFormat) !vk.VkImage {
        const ci = std.mem.zeroInit(vk.VkImageCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .format = format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .usage = vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
        });
        var image: vk.VkImage = null;
        try check(vk.vkCreateImage(self.ctx.device, &ci, null, &image));
        return image;
    }

    fn createImageView2D(self: *const VulkanPipeline, image: vk.VkImage, format: vk.VkFormat) !vk.VkImageView {
        const ci = std.mem.zeroInit(vk.VkImageViewCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });
        var view: vk.VkImageView = null;
        try check(vk.vkCreateImageView(self.ctx.device, &ci, null, &view));
        return view;
    }

    fn uploadLayerInfoData(self: *VulkanPipeline, prepared: *PreparedResources, data: []f32, width: u32, height: u32) !void {
        const px_bytes: usize = 4 * 4; // RGBA32F = 4 channels * 4 bytes
        const total_bytes: vk.VkDeviceSize = @intCast(@as(usize, width) * @as(usize, height) * px_bytes);

        // Create staging buffer
        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try self.createBuffer(total_bytes, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &staging_buf, &staging_mem);
        errdefer self.destroyStagingBuffer(staging_buf, staging_mem);

        // Map and copy
        var map_ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, total_bytes, 0, &map_ptr));
        const dst: [*]u8 = @ptrCast(map_ptr);
        const src: [*]const u8 = @ptrCast(data.ptr);
        @memcpy(dst[0..@intCast(total_bytes)], src[0..@intCast(total_bytes)]);
        vk.vkUnmapMemory(self.ctx.device, staging_mem);

        const transfer = try self.beginTransferCommand();
        var transfer_finished = false;
        errdefer if (!transfer_finished) self.discardTransferCommand(transfer);
        const cmd = transfer.cmd;

        transitionImageLayout(cmd, prepared.layer_image, 1, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

        const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
            .bufferOffset = 0,
            .imageSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageExtent = .{ .width = width, .height = height, .depth = 1 },
        });
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, prepared.layer_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        transitionImageLayout(cmd, prepared.layer_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        try self.finishTransferCommand(transfer);
        transfer_finished = true;
        try self.finishUploadStaging(prepared, staging_buf, staging_mem);
    }

    fn rebuildImageArray(self: *VulkanPipeline, prepared: *PreparedResources) void {
        if (prepared.image_view != null) {
            vk.vkDestroyImageView(self.ctx.device, prepared.image_view, null);
            prepared.image_view = null;
        }
        if (prepared.image_image != null) {
            vk.vkDestroyImage(self.ctx.device, prepared.image_image, null);
            prepared.image_image = null;
        }
        if (prepared.image_memory != null) {
            vk.vkFreeMemory(self.ctx.device, prepared.image_memory, null);
            prepared.image_memory = null;
        }

        if (prepared.image_slot_count == 0) {
            prepared.allocated_image_width = 0;
            prepared.allocated_image_height = 0;
            prepared.allocated_image_count = 0;
            return;
        }

        var max_width: u32 = 1;
        var max_height: u32 = 1;
        var all_images: [MAX_IMAGES]*const snail_mod.Image = undefined;
        var image_count: usize = 0;
        for (prepared.image_slots[0..prepared.image_slot_count]) |slot| {
            const image = slot.image orelse continue;
            all_images[image_count] = image;
            image_count += 1;
            max_width = @max(max_width, image.width);
            max_height = @max(max_height, image.height);
        }

        prepared.allocated_image_width = upload_common.heightCapacity(max_width);
        prepared.allocated_image_height = upload_common.heightCapacity(max_height);
        prepared.allocated_image_count = upload_common.atlasCapacity(@intCast(prepared.image_slot_count));

        prepared.image_image = self.createImage2DArray(prepared.allocated_image_width, prepared.allocated_image_height, prepared.allocated_image_count, vk.VK_FORMAT_R8G8B8A8_SRGB) catch return;
        prepared.image_memory = self.allocateImageMemory(prepared.image_image) catch return;
        _ = vk.vkBindImageMemory(self.ctx.device, prepared.image_image, prepared.image_memory, 0);
        self.uploadImagesToArray(prepared, all_images[0..image_count], 0, vk.VK_IMAGE_LAYOUT_UNDEFINED) catch return;
        prepared.image_view = self.createImageView(prepared.image_image, vk.VK_FORMAT_R8G8B8A8_SRGB, prepared.allocated_image_count) catch return;
    }

    fn uploadImagesToArray(self: *VulkanPipeline, prepared: *PreparedResources, images: []const *const snail_mod.Image, start_layer: u32, old_layout: vk.VkImageLayout) !void {
        if (images.len == 0 or prepared.image_image == null) return;

        var total_staging: usize = 0;
        for (images) |image| total_staging += @as(usize, image.width) * @as(usize, image.height) * 4;

        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try self.createBuffer(
            @intCast(total_staging),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        errdefer self.destroyStagingBuffer(staging_buf, staging_mem);

        var map_ptr: ?*anyopaque = null;
        try check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, @intCast(total_staging), 0, &map_ptr));
        const staging_data: [*]u8 = @ptrCast(map_ptr);

        var regions: [MAX_IMAGES]vk.VkBufferImageCopy = undefined;
        var staging_offset: usize = 0;
        for (images, 0..) |image, i| {
            const size = @as(usize, image.width) * @as(usize, image.height) * 4;
            @memcpy(staging_data[staging_offset..][0..size], image.pixels[0..size]);
            regions[i] = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(staging_offset)),
                .imageSubresource = .{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = start_layer + @as(u32, @intCast(i)),
                    .layerCount = 1,
                },
                .imageExtent = .{ .width = image.width, .height = image.height, .depth = 1 },
            });
            staging_offset += size;
        }
        vk.vkUnmapMemory(self.ctx.device, staging_mem);

        const transfer = try self.beginTransferCommand();
        var transfer_finished = false;
        errdefer if (!transfer_finished) self.discardTransferCommand(transfer);
        const cmd = transfer.cmd;

        transitionImageLayout(cmd, prepared.image_image, prepared.allocated_image_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, prepared.image_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, @intCast(images.len), &regions);
        transitionImageLayout(cmd, prepared.image_image, prepared.allocated_image_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        try self.finishTransferCommand(transfer);
        transfer_finished = true;
        try self.finishUploadStaging(prepared, staging_buf, staging_mem);
    }
};

// ── Module-level helpers that don't access instance state ──

fn pipelineCacheDirPath(buf: []u8) ?[:0]const u8 {
    if (std.c.getenv("XDG_CACHE_HOME")) |root| {
        return std.fmt.bufPrintZ(buf, "{s}/snail", .{std.mem.span(root)}) catch null;
    }
    if (std.c.getenv("HOME")) |home| {
        return std.fmt.bufPrintZ(buf, "{s}/.cache/snail", .{std.mem.span(home)}) catch null;
    }
    return null;
}

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
    } else if (old_layout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL and new_layout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        src_access = vk.VK_ACCESS_SHADER_READ_BIT;
        dst_access = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
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

fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
