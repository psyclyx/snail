//! snail public API.
//!
//! The public surface is organized into explicit domains. Top-level aliases
//! re-export the same canonical declarations from those domain modules.

const build_options = @import("build_options");
const backend_kind = @import("backend_kind.zig");
const resource_key = @import("resource_key.zig");
const upload_common = @import("renderer/upload_common.zig");

pub const math = @import("math.zig");
pub const text = @import("text.zig");
pub const image = @import("image.zig");
pub const path = @import("path.zig");
pub const scene = @import("scene.zig");
pub const resources = @import("resources.zig");
pub const upload = @import("upload.zig");
pub const draw = @import("draw.zig");
pub const render = @import("render.zig");
pub const coverage = @import("coverage.zig");
pub const target = @import("target.zig");
pub const paint = @import("paint.zig");

const lowlevel_impl = @import("lowlevel.zig");

pub const Mat4 = math.Mat4;
pub const Vec2 = math.Vec2;
pub const BBox = math.BBox;
pub const Transform2D = math.Transform2D;
pub const Rect = target.Rect;

pub const GlyphMetrics = text.GlyphMetrics;
pub const LineMetrics = text.LineMetrics;
pub const DecorationMetrics = text.DecorationMetrics;
pub const ScriptMetrics = text.ScriptMetrics;
pub const TextAtlas = text.TextAtlas;
pub const ShapedText = text.ShapedText;
pub const TextBlob = text.TextBlob;
pub const TextPlacement = text.TextPlacement;
pub const TextAppend = text.TextAppend;
pub const TextAppendResult = text.TextAppendResult;
pub const CellMetrics = text.CellMetrics;
pub const CellMetricsOptions = text.CellMetricsOptions;
pub const TextBlobBuilder = text.TextBlobBuilder;
pub const FaceSpec = text.FaceSpec;
pub const FontWeight = text.FontWeight;
pub const FontStyle = text.FontStyle;
pub const SyntheticStyle = text.SyntheticStyle;
pub const Font = text.Font;
pub const isRenderableTextCodepoint = text.isRenderableTextCodepoint;

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

pub const FillRule = target.FillRule;
pub const SubpixelOrder = target.SubpixelOrder;
pub const ColorEncoding = target.ColorEncoding;
pub const TargetEncoding = target.TargetEncoding;
pub const PixelRect = target.PixelRect;
pub const ResolveRegion = target.ResolveRegion;
pub const ResolveBackdrop = target.ResolveBackdrop;
pub const IntermediateFormat = target.IntermediateFormat;
pub const DirectResolve = target.DirectResolve;
pub const LinearResolve = target.LinearResolve;
pub const Resolve = target.Resolve;
pub const CoverageTransfer = target.CoverageTransfer;
pub const PixelGrid = target.PixelGrid;
pub const ResolveTarget = target.ResolveTarget;
pub const TargetStamp = target.TargetStamp;

pub const BackendKind = backend_kind.BackendKind;
pub const VulkanContext = render.VulkanContext;
pub const CpuRenderer = render.CpuRenderer;
pub const ThreadPool = render.ThreadPool;
pub const Renderer = render.Renderer;
pub const GlRenderer = render.GlRenderer;
pub const VulkanRenderer = render.VulkanRenderer;

pub const Range = scene.Range;
pub const Override = scene.Override;
pub const PathDraw = scene.PathDraw;
pub const TextDraw = scene.TextDraw;
pub const Scene = scene.Scene;

pub const ResourceStamp = resource_key.ResourceStamp;
pub const ResourceKey = resource_key.ResourceKey;
pub const ResourceSet = resources.ResourceSet;
pub const PreparedResources = resources.PreparedResources;
pub const PreparedResourceRetirementQueue = resources.PreparedResourceRetirementQueue;
pub const ResourceCapacityMode = upload_common.AtlasCapacityMode;
pub const ResourceFootprint = upload.ResourceFootprint;
pub const UploadAllocators = upload.UploadAllocators;
pub const ResourceUploadPlan = upload.ResourceUploadPlan;
pub const ResourceUploadCommand = upload.ResourceUploadCommand;
pub const ResourceUploadCompletion = upload.ResourceUploadCompletion;
pub const PendingResourceUpload = upload.PendingResourceUpload;
pub const curveAtlasFootprint = resources.curveAtlasFootprint;
pub const textAtlasUploadFootprint = resources.textAtlasUploadFootprint;

