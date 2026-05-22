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
const TextBlobBundle = snail.TextBlobBundle;
const BlobInProgress = snail.BlobInProgress;

const testing = std.testing;

fn appendTestText(
    bip: BlobInProgress,
    style: snail.FontStyle,
    text: []const u8,
    baseline: snail.Vec2,
    em: f32,
    color: [4]f32,
) !TextAppendResult {
    var shaped = try bip.bundle.atlas.shapeText(bip.bundle.gpa, style, text);
    defer shaped.deinit();
    return bip.append(.{
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
    try testing.expect(shaped.advanceX() > 0);

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

test "TextBlobBundle.append with partially-prepared atlas skips missing glyphs" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();

    const result = try appendTestText(bip, .{}, "Hi there", .{ .x = 0, .y = 50 }, 16, .{ 1, 1, 1, 1 });
    try testing.expect(result.missing);
    try testing.expect(result.advance.x > 0); // advance still spans the full run

    // Builder must only retain glyphs that are actually in the atlas; the
    // resulting blob must validate cleanly against the same snapshot.
    try testing.expect(bip.glyphCount() <= 2);
    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    try blob.validate();
}

test "TextBlobBundle.append separates shape from placement and fill" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();

    const first = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 30, .y = 40 }, .em = 20 },
        .fill = .{ .solid = .{ 0, 1, 0, 1 } },
    });

    try testing.expectApproxEqAbs(shaped.advanceX() * 12, first.advance.x, 0.001);
    try testing.expectApproxEqAbs(shaped.advanceX() * 20, second.advance.x, 0.001);
    try testing.expectEqual(@as(usize, 2), bip.glyphCount());

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    try testing.expectApproxEqAbs(@as(f32, 10), blob.glyphs[0].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[0].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 12), blob.glyphs[0].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectApproxEqAbs(@as(f32, 30), blob.glyphs[1].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 40), blob.glyphs[1].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[1].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 0, 1, 0, 1 }, blob.glyphs[1].color);
}

test "TextBlobBundle.append can style shaped glyph ranges independently" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();

    const first = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs[0..1] },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs[1..2] },
        .placement = .{ .baseline = .{ .x = 10 + first.advance.x, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 0, 0, 1, 1 } },
    });

    try testing.expect(first.advance.x > 0);
    try testing.expect(second.advance.x > 0);
    try testing.expectEqual(@as(usize, 2), bip.glyphCount());

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectEqual([4]f32{ 0, 0, 1, 1 }, blob.glyphs[1].color);
    try testing.expectApproxEqAbs(10 + first.advance.x, blob.glyphs[1].transform.tx, 0.001);
}

test "TextBlobBundle.append stores gradient paint records" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();

    _ = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 10 },
        .fill = .{ .linear_gradient = .{
            .start = .{ .x = 10, .y = 20 },
            .end = .{ .x = 30, .y = 20 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
        } },
    });
    try testing.expectEqual(@as(usize, 1), bip.glyphCount());

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
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

test "TextBlobBundle.append stores image paint records" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();

    _ = try bip.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 4, .y = 8 }, .em = 2 },
        .fill = .{ .image = .{
            .image = &image,
            .uv_transform = snail.Transform2D.scale(0.25, 0.5),
        } },
    });

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
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

