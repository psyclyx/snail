//! Shared layer-info / paint-record patching for new-API prepared-page
//! caches. Legacy atlas-slot decision logic lived here too; that surface
//! was removed in the scorched-earth pass — only `patchImagePaintRecord`
//! and its helpers remain, used by the GL/Vulkan/CPU `backend_cache`
//! modules to write live image-layer indices into the layer-info texture
//! when uploading paint records.

fn layerInfoTexelBase(width: u32, x: u32, y: u32) usize {
    return (y * width + x) * 4;
}

fn layerInfoTexelBaseFromSourceOffset(dst_width: u32, src_width: u32, row_base: u32, texel_offset: u32) usize {
    const texel_x = texel_offset % src_width;
    const texel_y = row_base + texel_offset / src_width;
    return layerInfoTexelBase(dst_width, texel_x, texel_y);
}

pub fn patchImagePaintRecord(data: []f32, dst_width: u32, src_width: u32, row_base: u32, texel_offset: u32, view: anytype) void {
    const transform_base = layerInfoTexelBaseFromSourceOffset(dst_width, src_width, row_base, texel_offset + 2);
    data[transform_base + 3] = @floatFromInt(view.layer);
    const extra_base = layerInfoTexelBaseFromSourceOffset(dst_width, src_width, row_base, texel_offset + 5);
    data[extra_base + 0] = view.uv_scale.x;
    data[extra_base + 1] = view.uv_scale.y;
}
