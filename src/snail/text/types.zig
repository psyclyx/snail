const std = @import("std");

const config_mod = @import("config.zig");
const paint_mod = @import("../paint.zig");
const range_mod = @import("../range.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const FaceIndex = config_mod.FaceIndex;
const FontStyle = config_mod.FontStyle;
const FontConfig = config_mod.FontConfig;
const Paint = paint_mod.Paint;
const Range = range_mod.Range;
const Vec2 = vec.Vec2;

pub const TextPlacement = struct {
    baseline: Vec2,
    em: f32,
};

pub const TextAppend = struct {
    shaped: *const ShapedText,
    glyphs: Range = .{},
    placement: TextPlacement,
    fill: Paint,
};

pub const TextAppendResult = struct {
    advance: Vec2,
    missing: bool,
};

pub const TextBatchAppend = struct {
    shaped: *const ShapedText,
    glyphs: Range = .{},
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
