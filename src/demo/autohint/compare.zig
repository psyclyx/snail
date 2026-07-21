//! All-in-one hinting validation overlay for the interactive demo.
//!
//! Renders the same sample string in five hinting modes — unhinted, explicit
//! y-only, natural-width x/y, full-width x/y, and the font's built-in TT
//! hinting — stacked across a spread of ppems. Lets you compare both composable policies
//! against the TT-hint reference and unhinted baseline in one glance. Toggle
//! with V. Drawn as a
//! projection-only pass so it stays put while the world pans/zooms.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");
const assets = @import("assets");

const Allocator = std.mem.Allocator;
const ShapedRunCache = demo_support.ShapedRunCache;
const UnhintedGlyphCache = snail.UnhintedGlyphCache;
const warp = snail.autohint.warp;
const testing = std.testing;

// Chosen for hinting coverage: `Hamburg` (classic type tester — even `m` legs,
// `b`/`g` ascender/descender, arches), `wove` (round bowls `o`/`e` for
// blue-zone/overshoot + diagonals `w`/`v` that must NOT be x-stem-hinted),
// `Λόγος` (real Greek word "logos" — diagonal `Λ`, round `ο`, descender `γ`,
// final sigma `ς`), and digits. Sized to fit the (widened) grid cell.
pub const sample_text = "Hamburg wove Λόγος 0123";
pub const grid_ppems = [_]f32{ 9, 10, 11, 12, 13, 14, 16, 18, 22, 28 };
/// Shared by the interactive V overlay and its headless screenshot. The grid
/// ends at about 1210 logical pixels, so the default viewport leaves margin.
pub const default_viewport_height: u32 = 1700;

const grid_top: f32 = 26;
const row_leading: f32 = 1.32;
const row_gap: f32 = 3;
const ppem_gap: f32 = 9;
/// Height of the per-section "<n>px" size header above each ppem block.
const section_head: f32 = 15;

pub fn gridHeightPx(px_scale: f32) f32 {
    var y = grid_top * px_scale;
    for (grid_ppems) |ppem| {
        const em = Compare.devEm(ppem, px_scale);
        y += section_head * px_scale;
        y += rows.len * (em * row_leading + row_gap * px_scale);
        y += ppem_gap * px_scale;
    }
    return y;
}

/// Demo choices, deliberately not library presets.
///
/// All of them fade the warp to identity between 16 and 26 px — autohinting is a
/// small-size tool, and above ~26px analytic AA already renders stems and curves
/// cleanly (forcing the grid there flattens round tops and blobs serif corners).
/// The fade is caller-owned policy now; the library bakes in no threshold.
pub const demo_fade: snail.autohint.Fade = .{ .ppem_range = .{ .start_px = 16, .full_px = 26 } };

pub const y_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .none,
        .stem_width = .natural,
        .positioning = .independent,
        .registration = .none,
    },
    .y = .{
        .@"align" = .blue_zones,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.0 } },
        .overshoot = .{ .suppress_below_px = 0.5 },
    },
    .fade = demo_fade,
};

/// Cross-font/light x policy: align vertical stems but preserve their analyzed
/// widths. This avoids forcing near-pixel strokes wider in fonts such as Noto.
pub const x_natural_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .grid,
        .stem_width = .natural,
        .positioning = .independent,
        .registration = .left_round_outline,
    },
    .y = y_policy.y,
    .fade = demo_fade,
};

