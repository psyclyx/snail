//! Vulkan persistent prepared-pages cache for snail.
//!
//! Mirrors `snail-raster.DeviceAtlas` and `GlDeviceAtlas`:
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

const atlas_mod = @import("snail");
const draw_records = @import("snail").render.records;
const page_pool_mod = @import("snail");
const page_mod = @import("snail");
const image_mod = @import("snail");
const vk_types = @import("vulkan_types");
const vk_device = @import("device.zig");
const upload_plan = @import("snail").atlas_upload;

pub const vk = vk_types.vk;
pub const VulkanContext = vk_types.VulkanContext;

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Image = image_mod.Image;

const CURVE_TEX_WIDTH: u32 = upload_plan.CURVE_TEX_WIDTH;
const BAND_TEX_WIDTH: u32 = upload_plan.BAND_TEX_WIDTH;
const CURVE_WORDS_PER_ROW: u32 = CURVE_TEX_WIDTH * 4;
const BAND_WORDS_PER_ROW: u32 = BAND_TEX_WIDTH * 2;
const INFO_WIDTH: u32 = upload_plan.INFO_WIDTH;

pub const DeviceAtlasOptions = struct {
    max_bindings: u32 = 16,
    layer_info_height: u32 = 64,
    max_images: u32 = 16,
    max_image_width: u32 = 1024,
    max_image_height: u32 = 1024,
};

