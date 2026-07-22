const std = @import("std");
const vulkan_shaders = @import("build/vulkan_shaders.zig");
const slang_shaders = @import("build/slang_shaders.zig");

const version = "0.12.1";

const DemoEntry = enum {
    banner,
    game,
    autohint_compare,
    autohint_character_diff,
    autohint_diff,
    autohint_proportional,
    autohint_screenshot,
    backend_compare,
    composite_probe,
    coverage_parity_probe,
    coverage_probe,
    gamma_probe,
    algorithm_diagrams,
    screenshot_cpu,
    screenshot_gl,
    screenshot_gles30,
    screenshot_vulkan,
    banner_screenshot_cpu,
    banner_screenshot_gl,
    banner_screenshot_gles30,
    banner_screenshot_vulkan,
    game_screenshot_gl,
    game_screenshot_vulkan,
};

fn selectDemoEntry(b: *std.Build, mod: *std.Build.Module, entry: DemoEntry) void {
    const opts = b.addOptions();
    opts.addOption(DemoEntry, "value", entry);
    mod.addImport("demo_entry", opts.createModule());
}

const GlLibraries = struct {
    desktop: bool = false,
    es: bool = false,
};

fn configureEglOffscreenModule(
    mod: *std.Build.Module,
    embed_gl_mod: *std.Build.Module,
    libraries: GlLibraries,
) void {
    mod.linkSystemLibrary("EGL", .{});
    if (libraries.desktop) mod.linkSystemLibrary("OpenGL", .{});
    if (libraries.es) mod.linkSystemLibrary("GLESv2", .{});
    // Every EGL-offscreen tool renders GL through the caller-owned reference
    // renderer (embeddable-only); wire it once here.
    mod.addImport("embed_gl", embed_gl_mod);
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
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
    vulkan_types_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/platform/vulkan.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "render-state", .module = render_state_mod },
            .{ .name = "vulkan_types", .module = vulkan_types_mod },
        },
    });
    mod.linkSystemLibrary("vulkan", .{});
    return mod;
}

/// The reusable reference caller renderer for the Vulkan embeddable path
/// (`src/demo/render/vulkan/root.zig`). Bound to a specific `snail` module so its vk
/// types match the consumer's; created per consumer group (demo tools).
fn createEmbedVulkanModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    vulkan_types_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/demo/render/vulkan/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "render-state", .module = render_state_mod },
            .{ .name = "vulkan_shaders", .module = vk_shaders },
            .{ .name = "vulkan_types", .module = vulkan_types_mod },
        },
    });
}

fn createDemoVulkanTypesModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/render/vulkan/types.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.linkSystemLibrary("vulkan", .{});
    return mod;
}

/// Reference caller-owned GL all-in-one renderer + atlas cache + binding helper
/// (embeddable-only; the GL analog of `createEmbedVulkanModule`). This module
/// makes the live GL calls, so the *consuming exe* links the API used by its
/// selected build step; the Snail GLSL contract itself links no GL.
fn createEmbedGlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/render/gl/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "render-state", .module = render_state_mod },
        },
    });
    return mod;
}

fn createSupportModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    assets_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/support/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "assets", .module = assets_mod },
        },
    });
}

/// Construct the public `snail` module. Shader contracts are ordinary source
/// namespaces within the module and link no graphics APIs; callers own and
/// link their renderer. `public_name` publishes the module for dependents.
fn createSnailModuleFull(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    public_name: ?[]const u8,
    // When non-null, wired into every module and strip applied — for test
    // artifacts, whose test blocks pull font assets and want strip control.
    assets_mod: ?*std.Build.Module,
    strip: ?bool,
) *std.Build.Module {
    const options: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
    };
    const mod = if (public_name) |name| b.addModule(name, options) else b.createModule(options);
    if (assets_mod) |assets| mod.addImport("assets", assets);
    mod.linkSystemLibrary("harfbuzz", .{});
    return mod;
}

fn createRasterModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
    assets_mod: ?*std.Build.Module,
    strip: ?bool,
    public_name: ?[]const u8,
) *std.Build.Module {
    const module_options: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/snail-raster/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
    };
    const raster = if (public_name) |name| b.addModule(name, module_options) else b.createModule(module_options);
    raster.addImport("snail", snail_mod);
    raster.addImport("render-state", render_state_mod);
    if (assets_mod) |assets| raster.addImport("assets", assets);
    return raster;
}

fn createRenderStateModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/render_state.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "snail", .module = snail_mod }},
    });
}

fn createSnailModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return createSnailModuleFull(b, target, optimize, null, null, null);
}

/// For use as a dependency: returns the backend-neutral snail module plus its
/// shader contracts. The software renderer is constructed separately with
/// `rasterModule`.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return createSnailModule(b, target, optimize);
}

pub fn rasterModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    const render_state_mod = createRenderStateModule(b, target, optimize, snail_mod);
    return createRasterModule(
        b,
        target,
        optimize,
        snail_mod,
        render_state_mod,
        null,
        null,
        null,
    );
}

const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

fn parseBuildConfig(b: *std.Build) BuildConfig {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };
}

fn addSnailModule(
    b: *std.Build,
    config: BuildConfig,
) *std.Build.Module {
    return createSnailModuleFull(b, config.target, config.optimize, "snail", null, null);
}

const ProjectModules = struct {
    assets: *std.Build.Module,
    support: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    demo_vulkan_types: *std.Build.Module,
    snail: *std.Build.Module,
    render_state: *std.Build.Module,
    raster: *std.Build.Module,
};

