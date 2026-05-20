const std = @import("std");
const pkg_config = @import("build/pkg_config.zig");
const vulkan_shaders = @import("build/vulkan_shaders.zig");

const version = "0.11.0";

pub const ModuleOptions = struct {
    enable_profiling: bool = false,
    enable_gl33: bool = true,
    enable_gl44: bool = true,
    enable_gles30: bool = true,
    enable_vulkan: bool = true,
    enable_cpu: bool = true,
    enable_harfbuzz: bool = true,
};

fn createBuildOptionsModule(b: *std.Build, options: ModuleOptions) *std.Build.Module {
    const opts = b.addOptions();
    opts.addOption(bool, "enable_profiling", options.enable_profiling);
    opts.addOption(bool, "enable_gl33", options.enable_gl33);
    opts.addOption(bool, "enable_gl44", options.enable_gl44);
    opts.addOption(bool, "enable_gles30", options.enable_gles30);
    opts.addOption(bool, "enable_vulkan", options.enable_vulkan);
    opts.addOption(bool, "enable_cpu", options.enable_cpu);
    opts.addOption(bool, "enable_harfbuzz", options.enable_harfbuzz);
    return opts.createModule();
}

fn configureCoreModule(
    mod: *std.Build.Module,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
) void {
    mod.addImport("build_options", build_options_mod);
    if (options.enable_gl33 or options.enable_gl44) mod.linkSystemLibrary("OpenGL", .{});
    if (options.enable_gles30) mod.linkSystemLibrary("GLESv2", .{});
    mod.addImport("vulkan_shaders", vk_shaders);
    if (options.enable_vulkan) mod.linkSystemLibrary("vulkan", .{});
    if (options.enable_harfbuzz) mod.linkSystemLibrary("harfbuzz", .{});
}

fn configureDemoModule(
    mod: *std.Build.Module,
    b: *std.Build,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, build_options_mod, options, vk_shaders);
    mod.linkSystemLibrary("wayland-client", .{});
    if (options.enable_gl33 or options.enable_gl44) {
        mod.linkSystemLibrary("wayland-egl", .{});
        mod.linkSystemLibrary("EGL", .{});
    }
    mod.addIncludePath(b.path("src/demo/platform"));
    mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
}

fn configureEglOffscreenModule(
    mod: *std.Build.Module,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, build_options_mod, options, vk_shaders);
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
        "--suppressions=valgrind.supp",
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
    options: ModuleOptions,
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
    configureCoreModule(mod, build_options_mod, options, vk_shaders);
    return mod;
}

fn createSnailModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(mod, build_options_mod, options, vk_shaders);
    return mod;
}

/// For use as a dependency: returns a module with only the core snail library.
/// Defaults to GL 3.3 + GL 4.4 + GLES30 + Vulkan + CPU + HarfBuzz; use moduleWithOptions to trim backend support.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return moduleWithOptions(b, target, optimize, .{});
}

pub fn moduleWithOptions(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module_options: ModuleOptions,
) *std.Build.Module {
    return createSnailModule(
        b,
        target,
        optimize,
        createBuildOptionsModule(b, module_options),
        module_options,
        vulkan_shaders.createModule(b, module_options.enable_vulkan),
    );
}

const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core_options: ModuleOptions,
    enable_c_api: bool,
    enable_c_api_shared: bool,
    enable_c_api_static: bool,
};

const CApiArtifacts = struct {
    generated_header: std.Build.LazyPath,
    generated_mod: *std.Build.Module,
    generate_step: *std.Build.Step,
};

