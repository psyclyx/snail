//! Public draw entry for the software rasterizer.
//!
//! Walks batches, resolves each batch's `Binding.pool` to a
//! `DeviceAtlas` (caller-supplied), validates the binding's complete owner,
//! generation, and placement identity, then dispatches per-instance into the
//! CPU rasterizer through its package-private prepared-resource bridge.
//!

const std = @import("std");

const snail = @import("snail");
const render_state = @import("snail").render.target;
const math = @import("snail");
const draw_records = snail.render.records;
const device_atlas_mod = @import("device_atlas.zig");
const resources_mod = @import("resources.zig");
const vertex = @import("snail").render.records;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

pub const DrawRecords = draw_records.DrawRecords;

pub const DeviceAtlas = device_atlas_mod.DeviceAtlas;
pub const Binding = draw_records.Binding;
pub const Transform2D = math.Transform2D;

pub const DrawError = draw_records.DrawRecords.ValidationError || error{
    /// Batch references a `PagePool` no entry in `caches` covers.
    MissingBinding,
    /// A cache covers the pool, but no live slot matches the binding's complete
    /// source, generation, and placement identity.
    StaleBinding,
};

const renderer_mod = @import("renderer.zig");
const Renderer = renderer_mod.Renderer;
const RendererPtr = *Renderer;

/// Render `records` into `renderer`'s pixel buffer. `caches` provides the
/// CPU-side prepared data for the bindings referenced by `records.batches`.
/// The complete record stream and every binding identity are preflighted
/// before rendering, so malformed records and stale resources never produce a
/// partially drawn target.
///
/// `thread_pool` is the per-call work-distribution policy: pass a non-null
/// pool to fan tile work across its workers, or `null` to rasterize on the
/// calling thread. Output is byte-identical either way. A pool wins on
/// large batches and loses on small ones (dispatch overhead > work), so
/// the caller decides per draw rather than configuring the renderer once.
pub fn draw(
    renderer: RendererPtr,
    state: render_state.DrawState,
    records: DrawRecords,
    caches: []const *const DeviceAtlas,
    thread_pool: ?*ThreadPool,
    // `NonAffineMvp` bubbles up from the rasterizer, which (unlike the GPU
    // backends) can't handle a perspective MVP.
) (DrawError || Renderer.DrawBatchError)!void {
    try renderer.validateTarget(state.surface);
    try records.validate();
    // Validate all resource identities before the first pixel write.
    for (records.batches) |batch| _ = try findCache(caches, batch.binding);

    for (records.batches) |batch| {
        const cache = try findCache(caches, batch.binding);

        var layer_info_buf: [1]resources_mod.LayerInfoEntry = undefined;
        var layer_infos_slice: []resources_mod.LayerInfoEntry = &.{};
        var layer_info_count: usize = 0;
        if (cache.snapshotFor(batch.binding)) |snap| {
            layer_info_buf[0] = .{
                .data = snap.layer_info_data,
                .width = snap.layer_info_width,
                .height = snap.info_height,
                .row_base = snap.info_row_base,
                .path_records = snap.path_records,
                .path_layers = snap.path_layers,
            };
            layer_infos_slice = layer_info_buf[0..1];
            layer_info_count = 1;
        }
        var prepared = resources_mod.PreparedResources{
            .allocator = cache.allocator,
            .atlas_pages = cache.prepared,
            .layer_infos = layer_infos_slice,
            .layer_info_count = layer_info_count,
        };
        const batch_instances = records.instances[batch.first_instance..][0..batch.instance_count];
        try renderer_mod.drawPreparedBatch(
            renderer,
            &prepared,
            batch_instances,
            state,
            batch.page_base,
            thread_pool,
        );
    }
}

fn findCache(
    caches: []const *const DeviceAtlas,
    binding: Binding,
) DrawError!*const DeviceAtlas {
    var pool_seen = false;
    for (caches) |c| {
        if (c.pool != binding.pool) continue;
        pool_seen = true;
        if (c.isBindingLive(binding)) return c;
    }
    return if (pool_seen) error.StaleBinding else error.MissingBinding;
}

// ---------------------------------------------------------------------------
// Tests
//
// The emit() tests lock down the draw-record layout; these tests verify that
// the raster entry walks batches, validates bindings, and produces pixels
// through `drawBatch`.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "draw MissingBinding when no cache covers the binding's pool" {
    const allocator = testing.allocator;

    const upload_plan = @import("snail").atlas_upload;
    var pool_a = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 1,
        .curve_words_per_page = upload_plan.CURVE_TEX_WIDTH * 4,
        .band_words_per_page = upload_plan.BAND_TEX_WIDTH * 2,
    });
    defer pool_a.deinit();
    var pool_b = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 1,
        .curve_words_per_page = upload_plan.CURVE_TEX_WIDTH * 4,
        .band_words_per_page = upload_plan.BAND_TEX_WIDTH * 2,
    });
    defer pool_b.deinit();

    var cache_a = try DeviceAtlas.init(allocator, pool_a, .{ .max_bindings = 1, .layer_info_height = 4, .max_images = 0 });
    defer cache_a.deinit();

    var pixels: [16 * 16 * 4]u8 = .{0} ** (16 * 16 * 4);
    var renderer = try @import("renderer.zig").Renderer.init(&pixels, 16, 16, 16 * 4, .rgba8_unorm);
    const state = makeIdentityState(16, 16);

    const batches = [_]draw_records.DrawBatch{.{
        .binding = .{ .pool = pool_b, .generation = 0 },
        .first_instance = 0,
        .instance_count = 1,
        .kind = .regular,
    }};
    var instances = [_]snail.render.records.Instance{std.mem.zeroes(snail.render.records.Instance)};
    instances[0].xform = .{ 1, 0, 0, 1 };
    const records = DrawRecords{ .instances = &instances, .batches = &batches };
    try testing.expectError(error.MissingBinding, draw(&renderer, state, records, &.{&cache_a}, null));
}

