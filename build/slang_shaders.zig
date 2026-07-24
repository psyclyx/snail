//! Native-Slang shader toolchain for every supported shipped family/target
//! combination.
//!
//! Single source: `src/snail/shader/slang/` — proper Slang modules
//! (`module`/`import`), entry points declared with `[shader(...)]` in
//! `families/*.slang`. From each family file every GPU target is generated:
//!
//!   target      command                                              output
//!   ─────────   ──────────────────────────────────────────────────   ─────────────────────────────
//!   Vulkan      slangc -DSNAIL_TARGET_VULKAN -target spirv -O2       generated/spirv/<f>.*.spv
//!               -profile spirv_1_3 -default-image-format-unknown     (also compiled directly by the
//!                                                                    demo Vulkan build, see below)
//!   WGSL        slangc -DSNAIL_TARGET_WGSL -target wgsl              generated/wgsl/<f>.*.wgsl
//!   D3D11       slangc -DSNAIL_TARGET_D3D11 -target hlsl             generated/hlsl/<f>.*.hlsl
//!               -profile sm_5_0 -line-directive-mode none            (see hlsl_args for the trap notes)
//!   Metal       slangc -DSNAIL_TARGET_METAL -target metal            generated/msl/<f>.*.metal
//!               -ignore-capabilities -line-directive-mode none       (see msl_args)
//!   GLSL 330    slangc -DSNAIL_TARGET_GL -target glsl                generated/glsl330/<f>.*.glsl
//!   GLES 300    slangc -DSNAIL_TARGET_GL -DSNAIL_TARGET_GLES         generated/gles300/<f>.*.glsl
//!               both direct outputs pass through the mechanical dialect /
//!               interface normalizer (build/glsl_patch_direct.zig)
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
//!  - `-O2` (Vulkan only): optimize the native-Slang IR before handing it
//!    to the runtime driver. Slang's default -O1 substantially inflates the
//!    coverage-heavy modules (the path fragment is ~172 KiB at -O1 versus
//!    ~107 KiB at -O2 with v2026.5.2), making a genuinely cold NVIDIA
//!    pipeline compile needlessly expensive. The GL legs use the separate
//!    source-compile recipe described below.
//!  - `-O0` (coverage-heavy desktop-GL families only) preserves authored
//!    helper boundaries in Slang's direct GLSL backend. GLES keeps Slang's
//!    default O1: NVIDIA's GLES compiler reproducibly misrenders the O0
//!    painted fragment while O1 retains the same cold link time and renders
//!    identically on NVIDIA and Mesa.
//!  - `-target glsl` preserves the source's structured control flow, but
//!    Slang v2026.5.2 emits Vulkan-flavor surface syntax (`#version 450`,
//!    resource bindings, and varying locations) even for `glsl_330`.
//!    build/glsl_patch_direct.zig mechanically selects the shipping dialect,
//!    removes bindings, promotes GLES defaults to highp, and pins both
//!    stages' varyings to `snail_io<location>`. It performs no IR translation.
//!  - Portable binary16 decode: the compact autohint policy is unpacked in
//!    Slang with uint32/float32 operations, not `f16tof32`. That intrinsic
//!    can otherwise become real 16-bit operations unavailable in baseline GL 3.3
//!    and GLES 3.0. Generated-artifact tests reject those capabilities and
//!    narrow GLSL types so this cannot silently regress with source/toolchain
//!    changes.
//!  - GLES default precision is inserted as highp by the direct patcher
//!    (the catalog's precision; coverage math needs fp32).
//!  - `-target wgsl` works DIRECTLY for native Slang (entry names are the
//!    Slang function names, e.g. `vertexMain`): the GLSL-ingestion bugs
//!    (miscompiled texelFetch, renumbered stage IO) do not apply, and the
//!    output validates with naga as-is. No spirv-opt / naga pipeline needed.
//!  - `SV_VertexID` is avoided in the family source for SPIR-V targets:
//!    Slang lowers it to `VertexIndex - BaseVertex` for SPIR-V. Vulkan
//!    families therefore use raw VertexIndex via `spirv_asm`; the direct GL
//!    target uses native `gl_VertexID`.
//!  - `-warnings-disable 39001`: the paint-record families alias one
//!    COMBINED_IMAGE_SAMPLER descriptor (set 0, binding 3) with an
//!    image-only and a sampler-only variable — spec-legal, and exactly what
//!    the existing descriptor-set layout provides. slangc warns about the
//!    deliberate overlap.
//!
//! The GL artifacts no longer round-trip through SPIR-V/SPIRV-Cross.
//!
//! Artifacts are NOT checked in: every compile is a lazy build-graph Run
//! step whose output lands in the zig cache. `createGeneratedModule` lays
//! the artifacts of a REQUESTED TARGET SET out next to
//! `src/snail/shader/generated_root.zig` (copied into one WriteFiles
//! directory per module) and publishes the result as a module: the
//! aggregate `snail-shaders` (every target) plus per-target scoped
//! modules (`snail-shaders-gl`, `-glsl330`, `-wgsl`, `-hlsl`, `-msl`; see
//! build.zig). All modules share the one accessor root — Zig analyzes
//! declarations lazily, so an accessor for a target absent from the
//! module's WriteFiles dir is never analyzed and its `@embedFile` never
//! fires, as long as the consumer doesn't call it. A module therefore
//! depends on exactly its own targets' Run steps: a WGSL-only consumer
//! runs only slangc; builds that never touch generated shaders need no shader
//! compiler. `zig build gen-shaders` optionally materializes
//! the full matrix into zig-out/shaders/ for inspection.

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
    /// Family entry file under `dir`.
    source: []const u8,
    /// Directory containing the family entry file. Defaults to the library
    /// module dir; caller-authored families (the game's material shader)
    /// live in their own tree and import the library modules via the
    /// always-passed `-I module_dir`.
    dir: []const u8 = module_dir,
    /// Who consumes the artifacts. Library families feed the
    /// `snail-shaders` module; caller-authored families (the game's
    /// material shader) are wired as anonymous imports next to their
    /// consumer.
    owner: enum { library, game } = .library,
    /// Extra -D defines (family variants sharing one source).
    defines: []const []const u8 = &.{},
    stages: []const Stage,
    /// Preserve authored helper boundaries in coverage-heavy desktop GLSL.
    /// GLES intentionally keeps Slang's default O1; see the flag notes above.
    gl_o0: bool = false,
    /// Emit only the GL dialects (no spirv/wgsl artifacts): linear_resolve
    /// (Vulkan/WebGPU render to hardware-sRGB targets and have no resolve
    /// pass) and the game's material family (its Vulkan leg is compiled by
    /// the demo build directly).
    gl_only: bool = false,
    /// Skip the GLES 3.0 artifact (subpixel: ES 3.0 has no dual-source
    /// blending).
    no_gles: bool = false,
};

