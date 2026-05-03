//! Multi-font manager with immutable snapshot semantics.
//!
//! `Fonts` is the primary text rendering API. It manages multiple font faces
//! with style-specific and global fallback chains, a shared glyph atlas, and
//! automatic text itemization. All rendering methods are read-only and safe
//! for concurrent use. Extending the atlas returns a new immutable snapshot;
//! the old snapshot remains valid for in-flight readers.

const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");
const opentype = @import("font/opentype.zig");
const glyph_emit = @import("glyph_emit.zig");
const build_options = @import("build_options");
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const Allocator = std.mem.Allocator;
const AtlasPage = snail.AtlasPage;
const GlyphInfo = snail.Atlas.GlyphInfo;
const ColrBaseInfo = snail.Atlas.ColrBaseInfo;
const TextBatch = snail.TextBatch;
const bezier = @import("math/bezier.zig");
const band_tex = @import("render/band_texture.zig");

// ── Public types ──

pub const FaceIndex = u16;

pub const FaceSpec = struct {
    data: []const u8,
    weight: snail.FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: snail.SyntheticStyle = .{},
};

pub const AddTextResult = struct {
    advance: f32,
    missing: bool,
};

pub const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

pub const ScriptTransform = struct {
    x: f32,
    y: f32,
    font_size: f32,
};

pub const Decoration = enum {
    underline,
    strikethrough,
};

// ── Internal types ──

/// Immutable font configuration shared across snapshots via refcount.
/// Created once during Fonts.init, never modified.
pub const FontConfig = struct {
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    allocator: Allocator,
    faces: []FaceConfig,
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: []FaceIndex,
    primary_face: ?FaceIndex,

    pub fn retain(self: *FontConfig) *FontConfig {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *FontConfig) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) {
            const allocator = self.allocator;
            for (self.faces) |*fc| fc.deinit();
            allocator.free(self.faces);

            var it = self.style_chains.iterator();
            while (it.next()) |entry| entry.value_ptr.deinit(allocator);
            self.style_chains.deinit(allocator);

            allocator.free(self.global_chain);
            allocator.destroy(self);
        }
    }
};

/// Per-face immutable data: parsed font, shapers, style metadata.
pub const FaceConfig = struct {
    font: ttf.Font,
    font_data: []const u8,
    weight: snail.FontWeight,
    italic: bool,
    synthetic: snail.SyntheticStyle,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,
    owns_shapers: bool, // false when sharing with another face (dedup)

    fn deinit(self: *FaceConfig) void {
        if (!self.owns_shapers) return;
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

/// Per-face, per-snapshot glyph data. Rebuilt when the atlas is extended.
pub const FaceGlyphData = struct {
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null,
    glyph_lut_len: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,

    fn deinit(self: *FaceGlyphData, allocator: Allocator) void {
        self.glyph_map.deinit();
        if (self.glyph_lut) |lut| allocator.free(lut);
        if (self.colr_base_map) |*cbm| cbm.deinit();
    }

    fn clone(self: *const FaceGlyphData, allocator: Allocator) !FaceGlyphData {
        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        var colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null;
        if (self.colr_base_map) |cbm| {
            colr_base_map = std.AutoHashMap(u16, ColrBaseInfo).init(allocator);
            var cit = cbm.iterator();
            while (cit.next()) |entry| try colr_base_map.?.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var result = FaceGlyphData{
            .glyph_map = glyph_map,
            .colr_base_map = colr_base_map,
        };
        try result.buildGlyphLut(allocator);
        return result;
    }

    pub fn getGlyph(self: *const FaceGlyphData, gid: u16) ?GlyphInfo {
        if (self.glyph_lut) |lut| {
            if (gid < self.glyph_lut_len) {
                const info = lut[gid];
                if (info.band_entry.h_band_count > 0) return info;
            }
            return null;
        }
        return self.glyph_map.get(gid);
    }

    fn buildGlyphLut(self: *FaceGlyphData, allocator: Allocator) !void {
        if (self.glyph_lut) |lut| allocator.free(lut);
        self.glyph_lut = null;

        if (self.glyph_map.count() == 0) return;

        var max_gid: u32 = 0;
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* > max_gid) max_gid = entry.key_ptr.*;
        }

        const size = max_gid + 1;
        const lut = try allocator.alloc(GlyphInfo, size);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            lut[entry.key_ptr.*] = entry.value_ptr.*;
        }

        self.glyph_lut = lut;
        self.glyph_lut_len = @intCast(size);
    }
};

