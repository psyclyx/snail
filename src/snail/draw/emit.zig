//! `emit`: write GPU-ready vertex bytes for a flat shape slice resolved
//! against an `Atlas`, plus homogeneous `DrawSegment`s describing the binding
//! and semantic family of each contiguous instance run.
//!
//! `emit` walks shape lists and writes one 23-word `Instance` per shape into
//! caller-provided buffers. Consecutive instances and calls that share a
//! binding, semantic family, and word contiguity coalesce their segments.
//!
//! These functions operate on a raw `[]const Shape` directly; whatever
//! container the caller uses to organize their scene (an owned slice, an
//! arena-bumped buffer, a borrowed slice from a custom scene-graph) feeds
//! its shapes through unchanged.

const std = @import("std");
const math = @import("../math/vec.zig");
const vertex = @import("../format/vertex.zig");
const instance_emit = @import("../format/instance_emit.zig");
const atlas_mod = @import("../atlas.zig");
const autohint_policy = @import("../font/autohint/policy.zig");
const draw_records = @import("records.zig");
const shape_mod = @import("shape.zig");

const InstanceCursor = instance_emit.Cursor;

pub const Transform2D = math.Transform2D;
pub const Atlas = atlas_mod.Atlas;
pub const Binding = draw_records.Binding;
pub const DrawSegment = draw_records.DrawSegment;
pub const Shape = shape_mod.Shape;

const WORDS_PER_INSTANCE = vertex.WORDS_PER_INSTANCE;

pub const EmitError = error{
    /// The shape slice references a key not present in the atlas.
    MissingRecord,
    /// A shape's composed transform had near-zero determinant.
    InvalidTransform,
    /// An autohint analysis shape omitted its draw-time fitting policy.
    MissingAutohintPolicy,
    /// A non-autohint shape supplied an autohint fitting policy.
    UnexpectedAutohintPolicy,
    /// The supplied autohint policy failed semantic validation.
    InvalidAutohintPolicy,
    /// `words_buf` or `segs_buf` ran out of room.
    BufferTooSmall,
    /// A page index exceeded the vertex format's u8 `atlas_layer` slot.
    AtlasLayerOverflow,
    /// `binding.info_row_base + paint_info.info_y` exceeded the
    /// vertex format's u16 `info_y` slot. Caller's cache holds too
    /// much layer-info; either release retired bindings or shrink.
    InfoRowOverflow,
};

fn addRowBase(info_y: u16, row_base: u32) EmitError!u16 {
    const sum = @as(u32, info_y) + row_base;
    if (sum > std.math.maxInt(u16)) return error.InfoRowOverflow;
    return @intCast(sum);
}

pub const EmitResult = struct {
    shape_count: u32,
    word_count: u32,
    segment_count: u32,
};

