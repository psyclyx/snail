//! Shared state used by the optional software renderer and the reference GPU
//! callers. This is deliberately not part of the `snail` compiler module:
//! applications with their own renderer can define their own target policy.

const std = @import("std");
const snail = @import("snail");

const Mat4 = snail.Mat4;

pub const SubpixelOrder = enum(i32) {
    none = 0,
    rgb = 1,
    bgr = 2,
    vrgb = 3,
    vbgr = 4,

    pub fn name(self: SubpixelOrder) []const u8 {
        return switch (self) {
            .none => "none",
            .rgb => "rgb",
            .bgr => "bgr",
            .vrgb => "vrgb",
            .vbgr => "vbgr",
        };
    }
};

pub const ColorEncoding = enum(c_int) {
    linear = 0,
    srgb = 1,
};

pub const PixelRect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: u32 = 0,
    h: u32 = 0,

    pub fn full(width: u32, height: u32) PixelRect {
        return .{ .x = 0, .y = 0, .w = width, .h = height };
    }

    pub fn clipped(self: PixelRect, width: u32, height: u32) PixelRect {
        const x0 = @max(@as(i64, self.x), 0);
        const y0 = @max(@as(i64, self.y), 0);
        const x1 = @min(@as(i64, self.x) + @as(i64, self.w), @as(i64, width));
        const y1 = @min(@as(i64, self.y) + @as(i64, self.h), @as(i64, height));
        if (x0 >= x1 or y0 >= y1) return .{};
        return .{
            .x = @intCast(x0),
            .y = @intCast(y0),
            .w = @intCast(x1 - x0),
            .h = @intCast(y1 - y0),
        };
    }
};

pub const LinearResolve = struct {
    backdrop: Backdrop = .target,
    region: Region = .full_target,
    intermediate_format: Format = .rgba16f,

    pub const Region = union(enum) {
        full_target,
        pixel_rect: PixelRect,

        pub fn rect(self: Region, width: u32, height: u32) PixelRect {
            return switch (self) {
                .full_target => PixelRect.full(width, height),
                .pixel_rect => |r| r.clipped(width, height),
            };
        }
    };

    pub const Backdrop = union(enum) {
        /// Decode the current target contents into the linear intermediate before
        /// drawing Snail content. This is the fully general, most expensive path.
        target,
        /// Seed the intermediate with an sRGB straight-alpha color.
        clear: [4]f32,
        /// Seed the intermediate with transparent black.
        transparent,
        /// Leave the intermediate contents unspecified. The caller promises Snail
        /// fully covers the resolve region.
        dont_care,
    };

    pub const Format = enum(c_int) {
        rgba16f = 0,
        rgba32f = 1,
    };
};

pub const TargetSurface = struct {
    pixel_width: f32,
    pixel_height: f32,
    encoding: TargetEncoding,
    /// Byte layout of the attachment. GPU backends pack in hardware regardless,
    /// but use it to set the per-format dither amplitude (0 for float, 1/1023
    /// for 10-bit, 1/255 for 8-bit). Defaults to rgba8.
    format: PixelFormat = .rgba8_unorm,

    pub fn pixelRect(self: TargetSurface) PixelRect {
        return PixelRect.full(
            @intFromFloat(@max(self.pixel_width, 0.0)),
            @intFromFloat(@max(self.pixel_height, 0.0)),
        );
    }

    pub fn supportsLinearResolve(self: TargetSurface) bool {
        return self.encoding.attachment == .linear and self.encoding.stored_pixels == .srgb;
    }
};

pub const RasterOptions = struct {
    subpixel_order: SubpixelOrder = .none,
    coverage_transfer: CoverageTransfer = .identity,
};

pub const DrawState = struct {
    mvp: Mat4,
    surface: TargetSurface,
    raster: RasterOptions = .{},
    /// Optional pixel-space clip restricting where this draw writes.
    /// `null` means full surface (the default). The rect is intersected
    /// with the surface bounds; if the intersection is empty the draw
    /// is a no-op. The rect is interpreted in the surface's framebuffer
    /// coordinate system (y-down, same as `PixelRect.full(w, h)`).
    ///
    /// Per-draw, not per-shape: callers wanting per-shape clipping
    /// split into multiple draws with different `scissor_rect`s. The
    /// caller's draw order (and therefore z-order) is preserved across
    /// the split.
    scissor_rect: ?PixelRect = null,
};

