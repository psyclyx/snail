//! `gen-wgsl`: regenerate the checked-in WGSL shader catalog
//! (`src/snail/shader/wgsl/*.wgsl`) from the same composed per-family Vulkan
//! GLSL shaders the SPIR-V demo path compiles (build/vulkan_shaders.zig).
//!
//! slangc's own `-target wgsl` backend (v2026.5.2) cannot compile these
//! shaders: its GLSL front end miscompiles `texelFetch` on combined samplers
//! (the coordinate/lod arguments are replaced with swizzles of the sampler
//! itself) and renumbers stage IO locations per stage, breaking the
//! vertex↔fragment interface. The catalog therefore goes through SPIR-V:
//!
//!   1. slangc — same composed sources and flags as the Vulkan path
//!      (`-lang glsl -stage <s> -entry main -profile spirv_1_3`
//!      `-matrix-layout-row-major -warnings-disable 39001,41018`) plus
//!      `-DSNAIL_WGSL=1` (selects the WGSL-safe wrapper variants: no array
//!      varyings, no isnan/isinf) and `-emit-spirv-via-glsl`. The via-glsl
//!      backend is load-bearing: slang's *direct* SPIR-V backend lowers loop
//!      bodies into trivial `OpSwitch 0` selection constructs whose
//!      loop-break edges naga's structurizer drops — the resulting WGSL
//!      loops `continue` unconditionally and hang the GPU. glslang emits
//!      flag-based loop exits that naga translates faithfully. (Warning
//!      41012 additionally silenced: glslang upgrades the profile for
//!      samplerless texture functions.)
//!
//!      The dual-source subpixel family cannot use `-emit-spirv-via-glsl`
//!      in one step — slangc's GLSL backend drops the `index = 1` qualifier
//!      and glslang then rejects the duplicate `location = 0` — so it goes
//!      `slangc -target glsl` → build/glsl_patch_dual_source.zig (restore
//!      `index = 1`) → `glslangValidator -V`, then
//!      build/spv_patch_dual_source.zig adds the explicit `Index 0` on
//!      `frag_color` that naga requires alongside the blend output's
//!      `Index 1`.
//!   2. `spirv-opt --split-combined-image-sampler` — split combined image
//!      samplers into texture+sampler pairs (WGSL has no combined samplers).
//!   3. build/spv_wgsl_prep.zig — move the split samplers to descriptor set
//!      1, turn the push-constant block into a uniform buffer at set 2,
//!      binding 0 (WebGPU has neither push constants nor two resources per
//!      `@group`/`@binding`), and retype the dead layer-component extract of
//!      arrayed `textureSize` queries that naga cannot resolve.
//!   4. `naga` (wgpu-utils) — SPIR-V → WGSL, preserving locations, bindings,
//!      and the dual-source `@blend_src` attributes.
//!
//! The normal build embeds the checked-in artifacts and needs none of these
//! tools; `zig build gen-wgsl` (inside `nix-shell`, which provides slangc,
//! spirv-tools, glslang, and naga) rewrites them in the source tree.

const std = @import("std");
const vulkan_shaders = @import("vulkan_shaders.zig");

/// Checked-in artifact name for each Vulkan shader spec, keyed by the spec's
/// SPIR-V import name so the two catalogs cannot drift silently.
const wgsl_output_names = [vulkan_shaders.shader_specs.len]struct {
    import_name: []const u8,
    wgsl_name: []const u8,
}{
    .{ .import_name = "snail.vert.spv", .wgsl_name = "text.vert.wgsl" },
    .{ .import_name = "snail_autohint.vert.spv", .wgsl_name = "autohint.vert.wgsl" },
    .{ .import_name = "snail_text.frag.spv", .wgsl_name = "text.frag.wgsl" },
    .{ .import_name = "snail_colr.frag.spv", .wgsl_name = "colr.frag.wgsl" },
    .{ .import_name = "snail_path.frag.spv", .wgsl_name = "path.frag.wgsl" },
    .{ .import_name = "snail_tt_hinted_text.frag.spv", .wgsl_name = "tt_hinted_text.frag.wgsl" },
    .{ .import_name = "snail_autohint.frag.spv", .wgsl_name = "autohint.frag.wgsl" },
    .{ .import_name = "snail_text_subpixel_dual.frag.spv", .wgsl_name = "subpixel.frag.wgsl" },
};

fn addToolExe(b: *std.Build, name: []const u8, root: []const u8) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
}

