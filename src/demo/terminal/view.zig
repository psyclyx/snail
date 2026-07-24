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
            .regular = try snail.Font.init(assets.dejavu_sans_mono),
            .bold = try snail.Font.init(assets.noto_sans_bold),
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
    cell_width: f32 = 10.5,
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
    pool: *snail.PagePool,
    atlas: snail.Atlas,
    metrics: Metrics = .{},

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
            .pool = pool,
            .atlas = atlas,
        };
    }

    pub fn deinit(self: *View) void {
        self.atlas.deinit();
        self.pool.deinit();
        self.faces.deinit();
        self.allocator.destroy(self.fonts);
        self.* = undefined;
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
        var runs: std.ArrayList(PreparedRun) = .empty;
        defer {
            for (runs.items) |*run| run.deinit();
            runs.deinit(scratch);
        }

        for (0..screen_mod.row_count) |row_index| {
            try self.prepareRowRuns(scratch, &runs, screen, row_index);
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
            try runs.append(scratch, .{
                .shaped = shaped,
                .cells = try cells.toOwnedSlice(scratch),
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
            .snap = .grid,
            .world_to_pixel = world_to_pixel,
            // Layer fanout keeps dynamic COLRv0 emoji in ordinary geometry
            // pages, avoiding immutable paint-side-data binding growth.
            .colr = true,
        };
    }
};

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
    var second = try view.buildPicture(
        std.testing.allocator,
        scratch_arena.allocator(),
        &screen,
        .identity,
    );
    defer second.picture.deinit();
    try std.testing.expectEqual(@as(u32, 0), second.records_added);
}

test "view resolves emoji and script fallback into distinct font keys" {
    var view = try View.init(std.testing.allocator);
    defer view.deinit();

    var screen: Screen = .{};
    _ = screen.put(0, 0, "न", 1, .normal);
    _ = screen.put(0, 2, "🌍", 2, .accent);

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
