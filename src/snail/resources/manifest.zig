const image_mod = @import("../image.zig");
const path_mod = @import("../path.zig");
const footprint_types = @import("footprint_types.zig");
const resource_key_mod = @import("../resource_key.zig");
const text_mod = @import("../text.zig");
const upload_common = @import("../render/format/upload_common.zig");

const Image = image_mod.Image;
const PathPicture = path_mod.PathPicture;
const ResourceCapacityMode = upload_common.AtlasCapacityMode;
const ResourceFootprint = footprint_types.ResourceFootprint;
const ResourceKey = resource_key_mod.ResourceKey;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const derivedResourceKey = resource_key_mod.derived;
const resourceKey = resource_key_mod.resourceKey;

pub const ResourceManifest = struct {
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

    pub const TextBlobResourceKeys = resource_key_mod.TextResourceKeys;

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

    pub fn init(entries: []Entry) ResourceManifest {
        return .{ .entries = entries };
    }

    pub fn capacity(self: *const ResourceManifest) usize {
        return self.entries.len;
    }

    pub fn reset(self: *ResourceManifest) void {
        self.len = 0;
    }

    pub fn putTextAtlas(self: *ResourceManifest, key_value: anytype, atlas: *const TextAtlas) !void {
        try self.putTextAtlasOptions(key_value, atlas, .{});
    }

    pub fn putTextAtlasOptions(self: *ResourceManifest, key_value: anytype, atlas: *const TextAtlas, options: TextAtlasOptions) !void {
        try self.put(.{ .text_atlas = .{
            .key = resourceKey(key_value),
            .atlas = atlas,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    fn putTextBlobPaint(self: *ResourceManifest, key_value: anytype, blob: *const TextBlob) !void {
        try self.put(.{ .text_paint = .{
            .key = resourceKey(key_value),
            .blob = blob,
        } });
    }

    pub fn textBlobResourceKeys(atlas_key_value: anytype, blob_key_value: anytype, blob: *const TextBlob) TextBlobResourceKeys {
        const blob_key = resourceKey(blob_key_value);
        return .{
            .atlas = resourceKey(atlas_key_value),
            .paint = if (blob.hasPaintRecords()) derivedResourceKey(blob_key, "text_paint") else null,
        };
    }

    pub fn putTextBlob(self: *ResourceManifest, keys: TextBlobResourceKeys, blob: *const TextBlob) !void {
        try self.putTextAtlas(keys.atlas, blob.atlas);
        if (keys.paint) |paint_key| try self.putTextBlobPaint(paint_key, blob);
    }

    pub fn putPathPicture(self: *ResourceManifest, key_value: anytype, picture: *const PathPicture) !void {
        try self.putPathPictureOptions(key_value, picture, .{});
    }

    pub fn putPathPictureOptions(self: *ResourceManifest, key_value: anytype, picture: *const PathPicture, options: PathPictureOptions) !void {
        try self.put(.{ .path_picture = .{
            .key = resourceKey(key_value),
            .picture = picture,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putImage(self: *ResourceManifest, key_value: anytype, image: *const Image) !void {
        try self.put(.{ .image = .{ .key = resourceKey(key_value), .image = image } });
    }

    fn put(self: *ResourceManifest, entry: Entry) !void {
        const key = entryKey(entry);
        for (self.entries[0..self.len], 0..) |existing, i| {
            if (entryKey(existing).eql(key)) {
                self.entries[i] = entry;
                return;
            }
        }
        if (self.len >= self.entries.len) return error.ResourceManifestFull;
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

    pub fn slice(self: *const ResourceManifest) []const Entry {
        return self.entries[0..self.len];
    }

    pub fn estimateUploadFootprint(self: *const ResourceManifest) !ResourceFootprint {
        return @import("footprint.zig").resourceManifestUploadFootprint(self);
    }
};
