//! `emit`: write GPU-ready vertex bytes for a `Picture` resolved against an
//! `Atlas`, plus a `DrawSegment` describing how the renderer should bind and
//! dispatch them.
//!
//! Two primitives:
//!   - `emit` walks heterogeneous shape lists (one transform/color per shape).
//!     Writes one 16-word `Instance` per shape.
//!   - `emitInstanced` walks a picture replicated under M overrides. Writes
//!     N shape blocks (16 words each) + M override blocks (8 words each); the
//!     backend materializes N*M instances at dispatch.
//!
//! Both primitives write into caller-provided buffers and return word/segment
//! counts. Consecutive calls that share a binding/kind/contiguity coalesce
//! their segments (`draw_records.mergeIfAdjacent`).

const std = @import("std");
const math = @import("math/vec.zig");
const vertex = @import("render/format/vertex.zig");
const atlas_mod = @import("atlas.zig");
const draw_records = @import("draw_records.zig");
const picture_mod = @import("picture.zig");
const shape_mod = @import("shape.zig");

pub const Transform2D = math.Transform2D;
pub const Atlas = atlas_mod.Atlas;
pub const Binding = draw_records.Binding;
pub const Kind = draw_records.Kind;
pub const DrawSegment = draw_records.DrawSegment;
pub const Picture = picture_mod.Picture;
pub const Shape = shape_mod.Shape;
pub const Override = shape_mod.Override;

const WORDS_PER_INSTANCE = vertex.WORDS_PER_INSTANCE;
const WORDS_PER_OVERRIDE: usize = 8;

pub const EmitError = error{
    /// Picture references a key not present in the atlas.
    MissingRecord,
    /// A shape's composed transform had near-zero determinant.
    InvalidTransform,
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
    /// Index of the shape that caused the failure, when applicable.
    failed_shape_index: ?u32 = null,
};

