//! `emit`: write GPU-ready `Instance`s for a flat shape slice resolved
//! against an `Atlas`, plus homogeneous `DrawBatch`es describing the binding
//! and semantic family of each contiguous instance run.
//!
//! `emit` walks shape lists and writes one packed `Instance` per shape into
//! caller-provided buffers. Consecutive instances and calls that share a
//! binding, semantic family, and contiguity coalesce their batches.
//!
//! Buffer sizing: one emit call writes at most `shapes.len` instances and
//! `shapes.len` batches past the current lengths. Instances are GPU-bound
//! bytes (`std.mem.sliceAsBytes` gives the upload view); batches stay on the
//! CPU, so the two buffers can live in different memory.
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
const WORDS_PER_INSTANCE = vertex.WORDS_PER_INSTANCE;

pub const Transform2D = math.Transform2D;
pub const Atlas = atlas_mod.Atlas;
pub const Binding = draw_records.Binding;
pub const DrawBatch = draw_records.DrawBatch;
pub const Instance = draw_records.Instance;
pub const Shape = shape_mod.Shape;

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
    /// `instances_buf` or `batches_buf` ran out of room.
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
    instance_count: u32,
    batch_count: u32,
};

/// Heterogeneous emit. One pre-composed `Instance` per shape in `shapes`,
/// transform composed as `world_xform * shape.local_transform`, color as
/// `shape.local_color`, tint as `world_tint`.
pub fn emit(
    instances_buf: []Instance,
    batches_buf: []DrawBatch,
    instance_len: *usize,
    batch_len: *usize,
    binding: Binding,
    atlas: *const Atlas,
    shapes: []const Shape,
    world_xform: Transform2D,
    world_tint: [4]f32,
) EmitError!EmitResult {
    if (instances_buf.len - instance_len.* < shapes.len) return error.BufferTooSmall;

    const words_buf: []u32 = @ptrCast(std.mem.sliceAsBytes(instances_buf));
    var cursor: usize = instance_len.* * WORDS_PER_INSTANCE;
    const cur = InstanceCursor{ .buf = words_buf, .len = &cursor };
    var emitted: u32 = 0;
    var working_batch_len = batch_len.*;
    var batches_added: u32 = 0;

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

        const instance_index = cursor / WORDS_PER_INSTANCE - 1;
        const batch = DrawBatch{
            .binding = binding,
            .first_instance = @intCast(instance_index),
            .instance_count = 1,
            .kind = draw_records.shapeKind(&instances_buf[instance_index]),
        };
        if (!draw_records.mergeIfAdjacent(batches_buf, &working_batch_len, batch)) {
            if (working_batch_len >= batches_buf.len) return error.BufferTooSmall;
            batches_buf[working_batch_len] = batch;
            working_batch_len += 1;
            batches_added += 1;
        }
        emitted += 1;
    }

    instance_len.* = cursor / WORDS_PER_INSTANCE;
    batch_len.* = working_batch_len;

    return .{
        .instance_count = emitted,
        .batch_count = batches_added,
    };
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

