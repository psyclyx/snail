//! Immutable text-atlas snapshots with structural sharing.
//!
//! `snail.TextAtlas` is the public API name for this type. It manages multiple
//! font faces with style-specific and global fallback chains, a shared glyph
//! atlas, and automatic text itemization. Extending the atlas returns a new
//! immutable snapshot; the old snapshot remains valid for in-flight readers and
//! for other renderers that still reference it.

const std = @import("std");
const snail = @import("root.zig");
const ttf = @import("font/ttf.zig");
const opentype = @import("font/opentype.zig");
const glyph_emit = @import("glyph_emit.zig");
const paint_mod = @import("paint.zig");
const paint_records = @import("paint_records.zig");
const build_options = @import("build_options");
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const Allocator = std.mem.Allocator;
const AtlasPage = snail.lowlevel.AtlasPage;
const GlyphInfo = snail.lowlevel.CurveAtlas.GlyphInfo;
const ColrBaseInfo = snail.lowlevel.CurveAtlas.ColrBaseInfo;
const TextBatch = snail.lowlevel.TextBatch;
const bezier = @import("math/bezier.zig");
const band_tex = @import("renderer/band_texture.zig");

// ── Public types ──

pub const FaceIndex = u16;

pub const FaceSpec = struct {
    data: []const u8,
    weight: snail.FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: snail.SyntheticStyle = .{},
};

pub const TextPlacement = struct {
    baseline: snail.Vec2,
    em: f32,
};

pub const TextAppend = struct {
    shaped: *const ShapedText,
    glyphs: snail.Range = .{},
    placement: TextPlacement,
    fill: snail.Paint,
};

pub const TextAppendResult = struct {
    advance: snail.Vec2,
    missing: bool,
};

pub const TextBatchAppend = struct {
    shaped: *const ShapedText,
    glyphs: snail.Range = .{},
    placement: TextPlacement,
    color: [4]f32,
};

pub const CellMetricsOptions = struct {
    style: snail.FontStyle = .{},
    em: f32,
};

pub const CellMetrics = struct {
    cell_width: f32,
    line_height: f32,
};

pub const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

pub const ScriptTransform = struct {
    x: f32,
    y: f32,
    font_size: f32,
};

fn preparedViewLayerBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "layer_base")) view.layer_base else 0,
        else => 0,
    };
}

fn preparedViewInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "info_row_base")) view.info_row_base else 0,
        else => 0,
    };
}

fn preparedViewPaintInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "paint_info_row_base")) view.paint_info_row_base else 0,
        else => 0,
    };
}

pub const ShapedText = struct {
    allocator: Allocator,
    atlas_identity: u64,
    config: *const FontConfig,
    glyphs: []Glyph,
    advance_x: f32,
    advance_y: f32,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        x_offset: f32,
        y_offset: f32,
        x_advance: f32,
        y_advance: f32,
        source_start: u32,
        source_end: u32,
    };

    pub fn deinit(self: *ShapedText) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const TextBlob = struct {
    allocator: Allocator,
    /// Borrowed TextAtlas snapshot used to build this blob. The pointer and
    /// snapshot identity must remain valid until the blob is destroyed or
    /// `rebind` moves the blob to a compatible atlas snapshot.
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []Glyph,
    paint_layer_info_data: ?[]f32 = null,
    paint_layer_info_width: u32 = 0,
    paint_layer_info_height: u32 = 0,
    paint_image_records: ?[]?snail.lowlevel.CurveAtlas.PaintImageRecord = null,
    /// Upper bound on GPU vertex-output instances this blob will emit
    /// (counts COLR layer fan-out and synthetic-bold duplication). Used to
    /// size scratch buffers in `DrawList.estimate`.
    gpu_instance_budget: usize,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        transform: snail.Transform2D,
        embolden: f32,
        color: [4]f32,
        paint_record_index: ?u32 = null,
    };

    pub fn deinit(self: *TextBlob) void {
        self.allocator.free(self.glyphs);
        if (self.paint_layer_info_data) |data| self.allocator.free(data);
        if (self.paint_image_records) |records| self.allocator.free(records);
        self.* = undefined;
    }

    pub fn glyphCount(self: *const TextBlob) usize {
        return self.glyphs.len;
    }

    pub fn validateExact(self: *const TextBlob) !void {
        if (self.atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn validate(self: *const TextBlob) !void {
        try self.validateExact();
    }

    pub fn hasPaintRecords(self: *const TextBlob) bool {
        return self.paint_layer_info_data != null;
    }

    fn paintRecordLoc(self: *const TextBlob, record_index: u32) struct { x: u16, y: u16 } {
        const texel_offset = record_index * paint_records.texels_per_record;
        return .{
            .x = @intCast(texel_offset % self.paint_layer_info_width),
            .y = @intCast(texel_offset / self.paint_layer_info_width),
        };
    }

    /// Move this blob to a compatible atlas snapshot without rebuilding its
    /// glyph list. The new atlas must share the same font config, retain the
    /// old pages as a prefix, and contain every glyph referenced by the blob.
    pub fn rebind(self: *TextBlob, new_atlas: *const TextAtlas) !void {
        if (!new_atlas.canRebindFrom(self.atlas)) return error.WrongTextAtlasSnapshot;

        for (self.glyphs) |glyph| {
            if (!new_atlas.hasPreparedGlyph(glyph.face_index, glyph.glyph_id)) return error.MissingPreparedGlyph;
        }

        self.atlas = new_atlas;
        self.atlas_identity = new_atlas.snapshotIdentity();
        self.gpu_instance_budget = textBlobGpuInstanceBudgetForAtlas(new_atlas, self.glyphs);
    }

    pub fn init(
        allocator: Allocator,
        atlas: *const TextAtlas,
        append: TextAppend,
    ) !TextBlob {
        var builder = TextBlobBuilder.init(allocator, atlas);
        errdefer builder.deinit();
        _ = try atlas.appendShapedTextBlob(&builder, append, false);
        return builder.finish();
    }
};

/// Implementation of `TextBatch.addDraw`: emits one slice of a `TextDraw`
/// into `batch`. Lives here because the per-glyph layer-window walk uses
/// `FaceView` internals.
pub fn appendTextDrawIntoBatch(
    batch: *TextBatch,
    view: anytype,
    draw: snail.TextDraw,
    override_index: usize,
    start_glyph: usize,
) !TextBatch.AppendResult {
    const blob = draw.blob;
    try blob.validate();
    const range = draw.glyphs.resolve(blob.glyphs.len);
    const start = @max(start_glyph, range.start);
    if (start > range.end) return error.InvalidGlyphRange;
    if (override_index >= draw.instances.len) return error.InvalidOverrideIndex;
    const override = draw.instances[override_index];
    const has_outer_transform = !isIdentityTransform(override.transform);
    const paint_info_row_base = preparedViewPaintInfoRowBase(view);

    var count: usize = 0;
    var glyph_index = start;
    while (glyph_index < range.end) : (glyph_index += 1) {
        const glyph = blob.glyphs[glyph_index];
        const face_view = blob.atlas.faceView(glyph.face_index, view);
        const glyph_layer_base = try textBlobGlyphLayerWindowBase(&face_view, glyph.glyph_id) orelse continue;
        if (batch.layer_window_base) |base| {
            if (base != glyph_layer_base) break;
        } else {
            batch.layer_window_base = glyph_layer_base;
        }

        var final_transform = glyph.transform;
        if (has_outer_transform) {
            final_transform = snail.Transform2D.multiply(override.transform, final_transform);
        }
        if (glyph.paint_record_index) |record_index| {
            try emitPaintedBlobGlyph(batch, blob, &face_view, glyph.glyph_id, record_index, paint_info_row_base, override.tint, final_transform);
            count += 1;
        } else {
            switch (glyph_emit.emitGlyphWithTransformTinted(batch, &face_view, glyph.glyph_id, glyph.color, override.tint, final_transform)) {
                .emitted => count += 1,
                .skipped => {},
                .buffer_full => return error.DrawListFull,
                .layer_window_changed => break,
                .invalid_transform => return error.InvalidTransform,
            }
        }

        if (glyph.embolden != 0) {
            var bold_transform = glyph.transform;
            bold_transform.tx += glyph.embolden;
            if (has_outer_transform) {
                bold_transform = snail.Transform2D.multiply(override.transform, bold_transform);
            }
            if (glyph.paint_record_index) |record_index| {
                try emitPaintedBlobGlyph(batch, blob, &face_view, glyph.glyph_id, record_index, paint_info_row_base, override.tint, bold_transform);
            } else {
                switch (glyph_emit.emitGlyphWithTransformTinted(batch, &face_view, glyph.glyph_id, glyph.color, override.tint, bold_transform)) {
                    .emitted, .skipped => {},
                    .buffer_full => return error.DrawListFull,
                    .layer_window_changed => return error.GlyphSpansTextureLayerWindows,
                    .invalid_transform => return error.InvalidTransform,
                }
            }
        }
    }
    return .{
        .emitted = count,
        .next_glyph = glyph_index,
        .completed = glyph_index >= range.end,
        .layer_window_base = batch.currentLayerWindowBase(),
    };
}

fn emitPaintedBlobGlyph(
    batch: *TextBatch,
    blob: *const TextBlob,
    face_view: *const FaceView,
    glyph_id: u16,
    record_index: u32,
    paint_info_row_base: u32,
    tint: [4]f32,
    transform: snail.Transform2D,
) !void {
    const info = face_view.getGlyph(glyph_id) orelse return;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return;
    const loc = blob.paintRecordLoc(record_index);
    const info_y = paint_info_row_base + loc.y;
    if (info_y > std.math.maxInt(u16)) return error.LayerInfoLimitExceeded;
    try batch.addPathRecordTransformedTinted(
        info.bbox,
        loc.x,
        @intCast(info_y),
        1,
        .{ 1, 1, 1, 1 },
        tint,
        face_view.glyphLayer(info.page_index),
        transform,
    );
}

fn textBlobGlyphLayerWindowBase(view: *const FaceView, glyph_id: u16) !?u32 {
    if (view.getColrBase(glyph_id)) |cbi| {
        return view.glyphLayerWindowBase(cbi.page_index);
    }

    var layer_it = view.colrLayers(glyph_id);
    var base: ?u32 = null;
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = view.getGlyph(layer.glyph_id) orelse continue;
            if (linfo.band_entry.h_band_count == 0 or linfo.band_entry.v_band_count == 0) continue;
            const layer_base = view.glyphLayerWindowBase(linfo.page_index);
            if (base) |existing| {
                if (existing != layer_base) return error.GlyphSpansTextureLayerWindows;
            } else {
                base = layer_base;
            }
        }
        return base;
    }

    const info = view.getGlyph(glyph_id) orelse return null;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return null;
    return view.glyphLayerWindowBase(info.page_index);
}

