//! Native-Slang shader toolchain (stage A: text; stage B: the remaining
//! families).
//!
//! Single source: `src/snail/shader/slang/` — proper Slang modules
//! (`module`/`import`), entry points declared with `[shader(...)]` in
//! `families/*.slang`. From each family file every GPU target is generated:
//!
//!   target      command                                              output
//!   ─────────   ──────────────────────────────────────────────────   ─────────────────────────────
//!   Vulkan      slangc -DSNAIL_TARGET_VULKAN -target spirv           generated/spirv/<f>.*.spv
//!               -profile spirv_1_3 -default-image-format-unknown     (also compiled directly by the
//!                                                                    demo Vulkan build, see below)
//!   WGSL        slangc -DSNAIL_TARGET_WGSL -target wgsl              generated/wgsl/<f>.*.wgsl
//!   GLSL 330    slangc -DSNAIL_TARGET_GL -target spirv               generated/glsl330/<f>.*.glsl
//!               -profile spirv_1_3, then
//!               spirv-cross --version 330 --no-420pack-extension
//!   GLES 300    same SPIR-V leg,                                     generated/gles300/<f>.*.glsl
//!               spirv-cross --version 300 --es, then the highp
//!               default-precision patch (build/glsl_patch_es_highp.zig)
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
//!    ingestion path).
//!  - slangc's own `-target glsl` output is Vulkan-flavor GLSL only
//!    (`texture2DArray` + GL_EXT_samplerless_texture_functions,
//!    `layout(binding=N)`, `#version 450+`) and cannot be consumed by
//!    OpenGL 3.3 / GLES 3.0 contexts, so the GL family goes SPIR-V →
//!    SPIRV-Cross. SPIRV-Cross performs no clip-space conversion (the
//!    behavior naga needed `--keep-coordinate-space` to opt into).
//!  - SPIRV-Cross names varyings from each leg's own OpNames
//!    (`entryPointParam_vertexMain_*` from the vertex, `input_*` from the
//!    fragment) and GLSL 330 / ES 300 link varyings BY NAME:
//!    `--rename-interface-variable {out,in} <loc> snail_io<loc>` pins both
//!    stages of every family to one location-keyed name table (renames for
//!    locations a stage does not declare are ignored).
//!  - `--no-420pack-extension` (desktop leg): SPIRV-Cross otherwise emits
//!    `layout(binding = N)` under GL_ARB_shading_language_420pack; the
//!    loaders bind samplers by name (`SPIRV_Cross_Combined*`, see
//!    src/snail/shader/slang_generated.zig) exactly like the composed
//!    catalog's loose `u_*` samplers.
//!  - GLES default precision: SPIRV-Cross fragments open with `precision
//!    mediump float;` and only qualify globals explicitly — locals inherit
//!    the default. build/glsl_patch_es_highp.zig promotes the default to
//!    highp (the catalog's precision; coverage math needs fp32).
//!  - `-target wgsl` works DIRECTLY for native Slang (entry names are the
//!    Slang function names, e.g. `vertexMain`): the GLSL-ingestion bugs
//!    (miscompiled texelFetch, renumbered stage IO) do not apply, and the
//!    output validates with naga as-is. No spirv-opt / naga pipeline needed.
//!  - `SV_VertexID` is avoided in the family source for SPIR-V targets:
//!    Slang lowers it to `VertexIndex - BaseVertex` (D3D semantics), which
//!    needs the DrawParameters capability (an unenabled Vulkan device
//!    feature); through SPIRV-Cross's ES backend BaseVertex is a hard error
//!    ("BaseVertex not supported in ES profile"). families/*.slang load the
//!    raw VertexIndex builtin via `spirv_asm` instead — SPIRV-Cross turns it
//!    into plain `gl_VertexID` (WGSL keeps SV_VertexID: its vertex_index is
//!    raw).
//!  - `-warnings-disable 39001`: the paint-record families alias one
//!    COMBINED_IMAGE_SAMPLER descriptor (set 0, binding 3) with an
//!    image-only and a sampler-only variable — spec-legal, and exactly what
//!    the existing descriptor-set layout provides. slangc warns about the
//!    deliberate overlap.
//!
//! The naga-era via-glsl split (glslang loop shapes for naga's structurizer,
//! spirv-opt ADCE, the cubic-solver / base-vertex / dual-source-index patch
//! tools) is gone: SPIRV-Cross consumes slang's direct SPIR-V for every
//! stage, loops and spirv_asm included, so all GL legs share one recipe.
//!
//! `zig build gen-shaders` (inside `nix-shell`: slangc + spirv-cross)
//! rewrites the checked-in artifacts under `src/snail/shader/generated/`;
//! consumers embed those and need no toolchain. The demo Vulkan build
//! additionally compiles the SPIR-V leg directly (it already runs slangc
//! for every family).

