const std = @import("std");

fn configureCoreModule(
    mod: *std.Build.Module,
    opts: *std.Build.Step.Options,
    harfbuzz: bool,
    vulkan: bool,
    vk_shaders: *std.Build.Module,
) void {
    mod.addOptions("build_options", opts);
    mod.linkSystemLibrary("OpenGL", .{});
    mod.addImport("vulkan_shaders", vk_shaders);
    if (vulkan) mod.linkSystemLibrary("vulkan", .{});
    if (harfbuzz) mod.linkSystemLibrary("harfbuzz", .{});
}

fn configureDemoModule(
    mod: *std.Build.Module,
    b: *std.Build,
    opts: *std.Build.Step.Options,
    harfbuzz: bool,
    vulkan: bool,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, opts, harfbuzz, vulkan, vk_shaders);
    mod.linkSystemLibrary("wayland-client", .{});
    if (!vulkan) {
        mod.linkSystemLibrary("wayland-egl", .{});
        mod.linkSystemLibrary("EGL", .{});
    }
    mod.addIncludePath(b.path("src/render"));
    mod.addCSourceFile(.{ .file = b.path("src/render/xdg-shell-client-protocol.c") });
}

fn configureEglOffscreenModule(
    mod: *std.Build.Module,
    opts: *std.Build.Step.Options,
    harfbuzz: bool,
    vulkan: bool,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, opts, harfbuzz, vulkan, vk_shaders);
    mod.linkSystemLibrary("EGL", .{});
}

