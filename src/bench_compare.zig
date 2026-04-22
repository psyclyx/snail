//! Comparative benchmark: snail vs FreeType.
//!
//! Both are usable font libraries with C APIs. This benchmark measures the
//! full pipeline for each across multiple realistic scenarios.
//!
//! snail: parse TTF → build GPU textures (one-time, all sizes) → lay out text
//! FreeType: load font → rasterize glyphs to bitmaps (per size) → lay out text
//!
//! GPU draw time is excluded because FreeType's draw path (textured quads) is
//! trivially cheap — the real cost difference is in preparation and layout.
//! snail's GPU shader cost is also negligible at <0.25ms/frame for 300+ glyphs.

const std = @import("std");
const assets = @import("assets");
const ttf = @import("font/ttf.zig");
const curve_tex = @import("render/curve_texture.zig");
const band_tex = @import("render/band_texture.zig");
const bezier = @import("math/bezier.zig");
const snail = @import("snail.zig");

const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

fn fmtUs(us: f64) [32]u8 {
    var buf: [32]u8 = .{' '} ** 32;
    _ = std.fmt.bufPrint(&buf, "{d:>10.1} us", .{us}) catch {};
    return buf;
}

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
const SIZES = [_]u32{ 12, 18, 24, 36, 48, 72, 96 };
const BENCH_TIME_MULTIPLIER = 10;
const PREP_RUNS = BENCH_TIME_MULTIPLIER;
const LAYOUT_ITERS = 500 * BENCH_TIME_MULTIPLIER;

// ── snail measurements ──

const SnailResults = struct {
    font_load_us: f64,
    glyph_prep_us: f64, // parse + build textures for all glyphs, all sizes
    texture_bytes: usize,
    layout_short_us: f64, // per-iter
    layout_sentence_us: f64,
    layout_paragraph_us: f64,
    layout_torture_us: f64, // paragraph at 7 sizes
};

fn benchSnail(allocator: std.mem.Allocator, font_data: []const u8) !SnailResults {
    // Font load
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const t = nowNs();
        _ = try ttf.Font.init(font_data);
        font_load_total_us += usFrom(t);
    }
    const font_load_us = font_load_total_us / PREP_RUNS;
    const font_inner = try ttf.Font.init(font_data);

    // Glyph prep: parse all ASCII + build curve/band textures
    var font_wrapped = snail.Font{ .inner = font_inner };
    var glyph_prep_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        const t = nowNs();
        var tmp_atlas = try snail.Atlas.initAscii(allocator, &font_wrapped, &PRINTABLE_ASCII);
        glyph_prep_total_us += usFrom(t);
        tmp_atlas.deinit();
    }
    const glyph_prep_us = glyph_prep_total_us / PREP_RUNS;
    var atlas = try snail.Atlas.initAscii(allocator, &font_wrapped, &PRINTABLE_ASCII);
    defer atlas.deinit();

    const tex_bytes = atlas.textureByteLen();

    // Layout benchmarks
    var vbuf: [20000 * snail.FLOATS_PER_GLYPH]f32 = undefined;
    const white = [4]f32{ 1, 1, 1, 1 };

    // Short string
    var t = nowNs();
    for (0..LAYOUT_ITERS) |_| {
        var b = snail.Batch.init(&vbuf);
        _ = b.addString(&atlas, &font_wrapped, SHORT, 0, 0, 24, white);
        std.mem.doNotOptimizeAway(&b);
    }
    const layout_short_us = usFrom(t) / LAYOUT_ITERS;

    // Sentence at 48px
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| {
        var b = snail.Batch.init(&vbuf);
        _ = b.addString(&atlas, &font_wrapped, SENTENCE, 0, 0, 48, white);
        std.mem.doNotOptimizeAway(&b);
    }
    const layout_sentence_us = usFrom(t) / LAYOUT_ITERS;

    // Paragraph at 18px
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| {
        var b = snail.Batch.init(&vbuf);
        _ = b.addString(&atlas, &font_wrapped, PARAGRAPH, 0, 0, 18, white);
        std.mem.doNotOptimizeAway(&b);
    }
    const layout_paragraph_us = usFrom(t) / LAYOUT_ITERS;

    // Torture: paragraph at all 7 sizes
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| {
        var b = snail.Batch.init(&vbuf);
        var y: f32 = 700;
        for (SIZES) |sz| {
            const fsz: f32 = @floatFromInt(sz);
            _ = b.addString(&atlas, &font_wrapped, PARAGRAPH, 0, y, fsz, white);
            y -= fsz * 1.4;
        }
        std.mem.doNotOptimizeAway(&b);
    }
    const layout_torture_us = usFrom(t) / LAYOUT_ITERS;

    return .{
        .font_load_us = font_load_us,
        .glyph_prep_us = glyph_prep_us,
        .texture_bytes = tex_bytes,
        .layout_short_us = layout_short_us,
        .layout_sentence_us = layout_sentence_us,
        .layout_paragraph_us = layout_paragraph_us,
        .layout_torture_us = layout_torture_us,
    };
}

