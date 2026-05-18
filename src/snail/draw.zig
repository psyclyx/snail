const std = @import("std");

const path_mod = @import("path.zig");
const prepared_mod = @import("resources/prepared.zig");
const resource_key_mod = @import("resource_key.zig");
const scene_mod = @import("scene.zig");
const target_mod = @import("target.zig");
const text_mod = @import("text.zig");

pub const DrawState = target_mod.DrawState;
pub const DrawPass = target_mod.DrawPass;
pub const TargetSurface = target_mod.TargetSurface;
pub const TargetEncoding = target_mod.TargetEncoding;
pub const PixelRect = target_mod.PixelRect;
pub const ResolveRegion = target_mod.ResolveRegion;
pub const ResolveBackdrop = target_mod.ResolveBackdrop;
pub const IntermediateFormat = target_mod.IntermediateFormat;
pub const LinearResolve = target_mod.LinearResolve;
pub const ColorEncoding = target_mod.ColorEncoding;
pub const CoverageTransfer = target_mod.CoverageTransfer;
pub const SubpixelOrder = target_mod.SubpixelOrder;

pub const DrawKind = enum { text, path };
const PathBatch = path_mod.PathBatch;
const PATH_WORDS_PER_SHAPE = path_mod.PATH_WORDS_PER_SHAPE;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceStamp = resource_key_mod.ResourceStamp;
const Scene = scene_mod.Scene;
const TextBatch = text_mod.TextBatch;
const TEXT_WORDS_PER_GLYPH = text_mod.TEXT_WORDS_PER_GLYPH;

pub const DrawSegment = struct {
    kind: DrawKind,
    offset: usize,
    len: usize,
    texture_layer_base: u32 = 0,
    key: ResourceKey,
    resource_stamp: ResourceStamp,
};

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const DrawSegment,
};

const SegmentSink = union(enum) {
    fixed: Fixed,
    dynamic: Dynamic,

    const Fixed = struct {
        buf: []DrawSegment,
        len: *usize,
    };

    const Dynamic = struct {
        allocator: std.mem.Allocator,
        segments: *std.ArrayList(DrawSegment),
    };

    fn mergeIfAdjacent(prev: *DrawSegment, segment: DrawSegment) bool {
        if (prev.kind != segment.kind) return false;
        if (prev.offset + prev.len != segment.offset) return false;
        if (prev.texture_layer_base != segment.texture_layer_base) return false;
        if (!prev.key.eql(segment.key)) return false;
        if (!prev.resource_stamp.eql(segment.resource_stamp)) return false;
        prev.len += segment.len;
        return true;
    }

    fn add(self: *SegmentSink, segment: DrawSegment) !void {
        switch (self.*) {
            .fixed => |fixed| {
                if (fixed.len.* > 0 and mergeIfAdjacent(&fixed.buf[fixed.len.* - 1], segment)) return;
                if (fixed.len.* >= fixed.buf.len) return error.DrawListFull;
                fixed.buf[fixed.len.*] = segment;
                fixed.len.* += 1;
            },
            .dynamic => |dynamic| {
                if (dynamic.segments.items.len > 0 and mergeIfAdjacent(&dynamic.segments.items[dynamic.segments.items.len - 1], segment)) return;
                try dynamic.segments.append(dynamic.allocator, segment);
            },
        }
    }
};

pub const DrawList = struct {
    buf: []u32,
    len: usize = 0,
    segments_buf: []DrawSegment,
    segment_len: usize = 0,

    pub fn init(buf: []u32, segments_buf: []DrawSegment) DrawList {
        return .{ .buf = buf, .segments_buf = segments_buf };
    }

    pub fn reset(self: *DrawList) void {
        self.len = 0;
        self.segment_len = 0;
    }

    pub fn slice(self: *const DrawList) DrawRecords {
        return .{
            .words = self.buf[0..self.len],
            .segments = self.segments_buf[0..self.segment_len],
        };
    }

    /// Return an upper bound for the word buffer required by `addScene`.
    pub fn estimate(scene: *const Scene) usize {
        return estimateWords(scene);
    }

    fn estimateWords(scene: *const Scene) usize {
        var total: usize = 0;
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |draw| {
                    const glyphs = draw.glyphs.resolve(draw.blob.glyphCount());
                    const range_budget = if (glyphs.start == 0 and glyphs.end == draw.blob.glyphCount())
                        draw.blob.gpu_instance_budget
                    else
                        text_mod.textBlobRangeGpuInstanceBudget(draw.blob, glyphs);
                    total += range_budget * draw.instances.len * TEXT_WORDS_PER_GLYPH;
                },
                .path => |draw| {
                    const range = draw.shapes.resolve(draw.picture.shapes.len);
                    const span = range.end - range.start;
                    total += span * draw.instances.len * PATH_WORDS_PER_SHAPE;
                },
            }
        }
        return total;
    }

    pub fn estimateSegments(scene: *const Scene) usize {
        return estimateSegmentUpperBound(scene);
    }

    fn estimateSegmentUpperBound(scene: *const Scene) usize {
        var total: usize = 0;
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |draw| {
                    const glyphs = draw.glyphs.resolve(draw.blob.glyphCount());
                    const span = glyphs.end - glyphs.start;
                    total += span * draw.instances.len;
                },
                .path => |draw| {
                    const range = draw.shapes.resolve(draw.picture.shapes.len);
                    const span = range.end - range.start;
                    total += span * draw.instances.len;
                },
            }
        }
        return total;
    }

    pub fn addScene(
        self: *DrawList,
        prepared: *const PreparedResources,
        scene: *const Scene,
    ) !void {
        var segments = SegmentSink{ .fixed = .{ .buf = self.segments_buf, .len = &self.segment_len } };
        try addSceneToBuffers(self.buf, &self.len, &segments, prepared, scene);
    }
};

