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
    embed_gl_mod: *std.Build.Module,
) void {
    configureCoreModule(mod, build_options_mod, options, vk_shaders);
    mod.linkSystemLibrary("EGL", .{});
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
    return mod;
}

/// The reusable reference caller renderer for the Vulkan embeddable path
/// (`src/demo/embed_vulkan.zig`). Bound to a specific `snail` module so its vk
/// types match the consumer's; created per consumer group (demo tools, bench).
fn createEmbedVulkanModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/demo/embed_vulkan.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
        },
    });
}

/// Reference caller-owned GL all-in-one renderer + atlas cache + binding helper
/// (embeddable-only; the GL analog of `createEmbedVulkanModule`). This module
/// makes the live GL calls, so the *consuming exe* must link OpenGL/GLESv2
/// (every GL consumer already does via `configureCoreModule`); snail_gl itself
/// links no GL.
fn createEmbedGlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/demo/embed_gl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
        },
    });
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

/// Build the snail compiler-module graph and return the public `snail`
/// facade. The graph is a DAG:
///
///   snail_core ── snail_cpu / snail_gl / snail_vulkan ── snail (facade)
///
/// `snail_core` is backend-independent (links only harfbuzz for shaping);
/// each backend module links only its own system libs (GL / Vulkan); the
/// facade re-exports everything. A dependent that only wants Vulkan pulls
/// `snail_core` + `snail_vulkan` and links no GL. `public_name` addModule's
/// the facade (for external dependents) vs. an internal createModule.
const SnailGraph = struct {
    core: *std.Build.Module,
    cpu: *std.Build.Module,
    gl: *std.Build.Module,
    vulkan: *std.Build.Module,
    facade: *std.Build.Module,
};

fn buildSnailGraphFull(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
    public_name: ?[]const u8,
    // When non-null, wired into every module and strip applied — for test
    // artifacts, whose test blocks pull font assets and want strip control.
    assets_mod: ?*std.Build.Module,
    strip: ?bool,
) SnailGraph {
    const mk = struct {
        fn m(bb: *std.Build, path: []const u8, t: std.Build.ResolvedTarget, o: std.builtin.OptimizeMode, s: ?bool, bo: *std.Build.Module, am: ?*std.Build.Module) *std.Build.Module {
            const mod = bb.createModule(.{
                .root_source_file = bb.path(path),
                .target = t,
                .optimize = o,
                .link_libc = true,
                .strip = s,
            });
            mod.addImport("build_options", bo);
            if (am) |a| mod.addImport("assets", a);
            return mod;
        }
    }.m;

    const core = mk(b, "src/snail/core.zig", target, optimize, strip, build_options_mod, assets_mod);
    if (options.enable_harfbuzz) core.linkSystemLibrary("harfbuzz", .{});

    const cpu = mk(b, "src/snail/render/backend/cpu/root.zig", target, optimize, strip, build_options_mod, assets_mod);
    cpu.addImport("snail_core", core);

    const gl = mk(b, "src/snail/render/backend/gl/root.zig", target, optimize, strip, build_options_mod, assets_mod);
    gl.addImport("snail_core", core);
    // snail_gl links NO OpenGL: it's a pure-data contract (shader sources +
    // GlProgram layout + binding order), making no live GL calls. GL linkage is
    // the caller's, who owns the context — same as snail_vulkan links no Vulkan.

    const vk = mk(b, "src/snail/render/backend/vulkan/root.zig", target, optimize, strip, build_options_mod, assets_mod);
    vk.addImport("snail_core", core);
    vk.addImport("vulkan_shaders", vk_shaders);
    if (options.enable_vulkan) vk.linkSystemLibrary("vulkan", .{});

    const facade = if (public_name) |name| b.addModule(name, .{
        .root_source_file = b.path("src/snail/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
    }) else mk(b, "src/snail/root.zig", target, optimize, strip, build_options_mod, assets_mod);
    if (public_name != null) {
        facade.addImport("build_options", build_options_mod);
        if (assets_mod) |a| facade.addImport("assets", a);
    }
    facade.addImport("snail_core", core);
    facade.addImport("snail_cpu", cpu);
    facade.addImport("snail_gl", gl);
    facade.addImport("snail_vulkan", vk);
    return .{ .core = core, .cpu = cpu, .gl = gl, .vulkan = vk, .facade = facade };
}

fn buildSnailGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
    public_name: ?[]const u8,
) *std.Build.Module {
    return buildSnailGraphFull(b, target, optimize, build_options_mod, options, vk_shaders, public_name, null, null).facade;
}

