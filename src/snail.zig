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
const sprite_vertex_mod = @import("render/sprite_vertex.zig");
const pipeline = @import("render/pipeline.zig");
const sprite_pipeline = @import("render/sprite_pipeline.zig");
const vulkan_pipeline = if (build_options.enable_vulkan) @import("render/vulkan_pipeline.zig") else struct {
    pub const VulkanContext = void;
    pub fn init(_: anytype) !void {}
    pub fn deinit() void {}
    pub fn buildTextureArrays(_: anytype, _: anytype) void {}
    pub fn buildImageArray(_: anytype, _: anytype) void {}
    pub fn drawText(_: anytype, _: anytype, _: anytype, _: anytype) void {}
    pub fn drawTextGrayscale(_: anytype, _: anytype, _: anytype, _: anytype) void {}
    pub fn drawSprites(_: anytype, _: anytype, _: anytype, _: anytype) void {}
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
const CurveSegment = bezier.CurveSegment;
const ConicBezier = bezier.ConicBezier;
const CubicBezier = bezier.CubicBezier;
pub const GlyphMetrics = ttf.GlyphMetrics;
/// Font-wide line metrics from the `hhea` table, in font units.
pub const LineMetrics = ttf.LineMetrics;
pub const VectorTransform2D = vec.Transform2D;
pub const PATH_PAINT_INFO_WIDTH: u32 = 4096;
pub const PATH_PAINT_TEXELS_PER_RECORD: u32 = 6;
pub const PATH_PAINT_TAG_SOLID: f32 = -1.0;
pub const PATH_PAINT_TAG_LINEAR_GRADIENT: f32 = -2.0;
pub const PATH_PAINT_TAG_RADIAL_GRADIENT: f32 = -3.0;
pub const PATH_PAINT_TAG_IMAGE: f32 = -4.0;

// Re-export vertex constants for buffer sizing
pub const FLOATS_PER_VERTEX = vertex_mod.FLOATS_PER_VERTEX;
pub const VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const FLOATS_PER_GLYPH = FLOATS_PER_VERTEX * VERTICES_PER_GLYPH;
pub const SPRITE_FLOATS_PER_VERTEX = sprite_vertex_mod.FLOATS_PER_VERTEX;
pub const SPRITE_VERTICES_PER_SPRITE = sprite_vertex_mod.VERTICES_PER_SPRITE;
pub const SPRITE_FLOATS_PER_SPRITE = sprite_vertex_mod.FLOATS_PER_SPRITE;

pub const VectorRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const PathPaintExtend = enum(u8) {
    clamp = 0,
    repeat = 1,
    reflect = 2,
};

pub const ImageFilter = enum(u8) {
    linear = 0,
    nearest = 1,
};

pub const Image = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn initRgba8(allocator: std.mem.Allocator, width: u32, height: u32, pixels: []const u8) !Image {
        if (pixels.len != width * height * 4) return error.InvalidImageData;
        const owned = try allocator.dupe(u8, pixels);
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = owned,
        };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub const ImageView = struct {
    image: *const Image,
    layer: u16 = 0,
    uv_scale: Vec2 = .{ .x = 1.0, .y = 1.0 },
};

pub const SpriteUvRect = struct {
    u0: f32 = 0.0,
    v0: f32 = 0.0,
    u1: f32 = 1.0,
    v1: f32 = 1.0,
};

pub const SpriteAnchor = struct {
    x: f32 = 0.5,
    y: f32 = 0.5,

    pub const center = SpriteAnchor{};
    pub const top_left = SpriteAnchor{ .x = 0.0, .y = 0.0 };
    pub const top_right = SpriteAnchor{ .x = 1.0, .y = 0.0 };
    pub const bottom_left = SpriteAnchor{ .x = 0.0, .y = 1.0 };
    pub const bottom_right = SpriteAnchor{ .x = 1.0, .y = 1.0 };
};

pub const PathLinearGradient = struct {
    start: Vec2,
    end: Vec2,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: PathPaintExtend = .clamp,
};

pub const PathRadialGradient = struct {
    center: Vec2,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: PathPaintExtend = .clamp,
};

pub const PathImagePaint = struct {
    image: *const Image,
    uv_transform: VectorTransform2D = .identity,
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    extend_x: PathPaintExtend = .clamp,
    extend_y: PathPaintExtend = .clamp,
    filter: ImageFilter = .linear,
};

pub const PathPaint = union(enum) {
    solid: [4]f32,
    linear_gradient: PathLinearGradient,
    radial_gradient: PathRadialGradient,
    image: PathImagePaint,
};

pub const VectorFillStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint: ?PathPaint = null,
};

pub const VectorStrokeStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32,
    width: f32,
};

pub const PathStrokeCap = enum {
    butt,
    square,
    round,
};

pub const PathStrokeJoin = enum {
    miter,
    bevel,
    round,
};

pub const PathStrokeAlign = enum {
    center,
    inside,
};

pub const PathStrokeStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint: ?PathPaint = null,
    width: f32,
    cap: PathStrokeCap = .butt,
    join: PathStrokeJoin = .miter,
    miter_limit: f32 = 4.0,
    placement: PathStrokeAlign = .center,
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

            var all_curves: std.ArrayList(CurveSegment) = .empty;
            defer all_curves.deinit(allocator);
            for (glyph.contours) |contour| {
                for (contour.curves) |curve| {
                    try all_curves.append(allocator, CurveSegment.fromQuad(curve));
                }
            }

            const owned = try allocator.dupe(CurveSegment, all_curves.items);
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
        if (self.paint_image_records) |records| self.allocator.free(records);
        releasePages(self.pages);
        self.allocator.free(self.pages);
        self.glyph_map.deinit();
    }
};