/// View into one face's glyph data within a Fonts snapshot.
/// Implements the interface expected by glyph_emit.emitGlyph.
pub const FaceView = struct {
    face_glyphs: *const FaceGlyphData,
    face_config: *const FaceConfig,
    layer_base: u16,
    info_row_base: u16,

    pub fn getGlyph(self: *const FaceView, gid: u16) ?GlyphInfo {
        return self.face_glyphs.getGlyph(gid);
    }

    pub fn getColrBase(self: *const FaceView, gid: u16) ?ColrBaseInfo {
        if (self.face_glyphs.colr_base_map) |cbm| return cbm.get(gid);
        return null;
    }

    pub fn colrLayers(self: *const FaceView, gid: u16) ttf.Font.ColrLayerIterator {
        if (self.face_config.font.colr_offset == 0) return .{ .data = self.face_config.font_data };
        const temp = ttf.Font{ .data = self.face_config.font_data, .colr_offset = self.face_config.font.colr_offset, .cpal_offset = self.face_config.font.cpal_offset };
        return temp.colrLayers(gid);
    }

    pub fn glyphLayer(self: *const FaceView, page_index: u16) u8 {
        const layer = self.layer_base + page_index;
        std.debug.assert(layer < 256);
        return @intCast(layer);
    }

    pub fn layerInfoLoc(self: *const FaceView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = self.info_row_base + info_y,
        };
    }
};

// ── Fonts ──

