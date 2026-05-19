const bezier = @import("math/bezier.zig");
const ttf = @import("font/ttf.zig");

pub const GlyphMetrics = ttf.GlyphMetrics;
pub const LineMetrics = ttf.LineMetrics;
pub const DecorationMetrics = ttf.DecorationMetrics;
pub const ScriptMetrics = ttf.ScriptMetrics;
pub const tt = struct {
    pub const exec = @import("font/tt_exec.zig");
    pub const graphics = @import("font/tt_graphics.zig");
    pub const outline = @import("font/tt_outline.zig");
    pub const points = @import("font/tt_points.zig");
    pub const tables = @import("font/tt_tables.zig");
    pub const vm = @import("font/tt_vm.zig");
};

test {
    _ = tt.exec.Context;
    _ = tt.graphics.GraphicsState;
    _ = tt.outline.Point;
    _ = tt.points.Zone;
    _ = tt.tables.ProgramTables;
    _ = tt.vm.Program;
}

/// A parsed TrueType font. Immutable after init.
/// Thread-safe for concurrent reads (glyphIndex, getKerning).
/// The init/deinit, unitsPerEm, glyphIndex, and advanceWidth methods are part
/// of Snail's stable public API.
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
