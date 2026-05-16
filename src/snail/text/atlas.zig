const std = @import("std");

const snail = @import("../root.zig");
const glyph_emit = @import("../glyph_emit.zig");
const atlas_curve_mod = @import("../renderer/atlas/curve.zig");
const atlas_page_mod = @import("../renderer/atlas/page.zig");
const config_mod = @import("config.zig");
const shape_mod = @import("shape.zig");
const types_mod = @import("types.zig");
const view_mod = @import("view.zig");

const Allocator = std.mem.Allocator;
const CurveAtlas = atlas_curve_mod.CurveAtlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const GlyphInfo = CurveAtlas.GlyphInfo;
const TextBatch = snail.TextBatch;
const CellMetrics = types_mod.CellMetrics;
const CellMetricsOptions = types_mod.CellMetricsOptions;
const Decoration = types_mod.Decoration;
const FaceConfig = config_mod.FaceConfig;
const FaceGlyphData = config_mod.FaceGlyphData;
const FaceIndex = config_mod.FaceIndex;
const FaceSpec = config_mod.FaceSpec;
const FaceView = view_mod.FaceView;
const FontConfig = config_mod.FontConfig;
const ItemizedRun = config_mod.ItemizedRun;
const ScriptTransform = types_mod.ScriptTransform;
const ShapedText = types_mod.ShapedText;
const TextAppendResult = types_mod.TextAppendResult;
const TextBatchAppend = types_mod.TextBatchAppend;
const buildFontConfig = config_mod.buildFontConfig;
const glyphIndexForCellMetrics = config_mod.glyphIndexForCellMetrics;
const glyphPlacementTransform = shape_mod.glyphPlacementTransform;
const itemizeText = config_mod.itemizeText;
const resolveInner = config_mod.resolveInner;
const scaleAdvance = shape_mod.scaleAdvance;
const shapeRunForFace = shape_mod.shapeRunForFace;
const shapedAdvanceForRange = shape_mod.shapedAdvanceForRange;
const shapedGlyphAvailable = shape_mod.shapedGlyphAvailable;
const shapedPenAt = shape_mod.shapedPenAt;
const preparedViewInfoRowBase = view_mod.preparedViewInfoRowBase;
const preparedViewLayerBase = view_mod.preparedViewLayerBase;
const preparedViewPageLayers = view_mod.preparedViewPageLayers;

// ── TextAtlas ──

