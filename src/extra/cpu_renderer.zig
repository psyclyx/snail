//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).

const std = @import("std");
const snail = @import("snail");
const bezier = snail.bezier;
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

    /// Draw packed vector primitives in top-left pixel space.
    /// Supports the same per-primitive transforms as the GPU vector path.
    pub fn drawVector(self: *CpuRenderer, vertices: []const f32) void {
        var i: usize = 0;
        while (i + snail.VECTOR_FLOATS_PER_PRIMITIVE <= vertices.len) : (i += snail.VECTOR_FLOATS_PER_PRIMITIVE) {
            self.drawPackedVectorPrimitive(vertices[i .. i + snail.VECTOR_FLOATS_PER_PRIMITIVE]);
        }
    }

    pub fn drawVectorPicture(self: *CpuRenderer, picture: *const snail.VectorPicture) void {
        self.drawVector(picture.slice());
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
        if (gid == 0) return;
        const info = atlas.getGlyph(gid) orelse return;
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
                    if (max3(cov) < 1.0 / 255.0) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverageSubpixel(color, cov));
                }
            }
        }
    }

    fn drawPackedVectorPrimitive(self: *CpuRenderer, packed_primitive: []const f32) void {
        const primitive = PackedVectorPrimitive.fromSlice(packed_primitive) orelse return;
        if (primitive.rect.w <= 0 or primitive.rect.h <= 0) return;

        const inverse = inverseTransform(primitive.transform) orelse return;
        const bounds = primitive.pixelBounds();
        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), 0);
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.height)));
        if (px0 >= px1 or py0 >= py1) return;

        const epp = primitive.edgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        var row: u32 = @intCast(py0);
        while (row < @as(u32, @intCast(py1))) : (row += 1) {
            var col: u32 = @intCast(px0);
            while (col < @as(u32, @intCast(px1))) : (col += 1) {
                const world = Vec2.new(@as(f32, @floatFromInt(col)) + 0.5, @as(f32, @floatFromInt(row)) + 0.5);
                const local_world = inverse.applyPoint(world);
                const local_px = Vec2.new(local_world.x - primitive.rect.x, local_world.y - primitive.rect.y);
                const src = if (self.subpixel_order == .none)
                    primitive.sample(local_px, ppe, self.fill_rule)
                else
                    primitive.sampleSubpixel(local_px, epp, ppe, self.fill_rule, self.subpixel_order);
                if (src[3] < 1.0 / 255.0) continue;
                self.blendPremultipliedPixel(row, col, src);
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

const PackedVectorPrimitive = struct {
    rect: snail.VectorRect,
    fill: [4]f32,
    border: [4]f32,
    kind: snail.VectorPrimitiveKind,
    corner_radius: f32,
    border_width: f32,
    expand: f32,
    transform: Transform2D,

    fn fromSlice(packed_primitive: []const f32) ?PackedVectorPrimitive {
        if (packed_primitive.len < snail.VECTOR_FLOATS_PER_PRIMITIVE) return null;
        const kind_raw = @as(i32, @intFromFloat(@round(packed_primitive[12])));
        const kind = switch (kind_raw) {
            0 => snail.VectorPrimitiveKind.rect,
            1 => snail.VectorPrimitiveKind.rounded_rect,
            2 => snail.VectorPrimitiveKind.ellipse,
            else => return null,
        };

        return .{
            .rect = .{
                .x = packed_primitive[0],
                .y = packed_primitive[1],
                .w = packed_primitive[2],
                .h = packed_primitive[3],
            },
            .fill = .{ packed_primitive[4], packed_primitive[5], packed_primitive[6], packed_primitive[7] },
            .border = .{ packed_primitive[8], packed_primitive[9], packed_primitive[10], packed_primitive[11] },
            .kind = kind,
            .corner_radius = packed_primitive[13],
            .border_width = packed_primitive[14],
            .expand = packed_primitive[15],
            .transform = .{
                .xx = packed_primitive[16],
                .xy = packed_primitive[17],
                .tx = packed_primitive[18],
                .yx = packed_primitive[20],
                .yy = packed_primitive[21],
                .ty = packed_primitive[22],
            },
        };
    }

    fn pixelBounds(self: PackedVectorPrimitive) struct { min: Vec2, max: Vec2 } {
        const min_x = self.rect.x - self.expand;
        const min_y = self.rect.y - self.expand;
        const max_x = self.rect.x + self.rect.w + self.expand;
        const max_y = self.rect.y + self.rect.h + self.expand;
        const corners = [_]Vec2{
            self.transform.applyPoint(.{ .x = min_x, .y = min_y }),
            self.transform.applyPoint(.{ .x = max_x, .y = min_y }),
            self.transform.applyPoint(.{ .x = max_x, .y = max_y }),
            self.transform.applyPoint(.{ .x = min_x, .y = max_y }),
        };

        var min = corners[0];
        var max = corners[0];
        for (corners[1..]) |p| {
            min.x = @min(min.x, p.x);
            min.y = @min(min.y, p.y);
            max.x = @max(max.x, p.x);
            max.y = @max(max.y, p.y);
        }
        return .{ .min = min, .max = max };
    }

    fn edgePixelsPerPixel(self: PackedVectorPrimitive, inverse: Transform2D) Vec2 {
        _ = self;
        return Vec2.new(
            @max(@abs(inverse.xx) + @abs(inverse.xy), 1.0 / 65536.0),
            @max(@abs(inverse.yx) + @abs(inverse.yy), 1.0 / 65536.0),
        );
    }

    fn sample(self: PackedVectorPrimitive, local_px: Vec2, ppe: Vec2, fill_rule: FillRule) [4]f32 {
        const cov_parts = self.coverage(local_px, ppe, fill_rule);
        return addPremultiplied(
            premultiplyCoverage(self.border, cov_parts.border),
            premultiplyCoverage(self.fill, cov_parts.fill),
        );
    }

    fn sampleSubpixel(
        self: PackedVectorPrimitive,
        local_px: Vec2,
        epp: Vec2,
        ppe: Vec2,
        fill_rule: FillRule,
        subpixel_order: SubpixelOrder,
    ) [4]f32 {
        const cov_parts = self.coverageSubpixel(local_px, epp, ppe, fill_rule, subpixel_order);
        return addPremultiplied(
            premultiplyCoverageSubpixel(self.border, cov_parts.border),
            premultiplyCoverageSubpixel(self.fill, cov_parts.fill),
        );
    }

    fn coverage(self: PackedVectorPrimitive, local_px: Vec2, ppe: Vec2, fill_rule: FillRule) struct { fill: f32, border: f32 } {
        const path = self.pathLayout();
        const outer_cov = evalPathCoverage(local_px, ppe, path.kind, path.origin, path.size, path.radius, fill_rule);
        const inner_cov = if (path.has_inner)
            evalPathCoverage(local_px, ppe, path.kind, path.inner_origin, path.inner_size, path.inner_radius, fill_rule)
        else
            0.0;
        return .{
            .fill = if (path.border_width > 0.0) (if (path.has_inner) inner_cov else 0.0) else outer_cov,
            .border = if (path.border_width > 0.0) (if (path.has_inner) @max(outer_cov - inner_cov, 0.0) else outer_cov) else 0.0,
        };
    }

    fn coverageSubpixel(
        self: PackedVectorPrimitive,
        local_px: Vec2,
        epp: Vec2,
        ppe: Vec2,
        fill_rule: FillRule,
        subpixel_order: SubpixelOrder,
    ) struct { fill: [3]f32, border: [3]f32 } {
        const path = self.pathLayout();
        const outer_cov = evalPathCoverageSubpixel(local_px, epp, ppe, path.kind, path.origin, path.size, path.radius, fill_rule, subpixel_order);
        const inner_cov = if (path.has_inner)
            evalPathCoverageSubpixel(local_px, epp, ppe, path.kind, path.inner_origin, path.inner_size, path.inner_radius, fill_rule, subpixel_order)
        else
            .{ 0.0, 0.0, 0.0 };
        return .{
            .fill = if (path.border_width > 0.0) (if (path.has_inner) inner_cov else .{ 0.0, 0.0, 0.0 }) else outer_cov,
            .border = if (path.border_width > 0.0) (if (path.has_inner) max3Vec(sub3(outer_cov, inner_cov), .{ 0.0, 0.0, 0.0 }) else outer_cov) else .{ 0.0, 0.0, 0.0 },
        };
    }

    fn pathLayout(self: PackedVectorPrimitive) struct {
        kind: snail.VectorPrimitiveKind,
        origin: Vec2,
        size: Vec2,
        radius: f32,
        border_width: f32,
        inner_origin: Vec2,
        inner_size: Vec2,
        inner_radius: f32,
        has_inner: bool,
    } {
        const size = Vec2.new(@max(self.rect.w, 0.0), @max(self.rect.h, 0.0));
        const max_radius = @min(size.x, size.y) * 0.5;
        var radius = std.math.clamp(self.corner_radius, 0.0, max_radius);
        const border_width = std.math.clamp(self.border_width, 0.0, max_radius);
        if (self.kind == .rect) radius = 0.0;
        const inner_size = Vec2.new(
            @max(size.x - border_width * 2.0, 0.0),
            @max(size.y - border_width * 2.0, 0.0),
        );
        const inner_max_radius = @min(inner_size.x, inner_size.y) * 0.5;
        const inner_radius = if (self.kind == .rounded_rect)
            std.math.clamp(radius - border_width, 0.0, inner_max_radius)
        else
            0.0;
        return .{
            .kind = self.kind,
            .origin = Vec2.new(0.0, 0.0),
            .size = size,
            .radius = radius,
            .border_width = border_width,
            .inner_origin = Vec2.new(border_width, border_width),
            .inner_size = inner_size,
            .inner_radius = inner_radius,
            .has_inner = border_width > 0.0 and inner_size.x > 1.0 / 65536.0 and inner_size.y > 1.0 / 65536.0,
        };
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

// ---------------------------------------------------------------------------
// Slug algorithm: CPU port of evalGlyphCoverage from shaders.zig
// ---------------------------------------------------------------------------

const CoveragePair = struct {
    cov: f32,
    wgt: f32,
};

const QuadraticCurve = struct {
    p12: [4]f32,
    p3: Vec2,
};

const GlyphBandState = struct {
    h_loc: [2]u32,
    h_count: u32,
    v_loc: [2]u32,
    v_count: u32,
};

const kPathArcSegmentsPerCorner: usize = 4;
const kPathRoundedRectCurveCount: usize = 4 + kPathArcSegmentsPerCorner * 4;
const kPathEllipseSegmentCount: usize = 16;

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

fn blendSubpixel(cw_r: CoveragePair, cw_g: CoveragePair, cw_b: CoveragePair, cw_o: CoveragePair, fill_rule: FillRule) [3]f32 {
    const wsum_r = cw_r.wgt + cw_o.wgt;
    const wsum_g = cw_g.wgt + cw_o.wgt;
    const wsum_b = cw_b.wgt + cw_o.wgt;
    const blend_r = cw_r.cov * cw_r.wgt + cw_o.cov * cw_o.wgt;
    const blend_g = cw_g.cov * cw_g.wgt + cw_o.cov * cw_o.wgt;
    const blend_b = cw_b.cov * cw_b.wgt + cw_o.cov * cw_o.wgt;
    return .{
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

fn premultiplyCoverageSubpixel(color: [4]f32, cov: [3]f32) [4]f32 {
    return .{
        color[0] * color[3] * cov[0],
        color[1] * color[3] * cov[1],
        color[2] * color[3] * cov[2],
        color[3] * max3(cov),
    };
}

fn addPremultiplied(a: [4]f32, b: [4]f32) [4]f32 {
    return .{
        a[0] + b[0],
        a[1] + b[1],
        a[2] + b[2],
        a[3] + b[3],
    };
}

fn max3(values: [3]f32) f32 {
    return @max(values[0], @max(values[1], values[2]));
}

fn sub3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

fn max3Vec(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        @max(a[0], b[0]),
        @max(a[1], b[1]),
        @max(a[2], b[2]),
    };
}

fn makeLine(p0: Vec2, p1: Vec2) QuadraticCurve {
    return .{
        .p12 = .{ p0.x, p0.y, (p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5 },
        .p3 = p1,
    };
}

fn makeArc(center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) QuadraticCurve {
    const mid_angle = (start_angle + end_angle) * 0.5;
    const control_scale = 1.0 / @cos((end_angle - start_angle) * 0.5);
    const p0 = center.add(Vec2.new(@cos(start_angle) * radii.x, @sin(start_angle) * radii.y));
    const p1 = center.add(Vec2.new(@cos(mid_angle) * radii.x * control_scale, @sin(mid_angle) * radii.y * control_scale));
    const p2 = center.add(Vec2.new(@cos(end_angle) * radii.x, @sin(end_angle) * radii.y));
    return .{
        .p12 = .{ p0.x, p0.y, p1.x, p1.y },
        .p3 = p2,
    };
}

fn curveCountForPath(kind: snail.VectorPrimitiveKind, radius: f32) usize {
    return switch (kind) {
        .ellipse => kPathEllipseSegmentCount,
        .rounded_rect => if (radius > 1.0 / 65536.0) kPathRoundedRectCurveCount else 4,
        .rect => 4,
    };
}

fn getRectCurve(origin: Vec2, size: Vec2, segment: usize) QuadraticCurve {
    const p0 = origin;
    const p1 = origin.add(Vec2.new(size.x, 0.0));
    const p2 = origin.add(size);
    const p3 = origin.add(Vec2.new(0.0, size.y));
    return switch (segment) {
        0 => makeLine(p0, p1),
        1 => makeLine(p1, p2),
        2 => makeLine(p2, p3),
        else => makeLine(p3, p0),
    };
}

fn getRoundedRectCurve(origin: Vec2, size: Vec2, radius: f32, segment: usize) QuadraticCurve {
    if (radius <= 1.0 / 65536.0) return getRectCurve(origin, size, segment);

    const step = std.math.pi / 2.0 / @as(f32, @floatFromInt(kPathArcSegmentsPerCorner));
    const arc = Vec2.new(radius, radius);
    const top_left = origin.add(Vec2.new(radius, radius));
    const top_right = origin.add(Vec2.new(size.x - radius, radius));
    const bottom_right = origin.add(size).sub(Vec2.new(radius, radius));
    const bottom_left = origin.add(Vec2.new(radius, size.y - radius));

    var index = segment;
    if (index == 0) return makeLine(origin.add(Vec2.new(radius, 0.0)), origin.add(Vec2.new(size.x - radius, 0.0)));
    index -= 1;
    if (index < kPathArcSegmentsPerCorner) {
        const start_angle = -std.math.pi / 2.0 + @as(f32, @floatFromInt(index)) * step;
        return makeArc(top_right, arc, start_angle, start_angle + step);
    }
    index -= kPathArcSegmentsPerCorner;
    if (index == 0) return makeLine(origin.add(Vec2.new(size.x, radius)), origin.add(Vec2.new(size.x, size.y - radius)));
    index -= 1;
    if (index < kPathArcSegmentsPerCorner) {
        const start_angle = @as(f32, @floatFromInt(index)) * step;
        return makeArc(bottom_right, arc, start_angle, start_angle + step);
    }
    index -= kPathArcSegmentsPerCorner;
    if (index == 0) return makeLine(origin.add(Vec2.new(size.x - radius, size.y)), origin.add(Vec2.new(radius, size.y)));
    index -= 1;
    if (index < kPathArcSegmentsPerCorner) {
        const start_angle = std.math.pi / 2.0 + @as(f32, @floatFromInt(index)) * step;
        return makeArc(bottom_left, arc, start_angle, start_angle + step);
    }
    index -= kPathArcSegmentsPerCorner;
    if (index == 0) return makeLine(origin.add(Vec2.new(0.0, size.y - radius)), origin.add(Vec2.new(0.0, radius)));
    index -= 1;
    const start_angle = std.math.pi + @as(f32, @floatFromInt(index)) * step;
    return makeArc(top_left, arc, start_angle, start_angle + step);
}

fn getEllipseCurve(origin: Vec2, size: Vec2, segment: usize) QuadraticCurve {
    const step = std.math.pi * 2.0 / @as(f32, @floatFromInt(kPathEllipseSegmentCount));
    const start_angle = -std.math.pi / 2.0 + @as(f32, @floatFromInt(segment)) * step;
    return makeArc(origin.add(size.scale(0.5)), size.scale(0.5), start_angle, start_angle + step);
}

fn getPathCurve(kind: snail.VectorPrimitiveKind, origin: Vec2, size: Vec2, radius: f32, segment: usize) QuadraticCurve {
    return switch (kind) {
        .rect => getRectCurve(origin, size, segment),
        .rounded_rect => getRoundedRectCurve(origin, size, radius, segment),
        .ellipse => getEllipseCurve(origin, size, segment),
    };
}

fn evalPathHorizCoverage(rc: Vec2, x_offset: f32, ppe: Vec2, kind: snail.VectorPrimitiveKind, origin: Vec2, size: Vec2, radius: f32) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const sample_rc = Vec2.new(rc.x + x_offset, rc.y);
    const curve_count = curveCountForPath(kind, radius);
    var i: usize = 0;
    while (i < curve_count) : (i += 1) {
        const curve = getPathCurve(kind, origin, size, radius, i);
        const p1x = curve.p12[0] - sample_rc.x;
        const p1y = curve.p12[1] - sample_rc.y;
        const p2x = curve.p12[2] - sample_rc.x;
        const p2y = curve.p12[3] - sample_rc.y;
        const p3x = curve.p3.x - sample_rc.x;
        const p3y = curve.p3.y - sample_rc.y;
        const code = calcRootCode(p1y, p2y, p3y);
        if (code != 0) {
            const roots = solveHorizPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe.x);
            if ((code & 1) != 0) {
                result.cov += clamp01(roots[0] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[0]) * 2.0));
            }
            if (code > 1) {
                result.cov -= clamp01(roots[1] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[1]) * 2.0));
            }
        }
    }
    return result;
}

