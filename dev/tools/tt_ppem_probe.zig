//! RESEARCH PROBE (not shipped): can TT bytecode hinting be reproduced at
//! any ppem from a single ppem-INDEPENDENT per-glyph descriptor?
//!
//! Iteration 1 (findings doc 2026-07-13) showed independent per-point output
//! regression FAILS: touched points are coupled by the hint plan. This iteration
//! "tries it" — building the structural (hint-plan-shaped) reconstruction the
//! findings recommended, and measuring held-out whether it reaches TT-grade:
//!
//!   * independent  : round(naive_i + phase_i) per point (the failing baseline).
//!   * chain        : order touched edges by funit-y; root snaps to grid; each
//!                    edge = prev_edge + round(Δfunits*ppem/upm + phase). Local
//!                    rounded gaps, accumulated — the autohinter's monotone-knot
//!                    shape, here seeded from the VM's own touched set.
//!   * chain+cvt    : same, but a link whose VM gap locks onto a `cvt` table
//!                    entry across sizes uses round(cvt) instead of the funit gap
//!                    — i.e. CVT-regularized stem widths.
//!
//! Descriptor uploaded once per glyph: funit-y per touched point + per-link phase
//! (+ optional cvt index). All ppem-independent. Fit on even ppem indices, scored
//! on the unseen odd ones. If chain/chain+cvt hits ~0 sub-px error where
//! independent left 1-2px, the ppem-independent TT path is validated in principle.
//!
//! Build/run:  zig build run-tt-probe

const std = @import("std");
const tt_internal = @import("snail_tt_probe_internal");
const tt_hint = tt_internal.hint;
const tt_vm = tt_internal.vm;
const ttf = tt_internal.ttf;
const assets = @import("assets");

const Program = tt_vm.Program;

const ppem_lo: f32 = 8.0;
const ppem_hi: f32 = 40.0;
const ppem_step: f32 = 0.25;

const Sample = struct {
    ppem: f32,
    naive_y: f32, // oy/64
    hinted_y: f32, // y/64
    touched: bool,
};

const Track = struct {
    orus_y: i32 = 0,
    idx: usize = 0,
    samples: std.ArrayListUnmanaged(Sample) = .empty,
    touched_ever: bool = false,
};

fn roundGrid(v: f32) f32 {
    return @round(v);
}

// ---- independent per-point rule (the failing baseline) --------------------

const Rule = struct { quantum: f32, phase: f32 };

fn applyRule(r: Rule, naive: f32) f32 {
    if (std.math.isInf(r.quantum)) return naive;
    return @round((naive + r.phase) / r.quantum) * r.quantum;
}

fn fitRule(samples: []const Sample, stride: usize) Rule {
    const quanta = [_]f32{ 1.0, 0.5, 2.0, std.math.inf(f32) };
    var best = Rule{ .quantum = 1.0, .phase = 0 };
    var best_cost: f32 = std.math.inf(f32);
    for (quanta) |q| {
        var p: f32 = -0.5;
        while (p < 0.5) : (p += 1.0 / 32.0) {
            var cost: f32 = 0;
            var i: usize = 0;
            while (i < samples.len) : (i += stride) {
                if (!samples[i].touched) continue;
                const e = applyRule(.{ .quantum = q, .phase = p }, samples[i].naive_y) - samples[i].hinted_y;
                cost += e * e;
            }
            if (cost < best_cost) {
                best_cost = cost;
                best = .{ .quantum = q, .phase = p };
            }
            if (std.math.isInf(q)) break;
        }
    }
    return best;
}

const Score = struct {
    rms: f32 = 0,
    max: f32 = 0,
    exact: f32 = 0, // count within 0.25px
    n: f32 = 0,

    fn add(self: *Score, err: f32) void {
        self.rms += err * err;
        if (err > self.max) self.max = err;
        if (err < 0.25) self.exact += 1;
        self.n += 1;
    }
    fn finish(self: *Score) void {
        if (self.n > 0) self.rms = @sqrt(self.rms / self.n);
    }
};

