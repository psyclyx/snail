const std = @import("std");

pub const MAX_ATLASES = 64;
pub const MAX_PAGES_PER_ATLAS = 256;
pub const MAX_IMAGES = 256;

pub fn AtlasSlot(comptime Atlas: type, comptime AtlasPage: type, comptime max_pages: usize) type {
    return struct {
        atlas: ?*const Atlas = null,
        base_layer: u32 = 0,
        info_row_base: u32 = 0,
        capacity_pages: u32 = 0,
        uploaded_pages: u32 = 0,
        page_ptrs: [max_pages]?*const AtlasPage = std.mem.zeroes([max_pages]?*const AtlasPage),
    };
}

pub fn ImageSlot(comptime Image: type) type {
    return struct {
        image: ?*const Image = null,
    };
}

pub fn atlasSlotsCompatible(atlas_slots: anytype, atlas_slot_count: usize, atlases: anytype) bool {
    if (atlases.len != atlas_slot_count) return false;
    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        const page_count: u32 = @intCast(atlas.pageCount());
        if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
        for (0..slot.uploaded_pages) |page_index| {
            if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
        }
    }
    return true;
}

pub fn rebuildAtlasSlots(atlas_slots: anytype, atlases: anytype) struct {
    atlas_slot_count: usize,
    allocated_curve_height: u32,
    allocated_band_height: u32,
    allocated_layer_count: u32,
} {
    std.debug.assert(atlases.len <= MAX_ATLASES);

    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layers: u32 = 0;
    var total_info_rows: u32 = 0;

    for (atlases, 0..) |atlas, i| {
        const page_count = atlas.pageCount();
        const capacity = atlasCapacity(@intCast(page_count));
        const slot = &atlas_slots[i];
        slot.* = .{
            .atlas = atlas,
            .base_layer = total_layers,
            .info_row_base = total_info_rows,
            .capacity_pages = capacity,
            .uploaded_pages = @intCast(page_count),
        };
        for (0..page_count) |page_index| {
            const page = atlas.page(@intCast(page_index));
            slot.page_ptrs[page_index] = page;
            if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
            if (page.band_height > max_band_h) max_band_h = page.band_height;
        }
        total_layers += capacity;
        total_info_rows += atlas.layer_info_height;
    }

    return .{
        .atlas_slot_count = atlases.len,
        .allocated_curve_height = heightCapacity(max_curve_h),
        .allocated_band_height = heightCapacity(max_band_h),
        .allocated_layer_count = total_layers,
    };
}

pub fn refreshAtlasSlots(atlas_slots: anytype, atlases: anytype) void {
    var total_info_rows: u32 = 0;
    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        const old_pages = slot.uploaded_pages;
        const new_pages: u32 = @intCast(atlas.pageCount());
        for (old_pages..new_pages) |page_index| {
            slot.page_ptrs[page_index] = atlas.page(@intCast(page_index));
        }
        slot.atlas = atlas;
        slot.uploaded_pages = new_pages;
        slot.info_row_base = total_info_rows;
        total_info_rows += atlas.layer_info_height;
    }
}

pub fn fillAtlasViews(atlas_slots: anytype, atlases: anytype, out_views: anytype) void {
    std.debug.assert(atlases.len == out_views.len);
    for (atlases, 0..) |atlas, i| {
        out_views[i] = .{
            .atlas = atlas,
            .layer_base = @intCast(atlas_slots[i].base_layer),
            .info_row_base = @intCast(atlas_slots[i].info_row_base),
        };
    }
}

pub fn findImageSlot(image_slots: anytype, image_slot_count: usize, image: anytype) ?usize {
    for (image_slots[0..image_slot_count], 0..) |slot, i| {
        if (slot.image == image) return i;
    }
    return null;
}

pub fn currentImageView(
    comptime ImageView: type,
    image_slots: anytype,
    image_slot_count: usize,
    allocated_image_width: u32,
    allocated_image_height: u32,
    image: anytype,
) ImageView {
    const slot_index = findImageSlot(image_slots, image_slot_count, image) orelse return .{ .image = image };
    const width_scale = if (allocated_image_width == 0) 1.0 else @as(f32, @floatFromInt(image.width)) / @as(f32, @floatFromInt(allocated_image_width));
    const height_scale = if (allocated_image_height == 0) 1.0 else @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(allocated_image_height));
    return .{
        .image = image,
        .layer = @intCast(slot_index),
        .uv_scale = .{ .x = width_scale, .y = height_scale },
    };
}

pub fn collectAtlasImages(image_slots: anytype, image_slot_count: usize, atlases: anytype, scratch: anytype) usize {
    var count: usize = 0;
    for (atlases) |atlas| {
        const records = atlas.paint_image_records orelse continue;
        for (records) |record| {
            const image = (record orelse continue).image;
            if (findImageSlot(image_slots, image_slot_count, image) != null) continue;
            var already_queued = false;
            for (scratch[0..count]) |queued| {
                if (queued == image) {
                    already_queued = true;
                    break;
                }
            }
            if (!already_queued and count < scratch.len) {
                scratch[count] = image;
                count += 1;
            }
        }
    }
    return count;
}

pub fn roundUpPowerOfTwo(value: u32) u32 {
    if (value <= 1) return 1;
    var v = value - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return v + 1;
}

pub fn atlasCapacity(page_count: u32) u32 {
    return @max(4, roundUpPowerOfTwo(page_count + 1));
}

pub fn heightCapacity(height: u32) u32 {
    return roundUpPowerOfTwo(@max(height, 1));
}

pub fn layerInfoTexelBase(width: u32, x: u32, y: u32) usize {
    return (y * width + x) * 4;
}

pub fn layerInfoTexelBaseOffset(width: u32, x: u32, y: u32, texel_offset: u32) usize {
    const texel = x + texel_offset;
    const texel_x = texel % width;
    const texel_y = y + texel / width;
    return layerInfoTexelBase(width, texel_x, texel_y);
}

pub fn patchImagePaintRecord(data: []f32, width: u32, row_base: u32, texel_offset: u32, view: anytype) void {
    const x = texel_offset % width;
    const y = row_base + texel_offset / width;
    const transform_base = layerInfoTexelBaseOffset(width, x, y, 2);
    data[transform_base + 3] = @floatFromInt(view.layer);
    const extra_base = layerInfoTexelBaseOffset(width, x, y, 5);
    data[extra_base + 0] = view.uv_scale.x;
    data[extra_base + 1] = view.uv_scale.y;
}