fn parseBuildConfig(b: *std.Build) BuildConfig {
    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_gl33 = b.option(bool, "gl33", "Enable GL 3.3 backend") orelse true;
    const enable_gl44 = b.option(bool, "gl44", "Enable GL 4.4 backend") orelse true;
    const enable_gles30 = b.option(bool, "gles30", "Enable OpenGL ES 3.0 backend") orelse true;
    const enable_cpu = b.option(bool, "cpu-renderer", "Enable CPU renderer backend") orelse true;
    const enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan backend") orelse true;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse true;
    const enable_c_api = b.option(bool, "c-api", "Build the C API libraries") orelse true;
    const c_api_shared_option = b.option(bool, "c-api-shared", "Build the C API shared library");
    const c_api_static_option = b.option(bool, "c-api-static", "Build the C API static library");
    const core_options = ModuleOptions{
        .enable_profiling = enable_profiling,
        .enable_gl33 = enable_gl33,
        .enable_gl44 = enable_gl44,
        .enable_gles30 = enable_gles30,
        .enable_vulkan = enable_vulkan,
        .enable_cpu = enable_cpu,
        .enable_harfbuzz = enable_harfbuzz,
    };

    const enable_c_api_shared = c_api_shared_option orelse enable_c_api;
    const enable_c_api_static = c_api_static_option orelse enable_c_api;

    if (!core_options.enable_gl33 and !core_options.enable_gl44 and !core_options.enable_gles30 and !core_options.enable_vulkan and !core_options.enable_cpu) {
        @panic("at least one renderer backend must be enabled");
    }
    if (!enable_c_api and ((c_api_shared_option orelse false) or (c_api_static_option orelse false))) {
        @panic("-Dc-api=false conflicts with -Dc-api-shared=true or -Dc-api-static=true");
    }
    if (enable_c_api and !enable_c_api_shared and !enable_c_api_static) {
        @panic("-Dc-api=true requires at least one of -Dc-api-shared=true or -Dc-api-static=true");
    }

    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .core_options = core_options,
        .enable_c_api = enable_c_api,
        .enable_c_api_shared = enable_c_api_shared,
        .enable_c_api_static = enable_c_api_static,
    };
}

fn addCApiArtifacts(b: *std.Build) CApiArtifacts {
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
    const c_api_header_check_mod = b.createModule(.{
        .root_source_file = b.path("tools/check_c_api_headers.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const c_api_header_check = b.addExecutable(.{
        .name = "snail-check-c-api-headers",
        .root_module = c_api_header_check_mod,
    });

    const gen_c_api_run = b.addRunArtifact(c_api_generator);
    gen_c_api_run.addArg("--emit");
    const generated_c_api_header = gen_c_api_run.addOutputFileArg("snail_generated.h");
    const generated_c_api_zig = gen_c_api_run.addOutputFileArg("c_api_generated.zig");
    const c_api_generated_mod = b.createModule(.{
        .root_source_file = generated_c_api_zig,
    });

    const generate_c_api_step = b.step("generate-c-api", "Generate C API build artifacts into the Zig cache");
    generate_c_api_step.dependOn(&gen_c_api_run.step);

    const check_c_api_step = b.step("check-c-api", "Check generated C API artifacts and public declarations");
    check_c_api_step.dependOn(&gen_c_api_run.step);
    const check_c_api_headers_run = b.addRunArtifact(c_api_header_check);
    check_c_api_step.dependOn(&check_c_api_headers_run.step);

    return .{
        .generated_header = generated_c_api_header,
        .generated_mod = c_api_generated_mod,
        .generate_step = generate_c_api_step,
    };
}

fn installCApi(
    b: *std.Build,
    config: BuildConfig,
    options_mod: *std.Build.Module,
    vk_shaders_mod: *std.Build.Module,
    c_api: CApiArtifacts,
) void {
    if (!config.enable_c_api) return;

    b.getInstallStep().dependOn(c_api.generate_step);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/snail/c_api.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
    });
    configureCoreModule(lib_module, options_mod, config.core_options, vk_shaders_mod);
    lib_module.addImport("c_api_generated", c_api.generated_mod);

    if (config.enable_c_api_shared) {
        const shared_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .dynamic });
        b.installArtifact(shared_lib);
    }

    if (config.enable_c_api_static) {
        const static_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .static });
        b.installArtifact(static_lib);
    }

    b.installFile("include/snail.h", "include/snail.h");
    b.getInstallStep().dependOn(&b.addInstallFile(c_api.generated_header, "include/snail_generated.h").step);
    if (config.core_options.enable_gl33) {
        b.installFile("include/snail_gl33.h", "include/snail_gl33.h");
    }
    if (config.core_options.enable_gl44) {
        b.installFile("include/snail_gl44.h", "include/snail_gl44.h");
    }
    if (config.core_options.enable_gles30) b.installFile("include/snail_gles30.h", "include/snail_gles30.h");
    if (config.core_options.enable_vulkan) b.installFile("include/snail_vulkan.h", "include/snail_vulkan.h");
    if (config.core_options.enable_cpu) b.installFile("include/snail_cpu.h", "include/snail_cpu.h");

    const generated_pkg_config = b.addWriteFiles().add(
        "snail.pc",
        pkg_config.render(b, version, config.core_options.enable_gl33 or config.core_options.enable_gl44, config.core_options.enable_gles30, config.core_options.enable_vulkan, config.core_options.enable_harfbuzz),
    );
    b.getInstallStep().dependOn(&b.addInstallFile(generated_pkg_config, "lib/pkgconfig/snail.pc").step);
}