/// Heterogeneous emit. One pre-composed `Instance` per shape in the picture,
/// transform composed as `world_xform * shape.local_transform`, color as
/// `shape.local_color`, tint as `world_tint`.
pub fn emit(
    words_buf: []u32,
    segs_buf: []DrawSegment,
    word_len: *usize,
    seg_len: *usize,
    binding: Binding,
    atlas: *const Atlas,
    picture: *const Picture,
    world_xform: Transform2D,
    world_tint: [4]f32,
) EmitError!EmitResult {
    const shapes = picture.shapes;
    const need_words = shapes.len * WORDS_PER_INSTANCE;
    if (words_buf.len - word_len.* < need_words) return error.BufferTooSmall;

    const start_offset: u32 = @intCast(word_len.*);
    var cursor: usize = word_len.*;
    var emitted: u32 = 0;

    for (shapes) |shape| {
        const rec = atlas.lookupRecord(shape.key) orelse {
            return error.MissingRecord;
        };

        // An empty record (curve_count == 0) corresponds to a non-rendering
        // glyph (e.g. ASCII space). Skip emitting any instance for it.
        if (rec.curve_count == 0) continue;

        const page = atlas.pages[rec.page_index];
        if (page.layer_index > std.math.maxInt(u8)) return error.AtlasLayerOverflow;
        const atlas_layer: u8 = @intCast(page.layer_index);

        const final_transform = Transform2D.multiply(world_xform, shape.local_transform);
        const dst = words_buf[cursor..][0..WORDS_PER_INSTANCE];

        const ok = if (atlas.lookupPaintRecord(shape.key)) |paint_info|
            vertex.generatePathRecordVerticesTransformedTinted(
                dst,
                rec.bbox,
                paint_info.info_x,
                try addRowBase(paint_info.info_y, binding.info_row_base),
                paint_info.layer_count,
                shape.local_color,
                world_tint,
                atlas_layer,
                final_transform,
            )
        else
            vertex.generateGlyphVerticesTransformedTinted(
                dst,
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

        if (!ok) return error.InvalidTransform;
        cursor += WORDS_PER_INSTANCE;
        emitted += 1;
    }

    const wrote_words: u32 = @intCast(cursor - word_len.*);
    word_len.* = cursor;

    if (emitted == 0) {
        return .{ .shape_count = 0, .word_count = 0, .segment_count = 0 };
    }

    var seg_added: u32 = 0;
    const seg = DrawSegment{
        .kind = .heterogeneous,
        .binding = binding,
        .words_offset = start_offset,
        .words_len = wrote_words,
        .shape_count = emitted,
        .override_count = 1,
    };
    if (!draw_records.mergeIfAdjacent(segs_buf, seg_len, seg)) {
        if (seg_len.* >= segs_buf.len) return error.BufferTooSmall;
        segs_buf[seg_len.*] = seg;
        seg_len.* += 1;
        seg_added = 1;
    }

    return .{
        .shape_count = emitted,
        .word_count = wrote_words,
        .segment_count = seg_added,
    };
}

/// Replicated emit. Writes N shape blocks + M override blocks. The backend
/// materializes N*M instances at dispatch by combining each shape with each
/// override.
///
/// Shape blocks use the same 16-word `Instance` format as heterogeneous
/// emit, with `color = shape.local_color`, `tint = identity`, and the
/// instance transform set to `shape.local_transform` (no world composition).
/// Override blocks are 8 words each: 6 f32 transform fields then a packed
/// u8x4 tint and one reserved word.
pub fn emitInstanced(
    words_buf: []u32,
    segs_buf: []DrawSegment,
    word_len: *usize,
    seg_len: *usize,
    binding: Binding,
    atlas: *const Atlas,
    picture: *const Picture,
    overrides: []const Override,
) EmitError!EmitResult {
    const shapes = picture.shapes;
    const need_words = shapes.len * WORDS_PER_INSTANCE + overrides.len * WORDS_PER_OVERRIDE;
    if (words_buf.len - word_len.* < need_words) return error.BufferTooSmall;
    if (seg_len.* >= segs_buf.len) return error.BufferTooSmall;

    const start_offset: u32 = @intCast(word_len.*);
    var cursor: usize = word_len.*;
    var shape_emitted: u32 = 0;

    for (shapes) |shape| {
        const rec = atlas.lookupRecord(shape.key) orelse {
            return error.MissingRecord;
        };
        // Match the heterogeneous behavior: skip non-rendering records
        // entirely. This means the replicated shape count may differ
        // from picture.shapes.len.
        if (rec.curve_count == 0) continue;
        const page = atlas.pages[rec.page_index];
        if (page.layer_index > std.math.maxInt(u8)) return error.AtlasLayerOverflow;
        const atlas_layer: u8 = @intCast(page.layer_index);

        const dst = words_buf[cursor..][0..WORDS_PER_INSTANCE];
        const ok = vertex.generateGlyphVerticesTransformedTinted(
            dst,
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
            .{ 1, 1, 1, 1 },
            atlas_layer,
            shape.local_transform,
        );
        if (!ok) return error.InvalidTransform;
        cursor += WORDS_PER_INSTANCE;
        shape_emitted += 1;
    }

    for (overrides) |ov| {
        writeOverride(words_buf[cursor..][0..WORDS_PER_OVERRIDE], ov);
        cursor += WORDS_PER_OVERRIDE;
    }

    const wrote_words: u32 = @intCast(cursor - word_len.*);
    word_len.* = cursor;

    if (shape_emitted == 0 or overrides.len == 0) {
        return .{ .shape_count = shape_emitted, .word_count = wrote_words, .segment_count = 0 };
    }

    segs_buf[seg_len.*] = .{
        .kind = .replicated,
        .binding = binding,
        .words_offset = start_offset,
        .words_len = wrote_words,
        .shape_count = shape_emitted,
        .override_count = @intCast(overrides.len),
    };
    seg_len.* += 1;

    return .{
        .shape_count = shape_emitted,
        .word_count = wrote_words,
        .segment_count = 1,
    };
}

/// Conservative upper bound on words written for an emit/emitInstanced call.
pub fn wordBudget(picture: *const Picture, override_count: usize) usize {
    const shapes = picture.shapes.len;
    if (override_count == 0) {
        // Heterogeneous: one Instance per shape.
        return shapes * WORDS_PER_INSTANCE;
    }
    // Replicated: shape blocks + override blocks.
    return shapes * WORDS_PER_INSTANCE + override_count * WORDS_PER_OVERRIDE;
}

/// Conservative upper bound on segments written for one emit call.
pub fn segmentBudget(picture: *const Picture, override_count: usize) usize {
    _ = picture;
    _ = override_count;
    return 1;
}

fn writeOverride(buf: []u32, ov: Override) void {
    std.debug.assert(buf.len == WORDS_PER_OVERRIDE);
    buf[0] = @bitCast(ov.transform.xx);
    buf[1] = @bitCast(ov.transform.xy);
    buf[2] = @bitCast(ov.transform.tx);
    buf[3] = @bitCast(ov.transform.yx);
    buf[4] = @bitCast(ov.transform.yy);
    buf[5] = @bitCast(ov.transform.ty);
    buf[6] = packU8x4(ov.tint);
    buf[7] = 0;
}

fn packU8x4(c: [4]f32) u32 {
    const r: u32 = unorm8(c[0]);
    const g: u32 = unorm8(c[1]);
    const b: u32 = unorm8(c[2]);
    const a: u32 = unorm8(c[3]);
    return r | (g << 8) | (b << 16) | (a << 24);
}

fn unorm8(v: f32) u32 {
    const clamped = std.math.clamp(v, 0.0, 1.0);
    return @intFromFloat(@round(clamped * 255.0));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const record_key_mod = @import("record_key.zig");
const curves_mod = @import("curves.zig");
const page_pool_mod = @import("page_pool.zig");
const curve_tex_format = @import("render/format/curve_texture.zig");

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
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    const need = wordBudget(&pic, 0);
    const words = try testing.allocator.alloc(u32, need);
    defer testing.allocator.free(words);
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    const binding = Binding{ .pool = pool };
    const result = try emit(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(u32, 2), result.shape_count);
    try testing.expectEqual(@as(u32, 2 * WORDS_PER_INSTANCE), result.word_count);
    try testing.expectEqual(@as(u32, 1), result.segment_count);
    try testing.expectEqual(@as(usize, 1), slen);
    try testing.expectEqual(Kind.heterogeneous, segs[0].kind);
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
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    var words = [_]u32{0} ** (WORDS_PER_INSTANCE);
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    const binding = Binding{ .pool = pool };
    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &pic, world_t, world_tint);

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
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    var buf: [WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    const binding = Binding{ .pool = pool };
    try testing.expectError(EmitError.MissingRecord, emit(&buf, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 }));
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
    var pa = try Picture.from(testing.allocator, &shapes_a);
    defer pa.deinit();
    var pb = try Picture.from(testing.allocator, &shapes_b);
    defer pb.deinit();

    var words: [4 * WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    const binding = Binding{ .pool = pool };

    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &pa, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&words, segs[0..], &wlen, &slen, binding, &atlas, &pb, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 1), slen);
    try testing.expectEqual(@as(u32, 2), segs[0].shape_count);
    try testing.expectEqual(@as(u32, 2 * WORDS_PER_INSTANCE), segs[0].words_len);
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
    var pa = try Picture.from(testing.allocator, &shapes_a);
    defer pa.deinit();
    var pb = try Picture.from(testing.allocator, &shapes_b);
    defer pb.deinit();

    var words: [4 * WORDS_PER_INSTANCE]u32 = undefined;
    var segs: [4]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    _ = try emit(&words, segs[0..], &wlen, &slen, .{ .pool = pool_a }, &atlas_a, &pa, .identity, .{ 1, 1, 1, 1 });
    _ = try emit(&words, segs[0..], &wlen, &slen, .{ .pool = pool_b }, &atlas_b, &pb, .identity, .{ 1, 1, 1, 1 });

    try testing.expectEqual(@as(usize, 2), slen);
    try testing.expect(segs[0].binding.pool == pool_a);
    try testing.expect(segs[1].binding.pool == pool_b);
}

