const std = @import("std");

const atlas_page_mod = @import("../renderer/atlas/page.zig");
const prepared_mod = @import("../resources/prepared.zig");
const resource_key_mod = @import("../resource_key.zig");
const set_mod = @import("../resources/set.zig");
const stamp_mod = @import("../resources/stamp.zig");
const upload_mod = @import("../upload.zig");

const AtlasPage = atlas_page_mod.AtlasPage;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceSet = set_mod.ResourceSet;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;

const PreparedAtlasResource = PreparedResources.PreparedAtlasResource;
const PreparedImageResource = PreparedResources.PreparedImageResource;
const PreparedLayerInfoResource = PreparedResources.PreparedLayerInfoResource;

const resourceEntryKey = stamp_mod.resourceEntryKey;
const resourceEntryStamp = stamp_mod.resourceEntryStamp;
const resourceEntryUploadBytes = stamp_mod.resourceEntryUploadBytes;

pub const AtlasRef = struct {
    ptr: *const anyopaque,
    page_count: *const fn (*const anyopaque) usize,
    page_at: *const fn (*const anyopaque, usize) *const AtlasPage,
    has_layer_info_or_images: bool,

    pub fn init(atlas: anytype) AtlasRef {
        const Atlas = switch (@typeInfo(@TypeOf(atlas))) {
            .pointer => |ptr| ptr.child,
            else => @TypeOf(atlas),
        };
        const S = struct {
            fn pageCount(ptr: *const anyopaque) usize {
                const typed: *const Atlas = @ptrCast(@alignCast(ptr));
                return typed.pageCount();
            }

            fn pageAt(ptr: *const anyopaque, page_index: usize) *const AtlasPage {
                const typed: *const Atlas = @ptrCast(@alignCast(ptr));
                return typed.page(@intCast(page_index));
            }
        };
        return .{
            .ptr = @ptrCast(atlas),
            .page_count = &S.pageCount,
            .page_at = &S.pageAt,
            .has_layer_info_or_images = atlasHasLayerInfoOrImages(atlas),
        };
    }

    pub fn pageCount(self: AtlasRef) usize {
        return self.page_count(self.ptr);
    }

    pub fn page(self: AtlasRef, page_index: usize) *const AtlasPage {
        return self.page_at(self.ptr, page_index);
    }
};

const AtlasUploadDelta = struct {
    reused_pages: u32 = 0,
    missing_pages: u32 = 0,
    curve_bytes: usize = 0,
    band_bytes: usize = 0,
};

const ResourceSetCounts = struct {
    atlases: usize = 0,
    layer_infos: usize = 0,
    images: usize = 0,
};

const PreparedAtlasLookup = struct {
    index: usize,
};

fn countResourceSetEntries(set: *const ResourceSet) ResourceSetCounts {
    var counts: ResourceSetCounts = .{};
    for (set.slice()) |entry| switch (entry) {
        .text_atlas, .path_picture => counts.atlases += 1,
        .text_paint => counts.layer_infos += 1,
        .image => counts.images += 1,
    };
    return counts;
}

fn preparedAtlasForKey(prepared: *const PreparedResources, key: ResourceKey) ?*const PreparedAtlasResource {
    for (prepared.atlases) |*entry| if (entry.key.eql(key)) return entry;
    return null;
}

fn preparedAtlasForKeyWithIndex(prepared: *const PreparedResources, key: ResourceKey) ?PreparedAtlasLookup {
    for (prepared.atlases, 0..) |*entry, i| {
        if (entry.key.eql(key)) return .{ .index = i };
    }
    return null;
}

fn preparedLayerInfoForKey(prepared: *const PreparedResources, key: ResourceKey) ?*const PreparedLayerInfoResource {
    for (prepared.layer_infos) |*entry| if (entry.key.eql(key)) return entry;
    return null;
}

fn preparedImageForKey(prepared: *const PreparedResources, key: ResourceKey) ?*const PreparedImageResource {
    for (prepared.images) |*entry| if (entry.key.eql(key)) return entry;
    return null;
}

fn atlasUploadDelta(current: ?*const PreparedResources, key: ResourceKey, atlas: AtlasRef) AtlasUploadDelta {
    var out: AtlasUploadDelta = .{};
    const old = if (current) |prepared| preparedAtlasForKey(prepared, key) else null;
    const old_atlas = if (old) |entry| entry.atlas else null;
    for (0..atlas.pageCount()) |page_index| {
        const page = atlas.page(page_index);
        const reused = if (old_atlas) |prev|
            page_index < prev.pageCount() and prev.page(@intCast(page_index)) == page
        else
            false;
        if (reused) {
            out.reused_pages += 1;
        } else {
            out.missing_pages += 1;
            out.curve_bytes += page.curveTextureBytes();
            out.band_bytes += page.bandTextureBytes();
        }
    }
    return out;
}