pub const TargetEncoding = struct {
    /// How the current attachment interprets color values written by the
    /// fragment stage. Use `.srgb` for GL/Vulkan sRGB formats and `.linear` for
    /// linear UNORM/float targets and CPU byte buffers.
    attachment: ColorEncoding,
    /// Encoding expected in the final stored pixels. On an sRGB attachment this
    /// should also be `.srgb`; the format encoder converts linear shader output.
    stored_pixels: ColorEncoding,

    pub const linear = TargetEncoding{ .attachment = .linear, .stored_pixels = .linear };
    pub const srgb = TargetEncoding{ .attachment = .srgb, .stored_pixels = .srgb };
    /// Single-pass compatibility for targets whose storage is linear but whose
    /// consumer expects sRGB bytes. Fixed-function blending happens in storage
    /// space; use an explicit linear intermediate plus final encode pass when
    /// overlapping translucent draws need fully linear-correct composition.
    pub const srgb_pixels_on_linear_attachment = TargetEncoding{ .attachment = .linear, .stored_pixels = .srgb };

    pub fn shaderOutputEncoding(self: TargetEncoding) ColorEncoding {
        return if (self.attachment == .srgb) .linear else self.stored_pixels;
    }

    pub fn shaderEncodesSrgb(self: TargetEncoding) bool {
        return self.shaderOutputEncoding() == .srgb;
    }

    pub fn cpuOutputSrgb(self: TargetEncoding) bool {
        return self.stored_pixels == .srgb;
    }
};

/// Byte layout of a render target. Orthogonal to `TargetEncoding` (which
/// decides sRGB-vs-linear semantics): this decides channel order, bit depth,
/// and packing. The CPU backend comptime-specializes its pixel pack over it;
/// GPU backends map it to a GL internalformat / VK format.
pub const PixelFormat = enum {
    /// 8-bit RGBA, R at byte 0. The default.
    rgba8_unorm,
    /// 8-bit BGRA, B at byte 0 — matches many platform swapchains (Vulkan,
    /// D3D). Same as `rgba8_unorm` but with R/B swapped in storage.
    bgra8_unorm,
    /// 10-bit R/G/B + 2-bit A packed little-endian into one u32.
    rgb10a2_unorm,
    /// 16-bit half-float RGBA (8 bytes). Stores linear values directly — no
    /// sRGB encode, no dither.
    rgba16f,
    /// Single 8-bit channel carrying painted alpha (coverage × paint.alpha).
    /// `r8_unorm` and `a8_unorm` are the same mask, differing only in which
    /// channel slot the API exposes; both elide all RGB paint/blend work.
    r8_unorm,
    a8_unorm,

    pub fn bytesPerPixel(fmt: PixelFormat) u32 {
        return switch (fmt) {
            .rgba8_unorm, .bgra8_unorm, .rgb10a2_unorm => 4,
            .rgba16f => 8,
            .r8_unorm, .a8_unorm => 1,
        };
    }

    /// Whether the format stores color (RGB). False for the single-channel
    /// masks, whose pipeline elides RGB paint sampling and RGB blend.
    pub fn hasColor(fmt: PixelFormat) bool {
        return fmt != .r8_unorm and fmt != .a8_unorm;
    }

    /// Float targets store linear values directly (no sRGB encode, no dither).
    pub fn isFloat(fmt: PixelFormat) bool {
        return fmt == .rgba16f;
    }

    /// Dither amplitude that suppresses banding for this format's bit depth,
    /// in normalized units: 1/255 for 8-bit, 1/1023 for 10-bit RGB, 0 for
    /// float (no quantization). Callers scale their noise by this before pack.
    pub fn ditherAmplitude(fmt: PixelFormat) f32 {
        return switch (fmt) {
            .rgba8_unorm, .bgra8_unorm, .r8_unorm, .a8_unorm => 1.0 / 255.0,
            .rgb10a2_unorm => 1.0 / 1023.0,
            .rgba16f => 0.0,
        };
    }
};

pub const CoverageTransfer = struct {
    /// Exponent applied to analytic coverage after edge evaluation. `1.0` is
    /// identity; values below `1.0` increase edge coverage and values above
    /// `1.0` reduce it.
    exponent: f32 = 1.0,

    pub const identity = CoverageTransfer{};

    pub fn power(exponent: f32) CoverageTransfer {
        return .{ .exponent = exponent };
    }

    pub fn shaderExponent(self: CoverageTransfer) f32 {
        if (!std.math.isFinite(self.exponent)) return 1.0;
        return @max(self.exponent, 1.0 / 65536.0);
    }

    pub fn apply(self: CoverageTransfer, coverage: f32) f32 {
        const cov = std.math.clamp(coverage, 0.0, 1.0);
        const exponent = self.shaderExponent();
        if (@abs(exponent - 1.0) <= 1.0e-6) return cov;
        return std.math.pow(f32, cov, exponent);
    }
};

pub fn resolveRect(surface: TargetSurface, resolve: LinearResolve) PixelRect {
    const width: u32 = @intFromFloat(@max(surface.pixel_width, 0.0));
    const height: u32 = @intFromFloat(@max(surface.pixel_height, 0.0));
    return resolve.region.rect(width, height);
}

test "pixel rect clips to target bounds" {
    try std.testing.expectEqual(PixelRect{ .x = 2, .y = 0, .w = 3, .h = 4 }, (PixelRect{ .x = 2, .y = -3, .w = 8, .h = 7 }).clipped(5, 4));
    try std.testing.expectEqual(PixelRect{}, (PixelRect{ .x = 9, .y = 1, .w = 2, .h = 2 }).clipped(5, 4));
}
