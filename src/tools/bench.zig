//! Consolidated benchmarks for pasteable README tables.
//!
//! Covers preparation, text shaping + picture build, vector picture build,
//! draw-record emit, and prepared rendering on each enabled CPU, GL,
//! OpenGL ES, and Vulkan backend.
//!
//! 8 scene kinds, 4 text workloads × hinted/un-hinted, two render modes,
//! FreeType comparison.

const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail");
const embed_gl = @import("embed_gl");
const snail_helpers = @import("snail-helpers");
const egl_offscreen = @import("demo_platform_offscreen_gl");
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};
const embed_vulkan = if (build_options.enable_vulkan) @import("embed_vulkan") else struct {};
const freetype = @import("bench/freetype.zig");
const render_timing = @import("bench/render_timing.zig");
const report = @import("bench/report.zig");
const corpus = @import("bench/corpus.zig");

// ── Section filter ──
//
// `SNAIL_BENCH_ONLY` selects which timed workloads run. When set,
// only the named sections run and only their rows print — useful for
// focused `perf record` runs. Each section name corresponds to ONE
// table row, not a category. Default (no env var) runs everything.
//
//   font-load        Font init
//   glyph-extract    extractCurves over 95 ASCII glyphs
//   hint-setup       HintVm.init at ppem
//   hint-execute     warm advance loop, all ASCII
//   hint-full        full HintVm.hint per ASCII glyph
//   hinter-cold      fresh HintVm + paragraph hinted once
//   hinter-warm      warm HintVm + paragraph hinted N times (cache hit)
//   vector-build     pathToCurves over 50 rounded rects
//   freetype         FreeType comparison rows (load, glyph prep, layout)
//   picture-build    snail picture build per text workload (un-hinted)
//   picture-build-hinted   same, hinted variant
//   emit             emit.emit per scene
//   cpu-draw         CPU and CPU(threaded) draw per scene
//   gl33 gl44 gles30 vulkan   per-backend GPU draw per scene
//   modes            per-backend per-mode (grayscale vs subpixel) draws
//   gl33-breakdown   one row per scene: per-stage GL 3.3 frame breakdown
const Filter = struct {
    enabled_set: ?std.StringHashMap(void) = null,

    fn init(allocator: std.mem.Allocator) !Filter {
        const raw = std.c.getenv("SNAIL_BENCH_ONLY") orelse return .{};
        var map = std.StringHashMap(void).init(allocator);
        var it = std.mem.tokenizeAny(u8, std.mem.span(raw), ", ");
        while (it.next()) |s| try map.put(s, {});
        return .{ .enabled_set = map };
    }

    fn deinit(self: *Filter) void {
        if (self.enabled_set) |*m| m.deinit();
    }

    fn run(self: *const Filter, name: []const u8) bool {
        if (self.enabled_set) |s| return s.contains(name);
        return true;
    }
};

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

// ── Corpus aliases (data lives in bench/corpus.zig) ──

const PRINTABLE_ASCII = corpus.PRINTABLE_ASCII;
const SHORT = corpus.SHORT;
const SENTENCE = corpus.SENTENCE;
const PARAGRAPH = corpus.PARAGRAPH;
const ARABIC_TEXT = corpus.ARABIC_TEXT;
const DEVANAGARI_TEXT = corpus.DEVANAGARI_TEXT;
const THAI_TEXT = corpus.THAI_TEXT;
const SIZES = corpus.SIZES;
const TextLine = corpus.TextLine;
const TextWorkload = corpus.TextWorkload;
const text_workloads = corpus.text_workloads;
const hinted_text_workloads = corpus.hinted_text_workloads;
const SceneKind = corpus.SceneKind;
const scene_kinds = corpus.scene_kinds;
const RenderMode = corpus.RenderMode;
const render_modes = corpus.render_modes;
const mode_scene_kinds = corpus.mode_scene_kinds;
const subpixelOrderName = corpus.subpixelOrderName;
const effectiveAaLabel = corpus.effectiveAaLabel;
const scene_text_lines = corpus.scene_text_lines;
const scene_multi_script_lines = corpus.scene_multi_script_lines;
const rich_text_strings = corpus.rich_text_strings;

// ── Row types ──

const SnailPrep = struct {
    font_load_us: ?f64 = null,
    ascii_prep_us: ?f64 = null,
    ascii_hint_setup_us: ?f64 = null,
    ascii_hint_execute_us: ?f64 = null,
    ascii_hint_us: ?f64 = null,
    paragraph_hint_context_cold_us: ?f64 = null,
    paragraph_hint_context_warm_us: ?f64 = null,
};

