const std = @import("std");

const band_tex = @import("../renderer/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const blob_mod = @import("blob.zig");
const glyph_emit = @import("../glyph_emit.zig");
const scene_mod = @import("../scene.zig");
const shape_mod = @import("shape.zig");
const texture_layers = @import("../renderer/texture_layers.zig");
const vertex_mod = @import("../renderer/vertex.zig");
const vec = @import("../math/vec.zig");
const view_mod = @import("view.zig");

const FaceView = view_mod.FaceView;
const TextBlob = blob_mod.TextBlob;
const TextDraw = scene_mod.TextDraw;
const Transform2D = vec.Transform2D;
const isIdentityTransform = shape_mod.isIdentityTransform;
const preparedViewPaintInfoRowBase = view_mod.preparedViewPaintInfoRowBase;

pub const WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const WORDS_PER_GLYPH = WORDS_PER_VERTEX * VERTICES_PER_GLYPH;

/// Accumulates glyph vertices into a caller-provided buffer.
/// Zero allocations. Can be pre-built for static text.
pub const TextBatch = struct {
    buf: []u32,
    len: usize, // words written
    layer_window_base: ?u32 = null,

    pub fn init(buf: []u32) TextBatch {
        return .{ .buf = buf, .len = 0 };
    }

    pub fn reset(self: *TextBatch) void {
        self.len = 0;
        self.layer_window_base = null;
    }

    pub fn glyphCount(self: *const TextBatch) usize {
        return self.len / WORDS_PER_GLYPH;
    }

    pub fn slice(self: *const TextBatch) []const u32 {
        return self.buf[0..self.len];
    }

    pub fn currentLayerWindowBase(self: *const TextBatch) u32 {
        return self.layer_window_base orelse 0;
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_glyph: usize,
        completed: bool,
        layer_window_base: u32,
    };

    /// Emit one slice of a `TextDraw` into this batch: the glyphs from
    /// `[start_glyph, draw.glyphs.end)` under `draw.instances[override_index]`.
    /// Returns where to resume; the caller is responsible for advancing
    /// across overrides and re-opening batches when full or when the
    /// texture layer window changes.
    pub fn addDraw(
        self: *TextBatch,
        view: anytype,
        draw: TextDraw,
        override_index: usize,
        start_glyph: usize,
    ) !AppendResult {
        return appendTextDrawIntoBatch(self, view, draw, override_index, start_glyph);
    }

    fn localLayer(self: *TextBatch, atlas_layer: u32) !u8 {
        const base = texture_layers.windowBase(atlas_layer);
        if (self.layer_window_base) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base = base;
        }
        return texture_layers.local(atlas_layer);
    }

    /// Append a single glyph quad.
    pub fn addGlyph(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.addGlyphTinted(x, y, font_size, bbox, band_entry, color, .{ 1, 1, 1, 1 }, atlas_layer);
    }

    pub fn addGlyphTinted(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        if (self.len + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        vertex_mod.generateGlyphVerticesTinted(self.buf[self.len..], x, y, font_size, bbox, band_entry, color, tint, local_layer);
        self.len += WORDS_PER_GLYPH;
    }

    /// Append a multi-layer COLR glyph quad.
    pub fn addColrGlyph(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.addColrGlyphTinted(x, y, font_size, union_bbox, info_x, info_y, layer_count, color, .{ 1, 1, 1, 1 }, atlas_layer);
    }

    pub fn addColrGlyphTinted(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        if (self.len + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        vertex_mod.generateMultiLayerGlyphVerticesTinted(
            self.buf[self.len..],
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
        self.len += WORDS_PER_GLYPH;
    }

    /// Append a single glyph quad with a 2D transform.
    pub fn addGlyphTransformed(
        self: *TextBatch,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.addGlyphTransformedTinted(bbox, band_entry, color, .{ 1, 1, 1, 1 }, atlas_layer, transform);
    }

    pub fn addGlyphTransformedTinted(
        self: *TextBatch,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateGlyphVerticesTransformedTinted(self.buf[self.len..], bbox, band_entry, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += WORDS_PER_GLYPH;
    }

    /// Append a multi-layer COLR glyph quad with a 2D transform.
    pub fn addColrGlyphTransformed(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.addColrGlyphTransformedTinted(union_bbox, info_x, info_y, layer_count, color, .{ 1, 1, 1, 1 }, atlas_layer, transform);
    }

    pub fn addColrGlyphTransformedTinted(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateMultiLayerGlyphVerticesTransformedTinted(self.buf[self.len..], union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += WORDS_PER_GLYPH;
    }

    pub fn addPathRecordTransformedTinted(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generatePathRecordVerticesTransformedTinted(self.buf[self.len..], union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += WORDS_PER_GLYPH;
    }
};

/// Emit one slice of a `TextDraw` into `batch`.
pub fn appendTextDrawIntoBatch(
    batch: *TextBatch,
    view: anytype,
    draw: TextDraw,
    override_index: usize,
    start_glyph: usize,
) !TextBatch.AppendResult {
    const blob = draw.blob;
    try blob.validate();
    const range = draw.glyphs.resolve(blob.glyphs.len);
    const start = @max(start_glyph, range.start);
    if (start > range.end) return error.InvalidGlyphRange;
    if (override_index >= draw.instances.len) return error.InvalidOverrideIndex;
    const override = draw.instances[override_index];
    const has_outer_transform = !isIdentityTransform(override.transform);
    const paint_info_row_base = preparedViewPaintInfoRowBase(view);

    var count: usize = 0;
    var glyph_index = start;
    while (glyph_index < range.end) : (glyph_index += 1) {
        const glyph = blob.glyphs[glyph_index];
        const face_view = blob.atlas.faceView(glyph.face_index, view);
        const glyph_layer_base = try textBlobGlyphLayerWindowBase(&face_view, glyph.glyph_id) orelse continue;
        if (batch.layer_window_base) |base| {
            if (base != glyph_layer_base) break;
        } else {
            batch.layer_window_base = glyph_layer_base;
        }

        var final_transform = glyph.transform;
        if (has_outer_transform) {
            final_transform = Transform2D.multiply(override.transform, final_transform);
        }
        if (glyph.paint_record_index) |record_index| {
            try emitPaintedBlobGlyph(batch, blob, &face_view, glyph.glyph_id, record_index, paint_info_row_base, override.tint, final_transform);
            count += 1;
        } else {
            switch (glyph_emit.emitGlyphWithTransformTinted(batch, &face_view, glyph.glyph_id, glyph.color, override.tint, final_transform)) {
                .emitted => count += 1,
                .skipped => {},
                .buffer_full => return error.DrawListFull,
                .layer_window_changed => break,
                .invalid_transform => return error.InvalidTransform,
            }
        }

        if (glyph.embolden != 0) {
            var bold_transform = glyph.transform;
            bold_transform.tx += glyph.embolden;
            if (has_outer_transform) {
                bold_transform = Transform2D.multiply(override.transform, bold_transform);
            }
            if (glyph.paint_record_index) |record_index| {
                try emitPaintedBlobGlyph(batch, blob, &face_view, glyph.glyph_id, record_index, paint_info_row_base, override.tint, bold_transform);
            } else {
                switch (glyph_emit.emitGlyphWithTransformTinted(batch, &face_view, glyph.glyph_id, glyph.color, override.tint, bold_transform)) {
                    .emitted, .skipped => {},
                    .buffer_full => return error.DrawListFull,
                    .layer_window_changed => return error.GlyphSpansTextureLayerWindows,
                    .invalid_transform => return error.InvalidTransform,
                }
            }
        }
    }
    return .{
        .emitted = count,
        .next_glyph = glyph_index,
        .completed = glyph_index >= range.end,
        .layer_window_base = batch.currentLayerWindowBase(),
    };
}

fn emitPaintedBlobGlyph(
    batch: *TextBatch,
    blob: *const TextBlob,
    face_view: *const FaceView,
    glyph_id: u16,
    record_index: u32,
    paint_info_row_base: u32,
    tint: [4]f32,
    transform: Transform2D,
) !void {
    const info = face_view.getGlyph(glyph_id) orelse return;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return;
    const loc = blob.paintRecordLoc(record_index);
    const info_y = paint_info_row_base + loc.y;
    if (info_y > std.math.maxInt(u16)) return error.LayerInfoLimitExceeded;
    try batch.addPathRecordTransformedTinted(
        info.bbox,
        loc.x,
        @intCast(info_y),
        1,
        .{ 1, 1, 1, 1 },
        tint,
        face_view.glyphLayer(info.page_index),
        transform,
    );
}

fn textBlobGlyphLayerWindowBase(view: *const FaceView, glyph_id: u16) !?u32 {
    if (view.getColrBase(glyph_id)) |cbi| {
        return view.glyphLayerWindowBase(cbi.page_index);
    }

    var layer_it = view.colrLayers(glyph_id);
    var base: ?u32 = null;
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = view.getGlyph(layer.glyph_id) orelse continue;
            if (linfo.band_entry.h_band_count == 0 or linfo.band_entry.v_band_count == 0) continue;
            const layer_base = view.glyphLayerWindowBase(linfo.page_index);
            if (base) |existing| {
                if (existing != layer_base) return error.GlyphSpansTextureLayerWindows;
            } else {
                base = layer_base;
            }
        }
        return base;
    }

    const info = view.getGlyph(glyph_id) orelse return null;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return null;
    return view.glyphLayerWindowBase(info.page_index);
}
