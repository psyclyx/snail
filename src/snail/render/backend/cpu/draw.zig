//! CPU-backend draw entry for `DrawRecords`.
//!
//! Walks segments, resolves each segment's `Binding.pool` to a
//! `CpuBackendCache` cache (caller-supplied), validates the binding's
//! generation against the cache's last upload, then dispatches per-instance
//! into the CPU rasterizer via `CpuRenderer.drawBatch`.
//!

const std = @import("std");

const build_options = @import("build_options");
const snail = @import("snail_core");
const math = @import("snail_core").files.math_vec;
const draw_records = @import("snail_core").files.picture_draw_records;
const cpu_upload_mod = @import("backend_cache.zig");
const cpu_resources = @import("resources.zig");
const vertex = @import("snail_core").files.format_vertex;

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const draw_records.DrawSegment,
};

pub const CpuBackendCache = cpu_upload_mod.CpuBackendCache;
pub const Binding = draw_records.Binding;
pub const Transform2D = math.Transform2D;

const WORDS_PER_INSTANCE: usize = vertex.WORDS_PER_INSTANCE;

pub const DrawError = error{
    /// Segment references a `PagePool` no entry in `caches` covers.
    MissingBinding,
    /// Segment's binding generation is newer than the cache's last upload.
    StaleBinding,
    /// Segment's word range is malformed for its declared shape count.
    MalformedSegment,
};

const CpuRendererPtr = if (build_options.enable_cpu)
    *@import("renderer.zig").CpuRenderer
else
    *opaque {};

/// Render `records` into `renderer`'s pixel buffer. `caches` provides the
/// CPU-side prepared data for the pools referenced by `records.segments`.
///
/// `thread_pool` is the per-call work-distribution policy: pass a non-null
/// pool to fan tile work across its workers, or `null` to rasterize on the
/// calling thread. Output is byte-identical either way. A pool wins on
/// large batches and loses on small ones (dispatch overhead > work), so
/// the caller decides per draw rather than configuring the renderer once.
pub fn drawCpu(
    renderer: CpuRendererPtr,
    state: snail.DrawState,
    records: DrawRecords,
    caches: []const *const CpuBackendCache,
    thread_pool: ?*snail.ThreadPool,
    // `NonAffineMvp` bubbles up from the rasterizer, which (unlike the GPU
    // backends) can't handle a perspective MVP.
) (DrawError || error{NonAffineMvp} || std.mem.Allocator.Error)!void {
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

        if (seg_words.len != @as(usize, seg.shape_count) * WORDS_PER_INSTANCE) return error.MalformedSegment;
        try renderer.drawBatch(&prepared, seg_words, state, 0, thread_pool);
    }
}