test "draw autohint fits per size without mutating atlas resources" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    const atlas_mod = @import("snail");
    const record_key_mod = @import("snail").record_key;
    const shape_mod = @import("snail");
    const emit_mod = @import("snail").emit;

    const W: u32 = 48;
    const H: u32 = 40;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);
    const gid = try font.glyphIndex('H');
    var curves = try font.extractCurves(allocator, allocator, gid);
    defer curves.deinit();

    var analyzer = try snail.autohint.AutohintAnalyzer.init(allocator, font_data);
    defer analyzer.deinit();
    var x_features: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;
    var y_features: [snail.autohint.max_features_per_axis]snail.autohint.FeatureEdge = undefined;
    const glyph_features = try analyzer.analyzeGlyph(allocator, gid, &x_features, &y_features);
    try testing.expect(glyph_features.x.len > 0 or glyph_features.y.len > 0);

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const base_key = record_key_mod.unhintedGlyph(0, gid);
    const key = record_key_mod.autohintGlyph(0, gid);
    var atlas = try atlas_mod.Atlas.from(allocator, pool, .{ .entries = &.{
        .{ .geometry = .{ .key = base_key, .curves = curves.view() } },
        .{ .autohint = .{
            .key = key,
            .base_key = base_key,
            .analysis = .{ .font = analyzer.fontFeatures(), .glyph = glyph_features },
        } },
    } });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 16, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const pages_ptr = atlas.pages.ptr;
    const pages_len = atlas.pages.len;
    const page = atlas.pages[0];
    const layer_info = atlas.layer_info_data.?;
    const layer_info_copy = try allocator.dupe(f32, layer_info);
    defer allocator.free(layer_info_copy);

    const Render = struct {
        fn atSize(
            pixels: []u8,
            px_size: f32,
            policy: snail.autohint.AutohintPolicy,
            shape_key: atlas_mod.record_key.RecordKey,
            binding: Binding,
            atlas_ptr: *const atlas_mod.Atlas,
            cache_ptr: *const DeviceAtlas,
        ) !void {
            @memset(pixels, 0);
            const shape = shape_mod.Shape{
                .key = shape_key,
                .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 10, .ty = 28 },
                .autohint_policy = policy,
            };
            var instances: [1]vertex.Instance = undefined;
            var batches: [1]draw_records.DrawBatch = undefined;
            var ilen: usize = 0;
            var blen: usize = 0;
            _ = try emit_mod.emit(&instances, &batches, &ilen, &blen, binding, atlas_ptr, &.{shape}, .identity, .{ 1, 1, 1, 1 });
            var renderer = try @import("renderer.zig").Renderer.init(pixels, W, H, STRIDE, .rgba8_unorm);
            try draw(&renderer, makeIdentityState(W, H), .{ .instances = instances[0..ilen], .batches = batches[0..blen] }, &.{cache_ptr}, null);
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
    try testing.expectEqual(layer_info.ptr, atlas.layer_info_data.?.ptr);
    try testing.expectEqual(layer_info.len, atlas.layer_info_data.?.len);
    try testing.expectEqualSlices(u8, std.mem.sliceAsBytes(layer_info_copy), std.mem.sliceAsBytes(atlas.layer_info_data.?));
}

