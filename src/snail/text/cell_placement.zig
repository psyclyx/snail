//! Place shaped glyphs onto a caller-owned cell grid.
//!
//! A terminal owns columns: font advances do not decide where the next cell
//! begins. `placeCellRun` maps each HarfBuzz source cluster to a `Cell` supplied
//! by the caller, while preserving the glyph offsets *within* that cluster.
//! This handles fallback faces with different advances, combining marks,
//! ligatures, and wide cells without teaching snail terminal width policy.
//!
//! Cells are sorted, non-overlapping UTF-8 source ranges. A glyph belongs to
//! the cell containing its `source_start`; a ligature spanning several cells is
//! anchored by its first source byte. The caller expresses wide-character and
//! wrapping policy simply by assigning the following cell a later `column`.

const std = @import("std");
const text = @import("../text.zig");
const faces_mod = @import("faces.zig");
const run_placement = @import("run_placement.zig");
const shape_mod = @import("../draw/shape.zig");
const math = @import("../math/vec.zig");
const record_key = @import("../atlas/record_key.zig");

pub const ShapedText = text.ShapedText;
pub const Faces = faces_mod.Faces;
pub const HintMode = run_placement.HintMode;
pub const YAxis = run_placement.YAxis;
pub const Shape = shape_mod.Shape;
pub const Vec2 = math.Vec2;
pub const Transform2D = math.Transform2D;

/// One terminal cell's relationship to the source passed to `shape()`.
///
/// `source` is a non-empty UTF-8 byte range. `column` is deliberately explicit:
/// snail does not infer Unicode width, wrapping, tabs, or cursor movement.
/// Multiple source ranges may map to the same column when that is useful to the
/// host, but ranges themselves must be sorted and non-overlapping.
pub const Cell = struct {
    source: text.SourceRange,
    column: u32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    mode: HintMode = .unhinted,
};

/// How the caller's cell grid is aligned to device pixels.
pub const CellSnap = enum {
    /// Preserve the grid and HarfBuzz offsets exactly in world space.
    none,
    /// Snap the baseline and cell advance to device pixels, retaining
    /// HarfBuzz's intra-cluster offsets. This gives exact terminal columns
    /// without disturbing mark/ligature positioning.
    grid,
    /// As `.grid`, then snap each final glyph origin too. Use for strongly
    /// grid-fitted autohint or TrueType-hinted glyphs.
    glyph_origins,
};

pub const CellRunPlacement = struct {
    /// Baseline of column zero in world coordinates.
    baseline: Vec2,
    /// Width of one terminal column in world coordinates.
    cell_width: f32,
    /// Em size in world coordinates.
    em: f32,
    snap: CellSnap = .none,
    y_axis: YAxis = .down,
    /// World-to-device-pixel transform. Required for snapped placement.
    /// Cell grids must remain axis-aligned; use `.none` for rotated text.
    world_to_pixel: ?Transform2D = null,
    /// Expand COLRv0 glyphs to separately colored layer shapes. Every such
    /// cell must use `.unhinted`, matching `recordUnhintedRun(.layers)`.
    colr: bool = false,
};

pub const PlaceCellRunError = error{
    NoCellForGlyph,
    InvalidCells,
    UnknownFaceIndex,
    MismatchedFontId,
    InvalidColrMode,
    MissingWorldToPixel,
    InvalidWorldToPixel,
    UnsupportedGridTransform,
    InvalidPlacement,
    InvalidColor,
    InvalidHintMode,
    BufferTooSmall,
    ShapeCountOverflow,
};

pub const PlaceCellRunAllocError = PlaceCellRunError || std.mem.Allocator.Error;

