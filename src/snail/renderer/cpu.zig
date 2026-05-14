//! CPU rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned RGBA8888 memory buffer.  Intended for headless rendering
//! and bootstrap frames (before EGL/Vulkan is available).
//!
//! Pixel parity vs GL/Vulkan: matches within 1 sRGB LSB on virtually every
//! pixel; near-tangent conic edges may diverge by a few LSB due to differing
//! float-op orderings between CPU code and the SPIR-V/GLSL pipeline.

const std = @import("std");
const snail = @import("../root.zig");
const vertex = @import("vertex.zig");
const bezier = snail.lowlevel.bezier;
const curve_tex = snail.lowlevel.curve_tex;
const CurveSegment = bezier.CurveSegment;
const GlyphBandEntry = std.meta.fieldInfo(snail.lowlevel.CurveAtlas.GlyphInfo, .band_entry).type;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const FillRule = snail.FillRule;
const SubpixelOrder = snail.SubpixelOrder;

// sRGB ↔ linear conversion. The 256-entry decode LUT is exact for u8 texels.
// Encode uses the IEC 61966-2-1 formula directly so per-pixel output rounds
// to the same bytes as a GL_SRGB framebuffer (no LUT-interpolation drift).

fn srgbFloatToLinearFormula(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

const srgb_to_linear_lut: [256]f32 = blk: {
    @setEvalBranchQuota(100_000);
    var table: [256]f32 = undefined;
    for (0..256) |i| {
        const v: f32 = @as(f32, @floatFromInt(i)) / 255.0;
        table[i] = srgbFloatToLinearFormula(v);
    }
    break :blk table;
};

const linear_to_srgb_byte_thresholds: [255]f32 = blk: {
    @setEvalBranchQuota(100_000);
    var table: [255]f32 = undefined;
    for (0..255) |i| {
        const threshold_srgb = (@as(f32, @floatFromInt(i)) + 0.5) / 255.0;
        table[i] = srgbFloatToLinearFormula(threshold_srgb);
    }
    break :blk table;
};

const linear_to_srgb_bucket_count = 4096;
const linear_to_srgb_byte_buckets: [linear_to_srgb_bucket_count]u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var table: [linear_to_srgb_bucket_count]u8 = undefined;
    for (0..linear_to_srgb_bucket_count) |bucket| {
        const lower = @as(f32, @floatFromInt(bucket)) / @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
        var byte: u8 = 0;
        while (byte < linear_to_srgb_byte_thresholds.len and lower >= linear_to_srgb_byte_thresholds[byte]) {
            byte += 1;
        }
        table[bucket] = byte;
    }
    break :blk table;
};

fn srgbToLinear(byte: u8) f32 {
    return srgb_to_linear_lut[byte];
}

fn linearToSrgb(v: f32) f32 {
    const clamped = @max(v, 0.0);
    if (clamped >= 1.0) return 1.0;
    return if (clamped <= 0.0031308) clamped * 12.92 else 1.055 * std.math.pow(f32, clamped, 1.0 / 2.4) - 0.055;
}

fn linearToSrgbByte(v: f32) u8 {
    const clamped = @min(@max(v, 0.0), 1.0);
    const bucket_float = clamped * @as(f32, @floatFromInt(linear_to_srgb_bucket_count));
    const bucket = @min(@as(usize, @intFromFloat(bucket_float)), linear_to_srgb_bucket_count - 1);
    var byte = linear_to_srgb_byte_buckets[bucket];
    while (byte < linear_to_srgb_byte_thresholds.len and clamped >= linear_to_srgb_byte_thresholds[byte]) {
        byte += 1;
    }
    while (byte > 0 and clamped < linear_to_srgb_byte_thresholds[byte - 1]) {
        byte -= 1;
    }
    return byte;
}

fn srgbFloatToLinear(v: f32) f32 {
    return srgbFloatToLinearFormula(v);
}

fn srgbToByte(v: f32) u8 {
    return @intFromFloat(@round(@min(@max(v * 255.0, 0.0), 255.0)));
}

fn srgbColorToLinear(color: [4]f32) [4]f32 {
    return .{
        srgbFloatToLinear(color[0]),
        srgbFloatToLinear(color[1]),
        srgbFloatToLinear(color[2]),
        color[3],
    };
}

fn linearColorToSrgb(color: [4]f32) [4]f32 {
    return .{
        linearToSrgb(color[0]),
        linearToSrgb(color[1]),
        linearToSrgb(color[2]),
        color[3],
    };
}

fn multiplyLinearColor(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

fn fract(v: f32) f32 {
    return v - @floor(v);
}

const invalid_prepared_cold = std.math.maxInt(u32);

// Coefficients only touched after the hot record identifies a curve as conic or cubic.
const PreparedAxisCurveCold = struct {
    cubic_a_root: f32 = 0.0,
    cubic_b_root: f32 = 0.0,
    cubic_c_root: f32 = 0.0,
    cubic_a_along: f32 = 0.0,
    cubic_b_along: f32 = 0.0,
    cubic_c_along: f32 = 0.0,
    conic_num_a_root: f32 = 0.0,
    conic_num_b_root: f32 = 0.0,
    conic_num_c_root: f32 = 0.0,
    conic_num_a_along: f32 = 0.0,
    conic_num_b_along: f32 = 0.0,
    conic_num_c_along: f32 = 0.0,
    conic_den_a: f32 = 0.0,
    conic_den_b: f32 = 0.0,
    conic_den_c: f32 = 0.0,

    fn fromSegment(segment: CurveSegment, comptime horizontal: bool) PreparedAxisCurveCold {
        const p0_root = if (horizontal) segment.p0.y else segment.p0.x;
        const p1_root = if (horizontal) segment.p1.y else segment.p1.x;
        const p2_root = if (horizontal) segment.p2.y else segment.p2.x;
        const p3_root = if (horizontal) segment.p3.y else segment.p3.x;
        const p0_along = if (horizontal) segment.p0.x else segment.p0.y;
        const p1_along = if (horizontal) segment.p1.x else segment.p1.y;
        const p2_along = if (horizontal) segment.p2.x else segment.p2.y;
        const p3_along = if (horizontal) segment.p3.x else segment.p3.y;

        const w0 = segment.weights[0];
        const w1 = segment.weights[1];
        const w2 = segment.weights[2];
        const p0_root_w = p0_root * w0;
        const p1_root_w = p1_root * w1;
        const p2_root_w = p2_root * w2;
        const p0_along_w = p0_along * w0;
        const p1_along_w = p1_along * w1;
        const p2_along_w = p2_along * w2;

        return .{
            .cubic_a_root = -p0_root + 3.0 * p1_root - 3.0 * p2_root + p3_root,
            .cubic_b_root = 3.0 * p0_root - 6.0 * p1_root + 3.0 * p2_root,
            .cubic_c_root = -3.0 * p0_root + 3.0 * p1_root,
            .cubic_a_along = -p0_along + 3.0 * p1_along - 3.0 * p2_along + p3_along,
            .cubic_b_along = 3.0 * p0_along - 6.0 * p1_along + 3.0 * p2_along,
            .cubic_c_along = -3.0 * p0_along + 3.0 * p1_along,
            .conic_num_a_root = p0_root_w - 2.0 * p1_root_w + p2_root_w,
            .conic_num_b_root = 2.0 * (p1_root_w - p0_root_w),
            .conic_num_c_root = p0_root_w,
            .conic_num_a_along = p0_along_w - 2.0 * p1_along_w + p2_along_w,
            .conic_num_b_along = 2.0 * (p1_along_w - p0_along_w),
            .conic_num_c_along = p0_along_w,
            .conic_den_a = w0 - 2.0 * w1 + w2,
            .conic_den_b = 2.0 * (w1 - w0),
            .conic_den_c = w0,
        };
    }
};

// Hot per-axis eval record laid out for scanline walking. Quadratic and line
// coverage use only this record; conic/cubic coefficients are indexed separately.
const PreparedAxisCurve = struct {
    valid: bool = false,
    kind: bezier.CurveKind = .quadratic,
    cold_index: u32 = invalid_prepared_cold,
    max_axis: f32 = 0.0,
    p0_root: f32 = 0.0,
    p1_root: f32 = 0.0,
    p2_root: f32 = 0.0,
    p0_along: f32 = 0.0,
    a_root: f32 = 0.0,
    b_root: f32 = 0.0,
    a_along: f32 = 0.0,
    b_along: f32 = 0.0,

    fn fromSegment(segment: CurveSegment, comptime horizontal: bool) PreparedAxisCurve {
        const p0_root = if (horizontal) segment.p0.y else segment.p0.x;
        const p1_root = if (horizontal) segment.p1.y else segment.p1.x;
        const p2_root = if (horizontal) segment.p2.y else segment.p2.x;
        const p0_along = if (horizontal) segment.p0.x else segment.p0.y;
        const p1_along = if (horizontal) segment.p1.x else segment.p1.y;
        const p2_along = if (horizontal) segment.p2.x else segment.p2.y;

        return .{
            .valid = true,
            .kind = segment.kind,
            .max_axis = if (horizontal) segmentMaxX(segment) else segmentMaxY(segment),
            .p0_root = p0_root,
            .p1_root = p1_root,
            .p2_root = p2_root,
            .p0_along = p0_along,
            .a_root = if (segment.kind == .line) p2_root - p0_root else p0_root - 2.0 * p1_root + p2_root,
            .b_root = p0_root - p1_root,
            .a_along = if (segment.kind == .line) p2_along - p0_along else p0_along - 2.0 * p1_along + p2_along,
            .b_along = p0_along - p1_along,
        };
    }
};

inline fn preparedAxisCurveNeedsCold(kind: bezier.CurveKind) bool {
    return kind == .conic or kind == .cubic;
}

fn prepareAxisCurve(
    allocator: std.mem.Allocator,
    cold_records: *std.ArrayList(PreparedAxisCurveCold),
    segment: CurveSegment,
    comptime horizontal: bool,
) !PreparedAxisCurve {
    var curve = PreparedAxisCurve.fromSegment(segment, horizontal);
    if (preparedAxisCurveNeedsCold(segment.kind)) {
        curve.cold_index = @intCast(cold_records.items.len);
        try cold_records.append(allocator, PreparedAxisCurveCold.fromSegment(segment, horizontal));
    }
    return curve;
}

const PreparedAtlasPage = struct {
    band_data: []const u16,
    h_curves: []PreparedAxisCurve,
    v_curves: []PreparedAxisCurve,
    h_cold_curves: []PreparedAxisCurveCold,
    v_cold_curves: []PreparedAxisCurveCold,
    band_width: u32,
    band_height: u32,

    fn init(allocator: std.mem.Allocator, page: *const snail.lowlevel.AtlasPage) !PreparedAtlasPage {
        const curve_data = try allocator.alloc(f32, page.curve_data.len);
        defer allocator.free(curve_data);
        for (page.curve_data, 0..) |value, i| {
            curve_data[i] = f16ToF32(value);
        }
        const band_texel_count = page.band_data.len / 2;
        const h_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(h_curves);
        const v_curves = try allocator.alloc(PreparedAxisCurve, band_texel_count);
        errdefer allocator.free(v_curves);
        @memset(h_curves, .{});
        @memset(v_curves, .{});
        var h_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer h_cold_curves.deinit(allocator);
        var v_cold_curves: std.ArrayList(PreparedAxisCurveCold) = .empty;
        errdefer v_cold_curves.deinit(allocator);

        for (0..band_texel_count) |texel_idx| {
            const curve_base = readBandCurveBase(page, texel_idx) orelse continue;
            const segment = decodeCurveSegmentFromSlice(curve_data, @intCast(curve_base));

            h_curves[texel_idx] = try prepareAxisCurve(allocator, &h_cold_curves, segment, true);
            v_curves[texel_idx] = try prepareAxisCurve(allocator, &v_cold_curves, segment, false);
        }

        const h_cold_curves_owned = try h_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(h_cold_curves_owned);
        const v_cold_curves_owned = try v_cold_curves.toOwnedSlice(allocator);
        errdefer allocator.free(v_cold_curves_owned);

        return .{
            .band_data = page.band_data,
            .h_curves = h_curves,
            .v_curves = v_curves,
            .h_cold_curves = h_cold_curves_owned,
            .v_cold_curves = v_cold_curves_owned,
            .band_width = page.band_width,
            .band_height = page.band_height,
        };
    }

    fn deinit(self: *PreparedAtlasPage, allocator: std.mem.Allocator) void {
        allocator.free(self.h_curves);
        allocator.free(self.v_curves);
        allocator.free(self.h_cold_curves);
        allocator.free(self.v_cold_curves);
        self.* = undefined;
    }
};

const PreparedPathLayer = struct {
    band_entry: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    paint: PreparedPathPaint,
};

const PreparedPathRecord = struct {
    texel_offset: u32,
    tag: i32,
    composite_mode: i32 = 0,
    layer_start: usize,
    layer_count: usize,
};

const LayerInfoEntry = struct {
    data: []const f32 = &.{},
    width: u32 = 0,
    height: u32 = 0,
    row_base: u32 = 0,
    path_records: []PreparedPathRecord = &.{},
    path_layers: []PreparedPathLayer = &.{},
    /// Source atlas's image-paint records, borrowed. Used by the prepared
    /// sampler to resolve tag-4 (image) paints — the atlas-side patching
    /// done by the GPU upload (`pipeline.zig` / `vulkan_pipeline.zig`)
    /// doesn't happen on the CPU, so we look up the `*const snail.Image`
    /// via this slice instead.
    paint_image_records: ?[]const ?snail.lowlevel.CurveAtlas.PaintImageRecord = null,

    fn deinit(self: *LayerInfoEntry, allocator: std.mem.Allocator) void {
        if (self.path_records.len > 0) allocator.free(self.path_records);
        if (self.path_layers.len > 0) allocator.free(self.path_layers);
        self.* = .{};
    }

    fn pathRecordAt(self: *const LayerInfoEntry, info_x: u16, info_y: u16) ?*const PreparedPathRecord {
        const target = @as(u32, info_y) * self.width + @as(u32, info_x);
        var lo: usize = 0;
        var hi: usize = self.path_records.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const offset = self.path_records[mid].texel_offset;
            if (target < offset) {
                hi = mid;
            } else if (target > offset) {
                lo = mid + 1;
            } else {
                return &self.path_records[mid];
            }
        }
        return null;
    }
};

