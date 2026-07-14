//! Objective autohint default-policy-vs-TrueType agreement metric for the hinting work.
//!
//! For every ppem in the demo grid, this renders the sample string TWICE
//! through the CPU backend at the same baseline/origin — once with the
//! explicit demo-local xy policy, once with the font's own
//! TrueType hinting (the gold standard we're chasing). It then:
//!
//!   * prints a per-size disagreement score (summed |ink_xy - ink_tt| and a
//!     count of pixels that differ by more than a visible margin), plus a
//!     grand total — the single number to drive down while iterating; and
//!   * writes zig-out/autohint-diff.tga, a red/green overlay where red is
//!     xy-policy-only ink, green is TrueType-only ink, and gray is where
//!     both agree — so the *location* of every disagreement is visible.
//!
//! Run with `zig build run-autohint-diff`. CPU-only (no GL/Wayland).

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const support = @import("support");
const compare_mod = @import("autohint_compare.zig");
const harness = @import("screenshot_harness.zig");

// One cell per size: wide enough for the whole sample at the largest em,
// tall enough for caps + descenders. Baseline is a fixed fraction down so
// both modes land on the same device row.
const W: u32 = 460;
const H: u32 = 40;
const left: f32 = 6;
const baseline: f32 = 28;

// Pure black ink on the harness off-white background — max contrast so the
// coverage ramp (and any disagreement in it) is as legible as possible.
const ink_color = [4]f32{ 0, 0, 0, 1 };
// Green channel of the shared background (screenshot_harness.bg_srgb_u8).
const bg_green: u8 = 246;

/// Per-pixel ink = how far the green channel dropped below the background,
/// i.e. coverage×contrast. Orientation-agnostic (we only ever diff or paint
/// per-pixel), so the buffer's flip state doesn't matter.
fn extractInk(rgba: []const u8, ink: []u8) void {
    var p: usize = 0;
    var i: usize = 0;
    while (p + 3 < rgba.len) : (p += 4) {
        const g = rgba[p + 1];
        ink[i] = if (g < bg_green) bg_green - g else 0;
        i += 1;
    }
}

fn renderMode(
    allocator: std.mem.Allocator,
    frame: std.mem.Allocator,
    pool: *snail.PagePool,
    atlas: *const snail.Atlas,
    empty_atlas: *const snail.Atlas,
    empty_pic: *const helpers.Picture,
    shaped: *const snail.ShapedText,
    em: f32,
    x_off: f32,
    y_off: f32,
    mode: @FieldType(helpers.RunPlacement, "mode"),
    snap: helpers.RunSnap,
) ![]u8 {
    var pic = try helpers.placeRun(frame, shaped, null, .{
        .baseline = .{ .x = left + x_off, .y = baseline + y_off },
        .em = em,
        .color = ink_color,
        .mode = mode,
        .snap = snap,
    });
    // Empty outlines intentionally have no autohint record; preserve their
    // no-op shape on the resident unhinted key, as the comparison grid does.
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
    const scene = harness.Scene{
        .pool = pool,
        .paths_atlas = empty_atlas,
        .text_atlas = atlas,
        .paths_picture = empty_pic,
        .text_picture = &pic,
    };
    // Match the demo's hinting-comparison view exactly (main.zig:1056) so the
    // tool draws xy/tt the same way the user sees them.
    return harness.renderCpuToPixels(allocator, scene, W, H, .{ .coverage_exponent = 0.55 });
}

const assets = @import("assets");

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

    const fonts = [_]struct { bytes: []const u8, label: []const u8, slug: []const u8, prop: bool = false }{
        .{ .bytes = assets.dejavu_sans_mono, .label = "DejaVu Sans Mono (TT-hinted)", .slug = "dejavu" },
        .{ .bytes = assets.noto_sans_mono, .label = "Noto Sans Mono (unhinted VF)", .slug = "noto" },
        .{ .bytes = assets.noto_sans_regular, .label = "Noto Sans (proportional TT-hinted)", .slug = "notoprop", .prop = true },
        .{ .bytes = assets.dejavu_serif, .label = "DejaVu Serif (proportional TT-hinted)", .slug = "dejavuserif", .prop = true },
    };
    for (fonts) |f| {
        var compare = try compare_mod.Compare.initFontMode(allocator, pool, f.bytes, f.label, f.prop);
        defer compare.deinit();
        std.debug.print("\n######## {s} ########\n", .{f.label});
        try runFont(allocator, pool, &compare, f.slug);
    }
}

