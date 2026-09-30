//! README algorithm diagrams, rendered by snail itself through the CPU
//! backend.
//!
//! Seven diagrams walk the Slug pipeline over one shared toy glyph — a
//! typographic 'o' authored as 16 explicit quadratic segments (8 per
//! contour, hole contour reversed) — so every panel shows the same shape
//! and every annotation is computed, not drawn by eye: band membership
//! follows the packer's rule over tight curve bounds, ray crossings come
//! from the actual quadratic roots, winding sums from the crossing signs,
//! and edge-coverage cells from snail-raster drawing the glyph at one
//! device pixel per cell.
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
/// Storage order: the hole contour first, so the highlighted outer arc in
/// diagram 1 is the record's last segment (index 15).
const glyph_segments = inner_arcs ++ outer_arcs;

const Box = struct { min: Vec2, max: Vec2 };

/// Tight bounds of a quadratic, as `QuadBezier.boundingBox` computes them.
fn segBounds(q: Quad) Box {
    var b = Box{
        .min = .{ .x = @min(q.p0.x, q.p1.x), .y = @min(q.p0.y, q.p1.y) },
        .max = .{ .x = @max(q.p0.x, q.p1.x), .y = @max(q.p0.y, q.p1.y) },
    };
    inline for (.{ "x", "y" }) |axis| {
        const a = @field(q.p0, axis);
        const c = @field(q.c, axis);
        const e = @field(q.p1, axis);
        const denom = a - 2 * c + e;
        if (@abs(denom) > 1e-10) {
            const t = (a - c) / denom;
            if (t > 0 and t < 1) {
                const v = @field(quadAt(q, t), axis);
                @field(b.min, axis) = @min(@field(b.min, axis), v);
                @field(b.max, axis) = @max(@field(b.max, axis), v);
            }
        }
    }
    return b;
}

/// The outline's bounds: bands tile this box, and the draw quad covers it.
fn glyphBounds() Box {
    var b = segBounds(glyph_segments[0]);
    for (glyph_segments[1..]) |q| {
        const s = segBounds(q);
        b.min = .{ .x = @min(b.min.x, s.min.x), .y = @min(b.min.y, s.min.y) };
        b.max = .{ .x = @max(b.max.x, s.max.x), .y = @max(b.max.y, s.max.y) };
    }
    return b;
}

/// Bands per axis the packer picks for 16 curves (band_texture.bandCount).
const band_count: u32 = 6;

const Axis = enum { rows, columns };

/// Band span of one segment, mirroring band_texture.recordMembership: the
/// tight bounds, widened by the packer's epsilon (1/1024 em), floored into
/// uniform bands over the outline's bounds.
fn segBands(q: Quad, axis: Axis) [2]u32 {
    const gb = glyphBounds();
    const sb = segBounds(q);
    const eps = glyph_h / 1024.0;
    const lo, const hi, const origin, const size = switch (axis) {
        .rows => .{ sb.min.y, sb.max.y, gb.min.y, gb.max.y - gb.min.y },
        .columns => .{ sb.min.x, sb.max.x, gb.min.x, gb.max.x - gb.min.x },
    };
    const n: f32 = @floatFromInt(band_count);
    const top: f32 = n - 1;
    return .{
        @intFromFloat(@floor(std.math.clamp((lo - eps - origin) * n / size, 0, top))),
        @intFromFloat(@floor(std.math.clamp((hi + eps - origin) * n / size, 0, top))),
    };
}

/// Which segments a band span [first, last] lists.
fn bandMembers(axis: Axis, first: u32, last: u32) [16]bool {
    var out: [16]bool = undefined;
    for (glyph_segments, &out) |q, *m| {
        const span = segBands(q, axis);
        m.* = span[0] <= last and span[1] >= first;
    }
    return out;
}