const ResolvedLayerInfo = struct {
    entry: *const LayerInfoEntry,
    local_y: u16,
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    /// Flat array of atlas pages indexed by texture-array layer.
    atlas_pages: []?PreparedAtlasPage = &.{},
    /// Layer info entries from uploaded atlases (combined, like the GPU texture).
    layer_infos: []LayerInfoEntry = &.{},
    layer_info_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, atlases: []const *const snail.lowlevel.CurveAtlas) !PreparedResources {
        var layer_count: usize = 0;
        var layer_info_count: usize = 0;
        for (atlases) |atlas| {
            layer_count += atlas.pageCount();
            if (atlas.layer_info_data != null) layer_info_count += 1;
        }
        const atlas_pages = try allocator.alloc(?PreparedAtlasPage, layer_count);
        errdefer allocator.free(atlas_pages);
        const layer_infos = try allocator.alloc(LayerInfoEntry, layer_info_count);
        errdefer allocator.free(layer_infos);
        @memset(atlas_pages, null);
        @memset(layer_infos, LayerInfoEntry{});
        return .{
            .allocator = allocator,
            .atlas_pages = atlas_pages,
            .layer_infos = layer_infos,
        };
    }

    pub fn deinit(self: *PreparedResources) void {
        self.reset();
        if (self.atlas_pages.len > 0) self.allocator.free(self.atlas_pages);
        if (self.layer_infos.len > 0) self.allocator.free(self.layer_infos);
        self.* = undefined;
    }

    pub fn reset(self: *PreparedResources) void {
        for (self.atlas_pages) |*page| {
            if (page.*) |*prepared_page| prepared_page.deinit(self.allocator);
        }
        for (self.layer_infos[0..self.layer_info_count]) |*entry| entry.deinit(self.allocator);
        @memset(self.atlas_pages, null);
        @memset(self.layer_infos, LayerInfoEntry{});
        self.layer_info_count = 0;
    }

    pub fn uploadAtlases(self: *PreparedResources, atlases: []const *const snail.lowlevel.CurveAtlas, out_views: anytype) !void {
        var layer_base: u32 = 0;
        var info_row_base: u32 = 0;
        self.reset();
        for (out_views, atlases) |*v, a| {
            v.* = .{ .atlas = a, .layer_base = layer_base, .info_row_base = info_row_base };
            try self.storeAtlasPages(a, layer_base, info_row_base);
            layer_base += @intCast(a.pageCount());
            info_row_base += a.layer_info_height;
        }
    }

    pub fn uploadImages(_: *PreparedResources, images: []const *const snail.Image, out_views: anytype) void {
        for (out_views, images) |*v, img| {
            v.* = .{ .image = img };
        }
    }

    fn storeAtlasPages(self: *PreparedResources, atlas: *const snail.lowlevel.CurveAtlas, layer_base: u32, info_row_base: u32) !void {
        for (0..atlas.pageCount()) |i| {
            const layer = layer_base + @as(u32, @intCast(i));
            if (layer >= self.atlas_pages.len) return error.PreparedResourceCapacityExceeded;
            self.atlas_pages[layer] = try PreparedAtlasPage.init(self.allocator, atlas.page(@intCast(i)));
        }
        if (atlas.layer_info_data) |lid| {
            if (self.layer_info_count >= self.layer_infos.len) return error.PreparedResourceCapacityExceeded;
            const prepared_layers = try preparePathLayerInfoRecords(self.allocator, lid, atlas.layer_info_width, atlas.layer_info_height, atlas.paint_image_records);
            self.layer_infos[self.layer_info_count] = .{
                .data = lid,
                .width = atlas.layer_info_width,
                .height = atlas.layer_info_height,
                .row_base = info_row_base,
                .path_records = prepared_layers.records,
                .path_layers = prepared_layers.layers,
                .paint_image_records = atlas.paint_image_records,
            };
            self.layer_info_count += 1;
        }
    }

    /// Resolve a global (info_x, info_y) into data pointer, width, and
    /// the source atlas's image-paint records, adjusting info_y for the
    /// atlas's row_base.
    fn resolveLayerInfo(self: *const PreparedResources, info_y: u16) ?ResolvedLayerInfo {
        for (self.layer_infos[0..self.layer_info_count]) |*entry| {
            if (info_y >= entry.row_base and info_y < entry.row_base + entry.height) {
                return .{
                    .entry = entry,
                    .local_y = @intCast(info_y - entry.row_base),
                };
            }
        }
        return null;
    }
};

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
    coverage_transfer: snail.CoverageTransfer,
    thread_pool: ?*snail.ThreadPool,
    // Half-open row window [row_clip_min, row_clip_max). Pixel writes outside
    // this range are skipped. Used by tile workers to claim disjoint scanline
    // bands; defaults to the full image for single-threaded callers.
    row_clip_min: u32,
    row_clip_max: u32,

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
            .coverage_transfer = .identity,
            .thread_pool = null,
            .row_clip_min = 0,
            .row_clip_max = height,
        };
    }

    /// Update the pixel buffer and dimensions without clearing atlas state.
    pub fn reinitBuffer(self: *CpuRenderer, pixels: [*]u8, width: u32, height: u32, stride: u32) void {
        self.pixels = pixels;
        self.width = width;
        self.height = height;
        self.stride = stride;
        self.row_clip_min = 0;
        self.row_clip_max = height;
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

    pub fn setCoverageTransfer(self: *CpuRenderer, transfer: snail.CoverageTransfer) void {
        self.coverage_transfer = transfer;
    }

    pub fn getCoverageTransfer(self: *const CpuRenderer) snail.CoverageTransfer {
        return self.coverage_transfer;
    }

    fn applyCoverageTransfer(self: *const CpuRenderer, cov: f32) f32 {
        return self.coverage_transfer.apply(cov);
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
        return snail.Renderer.initCpu(self);
    }

    pub fn uploadResourcesBlocking(self: *CpuRenderer, allocator: std.mem.Allocator, set: *const snail.ResourceSet) !snail.PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocator, set);
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
        const decoded = vertex.decodeInstance(inst);
        const bbox = snail.lowlevel.bezier.BBox{
            .min = .{ .x = decoded.rect[0], .y = decoded.rect[1] },
            .max = .{ .x = decoded.rect[2], .y = decoded.rect[3] },
        };
        const instance_transform = Transform2D{
            .xx = decoded.xform[0],
            .xy = decoded.xform[1],
            .yx = decoded.xform[2],
            .yy = decoded.xform[3],
            .tx = decoded.origin[0],
            .ty = decoded.origin[1],
        };
        // Compose the scene-to-pixel transform onto the baked instance
        // transform; GPU backends do this in the vertex shader via the MVP
        // uniform, the CPU rasterizer has to do it here.
        const transform = Transform2D.multiply(scene_to_pixel, instance_transform);
        const gz = decoded.glyph[0];
        const gw = decoded.glyph[1];
        const color = srgbColorToLinear(decoded.color);
        const tint = srgbColorToLinear(decoded.tint);

        const atlas_layer_byte: u8 = @intCast(gw >> 24);

        if (atlas_layer_byte == 0xFF) {
            const layer_count: u16 = @intCast(gw & 0xFFFF);
            const info_x: u16 = @intCast(gz & 0xFFFF);
            const info_y: u16 = @intCast(gz >> 16);
            const atlas_layer = texture_layer_base + @as(u32, @intFromFloat(decoded.band[3]));

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
            .band_scale_x = decoded.band[0],
            .band_scale_y = decoded.band[1],
            .band_offset_x = decoded.band[2],
            .band_offset_y = decoded.band[3],
        };

        const atlas_layer = texture_layer_base + @as(u32, atlas_layer_byte);
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        self.renderTransformedGlyph(page, bbox, be, transform, multiplyLinearColor(color, tint), allow_subpixel);
    }

    fn renderColrBatchLayers(
        self: *CpuRenderer,
        prepared: *const PreparedResources,
        union_bbox: snail.lowlevel.bezier.BBox,
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
        union_bbox: snail.lowlevel.bezier.BBox,
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
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
            if (px0 >= px1 or py0 >= py1) return;

            const epp = glyphEdgePixelsPerPixel(inverse);
            const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
            const sample_dx = Vec2.new(inverse.xx, inverse.yx);
            const sample_dy = Vec2.new(inverse.xy, inverse.yy);
            const use_subpixel = allow_subpixel and self.subpixel_order != .none;
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
                                sample_dx,
                                sample_dy,
                                be,
                                band_max_h,
                                band_max_v,
                                self.fill_rule,
                                self.subpixel_order,
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
            const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
            const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
            const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
            const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
            if (px0 >= px1 or py0 >= py1) return;

            const epp = glyphEdgePixelsPerPixel(inverse);
            const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
            const sample_dx = Vec2.new(inverse.xx, inverse.yx);
            const sample_dy = Vec2.new(inverse.xy, inverse.yy);
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
                            sample_dx,
                            sample_dy,
                            be,
                            band_max_h,
                            band_max_v,
                            self.fill_rule,
                            self.subpixel_order,
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
        bbox: snail.lowlevel.bezier.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        const inverse = inverseTransform(transform) orelse return;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForSubpixel(&bounds, self.subpixel_order, allow_subpixel);

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), @as(i32, @intCast(self.row_clip_min)));
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.row_clip_max)));
        if (px0 >= px1 or py0 >= py1) return;

        const epp = glyphEdgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;
        const sample_dx = Vec2.new(inverse.xx, inverse.yx);
        const sample_dy = Vec2.new(inverse.xy, inverse.yy);

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
                        sample_dx,
                        sample_dy,
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                        self.subpixel_order,
                    ));
                    if (max3(cov.rgb) < 1.0 / 255.0) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                }
            }
        }
    }

    fn drawGlyphId(
        self: *CpuRenderer,
        atlas: *const snail.lowlevel.CurveAtlas,
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
        atlas: *const snail.lowlevel.CurveAtlas,
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
        atlas: *const snail.lowlevel.CurveAtlas,
        info: snail.lowlevel.CurveAtlas.GlyphInfo,
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
        atlas: *const snail.lowlevel.CurveAtlas,
        info: snail.lowlevel.CurveAtlas.GlyphInfo,
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

        const px0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.x))), 0);
        const px1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.x))), @as(i32, @intCast(self.width)));
        const py0 = @max(@as(i32, @intFromFloat(@floor(bounds.min.y))), 0);
        const py1 = @min(@as(i32, @intFromFloat(@ceil(bounds.max.y))), @as(i32, @intCast(self.height)));

        if (px0 >= px1 or py0 >= py1) return;

        const epp_x: f32 = 1.0 / scale;
        const epp_y: f32 = 1.0 / scale;
        const ppe_x: f32 = scale;
        const ppe_y: f32 = scale;

        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;

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
                        Vec2.new(epp_x, 0.0),
                        Vec2.new(0.0, -epp_y),
                        be,
                        band_max_h,
                        band_max_v,
                        self.fill_rule,
                        self.subpixel_order,
                    ));
                    if (max3(cov.rgb) < 1.0 / 255.0) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                }
            }
        }
    }

    inline fn readDstChannel(self: *const CpuRenderer, byte: u8) f32 {
        return if (self.target_encoding.cpuOutputSrgb())
            srgbToLinear(byte)
        else
            @as(f32, @floatFromInt(byte)) / 255.0;
    }

    inline fn writeChannel(self: *const CpuRenderer, linear_value: f32, dither: f32) u8 {
        if (self.target_encoding.cpuOutputSrgb()) {
            if (dither == 0.0) return linearToSrgbByte(linear_value);
            return srgbToByte(linearToSrgb(linear_value) + dither);
        }
        return srgbToByte(linear_value + dither);
    }

    fn blendPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
        const off = row * self.stride + col * 4;
        const dst_r = self.readDstChannel(self.pixels[off + 0]);
        const dst_g = self.readDstChannel(self.pixels[off + 1]);
        const dst_b = self.readDstChannel(self.pixels[off + 2]);
        const dst_a = @as(f32, @floatFromInt(self.pixels[off + 3])) / 255.0;

        const src_a = clamp01(src[3]);
        const out_r = src[0] + dst_r * (1.0 - src_a);
        const out_g = src[1] + dst_g * (1.0 - src_a);
        const out_b = src[2] + dst_b * (1.0 - src_a);
        const out_a = src_a + dst_a * (1.0 - src_a);

        const dither = if (apply_dither)
            (interleavedGradientNoise(row, col) - 0.5) * (clamp01(out_a) / 255.0)
        else
            0.0;
        self.pixels[off + 0] = self.writeChannel(out_r, dither);
        self.pixels[off + 1] = self.writeChannel(out_g, dither);
        self.pixels[off + 2] = self.writeChannel(out_b, dither);
        self.pixels[off + 3] = srgbToByte(out_a);
    }

    fn blendSubpixelPremultipliedPixel(self: *CpuRenderer, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
        const off = row * self.stride + col * 4;
        const dst_r = self.readDstChannel(self.pixels[off + 0]);
        const dst_g = self.readDstChannel(self.pixels[off + 1]);
        const dst_b = self.readDstChannel(self.pixels[off + 2]);
        const dst_a = @as(f32, @floatFromInt(self.pixels[off + 3])) / 255.0;

        const out_r = src[0] + dst_r * (1.0 - clamp01(src_blend[0]));
        const out_g = src[1] + dst_g * (1.0 - clamp01(src_blend[1]));
        const out_b = src[2] + dst_b * (1.0 - clamp01(src_blend[2]));
        const src_a = clamp01(src[3]);
        const out_a = src_a + dst_a * (1.0 - src_a);

        const dither = if (apply_dither)
            (interleavedGradientNoise(row, col) - 0.5) * (clamp01(out_a) / 255.0)
        else
            0.0;
        self.pixels[off + 0] = self.writeChannel(out_r, dither);
        self.pixels[off + 1] = self.writeChannel(out_g, dither);
        self.pixels[off + 2] = self.writeChannel(out_b, dither);
        self.pixels[off + 3] = srgbToByte(out_a);
    }

    /// Per-channel subpixel blend (equivalent to GPU dual-source blending).
    /// Each RGB channel has its own coverage, so the destination attenuation
    /// is per-channel: out.r = src.r * alpha_r + dst.r * (1 - alpha_r), etc.
    fn blendSubpixelPixel(self: *CpuRenderer, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
        const src_blend = subpixelBlendCoverage(color, cov);
        self.blendSubpixelPremultipliedPixel(row, col, premultiplySubpixelCoverage(color, cov, alpha_cov), src_blend, false);
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

/// Compute the 2D affine that maps glyph-local (z = 0) coords to pixel coords
/// under the caller's MVP and viewport, by running the *full* GPU pipeline
/// (mvp -> NDC -> viewport remap) on three reference points and recovering
/// the affine from them. Makes no assumption about the MVP's shape.
///
/// For any MVP whose projection of the z = 0 plane is affine in screen space
/// (every 2D snail use case: ortho or arbitrary 2D-affine in any combination)
/// this is exact, not an approximation. A perspective MVP would make `w` vary
/// across the plane and the recovered affine wouldn't agree with the GPU; we
/// detect that and panic rather than silently producing different pixels than
/// the GL/Vulkan backends.
fn sceneToPixelFromMvp(mvp: snail.Mat4, vw: f32, vh: f32) Transform2D {
    const m = mvp.data;

    // Apply mvp to (0, 0, 0, 1), (1, 0, 0, 1), (0, 1, 0, 1) — origin and
    // basis vectors of the glyph-local z = 0 plane.
    const o_clip = [3]f32{ m[12], m[13], m[15] };
    const x_clip = [3]f32{ m[0] + m[12], m[1] + m[13], m[3] + m[15] };
    const y_clip = [3]f32{ m[4] + m[12], m[5] + m[13], m[7] + m[15] };

    // Affine projection of the plane requires constant w across reference
    // points. A perspective MVP would violate this; the CPU rasterizer
    // doesn't yet do per-pixel `1/w`, so refuse rather than produce output
    // that disagrees with the GPU backends.
    const eps_w: f32 = 1e-4;
    if (@abs(o_clip[2] - x_clip[2]) > eps_w or @abs(o_clip[2] - y_clip[2]) > eps_w) {
        std.debug.panic(
            "CpuRenderer: MVP projects the z = 0 plane non-affinely (perspective). w(o)={d}, w(x)={d}, w(y)={d}",
            .{ o_clip[2], x_clip[2], y_clip[2] },
        );
    }
    if (@abs(o_clip[2]) < 1e-6) {
        std.debug.panic("CpuRenderer: degenerate MVP — w == 0", .{});
    }

    const inv_w = 1.0 / o_clip[2];
    const half_w = vw * 0.5;
    const half_h = vh * 0.5;

    // ndc = clip / w, then viewport remap (snail uses y-down screen space, so
    // ndc_y is flipped).
    const o_x = (o_clip[0] * inv_w + 1.0) * half_w;
    const o_y = (1.0 - o_clip[1] * inv_w) * half_h;
    const x_x = (x_clip[0] * inv_w + 1.0) * half_w;
    const x_y = (1.0 - x_clip[1] * inv_w) * half_h;
    const y_x = (y_clip[0] * inv_w + 1.0) * half_w;
    const y_y = (1.0 - y_clip[1] * inv_w) * half_h;

    return .{
        .xx = x_x - o_x,
        .yx = x_y - o_y,
        .xy = y_x - o_x,
        .yy = y_y - o_y,
        .tx = o_x,
        .ty = o_y,
    };
}

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

const ScreenBounds = struct {
    min: Vec2,
    max: Vec2,
};

fn transformedGlyphBounds(bbox: snail.BBox, transform: Transform2D) ScreenBounds {
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

fn subpixelSupportExtra(order: SubpixelOrder) Vec2 {
    const extra = 2.0 / 3.0;
    return switch (order) {
        .rgb, .bgr => .{ .x = extra, .y = 0.0 },
        .vrgb, .vbgr => .{ .x = 0.0, .y = extra },
        .none => .{ .x = 0.0, .y = 0.0 },
    };
}

fn expandBoundsForSubpixel(bounds: *ScreenBounds, order: SubpixelOrder, allow_subpixel: bool) void {
    if (!allow_subpixel) return;
    const extra = subpixelSupportExtra(order);
    bounds.min.x -= extra.x;
    bounds.min.y -= extra.y;
    bounds.max.x += extra.x;
    bounds.max.y += extra.y;
}

fn glyphEdgePixelsPerPixel(inverse: Transform2D) Vec2 {
    return .{
        .x = @max(@sqrt(inverse.xx * inverse.xx + inverse.xy * inverse.xy), 1.0 / 65536.0),
        .y = @max(@sqrt(inverse.yx * inverse.yx + inverse.yy * inverse.yy), 1.0 / 65536.0),
    };
}

test "CPU grayscale footprint matches shader derivative length" {
    const inv = Transform2D{
        .xx = 0.5,
        .xy = 0.5,
        .yx = -0.25,
        .yy = 0.25,
    };
    const epp = glyphEdgePixelsPerPixel(inv);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 0.5)), epp.x, 0.0001);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 0.125)), epp.y, 0.0001);
}

