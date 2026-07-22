//! PPEM-independent autohint feature producer.
//!
//! `AutohintAnalyzer` flattens each outline and emits stable, em-normalized
//! edge facts. Pixel-size and policy-specific fitting happens later; this
//! module retains no fitted targets. Transient fitting is performed directly
//! from these records by `warp.fitGlyph` at draw time.

const std = @import("std");

const analysis = @import("analysis.zig");
const blue_mod = @import("blue.zig");
const outline = @import("../truetype/outline.zig");
const vm = @import("../truetype/vm.zig");
const ttf = @import("../ttf.zig");
const font_mod = @import("../../font.zig");
const modern_font = @import("../harfbuzz_font.zig");

const Allocator = std.mem.Allocator;
const Vec2 = @import("../../math/vec.zig").Vec2;

/// Owns the ppem-independent analysis inputs for one font: the parsed
/// program (outlines) and the derived blue zones. Cheap to keep alongside a
/// font; not thread-safe (mirrors `TtHintVm`).
pub const FeatureEdge = analysis.FeatureEdge;

/// Maximum feature records accepted per axis. Allocate this many
/// `FeatureEdge` values for each scratch slice passed to `analyzeGlyph` to
/// preserve every feature the runtime fitter can consume.
pub const max_features_per_axis: usize = 32;

pub const GlyphFeatures = struct {
    x: []const FeatureEdge,
    y: []const FeatureEdge,
    left: f32,
};

pub const FontFeatures = struct {
    blues: []const blue_mod.FeatureZone,
    std_x: f32,
    std_y: f32,
};

