const std = @import("std");
const vec = @import("../../math/vec.zig");
const Vec2 = vec.Vec2;
const Mat4 = vec.Mat4;
const BBox = @import("../../math/bezier.zig").BBox;
const band_tex = @import("band_texture.zig");
const curve_tex = @import("curve_texture.zig");
const render_abi = @import("abi.zig");

/// Per-instance data: 64 bytes = 16 u32 words per glyph.
///   rect:  4x f16 — bbox in em-space
///   xform: 4x f32 — linear part of 2D transform
///   org:   2x f32 — translation
///   glyph: 2x u32 — packed glyph data
///   bnd:   4x f32 — band transform
///   col:   4x u8 normalized sRGBA base color
///   tint:  4x u8 normalized sRGBA instance tint
pub const Instance = extern struct {
    rect: [4]u16,
    xform: [4]f32,
    origin: [2]f32,
    glyph: [2]u32,
    band: [4]f32,
    color: [4]u8,
    tint: [4]u8,
};

pub const BYTES_PER_INSTANCE: usize = @sizeOf(Instance);
pub const WORDS_PER_INSTANCE: usize = @divExact(BYTES_PER_INSTANCE, @sizeOf(u32));

/// One instance per glyph quad (instanced rendering).
pub const INSTANCES_PER_GLYPH: usize = 1;

pub const BYTES_PER_VERTEX = BYTES_PER_INSTANCE;
pub const WORDS_PER_VERTEX = WORDS_PER_INSTANCE;
pub const VERTICES_PER_GLYPH = INSTANCES_PER_GLYPH;

pub const SpecialLayerKind = render_abi.SpecialLayerKind;

comptime {
    std.debug.assert(BYTES_PER_INSTANCE == 64);
    std.debug.assert(WORDS_PER_INSTANCE == 16);
    std.debug.assert(@offsetOf(Instance, "rect") == 0);
    std.debug.assert(@offsetOf(Instance, "xform") == 8);
    std.debug.assert(@offsetOf(Instance, "origin") == 24);
    std.debug.assert(@offsetOf(Instance, "glyph") == 32);
    std.debug.assert(@offsetOf(Instance, "band") == 40);
    std.debug.assert(@offsetOf(Instance, "color") == 56);
    std.debug.assert(@offsetOf(Instance, "tint") == 60);
}

pub const DecodedInstance = struct {
    rect: [4]f32,
    xform: [4]f32,
    origin: [2]f32,
    glyph: [2]u32,
    band: [4]f32,
    color: [4]f32,
    tint: [4]f32,
};

const identity_tint = [4]f32{ 1, 1, 1, 1 };

fn f16BitsToF32(bits: u16) f32 {
    return @floatCast(@as(f16, @bitCast(bits)));
}

fn f32ToF16Bits(value: f32) u16 {
    return curve_tex.f32ToF16(value);
}

fn f16BitsToNextDown(bits: u16) u16 {
    if (bits == 0xFC00) return bits;
    if ((bits & 0x8000) != 0) return bits + 1;
    if (bits == 0) return 0x8001;
    return bits - 1;
}

fn f16BitsToNextUp(bits: u16) u16 {
    if (bits == 0x7C00) return bits;
    if ((bits & 0x8000) != 0) {
        if (bits == 0x8000) return 0x0001;
        return bits - 1;
    }
    return bits + 1;
}

fn f32ToF16RectMin(value: f32) u16 {
    const bits = f32ToF16Bits(value);
    return if (f16BitsToF32(bits) > value) f16BitsToNextDown(bits) else bits;
}

fn f32ToF16RectMax(value: f32) u16 {
    const bits = f32ToF16Bits(value);
    return if (f16BitsToF32(bits) < value) f16BitsToNextUp(bits) else bits;
}

fn half4(values: [4]f32) [4]u16 {
    return .{
        f32ToF16Bits(values[0]),
        f32ToF16Bits(values[1]),
        f32ToF16Bits(values[2]),
        f32ToF16Bits(values[3]),
    };
}

fn rectHalf4(values: [4]f32) [4]u16 {
    return .{
        f32ToF16RectMin(values[0]),
        f32ToF16RectMin(values[1]),
        f32ToF16RectMax(values[2]),
        f32ToF16RectMax(values[3]),
    };
}

fn specialRectHalf4(kind: SpecialLayerKind, values: [4]f32) [4]u16 {
    return switch (kind) {
        .path => rectHalf4(values),
        .hinted_text => rectHalf4(values),
        .colr => half4(values),
    };
}