test "TextBlobBundle stores hinted glyph records and emits hinted special vertices" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();
    try bip.appendHintedGlyphRef(0, gid, snail.Transform2D.scale(12, -12), .{ 0.2, 0.4, 0.6, 1 }, &hinted_value);
    try bip.appendHintedGlyphRef(0, gid, .{ .xx = 12, .yy = -12, .tx = 14, .ty = 0 }, .{ 0.2, 0.4, 0.6, 1 }, &hinted_value);

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    const hint_texel = blob.glyphs[0].hint_record_texel orelse return error.TestExpectedEqual;
    try testing.expectEqual(hint_texel, blob.glyphs[1].hint_record_texel.?);
    const meta = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, hint_texel + 2);
    try testing.expectEqual(@as(?u32, null), blob.glyphs[0].paint_record_index);
    try testing.expectEqual(@as(f32, @floatFromInt(info.base_curve_texel)), meta[0]);
    try testing.expectEqual(@as(f32, @floatFromInt(info.curve_count)), meta[1]);

    var buf = [_]u32{0} ** (snail.TEXT_WORDS_PER_GLYPH * 2);
    var batch = TextBatch.init(&buf);
    const result = try batch.addDraw(.{}, .{
        .blob = blob,
        .resources = blob.resourceKeys(snail.ResourceKey.named("fonts"), snail.ResourceKey.named("text")),
    }, 0, 0);

    try testing.expect(result.completed);
    try testing.expectEqual(@as(usize, 2), result.emitted);
    const packed_gw = vertex.decodeInstance(batch.slice()).glyph[1];
    try testing.expectEqual(render_abi.SpecialLayerKind.hinted_text, render_abi.specialGlyphWordKind(packed_gw).?);
}

test "TextBlobBundle hint run keeps fallback glyphs" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();
    _ = try bip.append(.{
        .source = .{ .hinted = run.glyphs },
        .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
        .fill = .{ .solid = .{ 0.2, 0.4, 0.6, 1 } },
    });

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    var hinted_glyphs: usize = 0;
    for (blob.glyphs) |glyph| {
        if (glyph.hint_record_texel != null) hinted_glyphs += 1;
    }
    try testing.expect(hinted_glyphs >= 2);
    try testing.expect(blob.glyphCount() > hinted_glyphs);
}

test "TextBlobBundle: streaming construction with abort/finish" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();
    if (try fonts.ensureText(.{}, "Hi")) |next| {
        fonts.deinit();
        fonts = next;
    }
    var shaped = try fonts.shapeText(testing.allocator, .{}, "Hi");
    defer shaped.deinit();

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    try testing.expectEqual(@as(usize, 0), bundle.blobCount());

    // Abort path: discard the in-progress blob, bundle stays empty.
    var bip0 = try bundle.startBlob();
    _ = try bip0.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 1, 1, 1 } },
    });
    try testing.expect(bip0.glyphCount() > 0);
    bip0.abort();
    try testing.expectEqual(@as(usize, 0), bundle.blobCount());

    // Finish path: produces a pointer-stable blob owned by the bundle.
    var bip1 = try bundle.startBlob();
    _ = try bip1.append(.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 1, 1, 1 } },
    });
    const blob = try bip1.finish(snail.ResourceKey.named("test_blob"));
    try testing.expectEqual(@as(usize, 1), bundle.blobCount());
    try testing.expect(blob.glyphCount() > 0);

    // Second in-flight start fails until previous one terminates.
    var bip2 = try bundle.startBlob();
    try testing.expectError(error.BlobInFlight, bundle.startBlob());
    bip2.abort();
}

test "TextBlobBundle: buildBlob bulk path with results" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();
    if (try fonts.ensureText(.{}, "Hi")) |next| {
        fonts.deinit();
        fonts = next;
    }
    var shaped = try fonts.shapeText(testing.allocator, .{}, "Hi");
    defer shaped.deinit();

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();

    var results: [2]TextAppendResult = undefined;
    const blob = try bundle.buildBlob(
        snail.ResourceKey.named("test_blob"),
        &.{
            .{
                .source = .{ .shaped = shaped.glyphs },
                .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
                .fill = .{ .solid = .{ 1, 0, 0, 1 } },
            },
            .{
                .source = .{ .shaped = shaped.glyphs },
                .placement = .{ .baseline = .{ .x = 0, .y = 24 }, .em = 12 },
                .fill = .{ .solid = .{ 0, 1, 0, 1 } },
            },
        },
        &results,
    );
    try testing.expect(blob.glyphCount() > 0);
    try testing.expect(results[0].advance.x > 0);
    try testing.expect(results[1].advance.x > 0);
}

