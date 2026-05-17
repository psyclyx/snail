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
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const vertex = @import("../../format/vertex.zig");
const CurveSegment = bezier.CurveSegment;
const CurveAtlas = atlas_curve_mod.CurveAtlas;
const AtlasPage = atlas_page_mod.AtlasPage;
const GlyphBandEntry = std.meta.fieldInfo(CurveAtlas.GlyphInfo, .band_entry).type;
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
const addColors = cpu_path_paint.addColors;
const advanceLocalPixel = cpu_geometry.advanceLocalPixel;
const clamp01 = cpu_color.clamp01;
const compositeOver = cpu_path_paint.compositeOver;
const compositeSubpixelOver = cpu_coverage.compositeSubpixelOver;
const evalGlyphCoverage = cpu_coverage.evalGlyphCoverage;
const evalGlyphCoverageSubpixel = cpu_coverage.evalGlyphCoverageSubpixel;
const expandBoundsForSubpixel = cpu_geometry.expandBoundsForSubpixel;
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
const PreparedPathRecord = cpu_path_paint.PreparedPathRecord;
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
    /// path sets this from `ResolveTarget.encoding` every frame.
    target_encoding: snail.TargetEncoding,
    target_resolve: snail.Resolve,
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
            // `ResolveTarget.encoding` per frame.
            .target_encoding = .srgb,
            .target_resolve = .{ .direct = .{} },
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

    pub fn setFillRule(self: *CpuRenderer, rule: FillRule) void {
        self.fill_rule = rule;
    }

    pub fn getFillRule(self: *const CpuRenderer) FillRule {
        return self.fill_rule;
    }

    pub fn setSubpixelOrder(self: *CpuRenderer, order: SubpixelOrder) void {
        self.subpixel_order = order;
    }

    pub fn getSubpixelOrder(self: *const CpuRenderer) SubpixelOrder {
        return self.subpixel_order;
    }

    pub fn setTargetEncoding(self: *CpuRenderer, encoding: snail.TargetEncoding) void {
        self.target_encoding = encoding;
    }

    pub fn getTargetEncoding(self: *const CpuRenderer) snail.TargetEncoding {
        return self.target_encoding;
    }

    pub fn setResolve(self: *CpuRenderer, resolve: snail.Resolve) void {
        self.target_resolve = resolve;
    }

    pub fn getResolve(self: *const CpuRenderer) snail.Resolve {
        return self.target_resolve;
    }

    pub fn setCoverageTransfer(self: *CpuRenderer, transfer: snail.CoverageTransfer) void {
        self.coverage_transfer = transfer;
    }

    pub fn getCoverageTransfer(self: *const CpuRenderer) snail.CoverageTransfer {
        return self.coverage_transfer;
    }

    pub const LinearResolveRestore = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,
    };

    pub fn beginLinearResolve(self: *CpuRenderer, target: snail.ResolveTarget, resolve: snail.LinearResolve) LinearResolveRestore {
        const restore = LinearResolveRestore{
            .row_clip_min = self.row_clip_min,
            .row_clip_max = self.row_clip_max,
            .col_clip_min = self.col_clip_min,
            .col_clip_max = self.col_clip_max,
        };
        const rect = target.resolveRect();
        self.col_clip_min = @intCast(rect.x);
        self.row_clip_min = @intCast(rect.y);
        self.col_clip_max = self.col_clip_min + rect.w;
        self.row_clip_max = self.row_clip_min + rect.h;
        self.seedLinearResolveBackdrop(target.encoding, rect, resolve.backdrop);
        return restore;
    }

    pub fn endLinearResolve(self: *CpuRenderer, restore: LinearResolveRestore) void {
        self.row_clip_min = restore.row_clip_min;
        self.row_clip_max = restore.row_clip_max;
        self.col_clip_min = restore.col_clip_min;
        self.col_clip_max = restore.col_clip_max;
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
            const bounds = transformedGlyphBounds(info.bbox, final_transform);
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
                    const cov = self.applyCoverageTransfer(evalGlyphCoverage(
                        page,
                        local.x,
                        local.y,
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

    pub fn drawTextPrepared(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, mvp: snail.Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
        const scene = sceneToPixelFromMvp(mvp, vw, vh);
        self.drawTextBatchPrepared(prepared, vertices, scene, texture_layer_base, true);
    }

    pub fn drawPathsPrepared(self: *CpuRenderer, prepared: *const PreparedResources, vertices: []const u32, mvp: snail.Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
        const scene = sceneToPixelFromMvp(mvp, vw, vh);
        self.drawTextBatchPrepared(prepared, vertices, scene, texture_layer_base, false);
    }

    pub fn beginFrame(_: *CpuRenderer) void {}

    pub fn backendName(_: *const CpuRenderer) []const u8 {
        return "CPU";
    }

    pub fn asRenderer(self: *CpuRenderer) snail.Renderer {
        return snail.render.adapter.cpu.borrow(self);
    }

    pub fn uploadResourcesBlocking(self: *CpuRenderer, allocators: snail.UploadAllocators, set: *const snail.ResourceSet) !snail.PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn draw(self: *CpuRenderer, prepared: *const snail.PreparedResources, records: snail.DrawRecords, options: snail.DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *CpuRenderer, prepared: *const snail.PreparedResources, scene: *const snail.PreparedScene, options: snail.DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    /// Frame-level fan-out invoked by the CPU vtable's `draw` entry when a
    /// thread pool is attached. Caller has already validated records, so
    /// each tile worker can call the void-returning `iterateRecords` path
    /// directly. Fanning out once per frame (rather than per segment)
    /// amortizes the wake-and-join cost across the whole scene.
    pub fn dispatchTiledDraw(
        self: *CpuRenderer,
        pool: *snail.ThreadPool,
        backend_prepared: ?*const anyopaque,
        records: snail.DrawRecords,
        options: snail.DrawOptions,
    ) void {
        const span = self.row_clip_max - self.row_clip_min;
        const tile_count = (span + TILE_ROWS - 1) / TILE_ROWS;
        var ctx = TileFrameCtx{
            .self = self,
            .backend_prepared = backend_prepared,
            .records = records,
            .options = options,
        };
        pool.dispatch(tile_count, &ctx, runFrameTile);
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

    fn renderBatchInstance(self: *CpuRenderer, prepared: *const PreparedResources, inst: []const u32, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const encoded = vertex.instanceAt(inst, 0);
        const bbox = bezier.BBox{
            .min = .{ .x = f16ToF32(encoded.rect[0]), .y = f16ToF32(encoded.rect[1]) },
            .max = .{ .x = f16ToF32(encoded.rect[2]), .y = f16ToF32(encoded.rect[3]) },
        };
        const instance_transform = Transform2D{
            .xx = encoded.xform[0],
            .xy = encoded.xform[1],
            .yx = encoded.xform[2],
            .yy = encoded.xform[3],
            .tx = encoded.origin[0],
            .ty = encoded.origin[1],
        };
        // Compose the scene-to-pixel transform onto the baked instance
        // transform; GPU backends do this in the vertex shader via the MVP
        // uniform, the CPU rasterizer has to do it here.
        const transform = Transform2D.multiply(scene_to_pixel, instance_transform);
        const gz = encoded.glyph[0];
        const gw = encoded.glyph[1];
        const color = srgbBytesToLinearColor(encoded.color);
        const tint = srgbBytesToLinearColor(encoded.tint);

        const atlas_layer_byte: u8 = @intCast(gw >> 24);

        if (atlas_layer_byte == 0xFF) {
            const layer_count: u16 = @intCast(gw & 0xFFFF);
            const info_x: u16 = @intCast(gz & 0xFFFF);
            const info_y: u16 = @intCast(gz >> 16);
            const atlas_layer = texture_layer_base + @as(u32, @intFromFloat(encoded.band[3]));

            // Resolve the layer info for this info_y (handles multi-atlas row offsets).
            const resolved = prepared.resolveLayerInfo(info_y) orelse return;
            const entry = resolved.entry;
            const first_tag = fetchLayerInfoTexel(entry.data, entry.width, info_x, resolved.local_y, 0)[3];
            if (first_tag < 0.0) {
                const record = entry.pathRecordAt(info_x, resolved.local_y) orelse return;
                self.renderPathBatchLayers(prepared, bbox, transform, tint, atlas_layer, entry, record, false);
            } else {
                self.renderColrBatchLayers(prepared, bbox, transform, color, tint, info_x, resolved.local_y, layer_count, atlas_layer, entry.data, entry.width);
            }
            return;
        }

        // Regular glyph: decode band entry from vertex data.
        const glyph_x: u16 = @intCast(gz & 0xFFFF);
        const glyph_y: u16 = @intCast(gz >> 16);
        const h_band_count: u16 = @intCast((gw & 0xFFFF) + 1);
        const v_band_count: u16 = @intCast(((gw >> 16) & 0xFF) + 1);

        const be = GlyphBandEntry{
            .glyph_x = glyph_x,
            .glyph_y = glyph_y,
            .h_band_count = h_band_count,
            .v_band_count = v_band_count,
            .band_scale_x = encoded.band[0],
            .band_scale_y = encoded.band[1],
            .band_offset_x = encoded.band[2],
            .band_offset_y = encoded.band[3],
        };

        const atlas_layer = texture_layer_base + @as(u32, atlas_layer_byte);
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        self.renderTransformedGlyph(page, bbox, be, transform, multiplyLinearColor(color, tint), allow_subpixel);
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
            const band_packed: u32 = @bitCast(data[t0 + 2]);
            const h_band_count: u16 = @intCast((band_packed & 0xFFFF) + 1);
            const v_band_count: u16 = @intCast(((band_packed >> 16) & 0xFFFF) + 1);

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
                .h_band_count = h_band_count,
                .v_band_count = v_band_count,
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
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;

        if (record.tag == 5) {
            // Composite group: header at offset 0, then 6 texels per layer starting at offset 1.
            const layer_count = record.layer_count;
            const composite_mode = record.composite_mode;
            const layers = entry.path_layers[record.layer_start..][0..layer_count];

            const inverse = inverseTransform(transform) orelse return;
            const bounds = transformedGlyphBounds(union_bbox, transform);
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
            if (px0 >= px1 or py0 >= py1) return;

            const epp = glyphEdgePixelsPerPixel(inverse);
            const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
            const sample_dx = Vec2.new(inverse.xx, inverse.yx);
            const sample_dy = Vec2.new(inverse.xy, inverse.yy);
            const use_subpixel = allow_subpixel and self.subpixel_order != .none;
            const subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order);
            const outline_composite = composite_mode == 1 and layer_count >= 2;
            const fill_paint_program: PreparedPathPaint = if (outline_composite) layers[0].paint else .{};
            const stroke_paint_program: PreparedPathPaint = if (outline_composite) layers[1].paint else .{};

            var row: u32 = @intCast(py0);
            while (row < @as(u32, @intCast(py1))) : (row += 1) {
                var col: u32 = @intCast(px0);
                var local = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(col)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                while (col < @as(u32, @intCast(px1))) : (advanceLocalPixel(&col, &local, sample_dx)) {
                    var result = [4]f32{ 0, 0, 0, 0 };
                    var result_blend = [3]f32{ 0, 0, 0 };
                    var fill_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 };
                    var stroke_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 };
                    var fill_paint = [4]f32{ 0, 0, 0, 0 };
                    var stroke_paint = [4]f32{ 0, 0, 0, 0 };
                    var fill_apply_dither = false;
                    var stroke_apply_dither = false;
                    var has_gradient = false;

                    for (0..layer_count) |l| {
                        const layer = layers[l];
                        const be = layer.band_entry;
                        const band_max_h = layer.band_max_h;
                        const band_max_v = layer.band_max_v;

                        if (use_subpixel) {
                            const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                                page,
                                local,
                                subpixel_plan,
                                be,
                                band_max_h,
                                band_max_v,
                                self.fill_rule,
                            ));

                            if (outline_composite and l < 2) {
                                if (l == 0) {
                                    fill_cov = cov;
                                    if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                                        const paint = fill_paint_program.sample(local);
                                        fill_paint = multiplyLinearColor(paint.color, tint);
                                        fill_apply_dither = paint.apply_dither;
                                    }
                                } else {
                                    stroke_cov = cov;
                                    if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                                        const paint = stroke_paint_program.sample(local);
                                        stroke_paint = multiplyLinearColor(paint.color, tint);
                                        stroke_apply_dither = paint.apply_dither;
                                    }
                                }
                                continue;
                            }

                            if (max3(cov.rgb) <= 0.0 and cov.alpha <= 0.0) continue;
                            var paint = layer.paint.sample(local);
                            paint.color = multiplyLinearColor(paint.color, tint);
                            if (paint.apply_dither and cov.alpha > 1e-6) has_gradient = true;
                            compositeSubpixelOver(
                                premultiplySubpixelCoverage(paint.color, cov.rgb, cov.alpha),
                                subpixelBlendCoverage(paint.color, cov.rgb),
                                &result,
                                &result_blend,
                            );
                        } else {
                            const cov = self.applyCoverageTransfer(evalGlyphCoverage(page, local.x, local.y, ppe.x, ppe.y, be, band_max_h, band_max_v, self.fill_rule));

                            if (outline_composite and l < 2) {
                                if (l == 0) {
                                    fill_cov = .{ .rgb = .{ cov, cov, cov }, .alpha = cov };
                                    if (cov > 0.0) {
                                        const paint = fill_paint_program.sample(local);
                                        fill_paint = multiplyLinearColor(paint.color, tint);
                                    }
                                } else {
                                    stroke_cov = .{ .rgb = .{ cov, cov, cov }, .alpha = cov };
                                    if (cov > 0.0) {
                                        const paint = stroke_paint_program.sample(local);
                                        stroke_paint = multiplyLinearColor(paint.color, tint);
                                    }
                                }
                                continue;
                            }
                            if (cov <= 0.0) continue;
                            var paint = layer.paint.sample(local);
                            paint.color = multiplyLinearColor(paint.color, tint);
                            const premul = premultiplyCoverage(paint.color, cov);
                            result = compositeOver(premul, result);
                        }
                    }

                    if (outline_composite) {
                        if (use_subpixel) {
                            const border_cov = [3]f32{
                                @min(fill_cov.rgb[0], stroke_cov.rgb[0]),
                                @min(fill_cov.rgb[1], stroke_cov.rgb[1]),
                                @min(fill_cov.rgb[2], stroke_cov.rgb[2]),
                            };
                            const interior_cov = [3]f32{
                                @max(fill_cov.rgb[0] - border_cov[0], 0.0),
                                @max(fill_cov.rgb[1] - border_cov[1], 0.0),
                                @max(fill_cov.rgb[2] - border_cov[2], 0.0),
                            };
                            const border_alpha = @min(fill_cov.alpha, stroke_cov.alpha);
                            const interior_alpha = @max(fill_cov.alpha - border_alpha, 0.0);
                            if (fill_apply_dither and interior_alpha > 1e-6) has_gradient = true;
                            if (stroke_apply_dither and border_alpha > 1e-6) has_gradient = true;
                            compositeSubpixelOver(
                                addColors(
                                    premultiplySubpixelCoverage(fill_paint, interior_cov, interior_alpha),
                                    premultiplySubpixelCoverage(stroke_paint, border_cov, border_alpha),
                                ),
                                .{
                                    subpixelBlendCoverage(fill_paint, interior_cov)[0] + subpixelBlendCoverage(stroke_paint, border_cov)[0],
                                    subpixelBlendCoverage(fill_paint, interior_cov)[1] + subpixelBlendCoverage(stroke_paint, border_cov)[1],
                                    subpixelBlendCoverage(fill_paint, interior_cov)[2] + subpixelBlendCoverage(stroke_paint, border_cov)[2],
                                },
                                &result,
                                &result_blend,
                            );
                        } else {
                            const border_cov = @min(fill_cov.alpha, stroke_cov.alpha);
                            const interior_cov = @max(fill_cov.alpha - border_cov, 0.0);
                            const combined = addColors(premultiplyCoverage(fill_paint, interior_cov), premultiplyCoverage(stroke_paint, border_cov));
                            result = compositeOver(combined, result);
                        }
                    }

                    if (result[3] < 1.0 / 255.0) continue;
                    if (use_subpixel) {
                        self.blendSubpixelPremultipliedPixel(row, col, result, result_blend, has_gradient);
                    } else {
                        self.blendPremultipliedPixel(row, col, result, false);
                    }
                }
            }
        } else {
            // Single-layer path paint.
            if (record.layer_count == 0) return;
            const layer = entry.path_layers[record.layer_start];
            const be = layer.band_entry;

            const inverse = inverseTransform(transform) orelse return;
            const bounds = transformedGlyphBounds(union_bbox, transform);
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
            if (px0 >= px1 or py0 >= py1) return;

            const epp = glyphEdgePixelsPerPixel(inverse);
            const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
            const sample_dx = Vec2.new(inverse.xx, inverse.yx);
            const sample_dy = Vec2.new(inverse.xy, inverse.yy);
            const subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order);
            const band_max_h = layer.band_max_h;
            const band_max_v = layer.band_max_v;
            const paint_program = layer.paint;

            var row: u32 = @intCast(py0);
            while (row < @as(u32, @intCast(py1))) : (row += 1) {
                var col: u32 = @intCast(px0);
                var local = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(col)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                while (col < @as(u32, @intCast(px1))) : (advanceLocalPixel(&col, &local, sample_dx)) {
                    if (!allow_subpixel or self.subpixel_order == .none) {
                        const cov = self.applyCoverageTransfer(evalGlyphCoverage(page, local.x, local.y, ppe.x, ppe.y, be, band_max_h, band_max_v, self.fill_rule));
                        if (cov < 1.0 / 255.0) continue;
                        var paint = paint_program.sample(local);
                        paint.color = multiplyLinearColor(paint.color, tint);
                        self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                    } else {
                        const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                            page,
                            local,
                            subpixel_plan,
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
        expandBoundsForSubpixel(&bounds, self.subpixel_order, allow_subpixel);

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
        expandBoundsForSubpixel(&bounds, self.subpixel_order, allow_subpixel);

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), @as(i32, @intCast(self.col_clip_min)));
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.col_clip_max)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));

        if (px0 >= px1 or py0 >= py1) return;

        const epp_x: f32 = 1.0 / scale;
        const epp_y: f32 = 1.0 / scale;
        const ppe_x: f32 = scale;
        const ppe_y: f32 = scale;

        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;
        const subpixel_plan = SubpixelCoveragePlan.init(Vec2.new(epp_x, 0.0), Vec2.new(0.0, -epp_y), self.subpixel_order);

        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            while (col < @as(u32, @intCast(px1))) : (col += 1) {
                const px_f = @as(f32, @floatFromInt(col)) + 0.5;
                const py_f = @as(f32, @floatFromInt(row)) + 0.5;

                const em_x = (px_f - x) / scale;
                const em_y = (y - py_f) / scale;

                if (!allow_subpixel or self.subpixel_order == .none) {
                    const cov = self.applyCoverageTransfer(evalGlyphCoverage(
                        page,
                        em_x,
                        em_y,
                        ppe_x,
                        ppe_y,
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                    ));
                    if (cov < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov), false);
                } else {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                        page,
                        Vec2.new(em_x, em_y),
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

    inline fn blendTarget(self: *CpuRenderer) cpu_blend.Target {
        return .{
            .pixels = self.pixels,
            .stride = self.stride,
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

const TileFrameCtx = struct {
    self: *const CpuRenderer,
    backend_prepared: ?*const anyopaque,
    records: snail.DrawRecords,
    options: snail.DrawOptions,
};

fn runFrameTile(opaque_ctx: *anyopaque, tile_index: u32) void {
    const ctx: *const TileFrameCtx = @ptrCast(@alignCast(opaque_ctx));
    var tile_renderer = ctx.self.*;
    tile_renderer.thread_pool = null;
    const tile_min = ctx.self.row_clip_min + tile_index * CpuRenderer.TILE_ROWS;
    tile_renderer.row_clip_min = tile_min;
    tile_renderer.row_clip_max = @min(tile_min + CpuRenderer.TILE_ROWS, ctx.self.row_clip_max);

    var renderer = tile_renderer.asRenderer();
    renderer.iterateRecords(ctx.records, ctx.options, ctx.backend_prepared);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn expectEqualSlicesWithinU8(expected: []const u8, actual: []const u8, max_diff: u8, max_differences: usize) !void {
    try std.testing.expectEqual(expected.len, actual.len);

    var diff_count: usize = 0;
    for (expected, actual) |lhs, rhs| {
        const diff = if (lhs > rhs) lhs - rhs else rhs - lhs;
        if (diff > max_diff) return error.TestExpectedEqual;
        if (diff != 0) diff_count += 1;
    }

    try std.testing.expect(diff_count <= max_differences);
}

test "f16ToF32 roundtrip" {
    const testing = std.testing;
    try testing.expectApproxEqAbs(@as(f32, 0.0), f16ToF32(0), 1e-10);
    try testing.expectApproxEqAbs(@as(f32, 1.0), f16ToF32(0x3C00), 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.5), f16ToF32(0x3800), 1e-4);
    try testing.expectApproxEqAbs(@as(f32, -1.0), f16ToF32(0xBC00), 1e-4);
}

test "cpu renderer renders glyphs" {
    const testing = std.testing;
    const assets = @import("assets");
    const font_data = assets.noto_sans_regular;

    var font = try snail.Font.init(font_data);
    defer font.deinit();

    var atlas = try snail.text.glyph_atlas.initAscii(testing.allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    const width: u32 = 200;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    const font_size: f32 = 24.0;
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    const text = "Hello";

    var cursor_x: f32 = 2.0;
    const baseline_y: f32 = 30.0;

    const em_scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
    for (text) |ch| {
        const gid = try font.glyphIndex(@as(u32, ch));
        renderer.drawGlyphId(&atlas, gid, cursor_x, baseline_y, font_size, white);
        const advance = try font.advanceWidth(gid);
        cursor_x += @as(f32, @floatFromInt(advance)) * em_scale;
    }

    var non_zero_count: u32 = 0;
    for (buf) |byte| {
        if (byte != 0) non_zero_count += 1;
    }
    try testing.expect(non_zero_count > 100);
}

test "cpu renderer renders path rect" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 18, .h = 12 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const inside = ((12 * stride) + (16 * 4));
    try testing.expect(buf[inside + 0] > 200);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] > 200);

    const outside = ((2 * stride) + (2 * 4));
    try testing.expectEqual(@as(u8, 0), buf[outside + 0]);
    try testing.expectEqual(@as(u8, 0), buf[outside + 3]);
}

test "cpu renderer renders transformed path picture" {
    const testing = std.testing;

    const width: u32 = 64;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 10, .h = 8 }, .{
        .paint = .{ .solid = .{ 0, 1, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPictureTransformed(&picture, .{ .tx = 20, .ty = 10 });

    const translated = ((13 * stride) + (24 * 4));
    try testing.expect(buf[translated + 1] > 200);
    try testing.expect(buf[translated + 3] > 200);

    const original = ((3 * stride) + (4 * 4));
    try testing.expectEqual(@as(u8, 0), buf[original + 1]);
    try testing.expectEqual(@as(u8, 0), buf[original + 3]);
}

test "cpu renderer matches absolute and transformed rounded rect pictures" {
    const testing = std.testing;

    const width: u32 = 160;
    const height: u32 = 120;
    const stride = width * 4;
    const absolute_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(absolute_buf);
    const transformed_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(transformed_buf);

    var absolute_renderer = CpuRenderer.init(absolute_buf.ptr, width, height, stride);
    absolute_renderer.clear(0, 0, 0, 0);
    var transformed_renderer = CpuRenderer.init(transformed_buf.ptr, width, height, stride);
    transformed_renderer.clear(0, 0, 0, 0);

    var absolute_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer absolute_builder.deinit();
    try absolute_builder.addRoundedRect(
        .{ .x = 64, .y = 40, .w = 32, .h = 18 },
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = 64, .y = 40 },
            .end = .{ .x = 96, .y = 58 },
            .start_color = .{ 0.2, 0.8, 1.0, 1.0 },
            .end_color = .{ 0.9, 0.7, 0.3, 1.0 },
        } } },
        .{ .paint = .{ .solid = .{ 1, 1, 1, 0.5 } }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .identity,
    );
    var absolute_picture = try absolute_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer absolute_picture.deinit();

    var transformed_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer transformed_builder.deinit();
    try transformed_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 32, .h = 18 },
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 32, .y = 18 },
            .start_color = .{ 0.2, 0.8, 1.0, 1.0 },
            .end_color = .{ 0.9, 0.7, 0.3, 1.0 },
        } } },
        .{ .paint = .{ .solid = .{ 1, 1, 1, 0.5 } }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .{ .tx = 64, .ty = 40 },
    );
    var transformed_picture = try transformed_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer transformed_picture.deinit();

    absolute_renderer.drawPathPicture(&absolute_picture);
    transformed_renderer.drawPathPicture(&transformed_picture);

    try expectEqualSlicesWithinU8(absolute_buf, transformed_buf, 1, 16);
}