fn addTestSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const test_step = b.step("test", "Run unit tests");
    const snail_tests = createSnailModuleFull(b, config.target, config.optimize, null, modules.assets, null);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = snail_tests })).step);
    const test_render_state = createRenderStateModule(b, config.target, config.optimize, snail_tests);
    const raster_tests = createRasterModule(b, config.target, config.optimize, snail_tests, test_render_state, modules.assets, null, null);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = raster_tests })).step);

    const public_api_tests = b.createModule(.{
        .root_source_file = b.path("src/tests/public_renderer_api.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "snail", .module = snail_tests },
            .{ .name = "snail-raster", .module = raster_tests },
        },
    });
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = public_api_tests })).step);

    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = modules.support })).step);

    // The dependency-free TGA pixel gate used by the Windows CI job.
    const pixelgate_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tools/pixelgate.zig"),
        .target = config.target,
        .optimize = config.optimize,
    }) });
    test_step.dependOn(&b.addRunArtifact(pixelgate_tests).step);

    const autohint_compare_test_module = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-raster", .module = modules.raster },
            .{ .name = "support", .module = modules.support },
        },
    });
    selectDemoEntry(b, autohint_compare_test_module, .autohint_compare);
    const autohint_compare_tests = b.addTest(.{ .root_module = autohint_compare_test_module });
    const run_autohint_compare_tests = b.addRunArtifact(autohint_compare_tests);
    test_step.dependOn(&run_autohint_compare_tests.step);

    const character_diff_test_module = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-raster", .module = modules.raster },
            .{ .name = "support", .module = modules.support },
        },
    });
    selectDemoEntry(b, character_diff_test_module, .autohint_character_diff);
    const character_diff_tests = b.addTest(.{ .root_module = character_diff_test_module });
    test_step.dependOn(&b.addRunArtifact(character_diff_tests).step);

    const test_valgrind_step = b.step("test-valgrind", "Run unit tests under Valgrind");
    const vg_snail = createSnailModuleFull(b, config.target, config.optimize, null, modules.assets, true);
    const vg_snail_tests = b.addTest(.{ .root_module = vg_snail });
    configureValgrindTest(vg_snail_tests);
    test_valgrind_step.dependOn(&b.addRunArtifact(vg_snail_tests).step);
    const vg_render_state = createRenderStateModule(b, config.target, config.optimize, vg_snail);
    const vg_raster = createRasterModule(b, config.target, config.optimize, vg_snail, vg_render_state, modules.assets, true, null);
    const vg_raster_tests = b.addTest(.{ .root_module = vg_raster });
    configureValgrindTest(vg_raster_tests);
    test_valgrind_step.dependOn(&b.addRunArtifact(vg_raster_tests).step);
}

