//! Blue-zone derivation for composable autohinting.
//!
//! Blue zones are the handful of font-global reference heights — baseline,
//! x-height, cap-height, ascender, descender — that make grid-fitting look
//! coherent: every glyph's baseline snaps to the *same* rounded pixel line,
//! every x-height agrees, so a line of text sits on shared rails instead of
//! each glyph rounding independently. (Blue zones originate in Adobe's Type 1
//! font spec.) We derive them once per font from the extrema of a few
//! reference letters; they are entirely ppem-independent — the per-size
//! rounding happens later in the warp. See [[project_snail]].
//!
//! `deriveLatin` covers curated Latin reference strings. The higher-level
//! producer falls back to repeated font-wide outline extrema when those strings
//! have no coverage, giving other scripts shared rails without pretending that
//! their metrics are Latin x-height/cap-height semantics.

const std = @import("std");

const analysis = @import("analysis.zig");
const warp = @import("warp.zig");
const vm = @import("../truetype/vm.zig");
const ttf = @import("../ttf.zig");

const Allocator = std.mem.Allocator;
const Edge = analysis.Edge;

pub const BlueKind = enum { top, bottom };

/// Tuning for blue-zone derivation. Exposed rather than baked in — pick
/// explicitly per the project's no-magic-thresholds rule.
/// See [[feedback_no_magic_thresholds]].
pub const Params = struct {
    /// Clamp the overshoot to this em fraction. Real overshoot is ~1%; anything
    /// larger means a stray descender/ascender point slipped into the reference
    /// set. Defence in depth beyond the curated `rounds` strings.
    max_overshoot_em: f32 = 0.03,

    pub const default: Params = .{};
};

/// Which reference letters define a zone, and whether it's a top or bottom
/// alignment. `flats` set the reference height; `rounds` (o, e, C, …) measure
/// the overshoot past it, and stand in as the reference when no flat is found.
const Spec = struct {
    kind: BlueKind,
    flats: []const u8,
    rounds: []const u8,
};

/// Reference letters per Latin zone, chosen by an objective property of the
/// letterforms: which have flat vs round tops/bottoms. `flats` set the height;
/// `rounds` measure the overshoot past it. Order fixes the blue indices.
const latin_specs = [_]Spec{
    // Round-BOTTOM references must avoid tails/spurs (Q's tail, G's spur)
    // which `glyphExtreme` would read as a huge bogus overshoot; O and C have
    // clean round bottoms. Tops are unaffected, so cap-height keeps OCGQ.
    .{ .kind = .bottom, .flats = "HEZLBDFP", .rounds = "OC" }, // cap baseline
    .{ .kind = .top, .flats = "THEZ", .rounds = "OCGQ" }, // cap height
    .{ .kind = .top, .flats = "xzvw", .rounds = "oesc" }, // x-height
    .{ .kind = .bottom, .flats = "xzvw", .rounds = "oesc" }, // small baseline
    .{ .kind = .top, .flats = "bdhkl", .rounds = "" }, // ascender
    .{ .kind = .bottom, .flats = "pq", .rounds = "gjy" }, // descender
};

pub const Zone = struct {
    pos: f32, // FUnits, the flat reference height (where x/z/H sit)
    shoot: f32, // FUnits, the overshoot height (where o/e/O reach past pos)
    kind: BlueKind,
};

/// Serializable, em-normalized blue-zone facts. Size-specific fitting rounds
/// these references later.
pub const FeatureZone = struct {
    ref: f32,
    shoot: f32,
};

