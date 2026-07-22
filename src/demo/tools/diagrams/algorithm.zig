//! README algorithm diagrams, rendered by snail itself through the CPU
//! backend.
//!
//! Seven diagrams walk the Slug pipeline over one shared toy glyph — a
//! typographic 'o' authored as 16 explicit quadratic segments (8 per
//! contour, hole contour reversed) — so every panel shows the same shape
//! and every annotation is computed, not drawn by eye: band membership
//! comes from real curve bounds, ray crossings from the actual quadratic
//! roots, winding sums from the crossing signs, and edge-coverage cells
//! from supersampled inside tests.
//!
//! Diagrams are authored in logical 320×200 coordinates and emitted under
//! a uniform 3× world transform (the renderer is resolution-independent,
//! so this is free sharpness) → 960×600 TGAs in `zig-out/`, embedded in
//! the README at width 320 so they stay crisp when zoomed.

const std = @import("std");
const snail = @import("snail");
const support = @import("support");
const assets_data = @import("assets");
const harness = @import("../../screenshot/harness.zig");
const raster = @import("snail-raster");

const Allocator = std.mem.Allocator;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const Rect = snail.Rect;

const SCALE: f32 = 3.0;
const LOGICAL_W: u32 = 320;
const LOGICAL_H: u32 = 200;
const W: u32 = @intFromFloat(@as(f32, LOGICAL_W) * SCALE);
const H: u32 = @intFromFloat(@as(f32, LOGICAL_H) * SCALE);

// ── Palette (authored sRGB, converted at the boundary) ──────────────

const srgb = snail.color.srgbToLinearColor;

const white = [4]f32{ 1, 1, 1, 1 };
const border = srgb(.{ 0.82, 0.85, 0.90, 1.0 });
const ink = srgb(.{ 0.09, 0.10, 0.14, 1.0 });
const muted = srgb(.{ 0.38, 0.43, 0.50, 1.0 });
const faint = srgb(.{ 0.72, 0.76, 0.82, 1.0 });
const grid_line = srgb(.{ 0.88, 0.90, 0.94, 1.0 });
const blue = srgb(.{ 0.13, 0.36, 0.84, 1.0 });
const blue_soft = srgb(.{ 0.84, 0.90, 1.0, 1.0 });
const teal = srgb(.{ 0.05, 0.52, 0.47, 1.0 });
const teal_soft = srgb(.{ 0.82, 0.94, 0.92, 1.0 });
const rose = srgb(.{ 0.84, 0.22, 0.42, 1.0 });
const amber = srgb(.{ 0.80, 0.52, 0.08, 1.0 });
const amber_soft = srgb(.{ 1.0, 0.93, 0.78, 1.0 });
const glyph_fill = srgb(.{ 0.55, 0.65, 0.85, 0.45 });

// ── Toy glyph: a typographic 'o' as explicit quadratic segments ─────
//
// Local frame is 100×124, y-down. Outer contour counter-clockwise, inner
// contour clockwise (opposite orientation ⇒ non-zero winding cancels in
// the counter). Eight 45° arcs per contour; the control point of each arc
// is the tangent intersection at distance r/cos(22.5°).

const Quad = struct { p0: Vec2, c: Vec2, p1: Vec2 };

const glyph_cx: f32 = 50;
const glyph_cy: f32 = 62;
const glyph_w: f32 = 100;
const glyph_h: f32 = 124;

fn ellipseArcs(comptime rx: f32, comptime ry: f32, comptime reversed: bool) [8]Quad {
    @setEvalBranchQuota(100_000);
    var out: [8]Quad = undefined;
    const sec: f32 = 1.0 / @cos(std.math.pi / 8.0);
    for (0..8) |i| {
        const a0 = @as(f32, @floatFromInt(i)) * std.math.pi / 4.0;
        const a1 = a0 + std.math.pi / 4.0;
        const am = (a0 + a1) * 0.5;
        const p0 = Vec2{ .x = glyph_cx + rx * @cos(a0), .y = glyph_cy + ry * @sin(a0) };
        const p1 = Vec2{ .x = glyph_cx + rx * @cos(a1), .y = glyph_cy + ry * @sin(a1) };
        const c = Vec2{ .x = glyph_cx + rx * sec * @cos(am), .y = glyph_cy + ry * sec * @sin(am) };
        out[i] = if (reversed) .{ .p0 = p1, .c = c, .p1 = p0 } else .{ .p0 = p0, .c = c, .p1 = p1 };
    }
    if (reversed) std.mem.reverse(Quad, &out);
    return out;
}

const outer_arcs = ellipseArcs(40, 46, false);
const inner_arcs = ellipseArcs(18, 32, true);
const glyph_segments = outer_arcs ++ inner_arcs; // 16 segments

fn segBoundsY(q: Quad) [2]f32 {
    return .{ @min(q.p0.y, @min(q.c.y, q.p1.y)), @max(q.p0.y, @max(q.c.y, q.p1.y)) };
}
fn segBoundsX(q: Quad) [2]f32 {
    return .{ @min(q.p0.x, @min(q.c.x, q.p1.x)), @max(q.p0.x, @max(q.c.x, q.p1.x)) };
}

fn quadAt(q: Quad, t: f32) Vec2 {
    const u = 1.0 - t;
    return .{
        .x = u * u * q.p0.x + 2 * u * t * q.c.x + t * t * q.p1.x,
        .y = u * u * q.p0.y + 2 * u * t * q.c.y + t * t * q.p1.y,
    };
}

const Crossing = struct { pos: Vec2, sign: i32 };

