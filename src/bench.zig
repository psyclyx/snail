const std = @import("std");
const assets = @import("assets");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");
const curve_tex = @import("render/curve_texture.zig");
const band_tex = @import("render/band_texture.zig");
const bezier = @import("math/bezier.zig");
const CurveSegment = bezier.CurveSegment;
const roots = @import("math/roots.zig");
const vec_mod = @import("math/vec.zig");

const BENCH_TIME_MULTIPLIER = 10;
const PREP_RUNS = BENCH_TIME_MULTIPLIER;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn elapsed(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0; // microseconds
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    std.debug.print("\n=== Snail Microbenchmarks ===\n\n", .{});

    const font_data = assets.noto_sans_regular;

    // Font init
    std.debug.print("Prep (avg over {} runs):\n", .{PREP_RUNS});
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const t = nowNs();
        _ = try ttf.Font.init(font_data);
        font_load_total_us += elapsed(t);
    }
    const font = try ttf.Font.init(font_data);
    std.debug.print("  Font.init: {d:.1} us\n", .{font_load_total_us / PREP_RUNS});

    // Parse glyphs
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var parse_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var run_cache = ttf.GlyphCache.init(allocator);
        const t = nowNs();
        for (chars) |ch| {
            const gid = try font.glyphIndex(ch);
            _ = try font.parseGlyph(allocator, &run_cache, gid);
        }
        parse_total_us += elapsed(t);
        run_cache.deinit();
    }
    const parse_avg_us = parse_total_us / PREP_RUNS;
    std.debug.print("  Parse {} glyphs: {d:.1} us avg, {d:.2} us/glyph\n", .{
        chars.len, parse_avg_us, parse_avg_us / @as(f64, @floatFromInt(chars.len)),
    });

    var cache = ttf.GlyphCache.init(allocator);
    defer cache.deinit();

    // Build curve texture
    std.debug.print("\nData Preparation:\n", .{});
    var glyph_curves: std.ArrayList(curve_tex.GlyphCurves) = .empty;
    defer {
        for (glyph_curves.items) |gc| allocator.free(gc.curves);
        glyph_curves.deinit(allocator);
    }

    for (chars) |ch| {
        const gid = try font.glyphIndex(ch);
        const glyph = try font.parseGlyph(allocator, &cache, gid);
        var all: std.ArrayList(CurveSegment) = .empty;
        defer all.deinit(allocator);
        for (glyph.contours) |contour| {
            for (contour.curves) |curve| try all.append(allocator, .{ .kind = .quadratic, .p0 = curve.p0, .p1 = curve.p1, .p2 = curve.p2 });
        }
        const owned = try allocator.dupe(CurveSegment, all.items);
        try glyph_curves.append(allocator, .{
            .curves = owned,
            .bbox = glyph.metrics.bbox,
            .logical_curve_count = owned.len,
            .prefer_direct_encoding = true,
        });
    }

    var curve_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const t = nowNs();
        var tmp_ct = try curve_tex.buildCurveTexture(allocator, glyph_curves.items);
        curve_total_us += elapsed(t);
        tmp_ct.texture.deinit();
        allocator.free(tmp_ct.entries);
    }
    std.debug.print("  Curve texture: {d:.1} us\n", .{curve_total_us / PREP_RUNS});

    var base_ct = try curve_tex.buildCurveTexture(allocator, glyph_curves.items);
    defer base_ct.texture.deinit();
    defer allocator.free(base_ct.entries);

    var band_total_us: f64 = 0;
    var band_glyph_count: usize = 0;
    for (0..PREP_RUNS) |_| {
        var bds: std.ArrayList(band_tex.GlyphBandData) = .empty;
        defer {
            for (bds.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
            bds.deinit(allocator);
        }

        const t = nowNs();
        for (glyph_curves.items, 0..) |gc, i| {
            var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.logical_curve_count, gc.bbox, base_ct.entries[i], gc.origin, gc.prefer_direct_encoding);
            try bds.append(allocator, bd);
            _ = &bd;
        }
        var bt = try band_tex.buildBandTexture(allocator, bds.items);
        band_total_us += elapsed(t);
        band_glyph_count = bds.items.len;
        bt.texture.deinit();
        allocator.free(bt.entries);
    }
    std.debug.print("  Band texture ({} glyphs): {d:.1} us\n", .{ band_glyph_count, band_total_us / PREP_RUNS });

    // Math benchmarks
    std.debug.print("\nMath:\n", .{});
    {
        const q = bezier.QuadBezier{
            .p0 = vec_mod.Vec2.new(0, 0),
            .p1 = vec_mod.Vec2.new(0.5, 1),
            .p2 = vec_mod.Vec2.new(1, 0),
        };
        const iters: u32 = 100_000 * BENCH_TIME_MULTIPLIER;
        const t = nowNs();
        var dummy: f32 = 0;
        for (0..iters) |i| {
            dummy += q.evaluate(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(iters))).x;
        }
        std.mem.doNotOptimizeAway(&dummy);
        std.debug.print("  Bezier eval: {d:.1} ns/iter\n", .{elapsed(t) * 1000.0 / @as(f64, @floatFromInt(iters))});
    }
    {
        const iters: u32 = 1_000_000 * BENCH_TIME_MULTIPLIER;
        const t = nowNs();
        var dummy: f32 = 0;
        for (0..iters) |i| {
            const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(iters));
            const r = roots.solveQuadratic(1.0, -f * 2.0, 0.5);
            dummy += r.t[0];
        }
        std.mem.doNotOptimizeAway(&dummy);
        std.debug.print("  Quadratic solve: {d:.1} ns/iter\n", .{elapsed(t) * 1000.0 / @as(f64, @floatFromInt(iters))});
    }

    std.debug.print("\nVector:\n", .{});
    {
        var builder = snail.PathPictureBuilder.init(allocator);
        defer builder.deinit();
        try builder.addRoundedRect(
            .{ .x = 0, .y = 0, .w = 80, .h = 28 },
            .{ .color = .{ 0.2, 0.5, 0.9, 1 } },
            .{
                .color = .{ 0.95, 0.98, 1, 1 },
                .width = 1.5,
                .join = .round,
                .placement = .inside,
            },
            9,
            .identity,
        );
        var picture = try builder.freeze(allocator);
        defer picture.deinit();
        const view = snail.AtlasView{ .atlas = &picture.atlas, .layer_base = 0 };

        const iters: u32 = 100_000 * BENCH_TIME_MULTIPLIER;
        var buf: [snail.FLOATS_PER_GLYPH]f32 = undefined;
        const t = nowNs();
        for (0..iters) |i| {
            var batch = snail.PathBatch.init(&buf);
            _ = i;
            _ = batch.addPicture(&view, &picture);
            std.mem.doNotOptimizeAway(batch.slice());
        }
        std.debug.print("  Path instancing (1 shape): {d:.1} ns/shape\n", .{
            elapsed(t) * 1000.0 / @as(f64, @floatFromInt(iters)),
        });
    }
    {
        const shape_count: usize = 64;
        const iters: u32 = 1_000 * BENCH_TIME_MULTIPLIER;
        const t = nowNs();
        for (0..iters) |i| {
            var builder = snail.PathPictureBuilder.init(allocator);
            defer builder.deinit();
            for (0..shape_count) |shape| {
                const xf: f32 = @floatFromInt((shape + i) % 16);
                const yf: f32 = @floatFromInt(shape / 16);
                try builder.addEllipse(
                    .{ .x = xf * 22, .y = yf * 22, .w = 18, .h = 18 },
                    .{ .color = .{ 0.95, 0.55, 0.2, 0.9 } },
                    .{ .color = .{ 0.15, 0.15, 0.2, 1 }, .width = 1, .placement = .inside },
                    .identity,
                );
            }
            var picture = try builder.freeze(allocator);
            picture.deinit();
        }
        std.debug.print("  Path freeze ({} shapes): {d:.1} us/picture, {d:.2} us/shape\n", .{
            shape_count,
            elapsed(t) / @as(f64, @floatFromInt(iters)),
            elapsed(t) / (@as(f64, @floatFromInt(iters)) * @as(f64, @floatFromInt(shape_count))),
        });
    }

    // Band quality analysis
    std.debug.print("\nBand Analysis:\n", .{});
    for ("AaBbOogq") |ch| {
        const gid = try font.glyphIndex(ch);
        const glyph = try font.parseGlyph(allocator, &cache, gid);
        var all: std.ArrayList(CurveSegment) = .empty;
        defer all.deinit(allocator);
        for (glyph.contours) |contour| {
            for (contour.curves) |curve| try all.append(allocator, .{ .kind = .quadratic, .p0 = curve.p0, .p1 = curve.p1, .p2 = curve.p2 });
        }

        const gc = [_]curve_tex.GlyphCurves{.{ .curves = all.items, .bbox = glyph.metrics.bbox, .logical_curve_count = all.items.len, .prefer_direct_encoding = true }};
        var ct2 = try curve_tex.buildCurveTexture(allocator, &gc);
        defer ct2.texture.deinit();
        defer allocator.free(ct2.entries);

        var bd = try band_tex.buildGlyphBandData(allocator, all.items, all.items.len, glyph.metrics.bbox, ct2.entries[0], .zero, true);
        defer band_tex.freeGlyphBandData(allocator, &bd);

        // Count max curves per band from the band data
        var max_curves_h: u16 = 0;
        var max_curves_v: u16 = 0;
        for (0..bd.h_band_count) |bi| {
            const count = bd.data[bi * 2];
            max_curves_h = @max(max_curves_h, count);
        }
        for (0..bd.v_band_count) |bi| {
            const off = (@as(usize, bd.h_band_count) + bi) * 2;
            const count = bd.data[off];
            max_curves_v = @max(max_curves_v, count);
        }

        std.debug.print("  '{c}': {d:>3} curves, {d}h x {d}v bands, max curves/band: h={d} v={d}, texels={d}\n", .{
            ch, all.items.len, bd.h_band_count, bd.v_band_count, max_curves_h, max_curves_v, bd.texel_count,
        });
    }

    // Font has no deinit (it doesn't own the data)
    std.debug.print("\n========================\n", .{});
}