test "draw renders a small Picture into non-zero pixels" {
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
    var owned: [1]@import("snail").GlyphCurves = .{curves_a};
    defer for (&owned) |*c| c.deinit();

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail").record_key.unhintedGlyph(0, gid);
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{
        .{ .geometry = .{ .key = key, .curves = owned[0].view() } },
    } });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    // GlyphCurves.bbox lives in unit-em coordinates (max ~1.0), so the
    // shape's scale is just the requested px size.
    const px_size: f32 = 24.0;
    const scale: f32 = px_size;
    const shape = @import("snail").Shape{
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
    const shapes = [_]@import("snail").Shape{shape};

    const emit_mod = @import("snail").emit;
    const instance_need = shapes.len;
    const instances = try allocator.alloc(vertex.Instance, instance_need);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit_mod.emit(instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = try @import("renderer.zig").Renderer.init(px, W, H, STRIDE, .rgba8_unorm);
    const state = makeIdentityState(W, H);
    const records = DrawRecords{ .instances = instances[0..ilen], .batches = batches[0..blen] };
    try draw(&renderer, state, records, &.{&cache}, null);

    // Expect some non-zero pixel coverage from the glyph.
    var any_drawn = false;
    for (px) |b| if (b != 0) {
        any_drawn = true;
        break;
    };
    try testing.expect(any_drawn);

    cache.release(binding);
    try testing.expectError(error.StaleBinding, draw(&renderer, state, records, &.{&cache}, null));
}

test "draw renders gradient-painted glyph through special-layer path" {
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

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail").record_key.unhintedGlyph(0, gid);

    // Linear gradient running across the glyph's local-em width.
    const gradient = snail.LinearGradient{
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 1, .y = 0 },
        .start_color = .{ 1, 0, 0, 1 },
        .end_color = .{ 0, 0, 1, 1 },
    };
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = curves.view(),
            .paint = .{ .linear_gradient = gradient },
        },
    }} });
    defer atlas.deinit();

    try testing.expect(atlas.lookupPaintRecord(key) != null);

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 32.0;
    const shape = @import("snail").Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 12, .ty = 40 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    const shapes = [_]@import("snail").Shape{shape};

    const emit_mod = @import("snail").emit;
    const instances = try allocator.alloc(vertex.Instance, shapes.len);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit_mod.emit(instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = try @import("renderer.zig").Renderer.init(px, W, H, STRIDE, .rgba8_unorm);
    const state = makeIdentityState(W, H);
    try draw(&renderer, state, .{ .instances = instances[0..ilen], .batches = batches[0..blen] }, &.{&cache}, null);

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

test "draw applies per-shape local color to image-painted path" {
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
    var image = try snail.Image.init(allocator, 4, 4, image_pixels[0..]);
    defer image.deinit();

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    // Square-ish path covering [0..1, 0..1] in local coords; the local
    // shape transform scales to pixel size.
    var path = @import("snail").Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var path_curves = try prepared_path.fillCurves(allocator, allocator);
    defer path_curves.deinit();

    const key = @import("snail").record_key.RecordKey{
        .namespace = @import("snail").record_key.ns.path_fill,
        .a = 0,
    };
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = path_curves.view(),
            .paint = .{ .image = .{
                .image = &image,
                .uv_transform = .identity,
            } },
        },
    }} });
    defer atlas.deinit();

    try testing.expect(atlas.paint_records != null);
    try testing.expect(atlas.paint_records.?[0].image == &image);

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 4 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const px_size: f32 = 12.0;
    const shapes = [_]@import("snail").Shape{
        .{
            .key = key,
            .local_transform = .{ .xx = px_size, .yy = px_size, .tx = 2, .ty = 10 },
            .local_color = .{ 1, 1, 1, 1 },
        },
        .{
            .key = key,
            .local_transform = .{ .xx = px_size, .yy = px_size, .tx = 18, .ty = 10 },
            .local_color = .{ 0.25, 1, 1, 1 },
        },
    };

    const emit_mod = @import("snail").emit;
    const instances = try allocator.alloc(vertex.Instance, shapes.len);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit_mod.emit(instances, batches[0..], &ilen, &blen, binding, &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = try @import("renderer.zig").Renderer.init(px, W, H, STRIDE, .rgba8_unorm);
    const state = makeIdentityState(W, H);
    try draw(&renderer, state, .{ .instances = instances[0..ilen], .batches = batches[0..blen] }, &.{&cache}, null);

    // The two halves contain identical instances of the same immutable
    // image-paint record. Their only color difference is Shape.local_color.
    var full_red: u8 = 0;
    var quarter_red: u8 = 0;
    var row: u32 = 0;
    while (row < H) : (row += 1) {
        var col: u32 = 0;
        while (col < W) : (col += 1) {
            const off = row * STRIDE + col * 4;
            if (px[off + 3] < 220) continue;
            if (col < W / 2) {
                full_red = @max(full_red, px[off]);
            } else {
                quarter_red = @max(quarter_red, px[off]);
            }
        }
    }
    try testing.expect(full_red > 200);
    try testing.expect(quarter_red > 32);
    try testing.expect(@as(u16, quarter_red) + 32 < @as(u16, full_red));
}