/// Band `i`'s extent along its axis, in the local frame.
fn bandExtent(axis: Axis, i: u32) [2]f32 {
    const gb = glyphBounds();
    const origin, const size = switch (axis) {
        .rows => .{ gb.min.y, gb.max.y - gb.min.y },
        .columns => .{ gb.min.x, gb.max.x - gb.min.x },
    };
    const step = size / @as(f32, @floatFromInt(band_count));
    return .{ origin + step * @as(f32, @floatFromInt(i)), origin + step * @as(f32, @floatFromInt(i + 1)) };
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
    sources: []const snail.FontSource,
    outline_context: snail.OutlineContext,

    path_curves: std.ArrayList(snail.GlyphCurves) = .empty,
    path_entries: std.ArrayList(snail.AtlasGeometryEntry) = .empty,
    path_shapes: std.ArrayList(snail.Shape) = .empty,
    next_id: u32 = 0,

    text_atlas: snail.Atlas,
    text_pics: std.ArrayList(support.Picture) = .empty,

    fn init(
        allocator: Allocator,
        pool: *snail.PagePool,
        faces: *snail.Faces,
        sources: []const snail.FontSource,
    ) snail.PagePool.IdentityError!Ctx {
        return .{
            .allocator = allocator,
            .scratch = std.heap.ArenaAllocator.init(allocator),
            .pool = pool,
            .faces = faces,
            .sources = sources,
            .outline_context = snail.OutlineContext.init(allocator, allocator),
            .text_atlas = try snail.Atlas.init(allocator, pool),
        };
    }

    fn deinit(self: *Ctx) void {
        self.outline_context.deinit();
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
            .curves = self.path_curves.items[self.path_curves.items.len - 1].view(),
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
        var plan = try snail.planRuns(
            &self.text_atlas,
            self.allocator,
            self.sources,
            &.{&shaped},
            .{ .unhinted = .{} },
        );
        defer plan.deinit();
        try prepareOutlinesAndApply(
            self.allocator,
            &self.text_atlas,
            &plan,
            &self.outline_context,
        );
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
        const tagged = try self.allocator.alloc(snail.AtlasEntry, self.path_entries.items.len);
        defer self.allocator.free(tagged);
        for (self.path_entries.items, tagged) |entry, *out| out.* = .{ .geometry = entry };
        var paths_atlas = try snail.Atlas.from(self.allocator, self.pool, .{ .entries = tagged });
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

fn prepareOutlinesAndApply(
    allocator: Allocator,
    atlas: *snail.Atlas,
    plan: *const snail.PreparePlan,
    context: *snail.OutlineContext,
) !void {
    const owned = try allocator.alloc(?snail.prepared.OwnedRecord, plan.requests().len);
    defer allocator.free(owned);
    @memset(owned, null);
    defer for (owned) |*record| {
        if (record.*) |*value| value.deinit();
    };

    const results = try allocator.alloc(?snail.prepared.RecordView, plan.requests().len);
    defer allocator.free(results);
    @memset(results, null);

    for (plan.requests(), 0..) |request, i| {
        owned[i] = try context.prepare(request);
        results[i] = owned[i].?.view();
    }
    try plan.applyInPlace(allocator, atlas, results);
}

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

fn outlineRect(ctx: *Ctx, r: Rect, w: f32, color: [4]f32) !void {
    const tl = Vec2{ .x = r.x, .y = r.y };
    const tr = Vec2{ .x = r.x + r.w, .y = r.y };
    const bl = Vec2{ .x = r.x, .y = r.y + r.h };
    const br = Vec2{ .x = r.x + r.w, .y = r.y + r.h };
    try ctx.line(tl, tr, w, color);
    try ctx.line(tr, br, w, color);
    try ctx.line(br, bl, w, color);
    try ctx.line(bl, tl, w, color);
}

fn diagramCurves(ctx: *Ctx) !void {
    try title(ctx, "1. Prepare: outlines stay curves");

    // The outline: every dot is a segment boundary.
    try ctx.panel(.{ .x = 13, .y = 30, .w = 150, .h = 158 });
    const place = glyphPlace(38, 38, 1.0);
    try emBox(ctx, place, 4);
    try ctx.glyphStroke(place, 1.4, ink);
    for (glyph_segments) |q| {
        const p = mapPt(place, q.p0);
        try ctx.fillCircle(p.x, p.y, 1.4, ink);
    }
    const hi_index = 15;
    const hi = glyph_segments[hi_index];
    try ctx.segStroke(hi, place, 2.4, blue);
    const p0 = mapPt(place, hi.p0);
    const p1 = mapPt(place, hi.c);
    const p2 = mapPt(place, hi.p1);
    try ctx.line(p0, p1, 0.7, rose);
    try ctx.line(p1, p2, 0.7, rose);
    try ctx.fillCircle(p0.x, p0.y, 2.0, ink);
    try ctx.fillCircle(p2.x, p2.y, 2.0, ink);
    try ctx.ringCircle(p1.x, p1.y, 2.2, 1.2, rose);
    _ = try ctx.text("p0", p0.x + 3, p0.y - 3, small_em, ink, .regular);
    _ = try ctx.text("p1", p1.x + 5, p1.y + 3, small_em, rose, .regular);
    _ = try ctx.text("p2", p2.x + 5, p2.y + 6, small_em, ink, .regular);
    _ = try ctx.text("16 quadratic segments", 38, 180, label_em, muted, .regular);

    // A stretch of the shared curve texture: this glyph is one contiguous
    // run of texel pairs between other glyphs' runs.
    try ctx.panel(.{ .x = 175, .y = 30, .w = 132, .h = 158 });
    _ = try ctx.text("curve texture", 184, 46, label_em, muted, .regular);
    const other = srgb(.{ 0.90, 0.91, 0.94, 1.0 });
    const texel: f32 = 7;
    const pair_step: f32 = 2 * texel + 0.8 + 2.6;
    const row_step: f32 = 10;
    const strip = Vec2{ .x = 184, .y = 54 };
    const pairs_per_row = 6;
    const run_start_pair = 4; // other glyphs precede this one in the row
    var hi_pair: Vec2 = undefined;
    for (0..pairs_per_row * 4) |pair| {
        const px = strip.x + @as(f32, @floatFromInt(pair % pairs_per_row)) * pair_step;
        const py = strip.y + @as(f32, @floatFromInt(pair / pairs_per_row)) * row_step;
        const seg: isize = @as(isize, @intCast(pair)) - run_start_pair;
        const color = if (seg == hi_index) blue else if (seg >= 0 and seg < glyph_segments.len) blue_soft else other;
        if (seg == hi_index) hi_pair = .{ .x = px, .y = py };
        try ctx.fillRect(.{ .x = px, .y = py, .w = texel, .h = texel }, color);
        try ctx.fillRect(.{ .x = px + texel + 0.8, .y = py, .w = texel, .h = texel }, color);
    }

    // The highlighted segment's two RGBA16F texels, channel by channel.
    const call_y: f32 = 106;
    const call_h: f32 = 14;
    const chan: f32 = 13;
    const texel_x = [2]f32{ 184, 184 + 4 * chan + 4 };
    const call_r = texel_x[1] + 4 * chan;
    try ctx.line(.{ .x = hi_pair.x, .y = hi_pair.y + texel }, .{ .x = texel_x[0], .y = call_y - 10 }, 0.4, blue);
    try ctx.line(.{ .x = hi_pair.x + 2 * texel + 0.8, .y = hi_pair.y + texel }, .{ .x = call_r, .y = call_y - 10 }, 0.4, blue);
    const slots = [2][2]?struct { name: []const u8, color: [4]f32 }{
        .{ .{ .name = "p0", .color = ink }, .{ .name = "p1", .color = rose } },
        .{ .{ .name = "p2", .color = ink }, null },
    };
    const channel_names = [4][]const u8{ "R", "G", "B", "A" };
    for (texel_x, slots) |tx, texel_slots| {
        try ctx.fillRect(.{ .x = tx, .y = call_y, .w = 4 * chan, .h = call_h }, white);
        for (channel_names, 0..) |name, ch| {
            const cx = tx + (@as(f32, @floatFromInt(ch)) + 0.5) * chan;
            try ctx.textCentered(name, cx, call_y - 2.5, small_em, muted, .regular);
            if (ch > 0) try ctx.line(.{ .x = tx + @as(f32, @floatFromInt(ch)) * chan, .y = call_y }, .{ .x = tx + @as(f32, @floatFromInt(ch)) * chan, .y = call_y + call_h }, 0.4, faint);
        }
        // Each point fills two channels: x, then y.
        for (texel_slots, 0..) |slot, s| {
            const sx = tx + @as(f32, @floatFromInt(s)) * 2 * chan;
            if (slot) |named| {
                try ctx.textCentered("x", sx + 0.5 * chan, call_y + call_h / 2 + 2.6, small_em, named.color, .regular);
                try ctx.textCentered("y", sx + 1.5 * chan, call_y + call_h / 2 + 2.6, small_em, named.color, .regular);
                const bracket_y = call_y + call_h + 3;
                try ctx.line(.{ .x = sx + 2, .y = bracket_y }, .{ .x = sx + 2 * chan - 2, .y = bracket_y }, 0.6, named.color);
                try ctx.textCentered(named.name, sx + chan, bracket_y + 8, small_em, named.color, .regular);
            } else {
                try ctx.fillRect(.{ .x = sx, .y = call_y, .w = 2 * chan, .h = call_h }, other);
            }
        }
        try outlineRect(ctx, .{ .x = tx, .y = call_y, .w = 4 * chan, .h = call_h }, 0.8, blue);
    }
    _ = try ctx.text("channel: one 16-bit float", 184, call_y + call_h + 23, small_em, ink, .regular);
    _ = try ctx.text("texel: 4 channels = 64 bits", 184, call_y + call_h + 32, small_em, muted, .regular);
    _ = try ctx.text("segment: 2 texels = 16 bytes", 184, call_y + call_h + 41, small_em, muted, .regular);

    const legend_y: f32 = 176;
    try ctx.fillRect(.{ .x = 184, .y = legend_y - 5, .w = 5, .h = 5 }, blue_soft);
    _ = try ctx.text("this glyph", 192, legend_y, small_em, muted, .regular);
    try ctx.fillRect(.{ .x = 238, .y = legend_y - 5, .w = 5, .h = 5 }, other);
    _ = try ctx.text("other glyphs", 246, legend_y, small_em, muted, .regular);
}

// ── Diagram 2: bands ────────────────────────────────────────────────

/// Draw a glyph in a panel with its bands along `axis`, one highlighted,
/// and list the highlighted band's segments as numbered chips — ordered as
/// the packer stores them (descending max x for rows, topmost first for
/// columns).
fn bandPanel(ctx: *Ctx, panel_x: f32, axis: Axis, highlight: u32, caption: []const u8) !void {
    try ctx.panel(.{ .x = panel_x, .y = 30, .w = 145, .h = 158 });
    const gb = glyphBounds();
    const scale: f32 = 0.95;
    const left = panel_x + (145 - (gb.max.x - gb.min.x) * scale) / 2;
    const place = glyphPlace(left - gb.min.x * scale, 42 - gb.min.y * scale, scale);
    const tl = mapPt(place, gb.min);
    const br = mapPt(place, gb.max);
    const stripe = srgb(.{ 0.95, 0.96, 0.98, 1.0 });
    for (0..band_count) |i_usize| {
        const i: u32 = @intCast(i_usize);
        const color = if (i == highlight) amber_soft else if (i % 2 == 0) stripe else white;
        const ext = bandExtent(axis, i);
        const r: Rect = switch (axis) {
            .rows => .{ .x = tl.x, .y = mapPt(place, .{ .x = 0, .y = ext[0] }).y, .w = br.x - tl.x, .h = (ext[1] - ext[0]) * scale },
            .columns => .{ .x = mapPt(place, .{ .x = ext[0], .y = 0 }).x, .y = tl.y, .w = (ext[1] - ext[0]) * scale, .h = br.y - tl.y },
        };
        try ctx.fillRect(r, color);
    }
    try outlineRect(ctx, .{ .x = tl.x, .y = tl.y, .w = br.x - tl.x, .h = br.y - tl.y }, 0.6, faint);
    try ctx.glyphStroke(place, 1.2, faint);

    const members = bandMembers(axis, highlight, highlight);
    var order: [16]u8 = undefined;
    var count: usize = 0;
    const center = Vec2{ .x = glyph_cx, .y = glyph_cy };
    for (glyph_segments, members, 0..) |q, m, i| {
        if (!m) continue;
        order[count] = @intCast(i);
        count += 1;
        try ctx.segStroke(q, place, 2.0, amber);
        // Number the segment just outside its midpoint.
        const mid = quadAt(q, 0.5);
        const dx = mid.x - center.x;
        const dy = mid.y - center.y;
        const len = @sqrt(dx * dx + dy * dy);
        const out_dir: f32 = if (i < inner_arcs.len) -1 else 1; // hole labels point inward
        const lp = mapPt(place, .{ .x = mid.x + out_dir * 7 * dx / len, .y = mid.y + out_dir * 7 * dy / len });
        var buf: [4]u8 = undefined;
        try ctx.textCentered(try std.fmt.bufPrint(&buf, "{d}", .{i}), lp.x, lp.y + 2.5, small_em, amber, .regular);
    }
    const Sort = struct {
        axis: Axis,
        fn key(self: @This(), i: u8) f32 {
            const q = glyph_segments[i];
            return switch (self.axis) {
                .rows => @max(q.p0.x, @max(q.c.x, q.p1.x)),
                .columns => -@min(q.p0.y, @min(q.c.y, q.p1.y)),
            };
        }
        fn lessThan(self: @This(), a: u8, b: u8) bool {
            return self.key(a) > self.key(b);
        }
    };
    std.mem.sort(u8, order[0..count], Sort{ .axis = axis }, Sort.lessThan);

    const chip_y = br.y + 16;
    _ = try ctx.text("list", tl.x, chip_y + 6.5, small_em, muted, .regular);
    var cx = tl.x + 15;
    for (order[0..count]) |i| {
        try ctx.fillRect(.{ .x = cx, .y = chip_y, .w = 9.4, .h = 9 }, amber_soft);
        var buf: [4]u8 = undefined;
        try ctx.textCentered(try std.fmt.bufPrint(&buf, "{d}", .{i}), cx + 4.7, chip_y + 6.8, small_em, amber, .regular);
        cx += 10.4;
    }
    _ = try ctx.text(caption, tl.x, 182, label_em, muted, .regular);
}

fn diagramBands(ctx: *Ctx) !void {
    try title(ctx, "2. Prepare: bands index the curves");
    try bandPanel(ctx, 13, .rows, 2, "horizontal bands");
    try bandPanel(ctx, 162, .columns, 4, "vertical bands");
}

// ── Diagram 3: instanced quads ──────────────────────────────────────

fn diagramQuad(ctx: *Ctx) !void {
    try title(ctx, "3. Draw: one instanced quad per glyph");

    // The quad covers the outline's bounds, dilated a little on screen so
    // edge pixels still get a fragment.
    const gb = glyphBounds();
    const dilate: f32 = 4;
    const corners = [4]Vec2{
        .{ .x = gb.min.x - dilate, .y = gb.min.y - dilate },
        .{ .x = gb.max.x + dilate, .y = gb.min.y - dilate },
        .{ .x = gb.max.x + dilate, .y = gb.max.y + dilate },
        .{ .x = gb.min.x - dilate, .y = gb.max.y + dilate },
    };

    try ctx.panel(.{ .x = 13, .y = 30, .w = 150, .h = 158 });
    {
        var gx: f32 = 25;
        while (gx < 155) : (gx += 16) try ctx.line(.{ .x = gx, .y = 38 }, .{ .x = gx, .y = 180 }, 0.4, grid_line);
        var gy: f32 = 44;
        while (gy < 182) : (gy += 16) try ctx.line(.{ .x = 21, .y = gy }, .{ .x = 155, .y = gy }, 0.4, grid_line);
    }
    const ang: f32 = -0.32;
    const s: f32 = 0.9;
    const rot = Transform2D{
        .xx = s * @cos(ang),
        .xy = -s * @sin(ang),
        .yx = s * @sin(ang),
        .yy = s * @cos(ang),
        .tx = 44,
        .ty = 68,
    };
    try ctx.glyphFill(rot, glyph_fill);
    try ctx.glyphStroke(rot, 1.2, blue);
    for (0..4) |i| {
        const a = mapPt(rot, corners[i]);
        const b = mapPt(rot, corners[(i + 1) % 4]);
        try ctx.line(a, b, 0.9, blue);
        try ctx.fillCircle(a.x, a.y, 1.8, blue);
    }
    const frag_local = Vec2{ .x = 78, .y = 84 };
    const frag = mapPt(rot, frag_local);
    try ctx.fillCircle(frag.x, frag.y, 2.6, amber);
    _ = try ctx.text("screen", 24, 182, label_em, muted, .regular);

    try ctx.panel(.{ .x = 175, .y = 30, .w = 132, .h = 158 });
    const up = glyphPlace(196, 44, 0.9);
    try outlineRect(ctx, .{
        .x = mapPt(up, corners[0]).x,
        .y = mapPt(up, corners[0]).y,
        .w = (gb.max.x - gb.min.x + 2 * dilate) * 0.9,
        .h = (gb.max.y - gb.min.y + 2 * dilate) * 0.9,
    }, 0.6, faint);
    try ctx.glyphStroke(up, 1.3, ink);
    const frag_up = mapPt(up, frag_local);
    try ctx.fillCircle(frag_up.x, frag_up.y, 2.6, amber);
    try ctx.dashedLine(frag, .{ .x = frag_up.x - 4, .y = frag_up.y }, 0.8, 3.0, 2.6, amber);
    _ = try ctx.text("glyph space", 196, 182, label_em, muted, .regular);
    _ = try ctx.text("inverse", 150, 104, small_em, amber, .regular);
    _ = try ctx.text("transform", 150, 113, small_em, amber, .regular);
}

// ── Diagram 4: pick bands ───────────────────────────────────────────

/// The sample shared by diagrams 4 and 5: in the ring's left side, so its
/// rightward ray crosses both contours.
const sample_pt = Vec2{ .x = 22, .y = 72 };

fn diagramPickBands(ctx: *Ctx) !void {
    try title(ctx, "4. Draw: the pixel footprint picks band spans");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 180, .h = 158 });
    const gb = glyphBounds();
    const scale: f32 = 1.2;
    const place = glyphPlace(103 - glyph_cx * scale, 109 - glyph_cy * scale, scale);
    const tl = mapPt(place, gb.min);
    const br = mapPt(place, gb.max);

    // A pixel's footprint in glyph space, enlarged here to straddle band
    // edges. Its height picks rows; its width picks columns.
    const half = Vec2{ .x = 7, .y = 9 };
    const lo = Vec2{ .x = sample_pt.x - half.x, .y = sample_pt.y - half.y };
    const hi = Vec2{ .x = sample_pt.x + half.x, .y = sample_pt.y + half.y };
    const n: f32 = @floatFromInt(band_count);
    const row_first: u32 = @intFromFloat(@floor((lo.y - gb.min.y) / (gb.max.y - gb.min.y) * n));
    const row_last: u32 = @intFromFloat(@floor((hi.y - gb.min.y) / (gb.max.y - gb.min.y) * n));
    const col_first: u32 = @intFromFloat(@floor((lo.x - gb.min.x) / (gb.max.x - gb.min.x) * n));
    const col_last: u32 = @intFromFloat(@floor((hi.x - gb.min.x) / (gb.max.x - gb.min.x) * n));

    var row_wash = blue_soft;
    row_wash[3] = 0.75;
    var col_wash = teal_soft;
    col_wash[3] = 0.75;
    const rows_y0 = mapPt(place, .{ .x = 0, .y = bandExtent(.rows, row_first)[0] }).y;
    const rows_y1 = mapPt(place, .{ .x = 0, .y = bandExtent(.rows, row_last)[1] }).y;
    try ctx.fillRect(.{ .x = tl.x, .y = rows_y0, .w = br.x - tl.x, .h = rows_y1 - rows_y0 }, row_wash);
    const cols_x0 = mapPt(place, .{ .x = bandExtent(.columns, col_first)[0], .y = 0 }).x;
    const cols_x1 = mapPt(place, .{ .x = bandExtent(.columns, col_last)[1], .y = 0 }).x;
    try ctx.fillRect(.{ .x = cols_x0, .y = tl.y, .w = cols_x1 - cols_x0, .h = br.y - tl.y }, col_wash);
    try outlineRect(ctx, .{ .x = tl.x, .y = tl.y, .w = br.x - tl.x, .h = br.y - tl.y }, 0.6, faint);
    try ctx.glyphStroke(place, 1.2, faint);

    const in_rows = bandMembers(.rows, row_first, row_last);
    const in_cols = bandMembers(.columns, col_first, col_last);
    var candidates: u32 = 0;
    for (glyph_segments, in_rows, in_cols) |q, r, c| {
        if (r) try ctx.segStroke(q, place, 2.2, blue);
        if (c) try ctx.segStroke(q, place, if (r) 1.0 else 2.2, teal);
        if (r or c) candidates += 1;
    }
    const fp_tl = mapPt(place, lo);
    const fp_br = mapPt(place, hi);
    try outlineRect(ctx, .{ .x = fp_tl.x, .y = fp_tl.y, .w = fp_br.x - fp_tl.x, .h = fp_br.y - fp_tl.y }, 1.1, amber);
    const sp = mapPt(place, sample_pt);
    try ctx.fillCircle(sp.x, sp.y, 2.6, amber);

    try ctx.panel(.{ .x = 205, .y = 30, .w = 102, .h = 158 });
    _ = try ctx.text("rows it spans:", 214, 50, label_em, blue, .regular);
    _ = try ctx.text("horizontal ray", 214, 61, label_em, blue, .regular);
    _ = try ctx.text("columns it spans:", 214, 80, label_em, teal, .regular);
    _ = try ctx.text("vertical ray", 214, 91, label_em, teal, .regular);
    var buf: [32]u8 = undefined;
    _ = try ctx.text(try std.fmt.bufPrint(&buf, "{d} of 16 curves", .{candidates}), 214, 118, label_em, ink, .regular);
    _ = try ctx.text("are candidates", 214, 129, label_em, ink, .regular);
    _ = try ctx.text("footprint enlarged", 214, 178, small_em, muted, .regular);
}