// ── FreeType measurements ──

const FTResults = struct {
    font_load_us: f64,
    glyph_prep_us: f64, // rasterize all ASCII at one size
    glyph_prep_all_sizes_us: f64, // rasterize at all 7 sizes
    bitmap_bytes_single: usize,
    bitmap_bytes_all: usize,
    layout_short_us: f64,
    layout_sentence_us: f64,
    layout_paragraph_us: f64,
    layout_torture_us: f64,
};

fn benchFreetype(font_data: []const u8) !FTResults {
    // Font load
    var font_load_total_us: f64 = 0;
    for (0..PREP_RUNS) |_| {
        var load_library: c.FT_Library = null;
        const t = nowNs();
        if (c.FT_Init_FreeType(&load_library) != 0) return error.FTInitFailed;
        var load_face: c.FT_Face = null;
        if (c.FT_New_Memory_Face(load_library, font_data.ptr, @intCast(font_data.len), 0, &load_face) != 0) {
            _ = c.FT_Done_FreeType(load_library);
            return error.FTFaceFailed;
        }
        font_load_total_us += usFrom(t);
        _ = c.FT_Done_Face(load_face);
        _ = c.FT_Done_FreeType(load_library);
    }
    const font_load_us = font_load_total_us / PREP_RUNS;

    var library: c.FT_Library = null;
    if (c.FT_Init_FreeType(&library) != 0) return error.FTInitFailed;
    defer _ = c.FT_Done_FreeType(library);
    var face: c.FT_Face = null;
    if (c.FT_New_Memory_Face(library, font_data.ptr, @intCast(font_data.len), 0, &face) != 0)
        return error.FTFaceFailed;
    defer _ = c.FT_Done_Face(face);

    // Glyph prep: rasterize all ASCII at 48px (single size)
    var bitmap_bytes_single: usize = 0;
    var glyph_prep_total_us: f64 = 0;
    for (0..PREP_RUNS) |run| {
        _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
        var run_bytes: usize = 0;
        const t = nowNs();
        for (&PRINTABLE_ASCII) |ch| {
            const gi = c.FT_Get_Char_Index(face, ch);
            if (gi == 0) continue;
            if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
            if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
            run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
        }
        glyph_prep_total_us += usFrom(t);
        if (run == 0) bitmap_bytes_single = run_bytes;
    }
    const glyph_prep_us = glyph_prep_total_us / PREP_RUNS;

    // Glyph prep: rasterize at ALL 7 sizes
    var bitmap_bytes_all: usize = 0;
    var glyph_prep_all_total_us: f64 = 0;
    for (0..PREP_RUNS) |run| {
        var run_bytes: usize = 0;
        const t = nowNs();
        for (SIZES) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            for (&PRINTABLE_ASCII) |ch| {
                const gi = c.FT_Get_Char_Index(face, ch);
                if (gi == 0) continue;
                if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
                if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
                run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
            }
        }
        glyph_prep_all_total_us += usFrom(t);
        if (run == 0) bitmap_bytes_all = run_bytes;
    }
    const glyph_prep_all_sizes_us = glyph_prep_all_total_us / PREP_RUNS;

    // Layout benchmarks — FreeType layout requires FT_Load_Glyph per character
    // to get advance widths (this is the real-world cost)
    _ = c.FT_Set_Pixel_Sizes(face, 0, 24);

    const LayoutCtx = struct {
        face: c.FT_Face,
        fn layoutString(self: @This(), text: []const u8) void {
            var pen_x: i32 = 0;
            var prev: u32 = 0;
            for (text) |ch| {
                const gi = c.FT_Get_Char_Index(self.face, ch);
                if (prev != 0 and gi != 0) {
                    var delta: c.FT_Vector = undefined;
                    _ = c.FT_Get_Kerning(self.face, prev, gi, c.FT_KERNING_DEFAULT, &delta);
                    pen_x += @intCast(delta.x >> 6);
                }
                if (c.FT_Load_Glyph(self.face, gi, c.FT_LOAD_DEFAULT) != 0) {
                    prev = gi;
                    continue;
                }
                pen_x += @intCast(self.face.*.glyph.*.advance.x >> 6);
                prev = gi;
            }
            std.mem.doNotOptimizeAway(&pen_x);
        }
    };
    const ctx = LayoutCtx{ .face = face };

    // Short
    var t = nowNs();
    for (0..LAYOUT_ITERS) |_| ctx.layoutString(SHORT);
    const layout_short_us = usFrom(t) / LAYOUT_ITERS;

    // Sentence
    _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| ctx.layoutString(SENTENCE);
    const layout_sentence_us = usFrom(t) / LAYOUT_ITERS;

    // Paragraph
    _ = c.FT_Set_Pixel_Sizes(face, 0, 18);
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| ctx.layoutString(PARAGRAPH);
    const layout_paragraph_us = usFrom(t) / LAYOUT_ITERS;

    // Torture: paragraph at all 7 sizes (FreeType must switch sizes each time)
    t = nowNs();
    for (0..LAYOUT_ITERS) |_| {
        for (SIZES) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            ctx.layoutString(PARAGRAPH);
        }
    }
    const layout_torture_us = usFrom(t) / LAYOUT_ITERS;

    return .{
        .font_load_us = font_load_us,
        .glyph_prep_us = glyph_prep_us,
        .glyph_prep_all_sizes_us = glyph_prep_all_sizes_us,
        .bitmap_bytes_single = bitmap_bytes_single,
        .bitmap_bytes_all = bitmap_bytes_all,
        .layout_short_us = layout_short_us,
        .layout_sentence_us = layout_sentence_us,
        .layout_paragraph_us = layout_paragraph_us,
        .layout_torture_us = layout_torture_us,
    };
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    const font_data = assets.noto_sans_regular;

    const s = try benchSnail(allocator, font_data);
    const f = try benchFreetype(font_data);

    std.debug.print(
        \\
        \\=== snail vs FreeType ===
        \\NotoSans-Regular.ttf, 95 ASCII glyphs, {d} prep runs, {d} layout samples/scenario
        \\
        \\                              snail            FreeType
        \\                              -----            --------
        \\  Font load               {s}      {s}
        \\  Glyph prep (1 size)     {s}      {s}
        \\  Glyph prep (7 sizes)    {s}      {s}
        \\  Texture/bitmap memory       {d:>6.0} KB (all)     {d:>6.0} KB (1 size)
        \\                                                {d:>6.0} KB (7 sizes)
        \\
        \\  Layout: "{s}"
        \\                          {s}      {s}
        \\  Layout: 53-char sentence @ 48px
        \\                          {s}      {s}
        \\  Layout: 175-char paragraph @ 18px
        \\                          {s}      {s}
        \\  Layout: paragraph x 7 sizes (torture)
        \\                          {s}      {s}
        \\
        \\  Notes:
        \\    - prep timings above are averages over {d} runs
        \\    - snail glyph prep is resolution-independent (same cost for any/all sizes)
        \\    - FreeType must re-rasterize per size ({d:.0} us per additional size)
        \\    - snail layout reads pre-parsed metrics; FreeType calls FT_Load_Glyph per char
        \\    - GPU draw cost excluded (trivial for both: textured quads vs Slug shader)
        \\
        \\========================
        \\
    , .{
        PREP_RUNS,
        LAYOUT_ITERS,
        fmtUs(s.font_load_us),
        fmtUs(f.font_load_us),
        fmtUs(s.glyph_prep_us),
        fmtUs(f.glyph_prep_us),
        fmtUs(s.glyph_prep_us),
        fmtUs(f.glyph_prep_all_sizes_us),
        @as(f64, @floatFromInt(s.texture_bytes)) / 1024.0,
        @as(f64, @floatFromInt(f.bitmap_bytes_single)) / 1024.0,
        @as(f64, @floatFromInt(f.bitmap_bytes_all)) / 1024.0,
        SHORT,
        fmtUs(s.layout_short_us),
        fmtUs(f.layout_short_us),
        fmtUs(s.layout_sentence_us),
        fmtUs(f.layout_sentence_us),
        fmtUs(s.layout_paragraph_us),
        fmtUs(f.layout_paragraph_us),
        fmtUs(s.layout_torture_us),
        fmtUs(f.layout_torture_us),
        PREP_RUNS,
        (f.glyph_prep_all_sizes_us - f.glyph_prep_us) / 6.0,
    });
}
