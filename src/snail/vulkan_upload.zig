//! Phase 5c: new-API Vulkan prepared-pages cache.
//!
//! Mirrors `Gl33PreparedPages` and `Gles30PreparedPages` for Vulkan.
//! Per-`PagePool` resident `VkImage`s for curve + band textures
//! (`VK_FORMAT_R16G16B16A16_SFLOAT` / `R16G16_UINT`, both
//! `VIEW_TYPE_2D_ARRAY`, sized to `pool.options.max_layers`).
//! Per-upload `layer_info` (RGBA32F 2D) and `image_array` (sRGBA8
//! 2D_ARRAY) plus a per-upload descriptor set tying all four
//! together. The descriptor set is indexed by `binding.generation`
//! like the GL `layer_info_slots` so multiple atlases can share one
//! cache without trampling each other.
//!
//! Uploads go through a per-call staging buffer and a synchronous
//! transfer command — the cache is single-threaded and the new path
//! doesn't have a frame-fence model yet. Image layouts are
//! UNDEFINED → TRANSFER_DST_OPTIMAL → SHADER_READ_ONLY_OPTIMAL.

const std = @import("std");

const atlas_mod = @import("atlas.zig");
const draw_records = @import("draw_records.zig");
const page_pool_mod = @import("page_pool.zig");
const page_mod = @import("page.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");
const upload_common = @import("render/format/upload_common.zig");
const image_mod = @import("image.zig");
const vk_types = @import("render/backend/vulkan/types.zig");
const vk_device = @import("render/backend/vulkan/device.zig");

pub const vk = vk_types.vk;
pub const VulkanContext = vk_types.VulkanContext;

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Image = image_mod.Image;

const CURVE_TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;
const BAND_TEX_WIDTH: u32 = band_tex.TEX_WIDTH;
const CURVE_WORDS_PER_ROW: u32 = CURVE_TEX_WIDTH * 4;
const BAND_WORDS_PER_ROW: u32 = BAND_TEX_WIDTH * 2;

/// One per-upload "slot": each `upload(atlas)` call allocates a fresh
/// descriptor pool + descriptor set, the layer-info image (if the
/// atlas has paint records), the image-array (if there are image
/// paints), and stores everything here keyed by binding.generation.
const BindingSlot = struct {
    desc_pool: vk.VkDescriptorPool = null,
    desc_set: vk.VkDescriptorSet = null,
    layer_image: vk.VkImage = null,
    layer_memory: vk.VkDeviceMemory = null,
    layer_view: vk.VkImageView = null,
    image_array: vk.VkImage = null,
    image_array_memory: vk.VkDeviceMemory = null,
    image_array_view: vk.VkImageView = null,
};

/// Minimal pipeline-shape adapter the cache talks to. The real
/// `VulkanPipeline` satisfies this surface; tests can stub it.
pub const PipelineShape = struct {
    ctx: VulkanContext,
    transfer_cmd_pool: vk.VkCommandPool,
    scheduled_resource_upload_cmd: vk.VkCommandBuffer,
    sampler_nearest: vk.VkSampler,
    sampler_linear: vk.VkSampler,
    desc_set_layout: vk.VkDescriptorSetLayout,
};

