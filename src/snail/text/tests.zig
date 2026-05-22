const std = @import("std");

const paint_records = @import("../paint_records.zig");
const render_abi = @import("../render/format/abi.zig");
const snail = @import("../root.zig");
const text_hint_format = @import("../render/format/text_hint.zig");
const vertex = @import("../render/format/vertex.zig");

const FaceIndex = snail.FaceIndex;
const TextAppendResult = snail.TextAppendResult;
const TextAtlas = snail.TextAtlas;
const TextBatch = snail.TextBatch;
const TextBlobBuilder = snail.TextBlobBuilder;

const testing = std.testing;

fn appendTestText(
    builder: *TextBlobBuilder,
    style: snail.FontStyle,
    text: []const u8,
    baseline: snail.Vec2,
    em: f32,
    color: [4]f32,
) !TextAppendResult {
    var shaped = try builder.atlas.shapeText(builder.allocator, style, text);
    defer shaped.deinit();
    return builder.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = baseline, .em = em },
        .fill = .{ .solid = color },
    });
}

fn appendTestTextBatch(
    atlas: *const TextAtlas,
    batch: *TextBatch,
    style: snail.FontStyle,
    text: []const u8,
    baseline: snail.Vec2,
    em: f32,
    color: [4]f32,
    allow_missing: bool,
) !TextAppendResult {
    var shaped = try atlas.shapeText(testing.allocator, style, text);
    defer shaped.deinit();
    return atlas.appendTextBatch(batch, .{
        .glyphs = shaped.glyphs,
        .placement = .{ .baseline = baseline, .em = em },
        .color = color,
    }, allow_missing);
}

test "TextAtlas.init with single face" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(?FaceIndex, 0), fonts.config.primary_face);
    try testing.expectEqual(@as(usize, 1), fonts.config.faces.len);
    try testing.expectEqual(@as(usize, 0), fonts.pageCount());
}

test "font config cache distinguishes same-pointer slices by length" {
    const assets_data = @import("assets");
    const full = assets_data.noto_sans_regular;
    try testing.expectError(error.UnexpectedEof, TextAtlas.init(testing.allocator, &.{
        .{ .data = full },
        .{ .data = full[0..12], .fallback = true },
    }));
}

test "TextAtlas.ensureText adds missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(usize, 0), fonts.pageCount());

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    try testing.expect(fonts.pageCount() > 0);

    // Ensuring the same text again returns null (nothing new).
    const again = try fonts.ensureText(.{}, "Hello");
    try testing.expectEqual(@as(?TextAtlas, null), again);
}

test "TextAtlas.ensureText is stable for runs containing empty glyphs" {
    // Regression: a glyph rasterised with `h_band_count == 0` (e.g. space)
    // used to be reported as missing by `shapedGlyphAvailable` even after it
    // was placed in the atlas, while `ensureGlyphMaps` filtered it out via
    // `glyph_map.contains` — so each call published a new (functionally
    // identical) snapshot, spinning any caller that rebound on snapshot
    // identity changes.
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "a b")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    const pages_after_first = fonts.pageCount();

    // Re-ensuring text whose only "missing" glyph is the empty space must be
    // a no-op — no new snapshot, no new pages.
    try testing.expectEqual(@as(?TextAtlas, null), try fonts.ensureText(.{}, "a b"));
    try testing.expectEqual(@as(?TextAtlas, null), try fonts.ensureText(.{}, " "));
    try testing.expectEqual(pages_after_first, fonts.pageCount());
}

