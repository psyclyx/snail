//! `Atlas.Builder`: shared state for `Atlas.from`/`extend`/`compact`.
//! Owns refs on intermediate pages until `finish()` transfers them to
//! the resulting `Atlas`, or `abort()` releases them.
//!
//! Lives in its own module so `atlas.zig` stays focused on the public
//! `Atlas` surface — the builder pulls in band-ref rewriting plus the
//! paint-record / composite-record layout logic that callers never need
//! to touch directly.

const std = @import("std");

const atlas_mod = @import("../atlas.zig");
const page_mod = @import("page.zig");
const page_pool_mod = @import("page_pool.zig");
const atlas_record_mod = @import("record.zig");
const record_key_mod = @import("record_key.zig");
const curves_mod = @import("curves.zig");
const curve_tex_format = @import("../format/curve_texture.zig");
const band_tex_format = @import("../format/band_texture.zig");
const paint_records = @import("paint_records.zig");
const autohint_format = @import("../format/autohint_record.zig");
const autohint_warp = @import("../font/autohint/warp.zig");
const render_abi = @import("../format/abi.zig");
const paint_mod = @import("../paint.zig");

const Atlas = atlas_mod.Atlas;
const Entry = atlas_mod.Entry;
const Layer = atlas_mod.Layer;
const Paint = paint_mod.Paint;
const InsertError = atlas_mod.InsertError;
const AtlasPage = page_mod.AtlasPage;
const PagePool = page_pool_mod.PagePool;
const AtlasRecord = atlas_record_mod.AtlasRecord;
const GlyphBandEntry = atlas_record_mod.GlyphBandEntry;
const RecordKey = record_key_mod.RecordKey;
const GlyphCurves = curves_mod.GlyphCurves;
const PaintImageRecord = atlas_mod.PaintImageRecord;
const PaintRecordInfo = atlas_mod.PaintRecordInfo;
const RecordLookup = atlas_mod.RecordLookup;
const PaintLookup = atlas_mod.PaintLookup;
const TtAdvanceLookup = atlas_mod.TtAdvanceLookup;

const CURVE_TEX_WIDTH = curve_tex_format.TEX_WIDTH;
const CURVE_SEGMENT_TEXELS = curve_tex_format.SEGMENT_TEXELS;
const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * 4;
const BAND_TEX_WIDTH = band_tex_format.TEX_WIDTH;
const BAND_TEX_WIDTH_USIZE: usize = BAND_TEX_WIDTH;