/// slangc arguments for the D3D11 HLSL leg (SM 5.0, FXC/d3dcompiler_47
/// class — slangc emits fxc-compatible HLSL: plain `cbuffer`, no
/// ConstantBuffer<> syntax). Notes, all verified empirically (v2026.5.2):
///
///  - Matrix layout: like the SPIR-V legs, the DEFAULT layout is correct.
///    The HLSL backend prints `#pragma pack_matrix(column_major)` and
///    `mul(mvp, v)`: with column-major packing, HLSL's logical row i
///    gathers the i-th component of each memory register, so the CPU's
///    column-major GLSL bytes read with GLSL `M * v` semantics — the same
///    convention every other target uses. No matrix flag is passed.
///  - Registers are assigned in declaration order and land exactly on the
///    Vulkan binding numbers: b0 = SnailPushConstants cbuffer, t0 curve,
///    t1 band, t2 layer-info (t2 records for text_sample), t3 image array,
///    s0 image sampler (`-fvk-*` flags do not apply to -target hlsl).
///  - -DSNAIL_TARGET_D3D11 selects the SV_VertexID entry (native D3D
///    semantics there; the spirv_asm raw-VertexIndex load is a hard error:
///    "unexpected IR opcode during code emit") including the clip-space
///    y-flip (D3D11 clip space is y-up like WebGPU's), and the plain
///    resource-declaration branch shared with the GL family.
///  - IO struct fields need HLSL semantics (ATTRIB0..6 vertex inputs,
///    TEXCOORD0..14 varyings, declared in the family sources next to the
///    [[vk::location]]s); without them dxc/fxc reject the entry point.
///  - -line-directive-mode none keeps absolute build paths out of the
///    generated artifacts.
///  - Dual source: [[vk::index(1)]] emits SV_Target0/SV_Target1 — D3D11's
///    dual-source form (blend factors SRC1_*) — so text_subpixel has a
///    full-fidelity HLSL artifact.
const hlsl_args: []const []const u8 = &.{ "-target", "hlsl", "-profile", "sm_5_0", "-line-directive-mode", "none" };

