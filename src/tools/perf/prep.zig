const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");
const common = @import("common.zig");
const fixtures = @import("fixtures.zig");

const cases = [_][]const u8{
    "shape-latin",
    "shape-multiscript",
    "shape-cff2-variable",
    "place-run",
    "curves-unhinted",
    "curves-cff",
    "curves-gvar",
    "curves-cff2",
    "truetype-prepare",
    "curves-truetype",
    "autohint-setup",
    "autohint-setup-nonlatin",
    "autohint-setup-cff2",
    "analyze-autohint",
    "analyze-autohint-cff2",
    "path-prepare",
    "path-pack",
    "atlas-build-text",
    "atlas-build-truetype",
    "atlas-build-autohint",
    "atlas-build-path",
    "atlas-build-mixed",
    "atlas-build-colr",
    "atlas-upload-plan",
    "emit-text",
    "emit-truetype",
    "emit-autohint",
    "emit-path",
    "emit-mixed",
    "emit-colr",
};

pub fn main(init: std.process.Init) !void {
    const raw_args = try init.minimal.args.toSlice(init.arena.allocator());
    const args = common.parseArgs(raw_args, &cases) catch |err| {
        common.printUsage(raw_args[0], &cases);
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };
    const allocator = std.heap.smp_allocator;

    if (std.mem.eql(u8, args.case, "shape-latin")) {
        try shapeCase(allocator, args, fixtures.paragraph, 2048);
    } else if (std.mem.eql(u8, args.case, "shape-multiscript")) {
        try shapeCase(allocator, args, fixtures.multiscript, 2048);
    } else if (std.mem.eql(u8, args.case, "shape-cff2-variable")) {
        var font = try formatFont(.cff2);
        try shapeFontCase(allocator, args, &font, fixtures.paragraph, 2048);
    } else if (std.mem.eql(u8, args.case, "place-run")) {
        try placeRunCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "curves-unhinted")) {
        try unhintedCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "curves-cff")) {
        var font = try formatFont(.cff);
        try curvesFontCase(allocator, args, &font, 32);
    } else if (std.mem.eql(u8, args.case, "curves-gvar")) {
        var font = try formatFont(.gvar);
        try curvesFontCase(allocator, args, &font, 32);
    } else if (std.mem.eql(u8, args.case, "curves-cff2")) {
        var font = try formatFont(.cff2);
        try curvesFontCase(allocator, args, &font, 32);
    } else if (std.mem.eql(u8, args.case, "truetype-prepare")) {
        try trueTypePrepareCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "curves-truetype")) {
        try trueTypeCurvesCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "autohint-setup")) {
        try autohintSetupCase(allocator, args, assets.noto_sans_regular);
    } else if (std.mem.eql(u8, args.case, "autohint-setup-nonlatin")) {
        try autohintSetupCase(allocator, args, assets.noto_sans_arabic);
    } else if (std.mem.eql(u8, args.case, "autohint-setup-cff2")) {
        var font = try formatFont(.cff2);
        try autohintSetupFontCase(allocator, args, &font);
    } else if (std.mem.eql(u8, args.case, "analyze-autohint")) {
        try autohintAnalyzeCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "analyze-autohint-cff2")) {
        var font = try formatFont(.cff2);
        try autohintAnalyzeFontCase(allocator, args, &font, 32);
    } else if (std.mem.eql(u8, args.case, "path-prepare")) {
        try pathPrepareCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "path-pack")) {
        try pathPackCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "atlas-build-text")) {
        try atlasBuildCase(allocator, args, .regular);
    } else if (std.mem.eql(u8, args.case, "atlas-build-truetype")) {
        try atlasBuildCase(allocator, args, .hinted);
    } else if (std.mem.eql(u8, args.case, "atlas-build-autohint")) {
        try atlasBuildCase(allocator, args, .autohint);
    } else if (std.mem.eql(u8, args.case, "atlas-build-path")) {
        try atlasBuildCase(allocator, args, .path);
    } else if (std.mem.eql(u8, args.case, "atlas-build-mixed")) {
        try atlasBuildCase(allocator, args, .mixed);
    } else if (std.mem.eql(u8, args.case, "atlas-build-colr")) {
        try atlasBuildCase(allocator, args, .colr);
    } else if (std.mem.eql(u8, args.case, "atlas-upload-plan")) {
        try uploadPlanCase(allocator, args);
    } else if (std.mem.eql(u8, args.case, "emit-text")) {
        try emitCase(allocator, args, .regular);
    } else if (std.mem.eql(u8, args.case, "emit-truetype")) {
        try emitCase(allocator, args, .hinted);
    } else if (std.mem.eql(u8, args.case, "emit-autohint")) {
        try emitCase(allocator, args, .autohint);
    } else if (std.mem.eql(u8, args.case, "emit-path")) {
        try emitCase(allocator, args, .path);
    } else if (std.mem.eql(u8, args.case, "emit-mixed")) {
        try emitCase(allocator, args, .mixed);
    } else if (std.mem.eql(u8, args.case, "emit-colr")) {
        try emitCase(allocator, args, .colr);
    } else unreachable;
}

