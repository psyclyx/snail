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
//! a uniform 6× world transform (the renderer is resolution-independent,
//! so this is free sharpness) → 1920×1200 TGAs in `zig-out/`, embedded in
//! the README at width 640 so they stay crisp when zoomed.

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

const SCALE: f32 = 6.0;
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
        try self.addPrepared(curves, try prepared.paintForDesign(.{ .solid = color }), prepared.placedBy(outer));
    }

    /// Stroke `path` placed by `outer`; `width` is in the path's frame.
    fn strokePath(self: *Ctx, path: *const snail.Path, width: f32, color: [4]f32, outer: Transform2D) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const style = snail.StrokeStyle{ .paint = .{ .solid = color }, .width = width };
        const curves = try prepared.strokeCurves(self.allocator, self.scratch.allocator(), style);
        _ = self.scratch.reset(.retain_capacity);
        try self.addPrepared(curves, try prepared.paintForDesign(.{ .solid = color }), prepared.placedBy(outer));
    }

    fn strokePathRound(self: *Ctx, path: *const snail.Path, width: f32, color: [4]f32, outer: Transform2D) !void {
        var prepared = try path.prepare(self.allocator);
        defer prepared.deinit();
        const style = snail.StrokeStyle{
            .paint = .{ .solid = color },
            .width = width,
            .cap = .round,
            .join = .round,
        };
        const curves = try prepared.strokeCurves(self.allocator, self.scratch.allocator(), style);
        _ = self.scratch.reset(.retain_capacity);
        try self.addPrepared(curves, try prepared.paintForDesign(.{ .solid = color }), prepared.placedBy(outer));
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

    fn render(self: *Ctx, out_path: [*:0]const u8, width: u32, height: u32, scale: f32) !void {
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
        }, out_path, width, height, scale);
    }
};

