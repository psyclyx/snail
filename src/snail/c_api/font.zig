const common = @import("common.zig");
const ttf = common.ttf;
const createHandle = common.createHandle;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_INVALID_FONT = common.SNAIL_ERR_INVALID_FONT;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SnailBBox = common.SnailBBox;
const SnailGlyphMetrics = common.SnailGlyphMetrics;
const SnailLineMetrics = common.SnailLineMetrics;
const SnailDecorationMetrics = common.SnailDecorationMetrics;
const SnailScriptMetrics = common.SnailScriptMetrics;
const wrapBBox = common.wrapBBox;
const wrapDecorationMetrics = common.wrapDecorationMetrics;
const wrapScriptMetrics = common.wrapScriptMetrics;
const FontImpl = common.FontImpl;
const destroyHandle = common.destroyHandle;

// Font metrics helper

pub export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const font = ttf.Font.init(data[0..len]) catch return SNAIL_ERR_INVALID_FONT;
    const impl = createHandle(FontImpl, null) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.inner = font;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_font_deinit(font: ?*FontImpl) void {
    if (font) |f| destroyHandle(f);
}

pub export fn snail_font_units_per_em(font: *const FontImpl) u16 {
    return font.inner.units_per_em;
}

pub export fn snail_font_glyph_index(font: *const FontImpl, codepoint: u32) u16 {
    return font.inner.glyphIndex(codepoint) catch 0;
}

pub export fn snail_font_get_kerning(font: *const FontImpl, left: u16, right: u16) i16 {
    return font.inner.getKerning(left, right) catch 0;
}

pub export fn snail_font_glyph_metrics(font: *const FontImpl, glyph_id: u16, out: *SnailGlyphMetrics) c_int {
    const m = font.inner.glyphMetrics(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .advance_width = m.advance_width, .lsb = m.lsb, .bbox = wrapBBox(m.bbox) };
    return SNAIL_OK;
}

pub export fn snail_font_line_metrics(font: *const FontImpl, out: *SnailLineMetrics) c_int {
    const m = font.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_font_decoration_metrics(font: *const FontImpl, out: *SnailDecorationMetrics) c_int {
    out.* = wrapDecorationMetrics(font.inner.decorationMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_superscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.superscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_subscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.subscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_advance_width(font: *const FontImpl, glyph_id: u16, out: *i16) c_int {
    out.* = font.inner.advanceWidth(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

pub export fn snail_font_bbox(font: *const FontImpl, glyph_id: u16, out: *SnailBBox) c_int {
    out.* = wrapBBox(font.inner.bbox(glyph_id) catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}
