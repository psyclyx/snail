//! Interactive-demo banner content, ported to the new snail API.
//!
//! Builds the full reference banner (title bar, four content cards, two-row
//! primitives card, vector snail card) and returns it as four caller-owned
//! resources: `paths_atlas` + `paths_picture` (every filled/stroked path:
//! card chrome, primitive demos, the snail) and `text_atlas` +
//! `text_picture` (every shaped run). The `PagePool` is caller-owned and
//! is shared across both atlases.
//!
//! Layout and palette are byte-identical to the legacy banner — the new
//! pipeline is purely about how the entries/shapes are constructed.
//! Hinting is opt-in via `HintOptions`: when enabled, every Latin run is
//! ppem-scaled, hinted via `HintVm.hint`, and emitted under
//! `recordKey.hintedGlyph` keys; non-Latin runs fall back to unhinted
//! glyphs. Per-glyph paint (gradient wordmarks, image-painted "image"
//! word) goes through the path namespace with `mapPaintToLocal` baking
//! the world paint into glyph-local coordinates, the same trick
//! `content.zig` uses for its wordmark.

const std = @import("std");
const snail = @import("snail");
const banner_snail = @import("banner_snail.zig");
const assets_data = @import("assets");

const Allocator = std.mem.Allocator;

pub const addVectorSnail = banner_snail.addVectorSnail;

// ── Reference canvas ──

const REF_W: f32 = 1680;
const REF_H: f32 = 874;

// ── Palette (light theme) ──

const bg = [4]f32{ 0.96, 0.965, 0.975, 1.0 };
const text_color = [4]f32{ 0.10, 0.10, 0.14, 1.0 };
const muted = [4]f32{ 0.42, 0.46, 0.52, 1.0 };
const accent = [4]f32{ 0.15, 0.38, 0.85, 1.0 };
const surface = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
const border = [4]f32{ 0.84, 0.86, 0.89, 1.0 };

// ── Layout ──

pub const Layout = struct {
    scale: f32,
    canvas: snail.Rect,
    title: snail.Rect,
    styles: snail.Rect,
    decorations: snail.Rect,
    shaping: snail.Rect,
    scripts: snail.Rect,
    vectors: snail.Rect,
    snail_stage: snail.Rect,
};

pub fn buildLayout(w: f32, h: f32) Layout {
    const scale = @min(w / REF_W, h / REF_H);
    const margin = 48 * scale;
    const col_gap = 28 * scale;
    const row_gap = 24 * scale;

    const cx = (w - REF_W * scale) * 0.5;
    const cy = (h - REF_H * scale) * 0.5;

    // Title row
    const title_h = 100 * scale;
    const title = snail.Rect{ .x = cx + margin, .y = cy + margin, .w = REF_W * scale - margin * 2, .h = title_h };

    // Content row: 4 columns
    const content_top = title.y + title.h + row_gap;
    const content_w = REF_W * scale - margin * 2;
    const col_w = (content_w - col_gap * 3) / 4;
    const content_h = 300 * scale;

    const col_x = cx + margin;
    const styles = snail.Rect{ .x = col_x, .y = content_top, .w = col_w, .h = content_h };
    const decorations = snail.Rect{ .x = col_x + col_w + col_gap, .y = content_top, .w = col_w, .h = content_h };
    const shaping = snail.Rect{ .x = col_x + (col_w + col_gap) * 2, .y = content_top, .w = col_w, .h = content_h };
    const scripts = snail.Rect{ .x = col_x + (col_w + col_gap) * 3, .y = content_top, .w = col_w, .h = content_h };

    // Vectors row
    const vectors_top = content_top + content_h + row_gap;
    const vectors_h = REF_H * scale - (vectors_top - cy) - margin;
    const vectors_w = content_w * 0.55;
    const vectors = snail.Rect{ .x = col_x, .y = vectors_top, .w = vectors_w, .h = vectors_h };

    const snail_stage = snail.Rect{
        .x = col_x + vectors_w + col_gap,
        .y = vectors_top,
        .w = content_w - vectors_w - col_gap,
        .h = vectors_h,
    };

    return .{
        .scale = scale,
        .canvas = .{ .x = cx, .y = cy, .w = REF_W * scale, .h = REF_H * scale },
        .title = title,
        .styles = styles,
        .decorations = decorations,
        .shaping = shaping,
        .scripts = scripts,
        .vectors = vectors,
        .snail_stage = snail_stage,
    };
}

pub fn clearColor() [4]f32 {
    return bg;
}

// ── Shared sizing constants (must match between text + vector helpers) ──

const card_pad = 20;
const heading_size = 15;
const sub_heading_size = 13;
const body_text_size = 22;
const body_line_h = 28;
const shape_sz = 56;
const shape_gap = 14;

// ── Public API ──

pub const HintOptions = struct {
    enabled: bool = false,
    /// Scales the font-size em to a hinter ppem. Legacy banner used 1.0;
    /// pass values >1.0 for super-sampled hinting.
    ppem_scale: f32 = 1.0,
};

/// Built banner ready for upload + emit. Atlases, pictures, and the
/// decoration-rect slice are owned by this value. Call `deinit` to release
/// them. The `PagePool` is caller-owned and is *not* released here; it's
/// exposed so backend drivers can size their prepared-pages caches against
/// the same pool the atlases live in.
pub const Content = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    paths_atlas: snail.Atlas,
    text_atlas: snail.Atlas,
    paths_picture: snail.Picture,
    text_picture: snail.Picture,
    layout: Layout,
    decoration_rects: []snail.Rect,
    missing: bool,

    pub fn deinit(self: *Content) void {
        self.text_picture.deinit();
        self.paths_picture.deinit();
        self.text_atlas.deinit();
        self.paths_atlas.deinit();
        if (self.decoration_rects.len > 0) self.allocator.free(self.decoration_rects);
        self.* = undefined;
    }
};

