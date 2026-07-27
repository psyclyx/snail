//! Snail-backed view of the terminal cell model.
//!
//! The screen decides text, style, columns, wrapping, and wide-cell policy.
//! This layer turns visible style runs into:
//!
//!   cells -> UTF-8 run + source ranges -> shape -> batch record -> place
//!
//! It intentionally rebuilds the cheap shaped/picture values when the model
//! changes while retaining `Faces` and the append-only glyph `Atlas`.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");
const demo_support = @import("support");
const screen_mod = @import("screen.zig");

const Allocator = std.mem.Allocator;
const Picture = demo_support.Picture;
const Screen = screen_mod.Screen;
const Style = screen_mod.Style;

const font_id = struct {
    const regular: u32 = 1;
    const bold: u32 = 2;
    const emoji: u32 = 10;
    const symbols: u32 = 11;
    const devanagari: u32 = 12;
    const arabic: u32 = 13;
    const thai: u32 = 14;
};

const bold_coordinates = [_]snail.FontVariation{
    .{ .tag = "wght".*, .value = 700 },
};
const mono_advance: f32 = 1233.0 / 2048.0;
const line_height_ratio: f32 = 26.0 / 18.0;

const hint_fade: snail.autohint.Fade = .{
    .ppem_range = .{ .start_px = 16, .full_px = 26 },
};
const auto_y_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .none,
        .stem_width = .natural,
        .positioning = .independent,
        .registration = .none,
    },
    .y = .{
        .@"align" = .blue_zones,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0 } },
        .overshoot = .{ .suppress_below_px = 0.5 },
    },
    .fade = hint_fade,
};
const auto_df_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .grid,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.2, .max_px = 1.6 } },
        .positioning = .independent,
        .registration = .left_round_outline,
    },
    .y = .{
        .@"align" = .blue_zones,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.2, .max_px = 1.6 } },
        .overshoot = .preserve,
    },
    .fade = hint_fade,
};

pub const Hinting = enum {
    unhinted,
    auto_y,
    auto_df,
    tt,

    pub fn next(self: Hinting) Hinting {
        return switch (self) {
            .unhinted => .auto_y,
            .auto_y => .auto_df,
            .auto_df => .tt,
            .tt => .unhinted,
        };
    }

    pub fn label(self: Hinting) []const u8 {
        return switch (self) {
            .unhinted => "unhinted",
            .auto_y => "auto-y",
            .auto_df => "auto-df",
            .tt => "truetype",
        };
    }
};

const Fonts = struct {
    regular: snail.Font,
    bold: snail.Font,
    emoji: snail.Font,
    symbols: snail.Font,
    devanagari: snail.Font,
    arabic: snail.Font,
    thai: snail.Font,

    fn init() !Fonts {
        return .{
            // The primary static TrueType face exercises every hint path.
            .regular = try snail.Font.init(assets.dejavu_sans_mono),
            // A selected variable monospace instance exercises style
            // selection and a distinct atlas identity without proportional
            // outlines spilling across host cells.
            .bold = try snail.Font.initWithOptions(assets.noto_sans_mono, .{
                .variations = &bold_coordinates,
            }),
            .emoji = try snail.Font.init(assets.twemoji_mozilla),
            .symbols = try snail.Font.init(assets.noto_sans_symbols),
            .devanagari = try snail.Font.init(assets.noto_sans_devanagari),
            .arabic = try snail.Font.init(assets.noto_sans_arabic),
            .thai = try snail.Font.init(assets.noto_sans_thai),
        };
    }
};

const PreparedRun = struct {
    shaped: snail.ShapedText,
    cells: []const snail.Cell,
    baseline_y: f32,

    fn deinit(self: *PreparedRun) void {
        self.shaped.deinit();
    }
};

pub const Metrics = struct {
    origin_x: f32 = 42,
    first_baseline_y: f32 = 46,
    em: f32 = 18,
    cell_width: f32 = 18 * mono_advance,
    line_height: f32 = 26,
};

pub const BuildResult = struct {
    picture: Picture,
    records_added: u32,
};

