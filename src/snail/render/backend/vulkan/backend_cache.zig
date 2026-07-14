//! Vulkan persistent prepared-pages cache for snail.
//!
//! Mirrors `CpuBackendCache` and `GlBackendCache`:
//! caller-sized capacity, slot allocation via free-list, explicit
//! `release(binding)`, no auto-grow.
//!
//! Per-cache resident GPU state:
//!
//! - `curve_image` / `band_image` — `VK_IMAGE_VIEW_TYPE_2D_ARRAY`
//!   sized to `pool.options.max_layers`. Curve = `R16G16B16A16_SFLOAT`,
//!   band = `R16G16_UINT`. Pages stream in via per-layer
//!   `vkCmdCopyBufferToImage`.
//! - `layer_info_image` — `VK_IMAGE_VIEW_TYPE_2D`
//!   (`R32G32B32A32_SFLOAT`) sized to
//!   `INFO_WIDTH × options.layer_info_height`. Each binding occupies
//!   a row band starting at `binding.info_row_base`.
//! - `image_array_image` — `VK_IMAGE_VIEW_TYPE_2D_ARRAY`
//!   (`R8G8B8A8_SRGB`) sized to
//!   `options.max_image_width × options.max_image_height × options.max_images`.
//!   Allocated only when `max_images > 0`.
//!
//! One descriptor set is created at init time and points at all four
//! resident images. The shader reads info_y / image_layer absolute (emit
//! adds `binding.info_row_base` / patches the layer_info texel with
//! `image_layer_base + local_layer`), so no per-binding descriptor swap
//! is needed.

const std = @import("std");

const atlas_mod = @import("../../../atlas.zig");
const draw_records = @import("../../../picture/draw_records.zig");
const page_pool_mod = @import("../../../atlas/page_pool.zig");
const page_mod = @import("../../../atlas/page.zig");
const curve_tex = @import("../../../format/curve_texture.zig");
const band_tex = @import("../../../format/band_texture.zig");
const paint_records = @import("../../../atlas/paint_records.zig");
const upload_common = @import("../../../format/upload_common.zig");
const image_mod = @import("../../../image.zig");
const vk_types = @import("types.zig");
const vk_device = @import("device.zig");
const cache_base = @import("../cache.zig");
const range_allocator = @import("../range_allocator.zig");

const RangeAllocator = range_allocator.RangeAllocator;
const Range = range_allocator.Range;

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
const INFO_WIDTH: u32 = paint_records.info_width;

pub const CacheOptions = cache_base.GpuCacheOptions;
pub const UploadError = cache_base.BaseUploadError || error{
    ImageTooLarge,
    MissingCommandBuffer,
    NoSuitableMemory,
    VulkanError,
    VulkanMapMemoryReturnedNull,
};
pub const ResizeError = cache_base.BaseResizeError || error{VulkanError};

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