/// Heterogeneous emit. One pre-composed `Instance` per shape in `shapes`,
/// transform composed as `world_xform * shape.local_transform`, color as
/// `shape.local_color`, tint as `world_tint`.
pub fn emit(
    words_buf: []u32,
    segs_buf: []DrawSegment,
    word_len: *usize,
    seg_len: *usize,
    binding: Binding,
    atlas: *const Atlas,
    shapes: []const Shape,
    world_xform: Transform2D,
    world_tint: [4]f32,
) EmitError!EmitResult {
    const need_words = shapes.len * WORDS_PER_INSTANCE;
    if (words_buf.len - word_len.* < need_words) return error.BufferTooSmall;

    var cursor: usize = word_len.*;
    const cur = InstanceCursor{ .buf = words_buf, .len = &cursor };
    var emitted: u32 = 0;
    var working_seg_len = seg_len.*;
    var segments_added: u32 = 0;

    for (shapes) |shape| {
        const rec = atlas.lookupRecord(shape.key) orelse {
            return error.MissingRecord;
        };

        // Empty records are non-rendering glyphs (spaces, zero-contour
        // controls). Their semantic side records are intentionally optional;
        // skip before validating mode-specific metadata.
        if (rec.curve_count == 0) continue;

        const ah_info_opt = atlas.lookupAutohintRecord(shape.key);
        const packed_policy = if (ah_info_opt != null) blk: {
            const policy = shape.autohint_policy orelse return error.MissingAutohintPolicy;
            policy.validate() catch return error.InvalidAutohintPolicy;
            break :blk policy.pack();
        } else blk: {
            if (shape.autohint_policy != null) return error.UnexpectedAutohintPolicy;
            break :blk [_]u32{0} ** 7;
        };

        const page = atlas.pages[rec.page_index];
        if (page.layer_index > std.math.maxInt(u8)) return error.AtlasLayerOverflow;
        const atlas_layer: u8 = @intCast(page.layer_index);

        const final_transform = Transform2D.multiply(world_xform, shape.local_transform);

        if (ah_info_opt) |ah_info| {
            // Warped instance over the shared base glyph.
            try cur.appendAutohintTransformedTinted(
                rec.bbox,
                ah_info.info_x,
                try addRowBase(ah_info.info_y, binding.info_row_base),
                ah_info.layer_count,
                shape.local_color,
                world_tint,
                atlas_layer,
                final_transform,
                packed_policy,
            );
        } else if (atlas.lookupTtHintedRecord(shape.key)) |hinted_info| {
            try cur.appendTtHintedTextTransformedTinted(
                rec.bbox,
                hinted_info.info_x,
                try addRowBase(hinted_info.info_y, binding.info_row_base),
                hinted_info.layer_count,
                shape.local_color,
                world_tint,
                atlas_layer,
                final_transform,
            );
        } else if (atlas.lookupPaintRecord(shape.key)) |paint_info| {
            if (shape.key.namespace == record_key_mod.ns.unhinted_glyph) {
                try cur.appendMultiLayerGlyphTransformedTinted(
                    rec.bbox,
                    paint_info.info_x,
                    try addRowBase(paint_info.info_y, binding.info_row_base),
                    paint_info.layer_count,
                    shape.local_color,
                    world_tint,
                    atlas_layer,
                    final_transform,
                );
            } else {
                try cur.appendPathRecordTransformedTinted(
                    rec.bbox,
                    paint_info.info_x,
                    try addRowBase(paint_info.info_y, binding.info_row_base),
                    paint_info.layer_count,
                    shape.local_color,
                    world_tint,
                    atlas_layer,
                    final_transform,
                );
            }
        } else {
            try cur.appendGlyphTransformedTinted(
                rec.bbox,
                .{
                    .glyph_x = rec.bands.glyph_x,
                    .glyph_y = rec.bands.glyph_y,
                    .h_band_count = rec.bands.h_band_count,
                    .v_band_count = rec.bands.v_band_count,
                    .band_scale_x = rec.bands.band_scale_x,
                    .band_scale_y = rec.bands.band_scale_y,
                    .band_offset_x = rec.bands.band_offset_x,
                    .band_offset_y = rec.bands.band_offset_y,
                },
                shape.local_color,
                world_tint,
                atlas_layer,
                final_transform,
            );
        }

        const instance_word_offset = cursor - WORDS_PER_INSTANCE;
        const kind = draw_records.shapeKind(words_buf[0..cursor], instance_word_offset / WORDS_PER_INSTANCE);
        const segment = DrawSegment{
            .binding = binding,
            .words_offset = @intCast(instance_word_offset),
            .words_len = @intCast(WORDS_PER_INSTANCE),
            .shape_count = 1,
            .kind = kind,
        };
        if (!draw_records.mergeIfAdjacent(segs_buf, &working_seg_len, segment)) {
            if (working_seg_len >= segs_buf.len) return error.BufferTooSmall;
            segs_buf[working_seg_len] = segment;
            working_seg_len += 1;
            segments_added += 1;
        }
        emitted += 1;
    }

    const wrote_words: u32 = @intCast(cursor - word_len.*);
    word_len.* = cursor;
    seg_len.* = working_seg_len;

    if (emitted == 0) {
        return .{ .shape_count = 0, .word_count = 0, .segment_count = 0 };
    }

    return .{
        .shape_count = emitted,
        .word_count = wrote_words,
        .segment_count = segments_added,
    };
}

/// Conservative upper bound on words written for an `emit` call.
pub fn wordBudget(shape_count: usize) usize {
    return shape_count * WORDS_PER_INSTANCE;
}

/// Conservative upper bound on segments written for one emit call.
pub fn segmentBudget(shape_count: usize) usize {
    return shape_count;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const record_key_mod = @import("../atlas/record_key.zig");
const curves_mod = @import("../atlas/curves.zig");
const page_pool_mod = @import("../atlas/page_pool.zig");
const curve_tex_format = @import("../format/curve_texture.zig");

const PagePool = page_pool_mod.PagePool;
const GlyphCurves = curves_mod.GlyphCurves;

fn makeTinyCurves(allocator: std.mem.Allocator) !GlyphCurves {
    const curve_words = curve_tex_format.SEGMENT_TEXELS * 4; // one segment
    const curve_bytes = try allocator.alloc(u16, curve_words);
    for (curve_bytes, 0..) |*w, i| w.* = @intCast(@as(u16, @intCast(i)) +% 0x100);

    // 1 h-band + 1 v-band, 1 ref each.
    const band_bytes = try allocator.alloc(u16, 8);
    band_bytes[0] = 1; // h-band count
    band_bytes[1] = 2; // h-band offset
    band_bytes[2] = 1; // v-band count
    band_bytes[3] = 3; // v-band offset
    band_bytes[4] = 0; // h-band ref0: cx=0
    band_bytes[5] = 0; // cy=0
    band_bytes[6] = 0; // v-band ref0: cx=0
    band_bytes[7] = 0;

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = 1,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
        .bbox = .{ .min = .zero, .max = .{ .x = 1, .y = 1 } },
    };
}

