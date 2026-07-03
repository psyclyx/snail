//! Builds the vector snail as a sequence of (path, paint, transform)
//! shapes using `pathToCurves` / `strokeToCurves` and direct Atlas entries.

const std = @import("std");
const snail = @import("snail");
const snail_helpers = @import("snail-helpers");

const Allocator = std.mem.Allocator;

pub const Builder = struct {
    allocator: Allocator,
    /// Reset between path producer calls; intermediate buffers for
    /// `pathToCurves` / `strokeToCurves` come off this arena rather than
    /// the gpa, so they collapse to bump-pointer allocations.
    scratch_arena: *std.heap.ArenaAllocator,
    owned_curves: *std.ArrayList(snail.GlyphCurves),
    entries: *std.ArrayList(snail.AtlasEntry),
    shapes: *std.ArrayList(snail.Shape),
    /// Heap-allocated slices backing each entry's `extra_layers`. The
    /// caller is responsible for freeing each slice after the atlas is
    /// built. Snail itself never owns this storage; entries borrow.
    extra_layer_storage: *std.ArrayList([]snail.AtlasLayer),
    next_id: *u32,

    pub fn addFilledPath(
        self: Builder,
        path: *const snail.Path,
        paint: snail.Paint,
        transform: snail.Transform2D,
    ) !void {
        const curves = try path.toCurves(self.allocator, self.scratch_arena.allocator());
        _ = self.scratch_arena.reset(.retain_capacity);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.owned_curves.append(self.allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_id.* };
        self.next_id.* += 1;
        try self.entries.append(self.allocator, .{
            .key = key,
            .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
            .paint = paint,
        });
        try self.shapes.append(self.allocator, .{
            .key = key,
            .local_transform = transform,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    pub fn addStrokedPath(
        self: Builder,
        path: *const snail.Path,
        stroke: snail.StrokeStyle,
        transform: snail.Transform2D,
    ) !void {
        const curves = try path.strokeToCurves(self.allocator, self.scratch_arena.allocator(), stroke);
        _ = self.scratch_arena.reset(.retain_capacity);
        if (curves.isEmpty()) {
            var owned = curves;
            owned.deinit();
            return;
        }
        try self.owned_curves.append(self.allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = self.next_id.* };
        self.next_id.* += 1;
        try self.entries.append(self.allocator, .{
            .key = key,
            .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
            .paint = stroke.paint,
        });
        try self.shapes.append(self.allocator, .{
            .key = key,
            .local_transform = transform,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    // Ellipses are authored as a unit circle placed via
    // `transform ∘ placeRect(rect)`, so their outlines stay f16-precise
    // regardless of design-space offset (crucial for the small, high-offset
    // eyes). Paints are re-expressed into the unit sample space with
    // `mapPaintToLocal` — solid passes through; gradients/images are remapped.
    pub fn addFilledEllipse(
        self: Builder,
        rect: snail.Rect,
        paint: snail.Paint,
        transform: snail.Transform2D,
    ) !void {
        var path = try snail_helpers.unitEllipsePath(self.allocator);
        defer path.deinit();
        const to_paint = snail_helpers.placeRect(rect);
        const local_paint = snail.mapPaintToLocal(paint, to_paint) orelse paint;
        try self.addFilledPath(&path, local_paint, snail.Transform2D.multiply(transform, to_paint));
    }

    pub fn addEllipse(
        self: Builder,
        rect: snail.Rect,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
        transform: snail.Transform2D,
    ) !void {
        var path = try snail_helpers.unitEllipsePath(self.allocator);
        defer path.deinit();
        const to_paint = snail_helpers.placeRect(rect);
        const place = snail.Transform2D.multiply(transform, to_paint);
        try self.addFilledPath(&path, snail.mapPaintToLocal(fill, to_paint) orelse fill, place);
        var unit_stroke = stroke;
        unit_stroke.width = snail_helpers.unitStrokeWidth(rect, stroke.width);
        unit_stroke.paint = snail.mapPaintToLocal(stroke.paint, to_paint) orelse stroke.paint;
        try self.addStrokedPath(&path, unit_stroke, place);
    }

    /// Fill + stroke compound. When `stroke.placement == .inside`, this
    /// emits a composite-group atlas entry so the GPU clips the stroke
    /// to the fill interior. Other placements fall back to drawing the
    /// fill and stroke as separate shapes.
    pub fn addPathFillAndStroke(
        self: Builder,
        path: *const snail.Path,
        fill: snail.Paint,
        stroke: snail.StrokeStyle,
        transform: snail.Transform2D,
    ) !void {
        if (stroke.placement != .inside) {
            try self.addFilledPath(path, fill, transform);
            try self.addStrokedPath(path, stroke, transform);
            return;
        }

        const fill_curves = try path.toCurves(self.allocator, self.scratch_arena.allocator());
        _ = self.scratch_arena.reset(.retain_capacity);
        if (fill_curves.isEmpty()) {
            var owned = fill_curves;
            owned.deinit();
            // Fill is empty — emit only the stroke.
            try self.addStrokedPath(path, stroke, transform);
            return;
        }
        const stroke_curves = try path.strokeToCurves(self.allocator, self.scratch_arena.allocator(), stroke);
        _ = self.scratch_arena.reset(.retain_capacity);
        if (stroke_curves.isEmpty()) {
            // Stroke degenerate — emit fill only.
            try self.owned_curves.append(self.allocator, fill_curves);
            const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_id.* };
            self.next_id.* += 1;
            try self.entries.append(self.allocator, .{
                .key = key,
                .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
                .paint = fill,
            });
            try self.shapes.append(self.allocator, .{
                .key = key,
                .local_transform = transform,
                .local_color = .{ 1, 1, 1, 1 },
            });
            var owned_stroke = stroke_curves;
            owned_stroke.deinit();
            return;
        }

        try self.owned_curves.append(self.allocator, fill_curves);
        try self.owned_curves.append(self.allocator, stroke_curves);

        const extras = try self.allocator.alloc(snail.AtlasLayer, 1);
        extras[0] = .{
            .curves = self.owned_curves.items[self.owned_curves.items.len - 1],
            .paint = stroke.paint,
        };
        try self.extra_layer_storage.append(self.allocator, extras);

        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_id.* };
        self.next_id.* += 1;
        try self.entries.append(self.allocator, .{
            .key = key,
            .curves = self.owned_curves.items[self.owned_curves.items.len - 2],
            .paint = fill,
            .extra_layers = extras,
            .composite_mode = .fill_stroke_inside,
        });
        try self.shapes.append(self.allocator, .{
            .key = key,
            .local_transform = transform,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }
};

fn perpLeft(v: snail.Vec2) snail.Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

fn addFilledQuadraticRibbon(
    builder: Builder,
    start: snail.Vec2,
    control: snail.Vec2,
    end: snail.Vec2,
    half_width: f32,
    color: [4]f32,
    transform: snail.Transform2D,
) !void {
    const start_tangent = snail.Vec2.normalize(snail.Vec2.sub(control, start));
    const end_tangent = snail.Vec2.normalize(snail.Vec2.sub(end, control));
    const blended_tangent = snail.Vec2.add(start_tangent, end_tangent);
    const mid_tangent = if (snail.Vec2.length(blended_tangent) > 1e-5)
        snail.Vec2.normalize(blended_tangent)
    else
        snail.Vec2.normalize(snail.Vec2.sub(end, start));

    const start_normal = snail.Vec2.scale(perpLeft(start_tangent), half_width);
    const mid_normal = snail.Vec2.scale(perpLeft(mid_tangent), half_width);
    const end_normal = snail.Vec2.scale(perpLeft(end_tangent), half_width);
    const tip_cap = snail.Vec2.scale(end_tangent, half_width * 0.9);

    var ribbon = snail.Path.init(builder.allocator);
    defer ribbon.deinit();
    try ribbon.moveTo(snail.Vec2.add(start, start_normal));
    try ribbon.quadTo(snail.Vec2.add(control, mid_normal), snail.Vec2.add(end, end_normal));
    try ribbon.quadTo(snail.Vec2.add(end, tip_cap), snail.Vec2.sub(end, end_normal));
    try ribbon.quadTo(snail.Vec2.sub(control, mid_normal), snail.Vec2.sub(start, start_normal));
    try ribbon.close();
    try builder.addFilledPath(&ribbon, .{ .solid = color }, transform);
}

pub fn addVectorSnail(builder: Builder, snail_stage: snail.Rect) !void {
    const art_width = @min(snail_stage.w * 0.82, 440.0);
    const scale = art_width / 360.0;
    const art_height = 220.0 * scale;
    const art_x = snail_stage.x + (snail_stage.w - art_width) * 0.5;
    const art_y = snail_stage.y + (snail_stage.h - art_height) * 0.5 + 10.0;
    const transform = snail.Transform2D.multiply(
        snail.Transform2D.translate(art_x, art_y),
        snail.Transform2D.scale(scale, scale),
    );

    try builder.addFilledEllipse(.{
        .x = 62.0,
        .y = 168.0,
        .w = 240.0,
        .h = 28.0,
    }, .{ .radial_gradient = .{
        .center = .{ .x = 182.0, .y = 182.0 },
        .radius = 125.0,
        .inner_color = .{ 0.0, 0.0, 0.0, 0.18 },
        .outer_color = .{ 0.0, 0.0, 0.0, 0.0 },
    } }, transform);

    var body = snail.Path.init(builder.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28.0, .y = 155.0 });
    try body.cubicTo(.{ .x = 62.0, .y = 132.0 }, .{ .x = 106.0, .y = 121.0 }, .{ .x = 142.0, .y = 127.0 });
    try body.cubicTo(.{ .x = 179.0, .y = 133.0 }, .{ .x = 210.0, .y = 151.0 }, .{ .x = 246.0, .y = 151.0 });
    try body.cubicTo(.{ .x = 288.0, .y = 151.0 }, .{ .x = 317.0, .y = 145.0 }, .{ .x = 332.0, .y = 131.0 });
    try body.cubicTo(.{ .x = 346.0, .y = 119.0 }, .{ .x = 345.0, .y = 104.0 }, .{ .x = 327.0, .y = 100.0 });
    try body.cubicTo(.{ .x = 307.0, .y = 96.0 }, .{ .x = 286.0, .y = 105.0 }, .{ .x = 278.0, .y = 119.0 });
    try body.cubicTo(.{ .x = 269.0, .y = 132.0 }, .{ .x = 252.0, .y = 136.0 }, .{ .x = 233.0, .y = 132.0 });
    try body.cubicTo(.{ .x = 210.0, .y = 126.0 }, .{ .x = 189.0, .y = 105.0 }, .{ .x = 166.0, .y = 92.0 });
    try body.cubicTo(.{ .x = 142.0, .y = 79.0 }, .{ .x = 106.0, .y = 84.0 }, .{ .x = 82.0, .y = 106.0 });
    try body.cubicTo(.{ .x = 58.0, .y = 127.0 }, .{ .x = 42.0, .y = 149.0 }, .{ .x = 28.0, .y = 155.0 });
    try body.close();
    try builder.addPathFillAndStroke(&body, .{ .linear_gradient = .{
        .start = .{ .x = 48.0, .y = 102.0 },
        .end = .{ .x = 320.0, .y = 158.0 },
        .start_color = .{ 0.38, 0.48, 0.38, 0.95 },
        .end_color = .{ 0.68, 0.65, 0.52, 0.95 },
    } }, .{
        .paint = .{ .solid = .{ 0.45, 0.50, 0.38, 0.50 } },
        .width = 2.0,
        .join = .round,
        .placement = .inside,
    }, transform);

    var belly = snail.Path.init(builder.allocator);
    defer belly.deinit();
    try belly.moveTo(.{ .x = 92.0, .y = 140.0 });
    try belly.cubicTo(.{ .x = 138.0, .y = 132.0 }, .{ .x = 204.0, .y = 136.0 }, .{ .x = 274.0, .y = 142.0 });
    try builder.addStrokedPath(&belly, .{
        .paint = .{ .solid = .{ 1.0, 1.0, 0.95, 0.35 } },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, transform);

    try builder.addEllipse(.{
        .x = 156.0,
        .y = 24.0,
        .w = 114.0,
        .h = 114.0,
    }, .{ .radial_gradient = .{
        .center = .{ .x = 208.0, .y = 68.0 },
        .radius = 72.0,
        .inner_color = .{ 0.62, 0.82, 0.92, 0.55 },
        .outer_color = .{ 0.25, 0.45, 0.62, 0.88 },
    } }, .{
        .paint = .{ .solid = .{ 0.35, 0.60, 0.78, 0.65 } },
        .width = 2.4,
        .join = .round,
    }, transform);

    var spiral = snail.Path.init(builder.allocator);
    defer spiral.deinit();
    try spiral.moveTo(.{ .x = 254.0, .y = 78.0 });
    try spiral.cubicTo(.{ .x = 248.0, .y = 44.0 }, .{ .x = 196.0, .y = 41.0 }, .{ .x = 178.0, .y = 72.0 });
    try spiral.cubicTo(.{ .x = 160.0, .y = 102.0 }, .{ .x = 178.0, .y = 138.0 }, .{ .x = 214.0, .y = 134.0 });
    try spiral.cubicTo(.{ .x = 247.0, .y = 130.0 }, .{ .x = 256.0, .y = 95.0 }, .{ .x = 235.0, .y = 81.0 });
    try spiral.cubicTo(.{ .x = 217.0, .y = 69.0 }, .{ .x = 195.0, .y = 83.0 }, .{ .x = 200.0, .y = 103.0 });
    try spiral.cubicTo(.{ .x = 204.0, .y = 118.0 }, .{ .x = 224.0, .y = 117.0 }, .{ .x = 229.0, .y = 104.0 });
    try builder.addStrokedPath(&spiral, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 252.0, .y = 60.0 },
            .end = .{ .x = 194.0, .y = 114.0 },
            .start_color = .{ 0.92, 0.72, 0.28, 0.92 },
            .end_color = .{ 0.85, 0.45, 0.18, 0.88 },
        } },
        .width = 9.0,
        .cap = .round,
        .join = .round,
    }, transform);

    try addFilledQuadraticRibbon(builder, .{ .x = 308.0, .y = 100.0 }, .{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 }, 2.0, .{ 0.58, 0.58, 0.52, 0.90 }, transform);
    try addFilledQuadraticRibbon(builder, .{ .x = 294.0, .y = 102.0 }, .{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 }, 2.0, .{ 0.58, 0.58, 0.52, 0.90 }, transform);

    const eye_stroke = snail.StrokeStyle{
        .paint = .{ .solid = .{ 0.30, 0.32, 0.28, 0.80 } },
        .width = 1.2,
        .join = .round,
    };
    try builder.addEllipse(.{ .x = 330.0, .y = 54.0, .w = 9.0, .h = 9.0 }, .{ .solid = .{ 0.98, 0.97, 0.94, 1.0 } }, eye_stroke, transform);
    try builder.addFilledEllipse(.{ .x = 332.0, .y = 56.0, .w = 5.0, .h = 5.0 }, .{ .solid = .{ 0.18, 0.20, 0.22, 1.0 } }, transform);
    try builder.addFilledEllipse(.{ .x = 333.0, .y = 56.5, .w = 1.5, .h = 1.5 }, .{ .solid = .{ 1.0, 1.0, 1.0, 0.90 } }, transform);
    try builder.addEllipse(.{ .x = 303.0, .y = 61.0, .w = 7.0, .h = 7.0 }, .{ .solid = .{ 0.98, 0.97, 0.94, 1.0 } }, eye_stroke, transform);
    try builder.addFilledEllipse(.{ .x = 304.5, .y = 62.5, .w = 4.0, .h = 4.0 }, .{ .solid = .{ 0.18, 0.20, 0.22, 1.0 } }, transform);
    try builder.addFilledEllipse(.{ .x = 305.2, .y = 63.0, .w = 1.2, .h = 1.2 }, .{ .solid = .{ 1.0, 1.0, 1.0, 0.90 } }, transform);

    var smile = snail.Path.init(builder.allocator);
    defer smile.deinit();
    try smile.moveTo(.{ .x = 314.0, .y = 119.0 });
    try smile.quadTo(.{ .x = 321.0, .y = 123.0 }, .{ .x = 329.0, .y = 119.0 });
    try builder.addStrokedPath(&smile, .{
        .paint = .{ .solid = .{ 0.25, 0.28, 0.22, 0.70 } },
        .width = 2.0,
        .cap = .round,
        .join = .round,
    }, transform);
}
