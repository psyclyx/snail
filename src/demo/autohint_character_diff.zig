//! Per-character composable-autohint comparison harness.
//!
//! Each corpus character is rendered alone at 9..14 PPEM through four
//! harness-local policies and the TrueType path. Writes one contact sheet per
//! font/size plus a stable TSV under zig-out/autohint-character-diff/.

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const support = @import("support");
const compare_mod = @import("autohint_compare.zig");
const harness = @import("screenshot_harness.zig");
const assets = @import("assets");

pub const corpus = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^*()[]{}+=";
pub const ppems = [_]u32{ 9, 10, 11, 12, 13, 14 };
const policy_count = 4;
const cell_w: u32 = 28;
const cell_h: u32 = 28;
const label_w: u32 = 28;
const columns: u32 = 1 + policy_count * 2; // TT, candidates, diffs.
const sheet_w: u32 = label_w + columns * cell_w;
const sheet_h: u32 = corpus.len * cell_h;
const left: f32 = 4;
const baseline: f32 = 20;
const bg_green: u8 = 246;
const ink_color = [4]f32{ 0, 0, 0, 1 };
const visible_margin: u8 = 40;

const PolicyCase = struct {
    name: []const u8,
    policy: snail.autohint.AutohintPolicy,
};

const y_axis: snail.autohint.policy.YPolicy = .{
    .@"align" = .blue_zones,
    .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = 1.6 } },
    .overshoot = .{ .suppress_below_px = 0.5 },
};

pub const policies = [_]PolicyCase{
    .{ .name = "y", .policy = .{ .y = y_axis } },
    .{ .name = "x-natural", .policy = .{
        .x = .{ .@"align" = .grid, .stem_width = .natural },
        .y = y_axis,
    } },
    .{ .name = "x-full", .policy = .{
        .x = .{ .@"align" = .grid, .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } } },
        .y = y_axis,
    } },
    .{ .name = "xy-relative", .policy = .{
        .x = .{
            .@"align" = .grid,
            .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
            .positioning = .relative,
            .registration = .left_round_outline,
        },
        .y = y_axis,
    } },
};

const Metrics = struct {
    abs_diff: u64,
    visible_pixels: u64,
    normalized: f64,
    candidate_only: u64,
    reference_only: u64,
    best_dx: i32,
    best_dy: i32,
    best_residual: u64,
};

fn extractInk(rgba: []const u8, ink: []u8) void {
    var p: usize = 0;
    var i: usize = 0;
    while (p + 3 < rgba.len) : (p += 4) {
        const g = rgba[p + 1];
        ink[i] = if (g < bg_green) bg_green - g else 0;
        i += 1;
    }
}

fn shiftedResidual(candidate: []const u8, reference: []const u8, dx: i32, dy: i32) u64 {
    var sum: u64 = 0;
    for (0..cell_h) |y| for (0..cell_w) |x| {
        const sx = @as(i32, @intCast(x)) - dx;
        const sy = @as(i32, @intCast(y)) - dy;
        const a: u8 = if (sx >= 0 and sy >= 0 and sx < cell_w and sy < cell_h)
            candidate[@as(usize, @intCast(sy)) * cell_w + @as(usize, @intCast(sx))]
        else
            0;
        const t = reference[y * cell_w + x];
        sum += if (a > t) a - t else t - a;
    };
    return sum;
}