pub const DrawOptions = draw.DrawOptions;
pub const DrawSegment = draw.DrawSegment;
pub const DrawRecords = draw.DrawRecords;
pub const DrawList = draw.DrawList;
pub const PreparedScene = draw.PreparedScene;

/// Default ASCII printable character set (space through tilde).
pub const ASCII_PRINTABLE = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

/// Low-level building blocks. Most callers should prefer the canonical types
/// at the top level (`TextAtlas`, `Path`, `PathPicture`, `Renderer`, ...).
pub const lowlevel = struct {
    pub const bezier = @import("math/bezier.zig");
    pub const gl = if (build_options.enable_opengl) @import("renderer/gl_bindings.zig").gl else struct {};
    pub const curve_tex = @import("renderer/curve_texture.zig");
    pub const ttf = @import("font/ttf.zig");
    pub const vertex = @import("renderer/vertex.zig");

    pub const Font = text.Font;
    pub const CurveAtlas = lowlevel_impl.CurveAtlas;
    pub const Atlas = lowlevel_impl.Atlas;
    pub const AtlasPage = lowlevel_impl.AtlasPage;
    pub const PreparedAtlasView = lowlevel_impl.PreparedAtlasView;
    pub const PreparedTextAtlasView = lowlevel_impl.PreparedTextAtlasView;
    pub const PreparedLayerInfoUpload = lowlevel_impl.PreparedLayerInfoUpload;
    pub const PreparedLayerInfoView = lowlevel_impl.PreparedLayerInfoView;
    pub const PreparedImageView = lowlevel_impl.PreparedImageView;
    pub const curveAtlasFootprint = resources.curveAtlasFootprint;

    pub const TextBatch = lowlevel_impl.TextBatch;
    pub const PathBatch = path.PathBatch;

    pub const TEXT_WORDS_PER_VERTEX = lowlevel_impl.TEXT_WORDS_PER_VERTEX;
    pub const TEXT_VERTICES_PER_GLYPH = lowlevel_impl.TEXT_VERTICES_PER_GLYPH;
    pub const TEXT_WORDS_PER_GLYPH = lowlevel_impl.TEXT_WORDS_PER_GLYPH;
    pub const PATH_WORDS_PER_VERTEX = path.PATH_WORDS_PER_VERTEX;
    pub const PATH_VERTICES_PER_SHAPE = path.PATH_VERTICES_PER_SHAPE;
    pub const PATH_WORDS_PER_SHAPE = path.PATH_WORDS_PER_SHAPE;

    pub const TEXTURE_LAYER_WINDOW_SIZE = lowlevel_impl.TEXTURE_LAYER_WINDOW_SIZE;
    pub const textureLayerWindowBase = lowlevel_impl.textureLayerWindowBase;
    pub const textureLayerLocal = lowlevel_impl.textureLayerLocal;

    pub const PATH_PAINT_INFO_WIDTH = path.PATH_PAINT_INFO_WIDTH;
    pub const PATH_PAINT_TEXELS_PER_RECORD = path.PATH_PAINT_TEXELS_PER_RECORD;
    pub const PATH_PAINT_TAG_SOLID = path.PATH_PAINT_TAG_SOLID;
    pub const PATH_PAINT_TAG_LINEAR_GRADIENT = path.PATH_PAINT_TAG_LINEAR_GRADIENT;
    pub const PATH_PAINT_TAG_RADIAL_GRADIENT = path.PATH_PAINT_TAG_RADIAL_GRADIENT;
    pub const PATH_PAINT_TAG_IMAGE = path.PATH_PAINT_TAG_IMAGE;
    pub const PATH_PAINT_TAG_COMPOSITE_GROUP = path.PATH_PAINT_TAG_COMPOSITE_GROUP;

    pub const PathPictureDebugView = path.PathPictureDebugView;
    pub const PathPictureBoundsOverlayOptions = path.PathPictureBoundsOverlayOptions;
};

test {
    _ = math;
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