inline fn advanceLocalPixel(col: *u32, local: *Vec2, sample_dx: Vec2) void {
    col.* += 1;
    local.x += sample_dx.x;
    local.y += sample_dx.y;
}

fn fetchLayerInfoTexel(data: []const f32, width: u32, info_x: u16, info_y: u16, offset: u32) [4]f32 {
    const texel = @as(u32, info_x) + offset;
    const x = texel % width;
    const y = @as(u32, info_y) + texel / width;
    const base = (y * width + x) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

fn fetchLayerInfoTexelOffset(data: []const f32, texel_offset: u32) [4]f32 {
    const base = @as(usize, texel_offset) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

fn pathInfoTag(info: [4]f32) i32 {
    return @intFromFloat(@round(-info[3]));
}

const PreparedPathLayerInfo = struct {
    records: []PreparedPathRecord,
    layers: []PreparedPathLayer,
};

const PreparedPathLayerInfoCounts = struct {
    records: usize = 0,
    layers: usize = 0,
};

fn pathLayerInfoTexelCount(data: []const f32, width: u32, height: u32) u32 {
    const declared = @as(usize, width) * @as(usize, height);
    return @intCast(@min(declared, data.len / 4));
}

fn countPreparedPathLayerInfo(data: []const f32, width: u32, height: u32) PreparedPathLayerInfoCounts {
    const texel_count = pathLayerInfoTexelCount(data, width, height);
    var counts = PreparedPathLayerInfoCounts{};
    var texel: u32 = 0;
    while (texel < texel_count) {
        const info = fetchLayerInfoTexelOffset(data, texel);
        const tag = pathInfoTag(info);
        switch (tag) {
            1, 2, 3, 4 => {
                counts.records += 1;
                counts.layers += 1;
                texel += 6;
            },
            5 => {
                const layer_count: usize = @intCast(@max(@as(i32, @intFromFloat(@round(info[0]))), 0));
                counts.records += 1;
                counts.layers += layer_count;
                texel += 1 + @as(u32, @intCast(layer_count)) * 6;
            },
            else => texel += 1,
        }
    }
    return counts;
}

fn preparePathLayerInfoRecords(
    allocator: std.mem.Allocator,
    data: []const f32,
    width: u32,
    height: u32,
    paint_image_records: ?[]const ?snail.lowlevel.CurveAtlas.PaintImageRecord,
) !PreparedPathLayerInfo {
    const counts = countPreparedPathLayerInfo(data, width, height);
    const records = try allocator.alloc(PreparedPathRecord, counts.records);
    errdefer allocator.free(records);
    const layers = try allocator.alloc(PreparedPathLayer, counts.layers);
    errdefer allocator.free(layers);

    const texel_count = pathLayerInfoTexelCount(data, width, height);
    var record_index: usize = 0;
    var layer_index: usize = 0;
    var texel: u32 = 0;
    while (texel < texel_count) {
        const info = fetchLayerInfoTexelOffset(data, texel);
        const tag = pathInfoTag(info);
        switch (tag) {
            1, 2, 3, 4 => {
                records[record_index] = .{
                    .texel_offset = texel,
                    .tag = tag,
                    .layer_start = layer_index,
                    .layer_count = 1,
                };
                layers[layer_index] = preparePathLayerFromLayerInfoOffset(data, texel, paint_image_records);
                record_index += 1;
                layer_index += 1;
                texel += 6;
            },
            5 => {
                const layer_count: usize = @intCast(@max(@as(i32, @intFromFloat(@round(info[0]))), 0));
                records[record_index] = .{
                    .texel_offset = texel,
                    .tag = tag,
                    .composite_mode = @intFromFloat(@round(info[1])),
                    .layer_start = layer_index,
                    .layer_count = layer_count,
                };
                for (0..layer_count) |i| {
                    const layer_offset = texel + 1 + @as(u32, @intCast(i)) * 6;
                    layers[layer_index + i] = preparePathLayerFromLayerInfoOffset(data, layer_offset, paint_image_records);
                }
                record_index += 1;
                layer_index += layer_count;
                texel += 1 + @as(u32, @intCast(layer_count)) * 6;
            },
            else => texel += 1,
        }
    }

    return .{ .records = records, .layers = layers };
}

fn preparePathLayerFromLayerInfoOffset(
    data: []const f32,
    texel_offset: u32,
    paint_image_records: ?[]const ?snail.lowlevel.CurveAtlas.PaintImageRecord,
) PreparedPathLayer {
    const info = fetchLayerInfoTexelOffset(data, texel_offset);
    const band = fetchLayerInfoTexelOffset(data, texel_offset + 1);
    const band_packed: u32 = @bitCast(info[2]);
    const be = GlyphBandEntry{
        .glyph_x = @intFromFloat(info[0]),
        .glyph_y = @intFromFloat(info[1]),
        .h_band_count = @intCast((band_packed & 0xFFFF) + 1),
        .v_band_count = @intCast(((band_packed >> 16) & 0xFFFF) + 1),
        .band_scale_x = band[0],
        .band_scale_y = band[1],
        .band_offset_x = band[2],
        .band_offset_y = band[3],
    };
    return .{
        .band_entry = be,
        .band_max_h = @as(i32, @intCast(be.h_band_count)) - 1,
        .band_max_v = @as(i32, @intCast(be.v_band_count)) - 1,
        .paint = preparePathPaintFromLayerInfoOffset(data, texel_offset, paint_image_records),
    };
}

fn preparePathPaintFromLayerInfoOffset(
    data: []const f32,
    texel_offset: u32,
    paint_image_records: ?[]const ?snail.lowlevel.CurveAtlas.PaintImageRecord,
) PreparedPathPaint {
    const info = fetchLayerInfoTexelOffset(data, texel_offset);
    const tag = pathInfoTag(info);
    const data0 = fetchLayerInfoTexelOffset(data, texel_offset + 2);
    switch (tag) {
        1 => return .{ .kind = .solid, .color0 = srgbColorToLinear(data0) },
        2 => {
            const color0 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const color1 = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            return .{
                .kind = .linear_gradient,
                .data0 = data0,
                .color0 = linearColorToSrgb(color0),
                .color1 = linearColorToSrgb(color1),
                .extra = extra,
            };
        },
        3 => {
            const color0 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const color1 = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            return .{
                .kind = .radial_gradient,
                .data0 = data0,
                .color0 = linearColorToSrgb(color0),
                .color1 = linearColorToSrgb(color1),
            };
        },
        4 => {
            // Image paint. The atlas-side `paint_image_records` stores each
            // record's `texel_offset` as the flat layer-info texel address
            // it was written at; match against the absolute texel for this
            // layer to find the source image. (GPU backends instead patch
            // the `extra` texel in place at upload time — see
            // `pipeline.zig` `patchImagePaintRecord` — so the shader reads
            // the image slot directly out of layer-info.)
            const records = paint_image_records orelse return .{};
            const data1 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const tint = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            return .{
                .kind = .image,
                .data0 = data0,
                .data1 = data1,
                .color0 = tint,
                .extra = extra,
                .image_record = findImageRecordByTexel(records, texel_offset),
            };
        },
        else => return .{},
    }
}

fn findImageRecordByTexel(
    records: []const ?snail.lowlevel.CurveAtlas.PaintImageRecord,
    abs_texel: u32,
) ?snail.lowlevel.CurveAtlas.PaintImageRecord {
    for (records) |maybe_record| {
        const record = maybe_record orelse continue;
        if (record.texel_offset == abs_texel) return record;
    }
    return null;
}

fn compositeOver(src: [4]f32, dst: [4]f32) [4]f32 {
    const inv_a = 1.0 - src[3];
    return .{
        src[0] + dst[0] * inv_a,
        src[1] + dst[1] * inv_a,
        src[2] + dst[2] * inv_a,
        src[3] + dst[3] * inv_a,
    };
}

fn addColors(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
}

fn wrapPaintT(t: f32, extend_mode: snail.PaintExtend) f32 {
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

fn paintExtendFromFloat(raw: f32) snail.PaintExtend {
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
        srgbToLinear(image.pixels[idx + 0]),
        srgbToLinear(image.pixels[idx + 1]),
        srgbToLinear(image.pixels[idx + 2]),
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

const PathPaintSample = struct {
    color: [4]f32,
    apply_dither: bool = false,
};

const PreparedPathPaint = struct {
    const Kind = enum {
        invalid,
        solid,
        linear_gradient,
        radial_gradient,
        image,
    };

    kind: Kind = .invalid,
    color0: [4]f32 = .{ 1, 0, 1, 1 },
    color1: [4]f32 = .{ 1, 0, 1, 1 },
    data0: [4]f32 = .{ 0, 0, 0, 0 },
    data1: [4]f32 = .{ 0, 0, 0, 0 },
    extra: [4]f32 = .{ 0, 0, 0, 0 },
    image_record: ?snail.lowlevel.CurveAtlas.PaintImageRecord = null,

    fn sample(self: *const PreparedPathPaint, local: Vec2) PathPaintSample {
        return switch (self.kind) {
            .solid => .{ .color = self.color0 },
            .linear_gradient => blk: {
                const start = Vec2.new(self.data0[0], self.data0[1]);
                const end = Vec2.new(self.data0[2], self.data0[3]);
                const delta = Vec2.sub(end, start);
                const len_sq = Vec2.dot(delta, delta);
                var t: f32 = 0.0;
                if (len_sq > 1e-10) t = Vec2.dot(Vec2.sub(local, start), delta) / len_sq;
                break :blk .{
                    .color = lerpGradientColorFromSrgb(self.color0, self.color1, wrapPaintT(t, paintExtendFromFloat(self.extra[0]))),
                    .apply_dither = true,
                };
            },
            .radial_gradient => blk: {
                const center = Vec2.new(self.data0[0], self.data0[1]);
                const radius = @max(@abs(self.data0[2]), 1.0 / 65536.0);
                const t = Vec2.length(Vec2.sub(local, center)) / radius;
                break :blk .{
                    .color = lerpGradientColorFromSrgb(self.color0, self.color1, wrapPaintT(t, paintExtendFromFloat(self.data0[3]))),
                    .apply_dither = true,
                };
            },
            .image => blk: {
                const record = self.image_record orelse break :blk .{ .color = .{ 1, 0, 1, 1 } };
                break :blk samplePreparedImageWithRecord(record, self.data0, self.data1, self.color0, self.extra, local);
            },
            .invalid => .{ .color = .{ 1, 0, 1, 1 } },
        };
    }
};

fn samplePathPaint(atlas: *const snail.lowlevel.CurveAtlas, shape: snail.PathPicture.Shape, glyph_id: u16, local: Vec2) PathPaintSample {
    return samplePathPaintAt(atlas, shape.info_x, shape.info_y, glyph_id, local);
}

fn samplePathPaintAt(atlas: *const snail.lowlevel.CurveAtlas, info_x: u16, info_y: u16, glyph_id: u16, local: Vec2) PathPaintSample {
    const data = atlas.layer_info_data orelse return .{ .color = .{ 1, 1, 1, 1 } };
    const width = atlas.layer_info_width;
    const info = fetchLayerInfoTexel(data, width, info_x, info_y, 0);
    const tag: i32 = @intFromFloat(@round(-info[3]));

    const data0 = fetchLayerInfoTexel(data, width, info_x, info_y, 2);
    switch (tag) {
        1 => return .{ .color = srgbColorToLinear(data0) },
        2 => {
            const color0 = fetchLayerInfoTexel(data, width, info_x, info_y, 3);
            const color1 = fetchLayerInfoTexel(data, width, info_x, info_y, 4);
            const extra = fetchLayerInfoTexel(data, width, info_x, info_y, 5);
            const start = Vec2.new(data0[0], data0[1]);
            const end = Vec2.new(data0[2], data0[3]);
            const delta = Vec2.sub(end, start);
            const len_sq = Vec2.dot(delta, delta);
            var t: f32 = 0.0;
            if (len_sq > 1e-10) t = Vec2.dot(Vec2.sub(local, start), delta) / len_sq;
            return .{
                .color = lerpGradientColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(extra[0]))),
                .apply_dither = true,
            };
        },
        3 => {
            const color0 = fetchLayerInfoTexel(data, width, info_x, info_y, 3);
            const color1 = fetchLayerInfoTexel(data, width, info_x, info_y, 4);
            const center = Vec2.new(data0[0], data0[1]);
            const radius = @max(@abs(data0[2]), 1.0 / 65536.0);
            const t = Vec2.length(Vec2.sub(local, center)) / radius;
            return .{
                .color = lerpGradientColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(data0[3]))),
                .apply_dither = true,
            };
        },
        4 => return sampleImagePaint(atlas, glyph_id, data, width, info_x, info_y, 2, data0, local),
        5 => {
            // Composite group: 1-texel header, then 6-texel sub-records.
            // Read the fill layer's paint tag at offset 1 from the group header.
            const fill_info = fetchLayerInfoTexel(data, width, info_x, info_y, 1);
            const fill_tag: i32 = @intFromFloat(@round(-fill_info[3]));
            // Fill paint data starts at offset 3 (header=0, sub-record band info=1,2, paint data=3+)
            const fill_data0 = fetchLayerInfoTexel(data, width, info_x, info_y, 3);
            switch (fill_tag) {
                1 => return .{ .color = srgbColorToLinear(fill_data0) },
                2 => {
                    const color0 = fetchLayerInfoTexel(data, width, info_x, info_y, 4);
                    const color1 = fetchLayerInfoTexel(data, width, info_x, info_y, 5);
                    const extra = fetchLayerInfoTexel(data, width, info_x, info_y, 6);
                    const start = Vec2.new(fill_data0[0], fill_data0[1]);
                    const end = Vec2.new(fill_data0[2], fill_data0[3]);
                    const delta = Vec2.sub(end, start);
                    const len_sq = Vec2.dot(delta, delta);
                    var t: f32 = 0.0;
                    if (len_sq > 1e-10) t = Vec2.dot(Vec2.sub(local, start), delta) / len_sq;
                    return .{
                        .color = lerpGradientColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(extra[0]))),
                        .apply_dither = true,
                    };
                },
                3 => {
                    const color0 = fetchLayerInfoTexel(data, width, info_x, info_y, 4);
                    const color1 = fetchLayerInfoTexel(data, width, info_x, info_y, 5);
                    const center = Vec2.new(fill_data0[0], fill_data0[1]);
                    const radius = @max(@abs(fill_data0[2]), 1.0 / 65536.0);
                    const t = Vec2.length(Vec2.sub(local, center)) / radius;
                    return .{
                        .color = lerpGradientColor(color0, color1, wrapPaintT(t, paintExtendFromFloat(fill_data0[3]))),
                        .apply_dither = true,
                    };
                },
                4 => return sampleImagePaint(atlas, glyph_id, data, width, info_x, info_y, 3, fill_data0, local),
                else => return .{ .color = .{ 1, 0, 1, 1 } },
            }
        },
        else => return .{ .color = .{ 1, 0, 1, 1 } },
    }
}

