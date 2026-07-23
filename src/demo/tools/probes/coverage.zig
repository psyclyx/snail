//! Faithful CPU port of the GL path coverage evaluator (`evalGlyphCoverage`
//! + the axis scans in snail_path_frag_body.glsl), evaluating ALL segments (no
//! band split — for a single-band footprint that is the same winding). Two conic
//! solvers are selectable: `.deriv` (the shipping derivative-sign + isNearEndRoot
//! form) and `.code` (the candidate calcRootCode parity form). It sweeps rc over
//! a fine grid at a chosen anisotropic footprint and reports interior coverage
//! "holes" (a near-zero pixel whose rc-neighbors are near-full) for each method
//! and each authoring frame. Deterministic, no GPU, printf-friendly.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");

const kParamEps: f32 = 1e-5;
const kCoordEps: f32 = 1.0 / 65536.0;
var verbose: bool = false;

const Method = enum { deriv, code };

const Seg = struct {
    kind: u8, // 1 conic, 3 line
    p0: [2]f32,
    p1: [2]f32,
    p2: [2]f32,
    w: [3]f32,
};

fn f16q(v: f32) f32 {
    return @as(f32, @as(f16, @floatCast(v)));
}

fn appendCoverage(cov: *f32, wgt: *f32, distance: f32, sign: f32) void {
    cov.* += sign * std.math.clamp(distance + 0.5, 0.0, 1.0);
    wgt.* = @max(wgt.*, std.math.clamp(1.0 - @abs(distance) * 2.0, 0.0, 1.0));
}

fn distToUnit(t: f32) f32 {
    return @max(@max(0.0, -t), t - 1.0);
}

fn snapNearTangentSqrt(disc: f32, b: f32, ac: f32) f32 {
    const tol = @max(b * b, @abs(ac)) * 3.0e-6;
    return if (disc <= tol) 0.0 else @sqrt(disc);
}

fn rootCodeCoord(v: f32) f32 {
    return if (@abs(v) <= kCoordEps) 0.0 else v;
}
fn calcRootCode(y1v: f32, y2v: f32, y3v: f32) u32 {
    const y1 = rootCodeCoord(y1v);
    const y2 = rootCodeCoord(y2v);
    const y3 = rootCodeCoord(y3v);
    const s1: u32 = @as(u32, @bitCast(y1)) >> 31;
    const s2: u32 = @as(u32, @bitCast(y2)) >> 30;
    const s3: u32 = @as(u32, @bitCast(y3)) >> 29;
    var shift: u32 = (s2 & 2) | (s1 & ~@as(u32, 2));
    shift = (s3 & 4) | (shift & ~@as(u32, 4));
    return (@as(u32, 0x2E74) >> @as(u5, @intCast(shift & 0x1F))) & 0x0101;
}

fn segMaxAlong(seg: Seg, horizontal: bool) f32 {
    const a0 = if (horizontal) seg.p0[0] else seg.p0[1];
    const a1 = if (horizontal) seg.p1[0] else seg.p1[1];
    const a2 = if (horizontal) seg.p2[0] else seg.p2[1];
    if (seg.kind == 3) return @max(a0, a2);
    return @max(@max(a0, a1), a2);
}

fn lineContrib(cov: *f32, wgt: *f32, seg: Seg, srx: f32, sry: f32, ppe: f32, horizontal: bool) void {
    const p0x = seg.p0[0] - srx;
    const p0y = seg.p0[1] - sry;
    const p2x = seg.p2[0] - srx;
    const p2y = seg.p2[1] - sry;
    const rootAxis0 = if (horizontal) p0y else p0x;
    const rootAxis2 = if (horizontal) p2y else p2x;
    // Half-open sign-of-zero crossing test (mirrors calcRootCode): a vertex
    // exactly on the scanline snaps to +0 and counts as the positive side, so a
    // shared vertex is owned by exactly one segment. Replaces the fragile
    // isEndpointRootDelta end-skip, which discarded a junction crossing the line
    // actually owns when the neighbouring conic's start root FP-drifted out of
    // [0,1] → both dropped it → interior pixel to zero winding.
    const a0 = rootCodeCoord(rootAxis0);
    const a2 = rootCodeCoord(rootAxis2);
    if ((a0 < 0.0) == (a2 < 0.0)) return;
    const denom = rootAxis2 - rootAxis0;
    if (@abs(denom) < 1e-10) return;
    const t = std.math.clamp(-rootAxis0 / denom, 0.0, 1.0);
    const derivativeAxis = if (horizontal) (p2y - p0y) else (p0x - p2x);
    if (@abs(derivativeAxis) <= kParamEps) return;
    const distance = (if (horizontal) (p0x + (p2x - p0x) * t) else (p0y + (p2y - p0y) * t)) * ppe;
    appendCoverage(cov, wgt, distance, if (derivativeAxis > 0.0) 1.0 else -1.0);
}