const std = @import("std");

pub const module_dir = "src/snail/shader/slang";

const Stage = struct {
    entry: []const u8,
    stage: []const u8,
    short: []const u8, // "vert" / "frag"
};

const vertex_stage = Stage{ .entry = "vertexMain", .stage = "vertex", .short = "vert" };
const fragment_stage = Stage{ .entry = "fragmentMain", .stage = "fragment", .short = "frag" };

pub const Family = struct {
    /// Artifact base name (generated/<target>/<name>.<stage>.<ext>).
    name: []const u8,
    /// Family entry file under families/.
    source: []const u8,
    /// Extra -D defines (family variants sharing one source).
    defines: []const []const u8 = &.{},
    stages: []const Stage,
    /// GL legs only: compile -O0. At the default -O, slangc strength-reduces
    /// constant divisions (c/1.055 → c*0.94786733), which shifted the
    /// painted family's dither re-linearization by 1 ULP and flipped
    /// scattered gradient pixels by 1 LSB vs the raw-GLSL catalog (the
    /// exact-0 GL gate caught it; the vertex sRGB decode turned
    /// srgbToLinear(1.0) into 0.99999988 the same way). -O0 preserves the
    /// divisions. The Vulkan and WGSL legs must KEEP the default -O: their
    /// pre-cutover baselines came from the slangc GLSL-ingestion pipeline,
    /// which performed the same reduction — per-target bit-parity pins each
    /// leg to its own history. Stage-A text stays on its proven default-O
    /// recipe.
    gl_o0: bool = false,
    /// Emit only the GL dialects (no spirv/wgsl artifacts). Used for the
    /// painted vertex, which exists solely because the GL leg needs the -O0
    /// vertex while Vulkan/WGSL keep sharing the text vertex.
    gl_only: bool = false,
    /// Skip the WGSL artifact (subpixel: slangc's WGSL backend drops
    /// [[vk::index(1)]] — no @blend_src — so a valid dual-source WGSL
    /// module cannot be generated natively; wgpu keeps the old catalog).
    no_wgsl: bool = false,
    /// Skip the GLES 3.0 artifact (subpixel: ES 3.0 has no dual-source
    /// blending; the composed catalog has no GLES subpixel program either).
    no_gles: bool = false,
    /// GL dialects only: run build/glsl_patch_cubic_solver.zig on the
    /// SPIRV-Cross output — substitutes the composed-catalog text of the
    /// cubic Newton solver, whose regenerated emission Mesa compiles with
    /// different multiply-add fusion (1-LSB drift on cubic path edges; see
    /// the tool). This survived the naga→SPIRV-Cross switch: the AE=0 GL
    /// gate needs the composed text either way.
    patch_cubic_solver: bool = false,
};