/// Multi-font text rendering with immutable snapshot semantics.
///
/// Create with `init`, populate glyphs with `ensureText`, render with `addText`.
/// All rendering methods are read-only and safe for concurrent use.
/// `ensureText` returns a new snapshot; the old one remains valid.
pub const Fonts = struct {
    allocator: Allocator,
    config: *FontConfig,
    pages: []*AtlasPage,
    face_glyphs: []FaceGlyphData,

    // Merged COLR layer info across all faces.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,

    // GPU handle state (set after upload).
    layer_base: u16 = 0,
    info_row_base: u16 = 0,

    pub fn init(allocator: Allocator, specs: []const FaceSpec) !Fonts {
        // Build FontConfig.
        const config = try buildFontConfig(allocator, specs);
        errdefer config.release();

        // Start with empty glyph data for each face.
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

    pub fn deinit(self: *Fonts) void {
        for (self.face_glyphs) |*fg| fg.deinit(self.allocator);
        self.allocator.free(self.face_glyphs);

        for (self.pages) |p| p.release();
        self.allocator.free(self.pages);

        if (self.layer_info_data) |lid| self.allocator.free(lid);

        self.config.release();
    }

    // ── Resolution ──

    pub fn resolve(self: *const Fonts, style: snail.FontStyle, codepoint: u21) ?FaceIndex {
        return resolveInner(self.config, style, codepoint, 0);
    }

    // ── Metrics ──

    pub fn lineMetrics(self: *const Fonts) !snail.LineMetrics {
        const pf = self.config.primary_face orelse return error.NoFaces;
        return self.config.faces[pf].font.lineMetrics();
    }

    pub fn unitsPerEm(self: *const Fonts) !u16 {
        const pf = self.config.primary_face orelse return error.NoFaces;
        return self.config.faces[pf].font.units_per_em;
    }

    pub fn decorationRect(self: *const Fonts, decoration: Decoration, x: f32, y: f32, advance: f32, font_size: f32) !snail.Rect {
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

    pub fn superscriptTransform(self: *const Fonts, x: f32, y: f32, font_size: f32) !ScriptTransform {
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

    pub fn subscriptTransform(self: *const Fonts, x: f32, y: f32, font_size: f32) !ScriptTransform {
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
    pub fn itemize(self: *const Fonts, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
        return itemizeText(self.allocator, self.config, style, text);
    }

    // ── Rendering ──

    /// Itemize, shape, and emit text into a TextBatch. Returns advance width
    /// and whether any glyphs were missing from the atlas.
    pub fn addText(
        self: *const Fonts,
        batch: *TextBatch,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) !AddTextResult {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        var cx = x;
        var missing = false;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (hasMissingGlyphs(fc, fg, segment))
                missing = true;

            const face_view = FaceView{
                .face_glyphs = fg,
                .face_config = fc,
                .layer_base = self.layer_base,
                .info_row_base = self.info_row_base,
            };

            const has_synthetic = fc.synthetic.skew_x != 0 or fc.synthetic.embolden != 0;

            if (!has_synthetic) {
                cx += addTextForFace(batch, &face_view, fc, fg, segment, cx, y, font_size, color);
            } else {
                cx += addTextForFaceSynthetic(self.allocator, batch, &face_view, fc, fg, segment, cx, y, font_size, color);
            }
        }

        return .{ .advance = cx - x, .missing = missing };
    }

    /// Measure advance width without emitting vertices.
    pub fn measureText(
        self: *const Fonts,
        style: snail.FontStyle,
        text: []const u8,
        font_size: f32,
    ) !f32 {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        var width: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (comptime build_options.enable_harfbuzz) {
                if (fc.hb_shaper) |hbs| {
                    width += hbs.measureWidth(segment, font_size);
                    continue;
                }
            }

            const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
            const utf8_view = std.unicode.Utf8View.initUnchecked(segment);
            var it = utf8_view.iterator();
            while (it.nextCodepoint()) |cp| {
                const gid = fc.font.glyphIndex(cp) catch 0;
                if (gid == 0) {
                    width += scale * 500;
                    continue;
                }
                if (fg.getGlyph(gid)) |info| {
                    width += @as(f32, @floatFromInt(info.advance_width)) * scale;
                } else {
                    width += @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * scale;
                }
            }
        }
        return width;
    }

    // ── Atlas extension ──

    /// Return a new Fonts snapshot with atlas extended for the given text.
    /// Returns null if all glyphs are already present. The old snapshot stays valid.
    pub fn ensureText(self: *const Fonts, style: snail.FontStyle, text: []const u8) !?Fonts {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        // Discover missing glyphs per face.
        var any_missing = false;
        var face_new_gids: [256]?std.AutoHashMap(u16, void) = .{null} ** 256;
        defer for (&face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            // Discover glyph IDs for this segment.
            if (comptime build_options.enable_harfbuzz) {
                if (fc.hb_shaper) |hbs| {
                    const discovered = try hbs.discoverGlyphs(self.allocator, segment);
                    defer if (discovered.len > 0) self.allocator.free(discovered);
                    for (discovered) |gid| {
                        if (gid == 0) continue;
                        if (fg.getGlyph(gid) != null) continue;
                        const has_colr = if (fg.colr_base_map) |cbm| cbm.contains(gid) else false;
                        if (has_colr) continue;
                        if (face_new_gids[run.face_index] == null)
                            face_new_gids[run.face_index] = std.AutoHashMap(u16, void).init(self.allocator);
                        try face_new_gids[run.face_index].?.put(gid, {});
                        any_missing = true;
                    }
                    continue;
                }
            }

            // Fallback: cmap-based discovery.
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
                const gid = fc.font.glyphIndex(cp) catch continue;
                if (gid == 0) continue;
                if (fg.getGlyph(gid) != null) continue;
                const has_colr = if (fg.colr_base_map) |cbm| cbm.contains(gid) else false;
                if (has_colr) continue;
                if (face_new_gids[run.face_index] == null)
                    face_new_gids[run.face_index] = std.AutoHashMap(u16, void).init(self.allocator);
                try face_new_gids[run.face_index].?.put(gid, {});
                any_missing = true;
            }
        }

        if (!any_missing) return null;

        // Build new pages for each face with missing glyphs.
        var new_pages_list = std.ArrayListUnmanaged(*AtlasPage).empty;
        defer new_pages_list.deinit(self.allocator);

        const new_face_glyphs = try self.allocator.alloc(FaceGlyphData, self.config.faces.len);
        errdefer {
            for (new_face_glyphs) |*fg| fg.deinit(self.allocator);
            self.allocator.free(new_face_glyphs);
        }

        for (self.config.faces, 0..) |*fc, fi| {
            if (face_new_gids[fi]) |*new_gids| {
                // Expand COLR layers.
                snail.Atlas.expandColrLayersInner(&fc.font, self.allocator, new_gids) catch {};

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
                    continue;
                }

                // Build page for the new glyphs.
                const page_index: u16 = @intCast(self.pages.len + new_pages_list.items.len);
                const page_result = try snail.Atlas.buildPageDataInner(self.allocator, &fc.font, &filtered, page_index);
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
                try new_face_glyphs[fi].buildGlyphLut(self.allocator);

            } else {
                new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
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

    pub fn pageCount(self: *const Fonts) usize {
        return self.pages.len;
    }

    pub fn page(self: *const Fonts, index: usize) *const AtlasPage {
        return self.pages[index];
    }

    pub fn pageSlice(self: *const Fonts) []*AtlasPage {
        return self.pages;
    }

    /// Create a temporary Atlas wrapper for GPU upload. The wrapper borrows
    /// pages from this Fonts snapshot — do NOT deinit it (use deinitUploadAtlas).
    /// Upload alongside PathPicture atlases via Renderer.uploadAtlases.
    pub fn uploadAtlas(self: *const Fonts) snail.Atlas {
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
    pub fn deinitUploadAtlas(_: *const Fonts, wrapper: *snail.Atlas) void {
        wrapper.glyph_map.deinit();
        // Don't free pages — they belong to Fonts.
        wrapper.pages = &.{};
        // Don't call wrapper.deinit() — that would release shared pages.
    }
};

// ── FontConfig construction ──

fn buildFontConfig(allocator: Allocator, specs: []const FaceSpec) !*FontConfig {
    const config = try allocator.create(FontConfig);
    errdefer allocator.destroy(config);

    const faces = try allocator.alloc(FaceConfig, specs.len);
    errdefer allocator.free(faces);

    // Parse fonts, deduplicating by data pointer.
    var parsed_cache = std.AutoHashMap([*]const u8, struct { font: ttf.Font, shaper: ?opentype.Shaper, hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void }).init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        if (parsed_cache.get(spec.data.ptr)) |cached| {
            faces[i] = .{
                .font = cached.font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = cached.shaper,
                .hb_shaper = cached.hb_shaper,
                .owns_shapers = false,
            };
        } else {
            const font = try ttf.Font.init(spec.data);
            const shaper = opentype.Shaper.init(allocator, spec.data, font.gsub_offset, font.gpos_offset) catch null;
            const hb_shaper = if (comptime build_options.enable_harfbuzz)
                harfbuzz.HarfBuzzShaper.init(spec.data, font.units_per_em) catch null
            else {};

            try parsed_cache.put(spec.data.ptr, .{ .font = font, .shaper = shaper, .hb_shaper = hb_shaper });

            faces[i] = .{
                .font = font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = shaper,
                .hb_shaper = hb_shaper,
                .owns_shapers = true,
            };
        }
    }

    // Build style chains and global fallback chain.
    var style_chains = std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)).empty;
    errdefer {
        var it = style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        style_chains.deinit(allocator);
    }

    var global_chain_list = std.ArrayListUnmanaged(FaceIndex).empty;
    errdefer global_chain_list.deinit(allocator);

    var primary_face: ?FaceIndex = null;

    for (specs, 0..) |spec, i| {
        const fi: FaceIndex = @intCast(i);

        if (spec.fallback) {
            try global_chain_list.append(allocator, fi);
            if (primary_face == null) primary_face = fi;
        } else {
            const key = packStyle(.{ .weight = spec.weight, .italic = spec.italic });
            const gop = try style_chains.getOrPut(allocator, key);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(allocator, fi);

            if (primary_face == null and spec.weight == .regular and !spec.italic) {
                primary_face = fi;
            }
        }
    }

    const global_chain = try allocator.alloc(FaceIndex, global_chain_list.items.len);
    @memcpy(global_chain, global_chain_list.items);
    global_chain_list.deinit(allocator);

    config.* = .{
        .allocator = allocator,
        .faces = faces,
        .style_chains = style_chains,
        .global_chain = global_chain,
        .primary_face = primary_face,
    };

    return config;
}

// ── Resolution helpers ──

fn resolveInner(config: *const FontConfig, style: snail.FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
    if (depth > 3) return null;

    // 1. Style-specific chain
    if (config.style_chains.get(packStyle(style))) |chain| {
        for (chain.items) |fi| {
            if (faceHasGlyph(config, fi, codepoint)) return fi;
        }
    }

    // 2. Global fallbacks
    for (config.global_chain) |fi| {
        if (faceHasGlyph(config, fi, codepoint)) return fi;
    }

    // 3. Style degradation
    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveInner(config, .{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
        if (resolveInner(config, .{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.italic) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.weight != .regular) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    }

    return null;
}

fn faceHasGlyph(config: *const FontConfig, fi: FaceIndex, codepoint: u21) bool {
    const gid = config.faces[fi].font.glyphIndex(codepoint) catch return false;
    return gid != 0;
}

fn packStyle(style: snail.FontStyle) u8 {
    return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
}

// ── Itemization ──

fn itemizeText(allocator: Allocator, config: *const FontConfig, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
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

        const face_idx = resolveInner(config, style, cp, 0) orelse
            if (config.primary_face) |pf| pf else {
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

    if (current_face) |fi| {
        try runs.append(allocator, .{
            .face_index = fi,
            .text_start = run_start,
            .text_end = byte_offset,
        });
    }

    return try runs.toOwnedSlice(allocator);
}

// ── Missing glyph detection ──

fn hasMissingGlyphs(fc: *const FaceConfig, fg: *const FaceGlyphData, segment: []const u8) bool {
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
        const gid = fc.font.glyphIndex(cp) catch continue;
        if (gid == 0) continue;
        if (fg.getGlyph(gid) != null) continue;
        const has_colr = if (fg.colr_base_map) |cbm| cbm.contains(gid) else false;
        if (!has_colr) return true;
    }
    return false;
}

// ── Per-face text rendering ──

fn addTextForFace(
    batch: *TextBatch,
    face_view: *const FaceView,
    fc: *const FaceConfig,
    fg: *const FaceGlyphData,
    text: []const u8,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
) f32 {
    // HarfBuzz fast path
    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            return hbs.shapeAndEmit(text, font_size, x, y, color, face_view, batch);
        }
    }

    // Built-in shaping path
    const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
    var cursor_x = x;

    // Map codepoints to glyph IDs
    var glyph_buf: [256]u16 = undefined;
    var glyph_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (glyph_count >= glyph_buf.len) break;
        glyph_buf[glyph_count] = fc.font.glyphIndex(cp) catch 0;
        glyph_count += 1;
    }

    // Apply ligatures
    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigatures(glyph_buf[0..glyph_count]) catch glyph_count;
    }

    // Layout and emit
    var prev_gid: u16 = 0;
    for (glyph_buf[0..glyph_count]) |gid| {
        if (gid == 0) {
            cursor_x += scale * 500;
            prev_gid = 0;
            continue;
        }

        // Kerning
        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| {
                kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            }
            if (kern == 0) {
                kern = fc.font.getKerning(prev_gid, gid) catch 0;
            }
            cursor_x += @as(f32, @floatFromInt(kern)) * scale;
        }

        if (glyph_emit.emitGlyph(batch, face_view, gid, cursor_x, y, font_size, color) == .buffer_full) break;

        const advance = faceGlyphAdvance(fc, fg, gid) orelse {
            cursor_x += scale * 500;
            prev_gid = gid;
            continue;
        };
        cursor_x += @as(f32, @floatFromInt(advance)) * scale;
        prev_gid = gid;
    }

    return cursor_x - x;
}

