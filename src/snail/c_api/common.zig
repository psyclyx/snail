//! C API for snail's public Zig resource model.
//! All exported functions use opaque handles and explicit ownership.

pub const std = @import("std");
pub const builtin = @import("builtin");
pub const snail = @import("../root.zig");
pub const resource_key = @import("../resource_key.zig");
pub const ttf = @import("../font/ttf.zig");
pub const build_options = @import("build_options");
pub const c_convert = @import("convert.zig");
pub const c_handles = @import("handles.zig");
pub const c_runtime = @import("runtime.zig");
pub const c_types = @import("types.zig");

pub const vk = c_types.vk;

pub const resolveAllocator = c_runtime.resolveAllocator;
pub const mapError = c_runtime.mapError;

pub const SnailAllocFn = c_types.SnailAllocFn;
pub const SnailFreeFn = c_types.SnailFreeFn;
pub const SnailAllocator = c_types.SnailAllocator;
pub const SNAIL_OK = c_types.SNAIL_OK;
pub const SNAIL_ERR_INVALID_FONT = c_types.SNAIL_ERR_INVALID_FONT;
pub const SNAIL_ERR_OUT_OF_MEMORY = c_types.SNAIL_ERR_OUT_OF_MEMORY;
pub const SNAIL_ERR_RENDERER_FAILED = c_types.SNAIL_ERR_RENDERER_FAILED;
pub const SNAIL_ERR_INVALID_ARGUMENT = c_types.SNAIL_ERR_INVALID_ARGUMENT;
pub const SNAIL_ERR_DRAW_FAILED = c_types.SNAIL_ERR_DRAW_FAILED;
pub const SNAIL_ERR_HINT_UNAVAILABLE = c_types.SNAIL_ERR_HINT_UNAVAILABLE;

pub const SnailVulkanContext = c_types.SnailVulkanContext;
pub const SnailBBox = c_types.SnailBBox;
pub const SnailGlyphMetrics = c_types.SnailGlyphMetrics;
pub const SnailLineMetrics = c_types.SnailLineMetrics;
pub const SnailDecorationMetrics = c_types.SnailDecorationMetrics;
pub const SnailScriptMetrics = c_types.SnailScriptMetrics;
pub const SnailScriptTransform = c_types.SnailScriptTransform;
pub const SnailCellMetrics = c_types.SnailCellMetrics;
pub const SnailRect = c_types.SnailRect;
pub const SnailMat4 = c_types.SnailMat4;
pub const SnailString = c_types.SnailString;
pub const SnailTransform2D = c_types.SnailTransform2D;
pub const SnailOverride = c_types.SnailOverride;
pub const SnailRange = c_types.SnailRange;
pub const SnailShapeMark = c_types.SnailShapeMark;
pub const SnailSyntheticStyle = c_types.SnailSyntheticStyle;
pub const SnailFaceSpec = c_types.SnailFaceSpec;
pub const SnailFontStyle = c_types.SnailFontStyle;
pub const SnailShapedGlyph = c_types.SnailShapedGlyph;
pub const SnailTextPlacement = c_types.SnailTextPlacement;
pub const SnailTextAppendOptions = c_types.SnailTextAppendOptions;
pub const SnailTextAppendResult = c_types.SnailTextAppendResult;
pub const SnailTrueTypeHintPpem = c_types.SnailTrueTypeHintPpem;
pub const SnailTrueTypeHintRunStats = c_types.SnailTrueTypeHintRunStats;
pub const SnailTargetSurface = c_types.SnailTargetSurface;
pub const SnailPixelRect = c_types.SnailPixelRect;
pub const SnailLinearResolve = c_types.SnailLinearResolve;
pub const SnailRasterOptions = c_types.SnailRasterOptions;
pub const SnailDrawState = c_types.SnailDrawState;
pub const SnailDrawPass = c_types.SnailDrawPass;
pub const SnailResourceKey = c_types.SnailResourceKey;
pub const SnailTextResourceKeys = c_types.SnailTextResourceKeys;
pub const SnailTextDraw = c_types.SnailTextDraw;
pub const SnailPathPictureDraw = c_types.SnailPathPictureDraw;
pub const SnailResourceStamp = c_types.SnailResourceStamp;
pub const SNAIL_RESOURCE_CAPACITY_GROWABLE = c_types.SNAIL_RESOURCE_CAPACITY_GROWABLE;
pub const SNAIL_RESOURCE_CAPACITY_EXACT = c_types.SNAIL_RESOURCE_CAPACITY_EXACT;
pub const SnailResourceFootprint = c_types.SnailResourceFootprint;
pub const SnailResourceCacheStats = c_types.SnailResourceCacheStats;
pub const SnailResourceUploadPlanSummary = c_types.SnailResourceUploadPlanSummary;
pub const SnailCoverageDrawState = c_types.SnailCoverageDrawState;
pub const SnailGl33TextCoverageProgram = c_types.SnailGl33TextCoverageProgram;
pub const SnailGl44TextCoverageProgram = c_types.SnailGl44TextCoverageProgram;
pub const SnailGles30TextCoverageProgram = c_types.SnailGles30TextCoverageProgram;
pub const SnailVulkanTextCoverageProgram = c_types.SnailVulkanTextCoverageProgram;
pub const SNAIL_PAINT_SOLID = c_types.SNAIL_PAINT_SOLID;
pub const SNAIL_PAINT_LINEAR = c_types.SNAIL_PAINT_LINEAR;
pub const SNAIL_PAINT_RADIAL = c_types.SNAIL_PAINT_RADIAL;
pub const SNAIL_PAINT_IMAGE = c_types.SNAIL_PAINT_IMAGE;
pub const SnailLinearGradient = c_types.SnailLinearGradient;
pub const SnailRadialGradient = c_types.SnailRadialGradient;
pub const SnailImagePaint = c_types.SnailImagePaint;
pub const SnailPaint = c_types.SnailPaint;
pub const SnailFillStyle = c_types.SnailFillStyle;
pub const SnailStrokeStyle = c_types.SnailStrokeStyle;

