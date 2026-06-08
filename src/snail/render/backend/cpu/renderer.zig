//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).
//!
//! Pixel parity vs GL/Vulkan: matches within 1 sRGB LSB on virtually every
//! pixel; near-tangent conic edges may diverge by a few LSB due to differing
//! float-op orderings between CPU code and the SPIR-V/GLSL pipeline.

const std = @import("std");
const snail = @import("../../../root.zig");
const bezier = @import("../../../math/bezier.zig");
const curve_tex = @import("../../format/curve_texture.zig");
const band_tex = @import("../../format/band_texture.zig");
const render_abi = @import("../../format/abi.zig");
const text_hint_format = @import("../../format/text_hint.zig");
const vertex = @import("../../format/vertex.zig");
const CurveSegment = bezier.CurveSegment;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const FillRule = snail.FillRule;
const SubpixelOrder = snail.SubpixelOrder;
const cpu_blend = @import("blend.zig");
const cpu_color = @import("color.zig");
const cpu_coverage = @import("coverage.zig");
const cpu_geometry = @import("geometry.zig");
const cpu_path_paint = @import("path_paint.zig");
const cpu_resources = @import("resources.zig");
const cpu_texture = @import("texture.zig");

const SubpixelCoverage = cpu_coverage.SubpixelCoverage;
const SubpixelCoveragePlan = cpu_coverage.SubpixelCoveragePlan;
const HintedTextRecord = cpu_coverage.HintedTextRecord;
const addColors = cpu_path_paint.addColors;
const advanceLocalPixel = cpu_geometry.advanceLocalPixel;
const clamp01 = cpu_color.clamp01;
const compositeOver = cpu_path_paint.compositeOver;
const compositeSubpixelOver = cpu_coverage.compositeSubpixelOver;
const evalGlyphCoverage = cpu_coverage.evalGlyphCoverage;
const evalGlyphCoverageBandSpan = cpu_coverage.evalGlyphCoverageBandSpan;
const evalGlyphCoverageBandSpanRowH = cpu_coverage.evalGlyphCoverageBandSpanRowH;
const evalGlyphCoverageRowH = cpu_coverage.evalGlyphCoverageRowH;
const evalGlyphCoverageSaturatedRowH = cpu_coverage.evalGlyphCoverageSaturatedRowH;
const evalGlyphCoverageSubpixel = cpu_coverage.evalGlyphCoverageSubpixel;
const evalGlyphCoverageSubpixelRowH = cpu_coverage.evalGlyphCoverageSubpixelRowH;
const evalHintedTextCoverageBandSpan = cpu_coverage.evalHintedTextCoverageBandSpan;
const prepareRowHorizSpanState = cpu_coverage.prepareRowHorizSpanState;
const prepareRowHorizState = cpu_coverage.prepareRowHorizState;
const prepareSaturatedRowState = cpu_coverage.prepareSaturatedRowState;
const RowHorizState = cpu_coverage.RowHorizState;
const SaturatedRowState = cpu_coverage.SaturatedRowState;
const expandBoundsForCoverageSupport = cpu_geometry.expandBoundsForCoverageSupport;
const f16ToF32 = cpu_texture.f16ToF32;
const fetchLayerInfoTexel = cpu_path_paint.fetchLayerInfoTexel;
const glyphEdgePixelsPerPixel = cpu_geometry.glyphEdgePixelsPerPixel;
const inverseTransform = cpu_geometry.inverseTransform;
const LayerInfoEntry = cpu_path_paint.LayerInfoEntry;
const linearToSrgbByte = cpu_color.linearToSrgbByte;
const max3 = cpu_color.max3;
const multiplyLinearColor = cpu_color.multiplyLinearColor;
const premultiplyCoverage = cpu_coverage.premultiplyCoverage;
const premultiplySubpixelCoverage = cpu_coverage.premultiplySubpixelCoverage;
const PreparedPathPaint = cpu_path_paint.PreparedPathPaint;
const PreparedPathLayer = cpu_path_paint.PreparedPathLayer;
const PreparedPathRecord = cpu_path_paint.PreparedPathRecord;
const PreparedAtlasPage = cpu_resources.PreparedAtlasPage;
const samplePathPaint = cpu_path_paint.samplePathPaint;
const ScreenBounds = cpu_geometry.ScreenBounds;
const srgbBytesToLinearColor = cpu_color.srgbBytesToLinearColor;
const srgbColorToLinear = cpu_color.srgbColorToLinear;
const subpixelBlendCoverage = cpu_coverage.subpixelBlendCoverage;
const transformedGlyphBounds = cpu_geometry.transformedGlyphBounds;