pub const AtlasView = struct {
    atlas: *const Atlas,
    layer_base: u16 = 0,
    info_row_base: u16 = 0,

    pub fn glyphLayer(self: *const AtlasView, page_index: u16) u8 {
        const layer = self.layer_base + page_index;
        std.debug.assert(layer < 256);
        return @intCast(layer);
    }

    pub fn layerInfoLoc(self: *const AtlasView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = self.info_row_base + info_y,
        };
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
        union_bbox: bezier.BBox,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        color: [4]f32,
        atlas_layer: u8,
    ) bool {
        if (self.len + FLOATS_PER_GLYPH > self.buf.len) return false;
        vertex_mod.generateMultiLayerGlyphVertices(
            self.buf[self.len..],
            x,
            y,
            font_size,
            union_bbox,
            info_x,
            info_y,
            layer_count,
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
                    const info_loc = view.layerInfoLoc(cbi.info_x, cbi.info_y);
                    if (!self.addColrGlyph(
                        x + sg.x_offset,
                        y + sg.y_offset,
                        font_size,
                        cbi.union_bbox,
                        info_loc.x,
                        info_loc.y,
                        cbi.layer_count,
                        color,
                        view.glyphLayer(cbi.page_index),
                    )) break;
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
                    const info_loc = view.layerInfoLoc(cbi.info_x, cbi.info_y);
                    _ = self.addColrGlyph(
                        cursor_x,
                        y,
                        font_size,
                        cbi.union_bbox,
                        info_loc.x,
                        info_loc.y,
                        cbi.layer_count,
                        color,
                        view.glyphLayer(cbi.page_index),
                    );
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
pub const SpritePicture = struct {
    allocator: std.mem.Allocator,
    vertices: []f32,

    pub fn initClone(allocator: std.mem.Allocator, vertices: []const f32) !SpritePicture {
        const owned = try allocator.alloc(f32, vertices.len);
        @memcpy(owned, vertices);
        return .{
            .allocator = allocator,
            .vertices = owned,
        };
    }

    pub fn deinit(self: *SpritePicture) void {
        self.allocator.free(self.vertices);
        self.* = undefined;
    }

    pub fn slice(self: *const SpritePicture) []const f32 {
        return self.vertices;
    }

    pub fn spriteCount(self: *const SpritePicture) usize {
        return self.vertices.len / SPRITE_FLOATS_PER_SPRITE;
    }
};

pub const SpriteBatch = struct {
    buf: []f32,
    len: usize = 0,

    pub fn init(buf: []f32) SpriteBatch {
        return .{ .buf = buf };
    }

    pub fn reset(self: *SpriteBatch) void {
        self.len = 0;
    }

    pub fn spriteCount(self: *const SpriteBatch) usize {
        return self.len / SPRITE_FLOATS_PER_SPRITE;
    }

    pub fn slice(self: *const SpriteBatch) []const f32 {
        return self.buf[0..self.len];
    }

    pub fn freeze(self: *const SpriteBatch, allocator: std.mem.Allocator) !SpritePicture {
        return SpritePicture.initClone(allocator, self.slice());
    }

    fn coerceImageView(image_like: anytype) ImageView {
        const T = @TypeOf(image_like);
        return switch (T) {
            ImageView => image_like,
            *const ImageView, *ImageView => image_like.*,
            else => @compileError("expected ImageView or *ImageView"),
        };
    }

    pub fn addSprite(
        self: *SpriteBatch,
        image_like: anytype,
        position: Vec2,
        size: Vec2,
        tint: [4]f32,
    ) bool {
        return self.addSpriteTransformed(
            image_like,
            size,
            tint,
            .{},
            .linear,
            .center,
            VectorTransform2D.translate(position.x, position.y),
        );
    }

    pub fn addSpriteAt(
        self: *SpriteBatch,
        image_like: anytype,
        position: Vec2,
        size: Vec2,
        rotation_rad: f32,
        anchor: SpriteAnchor,
        tint: [4]f32,
        uv_rect: SpriteUvRect,
        filter: ImageFilter,
    ) bool {
        const transform = VectorTransform2D.multiply(
            VectorTransform2D.translate(position.x, position.y),
            VectorTransform2D.rotate(rotation_rad),
        );
        return self.addSpriteTransformed(image_like, size, tint, uv_rect, filter, anchor, transform);
    }

    pub fn addSpriteRect(
        self: *SpriteBatch,
        image_like: anytype,
        rect: VectorRect,
        tint: [4]f32,
        uv_rect: SpriteUvRect,
        filter: ImageFilter,
    ) bool {
        return self.addSpriteTransformed(
            image_like,
            .{ .x = rect.w, .y = rect.h },
            tint,
            uv_rect,
            filter,
            .top_left,
            VectorTransform2D.translate(rect.x, rect.y),
        );
    }

    pub fn addSpriteTransformed(
        self: *SpriteBatch,
        image_like: anytype,
        size: Vec2,
        tint: [4]f32,
        uv_rect: SpriteUvRect,
        filter: ImageFilter,
        anchor: SpriteAnchor,
        transform: VectorTransform2D,
    ) bool {
        if (self.len + SPRITE_FLOATS_PER_SPRITE > self.buf.len) return false;
        const view = coerceImageView(image_like);
        sprite_vertex_mod.generateSpriteVertices(
            self.buf[self.len..],
            view,
            size,
            tint,
            uv_rect,
            filter,
            anchor,
            transform,
        );
        self.len += SPRITE_FLOATS_PER_SPRITE;
        return true;
    }
};

const kPathArcSplitMaxDepth: u8 = 8;
const kPathStrokeOffsetTolerance: f32 = 0.02;
const kPathStrokeOffsetMaxDepth: u8 = 10;
const kPathCurveApproxTolerance: f32 = 0.02;
const kPathCurveApproxMaxDepth: u8 = 8;

fn makePathLineCurve(p0: Vec2, p1: Vec2) bezier.QuadBezier {
    return .{
        .p0 = p0,
        .p1 = Vec2.lerp(p0, p1, 0.5),
        .p2 = p1,
    };
}

fn makePathLineSegment(p0: Vec2, p1: Vec2) CurveSegment {
    return CurveSegment.fromQuad(makePathLineCurve(p0, p1));
}

fn makePathArcCurve(center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) bezier.QuadBezier {
    const p0 = center.add(Vec2.new(@cos(start_angle) * radii.x, @sin(start_angle) * radii.y));
    const p2 = center.add(Vec2.new(@cos(end_angle) * radii.x, @sin(end_angle) * radii.y));
    const t0 = Vec2.new(-@sin(start_angle) * radii.x, @cos(start_angle) * radii.y);
    const t1 = Vec2.new(-@sin(end_angle) * radii.x, @cos(end_angle) * radii.y);
    const control = lineIntersection(p0, t0, p2, t1) orelse Vec2.lerp(p0, p2, 0.5);
    return .{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    };
}

fn appendAdaptiveArcCurve(
    path: *VectorPath,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
    depth: u8,
) !void {
    const span = end_angle - start_angle;
    if (depth == 0 or @abs(span) <= std.math.pi * 0.125 + 1e-6) {
        try path.appendSegment(CurveSegment.fromQuad(makePathArcCurve(center, radii, start_angle, end_angle)));
        return;
    }
    const mid_angle = (start_angle + end_angle) * 0.5;
    try appendAdaptiveArcCurve(path, center, radii, start_angle, mid_angle, depth - 1);
    try appendAdaptiveArcCurve(path, center, radii, mid_angle, end_angle, depth - 1);
}

fn pointsApproxEqual(a: Vec2, b: Vec2) bool {
    return @abs(a.x - b.x) <= 1e-4 and @abs(a.y - b.y) <= 1e-4;
}

fn cross2(a: Vec2, b: Vec2) f32 {
    return a.x * b.y - a.y * b.x;
}

fn perpLeft(v: Vec2) Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

fn signedAngleBetween(a: Vec2, b: Vec2) f32 {
    return std.math.atan2(cross2(a, b), Vec2.dot(a, b));
}

fn lineIntersection(p0: Vec2, d0: Vec2, p1: Vec2, d1: Vec2) ?Vec2 {
    const denom = cross2(d0, d1);
    if (@abs(denom) <= 1e-6) return null;
    const rel = Vec2.sub(p1, p0);
    const t = cross2(rel, d1) / denom;
    return Vec2.add(p0, Vec2.scale(d0, t));
}

fn appendLineIfNeeded(path: *VectorPath, point: Vec2) !void {
    if (!pointsApproxEqual(path.requireContour().?.current_point, point)) {
        try path.lineTo(point);
    }
}

fn resolveFillPaint(style: VectorFillStyle) PathPaint {
    return style.paint orelse .{ .solid = style.color };
}

fn resolveStrokePaint(style: PathStrokeStyle) PathPaint {
    return style.paint orelse .{ .solid = style.color };
}

fn fillStyleForStroke(style: PathStrokeStyle) VectorFillStyle {
    return .{
        .color = style.color,
        .paint = style.paint,
    };
}

fn reverseCurveSegment(curve: CurveSegment) CurveSegment {
    return switch (curve.kind) {
        .quadratic => .{
            .kind = .quadratic,
            .p0 = curve.p2,
            .p1 = curve.p1,
            .p2 = curve.p0,
        },
        .conic => .{
            .kind = .conic,
            .p0 = curve.p2,
            .p1 = curve.p1,
            .p2 = curve.p0,
            .weights = .{ curve.weights[2], curve.weights[1], curve.weights[0] },
        },
        .cubic => .{
            .kind = .cubic,
            .p0 = curve.p3,
            .p1 = curve.p2,
            .p2 = curve.p1,
            .p3 = curve.p0,
        },
    };
}

fn curveUnitTangent(curve: CurveSegment, t: f32) Vec2 {
    const deriv = curve.derivative(t);
    if (Vec2.length(deriv) > 1e-5) return Vec2.normalize(deriv);

    const fallback_deltas = [_]f32{ 1e-4, 1e-3, 1e-2, 5e-2 };
    for (fallback_deltas) |delta| {
        const t0 = std.math.clamp(t - delta, 0.0, 1.0);
        const t1 = std.math.clamp(t + delta, 0.0, 1.0);
        if (@abs(t1 - t0) <= 1e-6) continue;
        const diff = Vec2.sub(curve.evaluate(t1), curve.evaluate(t0));
        if (Vec2.length(diff) > 1e-5) return Vec2.normalize(diff);
    }

    const chord = Vec2.sub(curve.endPoint(), curve.p0);
    if (Vec2.length(chord) > 1e-5) return Vec2.normalize(chord);
    return .{ .x = 1.0, .y = 0.0 };
}

fn offsetCurvePoint(curve: CurveSegment, t: f32, offset: f32) Vec2 {
    const tangent = curveUnitTangent(curve, t);
    const normal = perpLeft(tangent);
    return Vec2.add(curve.evaluate(t), Vec2.scale(normal, offset));
}

fn fitOffsetCurveQuad(curve: CurveSegment, offset: f32) CurveSegment {
    const p0 = offsetCurvePoint(curve, 0.0, offset);
    const pm = offsetCurvePoint(curve, 0.5, offset);
    const p2 = offsetCurvePoint(curve, 1.0, offset);
    const control = Vec2.new(
        pm.x * 2.0 - (p0.x + p2.x) * 0.5,
        pm.y * 2.0 - (p0.y + p2.y) * 0.5,
    );
    return CurveSegment.fromQuad(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    });
}

fn fitCurveQuadratic(curve: CurveSegment) CurveSegment {
    if (curve.kind == .quadratic) return curve;
    const p0 = curve.evaluate(0.0);
    const pm = curve.evaluate(0.5);
    const p2 = curve.evaluate(1.0);
    const control = Vec2.new(
        pm.x * 2.0 - (p0.x + p2.x) * 0.5,
        pm.y * 2.0 - (p0.y + p2.y) * 0.5,
    );
    return CurveSegment.fromQuad(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    });
}

