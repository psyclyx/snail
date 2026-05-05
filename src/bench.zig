//! Consolidated benchmarks for pasteable README tables.
//!
//! The benchmark covers preparation, text layout/object creation, vector path
//! freezing, draw-record generation, and prepared rendering on CPU, GL, and
//! Vulkan when Vulkan is built in.

const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");
const egl_offscreen = @import("render/egl_offscreen.zig");
const gl = @import("render/gl.zig").gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("render/vulkan_platform.zig") else struct {};

const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

const PREP_RUNS = 20;
const TEXT_WARMUP = 50;
const TEXT_ITERS = 1000;
const RECORD_WARMUP = 50;
const RECORD_ITERS = 1000;
const GPU_WARMUP = 50;
const GPU_FRAMES = 500;
const CPU_WARMUP = 5;
const CPU_FRAMES = 20;
const WIDTH: u32 = 640;
const HEIGHT: u32 = 360;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;

const PRINTABLE_ASCII = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

const SHORT = "Hello, world!";
const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";
const ARABIC_TEXT = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x85\xd9\x86 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x8a\xd9\x85";
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0";
const THAI_TEXT = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a";
const SIZES = [_]u32{ 12, 18, 24, 36, 48, 72, 96 };

const TextLine = struct {
    text: []const u8,
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    style: snail.FontStyle = .{},
};

const TextWorkload = enum {
    short,
    sentence,
    paragraph,
    paragraph_sizes,

    fn name(self: TextWorkload) []const u8 {
        return switch (self) {
            .short => "Short string",
            .sentence => "Sentence",
            .paragraph => "Paragraph",
            .paragraph_sizes => "Paragraph x 7 sizes",
        };
    }
};

const text_workloads = [_]TextWorkload{ .short, .sentence, .paragraph, .paragraph_sizes };

const SceneKind = enum {
    text,
    vector,
    mixed,
    multi_script,

    fn name(self: SceneKind) []const u8 {
        return switch (self) {
            .text => "Text",
            .vector => "Vector paths",
            .mixed => "Mixed text + vector",
            .multi_script => "Multi-script text",
        };
    }
};

const scene_kinds = [_]SceneKind{ .text, .vector, .mixed, .multi_script };

const RenderMode = struct {
    aa: snail.SubpixelOrder,

    fn aaName(self: RenderMode) []const u8 {
        return switch (self.aa) {
            .none => "grayscale",
            .rgb => "subpixel rgb",
            .bgr => "subpixel bgr",
            .vrgb => "subpixel vrgb",
            .vbgr => "subpixel vbgr",
        };
    }
};

const render_modes = [_]RenderMode{
    .{ .aa = .none },
    .{ .aa = .rgb },
};

const mode_scene_kinds = [_]SceneKind{ .text, .multi_script };

const scene_text_lines = [_]TextLine{
    .{ .text = "Score: 12345  FPS: 60  Level 7", .x = 18, .y = 30, .size = 18 },
    .{ .text = "Health: 100%  Ammo: 42/120", .x = 18, .y = 56, .size = 18, .color = .{ 0.9, 0.35, 0.3, 1 } },
    .{ .text = SENTENCE, .x = 18, .y = 96, .size = 22 },
    .{ .text = PARAGRAPH, .x = 18, .y = 130, .size = 16, .color = .{ 0.92, 0.92, 0.92, 1 } },
};

const scene_multi_script_lines = [_]TextLine{
    .{ .text = "Latin: " ++ SENTENCE, .x = 18, .y = 34, .size = 18 },
    .{ .text = ARABIC_TEXT, .x = 18, .y = 72, .size = 22 },
    .{ .text = DEVANAGARI_TEXT, .x = 18, .y = 112, .size = 22 },
    .{ .text = THAI_TEXT, .x = 18, .y = 152, .size = 22 },
};

const SceneBundle = struct {
    allocator: std.mem.Allocator,
    scene: snail.Scene,
    blobs: []snail.TextBlob = &.{},
    picture: ?*snail.PathPicture = null,

    fn deinit(self: *SceneBundle) void {
        self.scene.deinit();
        for (self.blobs) |*blob| blob.deinit();
        if (self.blobs.len > 0) self.allocator.free(self.blobs);
        if (self.picture) |picture| {
            picture.deinit();
            self.allocator.destroy(picture);
        }
        self.* = undefined;
    }
};

const SnailPrep = struct {
    font_load_us: f64,
    ascii_prep_us: f64,
    texture_bytes: usize,
};

const VectorPrep = struct {
    freeze_us: f64,
    shapes: usize,
    texture_bytes: usize,
};

