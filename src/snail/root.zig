//! snail public API.
//!
//! The public surface is made of explicit top-level declarations. Implementation
//! modules stay private unless they define an intentional public namespace such
//! as `coverage`.

const backend_kind = @import("backend_kind.zig");
const resource_key = @import("resource_key.zig");
const upload_common = @import("render/format/upload_common.zig");

const math = @import("math.zig");
pub const font = @import("font.zig");
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
pub const SourceRange = text.SourceRange;
pub const OpenTypeFeature = text.OpenTypeFeature;
pub const ShapeOptions = text.ShapeOptions;
pub const TextAtlas = text.TextAtlas;
pub const ShapedText = text.ShapedText;
pub const Cluster = text.Cluster;
pub const ClusterIterator = text.ClusterIterator;
pub const clusters = text.clusters;
pub const track = text.track;
pub const shiftBaseline = text.shiftBaseline;
pub const spaceWords = text.spaceWords;
pub const snapAdvances = text.snapAdvances;
pub const TextBlob = text.TextBlob;
pub const TextPlacement = text.TextPlacement;
pub const TextAppend = text.TextAppend;
pub const TextAppendResult = text.TextAppendResult;
pub const TrueTypeHintContext = text.TrueTypeHintContext;
pub const TrueTypeHintContextOptions = text.TrueTypeHintContextOptions;
pub const TrueTypeHintCacheFootprint = text.TrueTypeHintCacheFootprint;
pub const TrueTypeHintSizeKeyEntry = text.TrueTypeHintSizeKeyEntry;
pub const TrueTypeHintSizeKeyIterator = text.TrueTypeHintSizeKeyIterator;
pub const TrueTypeHintGlyphKeyEntry = text.TrueTypeHintGlyphKeyEntry;
pub const TrueTypeHintGlyphKeyIterator = text.TrueTypeHintGlyphKeyIterator;
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
pub const GlyphHintSnapshot = text.GlyphHintSnapshot;
pub const GlyphHintSnapshotBuilderOptions = text.GlyphHintSnapshotBuilderOptions;
pub const CellMetrics = text.CellMetrics;
pub const CellMetricsOptions = text.CellMetricsOptions;
pub const TextCellGrid = text.TextCellGrid;
pub const TextCellGridOptions = text.TextCellGridOptions;
pub const Decoration = text.Decoration;
pub const ScriptTransform = text.ScriptTransform;
pub const ItemizedRun = text.ItemizedRun;
pub const TextBlobBundle = text.TextBlobBundle;
pub const BlobInProgress = text.BlobInProgress;
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
pub const mapPaintToLocal = paint.mapToLocal;
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
pub const Gles30Renderer = render.Gles30Renderer;
pub const VulkanRenderer = render.VulkanRenderer;

pub const Range = @import("range.zig").Range;
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

// --- New (rewrite) public surface. Coexists with the legacy types above
// until Phase 6 sweeps the old API out.
pub const recordKey = @import("record_key.zig");
pub const RecordKey = recordKey.RecordKey;
pub const GlyphCurves = @import("curves.zig").GlyphCurves;
pub const PagePool = @import("page_pool.zig").PagePool;
pub const AtlasPage = @import("page.zig").AtlasPage;
const atlas_mod_pub = @import("atlas.zig");
pub const Atlas = atlas_mod_pub.Atlas;
pub const AtlasEntry = atlas_mod_pub.Entry;
pub const CompositeMode = atlas_mod_pub.CompositeMode;
pub const AtlasLayer = atlas_mod_pub.Layer;
pub const AtlasRecord = @import("atlas_record.zig").AtlasRecord;
pub const PaintRecordInfo = atlas_mod_pub.PaintRecordInfo;
pub const Shape = @import("shape.zig").Shape;
pub const Override2 = @import("shape.zig").Override;
pub const Picture = @import("picture.zig").Picture;
pub const DrawSegment = @import("draw_records.zig").DrawSegment;
pub const Binding = @import("draw_records.zig").Binding;
pub const emit = @import("emit.zig");
pub const shapedRunPicture = @import("text_picture.zig").shapedRunPicture;
pub const hintedShapedRunPicture = @import("text_picture.zig").hintedShapedRunPicture;
pub const Hinter = @import("hinter.zig").Hinter;
pub const HintPpem = @import("hinter.zig").HintPpem;
pub const CpuPreparedPages = @import("render/backend/cpu/prepared_pages.zig").CpuPreparedPages;
pub const drawCpu = @import("render/backend/cpu/draw.zig").drawCpu;
pub const Gl33PreparedPages = @import("render/backend/gl/prepared_pages.zig").Gl33PreparedPages;
pub const Gl44PreparedPages = @import("render/backend/gl/prepared_pages.zig").Gl44PreparedPages;
pub const Gles30PreparedPages = @import("render/backend/gl/prepared_pages.zig").Gles30PreparedPages;
pub const VulkanPreparedPages = @import("render/backend/vulkan/prepared_pages.zig").VulkanPreparedPages;
pub const VulkanPreparedPagesPipelineShape = @import("render/backend/vulkan/prepared_pages.zig").PipelineShape;
pub const paths = @import("paths.zig");
pub const ns = recordKey.ns;

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
    _ = @import("record_key.zig");
    _ = @import("curves.zig");
    _ = @import("atlas_record.zig");
    _ = @import("page.zig");
    _ = @import("page_pool.zig");
    _ = @import("atlas.zig");
    _ = @import("paths.zig");
    _ = @import("hinter.zig");
    _ = @import("shape.zig");
    _ = @import("picture.zig");
    _ = @import("draw_records.zig");
    _ = @import("emit.zig");
    _ = @import("render/backend/cpu/prepared_pages.zig");
    _ = @import("render/backend/cpu/draw.zig");
    _ = @import("render/backend/gl/prepared_pages.zig");
    _ = @import("render/backend/vulkan/prepared_pages.zig");
    _ = @import("text_picture.zig");
    _ = @import("paths.zig");
}
