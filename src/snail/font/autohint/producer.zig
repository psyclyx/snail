//! `auto_light` warp-knot producer.
//!
//! Given a glyph and a ppem, `glyphKnots` runs the resolution-independent
//! edge analysis + blue-zone hinting and returns the per-axis warp `Knot`s
//! that grid-fit the outline. Those knots are packed into an `autohint` atlas
//! record (aliasing the shared unhinted base curves) and applied in the shader
//! at sample time — no per-ppem curves are baked. The grid-fit is HOW this
//! differs from the TrueType path (`HintVm`): resolution-independent edge
//! analysis + warp (`warp.zig`) instead of the TT bytecode VM, so it works on
//! any outline (incl. unhinted / CFF) uniformly. See [[project_autohint]].

const std = @import("std");

const analysis = @import("analysis.zig");
const blue_mod = @import("blue.zig");
const warp = @import("warp.zig");
const outline = @import("../truetype/outline.zig");
const vm = @import("../truetype/vm.zig");
const ttf = @import("../ttf.zig");

const Allocator = std.mem.Allocator;
const Vec2 = @import("../../math/vec.zig").Vec2;

/// Owns the ppem-independent analysis inputs for one font: the parsed
/// program (outlines) and the derived blue zones. Cheap to keep alongside a
/// font; not thread-safe (mirrors `HintVm`).
pub const AutoLight = struct {
    allocator: Allocator,
    program: vm.Program,
    font: ttf.Font,
    blues: blue_mod.Blues,
    params: analysis.Params = .default,
    /// Blue-assignment tolerance as an em fraction.
    blue_tol_em: f32 = 1.0 / 24.0,
    /// Dominant vertical- and horizontal-stem widths (FUnits), derived once
    /// from reference glyphs so every stem of that weight snaps to the same
    /// pixel width — an even colour instead of mixed 1px/2px stems.
    std_x: f32 = 0,
    std_y: f32 = 0,

    pub fn init(allocator: Allocator, font_data: []const u8) !AutoLight {
        const program = try vm.Program.init(font_data);
        const font = try ttf.Font.init(font_data);
        const blues = try blue_mod.deriveLatin(allocator, &program, &font, .{});
        var self: AutoLight = .{ .allocator = allocator, .program = program, .font = font, .blues = blues };
        self.std_x = self.deriveStandardWidth(.x, "Hnmurbdpq");
        self.std_y = self.deriveStandardWidth(.y, "EFHTLZ");
        return self;
    }

    /// Median stem width (FUnits) along `axis` across reference letters, or 0
    /// if none found. Median is robust to the odd serif/thin stroke.
    fn deriveStandardWidth(self: *AutoLight, axis: analysis.Axis, ref: []const u8) f32 {
        var widths: std.ArrayList(f32) = .empty;
        defer widths.deinit(self.allocator);

        for (ref) |ch| {
            const gid = self.font.glyphIndex(ch) catch continue;
            if (gid == 0) continue;
            var topo = self.program.loadGlyphTopology(self.allocator, gid) catch continue;
            defer topo.deinit();
            const simple = switch (topo) {
                .simple => |s| s,
                else => continue,
            };
            var a = analysis.analyzeGlyph(self.allocator, simple.points, simple.contours, self.font.units_per_em, self.params, axis) catch continue;
            defer a.deinit();
            for (a.edges, 0..) |e, i| {
                if (e.isStem() and e.stem > i) widths.append(self.allocator, e.width) catch {};
            }
        }

        if (widths.items.len == 0) return 0;
        std.mem.sort(f32, widths.items, {}, std.sort.asc(f32));
        return widths.items[widths.items.len / 2];
    }

    pub fn deinit(self: *AutoLight) void {
        self.blues.deinit();
        self.* = undefined;
    }

    /// Analyse both axes of a flattened outline and fill the caller's knot
    /// buffers (FUnits). Backs `glyphKnots`.
    fn fillKnots(
        self: *AutoLight,
        scratch: Allocator,
        pts: []const outline.Point,
        contours: []const outline.ContourRange,
        px_per_unit: f32,
        x_buf: []warp.Knot,
        y_buf: []warp.Knot,
    ) !struct { nx: usize, ny: usize } {
        var ay = try analysis.analyzeGlyph(scratch, pts, contours, self.font.units_per_em, self.params, .y);
        defer ay.deinit();
        self.blues.assignEdges(ay.edges, self.blue_tol_em);
        var zbuf: [warp.max_knots]warp.BlueZone = undefined;
        const zones = self.blues.warpZones(&zbuf);
        const ny = warp.buildKnots(ay.edges, zones, px_per_unit, self.std_y, .{}, y_buf);

        var ax = try analysis.analyzeGlyph(scratch, pts, contours, self.font.units_per_em, self.params, .x);
        defer ax.deinit();
        // The x-axis hints HARD (unlike the light y-axis): every vertical stem
        // snaps to a solid whole pixel, stems are positioned relative to the
        // first so glyph widths are preserved, and a round glyph's left bowl is
        // registered to the grid too (leftmost outline x) so it doesn't get left
        // a pixel behind the flats. Vertical-stem crispness is the whole reason
        // to hint x at all; there are no x blues.
        var min_x: f32 = std.math.inf(f32);
        for (pts) |p| min_x = @min(min_x, @as(f32, @floatFromInt(p.x)));
        const nx = warp.buildKnotsReg(ax.edges, &.{}, px_per_unit, self.std_x, .{
            .full_stem_hint = true,
            .anchor_stem_positions = true,
        }, min_x, x_buf);
        return .{ .nx = nx, .ny = ny };
    }

    /// Em-normalised (÷upm) warp knots for the runtime warp path — the base
    /// atlas glyph is in em space, so the FUnit knots are rescaled to match.
    /// Fills `x_buf`/`y_buf` (each ≥ `warp.max_knots`) and returns the used
    /// slices; empty when the glyph has no usable features.
    pub fn glyphKnots(
        self: *AutoLight,
        scratch: Allocator,
        glyph_id: u16,
        ppem_26_6: u32,
        x_buf: []warp.Knot,
        y_buf: []warp.Knot,
    ) !AxisKnots {
        const ppem_px = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
        const upm: f32 = @floatFromInt(self.font.units_per_em);
        const px_per_unit = if (upm > 0) ppem_px / upm else 0;

        var pts: std.ArrayList(outline.Point) = .empty;
        defer pts.deinit(scratch);
        var contours: std.ArrayList(outline.ContourRange) = .empty;
        defer contours.deinit(scratch);
        try flattenGlyph(scratch, &self.program, glyph_id, &pts, &contours, 0);
        if (pts.items.len == 0 or upm <= 0) return .{ .x = x_buf[0..0], .y = y_buf[0..0] };

        const counts = try self.fillKnots(scratch, pts.items, contours.items, px_per_unit, x_buf, y_buf);
        for (x_buf[0..counts.nx]) |*k| {
            k.base /= upm;
            k.target /= upm;
        }
        for (y_buf[0..counts.ny]) |*k| {
            k.base /= upm;
            k.target /= upm;
        }
        return .{ .x = x_buf[0..counts.nx], .y = y_buf[0..counts.ny] };
    }
};