pub const TextBlobBuilder = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    glyphs: std.ArrayListUnmanaged(TextBlob.Glyph) = .empty,
    paint_records: std.ArrayListUnmanaged(PendingPaintRecord) = .empty,
    gpu_instance_budget: usize = 0,

    const PendingPaintRecord = struct {
        band_entry: band_tex.GlyphBandEntry,
        paint: snail.Paint,
    };

    pub fn init(allocator: Allocator, atlas: *const TextAtlas) TextBlobBuilder {
        return .{
            .allocator = allocator,
            .atlas = atlas,
        };
    }

    pub fn deinit(self: *TextBlobBuilder) void {
        self.glyphs.deinit(self.allocator);
        self.paint_records.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *TextBlobBuilder) void {
        self.glyphs.clearRetainingCapacity();
        self.paint_records.clearRetainingCapacity();
        self.gpu_instance_budget = 0;
    }

    pub fn glyphCount(self: *const TextBlobBuilder) usize {
        return self.glyphs.items.len;
    }

    pub fn finish(self: *TextBlobBuilder) !TextBlob {
        const owned = try self.glyphs.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        const paint_info = try self.finishPaintRecords();
        errdefer if (paint_info.data) |data| self.allocator.free(data);
        errdefer if (paint_info.image_records) |records| self.allocator.free(records);
        const gpu_instance_budget = self.gpu_instance_budget;
        self.glyphs = .empty;
        self.gpu_instance_budget = 0;
        return .{
            .allocator = self.allocator,
            .atlas = self.atlas,
            .atlas_identity = self.atlas.snapshotIdentity(),
            .glyphs = owned,
            .paint_layer_info_data = paint_info.data,
            .paint_layer_info_width = paint_info.width,
            .paint_layer_info_height = paint_info.height,
            .paint_image_records = paint_info.image_records,
            .gpu_instance_budget = gpu_instance_budget,
        };
    }

    pub fn append(self: *TextBlobBuilder, text_append: TextAppend) !TextAppendResult {
        return self.atlas.appendShapedTextBlob(self, text_append, true);
    }

    const FinishedPaintRecords = struct {
        data: ?[]f32 = null,
        width: u32 = 0,
        height: u32 = 0,
        image_records: ?[]?snail.lowlevel.CurveAtlas.PaintImageRecord = null,
    };

    fn finishPaintRecords(self: *TextBlobBuilder) !FinishedPaintRecords {
        const count = self.paint_records.items.len;
        if (count == 0) return .{};

        const texel_count: u32 = @intCast(count * paint_records.texels_per_record);
        const width = paint_records.infoWidth(texel_count);
        const height = @max(@as(u32, 1), (texel_count + width - 1) / width);
        const data = try self.allocator.alloc(f32, @as(usize, width) * @as(usize, height) * 4);
        errdefer self.allocator.free(data);
        @memset(data, 0);

        const image_records = try self.allocator.alloc(?snail.lowlevel.CurveAtlas.PaintImageRecord, count);
        errdefer self.allocator.free(image_records);
        @memset(image_records, null);
        var has_image_paints = false;

        for (self.paint_records.items, 0..) |record, i| {
            const texel_offset: u32 = @intCast(i * paint_records.texels_per_record);
            paint_records.write(data, width, texel_offset, record.band_entry, record.paint);
            switch (record.paint) {
                .image => |image_paint| {
                    image_records[i] = .{
                        .image = image_paint.image,
                        .texel_offset = texel_offset,
                    };
                    has_image_paints = true;
                },
                else => {},
            }
        }
        self.paint_records.clearRetainingCapacity();

        return .{
            .data = data,
            .width = width,
            .height = height,
            .image_records = if (has_image_paints) image_records else blk: {
                self.allocator.free(image_records);
                break :blk null;
            },
        };
    }
};

pub const Decoration = enum {
    underline,
    strikethrough,
};

// ── Internal types ──

/// Immutable font configuration shared across snapshots via refcount.
/// Created once during TextAtlas.init, never modified.
pub const FontConfig = struct {
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    allocator: Allocator,
    faces: []FaceConfig,
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: []FaceIndex,
    primary_face: ?FaceIndex,

    pub fn retain(self: *FontConfig) *FontConfig {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *FontConfig) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) {
            const allocator = self.allocator;
            for (self.faces) |*fc| fc.deinit();
            allocator.free(self.faces);

            var it = self.style_chains.iterator();
            while (it.next()) |entry| entry.value_ptr.deinit(allocator);
            self.style_chains.deinit(allocator);

            allocator.free(self.global_chain);
            allocator.destroy(self);
        }
    }
};