fn findCache(
    caches: []const *const CpuBackendCache,
    pool: *cpu_upload_mod.PagePool,
) ?*const CpuBackendCache {
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
// renders some non-empty pixels through `drawBatch`.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "drawCpu MissingBinding when no cache covers the binding's pool" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;

    var pool_a = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool_a.deinit();
    var pool_b = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool_b.deinit();

    var cache_a = try CpuBackendCache.init(allocator, pool_a, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache_a.deinit();

    var pixels: [16 * 16 * 4]u8 = .{0} ** (16 * 16 * 4);
    var renderer = @import("renderer.zig").CpuRenderer.init(&pixels, 16, 16, 16 * 4);
    const state = makeIdentityState(16, 16);

    const segments = [_]draw_records.DrawSegment{.{
        .binding = .{ .pool = pool_b, .generation = 0 },
        .words_offset = 0,
        .words_len = 0,
        .shape_count = 0,
    }};
    const records = DrawRecords{ .words = &.{}, .segments = &segments };
    try testing.expectError(error.MissingBinding, drawCpu(&renderer, state, records, &.{&cache_a}, null));
}

test "drawCpu autohint fits per size without mutating atlas resources" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    const atlas_mod = @import("snail_core").files.atlas;
    const record_key_mod = @import("snail_core").files.atlas_record_key;
    const shape_mod = @import("snail_core").files.picture_shape;
    const emit_mod = @import("snail_core").files.picture_emit;

    const W: u32 = 48;
    const H: u32 = 40;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);
    const gid = try font.glyphIndex('H');
    var curves = try font.extractCurves(allocator, allocator, gid);
    defer curves.deinit();

    var analyzer = try snail.autohint.AutohintAnalyzer.init(allocator, font_data);
    defer analyzer.deinit();
    var x_features: [snail.autohint.warp.max_knots]snail.autohint.FeatureEdge = undefined;
    var y_features: [snail.autohint.warp.max_knots]snail.autohint.FeatureEdge = undefined;
    const glyph_features = try analyzer.analyzeGlyph(allocator, gid, &x_features, &y_features);
    try testing.expect(glyph_features.x.len > 0 or glyph_features.y.len > 0);

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const base_key = record_key_mod.unhintedGlyph(0, gid);
    const key = record_key_mod.autohintGlyph(0, gid);
    var atlas = try atlas_mod.Atlas.from(allocator, pool, &.{
        .{ .key = base_key, .curves = curves },
        .{
            .key = key,
            .curves = atlas_mod.GlyphCurves.empty(allocator),
            .autohint = .{ .font = analyzer.fontFeatures(), .glyph = glyph_features },
            .autohint_base = base_key,
        },
    });
    defer atlas.deinit();

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 16, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const pages_ptr = atlas.pages.ptr;
    const pages_len = atlas.pages.len;
    const page = atlas.pages[0];
    const curve_data = page.curve.data;
    const band_data = page.band.data;
    const layer_info = atlas.layer_info_data.?;
    const layer_info_copy = try allocator.dupe(f32, layer_info);
    defer allocator.free(layer_info_copy);
    const curve_used = page.curve.usedWords();
    const curve_uploaded = page.curve.uploadedWords();
    const band_used = page.band.usedWords();
    const band_uploaded = page.band.uploadedWords();
    const curve_copy = try allocator.dupe(u16, page.curve.data[0..curve_used]);
    defer allocator.free(curve_copy);
    const band_copy = try allocator.dupe(u16, page.band.data[0..band_used]);
    defer allocator.free(band_copy);

    const Render = struct {
        fn atSize(
            pixels: []u8,
            px_size: f32,
            policy: shape_mod.AutohintPolicy,
            shape_key: atlas_mod.RecordKey,
            binding: Binding,
            atlas_ptr: *const atlas_mod.Atlas,
            cache_ptr: *const CpuBackendCache,
        ) !void {
            @memset(pixels, 0);
            const shape = shape_mod.Shape{
                .key = shape_key,
                .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 10, .ty = 28 },
                .autohint_policy = policy,
            };
            var words: [vertex.WORDS_PER_INSTANCE]u32 = undefined;
            var segs: [1]draw_records.DrawSegment = undefined;
            var wlen: usize = 0;
            var slen: usize = 0;
            _ = try emit_mod.emit(&words, &segs, &wlen, &slen, binding, atlas_ptr, &.{shape}, .identity, .{ 1, 1, 1, 1 });
            var renderer = @import("renderer.zig").CpuRenderer.init(pixels.ptr, W, H, STRIDE);
            try drawCpu(&renderer, makeIdentityState(W, H), .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{cache_ptr}, null);
        }
    };

    const pixels_12 = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels_12);
    const pixels_17 = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels_17);
    try Render.atSize(pixels_12, 12, .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    }, key, bindings[0], &atlas, &cache);
    try Render.atSize(pixels_17, 17, .{
        .x = .{ .@"align" = .grid, .positioning = .relative },
        .y = .{ .@"align" = .blue_zones },
    }, key, bindings[0], &atlas, &cache);

    try testing.expect(!std.mem.allEqual(u8, pixels_12, 0));
    try testing.expect(!std.mem.allEqual(u8, pixels_17, 0));
    try testing.expect(!std.mem.eql(u8, pixels_12, pixels_17));
    try testing.expectEqual(pages_ptr, atlas.pages.ptr);
    try testing.expectEqual(pages_len, atlas.pages.len);
    try testing.expectEqual(page, atlas.pages[0]);
    try testing.expectEqual(curve_data.ptr, page.curve.data.ptr);
    try testing.expectEqual(curve_data.len, page.curve.data.len);
    try testing.expectEqual(band_data.ptr, page.band.data.ptr);
    try testing.expectEqual(band_data.len, page.band.data.len);
    try testing.expectEqual(layer_info.ptr, atlas.layer_info_data.?.ptr);
    try testing.expectEqual(layer_info.len, atlas.layer_info_data.?.len);
    try testing.expectEqual(curve_used, page.curve.usedWords());
    try testing.expectEqual(curve_uploaded, page.curve.uploadedWords());
    try testing.expectEqual(band_used, page.band.usedWords());
    try testing.expectEqual(band_uploaded, page.band.uploadedWords());
    try testing.expectEqualSlices(u8, std.mem.sliceAsBytes(layer_info_copy), std.mem.sliceAsBytes(atlas.layer_info_data.?));
    try testing.expectEqualSlices(u16, curve_copy, page.curve.data[0..curve_used]);
    try testing.expectEqualSlices(u16, band_copy, page.band.data[0..band_used]);
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

    const gid = try font.glyphIndex('A');
    const curves_a = try font.extractCurves(allocator, allocator, gid);
    var owned: [1]@import("snail_core").files.atlas_curves.GlyphCurves = .{curves_a};
    defer for (&owned) |*c| c.deinit();

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail_core").files.atlas_record_key.unhintedGlyph(0, gid);
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{ .key = key, .curves = owned[0] }});
    defer atlas.deinit();

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    // GlyphCurves.bbox lives in unit-em coordinates (max ~1.0), so the
    // shape's scale is just the requested px size.
    const px_size: f32 = 24.0;
    const scale: f32 = px_size;
    const shape = @import("snail_core").files.picture_shape.Shape{
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
    const shapes = [_]@import("snail_core").files.picture_shape.Shape{shape};

    const emit_mod = @import("snail_core").files.picture_emit;
    const word_need = emit_mod.wordBudget(shapes.len);
    const words = try allocator.alloc(u32, word_need);
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = @import("renderer.zig").CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    const records = DrawRecords{ .words = words[0..wlen], .segments = segs[0..slen] };
    try drawCpu(&renderer, state, records, &.{&cache}, null);

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

    const gid = try font.glyphIndex('O');
    var curves = try font.extractCurves(allocator, allocator, gid);
    defer curves.deinit();

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail_core").files.atlas_record_key.unhintedGlyph(0, gid);

    // Linear gradient running across the glyph's local-em width.
    const gradient = snail.LinearGradient{
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 1, .y = 0 },
        .start_color = .{ 1, 0, 0, 1 },
        .end_color = .{ 0, 0, 1, 1 },
    };
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = curves,
        .paint = .{ .linear_gradient = gradient },
    }});
    defer atlas.deinit();

    try testing.expect(atlas.lookupPaintRecord(key) != null);

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 32.0;
    const shape = @import("snail_core").files.picture_shape.Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 12, .ty = 40 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    const shapes = [_]@import("snail_core").files.picture_shape.Shape{shape};

    const emit_mod = @import("snail_core").files.picture_emit;
    const words = try allocator.alloc(u32, emit_mod.wordBudget(shapes.len));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = @import("renderer.zig").CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache}, null);

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

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    // Square-ish path covering [0..1, 0..1] in local coords; the local
    // shape transform scales to pixel size.
    var path = @import("snail_core").files.path.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var path_curves = try prepared_path.fillCurves(allocator, allocator);
    defer path_curves.deinit();

    const key = @import("snail_core").files.atlas_record_key.RecordKey{
        .namespace = @import("snail_core").files.atlas_record_key.ns.path_fill,
        .a = 0,
    };
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = path_curves,
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .identity,
        } },
    }});
    defer atlas.deinit();

    try testing.expect(atlas.paint_image_records != null);
    try testing.expect(atlas.paint_image_records.?[0] != null);
    try testing.expect(atlas.paint_image_records.?[0].?.image == &image);

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 4 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 20.0;
    const shape = @import("snail_core").files.picture_shape.Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = px_size, .tx = 6, .ty = 6 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    const shapes = [_]@import("snail_core").files.picture_shape.Shape{shape};

    const emit_mod = @import("snail_core").files.picture_emit;
    const words = try allocator.alloc(u32, emit_mod.wordBudget(shapes.len));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = @import("renderer.zig").CpuRenderer.init(px.ptr, W, H, STRIDE);
    const state = makeIdentityState(W, H);
    try drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache}, null);

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