/// Candidate universal default: crisp at small sizes, weight-preserving at large.
/// Both axes use the LIGHT taper — a stem's edges register to the grid (crisp) at
/// every size, but its WIDTH is only quantized to a whole pixel while thin
/// (< max_px ≈ 1.6px, i.e. small ppem); above that it keeps its natural width.
/// This is what makes it degrade gracefully on faces the sans-tuned analyzer
/// wasn't built for: at large ppem a `full` width-snap over-bolds serif stems and
/// flattens their stroke contrast (rough), while the taper lets AA carry them at
/// natural weight. A low std-snap (0.2, vs xf's 0.4) avoids bolding light fonts
/// (Noto) to the shared std width; round-left registration keeps bowls in-column.
/// Positioning is INDEPENDENT: `relative` anchors the whole stem cluster and, at
/// the demo's non-integer render scale, lands the leftmost stem off the pixel grid
/// (the 'm' left leg renders as a thin straddled sliver); independent snaps each
/// stem edge to its own grid line — crisper here and closer to TT hinting.
/// Overshoot is PRESERVED, not suppressed: a round apex (o/e/c/ς top, bowl bottom)
/// whose overshoot is suppressed snaps exactly onto the x-height/baseline pixel
/// row, and because that arc is nearly flat it fills the row uniformly → a visibly
/// flat-topped 'o'. Keeping the (sub-pixel) overshoot lifts the apex off the row so
/// it AA's into a curve like TT hinting; at small ppem the overshoot is a fraction of
/// a pixel and doesn't blur the line.
pub const default_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .grid,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.2, .max_px = 1.6 } },
        .positioning = .independent,
        .registration = .left_round_outline,
    },
    .y = .{
        .@"align" = .blue_zones,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.2, .max_px = 1.6 } },
        .overshoot = .preserve,
    },
    .fade = demo_fade,
};

/// Strong/terminal policy: the same y fitting plus full x grid fitting.
pub const xy_policy: snail.autohint.AutohintPolicy = .{
    .x = .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .positioning = .independent,
        .registration = .left_round_outline,
    },
    .y = .{
        .@"align" = .blue_zones,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.0 } },
        .overshoot = .{ .suppress_below_px = 0.5 },
    },
    .fade = demo_fade,
};

const Row = struct {
    tag: []const u8,
    mode: @FieldType(snail.RunPlacement, "mode"),
    snap: snail.RunSnap,
};

const rows = [_]Row{
    .{ .tag = "un", .mode = .unhinted, .snap = .none },
    .{ .tag = "y", .mode = .{ .autohint = y_policy }, .snap = .none },
    .{ .tag = "xn", .mode = .{ .autohint = x_natural_policy }, .snap = .columns },
    .{ .tag = "xf", .mode = .{ .autohint = xy_policy }, .snap = .columns },
    .{ .tag = "df", .mode = .{ .autohint = default_policy }, .snap = .columns },
    .{ .tag = "tt", .mode = .{ .tt_hint = .{ .ppem_26_6 = 0 } }, .snap = .columns },
};

