const std = @import("std");
const band_tex = @import("../render/format/band_texture.zig");
const render_abi = @import("../render/format/abi.zig");

pub const PaintRecordKind = render_abi.PaintRecordKind;

pub const info_width: u32 = render_abi.paint_info_width;
pub const texels_per_record: u32 = render_abi.paint_texels_per_record;
pub const tag_solid: f32 = render_abi.paintRecordTag(.solid);
pub const tag_linear_gradient: f32 = render_abi.paintRecordTag(.linear_gradient);
pub const tag_radial_gradient: f32 = render_abi.paintRecordTag(.radial_gradient);
pub const tag_conic_gradient: f32 = render_abi.paintRecordTag(.conic_gradient);
pub const tag_image: f32 = render_abi.paintRecordTag(.image);
pub const tag_composite_group: f32 = render_abi.paintRecordTag(.composite_group);

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
    return render_abi.paintRecordTag(switch (paint) {
        .solid => .solid,
        .linear_gradient => .linear_gradient,
        .radial_gradient => .radial_gradient,
        .conic_gradient => .conic_gradient,
        .image => .image,
    });
}

/// Bit 15 of texel 0.x is used to encode the fill rule for this record:
/// 0 = non-zero, 1 = even-odd. `glyph_x` is the curve atlas band-texture
/// x coordinate and is bounded by `BAND_TEX_WIDTH` (4096), so the bit
/// is structurally free.
pub const FILL_RULE_BIT: u16 = 1 << 15;

pub fn write(
    data: []f32,
    texel_width: u32,
    texel_offset: u32,
    band_entry: band_tex.GlyphBandEntry,
    paint: anytype,
    fill_rule_bit: u16,
) void {
    writeBandHeader(data, texel_width, texel_offset, band_entry, tagFor(paint), fill_rule_bit);
    switch (paint) {
        // Solid colors store linear in the layer-info texture so the
        // path/colr fragment shaders skip a per-pixel `srgbDecode`.
        // Matches the gradient endpoint convention.
        .solid => |color| setTexel(data, texel_width, texel_offset + 2, srgbToLinearColor(color)),
        .linear_gradient => |gradient| writeLinearGradient(data, texel_width, texel_offset, gradient),
        .radial_gradient => |gradient| writeRadialGradient(data, texel_width, texel_offset, gradient),
        .conic_gradient => |gradient| writeConicGradient(data, texel_width, texel_offset, gradient),
        .image => |image| writeImagePaint(data, texel_width, texel_offset, image),
    }
}

fn writeBandHeader(data: []f32, texel_width: u32, texel_offset: u32, band_entry: band_tex.GlyphBandEntry, tag: f32, fill_rule_bit: u16) void {
    const packed_bands = render_abi.packBandCounts(band_entry.h_band_count, band_entry.v_band_count);
    std.debug.assert(band_entry.glyph_x < FILL_RULE_BIT);
    const glyph_x_with_fill_rule: u16 = band_entry.glyph_x | fill_rule_bit;
    setTexel(data, texel_width, texel_offset + 0, .{
        @floatFromInt(glyph_x_with_fill_rule),
        @floatFromInt(band_entry.glyph_y),
        @bitCast(packed_bands),
        tag,
    });
    setTexel(data, texel_width, texel_offset + 1, .{
        band_entry.band_scale_x,
        band_entry.band_scale_y,
        band_entry.band_offset_x,
        band_entry.band_offset_y,
    });
}

fn writeLinearGradient(data: []f32, texel_width: u32, texel_offset: u32, gradient: anytype) void {
    setTexel(data, texel_width, texel_offset + 2, .{
        gradient.start.x,
        gradient.start.y,
        gradient.end.x,
        gradient.end.y,
    });
    // Endpoints are stored linear (like solid), so the renderer interpolates
    // in linear light — consistent with the rest of the pipeline and free of
    // the sRGB-space "muddy midpoint" for complementary colors.
    setTexel(data, texel_width, texel_offset + 3, srgbToLinearColor(gradient.start_color));
    setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(gradient.end_color));
    setTexel(data, texel_width, texel_offset + 5, .{
        @floatFromInt(@intFromEnum(gradient.extend)),
        0,
        0,
        0,
    });
}

fn writeRadialGradient(data: []f32, texel_width: u32, texel_offset: u32, gradient: anytype) void {
    setTexel(data, texel_width, texel_offset + 2, .{
        gradient.center.x,
        gradient.center.y,
        gradient.radius,
        @floatFromInt(@intFromEnum(gradient.extend)),
    });
    // Linear-stored endpoints; see writeLinearGradient.
    setTexel(data, texel_width, texel_offset + 3, srgbToLinearColor(gradient.inner_color));
    setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(gradient.outer_color));
    setTexel(data, texel_width, texel_offset + 5, .{ 0, 0, 0, 0 });
}

fn writeConicGradient(data: []f32, texel_width: u32, texel_offset: u32, gradient: anytype) void {
    setTexel(data, texel_width, texel_offset + 2, .{
        gradient.center.x,
        gradient.center.y,
        gradient.start_angle,
        @floatFromInt(@intFromEnum(gradient.extend)),
    });
    // Linear-stored endpoints; see writeLinearGradient.
    setTexel(data, texel_width, texel_offset + 3, srgbToLinearColor(gradient.start_color));
    setTexel(data, texel_width, texel_offset + 4, srgbToLinearColor(gradient.end_color));
    setTexel(data, texel_width, texel_offset + 5, .{ 0, 0, 0, 0 });
}

fn writeImagePaint(data: []f32, texel_width: u32, texel_offset: u32, image: anytype) void {
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
    // texel+4 is unused (image color modulation is per-instance tint, not a
    // per-paint field). Kept zero to preserve the fixed 6-texel record.
    setTexel(data, texel_width, texel_offset + 4, .{ 0, 0, 0, 0 });
    setTexel(data, texel_width, texel_offset + 5, .{
        0,
        0,
        @floatFromInt(@intFromEnum(image.extend_x)),
        @floatFromInt(@intFromEnum(image.extend_y)),
    });
}
