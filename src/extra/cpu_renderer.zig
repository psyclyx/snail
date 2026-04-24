//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).

const std = @import("std");
const snail = @import("snail");
const bezier = snail.bezier;
const curve_tex = snail.curve_tex;
const CurveSegment = bezier.CurveSegment;
const GlyphBandEntry = std.meta.fieldInfo(snail.Atlas.GlyphInfo, .band_entry).type;
const Vec2 = snail.Vec2;
const Transform2D = snail.VectorTransform2D;
const FillRule = snail.FillRule;
const SubpixelOrder = snail.SubpixelOrder;

fn srgbToLinear(v: f32) f32 {
    if (v <= 0.04045) return v / 12.92;
    return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn linearToSrgb(v: f32) f32 {
    if (v <= 0.0031308) return v * 12.92;
    return 1.055 * std.math.pow(f32, v, 1.0 / 2.4) - 0.055;
}

const kLogBandTextureWidth: u5 = 12;
const BAND_TEX_WIDTH: u32 = 1 << kLogBandTextureWidth;
const kLogCurveTextureWidth: u5 = 12;
const CURVE_TEX_WIDTH: u32 = 1 << kLogCurveTextureWidth;

pub const CpuRenderer = struct {
    pixels: [*]u8, // RGBA8888 buffer, caller-owned
    width: u32,
    height: u32,
    stride: u32, // bytes per row (usually width * 4)
    fill_rule: FillRule,
    subpixel_order: SubpixelOrder,

    pub fn init(pixels: [*]u8, width: u32, height: u32, stride: u32) CpuRenderer {
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
            .fill_rule = .non_zero,
            .subpixel_order = .none,
        };
    }

    pub fn setFillRule(self: *CpuRenderer, rule: FillRule) void {
        self.fill_rule = rule;
    }

    pub fn fillRule(self: *const CpuRenderer) FillRule {
        return self.fill_rule;
    }

    pub fn setSubpixelOrder(self: *CpuRenderer, order: SubpixelOrder) void {
        self.subpixel_order = order;
    }

    pub fn subpixelOrder(self: *const CpuRenderer) SubpixelOrder {
        return self.subpixel_order;
    }

    pub fn setSubpixel(self: *CpuRenderer, enabled: bool) void {
        self.subpixel_order = if (enabled) .rgb else .none;
    }

    pub fn clear(self: *CpuRenderer, r: u8, g: u8, b: u8, a: u8) void {
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

    pub fn fillRect(self: *CpuRenderer, x: i32, y: i32, w: u32, h: u32, r: u8, g: u8, b: u8, a: u8) void {
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

    pub fn drawPathPicture(self: *CpuRenderer, picture: *const snail.PathPicture) void {
        self.drawPathPictureTransformed(picture, .identity);
    }

    pub fn drawPathPictureTransformed(self: *CpuRenderer, picture: *const snail.PathPicture, transform: Transform2D) void {
        for (picture.instances) |instance| {
            const info = picture.atlas.getGlyph(instance.glyph_id) orelse continue;
            const inverse = inverseTransform(Transform2D.multiply(transform, instance.transform)) orelse continue;
            const final_transform = Transform2D.multiply(transform, instance.transform);
            const bounds = transformedGlyphBounds(info.bbox, final_transform);
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), 0);
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.height)));
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
                    const paint = samplePathPaint(&picture.atlas, instance, local);

                    if (self.subpixel_order == .none) {
                        const cov = evalGlyphCoverage(
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
                        );
                        if (cov < 1.0 / 255.0) continue;
                        self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint, cov));
                    } else {
                        const cov = evalGlyphCoverageSubpixel(
                            page,
                            local.x,
                            local.y,
                            epp,
                            ppe,
                            info.band_entry,
                            band_max_h,
                            band_max_v,
                            self.fill_rule,
                            self.subpixel_order,
                        );
                        if (max3(cov.rgb) < 1.0 / 255.0) continue;
                        self.blendPremultipliedPixel(row, col, premultiplyCoverageSubpixel(paint, cov.rgb, cov.alpha));
                    }
                }
            }
        }
    }

    /// Render a single glyph using the Slug algorithm (CPU evaluation).
    /// Same inputs as snail.Batch.addGlyph -- uses atlas curve/band data.
    pub fn drawGlyph(
        self: *CpuRenderer,
        atlas: *const snail.Atlas,
        font: *const snail.Font,
        codepoint: u32,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32, // RGBA 0-1
    ) void {
        const gid = font.glyphIndex(codepoint) catch return;
        self.drawGlyphId(atlas, gid, x, y, font_size, color);
    }

    pub fn drawGlyphId(
        self: *CpuRenderer,
        atlas: *const snail.Atlas,
        glyph_id: u16,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) void {
        if (glyph_id == 0) return;
        const info = atlas.getGlyph(glyph_id) orelse return;
        self.drawGlyphInfo(atlas, info, x, y, font_size, color);
    }

    pub fn drawGlyphInfo(
        self: *CpuRenderer,
        atlas: *const snail.Atlas,
        info: snail.Atlas.GlyphInfo,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) void {
        if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return;
        self.renderGlyphInternal(atlas, info, x, y, font_size, color);
    }

    fn renderGlyphInternal(
        self: *CpuRenderer,
        atlas: *const snail.Atlas,
        info: snail.Atlas.GlyphInfo,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) void {
        const be = info.band_entry;
        const bbox = info.bbox;
        const page = atlas.page(info.page_index);

        // Scale from em-space to pixels
        const scale = font_size;

        // Glyph pixel bounds (screen-space, y-down for CPU buffer)
        // In em-space, bbox.min.y is the bottom. In screen y-down, that maps to higher y.
        const glyph_x0 = x + bbox.min.x * scale;
        const glyph_x1 = x + bbox.max.x * scale;
        // y parameter is the baseline (y-down). Em-space y goes up, screen y goes down.
        const glyph_y0 = y - bbox.max.y * scale; // top of glyph in screen coords
        const glyph_y1 = y - bbox.min.y * scale; // bottom of glyph in screen coords

        // Integer pixel bounds (clipped to buffer)
        const px0 = @max(@as(i32, @intFromFloat(@floor(glyph_x0))), 0);
        const px1 = @min(@as(i32, @intFromFloat(@ceil(glyph_x1))), @as(i32, @intCast(self.width)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(glyph_y0))), 0);
        const py1 = @min(@as(i32, @intFromFloat(@ceil(glyph_y1))), @as(i32, @intCast(self.height)));

        if (px0 >= px1 or py0 >= py1) return;

        // em-space units per pixel
        const epp_x: f32 = 1.0 / scale;
        const epp_y: f32 = 1.0 / scale;
        // pixels per em-unit
        const ppe_x: f32 = scale;
        const ppe_y: f32 = scale;

        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;

        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            while (col < @as(u32, @intCast(px1))) : (col += 1) {
                // Pixel center in em-space
                const px_f = @as(f32, @floatFromInt(col)) + 0.5;
                const py_f = @as(f32, @floatFromInt(row)) + 0.5;

                // Convert screen coords to em-space
                // screen_x = x + em_x * scale  =>  em_x = (screen_x - x) / scale
                // screen_y = y - em_y * scale   =>  em_y = (y - screen_y) / scale
                const em_x = (px_f - x) / scale;
                const em_y = (y - py_f) / scale;

                if (self.subpixel_order == .none) {
                    const cov = evalGlyphCoverage(
                        page,
                        em_x,
                        em_y,
                        epp_x,
                        epp_y,
                        ppe_x,
                        ppe_y,
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                    );
                    if (cov < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov));
                } else {
                    const cov = evalGlyphCoverageSubpixel(
                        page,
                        em_x,
                        em_y,
                        Vec2.new(epp_x, epp_y),
                        Vec2.new(ppe_x, ppe_y),
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                        self.subpixel_order,
                    );
                    if (max3(cov.rgb) < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverageSubpixel(color, cov.rgb, cov.alpha));
                }
            }
        }
    }

    fn blendPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32) void {
        const off = row * self.stride + col * 4;
        const dst_r = srgbToLinear(@as(f32, @floatFromInt(self.pixels[off + 0])) / 255.0);
        const dst_g = srgbToLinear(@as(f32, @floatFromInt(self.pixels[off + 1])) / 255.0);
        const dst_b = srgbToLinear(@as(f32, @floatFromInt(self.pixels[off + 2])) / 255.0);
        const dst_a = @as(f32, @floatFromInt(self.pixels[off + 3])) / 255.0;

        const src_a = clamp01(src[3]);
        const out_r = src[0] + dst_r * (1.0 - src_a);
        const out_g = src[1] + dst_g * (1.0 - src_a);
        const out_b = src[2] + dst_b * (1.0 - src_a);
        const out_a = src_a + dst_a * (1.0 - src_a);

        self.pixels[off + 0] = @intFromFloat(@min(@max(linearToSrgb(out_r) * 255.0, 0.0), 255.0));
        self.pixels[off + 1] = @intFromFloat(@min(@max(linearToSrgb(out_g) * 255.0, 0.0), 255.0));
        self.pixels[off + 2] = @intFromFloat(@min(@max(linearToSrgb(out_b) * 255.0, 0.0), 255.0));
        self.pixels[off + 3] = @intFromFloat(@min(@max(out_a * 255.0, 0.0), 255.0));
    }
};

