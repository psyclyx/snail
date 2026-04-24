pub const EmitResult = enum {
    emitted,
    skipped,
    buffer_full,
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
    const atlas = view.atlas;

    if (atlas.colr_base_map) |cbm| {
        if (cbm.get(glyph_id)) |cbi| {
            const info_loc = view.layerInfoLoc(cbi.info_x, cbi.info_y);
            if (!batch.addColrGlyph(
                x,
                y,
                font_size,
                cbi.union_bbox,
                info_loc.x,
                info_loc.y,
                cbi.layer_count,
                color,
                view.glyphLayer(cbi.page_index),
            )) return .buffer_full;
            return .emitted;
        }
    }

    var emitted = false;
    var layer_it = atlas.colrLayers(glyph_id);
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = atlas.getGlyph(layer.glyph_id) orelse continue;
            if (!hasRenderableBands(linfo)) continue;
            const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
            if (!batch.addGlyph(x, y, font_size, linfo.bbox, linfo.band_entry, lcolor, view.glyphLayer(linfo.page_index))) {
                return .buffer_full;
            }
            emitted = true;
        }
        return if (emitted) .emitted else .skipped;
    }

    const info = atlas.getGlyph(glyph_id) orelse return .skipped;
    if (!hasRenderableBands(info)) return .skipped;
    if (!batch.addGlyph(x, y, font_size, info.bbox, info.band_entry, color, view.glyphLayer(info.page_index))) {
        return .buffer_full;
    }
    return .emitted;
}