fn conicDeriv(cov: *f32, wgt: *f32, seg: Seg, srx: f32, sry: f32, ppe: f32, horizontal: bool) void {
    const sampleRoot = if (horizontal) sry else srx;
    const sampleAlong = if (horizontal) srx else sry;
    const p0Root = if (horizontal) seg.p0[1] else seg.p0[0];
    const p1Root = if (horizontal) seg.p1[1] else seg.p1[0];
    const p2Root = if (horizontal) seg.p2[1] else seg.p2[0];
    const p0A = if (horizontal) seg.p0[0] else seg.p0[1];
    const p1A = if (horizontal) seg.p1[0] else seg.p1[1];
    const p2A = if (horizontal) seg.p2[0] else seg.p2[1];
    const c0 = seg.w[0] * (p0Root - sampleRoot);
    const c1 = seg.w[1] * (p1Root - sampleRoot);
    const c2 = seg.w[2] * (p2Root - sampleRoot);
    // calcRootCode (sign-of-zero) is the robust source of truth for the crossing
    // count/ownership. The polynomial solve only supplies the parameter values,
    // which can FP-drift just outside [0,1] at a shared vertex; clamp them in
    // rather than reject, so a crossing the conic owns is never dropped.
    const code = calcRootCode(c0, c1, c2);
    if (code == 0) {
        if (verbose) std.debug.print("      conicDeriv: GATED (code==0)\n", .{});
        return;
    }
    const want: u8 = if (code == 0x101) 2 else 1;
    const quadA = c0 - 2.0 * c1 + c2;
    const quadB = 2.0 * (c1 - c0);
    var cand: [2]f32 = .{ 0, 0 };
    var ncand: u8 = 0;
    if (@abs(quadA) < kCoordEps) {
        if (@abs(quadB) >= kCoordEps) {
            cand[0] = -c0 / quadB;
            ncand = 1;
        }
    } else {
        var disc = quadB * quadB - 4.0 * quadA * c0;
        if (disc < 0.0) disc = 0.0; // near-tangent: double root at the vertex
        const sq = @sqrt(disc);
        const inv2a = 0.5 / quadA;
        cand[0] = (-quadB - sq) * inv2a;
        cand[1] = (-quadB + sq) * inv2a;
        ncand = 2;
    }
    const endRootDelta = (if (horizontal) seg.p2[1] else seg.p2[0]) - sampleRoot;
    if (verbose) std.debug.print("      conicDeriv: code=0x{X} want={d} cand=[{d:.5},{d:.5}] ncand={d}\n", .{ code, want, cand[0], cand[1], ncand });
    if (want == 1) {
        // Pick the candidate nearest [0,1]; clamp it in.
        var best = cand[0];
        if (ncand == 2 and distToUnit(cand[1]) < distToUnit(cand[0])) best = cand[1];
        if (ncand > 0) conicDerivRoot(cov, wgt, std.math.clamp(best, 0.0, 1.0), endRootDelta, sampleAlong, ppe, horizontal, seg, p0Root, p1Root, p2Root, p0A, p1A, p2A);
    } else {
        conicDerivRoot(cov, wgt, std.math.clamp(cand[0], 0.0, 1.0), endRootDelta, sampleAlong, ppe, horizontal, seg, p0Root, p1Root, p2Root, p0A, p1A, p2A);
        if (ncand == 2) conicDerivRoot(cov, wgt, std.math.clamp(cand[1], 0.0, 1.0), endRootDelta, sampleAlong, ppe, horizontal, seg, p0Root, p1Root, p2Root, p0A, p1A, p2A);
    }
}