/// Per-face immutable data: parsed font, shapers, style metadata.
pub const FaceConfig = struct {
    font: ttf.Font,
    font_data: []const u8,
    weight: snail.FontWeight,
    italic: bool,
    synthetic: snail.SyntheticStyle,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,
    owns_shapers: bool, // false when sharing with another face (dedup)

    fn deinit(self: *FaceConfig) void {
        if (!self.owns_shapers) return;
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

/// Per-face, per-snapshot glyph data. Rebuilt when the atlas is extended.
pub const FaceGlyphData = struct {
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null,
    /// Parallel presence bitset for `glyph_lut`: bit `gid` is set iff `glyph_map`
    /// has an entry for `gid`. Required because a present-but-empty glyph (e.g.
    /// space, with `h_band_count == 0`) is indistinguishable in the LUT from an
    /// absent gid that landed in the zero-initialised slot.
    glyph_lut_present: ?[]u64 = null,
    glyph_lut_len: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,

    fn deinit(self: *FaceGlyphData, allocator: Allocator) void {
        self.glyph_map.deinit();
        if (self.glyph_lut) |lut| allocator.free(lut);
        if (self.glyph_lut_present) |bits| allocator.free(bits);
        if (self.colr_base_map) |*cbm| cbm.deinit();
    }

    fn clone(self: *const FaceGlyphData, allocator: Allocator) !FaceGlyphData {
        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        var colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null;
        if (self.colr_base_map) |cbm| {
            colr_base_map = std.AutoHashMap(u16, ColrBaseInfo).init(allocator);
            var cit = cbm.iterator();
            while (cit.next()) |entry| try colr_base_map.?.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var result = FaceGlyphData{
            .glyph_map = glyph_map,
            .colr_base_map = colr_base_map,
        };
        try result.buildGlyphLut(allocator);
        return result;
    }

    pub fn getGlyph(self: *const FaceGlyphData, gid: u16) ?GlyphInfo {
        if (self.glyph_lut) |lut| {
            if (gid >= self.glyph_lut_len) return null;
            if (self.glyph_lut_present) |bits| {
                const word = bits[gid >> 6];
                if ((word >> @intCast(gid & 63)) & 1 == 0) return null;
            }
            return lut[gid];
        }
        return self.glyph_map.get(gid);
    }

    fn buildGlyphLut(self: *FaceGlyphData, allocator: Allocator) !void {
        if (self.glyph_lut) |lut| allocator.free(lut);
        self.glyph_lut = null;
        if (self.glyph_lut_present) |bits| allocator.free(bits);
        self.glyph_lut_present = null;
        self.glyph_lut_len = 0;

        if (self.glyph_map.count() == 0) return;

        var max_gid: u32 = 0;
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* > max_gid) max_gid = entry.key_ptr.*;
        }

        const size = max_gid + 1;
        const lut = try allocator.alloc(GlyphInfo, size);
        errdefer allocator.free(lut);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        const word_count = (size + 63) / 64;
        const present = try allocator.alloc(u64, word_count);
        @memset(present, 0);

        it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            const gid = entry.key_ptr.*;
            lut[gid] = entry.value_ptr.*;
            present[gid >> 6] |= @as(u64, 1) << @intCast(gid & 63);
        }

        self.glyph_lut = lut;
        self.glyph_lut_present = present;
        self.glyph_lut_len = @intCast(size);
    }
};

/// View into one face's glyph data within a TextAtlas snapshot.
/// Implements the interface expected by glyph_emit.emitGlyph.
pub const FaceView = struct {
    face_glyphs: *const FaceGlyphData,
    face_config: *const FaceConfig,
    layer_base: u32,
    info_row_base: u32,

    pub fn getGlyph(self: *const FaceView, gid: u16) ?GlyphInfo {
        return self.face_glyphs.getGlyph(gid);
    }

    pub fn getColrBase(self: *const FaceView, gid: u16) ?ColrBaseInfo {
        if (self.face_glyphs.colr_base_map) |cbm| return cbm.get(gid);
        return null;
    }

    pub fn colrLayers(self: *const FaceView, gid: u16) ttf.Font.ColrLayerIterator {
        if (self.face_config.font.colr_offset == 0) return .{ .data = self.face_config.font_data };
        const temp = ttf.Font{ .data = self.face_config.font_data, .colr_offset = self.face_config.font.colr_offset, .cpal_offset = self.face_config.font.cpal_offset };
        return temp.colrLayers(gid);
    }

    pub fn glyphLayer(self: *const FaceView, page_index: u16) u32 {
        const layer = self.layer_base + page_index;
        return layer;
    }

    pub fn glyphLayerWindowBase(self: *const FaceView, page_index: u16) u32 {
        return snail.lowlevel.textureLayerWindowBase(self.glyphLayer(page_index));
    }

    pub fn layerInfoLoc(self: *const FaceView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = @intCast(self.info_row_base + info_y),
        };
    }
};

// ── TextAtlas ──