/// Roots of the segment against a horizontal line y = y0 (t ∈ [0,1)).
/// `sign` is the crossing direction (dy/dt > 0 ⇒ +1).
fn hCrossings(q: Quad, y0: f32, out: *[2]Crossing) usize {
    const a = q.p0.y - 2 * q.c.y + q.p1.y;
    const b = 2 * (q.c.y - q.p0.y);
    const c = q.p0.y - y0;
    var roots: [2]f32 = undefined;
    var n: usize = 0;
    if (@abs(a) < 1e-6) {
        if (@abs(b) > 1e-6) {
            roots[n] = -c / b;
            n += 1;
        }
    } else {
        const disc = b * b - 4 * a * c;
        if (disc >= 0) {
            const s = @sqrt(disc);
            roots[n] = (-b - s) / (2 * a);
            n += 1;
            roots[n] = (-b + s) / (2 * a);
            n += 1;
        }
    }
    var count: usize = 0;
    for (roots[0..n]) |t| {
        if (t < 0 or t >= 1) continue;
        const dy = 2 * (1 - t) * (q.c.y - q.p0.y) + 2 * t * (q.p1.y - q.c.y);
        out[count] = .{ .pos = quadAt(q, t), .sign = if (dy > 0) 1 else -1 };
        count += 1;
    }
    return count;
}

/// Same against a vertical line x = x0.
fn vCrossings(q: Quad, x0: f32, out: *[2]Crossing) usize {
    const flipped = Quad{
        .p0 = .{ .x = q.p0.y, .y = q.p0.x },
        .c = .{ .x = q.c.y, .y = q.c.x },
        .p1 = .{ .x = q.p1.y, .y = q.p1.x },
    };
    var tmp: [2]Crossing = undefined;
    const n = hCrossings(flipped, x0, &tmp);
    for (tmp[0..n], 0..) |cr, i| out[i] = .{ .pos = .{ .x = cr.pos.y, .y = cr.pos.x }, .sign = cr.sign };
    return n;
}

/// Non-zero winding inside test via a +x horizontal ray (local coords).
fn insideGlyph(p: Vec2) bool {
    var w: i32 = 0;
    for (glyph_segments) |q| {
        var tmp: [2]Crossing = undefined;
        const n = hCrossings(q, p.y, &tmp);
        for (tmp[0..n]) |cr| {
            if (cr.pos.x > p.x) w += cr.sign;
        }
    }
    return w != 0;
}

// ── Scene builder ───────────────────────────────────────────────────