fn inverseTransform(transform: Transform2D) ?Transform2D {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1.0 / 65536.0) return null;
    const inv_det = 1.0 / det;
    return .{
        .xx = transform.yy * inv_det,
        .xy = -transform.xy * inv_det,
        .tx = (transform.xy * transform.ty - transform.yy * transform.tx) * inv_det,
        .yx = -transform.yx * inv_det,
        .yy = transform.xx * inv_det,
        .ty = (transform.yx * transform.tx - transform.xx * transform.ty) * inv_det,
    };
}

fn transformedGlyphBounds(bbox: snail.BBox, transform: Transform2D) struct { min: Vec2, max: Vec2 } {
    const corners = [_]Vec2{
        transform.applyPoint(bbox.min),
        transform.applyPoint(.{ .x = bbox.max.x, .y = bbox.min.y }),
        transform.applyPoint(bbox.max),
        transform.applyPoint(.{ .x = bbox.min.x, .y = bbox.max.y }),
    };

    var min = corners[0];
    var max = corners[0];
    for (corners[1..]) |corner| {
        min.x = @min(min.x, corner.x);
        min.y = @min(min.y, corner.y);
        max.x = @max(max.x, corner.x);
        max.y = @max(max.y, corner.y);
    }
    return .{ .min = min, .max = max };
}

fn glyphEdgePixelsPerPixel(inverse: Transform2D) Vec2 {
    return .{
        .x = @max(@abs(inverse.xx) + @abs(inverse.xy), 1.0 / 65536.0),
        .y = @max(@abs(inverse.yx) + @abs(inverse.yy), 1.0 / 65536.0),
    };
}

