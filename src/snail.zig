//! snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
//!
//! ## Color convention
//!
//! All colors are sRGB, straight (unpremultiplied) alpha, as `[4]f32` in 0.0–1.0.
//! The renderer premultiplies alpha and handles linearization for blending internally.
//! Image pixel data (`Image.initSrgba8`) is sRGB RGBA8 (4 bytes per pixel).
//! Gradient interpolation is in sRGB space (perceptually uniform).
//!
//! ## Public model
//!
//! CPU values are app-owned, immutable after construction where applicable, and
//! shareable across renderers: `TextAtlas`, `ShapedText`, `TextBlob`, `Image`,
//! `PathPicture`, and borrowed `Scene` command lists. `Path` is the mutable
//! vector builder.
//!
//! Resource realization is explicit. `ResourceSet` is a caller-buffered borrowed
//! manifest of CPU values. `PreparedResources` is the backend-specific
//! realization for one renderer/context. `DrawList` is caller-buffered draw
//! records, and `PreparedScene` is the optional owned cache of those records.
//!
//! Drawing consumes only `PreparedResources` plus draw records. It does not
//! discover, upload, allocate, or invalidate resources.
//!
//! ## Usage
//!
//!   var text_atlas = try snail.TextAtlas.init(allocator, &.{.{ .data = ttf_bytes }});
//!   defer text_atlas.deinit();
//!   if (try text_atlas.ensureText(.{}, "Hello")) |next| {
//!       text_atlas.deinit();
//!       text_atlas = next;
//!   }
//!
//!   var builder = snail.TextBlobBuilder.init(allocator, &text_atlas);
//!   defer builder.deinit();
//!   _ = try builder.addText(.{}, "Hello", 40, 80, 24, .{ 0, 0, 0, 1 });
//!   var text_blob = try builder.finish();
//!   defer text_blob.deinit();
//!
//!   var scene = snail.Scene.init(allocator);
//!   defer scene.deinit();
//!   try scene.addText(&text_blob);
//!
//!   var resource_entries: [8]snail.ResourceSet.Entry = undefined;
//!   var resources = snail.ResourceSet.init(&resource_entries);
//!   try resources.addScene(&scene);
//!   var gl = try snail.GlRenderer.init(allocator);
//!   defer gl.deinit();
//!   var prepared = try gl.uploadResourcesBlocking(allocator, &resources);
//!   defer prepared.deinit();
//!
//!   const options = snail.DrawOptions{ .mvp = snail.Mat4.identity, .target = .{
//!       .pixel_width = 1280, .pixel_height = 720, .subpixel_order = .rgb,
//!   } };
//!   var buf = try allocator.alloc(u32, snail.DrawList.estimate(&scene, options));
//!   var segments = try allocator.alloc(snail.DrawSegment, snail.DrawList.estimateSegments(&scene, options));
//!   defer allocator.free(buf);
//!   defer allocator.free(segments);
//!   var draw = snail.DrawList.init(buf, segments);
//!   try draw.addScene(&prepared, &scene, options);
//!   try gl.draw(&prepared, draw.slice(), options);

const std = @import("std");
const build_options = @import("build_options");
const glyph_emit = @import("glyph_emit.zig");
const fonts_mod = @import("fonts.zig");
const ttf = @import("font/ttf.zig");
const opentype = @import("font/opentype.zig");
// Internal modules — not part of the public API surface. Exposed for internal
// tools (e.g. cpu_renderer) that need raw curve/texture data access.
pub const bezier = @import("math/bezier.zig");
const vec = @import("math/vec.zig");
pub const curve_tex = @import("render/curve_texture.zig");
const band_tex = @import("render/band_texture.zig");
const vertex_mod = @import("render/vertex.zig");
const roots = @import("math/roots.zig");
const pipeline = @import("render/pipeline.zig");
const cpu_renderer_mod = if (build_options.enable_cpu) @import("cpu_renderer.zig") else struct {
    pub const CpuRenderer = void;
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("render/vulkan_pipeline.zig") else struct {
    pub const VulkanContext = void;
    pub const PreparedResources = void;
    pub const VulkanPipeline = struct {
        subpixel_order: @import("render/subpixel_order.zig").SubpixelOrder = .none,
        fill_rule: FillRule = .non_zero,
        pub fn init(_: *VulkanPipeline, _: anytype) !void {}
        pub fn deinit(_: *VulkanPipeline) void {}
        pub fn beginFrame(_: *VulkanPipeline) void {}
        pub fn backendName(_: *const VulkanPipeline) []const u8 {
            return "vulkan (disabled)";
        }
    };
};
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
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
/// Underline and strikethrough metrics from the post and OS/2 tables, in font units.
pub const DecorationMetrics = ttf.DecorationMetrics;
/// Superscript or subscript metrics from the OS/2 table, in font units.
pub const ScriptMetrics = ttf.ScriptMetrics;
pub const Transform2D = vec.Transform2D;
pub const TextAtlas = fonts_mod.TextAtlas;
pub const ShapedText = fonts_mod.ShapedText;
const PreparedTextAtlasView = struct {
    layer_base: u32 = 0,
    info_row_base: u32 = 0,
};
pub const TextBlob = fonts_mod.TextBlob;
pub const TextBlobOptions = fonts_mod.TextBlobOptions;
pub const TextBlobBuilder = fonts_mod.TextBlobBuilder;
pub const FaceSpec = fonts_mod.FaceSpec;
/// Uniform locations and texture units used when a caller evaluates Snail text
/// coverage inside their own GL shader.
pub const TextCoverageBindings = pipeline.TextCoverageBindings;

/// GLSL 330 pieces for material shaders that consume Snail text coverage.
///
/// Include `glsl330_vertex_interface` in a vertex shader that draws prepared
/// text coverage geometry, and `glsl330_fragment_interface` plus
/// `glsl330_fragment_body` in the fragment shader. The fragment body exposes
/// `snail_text_coverage()`, `snail_text_color_srgb()`, and
/// `snail_text_color_linear()` for use as material inputs. Material shaders
/// that evaluate coverage without Snail's text varyings can instead include
/// `glsl330_resource_interface` and `glsl330_coverage_functions`.
pub const TextCoverageShader = struct {
    pub const glsl330_vertex_interface = pipeline.text_vertex_interface;
    pub const glsl330_fragment_interface = pipeline.text_coverage_fragment_interface;
    pub const glsl330_resource_interface =
        \\uniform sampler2DArray u_curve_tex;
        \\uniform usampler2DArray u_band_tex;
        \\uniform int u_fill_rule;
        \\
        \\#define SNAIL_FILL_RULE u_fill_rule
        \\
    ;
    pub const glsl330_coverage_functions = pipeline.text_coverage_fragment_body;
    pub const glsl330_fragment_body =
        glsl330_coverage_functions ++
        "\n" ++
        \\float snail_text_coverage() {
        \\    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
        \\    if (atlas_layer == 0xFF) return 0.0;
        \\    vec2 rc = v_texcoord;
        \\    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
        \\    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
        \\    vec2 ppe = vec2(1.0 / max(length(dx), 1.0 / 65536.0), 1.0 / max(length(dy), 1.0 / 65536.0));
        \\    return evalGlyphCoverage(rc, ppe, v_glyph.xy,
        \\                             ivec2(v_glyph.z, v_glyph.w & 0xFF),
        \\                             v_banding, atlas_layer);
        \\}
        \\
        \\vec4 snail_text_color_srgb() {
        \\    return v_color;
        \\}
        \\
        \\vec4 snail_text_color_linear() {
        \\    return vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
        \\}
        \\
        ;
};

/// Resolve options used when preparing text coverage geometry for a custom
/// material shader.
pub const TextCoverageOptions = struct {
    transform: Transform2D = .identity,
    resolve: TextResolveOptions = .{},
    target: ResolveTarget = .{
        .pixel_width = 1.0,
        .pixel_height = 1.0,
        .subpixel_order = .none,
        .is_final_composite = false,
        .opaque_backdrop = false,
    },
    scene_to_screen: ?Transform2D = null,
};

/// Prepared glyph coverage records for use by a custom material shader.
///
/// This owns only the per-glyph draw data. Snail atlas textures come from
/// PreparedResources.
pub const TextCoverageRecords = struct {
    allocator: std.mem.Allocator,
    vertices: []u32 = &.{},
    atlas: ?*const TextAtlas = null,
    atlas_stamp: ResourceStamp = .{},

    pub fn initOwned(allocator: std.mem.Allocator) TextCoverageRecords {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TextCoverageRecords) void {
        if (self.vertices.len > 0) self.allocator.free(self.vertices);
        self.* = undefined;
    }

    pub fn glyphCount(self: *const TextCoverageRecords) usize {
        return self.vertices.len / TEXT_WORDS_PER_GLYPH;
    }

    pub fn slice(self: *const TextCoverageRecords) []const u32 {
        return self.vertices;
    }

    pub fn buildLocal(
        self: *TextCoverageRecords,
        prepared: *const PreparedResources,
        blob: *const TextBlob,
        options: TextCoverageOptions,
    ) !void {
        const atlas_view = try prepared.textAtlasView(blob.atlas);
        const scratch = try self.allocator.alloc(u32, @max(blob.instance_count_hint, 1) * TEXT_WORDS_PER_GLYPH);
        defer self.allocator.free(scratch);

        var batch = TextBatch.init(scratch);
        _ = try blob.appendToBatch(
            &batch,
            atlas_view,
            options.transform,
            options.resolve,
            options.target,
            options.scene_to_screen,
        );

        if (self.vertices.len > 0) self.allocator.free(self.vertices);
        self.vertices = try self.allocator.dupe(u32, batch.slice());
        self.atlas = blob.atlas;
        self.atlas_stamp = try prepared.textStamp(blob.atlas);
    }

    pub fn rebuildLocal(
        self: *TextCoverageRecords,
        prepared: *const PreparedResources,
        blob: *const TextBlob,
        options: TextCoverageOptions,
    ) !void {
        try self.buildLocal(prepared, blob, options);
    }

    pub fn validFor(self: *const TextCoverageRecords, prepared: *const PreparedResources) bool {
        const atlas = self.atlas orelse return false;
        const stamp = prepared.textStamp(atlas) catch return false;
        return self.atlas_stamp.eql(stamp);
    }
};

/// GL backend hook for evaluating Snail coverage inside caller-owned shaders.
pub const TextCoverageBackend = struct {
    gl: *pipeline.GlTextState,
    gl_resources: *const pipeline.PreparedResources,
    prepared: *const PreparedResources,

    fn glState(self: TextCoverageBackend) *pipeline.GlTextState {
        return self.gl;
    }

    pub fn bindResources(self: TextCoverageBackend, bindings: TextCoverageBindings) void {
        self.gl_resources.bindTextCoverageResources(bindings);
    }

    pub fn drawCoverage(self: TextCoverageBackend, coverage: *const TextCoverageRecords) void {
        std.debug.assert(coverage.validFor(self.prepared));
        self.drawVertices(coverage.slice());
    }

    pub fn drawVertices(self: TextCoverageBackend, vertices: []const u32) void {
        self.glState().drawPreparedText(self.gl_resources, vertices);
    }

    pub fn draw(self: TextCoverageBackend, vertices: []const u32) void {
        self.drawVertices(vertices);
    }

    pub fn bind(self: TextCoverageBackend, bindings: TextCoverageBindings) void {
        self.bindResources(bindings);
    }
};

/// A positioned glyph in a shaped run. Carries source-span metadata so callers
/// can reason about ligatures, cells, selection, and painting.
pub const GlyphPlacement = struct {
    glyph_id: u16,
    x_offset: f32, // pixel offset from run origin
    y_offset: f32, // pixel offset from run origin
    x_advance: f32, // pixel advance for this glyph
    y_advance: f32, // pixel advance (0 for horizontal text)
    source_start: u32, // byte offset in source text
    source_end: u32, // byte offset in source text
};

/// A shaped text run: the output of shaping a UTF-8 string.
/// The built-in shaper and HarfBuzz both produce this same type.
pub const ShapedRun = struct {
    glyphs: []const GlyphPlacement,
    advance_x: f32, // total advance in pixels
    advance_y: f32, // total advance in pixels
};

pub const PATH_PAINT_INFO_WIDTH: u32 = 4096;
pub const PATH_PAINT_TEXELS_PER_RECORD: u32 = 6;
pub const PATH_PAINT_TAG_SOLID: f32 = -1.0;
pub const PATH_PAINT_TAG_LINEAR_GRADIENT: f32 = -2.0;
pub const PATH_PAINT_TAG_RADIAL_GRADIENT: f32 = -3.0;
pub const PATH_PAINT_TAG_IMAGE: f32 = -4.0;
pub const PATH_PAINT_TAG_COMPOSITE_GROUP: f32 = -5.0;

pub const PathPictureDebugView = enum(u8) {
    normal,
    fill_mask,
    stroke_mask,
    layer_tint,
};

pub const PathPictureBoundsOverlayOptions = struct {
    stroke_color: [4]f32 = .{ 1.0, 0.36, 0.24, 0.95 },
    stroke_width: f32 = 1.0,
    origin_color: [4]f32 = .{ 1.0, 0.78, 0.22, 0.95 },
    origin_size: f32 = 6.0,
};

// Text batch sizing constants
pub const TEXT_WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = vertex_mod.VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = TEXT_WORDS_PER_VERTEX * TEXT_VERTICES_PER_GLYPH;

// Path batch sizing constants (same vertex format as text)
pub const PATH_WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = vertex_mod.VERTICES_PER_GLYPH;
pub const PATH_WORDS_PER_SHAPE = PATH_WORDS_PER_VERTEX * PATH_VERTICES_PER_SHAPE;

/// One byte in the hot instance format is reserved for the local texture-array
/// layer. 0xff is still the special-instance sentinel, so draw records split
/// layer bindings into 255-layer windows and carry the window base separately.
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

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const PaintExtend = enum(u8) {
    clamp = 0,
    repeat = 1,
    reflect = 2,
};

pub const ImageFilter = enum(u8) {
    linear = 0,
    nearest = 1,
};

pub const FontWeight = enum(u4) {
    thin = 1,
    extra_light = 2,
    light = 3,
    regular = 4,
    medium = 5,
    semi_bold = 6,
    bold = 7,
    extra_bold = 8,
    black = 9,
};

pub const FontStyle = struct {
    weight: FontWeight = .regular,
    italic: bool = false,
};

/// Synthetic style transforms applied at the vertex level during glyph emission.
pub const SyntheticStyle = struct {
    /// Extra stroke offset in pixels (scaled by font_size / units_per_em). 0 = none.
    embolden: f32 = 0,
    /// Horizontal shear factor. 0.2 ≈ 12° synthetic italic. 0 = upright.
    skew_x: f32 = 0,
};

pub const Image = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    /// Immutable sRGBA8 pixels. Initialize with initSrgba8; mutation requires
    /// constructing a new Image so content stamps remain meaningful.
    pixels: []const u8,

    pub fn initSrgba8(allocator: std.mem.Allocator, width: u32, height: u32, pixels: []const u8) !Image {
        if (width == 0 or height == 0) return error.InvalidImageData;
        const px_count = std.math.mul(usize, width, height) catch return error.InvalidImageData;
        const byte_count = std.math.mul(usize, px_count, 4) catch return error.InvalidImageData;
        if (pixels.len != byte_count) return error.InvalidImageData;
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

    pub fn pixelSlice(self: *const Image) []const u8 {
        return self.pixels;
    }
};

const PreparedImageView = struct {
    image: *const Image,
    layer: u16 = 0,
    uv_scale: Vec2 = .{ .x = 1.0, .y = 1.0 },
};

pub const LinearGradient = struct {
    start: Vec2,
    end: Vec2,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: PaintExtend = .clamp,
};

pub const RadialGradient = struct {
    center: Vec2,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: PaintExtend = .clamp,
};

pub const ImagePaint = struct {
    image: *const Image,
    uv_transform: Transform2D = .identity,
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    extend_x: PaintExtend = .clamp,
    extend_y: PaintExtend = .clamp,
    filter: ImageFilter = .linear,
};

pub const Paint = union(enum) {
    solid: [4]f32,
    linear_gradient: LinearGradient,
    radial_gradient: RadialGradient,
    image: ImagePaint,
};

pub const FillStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint: ?Paint = null,
};

pub const StrokeCap = enum {
    butt,
    square,
    round,
};

pub const StrokeJoin = enum {
    miter,
    bevel,
    round,
};

pub const StrokePlacement = enum {
    center,
    inside,
};

pub const StrokeStyle = struct {
    // Straight RGBA; the renderer premultiplies internally.
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint: ?Paint = null,
    width: f32,
    cap: StrokeCap = .butt,
    join: StrokeJoin = .miter,
    miter_limit: f32 = 4.0,
    placement: StrokePlacement = .center,
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

    /// Underline and strikethrough metrics from the post and OS/2 tables, in font units.
    pub fn decorationMetrics(self: *const Font) !DecorationMetrics {
        return self.inner.decorationMetrics();
    }

    /// Superscript size and offset from the OS/2 table, in font units.
    pub fn superscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.superscriptMetrics();
    }

    /// Subscript size and offset from the OS/2 table, in font units.
    pub fn subscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.subscriptMetrics();
    }

    pub fn bbox(self: *const Font, glyph_id: u16) !BBox {
        return self.inner.bbox(glyph_id);
    }
};

pub fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}

/// Pre-built curve-page texture data for glyphs and vector paths.
/// This is the low-level storage format behind TextAtlas and PathPicture.
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

