const std = @import("std");

/// Increment whenever persisted draw records or atlas textures become
/// incompatible with the shipped shader decoders.
pub const version: u32 = 2;

/// Both ordinary and special records carry a full u8 atlas-array layer.
pub const max_atlas_layers: u32 = std.math.maxInt(u8) + 1;

pub const SpecialLayerKind = enum(u8) {
    colr = 0,
    path = 1,
    tt_hinted_text = 2,
    /// Resolution-independent light autohinting: the slab record carries the
    /// base (unhinted) glyph location + per-axis warp knots; the shader warps
    /// the sample coordinate and runs normal coverage against the base glyph.
    autohint = 3,
};

pub const PaintRecordKind = enum(u8) {
    solid = 1,
    linear_gradient = 2,
    radial_gradient = 3,
    image = 4,
    composite_group = 5,
    conic_gradient = 6,
};

pub const paint_info_width: u32 = 4096;
pub const paint_texels_per_record: u32 = 6;

pub const composite_mode_source_over: u8 = 0;
pub const composite_mode_fill_stroke_inside: u8 = 1;

pub fn packGlyphLocation(x: u16, y: u16) u32 {
    return @as(u32, x) | (@as(u32, y) << 16);
}

pub fn glyphLocationX(word: u32) u16 {
    return @intCast(word & 0xffff);
}

pub fn glyphLocationY(word: u32) u16 {
    return @intCast(word >> 16);
}

const special_marker: u32 = @as(u32, 1) << 31;
const special_reserved_mask: u32 = 0x7c000000;

/// Ordinary glyph word: 4-bit `(count - 1)` values, then an 8-bit atlas layer.
pub fn regularGlyphWord(h_count: u16, v_count: u16, atlas_layer: u8) ?u32 {
    if (h_count == 0 or h_count > 16 or v_count == 0 or v_count > 16) return null;
    return @as(u32, h_count - 1) |
        (@as(u32, v_count - 1) << 4) |
        (@as(u32, atlas_layer) << 8);
}

/// Special glyph word: full layer count, semantic kind, atlas layer, and a
/// high marker bit. The marker cannot collide with an ordinary word because
/// ordinary words use only bits 0..15.
pub fn specialGlyphWord(layer_count: u16, kind: SpecialLayerKind, atlas_layer: u8) ?u32 {
    if (layer_count == 0) return null;
    return @as(u32, layer_count) |
        (@as(u32, @intFromEnum(kind)) << 16) |
        (@as(u32, atlas_layer) << 18) |
        special_marker;
}

pub fn glyphWordAtlasLayer(word: u32) u8 {
    return if (glyphWordIsSpecial(word))
        @intCast((word >> 18) & 0xff)
    else
        @intCast((word >> 8) & 0xff);
}

pub fn glyphWordIsSpecial(word: u32) bool {
    return word & special_marker != 0;
}

pub fn specialGlyphWordLayerCount(word: u32) u16 {
    return @intCast(word & 0xffff);
}

pub fn specialGlyphWordKind(word: u32) ?SpecialLayerKind {
    if (!glyphWordIsSpecial(word)) return null;
    if (word & special_reserved_mask != 0) return null;
    const raw: u8 = @intCast((word >> 16) & 0x3);
    return switch (raw) {
        @intFromEnum(SpecialLayerKind.colr) => .colr,
        @intFromEnum(SpecialLayerKind.path) => .path,
        @intFromEnum(SpecialLayerKind.tt_hinted_text) => .tt_hinted_text,
        @intFromEnum(SpecialLayerKind.autohint) => .autohint,
        else => null,
    };
}

pub fn regularGlyphWordHBandCount(word: u32) u16 {
    return @intCast((word & 0xf) + 1);
}

pub fn regularGlyphWordVBandCount(word: u32) u16 {
    return @intCast(((word >> 4) & 0xf) + 1);
}

pub const BandCounts = struct {
    h: u16,
    v: u16,
};

/// Pack non-zero band counts. Zero has no representation because each lane
/// stores `(count - 1)`.
pub fn packBandCounts(h: u16, v: u16) ?u32 {
    if (h == 0 or v == 0) return null;
    return @as(u32, h - 1) | (@as(u32, v - 1) << 16);
}

/// Decode packed band counts. A lane containing `0xffff` would denote 65536,
/// which does not fit in `BandCounts`; reject it instead of trapping on the
/// narrowing conversion.
pub fn unpackBandCounts(word: u32) ?BandCounts {
    const h_minus_one = word & 0xffff;
    const v_minus_one = word >> 16;
    if (h_minus_one == std.math.maxInt(u16) or v_minus_one == std.math.maxInt(u16)) return null;
    return .{
        .h = @intCast(h_minus_one + 1),
        .v = @intCast(v_minus_one + 1),
    };
}

pub fn paintRecordTag(kind: PaintRecordKind) f32 {
    return -@as(f32, @floatFromInt(@intFromEnum(kind)));
}

pub fn paintRecordKindFromTag(tag: f32) ?PaintRecordKind {
    if (!std.math.isFinite(tag) or tag >= 0.0) return null;
    const magnitude = -tag;
    if (magnitude < @intFromEnum(PaintRecordKind.solid) or
        magnitude > @intFromEnum(PaintRecordKind.conic_gradient) or
        @trunc(magnitude) != magnitude)
    {
        return null;
    }
    const raw: u8 = @intFromFloat(magnitude);
    return switch (raw) {
        @intFromEnum(PaintRecordKind.solid) => .solid,
        @intFromEnum(PaintRecordKind.linear_gradient) => .linear_gradient,
        @intFromEnum(PaintRecordKind.radial_gradient) => .radial_gradient,
        @intFromEnum(PaintRecordKind.image) => .image,
        @intFromEnum(PaintRecordKind.composite_group) => .composite_group,
        @intFromEnum(PaintRecordKind.conic_gradient) => .conic_gradient,
        else => null,
    };
}

