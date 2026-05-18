const build_options = @import("build_options");
const snail = @import("../root.zig");
const c = @import("types.zig");

const SnailBBox = c.SnailBBox;
const SnailDecorationMetrics = c.SnailDecorationMetrics;
const SnailDrawPass = c.SnailDrawPass;
const SnailDrawState = c.SnailDrawState;
const SnailFillStyle = c.SnailFillStyle;
const SnailFontStyle = c.SnailFontStyle;
const SnailCoverageDrawState = c.SnailCoverageDrawState;
const SnailGlTextCoverageProgram = c.SnailGlTextCoverageProgram;
const SnailMat4 = c.SnailMat4;
const SnailOverride = c.SnailOverride;
const SnailPaint = c.SnailPaint;
const SnailRange = c.SnailRange;
const SnailRect = c.SnailRect;
const SnailResourceCacheStats = c.SnailResourceCacheStats;
const SnailResourceFootprint = c.SnailResourceFootprint;
const SnailResourceStamp = c.SnailResourceStamp;
const SnailTextResourceKeys = c.SnailTextResourceKeys;
const SnailRasterOptions = c.SnailRasterOptions;
const SnailLinearResolve = c.SnailLinearResolve;
const SnailPixelRect = c.SnailPixelRect;
const SnailTargetSurface = c.SnailTargetSurface;
const SnailScriptMetrics = c.SnailScriptMetrics;
const SnailScriptTransform = c.SnailScriptTransform;
const SnailShapeMark = c.SnailShapeMark;
const SnailString = c.SnailString;
const SnailStrokeStyle = c.SnailStrokeStyle;
const SnailSyntheticStyle = c.SnailSyntheticStyle;
const SnailTextPlacement = c.SnailTextPlacement;
const SnailTransform2D = c.SnailTransform2D;
const SnailVulkanTextCoverageProgram = c.SnailVulkanTextCoverageProgram;
const SNAIL_PAINT_IMAGE = c.SNAIL_PAINT_IMAGE;
const SNAIL_PAINT_LINEAR = c.SNAIL_PAINT_LINEAR;
const SNAIL_PAINT_RADIAL = c.SNAIL_PAINT_RADIAL;
const SNAIL_PAINT_SOLID = c.SNAIL_PAINT_SOLID;
const SNAIL_RESOURCE_CAPACITY_EXACT = c.SNAIL_RESOURCE_CAPACITY_EXACT;
const SNAIL_RESOURCE_CAPACITY_GROWABLE = c.SNAIL_RESOURCE_CAPACITY_GROWABLE;

pub fn wrapBBox(bbox: snail.BBox) SnailBBox {
    return .{ .min_x = bbox.min.x, .min_y = bbox.min.y, .max_x = bbox.max.x, .max_y = bbox.max.y };
}

pub fn wrapString(s: []const u8) SnailString {
    return .{ .data = s.ptr, .len = s.len };
}

pub fn wrapDecorationMetrics(metrics: snail.DecorationMetrics) SnailDecorationMetrics {
    return .{
        .underline_position = metrics.underline_position,
        .underline_thickness = metrics.underline_thickness,
        .strikethrough_position = metrics.strikethrough_position,
        .strikethrough_thickness = metrics.strikethrough_thickness,
    };
}

pub fn wrapScriptMetrics(metrics: snail.ScriptMetrics) SnailScriptMetrics {
    return .{
        .x_size = metrics.x_size,
        .y_size = metrics.y_size,
        .x_offset = metrics.x_offset,
        .y_offset = metrics.y_offset,
    };
}

pub fn wrapScriptTransform(transform: snail.ScriptTransform) SnailScriptTransform {
    return .{
        .x = transform.x,
        .y = transform.y,
        .font_size = transform.font_size,
    };
}

pub fn wrapResourceStamp(stamp: snail.ResourceStamp) SnailResourceStamp {
    return .{
        .identity = stamp.identity,
        .layout = stamp.layout,
        .content = stamp.content,
    };
}

pub fn wrapTextResourceKeys(keys: snail.ResourceManifest.TextBlobResourceKeys) SnailTextResourceKeys {
    return .{
        .atlas_key = keys.atlas.id,
        .paint_key = if (keys.paint) |paint| paint.id else 0,
        .has_paint_key = keys.paint != null,
    };
}

