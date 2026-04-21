//! .snail preprocessed font format.
//!
//! Binary layout (all fields little-endian):
//!   Header (32 bytes)
//!   GlyphEntry[glyph_count]
//!   curve_data: u16[curve_texels * 4]   (RGBA16F, directly uploadable)
//!   band_data:  u16[band_texels * 2]    (RG16UI, directly uploadable)
//!
//! Designed for mmap + direct GPU upload with zero parsing.

const std = @import("std");
const snail = @import("../snail.zig");
const band_tex = @import("../render/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");

const MAGIC = [4]u8{ 'S', 'N', 'A', 'L' };
const VERSION: u16 = 1;

const Header = extern struct {
    magic: [4]u8,
    version: u16,
    units_per_em: u16,
    glyph_count: u32,
    curve_texels: u32, // total texels in curve texture (width * height)
    curve_width: u16,
    curve_height: u16,
    band_texels: u32,
    band_width: u16,
    band_height: u16,
    _pad: [4]u8,
};

const GlyphEntry = extern struct {
    glyph_id: u16,
    advance_width: u16,
    bbox_min_x: f32,
    bbox_min_y: f32,
    bbox_max_x: f32,
    bbox_max_y: f32,
    band_glyph_x: u16,
    band_glyph_y: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

/// Serialize an Atlas to a byte buffer. Caller owns returned memory.
pub fn serialize(allocator: std.mem.Allocator, atlas: *const snail.Atlas, units_per_em: u16) ![]u8 {
    var compacted: ?snail.Atlas = null;
    defer if (compacted) |*owned| owned.deinit();
    const source = blk: {
        if (atlas.pageCount() == 1) break :blk atlas;
        compacted = try atlas.compact();
        break :blk &compacted.?;
    };
    const page = source.page(0);
    const glyph_count: u32 = @intCast(source.glyph_map.count());

    const header_size = @sizeOf(Header);
    const glyph_size = @as(usize, glyph_count) * @sizeOf(GlyphEntry);
    const curve_size = page.curve_data.len * 2;
    const band_size = page.band_data.len * 2;
    const total = header_size + glyph_size + curve_size + band_size;

    var buf = try allocator.alloc(u8, total);
    errdefer allocator.free(buf);

    // Header
    const header = Header{
        .magic = MAGIC,
        .version = VERSION,
        .units_per_em = units_per_em,
        .glyph_count = glyph_count,
        .curve_texels = page.curve_width * page.curve_height,
        .curve_width = @intCast(page.curve_width),
        .curve_height = @intCast(page.curve_height),
        .band_texels = page.band_width * page.band_height,
        .band_width = @intCast(page.band_width),
        .band_height = @intCast(page.band_height),
        ._pad = .{0} ** 4,
    };
    @memcpy(buf[0..header_size], std.mem.asBytes(&header));

    // Glyph entries
    var offset: usize = header_size;
    var it = source.glyph_map.iterator();
    while (it.next()) |entry| {
        const gid = entry.key_ptr.*;
        const info = entry.value_ptr.*;
        const ge = GlyphEntry{
            .glyph_id = gid,
            .advance_width = info.advance_width,
            .bbox_min_x = info.bbox.min.x,
            .bbox_min_y = info.bbox.min.y,
            .bbox_max_x = info.bbox.max.x,
            .bbox_max_y = info.bbox.max.y,
            .band_glyph_x = info.band_entry.glyph_x,
            .band_glyph_y = info.band_entry.glyph_y,
            .h_band_count = info.band_entry.h_band_count,
            .v_band_count = info.band_entry.v_band_count,
            .band_scale_x = info.band_entry.band_scale_x,
            .band_scale_y = info.band_entry.band_scale_y,
            .band_offset_x = info.band_entry.band_offset_x,
            .band_offset_y = info.band_entry.band_offset_y,
        };
        @memcpy(buf[offset..][0..@sizeOf(GlyphEntry)], std.mem.asBytes(&ge));
        offset += @sizeOf(GlyphEntry);
    }

    // Curve data
    const curve_bytes: []const u8 = @as([*]const u8, @ptrCast(page.curve_data.ptr))[0..curve_size];
    @memcpy(buf[offset..][0..curve_size], curve_bytes);
    offset += curve_size;

    // Band data
    const band_bytes: []const u8 = @as([*]const u8, @ptrCast(page.band_data.ptr))[0..band_size];
    @memcpy(buf[offset..][0..band_size], band_bytes);

    return buf;
}

/// Write an Atlas to a .snail file.
pub fn write(atlas: *const snail.Atlas, font: *const snail.Font, path: [*:0]const u8) !void {
    var compacted: ?snail.Atlas = null;
    defer if (compacted) |*owned| owned.deinit();
    const source = blk: {
        if (atlas.pageCount() == 1) break :blk atlas;
        compacted = try atlas.compact();
        break :blk &compacted.?;
    };
    const page = source.page(0);
    const c_file = std.c.fopen(path, "wb") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(c_file);

    const glyph_count: u32 = @intCast(source.glyph_map.count());

    const header = Header{
        .magic = MAGIC,
        .version = VERSION,
        .units_per_em = font.unitsPerEm(),
        .glyph_count = glyph_count,
        .curve_texels = page.curve_width * page.curve_height,
        .curve_width = @intCast(page.curve_width),
        .curve_height = @intCast(page.curve_height),
        .band_texels = page.band_width * page.band_height,
        .band_width = @intCast(page.band_width),
        .band_height = @intCast(page.band_height),
        ._pad = .{0} ** 4,
    };

    if (std.c.fwrite(std.mem.asBytes(&header), @sizeOf(Header), 1, c_file) != 1) return error.WriteFailed;

    var it = source.glyph_map.iterator();
    while (it.next()) |entry| {
        const gid = entry.key_ptr.*;
        const info = entry.value_ptr.*;
        const ge = GlyphEntry{
            .glyph_id = gid,
            .advance_width = info.advance_width,
            .bbox_min_x = info.bbox.min.x,
            .bbox_min_y = info.bbox.min.y,
            .bbox_max_x = info.bbox.max.x,
            .bbox_max_y = info.bbox.max.y,
            .band_glyph_x = info.band_entry.glyph_x,
            .band_glyph_y = info.band_entry.glyph_y,
            .h_band_count = info.band_entry.h_band_count,
            .v_band_count = info.band_entry.v_band_count,
            .band_scale_x = info.band_entry.band_scale_x,
            .band_scale_y = info.band_entry.band_scale_y,
            .band_offset_x = info.band_entry.band_offset_x,
            .band_offset_y = info.band_entry.band_offset_y,
        };
        if (std.c.fwrite(std.mem.asBytes(&ge), @sizeOf(GlyphEntry), 1, c_file) != 1) return error.WriteFailed;
    }

    if (std.c.fwrite(page.curve_data.ptr, 2, page.curve_data.len, c_file) != page.curve_data.len) return error.WriteFailed;
    if (std.c.fwrite(page.band_data.ptr, 2, page.band_data.len, c_file) != page.band_data.len) return error.WriteFailed;
}

/// Load a .snail file into an Atlas. The returned atlas is ready for
/// Renderer.uploadAtlas(). Zero TTF parsing required.
pub fn load(allocator: std.mem.Allocator, data: []const u8) !snail.Atlas {
    if (data.len < @sizeOf(Header)) return error.InvalidSnailFile;

    const header: *const Header = @ptrCast(@alignCast(data.ptr));
    if (!std.mem.eql(u8, &header.magic, &MAGIC)) return error.InvalidSnailFile;
    if (header.version != VERSION) return error.UnsupportedVersion;

    // Validate dimensions
    if (header.curve_width == 0 or header.curve_height == 0) return error.InvalidSnailFile;
    if (header.band_width == 0 or header.band_height == 0) return error.InvalidSnailFile;

    const glyph_data_start = @sizeOf(Header);
    const glyph_data_end = glyph_data_start + @as(usize, header.glyph_count) * @sizeOf(GlyphEntry);
    const curve_u16_count = @as(usize, header.curve_texels) * 4;
    const curve_data_end = glyph_data_end + curve_u16_count * 2;
    const band_u16_count = @as(usize, header.band_texels) * 2;
    const band_data_end = curve_data_end + band_u16_count * 2;

    if (data.len < band_data_end) return error.InvalidSnailFile;

    // Build glyph map
    var glyph_map = std.AutoHashMap(u16, snail.Atlas.GlyphInfo).init(allocator);
    errdefer glyph_map.deinit();

    for (0..header.glyph_count) |i| {
        const ge_ptr: *const GlyphEntry = @ptrCast(@alignCast(data[glyph_data_start + i * @sizeOf(GlyphEntry) ..]));
        try glyph_map.put(ge_ptr.glyph_id, .{
            .bbox = .{
                .min = vec.Vec2.new(ge_ptr.bbox_min_x, ge_ptr.bbox_min_y),
                .max = vec.Vec2.new(ge_ptr.bbox_max_x, ge_ptr.bbox_max_y),
            },
            .advance_width = ge_ptr.advance_width,
            .band_entry = .{
                .glyph_x = ge_ptr.band_glyph_x,
                .glyph_y = ge_ptr.band_glyph_y,
                .h_band_count = ge_ptr.h_band_count,
                .v_band_count = ge_ptr.v_band_count,
                .band_scale_x = ge_ptr.band_scale_x,
                .band_scale_y = ge_ptr.band_scale_y,
                .band_offset_x = ge_ptr.band_offset_x,
                .band_offset_y = ge_ptr.band_offset_y,
            },
            .page_index = 0,
        });
    }

    // Copy texture data (so the atlas owns it and can free it)
    const curve_data = try allocator.alloc(u16, curve_u16_count);
    errdefer allocator.free(curve_data);
    const curve_src: [*]const u16 = @ptrCast(@alignCast(data[glyph_data_end..].ptr));
    @memcpy(curve_data, curve_src[0..curve_u16_count]);

    const band_data = try allocator.alloc(u16, band_u16_count);
    errdefer allocator.free(band_data);
    const band_src: [*]const u16 = @ptrCast(@alignCast(data[curve_data_end..].ptr));
    @memcpy(band_data, band_src[0..band_u16_count]);

    const page = try snail.AtlasPage.init(
        allocator,
        curve_data,
        header.curve_width,
        header.curve_height,
        band_data,
        header.band_width,
        header.band_height,
    );
    const pages = try allocator.alloc(*snail.AtlasPage, 1);
    pages[0] = page;

    return snail.Atlas.initFromParts(allocator, null, pages, glyph_map);
}

// ── Tests ──

const assets = @import("assets");

test "snail file roundtrip" {
    const allocator = std.testing.allocator;

    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();

    const codepoints = [_]u32{ 'A', 'B', 'C' };
    var atlas = try snail.Atlas.init(allocator, &font, &codepoints);
    defer atlas.deinit();

    // Serialize
    const data = try serialize(allocator, &atlas, font.unitsPerEm());
    defer allocator.free(data);

    // Load back
    var loaded = try load(allocator, data);
    defer loaded.deinit();

    // Verify glyph counts match
    try std.testing.expectEqual(atlas.glyph_map.count(), loaded.glyph_map.count());
    try std.testing.expectEqual(atlas.page(0).curve_width, loaded.page(0).curve_width);
    try std.testing.expectEqual(atlas.page(0).curve_height, loaded.page(0).curve_height);
    try std.testing.expectEqual(atlas.page(0).band_width, loaded.page(0).band_width);
    try std.testing.expectEqual(atlas.page(0).band_height, loaded.page(0).band_height);

    // Verify curve data matches
    try std.testing.expectEqualSlices(u16, atlas.page(0).curve_data, loaded.page(0).curve_data);
    try std.testing.expectEqualSlices(u16, atlas.page(0).band_data, loaded.page(0).band_data);

    // Verify glyph info roundtrips
    var it = atlas.glyph_map.iterator();
    while (it.next()) |entry| {
        const loaded_info = loaded.glyph_map.get(entry.key_ptr.*) orelse
            return error.MissingGlyph;
        const orig = entry.value_ptr.*;
        try std.testing.expectEqual(orig.advance_width, loaded_info.advance_width);
        try std.testing.expectApproxEqAbs(orig.bbox.min.x, loaded_info.bbox.min.x, 1e-6);
        try std.testing.expectApproxEqAbs(orig.bbox.max.y, loaded_info.bbox.max.y, 1e-6);
        try std.testing.expectEqual(orig.band_entry.h_band_count, loaded_info.band_entry.h_band_count);
    }
}

test "snail file rejects bad magic" {
    var bad_data_storage: [@sizeOf(Header) + @alignOf(Header)]u8 align(@alignOf(Header)) = .{0} ** (@sizeOf(Header) + @alignOf(Header));
    try std.testing.expectError(error.InvalidSnailFile, load(std.testing.allocator, &bad_data_storage));
}

test "snail file rejects truncated data" {
    try std.testing.expectError(error.InvalidSnailFile, load(std.testing.allocator, "short"));
}