const Ctx = struct {
    allocator: Allocator,
    scratch: std.heap.ArenaAllocator,
    pool: *snail.PagePool,
    faces: *snail.Faces,

    path_curves: std.ArrayList(snail.GlyphCurves) = .empty,
    path_entries: std.ArrayList(snail.AtlasEntry) = .empty,
    path_shapes: std.ArrayList(snail.Shape) = .empty,
    next_id: u32 = 0,

    text_atlas: snail.Atlas,
    text_pics: std.ArrayList(support.Picture) = .empty,

    fn init(allocator: Allocator, pool: *snail.PagePool, faces: *snail.Faces) snail.PagePool.IdentityError!Ctx {
        return .{
            .allocator = allocator,
            .scratch = std.heap.ArenaAllocator.init(allocator),
            .pool = pool,
            .faces = faces,
            .text_atlas = try snail.Atlas.init(allocator, pool),
        };
    }

    fn deinit(self: *Ctx) void {
        for (self.text_pics.items) |*p| p.deinit();
        self.text_pics.deinit(self.allocator);
        self.text_atlas.deinit();
        self.path_shapes.deinit(self.allocator);
        self.path_entries.deinit(self.allocator);
        for (self.path_curves.items) |*c| c.deinit();
        self.path_curves.deinit(self.allocator);
        self.scratch.deinit();
    }

    fn addPrepared(self: *Ctx, curves: snail.GlyphCurves, paint: snail.Paint, transform: Transform2D) !void {
        try self.path_curves.append(self.allocator, curves);
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = self.next_id };
        self.next_id += 1;
        try self.path_entries.append(self.allocator, .{
            .key = key,
            .curves = self.path_curves.items[self.path_curves.items.len - 1],
            .paint = paint,
        });
        try self.path_shapes.append(self.allocator, .{ .key = key, .local_transform = transform, .local_color = white });
    }

    /// Fill `path` (authored in any frame) placed by `outer`.
    fn fillPath(self: *Ctx, path: *const snail.Path, color: [4]f32, outer: Transform2D) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const curves = try prepared.fillCurves(self.allocator, self.scratch.allocator());
        _ = self.scratch.reset(.retain_capacity);
        try self.addPrepared(curves, prepared.paintForDesign(.{ .solid = color }), prepared.placedBy(outer));
    }

    /// Stroke `path` placed by `outer`; `width` is in the path's frame.
    fn strokePath(self: *Ctx, path: *const snail.Path, width: f32, color: [4]f32, outer: Transform2D) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const style = snail.StrokeStyle{ .paint = .{ .solid = color }, .width = width };
        const curves = try prepared.strokeCurves(self.allocator, self.scratch.allocator(), style);
        _ = self.scratch.reset(.retain_capacity);
        try self.addPrepared(curves, prepared.paintForDesign(.{ .solid = color }), prepared.placedBy(outer));
    }

    fn fillRect(self: *Ctx, rect: Rect, color: [4]f32) !void {
        var p = try support.unitRectPath(self.allocator);
        defer p.deinit();
        try self.fillPath(&p, color, support.placeRect(rect));
    }

    fn panel(self: *Ctx, rect: Rect) !void {
        var p = try support.unitRoundedRectPathFor(self.allocator, rect, 6.0);
        defer p.deinit();
        try self.fillPath(&p, white, support.placeRectUniform(rect));
        try self.strokePath(&p, support.unitStrokeWidth(rect, 1.0), border, support.placeRectUniform(rect));
    }

    fn fillCircle(self: *Ctx, cx: f32, cy: f32, r: f32, color: [4]f32) !void {
        var p = try support.unitEllipsePath(self.allocator);
        defer p.deinit();
        try self.fillPath(&p, color, support.placeRect(.{ .x = cx - r, .y = cy - r, .w = 2 * r, .h = 2 * r }));
    }

    fn ringCircle(self: *Ctx, cx: f32, cy: f32, r: f32, w: f32, color: [4]f32) !void {
        var p = try support.unitEllipsePath(self.allocator);
        defer p.deinit();
        try self.strokePath(&p, w / (2 * r), color, support.placeRect(.{ .x = cx - r, .y = cy - r, .w = 2 * r, .h = 2 * r }));
    }

    /// Oriented thin rectangle from `a` to `b`, `w` thick — crisp straight
    /// lines at any angle (unit-frame authored, so no f16 wobble).
    fn line(self: *Ctx, a: Vec2, b: Vec2, w: f32, color: [4]f32) !void {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 1e-6) return;
        const nx = -dy / len;
        const ny = dx / len;
        var p = try support.unitRectPath(self.allocator);
        defer p.deinit();
        try self.fillPath(&p, color, .{
            .xx = dx,
            .xy = w * nx,
            .tx = a.x - 0.5 * w * nx,
            .yx = dy,
            .yy = w * ny,
            .ty = a.y - 0.5 * w * ny,
        });
    }

    fn dashedLine(self: *Ctx, a: Vec2, b: Vec2, w: f32, dash: f32, gap: f32, color: [4]f32) !void {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = @sqrt(dx * dx + dy * dy);
        var s: f32 = 0;
        while (s < len) : (s += dash + gap) {
            const e = @min(s + dash, len);
            try self.line(
                .{ .x = a.x + dx * s / len, .y = a.y + dy * s / len },
                .{ .x = a.x + dx * e / len, .y = a.y + dy * e / len },
                w,
                color,
            );
        }
    }

    fn arrow(self: *Ctx, a: Vec2, b: Vec2, w: f32, color: [4]f32) !void {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 1e-6) return;
        const ux = dx / len;
        const uy = dy / len;
        const head: f32 = 4.5;
        const shaft_end = Vec2{ .x = b.x - ux * head, .y = b.y - uy * head };
        try self.line(a, shaft_end, w, color);
        var p = snail.Path.init(self.allocator);
        defer p.deinit();
        try p.moveTo(.{ .x = b.x, .y = b.y });
        try p.lineTo(.{ .x = b.x - ux * head - uy * head * 0.45, .y = b.y - uy * head + ux * head * 0.45 });
        try p.lineTo(.{ .x = b.x - ux * head + uy * head * 0.45, .y = b.y - uy * head - ux * head * 0.45 });
        try p.close();
        try self.fillPath(&p, color, .identity);
    }

    /// Build a Path of the toy glyph (both contours) in its local frame.
    fn glyphPath(self: *Ctx) !snail.Path {
        var p = snail.Path.init(self.allocator);
        errdefer p.deinit();
        try p.moveTo(outer_arcs[0].p0);
        for (outer_arcs) |q| try p.quadTo(q.c, q.p1);
        try p.close();
        try p.moveTo(inner_arcs[0].p0);
        for (inner_arcs) |q| try p.quadTo(q.c, q.p1);
        try p.close();
        return p;
    }

    fn glyphFill(self: *Ctx, place: Transform2D, color: [4]f32) !void {
        var p = try self.glyphPath();
        defer p.deinit();
        try self.fillPath(&p, color, place);
    }

    fn glyphStroke(self: *Ctx, place: Transform2D, width_local: f32, color: [4]f32) !void {
        var p = try self.glyphPath();
        defer p.deinit();
        try self.strokePath(&p, width_local, color, place);
    }

    /// Stroke one segment of the toy glyph under `place`.
    fn segStroke(self: *Ctx, q: Quad, place: Transform2D, width_local: f32, color: [4]f32) !void {
        var p = snail.Path.init(self.allocator);
        defer p.deinit();
        try p.moveTo(q.p0);
        try p.quadTo(q.c, q.p1);
        try self.strokePath(&p, width_local, color, place);
    }

    fn text(self: *Ctx, str: []const u8, x: f32, y: f32, em: f32, color: [4]f32, weight: snail.FontWeight) !f32 {
        var shaped = try snail.shape(self.allocator, self.faces, str, .{ .style = .{ .weight = weight } });
        defer shaped.deinit();
        try snail.recordUnhintedRun(&self.text_atlas, self.allocator, self.faces, &shaped, .{});
        const pic = try support.placeRun(self.allocator, &shaped, null, .{
            .baseline = .{ .x = x, .y = y },
            .em = em,
            .color = color,
        });
        try self.text_pics.append(self.allocator, pic);
        return shaped.advanceX() * em;
    }

    /// Measure without emitting (for centering).
    fn textWidth(self: *Ctx, str: []const u8, em: f32, weight: snail.FontWeight) !f32 {
        var shaped = try snail.shape(self.allocator, self.faces, str, .{ .style = .{ .weight = weight } });
        defer shaped.deinit();
        return shaped.advanceX() * em;
    }

    fn textCentered(self: *Ctx, str: []const u8, cx: f32, y: f32, em: f32, color: [4]f32, weight: snail.FontWeight) !void {
        const w = try self.textWidth(str, em, weight);
        _ = try self.text(str, cx - w / 2, y, em, color, weight);
    }

    fn render(self: *Ctx, out_path: [*:0]const u8) !void {
        var paths_atlas = try snail.Atlas.from(self.allocator, self.pool, self.path_entries.items);
        defer paths_atlas.deinit();
        var paths_picture = try support.Picture.from(self.allocator, self.path_shapes.items);
        defer paths_picture.deinit();

        var refs: std.ArrayList(*const support.Picture) = .empty;
        defer refs.deinit(self.allocator);
        for (self.text_pics.items) |*p| try refs.append(self.allocator, p);
        var text_picture = try support.Picture.concat(self.allocator, refs.items);
        defer text_picture.deinit();

        try renderScaled(self.allocator, .{
            .pool = self.pool,
            .paths_atlas = &paths_atlas,
            .text_atlas = &self.text_atlas,
            .paths_picture = &paths_picture,
            .text_picture = &text_picture,
        }, out_path);
    }
};

