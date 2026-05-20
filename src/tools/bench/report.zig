const std = @import("std");
const build_options = @import("build_options");
const gl = @import("support").gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};

fn ratio(numerator: f64, denominator: f64) f64 {
    return numerator / @max(denominator, 0.001);
}

fn kib(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / 1024.0;
}

fn cpuModelName(buf: []u8) []const u8 {
    const file = std.c.fopen("/proc/cpuinfo", "r") orelse return "unknown";
    defer _ = std.c.fclose(file);
    var read_buf: [4096]u8 = undefined;
    const n = std.c.fread(&read_buf, 1, read_buf.len, file);
    const text = read_buf[0..n];
    const prefix = "model name";
    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |line| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        const out_len = @min(buf.len, value.len);
        @memcpy(buf[0..out_len], value[0..out_len]);
        return buf[0..out_len];
    }
    return "unknown";
}

fn glStringSafe(name: gl.GLenum) []const u8 {
    const ptr = gl.glGetString(name) orelse return "unknown";
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

pub const GlHardwareRow = struct {
    backend: []const u8,
    renderer: []const u8,
    version: []const u8,

    pub fn deinit(self: GlHardwareRow, allocator: std.mem.Allocator) void {
        allocator.free(self.backend);
        allocator.free(self.renderer);
        allocator.free(self.version);
    }
};

pub fn captureGlHardwareRow(allocator: std.mem.Allocator, backend: []const u8) !GlHardwareRow {
    const backend_copy = try allocator.dupe(u8, backend);
    errdefer allocator.free(backend_copy);
    const renderer_copy = try allocator.dupe(u8, glStringSafe(gl.GL_RENDERER));
    errdefer allocator.free(renderer_copy);
    const version_copy = try allocator.dupe(u8, glStringSafe(gl.GL_VERSION));
    return .{
        .backend = backend_copy,
        .renderer = renderer_copy,
        .version = version_copy,
    };
}

pub fn printHardwareTable(gl_rows: []const GlHardwareRow, vulkan_initialized: bool) void {
    var cpu_buf: [256]u8 = undefined;
    const cpu = cpuModelName(&cpu_buf);
    std.debug.print(
        \\## Hardware
        \\
        \\| Component | Detected |
        \\|---|---|
        \\| CPU | {s} |
        \\
    , .{cpu});

    for (gl_rows) |row| {
        std.debug.print(
            "| {s} renderer | {s} |\n| {s} version | {s} |\n",
            .{ row.backend, row.renderer, row.backend, row.version },
        );
    }

    if (comptime build_options.enable_vulkan) {
        if (vulkan_initialized) {
            var vk_buf: [256]u8 = undefined;
            const name = vulkan_platform.physicalDeviceName(&vk_buf) orelse "unknown";
            std.debug.print("| Vulkan device | {s} |\n", .{name});
        }
    } else {
        std.debug.print("| Vulkan | disabled (`zig build run-bench -Dvulkan=false`) |\n", .{});
    }
    std.debug.print("\n", .{});
}

pub fn printPreparationTables(snail_prep: anytype, vector_prep: anytype, ft: anytype) void {
    std.debug.print(
        \\## Preparation
        \\
        \\| Workload | Snail | FreeType | FreeType / Snail |
        \\|---|---:|---:|---:|
        \\| Font load | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| Glyph prep, ASCII | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| Glyph prep, 7 sizes | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| TT hint setup @ 12px | {d:.2} us | n/a | n/a |
        \\| TT hint execute, ASCII @ 12px | {d:.2} us | n/a | n/a |
        \\| TT hint plan, ASCII @ 12px | {d:.2} us | n/a | n/a |
        \\| TT hint context cold, paragraph @ 12px | {d:.2} us | n/a | n/a |
        \\| TT hint context warm, paragraph @ 12px | {d:.2} us | n/a | n/a |
        \\| PathPicture freeze, {d} shapes | {d:.2} us | n/a | n/a |
        \\
        \\## Prepared Resource Memory
        \\
        \\| Resource | Used bytes | Allocated GPU bytes | Used KiB | Allocated KiB |
        \\|---|---:|---:|---:|---:|
        \\| Snail text textures | {d} | {d} | {d:.1} | {d:.1} |
        \\| Snail vector textures | {d} | {d} | {d:.1} | {d:.1} |
        \\| FreeType bitmaps, one size | {d} | {d} | {d:.1} | {d:.1} |
        \\| FreeType bitmaps, seven sizes | {d} | {d} | {d:.1} | {d:.1} |
        \\
    , .{
        snail_prep.font_load_us,
        ft.font_load_us,
        ratio(ft.font_load_us, snail_prep.font_load_us),
        snail_prep.ascii_prep_us,
        ft.glyph_prep_us,
        ratio(ft.glyph_prep_us, snail_prep.ascii_prep_us),
        snail_prep.ascii_prep_us,
        ft.glyph_prep_all_sizes_us,
        ratio(ft.glyph_prep_all_sizes_us, snail_prep.ascii_prep_us),
        snail_prep.ascii_hint_setup_us,
        snail_prep.ascii_hint_execute_us,
        snail_prep.ascii_hint_us,
        snail_prep.paragraph_hint_context_cold_us,
        snail_prep.paragraph_hint_context_warm_us,
        vector_prep.shapes,
        vector_prep.freeze_us,
        snail_prep.footprint.usedBytes(),
        snail_prep.footprint.allocatedBytes(),
        kib(snail_prep.footprint.usedBytes()),
        kib(snail_prep.footprint.allocatedBytes()),
        vector_prep.footprint.usedBytes(),
        vector_prep.footprint.allocatedBytes(),
        kib(vector_prep.footprint.usedBytes()),
        kib(vector_prep.footprint.allocatedBytes()),
        ft.bitmap_bytes_single,
        ft.bitmap_bytes_single,
        kib(ft.bitmap_bytes_single),
        kib(ft.bitmap_bytes_single),
        ft.bitmap_bytes_all,
        ft.bitmap_bytes_all,
        kib(ft.bitmap_bytes_all),
        kib(ft.bitmap_bytes_all),
    });
    std.debug.print("\n", .{});
}

pub fn printTextTable(rows: anytype) void {
    std.debug.print(
        \\## Text Creation And Layout
        \\
        \\| Workload | Snail TextBlob | FreeType layout | FreeType / Snail |
        \\|---|---:|---:|---:|
        \\
    , .{});
    for (rows) |row| {
        std.debug.print(
            \\| {s} | {d:.2} us | {d:.2} us | {d:.2}x |
            \\
        , .{
            row.workload.name(),
            row.snail_us,
            row.ft_us,
            ratio(row.ft_us, row.snail_us),
        });
    }
    std.debug.print("\n", .{});
}

pub fn printRecordTable(rows: anytype) void {
    std.debug.print(
        \\## Draw Record Creation
        \\
        \\| Scene | Commands | Words | Segments | PreparedScene.initOwned |
        \\|---|---:|---:|---:|---:|
        \\
    , .{});
    for (rows) |row| {
        std.debug.print(
            \\| {s} | {d} | {d} | {d} | {d:.2} us |
            \\
        , .{ row.scene.name(), row.commands, row.words, row.segments, row.us });
    }
    std.debug.print("\n", .{});
}

pub fn printModeTable(rows: anytype) void {
    std.debug.print(
        \\## Render Modes
        \\
        \\Per-AA timings for the text and multi-script scenes. AA controls
        \\the fragment-shader path (grayscale vs LCD subpixel).
        \\
        \\| Backend | Scene | AA | Words | Segments | PreparedScene | Draw |
        \\|---|---|---|---:|---:|---:|---:|
        \\
    , .{});
    for (rows) |row| {
        std.debug.print(
            \\| {s} | {s} | {s} | {d} | {d} | {d:.2} us | {d:.2} us |
            \\
        , .{
            row.backend,
            row.scene.name(),
            row.mode.aaName(),
            row.words,
            row.segments,
            row.record_us,
            row.draw_us,
        });
    }
    std.debug.print("\n", .{});
}

pub fn printRenderTable(comptime width: u32, comptime height: u32, cpu_frames: usize, gpu_frames: usize, rows: anytype) void {
    std.debug.print(
        \\## Prepared Render
        \\
        \\Target: {d}x{d}. CPU uses {d} measured frames; GPU backends use {d} measured frames.
        \\
        \\| Backend | Scene | Frames | Commands | Words | Segments | Instance bytes/frame | Draw prepared scene |
        \\|---|---|---:|---:|---:|---:|---:|---:|
        \\
    , .{ width, height, cpu_frames, gpu_frames });
    for (rows) |row| {
        std.debug.print(
            \\| {s} | {s} | {d} | {d} | {d} | {d} | {d} | {d:.2} us |
            \\
        , .{
            row.backend,
            row.scene.name(),
            row.frames,
            row.commands,
            row.words,
            row.segments,
            row.instance_bytes,
            row.us,
        });
    }
    if (!build_options.enable_vulkan) {
        std.debug.print("| Vulkan | disabled (`zig build run-bench -Dvulkan=false`) | - | - | - | - | - | - |\n", .{});
    }
    std.debug.print("\n", .{});
}
