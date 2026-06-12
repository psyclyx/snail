//! snail public API.

const math = @import("math.zig");
const text_mod = @import("text.zig");
const image_mod = @import("image.zig");
const target = @import("target.zig");
const paint_mod = @import("paint.zig");
const backend_kind = @import("backend_kind.zig");
const record_key_mod = @import("atlas/record_key.zig");

pub const font = @import("font.zig");

// ── Math + geometry ──

pub const Mat4 = math.Mat4;
pub const Vec2 = math.Vec2;
pub const BBox = math.BBox;
pub const Transform2D = math.Transform2D;
pub const Rect = target.Rect;

// ── Text shaping ──

pub const ShapedText = text_mod.ShapedText;
pub const FaceIndex = text_mod.FaceIndex;

const faces_mod = @import("text/faces.zig");
pub const Face = faces_mod.Face;
pub const Faces = faces_mod.Faces;
pub const shape = faces_mod.shape;
pub const FontWeight = text_mod.FontWeight;
pub const FontStyle = text_mod.FontStyle;
pub const SyntheticStyle = text_mod.SyntheticStyle;
pub const SourceRange = text_mod.SourceRange;
pub const OpenTypeFeature = text_mod.OpenTypeFeature;
pub const ShapeOptions = text_mod.ShapeOptions;
pub const AdvanceProvider = text_mod.AdvanceProvider;
pub const MissingGlyphReplacement = text_mod.MissingGlyphReplacement;
pub const isRenderableTextCodepoint = text_mod.isRenderableTextCodepoint;

pub const Font = font.Font;
pub const tt = font.tt;

// ── Paint ──

pub const PaintExtend = paint_mod.Extend;
pub const ImageFilter = paint_mod.ImageFilter;
pub const LinearGradient = paint_mod.LinearGradient;
pub const RadialGradient = paint_mod.RadialGradient;
pub const ImagePaint = paint_mod.ImagePaint;
pub const Paint = paint_mod.Paint;
pub const FillStyle = paint_mod.FillStyle;
pub const StrokeCap = paint_mod.StrokeCap;
pub const StrokeJoin = paint_mod.StrokeJoin;
pub const StrokePlacement = paint_mod.StrokePlacement;
pub const StrokeStyle = paint_mod.StrokeStyle;
pub const mapPaintToLocal = paint_mod.mapToLocal;

pub const Image = image_mod.Image;

// ── Target / draw state ──

pub const FillRule = target.FillRule;
pub const SubpixelOrder = target.SubpixelOrder;
pub const ColorEncoding = target.ColorEncoding;
pub const TargetEncoding = target.TargetEncoding;
pub const PixelRect = target.PixelRect;
pub const ResolveRegion = target.ResolveRegion;
pub const ResolveBackdrop = target.ResolveBackdrop;
pub const IntermediateFormat = target.IntermediateFormat;
pub const LinearResolve = target.LinearResolve;
pub const DrawResolve = target.DrawResolve;
pub const CoverageTransfer = target.CoverageTransfer;
pub const SnapRule = target.SnapRule;
pub const pixelStep = target.pixelStep;
pub const pixelSteps = target.pixelSteps;
pub const snapToStep = target.snapToStep;
pub const snapDeltaToStep = target.snapDeltaToStep;
pub const snapLengthToStep = target.snapLengthToStep;
pub const snapPointToStep = target.snapPointToStep;
pub const snapRectToStep = target.snapRectToStep;
pub const mvpToScenePixel = target.mvpToScenePixel;
pub const TargetSurface = target.TargetSurface;
pub const RasterOptions = target.RasterOptions;
pub const DrawState = target.DrawState;
pub const DrawPass = target.DrawPass;
pub const resolveRect = target.resolveRect;

pub const BackendKind = backend_kind.BackendKind;

// ── New-API renderers ──

pub const CpuRenderer = @import("render/backend/cpu/renderer.zig").CpuRenderer;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
pub const Gl33Renderer = @import("render/backend/gl/state.zig").Gl33Renderer;
pub const Gl44Renderer = @import("render/backend/gl/state.zig").Gl44Renderer;
pub const Gles30Renderer = @import("render/backend/gles30/state.zig").Gles30Renderer;
pub const VulkanRenderer = @import("render/backend/vulkan/pipeline.zig").VulkanRenderer;
pub const VulkanContext = @import("render/backend/vulkan/types.zig").VulkanContext;

