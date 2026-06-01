//! Consolidated benchmarks for pasteable README tables.
//!
//! Covers preparation, text shaping + picture build, vector picture build,
//! draw-record emit, and prepared rendering on each enabled CPU, GL,
//! OpenGL ES, and Vulkan backend.
//!
//! Scenarios preserved from the legacy bench (8 scene kinds, 4 text
//! workloads × hinted/un-hinted, two render modes, FreeType comparison).
//! Adds one new scenario: a zoom-sweep that re-builds the banner at a
//! sequence of ppems with hinting on, measuring per-ppem rebuild cost vs
//! steady-state render. This is the data we want for the
//! BandReuseProof keep/delete decision.

const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail");
const egl_offscreen = @import("demo_platform_offscreen_gl");
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};
const freetype = @import("bench/freetype.zig");
const render_timing = @import("bench/render_timing.zig");
const report = @import("bench/report.zig");

// ── Knobs ──

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

const ZOOM_WARMUP = 5;
const ZOOM_REBUILD_RUNS = 20;
const ZOOM_RENDER_FRAMES = 50;
const ZOOM_W: u32 = 1280;
const ZOOM_H: u32 = 720;
const ZOOM_PPEMS = [_]u32{ 12, 14, 16, 18, 24, 32, 48 };

// ── Corpora ──

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

// ── Scenarios ──

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
const hinted_text_workloads = text_workloads;

const SceneKind = enum {
    text,
    rich_text,
    vector,
    mixed,
    multi_script,
    hinted_text,
    hinted_mixed,
    hinted_multi_script,

    pub fn name(self: SceneKind) []const u8 {
        return switch (self) {
            .text => "Text",
            .rich_text => "Rich text",
            .vector => "Vector paths",
            .mixed => "Mixed text + vector",
            .multi_script => "Multi-script text",
            .hinted_text => "Text (TT hinted)",
            .hinted_mixed => "Mixed text + vector (TT hinted)",
            .hinted_multi_script => "Multi-script text (TT hinted)",
        };
    }

    pub fn isHinted(self: SceneKind) bool {
        return switch (self) {
            .hinted_text, .hinted_mixed, .hinted_multi_script => true,
            else => false,
        };
    }

    pub fn needsText(self: SceneKind) bool {
        return switch (self) {
            .vector => false,
            else => true,
        };
    }

    pub fn needsVector(self: SceneKind) bool {
        return switch (self) {
            .vector, .mixed, .hinted_mixed => true,
            else => false,
        };
    }

    pub fn isMultiScript(self: SceneKind) bool {
        return switch (self) {
            .multi_script, .hinted_multi_script => true,
            else => false,
        };
    }

    pub fn isRich(self: SceneKind) bool {
        return self == .rich_text;
    }
};

const scene_kinds = [_]SceneKind{
    .text,
    .rich_text,
    .vector,
    .mixed,
    .multi_script,
    .hinted_text,
    .hinted_mixed,
    .hinted_multi_script,
};

const RenderMode = struct {
    aa: snail.SubpixelOrder,

    pub fn aaName(self: RenderMode) []const u8 {
        return subpixelOrderName(self.aa);
    }
};

const render_modes = [_]RenderMode{
    .{ .aa = .none },
    .{ .aa = .rgb },
};

const mode_scene_kinds = [_]SceneKind{ .text, .rich_text, .multi_script };

fn subpixelOrderName(order: snail.SubpixelOrder) []const u8 {
    return switch (order) {
        .none => "grayscale",
        .rgb => "subpixel rgb",
        .bgr => "subpixel bgr",
        .vrgb => "subpixel vrgb",
        .vbgr => "subpixel vbgr",
    };
}

fn effectiveAaLabel(order: snail.SubpixelOrder, supports_lcd: bool) []const u8 {
    if (order == .none) return "grayscale";
    if (supports_lcd) return subpixelOrderName(order);
    return "grayscale (LCD unavailable)";
}

// ── Scene text/lines (match legacy values) ──

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

// ── Row types ──

const SnailPrep = struct {
    font_load_us: f64,
    ascii_prep_us: f64,
    ascii_hint_setup_us: f64,
    ascii_hint_execute_us: f64,
    ascii_hint_us: f64,
    paragraph_hint_context_cold_us: f64,
    paragraph_hint_context_warm_us: f64,
};

const VectorPrep = struct {
    freeze_us: f64,
    shapes: usize,
};

const TextRow = struct {
    label: []const u8,
    snail_us: f64,
    ft_us: ?f64,
};

const RecordRow = struct {
    scene: SceneKind,
    us: f64,
    shapes: usize,
    words: usize,
    segments: usize,
};

const ModeRow = struct {
    backend: []const u8,
    scene: SceneKind,
    mode: RenderMode,
    effective_aa: []const u8,
    record_us: f64,
    draw_us: f64,
    words: usize,
    segments: usize,
};

const RenderRow = struct {
    backend: []const u8,
    scene: SceneKind,
    effective_aa: []const u8,
    frames: usize,
    shapes: usize,
    words: usize,
    segments: usize,
    instance_bytes: usize,
    us: f64,
};

const ZoomRow = struct {
    ppem: u32,
    rebuild_us: f64,
    render_us: f64,
    shapes: usize,
    words: usize,
};

// ── Timing helpers ──

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
        .raster = .{ .subpixel_order = subpixel_order, .coverage_transfer = .{ .exponent = 1.0 } },
    };
}

// ── Face / font management ──

const FACE_COUNT: usize = 5;
const FONT_COUNT: usize = 5;
// face_index → font_id; regular/bold/arabic/devanagari/thai (deduped via Shaper).
const FACE_TO_FONT_ID = [FACE_COUNT]u32{ 0, 1, 2, 3, 4 };

const FontSet = struct {
    allocator: std.mem.Allocator,
    shaper: snail.Shaper,
    fonts: [FONT_COUNT]snail.Font,
    has_hinter: bool,

    fn init(allocator: std.mem.Allocator) !FontSet {
        var shaper = try snail.Shaper.init(allocator, &.{
            .{ .data = assets.noto_sans_regular },
            .{ .data = assets.noto_sans_bold, .weight = .bold },
            .{ .data = assets.noto_sans_arabic, .fallback = true },
            .{ .data = assets.noto_sans_devanagari, .fallback = true },
            .{ .data = assets.noto_sans_thai, .fallback = true },
        });
        errdefer shaper.deinit();

        var fonts: [FONT_COUNT]snail.Font = undefined;
        const datas = [_][]const u8{
            assets.noto_sans_regular,
            assets.noto_sans_bold,
            assets.noto_sans_arabic,
            assets.noto_sans_devanagari,
            assets.noto_sans_thai,
        };
        var inited: usize = 0;
        errdefer for (fonts[0..inited]) |*f| f.deinit();
        for (datas, 0..) |data, i| {
            fonts[i] = try snail.Font.init(data);
            inited = i + 1;
        }

        var has_hinter = false;
        shaper.attachHinter(0) catch {};
        if (shaper.hinterForFace(0) != null) has_hinter = true;

        return .{
            .allocator = allocator,
            .shaper = shaper,
            .fonts = fonts,
            .has_hinter = has_hinter,
        };
    }

    fn deinit(self: *FontSet) void {
        for (&self.fonts) |*f| f.deinit();
        self.shaper.deinit();
        self.* = undefined;
    }
};

fn hintPpem26_6(em: f32) !u32 {
    const ppem = em * 64.0;
    if (!std.math.isFinite(ppem) or ppem < 1.0) return error.HintUnavailable;
    return @intFromFloat(@round(ppem));
}

// ── Atlas + Picture construction ──

const SceneBuild = struct {
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    /// Reset between path/glyph producer calls so intermediate buffers
    /// (split-at-extrema, prepared, band scratch) come from a bump
    /// pointer instead of the gpa.
    scratch_arena: std.heap.ArenaAllocator,
    owned_curves: std.ArrayList(snail.GlyphCurves),
    entries: std.ArrayList(snail.AtlasEntry),
    shapes: std.ArrayList(snail.Shape),
    extra_layer_storage: std.ArrayList([]snail.AtlasLayer),
    next_path_id: u32,

    fn init(allocator: std.mem.Allocator, pool: *snail.PagePool) SceneBuild {
        return .{
            .allocator = allocator,
            .pool = pool,
            .scratch_arena = std.heap.ArenaAllocator.init(allocator),
            .owned_curves = .empty,
            .entries = .empty,
            .shapes = .empty,
            .extra_layer_storage = .empty,
            .next_path_id = 0,
        };
    }

    fn deinit(self: *SceneBuild) void {
        for (self.owned_curves.items) |*c| c.deinit();
        self.owned_curves.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.shapes.deinit(self.allocator);
        for (self.extra_layer_storage.items) |s| self.allocator.free(s);
        self.extra_layer_storage.deinit(self.allocator);
        self.scratch_arena.deinit();
        self.* = undefined;
    }

    fn scratch(self: *SceneBuild) std.mem.Allocator {
        return self.scratch_arena.allocator();
    }

    /// Call after each producer call to drop the just-allocated
    /// intermediates while keeping the arena's backing capacity.
    fn resetScratch(self: *SceneBuild) void {
        _ = self.scratch_arena.reset(.retain_capacity);
    }

    fn freezeAtlas(self: *SceneBuild) !snail.Atlas {
        return snail.Atlas.from(self.allocator, self.pool, self.entries.items);
    }

    fn freezePicture(self: *SceneBuild) !snail.Picture {
        return snail.Picture.from(self.allocator, self.shapes.items);
    }
};

