const std = @import("std");
const atlas_mod = @import("text/atlas.zig");
const batch_mod = @import("text/batch.zig");
const bezier = @import("math/bezier.zig");
const blob_mod = @import("text/blob.zig");
const config_mod = @import("text/config.zig");
const glyph_atlas_mod = @import("text/glyph_atlas.zig");
const types_mod = @import("text/types.zig");
const view_mod = @import("text/view.zig");
const ttf = @import("font/ttf.zig");

pub const GlyphMetrics = ttf.GlyphMetrics;
pub const LineMetrics = ttf.LineMetrics;
pub const DecorationMetrics = ttf.DecorationMetrics;
pub const ScriptMetrics = ttf.ScriptMetrics;

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

/// Synthetic style transforms applied at the vertex level during glyph emission.
pub const SyntheticStyle = struct {
    /// Extra stroke offset in pixels (scaled by font_size / units_per_em). 0 = none.
    embolden: f32 = 0,
    /// Horizontal shear factor. 0.2 ~= 12 degrees synthetic italic. 0 = upright.
    skew_x: f32 = 0,
};

/// A parsed TrueType font. Immutable after init.
/// Thread-safe for concurrent reads (glyphIndex, getKerning).
/// The init/deinit, unitsPerEm, glyphIndex, and advanceWidth methods are part
/// of Snail's stable public API; `lowlevel.Font` is an alias for this type.
pub const Font = struct {
    inner: ttf.Font,

    /// Parse a TrueType font from raw file data.
    /// The data slice must outlive the Font.
    pub fn init(data: []const u8) !Font {
        return .{ .inner = try ttf.Font.init(data) };
    }

    pub fn deinit(self: *Font) void {
        _ = self;
    }

    pub fn unitsPerEm(self: *const Font) u16 {
        return self.inner.units_per_em;
    }

    pub fn glyphIndex(self: *const Font, codepoint: u32) !u16 {
        return self.inner.glyphIndex(codepoint);
    }

    pub fn getKerning(self: *const Font, left: u16, right: u16) !i16 {
        return self.inner.getKerning(left, right);
    }

    pub fn glyphMetrics(self: *const Font, glyph_id: u16) !GlyphMetrics {
        return self.inner.glyphMetrics(glyph_id);
    }

    /// Return ascent/descent/line_gap from the font `hhea` table, in font units.
    pub fn lineMetrics(self: *const Font) !LineMetrics {
        return self.inner.lineMetrics();
    }

    pub fn advanceWidth(self: *const Font, glyph_id: u16) !i16 {
        return self.inner.advanceWidth(glyph_id);
    }

    /// Underline and strikethrough metrics from the post and OS/2 tables, in font units.
    pub fn decorationMetrics(self: *const Font) !DecorationMetrics {
        return self.inner.decorationMetrics();
    }

    /// Superscript size and offset from the OS/2 table, in font units.
    pub fn superscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.superscriptMetrics();
    }

    /// Subscript size and offset from the OS/2 table, in font units.
    pub fn subscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.subscriptMetrics();
    }

    pub fn bbox(self: *const Font, glyph_id: u16) !bezier.BBox {
        return self.inner.bbox(glyph_id);
    }
};

pub fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}

pub const FaceSpec = config_mod.FaceSpec;
pub const FaceIndex = config_mod.FaceIndex;
pub const ItemizedRun = config_mod.ItemizedRun;
pub const FontConfig = config_mod.FontConfig;
pub const FaceConfig = config_mod.FaceConfig;
pub const FaceGlyphData = config_mod.FaceGlyphData;
pub const FaceView = view_mod.FaceView;
pub const glyph_atlas = glyph_atlas_mod;

pub const TextAtlas = atlas_mod.TextAtlas;
pub const TextBatch = batch_mod.TextBatch;
pub const ShapedText = types_mod.ShapedText;
pub const TextBlob = blob_mod.TextBlob;
pub const TextPlacement = types_mod.TextPlacement;
pub const TextAppend = types_mod.TextAppend;
pub const TextAppendResult = types_mod.TextAppendResult;
pub const TextBatchAppend = types_mod.TextBatchAppend;
pub const TextBlobBuilder = blob_mod.TextBlobBuilder;
pub const CellMetrics = types_mod.CellMetrics;
pub const CellMetricsOptions = types_mod.CellMetricsOptions;
pub const Decoration = types_mod.Decoration;
pub const ScriptTransform = types_mod.ScriptTransform;

pub const TEXT_WORDS_PER_VERTEX = batch_mod.WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = batch_mod.VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = batch_mod.WORDS_PER_GLYPH;

pub const appendTextDrawIntoBatch = batch_mod.appendTextDrawIntoBatch;
pub const textBlobRangeGpuInstanceBudget = blob_mod.textBlobRangeGpuInstanceBudget;

test {
    _ = @import("text/tests.zig");
}
