const band_tex = @import("band_texture.zig");
const bezier = @import("../../math/bezier.zig");
const vec = @import("../../math/vec.zig");
const vertex = @import("vertex.zig");

const BBox = bezier.BBox;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Transform2D = vec.Transform2D;

pub const WORDS_PER_INSTANCE = vertex.WORDS_PER_INSTANCE;

const identity_tint = [4]f32{ 1, 1, 1, 1 };

pub const CursorError = error{
    /// The instance buffer has no room for another instance.
    BufferTooSmall,
    /// A composed transform had a near-zero determinant.
    InvalidTransform,
};

/// Incremental writer over an instance-word buffer.
///
/// Owns the mechanics every instance emitter repeats: the capacity check, the
/// packed-vertex ABI write (via `vertex.generate*`), and the per-instance
/// advance. It is layer-policy-agnostic — the caller resolves the atlas layer
/// (a `u8` texture-array index) and passes it in, so the same writer serves
/// both the batch `picture.emit` path and immediate-mode callers.
pub const Cursor = struct {
    buf: []u32,
    len: *usize,

    fn ensureInstanceCapacity(self: Cursor) CursorError!void {
        if (self.len.* + WORDS_PER_INSTANCE > self.buf.len) return error.BufferTooSmall;
    }

    fn dst(self: Cursor) []u32 {
        return self.buf[self.len.*..][0..WORDS_PER_INSTANCE];
    }

    fn commit(self: Cursor) void {
        self.len.* += WORDS_PER_INSTANCE;
    }

    // ── transformed variants (batch + immediate-mode) ────────────────────────

    pub fn appendGlyphTransformedTinted(
        self: Cursor,
        bbox: BBox,
        band_entry: GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        layer: u8,
        transform: Transform2D,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateGlyphVerticesTransformedTinted(self.dst(), bbox, band_entry, color, tint, layer, transform))
            return error.InvalidTransform;
        self.commit();
    }

    pub fn appendAutohintTransformedTinted(
        self: Cursor,
        bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        layer: u8,
        transform: Transform2D,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateAutohintVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform))
            return error.InvalidTransform;
        self.commit();
    }

    pub fn appendPathRecordTransformedTinted(
        self: Cursor,
        bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        layer: u8,
        transform: Transform2D,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generatePathRecordVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform))
            return error.InvalidTransform;
        self.commit();
    }

    pub fn appendMultiLayerGlyphTransformedTinted(
        self: Cursor,
        bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        layer: u8,
        transform: Transform2D,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateMultiLayerGlyphVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform))
            return error.InvalidTransform;
        self.commit();
    }

    pub fn appendHintedTextTransformedTinted(
        self: Cursor,
        bbox: BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        layer: u8,
        transform: Transform2D,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateHintedTextVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform))
            return error.InvalidTransform;
        self.commit();
    }

    // ── axis-aligned convenience (immediate-mode) ────────────────────────────

    pub fn appendGlyph(
        self: Cursor,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: BBox,
        band_entry: GlyphBandEntry,
        color: [4]f32,
        layer: u8,
    ) CursorError!void {
        try self.appendGlyphTinted(x, y, font_size, bbox, band_entry, color, identity_tint, layer);
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
        layer: u8,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        vertex.generateGlyphVerticesTinted(self.dst(), x, y, font_size, bbox, band_entry, color, tint, layer);
        self.commit();
    }
};