fn curveQuadraticApproxError(curve: CurveSegment) f32 {
    if (curve.kind == .quadratic) return 0.0;
    const approx = fitCurveQuadratic(curve).asQuad();
    var max_error: f32 = 0.0;
    inline for ([_]f32{ 0.25, 0.75 }) |t| {
        const expected = curve.evaluate(t);
        const actual = approx.evaluate(t);
        max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
    }
    return max_error;
}

fn appendAdaptiveQuadraticApprox(
    path: *VectorPath,
    curve: CurveSegment,
    depth: u8,
) !void {
    if (curve.kind == .quadratic) {
        try path.appendSegment(curve);
        return;
    }

    if (depth == 0 or curveQuadraticApproxError(curve) <= kPathCurveApproxTolerance) {
        try path.appendSegment(fitCurveQuadratic(curve));
        return;
    }

    const halves = curve.split(0.5);
    try appendAdaptiveQuadraticApprox(path, halves[0], depth - 1);
    try appendAdaptiveQuadraticApprox(path, halves[1], depth - 1);
}

fn offsetCurveApproxError(curve: CurveSegment, offset: f32) f32 {
    const approx = fitOffsetCurveQuad(curve, offset).asQuad();
    var max_error: f32 = 0.0;
    inline for ([_]f32{ 0.25, 0.75 }) |t| {
        const expected = offsetCurvePoint(curve, t, offset);
        const actual = approx.evaluate(t);
        max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
    }
    return max_error;
}

fn appendOffsetCurveApprox(
    path: *VectorPath,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
) !void {
    if (curve.flatness() <= 1e-6) {
        try path.lineTo(offsetCurvePoint(curve, 1.0, offset));
        return;
    }

    if (depth == 0 or offsetCurveApproxError(curve, offset) <= kPathStrokeOffsetTolerance) {
        try path.appendSegment(fitOffsetCurveQuad(curve, offset));
        return;
    }

    const halves = curve.split(0.5);
    try appendOffsetCurveApprox(path, halves[0], offset, depth - 1);
    try appendOffsetCurveApprox(path, halves[1], offset, depth - 1);
}