/// Add a stroked + filled rounded rect or ellipse to a SceneBuild.
fn addFilledPath(
    self: *SceneBuild,
    path: *const snail.paths.Path,
    paint: snail.Paint,
) !void {
    const curves = try snail.paths.pathToCurves(self.allocator, self.scratch(), path);
    self.resetScratch();
    if (curves.isEmpty()) {
        var owned = curves;
        owned.deinit();
        return;
    }
    try self.owned_curves.append(self.allocator, curves);
    const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
    self.next_path_id += 1;
    try self.entries.append(self.allocator, .{
        .key = key,
        .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
        .paint = paint,
    });
    try self.shapes.append(self.allocator, .{
        .key = key,
        .local_transform = .identity,
        .local_color = .{ 1, 1, 1, 1 },
    });
}

fn addStrokedPath(
    self: *SceneBuild,
    path: *const snail.paths.Path,
    stroke: snail.StrokeStyle,
) !void {
    const curves = try snail.paths.strokeToCurves(self.allocator, self.scratch(), path, stroke);
    self.resetScratch();
    if (curves.isEmpty()) {
        var owned = curves;
        owned.deinit();
        return;
    }
    try self.owned_curves.append(self.allocator, curves);
    const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = self.next_path_id };
    self.next_path_id += 1;
    try self.entries.append(self.allocator, .{
        .key = key,
        .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
        .paint = stroke.paint,
    });
    try self.shapes.append(self.allocator, .{
        .key = key,
        .local_transform = .identity,
        .local_color = .{ 1, 1, 1, 1 },
    });
}

/// Insert the unhinted curves for every glyph in `shaped` into `build`'s
/// text atlas (deduped by `recordKey.unhintedGlyph` key).
fn ensureUnhintedRunCurves(
    build: *SceneBuild,
    fonts: *FontSet,
    glyph_caches: []snail.font.GlyphCache,
    shaped: *const snail.ShapedText,
) !void {
    for (shaped.glyphs) |g| {
        const fid = FACE_TO_FONT_ID[g.face_index];
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(build.entries.items, key)) continue;
        const curves = try fonts.fonts[fid].extractCurves(build.allocator, build.scratch(), &glyph_caches[fid], g.glyph_id);
        try build.owned_curves.append(build.allocator, curves);
        try build.entries.append(build.allocator, .{
            .key = key,
            .curves = build.owned_curves.items[build.owned_curves.items.len - 1],
        });
    }
}

fn ensureHintedRunCurves(
    build: *SceneBuild,
    fonts: *FontSet,
    shaped: *const snail.ShapedText,
    ppem_26_6: u32,
) !bool {
    const hinter = fonts.shaper.hinterForFace(0) orelse return false;
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    for (shaped.glyphs) |g| {
        if (g.face_index != 0) return false; // only face 0 is hintable
        const key = snail.recordKey.hintedGlyph(0, g.glyph_id, ppem_26_6);
        if (containsKey(build.entries.items, key)) continue;
        const curves = hinter.hint(build.allocator, build.allocator, g.glyph_id, ppem) catch return false;
        try build.owned_curves.append(build.allocator, curves);
        try build.entries.append(build.allocator, .{
            .key = key,
            .curves = build.owned_curves.items[build.owned_curves.items.len - 1],
        });
    }
    return true;
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

// ── Vector picture ──

fn buildVectorBuild(allocator: std.mem.Allocator, pool: *snail.PagePool) !SceneBuild {
    var build = SceneBuild.init(allocator, pool);
    errdefer build.deinit();

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
            const fill = snail.Paint{ .solid = colors[idx] };
            const stroke_paint = snail.Paint{ .solid = .{ 0.95, 0.96, 0.98, 0.95 } };
            const stroke_width = 1.5 + @as(f32, @floatFromInt((row + col) % 3));
            const stroke = snail.StrokeStyle{
                .paint = stroke_paint,
                .width = stroke_width,
                .join = .round,
                .placement = .inside,
            };

            switch ((row + col) % 3) {
                0 => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    try p.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, 10);
                    try addFilledPath(&build, &p, fill);
                    try addStrokedPath(&build, &p, stroke);
                },
                1 => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    try p.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 44 });
                    try addFilledPath(&build, &p, fill);
                    try addStrokedPath(&build, &p, stroke);
                },
                else => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    const scale: f32 = 0.8;
                    try p.moveTo(.{ .x = x + 0 * scale, .y = y + 32 * scale });
                    try p.cubicTo(
                        .{ .x = x + 18 * scale, .y = y - 8 * scale },
                        .{ .x = x + 46 * scale, .y = y - 8 * scale },
                        .{ .x = x + 64 * scale, .y = y + 32 * scale },
                    );
                    try p.quadTo(.{ .x = x + 32 * scale, .y = y + 62 * scale }, .{ .x = x + 0 * scale, .y = y + 32 * scale });
                    try p.close();
                    try addFilledPath(&build, &p, fill);
                    try addStrokedPath(&build, &p, .{
                        .paint = .{ .solid = .{ 0.08, 0.09, 0.11, 1 } },
                        .width = 1.25,
                        .join = .round,
                        .placement = .inside,
                    });
                },
            }
        }
    }

    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(.{ .x = 18, .y = 314, .w = 580, .h = 28 }, 8);
        try addFilledPath(&build, &p, .{ .solid = .{ 0.08, 0.10, 0.13, 0.82 } });
        try addStrokedPath(&build, &p, .{
            .paint = .{ .solid = .{ 0.55, 0.68, 0.85, 1 } },
            .width = 2,
            .join = .round,
            .placement = .inside,
        });
    }

    return build;
}

fn timeVectorBuild(allocator: std.mem.Allocator) !VectorPrep {
    var total_us: f64 = 0;
    var shapes: usize = 0;
    for (0..PREP_RUNS) |_| {
        var pool = try snail.PagePool.init(allocator, .{ .max_layers = 2, .curve_words_per_page = 1 << 16, .band_words_per_page = 1 << 14 });
        defer pool.deinit();
        const start = nowNs();
        var build = try buildVectorBuild(allocator, pool);
        total_us += usFrom(start);
        shapes = build.shapes.items.len;
        build.deinit();
    }
    return .{ .freeze_us = total_us / PREP_RUNS, .shapes = shapes };
}

// ── Scene bundle ──

const SceneBundle = struct {
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    build: SceneBuild,
    glyph_caches: [FONT_COUNT]snail.font.GlyphCache,
    atlas: snail.Atlas,
    picture: snail.Picture,

    fn deinit(self: *SceneBundle) void {
        self.picture.deinit();
        self.atlas.deinit();
        for (&self.glyph_caches) |*c| c.deinit();
        self.build.deinit();
        self.* = undefined;
    }
};

fn buildScene(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    fonts: *FontSet,
    kind: SceneKind,
) !SceneBundle {
    var build = SceneBuild.init(allocator, pool);
    errdefer build.deinit();

    var glyph_caches: [FONT_COUNT]snail.font.GlyphCache = undefined;
    for (&glyph_caches) |*c| c.* = snail.font.GlyphCache.init(allocator);
    errdefer for (&glyph_caches) |*c| c.deinit();

    if (kind.needsVector()) try appendVectorPathsTo(&build);

    if (kind.isRich()) {
        try buildRichText(&build, fonts, &glyph_caches);
    } else if (kind.needsText()) {
        const lines: []const TextLine = if (kind.isMultiScript()) scene_multi_script_lines[0..] else scene_text_lines[0..];
        for (lines) |line| {
            try addShapedLine(&build, fonts, &glyph_caches, line, kind.isHinted());
        }
    }

    const atlas = try build.freezeAtlas();
    var atlas_owned = atlas;
    errdefer atlas_owned.deinit();
    const picture = try build.freezePicture();

    return .{
        .allocator = allocator,
        .pool = pool,
        .build = build,
        .glyph_caches = glyph_caches,
        .atlas = atlas_owned,
        .picture = picture,
    };
}

