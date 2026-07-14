const std = @import("std");
const snail = @import("snail_core");
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
const srgbFloatToLinear = cpu_color.srgbFloatToLinear;
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

    /// Float form of `writeChannel`'s encode: the normalized [0,1] value a
    /// unorm channel would quantize (sRGB-encoded or linear, + dither), before
    /// the bit-depth round. Used for >8-bit unorm formats; the 8-bit path
    /// keeps `writeChannel` verbatim so RGBA8 stays byte-exact.
    inline fn encodeChannelF(self: Target, value: f32, dither: f32) f32 {
        if (self.storageSpaceSrgbBlend()) return clamp01(value + dither);
        if (self.target_encoding.cpuOutputSrgb()) return clamp01(linearToSrgbApprox(value) + dither);
        return clamp01(value + dither);
    }

    /// Float form of `readDstChannel` for >8-bit formats: a normalized stored
    /// value → storage-space (linear for sRGB targets, raw otherwise).
    inline fn decodeStored(self: Target, v: f32) f32 {
        if (self.storageSpaceSrgbBlend()) return v;
        return if (self.target_encoding.cpuOutputSrgb()) srgbFloatToLinear(v) else v;
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

const pixel_pack = @import("pixel_pack.zig");
const PixelFormat = snail.PixelFormat;

/// Byte offset of pixel (row, col) for `fmt`.
inline fn pixelOffset(comptime fmt: PixelFormat, target: Target, row: u32, col: u32) usize {
    return @as(usize, row) * target.stride + @as(usize, col) * fmt.bytesPerPixel();
}

/// Read the destination pixel back into storage-space RGBA for blending.
/// Mask formats return `{0,0,0, alpha}` (their RGB is never read).
inline fn readStorage(comptime fmt: PixelFormat, target: Target, off: usize) [4]f32 {
    const p = target.pixels;
    return switch (fmt) {
        .rgba8_unorm => .{ target.readDstChannel(p[off + 0]), target.readDstChannel(p[off + 1]), target.readDstChannel(p[off + 2]), @as(f32, @floatFromInt(p[off + 3])) / 255.0 },
        .bgra8_unorm => .{ target.readDstChannel(p[off + 2]), target.readDstChannel(p[off + 1]), target.readDstChannel(p[off + 0]), @as(f32, @floatFromInt(p[off + 3])) / 255.0 },
        .r8_unorm, .a8_unorm => .{ 0, 0, 0, @as(f32, @floatFromInt(p[off + 0])) / 255.0 },
        .rgb10a2_unorm => blk: {
            const n = pixel_pack.unpack(.rgb10a2_unorm, p[off..][0..4]);
            break :blk .{ target.decodeStored(n[0]), target.decodeStored(n[1]), target.decodeStored(n[2]), n[3] };
        },
        // Float targets store linear directly — no decode.
        .rgba16f => pixel_pack.unpack(.rgba16f, p[off..][0..8]),
    };
}

/// Write storage-space RGBA to the destination pixel for `fmt`. `noise` is the
/// raw dither value in [0,1); `dither` gates it. Alpha is never sRGB-encoded.
inline fn writePixel(comptime fmt: PixelFormat, target: Target, off: usize, storage: [4]f32, noise: f32, dither: bool) void {
    const p = target.pixels;
    const d: f32 = if (dither) (noise - 0.5) * clamp01(storage[3]) * fmt.ditherAmplitude() else 0.0;
    switch (fmt) {
        .rgba8_unorm => {
            p[off + 0] = target.writeChannel(storage[0], d);
            p[off + 1] = target.writeChannel(storage[1], d);
            p[off + 2] = target.writeChannel(storage[2], d);
            p[off + 3] = srgbToByte(clamp01(storage[3]));
        },
        .bgra8_unorm => {
            p[off + 0] = target.writeChannel(storage[2], d);
            p[off + 1] = target.writeChannel(storage[1], d);
            p[off + 2] = target.writeChannel(storage[0], d);
            p[off + 3] = srgbToByte(clamp01(storage[3]));
        },
        .r8_unorm, .a8_unorm => {
            p[off + 0] = srgbToByte(clamp01(storage[3]) + d);
        },
        .rgb10a2_unorm => {
            const bytes = pixel_pack.pack(.rgb10a2_unorm, .{
                target.encodeChannelF(storage[0], d),
                target.encodeChannelF(storage[1], d),
                target.encodeChannelF(storage[2], d),
                clamp01(storage[3]),
            });
            @memcpy(p[off..][0..4], &bytes);
        },
        .rgba16f => {
            const bytes = pixel_pack.pack(.rgba16f, storage);
            @memcpy(p[off..][0..8], &bytes);
        },
    }
}

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
pub inline fn opaqueBytesForTarget(comptime fmt: PixelFormat, target: Target, color: [3]f32) [fmt.bytesPerPixel()]u8 {
    const target_src = target.srcPremultipliedForTarget(.{ color[0], color[1], color[2], 1.0 });
    var buf: [fmt.bytesPerPixel()]u8 = undefined;
    var t = target;
    t.pixels = &buf;
    writePixel(fmt, t, 0, .{ target_src[0], target_src[1], target_src[2], 1.0 }, 0.0, false);
    return buf;
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

pub inline fn blendPremultipliedPixel(comptime fmt: PixelFormat, target: Target, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
    const off = pixelOffset(fmt, target, row, col);
    const target_src = target.srcPremultipliedForTarget(src);
    const src_a = clamp01(target_src[3]);
    const noise = if (apply_dither) interleavedGradientNoise(target.ditherRow(row), col) else 0.0;

    // Fully-opaque src: dst contribution is exactly zero (× (1 - src_a) == 0),
    // so the dst read and decode are pointless. Hits solid-color interiors.
    if (src_a >= 1.0) {
        writePixel(fmt, target, off, .{ target_src[0], target_src[1], target_src[2], 1.0 }, noise, apply_dither);
        return;
    }

    const dst = readStorage(fmt, target, off);
    var out: [4]f32 = undefined;
    if (comptime fmt.hasColor()) {
        // 4-wide `out = target_src + dst * (1 - src_a)` (target_src[3] == src_a,
        // so the alpha lane is the standard composite).
        const V = @Vector(4, f32);
        out = @as(V, target_src) + @as(V, dst) * @as(V, @splat(1.0 - src_a));
    } else {
        // Mask: only alpha; RGB paint/blend is elided for this format.
        out = .{ 0, 0, 0, target_src[3] + dst[3] * (1.0 - src_a) };
    }
    writePixel(fmt, target, off, out, noise, apply_dither);
}

pub inline fn blendSubpixelPremultipliedPixel(comptime fmt: PixelFormat, target: Target, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
    const off = pixelOffset(fmt, target, row, col);
    const src_a = clamp01(src[3]);
    const noise = if (apply_dither) interleavedGradientNoise(target.ditherRow(row), col) else 0.0;

    // Per-channel fully-opaque src: every dst lane is annihilated.
    if (src_a >= 1.0 and src_blend[0] >= 1.0 and src_blend[1] >= 1.0 and src_blend[2] >= 1.0) {
        writePixel(fmt, target, off, .{ src[0], src[1], src[2], 1.0 }, noise, apply_dither);
        return;
    }

    const dst = readStorage(fmt, target, off);
    const out = [4]f32{
        src[0] + dst[0] * (1.0 - clamp01(src_blend[0])),
        src[1] + dst[1] * (1.0 - clamp01(src_blend[1])),
        src[2] + dst[2] * (1.0 - clamp01(src_blend[2])),
        src_a + dst[3] * (1.0 - src_a),
    };
    writePixel(fmt, target, off, out, noise, apply_dither);
}

pub inline fn blendSubpixelPixel(comptime fmt: PixelFormat, target: Target, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
    const target_color = target.srcColorForSubpixelTarget(color);
    const src_blend = subpixelBlendCoverage(color, cov);
    blendSubpixelPremultipliedPixel(fmt, target, row, col, premultiplySubpixelCoverage(target_color, cov, alpha_cov), src_blend, false);
}

// ── gamma probes ───────────────────────────────────────────────────────────
//
// Gamma correctness is a full-coverage property, so these test the blend at a
// single known pixel with an analytic expected value — no AA, no cross-backend
// tolerance. The blend math here is *identical* to what an AA edge runs
// (`src·coverage over dst` vs `src·alpha over dst`), so pinning it at alpha=0.5
// gives confidence about edge gamma without comparing untestable AA edges.
//
// The signature regression: 50%-white over black. Blended in **linear light**
// → linear 0.5 → sRGB **188**. Blended in **gamma space** (the bug) → **128**.

const testing = std.testing;

fn blendProbe(encoding: snail.TargetEncoding, resolve: ResolveMode, bg: [4]u8, src: [4]f32) [4]u8 {
    var px = bg;
    const target = Target{
        .pixels = &px,
        .stride = 4,
        .height = 1,
        .target_encoding = encoding,
        .target_resolve = resolve,
    };
    blendPremultipliedPixel(.rgba8_unorm, target, 0, 0, src, false);
    return px;
}

test "format: bgra8 stores the same blend as rgba8 with R/B swapped" {
    var rgba = [4]u8{ 0, 0, 0, 255 };
    var bgra = [4]u8{ 0, 0, 0, 255 };
    const t_rgba = Target{ .pixels = &rgba, .stride = 4, .height = 1, .target_encoding = .srgb, .target_resolve = .{ .direct = {} } };
    const t_bgra = Target{ .pixels = &bgra, .stride = 4, .height = 1, .target_encoding = .srgb, .target_resolve = .{ .direct = {} } };
    // Opaque orange-ish (distinct R/B) over black.
    const src = [4]f32{ 0.6, 0.3, 0.1, 1.0 };
    blendPremultipliedPixel(.rgba8_unorm, t_rgba, 0, 0, src, false);
    blendPremultipliedPixel(.bgra8_unorm, t_bgra, 0, 0, src, false);
    try testing.expectEqual(rgba[0], bgra[2]); // R
    try testing.expectEqual(rgba[1], bgra[1]); // G
    try testing.expectEqual(rgba[2], bgra[0]); // B
    try testing.expectEqual(rgba[3], bgra[3]); // A
    try testing.expect(rgba[0] != rgba[2]); // genuinely distinct R vs B
}

test "format: a8/r8 mask stores painted alpha, elides RGB" {
    inline for (.{ PixelFormat.r8_unorm, PixelFormat.a8_unorm }) |fmt| {
        var px = [1]u8{0};
        const t = Target{ .pixels = &px, .stride = 1, .height = 1, .target_encoding = .linear, .target_resolve = .{ .direct = {} } };
        // 50% coverage of an opaque color over empty (alpha 0) dst.
        blendPremultipliedPixel(fmt, t, 0, 0, .{ 0.6, 0.3, 0.1, 0.5 }, false);
        try testing.expectApproxEqAbs(@as(f32, 128), @as(f32, @floatFromInt(px[0])), 1.0); // alpha 0.5 → 128
    }
}

test "gamma: 50% white over black blends in linear light on an sRGB target" {
    // src = white premultiplied by 0.5 coverage; bg = opaque black.
    const out = blendProbe(.srgb, .{ .direct = {} }, .{ 0, 0, 0, 255 }, .{ 0.5, 0.5, 0.5, 0.5 });
    // Linear-correct → 188. A gamma-space regression lands near 128.
    try testing.expectApproxEqAbs(@as(f32, 188), @as(f32, @floatFromInt(out[0])), 1.0);
    try testing.expectEqual(@as(u8, 255), out[3]);
}

test "gamma: linear target stores the linear 0.5 result unencoded (128)" {
    // On a fully-linear target the same blend stores linear 0.5 = 128; that is
    // correct for linear storage (no sRGB encode). Pins that we don't
    // accidentally sRGB-encode a linear target.
    const out = blendProbe(.linear, .{ .direct = {} }, .{ 0, 0, 0, 255 }, .{ 0.5, 0.5, 0.5, 0.5 });
    try testing.expectApproxEqAbs(@as(f32, 128), @as(f32, @floatFromInt(out[0])), 1.0);
}

test "gamma: opaque src writes its exact encoded color (encode probe)" {
    // Fully-opaque mid-gray (linear 0.5) over anything → sRGB 188 on an sRGB
    // target, 128 on a linear target. Catches a missing/double encode.
    const srgb_out = blendProbe(.srgb, .{ .direct = {} }, .{ 9, 9, 9, 255 }, .{ 0.5, 0.5, 0.5, 1.0 });
    try testing.expectApproxEqAbs(@as(f32, 188), @as(f32, @floatFromInt(srgb_out[0])), 1.0);
    const linear_out = blendProbe(.linear, .{ .direct = {} }, .{ 9, 9, 9, 255 }, .{ 0.5, 0.5, 0.5, 1.0 });
    try testing.expectApproxEqAbs(@as(f32, 128), @as(f32, @floatFromInt(linear_out[0])), 1.0);
}
