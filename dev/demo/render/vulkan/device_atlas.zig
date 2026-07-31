//! Vulkan persistent prepared-pages cache for snail.
//!
//! Mirrors `snail-raster.DeviceAtlas` and `GlDeviceAtlas`:
//! caller-sized capacity, slot allocation via free-list, explicit
//! `release(binding)`, no auto-grow.
//!
//! Per-cache resident GPU state:
//!
//! - `curve_buffer` / `band_buffer` — compact read-only uniform texel
//!   buffers. Curve = `R16G16B16A16_SFLOAT`, band = `R16G16_UINT`.
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
const image_mod = @import("snail");
const vk_types = @import("vulkan_types");
const vk_device = @import("device.zig");
const upload_plan = @import("snail").atlas_upload;

pub const vk = vk_types.vk;
pub const VulkanContext = vk_types.VulkanContext;

pub const Atlas = atlas_mod.Atlas;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const Image = image_mod.Image;

const INFO_WIDTH: u32 = upload_plan.INFO_WIDTH;
const CURVE_WORDS_PER_ROW: u32 = upload_plan.CURVE_TEX_WIDTH * 4;
const BAND_WORDS_PER_ROW: u32 = upload_plan.BAND_TEX_WIDTH * 2;

pub const DeviceAtlasOptions = struct {
    max_bindings: u32 = 16,
    layer_info_height: u32 = 64,
    max_images: u32 = 16,
    max_image_width: u32 = 1024,
    max_image_height: u32 = 1024,
};

pub const UploadError = upload_plan.Error || upload_plan.FlatLayout.Error || std.mem.Allocator.Error || error{
    BindingOutputLengthMismatch,
    ActiveBindingCountOverflow,
    ImageTooLarge,
    NoSuitableMemory,
    IncompleteResourceState,
    RecorderDeviceMismatch,
    UploadSizeOverflow,
    VulkanError,
    VulkanMapMemoryReturnedNull,
};
pub const ResizeError = upload_plan.InitError || upload_plan.FlatLayout.Error || std.mem.Allocator.Error || error{
    ActiveBindingsPreventResize,
    VulkanError,
};

/// Resident-resource creation context. Upload command buffers and staging
/// retirement are deliberately absent; those belong to `UploadRecorder`.
pub const ResourceContext = struct {
    ctx: VulkanContext,
    sampler_nearest: vk.VkSampler,
    sampler_linear: vk.VkSampler,
    desc_set_layout: vk.VkDescriptorSetLayout,
};