/// For use as a dependency: returns a module with only the core snail library.
/// No demo windowing, no Vulkan — the consumer must provide a GL 3.3+ context.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", false);
    options.addOption(bool, "enable_harfbuzz", true);
    options.addOption(bool, "enable_vulkan", false);
    options.addOption(bool, "force_gl33", true);

    // Stub vulkan_shaders module (never used when enable_vulkan=false)
    const vk_stub = b.createModule(.{
        .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(mod, options, true, false, vk_stub);
    return mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse true;
    const enable_vulkan = b.option(bool, "vulkan", "Use Vulkan backend for the demo") orelse false;
    const force_gl33 = b.option(bool, "gl33", "Force OpenGL 3.3 core profile (skip 4.4 attempt)") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", enable_profiling);
    options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    options.addOption(bool, "enable_vulkan", enable_vulkan);
    options.addOption(bool, "force_gl33", force_gl33);

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });

    // ── SPIR-V shader compilation (only when Vulkan enabled) ──
    const vk_shaders_mod: *std.Build.Module = if (enable_vulkan) blk: {
        const compile_vert = b.addSystemCommand(&.{ "glslc", "-fshader-stage=vert" });
        compile_vert.addFileArg(b.path("shaders/snail.vert"));
        compile_vert.addArg("-o");
        const vert_spv = compile_vert.addOutputFileArg("snail.vert.spv");

        const compile_frag = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_frag.addFileArg(b.path("shaders/snail.frag"));
        compile_frag.addArg("-o");
        const frag_spv = compile_frag.addOutputFileArg("snail.frag.spv");

        const compile_frag_text_sp = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_frag_text_sp.addFileArg(b.path("shaders/snail_text_subpixel.frag"));
        compile_frag_text_sp.addArg("-o");
        const frag_text_sp_spv = compile_frag_text_sp.addOutputFileArg("snail_text_subpixel.frag.spv");

        const compile_frag_text_sp_dual = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag", "-DSNAIL_DUAL_SOURCE=1" });
        compile_frag_text_sp_dual.addFileArg(b.path("shaders/snail_text_subpixel.frag"));
        compile_frag_text_sp_dual.addArg("-o");
        const frag_text_sp_dual_spv = compile_frag_text_sp_dual.addOutputFileArg("snail_text_subpixel_dual.frag.spv");

        const compile_sprite_vert = b.addSystemCommand(&.{ "glslc", "-fshader-stage=vert" });
        compile_sprite_vert.addFileArg(b.path("shaders/sprite.vert"));
        compile_sprite_vert.addArg("-o");
        const sprite_vert_spv = compile_sprite_vert.addOutputFileArg("sprite.vert.spv");

        const compile_sprite_frag = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_sprite_frag.addFileArg(b.path("shaders/sprite.frag"));
        compile_sprite_frag.addArg("-o");
        const sprite_frag_spv = compile_sprite_frag.addOutputFileArg("sprite.frag.spv");

        const mod = b.createModule(.{
            .root_source_file = b.path("src/render/vulkan_shaders.zig"),
        });
        mod.addAnonymousImport("snail.vert.spv", .{ .root_source_file = vert_spv });
        mod.addAnonymousImport("snail.frag.spv", .{ .root_source_file = frag_spv });
        mod.addAnonymousImport("snail_text_subpixel.frag.spv", .{ .root_source_file = frag_text_sp_spv });
        mod.addAnonymousImport("snail_text_subpixel_dual.frag.spv", .{ .root_source_file = frag_text_sp_dual_spv });
        mod.addAnonymousImport("sprite.vert.spv", .{ .root_source_file = sprite_vert_spv });
        mod.addAnonymousImport("sprite.frag.spv", .{ .root_source_file = sprite_frag_spv });
        break :blk mod;
    } else b.createModule(.{
        .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
    });

    // ── Shared library ──
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(lib_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

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
    configureDemoModule(demo_module, b, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_module });
    const install_demo = b.addInstallArtifact(exe, .{});

    const demo_step = b.step("demo", "Build the snail demo");
    demo_step.dependOn(&install_demo.step);

    const run_cmd = b.addRunArtifact(exe);
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
    configureCoreModule(test_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ── Extra module tests (cpu_renderer, etc.) ──
    const snail_mod = b.createModule(.{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(snail_mod, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const extra_test_module = b.createModule(.{
        .root_source_file = b.path("src/extra/cpu_renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = snail_mod },
        },
    });
    const extra_tests = b.addTest(.{ .root_module = extra_test_module });
    const run_extra_tests = b.addRunArtifact(extra_tests);
    test_step.dependOn(&run_extra_tests.step);

    // ── Benchmarks ──
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(bench_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    // ── Comparative benchmark (vs FreeType) ──
    const bench_cmp_module = b.createModule(.{
        .root_source_file = b.path("src/bench_compare.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(bench_cmp_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);
    bench_cmp_module.linkSystemLibrary("freetype2", .{});

    const bench_cmp_exe = b.addExecutable(.{ .name = "snail-bench-compare", .root_module = bench_cmp_module });
    const run_bench_cmp = b.addRunArtifact(bench_cmp_exe);
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
    configureEglOffscreenModule(bench_hl_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const bench_hl_exe = b.addExecutable(.{ .name = "snail-bench-headless", .root_module = bench_hl_module });
    const run_bench_hl = b.addRunArtifact(bench_hl_exe);
    const bench_hl_step = b.step("bench-headless", "Run headless rendering benchmark");
    bench_hl_step.dependOn(&run_bench_hl.step);

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_module });
    const run_bench = b.addRunArtifact(bench_exe);
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
    configureEglOffscreenModule(bench_suite_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);
    bench_suite_module.linkSystemLibrary("freetype2", .{});

    const bench_suite_exe = b.addExecutable(.{ .name = "snail-bench-suite", .root_module = bench_suite_module });
    const run_bench_suite = b.addRunArtifact(bench_suite_exe);
    const bench_suite_step = b.step("bench-suite", "Run consolidated benchmark suite");
    bench_suite_step.dependOn(&run_bench_suite.step);

    // ── Headless demo screenshot ──
    const screenshot_module = b.createModule(.{
        .root_source_file = b.path("src/screenshot_demo.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureEglOffscreenModule(screenshot_module, options, enable_harfbuzz, enable_vulkan, vk_shaders_mod);

    const screenshot_exe = b.addExecutable(.{ .name = "snail-screenshot", .root_module = screenshot_module });
    const run_screenshot = b.addRunArtifact(screenshot_exe);
    const screenshot_step = b.step("screenshot", "Render the demo scene offscreen and write zig-out/demo-screenshot.tga");
    screenshot_step.dependOn(&run_screenshot.step);

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
