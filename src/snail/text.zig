//! Public text-shaping types.
//!
//! The shaping orchestration lives in `text/faces.zig`; this file
//! exposes the small value types that signature into `ShapeOptions`,
//! `ShapedText`, and the picture builders. `Faces` is the only stateful
//! shaping noun, and `shape(faces, text, opts)` is the only entry
//! point.

const std = @import("std");

const hinter_mod = @import("font/tt_hint_vm.zig");

pub const TtHintVm = hinter_mod.TtHintVm;
pub const TtHintPpem = hinter_mod.TtHintPpem;

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

/// Text-flow direction passed to HarfBuzz. Leave `ShapeOptions.direction`
/// null to let HarfBuzz infer the direction from the text and script.
pub const TextDirection = enum {
    ltr,
    rtl,
    ttb,
    btt,
};

pub const ShapeOptions = struct {
    features: []const OpenTypeFeature = &.{},
    /// Style selector for the face chain (regular/bold/italic).
    style: FontStyle = .{},
    /// Explicit text-flow direction. `null` asks HarfBuzz to infer it.
    /// This controls shaping within each fallback-font run; it is not a
    /// replacement for paragraph-level Unicode bidi layout.
    direction: ?TextDirection = null,
    /// Optional ISO 15924 script tag, such as `"Latn".*` or `"Arab".*`.
    /// `null` asks HarfBuzz to infer the script.
    script: ?[4]u8 = null,
    /// Optional BCP 47 language tag. The slice is borrowed only for the
    /// duration of `shape()` and must be non-empty when present.
    language: ?[]const u8 = null,
    /// Closure invoked from HarfBuzz's `glyph_h_advance` font_func.
    /// Returns the advance in 26.6 fixed-point pixels for
    /// `(font_id, glyph_id)` at `target_ppem`. Faces the provider
    /// doesn't `covers()` shape em-space; the emitted advances are
    /// always em-space (the 26.6 values are divided by `ppem_26_6` so
    /// multiplying by `ppem_px` downstream recovers the original 26.6
    /// pixel positions exactly).
    ///
    /// A typical caller wires this to
    /// `snail.TtAdvanceSource.advanceProvider()` so HB lookups hit
    /// recorded `ns.tt_advance` values, falling back to the pure VM on miss.
    advance_provider: ?AdvanceProvider = null,
    /// Ppem used when `advance_provider` covers the face being shaped. It has
    /// two shape-time roles for those faces:
    ///   1. HB's provider sub-font scale is set to this so positions come back
    ///      in 26.6 units of this ppem (the caller divides by ppem to recover
    ///      em-space offsets).
    ///   2. It is passed to `advance_provider.get_advance` so the provider can
    ///      look up the right hinted advance.
    /// The provider does *not* carry its own ppem — it's a pure
    /// `(font_id, glyph_id, ppem) → advance` function. Required
    /// whenever `advance_provider` is non-null. Faces the provider does not
    /// cover continue to use the font's ordinary em scale. A missing value is
    /// reported
    /// as `error.MissingTargetPpem`; zero or values above the exact atlas-key
    /// range are reported as `error.InvalidPpem`. A supplied ppem is validated
    /// even when no provider is active, so invalid options never fail silently.
    target_ppem: ?TtHintPpem = null,
};

/// Closure handed to `ShapeOptions.advance_provider` so the shaping
/// callback can route through caller-owned state (a `TtAdvanceSource`,
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
    /// Returns the 26.6 advance, or null when the provider cannot supply
    /// one (e.g. a hint-VM failure for this glyph). On null, shaping falls
    /// back to the font's native em-scaled advance for that glyph, so a
    /// single bad glyph degrades to unhinted spacing instead of collapsing
    /// to zero width. Providers should expose their own error state (see
    /// `TtAdvanceSource.last_error`) so hosts can observe the fallback.
    get_advance: *const fn (context: *anyopaque, font_id: u32, glyph_id: u16, ppem: TtHintPpem) ?i32,
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
        /// First byte of this glyph's HarfBuzz cluster in the original UTF-8
        /// input. Bounds remain in logical source order even when glyph output
        /// is RTL. A ligature can start a multi-unit range, and multiple glyphs
        /// can share one range.
        source_start: u32,
        /// Exclusive end byte of the source cluster begun at `source_start`.
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
