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
const curve_tex = @import("../format/curve_texture.zig");

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
    pub const CloneError = std.mem.Allocator.Error || error{ShapeTooLarge};

    pub fn clone(self: *const GlyphCurves, allocator: std.mem.Allocator) CloneError!GlyphCurves {
        const backing_len = std.math.add(usize, self.curve_bytes.len, self.band_bytes.len) catch
            return error.ShapeTooLarge;
        const backing = try allocator.alloc(u16, backing_len);
        @memcpy(backing[0..self.curve_bytes.len], self.curve_bytes);
        @memcpy(backing[self.curve_bytes.len..], self.band_bytes);
        var copy = self.*;
        copy.allocator = allocator;
        copy.curve_bytes = backing[0..self.curve_bytes.len];
        copy.band_bytes = backing[self.curve_bytes.len..];
        copy.backing = backing;
        return copy;
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

    pub const ValidationError = error{InvalidCurves};

    /// Validate the packed texture payload before it crosses into the atlas.
    /// `GlyphCurves` is intentionally constructible by custom producers, so
    /// the atlas cannot assume its slices and scalar metadata were emitted by
    /// snail's own packers.
    pub fn validate(self: *const GlyphCurves) ValidationError!void {
        const segment_words = curve_tex.SEGMENT_TEXELS * 4;
        const expected_curve_words = @as(usize, self.curve_count) * segment_words;
        if (self.curve_bytes.len != expected_curve_words) return error.InvalidCurves;
        for (0..self.curve_count) |curve_index| {
            const curve_texel: u32 = @intCast(curve_index * curve_tex.SEGMENT_TEXELS);
            if (curve_tex.decodeSegmentAt(self.curve_bytes, curve_texel) == null) return error.InvalidCurves;
        }

        const scalar_values = [_]f32{
            self.band_scale_x,
            self.band_scale_y,
            self.band_offset_x,
            self.band_offset_y,
            self.bbox.min.x,
            self.bbox.min.y,
            self.bbox.max.x,
            self.bbox.max.y,
        };
        for (scalar_values) |value| {
            if (!std.math.isFinite(value)) return error.InvalidCurves;
        }
        if (self.bbox.min.x > self.bbox.max.x or self.bbox.min.y > self.bbox.max.y) {
            return error.InvalidCurves;
        }

        if (self.curve_count == 0) {
            if (self.band_bytes.len != 0 or self.h_band_count != 0 or self.v_band_count != 0) {
                return error.InvalidCurves;
            }
            return;
        }

        // A band reference stores its first-membership index in four bits.
        // The regular instance ABI also requires non-zero counts before it
        // encodes count-1.
        const max_bands: u16 = 1 << 4;
        if (self.h_band_count == 0 or self.v_band_count == 0 or
            self.h_band_count > max_bands or self.v_band_count > max_bands or
            self.band_bytes.len % 2 != 0)
        {
            return error.InvalidCurves;
        }

        const header_count = @as(usize, self.h_band_count) + @as(usize, self.v_band_count);
        const total_texels = self.band_bytes.len / 2;
        if (total_texels < header_count) return error.InvalidCurves;

        var expected_ref_texel = header_count;
        for (0..header_count) |band_index| {
            const count = @as(usize, self.band_bytes[band_index * 2]);
            const offset = @as(usize, self.band_bytes[band_index * 2 + 1]);
            if (offset != expected_ref_texel or count > total_texels - expected_ref_texel) {
                return error.InvalidCurves;
            }

            const axis_band_count: u16 = if (band_index < self.h_band_count)
                self.h_band_count
            else
                self.v_band_count;
            for (expected_ref_texel..expected_ref_texel + count) |ref_texel| {
                const w0 = self.band_bytes[ref_texel * 2];
                const w1 = self.band_bytes[ref_texel * 2 + 1];
                const first_member_band = w0 >> 12;
                if (first_member_band >= axis_band_count) return error.InvalidCurves;

                // x occupies 12 bits and y 14; y's high two bits carry the
                // curve kind. References must point at a segment start in
                // this glyph's local curve block.
                const curve_texel = @as(u32, w1 & 0x3fff) * curve_tex.TEX_WIDTH +
                    @as(u32, w0 & 0x0fff);
                if (curve_texel % curve_tex.SEGMENT_TEXELS != 0 or
                    curve_texel / curve_tex.SEGMENT_TEXELS >= self.curve_count)
                {
                    return error.InvalidCurves;
                }
            }
            expected_ref_texel += count;
        }
        if (expected_ref_texel != total_texels) return error.InvalidCurves;
    }
};

test "empty curves round-trip" {
    var c = GlyphCurves.empty(std.testing.allocator);
    defer c.deinit();
    try std.testing.expect(c.isEmpty());
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

test "validate rejects inconsistent and out-of-range packed payloads" {
    const allocator = std.testing.allocator;
    var empty = GlyphCurves.empty(allocator);
    try empty.validate();

    empty.bbox.max.x = std.math.nan(f32);
    try std.testing.expectError(error.InvalidCurves, empty.validate());
    empty.bbox.max.x = 0;

    empty.curve_count = 1;
    try std.testing.expectError(error.InvalidCurves, empty.validate());

    var curve_words = [_]u16{0} ** (curve_tex.SEGMENT_TEXELS * 4);
    // Two one-band headers followed by one reference for each axis.
    var band_words = [_]u16{ 1, 2, 1, 3, 0, 0, 0, 0 };
    const valid = GlyphCurves{
        .allocator = allocator,
        .curve_bytes = &curve_words,
        .band_bytes = &band_words,
        .curve_count = 1,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1,
        .band_scale_y = 1,
        .band_offset_x = 0,
        .band_offset_y = 0,
        .bbox = .{ .min = .zero, .max = .{ .x = 1, .y = 1 } },
    };
    try valid.validate();

    curve_words[0] = @bitCast(std.math.nan(f16));
    try std.testing.expectError(error.InvalidCurves, valid.validate());
    curve_words[0] = 0;

    curve_words[10] = curve_tex.f32ToF16(9);
    try std.testing.expectError(error.InvalidCurves, valid.validate());
    curve_words[10] = 0;

    band_words[5] = 1; // local texel 4096 is outside the single curve
    try std.testing.expectError(error.InvalidCurves, valid.validate());
}
