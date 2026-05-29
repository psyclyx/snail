//! Value-typed atlas. Holds refcounted page references plus a key→record
//! lookup table. Construction and update operations return new atlases,
//! leaving the input atlas untouched.
//!
//! See `docs/rewrite/02-atlas-and-pages.md` for the design rationale.

const std = @import("std");
const page_mod = @import("page.zig");
const page_pool_mod = @import("page_pool.zig");
const atlas_record_mod = @import("atlas_record.zig");
const record_key_mod = @import("record_key.zig");
const curves_mod = @import("curves.zig");
const curve_tex_format = @import("render/format/curve_texture.zig");
const band_tex_format = @import("render/format/band_texture.zig");
const paint_records = @import("paint_records.zig");
const paint_mod = @import("paint.zig");
const curve_atlas_mod = @import("render/format/atlas/curve.zig");

pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const AtlasRecord = atlas_record_mod.AtlasRecord;
pub const GlyphBandEntry = atlas_record_mod.GlyphBandEntry;
pub const RecordKey = record_key_mod.RecordKey;
pub const GlyphCurves = curves_mod.GlyphCurves;
pub const Paint = paint_mod.Paint;
/// Aliased to the legacy concrete type so the CPU renderer's
/// `preparePathLayerInfoRecords` (which takes this type by reference)
/// can be reused unchanged. Field shape is `{ image, texel_offset }`.
pub const PaintImageRecord = curve_atlas_mod.CurveAtlas.PaintImageRecord;

/// Lookup result for a key whose entry carries a paint. Holds the
/// (info_x, info_y) texel coordinates pointing at the layer_info record
/// in the atlas's `layer_info_data` buffer.
pub const PaintRecordInfo = struct {
    info_x: u16,
    info_y: u16,
    layer_count: u16 = 1,
};

const CURVE_TEX_WIDTH = curve_tex_format.TEX_WIDTH;
const CURVE_SEGMENT_TEXELS = curve_tex_format.SEGMENT_TEXELS;
const CURVE_SEGMENT_WORDS: u32 = CURVE_SEGMENT_TEXELS * 4;
const BAND_TEX_WIDTH = band_tex_format.TEX_WIDTH;
const BAND_TEX_WIDTH_USIZE: usize = BAND_TEX_WIDTH;

/// Pair handed to `from` / `extend` to insert one keyed shape. When
/// `paint` is non-null the atlas also allocates a layer_info record
/// for the entry and remembers (info_x, info_y) in `paint_lookup` so
/// emit can encode a special-layer instance instead of a regular one.
pub const Entry = struct {
    key: RecordKey,
    curves: GlyphCurves,
    paint: ?Paint = null,
};

pub const InsertError = std.mem.Allocator.Error || PagePool.AcquireError || error{RecordTooLargeForPage};

