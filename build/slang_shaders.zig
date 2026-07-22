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
//!               naga --keep-coordinate-space --profile core330
//!   GLES 300    same SPIR-V leg, naga --profile es300                generated/gles300/<f>.*.glsl
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
//!    families/*.slang load the raw VertexIndex builtin via
//!    `spirv_asm` instead (WGSL keeps SV_VertexID: its vertex_index is raw).
//!  - `-warnings-disable 39001`: the paint-record families alias one
//!    COMBINED_IMAGE_SAMPLER descriptor (set 0, binding 3) with an
//!    image-only and a sampler-only variable — spec-legal, and exactly what
//!    the existing descriptor-set layout provides. slangc warns about the
//!    deliberate overlap.
//!
//! Only families whose fragment (or vertex) actually reaches the GL/WGSL
//! hosts get the naga legs; per-family stage lists live in `families` below.
//! The FRAGMENT GL leg must go `-emit-spirv-via-glsl` when the stage has
//! loops (slang's direct SPIR-V loop structure is the recorded
//! naga-structurizer trap: the loop-exit `break` lands inside a
//! `do{}while(false)` wrapper and the loop never terminates — GPU hang,
//! white frame). glslang emits loops naga structurizes correctly. Stages
//! with a raw-VertexIndex `spirv_asm` block cannot compile via glsl, so a
//! stage can have loops or spirv_asm, never both.
//!
//! `zig build gen-shaders` (inside `nix-shell`: slangc + naga) rewrites the
//! checked-in artifacts under `src/snail/shader/generated/`; consumers embed
//! those and need no toolchain. The demo Vulkan build additionally compiles
//! the SPIR-V leg directly (it already runs slangc for every family).

const std = @import("std");

pub const module_dir = "src/snail/shader/slang";

const Stage = struct {
    entry: []const u8,
    stage: []const u8,
    short: []const u8, // "vert" / "frag"
    /// GL leg only: compile -emit-spirv-via-glsl (required for stages with
    /// loops; incompatible with spirv_asm).
    via_glsl: bool,
};

const vertex_stage = Stage{ .entry = "vertexMain", .stage = "vertex", .short = "vert", .via_glsl = false };
// The autohint vertex has fitter loops, so its GL leg must take the
// via-glsl path (and therefore SV_VertexID instead of spirv_asm — see
// build/glsl_patch_base_vertex.zig for the consequence).
const via_glsl_vertex_stage = Stage{ .entry = "vertexMain", .stage = "vertex", .short = "vert", .via_glsl = true };
const fragment_stage = Stage{ .entry = "fragmentMain", .stage = "fragment", .short = "frag", .via_glsl = true };
// Loop-free fragments (linear_resolve) may stay on the direct SPIR-V leg.
const direct_fragment_stage = Stage{ .entry = "fragmentMain", .stage = "fragment", .short = "frag", .via_glsl = false };

