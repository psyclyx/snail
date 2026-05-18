const std = @import("std");

const band_tex = @import("../render/format/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const build_options = @import("build_options");
const config_mod = @import("config.zig");
const curve_tex = @import("../render/format/curve_texture.zig");
const font_mod = @import("../font.zig");
const opentype = @import("../font/opentype.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const atlas_page_mod = @import("../render/format/atlas/page.zig");
const render_abi = @import("../render/format/abi.zig");
const ttf = @import("../font/ttf.zig");

const Atlas = atlas_curve_mod.Atlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const ColrBaseInfo = Atlas.ColrBaseInfo;
const CurveSegment = bezier.CurveSegment;
const Font = font_mod.Font;
const GlyphInfo = Atlas.GlyphInfo;
pub const BuildPageResult = Atlas.BuildPageResult;
const isRenderableTextCodepoint = config_mod.isRenderableTextCodepoint;

pub fn initFromParts(
    allocator: std.mem.Allocator,
    font: *const Font,
    pages: []*AtlasPage,
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
) !Atlas {
    var atlas = try Atlas.initFromParts(allocator, font, pages, glyph_map);
    errdefer atlas.deinit();
    try buildColrLayerInfo(&atlas, font, allocator);
    return atlas;
}

fn freeGlyphCurveScratch(allocator: std.mem.Allocator, glyphs: []const curve_tex.GlyphCurves) void {
    for (glyphs) |gc| {
        allocator.free(gc.curves);
        if (gc.prepared_curves) |prepared_curves| allocator.free(@constCast(prepared_curves));
    }
}

const PageGlyphMeta = struct {
    gid: u16,
    advance: u16,
    bbox: bezier.BBox,
};

const COLR_LAYER_INFO_TEX_WIDTH: u32 = 4096;

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
    return cloneWithAppendedGlyphs(self, &new_only);
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

    var base_glyphs = try collectColrBaseGlyphs(self, font, allocator);
    defer base_glyphs.deinit(allocator);
    if (base_glyphs.items.len == 0) return;

    const total_texels = colrLayerInfoTexelCount(font, base_glyphs.items);
    if (total_texels == 0) return;

    const height = @max(1, (total_texels + COLR_LAYER_INFO_TEX_WIDTH - 1) / COLR_LAYER_INFO_TEX_WIDTH);
    const data = try allocator.alloc(f32, COLR_LAYER_INFO_TEX_WIDTH * height * 4);
    @memset(data, 0);

    var colr_map = std.AutoHashMap(u16, ColrBaseInfo).init(allocator);
    errdefer colr_map.deinit();

    try writeColrLayerInfoRecords(self, font, base_glyphs.items, data, &colr_map);

    self.layer_info_data = data;
    self.layer_info_width = COLR_LAYER_INFO_TEX_WIDTH;
    self.layer_info_height = height;
    self.colr_base_map = colr_map;
}

fn collectColrBaseGlyphs(self: *const Atlas, font: *const Font, allocator: std.mem.Allocator) !std.ArrayList(u16) {
    var base_glyphs: std.ArrayList(u16) = .empty;
    errdefer base_glyphs.deinit(allocator);
    var map_it = self.glyph_map.keyIterator();
    while (map_it.next()) |gid_ptr| {
        if (font.inner.colrLayerCount(gid_ptr.*) > 0) try base_glyphs.append(allocator, gid_ptr.*);
    }
    return base_glyphs;
}

fn colrLayerInfoTexelCount(font: *const Font, base_glyphs: []const u16) u32 {
    var total_texels: u32 = 0;
    for (base_glyphs) |gid| {
        const layer_count = font.inner.colrLayerCount(gid);
        if (layer_count > 0) total_texels += @as(u32, layer_count) * 3;
    }
    return total_texels;
}

fn writeColrLayerInfoRecords(
    self: *const Atlas,
    font: *const Font,
    base_glyphs: []const u16,
    data: []f32,
    colr_map: *std.AutoHashMap(u16, ColrBaseInfo),
) !void {
    var texel_offset: u32 = 0;
    for (base_glyphs) |gid| {
        const layer_count = font.inner.colrLayerCount(gid);
        if (layer_count == 0) continue;

        const info_x: u16 = @intCast(texel_offset % COLR_LAYER_INFO_TEX_WIDTH);
        const info_y: u16 = @intCast(texel_offset / COLR_LAYER_INFO_TEX_WIDTH);
        const base_info = colrBaseLayerInfo(self, font, gid);

        var layer_it = font.inner.colrLayers(gid);
        while (layer_it.next()) |layer| {
            const linfo = self.glyph_map.get(layer.glyph_id) orelse continue;
            writeColrLayerRecord(data, texel_offset, linfo, layer);
            texel_offset += 3;
        }

        if (!base_info.layers_share_page or base_info.page_index == null) continue;

        try colr_map.put(gid, .{
            .info_x = info_x,
            .info_y = info_y,
            .layer_count = layer_count,
            .union_bbox = base_info.union_bbox,
            .page_index = base_info.page_index.?,
        });
    }
}

const ColrBaseLayerInfo = struct {
    union_bbox: bezier.BBox,
    page_index: ?u16 = null,
    layers_share_page: bool = true,
};

fn colrBaseLayerInfo(self: *const Atlas, font: *const Font, gid: u16) ColrBaseLayerInfo {
    var out = ColrBaseLayerInfo{
        .union_bbox = .{
            .min = .{ .x = std.math.inf(f32), .y = std.math.inf(f32) },
            .max = .{ .x = -std.math.inf(f32), .y = -std.math.inf(f32) },
        },
    };

    var bounds_it = font.inner.colrLayers(gid);
    while (bounds_it.next()) |layer| {
        const linfo = self.glyph_map.get(layer.glyph_id) orelse {
            out.layers_share_page = false;
            continue;
        };
        if (out.page_index) |expected| {
            if (expected != linfo.page_index) out.layers_share_page = false;
        } else {
            out.page_index = linfo.page_index;
        }
        out.union_bbox.min.x = @min(out.union_bbox.min.x, linfo.bbox.min.x);
        out.union_bbox.min.y = @min(out.union_bbox.min.y, linfo.bbox.min.y);
        out.union_bbox.max.x = @max(out.union_bbox.max.x, linfo.bbox.max.x);
        out.union_bbox.max.y = @max(out.union_bbox.max.y, linfo.bbox.max.y);
    }
    return out;
}

fn writeColrLayerRecord(data: []f32, texel_offset: u32, linfo: GlyphInfo, layer: anytype) void {
    const be = linfo.band_entry;
    writeColrTexel(data, texel_offset, .{
        @floatFromInt(be.glyph_x),
        @floatFromInt(be.glyph_y),
        @bitCast(render_abi.packBandCounts(be.h_band_count, be.v_band_count)),
        @floatFromInt(linfo.page_index),
    });
    writeColrTexel(data, texel_offset + 1, .{
        be.band_scale_x,
        be.band_scale_y,
        be.band_offset_x,
        be.band_offset_y,
    });
    writeColrTexel(data, texel_offset + 2, layer.color);
}

fn writeColrTexel(data: []f32, texel: u32, value: [4]f32) void {
    const x = texel % COLR_LAYER_INFO_TEX_WIDTH;
    const y = texel / COLR_LAYER_INFO_TEX_WIDTH;
    const base: usize = @intCast((y * COLR_LAYER_INFO_TEX_WIDTH + x) * 4);
    data[base + 0] = value[0];
    data[base + 1] = value[1];
    data[base + 2] = value[2];
    data[base + 3] = value[3];
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
    var glyph_curves_owned = true;
    errdefer if (glyph_curves_owned) freeGlyphCurveScratch(allocator, glyph_curves_list.items);
    defer glyph_curves_list.deinit(allocator);

    var glyph_infos: std.ArrayList(PageGlyphMeta) = .empty;
    defer glyph_infos.deinit(allocator);

    var seen_it = glyph_id_set.keyIterator();
    while (seen_it.next()) |gid_ptr| {
        try appendGlyphCurvesForId(allocator, font, &cache, gid_ptr.*, &glyph_curves_list, &glyph_infos);
    }

    var ct = try curve_tex.buildCurveTexture(allocator, allocator, glyph_curves_list.items);
    var ct_texture_owned = true;
    errdefer if (ct_texture_owned) ct.texture.deinit();
    defer allocator.free(ct.entries);

    var glyph_band_data = try buildGlyphBandDataList(allocator, glyph_curves_list.items, ct.entries);
    defer deinitGlyphBandDataList(allocator, &glyph_band_data);

    var bt = try band_tex.buildBandTexture(allocator, allocator, glyph_band_data.items);
    var bt_texture_owned = true;
    errdefer if (bt_texture_owned) bt.texture.deinit();
    defer allocator.free(bt.entries);

    var glyph_map = try buildGlyphMap(allocator, glyph_infos.items, bt.entries, page_index);
    errdefer glyph_map.deinit();

    freeGlyphCurveScratch(allocator, glyph_curves_list.items);
    glyph_curves_owned = false;

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

fn appendGlyphCurvesForId(
    allocator: std.mem.Allocator,
    font: *const ttf.Font,
    cache: *ttf.GlyphCache,
    gid: u16,
    glyph_curves_list: *std.ArrayList(curve_tex.GlyphCurves),
    glyph_infos: *std.ArrayList(PageGlyphMeta),
) !void {
    const glyph = font.parseGlyph(allocator, cache, gid) catch return;
    var all_curves: std.ArrayList(CurveSegment) = .empty;
    defer all_curves.deinit(allocator);
    for (glyph.contours) |contour| {
        for (contour.curves) |curve| try all_curves.append(allocator, CurveSegment.fromQuad(curve));
    }

    const owned = try allocator.dupe(CurveSegment, all_curves.items);
    const prepared = curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, owned, .zero) catch |err| {
        allocator.free(owned);
        return err;
    };
    const render_bbox = glyphRenderBBox(glyph.metrics.bbox, prepared);
    glyph_curves_list.append(allocator, .{
        .curves = owned,
        .bbox = render_bbox,
        .logical_curve_count = owned.len,
        .prefer_direct_encoding = true,
        .prepared_curves = prepared,
    }) catch |err| {
        allocator.free(owned);
        allocator.free(prepared);
        return err;
    };
    try glyph_infos.append(allocator, .{
        .gid = gid,
        .advance = glyph.metrics.advance_width,
        .bbox = render_bbox,
    });
}

fn glyphRenderBBox(metrics_bbox: bezier.BBox, prepared: []const CurveSegment) bezier.BBox {
    if (prepared.len == 0) return metrics_bbox;
    var prepared_bbox = prepared[0].boundingBox();
    for (prepared[1..]) |curve| prepared_bbox = prepared_bbox.merge(curve.boundingBox());
    return metrics_bbox.merge(prepared_bbox);
}

fn buildGlyphBandDataList(
    allocator: std.mem.Allocator,
    glyph_curves: []const curve_tex.GlyphCurves,
    curve_entries: []const curve_tex.GlyphCurveEntry,
) !std.ArrayList(band_tex.GlyphBandData) {
    var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
    errdefer deinitGlyphBandDataList(allocator, &glyph_band_data);
    for (glyph_curves, 0..) |gc, i| {
        var bd = try band_tex.buildGlyphBandDataForGlyph(allocator, gc, curve_entries[i]);
        try glyph_band_data.append(allocator, bd);
        _ = &bd;
    }
    return glyph_band_data;
}

fn deinitGlyphBandDataList(allocator: std.mem.Allocator, glyph_band_data: *std.ArrayList(band_tex.GlyphBandData)) void {
    for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
    glyph_band_data.deinit(allocator);
}

fn buildGlyphMap(
    allocator: std.mem.Allocator,
    glyph_infos: []const PageGlyphMeta,
    band_entries: []const band_tex.GlyphBandEntry,
    page_index: u16,
) !std.AutoHashMap(u16, GlyphInfo) {
    var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
    errdefer glyph_map.deinit();
    for (glyph_infos, 0..) |info, i| {
        try glyph_map.put(info.gid, .{
            .bbox = info.bbox,
            .advance_width = info.advance,
            .band_entry = band_entries[i],
            .page_index = page_index,
        });
    }
    return glyph_map;
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
    return extendGlyphIdSet(self, &requested);
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
    return extendGlyphIdSet(self, &requested);
}

/// Discover glyphs needed to render UTF-8 text and return a new atlas
/// snapshot with any missing glyphs appended as a new page.
///
/// When HarfBuzz is enabled, this uses full text shaping. Otherwise it
/// falls back to codepoint-driven discovery plus built-in ligature loading.
pub fn extendText(self: *const Atlas, text: []const u8) !?Atlas {
    if (comptime build_options.enable_harfbuzz) {
        return extendGlyphsForText(self, text);
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

    return extendCodepoints(self, codepoints);
}

/// Discover glyphs needed for text via HarfBuzz shaping and return a new atlas
/// snapshot with any missing glyphs appended as a new page.
pub fn extendGlyphsForText(self: *const Atlas, text: []const u8) !?Atlas {
    if (comptime !build_options.enable_harfbuzz) return null;
    const hbs = self.hb_shaper orelse return null;
    _ = self.font orelse return error.NoFontAvailable;

    const glyph_ids = try hbs.discoverGlyphs(self.allocator, text);
    defer if (glyph_ids.len > 0) self.allocator.free(glyph_ids);
    return extendGlyphIds(self, glyph_ids);
}

/// Return a compacted atlas snapshot. Handles are stable across extend, but
/// not guaranteed to remain valid across compact.
pub fn compact(self: *const Atlas) !Atlas {
    if (self.pages.len <= 1) return cloneRetained(self);
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