/// Multi-font text rendering with immutable snapshot semantics.
///
/// Create with `init`, populate glyphs with `ensureText`, render with `addText`.
/// All rendering methods are read-only and safe for concurrent use.
/// `ensureText` returns a new snapshot; the old one remains valid.
pub const TextAtlas = struct {
    allocator: Allocator,
    config: *FontConfig,
    pages: []*AtlasPage,
    face_glyphs: []FaceGlyphData,

    // Merged COLR layer info across all faces.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,

    // GPU handle state (set after upload).
    layer_base: u16 = 0,
    info_row_base: u16 = 0,

    pub fn init(allocator: Allocator, specs: []const FaceSpec) !TextAtlas {
        const config = try buildFontConfig(allocator, specs);
        errdefer config.release();

        const face_glyphs = try allocator.alloc(FaceGlyphData, config.faces.len);
        for (face_glyphs) |*fg| {
            fg.* = .{ .glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator) };
        }

        const pages = try allocator.alloc(*AtlasPage, 0);

        return .{
            .allocator = allocator,
            .config = config,
            .pages = pages,
            .face_glyphs = face_glyphs,
        };
    }

    pub fn snapshotIdentity(self: *const TextAtlas) u64 {
        var h: u64 = 0x9e3779b97f4a7c15;
        h ^= @as(u64, @intCast(@intFromPtr(self.config))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.pages.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.pages.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.face_glyphs.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.face_glyphs.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        return h;
    }

    pub fn deinit(self: *TextAtlas) void {
        for (self.face_glyphs) |*fg| fg.deinit(self.allocator);
        self.allocator.free(self.face_glyphs);

        for (self.pages) |p| p.release();
        self.allocator.free(self.pages);

        if (self.layer_info_data) |lid| self.allocator.free(lid);

        self.config.release();
    }

    // ── Resolution ──

    pub fn resolve(self: *const TextAtlas, style: snail.FontStyle, codepoint: u21) ?FaceIndex {
        return resolveInner(self.config, style, codepoint, 0);
    }

    // ── Metrics ──

    pub fn faceCount(self: *const TextAtlas) usize {
        return self.config.faces.len;
    }

    pub fn primaryFaceIndex(self: *const TextAtlas) !FaceIndex {
        return self.config.primary_face orelse error.NoFaces;
    }

    pub fn lineMetrics(self: *const TextAtlas) !snail.LineMetrics {
        return self.faceLineMetrics(try self.primaryFaceIndex());
    }

    pub fn unitsPerEm(self: *const TextAtlas) !u16 {
        return self.faceUnitsPerEm(try self.primaryFaceIndex());
    }

    pub fn faceLineMetrics(self: *const TextAtlas, face_index: usize) !snail.LineMetrics {
        const face = try self.faceConfig(face_index);
        return face.font.lineMetrics();
    }

    pub fn faceUnitsPerEm(self: *const TextAtlas, face_index: usize) !u16 {
        const face = try self.faceConfig(face_index);
        return face.font.units_per_em;
    }

    /// Return the glyph ID for `codepoint` in `face_index`, or null when the
    /// face's cmap resolves it to .notdef.
    pub fn glyphIndex(self: *const TextAtlas, face_index: usize, codepoint: u21) !?u16 {
        const face = try self.faceConfig(face_index);
        const gid = try face.font.glyphIndex(codepoint);
        return if (gid == 0) null else gid;
    }

    /// Return the horizontal advance for `glyph_id` in font units.
    pub fn advanceWidth(self: *const TextAtlas, face_index: usize, glyph_id: u16) !i16 {
        const face = try self.faceConfig(face_index);
        return face.font.advanceWidth(glyph_id);
    }

    /// Resolve the styled primary face and return terminal-friendly dimensions
    /// in the same units as `options.em`.
    pub fn cellMetrics(self: *const TextAtlas, options: CellMetricsOptions) !CellMetrics {
        const fi = self.resolve(options.style, 'M') orelse try self.primaryFaceIndex();
        const fc = &self.config.faces[fi];
        const gid = try glyphIndexForCellMetrics(fc);
        const advance = try fc.font.advanceWidth(gid);
        const lm = try fc.font.lineMetrics();
        const scale = options.em / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .cell_width = @as(f32, @floatFromInt(advance)) * scale,
            .line_height = @as(f32, @floatFromInt(@as(i32, lm.ascent) - @as(i32, lm.descent) + @as(i32, lm.line_gap))) * scale,
        };
    }

    pub fn decorationRect(self: *const TextAtlas, decoration: Decoration, x: f32, y: f32, advance: f32, font_size: f32) !snail.Rect {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const dm = try fc.font.decorationMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return switch (decoration) {
            .underline => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.underline_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.underline_thickness)) * scale),
            },
            .strikethrough => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.strikethrough_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.strikethrough_thickness)) * scale),
            },
        };
    }

    pub fn superscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.superscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y - @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    pub fn subscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.subscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y + @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    // ── Itemization ──

    /// Split text into runs where each run maps to one face.
    pub fn itemize(self: *const TextAtlas, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
        return itemizeText(self.allocator, self.config, style, text);
    }

    pub fn faceView(self: *const TextAtlas, face_index: FaceIndex, atlas_view: anytype) FaceView {
        return .{
            .face_glyphs = &self.face_glyphs[face_index],
            .face_config = &self.config.faces[face_index],
            .layer_base = preparedViewLayerBase(atlas_view),
            .info_row_base = preparedViewInfoRowBase(atlas_view),
        };
    }

    fn checkedFaceIndex(self: *const TextAtlas, face_index: usize) !FaceIndex {
        if (face_index >= self.config.faces.len) return error.InvalidFaceIndex;
        if (face_index > std.math.maxInt(FaceIndex)) return error.InvalidFaceIndex;
        return @intCast(face_index);
    }

    fn faceConfig(self: *const TextAtlas, face_index: usize) !*const FaceConfig {
        const fi = try self.checkedFaceIndex(face_index);
        return &self.config.faces[fi];
    }

    fn hasPreparedGlyph(self: *const TextAtlas, face_index: usize, glyph_id: u16) bool {
        const fi = self.checkedFaceIndex(face_index) catch return false;
        const face_view = self.faceView(fi, .{});
        return shapedGlyphAvailable(&face_view, glyph_id);
    }

    fn addMissingGlyphToFaceMap(
        self: *const TextAtlas,
        face_new_gids: []?std.AutoHashMap(u16, void),
        face_index: usize,
        glyph_id: u16,
    ) !void {
        if (glyph_id == 0) return;
        const fi = try self.checkedFaceIndex(face_index);
        if (self.hasPreparedGlyph(fi, glyph_id)) return;
        if (face_new_gids[fi] == null)
            face_new_gids[fi] = std.AutoHashMap(u16, void).init(self.allocator);
        try face_new_gids[fi].?.put(glyph_id, {});
    }

    fn canRebindFrom(self: *const TextAtlas, old_atlas: *const TextAtlas) bool {
        if (self.config != old_atlas.config) return false;
        if (self.face_glyphs.len != old_atlas.face_glyphs.len) return false;
        if (self.pages.len < old_atlas.pages.len) return false;
        for (old_atlas.pages, 0..) |page_ptr, i| {
            if (self.pages[i] != page_ptr) return false;
        }
        return true;
    }

    // ── Rendering ──

    pub fn shapeText(
        self: *const TextAtlas,
        allocator: Allocator,
        style: snail.FontStyle,
        text: []const u8,
    ) !ShapedText {
        const runs = try itemizeText(allocator, self.config, style, text);
        defer allocator.free(runs);

        var glyphs = std.ArrayListUnmanaged(ShapedText.Glyph).empty;
        errdefer glyphs.deinit(allocator);

        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const segment = text[run.text_start..run.text_end];
            const shaped_run = try shapeRunForFace(allocator, fc, run.face_index, segment, run.text_start);
            defer if (shaped_run.glyphs.len > 0) allocator.free(shaped_run.glyphs);

            for (shaped_run.glyphs) |glyph| {
                try glyphs.append(allocator, .{
                    .face_index = glyph.face_index,
                    .glyph_id = glyph.glyph_id,
                    .x_offset = cursor_x + glyph.x_offset,
                    .y_offset = cursor_y + glyph.y_offset,
                    .x_advance = glyph.x_advance,
                    .y_advance = glyph.y_advance,
                    .source_start = glyph.source_start,
                    .source_end = glyph.source_end,
                });
            }
            cursor_x += shaped_run.advance_x;
            cursor_y += shaped_run.advance_y;
        }

        return .{
            .allocator = allocator,
            .atlas_identity = self.snapshotIdentity(),
            .config = self.config,
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .advance_x = cursor_x,
            .advance_y = cursor_y,
        };
    }

    fn appendShapedTextBlob(
        self: *const TextAtlas,
        builder: *TextBlobBuilder,
        append: TextAppend,
        allow_missing: bool,
    ) !TextAppendResult {
        std.debug.assert(builder.atlas == self);
        const shaped = append.shaped;
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;
        const range = append.glyphs.resolve(shaped.glyphs.len);
        const pen_origin = shapedPenAt(shaped, range.start);

        var missing = false;
        for (shaped.glyphs[range.start..range.end]) |glyph| {
            const fc = &self.config.faces[glyph.face_index];
            const face_view = self.faceView(glyph.face_index, .{});
            if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
                missing = true;
                if (!allow_missing) return error.MissingPreparedGlyph;
                // Skip missing glyphs entirely so the produced blob never
                // references unrasterized GIDs — appending one would leave
                // the blob in a state where validate/draw both fail. The
                // returned advance still reflects the full shaped run so
                // the caller's cursor lands in the right place for the
                // next text segment.
                continue;
            }
            const x = append.placement.baseline.x + (glyph.x_offset - pen_origin.x) * append.placement.em;
            const y = append.placement.baseline.y + (glyph.y_offset - pen_origin.y) * append.placement.em;
            const transform = glyphPlacementTransform(x, y, append.placement.em, fc.synthetic.skew_x);
            const local_fill = paint_mod.mapToLocal(append.fill, transform) orelse return error.InvalidTransform;
            const paint = try appendBlobGlyphPaint(builder, &face_view, glyph.glyph_id, local_fill);
            try appendBlobGlyph(
                builder,
                glyph.face_index,
                &face_view,
                glyph.glyph_id,
                transform,
                paint.color,
                paint.record_index,
                fc.synthetic,
            );
        }

        return .{
            .advance = scaleAdvance(shapedAdvanceForRange(shaped, range), append.placement.em),
            .missing = missing,
        };
    }

    /// Emit shaped text directly into a low-level TextBatch.
    pub fn appendTextBatch(
        self: *const TextAtlas,
        batch: *TextBatch,
        append: TextBatchAppend,
        allow_missing: bool,
    ) !TextAppendResult {
        const shaped = append.shaped;
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;
        const range = append.glyphs.resolve(shaped.glyphs.len);
        const pen_origin = shapedPenAt(shaped, range.start);

        var missing = false;
        for (shaped.glyphs[range.start..range.end]) |glyph| {
            const fc = &self.config.faces[glyph.face_index];
            const face_view = self.faceView(glyph.face_index, .{
                .layer_base = self.layer_base,
                .info_row_base = self.info_row_base,
            });
            if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
                missing = true;
                if (!allow_missing) return error.MissingPreparedGlyph;
                continue;
            }

            const x = append.placement.baseline.x + (glyph.x_offset - pen_origin.x) * append.placement.em;
            const y = append.placement.baseline.y + (glyph.y_offset - pen_origin.y) * append.placement.em;
            if (glyph_emit.emitStyledGlyph(batch, &face_view, glyph.glyph_id, x, y, append.placement.em, append.color, fc.synthetic) == .buffer_full) break;
        }

        return .{
            .advance = scaleAdvance(shapedAdvanceForRange(shaped, range), append.placement.em),
            .missing = missing,
        };
    }

    /// Measure advance width without emitting vertices.
    pub fn measureText(
        self: *const TextAtlas,
        style: snail.FontStyle,
        text: []const u8,
        font_size: f32,
    ) !f32 {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        var width: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (comptime build_options.enable_harfbuzz) {
                if (fc.hb_shaper) |hbs| {
                    width += hbs.measureWidth(segment, font_size);
                    continue;
                }
            }

            const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
            const utf8_view = std.unicode.Utf8View.initUnchecked(segment);
            var it = utf8_view.iterator();
            while (it.nextCodepoint()) |cp| {
                const gid = fc.font.glyphIndex(cp) catch 0;
                if (gid == 0) {
                    width += scale * 500;
                    continue;
                }
                if (fg.getGlyph(gid)) |info| {
                    width += @as(f32, @floatFromInt(info.advance_width)) * scale;
                } else {
                    width += @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * scale;
                }
            }
        }
        return width;
    }

    // ── Atlas extension ──

    /// Return a new TextAtlas snapshot with atlas extended for the given text.
    /// Returns null if all glyphs are already present. The old snapshot stays valid.
    pub fn ensureText(self: *const TextAtlas, style: snail.FontStyle, text: []const u8) !?TextAtlas {
        var shaped = try self.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return self.ensureShaped(&shaped);
    }

    /// Return a new TextAtlas snapshot with all glyphs referenced by `shaped`
    /// available. Returns null if the current snapshot already contains them.
    pub fn ensureShaped(self: *const TextAtlas, shaped: *const ShapedText) !?TextAtlas {
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;

        const face_new_gids = try self.allocator.alloc(?std.AutoHashMap(u16, void), self.config.faces.len);
        defer self.allocator.free(face_new_gids);
        @memset(face_new_gids, null);
        defer for (face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (shaped.glyphs) |glyph| {
            try self.addMissingGlyphToFaceMap(face_new_gids, glyph.face_index, glyph.glyph_id);
        }

        return self.ensureGlyphMaps(face_new_gids);
    }

    /// Return a new TextAtlas snapshot with the given glyph IDs available for
    /// one face. Returns null if the current snapshot already contains them.
    pub fn ensureGlyphs(self: *const TextAtlas, face_index: usize, glyph_ids: []const u16) !?TextAtlas {
        const fi = try self.checkedFaceIndex(face_index);

        const face_new_gids = try self.allocator.alloc(?std.AutoHashMap(u16, void), self.config.faces.len);
        defer self.allocator.free(face_new_gids);
        @memset(face_new_gids, null);
        defer for (face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (glyph_ids) |gid| {
            try self.addMissingGlyphToFaceMap(face_new_gids, fi, gid);
        }

        return self.ensureGlyphMaps(face_new_gids);
    }

    fn ensureGlyphMaps(self: *const TextAtlas, face_new_gids: []?std.AutoHashMap(u16, void)) !?TextAtlas {
        std.debug.assert(face_new_gids.len == self.config.faces.len);

        var any_missing = false;
        for (face_new_gids) |maybe_map| {
            if (maybe_map) |map| {
                if (map.count() > 0) {
                    any_missing = true;
                    break;
                }
            }
        }
        if (!any_missing) return null;

        // Build new pages for each face with missing glyphs.
        var new_pages_list = std.ArrayListUnmanaged(*AtlasPage).empty;
        defer new_pages_list.deinit(self.allocator);

        const new_face_glyphs = try self.allocator.alloc(FaceGlyphData, self.config.faces.len);
        const new_face_glyphs_initialized = try self.allocator.alloc(bool, self.config.faces.len);
        defer self.allocator.free(new_face_glyphs_initialized);
        @memset(new_face_glyphs_initialized, false);
        errdefer {
            for (new_face_glyphs, new_face_glyphs_initialized) |*fg, initialized| {
                if (initialized) fg.deinit(self.allocator);
            }
            self.allocator.free(new_face_glyphs);
        }

        for (self.config.faces, 0..) |*fc, fi| {
            if (face_new_gids[fi]) |*new_gids| {
                // Expand COLR layers.
                try snail.lowlevel.CurveAtlas.expandColrLayersInner(&fc.font, self.allocator, new_gids);

                // Filter out glyph IDs already in the atlas.
                var filtered = std.AutoHashMap(u16, void).init(self.allocator);
                defer filtered.deinit();
                var git = new_gids.keyIterator();
                while (git.next()) |gid_ptr| {
                    if (!self.face_glyphs[fi].glyph_map.contains(gid_ptr.*))
                        try filtered.put(gid_ptr.*, {});
                }

                if (filtered.count() == 0) {
                    new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                    new_face_glyphs_initialized[fi] = true;
                    continue;
                }

                // Build page for the new glyphs. `page_index` is u16 because
                // the GPU vertex encoding only has 16 bits for it.
                const next_page = self.pages.len + new_pages_list.items.len;
                if (next_page > std.math.maxInt(u16)) return error.AtlasPageLimitExceeded;
                const page_index: u16 = @intCast(next_page);
                const page_result = try snail.lowlevel.CurveAtlas.buildPageDataInner(self.allocator, &fc.font, &filtered, page_index);
                try new_pages_list.append(self.allocator, page_result.page);

                // Merge glyph maps.
                var merged = std.AutoHashMap(u16, GlyphInfo).init(self.allocator);
                var eit = self.face_glyphs[fi].glyph_map.iterator();
                while (eit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var nit = page_result.glyph_map.iterator();
                while (nit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var pm = page_result.glyph_map;
                pm.deinit();

                new_face_glyphs[fi] = .{ .glyph_map = merged };
                new_face_glyphs_initialized[fi] = true;
                try new_face_glyphs[fi].buildGlyphLut(self.allocator);
            } else {
                new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                new_face_glyphs_initialized[fi] = true;
            }
        }

        // Assemble new pages array: retain old + own new.
        const total_pages = self.pages.len + new_pages_list.items.len;
        const new_pages = try self.allocator.alloc(*AtlasPage, total_pages);
        for (self.pages, 0..) |p, i| new_pages[i] = p.retain();
        for (new_pages_list.items, 0..) |p, i| new_pages[self.pages.len + i] = p;

        return .{
            .allocator = self.allocator,
            .config = self.config.retain(),
            .pages = new_pages,
            .face_glyphs = new_face_glyphs,
        };
    }

    // ── GPU upload helpers ──

    pub fn pageCount(self: *const TextAtlas) usize {
        return self.pages.len;
    }

    pub fn page(self: *const TextAtlas, index: usize) *const AtlasPage {
        return self.pages[index];
    }

    pub fn pageSlice(self: *const TextAtlas) []*AtlasPage {
        return self.pages;
    }

    pub fn uploadFootprint(self: *const TextAtlas) snail.ResourceFootprint {
        return snail.textAtlasUploadFootprint(self);
    }

    /// Low-level: create a temporary `CurveAtlas` wrapper that borrows this
    /// snapshot's pages for GPU upload. Most callers should use
    /// `Renderer.uploadResourcesBlocking` (or `planResourceUpload` /
    /// `beginResourceUpload`) instead — this entry point is for code that
    /// drives the upload helpers in `lowlevel` directly.
    ///
    /// The returned wrapper borrows `self.pages`. Free it via
    /// `deinitUploadAtlas` (do NOT call `wrapper.deinit()`, which would
    /// release the shared pages).
    pub fn uploadAtlas(self: *const TextAtlas) snail.lowlevel.CurveAtlas {
        return .{
            .allocator = self.allocator,
            .font = null,
            .pages = self.pages,
            .glyph_map = .init(self.allocator), // empty — glyph lookup goes through FaceView
            .shaper = null,
            .layer_info_data = self.layer_info_data,
            .layer_info_width = self.layer_info_width,
            .layer_info_height = self.layer_info_height,
        };
    }

    /// Clean up a wrapper Atlas from uploadAtlas(). Only frees the empty glyph_map,
    /// NOT the shared pages.
    pub fn deinitUploadAtlas(_: *const TextAtlas, wrapper: *snail.lowlevel.CurveAtlas) void {
        wrapper.glyph_map.deinit();
        // Don't free pages — they belong to TextAtlas.
        wrapper.pages = &.{};
        // Don't call wrapper.deinit() — that would release shared pages.
    }
};

// ── FontConfig construction ──

fn buildFontConfig(allocator: Allocator, specs: []const FaceSpec) !*FontConfig {
    const config = try allocator.create(FontConfig);
    errdefer allocator.destroy(config);

    const faces = try allocator.alloc(FaceConfig, specs.len);
    errdefer allocator.free(faces);

    // Parse fonts, deduplicating by data pointer.
    var parsed_cache = std.AutoHashMap([*]const u8, struct { font: ttf.Font, shaper: ?opentype.Shaper, hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void }).init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        if (parsed_cache.get(spec.data.ptr)) |cached| {
            faces[i] = .{
                .font = cached.font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = cached.shaper,
                .hb_shaper = cached.hb_shaper,
                .owns_shapers = false,
            };
        } else {
            const font = try ttf.Font.init(spec.data);
            const shaper = opentype.Shaper.init(allocator, spec.data, font.gsub_offset, font.gpos_offset) catch null;
            const hb_shaper = if (comptime build_options.enable_harfbuzz)
                harfbuzz.HarfBuzzShaper.init(spec.data, font.units_per_em) catch null
            else {};

            try parsed_cache.put(spec.data.ptr, .{ .font = font, .shaper = shaper, .hb_shaper = hb_shaper });

            faces[i] = .{
                .font = font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = shaper,
                .hb_shaper = hb_shaper,
                .owns_shapers = true,
            };
        }
    }

    // Build style chains and global fallback chain.
    var style_chains = std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)).empty;
    errdefer {
        var it = style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        style_chains.deinit(allocator);
    }

    var global_chain_list = std.ArrayListUnmanaged(FaceIndex).empty;
    errdefer global_chain_list.deinit(allocator);

    var primary_face: ?FaceIndex = null;

    for (specs, 0..) |spec, i| {
        const fi: FaceIndex = @intCast(i);

        if (spec.fallback) {
            try global_chain_list.append(allocator, fi);
            if (primary_face == null) primary_face = fi;
        } else {
            const key = packStyle(.{ .weight = spec.weight, .italic = spec.italic });
            const gop = try style_chains.getOrPut(allocator, key);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(allocator, fi);

            if (primary_face == null and spec.weight == .regular and !spec.italic) {
                primary_face = fi;
            }
        }
    }

    const global_chain = try allocator.alloc(FaceIndex, global_chain_list.items.len);
    @memcpy(global_chain, global_chain_list.items);
    global_chain_list.deinit(allocator);

    config.* = .{
        .allocator = allocator,
        .faces = faces,
        .style_chains = style_chains,
        .global_chain = global_chain,
        .primary_face = primary_face,
    };

    return config;
}

