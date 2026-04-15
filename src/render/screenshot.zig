const std = @import("std");
const platform = @import("platform.zig");
const gl = platform.gl;

/// Write raw RGBA pixels as a TGA file
pub fn writeTga(path: [*:0]const u8, pixels: []const u8, width: u32, height: u32) void {
    const c_file = std.c.fopen(path, "wb") orelse return;
    defer _ = std.c.fclose(c_file);

    // TGA header (18 bytes)
    var header: [18]u8 = .{0} ** 18;
    header[2] = 2; // uncompressed true-color
    header[12] = @intCast(width & 0xFF);
    header[13] = @intCast((width >> 8) & 0xFF);
    header[14] = @intCast(height & 0xFF);
    header[15] = @intCast((height >> 8) & 0xFF);
    header[16] = 32; // bits per pixel
    header[17] = 0x28; // top-left origin + 8 alpha bits

    _ = std.c.fwrite(&header, 1, 18, c_file);

    // TGA uses BGRA. Write row by row (flipping vertically).
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const src_row = height - 1 - row;
        const src_off = src_row * width * 4;

        var col: u32 = 0;
        while (col < width) : (col += 1) {
            const i = src_off + col * 4;
            const bgra = [4]u8{ pixels[i + 2], pixels[i + 1], pixels[i + 0], pixels[i + 3] };
            _ = std.c.fwrite(&bgra, 1, 4, c_file);
        }
    }
}

/// Capture the current framebuffer contents
pub fn captureFramebuffer(allocator: std.mem.Allocator, width: u32, height: u32) ![]u8 {
    const size = width * height * 4;
    const pixels = try allocator.alloc(u8, size);
    gl.glReadPixels(0, 0, @intCast(width), @intCast(height), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, pixels.ptr);
    return pixels;
}

/// Count non-zero pixels in RGBA data
pub fn countNonBlackPixels(pixels: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        if (pixels[i] > 0 or pixels[i + 1] > 0 or pixels[i + 2] > 0) {
            count += 1;
        }
    }
    return count;
}