test "cpu renderer keeps rounded rect cap joins opaque" {
    const testing = std.testing;

    const width: u32 = 80;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(
        .{ .x = 16.5, .y = 12.5, .w = 48.0, .h = 16.0 },
        .{ .paint = .{ .solid = .{ 0.2, 0.7, 0.9, 1.0 } } },
        null,
        8.0,
        .identity,
    );
    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const center_row: usize = 20;
    const seam_col: usize = 24; // sample center x = 24.5, exactly at rect.x + radius
    const inner_col: usize = 25;
    const seam_alpha = buf[center_row * stride + seam_col * 4 + 3];
    const inner_alpha = buf[center_row * stride + inner_col * 4 + 3];

    try testing.expectEqual(@as(u8, 255), inner_alpha);
    try testing.expectEqual(@as(u8, 255), seam_alpha);
}

test "cpu renderer matches huge-span and normalized curved path pictures" {
    const testing = std.testing;

    const width: u32 = 144;
    const height: u32 = 144;
    const stride = width * 4;
    const large_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(large_buf);
    const normalized_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(normalized_buf);

    var large_renderer = CpuRenderer.init(large_buf.ptr, width, height, stride);
    large_renderer.clear(0, 0, 0, 0);
    var normalized_renderer = CpuRenderer.init(normalized_buf.ptr, width, height, stride);
    normalized_renderer.clear(0, 0, 0, 0);

    var large_path = snail.Path.init(testing.allocator);
    defer large_path.deinit();
    try large_path.moveTo(.{ .x = 0, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 0 }, .{ .x = 64 * 64, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 80 * 64 }, .{ .x = 0, .y = 40 * 64 });
    try large_path.close();

    var large_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer large_builder.deinit();
    try large_builder.addFilledPath(
        &large_path,
        .{ .paint = .{ .solid = .{ 0.95, 0.55, 0.15, 1.0 } } },
        Transform2D.multiply(
            Transform2D.translate(24, 28),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer large_picture.deinit();

    var normalized_path = snail.Path.init(testing.allocator);
    defer normalized_path.deinit();
    try normalized_path.moveTo(.{ .x = 0, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 0 }, .{ .x = 64, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 80 }, .{ .x = 0, .y = 40 });
    try normalized_path.close();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addFilledPath(
        &normalized_path,
        .{ .paint = .{ .solid = .{ 0.95, 0.55, 0.15, 1.0 } } },
        Transform2D.translate(24, 28),
    );
    var normalized_picture = try normalized_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer normalized_picture.deinit();

    large_renderer.drawPathPicture(&large_picture);
    normalized_renderer.drawPathPicture(&normalized_picture);

    try testing.expectEqualSlices(u8, large_buf, normalized_buf);
}

test "cpu renderer matches huge-span and normalized rounded rect pictures" {
    const testing = std.testing;

    const width: u32 = 224;
    const height: u32 = 112;
    const stride = width * 4;
    const large_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(large_buf);
    const normalized_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(normalized_buf);

    var large_renderer = CpuRenderer.init(large_buf.ptr, width, height, stride);
    large_renderer.clear(0, 0, 0, 0);
    var normalized_renderer = CpuRenderer.init(normalized_buf.ptr, width, height, stride);
    normalized_renderer.clear(0, 0, 0, 0);

    var large_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer large_builder.deinit();
    try large_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 180 * 64, .h = 40 * 64 },
        .{ .paint = .{ .solid = .{ 0.33, 0.39, 0.36, 0.92 } } },
        .{ .paint = .{ .solid = .{ 0.79, 0.86, 0.78, 1.0 } }, .width = 2.0 * 64.0, .join = .round, .placement = .inside },
        20.0 * 64.0,
        Transform2D.multiply(
            Transform2D.translate(20, 24),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer large_picture.deinit();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 180, .h = 40 },
        .{ .paint = .{ .solid = .{ 0.33, 0.39, 0.36, 0.92 } } },
        .{ .paint = .{ .solid = .{ 0.79, 0.86, 0.78, 1.0 } }, .width = 2.0, .join = .round, .placement = .inside },
        20.0,
        Transform2D.translate(20, 24),
    );
    var normalized_picture = try normalized_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer normalized_picture.deinit();

    large_renderer.drawPathPicture(&large_picture);
    normalized_renderer.drawPathPicture(&normalized_picture);

    try expectEqualSlicesWithinU8(large_buf, normalized_buf, 1, 16);
}

