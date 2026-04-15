//! snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
//!
//! Usage:
//!   const font = try snail.Font.init(allocator, ttf_bytes);
//!   defer font.deinit();
//!
//!   var atlas = try snail.Atlas.init(allocator, &font, codepoints);
//!   defer atlas.deinit();
//!
//!   var renderer = try snail.Renderer.init();
//!   defer renderer.deinit();
//!   renderer.uploadAtlas(&atlas);
//!
//!   var batch = snail.Batch.init(&vertex_buf);
//!   batch.addString(&atlas, &font, "Hello", x, y, size, color);
//!   renderer.draw(batch.slice(), mvp, viewport_w, viewport_h);

const std = @import("std");
const build_options = @import("build_options");
pub const ttf = @import("font/ttf.zig");
pub const opentype = @import("font/opentype.zig");
pub const snail_file = @import("font/snail_file.zig");
pub const bezier = @import("math/bezier.zig");
pub const vec = @import("math/vec.zig");
const curve_tex = @import("render/curve_texture.zig");
const band_tex = @import("render/band_texture.zig");
const vertex_mod = @import("render/vertex.zig");
const pipeline = @import("render/pipeline.zig");
pub const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

pub const Mat4 = vec.Mat4;
pub const Vec2 = vec.Vec2;

// Re-export vertex constants for buffer sizing
pub const FLOATS_PER_VERTEX = vertex_mod.FLOATS_PER_VERTEX;
pub const VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const FLOATS_PER_GLYPH = FLOATS_PER_VERTEX * VERTICES_PER_GLYPH;

/// A parsed TrueType font. Immutable after init.
/// Thread-safe for concurrent reads (glyphIndex, getKerning).
pub const Font = struct {
    inner: ttf.Font,

    /// Parse a TrueType font from raw file data.
    /// The data slice must outlive the Font.
    pub fn init(data: []const u8) !Font {
        return .{ .inner = try ttf.Font.init(data) };
    }

    pub fn deinit(self: *Font) void {
        _ = self;
    }

    pub fn unitsPerEm(self: *const Font) u16 {
        return self.inner.units_per_em;
    }

    pub fn glyphIndex(self: *const Font, codepoint: u32) !u16 {
        return self.inner.glyphIndex(codepoint);
    }

    pub fn getKerning(self: *const Font, left: u16, right: u16) !i16 {
        return self.inner.getKerning(left, right);
    }
};