test "color-bitmap glyph renders as a placed image with upright orientation" {
    const allocator = testing.allocator;

    // A bitmap glyph is a placed image: extract the strike from the font,
    // decode it (a host service — stubbed here with a four-color 2x2 probe),
    // record it as an image-painted em-bbox rect keyed by ppem, and draw it
    // exactly like an outline glyph. The four quadrants let us verify both
    // sampling and orientation land the right corner in the right place.
    var font = try snail.Font.init(@import("assets").chromacheck_cbdt);
    const glyph_id = try font.glyphIndex(0xE903);
    const ppem: u16 = 32;
    var strike = (try font.colorBitmap(allocator, glyph_id, ppem)).?;
    defer strike.deinit();

    // Host decoder: turns the encoded strike into straight-alpha sRGBA texels.
    // TL red, TR green, BL blue, BR white (row-major, top row first).
    const Decoder = struct {
        fn decode(
            _: *anyopaque,
            _: snail.font.BitmapFormat,
            _: []const u8,
            gpa: std.mem.Allocator,
        ) snail.font.color_bitmap.DecodeError!snail.Image {
            const texels = [_]u8{
                255, 0,   0,   255, 0,   255, 0,   255,
                0,   0,   255, 255, 255, 255, 255, 255,
            };
            return snail.Image.init(gpa, 2, 2, &texels) catch return error.DecodeFailed;
        }
    };
    var stub_context: u8 = 0;
    const decoder = snail.font.ImageDecoder{ .context = &stub_context, .decode = Decoder.decode };
    var image = try decoder.decodeImage(strike.format, strike.data, allocator);
    defer image.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    // Geometry: a rect covering the strike's em-space placement box.
    const bb = strike.bbox;
    const w = bb.max.x - bb.min.x;
    const h = bb.max.y - bb.min.y;
    var path = snail.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = bb.min.x, .y = bb.min.y, .w = w, .h = h });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var rect_curves = try prepared_path.fillCurves(allocator, allocator);
    defer rect_curves.deinit();

    // `prepare` normalizes the rect into a [-1,1] design space; `design_to_source`
    // maps that back to the authored em rect. Composing it into both the uv and
    // the placement keeps everything in the strike's own em frame.
    const d2s = prepared_path.design_to_source;
    // Image UV maps the em-space rect (y-up) onto the image (rows top-down);
    // the flip keeps the strike upright under an outline glyph's placement.
    const uv_transform = snail.font.color_bitmap.imageUvTransform(strike.bbox).multiply(d2s);
    const key = snail.record_key.colorBitmapGlyph(0, glyph_id, ppem);
    var atlas = try snail.Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = rect_curves.view(),
            .paint = .{ .image = .{
                .image = &image,
                .uv_transform = uv_transform,
                .filter = .nearest,
            } },
        },
    }} });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 1 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const W: u32 = 40;
    const H: u32 = 40;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    // Place em(0..1) into the pixel box [8,8]..[8+S,8+S] with the y-flip an
    // outline run-placement transform carries: em-top -> screen-top.
    const x0: f32 = 8;
    const y0: f32 = 8;
    const S: f32 = 24;
    // Placement maps the source em rect (y-up) into the pixel box, composed
    // with design_to_source since the geometry lives in design space.
    const place = snail.Transform2D{ .xx = S, .xy = 0, .tx = x0, .yx = 0, .yy = -S, .ty = y0 + S };
    const shapes = [_]snail.Shape{.{
        .key = key,
        .local_transform = place.multiply(d2s),
        .local_color = .{ 1, 1, 1, 1 },
    }};

    const instances = try allocator.alloc(vertex.Instance, shapes.len);
    defer allocator.free(instances);
    var batches: [1]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try @import("snail").emit.emit(instances, batches[0..], &ilen, &blen, bindings[0], &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = try @import("renderer.zig").Renderer.init(px, W, H, STRIDE, .rgba8_unorm);
    const state = makeIdentityState(W, H);
    try draw(&renderer, state, .{ .instances = instances[0..ilen], .batches = batches[0..blen] }, &.{&cache}, null);

    // Dominant channel at each quadrant center (box spans pixels 8..32).
    const dominant = struct {
        fn at(pixels: []const u8, stride: u32, cx: u32, cy: u32) u2 {
            const off = cy * stride + cx * 4;
            const r = pixels[off + 0];
            const g = pixels[off + 1];
            const b = pixels[off + 2];
            if (r >= g and r >= b) return 0;
            if (g >= r and g >= b) return 1;
            return 2;
        }
    };
    try testing.expectEqual(@as(u2, 0), dominant.at(px, STRIDE, 14, 14)); // TL red
    try testing.expectEqual(@as(u2, 1), dominant.at(px, STRIDE, 26, 14)); // TR green
    try testing.expectEqual(@as(u2, 2), dominant.at(px, STRIDE, 14, 26)); // BL blue
    // BR white: all channels high.
    const br = 26 * STRIDE + 26 * 4;
    try testing.expect(px[br + 0] > 200 and px[br + 1] > 200 and px[br + 2] > 200);
}