pub const Atlas = struct {
    allocator: std.mem.Allocator,
    /// The pool from which `pages` were allocated. `null` only on the
    /// identity atlas (`empty(allocator)`); operations that allocate pages
    /// require a non-null pool.
    pool: ?*PagePool,
    /// Refcounted page references. Index into this slice is what
    /// `AtlasRecord.page_index` refers to.
    pages: []*AtlasPage,
    lookup: std.AutoHashMapUnmanaged(RecordKey, AtlasRecord),
    /// Optional layer_info f32 buffer holding 6-texel paint records, one
    /// per entry whose `paint` was non-null. Format mirrors the legacy
    /// `paint_records` module byte-for-byte so the existing CPU sampler
    /// (`samplePathPaintAt`) consumes it unchanged.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,
    /// Per-key (info_x, info_y) lookups for paint records.
    paint_lookup: std.AutoHashMapUnmanaged(RecordKey, PaintRecordInfo) = .{},
    /// One slot per emitted paint record (in insertion order). The slot
    /// is populated only for `.image` paints — gradient/solid records map
    /// to `null`. The atlas's CPU consumer (`CpuPreparedPages.upload`)
    /// hands this to `preparePathLayerInfoRecords`; the GPU upload path
    /// patches the matching layer-info texel in place. Images themselves
    /// are caller-owned references; the atlas only borrows.
    paint_image_records: ?[]?PaintImageRecord = null,

    /// Identity atlas. Has no pool; usable as the neutral element of
    /// `combine` but not extensible on its own.
    pub fn empty(allocator: std.mem.Allocator) Atlas {
        return .{
            .allocator = allocator,
            .pool = null,
            .pages = &.{},
            .lookup = .{},
        };
    }

    pub fn deinit(self: *Atlas) void {
        if (self.pool) |pool| {
            for (self.pages) |p| pool.release(p);
        } else {
            std.debug.assert(self.pages.len == 0);
        }
        if (self.pages.len > 0) self.allocator.free(self.pages);
        if (self.layer_info_data) |d| self.allocator.free(d);
        if (self.paint_image_records) |records| self.allocator.free(records);
        self.paint_lookup.deinit(self.allocator);
        self.lookup.deinit(self.allocator);
        self.* = undefined;
    }

    /// Look up the paint record (if any) bound to `key`. Returns null
    /// for keys whose entry had no paint, or for entries that came from
    /// `empty()` / `combine` of atlases without paints.
    pub fn lookupPaintRecord(self: *const Atlas, key: RecordKey) ?PaintRecordInfo {
        return self.paint_lookup.get(key);
    }

    pub fn contains(self: *const Atlas, key: RecordKey) bool {
        return self.lookup.contains(key);
    }

    pub fn lookupRecord(self: *const Atlas, key: RecordKey) ?AtlasRecord {
        return self.lookup.get(key);
    }

    pub fn recordCount(self: *const Atlas) u32 {
        return self.lookup.count();
    }

    pub fn pageCount(self: *const Atlas) usize {
        return self.pages.len;
    }

    /// Pack the entries into a fresh atlas backed by `pool`. Existing keys
    /// in `entries` (duplicates) keep the first occurrence.
    pub fn from(
        allocator: std.mem.Allocator,
        pool: *PagePool,
        entries: []const Entry,
    ) InsertError!Atlas {
        var builder = Builder.init(allocator, pool);
        errdefer builder.abort();

        for (entries) |entry| {
            try builder.insert(entry);
        }

        return builder.finish();
    }

    /// Sugar for `combine(allocator, &.{self, from(entries)})` that avoids
    /// the intermediate allocation. The original atlas is not mutated.
    pub fn extend(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        entries: []const Entry,
    ) InsertError!Atlas {
        const pool = self.pool orelse return error.RecordTooLargeForPage; // empty atlas, can't extend
        var builder = try Builder.initFrom(allocator, pool, self);
        errdefer builder.abort();

        for (entries) |entry| {
            try builder.insert(entry);
        }

        return builder.finish();
    }

    /// Union of pages and lookups. The result references the union of pages
    /// (each retained for the new atlas) and the union of lookups; on a key
    /// collision the first occurrence in the input order wins.
    ///
    /// Asserts all non-empty inputs share the same `PagePool`.
    pub fn combine(
        allocator: std.mem.Allocator,
        atlases: []const *const Atlas,
    ) std.mem.Allocator.Error!Atlas {
        var pool: ?*PagePool = null;
        var total_records: u32 = 0;
        for (atlases) |a| {
            if (a.pool) |p| {
                if (pool == null) {
                    pool = p;
                } else {
                    std.debug.assert(pool.? == p);
                }
            }
            total_records += a.recordCount();
        }

        var page_set = std.AutoHashMapUnmanaged(*AtlasPage, u16){};
        defer page_set.deinit(allocator);

        var pages: std.ArrayList(*AtlasPage) = .empty;
        errdefer pages.deinit(allocator);

        for (atlases) |a| {
            for (a.pages) |p| {
                const gop = try page_set.getOrPut(allocator, p);
                if (!gop.found_existing) {
                    gop.value_ptr.* = @intCast(pages.items.len);
                    try pages.append(allocator, p);
                }
            }
        }

        var lookup: std.AutoHashMapUnmanaged(RecordKey, AtlasRecord) = .{};
        errdefer lookup.deinit(allocator);
        try lookup.ensureTotalCapacity(allocator, total_records);

        for (atlases) |a| {
            var it = a.lookup.iterator();
            while (it.next()) |kv| {
                if (lookup.contains(kv.key_ptr.*)) continue;
                const old_page = a.pages[kv.value_ptr.page_index];
                const new_index = page_set.get(old_page).?;
                var rec = kv.value_ptr.*;
                rec.page_index = new_index;
                lookup.putAssumeCapacity(kv.key_ptr.*, rec);
            }
        }

        // Bump refcount once per page for the new atlas.
        for (pages.items) |p| p.retain();

        return .{
            .allocator = allocator,
            .pool = pool,
            .pages = try pages.toOwnedSlice(allocator),
            .lookup = lookup,
        };
    }

    /// Rebuild the atlas with the same keys but freshly packed into the
    /// minimum number of pages. Decodes each record's curve+band bytes from
    /// its source page, re-encodes them on new pages from the same pool.
    /// The original atlas is unaffected and continues to work.
    pub fn compact(
        self: *const Atlas,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
    ) InsertError!Atlas {
        const pool = self.pool orelse return Atlas.empty(allocator);
        var builder = Builder.init(allocator, pool);
        errdefer builder.abort();

        var it = self.lookup.iterator();
        while (it.next()) |kv| {
            const rec = kv.value_ptr.*;
            const src_page = self.pages[rec.page_index];
            // Decode the band bytes from the page back to glyph-local form.
            const band_words_total = bandWordsForRecordIncludingRefs(src_page, rec);
            const local_band = try scratch.alloc(u16, band_words_total);
            defer scratch.free(local_band);
            extractAndLocalizeBand(src_page, rec, local_band);

            const curve_word_offset = rec.curve_texel * 4;
            const curve_words_total: u32 = @as(u32, rec.curve_count) * CURVE_SEGMENT_WORDS;
            const local_curves = src_page.curve.data[curve_word_offset..][0..curve_words_total];

            const curves_value = GlyphCurves{
                .allocator = scratch,
                .curve_bytes = local_curves,
                .band_bytes = local_band,
                .curve_count = rec.curve_count,
                .h_band_count = rec.bands.h_band_count,
                .v_band_count = rec.bands.v_band_count,
                .band_scale_x = rec.bands.band_scale_x,
                .band_scale_y = rec.bands.band_scale_y,
                .band_offset_x = rec.bands.band_offset_x,
                .band_offset_y = rec.bands.band_offset_y,
                .bbox = rec.bbox,
            };

            try builder.insert(.{ .key = kv.key_ptr.*, .curves = curves_value });
        }

        return builder.finish();
    }
};

