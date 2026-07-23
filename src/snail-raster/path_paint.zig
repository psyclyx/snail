//! Path paint decoding and sampling for the software rasterizer.

const std = @import("std");
const snail = @import("snail");
const color = @import("color.zig");
const atlas_mod = @import("snail");
const band_tex = @import("snail").render.geometry;
const render_abi = @import("snail").render.records;

const GlyphBandEntry = band_tex.GlyphBandEntry;
const Vec2 = snail.Vec2;
const clamp01 = color.clamp01;
const srgbToLinear = color.srgbToLinear;

pub const PreparedPathLayer = struct {
    band_entry: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    paint: PreparedPathPaint,
    /// Per-record winding rule, decoded from texel 0.x bit 15 (the
    /// "fill rule bit" set by `paint_records.write`). The CPU
    /// renderer threads this into evalGlyphCoverage* per record so
    /// fill rule is a geometry property, not a per-frame uniform.
    fill_rule: snail.FillRule = .non_zero,
};

pub const PreparedPathRecord = struct {
    texel_offset: u32,
    tag: i32,
    composite_mode: i32 = 0,
    layer_start: usize,
    layer_count: usize,
};

pub const LayerInfoEntry = struct {
    data: []const f32 = &.{},
    width: u32 = 0,
    height: u32 = 0,
    row_base: u32 = 0,
    path_records: []PreparedPathRecord = &.{},
    path_layers: []PreparedPathLayer = &.{},
    owns_data: bool = false,
    owned_images: []snail.Image = &.{},

    pub fn deinit(self: *LayerInfoEntry, allocator: std.mem.Allocator) void {
        if (self.owns_data and self.data.len > 0) allocator.free(self.data);
        if (self.path_records.len > 0) allocator.free(self.path_records);
        if (self.path_layers.len > 0) allocator.free(self.path_layers);
        for (self.owned_images) |*image| image.deinit();
        if (self.owned_images.len > 0) allocator.free(self.owned_images);
        self.* = .{};
    }

    pub fn pathRecordAt(self: *const LayerInfoEntry, info_x: u16, info_y: u16) ?*const PreparedPathRecord {
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

pub const ResolvedLayerInfo = struct {
    entry: *const LayerInfoEntry,
    local_y: u16,
};

/// Fetch one texel from a layer-info slab. Returns null when the computed
/// texel falls outside `data`: special draw records carry caller-chosen
/// (info_x, info_y) coordinates, and the malformed-records contract requires
/// treating an out-of-range fetch like any other invalid record rather than
/// reading out of bounds.
pub fn fetchLayerInfoTexel(data: []const f32, width: u32, info_x: u16, info_y: u16, offset: u32) ?[4]f32 {
    if (width == 0) return null;
    const texel = @as(usize, info_x) + @as(usize, offset);
    const x = texel % @as(usize, width);
    const y = @as(usize, info_y) + texel / @as(usize, width);
    const base = (y * @as(usize, width) + x) * 4;
    if (base > data.len or data.len - base < 4) return null;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

pub fn fetchLayerInfoTexelOffset(data: []const f32, texel_offset: u32) [4]f32 {
    const base = @as(usize, texel_offset) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

pub fn pathInfoTag(info: [4]f32) i32 {
    // Layer-info also contains non-paint records whose fourth component may
    // be arbitrary packed bits. Recognize only exact paint sentinels; all
    // other values, including NaN/Inf, are non-paint texels. This avoids a
    // float-to-int trap while preserving mixed-record slab scanning.
    const raw = -info[3];
    if (raw == 1) return 1;
    if (raw == 2) return 2;
    if (raw == 3) return 3;
    if (raw == 4) return 4;
    if (raw == 5) return 5;
    if (raw == 6) return 6;
    return 0;
}

pub const PreparedPathLayerInfo = struct {
    records: []PreparedPathRecord,
    layers: []PreparedPathLayer,
};

const PreparedPathLayerInfoCounts = struct {
    records: usize = 0,
    layers: usize = 0,
    texels: u32 = 0,
};

const PathRecordDescriptor = struct {
    texel_offset: u32,
    layer_count: u16 = 1,
    image: ?*const snail.Image = null,
    image_layer: u32 = 0,
    first_image_use: bool = false,
};

pub const PreparePathLayerInfoError = std.mem.Allocator.Error || error{InvalidLayerInfo};

fn exactUnsigned(raw: f32, max: u32) ?u32 {
    if (!std.math.isFinite(raw) or raw < 0 or @as(f64, raw) > @as(f64, @floatFromInt(max))) return null;
    const rounded = @round(raw);
    if (raw != rounded) return null;
    return @intFromFloat(rounded);
}

fn validStraightColor(value: [4]f32) bool {
    for (value) |component| if (!std.math.isFinite(component)) return false;
    return value[3] >= 0 and value[3] <= 1;
}

fn validatePreparedPathLayer(data: []const f32, descriptor: anytype) error{InvalidLayerInfo}!void {
    const texel_offset = descriptor.texel_offset;
    const info = fetchLayerInfoTexelOffset(data, texel_offset);
    const tag = pathInfoTag(info);
    if (tag != 1 and tag != 2 and tag != 3 and tag != 4 and tag != 6) return error.InvalidLayerInfo;

    // The packed band-count word in info[2] may legitimately have a NaN bit
    // pattern. Every other scalar in a paint record is numeric and must be
    // finite before sampling or integer conversion.
    const base = @as(usize, texel_offset) * 4;
    for (0..6 * 4) |i| {
        if (i == 2) continue;
        if (!std.math.isFinite(data[base + i])) return error.InvalidLayerInfo;
    }
    _ = exactUnsigned(info[0], std.math.maxInt(u16)) orelse return error.InvalidLayerInfo;
    _ = exactUnsigned(info[1], std.math.maxInt(u16)) orelse return error.InvalidLayerInfo;
    const packed_band_counts: u32 = @bitCast(info[2]);
    // `unpackBandCounts` narrows `(raw + 1)` to u16, so reject malformed
    // fields before calling it. In particular, 0xffff would otherwise trap
    // while decoding caller-mutated page bytes.
    if ((packed_band_counts & 0xffff) >= 16 or (packed_band_counts >> 16) >= 16) {
        return error.InvalidLayerInfo;
    }

    const data0 = fetchLayerInfoTexelOffset(data, texel_offset + 2);
    switch (tag) {
        1 => {
            if (descriptor.image != null or descriptor.image_layer != 0 or descriptor.first_image_use or
                !validStraightColor(data0)) return error.InvalidLayerInfo;
        },
        2 => {
            if (descriptor.image != null or descriptor.image_layer != 0 or descriptor.first_image_use) return error.InvalidLayerInfo;
            if (!validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 3)) or
                !validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 4)))
            {
                return error.InvalidLayerInfo;
            }
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            _ = exactUnsigned(extra[0], 2) orelse return error.InvalidLayerInfo;
        },
        3 => {
            if (descriptor.image != null or descriptor.image_layer != 0 or descriptor.first_image_use) return error.InvalidLayerInfo;
            if (data0[2] <= 0 or
                !validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 3)) or
                !validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 4)))
            {
                return error.InvalidLayerInfo;
            }
            _ = exactUnsigned(data0[3], 2) orelse return error.InvalidLayerInfo;
        },
        6 => {
            if (descriptor.image != null or descriptor.image_layer != 0 or descriptor.first_image_use) return error.InvalidLayerInfo;
            if (!validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 3)) or
                !validStraightColor(fetchLayerInfoTexelOffset(data, texel_offset + 4)))
            {
                return error.InvalidLayerInfo;
            }
            _ = exactUnsigned(data0[3], 2) orelse return error.InvalidLayerInfo;
        },
        4 => {
            const image = descriptor.image orelse return error.InvalidLayerInfo;
            if (image.bytesPerTexel() != 4) return error.InvalidLayerInfo;
            const data1 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            _ = exactUnsigned(data1[3], 1) orelse return error.InvalidLayerInfo;
            _ = exactUnsigned(extra[2], 2) orelse return error.InvalidLayerInfo;
            _ = exactUnsigned(extra[3], 2) orelse return error.InvalidLayerInfo;
        },
        else => unreachable,
    }
}

