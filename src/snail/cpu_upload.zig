//! Phase 4: CPU-side preparation cache for `PagePool` pages.
//!
//! The new `PagePool` owns the raw curve+band byte buffers; the CPU renderer
//! needs them re-encoded into f32 plus per-band-texel `PreparedAxisCurve`
//! arrays before its inner sampling loop can read them. That preparation is
//! identical to what `cpu_resources.PreparedAtlasPage.init` does for the
//! legacy `AtlasPage`; this module adapts the new page shape to that
//! existing builder so the inner sampling loop is untouched.
//!
//! `CpuPreparedPages` is owned by the caller, sized once to the pool's
//! `max_layers`, and refreshed by `upload(atlas)` per frame (rebuilds the
//! prepared cache for each layer the atlas references). Returns a `Binding`
//! identifying the (pool, generation) pair the upload produced.

const std = @import("std");

const atlas_mod = @import("atlas.zig");
const draw_records = @import("draw_records.zig");
const page_mod = @import("page.zig");
const page_pool_mod = @import("page_pool.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");
const cpu_resources = @import("render/backend/cpu/resources.zig");
const cpu_path_paint = @import("render/backend/cpu/path_paint.zig");

pub const Atlas = atlas_mod.Atlas;
pub const AtlasPage = page_mod.AtlasPage;
pub const PagePool = page_pool_mod.PagePool;
pub const Binding = draw_records.Binding;
pub const PreparedAtlasPage = cpu_resources.PreparedAtlasPage;

/// One row of the curve texture is `TEX_WIDTH * 4` u16 words (RGBA16F).
const CURVE_WORDS_PER_ROW: u32 = curve_tex.TEX_WIDTH * 4;
/// One row of the band texture is `TEX_WIDTH * 2` u16 words (RG16UI).
const BAND_WORDS_PER_ROW: u32 = band_tex.TEX_WIDTH * 2;

/// Adapter exposing a new-style `AtlasPage` through the field shape
/// `PreparedAtlasPage.init` expects (legacy `AtlasPage` layout: `curve_data`,
/// `band_data`, plus width/height pairs).
const PageView = struct {
    curve_data: []const u16,
    band_data: []const u16,
    curve_width: u32,
    curve_height: u32,
    band_width: u32,
    band_height: u32,

    fn fromPage(p: *const AtlasPage) PageView {
        const curve_words = p.curve.data.len;
        const band_words = p.band.data.len;
        std.debug.assert(curve_words % CURVE_WORDS_PER_ROW == 0);
        std.debug.assert(band_words % BAND_WORDS_PER_ROW == 0);
        return .{
            .curve_data = p.curve.data,
            .band_data = p.band.data,
            .curve_width = curve_tex.TEX_WIDTH,
            .curve_height = @intCast(curve_words / CURVE_WORDS_PER_ROW),
            .band_width = band_tex.TEX_WIDTH,
            .band_height = @intCast(band_words / BAND_WORDS_PER_ROW),
        };
    }
};

