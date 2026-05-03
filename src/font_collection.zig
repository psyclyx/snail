const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");

const Font = snail.Font;
const Atlas = snail.Atlas;
const AtlasHandle = snail.AtlasHandle;
const ShapedRun = snail.ShapedRun;
const TextBatch = snail.TextBatch;
const FontStyle = snail.FontStyle;
const FontWeight = snail.FontWeight;
const SyntheticStyle = snail.SyntheticStyle;
const LineMetrics = snail.LineMetrics;
const DecorationMetrics = snail.DecorationMetrics;
const ScriptMetrics = snail.ScriptMetrics;
const Rect = snail.Rect;
const Allocator = std.mem.Allocator;

pub const FontCollection = struct {
    allocator: Allocator,
    faces: std.ArrayListUnmanaged(FaceEntry),
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: std.ArrayListUnmanaged(FaceIndex),
    primary_face: ?FaceIndex,
    atlas_list: std.ArrayListUnmanaged(*Atlas),
    atlas_index_map: std.AutoHashMapUnmanaged(*Atlas, u16),

    pub const FaceIndex = u16;

    const FaceEntry = struct {
        font: *const Font,
        atlas: *Atlas,
        handle: AtlasHandle,
        synthetic: SyntheticStyle,
    };

    pub const Face = struct {
        font: *const Font,
        atlas: *Atlas,
        handle: AtlasHandle,
        synthetic: SyntheticStyle,
    };

    pub const ItemizedRun = struct {
        face_index: FaceIndex,
        text_start: u32,
        text_end: u32,
    };

    /// Pixel-space position and size for superscript or subscript text.
    pub const ScriptTransform = struct {
        x: f32,
        y: f32,
        font_size: f32,
    };

    pub const Decoration = enum {
        underline,
        strikethrough,
    };

    pub fn init(allocator: Allocator) FontCollection {
        return .{
            .allocator = allocator,
            .faces = .empty,
            .style_chains = .empty,
            .global_chain = .empty,
            .primary_face = null,
            .atlas_list = .empty,
            .atlas_index_map = .empty,
        };
    }

    pub fn deinit(self: *FontCollection) void {
        self.faces.deinit(self.allocator);
        var it = self.style_chains.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.style_chains.deinit(self.allocator);
        self.global_chain.deinit(self.allocator);
        self.atlas_list.deinit(self.allocator);
        self.atlas_index_map.deinit(self.allocator);
    }

    /// Register a font+atlas for a style. Call order within a style = fallback priority.
    /// The collection borrows the font and atlas pointers — caller owns their lifetimes.
    pub fn addFace(
        self: *FontCollection,
        style: FontStyle,
        font: *const Font,
        atlas: *Atlas,
        synthetic: SyntheticStyle,
    ) !FaceIndex {
        const idx: FaceIndex = @intCast(self.faces.items.len);
        try self.faces.append(self.allocator, .{
            .font = font,
            .atlas = atlas,
            .handle = .{ .atlas = atlas },
            .synthetic = synthetic,
        });

        const key = packStyle(style);
        const gop = try self.style_chains.getOrPut(self.allocator, key);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(self.allocator, idx);

        if (self.primary_face == null and style.weight == .regular and !style.italic) {
            self.primary_face = idx;
        }

        try self.trackAtlas(atlas);
        return idx;
    }

    /// Register a global fallback (all styles). Checked after style-specific chains.
    pub fn addFallback(
        self: *FontCollection,
        font: *const Font,
        atlas: *Atlas,
        synthetic: SyntheticStyle,
    ) !FaceIndex {
        const idx: FaceIndex = @intCast(self.faces.items.len);
        try self.faces.append(self.allocator, .{
            .font = font,
            .atlas = atlas,
            .handle = .{ .atlas = atlas },
            .synthetic = synthetic,
        });

        try self.global_chain.append(self.allocator, idx);

        if (self.primary_face == null) {
            self.primary_face = idx;
        }

        try self.trackAtlas(atlas);
        return idx;
    }

    fn trackAtlas(self: *FontCollection, atlas: *Atlas) !void {
        const gop = try self.atlas_index_map.getOrPut(self.allocator, atlas);
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(self.atlas_list.items.len);
            try self.atlas_list.append(self.allocator, atlas);
        }
    }

    // --- GPU upload helpers ---

    /// All unique atlases in registration order (deduplicated).
    /// Pass to renderer.uploadAtlases().
    pub fn atlasSlice(self: *const FontCollection) []*Atlas {
        return self.atlas_list.items;
    }

    /// Store AtlasHandles after GPU upload. Must match atlasSlice() order and length.
    pub fn setAtlasHandles(self: *FontCollection, handles: []const AtlasHandle) void {
        for (self.faces.items) |*fe| {
            if (self.atlas_index_map.get(fe.atlas)) |ai| {
                fe.handle = handles[ai];
            }
        }
    }

    // --- Resolution ---

    /// Resolve a single codepoint to a face.
    /// Search: style chain → global fallbacks → style degradation → null.
    pub fn resolve(self: *const FontCollection, style: FontStyle, codepoint: u21) ?FaceIndex {
        return self.resolveInner(style, codepoint, 0);
    }

    fn resolveInner(self: *const FontCollection, style: FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
        if (depth > 3) return null;

        // 1. Style-specific chain
        if (self.style_chains.get(packStyle(style))) |chain| {
            for (chain.items) |fi| {
                if (self.fontHasGlyph(fi, codepoint)) return fi;
            }
        }

        // 2. Global fallbacks
        for (self.global_chain.items) |fi| {
            if (self.fontHasGlyph(fi, codepoint)) return fi;
        }

        // 3. Style degradation
        const next_depth = depth + 1;
        if (style.italic and style.weight != .regular) {
            // bold-italic → bold → italic → regular
            if (self.resolveInner(.{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
            if (self.resolveInner(.{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
            return self.resolveInner(.{ .weight = .regular, .italic = false }, codepoint, next_depth);
        } else if (style.italic) {
            return self.resolveInner(.{ .weight = .regular, .italic = false }, codepoint, next_depth);
        } else if (style.weight != .regular) {
            return self.resolveInner(.{ .weight = .regular, .italic = false }, codepoint, next_depth);
        }

        return null;
    }

    fn fontHasGlyph(self: *const FontCollection, fi: FaceIndex, codepoint: u21) bool {
        const gid = self.faces.items[fi].font.glyphIndex(codepoint) catch return false;
        return gid != 0;
    }

    /// Split text into maximal contiguous runs where each run resolves to one font.
    /// Caller owns the returned slice (free with the same allocator).
    pub fn itemize(
        self: *const FontCollection,
        style: FontStyle,
        text: []const u8,
        allocator: Allocator,
    ) ![]ItemizedRun {
        var runs = std.ArrayListUnmanaged(ItemizedRun).empty;
        errdefer runs.deinit(allocator);

        var byte_offset: u32 = 0;
        var current_face: ?FaceIndex = null;
        var run_start: u32 = 0;

        var i: usize = 0;
        while (i < text.len) {
            const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
                i += 1;
                byte_offset += 1;
                continue;
            };
            if (i + cp_len > text.len) break;

            const cp: u21 = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
                i += cp_len;
                byte_offset += @intCast(cp_len);
                continue;
            };

            const face_idx = self.resolve(style, cp) orelse
            // No font covers this codepoint — assign to first face or skip
                if (self.primary_face) |pf| pf else {
                i += cp_len;
                byte_offset += @intCast(cp_len);
                continue;
            };

            if (current_face == null) {
                current_face = face_idx;
                run_start = byte_offset;
            } else if (current_face.? != face_idx) {
                try runs.append(allocator, .{
                    .face_index = current_face.?,
                    .text_start = run_start,
                    .text_end = byte_offset,
                });
                current_face = face_idx;
                run_start = byte_offset;
            }

            i += cp_len;
            byte_offset += @intCast(cp_len);
        }

        // Flush final run
        if (current_face) |cf| {
            try runs.append(allocator, .{
                .face_index = cf,
                .text_start = run_start,
                .text_end = byte_offset,
            });
        }

        return runs.toOwnedSlice(allocator);
    }

    /// Look up a face by index.
    pub fn face(self: *const FontCollection, index: FaceIndex) Face {
        const fe = self.faces.items[index];
        return .{
            .font = fe.font,
            .atlas = fe.atlas,
            .handle = fe.handle,
            .synthetic = fe.synthetic,
        };
    }

    // --- Metrics ---

    /// Line metrics from the primary (first regular-weight) face.
    /// Use for consistent line spacing across all faces and styles.
    pub fn lineMetrics(self: *const FontCollection) !LineMetrics {
        const pf = self.primary_face orelse return error.NoFaces;
        return self.faces.items[pf].font.lineMetrics();
    }

    /// Units-per-em from the primary face.
    pub fn unitsPerEm(self: *const FontCollection) !u16 {
        const pf = self.primary_face orelse return error.NoFaces;
        return self.faces.items[pf].font.unitsPerEm();
    }

    /// Decoration metrics from the primary face.
    pub fn decorationMetrics(self: *const FontCollection) !DecorationMetrics {
        const pf = self.primary_face orelse return error.NoFaces;
        return self.faces.items[pf].font.decorationMetrics();
    }

    // --- Decoration & script helpers ---

    /// Compute a decoration rectangle spanning text at baseline (x, y) with
    /// the given advance width. Metrics come from the primary face, so the
    /// decoration is stable regardless of which fallback fonts the interior
    /// glyphs resolved to.
    pub fn decorationRect(self: *const FontCollection, decoration: Decoration, x: f32, y: f32, advance: f32, font_size: f32) !Rect {
        const dm = try self.decorationMetrics();
        const upem = try self.unitsPerEm();
        const scale = font_size / @as(f32, @floatFromInt(upem));
        return switch (decoration) {
            .underline => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.underline_position)) * scale,
                .w = advance,
                .h = @abs(@as(f32, @floatFromInt(dm.underline_thickness))) * scale,
            },
            .strikethrough => blk: {
                const thickness = @abs(@as(f32, @floatFromInt(dm.strikethrough_thickness))) * scale;
                const pos = @as(f32, @floatFromInt(dm.strikethrough_position)) * scale;
                break :blk .{
                    .x = x,
                    .y = y - pos - thickness * 0.5,
                    .w = advance,
                    .h = thickness,
                };
            },
        };
    }

    /// Compute adjusted position and size for superscript text.
    pub fn superscriptTransform(self: *const FontCollection, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.primary_face orelse return error.NoFaces;
        const fe = self.faces.items[pf];
        const sm = try fe.font.superscriptMetrics();
        const upem = fe.font.unitsPerEm();
        const upem_f = @as(f32, @floatFromInt(upem));
        const scale = font_size / upem_f;
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y - @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = font_size * @as(f32, @floatFromInt(sm.y_size)) / upem_f,
        };
    }

    /// Compute adjusted position and size for subscript text.
    pub fn subscriptTransform(self: *const FontCollection, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.primary_face orelse return error.NoFaces;
        const fe = self.faces.items[pf];
        const sm = try fe.font.subscriptMetrics();
        const upem = fe.font.unitsPerEm();
        const upem_f = @as(f32, @floatFromInt(upem));
        const scale = font_size / upem_f;
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y + @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = font_size * @as(f32, @floatFromInt(sm.y_size)) / upem_f,
        };
    }

    // --- Convenience ---

    pub const AddTextResult = struct {
        advance: f32,
        missing: bool,
    };

    /// Itemize + shape + emit in one call. Applies synthetic transforms.
    /// Returns advance width and whether any glyphs were missing from their atlas.
    /// When `missing` is true the caller can extend the relevant atlases
    /// (e.g. via `ensureGlyphs`) and redraw.
    pub fn addText(
        self: *const FontCollection,
        batch: *TextBatch,
        style: FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
        allocator: Allocator,
    ) !AddTextResult {
        const runs = try self.itemize(style, text, allocator);
        defer allocator.free(runs);

        var cx = x;
        var missing = false;
        for (runs) |run| {
            const fe = self.faces.items[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (self.runHasMissingGlyphs(fe, segment))
                missing = true;

            const has_synthetic = fe.synthetic.skew_x != 0 or fe.synthetic.embolden != 0;

            if (!has_synthetic) {
                // Use TextBatch.addText which has the HarfBuzz fast path for
                // complex scripts (Arabic, Devanagari, etc.).
                cx += batch.addText(&fe.handle, fe.font, segment, cx, y, font_size, color);
            } else {
                // Synthetic transforms require shapeUtf8 + addStyledRun.
                const shaped = try fe.handle.atlas.shapeUtf8(fe.font, segment, font_size, allocator);
                defer allocator.free(shaped.glyphs);
                _ = batch.addStyledRun(&fe.handle, &shaped, cx, y, font_size, color, fe.synthetic);
                cx += shaped.advance_x;
            }
        }

        return .{ .advance = cx - x, .missing = missing };
    }

    /// Extend all relevant atlases so that `text` can be rendered without missing glyphs.
    /// Returns true if any atlas was extended (caller should re-upload and redraw).
    pub fn ensureGlyphs(self: *const FontCollection, style: FontStyle, text: []const u8, allocator: Allocator) !bool {
        const runs = try self.itemize(style, text, allocator);
        defer allocator.free(runs);

        var extended = false;
        for (runs) |run| {
            const fe = self.faces.items[run.face_index];
            const segment = text[run.text_start..run.text_end];
            if (snail.replaceAtlas(fe.atlas, try fe.atlas.extendText(segment)))
                extended = true;
        }
        return extended;
    }

    /// Measure the advance width of styled text without emitting vertices.
    pub fn measureText(
        self: *const FontCollection,
        style: FontStyle,
        text: []const u8,
        font_size: f32,
        allocator: Allocator,
    ) !f32 {
        const runs = try self.itemize(style, text, allocator);
        defer allocator.free(runs);

        var width: f32 = 0;
        for (runs) |run| {
            const fe = self.faces.items[run.face_index];
            const segment = text[run.text_start..run.text_end];
            const shaped = try fe.handle.atlas.shapeUtf8(fe.font, segment, font_size, allocator);
            defer allocator.free(shaped.glyphs);
            width += shaped.advance_x;
        }
        return width;
    }

    // --- Internal ---

    /// Check whether any codepoint in `segment` maps to a glyph missing from
    /// the face's atlas.  Cheap: cmap lookup + hash probe per codepoint.
    fn runHasMissingGlyphs(self: *const FontCollection, fe: FaceEntry, segment: []const u8) bool {
        _ = self;
        const atlas = fe.handle.atlas;
        const font = fe.font;
        var i: usize = 0;
        while (i < segment.len) {
            const cp_len = std.unicode.utf8ByteSequenceLength(segment[i]) catch {
                i += 1;
                continue;
            };
            if (i + cp_len > segment.len) break;
            const cp: u21 = std.unicode.utf8Decode(segment[i..][0..cp_len]) catch {
                i += cp_len;
                continue;
            };
            i += cp_len;
            if (!snail.isRenderableTextCodepoint(cp)) continue;
            const gid = font.glyphIndex(cp) catch continue;
            if (gid == 0) continue;
            const in_base_map = if (atlas.colr_base_map) |cbm| cbm.contains(gid) else false;
            if (atlas.getGlyph(gid) == null and !in_base_map)
                return true;
        }
        return false;
    }

    fn packStyle(style: FontStyle) u8 {
        return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
    }
};

