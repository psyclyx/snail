//! C API for snail's public Zig resource model.
//! All exported functions use opaque handles and explicit ownership.

const std = @import("std");
const snail = @import("root.zig");
const ttf = @import("font/ttf.zig");
const generated = @import("c_api/generated.zig");

const build_options = @import("build_options");
const vk = if (build_options.enable_vulkan) @import("renderer/vulkan.zig").vk else struct {
    pub const VkPhysicalDevice = ?*anyopaque;
    pub const VkDevice = ?*anyopaque;
    pub const VkQueue = ?*anyopaque;
    pub const VkRenderPass = usize;
    pub const VkFormat = c_int;
    pub const VkCommandBuffer = ?*anyopaque;
};

// Allocator bridge

pub const SnailAllocFn = *const fn (ctx: ?*anyopaque, size: usize, alignment: usize) callconv(.c) ?[*]u8;
pub const SnailFreeFn = *const fn (ctx: ?*anyopaque, ptr: ?[*]u8, size: usize) callconv(.c) void;

pub const SnailAllocator = extern struct {
    alloc_fn: SnailAllocFn,
    free_fn: SnailFreeFn,
    ctx: ?*anyopaque,
};

pub const SnailVulkanContext = extern struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    color_format: vk.VkFormat,
    supports_dual_source_blend: bool = false,
};

fn toZigAllocator(ca: *const SnailAllocator) std.mem.Allocator {
    const S = struct {
        fn alloc(ctx_ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            return ca_inner.alloc_fn(ca_inner.ctx, len, alignment.toByteUnits());
        }
        fn free(ctx_ptr: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            ca_inner.free_fn(ca_inner.ctx, buf.ptr, buf.len);
        }
        fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
            return false;
        }
        fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
            return null;
        }
    };
    return .{
        .ptr = @ptrCast(@constCast(ca)),
        .vtable = &.{ .alloc = S.alloc, .resize = S.resize, .remap = S.remap, .free = S.free },
    };
}

fn libcAlloc(_: ?*anyopaque, size: usize, _: usize) callconv(.c) ?[*]u8 {
    return @ptrCast(std.c.malloc(size) orelse return null);
}

fn libcFree(_: ?*anyopaque, ptr: ?[*]u8, _: usize) callconv(.c) void {
    if (ptr) |p| std.c.free(p);
}

const default_c_allocator = SnailAllocator{
    .alloc_fn = &libcAlloc,
    .free_fn = &libcFree,
    .ctx = null,
};

fn resolveAllocator(ca: ?*const SnailAllocator) std.mem.Allocator {
    if (ca) |a| return toZigAllocator(a);
    return toZigAllocator(&default_c_allocator);
}

fn handleAllocator() std.mem.Allocator {
    return std.heap.smp_allocator;
}

// Error codes

pub const SNAIL_OK = generated.SNAIL_OK;
pub const SNAIL_ERR_INVALID_FONT = generated.SNAIL_ERR_INVALID_FONT;
pub const SNAIL_ERR_OUT_OF_MEMORY = generated.SNAIL_ERR_OUT_OF_MEMORY;
pub const SNAIL_ERR_RENDERER_FAILED = generated.SNAIL_ERR_RENDERER_FAILED;
pub const SNAIL_ERR_INVALID_ARGUMENT = generated.SNAIL_ERR_INVALID_ARGUMENT;
pub const SNAIL_ERR_DRAW_FAILED = generated.SNAIL_ERR_DRAW_FAILED;

fn mapError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => SNAIL_ERR_OUT_OF_MEMORY,
        error.InvalidFont, error.NoFaces, error.MissingCellMetricsGlyph => SNAIL_ERR_INVALID_FONT,
        error.InvalidEnum, error.InvalidArgument, error.InvalidFaceIndex, error.WrongTextAtlasSnapshot, error.MissingPreparedGlyph, error.UnsupportedTextPaint, error.InvalidShapeMark, error.InvalidShapeRange => SNAIL_ERR_INVALID_ARGUMENT,
        else => SNAIL_ERR_DRAW_FAILED,
    };
}

// C-compatible value types

pub const SnailBBox = extern struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
};

pub const SnailGlyphMetrics = extern struct {
    advance_width: u16,
    lsb: i16,
    bbox: SnailBBox,
};

pub const SnailLineMetrics = extern struct {
    ascent: i16,
    descent: i16,
    line_gap: i16,
};

pub const SnailCellMetrics = extern struct {
    cell_width: f32,
    line_height: f32,
};

pub const SnailRect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const SnailMat4 = extern struct {
    data: [16]f32,
};

pub const SnailTransform2D = extern struct {
    xx: f32 = 1,
    xy: f32 = 0,
    tx: f32 = 0,
    yx: f32 = 0,
    yy: f32 = 1,
    ty: f32 = 0,
};

pub const SnailOverride = extern struct {
    transform: SnailTransform2D = .{},
    tint: [4]f32 = .{ 1, 1, 1, 1 },
};

pub const SnailRange = extern struct {
    start: usize = 0,
    count: usize = std.math.maxInt(usize),
};

pub const SnailShapeMark = extern struct {
    shape_count: usize = 0,
};

pub const SnailSyntheticStyle = extern struct {
    embolden: f32 = 0,
    skew_x: f32 = 0,
};

pub const SnailFaceSpec = extern struct {
    data: [*]const u8,
    len: usize,
    weight: c_int = 4,
    italic: bool = false,
    fallback: bool = false,
    synthetic: SnailSyntheticStyle = .{},
};

pub const SnailFontStyle = extern struct {
    weight: c_int = 4,
    italic: bool = false,
};

pub const SnailShapedGlyph = extern struct {
    face_index: u16,
    glyph_id: u16,
    x_offset: f32,
    y_offset: f32,
    x_advance: f32,
    y_advance: f32,
    source_start: u32,
    source_end: u32,
};

pub const SnailTextPlacement = extern struct {
    baseline_x: f32,
    baseline_y: f32,
    em: f32,
};

pub const SnailTextAppendOptions = extern struct {
    placement: SnailTextPlacement,
    fill: SnailPaint = .{},
};