pub const Family = struct {
    /// Artifact base name (generated/<target>/<name>.<stage>.<ext>).
    name: []const u8,
    /// Family entry file under families/.
    source: []const u8,
    /// Extra -D defines (family variants sharing one source).
    defines: []const []const u8 = &.{},
    stages: []const Stage,
    /// GL via-glsl legs only: compile -O0 and run spirv-opt ADCE before
    /// naga. At the default -O, slangc's embedded glslang strength-reduces
    /// constant divisions (c/1.055 → c*0.94786733), which shifted the
    /// painted family's dither re-linearization by 1 ULP and flipped
    /// scattered gradient pixels by 1 LSB vs the raw-GLSL catalog (the
    /// exact-0 GL gate caught it). -O0 preserves the divisions; the ADCE
    /// pass is then required because un-inlined code keeps the dead layer
    /// component of arrayed GetDimensions queries, which naga's SPIR-V
    /// front end rejects ("Index 2 is out of bounds"). Stage-A text stays
    /// on its proven default-O recipe.
    ///
    /// The same reduction happens in slangc's DIRECT SPIR-V backend at the
    /// default -O (the vertex sRGB decode turned srgbToLinear(1.0) into
    /// 0.99999988, scaling every painted pixel and flipping scattered LSBs
    /// on the GL gate), so gl_o0 applies to direct-leg GL stages too. The
    /// Vulkan and WGSL legs must KEEP the default -O: their pre-cutover
    /// baselines came from the slangc GLSL-ingestion pipeline, which
    /// performed the same reduction — per-target bit-parity pins each leg
    /// to its own history.
    gl_o0: bool = false,
    /// Emit only the naga GL dialects (no spirv/wgsl artifacts). Used for
    /// the painted vertex, which exists solely because the GL leg needs
    /// the -O0 vertex while Vulkan/WGSL keep sharing the text vertex.
    gl_only: bool = false,
    /// GL dialects only: run build/glsl_patch_cubic_solver.zig on the naga
    /// output — substitutes the composed-catalog text of the cubic Newton
    /// solver, whose naga emission Mesa compiles with different
    /// multiply-add fusion (ULP drift on cubic path edges; see the tool).
    patch_cubic_solver: bool = false,
    /// GL vertex dialects only: run build/glsl_patch_base_vertex.zig on
    /// the naga output — pins the D3D-semantics gl_BaseVertex read (GL
    /// 4.6-only, absent in GLES) to 0, exact for snail's base-vertex-0
    /// draws. Needed by via-glsl vertex legs, which cannot use the
    /// spirv_asm raw-VertexIndex workaround.
    patch_gl_base_vertex: bool = false,
    /// Skip the WGSL artifact (subpixel: slangc's WGSL backend drops
    /// [[vk::index(1)]] — no @blend_src — so a valid dual-source WGSL
    /// module cannot be generated natively; wgpu keeps the old catalog).
    no_wgsl: bool = false,
    /// Skip the GLES 3.0 artifact (subpixel: ES 3.0 has no dual-source
    /// blending; the composed catalog has no GLES subpixel program either).
    no_gles: bool = false,
    /// Skip BOTH naga GL dialects (text_sample: naga's SPIR-V front end
    /// rejects texel buffers — "unsupported image dimension" /
    /// SampledBuffer — so the canonical GL flavor cannot be generated; the
    /// GL consumer keeps composing the GLSL catalog until stage C).
    no_gl: bool = false,
    /// GL leg only: run build/spv_patch_dual_source.zig before naga to add
    /// the explicit `Index 0` on the color output that naga's SPIR-V front
    /// end requires next to the blend output's `Index 1`.
    patch_dual_source_index: bool = false,
};

