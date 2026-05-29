//! Phase 4: CPU-backend draw entry for the new `DrawRecords` API.
//!
//! Walks segments, resolves each segment's `Binding.pool` to a
//! `CpuPreparedPages` cache (caller-supplied), validates the binding's
//! generation against the cache's last upload, then dispatches per-instance
//! into the existing CPU rasterizer via `CpuRenderer.drawTextPrepared`.
//!
//! Only `.heterogeneous` segments are supported in this MVP. Replicated
//! emit produces N shape blocks + M override blocks; the CPU rasterizer
//! doesn't yet materialize that outer product. Calls into replicated
//! segments surface `error.UnsupportedSegmentKind`.

const std = @import("std");

const build_options = @import("build_options");
const snail = @import("root.zig");
const draw_records = @import("draw_records.zig");
const cpu_upload_mod = @import("cpu_upload.zig");
const cpu_resources = @import("render/backend/cpu/resources.zig");

pub const DrawRecords = struct {
    words: []const u32,
    segments: []const draw_records.DrawSegment,
};

pub const CpuPreparedPages = cpu_upload_mod.CpuPreparedPages;
pub const Binding = draw_records.Binding;

pub const DrawError = error{
    /// Segment references a `PagePool` no entry in `caches` covers.
    MissingBinding,
    /// Segment's binding generation is newer than the cache's last upload.
    StaleBinding,
    /// Segment kind not implemented by the CPU draw path.
    UnsupportedSegmentKind,
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
    if (!build_options.enable_cpu) return error.UnsupportedSegmentKind;
    for (records.segments) |seg| {
        const cache = findCache(caches, seg.binding.pool) orelse return error.MissingBinding;
        if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) {
            return error.StaleBinding;
        }
        if (seg.kind != .heterogeneous) return error.UnsupportedSegmentKind;

        var prepared = cpu_resources.PreparedResources{
            .allocator = cache.allocator,
            .atlas_pages = cache.prepared,
        };
        const seg_words = records.words[seg.words_offset..][0..seg.words_len];
        try renderer.drawTextPrepared(&prepared, seg_words, state, 0);
    }
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

    var cache_a = try CpuPreparedPages.init(allocator, pool_a);
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

test "drawCpu refuses replicated kind in this MVP" {
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;

    var pool = try @import("page_pool.zig").PagePool.init(allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool.deinit();
    var cache = try CpuPreparedPages.init(allocator, pool);
    defer cache.deinit();

    var pixels: [8 * 8 * 4]u8 = .{0} ** (8 * 8 * 4);
    var renderer = snail.CpuRenderer.init(&pixels, 8, 8, 8 * 4);
    const state = makeIdentityState(8, 8);

    const segments = [_]draw_records.DrawSegment{.{
        .kind = .replicated,
        .binding = .{ .pool = pool, .generation = 0 },
        .words_offset = 0,
        .words_len = 0,
        .shape_count = 0,
        .override_count = 1,
    }};
    const records = DrawRecords{ .words = &.{}, .segments = &segments };
    try testing.expectError(error.UnsupportedSegmentKind, drawCpu(&renderer, state, records, &.{&cache}));
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

    var cache = try CpuPreparedPages.init(allocator, pool);
    defer cache.deinit();
    const binding = try cache.upload(&atlas);

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

fn makeIdentityState(w: u32, h: u32) snail.DrawState {
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    return .{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{
            .fill_rule = .non_zero,
            .subpixel_order = .none,
            .coverage_transfer = .{ .exponent = 1.0 },
        },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
}