/// Multi-font text rendering with immutable snapshot semantics.
///
/// Create with `init`, populate glyphs with `ensureText`, render with `addText`.
/// All rendering methods are read-only and safe for concurrent use.
/// `ensureText` returns a new snapshot; the old one remains valid.
pub const TextAtlas = struct {
    allocator: Allocator,
    config: *FontConfig,
    pages: []*AtlasPage,
    face_glyphs: []FaceGlyphData,

    // Merged COLR layer info across all faces.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,

    pub fn init(allocator: Allocator, specs: []const FaceSpec) !TextAtlas {
        const config = try buildFontConfig(allocator, specs);
        errdefer config.release();

        const face_glyphs = try allocator.alloc(FaceGlyphData, config.faces.len);
        for (face_glyphs) |*fg| {
            fg.* = .{ .glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator) };
        }

        const pages = try allocator.alloc(*AtlasPage, 0);

        return .{
            .allocator = allocator,
            .config = config,
            .pages = pages,
            .face_glyphs = face_glyphs,
        };
    }

    pub fn snapshotIdentity(self: *const TextAtlas) u64 {
        var h: u64 = 0x9e3779b97f4a7c15;
        h ^= @as(u64, @intCast(@intFromPtr(self.config))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.pages.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.pages.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.face_glyphs.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.face_glyphs.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        return h;
    }

    pub fn deinit(self: *TextAtlas) void {
        for (self.face_glyphs) |*fg| fg.deinit(self.allocator);
        self.allocator.free(self.face_glyphs);

        for (self.pages) |p| p.release();
        self.allocator.free(self.pages);

        if (self.layer_info_data) |lid| self.allocator.free(lid);

        self.config.release();
    }

    // ── Resolution ──

    pub fn resolve(self: *const TextAtlas, style: snail.FontStyle, codepoint: u21) ?FaceIndex {
        return resolveInner(self.config, style, codepoint, 0);
    }

    // ── Metrics ──

    pub fn faceCount(self: *const TextAtlas) usize {
        return self.config.faces.len;
    }

    pub fn primaryFaceIndex(self: *const TextAtlas) !FaceIndex {
        return self.config.primary_face orelse error.NoFaces;
    }

    pub fn lineMetrics(self: *const TextAtlas) !snail.LineMetrics {
        return self.faceLineMetrics(try self.primaryFaceIndex());
    }

    pub fn unitsPerEm(self: *const TextAtlas) !u16 {
        return self.faceUnitsPerEm(try self.primaryFaceIndex());
    }

    pub fn faceLineMetrics(self: *const TextAtlas, face_index: usize) !snail.LineMetrics {
        const face = try self.faceConfig(face_index);
        return face.font.lineMetrics();
    }

    pub fn faceUnitsPerEm(self: *const TextAtlas, face_index: usize) !u16 {
        const face = try self.faceConfig(face_index);
        return face.font.units_per_em;
    }

    /// Return the glyph ID for `codepoint` in `face_index`, or null when the
    /// face's cmap resolves it to .notdef.
    pub fn glyphIndex(self: *const TextAtlas, face_index: usize, codepoint: u21) !?u16 {
        const face = try self.faceConfig(face_index);
        const gid = try face.font.glyphIndex(codepoint);
        return if (gid == 0) null else gid;
    }

    /// Return the horizontal advance for `glyph_id` in font units.
    pub fn advanceWidth(self: *const TextAtlas, face_index: usize, glyph_id: u16) !i16 {
        const face = try self.faceConfig(face_index);
        return face.font.advanceWidth(glyph_id);
    }

    /// Resolve the styled primary face and return terminal-friendly dimensions
    /// in the same units as `options.em`.
    pub fn cellMetrics(self: *const TextAtlas, options: CellMetricsOptions) !CellMetrics {
        const fi = self.resolve(options.style, 'M') orelse try self.primaryFaceIndex();
        const fc = &self.config.faces[fi];
        const gid = try glyphIndexForCellMetrics(fc);
        const advance = try fc.font.advanceWidth(gid);
        const lm = try fc.font.lineMetrics();
        const scale = options.em / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .cell_width = @as(f32, @floatFromInt(advance)) * scale,
            .line_height = @as(f32, @floatFromInt(@as(i32, lm.ascent) - @as(i32, lm.descent) + @as(i32, lm.line_gap))) * scale,
        };
    }

    pub fn decorationRect(self: *const TextAtlas, decoration: Decoration, x: f32, y: f32, advance: f32, font_size: f32) !snail.Rect {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const dm = try fc.font.decorationMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return switch (decoration) {
            .underline => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.underline_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.underline_thickness)) * scale),
            },
            .strikethrough => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.strikethrough_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.strikethrough_thickness)) * scale),
            },
        };
    }

    pub fn superscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.superscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y - @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    pub fn subscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.subscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y + @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    // ── Itemization ──

    /// Split text into runs where each run maps to one face.
    pub fn itemize(self: *const TextAtlas, allocator: Allocator, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
        return itemizeText(allocator, self.config, style, text);
    }

    pub fn faceView(self: *const TextAtlas, face_index: FaceIndex, atlas_view: anytype) FaceView {
        return .{
            .face_glyphs = &self.face_glyphs[face_index],
            .face_config = &self.config.faces[face_index],
            .layer_base = preparedViewLayerBase(atlas_view),
            .page_layers = preparedViewPageLayers(atlas_view),
            .info_row_base = preparedViewInfoRowBase(atlas_view),
        };
    }

    pub fn checkedFaceIndex(self: *const TextAtlas, face_index: usize) !FaceIndex {
        if (face_index >= self.config.faces.len) return error.InvalidFaceIndex;
        if (face_index > std.math.maxInt(FaceIndex)) return error.InvalidFaceIndex;
        return @intCast(face_index);
    }

    fn faceConfig(self: *const TextAtlas, face_index: usize) !*const FaceConfig {
        const fi = try self.checkedFaceIndex(face_index);
        return &self.config.faces[fi];
    }

    pub fn hasPreparedGlyph(self: *const TextAtlas, face_index: usize, glyph_id: u16) bool {
        const fi = self.checkedFaceIndex(face_index) catch return false;
        const face_view = self.faceView(fi, .{});
        return shapedGlyphAvailable(&face_view, glyph_id);
    }

    fn addMissingGlyphToFaceMap(
        self: *const TextAtlas,
        face_new_gids: []?std.AutoHashMap(u16, void),
        face_index: usize,
        glyph_id: u16,
    ) !void {
        if (glyph_id == 0) return;
        const fi = try self.checkedFaceIndex(face_index);
        if (self.hasPreparedGlyph(fi, glyph_id)) return;
        if (face_new_gids[fi] == null)
            face_new_gids[fi] = std.AutoHashMap(u16, void).init(self.allocator);
        try face_new_gids[fi].?.put(glyph_id, {});
    }

    pub fn canRebindFrom(self: *const TextAtlas, old_atlas: *const TextAtlas) bool {
        if (self.config != old_atlas.config) return false;
        if (self.face_glyphs.len != old_atlas.face_glyphs.len) return false;
        if (self.pages.len < old_atlas.pages.len) return false;
        for (old_atlas.pages, 0..) |page_ptr, i| {
            if (self.pages[i] != page_ptr) return false;
        }
        return true;
    }

    // ── Rendering ──

    pub fn shapeText(
        self: *const TextAtlas,
        allocator: Allocator,
        style: snail.FontStyle,
        text: []const u8,
    ) !ShapedText {
        const runs = try itemizeText(allocator, self.config, style, text);
        defer allocator.free(runs);

        var glyphs = std.ArrayListUnmanaged(ShapedText.Glyph).empty;
        errdefer glyphs.deinit(allocator);

        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const segment = text[run.text_start..run.text_end];
            const shaped_run = try shapeRunForFace(allocator, fc, run.face_index, segment, run.text_start);
            defer if (shaped_run.glyphs.len > 0) allocator.free(shaped_run.glyphs);

            for (shaped_run.glyphs) |glyph| {
                try glyphs.append(allocator, .{
                    .face_index = glyph.face_index,
                    .glyph_id = glyph.glyph_id,
                    .x_offset = cursor_x + glyph.x_offset,
                    .y_offset = cursor_y + glyph.y_offset,
                    .x_advance = glyph.x_advance,
                    .y_advance = glyph.y_advance,
                    .source_start = glyph.source_start,
                    .source_end = glyph.source_end,
                });
            }
            cursor_x += shaped_run.advance_x;
            cursor_y += shaped_run.advance_y;
        }

        return .{
            .allocator = allocator,
            .atlas_identity = self.snapshotIdentity(),
            .config = self.config,
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .advance_x = cursor_x,
            .advance_y = cursor_y,
        };
    }

    /// Emit shaped text directly into a low-level TextBatch.
    pub fn appendTextBatch(
        self: *const TextAtlas,
        batch: *TextBatch,
        append: TextBatchAppend,
        allow_missing: bool,
    ) !TextAppendResult {
        const shaped = append.shaped;
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;
        const range = append.glyphs.resolve(shaped.glyphs.len);
        const pen_origin = shapedPenAt(shaped, range.start);

        var missing = false;
        for (shaped.glyphs[range.start..range.end]) |glyph| {
            const fc = &self.config.faces[glyph.face_index];
            const face_view = self.faceView(glyph.face_index, .{});
            if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
                missing = true;
                if (!allow_missing) return error.MissingPreparedGlyph;
                continue;
            }

            const x = append.placement.baseline.x + (glyph.x_offset - pen_origin.x) * append.placement.em;
            const y = append.placement.baseline.y + (glyph.y_offset - pen_origin.y) * append.placement.em;
            if (glyph_emit.emitStyledGlyph(batch, &face_view, glyph.glyph_id, x, y, append.placement.em, append.color, fc.synthetic) == .buffer_full) break;
        }

        return .{
            .advance = scaleAdvance(shapedAdvanceForRange(shaped, range), append.placement.em),
            .missing = missing,
        };
    }

    /// Measure advance width without emitting vertices.
    pub fn measureText(
        self: *const TextAtlas,
        style: snail.FontStyle,
        text: []const u8,
        font_size: f32,
    ) !f32 {
        var shaped = try self.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return shaped.advance_x * font_size;
    }

    // ── Atlas extension ──

    /// Return a new TextAtlas snapshot with atlas extended for the given text.
    /// Returns null if all glyphs are already present. The old snapshot stays valid.
    pub fn ensureText(self: *const TextAtlas, style: snail.FontStyle, text: []const u8) !?TextAtlas {
        var shaped = try self.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return self.ensureShaped(&shaped);
    }

    /// Return a new TextAtlas snapshot with all glyphs referenced by `shaped`
    /// available. Returns null if the current snapshot already contains them.
    pub fn ensureShaped(self: *const TextAtlas, shaped: *const ShapedText) !?TextAtlas {
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;

        const face_new_gids = try self.allocator.alloc(?std.AutoHashMap(u16, void), self.config.faces.len);
        defer self.allocator.free(face_new_gids);
        @memset(face_new_gids, null);
        defer for (face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (shaped.glyphs) |glyph| {
            try self.addMissingGlyphToFaceMap(face_new_gids, glyph.face_index, glyph.glyph_id);
        }

        return self.ensureGlyphMaps(face_new_gids);
    }

    /// Return a new TextAtlas snapshot with the given glyph IDs available for
    /// one face. Returns null if the current snapshot already contains them.
    pub fn ensureGlyphs(self: *const TextAtlas, face_index: usize, glyph_ids: []const u16) !?TextAtlas {
        const fi = try self.checkedFaceIndex(face_index);

        const face_new_gids = try self.allocator.alloc(?std.AutoHashMap(u16, void), self.config.faces.len);
        defer self.allocator.free(face_new_gids);
        @memset(face_new_gids, null);
        defer for (face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (glyph_ids) |gid| {
            try self.addMissingGlyphToFaceMap(face_new_gids, fi, gid);
        }

        return self.ensureGlyphMaps(face_new_gids);
    }

    fn ensureGlyphMaps(self: *const TextAtlas, face_new_gids: []?std.AutoHashMap(u16, void)) !?TextAtlas {
        std.debug.assert(face_new_gids.len == self.config.faces.len);

        var any_missing = false;
        for (face_new_gids) |maybe_map| {
            if (maybe_map) |map| {
                if (map.count() > 0) {
                    any_missing = true;
                    break;
                }
            }
        }
        if (!any_missing) return null;

        // Build new pages for each face with missing glyphs.
        var new_pages_list = std.ArrayListUnmanaged(*AtlasPage).empty;
        defer new_pages_list.deinit(self.allocator);

        const new_face_glyphs = try self.allocator.alloc(FaceGlyphData, self.config.faces.len);
        const new_face_glyphs_initialized = try self.allocator.alloc(bool, self.config.faces.len);
        defer self.allocator.free(new_face_glyphs_initialized);
        @memset(new_face_glyphs_initialized, false);
        errdefer {
            for (new_face_glyphs, new_face_glyphs_initialized) |*fg, initialized| {
                if (initialized) fg.deinit(self.allocator);
            }
            self.allocator.free(new_face_glyphs);
        }

        for (self.config.faces, 0..) |*fc, fi| {
            if (face_new_gids[fi]) |*new_gids| {
                // Expand COLR layers.
                try CurveAtlas.expandColrLayersInner(&fc.font, self.allocator, new_gids);

                // Filter out glyph IDs already in the atlas.
                var filtered = std.AutoHashMap(u16, void).init(self.allocator);
                defer filtered.deinit();
                var git = new_gids.keyIterator();
                while (git.next()) |gid_ptr| {
                    if (!self.face_glyphs[fi].glyph_map.contains(gid_ptr.*))
                        try filtered.put(gid_ptr.*, {});
                }

                if (filtered.count() == 0) {
                    new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                    new_face_glyphs_initialized[fi] = true;
                    continue;
                }

                // Build page for the new glyphs. `page_index` is u16 because
                // the GPU vertex encoding only has 16 bits for it.
                const next_page = self.pages.len + new_pages_list.items.len;
                if (next_page > std.math.maxInt(u16)) return error.AtlasPageLimitExceeded;
                const page_index: u16 = @intCast(next_page);
                const page_result = try CurveAtlas.buildPageDataInner(self.allocator, &fc.font, &filtered, page_index);
                try new_pages_list.append(self.allocator, page_result.page);

                // Merge glyph maps.
                var merged = std.AutoHashMap(u16, GlyphInfo).init(self.allocator);
                var eit = self.face_glyphs[fi].glyph_map.iterator();
                while (eit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var nit = page_result.glyph_map.iterator();
                while (nit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var pm = page_result.glyph_map;
                pm.deinit();

                new_face_glyphs[fi] = .{ .glyph_map = merged };
                new_face_glyphs_initialized[fi] = true;
                try new_face_glyphs[fi].buildGlyphLut(self.allocator);
            } else {
                new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                new_face_glyphs_initialized[fi] = true;
            }
        }

        // Assemble new pages array: retain old + own new.
        const total_pages = self.pages.len + new_pages_list.items.len;
        const new_pages = try self.allocator.alloc(*AtlasPage, total_pages);
        for (self.pages, 0..) |p, i| new_pages[i] = p.retain();
        for (new_pages_list.items, 0..) |p, i| new_pages[self.pages.len + i] = p;

        return .{
            .allocator = self.allocator,
            .config = self.config.retain(),
            .pages = new_pages,
            .face_glyphs = new_face_glyphs,
        };
    }

    // ── GPU upload helpers ──

    pub fn pageCount(self: *const TextAtlas) usize {
        return self.pages.len;
    }

    pub fn page(self: *const TextAtlas, index: usize) *const AtlasPage {
        return self.pages[index];
    }

    pub fn pageSlice(self: *const TextAtlas) []*AtlasPage {
        return self.pages;
    }

    pub fn uploadFootprint(self: *const TextAtlas) snail.ResourceFootprint {
        return snail.textAtlasUploadFootprint(self);
    }

    /// Low-level: create a temporary `CurveAtlas` wrapper that borrows this
    /// snapshot's pages for GPU upload. Most callers should use
    /// `Renderer.uploadResourcesBlocking` (or `planResourceUpload` /
    /// `beginResourceUpload`) instead — this entry point is for code that
    /// drives the upload helpers in `lowlevel` directly.
    ///
    /// The returned wrapper borrows `self.pages`. Free it via
    /// `deinitUploadAtlas` (do NOT call `wrapper.deinit()`, which would
    /// release the shared pages).
    pub fn uploadAtlas(self: *const TextAtlas) CurveAtlas {
        return .{
            .allocator = self.allocator,
            .font = null,
            .pages = self.pages,
            .glyph_map = .init(self.allocator), // empty — glyph lookup goes through FaceView
            .shaper = null,
            .layer_info_data = self.layer_info_data,
            .layer_info_width = self.layer_info_width,
            .layer_info_height = self.layer_info_height,
        };
    }

    /// Clean up a wrapper Atlas from uploadAtlas(). Only frees the empty glyph_map,
    /// NOT the shared pages.
    pub fn deinitUploadAtlas(_: *const TextAtlas, wrapper: *CurveAtlas) void {
        wrapper.glyph_map.deinit();
        // Don't free pages — they belong to TextAtlas.
        wrapper.pages = &.{};
        // Don't call wrapper.deinit() — that would release shared pages.
    }
};
