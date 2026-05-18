const std = @import("std");

const atlas_page_mod = @import("../render/format/atlas/page.zig");
const image_mod = @import("../image.zig");
const prepared_mod = @import("../resources/prepared.zig");
const resource_key_mod = @import("../resource_key.zig");
const manifest_mod = @import("../resources/manifest.zig");
const stamp_mod = @import("../resources/stamp.zig");
const upload_common = @import("../render/format/upload_common.zig");
const upload_mod = @import("../upload.zig");

const AtlasPage = atlas_page_mod.AtlasPage;
const Image = image_mod.Image;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceManifest = manifest_mod.ResourceManifest;
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

pub const AtlasCacheStatus = struct {
    can_overflow_into_bank: bool = false,
    needs_overflow_bank: bool = false,
    would_rebuild: bool = false,
};

const AtlasUploadDelta = struct {
    reused_pages: u32 = 0,
    missing_pages: u32 = 0,
    curve_bytes: usize = 0,
    band_bytes: usize = 0,
};

const ResourceManifestCounts = struct {
    atlases: usize = 0,
    layer_infos: usize = 0,
    images: usize = 0,
};

const PreparedAtlasLookup = struct {
    index: usize,
};

const ImageRequirements = struct {
    count: u32 = 0,
    max_width: u32 = 1,
    max_height: u32 = 1,

    fn capacityCount(self: ImageRequirements) u32 {
        if (self.count == 0) return 0;
        return upload_common.imageCapacity(self.count);
    }

    fn capacityWidth(self: ImageRequirements) u32 {
        return upload_common.imageExtentCapacity(self.max_width);
    }

    fn capacityHeight(self: ImageRequirements) u32 {
        return upload_common.imageExtentCapacity(self.max_height);
    }
};