pub const SnailResolveTarget = extern struct {
    pixel_width: f32,
    pixel_height: f32,
    subpixel_order: c_int = 0,
    fill_rule: c_int = 0,
    is_final_composite: bool = true,
    opaque_backdrop: bool = true,
    will_resample: bool = false,
    framebuffer_encoding: c_int = 0,
    pixel_encoding: c_int = 0,
    coverage_exponent: f32 = 1.0,
};

pub const SnailDrawOptions = extern struct {
    mvp: SnailMat4,
    target: SnailResolveTarget,
};

pub const SnailResourceKey = u64;

pub const SNAIL_RESOURCE_CAPACITY_GROWABLE: c_int = 0;
pub const SNAIL_RESOURCE_CAPACITY_EXACT: c_int = 1;

pub const SnailResourceFootprint = extern struct {
    curve_bytes_used: usize = 0,
    curve_bytes_allocated: usize = 0,
    band_bytes_used: usize = 0,
    band_bytes_allocated: usize = 0,
    layer_info_bytes_used: usize = 0,
    layer_info_bytes_allocated: usize = 0,
    image_bytes_used: usize = 0,
    image_bytes_allocated: usize = 0,
};

// Paint / style types

pub const SNAIL_PAINT_SOLID: c_int = 0;
pub const SNAIL_PAINT_LINEAR: c_int = 1;
pub const SNAIL_PAINT_RADIAL: c_int = 2;
pub const SNAIL_PAINT_IMAGE: c_int = 3;

pub const SnailLinearGradient = extern struct {
    start_x: f32,
    start_y: f32,
    end_x: f32,
    end_y: f32,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: c_int = 0,
};

pub const SnailRadialGradient = extern struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: c_int = 0,
};

pub const SnailImagePaint = extern struct {
    image: ?*const ImageImpl = null,
    uv_transform: SnailTransform2D = .{},
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    extend_x: c_int = 0,
    extend_y: c_int = 0,
    filter: c_int = 0,
};

pub const SnailPaint = extern struct {
    kind: c_int = SNAIL_PAINT_SOLID,
    paint_solid: [4]f32 = .{ 0, 0, 0, 0 },
    paint_linear: SnailLinearGradient = std.mem.zeroes(SnailLinearGradient),
    paint_radial: SnailRadialGradient = std.mem.zeroes(SnailRadialGradient),
    paint_image: SnailImagePaint = .{},
};

pub const SnailFillStyle = extern struct {
    paint: SnailPaint = .{},
};

pub const SnailStrokeStyle = extern struct {
    paint: SnailPaint = .{},
    width: f32 = 1,
    cap: c_int = 0,
    join: c_int = 0,
    miter_limit: f32 = 4,
    placement: c_int = 0,
};

// Opaque handle implementations

const FontImpl = struct { inner: ttf.Font };
const TextAtlasImpl = struct { inner: snail.TextAtlas, allocator: std.mem.Allocator };
const ShapedTextImpl = struct { inner: snail.ShapedText };
const TextBlobImpl = struct { inner: snail.TextBlob };
const ImageImpl = struct { inner: snail.Image };
const PathImpl = struct { inner: snail.Path };
const PathPictureBuilderImpl = struct { inner: snail.PathPictureBuilder };
const PathPictureImpl = struct { inner: snail.PathPicture };
const SceneImpl = struct {
    inner: snail.Scene,
    // C callers can't keep an `[]Override` slice alive across the boundary,
    // so the C entry points that take a transform stash a single-element
    // override here and hand `inner` a slice into this arena. Reset alongside
    // `inner` so capacity is reused frame-to-frame.
    overrides_arena: std.heap.ArenaAllocator,
};
const ResourceSetImpl = struct {
    inner: snail.ResourceSet,
    entries: []snail.ResourceSet.Entry,
    allocator: std.mem.Allocator,
};
const PreparedResourcesImpl = struct { inner: snail.PreparedResources };
const PreparedSceneImpl = struct { inner: snail.PreparedScene };
const RendererImpl = struct {
    backend: snail.BackendKind,
    gl: if (build_options.enable_opengl) ?snail.GlRenderer else void = if (build_options.enable_opengl) null else {},
    vulkan: if (build_options.enable_vulkan) ?snail.VulkanRenderer else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?snail.CpuRenderer else void = if (build_options.enable_cpu) null else {},

    fn asRenderer(self: *RendererImpl) snail.Renderer {
        return switch (self.backend) {
            .gl => blk: {
                if (comptime !build_options.enable_opengl) unreachable;
                if (self.gl) |*gl| break :blk gl.asRenderer();
                unreachable;
            },
            .vulkan => blk: {
                if (comptime !build_options.enable_vulkan) unreachable;
                if (self.vulkan) |*vk_renderer| break :blk vk_renderer.asRenderer();
                unreachable;
            },
            .cpu => blk: {
                if (comptime !build_options.enable_cpu) unreachable;
                if (self.cpu) |*cpu| break :blk cpu.asRenderer();
                unreachable;
            },
        };
    }

    fn deinit(self: *RendererImpl) void {
        switch (self.backend) {
            .gl => if (comptime build_options.enable_opengl) {
                if (self.gl) |*gl| gl.deinit();
            },
            .vulkan => if (comptime build_options.enable_vulkan) {
                if (self.vulkan) |*vk_renderer| vk_renderer.deinit();
            },
            .cpu => {},
        }
        self.* = undefined;
    }

    fn backendName(self: *const RendererImpl) []const u8 {
        return switch (self.backend) {
            .gl => if (comptime build_options.enable_opengl)
                self.gl.?.backendName()
            else
                "OpenGL (disabled)",
            .vulkan => if (comptime build_options.enable_vulkan)
                self.vulkan.?.backendName()
            else
                "vulkan (disabled)",
            .cpu => if (comptime build_options.enable_cpu)
                self.cpu.?.backendName()
            else
                "CPU (disabled)",
        };
    }
};

// Conversion helpers

fn wrapBBox(bbox: snail.BBox) SnailBBox {
    return .{ .min_x = bbox.min.x, .min_y = bbox.min.y, .max_x = bbox.max.x, .max_y = bbox.max.y };
}

fn toRect(r: SnailRect) snail.Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn toMat4(m: SnailMat4) snail.Mat4 {
    return .{ .data = m.data };
}

fn fromMat4(m: snail.Mat4) SnailMat4 {
    return .{ .data = m.data };
}

