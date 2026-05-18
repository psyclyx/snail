const std = @import("std");

const image_mod = @import("../image.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const atlas_page_mod = @import("../render/format/atlas/page.zig");
const footprint_types = @import("footprint_types.zig");
const manifest_mod = @import("manifest.zig");
const text_mod = @import("../text.zig");
const upload_common = @import("../render/format/upload_common.zig");

const Atlas = atlas_curve_mod.Atlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const Image = image_mod.Image;
const ResourceCapacityMode = upload_common.AtlasCapacityMode;
const ResourceFootprint = footprint_types.ResourceFootprint;
const ResourceManifest = manifest_mod.ResourceManifest;
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

const ManifestFootprintAccumulator = struct {
    out: ResourceFootprint = .{},
    total_layer_capacity: u32 = 0,
    first_page: ?*const AtlasPage = null,
    max_curve_h: u32 = 1,
    max_band_h: u32 = 1,
    total_layer_info_rows: u32 = 0,
    max_layer_info_width: u32 = 1,
    image_count: usize = 0,
    max_image_width: u32 = 1,
    max_image_height: u32 = 1,

    fn addTextAtlas(self: *ManifestFootprintAccumulator, atlas: *const TextAtlas, capacity_mode: ResourceCapacityMode) !void {
        try self.addLayerCapacity(atlas.pageCount(), capacity_mode);
        for (atlas.pageSlice()) |page_ref| self.addPage(page_ref);
        self.addLayerInfo(atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    }

    fn addCurveAtlas(self: *ManifestFootprintAccumulator, atlas: *const Atlas, capacity_mode: ResourceCapacityMode) !void {
        try self.addLayerCapacity(atlas.pageCount(), capacity_mode);
        for (0..atlas.pageCount()) |i| self.addPage(atlas.page(@intCast(i)));
        self.addLayerInfo(atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    }

    fn addLayerCapacity(self: *ManifestFootprintAccumulator, page_count: usize, capacity_mode: ResourceCapacityMode) !void {
        if (page_count > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
        self.total_layer_capacity = try std.math.add(
            u32,
            self.total_layer_capacity,
            upload_common.atlasCapacityForMode(@intCast(page_count), capacity_mode),
        );
    }

    fn addPage(self: *ManifestFootprintAccumulator, page_ref: *const AtlasPage) void {
        if (self.first_page == null) self.first_page = page_ref;
        self.out.curve_bytes_used += page_ref.curveTextureBytes();
        self.out.band_bytes_used += page_ref.bandTextureBytes();
        self.max_curve_h = @max(self.max_curve_h, page_ref.curve_height);
        self.max_band_h = @max(self.max_band_h, page_ref.band_height);
    }

    fn addLayerInfo(self: *ManifestFootprintAccumulator, data: ?[]const f32, width: u32, height: u32) void {
        if (data) |d| self.out.layer_info_bytes_used += d.len * @sizeOf(f32);
        if (height > 0) {
            self.total_layer_info_rows += height;
            self.max_layer_info_width = @max(self.max_layer_info_width, width);
        }
    }

    fn addImage(self: *ManifestFootprintAccumulator, image: *const Image) void {
        self.out.image_bytes_used += imageTextureBytes(image);
        self.max_image_width = @max(self.max_image_width, image.width);
        self.max_image_height = @max(self.max_image_height, image.height);
        self.image_count += 1;
    }

    fn finish(self: *const ManifestFootprintAccumulator) !ResourceFootprint {
        var out = self.out;
        if (self.first_page) |page_ref| {
            out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
                @as(usize, upload_common.heightCapacity(self.max_curve_h)) *
                @as(usize, self.total_layer_capacity) *
                CURVE_TEXEL_BYTES;
            out.band_bytes_allocated = @as(usize, page_ref.band_width) *
                @as(usize, upload_common.heightCapacity(self.max_band_h)) *
                @as(usize, self.total_layer_capacity) *
                BAND_TEXEL_BYTES;
        }

        if (self.total_layer_info_rows > 0) {
            out.layer_info_bytes_allocated = @as(usize, self.max_layer_info_width) *
                @as(usize, self.total_layer_info_rows) *
                LAYER_INFO_TEXEL_BYTES;
        }

        if (self.image_count > 0) {
            if (self.image_count > std.math.maxInt(u32)) return error.ImageLayerCountOverflow;
            out.image_bytes_allocated = @as(usize, upload_common.imageExtentCapacity(self.max_image_width)) *
                @as(usize, upload_common.imageExtentCapacity(self.max_image_height)) *
                @as(usize, upload_common.imageCapacity(@intCast(self.image_count))) *
                IMAGE_TEXEL_BYTES;
        }

        return out;
    }
};

pub fn resourceManifestUploadFootprint(set: *const ResourceManifest) !ResourceFootprint {
    var acc: ManifestFootprintAccumulator = .{};
    for (set.slice(), 0..) |entry, entry_index| {
        switch (entry) {
            .text_atlas => |text| try acc.addTextAtlas(text.atlas, text.atlas_capacity),
            .text_paint => |text| {
                acc.addLayerInfo(text.blob.paint_layer_info_data, text.blob.paint_layer_info_width, text.blob.paint_layer_info_height);
                if (text.blob.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        const image = (record orelse continue).image;
                        if (!resourceManifestSawImageBefore(set, entry_index, record_index, image)) acc.addImage(image);
                    }
                }
            },
            .path_picture => |path| {
                const atlas = &path.picture.atlas;
                try acc.addCurveAtlas(atlas, path.atlas_capacity);
                if (atlas.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        const image = (record orelse continue).image;
                        if (!resourceManifestSawImageBefore(set, entry_index, record_index, image)) acc.addImage(image);
                    }
                }
            },
            .image => |image| {
                if (!resourceManifestSawImageBefore(set, entry_index, null, image.image)) acc.addImage(image.image);
            },
        }
    }
    return acc.finish();
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

fn entryPaintImageRecords(entry: ResourceManifest.Entry) ?[]const ?Atlas.PaintImageRecord {
    return switch (entry) {
        .text_paint => |text| text.blob.paint_image_records,
        .path_picture => |path| path.picture.atlas.paint_image_records,
        else => null,
    };
}

fn entryReferencesImage(entry: ResourceManifest.Entry, image: *const Image) bool {
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

fn entryReferencesImageBeforeRecord(entry: ResourceManifest.Entry, image: *const Image, record_limit: usize) bool {
    const records = entryPaintImageRecords(entry) orelse return false;
    for (records[0..@min(record_limit, records.len)]) |record| {
        if ((record orelse continue).image == image) return true;
    }
    return false;
}

fn resourceManifestSawImageBefore(set: *const ResourceManifest, entry_index: usize, record_index: ?usize, image: *const Image) bool {
    const entries = set.slice();
    for (entries[0..entry_index]) |entry| {
        if (entryReferencesImage(entry, image)) return true;
    }
    if (record_index) |limit| {
        return entryReferencesImageBeforeRecord(entries[entry_index], image, limit);
    }
    return false;
}
