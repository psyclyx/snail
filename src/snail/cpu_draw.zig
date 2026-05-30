//! Phase 4: CPU-backend draw entry for the new `DrawRecords` API.
//!
//! Walks segments, resolves each segment's `Binding.pool` to a
//! `CpuPreparedPages` cache (caller-supplied), validates the binding's
//! generation against the cache's last upload, then dispatches per-instance
//! into the existing CPU rasterizer via `CpuRenderer.drawTextPrepared`.
//!
//! Supports both `.heterogeneous` and `.replicated` segments. The
//! replicated path materializes N shape blocks × M override blocks into
//! N*M composed instances in a scratch buffer, then hands those to the
//! existing rasterizer (same Instance format, so no rasterizer surgery).

const std = @import("std");

const build_options = @import("build_options");
const snail = @import("root.zig");
const math = @import("math/vec.zig");
const draw_records = @import("draw_records.zig");
const cpu_upload_mod = @import("cpu_upload.zig");
const cpu_resources = @import("render/backend/cpu/resources.zig");
const vertex = @import("render/format/vertex.zig");

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const draw_records.DrawSegment,
};

pub const CpuPreparedPages = cpu_upload_mod.CpuPreparedPages;
pub const Binding = draw_records.Binding;
pub const Transform2D = math.Transform2D;

const WORDS_PER_INSTANCE: usize = vertex.WORDS_PER_INSTANCE;
const WORDS_PER_OVERRIDE: usize = 8;

pub const DrawError = error{
    /// Segment references a `PagePool` no entry in `caches` covers.
    MissingBinding,
    /// Segment's binding generation is newer than the cache's last upload.
    StaleBinding,
    /// Segment's word range is malformed for its declared shape/override counts.
    MalformedSegment,
};

const CpuRendererPtr = if (build_options.enable_cpu)
    *@import("render/backend/cpu/renderer.zig").CpuRenderer
else
    *opaque {};

/// Render `records` into `renderer`'s pixel buffer. `caches` provides the
/// CPU-side prepared data for the pools referenced by `records.segments`.
pub fn drawCpu(
    renderer: CpuRendererPtr,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const CpuPreparedPages,
) (DrawError || anyerror)!void {
    if (!build_options.enable_cpu) return error.MalformedSegment;
    for (records.segments) |seg| {
        const cache = findCache(caches, seg.binding.pool) orelse return error.MissingBinding;
        if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) {
            return error.StaleBinding;
        }

        var layer_info_buf: [1]cpu_resources.LayerInfoEntry = undefined;
        var layer_infos_slice: []cpu_resources.LayerInfoEntry = &.{};
        var layer_info_count: usize = 0;
        if (cache.snapshotFor(seg.binding.generation)) |snap| {
            layer_info_buf[0] = .{
                .data = snap.layer_info_data,
                .width = snap.layer_info_width,
                .height = snap.info_height,
                .row_base = snap.info_row_base,
                .path_records = snap.path_records,
                .path_layers = snap.path_layers,
                .paint_image_records = snap.paint_image_records,
            };
            layer_infos_slice = layer_info_buf[0..1];
            layer_info_count = 1;
        }
        var prepared = cpu_resources.PreparedResources{
            .allocator = cache.allocator,
            .atlas_pages = cache.prepared,
            .layer_infos = layer_infos_slice,
            .layer_info_count = layer_info_count,
        };
        const seg_words = records.words[seg.words_offset..][0..seg.words_len];

        switch (seg.kind) {
            .heterogeneous => {
                try renderer.drawTextPrepared(&prepared, seg_words, state, 0);
            },
            .replicated => {
                try drawReplicatedSegment(renderer, &prepared, state, seg, seg_words, cache.allocator);
            },
        }
    }
}

/// Materialize a replicated segment's N shape blocks × M override blocks
/// into N*M composed instances in a scratch buffer, then hand the buffer
/// to the existing rasterizer.
fn drawReplicatedSegment(
    renderer: CpuRendererPtr,
    prepared: *const cpu_resources.PreparedResources,
    state: snail.DrawState,
    seg: draw_records.DrawSegment,
    seg_words: []const u32,
    allocator: std.mem.Allocator,
) !void {
    const n = seg.shape_count;
    const m = seg.override_count;
    if (n == 0 or m == 0) return;
    const expected_words = @as(usize, n) * WORDS_PER_INSTANCE + @as(usize, m) * WORDS_PER_OVERRIDE;
    if (seg_words.len != expected_words) return error.MalformedSegment;

    const composed = try allocator.alloc(u32, @as(usize, n) * @as(usize, m) * WORDS_PER_INSTANCE);
    defer allocator.free(composed);

    const shape_words = seg_words[0 .. @as(usize, n) * WORDS_PER_INSTANCE];
    const override_words = seg_words[@as(usize, n) * WORDS_PER_INSTANCE ..];

    var out_cursor: usize = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const shape_inst = shape_words[@as(usize, i) * WORDS_PER_INSTANCE ..][0..WORDS_PER_INSTANCE];
        var j: u32 = 0;
        while (j < m) : (j += 1) {
            const override_block = override_words[@as(usize, j) * WORDS_PER_OVERRIDE ..][0..WORDS_PER_OVERRIDE];
            const dst = composed[out_cursor..][0..WORDS_PER_INSTANCE];
            composeShapeOverride(dst, shape_inst, override_block);
            out_cursor += WORDS_PER_INSTANCE;
        }
    }

    try renderer.drawTextPrepared(prepared, composed, state, 0);
}