const Result = struct { indep: Score, chain: Score, chaincvt: Score, touched: usize };

fn analyzeGlyph(
    allocator: std.mem.Allocator,
    machine: *tt_hint.HintMachine,
    cache: *tt_hint.GlyphTopologyCache,
    program: *const Program,
    glyph_id: u16,
) !Result {
    const upm: f32 = @floatFromInt(program.head.units_per_em);

    var tracks = @as(std.ArrayListUnmanaged(Track), .empty);
    defer {
        for (tracks.items) |*t| t.samples.deinit(allocator);
        tracks.deinit(allocator);
    }
    // Post-prep scaled CVT (26.6 px) snapshot per successful ppem, aligned with
    // sample index. Used to test CVT-regularized stem widths.
    var cvt_snaps = @as(std.ArrayListUnmanaged([]i32), .empty);
    defer {
        for (cvt_snaps.items) |c| allocator.free(c);
        cvt_snaps.deinit(allocator);
    }

    var ppem: f32 = ppem_lo;
    var first = true;
    while (ppem <= ppem_hi + 1e-3) : (ppem += ppem_step) {
        const ppem_26_6: u32 = @intFromFloat(@round(ppem * 64.0));
        var prepared = machine.prepare(allocator, tt_hint.HintPpem.uniform(ppem_26_6), .{}) catch continue;
        defer prepared.deinit();
        const executed = machine.executeCachedGlyph(&prepared, cache, glyph_id) catch continue;
        switch (executed) {
            .simple => |hinted| {
                const pts = hinted.zone.points[0..hinted.phantom_start];
                if (first) {
                    try tracks.resize(allocator, pts.len);
                    for (tracks.items, 0..) |*t, i| t.* = .{ .idx = i };
                    first = false;
                }
                if (pts.len != tracks.items.len) continue;
                for (pts, tracks.items) |pt, *t| {
                    t.orus_y = pt.orus_y;
                    if (pt.touched_y) t.touched_ever = true;
                    try t.samples.append(allocator, .{
                        .ppem = ppem,
                        .naive_y = @as(f32, @floatFromInt(pt.oy)) / 64.0,
                        .hinted_y = @as(f32, @floatFromInt(pt.y)) / 64.0,
                        .touched = pt.touched_y,
                    });
                }
                try cvt_snaps.append(allocator, try allocator.dupe(i32, prepared.size.cvt));
            },
            .empty => {},
        }
    }

    var out = Result{ .indep = Score{}, .chain = Score{}, .chaincvt = Score{}, .touched = 0 };
    if (first) return out;
    const nsamp = tracks.items[0].samples.items.len;

    // Collect touched tracks, ordered by funit-y (ascending = bottom to top).
    var touched = @as(std.ArrayListUnmanaged(*Track), .empty);
    defer touched.deinit(allocator);
    for (tracks.items) |*t| {
        if (t.touched_ever) try touched.append(allocator, t);
    }
    std.sort.pdq(*Track, touched.items, {}, struct {
        fn lt(_: void, a: *Track, b: *Track) bool {
            return a.orus_y < b.orus_y;
        }
    }.lt);
    out.touched = touched.items.len;
    if (touched.items.len == 0) return out;

    // ---- independent per-point rule: fit even, score odd ----
    for (touched.items) |t| {
        const rule = fitRule(t.samples.items, 2);
        var i: usize = 1;
        while (i < nsamp) : (i += 2) {
            if (!t.samples.items[i].touched) continue;
            out.indep.add(@abs(applyRule(rule, t.samples.items[i].naive_y) - t.samples.items[i].hinted_y));
        }
    }

    // ---- chain: root snaps to grid, each edge = prev + round(Δfun*scale+phase).
    //      Fit per-link phase on even indices with teacher forcing (actual prev),
    //      then reconstruct odd indices by ACCUMULATING predictions. ----
    // Per link, optionally lock the gap to a cvt entry if it explains the VM gap
    // across training sizes better than the funit model (chain+cvt).
    const nlink = touched.items.len;
    const phases = try allocator.alloc(f32, nlink);
    defer allocator.free(phases);
    const cvt_idx = try allocator.alloc(i32, nlink); // -1 = use funit gap
    defer allocator.free(cvt_idx);

    // root (link 0): snap to grid, fit phase
    {
        const root = touched.items[0];
        var best_p: f32 = 0;
        var best_c: f32 = std.math.inf(f32);
        var p: f32 = -0.5;
        while (p < 0.5) : (p += 1.0 / 32.0) {
            var c: f32 = 0;
            var i: usize = 0;
            while (i < nsamp) : (i += 2) {
                if (!root.samples.items[i].touched) continue;
                const e = roundGrid(root.samples.items[i].naive_y + p) - root.samples.items[i].hinted_y;
                c += e * e;
            }
            if (c < best_c) {
                best_c = c;
                best_p = p;
            }
        }
        phases[0] = best_p;
        cvt_idx[0] = -1;
    }

    // links 1..: fit funit-gap phase (teacher forcing) + test cvt lock
    for (touched.items[1..], 1..) |t, k| {
        const prev = touched.items[k - 1];
        const dfun: f32 = @floatFromInt(t.orus_y - prev.orus_y);
        var best_p: f32 = 0;
        var best_c: f32 = std.math.inf(f32);
        var p: f32 = -0.5;
        while (p < 0.5) : (p += 1.0 / 32.0) {
            var c: f32 = 0;
            var i: usize = 0;
            while (i < nsamp) : (i += 2) {
                if (!t.samples.items[i].touched) continue;
                const scale = t.samples.items[i].ppem / upm;
                const pred = prev.samples.items[i].hinted_y + @round(dfun * scale + p);
                const e = pred - t.samples.items[i].hinted_y;
                c += e * e;
            }
            if (c < best_c) {
                best_c = c;
                best_p = p;
            }
        }
        phases[k] = best_p;

        // cvt lock: find a cvt entry whose rounded scaled value matches the VM's
        // actual gap across ALL training sizes (avg abs err < 0.1px).
        cvt_idx[k] = -1;
        const ncvt = cvt_snaps.items[0].len;
        var ci: usize = 0;
        var best_cvt_err: f32 = 0.1; // threshold
        while (ci < ncvt) : (ci += 1) {
            var err: f32 = 0;
            var cnt: f32 = 0;
            var i: usize = 0;
            while (i < nsamp) : (i += 2) {
                if (!t.samples.items[i].touched) continue;
                const gap = t.samples.items[i].hinted_y - prev.samples.items[i].hinted_y;
                const cvt_px = @as(f32, @floatFromInt(cvt_snaps.items[i][ci])) / 64.0;
                err += @abs(@round(cvt_px) - gap);
                cnt += 1;
            }
            if (cnt > 0 and err / cnt < best_cvt_err) {
                best_cvt_err = err / cnt;
                cvt_idx[k] = @intCast(ci);
            }
        }
    }

    // score odd indices, accumulating predictions
    const pred_funit = try allocator.alloc(f32, nlink);
    defer allocator.free(pred_funit);
    const pred_cvt = try allocator.alloc(f32, nlink);
    defer allocator.free(pred_cvt);
    var i: usize = 1;
    while (i < nsamp) : (i += 2) {
        const scale = touched.items[0].samples.items[i].ppem / upm;
        pred_funit[0] = roundGrid(touched.items[0].samples.items[i].naive_y + phases[0]);
        pred_cvt[0] = pred_funit[0];
        for (touched.items[1..], 1..) |t, k| {
            const prev = touched.items[k - 1];
            const dfun: f32 = @floatFromInt(t.orus_y - prev.orus_y);
            const funit_gap = @round(dfun * scale + phases[k]);
            pred_funit[k] = pred_funit[k - 1] + funit_gap;
            var cvt_gap = funit_gap;
            if (cvt_idx[k] >= 0) {
                const cvt_px = @as(f32, @floatFromInt(cvt_snaps.items[i][@intCast(cvt_idx[k])])) / 64.0;
                const g = @round(cvt_px);
                // A width-CVT is a small correction to the funit gap; if the
                // locked entry diverges (it was a position/constant, not a
                // width), fall back — else accumulation blows up.
                if (@abs(g - funit_gap) <= 2) cvt_gap = g;
            }
            pred_cvt[k] = pred_cvt[k - 1] + cvt_gap;
        }
        for (touched.items, 0..) |t, k| {
            if (!t.samples.items[i].touched) continue;
            out.chain.add(@abs(pred_funit[k] - t.samples.items[i].hinted_y));
            out.chaincvt.add(@abs(pred_cvt[k] - t.samples.items[i].hinted_y));
        }
    }

    out.indep.finish();
    out.chain.finish();
    out.chaincvt.finish();
    return out;
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const font_bytes = assets.dejavu_sans_mono;
    const program = try Program.init(font_bytes);
    const font = try ttf.Font.init(font_bytes);

    var machine = try tt_hint.HintMachine.initForProgram(allocator, &program);
    defer machine.deinit();
    var cache = tt_hint.GlyphTopologyCache.initForProgram(allocator, &program);
    defer cache.deinit();

    std.debug.print("=== TT ppem-independent reconstruction: DejaVu Sans Mono ===\n", .{});
    std.debug.print("sweep {d}..{d}px @{d} ({d} sizes); fit even sizes, score UNSEEN odd sizes.\n", .{
        ppem_lo, ppem_hi, ppem_step, @as(usize, @intFromFloat((ppem_hi - ppem_lo) / ppem_step)) + 1,
    });
    std.debug.print("exact = % of held-out touched-point samples within 0.25px of the VM.\n\n", .{});
    std.debug.print("  glyph  tched   independent(rms/max/exact)   chain(rms/max/exact)    chain+cvt(rms/max/exact)\n", .{});

    var agg_indep = Score{};
    var agg_chain = Score{};
    var agg_cvt = Score{};

    const glyphs = "Honeaiml-8203BOxstg";
    for (glyphs) |ch| {
        const gid = font.glyphIndex(ch) catch continue;
        const r = try analyzeGlyph(allocator, &machine, &cache, &program, gid);
        std.debug.print(
            "   '{c}'   {d:>3}    {d:>5.3} {d:>5.2} {d:>5.1}%      {d:>5.3} {d:>5.2} {d:>5.1}%      {d:>5.3} {d:>5.2} {d:>5.1}%\n",
            .{
                ch,              r.touched,
                r.indep.rms,     r.indep.max,
                pct(r.indep),    r.chain.rms,
                r.chain.max,     pct(r.chain),
                r.chaincvt.rms,  r.chaincvt.max,
                pct(r.chaincvt),
            },
        );
        accum(&agg_indep, r.indep);
        accum(&agg_chain, r.chain);
        accum(&agg_cvt, r.chaincvt);
    }
    agg_indep.finish();
    agg_chain.finish();
    agg_cvt.finish();
    std.debug.print("\n  ALL          {d:>5.3} {d:>5.2} {d:>5.1}%      {d:>5.3} {d:>5.2} {d:>5.1}%      {d:>5.3} {d:>5.2} {d:>5.1}%\n", .{
        agg_indep.rms, agg_indep.max, pct(agg_indep),
        agg_chain.rms, agg_chain.max, pct(agg_chain),
        agg_cvt.rms,   agg_cvt.max,   pct(agg_cvt),
    });
}

fn pct(s: Score) f32 {
    return if (s.n == 0) 100 else s.exact / s.n * 100;
}

fn accum(dst: *Score, s: Score) void {
    dst.rms += s.rms * s.rms * s.n; // s.rms already finished; re-square*n to pool
    dst.max = @max(dst.max, s.max);
    dst.exact += s.exact;
    dst.n += s.n;
}
