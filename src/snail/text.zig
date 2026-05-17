const atlas_mod = @import("text/atlas.zig");
const batch_mod = @import("text/batch.zig");
const blob_mod = @import("text/blob.zig");
const config_mod = @import("text/config.zig");
const glyph_atlas_mod = @import("text/glyph_atlas.zig");
const types_mod = @import("text/types.zig");
const view_mod = @import("text/view.zig");

pub const FaceSpec = config_mod.FaceSpec;
pub const FaceIndex = config_mod.FaceIndex;
pub const ItemizedRun = config_mod.ItemizedRun;
pub const FontWeight = config_mod.FontWeight;
pub const FontStyle = config_mod.FontStyle;
pub const SyntheticStyle = config_mod.SyntheticStyle;
pub const FontConfig = config_mod.FontConfig;
pub const FaceConfig = config_mod.FaceConfig;
pub const FaceGlyphData = config_mod.FaceGlyphData;
pub const FaceView = view_mod.FaceView;
pub const glyph_atlas = glyph_atlas_mod;
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
pub const CellMetrics = types_mod.CellMetrics;
pub const CellMetricsOptions = types_mod.CellMetricsOptions;
pub const Decoration = types_mod.Decoration;
pub const ScriptTransform = types_mod.ScriptTransform;

pub const TEXT_WORDS_PER_VERTEX = batch_mod.WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = batch_mod.VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = batch_mod.WORDS_PER_GLYPH;

pub const appendTextDrawIntoBatch = batch_mod.appendTextDrawIntoBatch;
pub const textBlobRangeGpuInstanceBudget = blob_mod.textBlobRangeGpuInstanceBudget;

test {
    _ = @import("text/tests.zig");
}