/// slangc arguments for the Metal MSL leg. Linux checks the generated
/// contract textually; macOS CI runtime-compiles every MSL artifact with a
/// real Metal frontend, builds the scene-used pipelines, and render-gates
/// them on a real GPU. Notes below were verified against the emitted code
/// (v2026.5.2):
///
///  - `-ignore-capabilities` is load-bearing: slangc's capability checker
///    has a Metal-specific bug where a fragment entry that uses `discard`
///    or a derivative op (`fwidth`) AND calls any function from an
///    imported module fails with E36107 "unavailable features in entry
///    point" — the same code compiles fine when the callee is pasted into
///    the entry's own translation unit, and `discard`/`fwidth` alone are
///    fine (they emit `discard_fragment()` / `dfdx`-based `fwidth`).
///    Every other target still compiles WITHOUT the flag, so capability
///    checking is only relaxed on this leg.
///  - Matrix layout: same shape as the verified WGSL leg — the parameter
///    block stores `_MatrixStorage_float4x4_ColMajornatural`, the entry
///    unpacks it with an explicit transpose into the logical row-major
///    matrix and multiplies `v * M`, so the CPU's column-major GLSL bytes
///    read with GLSL `M * v` semantics. Byte-for-byte the same contract as
///    every other target; no matrix flag is passed.
///  - The parameter block is `constant SnailPushConstants_natural*` at
///    [[buffer(0)]] with NATURAL (C) layout — identical offsets to the
///    96-byte PushConstants extern struct (all fields naturally aligned).
///  - Resources land on the Vulkan binding numbers in declaration order:
///    [[texture(0)]] curve, [[texture(1)]] band, [[texture(2)]] layer-info
///    (= the records texture_buffer for text_sample), [[texture(3)]] image
///    array, [[sampler(0)]] image sampler. Stage-in vertex data arrives
///    via [[attribute(0..6)]] (a MTLVertexDescriptor maps the instance
///    stream; its buffer index is the HOST's choice and must not collide
///    with [[buffer(0)]]).
///  - -DSNAIL_TARGET_METAL selects the SV_VertexID entry branch shared
///    with WGSL/D3D11 (spirv_asm is the same hard error as on HLSL:
///    "unexpected IR opcode during code emit"); SV_VertexID becomes the
///    native [[vertex_id]]. Metal clip space is y-up with z in [0,1] like
///    D3D11's, and the Metal backend inserts NO coordinate conversion
///    (verified: the only y-negation in the artifact is the family
///    source's explicit flip), so mvp = ortho(0, w, 0, h) like
///    minimal_wgpu/minimal_d3d11.
///  - Entry points keep their Slang names ([[vertex]] vertexMain /
///    [[fragment]] fragmentMain).
///  - Dual source: the Metal backend DROPS [[vk::index(1)]] (like WGSL's)
///    and emits text_subpixel's outputs as plain MRT [[color(0)]] /
///    [[color(1)]]. A Metal dual-source consumer must textually rewrite
///    the blend output to `[[color(0), index(1)]]` before compiling.
///  - text_sample's Buffer<uint> emits as `texture_buffer<uint,
///    access::read>` — MSL 2.1+ (set languageVersion when compiling).
///  - -line-directive-mode none keeps build paths out of the artifacts
///    (the Metal backend otherwise emits #line with the slangc input
///    paths, like the HLSL backend).
const msl_args: []const []const u8 = &.{ "-target", "metal", "-ignore-capabilities", "-line-directive-mode", "none" };