pub const wrapBBox = c_convert.wrapBBox;
pub const wrapString = c_convert.wrapString;
pub const wrapDecorationMetrics = c_convert.wrapDecorationMetrics;
pub const wrapScriptMetrics = c_convert.wrapScriptMetrics;
pub const wrapScriptTransform = c_convert.wrapScriptTransform;
pub const wrapResourceStamp = c_convert.wrapResourceStamp;
pub const toRect = c_convert.toRect;
pub const toSnailRect = c_convert.toSnailRect;
pub const fromMat4 = c_convert.fromMat4;
pub const toTransform = c_convert.toTransform;
pub const toOverride = c_convert.toOverride;
pub const fromCoverageDrawState = c_convert.fromCoverageDrawState;
pub const toCoverageDrawState = c_convert.toCoverageDrawState;
pub const toGl33CoverageProgram = c_convert.toGl33CoverageProgram;
pub const toGl44CoverageProgram = c_convert.toGl44CoverageProgram;
pub const toGles30CoverageProgram = c_convert.toGles30CoverageProgram;
pub const toVulkanCoverageProgram = c_convert.toVulkanCoverageProgram;
pub const fromResourceFootprint = c_convert.fromResourceFootprint;
pub const fromResourceCacheStats = c_convert.fromResourceCacheStats;
pub const wrapTextResourceKeys = c_convert.wrapTextResourceKeys;
pub const toTextResourceKeys = c_convert.toTextResourceKeys;
pub const toResourceCapacityMode = c_convert.toResourceCapacityMode;
pub const reservedResourceCapacityMode = c_convert.reservedResourceCapacityMode;
pub const toRange = c_convert.toRange;
pub const fromRange = c_convert.fromRange;
pub const toShapeMark = c_convert.toShapeMark;
pub const fromShapeMark = c_convert.fromShapeMark;
pub const toSyntheticStyle = c_convert.toSyntheticStyle;
pub const toFontWeight = c_convert.toFontWeight;
pub const toFontStyle = c_convert.toFontStyle;
pub const toDecoration = c_convert.toDecoration;
pub const toTextPlacement = c_convert.toTextPlacement;
pub const fromTextAppendResult = c_convert.fromTextAppendResult;
pub const toTrueTypeHintPpem = c_convert.toTrueTypeHintPpem;
pub const fromTrueTypeHintRunStats = c_convert.fromTrueTypeHintRunStats;
pub const toDrawState = c_convert.toDrawState;
pub const toDrawPass = c_convert.toDrawPass;
pub const toPaint = c_convert.toPaint;
pub const toFillStyle = c_convert.toFillStyle;
pub const toStrokeStyle = c_convert.toStrokeStyle;
pub const toOptFill = c_convert.toOptFill;
pub const toOptStroke = c_convert.toOptStroke;

// Opaque handle implementations