test "TextBlobBundle: freeze blocks further construction; reset clears" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();

    _ = try bundle.buildBlob(snail.ResourceKey.named("k"), &.{
        .{
            .source = .{ .shaped = shaped.glyphs },
            .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
            .fill = .{ .solid = .{ 1, 1, 1, 1 } },
        },
    }, null);
    bundle.freeze();
    try testing.expect(bundle.isFrozen());
    try testing.expectError(error.BundleFrozen, bundle.startBlob());

    const before_gen = bundle.currentGeneration();
    bundle.reset();
    try testing.expect(!bundle.isFrozen());
    try testing.expectEqual(@as(usize, 0), bundle.blobCount());
    try testing.expect(bundle.currentGeneration() != before_gen);
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();
    _ = try appendTestText(bip, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });
    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));

    var next = (try fonts.ensureText(.{}, "B")).?;
    defer next.deinit();

    var rebound_bundle = snail.TextBlobBundle.init(testing.allocator, &next);
    defer rebound_bundle.deinit();
    const rebound = try rebound_bundle.rebound(snail.ResourceKey.named("rebound"), blob, &next);
    try rebound.validate();
}

test "TextBlobBundle.rebound recomputes budget after ensureGlyphs" {
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

    var bundle = snail.TextBlobBundle.init(testing.allocator, &fonts);
    defer bundle.deinit();
    var bip = try bundle.startBlob();
    errdefer bip.abort();
    _ = try appendTestText(bip, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });

    const blob = try bip.finish(snail.ResourceKey.named("test_blob"));
    const original_budget = blob.gpu_instance_budget;
    try testing.expect(original_budget > 0);

    // Extend the atlas with an unrelated glyph; rebound must still succeed
    // and the recomputed budget must remain valid against the new snapshot.
    const gid_b = (try fonts.glyphIndex(0, 'B')).?;
    var next = (try fonts.ensureGlyphs(0, &.{gid_b})).?;
    defer next.deinit();

    var rebound_bundle = snail.TextBlobBundle.init(testing.allocator, &next);
    defer rebound_bundle.deinit();
    const rebound = try rebound_bundle.rebound(snail.ResourceKey.named("rebound"), blob, &next);
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
fn makeGlyph(source_start: u32, source_end: u32, x_advance: f32) snail.ShapedText.Glyph {
    return .{
        .face_index = 0,
        .glyph_id = 1,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = x_advance,
        .y_advance = 0,
        .source_start = source_start,
        .source_end = source_end,
    };
}

fn shapedFromGlyphs(glyphs: []snail.ShapedText.Glyph) snail.ShapedText {
    return .{
        .allocator = testing.allocator,
        .config = undefined,
        .glyphs = glyphs,
    };
}

test "clusters: empty shaped text yields no clusters" {
    var glyphs = [_]snail.ShapedText.Glyph{};
    const shaped = shapedFromGlyphs(&glyphs);
    var it = snail.clusters(&shaped);
    try testing.expectEqual(@as(?snail.Cluster, null), it.next());
}

test "clusters: one glyph per cluster (plain Latin)" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 3, 0.5),
        makeGlyph(1, 3, 0.5),
        makeGlyph(2, 3, 0.5),
    };
    const shaped = shapedFromGlyphs(&glyphs);
    var it = snail.clusters(&shaped);

    const c0 = it.next().?;
    try testing.expectEqual(@as(usize, 1), c0.glyphs.len);
    try testing.expectEqual(@as(u32, 0), c0.source_start);
    try testing.expectEqual(@as(u32, 1), c0.source_end);

    const c1 = it.next().?;
    try testing.expectEqual(@as(usize, 1), c1.glyphs.len);
    try testing.expectEqual(@as(u32, 1), c1.source_start);
    try testing.expectEqual(@as(u32, 2), c1.source_end);

    const c2 = it.next().?;
    try testing.expectEqual(@as(usize, 1), c2.glyphs.len);
    try testing.expectEqual(@as(u32, 2), c2.source_start);
    // Final cluster: source_end falls back to glyph.source_end.
    try testing.expectEqual(@as(u32, 3), c2.source_end);

    try testing.expectEqual(@as(?snail.Cluster, null), it.next());
}