// ── Resolution helpers ──

fn resolveInner(config: *const FontConfig, style: snail.FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
    if (depth > 3) return null;

    // 1. Style-specific chain
    if (config.style_chains.get(packStyle(style))) |chain| {
        for (chain.items) |fi| {
            if (faceHasGlyph(config, fi, codepoint)) return fi;
        }
    }

    // 2. Global fallbacks
    for (config.global_chain) |fi| {
        if (faceHasGlyph(config, fi, codepoint)) return fi;
    }

    // 3. Style degradation
    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveInner(config, .{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
        if (resolveInner(config, .{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.italic) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.weight != .regular) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    }

    return null;
}

fn faceHasGlyph(config: *const FontConfig, fi: FaceIndex, codepoint: u21) bool {
    const gid = config.faces[fi].font.glyphIndex(codepoint) catch return false;
    return gid != 0;
}

fn packStyle(style: snail.FontStyle) u8 {
    return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
}

// ── Itemization ──

fn itemizeText(allocator: Allocator, config: *const FontConfig, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
    _ = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;
    var runs = std.ArrayListUnmanaged(ItemizedRun).empty;
    errdefer runs.deinit(allocator);

    var byte_offset: u32 = 0;
    var current_face: ?FaceIndex = null;
    var run_start: u32 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return error.InvalidUtf8;
        if (i + cp_len > text.len) return error.InvalidUtf8;
        const cp: u21 = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return error.InvalidUtf8;

        const face_idx = resolveInner(config, style, cp, 0) orelse
            if (config.primary_face) |pf| pf else {
                i += cp_len;
                byte_offset += @intCast(cp_len);
                continue;
            };

        if (current_face == null) {
            current_face = face_idx;
            run_start = byte_offset;
        } else if (current_face.? != face_idx) {
            try runs.append(allocator, .{
                .face_index = current_face.?,
                .text_start = run_start,
                .text_end = byte_offset,
            });
            current_face = face_idx;
            run_start = byte_offset;
        }

        i += cp_len;
        byte_offset += @intCast(cp_len);
    }

    if (current_face) |fi| {
        try runs.append(allocator, .{
            .face_index = fi,
            .text_start = run_start,
            .text_end = byte_offset,
        });
    }

    return try runs.toOwnedSlice(allocator);
}

fn isIdentityTransform(transform: snail.Transform2D) bool {
    return transform.xx == 1 and transform.xy == 0 and transform.tx == 0 and transform.yx == 0 and transform.yy == 1 and transform.ty == 0;
}

fn glyphPlacementTransform(x: f32, y: f32, font_size: f32, skew_x: f32) snail.Transform2D {
    return .{
        .xx = font_size,
        .xy = skew_x * font_size,
        .tx = x,
        .yx = 0,
        .yy = -font_size,
        .ty = y,
    };
}

const ShapeRunResult = struct {
    glyphs: []ShapedText.Glyph,
    advance_x: f32,
    advance_y: f32,
};

fn shapeRunForFace(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
) !ShapeRunResult {
    if (text.len == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));

    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            const shaped = hbs.shapeText(text);
            if (shaped.count == 0 or shaped.infos == null or shaped.positions == null)
                return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

            const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
            errdefer allocator.free(out);

            var cursor_x: f32 = 0;
            var cursor_y: f32 = 0;
            for (0..shaped.count) |i| {
                const info = shaped.infos[i];
                const pos = shaped.positions[i];
                const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
                out[i] = .{
                    .face_index = face_index,
                    .glyph_id = @intCast(info.codepoint),
                    .x_offset = (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * inv_upem,
                    .y_offset = -(cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * inv_upem,
                    .x_advance = @as(f32, @floatFromInt(pos.x_advance)) * inv_upem,
                    .y_advance = -@as(f32, @floatFromInt(pos.y_advance)) * inv_upem,
                    .source_start = source_base + cluster,
                    .source_end = source_base + @as(u32, @intCast(text.len)),
                };
                cursor_x += @as(f32, @floatFromInt(pos.x_advance));
                cursor_y += @as(f32, @floatFromInt(pos.y_advance));
            }

            return .{
                .glyphs = out,
                .advance_x = cursor_x * inv_upem,
                .advance_y = -cursor_y * inv_upem,
            };
        }
    }

    var cp_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |_| cp_count += 1;
    }
    if (cp_count == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

    const gids = try allocator.alloc(u16, cp_count);
    defer allocator.free(gids);
    const src_starts = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_starts);
    const src_ends = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_ends);

    var glyph_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepointSlice()) |cp_slice| {
            const byte_pos = @intFromPtr(cp_slice.ptr) - @intFromPtr(text.ptr);
            const cp = std.unicode.utf8Decode(cp_slice) catch 0;
            gids[glyph_count] = fc.font.glyphIndex(@intCast(cp)) catch 0;
            src_starts[glyph_count] = source_base + @as(u32, @intCast(byte_pos));
            src_ends[glyph_count] = source_base + @as(u32, @intCast(byte_pos + cp_slice.len));
            glyph_count += 1;
        }
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigaturesTracked(
            gids[0..glyph_count],
            src_starts[0..glyph_count],
            src_ends[0..glyph_count],
        ) catch glyph_count;
    }

    const out = try allocator.alloc(ShapedText.Glyph, glyph_count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var prev_gid: u16 = 0;
    for (gids[0..glyph_count], 0..) |gid, i| {
        if (gid == 0) {
            const advance = 500.0 * inv_upem;
            out[i] = .{
                .face_index = face_index,
                .glyph_id = 0,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance,
                .y_advance = 0,
                .source_start = src_starts[i],
                .source_end = src_ends[i],
            };
            cursor_x += advance;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
            cursor_x += @as(f32, @floatFromInt(kern)) * inv_upem;
        }

        const advance = @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * inv_upem;
        out[i] = .{
            .face_index = face_index,
            .glyph_id = gid,
            .x_offset = cursor_x,
            .y_offset = 0,
            .x_advance = advance,
            .y_advance = 0,
            .source_start = src_starts[i],
            .source_end = src_ends[i],
        };
        cursor_x += advance;
        prev_gid = gid;
    }

    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

fn shapedGlyphAvailable(face_view: *const FaceView, glyph_id: u16) bool {
    if (glyph_id == 0) return true;
    if (face_view.getGlyph(glyph_id) != null) return true;
    if (face_view.getColrBase(glyph_id) != null) return true;
    var layers = face_view.colrLayers(glyph_id);
    if (layers.count() == 0) return false;
    var has_renderable_layer = false;
    while (layers.next()) |layer| {
        const info = face_view.getGlyph(layer.glyph_id) orelse return false;
        if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return false;
        has_renderable_layer = true;
    }
    return has_renderable_layer;
}

fn glyphInstanceBudget(face_view: *const FaceView, glyph_id: u16) usize {
    if (glyph_id == 0) return 0;
    if (face_view.getColrBase(glyph_id) != null) return 1;

    var layer_it = face_view.colrLayers(glyph_id);
    const layer_count = layer_it.count();
    if (layer_count > 0) return layer_count;

    // Match `glyph_emit.hasRenderableBands`: a present-but-empty glyph
    // (e.g. space with `h_band_count == 0`) emits no instances, so it must
    // not contribute to the budget — otherwise PreparedScene over-allocates.
    const info = face_view.getGlyph(glyph_id) orelse return 0;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return 0;
    return 1;
}

fn textBlobGpuInstanceBudgetForAtlas(atlas: *const TextAtlas, glyphs: []const TextBlob.Glyph) usize {
    var total: usize = 0;
    for (glyphs) |glyph| {
        const fi = atlas.checkedFaceIndex(glyph.face_index) catch continue;
        const face_view = atlas.faceView(fi, .{});
        const base_budget = glyphInstanceBudget(&face_view, glyph.glyph_id);
        total += base_budget;
        if (glyph.embolden != 0 and glyph.glyph_id != 0) {
            total += base_budget;
        }
    }
    return total;
}

pub fn textBlobRangeGpuInstanceBudget(blob: *const TextBlob, range: snail.Range.Resolved) usize {
    var total: usize = 0;
    for (blob.glyphs[range.start..range.end]) |glyph| {
        const face_view = blob.atlas.faceView(glyph.face_index, .{});
        const base_budget = glyphInstanceBudget(&face_view, glyph.glyph_id);
        total += base_budget;
        if (glyph.embolden != 0 and glyph.glyph_id != 0) {
            total += base_budget;
        }
    }
    return total;
}

fn shapedPenAt(shaped: *const ShapedText, glyph_index: usize) snail.Vec2 {
    var pen = snail.Vec2.zero;
    for (shaped.glyphs[0..@min(glyph_index, shaped.glyphs.len)]) |glyph| {
        pen.x += glyph.x_advance;
        pen.y += glyph.y_advance;
    }
    return pen;
}

fn shapedAdvanceForRange(shaped: *const ShapedText, range: snail.Range.Resolved) snail.Vec2 {
    var advance = snail.Vec2.zero;
    for (shaped.glyphs[range.start..range.end]) |glyph| {
        advance.x += glyph.x_advance;
        advance.y += glyph.y_advance;
    }
    return advance;
}

fn scaleAdvance(advance: snail.Vec2, em: f32) snail.Vec2 {
    return .{ .x = advance.x * em, .y = advance.y * em };
}

const BlobGlyphPaint = struct {
    color: [4]f32,
    record_index: ?u32 = null,
};

fn appendBlobGlyphPaint(
    builder: *TextBlobBuilder,
    face_view: *const FaceView,
    glyph_id: u16,
    fill: snail.Paint,
) !BlobGlyphPaint {
    return switch (fill) {
        .solid => |color| .{ .color = color },
        else => blk: {
            const info = face_view.getGlyph(glyph_id) orelse {
                if (glyph_id == 0) break :blk .{ .color = .{ 1, 1, 1, 1 } };
                return error.UnsupportedTextPaint;
            };
            if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) {
                break :blk .{ .color = .{ 1, 1, 1, 1 } };
            }
            const index: u32 = @intCast(builder.paint_records.items.len);
            try builder.paint_records.append(builder.allocator, .{
                .band_entry = info.band_entry,
                .paint = fill,
            });
            break :blk .{ .color = .{ 1, 1, 1, 1 }, .record_index = index };
        },
    };
}

