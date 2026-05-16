const std = @import("std");

const image_mod = @import("../image.zig");
const path_mod = @import("../path.zig");
const resource_key_mod = @import("../resource_key.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const set_mod = @import("set.zig");
const text_mod = @import("../text.zig");
const view_mod = @import("view.zig");

const Atlas = atlas_curve_mod.Atlas;
const Image = image_mod.Image;
const PathPicture = path_mod.PathPicture;
const PreparedLayerInfoUpload = view_mod.PreparedLayerInfoUpload;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceSet = set_mod.ResourceSet;
const ResourceStamp = resource_key_mod.ResourceStamp;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const mix64 = resource_key_mod.mix64;

pub fn textAtlasStamp(atlas: *const TextAtlas) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(atlas.pageCount())), @as(u64, atlas.layer_info_width));
    layout = mix64(layout, atlas.layer_info_height);
    var content = atlas.snapshotIdentity();
    for (atlas.pageSlice()) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
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
        for (records) |record| {
            const image = (record orelse continue).image;
            const stamp = imageStamp(image);
            content = mix64(content, stamp.identity);
            content = mix64(content, stamp.layout);
            content = mix64(content, stamp.content);
        }
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
    for (picture.atlas.pages) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
    }
    if (picture.atlas.layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x5041544850494354, std.mem.sliceAsBytes(data)));
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

pub fn resourceEntryKey(entry: ResourceSet.Entry) ResourceKey {
    return switch (entry) {
        .text_atlas => |text| text.key,
        .text_paint => |text| text.key,
        .path_picture => |path| path.key,
        .image => |image| image.key,
    };
}

pub fn resourceEntryStamp(entry: ResourceSet.Entry) ResourceStamp {
    return switch (entry) {
        .text_atlas => |text| textAtlasStamp(text.atlas),
        .text_paint => |text| textPaintStamp(text.blob),
        .path_picture => |path| pathPictureStamp(path.picture),
        .image => |image| imageStamp(image.image),
    };
}

pub fn resourceEntryUploadBytes(entry: ResourceSet.Entry) usize {
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