pub const AutohintAnalyzer = struct {
    allocator: Allocator,
    program: ?vm.Program,
    modern_instance: ?modern_font.Instance,
    font: font_mod.Font,
    blues: blue_mod.Blues,
    normalized_blues: []blue_mod.FeatureZone,
    params: analysis.Params = .default,
    blue_tol_em: f32 = 1.0 / 24.0,
    std_x: f32 = 0,
    std_y: f32 = 0,

    pub fn init(allocator: Allocator, font_data: []const u8) !AutohintAnalyzer {
        return initFace(allocator, font_data, 0);
    }

    pub fn initFace(allocator: Allocator, font_data: []const u8, face_index: u32) !AutohintAnalyzer {
        var font = try font_mod.Font.initFace(font_data, face_index);
        return initFont(allocator, &font);
    }

    /// Build analysis for an exact selected face and variable-font instance.
    /// The Font's borrowed bytes and variation slice must outlive this value.
    pub fn initFont(allocator: Allocator, source_font: *const font_mod.Font) !AutohintAnalyzer {
        const use_modern = source_font.inner.outline_format != .truetype or source_font.variations.len != 0;
        var program: ?vm.Program = null;
        var modern_instance: ?modern_font.Instance = null;
        var blues: blue_mod.Blues = undefined;

        if (use_modern) {
            modern_instance = try modern_font.Instance.init(
                source_font.inner.data,
                source_font.inner.face_index,
                source_font.inner.units_per_em,
                source_font.variations,
            );
            errdefer if (modern_instance) |*instance| instance.deinit();
            const blue_context = ModernBlueContext{
                .instance = &modern_instance.?,
                .font = source_font,
            };
            blues = try blue_mod.deriveLatinWith(
                allocator,
                source_font.inner.units_per_em,
                blue_context,
                modernGlyphExtreme,
                .{},
            );
            if (blues.zones.len == 0) {
                blues.deinit();
                blues = try deriveStatisticalBluesModern(
                    allocator,
                    &modern_instance.?,
                    source_font,
                    .default,
                    .{},
                );
            }
        } else {
            program = try vm.Program.initFace(source_font.inner.data, source_font.inner.face_index);
            blues = try blue_mod.deriveLatin(allocator, &program.?, &source_font.inner, .{});
            if (blues.zones.len == 0) {
                blues.deinit();
                blues = try deriveStatisticalBlues(allocator, &program.?, &source_font.inner, .default, .{});
            }
        }
        errdefer blues.deinit();
        var self: AutohintAnalyzer = .{
            .allocator = allocator,
            .program = program,
            .modern_instance = modern_instance,
            .font = source_font.*,
            .blues = blues,
            .normalized_blues = &.{},
        };
        self.std_x = self.deriveStandardWidth(.x, "Hnmurbdpq");
        self.std_y = self.deriveStandardWidth(.y, "EFHTLZ");
        self.normalized_blues = try self.blues.normalized(allocator);
        return self;
    }

    fn deriveStandardWidth(self: *AutohintAnalyzer, axis: analysis.Axis, ref: []const u8) f32 {
        var widths: std.ArrayList(f32) = .empty;
        defer widths.deinit(self.allocator);
        for (ref) |ch| {
            const gid = self.font.glyphIndex(ch) catch continue;
            if (gid == 0) continue;
            var result = self.analyzeEdges(self.allocator, gid, axis) catch continue;
            defer result.deinit();
            for (result.edges, 0..) |edge, i| {
                if (edge.isStem() and edge.stem > i) widths.append(self.allocator, edge.width) catch {};
            }
        }
        if (widths.items.len == 0) return 0;
        std.mem.sort(f32, widths.items, {}, std.sort.asc(f32));
        return widths.items[widths.items.len / 2];
    }

    pub fn deinit(self: *AutohintAnalyzer) void {
        self.allocator.free(self.normalized_blues);
        self.blues.deinit();
        if (self.modern_instance) |*instance| instance.deinit();
        self.* = undefined;
    }

    pub fn fontFeatures(self: *const AutohintAnalyzer) FontFeatures {
        const upm: f32 = @floatFromInt(self.font.inner.units_per_em);
        return .{
            .blues = self.normalized_blues,
            .std_x = self.std_x / upm,
            .std_y = self.std_y / upm,
        };
    }

    /// Analyze a glyph once into immutable, em-normalized edge facts.
    pub fn analyzeGlyph(
        self: *AutohintAnalyzer,
        scratch: Allocator,
        glyph_id: u16,
        x_buf: []FeatureEdge,
        y_buf: []FeatureEdge,
    ) !GlyphFeatures {
        const upm: f32 = @floatFromInt(self.font.inner.units_per_em);
        if (upm <= 0) return .{ .x = x_buf[0..0], .y = y_buf[0..0], .left = 0 };

        if (self.program) |*program| {
            var pts: std.ArrayList(outline.Point) = .empty;
            defer pts.deinit(scratch);
            var contours: std.ArrayList(outline.ContourRange) = .empty;
            defer contours.deinit(scratch);
            try flattenGlyph(scratch, program, glyph_id, &pts, &contours, 0);
            if (pts.items.len == 0) return .{ .x = x_buf[0..0], .y = y_buf[0..0], .left = 0 };

            var min_x: f32 = std.math.inf(f32);
            for (pts.items) |point| min_x = @min(min_x, @as(f32, @floatFromInt(point.x)));
            var y_analysis = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.inner.units_per_em, self.params, .y);
            defer y_analysis.deinit();
            self.blues.assignEdges(y_analysis.edges, self.blue_tol_em);
            const y = convertEdges(y_analysis.edges, upm, self.normalized_blues, y_buf);
            var x_analysis = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.inner.units_per_em, self.params, .x);
            defer x_analysis.deinit();
            const x = convertEdges(x_analysis.edges, upm, &.{}, x_buf);
            return .{ .x = x, .y = y, .left = min_x / upm };
        }

        var glyph_outline = try self.modern_instance.?.glyphOutline(scratch, glyph_id, 1.0);
        defer glyph_outline.deinit();
        if (glyph_outline.segments.len == 0)
            return .{ .x = x_buf[0..0], .y = y_buf[0..0], .left = 0 };
        var bounds = glyph_outline.segments[0].boundingBox();
        for (glyph_outline.segments[1..]) |curve| bounds = bounds.merge(curve.boundingBox());
        var y_analysis = try analysis.analyzeCurves(
            scratch,
            glyph_outline.segments,
            glyph_outline.contours,
            self.font.inner.units_per_em,
            self.params,
            .y,
        );
        defer y_analysis.deinit();
        self.blues.assignEdges(y_analysis.edges, self.blue_tol_em);
        const y = convertEdges(y_analysis.edges, upm, self.normalized_blues, y_buf);
        var x_analysis = try analysis.analyzeCurves(
            scratch,
            glyph_outline.segments,
            glyph_outline.contours,
            self.font.inner.units_per_em,
            self.params,
            .x,
        );
        defer x_analysis.deinit();
        const x = convertEdges(x_analysis.edges, upm, &.{}, x_buf);
        return .{ .x = x, .y = y, .left = bounds.min.x / upm };
    }

    fn analyzeEdges(self: *AutohintAnalyzer, allocator: Allocator, glyph_id: u16, axis: analysis.Axis) !analysis.GlyphAnalysis {
        if (self.program) |*program| {
            var topology = try program.loadGlyphTopology(allocator, glyph_id);
            defer topology.deinit();
            const simple = switch (topology) {
                .simple => |simple| simple,
                else => return error.NotSimpleGlyph,
            };
            return analysis.analyzeGlyph(
                allocator,
                simple.points,
                simple.contours,
                self.font.inner.units_per_em,
                self.params,
                axis,
            );
        }
        var glyph_outline = try self.modern_instance.?.glyphOutline(allocator, glyph_id, 1.0);
        defer glyph_outline.deinit();
        return analysis.analyzeCurves(
            allocator,
            glyph_outline.segments,
            glyph_outline.contours,
            self.font.inner.units_per_em,
            self.params,
            axis,
        );
    }
};

