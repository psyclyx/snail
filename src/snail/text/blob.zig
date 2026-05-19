const std = @import("std");

const paint_mod = @import("../paint.zig");
const paint_records = @import("../paint_records.zig");
const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const band_tex = @import("../render/format/band_texture.zig");
const bezier = @import("../math/bezier.zig");
const hint_context = @import("hint_context.zig");
const resource_key_mod = @import("../resource_key.zig");
const text_hint = @import("../render/format/text_hint.zig");
const atlas_mod = @import("atlas.zig");
const config_mod = @import("config.zig");
const range_mod = @import("../range.zig");
const shape_mod = @import("shape.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");
const view_mod = @import("view.zig");

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const FaceIndex = config_mod.FaceIndex;
const FaceView = view_mod.FaceView;
const HintedGlyphValue = hint_context.HintedGlyphValue;
const Paint = paint_mod.Paint;
const PaintImageRecord = atlas_curve_mod.CurveAtlas.PaintImageRecord;
const Range = range_mod.Range;
const ResourceKey = resource_key_mod.ResourceKey;
const ShapedText = types_mod.ShapedText;
const SyntheticStyle = config_mod.SyntheticStyle;
const TextAppend = types_mod.TextAppend;
const TextAppendResult = types_mod.TextAppendResult;
const TextAtlas = atlas_mod.TextAtlas;
const TextResourceKeys = resource_key_mod.TextResourceKeys;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;
const glyphInstanceBudget = shape_mod.glyphInstanceBudget;
const glyphPlacementTransform = shape_mod.glyphPlacementTransform;
const scaleAdvance = shape_mod.scaleAdvance;
const shapedAdvanceForRange = shape_mod.shapedAdvanceForRange;
const shapedGlyphAvailable = shape_mod.shapedGlyphAvailable;
const shapedPenAt = shape_mod.shapedPenAt;

pub const TextBlob = struct {
    allocator: Allocator,
    /// Borrowed TextAtlas snapshot used to build this blob. The pointer and
    /// snapshot identity must remain valid until the blob is destroyed or a
    /// rebound copy moves the blob data to a compatible atlas snapshot.
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []Glyph,
    paint_layer_info_data: ?[]f32 = null,
    paint_layer_info_width: u32 = 0,
    paint_layer_info_height: u32 = 0,
    paint_image_records: ?[]?PaintImageRecord = null,
    /// Upper bound on GPU vertex-output instances this blob will emit
    /// (counts COLR layer fan-out and synthetic-bold duplication). Used to
    /// size scratch buffers in `DrawList.estimate`.
    gpu_instance_budget: usize,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        embolden: f32,
        color: [4]f32,
        paint_record_index: ?u32 = null,
        hint_record_texel: ?u32 = null,
        hint_bbox: BBox = emptyBBox(),
    };

    pub const LayerInfoLoc = struct { x: u16, y: u16 };

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

    pub fn resourceKeys(self: *const TextBlob, atlas_key: ResourceKey, blob_key: ResourceKey) TextResourceKeys {
        return .{
            .atlas = atlas_key,
            .paint = if (self.hasPaintRecords()) resource_key_mod.derived(blob_key, "text_paint") else null,
        };
    }

    pub fn paintRecordLoc(self: *const TextBlob, record_index: u32) LayerInfoLoc {
        const texel_offset = record_index * paint_records.texels_per_record;
        return self.layerInfoLoc(texel_offset);
    }

    pub fn hintRecordLoc(self: *const TextBlob, texel_offset: u32) LayerInfoLoc {
        return self.layerInfoLoc(texel_offset);
    }

    fn layerInfoLoc(self: *const TextBlob, texel_offset: u32) LayerInfoLoc {
        return .{
            .x = @intCast(texel_offset % self.paint_layer_info_width),
            .y = @intCast(texel_offset / self.paint_layer_info_width),
        };
    }

    fn validateRebindAtlas(self: *const TextBlob, new_atlas: *const TextAtlas) !void {
        if (!new_atlas.canRebindFrom(self.atlas)) return error.WrongTextAtlasSnapshot;

        for (self.glyphs) |glyph| {
            if (!new_atlas.hasPreparedGlyph(glyph.face_index, glyph.glyph_id)) return error.MissingPreparedGlyph;
        }
    }

    /// Return a new blob bound to a compatible atlas snapshot without
    /// rebuilding its glyph list. The new atlas must share the same font
    /// config, retain the old pages as a prefix, and contain every glyph
    /// referenced by the blob.
    pub fn rebound(self: *const TextBlob, allocator: Allocator, new_atlas: *const TextAtlas) !TextBlob {
        try self.validateRebindAtlas(new_atlas);

        const glyphs = try allocator.dupe(Glyph, self.glyphs);
        errdefer allocator.free(glyphs);

        const paint_layer_info_data = if (self.paint_layer_info_data) |data|
            try allocator.dupe(f32, data)
        else
            null;
        errdefer if (paint_layer_info_data) |data| allocator.free(data);

        const paint_image_records = if (self.paint_image_records) |records|
            try allocator.dupe(?PaintImageRecord, records)
        else
            null;
        errdefer if (paint_image_records) |records| allocator.free(records);

        return .{
            .allocator = allocator,
            .atlas = new_atlas,
            .atlas_identity = new_atlas.snapshotIdentity(),
            .glyphs = glyphs,
            .paint_layer_info_data = paint_layer_info_data,
            .paint_layer_info_width = self.paint_layer_info_width,
            .paint_layer_info_height = self.paint_layer_info_height,
            .paint_image_records = paint_image_records,
            .gpu_instance_budget = textBlobGpuInstanceBudgetForAtlas(new_atlas, glyphs),
        };
    }

    pub fn init(
        allocator: Allocator,
        atlas: *const TextAtlas,
        append: TextAppend,
    ) !TextBlob {
        var builder = TextBlobBuilder.init(allocator, atlas);
        errdefer builder.deinit();
        _ = try appendShapedTextBlob(atlas, &builder, append, false);
        return builder.finish();
    }
};