/// Pre-built GPU texture data for a set of glyphs.
/// Create once, upload to Renderer, then use with Batch.
pub const Atlas = struct {
    allocator: std.mem.Allocator,
    font: ?*const Font, // null for .snail-loaded atlases

    // GPU texture data (CPU-side, ready for upload)
    curve_data: []u16,
    curve_width: u32,
    curve_height: u32,
    band_data: []u16,
    band_width: u32,
    band_height: u32,

    // Per-glyph lookup (dense array indexed by glyph ID for O(1) access)
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null, // dense lookup: glyph_lut[gid], h_band_count==0 means absent
    glyph_lut_len: u32 = 0,

    // OpenType shaper (ligatures + GPOS kerning)
    shaper: ?opentype.Shaper,

    // HarfBuzz shaper (full OpenType, compile-time optional)
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void = if (build_options.enable_harfbuzz) null else {},

    // GPU texture handles (created on first upload, 0 = not yet uploaded)
    gl_curve_texture: u32 = 0,
    gl_band_texture: u32 = 0,

    // Texture array layer index (assigned by Renderer.uploadAtlas)
    gl_layer: u8 = 0,

    pub const GlyphInfo = struct {
        bbox: bezier.BBox,
        advance_width: u16,
        band_entry: band_tex.GlyphBandEntry,
    };

    const TextureResult = struct {
        curve_data: []u16,
        curve_width: u32,
        curve_height: u32,
        band_data: []u16,
        band_width: u32,
        band_height: u32,
        glyph_map: std.AutoHashMap(u16, GlyphInfo),
    };

    /// Build curve/band textures and glyph map from a set of glyph IDs.
    fn buildTextureData(allocator: std.mem.Allocator, font: *const Font, glyph_id_set: *const std.AutoHashMap(u16, void)) !TextureResult {
        var cache = ttf.GlyphCache.init(allocator);
        defer cache.deinit();

        var glyph_curves_list: std.ArrayList(curve_tex.GlyphCurves) = .empty;
        defer glyph_curves_list.deinit(allocator);

        const GlyphMeta = struct { gid: u16, advance: u16, bbox: bezier.BBox };
        var glyph_infos: std.ArrayList(GlyphMeta) = .empty;
        defer glyph_infos.deinit(allocator);

        var seen_it = glyph_id_set.keyIterator();
        while (seen_it.next()) |gid_ptr| {
            const gid = gid_ptr.*;
            const glyph = font.inner.parseGlyph(allocator, &cache, gid) catch continue;

            var all_curves: std.ArrayList(bezier.QuadBezier) = .empty;
            defer all_curves.deinit(allocator);
            for (glyph.contours) |contour| {
                try all_curves.appendSlice(allocator, contour.curves);
            }

            const owned = try allocator.dupe(bezier.QuadBezier, all_curves.items);
            try glyph_curves_list.append(allocator, .{
                .curves = owned,
                .bbox = glyph.metrics.bbox,
            });
            try glyph_infos.append(allocator, .{
                .gid = gid,
                .advance = glyph.metrics.advance_width,
                .bbox = glyph.metrics.bbox,
            });
        }

        // Build curve texture
        var ct = try curve_tex.buildCurveTexture(allocator, glyph_curves_list.items);
        errdefer ct.texture.deinit();
        errdefer allocator.free(ct.entries);

        // Build band data
        var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
        defer {
            for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
            glyph_band_data.deinit(allocator);
        }
        for (glyph_curves_list.items, 0..) |gc, i| {
            var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.bbox, ct.entries[i]);
            try glyph_band_data.append(allocator, bd);
            _ = &bd;
        }

        var bt = try band_tex.buildBandTexture(allocator, glyph_band_data.items);
        errdefer bt.texture.deinit();
        errdefer allocator.free(bt.entries);

        // Build lookup map
        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
        for (glyph_infos.items, 0..) |info, i| {
            try glyph_map.put(info.gid, .{
                .bbox = info.bbox,
                .advance_width = info.advance,
                .band_entry = bt.entries[i],
            });
        }

        // Take ownership, free temp structures
        const curve_data = ct.texture.data;
        const band_data_owned = bt.texture.data;
        allocator.free(ct.entries);
        allocator.free(bt.entries);
        for (glyph_curves_list.items) |gc| allocator.free(gc.curves);

        return .{
            .curve_data = curve_data,
            .curve_width = ct.texture.width,
            .curve_height = ct.texture.height,
            .band_data = band_data_owned,
            .band_width = bt.texture.width,
            .band_height = bt.texture.height,
            .glyph_map = glyph_map,
        };
    }

    /// Build an atlas for the given codepoints.
    /// Thread-safe: uses its own GlyphCache internally.
    pub fn init(allocator: std.mem.Allocator, font: *const Font, codepoints: []const u32) !Atlas {
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        // Collect base glyphs
        for (codepoints) |cp| {
            const gid = font.inner.glyphIndex(cp) catch continue;
            if (gid == 0) continue;
            try seen.put(gid, {});
        }

        // Discover ligature output glyphs by scanning GSUB tables directly
        {
            const liga_glyphs = try opentype.discoverLigatureGlyphs(
                allocator, font.inner.data, font.inner.gsub_offset, &seen,
            );
            defer if (liga_glyphs.len > 0) allocator.free(liga_glyphs);
            for (liga_glyphs) |lg| try seen.put(lg, {});
        }

        const result = try buildTextureData(allocator, font, &seen);

        // Initialize OpenType shaper
        const shaper: ?opentype.Shaper = opentype.Shaper.init(
            allocator,
            font.inner.data,
            font.inner.gsub_offset,
            font.inner.gpos_offset,
        ) catch null;

        // Initialize HarfBuzz shaper (compile-time optional)
        const hb_shaper = if (comptime build_options.enable_harfbuzz)
            harfbuzz.HarfBuzzShaper.init(font.inner.data, font.unitsPerEm()) catch null
        else {};

        var atlas = Atlas{
            .allocator = allocator,
            .font = font,
            .curve_data = result.curve_data,
            .curve_width = result.curve_width,
            .curve_height = result.curve_height,
            .band_data = result.band_data,
            .band_width = result.band_width,
            .band_height = result.band_height,
            .glyph_map = result.glyph_map,
            .shaper = shaper,
            .hb_shaper = hb_shaper,
        };
        try atlas.buildGlyphLut();
        return atlas;
    }

    /// Build atlas from ASCII byte slice (convenience).
    pub fn initAscii(allocator: std.mem.Allocator, font: *const Font, chars: []const u8) !Atlas {
        var codepoints = try allocator.alloc(u32, chars.len);
        defer allocator.free(codepoints);
        for (chars, 0..) |ch, i| codepoints[i] = ch;
        return init(allocator, font, codepoints);
    }

    /// Add new codepoints to the atlas, rebuilding textures as needed.
    /// Returns true if new glyphs were added (caller must re-upload via
    /// Renderer.uploadAtlas). Returns false if all codepoints were already present.
    pub fn addCodepoints(self: *Atlas, new_codepoints: []const u32) !bool {
        const font = self.font orelse return error.NoFontAvailable;
        const allocator = self.allocator;

        // Collect all glyph IDs: existing + new
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        // Add existing glyphs
        var existing_it = self.glyph_map.keyIterator();
        while (existing_it.next()) |k| try seen.put(k.*, {});

        // Add new codepoints
        var added_any = false;
        for (new_codepoints) |cp| {
            const gid = font.inner.glyphIndex(cp) catch continue;
            if (gid == 0) continue;
            if (seen.contains(gid)) continue;
            try seen.put(gid, {});
            added_any = true;
        }

        if (!added_any) return false;

        // Discover ligature glyphs for the expanded set
        {
            const liga_glyphs = try opentype.discoverLigatureGlyphs(
                allocator, font.inner.data, font.inner.gsub_offset, &seen,
            );
            defer if (liga_glyphs.len > 0) allocator.free(liga_glyphs);
            for (liga_glyphs) |lg| try seen.put(lg, {});
        }

        // Re-parse all glyphs and rebuild textures
        const result = try buildTextureData(allocator, font, &seen);

        // Invalidate GPU textures (caller must re-upload)
        self.invalidateGpuTextures();

        // Free old data
        allocator.free(self.curve_data);
        allocator.free(self.band_data);
        self.glyph_map.deinit();

        // Install new data
        self.curve_data = result.curve_data;
        self.curve_width = result.curve_width;
        self.curve_height = result.curve_height;
        self.band_data = result.band_data;
        self.band_width = result.band_width;
        self.band_height = result.band_height;
        self.glyph_map = result.glyph_map;
        try self.buildGlyphLut();

        return true;
    }

    /// Discover glyphs needed for text via HarfBuzz shaping and add them
    /// to the atlas. Returns true if new glyphs were added.
    /// Requires -Dharfbuzz=true. Returns false if HarfBuzz is not available.
    pub fn addGlyphsForText(self: *Atlas, text: []const u8) !bool {
        if (comptime !build_options.enable_harfbuzz) return false;
        const hbs = self.hb_shaper orelse return false;

        const glyph_ids = try hbs.discoverGlyphs(self.allocator, text);
        defer if (glyph_ids.len > 0) self.allocator.free(glyph_ids);

        if (glyph_ids.len == 0) return false;

        const font = self.font orelse return error.NoFontAvailable;

        // Check if any are new
        var seen = std.AutoHashMap(u16, void).init(self.allocator);
        defer seen.deinit();

        var existing_it = self.glyph_map.keyIterator();
        while (existing_it.next()) |k| try seen.put(k.*, {});

        var added_any = false;
        for (glyph_ids) |gid| {
            if (!seen.contains(gid)) {
                try seen.put(gid, {});
                added_any = true;
            }
        }

        if (!added_any) return false;

        const result = try buildTextureData(self.allocator, font, &seen);

        self.invalidateGpuTextures();
        self.allocator.free(self.curve_data);
        self.allocator.free(self.band_data);
        self.glyph_map.deinit();

        self.curve_data = result.curve_data;
        self.curve_width = result.curve_width;
        self.curve_height = result.curve_height;
        self.band_data = result.band_data;
        self.band_width = result.band_width;
        self.band_height = result.band_height;
        self.glyph_map = result.glyph_map;
        try self.buildGlyphLut();

        return true;
    }

    /// Invalidate GPU textures (must re-upload after this).
    /// Build dense lookup table from glyph_map for O(1) glyph access.
    fn buildGlyphLut(self: *Atlas) !void {
        if (self.glyph_lut) |lut| self.allocator.free(lut);

        // Find max glyph ID
        var max_gid: u32 = 0;
        var it = self.glyph_map.keyIterator();
        while (it.next()) |k| {
            if (k.* > max_gid) max_gid = k.*;
        }

        const size = max_gid + 1;
        const lut = try self.allocator.alloc(GlyphInfo, size);
        // Zero-fill (h_band_count == 0 means absent)
        @memset(lut, std.mem.zeroes(GlyphInfo));

        var map_it = self.glyph_map.iterator();
        while (map_it.next()) |entry| {
            lut[entry.key_ptr.*] = entry.value_ptr.*;
        }

        self.glyph_lut = lut;
        self.glyph_lut_len = @intCast(size);
    }

    /// Fast glyph lookup: O(1) array access with HashMap fallback.
    pub fn getGlyph(self: *const Atlas, gid: u16) ?GlyphInfo {
        if (self.glyph_lut) |lut| {
            if (gid < self.glyph_lut_len) {
                const info = lut[gid];
                if (info.band_entry.h_band_count > 0) return info;
            }
            return null;
        }
        return self.glyph_map.get(gid);
    }

    fn invalidateGpuTextures(self: *Atlas) void {
        if (self.gl_curve_texture != 0) {
            pipeline.deleteTexture(&self.gl_curve_texture);
            pipeline.deleteTexture(&self.gl_band_texture);
        }
    }

    pub fn deinit(self: *Atlas) void {
        self.invalidateGpuTextures();
        if (self.glyph_lut) |lut| self.allocator.free(lut);
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
        if (self.shaper) |*s| @constCast(s).deinit();
        self.allocator.free(self.curve_data);
        self.allocator.free(self.band_data);
        self.glyph_map.deinit();
    }
};