// ---------------------------------------------------------------------------
// Builder: shared state for from/extend/compact. Owns refs on intermediate
// pages until finish() transfers them to the resulting Atlas, or abort()
// releases them.

const Builder = struct {
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

    fn init(allocator: std.mem.Allocator, pool: *PagePool) Builder {
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

    fn initFrom(
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

        // Carry over any layer_info / paint records from the base.
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

    fn abort(self: *Builder) void {
        for (self.pages.items) |p| self.pool.release(p);
        self.pages.deinit(self.allocator);
        self.lookup.deinit(self.allocator);
        self.layer_info_buf.deinit(self.allocator);
        self.paint_lookup.deinit(self.allocator);
        self.paint_image_records.deinit(self.allocator);
    }

    fn finish(self: *Builder) std.mem.Allocator.Error!Atlas {
        const pages_slice = try self.pages.toOwnedSlice(self.allocator);
        var layer_info_data: ?[]f32 = null;
        var layer_info_height: u32 = 0;
        if (self.layer_info_texels > 0) {
            layer_info_data = try self.layer_info_buf.toOwnedSlice(self.allocator);
            layer_info_height = (self.layer_info_texels + paint_records.info_width - 1) / paint_records.info_width;
        } else {
            self.layer_info_buf.deinit(self.allocator);
        }
        // Only carry a paint_image_records slice if any image paints were
        // emitted; otherwise drop it so consumers can shortcut on null.
        var paint_image_records: ?[]?PaintImageRecord = null;
        var has_image_paint = false;
        for (self.paint_image_records.items) |rec| {
            if (rec != null) {
                has_image_paint = true;
                break;
            }
        }
        if (has_image_paint) {
            paint_image_records = try self.paint_image_records.toOwnedSlice(self.allocator);
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
            .paint_image_records = paint_image_records,
        };
    }

    fn insertPaintRecord(self: *Builder, key: RecordKey, paint: Paint, band_entry: GlyphBandEntry) std.mem.Allocator.Error!void {
        const texel_offset = self.layer_info_texels;
        const new_texels = texel_offset + paint_records.texels_per_record;
        const need_floats = @as(usize, new_texels) * 4;
        if (self.layer_info_buf.items.len < need_floats) {
            try self.layer_info_buf.resize(self.allocator, need_floats);
            @memset(self.layer_info_buf.items[texel_offset * 4 .. need_floats], 0);
        }
        // paint_records.write expects band_texture.GlyphBandEntry; copy the
        // field-shape-identical local type across.
        const band_tex_entry = band_tex_format.GlyphBandEntry{
            .glyph_x = band_entry.glyph_x,
            .glyph_y = band_entry.glyph_y,
            .h_band_count = band_entry.h_band_count,
            .v_band_count = band_entry.v_band_count,
            .band_scale_x = band_entry.band_scale_x,
            .band_scale_y = band_entry.band_scale_y,
            .band_offset_x = band_entry.band_offset_x,
            .band_offset_y = band_entry.band_offset_y,
        };
        paint_records.write(self.layer_info_buf.items, paint_records.info_width, texel_offset, band_tex_entry, paint);
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

    fn insert(self: *Builder, entry: Entry) InsertError!void {
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

        const curve_words: u32 = @intCast(curves.curve_bytes.len);
        const band_words: u32 = @intCast(curves.band_bytes.len);
        std.debug.assert(curve_words % CURVE_SEGMENT_WORDS == 0);
        std.debug.assert(curve_words / CURVE_SEGMENT_WORDS == curves.curve_count);

        if (curve_words > self.pool.options.curve_words_per_page or
            band_words > self.pool.options.band_words_per_page)
        {
            return error.RecordTooLargeForPage;
        }

        // Try the tail page first; if it can't fit, acquire a fresh one.
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

        // Curve buffer: copy verbatim.
        page.writeCurve(reservation.curve_word_offset, curves.curve_bytes);

        // Band buffer: copy with curve-ref rewrite to absolute page texels.
        std.debug.assert(reservation.curve_word_offset % 4 == 0);
        const base_curve_texel = reservation.curve_word_offset / 4;

        // Scratch-write into the page directly, then patch in place.
        page.writeBand(reservation.band_word_offset, curves.band_bytes);
        const band_slice = page.band.data[reservation.band_word_offset..][0..band_words];
        rewriteBandRefs(band_slice, curves.h_band_count, curves.v_band_count, base_curve_texel);

        std.debug.assert(reservation.band_word_offset % 2 == 0);
        const band_texel = reservation.band_word_offset / 2;

        const record = AtlasRecord{
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
            .bbox = curves.bbox,
        };

        try self.lookup.put(self.allocator, entry.key, record);

        // If the entry carries a paint, allocate a layer_info record now.
        // The paint record embeds the band_entry so the rasterizer's
        // special-layer path can sample the same curves through it.
        if (entry.paint) |paint| {
            try self.insertPaintRecord(entry.key, paint, record.bands);
        }
    }
};

// ---------------------------------------------------------------------------
// Band-ref rewriting. The band format stores each curve reference as two
// u16 words: word 0 = (cx | first_member_band << 12), word 1 = cy. Where
// cx,cy form a texel position within the curve texture. On insertion the
// glyph is placed at some page texel offset; we add it to every ref.

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

fn extractAndLocalizeBand(src_page: *const AtlasPage, rec: AtlasRecord, out: []u16) void {
    const headers: usize = @as(usize, rec.bands.h_band_count) + @as(usize, rec.bands.v_band_count);
    const band_word_offset: usize = (@as(usize, rec.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, rec.bands.glyph_x)) * 2;

    // Sum up the index counts from the header section to determine ref count.
    var total_refs: u32 = 0;
    for (0..headers) |bi| {
        const r_word = src_page.band.data[band_word_offset + bi * 2];
        total_refs += r_word;
    }

    const total_words: usize = headers * 2 + @as(usize, total_refs) * 2;
    std.debug.assert(total_words == out.len);

    // Copy headers verbatim.
    @memcpy(out[0 .. headers * 2], src_page.band.data[band_word_offset..][0 .. headers * 2]);
    // Copy refs and rebase them back to glyph-local (curve_texel = 0).
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

fn bandWordsForRecordIncludingRefs(src_page: *const AtlasPage, rec: AtlasRecord) u32 {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn makeTestCurves(allocator: std.mem.Allocator) !GlyphCurves {
    // Two curve segments, one h-band, one v-band, two refs (one per band,
    // pointing at curve indices 0 and 1).
    const curve_words = 2 * CURVE_SEGMENT_WORDS;
    const curve_bytes = try allocator.alloc(u16, curve_words);
    for (curve_bytes, 0..) |*w, i| w.* = @intCast(@as(u16, @intCast(i)) +% 0x1000);

    // band header = 1 h-band + 1 v-band = 2 texels = 4 u16.
    // band refs = 2 refs per band * 2 bands = 4 texels = 8 u16. Plus 4
    // header words.
    const band_bytes = try allocator.alloc(u16, 12);
    band_bytes[0] = 2; // h-band 0 count
    band_bytes[1] = 2; // h-band 0 offset (from glyph_loc, in texels) = 2
    band_bytes[2] = 2; // v-band 0 count
    band_bytes[3] = 4; // v-band 0 offset = 4

    // h-band refs at curve texel 0 and 4 (i.e., curve 0 and curve 1).
    band_bytes[4] = 0; // cx=0, first_member_band=0
    band_bytes[5] = 0; // cy=0
    band_bytes[6] = 4; // cx=4
    band_bytes[7] = 0;
    // v-band refs (same).
    band_bytes[8] = 0;
    band_bytes[9] = 0;
    band_bytes[10] = 4;
    band_bytes[11] = 0;

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = 2,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
        .bbox = .{ .min = .zero, .max = .{ .x = 8, .y = 4 } },
    };
}

test "from packs entries into pages and records lookup" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);
    const entries = [_]Entry{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    };

    var atlas = try Atlas.from(testing.allocator, pool, &entries);
    defer atlas.deinit();

    try testing.expectEqual(@as(u32, 2), atlas.recordCount());
    try testing.expect(atlas.contains(k0));
    try testing.expect(atlas.contains(k1));

    // Two glyphs of 2 curves each (32 words/glyph) -> 64 curve words used.
    try testing.expectEqual(@as(usize, 1), atlas.pageCount());

    const r0 = atlas.lookupRecord(k0).?;
    const r1 = atlas.lookupRecord(k1).?;
    try testing.expectEqual(@as(u16, 0), r0.page_index);
    try testing.expectEqual(@as(u16, 0), r1.page_index);
    try testing.expect(r0.curve_texel < r1.curve_texel);
    try testing.expectEqual(@as(u16, 2), r0.curve_count);
}

test "from rewrites band refs to page-absolute texels" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);

    var atlas = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    });
    defer atlas.deinit();

    const r1 = atlas.lookupRecord(k1).?;
    const page = atlas.pages[r1.page_index];
    const band_word_offset = (@as(usize, r1.bands.glyph_y) * BAND_TEX_WIDTH_USIZE + @as(usize, r1.bands.glyph_x)) * 2;
    // The first h-band ref (4 header words in, so index 4) should point at r1.curve_texel.
    const ref_w0 = page.band.data[band_word_offset + 4];
    const ref_w1 = page.band.data[band_word_offset + 5];
    const cx = ref_w0 & CURVE_LOC_X_MASK;
    const cy: u32 = ref_w1;
    const decoded = cy * CURVE_TEX_WIDTH + cx;
    try testing.expectEqual(r1.curve_texel, decoded);
}