const FormatFont = enum { cff, gvar, cff2 };
const benchmark_variations = [_]snail.font.Variation{
    .{ .tag = "wght".*, .value = 750 },
};

fn formatFont(format: FormatFont) !snail.Font {
    return switch (format) {
        .cff => snail.Font.init(assets.source_serif_cff),
        .gvar => snail.Font.initWithOptions(assets.noto_sans_mono, .{ .variations = &benchmark_variations }),
        .cff2 => snail.Font.initWithOptions(assets.source_serif_cff2_variable, .{ .variations = &benchmark_variations }),
    };
}

fn iterations(args: common.Args, default: usize) usize {
    return args.iterations orelse default;
}

fn reportPrep(
    case: []const u8,
    result: common.Result,
    work_per_iteration: usize,
    work_unit: []const u8,
    counters: []const common.Counter,
    checksum: u64,
) void {
    var name_buffer: [128]u8 = undefined;
    const benchmark = std.fmt.bufPrint(&name_buffer, "prep/{s}", .{case}) catch unreachable;
    common.report(benchmark, result, work_per_iteration, work_unit, counters, checksum);
}

const ShapeContext = struct {
    allocator: std.mem.Allocator,
    faces: *snail.Faces,
    text: []const u8,
    output_glyphs: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *ShapeContext) !void {
        var shaped = try snail.shape(self.allocator, self.faces, self.text, .{});
        defer shaped.deinit();
        self.output_glyphs = shaped.glyphs.len;
        common.hashValue(&self.checksum, shaped.glyphs.len);
        common.hashValue(&self.checksum, shaped.advanceX());
        if (shaped.glyphs.len > 0) common.hashValue(&self.checksum, shaped.glyphs[shaped.glyphs.len - 1].glyph_id);
    }
};

fn shapeCase(allocator: std.mem.Allocator, args: common.Args, text: []const u8, default_iterations: usize) !void {
    var fonts = try fixtures.FontSet.init(allocator);
    defer fonts.deinit();
    var context = ShapeContext{ .allocator = allocator, .faces = &fonts.faces, .text = text };
    const result = try common.measure(allocator, &context, iterations(args, default_iterations), args.samples);
    const codepoints = try std.unicode.utf8CountCodepoints(text);
    reportPrep(
        args.case,
        result,
        codepoints,
        "codepoint",
        &.{
            .{ .name = "input_bytes", .value = text.len },
            .{ .name = "output_glyphs", .value = context.output_glyphs },
            .{ .name = "font_faces", .value = fonts.fonts.len },
        },
        context.checksum,
    );
}

fn shapeFontCase(
    allocator: std.mem.Allocator,
    args: common.Args,
    font: *snail.Font,
    text: []const u8,
    default_iterations: usize,
) !void {
    var faces = try snail.Faces.build(allocator, &.{.{ .font = font }});
    defer faces.deinit();
    var context = ShapeContext{ .allocator = allocator, .faces = &faces, .text = text };
    const result = try common.measure(allocator, &context, iterations(args, default_iterations), args.samples);
    reportPrep(
        args.case,
        result,
        try std.unicode.utf8CountCodepoints(text),
        "codepoint",
        &.{
            .{ .name = "input_bytes", .value = text.len },
            .{ .name = "output_glyphs", .value = context.output_glyphs },
            .{ .name = "font_faces", .value = 1 },
        },
        context.checksum,
    );
}