fn metrics(candidate: []const u8, reference: []const u8) Metrics {
    var result: Metrics = .{
        .abs_diff = 0,
        .visible_pixels = 0,
        .normalized = 0,
        .candidate_only = 0,
        .reference_only = 0,
        .best_dx = 0,
        .best_dy = 0,
        .best_residual = 0,
    };
    var ref_ink: u64 = 0;
    for (candidate, reference) |a, t| {
        const d = if (a > t) a - t else t - a;
        result.abs_diff += d;
        if (d > visible_margin) result.visible_pixels += 1;
        if (a > t) result.candidate_only += a - t else result.reference_only += t - a;
        ref_ink += t;
    }
    result.normalized = if (ref_ink == 0) 0 else @as(f64, @floatFromInt(result.abs_diff)) / @as(f64, @floatFromInt(ref_ink));
    result.best_residual = result.abs_diff;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            const residual = shiftedResidual(candidate, reference, dx, dy);
            if (residual < result.best_residual) {
                result.best_residual = residual;
                result.best_dx = dx;
                result.best_dy = dy;
            }
        }
    }
    return result;
}

fn renderCharacter(
    allocator: std.mem.Allocator,
    frame: std.mem.Allocator,
    pool: *snail.PagePool,
    atlas: *const snail.Atlas,
    empty_atlas: *const snail.Atlas,
    empty_pic: *const helpers.Picture,
    shaped: *const snail.ShapedText,
    em: f32,
    mode: @FieldType(helpers.RunPlacement, "mode"),
) ![]u8 {
    var pic = try helpers.placeRun(frame, shaped, null, .{
        .baseline = .{ .x = left, .y = baseline },
        .em = em,
        .color = ink_color,
        .mode = mode,
        .snap = .origins,
        .world_to_pixel = .{},
    });
    if (mode == .autohint) {
        const shapes = @constCast(pic.shapes);
        for (shaped.glyphs, shapes) |glyph, *shape| {
            const base_key = snail.recordKey.unhintedGlyph(glyph.font_id, glyph.glyph_id);
            const base = atlas.lookupRecord(base_key) orelse return error.MissingRecord;
            if (base.curve_count == 0) {
                shape.key = base_key;
                shape.autohint_policy = null;
            }
        }
    }
    const scene: harness.Scene = .{
        .pool = pool,
        .paths_atlas = empty_atlas,
        .text_atlas = atlas,
        .paths_picture = empty_pic,
        .text_picture = &pic,
    };
    return harness.renderCpuToPixels(allocator, scene, cell_w, cell_h, .{ .coverage_exponent = 0.55 });
}

fn paintCell(sheet: []u8, col: u32, row: usize, ink: []const u8) void {
    for (0..cell_h) |y| for (0..cell_w) |x| {
        const src = y * cell_w + x;
        const dst_x = label_w + col * cell_w + x;
        const dst_y = @as(u32, @intCast(row)) * cell_h + y;
        const dst = (@as(usize, dst_y) * sheet_w + dst_x) * 4;
        const shade = 255 - ink[src];
        sheet[dst + 0] = shade;
        sheet[dst + 1] = shade;
        sheet[dst + 2] = shade;
        sheet[dst + 3] = 255;
    };
}

fn paintDiff(sheet: []u8, col: u32, row: usize, candidate: []const u8, reference: []const u8) void {
    for (0..cell_h) |y| for (0..cell_w) |x| {
        const src = y * cell_w + x;
        const a = candidate[src];
        const t = reference[src];
        const dst_x = label_w + col * cell_w + x;
        const dst_y = @as(u32, @intCast(row)) * cell_h + y;
        const dst = (@as(usize, dst_y) * sheet_w + dst_x) * 4;
        sheet[dst + 0] = 255 - t;
        sheet[dst + 1] = 255 - a;
        sheet[dst + 2] = 255 - @max(a, t);
        sheet[dst + 3] = 255;
    };
}

fn sheetPath(buf: []u8, slug: []const u8, ppem: u32) ![:0]u8 {
    return std.fmt.bufPrintZ(buf, "zig-out/autohint-character-diff/{s}-{d}ppem.tga", .{ slug, ppem });
}