fn createSnailModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_mod: *std.Build.Module,
    options: ModuleOptions,
    vk_shaders: *std.Build.Module,
) *std.Build.Module {
    return buildSnailGraph(b, target, optimize, build_options_mod, options, vk_shaders, null);
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
    return buildSnailGraph(b, config.target, config.optimize, options_mod, config.core_options, vk_shaders_mod, "snail");
}

fn addSnailHelpersModule(
    b: *std.Build,
    config: BuildConfig,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    return b.addModule("snail-helpers", .{
        .root_source_file = b.path("src/snail-helpers/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{.{ .name = "snail", .module = snail_mod }},
    });
}

fn createReleaseHelpersModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    snail_mod: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/snail-helpers/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "snail", .module = snail_mod }},
    });
}

const ProjectModules = struct {
    assets: *std.Build.Module,
    support: *std.Build.Module,
    options: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    snail: *std.Build.Module,
    snail_helpers: *std.Build.Module,
};

fn addTestSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const test_step = b.step("test", "Run unit tests");
    // The snail library is a module graph (core + per-backend + facade);
    // each module's tests run in their own artifact.
    const test_graph = buildSnailGraphFull(b, config.target, config.optimize, modules.options, config.core_options, modules.vk_shaders, null, modules.assets, null);
    inline for (.{ test_graph.core, test_graph.cpu, test_graph.gl, test_graph.vulkan, test_graph.facade }) |m| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = m })).step);
    }

    const helpers_test_module = b.createModule(.{
        .root_source_file = b.path("src/snail-helpers/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "assets", .module = modules.assets },
        },
    });
    const helpers_unit_tests = b.addTest(.{ .root_module = helpers_test_module });
    const run_helpers_unit_tests = b.addRunArtifact(helpers_unit_tests);
    test_step.dependOn(&run_helpers_unit_tests.step);

    const autohint_compare_test_module = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_compare.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-helpers", .module = modules.snail_helpers },
        },
    });
    const autohint_compare_tests = b.addTest(.{ .root_module = autohint_compare_test_module });
    const run_autohint_compare_tests = b.addRunArtifact(autohint_compare_tests);
    test_step.dependOn(&run_autohint_compare_tests.step);

    const character_diff_test_module = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_character_diff.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-helpers", .module = modules.snail_helpers },
            .{ .name = "support", .module = createSupportModule(b, config.target, config.optimize) },
        },
    });
    const character_diff_tests = b.addTest(.{ .root_module = character_diff_test_module });
    test_step.dependOn(&b.addRunArtifact(character_diff_tests).step);

    const test_valgrind_step = b.step("test-valgrind", "Run unit tests under Valgrind");
    const vg = buildSnailGraphFull(b, config.target, config.optimize, modules.options, config.core_options, modules.vk_shaders, null, modules.assets, true);
    inline for (.{ vg.core, vg.cpu, vg.gl, vg.vulkan, vg.facade }) |m| {
        const vt = b.addTest(.{ .root_module = m });
        configureValgrindTest(vt);
        test_valgrind_step.dependOn(&b.addRunArtifact(vt).step);
    }
}