test "combine merges pages and lookups, first key wins" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k_shared = record_key_mod.unhintedGlyph(0, 2);

    var a = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k_shared, .curves = c0 },
    });
    defer a.deinit();

    var c2 = try makeTestCurves(testing.allocator);
    defer c2.deinit();
    const k1 = record_key_mod.unhintedGlyph(0, 3);
    var b = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k_shared, .curves = c2 }, // conflicting key
        .{ .key = k1, .curves = c1 },
    });
    defer b.deinit();

    var combined = try Atlas.combine(testing.allocator, &.{ &a, &b });
    defer combined.deinit();

    try testing.expectEqual(@as(u32, 3), combined.recordCount());
    try testing.expect(combined.contains(k0));
    try testing.expect(combined.contains(k_shared));
    try testing.expect(combined.contains(k1));

    // First-occurrence-wins: shared key resolves to A's record (same
    // curve_texel as in A).
    const shared_in_a = a.lookupRecord(k_shared).?;
    const shared_combined = combined.lookupRecord(k_shared).?;
    try testing.expectEqual(shared_in_a.curve_texel, shared_combined.curve_texel);

    // page_index is remapped to the combined atlas's pages slice.
    try testing.expect(shared_combined.page_index < combined.pages.len);
    try testing.expect(combined.pages[shared_combined.page_index] == a.pages[shared_in_a.page_index]);
}