pub const VectorPath = struct {
    allocator: std.mem.Allocator,
    curves: std.ArrayList(CurveSegment) = .empty,
    contours: std.ArrayList(Contour) = .empty,
    bbox: ?BBox = null,

    const Contour = struct {
        curve_start: usize,
        curve_end: usize,
        start_point: Vec2,
        current_point: Vec2,
        closed: bool,
    };

    pub fn init(allocator: std.mem.Allocator) VectorPath {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *VectorPath) void {
        self.curves.deinit(self.allocator);
        self.contours.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *VectorPath) void {
        self.curves.clearRetainingCapacity();
        self.contours.clearRetainingCapacity();
        self.bbox = null;
    }

    pub fn bounds(self: *const VectorPath) ?BBox {
        return self.bbox;
    }

    pub fn isEmpty(self: *const VectorPath) bool {
        return self.curves.items.len == 0;
    }

    pub fn moveTo(self: *VectorPath, point: Vec2) !void {
        if (self.contours.items.len > 0) {
            var contour = &self.contours.items[self.contours.items.len - 1];
            if (contour.curve_end == contour.curve_start and !contour.closed) {
                contour.start_point = point;
                contour.current_point = point;
                self.expandPointBBox(point);
                return;
            }
        }
        try self.contours.append(self.allocator, .{
            .curve_start = self.curves.items.len,
            .curve_end = self.curves.items.len,
            .start_point = point,
            .current_point = point,
            .closed = false,
        });
        self.expandPointBBox(point);
    }

    pub fn lineTo(self: *VectorPath, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.appendSegment(makePathLineSegment(contour.current_point, point));
    }

    pub fn quadTo(self: *VectorPath, control: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.appendSegment(CurveSegment.fromQuad(.{
            .p0 = contour.current_point,
            .p1 = control,
            .p2 = point,
        }));
    }

    pub fn cubicTo(self: *VectorPath, control1: Vec2, control2: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try appendAdaptiveQuadraticApprox(self, CurveSegment.fromCubic(.{
            .p0 = contour.current_point,
            .p1 = control1,
            .p2 = control2,
            .p3 = point,
        }), kPathCurveApproxMaxDepth);
    }

    pub fn close(self: *VectorPath) !void {
        if (self.requireContour()) |initial_contour| {
            var contour = initial_contour;
            if (contour.closed) return;
            if (contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                try self.appendSegment(makePathLineSegment(contour.current_point, contour.start_point));
                contour = self.requireContour().?;
            }
            contour.closed = true;
            contour.current_point = contour.start_point;
        }
    }

    pub fn addRect(self: *VectorPath, rect: VectorRect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.close();
    }

    pub fn addRectReversed(self: *VectorPath, rect: VectorRect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.close();
    }

    pub fn addRoundedRect(self: *VectorPath, rect: VectorRect, corner_radius: f32) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRect(rect);

        const arc = Vec2.new(radius, radius);
        const top_left = origin.add(Vec2.new(radius, radius));
        const top_right = origin.add(Vec2.new(size.x - radius, radius));
        const bottom_right = origin.add(size).sub(Vec2.new(radius, radius));
        const bottom_left = origin.add(Vec2.new(radius, size.y - radius));

        try self.moveTo(origin.add(Vec2.new(radius, 0.0)));
        try self.lineTo(origin.add(Vec2.new(size.x - radius, 0.0)));
        try self.appendArc(top_right, arc, -std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, size.y - radius)));
        try self.appendArc(bottom_right, arc, 0.0, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, size.y)));
        try self.appendArc(bottom_left, arc, std.math.pi / 2.0, std.math.pi);
        try self.lineTo(origin.add(Vec2.new(0.0, radius)));
        try self.appendArc(top_left, arc, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addRoundedRectReversed(self: *VectorPath, rect: VectorRect, corner_radius: f32) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRectReversed(rect);

        const arc = Vec2.new(radius, radius);
        const top_left = origin.add(Vec2.new(radius, radius));
        const top_right = origin.add(Vec2.new(size.x - radius, radius));
        const bottom_right = origin.add(size).sub(Vec2.new(radius, radius));
        const bottom_left = origin.add(Vec2.new(radius, size.y - radius));

        try self.moveTo(origin.add(Vec2.new(0.0, radius)));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y - radius)));
        try self.appendArc(bottom_left, arc, std.math.pi, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(size.x - radius, size.y)));
        try self.appendArc(bottom_right, arc, std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, radius)));
        try self.appendArc(top_right, arc, 0.0, -std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, 0.0)));
        try self.appendArc(top_left, arc, -std.math.pi / 2.0, -std.math.pi);
        try self.close();
    }

    pub fn addEllipse(self: *VectorPath, rect: VectorRect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try self.appendArc(center, radii, -std.math.pi / 2.0, 0.0);
        try self.appendArc(center, radii, 0.0, std.math.pi / 2.0);
        try self.appendArc(center, radii, std.math.pi / 2.0, std.math.pi);
        try self.appendArc(center, radii, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addEllipseReversed(self: *VectorPath, rect: VectorRect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try self.appendArc(center, radii, -std.math.pi / 2.0, -std.math.pi);
        try self.appendArc(center, radii, -std.math.pi, -std.math.pi * 1.5);
        try self.appendArc(center, radii, -std.math.pi * 1.5, -std.math.pi * 2.0);
        try self.appendArc(center, radii, -std.math.pi * 2.0, -std.math.pi * 2.5);
        try self.close();
    }

    fn requireContour(self: *VectorPath) ?*Contour {
        if (self.contours.items.len == 0) return null;
        return &self.contours.items[self.contours.items.len - 1];
    }

    fn appendSegment(self: *VectorPath, curve: CurveSegment) !void {
        var contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.curves.append(self.allocator, curve);
        contour = self.requireContour().?;
        contour.curve_end = self.curves.items.len;
        contour.current_point = curve.endPoint();
        self.expandCurveBBox(curve);
    }

    fn appendArc(self: *VectorPath, center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) !void {
        try appendAdaptiveArcCurve(self, center, radii, start_angle, end_angle, kPathArcSplitMaxDepth);
    }

    fn expandPointBBox(self: *VectorPath, point: Vec2) void {
        if (self.bbox) |bbox| {
            self.bbox = .{
                .min = Vec2.new(@min(bbox.min.x, point.x), @min(bbox.min.y, point.y)),
                .max = Vec2.new(@max(bbox.max.x, point.x), @max(bbox.max.y, point.y)),
            };
        } else {
            self.bbox = .{ .min = point, .max = point };
        }
    }

    fn expandCurveBBox(self: *VectorPath, curve: CurveSegment) void {
        const cb = curve.boundingBox();
        if (self.bbox) |bbox| {
            self.bbox = bbox.merge(cb);
        } else {
            self.bbox = cb;
        }
    }

    fn cloneFilledCurves(self: *const VectorPath, allocator: std.mem.Allocator) ![]CurveSegment {
        var close_count: usize = 0;
        for (self.contours.items) |contour| {
            if (!contour.closed and contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                close_count += 1;
            }
        }
        const out = try allocator.alloc(CurveSegment, self.curves.items.len + close_count);
        @memcpy(out[0..self.curves.items.len], self.curves.items);
        var write = self.curves.items.len;
        for (self.contours.items) |contour| {
            if (!contour.closed and contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                out[write] = makePathLineSegment(contour.current_point, contour.start_point);
                write += 1;
            }
        }
        return out;
    }

    fn cloneStrokedCurves(
        self: *const VectorPath,
        allocator: std.mem.Allocator,
        stroke: PathStrokeStyle,
    ) !?struct { curves: []CurveSegment, bbox: BBox } {
        if (stroke.width <= 1e-4 or self.contours.items.len == 0) return null;

        var outline = VectorPath.init(allocator);
        defer outline.deinit();

        for (self.contours.items) |contour| {
            if (contour.closed) {
                try buildClosedStrokeContours(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            } else {
                try buildOpenStrokeContour(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            }
        }

        if (outline.isEmpty()) return null;
        const curves = try allocator.alloc(CurveSegment, outline.curves.items.len);
        @memcpy(curves, outline.curves.items);
        return .{
            .curves = curves,
            .bbox = outline.bounds() orelse return error.EmptyPath,
        };
    }
};

fn appendArcSeries(path: *VectorPath, center: Vec2, radius: f32, start_angle: f32, end_angle: f32) !void {
    if (@abs(end_angle - start_angle) <= 1e-6) return;
    try appendAdaptiveArcCurve(path, center, Vec2.new(radius, radius), start_angle, end_angle, kPathArcSplitMaxDepth);
}

fn appendRoundJoin(path: *VectorPath, center: Vec2, prev_normal: Vec2, next_normal: Vec2, half_width: f32) !void {
    const start_angle = std.math.atan2(prev_normal.y, prev_normal.x);
    const delta = signedAngleBetween(prev_normal, next_normal);
    try appendArcSeries(path, center, half_width, start_angle, start_angle + delta);
}

fn appendRoundCap(path: *VectorPath, center: Vec2, dir: Vec2, half_width: f32, start_cap: bool) !void {
    const normal = perpLeft(dir);
    const start_angle = if (start_cap)
        std.math.atan2(-normal.y, -normal.x)
    else
        std.math.atan2(normal.y, normal.x);
    try appendArcSeries(path, center, half_width, start_angle, start_angle - std.math.pi);
}

fn appendStrokeJoinForSide(
    path: *VectorPath,
    center: Vec2,
    prev_dir: Vec2,
    next_dir: Vec2,
    half_width: f32,
    side: f32,
    join: PathStrokeJoin,
    miter_limit: f32,
) !void {
    const turn = cross2(prev_dir, next_dir);
    const normal_prev = Vec2.scale(perpLeft(prev_dir), side);
    const normal_next = Vec2.scale(perpLeft(next_dir), side);
    const prev_offset = Vec2.add(center, Vec2.scale(normal_prev, half_width));
    const next_offset = Vec2.add(center, Vec2.scale(normal_next, half_width));

    if (@abs(turn) <= 1e-5) {
        try appendLineIfNeeded(path, next_offset);
        return;
    }

    const intersection = lineIntersection(prev_offset, prev_dir, next_offset, next_dir);
    const is_outer = turn * side > 0.0;
    if (!is_outer) {
        if (intersection) |p| {
            try appendLineIfNeeded(path, p);
        }
        try appendLineIfNeeded(path, next_offset);
        return;
    }

    switch (join) {
        .bevel => {
            try appendLineIfNeeded(path, next_offset);
        },
        .round => {
            try appendRoundJoin(path, center, normal_prev, normal_next, half_width);
        },
        .miter => {
            if (intersection) |p| {
                if (Vec2.length(Vec2.sub(p, center)) <= half_width * @max(miter_limit, 1.0)) {
                    try appendLineIfNeeded(path, p);
                    try appendLineIfNeeded(path, next_offset);
                    return;
                }
            }
            try appendLineIfNeeded(path, next_offset);
        },
    }
}

fn appendOffsetBoundaryCurve(
    boundary: *VectorPath,
    curve: CurveSegment,
    side: f32,
    half_width: f32,
) !void {
    try appendOffsetCurveApprox(boundary, curve, side * half_width, kPathStrokeOffsetMaxDepth);
}

fn buildOffsetBoundary(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    closed: bool,
    side: f32,
    stroke: PathStrokeStyle,
) !?VectorPath {
    if ((!closed and curves.len == 0) or stroke.width <= 1e-4) return null;

    const half_width = stroke.width * 0.5;
    var boundary = VectorPath.init(allocator);
    errdefer boundary.deinit();

    const first_curve = curves[0];
    const start_point = offsetCurvePoint(first_curve, 0.0, side * half_width);
    try boundary.moveTo(start_point);
    try appendOffsetBoundaryCurve(&boundary, first_curve, side, half_width);

    if (curves.len > 1) {
        for (1..curves.len) |i| {
            const prev_curve = curves[i - 1];
            const curve = curves[i];
            try appendStrokeJoinForSide(
                &boundary,
                prev_curve.endPoint(),
                curveUnitTangent(prev_curve, 1.0),
                curveUnitTangent(curve, 0.0),
                half_width,
                side,
                stroke.join,
                stroke.miter_limit,
            );
            try appendOffsetBoundaryCurve(&boundary, curve, side, half_width);
        }
    }

    if (closed) {
        try appendStrokeJoinForSide(
            &boundary,
            curves[curves.len - 1].endPoint(),
            curveUnitTangent(curves[curves.len - 1], 1.0),
            curveUnitTangent(curves[0], 0.0),
            half_width,
            side,
            stroke.join,
            stroke.miter_limit,
        );
    }

    return boundary;
}

fn appendBoundaryCurves(dst: *VectorPath, src: *const VectorPath, reverse: bool) !void {
    if (!reverse) {
        for (src.curves.items) |curve| try dst.appendSegment(curve);
        return;
    }
    var i = src.curves.items.len;
    while (i > 0) {
        i -= 1;
        try dst.appendSegment(reverseCurveSegment(src.curves.items[i]));
    }
}

fn buildOpenStrokeContour(path: *VectorPath, curves: []const CurveSegment, stroke: PathStrokeStyle) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    var left = (try buildOffsetBoundary(path.allocator, curves, false, 1.0, stroke)) orelse return;
    defer left.deinit();
    var right = (try buildOffsetBoundary(path.allocator, curves, false, -1.0, stroke)) orelse return;
    defer right.deinit();

    const half_width = stroke.width * 0.5;
    const start_dir = curveUnitTangent(curves[0], 0.0);
    const end_dir = curveUnitTangent(curves[curves.len - 1], 1.0);
    const start_center = if (stroke.cap == .square)
        Vec2.sub(curves[0].p0, Vec2.scale(start_dir, half_width))
    else
        curves[0].p0;
    const end_center = if (stroke.cap == .square)
        Vec2.add(curves[curves.len - 1].endPoint(), Vec2.scale(end_dir, half_width))
    else
        curves[curves.len - 1].endPoint();
    const start_left = Vec2.add(start_center, Vec2.scale(perpLeft(start_dir), half_width));
    const start_right = Vec2.sub(start_center, Vec2.scale(perpLeft(start_dir), half_width));
    const end_left = Vec2.add(end_center, Vec2.scale(perpLeft(end_dir), half_width));
    const end_right = Vec2.sub(end_center, Vec2.scale(perpLeft(end_dir), half_width));
    const left_start = left.curves.items[0].p0;
    const right_start = right.curves.items[0].p0;
    const right_end = right.curves.items[right.curves.items.len - 1].endPoint();

    try path.moveTo(start_right);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[0].p0, start_dir, half_width, true),
        .butt, .square => try appendLineIfNeeded(path, start_left),
    }
    try appendLineIfNeeded(path, left_start);
    try appendBoundaryCurves(path, &left, false);
    try appendLineIfNeeded(path, end_left);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[curves.len - 1].endPoint(), end_dir, half_width, false),
        .butt, .square => try appendLineIfNeeded(path, end_right),
    }
    try appendLineIfNeeded(path, right_end);
    try appendBoundaryCurves(path, &right, true);
    try appendLineIfNeeded(path, right_start);
    try path.close();
}

