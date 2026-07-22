const std = @import("std");
const slang_shaders = @import("slang_shaders.zig");

fn appendBytes(dest: []u8, offset: *usize, bytes: []const u8) void {
    @memcpy(dest[offset.*..][0..bytes.len], bytes);
    offset.* += bytes.len;
}

pub fn assembledGlslSource(
    allocator: std.mem.Allocator,
    comptime wrapper_path: []const u8,
    comptime include_directive: []const u8,
    comptime source_paths: []const []const u8,
) []const u8 {
    const wrapper = @embedFile(wrapper_path);
    const include_idx = std.mem.indexOf(u8, wrapper, include_directive) orelse @panic("missing GLSL include directive");
    const prefix = wrapper[0..include_idx];
    const suffix = wrapper[include_idx + include_directive.len ..];
    var len = prefix.len + suffix.len;
    inline for (source_paths) |source_path| {
        len += @embedFile(source_path).len + 1;
    }

    const result = allocator.alloc(u8, len) catch @panic("out of memory assembling GLSL source");
    var offset: usize = 0;
    appendBytes(result, &offset, prefix);
    inline for (source_paths) |source_path| {
        appendBytes(result, &offset, @embedFile(source_path));
        appendBytes(result, &offset, "\n");
    }
    appendBytes(result, &offset, suffix);
    return result;
}

/// Common slangc invocation prefix for GLSL-ingestion SPIR-V compiles.
/// `-profile spirv_1_3` caps the binary at SPIR-V 1.3 — the demos create
/// Vulkan 1.1 devices and slangc's default (SPIR-V 1.5) trips
/// VUID-VkShaderModuleCreateInfo-pCode-08737. `-matrix-layout-row-major`
/// preserves GLSL matrix semantics: the flag names Slang's *logical*
/// convention, which maps inverted onto the SPIR-V decoration — row-major
/// here emits `ColMajor` + literal `M*v` codegen, matching how the CPU side
/// writes the push-constant `mvp` (GLSL column-major bytes). The default
/// (and `-matrix-layout-column-major`) emits `RowMajor`, silently transposing
/// every matrix. Warnings 41018 (out-param not
/// initialized on early `return false` — GLSL out-params are allowed to stay
/// unwritten) and 39001 (dual-source outputs sharing location 0, which is
/// exactly what `index = 1` is for) fire on valid GLSL; disable just those two.
pub fn slangcCommand(b: *std.Build, stage: []const u8) *std.Build.Step.Run {
    return b.addSystemCommand(&.{
        "slangc",                   "-lang",             "glsl",
        "-stage",                   stage,               "-entry",
        "main",                     "-profile",          "spirv_1_3",
        "-matrix-layout-row-major", "-warnings-disable", "39001,41018",
    });
}

pub fn compile(
    b: *std.Build,
    generated_shaders: *std.Build.Step.WriteFile,
    shader_dir: std.Build.LazyPath,
    shared_shader_dir: std.Build.LazyPath,
    comptime generated_source_path: []const u8,
    comptime wrapper_path: []const u8,
    comptime include_directive: []const u8,
    comptime source_paths: []const []const u8,
    stage: []const u8,
    output_name: []const u8,
    extra_args: []const []const u8,
) std.Build.LazyPath {
    const generated_source = generated_shaders.add(generated_source_path, assembledGlslSource(
        b.allocator,
        wrapper_path,
        include_directive,
        source_paths,
    ));

    const compile_step = slangcCommand(b, stage);
    for (extra_args) |arg| compile_step.addArg(arg);
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(shader_dir);
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(shared_shader_dir);
    compile_step.addFileArg(generated_source);
    compile_step.addArgs(&.{ "-target", "spirv", "-o" });
    return compile_step.addOutputFileArg(output_name);
}

/// Dependency-relative include directories for snail's reusable GLSL pieces.
/// A consumer constructs these with `snail_dependency.path(...)`; accepting
/// `LazyPath`s keeps the helper independent of the consumer's build root.
pub const IncludeDirs = struct {
    glsl: std.Build.LazyPath,
};