const PlaceContext = struct {
    allocator: std.mem.Allocator,
    shaped: *const snail.ShapedText,
    faces: *const snail.Faces,
    output_shapes: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *PlaceContext) !void {
        const placed = try snail.placeRunAlloc(self.allocator, self.shaped, self.faces, .{
            .baseline = .{ .x = 18, .y = 38 },
            .em = 20,
            .color = .{ 0.1, 0.3, 0.7, 1.0 },
        });
        defer self.allocator.free(placed);
        self.output_shapes = placed.len;
        common.hashValue(&self.checksum, placed.len);
        if (placed.len > 0) common.hashValue(&self.checksum, placed[placed.len - 1].local_transform.tx);
    }
};

fn placeRunCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var fonts = try fixtures.FontSet.init(allocator);
    defer fonts.deinit();
    var shaped = try snail.shape(allocator, &fonts.faces, fixtures.paragraph, .{});
    defer shaped.deinit();
    var context = PlaceContext{ .allocator = allocator, .shaped = &shaped, .faces = &fonts.faces };
    const result = try common.measure(allocator, &context, iterations(args, 2048), args.samples);
    reportPrep(
        args.case,
        result,
        shaped.glyphs.len,
        "glyph",
        &.{
            .{ .name = "input_glyphs", .value = shaped.glyphs.len },
            .{ .name = "output_shapes", .value = context.output_shapes },
        },
        context.checksum,
    );
}

fn asciiGlyphs(font: *const snail.Font, out: *[94]u16) !void {
    for (out, 0..) |*glyph, i| glyph.* = try font.glyphIndex(@intCast(33 + i));
}

fn consumeCurves(hash: *u64, curves: *const snail.GlyphCurves) void {
    common.hashValue(hash, curves.curve_count);
    common.hashValue(hash, curves.h_band_count);
    common.hashValue(hash, curves.curve_bytes.len);
    common.hashValue(hash, curves.band_bytes.len);
    if (curves.curve_bytes.len > 0) common.hashValue(hash, curves.curve_bytes[curves.curve_bytes.len / 2]);
}

const UnhintedContext = struct {
    allocator: std.mem.Allocator,
    font: *snail.Font,
    glyphs: *const [94]u16,
    scratch: *std.heap.ArenaAllocator,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *UnhintedContext) !void {
        for (self.glyphs) |glyph_id| {
            var curves = try self.font.extractCurves(self.allocator, self.scratch.allocator(), glyph_id);
            consumeCurves(&self.checksum, &curves);
            curves.deinit();
            _ = self.scratch.reset(.retain_capacity);
        }
    }
};

fn unhintedCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var font = try snail.Font.init(assets.noto_sans_regular);
    return curvesFontCase(allocator, args, &font, 96);
}

fn curvesFontCase(
    allocator: std.mem.Allocator,
    args: common.Args,
    font: *snail.Font,
    default_iterations: usize,
) !void {
    var glyphs: [94]u16 = undefined;
    try asciiGlyphs(font, &glyphs);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var context = UnhintedContext{ .allocator = allocator, .font = font, .glyphs = &glyphs, .scratch = &scratch };
    const result = try common.measure(allocator, &context, iterations(args, default_iterations), args.samples);
    reportPrep(args.case, result, glyphs.len, "glyph", &.{.{ .name = "glyphs", .value = glyphs.len }}, context.checksum);
}

const TrueTypePrepareContext = struct {
    allocator: std.mem.Allocator,
    font: *const snail.Font,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *TrueTypePrepareContext) !void {
        var vm = try snail.HintVm.init(self.allocator, self.font);
        defer vm.deinit();
        var prepared = try vm.prepare(snail.HintPpem.uniform(20 * 64));
        defer prepared.deinit();
        common.hashValue(&self.checksum, @as(u32, 20 * 64));
    }
};

fn trueTypePrepareCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var font = try snail.Font.init(assets.noto_sans_regular);
    var context = TrueTypePrepareContext{ .allocator = allocator, .font = &font };
    const result = try common.measure(allocator, &context, iterations(args, 512), args.samples);
    reportPrep(args.case, result, 1, "font_ppem_context", &.{.{ .name = "ppem", .value = 20 }}, context.checksum);
}

