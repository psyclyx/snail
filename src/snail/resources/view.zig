const image_mod = @import("../image.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const texture_layers = @import("../render/format/texture_layers.zig");
const vec = @import("../math/vec.zig");

const Atlas = atlas_curve_mod.Atlas;
const Image = image_mod.Image;

pub const PreparedTextAtlasView = struct {
    layer_base: u32 = 0,
    page_layers: []const u32 = &.{},
    info_row_base: u32 = 0,
    paint_info_row_base: u32 = 0,
    /// Row base into the layer-info texture for the blob's bundle hint
    /// pool. Bundle-shared: many blobs from one bundle resolve to the
    /// same row_base so the hint records are uploaded once per bundle.
    hint_info_row_base: u32 = 0,
};

pub const PreparedImageView = struct {
    image: *const Image,
    layer: u32 = 0,
    uv_scale: vec.Vec2 = .{ .x = 1.0, .y = 1.0 },
};

pub const PreparedAtlasView = struct {
    layer_base: u32 = 0,
    page_layers: []const u32 = &.{},
    info_row_base: u32 = 0,

    pub fn glyphLayer(self: *const PreparedAtlasView, page_index: u16) u32 {
        if (page_index < self.page_layers.len) return self.page_layers[page_index];
        const layer = self.layer_base + page_index;
        return layer;
    }

    pub fn glyphLayerWindowBase(self: *const PreparedAtlasView, page_index: u16) u32 {
        return texture_layers.windowBase(self.glyphLayer(page_index));
    }

    pub fn layerInfoLoc(self: *const PreparedAtlasView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = @intCast(self.info_row_base + info_y),
        };
    }
};

pub const PreparedLayerInfoUpload = struct {
    data: ?[]const f32 = null,
    width: u32 = 0,
    height: u32 = 0,
    paint_image_records: ?[]const ?Atlas.PaintImageRecord = null,
};

/// Bundle-shared hint slab upload (no per-blob image records).
pub const PreparedHintLayerInfoUpload = struct {
    data: ?[]const f32 = null,
    width: u32 = 0,
    height: u32 = 0,
};

pub const PreparedLayerInfoView = struct {
    info_row_base: u32 = 0,
};

pub fn coerceAtlasHandle(atlas_like: anytype) PreparedAtlasView {
    const T = @TypeOf(atlas_like);
    return switch (T) {
        *const PreparedAtlasView, *PreparedAtlasView => atlas_like.*,
        *const Atlas, *Atlas => .{},
        else => @compileError("expected *CurveAtlas or prepared atlas view"),
    };
}