/// Compile a caller-authored GLSL shader to SPIR-V with snail's include dirs on
/// the slangc `-I` path. This is the build-time analog of the GL family's
/// runtime source injection: the caller `#include`s snail's shipped `.glsl`
/// (the coverage math + the Vulkan records interface) and compiles their own
/// combined material shader. `stage` is a slangc stage name (`vertex`,
/// `fragment`); `defines` carries any `-D` macros (e.g. the per-instance word
/// stride). Returns the compiled `.spv` LazyPath, suitable for
/// `module.addAnonymousImport`.
pub fn compileCallerShader(
    b: *std.Build,
    source: std.Build.LazyPath,
    stage: []const u8,
    output_name: []const u8,
    defines: []const []const u8,
    snail_include_dirs: IncludeDirs,
    extra_include_dirs: []const std.Build.LazyPath,
) std.Build.LazyPath {
    const compile_step = slangcCommand(b, stage);
    for (defines) |d| compile_step.addArg(d);
    for (extra_include_dirs) |dir| {
        compile_step.addArg("-I");
        compile_step.addDirectoryArg(dir);
    }
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(snail_include_dirs.glsl);
    compile_step.addFileArg(source);
    compile_step.addArgs(&.{ "-target", "spirv", "-o" });
    return compile_step.addOutputFileArg(output_name);
}

pub const ShaderSpec = struct {
    import_name: []const u8,
    generated_source_path: []const u8,
    wrapper_path: []const u8,
    include_directive: []const u8,
    source_paths: []const []const u8,
    stage: []const u8,
    output_name: []const u8,
    extra_args: []const []const u8 = &.{},
    /// slangc's GLSL frontend drops `layout(..., index = 1)` on fragment
    /// outputs; run the spv patch tool to restore the dual-source Index
    /// decoration the source declares (see build/spv_patch_dual_source.zig).
    patch_dual_source_index: bool = false,
};

const fragment_common_includes =
    "#include \"snail_render_abi.glsl\"\n" ++
    "#include \"snail_coverage_common.glsl\"\n" ++
    "#include \"snail_color_common.glsl\"\n";

pub const shader_specs = [_]ShaderSpec{
    .{
        .import_name = "snail.vert.spv",
        .generated_source_path = "vulkan-generated/snail.vert",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail.vert",
        .include_directive = "#include \"snail_vert_body.glsl\"",
        .source_paths = &.{"../src/snail/shader/glsl/snail_vert_body.glsl"},
        .stage = "vertex",
        .output_name = "snail.vert.spv",
    },
    .{
        .import_name = "snail_autohint.vert.spv",
        .generated_source_path = "vulkan-generated/snail_autohint.vert",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_autohint.vert",
        .include_directive = "#include \"snail_color_common.glsl\"\n" ++
            "#include \"snail_autohint_warp.glsl\"\n" ++
            "#include \"snail_vert_body.glsl\"\n" ++
            "#include \"snail_autohint_vert_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_autohint_warp.glsl",
            "../src/snail/shader/glsl/snail_vert_body.glsl",
            "../src/snail/shader/glsl/snail_autohint_vert_body.glsl",
        },
        .stage = "vertex",
        .output_name = "snail_autohint.vert.spv",
    },
    .{
        .import_name = "snail_text.frag.spv",
        .generated_source_path = "vulkan-generated/snail_text.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_text.frag",
        .include_directive = fragment_common_includes ++
            "#include \"snail_text_frag_body.glsl\"\n" ++
            "#include \"snail_text_main.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_text_frag_body.glsl",
            "../src/snail/shader/glsl/snail_text_main.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_text.frag.spv",
    },
    .{
        .import_name = "snail_colr.frag.spv",
        .generated_source_path = "vulkan-generated/snail_colr.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_colr.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_path_frag_body.glsl\"\n#include \"snail_colr_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_path_frag_body.glsl",
            "../src/snail/shader/glsl/snail_colr_frag_body.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_colr.frag.spv",
    },
    .{
        .import_name = "snail_path.frag.spv",
        .generated_source_path = "vulkan-generated/snail.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_path_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_path_frag_body.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_path.frag.spv",
    },
    .{
        .import_name = "snail_tt_hinted_text.frag.spv",
        .generated_source_path = "vulkan-generated/snail_tt_hinted_text.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_tt_hinted_text.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_text_frag_body.glsl\"\n#include \"snail_tt_hinted_text_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_text_frag_body.glsl",
            "../src/snail/shader/glsl/snail_tt_hinted_text_frag_body.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_tt_hinted_text.frag.spv",
    },
    .{
        .import_name = "snail_autohint.frag.spv",
        .generated_source_path = "vulkan-generated/snail_autohint.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_autohint.frag",
        .include_directive = fragment_common_includes ++
            "#include \"snail_text_frag_body.glsl\"\n" ++
            "#include \"snail_autohint_warp.glsl\"\n" ++
            "#include \"snail_autohint_fast_main.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_text_frag_body.glsl",
            "../src/snail/shader/glsl/snail_autohint_warp.glsl",
            "../src/snail/shader/glsl/snail_autohint_fast_main.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_autohint.frag.spv",
    },
    .{
        .import_name = "snail_text_subpixel_dual.frag.spv",
        .generated_source_path = "vulkan-generated/snail_text_subpixel.frag",
        .wrapper_path = "../src/demo/render/vulkan/glsl/snail_text_subpixel.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_text_subpixel_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/glsl/snail_render_abi.glsl",
            "../src/snail/shader/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/glsl/snail_color_common.glsl",
            "../src/snail/shader/glsl/snail_text_subpixel_body.glsl",
        },
        .stage = "fragment",
        .output_name = "snail_text_subpixel_dual.frag.spv",
        .extra_args = &.{"-DSNAIL_DUAL_SOURCE=1"},
        .patch_dual_source_index = true,
    },
};

