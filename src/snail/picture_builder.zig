//! Picture-construction layer on top of the new-API primitives.
//!
//! `PictureBuilder` accumulates `(path geometry, paint, transform)` triples,
//! calls `pathToCurves` / `strokeToCurves` to convert each into a
//! `GlyphCurves`, and on `freeze()` builds a backing `Atlas` and a
//! `Picture` referencing fresh `RecordKey`s under `ns.path_fill` /
//! `ns.path_stroke`.
//!
//! Paints attach to the entry via `Atlas.Entry.paint`; emit then encodes
//! a special-layer instance per shape and the existing CPU rasterizer
//! samples the paint.
//!
//! Composite shapes (fill + stroke on the same path) become two shapes
//! drawn in painter order — same visual result as the legacy
//! `composite_group` source_over mode without the multi-layer record.

const std = @import("std");

const atlas_mod = @import("atlas.zig");
const picture_mod = @import("picture.zig");
const shape_mod = @import("shape.zig");
const record_key_mod = @import("record_key.zig");
const paths_mod = @import("paths.zig");
const curves_mod = @import("curves.zig");
const paint_mod = @import("paint.zig");
const path_core = @import("path/core.zig");
const math = @import("math/vec.zig");
const target = @import("target.zig");

pub const Atlas = atlas_mod.Atlas;
pub const PagePool = atlas_mod.PagePool;
pub const Picture = picture_mod.Picture;
pub const Shape = shape_mod.Shape;
pub const Entry = atlas_mod.Entry;
pub const GlyphCurves = curves_mod.GlyphCurves;
pub const Path = path_core.Path;
pub const FillStyle = paint_mod.FillStyle;
pub const StrokeStyle = paint_mod.StrokeStyle;
pub const Paint = paint_mod.Paint;
pub const Transform2D = math.Transform2D;
pub const Rect = target.Rect;
pub const RecordKey = record_key_mod.RecordKey;

pub const FrozenPicture = struct {
    atlas: Atlas,
    picture: Picture,

    pub fn deinit(self: *FrozenPicture) void {
        self.picture.deinit();
        self.atlas.deinit();
        self.* = undefined;
    }
};

