const std = @import("std");

const image_mod = @import("../image.zig");
const path_mod = @import("../path.zig");
const resource_key_mod = @import("../resource_key.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const manifest_mod = @import("manifest.zig");
const text_mod = @import("../text.zig");
const view_mod = @import("view.zig");

const AtlasPage = @import("../render/format/atlas/page.zig").AtlasPage;
const Atlas = atlas_curve_mod.Atlas;
const Image = image_mod.Image;
const PathPicture = path_mod.PathPicture;
const PreparedLayerInfoUpload = view_mod.PreparedLayerInfoUpload;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceManifest = manifest_mod.ResourceManifest;
const ResourceStamp = resource_key_mod.ResourceStamp;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const mix64 = resource_key_mod.mix64;

pub fn textAtlasStamp(atlas: *const TextAtlas) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(atlas.pageCount())), @as(u64, atlas.layer_info_width));
    layout = mix64(layout, atlas.layer_info_height);
    var content = atlas.snapshotIdentity();
    for (atlas.pageSlice()) |page| {
        content = hashAtlasPage(content, page);
    }
    if (atlas.layer_info_data) |data| {
        content = hashBytes(content, 0x544558544c415945, std.mem.sliceAsBytes(data));
    }
    return .{
        .identity = atlas.snapshotIdentity(),
        .layout = layout,
        .content = content,
    };
}

pub fn textPaintStamp(blob: *const TextBlob) ResourceStamp {
    const atlas_stamp = textAtlasStamp(blob.atlas);
    var layout = mix64(atlas_stamp.layout, blob.paint_layer_info_width);
    layout = mix64(layout, blob.paint_layer_info_height);
    var content = atlas_stamp.content;
    if (blob.paint_layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x544558545041494e, std.mem.sliceAsBytes(data)));
    }
    if (blob.paint_image_records) |records| {
        content = hashPaintImageRecords(content, records);
    }
    return .{
        .identity = mix64(@intCast(@intFromPtr(blob)), atlas_stamp.identity),
        .layout = layout,
        .content = content,
    };
}

pub fn pathPictureStamp(picture: *const PathPicture) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(picture.shapeCount())), picture.atlas.pageCount());
    layout = mix64(layout, picture.atlas.layer_info_width);
    layout = mix64(layout, picture.atlas.layer_info_height);
    var content = @as(u64, @intCast(@intFromPtr(picture)));
    for (picture.shapes) |shape| {
        content = hashPathShape(content, shape);
    }
    content = hashBytes(content, 0x50415448524f4c45, std.mem.sliceAsBytes(picture.layer_roles));
    for (picture.atlas.pages) |page| {
        content = hashAtlasPage(content, page);
    }
    if (picture.atlas.layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x5041544850494354, std.mem.sliceAsBytes(data)));
    }
    if (picture.atlas.paint_image_records) |records| {
        content = hashPaintImageRecords(content, records);
    }
    return .{
        .identity = @intCast(@intFromPtr(picture)),
        .layout = layout,
        .content = content,
    };
}

pub fn imageStamp(image: *const Image) ResourceStamp {
    const pixels = image.pixelSlice();
    return .{
        .identity = @intCast(@intFromPtr(image)),
        .layout = mix64(@as(u64, image.width), image.height),
        .content = std.hash.Wyhash.hash(0x494d414745535247, pixels),
    };
}

pub fn textPaintLayerInfoUpload(blob: *const TextBlob) PreparedLayerInfoUpload {
    return .{
        .data = blob.paint_layer_info_data,
        .width = blob.paint_layer_info_width,
        .height = blob.paint_layer_info_height,
        .paint_image_records = blob.paint_image_records,
    };
}

pub fn resourceEntryKey(entry: ResourceManifest.Entry) ResourceKey {
    return switch (entry) {
        .text_atlas => |text| text.key,
        .text_paint => |text| text.key,
        .path_picture => |path| path.key,
        .image => |image| image.key,
    };
}