pub const Compare = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    font: *snail.Font,
    faces: snail.Faces,
    font_id: u32,
    auto: snail.autohint.AutohintAnalyzer,
    /// The font's own TT hinting, if it has any (DejaVu does; Noto Sans
    /// Mono is unhinted, so this stays null and the tt row renders unhinted).
    tt: ?snail.TtHintVm,
    /// Short display name for the font (e.g. "DejaVu", "Noto").
    label: []const u8,
    /// Proportional (non-monospace) face: the hinted rows snap per-glyph
    /// ORIGINS (round each glyph's cumulative kerned position) instead of
    /// forcing one uniform integer column advance, which only fits monospace.
    proportional: bool = false,

    shape_cache: ShapedRunCache,
    glyph_cache: UnhintedGlyphCache,
    atlas: snail.Atlas,

    pub fn init(allocator: Allocator, pool: *snail.PagePool) !Compare {
        return initFont(allocator, pool, assets.dejavu_sans_mono, "DejaVu");
    }

    pub fn initFont(allocator: Allocator, pool: *snail.PagePool, font_bytes: []const u8, label: []const u8) !Compare {
        return initFontMode(allocator, pool, font_bytes, label, false);
    }

    pub fn initFontMode(allocator: Allocator, pool: *snail.PagePool, font_bytes: []const u8, label: []const u8, proportional: bool) !Compare {
        const font = try allocator.create(snail.Font);
        errdefer allocator.destroy(font);
        font.* = try snail.Font.init(font_bytes);

        var faces = try snail.Faces.build(allocator, &.{.{ .font = font }});
        errdefer faces.deinit();
        const font_id = faces.fontIdForFace(0);

        const auto = try snail.autohint.AutohintAnalyzer.init(allocator, font_bytes);
        const tt = snail.TtHintVm.init(allocator, font) catch null;

        return .{
            .allocator = allocator,
            .pool = pool,
            .font = font,
            .faces = faces,
            .font_id = font_id,
            .auto = auto,
            .tt = tt,
            .label = label,
            .proportional = proportional,
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
    pub fn devEm(ppem: f32, px_scale: f32) f32 {
        return @round(ppem * px_scale);
    }

    /// Build the full validation grid in DEVICE pixels (see `px_scale`).
    /// `scratch` must outlive the atlas build (the builder copies knots/curves
    /// in). Returns the picture; `self.atlas` is extended with everything it
    /// references. Draw the resulting pass with an `ortho(0, fb_w, fb_h, 0)`
    /// projection so device coordinates map 1:1 to framebuffer pixels.
    pub fn buildGrid(self: *Compare, frame_alloc: Allocator, scratch: Allocator, px_scale: f32) !demo_support.Picture {
        return self.buildGridAt(frame_alloc, scratch, px_scale, 0);
    }

    /// `buildGrid` with a device-x origin so multiple fonts can sit side by
    /// side. `column_width_px` (design units) is the horizontal span one grid
    /// occupies — pass 0 for a single grid.
    pub fn gridWidthPx(px_scale: f32) f32 {
        // Wide enough for the sample at the largest ppem (~52px tag column +
        // the full string). Three columns fit the demo's widened window.
        return 448 * px_scale;
    }

    pub fn buildGridAt(self: *Compare, frame_alloc: Allocator, scratch: Allocator, px_scale: f32, x0: f32) !demo_support.Picture {
        const shaped = try self.shape_cache.shape(&self.faces, sample_text, .{});

        // Tag glyphs render unhinted at a fixed size; sample glyphs render per
        // (ppem, row). Fold the font-label header's letters into the tag run
        // so ensureAll makes them resident too. Ensure everything in one pass.
        const tags_str = try std.fmt.allocPrint(frame_alloc, "unyxnxfdftt0123456789px{s}", .{self.label});
        const tags = try self.shape_cache.shape(&self.faces, tags_str, .{});
        try self.ensureAll(scratch, shaped, tags, px_scale);

        var refs: std.ArrayList(*const demo_support.Picture) = .empty;
        const left_tag: f32 = x0 + 8 * px_scale;
        const left_sample: f32 = x0 + 52 * px_scale;
        const tag_em: f32 = 12 * px_scale;

        // Column header: which font this grid is.
        const head_shaped = try self.shape_cache.shape(&self.faces, self.label, .{});
        const head = try frame_alloc.create(demo_support.Picture);
        head.* = try demo_support.placeRun(frame_alloc, head_shaped, &self.faces, .{
            .baseline = .{ .x = left_tag, .y = 14 * px_scale },
            .em = tag_em,
            .color = tag_color,
        });
        try refs.append(frame_alloc, head);

        var y: f32 = grid_top * px_scale;
        for (grid_ppems) |ppem| {
            const em: f32 = devEm(ppem, px_scale);
            const ppem_26_6: u32 = @intFromFloat(em * 64.0);

            // Section header: the ppem size this block is rendered at.
            const size_str = try std.fmt.allocPrint(frame_alloc, "{d}px", .{@as(u32, @intFromFloat(ppem))});
            const size_shaped = try self.shape_cache.shape(&self.faces, size_str, .{});
            const size_lbl = try frame_alloc.create(demo_support.Picture);
            size_lbl.* = try demo_support.placeRun(frame_alloc, size_shaped, &self.faces, .{
                .baseline = .{ .x = left_tag, .y = @round(y) + tag_em },
                .em = tag_em,
                .color = tag_color,
            });
            try refs.append(frame_alloc, size_lbl);
            y += section_head * px_scale;

            for (rows) |row_desc| {
                const baseline = @round(y) + em;
                // Row tag (fixed-size, unhinted).
                const tag_shaped = try self.shape_cache.shape(&self.faces, row_desc.tag, .{});
                const tag = try frame_alloc.create(demo_support.Picture);
                tag.* = try demo_support.placeRun(frame_alloc, tag_shaped, &self.faces, .{
                    .baseline = .{ .x = left_tag, .y = @round(y) + tag_em },
                    .em = tag_em,
                    .color = tag_color,
                });
                try refs.append(frame_alloc, tag);
                // The sample in this mode.
                const row = try frame_alloc.create(demo_support.Picture);
                row.* = try self.renderRow(frame_alloc, shaped, row_desc, ppem_26_6, em, left_sample, baseline);
                try refs.append(frame_alloc, row);
                y += em * row_leading + row_gap * px_scale;
            }
            y += ppem_gap * px_scale;
        }
        return demo_support.Picture.concat(frame_alloc, refs.items);
    }

    fn renderRow(
        self: *Compare,
        frame_alloc: Allocator,
        shaped: *const snail.ShapedText,
        row_desc: Row,
        ppem_26_6: u32,
        em: f32,
        left: f32,
        baseline: f32,
    ) !demo_support.Picture {
        // Grid layout is already in device pixels (see buildGrid), so the
        // world→device transform is identity and column snapping rounds to
        // integer device pens. The y-only row keeps natural x positioning.
        const mode: @FieldType(snail.RunPlacement, "mode") = switch (row_desc.mode) {
            .tt_hint => .{ .tt_hint = .{ .ppem_26_6 = ppem_26_6 } },
            else => row_desc.mode,
        };
        // Column snapping is a monospace convenience; a proportional face must
        // round each glyph's own origin instead of forcing a uniform advance.
        const snap: snail.RunSnap = if (self.proportional and row_desc.snap == .columns)
            .origins
        else
            row_desc.snap;
        const picture = try demo_support.placeRun(frame_alloc, shaped, null, .{
            .baseline = .{ .x = left, .y = baseline },
            .em = em,
            .color = text_color,
            .mode = mode,
            .snap = snap,
            .world_to_pixel = .identity,
        });
        // An empty outline has no bands to back an autohint record. Keep its
        // no-op shape on the shared unhinted key so emit-time lookup succeeds
        // without manufacturing size/policy-specific whitespace records.
        if (mode == .autohint) {
            const shapes = @constCast(picture.shapes);
            for (shaped.glyphs, shapes) |glyph, *shape| {
                const base = try self.glyph_cache.getOrInsert(self.allocator, frame_alloc, glyph.glyph_id);
                if (base.curve_count == 0) {
                    shape.key = snail.record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id);
                    shape.autohint_policy = null;
                }
            }
        }
        return picture;
    }

    /// Ensure the atlas holds unhinted curves and one immutable autohint
    /// analysis per sample glyph, plus TT-hinted curves for each PPEM.
    /// Feature slices and TT curves live on `scratch`; the atlas copies them.
    pub fn ensureAll(self: *Compare, scratch: Allocator, shaped: *const snail.ShapedText, tags: *const snail.ShapedText, px_scale: f32) !void {
        var entries: std.ArrayList(snail.AtlasEntry) = .empty;
        defer entries.deinit(scratch);

        // Unhinted (shared) — sample + tag glyphs.
        for ([_]*const snail.ShapedText{ shaped, tags }) |run| {
            for (run.glyphs) |g| {
                if (g.font_id != self.font_id) continue;
                const key = snail.record_key.unhintedGlyph(g.font_id, g.glyph_id);
                if (self.atlas.contains(key) or hasKey(entries.items, key)) continue;
                const c = try self.glyph_cache.getOrInsert(self.allocator, scratch, g.glyph_id);
                try entries.append(scratch, .{ .key = key, .curves = c.* });
            }
        }

        // Immutable analysis is populated exactly once per unique non-empty
        // sample glyph, independent of policy and PPEM. Empty outlines are the
        // explicit exception: they have no curves or bands, emit no instance,
        // and stay on the shared unhinted key with a null policy rather than
        // manufacturing an analysis record.
        for (shaped.glyphs) |g| {
            if (g.font_id != self.font_id) continue;
            const key_a = autoKey(g.font_id, g.glyph_id);
            if (self.atlas.contains(key_a) or hasKey(entries.items, key_a)) continue;
            // Whitespace has no bands for an autohint record to alias.
            const base = try self.glyph_cache.getOrInsert(self.allocator, scratch, g.glyph_id);
            if (base.curve_count == 0) continue;

            const x_features = try scratch.alloc(snail.autohint.FeatureEdge, warp.max_knots);
            const y_features = try scratch.alloc(snail.autohint.FeatureEdge, warp.max_knots);
            const glyph = try self.auto.analyzeGlyph(scratch, g.glyph_id, x_features, y_features);
            try entries.append(scratch, .{
                .key = key_a,
                .curves = snail.GlyphCurves.empty(scratch),
                .autohint = .{ .font = self.auto.fontFeatures(), .glyph = glyph },
                .autohint_base = snail.record_key.unhintedGlyph(g.font_id, g.glyph_id),
            });
        }

        // Only TT-hint preparation and baked curves remain PPEM-specific.
        for (grid_ppems) |ppem| {
            const ppem_26_6: u32 = @intFromFloat(devEm(ppem, px_scale) * 64.0);
            // Run fpgm/prep once for this size; every glyph hints from it.
            var tt_prepared: ?snail.TtHintVm.Prepared = if (self.tt) |*vm|
                (vm.prepare(snail.TtHintPpem.uniform(ppem_26_6)) catch null)
            else
                null;
            defer if (tt_prepared) |*p| p.deinit();

            for (shaped.glyphs) |g| {
                if (g.font_id != self.font_id) continue;

                if (self.tt) |*vm| if (tt_prepared) |*prepared| {
                    const key_t = snail.record_key.ttHintedGlyph(g.font_id, g.glyph_id, ppem_26_6);
                    if (!self.atlas.contains(key_t) and !hasKey(entries.items, key_t)) {
                        // Output on `scratch` (persists to the atlas build); VM
                        // internals on a dedicated temp arena so they can't
                        // alias the output. Hinting is pure now, so a glyph that
                        // errors can't corrupt anything — just register an empty
                        // record so the TT row still resolves.
                        var tmp = std.heap.ArenaAllocator.init(self.allocator);
                        defer tmp.deinit();
                        const curves = vm.hintGlyph(scratch, tmp.allocator(), prepared, g.glyph_id) catch
                            snail.GlyphCurves.empty(scratch);
                        try entries.append(scratch, .{ .key = key_t, .curves = curves });
                    }
                };
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

fn autoKey(font_id: u32, glyph_id: u16) snail.record_key.RecordKey {
    return snail.record_key.autohintGlyph(font_id, glyph_id);
}

const text_color = [4]f32{ 0.06, 0.07, 0.09, 1.0 };
const tag_color = [4]f32{ 0.45, 0.48, 0.55, 1.0 };

fn hasKey(entries: []const snail.AtlasEntry, key: snail.record_key.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

test "comparison contains both x-width policies and fits the default viewport" {
    try testing.expectEqualStrings("un", rows[0].tag);
    try testing.expectEqualStrings("y", rows[1].tag);
    try testing.expectEqualStrings("xn", rows[2].tag);
    try testing.expectEqualStrings("xf", rows[3].tag);
    try testing.expectEqualStrings("df", rows[4].tag);
    try testing.expectEqualStrings("tt", rows[5].tag);
    try testing.expect(gridHeightPx(1.0) <= @as(f32, @floatFromInt(default_viewport_height)));
}

test "comparison setup reuses autohint analysis across grid PPEMs" {
    var pool = try snail.PagePool.init(testing.allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var compare = try Compare.init(testing.allocator, pool);
    defer compare.deinit();
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();

    const shaped = try compare.shape_cache.shape(&compare.faces, sample_text, .{});
    const tags = try compare.shape_cache.shape(&compare.faces, "unyxyttDejaVu", .{});
    try compare.ensureAll(scratch.allocator(), shaped, tags, 1.0);

    var sample_glyphs: std.AutoHashMap(u16, void) = .init(testing.allocator);
    defer sample_glyphs.deinit();
    for (shaped.glyphs) |glyph| {
        if (glyph.font_id != compare.font_id) continue;
        const base = try compare.glyph_cache.getOrInsert(testing.allocator, scratch.allocator(), glyph.glyph_id);
        if (base.curve_count != 0) try sample_glyphs.put(glyph.glyph_id, {});
    }

    var it = sample_glyphs.keyIterator();
    while (it.next()) |glyph_id| {
        const analysis_key = autoKey(compare.font_id, glyph_id.*);
        try testing.expect(compare.atlas.lookupAutohintRecord(analysis_key) != null);
        if (compare.tt != null) {
            for (grid_ppems) |ppem| {
                const ppem_26_6: u32 = @intFromFloat(Compare.devEm(ppem, 1.0) * 64.0);
                try testing.expect(compare.atlas.contains(snail.record_key.ttHintedGlyph(compare.font_id, glyph_id.*, ppem_26_6)));
            }
        }
    }

    // A policy/size-independent analysis key means exactly one autohint slab
    // record is reachable for each unique sample glyph.
    try testing.expectEqual(sample_glyphs.count(), countAutohintRecords(&compare, shaped));
}

test "empty outlines remain shared unhinted no-op shapes" {
    var pool = try snail.PagePool.init(testing.allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var compare = try Compare.init(testing.allocator, pool);
    defer compare.deinit();
    var frame = std.heap.ArenaAllocator.init(testing.allocator);
    defer frame.deinit();
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();

    const shaped = try compare.shape_cache.shape(&compare.faces, sample_text, .{});
    const tags = try compare.shape_cache.shape(&compare.faces, "unyxyttDejaVu", .{});
    try compare.ensureAll(scratch.allocator(), shaped, tags, 1.0);

    var empty_index: ?usize = null;
    for (shaped.glyphs, 0..) |glyph, i| {
        const base = try compare.glyph_cache.getOrInsert(testing.allocator, scratch.allocator(), glyph.glyph_id);
        if (base.curve_count == 0) {
            empty_index = i;
            break;
        }
    }
    const i = empty_index orelse return error.TestExpectedEmptyOutline;
    const glyph = shaped.glyphs[i];
    const base_key = snail.record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id);
    const base_record = compare.atlas.lookupRecord(base_key).?;
    try testing.expectEqual(@as(u32, 0), base_record.curve_count);
    try testing.expectEqual(@as(u16, 0), base_record.bands.h_band_count);
    try testing.expectEqual(@as(u16, 0), base_record.bands.v_band_count);
    try testing.expect(compare.atlas.lookupAutohintRecord(autoKey(glyph.font_id, glyph.glyph_id)) == null);

    var picture = try compare.renderRow(frame.allocator(), shaped, rows[1], 12 * 64, 12, 0, 12);
    defer picture.deinit();
    const shape = picture.shapes[i];
    try testing.expect(shape.key.eql(base_key));
    try testing.expectEqual(@as(?snail.autohint.AutohintPolicy, null), shape.autohint_policy);

    var words: [snail.render.records.WORDS_PER_INSTANCE]u32 = undefined;
    var segments: [1]snail.render.records.DrawSegment = undefined;
    var word_len: usize = 0;
    var segment_len: usize = 0;
    _ = try snail.emit.emit(&words, &segments, &word_len, &segment_len, .{ .pool = pool }, &compare.atlas, &.{shape}, .identity, .{ 1, 1, 1, 1 });
    try testing.expectEqual(@as(usize, 0), word_len);
    try testing.expectEqual(@as(usize, 0), segment_len);
}

fn countAutohintRecords(compare: *const Compare, shaped: *const snail.ShapedText) u32 {
    var count: u32 = 0;
    for (shaped.glyphs, 0..) |glyph, i| {
        if (glyph.font_id != compare.font_id) continue;
        for (shaped.glyphs[0..i]) |prior| {
            if (prior.font_id == glyph.font_id and prior.glyph_id == glyph.glyph_id) break;
        } else {
            if (compare.atlas.lookupAutohintRecord(autoKey(glyph.font_id, glyph.glyph_id)) != null) count += 1;
        }
    }
    return count;
}
