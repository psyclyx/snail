const std = @import("std");
const bezier = @import("math/bezier.zig");
const vec = @import("math/vec.zig");

const Vec2 = vec.Vec2;
const BBox = bezier.BBox;
const QuadBezier = bezier.QuadBezier;

pub const GlyphHintSource = struct {
    stem_count: u8 = 0,
    stems: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const GlyphHintInstance = struct {
    stem_count: u8 = 0,
    source: [4]f32 = .{ 0, 0, 0, 0 },
    display: [4]f32 = .{ 0, 0, 0, 0 },
};

const EdgeCluster = struct {
    x_weighted: f32,
    y_min: f32,
    y_max: f32,
    weight: f32,

    fn centerX(self: EdgeCluster) f32 {
        return self.x_weighted / @max(self.weight, 1e-6);
    }
};

const StemCandidate = struct {
    left: f32,
    right: f32,
    score: f32,
};

fn bboxHeight(bbox: BBox) f32 {
    return bbox.max.y - bbox.min.y;
}

fn bboxWidth(bbox: BBox) f32 {
    return bbox.max.x - bbox.min.x;
}

fn curveBox(curve: QuadBezier) BBox {
    return curve.boundingBox();
}

fn candidateEdgeX(curve: QuadBezier) f32 {
    const mid = curve.evaluate(0.5);
    return (curve.p0.x + mid.x + curve.p2.x) * (1.0 / 3.0);
}

fn addEdgeCluster(clusters: []EdgeCluster, cluster_count: *usize, x: f32, y_min: f32, y_max: f32, weight: f32, merge_tol: f32) void {
    for (clusters[0..cluster_count.*]) |*cluster| {
        if (@abs(cluster.centerX() - x) <= merge_tol) {
            cluster.x_weighted += x * weight;
            cluster.weight += weight;
            cluster.y_min = @min(cluster.y_min, y_min);
            cluster.y_max = @max(cluster.y_max, y_max);
            return;
        }
    }
    if (cluster_count.* >= clusters.len) return;
    clusters[cluster_count.*] = .{
        .x_weighted = x * weight,
        .y_min = y_min,
        .y_max = y_max,
        .weight = weight,
    };
    cluster_count.* += 1;
}

fn edgeClusterLessThan(_: void, lhs: EdgeCluster, rhs: EdgeCluster) bool {
    return lhs.centerX() < rhs.centerX();
}

fn stemCandidateLessThan(_: void, lhs: StemCandidate, rhs: StemCandidate) bool {
    return lhs.score > rhs.score;
}

pub fn analyzeQuadGlyph(curves: []const QuadBezier, bbox: BBox) GlyphHintSource {
    const width = bboxWidth(bbox);
    const height = bboxHeight(bbox);
    if (curves.len == 0 or width <= 1e-4 or height <= 1e-4) return .{};

    var clusters: [16]EdgeCluster = undefined;
    var cluster_count: usize = 0;
    const merge_tol = @max(width * 0.04, 0.01);
    const min_edge_height = @max(height * 0.18, 0.06);
    const max_edge_width = @max(width * 0.08, 0.03);

    for (curves) |curve| {
        const cb = curveBox(curve);
        const dx = cb.max.x - cb.min.x;
        const dy = cb.max.y - cb.min.y;
        if (dy < min_edge_height) continue;
        if (dx > @max(max_edge_width, dy * 0.35)) continue;

        const center_x = candidateEdgeX(curve);
        addEdgeCluster(&clusters, &cluster_count, center_x, cb.min.y, cb.max.y, dy, merge_tol);
    }

    if (cluster_count < 2) return .{};
    std.sort.heap(EdgeCluster, clusters[0..cluster_count], {}, edgeClusterLessThan);

    var candidates: [16]StemCandidate = undefined;
    var candidate_count: usize = 0;
    const min_overlap = height * 0.22;
    const min_stem_width = @max(width * 0.03, 0.02);
    const max_stem_width = width * 0.38;

    for (clusters[0..cluster_count], 0..) |left_cluster, i| {
        for (clusters[i + 1 .. cluster_count]) |right_cluster| {
            const left_x = left_cluster.centerX();
            const right_x = right_cluster.centerX();
            const stem_width = right_x - left_x;
            if (stem_width < min_stem_width or stem_width > max_stem_width) continue;

            const overlap = @min(left_cluster.y_max, right_cluster.y_max) - @max(left_cluster.y_min, right_cluster.y_min);
            if (overlap < min_overlap) continue;

            const score = overlap * (left_cluster.weight + right_cluster.weight) / @max(stem_width, 1e-4);
            if (candidate_count < candidates.len) {
                candidates[candidate_count] = .{
                    .left = left_x,
                    .right = right_x,
                    .score = score,
                };
                candidate_count += 1;
            }
        }
    }

    if (candidate_count == 0) return .{};
    std.sort.heap(StemCandidate, candidates[0..candidate_count], {}, stemCandidateLessThan);

    var result = GlyphHintSource{};
    for (candidates[0..candidate_count]) |candidate| {
        if (result.stem_count == 0) {
            result.stems[0] = candidate.left;
            result.stems[1] = candidate.right;
            result.stem_count = 1;
            continue;
        }
        if (candidate.right <= result.stems[0] + width * 0.02 or candidate.left >= result.stems[1] - width * 0.02) {
            result.stems[2] = candidate.left;
            result.stems[3] = candidate.right;
            result.stem_count = 2;
            break;
        }
    }

    if (result.stem_count == 2 and result.stems[2] < result.stems[0]) {
        const left0 = result.stems[0];
        const right0 = result.stems[1];
        result.stems[0] = result.stems[2];
        result.stems[1] = result.stems[3];
        result.stems[2] = left0;
        result.stems[3] = right0;
    }

    return result;
}

fn snapToGrid(value: f32, step: f32) f32 {
    if (step <= 0) return value;
    return @round(value / step) * step;
}

fn resolveOneStem(source: GlyphHintSource, bbox: BBox, screen_tx: f32, screen_xx: f32, grid_step: f32) GlyphHintInstance {
    var hint = GlyphHintInstance{
        .stem_count = 1,
        .source = source.stems,
        .display = source.stems,
    };

    const stem_min = source.stems[0];
    const stem_max = source.stems[1];
    const bbox_min_screen = screen_tx + bbox.min.x * screen_xx;
    const bbox_max_screen = screen_tx + bbox.max.x * screen_xx;

    var left = snapToGrid(screen_tx + stem_min * screen_xx, grid_step);
    var right = snapToGrid(screen_tx + stem_max * screen_xx, grid_step);
    if (right < left) std.mem.swap(f32, &left, &right);
    if (right - left < grid_step) right = left + grid_step;
    if (left <= bbox_min_screen or right >= bbox_max_screen) return .{};

    hint.display[0] = (left - screen_tx) / screen_xx;
    hint.display[1] = (right - screen_tx) / screen_xx;
    return hint;
}

fn resolveTwoStems(source: GlyphHintSource, bbox: BBox, screen_tx: f32, screen_xx: f32, grid_step: f32) GlyphHintInstance {
    var hint = GlyphHintInstance{
        .stem_count = 2,
        .source = source.stems,
        .display = source.stems,
    };

    const bbox_min_screen = screen_tx + bbox.min.x * screen_xx;
    const bbox_max_screen = screen_tx + bbox.max.x * screen_xx;

    var left0 = snapToGrid(screen_tx + source.stems[0] * screen_xx, grid_step);
    var right0 = snapToGrid(screen_tx + source.stems[1] * screen_xx, grid_step);
    var left1 = snapToGrid(screen_tx + source.stems[2] * screen_xx, grid_step);
    var right1 = snapToGrid(screen_tx + source.stems[3] * screen_xx, grid_step);

    if (right0 < left0) std.mem.swap(f32, &left0, &right0);
    if (right1 < left1) std.mem.swap(f32, &left1, &right1);
    if (right0 - left0 < grid_step) right0 = left0 + grid_step;
    if (right1 - left1 < grid_step) right1 = left1 + grid_step;
    if (left1 <= right0) return .{};
    if (left0 <= bbox_min_screen or right1 >= bbox_max_screen) return .{};

    hint.display[0] = (left0 - screen_tx) / screen_xx;
    hint.display[1] = (right0 - screen_tx) / screen_xx;
    hint.display[2] = (left1 - screen_tx) / screen_xx;
    hint.display[3] = (right1 - screen_tx) / screen_xx;
    return hint;
}

pub fn resolveGlyphHint(source: GlyphHintSource, bbox: BBox, screen_tx: f32, screen_xx: f32, grid_step: f32) GlyphHintInstance {
    if (source.stem_count == 0) return .{};
    if (grid_step <= 0 or @abs(screen_xx) <= 1e-5) return .{};
    if (screen_xx < 0) return .{};

    return switch (source.stem_count) {
        1 => resolveOneStem(source, bbox, screen_tx, screen_xx, grid_step),
        2 => resolveTwoStems(source, bbox, screen_tx, screen_xx, grid_step),
        else => .{},
    };
}

fn mapSegment(display_x: f32, display_a: f32, display_b: f32, source_a: f32, source_b: f32) f32 {
    const span = display_b - display_a;
    if (@abs(span) <= 1e-6) return source_a;
    return source_a + (display_x - display_a) * ((source_b - source_a) / span);
}

fn segmentScale(display_a: f32, display_b: f32, source_a: f32, source_b: f32) f32 {
    const span = display_b - display_a;
    if (@abs(span) <= 1e-6) return 1.0;
    return (source_b - source_a) / span;
}

pub fn inverseWarpX(hint: GlyphHintInstance, bbox: BBox, display_x: f32) f32 {
    return switch (hint.stem_count) {
        0 => display_x,
        1 => blk: {
            const d0 = hint.display[0];
            const d1 = hint.display[1];
            const s0 = hint.source[0];
            const s1 = hint.source[1];
            if (display_x <= d0) break :blk mapSegment(display_x, bbox.min.x, d0, bbox.min.x, s0);
            if (display_x <= d1) break :blk mapSegment(display_x, d0, d1, s0, s1);
            break :blk mapSegment(display_x, d1, bbox.max.x, s1, bbox.max.x);
        },
        2 => blk: {
            const d0 = hint.display[0];
            const d1 = hint.display[1];
            const d2 = hint.display[2];
            const d3 = hint.display[3];
            const s0 = hint.source[0];
            const s1 = hint.source[1];
            const s2 = hint.source[2];
            const s3 = hint.source[3];
            if (display_x <= d0) break :blk mapSegment(display_x, bbox.min.x, d0, bbox.min.x, s0);
            if (display_x <= d1) break :blk mapSegment(display_x, d0, d1, s0, s1);
            if (display_x <= d2) break :blk mapSegment(display_x, d1, d2, s1, s2);
            if (display_x <= d3) break :blk mapSegment(display_x, d2, d3, s2, s3);
            break :blk mapSegment(display_x, d3, bbox.max.x, s3, bbox.max.x);
        },
        else => display_x,
    };
}

pub fn inverseWarpScaleX(hint: GlyphHintInstance, bbox: BBox, display_x: f32) f32 {
    return switch (hint.stem_count) {
        0 => 1.0,
        1 => blk: {
            const d0 = hint.display[0];
            const d1 = hint.display[1];
            const s0 = hint.source[0];
            const s1 = hint.source[1];
            if (display_x <= d0) break :blk segmentScale(bbox.min.x, d0, bbox.min.x, s0);
            if (display_x <= d1) break :blk segmentScale(d0, d1, s0, s1);
            break :blk segmentScale(d1, bbox.max.x, s1, bbox.max.x);
        },
        2 => blk: {
            const d0 = hint.display[0];
            const d1 = hint.display[1];
            const d2 = hint.display[2];
            const d3 = hint.display[3];
            const s0 = hint.source[0];
            const s1 = hint.source[1];
            const s2 = hint.source[2];
            const s3 = hint.source[3];
            if (display_x <= d0) break :blk segmentScale(bbox.min.x, d0, bbox.min.x, s0);
            if (display_x <= d1) break :blk segmentScale(d0, d1, s0, s1);
            if (display_x <= d2) break :blk segmentScale(d1, d2, s1, s2);
            if (display_x <= d3) break :blk segmentScale(d2, d3, s2, s3);
            break :blk segmentScale(d3, bbox.max.x, s3, bbox.max.x);
        },
        else => 1.0,
    };
}

test "analyzeQuadGlyph detects a single vertical stem" {
    const curves = [_]QuadBezier{
        .{ .p0 = Vec2.new(0.10, 0.0), .p1 = Vec2.new(0.10, 0.5), .p2 = Vec2.new(0.10, 1.0) },
        .{ .p0 = Vec2.new(0.18, 1.0), .p1 = Vec2.new(0.18, 0.5), .p2 = Vec2.new(0.18, 0.0) },
    };
    const hint = analyzeQuadGlyph(&curves, .{
        .min = Vec2.new(0.0, 0.0),
        .max = Vec2.new(0.3, 1.0),
    });
    try std.testing.expectEqual(@as(u8, 1), hint.stem_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.10), hint.stems[0], 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.18), hint.stems[1], 0.01);
}