pub fn toTextResourceKeys(keys: SnailTextResourceKeys) snail.TextResourceKeys {
    return .{
        .atlas = snail.ResourceKey.fromId(keys.atlas_key),
        .paint = if (keys.has_paint_key) snail.ResourceKey.fromId(keys.paint_key) else null,
    };
}

pub fn toRect(r: SnailRect) snail.Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

pub fn toSnailRect(r: snail.Rect) SnailRect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

pub fn toMat4(m: SnailMat4) snail.Mat4 {
    return .{ .data = m.data };
}

pub fn fromMat4(m: snail.Mat4) SnailMat4 {
    return .{ .data = m.data };
}

pub fn toTransform(t: SnailTransform2D) snail.Transform2D {
    return .{ .xx = t.xx, .xy = t.xy, .tx = t.tx, .yx = t.yx, .yy = t.yy, .ty = t.ty };
}

pub fn toOverride(override_value: SnailOverride) snail.Override {
    return .{ .transform = toTransform(override_value.transform), .tint = override_value.tint };
}

pub fn fromCoverageDrawState(state: snail.coverage.DrawState) SnailCoverageDrawState {
    return .{
        .fill_rule = @intFromEnum(state.fill_rule),
        .subpixel_order = @intFromEnum(state.subpixel_order),
        .output_srgb = state.output_srgb,
        .coverage_exponent = state.coverage_transfer.exponent,
        .layer_base = state.layer_base,
    };
}

pub fn toCoverageDrawState(state: SnailCoverageDrawState) !snail.coverage.DrawState {
    return .{
        .fill_rule = try toFillRule(state.fill_rule),
        .subpixel_order = try toSubpixelOrder(state.subpixel_order),
        .output_srgb = state.output_srgb,
        .coverage_transfer = .{ .exponent = state.coverage_exponent },
        .layer_base = state.layer_base,
    };
}

pub fn toGlCoverageProgram(program: SnailGlTextCoverageProgram) !snail.coverage.GlProgram {
    if (comptime build_options.enable_opengl) {
        return .{
            .curve_tex_loc = program.curve_tex_loc,
            .band_tex_loc = program.band_tex_loc,
            .layer_tex_loc = program.layer_tex_loc,
            .image_tex_loc = program.image_tex_loc,
            .fill_rule_loc = program.fill_rule_loc,
            .subpixel_order_loc = program.subpixel_order_loc,
            .output_srgb_loc = program.output_srgb_loc,
            .coverage_exponent_loc = program.coverage_exponent_loc,
            .layer_base_loc = program.layer_base_loc,
            .curve_tex_unit = program.curve_tex_unit,
            .band_tex_unit = program.band_tex_unit,
            .layer_tex_unit = program.layer_tex_unit,
            .image_tex_unit = program.image_tex_unit,
        };
    } else {
        return .{};
    }
}

pub fn toVulkanCoverageProgram(program: SnailVulkanTextCoverageProgram) snail.coverage.VulkanProgram {
    if (comptime build_options.enable_vulkan) {
        return .{
            .pipeline_layout = program.pipeline_layout,
            .descriptor_set_index = program.descriptor_set_index,
        };
    } else {
        return .{};
    }
}

pub fn fromResourceFootprint(footprint: snail.ResourceFootprint) SnailResourceFootprint {
    return .{
        .curve_bytes_used = footprint.curve_bytes_used,
        .curve_bytes_allocated = footprint.curve_bytes_allocated,
        .band_bytes_used = footprint.band_bytes_used,
        .band_bytes_allocated = footprint.band_bytes_allocated,
        .layer_info_bytes_used = footprint.layer_info_bytes_used,
        .layer_info_bytes_allocated = footprint.layer_info_bytes_allocated,
        .image_bytes_used = footprint.image_bytes_used,
        .image_bytes_allocated = footprint.image_bytes_allocated,
    };
}

pub fn fromResourceCacheStats(stats: snail.ResourceCacheStats) SnailResourceCacheStats {
    return .{
        .generation = stats.generation,
        .active_atlas_pages_resident = stats.active_atlas_pages_resident,
        .active_atlas_layers_allocated = stats.active_atlas_layers_allocated,
        .atlas_pages_resident = stats.atlas_pages_resident,
        .atlas_layers_allocated = stats.atlas_layers_allocated,
        .active_image_layers_resident = stats.active_image_layers_resident,
        .active_image_layers_allocated = stats.active_image_layers_allocated,
        .image_layers_resident = stats.image_layers_resident,
        .image_layers_allocated = stats.image_layers_allocated,
    };
}