const Grid = struct {
    p: CellRunPlacement,
    inverse: Transform2D = .identity,
    base_device: Vec2 = .{ .x = 0, .y = 0 },
    device_cell_width: f32 = 0,
    y_sign: f32,

    fn init(p: CellRunPlacement) PlaceCellRunError!Grid {
        if (!std.math.isFinite(p.baseline.x) or
            !std.math.isFinite(p.baseline.y) or
            !std.math.isFinite(p.cell_width) or
            !std.math.isFinite(p.em))
        {
            return error.InvalidPlacement;
        }
        if (p.cell_width <= 0 or p.em <= 0) return error.InvalidPlacement;

        var grid = Grid{
            .p = p,
            .y_sign = if (p.y_axis == .down) 1 else -1,
        };
        if (p.snap == .none) return grid;

        const world_to_pixel = p.world_to_pixel orelse return error.MissingWorldToPixel;
        if (world_to_pixel.xy != 0 or world_to_pixel.yx != 0)
            return error.UnsupportedGridTransform;
        grid.inverse = world_to_pixel.inverse() orelse return error.InvalidWorldToPixel;
        const base_device = world_to_pixel.applyPoint(p.baseline);
        if (!finiteVec(base_device)) return error.InvalidPlacement;
        grid.base_device = .{ .x = @round(base_device.x), .y = @round(base_device.y) };
        grid.device_cell_width = @round(world_to_pixel.xx * p.cell_width);
        if (!std.math.isFinite(grid.device_cell_width) or grid.device_cell_width == 0)
            return error.InvalidPlacement;
        return grid;
    }

    fn cellOrigin(self: *const Grid, column: u32) PlaceCellRunError!Vec2 {
        const column_f: f32 = @floatFromInt(column);
        const result = if (self.p.snap == .none)
            Vec2{
                .x = self.p.baseline.x + column_f * self.p.cell_width,
                .y = self.p.baseline.y,
            }
        else
            self.inverse.applyPoint(.{
                .x = self.base_device.x + column_f * self.device_cell_width,
                .y = self.base_device.y,
            });
        if (!finiteVec(result)) return error.InvalidPlacement;
        return result;
    }

    fn glyphOrigin(
        self: *const Grid,
        cell: Cell,
        glyph: ShapedText.Glyph,
        cluster_pen_x: f32,
        cluster_pen_y: f32,
    ) PlaceCellRunError!Vec2 {
        const cell_origin = try self.cellOrigin(cell.column);
        var result = Vec2{
            .x = cell_origin.x + self.p.em * (glyph.x_offset - cluster_pen_x),
            .y = cell_origin.y + self.p.em * (glyph.y_offset - cluster_pen_y) * self.y_sign,
        };
        if (!finiteVec(result)) return error.InvalidPlacement;
        if (self.p.snap == .glyph_origins) {
            const device = self.p.world_to_pixel.?.applyPoint(result);
            if (!finiteVec(device)) return error.InvalidPlacement;
            result = self.inverse.applyPoint(.{ .x = @round(device.x), .y = @round(device.y) });
            if (!finiteVec(result)) return error.InvalidPlacement;
        }
        return result;
    }
};

fn finiteVec(value: Vec2) bool {
    return std.math.isFinite(value.x) and std.math.isFinite(value.y);
}

fn validColor(color: [4]f32) bool {
    for (color) |component| if (!std.math.isFinite(component)) return false;
    return color[3] >= 0 and color[3] <= 1;
}

fn validateMode(mode: HintMode) bool {
    return switch (mode) {
        .unhinted => true,
        .autohint => |policy| blk: {
            policy.validate() catch break :blk false;
            break :blk true;
        },
        .tt_hint => |tt| tt.ppem_26_6 != 0 and tt.ppem_26_6 <= text.TtHintPpem.max_26_6,
    };
}

fn validateCells(cells: []const Cell, colr: bool) PlaceCellRunError!void {
    var previous_end: u32 = 0;
    for (cells, 0..) |cell, i| {
        if (cell.source.end <= cell.source.start) return error.InvalidCells;
        if (i != 0 and cell.source.start < previous_end) return error.InvalidCells;
        if (!validColor(cell.color)) return error.InvalidColor;
        if (!validateMode(cell.mode)) return error.InvalidHintMode;
        if (colr) switch (cell.mode) {
            .unhinted => {},
            else => return error.InvalidColrMode,
        };
        previous_end = cell.source.end;
    }
}

fn cellForSource(cells: []const Cell, source_start: u32) ?Cell {
    var lo: usize = 0;
    var hi = cells.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (cells[mid].source.start <= source_start) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) return null;
    const candidate = cells[lo - 1];
    return if (source_start < candidate.source.end) candidate else null;
}

