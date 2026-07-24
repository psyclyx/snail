const std = @import("std");
const band_tex = @import("band_texture.zig");
const bezier = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");
const vertex = @import("vertex.zig");
const render_abi = @import("abi.zig");

const BBox = bezier.BBox;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Transform2D = vec.Transform2D;

pub const WORDS_PER_INSTANCE = vertex.WORDS_PER_INSTANCE;

pub const CursorError = error{
    /// The instance buffer has no room for another instance.
    BufferTooSmall,
    /// The packed instance could not be represented or violated an ABI
    /// invariant. Higher-level emitters should preflight detailed errors.
    InvalidInstance,
};

/// Incremental writer over an instance-word buffer.
///
/// Owns the mechanics every instance emitter repeats: the capacity check, the
/// packed-vertex ABI write (via `vertex.generate*`), and the per-instance
/// advance. It is layer-policy-agnostic — the caller resolves the atlas layer
/// (a `u8` texture-array index) and passes it in.
pub const Cursor = struct {
    buf: []u32,
    len: *usize,

    fn ensureInstanceCapacity(self: Cursor) CursorError!void {
        if (self.len.* > self.buf.len or self.buf.len - self.len.* < WORDS_PER_INSTANCE) {
            return error.BufferTooSmall;
        }
    }

    fn dst(self: Cursor) []u32 {
        return self.buf[self.len.*..][0..WORDS_PER_INSTANCE];
    }

    fn commit(self: Cursor) void {
        self.len.* += WORDS_PER_INSTANCE;
    }

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
            return error.InvalidInstance;
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
        policy: [4]u32,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateAutohintVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform, policy))
            return error.InvalidInstance;
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
        curve_class: render_abi.PathCurveClass,
    ) CursorError!void {
        try self.ensureInstanceCapacity();
        if (!vertex.generateClassifiedPathRecordVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform, curve_class))
            return error.InvalidInstance;
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
            return error.InvalidInstance;
        self.commit();
    }

    pub fn appendTtHintedTextTransformedTinted(
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
        if (!vertex.generateTtHintedTextVerticesTransformedTinted(self.dst(), bbox, info_x, info_y, layer_count, color, tint, layer, transform))
            return error.InvalidInstance;
        self.commit();
    }
};

test "cursor capacity check is total for an invalid or overflowing length" {
    var storage: [WORDS_PER_INSTANCE]u32 = undefined;
    var invalid_len: usize = std.math.maxInt(usize);
    const invalid_cursor = Cursor{ .buf = &storage, .len = &invalid_len };
    try std.testing.expectError(error.BufferTooSmall, invalid_cursor.ensureInstanceCapacity());

    var short_len: usize = 1;
    const short_cursor = Cursor{ .buf = storage[0..WORDS_PER_INSTANCE], .len = &short_len };
    try std.testing.expectError(error.BufferTooSmall, short_cursor.ensureInstanceCapacity());
}
