const std = @import("std");
const band_tex = @import("render/format/band_texture.zig");

pub const info_width: u32 = 4096;
pub const texels_per_record: u32 = 6;
pub const tag_solid: f32 = -1.0;
pub const tag_linear_gradient: f32 = -2.0;
pub const tag_radial_gradient: f32 = -3.0;
pub const tag_image: f32 = -4.0;
pub const tag_composite_group: f32 = -5.0;

pub fn infoWidth(texel_count: u32) u32 {
    return @min(@max(texel_count, 1), info_width);
}

pub fn setTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
    const texel_x = texel_offset % texel_width;
    const texel_y = texel_offset / texel_width;
    const base = (texel_y * texel_width + texel_x) * 4;
    data[base + 0] = value[0];
    data[base + 1] = value[1];
    data[base + 2] = value[2];
    data[base + 3] = value[3];
}

pub fn readTexel(data: []const f32, texel_width: u32, texel_offset: u32) [4]f32 {
    const texel_x = texel_offset % texel_width;
    const texel_y = texel_offset / texel_width;
    const base = (texel_y * texel_width + texel_x) * 4;
    return .{
        data[base + 0],
        data[base + 1],
        data[base + 2],
        data[base + 3],
    };
}

pub fn srgbToLinear(v: f32) f32 {
    if (v <= 0.04045) return v / 12.92;
    return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn srgbToLinearColor(color: [4]f32) [4]f32 {
    return .{ srgbToLinear(color[0]), srgbToLinear(color[1]), srgbToLinear(color[2]), color[3] };
}

pub fn tagFor(paint: anytype) f32 {
    return switch (paint) {
        .solid => tag_solid,
        .linear_gradient => tag_linear_gradient,
        .radial_gradient => tag_radial_gradient,
        .image => tag_image,
    };
}

pub fn write(
    data: []f32,
    texel_width: u32,
    texel_offset: u32,
    band_entry: band_tex.GlyphBandEntry,
    paint: anytype,
) void {
    const packed_bands: u32 = @as(u32, band_entry.h_band_count - 1) | (@as(u32, band_entry.v_band_count - 1) << 16);
    setTexel(data, texel_width, texel_offset + 0, .{
        @floatFromInt(band_entry.glyph_x),
        @floatFromInt(band_entry.glyph_y),
        @bitCast(packed_bands),
        tagFor(paint),
    });
    setTexel(data, texel_width, texel_offset + 1, .{
        band_entry.band_scale_x,
        band_entry.band_scale_y,
        band_entry.band_offset_x,
        band_entry.band_offset_y,
    });

    switch (paint) {
        .solid => |color| {
            setTexel(data, texel_width, texel_offset + 2, color);
        },
        .linear_gradient => |gradient| {
            setTexel(data, texel_width, texel_offset + 2, .{
                gradient.start.x,
                gradient.start.y,
                gradient.end.x,
                gradient.end.y,
            });
            setTexel(data, texel_width, texel_offset + 3, srgbToLinearColor(gradient.start_color));
            setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(gradient.end_color));
            setTexel(data, texel_width, texel_offset + 5, .{
                @floatFromInt(@intFromEnum(gradient.extend)),
                0,
                0,
                0,
            });
        },
        .radial_gradient => |gradient| {
            setTexel(data, texel_width, texel_offset + 2, .{
                gradient.center.x,
                gradient.center.y,
                gradient.radius,
                @floatFromInt(@intFromEnum(gradient.extend)),
            });
            setTexel(data, texel_width, texel_offset + 3, srgbToLinearColor(gradient.inner_color));
            setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(gradient.outer_color));
            setTexel(data, texel_width, texel_offset + 5, .{
                0,
                0,
                0,
                0,
            });
        },
        .image => |image| {
            setTexel(data, texel_width, texel_offset + 2, .{
                image.uv_transform.xx,
                image.uv_transform.xy,
                image.uv_transform.tx,
                0,
            });
            setTexel(data, texel_width, texel_offset + 3, .{
                image.uv_transform.yx,
                image.uv_transform.yy,
                image.uv_transform.ty,
                @floatFromInt(@intFromEnum(image.filter)),
            });
            setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(image.tint));
            setTexel(data, texel_width, texel_offset + 5, .{
                0,
                0,
                @floatFromInt(@intFromEnum(image.extend_x)),
                @floatFromInt(@intFromEnum(image.extend_y)),
            });
        },
    }
}