fn paintLabel(sheet: []u8, row: usize, reference: []const u8) void {
    // The isolated TT glyph is also the readable row label; draw it smaller in
    // the reserved label column by copying the left 20 pixels of its cell.
    for (0..cell_h) |y| for (0..@min(label_w, cell_w)) |x| {
        const ink = reference[y * cell_w + x];
        const dst = ((row * cell_h + y) * sheet_w + x) * 4;
        const shade = 255 - ink;
        sheet[dst + 0] = shade;
        sheet[dst + 1] = shade;
        sheet[dst + 2] = shade;
        sheet[dst + 3] = 255;
    };
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();
    _ = std.c.mkdir("zig-out", 0o755);
    _ = std.c.mkdir("zig-out/autohint-character-diff", 0o755);

    var tsv = std.ArrayList(u8).empty;
    defer tsv.deinit(allocator);
    try tsv.appendSlice(allocator, "font\tppem\tcharacter\tcodepoint\tpolicy\tabs_diff\tvisible_pixels\tnormalized\tcandidate_only\treference_only\tbest_dx\tbest_dy\tbest_residual\n");

    const fonts = [_]struct { bytes: []const u8, label: []const u8, slug: []const u8, tt_fallback: bool }{
        .{ .bytes = assets.dejavu_sans_mono, .label = "DejaVu Sans Mono", .slug = "dejavu", .tt_fallback = false },
        .{ .bytes = assets.noto_sans_mono, .label = "Noto Sans Mono", .slug = "noto", .tt_fallback = true },
    };
    for (fonts) |font_desc| try runFont(allocator, pool, font_desc, &tsv);

    const out = std.c.fopen("zig-out/autohint-character-diff/metrics.tsv", "wb") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(out);
    if (std.c.fwrite(tsv.items.ptr, 1, tsv.items.len, out) != tsv.items.len) return error.FileWriteFailed;
}

fn runFont(allocator: std.mem.Allocator, pool: *snail.PagePool, font_desc: anytype, tsv: *std.ArrayList(u8)) !void {
    var compare = try compare_mod.Compare.initFont(allocator, pool, font_desc.bytes, font_desc.label);
    defer compare.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var frame = std.heap.ArenaAllocator.init(allocator);
    defer frame.deinit();

    const all = try compare.shape_cache.shape(&compare.faces, corpus, .{});
    const tags = try compare.shape_cache.shape(&compare.faces, "characterdiff", .{});
    try compare.ensureAll(scratch.allocator(), all, tags, 1.0);
    var empty_atlas = snail.Atlas.empty(allocator);
    defer empty_atlas.deinit();
    var empty_pic = try helpers.Picture.from(allocator, &.{});
    defer empty_pic.deinit();

    const pixels = @as(usize, cell_w) * cell_h;
    const ref_ink = try allocator.alloc(u8, pixels);
    defer allocator.free(ref_ink);
    const candidate_ink = try allocator.alloc(u8, pixels);
    defer allocator.free(candidate_ink);

    for (ppems) |ppem| {
        const sheet = try allocator.alloc(u8, @as(usize, sheet_w) * sheet_h * 4);
        defer allocator.free(sheet);
        @memset(sheet, 255);
        var totals = [_]u64{0} ** policy_count;
        var worst = [_]struct { score: u64 = 0, ch: u8 = 0 }{.{}} ** policy_count;

        for (corpus, 0..) |ch, row| {
            _ = frame.reset(.retain_capacity);
            const text = [_]u8{ch};
            const shaped = try compare.shape_cache.shape(&compare.faces, &text, .{});
            const ppem_26_6 = ppem * 64;
            const reference_rgba = try renderCharacter(allocator, frame.allocator(), pool, &compare.atlas, &empty_atlas, &empty_pic, shaped, @floatFromInt(ppem), .{ .truetype = .{ .ppem_26_6 = ppem_26_6 } });
            defer allocator.free(reference_rgba);
            extractInk(reference_rgba, ref_ink);
            paintLabel(sheet, row, ref_ink);
            paintCell(sheet, 0, row, ref_ink);

            for (policies, 0..) |case, p| {
                const rgba = try renderCharacter(allocator, frame.allocator(), pool, &compare.atlas, &empty_atlas, &empty_pic, shaped, @floatFromInt(ppem), .{ .autohint = case.policy });
                defer allocator.free(rgba);
                extractInk(rgba, candidate_ink);
                const m = metrics(candidate_ink, ref_ink);
                totals[p] += m.abs_diff;
                if (m.abs_diff > worst[p].score) worst[p] = .{ .score = m.abs_diff, .ch = ch };
                paintCell(sheet, @intCast(1 + p), row, candidate_ink);
                paintDiff(sheet, @intCast(1 + policy_count + p), row, candidate_ink, ref_ink);
                const line = try std.fmt.allocPrint(allocator, "{s}\t{d}\t{c}\t{d}\t{s}\t{d}\t{d}\t{d:.6}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{
                    font_desc.slug,   ppem,             ch,        ch,        case.name,       m.abs_diff, m.visible_pixels, m.normalized,
                    m.candidate_only, m.reference_only, m.best_dx, m.best_dy, m.best_residual,
                });
                defer allocator.free(line);
                try tsv.appendSlice(allocator, line);
            }
        }
        var path_buf: [160]u8 = undefined;
        const path = try sheetPath(&path_buf, font_desc.slug, ppem);
        try support.screenshot.writeTga(path, sheet, sheet_w, sheet_h);
        std.debug.print("{s} {d}ppem{s}:", .{ font_desc.label, ppem, if (font_desc.tt_fallback) " (TT fallback reference)" else "" });
        for (policies, 0..) |case, p| std.debug.print(" {s}={d} worst={c}:{d}", .{ case.name, totals[p], worst[p].ch, worst[p].score });
        std.debug.print("\n", .{});
    }
}