fn countPreparedPathLayerInfo(
    data: []const f32,
    width: u32,
    height: u32,
    descriptors: anytype,
) error{InvalidLayerInfo}!PreparedPathLayerInfoCounts {
    if ((width == 0) != (height == 0)) return error.InvalidLayerInfo;
    const texel_count_usize = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch
        return error.InvalidLayerInfo;
    const float_count = std.math.mul(usize, texel_count_usize, 4) catch return error.InvalidLayerInfo;
    if (data.len != float_count or texel_count_usize > std.math.maxInt(u32)) return error.InvalidLayerInfo;
    const texel_count: u32 = @intCast(texel_count_usize);
    var counts = PreparedPathLayerInfoCounts{ .texels = texel_count };
    var descriptor_index: usize = 0;
    var previous_end: u32 = 0;
    while (descriptor_index < descriptors.len) {
        const descriptor = descriptors[descriptor_index];
        const texel = descriptor.texel_offset;
        if (descriptor.layer_count == 0 or texel < previous_end or texel >= texel_count) return error.InvalidLayerInfo;
        const info = fetchLayerInfoTexelOffset(data, texel);
        if (descriptor.layer_count == 1) {
            if (texel_count - texel < 6 or pathInfoTag(info) == 5) return error.InvalidLayerInfo;
            try validatePreparedPathLayer(data, descriptor);
            previous_end = texel + 6;
            counts.records = std.math.add(usize, counts.records, 1) catch return error.InvalidLayerInfo;
            counts.layers = std.math.add(usize, counts.layers, 1) catch return error.InvalidLayerInfo;
            descriptor_index += 1;
            continue;
        }

        if (descriptor.image != null or descriptor.image_layer != 0 or descriptor.first_image_use or
            pathInfoTag(info) != 5) return error.InvalidLayerInfo;
        const layer_count: u32 = descriptor.layer_count;
        if (exactUnsigned(info[0], std.math.maxInt(u16)) != layer_count or
            exactUnsigned(info[1], 1) == null or !std.math.isFinite(info[2])) return error.InvalidLayerInfo;
        const record_texels = std.math.add(u32, std.math.mul(u32, layer_count, 6) catch
            return error.InvalidLayerInfo, 1) catch return error.InvalidLayerInfo;
        if (record_texels > texel_count - texel or
            layer_count > descriptors.len - descriptor_index - 1) return error.InvalidLayerInfo;
        for (0..layer_count) |layer_index| {
            const layer_descriptor = descriptors[descriptor_index + 1 + layer_index];
            const expected_offset = texel + 1 + @as(u32, @intCast(layer_index)) * 6;
            if (layer_descriptor.layer_count != 1 or layer_descriptor.texel_offset != expected_offset) {
                return error.InvalidLayerInfo;
            }
            try validatePreparedPathLayer(data, layer_descriptor);
        }
        previous_end = texel + record_texels;
        counts.records = std.math.add(usize, counts.records, 1) catch return error.InvalidLayerInfo;
        counts.layers = std.math.add(usize, counts.layers, layer_count) catch return error.InvalidLayerInfo;
        descriptor_index += 1 + layer_count;
    }
    return counts;
}