// ── Diagram 5: ray roots ────────────────────────────────────────────

fn diagramRoots(ctx: *Ctx) !void {
    try title(ctx, "5. Draw: solve candidates along two rays");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });
    const gb = glyphBounds();
    const place = glyphPlace(96, 42, 1.05);
    const br = mapPt(place, gb.max);
    const tl = mapPt(place, gb.min);
    try ctx.glyphStroke(place, 1.4, ink);

    // Rays run toward +x and up (+y in font space). Crossings behind the
    // sample contribute nothing, so they are not drawn.
    const sp = mapPt(place, sample_pt);
    try ctx.arrow(sp, .{ .x = br.x + 18, .y = sp.y }, 0.9, blue);
    try ctx.arrow(sp, .{ .x = sp.x, .y = tl.y - 8 }, 0.9, teal);
    try ctx.fillCircle(sp.x, sp.y, 2.6, amber);

    for (glyph_segments) |q| {
        var tmp: [2]Crossing = undefined;
        const hn = hCrossings(q, sample_pt.y, &tmp);
        for (tmp[0..hn]) |cr| {
            if (cr.pos.x <= sample_pt.x) continue;
            const m = mapPt(place, cr.pos);
            try ctx.fillCircle(m.x, m.y, 2.2, rose);
            _ = try ctx.text(if (cr.sign > 0) "+1" else "-1", m.x + 2, m.y - 5, small_em, rose, .regular);
        }
        const vn = vCrossings(q, sample_pt.x, &tmp);
        for (tmp[0..vn]) |cr| {
            if (cr.pos.y >= sample_pt.y) continue;
            const m = mapPt(place, cr.pos);
            try ctx.fillCircle(m.x, m.y, 2.2, rose);
            _ = try ctx.text(if (cr.sign > 0) "+1" else "-1", m.x + 5, m.y + 3, small_em, rose, .regular);
        }
    }
    _ = try ctx.text("horizontal ray", 224, 132, label_em, blue, .regular);
    _ = try ctx.text("vertical ray", 224, 145, label_em, teal, .regular);
    _ = try ctx.text("each hit is a root,", 224, 165, label_em, muted, .regular);
    _ = try ctx.text("signed by direction", 224, 176, label_em, muted, .regular);
}