const FreetypeResults = struct {
    font_load_us: f64,
    glyph_prep_us: f64,
    glyph_prep_all_sizes_us: f64,
    bitmap_bytes_single: usize,
    bitmap_bytes_all: usize,
    layout_short_us: f64,
    layout_sentence_us: f64,
    layout_paragraph_us: f64,
    layout_torture_us: f64,

    fn layout(self: FreetypeResults, workload: TextWorkload) f64 {
        return switch (workload) {
            .short => self.layout_short_us,
            .sentence => self.layout_sentence_us,
            .paragraph => self.layout_paragraph_us,
            .paragraph_sizes => self.layout_torture_us,
        };
    }
};

const TextRow = struct {
    workload: TextWorkload,
    snail_us: f64,
    ft_us: f64,
};

const RecordRow = struct {
    scene: SceneKind,
    us: f64,
    commands: usize,
    words: usize,
    segments: usize,
};

const ModeRow = struct {
    backend: []const u8,
    scene: SceneKind,
    mode: RenderMode,
    record_us: f64,
    draw_us: f64,
    words: usize,
    segments: usize,
};

const RenderRow = struct {
    backend: []const u8,
    scene: SceneKind,
    frames: usize,
    commands: usize,
    words: usize,
    segments: usize,
    us: f64,
};

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

fn printHardwareTable(gl_initialized: bool, vulkan_initialized: bool) void {
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

    if (gl_initialized) {
        std.debug.print(
            "| OpenGL renderer | {s} |\n| OpenGL version | {s} |\n",
            .{ glStringSafe(gl.GL_RENDERER), glStringSafe(gl.GL_VERSION) },
        );
    }

    if (comptime build_options.enable_vulkan) {
        if (vulkan_initialized) {
            var vk_buf: [256]u8 = undefined;
            const name = vulkan_platform.physicalDeviceName(&vk_buf) orelse "unknown";
            std.debug.print("| Vulkan device | {s} |\n", .{name});
        }
    } else {
        std.debug.print("| Vulkan | not built (`zig build bench -Dvulkan=true`) |\n", .{});
    }
    std.debug.print("\n", .{});
}

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

fn ratio(numerator: f64, denominator: f64) f64 {
    return numerator / @max(denominator, 0.001);
}

fn kib(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / 1024.0;
}

fn drawOptions(width: u32, height: u32, subpixel_order: snail.SubpixelOrder) snail.DrawOptions {
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    return .{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .subpixel_order = subpixel_order,
            .is_final_composite = true,
            .opaque_backdrop = true,
        },
    };
}