const ModernBlueContext = struct {
    instance: *modern_font.Instance,
    font: *const font_mod.Font,
};

fn modernGlyphExtreme(
    allocator: Allocator,
    context: ModernBlueContext,
    ch: u8,
    kind: blue_mod.BlueKind,
) !?f32 {
    const glyph_id = context.font.glyphIndex(ch) catch return null;
    if (glyph_id == 0) return null;
    var glyph_outline = try context.instance.glyphOutline(allocator, glyph_id, 1.0);
    defer glyph_outline.deinit();
    if (glyph_outline.segments.len == 0) return null;
    var bounds = glyph_outline.segments[0].boundingBox();
    for (glyph_outline.segments[1..]) |curve| bounds = bounds.merge(curve.boundingBox());
    return switch (kind) {
        .top => bounds.max.y,
        .bottom => bounds.min.y,
    };
}

const statistical_zone_bin_count = 257;
const statistical_zone_bin_offset = 128;
const statistical_zone_bins_per_em: f32 = 64;
const max_statistical_zones = 6;
const max_statistical_glyph_samples = 256;

const ZoneBin = struct {
    count: u32 = 0,
    flat_sum: f64 = 0,
    flat_count: u32 = 0,
    round_sum: f64 = 0,
    round_count: u32 = 0,

    fn add(self: *ZoneBin, pos: f32, round: bool) void {
        self.count += 1;
        if (round) {
            self.round_sum += pos;
            self.round_count += 1;
        } else {
            self.flat_sum += pos;
            self.flat_count += 1;
        }
    }

    fn merge(self: *ZoneBin, other: ZoneBin) void {
        self.count += other.count;
        self.flat_sum += other.flat_sum;
        self.flat_count += other.flat_count;
        self.round_sum += other.round_sum;
        self.round_count += other.round_count;
    }

    fn reference(self: ZoneBin) ?f32 {
        if (self.flat_count > 0) return @floatCast(self.flat_sum / @as(f64, @floatFromInt(self.flat_count)));
        if (self.round_count > 0) return @floatCast(self.round_sum / @as(f64, @floatFromInt(self.round_count)));
        return null;
    }

    fn overshoot(self: ZoneBin) ?f32 {
        if (self.round_count == 0) return null;
        return @floatCast(self.round_sum / @as(f64, @floatFromInt(self.round_count)));
    }
};

