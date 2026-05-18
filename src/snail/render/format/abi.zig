const std = @import("std");

pub const special_layer_sentinel: u8 = 0xff;

pub const SpecialLayerKind = enum(u8) {
    colr = 0,
    path = 1,
};

pub const PaintRecordKind = enum(u8) {
    solid = 1,
    linear_gradient = 2,
    radial_gradient = 3,
    image = 4,
    composite_group = 5,
};

pub const paint_info_width: u32 = 4096;
pub const paint_texels_per_record: u32 = 6;

pub const composite_mode_source_over: u8 = 0;
pub const composite_mode_fill_stroke_inside: u8 = 1;

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
        else => null,
    };
}

test "GLSL render ABI constants match Zig constants" {
    const glsl = @embedFile("../backend/glsl/snail_render_abi.glsl");
    try expectGlslConst(glsl, "SNAIL_SPECIAL_LAYER_SENTINEL", special_layer_sentinel);
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_COLR", @intFromEnum(SpecialLayerKind.colr));
    try expectGlslConst(glsl, "SNAIL_SPECIAL_KIND_PATH", @intFromEnum(SpecialLayerKind.path));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_SOLID", @intFromEnum(PaintRecordKind.solid));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_LINEAR_GRADIENT", @intFromEnum(PaintRecordKind.linear_gradient));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_RADIAL_GRADIENT", @intFromEnum(PaintRecordKind.radial_gradient));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_IMAGE", @intFromEnum(PaintRecordKind.image));
    try expectGlslConst(glsl, "SNAIL_PAINT_KIND_COMPOSITE_GROUP", @intFromEnum(PaintRecordKind.composite_group));
    try expectGlslConst(glsl, "SNAIL_PAINT_TEXELS_PER_RECORD", paint_texels_per_record);
    try expectGlslConst(glsl, "SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE", composite_mode_fill_stroke_inside);
}

fn expectGlslConst(glsl: []const u8, name: []const u8, value: anytype) !void {
    const needle = try std.fmt.allocPrint(std.testing.allocator, "const int {s} = {d};", .{ name, value });
    defer std.testing.allocator.free(needle);
    try std.testing.expect(std.mem.indexOf(u8, glsl, needle) != null);
}
