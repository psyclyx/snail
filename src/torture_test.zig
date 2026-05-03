//! Torture test for valgrind: exercises the full CPU pipeline heavily.
//! No GPU needed — tests TextAtlas init, ensureText, addText,
//! batch generation, word wrapping, and shaped runs.

const std = @import("std");
const snail = @import("snail.zig");
const assets = @import("assets");

test "torture: full pipeline" {
    const allocator = std.testing.allocator;

    // Create TextAtlas with Latin face
    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer fonts.deinit();

    // Ensure ASCII glyphs are loaded
    const ascii_text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    if (try fonts.ensureText(.{}, ascii_text)) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    // Dynamic glyph loading: add extended Latin codepoints via ensureText
    const extended_text = "\u{00C0}\u{00C1}\u{00C2}\u{00C3}\u{00C4}\u{00C5}" ++ // À-Å
        "\u{00C6}\u{00C7}\u{00C8}\u{00C9}\u{00CA}\u{00CB}" ++ // Æ-Ë
        "\u{00E0}\u{00E1}\u{00E2}\u{00E3}\u{00E4}\u{00E5}" ++ // à-å
        "\u{00E6}\u{00E7}\u{00E8}\u{00E9}\u{00EA}\u{00EB}" ++ // æ-ë
        "\u{00F1}\u{00F6}\u{00FC}\u{00DF}"; // ñ, ö, ü, ß

    if (try fonts.ensureText(.{}, extended_text)) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
        try std.testing.expect(true);
    } else {
        try std.testing.expect(false);
    }

    // Adding same text again should be a no-op (returns null)
    const added2 = try fonts.ensureText(.{}, extended_text);
    try std.testing.expect(added2 == null);

    // Batch generation: large vertex buffer, many strings
    const buf_size = 10000 * snail.lowlevel.TEXT_WORDS_PER_GLYPH;
    const vbuf = try allocator.alloc(u32, buf_size);
    defer allocator.free(vbuf);

    var batch = snail.lowlevel.TextBatch.init(vbuf);

    // Render many strings at various sizes
    const test_strings = [_][]const u8{
        "The quick brown fox jumps over the lazy dog",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789",
        "abcdefghijklmnopqrstuvwxyz !@#$%^&*()",
        "fi fl ffi ffl office difficult",
        "Pack my box with five dozen liquor jugs",
        "How vexingly quick daft zebras jump",
    };

    // Ensure all test strings are in the atlas (including ligature contexts).
    for (test_strings) |s| {
        if (try fonts.ensureText(.{}, s)) |new_fonts| {
            fonts.deinit();
            fonts = new_fonts;
        }
    }

    var y: f32 = 1000;
    for ([_]f32{ 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96 }) |size| {
        for (test_strings) |s| {
            _ = try fonts.addText(&batch, .{}, s, 0, y, size, .{ 1, 1, 1, 1 });
            y -= size * 1.3;
        }
    }

    try std.testing.expect(batch.glyphCount() > 100);

    // Large text block
    batch.reset();
    const paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris " ++
        "nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in " ++
        "reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla " ++
        "pariatur. Excepteur sint occaecat cupidatat non proident, sunt in " ++
        "culpa qui officia deserunt mollit anim id est laborum.";

    if (try fonts.ensureText(.{}, paragraph)) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    _ = try fonts.addText(&batch, .{}, paragraph, 0, 800, 14, .{ 1, 1, 1, 1 });
    try std.testing.expect(batch.glyphCount() > 200);

    // Verify glyph coverage after ensureText.
    batch.reset();
    const result2 = try fonts.addText(&batch, .{}, "fi", 0, 100, 24, .{ 1, 0, 0, 1 });
    try std.testing.expect(!result2.missing);
    try std.testing.expect(batch.glyphCount() > 0);

    // Rebuild fonts from scratch (tests full deallocation + rebuild path)
    var fonts2 = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer fonts2.deinit();
    if (try fonts2.ensureText(.{}, "XYZ")) |new_fonts| {
        fonts2.deinit();
        fonts2 = new_fonts;
    }
    if (try fonts2.ensureText(.{}, "ABCDE")) |new_fonts| {
        fonts2.deinit();
        fonts2 = new_fonts;
    }
    if (try fonts2.ensureText(.{}, "abcde")) |new_fonts| {
        fonts2.deinit();
        fonts2 = new_fonts;
    }
}

test "ensureText is idempotent for already-loaded text" {
    const allocator = std.testing.allocator;

    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer fonts.deinit();

    // Load some text
    if (try fonts.ensureText(.{}, "ABC")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    // Extending with new codepoints should return a new snapshot
    const extended = try fonts.ensureText(.{}, "\u{00E9}\u{00F1}\u{00FC}");
    try std.testing.expect(extended != null);
    if (extended) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    // Re-extending with same text should be idempotent
    const again = try fonts.ensureText(.{}, "\u{00E9}\u{00F1}\u{00FC}");
    try std.testing.expect(again == null);
}

test "ensureText discovers shaped glyphs for UTF-8 text" {
    const allocator = std.testing.allocator;

    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer fonts.deinit();

    // ensureText should handle ligature discovery (e.g., fi -> fi ligature)
    if (try fonts.ensureText(.{}, "fi")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    // After ensureText, addText should emit glyphs successfully.
    var vbuf: [100 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&vbuf);
    const result = try fonts.addText(&batch, .{}, "fi", 0, 0, 24, .{ 1, 1, 1, 1 });
    try std.testing.expect(result.advance > 0);
    try std.testing.expect(batch.glyphCount() > 0);
}

test "addText reports missing glyphs" {
    const allocator = std.testing.allocator;

    // Create fonts without pre-loading any text
    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer fonts.deinit();

    // addText without ensureText should report missing glyphs
    var vbuf: [100 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&vbuf);
    const result = try fonts.addText(&batch, .{}, "Hello", 0, 0, 24, .{ 1, 1, 1, 1 });
    try std.testing.expect(result.missing);
}

test "multi-face fonts with fallback" {
    const allocator = std.testing.allocator;

    // Create fonts with Latin primary + Arabic fallback
    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
        .{ .data = assets.noto_sans_arabic, .fallback = true },
    });
    defer fonts.deinit();

    // Ensure both scripts are loaded
    const arabic_text = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87";
    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    if (try fonts.ensureText(.{}, arabic_text)) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var vbuf: [200 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&vbuf);

    // Both scripts should render successfully.
    const latin_result = try fonts.addText(&batch, .{}, "Hello", 0, 0, 24, .{ 1, 1, 1, 1 });
    try std.testing.expect(latin_result.advance > 0);
    try std.testing.expect(batch.glyphCount() > 0);

    const before = batch.glyphCount();
    const arabic_result = try fonts.addText(&batch, .{}, arabic_text, 0, 30, 24, .{ 1, 1, 1, 1 });
    try std.testing.expect(arabic_result.advance > 0);
    try std.testing.expect(batch.glyphCount() > before);
}