pub const Builder = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    pages: std.ArrayList(*AtlasPage),
    lookup: RecordLookup,
    layer_info_buf: std.ArrayList(f32),
    layer_info_texels: u32,
    paint_lookup: PaintLookup,
    autohint_lookup: PaintLookup,
    tt_hinted_lookup: PaintLookup,
    tt_advance_lookup: TtAdvanceLookup,
    /// Per-record slot for image paints. Indexed in insertion order;
    /// non-image paints land as `null`. Empty when no paints emitted.
    paint_image_records: std.ArrayList(?PaintImageRecord),

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) Builder {
        return .{
            .allocator = allocator,
            .pool = pool,
            .pages = .empty,
            .lookup = RecordLookup.init(allocator, .{}),
            .layer_info_buf = .empty,
            .layer_info_texels = 0,
            .paint_lookup = PaintLookup.init(allocator, .{}),
            .autohint_lookup = PaintLookup.init(allocator, .{}),
            .tt_hinted_lookup = PaintLookup.init(allocator, .{}),
            .tt_advance_lookup = TtAdvanceLookup.init(allocator, .{}),
            .paint_image_records = .empty,
        };
    }

    pub fn initFrom(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        base: *const Atlas,
    ) std.mem.Allocator.Error!Builder {
        var b = Builder{
            .allocator = allocator,
            .pool = pool,
            .pages = .empty,
            // Share base's lookup tree wholesale — every subsequent
            // `put` path-copies just the new path and keeps the
            // unchanged subtrees pointed at base's nodes.
            .lookup = base.lookup.clone(),
            .layer_info_buf = .empty,
            .layer_info_texels = 0,
            .paint_lookup = base.paint_lookup.clone(),
            .autohint_lookup = base.autohint_lookup.clone(),
            .tt_hinted_lookup = base.tt_hinted_lookup.clone(),
            .tt_advance_lookup = base.tt_advance_lookup.clone(),
            .paint_image_records = .empty,
        };
        errdefer b.abort();

        try b.pages.ensureTotalCapacity(allocator, base.pages.len);
        for (base.pages) |p| {
            p.retain();
            b.pages.appendAssumeCapacity(p);
        }

        if (base.layer_info_data) |src| {
            try b.layer_info_buf.appendSlice(allocator, src);
            b.layer_info_texels = @intCast(src.len / 4);
        }

        if (base.paint_image_records) |src| {
            try b.paint_image_records.appendSlice(allocator, src);
        }
        return b;
    }

    pub fn abort(self: *Builder) void {
        for (self.pages.items) |p| self.pool.release(p);
        self.pages.deinit(self.allocator);
        self.lookup.deinit();
        self.layer_info_buf.deinit(self.allocator);
        self.paint_lookup.deinit();
        self.autohint_lookup.deinit();
        self.tt_hinted_lookup.deinit();
        self.tt_advance_lookup.deinit();
        self.paint_image_records.deinit(self.allocator);
    }

    /// In-place persistent put on `self.lookup`. The old map's last
    /// reference is released; the new map shares structure with the
    /// previous one through HAMT path-copy.
    fn lookupPut(self: *Builder, key: RecordKey, value: AtlasRecord) !void {
        const next = try self.lookup.put(key, value);
        self.lookup.deinit();
        self.lookup = next;
    }

    /// Same shape as `lookupPut` for the paint side.
    fn paintLookupPut(self: *Builder, key: RecordKey, value: PaintRecordInfo) !void {
        const next = try self.paint_lookup.put(key, value);
        self.paint_lookup.deinit();
        self.paint_lookup = next;
    }

    fn autohintLookupPut(self: *Builder, key: RecordKey, value: PaintRecordInfo) !void {
        const next = try self.autohint_lookup.put(key, value);
        self.autohint_lookup.deinit();
        self.autohint_lookup = next;
    }

    fn ttHintedLookupPut(self: *Builder, key: RecordKey, value: PaintRecordInfo) !void {
        const next = try self.tt_hinted_lookup.put(key, value);
        self.tt_hinted_lookup.deinit();
        self.tt_hinted_lookup = next;
    }

    /// Write the two texels a TT-hinted-text instance needs to resolve the
    /// baked glyph's ordinary band record. Curves are not duplicated into
    /// layer-info: TtHintVm already produced direct-encoded hinted curves.
    fn insertTtHintedRecord(self: *Builder, key: RecordKey, bands: GlyphBandEntry) InsertError!void {
        std.debug.assert(bands.h_band_count > 0 and bands.v_band_count > 0);
        const texel_offset = self.layer_info_texels;
        const new_texels = std.math.add(u32, texel_offset, 2) catch return error.LayerInfoTooLarge;
        const max_texels = paint_records.info_width * (@as(u32, std.math.maxInt(u16)) + 1);
        if (new_texels > max_texels) return error.LayerInfoTooLarge;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
            @memset(self.layer_info_buf.items[@as(usize, texel_offset) * 4 .. need_floats], 0);
        }
        paint_records.setTexel(self.layer_info_buf.items, paint_records.info_width, texel_offset, .{
            @floatFromInt(bands.glyph_x),
            @floatFromInt(bands.glyph_y),
            @bitCast(render_abi.packBandCounts(bands.h_band_count, bands.v_band_count)),
            0,
        });
        paint_records.setTexel(self.layer_info_buf.items, paint_records.info_width, texel_offset + 1, .{
            bands.band_scale_x,
            bands.band_scale_y,
            bands.band_offset_x,
            bands.band_offset_y,
        });
        try self.ttHintedLookupPut(key, .{
            .info_x = @intCast(texel_offset % paint_records.info_width),
            .info_y = @intCast(texel_offset / paint_records.info_width),
            .layer_count = 1,
        });
        self.layer_info_texels = new_texels;
    }

    /// Append one immutable feature record after validating counts and slab
    /// coordinates. Shares `layer_info_buf` with paint records.
    fn insertAutohintRecord(
        self: *Builder,
        key: RecordKey,
        bands: GlyphBandEntry,
        analysis: atlas_mod.AutohintAnalysis,
    ) InsertError!void {
        if (analysis.glyph.x.len > autohint_warp.max_knots or
            analysis.glyph.y.len > autohint_warp.max_knots or
            analysis.font.blues.len > autohint_warp.max_knots)
        {
            return error.InvalidAutohintAnalysis;
        }
        const record_floats = autohint_format.recordFloatCount(
            analysis.font.blues.len,
            analysis.glyph.x.len,
            analysis.glyph.y.len,
        );
        const record_texels: u32 = @intCast((record_floats + 3) / 4);
        const texel_offset = self.layer_info_texels;
        const new_texels = std.math.add(u32, texel_offset, record_texels) catch return error.LayerInfoTooLarge;
        const max_texels = paint_records.info_width * (@as(u32, std.math.maxInt(u16)) + 1);
        if (new_texels > max_texels) return error.LayerInfoTooLarge;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
            @memset(self.layer_info_buf.items[@as(usize, texel_offset) * 4 .. need_floats], 0);
        }
        autohint_format.writeRecord(self.layer_info_buf.items, @as(usize, texel_offset) * 4, .{
            .glyph_x = bands.glyph_x,
            .glyph_y = bands.glyph_y,
            .h_band_count = bands.h_band_count,
            .v_band_count = bands.v_band_count,
            .band_scale_x = bands.band_scale_x,
            .band_scale_y = bands.band_scale_y,
            .band_offset_x = bands.band_offset_x,
            .band_offset_y = bands.band_offset_y,
        }, analysis.font, analysis.glyph) catch return error.InvalidAutohintAnalysis;
        try self.autohintLookupPut(key, .{
            .info_x = @intCast(texel_offset % paint_records.info_width),
            .info_y = @intCast(texel_offset / paint_records.info_width),
            .layer_count = 1,
        });
        self.layer_info_texels = new_texels;
    }

    pub fn finish(self: *Builder) std.mem.Allocator.Error!Atlas {
        const pages_slice = try self.pages.toOwnedSlice(self.allocator);
        var layer_info_data: ?[]f32 = null;
        var layer_info_height: u32 = 0;
        if (self.layer_info_texels > 0) {
            layer_info_height = (self.layer_info_texels + paint_records.info_width - 1) / paint_records.info_width;
            // Pad the buffer's tail with zeros so the slice can be uploaded
            // directly as a `INFO_WIDTH × height` RGBA32F texture.
            const full_floats = @as(usize, paint_records.info_width) * @as(usize, layer_info_height) * 4;
            if (self.layer_info_buf.items.len < full_floats) {
                const old_len = self.layer_info_buf.items.len;
                try self.layer_info_buf.resize(self.allocator, full_floats);
                @memset(self.layer_info_buf.items[old_len..], 0);
            }
            layer_info_data = try self.layer_info_buf.toOwnedSlice(self.allocator);
        } else {
            self.layer_info_buf.deinit(self.allocator);
        }
        // Only carry a paint_image_records slice if any image paints were
        // emitted; otherwise drop it so consumers can shortcut on null.
        var paint_image_records_out: ?[]?PaintImageRecord = null;
        var has_image_paint = false;
        for (self.paint_image_records.items) |rec| {
            if (rec != null) {
                has_image_paint = true;
                break;
            }
        }
        if (has_image_paint) {
            paint_image_records_out = try self.paint_image_records.toOwnedSlice(self.allocator);
        } else {
            self.paint_image_records.deinit(self.allocator);
        }
        return .{
            .allocator = self.allocator,
            .pool = self.pool,
            .pages = pages_slice,
            .lookup = self.lookup,
            .layer_info_data = layer_info_data,
            .layer_info_width = if (layer_info_data != null) paint_records.info_width else 0,
            .layer_info_height = layer_info_height,
            .paint_lookup = self.paint_lookup,
            .autohint_lookup = self.autohint_lookup,
            .tt_hinted_lookup = self.tt_hinted_lookup,
            .tt_advance_lookup = self.tt_advance_lookup,
            .paint_image_records = paint_image_records_out,
        };
    }

    pub const Placement = struct {
        page_index: u16,
        page_generation: u16,
        curve_texel: u32,
        curve_count: u16,
        bands: GlyphBandEntry,
    };

    /// Reserve curve+band space for one set of GlyphCurves on a page,
    /// copying the bytes and rewriting band refs. Returns the placement
    /// metadata the caller stitches into AtlasRecord / paint records.
    fn placeCurves(self: *Builder, curves: GlyphCurves) InsertError!Placement {
        const curve_words: u32 = @intCast(curves.curve_bytes.len);
        const band_words: u32 = @intCast(curves.band_bytes.len);
        std.debug.assert(curve_words % CURVE_SEGMENT_WORDS == 0);
        std.debug.assert(curve_words / CURVE_SEGMENT_WORDS == curves.curve_count);

        if (curve_words > self.pool.options.curve_words_per_page or
            band_words > self.pool.options.band_words_per_page)
        {
            return error.RecordTooLargeForPage;
        }

        var page: *AtlasPage = undefined;
        var page_idx: u16 = undefined;
        var reservation: AtlasPage.Reservation = undefined;
        var placed = false;

        if (self.pages.items.len > 0) {
            const tail = self.pages.items[self.pages.items.len - 1];
            if (tail.reserve(curve_words, band_words)) |r| {
                page = tail;
                page_idx = @intCast(self.pages.items.len - 1);
                reservation = r;
                placed = true;
            }
        }

        if (!placed) {
            const new_page = try self.pool.acquire();
            errdefer self.pool.release(new_page);
            try self.pages.append(self.allocator, new_page);
            page = new_page;
            page_idx = @intCast(self.pages.items.len - 1);
            reservation = page.reserve(curve_words, band_words) orelse return error.RecordTooLargeForPage;
        }

        std.debug.assert(reservation.curve_word_offset + curves.curve_bytes.len <= page.curve.capacity_words);
        @memcpy(page.curve.data[reservation.curve_word_offset..][0..curves.curve_bytes.len], curves.curve_bytes);

        std.debug.assert(reservation.curve_word_offset % 4 == 0);
        const base_curve_texel = reservation.curve_word_offset / 4;

        std.debug.assert(reservation.band_word_offset + curves.band_bytes.len <= page.band.capacity_words);
        @memcpy(page.band.data[reservation.band_word_offset..][0..curves.band_bytes.len], curves.band_bytes);
        const band_slice = page.band.data[reservation.band_word_offset..][0..band_words];
        rewriteBandRefs(band_slice, curves.h_band_count, curves.v_band_count, base_curve_texel);

        std.debug.assert(reservation.band_word_offset % 2 == 0);
        const band_texel = reservation.band_word_offset / 2;

        return .{
            .page_index = page_idx,
            .page_generation = page.currentGeneration(),
            .curve_texel = base_curve_texel,
            .curve_count = curves.curve_count,
            .bands = .{
                .glyph_x = @intCast(band_texel % BAND_TEX_WIDTH),
                .glyph_y = @intCast(band_texel / BAND_TEX_WIDTH),
                .h_band_count = curves.h_band_count,
                .v_band_count = curves.v_band_count,
                .band_scale_x = curves.band_scale_x,
                .band_scale_y = curves.band_scale_y,
                .band_offset_x = curves.band_offset_x,
                .band_offset_y = curves.band_offset_y,
            },
        };
    }

    /// Write a composite group paint record: header texel + N regular
    /// paint records (6 texels each). The shader's `compositePathGroup`
    /// walks `layer_count` layers and composites them per `mode`.
    fn insertCompositeRecord(
        self: *Builder,
        key: RecordKey,
        mode: paint_mod.CompositeMode,
        base_paint: Paint,
        base_bands: GlyphBandEntry,
        base_fill_rule: paint_mod.FillRule,
        extra_layers: []const Layer,
        extra_placements: []const Placement,
        layer_count: u32,
    ) std.mem.Allocator.Error!void {
        std.debug.assert(extra_placements.len + 1 == layer_count);
        std.debug.assert(extra_placements.len <= extra_layers.len);

        const header_offset = self.layer_info_texels;
        const total_texels: u32 = 1 + layer_count * paint_records.texels_per_record;
        const new_texels = header_offset + total_texels;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
            @memset(self.layer_info_buf.items[header_offset * 4 .. need_floats], 0);
        }

        // Header texel: (layer_count, composite_mode, 0, tag_composite_group)
        paint_records.setTexel(self.layer_info_buf.items, paint_records.info_width, header_offset, .{
            @floatFromInt(layer_count),
            @floatFromInt(@intFromEnum(toAbiCompositeMode(mode))),
            0,
            paint_records.tag_composite_group,
        });

        // Image-paint slot for the header carries no image.
        try self.paint_image_records.append(self.allocator, null);

        var layer_texel = header_offset + 1;
        try self.writeLayerRecord(layer_texel, base_bands, base_paint, base_fill_rule);
        layer_texel += paint_records.texels_per_record;

        // Walk extra_placements alongside the non-empty entries of extra_layers.
        var place_index: usize = 0;
        for (extra_layers) |layer| {
            if (layer.curves.isEmpty()) continue;
            try self.writeLayerRecord(layer_texel, extra_placements[place_index].bands, layer.paint, layer.fill_rule);
            layer_texel += paint_records.texels_per_record;
            place_index += 1;
        }
        std.debug.assert(place_index == extra_placements.len);

        try self.paintLookupPut(key, .{
            .info_x = @intCast(header_offset % paint_records.info_width),
            .info_y = @intCast(header_offset / paint_records.info_width),
            .layer_count = @intCast(layer_count),
        });
        self.layer_info_texels = new_texels;
    }

    fn writeLayerRecord(
        self: *Builder,
        layer_texel: u32,
        bands: GlyphBandEntry,
        paint: Paint,
        fill_rule: paint_mod.FillRule,
    ) std.mem.Allocator.Error!void {
        const band_tex_entry = bandToTexFormat(bands);
        const rule_bit: u16 = if (fill_rule == .even_odd) paint_records.FILL_RULE_BIT else 0;
        paint_records.write(self.layer_info_buf.items, paint_records.info_width, layer_texel, band_tex_entry, paint, rule_bit);
        try self.paint_image_records.append(self.allocator, switch (paint) {
            .image => |img| .{ .image = img.image, .texel_offset = layer_texel },
            else => null,
        });
    }

    fn insertPaintRecord(self: *Builder, key: RecordKey, paint: Paint, band_entry: GlyphBandEntry, fill_rule: paint_mod.FillRule) std.mem.Allocator.Error!void {
        const texel_offset = self.layer_info_texels;
        const new_texels = texel_offset + paint_records.texels_per_record;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
            @memset(self.layer_info_buf.items[texel_offset * 4 .. need_floats], 0);
        }
        const band_tex_entry = bandToTexFormat(band_entry);
        const fill_rule_bit: u16 = if (fill_rule == .even_odd) paint_records.FILL_RULE_BIT else 0;
        paint_records.write(self.layer_info_buf.items, paint_records.info_width, texel_offset, band_tex_entry, paint, fill_rule_bit);
        try self.paintLookupPut(key, .{
            .info_x = @intCast(texel_offset % paint_records.info_width),
            .info_y = @intCast(texel_offset / paint_records.info_width),
            .layer_count = 1,
        });
        try self.paint_image_records.append(self.allocator, switch (paint) {
            .image => |img| .{ .image = img.image, .texel_offset = texel_offset },
            else => null,
        });
        self.layer_info_texels = new_texels;
    }

    pub fn insert(self: *Builder, entry: Entry) InsertError!void {
        if (self.lookup.contains(entry.key)) return;

        // Aliased autohint: reuse an already-inserted base glyph's placement
        // and bands, placing no curves of our own. A target-free analysis
        // cannot define a static TT-hinted-space expansion, so retain the base
        // bbox; emit expands device bounds when fitting is applied.
        if (entry.autohint) |analysis| {
            if (entry.autohint_base) |base_key| {
                const base_rec = self.lookup.get(base_key) orelse return error.MissingAutohintBase;
                try self.lookupPut(entry.key, base_rec);
                try self.insertAutohintRecord(entry.key, base_rec.bands, analysis);
                return;
            }
        }

        const curves = entry.curves;

        if (curves.isEmpty()) {
            try self.lookupPut(entry.key, .{
                .page_index = 0,
                .page_generation = 0,
                .curve_texel = 0,
                .curve_count = 0,
                .bands = .{
                    .glyph_x = 0,
                    .glyph_y = 0,
                    .h_band_count = 0,
                    .v_band_count = 0,
                    .band_scale_x = 0,
                    .band_scale_y = 0,
                    .band_offset_x = 0,
                    .band_offset_y = 0,
                },
                .bbox = curves.bbox,
            });
            return;
        }

        const base_placement = try self.placeCurves(curves);

        var bbox = curves.bbox;
        // Place each extra layer's curves. Empty layers are filtered.
        var stack_buf: [8]Placement = undefined;
        var extra_count: usize = 0;
        var heap_placements: ?[]Placement = null;
        defer if (heap_placements) |slc| self.allocator.free(slc);
        const extras_storage: []Placement = blk: {
            if (entry.extra_layers.len <= stack_buf.len) {
                break :blk stack_buf[0..entry.extra_layers.len];
            }
            heap_placements = try self.allocator.alloc(Placement, entry.extra_layers.len);
            break :blk heap_placements.?;
        };
        for (entry.extra_layers) |layer| {
            if (layer.curves.isEmpty()) continue;
            extras_storage[extra_count] = try self.placeCurves(layer.curves);
            bbox = bbox.merge(layer.curves.bbox);
            extra_count += 1;
        }

        const record = AtlasRecord{
            .page_index = base_placement.page_index,
            .page_generation = base_placement.page_generation,
            .curve_texel = base_placement.curve_texel,
            .curve_count = base_placement.curve_count,
            .bands = base_placement.bands,
            // Target-free analyses retain the base bbox. Device-space emit
            // supplies the conservative pixel expansion when fitting is used.
            .bbox = bbox,
        };

        try self.lookupPut(entry.key, record);

        if (entry.key.namespace == record_key_mod.ns.tt_hinted_glyph) {
            try self.insertTtHintedRecord(entry.key, base_placement.bands);
        }

        // Autohint: immutable analysis over the shared base glyph.
        if (entry.autohint) |analysis| {
            try self.insertAutohintRecord(entry.key, base_placement.bands, analysis);
        }

        // Skip layer-info entirely if there's no paint at all.
        if (entry.paint == null and extra_count == 0) return;

        if (extra_count == 0) {
            // Single-layer path: just one paint record, no composite header.
            try self.insertPaintRecord(entry.key, entry.paint.?, base_placement.bands, entry.fill_rule);
            return;
        }

        // Multi-layer composite. The base layer occupies slot 0; extras
        // fill slots 1..1+extra_count.
        const total_layers: u32 = @intCast(1 + extra_count);
        const base_paint = entry.paint orelse Paint{ .solid = .{ 0, 0, 0, 0 } };
        try self.insertCompositeRecord(
            entry.key,
            entry.composite_mode,
            base_paint,
            base_placement.bands,
            entry.fill_rule,
            entry.extra_layers,
            extras_storage[0..extra_count],
            total_layers,
        );
    }

    // ── Byte-exact record copy (compaction) ──────────────────────────────
    //
    // `Atlas.compact` re-inserts records from an existing atlas. Payloads
    // (paint texels, autohint features, curve/band bytes) are carried
    // bit-for-bit; only placement-dependent band locations are rewritten.
    // Nothing is decoded back to caller types — paint colors are already
    // stored linear, so a decode/re-encode round trip would drift.

    /// Copy `key`'s record (geometry + any side records) from `src` into
    /// this builder with full fidelity. A kept autohint record copies its
    /// base glyph implicitly (dependency closure) and re-aliases it rather
    /// than duplicating curves. Idempotent per key.
    pub fn insertCopied(
        self: *Builder,
        src: *const Atlas,
        key: RecordKey,
        scratch: std.mem.Allocator,
    ) InsertError!void {
        if (self.lookup.contains(key)) return;
        const rec = src.lookup.get(key) orelse return;

        // Aliased autohint analysis: bring the base along, re-alias, and
        // re-encode the analysis read straight off the source slab (the
        // read/write pair is a bit-exact round trip).
        if (key.namespace == record_key_mod.ns.autohint_glyph) {
            if (src.autohint_lookup.get(key)) |info| {
                const base_key = record_key_mod.unhintedGlyph(key.a, @intCast(key.b));
                try self.insertCopied(src, base_key, scratch);
                const base_rec = self.lookup.get(base_key) orelse return error.MissingAutohintBase;
                try self.lookupPut(key, base_rec);
                const slab = src.layer_info_data.?;
                const off = (@as(usize, info.info_y) * paint_records.info_width + info.info_x) * 4;
                try self.insertAutohintRecord(key, base_rec.bands, .{
                    .font = autohint_format.fontFeatures(slab, off),
                    .glyph = .{
                        .x = autohint_format.xFeatures(slab, off),
                        .y = autohint_format.yFeatures(slab, off),
                        .left = autohint_format.glyphLeft(slab, off),
                    },
                });
                return;
            }
            // Empty autohint record (whitespace): plain empty-record copy.
        }

        if (rec.curve_count == 0) {
            try self.lookupPut(key, rec);
            return;
        }

        const src_page = src.pages[rec.page_index];
        const placement = try self.repackRecordGeometry(src_page, rec, scratch);
        var new_rec = rec;
        new_rec.page_index = placement.page_index;
        new_rec.page_generation = placement.page_generation;
        new_rec.curve_texel = placement.curve_texel;
        new_rec.bands = placement.bands;
        try self.lookupPut(key, new_rec);

        if (key.namespace == record_key_mod.ns.tt_hinted_glyph) {
            try self.insertTtHintedRecord(key, placement.bands);
        }

        if (src.paint_lookup.get(key)) |paint_info| {
            try self.copyPaintSide(src, src_page, key, paint_info, placement.bands, scratch);
        }
    }

    /// Extract one record's curve/band bytes from its source page and
    /// place them on this builder's pages.
    fn repackRecordGeometry(
        self: *Builder,
        src_page: *const AtlasPage,
        rec: AtlasRecord,
        scratch: std.mem.Allocator,
    ) InsertError!Placement {
        const band_words_total = bandWordsForRecordIncludingRefs(src_page, rec);
        const local_band = try scratch.alloc(u16, band_words_total);
        defer scratch.free(local_band);
        extractAndLocalizeBand(src_page, rec, local_band);

        const curve_words: u32 = @as(u32, rec.curve_count) * CURVE_SEGMENT_WORDS;
        return self.placeCurves(.{
            .allocator = scratch,
            .curve_bytes = src_page.curve.data[rec.curve_texel * 4 ..][0..curve_words],
            .band_bytes = local_band,
            .curve_count = rec.curve_count,
            .h_band_count = rec.bands.h_band_count,
            .v_band_count = rec.bands.v_band_count,
            .band_scale_x = rec.bands.band_scale_x,
            .band_scale_y = rec.bands.band_scale_y,
            .band_offset_x = rec.bands.band_offset_x,
            .band_offset_y = rec.bands.band_offset_y,
            .bbox = rec.bbox,
        });
    }

    /// Copy a record's paint texels verbatim, repacking each extra layer's
    /// geometry and patching only the per-layer placement texel.
    fn copyPaintSide(
        self: *Builder,
        src: *const Atlas,
        src_page: *const AtlasPage,
        key: RecordKey,
        paint_info: PaintRecordInfo,
        new_base_bands: GlyphBandEntry,
        scratch: std.mem.Allocator,
    ) InsertError!void {
        const slab = src.layer_info_data.?;
        const width = paint_records.info_width;
        const src_texel: u32 = @as(u32, paint_info.info_y) * width + paint_info.info_x;
        const layer_count: u32 = paint_info.layer_count;
        const is_composite = layer_count > 1;
        const total_texels: u32 = if (is_composite)
            1 + layer_count * paint_records.texels_per_record
        else
            paint_records.texels_per_record;

        const dst_texel = self.layer_info_texels;
        const new_texels = std.math.add(u32, dst_texel, total_texels) catch return error.LayerInfoTooLarge;
        const max_texels = paint_records.info_width * (@as(u32, std.math.maxInt(u16)) + 1);
        if (new_texels > max_texels) return error.LayerInfoTooLarge;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
        }
        @memcpy(
            self.layer_info_buf.items[@as(usize, dst_texel) * 4 .. need_floats],
            slab[@as(usize, src_texel) * 4 ..][0 .. @as(usize, total_texels) * 4],
        );

        // Mirror `insert`'s image-slot pattern: composites carry a null
        // header slot, then one slot per layer record.
        if (is_composite) try self.paint_image_records.append(self.allocator, null);

        var layer_index: u32 = 0;
        while (layer_index < layer_count) : (layer_index += 1) {
            const layer_offset: u32 = if (is_composite)
                1 + layer_index * paint_records.texels_per_record
            else
                0;
            const src_layer_texel = src_texel + layer_offset;
            const dst_layer_texel = dst_texel + layer_offset;
            const t0 = paint_records.readTexel(slab, width, src_layer_texel);
            const t1 = paint_records.readTexel(slab, width, src_layer_texel + 1);
            const gx_raw: u16 = @intFromFloat(t0[0]);
            const fill_bit: u16 = gx_raw & paint_records.FILL_RULE_BIT;

            const new_bands: GlyphBandEntry = if (layer_index == 0)
                new_base_bands
            else blk: {
                // Recover the layer's curve block from its band refs, then
                // repack it like any other geometry.
                const counts = render_abi.unpackBandCounts(@bitCast(t0[2]));
                const src_bands = GlyphBandEntry{
                    .glyph_x = gx_raw & (paint_records.FILL_RULE_BIT - 1),
                    .glyph_y = @intFromFloat(t0[1]),
                    .h_band_count = counts.h,
                    .v_band_count = counts.v,
                    .band_scale_x = t1[0],
                    .band_scale_y = t1[1],
                    .band_offset_x = t1[2],
                    .band_offset_y = t1[3],
                };
                const range = curveRangeForBands(src_page, src_bands) orelse break :blk src_bands;
                const layer_placement = try self.repackRecordGeometry(src_page, .{
                    .page_index = 0,
                    .page_generation = 0,
                    .curve_texel = range.texel,
                    .curve_count = range.count,
                    .bands = src_bands,
                    .bbox = .{ .min = .zero, .max = .zero },
                }, scratch);
                break :blk layer_placement.bands;
            };

            // Patch the placement texel: location changes; band counts,
            // scales/offsets, tag, and fill rule copy through.
            paint_records.setTexel(self.layer_info_buf.items, width, dst_layer_texel, .{
                @floatFromInt(new_bands.glyph_x | fill_bit),
                @floatFromInt(new_bands.glyph_y),
                t0[2],
                t0[3],
            });

            const is_image = t0[3] == paint_records.tag_image;
            // An image-tagged layer always has a slot (insert appends one
            // per image paint); a miss means the source store is corrupt.
            try self.paint_image_records.append(self.allocator, if (is_image)
                .{ .image = findSourceImage(src, src_layer_texel) orelse return error.CorruptPaintRecord, .texel_offset = dst_layer_texel }
            else
                null);
        }

        try self.paintLookupPut(key, .{
            .info_x = @intCast(dst_texel % width),
            .info_y = @intCast(dst_texel / width),
            .layer_count = @intCast(layer_count),
        });
        self.layer_info_texels = new_texels;
    }

    /// Carry one `ns.tt_advance` value into the rebuilt store.
    pub fn putTtAdvance(self: *Builder, key: RecordKey, advance_26_6: i32) std.mem.Allocator.Error!void {
        if (self.tt_advance_lookup.contains(key)) return;
        const next = try self.tt_advance_lookup.put(key, advance_26_6);
        self.tt_advance_lookup.deinit();
        self.tt_advance_lookup = next;
    }
};