const VectorPrep = struct {
    freeze_us: ?f64 = null,
    shapes: usize = 50,
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

const Gl33BreakdownRow = struct {
    scene: SceneKind,
    clear_us: f64,
    begin_us: f64,
    draw_us: f64,
    finish_us: f64,
    total_us: f64,
    gpu_us: f64,
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

const FontSet = struct {
    allocator: std.mem.Allocator,
    faces: snail.Faces,
    /// Heap-allocated so `Faces.face(i).font` (raw `*const Font`)
    /// and the hint_vm's captured data slice survive FontSet getting
    /// moved during `init`'s return-by-value.
    fonts: []snail.Font,
    /// HintVm + cache for face 0. Heap-allocated so the cache's
    /// internal `*HintVm` stays stable when FontSet is moved by the
    /// `init` return-by-value. `hinted_cache.asAdvanceProvider()` is
    /// the right thing to hand to `ShapeOptions.advance_provider`.
    hint_vm: ?*snail.HintVm,
    hinted_cache: ?snail_helpers.HintedGlyphCache,
    has_hinter: bool,

    fn init(allocator: std.mem.Allocator) !FontSet {
        const fonts = try allocator.alloc(snail.Font, FONT_COUNT);
        errdefer allocator.free(fonts);
        const datas = [_][]const u8{
            assets.noto_sans_regular,
            assets.noto_sans_bold,
            assets.noto_sans_arabic,
            assets.noto_sans_devanagari,
            assets.noto_sans_thai,
        };
        for (datas, 0..) |data, i| {
            fonts[i] = try snail.Font.init(data);
        }

        var faces = try snail.Faces.build(allocator, &.{
            .{ .font = &fonts[0] },
            .{ .font = &fonts[1], .weight = .bold },
            .{ .font = &fonts[2], .fallback = true },
            .{ .font = &fonts[3], .fallback = true },
            .{ .font = &fonts[4], .fallback = true },
        });
        errdefer faces.deinit();

        const hint_vm: ?*snail.HintVm = blk: {
            const vm_ptr = allocator.create(snail.HintVm) catch break :blk null;
            vm_ptr.* = snail.HintVm.init(allocator, &fonts[0]) catch {
                allocator.destroy(vm_ptr);
                break :blk null;
            };
            break :blk vm_ptr;
        };
        const hinted_cache: ?snail_helpers.HintedGlyphCache = if (hint_vm) |vm_ptr|
            snail_helpers.HintedGlyphCache.init(allocator, vm_ptr, faces.fontIdForFace(0))
        else
            null;

        return .{
            .allocator = allocator,
            .faces = faces,
            .fonts = fonts,
            .hint_vm = hint_vm,
            .hinted_cache = hinted_cache,
            .has_hinter = hint_vm != null,
        };
    }

    fn deinit(self: *FontSet) void {
        if (self.hinted_cache) |*c| c.deinit();
        if (self.hint_vm) |vm| {
            vm.deinit();
            self.allocator.destroy(vm);
        }
        self.faces.deinit();
        self.allocator.free(self.fonts);
        self.* = undefined;
    }

    fn advanceProvider(self: *FontSet) ?snail.AdvanceProvider {
        if (self.hinted_cache) |*c| return c.asAdvanceProvider();
        return null;
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

    fn freezePicture(self: *SceneBuild) !snail_helpers.Picture {
        return snail_helpers.Picture.from(self.allocator, self.shapes.items);
    }
};

/// Add a stroked + filled rounded rect or ellipse to a SceneBuild.
fn addFilledPath(
    self: *SceneBuild,
    path: *const snail.Path,
    paint: snail.Paint,
) !void {
    var prepared = try path.prepare(self.allocator);
    defer prepared.deinit();
    const curves = try prepared.fillCurves(self.allocator, self.scratch());
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
        .paint = prepared.paintForDesign(paint),
    });
    try self.shapes.append(self.allocator, .{
        .key = key,
        .local_transform = prepared.design_to_source,
        .local_color = .{ 1, 1, 1, 1 },
    });
}

fn addStrokedPath(
    self: *SceneBuild,
    path: *const snail.Path,
    stroke: snail.StrokeStyle,
) !void {
    var prepared = try path.prepare(self.allocator);
    defer prepared.deinit();
    const curves = try prepared.strokeCurves(self.allocator, self.scratch(), stroke);
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
        .paint = prepared.paintForDesign(stroke.paint),
    });
    try self.shapes.append(self.allocator, .{
        .key = key,
        .local_transform = prepared.design_to_source,
        .local_color = .{ 1, 1, 1, 1 },
    });
}