fn evalPathVertCoverage(rc: Vec2, y_offset: f32, ppe: Vec2, kind: snail.VectorPrimitiveKind, origin: Vec2, size: Vec2, radius: f32) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const sample_rc = Vec2.new(rc.x, rc.y + y_offset);
    const curve_count = curveCountForPath(kind, radius);
    var i: usize = 0;
    while (i < curve_count) : (i += 1) {
        const curve = getPathCurve(kind, origin, size, radius, i);
        const p1x = curve.p12[0] - sample_rc.x;
        const p1y = curve.p12[1] - sample_rc.y;
        const p2x = curve.p12[2] - sample_rc.x;
        const p2y = curve.p12[3] - sample_rc.y;
        const p3x = curve.p3.x - sample_rc.x;
        const p3y = curve.p3.y - sample_rc.y;
        const code = calcRootCode(p1x, p2x, p3x);
        if (code != 0) {
            const roots = solveVertPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe.y);
            if ((code & 1) != 0) {
                result.cov -= clamp01(roots[0] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[0]) * 2.0));
            }
            if (code > 1) {
                result.cov += clamp01(roots[1] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[1]) * 2.0));
            }
        }
    }
    return result;
}

fn evalPathCoverage(rc: Vec2, ppe: Vec2, kind: snail.VectorPrimitiveKind, origin: Vec2, size: Vec2, radius: f32, fill_rule: FillRule) f32 {
    return resolveCoverage(
        evalPathHorizCoverage(rc, 0.0, ppe, kind, origin, size, radius),
        evalPathVertCoverage(rc, 0.0, ppe, kind, origin, size, radius),
        fill_rule,
    );
}

