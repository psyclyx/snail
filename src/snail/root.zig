//! snail public API.
//!
//! The public surface is made of explicit top-level declarations. Implementation
//! modules stay private unless they define an intentional public namespace such
//! as `coverage`.

const backend_kind = @import("backend_kind.zig");
const resource_key = @import("resource_key.zig");
const upload_common = @import("render/format/upload_common.zig");

const math = @import("math.zig");
const font = @import("font.zig");
const text = @import("text.zig");
const image = @import("image.zig");
const path = @import("path.zig");
const scene = @import("scene.zig");
const resources = @import("resources.zig");
const upload = @import("upload.zig");
const draw = @import("draw.zig");
const render = @import("render.zig");
pub const coverage = @import("coverage.zig");
const target = @import("target.zig");
const paint = @import("paint.zig");

pub const Mat4 = math.Mat4;
pub const Vec2 = math.Vec2;
pub const BBox = math.BBox;
pub const Transform2D = math.Transform2D;
pub const Rect = target.Rect;

pub const GlyphMetrics = font.GlyphMetrics;
pub const LineMetrics = font.LineMetrics;
pub const DecorationMetrics = font.DecorationMetrics;
pub const ScriptMetrics = font.ScriptMetrics;
pub const FaceIndex = text.FaceIndex;
pub const TextAtlas = text.TextAtlas;
pub const ShapedText = text.ShapedText;
pub const TextBlob = text.TextBlob;
pub const TextPlacement = text.TextPlacement;
pub const TextAppend = text.TextAppend;
pub const TextAppendResult = text.TextAppendResult;
pub const TrueTypeHintContext = text.TrueTypeHintContext;
pub const TrueTypeHintGlyphKey = text.TrueTypeHintGlyphKey;
pub const TrueTypeHintReject = text.TrueTypeHintReject;
pub const TrueTypeHintRejectReason = text.TrueTypeHintRejectReason;
pub const TrueTypeHintedGlyph = text.TrueTypeHintedGlyph;
pub const TrueTypePreparedHintGlyph = text.TrueTypePreparedHintGlyph;
pub const TrueTypePreparedHintRun = text.TrueTypePreparedHintRun;
pub const TrueTypeHintRunStats = text.TrueTypeHintRunStats;
pub const TrueTypeHintPrepareRunOptions = text.TrueTypeHintPrepareRunOptions;
pub const TextHintGlyphRecord = text.TextHintGlyphRecord;
pub const TrueTypeHintMachine = text.TrueTypeHintMachine;
pub const TrueTypeGlyphHint = text.TrueTypeGlyphHint;
pub const TrueTypeGlyphHintPatch = text.TrueTypeGlyphHintPatch;
pub const TrueTypeExecutedGlyph = text.TrueTypeExecutedGlyph;
pub const TrueTypeHintPpem = text.TrueTypeHintPpem;
pub const TrueTypeBaseGlyphHint = text.TrueTypeBaseGlyphHint;
pub const TrueTypeGlyphTopologyCache = text.TrueTypeGlyphTopologyCache;
pub const CellMetrics = text.CellMetrics;
pub const CellMetricsOptions = text.CellMetricsOptions;
pub const TextCellGrid = text.TextCellGrid;
pub const TextCellGridOptions = text.TextCellGridOptions;
pub const Decoration = text.Decoration;
pub const ScriptTransform = text.ScriptTransform;
pub const ItemizedRun = text.ItemizedRun;
pub const TextBlobBuilder = text.TextBlobBuilder;
pub const FaceSpec = text.FaceSpec;
pub const FontWeight = text.FontWeight;
pub const FontStyle = text.FontStyle;
pub const SyntheticStyle = text.SyntheticStyle;
pub const MissingGlyphReplacement = text.MissingGlyphReplacement;
pub const Font = font.Font;
pub const tt = font.tt;
pub const TextBatch = text.TextBatch;
pub const TEXT_WORDS_PER_VERTEX = text.TEXT_WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = text.TEXT_VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = text.TEXT_WORDS_PER_GLYPH;
pub const isRenderableTextCodepoint = text.isRenderableTextCodepoint;
pub const patchTrueTypeGlyphHint = text.patchTrueTypeGlyphHint;

pub const PaintExtend = paint.Extend;
pub const ImageFilter = paint.ImageFilter;
pub const LinearGradient = paint.LinearGradient;
pub const RadialGradient = paint.RadialGradient;
pub const ImagePaint = paint.ImagePaint;
pub const Paint = paint.Paint;
pub const FillStyle = paint.FillStyle;
pub const StrokeCap = paint.StrokeCap;
pub const StrokeJoin = paint.StrokeJoin;
pub const StrokePlacement = paint.StrokePlacement;
pub const StrokeStyle = paint.StrokeStyle;
pub const Image = image.Image;

pub const Path = path.Path;
pub const PathPicture = path.PathPicture;
pub const PathPictureBuilder = path.PathPictureBuilder;
pub const PATH_WORDS_PER_VERTEX = path.PATH_WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = path.PATH_VERTICES_PER_SHAPE;
pub const PATH_WORDS_PER_SHAPE = path.PATH_WORDS_PER_SHAPE;
pub const PathPictureDebugView = path.PathPictureDebugView;
pub const PathPictureBoundsOverlayOptions = path.PathPictureBoundsOverlayOptions;

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
pub const TargetSurface = target.TargetSurface;
pub const RasterOptions = target.RasterOptions;
pub const DrawState = target.DrawState;
pub const DrawPass = target.DrawPass;
pub const resolveRect = target.resolveRect;

pub const BackendKind = backend_kind.BackendKind;
pub const VulkanContext = render.VulkanContext;
pub const CpuRenderer = render.CpuRenderer;
pub const ThreadPool = render.ThreadPool;
pub const Renderer = render.Renderer;
pub const Gl33Renderer = render.Gl33Renderer;
pub const Gl44Renderer = render.Gl44Renderer;
pub const Gles3Renderer = render.Gles3Renderer;
pub const VulkanRenderer = render.VulkanRenderer;

pub const Range = scene.Range;
pub const Override = scene.Override;
pub const TextResourceKeys = scene.TextResourceKeys;
pub const PathDraw = scene.PathDraw;
pub const TextDraw = scene.TextDraw;
pub const Scene = scene.Scene;

pub const ResourceStamp = resource_key.ResourceStamp;
pub const ResourceKey = resource_key.ResourceKey;
pub const ResourceManifest = resources.ResourceManifest;
pub const PreparedResources = resources.PreparedResources;
pub const PreparedResourceRetirementQueue = resources.PreparedResourceRetirementQueue;
pub const ResourceCapacityMode = upload_common.AtlasCapacityMode;
pub const ResourceFootprint = resources.ResourceFootprint;
pub const ResourceCacheStats = upload.ResourceCacheStats;
pub const UploadAllocators = upload.UploadAllocators;
pub const ResourceUploadPlan = upload.ResourceUploadPlan;
pub const PendingResourceUpload = upload.PendingResourceUpload;

pub const DrawList = draw.DrawList;
pub const PreparedScene = draw.PreparedScene;

/// Default ASCII printable character set (space through tilde).
pub const ASCII_PRINTABLE = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

test {
    _ = math;
    _ = font;
    _ = text;
    _ = image;
    _ = path;
    _ = scene;
    _ = resources;
    _ = upload;
    _ = draw;
    _ = render;
    _ = coverage;
    _ = target;
    _ = paint;
    _ = @import("api_tests.zig");
    _ = @import("path_picture_tests.zig");
}