fn addSnailModule(
    b: *std.Build,
    config: BuildConfig,
    options_mod: *std.Build.Module,
    vk_shaders_mod: *std.Build.Module,
) *std.Build.Module {
    const snail_mod = b.addModule("snail", .{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
    });
    configureCoreModule(snail_mod, options_mod, config.core_options, vk_shaders_mod);
    return snail_mod;
}

const ProjectModules = struct {
    assets: *std.Build.Module,
    support: *std.Build.Module,
    options: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    snail: *std.Build.Module,
};

const ReleaseToolModules = struct {
    snail: *std.Build.Module,
    support: *std.Build.Module,
    offscreen_gl: *std.Build.Module,
    vulkan_platform: ?*std.Build.Module,
};

fn addInteractiveDemoSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const demo_module = b.createModule(.{
        .root_source_file = b.path("src/demo/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "support", .module = modules.support },
        },
    });
    configureDemoModule(demo_module, b, modules.options, config.core_options, modules.vk_shaders);

    const exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_module });
    const install_demo = b.addInstallArtifact(exe, .{});

    const install_demo_step = b.step("install-demo", "Install the interactive demo executable");
    install_demo_step.dependOn(&install_demo.step);
    const demo_step = b.step("demo", "Install the interactive demo executable");
    demo_step.dependOn(&install_demo.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the interactive demo");
    run_step.dependOn(&run_cmd.step);
    const run_demo_step = b.step("run-demo", "Run the interactive demo");
    run_demo_step.dependOn(&run_cmd.step);
}

fn addGameDemoSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const game_demo_options = ModuleOptions{
        .enable_profiling = config.core_options.enable_profiling,
        .enable_gl33 = true,
        .enable_gl44 = true,
        .enable_gles30 = false,
        .enable_vulkan = false,
        .enable_cpu = false,
        .enable_harfbuzz = config.core_options.enable_harfbuzz,
    };
    const game_demo_options_mod = createBuildOptionsModule(b, game_demo_options);
    const game_snail_mod = createSnailModule(b, config.target, config.optimize, game_demo_options_mod, game_demo_options, modules.vk_shaders);

    const game_demo_module = b.createModule(.{
        .root_source_file = b.path("src/demo/game.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = game_snail_mod },
            .{ .name = "support", .module = modules.support },
        },
    });
    configureDemoModule(game_demo_module, b, game_demo_options_mod, game_demo_options, modules.vk_shaders);

    const game_demo_exe = b.addExecutable(.{ .name = "snail-game-demo", .root_module = game_demo_module });
    const install_game_demo = b.addInstallArtifact(game_demo_exe, .{});

    const install_game_demo_step = b.step("install-game-demo", "Install the GL game-style demo executable");
    install_game_demo_step.dependOn(&install_game_demo.step);

    const run_game_demo = b.addRunArtifact(game_demo_exe);
    if (b.args) |args| run_game_demo.addArgs(args);
    const run_game_demo_step = b.step("run-game-demo", "Run the GL game-style demo");
    run_game_demo_step.dependOn(&run_game_demo.step);
}

fn addDemoSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    addInteractiveDemoSteps(b, config, modules);
    addGameDemoSteps(b, config, modules);
}

fn addTestSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    c_api: CApiArtifacts,
) void {
    const test_module = createCoreTestModule(
        b,
        b.path("src/snail/root.zig"),
        config.target,
        config.optimize,
        modules.assets,
        modules.options,
        config.core_options,
        modules.vk_shaders,
        null,
    );

    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(c_api.generate_step);
    test_step.dependOn(&run_unit_tests.step);

    const test_valgrind_step = b.step("test-valgrind", "Run unit tests under Valgrind");
    const valgrind_test_module = createCoreTestModule(
        b,
        b.path("src/snail/root.zig"),
        config.target,
        config.optimize,
        modules.assets,
        modules.options,
        config.core_options,
        modules.vk_shaders,
        true,
    );
    const valgrind_unit_tests = b.addTest(.{ .root_module = valgrind_test_module });
    configureValgrindTest(valgrind_unit_tests);
    const run_valgrind_unit_tests = b.addRunArtifact(valgrind_unit_tests);
    test_valgrind_step.dependOn(&run_valgrind_unit_tests.step);

    if (config.enable_c_api) {
        const c_api_test_module = createCoreTestModule(
            b,
            b.path("src/snail/c_api.zig"),
            config.target,
            config.optimize,
            modules.assets,
            modules.options,
            config.core_options,
            modules.vk_shaders,
            null,
        );
        c_api_test_module.addImport("c_api_generated", c_api.generated_mod);
        const c_api_tests = b.addTest(.{ .root_module = c_api_test_module });
        const run_c_api_tests = b.addRunArtifact(c_api_tests);
        test_step.dependOn(&run_c_api_tests.step);

        const valgrind_c_api_test_module = createCoreTestModule(
            b,
            b.path("src/snail/c_api.zig"),
            config.target,
            config.optimize,
            modules.assets,
            modules.options,
            config.core_options,
            modules.vk_shaders,
            true,
        );
        valgrind_c_api_test_module.addImport("c_api_generated", c_api.generated_mod);
        const valgrind_c_api_tests = b.addTest(.{ .root_module = valgrind_c_api_test_module });
        configureValgrindTest(valgrind_c_api_tests);
        const run_valgrind_c_api_tests = b.addRunArtifact(valgrind_c_api_tests);
        test_valgrind_step.dependOn(&run_valgrind_c_api_tests.step);
    }
}