/// Compose one shape Instance with one Override block. The override's
/// transform is left-multiplied onto the shape's, and the override's
/// tint replaces the shape's identity tint. All other fields are copied
/// verbatim from the shape block.
fn composeShapeOverride(
    dst: []u32,
    shape: []const u32,
    override: []const u32,
) void {
    std.debug.assert(dst.len == WORDS_PER_INSTANCE);
    std.debug.assert(shape.len == WORDS_PER_INSTANCE);
    std.debug.assert(override.len == WORDS_PER_OVERRIDE);

    @memcpy(dst, shape);

    const shape_t = Transform2D{
        .xx = @bitCast(shape[2]),
        .xy = @bitCast(shape[3]),
        .yx = @bitCast(shape[4]),
        .yy = @bitCast(shape[5]),
        .tx = @bitCast(shape[6]),
        .ty = @bitCast(shape[7]),
    };
    const override_t = Transform2D{
        .xx = @bitCast(override[0]),
        .xy = @bitCast(override[1]),
        .tx = @bitCast(override[2]),
        .yx = @bitCast(override[3]),
        .yy = @bitCast(override[4]),
        .ty = @bitCast(override[5]),
    };
    const composed_t = Transform2D.multiply(override_t, shape_t);
    dst[2] = @bitCast(composed_t.xx);
    dst[3] = @bitCast(composed_t.xy);
    dst[4] = @bitCast(composed_t.yx);
    dst[5] = @bitCast(composed_t.yy);
    dst[6] = @bitCast(composed_t.tx);
    dst[7] = @bitCast(composed_t.ty);

    // Override's tint slot is at word 6 (packed u8x4). The shape block's
    // tint slot is word 15. Overwrite verbatim.
    dst[15] = override[6];
}

