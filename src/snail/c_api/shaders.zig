const common = @import("common.zig");
const std = common.std;
const builtin = common.builtin;
const snail = common.snail;
const resource_key = common.resource_key;
const ttf = common.ttf;
const build_options = common.build_options;
const c_convert = common.c_convert;
const c_handles = common.c_handles;
const c_runtime = common.c_runtime;
const c_types = common.c_types;
const vk = common.vk;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocFn = common.SnailAllocFn;
const SnailFreeFn = common.SnailFreeFn;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_INVALID_FONT = common.SNAIL_ERR_INVALID_FONT;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_RENDERER_FAILED = common.SNAIL_ERR_RENDERER_FAILED;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SNAIL_ERR_DRAW_FAILED = common.SNAIL_ERR_DRAW_FAILED;
const SnailVulkanContext = common.SnailVulkanContext;
const SnailBBox = common.SnailBBox;
const SnailGlyphMetrics = common.SnailGlyphMetrics;
const SnailLineMetrics = common.SnailLineMetrics;
const SnailDecorationMetrics = common.SnailDecorationMetrics;
const SnailScriptMetrics = common.SnailScriptMetrics;
const SnailScriptTransform = common.SnailScriptTransform;
const SnailCellMetrics = common.SnailCellMetrics;
const SnailRect = common.SnailRect;
const SnailMat4 = common.SnailMat4;
const SnailString = common.SnailString;
const SnailTransform2D = common.SnailTransform2D;
const SnailOverride = common.SnailOverride;
const SnailRange = common.SnailRange;
const SnailShapeMark = common.SnailShapeMark;
const SnailSyntheticStyle = common.SnailSyntheticStyle;
const SnailFaceSpec = common.SnailFaceSpec;
const SnailFontStyle = common.SnailFontStyle;
const SnailShapedGlyph = common.SnailShapedGlyph;
const SnailTextPlacement = common.SnailTextPlacement;
const SnailTextAppendOptions = common.SnailTextAppendOptions;
const SnailResolveTarget = common.SnailResolveTarget;
const SnailDrawOptions = common.SnailDrawOptions;
const SnailResourceKey = common.SnailResourceKey;
const SnailResourceStamp = common.SnailResourceStamp;
const SNAIL_RESOURCE_CAPACITY_GROWABLE = common.SNAIL_RESOURCE_CAPACITY_GROWABLE;
const SNAIL_RESOURCE_CAPACITY_EXACT = common.SNAIL_RESOURCE_CAPACITY_EXACT;
const SnailResourceFootprint = common.SnailResourceFootprint;
const SnailResourceCacheStats = common.SnailResourceCacheStats;
const SnailGlTextCoverageBindings = common.SnailGlTextCoverageBindings;
const SnailVulkanTextCoverageBindings = common.SnailVulkanTextCoverageBindings;
const SNAIL_PAINT_SOLID = common.SNAIL_PAINT_SOLID;
const SNAIL_PAINT_LINEAR = common.SNAIL_PAINT_LINEAR;
const SNAIL_PAINT_RADIAL = common.SNAIL_PAINT_RADIAL;
const SNAIL_PAINT_IMAGE = common.SNAIL_PAINT_IMAGE;
const SnailLinearGradient = common.SnailLinearGradient;
const SnailRadialGradient = common.SnailRadialGradient;
const SnailImagePaint = common.SnailImagePaint;
const SnailPaint = common.SnailPaint;
const SnailFillStyle = common.SnailFillStyle;
const SnailStrokeStyle = common.SnailStrokeStyle;
const wrapBBox = common.wrapBBox;
const wrapString = common.wrapString;
const wrapDecorationMetrics = common.wrapDecorationMetrics;
const wrapScriptMetrics = common.wrapScriptMetrics;
const wrapScriptTransform = common.wrapScriptTransform;
const wrapResourceStamp = common.wrapResourceStamp;
const toRect = common.toRect;
const toSnailRect = common.toSnailRect;
const fromMat4 = common.fromMat4;
const toTransform = common.toTransform;
const toOverride = common.toOverride;
const toGlCoverageBindings = common.toGlCoverageBindings;
const toVulkanCoverageBindings = common.toVulkanCoverageBindings;
const fromResourceFootprint = common.fromResourceFootprint;
const fromResourceCacheStats = common.fromResourceCacheStats;
const toResourceCapacityMode = common.toResourceCapacityMode;
const reservedResourceCapacityMode = common.reservedResourceCapacityMode;
const toRange = common.toRange;
const fromRange = common.fromRange;
const toShapeMark = common.toShapeMark;
const fromShapeMark = common.fromShapeMark;
const toSyntheticStyle = common.toSyntheticStyle;
const toFontWeight = common.toFontWeight;
const toFontStyle = common.toFontStyle;
const toDecoration = common.toDecoration;
const toTextPlacement = common.toTextPlacement;
const toDrawOptions = common.toDrawOptions;
const toPaint = common.toPaint;
const toFillStyle = common.toFillStyle;
const toStrokeStyle = common.toStrokeStyle;
const toOptFill = common.toOptFill;
const toOptStroke = common.toOptStroke;
const FontImpl = common.FontImpl;
const TextAtlasImpl = common.TextAtlasImpl;
const ShapedTextImpl = common.ShapedTextImpl;
const TextBlobImpl = common.TextBlobImpl;
const ImageImpl = common.ImageImpl;
const PathImpl = common.PathImpl;
const PathPictureBuilderImpl = common.PathPictureBuilderImpl;
const PathPictureImpl = common.PathPictureImpl;
const SceneImpl = common.SceneImpl;
const ResourceSetImpl = common.ResourceSetImpl;
const PreparedResourcesImpl = common.PreparedResourcesImpl;
const PreparedSceneImpl = common.PreparedSceneImpl;
const PreparedResourceRetirementQueueImpl = common.PreparedResourceRetirementQueueImpl;
const ResourceUploadPlanImpl = common.ResourceUploadPlanImpl;
const PendingResourceUploadImpl = common.PendingResourceUploadImpl;
const DrawListImpl = common.DrawListImpl;
const TextCoverageRecordsImpl = common.TextCoverageRecordsImpl;
const CoverageBackendImpl = common.CoverageBackendImpl;
const ThreadPoolImpl = common.ThreadPoolImpl;
const RendererImpl = common.RendererImpl;
const destroyHandle = common.destroyHandle;