// ── Diagram 6: winding ──────────────────────────────────────────────

fn diagramWinding(ctx: *Ctx) !void {
    try title(ctx, "6. Draw: signed crossings sum to winding");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });
    const place = glyphPlace(64, 42, 1.05);
    const br = mapPt(place, .{ .x = glyph_w, .y = glyph_h });
    try ctx.glyphFill(place, glyph_fill);
    try ctx.glyphStroke(place, 1.4, ink);

    const a_local = Vec2{ .x = 76, .y = 44 }; // in the ring, upper right
    const b_local = Vec2{ .x = 50, .y = 74 }; // in the hole
    const ray_end_x = br.x + 26;

    for ([_]struct { p: Vec2, color: [4]f32, label: []const u8 }{
        .{ .p = a_local, .color = amber, .label = "A" },
        .{ .p = b_local, .color = teal, .label = "B" },
    }) |s| {
        const m = mapPt(place, s.p);
        try ctx.arrow(m, .{ .x = ray_end_x, .y = m.y }, 0.9, s.color);
        try ctx.fillCircle(m.x, m.y, 2.6, s.color);
        _ = try ctx.text(s.label, m.x - 2.5, m.y - 8, label_em, s.color, .bold);
        var w: i32 = 0;
        for (glyph_segments) |q| {
            var tmp: [2]Crossing = undefined;
            const n = hCrossings(q, s.p.y, &tmp);
            for (tmp[0..n]) |cr| {
                if (cr.pos.x <= s.p.x) continue;
                w += cr.sign;
                const c = mapPt(place, cr.pos);
                try ctx.fillCircle(c.x, c.y, 2.2, rose);
                _ = try ctx.text(if (cr.sign > 0) "+1" else "-1", c.x + 2, c.y - 5, small_em, rose, .regular);
            }
        }
        std.debug.assert((s.p.x == a_local.x) == (w != 0)); // A filled, B empty
    }
    _ = try ctx.text("A: w = +1, filled", 196, 90, label_em, amber, .regular);
    _ = try ctx.text("B: w = -1 +1 = 0, empty", 196, 127, label_em, teal, .regular);
    _ = try ctx.text("the hole needs no", 196, 158, label_em, muted, .regular);
    _ = try ctx.text("special handling", 196, 169, label_em, muted, .regular);
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