fn fetchLayerInfoTexel(data: []const f32, width: u32, info_x: u16, info_y: u16, offset: u32) [4]f32 {
    const texel = @as(u32, info_x) + offset;
    const x = texel % width;
    const y = @as(u32, info_y) + texel / width;
    const base = (y * width + x) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

fn wrapPaintT(t: f32, extend_mode: snail.PathPaintExtend) f32 {
    return switch (extend_mode) {
        .clamp => clamp01(t),
        .repeat => t - @floor(t),
        .reflect => blk: {
            var reflected = @mod(t, 2.0);
            if (reflected < 0.0) reflected += 2.0;
            break :blk 1.0 - @abs(reflected - 1.0);
        },
    };
}

fn paintExtendFromFloat(raw: f32) snail.PathPaintExtend {
    const mode: i32 = @intFromFloat(@round(raw));
    return switch (mode) {
        1 => .repeat,
        2 => .reflect,
        else => .clamp,
    };
}

fn sampleImageTexelLinear(image: *const snail.Image, x: u32, y: u32) [4]f32 {
    const idx = (@as(usize, y) * @as(usize, image.width) + @as(usize, x)) * 4;
    return .{
        srgbToLinear(@as(f32, @floatFromInt(image.pixels[idx + 0])) / 255.0),
        srgbToLinear(@as(f32, @floatFromInt(image.pixels[idx + 1])) / 255.0),
        srgbToLinear(@as(f32, @floatFromInt(image.pixels[idx + 2])) / 255.0),
        @as(f32, @floatFromInt(image.pixels[idx + 3])) / 255.0,
    };
}

fn sampleImageLinear(image: *const snail.Image, uv: Vec2, filter: snail.ImageFilter) [4]f32 {
    if (image.width == 0 or image.height == 0) return .{ 0, 0, 0, 0 };
    if (filter == .nearest) {
        const x = @min(@as(u32, @intFromFloat(@max(@floor(uv.x * @as(f32, @floatFromInt(image.width))), 0.0))), image.width - 1);
        const y = @min(@as(u32, @intFromFloat(@max(@floor(uv.y * @as(f32, @floatFromInt(image.height))), 0.0))), image.height - 1);
        return sampleImageTexelLinear(image, x, y);
    }

    const fx = uv.x * @as(f32, @floatFromInt(image.width)) - 0.5;
    const fy = uv.y * @as(f32, @floatFromInt(image.height)) - 0.5;
    const x0 = @min(@as(u32, @intFromFloat(@max(@floor(fx), 0.0))), image.width - 1);
    const y0 = @min(@as(u32, @intFromFloat(@max(@floor(fy), 0.0))), image.height - 1);
    const x1 = @min(x0 + 1, image.width - 1);
    const y1 = @min(y0 + 1, image.height - 1);
    const tx = clamp01(fx - @floor(fx));
    const ty = clamp01(fy - @floor(fy));

    const c00 = sampleImageTexelLinear(image, x0, y0);
    const c10 = sampleImageTexelLinear(image, x1, y0);
    const c01 = sampleImageTexelLinear(image, x0, y1);
    const c11 = sampleImageTexelLinear(image, x1, y1);
    const top = lerpColor(c00, c10, tx);
    const bottom = lerpColor(c01, c11, tx);
    return lerpColor(top, bottom, ty);
}

fn samplePathPaint(atlas: *const snail.Atlas, instance: snail.PathPicture.Instance, local: Vec2) [4]f32 {
    const data = atlas.layer_info_data orelse return .{ 1, 1, 1, 1 };
    const width = atlas.layer_info_width;
    const info = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 0);
    const tag: i32 = @intFromFloat(@round(-info[3]));

    const data0 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 2);
    switch (tag) {
        1 => return data0,
        2 => {
            const color0 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 3);
            const color1 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 4);
            const extra = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 5);
            const start = Vec2.new(data0[0], data0[1]);
            const end = Vec2.new(data0[2], data0[3]);
            const delta = Vec2.sub(end, start);
            const len_sq = Vec2.dot(delta, delta);
            var t: f32 = 0.0;
            if (len_sq > 1e-10) t = Vec2.dot(Vec2.sub(local, start), delta) / len_sq;
            return lerpColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(extra[0])));
        },
        3 => {
            const color0 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 3);
            const color1 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 4);
            const center = Vec2.new(data0[0], data0[1]);
            const radius = @max(@abs(data0[2]), 1.0 / 65536.0);
            const t = Vec2.length(Vec2.sub(local, center)) / radius;
            return lerpColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(data0[3])));
        },
        4 => {
            const records = atlas.paint_image_records orelse return .{ 1, 0, 1, 1 };
            const record_index = (@as(usize, instance.info_y) * @as(usize, width) + @as(usize, instance.info_x)) / snail.PATH_PAINT_TEXELS_PER_RECORD;
            if (record_index >= records.len) return .{ 1, 0, 1, 1 };
            const record = records[record_index] orelse return .{ 1, 0, 1, 1 };
            const data1 = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 3);
            const tint = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 4);
            const extra = fetchLayerInfoTexel(data, width, instance.info_x, instance.info_y, 5);
            const raw_uv = Vec2.new(
                data0[0] * local.x + data0[1] * local.y + data0[2],
                data1[0] * local.x + data1[1] * local.y + data1[2],
            );
            const scale_x = if (@abs(extra[0]) > 1e-6) extra[0] else 1.0;
            const scale_y = if (@abs(extra[1]) > 1e-6) extra[1] else 1.0;
            const uv = Vec2.new(
                wrapPaintT(raw_uv.x, paintExtendFromFloat(extra[2])) * scale_x,
                wrapPaintT(raw_uv.y, paintExtendFromFloat(extra[3])) * scale_y,
            );
            const filter: snail.ImageFilter = if (@as(i32, @intFromFloat(@round(data1[3]))) == 1) .nearest else .linear;
            const sample = sampleImageLinear(record.image, uv, filter);
            return .{
                sample[0] * tint[0],
                sample[1] * tint[1],
                sample[2] * tint[2],
                sample[3] * tint[3],
            };
        },
        else => return .{ 1, 0, 1, 1 },
    }
}

// ---------------------------------------------------------------------------
// Slug algorithm: CPU port of evalGlyphCoverage from shaders.zig
// ---------------------------------------------------------------------------

const CoveragePair = struct {
    cov: f32,
    wgt: f32,
};

const GlyphBandState = struct {
    h_loc: [2]u32,
    h_count: u32,
    v_loc: [2]u32,
    v_count: u32,
};

const SubpixelCoverage = struct {
    rgb: [3]f32,
    alpha: f32,
};

const CurveRoots = struct {
    count: u8 = 0,
    t: [3]f32 = .{ 0, 0, 0 },
};

