//! The module-creation layer of the build: constructors for every
//! `std.Build.Module` the project wires together (the public `snail` module and
//! its raster/render-state companions, the reference caller renderers, demo
//! platform glue), plus the small config/aggregate types that thread through
//! the step functions in `build.zig`. These are leaves — the step functions
//! call them, never the reverse — so they live here and `build.zig` stays the
//! orchestrator.

const std = @import("std");
const slang_shaders = @import("slang_shaders.zig");

pub const DemoEntry = enum {
    banner,
    game,
    terminal,
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

pub fn selectDemoEntry(b: *std.Build, mod: *std.Build.Module, entry: DemoEntry) void {
    const opts = b.addOptions();
    opts.addOption(DemoEntry, "value", entry);
    mod.addImport("demo_entry", opts.createModule());
}

pub const GlLibraries = struct {
    desktop: bool = false,
    es: bool = false,
};

pub fn configureEglOffscreenModule(
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

pub fn createDemoVulkanPlatformModule(
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
pub fn createEmbedVulkanModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    vulkan_types_mod: *std.Build.Module,
    shaders_reflection_mod: *std.Build.Module,
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
            .{ .name = "snail_shaders", .module = shaders_reflection_mod },
        },
    });
}

pub fn createDemoVulkanTypesModule(
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
pub fn createEmbedGlModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    snail_mod: *std.Build.Module,
    render_state_mod: *std.Build.Module,
    shaders_mod: *std.Build.Module,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo/render/gl/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "snail", .module = snail_mod },
            .{ .name = "render-state", .module = render_state_mod },
            .{ .name = "snail_shaders", .module = shaders_mod },
        },
    });
    return mod;
}

pub fn createSupportModule(
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
pub fn createSnailModuleFull(
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

pub fn createRasterModule(
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
    raster.addImport("snail-raster-support", b.createModule(.{
        .root_source_file = b.path("src/snail/raster_support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "snail", .module = snail_mod }},
    }));
    if (assets_mod) |assets| raster.addImport("assets", assets);
    return raster;
}

pub fn createRenderStateModule(
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

pub fn createSnailModule(
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

pub const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub fn parseBuildConfig(b: *std.Build) BuildConfig {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };
}

pub fn addSnailModule(
    b: *std.Build,
    config: BuildConfig,
) *std.Build.Module {
    return createSnailModuleFull(b, config.target, config.optimize, "snail", null, null);
}

pub const ProjectModules = struct {
    assets: *std.Build.Module,
    support: *std.Build.Module,
    vk_shaders: *std.Build.Module,
    demo_vulkan_types: *std.Build.Module,
    snail: *std.Build.Module,
    render_state: *std.Build.Module,
    raster: *std.Build.Module,
    /// The public aggregate `snail-shaders` module (every generated
    /// target; needs slangc when consumed). Used by the
    /// artifact-contract/public-API tests, which deliberately cover all
    /// target accessors.
    shaders: *std.Build.Module,
    /// Its laid-out root file, reusable as a test-compilation root.
    shaders_root: std.Build.LazyPath,
    /// Per-target scopes of the same accessor API (same import name
    /// `snail_shaders` in consumers): each depends only on its own
    /// targets' generation steps, so e.g. the GL demos never compile
    /// WGSL/HLSL/MSL.
    shaders_gl: *std.Build.Module, // glsl330 + gles300
    shaders_glsl330: *std.Build.Module, // desktop GL only (perf rows)
    shaders_wgsl: *std.Build.Module,
    shaders_hlsl: *std.Build.Module,
    shaders_msl: *std.Build.Module,
    /// Empty-target scope: root.zig + the generated parameter-ABI module
    /// (reflection.zig) only. For consumers that need the reflected
    /// PushConstants/bindings but embed no artifacts (the Vulkan
    /// reference renderer — its SPIR-V arrives via `vulkan_shaders`).
    shaders_reflection: *std.Build.Module,
    /// The game material family's build-time GL dialects (anonymous-import
    /// wiring via addGameShaderGl).
    game_material_gl: []const slang_shaders.Entry,
};

/// Compile the game's custom Vulkan material shaders (native Slang; the
/// caller-authored family src/demo/game/slang/game_material.slang imports
/// snail's text_sample module) to SPIR-V and inject them into `mod` as
/// anonymous imports for `game/game_shaders.zig`.
pub fn addGameShaderSpirv(b: *std.Build, mod: *std.Build.Module) void {
    const spv = slang_shaders.vulkanGameMaterialSpv(b);
    mod.addAnonymousImport("game_material.vert.spv", .{ .root_source_file = spv.vert });
    mod.addAnonymousImport("game_material.frag.spv", .{ .root_source_file = spv.frag });
}

/// Inject the game material family's build-time GL dialects into `mod` as
/// anonymous imports for `game/gl_material.zig`: an artifact at
/// `glsl330/game_material.vert.glsl` becomes `game_material.vert.glsl330`
/// (and so on for the three other stage/dialect combinations).
pub fn addGameShaderGl(b: *std.Build, mod: *std.Build.Module, entries: []const slang_shaders.Entry) void {
    for (entries) |e| {
        const dialect = std.fs.path.dirname(e.sub_path).?;
        const stem = std.fs.path.stem(e.sub_path); // e.g. "game_material.vert"
        mod.addAnonymousImport(b.fmt("{s}.{s}", .{ stem, dialect }), .{ .root_source_file = e.file });
    }
}
