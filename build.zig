const std = @import("std");
const vulkan_shaders = @import("build/vulkan_shaders.zig");

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
    coverage_probe,
    gamma_probe,
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

    // Autohint xy policy vs TrueType agreement metric + overlay — CPU backend.
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
    const autohint_diff_step = b.step("run-autohint-diff", "Render the autohint xy policy vs TrueType at every demo ppem, print a disagreement score and write zig-out/autohint-diff.tga");
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
    const tt_probe_step = b.step("run-tt-probe", "Probe whether TrueType hinting output is a ppem-independent per-glyph function");
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

/// Compile the game's custom Vulkan material shaders (which #include snail's
/// coverage + records GLSL) to SPIR-V and inject them into `mod` as anonymous
/// imports for `game/game_shaders.zig`.
fn addGameShaderSpirv(b: *std.Build, mod: *std.Build.Module) void {
    const snail_includes = vulkan_shaders.IncludeDirs{
        .glsl = b.path("src/snail/shader/glsl"),
    };
    const game_glsl = [_]std.Build.LazyPath{b.path("src/demo/game/glsl")};
    const vert = vulkan_shaders.compileCallerShader(b, b.path("src/demo/game/glsl/game_material.vert"), "-fshader-stage=vert", "game_material.vert.spv", &.{}, snail_includes, &game_glsl);
    const frag = vulkan_shaders.compileCallerShader(b, b.path("src/demo/game/glsl/game_material.frag"), "-fshader-stage=frag", "game_material.frag.spv", &.{}, snail_includes, &game_glsl);
    mod.addAnonymousImport("game_material.vert.spv", .{ .root_source_file = vert });
    mod.addAnonymousImport("game_material.frag.spv", .{ .root_source_file = frag });
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

pub fn build(b: *std.Build) void {
    const config = parseBuildConfig(b);
    // Consumers use `dependency.namedLazyPath(...)` for glslc `-I` arguments;
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
    addPerfSteps(b, config, modules);
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