test "shaped run of color-bitmap glyphs places and renders through the public API" {
    const allocator = testing.allocator;

    // The caller pattern, using only `snail` + `snail-raster`: shape a run,
    // place it like any text, then for each glyph that has a strike, decode it
    // (host service, stubbed), record it as an image-painted em-bbox rect, and
    // swap the placed shape onto that record. Outline and bitmap glyphs share
    // one placement path — a bitmap glyph is just a placed image.
    var font = try snail.Font.init(@import("assets").chromacheck_cbdt);
    var faces = try snail.Faces.build(allocator, &.{.{ .font = &font, .font_id = 0 }});
    defer faces.deinit();

    // Two emoji: a run with two distinct pen positions.
    var shaped = try snail.shape(allocator, &faces, "\u{E903}\u{E903}", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    const em: f32 = 16;
    const ppem: u16 = 16;
    const shapes = try snail.placeRunAlloc(allocator, &shaped, &faces, .{
        .baseline = .{ .x = 4, .y = 26 },
        .em = em,
    });
    defer allocator.free(shapes);

    // Host decoder: four-color 2x2 probe (TL red, TR green, BL blue, BR white).
    const Decoder = struct {
        fn decode(
            _: *anyopaque,
            _: snail.font.BitmapFormat,
            _: []const u8,
            gpa: std.mem.Allocator,
        ) snail.font.color_bitmap.DecodeError!snail.Image {
            const texels = [_]u8{
                255, 0,   0,   255, 0,   255, 0,   255,
                0,   0,   255, 255, 255, 255, 255, 255,
            };
            return snail.Image.init(gpa, 2, 2, &texels) catch return error.DecodeFailed;
        }
    };
    var ctx: u8 = 0;
    const decoder = snail.font.ImageDecoder{ .context = &ctx, .decode = Decoder.decode };

    // Both glyphs are the same emoji, so one decoded image + one atlas record
    // serve the whole run.
    const glyph_id = shaped.glyphs[0].glyph_id;
    const font_id = shaped.glyphs[0].font_id;
    var strike = (try faces.fontForFace(shaped.glyphs[0].face_index).?.colorBitmap(allocator, glyph_id, ppem)).?;
    defer strike.deinit();
    var image = try decoder.decodeImage(strike.format, strike.data, allocator);
    defer image.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const bb = strike.bbox;
    var path = snail.Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = bb.min.x, .y = bb.min.y, .w = bb.max.x - bb.min.x, .h = bb.max.y - bb.min.y });
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var rect_curves = try prepared_path.fillCurves(allocator, allocator);
    defer rect_curves.deinit();

    // `prepare` normalizes into a [-1,1] design space; `design_to_source` maps
    // back to the authored em rect. Composing it into both the uv and each
    // glyph's placement keeps a bitmap glyph in the exact em frame an outline
    // glyph uses — so it lands em-sized and abuts its neighbor instead of
    // spilling over it.
    const d2s = prepared_path.design_to_source;
    const key = snail.record_key.colorBitmapGlyph(font_id, glyph_id, ppem);
    var atlas = try snail.Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = rect_curves.view(),
            .paint = .{ .image = .{
                .image = &image,
                .uv_transform = snail.font.color_bitmap.imageUvTransform(bb).multiply(d2s),
                .filter = .nearest,
            } },
        },
    }} });
    defer atlas.deinit();

    // Swap every strike-backed glyph onto its bitmap record (untinted), keeping
    // its placeRun origin for the assertions before composing design_to_source.
    const origins = try allocator.alloc(?[2]f32, shapes.len);
    defer allocator.free(origins);
    @memset(origins, null);
    for (shapes, shaped.glyphs, origins) |*shp, g, *origin| {
        if (try faces.fontForFace(g.face_index).?.colorBitmap(allocator, g.glyph_id, ppem)) |*present| {
            @constCast(present).deinit();
            origin.* = .{ shp.local_transform.tx, shp.local_transform.ty };
            shp.key = snail.record_key.colorBitmapGlyph(g.font_id, g.glyph_id, ppem);
            shp.local_color = .{ 1, 1, 1, 1 };
            shp.local_transform = shp.local_transform.multiply(d2s);
        }
    }

    // Size the framebuffer to the placed run (advances are the font's to pick).
    var max_x: f32 = 0;
    for (origins) |o| if (o) |v| {
        max_x = @max(max_x, v[0] + em);
    };
    const W: u32 = @intFromFloat(@ceil(max_x) + 4);
    const H: u32 = 32;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 1 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const instances = try allocator.alloc(vertex.Instance, shapes.len);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try @import("snail").emit.emit(instances, batches[0..], &ilen, &blen, bindings[0], &atlas, shapes, .identity, .{ 1, 1, 1, 1 });

    var renderer = try @import("renderer.zig").Renderer.init(px, W, H, STRIDE, .rgba8_unorm);
    const state = makeIdentityState(W, H);
    try draw(&renderer, state, .{ .instances = instances[0..ilen], .batches = batches[0..blen] }, &.{&cache}, null);

    const dominant = struct {
        fn at(pixels: []const u8, stride: u32, cx: f32, cy: f32) u2 {
            const off = (@as(u32, @intFromFloat(cy)) * stride) + @as(u32, @intFromFloat(cx)) * 4;
            const r = pixels[off + 0];
            const g = pixels[off + 1];
            const b = pixels[off + 2];
            if (r >= g and r >= b) return 0;
            if (g >= r and g >= b) return 1;
            return 2;
        }
    };
    // Each placed emoji occupies x in [ox, ox+em], y in [oy-em, oy] (above the
    // baseline). Verify the three chromatic quadrants for BOTH instances —
    // proving run placement and per-strike sampling/orientation together.
    for (origins) |o| {
        const v = o orelse continue;
        const ox = v[0];
        const oy = v[1];
        try testing.expectEqual(@as(u2, 0), dominant.at(px, STRIDE, ox + em * 0.25, oy - em * 0.75)); // TL red
        try testing.expectEqual(@as(u2, 1), dominant.at(px, STRIDE, ox + em * 0.75, oy - em * 0.75)); // TR green
        try testing.expectEqual(@as(u2, 2), dominant.at(px, STRIDE, ox + em * 0.25, oy - em * 0.25)); // BL blue
    }
}