fn textAtlasTextureBytes(atlas: *const snail.TextAtlas) usize {
    var total: usize = 0;
    for (atlas.pageSlice()) |page| total += page.textureBytes();
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

fn pathPictureTextureBytes(picture: *const snail.PathPicture) usize {
    var total: usize = 0;
    for (picture.atlas.pages) |page| total += page.textureBytes();
    if (picture.atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

fn ensureText(atlas: *snail.TextAtlas, style: snail.FontStyle, text: []const u8) !void {
    if (try atlas.ensureText(style, text)) |next| {
        atlas.deinit();
        atlas.* = next;
    }
}

fn initTextAtlas(
    allocator: std.mem.Allocator,
    specs: []const snail.FaceSpec,
    texts: []const []const u8,
) !snail.TextAtlas {
    var atlas = try snail.TextAtlas.init(allocator, specs);
    errdefer atlas.deinit();
    for (texts) |text| try ensureText(&atlas, .{}, text);
    return atlas;
}

fn prepareSceneText(atlas: *snail.TextAtlas) !void {
    for (&scene_text_lines) |line| try ensureText(atlas, line.style, line.text);
    for (&scene_multi_script_lines) |line| try ensureText(atlas, line.style, line.text);
}

fn makeTextBlob(
    allocator: std.mem.Allocator,
    atlas: *snail.TextAtlas,
    line: TextLine,
) !snail.TextBlob {
    var shaped = try atlas.shapeText(allocator, line.style, line.text);
    defer shaped.deinit();

    var builder = snail.TextBlobBuilder.init(allocator, atlas);
    errdefer builder.deinit();
    _ = try atlas.appendShapedTextBlob(&builder, &shaped, .{
        .x = line.x,
        .y = line.y,
        .size = line.size,
        .color = line.color,
    }, true);
    return builder.finish();
}

fn lineFor(workload: TextWorkload) TextLine {
    return switch (workload) {
        .short => .{ .text = SHORT, .x = 0, .y = 24, .size = 24 },
        .sentence => .{ .text = SENTENCE, .x = 0, .y = 48, .size = 48 },
        .paragraph => .{ .text = PARAGRAPH, .x = 0, .y = 18, .size = 18 },
        .paragraph_sizes => unreachable,
    };
}

fn runTextWorkload(
    allocator: std.mem.Allocator,
    atlas: *snail.TextAtlas,
    workload: TextWorkload,
) !void {
    switch (workload) {
        .short, .sentence, .paragraph => {
            var blob = try makeTextBlob(allocator, atlas, lineFor(workload));
            std.mem.doNotOptimizeAway(blob.glyphCount());
            blob.deinit();
        },
        .paragraph_sizes => {
            var y: f32 = 330;
            for (SIZES) |size| {
                var blob = try makeTextBlob(allocator, atlas, .{
                    .text = PARAGRAPH,
                    .x = 0,
                    .y = y,
                    .size = @floatFromInt(size),
                });
                std.mem.doNotOptimizeAway(blob.glyphCount());
                blob.deinit();
                y -= @as(f32, @floatFromInt(size)) * 1.4;
            }
            std.mem.doNotOptimizeAway(y);
        },
    }
}

fn timeTextWorkload(atlas: *snail.TextAtlas, workload: TextWorkload) !f64 {
    const allocator = std.heap.smp_allocator;
    for (0..TEXT_WARMUP) |_| try runTextWorkload(allocator, atlas, workload);

    const start = nowNs();
    for (0..TEXT_ITERS) |_| try runTextWorkload(allocator, atlas, workload);
    return usFrom(start) / TEXT_ITERS;
}

fn addCustomVectorPath(builder: *snail.PathPictureBuilder, x: f32, y: f32, scale: f32, color: [4]f32) !void {
    var path = snail.Path.init(builder.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = x + 0 * scale, .y = y + 32 * scale });
    try path.cubicTo(
        .{ .x = x + 18 * scale, .y = y - 8 * scale },
        .{ .x = x + 46 * scale, .y = y - 8 * scale },
        .{ .x = x + 64 * scale, .y = y + 32 * scale },
    );
    try path.quadTo(.{ .x = x + 32 * scale, .y = y + 62 * scale }, .{ .x = x + 0 * scale, .y = y + 32 * scale });
    try path.close();
    try builder.addPath(&path, .{ .color = color }, .{
        .color = .{ 0.08, 0.09, 0.11, 1 },
        .width = 1.25,
        .join = .round,
        .placement = .inside,
    }, .identity);
}

fn buildVectorPicture(allocator: std.mem.Allocator) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    const colors = [_][4]f32{
        .{ 0.17, 0.43, 0.86, 0.92 },
        .{ 0.90, 0.36, 0.22, 0.90 },
        .{ 0.16, 0.66, 0.42, 0.90 },
        .{ 0.72, 0.45, 0.86, 0.88 },
    };

    for (0..4) |row| {
        for (0..6) |col| {
            const x = 24 + @as(f32, @floatFromInt(col)) * 96;
            const y = 24 + @as(f32, @floatFromInt(row)) * 70;
            const idx = (row * 6 + col) % colors.len;
            const fill = snail.FillStyle{ .color = colors[idx] };
            const stroke = snail.StrokeStyle{
                .color = .{ 0.95, 0.96, 0.98, 0.95 },
                .width = 1.5 + @as(f32, @floatFromInt((row + col) % 3)),
                .join = .round,
                .placement = .inside,
            };
            if ((row + col) % 3 == 0) {
                try builder.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, fill, stroke, 10, .identity);
            } else if ((row + col) % 3 == 1) {
                try builder.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 44 }, fill, stroke, .identity);
            } else {
                try addCustomVectorPath(&builder, x, y, 0.8, colors[idx]);
            }
        }
    }

    try builder.addRoundedRect(.{ .x = 18, .y = 314, .w = 580, .h = 28 }, .{
        .color = .{ 0.08, 0.10, 0.13, 0.82 },
    }, .{
        .color = .{ 0.55, 0.68, 0.85, 1 },
        .width = 2,
        .join = .round,
        .placement = .inside,
    }, 8, .identity);

    return builder.freeze(allocator);
}

fn timeVectorFreeze() !VectorPrep {
    const allocator = std.heap.smp_allocator;
    var total_us: f64 = 0;
    var shapes: usize = 0;
    var texture_bytes: usize = 0;

    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var picture = try buildVectorPicture(allocator);
        total_us += usFrom(start);
        shapes = picture.shapeCount();
        texture_bytes = pathPictureTextureBytes(&picture);
        picture.deinit();
    }

    return .{
        .freeze_us = total_us / PREP_RUNS,
        .shapes = shapes,
        .texture_bytes = texture_bytes,
    };
}