pub const UploadError = upload_plan.Error || std.mem.Allocator.Error || error{
    BindingOutputLengthMismatch,
    ActiveBindingCountOverflow,
    ImageTooLarge,
    MissingCommandBuffer,
    NoSuitableMemory,
    IncompleteResourceState,
    UploadSizeOverflow,
    VulkanError,
    VulkanMapMemoryReturnedNull,
};
pub const ResizeError = upload_plan.InitError || std.mem.Allocator.Error || error{
    ActiveBindingsPreventResize,
    PendingUploadsPreventResize,
    VulkanError,
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

pub const VulkanDeviceAtlas = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: DeviceAtlasOptions,
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

    // Font-atlas upload planning — caller-owned state (snail.AtlasUploadPlanner).
    // The GPU images + descriptor set stay here; the CPU allocation + region/
    // delta computation is the planner's. Backing slices are cache-owned.
    planner: upload_plan.Planner,
    plan_gen: []u64,
    plan_curve: []u32,
    plan_band: []u32,
    plan_slots: []upload_plan.Slot,
    plan_info_free: []upload_plan.Range,
    plan_image_free: []upload_plan.Range,
    plan_regions: []upload_plan.Region,
    // Per-atlas layer_info patch scratch: `max_bindings` slabs of
    // `sizes.layer_info_scratch` f32s, so batched atlases don't clobber each
    // other's patched slab before the flush.
    plan_info_scratch: []f32,
    info_scratch_stride: usize,
    active_bindings: u32 = 0,

    // Staging buffers whose copies were recorded into a caller-provided upload
    // command buffer (queue-decoupled path) and therefore must outlive the
    // caller's submit. Freed by `releaseUploads`.
    pending_staging: std.ArrayListUnmanaged(StagingBuffer) = .empty,

    const StagingBuffer = struct {
        buffer: vk.VkBuffer,
        memory: vk.VkDeviceMemory,
    };

    fn plannerOptions(options: DeviceAtlasOptions) upload_plan.Options {
        return .{
            .max_bindings = options.max_bindings,
            .layer_info_height = options.layer_info_height,
            .max_images = options.max_images,
            .max_image_width = options.max_image_width,
            .max_image_height = options.max_image_height,
        };
    }

    fn validateDeviceLimits(pool: *const PagePool, options: DeviceAtlasOptions) upload_plan.InitError!void {
        const curve_height = pool.options.curve_words_per_page / CURVE_WORDS_PER_ROW;
        const band_height = pool.options.band_words_per_page / BAND_WORDS_PER_ROW;
        if (curve_height > std.math.maxInt(i32) or
            band_height > std.math.maxInt(i32) or
            options.layer_info_height > std.math.maxInt(i32) or
            options.max_image_width > std.math.maxInt(i32) or
            options.max_image_height > std.math.maxInt(i32))
        {
            return error.InvalidOptions;
        }
    }

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, pipeline: PipelineShape, options: DeviceAtlasOptions) !Self {
        try validateDeviceLimits(pool, options);
        const opts = plannerOptions(options);
        const sz = try upload_plan.sizes(pool, opts);
        const info_scratch_len = std.math.mul(usize, sz.layer_info_scratch, options.max_bindings) catch return error.InvalidOptions;

        const gen = try allocator.alloc(u64, sz.generation);
        errdefer allocator.free(gen);
        const curve_words = try allocator.alloc(u32, sz.curve_words);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, sz.band_words);
        errdefer allocator.free(band_words);
        const slots = try allocator.alloc(upload_plan.Slot, sz.bindings);
        errdefer allocator.free(slots);
        const info_free = try allocator.alloc(upload_plan.Range, sz.info_free);
        errdefer allocator.free(info_free);
        const image_free = try allocator.alloc(upload_plan.Range, sz.image_free);
        errdefer allocator.free(image_free);
        const regions = try allocator.alloc(upload_plan.Region, sz.regions);
        errdefer allocator.free(regions);
        const info_scratch = try allocator.alloc(f32, info_scratch_len);
        errdefer allocator.free(info_scratch);

        return .{
            .allocator = allocator,
            .pool = pool,
            .options = options,
            .pipeline = pipeline,
            .planner = try upload_plan.Planner.init(pool, opts, gen, curve_words, band_words, slots, info_free, image_free),
            .plan_gen = gen,
            .plan_curve = curve_words,
            .plan_band = band_words,
            .plan_slots = slots,
            .plan_info_free = info_free,
            .plan_image_free = image_free,
            .plan_regions = regions,
            .plan_info_scratch = info_scratch,
            .info_scratch_stride = sz.layer_info_scratch,
        };
    }

    /// Free staging buffers retained from queue-decoupled uploads. The caller
    /// invokes this after the command buffer it provided (via
    /// `embeddable.cachePipelineShapeCallerUpload`) has finished executing.
    pub fn releaseUploads(self: *Self) void {
        for (self.pending_staging.items) |s| vk_device.destroyStagingBuffer(&self.pipeline, s.buffer, s.memory);
        self.pending_staging.clearRetainingCapacity();
    }

    pub fn deinit(self: *Self) void {
        self.releaseUploads();
        self.pending_staging.deinit(self.allocator);
        self.destroyGpuResources();
        self.allocator.free(self.plan_gen);
        self.allocator.free(self.plan_curve);
        self.allocator.free(self.plan_band);
        self.allocator.free(self.plan_slots);
        self.allocator.free(self.plan_info_free);
        self.allocator.free(self.plan_image_free);
        self.allocator.free(self.plan_regions);
        self.allocator.free(self.plan_info_scratch);
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

    /// Validate the complete cache-issued identity and slot placement.
    pub fn isBindingLive(self: *const Self, binding: Binding) bool {
        if (binding.pool != self.pool or binding.source_id != self.planner.source_id) return false;
        for (self.plan_slots) |slot| {
            if (slot.active and
                slot.generation == binding.generation and
                slot.info_row_base == binding.info_row_base and
                slot.image_layer_base == binding.image_layer_base)
            {
                return true;
            }
        }
        return false;
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

    pub fn resize(self: *Self, options: DeviceAtlasOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;
        if (self.pending_staging.items.len > 0) return error.PendingUploadsPreventResize;
        try validateDeviceLimits(self.pool, options);
        const opts = plannerOptions(options);
        const sz = try upload_plan.sizes(self.pool, opts);
        const info_scratch_len = std.math.mul(usize, sz.layer_info_scratch, options.max_bindings) catch return error.InvalidOptions;

        const new_gen = try self.allocator.alloc(u64, sz.generation);
        errdefer self.allocator.free(new_gen);
        const new_curve = try self.allocator.alloc(u32, sz.curve_words);
        errdefer self.allocator.free(new_curve);
        const new_band = try self.allocator.alloc(u32, sz.band_words);
        errdefer self.allocator.free(new_band);
        const new_slots = try self.allocator.alloc(upload_plan.Slot, sz.bindings);
        errdefer self.allocator.free(new_slots);
        const new_info_free = try self.allocator.alloc(upload_plan.Range, sz.info_free);
        errdefer self.allocator.free(new_info_free);
        const new_image_free = try self.allocator.alloc(upload_plan.Range, sz.image_free);
        errdefer self.allocator.free(new_image_free);
        const new_regions = try self.allocator.alloc(upload_plan.Region, sz.regions);
        errdefer self.allocator.free(new_regions);
        const new_info_scratch = try self.allocator.alloc(f32, info_scratch_len);
        errdefer self.allocator.free(new_info_scratch);
        const new_planner = try upload_plan.Planner.init(self.pool, opts, new_gen, new_curve, new_band, new_slots, new_info_free, new_image_free);

        const old_gen = self.plan_gen;
        const old_curve = self.plan_curve;
        const old_band = self.plan_band;
        const old_slots = self.plan_slots;
        const old_info_free = self.plan_info_free;
        const old_image_free = self.plan_image_free;
        const old_regions = self.plan_regions;
        const old_info_scratch = self.plan_info_scratch;

        self.destroyGpuResources();
        self.options = options;
        self.plan_gen = new_gen;
        self.plan_curve = new_curve;
        self.plan_band = new_band;
        self.plan_slots = new_slots;
        self.plan_info_free = new_info_free;
        self.plan_image_free = new_image_free;
        self.plan_regions = new_regions;
        self.plan_info_scratch = new_info_scratch;
        self.info_scratch_stride = sz.layer_info_scratch;
        self.planner = new_planner;

        self.allocator.free(old_gen);
        self.allocator.free(old_curve);
        self.allocator.free(old_band);
        self.allocator.free(old_slots);
        self.allocator.free(old_info_free);
        self.allocator.free(old_image_free);
        self.allocator.free(old_regions);
        self.allocator.free(old_info_scratch);
    }

    pub fn descriptorSet(self: *const Self) vk.VkDescriptorSet {
        return self.desc_set;
    }

    /// The descriptor-set layout `descriptorSet()` was allocated against. An
    /// embeddable caller builds their `VkPipelineLayout` from this so their
    /// pipeline is compatible with the set snail binds.
    pub fn descriptorSetLayout(self: *const Self) vk.VkDescriptorSetLayout {
        return self.pipeline.desc_set_layout;
    }

    pub fn upload(
        self: *Self,
        scratch: std.mem.Allocator,
        atlases: []const *const Atlas,
        out_bindings: []Binding,
    ) UploadError!void {
        if (atlases.len != out_bindings.len) return error.BindingOutputLengthMismatch;
        const binding_count = std.math.cast(u32, atlases.len) orelse return error.ActiveBindingCountOverflow;
        const next_active = std.math.add(u32, self.active_bindings, binding_count) catch return error.ActiveBindingCountOverflow;
        if (next_active > self.options.max_bindings) return error.NoFreeBinding;

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

        var batch = UploadBatch{};
        defer batch.deinit(scratch);

        // Roll back planner state if any atlas (or the flush) fails.
        var planned: usize = 0;
        errdefer {
            self.planner.invalidateUploads();
            for (out_bindings[0..planned]) |b| _ = self.planner.release(b);
        }

        for (atlases, 0..) |atlas, i| {
            var len: usize = 0;
            const info_scratch = self.plan_info_scratch[i * self.info_scratch_stride ..][0..self.info_scratch_stride];
            out_bindings[i] = try self.planner.plan(atlas, self.plan_regions, &len, info_scratch);
            planned = i + 1;
            try appendRegions(scratch, &batch, self.plan_regions[0..len]);
        }

        try self.ensureGpuResources();
        try self.flushBatch(scratch, &batch);
        self.active_bindings = next_active;
    }

    /// Incrementally update `prev_binding`'s slot with `atlas`'s current
    /// state. Exact snapshots and direct append-only children reuse unchanged
    /// data; branches, skipped descendants, and unrelated same-pool atlases
    /// conservatively replace binding-relative side data. This Vulkan
    /// implementation requires all resulting side data to fit the binding's
    /// original row/image reservation, queues the required
    /// curve/band/layer-info/image regions into one `UploadBatch`, and flushes
    /// it before returning.
    pub fn uploadDelta(
        self: *Self,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        if (prev_binding.pool != self.pool) return error.UnknownPool;
        if (!self.isBindingLive(prev_binding)) return error.UnknownBinding;
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        if (atlas.paint_image_records) |records| {
            for (records) |maybe_rec| {
                const rec = maybe_rec orelse continue;
                if (rec.image.width > self.options.max_image_width or rec.image.height > self.options.max_image_height) {
                    return error.ImageTooLarge;
                }
            }
        }

        var batch = UploadBatch{};
        defer batch.deinit(scratch);

        var len: usize = 0;
        const info_scratch = self.plan_info_scratch[0..self.info_scratch_stride];
        const binding = try self.planner.planDelta(prev_binding, atlas, self.plan_regions, &len, info_scratch);
        errdefer self.planner.invalidateUploads();
        try appendRegions(scratch, &batch, self.plan_regions[0..len]);
        try self.ensureGpuResources();
        try self.flushBatch(scratch, &batch);
        return binding;
    }

    pub fn release(self: *Self, binding: Binding) void {
        if (!self.isBindingLive(binding)) return;
        if (self.planner.release(binding)) {
            if (self.active_bindings > 0) self.active_bindings -= 1;
        }
    }

    // ── Resident image creation ──

    fn ensureGpuResources(self: *Self) UploadError!void {
        const complete = self.curve_image != null and
            self.band_image != null and
            (self.options.layer_info_height == 0 or self.layer_info_image != null) and
            (self.options.max_images == 0 or self.image_array_image != null) and
            self.desc_pool != null and self.desc_set != null;
        if (complete) return;

        const empty = self.curve_image == null and self.band_image == null and
            self.layer_info_image == null and self.image_array_image == null and
            self.desc_pool == null and self.desc_set == null;
        if (!empty) return error.IncompleteResourceState;
        errdefer self.destroyGpuResources();

        try self.createPoolImages();
        if (self.options.layer_info_height > 0) try self.createLayerInfoImage();
        if (self.options.max_images > 0) try self.createImageArrayImage();
        try self.createDescriptorSet();
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
    // The planner yields `Region`s (dirty curve/band layers, layer_info, images);
    // `appendRegions` sorts them into the `UploadBatch` op lists in the same
    // order the old queueBindingData produced, and `flushBatch` packs every
    // source into one staging buffer + one transfer command.

    fn appendRegions(scratch: std.mem.Allocator, batch: *UploadBatch, regions: []const upload_plan.Region) UploadError!void {
        for (regions) |r| switch (r.target) {
            .curve => try batch.curve_ops.append(scratch, .{ .src = r.src, .layer = r.layer, .col_base = r.col_base, .row_base = r.row_base, .width = r.width, .height = r.height }),
            .band => try batch.band_ops.append(scratch, .{ .src = r.src, .layer = r.layer, .col_base = r.col_base, .row_base = r.row_base, .width = r.width, .height = r.height }),
            .image => try batch.image_ops.append(scratch, .{ .src = r.src, .layer = r.layer, .width = r.width, .height = r.height }),
            .layer_info => try batch.layer_info_ops.append(scratch, .{ .src = r.src, .row_base = r.row_base, .width = r.width, .height = r.height }),
        };
    }

    fn flushBatch(self: *Self, _: std.mem.Allocator, batch: *UploadBatch) UploadError!void {
        var total: usize = 0;
        for (batch.curve_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.band_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.image_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.layer_info_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
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
        if (!transfer.owned) try self.pending_staging.ensureUnusedCapacity(self.allocator, 1);
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
                .imageOffset = vk.VkOffset3D{ .x = @intCast(op.col_base), .y = @intCast(op.row_base), .z = 0 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        for (batch.band_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = op.layer, .layerCount = 1 },
                .imageOffset = vk.VkOffset3D{ .x = @intCast(op.col_base), .y = @intCast(op.row_base), .z = 0 },
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
                .imageOffset = vk.VkOffset3D{ .x = @intCast(op.col_base), .y = @intCast(op.row_base), .z = 0 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging_buf, self.layer_info_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }

        if (batch.curve_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.curve_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
        if (batch.band_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.band_image, self.layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
        if (batch.image_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.image_array_image, self.options.max_images, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
        if (batch.layer_info_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.layer_info_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }

        try vk_device.finishTransferCommand(&self.pipeline, transfer);
        if (batch.curve_ops.items.len > 0) self.curve_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (batch.band_ops.items.len > 0) self.band_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (batch.image_ops.items.len > 0) self.image_array_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (batch.layer_info_ops.items.len > 0) self.layer_info_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (transfer.owned) {
            // Owned one-shot: finishTransferCommand already submitted + waited,
            // so the copy is done and the staging buffer is safe to free.
            vk_device.destroyStagingBuffer(&self.pipeline, staging_buf, staging_mem);
        } else {
            // Caller-provided command buffer: the copy hasn't executed yet.
            // Retain the staging buffer until the caller calls releaseUploads.
            self.pending_staging.appendAssumeCapacity(.{ .buffer = staging_buf, .memory = staging_mem });
        }
    }
};

const ArrayCopyOp = struct {
    src: []const u8,
    layer: u32,
    row_base: u32 = 0,
    col_base: u32 = 0,
    width: u32,
    height: u32,
    staging_offset: usize = 0,
};

const LayerInfoCopyOp = struct {
    src: []const u8,
    row_base: u32,
    col_base: u32 = 0,
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

const testing = std.testing;

test "VulkanDeviceAtlas init allocates fixed-capacity slots" {
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
    var cache = try VulkanDeviceAtlas.init(testing.allocator, pool, zero_pipeline, .{
        .max_bindings = 3,
        .layer_info_height = 8,
        .max_images = 2,
        .max_image_width = 32,
        .max_image_height = 32,
    });
    defer cache.deinit();

    // Planner backing is sized from the caller's options (no allocator taken
    // by the planner itself; the cache owns these slices).
    try testing.expectEqual(@as(usize, 3), cache.plan_slots.len);
    try testing.expectEqual(@as(usize, 4), cache.plan_gen.len);

    var unexpected_binding: [1]Binding = undefined;
    try testing.expectError(error.BindingOutputLengthMismatch, cache.upload(testing.allocator, &.{}, &unexpected_binding));
    try testing.expectEqual(@as(u32, 0), cache.active_bindings);
}
