//! snail public API.
//!
//! Thin packaging shell over the compiler-module graph: it re-exports the
//! backend-free `snail_core` API flat (Fonts/shaping/emit/…) and exposes each
//! backend as a namespace (`snail.core`, `snail.gl`, `snail.vulkan`,
//! `snail.cpu`). It holds no backend-specific code and no cross-backend
//! aggregation — an app picks the backend namespace(s) it needs (a
//! multi-backend app dispatches at its own level). The per-backend embeddable
//! coverage surface lives under `snail.gl.embeddable` / `snail.vulkan`.

pub const core = @import("snail_core");

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
pub const atlas_upload = core.atlas_upload;
pub const AtlasUploadPlanner = core.AtlasUploadPlanner;

pub const Shape = core.Shape;
pub const DrawSegment = core.DrawSegment;
pub const Binding = core.Binding;
pub const emit = core.emit;

pub const Instance = core.Instance;
pub const DecodedInstance = core.DecodedInstance;
pub const decodeInstance = core.decodeInstance;
pub const BindingTexels = core.BindingTexels;
pub const bindingTexels = core.bindingTexels;
pub const WORDS_PER_INSTANCE = core.WORDS_PER_INSTANCE;

pub const autohint = core.autohint;
pub const HintVm = core.HintVm;
pub const HintPpem = core.HintPpem;
pub const HintVmStats = core.HintVmStats;
pub const HintError = core.HintError;

pub const Path = core.Path;
pub const PreparedPath = core.PreparedPath;
pub const snap = core.snap;
pub const ThreadPool = core.ThreadPool;

// ── Renderer backends (each a separate compiler module, exposed as a
//    namespace; the per-backend embeddable coverage surface lives under
//    `gl.embeddable` / `vulkan.embeddable`) ──

pub const cpu = @import("snail_cpu");
pub const gl = @import("snail_gl");
pub const vulkan = @import("snail_vulkan");

pub const CpuRenderer = cpu.CpuRenderer;
pub const InstanceProfileEntry = cpu.InstanceProfileEntry;
pub const InstanceProfileBuf = cpu.InstanceProfileBuf;
pub const CpuBackendCache = cpu.CpuBackendCache;
pub const drawCpu = cpu.drawCpu;

// The all-in-one GL renderer + atlas cache are the caller's (embeddable-only);
// the reference implementation lives in `src/demo/embed_gl*.zig`. snail exposes
// only the GL contract + shaders under `snail.gl`.

test {
    _ = core;
    _ = cpu;
    _ = gl;
    _ = vulkan;
}