fn buildAutohintTestAtlas(pool: *PagePool) !atlas_mod.Atlas {
    const base_key = record_key_mod.unhintedGlyph(0, 1);
    const key = record_key_mod.autohintGlyph(0, 1);
    var curves = try makeTinyCurves(testing.allocator);
    defer curves.deinit();
    const x = [_]@import("../font/autohint/producer.zig").FeatureEdge{.{
        .pos = 0.2,
        .width = 0.1,
        .stem = -1,
        .blue = -1,
        .flags = .{ .round = false },
    }};
    return atlas_mod.Atlas.from(testing.allocator, pool, &.{
        .{ .key = base_key, .curves = curves },
        .{
            .key = key,
            .curves = GlyphCurves.empty(testing.allocator),
            .autohint = .{
                .font = .{ .blues = &.{}, .std_x = 0.1, .std_y = 0 },
                .glyph = .{ .x = &x, .y = &.{}, .left = 0 },
            },
            .autohint_base = base_key,
        },
    });
}

fn buildTestAtlas(pool: *PagePool, keys: []const u16) !atlas_mod.Atlas {
    var owned: std.ArrayList(GlyphCurves) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(testing.allocator);
    }
    var entries: std.ArrayList(atlas_mod.Entry) = .empty;
    defer entries.deinit(testing.allocator);

    for (keys) |k| {
        const c = try makeTinyCurves(testing.allocator);
        try owned.append(testing.allocator, c);
        try entries.append(testing.allocator, .{
            .key = record_key_mod.unhintedGlyph(0, k),
            .curves = owned.items[owned.items.len - 1],
        });
    }
    return atlas_mod.Atlas.from(testing.allocator, pool, entries.items);
}

