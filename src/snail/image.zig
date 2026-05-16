const std = @import("std");
const paint_mod = @import("paint.zig");
const upload_common = @import("renderer/upload_common.zig");
const upload_mod = @import("upload.zig");

pub const ImageFilter = paint_mod.ImageFilter;
pub const ImagePaint = paint_mod.ImagePaint;

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

    pub fn uploadFootprint(self: *const Image) upload_mod.ResourceFootprint {
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
    return @as(usize, upload_common.heightCapacity(image.width)) *
        @as(usize, upload_common.heightCapacity(image.height)) *
        @as(usize, upload_common.imageCapacity(1)) *
        4;
}