test "character diff corpus and policy order are stable" {
    try std.testing.expectEqualStrings("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^*()[]{}+=", corpus);
    try std.testing.expectEqual(@as(usize, 77), corpus.len);
    try std.testing.expectEqualStrings("y", policies[0].name);
    try std.testing.expectEqualStrings("x-natural", policies[1].name);
    try std.testing.expectEqualStrings("x-full", policies[2].name);
    try std.testing.expectEqualStrings("xy-relative", policies[3].name);
    try std.testing.expectEqualSlices(u32, &.{ 9, 10, 11, 12, 13, 14 }, &ppems);
}

test "metric math is per-cell and zero safe" {
    var a = [_]u8{0} ** (cell_w * cell_h);
    var t = [_]u8{0} ** (cell_w * cell_h);
    a[0..4].* = .{ 0, 20, 100, 0 };
    t[0..4].* = .{ 0, 50, 40, 0 };
    const m = metrics(&a, &t);
    try std.testing.expectEqual(@as(u64, 90), m.abs_diff);
    try std.testing.expectEqual(@as(u64, 1), m.visible_pixels);
    try std.testing.expectEqual(@as(u64, 60), m.candidate_only);
    try std.testing.expectEqual(@as(u64, 30), m.reference_only);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), m.normalized, 0.000001);
    const zero = [_]u8{0} ** (cell_w * cell_h);
    const empty = metrics(&zero, &zero);
    try std.testing.expectEqual(@as(f64, 0), empty.normalized);
}

test "contact sheet geometry and names include isolated m row" {
    try std.testing.expectEqual(@as(u32, 280), sheet_w);
    try std.testing.expectEqual(@as(u32, corpus.len * cell_h), sheet_h);
    const m_index = std.mem.indexOfScalar(u8, corpus, 'm').?;
    try std.testing.expectEqual(@as(usize, 12), m_index);
    try std.testing.expectEqual(@as(usize, 12 * cell_h), m_index * cell_h);
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("zig-out/autohint-character-diff/dejavu-12ppem.tga", try sheetPath(&buf, "dejavu", 12));
    for (policies) |case| try case.policy.validate();
}