/// Fonts without the Latin reference glyphs used by `deriveLatin` still tend
/// to repeat a small set of outline extrema: Arabic baselines/descenders,
/// Devanagari headlines, Mongolian joining rails, and analogous metrics in
/// other scripts. Infer only those font-global rails here. This is a one-time,
/// ppem-independent font analysis; individual glyph records still contain
/// only the semantic zone/stem relationships consumed at draw time.
fn deriveStatisticalBlues(
    allocator: Allocator,
    program: *const vm.Program,
    font: *const ttf.Font,
    analysis_params: analysis.Params,
    blue_params: blue_mod.Params,
) !blue_mod.Blues {
    var bottom = [_]ZoneBin{.{}} ** statistical_zone_bin_count;
    var top = [_]ZoneBin{.{}} ** statistical_zone_bin_count;
    var outlined_glyphs: usize = 0;
    const em: f32 = @floatFromInt(font.units_per_em);
    const extremum_tolerance = em / 24.0;

    var scratch_state = std.heap.ArenaAllocator.init(allocator);
    defer scratch_state.deinit();
    const scratch = scratch_state.allocator();

    const glyph_count: usize = font.num_glyphs;
    const sample_count = @min(glyph_count, max_statistical_glyph_samples);
    if (sample_count == 0) return .{
        .allocator = allocator,
        .units_per_em = font.units_per_em,
        .zones = try allocator.alloc(blue_mod.Zone, 0),
    };
    for (0..sample_count) |sample_index| {
        const glyph_index = sample_index * glyph_count / sample_count;
        defer _ = scratch_state.reset(.retain_capacity);
        var points: std.ArrayList(outline.Point) = .empty;
        var contours: std.ArrayList(outline.ContourRange) = .empty;
        flattenGlyph(scratch, program, @intCast(glyph_index), &points, &contours, 0) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => continue,
        };
        if (points.items.len == 0) continue;
        outlined_glyphs += 1;

        var min_y: f32 = std.math.inf(f32);
        var max_y: f32 = -std.math.inf(f32);
        for (points.items) |point| {
            const y: f32 = @floatFromInt(point.y);
            min_y = @min(min_y, y);
            max_y = @max(max_y, y);
        }

        var result = try analysis.analyzeGlyph(scratch, points.items, contours.items, font.units_per_em, analysis_params, .y);
        defer result.deinit();
        addExtremumCandidate(&bottom, result.edges, min_y, extremum_tolerance, em);
        addExtremumCandidate(&top, result.edges, max_y, extremum_tolerance, em);
    }

    return finishStatisticalBlues(allocator, font.units_per_em, outlined_glyphs, &bottom, &top, blue_params);
}

fn deriveStatisticalBluesModern(
    allocator: Allocator,
    instance: *modern_font.Instance,
    font: *const font_mod.Font,
    analysis_params: analysis.Params,
    blue_params: blue_mod.Params,
) !blue_mod.Blues {
    var bottom = [_]ZoneBin{.{}} ** statistical_zone_bin_count;
    var top = [_]ZoneBin{.{}} ** statistical_zone_bin_count;
    var outlined_glyphs: usize = 0;
    const em: f32 = @floatFromInt(font.inner.units_per_em);
    const extremum_tolerance = em / 24.0;

    var scratch_state = std.heap.ArenaAllocator.init(allocator);
    defer scratch_state.deinit();
    const scratch = scratch_state.allocator();
    const glyph_count: usize = font.inner.num_glyphs;
    const sample_count = @min(glyph_count, max_statistical_glyph_samples);
    if (sample_count == 0) return .{
        .allocator = allocator,
        .units_per_em = font.inner.units_per_em,
        .zones = try allocator.alloc(blue_mod.Zone, 0),
    };

    for (0..sample_count) |sample_index| {
        const glyph_index = sample_index * glyph_count / sample_count;
        defer _ = scratch_state.reset(.retain_capacity);
        var glyph_outline = instance.glyphOutline(scratch, @intCast(glyph_index), 1.0) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => continue,
        };
        defer glyph_outline.deinit();
        if (glyph_outline.segments.len == 0) continue;
        outlined_glyphs += 1;

        var bounds = glyph_outline.segments[0].boundingBox();
        for (glyph_outline.segments[1..]) |curve| bounds = bounds.merge(curve.boundingBox());
        var result = try analysis.analyzeCurves(
            scratch,
            glyph_outline.segments,
            glyph_outline.contours,
            font.inner.units_per_em,
            analysis_params,
            .y,
        );
        defer result.deinit();
        addExtremumCandidate(&bottom, result.edges, bounds.min.y, extremum_tolerance, em);
        addExtremumCandidate(&top, result.edges, bounds.max.y, extremum_tolerance, em);
    }

    return finishStatisticalBlues(
        allocator,
        font.inner.units_per_em,
        outlined_glyphs,
        &bottom,
        &top,
        blue_params,
    );
}