// ── Core new-API surface ──

pub const Range = @import("range.zig").Range;
pub const recordKey = record_key_mod;
pub const RecordKey = record_key_mod.RecordKey;
pub const ns = record_key_mod.ns;

pub const GlyphCurves = @import("atlas/curves.zig").GlyphCurves;
pub const PagePool = @import("atlas/page_pool.zig").PagePool;
pub const AtlasPage = @import("atlas/page.zig").AtlasPage;

const atlas_mod = @import("atlas.zig");
pub const Atlas = atlas_mod.Atlas;
pub const AtlasEntry = atlas_mod.Entry;
pub const CompositeMode = atlas_mod.CompositeMode;
pub const AtlasLayer = atlas_mod.Layer;
pub const PaintRecordInfo = atlas_mod.PaintRecordInfo;
pub const AtlasRecord = @import("atlas/record.zig").AtlasRecord;

const shape_mod = @import("picture/shape.zig");
pub const Shape = shape_mod.Shape;
pub const Override = shape_mod.Override;

pub const DrawSegment = @import("picture/draw_records.zig").DrawSegment;
pub const Binding = @import("picture/draw_records.zig").Binding;
pub const emit = @import("picture/emit.zig");

// ── Custom-shader primitives ──
//
// Symbolic decoders + texel-coord resolvers so callers can drive their
// own shader pipeline off the same byte layout the built-in renderers
// consume. Bind atlas pages via `Renderer.curveTexHandle()` etc.

const vertex_mod = @import("render/format/vertex.zig");
pub const Instance = vertex_mod.Instance;
pub const DecodedInstance = vertex_mod.DecodedInstance;
pub const decodeInstance = vertex_mod.decodeInstance;
pub const BindingTexels = vertex_mod.BindingTexels;
pub const bindingTexels = vertex_mod.bindingTexels;
pub const WORDS_PER_INSTANCE = vertex_mod.WORDS_PER_INSTANCE;
pub const WORDS_PER_OVERRIDE = vertex_mod.WORDS_PER_OVERRIDE;

pub const HintVm = @import("font/hint_vm.zig").HintVm;
pub const HintPpem = @import("font/hint_vm.zig").HintPpem;
pub const HintVmStats = @import("font/hint_vm.zig").HintVmStats;
pub const HintError = @import("font/hint_vm.zig").HintError;

pub const CpuBackendCache = @import("render/backend/cpu/backend_cache.zig").CpuBackendCache;
pub const drawCpu = @import("render/backend/cpu/draw.zig").drawCpu;
pub const Gl33BackendCache = @import("render/backend/gl/backend_cache.zig").Gl33BackendCache;
pub const Gl44BackendCache = @import("render/backend/gl/backend_cache.zig").Gl44BackendCache;
pub const Gles30BackendCache = @import("render/backend/gl/backend_cache.zig").Gles30BackendCache;
pub const VulkanBackendCache = @import("render/backend/vulkan/backend_cache.zig").VulkanBackendCache;
pub const VulkanBackendCachePipelineShape = @import("render/backend/vulkan/backend_cache.zig").PipelineShape;

pub const paths = @import("paths.zig");
pub const coverage = @import("coverage.zig");
pub const snap = @import("snap.zig");

/// Default ASCII printable character set (space through tilde).
pub const ASCII_PRINTABLE = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

test {
    _ = math;
    _ = font;
    _ = text_mod;
    _ = image_mod;
    _ = target;
    _ = paint_mod;
    _ = record_key_mod;
    _ = @import("atlas/curves.zig");
    _ = @import("atlas/record.zig");
    _ = @import("atlas/page.zig");
    _ = @import("atlas/page_pool.zig");
    _ = atlas_mod;
    _ = @import("paths.zig");
    _ = @import("font/hint_vm.zig");
    _ = @import("text/faces.zig");
    _ = shape_mod;
    _ = @import("picture/draw_records.zig");
    _ = @import("picture/emit.zig");
    _ = @import("render/backend/cpu/backend_cache.zig");
    _ = @import("render/backend/cpu/draw.zig");
    _ = @import("render/backend/gl/backend_cache.zig");
    _ = @import("render/backend/vulkan/backend_cache.zig");
    _ = @import("coverage.zig");
    _ = @import("snap.zig");
    _ = @import("util/hamt.zig");
}