pub fn preparePathLayerInfoRecords(
    allocator: std.mem.Allocator,
    data: []const f32,
    width: u32,
    height: u32,
    descriptors: anytype,
) PreparePathLayerInfoError!PreparedPathLayerInfo {
    // The entire mixed slab is structurally validated before allocating output
    // or decoding a single record. The second pass is therefore infallible and
    // cannot publish partially initialized slices.
    const counts = try countPreparedPathLayerInfo(data, width, height, descriptors);
    const records = try allocator.alloc(PreparedPathRecord, counts.records);
    errdefer allocator.free(records);
    const layers = try allocator.alloc(PreparedPathLayer, counts.layers);
    errdefer allocator.free(layers);

    var record_index: usize = 0;
    var layer_index: usize = 0;
    var descriptor_index: usize = 0;
    while (descriptor_index < descriptors.len) {
        const descriptor = descriptors[descriptor_index];
        const texel = descriptor.texel_offset;
        const info = fetchLayerInfoTexelOffset(data, texel);
        const tag = pathInfoTag(info);
        const descriptor_count: usize = descriptor.layer_count;
        records[record_index] = .{
            .texel_offset = texel,
            .tag = tag,
            .composite_mode = if (descriptor_count > 1) @intFromFloat(info[1]) else 0,
            .layer_start = layer_index,
            .layer_count = descriptor_count,
        };
        if (descriptor_count == 1) {
            layers[layer_index] = preparePathLayerFromLayerInfoOffset(data, descriptor);
            descriptor_index += 1;
        } else {
            for (0..descriptor_count) |i| {
                layers[layer_index + i] = preparePathLayerFromLayerInfoOffset(data, descriptors[descriptor_index + 1 + i]);
            }
            descriptor_index += 1 + descriptor_count;
        }
        record_index += 1;
        layer_index += descriptor_count;
    }

    return .{ .records = records, .layers = layers };
}

pub fn preparePathLayerInfoWithoutPaint(
    allocator: std.mem.Allocator,
    data: []const f32,
    width: u32,
    height: u32,
) PreparePathLayerInfoError!PreparedPathLayerInfo {
    const no_descriptors = [_]PathRecordDescriptor{};
    return preparePathLayerInfoRecords(allocator, data, width, height, &no_descriptors);
}

fn preparePathLayerFromLayerInfoOffset(
    data: []const f32,
    descriptor: anytype,
) PreparedPathLayer {
    const texel_offset = descriptor.texel_offset;
    const info = fetchLayerInfoTexelOffset(data, texel_offset);
    const band = fetchLayerInfoTexelOffset(data, texel_offset + 1);
    const band_counts = render_abi.unpackBandCounts(@bitCast(info[2])) orelse unreachable;
    const packed_gx: u16 = @intFromFloat(info[0]);
    const FILL_RULE_BIT: u16 = 1 << 15;
    const fill_rule: snail.FillRule = if ((packed_gx & FILL_RULE_BIT) != 0) .even_odd else .non_zero;
    const be = GlyphBandEntry{
        .glyph_x = packed_gx & (FILL_RULE_BIT - 1),
        .glyph_y = @intFromFloat(info[1]),
        .h_band_count = band_counts.h,
        .v_band_count = band_counts.v,
        .band_scale_x = band[0],
        .band_scale_y = band[1],
        .band_offset_x = band[2],
        .band_offset_y = band[3],
    };
    return .{
        .band_entry = be,
        .band_max_h = @as(i32, @intCast(be.h_band_count)) - 1,
        .band_max_v = @as(i32, @intCast(be.v_band_count)) - 1,
        .paint = preparePathPaintFromLayerInfoOffset(data, descriptor),
        .fill_rule = fill_rule,
    };
}