/// Low-level immutable curve atlas snapshot. App text should normally use
/// TextAtlas; CurveAtlas exists for backend/resource plumbing and advanced
/// curve-page users.
pub const CurveAtlas = struct {
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

        var ct = try curve_tex.buildCurveTexture(allocator, glyph_curves_list.items);
        errdefer ct.texture.deinit();
        errdefer allocator.free(ct.entries);

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

    /// Convenience: extend the atlas with all glyph IDs referenced by a shaped run.
    pub fn extendRun(self: *const Atlas, run: *const ShapedRun) !?Atlas {
        var requested = std.AutoHashMap(u16, void).init(self.allocator);
        defer requested.deinit();
        for (run.glyphs) |g| {
            if (g.glyph_id == 0) continue;
            try requested.put(g.glyph_id, {});
        }
        return self.extendGlyphIdSet(&requested);
    }

    /// Write glyph IDs from `run` that are not yet in this atlas into `out`.
    /// Returns the number of unique missing IDs written. Duplicates are suppressed.
    pub fn collectMissingGlyphIds(self: *const Atlas, run: *const ShapedRun, out: []u16) usize {
        var seen = std.StaticBitSet(65536).initEmpty();
        var count: usize = 0;
        for (run.glyphs) |g| {
            if (g.glyph_id == 0) continue;
            if (seen.isSet(g.glyph_id)) continue;
            if (self.getGlyph(g.glyph_id) != null) continue;
            if (self.colrLayerCount(g.glyph_id) > 0) continue;
            seen.set(g.glyph_id);
            if (count < out.len) {
                out[count] = g.glyph_id;
                count += 1;
            }
        }
        return count;
    }

    /// Shape a UTF-8 string into a run of glyph placements.
    /// Uses the built-in limited shaper (GSUB ligatures + GPOS/kern kerning).
    /// The caller must free `result.glyphs` with the same allocator.
    pub fn shapeUtf8(self: *const Atlas, font: *const Font, text: []const u8, font_size: f32, allocator: std.mem.Allocator) !ShapedRun {
        if (text.len == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

        const scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));

        // Count codepoints
        var cp_count: usize = 0;
        {
            const utf8_view = std.unicode.Utf8View.initUnchecked(text);
            var it = utf8_view.iterator();
            while (it.nextCodepoint()) |_| cp_count += 1;
        }
        if (cp_count == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

        // Map codepoints to glyph IDs with source byte tracking
        const gids = try allocator.alloc(u16, cp_count);
        defer allocator.free(gids);
        const src_starts = try allocator.alloc(u32, cp_count);
        defer allocator.free(src_starts);
        const src_ends = try allocator.alloc(u32, cp_count);
        defer allocator.free(src_ends);

        var idx: usize = 0;
        {
            const utf8_view = std.unicode.Utf8View.initUnchecked(text);
            var it = utf8_view.iterator();
            while (it.nextCodepointSlice()) |cp_slice| {
                const byte_pos = @intFromPtr(cp_slice.ptr) - @intFromPtr(text.ptr);
                const cp = std.unicode.utf8Decode(cp_slice) catch 0;
                gids[idx] = font.glyphIndex(@intCast(cp)) catch 0;
                src_starts[idx] = @intCast(byte_pos);
                src_ends[idx] = @intCast(byte_pos + cp_slice.len);
                idx += 1;
            }
        }

        // Apply ligature substitution with source span tracking
        var glyph_count = idx;
        if (self.shaper) |shaper| {
            glyph_count = shaper.applyLigaturesTracked(
                gids[0..glyph_count],
                src_starts[0..glyph_count],
                src_ends[0..glyph_count],
            ) catch glyph_count;
        }

        // Build positioned placements with kerning
        const placements = try allocator.alloc(GlyphPlacement, glyph_count);
        errdefer allocator.free(placements);

        var cursor_x: f32 = 0;
        var prev_gid: u16 = 0;
        var i: usize = 0;
        while (i < glyph_count) : (i += 1) {
            const gid = gids[i];
            if (gid == 0) {
                const fallback_advance = scale * 500;
                placements[i] = .{
                    .glyph_id = 0,
                    .x_offset = cursor_x,
                    .y_offset = 0,
                    .x_advance = fallback_advance,
                    .y_advance = 0,
                    .source_start = src_starts[i],
                    .source_end = src_ends[i],
                };
                cursor_x += fallback_advance;
                prev_gid = 0;
                continue;
            }

            // Kerning: prefer GPOS, fall back to kern table
            if (prev_gid != 0) {
                var kern: i16 = 0;
                if (self.shaper) |shaper| {
                    kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
                }
                if (kern == 0) {
                    kern = font.getKerning(prev_gid, gid) catch 0;
                }
                cursor_x += @as(f32, @floatFromInt(kern)) * scale;
            }

            const advance_units: i16 = font.advanceWidth(gid) catch 500;
            const advance_px = @as(f32, @floatFromInt(advance_units)) * scale;

            placements[i] = .{
                .glyph_id = gid,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance_px,
                .y_advance = 0,
                .source_start = src_starts[i],
                .source_end = src_ends[i],
            };

            cursor_x += advance_px;
            prev_gid = gid;
        }

        return .{
            .glyphs = placements,
            .advance_x = cursor_x,
            .advance_y = 0,
        };
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

const PreparedAtlasView = struct {
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

    // View interface methods used by glyph_emit.
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

fn coerceAtlasHandle(atlas_like: anytype) PreparedAtlasView {
    const T = @TypeOf(atlas_like);
    return switch (T) {
        *const PreparedAtlasView, *PreparedAtlasView => atlas_like.*,
        *const Atlas, *Atlas => .{ .atlas = atlas_like, .layer_base = 0 },
        else => @compileError("expected *CurveAtlas or prepared atlas view"),
    };
}

fn glyphAdvanceUnits(atlas: *const Atlas, font: *const Font, gid: u16) ?u16 {
    if (atlas.glyph_map.get(gid)) |info| return info.advance_width;
    if (atlas.colrLayerCount(gid) > 0) return font.inner.units_per_em;
    return null;
}

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
pub const TextBatch = struct {
    buf: []u32,
    len: usize, // words written
    layer_window_base: ?u32 = null,

    const glyph_stack_capacity = 256;

    const PreparedGlyphs = struct {
        slice: []const u16,
        owned: ?[]u16 = null,

        fn deinit(self: *const PreparedGlyphs, allocator: std.mem.Allocator) void {
            if (self.owned) |buf| allocator.free(buf);
        }
    };

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
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        vertex_mod.generateGlyphVertices(self.buf[self.len..], x, y, font_size, bbox, band_entry, color, local_layer);
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
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
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
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateGlyphVerticesTransformed(self.buf[self.len..], bbox, band_entry, color, local_layer, transform))
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
        if (self.len + TEXT_WORDS_PER_GLYPH > self.buf.len) return error.DrawListFull;
        const local_layer = try self.localLayer(atlas_layer);
        if (!vertex_mod.generateMultiLayerGlyphVerticesTransformed(self.buf[self.len..], union_bbox, info_x, info_y, layer_count, color, local_layer, transform))
            return error.InvalidTransform;
        self.len += TEXT_WORDS_PER_GLYPH;
    }

    /// Append a shaped run. Each glyph's position is relative to (x, y).
    /// Returns the number of glyphs successfully added.
    pub fn addRun(
        self: *TextBatch,
        atlas_like: anytype,
        run: *const ShapedRun,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) usize {
        const resolved_view = coerceAtlasHandle(atlas_like);
        const view = &resolved_view;
        var count: usize = 0;
        for (run.glyphs) |g| {
            switch (glyph_emit.emitGlyph(self, view, g.glyph_id, x + g.x_offset, y + g.y_offset, font_size, color)) {
                .emitted => count += 1,
                .skipped => {},
                .buffer_full => break,
                .layer_window_changed, .invalid_transform => break,
            }
        }
        return count;
    }

    /// Append a shaped run with synthetic style transforms (italic shear, bold offset).
    /// Each glyph's position is relative to (x, y). Returns the number of glyphs
    /// successfully added. When synthetic is identity (.{}), equivalent to addRun.
    pub fn addStyledRun(
        self: *TextBatch,
        atlas_like: anytype,
        run: *const ShapedRun,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
        synthetic: SyntheticStyle,
    ) usize {
        const resolved_view = coerceAtlasHandle(atlas_like);
        const view = &resolved_view;
        var count: usize = 0;
        for (run.glyphs) |g| {
            switch (glyph_emit.emitStyledGlyph(self, view, g.glyph_id, x + g.x_offset, y + g.y_offset, font_size, color, synthetic)) {
                .emitted => count += 1,
                .skipped => {},
                .buffer_full => break,
                .layer_window_changed, .invalid_transform => break,
            }
        }
        return count;
    }

    /// Lay out and append a string. Uses HarfBuzz for shaping when
    /// available (-Dharfbuzz=true), otherwise applies built-in ligature
    /// substitution and GPOS/kern kerning.
    /// Returns advance width in pixels.
    pub fn addText(
        self: *TextBatch,
        atlas_like: anytype,
        font: *const Font,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) f32 {
        const resolved_view = coerceAtlasHandle(atlas_like);
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

            switch (glyph_emit.emitGlyph(self, view, gid, cursor_x, y, font_size, color)) {
                .emitted, .skipped => {},
                .buffer_full, .layer_window_changed, .invalid_transform => break,
            }

            const advance = glyphAdvanceUnits(atlas, font, gid) orelse {
                cursor_x += scale * 500;
                prev_gid = gid;
                continue;
            };
            cursor_x += @as(f32, @floatFromInt(advance)) * scale;
            prev_gid = gid;
        }

        return cursor_x - x;
    }
};

const kPathArcSplitMaxDepth: u8 = 8;
const kPathStrokeOffsetTolerance: f32 = 0.005;
const kPathStrokeOffsetMaxDepth: u8 = 10;
const kPathCurveApproxTolerance: f32 = 0.005;
const kPathCurveApproxMaxDepth: u8 = 10;
const kPathLargePrimitiveTileExtent: f32 = 512.0;

fn makePathLineCurve(p0: Vec2, p1: Vec2) bezier.QuadBezier {
    return .{
        .p0 = p0,
        .p1 = Vec2.lerp(p0, p1, 0.5),
        .p2 = p1,
    };
}

fn makePathLineSegment(p0: Vec2, p1: Vec2) CurveSegment {
    return CurveSegment.fromLine(p0, p1);
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

fn makePathArcConic(center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) CurveSegment {
    const p0 = center.add(Vec2.new(@cos(start_angle) * radii.x, @sin(start_angle) * radii.y));
    const p2 = center.add(Vec2.new(@cos(end_angle) * radii.x, @sin(end_angle) * radii.y));
    const t0 = Vec2.new(-@sin(start_angle) * radii.x, @cos(start_angle) * radii.y);
    const t1 = Vec2.new(-@sin(end_angle) * radii.x, @cos(end_angle) * radii.y);
    const control = lineIntersection(p0, t0, p2, t1) orelse Vec2.lerp(p0, p2, 0.5);
    return CurveSegment.fromConic(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
        .w1 = @cos((end_angle - start_angle) * 0.5),
    });
}

fn appendAdaptiveArcCurve(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
    depth: u8,
) !void {
    const span = end_angle - start_angle;
    if (depth == 0 or @abs(span) <= std.math.pi * 0.125 + 1e-6) {
        path.band_curve_count += 1;
        try path.appendSegment(CurveSegment.fromQuad(makePathArcCurve(center, radii, start_angle, end_angle)));
        return;
    }
    const mid_angle = (start_angle + end_angle) * 0.5;
    try appendAdaptiveArcCurve(path, center, radii, start_angle, mid_angle, depth - 1);
    try appendAdaptiveArcCurve(path, center, radii, mid_angle, end_angle, depth - 1);
}

fn appendAdaptiveArcConic(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
) !void {
    const span = end_angle - start_angle;
    if (@abs(span) <= 1e-6) return;
    if (@abs(span) > std.math.pi * 0.5 + 1e-6) {
        const mid_angle = (start_angle + end_angle) * 0.5;
        try appendAdaptiveArcConic(path, center, radii, start_angle, mid_angle);
        try appendAdaptiveArcConic(path, center, radii, mid_angle, end_angle);
        return;
    }
    path.band_curve_count += 1;
    try path.appendSegment(makePathArcConic(center, radii, start_angle, end_angle));
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

fn appendLineIfNeeded(path: *Path, point: Vec2) !void {
    if (!pointsApproxEqual(path.requireContour().?.current_point, point)) {
        try path.lineTo(point);
    }
}

fn resolveFillPaint(style: FillStyle) Paint {
    return style.paint orelse .{ .solid = style.color };
}

fn resolveStrokePaint(style: StrokeStyle) Paint {
    return style.paint orelse .{ .solid = style.color };
}

fn translateBBox(bbox: BBox, delta: Vec2) BBox {
    return .{
        .min = Vec2.add(bbox.min, delta),
        .max = Vec2.add(bbox.max, delta),
    };
}

fn bboxCenter(bbox: BBox) Vec2 {
    return .{
        .x = (bbox.min.x + bbox.max.x) * 0.5,
        .y = (bbox.min.y + bbox.max.y) * 0.5,
    };
}

fn translatePaint(paint: Paint, delta: Vec2) Paint {
    return switch (paint) {
        .solid => paint,
        .linear_gradient => |gradient| .{ .linear_gradient = .{
            .start = Vec2.add(gradient.start, delta),
            .end = Vec2.add(gradient.end, delta),
            .start_color = gradient.start_color,
            .end_color = gradient.end_color,
            .extend = gradient.extend,
        } },
        .radial_gradient => |gradient| .{ .radial_gradient = .{
            .center = Vec2.add(gradient.center, delta),
            .radius = gradient.radius,
            .inner_color = gradient.inner_color,
            .outer_color = gradient.outer_color,
            .extend = gradient.extend,
        } },
        .image => |image_paint| .{ .image = .{
            .image = image_paint.image,
            .uv_transform = .{
                .xx = image_paint.uv_transform.xx,
                .xy = image_paint.uv_transform.xy,
                .tx = image_paint.uv_transform.tx - image_paint.uv_transform.xx * delta.x - image_paint.uv_transform.xy * delta.y,
                .yx = image_paint.uv_transform.yx,
                .yy = image_paint.uv_transform.yy,
                .ty = image_paint.uv_transform.ty - image_paint.uv_transform.yx * delta.x - image_paint.uv_transform.yy * delta.y,
            },
            .tint = image_paint.tint,
            .extend_x = image_paint.extend_x,
            .extend_y = image_paint.extend_y,
            .filter = image_paint.filter,
        } },
    };
}

fn fillStyleForStroke(style: StrokeStyle) FillStyle {
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
        .line => .{
            .kind = .line,
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
    path: *Path,
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
    path: *Path,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
) !void {
    if (curve.flatness() <= 1e-6) {
        try path.lineTo(offsetCurvePoint(curve, 1.0, offset));
        return;
    }

    if (depth == 0 or offsetCurveApproxError(curve, offset) <= kPathStrokeOffsetTolerance) {
        path.band_curve_count += 1;
        try path.appendSegment(fitOffsetCurveQuad(curve, offset));
        return;
    }

    const halves = curve.split(0.5);
    try appendOffsetCurveApprox(path, halves[0], offset, depth - 1);
    try appendOffsetCurveApprox(path, halves[1], offset, depth - 1);
}

pub const Path = struct {
    allocator: std.mem.Allocator,
    curves: std.ArrayList(CurveSegment) = .empty,
    contours: std.ArrayList(Contour) = .empty,
    bbox: ?BBox = null,
    band_curve_count: usize = 0,

    const Contour = struct {
        curve_start: usize,
        curve_end: usize,
        start_point: Vec2,
        current_point: Vec2,
        closed: bool,
    };

    pub fn init(allocator: std.mem.Allocator) Path {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Path) void {
        self.curves.deinit(self.allocator);
        self.contours.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *Path) void {
        self.curves.clearRetainingCapacity();
        self.contours.clearRetainingCapacity();
        self.bbox = null;
        self.band_curve_count = 0;
    }

    pub fn bounds(self: *const Path) ?BBox {
        return self.bbox;
    }

    pub fn isEmpty(self: *const Path) bool {
        return self.curves.items.len == 0;
    }

    pub fn moveTo(self: *Path, point: Vec2) !void {
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

    pub fn lineTo(self: *Path, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try self.appendSegment(makePathLineSegment(contour.current_point, point));
    }

    pub fn quadTo(self: *Path, control: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try self.appendSegment(CurveSegment.fromQuad(.{
            .p0 = contour.current_point,
            .p1 = control,
            .p2 = point,
        }));
    }

    pub fn cubicTo(self: *Path, control1: Vec2, control2: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try appendAdaptiveQuadraticApprox(self, CurveSegment.fromCubic(.{
            .p0 = contour.current_point,
            .p1 = control1,
            .p2 = control2,
            .p3 = point,
        }), kPathCurveApproxMaxDepth);
    }

    pub fn close(self: *Path) !void {
        if (self.requireContour()) |initial_contour| {
            var contour = initial_contour;
            if (contour.closed) return;
            if (contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                self.band_curve_count += 1;
                try self.appendSegment(makePathLineSegment(contour.current_point, contour.start_point));
                contour = self.requireContour().?;
            }
            contour.closed = true;
            contour.current_point = contour.start_point;
        }
    }

    pub fn addRect(self: *Path, rect: Rect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.close();
    }

    pub fn addRectReversed(self: *Path, rect: Rect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.close();
    }

    pub fn addRoundedRect(self: *Path, rect: Rect, corner_radius: f32) !void {
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
        try appendAdaptiveArcConic(self, top_right, arc, -std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, size.y - radius)));
        try appendAdaptiveArcConic(self, bottom_right, arc, 0.0, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, size.y)));
        try appendAdaptiveArcConic(self, bottom_left, arc, std.math.pi / 2.0, std.math.pi);
        try self.lineTo(origin.add(Vec2.new(0.0, radius)));
        try appendAdaptiveArcConic(self, top_left, arc, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addRoundedRectReversed(self: *Path, rect: Rect, corner_radius: f32) !void {
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
        try appendAdaptiveArcConic(self, bottom_left, arc, std.math.pi, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(size.x - radius, size.y)));
        try appendAdaptiveArcConic(self, bottom_right, arc, std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, radius)));
        try appendAdaptiveArcConic(self, top_right, arc, 0.0, -std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, 0.0)));
        try appendAdaptiveArcConic(self, top_left, arc, -std.math.pi / 2.0, -std.math.pi);
        try self.close();
    }

    pub fn addEllipse(self: *Path, rect: Rect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi / 2.0, 0.0);
        try appendAdaptiveArcConic(self, center, radii, 0.0, std.math.pi / 2.0);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi / 2.0, std.math.pi);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addEllipseReversed(self: *Path, rect: Rect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi / 2.0, -std.math.pi);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi, -std.math.pi * 1.5);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi * 1.5, -std.math.pi * 2.0);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi * 2.0, -std.math.pi * 2.5);
        try self.close();
    }

    fn requireContour(self: *Path) ?*Contour {
        if (self.contours.items.len == 0) return null;
        return &self.contours.items[self.contours.items.len - 1];
    }

    fn appendSegment(self: *Path, curve: CurveSegment) !void {
        var contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.curves.append(self.allocator, curve);
        contour = self.requireContour().?;
        contour.curve_end = self.curves.items.len;
        contour.current_point = curve.endPoint();
        self.expandCurveBBox(curve);
    }

    fn expandPointBBox(self: *Path, point: Vec2) void {
        if (self.bbox) |bbox| {
            self.bbox = .{
                .min = Vec2.new(@min(bbox.min.x, point.x), @min(bbox.min.y, point.y)),
                .max = Vec2.new(@max(bbox.max.x, point.x), @max(bbox.max.y, point.y)),
            };
        } else {
            self.bbox = .{ .min = point, .max = point };
        }
    }

    fn expandCurveBBox(self: *Path, curve: CurveSegment) void {
        const cb = curve.boundingBox();
        if (self.bbox) |bbox| {
            self.bbox = bbox.merge(cb);
        } else {
            self.bbox = cb;
        }
    }

    fn unclosedContourCount(self: *const Path) usize {
        var count: usize = 0;
        for (self.contours.items) |contour| {
            if (!contour.closed and contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                count += 1;
            }
        }
        return count;
    }

    fn cloneFilledCurves(self: *const Path, allocator: std.mem.Allocator) ![]CurveSegment {
        const close_count = self.unclosedContourCount();
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

    fn filledBandCurveCount(self: *const Path) usize {
        return self.band_curve_count + self.unclosedContourCount();
    }

    fn cloneStrokedCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        stroke: StrokeStyle,
    ) !?struct { curves: []CurveSegment, bbox: BBox, logical_curve_count: usize } {
        if (stroke.width <= 1e-4 or self.contours.items.len == 0) return null;

        var outline = Path.init(allocator);
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
            .logical_curve_count = self.filledBandCurveCount() * 2,
        };
    }
};