// ── Tests ──

const testing = std.testing;

test "addFace registers faces and tracks primary" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    const idx = try fc.addFace(.{}, &font, &atlas, .{});
    try testing.expectEqual(@as(FontCollection.FaceIndex, 0), idx);
    try testing.expectEqual(@as(?FontCollection.FaceIndex, 0), fc.primary_face);

    // Second face for bold — primary stays the first regular
    const idx2 = try fc.addFace(.{ .weight = .bold }, &font, &atlas, .{});
    try testing.expectEqual(@as(FontCollection.FaceIndex, 1), idx2);
    try testing.expectEqual(@as(?FontCollection.FaceIndex, 0), fc.primary_face);
}

test "atlasSlice deduplicates shared atlases" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    // Regular and synthetic italic share the same atlas
    _ = try fc.addFace(.{}, &font, &atlas, .{});
    _ = try fc.addFace(.{ .italic = true }, &font, &atlas, .{ .skew_x = 0.2 });

    try testing.expectEqual(@as(usize, 1), fc.atlasSlice().len);
}

test "resolve finds glyph in style chain" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    const reg_idx = try fc.addFace(.{}, &font, &atlas, .{});

    // ASCII 'A' should resolve to the regular face
    const resolved = fc.resolve(.{}, 'A');
    try testing.expectEqual(@as(?FontCollection.FaceIndex, reg_idx), resolved);
}