fn sampleImagePaint(
    atlas: *const snail.lowlevel.CurveAtlas,
    glyph_id: u16,
    data: []const f32,
    width: u32,
    info_x: u16,
    info_y: u16,
    data0_offset: u32,
    data0: [4]f32,
    local: Vec2,
) PathPaintSample {
    const records = atlas.paint_image_records orelse return .{ .color = .{ 1, 0, 1, 1 } };
    // paint_image_records is indexed by glyph_cursor (= glyph_id - 1).
    // The old texel-offset / 6 formula broke when composite group headers
    // shifted the texel cursor out of alignment with the glyph cursor.
    const record_index: usize = @as(usize, glyph_id) -| 1;
    if (record_index >= records.len) return .{ .color = .{ 1, 0, 1, 1 } };
    const record = records[record_index] orelse return .{ .color = .{ 1, 0, 1, 1 } };
    return sampleImageWithRecord(record, data, width, info_x, info_y, data0_offset, data0, local);
}

fn sampleImageWithRecord(
    record: snail.lowlevel.CurveAtlas.PaintImageRecord,
    data: []const f32,
    width: u32,
    info_x: u16,
    info_y: u16,
    data0_offset: u32,
    data0: [4]f32,
    local: Vec2,
) PathPaintSample {
    const data1 = fetchLayerInfoTexel(data, width, info_x, info_y, data0_offset + 1);
    const tint = fetchLayerInfoTexel(data, width, info_x, info_y, data0_offset + 2);
    const extra = fetchLayerInfoTexel(data, width, info_x, info_y, data0_offset + 3);
    const raw_uv = Vec2.new(
        data0[0] * local.x + data0[1] * local.y + data0[2],
        data1[0] * local.x + data1[1] * local.y + data1[2],
    );
    // extra[0..1] are UV scale factors patched by the GPU upload path.
    // The CPU samples images directly (not via a texture array), so
    // unpatched zeros are correct to treat as 1.0 (full image range).
    const uv = Vec2.new(
        wrapPaintT(raw_uv.x, paintExtendFromFloat(extra[2])),
        wrapPaintT(raw_uv.y, paintExtendFromFloat(extra[3])),
    );
    const filter: snail.ImageFilter = if (@as(i32, @intFromFloat(@round(data1[3]))) == 1) .nearest else .linear;
    const sample = sampleImageLinear(record.image, uv, filter);
    return .{ .color = .{
        sample[0] * tint[0],
        sample[1] * tint[1],
        sample[2] * tint[2],
        sample[3] * tint[3],
    } };
}