pub const VulkanPreparedPages = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: *PagePool,

    /// Pipeline pieces needed to create images, upload via staging, and
    /// build descriptor sets. Captured at init time; the caller owns
    /// these lifetimes (the cache borrows).
    pipeline: PipelineShape,

    // Pool-wide resident images (created lazily on first upload).
    curve_image: vk.VkImage = null,
    curve_memory: vk.VkDeviceMemory = null,
    curve_view: vk.VkImageView = null,
    curve_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    band_image: vk.VkImage = null,
    band_memory: vk.VkDeviceMemory = null,
    band_view: vk.VkImageView = null,
    band_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    curve_height: u32 = 0,
    band_height: u32 = 0,
    layer_count: u32 = 0,

    // Per-upload binding slots, indexed by binding.generation - 1.
    binding_slots: std.ArrayList(BindingSlot) = .empty,

    // Per-layer upload watermarks (parallel to pool.pages).
    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,

    upload_generation: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, pipeline: PipelineShape) !Self {
        const max_layers = pool.options.max_layers;
        const gen = try allocator.alloc(u16, max_layers);
        errdefer allocator.free(gen);
        const curve_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, max_layers);
        errdefer allocator.free(band_words);
        @memset(gen, 0);
        @memset(curve_words, 0);
        @memset(band_words, 0);

        return .{
            .allocator = allocator,
            .pool = pool,
            .pipeline = pipeline,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
        };
    }

    pub fn deinit(self: *Self) void {
        const dev = self.pipeline.ctx.device;
        for (self.binding_slots.items) |*slot| self.destroyBindingSlot(slot);
        self.binding_slots.deinit(self.allocator);

        if (self.curve_view != null) vk.vkDestroyImageView(dev, self.curve_view, null);
        if (self.curve_image != null) vk.vkDestroyImage(dev, self.curve_image, null);
        if (self.curve_memory != null) vk.vkFreeMemory(dev, self.curve_memory, null);
        if (self.band_view != null) vk.vkDestroyImageView(dev, self.band_view, null);
        if (self.band_image != null) vk.vkDestroyImage(dev, self.band_image, null);
        if (self.band_memory != null) vk.vkFreeMemory(dev, self.band_memory, null);

        self.allocator.free(self.prepared_generation);
        self.allocator.free(self.prepared_curve_words);
        self.allocator.free(self.prepared_band_words);
        self.* = undefined;
    }

    fn destroyBindingSlot(self: *Self, slot: *BindingSlot) void {
        const dev = self.pipeline.ctx.device;
        if (slot.image_array_view != null) vk.vkDestroyImageView(dev, slot.image_array_view, null);
        if (slot.image_array != null) vk.vkDestroyImage(dev, slot.image_array, null);
        if (slot.image_array_memory != null) vk.vkFreeMemory(dev, slot.image_array_memory, null);
        if (slot.layer_view != null) vk.vkDestroyImageView(dev, slot.layer_view, null);
        if (slot.layer_image != null) vk.vkDestroyImage(dev, slot.layer_image, null);
        if (slot.layer_memory != null) vk.vkFreeMemory(dev, slot.layer_memory, null);
        if (slot.desc_pool != null) vk.vkDestroyDescriptorPool(dev, slot.desc_pool, null);
        slot.* = .{};
    }

    /// Look up the descriptor set for a binding generation, or null if
    /// the cache has never seen that generation.
    pub fn descriptorSetFor(self: *const Self, generation: u32) vk.VkDescriptorSet {
        if (generation == 0 or generation > self.binding_slots.items.len) return null;
        return self.binding_slots.items[generation - 1].desc_set;
    }

    fn ensurePoolImages(self: *Self) !void {
        if (self.curve_image != null and self.band_image != null) return;

        const options = self.pool.options;
        self.curve_height = options.curve_words_per_page / CURVE_WORDS_PER_ROW;
        self.band_height = options.band_words_per_page / BAND_WORDS_PER_ROW;
        self.layer_count = options.max_layers;
        std.debug.assert(self.curve_height > 0 and self.band_height > 0);

        self.curve_image = try vk_device.createImage2DArray(
            &self.pipeline,
            CURVE_TEX_WIDTH,
            self.curve_height,
            self.layer_count,
            vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        );
        self.curve_memory = try vk_device.allocateImageMemory(&self.pipeline, self.curve_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.curve_image, self.curve_memory, 0);
        self.curve_view = try vk_device.createImageView(
            &self.pipeline,
            self.curve_image,
            vk.VK_FORMAT_R16G16B16A16_SFLOAT,
            self.layer_count,
        );

        self.band_image = try vk_device.createImage2DArray(
            &self.pipeline,
            BAND_TEX_WIDTH,
            self.band_height,
            self.layer_count,
            vk.VK_FORMAT_R16G16_UINT,
        );
        self.band_memory = try vk_device.allocateImageMemory(&self.pipeline, self.band_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.band_image, self.band_memory, 0);
        self.band_view = try vk_device.createImageView(
            &self.pipeline,
            self.band_image,
            vk.VK_FORMAT_R16G16_UINT,
            self.layer_count,
        );
    }

    /// Upload one page's full curve + band buffers into its layer.
    fn uploadPageFull(self: *Self, p: *const AtlasPage) !void {
        const layer = p.layer_index;
        const curve_src = p.curve.data;
        const band_src = p.band.data;
        std.debug.assert(curve_src.len % CURVE_WORDS_PER_ROW == 0);
        std.debug.assert(band_src.len % BAND_WORDS_PER_ROW == 0);

        const curve_byte_count = curve_src.len * @sizeOf(u16);
        const band_byte_count = band_src.len * @sizeOf(u16);
        const total_staging: vk.VkDeviceSize = @intCast(curve_byte_count + band_byte_count);

        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try vk_device.createBuffer(
            &self.pipeline,
            total_staging,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        errdefer vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);

        var map_ptr: ?*anyopaque = null;
        try vk_device.check(vk.vkMapMemory(self.pipeline.ctx.device, staging_mem, 0, total_staging, 0, &map_ptr));
        const dst: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);
        const curve_bytes: [*]const u8 = @ptrCast(curve_src.ptr);
        const band_bytes: [*]const u8 = @ptrCast(band_src.ptr);
        @memcpy(dst[0..curve_byte_count], curve_bytes[0..curve_byte_count]);
        @memcpy(dst[curve_byte_count..total_staging], band_bytes[0..band_byte_count]);
        vk.vkUnmapMemory(self.pipeline.ctx.device, staging_mem);

        const transfer = try vk_device.beginTransferCommand(&self.pipeline);
        errdefer vk_device.discardTransferCommand(&self.pipeline, transfer);
        const cmd = transfer.cmd;

        vk_device.transitionImageLayout(cmd, self.curve_image, self.layer_count, self.curve_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        vk_device.transitionImageLayout(cmd, self.band_image, self.layer_count, self.band_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

        const curve_region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
            .bufferOffset = 0,
            .imageSubresource = vk.VkImageSubresourceLayers{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = layer,
                .layerCount = 1,
            },
            .imageExtent = vk.VkExtent3D{ .width = CURVE_TEX_WIDTH, .height = self.curve_height, .depth = 1 },
        });
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &curve_region);

        const band_region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
            .bufferOffset = @as(vk.VkDeviceSize, @intCast(curve_byte_count)),
            .imageSubresource = vk.VkImageSubresourceLayers{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = layer,
                .layerCount = 1,
            },
            .imageExtent = vk.VkExtent3D{ .width = BAND_TEX_WIDTH, .height = self.band_height, .depth = 1 },
        });
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.band_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &band_region);

        vk_device.transitionImageLayout(cmd, self.curve_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        vk_device.transitionImageLayout(cmd, self.band_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        try vk_device.finishTransferCommand(&self.pipeline, transfer);
        vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
        self.curve_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        self.band_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

        self.prepared_curve_words[layer] = p.curve.usedWords();
        self.prepared_band_words[layer] = p.band.usedWords();
    }

    const UploadedImages = struct {
        image_array: vk.VkImage = null,
        image_memory: vk.VkDeviceMemory = null,
        image_view: vk.VkImageView = null,
        allocated_width: u32 = 0,
        allocated_height: u32 = 0,
        layer_count: u32 = 0,
        unique_images: std.ArrayList(*const Image) = .empty,

        fn deinit(self: *UploadedImages, allocator: std.mem.Allocator) void {
            self.unique_images.deinit(allocator);
        }

        fn layerForImage(self: *const UploadedImages, image: *const Image) ?u32 {
            for (self.unique_images.items, 0..) |existing, i| {
                if (existing == image) return @intCast(i);
            }
            return null;
        }
    };

    fn buildImageArray(self: *Self, scratch: std.mem.Allocator, atlas: *const Atlas) !UploadedImages {
        const records = atlas.paint_image_records orelse return .{};
        var result = UploadedImages{};
        errdefer result.deinit(scratch);

        for (records) |maybe_rec| {
            const rec = maybe_rec orelse continue;
            if (result.layerForImage(rec.image) != null) continue;
            try result.unique_images.append(scratch, rec.image);
        }
        if (result.unique_images.items.len == 0) return result;

        var max_w: u32 = 1;
        var max_h: u32 = 1;
        for (result.unique_images.items) |img| {
            max_w = @max(max_w, img.width);
            max_h = @max(max_h, img.height);
        }
        const alloc_w = upload_common.imageExtentCapacity(max_w);
        const alloc_h = upload_common.imageExtentCapacity(max_h);
        const layer_count: u32 = @intCast(result.unique_images.items.len);
        result.allocated_width = alloc_w;
        result.allocated_height = alloc_h;
        result.layer_count = layer_count;

        result.image_array = try vk_device.createImage2DArray(
            &self.pipeline,
            alloc_w,
            alloc_h,
            layer_count,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
        );
        result.image_memory = try vk_device.allocateImageMemory(&self.pipeline, result.image_array);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, result.image_array, result.image_memory, 0);
        result.image_view = try vk_device.createImageView(
            &self.pipeline,
            result.image_array,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
            layer_count,
        );

        var total_bytes: usize = 0;
        for (result.unique_images.items) |img| {
            total_bytes += @as(usize, img.width) * @as(usize, img.height) * 4;
        }
        if (total_bytes == 0) return result;

        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try vk_device.createBuffer(
            &self.pipeline,
            @intCast(total_bytes),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        errdefer vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
        var map_ptr: ?*anyopaque = null;
        try vk_device.check(vk.vkMapMemory(self.pipeline.ctx.device, staging_mem, 0, @intCast(total_bytes), 0, &map_ptr));
        const dst: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);

        var offsets = try scratch.alloc(usize, layer_count);
        defer scratch.free(offsets);
        var cursor: usize = 0;
        for (result.unique_images.items, 0..) |img, i| {
            offsets[i] = cursor;
            const img_bytes = @as(usize, img.width) * @as(usize, img.height) * 4;
            @memcpy(dst[cursor..][0..img_bytes], img.pixels[0..img_bytes]);
            cursor += img_bytes;
        }
        vk.vkUnmapMemory(self.pipeline.ctx.device, staging_mem);

        const transfer = try vk_device.beginTransferCommand(&self.pipeline);
        errdefer vk_device.discardTransferCommand(&self.pipeline, transfer);
        const cmd = transfer.cmd;
        vk_device.transitionImageLayout(cmd, result.image_array, layer_count, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        for (result.unique_images.items, 0..) |img, i| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(offsets[i])),
                .imageSubresource = vk.VkImageSubresourceLayers{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .mipLevel = 0,
                    .baseArrayLayer = @intCast(i),
                    .layerCount = 1,
                },
                .imageExtent = vk.VkExtent3D{ .width = img.width, .height = img.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, result.image_array, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        vk_device.transitionImageLayout(cmd, result.image_array, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        try vk_device.finishTransferCommand(&self.pipeline, transfer);
        vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);

        return result;
    }

    fn buildLayerInfoImage(self: *Self, scratch: std.mem.Allocator, atlas: *const Atlas, images: *const UploadedImages, slot: *BindingSlot) !void {
        const src = atlas.layer_info_data orelse return;
        const w = atlas.layer_info_width;
        const h = atlas.layer_info_height;
        if (w == 0 or h == 0) return;

        const data_copy = try scratch.dupe(f32, src);
        defer scratch.free(data_copy);

        if (atlas.paint_image_records) |records| {
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                const layer = images.layerForImage(rec.image) orelse continue;
                const uv_scale_x: f32 = if (images.allocated_width == 0) 1.0 else @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(images.allocated_width));
                const uv_scale_y: f32 = if (images.allocated_height == 0) 1.0 else @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(images.allocated_height));
                const View = struct {
                    layer: u32,
                    uv_scale: struct { x: f32, y: f32 },
                };
                upload_common.patchImagePaintRecord(data_copy, w, w, 0, rec.texel_offset, View{
                    .layer = layer,
                    .uv_scale = .{ .x = uv_scale_x, .y = uv_scale_y },
                });
            }
        }

        slot.layer_image = try vk_device.createImage2D(&self.pipeline, w, h, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
        slot.layer_memory = try vk_device.allocateImageMemory(&self.pipeline, slot.layer_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, slot.layer_image, slot.layer_memory, 0);
        slot.layer_view = try vk_device.createImageView2D(&self.pipeline, slot.layer_image, vk.VK_FORMAT_R32G32B32A32_SFLOAT);

        const total_bytes: usize = @as(usize, w) * @as(usize, h) * 4 * @sizeOf(f32);
        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try vk_device.createBuffer(
            &self.pipeline,
            @intCast(total_bytes),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        errdefer vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
        var map_ptr: ?*anyopaque = null;
        try vk_device.check(vk.vkMapMemory(self.pipeline.ctx.device, staging_mem, 0, @intCast(total_bytes), 0, &map_ptr));
        const dst: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);
        const src_bytes: [*]const u8 = @ptrCast(data_copy.ptr);
        @memcpy(dst[0..total_bytes], src_bytes[0..total_bytes]);
        vk.vkUnmapMemory(self.pipeline.ctx.device, staging_mem);

        const transfer = try vk_device.beginTransferCommand(&self.pipeline);
        errdefer vk_device.discardTransferCommand(&self.pipeline, transfer);
        const cmd = transfer.cmd;
        vk_device.transitionImageLayout(cmd, slot.layer_image, 1, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
            .bufferOffset = 0,
            .imageSubresource = vk.VkImageSubresourceLayers{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageExtent = vk.VkExtent3D{ .width = w, .height = h, .depth = 1 },
        });
        vk.vkCmdCopyBufferToImage(cmd, staging_buf, slot.layer_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        vk_device.transitionImageLayout(cmd, slot.layer_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        try vk_device.finishTransferCommand(&self.pipeline, transfer);
        vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
    }

    fn createDescriptorSet(self: *Self, slot: *BindingSlot) !void {
        const dev = self.pipeline.ctx.device;
        const pool_size = [1]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 4 },
        };
        const dp_info = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
        });
        try vk_device.check(vk.vkCreateDescriptorPool(dev, &dp_info, null, &slot.desc_pool));
        errdefer {
            if (slot.desc_pool != null) vk.vkDestroyDescriptorPool(dev, slot.desc_pool, null);
            slot.desc_pool = null;
        }

        var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
        ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        ds_info.descriptorPool = slot.desc_pool;
        ds_info.descriptorSetCount = 1;
        ds_info.pSetLayouts = @ptrCast(&self.pipeline.desc_set_layout);
        try vk_device.check(vk.vkAllocateDescriptorSets(dev, &ds_info, &slot.desc_set));

        const effective_layer_view = if (slot.layer_view != null) slot.layer_view else self.curve_view;
        const effective_image_view = if (slot.image_array_view != null) slot.image_array_view else self.curve_view;
        const image_infos = [4]vk.VkDescriptorImageInfo{
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = self.curve_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = self.band_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = effective_layer_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_linear, .imageView = effective_image_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
        };
        const writes = [4]vk.VkWriteDescriptorSet{
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = slot.desc_set,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[0],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = slot.desc_set,
                .dstBinding = 1,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[1],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = slot.desc_set,
                .dstBinding = 2,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[2],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = slot.desc_set,
                .dstBinding = 3,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[3],
            }),
        };
        vk.vkUpdateDescriptorSets(dev, 4, &writes, 0, null);
    }

    pub fn upload(self: *Self, scratch: std.mem.Allocator, atlas: *const Atlas) !Binding {
        self.upload_generation += 1;
        try self.ensurePoolImages();

        // Upload any stale or never-touched pages first. We currently
        // upload the page's full allocated buffer (matches the GL path);
        // partial row deltas can wait until a measurable benefit shows.
        for (atlas.pages) |p| {
            const layer = p.layer_index;
            std.debug.assert(layer < self.layer_count);
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const stale = self.prepared_generation[layer] != cur_gen or
                cur_curve != self.prepared_curve_words[layer] or
                cur_band != self.prepared_band_words[layer];
            if (!stale) continue;
            self.prepared_generation[layer] = cur_gen;
            try self.uploadPageFull(p);
        }

        var slot = BindingSlot{};
        errdefer self.destroyBindingSlot(&slot);

        var images = try self.buildImageArray(scratch, atlas);
        defer images.deinit(scratch);
        slot.image_array = images.image_array;
        slot.image_array_memory = images.image_memory;
        slot.image_array_view = images.image_view;

        try self.buildLayerInfoImage(scratch, atlas, &images, &slot);
        try self.createDescriptorSet(&slot);

        try self.binding_slots.append(self.allocator, slot);
        return .{ .pool = self.pool, .generation = self.upload_generation };
    }
};

