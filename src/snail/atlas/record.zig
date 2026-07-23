//! A resolved handle to one record on one atlas page.
//!
//! Pictures and shapes hold `RecordKey`s; the atlas resolves them to
//! `AtlasRecord`s at emit time. `AtlasRecord` is exposed publicly so callers
//! using the custom-shader path can pack their own vertex data.
//!
//! `page_generation` is a guard against stale references: pages are reused
//! when their refcount drops to zero, and a record issued at generation G
//! is invalid once the page has been recycled to generation G+1. Records
//! held in the live reference graph (i.e. via an Atlas) can never go stale,
//! because the Atlas itself holds a refcount on the page. Stale records only
//! happen if a caller persists one outside the graph (e.g. across a process
//! boundary).

const std = @import("std");
const bezier = @import("../math/bezier.zig");

pub const BBox = bezier.BBox;

/// One entry into a page's band texture. The fields mirror the existing
/// `format/band_texture.zig` `GlyphBandEntry` layout so emit can copy them
/// directly into the GPU instance format.
pub const GlyphBandEntry = struct {
    glyph_x: u16,
    glyph_y: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

pub const AtlasRecord = struct {
    /// Index into the owning Atlas's `pages` slice.
    page_index: u16,
    /// Snapshot of `AtlasPage.generation` at the time the record was issued.
    page_generation: u64,
    /// Starting texel within the page's curve texture.
    curve_texel: u32,
    /// Number of curve segments (each occupies `SEGMENT_TEXELS` texels).
    curve_count: u16,
    /// Band-lookup metadata for the page's band texture.
    bands: GlyphBandEntry,
    /// Local-space bounding box.
    bbox: BBox,
};

test "atlas record is value type" {
    const rec = AtlasRecord{
        .page_index = 0,
        .page_generation = 1,
        .curve_texel = 0,
        .curve_count = 1,
        .bands = .{
            .glyph_x = 0,
            .glyph_y = 0,
            .h_band_count = 1,
            .v_band_count = 1,
            .band_scale_x = 1,
            .band_scale_y = 1,
            .band_offset_x = 0,
            .band_offset_y = 0,
        },
        .bbox = .{ .min = .zero, .max = .zero },
    };
    const copy = rec;
    try std.testing.expectEqual(rec.curve_texel, copy.curve_texel);
}