fn addScreenshotSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const release_snail_mod = createSnailModule(b, config.target, .ReleaseFast);
    const release_render_state_mod = createRenderStateModule(b, config.target, .ReleaseFast, release_snail_mod);
    const release_raster_mod = createRasterModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod, null, null, null);
    const release_support_mod = createSupportModule(b, config.target, .ReleaseFast, release_snail_mod, modules.assets);
    const embed_vulkan_mod = createEmbedVulkanModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod, modules.vk_shaders, modules.demo_vulkan_types);
    const embed_gl_mod = createEmbedGlModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod);

    // CPU screenshot.
    const screenshot_cpu_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, screenshot_cpu_mod, .screenshot_cpu);
    const screenshot_cpu_exe = b.addExecutable(.{ .name = "snail-screenshot", .root_module = screenshot_cpu_mod });
    const run_screenshot_cpu = b.addRunArtifact(screenshot_cpu_exe);
    const screenshot_cpu_step = b.step("run-screenshot", "Render the demo through the CPU backend and write zig-out/demo-screenshot.tga");
    screenshot_cpu_step.dependOn(&run_screenshot_cpu.step);

    // CPU coverage-parity probe (affine twin of the composite probe).
    const coverage_parity_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, coverage_parity_mod, .coverage_parity_probe);
    const coverage_parity_exe = b.addExecutable(.{ .name = "snail-coverage-parity", .root_module = coverage_parity_mod });
    const run_coverage_parity = b.addRunArtifact(coverage_parity_exe);
    const coverage_parity_step = b.step("run-coverage-parity", "Sweep the composite panel through hostile affine transforms on the CPU rasterizer and gate on interior coverage holes");
    coverage_parity_step.dependOn(&run_coverage_parity.step);

    // README algorithm diagrams — CPU backend.
    const algorithm_diagrams_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, algorithm_diagrams_mod, .algorithm_diagrams);
    const algorithm_diagrams_exe = b.addExecutable(.{ .name = "snail-algorithm-diagrams", .root_module = algorithm_diagrams_mod });
    const run_algorithm_diagrams = b.addRunArtifact(algorithm_diagrams_exe);
    const algorithm_diagrams_step = b.step("run-algorithm-diagrams", "Render the README algorithm diagrams through the CPU backend into zig-out/algorithm-*.tga");
    algorithm_diagrams_step.dependOn(&run_algorithm_diagrams.step);

    // Composable autohint policy comparison — CPU backend.
    const autohint_shot_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, autohint_shot_mod, .autohint_screenshot);
    configureEglOffscreenModule(autohint_shot_mod, embed_gl_mod, .{ .desktop = true });
    const autohint_shot_exe = b.addExecutable(.{ .name = "snail-autohint-screenshot", .root_module = autohint_shot_mod });
    const run_autohint_shot = b.addRunArtifact(autohint_shot_exe);
    const autohint_shot_step = b.step("run-autohint-screenshot", "Render the composable autohint policy comparison through the CPU backend and write zig-out/autohint-screenshot.tga");
    autohint_shot_step.dependOn(&run_autohint_shot.step);

    // Autohint xy policy vs TT-hint agreement metric + overlay — CPU backend.
    const autohint_diff_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, autohint_diff_mod, .autohint_diff);
    const autohint_diff_exe = b.addExecutable(.{ .name = "snail-autohint-diff", .root_module = autohint_diff_mod });
    const run_autohint_diff = b.addRunArtifact(autohint_diff_exe);
    const autohint_diff_step = b.step("run-autohint-diff", "Render the autohint xy policy vs TT hinting at every demo ppem, print a disagreement score and write zig-out/autohint-diff.tga");
    autohint_diff_step.dependOn(&run_autohint_diff.step);

    const character_diff_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, character_diff_mod, .autohint_character_diff);
    const character_diff_exe = b.addExecutable(.{ .name = "snail-autohint-character-diff", .root_module = character_diff_mod });
    const run_character_diff = b.addRunArtifact(character_diff_exe);
    const character_diff_step = b.step("run-autohint-character-diff", "Write per-character TT/autohint contact sheets and metrics under zig-out/autohint-character-diff");
    character_diff_step.dependOn(&run_character_diff.step);

    // Proportional-face spot check — CPU backend.
    const prop_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, prop_mod, .autohint_proportional);
    const prop_exe = b.addExecutable(.{ .name = "snail-autohint-prop", .root_module = prop_mod });
    const prop_step = b.step("run-autohint-prop", "Render the autohint policies on a proportional TT-hinted face → zig-out/autohint-prop.tga");
    prop_step.dependOn(&b.addRunArtifact(prop_exe).step);

    // RESEARCH PROBE: TT bytecode ppem-independence analysis (internal types).
    const tt_probe_internal_mod = b.createModule(.{
        .root_source_file = b.path("src/snail/tt_probe_internal.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = modules.assets }},
    });
    const tt_probe_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/tt_ppem_probe.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail_tt_probe_internal", .module = tt_probe_internal_mod },
        },
    });
    const tt_probe_exe = b.addExecutable(.{ .name = "snail-tt-probe", .root_module = tt_probe_mod });
    const run_tt_probe = b.addRunArtifact(tt_probe_exe);
    const tt_probe_step = b.step("run-tt-probe", "Probe whether TT-hint output is a ppem-independent per-glyph function");
    tt_probe_step.dependOn(&run_tt_probe.step);

    // Banner screenshot — full interactive-demo scene through CPU backend.
    const banner_screenshot_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, banner_screenshot_mod, .banner_screenshot_cpu);
    const banner_screenshot_exe = b.addExecutable(.{ .name = "snail-banner-screenshot", .root_module = banner_screenshot_mod });
    const run_banner_screenshot = b.addRunArtifact(banner_screenshot_exe);
    const banner_screenshot_step = b.step("run-banner-screenshot", "Render the full banner scene through the CPU backend and write zig-out/banner-screenshot.tga");
    banner_screenshot_step.dependOn(&run_banner_screenshot.step);

    // Banner screenshot — GL 3.3 offscreen.
    const banner_screenshot_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, banner_screenshot_gl_mod, .banner_screenshot_gl);
    configureEglOffscreenModule(banner_screenshot_gl_mod, embed_gl_mod, .{ .desktop = true });
    const banner_screenshot_gl_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-gl", .root_module = banner_screenshot_gl_mod });
    const run_banner_screenshot_gl = b.addRunArtifact(banner_screenshot_gl_exe);
    const banner_screenshot_gl_step = b.step("run-banner-screenshot-gl", "Render the full banner scene through GL and write zig-out/banner-screenshot-gl.tga");
    banner_screenshot_gl_step.dependOn(&run_banner_screenshot_gl.step);

    // Banner screenshot — GLES 3.0 offscreen.
    const banner_screenshot_gles30_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, banner_screenshot_gles30_mod, .banner_screenshot_gles30);
    configureEglOffscreenModule(banner_screenshot_gles30_mod, embed_gl_mod, .{ .es = true });
    const banner_screenshot_gles30_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-gles30", .root_module = banner_screenshot_gles30_mod });
    const run_banner_screenshot_gles30 = b.addRunArtifact(banner_screenshot_gles30_exe);
    const banner_screenshot_gles30_step = b.step("run-banner-screenshot-gles30", "Render the full banner scene through GLES 3.0 and write zig-out/banner-screenshot-gles30.tga");
    banner_screenshot_gles30_step.dependOn(&run_banner_screenshot_gles30.step);

    // Banner screenshot — Vulkan offscreen.
    {
        const release_vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod, modules.demo_vulkan_types);
        const banner_screenshot_vk_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = release_vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
        selectDemoEntry(b, banner_screenshot_vk_mod, .banner_screenshot_vulkan);
        const banner_screenshot_vk_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-vulkan", .root_module = banner_screenshot_vk_mod });
        const run_banner_screenshot_vk = b.addRunArtifact(banner_screenshot_vk_exe);
        const banner_screenshot_vk_step = b.step("run-banner-screenshot-vulkan", "Render the full banner scene through Vulkan and write zig-out/banner-screenshot-vulkan.tga");
        banner_screenshot_vk_step.dependOn(&run_banner_screenshot_vk.step);
    }

    // GL screenshot.
    const screenshot_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, screenshot_gl_mod, .screenshot_gl);
    configureEglOffscreenModule(screenshot_gl_mod, embed_gl_mod, .{ .desktop = true });
    const screenshot_gl_exe = b.addExecutable(.{ .name = "snail-screenshot-gl", .root_module = screenshot_gl_mod });
    const run_screenshot_gl = b.addRunArtifact(screenshot_gl_exe);
    const screenshot_gl_step = b.step("run-screenshot-gl", "Render the demo through the GL backend and write zig-out/demo-screenshot-gl.tga");
    screenshot_gl_step.dependOn(&run_screenshot_gl.step);

    // Offscreen Vulkan game-scene screenshot (depth-tested) → zig-out/game-vulkan.tga.
    {
        const release_vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod, modules.demo_vulkan_types);
        const game_shot_vk_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = release_vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
        selectDemoEntry(b, game_shot_vk_mod, .game_screenshot_vulkan);
        addGameShaderSpirv(b, game_shot_vk_mod);
        const game_shot_vk_exe = b.addExecutable(.{ .name = "snail-game-screenshot-vulkan", .root_module = game_shot_vk_mod });
        const run_game_shot_vk = b.addRunArtifact(game_shot_vk_exe);
        const game_shot_vk_step = b.step("run-game-screenshot-vulkan", "Render the game scene offscreen through Vulkan → zig-out/game-vulkan.tga");
        game_shot_vk_step.dependOn(&run_game_shot_vk.step);
    }

    // Offscreen (no-window) game-scene screenshot per GL backend — the game's
    // headless verification harness. Writes zig-out/game-<backend>.tga.
    {
        const game_shot_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
            },
        });
        selectDemoEntry(b, game_shot_mod, .game_screenshot_gl);
        configureEglOffscreenModule(game_shot_mod, embed_gl_mod, .{ .desktop = true, .es = true });
        const game_shot_exe = b.addExecutable(.{ .name = "snail-game-screenshot", .root_module = game_shot_mod });
        const run_game_shot = b.addRunArtifact(game_shot_exe);
        const game_shot_step = b.step("run-game-screenshot", "Render the game scene offscreen per GL backend → zig-out/game-<backend>.tga");
        game_shot_step.dependOn(&run_game_shot.step);
    }

    // Regression gate for the fill_stroke_inside composite: sweeps a rounded-rect
    // panel through perspective and fails if any interior coverage hole appears.
    {
        const comp_probe_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
            },
        });
        selectDemoEntry(b, comp_probe_mod, .composite_probe);
        configureEglOffscreenModule(comp_probe_mod, embed_gl_mod, .{ .desktop = true });
        const comp_probe_exe = b.addExecutable(.{ .name = "snail-composite-probe", .root_module = comp_probe_mod });
        const run_comp_probe = b.addRunArtifact(comp_probe_exe);
        const comp_probe_step = b.step("run-composite-probe", "Sweep a fill_stroke_inside panel through perspective and gate on interior coverage holes");
        comp_probe_step.dependOn(&run_comp_probe.step);
    }

    // CPU port of the path coverage evaluator to root-cause the conic
    // grazing-corner hole deterministically (both conic solvers, swept footprint).
    {
        const cov_probe_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
            },
        });
        selectDemoEntry(b, cov_probe_mod, .coverage_probe);
        const cov_probe_exe = b.addExecutable(.{ .name = "snail-coverage-probe", .root_module = cov_probe_mod });
        const run_cov_probe = b.addRunArtifact(cov_probe_exe);
        const cov_probe_step = b.step("run-coverage-probe", "Sweep the conic coverage solver (deriv vs code) across grazing footprints and count holes");
        cov_probe_step.dependOn(&run_cov_probe.step);
    }

    // CPU-vs-GL pixel parity gate over the shared content scene.
    const backend_compare_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, backend_compare_mod, .backend_compare);
    configureEglOffscreenModule(backend_compare_mod, embed_gl_mod, .{ .desktop = true });
    const backend_compare_exe = b.addExecutable(.{ .name = "snail-backend-compare", .root_module = backend_compare_mod });
    const run_backend_compare = b.addRunArtifact(backend_compare_exe);
    const backend_compare_step = b.step("run-backend-compare", "Render the content scene through CPU and GL and fail if they diverge beyond the AA tolerance");
    backend_compare_step.dependOn(&run_backend_compare.step);

    // Gamma conformance gate: interior (full-coverage) pixels of a controlled
    // solid scene, CPU vs GL33 vs GLES30, checked exactly against the analytic
    // encode. Immune to AA-edge differences that backend-compare tolerates.
    const gamma_probe_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, gamma_probe_mod, .gamma_probe);
    configureEglOffscreenModule(gamma_probe_mod, embed_gl_mod, .{ .desktop = true, .es = true });
    const gamma_probe_exe = b.addExecutable(.{ .name = "snail-gamma-probe", .root_module = gamma_probe_mod });
    const run_gamma_probe = b.addRunArtifact(gamma_probe_exe);
    const gamma_probe_step = b.step("run-gamma-probe", "Check interior-pixel gamma (encode round-trip) across CPU/GL33/GLES30");
    gamma_probe_step.dependOn(&run_gamma_probe.step);

    // GLES screenshot.
    const screenshot_gles30_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-raster", .module = release_raster_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    selectDemoEntry(b, screenshot_gles30_mod, .screenshot_gles30);
    configureEglOffscreenModule(screenshot_gles30_mod, embed_gl_mod, .{ .es = true });
    const screenshot_gles30_exe = b.addExecutable(.{ .name = "snail-screenshot-gles30", .root_module = screenshot_gles30_mod });
    const run_screenshot_gles30 = b.addRunArtifact(screenshot_gles30_exe);
    const screenshot_gles30_step = b.step("run-screenshot-gles30", "Render the demo through the GLES30 backend and write zig-out/demo-screenshot-gles30.tga");
    screenshot_gles30_step.dependOn(&run_screenshot_gles30.step);

    // Vulkan screenshot.
    {
        const vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, release_snail_mod, release_render_state_mod, modules.demo_vulkan_types);
        const screenshot_vulkan_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-raster", .module = release_raster_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
        selectDemoEntry(b, screenshot_vulkan_mod, .screenshot_vulkan);
        const screenshot_vulkan_exe = b.addExecutable(.{ .name = "snail-screenshot-vulkan", .root_module = screenshot_vulkan_mod });
        const run_screenshot_vulkan = b.addRunArtifact(screenshot_vulkan_exe);
        const screenshot_vulkan_step = b.step("run-screenshot-vulkan", "Render the demo through the Vulkan backend and write zig-out/demo-screenshot-vulkan.tga");
        screenshot_vulkan_step.dependOn(&run_screenshot_vulkan.step);
    }
}

