//! All-in-one hinting validation overlay for the interactive demo.
//!
//! Renders the same sample string in three hinting modes — unhinted,
//! `auto_light` (this project's resolution-independent warp), and the font's
//! built-in TrueType hinting — stacked across a spread of ppems. Lets you
//! eyeball auto_light against the TrueType gold standard and the unhinted
//! baseline at every size in one glance. Toggle with V. Drawn as a
//! projection-only pass so it stays put while the world pans/zooms.

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const assets = @import("assets");

const Allocator = std.mem.Allocator;
const ShapedRunCache = helpers.ShapedRunCache;
const UnhintedGlyphCache = helpers.UnhintedGlyphCache;
const warp = snail.autohint.warp;

const sample_text = "Hamburg Λέξεις 0123";
const grid_ppems = [_]f32{ 9, 10, 11, 12, 13, 14, 16, 18, 22, 28 };

/// Distinguishes the auto-light record key from the TrueType key (both use
/// the hinted-glyph namespace, so auto flips this high bit).
const auto_key_bit: u32 = 0x4000_0000;

const Mode = enum { unhinted, auto, tt };
const modes = [_]Mode{ .unhinted, .auto, .tt };

fn modeTag(m: Mode) []const u8 {
    return switch (m) {
        .unhinted => "un",
        .auto => "au",
        .tt => "tt",
    };
}

