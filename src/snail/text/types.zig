const std = @import("std");

const config_mod = @import("config.zig");
const hint_context_mod = @import("hint_context.zig");
const paint_mod = @import("../paint.zig");
const target_mod = @import("../target.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const FaceIndex = config_mod.FaceIndex;
const FontStyle = config_mod.FontStyle;
const FontConfig = config_mod.FontConfig;
const Paint = paint_mod.Paint;
const PreparedHintRun = hint_context_mod.PreparedHintRun;
const SnapRule = target_mod.SnapRule;
const Vec2 = vec.Vec2;

pub const TextPlacement = struct {
    baseline: Vec2,
    em: f32,
};

/// A unit of text to append to a `TextBlobBuilder`. The `source` union
/// selects between an unhinted shaped-text slice and a slice of hinted
/// glyphs from a `PreparedHintRun`. In both cases the slice is
/// caller-owned; the first glyph in the slice lands at `placement.baseline`
/// (any shaper offset on the first glyph is implicit — adjust `baseline`
/// to account for it).
pub const TextAppend = struct {
    source: union(enum) {
        shaped: []const ShapedText.Glyph,
        hinted: []const PreparedHintRun.Glyph,
    },
    placement: TextPlacement,
    fill: Paint,
};

pub const TextAppendResult = struct {
    advance: Vec2,
    missing: bool,
};

pub const TextBatchAppend = struct {
    glyphs: []const ShapedText.Glyph,
    placement: TextPlacement,
    color: [4]f32,
};

pub const CellMetricsOptions = struct {
    style: FontStyle = .{},
    em: f32,
};

pub const CellMetrics = struct {
    cell_width: f32,
    line_height: f32,
};

pub const TextCellGridOptions = struct {
    style: FontStyle = .{},
    origin: Vec2 = .zero,
    em: f32,
    pixel_step: Vec2 = .{ .x = 1, .y = 1 },
    snap_rule: SnapRule = .nearest,
};

pub const TextCellGrid = struct {
    origin: Vec2,
    cell_width: f32,
    line_height: f32,
    baseline_offset: f32,
    em: f32,

    pub fn cellOrigin(self: TextCellGrid, column: usize, row: usize) Vec2 {
        return .{
            .x = self.origin.x + @as(f32, @floatFromInt(column)) * self.cell_width,
            .y = self.origin.y + @as(f32, @floatFromInt(row)) * self.line_height,
        };
    }

    pub fn baseline(self: TextCellGrid, column: usize, row: usize) Vec2 {
        const top_left = self.cellOrigin(column, row);
        return .{
            .x = top_left.x,
            .y = top_left.y + self.baseline_offset,
        };
    }

    pub fn placement(self: TextCellGrid, column: usize, row: usize) TextPlacement {
        return .{
            .baseline = self.baseline(column, row),
            .em = self.em,
        };
    }

    pub fn advanceColumns(self: TextCellGrid, columns: usize) Vec2 {
        return .{
            .x = @as(f32, @floatFromInt(columns)) * self.cell_width,
            .y = 0,
        };
    }
};

pub const ScriptTransform = struct {
    x: f32,
    y: f32,
    font_size: f32,
};

pub const ShapedText = struct {
    allocator: Allocator,
    config: *const FontConfig,
    glyphs: []Glyph,
    advance_x: f32,
    advance_y: f32,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        x_offset: f32,
        y_offset: f32,
        x_advance: f32,
        y_advance: f32,
        source_start: u32,
        source_end: u32,
    };

    pub fn deinit(self: *ShapedText) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const Decoration = enum {
    underline,
    strikethrough,
};
