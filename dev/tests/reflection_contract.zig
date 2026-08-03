//! Guards that the committed shader binding contract — the
//! `snail-shaders-reflection` scope, backed by src/snail/shader/reflection.zig
//! — is consumable with NO shader toolchain. This test rides the `test-core`
//! suite, which runs without slangc or naga; if the reflection path ever
//! reacquires a shader-tool dependency, `test-core` fails to build here.

const std = @import("std");
const shaders = @import("snail_shaders");

test "reflection binding contract compiles without a shader toolchain" {
    const refl = shaders.reflection;
    // Referencing these forces full analysis of the committed reflection
    // module. That it builds under `test-core` is the proof; the assertions
    // just keep the references live and sane without hard-coding ABI numbers.
    try std.testing.expect(@sizeOf(refl.PushConstants) == refl.vulkan_push_constant_size);
    try std.testing.expect(refl.binding.curve_tex != refl.binding.band_tex);
    try std.testing.expect(shaders.uniform_parameter_buffer_size >= refl.vulkan_push_constant_size);
}