fn shapeFor(
    origin: Vec2,
    em: f32,
    y_sign: f32,
    key: record_key.RecordKey,
    color: [4]f32,
    mode: HintMode,
) Shape {
    const policy = switch (mode) {
        .autohint => |value| value,
        else => null,
    };
    const scale = mode.scale(em);
    return .{
        .key = key,
        .local_transform = .{
            .xx = scale,
            .xy = 0,
            .tx = origin.x,
            .yx = 0,
            .yy = -y_sign * scale,
            .ty = origin.y,
        },
        .local_color = color,
        .autohint_policy = policy,
    };
}

fn colrLayerShapeCount(
    faces: *const Faces,
    glyph: ShapedText.Glyph,
) PlaceCellRunError!usize {
    const face_index: usize = @intCast(glyph.face_index);
    if (face_index >= faces.faceCount()) return error.UnknownFaceIndex;
    if (faces.fontIdForFace(glyph.face_index).? != glyph.font_id)
        return error.MismatchedFontId;
    var layers = faces.fontForFace(glyph.face_index).?.colrLayers(glyph.glyph_id);
    const count = layers.count();
    while (layers.next()) |layer| {
        if (!(layer.color[0] < 0) and !validColor(layer.color))
            return error.InvalidColor;
    }
    return if (count == 0) 1 else count;
}

/// Return the exact output storage needed by `placeCellRun`.
pub fn placedCellRunShapeCount(
    shaped: *const ShapedText,
    faces: ?*const Faces,
    cells: []const Cell,
    placement: CellRunPlacement,
) PlaceCellRunError!usize {
    try validateCells(cells, placement.colr);
    const grid = try Grid.init(placement);

    var count: usize = 0;
    var pen_x: f32 = 0;
    var pen_y: f32 = 0;
    var cluster_pen_x: f32 = 0;
    var cluster_pen_y: f32 = 0;
    var previous_cluster: ?u32 = null;
    for (shaped.glyphs) |glyph_value| {
        if (!std.math.isFinite(glyph_value.x_offset) or
            !std.math.isFinite(glyph_value.y_offset) or
            !std.math.isFinite(glyph_value.x_advance) or
            !std.math.isFinite(glyph_value.y_advance))
        {
            return error.InvalidPlacement;
        }
        if (previous_cluster == null or previous_cluster.? != glyph_value.source_start) {
            previous_cluster = glyph_value.source_start;
            cluster_pen_x = pen_x;
            cluster_pen_y = pen_y;
        }
        const cell = cellForSource(cells, glyph_value.source_start) orelse
            return error.NoCellForGlyph;
        _ = try grid.glyphOrigin(cell, glyph_value, cluster_pen_x, cluster_pen_y);
        const add: usize = if (placement.colr)
            try colrLayerShapeCount(faces orelse return error.UnknownFaceIndex, glyph_value)
        else
            1;
        count = std.math.add(usize, count, add) catch return error.ShapeCountOverflow;
        pen_x += glyph_value.x_advance;
        pen_y += glyph_value.y_advance;
        if (!std.math.isFinite(pen_x) or !std.math.isFinite(pen_y))
            return error.InvalidPlacement;
    }
    return count;
}