fn findCache(
    caches: []const *const CpuPreparedPages,
    pool: *cpu_upload_mod.PagePool,
) ?*const CpuPreparedPages {
    for (caches) |c| {
        if (c.pool == pool) return c;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Tests
//
// The emit() level already locks down byte-for-byte parity with the existing
// `generateGlyphVerticesTransformedTinted` vertex helper. `cpu_upload` reuses
// the existing `PreparedAtlasPage.initFromView` builder verbatim. That makes
// the CPU rasterizer's inner sampling loop identical for old and new paths
// given the same source data. The remaining responsibility of these tests
// is to verify the new draw entry walks segments, validates bindings, and
// renders some non-empty pixels through `drawTextPrepared`.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "drawCpu MissingBinding when no cache covers the binding's pool" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;

    var pool_a = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool_a.deinit();
    var pool_b = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool_b.deinit();

    var cache_a = try CpuPreparedPages.init(allocator, pool_a, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache_a.deinit();

    var pixels: [16 * 16 * 4]u8 = .{0} ** (16 * 16 * 4);
    var renderer = snail.CpuRenderer.init(&pixels, 16, 16, 16 * 4);
    const state = makeIdentityState(16, 16);

    const segments = [_]draw_records.DrawSegment{.{
        .kind = .heterogeneous,
        .binding = .{ .pool = pool_b, .generation = 0 },
        .words_offset = 0,
        .words_len = 0,
        .shape_count = 0,
        .override_count = 1,
    }};
    const records = DrawRecords{ .words = &.{}, .segments = &segments };
    try testing.expectError(error.MissingBinding, drawCpu(&renderer, state, records, &.{&cache_a}));
}

test "drawCpu replicated produces same pixels as equivalent heterogeneous emit" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    const W: u32 = 96;
    const H: u32 = 64;
    const STRIDE: u32 = W * 4;
    const px_hetero = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_hetero);
    @memset(px_hetero, 0);
    const px_repl = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_repl);
    @memset(px_repl, 0);

    var font = try snail.Font.init(font_data);
    defer font.deinit();
    var glyph_cache = @import("font.zig").GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    const gid = try font.glyphIndex('o');
    var curves = try font.extractCurves(allocator, &glyph_cache, gid);
    defer curves.deinit();

    var pool = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("record_key.zig").unhintedGlyph(0, gid);
    var atlas = try @import("atlas.zig").Atlas.from(allocator, pool, &.{.{ .key = key, .curves = curves }});
    defer atlas.deinit();

    var cache = try CpuPreparedPages.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 16.0;
    const base_shape = @import("shape.zig").Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 16, .ty = 48 },
        .local_color = .{ 1, 1, 1, 1 },
    };

    const overrides = [_]@import("shape.zig").Override{
        .{ .transform = .identity, .tint = .{ 1, 1, 1, 1 } },
        .{ .transform = Transform2D.translate(20, 0), .tint = .{ 1, 1, 1, 1 } },
        .{ .transform = Transform2D.translate(40, 0), .tint = .{ 1, 1, 1, 1 } },
    };

    // Heterogeneous: emit the shape three times, one for each override
    // transform composed into the shape's local_transform.
    {
        var shapes = std.ArrayList(@import("shape.zig").Shape).empty;
        defer shapes.deinit(allocator);
        for (overrides) |ov| {
            var s = base_shape;
            s.local_transform = Transform2D.multiply(ov.transform, base_shape.local_transform);
            try shapes.append(allocator, s);
        }
        var pic = try @import("picture.zig").Picture.from(allocator, shapes.items);
        defer pic.deinit();

        const emit_mod = @import("emit.zig");
        const words = try allocator.alloc(u32, emit_mod.wordBudget(&pic, 0));
        defer allocator.free(words);
        var segs: [4]draw_records.DrawSegment = undefined;
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

        var renderer = snail.CpuRenderer.init(px_hetero.ptr, W, H, STRIDE);
        const state = makeIdentityState(W, H);
        try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});
    }

    // Replicated: one base shape, three overrides via emitInstanced.
    {
        var pic = try @import("picture.zig").Picture.from(allocator, &.{base_shape});
        defer pic.deinit();

        const emit_mod = @import("emit.zig");
        const words = try allocator.alloc(u32, emit_mod.wordBudget(&pic, overrides.len));
        defer allocator.free(words);
        var segs: [4]draw_records.DrawSegment = undefined;
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try emit_mod.emitInstanced(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, &overrides);

        var renderer = snail.CpuRenderer.init(px_repl.ptr, W, H, STRIDE);
        const state = makeIdentityState(W, H);
        try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});
    }

    try testing.expectEqualSlices(u8, px_hetero, px_repl);
}

test "drawCpu renders a small Picture into non-zero pixels" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    const W: u32 = 64;
    const H: u32 = 48;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    var font = try snail.Font.init(font_data);
    defer font.deinit();
    var glyph_cache = @import("font.zig").GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    const gid = try font.glyphIndex('A');
    const curves_a = try font.extractCurves(allocator, &glyph_cache, gid);
    var owned: [1]@import("curves.zig").GlyphCurves = .{curves_a};
    defer for (&owned) |*c| c.deinit();

    var pool = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("record_key.zig").unhintedGlyph(0, gid);
    var atlas = try @import("atlas.zig").Atlas.from(allocator, pool, &.{.{ .key = key, .curves = owned[0] }});
    defer atlas.deinit();

    var cache = try CpuPreparedPages.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    // GlyphCurves.bbox lives in unit-em coordinates (max ~1.0), so the
    // shape's scale is just the requested px size.
    const px_size: f32 = 24.0;
    const scale: f32 = px_size;
    const shape = @import("shape.zig").Shape{
        .key = key,
        .local_transform = .{
            .xx = scale,
            .xy = 0,
            .tx = 12,
            .yx = 0,
            .yy = -scale,
            .ty = 40,
        },
        .local_color = .{ 1, 1, 1, 1 },
    };
    var pic = try @import("picture.zig").Picture.from(allocator, &.{shape});
    defer pic.deinit();

    const emit_mod = @import("emit.zig");
    const word_need = emit_mod.wordBudget(&pic, 0);
    const words = try allocator.alloc(u32, word_need);
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    const records = DrawRecords{ .words = words[0..wlen], .segments = segs[0..slen] };
    try drawCpu(&renderer, state, records, &.{&cache});

    // Expect some non-zero pixel coverage from the glyph.
    var any_drawn = false;
    for (px) |b| if (b != 0) {
        any_drawn = true;
        break;
    };
    try testing.expect(any_drawn);
}

