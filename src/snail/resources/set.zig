const image_mod = @import("../image.zig");
const path_mod = @import("../path.zig");
const footprint_types = @import("footprint_types.zig");
const resource_key_mod = @import("../resource_key.zig");
const scene_mod = @import("../scene.zig");
const text_mod = @import("../text.zig");
const upload_common = @import("../render/format/upload_common.zig");

const Image = image_mod.Image;
const PathPicture = path_mod.PathPicture;
const ResourceCapacityMode = upload_common.AtlasCapacityMode;
const ResourceFootprint = footprint_types.ResourceFootprint;
const ResourceKey = resource_key_mod.ResourceKey;
const Scene = scene_mod.Scene;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const pointerResourceKey = resource_key_mod.pointerResourceKey;
const resourceKey = resource_key_mod.resourceKey;

pub const ResourceSet = struct {
    /// Caller-buffered CPU manifest. Entries point at app-owned
    /// TextAtlas, PathPicture, and Image values; no upload happens here.
    entries: []Entry = &.{},
    len: usize = 0,

    pub const Entry = union(enum) {
        text_atlas: TextAtlasEntry,
        text_paint: TextPaintEntry,
        path_picture: PathPictureEntry,
        image: ImageEntry,
    };

    pub const TextAtlasEntry = struct {
        key: ResourceKey,
        atlas: *const TextAtlas,
        atlas_capacity: ResourceCapacityMode = .growable,
    };

    pub const PathPictureEntry = struct {
        key: ResourceKey,
        picture: *const PathPicture,
        atlas_capacity: ResourceCapacityMode = .exact,
    };

    pub const TextPaintEntry = struct {
        key: ResourceKey,
        blob: *const TextBlob,
    };

    pub const ImageEntry = struct {
        key: ResourceKey,
        image: *const Image,
    };

    pub const TextAtlasOptions = struct {
        /// `.growable` gives Snail one heuristic growth window. Use
        /// `.reserve_pages` when the caller knows the intended atlas headroom.
        atlas_capacity: ResourceCapacityMode = .growable,
    };

    pub const PathPictureOptions = struct {
        /// Path pictures are immutable by default; callers can opt into
        /// growable or reserved capacity when reusing a stable resource key for
        /// related snapshots.
        atlas_capacity: ResourceCapacityMode = .exact,
    };

    pub fn init(entries: []Entry) ResourceSet {
        return .{ .entries = entries };
    }

    pub fn capacity(self: *const ResourceSet) usize {
        return self.entries.len;
    }

    pub fn reset(self: *ResourceSet) void {
        self.len = 0;
    }

    pub fn putTextAtlas(self: *ResourceSet, key_value: anytype, atlas: *const TextAtlas) !void {
        try self.putTextAtlasOptions(key_value, atlas, .{});
    }

    pub fn putTextAtlasOptions(self: *ResourceSet, key_value: anytype, atlas: *const TextAtlas, options: TextAtlasOptions) !void {
        try self.put(.{ .text_atlas = .{
            .key = resourceKey(key_value),
            .atlas = atlas,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putPathPicture(self: *ResourceSet, key_value: anytype, picture: *const PathPicture) !void {
        try self.putPathPictureOptions(key_value, picture, .{});
    }

    pub fn putPathPictureOptions(self: *ResourceSet, key_value: anytype, picture: *const PathPicture, options: PathPictureOptions) !void {
        try self.put(.{ .path_picture = .{
            .key = resourceKey(key_value),
            .picture = picture,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putImage(self: *ResourceSet, key_value: anytype, image: *const Image) !void {
        try self.put(.{ .image = .{ .key = resourceKey(key_value), .image = image } });
    }

    pub fn addScene(self: *ResourceSet, scene: *const Scene) !void {
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| {
                    try self.put(.{ .text_atlas = .{
                        .key = pointerResourceKey("scene.text_atlas", text.blob.atlas),
                        .atlas = text.blob.atlas,
                    } });
                    if (text.blob.hasPaintRecords()) {
                        try self.put(.{ .text_paint = .{
                            .key = pointerResourceKey("scene.text_paint", text.blob),
                            .blob = text.blob,
                        } });
                    }
                },
                .path => |path| try self.put(.{ .path_picture = .{
                    .key = pointerResourceKey("scene.path_picture", path.picture),
                    .picture = path.picture,
                } }),
            }
        }
    }

    fn put(self: *ResourceSet, entry: Entry) !void {
        const key = entryKey(entry);
        for (self.entries[0..self.len], 0..) |existing, i| {
            if (entryKey(existing).eql(key)) {
                self.entries[i] = entry;
                return;
            }
        }
        if (self.len >= self.entries.len) return error.ResourceSetFull;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    fn entryKey(entry: Entry) ResourceKey {
        return switch (entry) {
            .text_atlas => |text| text.key,
            .text_paint => |text| text.key,
            .path_picture => |path| path.key,
            .image => |image| image.key,
        };
    }

    pub fn slice(self: *const ResourceSet) []const Entry {
        return self.entries[0..self.len];
    }

    pub fn estimateUploadFootprint(self: *const ResourceSet) !ResourceFootprint {
        return @import("footprint.zig").resourceSetUploadFootprint(self);
    }
};