test "drawCpu threaded matches single-threaded pixel-for-pixel" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    // Tall enough that row_clip_max > row_clip_min + TILE_ROWS (32) so the
    // parallel dispatch path actually triggers.
    const W: u32 = 128;
    const H: u32 = 96;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);

    const glyphs = "Hello, world!";
    const Owned = @import("snail_core").files.atlas_curves.GlyphCurves;
    var owned: std.ArrayList(Owned) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(allocator);
    }
    var entries: std.ArrayList(@import("snail_core").files.atlas.Entry) = .empty;
    defer entries.deinit(allocator);

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var shapes: std.ArrayList(@import("snail_core").files.picture_shape.Shape) = .empty;
    defer shapes.deinit(allocator);

    const px_size: f32 = 18.0;
    var pen_x: f32 = 4;
    for (glyphs) |c| {
        const gid = try font.glyphIndex(c);
        const key = @import("snail_core").files.atlas_record_key.unhintedGlyph(0, gid);
        if (!containsEntryKey(entries.items, key)) {
            const curves = try font.extractCurves(allocator, allocator, gid);
            try owned.append(allocator, curves);
            try entries.append(allocator, .{ .key = key, .curves = owned.items[owned.items.len - 1] });
        }
        try shapes.append(allocator, .{
            .key = key,
            .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = pen_x, .ty = 64 },
            .local_color = .{ 1, 1, 1, 1 },
        });
        pen_x += px_size * 0.55;
    }

    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, entries.items);
    defer atlas.deinit();
    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const emit_mod = @import("snail_core").files.picture_emit;
    const words = try allocator.alloc(u32, emit_mod.wordBudget(shapes.items.len));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, bindings[0], &atlas, shapes.items, .identity, .{ 1, 1, 1, 1 });
    const records = DrawRecords{ .words = words[0..wlen], .segments = segs[0..slen] };
    const state = makeIdentityState(W, H);

    const px_serial = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_serial);
    @memset(px_serial, 0);
    var renderer_serial = @import("renderer.zig").CpuRenderer.init(px_serial.ptr, W, H, STRIDE);
    try drawCpu(&renderer_serial, state, records, &.{&cache}, null);

    const px_threaded = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_threaded);
    @memset(px_threaded, 0);

    var thread_pool: snail.ThreadPool = undefined;
    try thread_pool.init(allocator, .{ .threads = 3 });
    defer thread_pool.deinit();

    var renderer_threaded = @import("renderer.zig").CpuRenderer.init(px_threaded.ptr, W, H, STRIDE);
    try drawCpu(&renderer_threaded, state, records, &.{&cache}, &thread_pool);

    try testing.expectEqualSlices(u8, px_serial, px_threaded);
}