fn unorm8(value: f32) u8 {
    const clamped = std.math.clamp(value, 0.0, 1.0);
    return @intFromFloat(@round(clamped * 255.0));
}

fn color4(color: [4]f32) [4]u8 {
    return .{
        unorm8(color[0]),
        unorm8(color[1]),
        unorm8(color[2]),
        unorm8(color[3]),
    };
}

fn decodeHalf4(values: [4]u16) [4]f32 {
    return .{
        f16BitsToF32(values[0]),
        f16BitsToF32(values[1]),
        f16BitsToF32(values[2]),
        f16BitsToF32(values[3]),
    };
}

fn decodeColor4(color: [4]u8) [4]f32 {
    return .{
        @as(f32, @floatFromInt(color[0])) / 255.0,
        @as(f32, @floatFromInt(color[1])) / 255.0,
        @as(f32, @floatFromInt(color[2])) / 255.0,
        @as(f32, @floatFromInt(color[3])) / 255.0,
    };
}

fn specialGlyphWord(layer_count: u16, kind: SpecialLayerKind) u32 {
    return render_abi.specialGlyphWord(layer_count, kind);
}

fn instancePtr(words: []u32) *Instance {
    std.debug.assert(words.len >= WORDS_PER_INSTANCE);
    return @ptrCast(@alignCast(words.ptr));
}

fn constInstancePtr(words: []const u32) *const Instance {
    std.debug.assert(words.len >= WORDS_PER_INSTANCE);
    return @ptrCast(@alignCast(words.ptr));
}

fn writeInstance(words: []u32, instance: Instance) void {
    instancePtr(words).* = instance;
}

pub fn instanceAt(words: []const u32, glyph_index: usize) *const Instance {
    const base = glyph_index * WORDS_PER_INSTANCE;
    return constInstancePtr(words[base..][0..WORDS_PER_INSTANCE]);
}

pub fn instanceAtMut(words: []u32, glyph_index: usize) *Instance {
    const base = glyph_index * WORDS_PER_INSTANCE;
    return instancePtr(words[base..][0..WORDS_PER_INSTANCE]);
}

pub fn instanceBytes(words: []const u32) []const u8 {
    return std.mem.sliceAsBytes(words);
}

pub fn decodeInstance(words: []const u32) DecodedInstance {
    const instance = constInstancePtr(words);
    return .{
        .rect = decodeHalf4(instance.rect),
        .xform = instance.xform,
        .origin = instance.origin,
        .glyph = instance.glyph,
        .band = instance.band,
        .color = decodeColor4(instance.color),
        .tint = decodeColor4(instance.tint),
    };
}

/// Generate instance data for a glyph quad (non-transformed).
pub fn generateGlyphVertices(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    atlas_layer: u8,
) void {
    generateGlyphVerticesTinted(buf, x, y, font_size, bbox, band_entry, color, identity_tint, atlas_layer);
}

/// Generate instance data for a tinted glyph quad (non-transformed).
pub fn generateGlyphVerticesTinted(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
) void {
    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    writeInstance(buf, .{
        .rect = half4(.{ bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y }),
        .xform = .{ font_size, 0, 0, -font_size },
        .origin = .{ x, y },
        .glyph = .{ gz, gw },
        .band = .{ band_entry.band_scale_x, band_entry.band_scale_y, band_entry.band_offset_x, band_entry.band_offset_y },
        .color = color4(color),
        .tint = color4(tint),
    });
}

/// Generate instance data for a glyph quad under a full 2D affine transform.
pub fn generateGlyphVerticesTransformed(
    buf: []u32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    return generateGlyphVerticesTransformedTinted(buf, bbox, band_entry, color, identity_tint, atlas_layer, transform);
}

/// Generate instance data for a tinted glyph quad under a full 2D affine transform.
pub fn generateGlyphVerticesTransformedTinted(
    buf: []u32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1e-10) return false;

    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    writeInstance(buf, .{
        .rect = half4(.{ bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y }),
        .xform = .{ transform.xx, transform.xy, transform.yx, transform.yy },
        .origin = .{ transform.tx, transform.ty },
        .glyph = .{ gz, gw },
        .band = .{ band_entry.band_scale_x, band_entry.band_scale_y, band_entry.band_offset_x, band_entry.band_offset_y },
        .color = color4(color),
        .tint = color4(tint),
    });
    return true;
}

/// Generate instance data for a multi-layer COLR glyph (single quad, all layers).
pub fn generateMultiLayerGlyphVertices(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    atlas_layer: u8,
) void {
    generateMultiLayerGlyphVerticesTinted(buf, x, y, font_size, union_bbox, info_x, info_y, layer_count, color, identity_tint, atlas_layer);
}