/// Coverage of the toy glyph per device pixel over a `cols`×`rows` window
/// whose top-left is `origin` and whose pixels are `unit` local units wide.
/// snail-raster draws the glyph white over transparent black at exactly
/// that resolution, so each pixel's alpha is snail's own coverage.
fn rasterCoverage(ctx: *Ctx, origin: Vec2, unit: f32, comptime cols: u32, comptime rows: u32) ![rows][cols]f32 {
    const allocator = ctx.allocator;
    var path = try ctx.glyphPath();
    defer path.deinit();
    var prepared = try path.prepare(allocator);
    defer prepared.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var curves = try prepared.fillCurves(allocator, scratch.allocator());
    defer curves.deinit();
    const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = 0 };
    const entries = [_]snail.AtlasEntry{.{ .geometry = .{
        .key = key,
        .curves = curves.view(),
        .paint = try prepared.paintForDesign(.{ .solid = white }),
    } }};
    var atlas = try snail.Atlas.from(allocator, ctx.pool, .{ .entries = &entries });
    defer atlas.deinit();
    const to_pixels = Transform2D{ .xx = 1 / unit, .yy = 1 / unit, .tx = -origin.x / unit, .ty = -origin.y / unit };
    const shapes = [_]snail.Shape{.{ .key = key, .local_transform = prepared.placedBy(to_pixels), .local_color = white }};

    var cache = try raster.DeviceAtlas.init(allocator, ctx.pool, .{
        .max_bindings = 1,
        .layer_info_height = 16,
        .max_images = 1,
    });
    defer cache.deinit();
    var bindings: [1]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    var instances: [1]snail.render.records.Instance = undefined;
    var batches: [1]snail.render.records.DrawBatch = undefined;
    var ni: usize = 0;
    var nb: usize = 0;
    _ = try snail.emit.emit(&instances, &batches, &ni, &nb, bindings[0], &atlas, &shapes, .identity, white);

    var pixels = [_]u8{0} ** (cols * rows * 4);
    var renderer = try raster.Renderer.init(&pixels, cols, rows, cols * 4, .rgba8_unorm);
    try raster.draw(
        &renderer,
        harness.drawState(cols, rows),
        .{ .instances = instances[0..ni], .batches = batches[0..nb] },
        &.{&cache},
        null,
    );
    var out: [rows][cols]f32 = undefined;
    for (0..rows) |r| {
        for (0..cols) |c| out[r][c] = @as(f32, @floatFromInt(pixels[(r * cols + c) * 4 + 3])) / 255.0;
    }
    return out;
}

