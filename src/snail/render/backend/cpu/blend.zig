const snail = @import("../../../root.zig");
const cpu_color = @import("color.zig");
const cpu_coverage = @import("coverage.zig");

test {
    _ = @import("pixel_pack.zig");
}

const clamp01 = cpu_color.clamp01;
const interleavedGradientNoise = cpu_color.interleavedGradientNoise;
const linearColorToSrgb = cpu_color.linearColorToSrgb;
const linearToSrgb = cpu_color.linearToSrgb;
const linearToSrgbApprox = cpu_color.linearToSrgbApprox;
const linearToSrgbByte = cpu_color.linearToSrgbByte;
const srgbColorToLinear = cpu_color.srgbColorToLinear;
const srgbToByte = cpu_color.srgbToByte;
const srgbToLinear = cpu_color.srgbToLinear;
const premultiplySubpixelCoverage = cpu_coverage.premultiplySubpixelCoverage;
const subpixelBlendCoverage = cpu_coverage.subpixelBlendCoverage;

pub const ResolveMode = union(enum) {
    direct: void,
    linear: snail.LinearResolve,
};

pub const Target = struct {
    pixels: [*]u8,
    stride: u32,
    height: u32,
    target_encoding: snail.TargetEncoding,
    target_resolve: ResolveMode,

    inline fn readDstChannel(self: Target, byte: u8) f32 {
        if (self.storageSpaceSrgbBlend()) {
            return @as(f32, @floatFromInt(byte)) / 255.0;
        }
        return if (self.target_encoding.cpuOutputSrgb())
            srgbToLinear(byte)
        else
            @as(f32, @floatFromInt(byte)) / 255.0;
    }

    inline fn writeChannel(self: Target, value: f32, dither: f32) u8 {
        if (self.storageSpaceSrgbBlend()) {
            return srgbToByte(value + dither);
        }
        if (self.target_encoding.cpuOutputSrgb()) {
            if (dither == 0.0) return linearToSrgbByte(value);
            // Use the LUT-approximated sRGB float to avoid `pow` per channel.
            // The bucket error is ~3-4 orders below the dither amplitude, so
            // the rounded byte still matches the formula within ≤1 LSB.
            return srgbToByte(linearToSrgbApprox(value) + dither);
        }
        return srgbToByte(value + dither);
    }

    inline fn storageSpaceSrgbBlend(self: Target) bool {
        return switch (self.target_resolve) {
            .direct => self.target_encoding.attachment == .linear and self.target_encoding.stored_pixels == .srgb,
            .linear => false,
        };
    }

    inline fn srcPremultipliedForTarget(self: Target, src: [4]f32) [4]f32 {
        if (!self.storageSpaceSrgbBlend()) return src;
        if (src[3] <= 0.0) return .{ 0, 0, 0, 0 };
        const inv_a = 1.0 / src[3];
        return .{
            linearToSrgb(@max(src[0] * inv_a, 0.0)) * src[3],
            linearToSrgb(@max(src[1] * inv_a, 0.0)) * src[3],
            linearToSrgb(@max(src[2] * inv_a, 0.0)) * src[3],
            src[3],
        };
    }

    inline fn srcColorForSubpixelTarget(self: Target, color: [4]f32) [4]f32 {
        if (!self.storageSpaceSrgbBlend()) return color;
        return linearColorToSrgb(color);
    }

    inline fn ditherRow(self: Target, row: u32) u32 {
        // Match shader dither, which keys noise from bottom-origin gl_FragCoord.
        return if (row < self.height) self.height - 1 - row else row;
    }
};

/// Precompute the target bytes for an opaque, alpha-premultiplied solid
/// source (i.e. `(color[0..3], 1.0)` in target-color-space). The bytes
/// match exactly what `blendPremultipliedPixel` would write for the
/// `src_a >= 1.0` branch — but computed once instead of per pixel so
/// the caller can `@memset` an entire row.
///
/// `color` is in linear space (the same space the rasterizer's
/// per-pixel path uses just before `blendPremultipliedPixel`). Dither
/// is intentionally not supported here: dithered paints aren't solid
/// (the paint sampler returns `apply_dither = true` only for
/// gradients/images), so the fast path skips them upstream.
pub inline fn opaqueLinearBytesForTarget(target: Target, color: [3]f32) [4]u8 {
    const target_src = target.srcPremultipliedForTarget(.{ color[0], color[1], color[2], 1.0 });
    return .{
        target.writeChannel(target_src[0], 0.0),
        target.writeChannel(target_src[1], 0.0),
        target.writeChannel(target_src[2], 0.0),
        255,
    };
}

pub fn colorBytesForEncoding(encoding: snail.TargetEncoding, color_srgb: [4]f32) [4]u8 {
    const alpha = clamp01(color_srgb[3]);
    const linear = srgbColorToLinear(color_srgb);
    const premul = [3]f32{
        linear[0] * alpha,
        linear[1] * alpha,
        linear[2] * alpha,
    };
    return switch (encoding.stored_pixels) {
        .srgb => .{
            linearToSrgbByte(premul[0]),
            linearToSrgbByte(premul[1]),
            linearToSrgbByte(premul[2]),
            srgbToByte(alpha),
        },
        .linear => .{
            srgbToByte(premul[0]),
            srgbToByte(premul[1]),
            srgbToByte(premul[2]),
            srgbToByte(alpha),
        },
    };
}

