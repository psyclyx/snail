const std = @import("std");
const footprint_types = @import("resources/footprint_types.zig");
const upload_common = @import("render/format/upload_common.zig");

pub const Image = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    /// Immutable sRGBA8 pixels. Initialize with initSrgba8; mutation requires
    /// constructing a new Image so content stamps remain meaningful.
    pixels: []const u8,

    pub fn initSrgba8(allocator: std.mem.Allocator, width: u32, height: u32, pixels: []const u8) !Image {
        if (width == 0 or height == 0) return error.InvalidImageData;
        const px_count = std.math.mul(usize, width, height) catch return error.InvalidImageData;
        const byte_count = std.math.mul(usize, px_count, 4) catch return error.InvalidImageData;
        if (pixels.len != byte_count) return error.InvalidImageData;
        const owned = try allocator.dupe(u8, pixels);
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = owned,
        };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn pixelSlice(self: *const Image) []const u8 {
        return self.pixels;
    }

    pub fn fingerprint(self: *const Image) upload_common.ImageFingerprint {
        const layout = imageLayoutHash(self);
        return .{
            .layout = layout,
            .content = std.hash.Wyhash.hash(layout, self.pixelSlice()),
        };
    }

    pub fn uploadFootprint(self: *const Image) footprint_types.ResourceFootprint {
        const bytes = textureBytes(self);
        return .{
            .image_bytes_used = bytes,
            .image_bytes_allocated = allocatedBytes(self),
        };
    }
};

pub fn textureBytes(image: *const Image) usize {
    return @as(usize, image.width) * image.height * 4;
}

pub fn allocatedBytes(image: *const Image) usize {
    return @as(usize, upload_common.imageExtentCapacity(image.width)) *
        @as(usize, upload_common.imageExtentCapacity(image.height)) *
        @as(usize, upload_common.imageCapacity(1)) *
        4;
}

fn imageLayoutHash(image: *const Image) u64 {
    var hash = mix64(0x40f2_93aa_f86e_75b1, image.width);
    hash = mix64(hash, image.height);
    hash = mix64(hash, image.pixelSlice().len);
    return hash;
}

fn mix64(seed: u64, value: anytype) u64 {
    var x = seed ^ @as(u64, @intCast(value));
    x +%= 0x9e37_79b9_7f4a_7c15;
    x = (x ^ (x >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    x = (x ^ (x >> 27)) *% 0x94d0_49bb_1331_11eb;
    return x ^ (x >> 31);
}