fn addScreenshotSteps(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const release_snail_mod = createSnailModule(b, config.target, .ReleaseFast, modules.options, config.core_options, modules.vk_shaders);
    const release_support_mod = createSupportModule(b, config.target, .ReleaseFast);
    const release_helpers_mod = createReleaseHelpersModule(b, config.target, release_snail_mod);
    const embed_vulkan_mod = createEmbedVulkanModule(b, config.target, .ReleaseFast, release_snail_mod);
    const embed_gl_mod = createEmbedGlModule(b, config.target, .ReleaseFast, release_snail_mod);

    // CPU screenshot.
    const screenshot_cpu_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const screenshot_cpu_exe = b.addExecutable(.{ .name = "snail-screenshot", .root_module = screenshot_cpu_mod });
    const run_screenshot_cpu = b.addRunArtifact(screenshot_cpu_exe);
    const screenshot_cpu_step = b.step("run-screenshot", "Render the demo through the CPU backend and write zig-out/demo-screenshot.tga");
    screenshot_cpu_step.dependOn(&run_screenshot_cpu.step);

    // Composable autohint policy comparison — CPU backend.
    const autohint_shot_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_screenshot.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(autohint_shot_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const autohint_shot_exe = b.addExecutable(.{ .name = "snail-autohint-screenshot", .root_module = autohint_shot_mod });
    const run_autohint_shot = b.addRunArtifact(autohint_shot_exe);
    const autohint_shot_step = b.step("run-autohint-screenshot", "Render the composable autohint policy comparison through the CPU backend and write zig-out/autohint-screenshot.tga");
    autohint_shot_step.dependOn(&run_autohint_shot.step);

    // Autohint xy policy vs TrueType agreement metric + overlay — CPU backend.
    const autohint_diff_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_diff.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const autohint_diff_exe = b.addExecutable(.{ .name = "snail-autohint-diff", .root_module = autohint_diff_mod });
    const run_autohint_diff = b.addRunArtifact(autohint_diff_exe);
    const autohint_diff_step = b.step("run-autohint-diff", "Render the autohint xy policy vs TrueType at every demo ppem, print a disagreement score and write zig-out/autohint-diff.tga");
    autohint_diff_step.dependOn(&run_autohint_diff.step);

    const character_diff_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_character_diff.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const character_diff_exe = b.addExecutable(.{ .name = "snail-autohint-character-diff", .root_module = character_diff_mod });
    const run_character_diff = b.addRunArtifact(character_diff_exe);
    const character_diff_step = b.step("run-autohint-character-diff", "Write per-character TT/autohint contact sheets and metrics under zig-out/autohint-character-diff");
    character_diff_step.dependOn(&run_character_diff.step);

    // Proportional-face spot check — CPU backend.
    const prop_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/autohint_proportional.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const prop_exe = b.addExecutable(.{ .name = "snail-autohint-prop", .root_module = prop_mod });
    const prop_step = b.step("run-autohint-prop", "Render the autohint policies on a proportional TT-hinted face → zig-out/autohint-prop.tga");
    prop_step.dependOn(&b.addRunArtifact(prop_exe).step);

    // RESEARCH PROBE: TT bytecode ppem-independence analysis (internal types).
    const tt_probe_mod = b.createModule(.{
        .root_source_file = b.path("src/snail/tt_ppem_probe.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
        },
    });
    const tt_probe_exe = b.addExecutable(.{ .name = "snail-tt-probe", .root_module = tt_probe_mod });
    const run_tt_probe = b.addRunArtifact(tt_probe_exe);
    const tt_probe_step = b.step("run-tt-probe", "Probe whether TrueType hinting output is a ppem-independent per-glyph function");
    tt_probe_step.dependOn(&run_tt_probe.step);

    // Banner screenshot — full interactive-demo scene through CPU backend.
    const banner_screenshot_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/banner_screenshot.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    const banner_screenshot_exe = b.addExecutable(.{ .name = "snail-banner-screenshot", .root_module = banner_screenshot_mod });
    const run_banner_screenshot = b.addRunArtifact(banner_screenshot_exe);
    const banner_screenshot_step = b.step("run-banner-screenshot", "Render the full banner scene through the CPU backend and write zig-out/banner-screenshot.tga");
    banner_screenshot_step.dependOn(&run_banner_screenshot.step);

    // Banner screenshot — GL 3.3 offscreen.
    const banner_screenshot_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/banner_screenshot_gl.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(banner_screenshot_gl_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const banner_screenshot_gl_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-gl", .root_module = banner_screenshot_gl_mod });
    const run_banner_screenshot_gl = b.addRunArtifact(banner_screenshot_gl_exe);
    const banner_screenshot_gl_step = b.step("run-banner-screenshot-gl", "Render the full banner scene through GL and write zig-out/banner-screenshot-gl.tga");
    banner_screenshot_gl_step.dependOn(&run_banner_screenshot_gl.step);

    // Banner screenshot — GLES 3.0 offscreen.
    const banner_screenshot_gles30_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/banner_screenshot_gles30.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(banner_screenshot_gles30_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const banner_screenshot_gles30_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-gles30", .root_module = banner_screenshot_gles30_mod });
    const run_banner_screenshot_gles30 = b.addRunArtifact(banner_screenshot_gles30_exe);
    const banner_screenshot_gles30_step = b.step("run-banner-screenshot-gles30", "Render the full banner scene through GLES 3.0 and write zig-out/banner-screenshot-gles30.tga");
    banner_screenshot_gles30_step.dependOn(&run_banner_screenshot_gles30.step);

    // Banner screenshot — Vulkan offscreen.
    if (config.core_options.enable_vulkan) {
        const release_vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod);
        const banner_screenshot_vk_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/banner_screenshot_vulkan.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-helpers", .module = release_helpers_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = release_vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
        const banner_screenshot_vk_exe = b.addExecutable(.{ .name = "snail-banner-screenshot-vulkan", .root_module = banner_screenshot_vk_mod });
        const run_banner_screenshot_vk = b.addRunArtifact(banner_screenshot_vk_exe);
        const banner_screenshot_vk_step = b.step("run-banner-screenshot-vulkan", "Render the full banner scene through Vulkan and write zig-out/banner-screenshot-vulkan.tga");
        banner_screenshot_vk_step.dependOn(&run_banner_screenshot_vk.step);
    }

    // GL screenshot.
    const screenshot_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot_gl.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(screenshot_gl_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const screenshot_gl_exe = b.addExecutable(.{ .name = "snail-screenshot-gl", .root_module = screenshot_gl_mod });
    const run_screenshot_gl = b.addRunArtifact(screenshot_gl_exe);
    const screenshot_gl_step = b.step("run-screenshot-gl", "Render the demo through the GL backend and write zig-out/demo-screenshot-gl.tga");
    screenshot_gl_step.dependOn(&run_screenshot_gl.step);

    // Offscreen Vulkan game-scene screenshot (depth-tested) → zig-out/game-vulkan.tga.
    if (config.core_options.enable_vulkan) {
        const release_vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod);
        const game_shot_vk_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/game_screenshot_vulkan.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-helpers", .module = release_helpers_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = release_vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
        addGameShaderSpirv(b, game_shot_vk_mod);
        const game_shot_vk_exe = b.addExecutable(.{ .name = "snail-game-screenshot-vulkan", .root_module = game_shot_vk_mod });
        const run_game_shot_vk = b.addRunArtifact(game_shot_vk_exe);
        const game_shot_vk_step = b.step("run-game-screenshot-vulkan", "Render the game scene offscreen through Vulkan → zig-out/game-vulkan.tga");
        game_shot_vk_step.dependOn(&run_game_shot_vk.step);
    }

    // Offscreen (no-window) game-scene screenshot per GL backend — the game's
    // headless verification harness. Writes zig-out/game-<backend>.tga.
    if (config.core_options.enable_gl33 or config.core_options.enable_gl44 or config.core_options.enable_gles30) {
        const game_shot_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/game_screenshot.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-helpers", .module = release_helpers_mod },
                .{ .name = "support", .module = release_support_mod },
            },
        });
        configureEglOffscreenModule(game_shot_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
        const game_shot_exe = b.addExecutable(.{ .name = "snail-game-screenshot", .root_module = game_shot_mod });
        const run_game_shot = b.addRunArtifact(game_shot_exe);
        const game_shot_step = b.step("run-game-screenshot", "Render the game scene offscreen per GL backend → zig-out/game-<backend>.tga");
        game_shot_step.dependOn(&run_game_shot.step);
    }

    // CPU-vs-GL pixel parity gate over the shared content scene.
    const backend_compare_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/backend_compare.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(backend_compare_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const backend_compare_exe = b.addExecutable(.{ .name = "snail-backend-compare", .root_module = backend_compare_mod });
    const run_backend_compare = b.addRunArtifact(backend_compare_exe);
    const backend_compare_step = b.step("run-backend-compare", "Render the content scene through CPU and GL and fail if they diverge beyond the AA tolerance");
    backend_compare_step.dependOn(&run_backend_compare.step);

    // Gamma conformance gate: interior (full-coverage) pixels of a controlled
    // solid scene, CPU vs GL33 vs GLES30, checked exactly against the analytic
    // encode. Immune to AA-edge differences that backend-compare tolerates.
    const gamma_probe_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/gamma_probe.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(gamma_probe_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const gamma_probe_exe = b.addExecutable(.{ .name = "snail-gamma-probe", .root_module = gamma_probe_mod });
    const run_gamma_probe = b.addRunArtifact(gamma_probe_exe);
    const gamma_probe_step = b.step("run-gamma-probe", "Check interior-pixel gamma (encode round-trip) across CPU/GL33/GLES30");
    gamma_probe_step.dependOn(&run_gamma_probe.step);

    // GLES screenshot.
    const screenshot_gles30_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/screenshot_gles30.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = release_snail_mod },
            .{ .name = "snail-helpers", .module = release_helpers_mod },
            .{ .name = "support", .module = release_support_mod },
        },
    });
    configureEglOffscreenModule(screenshot_gles30_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    const screenshot_gles30_exe = b.addExecutable(.{ .name = "snail-screenshot-gles30", .root_module = screenshot_gles30_mod });
    const run_screenshot_gles30 = b.addRunArtifact(screenshot_gles30_exe);
    const screenshot_gles30_step = b.step("run-screenshot-gles30", "Render the demo through the GLES30 backend and write zig-out/demo-screenshot-gles30.tga");
    screenshot_gles30_step.dependOn(&run_screenshot_gles30.step);

    // Vulkan screenshot.
    if (config.core_options.enable_vulkan) {
        const vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod);
        const screenshot_vulkan_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/screenshot_vulkan.zig"),
            .target = config.target,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .imports = &.{
                .{ .name = "assets", .module = modules.assets },
                .{ .name = "snail", .module = release_snail_mod },
                .{ .name = "snail-helpers", .module = release_helpers_mod },
                .{ .name = "support", .module = release_support_mod },
                .{ .name = "demo_platform_vulkan", .module = vk_platform_mod },
                .{ .name = "embed_vulkan", .module = embed_vulkan_mod },
            },
        });
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
    const demo_embed_gl_mod = createEmbedGlModule(b, config.target, demo_optimize, modules.snail);
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/main.zig"),
        .target = config.target,
        .optimize = demo_optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-helpers", .module = modules.snail_helpers },
            .{ .name = "support", .module = modules.support },
            .{ .name = "build_options", .module = modules.options },
            .{ .name = "embed_gl", .module = demo_embed_gl_mod },
        },
    });
    // Interactive demo wraps every backend's platform layer: Wayland +
    // EGL/OpenGL + Vulkan + libwayland-client. The platform sources live
    // alongside the demo and reference snail's public types only.
    demo_mod.linkSystemLibrary("wayland-client", .{});
    demo_mod.addIncludePath(b.path("src/demo/platform"));
    demo_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
    demo_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/presentation-time-client-protocol.c") });
    if (config.core_options.enable_gl33 or config.core_options.enable_gl44 or config.core_options.enable_gles30) {
        demo_mod.linkSystemLibrary("EGL", .{});
        demo_mod.linkSystemLibrary("wayland-egl", .{});
    }
    if (config.core_options.enable_gl33 or config.core_options.enable_gl44) demo_mod.linkSystemLibrary("OpenGL", .{});
    if (config.core_options.enable_gles30) demo_mod.linkSystemLibrary("GLESv2", .{});
    if (config.core_options.enable_vulkan) demo_mod.linkSystemLibrary("vulkan", .{});
    if (config.core_options.enable_harfbuzz) demo_mod.linkSystemLibrary("harfbuzz", .{});

    const demo_exe = b.addExecutable(.{ .name = "snail-demo", .root_module = demo_mod });
    b.installArtifact(demo_exe);
    const run_demo = b.addRunArtifact(demo_exe);
    if (b.args) |args| run_demo.addArgs(args);
    const run_step = b.step("run", "Run the interactive Wayland banner demo");
    run_step.dependOn(&run_demo.step);
}