fn samplePreparedImageWithRecord(
    record: snail.lowlevel.CurveAtlas.PaintImageRecord,
    data0: [4]f32,
    data1: [4]f32,
    tint: [4]f32,
    extra: [4]f32,
    local: Vec2,
) PathPaintSample {
    const raw_uv = Vec2.new(
        data0[0] * local.x + data0[1] * local.y + data0[2],
        data1[0] * local.x + data1[1] * local.y + data1[2],
    );
    const uv = Vec2.new(
        wrapPaintT(raw_uv.x, paintExtendFromFloat(extra[2])),
        wrapPaintT(raw_uv.y, paintExtendFromFloat(extra[3])),
    );
    const filter: snail.ImageFilter = if (@as(i32, @intFromFloat(@round(data1[3]))) == 1) .nearest else .linear;
    const sample = sampleImageLinear(record.image, uv, filter);
    return .{ .color = .{
        sample[0] * tint[0],
        sample[1] * tint[1],
        sample[2] * tint[2],
        sample[3] * tint[3],
    } };
}

fn interleavedGradientNoise(row: u32, col: u32) f32 {
    const pixel_x = @as(f32, @floatFromInt(col)) + 0.5;
    const pixel_y = @as(f32, @floatFromInt(row)) + 0.5;
    return fract(52.9829189 * fract(pixel_x * 0.06711056 + pixel_y * 0.00583715));
}

