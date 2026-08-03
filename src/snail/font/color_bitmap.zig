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
const vec = @import("../math/vec.zig");
const image_mod = @import("../image.zig");

pub const Image = image_mod.Image;
pub const BBox = bezier.BBox;
pub const Transform2D = vec.Transform2D;

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

/// UV transform that maps the strike's em-space placement rect (`bbox`, y-up)
/// onto its decoded image (rows top-down): `u = (x-min.x)/w`, `v = (max.y-y)/h`.
///
/// The y-flip is the whole point — it cancels the y-flip an outline glyph's
/// placement transform already carries (`placeRun` emits `yy = -scale`), so a
/// bitmap glyph recorded as an image-painted em-bbox rect places *exactly* like
/// an outline glyph and stays upright. Callers build the paint as
/// `ImagePaint{ .image = &decoded, .uv_transform = bitmap.imageUvTransform() }`.
pub fn imageUvTransform(bbox: BBox) Transform2D {
    const w = bbox.max.x - bbox.min.x;
    const h = bbox.max.y - bbox.min.y;
    return .{
        .xx = 1.0 / w,
        .xy = 0,
        .tx = -bbox.min.x / w,
        .yx = 0,
        .yy = -1.0 / h,
        .ty = bbox.max.y / h,
    };
}

test "imageUvTransform flips y and maps the bbox corners to image corners" {
    // A full-em strike: em top-left (0,1) -> image top-left (0,0).
    const t = imageUvTransform(.{ .min = vec.Vec2.new(0, 0), .max = vec.Vec2.new(1, 1) });
    const tl = t.applyPoint(vec.Vec2.new(0, 1));
    const br = t.applyPoint(vec.Vec2.new(1, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), tl.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), tl.y, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), br.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), br.y, 1e-6);

    // An offset/partial strike still maps its own corners to [0,1] uv.
    const o = imageUvTransform(.{ .min = vec.Vec2.new(0.25, 0.5), .max = vec.Vec2.new(0.75, 1.0) });
    const otl = o.applyPoint(vec.Vec2.new(0.25, 1.0));
    const obr = o.applyPoint(vec.Vec2.new(0.75, 0.5));
    try std.testing.expectApproxEqAbs(@as(f32, 0), otl.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), otl.y, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), obr.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), obr.y, 1e-6);
}

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