fn addInteractiveDemoStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    // Interactive demo: default to ReleaseFast unless the user explicitly
    // overrides via -Doptimize. The demo is CPU-bound enough on the
    // shape/emit path that a Debug build is visibly slower; explicit
    // override (e.g. `-Doptimize=Debug` for debugging) still wins.
    const demo_optimize = if (b.user_input_options.contains("optimize")) config.optimize else .ReleaseFast;
    const demo_embed_gl_mod = createEmbedGlModule(b, config.target, demo_optimize, modules.snail, modules.render_state);
    const demo_embed_vulkan_mod = createEmbedVulkanModule(b, config.target, demo_optimize, modules.snail, modules.render_state, modules.vk_shaders, modules.demo_vulkan_types);
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = demo_optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-raster", .module = modules.raster },
            .{ .name = "support", .module = modules.support },
            .{ .name = "embed_gl", .module = demo_embed_gl_mod },
            .{ .name = "embed_vulkan", .module = demo_embed_vulkan_mod },
            .{ .name = "vulkan_types", .module = modules.demo_vulkan_types },
        },
    });
    selectDemoEntry(b, demo_mod, .banner);
    // Interactive demo wraps every backend's platform layer: Wayland +
    // EGL/OpenGL + Vulkan + libwayland-client. The platform sources live
    // alongside the demo and reference snail's public types only.
    demo_mod.linkSystemLibrary("wayland-client", .{});
    demo_mod.addIncludePath(b.path("src/demo/platform"));
    demo_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
    demo_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/presentation-time-client-protocol.c") });
    demo_mod.linkSystemLibrary("EGL", .{});
    demo_mod.linkSystemLibrary("wayland-egl", .{});
    demo_mod.linkSystemLibrary("OpenGL", .{});
    demo_mod.linkSystemLibrary("GLESv2", .{});
    demo_mod.linkSystemLibrary("vulkan", .{});

    const demo_exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_mod });
    const install_demo_artifact = b.addInstallArtifact(demo_exe, .{});
    const install_demo_step = b.step("install-demo", "Install the interactive Wayland banner demo");
    install_demo_step.dependOn(&install_demo_artifact.step);
    const run_demo = b.addRunArtifact(demo_exe);
    if (b.args) |args| run_demo.addArgs(args);
    const run_step = b.step("run", "Run the interactive Wayland banner demo");
    run_step.dependOn(&run_demo.step);
}