fn instanceWords(instances: []const Instance, index: usize) []const u32 {
    const words: []const u32 = @ptrCast(std.mem.sliceAsBytes(instances));
    return words[index * WORDS_PER_INSTANCE ..][0..WORDS_PER_INSTANCE];
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

    var instances: [2]Instance = undefined;
    var batches: [1]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit(&instances, &batches, &ilen, &blen, .{ .pool = pool }, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    const decoded_a = vertex.decodeInstance(instanceWords(&instances, 0));
    const decoded_b = vertex.decodeInstance(instanceWords(&instances, 1));
    const packed_a = policy_a.pack();
    const packed_b = policy_b.pack();
    try testing.expectEqualSlices(u32, &packed_a, &decoded_a.policy);
    try testing.expectEqualSlices(u32, &packed_b, &decoded_b.policy);
    try testing.expect(!std.mem.eql(u32, &decoded_a.policy, &decoded_b.policy));
    try testing.expectEqualDeep(lookup_before, atlas.lookupAutohintRecord(key).?);
    try testing.expectEqual(slab_ptr, atlas.layer_info_data.?.ptr);
    try testing.expectEqual(slab_len, atlas.layer_info_data.?.len);

    try testing.expectEqual(draw_records.ShapeKind.autohint, batches[0].kind);
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
    var instances: [1]Instance = undefined;
    var batches: [1]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    const binding = Binding{ .pool = pool };

    try testing.expectError(error.MissingAutohintPolicy, emit(&instances, &batches, &ilen, &blen, binding, &atlas, &.{.{ .key = record_key_mod.autohintGlyph(0, 1) }}, .identity, .{ 1, 1, 1, 1 }));
    try testing.expectError(error.UnexpectedAutohintPolicy, emit(&instances, &batches, &ilen, &blen, binding, &atlas, &.{.{ .key = record_key_mod.unhintedGlyph(0, 1), .autohint_policy = .{} }}, .identity, .{ 1, 1, 1, 1 }));

    const invalid: autohint_policy.AutohintPolicy = .{
        .y = .{
            .@"align" = .blue_zones,
            .overshoot = .{ .suppress_below_px = std.math.nan(f32) },
        },
    };
    try testing.expectError(error.InvalidAutohintPolicy, emit(&instances, &batches, &ilen, &blen, binding, &atlas, &.{.{
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
    const instances = try testing.allocator.alloc(Instance, shapes.len);
    defer testing.allocator.free(instances);
    var batches: [4]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;

    const binding = Binding{ .pool = pool };
    const result = try emit(instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(u32, 2), result.instance_count);
    try testing.expectEqual(@as(u32, 1), result.batch_count);
    try testing.expectEqual(@as(usize, 2), ilen);
    try testing.expectEqual(@as(usize, 1), blen);
    try testing.expectEqual(@as(u32, 2), batches[0].instance_count);
    try testing.expectEqual(@as(u32, 0), batches[0].first_instance);

    // The composed transform on instance 0 should match the shape's local
    // transform (world is identity).
    const inst0 = vertex.decodeInstance(instanceWords(instances, 0));
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

    var instances: [1]Instance = undefined;
    var batches: [1]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    const binding = Binding{ .pool = pool };
    _ = try emit(&instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, world_t, world_tint);

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

    try testing.expectEqualSlices(u32, &direct, instanceWords(&instances, 0));
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

    var instances: [1]Instance = undefined;
    var batches: [1]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;

    const binding = Binding{ .pool = pool };
    try testing.expectError(EmitError.MissingRecord, emit(&instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 }));
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

    var instances: [4]Instance = undefined;
    var batches: [4]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    const binding = Binding{ .pool = pool };

    _ = try emit(&instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes_a, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes_b, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 1), blen);
    try testing.expectEqual(@as(u32, 2), batches[0].instance_count);
    try testing.expectEqual(@as(u32, 0), batches[0].first_instance);
}

test "emit splits contiguous shapes into exact semantic batches" {
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
    var instances: [5]Instance = undefined;
    var batches: [5]DrawBatch = undefined;
    var instance_len: usize = 0;
    var batch_len: usize = 0;
    const result = try emit(&instances, &batches, &instance_len, &batch_len, .{ .pool = pool }, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(u32, 5), result.batch_count);
    try testing.expectEqual(@as(usize, 5), batch_len);
    try testing.expectEqual(draw_records.ShapeKind.regular, batches[0].kind);
    try testing.expectEqual(draw_records.ShapeKind.colr, batches[1].kind);
    try testing.expectEqual(draw_records.ShapeKind.path, batches[2].kind);
    try testing.expectEqual(draw_records.ShapeKind.tt_hinted_text, batches[3].kind);
    try testing.expectEqual(draw_records.ShapeKind.regular, batches[4].kind);
    for (batches) |batch| {
        try testing.expectEqual(@as(u32, 1), batch.instance_count);
    }
}

test "emit produces separate batches for different bindings" {
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

    var instances: [4]Instance = undefined;
    var batches: [4]DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;

    _ = try emit(&instances, batches[0..], &ilen, &blen, .{ .pool = pool_a }, &atlas_a, &shapes_a, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&instances, batches[0..], &ilen, &blen, .{ .pool = pool_b }, &atlas_b, &shapes_b, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 2), blen);
    try testing.expect(batches[0].binding.pool == pool_a);
    try testing.expect(batches[1].binding.pool == pool_b);
}