fn appendArcSeries(path: *Path, center: Vec2, radius: f32, start_angle: f32, end_angle: f32) !void {
    if (@abs(end_angle - start_angle) <= 1e-6) return;
    try appendAdaptiveArcCurve(path, center, Vec2.new(radius, radius), start_angle, end_angle, kPathArcSplitMaxDepth);
}

fn appendRoundJoin(path: *Path, center: Vec2, prev_normal: Vec2, next_normal: Vec2, half_width: f32) !void {
    const start_angle = std.math.atan2(prev_normal.y, prev_normal.x);
    const delta = signedAngleBetween(prev_normal, next_normal);
    try appendArcSeries(path, center, half_width, start_angle, start_angle + delta);
}

fn appendRoundCap(path: *Path, center: Vec2, dir: Vec2, half_width: f32, start_cap: bool) !void {
    const normal = perpLeft(dir);
    const start_angle = if (start_cap)
        std.math.atan2(-normal.y, -normal.x)
    else
        std.math.atan2(normal.y, normal.x);
    try appendArcSeries(path, center, half_width, start_angle, start_angle - std.math.pi);
}

fn appendStrokeJoinForSide(
    path: *Path,
    center: Vec2,
    prev_dir: Vec2,
    next_dir: Vec2,
    half_width: f32,
    side: f32,
    join: StrokeJoin,
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
    boundary: *Path,
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
    stroke: StrokeStyle,
) !?Path {
    if ((!closed and curves.len == 0) or stroke.width <= 1e-4) return null;

    const half_width = stroke.width * 0.5;
    var boundary = Path.init(allocator);
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

fn appendBoundaryCurves(dst: *Path, src: *const Path, reverse: bool) !void {
    if (!reverse) {
        for (src.curves.items) |curve| {
            dst.band_curve_count += 1;
            try dst.appendSegment(curve);
        }
        return;
    }
    var i = src.curves.items.len;
    while (i > 0) {
        i -= 1;
        dst.band_curve_count += 1;
        try dst.appendSegment(reverseCurveSegment(src.curves.items[i]));
    }
}

fn buildOpenStrokeContour(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle) !void {
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

fn buildClosedStrokeContours(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle) !void {
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

fn pointOnEllipse(center: Vec2, radii: Vec2, angle: f32) Vec2 {
    return center.add(.{
        .x = @cos(angle) * radii.x,
        .y = @sin(angle) * radii.y,
    });
}

fn buildCircularSectorPath(
    path: *Path,
    center: Vec2,
    outer_radius: f32,
    inner_radius: f32,
    start_angle: f32,
    end_angle: f32,
) !void {
    const outer_radii = Vec2.new(outer_radius, outer_radius);
    const outer_start = pointOnEllipse(center, outer_radii, start_angle);
    try path.moveTo(outer_start);
    try appendAdaptiveArcCurve(path, center, outer_radii, start_angle, end_angle, kPathArcSplitMaxDepth);
    if (inner_radius <= 1.0 / 65536.0) {
        try path.lineTo(center);
    } else {
        const inner_radii = Vec2.new(inner_radius, inner_radius);
        const inner_end = pointOnEllipse(center, inner_radii, end_angle);
        try path.lineTo(inner_end);
        try appendAdaptiveArcCurve(path, center, inner_radii, end_angle, start_angle, kPathArcSplitMaxDepth);
    }
    try path.close();
}

const kPaintInfoWidth: u32 = PATH_PAINT_INFO_WIDTH;
const kPaintTexelsPerRecord: u32 = PATH_PAINT_TEXELS_PER_RECORD;
const kPaintTagSolid: f32 = PATH_PAINT_TAG_SOLID;
const kPaintTagLinearGradient: f32 = PATH_PAINT_TAG_LINEAR_GRADIENT;
const kPaintTagRadialGradient: f32 = PATH_PAINT_TAG_RADIAL_GRADIENT;
const kPaintTagImage: f32 = PATH_PAINT_TAG_IMAGE;
const kPaintTagCompositeGroup: f32 = PATH_PAINT_TAG_COMPOSITE_GROUP;

const PathCompositeMode = enum(u8) {
    source_over = 0,
    fill_stroke_inside = 1,
};

fn pathLayerInfoTexelOffset(texel_width: u32, info_x: u16, info_y: u16) u32 {
    return @as(u32, info_y) * texel_width + @as(u32, info_x);
}

fn readPathLayerInfoTexel(data: []const f32, texel_width: u32, texel_offset: u32) [4]f32 {
    const texel_x = texel_offset % texel_width;
    const texel_y = texel_offset / texel_width;
    const base = (texel_y * texel_width + texel_x) * 4;
    return .{
        data[base + 0],
        data[base + 1],
        data[base + 2],
        data[base + 3],
    };
}

fn writePathLayerInfoTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
    const texel_x = texel_offset % texel_width;
    const texel_y = texel_offset / texel_width;
    const base = (texel_y * texel_width + texel_x) * 4;
    data[base + 0] = value[0];
    data[base + 1] = value[1];
    data[base + 2] = value[2];
    data[base + 3] = value[3];
}

fn paletteColor(index: usize) [4]f32 {
    const palette = [_][4]f32{
        .{ 0.27, 0.86, 0.98, 0.96 },
        .{ 0.98, 0.54, 0.29, 0.96 },
        .{ 0.58, 0.94, 0.43, 0.96 },
        .{ 0.95, 0.39, 0.77, 0.96 },
        .{ 0.99, 0.86, 0.28, 0.96 },
        .{ 0.56, 0.66, 0.98, 0.96 },
    };
    return palette[index % palette.len];
}

fn blendColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    };
}

fn debugPaintColor(view: PathPictureDebugView, role: PathPicture.LayerRole, instance_index: usize) [4]f32 {
    const base = paletteColor(instance_index);
    return switch (view) {
        .normal => .{ 0, 0, 0, 0 },
        .fill_mask => switch (role) {
            .fill => base,
            .stroke => .{ 0.0, 0.0, 0.0, 0.0 },
        },
        .stroke_mask => switch (role) {
            .fill => .{ 0.0, 0.0, 0.0, 0.0 },
            .stroke => base,
        },
        .layer_tint => switch (role) {
            .fill => blendColor(base, .{ 0.15, 0.90, 0.98, 0.96 }, 0.45),
            .stroke => blendColor(base, .{ 0.98, 0.24, 0.82, 0.96 }, 0.55),
        },
    };
}

pub const PathPicture = struct {
    allocator: std.mem.Allocator,
    atlas: Atlas,
    instances: []Instance,
    layer_roles: []LayerRole,

    pub const LayerRole = enum(u8) {
        fill,
        stroke,
    };

    pub const Instance = struct {
        glyph_id: u16,
        bbox: BBox,
        page_index: u16,
        info_x: u16,
        info_y: u16,
        layer_count: u16 = 1,
        transform: Transform2D,
    };

    pub fn deinit(self: *PathPicture) void {
        self.atlas.deinit();
        self.allocator.free(self.instances);
        self.allocator.free(self.layer_roles);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPicture) usize {
        return self.instances.len;
    }

    fn applyDebugViewInPlace(self: *PathPicture, view: PathPictureDebugView) void {
        if (view == .normal) return;
        const data = self.atlas.layer_info_data orelse return;
        const width = self.atlas.layer_info_width;

        for (self.instances, 0..) |instance, instance_index| {
            const info_offset = pathLayerInfoTexelOffset(width, instance.info_x, instance.info_y);
            var header = readPathLayerInfoTexel(data, width, info_offset);
            var layer_count: usize = 1;
            var record_base = info_offset;

            if (@abs(header[3] - PATH_PAINT_TAG_COMPOSITE_GROUP) <= 0.001) {
                layer_count = @intCast(@as(i32, @intFromFloat(@round(header[0]))));
                header[1] = @floatFromInt(@intFromEnum(PathCompositeMode.source_over));
                writePathLayerInfoTexel(data, width, info_offset, header);
                record_base += 1;
            }

            for (0..layer_count) |layer_index| {
                const role_index = @as(usize, instance.glyph_id - 1) + layer_index;
                if (role_index >= self.layer_roles.len) break;
                const texel_offset = record_base + @as(u32, @intCast(layer_index)) * PATH_PAINT_TEXELS_PER_RECORD;
                var info = readPathLayerInfoTexel(data, width, texel_offset);
                info[3] = PATH_PAINT_TAG_SOLID;
                writePathLayerInfoTexel(data, width, texel_offset, info);
                writePathLayerInfoTexel(data, width, texel_offset + 2, debugPaintColor(view, self.layer_roles[role_index], instance_index));
            }
        }
    }

    pub fn withDebugView(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        view: PathPictureDebugView,
    ) !PathPicture {
        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.atlas.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        const pages = try allocator.alloc(*AtlasPage, self.atlas.pages.len);
        errdefer allocator.free(pages);
        for (self.atlas.pages, 0..) |page, i| pages[i] = page.retain();

        var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
        errdefer atlas.deinit();

        if (self.atlas.layer_info_data) |data| {
            atlas.layer_info_data = try allocator.dupe(f32, data);
            atlas.layer_info_width = self.atlas.layer_info_width;
            atlas.layer_info_height = self.atlas.layer_info_height;
        }
        if (self.atlas.paint_image_records) |records| {
            atlas.paint_image_records = try allocator.dupe(?Atlas.PaintImageRecord, records);
        }

        const instances = try allocator.dupe(Instance, self.instances);
        errdefer allocator.free(instances);
        const layer_roles = try allocator.dupe(LayerRole, self.layer_roles);
        errdefer allocator.free(layer_roles);

        var result = PathPicture{
            .allocator = allocator,
            .atlas = atlas,
            .instances = instances,
            .layer_roles = layer_roles,
        };
        result.applyDebugViewInPlace(view);
        return result;
    }

    pub fn buildBoundsOverlay(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        options: PathPictureBoundsOverlayOptions,
    ) !PathPicture {
        if (self.instances.len == 0) return error.EmptyPicture;

        var builder = PathPictureBuilder.init(allocator);
        defer builder.deinit();

        const cross_thickness = @max(options.stroke_width, 1.0);
        for (self.instances) |instance| {
            const rect = Rect{
                .x = instance.bbox.min.x,
                .y = instance.bbox.min.y,
                .w = instance.bbox.max.x - instance.bbox.min.x,
                .h = instance.bbox.max.y - instance.bbox.min.y,
            };
            try builder.addStrokedRect(
                rect,
                .{ .color = options.stroke_color, .width = options.stroke_width, .join = .miter },
                instance.transform,
            );
            if (options.origin_size > 1e-4 and options.origin_color[3] > 1e-4) {
                try builder.addFilledRect(.{
                    .x = -options.origin_size,
                    .y = -cross_thickness * 0.5,
                    .w = options.origin_size * 2.0,
                    .h = cross_thickness,
                }, .{ .color = options.origin_color }, instance.transform);
                try builder.addFilledRect(.{
                    .x = -cross_thickness * 0.5,
                    .y = -options.origin_size,
                    .w = cross_thickness,
                    .h = options.origin_size * 2.0,
                }, .{ .color = options.origin_color }, instance.transform);
            }
        }

        return builder.freeze(allocator);
    }
};