fn toTransform(t: SnailTransform2D) snail.Transform2D {
    return .{ .xx = t.xx, .xy = t.xy, .tx = t.tx, .yx = t.yx, .yy = t.yy, .ty = t.ty };
}

fn toOverride(override_value: SnailOverride) snail.Override {
    return .{ .transform = toTransform(override_value.transform), .tint = override_value.tint };
}

fn fromResourceFootprint(footprint: snail.ResourceFootprint) SnailResourceFootprint {
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

fn toResourceCapacityMode(value: c_int) !snail.ResourceCapacityMode {
    return switch (value) {
        SNAIL_RESOURCE_CAPACITY_GROWABLE => .growable,
        SNAIL_RESOURCE_CAPACITY_EXACT => .exact,
        else => error.InvalidEnum,
    };
}

export fn snail_resource_footprint_used_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_used +
        footprint.band_bytes_used +
        footprint.layer_info_bytes_used +
        footprint.image_bytes_used;
}

export fn snail_resource_footprint_allocated_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_allocated +
        footprint.band_bytes_allocated +
        footprint.layer_info_bytes_allocated +
        footprint.image_bytes_allocated;
}

fn toRange(range: SnailRange) snail.Range {
    return .{ .start = range.start, .count = range.count };
}

fn fromRange(range: snail.Range) SnailRange {
    return .{ .start = range.start, .count = range.count };
}

fn toShapeMark(mark: SnailShapeMark) snail.PathPictureBuilder.ShapeMark {
    return .{ .shape_count = mark.shape_count };
}

fn fromShapeMark(mark: snail.PathPictureBuilder.ShapeMark) SnailShapeMark {
    return .{ .shape_count = mark.shape_count };
}

fn toSyntheticStyle(s: SnailSyntheticStyle) snail.SyntheticStyle {
    return .{ .embolden = s.embolden, .skew_x = s.skew_x };
}

