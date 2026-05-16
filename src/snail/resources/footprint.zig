const std = @import("std");

const image_mod = @import("../image.zig");
const atlas_curve_mod = @import("../render/backend/atlas/curve.zig");
const atlas_page_mod = @import("../render/backend/atlas/page.zig");
const set_mod = @import("set.zig");
const text_mod = @import("../text.zig");
const upload_common = @import("../render/backend/upload_common.zig");
const upload_mod = @import("../upload.zig");

const Atlas = atlas_curve_mod.Atlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const Image = image_mod.Image;
const ResourceCapacityMode = upload_common.AtlasCapacityMode;
const ResourceFootprint = upload_mod.ResourceFootprint;
const ResourceSet = set_mod.ResourceSet;
const TextAtlas = text_mod.TextAtlas;

const CURVE_TEXEL_BYTES: usize = 8; // RGBA16F
const BAND_TEXEL_BYTES: usize = 4; // RG16UI
const LAYER_INFO_TEXEL_BYTES: usize = 16; // RGBA32F
const IMAGE_TEXEL_BYTES: usize = 4; // SRGBA8

pub fn curveAtlasFootprint(atlas: *const Atlas, capacity_mode: ResourceCapacityMode) ResourceFootprint {
    var out: ResourceFootprint = .{};
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var first_page: ?*const AtlasPage = null;

    for (0..atlas.pageCount()) |i| {
        const page_ref = atlas.page(@intCast(i));
        if (first_page == null) first_page = page_ref;
        out.curve_bytes_used += page_ref.curveTextureBytes();
        out.band_bytes_used += page_ref.bandTextureBytes();
        max_curve_h = @max(max_curve_h, page_ref.curve_height);
        max_band_h = @max(max_band_h, page_ref.band_height);
    }

    if (first_page) |page_ref| {
        const capacity = upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), capacity_mode);
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, capacity) *
            BAND_TEXEL_BYTES;
    }

    addLayerInfoFootprint(&out, atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    return out;
}

pub fn textAtlasUploadFootprint(atlas: *const TextAtlas) ResourceFootprint {
    var out: ResourceFootprint = .{};
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var first_page: ?*const AtlasPage = null;

    for (atlas.pageSlice()) |page_ref| {
        if (first_page == null) first_page = page_ref;
        out.curve_bytes_used += page_ref.curveTextureBytes();
        out.band_bytes_used += page_ref.bandTextureBytes();
        max_curve_h = @max(max_curve_h, page_ref.curve_height);
        max_band_h = @max(max_band_h, page_ref.band_height);
    }

    if (first_page) |page_ref| {
        const capacity = upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), .growable);
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, capacity) *
            BAND_TEXEL_BYTES;
    }

    addLayerInfoFootprint(&out, atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    return out;
}

