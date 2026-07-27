//! Generated-shader API gate. Kept separate from `public_renderer_api.zig` so
//! `zig build test-core` verifies the complete source-only API without needing
//! Slang or naga.

const std = @import("std");
const snail = @import("snail");
const generated = @import("snail_shaders");

test "generated shaders remain a separate opt-in module" {
    comptime {
        if (@hasDecl(snail, "shader")) @compileError("generated shaders must not pull tools into the core module");
        _ = generated.textSpv(.fragment);
        _ = generated.textWgsl(.fragment);
        _ = generated.textSampleFragGlsl330();
    }
}

test "public autohint GL artifacts require only baseline arithmetic" {
    inline for (.{
        generated.autohintGlsl330(.vertex),
        generated.autohintGlsl330(.fragment),
        generated.autohintSubpixelFragGlsl330(),
        generated.autohintGles300(.vertex),
        generated.autohintGles300(.fragment),
    }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "GL_EXT_shader_explicit_arithmetic_types") == null);
        try std.testing.expect(std.mem.indexOf(u8, src, "uint16_t") == null);
        try std.testing.expect(std.mem.indexOf(u8, src, "uint16BitsToFloat16") == null);
        try std.testing.expect(std.mem.indexOf(u8, src, "No extension available for") == null);
    }
}