fn appendBlobGlyph(
    builder: *TextBlobBuilder,
    face_index: FaceIndex,
    face_view: *const FaceView,
    glyph_id: u16,
    transform: snail.Transform2D,
    color: [4]f32,
    paint_record_index: ?u32,
    synthetic: snail.SyntheticStyle,
) !void {
    try builder.glyphs.append(builder.allocator, .{
        .face_index = face_index,
        .glyph_id = glyph_id,
        .transform = transform,
        .embolden = synthetic.embolden,
        .color = color,
        .paint_record_index = paint_record_index,
    });
    builder.gpu_instance_budget += glyphInstanceBudget(face_view, glyph_id);
    if (synthetic.embolden != 0 and glyph_id != 0) {
        builder.gpu_instance_budget += glyphInstanceBudget(face_view, glyph_id);
    }
}

fn glyphIndexForCellMetrics(fc: *const FaceConfig) !u16 {
    const candidates = [_]u21{ 'M', 'W', ' ', '0' };
    for (candidates) |cp| {
        const gid = try fc.font.glyphIndex(cp);
        if (gid != 0) return gid;
    }
    return error.MissingCellMetricsGlyph;
}

// ── Tests ──

const testing = std.testing;

fn appendTestText(
    builder: *TextBlobBuilder,
    style: snail.FontStyle,
    text: []const u8,
    baseline: snail.Vec2,
    em: f32,
    color: [4]f32,
) !TextAppendResult {
    var shaped = try builder.atlas.shapeText(builder.allocator, style, text);
    defer shaped.deinit();
    return builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = baseline, .em = em },
        .fill = .{ .solid = color },
    });
}