/// Reimplement the vector path generation against the caller-supplied build
/// rather than allocating a separate SceneBuild and trying to move state.
fn appendVectorPathsTo(build: *SceneBuild) !void {
    const allocator = build.allocator;
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
            const fill = snail.Paint{ .solid = colors[idx] };
            const stroke = snail.StrokeStyle{
                .paint = .{ .solid = .{ 0.95, 0.96, 0.98, 0.95 } },
                .width = 1.5 + @as(f32, @floatFromInt((row + col) % 3)),
                .join = .round,
                .placement = .inside,
            };
            switch ((row + col) % 3) {
                0 => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    try p.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, 10);
                    try addFilledPath(build, &p, fill);
                    try addStrokedPath(build, &p, stroke);
                },
                1 => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    try p.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 44 });
                    try addFilledPath(build, &p, fill);
                    try addStrokedPath(build, &p, stroke);
                },
                else => {
                    var p = snail.paths.Path.init(allocator);
                    defer p.deinit();
                    const scale: f32 = 0.8;
                    try p.moveTo(.{ .x = x + 0 * scale, .y = y + 32 * scale });
                    try p.cubicTo(
                        .{ .x = x + 18 * scale, .y = y - 8 * scale },
                        .{ .x = x + 46 * scale, .y = y - 8 * scale },
                        .{ .x = x + 64 * scale, .y = y + 32 * scale },
                    );
                    try p.quadTo(.{ .x = x + 32 * scale, .y = y + 62 * scale }, .{ .x = x + 0 * scale, .y = y + 32 * scale });
                    try p.close();
                    try addFilledPath(build, &p, fill);
                    try addStrokedPath(build, &p, .{
                        .paint = .{ .solid = .{ 0.08, 0.09, 0.11, 1 } },
                        .width = 1.25,
                        .join = .round,
                        .placement = .inside,
                    });
                },
            }
        }
    }
    var p = snail.paths.Path.init(allocator);
    defer p.deinit();
    try p.addRoundedRect(.{ .x = 18, .y = 314, .w = 580, .h = 28 }, 8);
    try addFilledPath(build, &p, .{ .solid = .{ 0.08, 0.10, 0.13, 0.82 } });
    try addStrokedPath(build, &p, .{
        .paint = .{ .solid = .{ 0.55, 0.68, 0.85, 1 } },
        .width = 2,
        .join = .round,
        .placement = .inside,
    });
}

fn addShapedLine(
    build: *SceneBuild,
    fonts: *FontSet,
    glyph_caches: []snail.font.GlyphCache,
    line: TextLine,
    hinted: bool,
) !void {
    const allocator = build.allocator;
    if (hinted and fonts.has_hinter) {
        const ppem_26_6 = hintPpem26_6(line.size) catch return addShapedLineUnhinted(build, fonts, glyph_caches, line);
        var shaped = try fonts.shaper.shapeOpts(allocator, line.style, line.text, .{ .target_ppem = snail.HintPpem.uniform(ppem_26_6) });
        defer shaped.deinit();
        const ok = ensureHintedRunCurves(build, fonts, &shaped, ppem_26_6) catch false;
        if (ok) {
            var pic = try snail.hintedShapedRunPicture(allocator, &shaped, .{
                .baseline = .{ .x = line.x, .y = line.y },
                .em = line.size,
                .ppem_26_6 = ppem_26_6,
                .color = line.color,
                .face_to_font_id = &FACE_TO_FONT_ID,
            });
            defer pic.deinit();
            try build.shapes.appendSlice(allocator, pic.shapes);
            return;
        }
        // Hinting failed (non-Latin fallback face etc) — fall through to unhinted.
    }
    return addShapedLineUnhinted(build, fonts, glyph_caches, line);
}

fn addShapedLineUnhinted(
    build: *SceneBuild,
    fonts: *FontSet,
    glyph_caches: []snail.font.GlyphCache,
    line: TextLine,
) !void {
    const allocator = build.allocator;
    var shaped = try fonts.shaper.shape(allocator, line.style, line.text);
    defer shaped.deinit();
    try ensureUnhintedRunCurves(build, fonts, glyph_caches, &shaped);
    var pic = try snail.shapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = line.x, .y = line.y },
        .em = line.size,
        .color = line.color,
        .face_to_font_id = &FACE_TO_FONT_ID,
    });
    defer pic.deinit();
    try build.shapes.appendSlice(allocator, pic.shapes);
}

fn buildRichText(
    build: *SceneBuild,
    fonts: *FontSet,
    glyph_caches: []snail.font.GlyphCache,
) !void {
    // Match the legacy rich-text layout: a wide variety of weights, sizes,
    // colors, and gradient paints across three lines.
    var x: f32 = 18.0;
    var y: f32 = 46.0;

    x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "RICH ", x, y, 30.0, .{ .solid = .{ 0.95, 0.97, 1.0, 1.0 } });
    {
        const grad = snail.Paint{ .linear_gradient = .{
            .start = .{ .x = x, .y = y - 30.0 },
            .end = .{ .x = x + 150.0, .y = y },
            .start_color = .{ 0.30, 0.65, 1.0, 1.0 },
            .end_color = .{ 1.0, 0.35, 0.58, 1.0 },
        } };
        x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "gradient", x, y, 30.0, grad);
    }
    _ = try addRichRun(build, fonts, glyph_caches, .{}, " runs", x, y, 22.0, .{ .solid = .{ 0.72, 0.78, 0.86, 1.0 } });

    x = 18.0;
    y = 94.0;
    x += try addRichRun(build, fonts, glyph_caches, .{}, "status  ", x, y, 18.0, .{ .solid = .{ 0.60, 0.68, 0.76, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "HP ", x, y, 24.0, .{ .solid = .{ 0.80, 0.92, 0.86, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "83", x, y, 28.0, .{ .solid = .{ 0.25, 0.92, 0.50, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{}, "   shield ", x, y, 18.0, .{ .solid = .{ 0.62, 0.72, 0.82, 1.0 } });
    {
        const grad = snail.Paint{ .linear_gradient = .{
            .start = .{ .x = x, .y = y - 22.0 },
            .end = .{ .x = x + 76.0, .y = y },
            .start_color = .{ 0.20, 0.82, 0.92, 1.0 },
            .end_color = .{ 0.85, 0.96, 0.45, 1.0 },
        } };
        _ = try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "online", x, y, 22.0, grad);
    }

    x = 18.0;
    y = 142.0;
    x += try addRichRun(build, fonts, glyph_caches, .{}, "per-letter  ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
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
        const sz = 24.0 + @as(f32, @floatFromInt(i % 3)) * 3.0;
        x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, &one, x, y, sz, .{ .solid = colors[i] });
    }
    x += try addRichRun(build, fonts, glyph_caches, .{}, "  alerts ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "OK", x, y, 20.0, .{ .solid = .{ 0.36, 0.92, 0.52, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{}, " / ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "WARN", x, y, 20.0, .{ .solid = .{ 0.98, 0.72, 0.32, 1.0 } });
    x += try addRichRun(build, fonts, glyph_caches, .{}, " / ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    _ = try addRichRun(build, fonts, glyph_caches, .{ .weight = .bold }, "CRIT", x, y, 20.0, .{ .solid = .{ 1.0, 0.40, 0.44, 1.0 } });
}

/// Add a single run with a solid or gradient/image paint. Solid paints
/// emit through the shaped text path (deduped glyph atlas); gradient /
/// image paints go through the path namespace with `mapPaintToLocal`
/// baking the world paint into glyph-local coordinates. Returns the
/// run's x advance.
fn addRichRun(
    build: *SceneBuild,
    fonts: *FontSet,
    glyph_caches: []snail.font.GlyphCache,
    style: snail.FontStyle,
    text: []const u8,
    x: f32,
    y: f32,
    em: f32,
    paint: snail.Paint,
) !f32 {
    const allocator = build.allocator;
    var shaped = try fonts.shaper.shape(allocator, style, text);
    defer shaped.deinit();
    const advance = em * shaped.advanceX();
    switch (paint) {
        .solid => |color| {
            try ensureUnhintedRunCurves(build, fonts, glyph_caches, &shaped);
            var pic = try snail.shapedRunPicture(allocator, &shaped, .{
                .baseline = .{ .x = x, .y = y },
                .em = em,
                .color = color,
                .face_to_font_id = &FACE_TO_FONT_ID,
            });
            defer pic.deinit();
            try build.shapes.appendSlice(allocator, pic.shapes);
        },
        else => {
            // Per-glyph paint baked into glyph-local space.
            for (shaped.glyphs) |g| {
                const fid = FACE_TO_FONT_ID[g.face_index];
                const pen_x = x + em * g.x_offset;
                const pen_y = y + em * g.y_offset;
                const transform = snail.Transform2D{
                    .xx = em,
                    .xy = 0,
                    .tx = pen_x,
                    .yx = 0,
                    .yy = -em,
                    .ty = pen_y,
                };
                const local_paint = snail.mapPaintToLocal(paint, transform) orelse continue;
                const curves = try fonts.fonts[fid].extractCurves(allocator, allocator, &glyph_caches[fid], g.glyph_id);
                try build.owned_curves.append(allocator, curves);
                const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = build.next_path_id };
                build.next_path_id += 1;
                try build.entries.append(allocator, .{
                    .key = key,
                    .curves = build.owned_curves.items[build.owned_curves.items.len - 1],
                    .paint = local_paint,
                });
                try build.shapes.append(allocator, .{
                    .key = key,
                    .local_transform = transform,
                    .local_color = .{ 1, 1, 1, 1 },
                });
            }
        },
    }
    return advance;
}

// ── Snail preparation timing ──

fn benchSnailPrep(allocator: std.mem.Allocator) !SnailPrep {
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var f = try snail.Font.init(assets.noto_sans_regular);
        font_load_total_us += usFrom(start);
        f.deinit();
    }

    // ASCII glyph prep: extract curves into a fresh pool. Uses an
    // ArenaAllocator as `scratch` for the per-glyph intermediate
    // buffers; resets between glyphs so the allocations collapse to
    // bump-pointer ops.
    var ascii_prep_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var pool = try snail.PagePool.init(allocator, .{ .max_layers = 2, .curve_words_per_page = 1 << 16, .band_words_per_page = 1 << 14 });
        defer pool.deinit();
        var font = try snail.Font.init(assets.noto_sans_regular);
        defer font.deinit();
        var cache = snail.font.GlyphCache.init(allocator);
        defer cache.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();

        var entries: std.ArrayListUnmanaged(snail.AtlasEntry) = .empty;
        defer entries.deinit(allocator);
        var owned: std.ArrayListUnmanaged(snail.GlyphCurves) = .empty;
        defer {
            for (owned.items) |*c| c.deinit();
            owned.deinit(allocator);
        }

        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = try font.glyphIndex(ch);
            if (gid == 0) continue;
            const curves = try font.extractCurves(allocator, scratch_arena.allocator(), &cache, gid);
            _ = scratch_arena.reset(.retain_capacity);
            try owned.append(allocator, curves);
            try entries.append(allocator, .{
                .key = snail.recordKey.unhintedGlyph(0, gid),
                .curves = owned.items[owned.items.len - 1],
            });
        }
        var atlas = try snail.Atlas.from(allocator, pool, entries.items);
        defer atlas.deinit();
        ascii_prep_total_us += usFrom(start);
    }

    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();

    const ascii_hint_setup_us = try timeHinterSetup(allocator, &font, 12 * 64);
    const ascii_hint_execute_us = try timeHinterExecute(allocator, &font, 12 * 64);
    const ascii_hint_us = try timeHinterFull(allocator, &font, 12 * 64);
    const paragraph_cold_us = try timeHinterParagraphCold(allocator, &font, 12 * 64);
    const paragraph_warm_us = try timeHinterParagraphWarm(allocator, &font, 12 * 64);

    return .{
        .font_load_us = font_load_total_us / PREP_RUNS,
        .ascii_prep_us = ascii_prep_total_us / PREP_RUNS,
        .ascii_hint_setup_us = ascii_hint_setup_us,
        .ascii_hint_execute_us = ascii_hint_execute_us,
        .ascii_hint_us = ascii_hint_us,
        .paragraph_hint_context_cold_us = paragraph_cold_us,
        .paragraph_hint_context_warm_us = paragraph_warm_us,
    };
}

