const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");

pub const width: u32 = 640;
pub const height: u32 = 360;
pub const paragraph =
    "The quick brown fox jumps over the lazy dog. " ++
    "Snail prepares glyphs, paths, atlases, and draw records for consumer-owned renderers. " ++
    "0123456789";
pub const multiscript = paragraph ++
    " \xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87" ++
    " \xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87" ++
    " \xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xb0\xe0\xb8\x94\xe0\xb8\xb5";

pub const SceneKind = enum {
    regular,
    hinted,
    autohint,
    colr,
    path,
    mixed,
};

pub const FontSet = struct {
    allocator: std.mem.Allocator,
    fonts: []snail.Font,
    faces: snail.Faces,

    pub fn init(allocator: std.mem.Allocator) !FontSet {
        const data = [_][]const u8{
            assets.noto_sans_regular,
            assets.noto_sans_arabic,
            assets.noto_sans_devanagari,
            assets.noto_sans_thai,
        };
        const fonts = try allocator.alloc(snail.Font, data.len);
        errdefer allocator.free(fonts);
        for (data, 0..) |bytes, i| fonts[i] = try snail.Font.init(bytes);
        var faces = try snail.Faces.build(allocator, &.{
            .{ .font = &fonts[0] },
            .{ .font = &fonts[1], .fallback = true },
            .{ .font = &fonts[2], .fallback = true },
            .{ .font = &fonts[3], .fallback = true },
        });
        errdefer faces.deinit();
        return .{ .allocator = allocator, .fonts = fonts, .faces = faces };
    }

    pub fn deinit(self: *FontSet) void {
        self.faces.deinit();
        self.allocator.free(self.fonts);
        self.* = undefined;
    }
};

const SceneBuild = struct {
    allocator: std.mem.Allocator,
    scratch_arena: std.heap.ArenaAllocator,
    owned_curves: std.ArrayList(snail.GlyphCurves),
    colr_layers: std.ArrayList(snail.AtlasLayer),
    entries: std.ArrayList(snail.AtlasEntry),
    shapes: std.ArrayList(snail.Shape),
    autohint_analyzer: ?snail.autohint.AutohintAnalyzer,
    next_path_id: u32,

    fn init(allocator: std.mem.Allocator) SceneBuild {
        return .{
            .allocator = allocator,
            .scratch_arena = std.heap.ArenaAllocator.init(allocator),
            .owned_curves = .empty,
            .colr_layers = .empty,
            .entries = .empty,
            .shapes = .empty,
            .autohint_analyzer = null,
            .next_path_id = 0,
        };
    }

    fn deinit(self: *SceneBuild) void {
        for (self.owned_curves.items) |*curves| curves.deinit();
        self.owned_curves.deinit(self.allocator);
        self.colr_layers.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.shapes.deinit(self.allocator);
        if (self.autohint_analyzer) |*analyzer| analyzer.deinit();
        self.scratch_arena.deinit();
        self.* = undefined;
    }

    fn scratch(self: *SceneBuild) std.mem.Allocator {
        return self.scratch_arena.allocator();
    }

    fn resetScratch(self: *SceneBuild) void {
        _ = self.scratch_arena.reset(.retain_capacity);
    }

    fn addCurves(self: *SceneBuild, key: snail.recordKey.RecordKey, curves: snail.GlyphCurves) !void {
        try self.owned_curves.append(self.allocator, curves);
        try self.entries.append(self.allocator, .{
            .key = key,
            .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
        });
    }
};

pub const Scene = struct {
    build: SceneBuild,
    atlas: snail.Atlas,

    pub fn shapes(self: *const Scene) []const snail.Shape {
        return self.build.shapes.items;
    }

    pub fn entries(self: *const Scene) []const snail.AtlasEntry {
        return self.build.entries.items;
    }

    pub fn colrLayerCount(self: *const Scene) usize {
        return if (self.build.colr_layers.items.len == 0) 0 else self.build.colr_layers.items.len + 1;
    }

    pub fn deinit(self: *Scene) void {
        self.atlas.deinit();
        self.build.deinit();
        self.* = undefined;
    }
};

