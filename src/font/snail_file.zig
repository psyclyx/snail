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

/// Write an Atlas to a .snail file.
pub fn write(atlas: *const snail.Atlas, font: *const snail.Font, path: [*:0]const u8) void {
    const c_file = std.c.fopen(path, "wb") orelse return;
    defer _ = std.c.fclose(c_file);

    // Count glyphs
    const glyph_count: u32 = @intCast(atlas.glyph_map.count());

    const header = Header{
        .magic = MAGIC,
        .version = VERSION,
        .units_per_em = font.unitsPerEm(),
        .glyph_count = glyph_count,
        .curve_texels = atlas.curve_width * atlas.curve_height,
        .curve_width = @intCast(atlas.curve_width),
        .curve_height = @intCast(atlas.curve_height),
        .band_texels = atlas.band_width * atlas.band_height,
        .band_width = @intCast(atlas.band_width),
        .band_height = @intCast(atlas.band_height),
        ._pad = .{0} ** 4,
    };

    _ = std.c.fwrite(std.mem.asBytes(&header), @sizeOf(Header), 1, c_file);

    // Write glyph entries
    var it = atlas.glyph_map.iterator();
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
        _ = std.c.fwrite(std.mem.asBytes(&ge), @sizeOf(GlyphEntry), 1, c_file);
    }

    // Write curve data (directly GPU-uploadable)
    _ = std.c.fwrite(atlas.curve_data.ptr, 2, atlas.curve_data.len, c_file);

    // Write band data
    _ = std.c.fwrite(atlas.band_data.ptr, 2, atlas.band_data.len, c_file);
}

/// Load a .snail file into an Atlas. The returned atlas is ready for
/// Renderer.uploadAtlas(). Zero TTF parsing required.
pub fn load(allocator: std.mem.Allocator, data: []const u8) !snail.Atlas {
    if (data.len < @sizeOf(Header)) return error.InvalidSnailFile;

    const header: *const Header = @ptrCast(@alignCast(data.ptr));
    if (!std.mem.eql(u8, &header.magic, &MAGIC)) return error.InvalidSnailFile;
    if (header.version != VERSION) return error.UnsupportedVersion;

    const glyph_data_start = @sizeOf(Header);
    const glyph_data_end = glyph_data_start + @as(usize, header.glyph_count) * @sizeOf(GlyphEntry);
    const curve_data_end = glyph_data_end + @as(usize, header.curve_texels) * 4 * 2; // u16 * 4 channels
    const band_data_end = curve_data_end + @as(usize, header.band_texels) * 2 * 2; // u16 * 2 channels

    if (data.len < band_data_end) return error.InvalidSnailFile;

    // Build glyph map
    var glyph_map = std.AutoHashMap(u16, snail.Atlas.GlyphInfo).init(allocator);
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
        });
    }

    // Copy texture data (so the atlas owns it and can free it)
    const curve_u16_count = @as(usize, header.curve_texels) * 4;
    const curve_data = try allocator.alloc(u16, curve_u16_count);
    const curve_src: [*]const u16 = @ptrCast(@alignCast(data[glyph_data_end..].ptr));
    @memcpy(curve_data, curve_src[0..curve_u16_count]);

    const band_u16_count = @as(usize, header.band_texels) * 2;
    const band_data = try allocator.alloc(u16, band_u16_count);
    const band_src: [*]const u16 = @ptrCast(@alignCast(data[curve_data_end..].ptr));
    @memcpy(band_data, band_src[0..band_u16_count]);

    return .{
        .allocator = allocator,
        .font = undefined, // not available from .snail files
        .curve_data = curve_data,
        .curve_width = header.curve_width,
        .curve_height = header.curve_height,
        .band_data = band_data,
        .band_width = header.band_width,
        .band_height = header.band_height,
        .glyph_map = glyph_map,
        .shaper = null,
    };
}
