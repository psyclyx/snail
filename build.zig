const std = @import("std");

pub const DemoRenderer = enum { gl44, gl33, vulkan, cpu };

fn assembledGlslSource(
    allocator: std.mem.Allocator,
    comptime wrapper_path: []const u8,
    comptime include_directive: []const u8,
    comptime body_path: []const u8,
) []const u8 {
    const wrapper = @embedFile(wrapper_path);
    const body = @embedFile(body_path);
    const include_idx = std.mem.indexOf(u8, wrapper, include_directive) orelse @panic("missing GLSL include directive");
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        wrapper[0..include_idx],
        body,
        wrapper[include_idx + include_directive.len ..],
    }) catch @panic("out of memory assembling GLSL source");
}

fn configureCoreModule(
    mod: *std.Build.Module,
    opts: *std.Build.Step.Options,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) void {
    mod.addOptions("build_options", opts);
    if (opengl) mod.linkSystemLibrary("OpenGL", .{});
    mod.addImport("vulkan_shaders", vk_shaders);
    if (vulkan) mod.linkSystemLibrary("vulkan", .{});
    if (harfbuzz) mod.linkSystemLibrary("harfbuzz", .{});
}

fn configureDemoModule(
    mod: *std.Build.Module,
    b: *std.Build,
    opts: *std.Build.Step.Options,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
    demo_renderer: DemoRenderer,
) void {
    configureCoreModule(mod, opts, opengl, vulkan, harfbuzz, vk_shaders);
    switch (demo_renderer) {
        .gl44, .gl33 => {
            mod.linkSystemLibrary("wayland-client", .{});
            mod.linkSystemLibrary("wayland-egl", .{});
            mod.linkSystemLibrary("EGL", .{});
            mod.addIncludePath(b.path("src/render"));
            mod.addCSourceFile(.{ .file = b.path("src/render/xdg-shell-client-protocol.c") });
        },
        .vulkan => {
            mod.linkSystemLibrary("wayland-client", .{});
            mod.addIncludePath(b.path("src/render"));
            mod.addCSourceFile(.{ .file = b.path("src/render/xdg-shell-client-protocol.c") });
        },
        .cpu => {
            mod.linkSystemLibrary("wayland-client", .{});
            mod.addIncludePath(b.path("src/render"));
            mod.addCSourceFile(.{ .file = b.path("src/render/xdg-shell-client-protocol.c") });
        },
    }
}

fn configureEglOffscreenModule(
    mod: *std.Build.Module,
    opts: *std.Build.Step.Options,
    opengl: bool,
    vulkan: bool,
    harfbuzz: bool,
    vk_shaders: *std.Build.Module,
) void {
    configureCoreModule(mod, opts, opengl, vulkan, harfbuzz, vk_shaders);
    mod.linkSystemLibrary("EGL", .{});
}