fn preparePathPaintFromLayerInfoOffset(
    data: []const f32,
    descriptor: anytype,
) PreparedPathPaint {
    const texel_offset = descriptor.texel_offset;
    const info = fetchLayerInfoTexelOffset(data, texel_offset);
    const tag = pathInfoTag(info);
    const data0 = fetchLayerInfoTexelOffset(data, texel_offset + 2);
    switch (tag) {
        1 => return .{ .kind = .solid, .color0 = data0 },
        2 => {
            // Endpoints are linear (API colors are linear and paint_records
            // stores them verbatim), so the sampler interpolates directly.
            const color0 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const color1 = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            return .{
                .kind = .linear_gradient,
                .data0 = data0,
                .color0 = color0,
                .color1 = color1,
                .extra = extra,
            };
        },
        3 => {
            const color0 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const color1 = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            return .{
                .kind = .radial_gradient,
                .data0 = data0,
                .color0 = color0,
                .color1 = color1,
            };
        },
        6 => {
            const color0 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const color1 = fetchLayerInfoTexelOffset(data, texel_offset + 4);
            return .{
                .kind = .conic_gradient,
                .data0 = data0,
                .color0 = color0,
                .color1 = color1,
            };
        },
        4 => {
            const data1 = fetchLayerInfoTexelOffset(data, texel_offset + 3);
            const extra = fetchLayerInfoTexelOffset(data, texel_offset + 5);
            return .{
                .kind = .image,
                .data0 = data0,
                .data1 = data1,
                .extra = extra,
                .image = descriptor.image,
            };
        },
        else => return .{},
    }
}

pub fn compositeOver(src: [4]f32, dst: [4]f32) [4]f32 {
    const inv_a = 1.0 - src[3];
    return .{
        src[0] + dst[0] * inv_a,
        src[1] + dst[1] * inv_a,
        src[2] + dst[2] * inv_a,
        src[3] + dst[3] * inv_a,
    };
}

pub fn addColors(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
}

fn wrapPaintT(t: f32, extend_mode: snail.PaintExtend) f32 {
    // Arithmetic on otherwise finite transforms can overflow at extreme
    // coordinates. GPU sampling of NaN/Inf is not useful or portable; choose
    // a deterministic edge sample and, critically, keep the CPU path total.
    if (!std.math.isFinite(t)) {
        return if (extend_mode == .clamp and t > 0) 1.0 else 0.0;
    }
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
    if (!std.math.isFinite(raw)) return .clamp;
    if (raw == 1.0) return .repeat;
    if (raw == 2.0) return .reflect;
    return .clamp;
}

/// This renderer's image-format contract (the CPU analog of a GPU host
/// binding an sRGB texture): 4 bytes/texel, RGBA order, sRGB-encoded RGB
/// with straight linear alpha, decoded to linear before filtering.
fn sampleImageTexelLinear(image: *const snail.Image, x: u32, y: u32) [4]f32 {
    if (x >= image.width or y >= image.height) return .{ 0, 0, 0, 0 };
    const idx = (@as(usize, y) * @as(usize, image.width) + @as(usize, x)) * 4;
    if (idx > image.texels.len or image.texels.len - idx < 4) return .{ 0, 0, 0, 0 };
    return .{
        srgbToLinear(image.texels[idx + 0]),
        srgbToLinear(image.texels[idx + 1]),
        srgbToLinear(image.texels[idx + 2]),
        @as(f32, @floatFromInt(image.texels[idx + 3])) / 255.0,
    };
}

fn lerpColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    const wide_t: f64 = t;
    const one_minus_t = 1.0 - wide_t;
    var out: [4]f32 = undefined;
    inline for (0..4) |i| {
        out[i] = @floatCast(@as(f64, a[i]) * one_minus_t + @as(f64, b[i]) * wide_t);
    }
    return out;
}

fn clampTexelIndex(index: i64, extent: u32) u32 {
    std.debug.assert(extent > 0);
    if (index <= 0) return 0;
    return @intCast(@min(index, @as(i64, extent - 1)));
}

