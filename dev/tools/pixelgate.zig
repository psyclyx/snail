//! pixelgate — gate a rendered TGA against a reference TGA by differing-
//! pixel count, with zero external dependencies (no ImageMagick), so it can
//! run on a bare CI machine that only executes prebuilt artifacts (the
//! Windows D3D11 job in .github/workflows/ci.yml).
//!
//!   pixelgate <reference.tga> <candidate.tga> <max_bad_pixels>
//!
//! A pixel is "bad" when the maximum RGB channel delta exceeds 4% of full
//! scale (>10/255) — the same rule as the CI ImageMagick gates
//! (`-threshold 4%` over the max-channel difference, alpha ignored).
//! Prints the bad-pixel count; exits 0 iff count <= max_bad_pixels.
//!
//! Understands exactly what the demos and `magick -compress None` write:
//! uncompressed truecolor TGA (type 2), 24- or 32-bit, top-left or
//! bottom-left origin. Alpha is ignored.

const std = @import("std");

/// Renders are ~1.5 MB; a 64 MiB cap is plenty and bounds a corrupt header.
const max_file_bytes = 64 * 1024 * 1024;

/// Bad iff max RGB channel delta > tolerance: 10/255 ≈ 3.9%, so ">4%" in
/// the ImageMagick-gate sense (a delta of 11 is the first failure).
const channel_tolerance: u8 = 10;

const Image = struct {
    width: u32,
    height: u32,
    /// Tightly packed RGB triplets, row 0 = top row.
    rgb: []u8,

    fn deinit(self: *Image, gpa: std.mem.Allocator) void {
        gpa.free(self.rgb);
        self.* = undefined;
    }
};

const DecodeError = error{
    TruncatedTga,
    UnsupportedTga,
    OutOfMemory,
};

/// Decode an uncompressed 24/32-bit truecolor TGA into top-first RGB.
fn decodeTga(gpa: std.mem.Allocator, bytes: []const u8) DecodeError!Image {
    if (bytes.len < 18) return error.TruncatedTga;
    const id_length: usize = bytes[0];
    const colormap_type = bytes[1];
    const image_type = bytes[2];
    if (colormap_type != 0 or image_type != 2) return error.UnsupportedTga;
    const width: u32 = std.mem.readInt(u16, bytes[12..14], .little);
    const height: u32 = std.mem.readInt(u16, bytes[14..16], .little);
    const bpp = bytes[16];
    const descriptor = bytes[17];
    if (width == 0 or height == 0) return error.UnsupportedTga;
    if (bpp != 24 and bpp != 32) return error.UnsupportedTga;
    if (descriptor & 0x10 != 0) return error.UnsupportedTga; // right-to-left rows
    const top_first = descriptor & 0x20 != 0;
    const src_pixel_bytes: usize = bpp / 8;

    const pixel_count = @as(usize, width) * height;
    const data_start = 18 + id_length;
    if (bytes.len < data_start + pixel_count * src_pixel_bytes) return error.TruncatedTga;
    const data = bytes[data_start..];

    const rgb = try gpa.alloc(u8, pixel_count * 3);
    errdefer gpa.free(rgb);
    for (0..height) |row| {
        const src_row = if (top_first) row else height - 1 - row;
        const src = data[src_row * width * src_pixel_bytes ..];
        const dst = rgb[row * width * 3 ..];
        for (0..width) |x| {
            // TGA stores BGR(A).
            dst[x * 3 + 0] = src[x * src_pixel_bytes + 2];
            dst[x * 3 + 1] = src[x * src_pixel_bytes + 1];
            dst[x * 3 + 2] = src[x * src_pixel_bytes + 0];
        }
    }
    return .{ .width = width, .height = height, .rgb = rgb };
}

/// Count pixels whose max RGB channel delta exceeds `tolerance`.
fn countBadPixels(a: Image, b: Image, tolerance: u8) error{SizeMismatch}!u64 {
    if (a.width != b.width or a.height != b.height) return error.SizeMismatch;
    var bad: u64 = 0;
    var i: usize = 0;
    while (i < a.rgb.len) : (i += 3) {
        var max_delta: u8 = 0;
        inline for (0..3) |ch| {
            const delta = if (a.rgb[i + ch] > b.rgb[i + ch])
                a.rgb[i + ch] - b.rgb[i + ch]
            else
                b.rgb[i + ch] - a.rgb[i + ch];
            max_delta = @max(max_delta, delta);
        }
        if (max_delta > tolerance) bad += 1;
    }
    return bad;
}

