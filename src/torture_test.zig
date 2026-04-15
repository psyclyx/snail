//! Torture test for valgrind: exercises the full CPU pipeline heavily.
//! No GPU needed — tests font parsing, atlas building, dynamic loading,
//! .snail roundtrip, batch generation, word wrapping, and ligatures.

const std = @import("std");
const snail = @import("snail.zig");
const snail_file = @import("font/snail_file.zig");
const assets = @import("assets");

test "torture: full pipeline" {
    const allocator = std.testing.allocator;

    // Parse font
    var font = try snail.Font.init(assets.noto_sans_regular);
    defer font.deinit();

    // Build atlas with ASCII printable set
    var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    const initial_count = atlas.glyph_map.count();
    try std.testing.expect(initial_count > 0);

    // Dynamic glyph loading: add some extended Latin codepoints
    const extended = [_]u32{
        0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, // À-Å
        0x00C6, 0x00C7, 0x00C8, 0x00C9, 0x00CA, 0x00CB, // Æ-Ë
        0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, // à-å
        0x00E6, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, // æ-ë
        0x00F1, 0x00F6, 0x00FC, 0x00DF, // ñ, ö, ü, ß
    };
    const added = try atlas.addCodepoints(&extended);
    try std.testing.expect(added);
    try std.testing.expect(atlas.glyph_map.count() > initial_count);

    // Adding same codepoints again should be a no-op
    const added2 = try atlas.addCodepoints(&extended);
    try std.testing.expect(!added2);

    // .snail roundtrip
    const serialized = try snail_file.serialize(allocator, &atlas, font.unitsPerEm());
    defer allocator.free(serialized);

    var loaded = try snail_file.load(allocator, serialized);
    defer loaded.deinit();
    try std.testing.expectEqual(atlas.glyph_map.count(), loaded.glyph_map.count());

    // Batch generation: large vertex buffer, many strings
    const buf_size = 10000 * snail.FLOATS_PER_GLYPH;
    const vbuf = try allocator.alloc(f32, buf_size);
    defer allocator.free(vbuf);

    var batch = snail.Batch.init(vbuf);

    // Render many strings at various sizes
    const test_strings = [_][]const u8{
        "The quick brown fox jumps over the lazy dog",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789",
        "abcdefghijklmnopqrstuvwxyz !@#$%^&*()",
        "fi fl ffi ffl office difficult",
        "Pack my box with five dozen liquor jugs",
        "How vexingly quick daft zebras jump",
    };

    var y: f32 = 1000;
    for ([_]f32{ 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96 }) |size| {
        for (test_strings) |s| {
            _ = batch.addString(&atlas, &font, s, 0, y, size, .{ 1, 1, 1, 1 });
            y -= size * 1.3;
        }
    }

    try std.testing.expect(batch.glyphCount() > 100);

    // Word wrapping
    batch.reset();
    const paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris " ++
        "nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in " ++
        "reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla " ++
        "pariatur. Excepteur sint occaecat cupidatat non proident, sunt in " ++
        "culpa qui officia deserunt mollit anim id est laborum.";

    const height = batch.addStringWrapped(&atlas, &font, paragraph, 0, 800, 14, 600, 20, .{ 1, 1, 1, 1 });
    try std.testing.expect(height > 0);
    try std.testing.expect(batch.glyphCount() > 200);

    // Pre-shaped glyph API
    batch.reset();
    const f_gid = try font.glyphIndex('f');
    const i_gid = try font.glyphIndex('i');
    const shaped = [_]snail.Batch.ShapedGlyph{
        .{ .glyph_id = f_gid, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = i_gid, .x_offset = 10, .y_offset = 0 },
        .{ .glyph_id = f_gid, .x_offset = 20, .y_offset = 0 },
        .{ .glyph_id = i_gid, .x_offset = 30, .y_offset = 0 },
    };
    const shaped_count = batch.addShaped(&atlas, &shaped, 100, 200, 24, .{ 1, 0, 0, 1 });
    try std.testing.expectEqual(@as(usize, 4), shaped_count);

    // Rebuild atlas from scratch (tests full deallocation + rebuild path)
    var atlas2 = try snail.Atlas.init(allocator, &font, &[_]u32{ 'X', 'Y', 'Z' });
    defer atlas2.deinit();
    _ = try atlas2.addCodepoints(&[_]u32{ 'A', 'B', 'C', 'D', 'E' });
    _ = try atlas2.addCodepoints(&[_]u32{ 'a', 'b', 'c', 'd', 'e' });
}