test "cpu renderer renders gradient path picture" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 20, .y = 0 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
        } },
    }, .{ .tx = 10, .ty = 7 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (26 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);
}

test "cpu renderer dithers shallow gradient path picture" {
    const testing = std.testing;

    const width: u32 = 512;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 480, .h = 12 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 480, .y = 0 },
            .start_color = .{ 0.28, 0.28, 0.28, 1.0 },
            .end_color = .{ 0.42, 0.42, 0.42, 1.0 },
        } },
    }, .{ .tx = 16, .ty = 6 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const row: usize = 12;
    const start_col: usize = 20;
    const end_col: usize = 492;
    var prev = buf[row * stride + start_col * 4];
    var run: usize = 1;
    var max_run: usize = 1;
    var transitions: usize = 0;

    for ((start_col + 1)..end_col) |col| {
        const value = buf[row * stride + col * 4];
        if (value == prev) {
            run += 1;
            continue;
        }
        transitions += 1;
        max_run = @max(max_run, run);
        run = 1;
        prev = value;
    }
    max_run = @max(max_run, run);

    try testing.expect(transitions > 80);
    try testing.expect(max_run < 12);
}

test "cpu renderer renders image-painted path picture" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var image = try snail.Image.initSrgba8(testing.allocator, 2, 1, &.{
        255, 0, 0,   255,
        0,   0, 255, 255,
    });
    defer image.deinit();

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .{ .xx = 1.0 / 20.0, .xy = 0.0, .tx = 0.0, .yx = 0.0, .yy = 1.0 / 10.0, .ty = 0.0 },
        } },
    }, .{ .tx = 8, .ty = 6 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (22 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);

    // Same picture through the prepared / Scene path. Regression: the
    // prepared sampler used to return magenta for tag-4 (image) paints
    // because `paint_image_records` wasn't threaded into the layer-info
    // sampler.
    const prepared_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(prepared_buf);
    var prepared_renderer = CpuRenderer.init(prepared_buf.ptr, width, height, stride);
    prepared_renderer.clear(0, 0, 0, 0);

    var renderer_iface = prepared_renderer.asRenderer();
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });

    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer_iface.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
    };
    const needed = snail.DrawList.estimate(&scene, options);
    const needed_segments = snail.DrawList.estimateSegments(&scene, options);
    const draw_buf = try testing.allocator.alloc(u32, needed);
    defer testing.allocator.free(draw_buf);
    const draw_segments = try testing.allocator.alloc(snail.DrawSegment, needed_segments);
    defer testing.allocator.free(draw_segments);
    var draw = snail.DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, options);
    try renderer_iface.draw(&prepared, draw.slice(), options);

    try testing.expect(prepared_buf[left + 0] > prepared_buf[left + 2]);
    try testing.expect(prepared_buf[left + 3] > 200);
    try testing.expect(prepared_buf[right + 2] > prepared_buf[right + 0]);
    try testing.expect(prepared_buf[right + 3] > 200);
    // And specifically not magenta (the old missing-records placeholder).
    try testing.expect(!(prepared_buf[left + 0] > 200 and prepared_buf[left + 1] < 50 and prepared_buf[left + 2] > 200));
}

