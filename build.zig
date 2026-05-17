const std = @import("std");
const pkg_config = @import("build/pkg_config.zig");
const vulkan_shaders = @import("build/vulkan_shaders.zig");

const version = "0.9.0";

pub const ModuleOptions = struct {
    enable_profiling: bool = false,
    enable_opengl: bool = true,
    enable_vulkan: bool = true,
    enable_cpu: bool = true,
    enable_harfbuzz: bool = true,
    force_gl33: bool = false,
};

fn configureCoreModule(
    mod: *std.Build.Module,
    build_options_mod: *std.Build.Module,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) void {
    mod.addImport("build_options", build_options_mod);
    if (opengl) mod.linkSystemLibrary("OpenGL", .{});
    mod.addImport("vulkan_shaders", vk_shaders);
    if (vulkan) mod.linkSystemLibrary("vulkan", .{});
    if (harfbuzz) mod.linkSystemLibrary("harfbuzz", .{});
}

fn configureDemoModule(
    mod: *std.Build.Module,
    b: *std.Build,
    build_options_mod: *std.Build.Module,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, build_options_mod, opengl, vulkan, harfbuzz, vk_shaders);
    mod.linkSystemLibrary("wayland-client", .{});
    if (opengl) {
        mod.linkSystemLibrary("wayland-egl", .{});
        mod.linkSystemLibrary("EGL", .{});
    }
    mod.addIncludePath(b.path("src/demo/platform"));
    mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
}

fn configureEglOffscreenModule(
    mod: *std.Build.Module,
    build_options_mod: *std.Build.Module,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, build_options_mod, opengl, vulkan, harfbuzz, vk_shaders);
    mod.linkSystemLibrary("EGL", .{});
}

fn configureValgrindTest(test_exe: *std.Build.Step.Compile) void {
    test_exe.setExecCmd(&.{
        "valgrind",
        "--quiet",
        "--leak-check=full",
        "--show-leak-kinds=definite,possible",
        "--errors-for-leak-kinds=definite,possible",
        "--track-origins=yes",
        "--num-callers=32",
        "--error-exitcode=99",
        null,
    });
}

fn createDemoOffscreenGlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/platform/offscreen_gl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "build_options", .module = build_options_mod }},
    });
    mod.linkSystemLibrary("EGL", .{});
    return mod;
}

fn createDemoVulkanPlatformModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/platform/vulkan.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
            .{ .name = "snail", .module = snail_mod },
        },
    });
    mod.linkSystemLibrary("vulkan", .{});
    mod.linkSystemLibrary("wayland-client", .{});
    return mod;
}

fn createSupportModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/support/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
}

fn createCoreTestModule(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    assets_mod: *std.Build.Module,
    build_options_mod: *std.Build.Module,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
    strip: ?bool,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(mod, build_options_mod, opengl, vulkan, harfbuzz, vk_shaders);
    return mod;
}

fn createSnailModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(mod, build_options_mod, opengl, vulkan, harfbuzz, vk_shaders);
    return mod;
}

/// For use as a dependency: returns a module with only the core snail library.
/// Defaults to OpenGL + Vulkan + CPU + HarfBuzz; use moduleWithOptions to trim backend support.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return moduleWithOptions(b, target, optimize, .{});
}