fn applyFillRule(fill_rule: FillRule, winding: f32) f32 {
    if (fill_rule == .even_odd) {
        const x = winding * 0.5;
        const frac = x - @floor(x);
        return 1.0 - @abs(frac * 2.0 - 1.0);
    }
    return @abs(winding);
}

fn resolveCoverage(horiz: CoveragePair, vert: CoveragePair, fill_rule: FillRule) f32 {
    const wsum = horiz.wgt + vert.wgt;
    const blended = horiz.cov * horiz.wgt + vert.cov * vert.wgt;
    const cov = @max(
        applyFillRule(fill_rule, blended / @max(wsum, 1.0 / 65536.0)),
        @min(applyFillRule(fill_rule, horiz.cov), applyFillRule(fill_rule, vert.cov)),
    );
    return clamp01(cov);
}

fn blendSubpixel(cw_r: CoveragePair, cw_g: CoveragePair, cw_b: CoveragePair, cw_o: CoveragePair, fill_rule: FillRule) SubpixelCoverage {
    const wsum_r = cw_r.wgt + cw_o.wgt;
    const wsum_g = cw_g.wgt + cw_o.wgt;
    const wsum_b = cw_b.wgt + cw_o.wgt;
    const blend_r = cw_r.cov * cw_r.wgt + cw_o.cov * cw_o.wgt;
    const blend_g = cw_g.cov * cw_g.wgt + cw_o.cov * cw_o.wgt;
    const blend_b = cw_b.cov * cw_b.wgt + cw_o.cov * cw_o.wgt;
    const alpha_wsum = cw_g.wgt + cw_o.wgt;
    const alpha_blended = cw_g.cov * cw_g.wgt + cw_o.cov * cw_o.wgt;
    return .{
        .rgb = .{
            clamp01(@max(
                applyFillRule(fill_rule, blend_r / @max(wsum_r, 1.0 / 65536.0)),
                @min(applyFillRule(fill_rule, cw_r.cov), applyFillRule(fill_rule, cw_o.cov)),
            )),
            clamp01(@max(
                applyFillRule(fill_rule, blend_g / @max(wsum_g, 1.0 / 65536.0)),
                @min(applyFillRule(fill_rule, cw_g.cov), applyFillRule(fill_rule, cw_o.cov)),
            )),
            clamp01(@max(
                applyFillRule(fill_rule, blend_b / @max(wsum_b, 1.0 / 65536.0)),
                @min(applyFillRule(fill_rule, cw_b.cov), applyFillRule(fill_rule, cw_o.cov)),
            )),
        },
        .alpha = clamp01(@max(
            applyFillRule(fill_rule, alpha_blended / @max(alpha_wsum, 1.0 / 65536.0)),
            @min(applyFillRule(fill_rule, cw_g.cov), applyFillRule(fill_rule, cw_o.cov)),
        )),
    };
}

fn premultiplyCoverage(color: [4]f32, cov: f32) [4]f32 {
    const alpha = color[3] * cov;
    return .{
        color[0] * alpha,
        color[1] * alpha,
        color[2] * alpha,
        alpha,
    };
}

fn premultiplyCoverageSubpixel(color: [4]f32, cov: [3]f32, alpha_cov: f32) [4]f32 {
    return .{
        color[0] * color[3] * cov[0],
        color[1] * color[3] * cov[1],
        color[2] * color[3] * cov[2],
        color[3] * clamp01(alpha_cov),
    };
}

fn lerpColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    };
}

fn max3(values: [3]f32) f32 {
    return @max(values[0], @max(values[1], values[2]));
}

fn initGlyphBandState(
    page: *const snail.AtlasPage,
    em_x: f32,
    em_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
) GlyphBandState {
    const band_idx_x_f = em_x * be.band_scale_x + be.band_offset_x;
    const band_idx_y_f = em_y * be.band_scale_y + be.band_offset_y;
    const band_idx_x = clampInt(@as(i32, @intFromFloat(@floor(band_idx_x_f))), 0, band_max_v);
    const band_idx_y = clampInt(@as(i32, @intFromFloat(@floor(band_idx_y_f))), 0, band_max_h);
    const glyph_x = @as(u32, be.glyph_x);
    const glyph_y = @as(u32, be.glyph_y);

    const h_header = readBandTexel(page, glyph_x + @as(u32, @intCast(band_idx_y)), glyph_y);
    const v_header = readBandTexel(page, glyph_x + @as(u32, @intCast(band_max_h)) + 1 + @as(u32, @intCast(band_idx_x)), glyph_y);
    return .{
        .h_loc = calcBandLoc(glyph_x, glyph_y, h_header[1]),
        .h_count = h_header[0],
        .v_loc = calcBandLoc(glyph_x, glyph_y, v_header[1]),
        .v_count = v_header[0],
    };
}

fn appendCurveRoot(roots: *CurveRoots, t: f32) void {
    if (t < -1e-5 or t > 1.0 + 1e-5) return;
    const clamped = std.math.clamp(t, 0.0, 1.0);
    for (roots.t[0..roots.count]) |existing| {
        if (@abs(existing - clamped) <= 1e-5) return;
    }
    var insert_at: usize = roots.count;
    while (insert_at > 0 and roots.t[insert_at - 1] > clamped) : (insert_at -= 1) {}
    var i = roots.count;
    while (i > insert_at) : (i -= 1) roots.t[i] = roots.t[i - 1];
    roots.t[insert_at] = clamped;
    roots.count += 1;
}

fn solveQuadraticRoots(a: f32, b: f32, c_val: f32) CurveRoots {
    var roots = CurveRoots{};
    if (@abs(a) < 1e-10) {
        if (@abs(b) < 1e-10) return roots;
        appendCurveRoot(&roots, -c_val / b);
        return roots;
    }
    var disc = b * b - 4.0 * a * c_val;
    if (disc < 0.0) {
        if (disc > -1e-6) {
            disc = 0.0;
        } else {
            return roots;
        }
    }
    const sqrt_disc = @sqrt(disc);
    const inv_2a = 0.5 / a;
    appendCurveRoot(&roots, (-b - sqrt_disc) * inv_2a);
    appendCurveRoot(&roots, (-b + sqrt_disc) * inv_2a);
    return roots;
}

