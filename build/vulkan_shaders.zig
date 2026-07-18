const std = @import("std");

fn appendBytes(dest: []u8, offset: *usize, bytes: []const u8) void {
    @memcpy(dest[offset.*..][0..bytes.len], bytes);
    offset.* += bytes.len;
}

fn assembledGlslSource(
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

fn compile(
    b: *std.Build,
    generated_shaders: *std.Build.Step.WriteFile,
    shader_dir: std.Build.LazyPath,
    shared_shader_dir: std.Build.LazyPath,
    comptime generated_source_path: []const u8,
    comptime wrapper_path: []const u8,
    comptime include_directive: []const u8,
    comptime source_paths: []const []const u8,
    stage_arg: []const u8,
    output_name: []const u8,
    extra_args: []const []const u8,
) std.Build.LazyPath {
    const generated_source = generated_shaders.add(generated_source_path, assembledGlslSource(
        b.allocator,
        wrapper_path,
        include_directive,
        source_paths,
    ));

    const compile_step = b.addSystemCommand(&.{ "glslc", stage_arg });
    for (extra_args) |arg| compile_step.addArg(arg);
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(shader_dir);
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(shared_shader_dir);
    compile_step.addFileArg(generated_source);
    compile_step.addArg("-o");
    return compile_step.addOutputFileArg(output_name);
}

/// Dependency-relative include directories for snail's reusable GLSL pieces.
/// A consumer constructs these with `snail_dependency.path(...)`; accepting
/// `LazyPath`s keeps the helper independent of the consumer's build root.
pub const IncludeDirs = struct {
    shared: std.Build.LazyPath,
    vulkan: std.Build.LazyPath,
};

/// Compile a caller-authored GLSL shader to SPIR-V with snail's include dirs on
/// the glslc `-I` path. This is the build-time analog of the GL family's
/// runtime source injection: the caller `#include`s snail's shipped `.glsl`
/// (the coverage math + the Vulkan records interface) and compiles their own
/// combined material shader. `defines` carries any `-D` macros (e.g. the
/// per-instance word stride). Returns the compiled `.spv` LazyPath, suitable
/// for `module.addAnonymousImport`.
pub fn compileCallerShader(
    b: *std.Build,
    source: std.Build.LazyPath,
    stage_arg: []const u8,
    output_name: []const u8,
    defines: []const []const u8,
    snail_include_dirs: IncludeDirs,
    extra_include_dirs: []const std.Build.LazyPath,
) std.Build.LazyPath {
    const compile_step = b.addSystemCommand(&.{ "glslc", stage_arg });
    for (defines) |d| compile_step.addArg(d);
    for (extra_include_dirs) |dir| {
        compile_step.addArg("-I");
        compile_step.addDirectoryArg(dir);
    }
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(snail_include_dirs.vulkan);
    compile_step.addArg("-I");
    compile_step.addDirectoryArg(snail_include_dirs.shared);
    compile_step.addFileArg(source);
    compile_step.addArg("-o");
    return compile_step.addOutputFileArg(output_name);
}

const ShaderSpec = struct {
    import_name: []const u8,
    generated_source_path: []const u8,
    wrapper_path: []const u8,
    include_directive: []const u8,
    source_paths: []const []const u8,
    stage_arg: []const u8,
    output_name: []const u8,
    extra_args: []const []const u8 = &.{},
};

const fragment_common_includes =
    "#include \"snail_render_abi.glsl\"\n" ++
    "#include \"snail_coverage_common.glsl\"\n" ++
    "#include \"snail_color_common.glsl\"\n";

const shader_specs = [_]ShaderSpec{
    .{
        .import_name = "snail.vert.spv",
        .generated_source_path = "vulkan-generated/snail.vert",
        .wrapper_path = "../src/demo/vulkan_glsl/snail.vert",
        .include_directive = "#include \"snail_vert_body.glsl\"",
        .source_paths = &.{"../src/snail/shader/gl/glsl/snail_vert_body.glsl"},
        .stage_arg = "-fshader-stage=vert",
        .output_name = "snail.vert.spv",
    },
    .{
        .import_name = "snail_text.frag.spv",
        .generated_source_path = "vulkan-generated/snail_text.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail_text.frag",
        .include_directive = fragment_common_includes ++
            "#include \"snail_text_frag_body.glsl\"\n" ++
            "#include \"snail_text_main.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_text_frag_body.glsl",
            "../src/snail/shader/gl/glsl/snail_text_main.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_text.frag.spv",
    },
    .{
        .import_name = "snail_colr.frag.spv",
        .generated_source_path = "vulkan-generated/snail_colr.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail_colr.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_colr_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_colr_frag_body.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_colr.frag.spv",
    },
    .{
        .import_name = "snail_path.frag.spv",
        .generated_source_path = "vulkan-generated/snail.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_path_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_path_frag_body.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_path.frag.spv",
    },
    .{
        .import_name = "snail_hinted_text.frag.spv",
        .generated_source_path = "vulkan-generated/snail_hinted_text.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail_hinted_text.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_hinted_text_frag_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_hinted_text_frag_body.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_hinted_text.frag.spv",
    },
    .{
        .import_name = "snail_autohint.frag.spv",
        .generated_source_path = "vulkan-generated/snail_autohint.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail_autohint.frag",
        .include_directive = fragment_common_includes ++
            "#include \"snail_text_frag_body.glsl\"\n" ++
            "#include \"snail_autohint_warp.glsl\"\n" ++
            "#include \"snail_autohint_main.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_text_frag_body.glsl",
            "../src/snail/shader/gl/glsl/snail_autohint_warp.glsl",
            "../src/snail/shader/gl/glsl/snail_autohint_main.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_autohint.frag.spv",
    },
    .{
        .import_name = "snail_text_subpixel_dual.frag.spv",
        .generated_source_path = "vulkan-generated/snail_text_subpixel.frag",
        .wrapper_path = "../src/demo/vulkan_glsl/snail_text_subpixel.frag",
        .include_directive = fragment_common_includes ++ "#include \"snail_text_subpixel_body.glsl\"",
        .source_paths = &.{
            "../src/snail/shader/gl/glsl/snail_render_abi.glsl",
            "../src/snail/shader/gl/glsl/snail_coverage_common.glsl",
            "../src/snail/shader/gl/glsl/snail_color_common.glsl",
            "../src/snail/shader/gl/glsl/snail_text_subpixel_body.glsl",
        },
        .stage_arg = "-fshader-stage=frag",
        .output_name = "snail_text_subpixel_dual.frag.spv",
        .extra_args = &.{"-DSNAIL_DUAL_SOURCE=1"},
    },
};

pub fn createModule(b: *std.Build, enable_vulkan: bool) *std.Build.Module {
    if (!enable_vulkan) {
        return b.createModule(.{
            .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
        });
    }

    const shader_dir = b.path("src/demo/vulkan_glsl");
    // The reference wrappers live with the demo; reusable color/coverage pieces
    // live in the library include directory and stay independently includable.
    const shared_shader_dir = b.path("src/snail/shader/gl/glsl");
    const generated_shaders = b.addWriteFiles();

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
            spec.stage_arg,
            spec.output_name,
            spec.extra_args,
        );
    }

    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/embed_vulkan_shaders.zig"),
    });
    inline for (shader_specs, 0..) |spec, i| {
        mod.addAnonymousImport(spec.import_name, .{ .root_source_file = spv_outputs[i] });
    }
    return mod;
}