pub fn moduleWithOptions(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module_options: ModuleOptions,
) *std.Build.Module {
    if (module_options.force_gl33 and !module_options.enable_opengl) {
        @panic("ModuleOptions.force_gl33 requires ModuleOptions.enable_opengl");
    }

    const opts = b.addOptions();
    opts.addOption(bool, "enable_profiling", module_options.enable_profiling);
    opts.addOption(bool, "enable_opengl", module_options.enable_opengl);
    opts.addOption(bool, "enable_vulkan", module_options.enable_vulkan);
    opts.addOption(bool, "enable_cpu", module_options.enable_cpu);
    opts.addOption(bool, "enable_harfbuzz", module_options.enable_harfbuzz);
    opts.addOption(bool, "force_gl33", module_options.force_gl33);

    return createSnailModule(
        b,
        target,
        optimize,
        opts.createModule(),
        module_options.enable_opengl,
        module_options.enable_vulkan,
        module_options.enable_harfbuzz,
        vulkan_shaders.createModule(b, module_options.enable_vulkan),
    );
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_opengl = b.option(bool, "opengl", "Enable OpenGL backend") orelse true;
    const enable_cpu = b.option(bool, "cpu-renderer", "Enable CPU renderer backend") orelse true;
    const enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan backend") orelse true;
    const force_gl33 = b.option(bool, "gl33", "Force OpenGL 3.3 context where OpenGL is used") orelse false;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse true;
    const enable_c_api = b.option(bool, "c-api", "Build the C API libraries") orelse true;
    const c_api_shared_option = b.option(bool, "c-api-shared", "Build the C API shared library");
    const c_api_static_option = b.option(bool, "c-api-static", "Build the C API static library");
    const enable_c_api_shared = c_api_shared_option orelse enable_c_api;
    const enable_c_api_static = c_api_static_option orelse enable_c_api;
    if (!enable_opengl and !enable_vulkan and !enable_cpu) {
        @panic("at least one renderer backend must be enabled");
    }
    if (force_gl33 and !enable_opengl) {
        @panic("-Dgl33=true requires -Dopengl=true");
    }
    if (!enable_c_api and ((c_api_shared_option orelse false) or (c_api_static_option orelse false))) {
        @panic("-Dc-api=false conflicts with -Dc-api-shared=true or -Dc-api-static=true");
    }
    if (enable_c_api and !enable_c_api_shared and !enable_c_api_static) {
        @panic("-Dc-api=true requires at least one of -Dc-api-shared=true or -Dc-api-static=true");
    }

    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", enable_profiling);
    options.addOption(bool, "enable_opengl", enable_opengl);
    options.addOption(bool, "enable_vulkan", enable_vulkan);
    options.addOption(bool, "enable_cpu", enable_cpu);
    options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    options.addOption(bool, "force_gl33", force_gl33);
    const options_mod = options.createModule();

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const support_mod = createSupportModule(b, target, optimize);
    const release_support_mod = createSupportModule(b, target, .ReleaseFast);

    // ── SPIR-V shader compilation (only when Vulkan enabled) ──
    const vk_shaders_mod = vulkan_shaders.createModule(b, enable_vulkan);

    // ── C API generated source/header ──
    const c_api_manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/snail/c_api/manifest.zig"),
    });
    const c_api_generator_mod = b.createModule(.{
        .root_source_file = b.path("tools/gen_c_api.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{.{ .name = "manifest", .module = c_api_manifest_mod }},
    });
    const c_api_generator = b.addExecutable(.{
        .name = "snail-gen-c-api",
        .root_module = c_api_generator_mod,
    });

    const gen_c_api_run = b.addRunArtifact(c_api_generator);
    gen_c_api_run.addArg("--emit");
    const generated_c_api_header = gen_c_api_run.addOutputFileArg("snail_generated.h");
    const generated_c_api_zig = gen_c_api_run.addOutputFileArg("c_api_generated.zig");
    const c_api_generated_mod = b.createModule(.{
        .root_source_file = generated_c_api_zig,
    });

    const gen_c_api_step = b.step("gen-c-api", "Generate C API build artifacts into the Zig cache");
    gen_c_api_step.dependOn(&gen_c_api_run.step);

    const check_c_api_step = b.step("check-c-api", "Validate the C API generator by emitting cache artifacts");
    check_c_api_step.dependOn(&gen_c_api_run.step);

    // ── C API libraries ──
    if (enable_c_api) {
        b.getInstallStep().dependOn(gen_c_api_step);

        const lib_module = b.createModule(.{
            .root_source_file = b.path("src/snail/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        configureCoreModule(lib_module, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
        lib_module.addImport("c_api_generated", c_api_generated_mod);

        if (enable_c_api_shared) {
            const shared_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .dynamic });
            b.installArtifact(shared_lib);
        }

        if (enable_c_api_static) {
            const static_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .static });
            b.installArtifact(static_lib);
        }

        b.installFile("include/snail.h", "include/snail.h");
        b.getInstallStep().dependOn(&b.addInstallFile(generated_c_api_header, "include/snail_generated.h").step);
        if (enable_opengl) b.installFile("include/snail_gl.h", "include/snail_gl.h");
        if (enable_vulkan) b.installFile("include/snail_vulkan.h", "include/snail_vulkan.h");
        if (enable_cpu) b.installFile("include/snail_cpu.h", "include/snail_cpu.h");

        const generated_pkg_config = b.addWriteFiles().add(
            "snail.pc",
            pkg_config.render(b, version, enable_opengl, enable_vulkan, enable_harfbuzz),
        );
        b.getInstallStep().dependOn(&b.addInstallFile(generated_pkg_config, "lib/pkgconfig/snail.pc").step);
    }

    // ── Zig module (for downstream zig package consumers) ──
    const snail_mod = b.addModule("snail", .{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(snail_mod, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    // ── Demo executable ──
    const demo_module = b.createModule(.{
        .root_source_file = b.path("src/demo/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "support", .module = support_mod },
        },
    });
    configureDemoModule(demo_module, b, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    const exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_module });
    const install_demo = b.addInstallArtifact(exe, .{});

    const demo_step = b.step("demo", "Build the snail demo");
    demo_step.dependOn(&install_demo.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the snail demo");
    run_step.dependOn(&run_cmd.step);

    // ── Game-style OpenGL demo ──
    const game_demo_options = b.addOptions();
    game_demo_options.addOption(bool, "enable_profiling", enable_profiling);
    game_demo_options.addOption(bool, "enable_opengl", true);
    game_demo_options.addOption(bool, "enable_vulkan", false);
    game_demo_options.addOption(bool, "enable_cpu", false);
    game_demo_options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    game_demo_options.addOption(bool, "force_gl33", false);
    const game_demo_options_mod = game_demo_options.createModule();
    const game_snail_mod = createSnailModule(b, target, optimize, game_demo_options_mod, true, false, enable_harfbuzz, vk_shaders_mod);

    const game_demo_module = b.createModule(.{
        .root_source_file = b.path("src/demo/game.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = game_snail_mod },
            .{ .name = "support", .module = support_mod },
        },
    });
    configureDemoModule(game_demo_module, b, game_demo_options_mod, true, false, enable_harfbuzz, vk_shaders_mod);

    const game_demo_exe = b.addExecutable(.{ .name = "snail-game-demo", .root_module = game_demo_module });
    const install_game_demo = b.addInstallArtifact(game_demo_exe, .{});

    const game_demo_step = b.step("game-demo", "Build the OpenGL game-style demo");
    game_demo_step.dependOn(&install_game_demo.step);

    const run_game_demo = b.addRunArtifact(game_demo_exe);
    if (b.args) |args| run_game_demo.addArgs(args);
    const run_game_demo_step = b.step("run-game-demo", "Run the OpenGL game-style demo");
    run_game_demo_step.dependOn(&run_game_demo.step);

    // ── Tests ──
    const test_module = createCoreTestModule(
        b,
        b.path("src/snail/root.zig"),
        target,
        optimize,
        assets_mod,
        options_mod,
        enable_opengl,
        enable_vulkan,
        enable_harfbuzz,
        vk_shaders_mod,
        null,
    );

    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(gen_c_api_step);
    test_step.dependOn(&run_unit_tests.step);

    const valgrind_test_step = b.step("valgrind-test", "Run unit tests under Valgrind");
    const valgrind_test_module = createCoreTestModule(
        b,
        b.path("src/snail/root.zig"),
        target,
        optimize,
        assets_mod,
        options_mod,
        enable_opengl,
        enable_vulkan,
        enable_harfbuzz,
        vk_shaders_mod,
        true,
    );
    const valgrind_unit_tests = b.addTest(.{ .root_module = valgrind_test_module });
    configureValgrindTest(valgrind_unit_tests);
    const run_valgrind_unit_tests = b.addRunArtifact(valgrind_unit_tests);
    valgrind_test_step.dependOn(&run_valgrind_unit_tests.step);

    if (enable_c_api) {
        const c_api_test_module = createCoreTestModule(
            b,
            b.path("src/snail/c_api.zig"),
            target,
            optimize,
            assets_mod,
            options_mod,
            enable_opengl,
            enable_vulkan,
            enable_harfbuzz,
            vk_shaders_mod,
            null,
        );
        c_api_test_module.addImport("c_api_generated", c_api_generated_mod);
        const c_api_tests = b.addTest(.{ .root_module = c_api_test_module });
        const run_c_api_tests = b.addRunArtifact(c_api_tests);
        test_step.dependOn(&run_c_api_tests.step);

        const valgrind_c_api_test_module = createCoreTestModule(
            b,
            b.path("src/snail/c_api.zig"),
            target,
            optimize,
            assets_mod,
            options_mod,
            enable_opengl,
            enable_vulkan,
            enable_harfbuzz,
            vk_shaders_mod,
            true,
        );
        valgrind_c_api_test_module.addImport("c_api_generated", c_api_generated_mod);
        const valgrind_c_api_tests = b.addTest(.{ .root_module = valgrind_c_api_test_module });
        configureValgrindTest(valgrind_c_api_tests);
        const run_valgrind_c_api_tests = b.addRunArtifact(valgrind_c_api_tests);
        valgrind_test_step.dependOn(&run_valgrind_c_api_tests.step);
    }

    // ── Benchmarks ──
    const release_snail_mod = createSnailModule(b, target, .ReleaseFast, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    const release_offscreen_gl_mod = createDemoOffscreenGlModule(b, target, .ReleaseFast, options_mod);
    const release_vulkan_platform_mod = if (enable_vulkan) createDemoVulkanPlatformModule(b, target, .ReleaseFast, options_mod, release_snail_mod) else null;
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/tools/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "demo_platform_offscreen_gl", .module = release_offscreen_gl_mod },
            .{ .name = "demo_platform_vulkan", .module = release_vulkan_platform_mod orelse release_offscreen_gl_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(bench_module, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    bench_module.linkSystemLibrary("freetype2", .{});

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_module });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run consolidated benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ── CPU text profile target (for use under perf record) ──
    const profile_text_module = b.createModule(.{
        .root_source_file = b.path("src/tools/profile_cpu_text.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .omit_frame_pointer = false,
        .link_libc = true, // HarfBuzz cImport needs libc headers
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = release_snail_mod },
        },
    });
    configureCoreModule(profile_text_module, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    const profile_text_exe = b.addExecutable(.{ .name = "snail-profile-cpu-text", .root_module = profile_text_module });
    const install_profile_text = b.addInstallArtifact(profile_text_exe, .{});
    const profile_text_step = b.step("profile-cpu-text", "Build CPU-text profile target (run zig-out/bin/snail-profile-cpu-text [iters] [serial|threaded])");
    profile_text_step.dependOn(&install_profile_text.step);

    // ── Headless demo screenshot ──
    const screenshot_module = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(screenshot_module, options_mod, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    const screenshot_exe = b.addExecutable(.{ .name = "snail-screenshot", .root_module = screenshot_module });
    const run_screenshot = b.addRunArtifact(screenshot_exe);
    const screenshot_step = b.step("screenshot", "Render the demo scene offscreen and write zig-out/demo-screenshot.tga");
    screenshot_step.dependOn(&run_screenshot.step);

    // ── Backend pixel comparison ──
    const compare_options = b.addOptions();
    compare_options.addOption(bool, "enable_profiling", false);
    compare_options.addOption(bool, "enable_opengl", true);
    compare_options.addOption(bool, "enable_vulkan", enable_vulkan);
    compare_options.addOption(bool, "enable_cpu", true);
    compare_options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    compare_options.addOption(bool, "force_gl33", false);
    const compare_options_mod = compare_options.createModule();
    const backend_compare_snail_mod = createSnailModule(b, target, optimize, compare_options_mod, true, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    const compare_offscreen_gl_mod = createDemoOffscreenGlModule(b, target, optimize, compare_options_mod);
    const compare_vulkan_platform_mod = if (enable_vulkan) createDemoVulkanPlatformModule(b, target, optimize, compare_options_mod, backend_compare_snail_mod) else null;

    const backend_compare_module = b.createModule(.{
        .root_source_file = b.path("src/tools/backend_compare.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "snail", .module = backend_compare_snail_mod },
            .{ .name = "demo_platform_offscreen_gl", .module = compare_offscreen_gl_mod },
            .{ .name = "demo_platform_vulkan", .module = compare_vulkan_platform_mod orelse compare_offscreen_gl_mod },
            .{ .name = "support", .module = support_mod },
        },
    });
    configureEglOffscreenModule(backend_compare_module, compare_options_mod, true, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    const backend_compare_exe = b.addExecutable(.{ .name = "snail-backend-compare", .root_module = backend_compare_module });
    const run_backend_compare = b.addRunArtifact(backend_compare_exe);
    const backend_compare_step = b.step("backend-compare", "Compare CPU/OpenGL/Vulkan backend pixels offscreen");
    backend_compare_step.dependOn(&run_backend_compare.step);

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
