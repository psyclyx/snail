//! The renderable form of any shape: a packed list of Bezier curve segments
//! plus the band lookup table the renderer uses to find candidate curves per
//! sample.
//!
//! Four producers return this type, all interchangeable downstream:
//!   - `font.extractCurves`           — unhinted glyph outlines
//!   - `hinter.hint`                  — hinted (TT bytecode) glyph outlines
//!   - `pathToCurves`                 — filled paths
//!   - `strokeToCurves`               — stroked paths (offset curve expansion)
//!
//! `GlyphCurves` itself is an immutable value owned by an allocator. It carries
//! the raw packed bytes that go into an atlas page (curve texture and band
//! texture data), plus enough metadata for the atlas to size and address it.

const std = @import("std");
const bezier = @import("math/bezier.zig");

pub const BBox = bezier.BBox;

pub const GlyphCurves = struct {
    allocator: std.mem.Allocator,
    /// Packed curve texture bytes (u16 half-floats, four texels per segment).
    curve_bytes: []const u16,
    /// Packed band texture bytes (u16 indices).
    band_bytes: []const u16,
    /// Number of curve segments (each segment occupies `SEGMENT_TEXELS` texels).
    curve_count: u16,
    /// Horizontal and vertical band counts (used by the renderer to walk only
    /// the candidate curves per sample).
    h_band_count: u16,
    v_band_count: u16,
    /// Bounding box of the shape in its local (untransformed) coordinate space.
    bbox: BBox,

    pub fn deinit(self: *GlyphCurves) void {
        self.allocator.free(self.curve_bytes);
        self.allocator.free(self.band_bytes);
        self.* = undefined;
    }

    /// Byte size of the curve texture footprint (curves only, not bands).
    pub fn curveBytes(self: *const GlyphCurves) usize {
        return self.curve_bytes.len * @sizeOf(u16);
    }

    /// Byte size of the band lookup footprint.
    pub fn bandBytes(self: *const GlyphCurves) usize {
        return self.band_bytes.len * @sizeOf(u16);
    }

    /// Empty curves (no shape). Useful as a sentinel for missing glyphs that
    /// should still occupy a slot (e.g. ASCII space).
    pub fn empty(allocator: std.mem.Allocator) GlyphCurves {
        return .{
            .allocator = allocator,
            .curve_bytes = &[_]u16{},
            .band_bytes = &[_]u16{},
            .curve_count = 0,
            .h_band_count = 0,
            .v_band_count = 0,
            .bbox = .{ .min = .zero, .max = .zero },
        };
    }

    pub fn isEmpty(self: *const GlyphCurves) bool {
        return self.curve_count == 0;
    }
};

test "empty curves round-trip" {
    var c = GlyphCurves.empty(std.testing.allocator);
    defer c.deinit();
    try std.testing.expect(c.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), c.curveBytes());
}