fn cbrtSigned(v: f32) f32 {
    if (v == 0.0) return 0.0;
    return std.math.sign(v) * std.math.pow(f32, @abs(v), 1.0 / 3.0);
}

fn solveCubicRoots(a: f32, b: f32, c_val: f32, d: f32) CurveRoots {
    if (@abs(a) < 1e-10) return solveQuadraticRoots(b, c_val, d);

    var roots = CurveRoots{};
    const inv_a = 1.0 / a;
    const aa = b * inv_a;
    const bb = c_val * inv_a;
    const cc = d * inv_a;
    const third = 1.0 / 3.0;
    const p = bb - aa * aa * third;
    const q = (2.0 * aa * aa * aa) / 27.0 - (aa * bb) * third + cc;
    const half_q = q * 0.5;
    const third_p = p * third;
    const disc = half_q * half_q + third_p * third_p * third_p;
    const offset = aa * third;

    if (disc > 1e-8) {
        const sqrt_disc = @sqrt(disc);
        const u = cbrtSigned(-half_q + sqrt_disc);
        const v = cbrtSigned(-half_q - sqrt_disc);
        appendCurveRoot(&roots, u + v - offset);
        return roots;
    }

    if (disc >= -1e-8) {
        const u = cbrtSigned(-half_q);
        appendCurveRoot(&roots, 2.0 * u - offset);
        appendCurveRoot(&roots, -u - offset);
        return roots;
    }

    const r = @sqrt(-third_p);
    const phi = std.math.acos(std.math.clamp(-half_q / (r * r * r), -1.0, 1.0));
    const two_r = 2.0 * r;
    appendCurveRoot(&roots, two_r * @cos(phi * third) - offset);
    appendCurveRoot(&roots, two_r * @cos((phi + 2.0 * std.math.pi) * third) - offset);
    appendCurveRoot(&roots, two_r * @cos((phi + 4.0 * std.math.pi) * third) - offset);
    return roots;
}

fn solveSegmentHorizontalRoots(segment: CurveSegment, py: f32) CurveRoots {
    return switch (segment.kind) {
        .line => solveQuadraticRoots(0.0, segment.p2.y - segment.p0.y, segment.p0.y - py),
        .quadratic => blk: {
            const a = segment.p0.y - 2.0 * segment.p1.y + segment.p2.y;
            const b = 2.0 * (segment.p1.y - segment.p0.y);
            break :blk solveQuadraticRoots(a, b, segment.p0.y - py);
        },
        .conic => blk: {
            const c0 = segment.weights[0] * (segment.p0.y - py);
            const c1 = segment.weights[1] * (segment.p1.y - py);
            const c2 = segment.weights[2] * (segment.p2.y - py);
            break :blk solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
        },
        .cubic => blk: {
            const a = -segment.p0.y + 3.0 * segment.p1.y - 3.0 * segment.p2.y + segment.p3.y;
            const b = 3.0 * segment.p0.y - 6.0 * segment.p1.y + 3.0 * segment.p2.y;
            const c0 = -3.0 * segment.p0.y + 3.0 * segment.p1.y;
            const d = segment.p0.y - py;
            break :blk solveCubicRoots(a, b, c0, d);
        },
    };
}

fn solveSegmentVerticalRoots(segment: CurveSegment, px: f32) CurveRoots {
    return switch (segment.kind) {
        .line => solveQuadraticRoots(0.0, segment.p2.x - segment.p0.x, segment.p0.x - px),
        .quadratic => blk: {
            const a = segment.p0.x - 2.0 * segment.p1.x + segment.p2.x;
            const b = 2.0 * (segment.p1.x - segment.p0.x);
            break :blk solveQuadraticRoots(a, b, segment.p0.x - px);
        },
        .conic => blk: {
            const c0 = segment.weights[0] * (segment.p0.x - px);
            const c1 = segment.weights[1] * (segment.p1.x - px);
            const c2 = segment.weights[2] * (segment.p2.x - px);
            break :blk solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
        },
        .cubic => blk: {
            const a = -segment.p0.x + 3.0 * segment.p1.x - 3.0 * segment.p2.x + segment.p3.x;
            const b = 3.0 * segment.p0.x - 6.0 * segment.p1.x + 3.0 * segment.p2.x;
            const c0 = -3.0 * segment.p0.x + 3.0 * segment.p1.x;
            const d = segment.p0.x - px;
            break :blk solveCubicRoots(a, b, c0, d);
        },
    };
}

fn segmentMaxX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.x, segment.p2.x);
    var result = @max(@max(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @max(result, segment.p3.x);
    return result;
}

fn segmentMaxY(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.y, segment.p2.y);
    var result = @max(@max(segment.p0.y, segment.p1.y), segment.p2.y);
    if (segment.kind == .cubic) result = @max(result, segment.p3.y);
    return result;
}

fn appendCoverageContribution(result: *CoveragePair, distance: f32, sign: f32) void {
    result.cov += sign * clamp01(distance + 0.5);
    result.wgt = @max(result.wgt, clamp01(1.0 - @abs(distance) * 2.0));
}

