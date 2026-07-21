const std = @import("std");

/// An image paint's texel payload. The bytes are OPAQUE to snail's core:
/// it never decodes them, and the bytes-per-texel is implied by
/// `texels.len / (width * height)`. The device that samples them defines
/// the format contract:
///
/// - GPU backends: the host uploads `texels` into a texture array layer of
///   its choosing; the only requirement is that SAMPLING YIELDS LINEAR
///   color (e.g. sRGB bytes in an `SRGB8_ALPHA8`/`R8G8B8A8_SRGB` texture,
///   or pre-linearized data in a UNORM/float format). Alpha is straight
///   (non-premultiplied).
/// - `snail-raster` (the CPU renderer) documents its accepted format on
///   its own module: 4 bytes/texel sRGBA, decoded to linear per tap.
pub const Image = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    /// Immutable texel bytes, row-major, tightly packed. Mutation requires
    /// constructing a new Image so content stamps remain meaningful.
    texels: []const u8,

    /// Copies `texels`. Fails unless the length is a nonzero whole number
    /// of bytes per texel times `width * height`.
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, texels: []const u8) !Image {
        if (width == 0 or height == 0) return error.InvalidImageData;
        const px_count = std.math.mul(usize, width, height) catch return error.InvalidImageData;
        if (texels.len == 0 or texels.len % px_count != 0) return error.InvalidImageData;
        const owned = try allocator.dupe(u8, texels);
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .texels = owned,
        };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.texels);
        self.* = undefined;
    }

    pub fn bytesPerTexel(self: *const Image) usize {
        return self.texels.len / (@as(usize, self.width) * @as(usize, self.height));
    }
};

test "Image validates texel payload length" {
    const a = std.testing.allocator;
    var img = try Image.init(a, 2, 2, &[_]u8{0} ** 16);
    defer img.deinit();
    try std.testing.expectEqual(@as(usize, 4), img.bytesPerTexel());
    try std.testing.expectError(error.InvalidImageData, Image.init(a, 2, 2, &[_]u8{0} ** 15));
    try std.testing.expectError(error.InvalidImageData, Image.init(a, 0, 2, &[_]u8{0} ** 8));
    try std.testing.expectError(error.InvalidImageData, Image.init(a, 2, 2, &.{}));
}