fn finishStatisticalBlues(
    allocator: Allocator,
    units_per_em: u16,
    outlined_glyphs: usize,
    bottom: *[statistical_zone_bin_count]ZoneBin,
    top: *[statistical_zone_bin_count]ZoneBin,
    blue_params: blue_mod.Params,
) !blue_mod.Blues {
    const em: f32 = @floatFromInt(units_per_em);
    var zones: std.ArrayList(blue_mod.Zone) = .empty;
    errdefer zones.deinit(allocator);
    const minimum_samples: u32 = @max(4, @as(u32, @intCast(outlined_glyphs / 32)));
    while (zones.items.len < max_statistical_zones) {
        const peak = strongestZonePeak(bottom, top);
        if (peak.score < minimum_samples) break;

        var accumulated: ZoneBin = .{};
        const lo = peak.index -| 1;
        const hi = @min(peak.index + 2, statistical_zone_bin_count);
        const source = if (peak.kind == .bottom) bottom else top;
        for (source[lo..hi]) |bin| accumulated.merge(bin);
        const ref = accumulated.reference() orelse break;
        const max_overshoot = blue_params.max_overshoot_em * em;
        const measured_shoot = accumulated.overshoot() orelse ref;
        var shoot = switch (peak.kind) {
            .bottom => std.math.clamp(measured_shoot, ref - max_overshoot, ref),
            .top => std.math.clamp(measured_shoot, ref, ref + max_overshoot),
        };
        // `FeatureZone` intentionally stays two floats. Preserve bottom/top
        // direction in the sign of a sub-FUnit no-op overshoot when a cluster
        // has no measured round samples; it is far below any pixel threshold.
        if (shoot == ref) shoot += if (peak.kind == .bottom) -em / 65536.0 else em / 65536.0;
        try zones.append(allocator, .{ .pos = ref, .shoot = shoot, .kind = peak.kind });

        // A zone owns an ~1/12 em neighborhood in both directions and kinds.
        // This prevents near-identical top/bottom extrema from becoming two
        // ambiguous references while retaining genuinely separate rails.
        const separation_bins: usize = 5;
        const clear_lo = peak.index -| separation_bins;
        const clear_hi = @min(peak.index + separation_bins + 1, statistical_zone_bin_count);
        @memset(bottom[clear_lo..clear_hi], .{});
        @memset(top[clear_lo..clear_hi], .{});
    }

    return .{
        .allocator = allocator,
        .units_per_em = units_per_em,
        .zones = try zones.toOwnedSlice(allocator),
    };
}

fn addExtremumCandidate(
    bins: *[statistical_zone_bin_count]ZoneBin,
    edges: []const analysis.Edge,
    extremum: f32,
    tolerance: f32,
    em: f32,
) void {
    if (!std.math.isFinite(extremum) or !std.math.isFinite(tolerance) or
        tolerance < 0 or !std.math.isFinite(em) or em <= 0) return;
    var best: ?analysis.Edge = null;
    var best_gap = tolerance;
    for (edges) |edge| {
        if (!std.math.isFinite(edge.pos)) continue;
        const gap = @abs(edge.pos - extremum);
        if (gap >= best_gap) continue;
        best = edge;
        best_gap = gap;
    }
    const edge = best orelse return;
    const scaled = @as(f64, edge.pos) / @as(f64, em) * statistical_zone_bins_per_em;
    if (!std.math.isFinite(scaled)) return;
    const index = @round(scaled) + statistical_zone_bin_offset;
    if (index < 0 or index >= statistical_zone_bin_count) return;
    bins[@intFromFloat(index)].add(edge.pos, edge.round);
}

const ZonePeak = struct {
    index: usize = 0,
    kind: blue_mod.BlueKind = .bottom,
    score: u32 = 0,
    center_count: u32 = 0,
};

fn strongestZonePeak(bottom: *const [statistical_zone_bin_count]ZoneBin, top: *const [statistical_zone_bin_count]ZoneBin) ZonePeak {
    var best: ZonePeak = .{};
    for ([_]struct { kind: blue_mod.BlueKind, bins: *const [statistical_zone_bin_count]ZoneBin }{
        .{ .kind = .bottom, .bins = bottom },
        .{ .kind = .top, .bins = top },
    }) |source| {
        for (source.bins, 0..) |center, i| {
            var score: u32 = 0;
            for (source.bins[i -| 1..@min(i + 2, statistical_zone_bin_count)]) |bin| score += bin.count;
            if (score > best.score or (score == best.score and center.count > best.center_count)) {
                best = .{ .index = i, .kind = source.kind, .score = score, .center_count = center.count };
            }
        }
    }
    return best;
}