pub const PreparedResources = cpu_resources.PreparedResources;

/// Skip threshold for coverage/alpha values below one 8-bit LSB: anything
/// smaller rounds to zero in the final sRGB8 output, so the composite would
/// be a no-op.
const one_lsb_8bit: f32 = 1.0 / 255.0;

pub const CpuRenderer = struct {
    pixels: [*]u8, // RGBA8888 buffer, caller-owned
    width: u32,
    height: u32,
    stride: u32, // bytes per row (usually width * 4)
    subpixel_order: SubpixelOrder,
    /// Encoding of the caller-owned pixel buffer. The unified `Renderer.draw`
    /// path sets this from `DrawState.surface.encoding` every frame.
    target_encoding: snail.TargetEncoding,
    target_resolve: cpu_blend.ResolveMode,
    linear_resolve_active: bool,
    coverage_transfer: snail.CoverageTransfer,
    thread_pool: ?*snail.ThreadPool,
    // Half-open row window [row_clip_min, row_clip_max). Pixel writes outside
    // this range are skipped. Used by tile workers to claim disjoint scanline
    // bands; defaults to the full image for single-threaded callers.
    row_clip_min: u32,
    row_clip_max: u32,
    col_clip_min: u32,
    col_clip_max: u32,

    pub const TILE_ROWS: u32 = 2;

    // Stack-allocated row-state array for composite paths. Most COLR / outline
    // groups have far fewer layers than this; spillover falls back to per-pixel
    // evaluation.
    const MAX_COMPOSITE_LAYERS: usize = 8;

    pub fn init(pixels: [*]u8, width: u32, height: u32, stride: u32) CpuRenderer {
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
            .thread_pool = null,
            .row_clip_min = 0,
            .row_clip_max = height,
            .col_clip_min = 0,
            .col_clip_max = width,
        };
    }

    /// Convenience initializer for callers that already own a thread pool.
    /// Does not allocate and does not take ownership of `pool`.
    pub fn initWithThreadPool(pixels: [*]u8, width: u32, height: u32, stride: u32, pool: ?*snail.ThreadPool) CpuRenderer {
        var renderer = init(pixels, width, height, stride);
        renderer.setThreadPool(pool);
        return renderer;
    }

    /// Update the pixel buffer and dimensions without clearing atlas state.
    pub fn reinitBuffer(self: *CpuRenderer, pixels: [*]u8, width: u32, height: u32, stride: u32) void {
        self.pixels = pixels;
        self.width = width;
        self.height = height;
        self.stride = stride;
        self.row_clip_min = 0;
        self.row_clip_max = height;
        self.col_clip_min = 0;
        self.col_clip_max = width;
    }

    /// Attach a caller-owned `snail.ThreadPool` to fan tile work out across
    /// scanline strips during draw. Pass `null` to revert to single-threaded
    /// rendering. Output is byte-identical to the single-threaded path; the
    /// draw path remains allocation-free (the pool's task slot lives in
    /// pre-allocated state). The pool must outlive the renderer.
    pub fn setThreadPool(self: *CpuRenderer, pool: ?*snail.ThreadPool) void {
        self.thread_pool = pool;
    }

    pub const LinearResolveRestore = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,
        target_encoding: snail.TargetEncoding,
        target_resolve: cpu_blend.ResolveMode,
        linear_resolve_active: bool,
    };

    pub fn beginLinearResolve(self: *CpuRenderer, surface: snail.TargetSurface, resolve: snail.LinearResolve) !LinearResolveRestore {
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

    pub fn endLinearResolve(self: *CpuRenderer, restore: LinearResolveRestore) void {
        std.debug.assert(self.linear_resolve_active);
        self.row_clip_min = restore.row_clip_min;
        self.row_clip_max = restore.row_clip_max;
        self.col_clip_min = restore.col_clip_min;
        self.col_clip_max = restore.col_clip_max;
        self.target_encoding = restore.target_encoding;
        self.target_resolve = restore.target_resolve;
        self.linear_resolve_active = restore.linear_resolve_active;
    }

    fn seedLinearResolveBackdrop(self: *CpuRenderer, encoding: snail.TargetEncoding, rect: snail.PixelRect, backdrop: snail.ResolveBackdrop) void {
        switch (backdrop) {
            .target, .dont_care => return,
            .transparent => self.fillResolveRect(rect, .{ 0, 0, 0, 0 }),
            .clear => |color| self.fillResolveRect(rect, cpu_blend.colorBytesForEncoding(encoding, color)),
        }
    }

    fn fillResolveRect(self: *CpuRenderer, rect: snail.PixelRect, color: [4]u8) void {
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

    inline fn applyCoverageTransfer(self: *const CpuRenderer, cov: f32) f32 {
        const exponent = self.coverage_transfer.exponent;
        if (@abs(exponent - 1.0) <= 1.0e-6 or !std.math.isFinite(exponent)) return cov;
        return std.math.pow(f32, std.math.clamp(cov, 0.0, 1.0), @max(exponent, 1.0 / 65536.0));
    }

    fn applySubpixelCoverageTransfer(self: *const CpuRenderer, cov: SubpixelCoverage) SubpixelCoverage {
        return .{
            .rgb = .{
                self.applyCoverageTransfer(cov.rgb[0]),
                self.applyCoverageTransfer(cov.rgb[1]),
                self.applyCoverageTransfer(cov.rgb[2]),
            },
            .alpha = self.applyCoverageTransfer(cov.alpha),
        };
    }

    fn setSubpixel(self: *CpuRenderer, enabled: bool) void {
        self.subpixel_order = if (enabled) .rgb else .none;
    }

    fn clear(self: *CpuRenderer, r: u8, g: u8, b: u8, a: u8) void {
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

    fn fillRect(self: *CpuRenderer, x: i32, y: i32, w: u32, h: u32, r: u8, g: u8, b: u8, a: u8) void {
        const x0 = @max(x, 0);
        const y0 = @max(y, 0);
        const x1: i32 = @min(x + @as(i32, @intCast(w)), @as(i32, @intCast(self.width)));
        const y1: i32 = @min(y + @as(i32, @intCast(h)), @as(i32, @intCast(self.height)));
        if (x0 >= x1 or y0 >= y1) return;

        var row: u32 = @intCast(y0);
        while (row < @as(u32, @intCast(y1))) : (row += 1) {
            var col: u32 = @intCast(x0);
            while (col < @as(u32, @intCast(x1))) : (col += 1) {
                const off = row * self.stride + col * 4;
                self.pixels[off + 0] = r;
                self.pixels[off + 1] = g;
                self.pixels[off + 2] = b;
                self.pixels[off + 3] = a;
            }
        }
    }

    pub fn drawBatch(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, state: snail.DrawState, texture_layer_base: u32) !void {
        // Drive the four fields the rendering helpers read off `self` from
        // `state`. There's no save/restore: each `drawBatch` overwrites
        // them from scratch, and `beginLinearResolve` owns `target_resolve`
        // for the duration of a linear-resolve pass (so we leave it alone
        // when one is active).
        self.subpixel_order = state.raster.subpixel_order;
        self.target_encoding = state.surface.encoding;
        if (!self.linear_resolve_active) self.target_resolve = .{ .direct = {} };
        self.coverage_transfer = state.raster.coverage_transfer;

        // The CPU rasterizer doesn't do per-pixel 1/w, so a non-affine MVP
        // would silently disagree with the GPU backends. Refuse loudly.
        const scene = snail.mvpToScenePixel(state.mvp, state.surface.pixel_width, state.surface.pixel_height) orelse
            std.debug.panic("CpuRenderer: MVP is non-affine (perspective) or degenerate", .{});
        if (self.thread_pool) |pool| {
            if (pool.threadCount() > 0 and self.row_clip_max > self.row_clip_min + TILE_ROWS) {
                self.drawBatchInstancesParallel(pool, prepared, vertices, scene, texture_layer_base, true);
                return;
            }
        }
        self.drawBatchInstances(prepared, vertices, scene, texture_layer_base, true);
    }

    pub fn beginDraw(_: *CpuRenderer) void {}

    pub fn backendName(_: *const CpuRenderer) [:0]const u8 {
        return "CPU";
    }

    fn drawBatchInstances(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const WORDS = vertex.WORDS_PER_INSTANCE;
        var i: usize = 0;
        while (i + WORDS <= vertices.len) : (i += WORDS) {
            const inst = vertices[i..][0..WORDS];
            self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
        }
    }

    const TileCtx = struct {
        base: *const CpuRenderer,
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
        worker.thread_pool = null;
        worker.drawBatchInstances(ctx.prepared, ctx.vertices, ctx.scene_to_pixel, ctx.texture_layer_base, ctx.allow_subpixel);
    }

    fn drawBatchInstancesParallel(
        self: *CpuRenderer,
        pool: *snail.ThreadPool,
        prepared: *const PreparedResources,
        vertices: []const u32,
        scene_to_pixel: Transform2D,
        texture_layer_base: u32,
        allow_subpixel: bool,
    ) void {
        const y0 = self.row_clip_min;
        const y1 = self.row_clip_max;
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

    const BatchInstance = struct {
        bbox: bezier.BBox,
        transform: Transform2D,
        glyph: [2]u32,
        band: [4]f32,
        color: [4]f32,
        tint: [4]f32,

        fn atlasLayerByte(self: BatchInstance) u8 {
            return render_abi.glyphWordAtlasLayer(self.glyph[1]);
        }

        fn isSpecialLayer(self: BatchInstance) bool {
            return render_abi.glyphWordIsSpecial(self.glyph[1]);
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
        };
    }

    fn renderBatchInstance(self: *CpuRenderer, prepared: *const PreparedResources, inst: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const decoded = decodeBatchInstance(inst, scene_to_pixel);
        if (decoded.isSpecialLayer()) {
            self.renderSpecialBatchInstance(prepared, decoded, texture_layer_base);
        } else {
            self.renderRegularBatchInstance(prepared, decoded, texture_layer_base, allow_subpixel);
        }
    }

    fn renderRegularBatchInstance(self: *CpuRenderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32, allow_subpixel: bool) void {
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

    fn renderSpecialBatchInstance(self: *CpuRenderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32) void {
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

        const first_tag = fetchLayerInfoTexel(entry.data, entry.width, info_x, resolved.local_y, 0)[3];
        if (special_kind == .path and first_tag < 0.0) {
            const record = entry.pathRecordAt(info_x, resolved.local_y) orelse return;
            self.renderPathBatchLayers(prepared, decoded.bbox, decoded.transform, decoded.tint, atlas_layer, entry, record, false);
        } else if (special_kind == .colr) {
            self.renderColrBatchLayers(prepared, decoded.bbox, decoded.transform, decoded.color, decoded.tint, info_x, resolved.local_y, layer_count, atlas_layer, entry.data, entry.width);
        }
    }

    fn renderHintedTextBatchInstance(
        self: *CpuRenderer,
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

    fn renderColrBatchLayers(
        self: *CpuRenderer,
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

    fn pathRasterState(self: *const CpuRenderer, bbox: bezier.BBox, transform: Transform2D, allow_subpixel: bool) ?PathRasterState {
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
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
        self: *CpuRenderer,
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
        self: *CpuRenderer,
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

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
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
        self: *CpuRenderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, allow_subpixel, null);
    }

    fn renderTransformedHintedGlyph(
        self: *CpuRenderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        record: HintedTextRecord,
    ) void {
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, false, record);
    }

    fn renderTransformedGlyphMaybeHinted(
        self: *CpuRenderer,
        page: anytype,
        bbox: bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
        hint_record: ?HintedTextRecord,
    ) void {
        const inverse = inverseTransform(transform) orelse return;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);

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
        const use_row_h_subpixel = prepared_page and axis_aligned and subpixel_rgb and hint_record == null;
        const use_row_h_grayscale = prepared_page and axis_aligned and grayscale_path and hint_record == null;
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

            while (col < @as(u32, @intCast(px1))) : (advanceLocalPixel(&col, &display_local, sample_dx)) {
                if (!allow_subpixel or self.subpixel_order == .none) {
                    // Text/hinted glyphs from fonts use non-zero winding by convention.
                    const raw_cov = if (hint_record) |record|
                        evalHintedTextCoverageBandSpan(page, record, display_local.x, display_local.y, epp.x, epp.y, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero)
                    else if (row_state_ready)
                        evalGlyphCoverageRowH(page, display_local.x, display_local.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero)
                    else
                        evalGlyphCoverage(page, display_local.x, display_local.y, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
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

    inline fn blendTarget(self: *CpuRenderer) cpu_blend.Target {
        return .{
            .pixels = self.pixels,
            .stride = self.stride,
            .height = self.height,
            .target_encoding = self.target_encoding,
            .target_resolve = self.target_resolve,
        };
    }

    inline fn blendPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
        cpu_blend.blendPremultipliedPixel(self.blendTarget(), row, col, src, apply_dither);
    }

    inline fn blendSubpixelPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
        cpu_blend.blendSubpixelPremultipliedPixel(self.blendTarget(), row, col, src, src_blend, apply_dither);
    }

    /// Per-channel subpixel blend (equivalent to GPU dual-source blending).
    /// Each RGB channel has its own coverage, so the destination attenuation
    /// is per-channel: out.r = src.r * alpha_r + dst.r * (1 - alpha_r), etc.
    inline fn blendSubpixelPixel(self: *CpuRenderer, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
        cpu_blend.blendSubpixelPixel(self.blendTarget(), row, col, color, cov, alpha_cov);
    }
};

