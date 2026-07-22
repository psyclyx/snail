//! Native-Slang shader toolchain (stage A: the regular-text family).
//!
//! Single source: `src/snail/shader/slang/` — proper Slang modules
//! (`module`/`import`), entry points declared with `[shader(...)]` in
//! `families/text.slang`. From that one family file every GPU target is
//! generated:
//!
//!   target      command                                              output
//!   ─────────   ──────────────────────────────────────────────────   ─────────────────────────────
//!   Vulkan      slangc -DSNAIL_TARGET_VULKAN -target spirv           generated/spirv/text.*.spv
//!               -profile spirv_1_3 -default-image-format-unknown     (also compiled directly by the
//!                                                                    demo Vulkan build, see below)
//!   WGSL        slangc -DSNAIL_TARGET_WGSL -target wgsl              generated/wgsl/text.*.wgsl
//!   GLSL 330    slangc -DSNAIL_TARGET_GL -target spirv               generated/glsl330/text.*.glsl
//!               -profile spirv_1_3, then
//!               naga --keep-coordinate-space --profile core330
//!   GLES 300    same SPIR-V leg, naga --profile es300                generated/gles300/text.*.glsl
//!
//! Flag notes (the traps, empirically verified against v2026.5.2):
//!
//!  - Matrix layout: for *native* Slang the DEFAULT (row-major logical)
//!    layout is correct. `mul(mvp, v)` emits `RowMajor` + MatrixStride 16 +
//!    `OpVectorTimesMatrix(v, M)`, which reads the CPU's column-major GLSL
//!    bytes with GLSL `M * v` semantics. This is the OPPOSITE of the
//!    GLSL-ingestion finding recorded in build/vulkan_shaders.zig
//!    (`-matrix-layout-row-major` was load-bearing there); passing
//!    `-matrix-layout-column-major` here silently transposes every matrix
//!    (blank render). No matrix flag is passed: the default is the correct
//!    convention and this comment is the record of why.
//!  - `-default-image-format-unknown`: without it slangc guesses an image
//!    format from `Texture2DArray<uint2>` (Rg32ui) and drags in the
//!    StorageImageExtendedFormats capability — a device feature — for a
//!    texture we only ever `Load`.
//!  - `-profile spirv_1_3`: demo devices are Vulkan 1.1 (same reason as the
//!    ingestion path); also keeps naga's SPIR-V front end happy (it warns on
//!    SPIR-V 1.0 modules).
//!  - slangc's own `-target glsl` output is Vulkan-flavor GLSL only
//!    (`texture2DArray` + GL_EXT_samplerless_texture_functions,
//!    `layout(binding=N)`, `#version 450+`) and cannot be consumed by
//!    OpenGL 3.3 / GLES 3.0 contexts, so the GL family goes SPIR-V → naga
//!    (already in the toolchain for the WGSL catalog).
//!    `--keep-coordinate-space` is load-bearing: naga otherwise injects the
//!    Vulkan→GL clip-space conversion (`gl_Position.yz = vec2(-y, z*2-w)`)
//!    and the render is vertically flipped vs. the GL contract.
//!  - `-target wgsl` works DIRECTLY for native Slang (entry names are the
//!    Slang function names, e.g. `vertexMain`): the GLSL-ingestion bugs
//!    (miscompiled texelFetch, renumbered stage IO) do not apply, and the
//!    output validates with naga as-is. No spirv-opt / naga pipeline needed.
//!  - `SV_VertexID` is avoided in the family source for SPIR-V targets:
//!    Slang lowers it to `VertexIndex - BaseVertex` (D3D semantics), which
//!    needs the DrawParameters capability (an unenabled Vulkan device
//!    feature) and becomes `gl_BaseVertex` (GL 4.6-only) through naga.
//!    families/text.slang loads the raw VertexIndex builtin via
//!    `spirv_asm` instead (WGSL keeps SV_VertexID: its vertex_index is raw).
//!
//! `zig build gen-shaders` (inside `nix-shell`: slangc + naga) rewrites the
//! checked-in artifacts under `src/snail/shader/generated/`; consumers embed
//! those and need no toolchain. The demo Vulkan build additionally compiles
//! the SPIR-V leg directly (it already runs slangc for every family).

const std = @import("std");

pub const family_source = "src/snail/shader/slang/families/text.slang";
pub const module_dir = "src/snail/shader/slang";

const Stage = struct {
    entry: []const u8,
    stage: []const u8,
    short: []const u8, // "vert" / "frag"
};

const stages = [_]Stage{
    .{ .entry = "vertexMain", .stage = "vertex", .short = "vert" },
    .{ .entry = "fragmentMain", .stage = "fragment", .short = "frag" },
};