/// The families gen-shaders produces. Vertex artifacts exist only where the
/// stage differs from the shared text vertex (colr/path/tt_hinted reuse
/// text.vert.* — identical source, identical interface).
pub const families = [_]Family{
    .{ .name = "text", .source = "families/text.slang", .stages = &.{ vertex_stage, fragment_stage } },
    .{ .name = "colr", .source = "families/painted.slang", .defines = &.{"SNAIL_FAMILY_COLR"}, .stages = &.{fragment_stage}, .gl_o0 = true, .patch_cubic_solver = true },
    .{ .name = "path", .source = "families/painted.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .patch_cubic_solver = true },
    .{ .name = "tt_hinted_text", .source = "families/tt_hinted_text.slang", .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "autohint", .source = "families/autohint.slang", .stages = &.{ via_glsl_vertex_stage, fragment_stage }, .gl_o0 = true, .patch_gl_base_vertex = true },
    .{ .name = "text_subpixel", .source = "families/text_subpixel.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_wgsl = true, .no_gles = true, .patch_dual_source_index = true },
    // Canonical artifacts only — the shipped consumer (the game's material
    // shader) keeps composing the GLSL catalog until stage C. GLES skipped:
    // no texel buffers in ES 3.0 (the R32UI-texture interface stays).
    .{ .name = "text_sample", .source = "families/text_sample_family.slang", .stages = &.{fragment_stage}, .no_gl = true },
    // GL-only fullscreen seed/encode pass (Vulkan/WebGPU demo paths render
    // to hardware-sRGB targets and have no linear-resolve pass). Loop-free,
    // so both GL legs stay on direct SPIR-V (fragment_stage's via-glsl is
    // for loop-bearing stages).
    .{ .name = "linear_resolve", .source = "families/linear_resolve.slang", .stages = &.{ vertex_stage, direct_fragment_stage }, .gl_o0 = true, .gl_only = true },
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
    const solver_patch_tool = b.addExecutable(.{
        .name = "glsl-patch-cubic-solver",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/glsl_patch_cubic_solver.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const base_vertex_patch_tool = b.addExecutable(.{
        .name = "glsl-patch-base-vertex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/glsl_patch_base_vertex.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const dual_source_patch_tool = b.addExecutable(.{
        .name = "spv-patch-dual-source-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/spv_patch_dual_source.zig"),
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

            // GL family — SPIR-V leg, then naga per dialect. naga picks the
            // output language from the file extension (`.vert`/`.frag`); the
            // checked-in artifacts carry the explicit `.glsl` suffix.
            if (!family.no_gl) {
            const via: []const []const u8 = if (stage.via_glsl and family.gl_o0)
                &.{ "-target", "spirv", "-profile", "spirv_1_3", "-emit-spirv-via-glsl", "-warnings-disable", "41012", "-O0" }
            else if (stage.via_glsl)
                &.{ "-target", "spirv", "-profile", "spirv_1_3", "-emit-spirv-via-glsl", "-warnings-disable", "41012" }
            else if (family.gl_o0)
                &.{ "-target", "spirv", "-profile", "spirv_1_3", "-O0" }
            else
                &.{ "-target", "spirv", "-profile", "spirv_1_3" };
            var raw_gl_spv = slangcFamily(b, family, stage, "SNAIL_TARGET_GL", via, "gl-" ++ family.name ++ "." ++ stage.short ++ ".spv");
            if (family.patch_dual_source_index and std.mem.eql(u8, stage.short, "frag")) {
                const patch = b.addRunArtifact(dual_source_patch_tool);
                patch.addFileArg(raw_gl_spv);
                raw_gl_spv = patch.addOutputFileArg("idx-" ++ family.name ++ "." ++ stage.short ++ ".spv");
                patch.addArgs(&.{ "fragmentMain_color", "0" });
            }
            const gl_spv = if (stage.via_glsl and family.gl_o0) blk: {
                const dce = b.addSystemCommand(&.{ "spirv-opt", "--eliminate-dead-code-aggressive" });
                dce.addFileArg(raw_gl_spv);
                dce.addArg("-o");
                break :blk dce.addOutputFileArg("dce-" ++ family.name ++ "." ++ stage.short ++ ".spv");
            } else raw_gl_spv;
            inline for (.{ "core330", "es300" }, .{ "glsl330", "gles300" }) |profile, out_dir| {
                const skip_dialect = family.no_gles and comptime std.mem.eql(u8, profile, "es300");
                if (!skip_dialect) {
                const naga = b.addSystemCommand(&.{
                    "naga", "--input-kind", "spv", "--keep-coordinate-space", "--profile", profile,
                });
                naga.addFileArg(gl_spv);
                var glsl = naga.addOutputFileArg(profile ++ "-" ++ family.name ++ "." ++ stage.short);
                if (family.patch_cubic_solver and std.mem.eql(u8, stage.short, "frag")) {
                    const patch = b.addRunArtifact(solver_patch_tool);
                    patch.addFileArg(glsl);
                    patch.addFileArg(b.path("src/snail/shader/glsl/snail_path_frag_body.glsl"));
                    glsl = patch.addOutputFileArg("patched-" ++ profile ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                }
                if (family.patch_gl_base_vertex and std.mem.eql(u8, stage.short, "vert")) {
                    const patch = b.addRunArtifact(base_vertex_patch_tool);
                    patch.addFileArg(glsl);
                    glsl = patch.addOutputFileArg("bv-patched-" ++ profile ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                }
                update.addCopyFileToSource(glsl, "src/snail/shader/generated/" ++ out_dir ++ "/" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                }
            }
            }
        }
    }

    const step = b.step("gen-shaders", "Regenerate the checked-in native-Slang shader artifacts in src/snail/shader/generated (needs slangc + naga)");
    step.dependOn(&update.step);
}