/// `harness.renderCpu` with the 3× world transform applied at emit time.
fn renderScaled(allocator: Allocator, scene: harness.Scene, out_path: [*:0]const u8) !void {
    const stride: u32 = W * 4;
    const pixels = try allocator.alloc(u8, @as(usize, H) * stride);
    defer allocator.free(pixels);
    harness.fillBgRgba8(pixels);

    var cache = try raster.DeviceAtlas.init(allocator, scene.pool, .{
        .max_bindings = 4,
        .layer_info_height = 128,
        .max_images = 4,
    });
    defer cache.deinit();
    var bindings: [2]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{ scene.paths_atlas, scene.text_atlas }, &bindings);

    const budget = harness.shapeBudget(scene);
    const instances = try allocator.alloc(snail.render.records.Instance, budget);
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, budget);
    defer allocator.free(batches);

    const world = Transform2D{ .xx = SCALE, .yy = SCALE };
    var ni: usize = 0;
    var nb: usize = 0;
    _ = try snail.emit.emit(instances, batches, &ni, &nb, bindings[0], scene.paths_atlas, scene.paths_picture.shapes, world, white);
    _ = try snail.emit.emit(instances, batches, &ni, &nb, bindings[1], scene.text_atlas, scene.text_picture.shapes, world, white);

    var renderer = try raster.Renderer.init(pixels, W, H, stride);
    try raster.draw(
        &renderer,
        harness.drawState(W, H),
        .{ .instances = instances[0..ni], .batches = batches[0..nb] },
        &.{&cache},
        null,
    );
    try harness.flipRowsInPlace(allocator, pixels, W, H);
    try harness.writeOutput(out_path, pixels, W, H);
}

// ── Shared layout ───────────────────────────────────────────────────

const title_em: f32 = 12;
const label_em: f32 = 8.5;
const small_em: f32 = 7.5;

fn title(ctx: *Ctx, str: []const u8) !void {
    _ = try ctx.text(str, 13, 20, title_em, ink, .bold);
}

/// Place transform for the toy glyph's 100×124 local frame into a rect.
fn glyphPlace(x: f32, y: f32, scale: f32) Transform2D {
    return .{ .xx = scale, .yy = scale, .tx = x, .ty = y };
}

fn mapPt(place: Transform2D, p: Vec2) Vec2 {
    return place.applyPoint(p);
}

/// Faint em-box + grid behind a placed glyph.
fn emBox(ctx: *Ctx, place: Transform2D, cells: u32) !void {
    const tl = mapPt(place, .{ .x = 0, .y = 0 });
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });
    var i: u32 = 1;
    while (i < cells) : (i += 1) {
        const fx = tl.x + (br.x - tl.x) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(cells));
        const fy = tl.y + (br.y - tl.y) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(cells));
        try ctx.line(.{ .x = fx, .y = tl.y }, .{ .x = fx, .y = br.y }, 0.4, grid_line);
        try ctx.line(.{ .x = tl.x, .y = fy }, .{ .x = br.x, .y = fy }, 0.4, grid_line);
    }
    var p = try support.unitRectPath(ctx.allocator);
    defer p.deinit();
    try ctx.strokePath(&p, 0.6 / (br.x - tl.x), faint, support.placeRect(.{ .x = tl.x, .y = tl.y, .w = br.x - tl.x, .h = br.y - tl.y }));
}

// ── Diagram 1: curve records ────────────────────────────────────────

