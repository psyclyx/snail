//! GL counterpart to `screenshot_new.zig`. Renders the same Picture
//! content through the new-API GL upload + draw path (Phase 5a) and
//! writes `zig-out/demo-screenshot-new-gl.tga`. Useful for like-for-
//! like CPU/GL pixel comparison of the new path.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const gl = @import("support").gl;
const assets_data = @import("assets");
const banner_snail_new = @import("banner_snail_new.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

const W: u32 = 400;
const H: u32 = 240;
const STRIDE: u32 = W * 4;
const OUT_PATH = "zig-out/demo-screenshot-new-gl.tga";

const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;

const OffscreenTarget = struct {
    fbo: gl.GLuint = 0,
    fbo_tex: gl.GLuint = 0,

    fn init(width: u32, height: u32) !OffscreenTarget {
        var self = OffscreenTarget{};
        gl.glGenFramebuffers(1, &self.fbo);
        gl.glGenTextures(1, &self.fbo_tex);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.fbo_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, @intCast(width), @intCast(height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.fbo_tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        return self;
    }

    fn deinit(self: *OffscreenTarget) void {
        gl.glDeleteFramebuffers(1, &self.fbo);
        gl.glDeleteTextures(1, &self.fbo_tex);
    }
};

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(W, H, .gl33);
    defer gl_ctx.deinit();

    var target = try OffscreenTarget.init(W, H);
    defer target.deinit();

    // -- Shape text (identical to screenshot_new.zig).
    var text_atlas = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_bold, .weight = .bold },
        .{ .data = assets_data.noto_sans_arabic, .fallback = true },
        .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
        .{ .data = assets_data.noto_sans_thai, .fallback = true },
        .{ .data = assets_data.twemoji_mozilla, .fallback = true },
    });
    defer text_atlas.deinit();

    const wordmark_text = "snail";
    const tagline_text = "GPU text and vector rendering";
    const sample_hello = "Hello";
    const sample_arabic = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7";
    const sample_devanagari = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87";
    const sample_thai = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5";
    const sample_emoji = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d";

    inline for (.{
        .{ .weight = .bold, .text = wordmark_text },
        .{ .weight = .regular, .text = tagline_text },
        .{ .weight = .regular, .text = sample_hello },
        .{ .weight = .regular, .text = sample_arabic },
        .{ .weight = .regular, .text = sample_devanagari },
        .{ .weight = .regular, .text = sample_thai },
        .{ .weight = .regular, .text = sample_emoji },
        .{ .weight = .regular, .text = " \xc2\xb7 " },
    }) |entry| {
        const style: snail.FontStyle = .{ .weight = entry.weight };
        if (try text_atlas.ensureText(style, entry.text)) |next| {
            text_atlas.deinit();
            text_atlas = next;
        }
    }

    var shaped_wordmark = try text_atlas.shapeText(allocator, .{ .weight = .bold }, wordmark_text);
    defer shaped_wordmark.deinit();
    var shaped_tagline = try text_atlas.shapeText(allocator, .{}, tagline_text);
    defer shaped_tagline.deinit();

    const sample_texts = [_][]const u8{ sample_hello, sample_arabic, sample_devanagari, sample_thai, sample_emoji };
    var shaped_samples: [sample_texts.len]snail.ShapedText = undefined;
    var shaped_count: usize = 0;
    defer for (shaped_samples[0..shaped_count]) |*s| s.deinit();
    for (sample_texts) |text| {
        shaped_samples[shaped_count] = try text_atlas.shapeText(allocator, .{}, text);
        shaped_count += 1;
    }
    var shaped_sep = try text_atlas.shapeText(allocator, .{}, " \xc2\xb7 ");
    defer shaped_sep.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var font_regular = try snail.Font.init(assets_data.noto_sans_regular);
    defer font_regular.deinit();
    var font_bold = try snail.Font.init(assets_data.noto_sans_bold);
    defer font_bold.deinit();
    var font_arabic = try snail.Font.init(assets_data.noto_sans_arabic);
    defer font_arabic.deinit();
    var font_devanagari = try snail.Font.init(assets_data.noto_sans_devanagari);
    defer font_devanagari.deinit();
    var font_thai = try snail.Font.init(assets_data.noto_sans_thai);
    defer font_thai.deinit();
    var font_emoji = try snail.Font.init(assets_data.twemoji_mozilla);
    defer font_emoji.deinit();
    var fonts = [_]*snail.Font{ &font_regular, &font_bold, &font_arabic, &font_devanagari, &font_thai, &font_emoji };
    const face_to_font_id = [_]u32{ 0, 1, 2, 3, 4, 5 };
    const colr_fonts = [_]*const snail.Font{ &font_regular, &font_bold, &font_arabic, &font_devanagari, &font_thai, &font_emoji };

    var glyph_cache = snail.font.GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    var owned_curves: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (owned_curves.items) |*c| c.deinit();
        owned_curves.deinit(allocator);
    }
    var text_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer text_entries.deinit(allocator);

    for (shaped_tagline.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(text_entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try text_entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
    }
    const sample_runs = [_]*const snail.ShapedText{
        &shaped_samples[0], &shaped_samples[1], &shaped_samples[2],
        &shaped_samples[3], &shaped_samples[4], &shaped_sep,
    };
    for (sample_runs) |shaped_ptr| {
        for (shaped_ptr.glyphs) |g| {
            const fid: u32 = g.face_index;
            if (fid >= fonts.len) continue;
            try ensureGlyphOrColrLayers(allocator, &glyph_cache, fonts[fid], fid, g.glyph_id, &owned_curves, &text_entries);
        }
    }

    var path_curves_owned: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (path_curves_owned.items) |*c| c.deinit();
        path_curves_owned.deinit(allocator);
    }
    var path_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer path_entries.deinit(allocator);
    var path_shapes: std.ArrayList(snail.Shape) = .empty;
    defer path_shapes.deinit(allocator);
    var next_path_id: u32 = 0;

    const card_rect = snail.Rect{ .x = 12, .y = 12, .w = @as(f32, @floatFromInt(W)) - 24, .h = @as(f32, @floatFromInt(H)) - 24 };

    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.pathToCurves(allocator, &p));
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{ .key = key, .curves = path_curves_owned.items[path_curves_owned.items.len - 1], .paint = .{ .solid = .{ 1, 1, 1, 1 } } });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.strokeToCurves(allocator, &p, .{ .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } }, .width = 1.5 }));
        const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{ .key = key, .curves = path_curves_owned.items[path_curves_owned.items.len - 1], .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } } });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    {
        const snail_stage = snail.Rect{ .x = @as(f32, @floatFromInt(W)) - 154.0, .y = 12.0, .w = 140.0, .h = 122.0 };
        const snail_builder = banner_snail_new.Builder{
            .allocator = allocator,
            .owned_curves = &path_curves_owned,
            .entries = &path_entries,
            .shapes = &path_shapes,
            .next_id = &next_path_id,
        };
        try banner_snail_new.addVectorSnail(snail_builder, snail_stage);
    }

    const left_pad: f32 = 24;
    const wordmark_baseline: f32 = 76;
    const wordmark_em: f32 = 52;
    const tagline_baseline: f32 = wordmark_baseline + 22;
    const tagline_em: f32 = 13;
    const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };

    const wordmark_world_gradient = snail.LinearGradient{
        .start = .{ .x = left_pad, .y = wordmark_baseline - wordmark_em },
        .end = .{ .x = left_pad + 135, .y = wordmark_baseline },
        .start_color = .{ 0.08, 0.30, 0.72, 1.0 },
        .end_color = .{ 0.10, 0.10, 0.14, 1.0 },
    };
    for (shaped_wordmark.glyphs) |g| {
        const fid: u32 = g.face_index;
        if (fid >= fonts.len) continue;
        const pen_x = left_pad + wordmark_em * g.x_offset;
        const pen_y = wordmark_baseline + wordmark_em * g.y_offset;
        const transform = snail.Transform2D{
            .xx = wordmark_em, .xy = 0, .tx = pen_x,
            .yx = 0, .yy = -wordmark_em, .ty = pen_y,
        };
        const local_paint = snail.mapPaintToLocal(.{ .linear_gradient = wordmark_world_gradient }, transform) orelse continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try path_curves_owned.append(allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{ .key = key, .curves = path_curves_owned.items[path_curves_owned.items.len - 1], .paint = local_paint });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = transform, .local_color = .{ 1, 1, 1, 1 } });
    }

    var paths_atlas = try snail.Atlas.from(allocator, pool, path_entries.items);
    defer paths_atlas.deinit();
    var paths_picture = try snail.Picture.from(allocator, path_shapes.items);
    defer paths_picture.deinit();

    var text_atlas_new = try snail.Atlas.from(allocator, pool, text_entries.items);
    defer text_atlas_new.deinit();

    // -- GL renderer init.
    var gl_renderer = try snail.Gl33Renderer.init(allocator);
    defer gl_renderer.deinit();

    var cache = try snail.Gl33PreparedPages.init(allocator, pool);
    defer cache.deinit();
    const paths_binding = try cache.upload(allocator, &paths_atlas);
    const text_binding = try cache.upload(allocator, &text_atlas_new);

    var tagline_pic = try snail.shapedRunPicture(allocator, &shaped_tagline, .{
        .baseline = .{ .x = left_pad, .y = tagline_baseline },
        .em = tagline_em,
        .color = tagline_color,
        .face_to_font_id = &face_to_font_id,
    });
    defer tagline_pic.deinit();

    const sample_baseline: f32 = 196.0;
    const sample_em: f32 = 16.0;
    const sample_color = [4]f32{ 0.15, 0.18, 0.24, 1.0 };
    const sep_color = [4]f32{ 0.65, 0.70, 0.78, 1.0 };
    var sample_pics: std.ArrayList(snail.Picture) = .empty;
    defer {
        for (sample_pics.items) |*p| p.deinit();
        sample_pics.deinit(allocator);
    }

    var sx = left_pad;
    for (shaped_samples[0..shaped_count], 0..) |shaped, sample_idx| {
        if (sample_idx != 0) {
            try sample_pics.append(allocator, try snail.shapedRunPicture(allocator, &shaped_sep, .{
                .baseline = .{ .x = sx, .y = sample_baseline },
                .em = sample_em,
                .color = sep_color,
                .face_to_font_id = &face_to_font_id,
                .colr_fonts = &colr_fonts,
            }));
            sx += shaped_sep.advanceX() * sample_em;
        }
        try sample_pics.append(allocator, try snail.shapedRunPicture(allocator, &shaped, .{
            .baseline = .{ .x = sx, .y = sample_baseline },
            .em = sample_em,
            .color = sample_color,
            .face_to_font_id = &face_to_font_id,
            .colr_fonts = &colr_fonts,
        }));
        sx += shaped.advanceX() * sample_em;
    }

    var combine_inputs: std.ArrayList(*const snail.Picture) = .empty;
    defer combine_inputs.deinit(allocator);
    try combine_inputs.append(allocator, &tagline_pic);
    for (sample_pics.items) |*p| try combine_inputs.append(allocator, p);

    var text_pic = try snail.Picture.concat(allocator, combine_inputs.items);
    defer text_pic.deinit();

    // -- Emit + draw via GL.
    const words = try allocator.alloc(u32, snail.emit.wordBudget(&paths_picture, 0) + snail.emit.wordBudget(&text_pic, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &paths_atlas, &paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &text_atlas_new, &text_pic, .identity, .{ 1, 1, 1, 1 });

    // GL view: y axis goes up (origin bottom-left). Mirror the
    // ortho the CPU demo uses so the resulting framebuffer renders
    // bottom-up natively (writeTga flips again).
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const draw_state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };

    const bg = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };
    gl.glClearColor(srgbToLinear(bg[0]), srgbToLinear(bg[1]), srgbToLinear(bg[2]), bg[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl_renderer.state.beginDraw();
    try gl_renderer.state.drawNewApi(
        allocator,
        draw_state,
        .{ .words = words[0..wlen], .segments = segs[0..slen] },
        &.{&cache},
    );

    const pixels = try screenshot.captureFramebuffer(allocator, W, H);
    defer allocator.free(pixels);

    _ = std.c.mkdir("zig-out", 0o755);
    try screenshot.writeTga(OUT_PATH, pixels, W, H);
    std.debug.print("wrote {s}\n", .{OUT_PATH});
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

fn ensureGlyphOrColrLayers(
    allocator: std.mem.Allocator,
    cache: *snail.font.GlyphCache,
    font: *snail.Font,
    fid: u32,
    glyph_id: u16,
    owned_curves: *std.ArrayList(snail.GlyphCurves),
    entries: *std.ArrayList(snail.AtlasEntry),
) !void {
    var iter = font.colrLayers(glyph_id);
    if (iter.count() > 0) {
        while (iter.next()) |layer| {
            const key = snail.recordKey.unhintedGlyph(fid, layer.glyph_id);
            if (containsKey(entries.items, key)) continue;
            const curves = try font.extractCurves(allocator, cache, layer.glyph_id);
            try owned_curves.append(allocator, curves);
            try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
        }
        return;
    }
    const key = snail.recordKey.unhintedGlyph(fid, glyph_id);
    if (containsKey(entries.items, key)) return;
    const curves = try font.extractCurves(allocator, cache, glyph_id);
    try owned_curves.append(allocator, curves);
    try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
}
