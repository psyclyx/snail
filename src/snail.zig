//! snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
//!
//! Usage:
//!   const font = try snail.Font.init(ttf_bytes);
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
const vector_vertex_mod = @import("render/vector_vertex.zig");
const pipeline = @import("render/pipeline.zig");
const vector_pipeline = @import("render/vector_pipeline.zig");
const vulkan_pipeline = if (build_options.enable_vulkan) @import("render/vulkan_pipeline.zig") else struct {
    pub const VulkanContext = void;
    pub fn init(_: anytype) !void {}
    pub fn deinit() void {}
    pub fn buildTextureArrays(_: anytype, _: anytype) void {}
    pub fn drawText(_: anytype, _: anytype, _: anytype, _: anytype) void {}
    pub fn drawVector(_: anytype, _: anytype, _: anytype, _: anytype) void {}
    pub fn setCommandBuffer(_: anytype) void {}
    pub fn getBackendName() []const u8 {
        return "vulkan (disabled)";
    }
    pub var subpixel_order: @import("render/subpixel_order.zig").SubpixelOrder = .none;
    pub var fill_rule: pipeline.FillRule = .non_zero;
};
pub const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

pub const Mat4 = vec.Mat4;
pub const Vec2 = vec.Vec2;
pub const BBox = bezier.BBox;
pub const GlyphMetrics = ttf.GlyphMetrics;
/// Font-wide line metrics from the `hhea` table, in font units.
pub const LineMetrics = ttf.LineMetrics;
pub const VectorTransform2D = vec.Transform2D;

// Re-export vertex constants for buffer sizing
pub const FLOATS_PER_VERTEX = vertex_mod.FLOATS_PER_VERTEX;
pub const VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const FLOATS_PER_GLYPH = FLOATS_PER_VERTEX * VERTICES_PER_GLYPH;
pub const VectorRect = vector_vertex_mod.Rect;
pub const VectorPrimitiveKind = vector_vertex_mod.PrimitiveKind;
pub const VECTOR_FLOATS_PER_VERTEX = vector_vertex_mod.FLOATS_PER_VERTEX;
pub const VECTOR_VERTICES_PER_PRIMITIVE = vector_vertex_mod.VERTICES_PER_PRIMITIVE;
pub const VECTOR_FLOATS_PER_PRIMITIVE = vector_vertex_mod.FLOATS_PER_PRIMITIVE;
pub const VECTOR_VERTICES_PER_ROUNDED_RECT = VECTOR_VERTICES_PER_PRIMITIVE;
pub const VECTOR_FLOATS_PER_ROUNDED_RECT = VECTOR_FLOATS_PER_PRIMITIVE;

pub const VectorFillStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32,
};

pub const VectorStrokeStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32,
    width: f32,
};

pub const VectorShape = union(enum) {
    rect: VectorRect,
    rounded_rect: struct {
        rect: VectorRect,
        corner_radius: f32,
    },
    ellipse: VectorRect,
};

pub const VectorPrimitive = struct {
    shape: VectorShape,
    fill: ?VectorFillStyle = null,
    stroke: ?VectorStrokeStyle = null,
    transform: VectorTransform2D = .identity,
};

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

    pub fn glyphMetrics(self: *const Font, glyph_id: u16) !GlyphMetrics {
        return self.inner.glyphMetrics(glyph_id);
    }

    /// Return ascent/descent/line_gap from the font `hhea` table, in font units.
    pub fn lineMetrics(self: *const Font) !LineMetrics {
        return self.inner.lineMetrics();
    }

    pub fn advanceWidth(self: *const Font, glyph_id: u16) !i16 {
        return self.inner.advanceWidth(glyph_id);
    }

    pub fn bbox(self: *const Font, glyph_id: u16) !BBox {
        return self.inner.bbox(glyph_id);
    }
};

fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}

/// Pre-built GPU texture data for a set of glyphs.
/// Create once, upload to Renderer, then use with Batch.
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
};

