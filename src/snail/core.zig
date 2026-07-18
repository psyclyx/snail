//! snail core: backend-independent primitives.
//!
//! This is the root of the `snail_core` compiler module — font parsing,
//! shaping, autohinting, the atlas, geometry, paint, the GPU byte-layout
//! ABI, and the emit path. It knows nothing about any concrete renderer
//! backend; backends (`cpu`/`gl`/`vulkan`) and the `snail` facade both
//! depend on it, never the reverse.
//!
//! `root.zig` re-exports this whole surface as the public `snail` API and adds
//! the CPU renderer plus backend shader/include namespaces.

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

const run_placement = @import("text/run_placement.zig");
pub const HintMode = run_placement.HintMode;
pub const RunSnap = run_placement.RunSnap;
pub const RunPlacement = run_placement.RunPlacement;
pub const PlaceRunError = run_placement.PlaceRunError;
pub const PlaceRunAllocError = run_placement.PlaceRunAllocError;
pub const placedRunShapeCount = run_placement.placedRunShapeCount;
pub const placeRun = run_placement.placeRun;
pub const placeRunAlloc = run_placement.placeRunAlloc;

pub const HintedGlyphCache = @import("text/hinted_glyph_cache.zig").HintedGlyphCache;
pub const UnhintedGlyphCache = @import("text/unhinted_glyph_cache.zig").UnhintedGlyphCache;

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
pub const PixelFormat = target.PixelFormat;
pub const PixelRect = target.PixelRect;
pub const LinearResolve = target.LinearResolve;
pub const CoverageTransfer = target.CoverageTransfer;
pub const mvpToScenePixel = target.mvpToScenePixel;
pub const TargetSurface = target.TargetSurface;
pub const RasterOptions = target.RasterOptions;
pub const DrawState = target.DrawState;
pub const resolveRect = target.resolveRect;

pub const BackendKind = backend_kind.BackendKind;

// ── Record keys / atlas ──

pub const recordKey = record_key_mod;
pub const RecordKey = record_key_mod.RecordKey;
pub const ns = record_key_mod.ns;

pub const GlyphCurves = @import("atlas/curves.zig").GlyphCurves;
pub const PagePool = @import("atlas/page_pool.zig").PagePool;
pub const AtlasPage = @import("atlas/page.zig").AtlasPage;

const atlas_mod = @import("atlas.zig");
pub const Atlas = atlas_mod.Atlas;
/// Backend-neutral atlas upload descriptions and the optional fixed-capacity
/// placement planner. The complete contract is public so callers never need
/// to reach through the internal `files` namespace for its backing types.
pub const atlas_upload = @import("atlas/upload_plan.zig");
pub const AtlasUploadPlanner = atlas_upload.Planner;
pub const AtlasEntry = atlas_mod.Entry;
pub const AtlasInsertError = atlas_mod.InsertError;
pub const AutohintAnalysis = atlas_mod.AutohintAnalysis;
pub const CompositeMode = atlas_mod.CompositeMode;
pub const AtlasLayer = atlas_mod.Layer;
pub const PaintRecordInfo = atlas_mod.PaintRecordInfo;
pub const PaintImageRecord = atlas_mod.PaintImageRecord;
pub const AtlasRecord = @import("atlas/record.zig").AtlasRecord;

const shape_mod = @import("picture/shape.zig");
pub const Shape = shape_mod.Shape;

pub const DrawSegment = @import("picture/draw_records.zig").DrawSegment;
pub const Binding = @import("picture/draw_records.zig").Binding;
pub const emit = @import("picture/emit.zig");

// ── GPU byte-layout ABI (custom-shader primitives) ──
//
// Symbolic decoders + texel-coord resolvers so callers can drive their
// own shader pipeline off the same byte layout the built-in renderers
// consume. The higher-level, per-backend integration surface lives in
// `snail.coverage` (facade); these raw primitives sit one layer beneath.

const vertex_mod = @import("format/vertex.zig");
pub const Instance = vertex_mod.Instance;
pub const DecodedInstance = vertex_mod.DecodedInstance;
pub const decodeInstance = vertex_mod.decodeInstance;
pub const BindingTexels = vertex_mod.BindingTexels;
pub const bindingTexels = vertex_mod.bindingTexels;
pub const WORDS_PER_INSTANCE = vertex_mod.WORDS_PER_INSTANCE;

pub const autohint = struct {
    pub const policy = @import("font/autohint/policy.zig");
    pub const AutohintPolicy = policy.AutohintPolicy;
    pub const Fade = policy.Fade;
    pub const analysis = @import("font/autohint/analysis.zig");
    pub const warp = @import("font/autohint/warp.zig");
    pub const blue = @import("font/autohint/blue.zig");
    pub const producer = @import("font/autohint/producer.zig");
    pub const AutohintAnalyzer = producer.AutohintAnalyzer;
    pub const GlyphFeatures = producer.GlyphFeatures;
    pub const FontFeatures = producer.FontFeatures;
    pub const FeatureEdge = analysis.FeatureEdge;
};

pub const HintVm = @import("font/hint_vm.zig").HintVm;
pub const HintPpem = @import("font/hint_vm.zig").HintPpem;
pub const HintVmStats = @import("font/hint_vm.zig").HintVmStats;
pub const HintError = @import("font/hint_vm.zig").HintError;

pub const Path = @import("path.zig").Path;
pub const PreparedPath = @import("path.zig").PreparedPath;
pub const snap = @import("snap.zig");

/// Stable byte-layout and policy contract for caller-owned renderers.
pub const render = @import("render.zig");

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
    _ = @import("atlas/upload_plan.zig");
    _ = atlas_mod;
    _ = @import("path.zig");
    _ = @import("paths.zig");
    _ = @import("font/hint_vm.zig");
    _ = @import("font/autohint/policy.zig");
    _ = @import("font/autohint/analysis.zig");
    _ = @import("font/autohint/warp.zig");
    _ = @import("font/autohint/blue.zig");
    _ = @import("font/autohint/producer.zig");
    _ = @import("format/autohint_record.zig");
    _ = @import("format/abi.zig");
    _ = @import("text/faces.zig");
    _ = @import("text/run_placement.zig");
    _ = @import("text/hinted_glyph_cache.zig");
    _ = @import("text/unhinted_glyph_cache.zig");
    _ = shape_mod;
    _ = @import("picture/draw_records.zig");
    _ = @import("picture/emit.zig");
    _ = @import("snap.zig");
    _ = @import("util/hamt.zig");
}