fn addTextForFaceSynthetic(
    allocator: Allocator,
    batch: *TextBatch,
    face_view: *const FaceView,
    fc: *const FaceConfig,
    fg: *const FaceGlyphData,
    text: []const u8,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
) f32 {
    // For synthetic styles, we need per-glyph positioning then emitStyledGlyph.
    const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
    var cursor_x = x;

    var glyph_buf: [256]u16 = undefined;
    var glyph_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (glyph_count >= glyph_buf.len) break;
        glyph_buf[glyph_count] = fc.font.glyphIndex(cp) catch 0;
        glyph_count += 1;
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigatures(glyph_buf[0..glyph_count]) catch glyph_count;
    }

    _ = allocator; // reserved for future heap shaping path

    var prev_gid: u16 = 0;
    for (glyph_buf[0..glyph_count]) |gid| {
        if (gid == 0) {
            cursor_x += scale * 500;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| {
                kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            }
            if (kern == 0) {
                kern = fc.font.getKerning(prev_gid, gid) catch 0;
            }
            cursor_x += @as(f32, @floatFromInt(kern)) * scale;
        }

        if (glyph_emit.emitStyledGlyph(batch, face_view, gid, cursor_x, y, font_size, color, fc.synthetic) == .buffer_full) break;

        const advance = faceGlyphAdvance(fc, fg, gid) orelse {
            cursor_x += scale * 500;
            prev_gid = gid;
            continue;
        };
        cursor_x += @as(f32, @floatFromInt(advance)) * scale;
        prev_gid = gid;
    }

    return cursor_x - x;
}