pub const View = struct {
    allocator: Allocator,
    fonts: *Fonts,
    faces: snail.Faces,
    analyzer: snail.autohint.AutohintAnalyzer,
    tt_vm: snail.TtHintVm,
    pool: *snail.PagePool,
    atlas: snail.Atlas,
    metrics: Metrics = .{},
    hinting: Hinting = .unhinted,

    pub fn init(allocator: Allocator) !View {
        const fonts = try allocator.create(Fonts);
        errdefer allocator.destroy(fonts);
        fonts.* = try Fonts.init();

        var faces = try snail.Faces.build(allocator, &.{
            .{ .font = &fonts.regular, .font_id = font_id.regular },
            .{ .font = &fonts.bold, .font_id = font_id.bold, .weight = .bold },
            // Global fallbacks are ordered. Emoji-presentation clusters prefer
            // this chain before the styled face; other clusters try style first.
            .{ .font = &fonts.emoji, .font_id = font_id.emoji, .fallback = true },
            .{ .font = &fonts.symbols, .font_id = font_id.symbols, .fallback = true },
            .{ .font = &fonts.devanagari, .font_id = font_id.devanagari, .fallback = true },
            .{ .font = &fonts.arabic, .font_id = font_id.arabic, .fallback = true },
            .{ .font = &fonts.thai, .font_id = font_id.thai, .fallback = true },
        });
        errdefer faces.deinit();

        var analyzer = try snail.autohint.AutohintAnalyzer.initFont(
            allocator,
            &fonts.regular,
        );
        errdefer analyzer.deinit();

        var tt_vm = try snail.TtHintVm.init(allocator, &fonts.regular);
        errdefer tt_vm.deinit();

        const pool = try snail.PagePool.init(allocator, .{
            .max_layers = 16,
            .curve_words_per_page = 1 << 18,
            .band_words_per_page = 1 << 15,
        });
        errdefer pool.deinit();

        var atlas = try snail.Atlas.init(allocator, pool);
        errdefer atlas.deinit();
        return .{
            .allocator = allocator,
            .fonts = fonts,
            .faces = faces,
            .analyzer = analyzer,
            .tt_vm = tt_vm,
            .pool = pool,
            .atlas = atlas,
        };
    }

    pub fn deinit(self: *View) void {
        self.atlas.deinit();
        self.pool.deinit();
        self.tt_vm.deinit();
        self.analyzer.deinit();
        self.faces.deinit();
        self.allocator.destroy(self.fonts);
        self.* = undefined;
    }

    /// Change terminal metrics without touching ppem-independent glyph
    /// residency. Very large sizes naturally show fewer cells in the fixed
    /// viewport; the bounds only prevent degenerate demo input.
    pub fn setTextSize(self: *View, requested_em: f32) bool {
        const em = std.math.clamp(requested_em, 6, 96);
        if (em == self.metrics.em) return false;
        self.metrics.em = em;
        self.metrics.cell_width = em * mono_advance;
        self.metrics.line_height = em * line_height_ratio;
        self.metrics.first_baseline_y = em + 28;
        return true;
    }

    pub fn cycleHinting(self: *View) Hinting {
        self.hinting = self.hinting.next();
        return self.hinting;
    }

    /// Build the visible picture. `scratch` owns shaping values only for this
    /// call; atlas storage always uses the view's long-lived allocator.
    pub fn buildPicture(
        self: *View,
        picture_allocator: Allocator,
        scratch: Allocator,
        screen: *const Screen,
        world_to_pixel: snail.Transform2D,
    ) !BuildResult {
        const ppem_26_6 = try self.devicePpem(world_to_pixel);
        const primary_mode = self.primaryHintMode(ppem_26_6);
        var runs: std.ArrayList(PreparedRun) = .empty;
        defer {
            for (runs.items) |*run| run.deinit();
            runs.deinit(scratch);
        }

        for (0..screen_mod.row_count) |row_index| {
            try self.prepareRowRuns(
                scratch,
                &runs,
                screen,
                row_index,
                primary_mode,
            );
        }

        const run_ptrs = try scratch.alloc(*const snail.ShapedText, runs.items.len);
        for (runs.items, run_ptrs) |*run, *out| out.* = &run.shaped;

        const before = self.atlas.recordCount();
        try snail.recordUnhintedRuns(
            &self.atlas,
            self.allocator,
            &self.faces,
            run_ptrs,
            .{ .colr = .layers },
        );
        switch (self.hinting) {
            .unhinted => {},
            .auto_y, .auto_df => try snail.recordAutohintRuns(
                &self.atlas,
                self.allocator,
                &self.analyzer,
                font_id.regular,
                run_ptrs,
            ),
            .tt => {
                var prepared = try self.tt_vm.prepare(
                    snail.TtHintPpem.uniform(ppem_26_6),
                );
                defer prepared.deinit();
                try snail.recordTtHintRuns(
                    &self.atlas,
                    self.allocator,
                    &self.tt_vm,
                    &prepared,
                    font_id.regular,
                    run_ptrs,
                );
            },
        }
        const after = self.atlas.recordCount();

        var shape_count: usize = 0;
        for (runs.items) |*run| {
            const cell_placement = self.placement(run.baseline_y, world_to_pixel);
            const count = try snail.placedCellRunShapeCount(
                &run.shaped,
                &self.faces,
                run.cells,
                cell_placement,
            );
            shape_count = try std.math.add(usize, shape_count, count);
        }

        const shapes = try picture_allocator.alloc(snail.Shape, shape_count);
        errdefer picture_allocator.free(shapes);
        var cursor: usize = 0;
        for (runs.items) |*run| {
            const placed = try snail.placeCellRun(
                shapes[cursor..],
                &run.shaped,
                &self.faces,
                run.cells,
                self.placement(run.baseline_y, world_to_pixel),
            );
            cursor += placed.len;
        }
        std.debug.assert(cursor == shapes.len);

        return .{
            .picture = Picture.fromOwnedSlice(picture_allocator, shapes),
            .records_added = after - before,
        };
    }

    fn prepareRowRuns(
        self: *View,
        scratch: Allocator,
        runs: *std.ArrayList(PreparedRun),
        screen: *const Screen,
        row_index: usize,
        primary_mode: snail.HintMode,
    ) !void {
        const row = screen.row(row_index);
        var column: usize = 0;
        while (column < row.len) {
            while (column < row.len and !row[column].isLead()) column += 1;
            if (column == row.len) break;

            const style = row[column].style;
            var text_bytes: std.ArrayList(u8) = .empty;
            defer text_bytes.deinit(scratch);
            var cells: std.ArrayList(snail.Cell) = .empty;
            errdefer cells.deinit(scratch);

            while (column < row.len) {
                const model_cell = row[column];
                if (!model_cell.isLead() or model_cell.style != style) break;
                const source_start = text_bytes.items.len;
                try text_bytes.appendSlice(scratch, model_cell.text);
                try cells.append(scratch, .{
                    .source = .{
                        .start = @intCast(source_start),
                        .end = @intCast(text_bytes.items.len),
                    },
                    .column = @intCast(column),
                    .color = styleColor(style),
                });
                column += model_cell.width;
            }

            const features = terminalFeatures();
            var shaped = try snail.shape(scratch, &self.faces, text_bytes.items, .{
                .style = styleFont(style),
                .direction = .ltr,
                .script = null,
                .language = null,
                .features = &features,
            });
            errdefer shaped.deinit();
            const owned_cells = try cells.toOwnedSlice(scratch);
            assignPrimaryHintMode(owned_cells, &shaped, primary_mode);
            try runs.append(scratch, .{
                .shaped = shaped,
                .cells = owned_cells,
                .baseline_y = self.metrics.first_baseline_y +
                    @as(f32, @floatFromInt(row_index)) * self.metrics.line_height,
            });
        }
    }

    fn placement(self: *const View, baseline_y: f32, world_to_pixel: snail.Transform2D) snail.CellRunPlacement {
        return .{
            .baseline = .{ .x = self.metrics.origin_x, .y = baseline_y },
            .cell_width = self.metrics.cell_width,
            .em = self.metrics.em,
            .snap = switch (self.hinting) {
                .unhinted, .auto_y => .grid,
                .auto_df, .tt => .glyph_origins,
            },
            .world_to_pixel = world_to_pixel,
            // Layer fanout keeps dynamic COLRv0 emoji in ordinary geometry
            // pages, avoiding immutable paint-side-data binding growth.
            .colr = true,
        };
    }

    fn primaryHintMode(self: *const View, ppem_26_6: u32) snail.HintMode {
        return switch (self.hinting) {
            .unhinted => .unhinted,
            .auto_y => .{ .autohint = auto_y_policy },
            .auto_df => .{ .autohint = auto_df_policy },
            .tt => .{ .tt_hint = .{ .ppem_26_6 = ppem_26_6 } },
        };
    }

    fn devicePpem(self: *const View, world_to_pixel: snail.Transform2D) !u32 {
        const ppem = @abs(world_to_pixel.yy) * self.metrics.em * 64;
        if (!std.math.isFinite(ppem) or ppem < 1 or
            ppem > @as(f32, @floatFromInt(snail.TtHintPpem.max_26_6)))
        {
            return error.InvalidPpem;
        }
        return @intFromFloat(@round(ppem));
    }
};