/// The families gen-shaders produces. Vertex artifacts exist only where the
/// stage differs from the shared text vertex (colr/path/tt_hinted reuse
/// text.vert.* — identical source, identical interface).
pub const families = [_]Family{
    .{ .name = "text", .source = "families/text.slang", .stages = &.{ vertex_stage, fragment_stage } },
    .{ .name = "colr", .source = "families/painted.slang", .defines = &.{"SNAIL_PAINTED_COLR"}, .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "path_quadratic", .source = "families/painted.slang", .defines = &.{ "SNAIL_PAINTED_PATH", "SNAIL_PATH_QUADRATIC" }, .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "path_conic", .source = "families/painted.slang", .defines = &.{ "SNAIL_PAINTED_PATH", "SNAIL_PATH_CONIC" }, .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "path", .source = "families/painted.slang", .defines = &.{"SNAIL_PAINTED_PATH"}, .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "tt_hinted_text", .source = "families/tt_hinted_text.slang", .stages = &.{fragment_stage}, .gl_o0 = true },
    .{ .name = "autohint", .source = "families/autohint.slang", .stages = &.{ vertex_stage, fragment_stage }, .gl_o0 = true },
    // The WGSL artifact carries a dual-source entry (`fragmentDualMain`,
    // @blend_src 0/1) synthesized after slangc by
    // build/wgsl_gen_dual_entry.zig; the plain `fragmentMain` entry keeps
    // MRT locations 0/1. naga validates the transformed artifact.
    .{ .name = "text_subpixel", .source = "families/text_subpixel.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_gles = true },
    // LCD subpixel variants of the hinted text families. Fragment-only:
    // tt_hinted_text_subpixel pairs with text.vert, autohint_subpixel with
    // autohint.vert (identical varying interfaces). Same dual-source and
    // WGSL post-generation transform as text_subpixel.
    .{ .name = "tt_hinted_text_subpixel", .source = "families/tt_hinted_text_subpixel.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_gles = true },
    .{ .name = "autohint_subpixel", .source = "families/autohint_subpixel.slang", .stages = &.{fragment_stage}, .gl_o0 = true, .no_gles = true },
    // Canonical artifacts for every target. Desktop GL is a plain
    // `usamplerBuffer` texel buffer. GLES 3.0 has no texel buffers at any
    // extension level (GL_EXT_texture_buffer requires ES 3.1), so its leg
    // compiles with -DSNAIL_TARGET_GLES and binds the emit words as a 2D
    // R32UI texture instead.
    .{ .name = "text_sample", .source = "families/text_sample_family.slang", .stages = &.{fragment_stage}, .gl_o0 = true },
    // The game demo's text-as-material shader: a caller-authored family
    // importing the library's text_sample module. GL dialects are wired as
    // anonymous imports next to the consumer (build.zig addGameShaderGl);
    // the Vulkan leg is compiled by the demo build directly (build.zig
    // addGameShaderSpirv), like the library families.
    .{ .name = "game_material", .source = "game_material.slang", .dir = "src/demo/game/slang", .owner = .game, .stages = &.{ vertex_stage, fragment_stage }, .gl_o0 = true, .gl_only = true },
    // GL-only fullscreen seed/encode pass (Vulkan/WebGPU demo paths render
    // to hardware-sRGB targets and have no linear-resolve pass).
    .{ .name = "linear_resolve", .source = "families/linear_resolve.slang", .stages = &.{ vertex_stage, fragment_stage }, .gl_o0 = true, .gl_only = true },
};

fn findFamily(comptime name: []const u8) Family {
    inline for (families) |f| {
        if (comptime std.mem.eql(u8, f.name, name)) return f;
    }
    @compileError("unknown slang shader family: " ++ name);
}

/// Register every `.slang` file under `dir_path` (recursively) as a cache
/// input of the slangc invocation. Load-bearing: `addDirectoryArg` (the
/// `-I` argument) hashes only the path STRING — without explicit file
/// inputs, an edit to an imported module (anything that is not the family
/// entry file) leaves the cached slangc output stale and consumers silently
/// embed old artifacts.
fn addModuleInputs(b: *std.Build, cmd: *std.Build.Step.Run, dir_path: []const u8) void {
    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        const sub_path = b.pathJoin(&.{ dir_path, entry.name });
        switch (entry.kind) {
            .file => if (std.mem.endsWith(u8, entry.name, ".slang")) cmd.addFileInput(b.path(sub_path)),
            .directory => addModuleInputs(b, cmd, sub_path),
            else => {},
        }
    }
}

/// Per-tool preflight for the shader toolchain, mirroring the
/// HARFBUZZ_SRC pattern in build.zig: when a tool is missing from PATH,
/// every generation Run step that would invoke it gets a Fail-step
/// dependency so consumers abort with a message naming exactly what is
/// missing for which targets, instead of a raw exec error. The gates are
/// PER TOOL because WGSL's dual-source validation additionally needs naga;
/// every generated target otherwise needs only slangc. Consumers that never depend on generated
/// shaders are untouched (the Fail steps, like the Run steps, only
/// execute when depended on). Cached per build graph.
var toolchain_gate_cache: ?struct {
    owner: *std.Build,
    slangc_fail: ?*std.Build.Step,
    naga_fail: ?*std.Build.Step,
} = null;

fn toolchainGates(b: *std.Build) *@TypeOf(toolchain_gate_cache.?) {
    if (toolchain_gate_cache) |*g| if (g.owner == b) return g;
    const slangc_missing = if (b.findProgram(&.{"slangc"}, &.{})) |_| false else |_| true;
    const naga_missing = if (b.findProgram(&.{"naga"}, &.{})) |_| false else |_| true;
    toolchain_gate_cache = .{
        .owner = b,
        .slangc_fail = if (slangc_missing)
            &b.addFail("generated shaders (all targets: spirv/wgsl/hlsl/msl/glsl330/gles300) need slangc; enter nix-shell or install shader-slang").step
        else
            null,
        .naga_fail = if (naga_missing)
            &b.addFail("the subpixel WGSL validation tripwire needs the naga CLI (wgpu-utils); enter nix-shell or install it (only zig build test / gen-shaders run this)").step
        else
            null,
    };
    return &toolchain_gate_cache.?;
}

fn attachSlangcGate(b: *std.Build, step: *std.Build.Step) void {
    if (toolchainGates(b).slangc_fail) |fail| step.dependOn(fail);
}

/// slangc invocation for one entry point of one family. `target_defines`
/// select the per-target resource-binding flavor in the family source (the
/// GLES legs pass SNAIL_TARGET_GL + SNAIL_TARGET_GLES.
fn slangcFamily(
    b: *std.Build,
    comptime family: Family,
    stage: Stage,
    target_defines: []const []const u8,
    target_args: []const []const u8,
    output_name: []const u8,
) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{"slangc"});
    attachSlangcGate(b, &cmd.step);
    for (target_defines) |d| cmd.addArg(b.fmt("-D{s}", .{d}));
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
    addModuleInputs(b, cmd, module_dir);
    if (comptime !std.mem.eql(u8, family.dir, module_dir)) addModuleInputs(b, cmd, family.dir);
    cmd.addFileArg(b.path(family.dir ++ "/" ++ family.source));
    cmd.addArgs(target_args);
    cmd.addArg("-o");
    return cmd.addOutputFileArg(output_name);
}

