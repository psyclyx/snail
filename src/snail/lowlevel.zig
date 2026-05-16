const std = @import("std");

const band_tex = @import("renderer/band_texture.zig");
const bezier = @import("math/bezier.zig");
const build_options = @import("build_options");
const curve_tex = @import("renderer/curve_texture.zig");
const glyph_emit = @import("glyph_emit.zig");
const fonts_mod = @import("fonts.zig");
const image_mod = @import("image.zig");
const opentype = @import("font/opentype.zig");
const scene_mod = @import("scene.zig");
const text_mod = @import("text.zig");
const ttf = @import("font/ttf.zig");
const vertex_mod = @import("renderer/vertex.zig");
const vec = @import("math/vec.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const CurveSegment = bezier.CurveSegment;
const Font = text_mod.Font;
const Image = image_mod.Image;
const TextDraw = scene_mod.TextDraw;
const Transform2D = vec.Transform2D;
const isRenderableTextCodepoint = text_mod.isRenderableTextCodepoint;

pub const TEXT_WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = TEXT_WORDS_PER_VERTEX * TEXT_VERTICES_PER_GLYPH;

pub const TEXTURE_LAYER_WINDOW_SIZE: u32 = 255;

pub fn textureLayerWindowBase(layer: u32) u32 {
    return (layer / TEXTURE_LAYER_WINDOW_SIZE) * TEXTURE_LAYER_WINDOW_SIZE;
}

pub fn textureLayerLocal(layer: u32) !u8 {
    const base = textureLayerWindowBase(layer);
    const local = layer - base;
    if (local >= TEXTURE_LAYER_WINDOW_SIZE) return error.TextureLayerWindowOverflow;
    return @intCast(local);
}

pub const PreparedTextAtlasView = struct {
    layer_base: u32 = 0,
    info_row_base: u32 = 0,
    paint_info_row_base: u32 = 0,
};

pub const PreparedImageView = struct {
    image: *const Image,
    layer: u32 = 0,
    uv_scale: vec.Vec2 = .{ .x = 1.0, .y = 1.0 },
};

pub const AtlasPage = struct {
    allocator: std.mem.Allocator,
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    curve_data: []u16,
    curve_width: u32,
    curve_height: u32,
    band_data: []u16,
    band_width: u32,
    band_height: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        curve_data: []u16,
        curve_width: u32,
        curve_height: u32,
        band_data: []u16,
        band_width: u32,
        band_height: u32,
    ) !*AtlasPage {
        const page = try allocator.create(AtlasPage);
        page.* = .{
            .allocator = allocator,
            .curve_data = curve_data,
            .curve_width = curve_width,
            .curve_height = curve_height,
            .band_data = band_data,
            .band_width = band_width,
            .band_height = band_height,
        };
        return page;
    }

    pub fn retain(self: *AtlasPage) *AtlasPage {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *AtlasPage) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) {
            self.allocator.free(self.curve_data);
            self.allocator.free(self.band_data);
            self.allocator.destroy(self);
        }
    }

    pub fn textureBytes(self: *const AtlasPage) usize {
        return self.curve_data.len * @sizeOf(u16) + self.band_data.len * @sizeOf(u16);
    }

    pub fn curveTextureBytes(self: *const AtlasPage) usize {
        return self.curve_data.len * @sizeOf(u16);
    }

    pub fn bandTextureBytes(self: *const AtlasPage) usize {
        return self.band_data.len * @sizeOf(u16);
    }
};

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

    pub const PaintImageRecord = struct {
        image: *const Image,
        texel_offset: u32,
    };

    pub const BuildPageResult = struct {
        page: *AtlasPage,
        glyph_map: std.AutoHashMap(u16, GlyphInfo),
    };

    fn clonePages(allocator: std.mem.Allocator, pages: []const *AtlasPage) ![]*AtlasPage {
        const out = try allocator.alloc(*AtlasPage, pages.len);
        errdefer allocator.free(out);
        for (pages, 0..) |atlas_page, i| out[i] = atlas_page.retain();
        return out;
    }

    fn releasePages(pages: []const *AtlasPage) void {
        for (pages) |atlas_page| atlas_page.release();
    }

    fn collectGlyphIds(map: *const std.AutoHashMap(u16, GlyphInfo), allocator: std.mem.Allocator) !std.AutoHashMap(u16, void) {
        var seen = std.AutoHashMap(u16, void).init(allocator);
        errdefer seen.deinit();

        var it = map.keyIterator();
        while (it.next()) |gid_ptr| try seen.put(gid_ptr.*, {});
        return seen;
    }

    fn cloneWithAppendedGlyphs(self: *const Atlas, new_only: *const std.AutoHashMap(u16, void)) !?Atlas {
        const font = self.font orelse return error.NoFontAvailable;
        if (new_only.count() == 0) return null;

        // `page_index` is u16 in the on-GPU vertex encoding (`Shape` /
        // `GlyphPlacement`); reject growth past that rather than panic on
        // narrowing.
        if (self.pages.len >= std.math.maxInt(u16)) return error.AtlasPageLimitExceeded;
        const new_page_index: u16 = @intCast(self.pages.len);
        const page_result = try buildPageData(self.allocator, font, new_only, new_page_index);
        errdefer {
            page_result.page.release();
            var page_map = page_result.glyph_map;
            page_map.deinit();
        }

        const pages = try self.allocator.alloc(*AtlasPage, self.pages.len + 1);
        errdefer self.allocator.free(pages);
        for (self.pages, 0..) |atlas_page, i| pages[i] = atlas_page.retain();
        pages[self.pages.len] = page_result.page;

        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(self.allocator);
        errdefer glyph_map.deinit();
        var existing = self.glyph_map.iterator();
        while (existing.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);
        var appended = page_result.glyph_map.iterator();
        while (appended.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        const next = try initFromParts(self.allocator, font, pages, glyph_map);
        var page_map = page_result.glyph_map;
        page_map.deinit();
        return next;
    }

    fn extendGlyphIdSet(self: *const Atlas, requested: *const std.AutoHashMap(u16, void)) !?Atlas {
        const font = self.font orelse return error.NoFontAvailable;

        var seen = try collectGlyphIds(&self.glyph_map, self.allocator);
        defer seen.deinit();

        var added_any = false;
        var requested_it = requested.keyIterator();
        while (requested_it.next()) |gid_ptr| {
            const gid = gid_ptr.*;
            if (gid == 0 or seen.contains(gid)) continue;
            try seen.put(gid, {});
            added_any = true;
        }
        if (!added_any) return null;

        try expandColrLayers(font, self.allocator, &seen);

        var new_only = std.AutoHashMap(u16, void).init(self.allocator);
        defer new_only.deinit();
        var seen_it = seen.keyIterator();
        while (seen_it.next()) |gid_ptr| {
            if (!self.glyph_map.contains(gid_ptr.*)) try new_only.put(gid_ptr.*, {});
        }
        return self.cloneWithAppendedGlyphs(&new_only);
    }

    /// Expand a glyph-ID set with the COLRv0 layer glyphs of every base glyph
    /// already in the set. Must be called before buildTextureData so the layer
    /// glyphs get their own atlas entries (they are rendered independently with
    /// per-layer palette colors). No-op when the font has no COLR table.
    pub fn expandColrLayers(font: *const Font, allocator: std.mem.Allocator, seen: *std.AutoHashMap(u16, void)) !void {
        try expandColrLayersInner(&font.inner, allocator, seen);
    }

    pub fn expandColrLayersInner(font: *const ttf.Font, allocator: std.mem.Allocator, seen: *std.AutoHashMap(u16, void)) !void {
        if (font.colr_offset == 0) return;

        var keys: std.ArrayList(u16) = .empty;
        defer keys.deinit(allocator);
        var it = seen.keyIterator();
        while (it.next()) |k| try keys.append(allocator, k.*);

        for (keys.items) |gid| {
            var layer_it = font.colrLayers(gid);
            while (layer_it.next()) |layer| try seen.put(layer.glyph_id, {});
        }
    }

    /// Build a layer info texture and base-glyph map for single-pass COLR compositing.
    /// Must be called after page construction (needs per-layer GlyphInfo entries).
    fn buildColrLayerInfo(
        self: *Atlas,
        font: *const Font,
        allocator: std.mem.Allocator,
    ) !void {
        if (font.inner.colr_offset == 0) return;

        const TEX_WIDTH: u32 = 4096;

        var base_glyphs: std.ArrayList(u16) = .empty;
        defer base_glyphs.deinit(allocator);

        var map_it = self.glyph_map.keyIterator();
        while (map_it.next()) |gid_ptr| {
            if (font.inner.colrLayerCount(gid_ptr.*) > 0) try base_glyphs.append(allocator, gid_ptr.*);
        }
        if (base_glyphs.items.len == 0) return;

        var total_texels: u32 = 0;
        for (base_glyphs.items) |gid| {
            const layer_count = font.inner.colrLayerCount(gid);
            if (layer_count > 0) total_texels += @as(u32, layer_count) * 3;
        }
        if (total_texels == 0) return;

        const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
        const data = try allocator.alloc(f32, TEX_WIDTH * height * 4);
        @memset(data, 0);

        var colr_map = std.AutoHashMap(u16, ColrBaseInfo).init(allocator);
        errdefer colr_map.deinit();

        var texel_offset: u32 = 0;
        for (base_glyphs.items) |gid| {
            const layer_count = font.inner.colrLayerCount(gid);
            if (layer_count == 0) continue;

            const info_x: u16 = @intCast(texel_offset % TEX_WIDTH);
            const info_y: u16 = @intCast(texel_offset / TEX_WIDTH);

            var union_bbox = bezier.BBox{
                .min = .{ .x = std.math.inf(f32), .y = std.math.inf(f32) },
                .max = .{ .x = -std.math.inf(f32), .y = -std.math.inf(f32) },
            };

            var layer_page_index: ?u16 = null;
            var layers_share_page = true;

            var bounds_it = font.inner.colrLayers(gid);
            while (bounds_it.next()) |layer| {
                const linfo = self.glyph_map.get(layer.glyph_id) orelse {
                    layers_share_page = false;
                    continue;
                };
                if (layer_page_index) |expected| {
                    if (expected != linfo.page_index) layers_share_page = false;
                } else {
                    layer_page_index = linfo.page_index;
                }
                union_bbox.min.x = @min(union_bbox.min.x, linfo.bbox.min.x);
                union_bbox.min.y = @min(union_bbox.min.y, linfo.bbox.min.y);
                union_bbox.max.x = @max(union_bbox.max.x, linfo.bbox.max.x);
                union_bbox.max.y = @max(union_bbox.max.y, linfo.bbox.max.y);
            }

            var layer_it = font.inner.colrLayers(gid);
            while (layer_it.next()) |layer| {
                const linfo = self.glyph_map.get(layer.glyph_id) orelse continue;
                const be = linfo.band_entry;

                const t0 = texel_offset;
                const t0_x = t0 % TEX_WIDTH;
                const t0_y = t0 / TEX_WIDTH;
                data[(t0_y * TEX_WIDTH + t0_x) * 4 + 0] = @floatFromInt(be.glyph_x);
                data[(t0_y * TEX_WIDTH + t0_x) * 4 + 1] = @floatFromInt(be.glyph_y);
                const band_packed: u32 = @as(u32, be.h_band_count - 1) | (@as(u32, be.v_band_count - 1) << 16);
                data[(t0_y * TEX_WIDTH + t0_x) * 4 + 2] = @bitCast(band_packed);
                data[(t0_y * TEX_WIDTH + t0_x) * 4 + 3] = @floatFromInt(linfo.page_index);

                const t1 = texel_offset + 1;
                const t1_x = t1 % TEX_WIDTH;
                const t1_y = t1 / TEX_WIDTH;
                data[(t1_y * TEX_WIDTH + t1_x) * 4 + 0] = be.band_scale_x;
                data[(t1_y * TEX_WIDTH + t1_x) * 4 + 1] = be.band_scale_y;
                data[(t1_y * TEX_WIDTH + t1_x) * 4 + 2] = be.band_offset_x;
                data[(t1_y * TEX_WIDTH + t1_x) * 4 + 3] = be.band_offset_y;

                const t2 = texel_offset + 2;
                const t2_x = t2 % TEX_WIDTH;
                const t2_y = t2 / TEX_WIDTH;
                data[(t2_y * TEX_WIDTH + t2_x) * 4 + 0] = layer.color[0];
                data[(t2_y * TEX_WIDTH + t2_x) * 4 + 1] = layer.color[1];
                data[(t2_y * TEX_WIDTH + t2_x) * 4 + 2] = layer.color[2];
                data[(t2_y * TEX_WIDTH + t2_x) * 4 + 3] = layer.color[3];

                texel_offset += 3;
            }

            if (!layers_share_page or layer_page_index == null) continue;

            try colr_map.put(gid, .{
                .info_x = info_x,
                .info_y = info_y,
                .layer_count = layer_count,
                .union_bbox = union_bbox,
                .page_index = layer_page_index.?,
            });
        }

        self.layer_info_data = data;
        self.layer_info_width = TEX_WIDTH;
        self.layer_info_height = height;
        self.colr_base_map = colr_map;
    }

    /// Build a single immutable page and glyph map from a set of glyph IDs.
    pub fn buildPageData(
        allocator: std.mem.Allocator,
        font: *const Font,
        glyph_id_set: *const std.AutoHashMap(u16, void),
        page_index: u16,
    ) !BuildPageResult {
        return buildPageDataInner(allocator, &font.inner, glyph_id_set, page_index);
    }

    pub fn buildPageDataInner(
        allocator: std.mem.Allocator,
        font: *const ttf.Font,
        glyph_id_set: *const std.AutoHashMap(u16, void),
        page_index: u16,
    ) !BuildPageResult {
        var cache = ttf.GlyphCache.init(allocator);
        defer cache.deinit();

        var glyph_curves_list: std.ArrayList(curve_tex.GlyphCurves) = .empty;
        errdefer for (glyph_curves_list.items) |gc| allocator.free(gc.curves);
        defer glyph_curves_list.deinit(allocator);

        const GlyphMeta = struct {
            gid: u16,
            advance: u16,
            bbox: bezier.BBox,
        };
        var glyph_infos: std.ArrayList(GlyphMeta) = .empty;
        defer glyph_infos.deinit(allocator);

        var seen_it = glyph_id_set.keyIterator();
        while (seen_it.next()) |gid_ptr| {
            const gid = gid_ptr.*;
            const glyph = font.parseGlyph(allocator, &cache, gid) catch continue;

            var all_curves: std.ArrayList(CurveSegment) = .empty;
            defer all_curves.deinit(allocator);
            for (glyph.contours) |contour| {
                for (contour.curves) |curve| {
                    try all_curves.append(allocator, CurveSegment.fromQuad(curve));
                }
            }

            const owned = try allocator.dupe(CurveSegment, all_curves.items);
            const render_bbox = blk: {
                const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, owned, .zero);
                defer allocator.free(prepared);
                if (prepared.len == 0) break :blk glyph.metrics.bbox;
                var prepared_bbox = prepared[0].boundingBox();
                for (prepared[1..]) |curve| prepared_bbox = prepared_bbox.merge(curve.boundingBox());
                break :blk glyph.metrics.bbox.merge(prepared_bbox);
            };
            try glyph_curves_list.append(allocator, .{
                .curves = owned,
                .bbox = render_bbox,
                .logical_curve_count = owned.len,
                .prefer_direct_encoding = true,
            });
            try glyph_infos.append(allocator, .{
                .gid = gid,
                .advance = glyph.metrics.advance_width,
                .bbox = render_bbox,
            });
        }

        var ct = try curve_tex.buildCurveTexture(allocator, allocator, glyph_curves_list.items);
        var ct_texture_owned = true;
        errdefer if (ct_texture_owned) ct.texture.deinit();
        defer allocator.free(ct.entries);

        var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
        defer {
            for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
            glyph_band_data.deinit(allocator);
        }
        for (glyph_curves_list.items, 0..) |gc, i| {
            var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.logical_curve_count, gc.bbox, ct.entries[i], gc.origin, gc.prefer_direct_encoding);
            try glyph_band_data.append(allocator, bd);
            _ = &bd;
        }

        var bt = try band_tex.buildBandTexture(allocator, allocator, glyph_band_data.items);
        var bt_texture_owned = true;
        errdefer if (bt_texture_owned) bt.texture.deinit();
        defer allocator.free(bt.entries);

        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        for (glyph_infos.items, 0..) |info, i| {
            try glyph_map.put(info.gid, .{
                .bbox = info.bbox,
                .advance_width = info.advance,
                .band_entry = bt.entries[i],
                .page_index = page_index,
            });
        }

        for (glyph_curves_list.items) |gc| allocator.free(gc.curves);

        const atlas_page = try AtlasPage.init(
            allocator,
            ct.texture.data,
            ct.texture.width,
            ct.texture.height,
            bt.texture.data,
            bt.texture.width,
            bt.texture.height,
        );
        ct_texture_owned = false;
        bt_texture_owned = false;

        return .{
            .page = atlas_page,
            .glyph_map = glyph_map,
        };
    }

    fn buildGlyphLut(self: *Atlas) !void {
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

        if (font) |f| try atlas.buildColrLayerInfo(f, allocator);
        try atlas.buildGlyphLut();
        return atlas;
    }

    /// Build an atlas snapshot for the given codepoints.
    pub fn init(allocator: std.mem.Allocator, font: *const Font, codepoints: []const u32) !Atlas {
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        for (codepoints) |cp| {
            const gid = font.inner.glyphIndex(cp) catch continue;
            if (gid == 0) continue;
            try seen.put(gid, {});
        }

        {
            const liga_glyphs = try opentype.discoverLigatureGlyphs(
                allocator,
                font.inner.data,
                font.inner.gsub_offset,
                &seen,
            );
            defer if (liga_glyphs.len > 0) allocator.free(liga_glyphs);
            for (liga_glyphs) |lg| try seen.put(lg, {});
        }

        try expandColrLayers(font, allocator, &seen);

        const page_result = try buildPageData(allocator, font, &seen, 0);
        errdefer {
            page_result.page.release();
            var map_copy = page_result.glyph_map;
            map_copy.deinit();
        }

        const pages = try allocator.alloc(*AtlasPage, 1);
        pages[0] = page_result.page;

        return initFromParts(allocator, font, pages, page_result.glyph_map);
    }

    pub fn initAscii(allocator: std.mem.Allocator, font: *const Font, chars: []const u8) !Atlas {
        var codepoints = try allocator.alloc(u32, chars.len);
        defer allocator.free(codepoints);
        for (chars, 0..) |ch, i| codepoints[i] = ch;
        return init(allocator, font, codepoints);
    }

    fn cloneRetained(self: *const Atlas) !Atlas {
        const pages = try clonePages(self.allocator, self.pages);
        errdefer {
            releasePages(pages);
            self.allocator.free(pages);
        }

        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(self.allocator);
        errdefer glyph_map.deinit();
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        return initFromParts(self.allocator, self.font, pages, glyph_map);
    }

    /// Return a new atlas snapshot with any missing glyph IDs appended as a new
    /// page. Existing glyph handles remain stable across extend.
    pub fn extendGlyphIds(self: *const Atlas, glyph_ids: []const u16) !?Atlas {
        var requested = std.AutoHashMap(u16, void).init(self.allocator);
        defer requested.deinit();

        for (glyph_ids) |gid| {
            if (gid == 0) continue;
            try requested.put(gid, {});
        }
        return self.extendGlyphIdSet(&requested);
    }

    /// Return a new atlas snapshot with any missing codepoints appended as a new page.
    /// Existing glyph handles remain stable across extend.
    pub fn extendCodepoints(self: *const Atlas, new_codepoints: []const u32) !?Atlas {
        const font = self.font orelse return error.NoFontAvailable;

        var seen = try collectGlyphIds(&self.glyph_map, self.allocator);
        defer seen.deinit();

        var requested = std.AutoHashMap(u16, void).init(self.allocator);
        defer requested.deinit();

        for (new_codepoints) |cp| {
            const gid = font.glyphIndex(cp) catch continue;
            if (gid == 0 or seen.contains(gid)) continue;
            try seen.put(gid, {});
            try requested.put(gid, {});
        }

        {
            const liga_glyphs = try opentype.discoverLigatureGlyphs(
                self.allocator,
                font.inner.data,
                font.inner.gsub_offset,
                &seen,
            );
            defer if (liga_glyphs.len > 0) self.allocator.free(liga_glyphs);
            for (liga_glyphs) |lg| {
                if (lg == 0 or self.glyph_map.contains(lg)) continue;
                try requested.put(lg, {});
            }
        }
        return self.extendGlyphIdSet(&requested);
    }

    /// Discover glyphs needed to render UTF-8 text and return a new atlas
    /// snapshot with any missing glyphs appended as a new page.
    ///
    /// When HarfBuzz is enabled, this uses full text shaping. Otherwise it
    /// falls back to codepoint-driven discovery plus built-in ligature loading.
    pub fn extendText(self: *const Atlas, text: []const u8) !?Atlas {
        if (comptime build_options.enable_harfbuzz) {
            return self.extendGlyphsForText(text);
        }

        var unique_codepoints = std.AutoHashMap(u32, void).init(self.allocator);
        defer unique_codepoints.deinit();

        const view = std.unicode.Utf8View.init(text) catch return null;
        var it = view.iterator();
        while (it.nextCodepoint()) |codepoint| {
            if (!isRenderableTextCodepoint(codepoint)) continue;
            try unique_codepoints.put(codepoint, {});
        }
        if (unique_codepoints.count() == 0) return null;

        var codepoints = try self.allocator.alloc(u32, unique_codepoints.count());
        defer self.allocator.free(codepoints);

        var index: usize = 0;
        var key_it = unique_codepoints.keyIterator();
        while (key_it.next()) |codepoint| : (index += 1) {
            codepoints[index] = codepoint.*;
        }

        return self.extendCodepoints(codepoints);
    }

    /// Discover glyphs needed for text via HarfBuzz shaping and return a new atlas
    /// snapshot with any missing glyphs appended as a new page.
    pub fn extendGlyphsForText(self: *const Atlas, text: []const u8) !?Atlas {
        if (comptime !build_options.enable_harfbuzz) return null;
        const hbs = self.hb_shaper orelse return null;
        _ = self.font orelse return error.NoFontAvailable;

        const glyph_ids = try hbs.discoverGlyphs(self.allocator, text);
        defer if (glyph_ids.len > 0) self.allocator.free(glyph_ids);
        return self.extendGlyphIds(glyph_ids);
    }

    /// Return a compacted atlas snapshot. Handles are stable across extend, but
    /// not guaranteed to remain valid across compact.
    pub fn compact(self: *const Atlas) !Atlas {
        if (self.pages.len <= 1) return self.cloneRetained();
        const font = self.font orelse return error.NoFontAvailable;

        var seen = try collectGlyphIds(&self.glyph_map, self.allocator);
        defer seen.deinit();

        const page_result = try buildPageData(self.allocator, font, &seen, 0);
        errdefer {
            page_result.page.release();
            var page_map = page_result.glyph_map;
            page_map.deinit();
        }

        const pages = try self.allocator.alloc(*AtlasPage, 1);
        pages[0] = page_result.page;

        const next = try initFromParts(self.allocator, font, pages, page_result.glyph_map);
        return next;
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

pub const PreparedAtlasView = struct {
    atlas: *const Atlas,
    layer_base: u32 = 0,
    info_row_base: u32 = 0,

    pub fn glyphLayer(self: *const PreparedAtlasView, page_index: u16) u32 {
        const layer = self.layer_base + page_index;
        return layer;
    }

    pub fn glyphLayerWindowBase(self: *const PreparedAtlasView, page_index: u16) u32 {
        return textureLayerWindowBase(self.glyphLayer(page_index));
    }

    pub fn layerInfoLoc(self: *const PreparedAtlasView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = @intCast(self.info_row_base + info_y),
        };
    }

    pub fn getGlyph(self: *const PreparedAtlasView, gid: u16) ?Atlas.GlyphInfo {
        return self.atlas.getGlyph(gid);
    }

    pub fn getColrBase(self: *const PreparedAtlasView, gid: u16) ?Atlas.ColrBaseInfo {
        if (self.atlas.colr_base_map) |cbm| return cbm.get(gid);
        return null;
    }

    pub fn colrLayers(self: *const PreparedAtlasView, gid: u16) ttf.Font.ColrLayerIterator {
        return self.atlas.colrLayers(gid);
    }
};