pub const PictureBuilder = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    entries: std.ArrayList(Entry),
    /// `Atlas.from` copies curve+band bytes into pages; the builder still
    /// owns these GlyphCurves until freeze() runs (Entry borrows them).
    owned_curves: std.ArrayList(GlyphCurves),
    shapes: std.ArrayList(Shape),
    next_id: u32,

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) PictureBuilder {
        return .{
            .allocator = allocator,
            .pool = pool,
            .entries = .empty,
            .owned_curves = .empty,
            .shapes = .empty,
            .next_id = 0,
        };
    }

    pub fn deinit(self: *PictureBuilder) void {
        for (self.owned_curves.items) |*c| c.deinit();
        self.owned_curves.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.shapes.deinit(self.allocator);
        self.* = undefined;
    }

    /// Convert and finalize. The builder is consumed and its arrays
    /// drained into the returned `FrozenPicture`. Subsequent use of the
    /// builder is invalid.
    pub fn freeze(self: *PictureBuilder) !FrozenPicture {
        var atlas = try Atlas.from(self.allocator, self.pool, self.entries.items);
        errdefer atlas.deinit();
        const picture = try Picture.from(self.allocator, self.shapes.items);

        // GlyphCurves bytes were copied into atlas pages by Atlas.from;
        // we still own the originals and need to release them now that
        // the build is complete.
        for (self.owned_curves.items) |*c| c.deinit();
        self.owned_curves.deinit(self.allocator);
        self.owned_curves = .empty;
        self.entries.deinit(self.allocator);
        self.entries = .empty;
        self.shapes.deinit(self.allocator);
        self.shapes = .empty;

        return .{ .atlas = atlas, .picture = picture };
    }

    // ----- primitives -----

    pub fn addFilledPath(
        self: *PictureBuilder,
        path: *const Path,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.appendFillFromCurves(
            try paths_mod.pathToCurves(self.allocator, path),
            fill.paint,
            transform,
        );
    }

    pub fn addStrokedPath(
        self: *PictureBuilder,
        path: *const Path,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.appendStrokeFromCurves(
            try paths_mod.strokeToCurves(self.allocator, path, stroke),
            stroke.paint,
            transform,
        );
    }

    pub fn addPath(
        self: *PictureBuilder,
        path: *const Path,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (fill) |f| try self.addFilledPath(path, f, transform);
        if (stroke) |s| try self.addStrokedPath(path, s, transform);
    }

    pub fn addFilledRect(
        self: *PictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addFilledPath(&path, fill, transform);
    }

    pub fn addStrokedRect(
        self: *PictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addStrokedPath(&path, stroke, transform);
    }

    pub fn addRect(
        self: *PictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledRoundedRect(
        self: *PictureBuilder,
        rect: Rect,
        fill: FillStyle,
        radius: f32,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, radius);
        try self.addFilledPath(&path, fill, transform);
    }

    pub fn addRoundedRect(
        self: *PictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        radius: f32,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, radius);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledEllipse(
        self: *PictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addFilledPath(&path, fill, transform);
    }

    pub fn addStrokedEllipse(
        self: *PictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addStrokedPath(&path, stroke, transform);
    }

    pub fn addEllipse(
        self: *PictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    // ----- internal -----

    fn appendFillFromCurves(
        self: *PictureBuilder,
        curves: GlyphCurves,
        paint: Paint,
        transform: Transform2D,
    ) !void {
        try self.appendFromCurves(curves, paint, transform, record_key_mod.ns.path_fill);
    }

    fn appendStrokeFromCurves(
        self: *PictureBuilder,
        curves: GlyphCurves,
        paint: Paint,
        transform: Transform2D,
    ) !void {
        try self.appendFromCurves(curves, paint, transform, record_key_mod.ns.path_stroke);
    }

    fn appendFromCurves(
        self: *PictureBuilder,
        curves: GlyphCurves,
        paint: Paint,
        transform: Transform2D,
        namespace: u32,
    ) !void {
        // Drop empty curves (e.g. degenerate stroke) so we don't burn
        // atlas keys on no-ops.
        if (curves.isEmpty()) {
            var c = curves;
            c.deinit();
            return;
        }

        try self.owned_curves.append(self.allocator, curves);
        const stored = &self.owned_curves.items[self.owned_curves.items.len - 1];

        const key: RecordKey = .{
            .namespace = namespace,
            .a = self.next_id,
            .b = 0,
            .c = 0,
        };
        self.next_id += 1;

        try self.entries.append(self.allocator, .{
            .key = key,
            .curves = stored.*,
            .paint = paint,
        });
        try self.shapes.append(self.allocator, .{
            .key = key,
            .local_transform = transform,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "PictureBuilder freezes a filled rect into a Picture + Atlas" {
    const allocator = testing.allocator;

    var pool = try PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 14,
        .band_words_per_page = 1 << 12,
    });
    defer pool.deinit();

    var b = PictureBuilder.init(allocator, pool);
    defer b.deinit();

    try b.addFilledRect(.{ .x = 10, .y = 20, .w = 40, .h = 30 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }, .identity);

    var frozen = try b.freeze();
    defer frozen.deinit();

    try testing.expectEqual(@as(usize, 1), frozen.picture.shapes.len);
    const key = frozen.picture.shapes[0].key;
    try testing.expect(frozen.atlas.lookupRecord(key) != null);
    try testing.expect(frozen.atlas.lookupPaintRecord(key) != null);
}

test "PictureBuilder composite (fill+stroke) yields two shapes" {
    const allocator = testing.allocator;

    var pool = try PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 14,
        .band_words_per_page = 1 << 12,
    });
    defer pool.deinit();

    var b = PictureBuilder.init(allocator, pool);
    defer b.deinit();

    try b.addRect(.{ .x = 0, .y = 0, .w = 50, .h = 50 }, .{
        .paint = .{ .solid = .{ 1, 1, 0, 1 } },
    }, .{
        .paint = .{ .solid = .{ 0, 0, 0, 1 } },
        .width = 2.0,
    }, .identity);

    var frozen = try b.freeze();
    defer frozen.deinit();

    try testing.expectEqual(@as(usize, 2), frozen.picture.shapes.len);
    try testing.expect(frozen.picture.shapes[0].key.namespace == record_key_mod.ns.path_fill);
    try testing.expect(frozen.picture.shapes[1].key.namespace == record_key_mod.ns.path_stroke);
}