fn vulkanStageSpv(b: *std.Build, comptime family: Family, stage: Stage) std.Build.LazyPath {
    return slangcFamily(b, family, stage, &.{"SNAIL_TARGET_VULKAN"}, &.{ "-target", "spirv", "-profile", "spirv_1_3", "-O2" }, b.fmt("{s}.{s}.spv", .{ family.name, stage.short }));
}

/// A slang reflection JSON for one family+stage+target (an extra compile:
/// adding `-reflection-json` to the artifact compiles would churn every
/// cache key; slangc runs are cheap). Input registration matches
/// slangcFamily.
fn stageReflectionJson(b: *std.Build, comptime family: Family, stage: Stage, target_define: []const u8, target_args: []const []const u8, label: []const u8) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{"slangc"});
    attachSlangcGate(b, &cmd.step);
    cmd.addArg(b.fmt("-D{s}", .{target_define}));
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
    addModuleInputs(b, cmd, module_dir);
    if (comptime !std.mem.eql(u8, family.dir, module_dir)) addModuleInputs(b, cmd, family.dir);
    cmd.addFileArg(b.path(family.dir ++ "/" ++ family.source));
    cmd.addArgs(target_args);
    cmd.addArg("-reflection-json");
    const json = cmd.addOutputFileArg(b.fmt("{s}.{s}.{s}.reflection.json", .{ family.name, stage.short, label }));
    cmd.addArg("-o");
    _ = cmd.addOutputFileArg(b.fmt("{s}.{s}.{s}.refl.out", .{ family.name, stage.short, label }));
    return json;
}

/// Families sharing the SnailPushConstants parameter block; their
/// reflections feed the generated parameter-ABI module (reflection.zig).
/// text_sample / linear_resolve / the game material own different
/// parameter blocks.
fn familyHasReflectionContract(comptime name: []const u8) bool {
    return comptime std.mem.eql(u8, name, "text") or
        std.mem.eql(u8, name, "colr") or
        std.mem.eql(u8, name, "path_quadratic") or
        std.mem.eql(u8, name, "path_conic") or
        std.mem.eql(u8, name, "path") or
        std.mem.eql(u8, name, "tt_hinted_text") or
        std.mem.eql(u8, name, "autohint") or
        std.mem.eql(u8, name, "text_subpixel") or
        std.mem.eql(u8, name, "tt_hinted_text_subpixel") or
        std.mem.eql(u8, name, "autohint_subpixel");
}