test "resolve falls back across styles" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    const reg_idx = try fc.addFace(.{}, &font, &atlas, .{});

    // Request bold — no bold face registered, should degrade to regular
    const resolved = fc.resolve(.{ .weight = .bold }, 'A');
    try testing.expectEqual(@as(?FontCollection.FaceIndex, reg_idx), resolved);

    // Request bold-italic — should also degrade to regular
    const resolved2 = fc.resolve(.{ .weight = .bold, .italic = true }, 'A');
    try testing.expectEqual(@as(?FontCollection.FaceIndex, reg_idx), resolved2);
}

test "resolve uses global fallback" {
    const assets = @import("assets");
    var latin_font = try Font.init(assets.noto_sans_regular);
    var arabic_font = try Font.init(assets.noto_sans_arabic);

    var latin_atlas = try Atlas.init(testing.allocator, &latin_font, &.{});
    defer latin_atlas.deinit();
    var arabic_atlas = try Atlas.init(testing.allocator, &arabic_font, &.{});
    defer arabic_atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    _ = try fc.addFace(.{}, &latin_font, &latin_atlas, .{});
    const arabic_idx = try fc.addFallback(&arabic_font, &arabic_atlas, .{});

    // Arabic character U+0627 (Alef) — not in NotoSans-Regular, should fall back to Arabic font
    const resolved = fc.resolve(.{}, 0x0627);
    try testing.expectEqual(@as(?FontCollection.FaceIndex, arabic_idx), resolved);
}

