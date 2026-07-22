//! Shared types and pure helpers used by both `gl/state.zig` (GL 3.3 +
//! 4.4) and `gles30/state.zig`.
//!
//! The two state files keep separate implementations because the
//! streaming models genuinely differ — GL 4.4 uses persistent-mapped
//! ring buffers, GL 3.3 uses orphan-and-stream, GLES3 uses plain
//! `glBufferSubData`. What's shared is the linear-resolve pre/post and
//! a few sRGB conversion helpers. Pulling them here keeps both
//! callsites byte-identical so a fix in one lands in both.

const std = @import("std");
const PixelRect = @import("render-state").PixelRect;

/// Saved framebuffer / viewport state captured at `beginLinearResolve`
/// and re-applied at `endLinearResolve`. Uses bare C types for the gl
/// fields so both the `GL/gl.h` and `GLES3/gl3.h` bindings can fill it
/// in without an adapter — `c_int` is the underlying type of
/// `gl.GLint` in both header families.
pub const LinearResolveRestore = struct {
    draw_fbo: c_int = 0,
    read_fbo: c_int = 0,
    viewport: [4]c_int = .{ 0, 0, 0, 0 },
    resolve_rect: PixelRect = .{},
    depth_test: bool = false,
    scissor_test: bool = false,
    blend: bool = false,
};

pub const LinearResolvePass = enum(c_int) {
    seed_intermediate = 0,
    encode_to_target = 1,
};

/// The 96-byte std140 uniform block of the native-Slang text-family
/// shaders (`snail.shader.generated`). Field-for-field identical to
/// the Vulkan `contract.zig:PushConstants`; the GL hosts upload it into a
/// UBO instead of setting loose uniforms.
pub const NativeTextPushBlock = extern struct {
    mvp: [16]f32,
    viewport: [2]f32,
    subpixel_order: i32,
    output_srgb: i32,
    layer_base: i32,
    coverage_exponent: f32,
    dither_scale: f32,
    mask_output: i32,
};

comptime {
    if (@sizeOf(NativeTextPushBlock) != 96) @compileError("NativeTextPushBlock must be 96 bytes");
}

/// The UBO binding point both native text uniform blocks are bound to.
pub const NATIVE_TEXT_UBO_BINDING: c_uint = 0;

/// sRGB transfer function — single channel.
pub fn srgbFloatToLinear(v: f32) f32 {
    const c = std.math.clamp(v, 0.0, 1.0);
    return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

/// Convert a premultiplied-sRGB clear color into the
/// premultiplied-linear value the resolve target wants.
pub fn linearPremultipliedBackdropColor(color_srgb: [4]f32) [4]f32 {
    const alpha = std.math.clamp(color_srgb[3], 0.0, 1.0);
    return .{
        srgbFloatToLinear(color_srgb[0]) * alpha,
        srgbFloatToLinear(color_srgb[1]) * alpha,
        srgbFloatToLinear(color_srgb[2]) * alpha,
        alpha,
    };
}

/// Convert a top-down rect's Y origin into GL's bottom-up Y origin at
/// the given viewport height.
pub fn glRectY(rect: PixelRect, viewport_height: u32) c_int {
    return @intCast(@as(i32, @intCast(viewport_height)) - rect.y - @as(i32, @intCast(rect.h)));
}