pub inline fn blendPremultipliedPixel(target: Target, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
    const off = row * target.stride + col * 4;
    const target_src = target.srcPremultipliedForTarget(src);
    const src_a = clamp01(target_src[3]);

    // Fully-opaque src: dst contribution is exactly zero (multiplied by 1 -
    // src_a == 0), so the dst read and sRGB-decode would be discarded. Bit-
    // identical to the slow path; hits the dense interior of solid-color text.
    if (src_a >= 1.0) {
        const dither = if (apply_dither)
            (interleavedGradientNoise(target.ditherRow(row), col) - 0.5) * (1.0 / 255.0)
        else
            0.0;
        target.pixels[off + 0] = target.writeChannel(target_src[0], dither);
        target.pixels[off + 1] = target.writeChannel(target_src[1], dither);
        target.pixels[off + 2] = target.writeChannel(target_src[2], dither);
        target.pixels[off + 3] = 255;
        return;
    }

    const dst_r = target.readDstChannel(target.pixels[off + 0]);
    const dst_g = target.readDstChannel(target.pixels[off + 1]);
    const dst_b = target.readDstChannel(target.pixels[off + 2]);
    const dst_a = @as(f32, @floatFromInt(target.pixels[off + 3])) / 255.0;

    // 4-wide blend: `out = target_src + dst * (1 - src_a)` fuses to one vmadd.
    // target_src[3] == src_a (alpha preserved through srcPremultipliedForTarget),
    // so `target_src[3] + dst_a * (1 - src_a) == src_a + dst_a * (1 - src_a)`,
    // which is exactly the alpha composite formula.
    const V = @Vector(4, f32);
    const src_v: V = target_src;
    const dst_v: V = .{ dst_r, dst_g, dst_b, dst_a };
    const inv_alpha_v: V = @splat(1.0 - src_a);
    const out_v = src_v + dst_v * inv_alpha_v;

    const dither = if (apply_dither)
        (interleavedGradientNoise(target.ditherRow(row), col) - 0.5) * (clamp01(out_v[3]) / 255.0)
    else
        0.0;
    target.pixels[off + 0] = target.writeChannel(out_v[0], dither);
    target.pixels[off + 1] = target.writeChannel(out_v[1], dither);
    target.pixels[off + 2] = target.writeChannel(out_v[2], dither);
    target.pixels[off + 3] = srgbToByte(out_v[3]);
}

pub inline fn blendSubpixelPremultipliedPixel(target: Target, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
    const off = row * target.stride + col * 4;
    const src_a = clamp01(src[3]);

    // Per-channel fully-opaque src: each dst lane is annihilated by
    // `1 - src_blend[i] == 0`, and the alpha lane by `1 - src_a == 0`.
    // Bit-exact with the slow path, common in solid-color text interiors.
    if (src_a >= 1.0 and src_blend[0] >= 1.0 and src_blend[1] >= 1.0 and src_blend[2] >= 1.0) {
        const dither = if (apply_dither)
            (interleavedGradientNoise(target.ditherRow(row), col) - 0.5) * (1.0 / 255.0)
        else
            0.0;
        target.pixels[off + 0] = target.writeChannel(src[0], dither);
        target.pixels[off + 1] = target.writeChannel(src[1], dither);
        target.pixels[off + 2] = target.writeChannel(src[2], dither);
        target.pixels[off + 3] = 255;
        return;
    }

    const dst_r = target.readDstChannel(target.pixels[off + 0]);
    const dst_g = target.readDstChannel(target.pixels[off + 1]);
    const dst_b = target.readDstChannel(target.pixels[off + 2]);
    const dst_a = @as(f32, @floatFromInt(target.pixels[off + 3])) / 255.0;

    const out_r = src[0] + dst_r * (1.0 - clamp01(src_blend[0]));
    const out_g = src[1] + dst_g * (1.0 - clamp01(src_blend[1]));
    const out_b = src[2] + dst_b * (1.0 - clamp01(src_blend[2]));
    const out_a = src_a + dst_a * (1.0 - src_a);

    const dither = if (apply_dither)
        (interleavedGradientNoise(target.ditherRow(row), col) - 0.5) * (clamp01(out_a) / 255.0)
    else
        0.0;
    target.pixels[off + 0] = target.writeChannel(out_r, dither);
    target.pixels[off + 1] = target.writeChannel(out_g, dither);
    target.pixels[off + 2] = target.writeChannel(out_b, dither);
    target.pixels[off + 3] = srgbToByte(out_a);
}

pub inline fn blendSubpixelPixel(target: Target, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
    const target_color = target.srcColorForSubpixelTarget(color);
    const src_blend = subpixelBlendCoverage(color, cov);
    blendSubpixelPremultipliedPixel(target, row, col, premultiplySubpixelCoverage(target_color, cov, alpha_cov), src_blend, false);
}