test "cpu renderer premultiplies translucent path fill" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 28;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 0.5 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const inside = ((11 * stride) + (14 * 4));
    try testing.expect(buf[inside + 0] >= 185);
    try testing.expect(buf[inside + 0] <= 189);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}

test "cpu renderer decodes translucent sRGB solid path colors before blending" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 28;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 0.5, 0.5, 0.5, 0.5 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const inside = ((11 * stride) + (14 * 4));
    try testing.expect(buf[inside + 0] >= 91);
    try testing.expect(buf[inside + 0] <= 93);
    try testing.expectEqual(buf[inside + 0], buf[inside + 1]);
    try testing.expectEqual(buf[inside + 1], buf[inside + 2]);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}

test "cpu direct sRGB pixels on linear attachment blends in storage space" {
    var buf = [_]u8{ 0, 0, 0, 255 };
    var renderer = CpuRenderer.init(buf[0..].ptr, 1, 1, 4);
    renderer.setTargetEncoding(.srgb_pixels_on_linear_attachment);
    renderer.setResolve(.{ .direct = .{} });

    renderer.blendPremultipliedPixel(0, 0, .{ 0.5, 0.5, 0.5, 0.5 }, false);

    try std.testing.expectEqual(@as(u8, 128), buf[0]);
    try std.testing.expectEqual(@as(u8, 128), buf[1]);
    try std.testing.expectEqual(@as(u8, 128), buf[2]);
    try std.testing.expectEqual(@as(u8, 255), buf[3]);
}

