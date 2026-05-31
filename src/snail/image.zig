const std = @import("std");

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
};