fn toFontWeight(v: c_int) !snail.FontWeight {
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

fn toFontStyle(style: SnailFontStyle) !snail.FontStyle {
    return .{ .weight = try toFontWeight(style.weight), .italic = style.italic };
}

fn toPaintExtend(v: c_int) !snail.PaintExtend {
    return switch (v) {
        0 => .clamp,
        1 => .repeat,
        2 => .reflect,
        else => error.InvalidEnum,
    };
}

fn toImageFilter(v: c_int) !snail.ImageFilter {
    return switch (v) {
        0 => .linear,
        1 => .nearest,
        else => error.InvalidEnum,
    };
}

fn toStrokeCap(v: c_int) !snail.StrokeCap {
    return switch (v) {
        0 => .butt,
        1 => .square,
        2 => .round,
        else => error.InvalidEnum,
    };
}

fn toStrokeJoin(v: c_int) !snail.StrokeJoin {
    return switch (v) {
        0 => .miter,
        1 => .bevel,
        2 => .round,
        else => error.InvalidEnum,
    };
}

fn toStrokePlacement(v: c_int) !snail.StrokePlacement {
    return switch (v) {
        0 => .center,
        1 => .inside,
        else => error.InvalidEnum,
    };
}

fn toSubpixelOrder(v: c_int) !snail.SubpixelOrder {
    return switch (v) {
        0 => .none,
        1 => .rgb,
        2 => .bgr,
        3 => .vrgb,
        4 => .vbgr,
        else => error.InvalidEnum,
    };
}

fn toFillRule(v: c_int) !snail.FillRule {
    return switch (v) {
        0 => .non_zero,
        1 => .even_odd,
        else => error.InvalidEnum,
    };
}

fn toColorEncoding(v: c_int) !snail.ColorEncoding {
    return switch (v) {
        0 => .linear,
        1 => .srgb,
        else => error.InvalidEnum,
    };
}

fn toResolveTarget(target: SnailResolveTarget) !snail.ResolveTarget {
    return .{
        .pixel_width = target.pixel_width,
        .pixel_height = target.pixel_height,
        .subpixel_order = try toSubpixelOrder(target.subpixel_order),
        .fill_rule = try toFillRule(target.fill_rule),
        .is_final_composite = target.is_final_composite,
        .opaque_backdrop = target.opaque_backdrop,
        .will_resample = target.will_resample,
        .encoding = .{
            .framebuffer = try toColorEncoding(target.framebuffer_encoding),
            .pixels = try toColorEncoding(target.pixel_encoding),
        },
        .coverage_transfer = .{ .exponent = target.coverage_exponent },
    };
}

fn toDrawOptions(options: SnailDrawOptions) !snail.DrawOptions {
    return .{ .mvp = toMat4(options.mvp), .target = try toResolveTarget(options.target) };
}

fn toTextPlacement(placement: SnailTextPlacement) snail.TextPlacement {
    return .{
        .baseline = .{ .x = placement.baseline_x, .y = placement.baseline_y },
        .em = placement.em,
    };
}

fn toPaint(paint: SnailPaint) !snail.Paint {
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

fn toFillStyle(s: SnailFillStyle) !snail.FillStyle {
    return .{
        .paint = try toPaint(s.paint),
    };
}

fn toStrokeStyle(s: SnailStrokeStyle) !snail.StrokeStyle {
    return .{
        .paint = try toPaint(s.paint),
        .width = s.width,
        .cap = try toStrokeCap(s.cap),
        .join = try toStrokeJoin(s.join),
        .miter_limit = s.miter_limit,
        .placement = try toStrokePlacement(s.placement),
    };
}

fn toOptFill(ptr: ?*const SnailFillStyle) !?snail.FillStyle {
    if (ptr) |s| return try toFillStyle(s.*);
    return null;
}

fn toOptStroke(ptr: ?*const SnailStrokeStyle) !?snail.StrokeStyle {
    if (ptr) |s| return try toStrokeStyle(s.*);
    return null;
}

fn destroyHandle(ptr: anytype) void {
    handleAllocator().destroy(ptr);
}

// Font metrics helper

export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const font = ttf.Font.init(data[0..len]) catch return SNAIL_ERR_INVALID_FONT;
    const impl = handleAllocator().create(FontImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = font };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_font_deinit(font: ?*FontImpl) void {
    if (font) |f| destroyHandle(f);
}

export fn snail_font_units_per_em(font: *const FontImpl) u16 {
    return font.inner.units_per_em;
}

export fn snail_font_glyph_index(font: *const FontImpl, codepoint: u32) u16 {
    return font.inner.glyphIndex(codepoint) catch 0;
}

export fn snail_font_get_kerning(font: *const FontImpl, left: u16, right: u16) i16 {
    return font.inner.getKerning(left, right) catch 0;
}

export fn snail_font_glyph_metrics(font: *const FontImpl, glyph_id: u16, out: *SnailGlyphMetrics) c_int {
    const m = font.inner.glyphMetrics(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .advance_width = m.advance_width, .lsb = m.lsb, .bbox = wrapBBox(m.bbox) };
    return SNAIL_OK;
}

export fn snail_font_line_metrics(font: *const FontImpl, out: *SnailLineMetrics) c_int {
    const m = font.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_font_advance_width(font: *const FontImpl, glyph_id: u16, out: *i16) c_int {
    out.* = font.inner.advanceWidth(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

export fn snail_font_bbox(font: *const FontImpl, glyph_id: u16, out: *SnailBBox) c_int {
    out.* = wrapBBox(font.inner.bbox(glyph_id) catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

// TextAtlas and shaping

export fn snail_text_atlas_init(
    alloc_ptr: ?*const SnailAllocator,
    specs: [*]const SnailFaceSpec,
    spec_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (spec_count == 0) return SNAIL_ERR_INVALID_ARGUMENT;
    const allocator = resolveAllocator(alloc_ptr);
    const zig_specs = allocator.alloc(snail.FaceSpec, spec_count) catch return SNAIL_ERR_OUT_OF_MEMORY;
    defer allocator.free(zig_specs);

    for (specs[0..spec_count], 0..) |spec, i| {
        zig_specs[i] = .{
            .data = spec.data[0..spec.len],
            .weight = toFontWeight(spec.weight) catch return SNAIL_ERR_INVALID_ARGUMENT,
            .italic = spec.italic,
            .fallback = spec.fallback,
            .synthetic = toSyntheticStyle(spec.synthetic),
        };
    }

    const atlas = snail.TextAtlas.init(allocator, zig_specs) catch |err| return mapError(err);
    const impl = handleAllocator().create(TextAtlasImpl) catch {
        var doomed = atlas;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = atlas, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_atlas_deinit(atlas: ?*TextAtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        destroyHandle(a);
    }
}

export fn snail_text_atlas_page_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.pageCount();
}

export fn snail_text_atlas_upload_footprint(atlas: *const TextAtlasImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(atlas.inner.uploadFootprint());
}

export fn snail_text_atlas_texture_byte_len(atlas: *const TextAtlasImpl) usize {
    var total: usize = 0;
    for (atlas.inner.pageSlice()) |page| total += page.textureBytes();
    if (atlas.inner.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

export fn snail_text_atlas_units_per_em(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.unitsPerEm() catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

export fn snail_text_atlas_line_metrics(atlas: *const TextAtlasImpl, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_text_atlas_face_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.faceCount();
}

export fn snail_text_atlas_primary_face_index(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.primaryFaceIndex() catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_face_units_per_em(atlas: *const TextAtlasImpl, face_index: usize, out: *u16) c_int {
    out.* = atlas.inner.faceUnitsPerEm(face_index) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_face_line_metrics(atlas: *const TextAtlasImpl, face_index: usize, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.faceLineMetrics(face_index) catch |err| return mapError(err);
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_text_atlas_glyph_index(atlas: *const TextAtlasImpl, face_index: usize, codepoint: u32, out: *u16) c_int {
    const cp = std.math.cast(u21, codepoint) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    out.* = (atlas.inner.glyphIndex(face_index, cp) catch |err| return mapError(err)) orelse 0;
    return SNAIL_OK;
}

export fn snail_text_atlas_advance_width(atlas: *const TextAtlasImpl, face_index: usize, glyph_id: u16, out: *i16) c_int {
    out.* = atlas.inner.advanceWidth(face_index, glyph_id) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_cell_metrics(atlas: *const TextAtlasImpl, style: SnailFontStyle, em: f32, out: *SnailCellMetrics) c_int {
    const metrics = atlas.inner.cellMetrics(.{
        .style = toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT,
        .em = em,
    }) catch |err| return mapError(err);
    out.* = .{ .cell_width = metrics.cell_width, .line_height = metrics.line_height };
    return SNAIL_OK;
}

export fn snail_text_atlas_shape_utf8(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*ShapedTextImpl,
) c_int {
    const shaped = atlas.inner.shapeText(atlas.allocator, toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    const impl = handleAllocator().create(ShapedTextImpl) catch {
        var doomed = shaped;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = shaped };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_atlas_ensure_text(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*TextAtlasImpl,
) c_int {
    const next = atlas.inner.ensureText(toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = handleAllocator().create(TextAtlasImpl) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .inner = new_atlas, .allocator = atlas.allocator };
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

export fn snail_text_atlas_ensure_shaped(atlas: *const TextAtlasImpl, shaped: *const ShapedTextImpl, out: *?*TextAtlasImpl) c_int {
    const next = atlas.inner.ensureShaped(&shaped.inner) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = handleAllocator().create(TextAtlasImpl) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .inner = new_atlas, .allocator = atlas.allocator };
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

export fn snail_text_atlas_ensure_glyphs(
    atlas: *const TextAtlasImpl,
    face_index: usize,
    glyph_ids: ?[*]const u16,
    glyph_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (glyph_count > 0 and glyph_ids == null) return SNAIL_ERR_INVALID_ARGUMENT;
    const gids = if (glyph_count == 0) &.{} else glyph_ids.?[0..glyph_count];
    const next = atlas.inner.ensureGlyphs(face_index, gids) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = handleAllocator().create(TextAtlasImpl) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .inner = new_atlas, .allocator = atlas.allocator };
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

export fn snail_shaped_text_deinit(shaped: ?*ShapedTextImpl) void {
    if (shaped) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

export fn snail_shaped_text_glyph_count(shaped: *const ShapedTextImpl) usize {
    return shaped.inner.glyphs.len;
}

export fn snail_shaped_text_advance_x(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_x;
}

export fn snail_shaped_text_advance_y(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_y;
}

export fn snail_shaped_text_glyph(shaped: *const ShapedTextImpl, index: usize, out: *SnailShapedGlyph) bool {
    if (index >= shaped.inner.glyphs.len) return false;
    const g = shaped.inner.glyphs[index];
    out.* = .{
        .face_index = g.face_index,
        .glyph_id = g.glyph_id,
        .x_offset = g.x_offset,
        .y_offset = g.y_offset,
        .x_advance = g.x_advance,
        .y_advance = g.y_advance,
        .source_start = g.source_start,
        .source_end = g.source_end,
    };
    return true;
}

export fn snail_shaped_text_copy_glyphs(shaped: *const ShapedTextImpl, out: [*]SnailShapedGlyph, capacity: usize) usize {
    const count = @min(shaped.inner.glyphs.len, capacity);
    for (shaped.inner.glyphs[0..count], 0..) |g, i| {
        out[i] = .{
            .face_index = g.face_index,
            .glyph_id = g.glyph_id,
            .x_offset = g.x_offset,
            .y_offset = g.y_offset,
            .x_advance = g.x_advance,
            .y_advance = g.y_advance,
            .source_start = g.source_start,
            .source_end = g.source_end,
        };
    }
    return count;
}

export fn snail_text_blob_init_from_shaped(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    shaped: *const ShapedTextImpl,
    options: SnailTextAppendOptions,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const blob = snail.TextBlob.init(allocator, &atlas.inner, .{
        .shaped = &shaped.inner,
        .placement = toTextPlacement(options.placement),
        .fill = toPaint(options.fill) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch |err| return mapError(err);
    const impl = handleAllocator().create(TextBlobImpl) catch {
        var doomed = blob;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = blob };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_blob_init_text(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    options: SnailTextAppendOptions,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var shaped = atlas.inner.shapeText(allocator, toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    defer shaped.deinit();
    return snail_text_blob_init_from_shaped(alloc_ptr, atlas, &.{ .inner = shaped }, options, out);
}

export fn snail_text_blob_deinit(blob: ?*TextBlobImpl) void {
    if (blob) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

export fn snail_text_blob_glyph_count(blob: *const TextBlobImpl) usize {
    return blob.inner.glyphCount();
}

export fn snail_text_blob_rebind(blob: *TextBlobImpl, atlas: *const TextAtlasImpl) c_int {
    const rebound = blob.inner.rebound(blob.inner.allocator, &atlas.inner) catch |err| return mapError(err);
    blob.inner.deinit();
    blob.inner = rebound;
    return SNAIL_OK;
}

// Image

export fn snail_image_init_srgba8(
    alloc_ptr: ?*const SnailAllocator,
    width: u32,
    height: u32,
    pixels: [*]const u8,
    out: *?*ImageImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const img = snail.Image.initSrgba8(allocator, width, height, pixels[0 .. width * height * 4]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = handleAllocator().create(ImageImpl) catch {
        var doomed = img;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = img };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_image_deinit(image: ?*ImageImpl) void {
    if (image) |img| {
        img.inner.deinit();
        destroyHandle(img);
    }
}

export fn snail_image_width(image: *const ImageImpl) u32 {
    return image.inner.width;
}

export fn snail_image_height(image: *const ImageImpl) u32 {
    return image.inner.height;
}

export fn snail_image_upload_footprint(image: *const ImageImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(image.inner.uploadFootprint());
}

// Paths and path pictures

export fn snail_path_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.Path.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_deinit(path: ?*PathImpl) void {
    if (path) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_path_reset(path: *PathImpl) void {
    path.inner.reset();
}

export fn snail_path_is_empty(path: *const PathImpl) bool {
    return path.inner.isEmpty();
}

export fn snail_path_bounds(path: *const PathImpl, out: *SnailBBox) bool {
    if (path.inner.bounds()) |b| {
        out.* = wrapBBox(b);
        return true;
    }
    return false;
}

export fn snail_path_move_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.moveTo(.{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_line_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.lineTo(.{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_quad_to(path: *PathImpl, cx: f32, cy: f32, x: f32, y: f32) c_int {
    path.inner.quadTo(.{ .x = cx, .y = cy }, .{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_cubic_to(path: *PathImpl, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) c_int {
    path.inner.cubicTo(.{ .x = c1x, .y = c1y }, .{ .x = c2x, .y = c2y }, .{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_close(path: *PathImpl) c_int {
    path.inner.close() catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_rect(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRect(toRect(rect)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_rounded_rect(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRect(toRect(rect), corner_radius) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_ellipse(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipse(toRect(rect)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureBuilderImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathPictureBuilderImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.PathPictureBuilder.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_deinit(builder: ?*PathPictureBuilderImpl) void {
    if (builder) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

export fn snail_path_picture_builder_add_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: ?*const SnailFillStyle,
    stroke: ?*const SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addPath(&path.inner, toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_filled_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: SnailFillStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addFilledPath(&path.inner, toFillStyle(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_stroked_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    stroke: SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addStrokedPath(&path.inner, toStrokeStyle(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rounded_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, corner_radius: f32, transform: SnailTransform2D) c_int {
    builder.inner.addRoundedRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, corner_radius, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_ellipse(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addEllipse(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_freeze(builder: *const PathPictureBuilderImpl, alloc_ptr: ?*const SnailAllocator, scratch_alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const scratch_allocator = resolveAllocator(scratch_alloc_ptr);
    var picture = builder.inner.freeze(.{
        .persistent_allocator = allocator,
        .scratch_allocator = scratch_allocator,
    }) catch |err| return mapError(err);
    const impl = handleAllocator().create(PathPictureImpl) catch {
        picture.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = picture };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_picture_deinit(picture: ?*PathPictureImpl) void {
    if (picture) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_path_picture_shape_count(picture: *const PathPictureImpl) usize {
    return picture.inner.shapeCount();
}

export fn snail_path_picture_upload_footprint(picture: *const PathPictureImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(picture.inner.uploadFootprint());
}

export fn snail_path_picture_builder_shape_count(builder: *const PathPictureBuilderImpl) usize {
    return builder.inner.shapeCount();
}

export fn snail_path_picture_builder_mark(builder: *const PathPictureBuilderImpl) SnailShapeMark {
    return fromShapeMark(builder.inner.mark());
}

export fn snail_path_picture_builder_range_from(builder: *const PathPictureBuilderImpl, mark: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeFrom(toShapeMark(mark)) catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_path_picture_builder_range_between(builder: *const PathPictureBuilderImpl, start: SnailShapeMark, end: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeBetween(toShapeMark(start), toShapeMark(end)) catch |err| return mapError(err));
    return SNAIL_OK;
}

// Scene and resources

export fn snail_scene_init(alloc_ptr: ?*const SnailAllocator, out: *?*SceneImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(SceneImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{
        .inner = snail.Scene.init(allocator),
        .overrides_arena = std.heap.ArenaAllocator.init(allocator),
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_scene_deinit(scene: ?*SceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        s.overrides_arena.deinit();
        destroyHandle(s);
    }
}

export fn snail_scene_reset(scene: *SceneImpl) void {
    scene.inner.reset();
    _ = scene.overrides_arena.reset(.retain_capacity);
}

export fn snail_scene_command_count(scene: *const SceneImpl) usize {
    return scene.inner.commandCount();
}

fn stashOverride(scene: *SceneImpl, override: snail.Override) ![]const snail.Override {
    const slot = try scene.overrides_arena.allocator().alloc(snail.Override, 1);
    slot[0] = override;
    return slot;
}

export fn snail_scene_add_text(scene: *SceneImpl, blob: *const TextBlobImpl) c_int {
    scene.inner.addText(.{ .blob = &blob.inner }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_text_transformed(scene: *SceneImpl, blob: *const TextBlobImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_text_override(scene, blob, .{ .transform = transform });
}

export fn snail_scene_add_text_override(scene: *SceneImpl, blob: *const TextBlobImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addText(.{
        .blob = &blob.inner,
        .instances = instances,
    }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture(scene: *SceneImpl, picture: *const PathPictureImpl) c_int {
    scene.inner.addPath(.{ .picture = &picture.inner }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_range(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange) c_int {
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
    }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_override(scene, picture, .{ .transform = transform });
}

export fn snail_scene_add_path_picture_range_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_range_override(scene, picture, range, .{ .transform = transform });
}

export fn snail_scene_add_path_picture_override(scene: *SceneImpl, picture: *const PathPictureImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{ .picture = &picture.inner, .instances = instances }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_range_override(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
        .instances = instances,
    }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_init(alloc_ptr: ?*const SnailAllocator, capacity: usize, out: *?*ResourceSetImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const entries = allocator.alloc(snail.ResourceSet.Entry, capacity) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = handleAllocator().create(ResourceSetImpl) catch {
        allocator.free(entries);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = snail.ResourceSet.init(entries), .entries = entries, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_resource_set_deinit(set: ?*ResourceSetImpl) void {
    if (set) |s| {
        s.allocator.free(s.entries);
        destroyHandle(s);
    }
}

export fn snail_resource_set_reset(set: *ResourceSetImpl) void {
    set.inner.reset();
}

export fn snail_resource_set_count(set: *const ResourceSetImpl) usize {
    return set.inner.len;
}

export fn snail_resource_set_capacity(set: *const ResourceSetImpl) usize {
    return set.inner.capacity();
}

export fn snail_resource_set_put_text_atlas(set: *ResourceSetImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl) c_int {
    set.inner.putTextAtlas(snail.ResourceKey.fromId(key), &atlas.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_text_atlas_options(set: *ResourceSetImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl, atlas_capacity: c_int) c_int {
    set.inner.putTextAtlasOptions(snail.ResourceKey.fromId(key), &atlas.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl) c_int {
    set.inner.putPathPicture(snail.ResourceKey.fromId(key), &picture.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture_options(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl, atlas_capacity: c_int) c_int {
    set.inner.putPathPictureOptions(snail.ResourceKey.fromId(key), &picture.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_image(set: *ResourceSetImpl, key: SnailResourceKey, image: *const ImageImpl) c_int {
    set.inner.putImage(snail.ResourceKey.fromId(key), &image.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_estimate_upload_footprint(set: *const ResourceSetImpl, out: *SnailResourceFootprint) c_int {
    out.* = fromResourceFootprint(set.inner.estimateUploadFootprint() catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_resource_set_add_scene(set: *ResourceSetImpl, scene: *const SceneImpl) c_int {
    set.inner.addScene(&scene.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_prepared_resources_deinit(prepared: ?*PreparedResourcesImpl) void {
    if (prepared) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_prepared_scene_init(
    alloc_ptr: ?*const SnailAllocator,
    prepared: *const PreparedResourcesImpl,
    scene: *const SceneImpl,
    options: SnailDrawOptions,
    out: *?*PreparedSceneImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const zig_options = toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const prepared_scene = snail.PreparedScene.initOwned(allocator, &prepared.inner, &scene.inner, zig_options) catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedSceneImpl) catch {
        var doomed = prepared_scene;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared_scene };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_prepared_scene_deinit(scene: ?*PreparedSceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

export fn snail_prepared_scene_word_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.words.len;
}

export fn snail_prepared_scene_segment_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.segments.len;
}

// Renderer

fn cpuPixels(pixels: ?[*]u8, width: u32, height: u32, stride: u32) ?[*]u8 {
    const ptr = pixels orelse return null;
    if (width == 0 or height == 0) return null;
    const min_stride = std.math.mul(u32, width, 4) catch return null;
    if (stride < min_stride) return null;
    return ptr;
}

export fn snail_gl_renderer_init(out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_opengl) {
        const gl = snail.GlRenderer.init(handleAllocator()) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = gl;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .gl, .gl = gl };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_cpu_available() bool {
    return build_options.enable_cpu;
}

export fn snail_cpu_renderer_init(pixels: ?[*]u8, width: u32, height: u32, stride: u32, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_cpu) {
        const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
        const cpu = snail.CpuRenderer.init(pixel_ptr, width, height, stride);
        const impl = handleAllocator().create(RendererImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
        impl.* = .{ .backend = .cpu, .cpu = cpu };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_cpu_renderer_reinit_buffer(renderer: *RendererImpl, pixels: ?[*]u8, width: u32, height: u32, stride: u32) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .cpu) return SNAIL_ERR_INVALID_ARGUMENT;
    const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.cpu) |*cpu| {
        cpu.reinitBuffer(pixel_ptr, width, height, stride);
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

export fn snail_vulkan_available() bool {
    return build_options.enable_vulkan;
}

export fn snail_vulkan_renderer_init(ctx: *const SnailVulkanContext, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = snail.VulkanContext{
            .physical_device = ctx.physical_device,
            .device = ctx.device,
            .graphics_queue = ctx.graphics_queue,
            .queue_family_index = ctx.queue_family_index,
            .render_pass = ctx.render_pass,
            .color_format = ctx.color_format,
            .supports_dual_source_blend = ctx.supports_dual_source_blend,
        };
        const vk_renderer = snail.VulkanRenderer.init(vk_ctx) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = vk_renderer;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .vulkan, .vulkan = vk_renderer };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_vulkan_renderer_begin_frame(renderer: *RendererImpl, command_buffer: vk.VkCommandBuffer, frame_slot: u32) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .vulkan) return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.vulkan) |*vk_renderer| {
        vk_renderer.beginFrame(.{ .cmd = command_buffer, .frame_index = frame_slot });
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

export fn snail_renderer_deinit(renderer: ?*RendererImpl) void {
    if (renderer) |r| {
        r.deinit();
        destroyHandle(r);
    }
}

export fn snail_renderer_begin_frame(renderer: *RendererImpl) void {
    var erased = renderer.asRenderer();
    erased.beginFrame();
}

export fn snail_renderer_set_subpixel_order(renderer: *RendererImpl, order: c_int) c_int {
    var erased = renderer.asRenderer();
    erased.setSubpixelOrder(toSubpixelOrder(order) catch return SNAIL_ERR_INVALID_ARGUMENT);
    return SNAIL_OK;
}

export fn snail_renderer_subpixel_order(renderer: *const RendererImpl) c_int {
    var erased = @constCast(renderer).asRenderer();
    return @intFromEnum(erased.subpixelOrder());
}

export fn snail_renderer_set_fill_rule(renderer: *RendererImpl, rule: c_int) c_int {
    var erased = renderer.asRenderer();
    erased.setFillRule(toFillRule(rule) catch return SNAIL_ERR_INVALID_ARGUMENT);
    return SNAIL_OK;
}

export fn snail_renderer_fill_rule(renderer: *const RendererImpl) c_int {
    var erased = @constCast(renderer).asRenderer();
    return @intFromEnum(erased.fillRule());
}

export fn snail_renderer_backend_name(renderer: *const RendererImpl) [*:0]const u8 {
    return @ptrCast(renderer.backendName().ptr);
}

export fn snail_renderer_upload_resources_blocking(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    set: *const ResourceSetImpl,
    out: *?*PreparedResourcesImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var erased = renderer.asRenderer();
    const prepared = erased.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set.inner) catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedResourcesImpl) catch {
        var doomed = prepared;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_renderer_draw_prepared(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    options: SnailDrawOptions,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPrepared(&prepared.inner, &scene.inner, toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

// Compile-time features and constants

export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

export fn snail_text_words_per_glyph() usize {
    return snail.lowlevel.TEXT_WORDS_PER_GLYPH;
}
export fn snail_text_words_per_vertex() usize {
    return snail.lowlevel.TEXT_WORDS_PER_VERTEX;
}
export fn snail_text_vertices_per_glyph() usize {
    return snail.lowlevel.TEXT_VERTICES_PER_GLYPH;
}
export fn snail_path_words_per_shape() usize {
    return snail.lowlevel.PATH_WORDS_PER_SHAPE;
}
export fn snail_path_words_per_vertex() usize {
    return snail.lowlevel.PATH_WORDS_PER_VERTEX;
}
export fn snail_path_vertices_per_shape() usize {
    return snail.lowlevel.PATH_VERTICES_PER_SHAPE;
}

export fn snail_mat4_identity() SnailMat4 {
    return fromMat4(snail.Mat4.identity);
}

// Tests

const testing = std.testing;

fn testTextAtlas() !*TextAtlasImpl {
    const assets = @import("assets");
    var atlas: ?*TextAtlasImpl = null;
    const spec = SnailFaceSpec{
        .data = assets.noto_sans_regular.ptr,
        .len = assets.noto_sans_regular.len,
    };
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_init(null, @ptrCast(&spec), 1, &atlas));
    return atlas.?;
}

fn ensureForText(atlas_ptr: **TextAtlasImpl, text: []const u8) !void {
    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_text(atlas_ptr.*, .{}, text.ptr, text.len, &next));
    if (next) |replacement| {
        snail_text_atlas_deinit(atlas_ptr.*);
        atlas_ptr.* = replacement;
    }
}

test "c_api: font metrics helper" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    try testing.expect(snail_font_units_per_em(font.?) > 0);
    const gid = snail_font_glyph_index(font.?, 'A');
    try testing.expect(gid > 0);

    var metrics: SnailGlyphMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_glyph_metrics(font.?, gid, &metrics));
    try testing.expect(metrics.advance_width > 0);
}

test "c_api: text atlas metrics and ensure glyphs" {
    const atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);

    try testing.expectEqual(@as(usize, 1), snail_text_atlas_face_count(atlas));

    var primary_face: u16 = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_primary_face_index(atlas, &primary_face));
    try testing.expectEqual(@as(u16, 0), primary_face);

    var upem: u16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_face_units_per_em(atlas, primary_face, &upem));
    try testing.expect(upem > 0);

    var line_metrics: SnailLineMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_face_line_metrics(atlas, primary_face, &line_metrics));
    try testing.expect(line_metrics.ascent > 0);
    try testing.expect(line_metrics.descent < 0);

    var gid: u16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_glyph_index(atlas, primary_face, 'A', &gid));
    try testing.expect(gid > 0);

    var advance: i16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_advance_width(atlas, primary_face, gid, &advance));
    try testing.expect(advance > 0);

    var cell_metrics: SnailCellMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_cell_metrics(atlas, .{}, 16, &cell_metrics));
    try testing.expect(cell_metrics.cell_width > 0);
    try testing.expect(cell_metrics.line_height > cell_metrics.cell_width);

    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_glyphs(atlas, primary_face, @ptrCast(&gid), 1, &next));
    try testing.expect(next != null);
    defer snail_text_atlas_deinit(next);

    var again: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_glyphs(next.?, primary_face, @ptrCast(&gid), 1, &again));
    try testing.expectEqual(@as(?*TextAtlasImpl, null), again);
}

test "c_api: text atlas shape ensure and blob" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);

    const text = "Hello";
    var shaped: ?*ShapedTextImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_shape_utf8(atlas, .{}, text.ptr, text.len, &shaped));
    defer snail_shaped_text_deinit(shaped);
    try testing.expectEqual(@as(usize, 5), snail_shaped_text_glyph_count(shaped.?));
    try testing.expect(snail_shaped_text_advance_x(shaped.?) > 0);

    var replacement: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_shaped(atlas, shaped.?, &replacement));
    if (replacement) |next| {
        snail_text_atlas_deinit(atlas);
        atlas = next;
    }

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_from_shaped(null, atlas, shaped.?, .{
        .placement = .{ .baseline_x = 10, .baseline_y = 20, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);
    try testing.expectEqual(@as(usize, 5), snail_text_blob_glyph_count(blob.?));
}

test "c_api: text blob rebinds to extended atlas" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "A");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "A", 1, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_text(atlas, .{}, "B", 1, &next));
    try testing.expect(next != null);

    try testing.expectEqual(SNAIL_OK, snail_text_blob_rebind(blob.?, next.?));
    snail_text_atlas_deinit(atlas);
    atlas = next.?;
}

test "c_api: scene and resource set follow public model" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text(scene.?, blob.?));
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text_override(scene.?, blob.?, .{
        .tint = .{ 0.5, 0.75, 1.0, 0.5 },
    }));
    try testing.expectEqual(@as(usize, 2), snail_scene_command_count(scene.?));

    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 4, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_OK, snail_resource_set_add_scene(resources.?, scene.?));
    try testing.expectEqual(@as(usize, 1), snail_resource_set_count(resources.?));
}

test "c_api: path picture builder" {
    var builder: ?*PathPictureBuilderImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_init(null, &builder));
    defer snail_path_picture_builder_deinit(builder);

    const fill = SnailFillStyle{ .paint = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 0.1, 0.2, 0.3, 1 } } };
    const stroke = SnailStrokeStyle{ .paint = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } }, .width = 2, .placement = 1 };
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rounded_rect(
        builder.?,
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
        &fill,
        &stroke,
        8,
        .{},
    ));
    try testing.expectEqual(@as(usize, 1), snail_path_picture_builder_shape_count(builder.?));
    const second_mark = snail_path_picture_builder_mark(builder.?);
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rect(
        builder.?,
        .{ .x = 120, .y = 0, .w = 20, .h = 20 },
        &fill,
        null,
        .{},
    ));

    var second_range: SnailRange = undefined;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_range_from(builder.?, second_mark, &second_range));
    try testing.expectEqual(@as(usize, 1), second_range.start);
    try testing.expectEqual(@as(usize, 1), second_range.count);
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_path_picture_builder_range_between(
        builder.?,
        .{ .shape_count = 2 },
        .{ .shape_count = 1 },
        &second_range,
    ));

    var picture: ?*PathPictureImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_freeze(builder.?, null, null, &picture));
    defer snail_path_picture_deinit(picture);
    try testing.expectEqual(@as(usize, 2), snail_path_picture_shape_count(picture.?));
    var picture_footprint: SnailResourceFootprint = .{};
    snail_path_picture_upload_footprint(picture.?, &picture_footprint);
    try testing.expect(snail_resource_footprint_allocated_bytes(picture_footprint) > 0);

    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 2, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_OK, snail_resource_set_put_path_picture_options(
        resources.?,
        7,
        picture.?,
        SNAIL_RESOURCE_CAPACITY_EXACT,
    ));
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_resource_set_put_path_picture_options(
        resources.?,
        8,
        picture.?,
        99,
    ));
    var set_footprint: SnailResourceFootprint = .{};
    try testing.expectEqual(SNAIL_OK, snail_resource_set_estimate_upload_footprint(resources.?, &set_footprint));
    try testing.expect(snail_resource_footprint_allocated_bytes(set_footprint) >= snail_resource_footprint_allocated_bytes(picture_footprint));

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_path_picture_range(scene.?, picture.?, second_range));
    try testing.expectEqual(SNAIL_OK, snail_scene_add_path_picture_range_override(scene.?, picture.?, second_range, .{
        .tint = .{ 1, 0.5, 0.25, 1 },
    }));
    try testing.expectEqual(@as(usize, 2), snail_scene_command_count(scene.?));
}

test "c_api: image paint init and constants" {
    var pixels = [_]u8{255} ** (4 * 4 * 4);
    var image: ?*ImageImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_image_init_srgba8(null, 4, 4, &pixels, &image));
    defer snail_image_deinit(image);
    try testing.expectEqual(@as(u32, 4), snail_image_width(image.?));
    try testing.expectEqual(@as(u32, 4), snail_image_height(image.?));
    var footprint: SnailResourceFootprint = .{};
    snail_image_upload_footprint(image.?, &footprint);
    try testing.expectEqual(@as(usize, 4 * 4 * 4), snail_resource_footprint_used_bytes(footprint));
    try testing.expect(snail_resource_footprint_allocated_bytes(footprint) >= snail_resource_footprint_used_bytes(footprint));

    try testing.expectEqual(snail.lowlevel.TEXT_WORDS_PER_GLYPH, snail_text_words_per_glyph());
    try testing.expectEqual(snail.lowlevel.TEXT_WORDS_PER_VERTEX, snail_text_words_per_vertex());
    try testing.expectEqual(snail.lowlevel.TEXT_VERTICES_PER_GLYPH, snail_text_vertices_per_glyph());
    try testing.expectEqual(snail.lowlevel.PATH_WORDS_PER_SHAPE, snail_path_words_per_shape());
    try testing.expectEqual(snail.lowlevel.PATH_WORDS_PER_VERTEX, snail_path_words_per_vertex());
    try testing.expectEqual(snail.lowlevel.PATH_VERTICES_PER_SHAPE, snail_path_vertices_per_shape());
}