fn conicDerivRoot(cov: *f32, wgt: *f32, t: f32, endRootDelta: f32, sampleAlong: f32, ppe: f32, horizontal: bool, seg: Seg, p0Root: f32, p1Root: f32, p2Root: f32, p0A: f32, p1A: f32, p2A: f32) void {
    const rootA = p0Root * seg.w[0] - 2.0 * p1Root * seg.w[1] + p2Root * seg.w[2];
    const rootB = 2.0 * (p1Root * seg.w[1] - p0Root * seg.w[0]);
    const rootC = p0Root * seg.w[0];
    const alongA = p0A * seg.w[0] - 2.0 * p1A * seg.w[1] + p2A * seg.w[2];
    const alongB = 2.0 * (p1A * seg.w[1] - p0A * seg.w[0]);
    const alongC = p0A * seg.w[0];
    const denA = seg.w[0] - 2.0 * seg.w[1] + seg.w[2];
    const denB = 2.0 * (seg.w[1] - seg.w[0]);
    const denC = seg.w[0];
    const den = @max((denA * t + denB) * t + denC, kCoordEps);
    const along = ((alongA * t + alongB) * t + alongC) / den;
    const rootNumer = (rootA * t + rootB) * t + rootC;
    const rootPrime = 2.0 * rootA * t + rootB;
    const denPrime = 2.0 * denA * t + denB;
    var derivAxis = (rootPrime * den - rootNumer * denPrime) / (den * den);
    if (!horizontal) derivAxis = -derivAxis;
    if (verbose) std.debug.print("        root t={d:.5} endDelta={e:.3} derivAxis={e:.3} along={d:.5} isNearEnd={} killByEndSkip={}\n", .{ t, endRootDelta, derivAxis, along, t >= 1.0 - kParamEps, (t >= 1.0 - kParamEps and @abs(endRootDelta) <= kCoordEps) });
    if (@abs(derivAxis) <= kParamEps) return;
    const dist = (along - sampleAlong) * ppe;
    appendCoverage(cov, wgt, dist, if (derivAxis > 0.0) 1.0 else -1.0);
}

fn conicAlongDist(seg: Seg, t: f32, p0A: f32, p1A: f32, p2A: f32, sampleAlong: f32, ppe: f32) f32 {
    const u = 1.0 - t;
    const num = seg.w[0] * p0A * u * u + 2.0 * seg.w[1] * p1A * t * u + seg.w[2] * p2A * t * t;
    const den = @max(seg.w[0] * u * u + 2.0 * seg.w[1] * t * u + seg.w[2] * t * t, kCoordEps);
    return (num / den - sampleAlong) * ppe;
}

fn conicCode(cov: *f32, wgt: *f32, seg: Seg, srx: f32, sry: f32, ppe: f32, horizontal: bool) void {
    const sampleRoot = if (horizontal) sry else srx;
    const sampleAlong = if (horizontal) srx else sry;
    const p0Root = if (horizontal) seg.p0[1] else seg.p0[0];
    const p1Root = if (horizontal) seg.p1[1] else seg.p1[0];
    const p2Root = if (horizontal) seg.p2[1] else seg.p2[0];
    const p0A = if (horizontal) seg.p0[0] else seg.p0[1];
    const p1A = if (horizontal) seg.p1[0] else seg.p1[1];
    const p2A = if (horizontal) seg.p2[0] else seg.p2[1];
    const c0 = seg.w[0] * (p0Root - sampleRoot);
    const c1 = seg.w[1] * (p1Root - sampleRoot);
    const c2 = seg.w[2] * (p2Root - sampleRoot);
    const code = calcRootCode(c0, c1, c2);
    if (code == 0) return;
    const aRoot = c0 - 2.0 * c1 + c2;
    const bHalf = c0 - c1;
    var t0: f32 = undefined;
    var t1: f32 = undefined;
    if (@abs(aRoot) < kCoordEps) {
        t0 = if (@abs(bHalf) < kCoordEps) 0.0 else c0 * 0.5 / bHalf;
        t1 = t0;
    } else {
        const sq = snapNearTangentSqrt(bHalf * bHalf - aRoot * c0, bHalf, aRoot * c0);
        if (bHalf >= 0.0) {
            const q = bHalf + sq;
            t1 = q / aRoot;
            t0 = if (@abs(q) < kCoordEps) 0.0 else c0 / q;
        } else {
            const q = bHalf - sq;
            t0 = q / aRoot;
            t1 = if (@abs(q) < kCoordEps) 0.0 else c0 / q;
        }
    }
    const s0: f32 = if (horizontal) 1.0 else -1.0;
    const s1: f32 = if (horizontal) -1.0 else 1.0;
    if ((code & 1) != 0) appendCoverage(cov, wgt, conicAlongDist(seg, t0, p0A, p1A, p2A, sampleAlong, ppe), s0);
    if (code > 1) appendCoverage(cov, wgt, conicAlongDist(seg, t1, p0A, p1A, p2A, sampleAlong, ppe), s1);
}