fn diagramCurves(ctx: *Ctx) !void {
    try title(ctx, "1. Prepare: outlines stay curves");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 150, .h = 158 });
    const place = glyphPlace(38, 44, 1.0);
    try emBox(ctx, place, 4);
    try ctx.glyphStroke(place, 1.4, ink);

    // Highlight one segment with its control points.
    const hi = outer_arcs[7]; // upper-right arc (y-down: angles 315°..360°)
    try ctx.segStroke(hi, place, 2.4, blue);
    const p0 = mapPt(place, hi.p0);
    const p1 = mapPt(place, hi.p1);
    const c = mapPt(place, hi.c);
    try ctx.line(p0, c, 0.7, rose);
    try ctx.line(c, p1, 0.7, rose);
    try ctx.fillCircle(p0.x, p0.y, 2.0, ink);
    try ctx.fillCircle(p1.x, p1.y, 2.0, ink);
    try ctx.ringCircle(c.x, c.y, 2.2, 1.2, rose);
    _ = try ctx.text("control", c.x + 5, c.y + 1, small_em, rose, .regular);
    _ = try ctx.text("on-curve", p1.x + 6, p1.y + 8, small_em, muted, .regular);

    // Curve texture strip: 16 segments × 4 texels, highlighted segment lit.
    try ctx.panel(.{ .x = 175, .y = 30, .w = 132, .h = 158 });
    _ = try ctx.text("curve texture", 184, 46, label_em, muted, .regular);
    const strip_x: f32 = 184;
    const strip_y: f32 = 56;
    const cell: f32 = 5.4;
    const gapx: f32 = 1.2;
    const group_w = 4 * cell + 3 * gapx;
    for (0..16) |seg| {
        const row: f32 = @floatFromInt(seg / 4);
        const col: f32 = @floatFromInt(seg % 4);
        const gx = strip_x + col * (group_w + 4);
        const gy = strip_y + row * (cell + 6);
        const lit = seg == 7;
        for (0..4) |t| {
            const tx = gx + @as(f32, @floatFromInt(t)) * (cell + gapx);
            try ctx.fillRect(.{ .x = tx, .y = gy, .w = cell, .h = cell }, if (lit) blue else blue_soft);
        }
    }
    _ = try ctx.text("4 texels per segment,", 184, 118, label_em, muted, .regular);
    _ = try ctx.text("em coordinates, f16", 184, 129, label_em, muted, .regular);
    _ = try ctx.text("16 segments = one glyph", 184, 147, label_em, ink, .regular);
    _ = try ctx.text("record, any size", 184, 158, label_em, ink, .regular);
}

// ── Diagram 2: bands ────────────────────────────────────────────────

fn bandRange(comptime horizontal: bool, lo: f32, hi: f32) [16]bool {
    var out: [16]bool = undefined;
    for (glyph_segments, 0..) |q, i| {
        const b = if (horizontal) segBoundsY(q) else segBoundsX(q);
        out[i] = b[0] < hi and b[1] > lo;
    }
    return out;
}

fn diagramBands(ctx: *Ctx) !void {
    try title(ctx, "2. Prepare: bands index the curves");

    const band_count: u32 = 6;

    // Horizontal bands (left), highlight band 2.
    try ctx.panel(.{ .x = 13, .y = 30, .w = 145, .h = 158 });
    const lp = glyphPlace(36, 44, 0.95);
    {
        const tl = mapPt(lp, .{ .x = 0, .y = 0 });
        const br = mapPt(lp, .{ .x = glyph_w, .y = glyph_h });
        const bh = (br.y - tl.y) / @as(f32, @floatFromInt(band_count));
        for (0..band_count) |i| {
            const fy = tl.y + bh * @as(f32, @floatFromInt(i));
            const color = if (i == 2) amber_soft else if (i % 2 == 0) blue_soft else white;
            try ctx.fillRect(.{ .x = tl.x, .y = fy, .w = br.x - tl.x, .h = bh }, color);
        }
        try emBox(ctx, lp, 1);
        try ctx.glyphStroke(lp, 1.2, faint);
        const lo = glyph_h * 2.0 / @as(f32, @floatFromInt(band_count));
        const hi = glyph_h * 3.0 / @as(f32, @floatFromInt(band_count));
        const members = bandRange(true, lo, hi);
        for (glyph_segments, members) |q, m| {
            if (m) try ctx.segStroke(q, lp, 2.0, amber);
        }
        _ = try ctx.text("horizontal bands", 36, 182, label_em, muted, .regular);
    }

    // Vertical bands (right), highlight band 4.
    try ctx.panel(.{ .x = 162, .y = 30, .w = 145, .h = 158 });
    const rp = glyphPlace(186, 44, 0.95);
    {
        const tl = mapPt(rp, .{ .x = 0, .y = 0 });
        const br = mapPt(rp, .{ .x = glyph_w, .y = glyph_h });
        const bw = (br.x - tl.x) / @as(f32, @floatFromInt(band_count));
        for (0..band_count) |i| {
            const fx = tl.x + bw * @as(f32, @floatFromInt(i));
            const color = if (i == 4) amber_soft else if (i % 2 == 0) teal_soft else white;
            try ctx.fillRect(.{ .x = fx, .y = tl.y, .w = bw, .h = br.y - tl.y }, color);
        }
        try emBox(ctx, rp, 1);
        try ctx.glyphStroke(rp, 1.2, faint);
        const lo = glyph_w * 4.0 / @as(f32, @floatFromInt(band_count));
        const hi = glyph_w * 5.0 / @as(f32, @floatFromInt(band_count));
        const members = bandRange(false, lo, hi);
        for (glyph_segments, members) |q, m| {
            if (m) try ctx.segStroke(q, rp, 2.0, amber);
        }
        _ = try ctx.text("vertical bands", 186, 182, label_em, muted, .regular);
    }
}

// ── Diagram 3: instanced quads ──────────────────────────────────────

