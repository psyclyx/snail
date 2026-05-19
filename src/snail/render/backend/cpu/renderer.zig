//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).
//!
//! Pixel parity vs GL/Vulkan: matches within 1 sRGB LSB on virtually every
//! pixel; near-tangent conic edges may diverge by a few LSB due to differing
//! float-op orderings between CPU code and the SPIR-V/GLSL pipeline.

const std = @import("std");
const builtin = @import("builtin");
const snail = @import("../../../root.zig");
const draw_mod = @import("../../../draw.zig");
const cpu_adapter = @import("../../adapter/cpu.zig");
const bezier = @import("../../../math/bezier.zig");
const curve_tex = @import("../../format/curve_texture.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const render_abi = @import("../../format/abi.zig");
const vertex = @import("../../format/vertex.zig");
const CurveSegment = bezier.CurveSegment;
const CurveAtlas = atlas_curve_mod.CurveAtlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const GlyphBandEntry = std.meta.fieldInfo(CurveAtlas.GlyphInfo, .band_entry).type;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const DrawRecords = draw_mod.DrawRecords;
const FillRule = snail.FillRule;
const SubpixelOrder = snail.SubpixelOrder;
const cpu_blend = @import("blend.zig");
const cpu_color = @import("color.zig");
const cpu_coverage = @import("coverage.zig");
const cpu_geometry = @import("geometry.zig");
const cpu_path_paint = @import("path_paint.zig");
const cpu_resources = @import("resources.zig");
const cpu_texture = @import("texture.zig");
const cpu_tile_frame = @import("tile_frame.zig");

const SubpixelCoverage = cpu_coverage.SubpixelCoverage;
const SubpixelCoveragePlan = cpu_coverage.SubpixelCoveragePlan;
const addColors = cpu_path_paint.addColors;
const advanceLocalPixel = cpu_geometry.advanceLocalPixel;
const clamp01 = cpu_color.clamp01;
const compositeOver = cpu_path_paint.compositeOver;
const compositeSubpixelOver = cpu_coverage.compositeSubpixelOver;
const evalGlyphCoverage = cpu_coverage.evalGlyphCoverage;
const evalGlyphCoverageBandSpan = cpu_coverage.evalGlyphCoverageBandSpan;
const evalGlyphCoverageSubpixel = cpu_coverage.evalGlyphCoverageSubpixel;
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
const sceneToPixelFromMvp = cpu_geometry.sceneToPixelFromMvp;
const ScreenBounds = cpu_geometry.ScreenBounds;
const srgbBytesToLinearColor = cpu_color.srgbBytesToLinearColor;
const srgbColorToLinear = cpu_color.srgbColorToLinear;
const subpixelBlendCoverage = cpu_coverage.subpixelBlendCoverage;
const transformedGlyphBounds = cpu_geometry.transformedGlyphBounds;

pub const PreparedResources = cpu_resources.PreparedResources;

pub const CpuRenderer = struct {
    pixels: [*]u8, // RGBA8888 buffer, caller-owned
    width: u32,
    height: u32,
    stride: u32, // bytes per row (usually width * 4)
    fill_rule: FillRule,
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

    pub const TILE_ROWS: u32 = 32;

    pub fn init(pixels: [*]u8, width: u32, height: u32, stride: u32) CpuRenderer {
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
            .fill_rule = .non_zero,
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

    fn drawPathPicture(self: *CpuRenderer, picture: *const snail.PathPicture) void {
        self.drawPathPictureTransformed(picture, .identity);
    }

    fn drawPathPictureTransformed(self: *CpuRenderer, picture: *const snail.PathPicture, transform: Transform2D) void {
        for (picture.shapes) |shape| {
            const info = picture.atlas.getGlyph(shape.glyph_id) orelse continue;
            const final_transform = Transform2D.multiply(transform, shape.transform);
            const inverse = inverseTransform(final_transform) orelse continue;
            var bounds = transformedGlyphBounds(info.bbox, final_transform);
            expandBoundsForCoverageSupport(&bounds, self.subpixel_order, false);
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
            if (px0 >= px1 or py0 >= py1) continue;

            const epp = glyphEdgePixelsPerPixel(inverse);
            const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
            const band_max_h: i32 = @as(i32, @intCast(info.band_entry.h_band_count)) - 1;
            const band_max_v: i32 = @as(i32, @intCast(info.band_entry.v_band_count)) - 1;
            const page = picture.atlas.page(info.page_index);

            var row: u32 = @intCast(py0);
            while (row < @as(u32, @intCast(py1))) : (row += 1) {
                var col: u32 = @intCast(px0);
                while (col < @as(u32, @intCast(px1))) : (col += 1) {
                    const world = Vec2.new(@as(f32, @floatFromInt(col)) + 0.5, @as(f32, @floatFromInt(row)) + 0.5);
                    const local = inverse.applyPoint(world);
                    const paint = samplePathPaint(&picture.atlas, shape, shape.glyph_id, local);
                    const cov = self.applyCoverageTransfer(evalGlyphCoverageBandSpan(
                        page,
                        local.x,
                        local.y,
                        epp.x,
                        epp.y,
                        ppe.x,
                        ppe.y,
                        info.band_entry,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                    ));
                    if (cov < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                }
            }
        }
    }

    const DrawStateRestore = struct {
        fill_rule: FillRule,
        subpixel_order: SubpixelOrder,
        target_encoding: snail.TargetEncoding,
        target_resolve: cpu_blend.ResolveMode,
        coverage_transfer: snail.CoverageTransfer,
    };

    fn applyDrawState(self: *CpuRenderer, state: snail.DrawState) DrawStateRestore {
        const restore = DrawStateRestore{
            .fill_rule = self.fill_rule,
            .subpixel_order = self.subpixel_order,
            .target_encoding = self.target_encoding,
            .coverage_transfer = self.coverage_transfer,
            .target_resolve = self.target_resolve,
        };
        self.fill_rule = state.raster.fill_rule;
        self.subpixel_order = state.raster.subpixel_order;
        self.target_encoding = state.surface.encoding;
        if (!self.linear_resolve_active) self.target_resolve = .{ .direct = {} };
        self.coverage_transfer = state.raster.coverage_transfer;
        return restore;
    }

    fn restoreDrawState(self: *CpuRenderer, restore: DrawStateRestore) void {
        self.fill_rule = restore.fill_rule;
        self.subpixel_order = restore.subpixel_order;
        self.target_encoding = restore.target_encoding;
        self.target_resolve = restore.target_resolve;
        self.coverage_transfer = restore.coverage_transfer;
    }

    pub fn drawTextPrepared(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, state: snail.DrawState, texture_layer_base: u32) !void {
        const restore = self.applyDrawState(state);
        defer self.restoreDrawState(restore);
        const scene = sceneToPixelFromMvp(state.mvp, state.surface.pixel_width, state.surface.pixel_height);
        self.drawTextBatchPrepared(prepared, vertices, scene, texture_layer_base, true);
    }

    pub fn drawPathsPrepared(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, state: snail.DrawState, texture_layer_base: u32) !void {
        const restore = self.applyDrawState(state);
        defer self.restoreDrawState(restore);
        const scene = sceneToPixelFromMvp(state.mvp, state.surface.pixel_width, state.surface.pixel_height);
        self.drawTextBatchPrepared(prepared, vertices, scene, texture_layer_base, false);
    }

    pub fn beginDraw(_: *CpuRenderer) void {}

    pub fn backendName(_: *const CpuRenderer) [:0]const u8 {
        return "CPU";
    }

    pub fn asRenderer(self: *CpuRenderer) snail.Renderer {
        return cpu_adapter.borrow(self);
    }

    pub fn uploadResourcesBlocking(self: *CpuRenderer, allocators: snail.UploadAllocators, set: *const snail.ResourceManifest) !snail.PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn draw(self: *CpuRenderer, prepared: *const snail.PreparedResources, list: *const snail.DrawList, state: snail.DrawState) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, list, state);
    }

    pub fn drawPrepared(self: *CpuRenderer, prepared: *const snail.PreparedResources, scene: *const snail.PreparedScene, state: snail.DrawState) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, state);
    }

    pub fn drawPass(self: *CpuRenderer, prepared: *const snail.PreparedResources, list: *const snail.DrawList, pass: snail.DrawPass) !void {
        var renderer = self.asRenderer();
        try renderer.drawPass(prepared, list, pass);
    }

    pub fn drawPreparedPass(self: *CpuRenderer, prepared: *const snail.PreparedResources, scene: *const snail.PreparedScene, pass: snail.DrawPass) !void {
        var renderer = self.asRenderer();
        try renderer.drawPreparedPass(prepared, scene, pass);
    }

    /// Frame-level fan-out invoked by the CPU vtable's `draw` entry when a
    /// thread pool is attached. Caller has already validated records, so
    /// each tile worker can call `iterateRecords` with no expected draw
    /// errors. Fanning out once per frame (rather than per segment)
    /// amortizes the wake-and-join cost across the whole scene.
    pub fn dispatchTiledDraw(
        self: *CpuRenderer,
        pool: *snail.ThreadPool,
        backend_prepared: ?*const anyopaque,
        records: DrawRecords,
        state: snail.DrawState,
    ) void {
        const span = self.row_clip_max - self.row_clip_min;
        const tile_count = (span + TILE_ROWS - 1) / TILE_ROWS;
        var ctx = cpu_tile_frame.Context(CpuRenderer){
            .self = self,
            .backend_prepared = backend_prepared,
            .records = records,
            .state = state,
        };
        pool.dispatch(tile_count, &ctx, cpu_tile_frame.callback(CpuRenderer, TILE_ROWS));
    }

    pub fn drawTextBatchPrepared(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const WORDS = vertex.WORDS_PER_INSTANCE;
        // Always serial: parallelism is at the frame level via `drawPrepared`.
        // Per-instance bounds rejection inside the row loops handles tile
        // clipping when this is invoked from a tile worker.
        var i: usize = 0;
        while (i + WORDS <= vertices.len) : (i += WORDS) {
            const inst = vertices[i..][0..WORDS];
            self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
        }
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
        const band_counts = render_abi.unpackBandCounts(@bitCast(header[2]));
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
        self.renderTransformedGlyph(page, decoded.bbox, be, decoded.transform, multiplyLinearColor(decoded.color, decoded.tint), false);
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
    ) void {
        const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
            page,
            local,
            raster.subpixel_plan,
            layer.band_entry,
            layer.band_max_h,
            layer.band_max_v,
            self.fill_rule,
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
            self.fill_rule,
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
    ) void {
        const cov = self.scalarPathLayerCoverage(page, raster, layer, local);

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
    ) PathCompositePixel {
        var accum: PathCompositeAccum = .{};
        for (layers, 0..) |layer, layer_index| {
            if (raster.use_subpixel) {
                self.recordCompositeSubpixelLayer(&accum, page, raster, layer, layer_index, programs, local, tint);
            } else {
                self.recordCompositeScalarLayer(&accum, page, raster, layer, layer_index, programs, local, tint);
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
        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });
            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                const fill_cov = self.scalarPathLayerCoverage(page, raster, fill_layer, local);
                if (fill_cov <= 0.0) continue;

                const stroke_cov = self.scalarPathLayerCoverage(page, raster, stroke_layer, local);
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
                if (combined[3] < 1.0 / 255.0) continue;
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

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });
            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                const pixel = self.sampleCompositePathPixel(page, raster, layers, programs, local, tint);
                if (pixel.color[3] < 1.0 / 255.0) continue;
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

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });
            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                if (!raster.use_subpixel) {
                    const cov = self.applyCoverageTransfer(evalGlyphCoverageBandSpan(page, local.x, local.y, raster.epp.x, raster.epp.y, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, self.fill_rule));
                    if (cov < 1.0 / 255.0) continue;
                    var paint = paint_program.sample(local);
                    paint.color = multiplyLinearColor(paint.color, tint);
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                } else {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                        page,
                        local,
                        raster.subpixel_plan,
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                    ));
                    if (max3(cov.rgb) < 1.0 / 255.0) continue;
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

        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            var display_local = inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });
            while (col < @as(u32, @intCast(px1))) : (advanceLocalPixel(&col, &display_local, sample_dx)) {
                if (!allow_subpixel or self.subpixel_order == .none) {
                    const cov = self.applyCoverageTransfer(evalGlyphCoverage(page, display_local.x, display_local.y, ppe.x, ppe.y, be, band_max_h, band_max_v, self.fill_rule));
                    if (cov < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov), false);
                } else {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                        page,
                        display_local,
                        subpixel_plan,
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                    ));
                    if (max3(cov.rgb) < 1.0 / 255.0) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                }
            }
        }
    }

    fn drawGlyphId(
        self: *CpuRenderer,
        atlas: *const CurveAtlas,
        glyph_id: u16,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) void {
        self.drawGlyphIdLinear(atlas, glyph_id, x, y, font_size, srgbColorToLinear(color), true);
    }

    fn drawGlyphIdLinear(
        self: *CpuRenderer,
        atlas: *const CurveAtlas,
        glyph_id: u16,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        if (glyph_id == 0) return;
        const info = atlas.getGlyph(glyph_id) orelse return;
        self.drawGlyphInfoLinear(atlas, info, x, y, font_size, color, allow_subpixel);
    }

    fn drawGlyphInfoLinear(
        self: *CpuRenderer,
        atlas: *const CurveAtlas,
        info: CurveAtlas.GlyphInfo,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return;
        self.renderGlyphInternal(atlas, info, x, y, font_size, color, allow_subpixel);
    }

    fn renderGlyphInternal(
        self: *CpuRenderer,
        atlas: *const CurveAtlas,
        info: CurveAtlas.GlyphInfo,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        const be = info.band_entry;
        const bbox = info.bbox;
        const page = atlas.page(info.page_index);

        const scale = font_size;

        // y parameter is the baseline (y-down). Em-space y goes up, screen y goes down.
        const glyph_x0 = x + bbox.min.x * scale;
        const glyph_x1 = x + bbox.max.x * scale;
        const glyph_y0 = y - bbox.max.y * scale;
        const glyph_y1 = y - bbox.min.y * scale;

        var bounds = ScreenBounds{
            .min = Vec2.new(glyph_x0, glyph_y0),
            .max = Vec2.new(glyph_x1, glyph_y1),
        };
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));

        if (px0 >= px1 or py0 >= py1) return;

        const epp_x: f32 = 1.0 / scale;
        const epp_y: f32 = 1.0 / scale;

        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;
        const subpixel_plan = SubpixelCoveragePlan.init(Vec2.new(epp_x, 0.0), Vec2.new(0.0, -epp_y), self.subpixel_order);

        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            while (col < @as(u32, @intCast(px1))) : (col += 1) {
                self.renderGlyphPixel(page, row, col, x, y, scale, be, band_max_h, band_max_v, subpixel_plan, color, allow_subpixel);
            }
        }
    }

    fn renderGlyphPixel(
        self: *CpuRenderer,
        page: anytype,
        row: u32,
        col: u32,
        x: f32,
        y: f32,
        scale: f32,
        be: GlyphBandEntry,
        band_max_h: i32,
        band_max_v: i32,
        subpixel_plan: SubpixelCoveragePlan,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        const px_f = @as(f32, @floatFromInt(col)) + 0.5;
        const py_f = @as(f32, @floatFromInt(row)) + 0.5;
        const em_x = (px_f - x) / scale;
        const em_y = (y - py_f) / scale;

        if (!allow_subpixel or self.subpixel_order == .none) {
            const cov = self.applyCoverageTransfer(evalGlyphCoverage(
                page,
                em_x,
                em_y,
                scale,
                scale,
                be,
                band_max_h,
                band_max_v,
                self.fill_rule,
            ));
            if (cov < 1.0 / 255.0) return;
            self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov), false);
            return;
        }

        const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
            page,
            Vec2.new(em_x, em_y),
            subpixel_plan,
            be,
            band_max_h,
            band_max_v,
            self.fill_rule,
        ));
        if (max3(cov.rgb) < 1.0 / 255.0) return;
        self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
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

    fn blendPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
        cpu_blend.blendPremultipliedPixel(self.blendTarget(), row, col, src, apply_dither);
    }

    fn blendSubpixelPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
        cpu_blend.blendSubpixelPremultipliedPixel(self.blendTarget(), row, col, src, src_blend, apply_dither);
    }

    /// Per-channel subpixel blend (equivalent to GPU dual-source blending).
    /// Each RGB channel has its own coverage, so the destination attenuation
    /// is per-channel: out.r = src.r * alpha_r + dst.r * (1 - alpha_r), etc.
    fn blendSubpixelPixel(self: *CpuRenderer, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
        cpu_blend.blendSubpixelPixel(self.blendTarget(), row, col, color, cov, alpha_cov);
    }
};

pub const test_api = if (builtin.is_test) struct {
    pub const clear = CpuRenderer.clear;
    pub const drawPathPicture = CpuRenderer.drawPathPicture;
    pub const drawPathPictureTransformed = CpuRenderer.drawPathPictureTransformed;
    pub const drawGlyphId = CpuRenderer.drawGlyphId;
    pub const blendPremultipliedPixel = CpuRenderer.blendPremultipliedPixel;
} else struct {};