test "autohint shapes share lookup data and emit distinct seven-word policies" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildAutohintTestAtlas(pool);
    defer atlas.deinit();

    const key = record_key_mod.autohintGlyph(0, 1);
    const policy_a: shape_mod.AutohintPolicy = .{ .x = .{ .@"align" = .grid } };
    const policy_b: shape_mod.AutohintPolicy = .{ .x = .{ .@"align" = .grid, .positioning = .relative } };
    const shapes = [_]Shape{
        .{ .key = key, .autohint_policy = policy_a },
        .{ .key = key, .autohint_policy = policy_b },
    };
    try testing.expectEqual(shapes[0].key, shapes[1].key);
    const lookup_before = atlas.lookupAutohintRecord(key).?;
    const slab_ptr = atlas.layer_info_data.?.ptr;
    const slab_len = atlas.layer_info_data.?.len;

    var words: [2 * WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit(&words, &segs, &wlen, &slen, .{ .pool = pool }, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    const decoded_a = vertex.decodeInstance(words[0..WORDS_PER_INSTANCE]);
    const decoded_b = vertex.decodeInstance(words[WORDS_PER_INSTANCE..]);
    const packed_a = policy_a.pack();
    const packed_b = policy_b.pack();
    try testing.expectEqualSlices(u32, &packed_a, &decoded_a.policy);
    try testing.expectEqualSlices(u32, &packed_b, &decoded_b.policy);
    try testing.expect(!std.mem.eql(u32, &decoded_a.policy, &decoded_b.policy));
    try testing.expectEqualDeep(lookup_before, atlas.lookupAutohintRecord(key).?);
    try testing.expectEqual(slab_ptr, atlas.layer_info_data.?.ptr);
    try testing.expectEqual(slab_len, atlas.layer_info_data.?.len);

    try testing.expectEqual(draw_records.ShapeKind.autohint, segs[0].kind);
}

test "emit enforces autohint policy presence and placement" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildAutohintTestAtlas(pool);
    defer atlas.deinit();
    var words: [WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    const binding = Binding{ .pool = pool };

    try testing.expectError(error.MissingAutohintPolicy, emit(&words, &segs, &wlen, &slen, binding, &atlas, &.{.{ .key = record_key_mod.autohintGlyph(0, 1) }}, .identity, .{ 1, 1, 1, 1 }));
    try testing.expectError(error.UnexpectedAutohintPolicy, emit(&words, &segs, &wlen, &slen, binding, &atlas, &.{.{ .key = record_key_mod.unhintedGlyph(0, 1), .autohint_policy = .{} }}, .identity, .{ 1, 1, 1, 1 }));

    const invalid: autohint_policy.AutohintPolicy = .{
        .y = .{
            .@"align" = .blue_zones,
            .overshoot = .{ .suppress_below_px = std.math.nan(f32) },
        },
    };
    try testing.expectError(error.InvalidAutohintPolicy, emit(&words, &segs, &wlen, &slen, binding, &atlas, &.{.{
        .key = record_key_mod.autohintGlyph(0, 1),
        .autohint_policy = invalid,
    }}, .identity, .{ 1, 1, 1, 1 }));
}

test "emit writes one instance per shape" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var atlas = try buildTestAtlas(pool, &.{ 1, 2 });
    defer atlas.deinit();

    const shapes = [_]Shape{
        .{ .key = record_key_mod.unhintedGlyph(0, 1), .local_transform = .translate(10, 20) },
        .{ .key = record_key_mod.unhintedGlyph(0, 2), .local_transform = .translate(30, 40) },
    };
    const need = wordBudget(shapes.len);
    const words = try testing.allocator.alloc(u32, need);
    defer testing.allocator.free(words);
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    const binding = Binding{ .pool = pool };
    const result = try emit(words, segs[0..], &wlen, &slen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(u32, 2), result.shape_count);
    try testing.expectEqual(@as(u32, 2 * WORDS_PER_INSTANCE), result.word_count);
    try testing.expectEqual(@as(u32, 1), result.segment_count);
    try testing.expectEqual(@as(usize, 1), slen);
    try testing.expectEqual(@as(u32, 2), segs[0].shape_count);
    try testing.expectEqual(@as(u32, 0), segs[0].words_offset);

    // The composed transform on instance 0 should match the shape's local
    // transform (world is identity).
    const inst0 = vertex.decodeInstance(words[0..WORDS_PER_INSTANCE]);
    try testing.expectApproxEqAbs(@as(f32, 10), inst0.origin[0], 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 20), inst0.origin[1], 1e-5);
}

test "emit matches generateGlyphVerticesTransformedTinted byte-for-byte" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var atlas = try buildTestAtlas(pool, &.{1});
    defer atlas.deinit();

    const key = record_key_mod.unhintedGlyph(0, 1);
    const local_t = Transform2D{ .xx = 1.5, .xy = 0.0, .tx = 4.0, .yx = 0.0, .yy = -1.5, .ty = 7.0 };
    const local_color = [4]f32{ 0.25, 0.5, 0.75, 1.0 };
    const world_t = Transform2D{ .xx = 1.0, .xy = 0.0, .tx = 100.0, .yx = 0.0, .yy = 1.0, .ty = 200.0 };
    const world_tint = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    const shapes = [_]Shape{.{ .key = key, .local_transform = local_t, .local_color = local_color }};

    var words = [_]u32{0} ** (WORDS_PER_INSTANCE);
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    const binding = Binding{ .pool = pool };
    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &shapes, world_t, world_tint);

    // Now produce the same instance through the existing vertex helper.
    const rec = atlas.lookupRecord(key).?;
    const final_t = Transform2D.multiply(world_t, local_t);

    var direct = [_]u32{0} ** (WORDS_PER_INSTANCE);
    try testing.expect(vertex.generateGlyphVerticesTransformedTinted(
        &direct,
        rec.bbox,
        .{
            .glyph_x = rec.bands.glyph_x,
            .glyph_y = rec.bands.glyph_y,
            .h_band_count = rec.bands.h_band_count,
            .v_band_count = rec.bands.v_band_count,
            .band_scale_x = rec.bands.band_scale_x,
            .band_scale_y = rec.bands.band_scale_y,
            .band_offset_x = rec.bands.band_offset_x,
            .band_offset_y = rec.bands.band_offset_y,
        },
        local_color,
        world_tint,
        @intCast(atlas.pages[rec.page_index].layer_index),
        final_t,
    ));

    try testing.expectEqualSlices(u32, &direct, &words);
}

test "emit reports MissingRecord on unknown key" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 512,
        .band_words_per_page = 128,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{1});
    defer atlas.deinit();

    const shapes = [_]Shape{.{ .key = record_key_mod.unhintedGlyph(0, 99) }};

    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    const binding = Binding{ .pool = pool };
    try testing.expectError(EmitError.MissingRecord, emit(&buf, segs[0..], &wlen, &slen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 }));
}