test "itemize splits text by font coverage" {
    const assets = @import("assets");
    var latin_font = try Font.init(assets.noto_sans_regular);
    var arabic_font = try Font.init(assets.noto_sans_arabic);

    var latin_atlas = try Atlas.init(testing.allocator, &latin_font, &.{});
    defer latin_atlas.deinit();
    var arabic_atlas = try Atlas.init(testing.allocator, &arabic_font, &.{});
    defer arabic_atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    const latin_idx = try fc.addFace(.{}, &latin_font, &latin_atlas, .{});
    const arabic_idx = try fc.addFallback(&arabic_font, &arabic_atlas, .{});

    // "Hi" (Latin) + U+0627 U+0628 (Arabic Alef Ba)
    const text = "Hi\xD8\xA7\xD8\xA8";
    const runs = try fc.itemize(.{}, text, testing.allocator);
    defer testing.allocator.free(runs);

    try testing.expectEqual(@as(usize, 2), runs.len);
    try testing.expectEqual(latin_idx, runs[0].face_index);
    try testing.expectEqual(@as(u32, 0), runs[0].text_start);
    try testing.expectEqual(@as(u32, 2), runs[0].text_end);
    try testing.expectEqual(arabic_idx, runs[1].face_index);
    try testing.expectEqual(@as(u32, 2), runs[1].text_start);
    try testing.expectEqual(@as(u32, 6), runs[1].text_end);
}