/// Long-lived fonts/shaper/paint-image used to drive `build`. Build once
/// (init), call `build` per frame as layout changes, then `deinit` at
/// shutdown. The shaper allocator and font datas come from `assets`.
pub const Assets = struct {
    allocator: Allocator,
    shaper: snail.Shaper,
    fonts: [font_count]snail.Font,
    paint_image: snail.Image,
    /// Whether face 0 has a hinter attached on `shaper`. The actual
    /// `HintVm` lives inside the Shaper (so HB and the demo render path
    /// share one VM/cache). `false` means hinting wasn't available for
    /// this font and the build falls through to unhinted glyphs.
    has_regular_hinter: bool,

    pub const face_count: usize = 10;
    pub const font_count: usize = 7;

    /// Logical-face → font index (into `fonts`). The shaper carries 10
    /// faces (regular/bold/italic/bold-italic/semi-bold/arabic/devanagari/
    /// symbols/thai/emoji); the underlying `Font` set deduplicates back to
    /// 6 (regular, bold, arabic, devanagari, symbols, thai, emoji+symbols)
    /// by reusing regular for italic and bold for bold-italic, since the
    /// italic faces are synthetic-skew-only.
    pub const face_to_font_id = [face_count]u32{ 0, 1, 0, 1, 0, 2, 3, 4, 5, 6 };

    pub fn init(allocator: Allocator) !Assets {
        var shaper = try snail.Shaper.init(allocator, &.{
            .{ .data = assets_data.noto_sans_regular },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold },
            .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_regular, .weight = .semi_bold, .synthetic = .{ .embolden = 0.5 } },
            .{ .data = assets_data.noto_sans_arabic, .fallback = true },
            .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
            .{ .data = assets_data.noto_sans_symbols, .fallback = true },
            .{ .data = assets_data.noto_sans_thai, .fallback = true },
            .{ .data = assets_data.twemoji_mozilla, .fallback = true },
        });
        errdefer shaper.deinit();

        var fonts: [font_count]snail.Font = undefined;
        const datas = [_][]const u8{
            assets_data.noto_sans_regular,
            assets_data.noto_sans_bold,
            assets_data.noto_sans_arabic,
            assets_data.noto_sans_devanagari,
            assets_data.noto_sans_symbols,
            assets_data.noto_sans_thai,
            assets_data.twemoji_mozilla,
        };
        for (datas, 0..) |data, i| {
            fonts[i] = try snail.Font.init(data);
        }

        const paint_image = try initPaintImage(allocator);
        errdefer {
            var img = paint_image;
            img.deinit();
        }

        // Only the regular (italic-source) face gets a hinter today; the
        // other faces are either bold (no hint program differences worth
        // wiring in this demo) or fallback scripts. The Shaper now owns
        // the HintVm so HB's `glyph_h_advance` font_func can route
        // through it during shape, and the render path picks the same
        // instance up via `shaper.hinterForFace(0)` for glyph extraction.
        var has_regular_hinter = false;
        shaper.attachHinter(0) catch {};
        if (shaper.hinterForFace(0) != null) has_regular_hinter = true;

        return .{
            .allocator = allocator,
            .shaper = shaper,
            .fonts = fonts,
            .paint_image = paint_image,
            .has_regular_hinter = has_regular_hinter,
        };
    }

    pub fn deinit(self: *Assets) void {
        self.paint_image.deinit();
        self.shaper.deinit();
        self.* = undefined;
    }

    /// COLR fanout helper: the shaper's fallback faces (arabic..emoji)
    /// reuse their underlying `Font`, so this lookup is identical to
    /// `face_to_font_id` aside from being typed as `*const Font`.
    pub fn colrFontsTable(self: *const Assets) [face_count]*const snail.Font {
        return .{
            &self.fonts[0],
            &self.fonts[1],
            &self.fonts[0],
            &self.fonts[1],
            &self.fonts[0],
            &self.fonts[2],
            &self.fonts[3],
            &self.fonts[4],
            &self.fonts[5],
            &self.fonts[6],
        };
    }

    fn font(self: *const Assets, face_index: u32) *const snail.Font {
        const tbl = face_to_font_id;
        return &self.fonts[tbl[@as(usize, face_index)]];
    }
};

fn initPaintImage(allocator: Allocator) !snail.Image {
    var pixels: [16 * 16 * 4]u8 = undefined;
    const colors = [_][4]u8{
        .{ 36, 92, 220, 255 },
        .{ 242, 88, 142, 255 },
        .{ 255, 210, 80, 255 },
        .{ 40, 176, 132, 255 },
    };
    for (0..16) |py| {
        for (0..16) |px| {
            const diagonal = ((px + py) / 4) % 2;
            const quadrant = @as(usize, @intFromBool(px >= 8)) + @as(usize, @intFromBool(py >= 8)) * 2;
            const color = colors[(quadrant + diagonal) % colors.len];
            const i = (py * 16 + px) * 4;
            pixels[i + 0] = color[0];
            pixels[i + 1] = color[1];
            pixels[i + 2] = color[2];
            pixels[i + 3] = color[3];
        }
    }
    return snail.Image.initSrgba8(allocator, 16, 16, &pixels);
}

// ── Build entry point ──

/// Build the banner content. `assets` and `pool` are caller-owned and must
/// outlive the returned `Content`. `snap_step` is the half-pixel-step used
/// for text snapping; pass `.{ .x = 1, .y = 1 }` for "no snap".
pub fn build(
    allocator: Allocator,
    pool: *snail.PagePool,
    assets: *Assets,
    width: f32,
    height: f32,
    snap_step: snail.Vec2,
    hint_opts: HintOptions,
) !Content {
    const layout = buildLayout(width, height);

    var builder = try BannerBuilder.init(allocator, assets, &layout, snap_step, hint_opts);
    defer builder.deinit();

    // ── Text pass: shape every run, populate text-atlas entries, collect
    //    decoration rects, and gather (separately) any gradient/image-painted
    //    text glyphs into `painted_text_entries`/`painted_text_shapes`.
    try builder.buildTextPass();

    // ── Path pass: background, cards, decorations, vector shapes, snail.
    //    Appends to path_entries/path_shapes.
    try builder.buildPathPass();

    // ── Splice the painted-text glyphs onto the END of the path arrays so
    //    they render on TOP of the cards. Atlas keys were assigned during
    //    the text pass; they're still unique within path_entries.
    try builder.path_entries.appendSlice(builder.allocator, builder.painted_text_entries.items);
    try builder.path_shapes.appendSlice(builder.allocator, builder.painted_text_shapes.items);

    // ── Seal atlases ──
    var paths_atlas = try snail.Atlas.from(allocator, pool, builder.path_entries.items);
    errdefer paths_atlas.deinit();
    var text_atlas = try snail.Atlas.from(allocator, pool, builder.text_entries.items);
    errdefer text_atlas.deinit();

    // ── Combine pictures ──
    var paths_picture = try snail.Picture.from(allocator, builder.path_shapes.items);
    errdefer paths_picture.deinit();
    var text_picture = try snail.Picture.from(allocator, builder.text_shapes.items);
    errdefer text_picture.deinit();

    const decoration_rects = try builder.takeDecorationRects();

    return .{
        .allocator = allocator,
        .pool = pool,
        .paths_atlas = paths_atlas,
        .text_atlas = text_atlas,
        .paths_picture = paths_picture,
        .text_picture = text_picture,
        .layout = layout,
        .decoration_rects = decoration_rects,
        .missing = builder.missing,
    };
}