test "paint record tag decoder is total for malformed floats" {
    try std.testing.expectEqual(@as(?PaintRecordKind, .solid), paintRecordKindFromTag(-1.0));
    try std.testing.expectEqual(@as(?PaintRecordKind, null), paintRecordKindFromTag(-1.4));
    try std.testing.expectEqual(@as(?PaintRecordKind, null), paintRecordKindFromTag(std.math.nan(f32)));
    try std.testing.expectEqual(@as(?PaintRecordKind, null), paintRecordKindFromTag(-std.math.inf(f32)));
    try std.testing.expectEqual(@as(?PaintRecordKind, null), paintRecordKindFromTag(-1.0e30));
}

test "band count codec is total at representation boundaries" {
    try std.testing.expectEqual(@as(?u32, null), packBandCounts(0, 1));
    try std.testing.expectEqual(@as(?u32, null), packBandCounts(1, 0));
    const word = packBandCounts(1, std.math.maxInt(u16)).?;
    try std.testing.expectEqual(BandCounts{ .h = 1, .v = std.math.maxInt(u16) }, unpackBandCounts(word).?);
    try std.testing.expectEqual(@as(?BandCounts, null), unpackBandCounts(0x0000ffff));
    try std.testing.expectEqual(@as(?BandCounts, null), unpackBandCounts(0xffff0000));
    try std.testing.expectEqual(@as(?BandCounts, null), unpackBandCounts(0xffffffff));
}

test "glyph word encoders reject unrepresentable semantic values" {
    try std.testing.expectEqual(@as(?u32, null), regularGlyphWord(0, 1, 0));
    try std.testing.expectEqual(@as(?u32, null), regularGlyphWord(1, 0, 0));
    try std.testing.expectEqual(@as(?u32, null), regularGlyphWord(17, 1, 0));
    try std.testing.expectEqual(@as(?u32, null), regularGlyphWord(1, 17, 0));
    try std.testing.expect(regularGlyphWord(16, 16, std.math.maxInt(u8)) != null);
    try std.testing.expectEqual(@as(?u32, null), specialGlyphWord(0, .path, 0));
    try std.testing.expect(specialGlyphWord(std.math.maxInt(u16), .autohint, std.math.maxInt(u8)) != null);
}

test "Slang render ABI constants match Zig constants" {
    const slang = @embedFile("../shader/slang/render_abi.slang");
    try expectSlangConst(slang, "SNAIL_RENDER_ABI_VERSION", version);
    try std.testing.expect(std.mem.indexOf(u8, slang, "public static const uint SNAIL_SPECIAL_GLYPH_MARKER = 0x80000000u;") != null);
    try expectSlangConst(slang, "SNAIL_SPECIAL_KIND_COLR", @intFromEnum(SpecialLayerKind.colr));
    try expectSlangConst(slang, "SNAIL_SPECIAL_KIND_PATH", @intFromEnum(SpecialLayerKind.path));
    try expectSlangConst(slang, "SNAIL_SPECIAL_KIND_TT_HINTED_TEXT", @intFromEnum(SpecialLayerKind.tt_hinted_text));
    try expectSlangConst(slang, "SNAIL_SPECIAL_KIND_AUTOHINT", @intFromEnum(SpecialLayerKind.autohint));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_SOLID", @intFromEnum(PaintRecordKind.solid));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_LINEAR_GRADIENT", @intFromEnum(PaintRecordKind.linear_gradient));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_RADIAL_GRADIENT", @intFromEnum(PaintRecordKind.radial_gradient));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_IMAGE", @intFromEnum(PaintRecordKind.image));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_COMPOSITE_GROUP", @intFromEnum(PaintRecordKind.composite_group));
    try expectSlangConst(slang, "SNAIL_PAINT_KIND_CONIC_GRADIENT", @intFromEnum(PaintRecordKind.conic_gradient));
    try expectSlangConst(slang, "SNAIL_PAINT_TEXELS_PER_RECORD", paint_texels_per_record);
    try expectSlangConst(slang, "SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE", composite_mode_fill_stroke_inside);
}

test "autohint Slang derives transient targets from immutable features" {
    const slang = @embedFile("../shader/slang/autohint_warp.slang");
    const fragment = @embedFile("../shader/slang/autohint_frag.slang");
    try std.testing.expect(std.mem.indexOf(u8, slang, "snailDecodeAutohintPolicy") != null);
    try std.testing.expect(std.mem.indexOf(u8, slang, "snailFitAutohintAxis") != null);
    try std.testing.expect(std.mem.indexOf(u8, slang, "storedTarget") == null);
    try std.testing.expect(std.mem.indexOf(u8, fragment, "SNAIL_AH_FRAG_KNOTS = 32") != null);
}

fn expectSlangConst(slang: []const u8, name: []const u8, value: anytype) !void {
    const needle = try std.fmt.allocPrint(std.testing.allocator, "public static const int {s} = {d};", .{ name, value });
    defer std.testing.allocator.free(needle);
    try std.testing.expect(std.mem.indexOf(u8, slang, needle) != null);
}