const TrueTypeCurvesContext = struct {
    allocator: std.mem.Allocator,
    vm: *snail.HintVm,
    prepared: *const snail.HintVm.Prepared,
    glyphs: *const [94]u16,
    scratch: *std.heap.ArenaAllocator,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *TrueTypeCurvesContext) !void {
        for (self.glyphs) |glyph_id| {
            var curves = try self.vm.hintGlyph(self.allocator, self.scratch.allocator(), self.prepared, glyph_id);
            consumeCurves(&self.checksum, &curves);
            curves.deinit();
            _ = self.scratch.reset(.retain_capacity);
        }
    }
};

fn trueTypeCurvesCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var font = try snail.Font.init(assets.noto_sans_regular);
    var glyphs: [94]u16 = undefined;
    try asciiGlyphs(&font, &glyphs);
    var vm = try snail.HintVm.init(allocator, &font);
    defer vm.deinit();
    var prepared = try vm.prepare(snail.HintPpem.uniform(20 * 64));
    defer prepared.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var context = TrueTypeCurvesContext{
        .allocator = allocator,
        .vm = &vm,
        .prepared = &prepared,
        .glyphs = &glyphs,
        .scratch = &scratch,
    };
    const result = try common.measure(allocator, &context, iterations(args, 32), args.samples);
    reportPrep(
        args.case,
        result,
        glyphs.len,
        "glyph",
        &.{ .{ .name = "glyphs", .value = glyphs.len }, .{ .name = "ppem", .value = 20 } },
        context.checksum,
    );
}

const AutohintSetupContext = struct {
    allocator: std.mem.Allocator,
    font_data: []const u8,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *AutohintSetupContext) !void {
        var analyzer = try snail.autohint.AutohintAnalyzer.init(self.allocator, self.font_data);
        defer analyzer.deinit();
        common.hashValue(&self.checksum, self.font_data.len);
    }
};

fn autohintSetupCase(allocator: std.mem.Allocator, args: common.Args, font_data: []const u8) !void {
    var context = AutohintSetupContext{ .allocator = allocator, .font_data = font_data };
    const result = try common.measure(allocator, &context, iterations(args, 32), args.samples);
    reportPrep(
        args.case,
        result,
        1,
        "font_analyzer",
        &.{.{ .name = "font_bytes", .value = font_data.len }},
        context.checksum,
    );
}

const AutohintFontSetupContext = struct {
    allocator: std.mem.Allocator,
    font: *const snail.Font,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *AutohintFontSetupContext) !void {
        var analyzer = try snail.autohint.AutohintAnalyzer.initFont(self.allocator, self.font);
        defer analyzer.deinit();
        const features = analyzer.fontFeatures();
        common.hashValue(&self.checksum, features.std_x);
        common.hashValue(&self.checksum, features.blues.len);
    }
};

fn autohintSetupFontCase(allocator: std.mem.Allocator, args: common.Args, font: *const snail.Font) !void {
    var context = AutohintFontSetupContext{ .allocator = allocator, .font = font };
    const result = try common.measure(allocator, &context, iterations(args, 32), args.samples);
    reportPrep(
        args.case,
        result,
        1,
        "font_analyzer",
        &.{.{ .name = "font_bytes", .value = font.inner.data.len }},
        context.checksum,
    );
}

const AutohintAnalyzeContext = struct {
    analyzer: *snail.autohint.AutohintAnalyzer,
    glyphs: *const [94]u16,
    scratch: *std.heap.ArenaAllocator,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *AutohintAnalyzeContext) !void {
        for (self.glyphs) |glyph_id| {
            const a = self.scratch.allocator();
            const x = try a.alloc(snail.autohint.FeatureEdge, snail.autohint.warp.max_knots);
            const y = try a.alloc(snail.autohint.FeatureEdge, snail.autohint.warp.max_knots);
            const analysis = try self.analyzer.analyzeGlyph(a, glyph_id, x, y);
            common.hashValue(&self.checksum, analysis.x.len);
            common.hashValue(&self.checksum, analysis.y.len);
            common.hashValue(&self.checksum, analysis.left);
            _ = self.scratch.reset(.retain_capacity);
        }
    }
};

fn autohintAnalyzeCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var font = try snail.Font.init(assets.noto_sans_regular);
    return autohintAnalyzeFontCase(allocator, args, &font, 96);
}