fn convertEdges(edges: []const analysis.Edge, upm: f32, zones: []const blue_mod.FeatureZone, out: []FeatureEdge) []const FeatureEdge {
    if (edges.len > max_features_per_axis or edges.len > out.len) return out[0..0];
    var all: [max_features_per_axis]FeatureEdge = undefined;
    for (edges, all[0..edges.len]) |edge, *feature| {
        feature.* = .{
            .pos = edge.pos / upm,
            .width = edge.width / upm,
            .stem = edge.stem,
            .blue = edge.blue,
            .flags = .{ .round = edge.round, .synthetic_apex = edge.synthetic_apex },
        };
    }
    const features = all[0..edges.len];
    for (features, 0..) |*feature, i| {
        feature.flags.semantics_resolved = true;
        feature.flags.blue_dir_negative = semanticDirection(features, zones, i, true) < 0;
    }
    for (features, 0..) |*feature, i| {
        if (feature.blue < 0 or !feature.flags.round) continue;
        feature.flags.grid_companion = findCompanion(features, zones, i, false);
        feature.flags.blue_companion = findCompanion(features, zones, i, true);
    }

    // Once semantic relationships are explicit, unrelated outline extrema no
    // longer participate in fitting. Keep only actual stem/blue operations and
    // the companions referenced by those operations; remap their indices into
    // a compact, ppem-independent fit program.
    var keep = [_]bool{false} ** max_features_per_axis;
    for (features, 0..) |feature, i| keep[i] = feature.stem >= 0 or feature.blue >= 0;
    for (features) |feature| {
        if (feature.flags.grid_companion < 62) keep[feature.flags.grid_companion] = true;
        if (feature.flags.blue_companion < 62) keep[feature.flags.blue_companion] = true;
    }
    var remap = [_]i16{-1} ** max_features_per_axis;
    var count: usize = 0;
    for (features, 0..) |feature, i| {
        if (!keep[i]) continue;
        remap[i] = @intCast(count);
        out[count] = feature;
        count += 1;
    }
    for (out[0..count]) |*feature| {
        if (feature.stem >= 0) feature.stem = remap[@intCast(feature.stem)];
        feature.flags.grid_companion = remapCompanion(feature.flags.grid_companion, &remap);
        feature.flags.blue_companion = remapCompanion(feature.flags.blue_companion, &remap);
    }
    return out[0..count];
}

fn remapCompanion(encoded: u6, remap: *const [max_features_per_axis]i16) u6 {
    if (encoded >= 62) return encoded;
    const mapped = remap[encoded];
    return if (mapped < 0) 62 else @intCast(mapped);
}

fn semanticDirection(features: []const FeatureEdge, zones: []const blue_mod.FeatureZone, index: usize, use_blues: bool) i8 {
    const feature = features[index];
    const partner_above = feature.stem >= 0 and @as(usize, @intCast(feature.stem)) < features.len and
        features[@intCast(feature.stem)].pos > feature.pos;
    const valid_blue = use_blues and feature.blue >= 0 and @as(usize, @intCast(feature.blue)) < zones.len;
    const bottom_blue = valid_blue and zones[@intCast(feature.blue)].shoot < zones[@intCast(feature.blue)].ref;
    if (partner_above or bottom_blue) return -1;
    if (feature.stem >= 0 or valid_blue or !use_blues) return 1;

    var nearest = std.math.inf(f32);
    var direction: i8 = 1;
    for (features) |candidate| {
        if (candidate.blue < 0 or @as(usize, @intCast(candidate.blue)) >= zones.len) continue;
        const gap = @abs(candidate.pos - feature.pos);
        if (gap >= nearest) continue;
        nearest = gap;
        const zone = zones[@intCast(candidate.blue)];
        direction = if (zone.shoot < zone.ref) 1 else -1;
    }
    return direction;
}