fn diagramCoverage(ctx: *Ctx) !void {
    try title(ctx, "7. Draw: nearby crossings = partial coverage");

    try ctx.panel(.{ .x = 13, .y = 30, .w = 294, .h = 158 });

    // Zoom onto a diagonal stretch of the outer edge (upper right). Cells
    // are device pixels, shaded by snail-raster's coverage.
    const cols: u32 = 11;
    const rows: u32 = 5;
    const cell: f32 = 24;
    const gx0: f32 = 26;
    const gy0: f32 = 48;
    const zoom: f32 = 10.0; // logical px per local unit
    const unit = cell / zoom; // local units per device pixel
    const win_w = @as(f32, @floatFromInt(cols)) * unit;
    const win_h = @as(f32, @floatFromInt(rows)) * unit;
    const lx0: f32 = 79.8 - win_w / 2.0;
    const ly0: f32 = 32.4 - win_h / 2.0;
    const place = Transform2D{ .xx = zoom, .yy = zoom, .tx = gx0 - lx0 * zoom, .ty = gy0 - ly0 * zoom };
    const coverage = try rasterCoverage(ctx, .{ .x = lx0, .y = ly0 }, unit, cols, rows);

    var best: ?struct { r: usize, c: usize, alpha: f32 } = null;
    for (0..rows) |r| {
        for (0..cols) |c| {
            const alpha = coverage[r][c];
            const px = gx0 + @as(f32, @floatFromInt(c)) * cell;
            const py = gy0 + @as(f32, @floatFromInt(r)) * cell;
            if (alpha > 0.001) {
                var color = ink;
                color[3] = alpha;
                try ctx.fillRect(.{ .x = px, .y = py, .w = cell, .h = cell }, color);
            }
            if (alpha > 0.02 and alpha < 0.98 and (best == null or @abs(alpha - 0.5) < @abs(best.?.alpha - 0.5)))
                best = .{ .r = r, .c = c, .alpha = alpha };
        }
    }
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

    // The most fractional pixel: its center sits on the edge.
    if (best) |b| {
        const px = gx0 + @as(f32, @floatFromInt(b.c)) * cell;
        const py = gy0 + @as(f32, @floatFromInt(b.r)) * cell;
        var pth = try support.unitRectPath(ctx.allocator);
        defer pth.deinit();
        try ctx.strokePath(&pth, 1.6 / cell, amber, support.placeRect(.{ .x = px, .y = py, .w = cell, .h = cell }));
        try ctx.fillCircle(px + cell / 2, py + cell / 2, 2.2, amber);
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "\u{03b1} = {d:.2}", .{b.alpha});
        _ = try ctx.text(s, px + cell + 6, py + cell * 0.5 + 3, label_em, amber, .regular);
    }

    const cap_y = gy0 + @as(f32, @floatFromInt(rows)) * cell + 14;
    _ = try ctx.text("one cell = one device pixel", 26, cap_y, label_em, muted, .regular);
    _ = try ctx.text("partial within ½ px of the edge", 166, cap_y, label_em, muted, .regular);
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
    const sources = [_]snail.FontSource{
        .{ .font_id = 0, .font = &font_regular, .cache_key = .{0} ** 16 },
        .{ .font_id = 1, .font = &font_bold, .cache_key = .{1} ** 16 },
    };

    const pool = try snail.PagePool.init(allocator, .{
        .max_pages = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 15,
    });
    defer pool.deinit();

    for (diagrams) |d| {
        var ctx = try Ctx.init(allocator, pool, &faces, &sources);
        defer ctx.deinit();
        try d.build(&ctx);
        try ctx.render(d.name, d.width, d.height, SCALE);
    }
}