/// Accumulates glyph vertices into a caller-provided buffer.
/// Zero allocations. Can be pre-built for static text.
pub const Batch = struct {
    buf: []f32,
    len: usize, // floats written

    pub fn init(buf: []f32) Batch {
        return .{ .buf = buf, .len = 0 };
    }

    pub fn reset(self: *Batch) void {
        self.len = 0;
    }

    pub fn glyphCount(self: *const Batch) usize {
        return self.len / FLOATS_PER_GLYPH;
    }

    pub fn slice(self: *const Batch) []const f32 {
        return self.buf[0..self.len];
    }

    /// Append a single glyph quad. Returns false if buffer is full.
    pub fn addGlyph(
        self: *Batch,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u8,
    ) bool {
        if (self.len + FLOATS_PER_GLYPH > self.buf.len) return false;
        vertex_mod.generateGlyphVertices(self.buf[self.len..], x, y, font_size, bbox, band_entry, color, atlas_layer);
        self.len += FLOATS_PER_GLYPH;
        return true;
    }

    /// A pre-shaped glyph with position. Produced by external shapers (HarfBuzz).
    pub const ShapedGlyph = struct {
        glyph_id: u16,
        x_offset: f32, // pixel offset from string origin
        y_offset: f32,
    };

    /// Append pre-shaped glyphs. Use this when text has been shaped externally
    /// (e.g. by HarfBuzz). Each glyph's position is relative to (x, y).
    /// Returns the number of glyphs successfully added.
    pub fn addShaped(
        self: *Batch,
        atlas: *const Atlas,
        glyphs: []const ShapedGlyph,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) usize {
        var count: usize = 0;
        for (glyphs) |sg| {
            const info = atlas.getGlyph(sg.glyph_id) orelse continue;
            if (info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0) {
                if (!self.addGlyph(x + sg.x_offset, y + sg.y_offset, font_size, info.bbox, info.band_entry, color, atlas.gl_layer)) break;
            }
            count += 1;
        }
        return count;
    }

    /// Lay out and append a string. Uses HarfBuzz for shaping when
    /// available (-Dharfbuzz=true), otherwise applies built-in ligature
    /// substitution and GPOS/kern kerning.
    /// Returns advance width in pixels.
    pub fn addString(
        self: *Batch,
        atlas: *const Atlas,
        font: *const Font,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) f32 {
        // Use HarfBuzz when available (zero-allocation path)
        if (comptime build_options.enable_harfbuzz) {
            if (atlas.hb_shaper) |hbs| {
                return hbs.shapeAndEmit(text, font_size, x, y, color, atlas, self, atlas.gl_layer);
            }
        }

        const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
        var cursor_x = x;

        // Convert UTF-8 text to glyph IDs
        var glyph_buf: [1024]u16 = undefined;
        var glyph_count: usize = 0;
        const view = std.unicode.Utf8View.initUnchecked(text);
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            if (glyph_count >= glyph_buf.len) break;
            glyph_buf[glyph_count] = font.glyphIndex(cp) catch 0;
            glyph_count += 1;
        }

        // Apply ligature substitution
        if (atlas.shaper) |shaper| {
            glyph_count = shaper.applyLigatures(glyph_buf[0..glyph_count]) catch glyph_count;
        }

        // Layout
        var prev_gid: u16 = 0;
        for (glyph_buf[0..glyph_count]) |gid| {
            if (gid == 0) {
                cursor_x += scale * 500;
                prev_gid = 0;
                continue;
            }

            // Kerning: prefer GPOS, fall back to kern table
            if (prev_gid != 0) {
                var kern: i16 = 0;
                if (atlas.shaper) |shaper| {
                    kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
                }
                if (kern == 0) {
                    kern = font.getKerning(prev_gid, gid) catch 0;
                }
                cursor_x += @as(f32, @floatFromInt(kern)) * scale;
            }

            const info = atlas.getGlyph(gid) orelse {
                cursor_x += scale * 500;
                prev_gid = gid;
                continue;
            };

            if (info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0) {
                if (!self.addGlyph(cursor_x, y, font_size, info.bbox, info.band_entry, color, atlas.gl_layer)) break;
            }

            cursor_x += @as(f32, @floatFromInt(info.advance_width)) * scale;
            prev_gid = gid;
        }

        return cursor_x - x;
    }

    /// Lay out a string with word wrapping at max_width pixels.
    /// Returns the total height used (from y downward).
    pub fn addStringWrapped(
        self: *Batch,
        atlas: *const Atlas,
        font: *const Font,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        max_width: f32,
        line_height: f32,
        color: [4]f32,
    ) f32 {
        var line_y = y;
        var remaining = text;

        while (remaining.len > 0) {
            // Find the longest prefix that fits in max_width
            var best_break: usize = 0;
            var last_space: usize = 0;
            var i: usize = 0;

            while (i < remaining.len) : (i += 1) {
                if (remaining[i] == ' ' or remaining[i] == '\t') {
                    last_space = i;
                }
                if (remaining[i] == '\n') {
                    best_break = i;
                    break;
                }
                // Measure up to this point
                const w = self.measureGlyphWidth(atlas, font, remaining[0 .. i + 1], font_size);
                if (w > max_width and i > 0) {
                    // Went over — break at last space, or force break here
                    best_break = if (last_space > 0) last_space else i;
                    break;
                }
                best_break = i + 1;
            }

            if (best_break == 0 and remaining.len > 0) best_break = 1;

            // Render this line
            _ = self.addString(atlas, font, remaining[0..best_break], x, line_y, font_size, color);
            line_y -= line_height;

            // Skip past break character
            if (best_break < remaining.len and (remaining[best_break] == ' ' or remaining[best_break] == '\n')) {
                remaining = remaining[best_break + 1 ..];
            } else {
                remaining = remaining[best_break..];
            }
        }

        return y - line_y;
    }

    /// Measure the advance width of a string without emitting vertices.
    fn measureGlyphWidth(
        self: *const Batch,
        atlas: *const Atlas,
        font: *const Font,
        text: []const u8,
        font_size: f32,
    ) f32 {
        _ = self;
        // Use HarfBuzz for measurement when available
        if (comptime build_options.enable_harfbuzz) {
            if (atlas.hb_shaper) |hbs| {
                return hbs.measureWidth(text, font_size);
            }
        }
        const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
        var width: f32 = 0;
        var prev_gid: u16 = 0;
        const view = std.unicode.Utf8View.initUnchecked(text);
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            const gid = font.glyphIndex(cp) catch 0;
            if (gid == 0) {
                width += scale * 500;
                prev_gid = 0;
                continue;
            }
            if (prev_gid != 0) {
                var kern: i16 = 0;
                if (atlas.shaper) |shaper| {
                    kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
                }
                if (kern == 0) {
                    kern = font.getKerning(prev_gid, gid) catch 0;
                }
                width += @as(f32, @floatFromInt(kern)) * scale;
            }
            const info = atlas.getGlyph(gid) orelse {
                width += scale * 500;
                prev_gid = gid;
                continue;
            };
            width += @as(f32, @floatFromInt(info.advance_width)) * scale;
            prev_gid = gid;
        }
        return width;
    }
};