/// slangc invocation for one entry point of the text family. `target_define`
/// selects the per-target resource-binding flavor in families/text.slang.
fn slangcFamily(
    b: *std.Build,
    stage: Stage,
    target_define: []const u8,
    target_args: []const []const u8,
    output_name: []const u8,
) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{
        "slangc",
        b.fmt("-D{s}", .{target_define}),
        "-entry",
        stage.entry,
        "-stage",
        stage.stage,
        "-default-image-format-unknown",
        "-I",
    });
    cmd.addDirectoryArg(b.path(module_dir));
    cmd.addFileArg(b.path(family_source));
    cmd.addArgs(target_args);
    cmd.addArg("-o");
    return cmd.addOutputFileArg(output_name);
}

/// Compile the native text family to Vulkan SPIR-V (both stages). Used by
/// the demo Vulkan build for the text pipeline and by `gen-shaders` for the
/// checked-in artifact.
pub fn vulkanTextSpv(b: *std.Build) struct { vert: std.Build.LazyPath, frag: std.Build.LazyPath } {
    return .{
        .vert = slangcFamily(b, stages[0], "SNAIL_TARGET_VULKAN", &.{ "-target", "spirv", "-profile", "spirv_1_3" }, "text.vert.spv"),
        .frag = slangcFamily(b, stages[1], "SNAIL_TARGET_VULKAN", &.{ "-target", "spirv", "-profile", "spirv_1_3" }, "text.frag.spv"),
    };
}

pub fn addGenShadersStep(b: *std.Build) void {
    const update = b.addUpdateSourceFiles();

    // Vulkan SPIR-V (checked-in record; the demo build also compiles this
    // leg itself so the running pipeline can never drift from the source).
    const vk = vulkanTextSpv(b);
    update.addCopyFileToSource(vk.vert, "src/snail/shader/generated/spirv/text.vert.spv");
    update.addCopyFileToSource(vk.frag, "src/snail/shader/generated/spirv/text.frag.spv");

    // WGSL — direct target.
    inline for (stages) |stage| {
        const wgsl = slangcFamily(b, stage, "SNAIL_TARGET_WGSL", &.{ "-target", "wgsl" }, "text." ++ stage.short ++ ".wgsl");
        update.addCopyFileToSource(wgsl, "src/snail/shader/generated/wgsl/text." ++ stage.short ++ ".wgsl");
    }

    // GL family — SPIR-V leg, then naga per dialect. naga picks the output
    // language from the file extension (`.vert`/`.frag`); the checked-in
    // artifacts carry the explicit `.glsl` suffix.
    //
    // The FRAGMENT leg must go `-emit-spirv-via-glsl` (slangc → GLSL →
    // glslang): slang's *direct* SPIR-V loop structure is the recorded naga
    // trap — the structurizer buries the loop-exit `break` inside a
    // `do{}while(false)` wrapper and the coverage loops never terminate
    // (GPU hang, white frame). glslang emits loops naga structurizes
    // correctly. The VERTEX leg stays on direct SPIR-V: it has no loops
    // (the trap cannot bite) and its raw-VertexIndex `spirv_asm` block does
    // not compile through the via-glsl backend. Consequence: the two
    // stages' uniform blocks get different generated names (see
    // slang_generated.zig). `-warnings-disable 41012` silences glslang's
    // profile upgrade for samplerless texelFetch.
    inline for (stages) |stage| {
        const via: []const []const u8 = if (std.mem.eql(u8, stage.short, "frag"))
            &.{ "-target", "spirv", "-profile", "spirv_1_3", "-emit-spirv-via-glsl", "-warnings-disable", "41012" }
        else
            &.{ "-target", "spirv", "-profile", "spirv_1_3" };
        const spv = slangcFamily(b, stage, "SNAIL_TARGET_GL", via, "gl-text." ++ stage.short ++ ".spv");
        inline for (.{ "core330", "es300" }, .{ "glsl330", "gles300" }) |profile, out_dir| {
            const naga = b.addSystemCommand(&.{
                "naga", "--input-kind", "spv", "--keep-coordinate-space", "--profile", profile,
            });
            naga.addFileArg(spv);
            const glsl = naga.addOutputFileArg(profile ++ "-text." ++ stage.short);
            update.addCopyFileToSource(glsl, "src/snail/shader/generated/" ++ out_dir ++ "/text." ++ stage.short ++ ".glsl");
        }
    }

    const step = b.step("gen-shaders", "Regenerate the checked-in native-Slang shader artifacts in src/snail/shader/generated (needs slangc + naga)");
    step.dependOn(&update.step);
}