pub fn toResourceCapacityMode(value: c_int) !snail.ResourceCapacityMode {
    return switch (value) {
        SNAIL_RESOURCE_CAPACITY_GROWABLE => .growable,
        SNAIL_RESOURCE_CAPACITY_EXACT => .exact,
        else => error.InvalidEnum,
    };
}

pub fn reservedResourceCapacityMode(reserved_pages: u32) snail.ResourceCapacityMode {
    return .{ .reserve_pages = reserved_pages };
}

pub fn toRange(range: SnailRange) snail.Range {
    return .{ .start = range.start, .count = range.count };
}

pub fn fromRange(range: snail.Range) SnailRange {
    return .{ .start = range.start, .count = range.count };
}

pub fn toShapeMark(mark: SnailShapeMark) snail.PathPictureBuilder.ShapeMark {
    return .{ .shape_count = mark.shape_count };
}

pub fn fromShapeMark(mark: snail.PathPictureBuilder.ShapeMark) SnailShapeMark {
    return .{ .shape_count = mark.shape_count };
}

pub fn toSyntheticStyle(s: SnailSyntheticStyle) snail.SyntheticStyle {
    return .{ .embolden = s.embolden, .skew_x = s.skew_x };
}

pub fn toFontWeight(v: c_int) !snail.FontWeight {
    return switch (v) {
        1 => .thin,
        2 => .extra_light,
        3 => .light,
        4 => .regular,
        5 => .medium,
        6 => .semi_bold,
        7 => .bold,
        8 => .extra_bold,
        9 => .black,
        else => error.InvalidEnum,
    };
}

pub fn toFontStyle(style: SnailFontStyle) !snail.FontStyle {
    return .{ .weight = try toFontWeight(style.weight), .italic = style.italic };
}

pub fn toPaintExtend(v: c_int) !snail.PaintExtend {
    return switch (v) {
        0 => .clamp,
        1 => .repeat,
        2 => .reflect,
        else => error.InvalidEnum,
    };
}

pub fn toImageFilter(v: c_int) !snail.ImageFilter {
    return switch (v) {
        0 => .linear,
        1 => .nearest,
        else => error.InvalidEnum,
    };
}

pub fn toStrokeCap(v: c_int) !snail.StrokeCap {
    return switch (v) {
        0 => .butt,
        1 => .square,
        2 => .round,
        else => error.InvalidEnum,
    };
}

pub fn toStrokeJoin(v: c_int) !snail.StrokeJoin {
    return switch (v) {
        0 => .miter,
        1 => .bevel,
        2 => .round,
        else => error.InvalidEnum,
    };
}

pub fn toStrokePlacement(v: c_int) !snail.StrokePlacement {
    return switch (v) {
        0 => .center,
        1 => .inside,
        else => error.InvalidEnum,
    };
}

pub fn toSubpixelOrder(v: c_int) !snail.SubpixelOrder {
    return switch (v) {
        0 => .none,
        1 => .rgb,
        2 => .bgr,
        3 => .vrgb,
        4 => .vbgr,
        else => error.InvalidEnum,
    };
}

pub fn toFillRule(v: c_int) !snail.FillRule {
    return switch (v) {
        0 => .non_zero,
        1 => .even_odd,
        else => error.InvalidEnum,
    };
}

pub fn toDecoration(v: c_int) !snail.Decoration {
    return switch (v) {
        0 => .underline,
        1 => .strikethrough,
        else => error.InvalidEnum,
    };
}

pub fn toColorEncoding(v: c_int) !snail.ColorEncoding {
    return switch (v) {
        0 => .linear,
        1 => .srgb,
        else => error.InvalidEnum,
    };
}

pub fn toResolveBackdrop(kind: c_int, clear_color: [4]f32) !snail.ResolveBackdrop {
    return switch (kind) {
        0 => .target,
        1 => .{ .clear = clear_color },
        2 => .transparent,
        3 => .dont_care,
        else => error.InvalidEnum,
    };
}

pub fn toPixelRect(rect: SnailPixelRect) snail.PixelRect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
}

pub fn toResolveRegion(kind: c_int, rect: SnailPixelRect) !snail.ResolveRegion {
    return switch (kind) {
        0 => .full_target,
        1 => .{ .pixel_rect = toPixelRect(rect) },
        else => error.InvalidEnum,
    };
}

pub fn toIntermediateFormat(v: c_int) !snail.IntermediateFormat {
    return switch (v) {
        0 => .rgba16f,
        1 => .rgba32f,
        else => error.InvalidEnum,
    };
}