fn countResourceEntries(entries: []const ResourceManifest.Entry) ResourceManifestCounts {
    var counts: ResourceManifestCounts = .{};
    for (entries) |entry| switch (entry) {
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
    return renderer.atlasCacheStatus(prepared, lookup.index, atlas).needs_overflow_bank;
}

fn currentAtlasWouldRebuild(renderer: anytype, current: ?*const PreparedResources, key: ResourceKey, atlas: AtlasRef) bool {
    const prepared = current orelse return false;
    const lookup = preparedAtlasForKeyWithIndex(prepared, key) orelse return false;
    return renderer.atlasCacheStatus(prepared, lookup.index, atlas).would_rebuild;
}

fn resourceManifestCanUseAtlasOverflowBanks(renderer: anytype, current: ?*const PreparedResources, entries: []const ResourceManifest.Entry, counts: ResourceManifestCounts) bool {
    const prepared = current orelse return false;
    if (counts.layer_infos != 0 or counts.atlases != prepared.atlases.len) return false;
    if (!renderer.canUseAtlasOverflowBanks(prepared, counts.atlases)) return false;

    var atlas_index: usize = 0;
    for (entries) |entry| switch (entry) {
        .text_atlas => |text| {
            const lookup = preparedAtlasForKeyWithIndex(prepared, text.key) orelse return false;
            defer atlas_index += 1;
            if (lookup.index != atlas_index) return false;
            if (!renderer.atlasCacheStatus(prepared, lookup.index, AtlasRef.init(text.atlas)).can_overflow_into_bank) return false;
        },
        .path_picture => |path| {
            const lookup = preparedAtlasForKeyWithIndex(prepared, path.key) orelse return false;
            defer atlas_index += 1;
            if (lookup.index != atlas_index) return false;
            if (!renderer.atlasCacheStatus(prepared, lookup.index, AtlasRef.init(&path.picture.atlas)).can_overflow_into_bank) return false;
        },
        .text_paint, .image => {},
    };
    return true;
}

fn collectImageRequirements(allocator: std.mem.Allocator, entries: []const ResourceManifest.Entry) !ImageRequirements {
    var images = std.ArrayListUnmanaged(*const Image).empty;
    defer images.deinit(allocator);

    for (entries) |entry| switch (entry) {
        .text_atlas => {},
        .text_paint => |text| try appendPaintRecordImages(allocator, &images, text.blob.paint_image_records),
        .path_picture => |path| try appendPaintRecordImages(allocator, &images, path.picture.atlas.paint_image_records),
        .image => |image| try appendUniqueImage(allocator, &images, image.image),
    };

    var requirements: ImageRequirements = .{ .count = @intCast(images.items.len) };
    for (images.items) |image| {
        requirements.max_width = @max(requirements.max_width, image.width);
        requirements.max_height = @max(requirements.max_height, image.height);
    }
    return requirements;
}

fn appendPaintRecordImages(
    allocator: std.mem.Allocator,
    images: *std.ArrayListUnmanaged(*const Image),
    maybe_records: ?[]const ?@import("../render/format/atlas/curve.zig").Atlas.PaintImageRecord,
) !void {
    const records = maybe_records orelse return;
    for (records) |record| {
        const image = (record orelse continue).image;
        try appendUniqueImage(allocator, images, image);
    }
}

fn appendUniqueImage(allocator: std.mem.Allocator, images: *std.ArrayListUnmanaged(*const Image), image: *const Image) !void {
    for (images.items) |existing| {
        if (existing == image) return;
    }
    try images.append(allocator, image);
}

pub fn planResourceUpload(renderer: anytype, allocator: std.mem.Allocator, current: ?*const PreparedResources, next_set: *const ResourceManifest) !ResourceUploadPlan {
    var plan = try ResourceUploadPlan.init(allocator, next_set);
    errdefer plan.deinit();

    const entries = plan.manifest.entries;
    const counts = countResourceEntries(entries);
    const image_requirements = try collectImageRequirements(allocator, entries);
    const uses_resource_cache = renderer.usesResourceCache();
    plan.footprint = try next_set.estimateUploadFootprint();
    var needs_atlas_overflow_bank = false;
    var next_atlas_index: usize = 0;
    for (entries) |entry| {
        const key = resourceEntryKey(entry);
        const stamp = resourceEntryStamp(entry);
        const bytes = resourceEntryUploadBytes(entry);
        const old_stamp = if (current) |prepared| prepared.stampForKey(key) else null;
        const changed = if (old_stamp) |old| !old.eql(stamp) else true;
        if (changed) {
            try plan.diff.add(key, bytes);
        }
        switch (entry) {
            .text_atlas => |text| {
                const atlas_index = next_atlas_index;
                next_atlas_index += 1;
                const atlas = AtlasRef.init(text.atlas);
                const delta = atlasUploadDelta(current, key, atlas);
                plan.cache.reused_atlas_pages += delta.reused_pages;
                plan.cache.missing_atlas_pages += delta.missing_pages;
                plan.upload.curve_bytes += delta.curve_bytes;
                plan.upload.band_bytes += delta.band_bytes;
                if (current) |prepared| {
                    if (preparedAtlasForKeyWithIndex(prepared, key)) |lookup| {
                        if (lookup.index != atlas_index and uses_resource_cache) plan.cache.atlas_rebuilds = 1;
                    }
                }
                if (currentAtlasNeedsOverflowBank(renderer, current, key, atlas)) needs_atlas_overflow_bank = true;
                if (currentAtlasWouldRebuild(renderer, current, key, atlas)) plan.cache.atlas_rebuilds = 1;
            },
            .path_picture => |path| {
                const atlas_index = next_atlas_index;
                next_atlas_index += 1;
                const atlas = AtlasRef.init(&path.picture.atlas);
                const delta = atlasUploadDelta(current, key, atlas);
                plan.cache.reused_atlas_pages += delta.reused_pages;
                plan.cache.missing_atlas_pages += delta.missing_pages;
                plan.upload.curve_bytes += delta.curve_bytes;
                plan.upload.band_bytes += delta.band_bytes;
                if (current) |prepared| {
                    if (preparedAtlasForKeyWithIndex(prepared, key)) |lookup| {
                        if (lookup.index != atlas_index and uses_resource_cache) plan.cache.atlas_rebuilds = 1;
                    }
                }
                if (currentAtlasNeedsOverflowBank(renderer, current, key, atlas)) needs_atlas_overflow_bank = true;
                if (currentAtlasWouldRebuild(renderer, current, key, atlas)) plan.cache.atlas_rebuilds = 1;
            },
            .text_paint => {
                const old_layer = if (current) |prepared| preparedLayerInfoForKey(prepared, key) else null;
                if (old_layer == null or changed) plan.upload.layer_info_bytes += bytes;
            },
            .image => |image| {
                const old_image = if (current) |prepared| preparedImageForKey(prepared, key) else null;
                if (old_image) |prev| {
                    if (prev.stamp.eql(stamp)) {
                        plan.cache.reused_images += 1;
                    } else {
                        plan.cache.missing_images += 1;
                        plan.upload.image_bytes += image.image.pixelSlice().len;
                    }
                } else {
                    plan.cache.missing_images += 1;
                    plan.upload.image_bytes += image.image.pixelSlice().len;
                }
            },
        }
    }
    const stats = renderer.resourceCacheStats();
    const free_atlas_layers = stats.active_atlas_layers_allocated -| stats.active_atlas_pages_resident;
    const free_image_layers = stats.active_image_layers_allocated -| stats.active_image_layers_resident;
    plan.cache.new_atlas_banks = if (needs_atlas_overflow_bank or plan.cache.missing_atlas_pages > free_atlas_layers) 1 else 0;
    plan.cache.new_image_banks = if (plan.cache.missing_images > free_image_layers) 1 else 0;
    if (counts.layer_infos > 0 and current != null and uses_resource_cache) plan.cache.atlas_rebuilds = 1;
    if (current) |prepared| {
        if (counts.atlases != prepared.atlases.len and uses_resource_cache) plan.cache.atlas_rebuilds = 1;
    }
    if (plan.cache.new_atlas_banks > 0 and
        stats.active_atlas_layers_allocated > 0 and
        uses_resource_cache and
        !resourceManifestCanUseAtlasOverflowBanks(renderer, current, entries, counts))
    {
        plan.cache.atlas_rebuilds = 1;
    }
    if (plan.cache.new_image_banks > 0 and stats.active_image_layers_allocated > 0 and uses_resource_cache) plan.cache.image_rebuilds = 1;
    if (current) |prepared| {
        if (uses_resource_cache and renderer.imageArrayWouldRebuild(
            prepared,
            image_requirements.capacityCount(),
            image_requirements.capacityWidth(),
            image_requirements.capacityHeight(),
        )) {
            plan.cache.image_rebuilds = 1;
        }
    }
    if (plan.cache.atlas_rebuilds > 0) {
        plan.upload.curve_bytes = plan.footprint.curve_bytes_used;
        plan.upload.band_bytes = plan.footprint.band_bytes_used;
    }
    if (plan.cache.image_rebuilds > 0) {
        plan.upload.image_bytes = plan.footprint.image_bytes_used;
    }
    plan.upload.bytes = if (uses_resource_cache)
        plan.upload.curve_bytes +
            plan.upload.band_bytes +
            plan.upload.layer_info_bytes +
            plan.upload.image_bytes
    else
        plan.footprint.allocatedBytes();
    return plan;
}