/// `harness.renderCpu` with a supersampling world transform applied at emit time.
fn renderScaled(allocator: Allocator, scene: harness.Scene, out_path: [*:0]const u8, width: u32, height: u32, scale: f32) !void {
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, @as(usize, height) * stride);
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

    const world = Transform2D{ .xx = scale, .yy = scale };
    var ni: usize = 0;
    var nb: usize = 0;
    _ = try snail.emit.emit(instances, batches, &ni, &nb, bindings[0], scene.paths_atlas, scene.paths_picture.shapes, world, white);
    _ = try snail.emit.emit(instances, batches, &ni, &nb, bindings[1], scene.text_atlas, scene.text_picture.shapes, world, white);

    var renderer = try raster.Renderer.init(pixels, width, height, stride, .rgba8_unorm);
    try raster.draw(
        &renderer,
        harness.drawState(width, height),
        .{ .instances = instances[0..ni], .batches = batches[0..nb] },
        &.{&cache},
        null,
    );
    try harness.flipRowsInPlace(allocator, pixels, width, height);
    try harness.writeOutput(out_path, pixels, width, height);
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
    _ = try ctx.text("16 segments = one", 184, 147, label_em, ink, .regular);
    _ = try ctx.text("unhinted glyph record", 184, 158, label_em, ink, .regular);
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
    try title(ctx, "4. Draw: the pixel footprint picks band spans");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 180, .h = 158 });
    const place = glyphPlace(48, 42, 1.05);
    const band_count: f32 = 6;
    const footprint_half = Vec2{ .x = 8, .y = 10.5 };
    const footprint_lo = Vec2{
        .x = sample_pt.x - footprint_half.x,
        .y = sample_pt.y - footprint_half.y,
    };
    const footprint_hi = Vec2{
        .x = sample_pt.x + footprint_half.x,
        .y = sample_pt.y + footprint_half.y,
    };
    const tl = mapPt(place, .{ .x = 0, .y = 0 });
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });

    // Highlight every row and column touched by this deliberately enlarged
    // record-local pixel footprint. It straddles a boundary on each axis.
    const hband_first: u32 = @intFromFloat(@floor(footprint_lo.y / glyph_h * band_count));
    const hband_last: u32 = @intFromFloat(@floor(footprint_hi.y / glyph_h * band_count));
    const vband_first: u32 = @intFromFloat(@floor(footprint_lo.x / glyph_w * band_count));
    const vband_last: u32 = @intFromFloat(@floor(footprint_hi.x / glyph_w * band_count));
    const bh = (br.y - tl.y) / band_count;
    const bw = (br.x - tl.x) / band_count;
    for (hband_first..hband_last + 1) |band| {
        try ctx.fillRect(.{
            .x = tl.x,
            .y = tl.y + @as(f32, @floatFromInt(band)) * bh,
            .w = br.x - tl.x,
            .h = bh,
        }, blue_soft);
    }
    for (vband_first..vband_last + 1) |band| {
        try ctx.fillRect(.{
            .x = tl.x + @as(f32, @floatFromInt(band)) * bw,
            .y = tl.y,
            .w = bw,
            .h = br.y - tl.y,
        }, teal_soft);
    }

    try emBox(ctx, place, 1);
    try ctx.glyphStroke(place, 1.2, faint);

    const h_members = bandRange(
        true,
        @as(f32, @floatFromInt(hband_first)) * glyph_h / band_count,
        @as(f32, @floatFromInt(hband_last + 1)) * glyph_h / band_count,
    );
    const v_members = bandRange(
        false,
        @as(f32, @floatFromInt(vband_first)) * glyph_w / band_count,
        @as(f32, @floatFromInt(vband_last + 1)) * glyph_w / band_count,
    );
    var candidates: u32 = 0;
    for (glyph_segments, h_members, v_members) |q, hm, vm| {
        if (hm) try ctx.segStroke(q, place, 2.0, blue);
        if (vm) try ctx.segStroke(q, place, 2.0, teal);
        if (hm or vm) candidates += 1;
    }
    const sp = mapPt(place, sample_pt);
    const fp_tl = mapPt(place, footprint_lo);
    const fp_br = mapPt(place, footprint_hi);
    try ctx.line(fp_tl, .{ .x = fp_br.x, .y = fp_tl.y }, 1.1, amber);
    try ctx.line(.{ .x = fp_br.x, .y = fp_tl.y }, fp_br, 1.1, amber);
    try ctx.line(fp_br, .{ .x = fp_tl.x, .y = fp_br.y }, 1.1, amber);
    try ctx.line(.{ .x = fp_tl.x, .y = fp_br.y }, fp_tl, 1.1, amber);
    try ctx.fillCircle(sp.x, sp.y, 2.6, amber);

    try ctx.panel(.{ .x = 205, .y = 30, .w = 102, .h = 158 });
    _ = try ctx.text("candidates", 214, 46, label_em, muted, .regular);
    var buf: [32]u8 = undefined;
    const c1 = try std.fmt.bufPrint(&buf, "{d} of 16 curves", .{candidates});
    _ = try ctx.text(c1, 214, 62, label_em, ink, .regular);
    _ = try ctx.text("across every", 214, 73, label_em, ink, .regular);
    _ = try ctx.text("touched band", 214, 84, label_em, ink, .regular);
    _ = try ctx.text("duplicates count once", 214, 104, label_em, muted, .regular);
    _ = try ctx.text("the rest are", 214, 119, label_em, muted, .regular);
    _ = try ctx.text("never evaluated", 214, 130, label_em, muted, .regular);
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
    _ = try ctx.text("paint × coverage = premul", 196, cap_y, label_em, muted, .regular);
}

// ── README hero: a dedicated snail composition, not the demo scene ───

const HERO_LOGICAL_W: u32 = 640;
const HERO_LOGICAL_H: u32 = 200;
const HERO_W: u32 = @intFromFloat(@as(f32, HERO_LOGICAL_W) * SCALE);
const HERO_H: u32 = @intFromFloat(@as(f32, HERO_LOGICAL_H) * SCALE);