test "emitInstanced writes shape and override blocks" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2 });
    defer atlas.deinit();

    const shapes = [_]Shape{
        .{ .key = record_key_mod.unhintedGlyph(0, 1) },
        .{ .key = record_key_mod.unhintedGlyph(0, 2) },
    };
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    const overrides = [_]Override{
        .{ .transform = .translate(100, 0) },
        .{ .transform = .translate(0, 100) },
        .{ .transform = .translate(50, 50) },
    };

    const need = wordBudget(&pic, overrides.len);
    const words = try testing.allocator.alloc(u32, need);
    defer testing.allocator.free(words);
    var segs: [1]DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;

    const result = try emitInstanced(words, segs[0..], &wlen, &slen, .{ .pool = pool }, &atlas, &pic, &overrides);
    try testing.expectEqual(@as(u32, 2), result.shape_count);
    try testing.expectEqual(@as(u32, 1), result.segment_count);
    try testing.expectEqual(Kind.replicated, segs[0].kind);
    try testing.expectEqual(@as(u32, 2), segs[0].shape_count);
    try testing.expectEqual(@as(u32, 3), segs[0].override_count);
    try testing.expectEqual(@as(u32, 2 * WORDS_PER_INSTANCE + 3 * WORDS_PER_OVERRIDE), segs[0].words_len);
}

test "wordBudget bounds match actual emit output" {
    var pool = try PagePool.init(testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 1024,
        .band_words_per_page = 256,
    });
    defer pool.deinit();
    var atlas = try buildTestAtlas(pool, &.{ 1, 2, 3 });
    defer atlas.deinit();

    const shapes = [_]Shape{
        .{ .key = record_key_mod.unhintedGlyph(0, 1) },
        .{ .key = record_key_mod.unhintedGlyph(0, 2) },
        .{ .key = record_key_mod.unhintedGlyph(0, 3) },
    };
    var pic = try Picture.from(testing.allocator, &shapes);
    defer pic.deinit();

    const overrides = [_]Override{ .{}, .{} };
    try testing.expectEqual(@as(usize, 3 * WORDS_PER_INSTANCE), wordBudget(&pic, 0));
    try testing.expectEqual(@as(usize, 3 * WORDS_PER_INSTANCE + 2 * WORDS_PER_OVERRIDE), wordBudget(&pic, overrides.len));
}