test "draw threaded matches single-threaded pixel-for-pixel" {
    // Worker threads are Linux-only (see thread_pool.zig); elsewhere the
    // explicit 3-thread request below fails with UnsupportedPlatform.
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    // Tall enough that row_clip_max > row_clip_min + TILE_ROWS (32) so the
    // parallel dispatch path actually triggers.
    const W: u32 = 128;
    const H: u32 = 96;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);

    const glyphs = "Hello, world!";
    const Owned = @import("snail").GlyphCurves;
    var owned: std.ArrayList(Owned) = .empty;
    defer {
        for (owned.items) |*c| c.deinit();
        owned.deinit(allocator);
    }
    var entries: std.ArrayList(@import("snail").AtlasGeometryEntry) = .empty;
    defer entries.deinit(allocator);

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var shapes: std.ArrayList(@import("snail").Shape) = .empty;
    defer shapes.deinit(allocator);

    const px_size: f32 = 18.0;
    var pen_x: f32 = 4;
    for (glyphs) |c| {
        const gid = try font.glyphIndex(c);
        const key = @import("snail").record_key.unhintedGlyph(0, gid);
        if (!containsEntryKey(entries.items, key)) {
            const curves = try font.extractCurves(allocator, allocator, gid);
            try owned.append(allocator, curves);
            try entries.append(allocator, .{ .key = key, .curves = owned.items[owned.items.len - 1].view() });
        }
        try shapes.append(allocator, .{
            .key = key,
            .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = pen_x, .ty = 64 },
            .local_color = .{ 1, 1, 1, 1 },
        });
        pen_x += px_size * 0.55;
    }

    const tagged = try allocator.alloc(@import("snail").AtlasEntry, entries.items.len);
    defer allocator.free(tagged);
    for (entries.items, tagged) |entry, *out| out.* = .{ .geometry = entry };
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = tagged });
    defer atlas.deinit();
    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const emit_mod = @import("snail").emit;
    const instances = try allocator.alloc(vertex.Instance, shapes.items.len);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit_mod.emit(instances, batches[0..], &ilen, &blen, bindings[0], &atlas, shapes.items, .identity, .{ 1, 1, 1, 1 });
    const records = DrawRecords{ .instances = instances[0..ilen], .batches = batches[0..blen] };
    const state = makeIdentityState(W, H);

    const px_serial = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_serial);
    @memset(px_serial, 0);
    var renderer_serial = try @import("renderer.zig").Renderer.init(px_serial, W, H, STRIDE, .rgba8_unorm);
    try draw(&renderer_serial, state, records, &.{&cache}, null);

    const px_threaded = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_threaded);
    @memset(px_threaded, 0);

    var thread_pool: ThreadPool = undefined;
    try thread_pool.init(allocator, .{ .threads = 3 });
    defer thread_pool.deinit();

    var renderer_threaded = try @import("renderer.zig").Renderer.init(px_threaded, W, H, STRIDE, .rgba8_unorm);
    try draw(&renderer_threaded, state, records, &.{&cache}, &thread_pool);

    try testing.expectEqualSlices(u8, px_serial, px_threaded);
}

fn containsEntryKey(entries: []const @import("snail").AtlasGeometryEntry, key: @import("snail").record_key.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

test "shared-endpoint interior coverage stays solid (no centre seam)" {
    // Regression for the 1px white seam down shapes whose halves meet on the
    // sampling axis. The banner "custom path" leaf is two cubics sharing the
    // endpoints (0.5,0) and (0.5,1). Adaptive lowering must retain those joins
    // exactly so the half-open quadratic root convention assigns each
    // vertical-ray endpoint crossing once.
    const allocator = testing.allocator;
    const coverage = @import("coverage.zig");
    const geometry = @import("geometry.zig");
    const Vec2 = math.Vec2;

    var path = @import("snail").Path.init(allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0.5, .y = 0 });
    try path.cubicTo(.{ .x = 0.95, .y = 0.2 }, .{ .x = 0.95, .y = 0.8 }, .{ .x = 0.5, .y = 1 });
    try path.cubicTo(.{ .x = 0.05, .y = 0.8 }, .{ .x = 0.05, .y = 0.2 }, .{ .x = 0.5, .y = 0 });
    try path.close();
    var prepared_path = try path.prepare(allocator);
    defer prepared_path.deinit();
    var curves = try prepared_path.fillCurves(allocator, allocator);
    defer curves.deinit();

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail").record_key.RecordKey{
        .namespace = @import("snail").record_key.ns.path_fill,
        .a = 0,
    };
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = curves.view(),
            .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        },
    }} });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const page = &cache.prepared[0].?;
    const layer = cache.snapshotFor(bindings[0]).?.path_layers[0];
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
    const allocator = testing.allocator;
    const coverage = @import("coverage.zig");
    const geometry = @import("geometry.zig");
    const Vec2 = math.Vec2;

    var path = @import("snail").Path.init(allocator);
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

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail").record_key.RecordKey{
        .namespace = @import("snail").record_key.ns.path_stroke,
        .a = 0,
    };
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{.{
        .geometry = .{
            .key = key,
            .curves = curves.view(),
            .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        },
    }} });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const page = &cache.prepared[0].?;
    const layer = cache.snapshotFor(bindings[0]).?.path_layers[0];
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