/// Insert the unhinted curves for every glyph in `shaped` into `build`'s
/// text atlas (deduped by `recordKey.unhintedGlyph` key).
fn ensureUnhintedRunCurves(
    build: *SceneBuild,
    fonts: *FontSet,
    shaped: *const snail.ShapedText,
) !void {
    for (shaped.glyphs) |g| {
        const fid = g.font_id;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(build.entries.items, key)) continue;
        const curves = try fonts.fonts[fid].extractCurves(build.allocator, build.scratch(), g.glyph_id);
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
    const hinter = fonts.hint_vm orelse return false;
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    var prepared = hinter.prepare(ppem) catch return false;
    defer prepared.deinit();
    for (shaped.glyphs) |g| {
        if (g.face_index != 0) return false; // only face 0 is hintable
        const key = snail.recordKey.hintedGlyph(0, g.glyph_id, ppem_26_6);
        if (containsKey(build.entries.items, key)) continue;
        const curves = hinter.hintGlyph(build.allocator, build.allocator, &prepared, g.glyph_id) catch return false;
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
                    var p = snail.Path.init(allocator);
                    defer p.deinit();
                    try p.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, 10);
                    try addFilledPath(&build, &p, fill);
                    try addStrokedPath(&build, &p, stroke);
                },
                1 => {
                    var p = snail.Path.init(allocator);
                    defer p.deinit();
                    try p.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 44 });
                    try addFilledPath(&build, &p, fill);
                    try addStrokedPath(&build, &p, stroke);
                },
                else => {
                    var p = snail.Path.init(allocator);
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
        var p = snail.Path.init(allocator);
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
    atlas: snail.Atlas,
    picture: snail_helpers.Picture,

    fn deinit(self: *SceneBundle) void {
        self.picture.deinit();
        self.atlas.deinit();
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

    if (kind.needsVector()) try appendVectorPathsTo(&build);

    if (kind.isRich()) {
        try buildRichText(&build, fonts);
    } else if (kind.needsText()) {
        const lines: []const TextLine = if (kind.isMultiScript()) scene_multi_script_lines[0..] else scene_text_lines[0..];
        for (lines) |line| {
            try addShapedLine(&build, fonts, line, kind.isHinted());
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
                    var p = snail.Path.init(allocator);
                    defer p.deinit();
                    try p.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, 10);
                    try addFilledPath(build, &p, fill);
                    try addStrokedPath(build, &p, stroke);
                },
                1 => {
                    var p = snail.Path.init(allocator);
                    defer p.deinit();
                    try p.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 44 });
                    try addFilledPath(build, &p, fill);
                    try addStrokedPath(build, &p, stroke);
                },
                else => {
                    var p = snail.Path.init(allocator);
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
    var p = snail.Path.init(allocator);
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
    line: TextLine,
    hinted: bool,
) !void {
    const allocator = build.allocator;
    if (hinted and fonts.has_hinter) {
        const ppem_26_6 = hintPpem26_6(line.size) catch return addShapedLineUnhinted(build, fonts, line);
        var shaped = try snail.shape(allocator, &fonts.faces, line.text, .{ .style = line.style, .target_ppem = snail.HintPpem.uniform(ppem_26_6), .advance_provider = fonts.advanceProvider() });
        defer shaped.deinit();
        const ok = ensureHintedRunCurves(build, fonts, &shaped, ppem_26_6) catch false;
        if (ok) {
            var pic = try snail_helpers.placeRun(allocator, &shaped, null, .{
                .baseline = .{ .x = line.x, .y = line.y },
                .em = line.size,
                .color = line.color,
                .mode = .{ .truetype = .{ .ppem_26_6 = ppem_26_6 } },
            });
            defer pic.deinit();
            try build.shapes.appendSlice(allocator, pic.shapes);
            return;
        }
        // Hinting failed (non-Latin fallback face etc) — fall through to unhinted.
    }
    return addShapedLineUnhinted(build, fonts, line);
}

fn addShapedLineUnhinted(
    build: *SceneBuild,
    fonts: *FontSet,
    line: TextLine,
) !void {
    const allocator = build.allocator;
    var shaped = try snail.shape(allocator, &fonts.faces, line.text, .{ .style = line.style });
    defer shaped.deinit();
    try ensureUnhintedRunCurves(build, fonts, &shaped);
    var pic = try snail_helpers.placeRun(allocator, &shaped, &fonts.faces, .{
        .baseline = .{ .x = line.x, .y = line.y },
        .em = line.size,
        .color = line.color,
    });
    defer pic.deinit();
    try build.shapes.appendSlice(allocator, pic.shapes);
}