/// The image reference behind an image-paint layer, located by the layer's
/// texel offset (each `PaintImageRecord` is self-describing).
fn findSourceImage(src: *const Atlas, layer_texel: u32) ?*const @import("../image.zig").Image {
    const slots = src.paint_image_records orelse return null;
    for (slots) |maybe_slot| {
        const slot = maybe_slot orelse continue;
        if (slot.texel_offset == layer_texel) return slot.image;
    }
    return null;
}

/// The contiguous curve block a set of bands references: minimum and
/// maximum referenced segment, recovered by walking the band refs (refs
/// store absolute page texels). Null when the bands reference no curves.
fn curveRangeForBands(src_page: *const AtlasPage, bands: GlyphBandEntry) ?struct { texel: u32, count: u16 } {
    const headers: usize = @as(usize, bands.h_band_count) + @as(usize, bands.v_band_count);
    if (headers == 0) return null;
    const band_word_offset: usize = (@as(usize, bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, bands.glyph_x)) * 2;

    var total_refs: u32 = 0;
    for (0..headers) |bi| total_refs += src_page.band.data[band_word_offset + bi * 2];
    if (total_refs == 0) return null;

    var min_texel: u32 = std.math.maxInt(u32);
    var max_texel: u32 = 0;
    const refs = src_page.band.data[band_word_offset + headers * 2 ..][0 .. @as(usize, total_refs) * 2];
    var j: usize = 0;
    while (j + 1 < refs.len) : (j += 2) {
        const cx: u32 = refs[j] & CURVE_LOC_X_MASK;
        const cy: u32 = refs[j + 1];
        const abs_texel = cy * CURVE_TEX_WIDTH + cx;
        min_texel = @min(min_texel, abs_texel);
        max_texel = @max(max_texel, abs_texel);
    }
    return .{
        .texel = min_texel,
        .count = @intCast((max_texel - min_texel) / CURVE_SEGMENT_TEXELS + 1),
    };
}