fn containsEntryKey(entries: []const @import("snail_core").files.atlas.Entry, key: @import("snail_core").files.atlas_record_key.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

test "shared-endpoint interior coverage stays solid (no centre seam)" {
    // Regression for the 1px white seam down shapes whose halves meet on the
    // sampling axis. The banner "custom path" leaf is two cubics sharing the
    // endpoints (0.5,0) and (0.5,1); both sit on the vertical centre line, so
    // the vertical-ray winding is evaluated right at a curve endpoint there.
    // The old Cardano/quadratic cubic solver dropped that near-endpoint root in
    // a hair-thin column, collapsing V-coverage to 0 and painting a white line
    // down the shape on the CPU (the GPU's monotonic solver stayed correct).
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const coverage = @import("coverage.zig");
    const geometry = @import("geometry.zig");
    const Vec2 = math.Vec2;

    var path = @import("snail_core").files.path.Path.init(allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0.5, .y = 0 });
    try path.cubicTo(.{ .x = 0.95, .y = 0.2 }, .{ .x = 0.95, .y = 0.8 }, .{ .x = 0.5, .y = 1 });
    try path.cubicTo(.{ .x = 0.05, .y = 0.8 }, .{ .x = 0.05, .y = 0.2 }, .{ .x = 0.5, .y = 0 });
    try path.close();
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves = try prepared_path.fillCurves(allocator, allocator);
    defer curves.deinit();

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail_core").files.atlas_record_key.RecordKey{
        .namespace = @import("snail_core").files.atlas_record_key.ns.path_fill,
        .a = 0,
    };
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas.deinit();

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const page = &cache.prepared[0].?;
    const layer = cache.snapshotFor(bindings[0].generation).?.path_layers[0];
    const be = layer.band_entry;

    // Sweep scales and sub-pixel offsets; every deep-interior pixel of the leaf
    // must stay fully covered. Before the fix a specific alignment left the
    // column at x≈0.5 uncovered (coverage 0).
    const scales = [_]f32{ 40, 63.3, 128.7, 200, 288 };
    const offsets = [_]f32{ 0.0, 0.13, 0.37, 0.5, 0.61, 0.83 };
    var worst: f32 = 0;
    for (scales) |scale| {
        for (offsets) |ox| {
            for (offsets) |oy| {
                const inv = (Transform2D{
                    .xx = scale * prepared_path.design_to_source.xx,
                    .xy = 0,
                    .yx = 0,
                    .yy = scale * prepared_path.design_to_source.yy,
                    .tx = ox,
                    .ty = oy,
                }).inverse().?;
                const epp = geometry.glyphEdgePixelsPerPixel(inv);
                const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
                var py: i32 = @intFromFloat(@floor(oy));
                const py_hi: i32 = @intFromFloat(@ceil(scale + oy));
                while (py < py_hi) : (py += 1) {
                    const ly = (@as(f32, @floatFromInt(py)) + 0.5 - oy) / scale;
                    if (ly < 0.35 or ly > 0.65) continue; // leaf is widest mid-height
                    var px: i32 = @intFromFloat(@floor(ox));
                    const px_hi: i32 = @intFromFloat(@ceil(scale + ox));
                    while (px < px_hi) : (px += 1) {
                        const lx = (@as(f32, @floatFromInt(px)) + 0.5 - ox) / scale;
                        if (@abs(lx - 0.5) > 0.2) continue; // deep interior, straddles the centre
                        const design = prepared_path.source_to_design.applyPoint(.{ .x = lx, .y = ly });
                        const cov = coverage.evalGlyphCoverageBandSpan(page, design.x, design.y, epp.x, epp.y, ppe.x, ppe.y, be, layer.band_max_h, layer.band_max_v, layer.fill_rule);
                        worst = @max(worst, 1.0 - cov);
                    }
                }
            }
        }
    }
    try testing.expect(worst < 0.01);
}