fn nearestTexelIndex(t: f32, extent: u32) u32 {
    std.debug.assert(extent > 0);
    if (!std.math.isFinite(t) or t <= 0) return 0;
    if (t >= 1) return extent - 1;
    const scaled = @as(f64, t) * @as(f64, @floatFromInt(extent));
    return @intCast(@min(@as(u64, @intFromFloat(@floor(scaled))), @as(u64, extent - 1)));
}

fn sampleImageLinear(image: *const snail.Image, uv: Vec2, filter: snail.ImageFilter) [4]f32 {
    if (image.bytesPerTexel() != 4) return .{ 0, 0, 0, 0 };
    if (filter == .nearest) {
        const x = nearestTexelIndex(uv.x, image.width);
        const y = nearestTexelIndex(uv.y, image.height);
        return sampleImageTexelLinear(image, x, y);
    }

    // Wrapped UVs are in [0,1]. Wide intermediates keep max-u32 texture
    // dimensions representable and make the subsequent integer conversion
    // total even when f32 cannot distinguish the final texels.
    const fx = @as(f64, uv.x) * @as(f64, @floatFromInt(image.width)) - 0.5;
    const fy = @as(f64, uv.y) * @as(f64, @floatFromInt(image.height)) - 0.5;
    const raw_x0: i64 = @intFromFloat(@floor(fx));
    const raw_y0: i64 = @intFromFloat(@floor(fy));
    // Clamp the two raw taps independently. Deriving x1/y1 from an already
    // clamped lower tap incorrectly blends the first two texels at uv=0,
    // unlike hardware linear sampling with clamp-to-edge.
    const x0 = clampTexelIndex(raw_x0, image.width);
    const y0 = clampTexelIndex(raw_y0, image.height);
    const x1 = clampTexelIndex(raw_x0 + 1, image.width);
    const y1 = clampTexelIndex(raw_y0 + 1, image.height);
    const tx = clamp01(@floatCast(fx - @floor(fx)));
    const ty = clamp01(@floatCast(fy - @floor(fy)));

    const c00 = sampleImageTexelLinear(image, x0, y0);
    const c10 = sampleImageTexelLinear(image, x1, y0);
    const c01 = sampleImageTexelLinear(image, x0, y1);
    const c11 = sampleImageTexelLinear(image, x1, y1);
    const top = lerpColor(c00, c10, tx);
    const bottom = lerpColor(c01, c11, tx);
    return lerpColor(top, bottom, ty);
}

pub const PathPaintSample = struct {
    color: [4]f32,
    apply_dither: bool = false,
};

pub const PreparedPathPaint = struct {
    const Kind = enum {
        invalid,
        solid,
        linear_gradient,
        radial_gradient,
        conic_gradient,
        image,
    };

    kind: Kind = .invalid,
    color0: [4]f32 = .{ 1, 0, 1, 1 },
    color1: [4]f32 = .{ 1, 0, 1, 1 },
    data0: [4]f32 = .{ 0, 0, 0, 0 },
    data1: [4]f32 = .{ 0, 0, 0, 0 },
    extra: [4]f32 = .{ 0, 0, 0, 0 },
    image: ?*const snail.Image = null,

    pub fn sample(self: *const PreparedPathPaint, local: Vec2) PathPaintSample {
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
                    .color = lerpColor(self.color0, self.color1, wrapPaintT(t, paintExtendFromFloat(self.extra[0]))),
                    .apply_dither = true,
                };
            },
            .radial_gradient => blk: {
                const center = Vec2.new(self.data0[0], self.data0[1]);
                const radius = @max(@abs(self.data0[2]), 1.0 / 65536.0);
                const t = Vec2.length(Vec2.sub(local, center)) / radius;
                break :blk .{
                    .color = lerpColor(self.color0, self.color1, wrapPaintT(t, paintExtendFromFloat(self.data0[3]))),
                    .apply_dither = true,
                };
            },
            .conic_gradient => blk: {
                // data0.xy = center, data0.z = start angle, data0.w = extend.
                const center = Vec2.new(self.data0[0], self.data0[1]);
                const d = Vec2.sub(local, center);
                const t = (std.math.atan2(d.y, d.x) - self.data0[2]) * (1.0 / (2.0 * std.math.pi));
                break :blk .{
                    .color = lerpColor(self.color0, self.color1, wrapPaintT(t, paintExtendFromFloat(self.data0[3]))),
                    .apply_dither = true,
                };
            },
            .image => blk: {
                const image = self.image orelse break :blk .{ .color = .{ 1, 0, 1, 1 } };
                break :blk samplePreparedImage(image, self.data0, self.data1, self.extra, local);
            },
            .invalid => .{ .color = .{ 1, 0, 1, 1 } },
        };
    }
};

fn samplePreparedImage(
    image: *const snail.Image,
    data0: [4]f32,
    data1: [4]f32,
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
    const filter: snail.ImageFilter = if (data1[3] == 1.0) .nearest else .linear;
    // Image color modulation is per-instance tint, applied by the renderer
    // after sampling — not a per-paint field.
    return .{ .color = sampleImageLinear(image, uv, filter) };
}