fn evalPathCoverageSubpixel(
    rc: Vec2,
    epp: Vec2,
    ppe: Vec2,
    kind: snail.VectorPrimitiveKind,
    origin: Vec2,
    size: Vec2,
    radius: f32,
    fill_rule: FillRule,
    subpixel_order: SubpixelOrder,
) [3]f32 {
    return switch (subpixel_order) {
        .rgb, .bgr => blk: {
            const s: f32 = if (subpixel_order == .bgr) -1.0 else 1.0;
            const sp = epp.x / 3.0;
            break :blk blendSubpixel(
                evalPathHorizCoverage(rc, -sp * s, ppe, kind, origin, size, radius),
                evalPathHorizCoverage(rc, 0.0, ppe, kind, origin, size, radius),
                evalPathHorizCoverage(rc, sp * s, ppe, kind, origin, size, radius),
                evalPathVertCoverage(rc, 0.0, ppe, kind, origin, size, radius),
                fill_rule,
            );
        },
        .vrgb, .vbgr => blk: {
            const s: f32 = if (subpixel_order == .vbgr) -1.0 else 1.0;
            const sp = epp.y / 3.0;
            break :blk blendSubpixel(
                evalPathVertCoverage(rc, -sp * s, ppe, kind, origin, size, radius),
                evalPathVertCoverage(rc, 0.0, ppe, kind, origin, size, radius),
                evalPathVertCoverage(rc, sp * s, ppe, kind, origin, size, radius),
                evalPathHorizCoverage(rc, 0.0, ppe, kind, origin, size, radius),
                fill_rule,
            );
        },
        .none => .{ 0.0, 0.0, 0.0 },
    };
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

fn evalGlyphHorizCoverage(page: *const snail.AtlasPage, rc: Vec2, x_offset: f32, ppe_x: f32, state: GlyphBandState) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const sample_rc = Vec2.new(rc.x + x_offset, rc.y);
    var i: u32 = 0;
    while (i < state.h_count) : (i += 1) {
        const b_loc = calcBandLoc(state.h_loc[0], state.h_loc[1], i);
        const curve_ref = readBandTexel(page, b_loc[0], b_loc[1]);
        const p12 = readCurveTexelF32(page, curve_ref[0], curve_ref[1]);
        const p3 = readCurveTexelF32_p3(page, curve_ref[0] + 1, curve_ref[1]);
        const p1x = p12[0] - sample_rc.x;
        const p1y = p12[1] - sample_rc.y;
        const p2x = p12[2] - sample_rc.x;
        const p2y = p12[3] - sample_rc.y;
        const p3x = p3[0] - sample_rc.x;
        const p3y = p3[1] - sample_rc.y;
        if (@max(@max(p1x, p2x), p3x) * ppe_x < -0.5) break;
        const code = calcRootCode(p1y, p2y, p3y);
        if (code != 0) {
            const roots = solveHorizPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe_x);
            if ((code & 1) != 0) {
                result.cov += clamp01(roots[0] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[0]) * 2.0));
            }
            if (code > 1) {
                result.cov -= clamp01(roots[1] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[1]) * 2.0));
            }
        }
    }
    return result;
}

