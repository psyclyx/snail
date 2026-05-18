const std = @import("std");
const vulkan_types = @import("types.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const texture_layers = @import("../../format/texture_layers.zig");
const upload_common = @import("../../format/upload_common.zig");
const snail_mod = @import("../../../root.zig");

pub const vk = vulkan_types.vk;
pub const VulkanContext = vulkan_types.VulkanContext;
pub const CurveAtlas = atlas_curve_mod.CurveAtlas;
pub const AtlasPage = atlas_page_mod.AtlasPage;

pub const AtlasSlot = upload_common.AtlasSlot(CurveAtlas, AtlasPage);
pub const ImageSlot = upload_common.ImageSlot(snail_mod.Image);
pub const AtlasPageUpload = struct {
    page: *const AtlasPage,
    layer: u32,
};

pub fn atlasPagesInBank(slots: []const AtlasSlot, bank_id: u32) u32 {
    var total: u32 = 0;
    for (slots) |slot| {
        const layer_count = @min(slot.uploaded_pages, slot.page_layers.len);
        if (layer_count == 0 and bank_id == 0) {
            total += slot.uploaded_pages;
            continue;
        }
        for (slot.page_layers[0..layer_count]) |layer| {
            if (texture_layers.bank(layer) == bank_id) total += 1;
        }
    }
    return total;
}

pub const UploadStagingBuffer = struct {
    buffer: vk.VkBuffer = null,
    memory: vk.VkDeviceMemory = null,
};

pub const ResourceBank = struct {
    id: u32 = 0,
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
    allocated_layer_count: u32 = 0,
    allocated_image_count: u32 = 0,
    resident_atlas_pages: u32 = 0,
    resident_image_layers: u32 = 0,

    fn hasAny(self: *const ResourceBank) bool {
        return self.curve_image != null or
            self.band_image != null or
            self.layer_image != null or
            self.image_image != null;
    }

    pub fn deinit(self: *ResourceBank, ctx: VulkanContext) void {
        if (self.image_view != null) vk.vkDestroyImageView(ctx.device, self.image_view, null);
        if (self.image_image != null) vk.vkDestroyImage(ctx.device, self.image_image, null);
        if (self.image_memory != null) vk.vkFreeMemory(ctx.device, self.image_memory, null);
        if (self.layer_view != null) vk.vkDestroyImageView(ctx.device, self.layer_view, null);
        if (self.layer_image != null) vk.vkDestroyImage(ctx.device, self.layer_image, null);
        if (self.layer_memory != null) vk.vkFreeMemory(ctx.device, self.layer_memory, null);
        if (self.band_view != null) vk.vkDestroyImageView(ctx.device, self.band_view, null);
        if (self.band_image != null) vk.vkDestroyImage(ctx.device, self.band_image, null);
        if (self.band_memory != null) vk.vkFreeMemory(ctx.device, self.band_memory, null);
        if (self.curve_view != null) vk.vkDestroyImageView(ctx.device, self.curve_view, null);
        if (self.curve_image != null) vk.vkDestroyImage(ctx.device, self.curve_image, null);
        if (self.curve_memory != null) vk.vkFreeMemory(ctx.device, self.curve_memory, null);
        if (self.desc_pool != null) vk.vkDestroyDescriptorPool(ctx.device, self.desc_pool, null);
        self.* = .{};
    }
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    ctx: VulkanContext,
    desc_set_layout: vk.VkDescriptorSetLayout = null,
    desc_pool: vk.VkDescriptorPool = null,
    desc_set: vk.VkDescriptorSet = null,
    active_atlas_bank_id: u32 = 0,
    next_atlas_bank_id: u32 = 1,

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
    atlas_banks: []ResourceBank = &.{},
    atlas_bank_count: usize = 0,

    atlas_slots: []AtlasSlot = &.{},
    atlas_slot_count: usize = 0,
    allocated_curve_height: u32 = 0,
    allocated_band_height: u32 = 0,
    allocated_layer_count: u32 = 0,
    atlas_has_special_text_runs: bool = false,
    image_slots: []ImageSlot = &.{},
    image_slot_count: usize = 0,
    allocated_image_width: u32 = 0,
    allocated_image_height: u32 = 0,
    allocated_image_count: u32 = 0,
    upload_staging: std.ArrayListUnmanaged(UploadStagingBuffer) = .empty,
    generation: u64 = 0,

    pub fn init(ctx: VulkanContext, desc_set_layout: vk.VkDescriptorSetLayout, allocator: std.mem.Allocator) !PreparedResources {
        var self = PreparedResources{ .allocator = allocator, .ctx = ctx, .desc_set_layout = desc_set_layout };
        errdefer self.deinit();

        try self.initDescriptorSet();
        return self;
    }

    pub fn initDescriptorSet(self: *PreparedResources) !void {
        try self.initDescriptorSetInto(&self.desc_pool, &self.desc_set);
    }

    pub fn initDescriptorSetInto(self: *PreparedResources, desc_pool: *vk.VkDescriptorPool, desc_set: *vk.VkDescriptorSet) !void {
        const pool_size = [1]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 4 },
        };
        const dp_info = std.mem.zeroInit(vk.VkDescriptorPoolCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 1,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
        });
        try check(vk.vkCreateDescriptorPool(self.ctx.device, &dp_info, null, desc_pool));
        errdefer {
            if (desc_pool.* != null) vk.vkDestroyDescriptorPool(self.ctx.device, desc_pool.*, null);
            desc_pool.* = null;
        }

        var ds_info: vk.VkDescriptorSetAllocateInfo = std.mem.zeroes(vk.VkDescriptorSetAllocateInfo);
        ds_info.sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        ds_info.descriptorPool = desc_pool.*;
        ds_info.descriptorSetCount = 1;
        ds_info.pSetLayouts = @ptrCast(&self.desc_set_layout);
        try check(vk.vkAllocateDescriptorSets(self.ctx.device, &ds_info, desc_set));
    }

    pub fn deinit(self: *PreparedResources) void {
        self.destroyRetainedUploadStaging();
        self.destroyAtlasTextureResources();
        self.destroyImageResources();
        self.resetAtlasUploadState();
        self.destroyRetainedBanks();
        if (self.desc_pool != null) vk.vkDestroyDescriptorPool(self.ctx.device, self.desc_pool, null);
        self.desc_pool = null;
        self.desc_set = null;
    }

    pub fn retainUploadStaging(self: *PreparedResources, buffer: vk.VkBuffer, memory: vk.VkDeviceMemory) !void {
        try self.upload_staging.append(self.allocator, .{ .buffer = buffer, .memory = memory });
    }

    pub fn destroyRetainedUploadStaging(self: *PreparedResources) void {
        for (self.upload_staging.items) |staging| {
            if (staging.buffer != null) vk.vkDestroyBuffer(self.ctx.device, staging.buffer, null);
            if (staging.memory != null) vk.vkFreeMemory(self.ctx.device, staging.memory, null);
        }
        self.upload_staging.clearAndFree(self.allocator);
    }

    pub fn destroyRetainedBanks(self: *PreparedResources) void {
        for (self.atlas_banks[0..self.atlas_bank_count]) |*bank| bank.deinit(self.ctx);
        if (self.atlas_banks.len > 0) self.allocator.free(self.atlas_banks);
        self.atlas_banks = &.{};
        self.atlas_bank_count = 0;
    }

    pub fn ensureRetainedBankCapacity(self: *PreparedResources, capacity: usize) !void {
        if (capacity <= self.atlas_banks.len) return;
        const next_len = @max(capacity, @max(self.atlas_banks.len * 2, 4));
        const next = try self.allocator.alloc(ResourceBank, next_len);
        @memset(next, ResourceBank{});
        if (self.atlas_bank_count > 0) @memcpy(next[0..self.atlas_bank_count], self.atlas_banks[0..self.atlas_bank_count]);
        if (self.atlas_banks.len > 0) self.allocator.free(self.atlas_banks);
        self.atlas_banks = next;
    }

    pub fn activeBankHasAnyResources(self: *const PreparedResources) bool {
        return self.curve_image != null or
            self.band_image != null or
            self.layer_image != null or
            self.image_image != null;
    }

    pub fn retainActiveBank(self: *PreparedResources) !void {
        if (!self.activeBankHasAnyResources()) return;
        try self.ensureRetainedBankCapacity(self.atlas_bank_count + 1);
        self.atlas_banks[self.atlas_bank_count] = .{
            .id = self.active_atlas_bank_id,
            .desc_pool = self.desc_pool,
            .desc_set = self.desc_set,
            .curve_image = self.curve_image,
            .curve_view = self.curve_view,
            .curve_memory = self.curve_memory,
            .band_image = self.band_image,
            .band_view = self.band_view,
            .band_memory = self.band_memory,
            .layer_image = self.layer_image,
            .layer_view = self.layer_view,
            .layer_memory = self.layer_memory,
            .image_image = self.image_image,
            .image_view = self.image_view,
            .image_memory = self.image_memory,
            .allocated_layer_count = self.allocated_layer_count,
            .allocated_image_count = self.allocated_image_count,
            .resident_atlas_pages = atlasPagesInBank(self.atlas_slots[0..self.atlas_slot_count], self.active_atlas_bank_id),
            .resident_image_layers = @intCast(self.image_slot_count),
        };
        self.atlas_bank_count += 1;
        self.desc_pool = null;
        self.desc_set = null;
        self.curve_image = null;
        self.curve_view = null;
        self.curve_memory = null;
        self.band_image = null;
        self.band_view = null;
        self.band_memory = null;
        self.layer_image = null;
        self.layer_view = null;
        self.layer_memory = null;
        self.image_image = null;
        self.image_view = null;
        self.image_memory = null;
        self.resetImageUploadState();
        self.active_atlas_bank_id = self.next_atlas_bank_id;
        self.next_atlas_bank_id +%= 1;
        try self.initDescriptorSet();
    }

    pub fn bankForId(self: *const PreparedResources, bank_id: u32) ?ResourceBank {
        if (bank_id == self.active_atlas_bank_id) {
            return .{
                .id = self.active_atlas_bank_id,
                .desc_pool = self.desc_pool,
                .desc_set = self.desc_set,
                .curve_image = self.curve_image,
                .curve_view = self.curve_view,
                .curve_memory = self.curve_memory,
                .band_image = self.band_image,
                .band_view = self.band_view,
                .band_memory = self.band_memory,
                .layer_image = self.layer_image,
                .layer_view = self.layer_view,
                .layer_memory = self.layer_memory,
                .image_image = self.image_image,
                .image_view = self.image_view,
                .image_memory = self.image_memory,
                .allocated_layer_count = self.allocated_layer_count,
                .allocated_image_count = self.allocated_image_count,
                .resident_atlas_pages = atlasPagesInBank(self.atlas_slots[0..self.atlas_slot_count], self.active_atlas_bank_id),
                .resident_image_layers = @intCast(self.image_slot_count),
            };
        }
        for (self.atlas_banks[0..self.atlas_bank_count]) |bank| {
            if (bank.id == bank_id) return bank;
        }
        return null;
    }

    pub fn texturesReady(self: *const PreparedResources) bool {
        return self.curve_image != null and self.band_image != null and self.atlas_slot_count > 0;
    }

    pub fn atlasSlotsCompatible(self: *const PreparedResources, atlases: []const *const CurveAtlas) bool {
        return upload_common.atlasSlotsCompatible(self.atlas_slots, self.atlas_slot_count, atlases);
    }

    pub fn atlasPrefixesCompatibleForOverflow(self: *const PreparedResources, atlases: []const *const CurveAtlas) bool {
        return upload_common.atlasPrefixesCompatibleForOverflow(self.atlas_slots, self.atlas_slot_count, atlases);
    }

    pub fn fillAtlasViews(self: *const PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) void {
        upload_common.fillAtlasViews(self.atlas_slots, atlases, out_views);
    }

    pub fn encodeSlotPageLayers(self: *PreparedResources) void {
        upload_common.encodeSlotPageLayers(self.atlas_slots, self.atlas_slot_count, self.active_atlas_bank_id);
    }

    pub fn encodeSlotPageLayersFromStarts(self: *PreparedResources, start_pages: []const u32) void {
        upload_common.encodeSlotPageLayersFromStarts(self.atlas_slots, self.atlas_slot_count, self.active_atlas_bank_id, start_pages);
    }

    pub fn atlasLayerInfoRows(_: *const PreparedResources, atlases: []const *const CurveAtlas) u32 {
        return upload_common.atlasLayerInfoRows(atlases);
    }

    pub fn fillLayerInfoViews(_: *const PreparedResources, row_base_start: u32, layer_infos: anytype, out_views: anytype) void {
        upload_common.fillLayerInfoViews(row_base_start, layer_infos, out_views);
    }

    pub fn currentImageView(self: *const PreparedResources, comptime ImageView: type, image: *const snail_mod.Image) ImageView {
        return upload_common.currentImageView(
            ImageView,
            self.image_slots,
            self.image_slot_count,
            self.allocated_image_width,
            self.allocated_image_height,
            image,
        );
    }

    pub fn findImageSlot(self: *const PreparedResources, image: *const snail_mod.Image) ?usize {
        return upload_common.findImageSlot(self.image_slots, self.image_slot_count, image);
    }

    pub fn ensureAtlasSlotCount(self: *PreparedResources, count: usize) !void {
        if (self.atlas_slots.len == count) return;
        self.resetAtlasUploadState();
        if (count == 0) return;
        self.atlas_slots = try self.allocator.alloc(AtlasSlot, count);
        @memset(self.atlas_slots, AtlasSlot{});
    }

    pub fn ensureSlotPageCapacity(self: *PreparedResources, slot: *AtlasSlot, capacity: u32) !void {
        return upload_common.ensureSlotPageCapacity(self.allocator, slot, capacity);
    }

    pub fn resetAtlasUploadState(self: *PreparedResources) void {
        for (self.atlas_slots) |*slot| slot.deinit(self.allocator);
        if (self.atlas_slots.len > 0) self.allocator.free(self.atlas_slots);
        self.atlas_slots = &.{};
        self.atlas_slot_count = 0;
        self.allocated_curve_height = 0;
        self.allocated_band_height = 0;
        self.allocated_layer_count = 0;
        self.atlas_has_special_text_runs = false;
    }

    pub fn resetImageUploadState(self: *PreparedResources) void {
        self.image_slot_count = 0;
        self.allocated_image_width = 0;
        self.allocated_image_height = 0;
        self.allocated_image_count = 0;
        if (self.image_slots.len > 0) self.allocator.free(self.image_slots);
        self.image_slots = &.{};
    }

    pub fn destroyAtlasTextureResources(self: *PreparedResources) void {
        const had_resources = self.curve_image != null or
            self.band_image != null or
            self.layer_image != null;
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
        if (had_resources) self.generation +%= 1;
    }

    pub fn destroyImageResources(self: *PreparedResources) void {
        const had_resources = self.image_image != null;
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
        self.resetImageUploadState();
        if (had_resources) self.generation +%= 1;
    }
};

fn check(result: vk.VkResult) !void {
    if (result != vk.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}