pub const FillRule = pipeline.FillRule;

/// GPU renderer. Owns shader programs and texture handles.
/// Requires an active OpenGL 3.3+ context.
pub const Renderer = struct {
    _init: bool = true,

    pub fn init() !Renderer {
        try pipeline.init();
        return .{};
    }

    pub fn deinit(self: *Renderer) void {
        _ = self;
        pipeline.deinit();
    }

    /// Upload one or more atlases as a texture array.
    /// All atlases in the array can be rendered in a single draw call —
    /// the layer index is encoded in vertex data automatically.
    /// Call again after atlas data changes to rebuild the array.
    pub fn uploadAtlases(self: *Renderer, atlases: []const *const Atlas) void {
        _ = self;
        pipeline.buildTextureArrays(atlases);
    }

    /// Convenience: upload a single atlas (layer 0).
    pub fn uploadAtlas(self: *Renderer, atlas: *const Atlas) void {
        const arr = [1]*const Atlas{atlas};
        self.uploadAtlases(&arr);
    }

    /// Draw a batch of glyph vertices.
    pub fn draw(self: *Renderer, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        _ = self;
        pipeline.drawText(vertices, mvp, viewport_w, viewport_h);
    }

    /// Toggle subpixel LCD rendering.
    pub fn setSubpixel(self: *Renderer, enabled: bool) void {
        _ = self;
        pipeline.subpixel_enabled = enabled;
    }

    pub fn subpixelEnabled(self: *const Renderer) bool {
        _ = self;
        return pipeline.subpixel_enabled;
    }

    /// Set fill rule: non_zero (default, TrueType) or even_odd (PostScript/CFF).
    pub fn setFillRule(self: *Renderer, rule: FillRule) void {
        _ = self;
        pipeline.fill_rule = rule;
    }

    pub fn fillRule(self: *const Renderer) FillRule {
        _ = self;
        return pipeline.fill_rule;
    }

    pub fn backendName(self: *const Renderer) []const u8 {
        _ = self;
        return pipeline.getBackendName();
    }
};

/// Default ASCII printable character set (space through tilde).
pub const ASCII_PRINTABLE = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

test {
    _ = @import("math/vec.zig");
    _ = @import("math/bezier.zig");
    _ = @import("math/roots.zig");
    _ = @import("font/ttf.zig");
    _ = @import("render/curve_texture.zig");
    _ = @import("render/band_texture.zig");
    _ = @import("font/opentype.zig");
    _ = @import("font/snail_file.zig");
    _ = @import("c_api.zig");
    _ = @import("render/vertex.zig");
    _ = @import("torture_test.zig");
}