fn buildClosedStrokeContours(path: *VectorPath, curves: []const CurveSegment, stroke: PathStrokeStyle) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    var left = (try buildOffsetBoundary(path.allocator, curves, true, 1.0, stroke)) orelse return;
    defer left.deinit();
    var right = (try buildOffsetBoundary(path.allocator, curves, true, -1.0, stroke)) orelse return;
    defer right.deinit();

    try path.moveTo(left.curves.items[0].p0);
    try appendBoundaryCurves(path, &left, false);
    try path.close();

    try path.moveTo(right.curves.items[right.curves.items.len - 1].endPoint());
    try appendBoundaryCurves(path, &right, true);
    try path.close();
}

const kPathPaintInfoWidth: u32 = PATH_PAINT_INFO_WIDTH;
const kPathPaintTexelsPerRecord: u32 = PATH_PAINT_TEXELS_PER_RECORD;
const kPathPaintTagSolid: f32 = PATH_PAINT_TAG_SOLID;
const kPathPaintTagLinearGradient: f32 = PATH_PAINT_TAG_LINEAR_GRADIENT;
const kPathPaintTagRadialGradient: f32 = PATH_PAINT_TAG_RADIAL_GRADIENT;
const kPathPaintTagImage: f32 = PATH_PAINT_TAG_IMAGE;
const kPathPaintTagCompositeGroup: f32 = -5.0;

const PathCompositeMode = enum(u8) {
    source_over = 0,
    fill_stroke_inside = 1,
};

pub const PathPicture = struct {
    allocator: std.mem.Allocator,
    atlas: Atlas,
    instances: []Instance,

    pub const Instance = struct {
        glyph_id: u16,
        bbox: BBox,
        page_index: u16,
        info_x: u16,
        info_y: u16,
        layer_count: u16 = 1,
        transform: VectorTransform2D,
    };

    pub fn deinit(self: *PathPicture) void {
        self.atlas.deinit();
        self.allocator.free(self.instances);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPicture) usize {
        return self.instances.len;
    }
};