test "TextAtlas uses replacement glyph for unresolved codepoints" {
    const assets_data = @import("assets");
    const missing_text = "\xF4\x8F\xBF\xBF";
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(?u16, null), try fonts.glyphIndex(0, 0x10FFFF));
    const replacement = fonts.missingGlyphReplacement().?;
    try testing.expectEqual(@as(u21, 0xFFFD), replacement.codepoint);

    var shaped = try fonts.shapeText(testing.allocator, .{}, missing_text);
    defer shaped.deinit();
    try testing.expectEqual(@as(usize, 1), shaped.glyphs.len);
    try testing.expectEqual(replacement.face_index, shaped.glyphs[0].face_index);
    try testing.expectEqual(replacement.glyph_id, shaped.glyphs[0].glyph_id);
    try testing.expect(shaped.advance_x > 0);

    if (try fonts.ensureShaped(&shaped)) |next| {
        fonts.deinit();
        fonts = next;
    }
    try testing.expect(fonts.hasPreparedGlyph(replacement.face_index, replacement.glyph_id));

    var buf: [8 * snail.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.TextBatch.init(&buf);
    const result = try fonts.appendTextBatch(&batch, .{
        .glyphs = shaped.glyphs,
        .placement = .{ .baseline = .{ .x = 0, .y = 16 }, .em = 16 },
        .color = .{ 1, 1, 1, 1 },
    }, true);
    try testing.expect(!result.missing);
    try testing.expect(batch.glyphCount() > 0);
}

test "TextAtlas.ensureText snapshot immutability" {
    const assets_data = @import("assets");
    var fonts1 = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts1.deinit();

    if (try fonts1.ensureText(.{}, "AB")) |new_fonts| {
        fonts1.deinit();
        fonts1 = new_fonts;
    }
    const pages_before = fonts1.pageCount();

    const maybe_fonts2 = try fonts1.ensureText(.{}, "CDEFGHIJKLMNOP");
    try testing.expect(maybe_fonts2 != null);
    var fonts2 = maybe_fonts2.?;
    defer fonts2.deinit();

    try testing.expectEqual(pages_before, fonts1.pageCount());
    try testing.expect(fonts2.pageCount() >= pages_before);
}

test "TextAtlas.appendTextBatch renders and reports advance" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var buf: [64 * snail.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.TextBatch.init(&buf);
    const result = try appendTestTextBatch(&fonts, &batch, .{}, "Hello", .{ .x = 0, .y = 100 }, 24, .{ 1, 1, 1, 1 }, true);

    try testing.expect(result.advance.x > 0);
    try testing.expect(batch.glyphCount() > 0);
    try testing.expect(!result.missing);
}

test "TextAtlas.appendTextBatch reports missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Atlas is empty; addText should report missing glyphs.
    var buf: [64 * snail.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.TextBatch.init(&buf);
    const result = try appendTestTextBatch(&fonts, &batch, .{}, "Hello", .{ .x = 0, .y = 100 }, 24, .{ 1, 1, 1, 1 }, true);

    try testing.expect(result.missing);
    try testing.expectEqual(@as(usize, 0), batch.glyphCount());
}

test "TextBlobBuilder.append with partially-prepared atlas skips missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Prepare only "Hi" — the rest of the run will be missing.
    if (try fonts.ensureText(.{}, "Hi")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const result = try appendTestText(&builder, .{}, "Hi there", .{ .x = 0, .y = 50 }, 16, .{ 1, 1, 1, 1 });
    try testing.expect(result.missing);
    try testing.expect(result.advance.x > 0); // advance still spans the full run

    // Builder must only retain glyphs that are actually in the atlas; the
    // resulting blob must validate cleanly against the same snapshot.
    try testing.expect(builder.glyphCount() <= 2);
    var blob = try builder.finish();
    defer blob.deinit();
    try blob.validate();
}

test "TextBlobBuilder.append separates shape from placement and fill" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const first = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 30, .y = 40 }, .em = 20 },
        .fill = .{ .solid = .{ 0, 1, 0, 1 } },
    });

    try testing.expectApproxEqAbs(shaped.advance_x * 12, first.advance.x, 0.001);
    try testing.expectApproxEqAbs(shaped.advance_x * 20, second.advance.x, 0.001);
    try testing.expectEqual(@as(usize, 2), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expectApproxEqAbs(@as(f32, 10), blob.glyphs[0].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[0].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 12), blob.glyphs[0].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectApproxEqAbs(@as(f32, 30), blob.glyphs[1].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 40), blob.glyphs[1].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[1].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 0, 1, 0, 1 }, blob.glyphs[1].color);
}