fn timeHinterSetup(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var h = snail.Hinter.init(allocator, font) catch return 0;
        // Trigger machine init at this ppem (setup cost).
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        _ = h.advanceX26Dot6(0, ppem) catch 0;
        total += usFrom(start);
        h.deinit();
    }
    return total / PREP_RUNS;
}

fn timeHinterExecute(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var h = snail.Hinter.init(allocator, font) catch return 0;
    defer h.deinit();
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    // Warmup machine for this ppem.
    _ = h.advanceX26Dot6(0, ppem) catch 0;

    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        // Re-fresh per-run by clearing the glyph-cache only via a fresh
        // run at a slightly different ppem? Simpler: just measure VM
        // execute by reading advances for all ASCII glyphs in a hot
        // metrics-cache. We approximate "execute" by the warm advance
        // query loop, which still routes through the VM machine state.
        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = font.glyphIndex(ch) catch continue;
            _ = h.advanceX26Dot6(gid, ppem) catch continue;
        }
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterFull(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var h = snail.Hinter.init(allocator, font) catch return 0;
        defer h.deinit();
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = font.glyphIndex(ch) catch continue;
            var curves = h.hint(allocator, scratch_arena.allocator(), gid, ppem) catch continue;
            _ = scratch_arena.reset(.retain_capacity);
            curves.deinit();
        }
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterParagraphCold(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    // Cold: hinter constructed fresh, paragraph hinted once.
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var h = snail.Hinter.init(allocator, font) catch return 0;
        defer h.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        const start = nowNs();
        try hintParagraph(&h, font, allocator, &scratch_arena, ppem);
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterParagraphWarm(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var h = snail.Hinter.init(allocator, font) catch return 0;
    defer h.deinit();
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    // Warmup.
    try hintParagraph(&h, font, allocator, &scratch_arena, ppem);

    var total: f64 = 0;
    for (0..TEXT_ITERS) |_| {
        const start = nowNs();
        try hintParagraph(&h, font, allocator, &scratch_arena, ppem);
        total += usFrom(start);
    }
    return total / TEXT_ITERS;
}

fn hintParagraph(h: *snail.Hinter, font: *const snail.Font, allocator: std.mem.Allocator, scratch_arena: *std.heap.ArenaAllocator, ppem: snail.HintPpem) !void {
    for (PARAGRAPH) |ch| {
        const gid = font.glyphIndex(ch) catch continue;
        var curves = h.hint(allocator, scratch_arena.allocator(), gid, ppem) catch continue;
        _ = scratch_arena.reset(.retain_capacity);
        std.mem.doNotOptimizeAway(curves.curve_count);
        curves.deinit();
    }
}

// ── Text workload timing ──

fn lineFor(workload: TextWorkload) TextLine {
    return switch (workload) {
        .short => .{ .text = SHORT, .x = 0, .y = 24, .size = 24 },
        .sentence => .{ .text = SENTENCE, .x = 0, .y = 48, .size = 48 },
        .paragraph => .{ .text = PARAGRAPH, .x = 0, .y = 18, .size = 18 },
        .paragraph_sizes => unreachable,
    };
}

/// Lines for one workload iteration, shaped and atlas-resident.
/// Time(picture build) is measured separately from shape/atlas-prep
/// so the bench column matches the old README's "TextBlob" semantic:
/// pre-shaped input → per-frame draw description. Shaping cost is
/// reported separately in the "Preparation" table.
const PreparedLines = struct {
    items: std.ArrayListUnmanaged(PreparedLine) = .empty,
    pool: *snail.PagePool,
    fonts: *FontSet,
    glyph_caches: [FONT_COUNT]snail.font.GlyphCache,
    hinted: bool,

    fn init(allocator: std.mem.Allocator, pool: *snail.PagePool, fonts: *FontSet, hinted: bool) PreparedLines {
        var caches: [FONT_COUNT]snail.font.GlyphCache = undefined;
        for (&caches) |*c| c.* = snail.font.GlyphCache.init(allocator);
        return .{ .pool = pool, .fonts = fonts, .glyph_caches = caches, .hinted = hinted };
    }

    fn deinit(self: *PreparedLines, allocator: std.mem.Allocator) void {
        for (self.items.items) |*it| it.deinit();
        self.items.deinit(allocator);
        for (&self.glyph_caches) |*c| c.deinit();
    }

    fn add(self: *PreparedLines, allocator: std.mem.Allocator, line: TextLine) !void {
        const item = try prepareLine(allocator, self.pool, self.fonts, &self.glyph_caches, line, self.hinted);
        try self.items.append(allocator, item);
    }
};

const PreparedLine = struct {
    shaped: snail.ShapedText,
    line: TextLine,
    hinted: bool,
    ppem_26_6: u32 = 0, // only set when hinted == true and hinting succeeded

    fn deinit(self: *PreparedLine) void {
        self.shaped.deinit();
    }
};

fn prepareLine(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    fonts: *FontSet,
    glyph_caches: *[FONT_COUNT]snail.font.GlyphCache,
    line: TextLine,
    hinted: bool,
) !PreparedLine {
    // Mirror addShapedLine's setup but stop short of the picture build,
    // and stop short of releasing the shaped run — that's what the
    // timed loop is going to consume.
    if (hinted and fonts.has_hinter) {
        const ppem_26_6 = hintPpem26_6(line.size) catch return prepareLineUnhinted(allocator, pool, fonts, glyph_caches, line);
        var shaped = try fonts.shaper.shapeOpts(allocator, line.style, line.text, .{ .target_ppem = snail.HintPpem.uniform(ppem_26_6) });
        errdefer shaped.deinit();
        var build = SceneBuild.init(allocator, pool);
        defer build.deinit();
        const ok = ensureHintedRunCurves(&build, fonts, &shaped, ppem_26_6) catch false;
        if (!ok) {
            // Hinting failed (non-Latin fallback face etc) — fall through to unhinted.
            shaped.deinit();
            return prepareLineUnhinted(allocator, pool, fonts, glyph_caches, line);
        }
        return .{ .shaped = shaped, .line = line, .hinted = true, .ppem_26_6 = ppem_26_6 };
    }
    return prepareLineUnhinted(allocator, pool, fonts, glyph_caches, line);
}

fn prepareLineUnhinted(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    fonts: *FontSet,
    glyph_caches: *[FONT_COUNT]snail.font.GlyphCache,
    line: TextLine,
) !PreparedLine {
    var shaped = try fonts.shaper.shape(allocator, line.style, line.text);
    errdefer shaped.deinit();
    var build = SceneBuild.init(allocator, pool);
    defer build.deinit();
    try ensureUnhintedRunCurves(&build, fonts, glyph_caches, &shaped);
    return .{ .shaped = shaped, .line = line, .hinted = false };
}

fn prepareLines(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    fonts: *FontSet,
    workload: TextWorkload,
    hinted: bool,
) !PreparedLines {
    var prepared = PreparedLines.init(allocator, pool, fonts, hinted);
    errdefer prepared.deinit(allocator);
    switch (workload) {
        .short, .sentence, .paragraph => {
            try prepared.add(allocator, lineFor(workload));
        },
        .paragraph_sizes => {
            var y: f32 = 330;
            for (SIZES) |sz| {
                try prepared.add(allocator, .{
                    .text = PARAGRAPH,
                    .x = 0,
                    .y = y,
                    .size = @floatFromInt(sz),
                });
                y -= @as(f32, @floatFromInt(sz)) * 1.4;
            }
        },
    }
    return prepared;
}

fn buildPicturesForPreparedLines(
    allocator: std.mem.Allocator,
    prepared: *const PreparedLines,
) !usize {
    var shape_count: usize = 0;
    for (prepared.items.items) |*it| {
        if (it.hinted) {
            var pic = try snail.hintedShapedRunPicture(allocator, &it.shaped, .{
                .baseline = .{ .x = it.line.x, .y = it.line.y },
                .em = it.line.size,
                .ppem_26_6 = it.ppem_26_6,
                .color = it.line.color,
                .face_to_font_id = &FACE_TO_FONT_ID,
            });
            shape_count += pic.shapes.len;
            pic.deinit();
        } else {
            var pic = try snail.shapedRunPicture(allocator, &it.shaped, .{
                .baseline = .{ .x = it.line.x, .y = it.line.y },
                .em = it.line.size,
                .color = it.line.color,
                .face_to_font_id = &FACE_TO_FONT_ID,
            });
            shape_count += pic.shapes.len;
            pic.deinit();
        }
    }
    return shape_count;
}

fn timeTextWorkload(allocator: std.mem.Allocator, fonts: *FontSet, workload: TextWorkload) !f64 {
    var pool = try snail.PagePool.init(allocator, .{ .max_layers = 4, .curve_words_per_page = 1 << 18, .band_words_per_page = 1 << 16 });
    defer pool.deinit();
    var prepared = try prepareLines(allocator, pool, fonts, workload, false);
    defer prepared.deinit(allocator);

    for (0..TEXT_WARMUP) |_| {
        const s = try buildPicturesForPreparedLines(allocator, &prepared);
        std.mem.doNotOptimizeAway(s);
    }
    const start = nowNs();
    for (0..TEXT_ITERS) |_| {
        const s = try buildPicturesForPreparedLines(allocator, &prepared);
        std.mem.doNotOptimizeAway(s);
    }
    return usFrom(start) / TEXT_ITERS;
}

fn timeHintedTextWorkload(allocator: std.mem.Allocator, fonts: *FontSet, workload: TextWorkload) !f64 {
    var pool = try snail.PagePool.init(allocator, .{ .max_layers = 4, .curve_words_per_page = 1 << 18, .band_words_per_page = 1 << 16 });
    defer pool.deinit();
    var prepared = try prepareLines(allocator, pool, fonts, workload, true);
    defer prepared.deinit(allocator);

    for (0..TEXT_WARMUP) |_| {
        const s = try buildPicturesForPreparedLines(allocator, &prepared);
        std.mem.doNotOptimizeAway(s);
    }
    const start = nowNs();
    for (0..TEXT_ITERS) |_| {
        const s = try buildPicturesForPreparedLines(allocator, &prepared);
        std.mem.doNotOptimizeAway(s);
    }
    return usFrom(start) / TEXT_ITERS;
}

fn hintedTextWorkloadName(workload: TextWorkload) []const u8 {
    return switch (workload) {
        .short => "Short string (TT hinted @ 24px)",
        .sentence => "Sentence (TT hinted @ 48px)",
        .paragraph => "Paragraph (TT hinted @ 18px)",
        .paragraph_sizes => "Paragraph x 7 sizes (TT hinted)",
    };
}

// ── Record build (emit.emit) ──

fn timeRecordEmit(
    allocator: std.mem.Allocator,
    binding: snail.Binding,
    atlas: *const snail.Atlas,
    picture: *const snail.Picture,
) !struct { us: f64, words: usize, segments: usize } {
    const word_cap = snail.emit.wordBudget(picture, 0);
    const words = try allocator.alloc(u32, word_cap);
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, snail.emit.segmentBudget(picture, 0));
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    // Warmup
    for (0..RECORD_WARMUP) |_| {
        wlen = 0;
        slen = 0;
        _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture, .identity, .{ 1, 1, 1, 1 });
    }
    const start = nowNs();
    for (0..RECORD_ITERS) |_| {
        wlen = 0;
        slen = 0;
        _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture, .identity, .{ 1, 1, 1, 1 });
    }
    const us = usFrom(start) / RECORD_ITERS;
    return .{ .us = us, .words = wlen, .segments = slen };
}