fn addSceneToBuffers(
    words: []u32,
    word_len: *usize,
    segments: *SegmentSink,
    prepared: *const PreparedResources,
    scene: *const Scene,
) !void {
    for (scene.commands.items) |command| {
        switch (command) {
            .text => |draw| {
                var view = try prepared.textAtlasView(draw.resources.atlas);
                const segment_key, const segment_stamp = if (draw.blob.hasPaintRecords()) blk: {
                    const paint_key = draw.resources.paint orelse return error.MissingPreparedResource;
                    const paint_view = try prepared.textPaintView(paint_key);
                    view.paint_info_row_base = paint_view.info_row_base;
                    break :blk .{ paint_key, try prepared.textPaintStamp(paint_key) };
                } else blk: {
                    break :blk .{ draw.resources.atlas, try prepared.textStamp(draw.resources.atlas) };
                };
                const glyph_range = draw.glyphs.resolve(draw.blob.glyphCount());
                for (draw.instances, 0..) |_, override_index| {
                    var glyph_start = glyph_range.start;
                    while (glyph_start < glyph_range.end) {
                        const start = word_len.*;
                        var batch = TextBatch.init(words[word_len.*..]);
                        const result = try batch.addDraw(view, draw, override_index, glyph_start);
                        glyph_start = result.next_glyph;
                        if (batch.glyphCount() == 0) {
                            if (result.completed) break;
                            continue;
                        }
                        word_len.* += batch.slice().len;
                        try segments.add(.{
                            .kind = .text,
                            .offset = start,
                            .len = batch.slice().len,
                            .texture_layer_base = result.layer_window_base,
                            .key = segment_key,
                            .resource_stamp = segment_stamp,
                        });
                        if (result.completed) break;
                    }
                }
            },
            .path => |draw| {
                const view = try prepared.pathAtlasView(draw.resource_key);
                const range = draw.shapes.resolve(draw.picture.shapes.len);
                for (draw.instances, 0..) |_, override_index| {
                    var shape_start = range.start;
                    while (shape_start < range.end) {
                        const start = word_len.*;
                        var batch = PathBatch.init(words[word_len.*..]);
                        const result = try batch.addDraw(&view, draw, override_index, shape_start);
                        shape_start = result.next_shape;
                        if (batch.shapeCount() == 0) {
                            if (result.completed) break;
                            continue;
                        }
                        word_len.* += batch.slice().len;
                        try segments.add(.{
                            .kind = .path,
                            .offset = start,
                            .len = batch.slice().len,
                            .texture_layer_base = result.layer_window_base,
                            .key = draw.resource_key,
                            .resource_stamp = try prepared.pathStamp(draw.resource_key),
                        });
                        if (result.completed) break;
                    }
                }
            },
        }
    }
}

pub const PreparedScene = struct {
    allocator: std.mem.Allocator,
    words: []u32 = &.{},
    segments: []DrawSegment = &.{},

    pub fn initOwned(
        allocator: std.mem.Allocator,
        prepared: *const PreparedResources,
        scene: *const Scene,
    ) !PreparedScene {
        const needed = DrawList.estimateWords(scene);
        const words = try allocator.alloc(u32, needed);
        errdefer allocator.free(words);
        var segment_list: std.ArrayList(DrawSegment) = .empty;
        errdefer segment_list.deinit(allocator);
        try segment_list.ensureTotalCapacity(allocator, scene.commands.items.len);
        var word_len: usize = 0;
        var segment_sink = SegmentSink{ .dynamic = .{ .allocator = allocator, .segments = &segment_list } };
        try addSceneToBuffers(words, &word_len, &segment_sink, prepared, scene);
        const owned_segments = try segment_list.toOwnedSlice(allocator);
        errdefer allocator.free(owned_segments);
        return .{
            .allocator = allocator,
            .words = words[0..word_len],
            .segments = owned_segments,
        };
    }

    pub fn deinit(self: *PreparedScene) void {
        if (self.words.len > 0) self.allocator.free(self.words);
        if (self.segments.len > 0) self.allocator.free(self.segments);
        self.* = undefined;
    }

    pub fn slice(self: *const PreparedScene) DrawRecords {
        return .{
            .words = self.words,
            .segments = self.segments,
        };
    }
};