pub const VulkanBackendCache = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: CacheOptions,
    pipeline: PipelineShape,

    // Pool-wide resident images.
    curve_image: vk.VkImage = null,
    curve_memory: vk.VkDeviceMemory = null,
    curve_view: vk.VkImageView = null,
    curve_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,

    band_image: vk.VkImage = null,
    band_memory: vk.VkDeviceMemory = null,
    band_view: vk.VkImageView = null,
    band_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,

    layer_info_image: vk.VkImage = null,
    layer_info_memory: vk.VkDeviceMemory = null,
    layer_info_view: vk.VkImageView = null,
    layer_info_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,

    image_array_image: vk.VkImage = null,
    image_array_memory: vk.VkDeviceMemory = null,
    image_array_view: vk.VkImageView = null,
    image_array_layout: vk.VkImageLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,

    // Shared descriptor set + pool (one set across all bindings).
    desc_pool: vk.VkDescriptorPool = null,
    desc_set: vk.VkDescriptorSet = null,

    curve_height: u32 = 0,
    band_height: u32 = 0,
    layer_count: u32 = 0,

    // Per-binding slot bookkeeping.
    bindings: []BindingSlot,
    active_bindings: u32 = 0,
    layer_info_ranges: RangeAllocator = .{},
    image_ranges: RangeAllocator = .{},
    image_storage: []?*const Image = &.{},

    // Per-pool-layer streaming watermarks.
    prepared_generation: []u16,
    prepared_curve_words: []u32,
    prepared_band_words: []u32,

    upload_generation: u32 = 0,

    pub const BindingSlot = struct {
        active: bool = false,
        generation: u32 = 0,
        info_row_base: u32 = 0,
        info_height: u32 = 0,
        image_layer_base: u32 = 0,
        image_count: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, pipeline: PipelineShape, options: CacheOptions) !Self {
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

        const bindings = try allocator.alloc(BindingSlot, options.max_bindings);
        errdefer allocator.free(bindings);
        for (bindings) |*b| b.* = .{};

        const image_storage = if (options.max_images > 0)
            try allocator.alloc(?*const Image, options.max_images)
        else
            @as([]?*const Image, &.{});
        errdefer if (options.max_images > 0) allocator.free(image_storage);
        if (options.max_images > 0) @memset(image_storage, null);

        var layer_info_ranges = try RangeAllocator.init(allocator, options.layer_info_height);
        errdefer layer_info_ranges.deinit(allocator);

        var image_ranges = try RangeAllocator.init(allocator, options.max_images);
        errdefer image_ranges.deinit(allocator);

        return .{
            .allocator = allocator,
            .pool = pool,
            .options = options,
            .pipeline = pipeline,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
            .bindings = bindings,
            .image_storage = image_storage,
            .layer_info_ranges = layer_info_ranges,
            .image_ranges = image_ranges,
        };
    }

    pub fn deinit(self: *Self) void {
        self.destroyGpuResources();
        self.allocator.free(self.prepared_generation);
        self.allocator.free(self.prepared_curve_words);
        self.allocator.free(self.prepared_band_words);
        self.allocator.free(self.bindings);
        if (self.options.max_images > 0) self.allocator.free(self.image_storage);
        self.layer_info_ranges.deinit(self.allocator);
        self.image_ranges.deinit(self.allocator);
        self.* = undefined;
    }

    // ── Custom-shader resource handles ──
    //
    // Vulkan backends expose the `VkImageView`s a custom shader needs
    // to sample the cache's textures. They become non-null once the
    // first `upload`/`uploadDelta` populates them, and are left in
    // `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL` by that upload — so a
    // caller sampling them after the upload's transfer completes needs
    // no further layout transition.

    pub fn curveTexHandle(self: *const Self) vk.VkImageView {
        return self.curve_view;
    }

    pub fn bandTexHandle(self: *const Self) vk.VkImageView {
        return self.band_view;
    }

    pub fn layerInfoTexHandle(self: *const Self) vk.VkImageView {
        return self.layer_info_view;
    }

    pub fn imageArrayHandle(self: *const Self) vk.VkImageView {
        return self.image_array_view;
    }

    fn destroyGpuResources(self: *Self) void {
        const dev = self.pipeline.ctx.device;
        if (dev == null) return;

        if (self.desc_pool != null) vk.vkDestroyDescriptorPool(dev, self.desc_pool, null);
        self.desc_pool = null;
        self.desc_set = null;

        const destroy_image = struct {
            fn call(d: vk.VkDevice, view: *vk.VkImageView, img: *vk.VkImage, mem: *vk.VkDeviceMemory) void {
                if (view.* != null) vk.vkDestroyImageView(d, view.*, null);
                if (img.* != null) vk.vkDestroyImage(d, img.*, null);
                if (mem.* != null) vk.vkFreeMemory(d, mem.*, null);
                view.* = null;
                img.* = null;
                mem.* = null;
            }
        }.call;
        destroy_image(dev, &self.curve_view, &self.curve_image, &self.curve_memory);
        destroy_image(dev, &self.band_view, &self.band_image, &self.band_memory);
        destroy_image(dev, &self.layer_info_view, &self.layer_info_image, &self.layer_info_memory);
        destroy_image(dev, &self.image_array_view, &self.image_array_image, &self.image_array_memory);

        self.curve_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
        self.band_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
        self.layer_info_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
        self.image_array_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
    }

    pub fn resize(self: *Self, options: CacheOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;
        self.destroyGpuResources();
        self.options = options;

        const new_bindings = try self.allocator.realloc(self.bindings, options.max_bindings);
        for (new_bindings) |*b| b.* = .{};
        self.bindings = new_bindings;

        if (self.image_storage.len > 0) self.allocator.free(self.image_storage);
        self.image_storage = if (options.max_images > 0)
            try self.allocator.alloc(?*const Image, options.max_images)
        else
            &.{};
        if (options.max_images > 0) @memset(self.image_storage, null);

        try self.layer_info_ranges.reset(self.allocator, options.layer_info_height);
        try self.image_ranges.reset(self.allocator, options.max_images);
    }

    pub fn descriptorSet(self: *const Self) vk.VkDescriptorSet {
        return self.desc_set;
    }

    pub fn upload(
        self: *Self,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
        out_bindings: []Binding,
    ) UploadError!void {
        std.debug.assert(atlases.len == out_bindings.len);

        for (atlases) |atlas| {
            if (atlas.pool) |p| {
                if (p != self.pool) return error.UnknownPool;
            }
            const records = atlas.paint_image_records orelse continue;
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                if (rec.image.width > self.options.max_image_width or rec.image.height > self.options.max_image_height) {
                    return error.ImageTooLarge;
                }
            }
        }

        try self.ensureGpuResources();

        var batch = UploadBatch{};
        defer batch.deinit(scratch);

        var allocated_layer_ranges: std.ArrayList(Range) = .empty;
        defer allocated_layer_ranges.deinit(scratch);
        var allocated_image_ranges: std.ArrayList(Range) = .empty;
        defer allocated_image_ranges.deinit(scratch);
        var allocated_slot_indices: std.ArrayList(u32) = .empty;
        defer allocated_slot_indices.deinit(scratch);
        var layer_info_copies: std.ArrayList([]const f32) = .empty;
        defer {
            for (layer_info_copies.items) |c| scratch.free(c);
            layer_info_copies.deinit(scratch);
        }

        var success = false;
        defer if (!success) {
            for (allocated_layer_ranges.items) |r| self.layer_info_ranges.release(self.allocator, r) catch {};
            for (allocated_image_ranges.items) |r| self.image_ranges.release(self.allocator, r) catch {};
            for (allocated_slot_indices.items) |i| self.bindings[i] = .{};
        };

        for (atlases, 0..) |atlas, i| {
            const info_height = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
            const image_count = countUniqueImages(atlas);

            const slot_index = self.findFreeBinding() orelse return error.NoFreeBinding;
            try allocated_slot_indices.append(scratch, slot_index);

            const info_range: Range = if (info_height == 0)
                .{ .base = 0, .size = 0 }
            else
                self.layer_info_ranges.take(info_height) orelse return error.NoFreeLayerInfoRows;
            try allocated_layer_ranges.append(scratch, info_range);

            const image_range: Range = if (image_count == 0)
                .{ .base = 0, .size = 0 }
            else
                self.image_ranges.take(image_count) orelse return error.NoFreeImageLayers;
            try allocated_image_ranges.append(scratch, image_range);

            self.upload_generation += 1;
            const slot = &self.bindings[slot_index];
            slot.* = .{
                .active = true,
                .generation = self.upload_generation,
                .info_row_base = info_range.base,
                .info_height = info_range.size,
                .image_layer_base = image_range.base,
                .image_count = image_range.size,
            };

            try self.queueBindingData(scratch, &batch, &layer_info_copies, atlas, slot);

            out_bindings[i] = .{
                .pool = self.pool,
                .generation = slot.generation,
                .info_row_base = slot.info_row_base,
                .image_layer_base = slot.image_layer_base,
            };
        }

        try self.flushBatch(scratch, &batch);

        self.active_bindings += @intCast(atlases.len);
        success = true;
    }

    /// Incrementally update `prev_binding`'s slot with `atlas`'s
    /// current state. See `GlBackendCache.uploadDelta` for the
    /// contract; this Vulkan implementation queues only the changed
    /// curve / band / layer-info / image regions into a single
    /// `UploadBatch` that's flushed before returning.
    pub fn uploadDelta(
        self: *Self,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        const slot_index = self.findSlotByGeneration(prev_binding.generation) orelse return error.UnknownBinding;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return error.UnknownBinding;

        const need_info_height = if (atlas.layer_info_data != null) atlas.layer_info_height else 0;
        if (need_info_height > slot.info_height) return error.NoLayerInfoRoomToGrow;
        const need_image_count = countUniqueImages(atlas);
        if (need_image_count > slot.image_count) return error.NoLayerInfoRoomToGrow;

        if (atlas.paint_image_records) |records| {
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                if (rec.image.width > self.options.max_image_width or rec.image.height > self.options.max_image_height) {
                    return error.ImageTooLarge;
                }
            }
        }

        try self.ensureGpuResources();

        var batch = UploadBatch{};
        defer batch.deinit(scratch);
        var layer_info_copies: std.ArrayList([]const f32) = .empty;
        defer {
            for (layer_info_copies.items) |c| scratch.free(c);
            layer_info_copies.deinit(scratch);
        }

        try self.queueBindingData(scratch, &batch, &layer_info_copies, atlas, slot);
        try self.flushBatch(scratch, &batch);

        return .{
            .pool = self.pool,
            .generation = slot.generation,
            .info_row_base = slot.info_row_base,
            .image_layer_base = slot.image_layer_base,
        };
    }

    pub fn release(self: *Self, binding: Binding) void {
        const slot_index = self.findSlotByGeneration(binding.generation) orelse return;
        const slot = &self.bindings[slot_index];
        if (!slot.active) return;

        if (slot.info_height > 0) {
            self.layer_info_ranges.release(self.allocator, .{ .base = slot.info_row_base, .size = slot.info_height }) catch {};
        }
        if (slot.image_count > 0) {
            for (slot.image_layer_base..slot.image_layer_base + slot.image_count) |layer| {
                self.image_storage[layer] = null;
            }
            self.image_ranges.release(self.allocator, .{ .base = slot.image_layer_base, .size = slot.image_count }) catch {};
        }
        slot.* = .{};
        self.active_bindings -= 1;
    }

    // ── Resident image creation ──

    fn ensureGpuResources(self: *Self) UploadError!void {
        if (self.curve_image == null) try self.createPoolImages();
        if (self.layer_info_image == null and self.options.layer_info_height > 0) try self.createLayerInfoImage();
        if (self.image_array_image == null and self.options.max_images > 0) try self.createImageArrayImage();
        if (self.desc_pool == null) try self.createDescriptorSet();
    }

    fn createPoolImages(self: *Self) UploadError!void {
        const opts = self.pool.options;
        self.curve_height = opts.curve_words_per_page / CURVE_WORDS_PER_ROW;
        self.band_height = opts.band_words_per_page / BAND_WORDS_PER_ROW;
        self.layer_count = opts.max_layers;
        std.debug.assert(self.curve_height > 0 and self.band_height > 0);

        self.curve_image = try vk_device.createImage2DArray(&self.pipeline, CURVE_TEX_WIDTH, self.curve_height, self.layer_count, vk.VK_FORMAT_R16G16B16A16_SFLOAT);
        self.curve_memory = try vk_device.allocateImageMemory(&self.pipeline, self.curve_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.curve_image, self.curve_memory, 0);
        self.curve_view = try vk_device.createImageView(&self.pipeline, self.curve_image, vk.VK_FORMAT_R16G16B16A16_SFLOAT, self.layer_count);

        self.band_image = try vk_device.createImage2DArray(&self.pipeline, BAND_TEX_WIDTH, self.band_height, self.layer_count, vk.VK_FORMAT_R16G16_UINT);
        self.band_memory = try vk_device.allocateImageMemory(&self.pipeline, self.band_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.band_image, self.band_memory, 0);
        self.band_view = try vk_device.createImageView(&self.pipeline, self.band_image, vk.VK_FORMAT_R16G16_UINT, self.layer_count);
    }

    fn createLayerInfoImage(self: *Self) UploadError!void {
        self.layer_info_image = try vk_device.createImage2D(&self.pipeline, INFO_WIDTH, self.options.layer_info_height, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
        self.layer_info_memory = try vk_device.allocateImageMemory(&self.pipeline, self.layer_info_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.layer_info_image, self.layer_info_memory, 0);
        self.layer_info_view = try vk_device.createImageView2D(&self.pipeline, self.layer_info_image, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
    }

    fn createImageArrayImage(self: *Self) UploadError!void {
        self.image_array_image = try vk_device.createImage2DArray(&self.pipeline, self.options.max_image_width, self.options.max_image_height, self.options.max_images, vk.VK_FORMAT_R8G8B8A8_SRGB);
        self.image_array_memory = try vk_device.allocateImageMemory(&self.pipeline, self.image_array_image);
        _ = vk.vkBindImageMemory(self.pipeline.ctx.device, self.image_array_image, self.image_array_memory, 0);
        self.image_array_view = try vk_device.createImageView(&self.pipeline, self.image_array_image, vk.VK_FORMAT_R8G8B8A8_SRGB, self.options.max_images);
    }

    fn createDescriptorSet(self: *Self) UploadError!void {
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
        try vk_device.check(vk.vkCreateDescriptorPool(dev, &dp_info, null, &self.desc_pool));

        var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
        ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        ds_info.descriptorPool = self.desc_pool;
        ds_info.descriptorSetCount = 1;
        ds_info.pSetLayouts = @ptrCast(&self.pipeline.desc_set_layout);
        try vk_device.check(vk.vkAllocateDescriptorSets(dev, &ds_info, &self.desc_set));

        // The shader always reads from layer_info/image_array via
        // bindings 2/3. When the cache has no such resources, point
        // the descriptor at `curve_view` as a placeholder — the
        // shader will never actually sample it for that draw.
        const effective_layer_view = if (self.layer_info_view != null) self.layer_info_view else self.curve_view;
        const effective_image_view = if (self.image_array_view != null) self.image_array_view else self.curve_view;

        const image_infos = [4]vk.VkDescriptorImageInfo{
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = self.curve_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = self.band_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_nearest, .imageView = effective_layer_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.pipeline.sampler_linear, .imageView = effective_image_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
        };
        var writes: [4]vk.VkWriteDescriptorSet = undefined;
        for (&writes, 0..) |*w, i| {
            w.* = std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.desc_set,
                .dstBinding = @as(u32, @intCast(i)),
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[i],
            });
        }
        vk.vkUpdateDescriptorSets(dev, 4, &writes, 0, null);
    }

    // ── Batched staging upload ──
    //
    // Instead of one staging buffer + transfer command per resource per
    // atlas, queueBindingData accumulates copies into an UploadBatch.
    // After all atlases are queued, flushBatch packs every source into
    // a single staging buffer and submits one transfer command. This
    // turns O(atlases × resources) round trips into O(1).

    fn queueBindingData(
        self: *Self,
        scratch: std.mem.Allocator,
        batch: *UploadBatch,
        layer_info_copies: *std.ArrayList([]const f32),
        atlas: *const Atlas,
        slot: *BindingSlot,
    ) UploadError!void {
        for (atlas.pages) |p| {
            const layer = p.layer_index;
            if (layer >= self.layer_count) return error.PageNotInPool;
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const stale = self.prepared_generation[layer] != cur_gen or
                cur_curve != self.prepared_curve_words[layer] or
                cur_band != self.prepared_band_words[layer];
            if (!stale) continue;
            self.prepared_generation[layer] = cur_gen;

            const curve_bytes = p.curve.data.len * @sizeOf(u16);
            const band_bytes = p.band.data.len * @sizeOf(u16);
            try batch.curve_ops.append(scratch, .{
                .src = @as([*]const u8, @ptrCast(p.curve.data.ptr))[0..curve_bytes],
                .layer = layer,
                .width = CURVE_TEX_WIDTH,
                .height = self.curve_height,
            });
            try batch.band_ops.append(scratch, .{
                .src = @as([*]const u8, @ptrCast(p.band.data.ptr))[0..band_bytes],
                .layer = layer,
                .width = BAND_TEX_WIDTH,
                .height = self.band_height,
            });
            self.prepared_curve_words[layer] = p.curve.usedWords();
            self.prepared_band_words[layer] = p.band.usedWords();
        }

        if (atlas.layer_info_data == null) return;
        const src = atlas.layer_info_data.?;
        std.debug.assert(atlas.layer_info_width == INFO_WIDTH);

        const data_copy = try scratch.dupe(f32, src);
        // Hand ownership to layer_info_copies so the slice lives until
        // flushBatch reads from it.
        try layer_info_copies.append(scratch, data_copy);

        if (atlas.paint_image_records) |records| {
            var local_layer: u32 = 0;
            var seen = std.AutoHashMap(*const Image, u32).init(scratch);
            defer seen.deinit();
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                const gop = try seen.getOrPut(rec.image);
                if (!gop.found_existing) {
                    gop.value_ptr.* = local_layer;
                    const abs_layer = slot.image_layer_base + local_layer;
                    self.image_storage[abs_layer] = rec.image;
                    const img_bytes = @as(usize, rec.image.width) * @as(usize, rec.image.height) * 4;
                    try batch.image_ops.append(scratch, .{
                        .src = rec.image.pixels[0..img_bytes],
                        .layer = abs_layer,
                        .width = rec.image.width,
                        .height = rec.image.height,
                    });
                    local_layer += 1;
                }
                const abs_layer = slot.image_layer_base + gop.value_ptr.*;
                const uv_scale_x: f32 = @as(f32, @floatFromInt(rec.image.width)) / @as(f32, @floatFromInt(self.options.max_image_width));
                const uv_scale_y: f32 = @as(f32, @floatFromInt(rec.image.height)) / @as(f32, @floatFromInt(self.options.max_image_height));
                const View = struct {
                    layer: u32,
                    uv_scale: struct { x: f32, y: f32 },
                };
                upload_common.patchImagePaintRecord(data_copy, INFO_WIDTH, INFO_WIDTH, 0, rec.texel_offset, View{
                    .layer = abs_layer,
                    .uv_scale = .{ .x = uv_scale_x, .y = uv_scale_y },
                });
            }
        }

        if (slot.info_height > 0) {
            const data_bytes = data_copy.len * @sizeOf(f32);
            try batch.layer_info_ops.append(scratch, .{
                .src = @as([*]const u8, @ptrCast(data_copy.ptr))[0..data_bytes],
                .row_base = slot.info_row_base,
                .width = INFO_WIDTH,
                .height = slot.info_height,
            });
        }
    }

    fn flushBatch(self: *Self, _: std.mem.Allocator, batch: *UploadBatch) UploadError!void {
        var total: usize = 0;
        for (batch.curve_ops.items) |op| total += op.src.len;
        for (batch.band_ops.items) |op| total += op.src.len;
        for (batch.image_ops.items) |op| total += op.src.len;
        for (batch.layer_info_ops.items) |op| total += op.src.len;
        if (total == 0) return;

        var staging_buf: vk.VkBuffer = null;
        var staging_mem: vk.VkDeviceMemory = null;
        try vk_device.createBuffer(&self.pipeline, @intCast(total), vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &staging_buf, &staging_mem);
        errdefer vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);

        var map_ptr: ?*anyopaque = null;
        try vk_device.check(vk.vkMapMemory(self.pipeline.ctx.device, staging_mem, 0, @intCast(total), 0, &map_ptr));
        const dst: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);

        var cursor: usize = 0;
        const assignOffsets = struct {
            fn call(d: [*]u8, c: *usize, ops: anytype) void {
                for (ops.items) |*op| {
                    @memcpy(d[c.*..][0..op.src.len], op.src);
                    op.staging_offset = c.*;
                    c.* += op.src.len;
                }
            }
        }.call;
        assignOffsets(dst, &cursor, batch.curve_ops);
        assignOffsets(dst, &cursor, batch.band_ops);
        assignOffsets(dst, &cursor, batch.image_ops);
        assignOffsets(dst, &cursor, batch.layer_info_ops);
        vk.vkUnmapMemory(self.pipeline.ctx.device, staging_mem);

        const transfer = try vk_device.beginTransferCommand(&self.pipeline);
        errdefer vk_device.discardTransferCommand(&self.pipeline, transfer);
        const cmd = transfer.cmd;

        // Transition every touched image once.
        if (batch.curve_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.curve_image, self.layer_count, self.curve_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        if (batch.band_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.band_image, self.layer_count, self.band_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        if (batch.image_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.image_array_image, self.options.max_images, self.image_array_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        if (batch.layer_info_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.layer_info_image, 1, self.layer_info_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

        for (batch.curve_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = op.layer, .layerCount = 1 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        for (batch.band_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = op.layer, .layerCount = 1 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.band_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        for (batch.image_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = op.layer, .layerCount = 1 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.image_array_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        for (batch.layer_info_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
                .imageOffset = vk.VkOffset3D{ .x = 0, .y = @intCast(op.row_base), .z = 0 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.layer_info_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }

        if (batch.curve_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.curve_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
            self.curve_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        }
        if (batch.band_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.band_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
            self.band_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        }
        if (batch.image_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.image_array_image, self.options.max_images, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
            self.image_array_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        }
        if (batch.layer_info_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.layer_info_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
            self.layer_info_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        }

        try vk_device.finishTransferCommand(&self.pipeline, transfer);
        vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
    }

    // ── Slot allocator ──

    fn findFreeBinding(self: *Self) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (!slot.active) return @intCast(i);
        }
        return null;
    }

    fn findSlotByGeneration(self: *const Self, generation: u32) ?u32 {
        for (self.bindings, 0..) |*slot, i| {
            if (slot.active and slot.generation == generation) return @intCast(i);
        }
        return null;
    }

};

const ArrayCopyOp = struct {
    src: []const u8,
    layer: u32,
    width: u32,
    height: u32,
    staging_offset: usize = 0,
};

const LayerInfoCopyOp = struct {
    src: []const u8,
    row_base: u32,
    width: u32,
    height: u32,
    staging_offset: usize = 0,
};

const UploadBatch = struct {
    curve_ops: std.ArrayList(ArrayCopyOp) = .empty,
    band_ops: std.ArrayList(ArrayCopyOp) = .empty,
    image_ops: std.ArrayList(ArrayCopyOp) = .empty,
    layer_info_ops: std.ArrayList(LayerInfoCopyOp) = .empty,

    fn deinit(self: *UploadBatch, allocator: std.mem.Allocator) void {
        self.curve_ops.deinit(allocator);
        self.band_ops.deinit(allocator);
        self.image_ops.deinit(allocator);
        self.layer_info_ops.deinit(allocator);
    }
};

fn countUniqueImages(atlas: *const Atlas) u32 {
    const records = atlas.paint_image_records orelse return 0;
    var seen_count: u32 = 0;
    for (records, 0..) |maybe_rec, i| {
        const rec = maybe_rec orelse continue;
        var duplicate = false;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            const prev = records[j] orelse continue;
            if (prev.image == rec.image) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) seen_count += 1;
    }
    return seen_count;
}

const testing = std.testing;

test "VulkanBackendCache init allocates fixed-capacity slots" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 4,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    const zero_pipeline = PipelineShape{
        .ctx = std.mem.zeroes(VulkanContext),
        .transfer_cmd_pool = null,
        .scheduled_resource_upload_cmd = null,
        .sampler_nearest = null,
        .sampler_linear = null,
        .desc_set_layout = null,
    };
    var cache = try VulkanBackendCache.init(testing.allocator, pool, zero_pipeline, .{
        .max_bindings = 3,
        .layer_info_height = 8,
        .max_images = 2,
        .max_image_width = 32,
        .max_image_height = 32,
    });
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 3), cache.bindings.len);
    try testing.expectEqual(@as(usize, 2), cache.image_storage.len);
    try testing.expectEqual(@as(usize, 1), cache.layer_info_ranges.free.items.len);
    try testing.expectEqual(@as(u32, 8), cache.layer_info_ranges.free.items[0].size);
}
