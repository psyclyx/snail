//! Vulkan SPIR-V shader module for the reference demo renderer.
//!
//! Every family is compiled at build time from the native-Slang sources
//! (`src/snail/shader/slang/families/*.slang`) via `slangc` — the same
//! compile that produces the `snail-shaders` module's `spirv/*.spv`
//! artifacts, so the running pipeline can never drift from the source. See
//! build/slang_shaders.zig for the per-target flag sets and their reasons.

const std = @import("std");
const slang_shaders = @import("slang_shaders.zig");

pub fn createModule(b: *std.Build) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/render/vulkan/shaders.zig"),
    });

    // Fragment-only families share the native text vertex module.
    const native_text = slang_shaders.vulkanTextSpv(b);
    mod.addAnonymousImport("snail_text_native.vert.spv", .{ .root_source_file = native_text.vert });
    mod.addAnonymousImport("snail_text_native.frag.spv", .{ .root_source_file = native_text.frag });
    mod.addAnonymousImport("snail_colr_native.frag.spv", .{ .root_source_file = slang_shaders.vulkanFragmentSpv(b, "colr") });
    mod.addAnonymousImport("snail_path_native.frag.spv", .{ .root_source_file = slang_shaders.vulkanFragmentSpv(b, "path") });
    mod.addAnonymousImport("snail_tt_hinted_native.frag.spv", .{ .root_source_file = slang_shaders.vulkanFragmentSpv(b, "tt_hinted_text") });
    mod.addAnonymousImport("snail_autohint_native.vert.spv", .{ .root_source_file = slang_shaders.vulkanVertexSpv(b, "autohint") });
    mod.addAnonymousImport("snail_autohint_native.frag.spv", .{ .root_source_file = slang_shaders.vulkanFragmentSpv(b, "autohint") });
    mod.addAnonymousImport("snail_subpixel_native.frag.spv", .{ .root_source_file = slang_shaders.vulkanFragmentSpv(b, "text_subpixel") });
    return mod;
}