fn findCompanion(features: []const FeatureEdge, zones: []const blue_mod.FeatureZone, index: usize, use_blues: bool) u6 {
    const direction = semanticDirection(features, zones, index, use_blues);
    const top = direction > 0;
    var best: u6 = 62;
    var best_gap = std.math.inf(f32);
    for (features, 0..) |candidate, candidate_index| {
        if (candidate_index == index or semanticDirection(features, zones, candidate_index, use_blues) == direction) continue;
        const gap = if (top) features[index].pos - candidate.pos else candidate.pos - features[index].pos;
        if (gap <= 0 or gap >= best_gap) continue;
        best_gap = gap;
        best = @intCast(candidate_index);
    }
    return best;
}

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
    const base = pts.items.len;
    _ = std.math.cast(u32, base) orelse return error.InvalidFont;
    for (s.contours) |c| {
        if (c.start > c.end or c.end > s.points.len) return error.InvalidFont;
        const end = std.math.add(usize, base, c.end) catch return error.InvalidFont;
        _ = std.math.cast(u32, end) orelse return error.InvalidFont;
    }
    for (s.points) |p| {
        const v = Vec2.add(transform.apply(.{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) }), offset);
        _ = roundedI16(v.x) orelse return error.InvalidFont;
        _ = roundedI16(v.y) orelse return error.InvalidFont;
    }

    try contours.ensureUnusedCapacity(allocator, s.contours.len);
    try pts.ensureUnusedCapacity(allocator, s.points.len);
    for (s.contours) |c| {
        contours.appendAssumeCapacity(.{
            .start = @intCast(base + @as(usize, c.start)),
            .end = @intCast(base + @as(usize, c.end)),
        });
    }
    for (s.points) |p| {
        const v = Vec2.add(transform.apply(.{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) }), offset);
        pts.appendAssumeCapacity(.{
            .x = roundedI16(v.x).?,
            .y = roundedI16(v.y).?,
            .on_curve = p.on_curve,
        });
    }
}