fn buildScene(
    allocator: std.mem.Allocator,
    atlas: *snail.TextAtlas,
    kind: SceneKind,
) !SceneBundle {
    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();

    const needs_text = kind == .text or kind == .mixed or kind == .multi_script;
    const needs_vector = kind == .vector or kind == .mixed;

    var blobs: []snail.TextBlob = &.{};
    var blob_count: usize = 0;
    errdefer {
        for (blobs[0..blob_count]) |*blob| blob.deinit();
        if (blobs.len > 0) allocator.free(blobs);
    }

    if (needs_text) {
        const lines: []const TextLine = if (kind == .multi_script) scene_multi_script_lines[0..] else scene_text_lines[0..];
        blobs = try allocator.alloc(snail.TextBlob, lines.len);
        for (lines) |line| {
            blobs[blob_count] = try makeTextBlob(allocator, atlas, line);
            try scene.addText(.{ .blob = &blobs[blob_count] });
            blob_count += 1;
        }
    }

    var picture: ?*snail.PathPicture = null;
    errdefer {
        if (picture) |p| {
            p.deinit();
            allocator.destroy(p);
        }
    }
    if (needs_vector) {
        const allocated_picture = try allocator.create(snail.PathPicture);
        allocated_picture.* = buildVectorPicture(allocator) catch |err| {
            allocator.destroy(allocated_picture);
            return err;
        };
        picture = allocated_picture;
        try scene.addPath(.{ .picture = allocated_picture });
    }

    return .{
        .allocator = allocator,
        .scene = scene,
        .blobs = blobs,
        .picture = picture,
    };
}

fn uploadSceneResources(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    scene: *const snail.Scene,
) !snail.PreparedResources {
    const entries = try allocator.alloc(snail.ResourceSet.Entry, @max(scene.commandCount(), 1));
    defer allocator.free(entries);

    var set = snail.ResourceSet.init(entries);
    try set.addScene(scene);
    return renderer.uploadResourcesBlocking(allocator, &set);
}

fn benchSnailPrep(allocator: std.mem.Allocator, font_data: []const u8) !SnailPrep {
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        _ = try ttf.Font.init(font_data);
        font_load_total_us += usFrom(start);
    }

    var prep_total_us: f64 = 0;
    var texture_bytes: usize = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var atlas = try snail.TextAtlas.init(allocator, &.{.{ .data = font_data }});
        try ensureText(&atlas, .{}, &PRINTABLE_ASCII);
        prep_total_us += usFrom(start);
        texture_bytes = textAtlasTextureBytes(&atlas);
        atlas.deinit();
    }

    return .{
        .font_load_us = font_load_total_us / PREP_RUNS,
        .ascii_prep_us = prep_total_us / PREP_RUNS,
        .texture_bytes = texture_bytes,
    };
}

fn benchFreetype(font_data: []const u8) !FreetypeResults {
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var load_library: c.FT_Library = null;
        const start = nowNs();
        if (c.FT_Init_FreeType(&load_library) != 0) return error.FTInitFailed;
        var load_face: c.FT_Face = null;
        if (c.FT_New_Memory_Face(load_library, font_data.ptr, @intCast(font_data.len), 0, &load_face) != 0) {
            _ = c.FT_Done_FreeType(load_library);
            return error.FTFaceFailed;
        }
        font_load_total_us += usFrom(start);
        _ = c.FT_Done_Face(load_face);
        _ = c.FT_Done_FreeType(load_library);
    }

    var library: c.FT_Library = null;
    if (c.FT_Init_FreeType(&library) != 0) return error.FTInitFailed;
    defer _ = c.FT_Done_FreeType(library);

    var face: c.FT_Face = null;
    if (c.FT_New_Memory_Face(library, font_data.ptr, @intCast(font_data.len), 0, &face) != 0) return error.FTFaceFailed;
    defer _ = c.FT_Done_Face(face);

    var bitmap_bytes_single: usize = 0;
    var glyph_prep_total_us: f64 = 0;
    for (0..PREP_RUNS) |run| {
        _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
        var run_bytes: usize = 0;
        const start = nowNs();
        for (&PRINTABLE_ASCII) |ch| {
            const gi = c.FT_Get_Char_Index(face, ch);
            if (gi == 0) continue;
            if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
            if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
            run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
        }
        glyph_prep_total_us += usFrom(start);
        if (run == 0) bitmap_bytes_single = run_bytes;
    }

    var bitmap_bytes_all: usize = 0;
    var glyph_prep_all_total_us: f64 = 0;
    for (0..PREP_RUNS) |run| {
        var run_bytes: usize = 0;
        const start = nowNs();
        for (SIZES) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            for (&PRINTABLE_ASCII) |ch| {
                const gi = c.FT_Get_Char_Index(face, ch);
                if (gi == 0) continue;
                if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
                if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
                run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
            }
        }
        glyph_prep_all_total_us += usFrom(start);
        if (run == 0) bitmap_bytes_all = run_bytes;
    }

    const LayoutCtx = struct {
        face: c.FT_Face,

        fn layoutString(self: @This(), text: []const u8) void {
            var pen_x: i32 = 0;
            var prev: u32 = 0;
            for (text) |ch| {
                const gi = c.FT_Get_Char_Index(self.face, ch);
                if (prev != 0 and gi != 0) {
                    var delta: c.FT_Vector = undefined;
                    _ = c.FT_Get_Kerning(self.face, prev, gi, c.FT_KERNING_DEFAULT, &delta);
                    pen_x += @intCast(delta.x >> 6);
                }
                if (c.FT_Load_Glyph(self.face, gi, c.FT_LOAD_DEFAULT) == 0) {
                    pen_x += @intCast(self.face.*.glyph.*.advance.x >> 6);
                }
                prev = gi;
            }
            std.mem.doNotOptimizeAway(pen_x);
        }
    };
    const ctx = LayoutCtx{ .face = face };

    _ = c.FT_Set_Pixel_Sizes(face, 0, 24);
    var start = nowNs();
    for (0..TEXT_ITERS) |_| ctx.layoutString(SHORT);
    const short_us = usFrom(start) / TEXT_ITERS;

    _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
    start = nowNs();
    for (0..TEXT_ITERS) |_| ctx.layoutString(SENTENCE);
    const sentence_us = usFrom(start) / TEXT_ITERS;

    _ = c.FT_Set_Pixel_Sizes(face, 0, 18);
    start = nowNs();
    for (0..TEXT_ITERS) |_| ctx.layoutString(PARAGRAPH);
    const paragraph_us = usFrom(start) / TEXT_ITERS;

    start = nowNs();
    for (0..TEXT_ITERS) |_| {
        for (SIZES) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            ctx.layoutString(PARAGRAPH);
        }
    }
    const torture_us = usFrom(start) / TEXT_ITERS;

    return .{
        .font_load_us = font_load_total_us / PREP_RUNS,
        .glyph_prep_us = glyph_prep_total_us / PREP_RUNS,
        .glyph_prep_all_sizes_us = glyph_prep_all_total_us / PREP_RUNS,
        .bitmap_bytes_single = bitmap_bytes_single,
        .bitmap_bytes_all = bitmap_bytes_all,
        .layout_short_us = short_us,
        .layout_sentence_us = sentence_us,
        .layout_paragraph_us = paragraph_us,
        .layout_torture_us = torture_us,
    };
}

