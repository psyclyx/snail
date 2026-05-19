const band_tex = @import("band_texture.zig");
const bezier = @import("../../math/bezier.zig");
const texture_layers = @import("texture_layers.zig");
const vec = @import("../../math/vec.zig");
const vertex = @import("vertex.zig");

const BBox = bezier.BBox;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Transform2D = vec.Transform2D;

pub const WORDS_PER_VERTEX = vertex.WORDS_PER_VERTEX;
pub const VERTICES_PER_GLYPH = vertex.VERTICES_PER_GLYPH;
pub const WORDS_PER_GLYPH = WORDS_PER_VERTEX * VERTICES_PER_GLYPH;

const identity_tint = [4]f32{ 1, 1, 1, 1 };

/// Mutable cursor over an instance-word buffer.
///
/// Text and path batches decide *what* to emit. This cursor owns the common
/// mechanics of capacity checks, texture-window splitting, and writing the
/// packed vertex ABI.
pub const Cursor = struct {
    buf: []u32,
    len: *usize,
    layer_window_base: *?u32,

    pub fn currentLayerWindowBase(self: Cursor) u32 {
        return self.layer_window_base.* orelse 0;
    }

    fn localLayer(self: Cursor, atlas_layer: u32) !u8 {
        const base = texture_layers.windowBase(atlas_layer);
        if (self.layer_window_base.*) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base.* = base;
        }
        return texture_layers.local(atlas_layer);
    }

    fn remaining(self: Cursor) []u32 {
        return self.buf[self.len.*..];
    }

    fn ensureInstanceCapacity(self: Cursor) !void {
        if (self.len.* + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
    }

    fn commitInstance(self: Cursor) void {
        self.len.* += WORDS_PER_GLYPH;
    }

    pub fn appendGlyph(
        self: Cursor,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: BBox,
        band_entry: GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.appendGlyphTinted(x, y, font_size, bbox, band_entry, color, identity_tint, atlas_layer);
    }

    pub fn appendGlyphTinted(
        self: Cursor,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: BBox,
        band_entry: GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.ensureInstanceCapacity();
        const local_layer = try self.localLayer(atlas_layer);
        vertex.generateGlyphVerticesTinted(self.remaining(), x, y, font_size, bbox, band_entry, color, tint, local_layer);
        self.commitInstance();
    }

    pub fn appendMultiLayerGlyphTinted(
        self: Cursor,
        x: f32,
        y: f32,
        font_size: f32,
        union_bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.ensureInstanceCapacity();
        const local_layer = try self.localLayer(atlas_layer);
        vertex.generateMultiLayerGlyphVerticesTinted(
            self.remaining(),
            x,
            y,
            font_size,
            union_bbox,
            info_x,
            info_y,
            layer_count,
            color,
            tint,
            local_layer,
        );
        self.commitInstance();
    }

    pub fn appendGlyphTransformedTinted(
        self: Cursor,
        bbox: BBox,
        band_entry: GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.ensureInstanceCapacity();
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex.generateGlyphVerticesTransformedTinted(self.remaining(), bbox, band_entry, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.commitInstance();
    }

    pub fn appendMultiLayerGlyphTransformedTinted(
        self: Cursor,
        union_bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.ensureInstanceCapacity();
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex.generateMultiLayerGlyphVerticesTransformedTinted(self.remaining(), union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.commitInstance();
    }

    pub fn appendPathRecordTransformedTinted(
        self: Cursor,
        union_bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.ensureInstanceCapacity();
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex.generatePathRecordVerticesTransformedTinted(self.remaining(), union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.commitInstance();
    }
};