pub const PreparedLayerInfoUpload = struct {
    data: ?[]const f32 = null,
    width: u32 = 0,
    height: u32 = 0,
    paint_image_records: ?[]const ?Atlas.PaintImageRecord = null,
};

pub const PreparedLayerInfoView = struct {
    info_row_base: u32 = 0,
};

pub fn coerceAtlasHandle(atlas_like: anytype) PreparedAtlasView {
    const T = @TypeOf(atlas_like);
    return switch (T) {
        *const PreparedAtlasView, *PreparedAtlasView => atlas_like.*,
        *const Atlas, *Atlas => .{ .atlas = atlas_like, .layer_base = 0 },
        else => @compileError("expected *CurveAtlas or prepared atlas view"),
    };
}

/// Accumulates glyph vertices into a caller-provided buffer.
/// Zero allocations. Can be pre-built for static text.
pub const TextBatch = struct {
    buf: []u32,
    len: usize, // words written
    layer_window_base: ?u32 = null,

    pub fn init(buf: []u32) TextBatch {
        return .{ .buf = buf, .len = 0 };
    }

    pub fn reset(self: *TextBatch) void {
        self.len = 0;
        self.layer_window_base = null;
    }

    pub fn glyphCount(self: *const TextBatch) usize {
        return self.len / TEXT_WORDS_PER_GLYPH;
    }

    pub fn slice(self: *const TextBatch) []const u32 {
        return self.buf[0..self.len];
    }

    pub fn currentLayerWindowBase(self: *const TextBatch) u32 {
        return self.layer_window_base orelse 0;
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_glyph: usize,
        completed: bool,
        layer_window_base: u32,
    };

    /// Emit one slice of a `TextDraw` into this batch: the glyphs from
    /// `[start_glyph, draw.glyphs.end)` under `draw.instances[override_index]`.
    /// Returns where to resume; the caller is responsible for advancing
    /// across overrides and re-opening batches when full or when the
    /// texture layer window changes.
    pub fn addDraw(
        self: *TextBatch,
        view: anytype,
        draw: TextDraw,
        override_index: usize,
        start_glyph: usize,
    ) !AppendResult {
        return fonts_mod.appendTextDrawIntoBatch(self, view, draw, override_index, start_glyph);
    }

    fn localLayer(self: *TextBatch, atlas_layer: u32) !u8 {
        const base = textureLayerWindowBase(atlas_layer);
        if (self.layer_window_base) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base = base;
        }
        return textureLayerLocal(atlas_layer);
    }

    /// Append a single glyph quad.
    pub fn addGlyph(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.addGlyphTinted(x, y, font_size, bbox, band_entry, color, .{ 1, 1, 1, 1 }, atlas_layer);
    }

    pub fn addGlyphTinted(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        vertex_mod.generateGlyphVerticesTinted(self.buf[self.len..], x, y, font_size, bbox, band_entry, color, tint, local_layer);
        self.len += TEXT_WORDS_PER_GLYPH;
    }

    /// Append a multi-layer COLR glyph quad.
    pub fn addColrGlyph(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        atlas_layer: u32,
    ) !void {
        try self.addColrGlyphTinted(x, y, font_size, union_bbox, info_x, info_y, layer_count, color, .{ 1, 1, 1, 1 }, atlas_layer);
    }

    pub fn addColrGlyphTinted(
        self: *TextBatch,
        x: f32,
        y: f32,
        font_size: f32,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
    ) !void {
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        vertex_mod.generateMultiLayerGlyphVerticesTinted(
            self.buf[self.len..],
            x,
            y,
            font_size,
            union_bbox,
            info_x,
            info_y,
            layer_count,
            color,
            tint,
            local_layer,
        );
        self.len += TEXT_WORDS_PER_GLYPH;
    }

    /// Append a single glyph quad with a 2D transform.
    pub fn addGlyphTransformed(
        self: *TextBatch,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.addGlyphTransformedTinted(bbox, band_entry, color, .{ 1, 1, 1, 1 }, atlas_layer, transform);
    }

    pub fn addGlyphTransformedTinted(
        self: *TextBatch,
        bbox: bezier.BBox,
        band_entry: band_tex.GlyphBandEntry,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateGlyphVerticesTransformedTinted(self.buf[self.len..], bbox, band_entry, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += TEXT_WORDS_PER_GLYPH;
    }

    /// Append a multi-layer COLR glyph quad with a 2D transform.
    pub fn addColrGlyphTransformed(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        try self.addColrGlyphTransformedTinted(union_bbox, info_x, info_y, layer_count, color, .{ 1, 1, 1, 1 }, atlas_layer, transform);
    }

    pub fn addColrGlyphTransformedTinted(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateMultiLayerGlyphVerticesTransformedTinted(self.buf[self.len..], union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += TEXT_WORDS_PER_GLYPH;
    }

    pub fn addPathRecordTransformedTinted(
        self: *TextBatch,
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        tint: [4]f32,
        atlas_layer: u32,
        transform: Transform2D,
    ) !void {
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generatePathRecordVerticesTransformedTinted(self.buf[self.len..], union_bbox, info_x, info_y, layer_count, color, tint, local_layer, transform))
            return error.InvalidTransform;
        self.len += TEXT_WORDS_PER_GLYPH;
    }
};