/// Emit a heterogeneous DrawRecords blob for a scene. The caller owns the
/// returned buffers.
const EmittedRecords = struct {
    allocator: std.mem.Allocator,
    words: []u32,
    segments: []snail.DrawSegment,
    word_len: usize,
    segment_len: usize,
    shapes: usize,

    fn deinit(self: *EmittedRecords) void {
        self.allocator.free(self.words);
        self.allocator.free(self.segments);
        self.* = undefined;
    }
};

fn emitScene(
    allocator: std.mem.Allocator,
    binding: snail.Binding,
    atlas: *const snail.Atlas,
    picture: *const snail.Picture,
) !EmittedRecords {
    const word_cap = snail.emit.wordBudget(picture, 0);
    const words = try allocator.alloc(u32, word_cap);
    errdefer allocator.free(words);
    const seg_cap = @max(snail.emit.segmentBudget(picture, 0), 1);
    const segs = try allocator.alloc(snail.DrawSegment, seg_cap);
    errdefer allocator.free(segs);
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture, .identity, .{ 1, 1, 1, 1 });
    return .{
        .allocator = allocator,
        .words = words,
        .segments = segs,
        .word_len = wlen,
        .segment_len = slen,
        .shapes = picture.shapes.len,
    };
}

// ── Backend driving ──

// CPU prepared-pages capacity sized to cover all 8 scene atlases plus
// some headroom for the zoom sweep's banner caches reused later.

// ── Zoom sweep ──

const ZoomBuild = struct {
    pool: *snail.PagePool,
    assets_owned: ?*demo_banner.Assets,
    content: demo_banner.Content,
    cache: snail.CpuPreparedPages,
    bindings: [2]snail.Binding,
    words: []u32,
    segments: []snail.DrawSegment,
    word_len: usize,
    segment_len: usize,

    /// Tear down in reverse construction order. The cache and atlases
    /// hold references into the pool, so release them before the pool;
    /// pool owns the per-layer pages. The owned Assets carries the
    /// paint_image whose pixel storage is heap-allocated.
    fn deinit(self: *ZoomBuild, allocator: std.mem.Allocator) void {
        allocator.free(self.words);
        allocator.free(self.segments);
        self.cache.deinit();
        self.content.deinit();
        self.pool.deinit();
        if (self.assets_owned) |a| {
            a.deinit();
            allocator.destroy(a);
        }
        self.* = undefined;
    }
};

const demo_banner = @import("demo_banner");