// ---------------------------------------------------------------------------
// Slug algorithm: CPU port of evalGlyphCoverage from shaders.zig
// ---------------------------------------------------------------------------

const CoveragePair = struct {
    cov: f32,
    wgt: f32,
};

const GlyphBandState = struct {
    h_base: usize,
    h_count: u32,
    v_base: usize,
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

fn blendSubpixelSample(cw_s: CoveragePair, cw_o: CoveragePair, fill_rule: FillRule) f32 {
    const wsum = cw_s.wgt + cw_o.wgt;
    const blended = cw_s.cov * cw_s.wgt + cw_o.cov * cw_o.wgt;
    return clamp01(@max(
        applyFillRule(fill_rule, blended / @max(wsum, 1.0 / 65536.0)),
        @min(applyFillRule(fill_rule, cw_s.cov), applyFillRule(fill_rule, cw_o.cov)),
    ));
}

fn filterSubpixelCoverage(s_m3: f32, s_m2: f32, s_m1: f32, s_0: f32, s_p1: f32, s_p2: f32, s_p3: f32, reverse_order: bool) SubpixelCoverage {
    const w0 = 8.0 / 256.0;
    const w1 = 77.0 / 256.0;
    const w2 = 86.0 / 256.0;
    const left = w0 * s_m3 + w1 * s_m2 + w2 * s_m1 + w1 * s_0 + w0 * s_p1;
    const center = w0 * s_m2 + w1 * s_m1 + w2 * s_0 + w1 * s_p1 + w0 * s_p2;
    const right = w0 * s_m1 + w1 * s_0 + w2 * s_p1 + w1 * s_p2 + w0 * s_p3;
    const rgb = if (reverse_order)
        [3]f32{ clamp01(right), clamp01(center), clamp01(left) }
    else
        [3]f32{ clamp01(left), clamp01(center), clamp01(right) };
    return .{
        .rgb = rgb,
        .alpha = clamp01((rgb[0] + rgb[1] + rgb[2]) * (1.0 / 3.0)),
    };
}

fn edgePixelsToPixelsPerEm(edge_pixels: Vec2) Vec2 {
    return .{
        .x = 1.0 / @max(edge_pixels.x, 1.0 / 65536.0),
        .y = 1.0 / @max(edge_pixels.y, 1.0 / 65536.0),
    };
}

fn subpixelCoveragePixelsPerEm(sample_dx: Vec2, sample_dy: Vec2, subpixel_order: SubpixelOrder) Vec2 {
    const dx = Vec2.new(@abs(sample_dx.x), @abs(sample_dx.y));
    const dy = Vec2.new(@abs(sample_dy.x), @abs(sample_dy.y));
    const edge_pixels = switch (subpixel_order) {
        .rgb, .bgr => Vec2.new(dx.x * (1.0 / 3.0) + dy.x, dx.y * (1.0 / 3.0) + dy.y),
        .vrgb, .vbgr => Vec2.new(dx.x + dy.x * (1.0 / 3.0), dx.y + dy.y * (1.0 / 3.0)),
        .none => Vec2.new(dx.x + dy.x, dx.y + dy.y),
    };
    return edgePixelsToPixelsPerEm(edge_pixels);
}

test "subpixel coverage narrows the analytic footprint on the subpixel axis" {
    const sample_dx = Vec2.new(1.0 / 20.0, 0.0);
    const sample_dy = Vec2.new(0.0, 1.0 / 24.0);

    const rgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .rgb);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), rgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rgb.y, 0.0001);

    const bgr = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .bgr);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), bgr.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), bgr.y, 0.0001);

    const vrgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .vrgb);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), vrgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 72.0), vrgb.y, 0.0001);

    const none = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .none);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), none.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), none.y, 0.0001);
}

test "subpixel coverage footprint is screen-space under shear" {
    const sample_dx = Vec2.new(1.0 / 20.0, 0.0);
    const sample_dy = Vec2.new(0.01, 1.0 / 24.0);

    const rgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .rgb);
    try std.testing.expectApproxEqAbs(@as(f32, 37.5), rgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rgb.y, 0.0001);

    const vrgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .vrgb);
    try std.testing.expectApproxEqAbs(@as(f32, 18.75), vrgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 72.0), vrgb.y, 0.0001);
}

test "cpu subpixel bounds expand only along physical subpixel axis" {
    var rgb_bounds = ScreenBounds{
        .min = Vec2.new(10.0, 20.0),
        .max = Vec2.new(30.0, 40.0),
    };
    expandBoundsForSubpixel(&rgb_bounds, .rgb, true);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0 - 2.0 / 3.0), rgb_bounds.min.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0 + 2.0 / 3.0), rgb_bounds.max.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), rgb_bounds.min.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), rgb_bounds.max.y, 0.0001);

    var vertical_bounds = ScreenBounds{
        .min = Vec2.new(10.0, 20.0),
        .max = Vec2.new(30.0, 40.0),
    };
    expandBoundsForSubpixel(&vertical_bounds, .vrgb, true);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), vertical_bounds.min.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), vertical_bounds.max.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0 - 2.0 / 3.0), vertical_bounds.min.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0 + 2.0 / 3.0), vertical_bounds.max.y, 0.0001);
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

fn premultiplySubpixelCoverage(color: [4]f32, cov: [3]f32, alpha_cov: f32) [4]f32 {
    return .{
        color[0] * color[3] * cov[0],
        color[1] * color[3] * cov[1],
        color[2] * color[3] * cov[2],
        color[3] * alpha_cov,
    };
}

fn subpixelBlendCoverage(color: [4]f32, cov: [3]f32) [3]f32 {
    return .{
        color[3] * cov[0],
        color[3] * cov[1],
        color[3] * cov[2],
    };
}

fn compositeSubpixelOver(src: [4]f32, src_blend: [3]f32, dst_color: *[4]f32, dst_blend: *[3]f32) void {
    dst_color.* = .{
        src[0] + dst_color.*[0] * (1.0 - src_blend[0]),
        src[1] + dst_color.*[1] * (1.0 - src_blend[1]),
        src[2] + dst_color.*[2] * (1.0 - src_blend[2]),
        src[3] + dst_color.*[3] * (1.0 - src[3]),
    };
    dst_blend.* = .{
        src_blend[0] + dst_blend.*[0] * (1.0 - src_blend[0]),
        src_blend[1] + dst_blend.*[1] * (1.0 - src_blend[1]),
        src_blend[2] + dst_blend.*[2] * (1.0 - src_blend[2]),
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

fn lerpGradientColor(a_linear: [4]f32, b_linear: [4]f32, t: f32) [4]f32 {
    return lerpGradientColorFromSrgb(linearColorToSrgb(a_linear), linearColorToSrgb(b_linear), t);
}

fn lerpGradientColorFromSrgb(a_srgb: [4]f32, b_srgb: [4]f32, t: f32) [4]f32 {
    return srgbColorToLinear(lerpColor(a_srgb, b_srgb, t));
}

fn max3(values: [3]f32) f32 {
    return @max(values[0], @max(values[1], values[2]));
}

fn initGlyphBandState(
    page: anytype,
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
    const glyph_band_base = @as(usize, glyph_y) * @as(usize, page.band_width) + @as(usize, glyph_x);

    const h_header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_idx_y)));
    const v_header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_max_h)) + 1 + @as(usize, @intCast(band_idx_x)));
    return .{
        .h_base = glyph_band_base + h_header[1],
        .h_count = h_header[0],
        .v_base = glyph_band_base + v_header[1],
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
        if (disc > -1e-6) disc = 0.0 else return roots;
    }
    // Stable form: q = -0.5 * (b + sign(b) * sqrt(disc)); roots are q/a and c/q.
    const sq = @sqrt(disc);
    const q = -0.5 * (b + (if (b >= 0.0) sq else -sq));
    if (@abs(q) < 1e-10) {
        appendCurveRoot(&roots, 0.0);
        return roots;
    }
    appendCurveRoot(&roots, q / a);
    appendCurveRoot(&roots, c_val / q);
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

// TODO: precision sensitivity at exact-edge samples. When the sample em
// coord lands on a contour y (e.g. a Latin baseline at integer screen y +
// 0.5 with text origin at integer + 0.5), CPU and GL can disagree by ~0.5
// coverage on a single row. The two backends compute the same mathematical
// em coord via different float op orderings — CPU applies inverseTransform
// directly, GL interpolates v_texcoord across the dilated quad — and one
// rounds slightly negative while the other rounds slightly positive.
// calcRootCode's bit-level sign trick (`@bitCast(y) < 0`) then either sees
// "all positive, no crossing" or "all negative, two crossings", with no
// in-between. Real fix is either matching float op orderings exactly or
// replacing the sign-bit gate with a tolerance-aware check that includes
// curves whose y-range overlaps the AA window in pixel space. The
// backend-compare test scene avoids this by pinning baselines to integer y.
const CoverageScan = enum {
    continue_scan,
    stop_scan,
};

inline fn accumulateQuadraticCoverage(
    result: *CoveragePair,
    p0x: f32,
    p0y: f32,
    p1x: f32,
    p1y: f32,
    p2x: f32,
    p2y: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const code = if (horizontal)
        calcRootCode(p0y, p1y, p2y)
    else
        calcRootCode(p0x, p1x, p2x);
    if (code == 0) return;

    const roots = if (horizontal)
        solveHorizPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
    else
        solveVertPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

    if ((code & 1) != 0) {
        appendCoverageContribution(result, roots[0], if (horizontal) 1.0 else -1.0);
    }
    if (code > 1) {
        appendCoverageContribution(result, roots[1], if (horizontal) -1.0 else 1.0);
    }
}