pub fn toLinearResolve(resolve: SnailLinearResolve) !snail.LinearResolve {
    return .{
        .backdrop = try toResolveBackdrop(resolve.backdrop_kind, resolve.clear_color),
        .region = try toResolveRegion(resolve.region_kind, resolve.region_rect),
        .intermediate_format = try toIntermediateFormat(resolve.intermediate_format),
    };
}

pub fn toTargetSurface(surface: SnailTargetSurface) !snail.TargetSurface {
    return .{
        .pixel_width = surface.pixel_width,
        .pixel_height = surface.pixel_height,
        .encoding = .{
            .attachment = try toColorEncoding(surface.attachment_encoding),
            .stored_pixels = try toColorEncoding(surface.stored_pixel_encoding),
        },
    };
}

pub fn toRasterOptions(raster: SnailRasterOptions) !snail.RasterOptions {
    return .{
        .subpixel_order = try toSubpixelOrder(raster.subpixel_order),
        .fill_rule = try toFillRule(raster.fill_rule),
        .coverage_transfer = .{ .exponent = raster.coverage_exponent },
    };
}

pub fn toDrawState(state: SnailDrawState) !snail.DrawState {
    return .{
        .mvp = toMat4(state.mvp),
        .surface = try toTargetSurface(state.surface),
        .raster = try toRasterOptions(state.raster),
    };
}

pub fn toDrawPass(pass: SnailDrawPass) !snail.DrawPass {
    return .{
        .state = try toDrawState(pass.state),
        .resolve = switch (pass.resolve_kind) {
            0 => .direct,
            1 => .{ .linear = try toLinearResolve(pass.linear_resolve) },
            else => return error.InvalidEnum,
        },
    };
}

pub fn toTextPlacement(placement: SnailTextPlacement) snail.TextPlacement {
    return .{
        .baseline = .{ .x = placement.baseline_x, .y = placement.baseline_y },
        .em = placement.em,
    };
}

pub fn toPaint(paint: SnailPaint) !snail.Paint {
    return switch (paint.kind) {
        SNAIL_PAINT_SOLID => .{ .solid = paint.paint_solid },
        SNAIL_PAINT_LINEAR => .{ .linear_gradient = .{
            .start = .{ .x = paint.paint_linear.start_x, .y = paint.paint_linear.start_y },
            .end = .{ .x = paint.paint_linear.end_x, .y = paint.paint_linear.end_y },
            .start_color = paint.paint_linear.start_color,
            .end_color = paint.paint_linear.end_color,
            .extend = try toPaintExtend(paint.paint_linear.extend),
        } },
        SNAIL_PAINT_RADIAL => .{ .radial_gradient = .{
            .center = .{ .x = paint.paint_radial.center_x, .y = paint.paint_radial.center_y },
            .radius = paint.paint_radial.radius,
            .inner_color = paint.paint_radial.inner_color,
            .outer_color = paint.paint_radial.outer_color,
            .extend = try toPaintExtend(paint.paint_radial.extend),
        } },
        SNAIL_PAINT_IMAGE => blk: {
            const image = paint.paint_image;
            const img = image.image orelse return error.InvalidArgument;
            break :blk .{ .image = .{
                .image = &img.inner,
                .uv_transform = toTransform(image.uv_transform),
                .tint = image.tint,
                .extend_x = try toPaintExtend(image.extend_x),
                .extend_y = try toPaintExtend(image.extend_y),
                .filter = try toImageFilter(image.filter),
            } };
        },
        else => error.InvalidEnum,
    };
}

pub fn toFillStyle(s: SnailFillStyle) !snail.FillStyle {
    return .{
        .paint = try toPaint(s.paint),
    };
}

pub fn toStrokeStyle(s: SnailStrokeStyle) !snail.StrokeStyle {
    return .{
        .paint = try toPaint(s.paint),
        .width = s.width,
        .cap = try toStrokeCap(s.cap),
        .join = try toStrokeJoin(s.join),
        .miter_limit = s.miter_limit,
        .placement = try toStrokePlacement(s.placement),
    };
}

pub fn toOptFill(ptr: ?*const SnailFillStyle) !?snail.FillStyle {
    if (ptr) |s| return try toFillStyle(s.*);
    return null;
}

pub fn toOptStroke(ptr: ?*const SnailStrokeStyle) !?snail.StrokeStyle {
    if (ptr) |s| return try toStrokeStyle(s.*);
    return null;
}
