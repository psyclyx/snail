const std = @import("std");

pub const special_layer_sentinel: u8 = 0xff;

pub const SpecialLayerKind = enum(u8) {
    colr = 0,
    path = 1,
    hinted_text = 2,
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

pub const hint_record_flag_expanded_bands: u16 = 1 << 0;
pub const hint_record_flag_unordered_bands: u16 = 1 << 1;

pub fn packGlyphLocation(x: u16, y: u16) u32 {
    return @as(u32, x) | (@as(u32, y) << 16);
}

pub fn glyphLocationX(word: u32) u16 {
    return @intCast(word & 0xffff);
}

pub fn glyphLocationY(word: u32) u16 {
    return @intCast(word >> 16);
}

pub fn specialGlyphWord(layer_count: u16, kind: SpecialLayerKind) u32 {
    return @as(u32, layer_count) |
        (@as(u32, @intFromEnum(kind)) << 16) |
        (@as(u32, special_layer_sentinel) << 24);
}

pub fn glyphWordAtlasLayer(word: u32) u8 {
    return @intCast(word >> 24);
}

pub fn glyphWordIsSpecial(word: u32) bool {
    return glyphWordAtlasLayer(word) == special_layer_sentinel;
}

pub fn specialGlyphWordLayerCount(word: u32) u16 {
    return @intCast(word & 0xffff);
}

pub fn specialGlyphWordKind(word: u32) ?SpecialLayerKind {
    if (!glyphWordIsSpecial(word)) return null;
    const raw: u8 = @intCast((word >> 16) & 0xff);
    return switch (raw) {
        @intFromEnum(SpecialLayerKind.colr) => .colr,
        @intFromEnum(SpecialLayerKind.path) => .path,
        @intFromEnum(SpecialLayerKind.hinted_text) => .hinted_text,
        @intFromEnum(SpecialLayerKind.autohint) => .autohint,
        else => null,
    };
}

pub fn regularGlyphWordHBandCount(word: u32) u16 {
    return @intCast((word & 0xffff) + 1);
}

pub fn regularGlyphWordVBandCount(word: u32) u16 {
    return @intCast(((word >> 16) & 0xff) + 1);
}

pub const BandCounts = struct {
    h: u16,
    v: u16,
};

pub fn packBandCounts(h: u16, v: u16) u32 {
    return @as(u32, h - 1) | (@as(u32, v - 1) << 16);
}

pub fn unpackBandCounts(word: u32) BandCounts {
    return .{
        .h = @intCast((word & 0xffff) + 1),
        .v = @intCast(((word >> 16) & 0xffff) + 1),
    };
}

pub fn paintRecordTag(kind: PaintRecordKind) f32 {
    return -@as(f32, @floatFromInt(@intFromEnum(kind)));
}

pub fn paintRecordKindFromTag(tag: f32) ?PaintRecordKind {
    if (tag >= 0.0) return null;
    const raw: i32 = @intFromFloat(@round(-tag));
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

test "GLSL render ABI constants match Zig constants" {
    const glsl = @embedFile("../render/backend/gl/glsl/snail_render_abi.glsl");
    try expectGlslConst(glsl, "SNAIL_SPECIAL_LAYER_SENTINEL", special_layer_sentinel);
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_COLR", @intFromEnum(SpecialLayerKind.colr));
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_PATH", @intFromEnum(SpecialLayerKind.path));
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_HINTED_TEXT", @intFromEnum(SpecialLayerKind.hinted_text));
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_AUTOHINT", @intFromEnum(SpecialLayerKind.autohint));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_SOLID", @intFromEnum(PaintRecordKind.solid));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_LINEAR_GRADIENT", @intFromEnum(PaintRecordKind.linear_gradient));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_RADIAL_GRADIENT", @intFromEnum(PaintRecordKind.radial_gradient));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_IMAGE", @intFromEnum(PaintRecordKind.image));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_COMPOSITE_GROUP", @intFromEnum(PaintRecordKind.composite_group));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_CONIC_GRADIENT", @intFromEnum(PaintRecordKind.conic_gradient));
    try expectGlslConst(glsl, "SNAIL_PAINT_TEXELS_PER_RECORD", paint_texels_per_record);
    try expectGlslConst(glsl, "SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE", composite_mode_fill_stroke_inside);
    try expectGlslConst(glsl, "SNAIL_HINT_RECORD_FLAG_EXPANDED_BANDS", hint_record_flag_expanded_bands);
    try expectGlslConst(glsl, "SNAIL_HINT_RECORD_FLAG_UNORDERED_BANDS", hint_record_flag_unordered_bands);
}

test "autohint GLSL derives transient targets from immutable features" {
    const glsl = @embedFile("../render/backend/gl/glsl/snail_autohint_warp.glsl");
    try std.testing.expect(std.mem.indexOf(u8, glsl, "snailDecodeAutohintPolicy") != null);
    try std.testing.expect(std.mem.indexOf(u8, glsl, "snailFitAutohintAxis") != null);
    try std.testing.expect(std.mem.indexOf(u8, glsl, "storedTarget") == null);
    try std.testing.expect(std.mem.indexOf(u8, glsl, "SNAIL_AH_MAX_KNOTS = 32") != null);
}

fn expectGlslConst(glsl: []const u8, name: []const u8, value: anytype) !void {
    const needle = try std.fmt.allocPrint(std.testing.allocator, "const int {s} = {d};", .{ name, value });
    defer std.testing.allocator.free(needle);
    try std.testing.expect(std.mem.indexOf(u8, glsl, needle) != null);
}