test "compact preserves rendering byte-for-byte across record kinds" {
    const allocator = testing.allocator;
    const emit_mod = @import("snail").emit;
    const record_key_mod = @import("snail").record_key;

    const W: u32 = 128;
    const H: u32 = 48;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(@import("assets").dejavu_sans_mono);
    var emoji_font = try snail.Font.init(@import("assets").twemoji_mozilla);
    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font, .font_id = 0 },
        .{ .font = &emoji_font, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try snail.shape(allocator, &faces, "Ab\xf0\x9f\x8c\x8d", .{});
    var shaped_latin = try snail.shape(allocator, &faces, "Ab", .{});
    defer shaped.deinit();
    defer shaped_latin.deinit();

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 8,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    // Prepare every kind: unhinted + COLR, autohint analysis, TT-hinted
    // curves + advances.
    var atlas = try @import("snail").Atlas.init(allocator, pool);
    defer atlas.deinit();
    const sources = [_]snail.FontSource{
        .{ .font_id = 0, .font = &font, .cache_key = .{0} ** 16 },
        .{ .font_id = 1, .font = &emoji_font, .cache_key = .{1} ** 16 },
    };

    {
        var plan = try snail.planRuns(
            &atlas,
            allocator,
            &sources,
            &.{&shaped},
            .{ .unhinted = .{} },
        );
        defer plan.deinit();
        const owned = try allocator.alloc(?snail.prepared.OwnedRecord, plan.requests().len);
        defer allocator.free(owned);
        @memset(owned, null);
        const views = try allocator.alloc(?snail.prepared.RecordView, plan.requests().len);
        defer allocator.free(views);
        @memset(views, null);
        defer for (owned) |*record| if (record.*) |*value| value.deinit();

        var context = snail.OutlineContext.init(allocator, allocator);
        defer context.deinit();
        for (plan.requests(), 0..) |request, i| {
            owned[i] = try context.prepare(request);
            views[i] = owned[i].?.view();
        }
        try plan.applyInPlace(allocator, &atlas, views);
    }

    {
        const options: snail.AutohintRunOptions = .{};
        var plan = try snail.planRuns(
            &atlas,
            allocator,
            &sources,
            &.{&shaped_latin},
            .{ .autohint = options },
        );
        defer plan.deinit();
        const owned = try allocator.alloc(?snail.prepared.OwnedRecord, plan.requests().len);
        defer allocator.free(owned);
        @memset(owned, null);
        const views = try allocator.alloc(?snail.prepared.RecordView, plan.requests().len);
        defer allocator.free(views);
        @memset(views, null);
        defer for (owned) |*record| if (record.*) |*value| value.deinit();

        var outline = snail.OutlineContext.init(allocator, allocator);
        defer outline.deinit();
        var autohint = try snail.AutohintContext.init(
            allocator,
            allocator,
            &sources[0],
            options.autohint,
        );
        defer autohint.deinit();
        for (plan.requests(), 0..) |request, i| {
            owned[i] = switch (request.operation) {
                .outline => try outline.prepare(request),
                .autohint_model, .autohint_glyph => try autohint.prepare(request),
                else => return error.UnexpectedPrepareRequest,
            };
            views[i] = owned[i].?.view();
        }
        try plan.applyInPlace(allocator, &atlas, views);
    }

    {
        const ppem = snail.TtHintPpem.uniform(13 * 64);
        var plan = try snail.planRuns(
            &atlas,
            allocator,
            &sources,
            &.{&shaped_latin},
            .{ .tt_hint = ppem },
        );
        defer plan.deinit();
        const owned = try allocator.alloc(?snail.prepared.OwnedRecord, plan.requests().len);
        defer allocator.free(owned);
        @memset(owned, null);
        const views = try allocator.alloc(?snail.prepared.RecordView, plan.requests().len);
        defer allocator.free(views);
        @memset(views, null);
        defer for (owned) |*record| if (record.*) |*value| value.deinit();

        var context = try snail.TtHintContext.init(allocator, allocator, &sources[0]);
        defer context.deinit();
        var size = try context.prepareSize(ppem);
        defer size.deinit();
        for (plan.requests(), 0..) |request, i| {
            owned[i] = try context.prepare(&size, request);
            views[i] = owned[i].?.view();
        }
        try plan.applyInPlace(allocator, &atlas, views);
    }

    const policy: snail.autohint.AutohintPolicy = .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    };
    const unhinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 4, .y = 16 },
        .em = 13,
        .color = .{ 1, 1, 1, 1 },
        .mode = .unhinted,
    });
    defer allocator.free(unhinted);
    const autohinted = try snail.placeRunAlloc(allocator, &shaped_latin, null, .{
        .baseline = .{ .x = 4, .y = 30 },
        .em = 13,
        .color = .{ 1, 1, 0.5, 1 },
        .mode = .{ .autohint = policy },
    });
    defer allocator.free(autohinted);
    const tt_hinted = try snail.placeRunAlloc(allocator, &shaped_latin, null, .{
        .baseline = .{ .x = 4, .y = 44 },
        .em = 13,
        .color = .{ 0.5, 1, 1, 1 },
        .mode = .{ .tt_hint = .{ .ppem_26_6 = 13 * 64 } },
    });
    defer allocator.free(tt_hinted);
    _ = record_key_mod;

    const Render = struct {
        fn frame(
            alloc: std.mem.Allocator,
            target_pool: *@import("snail").PagePool,
            target_atlas: *const @import("snail").Atlas,
            shape_runs: []const []const @import("snail").Shape,
            pixels: []u8,
        ) !void {
            var cache = try DeviceAtlas.init(alloc, target_pool, .{ .max_bindings = 1, .layer_info_height = 32, .max_images = 0 });
            defer cache.deinit();
            var bindings: [1]Binding = undefined;
            try cache.upload(alloc, &.{target_atlas}, &bindings);

            var total: usize = 0;
            for (shape_runs) |run| total += run.len;
            const instances = try alloc.alloc(vertex.Instance, total);
            defer alloc.free(instances);
            const batches = try alloc.alloc(draw_records.DrawBatch, total);
            defer alloc.free(batches);
            var ilen: usize = 0;
            var blen: usize = 0;
            for (shape_runs) |run| {
                _ = try emit_mod.emit(instances, batches, &ilen, &blen, bindings[0], target_atlas, run, .identity, .{ 1, 1, 1, 1 });
            }

            @memset(pixels, 0);
            var renderer = try @import("renderer.zig").Renderer.init(pixels, 128, 48, 128 * 4, .rgba8_unorm);
            try draw(&renderer, makeIdentityState(128, 48), .{
                .instances = instances[0..ilen],
                .batches = batches[0..blen],
            }, &.{&cache}, null);
        }
    };

    const runs = [_][]const @import("snail").Shape{ unhinted, autohinted, tt_hinted };
    const pixels_before = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels_before);
    try Render.frame(allocator, pool, &atlas, &runs, pixels_before);

    var compacted = try atlas.compact(allocator, allocator, null);
    defer compacted.deinit();
    const pixels_after = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels_after);
    try Render.frame(allocator, pool, &compacted, &runs, pixels_after);

    var any_drawn = false;
    for (pixels_before) |b| {
        if (b != 0) {
            any_drawn = true;
            break;
        }
    }
    try testing.expect(any_drawn);
    try testing.expectEqualSlices(u8, pixels_before, pixels_after);
}

