const std = @import("std");

const build_options = @import("build_options");
const c_handles = @import("handles.zig");
const c_runtime = @import("runtime.zig");

pub const vk = if (build_options.enable_vulkan) @import("../render/backend/vulkan/pipeline.zig").vk else struct {
    pub const VkPhysicalDevice = ?*anyopaque;
    pub const VkDevice = ?*anyopaque;
    pub const VkQueue = ?*anyopaque;
    pub const VkRenderPass = usize;
    pub const VkFormat = c_int;
    pub const VkCommandBuffer = ?*anyopaque;
    pub const VkFence = ?*anyopaque;
    pub const VkDescriptorSetLayout = ?*anyopaque;
    pub const VkPipelineLayout = ?*anyopaque;
};

pub const SnailAllocFn = c_runtime.SnailAllocFn;
pub const SnailFreeFn = c_runtime.SnailFreeFn;
pub const SnailAllocator = c_runtime.SnailAllocator;
pub const SNAIL_OK = c_runtime.SNAIL_OK;
pub const SNAIL_ERR_INVALID_FONT = c_runtime.SNAIL_ERR_INVALID_FONT;
pub const SNAIL_ERR_OUT_OF_MEMORY = c_runtime.SNAIL_ERR_OUT_OF_MEMORY;
pub const SNAIL_ERR_RENDERER_FAILED = c_runtime.SNAIL_ERR_RENDERER_FAILED;
pub const SNAIL_ERR_INVALID_ARGUMENT = c_runtime.SNAIL_ERR_INVALID_ARGUMENT;
pub const SNAIL_ERR_DRAW_FAILED = c_runtime.SNAIL_ERR_DRAW_FAILED;
pub const SNAIL_ERR_HINT_UNAVAILABLE = c_runtime.SNAIL_ERR_HINT_UNAVAILABLE;

const TextBlobImpl = c_handles.TextBlobImpl;
const ImageImpl = c_handles.ImageImpl;
const PathPictureImpl = c_handles.PathPictureImpl;

pub const SnailVulkanContext = extern struct {
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    queue_family_index: u32,
    render_pass: vk.VkRenderPass,
    color_format: vk.VkFormat,
    supports_dual_source_blend: bool = false,
};

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

pub const SnailDecorationMetrics = extern struct {
    underline_position: i16,
    underline_thickness: i16,
    strikethrough_position: i16,
    strikethrough_thickness: i16,
};

pub const SnailScriptMetrics = extern struct {
    x_size: i16,
    y_size: i16,
    x_offset: i16,
    y_offset: i16,
};