/// Compile the game's custom Vulkan material shaders (which #include snail's
/// coverage + records GLSL) to SPIR-V and inject them into `mod` as anonymous
/// imports for `game/game_shaders.zig`.
fn addGameShaderSpirv(b: *std.Build, mod: *std.Build.Module) void {
    const game_glsl = [_][]const u8{"src/demo/game/glsl"};
    const vert = vulkan_shaders.compileCallerShader(b, b.path("src/demo/game/glsl/game_material.vert"), "-fshader-stage=vert", "game_material.vert.spv", &.{}, &game_glsl);
    const frag = vulkan_shaders.compileCallerShader(b, b.path("src/demo/game/glsl/game_material.frag"), "-fshader-stage=frag", "game_material.frag.spv", &.{}, &game_glsl);
    mod.addAnonymousImport("game_material.vert.spv", .{ .root_source_file = vert });
    mod.addAnonymousImport("game_material.frag.spv", .{ .root_source_file = frag });
}

fn addGameDemoStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    // The game demo cycles the GL family (gl33/gl44/gles30) at runtime — a 3D
    // scene whose custom material shader samples snail glyph coverage. Needs the
    // Wayland-EGL platform layer + the xdg-shell C protocol. (Vulkan lands in a
    // later stage.)
    if (!(config.core_options.enable_gl33 or config.core_options.enable_gl44 or config.core_options.enable_gles30)) return;

    const game_optimize = if (b.user_input_options.contains("optimize")) config.optimize else .ReleaseFast;
    const game_embed_gl_mod = createEmbedGlModule(b, config.target, game_optimize, modules.snail);
    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/game.zig"),
        .target = config.target,
        .optimize = game_optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "assets", .module = modules.assets },
            .{ .name = "snail", .module = modules.snail },
            .{ .name = "snail-helpers", .module = modules.snail_helpers },
            .{ .name = "support", .module = modules.support },
            .{ .name = "build_options", .module = modules.options },
            .{ .name = "embed_gl", .module = game_embed_gl_mod },
        },
    });
    game_mod.linkSystemLibrary("wayland-client", .{});
    game_mod.addIncludePath(b.path("src/demo/platform"));
    game_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/xdg-shell-client-protocol.c") });
    game_mod.addCSourceFile(.{ .file = b.path("src/demo/platform/presentation-time-client-protocol.c") });
    game_mod.linkSystemLibrary("EGL", .{});
    game_mod.linkSystemLibrary("wayland-egl", .{});
    if (config.core_options.enable_gl33 or config.core_options.enable_gl44) game_mod.linkSystemLibrary("OpenGL", .{});
    if (config.core_options.enable_gles30) game_mod.linkSystemLibrary("GLESv2", .{});
    if (config.core_options.enable_vulkan) {
        // vk_scene uses the reference caller renderer; the windowed Vulkan
        // platform is a relative file compiled into game_mod (its own vk cImport
        // via linkSystemLibrary). game/game_shaders.zig gets the material SPIR-V.
        game_mod.addImport("embed_vulkan", createEmbedVulkanModule(b, config.target, game_optimize, modules.snail));
        addGameShaderSpirv(b, game_mod);
        game_mod.linkSystemLibrary("vulkan", .{});
    }
    if (config.core_options.enable_harfbuzz) game_mod.linkSystemLibrary("harfbuzz", .{});

    const game_exe = b.addExecutable(.{ .name = "snail-game-demo", .root_module = game_mod });
    b.installArtifact(game_exe);
    const run_game = b.addRunArtifact(game_exe);
    if (b.args) |args| run_game.addArgs(args);
    const run_step = b.step("run-game", "Run the interactive Wayland 3D game demo (GL family)");
    run_step.dependOn(&run_game.step);
}