/// Compile the game's custom Vulkan material shaders (native Slang; the
/// caller-authored family src/demo/game/slang/game_material.slang imports
/// snail's text_sample module) to SPIR-V and inject them into `mod` as
/// anonymous imports for `game/game_shaders.zig`.
fn addGameShaderSpirv(b: *std.Build, mod: *std.Build.Module) void {
    const spv = slang_shaders.vulkanGameMaterialSpv(b);
    mod.addAnonymousImport("game_material.vert.spv", .{ .root_source_file = spv.vert });
    mod.addAnonymousImport("game_material.frag.spv", .{ .root_source_file = spv.frag });
}

fn addGameDemoStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    // The game demo cycles Vulkan and the GL family (gl33/gl44/gles30) at
    // runtime — a 3D scene whose custom material shader samples snail glyph
    // coverage. It owns both window-system integrations and their API links.
    const game_optimize = if (b.user_input_options.contains("optimize")) config.optimize else .ReleaseFast;
    const game_embed_gl_mod = createEmbedGlModule(b, config.target, game_optimize, modules.snail, modules.render_state);
    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/root.zig"),
        .target = config.target,
        .optimize = game_optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-raster", .module = modules.raster },
            .{ .name = "support", .module = modules.support },
            .{ .name = "embed_gl", .module = game_embed_gl_mod },
        },
    });
    selectDemoEntry(b, game_mod, .game);
    game_mod.linkSystemLibrary("wayland-client", .{});
    game_mod.addIncludePath(b.path("src/demo/platform"));
    game_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
    game_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/presentation-time-client-protocol.c") });
    game_mod.linkSystemLibrary("EGL", .{});
    game_mod.linkSystemLibrary("wayland-egl", .{});
    game_mod.linkSystemLibrary("OpenGL", .{});
    game_mod.linkSystemLibrary("GLESv2", .{});
    // vk_scene uses the reference caller renderer; the windowed Vulkan
    // platform is a relative file compiled into game_mod (its own vk cImport
    // via linkSystemLibrary). game/game_shaders.zig gets the material SPIR-V.
    game_mod.addImport("embed_vulkan", createEmbedVulkanModule(b, config.target, game_optimize, modules.snail, modules.render_state, modules.vk_shaders, modules.demo_vulkan_types));
    game_mod.addImport("vulkan_types", modules.demo_vulkan_types);
    addGameShaderSpirv(b, game_mod);
    game_mod.linkSystemLibrary("vulkan", .{});

    const game_exe = b.addExecutable(.{ .name = "snail-game-demo", .root_module = game_mod });
    const install_game_artifact = b.addInstallArtifact(game_exe, .{});
    const install_game_step = b.step("install-game", "Install the interactive Wayland 3D game demo");
    install_game_step.dependOn(&install_game_artifact.step);
    const run_game = b.addRunArtifact(game_exe);
    if (b.args) |args| run_game.addArgs(args);
    const run_step = b.step("run-game", "Run the interactive Wayland 3D game demo");
    run_step.dependOn(&run_game.step);
}