/// The families gen-shaders produces. Vertex artifacts exist only where the
/// stage differs from the shared text vertex (colr/path/tt_hinted reuse
/// text.vert.* — identical source, identical interface).
pub const families = [_]Family{
    .{ .name = "text", .source = "families/text.slang", .stages = &.{ vertex_stage, fragment_stage } },
    .{ .name = "colr", .source = "families/painted.slang", .defines = &.{"SNAIL_FAMILY_COLR"}, .stages = &.{fragment_stage}, .gl_o0 = true, .patch_cubic_solver = true },
    .{ .name = "path", .source = "families/painted.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .patch_cubic_solver = true },
    .{ .name = "tt_hinted_text", .source = "families/tt_hinted_text.slang", .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "autohint", .source = "families/autohint.slang", .stages = &.{ vertex_stage, fragment_stage }, .gl_o0 = true },
    .{ .name = "text_subpixel", .source = "families/text_subpixel.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_wgsl = true, .no_gles = true },
    // Canonical artifacts plus (new with the SPIRV-Cross leg) the desktop
    // GL dialect — naga rejected the Buffer<uint> texel buffer, SPIRV-Cross
    // emits a plain `usamplerBuffer` (validates under glslang as-is). No
    // GLES artifact: texel buffers do not exist in ES 3.0 at any extension
    // level — SPIRV-Cross emits `#extension GL_EXT_texture_buffer`, but
    // that extension itself requires ES 3.1 (the output only validates
    // with the version line rewritten to `310 es`), so the R32UI-texture
    // interface remains the ES 3.0 answer. The shipped consumer (the
    // game's material shader) keeps composing the GLSL catalog until
    // stage C.
    .{ .name = "text_sample", .source = "families/text_sample_family.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_gles = true },
    // GL-only fullscreen seed/encode pass (Vulkan/WebGPU demo paths render
    // to hardware-sRGB targets and have no linear-resolve pass).
    .{ .name = "linear_resolve", .source = "families/linear_resolve.slang", .stages = &.{ vertex_stage, fragment_stage }, .gl_o0 = true, .gl_only = true },
    // GL-only -O0 vertex for the painted programs (colr + path share it);
    // Vulkan/WGSL painted pipelines keep the text vertex (see gl_o0 docs).
    .{ .name = "painted", .source = "families/painted.slang", .stages = &.{vertex_stage}, .gl_o0 = true, .gl_only = true },
};

fn findFamily(comptime name: []const u8) Family {
    inline for (families) |f| {
        if (comptime std.mem.eql(u8, f.name, name)) return f;
    }
    @compileError("unknown slang shader family: " ++ name);
}

/// slangc invocation for one entry point of one family. `target_define`
/// selects the per-target resource-binding flavor in the family source.
fn slangcFamily(
    b: *std.Build,
    comptime family: Family,
    stage: Stage,
    target_define: []const u8,
    target_args: []const []const u8,
    output_name: []const u8,
) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{
        "slangc",
        b.fmt("-D{s}", .{target_define}),
    });
    inline for (family.defines) |d| cmd.addArg("-D" ++ d);
    cmd.addArgs(&.{
        "-entry",
        stage.entry,
        "-stage",
        stage.stage,
        "-default-image-format-unknown",
        "-warnings-disable",
        "39001",
        "-I",
    });
    cmd.addDirectoryArg(b.path(module_dir));
    cmd.addFileArg(b.path(module_dir ++ "/" ++ family.source));
    cmd.addArgs(target_args);
    cmd.addArg("-o");
    return cmd.addOutputFileArg(output_name);
}

fn vulkanStageSpv(b: *std.Build, comptime family: Family, stage: Stage) std.Build.LazyPath {
    return slangcFamily(b, family, stage, "SNAIL_TARGET_VULKAN", &.{ "-target", "spirv", "-profile", "spirv_1_3" }, b.fmt("{s}.{s}.spv", .{ family.name, stage.short }));
}

/// Compile the native text family to Vulkan SPIR-V (both stages). Used by
/// the demo Vulkan build for the text pipeline and by `gen-shaders` for the
/// checked-in artifact.
pub fn vulkanTextSpv(b: *std.Build) struct { vert: std.Build.LazyPath, frag: std.Build.LazyPath } {
    const family = comptime findFamily("text");
    return .{
        .vert = vulkanStageSpv(b, family, vertex_stage),
        .frag = vulkanStageSpv(b, family, fragment_stage),
    };
}

/// Compile a fragment-only family's Vulkan SPIR-V (the vertex stage is the
/// shared text vertex).
pub fn vulkanFragmentSpv(b: *std.Build, comptime name: []const u8) std.Build.LazyPath {
    return vulkanStageSpv(b, comptime findFamily(name), fragment_stage);
}

/// Compile a family's own Vulkan vertex SPIR-V (autohint).
pub fn vulkanVertexSpv(b: *std.Build, comptime name: []const u8) std.Build.LazyPath {
    return vulkanStageSpv(b, comptime findFamily(name), vertex_stage);
}

pub fn addGenShadersStep(b: *std.Build) void {
    const update = b.addUpdateSourceFiles();
    const es_highp_patch_tool = b.addExecutable(.{
        .name = "glsl-patch-es-highp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/glsl_patch_es_highp.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const solver_patch_tool = b.addExecutable(.{
        .name = "glsl-patch-cubic-solver",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/glsl_patch_cubic_solver.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    inline for (families) |family| {
        inline for (family.stages) |stage| {
            if (!family.gl_only) {
                // Vulkan SPIR-V (checked-in record; the demo build also
                // compiles this leg itself so the running pipeline can never
                // drift from the source).
                const spv = vulkanStageSpv(b, family, stage);
                update.addCopyFileToSource(spv, "src/snail/shader/generated/spirv/" ++ family.name ++ "." ++ stage.short ++ ".spv");

                if (!family.no_wgsl) {
                    // WGSL — direct target.
                    const wgsl = slangcFamily(b, family, stage, "SNAIL_TARGET_WGSL", &.{ "-target", "wgsl" }, family.name ++ "." ++ stage.short ++ ".wgsl");
                    update.addCopyFileToSource(wgsl, "src/snail/shader/generated/wgsl/" ++ family.name ++ "." ++ stage.short ++ ".wgsl");
                }
            }

            // GL family — one direct SPIR-V leg (loops and spirv_asm both
            // fine through SPIRV-Cross), then spirv-cross per dialect.
            const gl_args: []const []const u8 = if (family.gl_o0)
                &.{ "-target", "spirv", "-profile", "spirv_1_3", "-O0" }
            else
                &.{ "-target", "spirv", "-profile", "spirv_1_3" };
            const gl_spv = slangcFamily(b, family, stage, "SNAIL_TARGET_GL", gl_args, "gl-" ++ family.name ++ "." ++ stage.short ++ ".spv");
            inline for (.{ "glsl330", "gles300" }) |out_dir| {
                const es = comptime std.mem.eql(u8, out_dir, "gles300");
                const skip_dialect = family.no_gles and es;
                if (!skip_dialect) {
                    const cross = b.addSystemCommand(&.{"spirv-cross"});
                    cross.addFileArg(gl_spv);
                    if (es) {
                        cross.addArgs(&.{ "--version", "300", "--es" });
                    } else {
                        cross.addArgs(&.{ "--version", "330", "--no-420pack-extension" });
                    }
                    // One location-keyed varying name table for every
                    // family: GLSL <4.10 links varyings by NAME, and the
                    // two stages' SPIR-V legs carry different OpNames.
                    // Locations a stage does not declare are ignored.
                    const dir = if (comptime std.mem.eql(u8, stage.short, "vert")) "out" else "in";
                    const locs = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14" };
                    inline for (locs) |loc_str| {
                        cross.addArgs(&.{ "--rename-interface-variable", dir, loc_str, b.fmt("snail_io{s}", .{loc_str}) });
                    }
                    cross.addArg("--output");
                    var glsl = cross.addOutputFileArg(out_dir ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                    if (family.patch_cubic_solver and comptime std.mem.eql(u8, stage.short, "frag")) {
                        const patch = b.addRunArtifact(solver_patch_tool);
                        patch.addFileArg(glsl);
                        patch.addFileArg(b.path("src/snail/shader/glsl/snail_path_frag_body.glsl"));
                        glsl = patch.addOutputFileArg("patched-" ++ out_dir ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                    }
                    if (es) {
                        // Promote the fragment default precision to highp
                        // (SPIRV-Cross emits mediump; locals inherit it).
                        const patch = b.addRunArtifact(es_highp_patch_tool);
                        patch.addFileArg(glsl);
                        glsl = patch.addOutputFileArg("highp-" ++ out_dir ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                    }
                    update.addCopyFileToSource(glsl, "src/snail/shader/generated/" ++ out_dir ++ "/" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                }
            }
        }
    }

    const step = b.step("gen-shaders", "Regenerate the checked-in native-Slang shader artifacts in src/snail/shader/generated (needs slangc + spirv-cross)");
    step.dependOn(&update.step);
}