test "clusters: ligature collapses multiple glyphs into one cluster" {
    // HarfBuzz emits each ligature component with the same cluster index.
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 4, 0.7), // "ffi" ligature
        makeGlyph(0, 4, 0.0),
        makeGlyph(0, 4, 0.0),
        makeGlyph(3, 4, 0.4), // trailing "."
    };
    const shaped = shapedFromGlyphs(&glyphs);
    var it = snail.clusters(&shaped);

    const c0 = it.next().?;
    try testing.expectEqual(@as(usize, 3), c0.glyphs.len);
    try testing.expectEqual(@as(u32, 0), c0.source_start);
    try testing.expectEqual(@as(u32, 3), c0.source_end);

    const c1 = it.next().?;
    try testing.expectEqual(@as(usize, 1), c1.glyphs.len);
    try testing.expectEqual(@as(u32, 3), c1.source_start);
    try testing.expectEqual(@as(u32, 4), c1.source_end);

    try testing.expectEqual(@as(?snail.Cluster, null), it.next());
}

test "clusters: covers every glyph exactly once" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 5, 0.5),
        makeGlyph(0, 5, 0.0),
        makeGlyph(2, 5, 0.5),
        makeGlyph(3, 5, 0.5),
        makeGlyph(3, 5, 0.0),
        makeGlyph(3, 5, 0.0),
    };
    const shaped = shapedFromGlyphs(&glyphs);
    var it = snail.clusters(&shaped);

    var seen: usize = 0;
    while (it.next()) |c| seen += c.glyphs.len;
    try testing.expectEqual(glyphs.len, seen);
}

test "clusters: from real shapeText output, source spans are monotonic" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    var shaped = try fonts.shapeText(testing.allocator, .{}, "Hello");
    defer shaped.deinit();

    var it = snail.clusters(&shaped);
    var prev_start: ?u32 = null;
    var total: usize = 0;
    while (it.next()) |c| {
        try testing.expect(c.glyphs.len >= 1);
        try testing.expect(c.source_end > c.source_start);
        if (prev_start) |p| try testing.expect(c.source_start > p);
        prev_start = c.source_start;
        total += c.glyphs.len;
    }
    try testing.expectEqual(shaped.glyphs.len, total);
}

fn makeShapedForTransform(glyphs: []snail.ShapedText.Glyph) snail.ShapedText {
    return .{
        .allocator = testing.allocator,
        .config = undefined,
        .glyphs = glyphs,
    };
}

test "track: shifts subsequent clusters and bumps advance" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 3, 0.5),
        makeGlyph(1, 3, 0.5),
        makeGlyph(2, 3, 0.5),
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.track(&shaped, 0.1);

    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.1), shaped.glyphs[1].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.2), shaped.glyphs[2].x_offset, 1e-6);

    // Last glyph of each cluster gets the spacing baked into its x_advance.
    try testing.expectApproxEqAbs(@as(f32, 0.6), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), shaped.glyphs[2].x_advance, 1e-6);

    try testing.expectApproxEqAbs(@as(f32, 1.8), shaped.advanceX(), 1e-6);
}

test "track: preserves ligature internal layout" {
    var glyphs = [_]snail.ShapedText.Glyph{
        // "ffi" ligature: 3 glyphs in one cluster, only the first carries advance.
        .{
            .face_index = 0,
            .glyph_id = 1,
            .x_offset = 0.0,
            .y_offset = 0,
            .x_advance = 0.7,
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
        .{
            .face_index = 0,
            .glyph_id = 2,
            .x_offset = 0.2,
            .y_offset = 0,
            .x_advance = 0.0,
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
        .{
            .face_index = 0,
            .glyph_id = 3,
            .x_offset = 0.4,
            .y_offset = 0,
            .x_advance = 0.0,
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
        makeGlyph(3, 4, 0.5),
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.track(&shaped, 0.1);

    // Cluster 0: x_offsets unchanged (k=0).
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.2), shaped.glyphs[1].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.4), shaped.glyphs[2].x_offset, 1e-6);
    // Cluster 1: shifted by k=1.
    try testing.expectApproxEqAbs(@as(f32, 3.0 + 0.1 - 3.0), shaped.glyphs[3].x_offset, 1e-6);

    // Cluster-0 spacing is on its *last* glyph, not the first.
    try testing.expectApproxEqAbs(@as(f32, 0.7), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.1), shaped.glyphs[2].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), shaped.glyphs[3].x_advance, 1e-6);

    try testing.expectApproxEqAbs(@as(f32, 1.4), shaped.advanceX(), 1e-6);
}