fn assignPrimaryHintMode(
    cells: []snail.Cell,
    shaped: *const snail.ShapedText,
    primary_mode: snail.HintMode,
) void {
    for (cells) |*cell| {
        var has_glyph = false;
        var primary_only = true;
        for (shaped.glyphs) |glyph| {
            if (glyph.source_start < cell.source.start or
                glyph.source_start >= cell.source.end)
            {
                continue;
            }
            has_glyph = true;
            primary_only = primary_only and glyph.font_id == font_id.regular;
        }
        cell.mode = if (has_glyph and primary_only) primary_mode else .unhinted;
    }
}

fn terminalFeatures() [2]snail.OpenTypeFeature {
    // A host that wants programming ligatures can omit these and still map the
    // resulting multi-cell cluster through source ranges. This demo chooses the
    // conventional strict-cell presentation.
    return .{
        .{ .tag = "liga".*, .value = 0 },
        .{ .tag = "calt".*, .value = 0 },
    };
}

fn styleFont(style: Style) snail.FontStyle {
    return switch (style) {
        .heading, .prompt => .{ .weight = .bold },
        else => .{},
    };
}

fn styleColor(style: Style) [4]f32 {
    const srgb: [4]f32 = switch (style) {
        .normal => .{ 0.82, 0.85, 0.90, 1 },
        .dim => .{ 0.43, 0.49, 0.58, 1 },
        .heading => .{ 0.48, 0.82, 0.98, 1 },
        .prompt => .{ 0.45, 0.90, 0.61, 1 },
        .command => .{ 0.92, 0.94, 0.97, 1 },
        .success => .{ 0.45, 0.90, 0.61, 1 },
        .warning => .{ 0.98, 0.76, 0.36, 1 },
        .accent => .{ 0.83, 0.58, 0.98, 1 },
    };
    return snail.color.srgbToLinearColor(srgb);
}