/// A fixed public-API path fixture with lines, quadratics, cubics, a rounded
/// rectangle, and an ellipse. Preparation and curve packing benchmarks share
/// it so their reported source-curve count completely describes the workload.
pub fn benchmarkPath(allocator: std.mem.Allocator) !snail.Path {
    var path = snail.Path.init(allocator);
    errdefer path.deinit();
    try path.moveTo(.{ .x = 8, .y = 58 });
    try path.lineTo(.{ .x = 22, .y = 14 });
    try path.quadTo(.{ .x = 52, .y = -4 }, .{ .x = 76, .y = 24 });
    try path.cubicTo(.{ .x = 98, .y = 50 }, .{ .x = 70, .y = 82 }, .{ .x = 38, .y = 68 });
    try path.close();
    try path.addRoundedRect(.{ .x = 112, .y = 8, .w = 78, .h = 62 }, 13);
    try path.addEllipse(.{ .x = 204, .y = 8, .w = 72, .h = 62 });
    return path;
}

pub const Emitted = struct {
    allocator: std.mem.Allocator,
    words: []u32,
    segments: []snail.render.records.DrawSegment,
    word_len: usize,
    segment_len: usize,

    pub fn records(self: *const Emitted) snail.render.records.DrawRecords {
        return .{
            .words = self.words[0..self.word_len],
            .segments = self.segments[0..self.segment_len],
        };
    }

    pub fn deinit(self: *Emitted) void {
        self.allocator.free(self.words);
        self.allocator.free(self.segments);
        self.* = undefined;
    }
};

pub fn emitScene(
    allocator: std.mem.Allocator,
    binding: snail.render.records.Binding,
    scene: *const Scene,
) !Emitted {
    const words = try allocator.alloc(u32, snail.emit.wordBudget(scene.shapes().len));
    errdefer allocator.free(words);
    const segments = try allocator.alloc(snail.render.records.DrawSegment, @max(snail.emit.segmentBudget(scene.shapes().len), 1));
    errdefer allocator.free(segments);
    var word_len: usize = 0;
    var segment_len: usize = 0;
    _ = try snail.emit.emit(
        words,
        segments,
        &word_len,
        &segment_len,
        binding,
        &scene.atlas,
        scene.shapes(),
        .identity,
        .{ 1, 1, 1, 1 },
    );
    return .{
        .allocator = allocator,
        .words = words,
        .segments = segments,
        .word_len = word_len,
        .segment_len = segment_len,
    };
}

pub fn buildScene(allocator: std.mem.Allocator, pool: *snail.PagePool, kind: SceneKind) !Scene {
    var build = SceneBuild.init(allocator);
    errdefer build.deinit();

    switch (kind) {
        .path => try addPaths(&build),
        .colr => try addColr(&build),
        else => {
            var fonts = try FontSet.init(allocator);
            defer fonts.deinit();
            switch (kind) {
                .regular => try addRegularText(&build, &fonts),
                .hinted => try addHintedText(&build, &fonts),
                .autohint => try addAutohintText(&build, &fonts),
                .mixed => {
                    try addPaths(&build);
                    try addRegularText(&build, &fonts);
                },
                .path, .colr => unreachable,
            }
        },
    }

    var atlas = try snail.Atlas.from(allocator, pool, build.entries.items);
    errdefer atlas.deinit();
    return .{ .build = build, .atlas = atlas };
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.recordKey.RecordKey) bool {
    for (entries) |entry| if (entry.key.eql(key)) return true;
    return false;
}

fn ensureUnhinted(build: *SceneBuild, fonts: *FontSet, shaped: *const snail.ShapedText) !void {
    for (shaped.glyphs) |glyph| {
        const key = snail.recordKey.unhintedGlyph(glyph.font_id, glyph.glyph_id);
        if (containsKey(build.entries.items, key)) continue;
        const curves = try fonts.fonts[glyph.font_id].extractCurves(build.allocator, build.scratch(), glyph.glyph_id);
        build.resetScratch();
        try build.addCurves(key, curves);
    }
}

fn addRegularText(build: *SceneBuild, fonts: *FontSet) !void {
    var shaped = try snail.shape(build.allocator, &fonts.faces, paragraph, .{});
    defer shaped.deinit();
    try ensureUnhinted(build, fonts, &shaped);
    const colors = [_][4]f32{
        .{ 0.08, 0.12, 0.22, 1 },
        .{ 0.16, 0.38, 0.70, 0.92 },
        .{ 0.50, 0.18, 0.22, 0.88 },
        .{ 0.12, 0.46, 0.30, 0.90 },
    };
    for (0..6) |row| {
        const placed = try snail.placeRunAlloc(build.allocator, &shaped, &fonts.faces, .{
            .baseline = .{ .x = 18, .y = 38 + @as(f32, @floatFromInt(row)) * 54 },
            .em = 18 + @as(f32, @floatFromInt(row % 3)) * 2,
            .color = colors[row % colors.len],
        });
        defer build.allocator.free(placed);
        try build.shapes.appendSlice(build.allocator, placed);
    }
}