test "track: zero em is a no-op" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 2, 0.5),
        makeGlyph(1, 2, 0.5),
    };
    const before = glyphs;
    var shaped = makeShapedForTransform(&glyphs);
    snail.track(&shaped, 0.0);
    try testing.expectEqualSlices(snail.ShapedText.Glyph, &before, shaped.glyphs);
    try testing.expectEqual(@as(f32, 1.0), shaped.advanceX());
}

test "track: empty input is a no-op" {
    var glyphs = [_]snail.ShapedText.Glyph{};
    var shaped = makeShapedForTransform(&glyphs);
    snail.track(&shaped, 0.1);
    try testing.expectEqual(@as(usize, 0), shaped.glyphs.len);
    try testing.expectEqual(@as(f32, 0.0), shaped.advanceX());
}

test "shiftBaseline: positive em moves glyphs up" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 2, 0.5),
        makeGlyph(1, 2, 0.5),
    };
    glyphs[0].y_offset = 0.0;
    glyphs[1].y_offset = 0.1;
    var shaped = makeShapedForTransform(&glyphs);
    snail.shiftBaseline(&shaped, 0.3);

    // y_offset convention: lower values render higher → +em subtracts.
    try testing.expectApproxEqAbs(@as(f32, -0.3), shaped.glyphs[0].y_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, -0.2), shaped.glyphs[1].y_offset, 1e-6);

    // Horizontal metrics untouched.
    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectEqual(@as(f32, 1.0), shaped.advanceX());
}

test "shiftBaseline: zero em is a no-op" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 1, 0.5),
    };
    glyphs[0].y_offset = 0.25;
    var shaped = makeShapedForTransform(&glyphs);
    snail.shiftBaseline(&shaped, 0.0);
    try testing.expectEqual(@as(f32, 0.25), shaped.glyphs[0].y_offset);
}

test "spaceWords: whitespace cluster expands, others untouched" {
    // Source: "a b" → 3 single-byte clusters at offsets 0, 1, 2.
    const source = "a b";
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 3, 0.5), // 'a'
        makeGlyph(1, 3, 0.3), // ' '
        makeGlyph(2, 3, 0.5), // 'b'
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.spaceWords(&shaped, source, 0.4);

    // x_offset: cluster 0 untouched, cluster 1 untouched (no space added before it),
    // cluster 2 shifted by 0.4 (the space's added em).
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[1].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.4), shaped.glyphs[2].x_offset, 1e-6);

    // x_advance: only the space cluster's last glyph grew.
    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.7), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[2].x_advance, 1e-6);

    try testing.expectApproxEqAbs(@as(f32, 1.7), shaped.advanceX(), 1e-6);
}

test "spaceWords: multiple whitespace clusters compound" {
    const source = "a  b";
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 4, 0.5),
        makeGlyph(1, 4, 0.3),
        makeGlyph(2, 4, 0.3),
        makeGlyph(3, 4, 0.5),
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.spaceWords(&shaped, source, 0.2);

    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[1].x_offset, 1e-6); // first ' '
    try testing.expectApproxEqAbs(@as(f32, 0.2), shaped.glyphs[2].x_offset, 1e-6); // second ' ' after one space added
    try testing.expectApproxEqAbs(@as(f32, 0.4), shaped.glyphs[3].x_offset, 1e-6); // 'b' after two spaces
    try testing.expectApproxEqAbs(@as(f32, 2.0), shaped.advanceX(), 1e-6);
}