fn evalGlyphCoverageAxis(page: *const snail.AtlasPage, sample_rc: Vec2, ppe: f32, loc: [2]u32, count: u32, horizontal: bool) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const b_loc = calcBandLoc(loc[0], loc[1], i);
        const curve_ref = readBandTexel(page, b_loc[0], b_loc[1]);
        const segment = readCurveSegment(page, curve_ref[0], curve_ref[1]);
        const max_coord = if (horizontal)
            segmentMaxX(segment) - sample_rc.x
        else
            segmentMaxY(segment) - sample_rc.y;
        if (max_coord * ppe < -0.5) break;

        if (segment.kind == .quadratic) {
            const p0x = segment.p0.x - sample_rc.x;
            const p0y = segment.p0.y - sample_rc.y;
            const p1x = segment.p1.x - sample_rc.x;
            const p1y = segment.p1.y - sample_rc.y;
            const p2x = segment.p2.x - sample_rc.x;
            const p2y = segment.p2.y - sample_rc.y;
            const code = if (horizontal)
                calcRootCode(p0y, p1y, p2y)
            else
                calcRootCode(p0x, p1x, p2x);
            if (code == 0) continue;

            const roots = if (horizontal)
                solveHorizPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
            else
                solveVertPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

            if ((code & 1) != 0) {
                appendCoverageContribution(&result, roots[0], if (horizontal) 1.0 else -1.0);
            }
            if (code > 1) {
                appendCoverageContribution(&result, roots[1], if (horizontal) -1.0 else 1.0);
            }
            continue;
        }

        const roots = if (horizontal)
            solveSegmentHorizontalRoots(segment, sample_rc.y)
        else
            solveSegmentVerticalRoots(segment, sample_rc.x);

        for (roots.t[0..roots.count]) |t| {
            if (t >= 1.0 - 1e-5) continue;
            const point = segment.evaluate(t);
            const deriv = segment.derivative(t);
            const derivative_axis = if (horizontal) deriv.y else -deriv.x;
            if (@abs(derivative_axis) <= 1e-5) continue;
            const distance = if (horizontal)
                (point.x - sample_rc.x) * ppe
            else
                (point.y - sample_rc.y) * ppe;
            appendCoverageContribution(&result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
        }
    }
    return result;
}

fn evalGlyphHorizCoverage(page: *const snail.AtlasPage, rc: Vec2, x_offset: f32, ppe_x: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x + x_offset, rc.y), ppe_x, state.h_loc, state.h_count, true);
}

fn evalGlyphVertCoverage(page: *const snail.AtlasPage, rc: Vec2, y_offset: f32, ppe_y: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x, rc.y + y_offset), ppe_y, state.v_loc, state.v_count, false);
}

fn evalGlyphCoverage(
    page: *const snail.AtlasPage,
    em_x: f32,
    em_y: f32,
    epp_x: f32,
    epp_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    _ = epp_x;
    _ = epp_y;
    const state = initGlyphBandState(page, em_x, em_y, be, band_max_h, band_max_v);
    return resolveCoverage(
        evalGlyphHorizCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_x, state),
        evalGlyphVertCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_y, state),
        fill_rule,
    );
}

fn evalGlyphCoverageSubpixel(
    page: *const snail.AtlasPage,
    em_x: f32,
    em_y: f32,
    epp: Vec2,
    ppe: Vec2,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
    subpixel_order: SubpixelOrder,
) SubpixelCoverage {
    const rc = Vec2.new(em_x, em_y);
    const state = initGlyphBandState(page, em_x, em_y, be, band_max_h, band_max_v);
    return switch (subpixel_order) {
        .rgb, .bgr => blk: {
            const s: f32 = if (subpixel_order == .bgr) -1.0 else 1.0;
            const sp = epp.x / 3.0;
            break :blk blendSubpixel(
                evalGlyphHorizCoverage(page, rc, -sp * s, ppe.x, state),
                evalGlyphHorizCoverage(page, rc, 0.0, ppe.x, state),
                evalGlyphHorizCoverage(page, rc, sp * s, ppe.x, state),
                evalGlyphVertCoverage(page, rc, 0.0, ppe.y, state),
                fill_rule,
            );
        },
        .vrgb, .vbgr => blk: {
            const s: f32 = if (subpixel_order == .vbgr) -1.0 else 1.0;
            const sp = epp.y / 3.0;
            break :blk blendSubpixel(
                evalGlyphVertCoverage(page, rc, -sp * s, ppe.y, state),
                evalGlyphVertCoverage(page, rc, 0.0, ppe.y, state),
                evalGlyphVertCoverage(page, rc, sp * s, ppe.y, state),
                evalGlyphHorizCoverage(page, rc, 0.0, ppe.x, state),
                fill_rule,
            );
        },
        .none => .{ .rgb = .{ 0.0, 0.0, 0.0 }, .alpha = 0.0 },
    };
}

// ---------------------------------------------------------------------------
// Texture access helpers
// ---------------------------------------------------------------------------

/// Read a band texture texel (RG16UI) at the given texel coordinates.
/// The band texture is laid out as a 1D array of u16 pairs, row-major.
fn readBandTexel(page: *const snail.AtlasPage, tx: u32, ty: u32) [2]u32 {
    const idx = (ty * page.band_width + tx) * 2;
    if (idx + 1 >= page.band_data.len) return .{ 0, 0 };
    return .{
        @as(u32, page.band_data[idx]),
        @as(u32, page.band_data[idx + 1]),
    };
}

/// Read one curve texture texel as f32 values.
fn readCurveTexelF32(page: *const snail.AtlasPage, tx: u32, ty: u32) [4]f32 {
    const idx = (ty * page.curve_width + tx) * 4;
    if (idx + 3 >= page.curve_data.len) return .{ 0, 0, 0, 0 };
    return .{
        f16ToF32(page.curve_data[idx + 0]),
        f16ToF32(page.curve_data[idx + 1]),
        f16ToF32(page.curve_data[idx + 2]),
        f16ToF32(page.curve_data[idx + 3]),
    };
}

fn readCurveTexelF32_meta(page: *const snail.AtlasPage, tx: u32, ty: u32) [4]f32 {
    return readCurveTexelF32(page, tx, ty);
}

fn calcCurveLoc(glyph_x: u32, glyph_y: u32, offset: u32) [2]u32 {
    var loc_x = glyph_x + offset;
    var loc_y = glyph_y;
    loc_y += loc_x >> kLogCurveTextureWidth;
    loc_x &= CURVE_TEX_WIDTH - 1;
    return .{ loc_x, loc_y };
}