fn addHintedText(build: *SceneBuild, fonts: *FontSet) !void {
    const ppem_26_6: u32 = 20 * 64;
    var vm = try snail.HintVm.init(build.allocator, &fonts.fonts[0]);
    defer vm.deinit();
    var prepared = try vm.prepare(snail.HintPpem.uniform(ppem_26_6));
    defer prepared.deinit();
    var shaped = try snail.shape(build.allocator, &fonts.faces, paragraph, .{ .target_ppem = snail.HintPpem.uniform(ppem_26_6) });
    defer shaped.deinit();
    for (shaped.glyphs) |glyph| {
        const key = snail.recordKey.hintedGlyph(glyph.font_id, glyph.glyph_id, ppem_26_6);
        if (containsKey(build.entries.items, key)) continue;
        const curves = try vm.hintGlyph(build.allocator, build.scratch(), &prepared, glyph.glyph_id);
        build.resetScratch();
        try build.addCurves(key, curves);
    }
    for (0..6) |row| {
        const placed = try snail.placeRunAlloc(build.allocator, &shaped, null, .{
            .baseline = .{ .x = 18, .y = 38 + @as(f32, @floatFromInt(row)) * 54 },
            .em = 20,
            .color = .{ 0.08, 0.18 + @as(f32, @floatFromInt(row)) * 0.04, 0.34, 1 },
            .mode = .{ .truetype = .{ .ppem_26_6 = ppem_26_6 } },
        });
        defer build.allocator.free(placed);
        try build.shapes.appendSlice(build.allocator, placed);
    }
}

fn addAutohintText(build: *SceneBuild, fonts: *FontSet) !void {
    var shaped = try snail.shape(build.allocator, &fonts.faces, paragraph, .{});
    defer shaped.deinit();
    try ensureUnhinted(build, fonts, &shaped);
    build.autohint_analyzer = try snail.autohint.AutohintAnalyzer.init(build.allocator, assets.noto_sans_regular);
    const analyzer = &build.autohint_analyzer.?;

    for (shaped.glyphs) |glyph| {
        const key = snail.recordKey.autohintGlyph(glyph.font_id, glyph.glyph_id);
        if (containsKey(build.entries.items, key)) continue;
        const base_key = snail.recordKey.unhintedGlyph(glyph.font_id, glyph.glyph_id);
        const base = for (build.entries.items) |entry| {
            if (entry.key.eql(base_key)) break entry.curves;
        } else continue;
        if (base.isEmpty()) continue;
        const x = try build.scratch().alloc(snail.autohint.FeatureEdge, snail.autohint.warp.max_knots);
        const y = try build.scratch().alloc(snail.autohint.FeatureEdge, snail.autohint.warp.max_knots);
        const analysis = try analyzer.analyzeGlyph(build.scratch(), glyph.glyph_id, x, y);
        try build.entries.append(build.allocator, .{
            .key = key,
            .curves = snail.GlyphCurves.empty(build.scratch()),
            .autohint = .{ .font = analyzer.fontFeatures(), .glyph = analysis },
            .autohint_base = base_key,
        });
    }

    const policy = snail.autohint.AutohintPolicy{
        .x = .{ .@"align" = .grid, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } }, .positioning = .relative },
        .y = .{ .@"align" = .blue_zones, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } } },
    };
    for (0..6) |row| {
        const placed = try snail.placeRunAlloc(build.allocator, &shaped, null, .{
            .baseline = .{ .x = 18, .y = 38 + @as(f32, @floatFromInt(row)) * 54 },
            .em = 18 + @as(f32, @floatFromInt(row % 3)) * 2,
            .color = .{ 0.10, 0.32, 0.22 + @as(f32, @floatFromInt(row)) * 0.04, 1 },
            .mode = .{ .autohint = policy },
        });
        defer build.allocator.free(placed);
        for (shaped.glyphs, placed) |glyph, *shape| {
            const key = snail.recordKey.autohintGlyph(glyph.font_id, glyph.glyph_id);
            if (!containsKey(build.entries.items, key)) {
                shape.key = snail.recordKey.unhintedGlyph(glyph.font_id, glyph.glyph_id);
                shape.autohint_policy = null;
            }
        }
        try build.shapes.appendSlice(build.allocator, placed);
    }
}