test "view retains atlas records across screen rebuilds" {
    var view = try View.init(std.testing.allocator);
    defer view.deinit();

    var screen: Screen = .{};
    _ = screen.putAscii(0, 0, "abc", .normal);

    var scratch_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch_arena.deinit();
    var first = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer first.picture.deinit();
    try std.testing.expect(first.records_added > 0);

    _ = scratch_arena.reset(.retain_capacity);
    try std.testing.expect(view.setTextSize(20));
    var second = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer second.picture.deinit();
    try std.testing.expectEqual(@as(u32, 0), second.records_added);
    try std.testing.expectEqual(@as(f32, 20 * mono_advance), view.metrics.cell_width);
    try std.testing.expect(view.setTextSize(500));
    try std.testing.expectEqual(@as(f32, 96), view.metrics.em);
    try std.testing.expect(view.setTextSize(1));
    try std.testing.expectEqual(@as(f32, 6), view.metrics.em);
}

test "view resolves emoji and script fallback into distinct font keys" {
    var view = try View.init(std.testing.allocator);
    defer view.deinit();

    var screen: Screen = .{};
    _ = screen.put(0, 0, "न", 1, .normal);
    _ = screen.put(0, 2, "🌍", 2, .accent);
    try std.testing.expectEqual(Hinting.auto_y, view.cycleHinting());

    var scratch_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch_arena.deinit();
    var result = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer result.picture.deinit();

    var saw_devanagari = false;
    var saw_emoji = false;
    for (result.picture.shapes) |shape| {
        saw_devanagari = saw_devanagari or shape.key.a == font_id.devanagari;
        saw_emoji = saw_emoji or shape.key.a == font_id.emoji;
    }
    try std.testing.expect(saw_devanagari);
    try std.testing.expect(saw_emoji);
}

test "view cycles matching autohint and TrueType record namespaces" {
    var view = try View.init(std.testing.allocator);
    defer view.deinit();

    var screen: Screen = .{};
    _ = screen.putAscii(0, 0, "hint me", .normal);
    var scratch_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch_arena.deinit();

    var unhinted = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer unhinted.picture.deinit();

    _ = scratch_arena.reset(.retain_capacity);
    try std.testing.expectEqual(Hinting.auto_y, view.cycleHinting());
    var auto_y = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer auto_y.picture.deinit();
    try std.testing.expect(auto_y.records_added > 0);

    _ = scratch_arena.reset(.retain_capacity);
    try std.testing.expectEqual(Hinting.auto_df, view.cycleHinting());
    var auto_df = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer auto_df.picture.deinit();
    try std.testing.expectEqual(@as(u32, 0), auto_df.records_added);

    _ = scratch_arena.reset(.retain_capacity);
    try std.testing.expectEqual(Hinting.tt, view.cycleHinting());
    var tt = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer tt.picture.deinit();
    try std.testing.expect(tt.records_added > 0);
}