pub fn resourceSetUploadFootprint(set: *const ResourceSet) !ResourceFootprint {
    var out: ResourceFootprint = .{};
    var total_layer_capacity: u32 = 0;
    var first_page: ?*const AtlasPage = null;
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layer_info_rows: u32 = 0;
    var max_layer_info_width: u32 = 1;

    var image_count: usize = 0;
    var max_image_width: u32 = 1;
    var max_image_height: u32 = 1;

    for (set.slice(), 0..) |entry, entry_index| {
        switch (entry) {
            .text_atlas => |text| {
                const atlas = text.atlas;
                if (atlas.pageCount() > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
                total_layer_capacity = try std.math.add(u32, total_layer_capacity, upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), text.atlas_capacity));
                for (atlas.pageSlice()) |page_ref| {
                    if (first_page == null) first_page = page_ref;
                    out.curve_bytes_used += page_ref.curveTextureBytes();
                    out.band_bytes_used += page_ref.bandTextureBytes();
                    max_curve_h = @max(max_curve_h, page_ref.curve_height);
                    max_band_h = @max(max_band_h, page_ref.band_height);
                }
                if (atlas.layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (atlas.layer_info_height > 0) {
                    total_layer_info_rows += atlas.layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, atlas.layer_info_width);
                }
            },
            .text_paint => |text| {
                const blob = text.blob;
                if (blob.paint_layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (blob.paint_layer_info_height > 0) {
                    total_layer_info_rows += blob.paint_layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, blob.paint_layer_info_width);
                }
                if (blob.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        addImageFootprintIfFirst(&out, set, entry_index, record_index, (record orelse continue).image, &image_count, &max_image_width, &max_image_height);
                    }
                }
            },
            .path_picture => |path| {
                const atlas = &path.picture.atlas;
                if (atlas.pageCount() > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
                total_layer_capacity = try std.math.add(u32, total_layer_capacity, upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), path.atlas_capacity));
                for (0..atlas.pageCount()) |i| {
                    const page_ref = atlas.page(@intCast(i));
                    if (first_page == null) first_page = page_ref;
                    out.curve_bytes_used += page_ref.curveTextureBytes();
                    out.band_bytes_used += page_ref.bandTextureBytes();
                    max_curve_h = @max(max_curve_h, page_ref.curve_height);
                    max_band_h = @max(max_band_h, page_ref.band_height);
                }
                if (atlas.layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (atlas.layer_info_height > 0) {
                    total_layer_info_rows += atlas.layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, atlas.layer_info_width);
                }
                if (atlas.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        addImageFootprintIfFirst(&out, set, entry_index, record_index, (record orelse continue).image, &image_count, &max_image_width, &max_image_height);
                    }
                }
            },
            .image => |image| addImageFootprintIfFirst(&out, set, entry_index, null, image.image, &image_count, &max_image_width, &max_image_height),
        }
    }

    if (first_page) |page_ref| {
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, total_layer_capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, total_layer_capacity) *
            BAND_TEXEL_BYTES;
    }

    if (total_layer_info_rows > 0) {
        out.layer_info_bytes_allocated = @as(usize, max_layer_info_width) *
            @as(usize, total_layer_info_rows) *
            LAYER_INFO_TEXEL_BYTES;
    }

    if (image_count > 0) {
        if (image_count > std.math.maxInt(u32)) return error.ImageLayerCountOverflow;
        out.image_bytes_allocated = @as(usize, upload_common.imageExtentCapacity(max_image_width)) *
            @as(usize, upload_common.imageExtentCapacity(max_image_height)) *
            @as(usize, upload_common.imageCapacity(@intCast(image_count))) *
            IMAGE_TEXEL_BYTES;
    }

    return out;
}

fn addLayerInfoFootprint(out: *ResourceFootprint, data: ?[]const f32, width: u32, height: u32) void {
    if (data) |d| out.layer_info_bytes_used += d.len * @sizeOf(f32);
    if (height > 0) {
        out.layer_info_bytes_allocated += @as(usize, @max(width, 1)) *
            @as(usize, height) *
            LAYER_INFO_TEXEL_BYTES;
    }
}

fn imageTextureBytes(image: *const Image) usize {
    return image_mod.textureBytes(image);
}

fn entryPaintImageRecords(entry: ResourceSet.Entry) ?[]const ?Atlas.PaintImageRecord {
    return switch (entry) {
        .text_paint => |text| text.blob.paint_image_records,
        .path_picture => |path| path.picture.atlas.paint_image_records,
        else => null,
    };
}

fn entryReferencesImage(entry: ResourceSet.Entry, image: *const Image) bool {
    switch (entry) {
        .image => |entry_image| if (entry_image.image == image) return true,
        else => {},
    }
    const records = entryPaintImageRecords(entry) orelse return false;
    for (records) |record| {
        if ((record orelse continue).image == image) return true;
    }
    return false;
}

fn entryReferencesImageBeforeRecord(entry: ResourceSet.Entry, image: *const Image, record_limit: usize) bool {
    const records = entryPaintImageRecords(entry) orelse return false;
    for (records[0..@min(record_limit, records.len)]) |record| {
        if ((record orelse continue).image == image) return true;
    }
    return false;
}

fn resourceSetSawImageBefore(set: *const ResourceSet, entry_index: usize, record_index: ?usize, image: *const Image) bool {
    const entries = set.slice();
    for (entries[0..entry_index]) |entry| {
        if (entryReferencesImage(entry, image)) return true;
    }
    if (record_index) |limit| {
        return entryReferencesImageBeforeRecord(entries[entry_index], image, limit);
    }
    return false;
}

fn addImageFootprintIfFirst(
    out: *ResourceFootprint,
    set: *const ResourceSet,
    entry_index: usize,
    record_index: ?usize,
    image: *const Image,
    image_count: *usize,
    max_image_width: *u32,
    max_image_height: *u32,
) void {
    if (resourceSetSawImageBefore(set, entry_index, record_index, image)) return;
    out.image_bytes_used += imageTextureBytes(image);
    max_image_width.* = @max(max_image_width.*, image.width);
    max_image_height.* = @max(max_image_height.*, image.height);
    image_count.* += 1;
}