fn diagramQuad(ctx: *Ctx) !void {
    try title(ctx, "3. Draw: one instanced quad per glyph");

    // Screen panel: rotated glyph + bounding quad + fragment.
    try ctx.panel(.{ .x = 13, .y = 30, .w = 150, .h = 158 });
    {
        // Device grid.
        var gx: f32 = 25;
        while (gx < 155) : (gx += 16) try ctx.line(.{ .x = gx, .y = 38 }, .{ .x = gx, .y = 180 }, 0.4, grid_line);
        var gy: f32 = 44;
        while (gy < 182) : (gy += 16) try ctx.line(.{ .x = 21, .y = gy }, .{ .x = 155, .y = gy }, 0.4, grid_line);
    }
    const ang: f32 = -0.32;
    const s: f32 = 0.78;
    const rot = Transform2D{
        .xx = s * @cos(ang),
        .xy = -s * @sin(ang),
        .yx = s * @sin(ang),
        .yy = s * @cos(ang),
        .tx = 58,
        .ty = 74,
    };
    try ctx.glyphFill(rot, glyph_fill);
    try ctx.glyphStroke(rot, 1.2, blue);
    // Bounding quad = transformed em box corners.
    const q0 = mapPt(rot, .{ .x = 0, .y = 0 });
    const q1 = mapPt(rot, .{ .x = glyph_w, .y = 0 });
    const q2 = mapPt(rot, .{ .x = glyph_w, .y = glyph_h });
    const q3 = mapPt(rot, .{ .x = 0, .y = glyph_h });
    try ctx.line(q0, q1, 0.9, blue);
    try ctx.line(q1, q2, 0.9, blue);
    try ctx.line(q2, q3, 0.9, blue);
    try ctx.line(q3, q0, 0.9, blue);
    for ([_]Vec2{ q0, q1, q2, q3 }) |q| try ctx.fillCircle(q.x, q.y, 1.8, blue);
    const frag_local = Vec2{ .x = 78, .y = 84 };
    const frag = mapPt(rot, frag_local);
    try ctx.fillCircle(frag.x, frag.y, 2.6, amber);
    _ = try ctx.text("screen", 24, 182, label_em, muted, .regular);

    // Glyph-space panel: upright glyph, mapped fragment.
    try ctx.panel(.{ .x = 175, .y = 30, .w = 132, .h = 158 });
    const up = glyphPlace(196, 44, 0.9);
    try emBox(ctx, up, 4);
    try ctx.glyphStroke(up, 1.3, ink);
    const frag_up = mapPt(up, frag_local);
    try ctx.fillCircle(frag_up.x, frag_up.y, 2.6, amber);
    try ctx.dashedLine(frag, .{ .x = frag_up.x - 4, .y = frag_up.y }, 0.8, 3.0, 2.6, amber);
    _ = try ctx.text("glyph space", 196, 182, label_em, muted, .regular);
    _ = try ctx.text("inverse", 152, 96, small_em, amber, .regular);
    _ = try ctx.text("transform", 152, 105, small_em, amber, .regular);
}

// ── Diagram 4: pick bands ───────────────────────────────────────────

const sample_pt = Vec2{ .x = 76, .y = 72 }; // inside the ring, centered in its bands

fn diagramPickBands(ctx: *Ctx) !void {
    try title(ctx, "4. Draw: the sample picks two bands");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 180, .h = 158 });
    const place = glyphPlace(48, 42, 1.05);
    const band_count: f32 = 6;
    const tl = mapPt(place, .{ .x = 0, .y = 0 });
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });

    // The sample's h band (row) and v band (column).
    const hband: f32 = @floor(sample_pt.y / glyph_h * band_count);
    const vband: f32 = @floor(sample_pt.x / glyph_w * band_count);
    const bh = (br.y - tl.y) / band_count;
    const bw = (br.x - tl.x) / band_count;
    try ctx.fillRect(.{ .x = tl.x, .y = tl.y + hband * bh, .w = br.x - tl.x, .h = bh }, blue_soft);
    try ctx.fillRect(.{ .x = tl.x + vband * bw, .y = tl.y, .w = bw, .h = br.y - tl.y }, teal_soft);

    try emBox(ctx, place, 1);
    try ctx.glyphStroke(place, 1.2, faint);

    const h_members = bandRange(true, hband * glyph_h / band_count, (hband + 1) * glyph_h / band_count);
    const v_members = bandRange(false, vband * glyph_w / band_count, (vband + 1) * glyph_w / band_count);
    var candidates: u32 = 0;
    for (glyph_segments, h_members, v_members) |q, hm, vm| {
        if (hm) try ctx.segStroke(q, place, 2.0, blue);
        if (vm) try ctx.segStroke(q, place, 2.0, teal);
        if (hm or vm) candidates += 1;
    }
    const sp = mapPt(place, sample_pt);
    try ctx.fillCircle(sp.x, sp.y, 2.6, amber);

    try ctx.panel(.{ .x = 205, .y = 30, .w = 102, .h = 158 });
    _ = try ctx.text("candidates", 214, 46, label_em, muted, .regular);
    var buf: [32]u8 = undefined;
    const c1 = try std.fmt.bufPrint(&buf, "{d} of 16 curves", .{candidates});
    _ = try ctx.text(c1, 214, 62, label_em, ink, .regular);
    _ = try ctx.text("in the sample's", 214, 73, label_em, ink, .regular);
    _ = try ctx.text("two bands", 214, 84, label_em, ink, .regular);
    _ = try ctx.text("the rest are", 214, 104, label_em, muted, .regular);
    _ = try ctx.text("never touched", 214, 115, label_em, muted, .regular);
}

// ── Diagram 5: ray roots ────────────────────────────────────────────

