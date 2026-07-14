//! snail public API.
//!
//! Facade over the `snail_core` module (backend-independent primitives,
//! see `core.zig`) plus the concrete renderer backends and the `coverage`
//! custom-shader surface. Consumers `@import("snail")` and get the whole
//! flat API; core stays a separate, backend-free module underneath.

const core = @import("core.zig");

// ── Core surface (re-exported from snail_core) ──

pub const font = core.font;

pub const Mat4 = core.Mat4;
pub const Vec2 = core.Vec2;
pub const BBox = core.BBox;
pub const Transform2D = core.Transform2D;
pub const Rect = core.Rect;

pub const ShapedText = core.ShapedText;
pub const FaceIndex = core.FaceIndex;
pub const Face = core.Face;
pub const Faces = core.Faces;
pub const shape = core.shape;
pub const FontWeight = core.FontWeight;
pub const FontStyle = core.FontStyle;
pub const SyntheticStyle = core.SyntheticStyle;
pub const SourceRange = core.SourceRange;
pub const OpenTypeFeature = core.OpenTypeFeature;
pub const ShapeOptions = core.ShapeOptions;
pub const AdvanceProvider = core.AdvanceProvider;
pub const MissingGlyphReplacement = core.MissingGlyphReplacement;
pub const isRenderableTextCodepoint = core.isRenderableTextCodepoint;
pub const Font = core.Font;
pub const tt = core.tt;

pub const PaintExtend = core.PaintExtend;
pub const ImageFilter = core.ImageFilter;
pub const LinearGradient = core.LinearGradient;
pub const RadialGradient = core.RadialGradient;
pub const ImagePaint = core.ImagePaint;
pub const Paint = core.Paint;
pub const FillStyle = core.FillStyle;
pub const StrokeCap = core.StrokeCap;
pub const StrokeJoin = core.StrokeJoin;
pub const StrokePlacement = core.StrokePlacement;
pub const StrokeStyle = core.StrokeStyle;
pub const mapPaintToLocal = core.mapPaintToLocal;

pub const Image = core.Image;

pub const FillRule = core.FillRule;
pub const SubpixelOrder = core.SubpixelOrder;
pub const ColorEncoding = core.ColorEncoding;
pub const TargetEncoding = core.TargetEncoding;
pub const PixelFormat = core.PixelFormat;
pub const PixelRect = core.PixelRect;
pub const LinearResolve = core.LinearResolve;
pub const CoverageTransfer = core.CoverageTransfer;
pub const mvpToScenePixel = core.mvpToScenePixel;
pub const TargetSurface = core.TargetSurface;
pub const RasterOptions = core.RasterOptions;
pub const DrawState = core.DrawState;
pub const resolveRect = core.resolveRect;

pub const BackendKind = core.BackendKind;

pub const recordKey = core.recordKey;
pub const RecordKey = core.RecordKey;
pub const ns = core.ns;
pub const GlyphCurves = core.GlyphCurves;
pub const PagePool = core.PagePool;
pub const AtlasPage = core.AtlasPage;
pub const Atlas = core.Atlas;
pub const AtlasEntry = core.AtlasEntry;
pub const AtlasInsertError = core.AtlasInsertError;
pub const AutohintAnalysis = core.AutohintAnalysis;
pub const CompositeMode = core.CompositeMode;
pub const AtlasLayer = core.AtlasLayer;
pub const PaintRecordInfo = core.PaintRecordInfo;
pub const AtlasRecord = core.AtlasRecord;

pub const Shape = core.Shape;
pub const Override = core.Override;
pub const DrawSegment = core.DrawSegment;
pub const Binding = core.Binding;
pub const emit = core.emit;

pub const Instance = core.Instance;
pub const DecodedInstance = core.DecodedInstance;
pub const decodeInstance = core.decodeInstance;
pub const BindingTexels = core.BindingTexels;
pub const bindingTexels = core.bindingTexels;
pub const WORDS_PER_INSTANCE = core.WORDS_PER_INSTANCE;
pub const WORDS_PER_OVERRIDE = core.WORDS_PER_OVERRIDE;

pub const autohint = core.autohint;
pub const HintVm = core.HintVm;
pub const HintPpem = core.HintPpem;
pub const HintVmStats = core.HintVmStats;
pub const HintError = core.HintError;

pub const Path = core.Path;
pub const snap = core.snap;
pub const ThreadPool = core.ThreadPool;

// ── Renderer backends ──

pub const CpuRenderer = @import("render/backend/cpu/renderer.zig").CpuRenderer;
pub const InstanceProfileEntry = @import("render/backend/cpu/renderer.zig").InstanceProfileEntry;
pub const InstanceProfileBuf = @import("render/backend/cpu/renderer.zig").InstanceProfileBuf;
pub const Gl33Renderer = @import("render/backend/gl/state.zig").Gl33Renderer;
pub const Gl44Renderer = @import("render/backend/gl/state.zig").Gl44Renderer;
pub const Gles30Renderer = @import("render/backend/gles30/state.zig").Gles30Renderer;
pub const VulkanRenderer = @import("render/backend/vulkan/pipeline.zig").VulkanRenderer;
pub const VulkanContext = @import("render/backend/vulkan/types.zig").VulkanContext;

pub const CpuBackendCache = @import("render/backend/cpu/backend_cache.zig").CpuBackendCache;
pub const drawCpu = @import("render/backend/cpu/draw.zig").drawCpu;
pub const Gl33BackendCache = @import("render/backend/gl/backend_cache.zig").Gl33BackendCache;
pub const Gl44BackendCache = @import("render/backend/gl/backend_cache.zig").Gl44BackendCache;
pub const Gles30BackendCache = @import("render/backend/gl/backend_cache.zig").Gles30BackendCache;
pub const VulkanBackendCache = @import("render/backend/vulkan/backend_cache.zig").VulkanBackendCache;

// ── Custom-shader integration facade ──

pub const coverage = @import("coverage.zig");

test {
    _ = core;
    _ = @import("render/backend/range_allocator.zig");
    _ = @import("render/backend/cpu/backend_cache.zig");
    _ = @import("render/backend/cpu/draw.zig");
    _ = @import("render/backend/gl/backend_cache.zig");
    _ = @import("render/backend/vulkan/backend_cache.zig");
    _ = coverage;
}