test "TextBlobBuilder.append can style shaped glyph ranges independently" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "AB")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "AB");
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len >= 2);

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const first = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs[0..1] },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs[1..2] },
        .placement = .{ .baseline = .{ .x = 10 + first.advance.x, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 0, 0, 1, 1 } },
    });

    try testing.expect(first.advance.x > 0);
    try testing.expect(second.advance.x > 0);
    try testing.expectEqual(@as(usize, 2), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectEqual([4]f32{ 0, 0, 1, 1 }, blob.glyphs[1].color);
    try testing.expectApproxEqAbs(10 + first.advance.x, blob.glyphs[1].transform.tx, 0.001);
}

test "TextBlobBuilder.append stores gradient paint records" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    _ = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 10 },
        .fill = .{ .linear_gradient = .{
            .start = .{ .x = 10, .y = 20 },
            .end = .{ .x = 30, .y = 20 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
        } },
    });
    try testing.expectEqual(@as(usize, 1), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expect(blob.hasPaintRecords());
    try testing.expectEqual(@as(?u32, 0), blob.glyphs[0].paint_record_index);
    try testing.expectEqual([4]f32{ 1, 1, 1, 1 }, blob.glyphs[0].color);
    try testing.expectEqual(@as(u32, paint_records.texels_per_record), blob.paint_layer_info_width);
    try testing.expectEqual(@as(u32, 1), blob.paint_layer_info_height);

    const loc = blob.paintRecordLoc(0);
    try testing.expectEqual(@as(u16, 0), loc.x);
    try testing.expectEqual(@as(u16, 0), loc.y);
    const tag = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 0)[3];
    try testing.expectApproxEqAbs(paint_records.tag_linear_gradient, tag, 0.001);
    const coords = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 2);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2), coords[2], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[3], 0.001);
    try testing.expect(blob.paint_image_records == null);
}

test "TextBlobBuilder.append stores image paint records" {
    const assets_data = @import("assets");
    var image = try snail.Image.initSrgba8(testing.allocator, 1, 1, &.{ 255, 64, 32, 255 });
    defer image.deinit();
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    _ = try builder.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 4, .y = 8 }, .em = 2 },
        .fill = .{ .image = .{
            .image = &image,
            .uv_transform = snail.Transform2D.scale(0.25, 0.5),
        } },
    });

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expect(blob.hasPaintRecords());
    const records = blob.paint_image_records orelse return error.TestExpectedEqual;
    try testing.expectEqual(@as(usize, 1), records.len);
    try testing.expect(records[0].?.image == &image);
    try testing.expectEqual(@as(u32, 0), records[0].?.texel_offset);
    const tag = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 0)[3];
    try testing.expectApproxEqAbs(paint_records.tag_image, tag, 0.001);
    const data0 = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 2);
    const data1 = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 3);
    try testing.expectApproxEqAbs(@as(f32, 0.5), data0[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), data0[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1), data0[2], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), data1[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, -1), data1[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 4), data1[2], 0.001);
}