fn diagramRoots(ctx: *Ctx) !void {
    try title(ctx, "5. Draw: solve ray roots per candidate");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });
    const place = glyphPlace(96, 42, 1.05);
    const tl = mapPt(place, .{ .x = 0, .y = 0 });
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });
    try emBox(ctx, place, 1);
    try ctx.glyphStroke(place, 1.4, ink);

    const sp = mapPt(place, sample_pt);
    // Horizontal ray.
    try ctx.line(.{ .x = tl.x - 14, .y = sp.y }, .{ .x = br.x + 14, .y = sp.y }, 0.9, blue);
    // Vertical ray.
    try ctx.line(.{ .x = sp.x, .y = tl.y - 6 }, .{ .x = sp.x, .y = br.y + 6 }, 0.9, teal);
    try ctx.fillCircle(sp.x, sp.y, 2.6, amber);

    // Real crossings with signs.
    for (glyph_segments) |q| {
        var tmp: [2]Crossing = undefined;
        const hn = hCrossings(q, sample_pt.y, &tmp);
        for (tmp[0..hn]) |cr| {
            const m = mapPt(place, cr.pos);
            try ctx.fillCircle(m.x, m.y, 2.2, rose);
            const s = if (cr.sign > 0) "+1" else "-1";
            _ = try ctx.text(s, m.x - 3, m.y - 6, small_em, rose, .regular);
        }
        const vn = vCrossings(q, sample_pt.x, &tmp);
        for (tmp[0..vn]) |cr| {
            const m = mapPt(place, cr.pos);
            try ctx.fillCircle(m.x, m.y, 2.2, rose);
            const s = if (cr.sign > 0) "+1" else "-1";
            _ = try ctx.text(s, m.x + 5, m.y + 3, small_em, rose, .regular);
        }
    }
    _ = try ctx.text("horizontal ray", 224, 132, label_em, blue, .regular);
    _ = try ctx.text("vertical ray", 224, 145, label_em, teal, .regular);
    _ = try ctx.text("quadratic roots,", 224, 165, label_em, muted, .regular);
    _ = try ctx.text("signed by direction", 224, 176, label_em, muted, .regular);
}

// ── Diagram 6: winding ──────────────────────────────────────────────

fn diagramWinding(ctx: *Ctx) !void {
    try title(ctx, "6. Draw: signed roots sum to winding");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });
    const place = glyphPlace(64, 42, 1.05);
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });
    try ctx.glyphFill(place, glyph_fill);
    try ctx.glyphStroke(place, 1.4, ink);

    // Distinct ray heights so the two rays (and their crossing sums) read
    // separately.
    const a_local = Vec2{ .x = 76, .y = 44 }; // in the ring, upper right
    const b_local = Vec2{ .x = 50, .y = 74 }; // in the hole
    const ray_end_x = br.x + 26;

    for ([_]struct { p: Vec2, color: [4]f32, label: []const u8, ly: f32 }{
        .{ .p = a_local, .color = amber, .label = "A", .ly = -8 },
        .{ .p = b_local, .color = teal, .label = "B", .ly = -8 },
    }) |s| {
        const m = mapPt(place, s.p);
        try ctx.line(m, .{ .x = ray_end_x, .y = m.y }, 0.9, s.color);
        try ctx.fillCircle(m.x, m.y, 2.6, s.color);
        _ = try ctx.text(s.label, m.x - 2.5, m.y + s.ly, label_em, s.color, .bold);
        var w: i32 = 0;
        for (glyph_segments) |q| {
            var tmp: [2]Crossing = undefined;
            const n = hCrossings(q, s.p.y, &tmp);
            for (tmp[0..n]) |cr| {
                if (cr.pos.x <= s.p.x) continue;
                w += cr.sign;
                const c = mapPt(place, cr.pos);
                try ctx.fillCircle(c.x, c.y, 2.2, rose);
                const sign = if (cr.sign > 0) "+1" else "-1";
                _ = try ctx.text(sign, c.x - 3, c.y - 5, small_em, rose, .regular);
            }
        }
        std.debug.assert((s.p.x == a_local.x) == (w != 0)); // A filled, B empty
    }
    _ = try ctx.text("A: crossings sum to w = 1", 196, 84, label_em, ink, .regular);
    _ = try ctx.text("non-zero: filled", 196, 95, label_em, amber, .regular);
    _ = try ctx.text("B: +1 and -1 cancel, w = 0", 196, 121, label_em, ink, .regular);
    _ = try ctx.text("zero: the hole stays empty", 196, 132, label_em, teal, .regular);
    _ = try ctx.text("h and v estimates are", 196, 158, label_em, muted, .regular);
    _ = try ctx.text("weighted together", 196, 169, label_em, muted, .regular);
}

// ── Diagram 7: edge coverage ────────────────────────────────────────

/// The quadratic restricted to `[t0, t1]` (exact — a quadratic's
/// restriction is a quadratic; the control point follows the tangent).
fn subQuad(q: Quad, t0: f32, t1: f32) Quad {
    const p0 = quadAt(q, t0);
    const p1 = quadAt(q, t1);
    const dx = (1 - t0) * (q.c.x - q.p0.x) + t0 * (q.p1.x - q.c.x);
    const dy = (1 - t0) * (q.c.y - q.p0.y) + t0 * (q.p1.y - q.c.y);
    return .{ .p0 = p0, .c = .{ .x = p0.x + dx * (t1 - t0), .y = p0.y + dy * (t1 - t0) }, .p1 = p1 };
}

