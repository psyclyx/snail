const std = @import("std");
const snail = @import("../../../root.zig");
const color = @import("color.zig");
const atlas_curve_mod = @import("../atlas/curve.zig");

const CurveAtlas = atlas_curve_mod.CurveAtlas;
const PaintImageRecord = CurveAtlas.PaintImageRecord;
const GlyphBandEntry = std.meta.fieldInfo(CurveAtlas.GlyphInfo, .band_entry).type;
const Vec2 = snail.Vec2;
const clamp01 = color.clamp01;
const linearColorToSrgb = color.linearColorToSrgb;
const srgbColorToLinear = color.srgbColorToLinear;
const srgbToLinear = color.srgbToLinear;

pub const PreparedPathLayer = struct {
    band_entry: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    paint: PreparedPathPaint,
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
    /// Source atlas's image-paint records, borrowed. Used by the prepared
    /// sampler to resolve tag-4 (image) paints — the atlas-side patching
    /// done by the GPU upload (`pipeline.zig` / `vulkan_pipeline.zig`)
    /// doesn't happen on the CPU, so we look up the `*const snail.Image`
    /// via this slice instead.
    paint_image_records: ?[]const ?PaintImageRecord = null,

    pub fn deinit(self: *LayerInfoEntry, allocator: std.mem.Allocator) void {
        if (self.path_records.len > 0) allocator.free(self.path_records);
        if (self.path_layers.len > 0) allocator.free(self.path_layers);
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

pub fn fetchLayerInfoTexel(data: []const f32, width: u32, info_x: u16, info_y: u16, offset: u32) [4]f32 {
    const texel = @as(u32, info_x) + offset;
    const x = texel % width;
    const y = @as(u32, info_y) + texel / width;
    const base = (y * width + x) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

pub fn fetchLayerInfoTexelOffset(data: []const f32, texel_offset: u32) [4]f32 {
    const base = @as(usize, texel_offset) * 4;
    return .{ data[base + 0], data[base + 1], data[base + 2], data[base + 3] };
}

pub fn pathInfoTag(info: [4]f32) i32 {
    return @intFromFloat(@round(-info[3]));
}

pub const PreparedPathLayerInfo = struct {
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

pub fn preparePathLayerInfoRecords(
    allocator: std.mem.Allocator,
    data: []const f32,
    width: u32,
    height: u32,
    paint_image_records: ?[]const ?PaintImageRecord,
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
    paint_image_records: ?[]const ?PaintImageRecord,
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
    paint_image_records: ?[]const ?PaintImageRecord,
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
    records: []const ?PaintImageRecord,
    abs_texel: u32,
) ?PaintImageRecord {
    for (records) |maybe_record| {
        const record = maybe_record orelse continue;
        if (record.texel_offset == abs_texel) return record;
    }
    return null;
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
        image,
    };

    kind: Kind = .invalid,
    color0: [4]f32 = .{ 1, 0, 1, 1 },
    color1: [4]f32 = .{ 1, 0, 1, 1 },
    data0: [4]f32 = .{ 0, 0, 0, 0 },
    data1: [4]f32 = .{ 0, 0, 0, 0 },
    extra: [4]f32 = .{ 0, 0, 0, 0 },
    image_record: ?PaintImageRecord = null,

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

pub fn samplePathPaint(atlas: *const CurveAtlas, shape: snail.PathPicture.Shape, glyph_id: u16, local: Vec2) PathPaintSample {
    return samplePathPaintAt(atlas, shape.info_x, shape.info_y, glyph_id, local);
}

pub fn samplePathPaintAt(atlas: *const CurveAtlas, info_x: u16, info_y: u16, glyph_id: u16, local: Vec2) PathPaintSample {
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

pub fn sampleImagePaint(
    atlas: *const CurveAtlas,
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

pub fn sampleImageWithRecord(
    record: PaintImageRecord,
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

pub fn samplePreparedImageWithRecord(
    record: PaintImageRecord,
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