test "cpu linear resolve sRGB pixels on linear attachment blends in linear space" {
    var buf = [_]u8{ 0, 0, 0, 255 };
    var renderer = CpuRenderer.init(buf[0..].ptr, 1, 1, 4);
    renderer.setTargetEncoding(.srgb_pixels_on_linear_attachment);
    renderer.setResolve(.{ .linear = .{} });

    renderer.blendPremultipliedPixel(0, 0, .{ 0.5, 0.5, 0.5, 0.5 }, false);

    const expected = linearToSrgbByte(0.5);
    try std.testing.expectEqual(expected, buf[0]);
    try std.testing.expectEqual(expected, buf[1]);
    try std.testing.expectEqual(expected, buf[2]);
    try std.testing.expectEqual(@as(u8, 255), buf[3]);
}

test "cpu linear resolve clear backdrop seeds only resolve region" {
    const width: u32 = 4;
    const height: u32 = 3;
    const stride: u32 = width * 4;
    const width_usize: usize = @intCast(width);
    const height_usize: usize = @intCast(height);
    const stride_usize: usize = @intCast(stride);
    var buf = [_]u8{9} ** (4 * 3 * 4);
    var renderer = CpuRenderer.init(buf[0..].ptr, width, height, stride);

    const linear = snail.LinearResolve{
        .backdrop = .{ .clear = .{ 1, 0, 0, 1 } },
        .region = .{ .pixel_rect = .{ .x = 1, .y = 1, .w = 2, .h = 1 } },
    };
    const target = snail.ResolveTarget{
        .pixel_width = @floatFromInt(width),
        .pixel_height = @floatFromInt(height),
        .encoding = .srgb_pixels_on_linear_attachment,
        .resolve = .{ .linear = linear },
    };

    const restore = renderer.beginLinearResolve(target, linear);
    renderer.endLinearResolve(restore);

    for (0..height_usize) |row| {
        for (0..width_usize) |col| {
            const off = row * stride_usize + col * 4;
            if (row == 1 and (col == 1 or col == 2)) {
                try std.testing.expectEqual(@as(u8, 255), buf[off + 0]);
                try std.testing.expectEqual(@as(u8, 0), buf[off + 1]);
                try std.testing.expectEqual(@as(u8, 0), buf[off + 2]);
                try std.testing.expectEqual(@as(u8, 255), buf[off + 3]);
            } else {
                try std.testing.expectEqual(@as(u8, 9), buf[off + 0]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 1]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 2]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 3]);
            }
        }
    }
}

