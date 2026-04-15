const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse false;
    const enable_vulkan = b.option(bool, "vulkan", "Use Vulkan backend instead of OpenGL") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", enable_profiling);
    options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    options.addOption(bool, "enable_vulkan", enable_vulkan);

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });

    // ── SPIR-V shader compilation (Vulkan) ──
    const vk_shaders_mod: ?*std.Build.Module = if (enable_vulkan) blk: {
        const compile_vert = b.addSystemCommand(&.{ "glslc", "-fshader-stage=vert", "shaders/slug.vert", "-o" });
        const vert_spv = compile_vert.addOutputFileArg("slug.vert.spv");

        const compile_frag = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag", "shaders/slug.frag", "-o" });
        const frag_spv = compile_frag.addOutputFileArg("slug.frag.spv");

        const compile_frag_sp = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag", "shaders/slug_subpixel.frag", "-o" });
        const frag_sp_spv = compile_frag_sp.addOutputFileArg("slug_subpixel.frag.spv");

        const mod = b.createModule(.{
            .root_source_file = b.path("src/render/vulkan_shaders.zig"),
        });
        mod.addAnonymousImport("slug.vert.spv", .{ .root_source_file = vert_spv });
        mod.addAnonymousImport("slug.frag.spv", .{ .root_source_file = frag_spv });
        mod.addAnonymousImport("slug_subpixel.frag.spv", .{ .root_source_file = frag_sp_spv });
        break :blk mod;
    } else null;

    // Helper: configure a module with common options and Vulkan support
    const configureModule = struct {
        fn f(mod: *std.Build.Module, opts: *std.Build.Step.Options, harfbuzz: bool, vulkan: bool, vk_shaders: ?*std.Build.Module) void {
            mod.addOptions("build_options", opts);
            mod.linkSystemLibrary("glfw3", .{});
            mod.linkSystemLibrary("gl", .{}); // GL pipeline is always compiled
            if (vulkan) {
                mod.linkSystemLibrary("vulkan", .{});
                if (vk_shaders) |shaders| mod.addImport("vulkan_shaders", shaders);
            }
            if (harfbuzz) mod.linkSystemLibrary("harfbuzz", .{});
        }
    }.f;

    // ── Shared library ──
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureModule(lib_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const shared_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .dynamic });
    b.installArtifact(shared_lib);

    const static_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .static });
    b.installArtifact(static_lib);

    // Install header
    b.installFile("include/snail.h", "include/snail.h");

    // ── Demo executable ──
    const demo_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureModule(demo_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_module });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the snail demo");
    run_step.dependOn(&run_cmd.step);

    // ── Tests ──
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureModule(test_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ── Benchmarks ──
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    bench_module.addOptions("build_options", options);

    // ── Comparative benchmark (vs FreeType) ──
    const bench_cmp_module = b.createModule(.{
        .root_source_file = b.path("src/bench_compare.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureModule(bench_cmp_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);
    bench_cmp_module.linkSystemLibrary("freetype2", .{});

    const bench_cmp_exe = b.addExecutable(.{ .name = "snail-bench-compare", .root_module = bench_cmp_module });
    b.installArtifact(bench_cmp_exe);
    const run_bench_cmp = b.addRunArtifact(bench_cmp_exe);
    run_bench_cmp.step.dependOn(b.getInstallStep());
    const bench_cmp_step = b.step("bench-compare", "Run comparative benchmark vs FreeType");
    bench_cmp_step.dependOn(&run_bench_cmp.step);

    // ── Headless benchmark (standardized cross-library comparison) ──
    const bench_hl_module = b.createModule(.{
        .root_source_file = b.path("src/bench_headless.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureModule(bench_hl_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const bench_hl_exe = b.addExecutable(.{ .name = "snail-bench-headless", .root_module = bench_hl_module });
    b.installArtifact(bench_hl_exe);
    const run_bench_hl = b.addRunArtifact(bench_hl_exe);
    run_bench_hl.step.dependOn(b.getInstallStep());
    const bench_hl_step = b.step("bench-headless", "Run headless rendering benchmark");
    bench_hl_step.dependOn(&run_bench_hl.step);

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_module });
    b.installArtifact(bench_exe);
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ── Benchmark suite (consolidated) ──
    const bench_suite_module = b.createModule(.{
        .root_source_file = b.path("src/bench_suite.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureModule(bench_suite_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);
    bench_suite_module.linkSystemLibrary("freetype2", .{});

    const bench_suite_exe = b.addExecutable(.{ .name = "snail-bench-suite", .root_module = bench_suite_module });
    b.installArtifact(bench_suite_exe);
    const run_bench_suite = b.addRunArtifact(bench_suite_exe);
    run_bench_suite.step.dependOn(b.getInstallStep());
    const bench_suite_step = b.step("bench-suite", "Run consolidated benchmark suite");
    bench_suite_step.dependOn(&run_bench_suite.step);

    // ── Valgrind ──
    const valgrind_step = b.step("valgrind", "Run tests under valgrind (memory checking)");
    const valgrind = b.addSystemCommand(&.{
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=definite,indirect",
        "--error-exitcode=1",
        "--track-origins=yes",
        "--suppressions=valgrind.supp",
    });
    valgrind.addArtifactArg(unit_tests);
    valgrind_step.dependOn(&valgrind.step);
}