// ── paint evaluator vector tests ───────────────────────────────────────────
//
// These pin the CPU paint semantics kind-by-kind. They are the source of
// truth the GLSL evaluator (`snail_path_frag_body.glsl`) must match — the two
// are hand-synced, so a drift here or there shows up as a CPU/GPU mismatch.
// Gradients interpolate their (linear-stored) endpoints in linear light, so a
// 0→1 ramp sampled at t lands on t.

const testing = std.testing;
const test_simple_descriptors = [_]PathRecordDescriptor{.{ .texel_offset = 0 }};
const test_no_descriptors = [_]PathRecordDescriptor{};
const test_composite_descriptors = [_]PathRecordDescriptor{
    .{ .texel_offset = 0, .layer_count = 2 },
    .{ .texel_offset = 1 },
    .{ .texel_offset = 7 },
};

fn validSolidLayerInfo() [24]f32 {
    var data = [_]f32{0} ** 24;
    data[0] = 3;
    data[1] = 4;
    // Band counts are stored as `(count - 1)` in each 16-bit lane; 1x1 is 0.
    data[2] = @bitCast(@as(u32, 0));
    data[3] = -1;
    data[4] = 1;
    data[5] = 1;
    data[8] = 0.25;
    data[9] = 0.5;
    data[10] = 0.75;
    data[11] = 1;
    return data;
}

fn freePreparedPathLayerInfo(allocator: std.mem.Allocator, prepared: PreparedPathLayerInfo) void {
    allocator.free(prepared.records);
    allocator.free(prepared.layers);
}

fn validCompositeLayerInfo() [52]f32 {
    var data = [_]f32{0} ** 52;
    data[0] = 2;
    data[1] = 0;
    data[3] = -5;
    const solid = validSolidLayerInfo();
    @memcpy(data[4..28], &solid);
    @memcpy(data[28..52], &solid);
    return data;
}

fn exercisePrepareCompositeAllocationFailures(allocator: std.mem.Allocator, data: *const [52]f32) !void {
    const prepared = try preparePathLayerInfoRecords(allocator, data, 13, 1, &test_composite_descriptors);
    defer freePreparedPathLayerInfo(allocator, prepared);
    try testing.expectEqual(@as(usize, 1), prepared.records.len);
    try testing.expectEqual(@as(usize, 2), prepared.layers.len);
}

fn exercisePreparePathLayerInfoAllocationFailures(allocator: std.mem.Allocator, data: *const [24]f32) !void {
    const prepared = try preparePathLayerInfoRecords(allocator, data, 6, 1, &test_simple_descriptors);
    defer freePreparedPathLayerInfo(allocator, prepared);
    try testing.expectEqual(@as(usize, 1), prepared.records.len);
    try testing.expectEqual(@as(usize, 1), prepared.layers.len);
}

test "path layer-info preparation validates before allocation and cleans up failures" {
    var data = validSolidLayerInfo();
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exercisePreparePathLayerInfoAllocationFailures,
        .{&data},
    );

    var composite = validCompositeLayerInfo();
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exercisePrepareCompositeAllocationFailures,
        .{&composite},
    );

    var malformed = data;
    malformed[0] = std.math.nan(f32);
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(
        error.InvalidLayerInfo,
        preparePathLayerInfoRecords(failing.allocator(), &malformed, 6, 1, &test_simple_descriptors),
    );
}

test "layer-info texel fetch is bounds-checked against the slab" {
    const slab = [_]f32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    try testing.expectEqual([4]f32{ 1, 2, 3, 4 }, fetchLayerInfoTexel(&slab, 2, 0, 0, 0).?);
    try testing.expectEqual([4]f32{ 5, 6, 7, 8 }, fetchLayerInfoTexel(&slab, 2, 1, 0, 0).?);
    try testing.expectEqual(@as(?[4]f32, null), fetchLayerInfoTexel(&slab, 2, 0, 1, 0));
    // A caller-chosen info_x far outside the slab must not read out of bounds.
    try testing.expectEqual(@as(?[4]f32, null), fetchLayerInfoTexel(&slab, 2, 65535, 0, 0));
    try testing.expectEqual(@as(?[4]f32, null), fetchLayerInfoTexel(&slab, 0, 0, 0, 0));
}