fn autohintAnalyzeFontCase(
    allocator: std.mem.Allocator,
    args: common.Args,
    font: *snail.Font,
    default_iterations: usize,
) !void {
    var glyphs: [94]u16 = undefined;
    try asciiGlyphs(font, &glyphs);
    var analyzer = try snail.autohint.AutohintAnalyzer.initFont(allocator, font);
    defer analyzer.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var context = AutohintAnalyzeContext{ .analyzer = &analyzer, .glyphs = &glyphs, .scratch = &scratch };
    const result = try common.measure(allocator, &context, iterations(args, default_iterations), args.samples);
    reportPrep(args.case, result, glyphs.len, "glyph", &.{.{ .name = "glyphs", .value = glyphs.len }}, context.checksum);
}

const PathPrepareContext = struct {
    allocator: std.mem.Allocator,
    path: *const snail.Path,
    prepared_curves: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *PathPrepareContext) !void {
        var prepared = try self.path.prepare(self.allocator);
        defer prepared.deinit();
        self.prepared_curves = prepared.design.curves.items.len;
        common.hashValue(&self.checksum, self.prepared_curves);
    }
};

fn pathPrepareCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var path = try fixtures.benchmarkPath(allocator);
    defer path.deinit();
    var context = PathPrepareContext{ .allocator = allocator, .path = &path };
    const result = try common.measure(allocator, &context, iterations(args, 2048), args.samples);
    reportPrep(
        args.case,
        result,
        1,
        "path",
        &.{
            .{ .name = "source_curves", .value = path.curves.items.len },
            .{ .name = "prepared_curves", .value = context.prepared_curves },
        },
        context.checksum,
    );
}

const PathPackContext = struct {
    allocator: std.mem.Allocator,
    prepared: *const snail.PreparedPath,
    scratch: *std.heap.ArenaAllocator,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *PathPackContext) !void {
        var curves = try self.prepared.fillCurves(self.allocator, self.scratch.allocator());
        consumeCurves(&self.checksum, &curves);
        curves.deinit();
        _ = self.scratch.reset(.retain_capacity);
    }
};

fn pathPackCase(allocator: std.mem.Allocator, args: common.Args) !void {
    var path = try fixtures.benchmarkPath(allocator);
    defer path.deinit();
    var prepared = try path.prepare(allocator);
    defer prepared.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var context = PathPackContext{ .allocator = allocator, .prepared = &prepared, .scratch = &scratch };
    const result = try common.measure(allocator, &context, iterations(args, 2048), args.samples);
    reportPrep(
        args.case,
        result,
        prepared.design.curves.items.len,
        "curve",
        &.{.{ .name = "prepared_curves", .value = prepared.design.curves.items.len }},
        context.checksum,
    );
}

fn initPool(allocator: std.mem.Allocator) !*snail.PagePool {
    return snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
}

const AtlasBuildContext = struct {
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    entries: []const snail.AtlasEntry,
    output_pages: usize = 0,
    output_records: usize = 0,
    output_paint_records: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *AtlasBuildContext) !void {
        var atlas = try snail.Atlas.from(self.allocator, self.pool, self.entries);
        defer atlas.deinit();
        self.output_pages = atlas.pageCount();
        self.output_records = atlas.recordCount();
        self.output_paint_records = atlas.paintRecordCount();
        common.hashValue(&self.checksum, self.output_pages);
        common.hashValue(&self.checksum, self.output_records);
        common.hashValue(&self.checksum, self.output_paint_records);
    }
};

fn atlasBuildCase(allocator: std.mem.Allocator, args: common.Args, kind: fixtures.SceneKind) !void {
    const pool = try initPool(allocator);
    defer pool.deinit();
    var scene = try fixtures.buildScene(allocator, pool, kind);
    defer scene.deinit();
    var context = AtlasBuildContext{ .allocator = allocator, .pool = pool, .entries = scene.entries() };
    const result = try common.measure(allocator, &context, iterations(args, 512), args.samples);
    reportPrep(
        args.case,
        result,
        scene.entries().len,
        "atlas_entry",
        &.{
            .{ .name = "input_entries", .value = scene.entries().len },
            .{ .name = "output_records", .value = context.output_records },
            .{ .name = "output_paint_records", .value = context.output_paint_records },
            .{ .name = "output_pages", .value = context.output_pages },
            .{ .name = "colr_layers", .value = scene.colrLayerCount() },
        },
        context.checksum,
    );
}