test "cpu renderer renders collapsed inside stroke" {
    const testing = std.testing;

    const width: u32 = 32;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRect(
        .{ .x = 8, .y = 8, .w = 8, .h = 8 },
        null,
        .{ .paint = .{ .solid = .{ 0, 1, 0, 1 } }, .width = 8, .placement = .inside },
        .identity,
    );

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const center = ((12 * stride) + (12 * 4));
    try testing.expect(buf[center + 0] < 8);
    try testing.expect(buf[center + 1] > 200);
    try testing.expect(buf[center + 2] < 8);
    try testing.expect(buf[center + 3] > 200);
}

test "cpu renderer fills both demo eye stalks" {
    const testing = std.testing;

    const width: u32 = 360;
    const height: u32 = 180;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var stalk_a = snail.Path.init(testing.allocator);
    defer stalk_a.deinit();
    try stalk_a.moveTo(.{ .x = 308.0, .y = 100.0 });
    try stalk_a.quadTo(.{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 });

    var stalk_b = snail.Path.init(testing.allocator);
    defer stalk_b.deinit();
    try stalk_b.moveTo(.{ .x = 294.0, .y = 102.0 });
    try stalk_b.quadTo(.{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addStrokedPath(&stalk_a, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);
    try builder.addStrokedPath(&stalk_b, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const samples = [_]snail.Vec2{
        .{ .x = 318.5, .y = 77.5 },
        .{ .x = 299.0, .y = 81.5 },
    };

    for (samples) |sample| {
        const sx: i32 = @intFromFloat(@round(sample.x));
        const sy: i32 = @intFromFloat(@round(sample.y));
        var max_alpha: u8 = 0;
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                const x = sx + dx;
                const y = sy + dy;
                if (x < 0 or y < 0 or x >= width or y >= height) continue;
                const off = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x)) * 4;
                max_alpha = @max(max_alpha, buf[off + 3]);
            }
        }
        try testing.expect(max_alpha > 180);
    }
}