pub const TextBlobBuilder = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    glyphs: std.ArrayListUnmanaged(TextBlob.Glyph) = .empty,
    paint_records: std.ArrayListUnmanaged(PendingPaintRecord) = .empty,
    hint_records: std.ArrayListUnmanaged(PendingHintRecord) = .empty,
    hint_record_refs: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    gpu_instance_budget: usize = 0,

    const PendingPaintRecord = struct {
        band_entry: band_tex.GlyphBandEntry,
        paint: Paint,
    };

    const PendingHintRecord = struct {
        record: text_hint.GlyphRecord,
        curve_deltas_f16: []u16,
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
        self.clearHintRecords();
        self.hint_records.deinit(self.allocator);
        self.hint_record_refs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *TextBlobBuilder) void {
        self.glyphs.clearRetainingCapacity();
        self.paint_records.clearRetainingCapacity();
        self.clearHintRecords();
        self.hint_record_refs.clearRetainingCapacity();
        self.gpu_instance_budget = 0;
    }

    pub fn glyphCount(self: *const TextBlobBuilder) usize {
        return self.glyphs.items.len;
    }

    pub fn finish(self: *TextBlobBuilder) !TextBlob {
        const owned = try self.glyphs.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned);
        const paint_info = try self.finishLayerInfoRecords(owned);
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
        return appendShapedTextBlob(self.atlas, self, text_append, true);
    }

    pub fn appendHintedGlyph(
        self: *TextBlobBuilder,
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        color: [4]f32,
        record: text_hint.GlyphRecord,
        curve_deltas_f16: []const u16,
    ) !void {
        const expected_deltas = @as(usize, record.curve_count) * text_hint.delta_values_per_curve;
        if (curve_deltas_f16.len != expected_deltas) return error.InvalidHintDeltaCount;

        const hint_index: u32 = @intCast(self.hint_records.items.len);
        const deltas = try self.allocator.dupe(u16, curve_deltas_f16);
        errdefer self.allocator.free(deltas);
        try self.hint_records.append(self.allocator, .{
            .record = record,
            .curve_deltas_f16 = deltas,
        });
        errdefer self.removeLastHintRecord();

        try self.glyphs.append(self.allocator, .{
            .face_index = face_index,
            .glyph_id = glyph_id,
            .transform = transform,
            .embolden = 0,
            .color = color,
            .hint_record_texel = hint_index,
            .hint_bbox = record.bbox,
        });
        self.gpu_instance_budget += 1;
    }

    pub fn appendHintedGlyphRef(
        self: *TextBlobBuilder,
        face_index: FaceIndex,
        glyph_id: u16,
        transform: Transform2D,
        color: [4]f32,
        value: *const HintedGlyphValue,
    ) !void {
        const attachment = value.attachment orelse return error.EmptyHintedGlyph;
        const intern_key = @intFromPtr(value);
        const intern = try self.internHintRecord(intern_key, attachment.record, attachment.curve_deltas_f16);
        errdefer if (intern.created) self.removeInternedHintRecord(intern_key, intern.index);

        try self.glyphs.append(self.allocator, .{
            .face_index = face_index,
            .glyph_id = glyph_id,
            .transform = transform,
            .embolden = 0,
            .color = color,
            .hint_record_texel = intern.index,
            .hint_bbox = value.bbox,
        });
        self.gpu_instance_budget += 1;
    }

    const FinishedLayerInfoRecords = struct {
        data: ?[]f32 = null,
        width: u32 = 0,
        height: u32 = 0,
        image_records: ?[]?PaintImageRecord = null,
    };

    fn finishLayerInfoRecords(self: *TextBlobBuilder, glyphs: []TextBlob.Glyph) !FinishedLayerInfoRecords {
        const paint_count = self.paint_records.items.len;
        const hint_count = self.hint_records.items.len;
        if (paint_count == 0 and hint_count == 0) return .{};

        const hint_offsets = try self.computeHintRecordOffsets(paint_count);
        defer self.allocator.free(hint_offsets);
        const texel_count = totalLayerInfoTexels(paint_count, self.hint_records.items);
        const width = text_hint.infoWidth(texel_count);
        const height = @max(@as(u32, 1), (texel_count + width - 1) / width);
        const data = try self.allocator.alloc(f32, @as(usize, width) * @as(usize, height) * 4);
        errdefer self.allocator.free(data);
        @memset(data, 0);

        const image_records = try self.allocator.alloc(?PaintImageRecord, @max(paint_count, 1));
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

        for (self.hint_records.items, hint_offsets) |record, texel_offset| {
            try text_hint.writeGlyphRecord(data, width, texel_offset, record.record, record.curve_deltas_f16);
        }
        patchHintGlyphTexels(glyphs, hint_offsets);

        self.paint_records.clearRetainingCapacity();
        self.clearHintRecords();
        self.hint_record_refs.clearRetainingCapacity();

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

    fn computeHintRecordOffsets(self: *TextBlobBuilder, paint_count: usize) ![]u32 {
        const offsets = try self.allocator.alloc(u32, self.hint_records.items.len);
        errdefer self.allocator.free(offsets);

        var texel_offset: u32 = @intCast(paint_count * paint_records.texels_per_record);
        for (self.hint_records.items, offsets) |record, *offset| {
            offset.* = texel_offset;
            texel_offset += text_hint.recordTexelCount(record.record.curve_count);
        }
        return offsets;
    }

    fn clearHintRecords(self: *TextBlobBuilder) void {
        for (self.hint_records.items) |record| self.allocator.free(record.curve_deltas_f16);
        self.hint_records.clearRetainingCapacity();
    }

    fn removeLastHintRecord(self: *TextBlobBuilder) void {
        std.debug.assert(self.hint_records.items.len > 0);
        const last_index = self.hint_records.items.len - 1;
        self.allocator.free(self.hint_records.items[last_index].curve_deltas_f16);
        self.hint_records.items.len = last_index;
    }

    const InternedHintRecord = struct {
        index: u32,
        created: bool,
    };

    fn internHintRecord(
        self: *TextBlobBuilder,
        intern_key: usize,
        record: text_hint.GlyphRecord,
        curve_deltas_f16: []const u16,
    ) !InternedHintRecord {
        if (self.hint_record_refs.get(intern_key)) |index| return .{ .index = index, .created = false };

        const index: u32 = @intCast(self.hint_records.items.len);
        const deltas = try self.allocator.dupe(u16, curve_deltas_f16);
        errdefer self.allocator.free(deltas);
        try self.hint_records.append(self.allocator, .{
            .record = record,
            .curve_deltas_f16 = deltas,
        });
        errdefer self.removeLastHintRecord();
        try self.hint_record_refs.put(self.allocator, intern_key, index);
        return .{ .index = index, .created = true };
    }

    fn removeInternedHintRecord(self: *TextBlobBuilder, intern_key: usize, index: u32) void {
        _ = self.hint_record_refs.remove(intern_key);
        std.debug.assert(index + 1 == self.hint_records.items.len);
        self.removeLastHintRecord();
    }
};