inline fn accumulateLineCoverage(
    result: *CoveragePair,
    p0x: f32,
    p0y: f32,
    p2x: f32,
    p2y: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const root_axis0 = if (horizontal) p0y else p0x;
    const root_axis2 = if (horizontal) p2y else p2x;
    const denom = root_axis2 - root_axis0;
    if (@abs(denom) < 1e-10) return;

    const t_raw = -root_axis0 / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (t >= 1.0 - 1e-5) return;

    const derivative_axis = if (horizontal) p2y - p0y else p0x - p2x;
    if (@abs(derivative_axis) <= 1e-5) return;

    const distance = if (horizontal)
        (p0x + (p2x - p0x) * t) * ppe
    else
        (p0y + (p2y - p0y) * t) * ppe;
    appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
}

inline fn accumulateGlyphCoverageSegment(
    result: *CoveragePair,
    segment: CurveSegment,
    sample_rc: Vec2,
    ppe: f32,
    comptime horizontal: bool,
) CoverageScan {
    const max_x = segmentMaxX(segment);
    const max_y = segmentMaxY(segment);
    const max_coord = if (horizontal) max_x - sample_rc.x else max_y - sample_rc.y;
    if (max_coord * ppe < -0.5) return .stop_scan;

    if (segment.kind == .quadratic) {
        const p0x = segment.p0.x - sample_rc.x;
        const p0y = segment.p0.y - sample_rc.y;
        const p1x = segment.p1.x - sample_rc.x;
        const p1y = segment.p1.y - sample_rc.y;
        const p2x = segment.p2.x - sample_rc.x;
        const p2y = segment.p2.y - sample_rc.y;
        accumulateQuadraticCoverage(result, p0x, p0y, p1x, p1y, p2x, p2y, ppe, horizontal);
        return .continue_scan;
    }

    if (segment.kind == .line) {
        accumulateLineCoverage(
            result,
            segment.p0.x - sample_rc.x,
            segment.p0.y - sample_rc.y,
            segment.p2.x - sample_rc.x,
            segment.p2.y - sample_rc.y,
            ppe,
            horizontal,
        );
        return .continue_scan;
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
        appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
    }
    return .continue_scan;
}

inline fn solvePreparedAxisQuadratic(curve: *const PreparedAxisCurve, p0_along: f32, p0_root: f32, ppe: f32) [2]f32 {
    const ax = curve.a_along;
    const ay = curve.a_root;
    const bx = curve.b_along;
    const by = curve.b_root;
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ay) < eps) {
        t1 = if (@abs(by) < eps) 0.0 else p0_root * 0.5 / by;
        t2 = t1;
    } else {
        const sq = @sqrt(@max(by * by - ay * p0_root, 0.0));
        if (by >= 0.0) {
            const q = by + sq;
            t2 = q / ay;
            t1 = if (@abs(q) < eps) 0.0 else p0_root / q;
        } else {
            const q = by - sq;
            t1 = q / ay;
            t2 = if (@abs(q) < eps) 0.0 else p0_root / q;
        }
    }

    const d1 = (ax * t1 - bx * 2.0) * t1 + p0_along;
    const d2 = (ax * t2 - bx * 2.0) * t2 + p0_along;
    return .{ d1 * ppe, d2 * ppe };
}

inline fn accumulatePreparedQuadraticCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    sample_root: f32,
    sample_along: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const p0_root = curve.p0_root - sample_root;
    const p1_root = curve.p1_root - sample_root;
    const p2_root = curve.p2_root - sample_root;
    const code = calcRootCode(p0_root, p1_root, p2_root);
    if (code == 0) return;

    const roots = solvePreparedAxisQuadratic(curve, curve.p0_along - sample_along, p0_root, ppe);

    if ((code & 1) != 0) {
        appendCoverageContribution(result, roots[0], if (horizontal) 1.0 else -1.0);
    }
    if (code > 1) {
        appendCoverageContribution(result, roots[1], if (horizontal) -1.0 else 1.0);
    }
}

inline fn accumulatePreparedLineCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    sample_root: f32,
    sample_along: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const denom = curve.a_root;
    if (@abs(denom) < 1e-10) return;

    const t_raw = -(curve.p0_root - sample_root) / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (t >= 1.0 - 1e-5) return;

    const derivative_axis = if (horizontal) curve.a_root else -curve.a_root;
    if (@abs(derivative_axis) <= 1e-5) return;

    const distance = (curve.p0_along - sample_along + curve.a_along * t) * ppe;
    appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
}

inline fn solvePreparedConicRoots(cold: *const PreparedAxisCurveCold, sample_root: f32) CurveRoots {
    return solveQuadraticRoots(
        cold.conic_num_a_root - sample_root * cold.conic_den_a,
        cold.conic_num_b_root - sample_root * cold.conic_den_b,
        cold.conic_num_c_root - sample_root * cold.conic_den_c,
    );
}

inline fn solvePreparedCubicRoots(curve: *const PreparedAxisCurve, cold: *const PreparedAxisCurveCold, sample_root: f32) CurveRoots {
    return solveCubicRoots(
        cold.cubic_a_root,
        cold.cubic_b_root,
        cold.cubic_c_root,
        curve.p0_root - sample_root,
    );
}

inline fn evaluatePreparedConicAlong(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    const denom = @max((cold.conic_den_a * t + cold.conic_den_b) * t + cold.conic_den_c, 1.0 / 65536.0);
    return ((cold.conic_num_a_along * t + cold.conic_num_b_along) * t + cold.conic_num_c_along) / denom;
}

inline fn derivativePreparedConicRoot(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    const denom = @max((cold.conic_den_a * t + cold.conic_den_b) * t + cold.conic_den_c, 1.0 / 65536.0);
    const denom_prime = 2.0 * cold.conic_den_a * t + cold.conic_den_b;
    const n = (cold.conic_num_a_root * t + cold.conic_num_b_root) * t + cold.conic_num_c_root;
    const n_prime = 2.0 * cold.conic_num_a_root * t + cold.conic_num_b_root;
    const inv = 1.0 / (denom * denom);
    return (n_prime * denom - n * denom_prime) * inv;
}

inline fn evaluatePreparedCubicAlong(curve: *const PreparedAxisCurve, cold: *const PreparedAxisCurveCold, t: f32) f32 {
    return ((cold.cubic_a_along * t + cold.cubic_b_along) * t + cold.cubic_c_along) * t + curve.p0_along;
}

inline fn derivativePreparedCubicRoot(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    return (3.0 * cold.cubic_a_root * t + 2.0 * cold.cubic_b_root) * t + cold.cubic_c_root;
}

fn preparedCurveCold(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold) *const PreparedAxisCurveCold {
    if (curve.cold_index >= cold_curves.len) {
        @panic("prepared conic/cubic curve is missing cold coefficient data");
    }
    return &cold_curves[curve.cold_index];
}

inline fn accumulatePreparedCurveCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    cold_curves: []const PreparedAxisCurveCold,
    sample_rc: Vec2,
    ppe: f32,
    comptime horizontal: bool,
) CoverageScan {
    const sample_root = if (horizontal) sample_rc.y else sample_rc.x;
    const sample_along = if (horizontal) sample_rc.x else sample_rc.y;
    const max_coord = curve.max_axis - sample_along;
    if (max_coord * ppe < -0.5) return .stop_scan;

    if (curve.kind == .quadratic) {
        accumulatePreparedQuadraticCoverage(result, curve, sample_root, sample_along, ppe, horizontal);
        return .continue_scan;
    }

    if (curve.kind == .line) {
        accumulatePreparedLineCoverage(
            result,
            curve,
            sample_root,
            sample_along,
            ppe,
            horizontal,
        );
        return .continue_scan;
    }

    const cold = preparedCurveCold(curve, cold_curves);
    const roots = switch (curve.kind) {
        .conic => solvePreparedConicRoots(cold, sample_root),
        .cubic => solvePreparedCubicRoots(curve, cold, sample_root),
        .quadratic, .line => unreachable,
    };

    for (roots.t[0..roots.count]) |t| {
        if (t >= 1.0 - 1e-5) continue;
        const along = switch (curve.kind) {
            .conic => evaluatePreparedConicAlong(cold, t),
            .cubic => evaluatePreparedCubicAlong(curve, cold, t),
            .quadratic, .line => unreachable,
        };
        const root_deriv = switch (curve.kind) {
            .conic => derivativePreparedConicRoot(cold, t),
            .cubic => derivativePreparedCubicRoot(cold, t),
            .quadratic, .line => unreachable,
        };
        const derivative_axis = if (horizontal) root_deriv else -root_deriv;
        if (@abs(derivative_axis) <= 1e-5) continue;
        const distance = (along - sample_along) * ppe;
        appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
    }
    return .continue_scan;
}

fn evalPreparedGlyphCoverageAxisFromBand(page: anytype, sample_rc: Vec2, ppe: f32, band_base: usize, count: u32, comptime horizontal: bool) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const curves = if (horizontal) page.h_curves else page.v_curves;
    const cold_curves = if (horizontal) page.h_cold_curves else page.v_cold_curves;
    if (band_base >= curves.len) return result;
    const band_count = @min(@as(usize, count), curves.len - band_base);
    const band_curves = curves[band_base..][0..band_count];

    var i: usize = 0;
    while (i < band_count) : (i += 1) {
        const curve = &band_curves[i];
        if (!curve.valid) continue;
        if (accumulatePreparedCurveCoverage(&result, curve, cold_curves, sample_rc, ppe, horizontal) == .stop_scan) break;
    }
    return result;
}