/// Caller-owned state for one or more atlas uploads recorded into `cmd`.
/// The command buffer must be recording on a graphics-capable queue family:
/// the emitted barriers make resources immediately vertex/fragment-readable.
/// After the caller submits and observes completion, call `releaseCompleted`.
pub const UploadRecorder = struct {
    allocator: std.mem.Allocator,
    resources: ResourceContext,
    cmd: vk.VkCommandBuffer,
    staging: std.ArrayListUnmanaged(StagingBuffer) = .empty,

    const StagingBuffer = struct {
        buffer: vk.VkBuffer,
        memory: vk.VkDeviceMemory,
    };

    const StagingWrite = struct {
        buffer: vk.VkBuffer,
        memory: vk.VkDeviceMemory,
        bytes: [*]u8,
    };

    pub fn init(allocator: std.mem.Allocator, resources: ResourceContext, cmd: vk.VkCommandBuffer) UploadRecorder {
        std.debug.assert(cmd != null);
        return .{ .allocator = allocator, .resources = resources, .cmd = cmd };
    }

    fn beginStaging(self: *UploadRecorder, byte_len: usize) UploadError!StagingWrite {
        try self.staging.ensureUnusedCapacity(self.allocator, 1);
        var buffer: vk.VkBuffer = null;
        var memory: vk.VkDeviceMemory = null;
        try vk_device.createBuffer(
            &self.resources,
            @intCast(byte_len),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &buffer,
            &memory,
        );
        errdefer vk_device.destroyStagingBuffer(&self.resources, buffer, memory);

        var mapped: ?*anyopaque = null;
        try vk_device.check(vk.vkMapMemory(
            self.resources.ctx.device,
            memory,
            0,
            @intCast(byte_len),
            0,
            &mapped,
        ));
        return .{
            .buffer = buffer,
            .memory = memory,
            .bytes = @ptrCast(mapped orelse {
                vk.vkUnmapMemory(self.resources.ctx.device, memory);
                return error.VulkanMapMemoryReturnedNull;
            }),
        };
    }

    fn retainStaging(self: *UploadRecorder, write: *StagingWrite) void {
        vk.vkUnmapMemory(self.resources.ctx.device, write.memory);
        self.staging.appendAssumeCapacity(.{
            .buffer = write.buffer,
            .memory = write.memory,
        });
        write.buffer = null;
        write.memory = null;
    }

    fn discardStaging(self: *UploadRecorder, write: *StagingWrite) void {
        if (write.memory != null) {
            vk.vkUnmapMemory(self.resources.ctx.device, write.memory);
            vk_device.destroyStagingBuffer(&self.resources, write.buffer, write.memory);
        }
        write.buffer = null;
        write.memory = null;
    }

    /// Destroy staging resources after the caller's completion primitive has
    /// signaled. This function performs no wait and submits nothing.
    pub fn releaseCompleted(self: *UploadRecorder) void {
        for (self.staging.items) |s| {
            vk.vkDestroyBuffer(self.resources.ctx.device, s.buffer, null);
            vk.vkFreeMemory(self.resources.ctx.device, s.memory, null);
        }
        self.staging.clearRetainingCapacity();
    }

    pub fn deinit(self: *UploadRecorder) void {
        std.debug.assert(self.staging.items.len == 0);
        self.staging.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const VulkanDeviceAtlas = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pool: *PagePool,
    options: DeviceAtlasOptions,
    resources: ResourceContext,

    // Pool-wide compact formatted buffers.
    flat: upload_plan.FlatLayout,
    curve_buffer: vk.VkBuffer = null,
    curve_memory: vk.VkDeviceMemory = null,
    curve_view: vk.VkBufferView = null,

    band_buffer: vk.VkBuffer = null,
    band_memory: vk.VkDeviceMemory = null,
    band_view: vk.VkBufferView = null,

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

    // Font-atlas upload planning — caller-owned state (snail.atlas_upload.Planner).
    // The GPU resources + descriptor set stay here; the CPU allocation + region/
    // delta computation is the planner's. Backing slices are cache-owned.
    planner: upload_plan.Planner,
    plan_gen: []u64,
    plan_curve: []u32,
    plan_band: []u32,
    plan_slots: []upload_plan.Slot,
    plan_info_free: []upload_plan.Range,
    plan_image_free: []upload_plan.Range,
    plan_page_rollbacks: []upload_plan.PageRollback,
    plan_regions: []upload_plan.Region,
    // Per-atlas layer_info patch scratch: `max_bindings` slabs of
    // `sizes.layer_info_scratch` f32s, so batched atlases don't clobber each
    // other's patched slab before the flush.
    plan_info_scratch: []f32,
    info_scratch_stride: usize,
    active_bindings: u32 = 0,

    fn plannerOptions(options: DeviceAtlasOptions) upload_plan.Options {
        return .{
            .max_bindings = options.max_bindings,
            .layer_info_height = options.layer_info_height,
            .max_images = options.max_images,
            .max_image_width = options.max_image_width,
            .max_image_height = options.max_image_height,
        };
    }

    fn validateDeviceLimits(ctx: VulkanContext, pool: *const PagePool, options: DeviceAtlasOptions) !void {
        const flat = try upload_plan.FlatLayout.init(pool);
        var props: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(ctx.physical_device, &props);
        if (flat.curve_total_texels > props.limits.maxTexelBufferElements or
            flat.band_total_texels > props.limits.maxTexelBufferElements or
            INFO_WIDTH > props.limits.maxImageDimension2D or
            @max(1, options.layer_info_height) > props.limits.maxImageDimension2D or
            @max(1, options.max_image_width) > props.limits.maxImageDimension2D or
            @max(1, options.max_image_height) > props.limits.maxImageDimension2D or
            @max(1, options.max_images) > props.limits.maxImageArrayLayers)
        {
            return error.InvalidOptions;
        }
        inline for (.{
            vk.VK_FORMAT_R16G16B16A16_SFLOAT,
            vk.VK_FORMAT_R16G16_UINT,
        }) |format| {
            var format_props: vk.VkFormatProperties = undefined;
            vk.vkGetPhysicalDeviceFormatProperties(ctx.physical_device, format, &format_props);
            if (format_props.bufferFeatures & vk.VK_FORMAT_FEATURE_UNIFORM_TEXEL_BUFFER_BIT == 0) {
                return error.InvalidOptions;
            }
        }
        inline for (.{
            vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
        }) |format| {
            var format_props: vk.VkFormatProperties = undefined;
            vk.vkGetPhysicalDeviceFormatProperties(ctx.physical_device, format, &format_props);
            const required = vk.VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT |
                vk.VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
            if (format_props.optimalTilingFeatures & required != required) {
                return error.InvalidOptions;
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool, resources: ResourceContext, options: DeviceAtlasOptions) !Self {
        try validateDeviceLimits(resources.ctx, pool, options);
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
        const page_rollbacks = try allocator.alloc(upload_plan.PageRollback, sz.page_rollbacks);
        errdefer allocator.free(page_rollbacks);
        const regions = try allocator.alloc(upload_plan.Region, sz.regions);
        errdefer allocator.free(regions);
        const info_scratch = try allocator.alloc(f32, info_scratch_len);
        errdefer allocator.free(info_scratch);

        return .{
            .allocator = allocator,
            .pool = pool,
            .options = options,
            .resources = resources,
            .flat = try upload_plan.FlatLayout.init(pool),
            .planner = try upload_plan.Planner.init(pool, opts, gen, curve_words, band_words, slots, info_free, image_free, page_rollbacks),
            .plan_gen = gen,
            .plan_curve = curve_words,
            .plan_band = band_words,
            .plan_slots = slots,
            .plan_info_free = info_free,
            .plan_image_free = image_free,
            .plan_page_rollbacks = page_rollbacks,
            .plan_regions = regions,
            .plan_info_scratch = info_scratch,
            .info_scratch_stride = sz.layer_info_scratch,
        };
    }

    pub fn deinit(self: *Self) void {
        self.destroyGpuResources();
        self.allocator.free(self.plan_gen);
        self.allocator.free(self.plan_curve);
        self.allocator.free(self.plan_band);
        self.allocator.free(self.plan_slots);
        self.allocator.free(self.plan_info_free);
        self.allocator.free(self.plan_page_rollbacks);
        self.allocator.free(self.plan_image_free);
        self.allocator.free(self.plan_regions);
        self.allocator.free(self.plan_info_scratch);
        self.* = undefined;
    }

    // ── Custom-shader resource handles ──
    //
    // Vulkan backends expose the resource views a custom shader needs. They
    // become non-null on the first upload. The texel buffers require no image
    // layout; the sampled images are left shader-readable.

    pub fn curveBufferView(self: *const Self) vk.VkBufferView {
        return self.curve_view;
    }

    pub fn bandBufferView(self: *const Self) vk.VkBufferView {
        return self.band_view;
    }

    /// Fixed page strides consumed by the flat-buffer shader ABI.
    pub fn atlasPageTexels(self: *const Self) [2]i32 {
        return .{
            @intCast(self.flat.curve_page_texels),
            @intCast(self.flat.band_page_texels),
        };
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
        const dev = self.resources.ctx.device;
        if (dev == null) return;

        if (self.desc_pool != null) vk.vkDestroyDescriptorPool(dev, self.desc_pool, null);
        self.desc_pool = null;
        self.desc_set = null;

        if (self.curve_view != null) vk.vkDestroyBufferView(dev, self.curve_view, null);
        if (self.curve_buffer != null) vk.vkDestroyBuffer(dev, self.curve_buffer, null);
        if (self.curve_memory != null) vk.vkFreeMemory(dev, self.curve_memory, null);
        self.curve_view = null;
        self.curve_buffer = null;
        self.curve_memory = null;
        if (self.band_view != null) vk.vkDestroyBufferView(dev, self.band_view, null);
        if (self.band_buffer != null) vk.vkDestroyBuffer(dev, self.band_buffer, null);
        if (self.band_memory != null) vk.vkFreeMemory(dev, self.band_memory, null);
        self.band_view = null;
        self.band_buffer = null;
        self.band_memory = null;

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
        destroy_image(dev, &self.layer_info_view, &self.layer_info_image, &self.layer_info_memory);
        destroy_image(dev, &self.image_array_view, &self.image_array_image, &self.image_array_memory);

        self.layer_info_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
        self.image_array_layout = vk.VK_IMAGE_LAYOUT_UNDEFINED;
    }

    pub fn resize(self: *Self, options: DeviceAtlasOptions) ResizeError!void {
        if (self.active_bindings > 0) return error.ActiveBindingsPreventResize;
        try validateDeviceLimits(self.resources.ctx, self.pool, options);
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
        const new_page_rollbacks = try self.allocator.alloc(upload_plan.PageRollback, sz.page_rollbacks);
        errdefer self.allocator.free(new_page_rollbacks);
        const new_regions = try self.allocator.alloc(upload_plan.Region, sz.regions);
        errdefer self.allocator.free(new_regions);
        const new_info_scratch = try self.allocator.alloc(f32, info_scratch_len);
        errdefer self.allocator.free(new_info_scratch);
        const new_planner = try upload_plan.Planner.init(self.pool, opts, new_gen, new_curve, new_band, new_slots, new_info_free, new_image_free, new_page_rollbacks);

        const old_gen = self.plan_gen;
        const old_curve = self.plan_curve;
        const old_band = self.plan_band;
        const old_slots = self.plan_slots;
        const old_info_free = self.plan_info_free;
        const old_image_free = self.plan_image_free;
        const old_page_rollbacks = self.plan_page_rollbacks;
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
        self.plan_page_rollbacks = new_page_rollbacks;
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
        self.allocator.free(old_page_rollbacks);
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
        return self.resources.desc_set_layout;
    }

    pub fn upload(
        self: *Self,
        recorder: *UploadRecorder,
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
            const records = atlas.paint_records orelse continue;
            for (records) |rec| {
                const image = rec.image orelse continue;
                if (image.width > self.options.max_image_width or image.height > self.options.max_image_height) {
                    return error.ImageTooLarge;
                }
            }
        }

        var batch = UploadBatch{};
        defer batch.deinit(scratch);

        // Roll back planner state if any atlas (or the flush) fails.
        var planned: usize = 0;
        errdefer {
            self.planner.invalidateUploads() catch {};
            for (out_bindings[0..planned]) |b| _ = self.planner.release(b);
        }

        for (atlases, 0..) |atlas, i| {
            var len: usize = 0;
            const info_scratch = self.plan_info_scratch[i * self.info_scratch_stride ..][0..self.info_scratch_stride];
            var pending = try self.planner.plan(atlas, self.plan_regions, &len, info_scratch);
            errdefer self.planner.abort(&pending) catch {};
            try appendRegions(scratch, &batch, pending.regions());
            out_bindings[i] = try self.planner.commit(&pending);
            planned = i + 1;
        }

        try self.ensureGpuResources();
        try self.flushBatch(recorder, &batch);
        self.active_bindings = next_active;
    }

    /// Incrementally update `prev_binding`'s slot with `atlas`'s current
    /// state. Exact snapshots and direct append-only children reuse unchanged
    /// data; other snapshots return `error.IncompatibleSnapshot` and require a
    /// fresh binding. This Vulkan implementation requires all resulting side
    /// data to fit the binding's original row/image reservation and queues the required
    /// curve/band/layer-info/image regions into one `UploadBatch`, and flushes
    /// it before returning.
    pub fn uploadDelta(
        self: *Self,
        recorder: *UploadRecorder,
        scratch: std.mem.Allocator,
        prev_binding: Binding,
        atlas: *const Atlas,
    ) UploadError!Binding {
        if (prev_binding.pool != self.pool) return error.UnknownPool;
        if (!self.isBindingLive(prev_binding)) return error.UnknownBinding;
        if (atlas.pool) |p| {
            if (p != self.pool) return error.UnknownPool;
        }
        if (atlas.paint_records) |records| {
            for (records) |rec| {
                const image = rec.image orelse continue;
                if (image.width > self.options.max_image_width or image.height > self.options.max_image_height) {
                    return error.ImageTooLarge;
                }
            }
        }

        var batch = UploadBatch{};
        defer batch.deinit(scratch);

        var len: usize = 0;
        const info_scratch = self.plan_info_scratch[0..self.info_scratch_stride];
        var pending = try self.planner.planDelta(prev_binding, atlas, self.plan_regions, &len, info_scratch);
        errdefer self.planner.abort(&pending) catch {};
        try appendRegions(scratch, &batch, pending.regions());
        try self.ensureGpuResources();
        try self.flushBatch(recorder, &batch);
        return self.planner.commit(&pending);
    }

    pub fn release(self: *Self, binding: Binding) void {
        if (!self.isBindingLive(binding)) return;
        if (self.planner.release(binding)) {
            if (self.active_bindings > 0) self.active_bindings -= 1;
        }
    }

    // ── Resident resource creation ──

    fn ensureGpuResources(self: *Self) UploadError!void {
        const complete = self.curve_buffer != null and
            self.band_buffer != null and
            self.layer_info_image != null and
            self.image_array_image != null and
            self.desc_pool != null and self.desc_set != null;
        if (complete) return;

        const empty = self.curve_buffer == null and self.band_buffer == null and
            self.layer_info_image == null and self.image_array_image == null and
            self.desc_pool == null and self.desc_set == null;
        if (!empty) return error.IncompleteResourceState;
        errdefer self.destroyGpuResources();

        try self.createPoolBuffers();
        try self.createLayerInfoImage();
        try self.createImageArrayImage();
        try self.createDescriptorSet();
    }

    fn createPoolBuffers(self: *Self) UploadError!void {
        const usage = vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            vk.VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT;
        try vk_device.createBuffer(&self.resources, self.flat.curveByteSize(), usage, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &self.curve_buffer, &self.curve_memory);
        try vk_device.createBuffer(&self.resources, self.flat.bandByteSize(), usage, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &self.band_buffer, &self.band_memory);

        inline for (.{
            .{ &self.curve_view, self.curve_buffer, vk.VK_FORMAT_R16G16B16A16_SFLOAT, self.flat.curveByteSize() },
            .{ &self.band_view, self.band_buffer, vk.VK_FORMAT_R16G16_UINT, self.flat.bandByteSize() },
        }) |item| {
            const info = std.mem.zeroInit(vk.VkBufferViewCreateInfo, .{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO,
                .buffer = item[1],
                .format = item[2],
                .offset = 0,
                .range = item[3],
            });
            try vk_device.check(vk.vkCreateBufferView(self.resources.ctx.device, &info, null, item[0]));
        }
    }

    fn createLayerInfoImage(self: *Self) UploadError!void {
        self.layer_info_image = try vk_device.createImage2D(&self.resources, INFO_WIDTH, @max(1, self.options.layer_info_height), vk.VK_FORMAT_R32G32B32A32_SFLOAT);
        self.layer_info_memory = try vk_device.allocateImageMemory(&self.resources, self.layer_info_image);
        try vk_device.check(vk.vkBindImageMemory(self.resources.ctx.device, self.layer_info_image, self.layer_info_memory, 0));
        self.layer_info_view = try vk_device.createImageView2D(&self.resources, self.layer_info_image, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
    }

    fn createImageArrayImage(self: *Self) UploadError!void {
        self.image_array_image = try vk_device.createImage2DArray(&self.resources, @max(1, self.options.max_image_width), @max(1, self.options.max_image_height), @max(1, self.options.max_images), vk.VK_FORMAT_R8G8B8A8_SRGB);
        self.image_array_memory = try vk_device.allocateImageMemory(&self.resources, self.image_array_image);
        try vk_device.check(vk.vkBindImageMemory(self.resources.ctx.device, self.image_array_image, self.image_array_memory, 0));
        self.image_array_view = try vk_device.createImageView(&self.resources, self.image_array_image, vk.VK_FORMAT_R8G8B8A8_SRGB, @max(1, self.options.max_images));
    }

    fn createDescriptorSet(self: *Self) UploadError!void {
        const dev = self.resources.ctx.device;
        const pool_size = [2]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER, .descriptorCount = 2 },
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 2 },
        };
        const dp_info = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = pool_size.len,
            .pPoolSizes = &pool_size,
        });
        try vk_device.check(vk.vkCreateDescriptorPool(dev, &dp_info, null, &self.desc_pool));

        var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
        ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        ds_info.descriptorPool = self.desc_pool;
        ds_info.descriptorSetCount = 1;
        ds_info.pSetLayouts = @ptrCast(&self.resources.desc_set_layout);
        try vk_device.check(vk.vkAllocateDescriptorSets(dev, &ds_info, &self.desc_set));

        const image_infos = [2]vk.VkDescriptorImageInfo{
            .{ .sampler = self.resources.sampler_nearest, .imageView = self.layer_info_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
            .{ .sampler = self.resources.sampler_linear, .imageView = self.image_array_view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL },
        };
        var texel_views = [2]vk.VkBufferView{ self.curve_view, self.band_view };
        var writes = [4]vk.VkWriteDescriptorSet{
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.desc_set,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
                .pTexelBufferView = &texel_views[0],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.desc_set,
                .dstBinding = 1,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
                .pTexelBufferView = &texel_views[1],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.desc_set,
                .dstBinding = 2,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[0],
            }),
            std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.desc_set,
                .dstBinding = 3,
                .descriptorCount = 1,
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &image_infos[1],
            }),
        };
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
            .curve => try batch.curve_ops.append(scratch, .{ .src = r.src, .page = r.page, .col_base = r.col_base, .row_base = r.row_base, .width = r.width, .height = r.height }),
            .band => try batch.band_ops.append(scratch, .{ .src = r.src, .page = r.page, .col_base = r.col_base, .row_base = r.row_base, .width = r.width, .height = r.height }),
            .image => try batch.image_ops.append(scratch, .{ .src = r.src, .layer = r.layer, .width = r.width, .height = r.height }),
            .layer_info => try batch.layer_info_ops.append(scratch, .{ .src = r.src, .row_base = r.row_base, .width = r.width, .height = r.height }),
        };
    }

    fn flushBatch(self: *Self, recorder: *UploadRecorder, batch: *UploadBatch) UploadError!void {
        if (recorder.resources.ctx.device != self.resources.ctx.device) return error.RecorderDeviceMismatch;
        var total: usize = 0;
        for (batch.curve_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.band_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.image_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        for (batch.layer_info_ops.items) |op| total = std.math.add(usize, total, op.src.len) catch return error.UploadSizeOverflow;
        if (total == 0) return;

        var staging = try recorder.beginStaging(total);
        errdefer recorder.discardStaging(&staging);
        const dst = staging.bytes;

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
        const cmd = recorder.cmd;

        // Transition every touched sampled image once. Curve and band data are
        // buffers, so they only need the transfer→shader memory barrier below.
        if (batch.image_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.image_array_image, @max(1, self.options.max_images), self.image_array_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        if (batch.layer_info_ops.items.len > 0)
            vk_device.transitionImageLayout(cmd, self.layer_info_image, 1, self.layer_info_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);

        for (batch.curve_ops.items) |op| {
            const copy = (try self.flat.translate(.{
                .target = .curve,
                .src = op.src,
                .page = op.page,
                .col_base = op.col_base,
                .row_base = op.row_base,
                .width = op.width,
                .height = op.height,
            })).?;
            const region = vk.VkBufferCopy{
                .srcOffset = @intCast(op.staging_offset),
                .dstOffset = copy.byte_offset,
                .size = @intCast(op.src.len),
            };
            vk.vkCmdCopyBuffer(cmd, staging.buffer, self.curve_buffer, 1, &region);
        }
        for (batch.band_ops.items) |op| {
            const copy = (try self.flat.translate(.{
                .target = .band,
                .src = op.src,
                .page = op.page,
                .col_base = op.col_base,
                .row_base = op.row_base,
                .width = op.width,
                .height = op.height,
            })).?;
            const region = vk.VkBufferCopy{
                .srcOffset = @intCast(op.staging_offset),
                .dstOffset = copy.byte_offset,
                .size = @intCast(op.src.len),
            };
            vk.vkCmdCopyBuffer(cmd, staging.buffer, self.band_buffer, 1, &region);
        }
        for (batch.image_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = op.layer, .layerCount = 1 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging.buffer, self.image_array_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }
        for (batch.layer_info_ops.items) |op| {
            const region = std.mem.zeroInit(vk.VkBufferImageCopy, .{
                .bufferOffset = @as(vk.VkDeviceSize, @intCast(op.staging_offset)),
                .imageSubresource = vk.VkImageSubresourceLayers{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
                .imageOffset = vk.VkOffset3D{ .x = @intCast(op.col_base), .y = @intCast(op.row_base), .z = 0 },
                .imageExtent = vk.VkExtent3D{ .width = op.width, .height = op.height, .depth = 1 },
            });
            vk.vkCmdCopyBufferToImage(cmd, staging.buffer, self.layer_info_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        }

        var buffer_barriers: [2]vk.VkBufferMemoryBarrier = undefined;
        var buffer_barrier_count: u32 = 0;
        if (batch.curve_ops.items.len > 0) {
            buffer_barriers[buffer_barrier_count] = std.mem.zeroInit(vk.VkBufferMemoryBarrier, .{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
                .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .buffer = self.curve_buffer,
                .offset = 0,
                .size = vk.VK_WHOLE_SIZE,
            });
            buffer_barrier_count += 1;
        }
        if (batch.band_ops.items.len > 0) {
            buffer_barriers[buffer_barrier_count] = std.mem.zeroInit(vk.VkBufferMemoryBarrier, .{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
                .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
                .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
                .buffer = self.band_buffer,
                .offset = 0,
                .size = vk.VK_WHOLE_SIZE,
            });
            buffer_barrier_count += 1;
        }
        if (buffer_barrier_count > 0) {
            vk.vkCmdPipelineBarrier(
                cmd,
                vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
                vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                0,
                0,
                null,
                buffer_barrier_count,
                &buffer_barriers,
                0,
                null,
            );
        }
        if (batch.image_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.image_array_image, @max(1, self.options.max_images), vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        }
        if (batch.layer_info_ops.items.len > 0) {
            vk_device.transitionImageLayout(cmd, self.layer_info_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT | vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        }

        if (batch.image_ops.items.len > 0) self.image_array_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (batch.layer_info_ops.items.len > 0) self.layer_info_layout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        recorder.retainStaging(&staging);
    }
};

const ArrayCopyOp = struct {
    src: []const u8,
    page: u32 = 0,
    layer: u32 = 0,
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
        .max_pages = 4,
        .curve_words_per_page = CURVE_WORDS_PER_ROW * 4,
        .band_words_per_page = BAND_WORDS_PER_ROW * 2,
    });
    defer pool.deinit();

    const zero_resources = ResourceContext{
        .ctx = std.mem.zeroes(VulkanContext),
        .sampler_nearest = null,
        .sampler_linear = null,
        .desc_set_layout = null,
    };
    var cache = try VulkanDeviceAtlas.init(testing.allocator, pool, zero_resources, .{
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
    var recorder = UploadRecorder{
        .allocator = testing.allocator,
        .resources = zero_resources,
        .cmd = null,
    };
    defer recorder.deinit();
    try testing.expectError(error.BindingOutputLengthMismatch, cache.upload(&recorder, testing.allocator, &.{}, &unexpected_binding));
    try testing.expectEqual(@as(u32, 0), cache.active_bindings);
}