test "path layer-info preparation rejects malformed dimensions and records without traps" {
    var data = validSolidLayerInfo();
    const simple = [_]PathRecordDescriptor{.{ .texel_offset = 0 }};
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, data[0..20], 5, 1, &simple));
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &data, 5, 1, &simple));
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &.{}, 0, 1, &simple));

    var composite = [_]f32{0} ** 4;
    composite[0] = std.math.floatMax(f32);
    composite[3] = -5;
    const composite_descriptors = [_]PathRecordDescriptor{.{ .texel_offset = 0, .layer_count = 2 }};
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &composite, 1, 1, &composite_descriptors));
    composite[0] = 1;
    composite[1] = 2;
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &composite, 1, 1, &composite_descriptors));
    composite[1] = 0;
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &composite, 1, 1, &composite_descriptors));

    data = validSolidLayerInfo();
    data[11] = 2;
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &data, 6, 1, &simple));

    data = validSolidLayerInfo();
    data[2] = @bitCast(@as(u32, std.math.maxInt(u32)));
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &data, 6, 1, &simple));

    data = validSolidLayerInfo();
    data[3] = -4;
    try testing.expectError(error.InvalidLayerInfo, preparePathLayerInfoRecords(testing.allocator, &data, 6, 1, &simple));

    // Mixed slabs may contain arbitrary packed values in non-paint texels.
    // They are ignored rather than converted to integers.
    const packed_nonpaint = [_]f32{ 0, 0, 0, std.math.nan(f32) };
    const empty = try preparePathLayerInfoRecords(testing.allocator, &packed_nonpaint, 1, 1, &test_no_descriptors);
    defer freePreparedPathLayerInfo(testing.allocator, empty);
    try testing.expectEqual(@as(usize, 0), empty.records.len);

    // Explicit descriptors prevent ordinary autohint payload values from
    // being misclassified as paint sentinels.
    var autohint_like = [_]f32{0} ** 24;
    autohint_like[11] = -1;
    const no_paints = try preparePathLayerInfoRecords(testing.allocator, &autohint_like, 6, 1, &test_no_descriptors);
    defer freePreparedPathLayerInfo(testing.allocator, no_paints);
    try testing.expectEqual(@as(usize, 0), no_paints.records.len);
}

test "solid paint samples its stored linear color, position-independent" {
    const p = PreparedPathPaint{ .kind = .solid, .color0 = .{ 0.25, 0.5, 0.75, 1.0 } };
    try testing.expectEqual([4]f32{ 0.25, 0.5, 0.75, 1.0 }, p.sample(Vec2.new(3, 7)).color);
    try testing.expectEqual([4]f32{ 0.25, 0.5, 0.75, 1.0 }, p.sample(Vec2.new(-9, 2)).color);
    try testing.expect(!p.sample(Vec2.new(0, 0)).apply_dither);
}

test "linear gradient projects position onto the axis and mixes in linear light" {
    const p = PreparedPathPaint{
        .kind = .linear_gradient,
        .data0 = .{ 0, 0, 10, 0 }, // start (0,0) → end (10,0)
        .color0 = .{ 0, 0, 0, 1 },
        .color1 = .{ 1, 1, 1, 1 },
        .extra = .{ 0, 0, 0, 0 }, // clamp
    };
    try testing.expectApproxEqAbs(@as(f32, 0), p.sample(Vec2.new(0, 0)).color[0], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1), p.sample(Vec2.new(10, 0)).color[0], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(5, 0)).color[0], 1e-4);
    // Off-axis position projects onto the axis (y is ignored here).
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(5, 99)).color[0], 1e-4);
    try testing.expect(p.sample(Vec2.new(5, 0)).apply_dither);
}

test "gradient interpolation keeps opposite finite HDR endpoints finite" {
    const limit = std.math.floatMax(f32);
    const mixed = lerpColor(.{ -limit, limit, -limit, 0 }, .{ limit, -limit, limit, 1 }, 0.5);
    try testing.expectEqual([4]f32{ 0, 0, 0, 0.5 }, mixed);
}

test "linear gradient extend modes past the endpoints" {
    var p = PreparedPathPaint{
        .kind = .linear_gradient,
        .data0 = .{ 0, 0, 10, 0 },
        .color0 = .{ 0, 0, 0, 1 },
        .color1 = .{ 1, 1, 1, 1 },
        .extra = .{ 0, 0, 0, 0 },
    };
    // x = 15 → t = 1.5
    p.extra[0] = 0; // clamp → 1.0 → white
    try testing.expectApproxEqAbs(@as(f32, 1), p.sample(Vec2.new(15, 0)).color[0], 1e-4);
    p.extra[0] = 1; // repeat → fract(1.5) = 0.5
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(15, 0)).color[0], 1e-4);
    p.extra[0] = 2; // reflect → 0.5
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(15, 0)).color[0], 1e-4);
}

test "radial gradient maps distance/radius to t" {
    const p = PreparedPathPaint{
        .kind = .radial_gradient,
        .data0 = .{ 0, 0, 10, 0 }, // center (0,0), radius 10, clamp
        .color0 = .{ 0, 0, 0, 1 },
        .color1 = .{ 1, 1, 1, 1 },
    };
    try testing.expectApproxEqAbs(@as(f32, 0), p.sample(Vec2.new(0, 0)).color[0], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1), p.sample(Vec2.new(10, 0)).color[0], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1), p.sample(Vec2.new(0, 10)).color[0], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(5, 0)).color[0], 1e-4);
}