fn spiralPoint(center: Vec2, radius: f32, decay: f32, theta: f32, start_angle: f32) Vec2 {
    const r = radius * @exp(decay * (theta - start_angle));
    return .{
        .x = center.x + r * @cos(theta),
        .y = center.y + r * @sin(theta),
    };
}

fn spiralTangent(radius: f32, decay: f32, theta: f32, start_angle: f32) Vec2 {
    const r = radius * @exp(decay * (theta - start_angle));
    return .{
        .x = r * (decay * @cos(theta) - @sin(theta)),
        .y = r * (decay * @sin(theta) + @cos(theta)),
    };
}

const SpiralSpan = struct {
    p0: Vec2,
    c0: Vec2,
    c1: Vec2,
    p1: Vec2,
};

fn logarithmicSpiralSpan(center: Vec2, radius: f32, decay: f32, start_angle: f32, step: f32, i: u32) SpiralSpan {
    const theta0 = start_angle + @as(f32, @floatFromInt(i)) * step;
    const theta1 = theta0 + step;
    const p0 = spiralPoint(center, radius, decay, theta0, start_angle);
    const p1 = spiralPoint(center, radius, decay, theta1, start_angle);
    const d0 = spiralTangent(radius, decay, theta0, start_angle);
    const d1 = spiralTangent(radius, decay, theta1, start_angle);
    return .{
        .p0 = p0,
        .c0 = .{ .x = p0.x + d0.x * step / 3.0, .y = p0.y + d0.y * step / 3.0 },
        .c1 = .{ .x = p1.x - d1.x * step / 3.0, .y = p1.y - d1.y * step / 3.0 },
        .p1 = p1,
    };
}

/// Append a logarithmic spiral as cubic Hermite spans. Increasing `theta`
/// shrinks the radius, so each revolution repeats the same geometry at a
/// smaller scale.
fn logarithmicSpiral(path: *snail.Path, center: Vec2, radius: f32, inner_radius: f32, turns: f32, start_angle: f32) !void {
    const sweep = turns * 2.0 * std.math.pi;
    const decay = @log(inner_radius / radius) / sweep;
    const segment_count: u32 = 32;
    const step = sweep / @as(f32, @floatFromInt(segment_count));

    try path.moveTo(spiralPoint(center, radius, decay, start_angle, start_angle));
    for (0..segment_count) |i| {
        const span = logarithmicSpiralSpan(center, radius, decay, start_angle, step, @intCast(i));
        try path.cubicTo(span.c0, span.c1, span.p1);
    }
}

fn fillSpiralFrame(
    ctx: *Ctx,
    center: Vec2,
    radius: f32,
    inner_radius: f32,
    turns: f32,
    start_angle: f32,
    color: [4]f32,
) !void {
    const sweep = turns * 2.0 * std.math.pi;
    const decay = @log(inner_radius / radius) / sweep;
    const segment_count: u32 = 32;
    const step = sweep / @as(f32, @floatFromInt(segment_count));

    var ribbon = snail.Path.init(ctx.allocator);
    defer ribbon.deinit();
    const first = logarithmicSpiralSpan(center, radius, decay, start_angle, step, 0);
    try ribbon.moveTo(first.p0);
    for (0..segment_count) |i| {
        const span = logarithmicSpiralSpan(center, radius, decay, start_angle, step, @intCast(i));
        try ribbon.cubicTo(span.c0, span.c1, span.p1);
    }

    const last = logarithmicSpiralSpan(center, radius, decay, start_angle, step, segment_count - 1);
    const vx = first.p0.x - last.p1.x;
    try ribbon.cubicTo(
        .{ .x = last.p1.x + vx * 0.08, .y = first.p0.y - 3.0 },
        .{ .x = last.p1.x + vx * 0.68, .y = first.p0.y + 1.5 },
        first.p0,
    );
    try ribbon.close();
    try ctx.fillPath(&ribbon, color, .identity);
}