/// Compile the native text family to Vulkan SPIR-V (both stages). Used by
/// the demo Vulkan build for the text pipeline and by `collectArtifacts`
/// for the module artifact.
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

/// Compile the game demo's material family to Vulkan SPIR-V (both stages).
/// The game is a caller of snail's text_sample module, so its Vulkan leg is
/// compiled by the demo build like the library families (the GL dialects
/// the GL hosts embed come from `Artifacts.game`, see collectArtifacts).
pub fn vulkanGameMaterialSpv(b: *std.Build) struct { vert: std.Build.LazyPath, frag: std.Build.LazyPath } {
    const family = comptime findFamily("game_material");
    return .{
        .vert = vulkanStageSpv(b, family, vertex_stage),
        .frag = vulkanStageSpv(b, family, fragment_stage),
    };
}

/// The generated-artifact targets. `createGeneratedModule` scopes a
/// module to a subset so its consumers depend on (and run) exactly that
/// subset's generation steps: all targets are compiled directly by slangc.
pub const Target = enum { spirv, wgsl, hlsl, msl, glsl330, gles300 };

/// One generated artifact: its target, its path under the module's
/// `generated/` tree (e.g. "spirv/text.vert.spv"), and the build-graph
/// file producing it.
pub const Entry = struct {
    target: Target,
    sub_path: []const u8,
    file: std.Build.LazyPath,
    /// Optional validation step (naga over transformed subpixel WGSL, so
    /// regeneration re-proves the structural transform's assumptions).
    /// Run only by the aggregate/test module and gen-shaders, never by
    /// consumer scopes.
    validate: ?*std.Build.Step = null,
};

/// The full per-target artifact matrix, split by owner: `library` feeds the
/// `snail-shaders` module, `game` is the game demo's caller-authored
/// material family (GL dialects, wired as anonymous imports next to the
/// consumer by build.zig addGameShaderGl).
pub const Artifacts = struct {
    library: []const Entry,
    game: []const Entry,
    /// The generated parameter-ABI module (see
    /// build/gen_shader_reflection_zig.zig), copied next to the accessor
    /// root in every scope as `reflection.zig`.
    reflection_zig: std.Build.LazyPath,
};

fn appendEntry(b: *std.Build, list: *std.ArrayList(Entry), target: Target, sub_path: []const u8, file: std.Build.LazyPath) void {
    appendEntryValidated(b, list, target, sub_path, file, null);
}

fn appendEntryValidated(b: *std.Build, list: *std.ArrayList(Entry), target: Target, sub_path: []const u8, file: std.Build.LazyPath, validate: ?*std.Build.Step) void {
    list.append(b.allocator, .{ .target = target, .sub_path = sub_path, .file = file, .validate = validate }) catch @panic("OOM");
}

/// `naga <artifact>` — static WGSL validation. Only wired into the
/// aggregate/test module and gen-shaders (see Entry.validate).
fn nagaValidation(b: *std.Build, wgsl: std.Build.LazyPath) *std.Build.Step {
    const run = b.addSystemCommand(&.{"naga"});
    run.addFileArg(wgsl);
    if (toolchainGates(b).naga_fail) |fail| run.step.dependOn(fail);
    return &run.step;
}