test "conic gradient sweeps angle to t" {
    const p = PreparedPathPaint{
        .kind = .conic_gradient,
        .data0 = .{ 0, 0, 0, 1 }, // center (0,0), start angle 0, repeat
        .color0 = .{ 0, 0, 0, 1 },
        .color1 = .{ 1, 1, 1, 1 },
    };
    try testing.expectApproxEqAbs(@as(f32, 0), p.sample(Vec2.new(1, 0)).color[0], 1e-4); // angle 0 → t 0
    try testing.expectApproxEqAbs(@as(f32, 0.25), p.sample(Vec2.new(0, 1)).color[0], 1e-4); // π/2 → t .25
    try testing.expectApproxEqAbs(@as(f32, 0.5), p.sample(Vec2.new(-1, 0)).color[0], 1e-4); // π → t .5
    try testing.expectApproxEqAbs(@as(f32, 0.75), p.sample(Vec2.new(0, -1)).color[0], 1e-4); // -π/2 → t .75
}

test "linear image sampling matches hardware clamp at horizontal edges and seams" {
    var image = try snail.Image.init(testing.allocator, 2, 1, &.{
        255, 0, 0,   255,
        0,   0, 255, 255,
    });
    defer image.deinit();
    const data0 = [4]f32{ 1, 0, 0, 0 };
    const data1 = [4]f32{ 0, 1, 0, 0 }; // linear

    const clamp_left = samplePreparedImage(&image, data0, data1, .{ 0, 0, 0, 0 }, Vec2.new(0, 0.5)).color;
    const clamp_right = samplePreparedImage(&image, data0, data1, .{ 0, 0, 0, 0 }, Vec2.new(1, 0.5)).color;
    try testing.expectApproxEqAbs(@as(f32, 1), clamp_left[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), clamp_left[2], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), clamp_right[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), clamp_right[2], 1e-6);

    const repeat_seam = samplePreparedImage(&image, data0, data1, .{ 0, 0, 1, 0 }, Vec2.new(1, 0.5)).color;
    const reflect_seam = samplePreparedImage(&image, data0, data1, .{ 0, 0, 2, 0 }, Vec2.new(1, 0.5)).color;
    try testing.expectApproxEqAbs(@as(f32, 1), repeat_seam[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), repeat_seam[2], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), reflect_seam[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), reflect_seam[2], 1e-6);
}

test "linear image sampling matches hardware clamp at vertical edges" {
    var image = try snail.Image.init(testing.allocator, 1, 2, &.{
        255, 0,   0, 255,
        0,   255, 0, 255,
    });
    defer image.deinit();
    const data0 = [4]f32{ 1, 0, 0, 0 };
    const data1 = [4]f32{ 0, 1, 0, 0 };

    const top = samplePreparedImage(&image, data0, data1, .{ 0, 0, 0, 0 }, Vec2.new(0.5, 0)).color;
    const bottom = samplePreparedImage(&image, data0, data1, .{ 0, 0, 0, 0 }, Vec2.new(0.5, 1)).color;
    try testing.expectApproxEqAbs(@as(f32, 1), top[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), top[1], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0), bottom[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1), bottom[1], 1e-6);
}

test "image sampling is total for overflowed coordinates and wide extents" {
    try testing.expectEqual(@as(f32, 1), wrapPaintT(std.math.inf(f32), .clamp));
    try testing.expectEqual(@as(f32, 0), wrapPaintT(-std.math.inf(f32), .clamp));
    try testing.expectEqual(@as(f32, 0), wrapPaintT(std.math.nan(f32), .repeat));
    try testing.expectEqual(std.math.maxInt(u32) - 1, nearestTexelIndex(1.0, std.math.maxInt(u32)));
    try testing.expect(nearestTexelIndex(0.99999994, std.math.maxInt(u32)) < std.math.maxInt(u32));

    var image = try snail.Image.init(testing.allocator, 1, 1, &.{ 255, 0, 0, 255 });
    defer image.deinit();
    const sample = samplePreparedImage(
        &image,
        .{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32), 0 },
        .{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32), 0 },
        .{ 0, 0, 1, 2 },
        .{ .x = std.math.floatMax(f32), .y = -std.math.floatMax(f32) },
    );
    try testing.expectEqual([4]f32{ 1, 0, 0, 1 }, sample.color);

    const malformed = snail.Image{
        .allocator = testing.allocator,
        .width = 1,
        .height = 1,
        .texels = &.{255},
    };
    const fallback = samplePreparedImage(
        &malformed,
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ .x = 0, .y = 0 },
    );
    try testing.expectEqual([4]f32{ 0, 0, 0, 0 }, fallback.color);
}