test "drawCpu renders gradient-painted glyph through special-layer path" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    const W: u32 = 64;
    const H: u32 = 48;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    var font = try snail.Font.init(font_data);
    defer font.deinit();
    var glyph_cache = @import("font.zig").GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    const gid = try font.glyphIndex('O');
    var curves = try font.extractCurves(allocator, &glyph_cache, gid);
    defer curves.deinit();

    var pool = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("record_key.zig").unhintedGlyph(0, gid);

    // Linear gradient running across the glyph's local-em width.
    const gradient = snail.LinearGradient{
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 1, .y = 0 },
        .start_color = .{ 1, 0, 0, 1 },
        .end_color = .{ 0, 0, 1, 1 },
    };
    var atlas = try @import("atlas.zig").Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = curves,
        .paint = .{ .linear_gradient = gradient },
    }});
    defer atlas.deinit();

    try testing.expect(atlas.lookupPaintRecord(key) != null);

    var cache = try CpuPreparedPages.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 32.0;
    const shape = @import("shape.zig").Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 12, .ty = 40 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    var pic = try @import("picture.zig").Picture.from(allocator, &.{shape});
    defer pic.deinit();

    const emit_mod = @import("emit.zig");
    const words = try allocator.alloc(u32, emit_mod.wordBudget(&pic, 0));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    // Scan every drawn pixel; expect both red-dominant (left of the
    // gradient) and blue-dominant (right) coverage somewhere in the
    // rendered glyph. Coverage is partial near edges so any non-zero
    // alpha pixel counts.
    var has_red: bool = false;
    var has_blue: bool = false;
    var row: u32 = 0;
    while (row < H) : (row += 1) {
        var col: u32 = 0;
        while (col < W) : (col += 1) {
            const off = row * STRIDE + col * 4;
            if (px[off + 3] < 16) continue;
            if (@as(i32, px[off]) - @as(i32, px[off + 2]) > 24) has_red = true;
            if (@as(i32, px[off + 2]) - @as(i32, px[off]) > 24) has_blue = true;
        }
    }
    try testing.expect(has_red);
    try testing.expect(has_blue);
}

test "drawCpu renders image-painted shape through special-layer path" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;

    const W: u32 = 32;
    const H: u32 = 32;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    // Solid-red 4x4 sRGBA8 source image — the rendered shape should
    // pick up the red tint via the image paint sampling.
    var image_pixels: [4 * 4 * 4]u8 = undefined;
    var p: usize = 0;
    while (p + 3 < image_pixels.len) : (p += 4) {
        image_pixels[p + 0] = 255;
        image_pixels[p + 1] = 0;
        image_pixels[p + 2] = 0;
        image_pixels[p + 3] = 255;
    }
    var image = try snail.Image.initSrgba8(allocator, 4, 4, image_pixels[0..]);
    defer image.deinit();

    var pool = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    // Square-ish path covering [0..1, 0..1] in local coords; the local
    // shape transform scales to pixel size.
    var path = @import("paths.zig").Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var path_curves = try @import("paths.zig").pathToCurves(allocator, &path);
    defer path_curves.deinit();

    const key = @import("record_key.zig").RecordKey{
        .namespace = @import("record_key.zig").ns.path_fill,
        .a = 0,
    };
    var atlas = try @import("atlas.zig").Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = path_curves,
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .identity,
            .tint = .{ 1, 1, 1, 1 },
        } },
    }});
    defer atlas.deinit();

    try testing.expect(atlas.paint_image_records != null);
    try testing.expect(atlas.paint_image_records.?[0] != null);
    try testing.expect(atlas.paint_image_records.?[0].?.image == &image);

    var cache = try CpuPreparedPages.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 4 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 20.0;
    const shape = @import("shape.zig").Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = px_size, .tx = 6, .ty = 6 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    var pic = try @import("picture.zig").Picture.from(allocator, &.{shape});
    defer pic.deinit();

    const emit_mod = @import("emit.zig");
    const words = try allocator.alloc(u32, emit_mod.wordBudget(&pic, 0));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &pic, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    var has_red: bool = false;
    var row: u32 = 0;
    while (row < H) : (row += 1) {
        var col: u32 = 0;
        while (col < W) : (col += 1) {
            const off = row * STRIDE + col * 4;
            if (px[off + 3] < 16) continue;
            if (px[off] > 200 and px[off + 1] < 32 and px[off + 2] < 32) {
                has_red = true;
                break;
            }
        }
        if (has_red) break;
    }
    try testing.expect(has_red);
}

fn makeIdentityState(w: u32, h: u32) snail.DrawState {
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    return .{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{
            .subpixel_order = .none,
            .coverage_transfer = .{ .exponent = 1.0 },
        },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
}