test "emit coalesces adjacent same-binding calls" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2 });
    defer atlas.deinit();

    const shapes_a = [_]Shape{.{ .key = record_key_mod.unhintedGlyph(0, 1) }};
    const shapes_b = [_]Shape{.{ .key = record_key_mod.unhintedGlyph(0, 2) }};

    var words: [4 * WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    const binding = Binding{ .pool = pool };

    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &shapes_a, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &shapes_b, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 1), slen);
    try testing.expectEqual(@as(u32, 2), segs[0].shape_count);
    try testing.expectEqual(@as(u32, 2 * WORDS_PER_INSTANCE), segs[0].words_len);
}

test "emit splits contiguous shapes into exact semantic segments" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();

    var regular_curves = try makeTinyCurves(testing.allocator);
    defer regular_curves.deinit();
    var path_curves = try makeTinyCurves(testing.allocator);
    defer path_curves.deinit();
    const regular_key = record_key_mod.unhintedGlyph(0, 1);
    const colr_key = record_key_mod.unhintedGlyph(1, 2);
    const path_key = record_key_mod.RecordKey{ .namespace = record_key_mod.ns.path_fill, .a = 1 };
    const hinted_key = record_key_mod.ttHintedGlyph(0, 3, 16 * 64);
    var atlas = try Atlas.from(testing.allocator, pool, &.{
        .{ .key = regular_key, .curves = regular_curves },
        .{ .key = colr_key, .curves = regular_curves, .paint = .{ .solid = .{ 1, 0, 0, 1 } } },
        .{ .key = path_key, .curves = path_curves, .paint = .{ .solid = .{ 1, 1, 1, 1 } } },
        .{ .key = hinted_key, .curves = regular_curves },
    });
    defer atlas.deinit();

    const shapes = [_]Shape{
        .{ .key = regular_key },
        .{ .key = colr_key },
        .{ .key = path_key },
        .{ .key = hinted_key },
        .{ .key = regular_key },
    };
    var words: [5 * WORDS_PER_INSTANCE]u32 = undefined;
    var segments: [5]DrawSegment = undefined;
    var word_len: usize = 0;
    var segment_len: usize = 0;
    const result = try emit(&words, &segments, &word_len, &segment_len, .{ .pool = pool }, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(u32, 5), result.segment_count);
    try testing.expectEqual(@as(usize, 5), segment_len);
    try testing.expectEqual(draw_records.ShapeKind.regular, segments[0].kind);
    try testing.expectEqual(draw_records.ShapeKind.colr, segments[1].kind);
    try testing.expectEqual(draw_records.ShapeKind.path, segments[2].kind);
    try testing.expectEqual(draw_records.ShapeKind.tt_hinted_text, segments[3].kind);
    try testing.expectEqual(draw_records.ShapeKind.regular, segments[4].kind);
    for (segments) |segment| {
        try testing.expectEqual(@as(u32, 1), segment.shape_count);
        try testing.expectEqual(@as(u32, WORDS_PER_INSTANCE), segment.words_len);
    }
}

test "emit produces separate segments for different bindings" {
    var pool_a = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 512,
        .band_words_per_page = 128,
    });
    defer pool_a.deinit();
    var pool_b = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 512,
        .band_words_per_page = 128,
    });
    defer pool_b.deinit();

    var atlas_a = try buildTestAtlas(pool_a, &.{1});
    defer atlas_a.deinit();
    var atlas_b = try buildTestAtlas(pool_b, &.{2});
    defer atlas_b.deinit();

    const shapes_a = [_]Shape{.{ .key = record_key_mod.unhintedGlyph(0, 1) }};
    const shapes_b = [_]Shape{.{ .key = record_key_mod.unhintedGlyph(0, 2) }};

    var words: [4 * WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    _ = try emit(&words, segs[0..], &wlen, &slen, .{ .pool = pool_a }, &atlas_a, &shapes_a, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&words, segs[0..], &wlen, &slen, .{ .pool = pool_b }, &atlas_b, &shapes_b, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 2), slen);
    try testing.expect(segs[0].binding.pool == pool_a);
    try testing.expect(segs[1].binding.pool == pool_b);
}

test "wordBudget bounds match actual emit output" {
    const shape_count: usize = 3;
    try testing.expectEqual(@as(usize, 3 * WORDS_PER_INSTANCE), wordBudget(shape_count));
    try testing.expectEqual(shape_count, segmentBudget(shape_count));
}