fn axisScan(segs: []const Seg, srx: f32, sry: f32, ppe: f32, horizontal: bool, method: Method) [2]f32 {
    var cov: f32 = 0;
    var wgt: f32 = 0;
    const sampleAlong = if (horizontal) srx else sry;
    for (segs) |seg| {
        if ((segMaxAlong(seg, horizontal) - sampleAlong) * ppe < -0.5) continue;
        switch (seg.kind) {
            3 => lineContrib(&cov, &wgt, seg, srx, sry, ppe, horizontal),
            1 => switch (method) {
                .deriv => conicDeriv(&cov, &wgt, seg, srx, sry, ppe, horizontal),
                .code => conicCode(&cov, &wgt, seg, srx, sry, ppe, horizontal),
            },
            else => {},
        }
    }
    return .{ cov, wgt };
}

fn evalCoverage(segs: []const Seg, rc: [2]f32, epp: [2]f32, method: Method) f32 {
    const ppe = [2]f32{ 1.0 / @max(epp[0], kCoordEps), 1.0 / @max(epp[1], kCoordEps) };
    const horiz = axisScan(segs, rc[0], rc[1], ppe[0], true, method);
    const vert = axisScan(segs, rc[0], rc[1], ppe[1], false, method);
    const wsum = horiz[1] + vert[1];
    const blended = horiz[0] * horiz[1] + vert[0] * vert[1];
    const cov = @max(@abs(blended / @max(wsum, kCoordEps)), @min(@abs(horiz[0]), @abs(vert[0])));
    return std.math.clamp(cov, 0.0, 1.0);
}

fn loadSegs(allocator: std.mem.Allocator, rect: snail.Rect, radius: f32, out: *std.ArrayList(Seg)) !void {
    var p = try demo_support.unitRoundedRectPathFor(allocator, rect, radius);
    defer p.deinit();
    const raw = try p.cloneFilledCurves(allocator);
    defer allocator.free(raw);
    for (raw) |c| {
        const kind: u8 = switch (c.kind) {
            .conic => 1,
            .line => 3,
            else => 3,
        };
        try out.append(allocator, .{
            .kind = kind,
            .p0 = .{ f16q(c.p0.x), f16q(c.p0.y) },
            .p1 = .{ f16q(c.p1.x), f16q(c.p1.y) },
            .p2 = .{ f16q(c.p2.x), f16q(c.p2.y) },
            .w = .{ f16q(c.weights[0]), f16q(c.weights[1]), f16q(c.weights[2]) },
        });
    }
}

