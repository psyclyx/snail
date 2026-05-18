const std = @import("std");
const subpixel_policy = @import("../subpixel_policy.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const texture_layers = @import("../../format/texture_layers.zig");
const upload_common = @import("../../format/upload_common.zig");
const snail_mod = @import("../../../root.zig");
const vulkan_types = @import("types.zig");
const vulkan_resources = @import("resources.zig");
const device = @import("device.zig");

pub const vk = vulkan_types.vk;
const CurveAtlas = atlas_curve_mod.CurveAtlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const ImageSlot = vulkan_resources.ImageSlot;
const AtlasPageUpload = vulkan_resources.AtlasPageUpload;
const ResourceBank = vulkan_resources.ResourceBank;
const retainPage = vulkan_resources.retainPage;
pub const PreparedResources = vulkan_resources.PreparedResources;

/// Use a caller-owned, already-recording command buffer for resource
/// uploads. The caller must submit it; PreparedResources retains staging
/// buffers until the prepared object is retired.
pub fn beginResourceUploadRecording(self: anytype, cmd: anytype) void {
    std.debug.assert(self.scheduled_resource_upload_cmd == null);
    self.scheduled_resource_upload_cmd = @ptrCast(cmd);
}

pub fn endResourceUploadRecording(self: anytype) void {
    self.scheduled_resource_upload_cmd = null;
}

// ── Texture array management ──

pub fn uploadPreparedAtlases(self: anytype, prepared: *PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) !void {
    try uploadPreparedAtlasesWithOptionalCapacityModes(self, prepared, prepared.allocator, atlases, null, out_views);
}

pub fn uploadPreparedAtlasesWithCapacityModes(
    self: anytype,
    prepared: *PreparedResources,
    atlases: []const *const CurveAtlas,
    capacity_modes: []const upload_common.AtlasCapacityMode,
    out_views: anytype,
) !void {
    var layer_infos: [0]EmptyLayerInfoUpload = .{};
    var layer_info_views: [0]EmptyLayerInfoView = .{};
    try uploadPreparedAtlasesAndLayerInfoWithOptionalCapacityModes(self, prepared, prepared.allocator, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
}

pub fn uploadPreparedAtlasesAndLayerInfoWithCapacityModes(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    capacity_modes: []const upload_common.AtlasCapacityMode,
    out_views: anytype,
    layer_infos: anytype,
    out_layer_info_views: anytype,
) !void {
    try uploadPreparedAtlasesAndLayerInfoWithOptionalCapacityModes(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
}

fn uploadPreparedAtlasesWithOptionalCapacityModes(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    capacity_modes: ?[]const upload_common.AtlasCapacityMode,
    out_views: anytype,
) !void {
    var layer_infos: [0]EmptyLayerInfoUpload = .{};
    var layer_info_views: [0]EmptyLayerInfoView = .{};
    try uploadPreparedAtlasesAndLayerInfoWithOptionalCapacityModes(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
}

const EmptyLayerInfoUpload = struct {
    data: ?[]const f32 = null,
    width: u32 = 0,
    height: u32 = 0,
    paint_image_records: ?[]const ?CurveAtlas.PaintImageRecord = null,
};

const EmptyLayerInfoView = struct {
    info_row_base: u32 = 0,
};

fn uploadPreparedAtlasesAndLayerInfoWithOptionalCapacityModes(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    capacity_modes: ?[]const upload_common.AtlasCapacityMode,
    out_views: anytype,
    layer_infos: anytype,
    out_layer_info_views: anytype,
) !void {
    std.debug.assert(atlases.len == out_views.len);
    if (capacity_modes) |modes| std.debug.assert(atlases.len == modes.len);
    std.debug.assert(layer_infos.len == out_layer_info_views.len);

    if (atlases.len == 0 and layer_infos.len == 0) {
        prepared.destroyAtlasTextureResources();
        prepared.resetAtlasUploadState();
        return;
    }

    const simple_atlases = atlasesHaveNoLayerInfoOrImages(atlases);
    const no_active_layer_info = prepared.layer_image == null;
    const can_overflow_bank = layer_infos.len == 0 and simple_atlases and no_active_layer_info and prepared.texturesReady() and prepared.atlasPrefixesCompatibleForOverflow(atlases);
    const can_incremental = layer_infos.len == 0 and simple_atlases and no_active_layer_info and prepared.texturesReady() and prepared.atlasSlotsCompatible(atlases);
    if (!can_incremental and can_overflow_bank) {
        if (!try appendTexturePagesIntoNewBank(self, prepared, scratch, atlases)) {
            try rebuildTextureArrays(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
        } else {
            prepared.fillAtlasViews(atlases, out_views);
            prepared.fillLayerInfoViews(prepared.atlasLayerInfoRows(atlases), layer_infos, out_layer_info_views);
            try ensureAtlasImagesRegistered(self, prepared, scratch, atlases);
            try ensureLayerInfoImagesRegistered(self, prepared, scratch, layer_infos);
            try rebuildLayerInfoTexture(self, prepared, scratch, atlases, layer_infos, out_layer_info_views);
            prepared.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
        }
    } else if (!can_incremental) {
        try rebuildTextureArrays(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
    } else if (!try appendTexturePages(self, prepared, scratch, atlases)) {
        try rebuildTextureArrays(self, prepared, scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
    } else {
        prepared.fillAtlasViews(atlases, out_views);
        prepared.fillLayerInfoViews(prepared.atlasLayerInfoRows(atlases), layer_infos, out_layer_info_views);
        try ensureAtlasImagesRegistered(self, prepared, scratch, atlases);
        try ensureLayerInfoImagesRegistered(self, prepared, scratch, layer_infos);
        try rebuildLayerInfoTexture(self, prepared, scratch, atlases, layer_infos, out_layer_info_views);
        prepared.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
        updateDescriptorSet(self, prepared);
    }
}

pub fn uploadPreparedImages(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image, out_views: anytype) !void {
    std.debug.assert(images.len == out_views.len);
    try ensureImagesRegistered(self, prepared, scratch, images);
    const ImageView = upload_common.BufferElement(@TypeOf(out_views));
    for (images, 0..) |image, i| {
        out_views[i] = prepared.currentImageView(ImageView, image);
    }
    updateDescriptorSet(self, prepared);
}

fn atlasesHaveNoLayerInfoOrImages(atlases: []const *const CurveAtlas) bool {
    return upload_common.atlasesHaveNoLayerInfoOrImages(atlases);
}

fn rebuildTextureArrays(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    capacity_modes: ?[]const upload_common.AtlasCapacityMode,
    out_views: anytype,
    layer_infos: anytype,
    out_layer_info_views: anytype,
) !void {
    try prepared.retainActiveBank();
    prepared.resetAtlasUploadState();

    try prepared.ensureAtlasSlotCount(atlases.len);
    const slot_info = if (capacity_modes) |modes|
        try upload_common.rebuildAtlasSlotsWithCapacityModes(prepared.allocator, prepared.atlas_slots, atlases, modes)
    else
        try upload_common.rebuildAtlasSlots(prepared.allocator, prepared.atlas_slots, atlases);
    prepared.atlas_slot_count = slot_info.atlas_slot_count;
    prepared.allocated_curve_height = slot_info.allocated_curve_height;
    prepared.allocated_band_height = slot_info.allocated_band_height;
    prepared.allocated_layer_count = slot_info.allocated_layer_count;
    prepared.encodeSlotPageLayers();
    prepared.retainAtlasPageRefs();
    prepared.fillLayerInfoViews(slot_info.layer_info_rows, layer_infos, out_layer_info_views);

    const first_atlas = upload_common.firstNonEmptyAtlas(atlases) orelse {
        prepared.fillAtlasViews(atlases, out_views);
        try ensureLayerInfoImagesRegistered(self, prepared, scratch, layer_infos);
        try rebuildLayerInfoTexture(self, prepared, scratch, atlases, layer_infos, out_layer_info_views);
        updateDescriptorSet(self, prepared);
        return;
    };
    const first_page = first_atlas.page(0);
    const curve_w = first_page.curve_width;
    const band_w = first_page.band_width;

    prepared.curve_image = try device.createImage2DArray(self, curve_w, prepared.allocated_curve_height, prepared.allocated_layer_count, vk.VK_FORMAT_R16G16B16A16_SFLOAT);
    prepared.curve_memory = try device.allocateImageMemory(self, prepared.curve_image);
    _ = vk.vkBindImageMemory(self.ctx.device, prepared.curve_image, prepared.curve_memory, 0);

    prepared.band_image = try device.createImage2DArray(self, band_w, prepared.allocated_band_height, prepared.allocated_layer_count, vk.VK_FORMAT_R16G16_UINT);
    prepared.band_memory = try device.allocateImageMemory(self, prepared.band_image);
    _ = vk.vkBindImageMemory(self.ctx.device, prepared.band_image, prepared.band_memory, 0);

    try uploadTextureData(self, prepared, scratch, atlases, null, prepared.allocated_layer_count, vk.VK_IMAGE_LAYOUT_UNDEFINED);

    prepared.curve_view = try device.createImageView(self, prepared.curve_image, vk.VK_FORMAT_R16G16B16A16_SFLOAT, prepared.allocated_layer_count);
    prepared.band_view = try device.createImageView(self, prepared.band_image, vk.VK_FORMAT_R16G16_UINT, prepared.allocated_layer_count);

    try ensureAtlasImagesRegistered(self, prepared, scratch, atlases);
    try ensureLayerInfoImagesRegistered(self, prepared, scratch, layer_infos);
    try rebuildLayerInfoTexture(self, prepared, scratch, atlases, layer_infos, out_layer_info_views);
    prepared.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
    prepared.fillAtlasViews(atlases, out_views);
    updateDescriptorSet(self, prepared);
}

fn appendTexturePages(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !bool {
    var max_curve_h: u32 = prepared.allocated_curve_height;
    var max_band_h: u32 = prepared.allocated_band_height;
    const start_pages = try scratch.alloc(u32, atlases.len);
    defer scratch.free(start_pages);

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
    try uploadTextureData(self, prepared, scratch, atlases, start_pages[0..atlases.len], prepared.allocated_layer_count, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    try upload_common.refreshAtlasSlots(prepared.atlas_slots, atlases);
    prepared.encodeSlotPageLayersFromStarts(start_pages[0..atlases.len]);
    prepared.retainAtlasPageRefsFromStarts(start_pages[0..atlases.len]);
    return true;
}

fn createAtlasTextureBank(
    self: anytype,
    prepared: *PreparedResources,
    first_page: *const AtlasPage,
    layer_count: u32,
    curve_height: u32,
    band_height: u32,
) !ResourceBank {
    var bank = ResourceBank{
        .id = prepared.next_atlas_bank_id,
        .allocated_layer_count = layer_count,
        .resident_atlas_pages = layer_count,
    };
    prepared.next_atlas_bank_id +%= 1;
    errdefer bank.deinit(prepared.ctx);

    try prepared.initDescriptorSetInto(&bank.desc_pool, &bank.desc_set);

    bank.curve_image = try device.createImage2DArray(self, first_page.curve_width, curve_height, layer_count, vk.VK_FORMAT_R16G16B16A16_SFLOAT);
    bank.curve_memory = try device.allocateImageMemory(self, bank.curve_image);
    _ = vk.vkBindImageMemory(self.ctx.device, bank.curve_image, bank.curve_memory, 0);

    bank.band_image = try device.createImage2DArray(self, first_page.band_width, band_height, layer_count, vk.VK_FORMAT_R16G16_UINT);
    bank.band_memory = try device.allocateImageMemory(self, bank.band_image);
    _ = vk.vkBindImageMemory(self.ctx.device, bank.band_image, bank.band_memory, 0);

    return bank;
}

const AtlasAppendPlan = struct {
    first_page: *const AtlasPage,
    layer_count: u32,
    curve_height: u32,
    band_height: u32,
};

fn atlasAppendPlan(prepared: *const PreparedResources, atlases: []const *const CurveAtlas) !?AtlasAppendPlan {
    var page_count_total: usize = 0;
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var first_page: ?*const AtlasPage = null;
    for (atlases, 0..) |atlas, i| {
        const slot = &prepared.atlas_slots[i];
        for (slot.uploaded_pages..atlas.pageCount()) |page_index| {
            const page = atlas.page(@intCast(page_index));
            first_page = first_page orelse page;
            max_curve_h = @max(max_curve_h, page.curve_height);
            max_band_h = @max(max_band_h, page.band_height);
            page_count_total += 1;
        }
    }
    if (page_count_total == 0) return null;
    if (page_count_total > std.math.maxInt(u32)) return error.PreparedResourceCapacityExceeded;
    return .{
        .first_page = first_page.?,
        .layer_count = @intCast(page_count_total),
        .curve_height = upload_common.heightCapacity(max_curve_h),
        .band_height = upload_common.heightCapacity(max_band_h),
    };
}

fn ensureNewBankSlotCapacity(prepared: *PreparedResources, atlases: []const *const CurveAtlas) !void {
    try prepared.ensureRetainedBankCapacity(prepared.atlas_bank_count + 1);
    for (atlases, 0..) |atlas, i| {
        const slot = &prepared.atlas_slots[i];
        const new_pages: u32 = @intCast(atlas.pageCount());
        try prepared.ensureSlotPageCapacity(slot, @max(new_pages, slot.capacity_pages));
    }
}

fn buildNewBankUploads(
    prepared: *const PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    layer_count: u32,
) ![]AtlasPageUpload {
    const uploads = try scratch.alloc(AtlasPageUpload, layer_count);
    errdefer scratch.free(uploads);
    var layer: u32 = 0;
    for (atlases, 0..) |atlas, i| {
        const slot = &prepared.atlas_slots[i];
        for (slot.uploaded_pages..atlas.pageCount()) |page_index| {
            uploads[@intCast(layer)] = .{
                .page = atlas.page(@intCast(page_index)),
                .layer = layer,
            };
            layer += 1;
        }
    }
    return uploads;
}

fn installNewBankPages(prepared: *PreparedResources, atlases: []const *const CurveAtlas, bank_id: u32) void {
    var layer: u32 = 0;
    for (atlases, 0..) |atlas, i| {
        const slot = &prepared.atlas_slots[i];
        const old_pages = slot.uploaded_pages;
        const new_pages: u32 = @intCast(atlas.pageCount());
        for (old_pages..new_pages) |page_index| {
            const page = atlas.page(@intCast(page_index));
            slot.page_ptrs[page_index] = page;
            slot.page_layers[page_index] = texture_layers.inBank(bank_id, layer);
            retainPage(page);
            layer += 1;
        }
        slot.atlas = atlas;
        slot.uploaded_pages = new_pages;
    }
}

fn appendTexturePagesIntoNewBank(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !bool {
    const plan = (try atlasAppendPlan(prepared, atlases)) orelse return true;
    try ensureNewBankSlotCapacity(prepared, atlases);
    const uploads = try buildNewBankUploads(prepared, scratch, atlases, plan.layer_count);
    defer scratch.free(uploads);

    var bank = try createAtlasTextureBank(
        self,
        prepared,
        plan.first_page,
        plan.layer_count,
        plan.curve_height,
        plan.band_height,
    );
    errdefer bank.deinit(prepared.ctx);

    try uploadPageDataToImages(
        self,
        prepared,
        scratch,
        uploads,
        bank.curve_image,
        bank.band_image,
        bank.allocated_layer_count,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
    );

    bank.curve_view = try device.createImageView(self, bank.curve_image, vk.VK_FORMAT_R16G16B16A16_SFLOAT, bank.allocated_layer_count);
    bank.band_view = try device.createImageView(self, bank.band_image, vk.VK_FORMAT_R16G16_UINT, bank.allocated_layer_count);
    updateDescriptorSetViews(self, bank.desc_set, bank.curve_view, bank.band_view, null, null);

    installNewBankPages(prepared, atlases, bank.id);
    prepared.atlas_banks[prepared.atlas_bank_count] = bank;
    prepared.atlas_bank_count += 1;
    return true;
}

fn ensureAtlasImagesRegistered(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !void {
    var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
    defer images.deinit(scratch);
    try upload_common.collectAtlasImages(scratch, prepared.image_slots, prepared.image_slot_count, atlases, &images);
    try ensureImagesRegistered(self, prepared, scratch, images.items);
}

fn ensureLayerInfoImagesRegistered(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, layer_infos: anytype) !void {
    var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
    defer images.deinit(scratch);
    for (layer_infos) |info| {
        const records = info.paint_image_records orelse continue;
        for (records) |record| {
            const image = (record orelse continue).image;
            if (prepared.findImageSlot(image) != null) continue;
            var already_queued = false;
            for (images.items) |queued| {
                if (queued == image) {
                    already_queued = true;
                    break;
                }
            }
            if (!already_queued) try images.append(scratch, image);
        }
    }
    try ensureImagesRegistered(self, prepared, scratch, images.items);
}

fn ensureImageSlotCapacity(prepared: *PreparedResources, capacity: usize) !void {
    if (capacity <= prepared.image_slots.len) return;
    const next = try prepared.allocator.alloc(ImageSlot, capacity);
    @memset(next, ImageSlot{});
    if (prepared.image_slot_count > 0) @memcpy(next[0..prepared.image_slot_count], prepared.image_slots[0..prepared.image_slot_count]);
    if (prepared.image_slots.len > 0) prepared.allocator.free(prepared.image_slots);
    prepared.image_slots = next;
}

fn ensureImagesRegistered(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image) !void {
    if (images.len == 0) return;

    var target_images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
    defer target_images.deinit(scratch);
    var new_images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
    defer new_images.deinit(scratch);
    var required_width = prepared.allocated_image_width;
    var required_height = prepared.allocated_image_height;
    for (images) |image| {
        required_width = @max(required_width, image.width);
        required_height = @max(required_height, image.height);
        var target_seen = false;
        for (target_images.items) |queued| {
            if (queued == image) {
                target_seen = true;
                break;
            }
        }
        if (!target_seen) try target_images.append(scratch, image);
        if (prepared.findImageSlot(image) != null) continue;
        var already_queued = false;
        for (new_images.items) |queued| {
            if (queued == image) {
                already_queued = true;
                break;
            }
        }
        if (!already_queued) try new_images.append(scratch, image);
    }

    if (new_images.items.len == 0 and prepared.image_image != null) return;

    try ensureImageSlotCapacity(prepared, prepared.image_slot_count + new_images.items.len);

    const required_count: u32 = @intCast(prepared.image_slot_count + new_images.items.len);
    const new_width = upload_common.imageExtentCapacity(required_width);
    const new_height = upload_common.imageExtentCapacity(required_height);
    const needs_rebuild = prepared.image_image == null or
        required_count > prepared.allocated_image_count or
        new_width > prepared.allocated_image_width or
        new_height > prepared.allocated_image_height;

    if (needs_rebuild) {
        if (prepared.image_image != null) try prepared.retainActiveBank();
        try ensureImageSlotCapacity(prepared, target_images.items.len);
        for (target_images.items, 0..) |image, i| {
            prepared.image_slots[i] = .{ .image = image };
        }
        prepared.image_slot_count = target_images.items.len;
        try rebuildImageArray(self, prepared, scratch);
        return;
    }

    for (new_images.items, 0..) |image, i| {
        prepared.image_slots[prepared.image_slot_count + i] = .{ .image = image };
    }
    try uploadImagesToArray(self, prepared, scratch, new_images.items, @intCast(prepared.image_slot_count), vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    prepared.image_slot_count += new_images.items.len;
}

fn rebuildLayerInfoTexture(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas, layer_infos: anytype, layer_info_views: anytype) !void {
    const had_layer_info = prepared.layer_image != null;
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
    if (had_layer_info) prepared.generation +%= 1;

    var total_rows: u32 = 0;
    for (atlases) |atlas| total_rows += atlas.layer_info_height;
    for (layer_infos) |info| total_rows += info.height;
    if (total_rows == 0) return;

    var width = upload_common.maxLayerInfoWidth(atlases);
    for (layer_infos) |info| {
        if (info.height > 0 and info.width > width) width = info.width;
    }
    const total_texels = @as(usize, width) * @as(usize, total_rows) * 4;
    const data = try scratch.alloc(f32, total_texels);
    defer scratch.free(data);
    @memset(data, 0);

    const ImagePatchView = struct {
        image: *const snail_mod.Image,
        layer: u32 = 0,
        uv_scale: snail_mod.Vec2 = .{ .x = 1.0, .y = 1.0 },
    };
    for (atlases, 0..) |atlas, i| {
        const lid = atlas.layer_info_data orelse continue;
        const row_base = prepared.atlas_slots[i].info_row_base;
        const row_count = atlas.layer_info_height;
        upload_common.copyLayerInfoRows(data, width, row_base, lid, atlas.layer_info_width, row_count);

        const records = atlas.paint_image_records orelse continue;
        for (records) |record| {
            const paint = record orelse continue;
            upload_common.patchImagePaintRecord(data, width, atlas.layer_info_width, row_base, paint.texel_offset, prepared.currentImageView(ImagePatchView, paint.image));
        }
    }
    for (layer_infos, 0..) |info, i| {
        const lid = info.data orelse continue;
        const row_base = layer_info_views[i].info_row_base;
        upload_common.copyLayerInfoRows(data, width, row_base, lid, info.width, info.height);

        const records = info.paint_image_records orelse continue;
        for (records) |record| {
            const paint = record orelse continue;
            upload_common.patchImagePaintRecord(data, width, info.width, row_base, paint.texel_offset, prepared.currentImageView(ImagePatchView, paint.image));
        }
    }

    prepared.layer_image = try device.createImage2D(self, width, total_rows, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
    prepared.layer_memory = try device.allocateImageMemory(self, prepared.layer_image);
    _ = vk.vkBindImageMemory(self.ctx.device, prepared.layer_image, prepared.layer_memory, 0);
    try uploadLayerInfoData(self, prepared, data, width, total_rows);
    prepared.layer_view = try device.createImageView2D(self, prepared.layer_image, vk.VK_FORMAT_R32G32B32A32_SFLOAT);
}

fn updateDescriptorSet(self: anytype, prepared: *PreparedResources) void {
    updateDescriptorSetViews(self, prepared.desc_set, prepared.curve_view, prepared.band_view, prepared.layer_view, prepared.image_view);
}

fn updateDescriptorSetViews(
    self: anytype,
    desc_set: vk.VkDescriptorSet,
    curve_view: vk.VkImageView,
    band_view: vk.VkImageView,
    layer_view: vk.VkImageView,
    image_view: vk.VkImageView,
) void {
    const effective_layer_view = if (layer_view != null) layer_view else curve_view;
    const effective_image_view = if (image_view != null) image_view else curve_view;
    const image_infos = [4]vk.VkDescriptorImageInfo{
        .{
            .sampler = self.sampler_nearest,
            .imageView = curve_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        },
        .{
            .sampler = self.sampler_nearest,
            .imageView = band_view,
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
        std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = desc_set,
            .dstBinding = 2,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_infos[2],
        }),
        std.mem.zeroInit(vk.VkWriteDescriptorSet, .{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = desc_set,
            .dstBinding = 3,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &image_infos[3],
        }),
    };
    vk.vkUpdateDescriptorSets(self.ctx.device, 4, &writes, 0, null);
}

// ── Draw ──

fn uploadTextureData(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    atlases: []const *const CurveAtlas,
    start_pages: ?[]const u32,
    layer_count: u32,
    old_layout: vk.VkImageLayout,
) !void {
    var upload_count: u32 = 0;
    for (atlases, 0..) |atlas, i| {
        const start_page = if (start_pages) |sp| sp[i] else 0;
        upload_count += @intCast(atlas.pageCount() - start_page);
    }
    if (upload_count == 0) return;

    const uploads = try scratch.alloc(AtlasPageUpload, upload_count);
    defer scratch.free(uploads);

    var upload_index: usize = 0;
    for (atlases, 0..) |atlas, i| {
        const start_page = if (start_pages) |sp| sp[i] else 0;
        const base_layer = prepared.atlas_slots[i].base_layer;
        for (start_page..atlas.pageCount()) |page_index| {
            uploads[upload_index] = .{
                .page = atlas.page(@intCast(page_index)),
                .layer = base_layer + @as(u32, @intCast(page_index)),
            };
            upload_index += 1;
        }
    }

    try uploadPageDataToImages(
        self,
        prepared,
        scratch,
        uploads,
        prepared.curve_image,
        prepared.band_image,
        layer_count,
        old_layout,
    );
}

const MappedUploadStaging = struct {
    buffer: vk.VkBuffer,
    memory: vk.VkDeviceMemory,
    data: [*]u8,
};

fn atlasUploadStagingByteCount(uploads: []const AtlasPageUpload) usize {
    const curve_px_bytes: usize = 4 * 2; // RGBA16F = 4 channels * 2 bytes
    const band_px_bytes: usize = 2 * 2; // RG16UI = 2 channels * 2 bytes
    var total: usize = 0;
    for (uploads) |upload| {
        const page = upload.page;
        total += @as(usize, page.curve_width) * @as(usize, page.curve_height) * curve_px_bytes;
        total += @as(usize, page.band_width) * @as(usize, page.band_height) * band_px_bytes;
    }
    return total;
}

fn createMappedUploadStaging(self: anytype, total_staging: usize) !MappedUploadStaging {
    var staging_buf: vk.VkBuffer = null;
    var staging_mem: vk.VkDeviceMemory = null;
    try device.createBuffer(
        self,
        @intCast(total_staging),
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &staging_buf,
        &staging_mem,
    );
    errdefer device.destroyStagingBuffer(self, staging_buf, staging_mem);

    var map_ptr: ?*anyopaque = null;
    try device.check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, @intCast(total_staging), 0, &map_ptr));
    const data: [*]u8 = @ptrCast(map_ptr orelse {
        vk.vkUnmapMemory(self.ctx.device, staging_mem);
        return error.VulkanMapMemoryReturnedNull;
    });
    return .{ .buffer = staging_buf, .memory = staging_mem, .data = data };
}

fn imageCopyRegion(buffer_offset: usize, layer: u32, width: u32, height: u32) vk.VkBufferImageCopy {
    var region: vk.VkBufferImageCopy = std.mem.zeroes(vk.VkBufferImageCopy);
    region.bufferOffset = @intCast(buffer_offset);
    region.imageSubresource.aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.baseArrayLayer = layer;
    region.imageSubresource.layerCount = 1;
    region.imageExtent = .{ .width = width, .height = height, .depth = 1 };
    return region;
}

fn writeAtlasPageUploadRegions(
    staging_data: [*]u8,
    uploads: []const AtlasPageUpload,
    curve_regions: []vk.VkBufferImageCopy,
    band_regions: []vk.VkBufferImageCopy,
) void {
    const curve_px_bytes: usize = 4 * 2;
    const band_px_bytes: usize = 2 * 2;
    var staging_offset: usize = 0;

    for (uploads, 0..) |upload, region_index| {
        const page = upload.page;
        const layer = upload.layer;

        const curve_size = @as(usize, page.curve_width) * @as(usize, page.curve_height) * curve_px_bytes;
        const curve_bytes: [*]const u8 = @ptrCast(page.curve_data.ptr);
        @memcpy(staging_data[staging_offset..][0..curve_size], curve_bytes[0..curve_size]);
        curve_regions[region_index] = imageCopyRegion(staging_offset, layer, page.curve_width, page.curve_height);
        staging_offset += curve_size;

        const band_size = @as(usize, page.band_width) * @as(usize, page.band_height) * band_px_bytes;
        const band_bytes: [*]const u8 = @ptrCast(page.band_data.ptr);
        @memcpy(staging_data[staging_offset..][0..band_size], band_bytes[0..band_size]);
        band_regions[region_index] = imageCopyRegion(staging_offset, layer, page.band_width, page.band_height);
        staging_offset += band_size;
    }
}

fn submitAtlasPageUpload(
    self: anytype,
    prepared: *PreparedResources,
    staging: MappedUploadStaging,
    curve_image: vk.VkImage,
    band_image: vk.VkImage,
    layer_count: u32,
    old_layout: vk.VkImageLayout,
    curve_regions: []const vk.VkBufferImageCopy,
    band_regions: []const vk.VkBufferImageCopy,
) !void {
    const region_count: u32 = @intCast(curve_regions.len);
    const transfer = try device.beginTransferCommand(self);
    var transfer_finished = false;
    errdefer if (!transfer_finished) device.discardTransferCommand(self, transfer);
    const cmd = transfer.cmd;

    device.transitionImageLayout(cmd, curve_image, layer_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    device.transitionImageLayout(cmd, band_image, layer_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    vk.vkCmdCopyBufferToImage(cmd, staging.buffer, curve_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, region_count, curve_regions.ptr);
    vk.vkCmdCopyBufferToImage(cmd, staging.buffer, band_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, region_count, band_regions.ptr);

    device.transitionImageLayout(cmd, curve_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    device.transitionImageLayout(cmd, band_image, layer_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    try device.finishTransferCommand(self, transfer);
    transfer_finished = true;
    try device.finishUploadStaging(self, prepared, staging.buffer, staging.memory);
}

fn uploadPageDataToImages(
    self: anytype,
    prepared: *PreparedResources,
    scratch: std.mem.Allocator,
    uploads: []const AtlasPageUpload,
    curve_image: vk.VkImage,
    band_image: vk.VkImage,
    layer_count: u32,
    old_layout: vk.VkImageLayout,
) !void {
    if (uploads.len == 0) return;
    const region_count: u32 = @intCast(uploads.len);
    const staging = try createMappedUploadStaging(self, atlasUploadStagingByteCount(uploads));
    var staging_owned = true;
    var staging_mapped = true;
    errdefer if (staging_owned) device.destroyStagingBuffer(self, staging.buffer, staging.memory);
    errdefer if (staging_mapped) vk.vkUnmapMemory(self.ctx.device, staging.memory);

    // Record one VkBufferImageCopy per (atlas page, image), sized to the
    // total page count discovered above. Static arrays would silently
    // overflow when many fonts/atlases are uploaded together.
    const curve_regions = try scratch.alloc(vk.VkBufferImageCopy, region_count);
    defer scratch.free(curve_regions);
    const band_regions = try scratch.alloc(vk.VkBufferImageCopy, region_count);
    defer scratch.free(band_regions);
    writeAtlasPageUploadRegions(staging.data, uploads, curve_regions, band_regions);

    vk.vkUnmapMemory(self.ctx.device, staging.memory);
    staging_mapped = false;
    try submitAtlasPageUpload(self, prepared, staging, curve_image, band_image, layer_count, old_layout, curve_regions, band_regions);
    staging_owned = false;
}

fn uploadLayerInfoData(self: anytype, prepared: *PreparedResources, data: []f32, width: u32, height: u32) !void {
    const px_bytes: usize = 4 * 4; // RGBA32F = 4 channels * 4 bytes
    const total_bytes: vk.VkDeviceSize = @intCast(@as(usize, width) * @as(usize, height) * px_bytes);

    var staging_buf: vk.VkBuffer = null;
    var staging_mem: vk.VkDeviceMemory = null;
    try device.createBuffer(self, total_bytes, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &staging_buf, &staging_mem);
    errdefer device.destroyStagingBuffer(self, staging_buf, staging_mem);

    var map_ptr: ?*anyopaque = null;
    try device.check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, total_bytes, 0, &map_ptr));
    const dst: [*]u8 = @ptrCast(map_ptr);
    const src: [*]const u8 = @ptrCast(data.ptr);
    @memcpy(dst[0..@intCast(total_bytes)], src[0..@intCast(total_bytes)]);
    vk.vkUnmapMemory(self.ctx.device, staging_mem);

    const transfer = try device.beginTransferCommand(
        self,
    );
    var transfer_finished = false;
    errdefer if (!transfer_finished) device.discardTransferCommand(self, transfer);
    const cmd = transfer.cmd;

    device.transitionImageLayout(cmd, prepared.layer_image, 1, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

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

    device.transitionImageLayout(cmd, prepared.layer_image, 1, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    try device.finishTransferCommand(self, transfer);
    transfer_finished = true;
    try device.finishUploadStaging(self, prepared, staging_buf, staging_mem);
}

fn rebuildImageArray(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator) !void {
    const had_image = prepared.image_image != null;
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
    if (had_image) prepared.generation +%= 1;

    if (prepared.image_slot_count == 0) {
        prepared.allocated_image_width = 0;
        prepared.allocated_image_height = 0;
        prepared.allocated_image_count = 0;
        return;
    }

    var max_width: u32 = 1;
    var max_height: u32 = 1;
    const all_images = try scratch.alloc(*const snail_mod.Image, prepared.image_slot_count);
    defer scratch.free(all_images);
    var image_count: usize = 0;
    for (prepared.image_slots[0..prepared.image_slot_count]) |slot| {
        const image = slot.image orelse continue;
        all_images[image_count] = image;
        image_count += 1;
        max_width = @max(max_width, image.width);
        max_height = @max(max_height, image.height);
    }

    prepared.allocated_image_width = upload_common.imageExtentCapacity(max_width);
    prepared.allocated_image_height = upload_common.imageExtentCapacity(max_height);
    prepared.allocated_image_count = upload_common.imageCapacity(@intCast(prepared.image_slot_count));

    prepared.image_image = try device.createImage2DArray(self, prepared.allocated_image_width, prepared.allocated_image_height, prepared.allocated_image_count, vk.VK_FORMAT_R8G8B8A8_SRGB);
    prepared.image_memory = try device.allocateImageMemory(self, prepared.image_image);
    _ = vk.vkBindImageMemory(self.ctx.device, prepared.image_image, prepared.image_memory, 0);
    try uploadImagesToArray(self, prepared, scratch, all_images[0..image_count], 0, vk.VK_IMAGE_LAYOUT_UNDEFINED);
    prepared.image_view = try device.createImageView(self, prepared.image_image, vk.VK_FORMAT_R8G8B8A8_SRGB, prepared.allocated_image_count);
}

fn uploadImagesToArray(self: anytype, prepared: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image, start_layer: u32, old_layout: vk.VkImageLayout) !void {
    if (images.len == 0 or prepared.image_image == null) return;

    var total_staging: usize = 0;
    for (images) |image| total_staging += @as(usize, image.width) * @as(usize, image.height) * 4;

    var staging_buf: vk.VkBuffer = null;
    var staging_mem: vk.VkDeviceMemory = null;
    try device.createBuffer(
        self,
        @intCast(total_staging),
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &staging_buf,
        &staging_mem,
    );
    errdefer device.destroyStagingBuffer(self, staging_buf, staging_mem);

    var map_ptr: ?*anyopaque = null;
    try device.check(vk.vkMapMemory(self.ctx.device, staging_mem, 0, @intCast(total_staging), 0, &map_ptr));
    const staging_data: [*]u8 = @ptrCast(map_ptr orelse return error.VulkanMapMemoryReturnedNull);

    const regions = try scratch.alloc(vk.VkBufferImageCopy, images.len);
    defer scratch.free(regions);
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

    const transfer = try device.beginTransferCommand(
        self,
    );
    var transfer_finished = false;
    errdefer if (!transfer_finished) device.discardTransferCommand(self, transfer);
    const cmd = transfer.cmd;

    device.transitionImageLayout(cmd, prepared.image_image, prepared.allocated_image_count, old_layout, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    vk.vkCmdCopyBufferToImage(cmd, staging_buf, prepared.image_image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, @intCast(images.len), regions.ptr);
    device.transitionImageLayout(cmd, prepared.image_image, prepared.allocated_image_count, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    try device.finishTransferCommand(self, transfer);
    transfer_finished = true;
    try device.finishUploadStaging(self, prepared, staging_buf, staging_mem);
}