fn evalGlyphVertCoverage(page: *const snail.AtlasPage, rc: Vec2, y_offset: f32, ppe_y: f32, state: GlyphBandState) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const sample_rc = Vec2.new(rc.x, rc.y + y_offset);
    var i: u32 = 0;
    while (i < state.v_count) : (i += 1) {
        const b_loc = calcBandLoc(state.v_loc[0], state.v_loc[1], i);
        const curve_ref = readBandTexel(page, b_loc[0], b_loc[1]);
        const p12 = readCurveTexelF32(page, curve_ref[0], curve_ref[1]);
        const p3 = readCurveTexelF32_p3(page, curve_ref[0] + 1, curve_ref[1]);
        const p1x = p12[0] - sample_rc.x;
        const p1y = p12[1] - sample_rc.y;
        const p2x = p12[2] - sample_rc.x;
        const p2y = p12[3] - sample_rc.y;
        const p3x = p3[0] - sample_rc.x;
        const p3y = p3[1] - sample_rc.y;
        if (@max(@max(p1y, p2y), p3y) * ppe_y < -0.5) break;
        const code = calcRootCode(p1x, p2x, p3x);
        if (code != 0) {
            const roots = solveVertPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe_y);
            if ((code & 1) != 0) {
                result.cov -= clamp01(roots[0] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[0]) * 2.0));
            }
            if (code > 1) {
                result.cov += clamp01(roots[1] + 0.5);
                result.wgt = @max(result.wgt, clamp01(1.0 - @abs(roots[1]) * 2.0));
            }
        }
    }
    return result;
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
) [3]f32 {
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
        .none => .{ 0.0, 0.0, 0.0 },
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

/// Read curve texture texel 0 (p1.x, p1.y, p2.x, p2.y) as f32 values.
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

/// Read curve texture texel 1 (p3.x, p3.y) as f32 values.
fn readCurveTexelF32_p3(page: *const snail.AtlasPage, tx: u32, ty: u32) [2]f32 {
    const idx = (ty * page.curve_width + tx) * 4;
    if (idx + 1 >= page.curve_data.len) return .{ 0, 0 };
    return .{
        f16ToF32(page.curve_data[idx + 0]),
        f16ToF32(page.curve_data[idx + 1]),
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
        renderer.drawGlyph(&atlas, &font, @as(u32, ch), cursor_x, baseline_y, font_size, white);
        // Advance cursor
        const gid = font.glyphIndex(@as(u32, ch)) catch 0;
        if (atlas.getGlyph(gid)) |info| {
            cursor_x += @as(f32, @floatFromInt(info.advance_width)) * em_scale;
        } else {
            cursor_x += font_size * 0.5;
        }
    }

    // Verify non-zero pixels exist in the rendered area
    var non_zero_count: u32 = 0;
    for (buf) |byte| {
        if (byte != 0) non_zero_count += 1;
    }
    try testing.expect(non_zero_count > 100); // Glyphs should produce significant output
}

test "cpu renderer renders vector rect" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var shape_buf: [snail.VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = snail.VectorBatch.init(&shape_buf);
    try testing.expect(batch.addRect(
        .{ .x = 8, .y = 6, .w = 18, .h = 12 },
        .{ 1, 0, 0, 1 },
        .{ 0, 0, 0, 0 },
        0,
    ));

    renderer.drawVector(batch.slice());

    const inside = ((12 * stride) + (16 * 4));
    try testing.expect(buf[inside + 0] > 200);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] > 200);

    const outside = ((2 * stride) + (2 * 4));
    try testing.expectEqual(@as(u8, 0), buf[outside + 0]);
    try testing.expectEqual(@as(u8, 0), buf[outside + 3]);
}