fn runFont(allocator: std.mem.Allocator, pool: *snail.PagePool, compare: *compare_mod.Compare, slug: []const u8) !void {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    var frame = std.heap.ArenaAllocator.init(allocator);
    defer frame.deinit();

    // Monospace snaps uniform columns; a proportional face snaps per-glyph origins.
    const snap: helpers.RunSnap = if (compare.proportional) .origins else .columns;

    // Populate the atlas with every unhinted base, autohint analysis and TT-baked
    // glyph the grid references, at all grid ppems.
    const shaped = try compare.shape_cache.shape(&compare.faces, compare_mod.sample_text, .{});
    const tags = try compare.shape_cache.shape(&compare.faces, "unyxytt", .{});
    try compare.ensureAll(scratch.allocator(), shaped, tags, 1.0);

    var empty_atlas = snail.Atlas.empty(allocator);
    defer empty_atlas.deinit();
    var empty_pic = try helpers.Picture.from(allocator, &.{});
    defer empty_pic.deinit();

    const n = compare_mod.grid_ppems.len;
    const cell = @as(usize, W) * H;
    const xy_ink = try allocator.alloc(u8, cell);
    defer allocator.free(xy_ink);
    const tt_ink = try allocator.alloc(u8, cell);
    defer allocator.free(tt_ink);

    // Three stacked composites (bottom-up, like the harness output; smallest
    // ppem at the top so slot k counts down): plain grayscale xy, plain
    // grayscale tt, and the red/green overlay. The grayscale pair is what the
    // demo actually shows — the overlay just localises where they differ.
    const comp_xy = try allocator.alloc(u8, cell * n * 4);
    defer allocator.free(comp_xy);
    const comp_tt = try allocator.alloc(u8, cell * n * 4);
    defer allocator.free(comp_tt);
    const composite = try allocator.alloc(u8, cell * n * 4);
    defer allocator.free(composite);
    @memset(comp_xy, 255);
    @memset(comp_tt, 255);
    @memset(composite, 255);

    std.debug.print("autohint default policy vs TrueType disagreement (lower = closer)\n", .{});
    std.debug.print("  ppem  em   sum|Δ|   px>margin   best_dx,dy residual  (rigid shift that best aligns xy->tt; 0,0 => not a registration offset)\n", .{});

    var grand: u64 = 0;
    for (compare_mod.grid_ppems, 0..) |ppem, k| {
        _ = frame.reset(.retain_capacity);
        const em = compare_mod.Compare.devEm(ppem, 1.0);
        const ppem_26_6: u32 = @intFromFloat(em * 64.0);

        const tt = try renderMode(allocator, frame.allocator(), pool, &compare.atlas, &empty_atlas, &empty_pic, shaped, em, 0, 0, .{ .truetype = .{ .ppem_26_6 = ppem_26_6 } }, snap);
        defer allocator.free(tt);
        extractInk(tt, tt_ink);

        const xy = try renderMode(allocator, frame.allocator(), pool, &compare.atlas, &empty_atlas, &empty_pic, shaped, em, 0, 0, .{ .autohint = compare_mod.default_policy }, snap);
        defer allocator.free(xy);
        extractInk(xy, xy_ink);

        var row_sum: u64 = 0;
        var row_cnt: u64 = 0;
        for (xy_ink, tt_ink) |a, t| {
            const d = if (a > t) a - t else t - a;
            row_sum += d;
            if (d > 40) row_cnt += 1;
        }
        grand += row_sum;

        // Diagnostic: re-render xy over a grid of sub-pixel x/y offsets and
        // find the rigid shift that best matches tt. A small best shift with a
        // large residual drop => the disagreement is *registration*; 0,0
        // optimal (as here) => it's genuine per-glyph phase/shape, not a global
        // offset any single translation can fix.
        var best_dx: f32 = 0;
        var best_dy: f32 = 0;
        var best_res: u64 = row_sum;
        var oy: f32 = -1.5;
        while (oy <= 1.5 + 1e-3) : (oy += 0.5) {
            var ox: f32 = -1.5;
            while (ox <= 1.5 + 1e-3) : (ox += 0.25) {
                if (@abs(ox) < 1e-3 and @abs(oy) < 1e-3) continue;
                const shifted = try renderMode(allocator, frame.allocator(), pool, &compare.atlas, &empty_atlas, &empty_pic, shaped, em, ox, oy, .{ .autohint = compare_mod.default_policy }, snap);
                defer allocator.free(shifted);
                extractInk(shifted, xy_ink);
                var res: u64 = 0;
                for (xy_ink, tt_ink) |a, t| res += if (a > t) a - t else t - a;
                if (res < best_res) {
                    best_res = res;
                    best_dx = ox;
                    best_dy = oy;
                }
            }
        }
        // xy_ink currently holds the last shifted render; restore the unshifted
        // one for the overlay below.
        extractInk(xy, xy_ink);

        std.debug.print("  {d:>4}  {d:>2}  {d:>7}  {d:>7}   {d:>5.2},{d:>5.2}  {d:>7}\n", .{ ppem, @as(u32, @intFromFloat(em)), row_sum, row_cnt, best_dx, best_dy, best_res });

        // Paint each slot: plain grayscale xy and tt (what the demo shows),
        // plus the overlay (red = TT-only, green = xy-policy-only, gray = both).
        const slot = (n - 1 - k) * H;
        for (0..H) |y| {
            for (0..W) |x| {
                const s = y * W + x;
                const a = xy_ink[s];
                const t = tt_ink[s];
                const d = (slot + y) * W + x;
                inline for (.{ .{ comp_xy, a }, .{ comp_tt, t } }) |pair| {
                    pair[0][d * 4 + 0] = 255 - pair[1];
                    pair[0][d * 4 + 1] = 255 - pair[1];
                    pair[0][d * 4 + 2] = 255 - pair[1];
                    pair[0][d * 4 + 3] = 255;
                }
                composite[d * 4 + 0] = 255 - t;
                composite[d * 4 + 1] = 255 - a;
                composite[d * 4 + 2] = 255 - @max(a, t);
                composite[d * 4 + 3] = 255;
            }
        }
    }
    std.debug.print("  ----  --  -------\n", .{});
    std.debug.print("  total     {d:>7}\n", .{grand});

    _ = std.c.mkdir("zig-out", 0o755);
    var buf: [64]u8 = undefined;
    for ([_]struct { suffix: []const u8, data: []u8 }{
        .{ .suffix = "xy", .data = comp_xy },
        .{ .suffix = "tt", .data = comp_tt },
        .{ .suffix = "diff", .data = composite },
    }) |o| {
        const path = try std.fmt.bufPrintZ(&buf, "zig-out/autohint-{s}-{s}.tga", .{ slug, o.suffix });
        try support.screenshot.writeTga(path, o.data, W, @intCast(H * n));
    }
    std.debug.print("  wrote zig-out/autohint-{s}-(xy|tt|diff).tga ({d}x{d})\n", .{ slug, W, H * n });
}