pub fn resourceEntryStamp(entry: ResourceManifest.Entry) ResourceStamp {
    return switch (entry) {
        .text_atlas => |text| textAtlasStamp(text.atlas),
        .text_paint => |text| textPaintStamp(text.blob),
        .path_picture => |path| pathPictureStamp(path.picture),
        .image => |image| imageStamp(image.image),
    };
}

pub fn resourceEntryUploadBytes(entry: ResourceManifest.Entry) usize {
    return switch (entry) {
        .text_atlas => |text| textAtlasUploadBytes(text.atlas),
        .text_paint => |text| textPaintUploadBytes(text.blob),
        .path_picture => |path| curveAtlasUploadBytes(&path.picture.atlas),
        .image => |image| image.image.pixelSlice().len,
    };
}

fn curveAtlasUploadBytes(atlas: *const Atlas) usize {
    var total: usize = 0;
    for (0..atlas.pageCount()) |i| {
        total += atlas.page(@intCast(i)).textureBytes();
    }
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    if (atlas.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            total += image.pixelSlice().len;
        }
    }
    return total;
}

fn textAtlasUploadBytes(atlas: *const TextAtlas) usize {
    var total: usize = 0;
    for (atlas.pageSlice()) |page| total += page.textureBytes();
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

fn textPaintUploadBytes(blob: *const TextBlob) usize {
    var total: usize = 0;
    if (blob.paint_layer_info_data) |data| total += data.len * @sizeOf(f32);
    if (blob.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            total += image.pixelSlice().len;
        }
    }
    return total;
}

fn hashAtlasPage(seed: u64, page: *const AtlasPage) u64 {
    var h = seed;
    h = mix64(h, page.curve_width);
    h = mix64(h, page.curve_height);
    h = hashBytes(h, 0x4355525645504147, std.mem.sliceAsBytes(page.curve_data));
    h = mix64(h, page.band_width);
    h = mix64(h, page.band_height);
    h = hashBytes(h, 0x42414e4450414745, std.mem.sliceAsBytes(page.band_data));
    return h;
}

fn hashPathShape(seed: u64, shape: PathPicture.Shape) u64 {
    var h = seed;
    h = mix64(h, shape.glyph_id);
    h = hashBBox(h, shape.bbox);
    h = mix64(h, shape.page_index);
    h = mix64(h, shape.info_x);
    h = mix64(h, shape.info_y);
    h = mix64(h, shape.layer_count);
    h = hashTransform(h, shape.transform);
    return h;
}

fn hashBBox(seed: u64, bbox: anytype) u64 {
    var h = seed;
    h = hashF32(h, bbox.min.x);
    h = hashF32(h, bbox.min.y);
    h = hashF32(h, bbox.max.x);
    h = hashF32(h, bbox.max.y);
    return h;
}

fn hashTransform(seed: u64, transform: anytype) u64 {
    var h = seed;
    h = hashF32(h, transform.xx);
    h = hashF32(h, transform.xy);
    h = hashF32(h, transform.tx);
    h = hashF32(h, transform.yx);
    h = hashF32(h, transform.yy);
    h = hashF32(h, transform.ty);
    return h;
}

fn hashPaintImageRecords(seed: u64, records: []const ?Atlas.PaintImageRecord) u64 {
    var h = mix64(seed, records.len);
    for (records) |record| {
        const resolved = record orelse {
            h = mix64(h, 0);
            continue;
        };
        h = mix64(h, 1);
        h = mix64(h, resolved.texel_offset);
        const stamp = imageStamp(resolved.image);
        h = mix64(h, stamp.identity);
        h = mix64(h, stamp.layout);
        h = mix64(h, stamp.content);
    }
    return h;
}

fn hashBytes(seed: u64, comptime hash_seed: u64, bytes: []const u8) u64 {
    return mix64(seed, std.hash.Wyhash.hash(hash_seed, bytes));
}

fn hashF32(seed: u64, value: f32) u64 {
    return mix64(seed, @as(u32, @bitCast(value)));
}