test "cpu renderer renders transformed vector picture" {
    const testing = std.testing;

    const width: u32 = 64;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var shape_buf: [snail.VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = snail.VectorBatch.init(&shape_buf);
    try testing.expect(batch.addRectStyled(
        .{ .x = 0, .y = 0, .w = 10, .h = 8 },
        .{ .color = .{ 0, 1, 0, 1 } },
        null,
        .{ .tx = 20, .ty = 10 },
    ));

    var picture = try batch.freeze(testing.allocator);
    defer picture.deinit();

    renderer.drawVectorPicture(&picture);

    const translated = ((13 * stride) + (24 * 4));
    try testing.expect(buf[translated + 1] > 200);
    try testing.expect(buf[translated + 3] > 200);

    const original = ((3 * stride) + (4 * 4));
    try testing.expectEqual(@as(u8, 0), buf[original + 1]);
    try testing.expectEqual(@as(u8, 0), buf[original + 3]);
}

test "cpu renderer premultiplies translucent vector fill" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 28;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var shape_buf: [snail.VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = snail.VectorBatch.init(&shape_buf);
    try testing.expect(batch.addRect(
        .{ .x = 8, .y = 6, .w = 16, .h = 10 },
        .{ 1, 0, 0, 0.5 },
        .{ 0, 0, 0, 0 },
        0,
    ));

    renderer.drawVector(batch.slice());

    const inside = ((11 * stride) + (14 * 4));
    try testing.expect(buf[inside + 0] >= 185);
    try testing.expect(buf[inside + 0] <= 189);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}

test "cpu renderer renders collapsed interior as full border" {
    const testing = std.testing;

    const width: u32 = 32;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    renderer.clear(0, 0, 0, 0);

    var shape_buf: [snail.VECTOR_FLOATS_PER_PRIMITIVE]f32 = undefined;
    var batch = snail.VectorBatch.init(&shape_buf);
    try testing.expect(batch.addRect(
        .{ .x = 8, .y = 8, .w = 8, .h = 8 },
        .{ 1, 0, 0, 1 },
        .{ 0, 1, 0, 1 },
        8,
    ));

    renderer.drawVector(batch.slice());

    const center = ((12 * stride) + (12 * 4));
    try testing.expectEqual(@as(u8, 0), buf[center + 0]);
    try testing.expect(buf[center + 1] > 200);
    try testing.expectEqual(@as(u8, 0), buf[center + 2]);
    try testing.expect(buf[center + 3] > 200);
}
