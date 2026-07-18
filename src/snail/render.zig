//! Public contract for caller-owned renderers.
//!
//! Snail prepares atlas data and draw records, but callers own GPU objects,
//! shader entry points, command submission, and presentation.  This namespace
//! exposes the byte layouts and backend-neutral policies needed to consume
//! those records without reaching into Snail's source-file structure.

/// Packed draw-record layout and symbolic decoders.
pub const abi = @import("format/abi.zig");
pub const vertex = @import("format/vertex.zig");
pub const draw_records = @import("picture/draw_records.zig");

/// Atlas texture formats consumed by the coverage algorithms.
pub const curve_texture = @import("format/curve_texture.zig");
pub const band_texture = @import("format/band_texture.zig");
pub const text_hint = @import("format/text_hint.zig");
pub const autohint_record = @import("format/autohint_record.zig");
pub const texture_layers = @import("format/texture_layers.zig");

/// Layer-info paint records and image-view patching.
pub const paint_records = @import("atlas/paint_records.zig");
pub const upload = @import("format/upload_common.zig");

/// Backend-neutral helpers which renderer implementations may reuse.
pub const cache = @import("render/backend/cache.zig");
pub const range_allocator = @import("render/backend/range_allocator.zig");
pub const RangeAllocator = range_allocator.RangeAllocator;
pub const Range = range_allocator.Range;
pub const subpixel = @import("render/backend/subpixel_policy.zig");

/// Analytic curve representation used by the CPU coverage implementation.
pub const curve = @import("math/bezier.zig");

test {
    _ = abi;
    _ = vertex;
    _ = draw_records;
    _ = curve_texture;
    _ = band_texture;
    _ = text_hint;
    _ = autohint_record;
    _ = texture_layers;
    _ = paint_records;
    _ = upload;
    _ = cache;
    _ = range_allocator;
    _ = RangeAllocator;
    _ = Range;
    _ = subpixel;
    _ = curve;
}
