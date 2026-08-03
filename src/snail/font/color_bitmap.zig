//! Backend-neutral color-bitmap glyph presentation.
//!
//! Embedded bitmap strikes (CBDT/CBLC, `sbix`, EBDT/EBLC) surface here as
//! *encoded* image bytes plus an em-space placement box. snail never decodes
//! the bytes: decoding is a host service (`ImageDecoder`) so the library links
//! no image codec. The decoded texels become a `snail.Image` that the atlas
//! samples through the ordinary image-paint path — a bitmap glyph is a placed
//! image, not a new coverage primitive.
//!
//! HarfBuzz's OT color API is the producer (see `font/harfbuzz_font.zig`);
//! these types carry nothing HarfBuzz-specific so a different front end could
//! populate them.

const std = @import("std");
const bezier = @import("../math/bezier.zig");
const image_mod = @import("../image.zig");

pub const Image = image_mod.Image;

/// Encoding of a `ColorBitmap`'s bytes. The host decoder dispatches on this to
/// pick a codec. Only formats HarfBuzz surfaces for embedded strikes appear
/// here; `sbix` may additionally carry `jpg`/`tiff`, added when needed.
pub const BitmapFormat = enum {
    /// PNG document, as emitted by CBDT format 17/18/19 and PNG `sbix`
    /// strikes. This is what emoji fonts overwhelmingly use.
    png,
};

/// An embedded bitmap strike for one glyph at one ppem.
///
/// `data` is owned encoded bytes; `bbox` is the strike's own placement in em
/// space (units-per-em normalized, y-up), taken from the glyph extents the
/// strike reports — never the fallback outline bounds. Placement uses this box
/// so a bitmap-only glyph (no outline) still lands correctly.
pub const ColorBitmap = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    format: BitmapFormat,
    bbox: bezier.BBox,

    pub fn deinit(self: *ColorBitmap) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

pub const DecodeError = error{ DecodeFailed, OutOfMemory };

/// Host service that turns encoded bitmap bytes into straight-alpha sRGBA
/// texels as a `snail.Image`. snail supplies the bytes and format; the host
/// supplies the codec and owns the returned image for at least as long as any
/// atlas snapshot that references it.
///
/// A decoder that cannot handle `format`, or hits malformed data, returns
/// `error.DecodeFailed`; the caller's presentation policy then decides whether
/// to fall back to the outline.
pub const ImageDecoder = struct {
    context: *anyopaque,
    decode: *const fn (
        context: *anyopaque,
        format: BitmapFormat,
        bytes: []const u8,
        allocator: std.mem.Allocator,
    ) DecodeError!Image,

    pub fn decodeImage(
        self: ImageDecoder,
        format: BitmapFormat,
        bytes: []const u8,
        allocator: std.mem.Allocator,
    ) DecodeError!Image {
        return self.decode(self.context, format, bytes, allocator);
    }
};
