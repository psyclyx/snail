const std = @import("std");
const vec = @import("math/vec.zig");

const Mat4 = vec.Mat4;
const Vec2 = vec.Vec2;
const Transform2D = vec.Transform2D;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

pub const SubpixelOrder = @import("render/format/subpixel_order.zig").SubpixelOrder;

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

pub const DrawResolve = union(enum) {
    direct,
    linear: LinearResolve,
};

pub const TargetSurface = struct {
    pixel_width: f32,
    pixel_height: f32,
    encoding: TargetEncoding,

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

pub const DrawPass = struct {
    state: DrawState,
    resolve: DrawResolve = .direct,

    pub fn direct(state: DrawState) DrawPass {
        return .{ .state = state };
    }

    pub fn linear(state: DrawState, resolve: LinearResolve) DrawPass {
        return .{ .state = state, .resolve = .{ .linear = resolve } };
    }
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

/// Project the z = 0 plane of `mvp` to viewport pixel coordinates and
/// return the resulting world→pixel 2D affine. `viewport_w` / `viewport_h`
/// are the framebuffer dimensions the MVP renders into (snail uses
/// y-down screen space, so the returned `yy` for a typical ortho MVP is
/// positive).
///
/// Returns `null` for non-affine (perspective) MVPs or degenerate
/// (w ≈ 0) projections, in which case the caller has nothing meaningful
/// to snap against.
pub fn mvpToScenePixel(mvp: Mat4, viewport_w: f32, viewport_h: f32) ?Transform2D {
    const m = mvp.data;

    // Apply mvp to (0,0,0,1), (1,0,0,1), (0,1,0,1) — origin and basis
    // vectors of the z = 0 plane. Affine projection of the plane
    // requires constant w across the three; reject perspective.
    const o_clip = [3]f32{ m[12], m[13], m[15] };
    const x_clip = [3]f32{ m[0] + m[12], m[1] + m[13], m[3] + m[15] };
    const y_clip = [3]f32{ m[4] + m[12], m[5] + m[13], m[7] + m[15] };

    const eps_w: f32 = 1e-4;
    if (@abs(o_clip[2] - x_clip[2]) > eps_w or @abs(o_clip[2] - y_clip[2]) > eps_w) return null;
    if (@abs(o_clip[2]) < 1e-6) return null;

    const inv_w = 1.0 / o_clip[2];
    const half_w = viewport_w * 0.5;
    const half_h = viewport_h * 0.5;

    const o_x = (o_clip[0] * inv_w + 1.0) * half_w;
    const o_y = (1.0 - o_clip[1] * inv_w) * half_h;
    const x_x = (x_clip[0] * inv_w + 1.0) * half_w;
    const x_y = (1.0 - x_clip[1] * inv_w) * half_h;
    const y_x = (y_clip[0] * inv_w + 1.0) * half_w;
    const y_y = (1.0 - y_clip[1] * inv_w) * half_h;

    return .{
        .xx = x_x - o_x,
        .yx = x_y - o_y,
        .xy = y_x - o_x,
        .yy = y_y - o_y,
        .tx = o_x,
        .ty = o_y,
    };
}

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

test "pixel rect clips to target bounds" {
    try std.testing.expectEqual(PixelRect{ .x = 2, .y = 0, .w = 3, .h = 4 }, (PixelRect{ .x = 2, .y = -3, .w = 8, .h = 7 }).clipped(5, 4));
    try std.testing.expectEqual(PixelRect{}, (PixelRect{ .x = 9, .y = 1, .w = 2, .h = 2 }).clipped(5, 4));
}

test "mvpToScenePixel composes ortho + scene transform into world→pixel" {
    const projection = Mat4.ortho(0, 100, 50, 0, -1, 1);
    const scene = Mat4.multiply(
        Mat4.translate(10, -5, 0),
        Mat4.scaleUniform(0.5),
    );
    const mvp = Mat4.multiply(projection, scene);
    const t = mvpToScenePixel(mvp, 200, 100) orelse return error.TestExpectedTransform;

    // World (0,0) should map to (10*2 + 0*2, -5*2 + 0*2) = (20, -10) pixels.
    const origin = t.applyPoint(.{ .x = 0, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 20), origin.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -10), origin.y, 1e-4);

    // World x basis (1,0): pixel delta = (0.5 * 2, 0) = (1, 0).
    const basis_x = t.applyPoint(.{ .x = 1, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 21), basis_x.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -10), basis_x.y, 1e-4);
}

test "mvpToScenePixel returns null on perspective MVPs" {
    const persp = Mat4.perspective(std.math.pi * 0.5, 1.0, 0.1, 100);
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(persp, 100, 100));
}