fn evalGlyphCoverageAxis(page: anytype, sample_rc: Vec2, ppe: f32, band_base: usize, count: u32, comptime horizontal: bool) CoveragePair {
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "h_curves")) {
        return evalPreparedGlyphCoverageAxisFromBand(page, sample_rc, ppe, band_base, count, horizontal);
    }

    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const curve_base = readBandCurveBase(page, band_base + i) orelse continue;

        const tex0 = readCurveTexelF32Base(page, curve_base);
        const tex1 = readCurveTexelF32Base(page, curve_base + 4);
        const tex2 = readCurveTexelF32Base(page, curve_base + 8);

        const stored_kind = tex2[2];
        const direct_quadratic = stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5 and
            stored_kind < curve_tex.DIRECT_ENCODING_KIND_BIAS + 0.5;
        const packed_quadratic = stored_kind < 0.5;
        if (packed_quadratic or direct_quadratic) {
            const p0_abs = if (direct_quadratic)
                Vec2.new(tex0[0], tex0[1])
            else
                Vec2.new(
                    tex0[0] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[2],
                    tex0[1] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[3],
                );
            const p1_abs = if (direct_quadratic)
                Vec2.new(tex0[2], tex0[3])
            else
                Vec2.new(p0_abs.x + tex1[0], p0_abs.y + tex1[1]);
            const p2_abs = if (direct_quadratic)
                Vec2.new(tex1[0], tex1[1])
            else
                Vec2.new(p0_abs.x + tex1[2], p0_abs.y + tex1[3]);

            const p0x = p0_abs.x - sample_rc.x;
            const p0y = p0_abs.y - sample_rc.y;
            const p1x = p1_abs.x - sample_rc.x;
            const p1y = p1_abs.y - sample_rc.y;
            const p2x = p2_abs.x - sample_rc.x;
            const p2y = p2_abs.y - sample_rc.y;
            const max_coord = if (horizontal)
                @max(@max(p0x, p1x), p2x)
            else
                @max(@max(p0y, p1y), p2y);
            if (max_coord * ppe < -0.5) break;
            accumulateQuadraticCoverage(&result, p0x, p0y, p1x, p1y, p2x, p2y, ppe, horizontal);
            continue;
        }

        const direct_line = stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS + 2.5 and
            stored_kind < curve_tex.DIRECT_ENCODING_KIND_BIAS + 3.5;
        const packed_line = stored_kind >= 2.5 and stored_kind < 3.5;
        if (packed_line or direct_line) {
            const p0_abs = if (direct_line)
                Vec2.new(tex0[0], tex0[1])
            else
                Vec2.new(
                    tex0[0] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[2],
                    tex0[1] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[3],
                );
            const p2_abs = if (direct_line)
                Vec2.new(tex1[0], tex1[1])
            else
                Vec2.new(p0_abs.x + tex1[2], p0_abs.y + tex1[3]);

            const p0x = p0_abs.x - sample_rc.x;
            const p0y = p0_abs.y - sample_rc.y;
            const p2x = p2_abs.x - sample_rc.x;
            const p2y = p2_abs.y - sample_rc.y;
            const max_coord = if (horizontal) @max(p0x, p2x) else @max(p0y, p2y);
            if (max_coord * ppe < -0.5) break;
            accumulateLineCoverage(&result, p0x, p0y, p2x, p2y, ppe, horizontal);
            continue;
        }

        const meta = readCurveTexelF32Base(page, curve_base + 12);
        const segment = decodeCurveSegment(tex0, tex1, tex2, meta);
        if (accumulateGlyphCoverageSegment(&result, segment, sample_rc, ppe, horizontal) == .stop_scan) break;
    }
    return result;
}

fn evalGlyphHorizCoverage(page: anytype, rc: Vec2, x_offset: f32, ppe_x: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x + x_offset, rc.y), ppe_x, state.h_base, state.h_count, true);
}

fn evalGlyphVertCoverage(page: anytype, rc: Vec2, y_offset: f32, ppe_y: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x, rc.y + y_offset), ppe_y, state.v_base, state.v_count, false);
}

fn evalGlyphCoverage(
    page: anytype,
    em_x: f32,
    em_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    const state = initGlyphBandState(page, em_x, em_y, be, band_max_h, band_max_v);
    return resolveCoverage(
        evalGlyphHorizCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_x, state),
        evalGlyphVertCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_y, state),
        fill_rule,
    );
}

fn evalGlyphCoverageSubpixel(
    page: anytype,
    rc: Vec2,
    sample_dx: Vec2,
    sample_dy: Vec2,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
    subpixel_order: SubpixelOrder,
) SubpixelCoverage {
    const subpixel_ppe = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, subpixel_order);
    const step = Vec2.scale(switch (subpixel_order) {
        .rgb, .bgr => sample_dx,
        .vrgb, .vbgr => sample_dy,
        .none => Vec2.new(0.0, 0.0),
    }, 1.0 / 3.0);
    const reverse_order = subpixel_order == .bgr or subpixel_order == .vbgr;
    return switch (subpixel_order) {
        .rgb, .bgr, .vrgb, .vbgr => filterSubpixelCoverage(
            evalGlyphCoverage(page, rc.x - step.x * 3.0, rc.y - step.y * 3.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x - step.x * 2.0, rc.y - step.y * 2.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x - step.x * 1.0, rc.y - step.y * 1.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x, rc.y, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x + step.x * 1.0, rc.y + step.y * 1.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x + step.x * 2.0, rc.y + step.y * 2.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            evalGlyphCoverage(page, rc.x + step.x * 3.0, rc.y + step.y * 3.0, subpixel_ppe.x, subpixel_ppe.y, be, band_max_h, band_max_v, fill_rule),
            reverse_order,
        ),
        .none => .{ .rgb = .{ 0.0, 0.0, 0.0 }, .alpha = 0.0 },
    };
}

// ---------------------------------------------------------------------------
// Texture access helpers
// ---------------------------------------------------------------------------

fn readBandTexelLinear(page: anytype, texel_idx: usize) [2]u32 {
    const idx = texel_idx * 2;
    if (idx + 1 >= page.band_data.len) return .{ 0, 0 };
    return .{
        @as(u32, page.band_data[idx]),
        @as(u32, page.band_data[idx + 1]),
    };
}

fn readBandCurveBase(page: anytype, texel_idx: usize) ?usize {
    const ref = readBandTexelLinear(page, texel_idx);
    if (ref[0] >= page.curve_width or ref[1] >= page.curve_height) return null;
    return @as(usize, (ref[1] * page.curve_width + ref[0]) * 4);
}

fn readCurveTexelF32Base(page: anytype, idx: usize) [4]f32 {
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "curve_data_f32")) {
        if (idx + 3 >= page.curve_data_f32.len) return .{ 0, 0, 0, 0 };
        return .{
            page.curve_data_f32[idx + 0],
            page.curve_data_f32[idx + 1],
            page.curve_data_f32[idx + 2],
            page.curve_data_f32[idx + 3],
        };
    } else {
        if (idx + 3 >= page.curve_data.len) return .{ 0, 0, 0, 0 };
        return .{
            f16ToF32(page.curve_data[idx + 0]),
            f16ToF32(page.curve_data[idx + 1]),
            f16ToF32(page.curve_data[idx + 2]),
            f16ToF32(page.curve_data[idx + 3]),
        };
    }
}

fn readCurveTexelF32Slice(data: []const f32, idx: usize) [4]f32 {
    if (idx + 3 >= data.len) return .{ 0, 0, 0, 0 };
    return .{
        data[idx + 0],
        data[idx + 1],
        data[idx + 2],
        data[idx + 3],
    };
}

fn decodeCurveSegmentFromSlice(curve_data_f32: []const f32, curve_base: u32) CurveSegment {
    const base: usize = @intCast(curve_base);
    const tex0 = readCurveTexelF32Slice(curve_data_f32, base);
    const tex1 = readCurveTexelF32Slice(curve_data_f32, base + 4);
    const tex2 = readCurveTexelF32Slice(curve_data_f32, base + 8);
    const meta = readCurveTexelF32Slice(curve_data_f32, base + 12);
    return decodeCurveSegment(tex0, tex1, tex2, meta);
}

fn isDirectEncodedCurveKind(stored_kind: f32) bool {
    return stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5;
}

fn curveKindFromStoredKind(stored_kind: f32) bezier.CurveKind {
    const kind_u16: u16 = @intCast(if (isDirectEncodedCurveKind(stored_kind))
        @as(i32, @intFromFloat(@round(stored_kind - curve_tex.DIRECT_ENCODING_KIND_BIAS)))
    else
        @as(i32, @intFromFloat(@round(stored_kind))));
    return switch (kind_u16) {
        1 => .conic,
        2 => .cubic,
        3 => .line,
        else => .quadratic,
    };
}

fn decodeCurveSegment(tex0: [4]f32, tex1: [4]f32, tex2: [4]f32, meta: [4]f32) CurveSegment {
    const stored_kind = tex2[2];
    const kind = curveKindFromStoredKind(stored_kind);
    if (isDirectEncodedCurveKind(stored_kind)) {
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
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ay) < eps) {
        t1 = if (@abs(by) < eps) 0.0 else p1y * 0.5 / by;
        t2 = t1;
    } else {
        const sq = @sqrt(@max(by * by - ay * p1y, 0.0));
        if (by >= 0.0) {
            const q = by + sq;
            t2 = q / ay;
            t1 = if (@abs(q) < eps) 0.0 else p1y / q;
        } else {
            const q = by - sq;
            t1 = q / ay;
            t2 = if (@abs(q) < eps) 0.0 else p1y / q;
        }
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
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ax) < eps) {
        t1 = if (@abs(bx) < eps) 0.0 else p1x * 0.5 / bx;
        t2 = t1;
    } else {
        const sq = @sqrt(@max(bx * bx - ax * p1x, 0.0));
        if (bx >= 0.0) {
            const q = bx + sq;
            t2 = q / ax;
            t1 = if (@abs(q) < eps) 0.0 else p1x / q;
        } else {
            const q = bx - sq;
            t1 = q / ax;
            t2 = if (@abs(q) < eps) 0.0 else p1x / q;
        }
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
        if (mant == 0) return @bitCast(sign);
        // Subnormal: normalize.
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
        // Inf/NaN.
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

    var font = try snail.lowlevel.Font.init(font_data);
    defer font.deinit();

    var atlas = try snail.lowlevel.CurveAtlas.initAscii(testing.allocator, &font, &snail.ASCII_PRINTABLE);
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
    var prepared = try renderer_iface.uploadResourcesBlocking(testing.allocator, &resources);
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
    _ = try blob_builder.addText(.{}, "Hello, world!", 4, 32, 16, .{ 1, 1, 1, 1 });
    _ = try blob_builder.addText(.{}, "Hello, world!", 4, 56, 16, .{ 1, 0.4, 0.4, 1 });
    _ = try blob_builder.addText(.{}, "Hello, world!", 4, 80, 16, .{ 0.4, 1, 0.4, 1 });
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
    var serial_resources = try serial_cpu.uploadResourcesBlocking(testing.allocator, blk: {
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
    var threaded_resources = try threaded_cpu.uploadResourcesBlocking(testing.allocator, blk: {
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
    var prepared = try renderer.uploadResourcesBlocking(testing.allocator, &resources);
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
    var prepared = try renderer.uploadResourcesBlocking(testing.allocator, &resources);
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