pub const PathPictureBuilder = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList(PathRecord) = .empty,

    const PathLayerRecord = struct {
        curves: []CurveSegment,
        bbox: BBox,
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
    };

    const PathRecord = struct {
        bbox: BBox,
        transform: Transform2D,
        layer_count: u16,
        composite_mode: PathCompositeMode,
        layers: [2]PathLayerRecord,
    };

    fn srgbToLinear(v: f32) f32 {
        if (v <= 0.04045) return v / 12.92;
        return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
    }

    fn srgbToLinearColor(color: [4]f32) [4]f32 {
        return .{ srgbToLinear(color[0]), srgbToLinear(color[1]), srgbToLinear(color[2]), color[3] };
    }

    fn setLayerInfoTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
        const texel_x = texel_offset % texel_width;
        const texel_y = texel_offset / texel_width;
        const base = (texel_y * texel_width + texel_x) * 4;
        data[base + 0] = value[0];
        data[base + 1] = value[1];
        data[base + 2] = value[2];
        data[base + 3] = value[3];
    }

    fn pathPaintTag(paint: Paint) f32 {
        return switch (paint) {
            .solid => kPaintTagSolid,
            .linear_gradient => kPaintTagLinearGradient,
            .radial_gradient => kPaintTagRadialGradient,
            .image => kPaintTagImage,
        };
    }

    fn writePaintRecord(
        data: []f32,
        texel_offset: u32,
        band_entry: band_tex.GlyphBandEntry,
        paint: Paint,
    ) void {
        const packed_bands: u32 = @as(u32, band_entry.h_band_count - 1) | (@as(u32, band_entry.v_band_count - 1) << 16);
        setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 0, .{
            @floatFromInt(band_entry.glyph_x),
            @floatFromInt(band_entry.glyph_y),
            @bitCast(packed_bands),
            pathPaintTag(paint),
        });
        setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 1, .{
            band_entry.band_scale_x,
            band_entry.band_scale_y,
            band_entry.band_offset_x,
            band_entry.band_offset_y,
        });

        switch (paint) {
            .solid => |color| {
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 2, color);
            },
            .linear_gradient => |gradient| {
                // Colors stored in linear space; the shader does sRGB
                // round-trip (linear→sRGB→mix→sRGB→linear) for interpolation.
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 2, .{
                    gradient.start.x,
                    gradient.start.y,
                    gradient.end.x,
                    gradient.end.y,
                });
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 3, srgbToLinearColor(gradient.start_color));
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 4, srgbToLinearColor(gradient.end_color));
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 5, .{
                    @floatFromInt(@intFromEnum(gradient.extend)),
                    0,
                    0,
                    0,
                });
            },
            .radial_gradient => |gradient| {
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 2, .{
                    gradient.center.x,
                    gradient.center.y,
                    gradient.radius,
                    @floatFromInt(@intFromEnum(gradient.extend)),
                });
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 3, srgbToLinearColor(gradient.inner_color));
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 4, srgbToLinearColor(gradient.outer_color));
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 5, .{
                    0,
                    0,
                    0,
                    0,
                });
            },
            .image => |image| {
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 2, .{
                    image.uv_transform.xx,
                    image.uv_transform.xy,
                    image.uv_transform.tx,
                    0,
                });
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 3, .{
                    image.uv_transform.yx,
                    image.uv_transform.yy,
                    image.uv_transform.ty,
                    @floatFromInt(@intFromEnum(image.filter)),
                });
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 4, srgbToLinearColor(image.tint));
                setLayerInfoTexel(data, kPaintInfoWidth, texel_offset + 5, .{
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
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
        transform: Transform2D,
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
                    .logical_curve_count = logical_curve_count,
                    .paint = paint,
                    .role = role,
                },
                undefined,
            },
        });
    }

    fn shouldTileRoundedRect(size: Vec2) bool {
        return @max(size.x, size.y) > kPathLargePrimitiveTileExtent;
    }

    fn addFilledRectTiles(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        const width = @max(rect.w, 0.0);
        const height = @max(rect.h, 0.0);
        if (width <= 1e-4 or height <= 1e-4) return;

        var y = rect.y;
        var remaining_h = height;
        while (remaining_h > 1e-4) {
            const tile_h = @min(remaining_h, kPathLargePrimitiveTileExtent);
            var x = rect.x;
            var remaining_w = width;
            while (remaining_w > 1e-4) {
                const tile_w = @min(remaining_w, kPathLargePrimitiveTileExtent);
                try self.addFilledRect(.{
                    .x = x,
                    .y = y,
                    .w = tile_w,
                    .h = tile_h,
                }, fill, transform);
                x += tile_w;
                remaining_w -= tile_w;
            }
            y += tile_h;
            remaining_h -= tile_h;
        }
    }

    fn addFilledCircularSector(
        self: *PathPictureBuilder,
        center: Vec2,
        outer_radius: f32,
        inner_radius: f32,
        start_angle: f32,
        end_angle: f32,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        if (outer_radius <= 1e-4) return;
        var path = Path.init(self.allocator);
        defer path.deinit();
        try buildCircularSectorPath(&path, center, outer_radius, inner_radius, start_angle, end_angle);
        try self.addFilledPath(&path, fill, transform);
    }

    fn addSimpleFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, null, transform);
    }

    fn addLargeFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addFilledRect(rect, fill, transform);

        const inner_w = size.x - radius * 2.0;
        const inner_h = size.y - radius * 2.0;

        if (inner_w > 1e-4 and inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + radius,
                .w = inner_w,
                .h = inner_h,
            }, fill, transform);
        }
        if (inner_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - radius,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
        }
        if (inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - radius,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
        }

        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                0.0,
                corner.start_angle,
                corner.end_angle,
                fill,
                transform,
            );
        }
    }

    fn addLargeInsideStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const inset = std.math.clamp(stroke.width, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) {
            if (fill) |style| {
                const inner_w = @max(size.x - inset * 2.0, 0.0);
                const inner_h = @max(size.y - inset * 2.0, 0.0);
                if (inner_w > 1e-4 and inner_h > 1e-4) {
                    try self.addFilledRectTiles(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = inner_w,
                        .h = inner_h,
                    }, style, transform);
                }
            }
            const stroke_fill = fillStyleForStroke(stroke);
            if (inset > 1e-4) {
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y, .w = size.x, .h = inset }, stroke_fill, transform);
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + size.y - inset, .w = size.x, .h = inset }, stroke_fill, transform);
                const middle_h = size.y - inset * 2.0;
                if (middle_h > 1e-4) {
                    try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                    try self.addFilledRectTiles(.{ .x = rect.x + size.x - inset, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                }
            }
            return;
        }

        if (fill) |style| {
            const inner_rect = Rect{
                .x = rect.x + inset,
                .y = rect.y + inset,
                .w = size.x - inset * 2.0,
                .h = size.y - inset * 2.0,
            };
            if (inner_rect.w > 1e-4 and inner_rect.h > 1e-4) {
                const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                if (shouldTileRoundedRect(Vec2.new(inner_rect.w, inner_rect.h))) {
                    try self.addLargeFilledRoundedRect(inner_rect, style, inner_radius, transform);
                } else {
                    try self.addSimpleFilledRoundedRect(inner_rect, style, inner_radius, transform);
                }
            }
        }

        if (inset <= 1e-4) return;

        const stroke_fill = fillStyleForStroke(stroke);
        const straight_w = size.x - radius * 2.0;
        const straight_h = size.y - radius * 2.0;
        if (straight_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - inset,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
        }
        if (straight_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - inset,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
        }

        const inner_radius = @max(radius - inset, 0.0);
        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                inner_radius,
                corner.start_angle,
                corner.end_angle,
                stroke_fill,
                transform,
            );
        }
    }

    fn addLargeCenterStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const half_width = @max(stroke.width * 0.5, 0.0);

        if (fill) |style| {
            try self.addLargeFilledRoundedRect(rect, style, radius, transform);
        }

        if (stroke.width <= 1e-4) return;

        var stroke_only = stroke;
        stroke_only.placement = .inside;
        const expanded = Rect{
            .x = rect.x - half_width,
            .y = rect.y - half_width,
            .w = size.x + stroke.width,
            .h = size.y + stroke.width,
        };
        try self.addLargeInsideStrokeRoundedRect(
            expanded,
            null,
            stroke_only,
            radius + half_width,
            transform,
        );
    }

    fn addExplicitInsideStrokeRecord(
        self: *PathPictureBuilder,
        fill_path: *const Path,
        fill: ?FillStyle,
        stroke_path: *const Path,
        stroke_paint: Paint,
        transform: Transform2D,
    ) !void {
        const stroke_bbox = stroke_path.bounds() orelse return error.EmptyPath;
        const stroke_curves = try stroke_path.cloneFilledCurves(self.allocator);
        errdefer self.allocator.free(stroke_curves);
        const stroke_logical_curve_count = stroke_path.filledBandCurveCount();

        if (fill) |style| {
            const fill_bbox = fill_path.bounds() orelse return error.EmptyPath;
            const fill_curves = try fill_path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(fill_curves);
            const fill_logical_curve_count = fill_path.filledBandCurveCount();
            try self.addCompositeRecord(
                fill_curves,
                fill_bbox,
                fill_logical_curve_count,
                resolveFillPaint(style),
                stroke_curves,
                stroke_bbox,
                stroke_logical_curve_count,
                stroke_paint,
                transform,
                .fill_stroke_inside,
            );
            return;
        }

        try self.addSingleRecord(stroke_curves, stroke_bbox, stroke_logical_curve_count, stroke_paint, .stroke, transform);
    }

    fn addCompositeRecord(
        self: *PathPictureBuilder,
        fill_curves: []CurveSegment,
        fill_bbox: BBox,
        fill_logical_curve_count: usize,
        fill_paint: Paint,
        stroke_curves: []CurveSegment,
        stroke_bbox: BBox,
        stroke_logical_curve_count: usize,
        stroke_paint: Paint,
        transform: Transform2D,
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
                    .logical_curve_count = fill_logical_curve_count,
                    .paint = fill_paint,
                    .role = .fill,
                },
                .{
                    .curves = stroke_curves,
                    .bbox = stroke_bbox,
                    .logical_curve_count = stroke_logical_curve_count,
                    .paint = stroke_paint,
                    .role = .stroke,
                },
            },
        });
    }

    pub fn addPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (fill == null and stroke == null) return error.EmptyStyle;
        if (path.isEmpty()) return error.EmptyPath;

        if (fill) |style| {
            const bbox = path.bounds() orelse return error.EmptyPath;
            const curves = try path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(curves);
            const logical_curve_count = path.filledBandCurveCount();
            if (stroke) |stroke_style| {
                var stroke_geom_style = stroke_style;
                if (stroke_style.placement == .inside) stroke_geom_style.width *= 2.0;
                if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                    errdefer self.allocator.free(stroke_geom.curves);
                    const composite_mode: PathCompositeMode = if (stroke_style.placement == .inside)
                        .fill_stroke_inside
                    else
                        .source_over;
                    try self.addCompositeRecord(
                        curves,
                        bbox,
                        logical_curve_count,
                        resolveFillPaint(style),
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        resolveStrokePaint(stroke_style),
                        transform,
                        composite_mode,
                    );
                    return;
                }
            }
            try self.addSingleRecord(curves, bbox, logical_curve_count, resolveFillPaint(style), .fill, transform);
        }
        if (stroke) |style| {
            var stroke_geom_style = style;
            if (style.placement == .inside) stroke_geom_style.width *= 2.0;
            if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                errdefer self.allocator.free(stroke_geom.curves);
                if (style.placement == .inside) {
                    const fill_bbox = path.bounds() orelse return error.EmptyPath;
                    const fill_curves = try path.cloneFilledCurves(self.allocator);
                    errdefer self.allocator.free(fill_curves);
                    try self.addCompositeRecord(
                        fill_curves,
                        fill_bbox,
                        path.filledBandCurveCount(),
                        .{ .solid = .{ 0, 0, 0, 0 } },
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        resolveStrokePaint(style),
                        transform,
                        .fill_stroke_inside,
                    );
                    return;
                }
                try self.addSingleRecord(
                    stroke_geom.curves,
                    stroke_geom.bbox,
                    stroke_geom.logical_curve_count,
                    resolveStrokePaint(style),
                    .stroke,
                    transform,
                );
            }
        }
    }

    pub fn addFilledPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, fill, null, transform);
    }

    pub fn addStrokedPath(
        self: *PathPictureBuilder,
        path: *const Path,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, null, stroke, transform);
    }

    pub fn addRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRect(rect);

                var stroke_path = Path.init(self.allocator);
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

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));

        if (stroke) |stroke_style| {
            const max_radius = @min(size.x, size.y) * 0.5;
            const radius = std.math.clamp(corner_radius, 0.0, max_radius);
            const inset = std.math.clamp(stroke_style.width, 0.0, max_radius);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRoundedRect(rect, radius);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRoundedRect(rect, radius);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    const inner_rect = Rect{
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

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addEllipse(rect);

                var stroke_path = Path.init(self.allocator);
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

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, fill, null, transform);
    }

    pub fn addFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, fill, null, corner_radius, transform);
    }

    pub fn addFilledEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addEllipse(rect, fill, null, transform);
    }

    pub fn addStrokedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, null, stroke, transform);
    }

    pub fn addStrokedRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, null, stroke, corner_radius, transform);
    }

    pub fn addStrokedEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
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
                kPaintTexelsPerRecord
            else
                1 + @as(u32, path.layer_count) * kPaintTexelsPerRecord;
        }

        const glyph_curves = try allocator.alloc(curve_tex.GlyphCurves, total_layer_count);
        defer allocator.free(glyph_curves);
        const packed_curve_slices = try allocator.alloc([]CurveSegment, total_layer_count);
        defer allocator.free(packed_curve_slices);
        var glyph_cursor: usize = 0;
        defer {
            for (packed_curve_slices[0..glyph_cursor]) |curves| allocator.free(curves);
        }
        for (self.paths.items) |path| {
            const origin = bboxCenter(path.bbox);
            for (path.layers[0..path.layer_count]) |layer| {
                const stored_curves = try allocator.dupe(CurveSegment, layer.curves);
                packed_curve_slices[glyph_cursor] = stored_curves;
                glyph_curves[glyph_cursor] = .{
                    .curves = stored_curves,
                    .bbox = layer.bbox,
                    .origin = origin,
                    .logical_curve_count = layer.logical_curve_count,
                    .prefer_direct_encoding = true,
                };
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
            var bd = try band_tex.buildGlyphBandData(allocator, gc.curves, gc.logical_curve_count, gc.bbox, ct.entries[i], gc.origin, gc.prefer_direct_encoding);
            try glyph_band_data.append(allocator, bd);
            _ = &bd;
        }

        var bt = try band_tex.buildBandTexture(allocator, glyph_band_data.items);
        errdefer bt.texture.deinit();
        errdefer allocator.free(bt.entries);

        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();

        const paint_height = @max(1, (total_paint_texels + kPaintInfoWidth - 1) / kPaintInfoWidth);
        const layer_info_data = try allocator.alloc(f32, kPaintInfoWidth * paint_height * 4);
        errdefer allocator.free(layer_info_data);
        @memset(layer_info_data, 0);

        const instances = try allocator.alloc(PathPicture.Instance, self.paths.items.len);
        errdefer allocator.free(instances);

        const layer_roles = try allocator.alloc(PathPicture.LayerRole, total_layer_count);
        errdefer allocator.free(layer_roles);

        const paint_image_records = try allocator.alloc(?Atlas.PaintImageRecord, total_layer_count);
        errdefer allocator.free(paint_image_records);
        @memset(paint_image_records, null);

        var has_image_paints = false;

        glyph_cursor = 0;
        var texel_cursor: u32 = 0;
        for (self.paths.items, 0..) |path, path_index| {
            const info_texel_offset = texel_cursor;
            if (path.layer_count > 1) {
                setLayerInfoTexel(layer_info_data, kPaintInfoWidth, texel_cursor, .{
                    @floatFromInt(path.layer_count),
                    @floatFromInt(@intFromEnum(path.composite_mode)),
                    0,
                    kPaintTagCompositeGroup,
                });
                texel_cursor += 1;
            }

            var first_glyph_id: u16 = 0;
            const origin = bboxCenter(path.bbox);
            const delta = Vec2.new(-origin.x, -origin.y);
            for (path.layers[0..path.layer_count], 0..) |layer, layer_index| {
                const glyph_id: u16 = @intCast(glyph_cursor + 1);
                if (layer_index == 0) first_glyph_id = glyph_id;
                const local_bbox = translateBBox(layer.bbox, delta);
                const local_paint = translatePaint(layer.paint, delta);
                try glyph_map.put(glyph_id, .{
                    .bbox = local_bbox,
                    .advance_width = 0,
                    .band_entry = bt.entries[glyph_cursor],
                    .page_index = 0,
                });
                layer_roles[glyph_cursor] = layer.role;
                writePaintRecord(layer_info_data, texel_cursor, bt.entries[glyph_cursor], local_paint);
                switch (local_paint) {
                    .image => |image_paint| {
                        paint_image_records[glyph_cursor] = .{
                            .image = image_paint.image,
                            .texel_offset = texel_cursor,
                        };
                        has_image_paints = true;
                    },
                    else => {},
                }
                texel_cursor += kPaintTexelsPerRecord;
                glyph_cursor += 1;
            }

            instances[path_index] = .{
                .glyph_id = first_glyph_id,
                .bbox = translateBBox(path.bbox, delta),
                .page_index = 0,
                .info_x = @intCast(info_texel_offset % kPaintInfoWidth),
                .info_y = @intCast(info_texel_offset / kPaintInfoWidth),
                .layer_count = path.layer_count,
                .transform = Transform2D.multiply(path.transform, Transform2D.translate(origin.x, origin.y)),
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
        atlas.layer_info_width = kPaintInfoWidth;
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
            .layer_roles = layer_roles,
        };
    }
};

pub const PathBatch = struct {
    buf: []u32,
    len: usize = 0,
    layer_window_base: ?u32 = null,

    pub fn init(buf: []u32) PathBatch {
        return .{ .buf = buf };
    }

    pub fn reset(self: *PathBatch) void {
        self.len = 0;
        self.layer_window_base = null;
    }

    pub fn shapeCount(self: *const PathBatch) usize {
        return self.len / PATH_WORDS_PER_SHAPE;
    }

    pub fn slice(self: *const PathBatch) []const u32 {
        return self.buf[0..self.len];
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_instance: usize,
        completed: bool,
        layer_window_base: u32,
    };

    pub fn currentLayerWindowBase(self: *const PathBatch) u32 {
        return self.layer_window_base orelse 0;
    }

    fn localLayer(self: *PathBatch, atlas_layer: u32) !u8 {
        const base = textureLayerWindowBase(atlas_layer);
        if (self.layer_window_base) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base = base;
        }
        return textureLayerLocal(atlas_layer);
    }

    pub fn addPicture(self: *PathBatch, atlas_like: anytype, picture: *const PathPicture) !usize {
        return self.addPictureTransformed(atlas_like, picture, .identity);
    }

    pub fn addPictureTransformed(
        self: *PathBatch,
        atlas_like: anytype,
        picture: *const PathPicture,
        transform: Transform2D,
    ) !usize {
        const result = try self.addPictureTransformedFrom(atlas_like, picture, transform, 0);
        if (!result.completed) return error.DrawListFull;
        return result.emitted;
    }

    pub fn addPictureTransformedFrom(
        self: *PathBatch,
        atlas_like: anytype,
        picture: *const PathPicture,
        transform: Transform2D,
        start_instance: usize,
    ) !AppendResult {
        const resolved_view = coerceAtlasHandle(atlas_like);
        const view = &resolved_view;
        var count: usize = 0;
        var instance_index = start_instance;
        while (instance_index < picture.instances.len) : (instance_index += 1) {
            const instance = picture.instances[instance_index];
            const layer_base = view.glyphLayerWindowBase(instance.page_index);
            if (self.layer_window_base) |base| {
                if (base != layer_base) break;
            } else {
                self.layer_window_base = layer_base;
            }
            if (self.len + PATH_WORDS_PER_SHAPE > self.buf.len) return error.DrawListFull;
            const final_transform = Transform2D.multiply(transform, instance.transform);
            const info_loc = view.layerInfoLoc(instance.info_x, instance.info_y);
            const local_layer = try self.localLayer(view.glyphLayer(instance.page_index));
            if (!vertex_mod.generateMultiLayerGlyphVerticesTransformed(
                self.buf[self.len..],
                instance.bbox,
                info_loc.x,
                info_loc.y,
                instance.layer_count,
                .{ 1, 1, 1, 1 },
                local_layer,
                final_transform,
            )) return error.InvalidTransform;
            self.len += PATH_WORDS_PER_SHAPE;
            count += 1;
        }
        return .{
            .emitted = count,
            .next_instance = instance_index,
            .completed = instance_index >= picture.instances.len,
            .layer_window_base = self.currentLayerWindowBase(),
        };
    }
};

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};
pub const SubpixelOrder = @import("render/subpixel_order.zig").SubpixelOrder;
pub const VulkanContext = vulkan_pipeline.VulkanContext;
pub const CpuRenderer = cpu_renderer_mod.CpuRenderer;

pub const ResolveTarget = struct {
    pixel_width: f32,
    pixel_height: f32,
    subpixel_order: SubpixelOrder = .none,
    fill_rule: FillRule = .non_zero,
    is_final_composite: bool = true,
    opaque_backdrop: bool = true,
    will_resample: bool = false,
};

pub const TextHinting = enum(u8) {
    none,
    phase,
    metrics,
};

/// Final-resolve text fitting.
///
/// This is intentionally a resolve-time control, not an atlas/layout control:
/// fitting should happen against the final target pixel grid. Callers that
/// animate, scroll, or otherwise preserve fractional motion should usually
/// leave this at `.none` while in motion and opt in deliberately for static
/// final text.
pub const TextResolveOptions = struct {
    hinting: TextHinting = .none,
};

fn sceneToScreenTransform(mvp: Mat4, viewport_w: f32, viewport_h: f32) ?Transform2D {
    if (@abs(mvp.data[3]) > 1e-5 or @abs(mvp.data[7]) > 1e-5 or @abs(mvp.data[11]) > 1e-5) return null;
    if (@abs(mvp.data[15] - 1.0) > 1e-5) return null;

    return .{
        .xx = mvp.data[0] * viewport_w * 0.5,
        .xy = mvp.data[4] * viewport_w * 0.5,
        .tx = (mvp.data[12] * 0.5 + 0.5) * viewport_w,
        .yx = mvp.data[1] * viewport_h * 0.5,
        .yy = mvp.data[5] * viewport_h * 0.5,
        .ty = (mvp.data[13] * 0.5 + 0.5) * viewport_h,
    };
}

fn effectiveSubpixelOrder(target: ResolveTarget) SubpixelOrder {
    if (!target.is_final_composite) return .none;
    if (!target.opaque_backdrop) return .none;
    if (target.will_resample) return .none;
    return target.subpixel_order;
}

pub const Scene = struct {
    allocator: std.mem.Allocator,
    /// Borrowed command list. Text commands borrow TextBlob; path commands
    /// borrow PathPicture. The referenced values must outlive the Scene.
    commands: std.ArrayListUnmanaged(Command) = .empty,

    pub const Command = union(enum) {
        text: TextCommand,
        path: PathCommand,
    };

    pub const TextCommand = struct {
        blob: *const TextBlob,
        transform: Transform2D = .identity,
        resolve: TextResolveOptions = .{},
    };

    pub const PathCommand = struct {
        picture: *const PathPicture,
        transform: Transform2D = .identity,
    };

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Scene) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *Scene) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn commandCount(self: *const Scene) usize {
        return self.commands.items.len;
    }

    pub fn addText(self: *Scene, blob: *const TextBlob) !void {
        try self.addTextTransformedOptions(blob, .identity, .{});
    }

    pub fn addTextOptions(self: *Scene, blob: *const TextBlob, resolve: TextResolveOptions) !void {
        try self.addTextTransformedOptions(blob, .identity, resolve);
    }

    pub fn addTextTransformed(self: *Scene, blob: *const TextBlob, transform: Transform2D) !void {
        try self.addTextTransformedOptions(blob, transform, .{});
    }

    pub fn addTextTransformedOptions(
        self: *Scene,
        blob: *const TextBlob,
        transform: Transform2D,
        resolve: TextResolveOptions,
    ) !void {
        try self.commands.append(self.allocator, .{ .text = .{
            .blob = blob,
            .transform = transform,
            .resolve = resolve,
        } });
    }

    pub fn addPathPicture(self: *Scene, picture: *const PathPicture) !void {
        try self.addPathPictureTransformed(picture, .identity);
    }

    pub fn addPathPictureTransformed(self: *Scene, picture: *const PathPicture, transform: Transform2D) !void {
        try self.commands.append(self.allocator, .{ .path = .{
            .picture = picture,
            .transform = transform,
        } });
    }
};

