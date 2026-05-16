const std = @import("std");
const vec = @import("math/vec.zig");

const Mat4 = vec.Mat4;
const Vec2 = vec.Vec2;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

pub const SubpixelOrder = @import("renderer/subpixel_order.zig").SubpixelOrder;

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

pub const ResolveRegion = union(enum) {
    full_target,
    pixel_rect: PixelRect,

    pub fn rect(self: ResolveRegion, width: u32, height: u32) PixelRect {
        return switch (self) {
            .full_target => PixelRect.full(width, height),
            .pixel_rect => |r| r.clipped(width, height),
        };
    }
};

pub const ResolveBackdrop = union(enum) {
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

pub const IntermediateFormat = enum(c_int) {
    rgba16f = 0,
    rgba32f = 1,
};

pub const DirectResolve = struct {};

pub const LinearResolve = struct {
    backdrop: ResolveBackdrop = .target,
    region: ResolveRegion = .full_target,
    intermediate_format: IntermediateFormat = .rgba16f,
};

pub const Resolve = union(enum) {
    direct: DirectResolve,
    linear: LinearResolve,

    pub fn isLinear(self: Resolve) bool {
        return switch (self) {
            .direct => false,
            .linear => true,
        };
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

pub const PixelGrid = struct {
    logical_size: [2]f32,
    pixel_size: [2]u32,

    pub fn init(logical_size: [2]f32, pixel_size: [2]u32) PixelGrid {
        return .{ .logical_size = logical_size, .pixel_size = pixel_size };
    }

    pub fn fromTarget(logical_size: [2]f32, target: ResolveTarget) PixelGrid {
        return .{
            .logical_size = logical_size,
            .pixel_size = .{
                @intFromFloat(@max(target.pixel_width, 0.0)),
                @intFromFloat(@max(target.pixel_height, 0.0)),
            },
        };
    }

    pub fn scale(self: PixelGrid) [2]f32 {
        return .{ self.axisScale(0), self.axisScale(1) };
    }

    pub fn snapX(self: PixelGrid, x: f32) f32 {
        return self.snapAxis(0, x);
    }

    pub fn snapY(self: PixelGrid, y: f32) f32 {
        return self.snapAxis(1, y);
    }

    pub fn snapPoint(self: PixelGrid, point: Vec2) Vec2 {
        return .{ .x = self.snapX(point.x), .y = self.snapY(point.y) };
    }

    pub fn snapRect(self: PixelGrid, rect: Rect) Rect {
        const min = self.snapPoint(.{ .x = rect.x, .y = rect.y });
        const max = self.snapPoint(.{ .x = rect.x + rect.w, .y = rect.y + rect.h });
        return .{ .x = min.x, .y = min.y, .w = @max(max.x - min.x, 0.0), .h = @max(max.y - min.y, 0.0) };
    }

    pub fn snapLengthX(self: PixelGrid, value: f32) f32 {
        return self.snapLengthAxis(0, value);
    }

    pub fn snapLengthY(self: PixelGrid, value: f32) f32 {
        return self.snapLengthAxis(1, value);
    }

    fn axisScale(self: PixelGrid, axis: usize) f32 {
        if (self.logical_size[axis] <= 0.0 or self.pixel_size[axis] == 0) return 1.0;
        return @as(f32, @floatFromInt(self.pixel_size[axis])) / self.logical_size[axis];
    }

    fn snapAxis(self: PixelGrid, axis: usize, value: f32) f32 {
        const s = self.axisScale(axis);
        return @round(value * s) / s;
    }

    fn snapLengthAxis(self: PixelGrid, axis: usize, value: f32) f32 {
        const s = self.axisScale(axis);
        return @max(@round(value * s), 1.0) / s;
    }
};

pub const ResolveTarget = struct {
    pixel_width: f32,
    pixel_height: f32,
    subpixel_order: SubpixelOrder = .none,
    fill_rule: FillRule = .non_zero,
    is_final_composite: bool = true,
    opaque_backdrop: bool = true,
    will_resample: bool = false,
    /// Explicit color encoding for this target. No renderer-global format
    /// state is consulted; each draw states the attachment encoding and the
    /// expected final pixel encoding.
    encoding: TargetEncoding,
    /// How Snail resolves into this target. `.direct` draws straight into the
    /// attachment. `.linear` resolves through a linear intermediate using an
    /// explicit backdrop and region contract.
    resolve: Resolve = .{ .direct = .{} },
    /// Optional, explicit transfer from analytically evaluated coverage to the
    /// coverage used for blending. This is a caller-controlled primitive for
    /// display tuning; renderers do not infer or remember it globally.
    coverage_transfer: CoverageTransfer = .identity,

    pub fn usesLinearResolve(self: ResolveTarget) bool {
        return self.resolve.isLinear();
    }

    pub fn supportsLinearResolve(self: ResolveTarget) bool {
        return self.encoding.attachment == .linear and self.encoding.stored_pixels == .srgb;
    }

    pub fn resolveRect(self: ResolveTarget) PixelRect {
        const width: u32 = @intFromFloat(@max(self.pixel_width, 0.0));
        const height: u32 = @intFromFloat(@max(self.pixel_height, 0.0));
        return switch (self.resolve) {
            .direct => PixelRect.full(width, height),
            .linear => |linear| linear.region.rect(width, height),
        };
    }
};

pub fn effectiveSubpixelOrder(target: ResolveTarget) SubpixelOrder {
    if (target.will_resample) return .none;
    if (!target.is_final_composite) return .none;
    if (!target.opaque_backdrop) return .none;
    return target.subpixel_order;
}

pub const TargetStamp = struct {
    pixel_size: [2]u32 = .{ 0, 0 },
    subpixel_order: SubpixelOrder = .none,
    encoding: TargetEncoding = .linear,
    resolve: Resolve = .{ .direct = .{} },
    mvp_class: MvpClass = .projective,

    pub const MvpClass = enum(u8) {
        identity,
        axis_aligned_2d,
        affine_2d,
        projective,
    };

    pub fn from(mvp: Mat4, target_value: ResolveTarget) TargetStamp {
        return .{
            .pixel_size = .{
                @intFromFloat(@max(target_value.pixel_width, 0.0)),
                @intFromFloat(@max(target_value.pixel_height, 0.0)),
            },
            .subpixel_order = effectiveSubpixelOrder(target_value),
            .encoding = target_value.encoding,
            .resolve = target_value.resolve,
            .mvp_class = classifyMvp(mvp),
        };
    }

    fn classifyMvp(mvp: Mat4) MvpClass {
        if (std.meta.eql(mvp, Mat4.identity)) return .identity;
        if (@abs(mvp.data[3]) > 1e-5 or @abs(mvp.data[7]) > 1e-5 or @abs(mvp.data[11]) > 1e-5) return .projective;
        if (@abs(mvp.data[15] - 1.0) > 1e-5) return .projective;
        if (@abs(mvp.data[1]) <= 1e-5 and @abs(mvp.data[4]) <= 1e-5) return .axis_aligned_2d;
        return .affine_2d;
    }
};

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