fn bandToTexFormat(b: GlyphBandEntry) band_tex_format.GlyphBandEntry {
    return .{
        .glyph_x = b.glyph_x,
        .glyph_y = b.glyph_y,
        .h_band_count = b.h_band_count,
        .v_band_count = b.v_band_count,
        .band_scale_x = b.band_scale_x,
        .band_scale_y = b.band_scale_y,
        .band_offset_x = b.band_offset_x,
        .band_offset_y = b.band_offset_y,
    };
}

fn toAbiCompositeMode(mode: paint_mod.CompositeMode) enum(u8) { source_over = 0, fill_stroke_inside = 1 } {
    return switch (mode) {
        .source_over => .source_over,
        .fill_stroke_inside => .fill_stroke_inside,
    };
}

// ── Band-ref rewriting ──
//
// The band format stores each curve reference as two u16 words:
// word 0 = (cx | first_member_band << 12), word 1 = cy. cx,cy form a
// texel position within the curve texture. On insertion the glyph is
// placed at some page texel offset; we add it to every ref.

const CURVE_LOC_X_BITS: u5 = 12;
const CURVE_LOC_X_MASK: u16 = (1 << CURVE_LOC_X_BITS) - 1;

fn rewriteBandRefs(band_words: []u16, h_band_count: u16, v_band_count: u16, base_curve_texel: u32) void {
    const header_word_count: usize = (@as(usize, h_band_count) + @as(usize, v_band_count)) * 2;
    if (band_words.len < header_word_count) return;

    var i: usize = header_word_count;
    while (i + 1 < band_words.len) : (i += 2) {
        const w0 = band_words[i];
        const w1 = band_words[i + 1];
        const first_member_band: u16 = w0 >> CURVE_LOC_X_BITS;
        const cx_orig: u32 = w0 & CURVE_LOC_X_MASK;
        const cy_orig: u32 = w1;
        const orig_texel = cy_orig * CURVE_TEX_WIDTH + cx_orig;
        const new_texel = orig_texel + base_curve_texel;
        const cx_new = new_texel % CURVE_TEX_WIDTH;
        const cy_new = new_texel / CURVE_TEX_WIDTH;
        std.debug.assert(cx_new <= CURVE_LOC_X_MASK);
        std.debug.assert(cy_new <= std.math.maxInt(u16));
        band_words[i] = @as(u16, @intCast(cx_new)) | (first_member_band << CURVE_LOC_X_BITS);
        band_words[i + 1] = @intCast(cy_new);
    }
}

