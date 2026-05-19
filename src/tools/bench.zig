//! Consolidated benchmarks for pasteable README tables.
//!
//! The benchmark covers preparation, text layout/object creation, vector path
//! freezing, draw-record generation, and prepared rendering on CPU, GL, and
//! Vulkan when Vulkan is built in.

const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail");
const egl_offscreen = @import("demo_platform_offscreen_gl");
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};
const freetype = @import("bench/freetype.zig");
const render_timing = @import("bench/render_timing.zig");
const report = @import("bench/report.zig");

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
const VECTOR_RESOURCE_KEY = snail.ResourceKey.named("bench.vectors");

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

    pub fn name(self: TextWorkload) []const u8 {
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
    rich_text,
    vector,
    mixed,
    multi_script,

    pub fn name(self: SceneKind) []const u8 {
        return switch (self) {
            .text => "Text",
            .rich_text => "Rich text",
            .vector => "Vector paths",
            .mixed => "Mixed text + vector",
            .multi_script => "Multi-script text",
        };
    }
};

const scene_kinds = [_]SceneKind{ .text, .rich_text, .vector, .mixed, .multi_script };

fn sceneTextKey(index: usize) snail.ResourceKey {
    return snail.ResourceKey.fromId(@intCast(index + 1));
}

fn declareTextBlobResources(
    set: *snail.ResourceManifest,
    atlas_key: snail.ResourceKey,
    blob_key: snail.ResourceKey,
    blob: *const snail.TextBlob,
) !snail.TextResourceKeys {
    const resources = blob.resourceKeys(atlas_key, blob_key);
    try set.putTextBlob(resources, blob);
    return resources;
}

const RenderMode = struct {
    aa: snail.SubpixelOrder,

    pub fn aaName(self: RenderMode) []const u8 {
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

const mode_scene_kinds = [_]SceneKind{ .text, .rich_text, .multi_script };

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

const rich_text_strings = [_][]const u8{
    "RICH",
    "gradient",
    "runs",
    "status",
    "HP",
    "83",
    "shield",
    "online",
    "per-letter",
    "snail",
    "alerts",
    "OK",
    "WARN",
    "CRIT",
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
    ascii_hint_setup_us: f64,
    ascii_hint_execute_us: f64,
    ascii_hint_us: f64,
    footprint: snail.ResourceFootprint,
};

const VectorPrep = struct {
    freeze_us: f64,
    shapes: usize,
    footprint: snail.ResourceFootprint,
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
    instance_bytes: usize,
    us: f64,
};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

fn drawState(width: u32, height: u32, subpixel_order: snail.SubpixelOrder) snail.DrawState {
    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    return .{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .surface = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = subpixel_order },
    };
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
    try ensureText(atlas, .{ .weight = .bold }, &PRINTABLE_ASCII);
    for (&scene_text_lines) |line| try ensureText(atlas, line.style, line.text);
    for (&scene_multi_script_lines) |line| try ensureText(atlas, line.style, line.text);
    for (&rich_text_strings) |text| {
        try ensureText(atlas, .{}, text);
        try ensureText(atlas, .{ .weight = .bold }, text);
    }
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
    _ = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = line.x, .y = line.y }, .em = line.size },
        .fill = .{ .solid = line.color },
    });
    return builder.finish();
}

fn appendPaintedRun(
    builder: *snail.TextBlobBuilder,
    style: snail.FontStyle,
    text: []const u8,
    x: f32,
    y: f32,
    em: f32,
    paint: snail.Paint,
) !snail.TextAppendResult {
    var shaped = try builder.atlas.shapeText(builder.allocator, style, text);
    defer shaped.deinit();
    return builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = x, .y = y }, .em = em },
        .fill = paint,
    });
}

fn appendSolidRun(
    builder: *snail.TextBlobBuilder,
    style: snail.FontStyle,
    text: []const u8,
    x: f32,
    y: f32,
    em: f32,
    color: [4]f32,
) !snail.TextAppendResult {
    return appendPaintedRun(builder, style, text, x, y, em, .{ .solid = color });
}

