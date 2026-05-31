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
const curve_tex_format = @import("../render/format/curve_texture.zig");
const band_tex_format = @import("../render/format/band_texture.zig");
const paint_records = @import("paint_records.zig");
const paint_mod = @import("../paint.zig");
const target_mod = @import("../target.zig");

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

const CURVE_TEX_WIDTH = curve_tex_format.TEX_WIDTH;
const CURVE_SEGMENT_TEXELS = curve_tex_format.SEGMENT_TEXELS;
const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * 4;
const BAND_TEX_WIDTH = band_tex_format.TEX_WIDTH;
const BAND_TEX_WIDTH_USIZE: usize = BAND_TEX_WIDTH;

pub const Builder = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    pages: std.ArrayList(*AtlasPage),
    lookup: std.AutoHashMapUnmanaged(RecordKey, AtlasRecord),
    layer_info_buf: std.ArrayList(f32),
    layer_info_texels: u32,
    paint_lookup: std.AutoHashMapUnmanaged(RecordKey, PaintRecordInfo),
    /// Per-record slot for image paints. Indexed in insertion order;
    /// non-image paints land as `null`. Empty when no paints emitted.
    paint_image_records: std.ArrayList(?PaintImageRecord),

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) Builder {
        return .{
            .allocator = allocator,
            .pool = pool,
            .pages = .empty,
            .lookup = .{},
            .layer_info_buf = .empty,
            .layer_info_texels = 0,
            .paint_lookup = .{},
            .paint_image_records = .empty,
        };
    }

    pub fn initFrom(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        base: *const Atlas,
    ) std.mem.Allocator.Error!Builder {
        var b = Builder.init(allocator, pool);
        errdefer b.abort();

        try b.pages.ensureTotalCapacity(allocator, base.pages.len);
        for (base.pages) |p| {
            p.retain();
            b.pages.appendAssumeCapacity(p);
        }

        try b.lookup.ensureTotalCapacity(allocator, base.recordCount());
        var it = base.lookup.iterator();
        while (it.next()) |kv| {
            b.lookup.putAssumeCapacity(kv.key_ptr.*, kv.value_ptr.*);
        }

        if (base.layer_info_data) |src| {
            try b.layer_info_buf.appendSlice(allocator, src);
            b.layer_info_texels = @intCast(src.len / 4);
        }
        try b.paint_lookup.ensureTotalCapacity(allocator, base.paint_lookup.count());
        var pit = base.paint_lookup.iterator();
        while (pit.next()) |kv| b.paint_lookup.putAssumeCapacity(kv.key_ptr.*, kv.value_ptr.*);

        if (base.paint_image_records) |src| {
            try b.paint_image_records.appendSlice(allocator, src);
        }
        return b;
    }

    pub fn abort(self: *Builder) void {
        for (self.pages.items) |p| self.pool.release(p);
        self.pages.deinit(self.allocator);
        self.lookup.deinit(self.allocator);
        self.layer_info_buf.deinit(self.allocator);
        self.paint_lookup.deinit(self.allocator);
        self.paint_image_records.deinit(self.allocator);
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

        page.writeCurve(reservation.curve_word_offset, curves.curve_bytes);

        std.debug.assert(reservation.curve_word_offset % 4 == 0);
        const base_curve_texel = reservation.curve_word_offset / 4;

        page.writeBand(reservation.band_word_offset, curves.band_bytes);
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
        base_fill_rule: target_mod.FillRule,
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

        try self.paint_lookup.put(self.allocator, key, .{
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
        fill_rule: target_mod.FillRule,
    ) std.mem.Allocator.Error!void {
        const band_tex_entry = bandToTexFormat(bands);
        const rule_bit: u16 = if (fill_rule == .even_odd) paint_records.FILL_RULE_BIT else 0;
        paint_records.write(self.layer_info_buf.items, paint_records.info_width, layer_texel, band_tex_entry, paint, rule_bit);
        try self.paint_image_records.append(self.allocator, switch (paint) {
            .image => |img| .{ .image = img.image, .texel_offset = layer_texel },
            else => null,
        });
    }

    fn insertPaintRecord(self: *Builder, key: RecordKey, paint: Paint, band_entry: GlyphBandEntry, fill_rule: target_mod.FillRule) std.mem.Allocator.Error!void {
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
        try self.paint_lookup.put(self.allocator, key, .{
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

        const curves = entry.curves;

        if (curves.isEmpty()) {
            try self.lookup.put(self.allocator, entry.key, .{
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
            .bbox = bbox,
        };

        try self.lookup.put(self.allocator, entry.key, record);

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
};

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