fn timeRecordBuild(
    prepared: *const snail.PreparedResources,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
) !f64 {
    const allocator = std.heap.smp_allocator;
    for (0..RECORD_WARMUP) |_| {
        var prepared_scene = try snail.PreparedScene.initOwned(allocator, prepared, scene, options);
        std.mem.doNotOptimizeAway(prepared_scene.words.len);
        prepared_scene.deinit();
    }

    const start = nowNs();
    for (0..RECORD_ITERS) |_| {
        var prepared_scene = try snail.PreparedScene.initOwned(allocator, prepared, scene, options);
        std.mem.doNotOptimizeAway(prepared_scene.words.len);
        prepared_scene.deinit();
    }
    return usFrom(start) / RECORD_ITERS;
}

// Per-AA timings against one backend for the text and multi-script scenes.
fn benchModes(
    allocator: std.mem.Allocator,
    backend_name: []const u8,
    atlas: *snail.TextAtlas,
    rows: *std.ArrayList(ModeRow),
    timer: anytype,
) !void {
    for (mode_scene_kinds) |scene_kind| {
        for (render_modes) |mode| {
            var bundle = try buildScene(allocator, atlas, scene_kind);
            defer bundle.deinit();

            const opts = drawOptions(WIDTH, HEIGHT, mode.aa);
            var resources = try uploadSceneResources(allocator, timer.renderer(), &bundle.scene);
            defer resources.deinit();
            var prepared_scene = try snail.PreparedScene.initOwned(allocator, &resources, &bundle.scene, opts);
            defer prepared_scene.deinit();

            const record_us = try timeRecordBuild(&resources, &bundle.scene, opts);
            const draw_us = try timer.timeDraw(&resources, &prepared_scene, opts);

            try rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .record_us = record_us,
                .draw_us = draw_us,
                .words = prepared_scene.words.len,
                .segments = prepared_scene.segments.len,
            });
        }
    }
}

fn initFramebuffer() struct { fbo: gl.GLuint, texture: gl.GLuint } {
    var fbo: gl.GLuint = 0;
    var tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex, 0);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    return .{ .fbo = fbo, .texture = tex };
}