/// Generate instance data for a tinted multi-layer COLR glyph.
pub fn generateMultiLayerGlyphVerticesTinted(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
) void {
    generateSpecialLayerVerticesTinted(buf, x, y, font_size, union_bbox, info_x, info_y, layer_count, color, tint, atlas_layer, .colr);
}

/// Generate instance data for a tinted path layer-info record.
pub fn generatePathRecordVerticesTinted(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
) void {
    generateSpecialLayerVerticesTinted(buf, x, y, font_size, union_bbox, info_x, info_y, layer_count, color, tint, atlas_layer, .path);
}

/// Generate instance data for a tinted hinted text layer-info record.
pub fn generateHintedTextVerticesTinted(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
) void {
    generateSpecialLayerVerticesTinted(buf, x, y, font_size, union_bbox, info_x, info_y, layer_count, color, tint, atlas_layer, .hinted_text);
}

fn generateSpecialLayerVerticesTinted(
    buf: []u32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    kind: SpecialLayerKind,
) void {
    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    const gw = specialGlyphWord(layer_count, kind);

    writeInstance(buf, .{
        .rect = specialRectHalf4(kind, .{ union_bbox.min.x, union_bbox.min.y, union_bbox.max.x, union_bbox.max.y }),
        .xform = .{ font_size, 0, 0, -font_size },
        .origin = .{ x, y },
        .glyph = .{ gz, gw },
        .band = .{ 0, 0, 0, @floatFromInt(atlas_layer) },
        .color = color4(color),
        .tint = color4(tint),
    });
}

/// Generate instance data for a transformed multi-layer COLR glyph.
pub fn generateMultiLayerGlyphVerticesTransformed(
    buf: []u32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    return generateMultiLayerGlyphVerticesTransformedTinted(buf, bbox, info_x, info_y, layer_count, color, identity_tint, atlas_layer, transform);
}

/// Generate instance data for a tinted transformed multi-layer COLR/path glyph.
pub fn generateMultiLayerGlyphVerticesTransformedTinted(
    buf: []u32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    return generateSpecialLayerVerticesTransformedTinted(buf, bbox, info_x, info_y, layer_count, color, tint, atlas_layer, transform, .colr);
}

/// Generate instance data for a tinted transformed path layer-info record.
pub fn generatePathRecordVerticesTransformedTinted(
    buf: []u32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    return generateSpecialLayerVerticesTransformedTinted(buf, bbox, info_x, info_y, layer_count, color, tint, atlas_layer, transform, .path);
}

/// Generate instance data for a tinted transformed hinted text layer-info record.
pub fn generateHintedTextVerticesTransformedTinted(
    buf: []u32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    return generateSpecialLayerVerticesTransformedTinted(buf, bbox, info_x, info_y, layer_count, color, tint, atlas_layer, transform, .hinted_text);
}

fn generateSpecialLayerVerticesTransformedTinted(
    buf: []u32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    tint: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
    kind: SpecialLayerKind,
) bool {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1e-10) return false;

    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    const gw = specialGlyphWord(layer_count, kind);

    writeInstance(buf, .{
        .rect = specialRectHalf4(kind, .{ bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y }),
        .xform = .{ transform.xx, transform.xy, transform.yx, transform.yy },
        .origin = .{ transform.tx, transform.ty },
        .glyph = .{ gz, gw },
        .band = .{ 0, 0, 0, @floatFromInt(atlas_layer) },
        .color = color4(color),
        .tint = color4(tint),
    });
    return true;
}