pub const Atlas = struct {
    allocator: std.mem.Allocator,
    font: ?*const Font, // null for .snail-loaded atlases
    pages: []*AtlasPage,

    // Per-glyph lookup (dense array indexed by glyph ID for O(1) access)
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null, // dense lookup: glyph_lut[gid], h_band_count==0 means absent
    glyph_lut_len: u32 = 0,

    // OpenType shaper (ligatures + GPOS kerning)
    shaper: ?opentype.Shaper,

    // HarfBuzz shaper (full OpenType, compile-time optional)
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void = if (build_options.enable_harfbuzz) null else {},

    // COLRv0 lookup data — raw font bytes and table offsets, valid for program
    // lifetime (font data is @embedFile). Stored separately so getColrLayers
    // can be called at render time without going through the potentially-stale
    // atlas.font pointer.
    colr_font_data: []const u8 = &.{},
    colr_offset: u32 = 0,
    cpal_offset: u32 = 0,

    // COLRv0 multi-layer info texture (RGBA32F, for single-pass compositing)
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,

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

    const BuildPageResult = struct {
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
    fn expandColrLayers(font: *const Font, allocator: std.mem.Allocator, seen: *std.AutoHashMap(u16, void)) !void {
        if (font.inner.colr_offset == 0) return;

        var keys: std.ArrayList(u16) = .empty;
        defer keys.deinit(allocator);
        var it = seen.keyIterator();
        while (it.next()) |k| try keys.append(allocator, k.*);

        for (keys.items) |gid| {
            var layer_it = font.inner.colrLayers(gid);
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
    fn buildPageData(
        allocator: std.mem.Allocator,
        font: *const Font,
        glyph_id_set: *const std.AutoHashMap(u16, void),
        page_index: u16,
    ) !BuildPageResult {
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

        var ct = try curve_tex.buildCurveTexture(allocator, glyph_curves_list.items);
        errdefer ct.texture.deinit();
        errdefer allocator.free(ct.entries);

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

        allocator.free(ct.entries);
        allocator.free(bt.entries);
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

        return .{
            .page = atlas_page,
            .glyph_map = glyph_map,
        };
    }

    fn buildGlyphLut(self: *Atlas) !void {
        if (self.glyph_lut) |lut| self.allocator.free(lut);

        var max_gid: u32 = 0;
        var it = self.glyph_map.keyIterator();
        while (it.next()) |k| {
            if (k.* > max_gid) max_gid = k.*;
        }

        const size = max_gid + 1;
        const lut = try self.allocator.alloc(GlyphInfo, size);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        var map_it = self.glyph_map.iterator();
        while (map_it.next()) |entry| {
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

    /// Convenience adapter for externally shaped glyph runs.
    pub fn extendShapedGlyphs(self: *const Atlas, glyphs: []const Batch.ShapedGlyph) !?Atlas {
        var requested = std.AutoHashMap(u16, void).init(self.allocator);
        defer requested.deinit();

        for (glyphs) |glyph| {
            if (glyph.glyph_id == 0) continue;
            try requested.put(glyph.glyph_id, {});
        }
        return self.extendGlyphIdSet(&requested);
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
    pub fn colrLayers(self: *const Atlas, glyph_id: u16) ttf.Font.ColrLayerIterator {
        if (self.colr_offset == 0) return .{ .data = self.colr_font_data };
        const temp = ttf.Font{ .data = self.colr_font_data, .colr_offset = self.colr_offset, .cpal_offset = self.cpal_offset };
        return temp.colrLayers(glyph_id);
    }

    pub fn colrLayerCount(self: *const Atlas, glyph_id: u16) u16 {
        if (self.colr_offset == 0) return 0;
        const temp = ttf.Font{ .data = self.colr_font_data, .colr_offset = self.colr_offset, .cpal_offset = self.cpal_offset };
        return temp.colrLayerCount(glyph_id);
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
        releasePages(self.pages);
        self.allocator.free(self.pages);
        self.glyph_map.deinit();
    }
};

pub const AtlasView = struct {
    atlas: *const Atlas,
    layer_base: u16 = 0,

    pub fn glyphLayer(self: *const AtlasView, page_index: u16) u8 {
        const layer = self.layer_base + page_index;
        std.debug.assert(layer < 256);
        return @intCast(layer);
    }
};

pub fn replaceAtlas(current: *Atlas, next: ?Atlas) bool {
    if (next) |replacement| {
        current.deinit();
        current.* = replacement;
        return true;
    }
    return false;
}

/// Accumulates glyph vertices into a caller-provided buffer.
/// Zero allocations. Can be pre-built for static text.
pub const Batch = struct {
    buf: []f32,
    len: usize, // floats written

    const glyph_stack_capacity = 256;
    const WrapBreak = struct {
        break_pos: usize,
        skip_len: usize,
    };

    const PreparedGlyphs = struct {
        slice: []const u16,
        owned: ?[]u16 = null,

        fn deinit(self: *const PreparedGlyphs, allocator: std.mem.Allocator) void {
            if (self.owned) |buf| allocator.free(buf);
        }
    };

    fn coerceAtlasView(atlas_like: anytype) AtlasView {
        const T = @TypeOf(atlas_like);
        return switch (T) {
            *const AtlasView, *AtlasView => atlas_like.*,
            *const Atlas, *Atlas => .{ .atlas = atlas_like, .layer_base = 0 },
            else => @compileError("expected *Atlas or *AtlasView"),
        };
    }

    fn prepareGlyphs(atlas: *const Atlas, font: *const Font, text: []const u8, stack_buf: []u16) ?PreparedGlyphs {
        if (text.len == 0) return .{ .slice = &.{} };

        var owned: ?[]u16 = null;
        const capacity = @max(text.len, 1);
        const buf = if (capacity <= stack_buf.len)
            stack_buf[0..capacity]
        else blk: {
            owned = atlas.allocator.alloc(u16, capacity) catch return null;
            break :blk owned.?;
        };

        var glyph_count: usize = 0;
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |cp| {
            buf[glyph_count] = font.glyphIndex(cp) catch 0;
            glyph_count += 1;
        }

        if (atlas.shaper) |shaper| {
            glyph_count = shaper.applyLigatures(buf[0..glyph_count]) catch glyph_count;
        }

        return .{
            .slice = buf[0..glyph_count],
            .owned = owned,
        };
    }

    fn sliceOffset(base: []const u8, part: []const u8) usize {
        return @intFromPtr(part.ptr) - @intFromPtr(base.ptr);
    }

    fn findForcedWrapBreak(
        self: *const Batch,
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        font_size: f32,
        max_width: f32,
    ) usize {
        if (text.len == 0) return 0;

        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        var best_break: usize = 0;
        var fallback_break: usize = text.len;

        while (it.nextCodepointSlice()) |cp_slice| {
            const end = sliceOffset(text, cp_slice) + cp_slice.len;
            if (best_break == 0) fallback_break = end;
            if (self.measureGlyphWidth(atlas_like, font, text[0..end], font_size) > max_width) break;
            best_break = end;
        }

        return if (best_break > 0) best_break else fallback_break;
    }

    fn findWrapBreak(
        self: *const Batch,
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        font_size: f32,
        max_width: f32,
    ) WrapBreak {
        if (text.len == 0) return .{ .break_pos = 0, .skip_len = 0 };

        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        var last_fit = WrapBreak{ .break_pos = 0, .skip_len = 0 };

        while (it.nextCodepointSlice()) |cp_slice| {
            const start = sliceOffset(text, cp_slice);
            const codepoint = std.unicode.utf8Decode(cp_slice) catch unreachable;
            if (codepoint != ' ' and codepoint != '\t') continue;
            if (start == 0) continue;

            if (self.measureGlyphWidth(atlas_like, font, text[0..start], font_size) > max_width) {
                if (last_fit.break_pos > 0) return last_fit;
                return .{
                    .break_pos = self.findForcedWrapBreak(atlas_like, font, text[0..start], font_size, max_width),
                    .skip_len = 0,
                };
            }

            last_fit = .{
                .break_pos = start,
                .skip_len = cp_slice.len,
            };
        }

        if (self.measureGlyphWidth(atlas_like, font, text, font_size) <= max_width) {
            return .{ .break_pos = text.len, .skip_len = 0 };
        }
        if (last_fit.break_pos > 0) return last_fit;

        return .{
            .break_pos = self.findForcedWrapBreak(atlas_like, font, text, font_size, max_width),
            .skip_len = 0,
        };
    }

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

    /// Append a multi-layer COLR glyph quad. Returns false if buffer is full.
    pub fn addColrGlyph(
        self: *Batch,
        x: f32,
        y: f32,
        font_size: f32,
        info: Atlas.ColrBaseInfo,
        color: [4]f32,
        atlas_layer: u8,
    ) bool {
        if (self.len + FLOATS_PER_GLYPH > self.buf.len) return false;
        vertex_mod.generateMultiLayerGlyphVertices(
            self.buf[self.len..],
            x,
            y,
            font_size,
            info.union_bbox,
            info.info_x,
            info.info_y,
            info.layer_count,
            color,
            atlas_layer,
        );
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
        atlas_like: anytype,
        glyphs: []const ShapedGlyph,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) usize {
        const resolved_view = coerceAtlasView(atlas_like);
        const view = &resolved_view;
        const atlas = view.atlas;
        var count: usize = 0;
        for (glyphs) |sg| {
            // Multi-layer COLR path: single quad per emoji
            if (atlas.colr_base_map) |cbm| {
                if (cbm.get(sg.glyph_id)) |cbi| {
                    if (!self.addColrGlyph(x + sg.x_offset, y + sg.y_offset, font_size, cbi, color, view.glyphLayer(cbi.page_index))) break;
                    count += 1;
                    continue;
                }
            }
            // Fallback: per-layer expansion (for atlases without layer info)
            var layer_it = atlas.colrLayers(sg.glyph_id);
            if (layer_it.count() > 0) {
                while (layer_it.next()) |layer| {
                    const linfo = atlas.getGlyph(layer.glyph_id) orelse continue;
                    if (linfo.band_entry.h_band_count > 0 and linfo.band_entry.v_band_count > 0) {
                        const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
                        if (!self.addGlyph(x + sg.x_offset, y + sg.y_offset, font_size, linfo.bbox, linfo.band_entry, lcolor, view.glyphLayer(linfo.page_index))) break;
                    }
                }
            } else {
                const info = atlas.getGlyph(sg.glyph_id) orelse {
                    count += 1;
                    continue;
                };
                if (info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0) {
                    if (!self.addGlyph(x + sg.x_offset, y + sg.y_offset, font_size, info.bbox, info.band_entry, color, view.glyphLayer(info.page_index))) break;
                }
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
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) f32 {
        const resolved_view = coerceAtlasView(atlas_like);
        const view = &resolved_view;
        const atlas = view.atlas;
        // Use HarfBuzz when available (zero-allocation path)
        if (comptime build_options.enable_harfbuzz) {
            if (atlas.hb_shaper) |hbs| {
                return hbs.shapeAndEmit(text, font_size, x, y, color, view, self);
            }
        }

        const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
        var cursor_x = x;
        var glyph_stack: [glyph_stack_capacity]u16 = undefined;
        var prepared = prepareGlyphs(atlas, font, text, &glyph_stack) orelse return 0;
        defer prepared.deinit(atlas.allocator);

        // Layout
        var prev_gid: u16 = 0;
        for (prepared.slice) |gid| {
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

            // COLRv0: single multi-layer quad (seamless compositing in shader)
            if (atlas.colr_base_map) |cbm| {
                if (cbm.get(gid)) |cbi| {
                    _ = self.addColrGlyph(cursor_x, y, font_size, cbi, color, view.glyphLayer(cbi.page_index));
                    const advance = if (atlas.glyph_map.get(gid)) |bi| bi.advance_width else font.inner.units_per_em;
                    cursor_x += @as(f32, @floatFromInt(advance)) * scale;
                    prev_gid = gid;
                    continue;
                }
            }
            // Fallback: per-layer expansion
            {
                var layer_it = font.inner.colrLayers(gid);
                if (layer_it.count() > 0) {
                    while (layer_it.next()) |layer| {
                        const linfo = atlas.getGlyph(layer.glyph_id) orelse continue;
                        if (linfo.band_entry.h_band_count > 0 and linfo.band_entry.v_band_count > 0) {
                            const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
                            _ = self.addGlyph(cursor_x, y, font_size, linfo.bbox, linfo.band_entry, lcolor, view.glyphLayer(linfo.page_index));
                        }
                    }
                    const advance = if (atlas.glyph_map.get(gid)) |bi| bi.advance_width else font.inner.units_per_em;
                    cursor_x += @as(f32, @floatFromInt(advance)) * scale;
                    prev_gid = gid;
                    continue;
                }
            }

            const info = atlas.getGlyph(gid) orelse {
                cursor_x += scale * 500;
                prev_gid = gid;
                continue;
            };

            if (info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0) {
                if (!self.addGlyph(cursor_x, y, font_size, info.bbox, info.band_entry, color, view.glyphLayer(info.page_index))) break;
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
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        max_width: f32,
        line_height: f32,
        color: [4]f32,
    ) f32 {
        const resolved_view = coerceAtlasView(atlas_like);
        const view = &resolved_view;
        var line_y = y;
        var remaining = text;

        while (remaining.len > 0) {
            const line_end = blk: {
                const utf8_view = std.unicode.Utf8View.initUnchecked(remaining);
                var it = utf8_view.iterator();
                while (it.nextCodepointSlice()) |cp_slice| {
                    const cp = std.unicode.utf8Decode(cp_slice) catch unreachable;
                    if (cp == '\n') break :blk sliceOffset(remaining, cp_slice);
                }
                break :blk remaining.len;
            };

            if (line_end == 0 and remaining.len > 0) {
                line_y -= line_height;
                remaining = remaining[1..];
                continue;
            }

            const break_info = self.findWrapBreak(view, font, remaining[0..line_end], font_size, max_width);
            if (break_info.break_pos == 0) break;

            _ = self.addString(view, font, remaining[0..break_info.break_pos], x, line_y, font_size, color);
            line_y -= line_height;

            const consumed = if (break_info.break_pos < line_end)
                break_info.break_pos + break_info.skip_len
            else if (line_end < remaining.len)
                line_end + 1
            else
                line_end;

            remaining = remaining[consumed..];
        }

        return y - line_y;
    }

    /// Measure the advance width of a string without emitting vertices.
    fn measureGlyphWidth(
        self: *const Batch,
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        font_size: f32,
    ) f32 {
        _ = self;
        const resolved_view = coerceAtlasView(atlas_like);
        const view = &resolved_view;
        const atlas = view.atlas;
        // Use HarfBuzz for measurement when available
        if (comptime build_options.enable_harfbuzz) {
            if (atlas.hb_shaper) |hbs| {
                return hbs.measureWidth(text, font_size);
            }
        }
        const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
        var width: f32 = 0;
        var prev_gid: u16 = 0;
        var glyph_stack: [glyph_stack_capacity]u16 = undefined;
        var prepared = prepareGlyphs(atlas, font, text, &glyph_stack) orelse return 0;
        defer prepared.deinit(atlas.allocator);

        for (prepared.slice) |gid| {
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

/// Accumulates vector primitives into a caller-provided buffer.
/// The public API is object-space and style-based; the packed buffer is the
/// low-level immediate format consumed by the renderer.
pub const VectorBatch = struct {
    buf: []f32,
    len: usize,

    pub fn init(buf: []f32) VectorBatch {
        return .{ .buf = buf, .len = 0 };
    }

    pub fn reset(self: *VectorBatch) void {
        self.len = 0;
    }

    pub fn shapeCount(self: *const VectorBatch) usize {
        return self.len / VECTOR_FLOATS_PER_PRIMITIVE;
    }

    pub fn slice(self: *const VectorBatch) []const f32 {
        return self.buf[0..self.len];
    }

    pub fn freeze(self: *const VectorBatch, allocator: std.mem.Allocator) !VectorPicture {
        return VectorPicture.initClone(allocator, self.slice());
    }

    fn addPackedPrimitive(
        self: *VectorBatch,
        kind: VectorPrimitiveKind,
        rect: VectorRect,
        fill: [4]f32,
        border: [4]f32,
        border_width: f32,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) bool {
        if (self.len + VECTOR_FLOATS_PER_PRIMITIVE > self.buf.len) return false;
        switch (kind) {
            .rect => vector_vertex_mod.generateRectVerticesTransformed(
                self.buf[self.len..],
                rect,
                fill,
                border,
                border_width,
                transform,
            ),
            .rounded_rect => vector_vertex_mod.generateRoundedRectVerticesTransformed(
                self.buf[self.len..],
                rect,
                fill,
                border,
                border_width,
                corner_radius,
                transform,
            ),
            .ellipse => vector_vertex_mod.generateEllipseVerticesTransformed(
                self.buf[self.len..],
                rect,
                fill,
                border,
                border_width,
                transform,
            ),
        }
        self.len += VECTOR_FLOATS_PER_PRIMITIVE;
        return true;
    }

    fn addStyledPrimitive(
        self: *VectorBatch,
        kind: VectorPrimitiveKind,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?VectorStrokeStyle,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) bool {
        const fill_color = if (fill) |style| style.color else [4]f32{ 0, 0, 0, 0 };
        const border_color = if (stroke) |style| style.color else [4]f32{ 0, 0, 0, 0 };
        const border_width = if (stroke) |style| style.width else 0;
        return self.addPackedPrimitive(kind, rect, fill_color, border_color, border_width, corner_radius, transform);
    }

    pub fn addPrimitive(self: *VectorBatch, primitive: VectorPrimitive) bool {
        return switch (primitive.shape) {
            .rect => |rect| self.addStyledPrimitive(.rect, rect, primitive.fill, primitive.stroke, 0, primitive.transform),
            .rounded_rect => |rr| self.addStyledPrimitive(.rounded_rect, rr.rect, primitive.fill, primitive.stroke, rr.corner_radius, primitive.transform),
            .ellipse => |rect| self.addStyledPrimitive(.ellipse, rect, primitive.fill, primitive.stroke, 0, primitive.transform),
        };
    }

    pub fn addRect(
        self: *VectorBatch,
        rect: VectorRect,
        fill: [4]f32,
        border: [4]f32,
        border_width: f32,
    ) bool {
        return self.addPackedPrimitive(.rect, rect, fill, border, border_width, 0, .identity);
    }

    pub fn addRectStyled(
        self: *VectorBatch,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?VectorStrokeStyle,
        transform: VectorTransform2D,
    ) bool {
        return self.addStyledPrimitive(.rect, rect, fill, stroke, 0, transform);
    }

    pub fn addRoundedRect(
        self: *VectorBatch,
        rect: VectorRect,
        fill: [4]f32,
        border: [4]f32,
        border_width: f32,
        corner_radius: f32,
    ) bool {
        return self.addPackedPrimitive(.rounded_rect, rect, fill, border, border_width, corner_radius, .identity);
    }

    pub fn addRoundedRectStyled(
        self: *VectorBatch,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?VectorStrokeStyle,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) bool {
        return self.addStyledPrimitive(.rounded_rect, rect, fill, stroke, corner_radius, transform);
    }

    pub fn addEllipse(
        self: *VectorBatch,
        rect: VectorRect,
        fill: [4]f32,
        border: [4]f32,
        border_width: f32,
    ) bool {
        return self.addPackedPrimitive(.ellipse, rect, fill, border, border_width, 0, .identity);
    }

    pub fn addEllipseStyled(
        self: *VectorBatch,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?VectorStrokeStyle,
        transform: VectorTransform2D,
    ) bool {
        return self.addStyledPrimitive(.ellipse, rect, fill, stroke, 0, transform);
    }
};

/// Immutable vector resource. Useful for static UI chrome or icons that should
/// be prepared once and drawn many times.
pub const VectorPicture = struct {
    allocator: std.mem.Allocator,
    vertices: []f32,

    pub fn initClone(allocator: std.mem.Allocator, vertices: []const f32) !VectorPicture {
        const owned = try allocator.alloc(f32, vertices.len);
        @memcpy(owned, vertices);
        return .{
            .allocator = allocator,
            .vertices = owned,
        };
    }

    pub fn deinit(self: *VectorPicture) void {
        self.allocator.free(self.vertices);
        self.* = undefined;
    }

    pub fn slice(self: *const VectorPicture) []const f32 {
        return self.vertices;
    }

    pub fn shapeCount(self: *const VectorPicture) usize {
        return self.vertices.len / VECTOR_FLOATS_PER_PRIMITIVE;
    }
};

pub const FillRule = pipeline.FillRule;
pub const SubpixelOrder = @import("render/subpixel_order.zig").SubpixelOrder;
pub const RenderBackend = enum { gl, vulkan };
pub const VulkanContext = vulkan_pipeline.VulkanContext;

/// GPU renderer. Owns shader programs and texture handles.
/// For OpenGL: requires an active GL 3.3+ context.
/// For Vulkan: requires a VulkanContext from the caller.
pub const Renderer = struct {
    backend: RenderBackend = .gl,

    /// Initialize with the current OpenGL context.
    pub fn init() !Renderer {
        try pipeline.init();
        try vector_pipeline.init();
        return .{ .backend = .gl };
    }

    /// Initialize with a Vulkan context (device, queue, render pass).
    pub fn initVulkan(vk_ctx: VulkanContext) !Renderer {
        try vulkan_pipeline.init(vk_ctx);
        return .{ .backend = .vulkan };
    }

    pub fn deinit(self: *Renderer) void {
        switch (self.backend) {
            .gl => {
                vector_pipeline.deinit();
                pipeline.deinit();
            },
            .vulkan => vulkan_pipeline.deinit(),
        }
    }

    /// Upload one or more immutable atlas snapshots as a texture array and
    /// return lightweight views that encode the texture-array base layer for
    /// each atlas. Existing glyph handles remain stable across extend because
    /// page-local indices do not change.
    pub fn uploadAtlases(self: *Renderer, atlases: []const *const Atlas, out_views: []AtlasView) void {
        std.debug.assert(atlases.len == out_views.len);
        switch (self.backend) {
            .gl => pipeline.buildTextureArrays(atlases, out_views),
            .vulkan => vulkan_pipeline.buildTextureArrays(atlases, out_views),
        }
    }

    /// Convenience: upload a single atlas and return its view.
    pub fn uploadAtlas(self: *Renderer, atlas: *const Atlas) AtlasView {
        const arr = [1]*const Atlas{atlas};
        var views = [1]AtlasView{undefined};
        self.uploadAtlases(&arr, &views);
        return views[0];
    }

    /// Reset cached GL state (program, textures). Call once per frame
    /// before draw() when other renderers share the GL context.
    pub fn beginFrame(self: *Renderer) void {
        switch (self.backend) {
            .gl => {
                pipeline.resetFrameState();
                vector_pipeline.resetFrameState();
            },
            .vulkan => {},
        }
    }

    /// Draw a batch of glyph vertices.
    pub fn draw(self: *Renderer, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        switch (self.backend) {
            .gl => pipeline.drawText(vertices, mvp, viewport_w, viewport_h),
            .vulkan => vulkan_pipeline.drawText(vertices, mvp, viewport_w, viewport_h),
        }
    }

    /// Draw vector primitives in pixel space with a top-left origin.
    pub fn drawVector(self: *Renderer, vertices: []const f32, viewport_w: f32, viewport_h: f32) void {
        self.drawVectorTransformed(vertices, Mat4.ortho(0, viewport_w, viewport_h, 0, -1, 1), viewport_w, viewport_h);
    }

    /// Draw vector primitives with an explicit object-to-clip transform.
    pub fn drawVectorTransformed(self: *Renderer, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        switch (self.backend) {
            .gl => {
                vector_pipeline.drawPrimitives(vertices, mvp);
                // Text pipeline caches GL state across draws; vector draws invalidate it.
                pipeline.resetFrameState();
            },
            .vulkan => vulkan_pipeline.drawVector(vertices, mvp, viewport_w, viewport_h),
        }
    }

    pub fn drawVectorPicture(self: *Renderer, picture: *const VectorPicture, viewport_w: f32, viewport_h: f32) void {
        self.drawVector(picture.slice(), viewport_w, viewport_h);
    }

    pub fn drawVectorPictureTransformed(self: *Renderer, picture: *const VectorPicture, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        self.drawVectorTransformed(picture.slice(), mvp, viewport_w, viewport_h);
    }

    /// Set the Vulkan command buffer for the current frame.
    /// Must be called before draw() when using Vulkan backend.
    pub fn setCommandBuffer(self: *Renderer, cmd: anytype) void {
        if (self.backend == .vulkan) vulkan_pipeline.setCommandBuffer(cmd);
    }

    /// Set LCD subpixel rendering order. Use .none to disable subpixel rendering.
    pub fn setSubpixelOrder(self: *Renderer, order: SubpixelOrder) void {
        switch (self.backend) {
            .gl => pipeline.subpixel_order = order,
            .vulkan => vulkan_pipeline.subpixel_order = order,
        }
    }

    pub fn subpixelOrder(self: *const Renderer) SubpixelOrder {
        return switch (self.backend) {
            .gl => pipeline.subpixel_order,
            .vulkan => vulkan_pipeline.subpixel_order,
        };
    }

    /// Convenience: enable subpixel with RGB order, or disable. Prefer setSubpixelOrder.
    pub fn setSubpixel(self: *Renderer, enabled: bool) void {
        self.setSubpixelOrder(if (enabled) .rgb else .none);
    }

    pub fn subpixelEnabled(self: *const Renderer) bool {
        return self.subpixelOrder() != .none;
    }

    /// Set fill rule: non_zero (default, TrueType) or even_odd (PostScript/CFF).
    pub fn setFillRule(self: *Renderer, rule: FillRule) void {
        switch (self.backend) {
            .gl => pipeline.fill_rule = rule,
            .vulkan => vulkan_pipeline.fill_rule = @enumFromInt(@intFromEnum(rule)),
        }
    }

    pub fn fillRule(self: *const Renderer) FillRule {
        return switch (self.backend) {
            .gl => pipeline.fill_rule,
            .vulkan => @enumFromInt(@intFromEnum(vulkan_pipeline.fill_rule)),
        };
    }

    pub fn backendName(self: *const Renderer) []const u8 {
        return switch (self.backend) {
            .gl => pipeline.getBackendName(),
            .vulkan => vulkan_pipeline.getBackendName(),
        };
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
    _ = @import("render/vector_vertex.zig");
    _ = @import("render/vector_pipeline.zig");
    _ = @import("torture_test.zig");
}

test "vector batch stores one rounded rect" {
    var buf: [VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = VectorBatch.init(&buf);

    try std.testing.expect(batch.addRoundedRect(
        .{ .x = 10, .y = 20, .w = 30, .h = 40 },
        .{ 1, 0, 0, 1 },
        .{ 0, 0, 0, 1 },
        2,
        6,
    ));
    try std.testing.expectEqual(@as(usize, 1), batch.shapeCount());
    try std.testing.expectEqual(@as(usize, VECTOR_FLOATS_PER_PRIMITIVE), batch.slice().len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), batch.slice()[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), batch.slice()[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), batch.slice()[12], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), batch.slice()[13], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), batch.slice()[14], 0.001);
}

test "vector batch rejects overflow" {
    var buf: [VECTOR_FLOATS_PER_PRIMITIVE - 1]f32 = undefined;
    var batch = VectorBatch.init(&buf);

    try std.testing.expect(!batch.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 10, .h = 10 },
        .{ 1, 1, 1, 1 },
        .{ 0, 0, 0, 1 },
        1,
        2,
    ));
    try std.testing.expectEqual(@as(usize, 0), batch.shapeCount());
    try std.testing.expectEqual(@as(usize, 0), batch.slice().len);
}

test "vector batch stores multiple primitive kinds" {
    var buf: [VECTOR_FLOATS_PER_PRIMITIVE * 3]f32 = undefined;
    var batch = VectorBatch.init(&buf);

    try std.testing.expect(batch.addRect(
        .{ .x = 0, .y = 0, .w = 20, .h = 10 },
        .{ 1, 1, 1, 1 },
        .{ 0, 0, 0, 0 },
        0,
    ));
    try std.testing.expect(batch.addEllipse(
        .{ .x = 5, .y = 5, .w = 12, .h = 12 },
        .{ 0, 1, 0, 1 },
        .{ 0, 0, 0, 1 },
        1,
    ));
    try std.testing.expectEqual(@as(usize, 2), batch.shapeCount());
    try std.testing.expectApproxEqAbs(@as(f32, 0), batch.slice()[12], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), batch.slice()[VECTOR_FLOATS_PER_PRIMITIVE + 12], 0.001);
}

test "vector batch stores styled primitive transform" {
    var buf: [VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = VectorBatch.init(&buf);
    const primitive = VectorPrimitive{
        .shape = .{
            .rounded_rect = .{
                .rect = .{ .x = 8, .y = 12, .w = 30, .h = 18 },
                .corner_radius = 5,
            },
        },
        .fill = .{ .color = .{ 0.1, 0.2, 0.3, 0.4 } },
        .stroke = .{ .color = .{ 0.9, 0.8, 0.7, 1.0 }, .width = 2.5 },
        .transform = .{ .xx = 1, .xy = 2, .tx = 3, .yx = 4, .yy = 5, .ty = 6 },
    };
    try std.testing.expect(batch.addPrimitive(primitive));
    try std.testing.expectApproxEqAbs(@as(f32, 3), batch.slice()[18], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), batch.slice()[22], 0.001);
}

test "vector batch can freeze into immutable picture" {
    var buf: [VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = VectorBatch.init(&buf);
    try std.testing.expect(batch.addRect(
        .{ .x = 0, .y = 0, .w = 20, .h = 10 },
        .{ 1, 1, 1, 1 },
        .{ 0, 0, 0, 0 },
        0,
    ));

    var picture = try batch.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(batch.slice().len, picture.slice().len);
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
}

test "addStringWrapped preserves blank lines" {
    const assets = @import("assets");

    var font = try Font.init(assets.noto_sans_regular);
    var atlas = try Atlas.initAscii(std.testing.allocator, &font, &ASCII_PRINTABLE);
    defer atlas.deinit();

    var buf: [128 * FLOATS_PER_GLYPH]f32 = undefined;
    var batch = Batch.init(&buf);
    const height = batch.addStringWrapped(&atlas, &font, "A\n\nB", 0, 100, 16, 200, 10, .{ 1, 1, 1, 1 });

    try std.testing.expectApproxEqAbs(@as(f32, 30), height, 0.001);
    try std.testing.expectEqual(@as(usize, 2), batch.glyphCount());
}

test "addStringWrapped forces UTF-8 breaks on codepoint boundaries" {
    const assets = @import("assets");

    var font = try Font.init(assets.noto_sans_regular);
    var atlas = try Atlas.init(std.testing.allocator, &font, &[_]u32{0x00E9});
    defer atlas.deinit();

    var buf: [128 * FLOATS_PER_GLYPH]f32 = undefined;
    var batch = Batch.init(&buf);
    const height = batch.addStringWrapped(&atlas, &font, "\xc3\xa9\xc3\xa9", 0, 40, 16, 0.01, 10, .{ 1, 1, 1, 1 });

    try std.testing.expectApproxEqAbs(@as(f32, 20), height, 0.001);
    try std.testing.expectEqual(@as(usize, 2), batch.glyphCount());
}

test "Font.lineMetrics forwards parser metrics" {
    const assets = @import("assets");

    var font = try Font.init(assets.noto_sans_regular);
    const metrics = try font.lineMetrics();

    try std.testing.expect(metrics.ascent > 0);
    try std.testing.expect(metrics.descent < 0);
    try std.testing.expect(metrics.line_gap >= 0);
}
