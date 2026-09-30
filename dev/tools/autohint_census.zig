//! Autohint census: how many fit features does each glyph carry per axis?
//!
//! The GPU autohint path fits knots once per quad in the vertex stage and
//! hands them to the fragment stage through flat varyings. The vertex fit is
//! bounded (`vertex_knots`) on per-axis feature count and on the font's
//! blue-zone count; a glyph above either bound refits in every fragment.
//! Feature counts are ppem-independent. The census also counts glyphs whose
//! analysis is empty on a non-empty outline (featureless, or dropped for
//! exceeding `max_features_per_axis` raw edges). `--chars` prints per-glyph
//! feature and fitted-knot counts at `--ppem`.
//!
//! Usage: snail-autohint-census [--ppem N] [--chars STR] [FONT[:FACE] ...]
//! With no fonts, runs over the bundled Latin assets.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");
const warp = @import("autohint_warp");

/// Per-axis bound of the draw-time fit (GPU knot slots and CPU fitter).
const vertex_knots: usize = snail.autohint.max_fit_features;

const policy = snail.autohint.AutohintPolicy{
    .x = .{ .@"align" = .grid, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } }, .positioning = .relative },
    .y = .{ .@"align" = .blue_zones, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } } },
};

const AxisStats = struct {
    hist: [65]usize = [_]usize{0} ** 65,
    over: usize = 0,
    empty_nonblank: usize = 0,
    max: usize = 0,
    sum: usize = 0,

    fn add(self: *AxisStats, knots: usize) void {
        self.hist[@min(knots, 64)] += 1;
        if (knots > vertex_knots) self.over += 1;
        self.max = @max(self.max, knots);
        self.sum += knots;
    }

    fn percentile(self: AxisStats, total: usize, p: f64) usize {
        const want: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(total)) * p));
        var seen: usize = 0;
        for (self.hist, 0..) |n, k| {
            seen += n;
            if (seen >= want) return k;
        }
        return 64;
    }
};

const Source = struct { name: []const u8, data: []const u8, face: u32 };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var ppem: f32 = 16;
    var sources: std.ArrayList(Source) = .empty;
    var chars: std.ArrayList(u21) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--ppem")) {
            i += 1;
            ppem = try std.fmt.parseFloat(f32, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--chars")) {
            i += 1;
            var it = (try std.unicode.Utf8View.init(args[i])).iterator();
            while (it.nextCodepoint()) |cp| try chars.append(arena, cp);
            continue;
        }
        var path: []const u8 = arg;
        var face: u32 = 0;
        if (std.mem.lastIndexOfScalar(u8, arg, ':')) |colon| {
            face = try std.fmt.parseInt(u32, arg[colon + 1 ..], 10);
            path = arg[0..colon];
        }
        const data = try std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .unlimited);
        try sources.append(arena, .{ .name = arg, .data = data, .face = face });
    }
    if (sources.items.len == 0) {
        try sources.append(arena, .{ .name = "NotoSans-Regular", .data = assets.noto_sans_regular, .face = 0 });
        try sources.append(arena, .{ .name = "DejaVuSansMono", .data = assets.dejavu_sans_mono, .face = 0 });
    }
    for (sources.items) |source| {
        if (chars.items.len != 0) try probeChars(source, ppem, chars.items) else try census(source);
    }
}

/// Per-character detail: feature and knot counts for specific codepoints.
fn probeChars(source: Source, ppem: f32, chars: []const u21) !void {
    const gpa = std.heap.c_allocator;
    var font = try snail.Font.initFace(source.data, source.face);
    var analyzer = try snail.autohint.AutohintAnalyzer.initFont(gpa, &font);
    defer analyzer.deinit();
    var scratch_state = std.heap.ArenaAllocator.init(gpa);
    defer scratch_state.deinit();
    var x_buf: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;
    var y_buf: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;
    var x_knots: [64]warp.Knot = undefined;
    var y_knots: [64]warp.Knot = undefined;
    std.debug.print("font={s} ppem={d}\n", .{ source.name, ppem });
    for (chars) |cp| {
        _ = scratch_state.reset(.retain_capacity);
        const gid = try font.glyphIndex(cp);
        const features = try analyzer.analyzeGlyph(scratch_state.allocator(), gid, &x_buf, &y_buf);
        const fitted = warp.fitGlyph(features, analyzer.fontFeatures(), policy, .{ .x = ppem, .y = ppem }, &x_knots, &y_knots);
        std.debug.print("  U+{X:0>4} gid={d} features x={d} y={d} knots x={d} y={d}\n", .{
            cp, gid, features.x.len, features.y.len, fitted.x.len, fitted.y.len,
        });
    }
}

fn census(source: Source) !void {
    const gpa = std.heap.c_allocator;
    var font = try snail.Font.initFace(source.data, source.face);
    var analyzer = try snail.autohint.AutohintAnalyzer.initFont(gpa, &font);
    defer analyzer.deinit();
    const font_features = analyzer.fontFeatures();

    var scratch_state = std.heap.ArenaAllocator.init(gpa);
    defer scratch_state.deinit();
    var x_buf: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;
    var y_buf: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;

    var x_stats: AxisStats = .{};
    var y_stats: AxisStats = .{};
    var either_over: usize = 0;
    var glyphs: usize = 0;
    var failed: usize = 0;
    const count = font.inner.num_glyphs;
    for (0..count) |gid_usize| {
        const gid: u16 = @intCast(gid_usize);
        _ = scratch_state.reset(.retain_capacity);
        const scratch = scratch_state.allocator();
        const curves = font.extractCurves(scratch, scratch, gid) catch {
            failed += 1;
            continue;
        };
        if (curves.isEmpty()) continue;
        const features = analyzer.analyzeGlyph(scratch, gid, &x_buf, &y_buf) catch {
            failed += 1;
            continue;
        };
        glyphs += 1;
        x_stats.add(features.x.len);
        y_stats.add(features.y.len);
        if (features.x.len == 0) x_stats.empty_nonblank += 1;
        if (features.y.len == 0) y_stats.empty_nonblank += 1;
        if (features.x.len > vertex_knots or features.y.len > vertex_knots) either_over += 1;
    }

    std.debug.print("font={s} glyphs={d} failed={d} blue_zones={d} vertex_bound={d} features_over_either={d} ({d:.2}%)\n", .{
        source.name, glyphs, failed, font_features.blues.len, vertex_knots, either_over, pct(either_over, glyphs),
    });
    inline for (.{ .{ "x", &x_stats }, .{ "y", &y_stats } }) |entry| {
        const s = entry[1];
        std.debug.print("  axis={s} mean={d:.2} p50={d} p90={d} p99={d} max={d} over={d} ({d:.2}%) empty_nonblank={d} ({d:.2}%)\n", .{
            entry[0],
            @as(f64, @floatFromInt(s.sum)) / @as(f64, @floatFromInt(@max(glyphs, 1))),
            s.percentile(glyphs, 0.50),
            s.percentile(glyphs, 0.90),
            s.percentile(glyphs, 0.99),
            s.max,
            s.over,
            pct(s.over, glyphs),
            s.empty_nonblank,
            pct(s.empty_nonblank, glyphs),
        });
    }
}

fn pct(n: usize, d: usize) f64 {
    return 100.0 * @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(@max(d, 1)));
}