test "cubic stroke has no detached coverage island near its start cap" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const coverage = @import("coverage.zig");
    const geometry = @import("geometry.zig");
    const Vec2 = math.Vec2;

    var path = @import("snail_core").files.path.Path.init(allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0.08, .y = 0.7 });
    try path.cubicTo(
        .{ .x = 0.3, .y = -0.1 },
        .{ .x = 0.7, .y = 1.1 },
        .{ .x = 0.92, .y = 0.3 },
    );
    var prepared = try path.prepare(allocator);
    defer prepared.deinit();
    var curves = try prepared.strokeCurves(allocator, allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 0.08,
        .cap = .round,
        .join = .round,
    });
    defer curves.deinit();

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail_core").files.atlas_record_key.RecordKey{
        .namespace = @import("snail_core").files.atlas_record_key.ns.path_stroke,
        .a = 0,
    };
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{
        .key = key,
        .curves = curves,
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }});
    defer atlas.deinit();

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const page = &cache.prepared[0].?;
    const layer = cache.snapshotFor(bindings[0].generation).?.path_layers[0];
    const be = layer.band_entry;

    const screen_scale: f32 = 300.0;
    const inv = (Transform2D{
        .xx = screen_scale * prepared.design_to_source.xx,
        .yy = screen_scale * prepared.design_to_source.yy,
    }).inverse().?;
    const epp = geometry.glyphEdgePixelsPerPixel(inv);
    const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);

    var worst: f32 = 0.0;
    var sy: f32 = 0.25;
    while (sy <= 0.45) : (sy += 0.0025) {
        var sx: f32 = 0.04;
        while (sx <= 0.11) : (sx += 0.0025) {
            const design = prepared.source_to_design.applyPoint(.{ .x = sx, .y = sy });
            worst = @max(worst, coverage.evalGlyphCoverageBandSpan(
                page,
                design.x,
                design.y,
                epp.x,
                epp.y,
                ppe.x,
                ppe.y,
                be,
                layer.band_max_h,
                layer.band_max_v,
                layer.fill_rule,
            ));
        }
    }
    try testing.expect(worst < 0.01);
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