// ── Internal builder ──

const BannerBuilder = struct {
    allocator: Allocator,
    assets: *Assets,
    layout: *const Layout,
    snap_step: snail.Vec2,
    hint_opts: HintOptions,

    /// Per-font glyph caches. `snail.font.GlyphCache` is keyed by glyph_id
    /// only and has no font identifier, so sharing a single cache across
    /// fonts returns the wrong outline for any glyph_id that exists in
    /// multiple fonts. Indexed by `Assets.fonts` index (i.e. font_id).
    glyph_caches: [Assets.font_count]snail.font.GlyphCache,

    // Path-namespace entries (cards, decorations, primitives, snail).
    path_curves_owned: std.ArrayList(snail.GlyphCurves),
    path_entries: std.ArrayList(snail.AtlasEntry),
    path_shapes: std.ArrayList(snail.Shape),
    extra_layer_storage: std.ArrayList([]snail.AtlasLayer),
    next_path_id: u32,

    // Gradient / image-painted text glyph entries. Collected during the text
    // pass but spliced onto the end of `path_entries`/`path_shapes` after the
    // path pass so they render ON TOP of the card backgrounds.
    painted_text_entries: std.ArrayList(snail.AtlasEntry),
    painted_text_shapes: std.ArrayList(snail.Shape),

    // Text-namespace entries (regular + COLR + hinted glyph curves).
    text_curves_owned: std.ArrayList(snail.GlyphCurves),
    text_entries: std.ArrayList(snail.AtlasEntry),
    text_shapes: std.ArrayList(snail.Shape),

    // Decoration underlines / strikethroughs, collected during text pass
    // and emitted as filled rects in the path pass.
    decoration_rects: std.ArrayList(snail.Rect),
    missing: bool,

    /// Per-build arena reused across `pathToCurves` / `strokeToCurves`
    /// calls. Resets after each producer call so intermediate buffers
    /// collapse to bump-pointer ops.
    scratch_arena: std.heap.ArenaAllocator,

    fn init(
        allocator: Allocator,
        assets: *Assets,
        layout: *const Layout,
        snap_step: snail.Vec2,
        hint_opts: HintOptions,
    ) !BannerBuilder {
        var glyph_caches: [Assets.font_count]snail.font.GlyphCache = undefined;
        for (&glyph_caches) |*c| c.* = snail.font.GlyphCache.init(allocator);
        return .{
            .allocator = allocator,
            .assets = assets,
            .layout = layout,
            .snap_step = snap_step,
            .hint_opts = hint_opts,
            .glyph_caches = glyph_caches,
            .path_curves_owned = .empty,
            .path_entries = .empty,
            .path_shapes = .empty,
            .extra_layer_storage = .empty,
            .next_path_id = 0,
            .text_curves_owned = .empty,
            .text_entries = .empty,
            .text_shapes = .empty,
            .painted_text_entries = .empty,
            .painted_text_shapes = .empty,
            .decoration_rects = .empty,
            .missing = false,
            .scratch_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    fn deinit(self: *BannerBuilder) void {
        for (self.path_curves_owned.items) |*c| c.deinit();
        self.path_curves_owned.deinit(self.allocator);
        self.path_entries.deinit(self.allocator);
        self.path_shapes.deinit(self.allocator);
        for (self.extra_layer_storage.items) |s| self.allocator.free(s);
        self.extra_layer_storage.deinit(self.allocator);

        for (self.text_curves_owned.items) |*c| c.deinit();
        self.text_curves_owned.deinit(self.allocator);
        self.text_entries.deinit(self.allocator);
        self.text_shapes.deinit(self.allocator);
        self.painted_text_entries.deinit(self.allocator);
        self.painted_text_shapes.deinit(self.allocator);

        self.decoration_rects.deinit(self.allocator);
        for (&self.glyph_caches) |*c| c.deinit();
        self.scratch_arena.deinit();
    }

    fn snailBuilder(self: *BannerBuilder) banner_snail.Builder {
        return .{
            .allocator = self.allocator,
            .scratch_arena = &self.scratch_arena,
            .owned_curves = &self.path_curves_owned,
            .entries = &self.path_entries,
            .shapes = &self.path_shapes,
            .extra_layer_storage = &self.extra_layer_storage,
            .next_id = &self.next_path_id,
        };
    }

    fn takeDecorationRects(self: *BannerBuilder) ![]snail.Rect {
        return self.decoration_rects.toOwnedSlice(self.allocator);
    }

    // ── Path pass ──

    fn buildPathPass(self: *BannerBuilder) !void {
        const sb = self.snailBuilder();
        const s = self.layout.scale;
        const r = 10 * s;
        const stroke_w = 1.0 * s;
        const card_stroke = snail.StrokeStyle{
            .paint = .{ .solid = border },
            .width = stroke_w,
            .join = .round,
            .placement = .inside,
        };

        // Background
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRect(self.layout.canvas);
            try sb.addFilledPath(&p, .{ .solid = bg }, .identity);
        }

        // Card backgrounds (rounded fill + inside stroke composite)
        try addRoundedCard(sb, self.layout.styles, .{ .solid = surface }, card_stroke, r);
        try addRoundedCard(sb, self.layout.decorations, .{ .solid = surface }, card_stroke, r);
        try addRoundedCard(sb, self.layout.shaping, .{ .solid = surface }, card_stroke, r);
        try addRoundedCard(sb, self.layout.scripts, .{ .solid = surface }, card_stroke, r);
        try addRoundedCard(sb, self.layout.vectors, .{ .solid = surface }, card_stroke, r);
        try addRoundedCard(sb, self.layout.snail_stage, .{ .solid = surface }, card_stroke, r);

        // Decoration rects (underline / strikethrough) collected by text pass.
        for (self.decoration_rects.items) |rect| {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRect(rect);
            try sb.addFilledPath(&p, .{ .solid = text_color }, .identity);
        }

        // Vector shape demos
        try self.addVectorShapes(sb);

        // The snail illustration
        try banner_snail.addVectorSnail(sb, self.layout.snail_stage);
    }

    fn addVectorShapes(self: *BannerBuilder, sb: banner_snail.Builder) !void {
        const s = self.layout.scale;
        const pad = card_pad * s;
        const sz = shape_sz * s;
        const gap = shape_gap * s;
        const x0 = self.layout.vectors.x + pad;
        const stroke_w = 2 * s;
        const paint_image = &self.assets.paint_image;

        // Y positions must match drawText's Vectors label layout.
        const shapes_y = self.layout.vectors.y + pad + heading_size * s + 14 * s + sub_heading_size * s + 6 * s;

        // ── Row 1: Shapes ──

        // Rect
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRect(.{ .x = x0, .y = shapes_y, .w = sz, .h = sz });
            try sb.addPathFillAndStroke(&p, .{ .solid = .{ 0.22, 0.50, 0.88, 1.0 } }, .{
                .paint = .{ .solid = .{ 0.15, 0.38, 0.72, 1.0 } },
                .width = stroke_w,
                .join = .miter,
                .placement = .inside,
            }, .identity);
        }

        // Rounded rect
        const rrx = x0 + sz + gap;
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRoundedRect(.{ .x = rrx, .y = shapes_y, .w = sz, .h = sz }, 12 * s);
            try sb.addPathFillAndStroke(&p, .{ .solid = .{ 0.92, 0.82, 0.48, 1.0 } }, .{
                .paint = .{ .solid = .{ 0.78, 0.62, 0.22, 1.0 } },
                .width = stroke_w,
                .join = .round,
                .placement = .inside,
            }, .identity);
        }

        // Ellipse
        const elx = x0 + (sz + gap) * 2;
        try sb.addEllipse(.{ .x = elx, .y = shapes_y, .w = sz, .h = sz }, .{ .solid = .{ 0.85, 0.52, 0.35, 1.0 } }, .{
            .paint = .{ .solid = .{ 0.72, 0.38, 0.22, 1.0 } },
            .width = stroke_w,
            .join = .round,
            .placement = .inside,
        }, .identity);

        // Custom path (leaf/diamond shape)
        const plx = x0 + (sz + gap) * 3;
        {
            var path = snail.paths.Path.init(sb.allocator);
            defer path.deinit();
            try path.moveTo(.{ .x = plx + sz * 0.5, .y = shapes_y });
            try path.cubicTo(
                .{ .x = plx + sz * 0.95, .y = shapes_y + sz * 0.2 },
                .{ .x = plx + sz * 0.95, .y = shapes_y + sz * 0.8 },
                .{ .x = plx + sz * 0.5, .y = shapes_y + sz },
            );
            try path.cubicTo(
                .{ .x = plx + sz * 0.05, .y = shapes_y + sz * 0.8 },
                .{ .x = plx + sz * 0.05, .y = shapes_y + sz * 0.2 },
                .{ .x = plx + sz * 0.5, .y = shapes_y },
            );
            try path.close();
            try sb.addPathFillAndStroke(&path, .{ .solid = .{ 0.58, 0.48, 0.82, 1.0 } }, .{
                .paint = .{ .solid = .{ 0.42, 0.32, 0.68, 1.0 } },
                .width = stroke_w,
                .join = .round,
                .placement = .inside,
            }, .identity);
        }

        // ── Row 2: Fills ──
        const fills_y = shapes_y + sz + 11 * s + 6 * s + sub_heading_size * s + 6 * s;

        // Solid fill
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRoundedRect(.{ .x = x0, .y = fills_y, .w = sz, .h = sz }, 6 * s);
            try sb.addFilledPath(&p, .{ .solid = .{ 0.35, 0.72, 0.55, 1.0 } }, .identity);
        }

        // Linear gradient
        const lgx = x0 + sz + gap;
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRoundedRect(.{ .x = lgx, .y = fills_y, .w = sz, .h = sz }, 6 * s);
            try sb.addFilledPath(&p, .{ .linear_gradient = .{
                .start = .{ .x = lgx, .y = fills_y },
                .end = .{ .x = lgx + sz, .y = fills_y + sz },
                .start_color = .{ 0.25, 0.55, 0.95, 1.0 },
                .end_color = .{ 0.85, 0.30, 0.55, 1.0 },
            } }, .identity);
        }

        // Radial gradient
        const rgx = x0 + (sz + gap) * 2;
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRoundedRect(.{ .x = rgx, .y = fills_y, .w = sz, .h = sz }, 6 * s);
            try sb.addFilledPath(&p, .{ .radial_gradient = .{
                .center = .{ .x = rgx + sz * 0.45, .y = fills_y + sz * 0.4 },
                .radius = sz * 0.55,
                .inner_color = .{ 0.98, 0.90, 0.55, 1.0 },
                .outer_color = .{ 0.88, 0.42, 0.18, 1.0 },
            } }, .identity);
        }

        // Image fill
        const imx = x0 + (sz + gap) * 3;
        const image_period = sz;
        {
            var p = snail.paths.Path.init(sb.allocator);
            defer p.deinit();
            try p.addRoundedRect(.{ .x = imx, .y = fills_y, .w = sz, .h = sz }, 6 * s);
            try sb.addFilledPath(&p, .{ .image = .{
                .image = paint_image,
                .uv_transform = .{
                    .xx = 1.0 / image_period,
                    .yy = 1.0 / image_period,
                    .tx = -imx / image_period,
                    .ty = -fills_y / image_period,
                },
                .filter = .nearest,
            } }, .identity);
        }

        // Stroke-only path (in shapes row, last cell)
        const stx = x0 + (sz + gap) * 4;
        {
            var stroke_path = snail.paths.Path.init(sb.allocator);
            defer stroke_path.deinit();
            try stroke_path.moveTo(.{ .x = stx + 4 * s, .y = shapes_y + sz * 0.7 });
            try stroke_path.cubicTo(
                .{ .x = stx + sz * 0.3, .y = shapes_y - sz * 0.1 },
                .{ .x = stx + sz * 0.7, .y = shapes_y + sz * 1.1 },
                .{ .x = stx + sz - 4 * s, .y = shapes_y + sz * 0.3 },
            );
            try sb.addStrokedPath(&stroke_path, .{
                .paint = .{ .solid = .{ 0.22, 0.55, 0.80, 1.0 } },
                .width = 4 * s,
                .cap = .round,
                .join = .round,
            }, .identity);
        }
    }

    // ── Text pass ──

    fn buildTextPass(self: *BannerBuilder) !void {
        const s = self.layout.scale;
        const pad = card_pad * s;
        const label_size = heading_size * s;
        const sub_label_size = sub_heading_size * s;
        const body_size = body_text_size * s;
        const line_h = body_line_h * s;

        // ── Title ──
        const layout = self.layout;
        const title_grad = snail.Paint{ .linear_gradient = .{
            .start = .{ .x = layout.title.x, .y = layout.title.y },
            .end = .{ .x = layout.title.x + 190 * s, .y = layout.title.y + 72 * s },
            .start_color = accent,
            .end_color = text_color,
        } };
        _ = try self.addPaintedText(.{ .weight = .bold }, "snail", layout.title.x, layout.title.y + 58 * s, 64 * s, title_grad);
        _ = try self.addText(.{}, "GPU text & vector rendering", layout.title.x + 210 * s, layout.title.y + 50 * s, 20 * s, muted);

        // ── Styles card ──
        {
            const x = layout.styles.x + pad;
            var y = layout.styles.y + pad;
            _ = try self.addText(.{ .weight = .bold }, "Styles", x, y + label_size, label_size, accent);
            y += label_size + 14 * s;

            _ = try self.addText(.{}, "Regular", x, y + body_size, body_size, text_color);
            y += line_h;
            _ = try self.addText(.{ .weight = .bold }, "Bold", x, y + body_size, body_size, text_color);
            y += line_h;
            _ = try self.addText(.{ .italic = true }, "Italic", x, y + body_size, body_size, text_color);
            y += line_h;
            _ = try self.addText(.{ .weight = .bold, .italic = true }, "Bold Italic", x, y + body_size, body_size, text_color);
            y += line_h;
            _ = try self.addText(.{ .weight = .semi_bold }, "Synthetic", x, y + body_size, body_size, text_color);
            y += line_h + 8 * s;

            _ = try self.addText(.{}, "Mixed styles", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;

            var rx = x;
            const mixed_baseline = y + body_size;
            rx += (try self.addText(.{ .weight = .bold }, "Bold ", rx, mixed_baseline, body_size, text_color)).advance_x;
            rx += (try self.addPaintedText(.{ .weight = .bold }, "gradient", rx, mixed_baseline, body_size, .{ .linear_gradient = .{
                .start = .{ .x = rx, .y = mixed_baseline - body_size },
                .end = .{ .x = rx + 92 * s, .y = mixed_baseline },
                .start_color = .{ 0.18, 0.50, 0.88, 1.0 },
                .end_color = .{ 0.88, 0.30, 0.56, 1.0 },
            } })).advance_x;
            _ = try self.addText(.{}, " / small", rx, mixed_baseline, 14 * s, muted);
            y += line_h + 4 * s;

            // Size ramp
            const sizes = [_]f32{ 10, 14, 18, 24, 32 };
            var sx = x;
            for (sizes) |sz| {
                const fs = sz * s;
                sx += (try self.addText(.{}, "Aa", sx, y + 32 * s, fs, muted)).advance_x + 12 * s;
            }
        }

        // ── Decorations card ──
        {
            const x = layout.decorations.x + pad;
            var y = layout.decorations.y + pad;
            _ = try self.addText(.{ .weight = .bold }, "Decorations", x, y + label_size, label_size, accent);
            y += label_size + 14 * s;

            // Underlined
            const ul_place = self.place(x, y + body_size, body_size);
            const ul = try self.addPaintedTextAt(.{}, "Underlined", ul_place, .{ .solid = text_color });
            try self.appendDecoration(.underline, .{}, ul_place.x, ul_place.y, ul.advance_x, ul_place.size);
            y += line_h;

            // Struck
            const st_place = self.place(x, y + body_size, body_size);
            const st = try self.addPaintedTextAt(.{}, "Struck", st_place, .{ .solid = text_color });
            try self.appendDecoration(.strikethrough, .{}, st_place.x, st_place.y, st.advance_x, st_place.size);
            y += line_h + 16 * s;

            // CH₅⁺ + C₂H₆ → C₂H₇⁺ + CH₄
            const sub_size = body_size * 1.2;
            const sub_y = y + sub_size;
            var cx_ = x;

            cx_ += (try self.addText(.{}, "CH", cx_, sub_y, sub_size, text_color)).advance_x;
            cx_ += try self.addSubscriptDigit(.{}, "5", cx_, sub_y, sub_size, text_color);
            cx_ += try self.addSuperscriptDigit(.{}, "+", cx_, sub_y, sub_size, text_color);

            cx_ += (try self.addText(.{}, " + ", cx_, sub_y, sub_size, text_color)).advance_x;

            cx_ += (try self.addText(.{}, "C", cx_, sub_y, sub_size, text_color)).advance_x;
            cx_ += try self.addSubscriptDigit(.{}, "2", cx_, sub_y, sub_size, text_color);
            cx_ += (try self.addText(.{}, "H", cx_, sub_y, sub_size, text_color)).advance_x;
            cx_ += try self.addSubscriptDigit(.{}, "6", cx_, sub_y, sub_size, text_color);

            {
                const r = try self.addText(.{}, " \u{2192} ", cx_, sub_y, sub_size, text_color);
                cx_ += r.advance_x;
                if (r.missing) self.missing = true;
            }

            cx_ += (try self.addText(.{}, "C", cx_, sub_y, sub_size, text_color)).advance_x;
            cx_ += try self.addSubscriptDigit(.{}, "2", cx_, sub_y, sub_size, text_color);
            cx_ += (try self.addText(.{}, "H", cx_, sub_y, sub_size, text_color)).advance_x;
            cx_ += try self.addSubscriptDigit(.{}, "7", cx_, sub_y, sub_size, text_color);
            cx_ += try self.addSuperscriptDigit(.{}, "+", cx_, sub_y, sub_size, text_color);

            cx_ += (try self.addText(.{}, " + ", cx_, sub_y, sub_size, text_color)).advance_x;

            cx_ += (try self.addText(.{}, "CH", cx_, sub_y, sub_size, text_color)).advance_x;
            _ = try self.addSubscriptDigit(.{}, "4", cx_, sub_y, sub_size, text_color);
        }

        // ── Shaping card ──
        {
            const x = layout.shaping.x + pad;
            var y = layout.shaping.y + pad;
            _ = try self.addText(.{ .weight = .bold }, "Shaping", x, y + label_size, label_size, accent);
            y += label_size + 14 * s;

            _ = try self.addText(.{}, "Ligatures", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            _ = try self.addText(.{}, "office ffi fl ffl", x, y + body_size, body_size, text_color);
            y += line_h + 16 * s;

            _ = try self.addText(.{}, "Kerning", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            _ = try self.addText(.{}, "AV To VA Ty", x, y + body_size, body_size, text_color);
            y += line_h + 16 * s;

            _ = try self.addText(.{}, "Sphinx of black", x, y + 18 * s, 16 * s, muted);
            y += 22 * s;
            _ = try self.addText(.{}, "quartz, judge", x, y + 18 * s, 16 * s, muted);
            y += 22 * s;
            _ = try self.addText(.{}, "my vow.", x, y + 18 * s, 16 * s, muted);
        }

        // ── Scripts card ──
        {
            const x = layout.scripts.x + pad;
            var y = layout.scripts.y + pad;
            _ = try self.addText(.{ .weight = .bold }, "Scripts", x, y + label_size, label_size, accent);
            y += label_size + 14 * s;

            const script_size = 18 * s;
            const script_line = 24 * s;

            _ = try self.addText(.{}, "Latin", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            _ = try self.addText(.{}, "Hello, world!", x, y + script_size, script_size, text_color);
            y += script_line + 4 * s;

            _ = try self.addText(.{}, "Arabic", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            if ((try self.addText(.{}, "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7", x, y + script_size, script_size, text_color)).missing) self.missing = true;
            y += script_line + 4 * s;

            _ = try self.addText(.{}, "Devanagari", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            if ((try self.addText(.{}, "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87", x, y + script_size, script_size, text_color)).missing) self.missing = true;
            y += script_line + 4 * s;

            _ = try self.addText(.{}, "Thai", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            if ((try self.addText(.{}, "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5", x, y + script_size, script_size, text_color)).missing) self.missing = true;
            y += script_line + 4 * s;

            _ = try self.addText(.{}, "Emoji", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;
            if ((try self.addText(.{}, "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88", x, y + script_size, script_size, text_color)).missing) self.missing = true;
        }

        // ── Vectors card labels ──
        {
            const x = layout.vectors.x + pad;
            var y = layout.vectors.y + pad;
            const sz = shape_sz * s;
            const gap = shape_gap * s;
            const item_label = 11 * s;

            _ = try self.addText(.{ .weight = .bold }, "Primitives", x, y + label_size, label_size, accent);
            y += label_size + 14 * s;

            _ = try self.addText(.{}, "Shapes", x, y + sub_label_size, sub_label_size, muted);
            y += sub_label_size + 6 * s;

            const shape_label_y = y + sz + 2 * s;
            var lx = x;
            const shape_labels = [_][]const u8{ "rect", "round", "ellipse", "path", "stroke" };
            for (shape_labels) |lbl| {
                _ = try self.addText(.{}, lbl, lx, shape_label_y + item_label, item_label, muted);
                lx += sz + gap;
            }

            const fills_label_y = shape_label_y + item_label + 6 * s;
            _ = try self.addText(.{}, "Fills", x, fills_label_y + sub_label_size, sub_label_size, muted);

            const fill_shapes_y = fills_label_y + sub_label_size + 6 * s;
            const fill_label_y = fill_shapes_y + sz + 2 * s;
            lx = x;
            const fill_labels = [_][]const u8{ "solid", "linear", "radial", "image" };
            for (fill_labels) |lbl| {
                _ = try self.addText(.{}, lbl, lx, fill_label_y + item_label, item_label, muted);
                lx += sz + gap;
            }

            const text_paint_label_y = fill_label_y + item_label + 14 * s;
            _ = try self.addText(.{}, "Text paint", x, text_paint_label_y + sub_label_size, sub_label_size, muted);
            const paint_text_size = 26 * s;
            const paint_text_y = text_paint_label_y + sub_label_size + 8 * s;
            const gradient_baseline = paint_text_y + paint_text_size;
            const gradient_advance = (try self.addPaintedText(.{ .weight = .bold }, "gradient", x, gradient_baseline, paint_text_size, .{ .linear_gradient = .{
                .start = .{ .x = x, .y = gradient_baseline - paint_text_size },
                .end = .{ .x = x + 132 * s, .y = gradient_baseline },
                .start_color = .{ 0.18, 0.50, 0.88, 1.0 },
                .end_color = .{ 0.88, 0.30, 0.56, 1.0 },
            } })).advance_x;

            const image_x = x + gradient_advance + 34 * s;
            const image_period = 30 * s;
            _ = try self.addPaintedText(.{ .weight = .bold }, "image", image_x, gradient_baseline, paint_text_size, .{ .image = .{
                .image = &self.assets.paint_image,
                .uv_transform = .{
                    .xx = 1.0 / image_period,
                    .yy = 1.0 / image_period,
                    .tx = -image_x / image_period,
                    .ty = -(gradient_baseline - paint_text_size) / image_period,
                },
                .extend_x = .repeat,
                .extend_y = .repeat,
                .filter = .nearest,
            } });
        }
    }

    // ── Text placement helpers ──

    const Placement = struct { x: f32, y: f32, size: f32 };

    const RunResult = struct {
        advance_x: f32,
        missing: bool,
    };

    fn place(self: *BannerBuilder, x: f32, y: f32, size: f32) Placement {
        const point = snail.snapPointToStep(.{ .x = x, .y = y }, self.snap_step, .nearest);
        return .{
            .x = point.x,
            .y = point.y,
            .size = snail.snapLengthToStep(size, self.snap_step.y, .nearest, 1.0),
        };
    }

    fn addText(
        self: *BannerBuilder,
        style: snail.FontStyle,
        string: []const u8,
        x: f32,
        y: f32,
        size: f32,
        color: [4]f32,
    ) !RunResult {
        return self.addPaintedText(style, string, x, y, size, .{ .solid = color });
    }

    fn addPaintedText(
        self: *BannerBuilder,
        style: snail.FontStyle,
        string: []const u8,
        x: f32,
        y: f32,
        size: f32,
        paint: snail.Paint,
    ) !RunResult {
        return self.addPaintedTextAt(style, string, self.place(x, y, size), paint);
    }

    /// Shape `string` at `placement` and emit it. Solid paints try the
    /// hinted path when hinting is enabled and the run lands on a hinted
    /// face; gradient / image paints always take the path-namespace
    /// per-glyph route (via `mapPaintToLocal`).
    fn addPaintedTextAt(
        self: *BannerBuilder,
        style: snail.FontStyle,
        string: []const u8,
        placement: Placement,
        paint: snail.Paint,
    ) !RunResult {
        // When hinting is on we shape with `target_ppem` so HB queries the
        // attached TT hinter for `glyph_h_advance` (face 0 only). Other
        // faces fall through to em-scale advances. Either way the
        // returned `ShapedText` is em-space — the hinted path bakes in
        // hint quantization that `placement.size * advance` recovers as
        // exact 26.6 pixel positions.
        const target_ppem: ?snail.HintPpem = if (self.hint_opts.enabled) blk: {
            const ppem_26_6 = hintPpem26_6(placement.size, self.hint_opts.ppem_scale) catch break :blk null;
            break :blk snail.HintPpem.uniform(ppem_26_6);
        } else null;
        var shaped = try self.assets.shaper.shapeOpts(self.allocator, style, string, .{
            .target_ppem = target_ppem,
        });
        defer shaped.deinit();

        var missing_in_run = false;
        for (shaped.glyphs) |g| {
            if (g.glyph_id == 0) missing_in_run = true;
        }

        const advance_x = placement.size * shaped.advanceX();

        switch (paint) {
            .solid => |color| {
                if (self.hint_opts.enabled and self.allRunGlyphsHintable(&shaped)) {
                    if (try self.tryEmitHintedRun(&shaped, placement, color)) {
                        return .{ .advance_x = advance_x, .missing = missing_in_run };
                    }
                }
                try self.emitShapedRunSolid(&shaped, placement, color);
            },
            else => {
                try self.emitShapedRunPaint(&shaped, placement, paint);
            },
        }

        return .{ .advance_x = advance_x, .missing = missing_in_run };
    }

    /// Subscript helper: shape the digit at the post-table subscript metrics
    /// for the current font (face 0). Returns the digit's advance, or the
    /// fallback path's advance when metrics aren't available.
    fn addSubscriptDigit(
        self: *BannerBuilder,
        style: snail.FontStyle,
        digit: []const u8,
        x: f32,
        baseline_y: f32,
        body_size: f32,
        color: [4]f32,
    ) !f32 {
        if (self.scriptPlacement(.sub, x, baseline_y, body_size)) |sp| {
            const r = try self.addText(style, digit, sp.x, sp.y, sp.size, color);
            return r.advance_x;
        } else |_| {
            const r = try self.addText(style, digit, x, baseline_y, body_size * 0.7, color);
            return r.advance_x;
        }
    }

    fn addSuperscriptDigit(
        self: *BannerBuilder,
        style: snail.FontStyle,
        digit: []const u8,
        x: f32,
        baseline_y: f32,
        body_size: f32,
        color: [4]f32,
    ) !f32 {
        if (self.scriptPlacement(.sup, x, baseline_y, body_size)) |sp| {
            const r = try self.addText(style, digit, sp.x, sp.y, sp.size, color);
            return r.advance_x;
        } else |_| {
            const r = try self.addText(style, digit, x, baseline_y - body_size * 0.4, body_size * 0.7, color);
            return r.advance_x;
        }
    }

    const ScriptKind = enum { sub, sup };

    /// Compute the placement for a sub- or superscript digit at the given
    /// baseline. Uses the regular face's OS/2 metrics; this is the same
    /// font that the legacy `TextAtlas.subscriptTransform` consulted.
    fn scriptPlacement(self: *BannerBuilder, kind: ScriptKind, x: f32, baseline_y: f32, body_size: f32) !Placement {
        const font_ref = &self.assets.fonts[0];
        const upem: f32 = @floatFromInt(font_ref.unitsPerEm());
        const em_scale = body_size / upem;
        const metrics = switch (kind) {
            .sub => try font_ref.subscriptMetrics(),
            .sup => try font_ref.superscriptMetrics(),
        };
        const sub_size: f32 = @as(f32, @floatFromInt(metrics.y_size)) * em_scale;
        const offset_y: f32 = @as(f32, @floatFromInt(metrics.y_offset)) * em_scale;
        const offset_x: f32 = @as(f32, @floatFromInt(metrics.x_offset)) * em_scale;
        const placed_y = switch (kind) {
            .sub => baseline_y + offset_y,
            .sup => baseline_y - offset_y,
        };
        return .{ .x = x + offset_x, .y = placed_y, .size = sub_size };
    }

    const DecorationKind = enum { underline, strikethrough };

    fn appendDecoration(
        self: *BannerBuilder,
        kind: DecorationKind,
        style: snail.FontStyle,
        baseline_x: f32,
        baseline_y: f32,
        advance: f32,
        em_size: f32,
    ) !void {
        _ = style;
        // Use the regular face metrics (decoration text is rendered with the
        // regular style in the layout). Matches legacy behavior, which read
        // metrics off the resolved face for each glyph but ended up using
        // the Latin face for both decorated samples.
        const font_ref = &self.assets.fonts[0];
        const upem: f32 = @floatFromInt(font_ref.unitsPerEm());
        const em_scale = em_size / upem;
        const dm = try font_ref.decorationMetrics();
        const rect = switch (kind) {
            .underline => snail.Rect{
                .x = baseline_x,
                .y = baseline_y - @as(f32, @floatFromInt(dm.underline_position)) * em_scale,
                .w = advance,
                .h = @as(f32, @floatFromInt(dm.underline_thickness)) * em_scale,
            },
            .strikethrough => snail.Rect{
                .x = baseline_x,
                .y = baseline_y - (@as(f32, @floatFromInt(dm.strikethrough_position)) + @as(f32, @floatFromInt(dm.strikethrough_thickness)) * 0.5) * em_scale,
                .w = advance,
                .h = @as(f32, @floatFromInt(dm.strikethrough_thickness)) * em_scale,
            },
        };
        try self.decoration_rects.append(self.allocator, rect);
    }

    // ── Emit machinery ──

    fn allRunGlyphsHintable(self: *const BannerBuilder, shaped: *const snail.ShapedText) bool {
        // We only have a hinter for face 0 today; if every glyph in the run
        // is from face 0 we can take the hinted path. Otherwise fall back
        // to unhinted (synthetic / fallback / emoji faces don't hint).
        if (!self.assets.has_regular_hinter) return false;
        for (shaped.glyphs) |g| {
            if (g.face_index != 0) return false;
        }
        return true;
    }

    /// Solid-color shaped run: insert each glyph's curves under
    /// `unhintedGlyph(font_id, glyph_id)` keys (with COLR fanout for color
    /// fonts) and emit one shape per glyph via `shapedRunPicture`.
    fn emitShapedRunSolid(
        self: *BannerBuilder,
        shaped: *const snail.ShapedText,
        placement: Placement,
        color: [4]f32,
    ) !void {
        try self.ensureUnhintedGlyphCurves(shaped);

        const colr_fonts = self.assets.colrFontsTable();
        var picture = try snail.shapedRunPicture(self.allocator, shaped, .{
            .baseline = .{ .x = placement.x, .y = placement.y },
            .em = placement.size,
            .color = color,
            .face_to_font_id = &Assets.face_to_font_id,
            .colr_fonts = &colr_fonts,
        });
        defer picture.deinit();
        try self.text_shapes.appendSlice(self.allocator, picture.shapes);
    }

    fn emitShapedRunPaint(
        self: *BannerBuilder,
        shaped: *const snail.ShapedText,
        placement: Placement,
        paint: snail.Paint,
    ) !void {
        // Gradient / image-painted runs need per-glyph paint baked into
        // local glyph coordinates, so each glyph becomes a one-off
        // path-namespace entry rather than going through the deduplicated
        // text atlas. Mirrors `content.zig`'s wordmark approach.
        for (shaped.glyphs) |g| {
            const face_index: u32 = g.face_index;
            const fid: u32 = Assets.face_to_font_id[@as(usize, face_index)];
            const font_ref = &self.assets.fonts[fid];
            const pen_x = placement.x + placement.size * g.x_offset;
            const pen_y = placement.y + placement.size * g.y_offset;
            const transform = snail.Transform2D{
                .xx = placement.size,
                .xy = 0,
                .tx = pen_x,
                .yx = 0,
                .yy = -placement.size,
                .ty = pen_y,
            };
            const local_paint = snail.mapPaintToLocal(paint, transform) orelse continue;

            const curves = try font_ref.extractCurves(self.allocator, self.scratch_arena.allocator(), &self.glyph_caches[fid], g.glyph_id);
            _ = self.scratch_arena.reset(.retain_capacity);
            try self.path_curves_owned.append(self.allocator, curves);

            const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = self.next_path_id };
            self.next_path_id += 1;
            try self.painted_text_entries.append(self.allocator, .{
                .key = key,
                .curves = self.path_curves_owned.items[self.path_curves_owned.items.len - 1],
                .paint = local_paint,
            });
            try self.painted_text_shapes.append(self.allocator, .{
                .key = key,
                .local_transform = transform,
                .local_color = .{ 1, 1, 1, 1 },
            });
        }
    }

    /// Attempt to emit the run with hinted glyph keys. Returns `true` on
    /// success, `false` if any glyph failed to hint (in which case the
    /// caller falls back to the unhinted path).
    fn tryEmitHintedRun(
        self: *BannerBuilder,
        shaped: *const snail.ShapedText,
        placement: Placement,
        color: [4]f32,
    ) !bool {
        const hinter = self.assets.shaper.hinterForFace(0) orelse return false;
        const ppem_26_6 = hintPpem26_6(placement.size, self.hint_opts.ppem_scale) catch return false;
        const ppem = snail.HintPpem.uniform(ppem_26_6);

        // Hint and insert curves for every glyph in the run before emitting
        // shapes, so a mid-run failure leaves the atlas state clean.
        for (shaped.glyphs) |g| {
            const key = snail.recordKey.hintedGlyph(0, g.glyph_id, ppem_26_6);
            if (containsKey(self.text_entries.items, key)) continue;
            const curves = hinter.hintGlyph(self.allocator, self.scratch_arena.allocator(), g.glyph_id, ppem) catch return false;
            _ = self.scratch_arena.reset(.retain_capacity);
            try self.text_curves_owned.append(self.allocator, curves);
            try self.text_entries.append(self.allocator, .{
                .key = key,
                .curves = self.text_curves_owned.items[self.text_curves_owned.items.len - 1],
            });
        }

        var picture = try snail.hintedShapedRunPicture(self.allocator, shaped, .{
            .baseline = .{ .x = placement.x, .y = placement.y },
            .em = placement.size,
            .ppem_26_6 = ppem_26_6,
            .color = color,
            .face_to_font_id = &Assets.face_to_font_id,
        });
        defer picture.deinit();
        try self.text_shapes.appendSlice(self.allocator, picture.shapes);
        return true;
    }

    fn ensureUnhintedGlyphCurves(self: *BannerBuilder, shaped: *const snail.ShapedText) !void {
        for (shaped.glyphs) |g| {
            const face_index: u32 = g.face_index;
            const fid: u32 = Assets.face_to_font_id[@as(usize, face_index)];
            const font_ref = &self.assets.fonts[fid];
            const cache = &self.glyph_caches[fid];
            var iter = font_ref.colrLayers(g.glyph_id);
            if (iter.count() > 0) {
                while (iter.next()) |layer| {
                    const layer_key = snail.recordKey.unhintedGlyph(fid, layer.glyph_id);
                    if (containsKey(self.text_entries.items, layer_key)) continue;
                    const curves = try font_ref.extractCurves(self.allocator, self.scratch_arena.allocator(), cache, layer.glyph_id);
                    _ = self.scratch_arena.reset(.retain_capacity);
                    try self.text_curves_owned.append(self.allocator, curves);
                    try self.text_entries.append(self.allocator, .{
                        .key = layer_key,
                        .curves = self.text_curves_owned.items[self.text_curves_owned.items.len - 1],
                    });
                }
            }
            const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
            if (containsKey(self.text_entries.items, key)) continue;
            const curves = try font_ref.extractCurves(self.allocator, self.scratch_arena.allocator(), cache, g.glyph_id);
            _ = self.scratch_arena.reset(.retain_capacity);
            try self.text_curves_owned.append(self.allocator, curves);
            try self.text_entries.append(self.allocator, .{
                .key = key,
                .curves = self.text_curves_owned.items[self.text_curves_owned.items.len - 1],
            });
        }
    }
};

// ── Tiny helpers ──

fn addRoundedCard(
    builder: banner_snail.Builder,
    rect: snail.Rect,
    fill: snail.Paint,
    stroke: snail.StrokeStyle,
    radius: f32,
) !void {
    var p = snail.paths.Path.init(builder.allocator);
    defer p.deinit();
    try p.addRoundedRect(rect, radius);
    try builder.addPathFillAndStroke(&p, fill, stroke, .identity);
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

fn hintPpem26_6(font_size: f32, ppem_scale: f32) !u32 {
    const ppem = font_size * ppem_scale;
    if (!std.math.isFinite(ppem) or ppem < 1.0) return error.HintUnavailable;
    return @intFromFloat(@round(@min(ppem, 4096.0) * 64.0));
}