pub const Blues = struct {
    allocator: Allocator,
    units_per_em: u16,
    zones: []Zone,

    pub fn deinit(self: *Blues) void {
        self.allocator.free(self.zones);
        self.* = undefined;
    }

    /// Copy the font-unit zones into an owned, em-normalized feature slice.
    pub fn normalized(self: Blues, allocator: Allocator) ![]FeatureZone {
        const result = try allocator.alloc(FeatureZone, self.zones.len);
        const upm: f32 = @floatFromInt(self.units_per_em);
        for (self.zones, result) |zone, *feature| {
            feature.* = .{ .ref = zone.pos / upm, .shoot = zone.shoot / upm };
        }
        return result;
    }

    /// The zone list the warp consumes (reference + overshoot). Borrows `self`.
    pub fn warpZones(self: Blues, out: []warp.BlueZone) []warp.BlueZone {
        const n = @min(self.zones.len, out.len);
        for (0..n) |i| out[i] = .{ .ref = self.zones[i].pos, .shoot = self.zones[i].shoot };
        return out[0..n];
    }

    /// Latch each edge onto the nearest zone within `tol_em` (em fraction).
    /// Proximity-only: zones are well separated in height, and the tolerance
    /// is tight enough that mid-glyph crossbars stay unlinked. Sets `edge.blue`.
    pub fn assignEdges(self: Blues, edges: []Edge, tol_em: f32) void {
        const tol = tol_em * @as(f32, @floatFromInt(self.units_per_em));
        for (edges) |*e| {
            var best: i16 = -1;
            var best_d: f32 = tol;
            for (self.zones, 0..) |z, i| {
                const d = @abs(e.pos - z.pos);
                if (d < best_d) {
                    best_d = d;
                    best = @intCast(i);
                }
            }
            e.blue = best;
        }
    }
};

const Accum = struct {
    flat_sum: f64 = 0,
    flat_n: u32 = 0,
    round_sum: f64 = 0,
    round_n: u32 = 0,

    fn add(self: *Accum, value: f32, is_round: bool) void {
        if (is_round) {
            self.round_sum += value;
            self.round_n += 1;
        } else {
            self.flat_sum += value;
            self.flat_n += 1;
        }
    }

    fn reference(self: Accum) ?f32 {
        if (self.flat_n > 0) return @floatCast(self.flat_sum / @as(f64, @floatFromInt(self.flat_n)));
        if (self.round_n > 0) return @floatCast(self.round_sum / @as(f64, @floatFromInt(self.round_n)));
        return null;
    }

    /// Mean of the round (overshoot) letters, or null if none measured.
    fn overshoot(self: Accum) ?f32 {
        if (self.round_n > 0) return @floatCast(self.round_sum / @as(f64, @floatFromInt(self.round_n)));
        return null;
    }
};

/// Derive blue zones for a font. Reference glyphs are pulled from `font`'s
/// cmap and measured via `program`; missing letters are skipped. A zone with
/// no measurable reference letter is dropped, so the result may be shorter
/// than `latin_specs` (fine — edges just won't link to absent zones).
pub fn deriveLatin(
    allocator: Allocator,
    program: *const vm.Program,
    font: *const ttf.Font,
    params: Params,
) !Blues {
    var zones: std.ArrayList(Zone) = .empty;
    errdefer zones.deinit(allocator);

    for (latin_specs) |spec| {
        var acc: Accum = .{};
        try accumulateSet(allocator, program, font, spec.flats, spec.kind, false, &acc);
        try accumulateSet(allocator, program, font, spec.rounds, spec.kind, true, &acc);
        if (acc.reference()) |ref| {
            // Clamp the overshoot to a sane magnitude (~3% em). Real overshoot
            // is ~1%; anything larger means a stray descender/ascender point
            // slipped into the reference set. Defence in depth beyond the
            // curated `rounds` strings.
            const max_over = params.max_overshoot_em * @as(f32, @floatFromInt(font.units_per_em));
            const shoot = std.math.clamp(acc.overshoot() orelse ref, ref - max_over, ref + max_over);
            try zones.append(allocator, .{ .pos = ref, .shoot = shoot, .kind = spec.kind });
        }
    }

    return .{
        .allocator = allocator,
        .units_per_em = font.units_per_em,
        .zones = try zones.toOwnedSlice(allocator),
    };
}

fn accumulateSet(
    allocator: Allocator,
    program: *const vm.Program,
    font: *const ttf.Font,
    chars: []const u8,
    kind: BlueKind,
    is_round: bool,
    acc: *Accum,
) !void {
    for (chars) |ch| {
        const gid = font.glyphIndex(ch) catch continue;
        if (gid == 0) continue;
        const extreme = glyphExtreme(allocator, program, gid, kind) catch continue orelse continue;
        acc.add(extreme, is_round);
    }
}