test "TextBlobBuilder stores hinted glyph records and emits hinted special vertices" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    const gid = (try fonts.glyphIndex(0, 'A')).?;
    const face_view = fonts.faceView(0, .{});
    const info = face_view.getGlyph(gid).?;
    const deltas = try testing.allocator.alloc(u16, @as(usize, info.curve_count) * text_hint_format.delta_values_per_curve);
    defer testing.allocator.free(deltas);
    @memset(deltas, 0);
    var hinted_value = snail.TrueTypeHintedGlyph{
        .key = .{ .face_index = 0, .ppem_x_26_6 = 12 * 64, .ppem_y_26_6 = 12 * 64, .glyph_id = gid },
        .advance = .{ .x = 1, .y = 0 },
        .bbox = info.bbox,
        .attachment = .{
            .record = .{
                .base_curve_texel = info.base_curve_texel,
                .curve_count = info.curve_count,
                .band_entry = info.band_entry,
                .bbox = info.bbox,
            },
            .curve_deltas_f16 = deltas,
        },
    };

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    try builder.appendHintedGlyphRef(0, gid, snail.Transform2D.scale(12, -12), .{ 0.2, 0.4, 0.6, 1 }, &hinted_value);
    try builder.appendHintedGlyphRef(0, gid, .{ .xx = 12, .yy = -12, .tx = 14, .ty = 0 }, .{ 0.2, 0.4, 0.6, 1 }, &hinted_value);

    var blob = try builder.finish();
    defer blob.deinit();
    const hint_texel = blob.glyphs[0].hint_record_texel orelse return error.TestExpectedEqual;
    try testing.expectEqual(hint_texel, blob.glyphs[1].hint_record_texel.?);
    const meta = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, hint_texel + 2);
    try testing.expectEqual(@as(?u32, null), blob.glyphs[0].paint_record_index);
    try testing.expectEqual(@as(f32, @floatFromInt(info.base_curve_texel)), meta[0]);
    try testing.expectEqual(@as(f32, @floatFromInt(info.curve_count)), meta[1]);

    var buf = [_]u32{0} ** (snail.TEXT_WORDS_PER_GLYPH * 2);
    var batch = TextBatch.init(&buf);
    const result = try batch.addDraw(.{}, .{
        .blob = &blob,
        .resources = blob.resourceKeys(snail.ResourceKey.named("fonts"), snail.ResourceKey.named("text")),
    }, 0, 0);

    try testing.expect(result.completed);
    try testing.expectEqual(@as(usize, 2), result.emitted);
    const packed_gw = vertex.decodeInstance(batch.slice()).glyph[1];
    try testing.expectEqual(render_abi.SpecialLayerKind.hinted_text, render_abi.specialGlyphWordKind(packed_gw).?);
}

test "TextBlobBuilder hint run keeps fallback glyphs" {
    const assets_data = @import("assets");
    const sample = "A \xf0\x9f\x9a\x80 B";
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.twemoji_mozilla, .fallback = true },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, sample)) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, sample);
    defer shaped.deinit();

    var context = snail.TrueTypeHintContext.init(testing.allocator, &fonts);
    defer context.deinit();
    var run = try context.prepareRun(testing.allocator, .{
        .shaped = &shaped,
        .ppem = snail.TrueTypeHintPpem.uniform(12 * 64),
    });
    defer run.deinit();

    try testing.expect(run.stats.hinted_count >= 2);
    try testing.expect(run.stats.fallback_count >= 1);

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    _ = try builder.append(.{
        .source = .{ .hinted = run.glyphs },
        .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
        .fill = .{ .solid = .{ 0.2, 0.4, 0.6, 1 } },
    });

    var blob = try builder.finish();
    defer blob.deinit();
    var hinted_glyphs: usize = 0;
    for (blob.glyphs) |glyph| {
        if (glyph.hint_record_texel != null) hinted_glyphs += 1;
    }
    try testing.expect(hinted_glyphs >= 2);
    try testing.expect(blob.glyphCount() > hinted_glyphs);
}

test "TextAtlas.lineMetrics returns primary face metrics" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const lm = try fonts.lineMetrics();
    try testing.expect(lm.ascent > 0);
    try testing.expect(lm.descent < 0);
}

test "TextAtlas exposes per-face metrics and cell metrics" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_bold, .weight = .bold },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(usize, 2), fonts.faceCount());
    try testing.expectEqual(@as(FaceIndex, 0), try fonts.primaryFaceIndex());

    const upem = try fonts.faceUnitsPerEm(0);
    try testing.expect(upem > 0);

    const gid = (try fonts.glyphIndex(0, 'M')).?;
    const advance = try fonts.advanceWidth(0, gid);
    try testing.expect(advance > 0);

    const metrics = try fonts.cellMetrics(.{ .style = .{}, .em = 16 });
    try testing.expect(metrics.cell_width > 0);
    try testing.expect(metrics.line_height > metrics.cell_width);
}