/// CPU-side prepared cache for one `PagePool`. Holds at most one
/// `PreparedAtlasPage` per pool layer, plus the source page's generation
/// used to build it (so a stale cached entry can be detected after page
/// recycling). When the bound atlas carries paint records, the cache
/// also holds a single `LayerInfoEntry` mirroring the atlas's
/// `layer_info_data` so the existing CPU special-layer dispatch can
/// resolve `samplePathPaintAt` calls without modification.
pub const CpuPreparedPages = struct {
    allocator: std.mem.Allocator,
    pool: *PagePool,
    /// Indexed by page `layer_index`. Null until first upload.
    prepared: []?PreparedAtlasPage,
    /// Generation of the underlying `AtlasPage` at the time the prepared
    /// entry was built. Used to detect stale caches after page recycling.
    prepared_generation: []u16,
    /// Source `data_len` watermarks at upload time. A later upload that
    /// finds the page extended (`data_len` grew) must rebuild the cache.
    prepared_curve_words: []u32,
    prepared_band_words: []u32,
    /// Per-upload `LayerInfoEntry` slots, indexed by `binding.generation`.
    /// Each call to `upload` appends one entry (or null when the atlas
    /// had no `layer_info_data`); drawCpu looks up `slot[binding.generation - 1]`
    /// to find the right paint-records buffer. This lets a single cache
    /// serve multiple atlases over the same pool without clobbering each
    /// other's layer_info.
    layer_info_slots: std.ArrayList(?cpu_resources.LayerInfoEntry) = .empty,
    /// Monotonically increases per upload; carried back to the caller via
    /// `Binding.generation` so segments referencing a stale upload can be
    /// detected.
    upload_generation: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, pool: *PagePool) !CpuPreparedPages {
        const layers = pool.options.max_layers;
        const prepared = try allocator.alloc(?PreparedAtlasPage, layers);
        errdefer allocator.free(prepared);
        const gen = try allocator.alloc(u16, layers);
        errdefer allocator.free(gen);
        const curve_words = try allocator.alloc(u32, layers);
        errdefer allocator.free(curve_words);
        const band_words = try allocator.alloc(u32, layers);
        errdefer allocator.free(band_words);
        @memset(prepared, null);
        @memset(gen, 0);
        @memset(curve_words, 0);
        @memset(band_words, 0);
        return .{
            .allocator = allocator,
            .pool = pool,
            .prepared = prepared,
            .prepared_generation = gen,
            .prepared_curve_words = curve_words,
            .prepared_band_words = band_words,
        };
    }

    pub fn deinit(self: *CpuPreparedPages) void {
        for (self.prepared) |*slot| {
            if (slot.*) |*p| p.deinit(self.allocator);
        }
        for (self.layer_info_slots.items) |*slot| {
            if (slot.*) |*li| li.deinit(self.allocator);
        }
        self.layer_info_slots.deinit(self.allocator);
        self.allocator.free(self.prepared);
        self.allocator.free(self.prepared_generation);
        self.allocator.free(self.prepared_curve_words);
        self.allocator.free(self.prepared_band_words);
        self.* = undefined;
    }

    /// (Re)build prepared entries for each page the atlas references. Pages
    /// whose `(generation, used_words)` haven't changed since the last
    /// upload are skipped. Also rebuilds the cached layer_info entry from
    /// the atlas's `layer_info_data`. Returns a `Binding` carrying this
    /// upload's generation; emit/draw use the binding to identify the
    /// cache state.
    pub fn upload(self: *CpuPreparedPages, atlas: *const Atlas) !Binding {
        self.upload_generation += 1;
        for (atlas.pages) |p| {
            const layer = p.layer_index;
            std.debug.assert(layer < self.prepared.len);
            const cur_gen = p.currentGeneration();
            const cur_curve = p.curve.usedWords();
            const cur_band = p.band.usedWords();
            const slot = &self.prepared[layer];
            const stale = (slot.* == null) or
                self.prepared_generation[layer] != cur_gen or
                self.prepared_curve_words[layer] != cur_curve or
                self.prepared_band_words[layer] != cur_band;
            if (!stale) continue;
            if (slot.*) |*existing| existing.deinit(self.allocator);
            slot.* = null;

            const view = PageView.fromPage(p);
            slot.* = try PreparedAtlasPage.initFromView(self.allocator, view);
            self.prepared_generation[layer] = cur_gen;
            self.prepared_curve_words[layer] = cur_curve;
            self.prepared_band_words[layer] = cur_band;
        }

        // Append (don't overwrite) a fresh LayerInfoEntry for this upload.
        // drawCpu uses `binding.generation` to index back to the right
        // slot when one cache serves multiple atlases.
        var new_slot: ?cpu_resources.LayerInfoEntry = null;
        if (atlas.layer_info_data) |src_data| {
            const owned = try self.allocator.dupe(f32, src_data);
            errdefer self.allocator.free(owned);
            // Borrow image pointers from the atlas (the Atlas guarantees
            // images outlive the upload). LayerInfoEntry.deinit frees the
            // slice but leaves images alone since `owned_images` is empty.
            const records_copy: ?[]?atlas_mod.PaintImageRecord = blk: {
                const src = atlas.paint_image_records orelse break :blk null;
                if (src.len == 0) break :blk null;
                const dst = try self.allocator.alloc(?atlas_mod.PaintImageRecord, src.len);
                @memcpy(dst, src);
                break :blk dst;
            };
            errdefer if (records_copy) |r| self.allocator.free(r);
            const prepared_records = try cpu_path_paint.preparePathLayerInfoRecords(
                self.allocator,
                owned,
                atlas.layer_info_width,
                atlas.layer_info_height,
                records_copy,
            );
            errdefer {
                self.allocator.free(prepared_records.records);
                self.allocator.free(prepared_records.layers);
            }
            new_slot = .{
                .data = owned,
                .width = atlas.layer_info_width,
                .height = atlas.layer_info_height,
                .row_base = 0,
                .path_records = prepared_records.records,
                .path_layers = prepared_records.layers,
                .owns_data = true,
                .paint_image_records = records_copy,
                .owned_images = &.{},
            };
        }
        try self.layer_info_slots.append(self.allocator, new_slot);

        return .{ .pool = self.pool, .generation = self.upload_generation };
    }

    /// Look up the layer_info entry for a given binding generation. Returns
    /// null when the atlas behind that upload had no paint records.
    pub fn layerInfoFor(self: *const CpuPreparedPages, generation: u32) ?*const cpu_resources.LayerInfoEntry {
        if (generation == 0 or generation > self.layer_info_slots.items.len) return null;
        const slot = &self.layer_info_slots.items[generation - 1];
        if (slot.*) |*li| return li;
        return null;
    }

    /// Look up the prepared page for a given pool layer. Returns null if the
    /// layer hasn't been uploaded.
    pub fn page(self: *const CpuPreparedPages, layer: u32) ?*const PreparedAtlasPage {
        if (layer >= self.prepared.len) return null;
        if (self.prepared[layer]) |*p| return p;
        return null;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const record_key_mod = @import("record_key.zig");
const curves_mod = @import("curves.zig");

test "upload builds prepared entry per atlas-referenced layer" {
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

    var entries: std.ArrayList(atlas_mod.Entry) = .empty;
    defer entries.deinit(testing.allocator);
    var owned: std.ArrayList(curves_mod.GlyphCurves) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(testing.allocator);
    }
    const gid_a = try font.glyphIndex('A');
    const curves_a = try font.extractCurves(testing.allocator, &cache, gid_a);
    try owned.append(testing.allocator, curves_a);
    try entries.append(testing.allocator, .{
        .key = record_key_mod.unhintedGlyph(0, gid_a),
        .curves = owned.items[owned.items.len - 1],
    });

    var atlas = try Atlas.from(testing.allocator, pool, entries.items);
    defer atlas.deinit();

    var prep = try CpuPreparedPages.init(testing.allocator, pool);
    defer prep.deinit();

    const b1 = try prep.upload(&atlas);
    try testing.expect(b1.pool == pool);
    try testing.expectEqual(@as(u32, 1), b1.generation);
    try testing.expect(prep.page(atlas.pages[0].layer_index) != null);

    // Second upload of an unchanged atlas bumps generation but skips rebuild.
    const b2 = try prep.upload(&atlas);
    try testing.expectEqual(@as(u32, 2), b2.generation);
}