fn loadTga(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !Image {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_bytes)) catch |err| {
        std.debug.print("pixelgate: cannot read {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    defer gpa.free(bytes);
    return decodeTga(gpa, bytes) catch |err| {
        std.debug.print("pixelgate: cannot decode {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        std.debug.print("usage: {s} <reference.tga> <candidate.tga> <max_bad_pixels>\n", .{if (args.len > 0) args[0] else "pixelgate"});
        std.process.exit(2);
    }
    const max_bad = std.fmt.parseInt(u64, args[3], 10) catch {
        std.debug.print("pixelgate: max_bad_pixels must be a non-negative integer, got '{s}'\n", .{args[3]});
        std.process.exit(2);
    };

    var reference = try loadTga(init.io, gpa, args[1]);
    defer reference.deinit(gpa);
    var candidate = try loadTga(init.io, gpa, args[2]);
    defer candidate.deinit(gpa);

    const bad = countBadPixels(reference, candidate, channel_tolerance) catch {
        std.debug.print("pixelgate: size mismatch: {s} is {d}x{d}, {s} is {d}x{d}\n", .{
            args[1], reference.width, reference.height,
            args[2], candidate.width, candidate.height,
        });
        std.process.exit(1);
    };
    std.debug.print("pixelgate: {d} pixels over 4% max-channel delta (threshold {d})\n", .{ bad, max_bad });
    if (bad > max_bad) std.process.exit(1);
}

// ── Tests ──

/// Encode top-first RGB triplets as a TGA byte stream for decoder tests.
fn encodeTga(
    gpa: std.mem.Allocator,
    width: u16,
    height: u16,
    rgb: []const u8,
    bpp: u8,
    top_first: bool,
) ![]u8 {
    std.debug.assert(rgb.len == @as(usize, width) * height * 3);
    const pixel_bytes: usize = bpp / 8;
    const out = try gpa.alloc(u8, 18 + @as(usize, width) * height * pixel_bytes);
    @memset(out[0..18], 0);
    out[2] = 2;
    std.mem.writeInt(u16, out[12..14], width, .little);
    std.mem.writeInt(u16, out[14..16], height, .little);
    out[16] = bpp;
    out[17] = if (top_first) 0x20 else 0;
    if (bpp == 32) out[17] |= 8; // alpha depth bits
    for (0..height) |row| {
        const dst_row = if (top_first) row else @as(usize, height) - 1 - row;
        const src = rgb[row * width * 3 ..];
        const dst = out[18 + dst_row * width * pixel_bytes ..];
        for (0..width) |x| {
            dst[x * pixel_bytes + 0] = src[x * 3 + 2];
            dst[x * pixel_bytes + 1] = src[x * 3 + 1];
            dst[x * pixel_bytes + 2] = src[x * 3 + 0];
            if (pixel_bytes == 4) dst[x * pixel_bytes + 3] = 0xff;
        }
    }
    return out;
}

const test_rgb = [_]u8{
    10, 20, 30, 40, 50, 60, // top row
    200, 210, 220, 250, 240, 230, // bottom row
};

test "decode 24-bit bottom-left and 32-bit top-left agree" {
    const gpa = std.testing.allocator;
    inline for (.{ .{ 24, false }, .{ 24, true }, .{ 32, false }, .{ 32, true } }) |case| {
        const bytes = try encodeTga(gpa, 2, 2, &test_rgb, case[0], case[1]);
        defer gpa.free(bytes);
        var image = try decodeTga(gpa, bytes);
        defer image.deinit(gpa);
        try std.testing.expectEqual(@as(u32, 2), image.width);
        try std.testing.expectEqual(@as(u32, 2), image.height);
        try std.testing.expectEqualSlices(u8, &test_rgb, image.rgb);
    }
}

test "decode rejects malformed input" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.TruncatedTga, decodeTga(gpa, &[_]u8{0} ** 17));
    const good = try encodeTga(gpa, 2, 2, &test_rgb, 24, true);
    defer gpa.free(good);
    try std.testing.expectError(error.TruncatedTga, decodeTga(gpa, good[0 .. good.len - 1]));
    var rle = try gpa.dupe(u8, good);
    defer gpa.free(rle);
    rle[2] = 10; // RLE truecolor
    try std.testing.expectError(error.UnsupportedTga, decodeTga(gpa, rle));
    var bad_bpp = try gpa.dupe(u8, good);
    defer gpa.free(bad_bpp);
    bad_bpp[16] = 16;
    try std.testing.expectError(error.UnsupportedTga, decodeTga(gpa, bad_bpp));
}

test "countBadPixels honors the >tolerance rule" {
    const gpa = std.testing.allocator;
    const base_bytes = try encodeTga(gpa, 2, 2, &test_rgb, 24, true);
    defer gpa.free(base_bytes);
    var base = try decodeTga(gpa, base_bytes);
    defer base.deinit(gpa);

    // Identical images: zero bad pixels.
    try std.testing.expectEqual(@as(u64, 0), try countBadPixels(base, base, channel_tolerance));

    // Delta of exactly `tolerance` on one channel: still fine; one more: bad.
    var shifted_rgb = test_rgb;
    shifted_rgb[1] += channel_tolerance;
    const at_bytes = try encodeTga(gpa, 2, 2, &shifted_rgb, 24, true);
    defer gpa.free(at_bytes);
    var at = try decodeTga(gpa, at_bytes);
    defer at.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 0), try countBadPixels(base, at, channel_tolerance));

    shifted_rgb[1] += 1;
    shifted_rgb[9] = 0; // second bad pixel, huge delta
    const over_bytes = try encodeTga(gpa, 2, 2, &shifted_rgb, 24, true);
    defer gpa.free(over_bytes);
    var over = try decodeTga(gpa, over_bytes);
    defer over.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 2), try countBadPixels(base, over, channel_tolerance));

    // Origin flip must not change the verdict (decode normalizes rows).
    const flipped_bytes = try encodeTga(gpa, 2, 2, &test_rgb, 32, false);
    defer gpa.free(flipped_bytes);
    var flipped = try decodeTga(gpa, flipped_bytes);
    defer flipped.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 0), try countBadPixels(base, flipped, channel_tolerance));
}

test "countBadPixels rejects size mismatch" {
    const gpa = std.testing.allocator;
    const two_by_two = try encodeTga(gpa, 2, 2, &test_rgb, 24, true);
    defer gpa.free(two_by_two);
    var a = try decodeTga(gpa, two_by_two);
    defer a.deinit(gpa);
    const one_by_four = try encodeTga(gpa, 1, 4, &test_rgb, 24, true);
    defer gpa.free(one_by_four);
    var b = try decodeTga(gpa, one_by_four);
    defer b.deinit(gpa);
    try std.testing.expectError(error.SizeMismatch, countBadPixels(a, b, channel_tolerance));
}