/// Max (top) or min (bottom) on-curve y of a simple glyph, in FUnits.
fn glyphExtreme(allocator: Allocator, program: *const vm.Program, gid: u16, kind: BlueKind) !?f32 {
    var topo = try program.loadGlyphTopology(allocator, gid);
    defer topo.deinit();
    const simple = switch (topo) {
        .simple => |s| s,
        else => return null,
    };
    if (simple.points.len == 0) return null;

    var extreme: f32 = @floatFromInt(simple.points[0].y);
    for (simple.points[1..]) |p| {
        const y: f32 = @floatFromInt(p.y);
        extreme = switch (kind) {
            .top => @max(extreme, y),
            .bottom => @min(extreme, y),
        };
    }
    return extreme;
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");

test "derive Latin blues orders baseline below x-height below cap" {
    const program = try vm.Program.init(assets.noto_sans_regular);
    const font = try ttf.Font.init(assets.noto_sans_regular);

    var blues = try deriveLatin(testing.allocator, &program, &font, .{});
    defer blues.deinit();

    const em: f32 = @floatFromInt(blues.units_per_em);

    // Find the zones we care about by kind + rough height.
    var cap_baseline: ?f32 = null;
    var x_height: ?f32 = null;
    var cap_height: ?f32 = null;
    var descender: ?f32 = null;
    for (blues.zones) |z| {
        if (z.kind == .bottom and @abs(z.pos) < 0.08 * em) cap_baseline = z.pos;
        if (z.kind == .top and z.pos > 0.35 * em and z.pos < 0.60 * em) x_height = z.pos;
        if (z.kind == .top and z.pos > 0.62 * em and z.pos < 0.85 * em) cap_height = z.pos;
        if (z.kind == .bottom and z.pos < -0.10 * em) descender = z.pos;
    }

    try testing.expect(cap_baseline != null);
    try testing.expect(x_height != null);
    try testing.expect(cap_height != null);
    try testing.expect(descender != null);
    try testing.expect(x_height.? < cap_height.?);
    try testing.expect(cap_baseline.? < x_height.?);
    try testing.expect(descender.? < cap_baseline.?);
}

test "baseline overshoot is a sane magnitude, not a descender tail" {
    const program = try vm.Program.init(assets.noto_sans_regular);
    const font = try ttf.Font.init(assets.noto_sans_regular);
    var blues = try deriveLatin(testing.allocator, &program, &font, .{});
    defer blues.deinit();

    const em: f32 = @floatFromInt(blues.units_per_em);
    for (blues.zones) |z| {
        // Overshoot never exceeds the clamp (~3% em); a tail/spur slipping in
        // (Q, G) would otherwise blow it far past that.
        try testing.expect(@abs(z.shoot - z.pos) <= 0.031 * em);
    }
}

test "assign links H baseline and cap edges to blue zones" {
    const program = try vm.Program.init(assets.noto_sans_regular);
    const font = try ttf.Font.init(assets.noto_sans_regular);

    var blues = try deriveLatin(testing.allocator, &program, &font, .{});
    defer blues.deinit();

    const gid = try font.glyphIndex('H');
    var topo = try program.loadGlyphTopology(testing.allocator, gid);
    defer topo.deinit();
    const simple = switch (topo) {
        .simple => |s| s,
        else => return error.NotSimpleGlyph,
    };

    var a = try analysis.analyzeGlyph(testing.allocator, simple.points, simple.contours, font.units_per_em, .default, .y);
    defer a.deinit();
    blues.assignEdges(a.edges, 1.0 / 24.0);

    // Baseline (lowest) and cap (highest) edges must latch onto a zone; the
    // crossbar in the middle must not.
    try testing.expect(a.edges[0].blue >= 0);
    try testing.expect(a.edges[a.edges.len - 1].blue >= 0);
    var linked_crossbar = false;
    for (a.edges) |e| {
        if (e.isStem() and e.blue >= 0) linked_crossbar = true;
    }
    try testing.expect(!linked_crossbar);
}