pub const Compare = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    font: *snail.Font,
    faces: snail.Faces,
    font_id: u32,
    auto: snail.autohint.AutoLight,
    /// The font's own TrueType hinting, if it has any (DejaVu does).
    tt: ?snail.HintVm,

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
        const tt = snail.HintVm.init(allocator, font) catch null;

        return .{
            .allocator = allocator,
            .pool = pool,
            .font = font,
            .faces = faces,
            .font_id = font_id,
            .auto = auto,
            .tt = tt,
            .shape_cache = ShapedRunCache.init(allocator),
            .glyph_cache = UnhintedGlyphCache.init(allocator, font),
            .atlas = snail.Atlas.empty(allocator),
        };
    }

    pub fn deinit(self: *Compare) void {
        self.atlas.deinit();
        if (self.tt) |*vm| vm.deinit();
        self.glyph_cache.deinit();
        self.shape_cache.deinit();
        self.auto.deinit();
        self.faces.deinit();
        self.allocator.destroy(self.font);
        self.* = undefined;
    }

    /// Device pixels per grid pixel. Hinting is a device-pixel operation:
    /// grid ppems are logical sizes, but the warp must grid-fit to the real
    /// framebuffer the GPU writes to, and glyphs must land on integer DEVICE
    /// pens or the stems smear. On a fractional-scale HiDPI display, integer
    /// logical pens map to fractional device pixels (52→78 but 69→103.5 at
    /// 1.5×), which is exactly the "glyphs after the first sit on partial
    /// boundaries" artefact. Pass `framebuffer_h / logical_h`; the caller then
    /// draws this pass with a device-pixel projection.
    fn devEm(ppem: f32, px_scale: f32) f32 {
        return @round(ppem * px_scale);
    }

    /// Build the full validation grid in DEVICE pixels (see `px_scale`).
    /// `scratch` must outlive the atlas build (the builder copies knots/curves
    /// in). Returns the picture; `self.atlas` is extended with everything it
    /// references. Draw the resulting pass with an `ortho(0, fb_w, fb_h, 0)`
    /// projection so device coordinates map 1:1 to framebuffer pixels.
    pub fn buildGrid(self: *Compare, frame_alloc: Allocator, scratch: Allocator, px_scale: f32) !helpers.Picture {
        const shaped = try self.shape_cache.shape(&self.faces, sample_text, .{});

        // Tag glyphs render unhinted at a fixed size; sample glyphs render per
        // (ppem, mode). Ensure everything the grid references in one pass.
        const tags = try self.shape_cache.shape(&self.faces, "unautt", .{});
        try self.ensureAll(scratch, shaped, tags, px_scale);

        var refs: std.ArrayList(*const helpers.Picture) = .empty;
        const left_tag: f32 = 8 * px_scale;
        const left_sample: f32 = 52 * px_scale;
        const tag_em: f32 = 12 * px_scale;

        var y: f32 = 26 * px_scale;
        for (grid_ppems) |ppem| {
            const em: f32 = devEm(ppem, px_scale);
            const ppem_26_6: u32 = @intFromFloat(em * 64.0);
            for (modes) |mode| {
                const baseline = @round(y) + em;
                // Mode tag (fixed-size, unhinted).
                const tag_shaped = try self.shape_cache.shape(&self.faces, modeTag(mode), .{});
                const tag = try frame_alloc.create(helpers.Picture);
                tag.* = try helpers.shapedRunPicture(frame_alloc, tag_shaped, &self.faces, .{
                    .baseline = .{ .x = left_tag, .y = @round(y) + tag_em },
                    .em = tag_em,
                    .color = tag_color,
                });
                try refs.append(frame_alloc, tag);
                // The sample in this mode.
                const row = try frame_alloc.create(helpers.Picture);
                row.* = try self.renderRow(frame_alloc, shaped, mode, ppem_26_6, em, left_sample, baseline);
                try refs.append(frame_alloc, row);
                y += em * 1.32 + 3 * px_scale;
            }
            y += 9 * px_scale;
        }
        return helpers.Picture.concat(frame_alloc, refs.items);
    }

    fn renderRow(
        self: *Compare,
        frame_alloc: Allocator,
        shaped: *const snail.ShapedText,
        mode: Mode,
        ppem_26_6: u32,
        em: f32,
        left: f32,
        baseline: f32,
    ) !helpers.Picture {
        switch (mode) {
            .unhinted => return helpers.shapedRunPicture(frame_alloc, shaped, &self.faces, .{
                .baseline = .{ .x = left, .y = baseline },
                .em = em,
                .color = text_color,
            }),
            // Both hinted modes place glyphs at INTEGER pens (mono → uniform
            // rounded advance) so grid-fit stems land on the pixel grid. This
            // matters for tt too: the TrueType outline is grid-fit assuming an
            // integer origin, so a fractional pen smears the crispness — the
            // same reason auto_light snaps origins. They differ only in the
            // record key and the curve space: auto's base curves are em-space
            // (scale = em); tt's baked curves are ppem-px space (scale =
            // em/ppem_px).
            .auto => return self.placeMonoRow(frame_alloc, shaped, .auto, ppem_26_6, em, em, left, baseline),
            .tt => {
                const ppem_px = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
                const scale = if (ppem_px > 0) em / ppem_px else em;
                return self.placeMonoRow(frame_alloc, shaped, .tt, ppem_26_6, em, scale, left, baseline);
            },
        }
    }

    /// Place a hinted row at rounded integer pens. `scale` is the local
    /// transform's uniform scale (curve-space → world); `mode` selects the
    /// record key namespace.
    fn placeMonoRow(
        self: *Compare,
        frame_alloc: Allocator,
        shaped: *const snail.ShapedText,
        mode: Mode,
        ppem_26_6: u32,
        em: f32,
        scale: f32,
        left: f32,
        baseline: f32,
    ) !helpers.Picture {
        _ = self;
        const mono_adv = monoAdvancePx(shaped, em);
        const origin_left = @round(left);
        const buf = try frame_alloc.alloc(snail.Shape, shaped.glyphs.len);
        for (shaped.glyphs, 0..) |g, i| {
            const origin_x = if (mono_adv) |adv|
                origin_left + @as(f32, @floatFromInt(i)) * adv
            else
                @round(left + em * g.x_offset);
            const key = switch (mode) {
                .auto => autoKey(g.font_id, g.glyph_id, ppem_26_6),
                .tt => snail.recordKey.hintedGlyph(g.font_id, g.glyph_id, ppem_26_6),
                .unhinted => unreachable,
            };
            buf[i] = .{
                .key = key,
                .local_transform = .{ .xx = scale, .xy = 0, .tx = origin_x, .yx = 0, .yy = -scale, .ty = baseline },
                .local_color = text_color,
            };
        }
        return helpers.Picture.fromOwnedSlice(frame_alloc, buf);
    }

    /// Ensure the atlas holds: unhinted curves for the tag + sample glyphs
    /// (ppem-independent), plus auto-light records and TrueType-baked curves
    /// for every (sample glyph, ppem). Knots/TT curves live on `scratch`; the
    /// atlas copies them during `extend`.
    fn ensureAll(self: *Compare, scratch: Allocator, shaped: *const snail.ShapedText, tags: *const snail.ShapedText, px_scale: f32) !void {
        var entries: std.ArrayList(snail.AtlasEntry) = .empty;
        defer entries.deinit(scratch);

        // Unhinted (shared) — sample + tag glyphs.
        for ([_]*const snail.ShapedText{ shaped, tags }) |run| {
            for (run.glyphs) |g| {
                if (g.font_id != self.font_id) continue;
                const key = snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id);
                if (self.atlas.contains(key) or hasKey(entries.items, key)) continue;
                const c = try self.glyph_cache.getOrInsert(self.allocator, scratch, g.glyph_id);
                try entries.append(scratch, .{ .key = key, .curves = c.* });
            }
        }

        // Per-ppem auto + TrueType. Device ppem must match buildGrid's keys.
        for (grid_ppems) |ppem| {
            const ppem_26_6: u32 = @intFromFloat(devEm(ppem, px_scale) * 64.0);
            for (shaped.glyphs) |g| {
                if (g.font_id != self.font_id) continue;

                const key_a = autoKey(g.font_id, g.glyph_id, ppem_26_6);
                if (!self.atlas.contains(key_a) and !hasKey(entries.items, key_a)) {
                    const xk = try scratch.alloc(warp.Knot, warp.max_knots);
                    const yk = try scratch.alloc(warp.Knot, warp.max_knots);
                    const knots = try self.auto.glyphKnots(scratch, g.glyph_id, ppem_26_6, xk, yk);
                    // Alias the shared unhinted base (inserted above / already
                    // in the atlas) — every ppem warps the one base copy.
                    try entries.append(scratch, .{
                        .key = key_a,
                        .curves = snail.GlyphCurves.empty(scratch),
                        .autohint = .{ .x = knots.x, .y = knots.y },
                        .autohint_base = snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id),
                    });
                }

                if (self.tt) |*vm| {
                    const key_t = snail.recordKey.hintedGlyph(g.font_id, g.glyph_id, ppem_26_6);
                    if (!self.atlas.contains(key_t) and !hasKey(entries.items, key_t)) {
                        // Output on `scratch` (persists to the atlas build); VM
                        // internals on a dedicated temp arena so they can't
                        // alias the output. On failure, register an empty record
                        // so the TT row still resolves rather than MissingRecord.
                        var tmp = std.heap.ArenaAllocator.init(self.allocator);
                        defer tmp.deinit();
                        const hint_ppem = snail.HintPpem.uniform(ppem_26_6);
                        const curves = vm.hintGlyph(scratch, tmp.allocator(), g.glyph_id, hint_ppem) catch blk: {
                            // snail's TT VM can throw mid-execution on some
                            // glyphs (e.g. DejaVu '2' -> StackUnderflow), which
                            // leaves the per-ppem machine corrupted. Evict it so
                            // later glyphs at this size get a fresh machine.
                            vm.evictPpem(hint_ppem);
                            break :blk snail.GlyphCurves.empty(scratch);
                        };
                        try entries.append(scratch, .{ .key = key_t, .curves = curves });
                    }
                }
            }
        }

        if (entries.items.len == 0) return;
        if (self.atlas.pool == null) {
            const fresh = try snail.Atlas.from(self.allocator, self.pool, entries.items);
            self.atlas.deinit();
            self.atlas = fresh;
        } else {
            const grown = try self.atlas.extend(self.allocator, entries.items);
            self.atlas.deinit();
            self.atlas = grown;
        }
    }
};

fn autoKey(font_id: u32, glyph_id: u16, ppem_26_6: u32) snail.RecordKey {
    return snail.recordKey.hintedGlyph(font_id, glyph_id, ppem_26_6 | auto_key_bit);
}

const text_color = [4]f32{ 0.06, 0.07, 0.09, 1.0 };
const tag_color = [4]f32{ 0.45, 0.48, 0.55, 1.0 };

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