fn makeRichTextBlob(allocator: std.mem.Allocator, atlas: *snail.TextAtlas) !snail.TextBlob {
    var builder = snail.TextBlobBuilder.init(allocator, atlas);
    errdefer builder.deinit();

    var x: f32 = 18.0;
    var y: f32 = 46.0;
    x += (try appendSolidRun(&builder, .{ .weight = .bold }, "RICH ", x, y, 30.0, .{ 0.95, 0.97, 1.0, 1.0 })).advance.x;
    x += (try appendPaintedRun(&builder, .{ .weight = .bold }, "gradient", x, y, 30.0, .{ .linear_gradient = .{
        .start = .{ .x = x, .y = y - 30.0 },
        .end = .{ .x = x + 150.0, .y = y },
        .start_color = .{ 0.30, 0.65, 1.0, 1.0 },
        .end_color = .{ 1.0, 0.35, 0.58, 1.0 },
    } })).advance.x;
    _ = try appendSolidRun(&builder, .{}, " runs", x, y, 22.0, .{ 0.72, 0.78, 0.86, 1.0 });

    x = 18.0;
    y = 94.0;
    x += (try appendSolidRun(&builder, .{}, "status  ", x, y, 18.0, .{ 0.60, 0.68, 0.76, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{ .weight = .bold }, "HP ", x, y, 24.0, .{ 0.80, 0.92, 0.86, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{ .weight = .bold }, "83", x, y, 28.0, .{ 0.25, 0.92, 0.50, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{}, "   shield ", x, y, 18.0, .{ 0.62, 0.72, 0.82, 1.0 })).advance.x;
    _ = try appendPaintedRun(&builder, .{ .weight = .bold }, "online", x, y, 22.0, .{ .linear_gradient = .{
        .start = .{ .x = x, .y = y - 22.0 },
        .end = .{ .x = x + 76.0, .y = y },
        .start_color = .{ 0.20, 0.82, 0.92, 1.0 },
        .end_color = .{ 0.85, 0.96, 0.45, 1.0 },
    } });

    x = 18.0;
    y = 142.0;
    x += (try appendSolidRun(&builder, .{}, "per-letter  ", x, y, 17.0, .{ 0.56, 0.64, 0.74, 1.0 })).advance.x;
    const letters = "snail";
    const colors = [_][4]f32{
        .{ 0.28, 0.55, 0.96, 1.0 },
        .{ 0.92, 0.36, 0.56, 1.0 },
        .{ 0.98, 0.78, 0.26, 1.0 },
        .{ 0.32, 0.82, 0.56, 1.0 },
        .{ 0.76, 0.56, 0.98, 1.0 },
    };
    for (letters, 0..) |letter, i| {
        const one = [_]u8{letter};
        x += (try appendSolidRun(&builder, .{ .weight = .bold }, &one, x, y, 24.0 + @as(f32, @floatFromInt(i % 3)) * 3.0, colors[i])).advance.x;
    }
    x += (try appendSolidRun(&builder, .{}, "  alerts ", x, y, 17.0, .{ 0.56, 0.64, 0.74, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{ .weight = .bold }, "OK", x, y, 20.0, .{ 0.36, 0.92, 0.52, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{}, " / ", x, y, 17.0, .{ 0.56, 0.64, 0.74, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{ .weight = .bold }, "WARN", x, y, 20.0, .{ 0.98, 0.72, 0.32, 1.0 })).advance.x;
    x += (try appendSolidRun(&builder, .{}, " / ", x, y, 17.0, .{ 0.56, 0.64, 0.74, 1.0 })).advance.x;
    _ = try appendSolidRun(&builder, .{ .weight = .bold }, "CRIT", x, y, 20.0, .{ 1.0, 0.40, 0.44, 1.0 });

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
    try builder.addPath(&path, .{ .paint = .{ .solid = color } }, .{
        .paint = .{ .solid = .{ 0.08, 0.09, 0.11, 1 } },
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
            const fill = snail.FillStyle{ .paint = .{ .solid = colors[idx] } };
            const stroke = snail.StrokeStyle{
                .paint = .{ .solid = .{ 0.95, 0.96, 0.98, 0.95 } },
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
        .paint = .{ .solid = .{ 0.08, 0.10, 0.13, 0.82 } },
    }, .{
        .paint = .{ .solid = .{ 0.55, 0.68, 0.85, 1 } },
        .width = 2,
        .join = .round,
        .placement = .inside,
    }, 8, .identity);

    return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
}

fn timeVectorFreeze() !VectorPrep {
    const allocator = std.heap.smp_allocator;
    var total_us: f64 = 0;
    var shapes: usize = 0;
    var footprint: snail.ResourceFootprint = .{};

    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var picture = try buildVectorPicture(allocator);
        total_us += usFrom(start);
        shapes = picture.shapeCount();
        footprint = picture.uploadFootprint();
        picture.deinit();
    }

    return .{
        .freeze_us = total_us / PREP_RUNS,
        .shapes = shapes,
        .footprint = footprint,
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

    if (kind == .rich_text) {
        blobs = try allocator.alloc(snail.TextBlob, 1);
        blobs[blob_count] = try makeRichTextBlob(allocator, atlas);
        try scene.addText(.{
            .blob = &blobs[blob_count],
            .resources = blobs[blob_count].resourceKeys(snail.ResourceKey.named("fonts"), sceneTextKey(blob_count)),
        });
        blob_count += 1;
    } else if (needs_text) {
        const lines: []const TextLine = if (kind == .multi_script) scene_multi_script_lines[0..] else scene_text_lines[0..];
        blobs = try allocator.alloc(snail.TextBlob, lines.len);
        for (lines) |line| {
            blobs[blob_count] = try makeTextBlob(allocator, atlas, line);
            try scene.addText(.{
                .blob = &blobs[blob_count],
                .resources = blobs[blob_count].resourceKeys(snail.ResourceKey.named("fonts"), sceneTextKey(blob_count)),
            });
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
        try scene.addPath(.{ .picture = allocated_picture, .resource_key = VECTOR_RESOURCE_KEY });
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
    bundle: *const SceneBundle,
) !snail.PreparedResources {
    const entries = try allocator.alloc(snail.ResourceManifest.Entry, @max(bundle.scene.commandCount() * 2, 1));
    defer allocator.free(entries);

    var set = snail.ResourceManifest.init(entries);
    for (bundle.blobs, 0..) |*blob, i| {
        _ = try declareTextBlobResources(&set, snail.ResourceKey.named("fonts"), sceneTextKey(i), blob);
    }
    if (bundle.picture) |picture| try set.putPathPicture(VECTOR_RESOURCE_KEY, picture);
    return renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
}

fn benchSnailPrep(allocator: std.mem.Allocator, font_data: []const u8) !SnailPrep {
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        _ = try snail.Font.init(font_data);
        font_load_total_us += usFrom(start);
    }

    var prep_total_us: f64 = 0;
    var footprint: snail.ResourceFootprint = .{};
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var atlas = try snail.TextAtlas.init(allocator, &.{.{ .data = font_data }});
        try ensureText(&atlas, .{}, &PRINTABLE_ASCII);
        prep_total_us += usFrom(start);
        footprint = atlas.uploadFootprint();
        atlas.deinit();
    }

    var hint_atlas = try snail.TextAtlas.init(allocator, &.{.{ .data = font_data }});
    defer hint_atlas.deinit();
    try ensureText(&hint_atlas, .{}, &PRINTABLE_ASCII);
    const ascii_hint_setup_us = try timeAsciiTrueTypeSetup(&hint_atlas);
    const ascii_hint_execute_us = try timeAsciiTrueTypeExecute(&hint_atlas);
    const ascii_hint_us = try timeAsciiTrueTypeHint(&hint_atlas);

    return .{
        .font_load_us = font_load_total_us / PREP_RUNS,
        .ascii_prep_us = prep_total_us / PREP_RUNS,
        .ascii_hint_setup_us = ascii_hint_setup_us,
        .ascii_hint_execute_us = ascii_hint_execute_us,
        .ascii_hint_us = ascii_hint_us,
        .footprint = footprint,
    };
}

fn timeAsciiTrueTypeSetup(atlas: *snail.TextAtlas) !f64 {
    const allocator = std.heap.smp_allocator;
    const face = &atlas.config.faces[0];
    var total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var machine = try snail.TrueTypeHintMachine.init(allocator, face, snail.TrueTypeHintPpem.uniform(12 * 64));
        total_us += usFrom(start);
        machine.deinit();
    }
    return total_us / PREP_RUNS;
}

fn timeAsciiTrueTypeExecute(atlas: *snail.TextAtlas) !f64 {
    const allocator = std.heap.smp_allocator;
    const face = &atlas.config.faces[0];
    var topology_cache = try snail.TrueTypeGlyphTopologyCache.init(allocator, face);
    defer topology_cache.deinit();
    try preloadAsciiHintTopology(atlas, &topology_cache);
    var machine = try snail.TrueTypeHintMachine.init(allocator, face, snail.TrueTypeHintPpem.uniform(12 * 64));
    defer machine.deinit();

    var total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        try executeAsciiOnce(&machine, atlas, &topology_cache);
        total_us += usFrom(start);
    }
    return total_us / PREP_RUNS;
}

fn timeAsciiTrueTypeHint(atlas: *snail.TextAtlas) !f64 {
    const allocator = std.heap.smp_allocator;
    const face = &atlas.config.faces[0];
    var topology_cache = try snail.TrueTypeGlyphTopologyCache.init(allocator, face);
    defer topology_cache.deinit();
    try preloadAsciiHintTopology(atlas, &topology_cache);
    var machine = try snail.TrueTypeHintMachine.init(allocator, face, snail.TrueTypeHintPpem.uniform(12 * 64));
    defer machine.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        try hintAsciiOnce(&machine, &arena, atlas, &topology_cache);
        total_us += usFrom(start);
    }
    return total_us / PREP_RUNS;
}

fn executeAsciiOnce(
    machine: *snail.TrueTypeHintMachine,
    atlas: *snail.TextAtlas,
    topology_cache: *snail.TrueTypeGlyphTopologyCache,
) !void {
    for (PRINTABLE_ASCII) |ch| {
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        const executed = machine.executeCachedGlyph(topology_cache, glyph_id) catch |err| switch (err) {
            error.UnsupportedCompoundHinting => continue,
            else => return err,
        };
        keepExecutedGlyphAlive(executed);
    }
}

fn keepExecutedGlyphAlive(executed: snail.TrueTypeExecutedGlyph) void {
    switch (executed) {
        .empty => |advance| std.mem.doNotOptimizeAway(advance.x),
        .simple => |hinted| std.mem.doNotOptimizeAway(hinted.advance_x_26_6),
    }
}

fn preloadAsciiHintTopology(atlas: *snail.TextAtlas, topology_cache: *snail.TrueTypeGlyphTopologyCache) !void {
    for (PRINTABLE_ASCII) |ch| {
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        _ = try topology_cache.get(glyph_id);
    }
}

fn hintAsciiOnce(
    machine: *snail.TrueTypeHintMachine,
    arena: *std.heap.ArenaAllocator,
    atlas: *snail.TextAtlas,
    topology_cache: *snail.TrueTypeGlyphTopologyCache,
) !void {
    for (PRINTABLE_ASCII) |ch| {
        _ = arena.reset(.retain_capacity);
        const scratch = arena.allocator();
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        const info = atlas.face_glyphs[0].getGlyph(glyph_id) orelse continue;
        const hint = machine.hintCachedGlyph(scratch, topology_cache, glyph_id, .{
            .base = .{ .info = info, .page = atlas.pages[info.page_index] },
        }) catch |err| switch (err) {
            error.UnsupportedCompoundHinting => continue,
            else => return err,
        };
        std.mem.doNotOptimizeAway(hint.curveDeltaBytes());
    }
}

fn timeRecordBuild(
    prepared: *const snail.PreparedResources,
    scene: *const snail.Scene,
) !f64 {
    const allocator = std.heap.smp_allocator;
    for (0..RECORD_WARMUP) |_| {
        var prepared_scene = try snail.PreparedScene.initOwned(allocator, prepared, scene);
        std.mem.doNotOptimizeAway(prepared_scene.wordCount());
        prepared_scene.deinit();
    }

    const start = nowNs();
    for (0..RECORD_ITERS) |_| {
        var prepared_scene = try snail.PreparedScene.initOwned(allocator, prepared, scene);
        std.mem.doNotOptimizeAway(prepared_scene.wordCount());
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

            const opts = drawState(WIDTH, HEIGHT, mode.aa);
            var resources = try uploadSceneResources(allocator, timer.renderer(), &bundle);
            defer resources.deinit();
            var prepared_scene = try snail.PreparedScene.initOwned(allocator, &resources, &bundle.scene);
            defer prepared_scene.deinit();

            const record_us = try timeRecordBuild(&resources, &bundle.scene);
            const draw_us = try timer.timeDraw(&resources, &prepared_scene, opts);

            try rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .record_us = record_us,
                .draw_us = draw_us,
                .words = prepared_scene.wordCount(),
                .segments = prepared_scene.segments.len,
            });
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const options = drawState(WIDTH, HEIGHT, .rgb);

    const font_data = assets.noto_sans_regular;
    const snail_prep = try benchSnailPrep(allocator, font_data);
    const vector_prep = try timeVectorFreeze();
    const ft = try freetype.bench(font_data, .{
        .prep_runs = PREP_RUNS,
        .text_iters = TEXT_ITERS,
        .printable_ascii = PRINTABLE_ASCII[0..],
        .sizes = SIZES[0..],
        .short = SHORT,
        .sentence = SENTENCE,
        .paragraph = PARAGRAPH,
    });

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
        .{ .data = assets.noto_sans_bold, .weight = .bold },
        .{ .data = assets.noto_sans_arabic, .fallback = true },
        .{ .data = assets.noto_sans_devanagari, .fallback = true },
        .{ .data = assets.noto_sans_thai, .fallback = true },
    }, &.{ SHORT, SENTENCE, PARAGRAPH, ARABIC_TEXT, DEVANAGARI_TEXT, THAI_TEXT });
    defer atlas.deinit();
    try prepareSceneText(&atlas);

    const cpu_pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels);
    var cpu = snail.CpuRenderer.init(cpu_pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var cpu_renderer = cpu.asRenderer();

    var cpu_pool: snail.ThreadPool = undefined;
    try cpu_pool.init(allocator, .{});
    defer cpu_pool.deinit();
    const cpu_pixels_threaded = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels_threaded);
    var cpu_threaded = snail.CpuRenderer.init(cpu_pixels_threaded.ptr, WIDTH, HEIGHT, WIDTH * 4);
    cpu_threaded.setThreadPool(&cpu_pool);
    var cpu_threaded_renderer = cpu_threaded.asRenderer();

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
        cpu_resources[i] = try uploadSceneResources(allocator, &cpu_renderer, &bundles[i]);
        cpu_resource_count += 1;
        prepared_scenes[i] = try snail.PreparedScene.initOwned(allocator, &cpu_resources[i], &bundles[i].scene);
        prepared_count += 1;
        record_rows[i] = .{
            .scene = kind,
            .us = try timeRecordBuild(&cpu_resources[i], &bundles[i].scene),
            .commands = bundles[i].scene.commandCount(),
            .words = prepared_scenes[i].wordCount(),
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
            .words = prepared_scenes[i].wordCount(),
            .segments = prepared_scenes[i].segments.len,
            .instance_bytes = prepared_scenes[i].wordCount() * @sizeOf(u32),
            .us = try render_timing.timeCpuDraw(&cpu_renderer, &cpu_resources[i], &prepared_scenes[i], options, cpu_pixels, CPU_WARMUP, CPU_FRAMES),
        });
    }

    for (scene_kinds, 0..) |kind, i| {
        try render_rows.append(allocator, .{
            .backend = "CPU (threaded)",
            .scene = kind,
            .frames = CPU_FRAMES,
            .commands = bundles[i].scene.commandCount(),
            .words = prepared_scenes[i].wordCount(),
            .segments = prepared_scenes[i].segments.len,
            .instance_bytes = prepared_scenes[i].wordCount() * @sizeOf(u32),
            .us = try render_timing.timeCpuDraw(&cpu_threaded_renderer, &cpu_resources[i], &prepared_scenes[i], options, cpu_pixels_threaded, CPU_WARMUP, CPU_FRAMES),
        });
    }

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
    defer gl_ctx.deinit();
    const framebuffer = render_timing.initFramebuffer(WIDTH, HEIGHT);
    defer render_timing.destroyFramebuffer(framebuffer);

    var gl_renderer_state = try snail.GlRenderer.init(allocator);
    defer gl_renderer_state.deinit();
    var gl_renderer = gl_renderer_state.asRenderer();
    for (scene_kinds, 0..) |kind, i| {
        var gl_resources = try uploadSceneResources(allocator, &gl_renderer, &bundles[i]);
        defer gl_resources.deinit();
        var gl_scene = try snail.PreparedScene.initOwned(allocator, &gl_resources, &bundles[i].scene);
        defer gl_scene.deinit();
        try render_rows.append(allocator, .{
            .backend = gl_renderer_state.backendName(),
            .scene = kind,
            .frames = GPU_FRAMES,
            .commands = bundles[i].scene.commandCount(),
            .words = gl_scene.wordCount(),
            .segments = gl_scene.segments.len,
            .instance_bytes = gl_scene.wordCount() * @sizeOf(u32),
            .us = try render_timing.timeGlDraw(&gl_renderer, &gl_resources, &gl_scene, options, GPU_WARMUP, GPU_FRAMES),
        });
    }

    var vk_state: if (build_options.enable_vulkan) ?snail.VulkanRenderer else void = if (build_options.enable_vulkan) null else {};
    var vk_renderer: if (build_options.enable_vulkan) snail.Renderer else void = undefined;
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
        errdefer vulkan_platform.deinitOffscreen();
        vk_state = try snail.VulkanRenderer.init(allocator, vk_ctx);
        errdefer if (vk_state) |*s| s.deinit();
        vk_renderer = vk_state.?.asRenderer();
        for (scene_kinds, 0..) |kind, i| {
            var vk_resources = try uploadSceneResources(allocator, &vk_renderer, &bundles[i]);
            defer vk_resources.deinit();
            var vk_scene = try snail.PreparedScene.initOwned(allocator, &vk_resources, &bundles[i].scene);
            defer vk_scene.deinit();
            try render_rows.append(allocator, .{
                .backend = vk_state.?.backendName(),
                .scene = kind,
                .frames = GPU_FRAMES,
                .commands = bundles[i].scene.commandCount(),
                .words = vk_scene.wordCount(),
                .segments = vk_scene.segments.len,
                .instance_bytes = vk_scene.wordCount() * @sizeOf(u32),
                .us = try render_timing.timeVulkanDraw(&vk_state.?, &vk_renderer, &vk_resources, &vk_scene, options, GPU_WARMUP, GPU_FRAMES),
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
            opts: snail.DrawState,
        ) !f64 {
            return render_timing.timeCpuDraw(self.renderer_ptr, prepared, scene, opts, self.pixels_buf, CPU_WARMUP, CPU_FRAMES);
        }
    };
    try benchModes(allocator, "CPU", &atlas, &mode_rows, CpuTimer{ .renderer_ptr = &cpu_renderer, .pixels_buf = cpu_pixels });
    try benchModes(allocator, "CPU (threaded)", &atlas, &mode_rows, CpuTimer{ .renderer_ptr = &cpu_threaded_renderer, .pixels_buf = cpu_pixels_threaded });

    const GlTimer = struct {
        renderer_ptr: *snail.Renderer,
        fn renderer(self: @This()) *snail.Renderer {
            return self.renderer_ptr;
        }
        fn timeDraw(
            self: @This(),
            prepared: *const snail.PreparedResources,
            scene: *const snail.PreparedScene,
            opts: snail.DrawState,
        ) !f64 {
            return render_timing.timeGlDraw(self.renderer_ptr, prepared, scene, opts, GPU_WARMUP, GPU_FRAMES);
        }
    };
    try benchModes(allocator, gl_renderer_state.backendName(), &atlas, &mode_rows, GlTimer{ .renderer_ptr = &gl_renderer });

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
                opts: snail.DrawState,
            ) !f64 {
                return render_timing.timeVulkanDraw(self.state, self.renderer_ptr, prepared, scene, opts, GPU_WARMUP, GPU_FRAMES);
            }
        };
        try benchModes(allocator, vk_state.?.backendName(), &atlas, &mode_rows, VkTimer{ .state = &vk_state.?, .renderer_ptr = &vk_renderer });
    }

    std.debug.print(
        \\# Snail Benchmarks
        \\
        \\NotoSans-Regular, {d} prep runs, {d} text iterations, {d} draw-record iterations.
        \\
        \\The vector workload contains filled and stroked rounded rectangles, ellipses, and custom cubic/quadratic paths. Vulkan rows are emitted unless the build is configured with `-Dvulkan=false`.
        \\
        \\
    , .{ PREP_RUNS, TEXT_ITERS, RECORD_ITERS });
    report.printHardwareTable(true, build_options.enable_vulkan);
    report.printPreparationTables(snail_prep, vector_prep, ft);
    report.printTextTable(&text_rows);
    report.printRecordTable(&record_rows);
    report.printRenderTable(WIDTH, HEIGHT, CPU_FRAMES, GPU_FRAMES, render_rows.items);
    report.printModeTable(mode_rows.items);
}
