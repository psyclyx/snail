const vec = @import("math/vec.zig");
const Transform2D = vec.Transform2D;
const snail = @import("snail.zig");
const SyntheticStyle = snail.SyntheticStyle;

pub const EmitResult = enum {
    emitted,
    skipped,
    buffer_full,
    layer_window_changed,
    invalid_transform,
};

fn hasRenderableBands(info: anytype) bool {
    return info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0;
}

pub fn emitGlyph(
    batch: anytype,
    view: anytype,
    glyph_id: u16,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
) EmitResult {
    if (view.getColrBase(glyph_id)) |cbi| {
        const info_loc = view.layerInfoLoc(cbi.info_x, cbi.info_y);
        batch.addColrGlyph(
            x,
            y,
            font_size,
            cbi.union_bbox,
            info_loc.x,
            info_loc.y,
            cbi.layer_count,
            color,
            view.glyphLayer(cbi.page_index),
        ) catch |err| return emitError(err);
        return .emitted;
    }

    var emitted = false;
    var layer_it = view.colrLayers(glyph_id);
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = view.getGlyph(layer.glyph_id) orelse continue;
            if (!hasRenderableBands(linfo)) continue;
            const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
            batch.addGlyph(x, y, font_size, linfo.bbox, linfo.band_entry, lcolor, view.glyphLayer(linfo.page_index)) catch |err| return emitError(err);
            emitted = true;
        }
        return if (emitted) .emitted else .skipped;
    }

    const info = view.getGlyph(glyph_id) orelse return .skipped;
    if (!hasRenderableBands(info)) return .skipped;
    batch.addGlyph(x, y, font_size, info.bbox, info.band_entry, color, view.glyphLayer(info.page_index)) catch |err| return emitError(err);
    return .emitted;
}

/// Emit a glyph with synthetic style transforms (bold offset, italic shear).
/// When synthetic has no transforms, delegates to emitGlyph.
pub fn emitStyledGlyph(
    batch: anytype,
    view: anytype,
    glyph_id: u16,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
    synthetic: SyntheticStyle,
) EmitResult {
    if (synthetic.skew_x == 0 and synthetic.embolden == 0) {
        return emitGlyph(batch, view, glyph_id, x, y, font_size, color);
    }

    const result = emitWithTransform(batch, view, glyph_id, x, y, font_size, color, synthetic.skew_x);
    if (result != .emitted) return result;

    // Synthetic bold: emit a second copy offset horizontally.
    if (synthetic.embolden != 0) {
        _ = emitWithTransform(batch, view, glyph_id, x + synthetic.embolden, y, font_size, color, synthetic.skew_x);
    }

    return .emitted;
}

pub fn emitGlyphWithTransform(
    batch: anytype,
    view: anytype,
    glyph_id: u16,
    color: [4]f32,
    transform: Transform2D,
) EmitResult {
    if (view.getColrBase(glyph_id)) |cbi| {
        const info_loc = view.layerInfoLoc(cbi.info_x, cbi.info_y);
        batch.addColrGlyphTransformed(
            cbi.union_bbox,
            info_loc.x,
            info_loc.y,
            cbi.layer_count,
            color,
            view.glyphLayer(cbi.page_index),
            transform,
        ) catch |err| return emitError(err);
        return .emitted;
    }

    var emitted = false;
    var layer_it = view.colrLayers(glyph_id);
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = view.getGlyph(layer.glyph_id) orelse continue;
            if (!hasRenderableBands(linfo)) continue;
            const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
            batch.addGlyphTransformed(linfo.bbox, linfo.band_entry, lcolor, view.glyphLayer(linfo.page_index), transform) catch |err| return emitError(err);
            emitted = true;
        }
        return if (emitted) .emitted else .skipped;
    }

    const info = view.getGlyph(glyph_id) orelse return .skipped;
    if (!hasRenderableBands(info)) return .skipped;
    batch.addGlyphTransformed(info.bbox, info.band_entry, color, view.glyphLayer(info.page_index), transform) catch |err| return emitError(err);
    return .emitted;
}

fn emitError(err: anyerror) EmitResult {
    return switch (err) {
        error.DrawListFull => .buffer_full,
        error.TextureLayerWindowChanged => .layer_window_changed,
        error.InvalidTransform => .invalid_transform,
        else => .buffer_full,
    };
}

/// Emit a glyph using the transformed vertex path with an optional italic shear.
/// The transform encodes font_size scaling, Y-flip, position, and shear into a
/// single affine matrix so the Slug curve evaluator's inverse Jacobian stays correct.
///
/// Em-space (ex, ey) maps to screen-space (sx, sy):
///   sx = font_size * ex + skew_x * font_size * ey + x
///   sy = -font_size * ey + y
///
/// At baseline (ey=0): no shear offset. Above baseline (ey>0): tops shift right.
fn emitWithTransform(
    batch: anytype,
    view: anytype,
    glyph_id: u16,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
    skew_x: f32,
) EmitResult {
    const transform = Transform2D{
        .xx = font_size,
        .xy = skew_x * font_size,
        .tx = x,
        .yx = 0,
        .yy = -font_size,
        .ty = y,
    };
    return emitGlyphWithTransform(batch, view, glyph_id, color, transform);
}