/// Wire every slangc invocation as lazy Run steps and return
/// their outputs. Nothing here executes unless a consumer depends on the
/// LazyPaths, so builds that never touch generated shaders never need the
/// toolchain on PATH.
pub fn collectArtifacts(b: *std.Build) Artifacts {
    var library: std.ArrayList(Entry) = .empty;
    var game: std.ArrayList(Entry) = .empty;
    const direct_glsl_patch_tool = b.addExecutable(.{
        .name = "glsl-patch-direct",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/glsl_patch_direct.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const wgsl_dual_entry_tool = b.addExecutable(.{
        .name = "wgsl-gen-dual-entry",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/wgsl_gen_dual_entry.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    // The parameter-ABI generator: every shared-block family's Vulkan-leg
    // reflection (both stages) plus one WGSL-leg reflection (the uniform
    // buffer's group/binding) → reflection.zig, laid out next to the
    // accessor root in every scope. Uniformity across families is asserted
    // by the tool.
    const reflection_gen_tool = b.addExecutable(.{
        .name = "gen-shader-reflection-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/gen_shader_reflection_zig.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const reflection_gen = b.addRunArtifact(reflection_gen_tool);
    const reflection_zig = reflection_gen.addOutputFileArg("reflection.zig");
    reflection_gen.addFileArg(stageReflectionJson(b, comptime findFamily("text"), fragment_stage, "SNAIL_TARGET_WGSL", &.{ "-target", "wgsl" }, "wgsl"));
    inline for (families) |family| {
        if (comptime familyHasReflectionContract(family.name)) {
            inline for (family.stages) |stage| {
                reflection_gen.addFileArg(stageReflectionJson(b, family, stage, "SNAIL_TARGET_VULKAN", &.{ "-target", "spirv", "-profile", "spirv_1_3" }, "vk"));
            }
        }
    }

    inline for (families) |family| {
        inline for (family.stages) |stage| {
            const list = switch (family.owner) {
                .library => &library,
                .game => &game,
            };
            if (!family.gl_only) {
                // Vulkan SPIR-V (module artifact; the demo build also
                // compiles this leg itself so the running pipeline can never
                // drift from the source).
                const spv = vulkanStageSpv(b, family, stage);
                appendEntry(b, list, .spirv, "spirv/" ++ family.name ++ "." ++ stage.short ++ ".spv", spv);

                // WGSL — direct target. The subpixel families' artifacts
                // then gain their dual-source entry (`fragmentDualMain`,
                // @blend_src) via wgsl-gen-dual-entry — a mechanical clone
                // of fragmentMain derived from the emitted text (slangc's
                // WGSL backend cannot express @blend_src; see the tool's
                // header) — and get a naga validation step re-proving the
                // transform. The other families are runtime-validated by
                // the wgpu example gates.
                const raw_wgsl = slangcFamily(b, family, stage, &.{"SNAIL_TARGET_WGSL"}, &.{ "-target", "wgsl" }, family.name ++ "." ++ stage.short ++ ".wgsl");
                const is_dual_source_family = comptime std.mem.eql(u8, family.name, "text_subpixel") or
                    std.mem.eql(u8, family.name, "tt_hinted_text_subpixel") or
                    std.mem.eql(u8, family.name, "autohint_subpixel");
                const wgsl = if (is_dual_source_family) blk: {
                    const gen = b.addRunArtifact(wgsl_dual_entry_tool);
                    gen.addFileArg(raw_wgsl);
                    break :blk gen.addOutputFileArg("dual-" ++ family.name ++ "." ++ stage.short ++ ".wgsl");
                } else raw_wgsl;
                const wgsl_validation: ?*std.Build.Step = if (is_dual_source_family)
                    nagaValidation(b, wgsl)
                else
                    null;
                appendEntryValidated(b, list, .wgsl, "wgsl/" ++ family.name ++ "." ++ stage.short ++ ".wgsl", wgsl, wgsl_validation);

                // D3D11 HLSL (SM 5.0) — direct target (see hlsl_args).
                const hlsl = slangcFamily(b, family, stage, &.{"SNAIL_TARGET_D3D11"}, hlsl_args, family.name ++ "." ++ stage.short ++ ".hlsl");
                appendEntry(b, list, .hlsl, "hlsl/" ++ family.name ++ "." ++ stage.short ++ ".hlsl", hlsl);

                // Metal MSL — direct target (see msl_args). Portable
                // builds validate the text contract; macOS CI also
                // runtime-compiles every artifact and render-gates the
                // scene-used families.
                const msl = slangcFamily(b, family, stage, &.{"SNAIL_TARGET_METAL"}, msl_args, family.name ++ "." ++ stage.short ++ ".metal");
                appendEntry(b, list, .msl, "msl/" ++ family.name ++ "." ++ stage.short ++ ".metal", msl);
            }

            // GL family — Slang's direct GLSL backend preserves the authored
            // helper/control-flow shape. A mechanical post-pass selects the
            // 330-core / 300-es surface dialect and location-keyed varying
            // names; there is no SPIR-V translation in this path.
            inline for (.{ "glsl330", "gles300" }) |out_dir| {
                const es = comptime std.mem.eql(u8, out_dir, "gles300");
                const skip_dialect = family.no_gles and es;
                if (!skip_dialect) {
                    const gl_args: []const []const u8 = if (family.gl_o0 and !es)
                        &.{ "-target", "glsl", "-profile", "glsl_330", "-O0", "-line-directive-mode", "none", "-warnings-disable", "41012" }
                    else
                        &.{ "-target", "glsl", "-profile", "glsl_330", "-line-directive-mode", "none", "-warnings-disable", "41012" };
                    const defines: []const []const u8 = if (es)
                        &.{ "SNAIL_TARGET_GL", "SNAIL_TARGET_GLES" }
                    else
                        &.{"SNAIL_TARGET_GL"};
                    const raw = slangcFamily(
                        b,
                        family,
                        stage,
                        defines,
                        gl_args,
                        "direct-" ++ out_dir ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl",
                    );
                    const patch = b.addRunArtifact(direct_glsl_patch_tool);
                    patch.addArgs(&.{ out_dir, stage.short });
                    patch.addFileArg(raw);
                    const glsl = patch.addOutputFileArg(out_dir ++ "-" ++ family.name ++ "." ++ stage.short ++ ".glsl");
                    appendEntry(b, list, if (es) .gles300 else .glsl330, out_dir ++ "/" ++ family.name ++ "." ++ stage.short ++ ".glsl", glsl);
                }
            }
        }
    }

    return .{
        .library = library.toOwnedSlice(b.allocator) catch @panic("OOM"),
        .game = game.toOwnedSlice(b.allocator) catch @panic("OOM"),
        .reflection_zig = reflection_zig,
    };
}

pub const GeneratedModule = struct {
    module: *std.Build.Module,
    /// The laid-out module root file — also usable as the root of a test
    /// compilation (the accessor file carries the artifact-contract tests).
    root: std.Build.LazyPath,
};

/// Build a published generated-shaders module scoped to `targets`: the
/// in-tree accessor source (src/snail/shader/generated_root.zig) copied
/// next to a `generated/` tree holding ONLY the requested targets'
/// artifacts — the paths its `@embedFile`s expect — inside one WriteFiles
/// output directory per module. Consumers depend on (and therefore run)
/// exactly the requested targets' generation steps: Zig analyzes
/// declarations lazily, so accessors for absent targets are never
/// analyzed as long as the consumer doesn't reference them (calling one
/// fails to compile with the missing generated/<target>/ path in the
/// message). The accessor API is identical across every scope; in-repo
/// consumers keep importing whichever module they are wired to as
/// `snail_shaders`. build.zig publishes the aggregate `snail-shaders`
/// (all targets — the artifact-contract test root and the public
/// dependency surface) plus the per-target scopes.
pub fn createGeneratedModule(b: *std.Build, name: []const u8, artifacts: Artifacts, targets: []const Target) GeneratedModule {
    return createGeneratedModuleOpts(b, name, artifacts, targets, false);
}

/// `run_validations` wires the artifacts' validation steps (naga over the
/// subpixel WGSL) into the module — used by the aggregate/test module so
/// `zig build test` re-proves the fragile artifacts; consumer scopes skip
/// it and carry no naga requirement.
pub fn createGeneratedModuleOpts(b: *std.Build, name: []const u8, artifacts: Artifacts, targets: []const Target, run_validations: bool) GeneratedModule {
    const wf = b.addWriteFiles();
    const root = wf.addCopyFile(b.path("src/snail/shader/generated_root.zig"), "root.zig");
    // The parameter-ABI module rides along in every scope (tiny, and the
    // reflection compiles are cheap slangc runs).
    _ = wf.addCopyFile(artifacts.reflection_zig, "reflection.zig");
    for (artifacts.library) |e| {
        if (std.mem.indexOfScalar(Target, targets, e.target) == null) continue;
        _ = wf.addCopyFile(e.file, b.pathJoin(&.{ "generated", e.sub_path }));
        if (run_validations) if (e.validate) |v| wf.step.dependOn(v);
    }
    return .{
        .module = b.addModule(name, .{ .root_source_file = root }),
        .root = root,
    };
}

/// Optional debugging step: materialize the generated artifacts into
/// zig-out/shaders/ (library families) and zig-out/shaders/game/ (the
/// game's material family) for inspection. Never writes into src/ —
/// consumers embed straight from the build cache via `snail-shaders`.
pub fn addGenShadersStep(b: *std.Build, artifacts: Artifacts) void {
    const step = b.step("gen-shaders", "Materialize the generated shader artifacts into zig-out/shaders for inspection (needs slangc + naga)");
    step.dependOn(&b.addInstallFile(artifacts.reflection_zig, "shaders/reflection.zig").step);
    for (artifacts.library) |e| {
        step.dependOn(&b.addInstallFile(e.file, b.pathJoin(&.{ "shaders", e.sub_path })).step);
        if (e.validate) |v| step.dependOn(v);
    }
    for (artifacts.game) |e| step.dependOn(&b.addInstallFile(e.file, b.pathJoin(&.{ "shaders", "game", e.sub_path })).step);
}