fn readCurveSegment(page: *const snail.AtlasPage, tx: u32, ty: u32) CurveSegment {
    const tex0 = readCurveTexelF32(page, tx, ty);
    const loc1 = calcCurveLoc(tx, ty, 1);
    const tex1 = readCurveTexelF32(page, loc1[0], loc1[1]);
    const loc2 = calcCurveLoc(tx, ty, 2);
    const tex2 = readCurveTexelF32(page, loc2[0], loc2[1]);
    const loc3 = calcCurveLoc(tx, ty, 3);
    const meta = readCurveTexelF32_meta(page, loc3[0], loc3[1]);
    const stored_kind = tex2[2];
    const kind_u16: u16 = @intCast(if (stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5)
        @as(i32, @intFromFloat(@round(stored_kind - curve_tex.DIRECT_ENCODING_KIND_BIAS)))
    else
        @as(i32, @intFromFloat(@round(stored_kind))));
    const kind: bezier.CurveKind = switch (kind_u16) {
        1 => .conic,
        2 => .cubic,
        3 => .line,
        else => .quadratic,
    };
    if (stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5) {
        return .{
            .kind = kind,
            .p0 = .{ .x = tex0[0], .y = tex0[1] },
            .p1 = .{ .x = tex0[2], .y = tex0[3] },
            .p2 = .{ .x = tex1[0], .y = tex1[1] },
            .p3 = .{ .x = tex1[2], .y = tex1[3] },
            .weights = .{ tex2[3], meta[0], meta[1] },
        };
    }

    const p0 = curve_tex.decodePackedAnchor(
        .{ .x = tex0[0], .y = tex0[1] },
        .{ .x = tex0[2], .y = tex0[3] },
    );
    return .{
        .kind = kind,
        .p0 = p0,
        .p1 = .{ .x = p0.x + tex1[0], .y = p0.y + tex1[1] },
        .p2 = .{ .x = p0.x + tex1[2], .y = p0.y + tex1[3] },
        .p3 = .{ .x = p0.x + tex2[0], .y = p0.y + tex2[1] },
        .weights = .{ tex2[3], meta[0], meta[1] },
    };
}

/// Calculate band texture location with row wrapping.
fn calcBandLoc(glyph_x: u32, glyph_y: u32, offset: u32) [2]u32 {
    var loc_x = glyph_x + offset;
    var loc_y = glyph_y;
    loc_y += loc_x >> kLogBandTextureWidth;
    loc_x &= BAND_TEX_WIDTH - 1;
    return .{ loc_x, loc_y };
}

// ---------------------------------------------------------------------------
// Slug math helpers (ported from GLSL)
// ---------------------------------------------------------------------------

/// Root code from sign bits of the three y-coordinates (relative to ray).
/// Encodes whether 0, 1, or 2 roots contribute to coverage.
/// Returns: 0 = no roots, 1 = first root only, 0x0100 = second root only, 0x0101 = both.
fn calcRootCode(y1: f32, y2: f32, y3: f32) u16 {
    const s1: u32 = @as(u32, @bitCast(y1)) >> 31;
    const s2: u32 = @as(u32, @bitCast(y2)) >> 30;
    const s3: u32 = @as(u32, @bitCast(y3)) >> 29;

    // Replicate the GLSL bit manipulation
    const shift_a: u32 = (s2 & 2) | (s1 & ~@as(u32, 2));
    const shift: u32 = (s3 & 4) | (shift_a & ~@as(u32, 4));

    return @as(u16, @intCast((@as(u32, 0x2E74) >> @as(u5, @intCast(shift & 0x1F))) & 0x0101));
    // The GLSL uses 0x0101 mask on a u16 shift result. We want the low byte.
}

/// Solve horizontal polynomial: find x-intersections for a horizontal ray.
/// p12 = (p1.x, p1.y, p2.x, p2.y), p3 = (p3.x, p3.y), all relative to pixel.
/// Returns two x-distances scaled by ppe_x.
fn solveHorizPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_x: f32) [2]f32 {
    const ax = p1x - p2x * 2.0 + p3x;
    const ay = p1y - p2y * 2.0 + p3y;
    const bx = p1x - p2x;
    const by = p1y - p2y;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ay) < 1.0 / 65536.0) {
        // Linear fallback
        const rb = 0.5 / by;
        t1 = p1y * rb;
        t2 = t1;
    } else {
        const ra = 1.0 / ay;
        const d = @sqrt(@max(by * by - ay * p1y, 0.0));
        t1 = (by - d) * ra;
        t2 = (by + d) * ra;
    }

    const x1 = (ax * t1 - bx * 2.0) * t1 + p1x;
    const x2 = (ax * t2 - bx * 2.0) * t2 + p1x;
    return .{ x1 * ppe_x, x2 * ppe_x };
}

/// Solve vertical polynomial: find y-intersections for a vertical ray.
fn solveVertPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_y: f32) [2]f32 {
    const ax = p1x - p2x * 2.0 + p3x;
    const ay = p1y - p2y * 2.0 + p3y;
    const bx = p1x - p2x;
    const by = p1y - p2y;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ax) < 1.0 / 65536.0) {
        const rb = 0.5 / bx;
        t1 = p1x * rb;
        t2 = t1;
    } else {
        const ra = 1.0 / ax;
        const d = @sqrt(@max(bx * bx - ax * p1x, 0.0));
        t1 = (bx - d) * ra;
        t2 = (bx + d) * ra;
    }

    const y1 = (ay * t1 - by * 2.0) * t1 + p1y;
    const y2 = (ay * t2 - by * 2.0) * t2 + p1y;
    return .{ y1 * ppe_y, y2 * ppe_y };
}

// ---------------------------------------------------------------------------
// Numeric utilities
// ---------------------------------------------------------------------------

