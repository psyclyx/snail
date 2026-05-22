const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const texture_layers = @import("../render/format/texture_layers.zig");
const ttf = @import("../font/ttf.zig");
const config_mod = @import("config.zig");

const GlyphInfo = atlas_curve_mod.CurveAtlas.GlyphInfo;
const ColrBaseInfo = atlas_curve_mod.CurveAtlas.ColrBaseInfo;
const FaceConfig = config_mod.FaceConfig;
const FaceGlyphData = config_mod.FaceGlyphData;

pub fn preparedViewLayerBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "layer_base")) view.layer_base else 0,
        else => 0,
    };
}

pub fn preparedViewPageLayers(view: anytype) []const u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "page_layers")) view.page_layers else &.{},
        else => &.{},
    };
}

pub fn preparedViewInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "info_row_base")) view.info_row_base else 0,
        else => 0,
    };
}

pub fn preparedViewPaintInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "paint_info_row_base")) view.paint_info_row_base else 0,
        else => 0,
    };
}

pub fn preparedViewHintInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "hint_info_row_base")) view.hint_info_row_base else 0,
        else => 0,
    };
}

/// View into one face's glyph data within a TextAtlas snapshot.
/// Implements the interface expected by glyph_emit.emitGlyph.
pub const FaceView = struct {
    face_glyphs: *const FaceGlyphData,
    face_config: *const FaceConfig,
    layer_base: u32,
    page_layers: []const u32 = &.{},
    info_row_base: u32,

    pub fn getGlyph(self: *const FaceView, gid: u16) ?GlyphInfo {
        return self.face_glyphs.getGlyph(gid);
    }

    pub fn getColrBase(self: *const FaceView, gid: u16) ?ColrBaseInfo {
        if (self.face_glyphs.colr_base_map) |cbm| return cbm.get(gid);
        return null;
    }

    pub fn colrLayers(self: *const FaceView, gid: u16) ttf.Font.ColrLayerIterator {
        if (self.face_config.font.colr_offset == 0) return .{ .data = self.face_config.font_data };
        const temp = ttf.Font{ .data = self.face_config.font_data, .colr_offset = self.face_config.font.colr_offset, .cpal_offset = self.face_config.font.cpal_offset };
        return temp.colrLayers(gid);
    }

    pub fn glyphLayer(self: *const FaceView, page_index: u16) u32 {
        if (page_index < self.page_layers.len) return self.page_layers[page_index];
        const layer = self.layer_base + page_index;
        return layer;
    }

    pub fn glyphLayerWindowBase(self: *const FaceView, page_index: u16) u32 {
        return texture_layers.windowBase(self.glyphLayer(page_index));
    }

    pub fn layerInfoLoc(self: *const FaceView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = @intCast(self.info_row_base + info_y),
        };
    }
};
