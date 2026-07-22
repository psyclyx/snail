//! Public data contract for caller-owned renderers.
//!
//! Snail prepares atlas data and draw records; callers own GPU objects, shader
//! entry points, command submission, and presentation. Only the symbols needed
//! to consume those prepared bytes are exposed here. Encoding, cache allocation,
//! and renderer implementation helpers remain private to their owners.

const abi_mod = @import("format/abi.zig");
const vertex_mod = @import("format/vertex.zig");
const draw_mod = @import("draw/records.zig");
const curve_texture_mod = @import("format/curve_texture.zig");
const band_texture_mod = @import("format/band_texture.zig");
const autohint_record_mod = @import("format/autohint_record.zig");
const curve_mod = @import("math/bezier.zig");

/// Emitted packed instances, batch metadata, and symbolic record decoders.
pub const records = struct {
    pub const abi_version = abi_mod.version;

    pub const Instance = vertex_mod.Instance;
    pub const BYTES_PER_INSTANCE = vertex_mod.BYTES_PER_INSTANCE;
    pub const InstanceValidationError = vertex_mod.ValidationError;
    pub const validateInstance = vertex_mod.validateInstance;

    pub const Binding = draw_mod.Binding;
    pub const DrawBatch = draw_mod.DrawBatch;
    pub const DrawRecords = draw_mod.DrawRecords;
    pub const ShapeKind = draw_mod.ShapeKind;
    pub const shapeKind = draw_mod.shapeKind;

    pub const SpecialLayerKind = abi_mod.SpecialLayerKind;
    pub const PaintRecordKind = abi_mod.PaintRecordKind;
    pub const BandCounts = abi_mod.BandCounts;
    pub const paint_texels_per_record = abi_mod.paint_texels_per_record;
    pub const composite_mode_fill_stroke_inside = abi_mod.composite_mode_fill_stroke_inside;
    pub const glyphLocationX = abi_mod.glyphLocationX;
    pub const glyphLocationY = abi_mod.glyphLocationY;
    pub const glyphWordAtlasLayer = abi_mod.glyphWordAtlasLayer;
    pub const glyphWordIsSpecial = abi_mod.glyphWordIsSpecial;
    pub const specialGlyphWordKind = abi_mod.specialGlyphWordKind;
    pub const specialGlyphWordLayerCount = abi_mod.specialGlyphWordLayerCount;
    pub const regularGlyphWordHBandCount = abi_mod.regularGlyphWordHBandCount;
    pub const regularGlyphWordVBandCount = abi_mod.regularGlyphWordVBandCount;
    pub const unpackBandCounts = abi_mod.unpackBandCounts;
};

/// Decoders for the immutable geometry/record bytes returned by
/// `atlas_upload.Planner`.
/// GPU callers normally use the shipped shader functions; this surface lets a
/// software renderer consume the exact same representation.
pub const geometry = struct {
    pub const CurveKind = curve_mod.CurveKind;
    pub const CurveSegment = curve_mod.CurveSegment;
    pub const GlyphBandEntry = band_texture_mod.GlyphBandEntry;

    pub const CURVE_SEGMENT_TEXELS = curve_texture_mod.SEGMENT_TEXELS;
    pub const PACKED_ANCHOR_CHUNK_EXTENT = curve_texture_mod.PACKED_ANCHOR_CHUNK_EXTENT;
    pub const DIRECT_ENCODING_KIND_BIAS = curve_texture_mod.DIRECT_ENCODING_KIND_BIAS;
    pub const decodePackedAnchor = curve_texture_mod.decodePackedAnchor;

    pub const autohint = struct {
        pub const header_floats = autohint_record_mod.header_floats;
        pub const BandEntry = autohint_record_mod.BandEntry;
        pub const DecodedRecord = autohint_record_mod.DecodedRecord;
        pub const DecodeError = autohint_record_mod.DecodeError;
        /// Validate one record and borrow its feature runs. The source float
        /// slice must remain alive and unchanged while the result is used.
        pub const decode = autohint_record_mod.decode;
    };
};

test {
    _ = records;
    _ = geometry;
}
