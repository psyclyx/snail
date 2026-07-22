//! Snail: CPU-side vector preparation and embeddable shader contracts.
//!
//! Font parsing, shaping, geometry, atlases, upload plans, emitted draw records,
//! and entry-point-free shader fragments live here. Snail owns no GPU objects or
//! command submission. The complete CPU renderer is the separate, optional
//! `snail-raster` module and consumes only this public API.
//!
//! Color contract: every `[4]f32` color crossing this API is LINEAR light
//! with straight alpha, and fragment output is premultiplied linear — snail
//! never interprets host colors. sRGB-authoring hosts convert once at the
//! boundary with the `color` helpers.

const math = @import("math.zig");
const text_mod = @import("text.zig");
const image_mod = @import("image.zig");
const paint_mod = @import("paint.zig");
const record_key_mod = @import("atlas/record_key.zig");

pub const font = @import("font.zig");

// ── Math + geometry ──

/// Boundary conversions for sRGB-authoring hosts (`srgbToLinearColor`,
/// `linearToSrgbColor`, and the scalar transfer functions).
pub const color = @import("color.zig");

pub const Mat4 = math.Mat4;
pub const Vec2 = math.Vec2;
pub const BBox = math.BBox;
pub const Transform2D = math.Transform2D;
pub const Rect = math.Rect;
pub const mvpToScenePixel = math.mvpToScenePixel;

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

const run_placement = @import("text/run_placement.zig");
pub const HintMode = run_placement.HintMode;
pub const RunSnap = run_placement.RunSnap;
pub const YAxis = run_placement.YAxis;
pub const RunPlacement = run_placement.RunPlacement;
pub const PlaceRunError = run_placement.PlaceRunError;
pub const PlaceRunAllocError = run_placement.PlaceRunAllocError;
pub const placedRunShapeCount = run_placement.placedRunShapeCount;
pub const placeRun = run_placement.placeRun;
pub const placeRunAlloc = run_placement.placeRunAlloc;

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
pub const FillRule = paint_mod.FillRule;

pub const Image = image_mod.Image;

// ── Record keys / atlas ──

pub const record_key = record_key_mod;

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
pub const OwnedAtlasUploadPlanner = atlas_upload.OwnedPlanner;
pub const AtlasEntry = atlas_mod.Entry;
pub const AtlasInsertError = atlas_mod.InsertError;
pub const AutohintAnalysis = atlas_mod.AutohintAnalysis;
pub const CompositeMode = atlas_mod.CompositeMode;
pub const AtlasLayer = atlas_mod.Layer;
pub const PaintRecordInfo = atlas_mod.PaintRecordInfo;
pub const PaintImageRecord = atlas_mod.PaintImageRecord;
pub const AtlasRecord = @import("atlas/record.zig").AtlasRecord;
pub const RecordFilter = atlas_mod.RecordFilter;

const atlas_populate = @import("atlas/populate.zig");
pub const UnhintedRunOptions = atlas_populate.UnhintedRunOptions;
pub const ColrHandling = atlas_populate.ColrHandling;
pub const recordUnhintedRun = atlas_populate.recordUnhintedRun;
pub const recordAutohintRun = atlas_populate.recordAutohintRun;
pub const recordTtHintRun = atlas_populate.recordTtHintRun;
pub const recordTtAdvanceRun = atlas_populate.recordTtAdvanceRun;
pub const TtAdvanceSource = atlas_populate.TtAdvanceSource;

const shape_mod = @import("draw/shape.zig");
pub const Shape = shape_mod.Shape;

pub const emit = @import("draw/emit.zig");

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

pub const TtHintVm = @import("font/tt_hint_vm.zig").TtHintVm;
pub const TtHintPpem = @import("font/tt_hint_vm.zig").TtHintPpem;
pub const TtHintVmStats = @import("font/tt_hint_vm.zig").TtHintVmStats;
pub const TtHintError = @import("font/tt_hint_vm.zig").TtHintError;

pub const Path = @import("path.zig").Path;
pub const PreparedPath = @import("path.zig").PreparedPath;
pub const snap = @import("snap.zig");

/// Stable byte-layout contract for caller-owned renderers.
pub const render = @import("render.zig");

/// Shader surface. `glsl` is the hand-written, entry-point-free GLSL
/// fragment catalog — the behavioral spec and the composition surface for
/// GL hosts that inject snail's coverage math into their own shaders. The
/// complete per-target catalog produced from the native-Slang sources
/// (`shader/slang/`) lives in the separate `snail-shaders` module
/// (`@import("snail_shaders")`), generated at build time — so consumers of
/// `snail` alone never need the Slang toolchain.
pub const shader = struct {
    pub const glsl = @import("shader/glsl.zig");
};

test {
    _ = math;
    _ = color;
    _ = font;
    _ = text_mod;
    _ = image_mod;
    _ = paint_mod;
    _ = record_key_mod;
    _ = @import("atlas/curves.zig");
    _ = @import("atlas/record.zig");
    _ = @import("atlas/page.zig");
    _ = @import("atlas/page_pool.zig");
    _ = @import("atlas/upload_plan.zig");
    _ = atlas_populate;
    _ = atlas_mod;
    _ = @import("path.zig");
    _ = @import("path_pack.zig");
    _ = @import("font/tt_hint_vm.zig");
    _ = @import("font/autohint/policy.zig");
    _ = @import("font/autohint/analysis.zig");
    _ = @import("font/autohint/warp.zig");
    _ = @import("font/autohint/blue.zig");
    _ = @import("font/autohint/producer.zig");
    _ = @import("format/autohint_record.zig");
    _ = @import("format/abi.zig");
    _ = @import("text/faces.zig");
    _ = @import("text/run_placement.zig");
    _ = shape_mod;
    _ = @import("draw/records.zig");
    _ = @import("draw/emit.zig");
    _ = @import("snap.zig");
    _ = @import("util/hamt.zig");
    _ = render;
    _ = shader;
    _ = shader.glsl;
}