fn createReleaseToolModules(
    b: *std.Build,
    config: BuildConfig,
    release_support_mod: *std.Build.Module,
    modules: ProjectModules,
) ReleaseToolModules {
    const release_snail_mod = createSnailModule(b, config.target, .ReleaseFast, modules.options, config.core_options, modules.vk_shaders);
    const release_offscreen_gl_mod = createDemoOffscreenGlModule(b, config.target, .ReleaseFast, modules.options);
    const release_vulkan_platform_mod = if (config.core_options.enable_vulkan) createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod) else null;
    return .{
        .snail = release_snail_mod,
        .support = release_support_mod,
        .offscreen_gl = release_offscreen_gl_mod,
        .vulkan_platform = release_vulkan_platform_mod,
    };
}

fn addBenchStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release: ReleaseToolModules,
) void {
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/tools/bench.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release.snail },
            .{ .name = "demo_platform_offscreen_gl", .module = release.offscreen_gl },
            .{ .name = "demo_platform_vulkan", .module = release.vulkan_platform orelse release.offscreen_gl },
            .{ .name = "support", .module = release.support },
        },
    });
    configureEglOffscreenModule(bench_module, modules.options, config.core_options, modules.vk_shaders);
    bench_module.linkSystemLibrary("freetype2", .{});

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_module });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("run-bench", "Run consolidated benchmarks");
    bench_step.dependOn(&run_bench.step);
    const bench_alias = b.step("bench", "Run consolidated benchmarks");
    bench_alias.dependOn(&run_bench.step);
}

fn addProfileCpuTextStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release: ReleaseToolModules,
) void {
    const profile_text_module = b.createModule(.{
        .root_source_file = b.path("src/tools/profile_cpu_text.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .omit_frame_pointer = false,
        .link_libc = true, // HarfBuzz cImport needs libc headers
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release.snail },
        },
    });
    configureCoreModule(profile_text_module, modules.options, config.core_options, modules.vk_shaders);
    const profile_text_exe = b.addExecutable(.{ .name = "snail-profile-cpu-text", .root_module = profile_text_module });
    const install_profile_text = b.addInstallArtifact(profile_text_exe, .{});
    const profile_text_step = b.step("install-profile-cpu-text", "Install CPU-text profile executable");
    profile_text_step.dependOn(&install_profile_text.step);
}

fn addProfileTtHintStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release: ReleaseToolModules,
) void {
    const profile_tt_module = b.createModule(.{
        .root_source_file = b.path("src/tools/profile_tt_hint.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .omit_frame_pointer = false,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release.snail },
        },
    });
    configureCoreModule(profile_tt_module, modules.options, config.core_options, modules.vk_shaders);
    const profile_tt_exe = b.addExecutable(.{ .name = "snail-profile-tt-hint", .root_module = profile_tt_module });
    const install_profile_tt = b.addInstallArtifact(profile_tt_exe, .{});
    const profile_tt_step = b.step("install-profile-tt-hint", "Install TrueType hint profile executable");
    profile_tt_step.dependOn(&install_profile_tt.step);
}

fn addScreenshotStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release: ReleaseToolModules,
) void {
    const screenshot_module = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release.snail },
            .{ .name = "support", .module = release.support },
        },
    });
    configureEglOffscreenModule(screenshot_module, modules.options, config.core_options, modules.vk_shaders);

    const screenshot_exe = b.addExecutable(.{ .name = "snail-screenshot", .root_module = screenshot_module });
    const run_screenshot = b.addRunArtifact(screenshot_exe);
    const screenshot_step = b.step("run-screenshot", "Render the demo scene offscreen and write zig-out/demo-screenshot.tga");
    screenshot_step.dependOn(&run_screenshot.step);
}

fn addAlgorithmScreenshotsStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release: ReleaseToolModules,
) void {
    const algorithm_screenshots_module = b.createModule(.{
        .root_source_file = b.path("src/demo/algorithm_screenshots.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release.snail },
            .{ .name = "support", .module = release.support },
        },
    });
    configureEglOffscreenModule(algorithm_screenshots_module, modules.options, config.core_options, modules.vk_shaders);

    const algorithm_screenshots_exe = b.addExecutable(.{ .name = "snail-algorithm-screenshots", .root_module = algorithm_screenshots_module });
    const run_algorithm_screenshots = b.addRunArtifact(algorithm_screenshots_exe);
    const algorithm_screenshots_step = b.step("run-algorithm-screenshots", "Render README algorithm diagrams offscreen and write zig-out/algorithm-*.png");
    algorithm_screenshots_step.dependOn(&run_algorithm_screenshots.step);
}

fn addBackendCompareStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const compare_options = ModuleOptions{
        .enable_profiling = false,
        .enable_gl33 = true,
        .enable_gl44 = true,
        .enable_gles30 = false,
        .enable_vulkan = config.core_options.enable_vulkan,
        .enable_cpu = true,
        .enable_harfbuzz = config.core_options.enable_harfbuzz,
    };
    const compare_options_mod = createBuildOptionsModule(b, compare_options);
    const backend_compare_snail_mod = createSnailModule(b, config.target, config.optimize, compare_options_mod, compare_options, modules.vk_shaders);
    const compare_offscreen_gl_mod = createDemoOffscreenGlModule(b, config.target, config.optimize, compare_options_mod);
    const compare_vulkan_platform_mod = if (compare_options.enable_vulkan) createDemoVulkanPlatformModule(b, config.target, config.optimize, compare_options_mod, backend_compare_snail_mod) else null;

    const backend_compare_module = b.createModule(.{
        .root_source_file = b.path("src/tools/backend_compare.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = backend_compare_snail_mod },
            .{ .name = "demo_platform_offscreen_gl", .module = compare_offscreen_gl_mod },
            .{ .name = "demo_platform_vulkan", .module = compare_vulkan_platform_mod orelse compare_offscreen_gl_mod },
            .{ .name = "support", .module = modules.support },
        },
    });
    configureEglOffscreenModule(backend_compare_module, compare_options_mod, compare_options, modules.vk_shaders);

    const backend_compare_exe = b.addExecutable(.{ .name = "snail-backend-compare", .root_module = backend_compare_module });
    const run_backend_compare = b.addRunArtifact(backend_compare_exe);
    const backend_compare_step = b.step("run-backend-compare", "Compare CPU/GL/Vulkan backend pixels offscreen");
    backend_compare_step.dependOn(&run_backend_compare.step);
}

fn addToolSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
    release_support_mod: *std.Build.Module,
) void {
    const release = createReleaseToolModules(b, config, release_support_mod, modules);
    addBenchStep(b, config, modules, release);
    addProfileCpuTextStep(b, config, modules, release);
    addProfileTtHintStep(b, config, modules, release);
    addScreenshotStep(b, config, modules, release);
    addAlgorithmScreenshotsStep(b, config, modules, release);
    addBackendCompareStep(b, config, modules);
}

pub fn build(b: *std.Build) void {
    const config = parseBuildConfig(b);
    const options_mod = createBuildOptionsModule(b, config.core_options);
    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const support_mod = createSupportModule(b, config.target, config.optimize);
    const release_support_mod = createSupportModule(b, config.target, .ReleaseFast);
    const vk_shaders_mod = vulkan_shaders.createModule(b, config.core_options.enable_vulkan);
    const c_api = addCApiArtifacts(b);

    installCApi(b, config, options_mod, vk_shaders_mod, c_api);
    const snail_mod = addSnailModule(b, config, options_mod, vk_shaders_mod);
    const modules = ProjectModules{
        .assets = assets_mod,
        .support = support_mod,
        .options = options_mod,
        .vk_shaders = vk_shaders_mod,
        .snail = snail_mod,
    };

    addDemoSteps(b, config, modules);
    addTestSteps(b, config, modules, c_api);
    addToolSteps(b, config, modules, release_support_mod);
}