fn clearGlFrame() void {
    gl.glClearColor(0.02, 0.025, 0.03, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
}

fn timeCpuDraw(
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawOptions,
    pixels: []u8,
) !f64 {
    for (0..CPU_WARMUP) |_| {
        @memset(pixels, 0);
        try renderer.drawPrepared(prepared, scene, options);
    }

    const start = nowNs();
    for (0..CPU_FRAMES) |_| {
        @memset(pixels, 0);
        try renderer.drawPrepared(prepared, scene, options);
    }
    return usFrom(start) / CPU_FRAMES;
}

fn timeGlDraw(
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawOptions,
) !f64 {
    for (0..GPU_WARMUP) |_| {
        clearGlFrame();
        try renderer.drawPrepared(prepared, scene, options);
    }
    gl.glFinish();

    const start = nowNs();
    for (0..GPU_FRAMES) |_| {
        clearGlFrame();
        try renderer.drawPrepared(prepared, scene, options);
    }
    gl.glFinish();
    return usFrom(start) / GPU_FRAMES;
}

fn timeVulkanDraw(
    vk_renderer: *snail.VulkanRenderer,
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawOptions,
) !f64 {
    if (comptime !build_options.enable_vulkan) unreachable;

    for (0..GPU_WARMUP) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentOffscreenFrameIndex() });
        try renderer.drawPrepared(prepared, scene, options);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();

    const start = nowNs();
    for (0..GPU_FRAMES) |_| {
        const cmd = vulkan_platform.beginFrameOffscreen();
        vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentOffscreenFrameIndex() });
        try renderer.drawPrepared(prepared, scene, options);
        vulkan_platform.endFrameOffscreen();
    }
    vulkan_platform.queueWaitIdle();
    return usFrom(start) / GPU_FRAMES;
}

fn printPreparationTables(snail_prep: SnailPrep, vector_prep: VectorPrep, ft: FreetypeResults) void {
    std.debug.print(
        \\## Preparation
        \\
        \\| Workload | Snail | FreeType | FreeType / Snail |
        \\|---|---:|---:|---:|
        \\| Font load | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| Glyph prep, ASCII | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| Glyph prep, 7 sizes | {d:.2} us | {d:.2} us | {d:.2}x |
        \\| PathPicture freeze, {d} shapes | {d:.2} us | n/a | n/a |
        \\
        \\## Prepared Resource Memory
        \\
        \\| Resource | Bytes | KiB |
        \\|---|---:|---:|
        \\| Snail text curve/band textures | {d} | {d:.1} |
        \\| Snail vector curve/band textures | {d} | {d:.1} |
        \\| FreeType bitmaps, one size | {d} | {d:.1} |
        \\| FreeType bitmaps, seven sizes | {d} | {d:.1} |
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
        vector_prep.shapes,
        vector_prep.freeze_us,
        snail_prep.texture_bytes,
        kib(snail_prep.texture_bytes),
        vector_prep.texture_bytes,
        kib(vector_prep.texture_bytes),
        ft.bitmap_bytes_single,
        kib(ft.bitmap_bytes_single),
        ft.bitmap_bytes_all,
        kib(ft.bitmap_bytes_all),
    });
    std.debug.print("\n", .{});
}