pub const FontImpl = c_handles.FontImpl;
pub const TextAtlasImpl = c_handles.TextAtlasImpl;
pub const ShapedTextImpl = c_handles.ShapedTextImpl;
pub const TextBlobImpl = c_handles.TextBlobImpl;
pub const TextBlobBundleImpl = c_handles.TextBlobBundleImpl;
pub const BlobInProgressImpl = c_handles.BlobInProgressImpl;
pub const TrueTypeHintContextImpl = c_handles.TrueTypeHintContextImpl;
pub const TrueTypePreparedHintRunImpl = c_handles.TrueTypePreparedHintRunImpl;
pub const ImageImpl = c_handles.ImageImpl;
pub const PathImpl = c_handles.PathImpl;
pub const PathPictureBuilderImpl = c_handles.PathPictureBuilderImpl;
pub const PathPictureImpl = c_handles.PathPictureImpl;
pub const SceneImpl = c_handles.SceneImpl;
pub const ResourceManifestImpl = c_handles.ResourceManifestImpl;
pub const PreparedResourcesImpl = c_handles.PreparedResourcesImpl;
pub const PreparedSceneImpl = c_handles.PreparedSceneImpl;
pub const PreparedResourceRetirementQueueImpl = c_handles.PreparedResourceRetirementQueueImpl;
pub const ResourceUploadPlanImpl = c_handles.ResourceUploadPlanImpl;
pub const PendingResourceUploadImpl = c_handles.PendingResourceUploadImpl;
pub const VulkanFrameImpl = c_handles.VulkanFrameImpl;
pub const DrawListImpl = c_handles.DrawListImpl;
pub const TextCoverageRecordsImpl = c_handles.TextCoverageRecordsImpl;
pub const CoverageBackendImpl = c_handles.CoverageBackendImpl;
pub const ThreadPoolImpl = c_handles.ThreadPoolImpl;
pub const RendererImpl = c_handles.RendererImpl;

pub const test_api = if (builtin.is_test) struct {
    pub const FontImpl = c_handles.FontImpl;
    pub const TextAtlasImpl = c_handles.TextAtlasImpl;
    pub const ShapedTextImpl = c_handles.ShapedTextImpl;
    pub const TextBlobImpl = c_handles.TextBlobImpl;
    pub const TextBlobBundleImpl = c_handles.TextBlobBundleImpl;
    pub const BlobInProgressImpl = c_handles.BlobInProgressImpl;
    pub const TrueTypeHintContextImpl = c_handles.TrueTypeHintContextImpl;
    pub const TrueTypePreparedHintRunImpl = c_handles.TrueTypePreparedHintRunImpl;
    pub const ImageImpl = c_handles.ImageImpl;
    pub const PathImpl = c_handles.PathImpl;
    pub const PathPictureBuilderImpl = c_handles.PathPictureBuilderImpl;
    pub const PathPictureImpl = c_handles.PathPictureImpl;
    pub const SceneImpl = c_handles.SceneImpl;
    pub const ResourceManifestImpl = c_handles.ResourceManifestImpl;
    pub const PreparedResourcesImpl = c_handles.PreparedResourcesImpl;
    pub const PreparedSceneImpl = c_handles.PreparedSceneImpl;
    pub const PreparedResourceRetirementQueueImpl = c_handles.PreparedResourceRetirementQueueImpl;
    pub const ResourceUploadPlanImpl = c_handles.ResourceUploadPlanImpl;
    pub const PendingResourceUploadImpl = c_handles.PendingResourceUploadImpl;
    pub const VulkanFrameImpl = c_handles.VulkanFrameImpl;
    pub const DrawListImpl = c_handles.DrawListImpl;
    pub const TextCoverageRecordsImpl = c_handles.TextCoverageRecordsImpl;
    pub const CoverageBackendImpl = c_handles.CoverageBackendImpl;
    pub const ThreadPoolImpl = c_handles.ThreadPoolImpl;
    pub const RendererImpl = c_handles.RendererImpl;
} else struct {};

pub fn createHandle(comptime T: type, alloc_ptr: ?*const SnailAllocator) !*T {
    const stored = try c_runtime.createStoredAllocator(alloc_ptr);
    errdefer c_runtime.destroyStoredAllocator(stored);
    const ptr = try stored.allocator().create(T);
    ptr.handle_allocator = stored;
    return ptr;
}

pub fn createHandleSharingAllocator(comptime T: type, stored: *c_runtime.StoredAllocator) !*T {
    _ = c_runtime.retainStoredAllocator(stored);
    errdefer c_runtime.destroyStoredAllocator(stored);
    const ptr = try stored.allocator().create(T);
    ptr.handle_allocator = stored;
    return ptr;
}

pub fn allocatorForHandle(ptr: anytype) std.mem.Allocator {
    return ptr.*.handle_allocator.allocator();
}

pub fn destroyHandle(ptr: anytype) void {
    const stored = ptr.*.handle_allocator;
    const allocator = stored.allocator();
    allocator.destroy(ptr);
    c_runtime.destroyStoredAllocator(stored);
}