test "analyzeQuadGlyph rejects diagonal edges" {
    const curves = [_]QuadBezier{
        .{ .p0 = Vec2.new(0.0, 0.0), .p1 = Vec2.new(0.15, 0.5), .p2 = Vec2.new(0.3, 1.0) },
        .{ .p0 = Vec2.new(0.6, 1.0), .p1 = Vec2.new(0.45, 0.5), .p2 = Vec2.new(0.3, 0.0) },
    };
    const hint = analyzeQuadGlyph(&curves, .{
        .min = Vec2.new(0.0, 0.0),
        .max = Vec2.new(0.6, 1.0),
    });
    try std.testing.expectEqual(@as(u8, 0), hint.stem_count);
}

test "inverseWarpX remaps through a single stem span" {
    const hint = GlyphHintInstance{
        .stem_count = 1,
        .source = .{ 0.2, 0.3, 0, 0 },
        .display = .{ 0.25, 0.35, 0, 0 },
    };
    const bbox = BBox{
        .min = Vec2.new(0.0, 0.0),
        .max = Vec2.new(1.0, 1.0),
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0.20), inverseWarpX(hint, bbox, 0.25), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.30), inverseWarpX(hint, bbox, 0.35), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.48846155), inverseWarpX(hint, bbox, 0.525), 0.0001);
}

test "inverseWarpScaleX matches each hinted span slope" {
    const hint = GlyphHintInstance{
        .stem_count = 1,
        .source = .{ 0.2, 0.3, 0, 0 },
        .display = .{ 0.25, 0.35, 0, 0 },
    };
    const bbox = BBox{
        .min = Vec2.new(0.0, 0.0),
        .max = Vec2.new(1.0, 1.0),
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), inverseWarpScaleX(hint, bbox, 0.10), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), inverseWarpScaleX(hint, bbox, 0.30), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7 / 0.65), inverseWarpScaleX(hint, bbox, 0.60), 0.0001);
}