fn diagramCoverage(ctx: *Ctx) !void {
    try title(ctx, "7. Draw: roots near the pixel = coverage");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });

    // Zoom onto a diagonal stretch of the outer edge (upper right): cells
    // are device pixels, filled with their true (supersampled) coverage.
    const cols: u32 = 11;
    const rows: u32 = 5;
    const cell: f32 = 24;
    const gx0: f32 = 26;
    const gy0: f32 = 48;
    const zoom: f32 = 10.0; // logical px per local unit
    const win_w = @as(f32, @floatFromInt(cols)) * cell / zoom;
    const win_h = @as(f32, @floatFromInt(rows)) * cell / zoom;
    const lx0: f32 = 79.8 - win_w / 2.0;
    const ly0: f32 = 32.4 - win_h / 2.0;
    const place = Transform2D{ .xx = zoom, .yy = zoom, .tx = gx0 - lx0 * zoom, .ty = gy0 - ly0 * zoom };

    var best_cell: ?struct { x: f32, y: f32, alpha: f32 } = null;
    for (0..rows) |r| {
        for (0..cols) |c| {
            const cx0 = lx0 + @as(f32, @floatFromInt(c)) * cell / zoom;
            const cy0 = ly0 + @as(f32, @floatFromInt(r)) * cell / zoom;
            var hits: u32 = 0;
            const n: u32 = 12;
            for (0..n) |sy| {
                for (0..n) |sx| {
                    const p = Vec2{
                        .x = cx0 + (@as(f32, @floatFromInt(sx)) + 0.5) / @as(f32, @floatFromInt(n)) * cell / zoom,
                        .y = cy0 + (@as(f32, @floatFromInt(sy)) + 0.5) / @as(f32, @floatFromInt(n)) * cell / zoom,
                    };
                    if (insideGlyph(p)) hits += 1;
                }
            }
            const alpha = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(n * n));
            const px = gx0 + @as(f32, @floatFromInt(c)) * cell;
            const py = gy0 + @as(f32, @floatFromInt(r)) * cell;
            if (alpha > 0.001) {
                var color = ink;
                color[3] = alpha;
                try ctx.fillRect(.{ .x = px, .y = py, .w = cell, .h = cell }, color);
            }
            // Remember the most fractional cell for annotation.
            if (alpha > 0.02 and alpha < 0.98) {
                if (best_cell == null or @abs(alpha - 0.5) < @abs(best_cell.?.alpha - 0.5))
                    best_cell = .{ .x = px, .y = py, .alpha = alpha };
            }
        }
    }
    // Pixel grid over the cells.
    for (0..cols + 1) |c| {
        const px = gx0 + @as(f32, @floatFromInt(c)) * cell;
        try ctx.line(.{ .x = px, .y = gy0 }, .{ .x = px, .y = gy0 + @as(f32, @floatFromInt(rows)) * cell }, 0.5, faint);
    }
    for (0..rows + 1) |r| {
        const py = gy0 + @as(f32, @floatFromInt(r)) * cell;
        try ctx.line(.{ .x = gx0, .y = py }, .{ .x = gx0 + @as(f32, @floatFromInt(cols)) * cell, .y = py }, 0.5, faint);
    }
    // The true edge over the top, clipped to the window by restricting each
    // arc to its in-window parameter range.
    const margin: f32 = 0.25;
    for (outer_arcs) |q| {
        var tmin: f32 = 2;
        var tmax: f32 = -1;
        var i: u32 = 0;
        while (i <= 200) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / 200.0;
            const p = quadAt(q, t);
            if (p.x >= lx0 - margin and p.x <= lx0 + win_w + margin and
                p.y >= ly0 - margin and p.y <= ly0 + win_h + margin)
            {
                tmin = @min(tmin, t);
                tmax = @max(tmax, t);
            }
        }
        if (tmax > tmin) try ctx.segStroke(subQuad(q, tmin, tmax), place, 0.13, blue);
    }
    // Annotate the most fractional pixel.
    if (best_cell) |bc| {
        var pth = try support.unitRectPath(ctx.allocator);
        defer pth.deinit();
        try ctx.strokePath(&pth, 1.6 / cell, amber, support.placeRect(.{ .x = bc.x, .y = bc.y, .w = cell, .h = cell }));
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "\u{03b1} = {d:.2}", .{bc.alpha});
        _ = try ctx.text(s, bc.x + cell + 6, bc.y + cell * 0.5 + 3, label_em, amber, .regular);
    }

    const cap_y = gy0 + @as(f32, @floatFromInt(rows)) * cell + 14;
    _ = try ctx.text("one cell = one device pixel", 26, cap_y, label_em, muted, .regular);
    _ = try ctx.text("coverage times paint,", 196, cap_y, label_em, muted, .regular);
    _ = try ctx.text("premultiplied linear out", 196, cap_y + 11, label_em, muted, .regular);
}

// ── Entry ───────────────────────────────────────────────────────────

const diagrams = [_]struct { name: [*:0]const u8, build: *const fn (*Ctx) anyerror!void }{
    .{ .name = "zig-out/algorithm-curves.tga", .build = diagramCurves },
    .{ .name = "zig-out/algorithm-bands.tga", .build = diagramBands },
    .{ .name = "zig-out/algorithm-quad.tga", .build = diagramQuad },
    .{ .name = "zig-out/algorithm-sample-bands.tga", .build = diagramPickBands },
    .{ .name = "zig-out/algorithm-roots.tga", .build = diagramRoots },
    .{ .name = "zig-out/algorithm-winding.tga", .build = diagramWinding },
    .{ .name = "zig-out/algorithm-alpha.tga", .build = diagramCoverage },
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var font_regular = try snail.Font.init(assets_data.noto_sans_regular);
    var font_bold = try snail.Font.init(assets_data.noto_sans_bold);
    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font_regular },
        .{ .font = &font_bold, .weight = .bold },
    });
    defer faces.deinit();

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 15,
    });
    defer pool.deinit();

    for (diagrams) |d| {
        var ctx = try Ctx.init(allocator, pool, &faces);
        defer ctx.deinit();
        try d.build(&ctx);
        try ctx.render(d.name);
    }
}