pub fn extractAndLocalizeBand(src_page: *const AtlasPage, rec: AtlasRecord, out: []u16) void {
    const headers: usize = @as(usize, rec.bands.h_band_count) + @as(usize, rec.bands.v_band_count);
    const band_word_offset: usize = (@as(usize, rec.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, rec.bands.glyph_x)) * 2;

    var total_refs: u32 = 0;
    for (0..headers) |bi| {
        const r_word = src_page.band.data[band_word_offset + bi * 2];
        total_refs += r_word;
    }

    const total_words: usize = headers * 2 + @as(usize, total_refs) * 2;
    std.debug.assert(total_words == out.len);

    @memcpy(out[0 .. headers * 2], src_page.band.data[band_word_offset..][0 .. headers * 2]);
    const refs_src = src_page.band.data[band_word_offset + headers * 2 ..][0 .. total_refs * 2];
    const refs_dst = out[headers * 2 ..];
    @memcpy(refs_dst, refs_src);

    var j: usize = 0;
    while (j + 1 < refs_dst.len) : (j += 2) {
        const w0 = refs_dst[j];
        const w1 = refs_dst[j + 1];
        const first_member_band: u16 = w0 >> CURVE_LOC_X_BITS;
        const cx_orig: u32 = w0 & CURVE_LOC_X_MASK;
        const cy_orig: u32 = w1;
        const abs_texel = cy_orig * CURVE_TEX_WIDTH + cx_orig;
        std.debug.assert(abs_texel >= rec.curve_texel);
        const local_texel = abs_texel - rec.curve_texel;
        const cx_local = local_texel % CURVE_TEX_WIDTH;
        const cy_local = local_texel / CURVE_TEX_WIDTH;
        std.debug.assert(cx_local <= CURVE_LOC_X_MASK);
        refs_dst[j] = @as(u16, @intCast(cx_local)) | (first_member_band << CURVE_LOC_X_BITS);
        refs_dst[j + 1] = @intCast(cy_local);
    }
}

pub fn bandWordsForRecordIncludingRefs(src_page: *const AtlasPage, rec: AtlasRecord) u32 {
    const headers: u32 = @as(u32, rec.bands.h_band_count) + @as(u32, rec.bands.v_band_count);
    const band_word_offset: usize = (@as(usize, rec.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, rec.bands.glyph_x)) * 2;

    var total_refs: u32 = 0;
    var bi: u32 = 0;
    while (bi < headers) : (bi += 1) {
        const r_word = src_page.band.data[band_word_offset + bi * 2];
        total_refs += r_word;
    }
    return (headers + total_refs) * 2;
}