test "instance data produces correct layout" {
    const bezier_mod = @import("../../math/bezier.zig");
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;

    const bbox = bezier_mod.BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 10,
        .glyph_y = 5,
        .h_band_count = 2,
        .v_band_count = 3,
        .band_scale_x = 4.0,
        .band_scale_y = 2.0,
        .band_offset_x = 0.1,
        .band_offset_y = 0.2,
    };
    const color = [4]f32{ 1.0, 0.5, 0.0, 1.0 };

    generateGlyphVertices(&buf, 100.0, 200.0, 24.0, bbox, band_entry, color, 0);
    const decoded = decodeInstance(&buf);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), decoded.rect[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), decoded.rect[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), decoded.rect[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), decoded.rect[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), decoded.xform[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), decoded.xform[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), decoded.xform[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -24.0), decoded.xform[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), decoded.origin[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), decoded.origin[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.color[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), decoded.color[1], 1.0 / 255.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), decoded.color[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.color[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.tint[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.tint[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.tint[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.tint[3], 0.001);
}

test "instance rect half encoding encloses source bbox" {
    const encoded = rectHalf4(.{ -18.37, -0.213, 142.91, 67.49 });
    const decoded = decodeHalf4(encoded);

    try std.testing.expect(decoded[0] <= -18.37);
    try std.testing.expect(decoded[1] <= -0.213);
    try std.testing.expect(decoded[2] >= 142.91);
    try std.testing.expect(decoded[3] >= 67.49);
}

test "multi-layer glyph instance preserves wide layer counts" {
    const bezier_mod = @import("../../math/bezier.zig");
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;

    const bbox = bezier_mod.BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const color = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    generateMultiLayerGlyphVertices(&buf, 10.0, 20.0, 24.0, bbox, 12, 34, 300, color, 7);

    const packed_gw = decodeInstance(&buf).glyph[1];
    try std.testing.expectEqual(@as(u16, 300), render_abi.specialGlyphWordLayerCount(packed_gw));
    try std.testing.expectEqual(SpecialLayerKind.colr, render_abi.specialGlyphWordKind(packed_gw).?);
}

test "path record instance uses path special kind" {
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };

    generatePathRecordVerticesTinted(&buf, 10.0, 20.0, 24.0, bbox, 12, 34, 1, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 1 }, 7);

    const packed_gw = decodeInstance(&buf).glyph[1];
    try std.testing.expectEqual(@as(u16, 1), render_abi.specialGlyphWordLayerCount(packed_gw));
    try std.testing.expectEqual(SpecialLayerKind.path, render_abi.specialGlyphWordKind(packed_gw).?);
}

test "hinted text instance uses hinted special kind" {
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(-0.1, -0.2),
        .max = Vec2.new(0.6, 0.8),
    };

    generateHintedTextVerticesTinted(&buf, 10.0, 20.0, 24.0, bbox, 12, 34, 1, .{ 1, 1, 1, 1 }, .{ 1, 1, 1, 1 }, 7);

    const packed_gw = decodeInstance(&buf).glyph[1];
    try std.testing.expectEqual(@as(u16, 1), render_abi.specialGlyphWordLayerCount(packed_gw));
    try std.testing.expectEqual(SpecialLayerKind.hinted_text, render_abi.specialGlyphWordKind(packed_gw).?);
}

test "transformed glyph instance stores affine transform" {
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(1.0, 2.0),
        .max = Vec2.new(5.0, 8.0),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 7,
        .glyph_y = 3,
        .h_band_count = 2,
        .v_band_count = 2,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };
    const transform = vec.Transform2D{
        .xx = 2.0,
        .xy = 1.0,
        .tx = 10.0,
        .yx = 0.0,
        .yy = 3.0,
        .ty = -4.0,
    };

    try std.testing.expect(generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 0.5, 0.25, 1 }, 0, transform));
    const decoded = decodeInstance(&buf);
    // rect
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.rect[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), decoded.rect[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), decoded.rect[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), decoded.rect[3], 0.001);
    // xform: xx, xy, yx, yy
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), decoded.xform[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decoded.xform[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), decoded.xform[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), decoded.xform[3], 0.001);
    // meta: tx, ty
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), decoded.origin[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -4.0), decoded.origin[1], 0.001);
}

test "transformed multi-layer glyph instance preserves info pointer and atlas sentinel" {
    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(-2.0, 1.0),
        .max = Vec2.new(6.0, 5.0),
    };
    const transform = vec.Transform2D{
        .xx = 1.5,
        .xy = 0.0,
        .tx = 4.0,
        .yx = 0.25,
        .yy = 2.0,
        .ty = -3.0,
    };

    try std.testing.expect(generateMultiLayerGlyphVerticesTransformed(&buf, bbox, 12, 34, 1, .{ 1, 1, 1, 1 }, 9, transform));
    const decoded = decodeInstance(&buf);
    const packed_gz = decoded.glyph[0];
    const packed_gw = decoded.glyph[1];
    try std.testing.expectEqual(@as(u16, 12), render_abi.glyphLocationX(packed_gz));
    try std.testing.expectEqual(@as(u16, 34), render_abi.glyphLocationY(packed_gz));
    try std.testing.expectEqual(@as(u16, 1), render_abi.specialGlyphWordLayerCount(packed_gw));
    try std.testing.expectEqual(SpecialLayerKind.colr, render_abi.specialGlyphWordKind(packed_gw).?);
    try std.testing.expectApproxEqAbs(@as(f32, 9), decoded.band[3], 0.001);
}