/// Restore the `Index 1` decoration on the `frag_blend` dual-source output
/// that slangc's GLSL frontend drops (see ShaderSpec.patch_dual_source_index).
pub fn createDualSourcePatchTool(b: *std.Build) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "spv-patch-dual-source",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/spv_patch_dual_source.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
}

pub fn patchDualSourceIndex(
    b: *std.Build,
    patch_tool: *std.Build.Step.Compile,
    input: std.Build.LazyPath,
    output_name: []const u8,
) std.Build.LazyPath {
    const run = b.addRunArtifact(patch_tool);
    run.addFileArg(input);
    const patched = run.addOutputFileArg(output_name);
    // Vulkan needs only `frag_blend Index 1`; the explicit `frag_color Index 0`
    // is harmless there and required by naga when generating the WGSL catalog.
    run.addArgs(&.{ "frag_blend", "1", "frag_color", "0" });
    return patched;
}

pub fn createModule(b: *std.Build) *std.Build.Module {
    const shader_dir = b.path("src/demo/render/vulkan/glsl");
    // The reference wrappers live with the demo; reusable color/coverage pieces
    // live in the library include directory and stay independently includable.
    const shared_shader_dir = b.path("src/snail/shader/glsl");
    const generated_shaders = b.addWriteFiles();

    const patch_tool = createDualSourcePatchTool(b);

    var spv_outputs: [shader_specs.len]std.Build.LazyPath = undefined;
    inline for (shader_specs, 0..) |spec, i| {
        spv_outputs[i] = compile(
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
            spec.extra_args,
        );
        if (spec.patch_dual_source_index) {
            spv_outputs[i] = patchDualSourceIndex(b, patch_tool, spv_outputs[i], spec.output_name);
        }
    }

    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/render/vulkan/shaders.zig"),
    });
    inline for (shader_specs, 0..) |spec, i| {
        mod.addAnonymousImport(spec.import_name, .{ .root_source_file = spv_outputs[i] });
    }

    // Stage A of the Slang cutover: the regular-text pipeline compiles from
    // the native-Slang family source (src/snail/shader/slang/families/
    // text.slang) instead of the composed GLSL. Other families keep the
    // GLSL-ingestion path above. See build/slang_shaders.zig for flags.
    const native_text = slang_shaders.vulkanTextSpv(b);
    mod.addAnonymousImport("snail_text_native.vert.spv", .{ .root_source_file = native_text.vert });
    mod.addAnonymousImport("snail_text_native.frag.spv", .{ .root_source_file = native_text.frag });
    return mod;
}