/// For use as a dependency: returns a module with only the core snail library.
/// No demo windowing, no Vulkan — the consumer must provide a GL 3.3+ context.
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const opts = b.addOptions();
    opts.addOption(bool, "enable_profiling", false);
    opts.addOption(bool, "enable_opengl", true);
    opts.addOption(bool, "enable_vulkan", false);
    opts.addOption(bool, "enable_cpu", false);
    opts.addOption(bool, "enable_harfbuzz", true);
    opts.addOption(bool, "force_gl33", false);
    opts.addOption(DemoRenderer, "demo_renderer", .gl44);

    const vk_stub = b.createModule(.{
        .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(mod, opts, true, false, true, vk_stub);
    return mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;
    const enable_opengl = b.option(bool, "opengl", "Enable OpenGL backend") orelse true;
    const enable_vulkan = b.option(bool, "vulkan", "Enable Vulkan backend") orelse false;
    const enable_cpu = b.option(bool, "cpu-renderer", "Enable CPU renderer backend") orelse true;
    const enable_harfbuzz = b.option(bool, "harfbuzz", "Enable HarfBuzz text shaping") orelse true;
    const enable_c_api = b.option(bool, "c-api", "Build the C API libraries") orelse true;
    const demo_renderer = b.option(DemoRenderer, "renderer", "Demo rendering backend (default: gl44)") orelse .gl44;

    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", enable_profiling);
    options.addOption(bool, "enable_opengl", enable_opengl);
    options.addOption(bool, "enable_vulkan", enable_vulkan);
    options.addOption(bool, "enable_cpu", enable_cpu);
    options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    options.addOption(bool, "force_gl33", demo_renderer == .gl33);
    options.addOption(DemoRenderer, "demo_renderer", demo_renderer);

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });

    // ── SPIR-V shader compilation (only when Vulkan enabled) ──
    const vk_shaders_mod: *std.Build.Module = if (enable_vulkan) blk: {
        const shader_dir = b.path("shaders");
        const shared_shader_dir = b.path("src/render/glsl");
        const generated_shaders = b.addWriteFiles();
        const generated_vert = generated_shaders.add("vulkan-generated/snail.vert", assembledGlslSource(
            b.allocator,
            "shaders/snail.vert",
            "#include \"snail_vert_body.glsl\"",
            "src/render/glsl/snail_vert_body.glsl",
        ));
        const generated_frag_text = generated_shaders.add("vulkan-generated/snail_text.frag", assembledGlslSource(
            b.allocator,
            "shaders/snail_text.frag",
            "#include \"snail_text_frag_body.glsl\"",
            "src/render/glsl/snail_text_frag_body.glsl",
        ));
        const generated_frag_colr = generated_shaders.add("vulkan-generated/snail_colr.frag", assembledGlslSource(
            b.allocator,
            "shaders/snail_colr.frag",
            "#include \"snail_colr_frag_body.glsl\"",
            "src/render/glsl/snail_colr_frag_body.glsl",
        ));
        const generated_frag_path = generated_shaders.add("vulkan-generated/snail.frag", assembledGlslSource(
            b.allocator,
            "shaders/snail.frag",
            "#include \"snail_path_frag_body.glsl\"",
            "src/render/glsl/snail_path_frag_body.glsl",
        ));
        const generated_frag_text_sp_dual = generated_shaders.add("vulkan-generated/snail_text_subpixel.frag", assembledGlslSource(
            b.allocator,
            "shaders/snail_text_subpixel.frag",
            "#include \"snail_text_subpixel_body.glsl\"",
            "src/render/glsl/snail_text_subpixel_body.glsl",
        ));

        const compile_vert = b.addSystemCommand(&.{ "glslc", "-fshader-stage=vert" });
        compile_vert.addArg("-I");
        compile_vert.addDirectoryArg(shader_dir);
        compile_vert.addArg("-I");
        compile_vert.addDirectoryArg(shared_shader_dir);
        compile_vert.addFileArg(generated_vert);
        compile_vert.addArg("-o");
        const vert_spv = compile_vert.addOutputFileArg("snail.vert.spv");

        const compile_frag_text = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_frag_text.addArg("-I");
        compile_frag_text.addDirectoryArg(shader_dir);
        compile_frag_text.addArg("-I");
        compile_frag_text.addDirectoryArg(shared_shader_dir);
        compile_frag_text.addFileArg(generated_frag_text);
        compile_frag_text.addArg("-o");
        const frag_text_spv = compile_frag_text.addOutputFileArg("snail_text.frag.spv");

        const compile_frag_colr = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_frag_colr.addArg("-I");
        compile_frag_colr.addDirectoryArg(shader_dir);
        compile_frag_colr.addArg("-I");
        compile_frag_colr.addDirectoryArg(shared_shader_dir);
        compile_frag_colr.addFileArg(generated_frag_colr);
        compile_frag_colr.addArg("-o");
        const frag_colr_spv = compile_frag_colr.addOutputFileArg("snail_colr.frag.spv");

        const compile_frag_path = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag" });
        compile_frag_path.addArg("-I");
        compile_frag_path.addDirectoryArg(shader_dir);
        compile_frag_path.addArg("-I");
        compile_frag_path.addDirectoryArg(shared_shader_dir);
        compile_frag_path.addFileArg(generated_frag_path);
        compile_frag_path.addArg("-o");
        const frag_path_spv = compile_frag_path.addOutputFileArg("snail_path.frag.spv");

        const compile_frag_text_sp_dual = b.addSystemCommand(&.{ "glslc", "-fshader-stage=frag", "-DSNAIL_DUAL_SOURCE=1" });
        compile_frag_text_sp_dual.addArg("-I");
        compile_frag_text_sp_dual.addDirectoryArg(shader_dir);
        compile_frag_text_sp_dual.addArg("-I");
        compile_frag_text_sp_dual.addDirectoryArg(shared_shader_dir);
        compile_frag_text_sp_dual.addFileArg(generated_frag_text_sp_dual);
        compile_frag_text_sp_dual.addArg("-o");
        const frag_text_sp_dual_spv = compile_frag_text_sp_dual.addOutputFileArg("snail_text_subpixel_dual.frag.spv");

        const mod = b.createModule(.{
            .root_source_file = b.path("src/render/vulkan_shaders.zig"),
        });
        mod.addAnonymousImport("snail.vert.spv", .{ .root_source_file = vert_spv });
        mod.addAnonymousImport("snail_text.frag.spv", .{ .root_source_file = frag_text_spv });
        mod.addAnonymousImport("snail_colr.frag.spv", .{ .root_source_file = frag_colr_spv });
        mod.addAnonymousImport("snail_path.frag.spv", .{ .root_source_file = frag_path_spv });
        mod.addAnonymousImport("snail_text_subpixel_dual.frag.spv", .{ .root_source_file = frag_text_sp_dual_spv });
        break :blk mod;
    } else b.createModule(.{
        .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
    });

    // ── C API libraries ──
    if (enable_c_api) {
        const lib_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        configureCoreModule(lib_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

        const shared_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .dynamic });
        b.installArtifact(shared_lib);

        const static_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .static });
        b.installArtifact(static_lib);

        b.installFile("include/snail.h", "include/snail.h");
    }

    // ── Zig module (for downstream zig package consumers) ──
    const snail_mod = b.addModule("snail", .{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureCoreModule(snail_mod, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    // ── Demo executable ──
    const demo_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureDemoModule(demo_module, b, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod, demo_renderer);

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
    game_demo_options.addOption(DemoRenderer, "demo_renderer", .gl44);

    const game_demo_module = b.createModule(.{
        .root_source_file = b.path("src/game_demo.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureDemoModule(game_demo_module, b, game_demo_options, true, false, enable_harfbuzz, vk_shaders_mod, .gl44);

    const game_demo_exe = b.addExecutable(.{ .name = "snail-game-demo", .root_module = game_demo_module });
    const install_game_demo = b.addInstallArtifact(game_demo_exe, .{});

    const game_demo_step = b.step("game-demo", "Build the OpenGL game-style demo");
    game_demo_step.dependOn(&install_game_demo.step);

    const run_game_demo = b.addRunArtifact(game_demo_exe);
    if (b.args) |args| run_game_demo.addArgs(args);
    const run_game_demo_step = b.step("run-game-demo", "Run the OpenGL game-style demo");
    run_game_demo_step.dependOn(&run_game_demo.step);

    // ── Tests ──
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/snail.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(test_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    if (enable_c_api) {
        const c_api_test_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "assets", .module = assets_mod }},
        });
        configureCoreModule(c_api_test_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
        const c_api_tests = b.addTest(.{ .root_module = c_api_test_module });
        const run_c_api_tests = b.addRunArtifact(c_api_tests);
        test_step.dependOn(&run_c_api_tests.step);
    }

    // ── Extra module tests (cpu_renderer, etc.) ──
    const extra_test_module = b.createModule(.{
        .root_source_file = b.path("src/cpu_renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(extra_test_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
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
    configureEglOffscreenModule(bench_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    bench_module.linkSystemLibrary("freetype2", .{});

    const bench_exe = b.addExecutable(.{ .name = "snail-bench", .root_module = bench_module });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run consolidated benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ── CPU text profile target (for use under perf record) ──
    const profile_text_module = b.createModule(.{
        .root_source_file = b.path("src/profile_cpu_text.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .omit_frame_pointer = false,
        .link_libc = true, // HarfBuzz cImport needs libc headers
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureCoreModule(profile_text_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);
    const profile_text_exe = b.addExecutable(.{ .name = "snail-profile-cpu-text", .root_module = profile_text_module });
    const install_profile_text = b.addInstallArtifact(profile_text_exe, .{});
    const profile_text_step = b.step("profile-cpu-text", "Build CPU-text profile target (run zig-out/bin/snail-profile-cpu-text [iters] [serial|threaded])");
    profile_text_step.dependOn(&install_profile_text.step);

    // ── Headless demo screenshot ──
    const screenshot_module = b.createModule(.{
        .root_source_file = b.path("src/screenshot_demo.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureEglOffscreenModule(screenshot_module, options, enable_opengl, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

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
    compare_options.addOption(DemoRenderer, "demo_renderer", .gl44);

    const backend_compare_module = b.createModule(.{
        .root_source_file = b.path("src/backend_compare.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    configureEglOffscreenModule(backend_compare_module, compare_options, true, enable_vulkan, enable_harfbuzz, vk_shaders_mod);

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