fn benchZoomSweep(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(ZoomRow),
) !void {
    // Each ppem rebuilds the banner using a fresh Assets so the hinter
    // cache starts cold. This matches "what does a zoom step actually
    // cost" — the user changes scale, and snail rebuilds atlases/
    // pictures for the new per-glyph ppem.
    for (ZOOM_PPEMS) |ppem_px| {
        // Build once to capture shapes/words so we can report them.
        var preview = try zoomBuildOneCold(allocator, ppem_px);
        const shapes = preview.content.paths_picture.shapes.len + preview.content.text_picture.shapes.len;
        const words = preview.word_len;

        // Rebuild timing: PREP_RUNS fresh rebuilds (Assets fresh too so
        // the hinter cache is cold, which is what a zoom step needs).
        var rebuild_total: f64 = 0;
        for (0..ZOOM_REBUILD_RUNS) |_| {
            const start = nowNs();
            var tmp = try zoomBuildOneCold(allocator, ppem_px);
            rebuild_total += usFrom(start);
            tmp.deinit(allocator);
        }
        const rebuild_us = rebuild_total / ZOOM_REBUILD_RUNS;

        // Steady-state render: reuse `preview` so the cache is warm.
        const W: u32 = ZOOM_W;
        const H: u32 = ZOOM_H;
        const STRIDE: u32 = W * 4;
        const px = try allocator.alloc(u8, H * STRIDE);
        defer allocator.free(px);
        var renderer = snail.CpuRenderer.init(px.ptr, W, H, STRIDE);
        const state = drawState(W, H, .none);
        for (0..ZOOM_WARMUP) |_| {
            @memset(px, 0);
            try snail.drawCpu(&renderer, state, .{ .words = preview.words[0..preview.word_len], .segments = preview.segments[0..preview.segment_len] }, &.{&preview.cache});
        }
        const r_start = nowNs();
        for (0..ZOOM_RENDER_FRAMES) |_| {
            @memset(px, 0);
            try snail.drawCpu(&renderer, state, .{ .words = preview.words[0..preview.word_len], .segments = preview.segments[0..preview.segment_len] }, &.{&preview.cache});
        }
        const render_us = usFrom(r_start) / ZOOM_RENDER_FRAMES;

        try rows.append(allocator, .{
            .ppem = ppem_px,
            .rebuild_us = rebuild_us,
            .render_us = render_us,
            .shapes = shapes,
            .words = words,
        });

        preview.deinit(allocator);
    }
}

/// Build a fresh banner + cache for the zoom sweep at the given ppem (in
/// pixels). The hinter's per-ppem cache starts cold every call.
///
/// `banner_assets` must be heap-allocated by the caller so the paint_image
/// pointer baked into atlas paint records stays valid. `Content`'s atlas
/// records keep `*const Image` pointers into `assets_box.paint_image`; if
/// `banner_assets` lived on the stack inside this function those pointers
/// would dangle the moment the function returned.
fn zoomBuildOneCold(allocator: std.mem.Allocator, ppem_px: u32) !ZoomBuild {
    const assets_box = try allocator.create(demo_banner.Assets);
    errdefer allocator.destroy(assets_box);
    assets_box.* = try demo_banner.Assets.init(allocator);
    errdefer assets_box.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 24,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    errdefer pool.deinit();

    // To force a per-ppem rebuild, we scale the layout so that the
    // banner's body text size lands at `ppem_px`. The reference body
    // size in banner.zig is 22 (body_text_size). We pick a canvas size
    // such that `scale = ppem_px / 22`.
    const ref_body: f32 = 22.0;
    const layout_scale: f32 = @as(f32, @floatFromInt(ppem_px)) / ref_body;
    const W: f32 = 1680.0 * layout_scale;
    const H: f32 = 874.0 * layout_scale;

    var content = try demo_banner.build(
        allocator,
        pool,
        assets_box,
        W,
        H,
        .{ .x = 1, .y = 1 },
        .{ .enabled = true, .ppem_scale = 1.0 },
    );
    errdefer content.deinit();

    var cache = try snail.CpuPreparedPages.init(allocator, content.pool, .{
        .max_bindings = 4,
        .layer_info_height = 256,
        .max_images = 8,
    });
    errdefer cache.deinit();
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &bindings);
    const paths_binding = bindings[0];
    const text_binding = bindings[1];

    const word_cap = snail.emit.wordBudget(&content.paths_picture, 0) + snail.emit.wordBudget(&content.text_picture, 0);
    const words = try allocator.alloc(u32, word_cap);
    errdefer allocator.free(words);
    const seg_cap = @max(snail.emit.segmentBudget(&content.paths_picture, 0) + snail.emit.segmentBudget(&content.text_picture, 0), 4);
    const segs = try allocator.alloc(snail.DrawSegment, seg_cap);
    errdefer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &content.paths_atlas, &content.paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &content.text_atlas, &content.text_picture, .identity, .{ 1, 1, 1, 1 });

    return .{
        .pool = pool,
        .assets_owned = assets_box,
        .content = content,
        .cache = cache,
        .bindings = bindings,
        .words = words,
        .segments = segs,
        .word_len = wlen,
        .segment_len = slen,
    };
}


// ── main ──

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const prepared_render_state = drawState(WIDTH, HEIGHT, .none);

    const font_data = assets.noto_sans_regular;
    const snail_prep = try benchSnailPrep(allocator);
    const vector_prep = try timeVectorBuild(allocator);
    const ft = try freetype.bench(font_data, .{
        .prep_runs = PREP_RUNS,
        .text_iters = TEXT_ITERS,
        .printable_ascii = PRINTABLE_ASCII[0..],
        .sizes = SIZES[0..],
        .short = SHORT,
        .sentence = SENTENCE,
        .paragraph = PARAGRAPH,
    });

    var fonts = try FontSet.init(allocator);
    defer fonts.deinit();

    // ── Text workload table ──
    var text_rows: std.ArrayList(TextRow) = .empty;
    defer text_rows.deinit(allocator);
    for (text_workloads) |workload| {
        try text_rows.append(allocator, .{
            .label = workload.name(),
            .snail_us = try timeTextWorkload(allocator, &fonts, workload),
            .ft_us = ft.layout(workload),
        });
    }
    for (hinted_text_workloads) |workload| {
        try text_rows.append(allocator, .{
            .label = hintedTextWorkloadName(workload),
            .snail_us = try timeHintedTextWorkload(allocator, &fonts, workload),
            .ft_us = null,
        });
    }

    // ── Scene bundles ──
    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 24,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var bundles: [scene_kinds.len]SceneBundle = undefined;
    var bundle_count: usize = 0;
    defer for (bundles[0..bundle_count]) |*b| b.deinit();
    for (scene_kinds) |kind| {
        bundles[bundle_count] = try buildScene(allocator, pool, &fonts, kind);
        bundle_count += 1;
    }

    // ── CPU prepared pages + per-scene emit ──
    var cpu_cache = try snail.CpuPreparedPages.init(allocator, pool, .{
        .max_bindings = 16,
        .layer_info_height = 256,
        .max_images = 8,
    });
    defer cpu_cache.deinit();
    var cpu_bindings: [scene_kinds.len]snail.Binding = undefined;
    {
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cpu_cache.upload(allocator, atlas_ptrs[0..bundle_count], cpu_bindings[0..bundle_count]);
    }

    var emitted: [scene_kinds.len]EmittedRecords = undefined;
    var emitted_count: usize = 0;
    defer for (emitted[0..emitted_count]) |*e| e.deinit();
    for (bundles[0..bundle_count], 0..) |*b, i| {
        emitted[i] = try emitScene(allocator, cpu_bindings[i], &b.atlas, &b.picture);
        emitted_count += 1;
    }

    // ── Record build (emit.emit) timing ──
    var record_rows: [scene_kinds.len]RecordRow = undefined;
    for (scene_kinds, 0..) |kind, i| {
        const r = try timeRecordEmit(allocator, cpu_bindings[i], &bundles[i].atlas, &bundles[i].picture);
        record_rows[i] = .{
            .scene = kind,
            .us = r.us,
            .shapes = bundles[i].picture.shapes.len,
            .words = r.words,
            .segments = r.segments,
        };
    }

    // ── CPU render rows ──
    var render_rows: std.ArrayList(RenderRow) = .empty;
    defer render_rows.deinit(allocator);

    const cpu_pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels);
    var cpu_renderer = snail.CpuRenderer.init(cpu_pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);

    var cpu_pool: snail.ThreadPool = undefined;
    try cpu_pool.init(allocator, .{});
    defer cpu_pool.deinit();
    const cpu_pixels_threaded = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    defer allocator.free(cpu_pixels_threaded);
    var cpu_renderer_threaded = snail.CpuRenderer.init(cpu_pixels_threaded.ptr, WIDTH, HEIGHT, WIDTH * 4);
    cpu_renderer_threaded.setThreadPool(&cpu_pool);

    for (scene_kinds, 0..) |kind, i| {
        const records = render_timing.DrawRecords{
            .words = emitted[i].words[0..emitted[i].word_len],
            .segments = emitted[i].segments[0..emitted[i].segment_len],
        };
        const us = try render_timing.timeCpuDraw(&cpu_renderer, prepared_render_state, records, &.{&cpu_cache}, cpu_pixels, CPU_WARMUP, CPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = "CPU",
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_render_state.raster.subpixel_order, true),
            .frames = CPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = emitted[i].word_len,
            .segments = emitted[i].segment_len,
            .instance_bytes = emitted[i].word_len * @sizeOf(u32),
            .us = us,
        });
    }

    for (scene_kinds, 0..) |kind, i| {
        const records = render_timing.DrawRecords{
            .words = emitted[i].words[0..emitted[i].word_len],
            .segments = emitted[i].segments[0..emitted[i].segment_len],
        };
        const us = try render_timing.timeCpuDraw(&cpu_renderer_threaded, prepared_render_state, records, &.{&cpu_cache}, cpu_pixels_threaded, CPU_WARMUP, CPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = "CPU (threaded)",
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_render_state.raster.subpixel_order, true),
            .frames = CPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = emitted[i].word_len,
            .segments = emitted[i].segment_len,
            .instance_bytes = emitted[i].word_len * @sizeOf(u32),
            .us = us,
        });
    }

    // ── Mode rows (CPU) ──
    var mode_rows: std.ArrayList(ModeRow) = .empty;
    defer mode_rows.deinit(allocator);
    try benchCpuModes(allocator, &cpu_renderer, &cpu_cache, "CPU", &bundles, bundle_count, cpu_bindings[0..bundle_count], cpu_pixels, &mode_rows);
    try benchCpuModes(allocator, &cpu_renderer_threaded, &cpu_cache, "CPU (threaded)", &bundles, bundle_count, cpu_bindings[0..bundle_count], cpu_pixels_threaded, &mode_rows);

    // ── GL hardware rows (collected as each GL backend stands up) ──
    var gl_hardware_rows: std.ArrayList(report.GlHardwareRow) = .empty;
    defer {
        for (gl_hardware_rows.items) |row| row.deinit(allocator);
        gl_hardware_rows.deinit(allocator);
    }

    if (comptime build_options.enable_gl33) {
        try benchGl33(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows);
    }
    if (comptime build_options.enable_gl44) {
        try benchGl44(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows);
    }
    if (comptime build_options.enable_gles30) {
        try benchGles30(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows);
    }

    if (comptime build_options.enable_vulkan) {
        try benchVulkan(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows);
    }

    // ── Zoom sweep ──
    var zoom_rows: std.ArrayList(ZoomRow) = .empty;
    defer zoom_rows.deinit(allocator);
    try benchZoomSweep(allocator, &zoom_rows);

    // ── Output ──
    std.debug.print(
        \\# Snail Benchmarks
        \\
        \\NotoSans-Regular, {d} prep runs, {d} text iterations, {d} draw-record iterations.
        \\Scenarios: {d} text workloads (un-hinted + hinted), {d} scene kinds, {d} render modes,
        \\plus a {d}-ppem zoom-sweep on the demo banner content.
        \\
        \\The vector workload contains filled and stroked rounded rectangles, ellipses,
        \\and custom cubic/quadratic paths. Backend rows follow the enabled build flags.
        \\
        \\
    , .{
        PREP_RUNS,
        TEXT_ITERS,
        RECORD_ITERS,
        text_workloads.len,
        scene_kinds.len,
        render_modes.len,
        ZOOM_PPEMS.len,
    });
    report.printHardwareTable(gl_hardware_rows.items, build_options.enable_vulkan);
    report.printPreparationTables(snail_prep, vector_prep, ft);
    report.printTextTable(text_rows.items);
    report.printRecordTable(&record_rows);
    report.printRenderTable(WIDTH, HEIGHT, CPU_FRAMES, GPU_FRAMES, render_rows.items);
    report.printModeTable(mode_rows.items);
    printZoomTable(zoom_rows.items);
}