/// Grid-sweep rc at a fixed footprint; count interior holes (near-zero pixel
/// whose four rc-neighbors are near-full) for the given method.
fn countHoles(segs: []const Seg, epp: [2]f32, method: Method, label: []const u8, verbose_holes: bool) u32 {
    var holes: u32 = 0;
    var shown: u32 = 0;
    const N: i32 = 900;
    var ix: i32 = 2;
    while (ix < N - 2) : (ix += 1) {
        const x = @as(f32, @floatFromInt(ix)) / @as(f32, @floatFromInt(N));
        if (x < 0.05 or x > 0.95) continue;
        var iy: i32 = 2;
        while (iy < N - 2) : (iy += 1) {
            const y = @as(f32, @floatFromInt(iy)) / @as(f32, @floatFromInt(N));
            if (y < 0.05 or y > 0.58) continue;
            const c = evalCoverage(segs, .{ x, y }, epp, method);
            if (c > 0.35) continue;
            const cl = evalCoverage(segs, .{ x - epp[0], y }, epp, method);
            const cr = evalCoverage(segs, .{ x + epp[0], y }, epp, method);
            const cu = evalCoverage(segs, .{ x, y - epp[1] }, epp, method);
            const cd = evalCoverage(segs, .{ x, y + epp[1] }, epp, method);
            var full: u32 = 0;
            if (cl > 0.85) full += 1;
            if (cr > 0.85) full += 1;
            if (cu > 0.85) full += 1;
            if (cd > 0.85) full += 1;
            if (full < 3) continue;
            holes += 1;
            if (verbose_holes and shown < 8) {
                std.debug.print("  [{s}] hole @rc=({d:.5},{d:.5}) cov={d:.3} nb=[{d:.2},{d:.2},{d:.2},{d:.2}]\n", .{ label, x, y, c, cl, cr, cu, cd });
                shown += 1;
            }
        }
    }
    return holes;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var segs = std.ArrayList(Seg).empty;
    defer segs.deinit(allocator);
    try loadSegs(allocator, .{ .x = 16, .y = 16, .w = 428, .h = 268 }, 22.0, &segs);

    // Exact GPU hole coordinates + footprint (from SNAIL_PATH_RC_DUMP). Full
    // axis breakdown for both conic methods.
    const holes = [_]struct { rc: [2]f32, epp: [2]f32 }{
        .{ .rc = .{ 0.007935, 0.574702140 }, .epp = .{ 0.004284, 0.004303 } },
        .{ .rc = .{ 0.007935, 0.051400400 }, .epp = .{ 0.004284, 0.004303 } }, // top junction (NEW regression)
    };
    for (holes) |h| {
        std.debug.print("\n=== exact hole rc=({d:.6},{d:.6}) epp=({d:.6},{d:.6}) ===\n", .{ h.rc[0], h.rc[1], h.epp[0], h.epp[1] });
        const ppe = [2]f32{ 1.0 / @max(h.epp[0], kCoordEps), 1.0 / @max(h.epp[1], kCoordEps) };
        // Per-curve horizontal contribution (deriv method).
        for (segs.items, 0..) |seg, i| {
            if ((segMaxAlong(seg, true) - h.rc[0]) * ppe[0] < -0.5) {
                std.debug.print("    seg[{d}] kind={d}: SKIPPED (maxAlong early-out)\n", .{ i, seg.kind });
                continue;
            }
            var c: f32 = 0;
            var w: f32 = 0;
            verbose = (seg.kind == 1);
            if (seg.kind == 3) lineContrib(&c, &w, seg, h.rc[0], h.rc[1], ppe[0], true) else conicDeriv(&c, &w, seg, h.rc[0], h.rc[1], ppe[0], true);
            verbose = false;
            std.debug.print("    seg[{d}] kind={d}: horiz cov+={d:.4} wgt={d:.4}\n", .{ i, seg.kind, c, w });
        }
        for ([_]Method{ .deriv, .code }) |m| {
            const horiz = axisScan(segs.items, h.rc[0], h.rc[1], ppe[0], true, m);
            const vert = axisScan(segs.items, h.rc[0], h.rc[1], ppe[1], false, m);
            const cov = evalCoverage(segs.items, h.rc, h.epp, m);
            std.debug.print("  {s}: horiz(cov={d:.4},wgt={d:.4}) vert(cov={d:.4},wgt={d:.4}) -> cov={d:.4}\n", .{ @tagName(m), horiz[0], horiz[1], vert[0], vert[1], cov });
        }
    }

    // Anisotropic footprints spanning the grazing regime (large epp on one axis
    // = compressed under perspective). Report holes for both conic methods.
    const footprints = [_][2]f32{
        .{ 0.02, 0.0002 },
        .{ 0.01, 0.0004 },
        .{ 0.006, 0.0006 },
        .{ 0.004, 0.001 },
        .{ 0.0002, 0.02 },
        .{ 0.0004, 0.01 },
        .{ 0.002, 0.002 },
    };
    var total_deriv: u32 = 0;
    var total_code: u32 = 0;
    for (footprints) |epp| {
        const hd = countHoles(segs.items, epp, .deriv, "deriv", total_deriv == 0);
        const hc = countHoles(segs.items, epp, .code, "code", true);
        total_deriv += hd;
        total_code += hc;
        std.debug.print("epp=({d:.4},{d:.4})  deriv holes={d}  code holes={d}\n", .{ epp[0], epp[1], hd, hc });
    }
    std.debug.print("\nTOTAL  deriv holes={d}  code holes={d}\n", .{ total_deriv, total_code });
}