test "drawCpu scissor_rect clips writes to the rect" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    const W: u32 = 64;
    const H: u32 = 48;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);
    const gid = try font.glyphIndex('M');
    var curves = try font.extractCurves(allocator, allocator, gid);
    defer curves.deinit();

    var pool = try @import("snail_core").files.atlas_page_pool.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail_core").files.atlas_record_key.unhintedGlyph(0, gid);
    var atlas = try @import("snail_core").files.atlas.Atlas.from(allocator, pool, &.{.{ .key = key, .curves = curves }});
    defer atlas.deinit();

    var cache = try CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const px_size: f32 = 36.0;
    const shape = @import("snail_core").files.picture_shape.Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 8, .ty = 40 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    const shapes = [_]@import("snail_core").files.picture_shape.Shape{shape};

    const emit_mod = @import("snail_core").files.picture_emit;
    const words = try allocator.alloc(u32, emit_mod.wordBudget(shapes.len));
    defer allocator.free(words);
    var segs: [2]draw_records.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, bindings[0], &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });
    const records = DrawRecords{ .words = words[0..wlen], .segments = segs[0..slen] };

    // Render once without scissor — the glyph should populate the
    // left half of the buffer.
    const px_full = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_full);
    @memset(px_full, 0);
    var ren_full = @import("renderer.zig").CpuRenderer.init(px_full.ptr, W, H, STRIDE);
    const state_full = makeIdentityState(W, H);
    try drawCpu(&ren_full, state_full, records, &.{&cache}, null);

    // Render again with a scissor that omits the left half of the
    // glyph. Every pixel inside the scissor should match the unclipped
    // render; every pixel outside should be zero.
    const px_clip = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_clip);
    @memset(px_clip, 0);
    var ren_clip = @import("renderer.zig").CpuRenderer.init(px_clip.ptr, W, H, STRIDE);
    var state_clip = makeIdentityState(W, H);
    state_clip.scissor_rect = .{ .x = 24, .y = 0, .w = 24, .h = H };
    try drawCpu(&ren_clip, state_clip, records, &.{&cache}, null);

    var row: u32 = 0;
    while (row < H) : (row += 1) {
        var col: u32 = 0;
        while (col < W) : (col += 1) {
            const off = row * STRIDE + col * 4;
            const in_scissor = col >= 24 and col < 48;
            if (in_scissor) {
                try testing.expectEqual(px_full[off + 0], px_clip[off + 0]);
                try testing.expectEqual(px_full[off + 3], px_clip[off + 3]);
            } else {
                try testing.expectEqual(@as(u8, 0), px_clip[off + 3]);
            }
        }
    }

    // Spot check: at least one pixel inside the scissor is non-zero
    // (otherwise the test would pass trivially).
    var any_drawn = false;
    var i: usize = 0;
    while (i < px_clip.len) : (i += 4) {
        if (px_clip[i + 3] != 0) {
            any_drawn = true;
            break;
        }
    }
    try testing.expect(any_drawn);
}
