const std = @import("std");
const assets = @import("assets");
const ttf = @import("font/ttf.zig");
const curve_tex = @import("render/curve_texture.zig");
const band_tex = @import("render/band_texture.zig");
const bezier = @import("math/bezier.zig");
const roots = @import("math/roots.zig");
const vec_mod = @import("math/vec.zig");

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

    std.debug.print("\n=== Snail Benchmarks ===\n\n", .{});

    const font_data = assets.noto_sans_regular;

    // Font init
    std.debug.print("Font Parsing:\n", .{});
    var t = nowNs();
    const font = try ttf.Font.init(font_data);
    std.debug.print("  Font.init: {d:.1} us\n", .{elapsed(t)});

    var cache = ttf.GlyphCache.init(allocator);
    defer cache.deinit();

    // Parse glyphs
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    t = nowNs();
    for (chars) |ch| {
        const gid = try font.glyphIndex(ch);
        _ = try font.parseGlyph(allocator, &cache, gid);
    }
    std.debug.print("  Parse {} glyphs: {d:.1} us total, {d:.2} us/glyph\n", .{
        chars.len, elapsed(t), elapsed(t) / @as(f64, @floatFromInt(chars.len)),
    });

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
        var all: std.ArrayList(bezier.QuadBezier) = .empty;
        defer all.deinit(allocator);
        for (glyph.contours) |contour| try all.appendSlice(allocator, contour.curves);
        const owned = try allocator.dupe(bezier.QuadBezier, all.items);
        try glyph_curves.append(allocator, .{ .curves = owned, .bbox = glyph.metrics.bbox });
    }

    t = nowNs();
    var ct = try curve_tex.buildCurveTexture(allocator, glyph_curves.items);
    defer ct.texture.deinit();
    defer allocator.free(ct.entries);
    std.debug.print("  Curve texture: {d:.1} us\n", .{elapsed(t)});

    t = nowNs();
    var bds: std.ArrayList(band_tex.GlyphBandData) = .empty;
    defer {
        for (bds.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
        bds.deinit(allocator);
    }
    for (glyph_curves.items, 0..) |gc, i| {
        var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.bbox, ct.entries[i]);
        try bds.append(allocator, bd);
        _ = &bd;
    }
    var bt = try band_tex.buildBandTexture(allocator, bds.items);
    defer bt.texture.deinit();
    defer allocator.free(bt.entries);
    std.debug.print("  Band texture ({} glyphs): {d:.1} us\n", .{ bds.items.len, elapsed(t) });

    // Math benchmarks
    std.debug.print("\nMath:\n", .{});
    {
        const q = bezier.QuadBezier{
            .p0 = vec_mod.Vec2.new(0, 0),
            .p1 = vec_mod.Vec2.new(0.5, 1),
            .p2 = vec_mod.Vec2.new(1, 0),
        };
        const iters: u32 = 100_000;
        t = nowNs();
        var dummy: f32 = 0;
        for (0..iters) |i| {
            dummy += q.evaluate(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(iters))).x;
        }
        std.mem.doNotOptimizeAway(&dummy);
        std.debug.print("  Bezier eval: {d:.1} ns/iter\n", .{elapsed(t) * 1000.0 / @as(f64, @floatFromInt(iters))});
    }
    {
        const iters: u32 = 1_000_000;
        t = nowNs();
        var dummy: f32 = 0;
        for (0..iters) |i| {
            const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(iters));
            const r = roots.solveQuadratic(1.0, -f * 2.0, 0.5);
            dummy += r.t[0];
        }
        std.mem.doNotOptimizeAway(&dummy);
        std.debug.print("  Quadratic solve: {d:.1} ns/iter\n", .{elapsed(t) * 1000.0 / @as(f64, @floatFromInt(iters))});
    }

    // Band quality analysis
    std.debug.print("\nBand Analysis:\n", .{});
    for ("AaBbOogq") |ch| {
        const gid = try font.glyphIndex(ch);
        const glyph = try font.parseGlyph(allocator, &cache, gid);
        var all: std.ArrayList(bezier.QuadBezier) = .empty;
        defer all.deinit(allocator);
        for (glyph.contours) |contour| try all.appendSlice(allocator, contour.curves);

        const gc = [_]curve_tex.GlyphCurves{.{ .curves = all.items, .bbox = glyph.metrics.bbox }};
        var ct2 = try curve_tex.buildCurveTexture(allocator, &gc);
        defer ct2.texture.deinit();
        defer allocator.free(ct2.entries);

        var bd = try band_tex.buildGlyphBandData(allocator, all.items, glyph.metrics.bbox, ct2.entries[0]);
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
