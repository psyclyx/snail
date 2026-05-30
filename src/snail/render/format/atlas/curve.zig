const std = @import("std");

const band_tex = @import("../band_texture.zig");
const bezier = @import("../../../math/bezier.zig");
const build_options = @import("build_options");
const font_mod = @import("../../../font.zig");
const opentype = @import("../../../font/opentype.zig");
const page_mod = @import("page.zig");
const ttf = @import("../../../font/ttf.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("../../../font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const Font = font_mod.Font;
const AtlasPage = page_mod.AtlasPage;

/// Low-level immutable curve atlas snapshot. App text should normally use
/// TextAtlas; CurveAtlas exists for backend/resource plumbing and advanced
/// curve-page users.
pub const CurveAtlas = struct {
    allocator: std.mem.Allocator,
    font: ?*const Font, // null for .snail-loaded atlases
    pages: []*AtlasPage,

    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null, // dense lookup: glyph_lut[gid], h_band_count==0 means absent
    glyph_lut_len: u32 = 0,

    shaper: ?opentype.Shaper,

    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void = if (build_options.enable_harfbuzz) null else {},

    // COLRv0 lookup data — raw font bytes and table offsets, valid for program
    // lifetime (font data is @embedFile). Stored separately so COLR layers
    // can be resolved at render time without going through the potentially-stale
    // atlas.font pointer.
    colr_font_data: []const u8 = &.{},
    colr_offset: u32 = 0,
    cpal_offset: u32 = 0,

    // COLRv0 multi-layer info texture (RGBA32F, for single-pass compositing)
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,
    paint_image_records: ?[]?PaintImageRecord = null,

    pub const GlyphInfo = struct {
        bbox: bezier.BBox,
        advance_width: u16,
        base_curve_texel: u32 = 0,
        curve_count: u16 = 0,
        band_entry: band_tex.GlyphBandEntry,
        page_index: u16,
    };

    /// Pre-built multi-layer info for a COLRv0 base glyph.
    pub const ColrBaseInfo = struct {
        info_x: u16, // texel position in layer_info texture
        info_y: u16,
        layer_count: u16,
        union_bbox: bezier.BBox,
        page_index: u16,
    };

    pub const PaintImageRecord = @import("../../../atlas.zig").PaintImageRecord;

    pub const BuildPageResult = struct {
        page: *AtlasPage,
        glyph_map: std.AutoHashMap(u16, GlyphInfo),
    };

    fn releasePages(pages: []const *AtlasPage) void {
        for (pages) |atlas_page| atlas_page.release();
    }

    pub fn buildGlyphLut(self: *Atlas) !void {
        if (self.glyph_lut) |lut| self.allocator.free(lut);

        var max_gid: u32 = 0;
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* > max_gid) max_gid = entry.key_ptr.*;
        }

        const size = max_gid + 1;
        const lut = try self.allocator.alloc(GlyphInfo, size);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            lut[entry.key_ptr.*] = entry.value_ptr.*;
        }

        self.glyph_lut = lut;
        self.glyph_lut_len = @intCast(size);
    }

    fn initShaper(allocator: std.mem.Allocator, font: *const Font) ?opentype.Shaper {
        return opentype.Shaper.init(
            allocator,
            font.inner.data,
            font.inner.gsub_offset,
            font.inner.gpos_offset,
        ) catch null;
    }

    fn initHbShaper(font: *const Font) if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void {
        return if (comptime build_options.enable_harfbuzz)
            harfbuzz.HarfBuzzShaper.init(font.inner.data, font.unitsPerEm()) catch null
        else {};
    }

    pub fn initFromParts(
        allocator: std.mem.Allocator,
        font: ?*const Font,
        pages: []*AtlasPage,
        glyph_map: std.AutoHashMap(u16, GlyphInfo),
    ) !Atlas {
        var atlas = Atlas{
            .allocator = allocator,
            .font = font,
            .pages = pages,
            .glyph_map = glyph_map,
            .shaper = if (font) |f| initShaper(allocator, f) else null,
            .hb_shaper = if (font) |f| initHbShaper(f) else if (comptime build_options.enable_harfbuzz) null else {},
            .colr_font_data = if (font) |f| f.inner.data else &.{},
            .colr_offset = if (font) |f| f.inner.colr_offset else 0,
            .cpal_offset = if (font) |f| f.inner.cpal_offset else 0,
            .paint_image_records = null,
        };
        errdefer atlas.deinit();
        try atlas.buildGlyphLut();
        return atlas;
    }

    pub fn pageCount(self: *const Atlas) usize {
        return self.pages.len;
    }

    pub fn page(self: *const Atlas, page_index: u16) *const AtlasPage {
        return self.pages[page_index];
    }

    pub fn textureByteLen(self: *const Atlas) usize {
        var total: usize = 0;
        for (self.pages) |atlas_page| total += atlas_page.textureBytes();
        return total;
    }

    /// Return an iterator over the COLRv0 layers for a glyph.
    /// Uses colr_font_data/colr_offset/cpal_offset stored at init time —
    /// safe to call at render time even after the original Font pointer goes stale.
    fn makeColrFont(self: *const Atlas) ttf.Font {
        return .{ .data = self.colr_font_data, .colr_offset = self.colr_offset, .cpal_offset = self.cpal_offset };
    }

    pub fn colrLayers(self: *const Atlas, glyph_id: u16) ttf.Font.ColrLayerIterator {
        if (self.colr_offset == 0) return .{ .data = self.colr_font_data };
        return self.makeColrFont().colrLayers(glyph_id);
    }

    pub fn colrLayerCount(self: *const Atlas, glyph_id: u16) u16 {
        if (self.colr_offset == 0) return 0;
        return self.makeColrFont().colrLayerCount(glyph_id);
    }

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

    pub fn deinit(self: *Atlas) void {
        if (self.glyph_lut) |lut| self.allocator.free(lut);
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
        if (self.shaper) |*s| @constCast(s).deinit();
        if (self.layer_info_data) |lid| self.allocator.free(lid);
        if (self.colr_base_map) |*cbm| @constCast(cbm).deinit();
        if (self.paint_image_records) |records| self.allocator.free(records);
        releasePages(self.pages);
        self.allocator.free(self.pages);
        self.glyph_map.deinit();
    }
};

pub const Atlas = CurveAtlas;