test "cpu renderer threaded draw matches single-threaded byte-for-byte" {
    const testing = std.testing;

    const width: u32 = 96;
    const height: u32 = 96;
    const stride = width * 4;

    var atlas = try snail.TextAtlas.init(testing.allocator, &.{.{ .data = @import("assets").noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "Hello, world!")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var blob_builder = snail.TextBlobBuilder.init(testing.allocator, &atlas);
    defer blob_builder.deinit();
    var shaped = try atlas.shapeText(testing.allocator, .{}, "Hello, world!");
    defer shaped.deinit();
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 32 }, .em = 16 },
        .fill = .{ .solid = .{ 1, 1, 1, 1 } },
    });
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 56 }, .em = 16 },
        .fill = .{ .solid = .{ 1, 0.4, 0.4, 1 } },
    });
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 80 }, .em = 16 },
        .fill = .{ .solid = .{ 0.4, 1, 0.4, 1 } },
    });
    var blob = try blob_builder.finish();
    defer blob.deinit();

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(.{ .x = 4, .y = 4, .w = width - 8, .h = 20 }, .{
        .paint = .{ .solid = .{ 0.2, 0.4, 0.8, 0.9 } },
    }, .{ .paint = .{ .solid = .{ 1, 1, 1, 1 } }, .width = 1.5 }, 4, .identity);
    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });
    try scene.addText(.{ .blob = &blob });

    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, @floatFromInt(width), @floatFromInt(height), 0, -1, 1),
        .target = .{
            .pixel_width = @floatFromInt(width),
            .pixel_height = @floatFromInt(height),
            .subpixel_order = .rgb,
            .encoding = .srgb,
        },
    };

    const serial_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(serial_buf);
    @memset(serial_buf, 0);

    var serial_cpu = CpuRenderer.init(serial_buf.ptr, width, height, stride);
    serial_cpu.setSubpixelOrder(.rgb);
    var serial_resources = try serial_cpu.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, blk: {
        var entries: [4]snail.ResourceSet.Entry = undefined;
        var set = snail.ResourceSet.init(&entries);
        try set.addScene(&scene);
        break :blk &set;
    });
    defer serial_resources.deinit();
    var serial_prepared = try snail.PreparedScene.initOwned(testing.allocator, &serial_resources, &scene, options);
    defer serial_prepared.deinit();
    try serial_cpu.drawPrepared(&serial_resources, &serial_prepared, options);

    var pool: snail.ThreadPool = undefined;
    try pool.init(testing.allocator, .{ .threads = 3 });
    defer pool.deinit();

    const threaded_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(threaded_buf);
    @memset(threaded_buf, 0);

    var threaded_cpu = CpuRenderer.init(threaded_buf.ptr, width, height, stride);
    threaded_cpu.setSubpixelOrder(.rgb);
    threaded_cpu.setThreadPool(&pool);
    var threaded_resources = try threaded_cpu.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, blk: {
        var entries: [4]snail.ResourceSet.Entry = undefined;
        var set = snail.ResourceSet.init(&entries);
        try set.addScene(&scene);
        break :blk &set;
    });
    defer threaded_resources.deinit();
    var threaded_prepared = try snail.PreparedScene.initOwned(testing.allocator, &threaded_resources, &scene, options);
    defer threaded_prepared.deinit();
    try threaded_cpu.drawPrepared(&threaded_resources, &threaded_prepared, options);

    try testing.expectEqualSlices(u8, serial_buf, threaded_buf);
}