fn addColr(build: *SceneBuild) !void {
    var font = try snail.Font.init(assets.twemoji_mozilla);
    const glyph_id = try font.glyphIndex(0x1F30D);
    var iter = font.colrLayers(glyph_id);
    const first = iter.next() orelse return error.MissingColrLayers;

    const first_curves = try font.extractCurves(build.allocator, build.scratch(), first.glyph_id);
    build.resetScratch();
    try build.owned_curves.append(build.allocator, first_curves);
    const base_curves = build.owned_curves.items[build.owned_curves.items.len - 1];
    const fallback = [4]f32{ 0.18, 0.35, 0.70, 1.0 };
    const first_color: [4]f32 = if (first.color[0] < 0) fallback else first.color;

    while (iter.next()) |layer| {
        const curves = try font.extractCurves(build.allocator, build.scratch(), layer.glyph_id);
        build.resetScratch();
        try build.owned_curves.append(build.allocator, curves);
        try build.colr_layers.append(build.allocator, .{
            .curves = build.owned_curves.items[build.owned_curves.items.len - 1],
            .paint = .{ .solid = if (layer.color[0] < 0) fallback else layer.color },
        });
    }

    const key = snail.recordKey.unhintedGlyph(0, glyph_id);
    try build.entries.append(build.allocator, .{
        .key = key,
        .curves = base_curves,
        .paint = .{ .solid = first_color },
        .extra_layers = build.colr_layers.items,
    });

    for (0..4) |row| for (0..8) |col| {
        const scale: f32 = 38 + @as(f32, @floatFromInt((row + col) % 3)) * 4;
        try build.shapes.append(build.allocator, .{
            .key = key,
            .local_transform = .{
                .xx = scale,
                .xy = 0,
                .tx = 24 + @as(f32, @floatFromInt(col)) * 76,
                .yx = 0,
                .yy = -scale,
                .ty = 72 + @as(f32, @floatFromInt(row)) * 82,
            },
        });
    };
}

fn addPaths(build: *SceneBuild) !void {
    const colors = [_][4]f32{
        .{ 0.17, 0.43, 0.86, 0.92 },
        .{ 0.90, 0.36, 0.22, 0.90 },
        .{ 0.16, 0.66, 0.42, 0.90 },
        .{ 0.72, 0.45, 0.86, 0.88 },
    };
    for (0..4) |row| for (0..6) |col| {
        const x = 24 + @as(f32, @floatFromInt(col)) * 96;
        const y = 24 + @as(f32, @floatFromInt(row)) * 76;
        var path = snail.Path.init(build.allocator);
        defer path.deinit();
        switch ((row + col) % 3) {
            0 => try path.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 48 }, 10),
            1 => try path.addEllipse(.{ .x = x, .y = y, .w = 72, .h = 48 }),
            else => {
                try path.moveTo(.{ .x = x, .y = y + 38 });
                try path.cubicTo(.{ .x = x + 16, .y = y - 8 }, .{ .x = x + 56, .y = y - 8 }, .{ .x = x + 72, .y = y + 38 });
                try path.quadTo(.{ .x = x + 36, .y = y + 68 }, .{ .x = x, .y = y + 38 });
                try path.close();
            },
        }
        var prepared = try path.prepare(build.allocator);
        defer prepared.deinit();
        const curves = try prepared.fillCurves(build.allocator, build.scratch());
        build.resetScratch();
        const key = snail.recordKey.RecordKey{ .namespace = snail.recordKey.ns.path_fill, .a = build.next_path_id };
        build.next_path_id += 1;
        try build.owned_curves.append(build.allocator, curves);
        try build.entries.append(build.allocator, .{
            .key = key,
            .curves = build.owned_curves.items[build.owned_curves.items.len - 1],
            .paint = prepared.paintForDesign(.{ .solid = colors[(row * 6 + col) % colors.len] }),
        });
        try build.shapes.append(build.allocator, .{
            .key = key,
            .local_transform = prepared.placedBy(.identity),
        });
    };
}