fn constructionRect(ctx: *Ctx, rect: Rect, width: f32, color: [4]f32) !void {
    const tl = Vec2{ .x = rect.x, .y = rect.y };
    const tr = Vec2{ .x = rect.x + rect.w, .y = rect.y };
    const br = Vec2{ .x = rect.x + rect.w, .y = rect.y + rect.h };
    const bl = Vec2{ .x = rect.x, .y = rect.y + rect.h };
    try ctx.line(tl, tr, width, color);
    try ctx.line(tr, br, width, color);
    try ctx.line(br, bl, width, color);
    try ctx.line(bl, tl, width, color);
}

fn fibonacciArc(ctx: *Ctx, rect: Rect, orientation: u2, width: f32, color: [4]f32) !void {
    const radius = rect.w;
    const center = switch (orientation) {
        0 => Vec2{ .x = rect.x, .y = rect.y + radius },
        1 => Vec2{ .x = rect.x + radius, .y = rect.y + radius },
        2 => Vec2{ .x = rect.x + radius, .y = rect.y },
        3 => Vec2{ .x = rect.x, .y = rect.y },
    };
    const start_angle: f32 = switch (orientation) {
        0 => -std.math.pi / 2.0,
        1 => std.math.pi,
        2 => std.math.pi / 2.0,
        3 => 0.0,
    };
    const end_angle = start_angle + std.math.pi / 2.0;
    const k: f32 = 0.55228475;
    const p0 = Vec2{
        .x = center.x + radius * @cos(start_angle),
        .y = center.y + radius * @sin(start_angle),
    };
    const p1 = Vec2{
        .x = center.x + radius * @cos(end_angle),
        .y = center.y + radius * @sin(end_angle),
    };
    const c0 = Vec2{
        .x = p0.x - radius * k * @sin(start_angle),
        .y = p0.y + radius * k * @cos(start_angle),
    };
    const c1 = Vec2{
        .x = p1.x + radius * k * @sin(end_angle),
        .y = p1.y - radius * k * @cos(end_angle),
    };
    var arc = snail.Path.init(ctx.allocator);
    defer arc.deinit();
    try arc.moveTo(p0);
    try arc.cubicTo(c0, c1, p1);
    try ctx.strokePathRound(&arc, width, color, .identity);
}

