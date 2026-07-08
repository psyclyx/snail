//! Screen-space overlay comparing unhinted vs. `auto_light` text at an
//! adjustable ppem, for eyeballing hinting quality in the interactive demo.
//!
//! Two rows of the same sample string in DejaVu Sans Mono: the top row is
//! plain unhinted glyphs; the bottom row is the resolution-independent light
//! autohint (CPU-baked through the existing hinted pipeline — same warp math
//! the shader path will use, see font/autohint/). Toggle with V; grow/shrink
//! the ppem with G / F. Drawn as its own projection-only pass so it stays put
//! while the world pans/zooms. Modeled on hud.zig, which calls itself the
//! template for exactly this. See [[project_snail]].

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const assets = @import("assets");

const Allocator = std.mem.Allocator;
const ShapedRunCache = helpers.ShapedRunCache;
const UnhintedGlyphCache = helpers.UnhintedGlyphCache;
const warp = snail.autohint.warp;

const sample_text = "Words Слова Λέξεις 0123";

pub const Compare = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    font: *snail.Font,
    faces: snail.Faces,
    font_id: u32,
    auto: snail.autohint.AutoLight,

    shape_cache: ShapedRunCache,
    glyph_cache: UnhintedGlyphCache,
    atlas: snail.Atlas,

    pub fn init(allocator: Allocator, pool: *snail.PagePool) !Compare {
        const font = try allocator.create(snail.Font);
        errdefer allocator.destroy(font);
        font.* = try snail.Font.init(assets.dejavu_sans_mono);

        var faces = try snail.Faces.build(allocator, &.{.{ .font = font }});
        errdefer faces.deinit();
        const font_id = faces.fontIdForFace(0);

        const auto = try snail.autohint.AutoLight.init(allocator, assets.dejavu_sans_mono);

        return .{
            .allocator = allocator,
            .pool = pool,
            .font = font,
            .faces = faces,
            .font_id = font_id,
            .auto = auto,
            .shape_cache = ShapedRunCache.init(allocator),
            .glyph_cache = UnhintedGlyphCache.init(allocator, font),
            .atlas = snail.Atlas.empty(allocator),
        };
    }

    pub fn deinit(self: *Compare) void {
        self.atlas.deinit();
        self.glyph_cache.deinit();
        self.shape_cache.deinit();
        self.auto.deinit();
        self.faces.deinit();
        self.allocator.destroy(self.font);
        self.* = undefined;
    }

    /// Build the two-row comparison picture for one frame at `ppem_px`
    /// (logical pixels). Extends `self.atlas` with any newly needed glyphs.
    pub fn buildPicture(
        self: *Compare,
        frame_alloc: Allocator,
        scratch_alloc: Allocator,
        ppem_px: f32,
        top_y: f32,
    ) !helpers.Picture {
        const em: f32 = @round(@max(ppem_px, 4.0));
        const ppem_26_6: u32 = @intFromFloat(em * 64.0);

        const shaped = try self.shape_cache.shape(&self.faces, sample_text, .{});
        try self.ensureAtlas(scratch_alloc, shaped, ppem_26_6);

        const left: f32 = 24.0;
        // Both rows sit on integer pixel baselines: light hinting only lands
        // features on the grid if the baseline itself is grid-aligned.
        const base_unhinted = @round(top_y);
        const base_auto = @round(top_y + em * 1.6);

        var unhinted = try helpers.shapedRunPicture(frame_alloc, shaped, &self.faces, .{
            .baseline = .{ .x = left, .y = base_unhinted },
            .em = em,
            .color = text_color,
        });
        defer unhinted.deinit();

        // Auto-light row: place each glyph's origin on a whole pixel — x-stems
        // are grid-fit relative to the origin, so a fractional origin throws
        // the sharpening away (the x-axis analogue of baseline snapping).
        //
        // Monospace → one uniform rounded advance, so columns stay aligned
        // (terminal-style). Proportional → snap each glyph's cumulative,
        // KERNING-INCLUDED shaped position (`x_offset` already carries
        // HarfBuzz's kerning); rounding the position rather than each advance
        // means errors don't accumulate down the line.
        const mono_adv = monoAdvancePx(shaped, em);
        const origin_left = @round(left);
        const buf = try frame_alloc.alloc(snail.Shape, shaped.glyphs.len);
        for (shaped.glyphs, 0..) |g, i| {
            const origin_x = if (mono_adv) |adv|
                origin_left + @as(f32, @floatFromInt(i)) * adv
            else
                @round(left + em * g.x_offset);
            buf[i] = .{
                .key = snail.recordKey.hintedGlyph(g.font_id, g.glyph_id, ppem_26_6),
                // Base curves are em-normalised, so scale by em (like the
                // unhinted row); the warp — carried by the atlas record — does
                // the grid-fit at sample time.
                .local_transform = .{ .xx = em, .xy = 0, .tx = origin_x, .yx = 0, .yy = -em, .ty = base_auto },
                .local_color = text_color,
            };
        }
        var auto = helpers.Picture.fromOwnedSlice(frame_alloc, buf);
        defer auto.deinit();

        return helpers.Picture.concat(frame_alloc, &.{ &unhinted, &auto });
    }

    fn ensureAtlas(self: *Compare, scratch: Allocator, shaped: *const snail.ShapedText, ppem_26_6: u32) !void {
        const cap = 128;
        var entries: [cap]snail.AtlasEntry = undefined;
        var n: usize = 0;

        for (shaped.glyphs) |g| {
            if (g.font_id != self.font_id) continue;

            // Shared unhinted base curves (em-space) — both rows sample these.
            const c = try self.glyph_cache.getOrInsert(self.allocator, scratch, g.glyph_id);

            const key_u = snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id);
            if (n < cap and !self.atlas.contains(key_u) and !hasKey(entries[0..n], key_u)) {
                entries[n] = .{ .key = key_u, .curves = c.* };
                n += 1;
            }

            // Auto-light key: same base curves + per-ppem warp knots. The
            // knots live on `scratch`, which outlives the atlas build below
            // (the builder copies them into the layer-info slab).
            const key_a = snail.recordKey.hintedGlyph(g.font_id, g.glyph_id, ppem_26_6);
            if (n < cap and !self.atlas.contains(key_a) and !hasKey(entries[0..n], key_a)) {
                const xk = try scratch.alloc(warp.Knot, warp.max_knots);
                const yk = try scratch.alloc(warp.Knot, warp.max_knots);
                const knots = try self.auto.glyphKnots(scratch, g.glyph_id, ppem_26_6, xk, yk);
                entries[n] = .{
                    .key = key_a,
                    .curves = c.*,
                    .autohint = .{ .x = knots.x, .y = knots.y },
                };
                n += 1;
            }
        }

        if (n == 0) return;
        if (self.atlas.pool == null) {
            const fresh = try snail.Atlas.from(self.allocator, self.pool, entries[0..n]);
            self.atlas.deinit();
            self.atlas = fresh;
            return;
        }
        const grown = try self.atlas.extend(self.allocator, entries[0..n]);
        self.atlas.deinit();
        self.atlas = grown;
    }
};

const text_color = [4]f32{ 0.06, 0.07, 0.09, 1.0 };

/// If every glyph shares one advance (a monospace run), return that advance
/// in whole pixels; else null. Mono fonts don't kern, so a uniform rounded
/// advance keeps columns aligned.
fn monoAdvancePx(shaped: *const snail.ShapedText, em: f32) ?f32 {
    if (shaped.glyphs.len == 0) return null;
    const first = shaped.glyphs[0].x_advance;
    if (first <= 0) return null;
    for (shaped.glyphs[1..]) |g| {
        if (@abs(g.x_advance - first) > 1e-4) return null;
    }
    return @round(first * em);
}

fn hasKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}
