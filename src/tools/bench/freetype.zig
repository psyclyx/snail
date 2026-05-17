const std = @import("std");

const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const Config = struct {
    prep_runs: usize,
    text_iters: usize,
    printable_ascii: []const u8,
    sizes: []const u32,
    short: []const u8,
    sentence: []const u8,
    paragraph: []const u8,
};

pub const Results = struct {
    font_load_us: f64,
    glyph_prep_us: f64,
    glyph_prep_all_sizes_us: f64,
    bitmap_bytes_single: usize,
    bitmap_bytes_all: usize,
    layout_short_us: f64,
    layout_sentence_us: f64,
    layout_paragraph_us: f64,
    layout_torture_us: f64,

    pub fn layout(self: Results, workload: anytype) f64 {
        return switch (workload) {
            .short => self.layout_short_us,
            .sentence => self.layout_sentence_us,
            .paragraph => self.layout_paragraph_us,
            .paragraph_sizes => self.layout_torture_us,
        };
    }
};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usFrom(start: u64) f64 {
    return @as(f64, @floatFromInt(nowNs() - start)) / 1000.0;
}

pub fn bench(font_data: []const u8, config: Config) !Results {
    var font_load_total_us: f64 = 0;
    for (0..config.prep_runs) |_| {
        var load_library: c.FT_Library = null;
        const start = nowNs();
        if (c.FT_Init_FreeType(&load_library) != 0) return error.FTInitFailed;
        var load_face: c.FT_Face = null;
        if (c.FT_New_Memory_Face(load_library, font_data.ptr, @intCast(font_data.len), 0, &load_face) != 0) {
            _ = c.FT_Done_FreeType(load_library);
            return error.FTFaceFailed;
        }
        font_load_total_us += usFrom(start);
        _ = c.FT_Done_Face(load_face);
        _ = c.FT_Done_FreeType(load_library);
    }

    var library: c.FT_Library = null;
    if (c.FT_Init_FreeType(&library) != 0) return error.FTInitFailed;
    defer _ = c.FT_Done_FreeType(library);

    var face: c.FT_Face = null;
    if (c.FT_New_Memory_Face(library, font_data.ptr, @intCast(font_data.len), 0, &face) != 0) return error.FTFaceFailed;
    defer _ = c.FT_Done_Face(face);

    var bitmap_bytes_single: usize = 0;
    var glyph_prep_total_us: f64 = 0;
    for (0..config.prep_runs) |run| {
        _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
        var run_bytes: usize = 0;
        const start = nowNs();
        for (config.printable_ascii) |ch| {
            const gi = c.FT_Get_Char_Index(face, ch);
            if (gi == 0) continue;
            if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
            if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
            run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
        }
        glyph_prep_total_us += usFrom(start);
        if (run == 0) bitmap_bytes_single = run_bytes;
    }

    var bitmap_bytes_all: usize = 0;
    var glyph_prep_all_total_us: f64 = 0;
    for (0..config.prep_runs) |run| {
        var run_bytes: usize = 0;
        const start = nowNs();
        for (config.sizes) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            for (config.printable_ascii) |ch| {
                const gi = c.FT_Get_Char_Index(face, ch);
                if (gi == 0) continue;
                if (c.FT_Load_Glyph(face, gi, c.FT_LOAD_DEFAULT) != 0) continue;
                if (c.FT_Render_Glyph(face.*.glyph, c.FT_RENDER_MODE_NORMAL) != 0) continue;
                run_bytes += @as(usize, face.*.glyph.*.bitmap.width) * @as(usize, face.*.glyph.*.bitmap.rows);
            }
        }
        glyph_prep_all_total_us += usFrom(start);
        if (run == 0) bitmap_bytes_all = run_bytes;
    }

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
                if (c.FT_Load_Glyph(self.face, gi, c.FT_LOAD_DEFAULT) == 0) {
                    pen_x += @intCast(self.face.*.glyph.*.advance.x >> 6);
                }
                prev = gi;
            }
            std.mem.doNotOptimizeAway(pen_x);
        }
    };
    const ctx = LayoutCtx{ .face = face };

    _ = c.FT_Set_Pixel_Sizes(face, 0, 24);
    var start = nowNs();
    for (0..config.text_iters) |_| ctx.layoutString(config.short);
    const short_us = usFrom(start) / @as(f64, @floatFromInt(config.text_iters));

    _ = c.FT_Set_Pixel_Sizes(face, 0, 48);
    start = nowNs();
    for (0..config.text_iters) |_| ctx.layoutString(config.sentence);
    const sentence_us = usFrom(start) / @as(f64, @floatFromInt(config.text_iters));

    _ = c.FT_Set_Pixel_Sizes(face, 0, 18);
    start = nowNs();
    for (0..config.text_iters) |_| ctx.layoutString(config.paragraph);
    const paragraph_us = usFrom(start) / @as(f64, @floatFromInt(config.text_iters));

    start = nowNs();
    for (0..config.text_iters) |_| {
        for (config.sizes) |sz| {
            _ = c.FT_Set_Pixel_Sizes(face, 0, sz);
            ctx.layoutString(config.paragraph);
        }
    }
    const torture_us = usFrom(start) / @as(f64, @floatFromInt(config.text_iters));

    return .{
        .font_load_us = font_load_total_us / @as(f64, @floatFromInt(config.prep_runs)),
        .glyph_prep_us = glyph_prep_total_us / @as(f64, @floatFromInt(config.prep_runs)),
        .glyph_prep_all_sizes_us = glyph_prep_all_total_us / @as(f64, @floatFromInt(config.prep_runs)),
        .bitmap_bytes_single = bitmap_bytes_single,
        .bitmap_bytes_all = bitmap_bytes_all,
        .layout_short_us = short_us,
        .layout_sentence_us = sentence_us,
        .layout_paragraph_us = paragraph_us,
        .layout_torture_us = torture_us,
    };
}