fn faceGlyphAdvance(fc: *const FaceConfig, fg: *const FaceGlyphData, gid: u16) ?u16 {
    if (fg.glyph_map.get(gid)) |info| return info.advance_width;
    if (fc.font.colr_offset != 0 and fc.font.colrLayerCount(gid) > 0) return fc.font.units_per_em;
    return null;
}

// ── Tests ──

const testing = std.testing;

test "Fonts.init with single face" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(?FaceIndex, 0), fonts.config.primary_face);
    try testing.expectEqual(@as(usize, 1), fonts.config.faces.len);
    try testing.expectEqual(@as(usize, 0), fonts.pageCount());
}

test "Fonts.ensureText adds missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Atlas starts empty.
    try testing.expectEqual(@as(usize, 0), fonts.pageCount());

    // Ensure text creates a new snapshot with glyphs.
    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    try testing.expect(fonts.pageCount() > 0);

    // Ensuring the same text again returns null (nothing new).
    const again = try fonts.ensureText(.{}, "Hello");
    try testing.expectEqual(@as(?Fonts, null), again);
}

test "Fonts.ensureText snapshot immutability" {
    const assets_data = @import("assets");
    var fonts1 = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts1.deinit();

    if (try fonts1.ensureText(.{}, "AB")) |new_fonts| {
        fonts1.deinit();
        fonts1 = new_fonts;
    }
    const pages_before = fonts1.pageCount();

    // Extend with more text → new snapshot.
    const maybe_fonts2 = try fonts1.ensureText(.{}, "CDEFGHIJKLMNOP");
    try testing.expect(maybe_fonts2 != null);
    var fonts2 = maybe_fonts2.?;
    defer fonts2.deinit();

    // Old snapshot unchanged.
    try testing.expectEqual(pages_before, fonts1.pageCount());
    // New snapshot has at least as many pages.
    try testing.expect(fonts2.pageCount() >= pages_before);
}

