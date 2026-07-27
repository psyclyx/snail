const std = @import("std");
const gl = @import("gl.zig").gl;

const png_signature = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

pub fn writeTga(path: [*:0]const u8, pixels: []const u8, width: u32, height: u32) !void {
    const c_file = std.c.fopen(path, "wb") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(c_file);

    var header: [18]u8 = .{0} ** 18;
    header[2] = 2;
    header[12] = @intCast(width & 0xFF);
    header[13] = @intCast((width >> 8) & 0xFF);
    header[14] = @intCast(height & 0xFF);
    header[15] = @intCast((height >> 8) & 0xFF);
    header[16] = 32;
    header[17] = 0x28;

    try fwriteAll(c_file, header[0..]);

    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const src_row = height - 1 - row;
        const src_off = src_row * width * 4;

        var col: u32 = 0;
        while (col < width) : (col += 1) {
            const i = src_off + col * 4;
            const bgra = [4]u8{ pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3] };
            try fwriteAll(c_file, bgra[0..]);
        }
    }
}

pub fn captureFramebuffer(allocator: std.mem.Allocator, width: u32, height: u32) ![]u8 {
    const size = width * height * 4;
    const pixels = try allocator.alloc(u8, size);
    gl.glReadPixels(0, 0, @intCast(width), @intCast(height), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, pixels.ptr);
    return pixels;
}

pub fn writePng(
    allocator: std.mem.Allocator,
    path: [*:0]const u8,
    pixels: []const u8,
    width: u32,
    height: u32,
) !void {
    const row_bytes = @as(usize, width) * 4;
    const raw_len = (@as(usize, width) * 4 + 1) * @as(usize, height);
    var raw = try allocator.alloc(u8, raw_len);
    defer allocator.free(raw);

    var dst: usize = 0;
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        raw[dst] = 0; // PNG filter type: none.
        dst += 1;
        const src_row = height - 1 - row;
        const src_off = @as(usize, src_row) * row_bytes;
        @memcpy(raw[dst .. dst + row_bytes], pixels[src_off .. src_off + row_bytes]);
        dst += row_bytes;
    }

    const max_block: usize = 65535;
    const block_count = (raw.len + max_block - 1) / max_block;
    const idat_len = 2 + raw.len + block_count * 5 + 4;
    var idat = try allocator.alloc(u8, idat_len);
    defer allocator.free(idat);

    var pos: usize = 0;
    idat[pos] = 0x78;
    idat[pos + 1] = 0x01; // zlib header: deflate, no compression.
    pos += 2;

    var remaining = raw.len;
    var raw_pos: usize = 0;
    while (remaining > 0) {
        const block_len = @min(remaining, max_block);
        remaining -= block_len;
        const len16: u16 = @intCast(block_len);
        idat[pos] = if (remaining == 0) 1 else 0; // final uncompressed block.
        idat[pos + 1] = @intCast(len16 & 0xff);
        idat[pos + 2] = @intCast(len16 >> 8);
        const nlen = ~len16;
        idat[pos + 3] = @intCast(nlen & 0xff);
        idat[pos + 4] = @intCast(nlen >> 8);
        pos += 5;
        @memcpy(idat[pos .. pos + block_len], raw[raw_pos .. raw_pos + block_len]);
        pos += block_len;
        raw_pos += block_len;
    }
    writeBe32(idat[pos .. pos + 4], adler32(raw));
    pos += 4;
    std.debug.assert(pos == idat.len);

    const c_file = std.c.fopen(path, "wb") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(c_file);

    try fwriteAll(c_file, png_signature[0..]);

    var ihdr: [13]u8 = .{0} ** 13;
    writeBe32(ihdr[0..4], width);
    writeBe32(ihdr[4..8], height);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // RGBA
    try writeChunk(c_file, "IHDR", ihdr[0..]);
    try writeChunk(c_file, "IDAT", idat);
    try writeChunk(c_file, "IEND", &.{});
}

fn fwriteAll(c_file: *std.c.FILE, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    if (std.c.fwrite(bytes.ptr, 1, bytes.len, c_file) != bytes.len) return error.FileWriteFailed;
}

fn writeChunk(c_file: *std.c.FILE, kind: *const [4]u8, data: []const u8) !void {
    var len_buf: [4]u8 = undefined;
    writeBe32(len_buf[0..], @intCast(data.len));
    try fwriteAll(c_file, len_buf[0..]);
    try fwriteAll(c_file, kind[0..]);
    try fwriteAll(c_file, data);

    var crc = std.hash.Crc32.init();
    crc.update(kind[0..]);
    crc.update(data);
    var crc_buf: [4]u8 = undefined;
    writeBe32(crc_buf[0..], crc.final());
    try fwriteAll(c_file, crc_buf[0..]);
}

fn writeBe32(dst: []u8, value: u32) void {
    std.debug.assert(dst.len >= 4);
    dst[0] = @intCast(value >> 24);
    dst[1] = @intCast((value >> 16) & 0xff);
    dst[2] = @intCast((value >> 8) & 0xff);
    dst[3] = @intCast(value & 0xff);
}

fn adler32(bytes: []const u8) u32 {
    const mod_adler = 65521;
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (bytes) |byte| {
        s1 = (s1 + byte) % mod_adler;
        s2 = (s2 + s1) % mod_adler;
    }
    return (s2 << 16) | s1;
}
