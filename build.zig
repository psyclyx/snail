const std = @import("std");
const pkg_config = @import("build/pkg_config.zig");
const vulkan_shaders = @import("build/vulkan_shaders.zig");

const version = "0.12.1";

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
};

fn parseBuildConfig(b: *std.Build) BuildConfig {
    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_gl33 = b.option(bool, "gl33", "Enable GL 3.3 backend") orelse true;
    const enable_gl44 = b.option(bool, "gl44", "Enable GL 4.4 backend") orelse true;
    const enable_gles30 = b.option(bool, "gles30", "Enable OpenGL ES 3.0 backend") orelse true;
    const enable_cpu = b.option(bool, "cpu-renderer", "Enable CPU renderer backend") orelse true;
    const enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan backend") orelse true;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse true;
    const core_options = ModuleOptions{
        .enable_profiling = enable_profiling,
        .enable_gl33 = enable_gl33,
        .enable_gl44 = enable_gl44,
        .enable_gles30 = enable_gles30,
        .enable_vulkan = enable_vulkan,
        .enable_cpu = enable_cpu,
        .enable_harfbuzz = enable_harfbuzz,
    };

    if (!core_options.enable_gl33 and !core_options.enable_gl44 and !core_options.enable_gles30 and !core_options.enable_vulkan and !core_options.enable_cpu) {
        @panic("at least one renderer backend must be enabled");
    }

    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .core_options = core_options,
    };
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

fn addTestSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
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
}

fn addScreenshotSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const release_snail_mod = createSnailModule(b, config.target, .ReleaseFast, modules.options, config.core_options, modules.vk_shaders);
    const release_support_mod = createSupportModule(b, config.target, .ReleaseFast);

    // CPU screenshot.
    const screenshot_cpu_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot_new.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const screenshot_cpu_exe = b.addExecutable(.{ .name = "snail-screenshot-new", .root_module = screenshot_cpu_mod });
    const run_screenshot_cpu = b.addRunArtifact(screenshot_cpu_exe);
    const screenshot_cpu_step = b.step("run-screenshot-new", "Render the demo through the CPU backend and write zig-out/demo-screenshot-new.tga");
    screenshot_cpu_step.dependOn(&run_screenshot_cpu.step);

    // GL screenshot.
    const screenshot_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot_new_gl.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(screenshot_gl_mod, modules.options, config.core_options, modules.vk_shaders);
    const screenshot_gl_exe = b.addExecutable(.{ .name = "snail-screenshot-new-gl", .root_module = screenshot_gl_mod });
    const run_screenshot_gl = b.addRunArtifact(screenshot_gl_exe);
    const screenshot_gl_step = b.step("run-screenshot-new-gl", "Render the demo through the GL backend and write zig-out/demo-screenshot-new-gl.tga");
    screenshot_gl_step.dependOn(&run_screenshot_gl.step);

    // GLES screenshot.
    const screenshot_gles30_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot_new_gles30.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(screenshot_gles30_mod, modules.options, config.core_options, modules.vk_shaders);
    const screenshot_gles30_exe = b.addExecutable(.{ .name = "snail-screenshot-new-gles30", .root_module = screenshot_gles30_mod });
    const run_screenshot_gles30 = b.addRunArtifact(screenshot_gles30_exe);
    const screenshot_gles30_step = b.step("run-screenshot-new-gles30", "Render the demo through the GLES30 backend and write zig-out/demo-screenshot-new-gles30.tga");
    screenshot_gles30_step.dependOn(&run_screenshot_gles30.step);

    // Vulkan screenshot.
    if (config.core_options.enable_vulkan) {
        const vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod);
        const screenshot_vulkan_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/screenshot_new_vulkan.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = vk_platform_mod },
            },
        });
        const screenshot_vulkan_exe = b.addExecutable(.{ .name = "snail-screenshot-new-vulkan", .root_module = screenshot_vulkan_mod });
        const run_screenshot_vulkan = b.addRunArtifact(screenshot_vulkan_exe);
        const screenshot_vulkan_step = b.step("run-screenshot-new-vulkan", "Render the demo through the Vulkan backend and write zig-out/demo-screenshot-new-vulkan.tga");
        screenshot_vulkan_step.dependOn(&run_screenshot_vulkan.step);
    }
}

pub fn build(b: *std.Build) void {
    const config = parseBuildConfig(b);
    const options_mod = createBuildOptionsModule(b, config.core_options);
    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const support_mod = createSupportModule(b, config.target, config.optimize);
    const vk_shaders_mod = vulkan_shaders.createModule(b, config.core_options.enable_vulkan);

    const snail_mod = addSnailModule(b, config, options_mod, vk_shaders_mod);
    const modules = ProjectModules{
        .assets = assets_mod,
        .support = support_mod,
        .options = options_mod,
        .vk_shaders = vk_shaders_mod,
        .snail = snail_mod,
    };

    addTestSteps(b, config, modules);
    addScreenshotSteps(b, config, modules);
}