fn appendTestTextBatch(
    atlas: *const TextAtlas,
    batch: *TextBatch,
    style: snail.FontStyle,
    text: []const u8,
    baseline: snail.Vec2,
    em: f32,
    color: [4]f32,
    allow_missing: bool,
) !TextAppendResult {
    var shaped = try atlas.shapeText(testing.allocator, style, text);
    defer shaped.deinit();
    return atlas.appendTextBatch(batch, .{
        .shaped = &shaped,
        .placement = .{ .baseline = baseline, .em = em },
        .color = color,
    }, allow_missing);
}

test "TextAtlas.init with single face" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(?FaceIndex, 0), fonts.config.primary_face);
    try testing.expectEqual(@as(usize, 1), fonts.config.faces.len);
    try testing.expectEqual(@as(usize, 0), fonts.pageCount());
}

test "TextAtlas.ensureText adds missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(usize, 0), fonts.pageCount());

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    try testing.expect(fonts.pageCount() > 0);

    // Ensuring the same text again returns null (nothing new).
    const again = try fonts.ensureText(.{}, "Hello");
    try testing.expectEqual(@as(?TextAtlas, null), again);
}

test "TextAtlas.ensureText is stable for runs containing empty glyphs" {
    // Regression: a glyph rasterised with `h_band_count == 0` (e.g. space)
    // used to be reported as missing by `shapedGlyphAvailable` even after it
    // was placed in the atlas, while `ensureGlyphMaps` filtered it out via
    // `glyph_map.contains` — so each call published a new (functionally
    // identical) snapshot, spinning any caller that rebound on snapshot
    // identity changes.
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "a b")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    const pages_after_first = fonts.pageCount();

    // Re-ensuring text whose only "missing" glyph is the empty space must be
    // a no-op — no new snapshot, no new pages.
    try testing.expectEqual(@as(?TextAtlas, null), try fonts.ensureText(.{}, "a b"));
    try testing.expectEqual(@as(?TextAtlas, null), try fonts.ensureText(.{}, " "));
    try testing.expectEqual(pages_after_first, fonts.pageCount());
}

test "TextAtlas.ensureText snapshot immutability" {
    const assets_data = @import("assets");
    var fonts1 = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts1.deinit();

    if (try fonts1.ensureText(.{}, "AB")) |new_fonts| {
        fonts1.deinit();
        fonts1 = new_fonts;
    }
    const pages_before = fonts1.pageCount();

    const maybe_fonts2 = try fonts1.ensureText(.{}, "CDEFGHIJKLMNOP");
    try testing.expect(maybe_fonts2 != null);
    var fonts2 = maybe_fonts2.?;
    defer fonts2.deinit();

    try testing.expectEqual(pages_before, fonts1.pageCount());
    try testing.expect(fonts2.pageCount() >= pages_before);
}

test "TextAtlas.appendTextBatch renders and reports advance" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var buf: [64 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&buf);
    const result = try appendTestTextBatch(&fonts, &batch, .{}, "Hello", .{ .x = 0, .y = 100 }, 24, .{ 1, 1, 1, 1 }, true);

    try testing.expect(result.advance.x > 0);
    try testing.expect(batch.glyphCount() > 0);
    try testing.expect(!result.missing);
}

test "TextAtlas.appendTextBatch reports missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Atlas is empty; addText should report missing glyphs.
    var buf: [64 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&buf);
    const result = try appendTestTextBatch(&fonts, &batch, .{}, "Hello", .{ .x = 0, .y = 100 }, 24, .{ 1, 1, 1, 1 }, true);

    try testing.expect(result.missing);
    try testing.expectEqual(@as(usize, 0), batch.glyphCount());
}