fn makeIdentityState(w: u32, h: u32) render_state.DrawState {
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    return .{
        .surface = .{ .pixel_width = w, .pixel_height = h, .encoding = .srgb },
        .raster = .{
            .subpixel_order = .none,
            .coverage_transfer = .{ .exponent = 1.0 },
        },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
}

test "draw scissor_rect clips writes to the rect" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    const W: u32 = 64;
    const H: u32 = 48;
    const STRIDE: u32 = W * 4;

    var font = try snail.Font.init(font_data);
    const gid = try font.glyphIndex('M');
    var curves = try font.extractCurves(allocator, allocator, gid);
    defer curves.deinit();

    var pool = try @import("snail").PagePool.init(allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    const key = @import("snail").record_key.unhintedGlyph(0, gid);
    var atlas = try @import("snail").Atlas.from(allocator, pool, .{ .entries = &.{
        .{ .geometry = .{ .key = key, .curves = curves.view() } },
    } });
    defer atlas.deinit();

    var cache = try DeviceAtlas.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);

    const px_size: f32 = 36.0;
    const shape = @import("snail").Shape{
        .key = key,
        .local_transform = .{ .xx = px_size, .yy = -px_size, .tx = 8, .ty = 40 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    const shapes = [_]@import("snail").Shape{shape};

    const emit_mod = @import("snail").emit;
    const instances = try allocator.alloc(vertex.Instance, shapes.len);
    defer allocator.free(instances);
    var batches: [2]draw_records.DrawBatch = undefined;
    var ilen: usize = 0;
    var blen: usize = 0;
    _ = try emit_mod.emit(instances, batches[0..], &ilen, &blen, bindings[0], &atlas, &shapes, .identity, .{ 1, 1, 1, 1 });
    const records = DrawRecords{ .instances = instances[0..ilen], .batches = batches[0..blen] };

    // Render once without scissor — the glyph should populate the
    // left half of the buffer.
    const px_full = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_full);
    @memset(px_full, 0);
    var ren_full = try @import("renderer.zig").Renderer.init(px_full, W, H, STRIDE, .rgba8_unorm);
    const state_full = makeIdentityState(W, H);
    try draw(&ren_full, state_full, records, &.{&cache}, null);

    // Render again with a scissor that omits the left half of the
    // glyph. Every pixel inside the scissor should match the unclipped
    // render; every pixel outside should be zero.
    const px_clip = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px_clip);
    @memset(px_clip, 0);
    var ren_clip = try @import("renderer.zig").Renderer.init(px_clip, W, H, STRIDE, .rgba8_unorm);
    var state_clip = makeIdentityState(W, H);
    state_clip.scissor_rect = .{ .x = 24, .y = 0, .w = 24, .h = H };
    try draw(&ren_clip, state_clip, records, &.{&cache}, null);

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