fn roundedI16(value: f32) ?i16 {
    if (!std.math.isFinite(value)) return null;
    const rounded = @round(@as(f64, value));
    if (rounded < std.math.minInt(i16) or rounded > std.math.maxInt(i16)) return null;
    return @intFromFloat(rounded);
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");

test "compound flattening rejects unrepresentable transforms atomically" {
    var source_points = [_]outline.Point{.{ .x = std.math.maxInt(i16), .y = 1, .on_curve = true }};
    var source_contours = [_]outline.ContourRange{.{ .start = 0, .end = 1 }};
    const simple = outline.SimpleGlyph{
        .allocator = testing.allocator,
        .contours = &source_contours,
        .points = &source_points,
        .instructions = &.{},
    };
    var points: std.ArrayList(outline.Point) = .empty;
    defer points.deinit(testing.allocator);
    var contours: std.ArrayList(outline.ContourRange) = .empty;
    defer contours.deinit(testing.allocator);

    try testing.expectError(error.InvalidFont, appendSimple(
        testing.allocator,
        simple,
        .{ .xx = std.math.floatMax(f32), .yy = 1 },
        .zero,
        &points,
        &contours,
    ));
    try testing.expectEqual(@as(usize, 0), points.items.len);
    try testing.expectEqual(@as(usize, 0), contours.items.len);
}

test "statistical extrema ignore non-finite producer values" {
    var bins = [_]ZoneBin{.{}} ** statistical_zone_bin_count;
    addExtremumCandidate(&bins, &.{.{
        .pos = std.math.nan(f32),
        .min = 0,
        .max = 0,
        .dir = 1,
    }}, 0, 1, 1000);
    for (bins) |bin| try testing.expectEqual(@as(u32, 0), bin.count);
}

test "glyph analysis contains features but no fitted targets" {
    const test_font = assets.dejavu_sans_mono;
    var analyzer = try AutohintAnalyzer.init(testing.allocator, test_font);
    defer analyzer.deinit();
    const glyph_h = try analyzer.font.glyphIndex('H');
    var xb: [max_features_per_axis]FeatureEdge = undefined;
    var yb: [max_features_per_axis]FeatureEdge = undefined;
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    try testing.expect(a.x.len > 0);
    try testing.expect(a.y.len > 0);
    try testing.expect(@hasField(FeatureEdge, "pos"));
    try testing.expect(!@hasField(FeatureEdge, "target"));
}

test "font analysis is normalized once" {
    var analyzer = try AutohintAnalyzer.init(testing.allocator, assets.dejavu_sans_mono);
    defer analyzer.deinit();
    const features = analyzer.fontFeatures();
    try testing.expect(features.blues.len > 0);
    try testing.expect(features.std_x > 0 and features.std_x < 1);
    try testing.expect(features.std_y > 0 and features.std_y < 1);
    for (features.blues) |zone| {
        try testing.expect(@abs(zone.ref) < 2);
        try testing.expect(@abs(zone.shoot) < 2);
    }
}

test "CFF2 autohint analyzes the selected variable instance" {
    const light_coordinates = [_]font_mod.Variation{.{ .tag = "wght".*, .value = 200 }};
    const heavy_coordinates = [_]font_mod.Variation{.{ .tag = "wght".*, .value = 900 }};
    var light_font = try font_mod.Font.initWithOptions(
        assets.source_serif_cff2_variable,
        .{ .variations = &light_coordinates },
    );
    var heavy_font = try font_mod.Font.initWithOptions(
        assets.source_serif_cff2_variable,
        .{ .variations = &heavy_coordinates },
    );
    var light = try AutohintAnalyzer.initFont(testing.allocator, &light_font);
    defer light.deinit();
    var heavy = try AutohintAnalyzer.initFont(testing.allocator, &heavy_font);
    defer heavy.deinit();

    const glyph_id = try light_font.glyphIndex('m');
    var light_x: [max_features_per_axis]FeatureEdge = undefined;
    var light_y: [max_features_per_axis]FeatureEdge = undefined;
    var heavy_x: [max_features_per_axis]FeatureEdge = undefined;
    var heavy_y: [max_features_per_axis]FeatureEdge = undefined;
    const light_glyph = try light.analyzeGlyph(testing.allocator, glyph_id, &light_x, &light_y);
    const heavy_glyph = try heavy.analyzeGlyph(testing.allocator, glyph_id, &heavy_x, &heavy_y);
    try testing.expect(light_glyph.x.len > 0);
    try testing.expect(heavy_glyph.x.len > 0);
    try testing.expect(light.fontFeatures().std_x != heavy.fontFeatures().std_x);
}

test "repeated analysis has one result independent of size" {
    const test_font = assets.dejavu_sans_mono;
    var analyzer = try AutohintAnalyzer.init(testing.allocator, test_font);
    defer analyzer.deinit();
    const glyph_h = try analyzer.font.glyphIndex('H');
    var xb: [max_features_per_axis]FeatureEdge = undefined;
    var yb: [max_features_per_axis]FeatureEdge = undefined;
    var xb2: [max_features_per_axis]FeatureEdge = undefined;
    var yb2: [max_features_per_axis]FeatureEdge = undefined;
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    const b = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb2, &yb2);
    try testing.expectEqualSlices(FeatureEdge, a.x, b.x);
    try testing.expectEqualSlices(FeatureEdge, a.y, b.y);
}

test "statistical zones retain non-Latin reference edges" {
    const Case = struct { data: []const u8, codepoint: u21 };
    const cases = [_]Case{
        .{ .data = assets.noto_sans_arabic, .codepoint = 0x0645 }, // Arabic meem
        .{ .data = assets.noto_sans_devanagari, .codepoint = 0x0915 }, // Devanagari ka
        .{ .data = assets.noto_sans_mongolian, .codepoint = 0x1820 }, // Mongolian a
    };
    for (cases) |case| {
        var analyzer = try AutohintAnalyzer.init(testing.allocator, case.data);
        defer analyzer.deinit();
        try testing.expect(analyzer.blues.zones.len > 0);
        try testing.expect(analyzer.blues.zones.len <= max_statistical_zones);

        const glyph_id = try analyzer.font.glyphIndex(case.codepoint);
        var feature_x: [max_features_per_axis]FeatureEdge = undefined;
        var feature_y: [max_features_per_axis]FeatureEdge = undefined;
        const glyph = try analyzer.analyzeGlyph(testing.allocator, glyph_id, &feature_x, &feature_y);
        try testing.expect(glyph.y.len > 0 and glyph.y.len <= 16);
        var has_reference = false;
        for (glyph.y) |feature| if (feature.blue >= 0) {
            has_reference = true;
        };
        try testing.expect(has_reference);
    }
}
