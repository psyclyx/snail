const atlas_mod = @import("text/atlas.zig");
const batch_mod = @import("text/batch.zig");
const blob_mod = @import("text/blob.zig");
const config_mod = @import("text/config.zig");
const hint_context_mod = @import("text/hint_context.zig");
const hint_plan_mod = @import("text/hint_plan.zig");
const tt_hint_mod = @import("text/tt_hint.zig");
const text_hint_format = @import("render/format/text_hint.zig");
const types_mod = @import("text/types.zig");

pub const FaceSpec = config_mod.FaceSpec;
pub const FaceIndex = config_mod.FaceIndex;
pub const ItemizedRun = config_mod.ItemizedRun;
pub const FontWeight = config_mod.FontWeight;
pub const FontStyle = config_mod.FontStyle;
pub const SyntheticStyle = config_mod.SyntheticStyle;
pub const isRenderableTextCodepoint = config_mod.isRenderableTextCodepoint;

pub const TextAtlas = atlas_mod.TextAtlas;
pub const TextBatch = batch_mod.TextBatch;
pub const ShapedText = types_mod.ShapedText;
pub const TextBlob = blob_mod.TextBlob;
pub const TextPlacement = types_mod.TextPlacement;
pub const TextAppend = types_mod.TextAppend;
pub const TextAppendResult = types_mod.TextAppendResult;
pub const TextBatchAppend = types_mod.TextBatchAppend;
pub const TextBlobBuilder = blob_mod.TextBlobBuilder;
pub const TrueTypeHintContext = hint_context_mod.TrueTypeHintContext;
pub const TrueTypeHintGlyphKey = hint_context_mod.HintGlyphKey;
pub const TrueTypeHintReject = hint_context_mod.HintReject;
pub const TrueTypeHintRejectReason = hint_context_mod.HintRejectReason;
pub const TrueTypeHintedGlyph = hint_context_mod.HintedGlyphValue;
pub const TrueTypeHintRunKeys = hint_context_mod.HintRunKeys;
pub const TrueTypeHintRunAvailability = hint_context_mod.HintRunAvailability;
pub const TextHintRunPlan = hint_plan_mod.TextHintRunPlan;
pub const HintedPlacement = hint_plan_mod.HintedPlacement;
pub const HintPlanStats = hint_plan_mod.HintPlanStats;
pub const TextHintPlanOptions = hint_plan_mod.PlanRunOptions;
pub const TextHintUploadOp = text_hint_format.UploadOp;
pub const TextHintGlyphRecord = text_hint_format.GlyphRecord;
pub const TextHintHandle = text_hint_format.HintHandle;
pub const TrueTypeHintMachine = tt_hint_mod.HintMachine;
pub const TrueTypeGlyphHint = tt_hint_mod.GlyphHint;
pub const TrueTypeGlyphHintOptions = tt_hint_mod.GlyphHintOptions;
pub const TrueTypeExecutedGlyph = tt_hint_mod.ExecutedGlyph;
pub const TrueTypeHintPpem = tt_hint_mod.HintPpem;
pub const TrueTypeBaseGlyphHint = tt_hint_mod.BaseGlyph;
pub const TrueTypeGlyphTopologyCache = tt_hint_mod.GlyphTopologyCache;
pub const CellMetrics = types_mod.CellMetrics;
pub const CellMetricsOptions = types_mod.CellMetricsOptions;
pub const Decoration = types_mod.Decoration;
pub const ScriptTransform = types_mod.ScriptTransform;

pub const TEXT_WORDS_PER_VERTEX = batch_mod.WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = batch_mod.VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = batch_mod.WORDS_PER_GLYPH;

pub const appendTextDrawIntoBatch = batch_mod.appendTextDrawIntoBatch;
pub const textBlobRangeGpuInstanceBudget = blob_mod.textBlobRangeGpuInstanceBudget;
pub const gatherTrueTypeHintRunKeys = hint_context_mod.gatherRunKeys;
pub const planHintedRun = hint_plan_mod.planRun;

test {
    _ = @import("text/tests.zig");
}