fn printZoomTable(rows: []const ZoomRow) void {
    std.debug.print(
        \\## Zoom Sweep
        \\
        \\Per-ppem rebuild + steady-state render of the full demo banner ({d}x{d}, CPU backend, hinting on).
        \\Rebuild starts from a cold Hinter cache (i.e. a zoom step that pushes through a previously-unseen ppem).
        \\Render is averaged over {d} frames with cache warm. Use rebuild/render ratio to judge whether the dormant
        \\BandReuseProof machinery in `src/snail/render/format/text_hint.zig` would meaningfully amortize the cost.
        \\
        \\| ppem | Shapes | Words | Cold rebuild | Steady render |
        \\|---:|---:|---:|---:|---:|
        \\
    , .{ ZOOM_W, ZOOM_H, ZOOM_RENDER_FRAMES });
    for (rows) |row| {
        std.debug.print("| {d} | {d} | {d} | {d:.2} us | {d:.2} us |\n", .{ row.ppem, row.shapes, row.words, row.rebuild_us, row.render_us });
    }
    std.debug.print("\n", .{});
}

// ── CPU mode timings ──

fn benchCpuModes(
    allocator: std.mem.Allocator,
    renderer: *snail.CpuRenderer,
    cache: *const snail.CpuPreparedPages,
    backend_name: []const u8,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    bindings: []const snail.Binding,
    pixels: []u8,
    rows: *std.ArrayList(ModeRow),
) !void {
    _ = bundle_count;
    for (mode_scene_kinds) |scene_kind| {
        const idx = sceneKindIndex(scene_kind);
        const b = &bundles[idx];
        for (render_modes) |mode| {
            const records_emitted = try emitScene(allocator, bindings[idx], &b.atlas, &b.picture);
            defer {
                var e = records_emitted;
                e.deinit();
            }
            const records = render_timing.DrawRecords{
                .words = records_emitted.words[0..records_emitted.word_len],
                .segments = records_emitted.segments[0..records_emitted.segment_len],
            };
            const state = drawState(WIDTH, HEIGHT, mode.aa);
            const record_us = (try timeRecordEmit(allocator, bindings[idx], &b.atlas, &b.picture)).us;
            const draw_us = try render_timing.timeCpuDraw(renderer, state, records, &.{cache}, pixels, CPU_WARMUP, CPU_FRAMES);
            try rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .effective_aa = effectiveAaLabel(mode.aa, true),
                .record_us = record_us,
                .draw_us = draw_us,
                .words = records_emitted.word_len,
                .segments = records_emitted.segment_len,
            });
        }
    }
}

fn sceneKindIndex(kind: SceneKind) usize {
    for (scene_kinds, 0..) |k, i| if (k == kind) return i;
    unreachable;
}

// ── GL backends ──

fn benchGl33(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    render_rows: *std.ArrayList(RenderRow),
    mode_rows: *std.ArrayList(ModeRow),
    gl_hardware_rows: *std.ArrayList(report.GlHardwareRow),
) !void {
    var ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT, .gl33);
    defer ctx.deinit();
    const fb = render_timing.initFramebuffer(WIDTH, HEIGHT);
    defer render_timing.destroyFramebuffer(fb);

    var renderer = try snail.Gl33Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try snail.Gl33PreparedPages.init(allocator, pool, .{
        .max_bindings = 16,
        .layer_info_height = 256,
        .max_images = 4,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [scene_kinds.len]snail.Binding = undefined;
    {
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cache.upload(allocator, atlas_ptrs[0..bundle_count], bindings[0..bundle_count]);
    }

    const backend_name = renderer.state.backendName();
    const supports_lcd = renderer.state.supports_dual_source_blend;

    try gl_hardware_rows.append(allocator, try report.captureGlHardwareRow(allocator, backend_name));

    const prepared_state = drawState(WIDTH, HEIGHT, .none);
    for (scene_kinds, 0..) |kind, i| {
        var records_emitted = try emitScene(allocator, bindings[i], &bundles[i].atlas, &bundles[i].picture);
        defer records_emitted.deinit();
        const records = render_timing.DrawRecords{
            .words = records_emitted.words[0..records_emitted.word_len],
            .segments = records_emitted.segments[0..records_emitted.segment_len],
        };
        const us = try render_timing.timeGl33Draw(allocator, &renderer, prepared_state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = backend_name,
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_state.raster.subpixel_order, supports_lcd),
            .frames = GPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = records_emitted.word_len,
            .segments = records_emitted.segment_len,
            .instance_bytes = records_emitted.word_len * @sizeOf(u32),
            .us = us,
        });
    }

    for (mode_scene_kinds) |scene_kind| {
        const idx = sceneKindIndex(scene_kind);
        for (render_modes) |mode| {
            var records_emitted = try emitScene(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture);
            defer records_emitted.deinit();
            const records = render_timing.DrawRecords{
                .words = records_emitted.words[0..records_emitted.word_len],
                .segments = records_emitted.segments[0..records_emitted.segment_len],
            };
            const state = drawState(WIDTH, HEIGHT, mode.aa);
            const record_us = (try timeRecordEmit(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture)).us;
            const draw_us = try render_timing.timeGl33Draw(allocator, &renderer, state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
            try mode_rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .effective_aa = effectiveAaLabel(mode.aa, supports_lcd),
                .record_us = record_us,
                .draw_us = draw_us,
                .words = records_emitted.word_len,
                .segments = records_emitted.segment_len,
            });
        }
    }
}

