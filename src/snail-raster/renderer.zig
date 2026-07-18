//! Software rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).
//!
//! Pixel parity vs GL/Vulkan: matches within 1 sRGB LSB on virtually every
//! pixel; near-tangent conic edges may diverge by a few LSB due to differing
//! float-op orderings between CPU code and the SPIR-V/GLSL pipeline.

const std = @import("std");
const snail = @import("snail");
const bezier = @import("snail").render.curve;
const band_tex = @import("snail").render.band_texture;
const render_abi = @import("snail").render.abi;
const text_hint_format = @import("snail").render.text_hint;
const autohint_record = @import("snail").render.autohint_record;
const autohint_warp = @import("snail").autohint.warp;
const autohint_policy = @import("snail").autohint.policy;
const vertex = @import("snail").render.vertex;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

/// Caller-owned transient fitted knots for one glyph draw.
pub const AutohintWarp = struct {
    x: []const autohint_warp.Knot,
    y: []const autohint_warp.Knot,
};
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const FillRule = snail.FillRule;
const SubpixelOrder = snail.SubpixelOrder;
const blend_mod = @import("blend.zig");
const color_mod = @import("color.zig");
const coverage_mod = @import("coverage.zig");
const geometry_mod = @import("geometry.zig");
const path_paint_mod = @import("path_paint.zig");
const resources_mod = @import("resources.zig");
const texture_mod = @import("texture.zig");

const SubpixelCoverage = coverage_mod.SubpixelCoverage;
const SubpixelCoveragePlan = coverage_mod.SubpixelCoveragePlan;
const HintedTextRecord = coverage_mod.HintedTextRecord;
const addColors = path_paint_mod.addColors;
const advanceLocalPixel = geometry_mod.advanceLocalPixel;
const compositeOver = path_paint_mod.compositeOver;
const compositeSubpixelOver = coverage_mod.compositeSubpixelOver;
const evalGlyphCoverage = coverage_mod.evalGlyphCoverage;
const evalGlyphCoverageBandSpan = coverage_mod.evalGlyphCoverageBandSpan;
const evalGlyphCoverageBandSpanRowH = coverage_mod.evalGlyphCoverageBandSpanRowH;
const evalGlyphCoverageRowH = coverage_mod.evalGlyphCoverageRowH;
const evalGlyphCoverageSaturatedRowH = coverage_mod.evalGlyphCoverageSaturatedRowH;
const evalGlyphCoverageSubpixel = coverage_mod.evalGlyphCoverageSubpixel;
const evalGlyphCoverageSubpixelRowH = coverage_mod.evalGlyphCoverageSubpixelRowH;
const evalHintedTextCoverageBandSpan = coverage_mod.evalHintedTextCoverageBandSpan;
const prepareRowHorizSpanState = coverage_mod.prepareRowHorizSpanState;
const prepareRowHorizState = coverage_mod.prepareRowHorizState;
const prepareSaturatedRowState = coverage_mod.prepareSaturatedRowState;
const RowHorizState = coverage_mod.RowHorizState;
const SaturatedRowState = coverage_mod.SaturatedRowState;
const expandBoundsForCoverageSupport = geometry_mod.expandBoundsForCoverageSupport;
const f16ToF32 = texture_mod.f16ToF32;
const fetchLayerInfoTexel = path_paint_mod.fetchLayerInfoTexel;
const glyphEdgePixelsPerPixel = geometry_mod.glyphEdgePixelsPerPixel;
const inverseTransform = geometry_mod.inverseTransform;
const LayerInfoEntry = path_paint_mod.LayerInfoEntry;
const max3 = color_mod.max3;
const multiplyLinearColor = color_mod.multiplyLinearColor;
const premultiplyCoverage = coverage_mod.premultiplyCoverage;
const premultiplySubpixelCoverage = coverage_mod.premultiplySubpixelCoverage;
const PreparedPathPaint = path_paint_mod.PreparedPathPaint;
const PreparedPathLayer = path_paint_mod.PreparedPathLayer;
const PreparedPathRecord = path_paint_mod.PreparedPathRecord;
const PreparedAtlasPage = resources_mod.PreparedAtlasPage;
const ScreenBounds = geometry_mod.ScreenBounds;
const srgbBytesToLinearColor = color_mod.srgbBytesToLinearColor;

fn expandDeviceBounds(bounds: *ScreenBounds, pixels: f32) void {
    bounds.min.x -= pixels;
    bounds.min.y -= pixels;
    bounds.max.x += pixels;
    bounds.max.y += pixels;
}
const srgbColorToLinear = color_mod.srgbColorToLinear;
const subpixelBlendCoverage = coverage_mod.subpixelBlendCoverage;
const transformedGlyphBounds = geometry_mod.transformedGlyphBounds;

pub const PreparedResources = resources_mod.PreparedResources;

// ── Per-instance profiling (diagnostic) ──
//
// When `instance_profile` is non-null, the SERIAL `drawBatchInstances`
// path times each instance individually and appends an entry. The
// threaded path (`drawBatchInstancesParallel` → `tileWorker`) skips the
// hook — per-instance timing in a tiled-parallel dispatch would be
// misleading (each strip processes every instance over a fraction of
// the surface, so per-strip-per-instance numbers don't compose into
// "how much did this instance cost"). Force the `cpu_unthreaded`
// backend to get a meaningful breakdown.

pub const InstanceProfileEntry = struct {
    /// Position in this drawBatch's vertex stream.
    index: u32,
    us: f64,
    /// Screen-space bbox extents after the scene-to-pixel transform,
    /// for distinguishing "this is a huge fill" from "this is a glyph".
    pixel_w: u32,
    pixel_h: u32,
};

pub const InstanceProfileBuf = struct {
    entries: []InstanceProfileEntry,
    count: usize = 0,

    pub fn reset(self: *InstanceProfileBuf) void {
        self.count = 0;
    }
};

/// CLOCK_MONOTONIC in nanoseconds. Used by the per-instance profiler
/// to time each `renderBatchInstance` call. Zig 0.16 dropped
/// `std.time.Instant`/`Timer`; this drops to `std.c.clock_gettime`
/// directly, same as the demo's wayland platform.
fn monotonicNanos() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

/// Skip threshold for coverage/alpha values below one 8-bit LSB: anything
/// smaller rounds to zero in the final sRGB8 output, so the composite would
/// be a no-op.
const one_lsb_8bit: f32 = 1.0 / 255.0;