pub const ResourceStamp = struct {
    identity: u64 = 0,
    layout: u64 = 0,
    content: u64 = 0,

    pub fn eql(a: ResourceStamp, b: ResourceStamp) bool {
        return a.identity == b.identity and a.layout == b.layout and a.content == b.content;
    }
};

pub const TargetStamp = struct {
    pixel_size: [2]u32 = .{ 0, 0 },
    subpixel_order: SubpixelOrder = .none,
    hinting: TextHinting = .none,
    mvp_class: MvpClass = .projective,
    hint_transform_hash: u64 = 0,

    pub const MvpClass = enum(u8) {
        identity,
        axis_aligned_2d,
        affine_2d,
        projective,
    };

    pub fn from(mvp: Mat4, target: ResolveTarget, hinting: TextHinting) TargetStamp {
        return .{
            .pixel_size = .{
                @intFromFloat(@max(target.pixel_width, 0.0)),
                @intFromFloat(@max(target.pixel_height, 0.0)),
            },
            .subpixel_order = effectiveSubpixelOrder(target),
            .hinting = hinting,
            .mvp_class = classifyMvp(mvp),
            .hint_transform_hash = if (hinting == .none) 0 else hashHintTransform(mvp, target),
        };
    }

    fn hashHintTransform(mvp: Mat4, target: ResolveTarget) u64 {
        var h = std.hash.Wyhash.hash(0x534e41494c48544d, std.mem.asBytes(&mvp.data));
        h = mix64(h, @as(u32, @bitCast(target.pixel_width)));
        h = mix64(h, @as(u32, @bitCast(target.pixel_height)));
        return h;
    }

    fn classifyMvp(mvp: Mat4) MvpClass {
        if (std.meta.eql(mvp, Mat4.identity)) return .identity;
        if (@abs(mvp.data[3]) > 1e-5 or @abs(mvp.data[7]) > 1e-5 or @abs(mvp.data[11]) > 1e-5) return .projective;
        if (@abs(mvp.data[15] - 1.0) > 1e-5) return .projective;
        if (@abs(mvp.data[1]) <= 1e-5 and @abs(mvp.data[4]) <= 1e-5) return .axis_aligned_2d;
        return .affine_2d;
    }
};

pub const ResourceKey = struct {
    id: u64,
    name: []const u8 = "",

    pub fn named(comptime name: []const u8) ResourceKey {
        return .{ .id = hashBytes(name), .name = name };
    }

    pub fn fromName(name: []const u8) ResourceKey {
        return .{ .id = hashBytes(name), .name = name };
    }

    pub fn fromId(id: u64) ResourceKey {
        return .{ .id = id };
    }

    pub fn eql(a: ResourceKey, b: ResourceKey) bool {
        return a.id == b.id;
    }
};

fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0x534e41494c5f4b45, bytes);
}

fn mix64(h: u64, v: u64) u64 {
    return h ^ (v +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2));
}

fn resourceKey(key_value: anytype) ResourceKey {
    const T = @TypeOf(key_value);
    if (T == ResourceKey) return key_value;
    return switch (@typeInfo(T)) {
        .enum_literal => ResourceKey.fromName(@tagName(key_value)),
        .@"enum" => ResourceKey.fromName(@tagName(key_value)),
        .comptime_int, .int => ResourceKey.fromId(@intCast(key_value)),
        .pointer => |ptr| blk: {
            if (ptr.child == u8) break :blk ResourceKey.fromName(key_value);
            switch (@typeInfo(ptr.child)) {
                .array => |array| {
                    if (array.child == u8) {
                        const slice: []const u8 = key_value;
                        break :blk ResourceKey.fromName(std.mem.trimRight(u8, slice, "\x00"));
                    }
                },
                else => {},
            }
            break :blk ResourceKey.fromId(@intCast(@intFromPtr(key_value)));
        },
        else => @compileError("resource keys must be enum literals, enums, strings, integers, or pointers"),
    };
}

fn pointerResourceKey(comptime prefix: []const u8, ptr: anytype) ResourceKey {
    var h = hashBytes(prefix);
    h = mix64(h, @intCast(@intFromPtr(ptr)));
    return .{ .id = h, .name = prefix };
}

pub const ResourceSet = struct {
    /// Caller-buffered CPU manifest. Entries point at app-owned
    /// TextAtlas, PathPicture, and Image values; no upload happens here.
    entries: []Entry = &.{},
    len: usize = 0,

    pub const Entry = union(enum) {
        text_atlas: TextAtlasEntry,
        path_picture: PathPictureEntry,
        image: ImageEntry,
    };

    pub const TextAtlasEntry = struct {
        key: ResourceKey,
        atlas: *const TextAtlas,
    };

    pub const PathPictureEntry = struct {
        key: ResourceKey,
        picture: *const PathPicture,
    };

    pub const ImageEntry = struct {
        key: ResourceKey,
        image: *const Image,
    };

    pub fn init(entries: []Entry) ResourceSet {
        return .{ .entries = entries };
    }

    pub fn capacity(self: *const ResourceSet) usize {
        return self.entries.len;
    }

    pub fn reset(self: *ResourceSet) void {
        self.len = 0;
    }

    pub fn putTextAtlas(self: *ResourceSet, key_value: anytype, atlas: *const TextAtlas) !void {
        try self.put(.{ .text_atlas = .{ .key = resourceKey(key_value), .atlas = atlas } });
    }

    pub fn putPathPicture(self: *ResourceSet, key_value: anytype, picture: *const PathPicture) !void {
        try self.put(.{ .path_picture = .{ .key = resourceKey(key_value), .picture = picture } });
    }

    pub fn putImage(self: *ResourceSet, key_value: anytype, image: *const Image) !void {
        try self.put(.{ .image = .{ .key = resourceKey(key_value), .image = image } });
    }

    pub fn addScene(self: *ResourceSet, scene: *const Scene) !void {
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| try self.put(.{ .text_atlas = .{
                    .key = pointerResourceKey("scene.text_atlas", text.blob.atlas),
                    .atlas = text.blob.atlas,
                } }),
                .path => |path| try self.put(.{ .path_picture = .{
                    .key = pointerResourceKey("scene.path_picture", path.picture),
                    .picture = path.picture,
                } }),
            }
        }
    }

    fn put(self: *ResourceSet, entry: Entry) !void {
        const key = entryKey(entry);
        for (self.entries[0..self.len], 0..) |existing, i| {
            if (entryKey(existing).eql(key)) {
                self.entries[i] = entry;
                return;
            }
        }
        if (self.len >= self.entries.len) return error.ResourceSetFull;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    fn entryKey(entry: Entry) ResourceKey {
        return switch (entry) {
            .text_atlas => |text| text.key,
            .path_picture => |path| path.key,
            .image => |image| image.key,
        };
    }

    pub fn slice(self: *const ResourceSet) []const Entry {
        return self.entries[0..self.len];
    }
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    /// Backend-specific realization for one renderer/context. Entries may
    /// borrow CPU values; those values must outlive this object unless a
    /// backend explicitly copied them.
    atlases: []PreparedAtlasResource = &.{},
    images: []PreparedImageResource = &.{},
    gl: ?pipeline.PreparedResources = null,
    vulkan: if (build_options.enable_vulkan) ?vulkan_pipeline.PreparedResources else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?cpu_renderer_mod.PreparedResources else void = if (build_options.enable_cpu) null else {},

    const PreparedAtlasKind = enum {
        text,
        path,
    };

    const PreparedAtlasResource = struct {
        key: ResourceKey,
        kind: PreparedAtlasKind,
        text_atlas: ?*const TextAtlas = null,
        picture: ?*const PathPicture = null,
        atlas: *const Atlas,
        wrapper: Atlas = undefined,
        owns_wrapper: bool = false,
        view: PreparedAtlasView = undefined,
        stamp: ResourceStamp,
    };

    const PreparedImageResource = struct {
        key: ResourceKey,
        image: *const Image,
        view: PreparedImageView = undefined,
        stamp: ResourceStamp,
    };

    pub fn deinit(self: *PreparedResources) void {
        if (self.gl) |*gl_resources| gl_resources.deinit();
        if (comptime build_options.enable_vulkan) {
            if (self.vulkan) |*vk_resources| vk_resources.deinit();
        }
        if (comptime build_options.enable_cpu) {
            if (self.cpu) |*cpu_resources| cpu_resources.deinit();
        }
        for (self.atlases) |*entry| {
            if (entry.owns_wrapper) entry.text_atlas.?.deinitUploadAtlas(&entry.wrapper);
        }
        if (self.atlases.len > 0) self.allocator.free(self.atlases);
        if (self.images.len > 0) self.allocator.free(self.images);
        self.* = undefined;
    }

    pub fn retireNowOrWhenSafe(self: *PreparedResources, renderer: *Renderer) void {
        _ = renderer;
        sweepRetiredPreparedResources();
        self.deinit();
    }

    pub fn retireAfter(self: *PreparedResources, allocator: std.mem.Allocator, fence_or_frame: anytype) !void {
        sweepRetiredPreparedResources();
        if (comptime build_options.enable_vulkan) {
            if (self.vulkan != null) {
                const fence = preparedRetirementFence(self, fence_or_frame) orelse return;
                try enqueueRetiredPreparedResources(allocator, self.*, fence);
                self.* = undefined;
                return;
            }
        }
        self.deinit();
    }

    pub fn stampForKey(self: *const PreparedResources, key_value: anytype) ?ResourceStamp {
        const key = resourceKey(key_value);
        for (self.atlases) |entry| if (entry.key.eql(key)) return entry.stamp;
        for (self.images) |entry| if (entry.key.eql(key)) return entry.stamp;
        return null;
    }

    pub fn textCoverageBackend(self: *const PreparedResources, renderer: *Renderer) ?TextCoverageBackend {
        if (renderer.vtable == &Renderer.gl_vtable or renderer.vtable == &Renderer.gl_borrowed_vtable) {
            if (self.gl) |*gl_resources| {
                return .{
                    .gl = @ptrCast(@alignCast(renderer.ptr)),
                    .gl_resources = gl_resources,
                    .prepared = self,
                };
            }
        }
        return null;
    }

    fn textAtlasEntry(self: *const PreparedResources, atlas: *const TextAtlas) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .text and entry.text_atlas == atlas) return entry;
        }
        return null;
    }

    fn pathPictureEntry(self: *const PreparedResources, picture: *const PathPicture) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .path and entry.picture == picture) return entry;
        }
        return null;
    }

    fn textAtlasView(self: *const PreparedResources, atlas: *const TextAtlas) !PreparedTextAtlasView {
        const entry = self.textAtlasEntry(atlas) orelse return error.MissingPreparedResource;
        return .{
            .layer_base = entry.view.layer_base,
            .info_row_base = entry.view.info_row_base,
        };
    }

    fn pathAtlasView(self: *const PreparedResources, picture: *const PathPicture) !PreparedAtlasView {
        const entry = self.pathPictureEntry(picture) orelse return error.MissingPreparedResource;
        return entry.view;
    }

    fn textStamp(self: *const PreparedResources, atlas: *const TextAtlas) !ResourceStamp {
        return (self.textAtlasEntry(atlas) orelse return error.MissingPreparedResource).stamp;
    }

    fn pathStamp(self: *const PreparedResources, picture: *const PathPicture) !ResourceStamp {
        return (self.pathPictureEntry(picture) orelse return error.MissingPreparedResource).stamp;
    }
};

const VulkanRetirementFence = if (build_options.enable_vulkan) struct {
    device: vulkan_pipeline.vk.VkDevice,
    fence: vulkan_pipeline.vk.VkFence,
} else void;

const RetiredPreparedResources = struct {
    allocator: std.mem.Allocator,
    resources: PreparedResources,
    vulkan_fence: if (build_options.enable_vulkan) ?VulkanRetirementFence else void = if (build_options.enable_vulkan) null else {},
    next: ?*RetiredPreparedResources = null,
};

var retired_resources_head: ?*RetiredPreparedResources = null;

// Deferred Vulkan retirements are swept opportunistically on public renderer
// calls. CPU and GL resources retire synchronously through deinit().
fn enqueueRetiredPreparedResources(allocator: std.mem.Allocator, resources: PreparedResources, fence: VulkanRetirementFence) !void {
    const node = try allocator.create(RetiredPreparedResources);
    node.* = .{
        .allocator = allocator,
        .resources = resources,
        .vulkan_fence = if (build_options.enable_vulkan) fence else {},
    };

    node.next = retired_resources_head;
    retired_resources_head = node;
}

fn sweepRetiredPreparedResources() void {
    var link = &retired_resources_head;
    while (link.*) |node| {
        if (retiredPreparedResourcesReady(node)) {
            link.* = node.next;
            var resources = node.resources;
            resources.deinit();
            node.allocator.destroy(node);
        } else {
            link = &node.next;
        }
    }
}

fn retiredPreparedResourcesReady(node: *const RetiredPreparedResources) bool {
    if (comptime build_options.enable_vulkan) {
        if (node.vulkan_fence) |fence| {
            const result = vulkan_pipeline.vk.vkGetFenceStatus(fence.device, fence.fence);
            return result == vulkan_pipeline.vk.VK_SUCCESS or result == vulkan_pipeline.vk.VK_ERROR_DEVICE_LOST;
        }
    }
    return true;
}

fn preparedRetirementFence(resources: *const PreparedResources, fence_or_frame: anytype) ?VulkanRetirementFence {
    if (comptime !build_options.enable_vulkan) return null;
    const vk_resources = resources.vulkan orelse return null;
    const T = @TypeOf(fence_or_frame);
    switch (@typeInfo(T)) {
        .@"struct" => {
            if (@hasField(T, "fence")) return makeVulkanRetirementFence(vk_resources.ctx.device, fence_or_frame.fence);
            return null;
        },
        else => return makeVulkanRetirementFence(vk_resources.ctx.device, fence_or_frame),
    }
}

fn makeVulkanRetirementFence(device: if (build_options.enable_vulkan) vulkan_pipeline.vk.VkDevice else void, fence: anytype) ?VulkanRetirementFence {
    if (comptime !build_options.enable_vulkan) return null;
    const T = @TypeOf(fence);
    switch (@typeInfo(T)) {
        .pointer, .optional => {
            const vk_fence: vulkan_pipeline.vk.VkFence = @ptrCast(fence);
            if (vk_fence == null) return null;
            return .{ .device = device, .fence = vk_fence };
        },
        else => return null,
    }
}

pub const ResourceUploadPlan = struct {
    set: *const ResourceSet,
    /// Bytes this backend path will upload or construct for the next prepared
    /// resource set. Backend packing may make this larger than `changed_bytes`.
    upload_bytes: usize = 0,
    /// Bytes whose dependency stamp differs from `current`, keyed by stable
    /// ResourceSet keys. Exposed so callers can see intent-preserving changes.
    changed_bytes: usize = 0,
    changed_keys: []ResourceKey = &.{},
    changed_len: usize = 0,

    pub fn changedKeys(self: *const ResourceUploadPlan) []const ResourceKey {
        return self.changed_keys[0..self.changed_len];
    }

    fn addChanged(self: *ResourceUploadPlan, key: ResourceKey, bytes: usize) !void {
        if (self.changed_len >= self.changed_keys.len) return error.ResourceUploadPlanFull;
        self.changed_keys[self.changed_len] = key;
        self.changed_len += 1;
        self.changed_bytes += bytes;
    }
};

pub const PendingResourceUpload = struct {
    renderer: *Renderer,
    allocator: std.mem.Allocator,
    plan: ResourceUploadPlan,
    prepared: ?PreparedResources = null,
    external_completion_required: bool = false,
    ready_to_publish: bool = false,

    /// Record upload work for this plan. Vulkan records into a caller-owned
    /// command buffer; CPU and GL complete during this call.
    pub fn record(self: *PendingResourceUpload, cmd_or_context: anytype, options: struct { budget_bytes: usize = std.math.maxInt(usize) }) !void {
        if (self.prepared != null) return;
        if (self.plan.upload_bytes > options.budget_bytes) return error.ResourceUploadBudgetExceeded;

        if (comptime build_options.enable_vulkan) {
            if (self.renderer.vtable == &Renderer.vulkan_borrowed_vtable) {
                const cmd = vulkanUploadCommand(cmd_or_context) orelse return error.MissingUploadCommand;
                const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(self.renderer.ptr));
                vk_state.beginResourceUploadRecording(cmd);
                defer vk_state.endResourceUploadRecording();
                self.prepared = try uploadPreparedResources(self.renderer, self.plan.set, self.allocator);
                self.external_completion_required = true;
                self.ready_to_publish = false;
                return;
            }
        }

        self.prepared = try self.renderer.uploadResourcesBlocking(self.allocator, self.plan.set);
        self.external_completion_required = false;
        self.ready_to_publish = true;
    }

    pub fn ready(self: *PendingResourceUpload, fence_or_frame: anytype) bool {
        if (self.prepared == null) return false;
        if (!self.external_completion_required) {
            self.ready_to_publish = true;
            return true;
        }
        if (self.externalCompletionReady(fence_or_frame)) {
            self.ready_to_publish = true;
            return true;
        }
        return false;
    }

    pub fn publish(self: *PendingResourceUpload) !PreparedResources {
        if (self.external_completion_required and !self.ready_to_publish) return error.ResourceUploadNotReady;
        if (self.prepared) |prepared| {
            sweepRetiredPreparedResources();
            self.prepared = null;
            self.external_completion_required = false;
            self.ready_to_publish = false;
            return prepared;
        }
        return error.ResourceUploadNotReady;
    }

    pub fn deinit(self: *PendingResourceUpload) void {
        if (self.prepared) |*prepared| prepared.deinit();
        self.prepared = null;
        self.external_completion_required = false;
        self.ready_to_publish = false;
    }

    fn externalCompletionReady(self: *const PendingResourceUpload, fence_or_frame: anytype) bool {
        const T = @TypeOf(fence_or_frame);
        if (T == bool) return fence_or_frame;

        switch (@typeInfo(T)) {
            .@"struct" => {
                if (@hasField(T, "ready")) return fence_or_frame.ready;
                if (@hasField(T, "complete")) return fence_or_frame.complete;
                if (@hasField(T, "signaled")) return fence_or_frame.signaled;
                if (comptime build_options.enable_vulkan) {
                    if (@hasField(T, "fence")) return self.vulkanFenceReady(fence_or_frame.fence);
                }
            },
            else => {},
        }

        if (comptime build_options.enable_vulkan) {
            return self.vulkanFenceReady(fence_or_frame);
        }
        return false;
    }

    fn vulkanFenceReady(self: *const PendingResourceUpload, fence: anytype) bool {
        if (comptime !build_options.enable_vulkan) return false;
        if (self.renderer.vtable != &Renderer.vulkan_borrowed_vtable) return false;
        const T = @TypeOf(fence);
        switch (@typeInfo(T)) {
            .pointer, .optional => {
                const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(self.renderer.ptr));
                const vk_fence: vulkan_pipeline.vk.VkFence = @ptrCast(fence);
                return vulkan_pipeline.vk.vkGetFenceStatus(vk_state.ctx.device, vk_fence) == vulkan_pipeline.vk.VK_SUCCESS;
            },
            else => return false,
        }
    }
};