/// Place a shaped run on caller-specified terminal columns.
///
/// Glyph output order is preserved. The function is allocation-free and
/// failure-atomic: all cells, modes, colors, transforms, face references, and
/// output capacity are validated before the first shape is written.
pub fn placeCellRun(
    out: []Shape,
    shaped: *const ShapedText,
    faces: ?*const Faces,
    cells: []const Cell,
    placement: CellRunPlacement,
) PlaceCellRunError![]Shape {
    const count = try placedCellRunShapeCount(shaped, faces, cells, placement);
    if (out.len < count) return error.BufferTooSmall;
    const grid = try Grid.init(placement);

    var pen_x: f32 = 0;
    var pen_y: f32 = 0;
    var cluster_pen_x: f32 = 0;
    var cluster_pen_y: f32 = 0;
    var previous_cluster: ?u32 = null;
    var cursor: usize = 0;

    for (shaped.glyphs) |glyph_value| {
        if (previous_cluster == null or previous_cluster.? != glyph_value.source_start) {
            previous_cluster = glyph_value.source_start;
            cluster_pen_x = pen_x;
            cluster_pen_y = pen_y;
        }
        const cell = cellForSource(cells, glyph_value.source_start) orelse unreachable;
        const origin = grid.glyphOrigin(cell, glyph_value, cluster_pen_x, cluster_pen_y) catch unreachable;

        if (!placement.colr) {
            out[cursor] = shapeFor(
                origin,
                placement.em,
                grid.y_sign,
                cell.mode.key(glyph_value.font_id, glyph_value.glyph_id),
                cell.color,
                cell.mode,
            );
            cursor += 1;
        } else {
            const font = faces.?.fontForFace(glyph_value.face_index).?;
            var layers = font.colrLayers(glyph_value.glyph_id);
            if (layers.count() == 0) {
                out[cursor] = shapeFor(
                    origin,
                    placement.em,
                    grid.y_sign,
                    record_key.unhintedGlyph(glyph_value.font_id, glyph_value.glyph_id),
                    cell.color,
                    .unhinted,
                );
                cursor += 1;
            } else {
                while (layers.next()) |layer| {
                    const color = if (layer.color[0] < 0) cell.color else layer.color;
                    out[cursor] = shapeFor(
                        origin,
                        placement.em,
                        grid.y_sign,
                        record_key.unhintedGlyph(glyph_value.font_id, layer.glyph_id),
                        color,
                        .unhinted,
                    );
                    cursor += 1;
                }
            }
        }

        pen_x += glyph_value.x_advance;
        pen_y += glyph_value.y_advance;
    }
    return out[0..cursor];
}

/// Allocating convenience wrapper around `placeCellRun`.
pub fn placeCellRunAlloc(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    faces: ?*const Faces,
    cells: []const Cell,
    placement: CellRunPlacement,
) PlaceCellRunAllocError![]Shape {
    const count = try placedCellRunShapeCount(shaped, faces, cells, placement);
    const out = try allocator.alloc(Shape, count);
    errdefer allocator.free(out);
    return placeCellRun(out, shaped, faces, cells, placement);
}

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testGlyph(
    source_start: u32,
    source_end: u32,
    x_offset: f32,
    x_advance: f32,
    glyph_id: u16,
    font_id: u32,
) ShapedText.Glyph {
    return .{
        .face_index = 0,
        .glyph_id = glyph_id,
        .x_offset = x_offset,
        .y_offset = 0,
        .x_advance = x_advance,
        .y_advance = 0,
        .source_start = source_start,
        .source_end = source_end,
        .font_id = font_id,
    };
}

test "cell placement ignores fallback advances and honors explicit columns" {
    var glyphs = [_]ShapedText.Glyph{
        testGlyph(0, 1, 0, 0.6, 1, 10),
        testGlyph(1, 5, 0.6, 1.2, 2, 20),
        testGlyph(5, 6, 1.8, 0.6, 3, 10),
    };
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const cells = [_]Cell{
        .{ .source = .{ .start = 0, .end = 1 }, .column = 0 },
        .{ .source = .{ .start = 1, .end = 5 }, .column = 1 },
        .{ .source = .{ .start = 5, .end = 6 }, .column = 3 },
    };
    var out: [3]Shape = undefined;
    const placed = try placeCellRun(&out, &shaped, null, &cells, .{
        .baseline = .{ .x = 10, .y = 20 },
        .cell_width = 8,
        .em = 16,
    });

    try testing.expectEqual(@as(f32, 10), placed[0].local_transform.tx);
    try testing.expectEqual(@as(f32, 18), placed[1].local_transform.tx);
    try testing.expectEqual(@as(f32, 34), placed[2].local_transform.tx);
    try testing.expectEqual(@as(u32, 20), placed[1].key.a);
}

