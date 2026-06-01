//! Prep-only profiling harness. Runs glyph extract, hinter hint, path
//! producers, and picture build in a tight loop for `iters` iterations
//! with no rendering, so `perf record` shows the prep hot path
//! unambiguously. Use:
//!
//!     zig build profile-prep -- 200
//!
//! with no arg defaulting to 100 iterations. For perf:
//!
//!     perf record -F 4999 -g .zig-cache/o/.../snail-profile-prep 200

const std = @import("std");
const assets = @import("assets");
const snail = @import("snail");

const PRINTABLE_ASCII = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};
const SHORT = "Hello, world!";
const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

const FACE_TO_FONT_ID = [_]u32{0};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

fn profileGlyphPrep(allocator: std.mem.Allocator, iters: usize) !f64 {
    var total: f64 = 0;
    for (0..iters) |_| {
        var font = try snail.Font.init(assets.noto_sans_regular);
        defer font.deinit();
        var cache = snail.font.GlyphCache.init(allocator);
        defer cache.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();

        var owned: std.ArrayListUnmanaged(snail.GlyphCurves) = .empty;
        defer {
            for (owned.items) |*c| c.deinit();
            owned.deinit(allocator);
        }

        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = try font.glyphIndex(ch);
            if (gid == 0) continue;
            const curves = try font.extractCurves(allocator, scratch_arena.allocator(), &cache, gid);
            _ = scratch_arena.reset(.retain_capacity);
            try owned.append(allocator, curves);
        }
        total += usFrom(start);
    }
    return total / @as(f64, @floatFromInt(iters));
}

fn profileHinterFull(allocator: std.mem.Allocator, iters: usize) !f64 {
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();
    var total: f64 = 0;
    for (0..iters) |_| {
        var h = snail.Hinter.init(allocator, &font) catch return 0;
        defer h.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const ppem = snail.HintPpem.uniform(12 * 64);

        const start = nowNs();
        for (PRINTABLE_ASCII) |ch| {
            const gid = font.glyphIndex(ch) catch continue;
            var curves = h.hint(allocator, scratch_arena.allocator(), gid, ppem) catch continue;
            _ = scratch_arena.reset(.retain_capacity);
            curves.deinit();
        }
        total += usFrom(start);
    }
    return total / @as(f64, @floatFromInt(iters));
}

fn profilePathBuild(allocator: std.mem.Allocator, iters: usize) !f64 {
    var total: f64 = 0;
    for (0..iters) |_| {
        var pool = try snail.PagePool.init(allocator, .{ .max_layers = 2, .curve_words_per_page = 1 << 16, .band_words_per_page = 1 << 14 });
        defer pool.deinit();
        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();

        var owned: std.ArrayListUnmanaged(snail.GlyphCurves) = .empty;
        defer {
            for (owned.items) |*c| c.deinit();
            owned.deinit(allocator);
        }

        const start = nowNs();
        // 50 shapes: rounded rect, ellipse, custom path, repeated.
        for (0..50) |i| {
            var p = snail.paths.Path.init(allocator);
            defer p.deinit();
            const x: f32 = @floatFromInt((i % 10) * 80);
            const y: f32 = @floatFromInt((i / 10) * 60);
            try p.addRoundedRect(.{ .x = x, .y = y, .w = 72, .h = 44 }, 10);
            const curves = try snail.paths.pathToCurves(allocator, scratch, &p);
            _ = scratch_arena.reset(.retain_capacity);
            try owned.append(allocator, curves);
        }
        total += usFrom(start);
    }
    return total / @as(f64, @floatFromInt(iters));
}

fn profilePictureBuild(allocator: std.mem.Allocator, iters: usize, fonts: *Fonts) !f64 {
    // Shape once, time only the per-iteration picture build.
    var shaped = try fonts.shaper.shape(allocator, .{}, PARAGRAPH);
    defer shaped.deinit();

    var total: f64 = 0;
    var iter: usize = 0;
    while (iter < iters * 100) : (iter += 1) {
        const start = nowNs();
        var pic = try snail.shapedRunPicture(allocator, &shaped, .{
            .baseline = .{ .x = 0, .y = 24 },
            .em = 24,
            .face_to_font_id = &FACE_TO_FONT_ID,
        });
        const us = usFrom(start);
        pic.deinit();
        total += us;
    }
    return total / @as(f64, @floatFromInt(iters * 100));
}

const Fonts = struct {
    shaper: snail.Shaper,

    fn init(allocator: std.mem.Allocator) !Fonts {
        return .{ .shaper = try snail.Shaper.init(allocator, &.{.{ .data = assets.noto_sans_regular }}) };
    }
    fn deinit(self: *Fonts) void {
        self.shaper.deinit();
    }
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const iter_env = std.c.getenv("PROFILE_PREP_ITERS");
    const iters: usize = if (iter_env) |s|
        std.fmt.parseInt(usize, std.mem.span(s), 10) catch 100
    else
        100;

    var fonts = try Fonts.init(allocator);
    defer fonts.deinit();

    std.debug.print("# Prep profile, {d} iters per row\n\n", .{iters});
    std.debug.print("| Workload | us/iter |\n", .{});
    std.debug.print("|---|---:|\n", .{});

    const glyph_us = try profileGlyphPrep(allocator, iters);
    std.debug.print("| Glyph prep, 95 ASCII | {d:.2} |\n", .{glyph_us});

    const hint_us = try profileHinterFull(allocator, iters);
    std.debug.print("| TT hint plan, 95 ASCII @ 12px | {d:.2} |\n", .{hint_us});

    const path_us = try profilePathBuild(allocator, iters);
    std.debug.print("| Path build, 50 rounded rects | {d:.2} |\n", .{path_us});

    const pic_us = try profilePictureBuild(allocator, iters, &fonts);
    std.debug.print("| Picture build, paragraph | {d:.2} |\n", .{pic_us});
}
