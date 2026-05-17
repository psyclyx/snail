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
const cpu_tile_frame = @import("tile_frame.zig");

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
        var ctx = cpu_tile_frame.Context(CpuRenderer){
            .self = self,
            .backend_prepared = backend_prepared,
            .records = records,
            .options = options,
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

pub const test_api = if (builtin.is_test) struct {
    pub const clear = CpuRenderer.clear;
    pub const drawPathPicture = CpuRenderer.drawPathPicture;
    pub const drawPathPictureTransformed = CpuRenderer.drawPathPictureTransformed;
    pub const drawGlyphId = CpuRenderer.drawGlyphId;
    pub const blendPremultipliedPixel = CpuRenderer.blendPremultipliedPixel;
} else struct {};
