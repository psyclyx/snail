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
const bezier = @import("../math/bezier.zig");

pub const BBox = bezier.BBox;

pub const GlyphCurves = struct {
    allocator: std.mem.Allocator,
    /// Packed curve texture bytes (u16 half-floats, four texels per segment).
    /// Laid out exactly as the existing `format/curve_texture.zig`
    /// format expects, with the glyph's first segment at byte 0.
    curve_bytes: []const u16,
    /// Packed band texture bytes (u16 indices). Curve refs are encoded
    /// assuming the glyph's first curve sits at texel 0 of the curve
    /// texture; the atlas rewrites them at insertion time to absolute
    /// page-local texel positions.
    band_bytes: []const u16,
    /// When non-null, both `curve_bytes` and `band_bytes` are slice views
    /// into this single combined allocation, and `deinit` frees only
    /// `backing`. Used by hot paths that want to coalesce the two
    /// allocations into one (eg. the TtHintVm's cached-glyph clone). When
    /// null, `deinit` frees `curve_bytes` and `band_bytes` independently.
    backing: ?[]u16 = null,
    /// Number of curve segments (each segment occupies `SEGMENT_TEXELS` texels).
    curve_count: u16,
    /// Horizontal and vertical band counts (used by the renderer to walk only
    /// the candidate curves per sample).
    h_band_count: u16,
    v_band_count: u16,
    /// Band transform: maps local-space coords to band indices. Computed by
    /// the producer at curve-build time. Carried on `GlyphCurves` (not
    /// recomputed at insertion) because it depends on the same dilated
    /// bbox used to bucket curves into bands.
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
    /// Bounding box of the shape in its local (untransformed) coordinate space.
    bbox: BBox,

    pub fn deinit(self: *GlyphCurves) void {
        if (self.backing) |b| {
            self.allocator.free(b);
        } else {
            self.allocator.free(self.curve_bytes);
            self.allocator.free(self.band_bytes);
        }
        self.* = undefined;
    }

    /// Deep-copy into a fresh allocation owned by `allocator`. The copy
    /// coalesces `curve_bytes` and `band_bytes` into a single `backing`
    /// buffer, so `deinit` frees exactly once. Scalar metadata is copied
    /// wholesale, so the invariant can't drift as fields are added.
    pub fn clone(self: *const GlyphCurves, allocator: std.mem.Allocator) std.mem.Allocator.Error!GlyphCurves {
        const backing = try allocator.alloc(u16, self.curve_bytes.len + self.band_bytes.len);
        @memcpy(backing[0..self.curve_bytes.len], self.curve_bytes);
        @memcpy(backing[self.curve_bytes.len..], self.band_bytes);
        var copy = self.*;
        copy.allocator = allocator;
        copy.curve_bytes = backing[0..self.curve_bytes.len];
        copy.band_bytes = backing[self.curve_bytes.len..];
        copy.backing = backing;
        return copy;
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
            .band_scale_x = 0,
            .band_scale_y = 0,
            .band_offset_x = 0,
            .band_offset_y = 0,
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

test "clone deep-copies bytes and metadata into one backing" {
    const allocator = std.testing.allocator;
    var src = GlyphCurves.empty(allocator);
    src.curve_bytes = try allocator.dupe(u16, &[_]u16{ 1, 2, 3 });
    src.band_bytes = try allocator.dupe(u16, &[_]u16{ 4, 5 });
    src.curve_count = 1;
    src.h_band_count = 2;
    src.bbox = .{ .min = .{ .x = -1, .y = -2 }, .max = .{ .x = 3, .y = 4 } };
    defer src.deinit();

    var dst = try src.clone(allocator);
    defer dst.deinit();

    try std.testing.expectEqualSlices(u16, src.curve_bytes, dst.curve_bytes);
    try std.testing.expectEqualSlices(u16, src.band_bytes, dst.band_bytes);
    try std.testing.expectEqual(src.curve_count, dst.curve_count);
    try std.testing.expectEqual(src.h_band_count, dst.h_band_count);
    try std.testing.expectEqual(src.bbox.min.x, dst.bbox.min.x);
    // Copy owns a single coalesced allocation, independent of the source.
    try std.testing.expect(dst.backing != null);
    try std.testing.expect(dst.curve_bytes.ptr != src.curve_bytes.ptr);
}