pub const PathPictureBuilder = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList(PathRecord) = .empty,

    const PathLayerRecord = struct {
        curves: []CurveSegment,
        bbox: BBox,
        paint: PathPaint,
    };

    const PathRecord = struct {
        bbox: BBox,
        transform: VectorTransform2D,
        layer_count: u16,
        composite_mode: PathCompositeMode,
        layers: [2]PathLayerRecord,
    };

    fn setLayerInfoTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
        const texel_x = texel_offset % texel_width;
        const texel_y = texel_offset / texel_width;
        const base = (texel_y * texel_width + texel_x) * 4;
        data[base + 0] = value[0];
        data[base + 1] = value[1];
        data[base + 2] = value[2];
        data[base + 3] = value[3];
    }

    fn pathPaintTag(paint: PathPaint) f32 {
        return switch (paint) {
            .solid => kPathPaintTagSolid,
            .linear_gradient => kPathPaintTagLinearGradient,
            .radial_gradient => kPathPaintTagRadialGradient,
            .image => kPathPaintTagImage,
        };
    }

    fn writePathPaintRecord(
        data: []f32,
        texel_offset: u32,
        band_entry: band_tex.GlyphBandEntry,
        paint: PathPaint,
    ) void {
        const packed_bands: u32 = @as(u32, band_entry.h_band_count - 1) | (@as(u32, band_entry.v_band_count - 1) << 16);
        setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 0, .{
            @floatFromInt(band_entry.glyph_x),
            @floatFromInt(band_entry.glyph_y),
            @bitCast(packed_bands),
            pathPaintTag(paint),
        });
        setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 1, .{
            band_entry.band_scale_x,
            band_entry.band_scale_y,
            band_entry.band_offset_x,
            band_entry.band_offset_y,
        });

        switch (paint) {
            .solid => |color| {
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 2, color);
            },
            .linear_gradient => |gradient| {
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 2, .{
                    gradient.start.x,
                    gradient.start.y,
                    gradient.end.x,
                    gradient.end.y,
                });
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 3, gradient.start_color);
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 4, gradient.end_color);
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 5, .{
                    @floatFromInt(@intFromEnum(gradient.extend)),
                    0,
                    0,
                    0,
                });
            },
            .radial_gradient => |gradient| {
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 2, .{
                    gradient.center.x,
                    gradient.center.y,
                    gradient.radius,
                    @floatFromInt(@intFromEnum(gradient.extend)),
                });
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 3, gradient.inner_color);
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 4, gradient.outer_color);
            },
            .image => |image| {
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 2, .{
                    image.uv_transform.xx,
                    image.uv_transform.xy,
                    image.uv_transform.tx,
                    0,
                });
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 3, .{
                    image.uv_transform.yx,
                    image.uv_transform.yy,
                    image.uv_transform.ty,
                    @floatFromInt(@intFromEnum(image.filter)),
                });
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 4, image.tint);
                setLayerInfoTexel(data, kPathPaintInfoWidth, texel_offset + 5, .{
                    0,
                    0,
                    @floatFromInt(@intFromEnum(image.extend_x)),
                    @floatFromInt(@intFromEnum(image.extend_y)),
                });
            },
        }
    }

    pub fn init(allocator: std.mem.Allocator) PathPictureBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathPictureBuilder) void {
        for (self.paths.items) |path| {
            for (path.layers[0..path.layer_count]) |layer| self.allocator.free(layer.curves);
        }
        self.paths.deinit(self.allocator);
        self.* = undefined;
    }

    fn addSingleRecord(
        self: *PathPictureBuilder,
        curves: []CurveSegment,
        bbox: BBox,
        paint: PathPaint,
        transform: VectorTransform2D,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = bbox,
            .transform = transform,
            .layer_count = 1,
            .composite_mode = .source_over,
            .layers = .{
                .{
                    .curves = curves,
                    .bbox = bbox,
                    .paint = paint,
                },
                undefined,
            },
        });
    }

    fn addExplicitInsideStrokeRecord(
        self: *PathPictureBuilder,
        fill_path: *const VectorPath,
        fill: ?VectorFillStyle,
        stroke_path: *const VectorPath,
        stroke_paint: PathPaint,
        transform: VectorTransform2D,
    ) !void {
        const stroke_bbox = stroke_path.bounds() orelse return error.EmptyPath;
        const stroke_curves = try stroke_path.cloneFilledCurves(self.allocator);
        errdefer self.allocator.free(stroke_curves);

        if (fill) |style| {
            const fill_bbox = fill_path.bounds() orelse return error.EmptyPath;
            const fill_curves = try fill_path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(fill_curves);
            try self.addCompositeRecord(
                fill_curves,
                fill_bbox,
                resolveFillPaint(style),
                stroke_curves,
                stroke_bbox,
                stroke_paint,
                transform,
                .source_over,
            );
            return;
        }

        try self.addSingleRecord(stroke_curves, stroke_bbox, stroke_paint, transform);
    }

    fn addCompositeRecord(
        self: *PathPictureBuilder,
        fill_curves: []CurveSegment,
        fill_bbox: BBox,
        fill_paint: PathPaint,
        stroke_curves: []CurveSegment,
        stroke_bbox: BBox,
        stroke_paint: PathPaint,
        transform: VectorTransform2D,
        composite_mode: PathCompositeMode,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = switch (composite_mode) {
                .source_over => fill_bbox.merge(stroke_bbox),
                .fill_stroke_inside => fill_bbox,
            },
            .transform = transform,
            .layer_count = 2,
            .composite_mode = composite_mode,
            .layers = .{
                .{
                    .curves = fill_curves,
                    .bbox = fill_bbox,
                    .paint = fill_paint,
                },
                .{
                    .curves = stroke_curves,
                    .bbox = stroke_bbox,
                    .paint = stroke_paint,
                },
            },
        });
    }

    pub fn addPath(
        self: *PathPictureBuilder,
        path: *const VectorPath,
        fill: ?VectorFillStyle,
        stroke: ?PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        if (fill == null and stroke == null) return error.EmptyStyle;
        if (path.isEmpty()) return error.EmptyPath;

        if (fill) |style| {
            const bbox = path.bounds() orelse return error.EmptyPath;
            const curves = try path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(curves);
            if (stroke) |stroke_style| {
                if (try path.cloneStrokedCurves(self.allocator, stroke_style)) |stroke_geom| {
                    errdefer self.allocator.free(stroke_geom.curves);
                    const composite_mode: PathCompositeMode = if (stroke_style.placement == .inside)
                        .fill_stroke_inside
                    else
                        .source_over;
                    try self.addCompositeRecord(
                        curves,
                        bbox,
                        resolveFillPaint(style),
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        resolveStrokePaint(stroke_style),
                        transform,
                        composite_mode,
                    );
                    return;
                }
            }
            try self.addSingleRecord(curves, bbox, resolveFillPaint(style), transform);
        }
        if (stroke) |style| {
            if (try path.cloneStrokedCurves(self.allocator, style)) |stroke_geom| {
                errdefer self.allocator.free(stroke_geom.curves);
                try self.addSingleRecord(stroke_geom.curves, stroke_geom.bbox, resolveStrokePaint(style), transform);
            }
        }
    }

    pub fn addFilledPath(
        self: *PathPictureBuilder,
        path: *const VectorPath,
        fill: VectorFillStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addPath(path, fill, null, transform);
    }

    pub fn addStrokedPath(
        self: *PathPictureBuilder,
        path: *const VectorPath,
        stroke: PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addPath(path, null, stroke, transform);
    }

    pub fn addRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = VectorPath.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRect(rect);

                var stroke_path = VectorPath.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRect(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addRectReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, resolveStrokePaint(stroke_style), transform);
            }
        }

        var path = VectorPath.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addRoundedRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?PathStrokeStyle,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const max_radius = @min(size.x, size.y) * 0.5;
            const radius = std.math.clamp(corner_radius, 0.0, max_radius);
            const inset = std.math.clamp(stroke_style.width, 0.0, max_radius);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = VectorPath.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRoundedRect(rect, radius);

                var stroke_path = VectorPath.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRoundedRect(rect, radius);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    const inner_rect = VectorRect{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    };
                    const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                    try stroke_path.addRoundedRectReversed(inner_rect, inner_radius);
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, resolveStrokePaint(stroke_style), transform);
            }
        }

        var path = VectorPath.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addEllipse(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: ?VectorFillStyle,
        stroke: ?PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = VectorPath.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addEllipse(rect);

                var stroke_path = VectorPath.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addEllipse(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addEllipseReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, resolveStrokePaint(stroke_style), transform);
            }
        }

        var path = VectorPath.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: VectorFillStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addRect(rect, fill, null, transform);
    }

    pub fn addFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: VectorFillStyle,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) !void {
        try self.addRoundedRect(rect, fill, null, corner_radius, transform);
    }

    pub fn addFilledEllipse(
        self: *PathPictureBuilder,
        rect: VectorRect,
        fill: VectorFillStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addEllipse(rect, fill, null, transform);
    }

    pub fn addStrokedRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        stroke: PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addRect(rect, null, stroke, transform);
    }

    pub fn addStrokedRoundedRect(
        self: *PathPictureBuilder,
        rect: VectorRect,
        stroke: PathStrokeStyle,
        corner_radius: f32,
        transform: VectorTransform2D,
    ) !void {
        try self.addRoundedRect(rect, null, stroke, corner_radius, transform);
    }

    pub fn addStrokedEllipse(
        self: *PathPictureBuilder,
        rect: VectorRect,
        stroke: PathStrokeStyle,
        transform: VectorTransform2D,
    ) !void {
        try self.addEllipse(rect, null, stroke, transform);
    }

    pub fn freeze(self: *const PathPictureBuilder, allocator: std.mem.Allocator) !PathPicture {
        if (self.paths.items.len == 0) return error.EmptyPicture;

        var total_layer_count: usize = 0;
        var total_paint_texels: u32 = 0;
        for (self.paths.items) |path| {
            total_layer_count += path.layer_count;
            total_paint_texels += if (path.layer_count == 1)
                kPathPaintTexelsPerRecord
            else
                1 + @as(u32, path.layer_count) * kPathPaintTexelsPerRecord;
        }

        const glyph_curves = try allocator.alloc(curve_tex.GlyphCurves, total_layer_count);
        defer allocator.free(glyph_curves);
        var glyph_cursor: usize = 0;
        for (self.paths.items) |path| {
            for (path.layers[0..path.layer_count]) |layer| {
                glyph_curves[glyph_cursor] = .{ .curves = layer.curves, .bbox = layer.bbox };
                glyph_cursor += 1;
            }
        }

        var ct = try curve_tex.buildCurveTexture(allocator, glyph_curves);
        errdefer ct.texture.deinit();
        errdefer allocator.free(ct.entries);

        var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
        defer {
            for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(allocator, bd);
            glyph_band_data.deinit(allocator);
        }
        for (glyph_curves, 0..) |gc, i| {
            var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.bbox, ct.entries[i]);
            try glyph_band_data.append(allocator, bd);
            _ = &bd;
        }

        var bt = try band_tex.buildBandTexture(allocator, glyph_band_data.items);
        errdefer bt.texture.deinit();
        errdefer allocator.free(bt.entries);

        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();

        const paint_height = @max(1, (total_paint_texels + kPathPaintInfoWidth - 1) / kPathPaintInfoWidth);
        const layer_info_data = try allocator.alloc(f32, kPathPaintInfoWidth * paint_height * 4);
        errdefer allocator.free(layer_info_data);
        @memset(layer_info_data, 0);

        const instances = try allocator.alloc(PathPicture.Instance, self.paths.items.len);
        errdefer allocator.free(instances);

        const paint_image_records = try allocator.alloc(?Atlas.PaintImageRecord, total_layer_count);
        errdefer allocator.free(paint_image_records);
        @memset(paint_image_records, null);

        var has_image_paints = false;

        glyph_cursor = 0;
        var texel_cursor: u32 = 0;
        for (self.paths.items, 0..) |path, path_index| {
            const info_texel_offset = texel_cursor;
            if (path.layer_count > 1) {
                setLayerInfoTexel(layer_info_data, kPathPaintInfoWidth, texel_cursor, .{
                    @floatFromInt(path.layer_count),
                    @floatFromInt(@intFromEnum(path.composite_mode)),
                    0,
                    kPathPaintTagCompositeGroup,
                });
                texel_cursor += 1;
            }

            var first_glyph_id: u16 = 0;
            for (path.layers[0..path.layer_count], 0..) |layer, layer_index| {
                const glyph_id: u16 = @intCast(glyph_cursor + 1);
                if (layer_index == 0) first_glyph_id = glyph_id;
                try glyph_map.put(glyph_id, .{
                    .bbox = layer.bbox,
                    .advance_width = 0,
                    .band_entry = bt.entries[glyph_cursor],
                    .page_index = 0,
                });
                writePathPaintRecord(layer_info_data, texel_cursor, bt.entries[glyph_cursor], layer.paint);
                switch (layer.paint) {
                    .image => |image_paint| {
                        paint_image_records[glyph_cursor] = .{
                            .image = image_paint.image,
                            .texel_offset = texel_cursor,
                        };
                        has_image_paints = true;
                    },
                    else => {},
                }
                texel_cursor += kPathPaintTexelsPerRecord;
                glyph_cursor += 1;
            }

            instances[path_index] = .{
                .glyph_id = first_glyph_id,
                .bbox = path.bbox,
                .page_index = 0,
                .info_x = @intCast(info_texel_offset % kPathPaintInfoWidth),
                .info_y = @intCast(info_texel_offset / kPathPaintInfoWidth),
                .layer_count = path.layer_count,
                .transform = path.transform,
            };
        }

        allocator.free(ct.entries);
        allocator.free(bt.entries);

        const page = try AtlasPage.init(
            allocator,
            ct.texture.data,
            ct.texture.width,
            ct.texture.height,
            bt.texture.data,
            bt.texture.width,
            bt.texture.height,
        );
        errdefer page.release();

        const pages = try allocator.alloc(*AtlasPage, 1);
        errdefer allocator.free(pages);
        pages[0] = page;

        var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
        errdefer atlas.deinit();
        atlas.layer_info_data = layer_info_data;
        atlas.layer_info_width = kPathPaintInfoWidth;
        atlas.layer_info_height = paint_height;
        if (has_image_paints) {
            atlas.paint_image_records = paint_image_records;
        } else {
            allocator.free(paint_image_records);
        }

        return .{
            .allocator = allocator,
            .atlas = atlas,
            .instances = instances,
        };
    }
};