test "cell placement preserves offsets within a combining cluster" {
    var glyphs = [_]ShapedText.Glyph{
        testGlyph(0, 3, 0.05, 0.6, 1, 0),
        testGlyph(0, 3, 0.35, 0, 2, 0),
        testGlyph(3, 4, 0.6, 0.6, 3, 0),
    };
    glyphs[1].y_offset = -0.4;
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const cells = [_]Cell{
        .{ .source = .{ .start = 0, .end = 3 }, .column = 2 },
        .{ .source = .{ .start = 3, .end = 4 }, .column = 3 },
    };
    var out: [3]Shape = undefined;
    const placed = try placeCellRun(&out, &shaped, null, &cells, .{
        .baseline = .{ .x = 0, .y = 20 },
        .cell_width = 10,
        .em = 10,
    });

    try testing.expectEqual(@as(f32, 20.5), placed[0].local_transform.tx);
    try testing.expectEqual(@as(f32, 23.5), placed[1].local_transform.tx);
    try testing.expectEqual(@as(f32, 16), placed[1].local_transform.ty);
    try testing.expectEqual(@as(f32, 30), placed[2].local_transform.tx);
}

test "cell placement supports per-cell record modes and colors" {
    var glyphs = [_]ShapedText.Glyph{
        testGlyph(0, 1, 0, 0.5, 1, 3),
        testGlyph(1, 2, 0.5, 0.5, 2, 3),
    };
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const cells = [_]Cell{
        .{
            .source = .{ .start = 0, .end = 1 },
            .column = 0,
            .color = .{ 1, 0, 0, 1 },
        },
        .{
            .source = .{ .start = 1, .end = 2 },
            .column = 1,
            .color = .{ 0, 1, 0, 1 },
            .mode = .{ .tt_hint = .{ .ppem_26_6 = 16 * 64 } },
        },
    };
    var out: [2]Shape = undefined;
    const placed = try placeCellRun(&out, &shaped, null, &cells, .{
        .baseline = .{ .x = 0, .y = 10 },
        .cell_width = 8,
        .em = 16,
    });

    try testing.expectEqual(record_key.ns.unhinted_glyph, placed[0].key.namespace);
    try testing.expectEqual(record_key.ns.tt_hinted_glyph, placed[1].key.namespace);
    try testing.expectEqual(@as(f32, 1), placed[0].local_color[0]);
    try testing.expectEqual(@as(f32, 1), placed[1].local_color[1]);
}

test "cell placement validates cells and output before writing" {
    var glyphs = [_]ShapedText.Glyph{testGlyph(4, 5, 0, 1, 1, 0)};
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const cells = [_]Cell{.{
        .source = .{ .start = 0, .end = 1 },
        .column = 0,
    }};
    var out = [_]Shape{.{ .key = .{ .namespace = 999 } }};
    try testing.expectError(error.NoCellForGlyph, placeCellRun(&out, &shaped, null, &cells, .{
        .baseline = .{ .x = 0, .y = 0 },
        .cell_width = 8,
        .em = 16,
    }));
    try testing.expectEqual(@as(u32, 999), out[0].key.namespace);

    const overlapping = [_]Cell{
        .{ .source = .{ .start = 0, .end = 2 }, .column = 0 },
        .{ .source = .{ .start = 1, .end = 3 }, .column = 1 },
    };
    try testing.expectError(error.InvalidCells, placedCellRunShapeCount(&shaped, null, &overlapping, .{
        .baseline = .{ .x = 0, .y = 0 },
        .cell_width = 8,
        .em = 16,
    }));
}

test "cell grid snapping rounds the device column advance" {
    var glyphs = [_]ShapedText.Glyph{
        testGlyph(0, 1, 0, 0.5, 1, 0),
        testGlyph(1, 2, 0.5, 0.5, 2, 0),
    };
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const cells = [_]Cell{
        .{ .source = .{ .start = 0, .end = 1 }, .column = 0 },
        .{ .source = .{ .start = 1, .end = 2 }, .column = 1 },
    };
    var out: [2]Shape = undefined;
    const placed = try placeCellRun(&out, &shaped, null, &cells, .{
        .baseline = .{ .x = 0.2, .y = 10.4 },
        .cell_width = 7.6,
        .em = 16,
        .snap = .grid,
        .world_to_pixel = .identity,
    });
    try testing.expectEqual(@as(f32, 0), placed[0].local_transform.tx);
    try testing.expectEqual(@as(f32, 8), placed[1].local_transform.tx);
    try testing.expectEqual(@as(f32, 10), placed[0].local_transform.ty);
}
