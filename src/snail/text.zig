//! Public text-shaping types.
//!
//! The shaping orchestration lives in `text/faces.zig`; this file
//! exposes the small value types that signature into `ShapeOptions`,
//! `ShapedText`, and the picture builders. `Faces` is the only stateful
//! shaping noun, and `shape(faces, text, opts)` is the only entry
//! point.

const std = @import("std");

const hinter_mod = @import("font/hint_vm.zig");

pub const HintVm = hinter_mod.HintVm;
pub const HintPpem = hinter_mod.HintPpem;

const Allocator = std.mem.Allocator;

// ── Public types ──

pub const FaceIndex = u16;

/// Half-open source-byte range, in the coordinate system of the text
/// passed to `shape()`. `end` is exclusive.
pub const SourceRange = struct {
    start: u32,
    end: u32,
};

/// An OpenType feature request forwarded to the shaper. `tag` is the
/// 4-byte feature tag in font-canonical order (e.g.
/// `.{ 'l', 'i', 'g', 'a' }`). `value = 0` disables, `value >= 1`
/// enables (some features take an index). `range = null` applies the
/// feature to the entire text; a non-null range restricts it to those
/// source bytes.
pub const OpenTypeFeature = struct {
    tag: [4]u8,
    value: u32 = 1,
    range: ?SourceRange = null,
};

pub const ShapeOptions = struct {
    features: []const OpenTypeFeature = &.{},
    /// Style selector for the face chain (regular/bold/italic).
    style: FontStyle = .{},
    /// Closure invoked from HarfBuzz's `glyph_h_advance` font_func.
    /// Returns the advance in 26.6 fixed-point pixels for
    /// `(font_id, glyph_id)` at `target_ppem`. Faces the provider
    /// doesn't `covers()` shape em-space; the emitted advances are
    /// always em-space (the 26.6 values are divided by `ppem_26_6` so
    /// multiplying by `ppem_px` downstream recovers the original 26.6
    /// pixel positions exactly).
    ///
    /// A typical caller wires this to
    /// `helpers.HintedGlyphCache.asAdvanceProvider()` so HB lookups hit
    /// the cache, falling back to the underlying `HintVm` on miss.
    advance_provider: ?AdvanceProvider = null,
    /// Ppem to shape at. Two roles, both shape-time:
    ///   1. HB's sub-font scale is set to this so positions come back
    ///      in 26.6 units of this ppem (the caller divides by ppem to
    ///      recover em-space offsets).
    ///   2. Passed to `advance_provider.get_advance` so the provider
    ///      can look up the right hinted advance.
    /// The provider does *not* carry its own ppem — it's a pure
    /// `(font_id, glyph_id, ppem) → advance` function. Required
    /// whenever `advance_provider` is non-null; ignored otherwise.
    target_ppem: ?HintPpem = null,
};

/// Closure handed to `ShapeOptions.advance_provider` so the shaping
/// callback can route through caller-owned state (a `HintedGlyphCache`,
/// a debug hook, a synthetic-metric source — anything that yields a
/// 26.6 advance for `(font_id, glyph_id)` and a ppem).
///
/// `covers` lets shape() ask whether the provider has meaningful
/// advances for a given font_id before attaching it to that face's HB
/// sub_font; faces not covered shape em-space. Without this hook a
/// single-font cache would mis-route advances for other faces in the
/// same run (Latin + emoji etc).
pub const AdvanceProvider = struct {
    context: *anyopaque,
    covers: *const fn (context: *anyopaque, font_id: u32) bool,
    get_advance: *const fn (context: *anyopaque, font_id: u32, glyph_id: u16, ppem: HintPpem) i32,
};

pub const FontWeight = enum(u4) {
    thin = 1,
    extra_light = 2,
    light = 3,
    regular = 4,
    medium = 5,
    semi_bold = 6,
    bold = 7,
    extra_bold = 8,
    black = 9,
};

pub const FontStyle = struct {
    weight: FontWeight = .regular,
    italic: bool = false,
};

/// Synthetic style hints attached to a face spec. The shaper carries
/// them on the face state so callers can read them back when laying
/// out glyphs.
pub const SyntheticStyle = struct {
    embolden: f32 = 0,
    skew_x: f32 = 0,
};

pub const MissingGlyphReplacement = struct {
    face_index: FaceIndex,
    glyph_id: u16,
    codepoint: u21,
};

pub const ShapedText = struct {
    allocator: Allocator,
    glyphs: []Glyph,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        x_offset: f32,
        y_offset: f32,
        x_advance: f32,
        y_advance: f32,
        source_start: u32,
        source_end: u32,
        /// Resolved font id, set by `shape(faces, ...)` from
        /// `faces.fontIdForFace(face_index)`. Picture builders read it
        /// directly to key atlas records.
        font_id: u32 = 0,
    };

    pub fn advanceX(self: *const ShapedText) f32 {
        var sum: f32 = 0;
        for (self.glyphs) |g| sum += g.x_advance;
        return sum;
    }

    pub fn advanceY(self: *const ShapedText) f32 {
        var sum: f32 = 0;
        for (self.glyphs) |g| sum += g.y_advance;
        return sum;
    }

    pub fn deinit(self: *ShapedText) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}