fn buildRichText(
    build: *SceneBuild,
    fonts: *FontSet,
) !void {
    // Match the legacy rich-text layout: a wide variety of weights, sizes,
    // colors, and gradient paints across three lines.
    var x: f32 = 18.0;
    var y: f32 = 46.0;

    x += try addRichRun(build, fonts, .{ .weight = .bold }, "RICH ", x, y, 30.0, .{ .solid = .{ 0.95, 0.97, 1.0, 1.0 } });
    {
        const grad = snail.Paint{ .linear_gradient = .{
            .start = .{ .x = x, .y = y - 30.0 },
            .end = .{ .x = x + 150.0, .y = y },
            .start_color = .{ 0.30, 0.65, 1.0, 1.0 },
            .end_color = .{ 1.0, 0.35, 0.58, 1.0 },
        } };
        x += try addRichRun(build, fonts, .{ .weight = .bold }, "gradient", x, y, 30.0, grad);
    }
    _ = try addRichRun(build, fonts, .{}, " runs", x, y, 22.0, .{ .solid = .{ 0.72, 0.78, 0.86, 1.0 } });

    x = 18.0;
    y = 94.0;
    x += try addRichRun(build, fonts, .{}, "status  ", x, y, 18.0, .{ .solid = .{ 0.60, 0.68, 0.76, 1.0 } });
    x += try addRichRun(build, fonts, .{ .weight = .bold }, "HP ", x, y, 24.0, .{ .solid = .{ 0.80, 0.92, 0.86, 1.0 } });
    x += try addRichRun(build, fonts, .{ .weight = .bold }, "83", x, y, 28.0, .{ .solid = .{ 0.25, 0.92, 0.50, 1.0 } });
    x += try addRichRun(build, fonts, .{}, "   shield ", x, y, 18.0, .{ .solid = .{ 0.62, 0.72, 0.82, 1.0 } });
    {
        const grad = snail.Paint{ .linear_gradient = .{
            .start = .{ .x = x, .y = y - 22.0 },
            .end = .{ .x = x + 76.0, .y = y },
            .start_color = .{ 0.20, 0.82, 0.92, 1.0 },
            .end_color = .{ 0.85, 0.96, 0.45, 1.0 },
        } };
        _ = try addRichRun(build, fonts, .{ .weight = .bold }, "online", x, y, 22.0, grad);
    }

    x = 18.0;
    y = 142.0;
    x += try addRichRun(build, fonts, .{}, "per-letter  ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
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
        x += try addRichRun(build, fonts, .{ .weight = .bold }, &one, x, y, sz, .{ .solid = colors[i] });
    }
    x += try addRichRun(build, fonts, .{}, "  alerts ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    x += try addRichRun(build, fonts, .{ .weight = .bold }, "OK", x, y, 20.0, .{ .solid = .{ 0.36, 0.92, 0.52, 1.0 } });
    x += try addRichRun(build, fonts, .{}, " / ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    x += try addRichRun(build, fonts, .{ .weight = .bold }, "WARN", x, y, 20.0, .{ .solid = .{ 0.98, 0.72, 0.32, 1.0 } });
    x += try addRichRun(build, fonts, .{}, " / ", x, y, 17.0, .{ .solid = .{ 0.56, 0.64, 0.74, 1.0 } });
    _ = try addRichRun(build, fonts, .{ .weight = .bold }, "CRIT", x, y, 20.0, .{ .solid = .{ 1.0, 0.40, 0.44, 1.0 } });
}

/// Add a single run with a solid or gradient/image paint. Solid paints
/// emit through the shaped text path (deduped glyph atlas); gradient /
/// image paints go through the path namespace with `mapPaintToLocal`
/// baking the world paint into glyph-local coordinates. Returns the
/// run's x advance.
fn addRichRun(
    build: *SceneBuild,
    fonts: *FontSet,
    style: snail.FontStyle,
    text: []const u8,
    x: f32,
    y: f32,
    em: f32,
    paint: snail.Paint,
) !f32 {
    const allocator = build.allocator;
    var shaped = try snail.shape(allocator, &fonts.faces, text, .{ .style = style });
    defer shaped.deinit();
    const advance = em * shaped.advanceX();
    switch (paint) {
        .solid => |color| {
            try ensureUnhintedRunCurves(build, fonts, &shaped);
            var pic = try snail_helpers.placeRun(allocator, &shaped, &fonts.faces, .{
                .baseline = .{ .x = x, .y = y },
                .em = em,
                .color = color,
            });
            defer pic.deinit();
            try build.shapes.appendSlice(allocator, pic.shapes);
        },
        else => {
            // Per-glyph paint baked into glyph-local space.
            for (shaped.glyphs) |g| {
                const fid = g.font_id;
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
                const curves = try fonts.fonts[fid].extractCurves(allocator, allocator, g.glyph_id);
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
//
// Each function below times ONE row in the preparation table. Callers
// gate each row independently via the `Filter`, so a focused
// `perf record` of, say, `glyph-extract` shows only that workload.

fn timeFontLoad() f64 {
    // Page in the embedded TTF .rodata once so the first measured
    // iteration doesn't fold a one-shot mmap fault into the average.
    _ = snail.Font.init(assets.noto_sans_regular) catch return 0;
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        _ = snail.Font.init(assets.noto_sans_regular) catch return 0;
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeGlyphExtract(allocator: std.mem.Allocator) !f64 {
    // ASCII glyph prep: extract curves into a fresh pool. Uses an
    // ArenaAllocator as `scratch` for the per-glyph intermediate
    // buffers; resets between glyphs so the allocations collapse to
    // bump-pointer ops.
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var pool = try snail.PagePool.init(allocator, .{ .max_layers = 2, .curve_words_per_page = 1 << 16, .band_words_per_page = 1 << 14 });
        defer pool.deinit();
        var font = try snail.Font.init(assets.noto_sans_regular);
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
            const curves = try font.extractCurves(allocator, scratch_arena.allocator(), gid);
            _ = scratch_arena.reset(.retain_capacity);
            try owned.append(allocator, curves);
            try entries.append(allocator, .{
                .key = snail.recordKey.unhintedGlyph(0, gid),
                .curves = owned.items[owned.items.len - 1],
            });
        }
        var atlas = try snail.Atlas.from(allocator, pool, entries.items);
        defer atlas.deinit();
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterSetup(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        var h = snail.HintVm.init(allocator, font) catch return 0;
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        var prepared = h.prepare(ppem) catch return 0;
        prepared.deinit();
        total += usFrom(start);
        h.deinit();
    }
    return total / PREP_RUNS;
}

fn timeHinterExecute(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    // VM execute: the size is prepared once (fpgm + prep), and the timed loop
    // measures only per-glyph TT bytecode execution — no fpgm/prep, no curve
    // build. The output advance is uncached at this layer
    // (helpers.HintedGlyphCache would memoize); each call re-runs the VM.
    var h = snail.HintVm.init(allocator, font) catch return 0;
    defer h.deinit();
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    var prepared = h.prepare(ppem) catch return 0;
    defer prepared.deinit();

    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = font.glyphIndex(ch) catch continue;
            _ = h.hintedAdvance(&prepared, gid) catch continue;
        }
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterFull(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var h = snail.HintVm.init(allocator, font) catch return 0;
        defer h.deinit();
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const start = nowNs();
        var prepared = h.prepare(ppem) catch continue;
        for (PRINTABLE_ASCII) |ch| {
            const gid = font.glyphIndex(ch) catch continue;
            var curves = h.hintGlyph(allocator, scratch_arena.allocator(), &prepared, gid) catch continue;
            _ = scratch_arena.reset(.retain_capacity);
            curves.deinit();
        }
        prepared.deinit();
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterParagraphCold(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    // Cold: fresh HintVm + HintedGlyphCache, paragraph hinted once
    // through the cache. The "cold" axis is the cache state (every
    // (glyph, ppem) is a miss on its first occurrence) — repeated
    // glyphs within the paragraph hit the cache on the second use, the
    // same way the in-VM cache used to behave before the cache split
    // out into helpers (commit d7864b2).
    var total: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var h = snail.HintVm.init(allocator, font) catch return 0;
        defer h.deinit();
        var cache = snail_helpers.HintedGlyphCache.init(allocator, &h, 0);
        defer cache.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const ppem = snail.HintPpem.uniform(ppem_26_6);
        const start = nowNs();
        try cacheParagraph(&cache, font, allocator, &scratch_arena, ppem);
        total += usFrom(start);
    }
    return total / PREP_RUNS;
}

fn timeHinterParagraphWarm(allocator: std.mem.Allocator, font: *const snail.Font, ppem_26_6: u32) !f64 {
    // Warm: HintVm + helpers.HintedGlyphCache shared across iterations.
    // The first pass populates the cache; subsequent passes hit it for
    // every (ppem, glyph_id) → bytes lookup, exercising the recommended
    // production path.
    var h = snail.HintVm.init(allocator, font) catch return 0;
    defer h.deinit();
    var cache = snail_helpers.HintedGlyphCache.init(allocator, &h, 0);
    defer cache.deinit();
    const ppem = snail.HintPpem.uniform(ppem_26_6);
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    // Warmup the cache.
    try cacheParagraph(&cache, font, allocator, &scratch_arena, ppem);

    var total: f64 = 0;
    for (0..TEXT_ITERS) |_| {
        const start = nowNs();
        try cacheParagraph(&cache, font, allocator, &scratch_arena, ppem);
        total += usFrom(start);
    }
    return total / TEXT_ITERS;
}

fn hintParagraph(h: *snail.HintVm, font: *const snail.Font, allocator: std.mem.Allocator, scratch_arena: *std.heap.ArenaAllocator, ppem: snail.HintPpem) !void {
    var prepared = try h.prepare(ppem);
    defer prepared.deinit();
    for (PARAGRAPH) |ch| {
        const gid = font.glyphIndex(ch) catch continue;
        var curves = h.hintGlyph(allocator, scratch_arena.allocator(), &prepared, gid) catch continue;
        _ = scratch_arena.reset(.retain_capacity);
        std.mem.doNotOptimizeAway(curves.curve_count);
        curves.deinit();
    }
}

fn cacheParagraph(cache: *snail_helpers.HintedGlyphCache, font: *const snail.Font, allocator: std.mem.Allocator, scratch_arena: *std.heap.ArenaAllocator, ppem: snail.HintPpem) !void {
    for (PARAGRAPH) |ch| {
        const gid = font.glyphIndex(ch) catch continue;
        const curves = cache.getOrInsertCurves(allocator, scratch_arena.allocator(), gid, ppem) catch continue;
        _ = scratch_arena.reset(.retain_capacity);
        std.mem.doNotOptimizeAway(curves.curve_count);
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
    hinted: bool,

    fn init(allocator: std.mem.Allocator, pool: *snail.PagePool, fonts: *FontSet, hinted: bool) PreparedLines {
        _ = allocator;
        return .{ .pool = pool, .fonts = fonts, .hinted = hinted };
    }

    fn deinit(self: *PreparedLines, allocator: std.mem.Allocator) void {
        for (self.items.items) |*it| it.deinit();
        self.items.deinit(allocator);
    }

    fn add(self: *PreparedLines, allocator: std.mem.Allocator, line: TextLine) !void {
        const item = try prepareLine(allocator, self.pool, self.fonts, line, self.hinted);
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
    line: TextLine,
    hinted: bool,
) !PreparedLine {
    // Mirror addShapedLine's setup but stop short of the picture build,
    // and stop short of releasing the shaped run — that's what the
    // timed loop is going to consume.
    if (hinted and fonts.has_hinter) {
        const ppem_26_6 = hintPpem26_6(line.size) catch return prepareLineUnhinted(allocator, pool, fonts, line);
        var shaped = try snail.shape(allocator, &fonts.faces, line.text, .{ .style = line.style, .target_ppem = snail.HintPpem.uniform(ppem_26_6), .advance_provider = fonts.advanceProvider() });
        errdefer shaped.deinit();
        var build = SceneBuild.init(allocator, pool);
        defer build.deinit();
        const ok = ensureHintedRunCurves(&build, fonts, &shaped, ppem_26_6) catch false;
        if (!ok) {
            // Hinting failed (non-Latin fallback face etc) — fall through to unhinted.
            shaped.deinit();
            return prepareLineUnhinted(allocator, pool, fonts, line);
        }
        return .{ .shaped = shaped, .line = line, .hinted = true, .ppem_26_6 = ppem_26_6 };
    }
    return prepareLineUnhinted(allocator, pool, fonts, line);
}

fn prepareLineUnhinted(
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    fonts: *FontSet,
    line: TextLine,
) !PreparedLine {
    var shaped = try snail.shape(allocator, &fonts.faces, line.text, .{ .style = line.style });
    errdefer shaped.deinit();
    var build = SceneBuild.init(allocator, pool);
    defer build.deinit();
    try ensureUnhintedRunCurves(&build, fonts, &shaped);
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
            var pic = try snail_helpers.placeRun(allocator, &it.shaped, null, .{
                .baseline = .{ .x = it.line.x, .y = it.line.y },
                .em = it.line.size,
                .color = it.line.color,
                .mode = .{ .truetype = .{ .ppem_26_6 = it.ppem_26_6 } },
            });
            shape_count += pic.shapes.len;
            pic.deinit();
        } else {
            var pic = try snail_helpers.placeRun(allocator, &it.shaped, &prepared.fonts.faces, .{
                .baseline = .{ .x = it.line.x, .y = it.line.y },
                .em = it.line.size,
                .color = it.line.color,
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
    picture: *const snail_helpers.Picture,
) !struct { us: f64, words: usize, segments: usize } {
    const word_cap = snail.emit.wordBudget(picture.shapes.len);
    const words = try allocator.alloc(u32, word_cap);
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, snail.emit.segmentBudget(picture.shapes.len));
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    // Warmup
    for (0..RECORD_WARMUP) |_| {
        wlen = 0;
        slen = 0;
        _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture.shapes, .identity, .{ 1, 1, 1, 1 });
    }
    const start = nowNs();
    for (0..RECORD_ITERS) |_| {
        wlen = 0;
        slen = 0;
        _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture.shapes, .identity, .{ 1, 1, 1, 1 });
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
    picture: *const snail_helpers.Picture,
) !EmittedRecords {
    const word_cap = snail.emit.wordBudget(picture.shapes.len);
    const words = try allocator.alloc(u32, word_cap);
    errdefer allocator.free(words);
    const seg_cap = @max(snail.emit.segmentBudget(picture.shapes.len), 1);
    const segs = try allocator.alloc(snail.DrawSegment, seg_cap);
    errdefer allocator.free(segs);
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, atlas, picture.shapes, .identity, .{ 1, 1, 1, 1 });
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

// ── main ──

pub fn main() !void {
    // Use the SMP allocator — same as the pre-rewrite bench. The
    // DebugAllocator (default in demos) tracks every allocation for
    // leak detection, which adds 5-10% per alloc/free on the prep
    // hot path. Bench needs raw throughput numbers.
    const allocator = std.heap.smp_allocator;

    var filter = try Filter.init(allocator);
    defer filter.deinit();

    const prepared_render_state = drawState(WIDTH, HEIGHT, .none);

    const font_data = assets.noto_sans_regular;

    // ── Preparation rows (each gated independently) ──
    var snail_prep = SnailPrep{};
    if (filter.run("font-load")) snail_prep.font_load_us = timeFontLoad();
    if (filter.run("glyph-extract")) snail_prep.ascii_prep_us = try timeGlyphExtract(allocator);
    if (filter.run("hint-setup") or filter.run("hint-execute") or filter.run("hint-full") or
        filter.run("hinter-cold") or filter.run("hinter-warm"))
    {
        var font = try snail.Font.init(assets.noto_sans_regular);
        if (filter.run("hint-setup")) snail_prep.ascii_hint_setup_us = try timeHinterSetup(allocator, &font, 12 * 64);
        if (filter.run("hint-execute")) snail_prep.ascii_hint_execute_us = try timeHinterExecute(allocator, &font, 12 * 64);
        if (filter.run("hint-full")) snail_prep.ascii_hint_us = try timeHinterFull(allocator, &font, 12 * 64);
        if (filter.run("hinter-cold")) snail_prep.paragraph_hint_context_cold_us = try timeHinterParagraphCold(allocator, &font, 12 * 64);
        if (filter.run("hinter-warm")) snail_prep.paragraph_hint_context_warm_us = try timeHinterParagraphWarm(allocator, &font, 12 * 64);
    }

    var vector_prep = VectorPrep{};
    if (filter.run("vector-build")) {
        const vb = try timeVectorBuild(allocator);
        vector_prep = vb;
    }

    const ft = if (filter.run("freetype") or filter.run("picture-build"))
        try freetype.bench(font_data, .{
            .prep_runs = PREP_RUNS,
            .text_iters = TEXT_ITERS,
            .printable_ascii = PRINTABLE_ASCII[0..],
            .sizes = SIZES[0..],
            .short = SHORT,
            .sentence = SENTENCE,
            .paragraph = PARAGRAPH,
        })
    else
        null;

    var fonts = try FontSet.init(allocator);
    defer fonts.deinit();

    // ── Text workload table ──
    var text_rows: std.ArrayList(TextRow) = .empty;
    defer text_rows.deinit(allocator);
    if (filter.run("picture-build")) {
        for (text_workloads) |workload| {
            try text_rows.append(allocator, .{
                .label = workload.name(),
                .snail_us = try timeTextWorkload(allocator, &fonts, workload),
                .ft_us = ft.?.layout(workload),
            });
        }
    }
    if (filter.run("picture-build-hinted")) {
        for (hinted_text_workloads) |workload| {
            try text_rows.append(allocator, .{
                .label = hintedTextWorkloadName(workload),
                .snail_us = try timeHintedTextWorkload(allocator, &fonts, workload),
                .ft_us = null,
            });
        }
    }

    // ── Scene bundles ──
    //
    // Bundles + CPU upload + emit are needed by emit/cpu-draw/modes/
    // gl*/vulkan rows. Skip the whole setup if none of those are
    // enabled — saves several seconds and ~16% of the perf samples
    // when running only a prep-side workload like `glyph-extract`.
    const needs_bundles = filter.run("emit") or filter.run("cpu-draw") or filter.run("modes") or
        filter.run("gl33") or filter.run("gl44") or filter.run("gles30") or filter.run("vulkan") or
        filter.run("gl33-breakdown");

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 24,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var bundles: [scene_kinds.len]SceneBundle = undefined;
    var bundle_count: usize = 0;
    defer for (bundles[0..bundle_count]) |*b| b.deinit();

    var cpu_cache_storage: ?snail.CpuBackendCache = null;
    defer if (cpu_cache_storage) |*c| c.deinit();
    var cpu_bindings: [scene_kinds.len]snail.Binding = undefined;

    var emitted: [scene_kinds.len]EmittedRecords = undefined;
    var emitted_count: usize = 0;
    defer for (emitted[0..emitted_count]) |*e| e.deinit();

    if (needs_bundles) {
        for (scene_kinds) |kind| {
            bundles[bundle_count] = try buildScene(allocator, pool, &fonts, kind);
            bundle_count += 1;
        }

        // ── CPU prepared pages + per-scene emit ──
        cpu_cache_storage = try snail.CpuBackendCache.init(allocator, pool, .{
            .max_bindings = 16,
            .layer_info_height = 256,
            .max_images = 8,
        });
        var atlas_ptrs: [scene_kinds.len]*const snail.Atlas = undefined;
        for (bundles[0..bundle_count], 0..) |*b, i| atlas_ptrs[i] = &b.atlas;
        try cpu_cache_storage.?.upload(allocator, atlas_ptrs[0..bundle_count], cpu_bindings[0..bundle_count]);

        for (bundles[0..bundle_count], 0..) |*b, i| {
            emitted[i] = try emitScene(allocator, cpu_bindings[i], &b.atlas, &b.picture);
            emitted_count += 1;
        }
    }

    // ── Record build (emit.emit) timing ──
    var record_rows: std.ArrayList(RecordRow) = .empty;
    defer record_rows.deinit(allocator);
    if (filter.run("emit")) {
        for (scene_kinds, 0..) |kind, i| {
            const r = try timeRecordEmit(allocator, cpu_bindings[i], &bundles[i].atlas, &bundles[i].picture);
            try record_rows.append(allocator, .{
                .scene = kind,
                .us = r.us,
                .shapes = bundles[i].picture.shapes.len,
                .words = r.words,
                .segments = r.segments,
            });
        }
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

    if (filter.run("cpu-draw")) {
        for (scene_kinds, 0..) |kind, i| {
            const records = render_timing.DrawRecords{
                .words = emitted[i].words[0..emitted[i].word_len],
                .segments = emitted[i].segments[0..emitted[i].segment_len],
            };
            const us = try render_timing.timeCpuDraw(&cpu_renderer, prepared_render_state, records, &.{&cpu_cache_storage.?}, cpu_pixels, CPU_WARMUP, CPU_FRAMES, null);
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
            const us = try render_timing.timeCpuDraw(&cpu_renderer_threaded, prepared_render_state, records, &.{&cpu_cache_storage.?}, cpu_pixels_threaded, CPU_WARMUP, CPU_FRAMES, &cpu_pool);
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
    }

    // ── Mode rows (CPU) ──
    var mode_rows: std.ArrayList(ModeRow) = .empty;
    defer mode_rows.deinit(allocator);
    if (filter.run("modes")) {
        try benchCpuModes(allocator, &cpu_renderer, &cpu_cache_storage.?, "CPU", &bundles, bundle_count, cpu_bindings[0..bundle_count], cpu_pixels, &mode_rows, null);
        try benchCpuModes(allocator, &cpu_renderer_threaded, &cpu_cache_storage.?, "CPU (threaded)", &bundles, bundle_count, cpu_bindings[0..bundle_count], cpu_pixels_threaded, &mode_rows, &cpu_pool);
    }

    // ── GL hardware rows (collected as each GL backend stands up) ──
    var gl_hardware_rows: std.ArrayList(report.GlHardwareRow) = .empty;
    defer {
        for (gl_hardware_rows.items) |row| row.deinit(allocator);
        gl_hardware_rows.deinit(allocator);
    }

    var gl33_breakdown_rows: std.ArrayList(Gl33BreakdownRow) = .empty;
    defer gl33_breakdown_rows.deinit(allocator);
    const want_gl33_breakdown = filter.run("gl33-breakdown");
    if (comptime build_options.enable_gl33) if (filter.run("gl33") or want_gl33_breakdown) {
        try benchGl33(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows, &gl33_breakdown_rows, want_gl33_breakdown);
    };
    if (comptime build_options.enable_gl44) if (filter.run("gl44")) {
        try benchGl44(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows);
    };
    if (comptime build_options.enable_gles30) if (filter.run("gles30")) {
        try benchGles30(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows, &gl_hardware_rows);
    };

    if (comptime build_options.enable_vulkan) if (filter.run("vulkan")) {
        try benchVulkan(allocator, pool, &bundles, bundle_count, &render_rows, &mode_rows);
    };

    // ── Output ──
    std.debug.print(
        \\# Snail Benchmarks
        \\
        \\NotoSans-Regular, {d} prep runs, {d} text iterations, {d} draw-record iterations.
        \\Scenarios: {d} text workloads (un-hinted + hinted), {d} scene kinds, {d} render modes.
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
    });
    report.printHardwareTable(gl_hardware_rows.items, build_options.enable_vulkan);
    report.printPreparationTables(snail_prep, vector_prep, ft);
    if (text_rows.items.len > 0) report.printTextTable(text_rows.items);
    if (record_rows.items.len > 0) report.printRecordTable(record_rows.items);
    if (render_rows.items.len > 0) report.printRenderTable(WIDTH, HEIGHT, CPU_FRAMES, GPU_FRAMES, render_rows.items);
    if (mode_rows.items.len > 0) report.printModeTable(mode_rows.items);
    if (gl33_breakdown_rows.items.len > 0) printGl33BreakdownTable(gl33_breakdown_rows.items);
}

fn printGl33BreakdownTable(rows: []const Gl33BreakdownRow) void {
    std.debug.print(
        \\## GL 3.3 Per-Frame Breakdown
        \\
        \\Each CPU-stage column (Clear / beginDraw / state.draw / glFinish) is
        \\measured around a per-frame `glFinish` so totals include CPU stall
        \\waiting for the GPU. The `GPU` column is a `GL_TIME_ELAPSED` timer
        \\query — pure on-GPU time, no CPU clock involved — reported as the
        \\minimum of 5 samples × `GPU_FRAMES` queries each, to filter clock
        \\thrash and external scheduling noise. Use the GPU column when
        \\evaluating shader-side changes.
        \\
        \\| Scene | Clear | beginDraw | state.draw | glFinish | Total | GPU |
        \\|---|---:|---:|---:|---:|---:|---:|
        \\
    , .{});
    for (rows) |row| {
        std.debug.print(
            "| {s} | {d:.2} us | {d:.2} us | {d:.2} us | {d:.2} us | {d:.2} us | {d:.2} us |\n",
            .{ row.scene.name(), row.clear_us, row.begin_us, row.draw_us, row.finish_us, row.total_us, row.gpu_us },
        );
    }
    std.debug.print("\n", .{});
}

// ── CPU mode timings ──

fn benchCpuModes(
    allocator: std.mem.Allocator,
    renderer: *snail.CpuRenderer,
    cache: *const snail.CpuBackendCache,
    backend_name: []const u8,
    bundles: *const [scene_kinds.len]SceneBundle,
    bundle_count: usize,
    bindings: []const snail.Binding,
    pixels: []u8,
    rows: *std.ArrayList(ModeRow),
    thread_pool: ?*snail.ThreadPool,
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
            const draw_us = try render_timing.timeCpuDraw(renderer, state, records, &.{cache}, pixels, CPU_WARMUP, CPU_FRAMES, thread_pool);
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
    breakdown_rows: *std.ArrayList(Gl33BreakdownRow),
    capture_breakdown: bool,
) !void {
    var ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT, .gl33);
    defer ctx.deinit();
    const fb = render_timing.initFramebuffer(WIDTH, HEIGHT);
    defer render_timing.destroyFramebuffer(fb);

    var renderer = try embed_gl.Gl33Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try embed_gl.Gl33BackendCache.init(allocator, pool, .{
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

        if (capture_breakdown) {
            const bd = try render_timing.timeGl33DrawBreakdown(allocator, &renderer, prepared_state, records, &.{&cache}, GPU_WARMUP, GPU_FRAMES);
            try breakdown_rows.append(allocator, .{
                .scene = kind,
                .clear_us = bd.clear_us,
                .begin_us = bd.begin_us,
                .draw_us = bd.draw_us,
                .finish_us = bd.finish_us,
                .total_us = bd.total_us,
                .gpu_us = bd.gpu_us,
            });
        }
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

    var renderer = try embed_gl.Gl44Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try embed_gl.Gl44BackendCache.init(allocator, pool, .{
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

    var renderer = try embed_gl.Gles30Renderer.init(allocator);
    defer renderer.deinit();

    var cache = try embed_gl.Gles30BackendCache.init(allocator, pool, .{
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

    // Benchmark the embeddable path — a standalone cache + the reference caller
    // renderer — the same code integrators run.
    var layout: embed_vulkan.VulkanResourceLayout = undefined;
    try layout.init(vk_ctx);
    defer layout.deinit();
    const transfer_pool = try embed_vulkan.createTransferPool(vk_ctx);
    defer embed_vulkan.vk.vkDestroyCommandPool(vk_ctx.device, transfer_pool, null);

    var cache = try embed_vulkan.VulkanBackendCache.init(allocator, pool, embed_vulkan.cachePipelineShape(vk_ctx, &layout, transfer_pool), .{
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

    var max_words: usize = 0;
    for (bundles[0..bundle_count]) |*b| max_words = @max(max_words, snail.emit.wordBudget(b.picture.shapes.len));
    var caller = try embed_vulkan.Renderer.init(vk_ctx, cache.descriptorSetLayout(), max_words * @sizeOf(u32), vulkan_platform.OFFSCREEN_FRAMES_IN_FLIGHT, false);
    defer caller.deinit();

    const backend_name = "Vulkan";
    const supports_lcd = vk_ctx.supports_dual_source_blend;

    const prepared_state = drawState(WIDTH, HEIGHT, .none);
    for (scene_kinds, 0..) |kind, i| {
        var records_emitted = try emitScene(allocator, bindings[i], &bundles[i].atlas, &bundles[i].picture);
        defer records_emitted.deinit();
        const records = render_timing.DrawRecords{
            .words = records_emitted.words[0..records_emitted.word_len],
            .segments = records_emitted.segments[0..records_emitted.segment_len],
        };
        const us = try render_timing.timeVulkanDraw(&caller, cache.descriptorSet(), prepared_state, records, GPU_WARMUP, GPU_FRAMES);
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
            const draw_us = try render_timing.timeVulkanDraw(&caller, cache.descriptorSet(), state, records, GPU_WARMUP, GPU_FRAMES);
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