fn benchGl44(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    render_rows: *std.ArrayList(RenderRow),
    mode_rows: *std.ArrayList(ModeRow),
    gl_hardware_rows: *std.ArrayList(report.GlHardwareRow),
) !void {
    var ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT, .gl44);
    defer ctx.deinit();
    const fb = render_timing.initFramebuffer(WIDTH, HEIGHT);
    defer render_timing.destroyFramebuffer(fb);

    var renderer = try snail.Gl44Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try snail.Gl44PreparedPages.init(allocator, pool, .{
        .max_bindings = 16,
        .layer_info_height = 256,
        .max_images = 4,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [scene_kinds.len]snail.Binding = undefined;
    {
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cache.upload(allocator, atlas_ptrs[0..bundle_count], bindings[0..bundle_count]);
    }

    const backend_name = renderer.state.backendName();
    const supports_lcd = renderer.state.supports_dual_source_blend;

    try gl_hardware_rows.append(allocator, try report.captureGlHardwareRow(allocator, backend_name));

    const prepared_state = drawState(WIDTH, HEIGHT, .none);
    for (scene_kinds, 0..) |kind, i| {
        var records_emitted = try emitScene(allocator, bindings[i], &bundles[i].atlas, &bundles[i].picture);
        defer records_emitted.deinit();
        const records = render_timing.DrawRecords{
            .words = records_emitted.words[0..records_emitted.word_len],
            .segments = records_emitted.segments[0..records_emitted.segment_len],
        };
        const us = try render_timing.timeGl44Draw(allocator, &renderer, prepared_state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = backend_name,
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_state.raster.subpixel_order, supports_lcd),
            .frames = GPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = records_emitted.word_len,
            .segments = records_emitted.segment_len,
            .instance_bytes = records_emitted.word_len * @sizeOf(u32),
            .us = us,
        });
    }

    for (mode_scene_kinds) |scene_kind| {
        const idx = sceneKindIndex(scene_kind);
        for (render_modes) |mode| {
            var records_emitted = try emitScene(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture);
            defer records_emitted.deinit();
            const records = render_timing.DrawRecords{
                .words = records_emitted.words[0..records_emitted.word_len],
                .segments = records_emitted.segments[0..records_emitted.segment_len],
            };
            const state = drawState(WIDTH, HEIGHT, mode.aa);
            const record_us = (try timeRecordEmit(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture)).us;
            const draw_us = try render_timing.timeGl44Draw(allocator, &renderer, state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
            try mode_rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .effective_aa = effectiveAaLabel(mode.aa, supports_lcd),
                .record_us = record_us,
                .draw_us = draw_us,
                .words = records_emitted.word_len,
                .segments = records_emitted.segment_len,
            });
        }
    }
}

fn benchGles30(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    render_rows: *std.ArrayList(RenderRow),
    mode_rows: *std.ArrayList(ModeRow),
    gl_hardware_rows: *std.ArrayList(report.GlHardwareRow),
) !void {
    var ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT, .gles30);
    defer ctx.deinit();
    const fb = render_timing.initFramebuffer(WIDTH, HEIGHT);
    defer render_timing.destroyFramebuffer(fb);

    var renderer = try snail.Gles30Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try snail.Gles30PreparedPages.init(allocator, pool, .{
        .max_bindings = 16,
        .layer_info_height = 256,
        .max_images = 4,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [scene_kinds.len]snail.Binding = undefined;
    {
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cache.upload(allocator, atlas_ptrs[0..bundle_count], bindings[0..bundle_count]);
    }

    const backend_name = renderer.state.backendName();
    const supports_lcd = false; // GLES30 has no dual-source blend.
    try gl_hardware_rows.append(allocator, try report.captureGlHardwareRow(allocator, backend_name));

    const prepared_state = drawState(WIDTH, HEIGHT, .none);
    for (scene_kinds, 0..) |kind, i| {
        var records_emitted = try emitScene(allocator, bindings[i], &bundles[i].atlas, &bundles[i].picture);
        defer records_emitted.deinit();
        const records = render_timing.DrawRecords{
            .words = records_emitted.words[0..records_emitted.word_len],
            .segments = records_emitted.segments[0..records_emitted.segment_len],
        };
        const us = try render_timing.timeGles30Draw(allocator, &renderer, prepared_state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = backend_name,
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_state.raster.subpixel_order, supports_lcd),
            .frames = GPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = records_emitted.word_len,
            .segments = records_emitted.segment_len,
            .instance_bytes = records_emitted.word_len * @sizeOf(u32),
            .us = us,
        });
    }

    for (mode_scene_kinds) |scene_kind| {
        const idx = sceneKindIndex(scene_kind);
        for (render_modes) |mode| {
            var records_emitted = try emitScene(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture);
            defer records_emitted.deinit();
            const records = render_timing.DrawRecords{
                .words = records_emitted.words[0..records_emitted.word_len],
                .segments = records_emitted.segments[0..records_emitted.segment_len],
            };
            const state = drawState(WIDTH, HEIGHT, mode.aa);
            const record_us = (try timeRecordEmit(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture)).us;
            const draw_us = try render_timing.timeGles30Draw(allocator, &renderer, state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
            try mode_rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .effective_aa = effectiveAaLabel(mode.aa, supports_lcd),
                .record_us = record_us,
                .draw_us = draw_us,
                .words = records_emitted.word_len,
                .segments = records_emitted.segment_len,
            });
        }
    }
}

fn benchVulkan(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    render_rows: *std.ArrayList(RenderRow),
    mode_rows: *std.ArrayList(ModeRow),
) !void {
    if (comptime !build_options.enable_vulkan) return;

    const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
    defer vulkan_platform.deinitOffscreen();
    var renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer renderer.deinit();

    var cache = try snail.VulkanPreparedPages.init(allocator, pool, renderer.state.pipelineShape(), .{
        .max_bindings = 16,
        .layer_info_height = 256,
        .max_images = 4,
        .max_image_width = 256,
        .max_image_height = 256,
    });
    defer cache.deinit();
    var bindings: [scene_kinds.len]snail.Binding = undefined;
    {
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cache.upload(allocator, atlas_ptrs[0..bundle_count], bindings[0..bundle_count]);
    }

    const backend_name = renderer.state.backendName();
    const supports_lcd = vk_ctx.supports_dual_source_blend;

    const prepared_state = drawState(WIDTH, HEIGHT, .none);
    for (scene_kinds, 0..) |kind, i| {
        var records_emitted = try emitScene(allocator, bindings[i], &bundles[i].atlas, &bundles[i].picture);
        defer records_emitted.deinit();
        const records = render_timing.DrawRecords{
            .words = records_emitted.words[0..records_emitted.word_len],
            .segments = records_emitted.segments[0..records_emitted.segment_len],
        };
        const us = try render_timing.timeVulkanDraw(allocator, &renderer, prepared_state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
        try render_rows.append(allocator, .{
            .backend = backend_name,
            .scene = kind,
            .effective_aa = effectiveAaLabel(prepared_state.raster.subpixel_order, supports_lcd),
            .frames = GPU_FRAMES,
            .shapes = bundles[i].picture.shapes.len,
            .words = records_emitted.word_len,
            .segments = records_emitted.segment_len,
            .instance_bytes = records_emitted.word_len * @sizeOf(u32),
            .us = us,
        });
    }

    for (mode_scene_kinds) |scene_kind| {
        const idx = sceneKindIndex(scene_kind);
        for (render_modes) |mode| {
            var records_emitted = try emitScene(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture);
            defer records_emitted.deinit();
            const records = render_timing.DrawRecords{
                .words = records_emitted.words[0..records_emitted.word_len],
                .segments = records_emitted.segments[0..records_emitted.segment_len],
            };
            const state = drawState(WIDTH, HEIGHT, mode.aa);
            const record_us = (try timeRecordEmit(allocator, bindings[idx], &bundles[idx].atlas, &bundles[idx].picture)).us;
            const draw_us = try render_timing.timeVulkanDraw(allocator, &renderer, state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
            try mode_rows.append(allocator, .{
                .backend = backend_name,
                .scene = scene_kind,
                .mode = mode,
                .effective_aa = effectiveAaLabel(mode.aa, supports_lcd),
                .record_us = record_us,
                .draw_us = draw_us,
                .words = records_emitted.word_len,
                .segments = records_emitted.segment_len,
            });
        }
    }
}