pub const PathBatch = struct {
    buf: []f32,
    len: usize = 0,

    pub fn init(buf: []f32) PathBatch {
        return .{ .buf = buf };
    }

    pub fn reset(self: *PathBatch) void {
        self.len = 0;
    }

    pub fn shapeCount(self: *const PathBatch) usize {
        return self.len / FLOATS_PER_GLYPH;
    }

    pub fn slice(self: *const PathBatch) []const f32 {
        return self.buf[0..self.len];
    }

    fn coerceAtlasView(atlas_like: anytype) AtlasView {
        const T = @TypeOf(atlas_like);
        return switch (T) {
            *const AtlasView, *AtlasView => atlas_like.*,
            *const Atlas, *Atlas => .{ .atlas = atlas_like, .layer_base = 0 },
            else => @compileError("expected *Atlas or *AtlasView"),
        };
    }

    pub fn addPicture(self: *PathBatch, atlas_like: anytype, picture: *const PathPicture) usize {
        return self.addPictureTransformed(atlas_like, picture, .identity);
    }

    pub fn addPictureTransformed(
        self: *PathBatch,
        atlas_like: anytype,
        picture: *const PathPicture,
        transform: VectorTransform2D,
    ) usize {
        const resolved_view = coerceAtlasView(atlas_like);
        const view = &resolved_view;
        var count: usize = 0;
        for (picture.instances) |instance| {
            if (self.len + FLOATS_PER_GLYPH > self.buf.len) break;
            const final_transform = VectorTransform2D.multiply(transform, instance.transform);
            const info_loc = view.layerInfoLoc(instance.info_x, instance.info_y);
            if (!vertex_mod.generateMultiLayerGlyphVerticesTransformed(
                self.buf[self.len..],
                instance.bbox,
                info_loc.x,
                info_loc.y,
                instance.layer_count,
                .{ 1, 1, 1, 1 },
                view.glyphLayer(instance.page_index),
                final_transform,
            )) continue;
            self.len += FLOATS_PER_GLYPH;
            count += 1;
        }
        return count;
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
        try sprite_pipeline.init();
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
                sprite_pipeline.deinit();
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

    /// Upload one or more images to the renderer's shared image array.
    pub fn uploadImages(self: *Renderer, images: []const *const Image, out_views: []ImageView) void {
        std.debug.assert(images.len == out_views.len);
        switch (self.backend) {
            .gl => pipeline.buildImageArray(images, out_views),
            .vulkan => vulkan_pipeline.buildImageArray(images, out_views),
        }
    }

    /// Convenience: upload a single image and return its current view.
    pub fn uploadImage(self: *Renderer, image: *const Image) ImageView {
        const arr = [1]*const Image{image};
        var views = [1]ImageView{undefined};
        self.uploadImages(&arr, &views);
        return views[0];
    }

    /// Convenience: upload a single atlas and return its view.
    pub fn uploadAtlas(self: *Renderer, atlas: *const Atlas) AtlasView {
        const arr = [1]*const Atlas{atlas};
        var views = [1]AtlasView{undefined};
        self.uploadAtlases(&arr, &views);
        return views[0];
    }

    /// Convenience: upload the atlas embedded in a frozen path picture.
    pub fn uploadPathPicture(self: *Renderer, picture: *const PathPicture) AtlasView {
        return self.uploadAtlas(&picture.atlas);
    }

    /// Reset cached GL state (program, textures). Call once per frame
    /// before draw() when other renderers share the GL context.
    pub fn beginFrame(self: *Renderer) void {
        switch (self.backend) {
            .gl => {
                pipeline.resetFrameState();
                sprite_pipeline.resetFrameState();
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

    /// Draw analytic path/glyph vertices with grayscale AA, ignoring LCD subpixel mode.
    pub fn drawPaths(self: *Renderer, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        switch (self.backend) {
            .gl => pipeline.drawTextGrayscale(vertices, mvp, viewport_w, viewport_h),
            .vulkan => vulkan_pipeline.drawTextGrayscale(vertices, mvp, viewport_w, viewport_h),
        }
    }

    /// Draw sprite vertices in pixel space with a top-left origin.
    pub fn drawSprites(self: *Renderer, vertices: []const f32, viewport_w: f32, viewport_h: f32) void {
        self.drawSpritesTransformed(vertices, Mat4.ortho(0, viewport_w, viewport_h, 0, -1, 1), viewport_w, viewport_h);
    }

    /// Draw sprite vertices with an explicit object-to-clip transform.
    pub fn drawSpritesTransformed(self: *Renderer, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        switch (self.backend) {
            .gl => {
                sprite_pipeline.drawSprites(vertices, mvp);
                pipeline.resetFrameState();
            },
            .vulkan => vulkan_pipeline.drawSprites(vertices, mvp, viewport_w, viewport_h),
        }
    }

    pub fn drawSpritePicture(self: *Renderer, picture: *const SpritePicture, viewport_w: f32, viewport_h: f32) void {
        self.drawSprites(picture.slice(), viewport_w, viewport_h);
    }

    pub fn drawSpritePictureTransformed(self: *Renderer, picture: *const SpritePicture, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        self.drawSpritesTransformed(picture.slice(), mvp, viewport_w, viewport_h);
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
    _ = @import("render/sprite_vertex.zig");
    _ = @import("torture_test.zig");
}

test "vector path approximates cubic commands into quadratic segments and reports bounds" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });

    try std.testing.expect(path.curves.items.len > 0);
    const last = path.curves.items[path.curves.items.len - 1];
    try std.testing.expectEqual(bezier.CurveKind.quadratic, last.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 24), last.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last.p2.y, 0.001);

    const bounds = path.bounds() orelse return error.TestExpectedEqual;
    try std.testing.expect(bounds.max.y > 0);
    try std.testing.expect(bounds.min.y < 0);
}

test "path picture freeze compiles atlas and transformed batch vertices" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 16, .y = 0 });
    try path.lineTo(.{ .x = 8, .y = 12 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .color = .{ 0.8, 0.2, 0.1, 1.0 } }, .{
        .xx = 1,
        .xy = 0,
        .tx = 20,
        .yx = 0,
        .yy = 1,
        .ty = 30,
    });

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(usize, 1), picture.atlas.pageCount());

    var vertex_buf: [FLOATS_PER_GLYPH]f32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const view = AtlasView{ .atlas = &picture.atlas };
    try std.testing.expectEqual(@as(usize, 1), batch.addPicture(&view, &picture));
    try std.testing.expectEqual(@as(usize, FLOATS_PER_GLYPH), batch.slice().len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), batch.slice()[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), batch.slice()[1], 0.001);
    const packed_gw: u32 = @bitCast(batch.slice()[7]);
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectApproxEqAbs(@as(f32, 0), batch.slice()[15], 0.001);
}

test "path batch offsets layer info rows through atlas views" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .color = .{ 0.4, 0.7, 0.9, 1.0 } }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    var vertex_buf: [FLOATS_PER_GLYPH]f32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const offset_view = AtlasView{
        .atlas = &picture.atlas,
        .layer_base = 3,
        .info_row_base = 17,
    };
    try std.testing.expectEqual(@as(usize, 1), batch.addPicture(&offset_view, &picture));
    const packed_gz: u32 = @bitCast(batch.slice()[6]);
    try std.testing.expectEqual(@as(u32, picture.instances[0].info_x), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, offset_view.info_row_base + picture.instances[0].info_y), packed_gz >> 16);
    try std.testing.expectApproxEqAbs(@as(f32, offset_view.glyphLayer(0)), batch.slice()[15], 0.001);
}