test "combine with empty atlas is identity" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
    defer a.deinit();

    var empty = Atlas.empty(testing.allocator);
    defer empty.deinit();

    var combined = try Atlas.combine(testing.allocator, &.{ &a, &empty });
    defer combined.deinit();
    try testing.expectEqual(@as(u32, 1), combined.recordCount());
    try testing.expect(combined.contains(k0));
}

test "extend keeps original atlas valid" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
    defer a.deinit();

    const k1 = record_key_mod.unhintedGlyph(0, 2);
    var b = try a.extend(testing.allocator, &.{.{ .key = k1, .curves = c1 }});
    defer b.deinit();

    try testing.expect(a.contains(k0));
    try testing.expect(!a.contains(k1));
    try testing.expect(b.contains(k0));
    try testing.expect(b.contains(k1));
    try testing.expectEqual(@as(u32, 1), a.recordCount());
    try testing.expectEqual(@as(u32, 2), b.recordCount());

    // The original atlas's record for k0 references a page that's still
    // alive (b retained it).
    try testing.expectEqual(@as(u32, 2), a.pages[0].refcount.load(.acquire));
}

test "extend dedups keys against existing atlas" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);
    var a = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
    defer a.deinit();

    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();
    var b = try a.extend(testing.allocator, &.{
        .{ .key = k0, .curves = c1 }, // conflict — existing wins
    });
    defer b.deinit();

    try testing.expectEqual(@as(u32, 1), b.recordCount());
    const old_rec = a.lookupRecord(k0).?;
    const new_rec = b.lookupRecord(k0).?;
    try testing.expectEqual(old_rec.curve_texel, new_rec.curve_texel);
}