const testing = std.testing;

test "VulkanPreparedPages init allocates per-layer state sized to pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 4,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    // The Vulkan path needs a real device + context. For this data-only
    // test we just verify the per-layer arrays size correctly using a
    // zero-initialized pipeline shape; the cache is constructed but
    // never asked to touch GPU resources.
    const zero_pipeline = PipelineShape{
        .ctx = std.mem.zeroes(VulkanContext),
        .transfer_cmd_pool = null,
        .scheduled_resource_upload_cmd = null,
        .sampler_nearest = null,
        .sampler_linear = null,
        .desc_set_layout = null,
    };
    var cache = try VulkanPreparedPages.init(testing.allocator, pool, zero_pipeline);
    defer {
        // We never created GPU resources, but the deinit walks ArrayLists
        // and tries to destroy. With null handles + null device the
        // Vulkan calls are no-ops, but we still need to clean up the
        // CPU-side allocations.
        cache.binding_slots.deinit(cache.allocator);
        cache.allocator.free(cache.prepared_generation);
        cache.allocator.free(cache.prepared_curve_words);
        cache.allocator.free(cache.prepared_band_words);
    }

    try testing.expectEqual(@as(usize, 4), cache.prepared_generation.len);
    try testing.expectEqual(@as(u32, 0), cache.upload_generation);
}