test "Fonts.addText renders and reports advance" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var buf: [64 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
    var batch = snail.TextBatch.init(&buf);
    const result = try fonts.addText(&batch, .{}, "Hello", 0, 100, 24, .{ 1, 1, 1, 1 });

    try testing.expect(result.advance > 0);
    try testing.expect(batch.glyphCount() > 0);
    try testing.expect(!result.missing);
}

test "Fonts.addText reports missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Don't ensure — atlas is empty.
    var buf: [64 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
    var batch = snail.TextBatch.init(&buf);
    const result = try fonts.addText(&batch, .{}, "Hello", 0, 100, 24, .{ 1, 1, 1, 1 });

    try testing.expect(result.missing);
    try testing.expectEqual(@as(usize, 0), batch.glyphCount());
}

test "Fonts.lineMetrics returns primary face metrics" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const lm = try fonts.lineMetrics();
    try testing.expect(lm.ascent > 0);
    try testing.expect(lm.descent < 0);
}

test "Fonts with multiple faces and fallback" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
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

test "Fonts deduplicates same font data" {
    const assets_data = @import("assets");
    var fonts = try Fonts.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    });
    defer fonts.deinit();

    // Both faces share the same parsed font (data pointer equality).
    try testing.expectEqual(fonts.config.faces[0].font.data.ptr, fonts.config.faces[1].font.data.ptr);
}
