const image_mod = @import("../image.zig");
const lowlevel_mod = @import("../lowlevel.zig");
const prepared_mod = @import("prepared.zig");
const set_mod = @import("set.zig");
const stamp_mod = @import("stamp.zig");
const upload_common = @import("../renderer/upload_common.zig");
const upload_mod = @import("../upload.zig");

const Atlas = lowlevel_mod.Atlas;
const Image = image_mod.Image;
const PreparedAtlasView = lowlevel_mod.PreparedAtlasView;
const PreparedImageView = lowlevel_mod.PreparedImageView;
const PreparedLayerInfoUpload = lowlevel_mod.PreparedLayerInfoUpload;
const PreparedLayerInfoView = lowlevel_mod.PreparedLayerInfoView;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceSet = set_mod.ResourceSet;
const UploadAllocators = upload_mod.UploadAllocators;

pub const ResourceUploadBatch = struct {
    atlases: []const *const Atlas,
    atlas_capacity_modes: []const upload_common.AtlasCapacityMode,
    atlas_views: []PreparedAtlasView,
    layer_infos: []const PreparedLayerInfoUpload,
    layer_info_views: []PreparedLayerInfoView,
    images: []const *const Image,
    image_views: []PreparedImageView,
};

pub fn uploadPreparedResources(renderer: anytype, set: *const ResourceSet, allocators: UploadAllocators) !PreparedResources {
    const persistent = allocators.persistent;
    const scratch = allocators.scratch;
    var atlas_count: usize = 0;
    var layer_info_count: usize = 0;
    var image_count: usize = 0;
    for (set.slice()) |entry| switch (entry) {
        .text_atlas, .path_picture => atlas_count += 1,
        .text_paint => layer_info_count += 1,
        .image => image_count += 1,
    };

    var prepared = PreparedResources{
        .allocator = persistent,
        .atlases = try persistent.alloc(PreparedResources.PreparedAtlasResource, atlas_count),
        .layer_infos = try persistent.alloc(PreparedResources.PreparedLayerInfoResource, layer_info_count),
        .images = try persistent.alloc(PreparedResources.PreparedImageResource, image_count),
    };
    errdefer prepared.deinit();

    const upload_atlases = try scratch.alloc(*const Atlas, atlas_count);
    defer scratch.free(upload_atlases);
    const atlas_capacity_modes = try scratch.alloc(upload_common.AtlasCapacityMode, atlas_count);
    defer scratch.free(atlas_capacity_modes);
    const atlas_views = try scratch.alloc(PreparedAtlasView, atlas_count);
    defer scratch.free(atlas_views);

    const upload_layer_infos = try scratch.alloc(PreparedLayerInfoUpload, layer_info_count);
    defer scratch.free(upload_layer_infos);
    const layer_info_views = try scratch.alloc(PreparedLayerInfoView, layer_info_count);
    defer scratch.free(layer_info_views);

    const upload_images = try scratch.alloc(*const Image, image_count);
    defer scratch.free(upload_images);
    const image_views = try scratch.alloc(PreparedImageView, image_count);
    defer scratch.free(image_views);

    var atlas_i: usize = 0;
    var layer_info_i: usize = 0;
    var image_i: usize = 0;
    for (set.slice()) |entry| {
        switch (entry) {
            .text_atlas => |text| {
                prepared.atlases[atlas_i] = .{
                    .key = text.key,
                    .kind = .text,
                    .text_atlas = text.atlas,
                    .atlas = undefined,
                    .owns_wrapper = true,
                    .stamp = stamp_mod.textAtlasStamp(text.atlas),
                };
                prepared.atlases[atlas_i].wrapper = text.atlas.uploadAtlas();
                prepared.atlases[atlas_i].atlas = &prepared.atlases[atlas_i].wrapper;
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_capacity_modes[atlas_i] = text.atlas_capacity;
                atlas_i += 1;
            },
            .text_paint => |text| {
                prepared.layer_infos[layer_info_i] = .{
                    .key = text.key,
                    .text_blob = text.blob,
                    .stamp = stamp_mod.textPaintStamp(text.blob),
                };
                upload_layer_infos[layer_info_i] = stamp_mod.textPaintLayerInfoUpload(text.blob);
                layer_info_i += 1;
            },
            .path_picture => |path| {
                prepared.atlases[atlas_i] = .{
                    .key = path.key,
                    .kind = .path,
                    .picture = path.picture,
                    .atlas = &path.picture.atlas,
                    .stamp = stamp_mod.pathPictureStamp(path.picture),
                };
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_capacity_modes[atlas_i] = path.atlas_capacity;
                atlas_i += 1;
            },
            .image => |image| {
                prepared.images[image_i] = .{
                    .key = image.key,
                    .image = image.image,
                    .stamp = stamp_mod.imageStamp(image.image),
                };
                upload_images[image_i] = image.image;
                image_i += 1;
            },
        }
    }

    try renderer.uploadResourceBatch(allocators, &prepared, .{
        .atlases = upload_atlases,
        .atlas_capacity_modes = atlas_capacity_modes[0..atlas_count],
        .atlas_views = atlas_views,
        .layer_infos = upload_layer_infos,
        .layer_info_views = layer_info_views,
        .images = upload_images,
        .image_views = image_views,
    });

    for (prepared.atlases, 0..) |*entry, i| {
        entry.view = atlas_views[i];
        if (atlas_views[i].page_layers.len > 0) {
            const page_layers = try persistent.dupe(u32, atlas_views[i].page_layers);
            entry.view.page_layers = page_layers;
            entry.owns_page_layers = true;
        }
    }
    for (prepared.layer_infos, 0..) |*entry, i| entry.view = layer_info_views[i];
    for (prepared.images, 0..) |*entry, i| entry.view = image_views[i];
    return prepared;
}