fn clamp01(v: f32) f32 {
    return std.math.clamp(v, 0.0, 1.0);
}

fn clampInt(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}

/// Convert IEEE 754 binary16 (half-float) to f32.
fn f16ToF32(h: u16) f32 {
    const sign: u32 = @as(u32, h & 0x8000) << 16;
    const exp_bits: u32 = (h >> 10) & 0x1F;
    const mant: u32 = @as(u32, h & 0x3FF);

    if (exp_bits == 0) {
        if (mant == 0) {
            // Zero
            return @bitCast(sign);
        }
        // Subnormal: normalize
        var m = mant;
        var e: u32 = 1;
        while (m & 0x400 == 0) {
            m <<= 1;
            e += 1;
        }
        const exp32: u32 = (127 - 15 + 1 - e) << 23;
        const mant32: u32 = (m & 0x3FF) << 13;
        return @bitCast(sign | exp32 | mant32);
    } else if (exp_bits == 0x1F) {
        // Inf/NaN
        return @bitCast(sign | 0x7F800000 | (mant << 13));
    }

    const exp32: u32 = (exp_bits + 127 - 15) << 23;
    const mant32: u32 = mant << 13;
    return @bitCast(sign | exp32 | mant32);
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

    // Build atlas with ASCII
    var atlas = try snail.Atlas.initAscii(testing.allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    const width: u32 = 200;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    // Render "Hello" at a reasonable size
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

    // Verify non-zero pixels exist in the rendered area
    var non_zero_count: u32 = 0;
    for (buf) |byte| {
        if (byte != 0) non_zero_count += 1;
    }
    try testing.expect(non_zero_count > 100); // Glyphs should produce significant output
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
        .color = .{ 1, 0, 0, 1 },
    }, .identity);

    var picture = try builder.freeze(testing.allocator);
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
        .color = .{ 0, 1, 0, 1 },
    }, .identity);

    var picture = try builder.freeze(testing.allocator);
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
        .{ .color = .{ 1, 1, 1, 0.5 }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .identity,
    );
    var absolute_picture = try absolute_builder.freeze(testing.allocator);
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
        .{ .color = .{ 1, 1, 1, 0.5 }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .{ .tx = 64, .ty = 40 },
    );
    var transformed_picture = try transformed_builder.freeze(testing.allocator);
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
        .{ .color = .{ 0.2, 0.7, 0.9, 1.0 } },
        null,
        8.0,
        .identity,
    );
    var picture = try builder.freeze(testing.allocator);
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

    var large_path = snail.VectorPath.init(testing.allocator);
    defer large_path.deinit();
    try large_path.moveTo(.{ .x = 0, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 0 }, .{ .x = 64 * 64, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 80 * 64 }, .{ .x = 0, .y = 40 * 64 });
    try large_path.close();

    var large_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer large_builder.deinit();
    try large_builder.addFilledPath(
        &large_path,
        .{ .color = .{ 0.95, 0.55, 0.15, 1.0 } },
        Transform2D.multiply(
            Transform2D.translate(24, 28),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(testing.allocator);
    defer large_picture.deinit();

    var normalized_path = snail.VectorPath.init(testing.allocator);
    defer normalized_path.deinit();
    try normalized_path.moveTo(.{ .x = 0, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 0 }, .{ .x = 64, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 80 }, .{ .x = 0, .y = 40 });
    try normalized_path.close();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addFilledPath(
        &normalized_path,
        .{ .color = .{ 0.95, 0.55, 0.15, 1.0 } },
        Transform2D.translate(24, 28),
    );
    var normalized_picture = try normalized_builder.freeze(testing.allocator);
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
        .{ .color = .{ 0.33, 0.39, 0.36, 0.92 } },
        .{ .color = .{ 0.79, 0.86, 0.78, 1.0 }, .width = 2.0 * 64.0, .join = .round, .placement = .inside },
        20.0 * 64.0,
        Transform2D.multiply(
            Transform2D.translate(20, 24),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(testing.allocator);
    defer large_picture.deinit();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 180, .h = 40 },
        .{ .color = .{ 0.33, 0.39, 0.36, 0.92 } },
        .{ .color = .{ 0.79, 0.86, 0.78, 1.0 }, .width = 2.0, .join = .round, .placement = .inside },
        20.0,
        Transform2D.translate(20, 24),
    );
    var normalized_picture = try normalized_builder.freeze(testing.allocator);
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

    var path = snail.VectorPath.init(testing.allocator);
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

    var picture = try builder.freeze(testing.allocator);
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (26 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);
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

    var image = try snail.Image.initRgba8(testing.allocator, 2, 1, &.{
        255, 0, 0,   255,
        0,   0, 255, 255,
    });
    defer image.deinit();

    var path = snail.VectorPath.init(testing.allocator);
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

    var picture = try builder.freeze(testing.allocator);
    defer picture.deinit();

    renderer.drawPathPicture(&picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (22 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);
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
        .color = .{ 1, 0, 0, 0.5 },
    }, .identity);

    var picture = try builder.freeze(testing.allocator);
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
        .{ .color = .{ 0, 1, 0, 1 }, .width = 8, .placement = .inside },
        .identity,
    );

    var picture = try builder.freeze(testing.allocator);
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

    var stalk_a = snail.VectorPath.init(testing.allocator);
    defer stalk_a.deinit();
    try stalk_a.moveTo(.{ .x = 308.0, .y = 100.0 });
    try stalk_a.quadTo(.{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 });

    var stalk_b = snail.VectorPath.init(testing.allocator);
    defer stalk_b.deinit();
    try stalk_b.moveTo(.{ .x = 294.0, .y = 102.0 });
    try stalk_b.quadTo(.{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addStrokedPath(&stalk_a, .{
        .color = .{ 1, 1, 1, 1 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);
    try builder.addStrokedPath(&stalk_b, .{
        .color = .{ 1, 1, 1, 1 },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(testing.allocator);
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