test "spaceWords: zero em and empty input are no-ops" {
    const source = "a b";
    var glyphs1 = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 3, 0.5),
        makeGlyph(1, 3, 0.3),
        makeGlyph(2, 3, 0.5),
    };
    const before = glyphs1;
    var shaped1 = makeShapedForTransform(&glyphs1);
    snail.spaceWords(&shaped1, source, 0.0);
    try testing.expectEqualSlices(snail.ShapedText.Glyph, &before, shaped1.glyphs);

    var empty = [_]snail.ShapedText.Glyph{};
    var shaped2 = makeShapedForTransform(&empty);
    snail.spaceWords(&shaped2, source, 0.4);
    try testing.expectEqual(@as(usize, 0), shaped2.glyphs.len);
}

test "spaceWords: out-of-range source span is treated as non-whitespace" {
    const source = "ab";
    // Cluster claims source bytes [5..6] — outside source.
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(5, 6, 0.5),
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.spaceWords(&shaped, source, 0.4);
    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[0].x_advance, 1e-6);
}

test "snapAdvances: rounds each cluster advance to a multiple of step" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 3, 0.4), // rounds to 0.5
        makeGlyph(1, 3, 0.7), // rounds to 0.5
        makeGlyph(2, 3, 1.1), // rounds to 1.0
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.snapAdvances(&shaped, 0.5);

    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), shaped.glyphs[2].x_advance, 1e-6);

    // x_offsets shift by cumulative delta of preceding clusters.
    // Cluster 0 delta = +0.1 → cluster 1 shifts by 0.1.
    // Cluster 1 delta = -0.2 → cluster 2 shifts by 0.1 - 0.2 = -0.1.
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[0].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.1), shaped.glyphs[1].x_offset, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, -0.1), shaped.glyphs[2].x_offset, 1e-6);

    try testing.expectApproxEqAbs(@as(f32, 2.0), shaped.advanceX(), 1e-6);
}

test "snapAdvances: wide cluster rounds to multiple cells" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 2, 0.5), // narrow → 1 cell
        makeGlyph(1, 2, 1.9), // wide → 2 cells (2.0 step)
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.snapAdvances(&shaped, 1.0);

    try testing.expectApproxEqAbs(@as(f32, 1.0), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 2.0), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 3.0), shaped.advanceX(), 1e-6);
}

test "snapAdvances: distributes ligature delta to last glyph only" {
    var glyphs = [_]snail.ShapedText.Glyph{
        .{
            .face_index = 0,
            .glyph_id = 1,
            .x_offset = 0.0,
            .y_offset = 0,
            .x_advance = 0.7, // ligature cluster total 0.7+0+0 = 0.7 → snaps to 1.0
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
        .{
            .face_index = 0,
            .glyph_id = 2,
            .x_offset = 0.2,
            .y_offset = 0,
            .x_advance = 0.0,
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
        .{
            .face_index = 0,
            .glyph_id = 3,
            .x_offset = 0.4,
            .y_offset = 0,
            .x_advance = 0.0,
            .y_advance = 0,
            .source_start = 0,
            .source_end = 3,
        },
    };
    var shaped = makeShapedForTransform(&glyphs);
    snail.snapAdvances(&shaped, 1.0);

    // Delta = 0.3 added to last glyph of the ligature cluster.
    try testing.expectApproxEqAbs(@as(f32, 0.7), shaped.glyphs[0].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), shaped.glyphs[1].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.3), shaped.glyphs[2].x_advance, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), shaped.advanceX(), 1e-6);
}

test "snapAdvances: non-positive step is a no-op" {
    var glyphs = [_]snail.ShapedText.Glyph{
        makeGlyph(0, 2, 0.4),
        makeGlyph(1, 2, 0.7),
    };
    const before = glyphs;
    var shaped = makeShapedForTransform(&glyphs);
    snail.snapAdvances(&shaped, 0.0);
    try testing.expectEqualSlices(snail.ShapedText.Glyph, &before, shaped.glyphs);
    snail.snapAdvances(&shaped, -0.5);
    try testing.expectEqualSlices(snail.ShapedText.Glyph, &before, shaped.glyphs);
}