fn vulkanUploadCommand(cmd_or_context: anytype) vulkan_pipeline.vk.VkCommandBuffer {
    if (comptime !build_options.enable_vulkan) return null;
    const T = @TypeOf(cmd_or_context);
    switch (@typeInfo(T)) {
        .@"struct" => {
            if (@hasField(T, "cmd")) return cmd_or_context.cmd;
            if (@hasField(T, "command_buffer")) return cmd_or_context.command_buffer;
            return null;
        },
        .pointer, .optional => return @ptrCast(cmd_or_context),
        else => return null,
    }
}

pub const DrawOptions = struct {
    mvp: Mat4,
    target: ResolveTarget,
};

pub const DrawSegment = struct {
    kind: enum { text, path },
    offset: usize,
    len: usize,
    texture_layer_base: u32 = 0,
    key: ResourceKey,
    resource_stamp: ResourceStamp,
    target_stamp: TargetStamp,
};

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const DrawSegment,
};

pub const DrawList = struct {
    buf: []u32,
    len: usize = 0,
    segments_buf: []DrawSegment,
    segment_len: usize = 0,

    pub fn init(buf: []u32, segments_buf: []DrawSegment) DrawList {
        return .{ .buf = buf, .segments_buf = segments_buf };
    }

    pub fn reset(self: *DrawList) void {
        self.len = 0;
        self.segment_len = 0;
    }

    pub fn slice(self: *const DrawList) DrawRecords {
        return .{
            .words = self.buf[0..self.len],
            .segments = self.segments_buf[0..self.segment_len],
        };
    }

    pub fn estimate(scene: *const Scene, options: DrawOptions) usize {
        _ = options;
        var total: usize = 0;
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| total += @max(text.blob.instance_count_hint, 1) * TEXT_WORDS_PER_GLYPH,
                .path => |path| total += @max(path.picture.shapeCount(), 1) * PATH_WORDS_PER_SHAPE,
            }
        }
        return total;
    }

    pub fn estimateSegments(scene: *const Scene, options: DrawOptions) usize {
        _ = options;
        var total: usize = 0;
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| total += @max(text.blob.glyphCount(), 1),
                .path => |path| total += @max(path.picture.instances.len, 1),
            }
        }
        return total;
    }

    pub fn addScene(
        self: *DrawList,
        prepared: *const PreparedResources,
        scene: *const Scene,
        options: DrawOptions,
    ) !void {
        const hint_context = sceneToScreenTransform(options.mvp, options.target.pixel_width, options.target.pixel_height);
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| {
                    const view = try prepared.textAtlasView(text.blob.atlas);
                    var glyph_start: usize = 0;
                    while (glyph_start < text.blob.glyphCount()) {
                        const start = self.len;
                        var batch = TextBatch.init(self.buf[self.len..]);
                        const result = try text.blob.appendToBatchFrom(&batch, view, text.transform, text.resolve, options.target, hint_context, glyph_start);
                        glyph_start = result.next_glyph;
                        if (batch.glyphCount() == 0) {
                            if (result.completed) break;
                            continue;
                        }
                        self.len += batch.slice().len;
                        try self.addSegment(.{
                            .kind = .text,
                            .offset = start,
                            .len = batch.slice().len,
                            .texture_layer_base = result.layer_window_base,
                            .key = prepared.textAtlasEntry(text.blob.atlas).?.key,
                            .resource_stamp = try prepared.textStamp(text.blob.atlas),
                            .target_stamp = TargetStamp.from(options.mvp, options.target, text.resolve.hinting),
                        });
                        if (result.completed) break;
                    }
                },
                .path => |path| {
                    const view = try prepared.pathAtlasView(path.picture);
                    var instance_start: usize = 0;
                    while (instance_start < path.picture.instances.len) {
                        const start = self.len;
                        var batch = PathBatch.init(self.buf[self.len..]);
                        const result = try batch.addPictureTransformedFrom(&view, path.picture, path.transform, instance_start);
                        instance_start = result.next_instance;
                        if (batch.shapeCount() == 0) {
                            if (result.completed) break;
                            continue;
                        }
                        self.len += batch.slice().len;
                        try self.addSegment(.{
                            .kind = .path,
                            .offset = start,
                            .len = batch.slice().len,
                            .texture_layer_base = result.layer_window_base,
                            .key = prepared.pathPictureEntry(path.picture).?.key,
                            .resource_stamp = try prepared.pathStamp(path.picture),
                            .target_stamp = TargetStamp.from(options.mvp, options.target, .none),
                        });
                        if (result.completed) break;
                    }
                },
            }
        }
    }

    fn addSegment(self: *DrawList, segment: DrawSegment) !void {
        if (self.segment_len >= self.segments_buf.len) return error.DrawListFull;
        self.segments_buf[self.segment_len] = segment;
        self.segment_len += 1;
    }
};

pub const PreparedScene = struct {
    allocator: std.mem.Allocator,
    words: []u32 = &.{},
    segments: []DrawSegment = &.{},

    pub fn initOwned(
        allocator: std.mem.Allocator,
        prepared: *const PreparedResources,
        scene: *const Scene,
        options: DrawOptions,
    ) !PreparedScene {
        const needed = DrawList.estimate(scene, options);
        const needed_segments = DrawList.estimateSegments(scene, options);
        const words = try allocator.alloc(u32, needed);
        errdefer allocator.free(words);
        const segment_buf = try allocator.alloc(DrawSegment, needed_segments);
        errdefer allocator.free(segment_buf);
        var draw = DrawList.init(words, segment_buf);
        try draw.addScene(prepared, scene, options);
        const segments = try allocator.dupe(DrawSegment, draw.slice().segments);
        errdefer allocator.free(segments);
        allocator.free(segment_buf);
        return .{
            .allocator = allocator,
            .words = words[0..draw.len],
            .segments = segments,
        };
    }

    pub fn deinit(self: *PreparedScene) void {
        if (self.words.len > 0) self.allocator.free(self.words);
        if (self.segments.len > 0) self.allocator.free(self.segments);
        self.* = undefined;
    }

    pub fn slice(self: *const PreparedScene) DrawRecords {
        return .{
            .words = self.words,
            .segments = self.segments,
        };
    }
};

fn textAtlasStamp(atlas: *const TextAtlas) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(atlas.pageCount())), @as(u64, atlas.layer_info_width));
    layout = mix64(layout, atlas.layer_info_height);
    var content = atlas.snapshotIdentity();
    for (atlas.pageSlice()) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
    }
    return .{
        .identity = atlas.snapshotIdentity(),
        .layout = layout,
        .content = content,
    };
}

fn pathPictureStamp(picture: *const PathPicture) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(picture.shapeCount())), picture.atlas.pageCount());
    layout = mix64(layout, picture.atlas.layer_info_width);
    layout = mix64(layout, picture.atlas.layer_info_height);
    var content = @as(u64, @intCast(@intFromPtr(picture)));
    for (picture.atlas.pages) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
    }
    if (picture.atlas.layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x5041544850494354, std.mem.sliceAsBytes(data)));
    }
    return .{
        .identity = @intCast(@intFromPtr(picture)),
        .layout = layout,
        .content = content,
    };
}

fn imageStamp(image: *const Image) ResourceStamp {
    const pixels = image.pixelSlice();
    return .{
        .identity = @intCast(@intFromPtr(image)),
        .layout = mix64(@as(u64, image.width), image.height),
        .content = std.hash.Wyhash.hash(0x494d414745535247, pixels),
    };
}

fn curveAtlasUploadBytes(atlas: *const Atlas) usize {
    var total: usize = 0;
    for (0..atlas.pageCount()) |i| {
        total += atlas.page(@intCast(i)).textureBytes();
    }
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    if (atlas.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            total += image.pixelSlice().len;
        }
    }
    return total;
}

fn textAtlasUploadBytes(atlas: *const TextAtlas) usize {
    var total: usize = 0;
    for (atlas.pageSlice()) |page| total += page.textureBytes();
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

fn resourceEntryKey(entry: ResourceSet.Entry) ResourceKey {
    return switch (entry) {
        .text_atlas => |text| text.key,
        .path_picture => |path| path.key,
        .image => |image| image.key,
    };
}

fn resourceEntryStamp(entry: ResourceSet.Entry) ResourceStamp {
    return switch (entry) {
        .text_atlas => |text| textAtlasStamp(text.atlas),
        .path_picture => |path| pathPictureStamp(path.picture),
        .image => |image| imageStamp(image.image),
    };
}

fn resourceEntryUploadBytes(entry: ResourceSet.Entry) usize {
    return switch (entry) {
        .text_atlas => |text| textAtlasUploadBytes(text.atlas),
        .path_picture => |path| curveAtlasUploadBytes(&path.picture.atlas),
        .image => |image| image.image.pixelSlice().len,
    };
}

fn uploadPreparedResources(renderer: *Renderer, set: *const ResourceSet, allocator: std.mem.Allocator) !PreparedResources {
    var atlas_count: usize = 0;
    var image_count: usize = 0;
    for (set.slice()) |entry| switch (entry) {
        .text_atlas, .path_picture => atlas_count += 1,
        .image => image_count += 1,
    };

    var prepared = PreparedResources{
        .allocator = allocator,
        .atlases = try allocator.alloc(PreparedResources.PreparedAtlasResource, atlas_count),
        .images = try allocator.alloc(PreparedResources.PreparedImageResource, image_count),
    };
    errdefer prepared.deinit();

    const upload_atlases = try allocator.alloc(*const Atlas, atlas_count);
    defer allocator.free(upload_atlases);
    const atlas_views = try allocator.alloc(PreparedAtlasView, atlas_count);
    defer allocator.free(atlas_views);

    const upload_images = try allocator.alloc(*const Image, image_count);
    defer allocator.free(upload_images);
    const image_views = try allocator.alloc(PreparedImageView, image_count);
    defer allocator.free(image_views);

    var atlas_i: usize = 0;
    var image_i: usize = 0;
    for (set.slice()) |entry| {
        switch (entry) {
            .text_atlas => |text| {
                prepared.atlases[atlas_i] = .{
                    .key = text.key,
                    .kind = .text,
                    .text_atlas = text.atlas,
                    .atlas = undefined,
                    .owns_wrapper = true,
                    .stamp = textAtlasStamp(text.atlas),
                };
                prepared.atlases[atlas_i].wrapper = text.atlas.uploadAtlas();
                prepared.atlases[atlas_i].atlas = &prepared.atlases[atlas_i].wrapper;
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_i += 1;
            },
            .path_picture => |path| {
                prepared.atlases[atlas_i] = .{
                    .key = path.key,
                    .kind = .path,
                    .picture = path.picture,
                    .atlas = &path.picture.atlas,
                    .stamp = pathPictureStamp(path.picture),
                };
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_i += 1;
            },
            .image => |image| {
                prepared.images[image_i] = .{
                    .key = image.key,
                    .image = image.image,
                    .stamp = imageStamp(image.image),
                };
                upload_images[image_i] = image.image;
                image_i += 1;
            },
        }
    }

    const uploaded = blk: {
        if (renderer.vtable == &Renderer.gl_vtable or renderer.vtable == &Renderer.gl_borrowed_vtable) {
            const gl_state: *pipeline.GlTextState = @ptrCast(@alignCast(renderer.ptr));
            var gl_prepared = pipeline.PreparedResources{ .allocator = allocator, .backend = gl_state.backend };
            if (atlas_count > 0) try gl_prepared.uploadAtlases(upload_atlases, atlas_views);
            if (image_count > 0) gl_prepared.uploadImages(upload_images, image_views);
            prepared.gl = gl_prepared;
            break :blk true;
        }
        if (comptime build_options.enable_vulkan) {
            if (renderer.vtable == &Renderer.vulkan_borrowed_vtable) {
                const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(renderer.ptr));
                var vk_prepared = try vulkan_pipeline.PreparedResources.init(vk_state);
                errdefer vk_prepared.deinit();
                if (atlas_count > 0) vk_state.uploadPreparedAtlases(&vk_prepared, upload_atlases, atlas_views);
                if (image_count > 0) vk_state.uploadPreparedImages(&vk_prepared, upload_images, image_views);
                prepared.vulkan = vk_prepared;
                break :blk true;
            }
        }
        if (comptime build_options.enable_cpu) {
            if (renderer.vtable == &Renderer.cpu_vtable) {
                var cpu_prepared = try cpu_renderer_mod.PreparedResources.init(allocator, upload_atlases);
                errdefer cpu_prepared.deinit();
                if (atlas_count > 0) try cpu_prepared.uploadAtlases(upload_atlases, atlas_views);
                if (image_count > 0) cpu_prepared.uploadImages(upload_images, image_views);
                prepared.cpu = cpu_prepared;
                break :blk true;
            }
        }
        break :blk false;
    };
    if (!uploaded) return error.UnsupportedRenderer;

    for (prepared.atlases, 0..) |*entry, i| entry.view = atlas_views[i];
    for (prepared.images, 0..) |*entry, i| entry.view = image_views[i];
    return prepared;
}

