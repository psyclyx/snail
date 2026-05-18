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

    pub fn putTextAtlas(self: *ResourceManifest, key: ResourceKey, atlas: *const TextAtlas) !void {
        try self.putTextAtlasOptions(key, atlas, .{});
    }

    pub fn putTextAtlasOptions(self: *ResourceManifest, key: ResourceKey, atlas: *const TextAtlas, options: TextAtlasOptions) !void {
        try self.put(.{ .text_atlas = .{
            .key = key,
            .atlas = atlas,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putTextPaint(self: *ResourceManifest, key: ResourceKey, blob: *const TextBlob) !void {
        try self.put(.{ .text_paint = .{
            .key = key,
            .blob = blob,
        } });
    }

    pub fn textBlobResourceKeys(atlas_key: ResourceKey, blob_key: ResourceKey, blob: *const TextBlob) TextBlobResourceKeys {
        return .{
            .atlas = atlas_key,
            .paint = if (blob.hasPaintRecords()) derivedResourceKey(blob_key, "text_paint") else null,
        };
    }

    pub fn putPathPicture(self: *ResourceManifest, key: ResourceKey, picture: *const PathPicture) !void {
        try self.putPathPictureOptions(key, picture, .{});
    }

    pub fn putPathPictureOptions(self: *ResourceManifest, key: ResourceKey, picture: *const PathPicture, options: PathPictureOptions) !void {
        try self.put(.{ .path_picture = .{
            .key = key,
            .picture = picture,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putImage(self: *ResourceManifest, key: ResourceKey, image: *const Image) !void {
        try self.put(.{ .image = .{ .key = key, .image = image } });
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