pub const AxisKnots = struct {
    x: []const warp.Knot,
    y: []const warp.Knot,
};

/// Resolve `glyph_id` (simple or compound) into a single flat point/contour
/// set in FUnits, appending to `pts`/`contours`. Compound components are
/// composed recursively with their transform + offset — this is pure geometry
/// (no hinting), just enough to give the analyser a whole outline. Depth is
/// bounded against malformed self-referential fonts.
fn flattenGlyph(
    allocator: Allocator,
    program: *const vm.Program,
    glyph_id: u16,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
    depth: u8,
) !void {
    if (depth > 8) return;
    var topo = try program.loadGlyphTopology(allocator, glyph_id);
    defer topo.deinit();
    switch (topo) {
        .empty => {},
        .simple => |s| try appendSimple(allocator, s, .{}, Vec2.zero, pts, contours),
        .compound => |cmp| {
            for (cmp.components) |comp| {
                // Point-matching components (args are point indices, not x/y)
                // are rare and mostly non-Latin; skip rather than mis-place.
                if (!comp.args_are_xy) continue;
                const raw = Vec2{ .x = @floatFromInt(comp.arg1), .y = @floatFromInt(comp.arg2) };
                try flattenComponent(allocator, program, comp.glyph_id, comp.transform, raw, pts, contours, depth);
            }
        },
    }
}

fn flattenComponent(
    allocator: Allocator,
    program: *const vm.Program,
    glyph_id: u16,
    transform: outline.ComponentTransform,
    offset: Vec2,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
    depth: u8,
) !void {
    if (depth > 8) return;
    var topo = try program.loadGlyphTopology(allocator, glyph_id);
    defer topo.deinit();
    switch (topo) {
        .empty => {},
        .simple => |s| try appendSimple(allocator, s, transform, offset, pts, contours),
        .compound => |cmp| {
            for (cmp.components) |comp| {
                if (!comp.args_are_xy) continue;
                const raw = Vec2{ .x = @floatFromInt(comp.arg1), .y = @floatFromInt(comp.arg2) };
                const child_offset = Vec2.add(offset, transform.apply(raw));
                try flattenComponent(allocator, program, comp.glyph_id, transform.concat(comp.transform), child_offset, pts, contours, depth + 1);
            }
        },
    }
}

fn appendSimple(
    allocator: Allocator,
    s: outline.SimpleGlyph,
    transform: outline.ComponentTransform,
    offset: Vec2,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
) !void {
    const base: u32 = @intCast(pts.items.len);
    for (s.contours) |c| try contours.append(allocator, .{ .start = base + c.start, .end = base + c.end });
    for (s.points) |p| {
        const v = Vec2.add(transform.apply(.{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) }), offset);
        try pts.append(allocator, .{
            .x = @intFromFloat(@round(v.x)),
            .y = @intFromFloat(@round(v.y)),
            .on_curve = p.on_curve,
        });
    }
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");

test "auto-light derives non-zero standard stem widths" {
    var al = try AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer al.deinit();
    try testing.expect(al.std_x > 0);
    try testing.expect(al.std_y > 0);
}
