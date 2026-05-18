const snail = @import("../../../root.zig");
const cpu_color = @import("color.zig");
const cpu_coverage = @import("coverage.zig");

const clamp01 = cpu_color.clamp01;
const interleavedGradientNoise = cpu_color.interleavedGradientNoise;
const linearColorToSrgb = cpu_color.linearColorToSrgb;
const linearToSrgb = cpu_color.linearToSrgb;
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
            return srgbToByte(linearToSrgb(value) + dither);
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

pub fn blendPremultipliedPixel(target: Target, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
    const off = row * target.stride + col * 4;
    const dst_r = target.readDstChannel(target.pixels[off + 0]);
    const dst_g = target.readDstChannel(target.pixels[off + 1]);
    const dst_b = target.readDstChannel(target.pixels[off + 2]);
    const dst_a = @as(f32, @floatFromInt(target.pixels[off + 3])) / 255.0;

    const target_src = target.srcPremultipliedForTarget(src);
    const src_a = clamp01(target_src[3]);
    const out_r = target_src[0] + dst_r * (1.0 - src_a);
    const out_g = target_src[1] + dst_g * (1.0 - src_a);
    const out_b = target_src[2] + dst_b * (1.0 - src_a);
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

pub fn blendSubpixelPremultipliedPixel(target: Target, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
    const off = row * target.stride + col * 4;
    const dst_r = target.readDstChannel(target.pixels[off + 0]);
    const dst_g = target.readDstChannel(target.pixels[off + 1]);
    const dst_b = target.readDstChannel(target.pixels[off + 2]);
    const dst_a = @as(f32, @floatFromInt(target.pixels[off + 3])) / 255.0;

    const out_r = src[0] + dst_r * (1.0 - clamp01(src_blend[0]));
    const out_g = src[1] + dst_g * (1.0 - clamp01(src_blend[1]));
    const out_b = src[2] + dst_b * (1.0 - clamp01(src_blend[2]));
    const src_a = clamp01(src[3]);
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

pub fn blendSubpixelPixel(target: Target, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
    const target_color = target.srcColorForSubpixelTarget(color);
    const src_blend = subpixelBlendCoverage(color, cov);
    blendSubpixelPremultipliedPixel(target, row, col, premultiplySubpixelCoverage(target_color, cov, alpha_cov), src_blend, false);
}