pub const SnailScriptTransform = extern struct {
    x: f32,
    y: f32,
    font_size: f32,
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

pub const SnailString = extern struct {
    data: [*]const u8,
    len: usize,
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

pub const SnailTextAppendResult = extern struct {
    advance_x: f32 = 0,
    advance_y: f32 = 0,
    missing: bool = false,
};

pub const SnailTrueTypeHintPpem = extern struct {
    x_26_6: u32,
    y_26_6: u32,
};

pub const SnailTrueTypeHintRunStats = extern struct {
    glyph_count: usize = 0,
    advance_x: f32 = 0,
    advance_y: f32 = 0,
};

pub const SnailTargetSurface = extern struct {
    pixel_width: f32,
    pixel_height: f32,
    attachment_encoding: c_int = 0,
    stored_pixel_encoding: c_int = 0,
};

pub const SnailPixelRect = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    w: u32 = 0,
    h: u32 = 0,
};

pub const SnailLinearResolve = extern struct {
    backdrop_kind: c_int = 0,
    clear_color: [4]f32 = .{ 0, 0, 0, 0 },
    region_kind: c_int = 0,
    region_rect: SnailPixelRect = .{},
    intermediate_format: c_int = 0,
};

pub const SnailRasterOptions = extern struct {
    subpixel_order: c_int = 0,
    fill_rule: c_int = 0,
    coverage_exponent: f32 = 1.0,
};

pub const SnailDrawState = extern struct {
    mvp: SnailMat4,
    surface: SnailTargetSurface,
    raster: SnailRasterOptions = .{},
};

pub const SnailDrawPass = extern struct {
    state: SnailDrawState,
    resolve_kind: c_int = 0,
    linear_resolve: SnailLinearResolve = .{},
};

pub const SnailResourceKey = u64;

pub const SnailTextResourceKeys = extern struct {
    atlas_key: SnailResourceKey = 0,
    paint_key: SnailResourceKey = 0,
    has_paint_key: bool = false,
};

pub const SnailTextDraw = extern struct {
    blob: ?*const TextBlobImpl = null,
    resources: SnailTextResourceKeys = .{},
    override_value: SnailOverride = .{},
    has_override: bool = false,
};

pub const SnailPathPictureDraw = extern struct {
    picture: ?*const PathPictureImpl = null,
    key: SnailResourceKey = 0,
    range: SnailRange = .{},
    override_value: SnailOverride = .{},
    has_range: bool = false,
    has_override: bool = false,
};

pub const SnailResourceStamp = extern struct {
    identity: u64 = 0,
    layout: u64 = 0,
    content: u64 = 0,
};

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

pub const SnailResourceCacheStats = extern struct {
    generation: u64 = 0,
    active_atlas_pages_resident: u32 = 0,
    active_atlas_layers_allocated: u32 = 0,
    atlas_pages_resident: u32 = 0,
    atlas_layers_allocated: u32 = 0,
    active_image_layers_resident: u32 = 0,
    active_image_layers_allocated: u32 = 0,
    image_layers_resident: u32 = 0,
    image_layers_allocated: u32 = 0,
};

pub const SnailResourceUploadPlanSummary = extern struct {
    footprint: SnailResourceFootprint = .{},
    upload_bytes: usize = 0,
    upload_curve_bytes: usize = 0,
    upload_band_bytes: usize = 0,
    upload_layer_info_bytes: usize = 0,
    upload_image_bytes: usize = 0,
    changed_bytes: usize = 0,
    changed_key_count: usize = 0,
    requires_cache_rebuild: bool = false,
};

pub const SnailCoverageDrawState = extern struct {
    fill_rule: c_int = 0,
    subpixel_order: c_int = 0,
    output_srgb: bool = false,
    coverage_exponent: f32 = 1.0,
    layer_base: u32 = 0,
};

pub const SnailGl33TextCoverageProgram = extern struct {
    curve_tex_loc: c_int = -1,
    band_tex_loc: c_int = -1,
    layer_tex_loc: c_int = -1,
    image_tex_loc: c_int = -1,
    fill_rule_loc: c_int = -1,
    subpixel_order_loc: c_int = -1,
    output_srgb_loc: c_int = -1,
    coverage_exponent_loc: c_int = -1,
    layer_base_loc: c_int = -1,
    curve_tex_unit: c_int = 0,
    band_tex_unit: c_int = 1,
    layer_tex_unit: c_int = 2,
    image_tex_unit: c_int = 3,
};

pub const SnailGl44TextCoverageProgram = extern struct {
    curve_tex_loc: c_int = -1,
    band_tex_loc: c_int = -1,
    layer_tex_loc: c_int = -1,
    image_tex_loc: c_int = -1,
    fill_rule_loc: c_int = -1,
    subpixel_order_loc: c_int = -1,
    output_srgb_loc: c_int = -1,
    coverage_exponent_loc: c_int = -1,
    layer_base_loc: c_int = -1,
    curve_tex_unit: c_int = 0,
    band_tex_unit: c_int = 1,
    layer_tex_unit: c_int = 2,
    image_tex_unit: c_int = 3,
};

pub const SnailGles3TextCoverageProgram = extern struct {
    curve_tex_loc: c_int = -1,
    band_tex_loc: c_int = -1,
    layer_tex_loc: c_int = -1,
    image_tex_loc: c_int = -1,
    fill_rule_loc: c_int = -1,
    subpixel_order_loc: c_int = -1,
    output_srgb_loc: c_int = -1,
    coverage_exponent_loc: c_int = -1,
    layer_base_loc: c_int = -1,
    curve_tex_unit: c_int = 0,
    band_tex_unit: c_int = 1,
    layer_tex_unit: c_int = 2,
    image_tex_unit: c_int = 3,
};

pub const SnailVulkanTextCoverageProgram = extern struct {
    pipeline_layout: vk.VkPipelineLayout = null,
    descriptor_set_index: u32 = 0,
};

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