test "TextAtlas cell grid snaps terminal placements" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const pixel_step = snail.Vec2{ .x = 0.5, .y = 0.25 };
    const grid = try fonts.cellGrid(.{
        .origin = .{ .x = 1.11, .y = 2.13 },
        .em = 15.9,
        .pixel_step = pixel_step,
        .snap_rule = .nearest,
    });

    try testing.expectApproxEqAbs(snail.snapToStep(1.11, pixel_step.x, .nearest), grid.origin.x, 0.0001);
    try testing.expectApproxEqAbs(snail.snapToStep(2.13, pixel_step.y, .nearest), grid.origin.y, 0.0001);
    try testing.expectApproxEqAbs(snail.snapToStep(grid.cell_width, pixel_step.x, .nearest), grid.cell_width, 0.0001);
    try testing.expectApproxEqAbs(snail.snapToStep(grid.line_height, pixel_step.y, .nearest), grid.line_height, 0.0001);
    try testing.expectApproxEqAbs(snail.snapToStep(grid.baseline_offset, pixel_step.y, .nearest), grid.baseline_offset, 0.0001);

    const placement = grid.placement(3, 2);
    try testing.expectApproxEqAbs(grid.origin.x + grid.cell_width * 3, placement.baseline.x, 0.0001);
    try testing.expectApproxEqAbs(grid.origin.y + grid.line_height * 2 + grid.baseline_offset, placement.baseline.y, 0.0001);
    try testing.expectApproxEqAbs(grid.em, placement.em, 0.0001);
}

test "TextAtlas.ensureGlyphs extends by resolved glyph id" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const gid = (try fonts.glyphIndex(0, 'A')).?;
    var next = (try fonts.ensureGlyphs(0, &.{gid})).?;
    defer next.deinit();

    try testing.expect(next.pageCount() > fonts.pageCount());
    try testing.expectEqual(@as(?TextAtlas, null), try next.ensureGlyphs(0, &.{gid}));
}

test "TextBlob.rebound accepts atlas snapshots that retain referenced glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    _ = try appendTestText(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();

    var next = (try fonts.ensureText(.{}, "B")).?;
    defer next.deinit();

    var rebound = try blob.rebound(testing.allocator, &next);
    defer rebound.deinit();
    try rebound.validate();
}

test "TextBlob.rebound recomputes budget after ensureGlyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Prepare 'A' so the blob has a real entry to rebound. (Building a blob
    // against an empty atlas leaves it empty — `addText` skips missing
    // glyphs so the blob never references unrasterized GIDs.)
    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    _ = try appendTestText(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });

    var blob = try builder.finish();
    defer blob.deinit();
    const original_budget = blob.gpu_instance_budget;
    try testing.expect(original_budget > 0);

    // Extend the atlas with an unrelated glyph; rebound must still succeed
    // and the recomputed budget must remain valid against the new snapshot.
    const gid_b = (try fonts.glyphIndex(0, 'B')).?;
    var next = (try fonts.ensureGlyphs(0, &.{gid_b})).?;
    defer next.deinit();

    var rebound = try blob.rebound(testing.allocator, &next);
    defer rebound.deinit();
    try rebound.validate();
    try testing.expect(rebound.gpu_instance_budget > 0);
}

test "TextAtlas with multiple faces and fallback" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_arabic, .fallback = true },
    });
    defer fonts.deinit();

    // Arabic codepoint should resolve to the Arabic face (index 1).
    const face = fonts.resolve(.{}, 0x0645); // م
    try testing.expectEqual(@as(?FaceIndex, 1), face);

    // Latin codepoint should resolve to the primary face (index 0).
    const latin = fonts.resolve(.{}, 'A');
    try testing.expectEqual(@as(?FaceIndex, 0), latin);
}

test "TextAtlas deduplicates same font data" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    });
    defer fonts.deinit();

    // Both faces share the same parsed font (data pointer equality).
    try testing.expectEqual(fonts.config.faces[0].font.data.ptr, fonts.config.faces[1].font.data.ptr);
}
