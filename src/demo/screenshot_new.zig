//! Minimal screenshot demo that goes through the new snail API end-to-end:
//! shaped text (`shapedRunPicture`) + a gradient paint record (`Atlas.from`
//! with an entry carrying `paint`) + a CPU draw (`drawCpu`).
//!
//! Not a replacement for the legacy `screenshot.zig` demo yet: this one
//! intentionally drops the path-picture vector snail and the
//! emoji/multi-script fallback content so the new-API renderable surface
//! we have today is exercised cleanly. Output goes to
//! `zig-out/demo-screenshot-new.tga`.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const assets_data = @import("assets");

const W: u32 = 400;
const H: u32 = 240;
const STRIDE: u32 = W * 4;
const OUT_PATH = "zig-out/demo-screenshot-new.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const pixels = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels);
    // Light background.
    const bg = [4]u8{ 245, 246, 249, 255 };
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        pixels[i + 0] = bg[0];
        pixels[i + 1] = bg[1];
        pixels[i + 2] = bg[2];
        pixels[i + 3] = bg[3];
    }

    // Text atlas - reuse the legacy shaping pipeline because the new API
    // doesn't have its own shaping bridge yet (the workloads doc envisions
    // one but it's not built).
    var text_atlas = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_bold, .weight = .bold },
    });
    defer text_atlas.deinit();

    const wordmark_text = "snail";
    const tagline_text = "GPU text and vector rendering";

    if (try text_atlas.ensureText(.{ .weight = .bold }, wordmark_text)) |next| {
        text_atlas.deinit();
        text_atlas = next;
    }
    if (try text_atlas.ensureText(.{}, tagline_text)) |next| {
        text_atlas.deinit();
        text_atlas = next;
    }

    var shaped_wordmark = try text_atlas.shapeText(allocator, .{ .weight = .bold }, wordmark_text);
    defer shaped_wordmark.deinit();
    var shaped_tagline = try text_atlas.shapeText(allocator, .{}, tagline_text);
    defer shaped_tagline.deinit();

    // New-API pool + per-font extraction.
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
    var fonts = [_]*snail.Font{ &font_regular, &font_bold };

    var glyph_cache = snail.font.GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    var owned_curves: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (owned_curves.items) |*c| c.deinit();
        owned_curves.deinit(allocator);
    }
    var entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer entries.deinit(allocator);

    const wordmark_gradient = snail.LinearGradient{
        .start = .{ .x = 0, .y = -0.7 },
        .end = .{ .x = 1.0, .y = 0.0 },
        .start_color = .{ 0.08, 0.30, 0.72, 1.0 },
        .end_color = .{ 0.10, 0.10, 0.14, 1.0 },
    };

    // Wordmark glyphs: bold font (face 1), gradient paint.
    for (shaped_wordmark.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (alreadyHas(entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try entries.append(allocator, .{
            .key = key,
            .curves = owned_curves.items[owned_curves.items.len - 1],
            .paint = .{ .linear_gradient = wordmark_gradient },
        });
    }
    // Tagline glyphs: regular font (face 0), no paint.
    for (shaped_tagline.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (alreadyHas(entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
    }

    var atlas = try snail.Atlas.from(allocator, pool, entries.items);
    defer atlas.deinit();

    var cache = try snail.CpuPreparedPages.init(allocator, pool);
    defer cache.deinit();
    const binding = try cache.upload(&atlas);

    // Build pictures placing the shaped runs.
    const left_pad: f32 = 24;
    const wordmark_baseline: f32 = 76;
    const wordmark_em: f32 = 52;
    const tagline_baseline: f32 = wordmark_baseline + 22;
    const tagline_em: f32 = 13;
    const wordmark_color = [4]f32{ 1, 1, 1, 1 }; // gradient supplies the actual color
    const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };

    var wordmark_pic = try snail.shapedRunPicture(allocator, &shaped_wordmark, .{
        .baseline = .{ .x = left_pad, .y = wordmark_baseline },
        .em = wordmark_em,
        .color = wordmark_color,
        .face_to_font_id = &.{ 0, 1 },
    });
    defer wordmark_pic.deinit();

    var tagline_pic = try snail.shapedRunPicture(allocator, &shaped_tagline, .{
        .baseline = .{ .x = left_pad, .y = tagline_baseline },
        .em = tagline_em,
        .color = tagline_color,
        .face_to_font_id = &.{ 0, 1 },
    });
    defer tagline_pic.deinit();

    var combined = try snail.Picture.concat(allocator, &.{ &wordmark_pic, &tagline_pic });
    defer combined.deinit();

    // Emit + draw.
    const words = try allocator.alloc(u32, snail.emit.wordBudget(&combined, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, snail.emit.segmentBudget(&combined, 0));
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, binding, &atlas, &combined, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(pixels.ptr, W, H, STRIDE);
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .fill_rule = .non_zero, .subpixel_order = .rgb, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    try snail.drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    // `writeTga` assumes a GL-style bottom-up framebuffer (it y-flips
    // when writing the file header's top-left origin). The CPU renderer
    // writes top-down, so pre-flip to compensate.
    flipRowsInPlace(pixels);

    _ = std.c.mkdir("zig-out", 0o755);
    try screenshot.writeTga(OUT_PATH, pixels, W, H);
    std.debug.print("wrote {s}\n", .{OUT_PATH});
}

fn flipRowsInPlace(pixels: []u8) void {
    var tmp: [W * 4]u8 = undefined;
    var y: usize = 0;
    while (y < H / 2) : (y += 1) {
        const top = y * W * 4;
        const bottom = (@as(usize, H) - 1 - y) * W * 4;
        @memcpy(&tmp, pixels[top..][0 .. W * 4]);
        @memcpy(pixels[top..][0 .. W * 4], pixels[bottom..][0 .. W * 4]);
        @memcpy(pixels[bottom..][0 .. W * 4], &tmp);
    }
}

fn alreadyHas(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}