test "deinit releases pages back to the pool" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    const k0 = record_key_mod.unhintedGlyph(0, 1);

    {
        var atlas = try Atlas.from(testing.allocator, pool, &.{.{ .key = k0, .curves = c0 }});
        defer atlas.deinit();
        try testing.expectError(error.OutOfLayers, pool.acquire());
    }
    // Atlas has been deinit'd; pool should be drained again.
    const reacquired = try pool.acquire();
    pool.release(reacquired);
}

test "atlas + font extract: end-to-end smoke test" {
    const font_mod = @import("font.zig");
    const font_data = @import("assets").noto_sans_regular;
    var font = try font_mod.Font.init(font_data);
    defer font.deinit();

    var cache = font_mod.GlyphCache.init(testing.allocator);
    defer cache.deinit();

    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(testing.allocator);

    var owned: std.ArrayList(GlyphCurves) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(testing.allocator);
    }

    const codes = [_]u32{ 'A', 'B', 'C', 'M', 'a', 'g', 'o' };
    for (codes) |cp| {
        const gid = try font.glyphIndex(cp);
        const curves = try font.extractCurves(testing.allocator, &cache, gid);
        try owned.append(testing.allocator, curves);
        try entries.append(testing.allocator, .{
            .key = record_key_mod.unhintedGlyph(0, gid),
            .curves = owned.items[owned.items.len - 1],
        });
    }

    var atlas = try Atlas.from(testing.allocator, pool, entries.items);
    defer atlas.deinit();

    try testing.expectEqual(@as(u32, codes.len), atlas.recordCount());
    for (codes) |cp| {
        const gid = try font.glyphIndex(cp);
        const key = record_key_mod.unhintedGlyph(0, gid);
        const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
        try testing.expect(rec.curve_count > 0);
    }
}

test "compact preserves keys" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var c0 = try makeTestCurves(testing.allocator);
    defer c0.deinit();
    var c1 = try makeTestCurves(testing.allocator);
    defer c1.deinit();

    const k0 = record_key_mod.unhintedGlyph(0, 1);
    const k1 = record_key_mod.unhintedGlyph(0, 2);
    var original = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = k0, .curves = c0 },
        .{ .key = k1, .curves = c1 },
    });
    defer original.deinit();

    var compacted = try original.compact(testing.allocator, testing.allocator);
    defer compacted.deinit();

    try testing.expectEqual(original.recordCount(), compacted.recordCount());
    try testing.expect(compacted.contains(k0));
    try testing.expect(compacted.contains(k1));

    // Compaction lays records out into fresh pages from the pool, so
    // bbox/metadata round-trip but curve_texel may differ.
    const orig_r0 = original.lookupRecord(k0).?;
    const comp_r0 = compacted.lookupRecord(k0).?;
    try testing.expectEqual(orig_r0.curve_count, comp_r0.curve_count);
    try testing.expectEqual(orig_r0.bands.h_band_count, comp_r0.bands.h_band_count);
    try testing.expectEqual(orig_r0.bands.v_band_count, comp_r0.bands.v_band_count);
}