/// Renderer execution machinery. Backend resources live in PreparedResources.
pub const Renderer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        drawText: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        drawPaths: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        beginFrame: *const fn (*anyopaque) void,
        setSubpixelOrder: *const fn (*anyopaque, SubpixelOrder) void,
        getSubpixelOrder: *const fn (*anyopaque) SubpixelOrder,
        setFillRule: *const fn (*anyopaque, FillRule) void,
        getFillRule: *const fn (*anyopaque) FillRule,
        backendName: *const fn (*anyopaque) []const u8,
    };

    /// Generate a VTable that type-erases calls to methods on *T.
    fn ImplVTable(comptime T: type, comptime owned: bool) VTable {
        const S = struct {
            fn cast(ptr: *anyopaque) *T {
                return @ptrCast(@alignCast(ptr));
            }
            fn constCast(ptr: *anyopaque) *const T {
                return @ptrCast(@alignCast(ptr));
            }
            fn deinitFn(ptr: *anyopaque) void {
                const self = cast(ptr);
                self.deinit();
                if (owned) std.heap.smp_allocator.destroy(self);
            }
            fn noopDeinit(_: *anyopaque) void {}
            fn drawTextFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
                if (prepared) |backend_prepared| {
                    if (comptime build_options.enable_cpu and T == CpuRenderer and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const cpu_renderer_mod.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime T == pipeline.GlTextState and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const vulkan_pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                }
                std.debug.panic("drawText requires PreparedResources ({*}, {d}, {d}, {d}, {d})", .{ ptr, verts.len, mvp.data[0], vw, vh });
            }
            fn drawPathsFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
                if (prepared) |backend_prepared| {
                    if (comptime build_options.enable_cpu and T == CpuRenderer and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const cpu_renderer_mod.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime T == pipeline.GlTextState and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const vulkan_pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                }
                std.debug.panic("drawPaths requires PreparedResources ({*}, {d}, {d}, {d}, {d})", .{ ptr, verts.len, mvp.data[0], vw, vh });
            }
            fn beginFrameFn(ptr: *anyopaque) void {
                cast(ptr).beginFrame();
            }
            fn setSubpixelOrderFn(ptr: *anyopaque, order: SubpixelOrder) void {
                cast(ptr).setSubpixelOrder(order);
            }
            fn getSubpixelOrderFn(ptr: *anyopaque) SubpixelOrder {
                return constCast(ptr).getSubpixelOrder();
            }
            fn setFillRuleFn(ptr: *anyopaque, rule: FillRule) void {
                cast(ptr).setFillRule(rule);
            }
            fn getFillRuleFn(ptr: *anyopaque) FillRule {
                return constCast(ptr).getFillRule();
            }
            fn backendNameFn(ptr: *anyopaque) []const u8 {
                return constCast(ptr).backendName();
            }
        };
        return .{
            .deinit = if (owned) &S.deinitFn else &S.noopDeinit,
            .drawText = &S.drawTextFn,
            .drawPaths = &S.drawPathsFn,
            .beginFrame = &S.beginFrameFn,
            .setSubpixelOrder = &S.setSubpixelOrderFn,
            .getSubpixelOrder = &S.getSubpixelOrderFn,
            .setFillRule = &S.setFillRuleFn,
            .getFillRule = &S.getFillRuleFn,
            .backendName = &S.backendNameFn,
        };
    }

    const gl_vtable = ImplVTable(pipeline.GlTextState, true);
    const gl_borrowed_vtable = ImplVTable(pipeline.GlTextState, false);
    const vulkan_borrowed_vtable = ImplVTable(vulkan_pipeline.VulkanPipeline, false);
    const cpu_vtable = ImplVTable(CpuRenderer, false);

    /// Blocking upload for simple programs. GL requires the target context to
    /// be current. CPU upload builds cheap views. Vulkan does not perform an
    /// implicit device/queue idle here.
    pub fn uploadResourcesBlocking(self: *Renderer, allocator: std.mem.Allocator, set: *const ResourceSet) !PreparedResources {
        sweepRetiredPreparedResources();
        return uploadPreparedResources(self, set, allocator);
    }

    pub fn planResourceUpload(self: *Renderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        _ = self;
        var plan = ResourceUploadPlan{ .set = next_set, .changed_keys = changed_keys };
        for (next_set.slice()) |entry| {
            const key = resourceEntryKey(entry);
            const stamp = resourceEntryStamp(entry);
            const bytes = resourceEntryUploadBytes(entry);
            plan.upload_bytes += bytes;
            const old_stamp = if (current) |prepared| prepared.stampForKey(key) else null;
            const changed = if (old_stamp) |old| !old.eql(stamp) else true;
            if (changed) {
                try plan.addChanged(key, bytes);
            }
        }
        return plan;
    }

    pub fn beginResourceUpload(self: *Renderer, allocator: std.mem.Allocator, plan: ResourceUploadPlan) !PendingResourceUpload {
        sweepRetiredPreparedResources();
        return .{ .renderer = self, .allocator = allocator, .plan = plan };
    }

    /// Execute prebuilt draw records. This never discovers, uploads, allocates,
    /// or invalidates resources.
    pub fn draw(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        self.setSubpixelOrder(effectiveSubpixelOrder(options.target));
        self.setFillRule(options.target.fill_rule);
        self.beginFrame();
        const backend_prepared: ?*const anyopaque = blk: {
            if (self.vtable == &gl_vtable or self.vtable == &gl_borrowed_vtable) {
                if (prepared.gl) |*gl_prepared| break :blk @ptrCast(gl_prepared);
                return error.MissingPreparedResource;
            }
            if (comptime build_options.enable_vulkan) if (self.vtable == &vulkan_borrowed_vtable) {
                if (prepared.vulkan) |*vk_prepared| break :blk @ptrCast(vk_prepared);
                return error.MissingPreparedResource;
            };
            if (comptime build_options.enable_cpu) if (self.vtable == &cpu_vtable) {
                if (prepared.cpu) |*cpu_prepared| break :blk @ptrCast(cpu_prepared);
                return error.MissingPreparedResource;
            };
            break :blk null;
        };
        for (records.segments) |segment| {
            const actual_stamp = prepared.stampForKey(segment.key) orelse return error.MissingPreparedResource;
            if (!actual_stamp.eql(segment.resource_stamp)) return error.StaleDrawRecords;
            const expected_target_stamp = TargetStamp.from(options.mvp, options.target, segment.target_stamp.hinting);
            if (!std.meta.eql(expected_target_stamp, segment.target_stamp)) return error.StaleDrawRecords;
            const vertices = records.words[segment.offset..][0..segment.len];
            switch (segment.kind) {
                .text => if (vertices.len > 0) self.drawText(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
                .path => if (vertices.len > 0) self.drawPaths(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
            }
        }
    }

    pub fn drawPrepared(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        try self.draw(prepared, scene.slice(), options);
    }

    /// Initialize with the current OpenGL context.
    pub fn init() !Renderer {
        const text = try std.heap.smp_allocator.create(pipeline.GlTextState);
        text.* = .{};
        errdefer std.heap.smp_allocator.destroy(text);
        try text.init();
        return .{ .ptr = @ptrCast(text), .vtable = &gl_vtable };
    }

    /// Initialize the CPU renderer with a caller-owned pixel buffer.
    pub fn initCpu(cpu: *CpuRenderer) Renderer {
        return .{ .ptr = @ptrCast(cpu), .vtable = &cpu_vtable };
    }

    pub fn deinit(self: *Renderer) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn beginFrame(self: *Renderer) void {
        self.vtable.beginFrame(self.ptr);
    }

    fn drawText(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawText(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    fn drawPaths(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawPaths(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    pub fn setSubpixelOrder(self: *Renderer, order: SubpixelOrder) void {
        self.vtable.setSubpixelOrder(self.ptr, order);
    }

    pub fn subpixelOrder(self: *const Renderer) SubpixelOrder {
        return self.vtable.getSubpixelOrder(@constCast(self.ptr));
    }

    pub fn setSubpixel(self: *Renderer, enabled: bool) void {
        self.setSubpixelOrder(if (enabled) .rgb else .none);
    }

    pub fn subpixelEnabled(self: *const Renderer) bool {
        return self.subpixelOrder() != .none;
    }

    pub fn setFillRule(self: *Renderer, rule: FillRule) void {
        self.vtable.setFillRule(self.ptr, rule);
    }

    pub fn fillRule(self: *const Renderer) FillRule {
        return self.vtable.getFillRule(@constCast(self.ptr));
    }

    pub fn backendName(self: *const Renderer) []const u8 {
        return self.vtable.backendName(@constCast(self.ptr));
    }
};

pub const GlRenderer = struct {
    allocator: std.mem.Allocator,
    state: *pipeline.GlTextState,

    pub fn init(allocator: std.mem.Allocator) !GlRenderer {
        const text = try allocator.create(pipeline.GlTextState);
        text.* = .{};
        errdefer allocator.destroy(text);
        try text.init();
        return .{ .allocator = allocator, .state = text };
    }

    pub fn deinit(self: *GlRenderer) void {
        self.state.deinit();
        self.allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *GlRenderer) Renderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &Renderer.gl_borrowed_vtable };
    }

    pub fn uploadResourcesBlocking(self: *GlRenderer, allocator: std.mem.Allocator, set: *const ResourceSet) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocator, set);
    }

    pub fn planResourceUpload(self: *GlRenderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *GlRenderer, allocator: std.mem.Allocator, plan: ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocator, plan);
    }

    pub fn draw(self: *GlRenderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *GlRenderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    pub fn textCoverageBackend(self: *GlRenderer, prepared: *const PreparedResources) ?TextCoverageBackend {
        if (prepared.gl) |*gl_resources| {
            return .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared };
        }
        return null;
    }

    pub fn backendName(self: *const GlRenderer) []const u8 {
        return self.state.backendName();
    }
};

pub const VulkanRenderer = struct {
    state: *vulkan_pipeline.VulkanPipeline,

    pub fn init(vk_ctx: VulkanContext) !VulkanRenderer {
        const vkp = try std.heap.smp_allocator.create(vulkan_pipeline.VulkanPipeline);
        vkp.* = .{};
        errdefer std.heap.smp_allocator.destroy(vkp);
        try vkp.init(vk_ctx);
        return .{ .state = vkp };
    }

    pub fn deinit(self: *VulkanRenderer) void {
        self.state.deinit();
        std.heap.smp_allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *VulkanRenderer) Renderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &Renderer.vulkan_borrowed_vtable };
    }

    pub fn beginFrame(self: *VulkanRenderer, frame: anytype) void {
        self.state.setCommandBuffer(frame.cmd);
        self.state.setFrameSlot(frame.frame_index);
    }

    pub fn uploadResourcesBlocking(self: *VulkanRenderer, allocator: std.mem.Allocator, set: *const ResourceSet) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocator, set);
    }

    pub fn planResourceUpload(self: *VulkanRenderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *VulkanRenderer, allocator: std.mem.Allocator, plan: ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocator, plan);
    }

    pub fn draw(self: *VulkanRenderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *VulkanRenderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    pub fn backendName(self: *const VulkanRenderer) []const u8 {
        return self.state.backendName();
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
    _ = @import("render/vertex.zig");
    _ = @import("torture_test.zig");
    _ = @import("fonts.zig");
}

test "vector path approximates cubic commands into quadratic segments and reports bounds" {
    var path = Path.init(std.testing.allocator);
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

fn testRectPicture(allocator: std.mem.Allocator, x: f32) !PathPicture {
    var path = Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = x, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .color = .{ 0.2, 0.4, 0.8, 1.0 } }, .identity);
    return builder.freeze(allocator);
}

test "draw with missing prepared resources fails" {
    const allocator = std.testing.allocator;
    const width: u32 = 4;
    const height: u32 = 4;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var prepared = PreparedResources{ .allocator = allocator };
    var words: [TEXT_WORDS_PER_GLYPH]u32 = undefined;
    const segments = [_]DrawSegment{.{
        .kind = .text,
        .offset = 0,
        .len = TEXT_WORDS_PER_GLYPH,
        .key = ResourceKey.named("missing"),
        .resource_stamp = .{},
        .target_stamp = .{},
    }};
    const records = DrawRecords{ .words = &words, .segments = &segments };
    try std.testing.expectError(error.MissingPreparedResource, renderer.draw(&prepared, records, .{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height },
    }));
}

test "draw dispatch uses only prepared stamps and caller records" {
    const FakeState = struct {
        begin_count: u32 = 0,
        text_count: u32 = 0,
        path_count: u32 = 0,
        words_seen: usize = 0,
        viewport_seen: [2]f32 = .{ 0, 0 },
        subpixel_order: SubpixelOrder = .none,
        fill_rule: FillRule = .non_zero,
        saw_backend_prepared: bool = true,
    };
    const Fake = struct {
        fn state(ptr: *anyopaque) *FakeState {
            return @ptrCast(@alignCast(ptr));
        }
        fn deinit(_: *anyopaque) void {}
        fn drawText(ptr: *anyopaque, backend_prepared: ?*const anyopaque, vertices: []const u32, _: Mat4, viewport_w: f32, viewport_h: f32, _: u32) void {
            const s = state(ptr);
            s.text_count += 1;
            s.words_seen += vertices.len;
            s.viewport_seen = .{ viewport_w, viewport_h };
            s.saw_backend_prepared = backend_prepared != null;
        }
        fn drawPaths(ptr: *anyopaque, backend_prepared: ?*const anyopaque, vertices: []const u32, _: Mat4, viewport_w: f32, viewport_h: f32, _: u32) void {
            const s = state(ptr);
            s.path_count += 1;
            s.words_seen += vertices.len;
            s.viewport_seen = .{ viewport_w, viewport_h };
            s.saw_backend_prepared = backend_prepared != null;
        }
        fn beginFrame(ptr: *anyopaque) void {
            state(ptr).begin_count += 1;
        }
        fn setSubpixelOrder(ptr: *anyopaque, order: SubpixelOrder) void {
            state(ptr).subpixel_order = order;
        }
        fn getSubpixelOrder(ptr: *anyopaque) SubpixelOrder {
            return state(ptr).subpixel_order;
        }
        fn setFillRule(ptr: *anyopaque, rule: FillRule) void {
            state(ptr).fill_rule = rule;
        }
        fn getFillRule(ptr: *anyopaque) FillRule {
            return state(ptr).fill_rule;
        }
        fn backendName(_: *anyopaque) []const u8 {
            return "fake";
        }
    };
    const fake_vtable = Renderer.VTable{
        .deinit = Fake.deinit,
        .drawText = Fake.drawText,
        .drawPaths = Fake.drawPaths,
        .beginFrame = Fake.beginFrame,
        .setSubpixelOrder = Fake.setSubpixelOrder,
        .getSubpixelOrder = Fake.getSubpixelOrder,
        .setFillRule = Fake.setFillRule,
        .getFillRule = Fake.getFillRule,
        .backendName = Fake.backendName,
    };

    const key = ResourceKey.named("shape");
    const stamp = ResourceStamp{ .identity = 1, .layout = 2, .content = 3 };
    var image: Image = .{ .allocator = std.testing.allocator, .width = 1, .height = 1, .pixels = &.{ 255, 255, 255, 255 } };
    var image_resources = [_]PreparedResources.PreparedImageResource{.{
        .key = key,
        .image = &image,
        .stamp = stamp,
    }};
    var prepared = PreparedResources{
        .allocator = std.testing.allocator,
        .images = image_resources[0..],
    };

    const options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{
            .pixel_width = 8,
            .pixel_height = 8,
            .subpixel_order = .rgb,
            .fill_rule = .even_odd,
        },
    };
    var words = [_]u32{ 1, 2, 3, 4 };
    const segments = [_]DrawSegment{.{
        .kind = .text,
        .offset = 0,
        .len = words.len,
        .key = key,
        .resource_stamp = stamp,
        .target_stamp = TargetStamp.from(options.mvp, options.target, .none),
    }};
    const records = DrawRecords{ .words = &words, .segments = &segments };

    var state: FakeState = .{};
    var renderer = Renderer{ .ptr = @ptrCast(&state), .vtable = &fake_vtable };
    try renderer.draw(&prepared, records, options);

    try std.testing.expectEqual(@as(u32, 1), state.begin_count);
    try std.testing.expectEqual(@as(u32, 1), state.text_count);
    try std.testing.expectEqual(@as(u32, 0), state.path_count);
    try std.testing.expectEqual(words.len, state.words_seen);
    try std.testing.expectEqual(SubpixelOrder.rgb, state.subpixel_order);
    try std.testing.expectEqual(FillRule.even_odd, state.fill_rule);
    try std.testing.expectEqual(@as(f32, 8), state.viewport_seen[0]);
    try std.testing.expectEqual(@as(f32, 8), state.viewport_seen[1]);
    try std.testing.expect(!state.saw_backend_prepared);
}

test "Renderer.draw source stays free of upload allocation and retirement sweeps" {
    const source = @embedFile("snail.zig");
    const start = std.mem.indexOf(u8, source, "pub fn draw(self: *Renderer").?;
    const end = start + std.mem.indexOf(u8, source[start..], "pub fn drawPrepared").?;
    const draw_source = source[start..end];
    try std.testing.expect(std.mem.indexOf(u8, draw_source, "uploadResources") == null);
    try std.testing.expect(std.mem.indexOf(u8, draw_source, "sweepRetiredPreparedResources") == null);
    try std.testing.expect(std.mem.indexOf(u8, draw_source, ".alloc(") == null);
}

test "Vulkan renderer path contains no device or queue idle" {
    const source = @embedFile("render/vulkan_pipeline.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "vkDeviceWaitIdle") == null);
    try std.testing.expect(std.mem.indexOf(u8, source, "vkQueueWaitIdle") == null);
}

test "Vulkan scheduled upload path records without internal submit" {
    const source = @embedFile("render/vulkan_pipeline.zig");
    const start = std.mem.indexOf(u8, source, "fn finishTransferCommand").?;
    const end = start + std.mem.indexOf(u8, source[start..], "fn submitTransferAndWait").?;
    const scheduled_finish = source[start..end];
    try std.testing.expect(std.mem.indexOf(u8, source, "beginResourceUploadRecording") != null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "if (!transfer.owned) return;") != null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "vkQueueSubmit") == null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "vkWaitForFences") == null);
}

test "Vulkan upload command helper accepts frame command fields" {
    if (!build_options.enable_vulkan) return;
    const cmd: vulkan_pipeline.vk.VkCommandBuffer = null;
    try std.testing.expect(vulkanUploadCommand(.{ .cmd = cmd }) == null);
    try std.testing.expect(vulkanUploadCommand(.{ .command_buffer = cmd }) == null);
}

test "TextBlob validation catches wrong atlas snapshot" {
    const assets_data = @import("assets");
    var atlas = try TextAtlas.init(std.testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();

    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(std.testing.allocator, &atlas);
    defer builder.deinit();
    _ = try builder.addText(.{}, "A", 0, 20, 16, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();
    try blob.validate();

    if (try atlas.ensureText(.{}, "B")) |next| {
        atlas.deinit();
        atlas = next;
    }
    try std.testing.expectError(error.WrongTextAtlasSnapshot, blob.validate());
}

test "replacing path-picture key does not invalidate unrelated text coverage records" {
    const assets_data = @import("assets");
    const allocator = std.testing.allocator;

    var atlas = try TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "Hello")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(allocator, &atlas);
    defer builder.deinit();
    _ = try builder.addText(.{}, "Hello", 0, 24, 18, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var set_a_entries: [4]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putTextAtlas(.fonts, &atlas);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(allocator, &set_a);
    defer prepared_a.deinit();

    var records = TextCoverageRecords.initOwned(allocator);
    defer records.deinit();
    try records.buildLocal(&prepared_a, &blob, .{});
    try std.testing.expect(records.validFor(&prepared_a));

    var set_b_entries: [4]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putTextAtlas(.fonts, &atlas);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var prepared_b = try renderer.uploadResourcesBlocking(allocator, &set_b);
    defer prepared_b.deinit();

    try std.testing.expect(records.validFor(&prepared_b));
}

test "draw rejects stale records when a resource key is replaced" {
    const allocator = std.testing.allocator;

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 32;
    const height: u32 = 32;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addPathPicture(&picture_a);

    var set_a_entries: [2]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(allocator, &set_a);
    defer prepared_a.deinit();

    const draw_options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height },
    };
    const needed = DrawList.estimate(&scene, draw_options);
    const needed_segments = DrawList.estimateSegments(&scene, draw_options);
    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments = try allocator.alloc(DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared_a, &scene, draw_options);

    var set_b_entries: [2]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var prepared_b = try renderer.uploadResourcesBlocking(allocator, &set_b);
    defer prepared_b.deinit();

    try std.testing.expectError(error.StaleDrawRecords, renderer.draw(&prepared_b, draw.slice(), draw_options));
}

test "resource upload plan reports changed keys and enforces budget" {
    const allocator = std.testing.allocator;

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var set_a_entries: [2]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(allocator, &set_a);
    defer prepared_a.deinit();

    var changed_same: [2]ResourceKey = undefined;
    const plan_same = try renderer.planResourceUpload(&prepared_a, &set_a, &changed_same);
    try std.testing.expect(plan_same.upload_bytes > 0);
    try std.testing.expectEqual(@as(usize, 0), plan_same.changedKeys().len);
    try std.testing.expectEqual(@as(usize, 0), plan_same.changed_bytes);

    var set_b_entries: [2]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var changed_b: [2]ResourceKey = undefined;
    const plan_b = try renderer.planResourceUpload(&prepared_a, &set_b, &changed_b);
    try std.testing.expect(plan_b.upload_bytes > 0);
    try std.testing.expect(plan_b.changed_bytes > 0);
    try std.testing.expectEqual(@as(usize, 1), plan_b.changedKeys().len);
    try std.testing.expect(plan_b.changedKeys()[0].eql(ResourceKey.named("hud_panel")));

    var pending = try renderer.beginResourceUpload(allocator, plan_b);
    defer pending.deinit();
    try std.testing.expectError(error.ResourceUploadBudgetExceeded, pending.record(.{}, .{ .budget_bytes = 0 }));
    try std.testing.expect(!pending.ready(.{}));

    try pending.record(.{}, .{ .budget_bytes = plan_b.upload_bytes });
    try std.testing.expect(pending.ready(.{}));
    var prepared_b = try pending.publish();
    defer prepared_b.deinit();
    try std.testing.expect(prepared_b.stampForKey(.hud_panel) != null);
}

test "pending upload publish waits for external completion marker" {
    const allocator = std.testing.allocator;

    var picture = try testRectPicture(allocator, 0);
    defer picture.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.putPathPicture(.hud_panel, &picture);
    var changed_keys: [2]ResourceKey = undefined;
    const plan = try renderer.planResourceUpload(null, &set, &changed_keys);

    var pending = PendingResourceUpload{
        .renderer = &renderer,
        .plan = plan,
        .allocator = allocator,
        .prepared = try renderer.uploadResourcesBlocking(allocator, &set),
        .external_completion_required = true,
    };
    defer pending.deinit();

    try std.testing.expect(!pending.ready(.{ .ready = false }));
    try std.testing.expectError(error.ResourceUploadNotReady, pending.publish());
    try std.testing.expect(pending.ready(.{ .ready = true }));
    var prepared = try pending.publish();
    defer prepared.deinit();
    try std.testing.expect(prepared.stampForKey(.hud_panel) != null);
}

