const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_profiling = b.option(bool, "profile", "Enable profiling instrumentation") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "enable_profiling", enable_profiling);

    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });

    // ── Shared library ──
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_module.addOptions("build_options", options);
    lib_module.linkSystemLibrary("glfw3", .{});
    lib_module.linkSystemLibrary("gl", .{});

    const shared_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .dynamic });
    b.installArtifact(shared_lib);

    const static_lib = b.addLibrary(.{ .name = "snail", .root_module = lib_module, .linkage = .static });
    b.installArtifact(static_lib);

    // Install header
    b.installFile("include/snail.h", "include/snail.h");

    // Install pkgconfig
    // (generated at build time — see below)

    // ── Demo executable ──
    const demo_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "assets", .module = assets_mod }},
    });
    demo_module.addOptions("build_options", options);
    demo_module.linkSystemLibrary("glfw3", .{});
    demo_module.linkSystemLibrary("gl", .{});

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
    test_module.addOptions("build_options", options);
    test_module.linkSystemLibrary("glfw3", .{});
    test_module.linkSystemLibrary("gl", .{});

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
    bench_cmp_module.addOptions("build_options", options);
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
    bench_hl_module.addOptions("build_options", options);
    bench_hl_module.linkSystemLibrary("glfw3", .{});
    bench_hl_module.linkSystemLibrary("gl", .{});

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
}