fn diagramBanner(ctx: *Ctx) !void {
    const hero_bg = srgb(.{ 0.945, 0.95, 0.91, 1.0 });
    const hero_ink = srgb(.{ 0.075, 0.15, 0.18, 1.0 });
    const hero_copy = srgb(.{ 0.68, 0.34, 0.20, 1.0 });
    const study_ink = srgb(.{ 0.24, 0.17, 0.11, 0.96 });
    const study_guide = srgb(.{ 0.35, 0.30, 0.23, 0.22 });
    const study_faint = srgb(.{ 0.35, 0.30, 0.23, 0.11 });
    const shell_arc = srgb(.{ 0.38, 0.31, 0.24, 0.48 });
    const shell_wash = srgb(.{ 0.80, 0.70, 0.52, 1.0 });
    const study_teal = srgb(.{ 0.07, 0.37, 0.37, 0.92 });
    const study_sanguine = srgb(.{ 0.64, 0.25, 0.14, 1.0 });
    const body_color = srgb(.{ 0.28, 0.39, 0.46, 1.0 });
    const body_light = srgb(.{ 0.55, 0.68, 0.70, 0.76 });
    const body_mark = srgb(.{ 0.12, 0.24, 0.29, 0.34 });

    try ctx.fillRect(.{ .x = 0, .y = 0, .w = HERO_LOGICAL_W, .h = HERO_LOGICAL_H }, hero_bg);

    _ = try ctx.text("snail", 38, 96, 68, hero_ink, .bold);
    _ = try ctx.text("every size fits.", 42, 145, 19, hero_copy, .regular);

    // Fibonacci-square scaffold for a 233:144 golden rectangle.
    const x0: f32 = 356;
    const fs: f32 = 0.82;
    const y0: f32 = @as(f32, @floatFromInt(HERO_LOGICAL_H)) - 61.0 - 144.0 * fs;
    const squares = [_]struct { x: f32, y: f32, side: f32, label: []const u8 }{
        .{ .x = 0, .y = 0, .side = 144, .label = "144" },
        .{ .x = 144, .y = 55, .side = 89, .label = "89" },
        .{ .x = 178, .y = 0, .side = 55, .label = "55" },
        .{ .x = 144, .y = 0, .side = 34, .label = "34" },
        .{ .x = 144, .y = 34, .side = 21, .label = "21" },
        .{ .x = 165, .y = 42, .side = 13, .label = "13" },
        .{ .x = 170, .y = 34, .side = 8, .label = "8" },
        .{ .x = 165, .y = 34, .side = 5, .label = "5" },
        .{ .x = 165, .y = 39, .side = 3, .label = "3" },
        .{ .x = 168, .y = 40, .side = 2, .label = "2" },
    };

    const outer = Rect{ .x = x0, .y = y0, .w = 233 * fs, .h = 144 * fs };
    // Mirror the construction so the shell's aperture faces the head.
    const center = Vec2{ .x = x0 + (233.0 - 169.5) * fs, .y = y0 + (144.0 - 40.5) * fs };
    const first = Vec2{ .x = x0 + 233.0 * fs, .y = y0 + 144.0 * fs };
    const dx = first.x - center.x;
    const dy = first.y - center.y;
    const outer_radius = @sqrt(dx * dx + dy * dy);
    const start_angle = std.math.atan2(dy, dx);
    const phi: f32 = 1.61803398875;
    var spiral_inner = outer_radius;
    for (0..9) |_| spiral_inner /= phi;

    // A low, fluid body sits behind the construction. Its broad shapes and
    // muted color deliberately contrast with the shell's measured linework.
    var body = snail.Path.init(ctx.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 348, .y = 151 });
    try body.cubicTo(.{ .x = 375, .y = 132 }, .{ .x = 405, .y = 119 }, .{ .x = 440, .y = 124 });
    try body.cubicTo(.{ .x = 472, .y = 129 }, .{ .x = 496, .y = 143 }, .{ .x = 531, .y = 139 });
    try body.cubicTo(.{ .x = 550, .y = 137 }, .{ .x = 563, .y = 124 }, .{ .x = 572, .y = 105 });
    try body.cubicTo(.{ .x = 580, .y = 88 }, .{ .x = 595, .y = 82 }, .{ .x = 608, .y = 91 });
    try body.cubicTo(.{ .x = 622, .y = 101 }, .{ .x = 621, .y = 121 }, .{ .x = 611, .y = 135 });
    try body.cubicTo(.{ .x = 598, .y = 151 }, .{ .x = 573, .y = 158 }, .{ .x = 541, .y = 159 });
    try body.cubicTo(.{ .x = 501, .y = 161 }, .{ .x = 471, .y = 151 }, .{ .x = 438, .y = 148 });
    try body.cubicTo(.{ .x = 403, .y = 145 }, .{ .x = 375, .y = 152 }, .{ .x = 356, .y = 160 });
    try body.quadTo(.{ .x = 347, .y = 164 }, .{ .x = 340, .y = 160 });
    try body.quadTo(.{ .x = 341, .y = 155 }, .{ .x = 348, .y = 151 });
    try body.close();
    try ctx.fillPath(&body, body_color, .identity);
    try ctx.strokePathRound(&body, 1.8, hero_ink, .identity);

    var foot_light = snail.Path.init(ctx.allocator);
    defer foot_light.deinit();
    try foot_light.moveTo(.{ .x = 365, .y = 157 });
    try foot_light.cubicTo(.{ .x = 419, .y = 148 }, .{ .x = 510, .y = 163 }, .{ .x = 583, .y = 148 });
    try ctx.strokePathRound(&foot_light, 2.7, body_light, .identity);

    var neck_fold = snail.Path.init(ctx.allocator);
    defer neck_fold.deinit();
    try neck_fold.moveTo(.{ .x = 536, .y = 148 });
    try neck_fold.cubicTo(.{ .x = 551, .y = 143 }, .{ .x = 562, .y = 133 }, .{ .x = 568, .y = 119 });
    try ctx.strokePathRound(&neck_fold, 0.9, body_mark, .identity);

    var near_feeler = snail.Path.init(ctx.allocator);
    defer near_feeler.deinit();
    try near_feeler.moveTo(.{ .x = 584, .y = 91 });
    try near_feeler.cubicTo(.{ .x = 581, .y = 79 }, .{ .x = 581, .y = 68 }, .{ .x = 586, .y = 59 });
    try ctx.strokePathRound(&near_feeler, 2.7, body_color, .identity);
    var far_feeler = snail.Path.init(ctx.allocator);
    defer far_feeler.deinit();
    try far_feeler.moveTo(.{ .x = 598, .y = 90 });
    try far_feeler.cubicTo(.{ .x = 607, .y = 80 }, .{ .x = 618, .y = 72 }, .{ .x = 622, .y = 63 });
    try ctx.strokePathRound(&far_feeler, 2.7, body_color, .identity);
    try ctx.fillCircle(586, 57, 5.8, hero_ink);
    try ctx.fillCircle(622, 61, 5.8, hero_ink);
    try ctx.fillCircle(588, 55, 1.6, white);
    try ctx.fillCircle(624, 59, 1.6, white);

    var smile = snail.Path.init(ctx.allocator);
    defer smile.deinit();
    try smile.moveTo(.{ .x = 578, .y = 119 });
    try smile.quadTo(.{ .x = 587, .y = 127 }, .{ .x = 595, .y = 117 });
    try ctx.strokePathRound(&smile, 1.55, hero_ink, .identity);

    // One flat shell field follows the logarithmic spiral, then returns along
    // a gently bowed version of the radial construction line. The teal curve
    // below remains its exact outer boundary.
    try fillSpiralFrame(ctx, center, outer_radius, spiral_inner, -2.25, start_angle, shell_wash);

    try constructionRect(ctx, outer, 0.52, study_guide);
    try ctx.line(
        .{ .x = outer.x, .y = outer.y },
        .{ .x = outer.x + outer.w, .y = outer.y + outer.h },
        0.38,
        study_faint,
    );
    try ctx.line(
        .{ .x = outer.x, .y = outer.y + outer.h },
        .{ .x = outer.x + outer.w, .y = outer.y },
        0.38,
        study_faint,
    );

    for (squares, 0..) |sq, i| {
        const rect = Rect{
            .x = x0 + (233.0 - sq.x - sq.side) * fs,
            .y = y0 + (144.0 - sq.y - sq.side) * fs,
            .w = sq.side * fs,
            .h = sq.side * fs,
        };
        try constructionRect(ctx, rect, if (i < 4) 0.44 else 0.28, if (i % 2 == 0) study_guide else study_faint);
        const orientation: u2 = @intCast(3 - (i % 4));
        try fibonacciArc(ctx, rect, orientation ^ 1, if (i < 6) 1.34 else 0.76, shell_arc);
    }

    // φ-scaled radii sampled every quarter turn.
    var radius = outer_radius;
    var inner_radius = outer_radius;
    for (0..10) |i| {
        const theta = start_angle - @as(f32, @floatFromInt(i)) * std.math.pi / 2.0;
        const point = Vec2{
            .x = center.x + radius * @cos(theta),
            .y = center.y + radius * @sin(theta),
        };
        try ctx.line(center, point, if (i % 2 == 0) 0.36 else 0.24, study_guide);
        try ctx.ringCircle(point.x, point.y, if (i < 5) 1.25 else 0.85, 0.52, study_sanguine);
        inner_radius = radius;
        radius /= phi;
    }

    // Exact logarithmic golden spiral against the quarter-circle approximation.
    var exact_spiral = snail.Path.init(ctx.allocator);
    defer exact_spiral.deinit();
    try logarithmicSpiral(&exact_spiral, center, outer_radius, inner_radius, -2.25, start_angle);
    try ctx.strokePathRound(&exact_spiral, 1.48, study_teal, .identity);

    // Principal construction axes deliberately exceed the golden rectangle.
    try ctx.line(
        .{ .x = outer.x - 24, .y = center.y },
        .{ .x = outer.x + outer.w + 20, .y = center.y },
        0.34,
        study_guide,
    );
    try ctx.line(
        .{ .x = center.x, .y = 12 },
        .{ .x = center.x, .y = 190 },
        0.34,
        study_guide,
    );
    try ctx.fillCircle(center.x, center.y, 1.45, study_sanguine);

    // Labels are emitted after the complete construction. The smallest cells
    // get a shell-colored knockout so control points cannot obscure them at
    // README display size.
    for (squares, 0..) |sq, i| {
        if (i >= 7) break;
        const rect = Rect{
            .x = x0 + (233.0 - sq.x - sq.side) * fs,
            .y = y0 + (144.0 - sq.y - sq.side) * fs,
            .w = sq.side * fs,
            .h = sq.side * fs,
        };
        const label_x = rect.x + 2.2;
        const label_y = rect.y + 5.9;
        if (i >= 3) {
            const label_w = try ctx.textWidth(sq.label, 5.0, .bold);
            try ctx.fillRect(.{
                .x = label_x - 0.8,
                .y = label_y - 4.8,
                .w = label_w + 1.6,
                .h = 5.9,
            }, shell_wash);
        }
        _ = try ctx.text(sq.label, label_x, label_y, 5.0, study_ink, .bold);
    }

    // Dimension line and working annotations.
    const dimension_y: f32 = 174;
    try ctx.line(.{ .x = outer.x, .y = dimension_y }, .{ .x = outer.x + outer.w, .y = dimension_y }, 0.40, study_ink);
    try ctx.line(.{ .x = outer.x, .y = dimension_y - 3 }, .{ .x = outer.x, .y = dimension_y + 3 }, 0.40, study_ink);
    try ctx.line(.{ .x = outer.x + outer.w, .y = dimension_y - 3 }, .{ .x = outer.x + outer.w, .y = dimension_y + 3 }, 0.40, study_ink);
    try ctx.textCentered("233 : 144 ~ φ", outer.x + outer.w / 2.0, dimension_y + 9, 5.2, study_ink, .regular);
    _ = try ctx.text("r(n+1) = r(n) / φ", center.x + 18, center.y - 17, 5.2, study_ink, .regular);
    _ = try ctx.text("Δθ = π/2", center.x + 58, center.y + 9, 5.0, study_sanguine, .regular);
    _ = try ctx.text("φ", center.x - 34, center.y + 16, 5.7, study_teal, .regular);
}

// ── Entry ───────────────────────────────────────────────────────────

const diagrams = [_]struct { name: [*:0]const u8, width: u32 = W, height: u32 = H, build: *const fn (*Ctx) anyerror!void }{
    .{ .name = "zig-out/banner.tga", .width = HERO_W, .height = HERO_H, .build = diagramBanner },
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
        .{ .font = &font_regular, .font_id = 0 },
        .{ .font = &font_bold, .font_id = 1, .weight = .bold },
    });
    defer faces.deinit();

    const pool = try snail.PagePool.init(allocator, .{
        .max_pages = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 15,
    });
    defer pool.deinit();

    for (diagrams) |d| {
        var ctx = try Ctx.init(allocator, pool, &faces);
        defer ctx.deinit();
        try d.build(&ctx);
        try ctx.render(d.name, d.width, d.height, SCALE);
    }
}