pub fn build(b: *std.Build) void {
    const config = parseBuildConfig(b);
    const options_mod = createBuildOptionsModule(b, config.core_options);
    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const support_mod = createSupportModule(b, config.target, config.optimize);
    const vk_shaders_mod = vulkan_shaders.createModule(b, config.core_options.enable_vulkan);

    const snail_mod = addSnailModule(b, config, options_mod, vk_shaders_mod);
    const snail_helpers_mod = addSnailHelpersModule(b, config, snail_mod);
    const modules = ProjectModules{
        .assets = assets_mod,
        .support = support_mod,
        .options = options_mod,
        .vk_shaders = vk_shaders_mod,
        .snail = snail_mod,
        .snail_helpers = snail_helpers_mod,
    };

    addTestSteps(b, config, modules);
    addScreenshotSteps(b, config, modules);
    addInteractiveDemoStep(b, config, modules);
    addGameDemoStep(b, config, modules);
    addBenchStep(b, config, modules);
}

fn addBenchStep(
    b: *std.Build,
    config: BuildConfig,
    modules: ProjectModules,
) void {
    const release_snail_mod = createSnailModule(b, config.target, .ReleaseFast, modules.options, config.core_options, modules.vk_shaders);
    const release_support_mod = createSupportModule(b, config.target, .ReleaseFast);
    const release_helpers_mod = createReleaseHelpersModule(b, config.target, release_snail_mod);
    const embed_gl_mod = createEmbedGlModule(b, config.target, .ReleaseFast, release_snail_mod);

    const offscreen_gl_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/platform/offscreen_gl.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    offscreen_gl_mod.linkSystemLibrary("EGL", .{});

    var bench_imports: std.ArrayListUnmanaged(std.Build.Module.Import) = .empty;
    bench_imports.appendSlice(b.allocator, &.{
        .{ .name = "assets", .module = modules.assets },
        .{ .name = "snail", .module = release_snail_mod },
        .{ .name = "snail-helpers", .module = release_helpers_mod },
        .{ .name = "support", .module = release_support_mod },
        .{ .name = "build_options", .module = modules.options },
        .{ .name = "demo_platform_offscreen_gl", .module = offscreen_gl_mod },
    }) catch @panic("OOM");

    if (config.core_options.enable_vulkan) {
        const release_vk_platform_mod = createDemoVulkanPlatformModule(b, config.target, .ReleaseFast, modules.options, release_snail_mod);
        bench_imports.append(b.allocator, .{ .name = "demo_platform_vulkan", .module = release_vk_platform_mod }) catch @panic("OOM");
        const embed_vulkan_mod = createEmbedVulkanModule(b, config.target, .ReleaseFast, release_snail_mod);
        bench_imports.append(b.allocator, .{ .name = "embed_vulkan", .module = embed_vulkan_mod }) catch @panic("OOM");
    }

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/bench.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = bench_imports.items,
    });
    configureEglOffscreenModule(bench_mod, modules.options, config.core_options, modules.vk_shaders, embed_gl_mod);
    bench_mod.linkSystemLibrary("freetype2", .{});

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_mod });
    b.installArtifact(bench_exe);
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run the snail benchmark harness (writes a markdown report to stdout). Set SNAIL_BENCH_ONLY=<sections> to focus.");
    bench_step.dependOn(&run_bench.step);
}