pub fn atlasSlotWouldRebuild(slot: anytype, allocated_curve_height: u32, allocated_band_height: u32, atlas: AtlasRef) bool {
    if (atlas.pageCount() > std.math.maxInt(u16)) return true;
    const page_count: u32 = @intCast(atlas.pageCount());
    if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return true;
    if (slot.uploaded_pages > slot.page_ptrs.len) return true;
    for (0..slot.uploaded_pages) |page_index| {
        if (slot.page_ptrs[page_index] != atlas.page(page_index)) return true;
    }
    for (0..page_count) |page_index| {
        const page = atlas.page(page_index);
        if (page.curve_height > allocated_curve_height) return true;
        if (page.band_height > allocated_band_height) return true;
    }
    return false;
}

fn atlasHasLayerInfoOrImages(atlas: anytype) bool {
    const Atlas = switch (@typeInfo(@TypeOf(atlas))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(atlas),
    };
    const has_layer_info = if (@hasField(Atlas, "layer_info_height")) atlas.layer_info_height != 0 else false;
    const has_paint_images = if (@hasField(Atlas, "paint_image_records")) atlas.paint_image_records != null else false;
    return has_layer_info or has_paint_images;
}

pub fn atlasSlotCanOverflowIntoBank(slot: anytype, atlas: AtlasRef) bool {
    if (atlas.pageCount() > std.math.maxInt(u16)) return false;
    const page_count: u32 = @intCast(atlas.pageCount());
    if (page_count < slot.uploaded_pages) return false;
    if (slot.uploaded_pages > slot.page_ptrs.len) return false;
    for (0..slot.uploaded_pages) |page_index| {
        if (slot.page_ptrs[page_index] != atlas.page(page_index)) return false;
    }
    return true;
}

pub fn atlasSlotNeedsOverflowBank(slot: anytype, allocated_curve_height: u32, allocated_band_height: u32, atlas: AtlasRef) bool {
    return atlasSlotCanOverflowIntoBank(slot, atlas) and
        atlasSlotWouldRebuild(slot, allocated_curve_height, allocated_band_height, atlas);
}

fn currentAtlasNeedsOverflowBank(renderer: anytype, current: ?*const PreparedResources, key: ResourceKey, atlas: AtlasRef) bool {
    const prepared = current orelse return false;
    const lookup = preparedAtlasForKeyWithIndex(prepared, key) orelse return false;
    return renderer.atlasNeedsOverflowBank(prepared, lookup.index, atlas);
}

fn currentAtlasWouldRebuild(renderer: anytype, current: ?*const PreparedResources, key: ResourceKey, atlas: AtlasRef) bool {
    const prepared = current orelse return false;
    const lookup = preparedAtlasForKeyWithIndex(prepared, key) orelse return false;
    return renderer.atlasWouldRebuild(prepared, lookup.index, atlas);
}

fn resourceSetCanUseAtlasOverflowBanks(renderer: anytype, current: ?*const PreparedResources, next_set: *const ResourceSet, counts: ResourceSetCounts) bool {
    const prepared = current orelse return false;
    if (counts.layer_infos != 0 or counts.atlases != prepared.atlases.len) return false;
    if (!renderer.canUseAtlasOverflowBanks(prepared, counts.atlases)) return false;

    var atlas_index: usize = 0;
    for (next_set.slice()) |entry| switch (entry) {
        .text_atlas => |text| {
            const lookup = preparedAtlasForKeyWithIndex(prepared, text.key) orelse return false;
            defer atlas_index += 1;
            if (lookup.index != atlas_index) return false;
            if (!renderer.atlasSlotCanOverflowIntoBank(prepared, lookup.index, AtlasRef.init(text.atlas))) return false;
        },
        .path_picture => |path| {
            const lookup = preparedAtlasForKeyWithIndex(prepared, path.key) orelse return false;
            defer atlas_index += 1;
            if (lookup.index != atlas_index) return false;
            if (!renderer.atlasSlotCanOverflowIntoBank(prepared, lookup.index, AtlasRef.init(&path.picture.atlas))) return false;
        },
        .text_paint, .image => {},
    };
    return true;
}