fn uploadOptions() snail.atlas_upload.Options {
    return .{
        .max_bindings = 1,
        .layer_info_height = 64,
        .max_images = 0,
        .max_image_width = 1,
        .max_image_height = 1,
    };
}

const UploadPlanContext = struct {
    planner: *snail.OwnedAtlasUploadPlanner,
    atlas: *const snail.Atlas,
    region_count: usize = 0,
    upload_bytes: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *UploadPlanContext) !void {
        self.planner.invalidateUploads();
        const plan = try self.planner.plan(self.atlas);
        defer std.debug.assert(self.planner.release(plan.binding));
        self.region_count = plan.regions.len;
        self.upload_bytes = 0;
        for (plan.regions) |region| self.upload_bytes += region.src.len;
        common.hashValue(&self.checksum, plan.binding.generation);
        common.hashValue(&self.checksum, self.region_count);
        common.hashValue(&self.checksum, self.upload_bytes);
    }
};

fn uploadPlanCase(allocator: std.mem.Allocator, args: common.Args) !void {
    const pool = try initPool(allocator);
    defer pool.deinit();
    var scene = try fixtures.buildScene(allocator, pool, .mixed);
    defer scene.deinit();
    var planner = try snail.OwnedAtlasUploadPlanner.init(allocator, pool, uploadOptions());
    defer planner.deinit();
    var context = UploadPlanContext{ .planner = &planner, .atlas = &scene.atlas };
    const result = try common.measure(allocator, &context, iterations(args, 2048), args.samples);
    reportPrep(
        args.case,
        result,
        1,
        "atlas",
        &.{
            .{ .name = "records", .value = scene.atlas.recordCount() },
            .{ .name = "pages", .value = scene.atlas.pageCount() },
            .{ .name = "regions", .value = context.region_count },
            .{ .name = "upload_bytes", .value = context.upload_bytes },
        },
        context.checksum,
    );
}

const EmitContext = struct {
    pool: *snail.PagePool,
    atlas: *const snail.Atlas,
    shapes: []const snail.Shape,
    words: []u32,
    segments: []snail.render.records.DrawSegment,
    output_words: usize = 0,
    output_segments: usize = 0,
    checksum: u64 = 14695981039346656037,

    pub fn run(self: *EmitContext) !void {
        var word_len: usize = 0;
        var segment_len: usize = 0;
        _ = try snail.emit.emit(
            self.words,
            self.segments,
            &word_len,
            &segment_len,
            .{ .pool = self.pool },
            self.atlas,
            self.shapes,
            .identity,
            .{ 1, 1, 1, 1 },
        );
        self.output_words = word_len;
        self.output_segments = segment_len;
        std.mem.doNotOptimizeAway(self.words.ptr);
        std.mem.doNotOptimizeAway(self.segments.ptr);
        common.hashValue(&self.checksum, word_len);
        common.hashValue(&self.checksum, segment_len);
        if (word_len > 0) common.hashValue(&self.checksum, self.words[word_len - 1]);
    }
};

fn emitCase(allocator: std.mem.Allocator, args: common.Args, kind: fixtures.SceneKind) !void {
    const pool = try initPool(allocator);
    defer pool.deinit();
    var scene = try fixtures.buildScene(allocator, pool, kind);
    defer scene.deinit();
    const words = try allocator.alloc(u32, snail.emit.wordBudget(scene.shapes().len));
    defer allocator.free(words);
    const segments = try allocator.alloc(snail.render.records.DrawSegment, @max(snail.emit.segmentBudget(scene.shapes().len), 1));
    defer allocator.free(segments);
    var context = EmitContext{
        .pool = pool,
        .atlas = &scene.atlas,
        .shapes = scene.shapes(),
        .words = words,
        .segments = segments,
    };
    const result = try common.measure(allocator, &context, iterations(args, 1024), args.samples);
    reportPrep(
        args.case,
        result,
        scene.shapes().len,
        "shape",
        &.{
            .{ .name = "input_shapes", .value = scene.shapes().len },
            .{ .name = "output_instances", .value = context.output_words / snail.render.records.WORDS_PER_INSTANCE },
            .{ .name = "output_bytes", .value = context.output_words * @sizeOf(u32) },
            .{ .name = "segments", .value = context.output_segments },
        },
        context.checksum,
    );
}