fn addMinimalGlStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/app/minimal_gl.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
        },
    });
    mod.linkSystemLibrary("EGL", .{});
    mod.linkSystemLibrary("OpenGL", .{});
    const exe = b.addExecutable(.{ .name = "snail-minimal-gl", .root_module = mod });
    const run = b.addRunArtifact(exe);
    const step = b.step("run-minimal-gl", "Render the one-file public-API GL example to zig-out/minimal-gl.tga");
    step.dependOn(&run.step);
}

/// Cross-compiled Windows demo: `zig build run-minimal-d3d11` builds
/// src/demo/app/minimal_d3d11.zig for x86_64-windows-gnu (zig's bundled
/// mingw provides d3d11.h/dxgi.h/d3dcompiler.h and the import libraries)
/// and runs it headless under Wine with a hermetic prefix in zig-out.
/// The one non-bundled dependency is HarfBuzz: the Windows snail module
/// compiles the upstream single-file amalgam (`src/harfbuzz.cc`) from the
/// nix-pinned source tree exported as `HARFBUZZ_SRC` (see shell.nix)
/// instead of linking the host system library.
fn addMinimalD3d11Step(
    b: *std.Build,
    modules: ProjectModules,
) void {
    const step = b.step("run-minimal-d3d11", "Render the one-file public-API D3D11 example under Wine to zig-out/minimal-d3d11.tga");
    const gates_step = b.step("install-windows-gates", "Install the cross-built D3D11 demo, pixelgate, and the reference TGA into zig-out/windows-gates for the Windows CI job");
    const hb_src = b.graph.environ_map.get("HARFBUZZ_SRC") orelse {
        const fail = b.addFail("run-minimal-d3d11 needs HARFBUZZ_SRC (enter nix-shell; see shell.nix)");
        step.dependOn(&fail.step);
        gates_step.dependOn(&fail.step);
        return;
    };
    const win_target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu });

    // The snail module for the Windows target: identical source, but
    // HarfBuzz is compiled in from the amalgam rather than system-linked.
    const snail_win = b.createModule(.{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = win_target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .link_libcpp = true,
    });
    snail_win.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ hb_src, "src" }) });
    snail_win.addCSourceFile(.{
        .file = .{ .cwd_relative = b.pathJoin(&.{ hb_src, "src", "harfbuzz.cc" }) },
        .flags = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti" },
        .language = .cpp,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/app/minimal_d3d11.zig"),
        .target = win_target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = snail_win },
        },
    });
    mod.linkSystemLibrary("d3d11", .{ .use_pkg_config = .no });
    mod.linkSystemLibrary("dxgi", .{ .use_pkg_config = .no });
    mod.linkSystemLibrary("d3dcompiler_47", .{ .use_pkg_config = .no });
    const exe = b.addExecutable(.{ .name = "snail-minimal-d3d11", .root_module = mod });

    // Hermetic Wine prefix inside zig-out (first run pays one-time prefix
    // setup); `wine` comes from the nix shell. The exe writes
    // zig-out/minimal-d3d11.tga relative to the build root.
    b.build_root.handle.createDirPath(b.graph.io, "zig-out") catch {};
    const run = b.addSystemCommand(&.{"wine"});
    run.addArtifactArg(exe);
    run.setEnvironmentVariable("WINEPREFIX", b.pathFromRoot("zig-out/wineprefix"));
    run.setEnvironmentVariable("WINEDEBUG", "-all");
    // Rendering output changes with the shaders/scene, not just the exe.
    run.has_side_effects = true;
    step.dependOn(&run.step);

    // `install-windows-gates`: everything a bare Windows CI runner needs to
    // validate the render against real D3D11 — the demo exe, the pixelgate
    // comparison tool (the ImageMagick gate without ImageMagick), and the
    // checked-in reference TGA. The Windows runner only executes these
    // prebuilt artifacts; the one nix-pinned toolchain stays on Linux
    // (see the `windows` job in .github/workflows/ci.yml).
    const gates_dir: std.Build.InstallDir = .{ .custom = "windows-gates" };

    // Cross-built CPU-rasterizer screenshot (the `run-screenshot` demo-scene
    // tool): no GL, no display, no D3D — pure snail-raster float math, so the
    // Windows render is gated bit-identical (pixelgate threshold 0) against
    // the checked-in Linux CPU reference. Reuses the amalgam-HarfBuzz snail
    // module above.
    {
        const render_state_win = createRenderStateModule(b, win_target, .ReleaseFast, snail_win);
        const raster_win = createRasterModule(b, win_target, .ReleaseFast, snail_win, render_state_win, null, null, null);
        const support_win = createSupportModule(b, win_target, .ReleaseFast, snail_win, modules.assets);
        const screenshot_cpu_win_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/root.zig"),
            .target = win_target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = snail_win },
                .{ .name = "snail-raster", .module = raster_win },
                .{ .name = "support", .module = support_win },
            },
        });
        selectDemoEntry(b, screenshot_cpu_win_mod, .screenshot_cpu);
        const screenshot_cpu_win_exe = b.addExecutable(.{ .name = "snail-screenshot-cpu", .root_module = screenshot_cpu_win_mod });
        gates_step.dependOn(&b.addInstallArtifact(screenshot_cpu_win_exe, .{ .dest_dir = .{ .override = gates_dir } }).step);
        gates_step.dependOn(&b.addInstallFile(b.path("src/demo/tools/screenshots/demo_cpu_reference.tga"), "windows-gates/demo_cpu_reference.tga").step);
    }

    // Cross-built WebGPU demo (wgpu-native's D3D12 backend on the Windows
    // runner): links the upstream wgpu-native Windows-gnu release import lib
    // pinned in shell.nix (SNAIL_WGPU_WINDOWS, version-matched to the nixpkgs
    // wgpu-native), ships wgpu_native.dll next to the exe.
    if (b.graph.environ_map.get("SNAIL_WGPU_WINDOWS")) |wgpu_win| {
        const wgpu_win_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/app/minimal_wgpu.zig"),
            .target = win_target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = snail_win },
            },
        });
        wgpu_win_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ wgpu_win, "include" }) });
        wgpu_win_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ wgpu_win, "lib" }) });
        wgpu_win_mod.linkSystemLibrary("wgpu_native", .{ .use_pkg_config = .no });
        const wgpu_win_exe = b.addExecutable(.{ .name = "snail-minimal-wgpu", .root_module = wgpu_win_mod });
        gates_step.dependOn(&b.addInstallArtifact(wgpu_win_exe, .{ .dest_dir = .{ .override = gates_dir } }).step);
        gates_step.dependOn(&b.addInstallFile(.{ .cwd_relative = b.pathJoin(&.{ wgpu_win, "lib", "wgpu_native.dll" }) }, "windows-gates/wgpu_native.dll").step);
    } else {
        gates_step.dependOn(&b.addFail("install-windows-gates needs SNAIL_WGPU_WINDOWS (enter nix-shell; see shell.nix)").step);
    }
    const pixelgate_win = b.addExecutable(.{
        .name = "pixelgate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/pixelgate.zig"),
            .target = win_target,
            .optimize = .ReleaseFast,
        }),
    });
    gates_step.dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = gates_dir } }).step);
    gates_step.dependOn(&b.addInstallArtifact(pixelgate_win, .{ .dest_dir = .{ .override = gates_dir } }).step);
    gates_step.dependOn(&b.addInstallFile(b.path("src/demo/app/minimal_reference.tga"), "windows-gates/minimal_reference.tga").step);

    // A native pixelgate too (zig-out/bin), so the same gate is runnable
    // locally against Wine-produced TGAs.
    const pixelgate_native = b.addExecutable(.{
        .name = "pixelgate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/pixelgate.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    gates_step.dependOn(&b.addInstallArtifact(pixelgate_native, .{}).step);
}

/// Best-effort Metal demo (see src/demo/app/minimal_metal.zig and
/// src/snail/shader/slang/README-notes "Metal stage"). Two steps:
///
///  - `check-metal-demo` (any host): cross-compiles the demo and its snail
///    module (HarfBuzz amalgam included) for aarch64-macos into a static
///    library — full semantic analysis + machine code generation with
///    zig's bundled macOS libc/libc++ headers, forced through
///    `comptime { _ = &main; }` in the demo file. What this does NOT
///    verify: linking against the Apple frameworks (needs an SDK), the
///    Objective-C selector spellings/enum values (runtime-checked only),
///    and any Metal runtime behavior.
///  - `run-minimal-metal` (macOS host only): native build linking
///    Metal/Foundation/CoreGraphics (CoreGraphics is required for
///    MTLCreateSystemDefaultDevice in a command-line tool), then runs it
///    to produce zig-out/minimal-metal.tga.
fn addMinimalMetalStep(
    b: *std.Build,
    modules: ProjectModules,
) void {
    const check_step = b.step("check-metal-demo", "Cross-compile the one-file Metal example for aarch64-macos (analysis+codegen only; no SDK link, no Metal runtime on this host)");
    const run_step = b.step("run-minimal-metal", "Render the one-file public-API Metal example to zig-out/minimal-metal.tga (macOS hosts only)");
    const hb_src = b.graph.environ_map.get("HARFBUZZ_SRC") orelse {
        const fail = b.addFail("check-metal-demo / run-minimal-metal need HARFBUZZ_SRC (enter nix-shell; see shell.nix)");
        check_step.dependOn(&fail.step);
        run_step.dependOn(&fail.step);
        return;
    };

    // The snail module for a macOS target: identical source, HarfBuzz
    // compiled in from the amalgam (same pattern as the Windows/D3D11
    // demo; zig bundles the macOS libc/libc++ headers, so this
    // cross-compiles without an SDK).
    const makeModule = struct {
        fn make(bb: *std.Build, mods: ProjectModules, hb: []const u8, target: std.Build.ResolvedTarget) *std.Build.Module {
            const snail_mac = bb.createModule(.{
                .root_source_file = bb.path("src/snail/root.zig"),
                .target = target,
                .optimize = .ReleaseFast,
                .link_libc = true,
                .link_libcpp = true,
            });
            snail_mac.addIncludePath(.{ .cwd_relative = bb.pathJoin(&.{ hb, "src" }) });
            snail_mac.addCSourceFile(.{
                .file = .{ .cwd_relative = bb.pathJoin(&.{ hb, "src", "harfbuzz.cc" }) },
                .flags = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti" },
                .language = .cpp,
            });
            const mod = bb.createModule(.{
                .root_source_file = bb.path("src/demo/app/minimal_metal.zig"),
                .target = target,
                .optimize = .ReleaseFast,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "assets", .module = mods.assets },
                    .{ .name = "snail", .module = snail_mac },
                },
            });
            return mod;
        }
    }.make;

    // Compile check: a static library needs no linker pass against the
    // (absent) Apple SDK, but still compiles every Zig and C++ input.
    const check_target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos });
    const check_lib = b.addLibrary(.{
        .name = "snail-minimal-metal-check",
        .linkage = .static,
        .root_module = makeModule(b, modules, hb_src, check_target),
    });
    // Installing the archive forces real machine-code emission (a bare
    // dependency would run analysis-only via -fno-emit-bin).
    check_step.dependOn(&b.addInstallArtifact(check_lib, .{}).step);

    if (b.graph.host.result.os.tag == .macos) {
        const mod = makeModule(b, modules, hb_src, b.resolveTargetQuery(.{}));
        mod.linkFramework("Metal", .{});
        mod.linkFramework("Foundation", .{});
        mod.linkFramework("CoreGraphics", .{});
        const exe = b.addExecutable(.{ .name = "snail-minimal-metal", .root_module = mod });
        const run = b.addRunArtifact(exe);
        // Rendering output changes with the shaders/scene, not just the exe.
        run.has_side_effects = true;
        run_step.dependOn(&run.step);
    } else {
        const fail = b.addFail("run-minimal-metal needs a macOS host (this build has no Metal runtime); on this host use `zig build check-metal-demo`");
        run_step.dependOn(&fail.step);
    }
}