pub const Renderer = struct {
    pixels: [*]u8, // RGBA8888 buffer, caller-owned
    width: u32,
    height: u32,
    stride: u32, // bytes per row (usually width * 4)
    subpixel_order: SubpixelOrder,
    /// Encoding of the caller-owned pixel buffer. The unified `Renderer.draw`
    /// path sets this from `DrawState.surface.encoding` every frame.
    target_encoding: snail.TargetEncoding,
    /// Byte layout of the caller's pixel buffer. Defaults to rgba8; the caller
    /// sets it (and a matching `stride` = width × bytesPerPixel) for other
    /// formats. The blend path comptime-specializes on it once per draw.
    format: snail.PixelFormat = .rgba8_unorm,
    target_resolve: blend_mod.ResolveMode,
    linear_resolve_active: bool,
    coverage_transfer: snail.CoverageTransfer,
    // Half-open row window [row_clip_min, row_clip_max). Pixel writes outside
    // this range are skipped. Used by tile workers to claim disjoint scanline
    // bands; defaults to the full image for single-threaded callers.
    row_clip_min: u32,
    row_clip_max: u32,
    col_clip_min: u32,
    col_clip_max: u32,
    /// Optional per-instance timing sink. Per-renderer (not a process global)
    /// so independent renderers on separate threads profile independently.
    /// Only the serial `drawBatchInstances` path records; wire a buffer in to
    /// start, clear to stop. The caller owns the buffer's storage/lifetime.
    instance_profile: ?*InstanceProfileBuf = null,

    pub const TILE_ROWS: u32 = 2;

    // Stack-allocated row-state array for composite paths. Most COLR / outline
    // groups have far fewer layers than this; spillover falls back to per-pixel
    // evaluation.
    const MAX_COMPOSITE_LAYERS: usize = 8;

    pub fn init(pixels: [*]u8, width: u32, height: u32, stride: u32) Renderer {
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
            .subpixel_order = .none,
            // CPU's pixel-buffer contract is sRGB bytes (cf. the file-level
            // doc). The unified `Renderer.draw` path overrides this from
            // `DrawState.surface.encoding` per frame.
            .target_encoding = .srgb,
            .target_resolve = .{ .direct = {} },
            .linear_resolve_active = false,
            .coverage_transfer = .identity,
            .row_clip_min = 0,
            .row_clip_max = height,
            .col_clip_min = 0,
            .col_clip_max = width,
        };
    }

    /// Update the pixel buffer and dimensions without clearing atlas state.
    pub fn reinitBuffer(self: *Renderer, pixels: [*]u8, width: u32, height: u32, stride: u32) void {
        self.pixels = pixels;
        self.width = width;
        self.height = height;
        self.stride = stride;
        self.row_clip_min = 0;
        self.row_clip_max = height;
        self.col_clip_min = 0;
        self.col_clip_max = width;
    }

    pub const LinearResolveRestore = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,
        target_encoding: snail.TargetEncoding,
        target_resolve: blend_mod.ResolveMode,
        linear_resolve_active: bool,
    };

    pub fn beginLinearResolve(self: *Renderer, surface: snail.TargetSurface, resolve: snail.LinearResolve) !LinearResolveRestore {
        if (!surface.supportsLinearResolve()) return error.UnsupportedResolve;
        if (self.linear_resolve_active) return error.LinearResolveAlreadyActive;
        const rect = snail.resolveRect(surface, resolve);
        if (rect.w == 0 or rect.h == 0) return error.InvalidTargetSurface;
        const restore = LinearResolveRestore{
            .row_clip_min = self.row_clip_min,
            .row_clip_max = self.row_clip_max,
            .col_clip_min = self.col_clip_min,
            .col_clip_max = self.col_clip_max,
            .target_encoding = self.target_encoding,
            .target_resolve = self.target_resolve,
            .linear_resolve_active = self.linear_resolve_active,
        };
        self.col_clip_min = @intCast(rect.x);
        self.row_clip_min = @intCast(rect.y);
        self.col_clip_max = self.col_clip_min + rect.w;
        self.row_clip_max = self.row_clip_min + rect.h;
        self.target_encoding = surface.encoding;
        self.target_resolve = .{ .linear = resolve };
        self.linear_resolve_active = true;
        self.seedLinearResolveBackdrop(surface.encoding, rect, resolve.backdrop);
        return restore;
    }

    pub fn endLinearResolve(self: *Renderer, restore: LinearResolveRestore) void {
        std.debug.assert(self.linear_resolve_active);
        self.row_clip_min = restore.row_clip_min;
        self.row_clip_max = restore.row_clip_max;
        self.col_clip_min = restore.col_clip_min;
        self.col_clip_max = restore.col_clip_max;
        self.target_encoding = restore.target_encoding;
        self.target_resolve = restore.target_resolve;
        self.linear_resolve_active = restore.linear_resolve_active;
    }

    fn seedLinearResolveBackdrop(self: *Renderer, encoding: snail.TargetEncoding, rect: snail.PixelRect, backdrop: snail.LinearResolve.Backdrop) void {
        switch (backdrop) {
            .target, .dont_care => return,
            .transparent => self.fillResolveRect(rect, .{ 0, 0, 0, 0 }),
            .clear => |color| self.fillResolveRect(rect, blend_mod.colorBytesForEncoding(encoding, color)),
        }
    }

    fn fillResolveRect(self: *Renderer, rect: snail.PixelRect, color: [4]u8) void {
        if (rect.w == 0 or rect.h == 0) return;
        var row: u32 = @intCast(rect.y);
        const y1 = row + rect.h;
        while (row < y1) : (row += 1) {
            var col: u32 = @intCast(rect.x);
            const x1 = col + rect.w;
            while (col < x1) : (col += 1) {
                const off = row * self.stride + col * 4;
                self.pixels[off + 0] = color[0];
                self.pixels[off + 1] = color[1];
                self.pixels[off + 2] = color[2];
                self.pixels[off + 3] = color[3];
            }
        }
    }

    inline fn applyCoverageTransfer(self: *const Renderer, cov: f32) f32 {
        const exponent = self.coverage_transfer.exponent;
        if (@abs(exponent - 1.0) <= 1.0e-6 or !std.math.isFinite(exponent)) return cov;
        return std.math.pow(f32, std.math.clamp(cov, 0.0, 1.0), @max(exponent, 1.0 / 65536.0));
    }

    fn applySubpixelCoverageTransfer(self: *const Renderer, cov: SubpixelCoverage) SubpixelCoverage {
        return .{
            .rgb = .{
                self.applyCoverageTransfer(cov.rgb[0]),
                self.applyCoverageTransfer(cov.rgb[1]),
                self.applyCoverageTransfer(cov.rgb[2]),
            },
            .alpha = self.applyCoverageTransfer(cov.alpha),
        };
    }

    fn clear(self: *Renderer, r: u8, g: u8, b: u8, a: u8) void {
        for (0..self.height) |row| {
            const row_start = row * self.stride;
            for (0..self.width) |col| {
                const off = row_start + col * 4;
                self.pixels[off + 0] = r;
                self.pixels[off + 1] = g;
                self.pixels[off + 2] = b;
                self.pixels[off + 3] = a;
            }
        }
    }

    pub fn drawBatch(self: *Renderer, prepared: *const PreparedResources, vertices: []const u32, state: snail.DrawState, texture_layer_base: u32, thread_pool: ?*ThreadPool) !void {
        // Drive the four fields the rendering helpers read off `self` from
        // `state`. There's no save/restore: each `drawBatch` overwrites
        // them from scratch, and `beginLinearResolve` owns `target_resolve`
        // for the duration of a linear-resolve pass (so we leave it alone
        // when one is active).
        self.subpixel_order = state.raster.subpixel_order;
        self.target_encoding = state.surface.encoding;
        if (!self.linear_resolve_active) self.target_resolve = .{ .direct = {} };
        self.coverage_transfer = state.raster.coverage_transfer;

        // Apply `state.scissor_rect` by intersecting with the current
        // clip window. Restore unconditionally — works inside or outside
        // a linear-resolve pass, since the resolve has already set the
        // outer clip to the resolve region. A non-overlapping scissor
        // collapses to a no-op (clip min == max), which the per-pixel
        // writes skip anyway, so an empty intersection is cheap.
        const clip_save = if (state.scissor_rect != null) ClipSave{
            .row_clip_min = self.row_clip_min,
            .row_clip_max = self.row_clip_max,
            .col_clip_min = self.col_clip_min,
            .col_clip_max = self.col_clip_max,
        } else null;
        defer if (clip_save) |s| s.restore(self);
        if (state.scissor_rect) |sr| {
            self.intersectClip(sr);
        }

        // The CPU rasterizer doesn't do per-pixel 1/w, so a non-affine MVP
        // would silently disagree with the GPU backends. Refuse — but as a
        // returned error, not a process abort: an embedder feeding matrices
        // from its own camera code shouldn't be able to crash the host.
        const scene = snail.mvpToScenePixel(state.mvp, state.surface.pixel_width, state.surface.pixel_height) orelse
            return error.NonAffineMvp;
        if (thread_pool) |pool| {
            if (pool.threadCount() > 0 and self.row_clip_max > self.row_clip_min + TILE_ROWS) {
                self.drawBatchInstancesParallel(pool, prepared, vertices, scene, texture_layer_base, true);
                return;
            }
        }
        // Serial path: enable the profile hook if the caller has wired
        // up `instance_profile`. The threaded path above skips it
        // intentionally — see `instance_profile` docs.
        self.drawBatchInstances(prepared, vertices, scene, texture_layer_base, true, true);
    }

    const ClipSave = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,

        fn restore(self: ClipSave, r: *Renderer) void {
            r.row_clip_min = self.row_clip_min;
            r.row_clip_max = self.row_clip_max;
            r.col_clip_min = self.col_clip_min;
            r.col_clip_max = self.col_clip_max;
        }
    };

    fn intersectClip(self: *Renderer, rect: snail.PixelRect) void {
        const cur = snail.PixelRect{
            .x = @intCast(self.col_clip_min),
            .y = @intCast(self.row_clip_min),
            .w = self.col_clip_max - self.col_clip_min,
            .h = self.row_clip_max - self.row_clip_min,
        };
        const sx0 = @max(@as(i64, rect.x), @as(i64, cur.x));
        const sy0 = @max(@as(i64, rect.y), @as(i64, cur.y));
        const sx1 = @min(@as(i64, rect.x) + @as(i64, rect.w), @as(i64, cur.x) + @as(i64, cur.w));
        const sy1 = @min(@as(i64, rect.y) + @as(i64, rect.h), @as(i64, cur.y) + @as(i64, cur.h));
        if (sx0 >= sx1 or sy0 >= sy1) {
            self.col_clip_min = self.col_clip_max;
            self.row_clip_min = self.row_clip_max;
            return;
        }
        self.col_clip_min = @intCast(sx0);
        self.row_clip_min = @intCast(sy0);
        self.col_clip_max = @intCast(sx1);
        self.row_clip_max = @intCast(sy1);
    }

    pub fn beginDraw(_: *Renderer) void {}

    pub fn backendName(_: *const Renderer) [:0]const u8 {
        return "CPU";
    }

    fn drawBatchInstances(self: *Renderer, prepared: *const PreparedResources, vertices: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool, profile_enabled: bool) void {
        const WORDS = vertex.WORDS_PER_INSTANCE;
        const profile = if (profile_enabled) self.instance_profile else null;
        var i: usize = 0;
        var idx: u32 = 0;
        while (i + WORDS <= vertices.len) : (i += WORDS) {
            const inst = vertices[i..][0..WORDS];
            if (profile) |p| {
                const start_ns = monotonicNanos();
                self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
                const end_ns = monotonicNanos();
                if (p.count < p.entries.len) {
                    const decoded = decodeBatchInstance(inst, scene_to_pixel);
                    var bounds = geometry_mod.transformedGlyphBounds(decoded.bbox, decoded.transform);
                    geometry_mod.expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);
                    const w_f = @max(0.0, bounds.max.x - bounds.min.x);
                    const h_f = @max(0.0, bounds.max.y - bounds.min.y);
                    p.entries[p.count] = .{
                        .index = idx,
                        .us = @as(f64, @floatFromInt(end_ns -% start_ns)) / 1000.0,
                        .pixel_w = @intFromFloat(@ceil(w_f)),
                        .pixel_h = @intFromFloat(@ceil(h_f)),
                    };
                    p.count += 1;
                }
            } else {
                self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
            }
            idx += 1;
        }
    }

    const TileCtx = struct {
        base: *const Renderer,
        prepared: *const PreparedResources,
        vertices: []const u32,
        scene_to_pixel: Transform2D,
        texture_layer_base: u32,
        allow_subpixel: bool,
        strip_rows: u32,
        y0: u32,
        y1: u32,
    };

    fn tileWorker(ctx_opaque: *anyopaque, idx: u32) void {
        const ctx: *const TileCtx = @ptrCast(@alignCast(ctx_opaque));
        const strip_y0 = ctx.y0 + idx * ctx.strip_rows;
        if (strip_y0 >= ctx.y1) return;
        const strip_y1 = @min(strip_y0 + ctx.strip_rows, ctx.y1);

        var worker = ctx.base.*;
        worker.row_clip_min = strip_y0;
        worker.row_clip_max = strip_y1;
        worker.drawBatchInstances(ctx.prepared, ctx.vertices, ctx.scene_to_pixel, ctx.texture_layer_base, ctx.allow_subpixel, false);
    }

    fn drawBatchInstancesParallel(
        self: *Renderer,
        pool: *ThreadPool,
        prepared: *const PreparedResources,
        vertices: []const u32,
        scene_to_pixel: Transform2D,
        texture_layer_base: u32,
        allow_subpixel: bool,
    ) void {
        // Tighten the dispatch range to the union pixel-Y bounds of the
        // actual instances. Without this we fan out one tile per
        // TILE_ROWS rows across the full row_clip range; a HUD-style
        // batch that only covers the top 100 rows would otherwise spawn
        // hundreds of empty tiles and let thread-pool barrier overhead
        // dominate the real rasterization.
        const dispatch_range = batchPixelRowRange(vertices, scene_to_pixel, self.subpixel_order, allow_subpixel);
        const y0 = @max(self.row_clip_min, dispatch_range.min);
        const y1 = @min(self.row_clip_max, dispatch_range.max);
        if (y1 <= y0) return;
        const rows = y1 - y0;
        const strip_count: u32 = (rows + TILE_ROWS - 1) / TILE_ROWS;
        var ctx = TileCtx{
            .base = self,
            .prepared = prepared,
            .vertices = vertices,
            .scene_to_pixel = scene_to_pixel,
            .texture_layer_base = texture_layer_base,
            .allow_subpixel = allow_subpixel,
            .strip_rows = TILE_ROWS,
            .y0 = y0,
            .y1 = y1,
        };
        pool.dispatch(strip_count, @ptrCast(&ctx), tileWorker);
    }

    /// Union of every instance's pixel-Y bounds, clamped to u32 row
    /// indices. Returns the full possible range on an empty batch so
    /// the caller's row_clip intersection short-circuits naturally.
    fn batchPixelRowRange(vertices: []const u32, scene_to_pixel: Transform2D, subpixel_order: SubpixelOrder, allow_subpixel: bool) struct { min: u32, max: u32 } {
        const WORDS = vertex.WORDS_PER_INSTANCE;
        if (vertices.len < WORDS) return .{ .min = 0, .max = 0 };

        var min_y: f32 = std.math.floatMax(f32);
        var max_y: f32 = -std.math.floatMax(f32);

        var i: usize = 0;
        while (i + WORDS <= vertices.len) : (i += WORDS) {
            const decoded = decodeBatchInstance(vertices[i..][0..WORDS], scene_to_pixel);
            var bounds = geometry_mod.transformedGlyphBounds(decoded.bbox, decoded.transform);
            geometry_mod.expandBoundsForCoverageSupport(&bounds, subpixel_order, allow_subpixel);
            if (decoded.isAutohint()) expandDeviceBounds(&bounds, 2.0);
            if (bounds.min.y < min_y) min_y = bounds.min.y;
            if (bounds.max.y > max_y) max_y = bounds.max.y;
        }

        if (min_y > max_y) return .{ .min = 0, .max = 0 };
        const lo: u32 = if (min_y <= 0) 0 else @intFromFloat(@floor(min_y));
        const hi_f = @ceil(max_y);
        const hi: u32 = if (hi_f <= 0) 0 else @intFromFloat(hi_f);
        return .{ .min = lo, .max = hi };
    }

    const BatchInstance = struct {
        bbox: bezier.BBox,
        transform: Transform2D,
        glyph: [2]u32,
        band: [4]f32,
        color: [4]f32,
        tint: [4]f32,
        policy: [7]u32,

        fn atlasLayerByte(self: BatchInstance) u8 {
            return render_abi.glyphWordAtlasLayer(self.glyph[1]);
        }

        fn isSpecialLayer(self: BatchInstance) bool {
            return render_abi.glyphWordIsSpecial(self.glyph[1]);
        }

        fn isAutohint(self: BatchInstance) bool {
            return self.isSpecialLayer() and render_abi.specialGlyphWordKind(self.glyph[1]) == .autohint;
        }
    };

    fn decodeBatchInstance(inst: []const u32, scene_to_pixel: Transform2D) BatchInstance {
        const encoded = vertex.instanceAt(inst, 0);
        const instance_transform = Transform2D{
            .xx = encoded.xform[0],
            .xy = encoded.xform[1],
            .yx = encoded.xform[2],
            .yy = encoded.xform[3],
            .tx = encoded.origin[0],
            .ty = encoded.origin[1],
        };
        return .{
            .bbox = .{
                .min = .{ .x = f16ToF32(encoded.rect[0]), .y = f16ToF32(encoded.rect[1]) },
                .max = .{ .x = f16ToF32(encoded.rect[2]), .y = f16ToF32(encoded.rect[3]) },
            },
            // GPU backends compose this with the MVP uniform in the vertex
            // shader. The CPU backend renders in pixel space directly.
            .transform = Transform2D.multiply(scene_to_pixel, instance_transform),
            .glyph = encoded.glyph,
            .band = encoded.band,
            .color = srgbBytesToLinearColor(encoded.color),
            .tint = srgbBytesToLinearColor(encoded.tint),
            .policy = encoded.policy,
        };
    }

    fn renderBatchInstance(self: *Renderer, prepared: *const PreparedResources, inst: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const decoded = decodeBatchInstance(inst, scene_to_pixel);
        if (decoded.isSpecialLayer()) {
            self.renderSpecialBatchInstance(prepared, decoded, texture_layer_base);
        } else {
            self.renderRegularBatchInstance(prepared, decoded, texture_layer_base, allow_subpixel);
        }
    }

    fn renderRegularBatchInstance(self: *Renderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32, allow_subpixel: bool) void {
        const gz = decoded.glyph[0];
        const gw = decoded.glyph[1];
        const be = GlyphBandEntry{
            .glyph_x = render_abi.glyphLocationX(gz),
            .glyph_y = render_abi.glyphLocationY(gz),
            .h_band_count = render_abi.regularGlyphWordHBandCount(gw),
            .v_band_count = render_abi.regularGlyphWordVBandCount(gw),
            .band_scale_x = decoded.band[0],
            .band_scale_y = decoded.band[1],
            .band_offset_x = decoded.band[2],
            .band_offset_y = decoded.band[3],
        };

        const atlas_layer = texture_layer_base + @as(u32, decoded.atlasLayerByte());
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        self.renderTransformedGlyph(page, decoded.bbox, be, decoded.transform, multiplyLinearColor(decoded.color, decoded.tint), allow_subpixel);
    }

    fn renderSpecialBatchInstance(self: *Renderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32) void {
        const gz = decoded.glyph[0];
        const gw = decoded.glyph[1];
        const layer_count = render_abi.specialGlyphWordLayerCount(gw);
        const info_x = render_abi.glyphLocationX(gz);
        const info_y = render_abi.glyphLocationY(gz);
        const atlas_layer = texture_layer_base + @as(u32, @intFromFloat(decoded.band[3]));

        const resolved = prepared.resolveLayerInfo(info_y) orelse return;
        const entry = resolved.entry;
        const special_kind = render_abi.specialGlyphWordKind(gw) orelse .colr;
        if (special_kind == .hinted_text) {
            self.renderHintedTextBatchInstance(prepared, decoded, atlas_layer, entry, info_x, resolved.local_y);
            return;
        }
        if (special_kind == .autohint) {
            self.renderAutohintBatchInstance(prepared, decoded, atlas_layer, entry, info_x, resolved.local_y);
            return;
        }

        const first_tag = fetchLayerInfoTexel(entry.data, entry.width, info_x, resolved.local_y, 0)[3];
        if (special_kind == .path and first_tag < 0.0) {
            const record = entry.pathRecordAt(info_x, resolved.local_y) orelse return;
            self.renderPathBatchLayers(prepared, decoded.bbox, decoded.transform, decoded.tint, atlas_layer, entry, record, false);
        } else if (special_kind == .colr) {
            self.renderColrBatchLayers(prepared, decoded.bbox, decoded.transform, decoded.color, decoded.tint, info_x, resolved.local_y, layer_count, atlas_layer, entry.data, entry.width);
        }
    }

    fn renderHintedTextBatchInstance(
        self: *Renderer,
        prepared: *const PreparedResources,
        decoded: BatchInstance,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        info_x: u16,
        info_y: u16,
    ) void {
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        const header = fetchLayerInfoTexel(entry.data, entry.width, info_x, info_y, 0);
        const band = fetchLayerInfoTexel(entry.data, entry.width, info_x, info_y, 1);
        const meta = fetchLayerInfoTexel(entry.data, entry.width, info_x, info_y, 2);
        const band_counts = render_abi.unpackBandCounts(@bitCast(header[2]));
        const band_pad = text_hint_format.unpackBandPadding(@intFromFloat(meta[3]));
        const be = GlyphBandEntry{
            .glyph_x = @intFromFloat(header[0]),
            .glyph_y = @intFromFloat(header[1]),
            .h_band_count = band_counts.h,
            .v_band_count = band_counts.v,
            .band_scale_x = band[0],
            .band_scale_y = band[1],
            .band_offset_x = band[2],
            .band_offset_y = band[3],
        };
        self.renderTransformedHintedGlyph(
            page,
            decoded.bbox,
            be,
            decoded.transform,
            multiplyLinearColor(decoded.color, decoded.tint),
            .{
                .data = entry.data,
                .width = entry.width,
                .info_x = info_x,
                .info_y = info_y,
                .base_curve_texel = @intFromFloat(meta[0]),
                .curve_count = @intFromFloat(meta[1]),
                .flags = @intFromFloat(meta[2]),
                .h_band_pad = band_pad.h,
                .v_band_pad = band_pad.v,
            },
        );
    }

    fn renderAutohintBatchInstance(
        self: *Renderer,
        prepared: *const PreparedResources,
        decoded: BatchInstance,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        info_x: u16,
        info_y: u16,
    ) void {
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        const off = (@as(usize, info_y) * entry.width + @as(usize, info_x)) * 4;
        if (off + autohint_record.header_floats >= entry.data.len) return;
        const rec = autohint_record.readBandEntry(entry.data, off);
        const be = GlyphBandEntry{
            .glyph_x = rec.glyph_x,
            .glyph_y = rec.glyph_y,
            .h_band_count = rec.h_band_count,
            .v_band_count = rec.v_band_count,
            .band_scale_x = rec.band_scale_x,
            .band_scale_y = rec.band_scale_y,
            .band_offset_x = rec.band_offset_x,
            .band_offset_y = rec.band_offset_y,
        };
        const policy = autohint_policy.AutohintPolicy.unpack(decoded.policy) catch return;
        self.renderTransformedAutohintGlyph(
            page,
            decoded.bbox,
            be,
            decoded.transform,
            multiplyLinearColor(decoded.color, decoded.tint),
            entry.data,
            off,
            policy,
        );
    }

    fn renderColrBatchLayers(
        self: *Renderer,
        prepared: *const PreparedResources,
        union_bbox: bezier.BBox,
        transform: Transform2D,
        default_color: [4]f32,
        tint: [4]f32,
        info_x: u16,
        info_y: u16,
        layer_count: u16,
        atlas_layer: u32,
        data: []const f32,
        width: u32,
    ) void {
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        for (0..layer_count) |layer_idx| {
            const base = @as(u32, info_x) + @as(u32, @intCast(layer_idx)) * 3;
            const t0_x = base % width;
            const t0_y = @as(u32, info_y) + base / width;

            // texel 0: (glyph_x, glyph_y, packed_bands, page_index)
            const t0 = (t0_y * width + t0_x) * 4;
            if (t0 + 3 >= data.len) return;
            const glyph_x: u16 = @intFromFloat(data[t0 + 0]);
            const glyph_y: u16 = @intFromFloat(data[t0 + 1]);
            const band_counts = render_abi.unpackBandCounts(@bitCast(data[t0 + 2]));

            // texel 1: (band_scale_x, band_scale_y, band_offset_x, band_offset_y)
            const t1_base = base + 1;
            const t1_x = t1_base % width;
            const t1_y = @as(u32, info_y) + t1_base / width;
            const t1 = (t1_y * width + t1_x) * 4;
            if (t1 + 3 >= data.len) return;

            // texel 2: (r, g, b, a) layer color
            const t2_base = base + 2;
            const t2_x = t2_base % width;
            const t2_y = @as(u32, info_y) + t2_base / width;
            const t2 = (t2_y * width + t2_x) * 4;
            if (t2 + 3 >= data.len) return;
            const layer_color = [4]f32{
                data[t2 + 0], data[t2 + 1], data[t2 + 2], data[t2 + 3],
            };
            // Negative sentinel means use default color.
            const color: [4]f32 = multiplyLinearColor(
                if (layer_color[0] < 0) default_color else srgbColorToLinear(layer_color),
                tint,
            );

            const be = GlyphBandEntry{
                .glyph_x = glyph_x,
                .glyph_y = glyph_y,
                .h_band_count = band_counts.h,
                .v_band_count = band_counts.v,
                .band_scale_x = data[t1 + 0],
                .band_scale_y = data[t1 + 1],
                .band_offset_x = data[t1 + 2],
                .band_offset_y = data[t1 + 3],
            };

            if (be.h_band_count == 0 or be.v_band_count == 0) continue;

            // Use the union bbox for all layers (same as GPU path).
            self.renderTransformedGlyph(page, union_bbox, be, transform, color, false);
        }
    }

    const PathRasterState = struct {
        inverse: Transform2D,
        x0: u32,
        x1: u32,
        y0: u32,
        y1: u32,
        epp: Vec2,
        ppe: Vec2,
        sample_dx: Vec2,
        subpixel_plan: SubpixelCoveragePlan,
        use_subpixel: bool,
    };

    const PathCompositePrograms = struct {
        outline: bool,
        fill: PreparedPathPaint = .{},
        stroke: PreparedPathPaint = .{},
    };

    const PathCompositeAccum = struct {
        result: [4]f32 = .{ 0, 0, 0, 0 },
        result_blend: [3]f32 = .{ 0, 0, 0 },
        fill_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 },
        stroke_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 },
        fill_paint: [4]f32 = .{ 0, 0, 0, 0 },
        stroke_paint: [4]f32 = .{ 0, 0, 0, 0 },
        fill_apply_dither: bool = false,
        stroke_apply_dither: bool = false,
        has_gradient: bool = false,
    };

    const PathCompositePixel = struct {
        color: [4]f32,
        blend: [3]f32,
        has_gradient: bool,
    };

    fn preparedAtlasPage(prepared: *const PreparedResources, atlas_layer: u32) ?*const PreparedAtlasPage {
        if (atlas_layer >= prepared.atlas_pages.len) return null;
        if (prepared.atlas_pages[atlas_layer]) |*page| return page;
        return null;
    }

    fn pathRasterState(self: *const Renderer, bbox: bezier.BBox, transform: Transform2D, allow_subpixel: bool) ?PathRasterState {
        const inverse = inverseTransform(transform) orelse return null;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
        if (px0 >= px1 or py0 >= py1) return null;

        const epp = glyphEdgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        const sample_dx = Vec2.new(inverse.xx, inverse.yx);
        const sample_dy = Vec2.new(inverse.xy, inverse.yy);
        return .{
            .inverse = inverse,
            .x0 = @intCast(px0),
            .x1 = @intCast(px1),
            .y0 = @intCast(py0),
            .y1 = @intCast(py1),
            .epp = epp,
            .ppe = ppe,
            .sample_dx = sample_dx,
            .subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order),
            .use_subpixel = allow_subpixel and self.subpixel_order != .none,
        };
    }

    fn recordCompositeSubpixelLayer(
        self: *Renderer,
        accum: *PathCompositeAccum,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        layer_index: usize,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_state: ?*const RowHorizState,
    ) void {
        const cov = if (row_state) |rs|
            self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixelRowH(
                page,
                local.x,
                local.y,
                rs,
                raster.subpixel_plan,
                layer.band_entry,
                layer.band_max_v,
                layer.fill_rule,
            ))
        else
            self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                page,
                local,
                raster.subpixel_plan,
                layer.band_entry,
                layer.band_max_h,
                layer.band_max_v,
                layer.fill_rule,
            ));

        if (programs.outline and layer_index < 2) {
            if (layer_index == 0) {
                accum.fill_cov = cov;
                if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                    const paint = programs.fill.sample(local);
                    accum.fill_paint = multiplyLinearColor(paint.color, tint);
                    accum.fill_apply_dither = paint.apply_dither;
                }
            } else {
                accum.stroke_cov = cov;
                if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                    const paint = programs.stroke.sample(local);
                    accum.stroke_paint = multiplyLinearColor(paint.color, tint);
                    accum.stroke_apply_dither = paint.apply_dither;
                }
            }
            return;
        }

        if (max3(cov.rgb) <= 0.0 and cov.alpha <= 0.0) return;
        var paint = layer.paint.sample(local);
        paint.color = multiplyLinearColor(paint.color, tint);
        if (paint.apply_dither and cov.alpha > 1e-6) accum.has_gradient = true;
        compositeSubpixelOver(
            premultiplySubpixelCoverage(paint.color, cov.rgb, cov.alpha),
            subpixelBlendCoverage(paint.color, cov.rgb),
            &accum.result,
            &accum.result_blend,
        );
    }

    fn scalarPathLayerCoverage(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        local: Vec2,
    ) f32 {
        return self.applyCoverageTransfer(evalGlyphCoverageBandSpan(
            page,
            local.x,
            local.y,
            raster.epp.x,
            raster.epp.y,
            raster.ppe.x,
            raster.ppe.y,
            layer.band_entry,
            layer.band_max_h,
            layer.band_max_v,
            layer.fill_rule,
        ));
    }

    fn recordCompositeScalarLayer(
        self: *Renderer,
        accum: *PathCompositeAccum,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        layer_index: usize,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_state: ?*const RowHorizState,
        sat_state: ?*const SaturatedRowState,
    ) void {
        const cov = if (row_state) |rs| blk: {
            if (sat_state) |ss| {
                break :blk self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                    page,
                    local.x,
                    local.y,
                    rs,
                    ss,
                    raster.epp.x,
                    raster.ppe.x,
                    raster.ppe.y,
                    layer.band_entry,
                    layer.band_max_h,
                    layer.band_max_v,
                    layer.fill_rule,
                ));
            }
            break :blk self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                page,
                local.x,
                local.y,
                rs,
                raster.epp.x,
                raster.ppe.x,
                raster.ppe.y,
                layer.band_entry,
                layer.band_max_h,
                layer.band_max_v,
                layer.fill_rule,
            ));
        } else self.scalarPathLayerCoverage(page, raster, layer, local);

        if (programs.outline and layer_index < 2) {
            const subpixel_cov: SubpixelCoverage = .{ .rgb = .{ cov, cov, cov }, .alpha = cov };
            if (layer_index == 0) {
                accum.fill_cov = subpixel_cov;
                if (cov > 0.0) {
                    const paint = programs.fill.sample(local);
                    accum.fill_paint = multiplyLinearColor(paint.color, tint);
                }
            } else {
                accum.stroke_cov = subpixel_cov;
                if (cov > 0.0) {
                    const paint = programs.stroke.sample(local);
                    accum.stroke_paint = multiplyLinearColor(paint.color, tint);
                }
            }
            return;
        }

        if (cov <= 0.0) return;
        var paint = layer.paint.sample(local);
        paint.color = multiplyLinearColor(paint.color, tint);
        accum.result = compositeOver(premultiplyCoverage(paint.color, cov), accum.result);
    }

    fn finishOutlineComposite(accum: *PathCompositeAccum, use_subpixel: bool) void {
        if (use_subpixel) {
            const border_cov = [3]f32{
                @min(accum.fill_cov.rgb[0], accum.stroke_cov.rgb[0]),
                @min(accum.fill_cov.rgb[1], accum.stroke_cov.rgb[1]),
                @min(accum.fill_cov.rgb[2], accum.stroke_cov.rgb[2]),
            };
            const interior_cov = [3]f32{
                @max(accum.fill_cov.rgb[0] - border_cov[0], 0.0),
                @max(accum.fill_cov.rgb[1] - border_cov[1], 0.0),
                @max(accum.fill_cov.rgb[2] - border_cov[2], 0.0),
            };
            const border_alpha = @min(accum.fill_cov.alpha, accum.stroke_cov.alpha);
            const interior_alpha = @max(accum.fill_cov.alpha - border_alpha, 0.0);
            if (accum.fill_apply_dither and interior_alpha > 1e-6) accum.has_gradient = true;
            if (accum.stroke_apply_dither and border_alpha > 1e-6) accum.has_gradient = true;
            const fill_blend = subpixelBlendCoverage(accum.fill_paint, interior_cov);
            const stroke_blend = subpixelBlendCoverage(accum.stroke_paint, border_cov);
            compositeSubpixelOver(
                addColors(
                    premultiplySubpixelCoverage(accum.fill_paint, interior_cov, interior_alpha),
                    premultiplySubpixelCoverage(accum.stroke_paint, border_cov, border_alpha),
                ),
                .{
                    fill_blend[0] + stroke_blend[0],
                    fill_blend[1] + stroke_blend[1],
                    fill_blend[2] + stroke_blend[2],
                },
                &accum.result,
                &accum.result_blend,
            );
        } else {
            const border_cov = @min(accum.fill_cov.alpha, accum.stroke_cov.alpha);
            const interior_cov = @max(accum.fill_cov.alpha - border_cov, 0.0);
            const combined = addColors(premultiplyCoverage(accum.fill_paint, interior_cov), premultiplyCoverage(accum.stroke_paint, border_cov));
            accum.result = compositeOver(combined, accum.result);
        }
    }

    fn sampleCompositePathPixel(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layers: []const PreparedPathLayer,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_states: ?[]const RowHorizState,
        sat_states: ?[]const SaturatedRowState,
    ) PathCompositePixel {
        var accum: PathCompositeAccum = .{};
        for (layers, 0..) |layer, layer_index| {
            const rs: ?*const RowHorizState = if (row_states) |states| &states[layer_index] else null;
            const ss: ?*const SaturatedRowState = if (sat_states) |states| &states[layer_index] else null;
            if (raster.use_subpixel) {
                self.recordCompositeSubpixelLayer(&accum, page, raster, layer, layer_index, programs, local, tint, rs);
            } else {
                self.recordCompositeScalarLayer(&accum, page, raster, layer, layer_index, programs, local, tint, rs, ss);
            }
        }
        if (programs.outline) finishOutlineComposite(&accum, raster.use_subpixel);
        return .{
            .color = accum.result,
            .blend = accum.result_blend,
            .has_gradient = accum.has_gradient,
        };
    }

    fn renderPathBatchLayers(
        self: *Renderer,
        prepared: *const PreparedResources,
        union_bbox: bezier.BBox,
        transform: Transform2D,
        tint: [4]f32,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        const page = preparedAtlasPage(prepared, atlas_layer) orelse return;

        if (record.tag == @intFromEnum(render_abi.PaintRecordKind.composite_group)) {
            self.renderCompositePathBatchLayers(page, union_bbox, transform, tint, entry, record, allow_subpixel);
        } else {
            self.renderSinglePathBatchLayer(page, union_bbox, transform, tint, entry, record, allow_subpixel);
        }
    }

    fn renderScalarInsideStrokeCompositePathBatchLayers(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        tint: [4]f32,
        fill_layer: PreparedPathLayer,
        stroke_layer: PreparedPathLayer,
        fill_program: PreparedPathPaint,
        stroke_program: PreparedPathPaint,
    ) void {
        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var fill_state: RowHorizState = undefined;
            var stroke_state: RowHorizState = undefined;
            const row_state_ready = axis_aligned and blk: {
                fill_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, fill_layer.band_entry, fill_layer.band_max_h);
                if (!fill_state.valid) break :blk false;
                stroke_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, stroke_layer.band_entry, stroke_layer.band_max_h);
                break :blk stroke_state.valid;
            };
            var fill_sat: SaturatedRowState = undefined;
            var stroke_sat: SaturatedRowState = undefined;
            const sat_state_ready = row_state_ready and blk: {
                fill_sat = prepareSaturatedRowState(page, local.y, raster.ppe.y, fill_layer.band_entry, fill_layer.band_max_v);
                if (!fill_sat.valid) break :blk false;
                stroke_sat = prepareSaturatedRowState(page, local.y, raster.ppe.y, stroke_layer.band_entry, stroke_layer.band_max_v);
                break :blk stroke_sat.valid;
            };

            // Inside-stroke composite fast path.
            //
            // For axis-aligned rounded-rect cards the body rows have a
            // predictable "stroke at edges, fill in middle" pattern:
            //   stroke_cov = 1   in [edge_left, edge_left + w)
            //   stroke_cov = 0   in the interior
            //   stroke_cov = 1   in [edge_right - w, edge_right)
            // With both fill_state and stroke_state h_uniform (their
            // H-band carries only vertical-line curves), the only X
            // transitions in coverage are at the path's left/right
            // extents — exactly the two stroke band edges. So a probe at
            // 8 evenly spaced columns can identify:
            //   * which probes sit in the interior (stroke = 0, fill = 1),
            //   * which probes sit in a stroke border (stroke = 1).
            // The range from the first interior probe to the last
            // interior probe is safe to fast-path with the fill paint;
            // the per-pixel loop handles the leftmost / rightmost stroke
            // borders (and the AA transition pixel) normally.
            //
            // Targets the six card body rows (each contributing ~20-80 ms
            // unthreaded at 4K). A 1-2 px stroke leaves 6/8 probes in the
            // interior, so the fast path covers ~75% of each row's pixels.
            // Gate on contribution counts (see the equivalent comment in
            // `renderSinglePathBatchLayer`). For an axis-aligned
            // rounded-rect card body row, the FILL has 2 contributing
            // curves (left + right verticals) and the STROKE has 4
            // (the four vertical edges of the inside-stroke band:
            // outer-left, inner-left, inner-right, outer-right). Glyph
            // / complex shape rows easily exceed both bounds, where the
            // probe-based pattern detection becomes unsafe.
            // The fill contrib bound (4) matches the relaxed bound in
            // `renderSinglePathBatchLayer` — a fractionally-positioned
            // axis-aligned rect can span two H-bands per pixel
            // footprint, doubling the contribution count even though
            // the underlying shape is still 2 vertical edges. The
            // stroke bound (8) is the same doubling applied to the
            // canonical 4-edge inside-stroke band. Glyph / complex
            // shape rows easily exceed both. The 8-probe pattern check
            // (all fills full + run_clean) still gates correctness.
            const fp_fill_contrib = if (row_state_ready) rowStateSignedContributionCount(fill_state) else 0;
            const fp_stroke_contrib = if (row_state_ready) rowStateSignedContributionCount(stroke_state) else 0;
            var fp_active = false;
            var fp_start: u32 = 0;
            var fp_end_excl: u32 = 0;
            no_fp: {
                if (!(row_state_ready and fp_fill_contrib <= 4 and fp_stroke_contrib <= 8 and raster.x1 > raster.x0 + 8)) break :no_fp;
                const ProbeFn = struct {
                    fn cov(
                        s_self: *Renderer,
                        p: *const PreparedAtlasPage,
                        loc: Vec2,
                        row_st: *const RowHorizState,
                        sat_st: *const SaturatedRowState,
                        r: PathRasterState,
                        layer: PreparedPathLayer,
                        sat_ready: bool,
                    ) f32 {
                        if (sat_ready) return s_self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                            p,
                            loc.x,
                            loc.y,
                            row_st,
                            sat_st,
                            r.epp.x,
                            r.ppe.x,
                            r.ppe.y,
                            layer.band_entry,
                            layer.band_max_h,
                            layer.band_max_v,
                            layer.fill_rule,
                        ));
                        return s_self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                            p,
                            loc.x,
                            loc.y,
                            row_st,
                            r.epp.x,
                            r.ppe.x,
                            r.ppe.y,
                            layer.band_entry,
                            layer.band_max_h,
                            layer.band_max_v,
                            layer.fill_rule,
                        ));
                    }
                };
                const n_probes: u32 = 8;
                var probe_col: [n_probes]u32 = undefined;
                var probe_loc: [n_probes]Vec2 = undefined;
                var probe_fill: [n_probes]f32 = undefined;
                var probe_stroke: [n_probes]f32 = undefined;
                // Inset probes by 2 pixels: at the bbox's first / last
                // pixel the fill itself has partial AA (rect's left /
                // right edge), so probing there fails `all_fills_full`
                // even on a clean axis-aligned card. The per-pixel loop
                // still handles those edge pixels correctly.
                const inset: u32 = 2;
                if (raster.x1 < raster.x0 + 2 * inset + n_probes) break :no_fp;
                const inset_start = raster.x0 + inset;
                const span = raster.x1 - raster.x0 - 1 - 2 * inset;
                inline for (0..n_probes) |i| {
                    const col_off: u32 = @intCast((@as(u64, span) * i) / (n_probes - 1));
                    probe_col[i] = inset_start + col_off;
                    probe_loc[i] = raster.inverse.applyPoint(.{
                        .x = @as(f32, @floatFromInt(probe_col[i])) + 0.5,
                        .y = @as(f32, @floatFromInt(row)) + 0.5,
                    });
                    probe_fill[i] = ProbeFn.cov(self, page, probe_loc[i], &fill_state, &fill_sat, raster, fill_layer, sat_state_ready);
                    probe_stroke[i] = ProbeFn.cov(self, page, probe_loc[i], &stroke_state, &stroke_sat, raster, stroke_layer, sat_state_ready);
                }
                const full_thresh: f32 = 1.0 - 1.0e-4;
                const empty_thresh: f32 = 1.0e-4;
                var all_fills_full = true;
                for (probe_fill) |f| {
                    if (f < full_thresh) {
                        all_fills_full = false;
                        break;
                    }
                }
                if (all_fills_full) {
                    // Find the first and last probes with stroke ~ 0.
                    var first_zero: ?u32 = null;
                    var last_zero: ?u32 = null;
                    for (probe_stroke, 0..) |s, i| {
                        if (s <= empty_thresh) {
                            if (first_zero == null) first_zero = @intCast(i);
                            last_zero = @intCast(i);
                        }
                    }
                    if (first_zero != null and last_zero != null and first_zero.? < last_zero.?) {
                        // Verify the run between first_zero and last_zero is
                        // all stroke≈0; if any probe in that interval has
                        // stroke>0, the pattern doesn't match the simple
                        // "stroke at edges" model and falling through to
                        // per-pixel is safer.
                        var run_clean = true;
                        var k: usize = first_zero.?;
                        while (k <= last_zero.?) : (k += 1) {
                            if (probe_stroke[k] > empty_thresh) {
                                run_clean = false;
                                break;
                            }
                        }
                        if (run_clean) {
                            fp_active = true;
                            fp_start = probe_col[first_zero.?];
                            fp_end_excl = probe_col[last_zero.?] + 1;
                        }
                    }
                }
            }

            // If a fast-path range was detected for this row, handle it
            // up front as a single batch (memset for solid+opaque, a
            // tight per-pixel blend loop for gradients/images). The
            // per-pixel loop below then `continue`s over those columns.
            if (fp_active) {
                const cov = self.applyCoverageTransfer(1.0);
                if (cov >= one_lsb_8bit) {
                    if (!self.tryFillRowSolidOpaque(row, fp_start, fp_end_excl, fill_program, tint)) {
                        var c: u32 = fp_start;
                        var local_at = raster.inverse.applyPoint(.{
                            .x = @as(f32, @floatFromInt(c)) + 0.5,
                            .y = @as(f32, @floatFromInt(row)) + 0.5,
                        });
                        while (c < fp_end_excl) : (advanceLocalPixel(&c, &local_at, raster.sample_dx)) {
                            const fill = fill_program.sample(local_at);
                            self.blendPremultipliedPixel(row, c, premultiplyCoverage(multiplyLinearColor(fill.color, tint), cov), false);
                        }
                    }
                }
            }

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                if (fp_active and col >= fp_start and col < fp_end_excl) continue;
                const fill_cov = if (sat_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                        page,
                        local.x,
                        local.y,
                        &fill_state,
                        &fill_sat,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        fill_layer.band_entry,
                        fill_layer.band_max_h,
                        fill_layer.band_max_v,
                        fill_layer.fill_rule,
                    ))
                else if (row_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                        page,
                        local.x,
                        local.y,
                        &fill_state,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        fill_layer.band_entry,
                        fill_layer.band_max_h,
                        fill_layer.band_max_v,
                        fill_layer.fill_rule,
                    ))
                else
                    self.scalarPathLayerCoverage(page, raster, fill_layer, local);
                if (fill_cov <= 0.0) continue;

                const stroke_cov = if (sat_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                        page,
                        local.x,
                        local.y,
                        &stroke_state,
                        &stroke_sat,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        stroke_layer.band_entry,
                        stroke_layer.band_max_h,
                        stroke_layer.band_max_v,
                        stroke_layer.fill_rule,
                    ))
                else if (row_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                        page,
                        local.x,
                        local.y,
                        &stroke_state,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        stroke_layer.band_entry,
                        stroke_layer.band_max_h,
                        stroke_layer.band_max_v,
                        stroke_layer.fill_rule,
                    ))
                else
                    self.scalarPathLayerCoverage(page, raster, stroke_layer, local);
                const border_cov = @min(fill_cov, stroke_cov);
                const interior_cov = @max(fill_cov - border_cov, 0.0);
                if (interior_cov <= 0.0 and border_cov <= 0.0) continue;

                var combined = [4]f32{ 0, 0, 0, 0 };
                if (interior_cov > 0.0) {
                    const fill = fill_program.sample(local);
                    combined = addColors(combined, premultiplyCoverage(multiplyLinearColor(fill.color, tint), interior_cov));
                }
                if (border_cov > 0.0) {
                    const stroke = stroke_program.sample(local);
                    combined = addColors(combined, premultiplyCoverage(multiplyLinearColor(stroke.color, tint), border_cov));
                }
                if (combined[3] < one_lsb_8bit) continue;
                self.blendPremultipliedPixel(row, col, combined, false);
            }
        }
    }

    fn renderCompositePathBatchLayers(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        union_bbox: bezier.BBox,
        transform: Transform2D,
        tint: [4]f32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        // Composite group: header at offset 0, then 6 texels per layer starting at offset 1.
        const layer_count = record.layer_count;
        const layers = entry.path_layers[record.layer_start..][0..layer_count];
        const raster = self.pathRasterState(union_bbox, transform, allow_subpixel) orelse return;
        const outline_composite = record.composite_mode == render_abi.composite_mode_fill_stroke_inside and layer_count >= 2;
        const programs = PathCompositePrograms{
            .outline = outline_composite,
            .fill = if (outline_composite) layers[0].paint else .{},
            .stroke = if (outline_composite) layers[1].paint else .{},
        };
        if (outline_composite and !raster.use_subpixel and layer_count == 2) {
            self.renderScalarInsideStrokeCompositePathBatchLayers(page, raster, tint, layers[0], layers[1], programs.fill, programs.stroke);
            return;
        }

        // For axis-aligned + RGB/BGR-subpixel-or-grayscale, pre-solve every
        // layer's H-axis curves once per row. Up to MAX_COMPOSITE_LAYERS is
        // bounded so the state array sits on the stack; rarely-exceeded.
        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;
        const subpixel_rgb = raster.use_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and raster.subpixel_plan.step.y == 0.0;
        const grayscale_path = !raster.use_subpixel;
        const can_row_batch = axis_aligned and (subpixel_rgb or grayscale_path) and layer_count <= MAX_COMPOSITE_LAYERS;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_states_storage: [MAX_COMPOSITE_LAYERS]RowHorizState = undefined;
            var row_states_ready: bool = false;
            if (can_row_batch) {
                row_states_ready = true;
                for (layers, 0..) |layer, i| {
                    row_states_storage[i] = if (subpixel_rgb)
                        prepareRowHorizState(page, local.y, layer.band_entry, layer.band_max_h)
                    else
                        prepareRowHorizSpanState(page, local.y, raster.epp.y, layer.band_entry, layer.band_max_h);
                    if (!row_states_storage[i].valid) {
                        row_states_ready = false;
                        break;
                    }
                }
            }
            const row_states: ?[]const RowHorizState = if (row_states_ready) row_states_storage[0..layer_count] else null;

            var sat_states_storage: [MAX_COMPOSITE_LAYERS]SaturatedRowState = undefined;
            var sat_states_ready: bool = false;
            if (row_states_ready and grayscale_path) {
                sat_states_ready = true;
                for (layers, 0..) |layer, i| {
                    sat_states_storage[i] = prepareSaturatedRowState(page, local.y, raster.ppe.y, layer.band_entry, layer.band_max_v);
                    if (!sat_states_storage[i].valid) {
                        sat_states_ready = false;
                        break;
                    }
                }
            }
            const sat_states: ?[]const SaturatedRowState = if (sat_states_ready) sat_states_storage[0..layer_count] else null;

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                const pixel = self.sampleCompositePathPixel(page, raster, layers, programs, local, tint, row_states, sat_states);
                if (pixel.color[3] < one_lsb_8bit) continue;
                if (raster.use_subpixel) {
                    self.blendSubpixelPremultipliedPixel(row, col, pixel.color, pixel.blend, pixel.has_gradient);
                } else {
                    self.blendPremultipliedPixel(row, col, pixel.color, false);
                }
            }
        }
    }

    fn renderSinglePathBatchLayer(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        union_bbox: bezier.BBox,
        transform: Transform2D,
        tint: [4]f32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        if (record.layer_count == 0) return;
        const layer = entry.path_layers[record.layer_start];
        const be = layer.band_entry;
        const raster = self.pathRasterState(union_bbox, transform, allow_subpixel) orelse return;
        const band_max_h = layer.band_max_h;
        const band_max_v = layer.band_max_v;
        const paint_program = layer.paint;

        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;
        const subpixel_rgb = raster.use_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and raster.subpixel_plan.step.y == 0.0;
        // Subpixel path uses single-band evalGlyphCoverageSubpixel internally,
        // so the existing single-band row state applies. Non-subpixel path
        // uses the band-span variant and needs the span-aware state.
        const use_row_h_subpixel = axis_aligned and subpixel_rgb;
        const use_row_h_span = axis_aligned and !raster.use_subpixel;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_state: RowHorizState = undefined;
            const row_state_ready = blk: {
                if (use_row_h_subpixel) {
                    row_state = prepareRowHorizState(page, local.y, be, band_max_h);
                    break :blk row_state.valid;
                } else if (use_row_h_span) {
                    row_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, be, band_max_h);
                    break :blk row_state.valid;
                }
                break :blk false;
            };
            var sat_state: SaturatedRowState = undefined;
            const sat_state_ready = use_row_h_span and row_state_ready and blk: {
                sat_state = prepareSaturatedRowState(page, local.y, raster.ppe.y, be, band_max_v);
                break :blk sat_state.valid;
            };

            // Row-uniformity fast path — same shape as the one in
            // `renderTransformedGlyphMaybeHinted`, see that comment for the
            // h_uniform/three-probe argument. Targets the banner background
            // fill (single-layer rect, ~30% of pass0 at 4K): interior rows
            // have only vertical-line H-band curves, all of which carry
            // zero signed contribution at any Y, so probing first/mid/last
            // is enough to confirm a fully-covered row and skip the
            // per-pixel coverage evaluation.
            // Gate on "≤ 2 H-band curves contribute signed coverage":
            // matches axis-aligned rect / rounded-rect interior rows
            // (their two vertical edges, opposite signs), excludes
            // glyph / curved-path rows (typically 5+ contributing
            // curves, where the 3-sample probe is unsafe — disjoint
            // strokes can land all three probes in solid sections while
            // skipping a hole between them). A naive
            // `rowStateHasNoSignedContribution` gate ("verticals don't
            // contribute") was inverted: vertical lines have a_root =
            // dy ≠ 0 so they DO produce signed crossings, which is
            // exactly what makes the rect's coverage well-defined.
            const fp_contrib = if (row_state_ready) rowStateSignedContributionCount(row_state) else 0;
            // Both gates required:
            //   state.count <= 3 excludes complex shapes (glyphs with
            //     6-30 curves per band, snail-illustration body rows
            //     with multiple disjoint inside regions);
            //   contributing <= 2 confirms the row has at most one
            //     "outside → inside" and one "inside → outside"
            //     transition along X — the rect/rounded-rect interior
            //     pattern the probes are designed for.
            // For axis-aligned rects at fractional scene-Y the band-span
            // walk and the `isBandSpanOwner` dedup still give
            // count == 2, so this gate covers both pan'd and stationary
            // rects.
            const fast_eligible = !raster.use_subpixel and row_state_ready and
                row_state.count <= 3 and fp_contrib <= 2;
            // Insert a 2-pixel safety margin: at the row's first / last
            // pixel the rect's vertical edge sits within the pixel
            // footprint, so AA gives partial coverage there. Probing one
            // pixel deeper guarantees deep-interior pixels for any
            // axis-aligned shape, while leaving the edge pixels for the
            // per-pixel loop to handle correctly.
            const inset: u32 = 2;
            var fp_start: u32 = raster.x1; // default: no fast-path range
            var fp_end_excl: u32 = raster.x1;
            if (fast_eligible and raster.x1 >= raster.x0 + 2 * inset + 2) {
                const probe_first: u32 = raster.x0 + inset;
                const probe_last: u32 = raster.x1 - 1 - inset;
                const probe_mid: u32 = probe_first + (probe_last - probe_first) / 2;
                const loc_pf = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_first)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_pm = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_mid)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_pl = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_last)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const probe = struct {
                    fn cov(
                        p: anytype,
                        loc: Vec2,
                        row_st: *const RowHorizState,
                        sat_st: *const SaturatedRowState,
                        r: PathRasterState,
                        b_e: GlyphBandEntry,
                        bmh: i32,
                        bmv: i32,
                        fill_rule: FillRule,
                        sat_ready: bool,
                        row_ready: bool,
                    ) f32 {
                        if (sat_ready) return evalGlyphCoverageSaturatedRowH(p, loc.x, loc.y, row_st, sat_st, r.epp.x, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                        if (row_ready) return evalGlyphCoverageBandSpanRowH(p, loc.x, loc.y, row_st, r.epp.x, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                        return evalGlyphCoverageBandSpan(p, loc.x, loc.y, r.epp.x, r.epp.y, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                    }
                }.cov;
                const cov_first = probe(page, loc_pf, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const cov_mid = probe(page, loc_pm, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const cov_last = probe(page, loc_pl, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const full_thresh: f32 = 1.0 - 1.0e-4;
                if (cov_first >= full_thresh and cov_mid >= full_thresh and cov_last >= full_thresh) {
                    const cov = self.applyCoverageTransfer(1.0);
                    if (cov >= one_lsb_8bit) {
                        fp_start = probe_first;
                        fp_end_excl = probe_last + 1;
                        if (self.tryFillRowSolidOpaque(row, fp_start, fp_end_excl, paint_program, tint)) {
                            // Fast-path-of-the-fast-path: solid + opaque +
                            // cov == 1 collapses the blend to a u32 memset.
                        } else {
                            var c: u32 = fp_start;
                            var local_at = loc_pf;
                            while (c < fp_end_excl) : (advanceLocalPixel(&c, &local_at, raster.sample_dx)) {
                                var paint = paint_program.sample(local_at);
                                paint.color = multiplyLinearColor(paint.color, tint);
                                self.blendPremultipliedPixel(row, c, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                            }
                        }
                    }
                }
            }

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                if (col >= fp_start and col < fp_end_excl) continue;
                if (!raster.use_subpixel) {
                    const raw_cov = if (sat_state_ready)
                        evalGlyphCoverageSaturatedRowH(page, local.x, local.y, &row_state, &sat_state, raster.epp.x, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule)
                    else if (row_state_ready)
                        evalGlyphCoverageBandSpanRowH(page, local.x, local.y, &row_state, raster.epp.x, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule)
                    else
                        evalGlyphCoverageBandSpan(page, local.x, local.y, raster.epp.x, raster.epp.y, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule);
                    const cov = self.applyCoverageTransfer(raw_cov);
                    if (cov < one_lsb_8bit) continue;
                    var paint = paint_program.sample(local);
                    paint.color = multiplyLinearColor(paint.color, tint);
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                } else {
                    const raw_cov = if (row_state_ready)
                        evalGlyphCoverageSubpixelRowH(page, local.x, local.y, &row_state, raster.subpixel_plan, be, band_max_v, layer.fill_rule)
                    else
                        evalGlyphCoverageSubpixel(page, local, raster.subpixel_plan, be, band_max_h, band_max_v, layer.fill_rule);
                    const cov = self.applySubpixelCoverageTransfer(raw_cov);
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    var paint = paint_program.sample(local);
                    paint.color = multiplyLinearColor(paint.color, tint);
                    self.blendSubpixelPremultipliedPixel(
                        row,
                        col,
                        premultiplySubpixelCoverage(paint.color, cov.rgb, cov.alpha),
                        subpixelBlendCoverage(paint.color, cov.rgb),
                        paint.apply_dither,
                    );
                }
            }
        }
    }

    fn renderTransformedGlyph(
        self: *Renderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, allow_subpixel, null, null);
    }

    fn renderTransformedHintedGlyph(
        self: *Renderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        record: HintedTextRecord,
    ) void {
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, false, record, null);
    }

    /// Fit the immutable analysis once for this draw, then render the shared
    /// base glyph through caller-owned transient knots. Grayscale only.
    fn renderTransformedAutohintGlyph(
        self: *Renderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        record_data: []const f32,
        record_off: usize,
        policy: autohint_policy.AutohintPolicy,
    ) void {
        const scale = Vec2.new(
            @sqrt(transform.xx * transform.xx + transform.yx * transform.yx),
            @sqrt(transform.xy * transform.xy + transform.yy * transform.yy),
        );
        var x_out: [autohint_warp.max_knots]autohint_warp.Knot = undefined;
        var y_out: [autohint_warp.max_knots]autohint_warp.Knot = undefined;
        const fitted = autohint_warp.fitGlyph(.{
            .x = autohint_record.xFeatures(record_data, record_off),
            .y = autohint_record.yFeatures(record_data, record_off),
            .left = autohint_record.glyphLeft(record_data, record_off),
        }, autohint_record.fontFeatures(record_data, record_off), policy, scale, &x_out, &y_out);
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, false, null, .{ .x = fitted.x, .y = fitted.y });
    }

    fn renderTransformedGlyphMaybeHinted(
        self: *Renderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
        hint_record: ?HintedTextRecord,
        warp: ?AutohintWarp,
    ) void {
        const inverse = inverseTransform(transform) orelse return;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);
        if (warp != null) expandDeviceBounds(&bounds, 2.0);

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
        if (px0 >= px1 or py0 >= py1) return;

        const epp = glyphEdgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;
        const sample_dx = Vec2.new(inverse.xx, inverse.yx);
        const sample_dy = Vec2.new(inverse.xy, inverse.yy);
        const subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order);

        // The row-batched H-axis fast path applies when (a) the transform is
        // axis-aligned (sample_dx.y == 0 so em_y is row-constant), (b) we're
        // in subpixel mode with RGB/BGR stripes (plan.step.y == 0 so all 7
        // subpixel samples in every pixel share em_y too), (c) the atlas
        // page is prepared, and (d) hinting is off (hinted text caches
        // shaped curves elsewhere). When any of those fails we fall back to
        // per-pixel evaluation.
        // Row-batched H-axis fast path. Applies when (a) the transform is
        // axis-aligned (sample_dx.y == 0 so em_y is row-constant), (b) the
        // atlas page is prepared, and (c) hinting is off (hinted text caches
        // shaped curves elsewhere). For RGB/BGR subpixel we additionally
        // require plan.step.y == 0 so all 7 subpixel samples share em_y too;
        // the non-subpixel path needs only the row-constant em_y. When any
        // condition fails we fall back to per-pixel evaluation.
        const PageType = switch (@typeInfo(@TypeOf(page))) {
            .pointer => |ptr| ptr.child,
            else => @TypeOf(page),
        };
        const prepared_page = comptime @hasField(PageType, "h_curves");
        const axis_aligned = @abs(sample_dx.y) < 1e-9;
        const subpixel_rgb = allow_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and subpixel_plan.step.y == 0.0;
        const grayscale_path = !allow_subpixel or self.subpixel_order == .none;
        const use_row_h_subpixel = prepared_page and axis_aligned and subpixel_rgb and hint_record == null and warp == null;
        const use_row_h_grayscale = prepared_page and axis_aligned and grayscale_path and hint_record == null and warp == null;
        const use_row_h = use_row_h_subpixel or use_row_h_grayscale;

        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            var display_local = inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_state: RowHorizState = undefined;
            const row_state_ready = use_row_h and blk: {
                row_state = prepareRowHorizState(page, display_local.y, be, band_max_h);
                break :blk row_state.valid;
            };

            // Row-uniformity fast path.
            //
            // Slug coverage = resolveCoverage(H, V). When every curve in
            // this row's H-band has zero signed contribution at this row
            // (vertical lines, or curves whose root-hull misses the row
            // entirely), the H half is constant across the row's X. Any
            // remaining per-pixel variation comes only from the V-band —
            // which for axis-aligned fills changes only at the path's
            // left/right extent. So three probes at the row's first /
            // middle / last pixel suffice:
            //
            //   * all ~1.0  → row's interior is fully covered. Fill with
            //                 the premultiplied color, skipping the
            //                 ~30 ns/px of curve solves the per-pixel
            //                 loop would otherwise spend.
            //   * all ~0.0  → row is entirely outside the path. Skip it.
            //   * mixed     → fall through to the per-pixel loop.
            //
            // The `h_uniform` gate is what makes three samples safe:
            // without it, a glyph with holes (O, P, R) could land all
            // three probes on "inside" pixels with the hole between them
            // staying uncovered. With the H-band carrying no per-X
            // variation, that ambiguity can't happen — any X-variation
            // in coverage comes from the V-band, which for the targets
            // of this fast path (big axis-aligned fills) has at most one
            // left→inside and one inside→right transition across the
            // row's X-extent.
            //
            // Targets the seven big offenders on the banner: background
            // fill + six card fills are axis-aligned rect / rounded-rect
            // paths whose interior rows have only vertical-line curves
            // in the H-band — those contribute nothing to row-level H.
            const h_uniform = row_state_ready and rowStateHasNoSignedContribution(row_state);
            const fast_row_eligible =
                grayscale_path and
                h_uniform and
                hint_record == null and
                warp == null and
                @as(u32, @intCast(px1)) > @as(u32, @intCast(px0)) + 2;
            if (fast_row_eligible) {
                const px_first: u32 = @intCast(px0);
                const px_last: u32 = @as(u32, @intCast(px1)) - 1;
                const px_mid: u32 = px_first + (px_last - px_first) / 2;
                const loc_first = display_local;
                const loc_mid = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(px_mid)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_last = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(px_last)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const cov_first = evalGlyphCoverageRowH(page, loc_first.x, loc_first.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                const cov_mid = evalGlyphCoverageRowH(page, loc_mid.x, loc_mid.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                const cov_last = evalGlyphCoverageRowH(page, loc_last.x, loc_last.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                // Only the all-full branch is safe under `h_uniform`
                // alone. An all-empty branch would mis-classify rows
                // whose three probes coincidentally land in
                // outside-stroke gaps (e.g. between the verticals of
                // "H" or "N") even though pixels between the probes
                // sit inside a stroke. The per-pixel loop's existing
                // `cov < one_lsb_8bit` check still skips empty pixels
                // individually, so dropping the row-skip costs nothing
                // beyond a missed micro-optimization.
                const full_thresh: f32 = 1.0 - 1.0e-4;
                if (cov_first >= full_thresh and cov_mid >= full_thresh and cov_last >= full_thresh) {
                    const cov = self.applyCoverageTransfer(1.0);
                    if (cov >= one_lsb_8bit) {
                        const premul = premultiplyCoverage(color, cov);
                        var c: u32 = px_first;
                        while (c <= px_last) : (c += 1) {
                            self.blendPremultipliedPixel(row, c, premul, false);
                        }
                    }
                    continue;
                }
            }

            while (col < @as(u32, @intCast(px1))) : (advanceLocalPixel(&col, &display_local, sample_dx)) {
                // Warp the sample coordinate back into base-outline space and
                // rescale the AA footprint by the local inverse slope (ppe_base
                // = ppe_screen / inv_slope). Identity when there's no warp.
                var sample = display_local;
                var sppe = ppe;
                if (warp) |w| {
                    const sx = autohint_warp.inverseWarp(w.x, display_local.x);
                    const sy = autohint_warp.inverseWarp(w.y, display_local.y);
                    sample = .{ .x = sx.base, .y = sy.base };
                    sppe = .{ .x = ppe.x / sx.inv_slope, .y = ppe.y / sy.inv_slope };
                }
                if (!allow_subpixel or self.subpixel_order == .none or warp != null) {
                    // Text/hinted glyphs from fonts use non-zero winding by convention.
                    const raw_cov = if (hint_record) |record|
                        evalHintedTextCoverageBandSpan(page, record, sample.x, sample.y, epp.x, epp.y, sppe.x, sppe.y, be, band_max_h, band_max_v, .non_zero)
                    else if (row_state_ready)
                        evalGlyphCoverageRowH(page, sample.x, sample.y, &row_state, sppe.x, sppe.y, be, band_max_h, band_max_v, .non_zero)
                    else
                        evalGlyphCoverage(page, sample.x, sample.y, sppe.x, sppe.y, be, band_max_h, band_max_v, .non_zero);
                    const cov = self.applyCoverageTransfer(raw_cov);
                    if (cov < one_lsb_8bit) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov), false);
                } else if (row_state_ready) {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixelRowH(
                        page,
                        display_local.x,
                        display_local.y,
                        &row_state,
                        subpixel_plan,
                        be,
                        band_max_v,
                        .non_zero,
                    ));
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                } else {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                        page,
                        display_local,
                        subpixel_plan,
                        be,
                        band_max_h,
                        band_max_v,
                        .non_zero,
                    ));
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                }
            }
        }
    }

    /// Helper for the row-uniformity fast paths: returns true when no
    /// curve in this row's H-band contributes signed X-axis coverage at
    /// the row's Y (e.g. all entries are vertical lines, or all curves
    /// in the band miss the row entirely). When true, per-pixel
    /// variation in the row's coverage can come only from the V-band,
    /// which for axis-aligned fills changes only at the path's left /
    /// right extents — so a small set of probes is enough to confirm
    /// uniformity. See `renderTransformedGlyphMaybeHinted` for the call
    /// site (the path-namespace renderers use the contribution-count
    /// helper below instead, since axis-aligned rects DO have signed
    /// vertical-edge contributions).
    inline fn rowStateHasNoSignedContribution(state: RowHorizState) bool {
        var c: usize = 0;
        while (c < state.count) : (c += 1) {
            const e = state.curves[c];
            if (e.sign[0] != 0.0 or e.sign[1] != 0.0 or e.sign[2] != 0.0) return false;
        }
        return true;
    }

    /// Helper for the path-namespace row-uniformity fast paths: counts
    /// curves in this row's H-band that contribute *any* signed X-axis
    /// crossing. An axis-aligned rect interior row has exactly 2 (its
    /// two vertical edges, sloping in opposite directions); a
    /// rounded-rect interior row between corners has the same; a corner
    /// row adds the corner curves; a glyph row easily has 5+ contributing
    /// curves. Gating on `count <= 2` lets through the axis-aligned
    /// rect / rounded-rect shapes the fast path targets while excluding
    /// the complex / glyph paths whose interior pixels can't be inferred
    /// from a small probe.
    inline fn rowStateSignedContributionCount(state: RowHorizState) usize {
        var n: usize = 0;
        var c: usize = 0;
        while (c < state.count) : (c += 1) {
            const e = state.curves[c];
            if (e.sign[0] != 0.0 or e.sign[1] != 0.0 or e.sign[2] != 0.0) n += 1;
        }
        return n;
    }

    /// Fill row pixels `[col_start, col_end_excl)` with `paint`'s solid
    /// color via `@memset`, IF the inputs collapse to "write the same
    /// 4 bytes everywhere":
    ///   * `paint.kind == .solid` (paint sample is constant across X)
    ///   * `linear_resolve_active == false` (the resolve pass writes
    ///     fp16, not u8 — the memset would corrupt it)
    ///   * the source after tint multiply has alpha ≈ 1 (opaque, so
    ///     blendPremultipliedPixel's fast path is just "write src")
    /// Returns true when the memset ran; false when the caller must
    /// fall back to per-pixel blending (gradient/image paints; partial
    /// alpha; linear-resolve mode).
    ///
    /// Targets the demo's banner background + card fills, which are
    /// the dominant cost in `pass0` even after the row-uniformity
    /// fast path skipped their coverage solves: each remaining pixel
    /// was still doing a linear→sRGB conversion + byte writes. This
    /// collapses the loop to a u32 memset — same shape as the
    /// framebuffer clear, which runs at memory bandwidth.
    fn tryFillRowSolidOpaque(
        self: *Renderer,
        row: u32,
        col_start: u32,
        col_end_excl: u32,
        paint: PreparedPathPaint,
        tint: [4]f32,
    ) bool {
        if (paint.kind != .solid) return false;
        if (self.linear_resolve_active) return false;
        const linear = multiplyLinearColor(paint.color0, tint);
        if (linear[3] < 1.0 - 1.0e-4) return false;
        switch (self.format) {
            inline else => |fmt| {
                // The u32 memset only applies to 4-byte formats (rgba8/bgra8/
                // rgb10a2, whose packed pixel is one word). Others fall back to
                // the per-pixel path.
                if (comptime fmt.bytesPerPixel() != 4) return false;
                const bytes = blend_mod.opaqueBytesForTarget(fmt, self.blendTarget(), .{ linear[0], linear[1], linear[2] });
                const word: u32 = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
                const offset = @as(usize, row) * self.stride + @as(usize, col_start) * 4;
                const dst_u32: [*]u32 = @ptrCast(@alignCast(self.pixels + offset));
                @memset(dst_u32[0..(col_end_excl - col_start)], word);
                return true;
            },
        }
    }

    inline fn blendTarget(self: *Renderer) blend_mod.Target {
        return .{
            .pixels = self.pixels,
            .stride = self.stride,
            .height = self.height,
            .target_encoding = self.target_encoding,
            .target_resolve = self.target_resolve,
        };
    }

    // The three pixel-write wrappers dispatch on the runtime format once here;
    // `inline else` gives each format a comptime-specialized (branch-free)
    // blend body. The format is constant per draw, so the branch predicts.
    inline fn blendPremultipliedPixel(self: *Renderer, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendPremultipliedPixel(fmt, self.blendTarget(), row, col, src, apply_dither),
        }
    }

    inline fn blendSubpixelPremultipliedPixel(self: *Renderer, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendSubpixelPremultipliedPixel(fmt, self.blendTarget(), row, col, src, src_blend, apply_dither),
        }
    }

    /// Per-channel subpixel blend (equivalent to GPU dual-source blending).
    /// Each RGB channel has its own coverage, so the destination attenuation
    /// is per-channel: out.r = src.r * alpha_r + dst.r * (1 - alpha_r), etc.
    inline fn blendSubpixelPixel(self: *Renderer, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendSubpixelPixel(fmt, self.blendTarget(), row, col, color, cov, alpha_cov),
        }
    }
};