fn printTextTable(rows: []const TextRow) void {
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

fn printRecordTable(rows: []const RecordRow) void {
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

fn printModeTable(rows: []const ModeRow) void {
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

fn printRenderTable(rows: []const RenderRow) void {
    std.debug.print(
        \\## Prepared Render
        \\
        \\Target: {d}x{d}. CPU uses {d} measured frames; GPU backends use {d} measured frames.
        \\
        \\| Backend | Scene | Frames | Commands | Words | Segments | Draw prepared scene |
        \\|---|---|---:|---:|---:|---:|---:|
        \\
    , .{ WIDTH, HEIGHT, CPU_FRAMES, GPU_FRAMES });
    for (rows) |row| {
        std.debug.print(
            \\| {s} | {s} | {d} | {d} | {d} | {d} | {d:.2} us |
            \\
        , .{
            row.backend,
            row.scene.name(),
            row.frames,
            row.commands,
            row.words,
            row.segments,
            row.us,
        });
    }
    if (!build_options.enable_vulkan) {
        std.debug.print("| Vulkan | not built (`zig build bench -Dvulkan=true`) | - | - | - | - | - |\n", .{});
    }
    std.debug.print("\n", .{});
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const options = drawOptions(WIDTH, HEIGHT, .rgb);

    const font_data = assets.noto_sans_regular;
    const snail_prep = try benchSnailPrep(allocator, font_data);
    const vector_prep = try timeVectorFreeze();
    const ft = try benchFreetype(font_data);

    var text_atlas = try initTextAtlas(allocator, &.{.{ .data = font_data }}, &.{
        &PRINTABLE_ASCII,
        SHORT,
        SENTENCE,
        PARAGRAPH,
    });
    defer text_atlas.deinit();

    var text_rows: [text_workloads.len]TextRow = undefined;
    for (&text_rows, text_workloads) |*row, workload| {
        row.* = .{
            .workload = workload,
            .snail_us = try timeTextWorkload(&text_atlas, workload),
            .ft_us = ft.layout(workload),
        };
    }

    var atlas = try initTextAtlas(allocator, &.{
        .{ .data = assets.noto_sans_regular },
        .{ .data = assets.noto_sans_arabic, .fallback = true },
        .{ .data = assets.noto_sans_devanagari, .fallback = true },
        .{ .data = assets.noto_sans_thai, .fallback = true },
    }, &.{ SHORT, SENTENCE, PARAGRAPH, ARABIC_TEXT, DEVANAGARI_TEXT, THAI_TEXT });
    defer atlas.deinit();
    try prepareSceneText(&atlas);

    const cpu_pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels);
    var cpu = snail.CpuRenderer.init(cpu_pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var cpu_renderer = snail.Renderer.initCpu(&cpu);

    var cpu_pool: snail.ThreadPool = undefined;
    try cpu_pool.init(allocator, .{});
    defer cpu_pool.deinit();
    const cpu_pixels_threaded = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels_threaded);
    var cpu_threaded = snail.CpuRenderer.init(cpu_pixels_threaded.ptr, WIDTH, HEIGHT, WIDTH * 4);
    cpu_threaded.setThreadPool(&cpu_pool);
    var cpu_threaded_renderer = snail.Renderer.initCpu(&cpu_threaded);

    var bundles: [scene_kinds.len]SceneBundle = undefined;
    var bundle_count: usize = 0;
    defer {
        for (bundles[0..bundle_count]) |*bundle| bundle.deinit();
    }
    for (scene_kinds) |kind| {
        bundles[bundle_count] = try buildScene(allocator, &atlas, kind);
        bundle_count += 1;
    }

    var record_rows: [scene_kinds.len]RecordRow = undefined;
    var cpu_resources: [scene_kinds.len]snail.PreparedResources = undefined;
    var cpu_resource_count: usize = 0;
    defer {
        for (cpu_resources[0..cpu_resource_count]) |*resources| resources.deinit();
    }
    var prepared_scenes: [scene_kinds.len]snail.PreparedScene = undefined;
    var prepared_count: usize = 0;
    defer {
        for (prepared_scenes[0..prepared_count]) |*scene| scene.deinit();
    }
    for (scene_kinds, 0..) |kind, i| {
        cpu_resources[i] = try uploadSceneResources(allocator, &cpu_renderer, &bundles[i].scene);
        cpu_resource_count += 1;
        prepared_scenes[i] = try snail.PreparedScene.initOwned(allocator, &cpu_resources[i], &bundles[i].scene, options);
        prepared_count += 1;
        record_rows[i] = .{
            .scene = kind,
            .us = try timeRecordBuild(&cpu_resources[i], &bundles[i].scene, options),
            .commands = bundles[i].scene.commandCount(),
            .words = prepared_scenes[i].words.len,
            .segments = prepared_scenes[i].segments.len,
        };
    }

    var render_rows: std.ArrayList(RenderRow) = .empty;
    defer render_rows.deinit(allocator);

    for (scene_kinds, 0..) |kind, i| {
        try render_rows.append(allocator, .{
            .backend = "CPU",
            .scene = kind,
            .frames = CPU_FRAMES,
            .commands = bundles[i].scene.commandCount(),
            .words = prepared_scenes[i].words.len,
            .segments = prepared_scenes[i].segments.len,
            .us = try timeCpuDraw(&cpu_renderer, &cpu_resources[i], &prepared_scenes[i], options, cpu_pixels),
        });
    }

    for (scene_kinds, 0..) |kind, i| {
        try render_rows.append(allocator, .{
            .backend = "CPU (threaded)",
            .scene = kind,
            .frames = CPU_FRAMES,
            .commands = bundles[i].scene.commandCount(),
            .words = prepared_scenes[i].words.len,
            .segments = prepared_scenes[i].segments.len,
            .us = try timeCpuDraw(&cpu_threaded_renderer, &cpu_resources[i], &prepared_scenes[i], options, cpu_pixels_threaded),
        });
    }

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
    defer gl_ctx.deinit();
    const framebuffer = initFramebuffer();
    defer {
        var fbo = framebuffer.fbo;
        var tex = framebuffer.texture;
        gl.glDeleteFramebuffers(1, &fbo);
        gl.glDeleteTextures(1, &tex);
    }

    var gl_renderer_state = try snail.Renderer.init();
    defer gl_renderer_state.deinit();
    for (scene_kinds, 0..) |kind, i| {
        var gl_resources = try uploadSceneResources(allocator, &gl_renderer_state, &bundles[i].scene);
        defer gl_resources.deinit();
        var gl_scene = try snail.PreparedScene.initOwned(allocator, &gl_resources, &bundles[i].scene, options);
        defer gl_scene.deinit();
        try render_rows.append(allocator, .{
            .backend = gl_renderer_state.backendName(),
            .scene = kind,
            .frames = GPU_FRAMES,
            .commands = bundles[i].scene.commandCount(),
            .words = gl_scene.words.len,
            .segments = gl_scene.segments.len,
            .us = try timeGlDraw(&gl_renderer_state, &gl_resources, &gl_scene, options),
        });
    }

    var vk_state: if (build_options.enable_vulkan) ?snail.VulkanRenderer else void = if (build_options.enable_vulkan) null else {};
    var vk_renderer: if (build_options.enable_vulkan) snail.Renderer else void = undefined;
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
        errdefer vulkan_platform.deinitOffscreen();
        vk_state = try snail.VulkanRenderer.init(vk_ctx);
        errdefer if (vk_state) |*s| s.deinit();
        vk_renderer = vk_state.?.asRenderer();
        for (scene_kinds, 0..) |kind, i| {
            var vk_resources = try uploadSceneResources(allocator, &vk_renderer, &bundles[i].scene);
            defer vk_resources.deinit();
            var vk_scene = try snail.PreparedScene.initOwned(allocator, &vk_resources, &bundles[i].scene, options);
            defer vk_scene.deinit();
            try render_rows.append(allocator, .{
                .backend = vk_state.?.backendName(),
                .scene = kind,
                .frames = GPU_FRAMES,
                .commands = bundles[i].scene.commandCount(),
                .words = vk_scene.words.len,
                .segments = vk_scene.segments.len,
                .us = try timeVulkanDraw(&vk_state.?, &vk_renderer, &vk_resources, &vk_scene, options),
            });
        }
    }
    defer if (build_options.enable_vulkan) {
        if (vk_state) |*s| s.deinit();
        vulkan_platform.deinitOffscreen();
    };

    var mode_rows: std.ArrayList(ModeRow) = .empty;
    defer mode_rows.deinit(allocator);

    const CpuTimer = struct {
        renderer_ptr: *snail.Renderer,
        pixels_buf: []u8,
        fn renderer(self: @This()) *snail.Renderer {
            return self.renderer_ptr;
        }
        fn timeDraw(
            self: @This(),
            prepared: *const snail.PreparedResources,
            scene: *const snail.PreparedScene,
            opts: snail.DrawOptions,
        ) !f64 {
            return timeCpuDraw(self.renderer_ptr, prepared, scene, opts, self.pixels_buf);
        }
    };
    try benchModes(allocator, "CPU", &atlas, &mode_rows, CpuTimer{ .renderer_ptr = &cpu_renderer, .pixels_buf = cpu_pixels });

    const GlTimer = struct {
        renderer_ptr: *snail.Renderer,
        fn renderer(self: @This()) *snail.Renderer {
            return self.renderer_ptr;
        }
        fn timeDraw(
            self: @This(),
            prepared: *const snail.PreparedResources,
            scene: *const snail.PreparedScene,
            opts: snail.DrawOptions,
        ) !f64 {
            return timeGlDraw(self.renderer_ptr, prepared, scene, opts);
        }
    };
    try benchModes(allocator, gl_renderer_state.backendName(), &atlas, &mode_rows, GlTimer{ .renderer_ptr = &gl_renderer_state });

    if (comptime build_options.enable_vulkan) {
        const VkTimer = struct {
            state: *snail.VulkanRenderer,
            renderer_ptr: *snail.Renderer,
            fn renderer(self: @This()) *snail.Renderer {
                return self.renderer_ptr;
            }
            fn timeDraw(
                self: @This(),
                prepared: *const snail.PreparedResources,
                scene: *const snail.PreparedScene,
                opts: snail.DrawOptions,
            ) !f64 {
                return timeVulkanDraw(self.state, self.renderer_ptr, prepared, scene, opts);
            }
        };
        try benchModes(allocator, vk_state.?.backendName(), &atlas, &mode_rows, VkTimer{ .state = &vk_state.?, .renderer_ptr = &vk_renderer });
    }

    std.debug.print(
        \\# Snail Benchmarks
        \\
        \\NotoSans-Regular, {d} prep runs, {d} text iterations, {d} draw-record iterations.
        \\
        \\The vector workload contains filled and stroked rounded rectangles, ellipses, and custom cubic/quadratic paths. Vulkan rows are emitted only when built with `-Dvulkan=true`.
        \\
        \\
    , .{ PREP_RUNS, TEXT_ITERS, RECORD_ITERS });
    printHardwareTable(true, build_options.enable_vulkan);
    printPreparationTables(snail_prep, vector_prep, ft);
    printTextTable(&text_rows);
    printRecordTable(&record_rows);
    printRenderTable(render_rows.items);
    printModeTable(mode_rows.items);
}