fn addMinimalWgpuStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/app/minimal_wgpu.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
        },
    });
    // wgpu-native ships no pkg-config file; the nix shell exports the split
    // dev/lib outputs (see shell.nix). Fall back to plain system linking when
    // the variables are absent.
    if (b.graph.environ_map.get("WGPU_NATIVE_INCLUDE")) |include_dir| {
        mod.addIncludePath(.{ .cwd_relative = include_dir });
    }
    if (b.graph.environ_map.get("WGPU_NATIVE_LIB")) |lib_dir| {
        mod.addLibraryPath(.{ .cwd_relative = lib_dir });
        // macOS: no LD_LIBRARY_PATH analog survives into the child process
        // (SIP scrubs DYLD_*), so bake the nix store lib dir into the rpath.
        mod.addRPath(.{ .cwd_relative = lib_dir });
    }
    mod.linkSystemLibrary("wgpu_native", .{ .use_pkg_config = .no });
    const exe = b.addExecutable(.{ .name = "snail-minimal-wgpu", .root_module = mod });
    const run = b.addRunArtifact(exe);
    const step = b.step("run-minimal-wgpu", "Render the one-file public-API WebGPU example to zig-out/minimal-wgpu.tga");
    step.dependOn(&run.step);
}

pub fn build(b: *std.Build) void {
    const config = parseBuildConfig(b);
    // Consumers use `dependency.namedLazyPath(...)` for slangc `-I` arguments;
    // the paths stay dependency-relative instead of assuming their build root.
    b.addNamedLazyPath("snail_glsl", b.path("src/snail/shader/glsl"));
    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const snail_mod = addSnailModule(b, config);
    const render_state_mod = createRenderStateModule(b, config.target, config.optimize, snail_mod);
    const raster_mod = createRasterModule(b, config.target, config.optimize, snail_mod, render_state_mod, null, null, "snail-raster");
    const support_mod = createSupportModule(b, config.target, config.optimize, snail_mod, assets_mod);
    const vk_shaders_mod = vulkan_shaders.createModule(b);
    const demo_vulkan_types_mod = createDemoVulkanTypesModule(b, config.target, config.optimize);

    const modules = ProjectModules{
        .assets = assets_mod,
        .support = support_mod,
        .vk_shaders = vk_shaders_mod,
        .demo_vulkan_types = demo_vulkan_types_mod,
        .snail = snail_mod,
        .render_state = render_state_mod,
        .raster = raster_mod,
    };

    addTestSteps(b, config, modules);
    addScreenshotSteps(b, config, modules);
    addInteractiveDemoStep(b, config, modules);
    addGameDemoStep(b, config, modules);
    addMinimalGlStep(b, config, modules);
    addMinimalWgpuStep(b, config, modules);
    addMinimalD3d11Step(b, modules);
    addMinimalMetalStep(b, modules);
    addPerfSteps(b, config, modules);
    slang_shaders.addGenShadersStep(b);
}

fn addPerfSteps(b: *std.Build, config: BuildConfig, modules: ProjectModules) void {
    const prep_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/perf/prep.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
        },
    });
    const prep_exe = b.addExecutable(.{ .name = "snail-perf-prep", .root_module = prep_mod });

    const raster_perf_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/perf/raster.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-raster", .module = modules.raster },
        },
    });
    const raster_perf_exe = b.addExecutable(.{ .name = "snail-perf-raster", .root_module = raster_perf_mod });

    const glsl_perf_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/perf/glsl.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
        },
    });
    glsl_perf_mod.linkSystemLibrary("EGL", .{});
    glsl_perf_mod.linkSystemLibrary("OpenGL", .{});
    const glsl_perf_exe = b.addExecutable(.{ .name = "snail-perf-glsl", .root_module = glsl_perf_mod });

    const install_perf = b.step("install-perf", "Install the consumer-facing performance regression runners");
    install_perf.dependOn(&b.addInstallArtifact(prep_exe, .{}).step);
    install_perf.dependOn(&b.addInstallArtifact(raster_perf_exe, .{}).step);
    install_perf.dependOn(&b.addInstallArtifact(glsl_perf_exe, .{}).step);
}