pub fn addGenWgslStep(b: *std.Build) void {
    const shader_dir = b.path("src/demo/render/vulkan/glsl");
    const shared_shader_dir = b.path("src/snail/shader/glsl");
    const generated_shaders = b.addWriteFiles();
    const spv_patch_tool = vulkan_shaders.createDualSourcePatchTool(b);
    const glsl_patch_tool = addToolExe(b, "glsl-patch-dual-source", "build/glsl_patch_dual_source.zig");
    const prep_tool = addToolExe(b, "spv-wgsl-prep", "build/spv_wgsl_prep.zig");

    const update = b.addUpdateSourceFiles();
    inline for (vulkan_shaders.shader_specs, wgsl_output_names) |spec, out| {
        comptime std.debug.assert(std.mem.eql(u8, spec.import_name, out.import_name));

        var spv: std.Build.LazyPath = undefined;
        if (spec.patch_dual_source_index) {
            // Dual-source leg: slangc GLSL text → restore `index = 1` →
            // glslang → restore `Index 0`.
            const generated_source = generated_shaders.add(spec.generated_source_path, vulkan_shaders.assembledGlslSource(
                b.allocator,
                spec.wrapper_path,
                spec.include_directive,
                spec.source_paths,
            ));
            const to_glsl = b.addSystemCommand(&.{
                "slangc",                   "-lang",             "glsl",
                "-stage",                   spec.stage,          "-entry",
                "main",                     "-matrix-layout-row-major", "-warnings-disable",
                "39001,41018,41012",        "-DSNAIL_WGSL=1",
            });
            for (spec.extra_args) |arg| to_glsl.addArg(arg);
            to_glsl.addArg("-I");
            to_glsl.addDirectoryArg(shader_dir);
            to_glsl.addArg("-I");
            to_glsl.addDirectoryArg(shared_shader_dir);
            to_glsl.addFileArg(generated_source);
            to_glsl.addArgs(&.{ "-target", "glsl", "-o" });
            const glsl_text = to_glsl.addOutputFileArg(b.fmt("gen-{s}.frag", .{out.wgsl_name}));

            const patch_glsl = b.addRunArtifact(glsl_patch_tool);
            patch_glsl.addFileArg(glsl_text);
            const patched_glsl = patch_glsl.addOutputFileArg(b.fmt("patched-{s}.frag", .{out.wgsl_name}));

            const glslang = b.addSystemCommand(&.{ "glslangValidator", "-V" });
            glslang.addFileArg(patched_glsl);
            glslang.addArg("-o");
            const raw_spv = glslang.addOutputFileArg(spec.output_name);

            const patch_spv = b.addRunArtifact(spv_patch_tool);
            patch_spv.addFileArg(raw_spv);
            spv = patch_spv.addOutputFileArg(spec.output_name);
            patch_spv.addArgs(&.{ "frag_color", "0" });
        } else {
            const extra_args: []const []const u8 = spec.extra_args ++ &[_][]const u8{
                "-DSNAIL_WGSL=1",
                "-emit-spirv-via-glsl",
                "-warnings-disable",
                "41012",
            };
            spv = vulkan_shaders.compile(
                b,
                generated_shaders,
                shader_dir,
                shared_shader_dir,
                spec.generated_source_path,
                spec.wrapper_path,
                spec.include_directive,
                spec.source_paths,
                spec.stage,
                spec.output_name,
                extra_args,
            );
        }

        const split = b.addSystemCommand(&.{ "spirv-opt", "--split-combined-image-sampler" });
        split.addFileArg(spv);
        split.addArg("-o");
        const split_spv = split.addOutputFileArg(b.fmt("split-{s}", .{spec.output_name}));

        const prep = b.addRunArtifact(prep_tool);
        prep.addFileArg(split_spv);
        const prep_spv = prep.addOutputFileArg(b.fmt("prep-{s}", .{spec.output_name}));

        const naga = b.addSystemCommand(&.{ "naga", "--input-kind", "spv" });
        naga.addFileArg(prep_spv);
        const wgsl = naga.addOutputFileArg(out.wgsl_name);

        update.addCopyFileToSource(wgsl, "src/snail/shader/wgsl/" ++ out.wgsl_name);
    }

    const step = b.step("gen-wgsl", "Regenerate the checked-in WGSL shader catalog in src/snail/shader/wgsl (needs slangc, glslang, spirv-opt, naga)");
    step.dependOn(&update.step);
}