pub export fn snail_gl_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.vertex_interface);
}

pub export fn snail_gl_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_interface);
}

pub export fn snail_gl_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.resource_interface);
}

pub export fn snail_gl_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.coverage_functions);
}

pub export fn snail_gl_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_interface);
}

pub export fn snail_gl_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_functions);
}

pub export fn snail_gl_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_body);
}

pub export fn snail_gl_coverage_backend_bind_resources(backend: *CoverageBackendImpl, bindings: SnailGlTextCoverageBindings) c_int {
    if (comptime !build_options.enable_opengl) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl => |gl_backend| {
            gl_backend.bindResources(toGlCoverageBindings(bindings) catch return SNAIL_ERR_INVALID_ARGUMENT);
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_vulkan_coverage_shader_vertex_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.vertex_shader);
}

pub export fn snail_vulkan_coverage_shader_text_fragment_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.text_fragment_shader);
}

pub export fn snail_vulkan_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.coverage_functions);
}

pub export fn snail_vulkan_coverage_shader_descriptor_set_index() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.descriptor_set_index;
}

pub export fn snail_vulkan_coverage_shader_curve_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.curve_texture_binding;
}

pub export fn snail_vulkan_coverage_shader_band_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.band_texture_binding;
}

pub export fn snail_vulkan_coverage_backend_descriptor_set_layout(backend: *CoverageBackendImpl) vk.VkDescriptorSetLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.descriptorSetLayout(),
        else => null,
    };
}

pub export fn snail_vulkan_coverage_backend_pipeline_layout(backend: *CoverageBackendImpl) vk.VkPipelineLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.pipelineLayout(),
        else => null,
    };
}

pub export fn snail_vulkan_coverage_backend_bind_resources(backend: *CoverageBackendImpl, bindings: SnailVulkanTextCoverageBindings) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .vulkan => |vk_backend| {
            vk_backend.bindResources(toVulkanCoverageBindings(bindings));
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}