pub fn appendShapedTextBlob(
    atlas: *const TextAtlas,
    builder: *TextBlobBuilder,
    append: TextAppend,
    allow_missing: bool,
) !TextAppendResult {
    std.debug.assert(builder.atlas == atlas);
    const shaped = append.shaped;
    if (shaped.config != atlas.config) return error.WrongTextAtlasSnapshot;
    const range = append.glyphs.resolve(shaped.glyphs.len);
    const pen_origin = shapedPenAt(shaped, range.start);

    var missing = false;
    for (shaped.glyphs[range.start..range.end]) |glyph| {
        const fc = &atlas.config.faces[glyph.face_index];
        const face_view = atlas.faceView(glyph.face_index, .{});
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

fn textBlobGpuInstanceBudgetForAtlas(atlas: *const TextAtlas, glyphs: []const TextBlob.Glyph) usize {
    var total: usize = 0;
    for (glyphs) |glyph| {
        if (glyph.hint_record_texel != null) {
            total += 1;
            continue;
        }
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

pub fn textBlobRangeGpuInstanceBudget(blob: *const TextBlob, range: Range.Resolved) usize {
    var total: usize = 0;
    for (blob.glyphs[range.start..range.end]) |glyph| {
        if (glyph.hint_record_texel != null) {
            total += 1;
            continue;
        }
        const face_view = blob.atlas.faceView(glyph.face_index, .{});
        const base_budget = glyphInstanceBudget(&face_view, glyph.glyph_id);
        total += base_budget;
        if (glyph.embolden != 0 and glyph.glyph_id != 0) {
            total += base_budget;
        }
    }
    return total;
}

const BlobGlyphPaint = struct {
    color: [4]f32,
    record_index: ?u32 = null,
};

fn appendBlobGlyphPaint(
    builder: *TextBlobBuilder,
    face_view: *const FaceView,
    glyph_id: u16,
    fill: Paint,
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
    transform: Transform2D,
    color: [4]f32,
    paint_record_index: ?u32,
    synthetic: SyntheticStyle,
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

fn totalLayerInfoTexels(paint_count: usize, hint_records: []const TextBlobBuilder.PendingHintRecord) u32 {
    var total: u32 = @intCast(paint_count * paint_records.texels_per_record);
    for (hint_records) |record| total += text_hint.recordTexelCount(record.record.curve_count);
    return total;
}

fn patchHintGlyphTexels(glyphs: []TextBlob.Glyph, hint_offsets: []const u32) void {
    for (glyphs) |*glyph| {
        const hint_index = glyph.hint_record_texel orelse continue;
        if (hint_index >= hint_offsets.len) continue;
        glyph.hint_record_texel = hint_offsets[hint_index];
    }
}

fn emptyBBox() BBox {
    return .{ .min = Vec2.zero, .max = Vec2.zero };
}