test "cpu renderer drawPaths batch matches drawPathPicture" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 32;
    const stride = width * 4;

    // Reference: render via drawPathPicture.
    const ref_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(ref_buf);
    var ref_renderer = CpuRenderer.init(ref_buf.ptr, width, height, stride);
    ref_renderer.clear(0, 0, 0, 0);
    ref_renderer.setSubpixelOrder(.rgb);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 18, .h = 12 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    ref_renderer.drawPathPicture(&picture);

    // Comparison: render via drawPaths batch.
    const batch_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(batch_buf);
    var batch_renderer = CpuRenderer.init(batch_buf.ptr, width, height, stride);
    batch_renderer.clear(0, 0, 0, 0);
    batch_renderer.setSubpixelOrder(.rgb);

    var renderer = batch_renderer.asRenderer();
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });

    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .subpixel_order = .rgb, .encoding = .srgb },
    };
    const needed = snail.DrawList.estimate(&scene, options);
    const needed_segments = snail.DrawList.estimateSegments(&scene, options);
    const draw_buf = try testing.allocator.alloc(u32, needed);
    defer testing.allocator.free(draw_buf);
    const draw_segments = try testing.allocator.alloc(snail.DrawSegment, needed_segments);
    defer testing.allocator.free(draw_segments);
    var draw = snail.DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, options);
    try renderer.draw(&prepared, draw.slice(), options);

    const inside = ((12 * stride) + (16 * 4));
    try testing.expect(ref_buf[inside + 0] > 200);
    try testing.expect(batch_buf[inside + 0] > 200);
    try testing.expect(batch_buf[inside + 3] > 200);

    const outside = ((2 * stride) + (2 * 4));
    try testing.expectEqual(@as(u8, 0), batch_buf[outside + 0]);
    try testing.expectEqual(@as(u8, 0), batch_buf[outside + 3]);
}

test "cpu renderer applies path draw tint in prepared batches" {
    const testing = std.testing;

    const width: u32 = 32;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var cpu = CpuRenderer.init(buf.ptr, width, height, stride);
    cpu.clear(0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 6, .y = 5, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    const overrides = [_]snail.Override{.{ .tint = .{ 1, 0, 0, 0.5 } }};
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture, .instances = &overrides });

    var renderer = cpu.asRenderer();
    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .subpixel_order = .none, .encoding = .srgb },
    };
    var prepared_scene = try snail.PreparedScene.initOwned(testing.allocator, &prepared, &scene, options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);

    const inside = ((10 * stride) + (12 * 4));
    try testing.expect(buf[inside + 0] > 180);
    try testing.expect(buf[inside + 1] < 8);
    try testing.expect(buf[inside + 2] < 8);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}