pub fn planResourceUpload(renderer: anytype, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
    const counts = countResourceSetEntries(next_set);
    const uses_resource_cache = renderer.usesResourceCache();
    var plan = ResourceUploadPlan{ .set = next_set, .changed_keys = changed_keys };
    plan.upload_footprint = try next_set.estimateUploadFootprint();
    plan.gpu_bytes_allocated = plan.upload_footprint.allocatedBytes();
    var needs_atlas_overflow_bank = false;
    var next_atlas_index: usize = 0;
    for (next_set.slice()) |entry| {
        const key = resourceEntryKey(entry);
        const stamp = resourceEntryStamp(entry);
        const bytes = resourceEntryUploadBytes(entry);
        const old_stamp = if (current) |prepared| prepared.stampForKey(key) else null;
        const changed = if (old_stamp) |old| !old.eql(stamp) else true;
        if (changed) {
            try plan.addChanged(key, bytes);
        }
        switch (entry) {
            .text_atlas => |text| {
                const atlas_index = next_atlas_index;
                next_atlas_index += 1;
                const atlas = AtlasRef.init(text.atlas);
                const delta = atlasUploadDelta(current, key, atlas);
                plan.reused_atlas_pages += delta.reused_pages;
                plan.missing_atlas_pages += delta.missing_pages;
                plan.curve_bytes_upload += delta.curve_bytes;
                plan.band_bytes_upload += delta.band_bytes;
                if (current) |prepared| {
                    if (preparedAtlasForKeyWithIndex(prepared, key)) |lookup| {
                        if (lookup.index != atlas_index and uses_resource_cache) plan.atlas_cache_rebuilds = 1;
                    }
                }
                if (currentAtlasNeedsOverflowBank(renderer, current, key, atlas)) needs_atlas_overflow_bank = true;
                if (currentAtlasWouldRebuild(renderer, current, key, atlas)) plan.atlas_cache_rebuilds = 1;
            },
            .path_picture => |path| {
                const atlas_index = next_atlas_index;
                next_atlas_index += 1;
                const atlas = AtlasRef.init(&path.picture.atlas);
                const delta = atlasUploadDelta(current, key, atlas);
                plan.reused_atlas_pages += delta.reused_pages;
                plan.missing_atlas_pages += delta.missing_pages;
                plan.curve_bytes_upload += delta.curve_bytes;
                plan.band_bytes_upload += delta.band_bytes;
                if (current) |prepared| {
                    if (preparedAtlasForKeyWithIndex(prepared, key)) |lookup| {
                        if (lookup.index != atlas_index and uses_resource_cache) plan.atlas_cache_rebuilds = 1;
                    }
                }
                if (currentAtlasNeedsOverflowBank(renderer, current, key, atlas)) needs_atlas_overflow_bank = true;
                if (currentAtlasWouldRebuild(renderer, current, key, atlas)) plan.atlas_cache_rebuilds = 1;
            },
            .text_paint => {
                const old_layer = if (current) |prepared| preparedLayerInfoForKey(prepared, key) else null;
                if (old_layer == null or changed) plan.layer_info_bytes_upload += bytes;
            },
            .image => |image| {
                const old_image = if (current) |prepared| preparedImageForKey(prepared, key) else null;
                if (old_image) |prev| {
                    if (prev.stamp.eql(stamp)) {
                        plan.reused_images += 1;
                    } else {
                        plan.missing_images += 1;
                        plan.image_bytes_upload += image.image.pixelSlice().len;
                    }
                } else {
                    plan.missing_images += 1;
                    plan.image_bytes_upload += image.image.pixelSlice().len;
                }
            },
        }
    }
    const stats = renderer.resourceCacheStats();
    const free_atlas_layers = stats.active_atlas_layers_allocated -| stats.active_atlas_pages_resident;
    const free_image_layers = stats.active_image_layers_allocated -| stats.active_image_layers_resident;
    plan.new_atlas_banks = if (needs_atlas_overflow_bank or plan.missing_atlas_pages > free_atlas_layers) 1 else 0;
    plan.new_image_banks = if (plan.missing_images > free_image_layers) 1 else 0;
    if (counts.layer_infos > 0 and current != null and uses_resource_cache) plan.atlas_cache_rebuilds = 1;
    if (current) |prepared| {
        if (counts.atlases != prepared.atlases.len and uses_resource_cache) plan.atlas_cache_rebuilds = 1;
    }
    if (plan.new_atlas_banks > 0 and
        stats.active_atlas_layers_allocated > 0 and
        uses_resource_cache and
        !resourceSetCanUseAtlasOverflowBanks(renderer, current, next_set, counts))
    {
        plan.atlas_cache_rebuilds = 1;
    }
    if (plan.new_image_banks > 0 and stats.active_image_layers_allocated > 0 and uses_resource_cache) plan.image_cache_rebuilds = 1;
    if (plan.atlas_cache_rebuilds > 0) {
        plan.curve_bytes_upload = plan.upload_footprint.curve_bytes_used;
        plan.band_bytes_upload = plan.upload_footprint.band_bytes_used;
    }
    if (plan.image_cache_rebuilds > 0) {
        plan.image_bytes_upload = plan.upload_footprint.image_bytes_used;
    }
    plan.upload_bytes = if (uses_resource_cache)
        plan.curve_bytes_upload +
            plan.band_bytes_upload +
            plan.layer_info_bytes_upload +
            plan.image_bytes_upload
    else
        plan.upload_footprint.allocatedBytes();
    return plan;
}
