//! Minimal screenshot demo that goes through the new snail API end-to-end:
//! shaped text (`shapedRunPicture`) + paint records + path primitives via
//! direct `pathToCurves` / `strokeToCurves` composition + CPU draw.
//!
//! Not a replacement for the legacy `screenshot.zig` demo yet: the COLR /
//! SVG emoji and multi-script fallback are dropped, and the vector-snail
//! `addVectorSnail` content is reduced to a placeholder shell ellipse.
//! Output goes to `zig-out/demo-screenshot-new.tga`.

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
    const bg = [4]u8{ 245, 246, 249, 255 };
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        pixels[i + 0] = bg[0];
        pixels[i + 1] = bg[1];
        pixels[i + 2] = bg[2];
        pixels[i + 3] = bg[3];
    }

    // -- Shape text via the existing TextAtlas (no new-API shaping yet).
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
    var text_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer text_entries.deinit(allocator);

    const wordmark_gradient = snail.LinearGradient{
        .start = .{ .x = 0, .y = -0.7 },
        .end = .{ .x = 1.0, .y = 0.0 },
        .start_color = .{ 0.08, 0.30, 0.72, 1.0 },
        .end_color = .{ 0.10, 0.10, 0.14, 1.0 },
    };

    for (shaped_wordmark.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(text_entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try text_entries.append(allocator, .{
            .key = key,
            .curves = owned_curves.items[owned_curves.items.len - 1],
            .paint = .{ .linear_gradient = wordmark_gradient },
        });
    }
    for (shaped_tagline.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(text_entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try text_entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
    }

    // -- Path content: build geometry directly with the Path API, convert
    // via `pathToCurves` / `strokeToCurves`, and assemble Atlas entries
    // and Shapes inline. No helper builder layer.
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

    const card_rect = snail.Rect{
        .x = 12,
        .y = 12,
        .w = @as(f32, @floatFromInt(W)) - 24,
        .h = @as(f32, @floatFromInt(H)) - 24,
    };

    // Card fill (white rounded rect).
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.pathToCurves(allocator, &p));
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    // Card stroke (light gray border).
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.strokeToCurves(allocator, &p, .{
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
            .width = 1.5,
        }));
        const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    // Shell placeholder (radial-gradient ellipse).
    const shell_cx: f32 = @as(f32, @floatFromInt(W)) - 70.0;
    const shell_cy: f32 = 60.0;
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addEllipse(.{ .x = shell_cx - 28, .y = shell_cy - 24, .w = 56, .h = 48 });
        try path_curves_owned.append(allocator, try snail.paths.pathToCurves(allocator, &p));
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .radial_gradient = .{
                .center = .{ .x = shell_cx - 5, .y = shell_cy - 6 },
                .radius = 28,
                .inner_color = .{ 0.95, 0.85, 0.55, 1.0 },
                .outer_color = .{ 0.55, 0.40, 0.20, 1.0 },
            } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }

    var paths_atlas = try snail.Atlas.from(allocator, pool, path_entries.items);
    defer paths_atlas.deinit();
    var paths_picture = try snail.Picture.from(allocator, path_shapes.items);
    defer paths_picture.deinit();

    var text_atlas_new = try snail.Atlas.from(allocator, pool, text_entries.items);
    defer text_atlas_new.deinit();

    // One cache serves both atlases through the same pool; bindings
    // disambiguate via their `generation` slot.
    var cache = try snail.CpuPreparedPages.init(allocator, pool);
    defer cache.deinit();
    const paths_binding = try cache.upload(&paths_atlas);
    const text_binding = try cache.upload(&text_atlas_new);

    // -- Build text Picture via shapedRunPicture.
    const left_pad: f32 = 24;
    const wordmark_baseline: f32 = 76;
    const wordmark_em: f32 = 52;
    const tagline_baseline: f32 = wordmark_baseline + 22;
    const tagline_em: f32 = 13;
    const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };

    var wordmark_pic = try snail.shapedRunPicture(allocator, &shaped_wordmark, .{
        .baseline = .{ .x = left_pad, .y = wordmark_baseline },
        .em = wordmark_em,
        .color = .{ 1, 1, 1, 1 },
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
    var text_pic = try snail.Picture.concat(allocator, &.{ &wordmark_pic, &tagline_pic });
    defer text_pic.deinit();

    // -- Emit + draw. Paths first (under), then text (over).
    const words = try allocator.alloc(u32, snail.emit.wordBudget(&paths_picture, 0) + snail.emit.wordBudget(&text_pic, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &paths_atlas, &paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &text_atlas_new, &text_pic, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(pixels.ptr, W, H, STRIDE);
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .fill_rule = .non_zero, .subpixel_order = .rgb, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    try snail.drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    // CPU buffer is top-down; writeTga assumes GL-style bottom-up.
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

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}
