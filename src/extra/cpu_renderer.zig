//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).

const std = @import("std");
const snail = @import("snail");
const bezier = snail.bezier;
const GlyphBandEntry = std.meta.fieldInfo(snail.Atlas.GlyphInfo, .band_entry).type;

const kLogBandTextureWidth: u5 = 12;
const BAND_TEX_WIDTH: u32 = 1 << kLogBandTextureWidth;

pub const CpuRenderer = struct {
    pixels: [*]u8, // RGBA8888 buffer, caller-owned
    width: u32,
    height: u32,
    stride: u32, // bytes per row (usually width * 4)

    pub fn init(pixels: [*]u8, width: u32, height: u32, stride: u32) CpuRenderer {
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
        };
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

                const cov = evalGlyphCoverage(
                    atlas,
                    em_x,
                    em_y,
                    epp_x,
                    epp_y,
                    ppe_x,
                    ppe_y,
                    be,
                    band_max_h,
                    band_max_v,
                );

                if (cov < 1.0 / 255.0) continue;

                // Alpha-blend into buffer
                const off = row * self.stride + col * 4;
                const src_a = color[3] * cov;
                const dst_r = @as(f32, @floatFromInt(self.pixels[off + 0])) / 255.0;
                const dst_g = @as(f32, @floatFromInt(self.pixels[off + 1])) / 255.0;
                const dst_b = @as(f32, @floatFromInt(self.pixels[off + 2])) / 255.0;
                const dst_a = @as(f32, @floatFromInt(self.pixels[off + 3])) / 255.0;

                const out_r = color[0] * src_a + dst_r * (1.0 - src_a);
                const out_g = color[1] * src_a + dst_g * (1.0 - src_a);
                const out_b = color[2] * src_a + dst_b * (1.0 - src_a);
                const out_a = src_a + dst_a * (1.0 - src_a);

                self.pixels[off + 0] = @intFromFloat(@min(@max(out_r * 255.0, 0.0), 255.0));
                self.pixels[off + 1] = @intFromFloat(@min(@max(out_g * 255.0, 0.0), 255.0));
                self.pixels[off + 2] = @intFromFloat(@min(@max(out_b * 255.0, 0.0), 255.0));
                self.pixels[off + 3] = @intFromFloat(@min(@max(out_a * 255.0, 0.0), 255.0));
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Slug algorithm: CPU port of evalGlyphCoverage from shaders.zig
// ---------------------------------------------------------------------------

fn evalGlyphCoverage(
    atlas: *const snail.Atlas,
    em_x: f32,
    em_y: f32,
    epp_x: f32,
    epp_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
) f32 {
    _ = epp_x;
    _ = epp_y;

    // Determine band indices
    const band_idx_x_f = em_x * be.band_scale_x + be.band_offset_x;
    const band_idx_y_f = em_y * be.band_scale_y + be.band_offset_y;
    const band_idx_x = clampInt(@as(i32, @intFromFloat(@floor(band_idx_x_f))), 0, band_max_v);
    const band_idx_y = clampInt(@as(i32, @intFromFloat(@floor(band_idx_y_f))), 0, band_max_h);

    const glyph_x = @as(u32, be.glyph_x);
    const glyph_y = @as(u32, be.glyph_y);

    // --- Horizontal coverage (ray in x direction, finds vertical edges) ---
    var xcov: f32 = 0.0;
    var xwgt: f32 = 0.0;
    {
        // Horizontal band header is at glyph_loc + band_idx_y (index into h bands)
        const h_header_pos = glyph_x + @as(u32, @intCast(band_idx_y));
        const h_header = readBandTexel(atlas, h_header_pos, glyph_y);
        const h_count = h_header[0];
        const h_offset = h_header[1];

        const h_loc = calcBandLoc(glyph_x, glyph_y, h_offset);

        var i: u32 = 0;
        while (i < h_count) : (i += 1) {
            const b_loc = calcBandLoc(h_loc[0], h_loc[1], @intCast(i));
            const curve_ref = readBandTexel(atlas, b_loc[0], b_loc[1]);
            const curve_loc_x = curve_ref[0];
            const curve_loc_y = curve_ref[1];

            // Read curve control points (em-space), translate relative to pixel
            const p12 = readCurveTexelF32(atlas, curve_loc_x, curve_loc_y);
            const p3 = readCurveTexelF32_p3(atlas, curve_loc_x + 1, curve_loc_y);

            const p1x = p12[0] - em_x;
            const p1y = p12[1] - em_y;
            const p2x = p12[2] - em_x;
            const p2y = p12[3] - em_y;
            const p3x = p3[0] - em_x;
            const p3y = p3[1] - em_y;

            // Early exit: all control points to the left
            if (@max(@max(p1x, p2x), p3x) * ppe_x < -0.5) break;

            // Root code from sign bits
            const code = calcRootCode(p1y, p2y, p3y);
            if (code != 0) {
                const r = solveHorizPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe_x);
                if ((code & 1) != 0) {
                    xcov += clamp01(r[0] + 0.5);
                    xwgt = @max(xwgt, clamp01(1.0 - @abs(r[0]) * 2.0));
                }
                if (code > 1) {
                    xcov -= clamp01(r[1] + 0.5);
                    xwgt = @max(xwgt, clamp01(1.0 - @abs(r[1]) * 2.0));
                }
            }
        }
    }

    // --- Vertical coverage (ray in y direction, finds horizontal edges) ---
    var ycov: f32 = 0.0;
    var ywgt: f32 = 0.0;
    {
        // Vertical band header is at glyph_loc + (h_band_count) + band_idx_x
        const v_header_pos = glyph_x + @as(u32, @intCast(band_max_h)) + 1 + @as(u32, @intCast(band_idx_x));
        const v_header = readBandTexel(atlas, v_header_pos, glyph_y);
        const v_count = v_header[0];
        const v_offset = v_header[1];

        const v_loc = calcBandLoc(glyph_x, glyph_y, v_offset);

        var i: u32 = 0;
        while (i < v_count) : (i += 1) {
            const b_loc = calcBandLoc(v_loc[0], v_loc[1], @intCast(i));
            const curve_ref = readBandTexel(atlas, b_loc[0], b_loc[1]);
            const curve_loc_x = curve_ref[0];
            const curve_loc_y = curve_ref[1];

            const p12 = readCurveTexelF32(atlas, curve_loc_x, curve_loc_y);
            const p3 = readCurveTexelF32_p3(atlas, curve_loc_x + 1, curve_loc_y);

            const p1x = p12[0] - em_x;
            const p1y = p12[1] - em_y;
            const p2x = p12[2] - em_x;
            const p2y = p12[3] - em_y;
            const p3x = p3[0] - em_x;
            const p3y = p3[1] - em_y;

            // Early exit: all control points above
            if (@max(@max(p1y, p2y), p3y) * ppe_y < -0.5) break;

            const code = calcRootCode(p1x, p2x, p3x);
            if (code != 0) {
                const r = solveVertPoly(p1x, p1y, p2x, p2y, p3x, p3y, ppe_y);
                if ((code & 1) != 0) {
                    ycov -= clamp01(r[0] + 0.5);
                    ywgt = @max(ywgt, clamp01(1.0 - @abs(r[0]) * 2.0));
                }
                if (code > 1) {
                    ycov += clamp01(r[1] + 0.5);
                    ywgt = @max(ywgt, clamp01(1.0 - @abs(r[1]) * 2.0));
                }
            }
        }
    }

    // Combine horizontal and vertical coverage
    const wsum = xwgt + ywgt;
    const blended = xcov * xwgt + ycov * ywgt;
    const cov = @max(
        @abs(blended / @max(wsum, 1.0 / 65536.0)),
        @min(@abs(xcov), @abs(ycov)),
    );
    return std.math.clamp(cov, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Texture access helpers
// ---------------------------------------------------------------------------

/// Read a band texture texel (RG16UI) at the given texel coordinates.
/// The band texture is laid out as a 1D array of u16 pairs, row-major.
fn readBandTexel(atlas: *const snail.Atlas, tx: u32, ty: u32) [2]u32 {
    const idx = (ty * atlas.band_width + tx) * 2;
    if (idx + 1 >= atlas.band_data.len) return .{ 0, 0 };
    return .{
        @as(u32, atlas.band_data[idx]),
        @as(u32, atlas.band_data[idx + 1]),
    };
}

/// Read curve texture texel 0 (p1.x, p1.y, p2.x, p2.y) as f32 values.
fn readCurveTexelF32(atlas: *const snail.Atlas, tx: u32, ty: u32) [4]f32 {
    const idx = (ty * atlas.curve_width + tx) * 4;
    if (idx + 3 >= atlas.curve_data.len) return .{ 0, 0, 0, 0 };
    return .{
        f16ToF32(atlas.curve_data[idx + 0]),
        f16ToF32(atlas.curve_data[idx + 1]),
        f16ToF32(atlas.curve_data[idx + 2]),
        f16ToF32(atlas.curve_data[idx + 3]),
    };
}

/// Read curve texture texel 1 (p3.x, p3.y) as f32 values.
fn readCurveTexelF32_p3(atlas: *const snail.Atlas, tx: u32, ty: u32) [2]f32 {
    const idx = (ty * atlas.curve_width + tx) * 4;
    if (idx + 1 >= atlas.curve_data.len) return .{ 0, 0 };
    return .{
        f16ToF32(atlas.curve_data[idx + 0]),
        f16ToF32(atlas.curve_data[idx + 1]),
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