test "CPU draw uses prepared resource views" {
    const allocator = std.testing.allocator;

    var picture = try testRectPicture(allocator, 0);
    defer picture.deinit();

    const width: u32 = 32;
    const height: u32 = 32;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    @memset(pixels, 0);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = Renderer.initCpu(&cpu);
    defer renderer.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addPathPicture(&picture);

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.putPathPicture(.panel, &picture);
    var prepared = try renderer.uploadResourcesBlocking(allocator, &set);
    defer prepared.deinit();

    const draw_options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height },
    };
    const needed = DrawList.estimate(&scene, draw_options);
    const needed_segments = DrawList.estimateSegments(&scene, draw_options);
    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments = try allocator.alloc(DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, draw_options);
    try renderer.draw(&prepared, draw.slice(), draw_options);

    var changed = false;
    for (pixels) |byte| {
        if (byte != 0) {
            changed = true;
            break;
        }
    }
    try std.testing.expect(changed);
}

test "vector path band count tracks source cubic commands" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    const filled = try path.cloneFilledCurves(std.testing.allocator);
    defer std.testing.allocator.free(filled);

    try std.testing.expect(filled.len > 2);
    try std.testing.expectEqual(@as(usize, 2), path.filledBandCurveCount());
}

test "path picture band heuristic uses source segment count for cubic fills" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .color = .{ 0.8, 0.2, 0.1, 1.0 } }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    const info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.v_band_count);
}

test "path picture layers use direct local curve encoding" {
    var body = Path.init(std.testing.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28.0, .y = 155.0 });
    try body.cubicTo(.{ .x = 62.0, .y = 132.0 }, .{ .x = 106.0, .y = 121.0 }, .{ .x = 142.0, .y = 127.0 });
    try body.cubicTo(.{ .x = 179.0, .y = 133.0 }, .{ .x = 210.0, .y = 151.0 }, .{ .x = 246.0, .y = 151.0 });
    try body.cubicTo(.{ .x = 288.0, .y = 151.0 }, .{ .x = 317.0, .y = 145.0 }, .{ .x = 332.0, .y = 131.0 });
    try body.cubicTo(.{ .x = 346.0, .y = 119.0 }, .{ .x = 345.0, .y = 104.0 }, .{ .x = 327.0, .y = 100.0 });
    try body.cubicTo(.{ .x = 307.0, .y = 96.0 }, .{ .x = 286.0, .y = 105.0 }, .{ .x = 278.0, .y = 119.0 });
    try body.cubicTo(.{ .x = 269.0, .y = 132.0 }, .{ .x = 252.0, .y = 136.0 }, .{ .x = 233.0, .y = 132.0 });
    try body.cubicTo(.{ .x = 210.0, .y = 126.0 }, .{ .x = 189.0, .y = 105.0 }, .{ .x = 166.0, .y = 92.0 });
    try body.cubicTo(.{ .x = 142.0, .y = 79.0 }, .{ .x = 106.0, .y = 84.0 }, .{ .x = 82.0, .y = 106.0 });
    try body.cubicTo(.{ .x = 58.0, .y = 127.0 }, .{ .x = 42.0, .y = 149.0 }, .{ .x = 28.0, .y = 155.0 });
    try body.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(&body, .{ .paint = .{ .linear_gradient = .{
        .start = .{ .x = 48.0, .y = 102.0 },
        .end = .{ .x = 320.0, .y = 158.0 },
        .start_color = .{ 0.90, 0.87, 0.78, 0.98 },
        .end_color = .{ 0.58, 0.66, 0.57, 0.98 },
    } } }, .{
        .color = .{ 0.92, 0.92, 0.86, 0.42 },
        .width = 2.0,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    const fill_info = picture.atlas.getGlyph(picture.instances[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.instances[0].glyph_id + 1) orelse return error.TestExpectedEqual;
    try std.testing.expect(fill_info.band_entry.h_band_count > 0);
    try std.testing.expect(stroke_info.band_entry.h_band_count > 0);
    try std.testing.expectEqual(
        curve_tex.f32ToF16(curve_tex.DIRECT_ENCODING_KIND_BIAS),
        picture.atlas.page(0).curve_data[10],
    );
}

test "path picture freeze compiles atlas and transformed batch vertices" {
    var path = Path.init(std.testing.allocator);
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

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &picture.atlas };
    try std.testing.expectEqual(@as(usize, 1), batch.addPicture(&view, &picture));
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), batch.slice().len);
    // Verify that the min corner world position equals the intended translation.
    const s = vertex_mod.decodeInstance(batch.slice());
    const world_x = s.xform[0] * s.rect[0] + s.xform[1] * s.rect[1] + s.origin[0];
    const world_y = s.xform[2] * s.rect[0] + s.xform[3] * s.rect[1] + s.origin[1];
    try std.testing.expectApproxEqAbs(@as(f32, 20), world_x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 30), world_y, 0.5);
    const packed_gw = s.glyph[1];
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.band[3], 0.001);
}

test "path batch offsets layer info rows through atlas views" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .color = .{ 0.4, 0.7, 0.9, 1.0 } }, .identity);

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const offset_view = PreparedAtlasView{
        .atlas = &picture.atlas,
        .layer_base = 3,
        .info_row_base = 17,
    };
    try std.testing.expectEqual(@as(usize, 1), try batch.addPicture(&offset_view, &picture));
    const s = vertex_mod.decodeInstance(batch.slice());
    const packed_gz = s.glyph[0];
    try std.testing.expectEqual(@as(u32, picture.instances[0].info_x), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, offset_view.info_row_base + picture.instances[0].info_y), packed_gz >> 16);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(try textureLayerLocal(offset_view.glyphLayer(0)))), s.band[3], 0.001);
}

test "styled path builder emits fill and stroke records" {
    var path = Path.init(std.testing.allocator);
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
    try std.testing.expectApproxEqAbs(kPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), lid[0], 0.001);
    try std.testing.expectApproxEqAbs(kPaintTagSolid, lid[7], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), lid[12], 0.001);
    try std.testing.expectApproxEqAbs(kPaintTagSolid, lid[31], 0.001);
}

test "open stroked path expands for round caps" {
    var path = Path.init(std.testing.allocator);
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
    try std.testing.expectApproxEqAbs(@as(f32, -9), stroke_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 9), stroke_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -3), stroke_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 3), stroke_info.bbox.max.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 6), picture.instances[0].transform.tx, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 0), picture.instances[0].transform.ty, 0.05);
}

test "square-capped stroked path extends beyond endpoints" {
    var path = Path.init(std.testing.allocator);
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
    var path = Path.init(std.testing.allocator);
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

test "quadratic stroked eye stalk contains its centerline midpoint" {
    const cases = [_]struct {
        start: Vec2,
        control: Vec2,
        end: Vec2,
    }{
        .{
            .start = .{ .x = 308.0, .y = 100.0 },
            .control = .{ .x = 316.0, .y = 76.0 },
            .end = .{ .x = 334.0, .y = 58.0 },
        },
        .{
            .start = .{ .x = 294.0, .y = 102.0 },
            .control = .{ .x = 298.0, .y = 80.0 },
            .end = .{ .x = 306.0, .y = 64.0 },
        },
    };

    for (cases) |case| {
        var path = Path.init(std.testing.allocator);
        defer path.deinit();
        try path.moveTo(case.start);
        try path.quadTo(case.control, case.end);

        const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
            .width = 4.0,
            .cap = .round,
            .join = .round,
        })) orelse return error.TestExpectedEqual;
        defer std.testing.allocator.free(stroke_geom.curves);

        const quads = try std.testing.allocator.alloc(bezier.QuadBezier, stroke_geom.curves.len);
        defer std.testing.allocator.free(quads);
        for (stroke_geom.curves, 0..) |curve, i| quads[i] = curve.asQuad();

        const midpoint = (bezier.QuadBezier{
            .p0 = case.start,
            .p1 = case.control,
            .p2 = case.end,
        }).evaluate(0.5);
        try std.testing.expect(roots.isInside(quads, midpoint));
    }
}

test "rounded rect corners use exact conic arc segments" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRoundedRect(.{ .x = 0, .y = 0, .w = 200, .h = 200 }, 40);

    try std.testing.expectEqual(@as(usize, 8), path.curves.items.len);
    var line_count: usize = 0;
    var conic_count: usize = 0;
    for (path.curves.items) |curve| {
        switch (curve.kind) {
            .line => line_count += 1,
            .conic => conic_count += 1,
            else => return error.TestExpectedEqual,
        }
    }
    try std.testing.expectEqual(@as(usize, 4), line_count);
    try std.testing.expectEqual(@as(usize, 4), conic_count);
}

test "ellipse quarters use exact conic arc segments" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addEllipse(.{ .x = 0, .y = 0, .w = 100, .h = 60 });

    try std.testing.expectEqual(@as(usize, 4), path.curves.items.len);
    for (path.curves.items) |curve| {
        try std.testing.expectEqual(bezier.CurveKind.conic, curve.kind);
    }
}

test "inside-aligned generic path stroke groups fill and stroke on one instance" {
    var path = Path.init(std.testing.allocator);
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

    try std.testing.expectApproxEqAbs(@as(f32, -20), fill_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -9), fill_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), fill_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 9), fill_info.bbox.max.y, 0.05);
    try std.testing.expect(stroke_info.bbox.min.x < fill_info.bbox.min.x);
    try std.testing.expect(stroke_info.bbox.max.x > fill_info.bbox.max.x);
    try std.testing.expect(stroke_info.bbox.min.y < fill_info.bbox.min.y);
    try std.testing.expect(stroke_info.bbox.max.y > fill_info.bbox.max.y);

    try std.testing.expectApproxEqAbs(@as(f32, -20), picture.instances[0].bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -9), picture.instances[0].bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), picture.instances[0].bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 9), picture.instances[0].bbox.max.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 30), picture.instances[0].transform.tx, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 29), picture.instances[0].transform.ty, 0.05);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPaintTagCompositeGroup, lid[3], 0.001);
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

    try std.testing.expectApproxEqAbs(@as(f32, -20), fill_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -9), fill_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 20), fill_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 9), fill_info.bbox.max.y, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.min.x, stroke_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.min.y, stroke_info.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.max.x, stroke_info.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(fill_info.bbox.max.y, stroke_info.bbox.max.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 30), picture.instances[0].transform.tx, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 29), picture.instances[0].transform.ty, 0.05);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(kPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @intFromEnum(PathCompositeMode.fill_stroke_inside)), lid[1], 0.001);
}

test "path picture records single-layer fill and stroke roles distinctly" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .color = .{ 1, 1, 1, 1 } }, .identity);
    try builder.addStrokedRect(
        .{ .x = 30, .y = 0, .w = 20, .h = 10 },
        .{ .color = .{ 1, 0, 0, 1 }, .width = 2.0, .join = .miter },
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    try std.testing.expectEqual(@as(usize, 2), picture.layer_roles.len);
    try std.testing.expectEqual(PathPicture.LayerRole.fill, picture.layer_roles[0]);
    try std.testing.expectEqual(PathPicture.LayerRole.stroke, picture.layer_roles[1]);
}

test "path picture debug view remaps composite fill and stroke paints by role" {
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
    var debug_picture = try picture.withDebugView(std.testing.allocator, .stroke_mask);
    defer debug_picture.deinit();

    const width = debug_picture.atlas.layer_info_width;
    const lid = debug_picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    const base = pathLayerInfoTexelOffset(width, debug_picture.instances[0].info_x, debug_picture.instances[0].info_y);
    const header = readPathLayerInfoTexel(lid, width, base);
    try std.testing.expectApproxEqAbs(PATH_PAINT_TAG_COMPOSITE_GROUP, header[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @intFromEnum(PathCompositeMode.source_over)), header[1], 0.001);

    const fill_record = readPathLayerInfoTexel(lid, width, base + 1);
    const fill_color = readPathLayerInfoTexel(lid, width, base + 3);
    const stroke_record = readPathLayerInfoTexel(lid, width, base + 1 + PATH_PAINT_TEXELS_PER_RECORD);
    const stroke_color = readPathLayerInfoTexel(lid, width, base + 3 + PATH_PAINT_TEXELS_PER_RECORD);
    try std.testing.expectApproxEqAbs(PATH_PAINT_TAG_SOLID, fill_record[3], 0.001);
    try std.testing.expectApproxEqAbs(PATH_PAINT_TAG_SOLID, stroke_record[3], 0.001);
    try std.testing.expectEqual(PathPicture.LayerRole.fill, debug_picture.layer_roles[0]);
    try std.testing.expectEqual(PathPicture.LayerRole.stroke, debug_picture.layer_roles[1]);
    try std.testing.expect(fill_color[3] < 0.001);
    try std.testing.expect(stroke_color[3] > 0.9);
}

test "path picture bounds overlay builds guides for each instance" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .color = .{ 1, 1, 1, 1 } }, .{ .tx = 30, .ty = 40 });

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();

    var overlay = try picture.buildBoundsOverlay(std.testing.allocator, .{ .stroke_width = 2.0, .origin_size = 4.0 });
    defer overlay.deinit();

    try std.testing.expectEqual(@as(usize, 3), overlay.shapeCount());
    for (overlay.instances) |instance| {
        try std.testing.expectApproxEqAbs(picture.instances[0].transform.tx, instance.transform.tx, 0.05);
        try std.testing.expectApproxEqAbs(picture.instances[0].transform.ty, instance.transform.ty, 0.05);
    }
}

test "path picture freeze stores large coordinates as direct local curves" {
    var absolute_builder = PathPictureBuilder.init(std.testing.allocator);
    defer absolute_builder.deinit();
    try absolute_builder.addRoundedRect(
        .{ .x = 640, .y = 960, .w = 40, .h = 18 },
        .{ .color = .{ 1, 1, 1, 1 } },
        null,
        9.0,
        .identity,
    );
    var absolute_picture = try absolute_builder.freeze(std.testing.allocator);
    defer absolute_picture.deinit();

    var transformed_builder = PathPictureBuilder.init(std.testing.allocator);
    defer transformed_builder.deinit();
    try transformed_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 40, .h = 18 },
        .{ .color = .{ 1, 1, 1, 1 } },
        null,
        9.0,
        .{ .tx = 640, .ty = 960 },
    );
    var transformed_picture = try transformed_builder.freeze(std.testing.allocator);
    defer transformed_picture.deinit();

    const absolute_page = absolute_picture.atlas.page(0);
    const f16ToF32 = struct {
        fn decode(bits: u16) f32 {
            return @as(f32, @floatCast(@as(f16, @bitCast(bits))));
        }
    }.decode;
    try std.testing.expectApproxEqAbs(-11.0, f16ToF32(absolute_page.curve_data[0]), 0.001);
    try std.testing.expectApproxEqAbs(-9.0, f16ToF32(absolute_page.curve_data[1]), 0.001);
    try std.testing.expectApproxEqAbs(0.0, f16ToF32(absolute_page.curve_data[2]), 0.001);
    try std.testing.expectApproxEqAbs(-9.0, f16ToF32(absolute_page.curve_data[3]), 0.001);
    try std.testing.expectApproxEqAbs(11.0, f16ToF32(absolute_page.curve_data[4]), 0.001);
    try std.testing.expectApproxEqAbs(-9.0, f16ToF32(absolute_page.curve_data[5]), 0.001);
    try std.testing.expectEqual(
        curve_tex.f32ToF16(curve_tex.DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(@intFromEnum(bezier.CurveKind.line)))),
        absolute_page.curve_data[10],
    );

    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].bbox.min.x, absolute_picture.instances[0].bbox.min.x, 0.001);
    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].bbox.min.y, absolute_picture.instances[0].bbox.min.y, 0.001);
    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].bbox.max.x, absolute_picture.instances[0].bbox.max.x, 0.001);
    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].bbox.max.y, absolute_picture.instances[0].bbox.max.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 660), absolute_picture.instances[0].transform.tx, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 969), absolute_picture.instances[0].transform.ty, 0.001);
    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].transform.tx, absolute_picture.instances[0].transform.tx, 0.001);
    try std.testing.expectApproxEqAbs(transformed_picture.instances[0].transform.ty, absolute_picture.instances[0].transform.ty, 0.001);
}

test "large rounded rect uses generic curve packing without helper tiling" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 1600, .h = 48 },
        .{ .color = .{ 1, 1, 1, 1 } },
        .{ .color = .{ 0, 0, 0, 1 }, .width = 2.0, .join = .round, .placement = .inside },
        24.0,
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
}

test "large rounded rect center stroke uses generic curve packing without helper tiling" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 1600, .h = 48 },
        .{ .color = .{ 1, 1, 1, 1 } },
        .{ .color = .{ 0, 0, 0, 1 }, .width = 6.0, .join = .round },
        24.0,
        .identity,
    );

    var picture = try builder.freeze(std.testing.allocator);
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
}

test "path picture gradient paint records encode linear and radial paints" {
    var path = Path.init(std.testing.allocator);
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
    try std.testing.expectApproxEqAbs(kPaintTagCompositeGroup, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(kPaintTagLinearGradient, lid[7], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), lid[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PaintExtend.reflect))), lid[24], 0.001);

    const radial_base = @as(usize, (1 + kPaintTexelsPerRecord)) * 4;
    try std.testing.expectApproxEqAbs(kPaintTagRadialGradient, lid[radial_base + 3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), lid[radial_base + 8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), lid[radial_base + 9], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), lid[radial_base + 10], 0.001);
}

test "path picture image paint records keep image metadata" {
    var image = try Image.initSrgba8(std.testing.allocator, 2, 2, &.{
        255, 0,   0,   255,
        0,   255, 0,   255,
        0,   0,   255, 255,
        255, 255, 255, 255,
    });
    defer image.deinit();

    var path = Path.init(std.testing.allocator);
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
    try std.testing.expectApproxEqAbs(@as(f32, 3.25), lid[10], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(ImageFilter.nearest))), lid[15], 0.001);
    // Tint RGB is linearized at pack time for correct image modulation.
    try std.testing.expectApproxEqAbs(PathPictureBuilder.srgbToLinear(0.5), lid[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PaintExtend.repeat))), lid[22], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(PaintExtend.reflect))), lid[23], 0.001);
}

test "Font.lineMetrics forwards parser metrics" {
    const assets = @import("assets");

    var font = try Font.init(assets.noto_sans_regular);
    const metrics = try font.lineMetrics();

    try std.testing.expect(metrics.ascent > 0);
    try std.testing.expect(metrics.descent < 0);
    try std.testing.expect(metrics.line_gap >= 0);
}