test "TextBlobBuilder.append with partially-prepared atlas skips missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Prepare only "Hi" — the rest of the run will be missing.
    if (try fonts.ensureText(.{}, "Hi")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const result = try appendTestText(&builder, .{}, "Hi there", .{ .x = 0, .y = 50 }, 16, .{ 1, 1, 1, 1 });
    try testing.expect(result.missing);
    try testing.expect(result.advance.x > 0); // advance still spans the full run

    // Builder must only retain glyphs that are actually in the atlas; the
    // resulting blob must validate cleanly against the same snapshot.
    try testing.expect(builder.glyphCount() <= 2);
    var blob = try builder.finish();
    defer blob.deinit();
    try blob.validate();
}

test "TextBlobBuilder.append separates shape from placement and fill" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const first = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 30, .y = 40 }, .em = 20 },
        .fill = .{ .solid = .{ 0, 1, 0, 1 } },
    });

    try testing.expectApproxEqAbs(shaped.advance_x * 12, first.advance.x, 0.001);
    try testing.expectApproxEqAbs(shaped.advance_x * 20, second.advance.x, 0.001);
    try testing.expectEqual(@as(usize, 2), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expectApproxEqAbs(@as(f32, 10), blob.glyphs[0].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[0].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 12), blob.glyphs[0].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectApproxEqAbs(@as(f32, 30), blob.glyphs[1].transform.tx, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 40), blob.glyphs[1].transform.ty, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), blob.glyphs[1].transform.xx, 0.001);
    try testing.expectEqual([4]f32{ 0, 1, 0, 1 }, blob.glyphs[1].color);
}

test "TextBlobBuilder.append can style shaped glyph ranges independently" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "AB")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "AB");
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len >= 2);

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    const first = try builder.append(.{
        .shaped = &shaped,
        .glyphs = .{ .start = 0, .count = 1 },
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 1, 0, 0, 1 } },
    });
    const second = try builder.append(.{
        .shaped = &shaped,
        .glyphs = .{ .start = 1, .count = 1 },
        .placement = .{ .baseline = .{ .x = 10 + first.advance.x, .y = 20 }, .em = 18 },
        .fill = .{ .solid = .{ 0, 0, 1, 1 } },
    });

    try testing.expect(first.advance.x > 0);
    try testing.expect(second.advance.x > 0);
    try testing.expectEqual(@as(usize, 2), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, blob.glyphs[0].color);
    try testing.expectEqual([4]f32{ 0, 0, 1, 1 }, blob.glyphs[1].color);
    try testing.expectApproxEqAbs(10 + first.advance.x, blob.glyphs[1].transform.tx, 0.001);
}

test "TextBlobBuilder.append stores gradient paint records" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    _ = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 10 },
        .fill = .{ .linear_gradient = .{
            .start = .{ .x = 10, .y = 20 },
            .end = .{ .x = 30, .y = 20 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
        } },
    });
    try testing.expectEqual(@as(usize, 1), builder.glyphCount());

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expect(blob.hasPaintRecords());
    try testing.expectEqual(@as(?u32, 0), blob.glyphs[0].paint_record_index);
    try testing.expectEqual([4]f32{ 1, 1, 1, 1 }, blob.glyphs[0].color);
    try testing.expectEqual(@as(u32, paint_records.texels_per_record), blob.paint_layer_info_width);
    try testing.expectEqual(@as(u32, 1), blob.paint_layer_info_height);

    const loc = blob.paintRecordLoc(0);
    try testing.expectEqual(@as(u16, 0), loc.x);
    try testing.expectEqual(@as(u16, 0), loc.y);
    const tag = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 0)[3];
    try testing.expectApproxEqAbs(paint_records.tag_linear_gradient, tag, 0.001);
    const coords = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 2);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2), coords[2], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), coords[3], 0.001);
    try testing.expect(blob.paint_image_records == null);
}

test "TextBlobBuilder.append stores image paint records" {
    const assets_data = @import("assets");
    var image = try snail.Image.initSrgba8(testing.allocator, 1, 1, &.{ 255, 64, 32, 255 });
    defer image.deinit();
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var shaped = try fonts.shapeText(testing.allocator, .{}, "A");
    defer shaped.deinit();

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();

    _ = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 8 }, .em = 2 },
        .fill = .{ .image = .{
            .image = &image,
            .uv_transform = snail.Transform2D.scale(0.25, 0.5),
        } },
    });

    var blob = try builder.finish();
    defer blob.deinit();
    try testing.expect(blob.hasPaintRecords());
    const records = blob.paint_image_records orelse return error.TestExpectedEqual;
    try testing.expectEqual(@as(usize, 1), records.len);
    try testing.expect(records[0].?.image == &image);
    try testing.expectEqual(@as(u32, 0), records[0].?.texel_offset);
    const tag = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 0)[3];
    try testing.expectApproxEqAbs(paint_records.tag_image, tag, 0.001);
    const data0 = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 2);
    const data1 = paint_records.readTexel(blob.paint_layer_info_data.?, blob.paint_layer_info_width, 3);
    try testing.expectApproxEqAbs(@as(f32, 0.5), data0[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), data0[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1), data0[2], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), data1[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, -1), data1[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 4), data1[2], 0.001);
}

test "TextAtlas.lineMetrics returns primary face metrics" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const lm = try fonts.lineMetrics();
    try testing.expect(lm.ascent > 0);
    try testing.expect(lm.descent < 0);
}

test "TextAtlas exposes per-face metrics and cell metrics" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_bold, .weight = .bold },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(usize, 2), fonts.faceCount());
    try testing.expectEqual(@as(FaceIndex, 0), try fonts.primaryFaceIndex());

    const upem = try fonts.faceUnitsPerEm(0);
    try testing.expect(upem > 0);

    const gid = (try fonts.glyphIndex(0, 'M')).?;
    const advance = try fonts.advanceWidth(0, gid);
    try testing.expect(advance > 0);

    const metrics = try fonts.cellMetrics(.{ .style = .{}, .em = 16 });
    try testing.expect(metrics.cell_width > 0);
    try testing.expect(metrics.line_height > metrics.cell_width);
}

test "TextAtlas.ensureGlyphs extends by resolved glyph id" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const gid = (try fonts.glyphIndex(0, 'A')).?;
    var next = (try fonts.ensureGlyphs(0, &.{gid})).?;
    defer next.deinit();

    try testing.expect(next.pageCount() > fonts.pageCount());
    try testing.expectEqual(@as(?TextAtlas, null), try next.ensureGlyphs(0, &.{gid}));
}

test "TextBlob.rebind accepts atlas snapshots that retain referenced glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "A")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    _ = try appendTestText(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();

    var next = (try fonts.ensureText(.{}, "B")).?;
    defer next.deinit();

    try blob.rebind(&next);
    try blob.validate();
}

test "TextBlob.rebind recomputes budget after ensureGlyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Prepare 'A' so the blob has a real entry to rebind. (Building a blob
    // against an empty atlas leaves it empty — `addText` skips missing
    // glyphs so the blob never references unrasterized GIDs.)
    if (try fonts.ensureText(.{}, "A")) |next| {
        fonts.deinit();
        fonts = next;
    }

    var builder = TextBlobBuilder.init(testing.allocator, &fonts);
    defer builder.deinit();
    _ = try appendTestText(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });

    var blob = try builder.finish();
    defer blob.deinit();
    const original_budget = blob.gpu_instance_budget;
    try testing.expect(original_budget > 0);

    // Extend the atlas with an unrelated glyph; rebind must still succeed
    // and the recomputed budget must remain valid against the new snapshot.
    const gid_b = (try fonts.glyphIndex(0, 'B')).?;
    var next = (try fonts.ensureGlyphs(0, &.{gid_b})).?;
    defer next.deinit();

    try blob.rebind(&next);
    try blob.validate();
    try testing.expect(blob.gpu_instance_budget > 0);
}

test "TextAtlas with multiple faces and fallback" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_arabic, .fallback = true },
    });
    defer fonts.deinit();

    // Arabic codepoint should resolve to the Arabic face (index 1).
    const face = fonts.resolve(.{}, 0x0645); // م
    try testing.expectEqual(@as(?FaceIndex, 1), face);

    // Latin codepoint should resolve to the primary face (index 0).
    const latin = fonts.resolve(.{}, 'A');
    try testing.expectEqual(@as(?FaceIndex, 0), latin);
}

test "TextAtlas deduplicates same font data" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    });
    defer fonts.deinit();

    // Both faces share the same parsed font (data pointer equality).
    try testing.expectEqual(fonts.config.faces[0].font.data.ptr, fonts.config.faces[1].font.data.ptr);
}