test "lineMetrics returns primary face metrics" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    _ = try fc.addFace(.{}, &font, &atlas, .{});

    const fc_metrics = try fc.lineMetrics();
    const font_metrics = try font.lineMetrics();
    try testing.expectEqual(font_metrics.ascent, fc_metrics.ascent);
    try testing.expectEqual(font_metrics.descent, fc_metrics.descent);
}

test "decorationRect returns valid geometry" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    _ = try fc.addFace(.{}, &font, &atlas, .{});

    const ul = try fc.decorationRect(.underline, 10, 100, 200, 24);
    try testing.expect(ul.w == 200);
    try testing.expect(ul.h > 0); // thickness should be positive
    try testing.expect(ul.y > 100); // below baseline (screen Y-down, underline_position is negative)

    const st = try fc.decorationRect(.strikethrough, 10, 100, 200, 24);
    try testing.expect(st.w == 200);
    try testing.expect(st.h > 0);
    try testing.expect(st.y < 100); // above baseline
}

test "superscript and subscript transforms" {
    const assets = @import("assets");
    var font = try Font.init(assets.noto_sans_regular);

    var atlas = try Atlas.init(testing.allocator, &font, &.{});
    defer atlas.deinit();

    var fc = FontCollection.init(testing.allocator);
    defer fc.deinit();

    _ = try fc.addFace(.{}, &font, &atlas, .{});

    const sup = try fc.superscriptTransform(100, 200, 24);
    try testing.expect(sup.font_size < 24); // smaller
    try testing.expect(sup.y < 200); // above baseline (screen Y-down)

    const sub = try fc.subscriptTransform(100, 200, 24);
    try testing.expect(sub.font_size < 24); // smaller
    try testing.expect(sub.y > 200); // below baseline
}