test "styled path builder emits fill and stroke records" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 4, .y = 6, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(
        &path,
        .{ .color = .{ 0.2, 0.4, 0.8, 1.0 } },
        .{ .color = .{ 0.9, 0.8, 0.2, 1.0 }, .width = 4.0, .join = .round },
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(u16, 2), picture.instances[0].layer_count);
    try std.testing.expectEqual(@as(u16, 0), picture.instances[0].info_x);
    try std.testing.expectEqual(@as(u16, 0), picture.instances[0].info_y);

    const fill_info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.instances[0].glyph_id + 1) orelse return error.TestExpectedEqual;
    try std.testing.expect(stroke_info.bbox.min.x < fill_info.bbox.min.x);
    try std.testing.expect(stroke_info.bbox.max.x > fill_info.bbox.max.x);
    try std.testing.expect(stroke_info.bbox.min.y < fill_info.bbox.min.y);
    try std.testing.expect(stroke_info.bbox.max.y > fill_info.bbox.max.y);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPathPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), lid[0], 0.001);
    try std.testing.expectApproxEqAbs(kPathPaintTagSolid, lid[7], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), lid[12], 0.001);
    try std.testing.expectApproxEqAbs(kPathPaintTagSolid, lid[31], 0.001);
}

test "open stroked path expands for round caps" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 12, .y = 0 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addStrokedPath(&path, .{
        .color = .{ 1.0, 1.0, 1.0, 1.0 },
        .width = 6.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    const stroke_info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    try std.testing.expect(stroke_info.bbox.min.x < 0.0);
    try std.testing.expect(stroke_info.bbox.max.x > 12.0);
    try std.testing.expect(stroke_info.bbox.min.y < -2.9);
    try std.testing.expect(stroke_info.bbox.max.y > 2.9);
}

test "square-capped stroked path extends beyond endpoints" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 12, .y = 0 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .width = 6.0,
        .cap = .square,
        .join = .miter,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), stroke_geom.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), stroke_geom.bbox.max.y, 0.05);
}

test "elliptical stroke outline stays curved without degenerate joins" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addEllipse(.{ .x = 0, .y = 0, .w = 100, .h = 60 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .width = 8.0,
        .join = .round,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    var curved_count: usize = 0;
    for (stroke_geom.curves) |curve| {
        try std.testing.expect(Vec2.length(Vec2.sub(curve.endPoint(), curve.p0)) > 1e-4);
        const chord_mid = Vec2.lerp(curve.p0, curve.endPoint(), 0.5);
        const curve_mid = curve.evaluate(0.5);
        if (Vec2.length(Vec2.sub(curve_mid, chord_mid)) > 1e-3) curved_count += 1;
    }
    try std.testing.expect(curved_count >= 8);
}

test "rounded rect corners are approximated with quadratic segments" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRoundedRect(.{ .x = 0, .y = 0, .w = 200, .h = 200 }, 40);

    try std.testing.expect(path.curves.items.len > 8);
    for (path.curves.items) |curve| {
        try std.testing.expectEqual(bezier.CurveKind.quadratic, curve.kind);
    }
}

test "inside-aligned generic path stroke groups fill and stroke on one instance" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRoundedRect(.{ .x = 10, .y = 20, .w = 40, .h = 18 }, 6.0);

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(
        &path,
        .{ .color = .{ 0.1, 0.2, 0.3, 0.4 } },
        .{ .color = .{ 0.8, 0.7, 0.6, 1.0 }, .width = 2.0, .join = .round, .placement = .inside },
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(u16, 2), picture.instances[0].layer_count);

    const fill_info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.instances[0].glyph_id + 1) orelse return error.TestExpectedEqual;

    try std.testing.expectApproxEqAbs(@as(f32, 10), fill_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), fill_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 50), fill_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 38), fill_info.bbox.max.y, 0.05);
    try std.testing.expect(stroke_info.bbox.min.x < fill_info.bbox.min.x);
    try std.testing.expect(stroke_info.bbox.max.x > fill_info.bbox.max.x);

    try std.testing.expectApproxEqAbs(@as(f32, 10), picture.instances[0].bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), picture.instances[0].bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 50), picture.instances[0].bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 38), picture.instances[0].bbox.max.y, 0.05);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPathPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @intFromEnum(PathCompositeMode.fill_stroke_inside)), lid[1], 0.001);
}

test "inside-aligned rounded rect helper emits explicit ring geometry" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(
        .{ .x = 10, .y = 20, .w = 40, .h = 18 },
        .{ .color = .{ 0.1, 0.2, 0.3, 0.4 } },
        .{ .color = .{ 0.8, 0.7, 0.6, 1.0 }, .width = 2.0, .join = .round, .placement = .inside },
        6.0,
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(u16, 2), picture.instances[0].layer_count);

    const fill_info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.instances[0].glyph_id + 1) orelse return error.TestExpectedEqual;

    try std.testing.expectApproxEqAbs(fill_info.bbox.min.x, stroke_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.min.y, stroke_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.max.x, stroke_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.max.y, stroke_info.bbox.max.y, 0.05);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPathPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @intFromEnum(PathCompositeMode.source_over)), lid[1], 0.001);
}

test "path picture gradient paint records encode linear and radial paints" {
    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 20, .y = 0 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
            .extend = .reflect,
        } },
    }, .{
        .paint = .{ .radial_gradient = .{
            .center = .{ .x = 10, .y = 5 },
            .radius = 12,
            .inner_color = .{ 1, 1, 1, 1 },
            .outer_color = .{ 0, 0, 0, 0 },
        } },
        .width = 2,
    }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPathPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(kPathPaintTagLinearGradient, lid[7], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), lid[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PathPaintExtend.reflect))), lid[24], 0.001);

    const radial_base = @as(usize, (1 + kPathPaintTexelsPerRecord)) * 4;
    try std.testing.expectApproxEqAbs(kPathPaintTagRadialGradient, lid[radial_base + 3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), lid[radial_base + 8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), lid[radial_base + 9], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), lid[radial_base + 10], 0.001);
}

test "path picture image paint records keep image metadata" {
    var image = try Image.initRgba8(std.testing.allocator, 2, 2, &.{
        255, 0,   0,   255,
        0,   255, 0,   255,
        0,   0,   255, 255,
        255, 255, 255, 255,
    });
    defer image.deinit();

    var path = VectorPath.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 12, .h = 8 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .{ .xx = 0.5, .xy = 0.0, .tx = 0.25, .yx = 0.0, .yy = 1.0, .ty = 0.0 },
            .tint = .{ 0.5, 0.75, 1.0, 0.25 },
            .extend_x = .repeat,
            .extend_y = .reflect,
            .filter = .nearest,
        } },
    }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    const records = picture.atlas.paint_image_records orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expect(records[0] != null);
    try std.testing.expect(records[0].?.image == &image);
    try std.testing.expectEqual(@as(u32, 0), records[0].?.texel_offset);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(PATH_PAINT_TAG_IMAGE, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), lid[8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), lid[10], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(ImageFilter.nearest))), lid[15], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), lid[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PathPaintExtend.repeat))), lid[22], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PathPaintExtend.reflect))), lid[23], 0.001);
}

test "sprite batch packs transformed image quads" {
    var image = try Image.initRgba8(std.testing.allocator, 4, 2, &.{
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    });
    defer image.deinit();

    var buf: [SPRITE_FLOATS_PER_SPRITE]f32 = undefined;
    var batch = SpriteBatch.init(&buf);
    try std.testing.expect(batch.addSpriteRect(
        ImageView{ .image = &image, .layer = 7, .uv_scale = .{ .x = 0.5, .y = 0.25 } },
        .{ .x = 10, .y = 20, .w = 16, .h = 12 },
        .{ 1, 0.5, 0.25, 1 },
        .{ .u0 = 0.25, .v0 = 0.0, .u1 = 0.75, .v1 = 1.0 },
        .nearest,
    ));
    try std.testing.expectEqual(@as(usize, 1), batch.spriteCount());
    try std.testing.expectApproxEqAbs(@as(f32, 10), batch.slice()[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), batch.slice()[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), batch.slice()[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.375), batch.slice()[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), batch.slice()[8], 0.001);

    var picture = try batch.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.spriteCount());
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
